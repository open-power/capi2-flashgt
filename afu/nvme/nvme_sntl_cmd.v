// *!***************************************************************************
// *! Copyright 2019 International Business Machines
// *!
// *! Licensed under the Apache License, Version 2.0 (the "License");
// *! you may not use this file except in compliance with the License.
// *! You may obtain a copy of the License at
// *! http://www.apache.org/licenses/LICENSE-2.0 
// *!
// *! The patent license granted to you in Section 3 of the License, as applied
// *! to the "Work," hereby includes implementations of the Work in physical form. 
// *!
// *! Unless required by applicable law or agreed to in writing, the reference design
// *! distributed under the License is distributed on an "AS IS" BASIS,
// *! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// *! See the License for the specific language governing permissions and
// *! limitations under the License.
// *!***************************************************************************

`timescale 1 ns / 10 ps

//  *************************************************************************
//  File : nvme_sntl_cmd.v
//  *************************************************************************
//  *************************************************************************
//  Description : FlashGT+ - SCSI to NVMe Layer command processing
//                
//  *************************************************************************

module nvme_sntl_cmd#
  (// afu/psl   interface parameters
   parameter tag_width        = 8,
   parameter datalen_width    = 25,
   parameter data_width       = 128,
   parameter data_bytes       = data_width/8,
   parameter bytec_width      = $clog2(data_bytes+1),
   parameter beatid_width     = datalen_width-$clog2(data_bytes),    
   parameter lunid_width      = 64, 
   parameter cmd_width        = 4, 
   parameter fcstat_width     = 8, 
   parameter fcxstat_width    = 8, 
   parameter rsp_info_width   = 160,
   parameter tag_par_width    = (tag_width + 63)/64, 
   parameter lunid_par_width  = (lunid_width + 63)/64, 
   parameter data_par_width   = (data_width + 63) /64,
   parameter status_width     = 8, // event status
   parameter sisl_block_size  = 4096, // all namespaces are mapped to 4K blocks
   parameter sisl_block_width = $clog2(sisl_block_size-1), // number of bits to convert from bytes to blocks
   parameter maxxfer_width    = datalen_width-sisl_block_width,
   parameter lunidx_width     = 8, // support 255 LUNs max
   parameter wdata_max_req    = 4096,
   parameter wdatalen_width   = $clog2(wdata_max_req)+1,
   parameter cid_width        = 16,
   parameter cid_par_width    = 2,
   parameter trk_entries      = (1<<tag_width),
   parameter trk_awidth       = tag_width,
   parameter wbuf_numids      = 6,  // 4KB per id
   parameter wbufid_width     = $clog2(wbuf_numids),
   parameter wbufid_par_width = (wbufid_width+7)/8,
   parameter num_isq = 16,  // max number of I/O submissions queues
   parameter isq_idwidth = $clog2(num_isq+2)  // id 0,1 are used by microcode

  
   )
   (
   
    input                             reset,
    input                             clk, 

    //-------------------------------------------------------
    // sislite request interface
    //-------------------------------------------------------
   
    //  req_r    - ready
    //  req_v    - valid.  xfer occurs only if valid & ready, otherwise no xfer
    //  req_cmd  - command encode FCP_*
    //  req_tag  - identifier for the command
    //  req_lun  - logical unit number
    output reg                        i_req_r_out,
    input                             i_req_v_in,
    input             [cmd_width-1:0] i_req_cmd_in, 
    input             [tag_width-1:0] i_req_tag_in, 
    input         [tag_par_width-1:0] i_req_tag_par_in, 
    input           [lunid_width-1:0] i_req_lun_in, 
    input       [lunid_par_width-1:0] i_req_lun_par_in, 
    input         [datalen_width-1:0] i_req_length_in, 
    input                             i_req_length_par_in, 
    input                     [127:0] i_req_cdb_in, 
    input                       [1:0] i_req_cdb_par_in, 

    //-------------------------------------------------------
    // admin/microcode interface     
    //-------------------------------------------------------
    output reg                        cmd_admin_valid,
    input                             admin_cmd_ack,
    output reg        [cmd_width-1:0] cmd_admin_cmd, 
    output reg                 [15:0] cmd_admin_cid, 
    output                      [1:0] cmd_admin_cid_par, 
    output reg      [lunid_width-1:0] cmd_admin_lun, 
    output reg    [datalen_width-1:0] cmd_admin_length, 
    output reg                [127:0] cmd_admin_cdb,
    output reg                        cmd_admin_flush,

    //-------------------------------------------------------
    // sislite LUN to namespace info lookup
    //-------------------------------------------------------
    output reg                        cmd_admin_lunlu_valid,
    output reg     [lunidx_width-1:0] cmd_admin_lunlu_idx, // index into lun lookup table
    output reg                        cmd_admin_lunlu_idx_par,
    input                      [31:0] admin_cmd_lunlu_nsid, // namespace id.  1 cycle after valid
    input                       [7:0] admin_cmd_lunlu_lbads, // block size in bytes = 2**lbads
    input                      [63:0] admin_cmd_lunlu_numlba, // number of 4K blocks
    input                             admin_cmd_lunlu_status, // ACA status

    output reg                        cmd_admin_lunlu_setaca,
    output reg     [lunidx_width-1:0] cmd_admin_lunlu_setaca_idx,
   
    output reg                        cmd_admin_lunlu_clraca,
    output reg     [lunidx_width-1:0] cmd_admin_lunlu_clraca_idx,

    //-------------------------------------------------------
    // response interface
    //-------------------------------------------------------
    output reg                        cmd_rsp_v,
    output reg        [tag_width-1:0] cmd_rsp_tag,
    output reg                        cmd_rsp_tag_par,
    output reg     [fcstat_width-1:0] cmd_rsp_fc_status,
    output reg    [fcxstat_width-1:0] cmd_rsp_fcx_status,
    output reg                  [7:0] cmd_rsp_scsi_status,
    output reg                        cmd_rsp_sns_valid,
    output reg                        cmd_rsp_fcp_valid,
    output reg                        cmd_rsp_underrun,
    output reg                        cmd_rsp_overrun,
    output reg                 [31:0] cmd_rsp_resid,
    output reg     [beatid_width-1:0] cmd_rsp_beats,
    output reg   [rsp_info_width-1:0] cmd_rsp_info,
    input                             rsp_cmd_ack,

    //-------------------------------------------------------
    // sntl insert into ISQ
    //-------------------------------------------------------

    output reg                 [63:0] sntl_ioq_req_lba,
    output reg                 [15:0] sntl_ioq_req_numblks,
    output reg                 [31:0] sntl_ioq_req_nsid,
    output reg                  [7:0] sntl_ioq_req_opcode,
    output reg                 [15:0] sntl_ioq_req_cmdid,
    output reg     [wbufid_width-1:0] sntl_ioq_req_wbufid,
    output reg [wbufid_par_width-1:0] sntl_ioq_req_wbufid_par,
    output reg    [datalen_width-1:0] sntl_ioq_req_reloff,
    output reg                        sntl_ioq_req_fua,
    output reg      [isq_idwidth-1:0] sntl_ioq_req_sqid,
    output reg                        sntl_ioq_req_valid,
    input                             ioq_sntl_req_ack,

    // which IOSQ to use
    input                             ioq_sntl_sqid_valid, // there's a submission queue entry available
    input           [isq_idwidth-1:0] ioq_sntl_sqid, // id of the submission queue with fewest entries in use
    output reg                        sntl_ioq_sqid_ack,
    output reg      [isq_idwidth-1:0] sntl_ioq_sqid,
    
    //-------------------------------------------------------
    // sntl completions from ICQ
    //-------------------------------------------------------

    input                      [14:0] ioq_sntl_cpl_status,
    input                      [15:0] ioq_sntl_cpl_cmdid,
    input                       [1:0] ioq_sntl_cpl_cmdid_par,
    input                             ioq_sntl_cpl_valid,
    output reg                        sntl_ioq_cpl_ack,

   
    //-------------------------------------------------------
    // write buffer request
    //-------------------------------------------------------
    output reg                        cmd_wbuf_req_valid, // asserted when data transfer for a cid/wbufid is complete
    output reg        [cid_width-1:0] cmd_wbuf_req_cid,
    output reg    [cid_par_width-1:0] cmd_wbuf_req_cid_par,
    output reg    [datalen_width-1:0] cmd_wbuf_req_reloff, // offset from start address of this command  
    output reg     [wbufid_width-1:0] cmd_wbuf_req_wbufid,
    output reg [wbufid_par_width-1:0] cmd_wbuf_req_wbufid_par,
    output reg                 [63:0] cmd_wbuf_req_lba,
    output reg                 [15:0] cmd_wbuf_req_numblks,
    output reg                        cmd_wbuf_req_unmap,
    input                             wbuf_cmd_req_ready,

    //-------------------------------------------------------
    // write buffer status
    //-------------------------------------------------------
    input                             wbuf_cmd_status_valid, // asserted when data transfer for a cid/wbufid is complete
    input          [wbufid_width-1:0] wbuf_cmd_status_wbufid,
    input      [wbufid_par_width-1:0] wbuf_cmd_status_wbufid_par,
    input             [cid_width-1:0] wbuf_cmd_status_cid,
    input         [cid_par_width-1:0] wbuf_cmd_status_cid_par, 
    input                             wbuf_cmd_status_error, // 0 = data is in the buffer  1 = error, data is not valid
    output reg                        cmd_wbuf_status_ready,

    //-------------------------------------------------------
    // write buffer management
    //-------------------------------------------------------
    output reg                        cmd_wbuf_id_valid, // need wbufid
    input                             wbuf_cmd_id_ack, // wbufid granted
    input          [wbufid_width-1:0] wbuf_cmd_id_wbufid,
    input      [wbufid_par_width-1:0] wbuf_cmd_id_wbufid_par,
   
    output reg                        cmd_wbuf_idfree_valid, // done with with wbufid
    output reg     [wbufid_width-1:0] cmd_wbuf_idfree_wbufid, 
    output reg [wbufid_par_width-1:0] cmd_wbuf_idfree_wbufid_par,
   
    //-------------------------------------------------------
    // SCSI unmap command events
    //-------------------------------------------------------
    // to unmap module
    output reg                        cmd_unmap_req_valid,
    output reg                        cmd_unmap_cpl_valid,
    output reg        [cid_width-1:0] cmd_unmap_cid,
    output reg    [cid_par_width-1:0] cmd_unmap_cid_par, 
    output reg                 [14:0] cmd_unmap_cpl_status,
    output reg                        cmd_unmap_flush,
    output                            cmd_unmap_ioidle, /* no reads or writes in progress */
    // from unmap module
    input                             unmap_cmd_valid,
    input             [cid_width-1:0] unmap_cmd_cid,
    input         [cid_par_width-1:0] unmap_cmd_cid_par, 
    input                       [3:0] unmap_cmd_event, // 0=write wbuf  1=write wbuf last 2=cpl
    input          [wbufid_width-1:0] unmap_cmd_wbufid,
    input      [wbufid_par_width-1:0] unmap_cmd_wbufid_par,
    input                      [14:0] unmap_cmd_cpl_status,
    input                       [7:0] unmap_cmd_reloff, // lba range pointer (offset into wbuf)
    output reg                        cmd_unmap_ack, 
    
    //-------------------------------------------------------
    // sntl completions for admin commands
    //-------------------------------------------------------

    input                      [14:0] admin_cmd_cpl_status,
    input                      [15:0] admin_cmd_cpl_cmdid,
    input                       [1:0] admin_cmd_cpl_cmdid_par,
    input                      [31:0] admin_cmd_cpl_data,
    input         [datalen_width-1:0] admin_cmd_cpl_length,
    input                             admin_cmd_cpl_length_par,
    input                             admin_cmd_cpl_valid,
    output reg                        cmd_admin_cpl_ack,

    //-------------------------------------------------------
    // dma command tracking lookup
    //-------------------------------------------------------
    input                             dma_cmd_valid,
    output reg                        cmd_dma_ready,
    input             [cid_width-1:0] dma_cmd_cid,
    input         [cid_par_width-1:0] dma_cmd_cid_par,
    input                             dma_cmd_rnw,
    input         [datalen_width-1:0] dma_cmd_reloff,
    input        [wdatalen_width-1:0] dma_cmd_length, // length of transfer in bytes
    input                             dma_cmd_length_par, 

    output reg                        cmd_dma_valid,
    output reg                        cmd_dma_error,


    // track error status from on sisl write payload
    input                             dma_cmd_wdata_valid,
    input             [cid_width-1:0] dma_cmd_wdata_cid,
    input         [cid_par_width-1:0] dma_cmd_wdata_cid_par, 
    input                             dma_cmd_wdata_error,
    output reg                        cmd_dma_wdata_ready,

    //-------------------------------------------------------
    input                             ctl_xx_csts_rdy, // NVMe controller is ready (link up, controller enabled)
    input                             ctl_xx_ioq_enable, // NVMe init complete, IOQ enabled.
    input                             ctl_xx_shutdown, // controller is shutting down, return FC_RC=shutdown for new commands
    input                             ctl_xx_shutdown_cmp, // controller shutdown is completed.  terminate any commands not yet completed.

    output reg                        cmd_regs_lunreset, // lun reset in progress
   
    input                      [35:0] regs_xx_timer1, // us free running
    input                      [15:0] regs_xx_timer2, // 2^14 * us - timer stops when backpressured
    input                      [15:0] regs_cmd_IOtimeout2, // timeout for I/O commands

    input         [maxxfer_width-1:0] regs_xx_maxxfer, // max transfer size allowed (number of 4K blocks)
    input               [tag_width:0] regs_cmd_maxiowr, // number of writes outstanding
    input               [tag_width:0] regs_cmd_maxiord, // number of reads outstanding

    input                             regs_xx_freeze,
   
    //-------------------------------------------------------
    // debug
    input                             regs_cmd_trk_rd,
    input             [tag_width-1:0] regs_cmd_trk_addr,
    input                             regs_cmd_trk_addr_par,
    output reg                [511:0] cmd_regs_trk_data,
    output reg                        cmd_regs_trk_ack,
   
    output reg                 [31:0] cmd_regs_dbgcount,
    output reg                 [31:0] cmd_perf_events,
    output reg                        sntl_regs_cmd_idle,

    input                      [15:0] regs_cmd_debug,
    input                             regs_cmd_disableto,

    //-------------------------------------------------------
    // error inject on I/O commands
   
    input                             regs_cmd_errinj_valid,
    input                       [3:0] regs_cmd_errinj_select,
    input                      [31:0] regs_cmd_errinj_lba,
    input                             regs_cmd_errinj_uselba,
    input                      [15:0] regs_cmd_errinj_status,
    output reg                        cmd_regs_errinj_ack,
    output reg                        cmd_regs_errinj_cmdrd,
    output reg                        cmd_regs_errinj_cmdwr,
    output                      [5:0] cmd_perror_ind,
   
    // ----------------------------------------------------------
    // parity error inject 
    // ----------------------------------------------------------
    input                             regs_sntl_pe_errinj_valid,
    input                      [15:0] regs_xxx_pe_errinj_decode, 
    input                             regs_wdata_pe_errinj_1cycle_valid 
    );


`include "nvme_func.svh"

   wire                         [5:0] cmd_perror_int;
   (* mark_debug = "true" *)
   wire                         [5:0] s1_perror;

   // Parity error srlat 
   // set/reset/ latch for parity 
   nvme_srlat#
     (.width(6))  icmd_sr   
       (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(cmd_perror_int));

   assign cmd_perror_ind = cmd_perror_int;


   wire                               i_localmode;
   assign i_localmode = 1'b0;

   wire                               disable_aca = regs_cmd_debug[7];
   wire                               disable_lun_reset = regs_cmd_debug[6];
   
   // hold 1 request from AFU   
   reg                                req_v_q;
   reg                                req_cnt_v_q;
   reg                [cmd_width-1:0] req_cmd_q;
   reg                [tag_width-1:0] req_tag_q;
   reg                                req_tag_par_q;
   reg              [lunid_width-1:0] req_lun_q;
   reg                                req_lun_par_q;
   reg            [datalen_width-1:0] req_length_q;
   reg                                req_length_par_q;
   reg                        [127:0] req_cdb_q;
   reg                          [1:0] req_cdb_par_q;
   reg                                req_taken;
   reg                                ready_q;
   
   reg                                req_v_d;
   reg                                req_cnt_v_d;
   reg                [cmd_width-1:0] req_cmd_d;
   reg                [tag_width-1:0] req_tag_d;
   reg                                req_tag_par_d;
   reg              [lunid_width-1:0] req_lun_d;
   reg                                req_lun_par_d;
   reg            [datalen_width-1:0] req_length_d;
   reg                                req_length_par_d;
   reg                        [127:0] req_cdb_d;
   reg                          [1:0] req_cdb_par_d;
   reg                                ready_d;
   
   //-------------------------------------------------------
   // AFU requests
   //-------------------------------------------------------
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin
             req_v_q          <= 1'b0;
             req_cnt_v_q      <= 1'b0;
             req_cmd_q        <= zero[cmd_width-1:0];
             req_tag_q        <= zero[tag_width-1:0];
             req_tag_par_q    <= 1'b1;
             req_lun_q        <= zero[lunid_width-1:0];
             req_lun_par_q    <= 1'b1;
             req_length_q     <= zero[datalen_width-1:0];
             req_length_par_q <= 1'b1;
             req_cdb_q        <= zero[127:0];                
             req_cdb_par_q    <= 2'b1;                
             ready_q          <= 1'b0;          
          end
        else
          begin
             req_v_q          <= req_v_d;
             req_cnt_v_q      <= req_cnt_v_d;
             req_cmd_q        <= req_cmd_d;
             req_tag_q        <= req_tag_d;
             req_tag_par_q    <= req_tag_par_d;
             req_lun_q        <= req_lun_d;
             req_lun_par_q    <= req_lun_par_d;
             req_length_q     <= req_length_d;
             req_length_par_q <= req_length_par_d;
             req_cdb_q        <= req_cdb_d;    
             req_cdb_par_q    <= req_cdb_par_d;    
             ready_q          <= ready_d;           
          end
     end

   always @*
     begin
        req_v_d           = req_v_q;
        req_cmd_d         = req_cmd_q;
        req_tag_d         = req_tag_q;
        req_tag_par_d     = req_tag_par_q; 
        req_lun_d         = req_lun_q;
        req_lun_par_d     = req_lun_par_q;
        req_length_d      = req_length_q;
        req_length_par_d  = req_length_par_q;
        req_cdb_d         = req_cdb_q;
        req_cdb_par_d     = req_cdb_par_q;
        req_cnt_v_d       = 1'b0;    
        
        if (i_req_v_in & ready_q)
          begin             
             req_v_d           = 1'b1;
             req_cnt_v_d       = 1'b1;
             req_cmd_d         = i_req_cmd_in;
             req_tag_d         = i_req_tag_in;
             req_tag_par_d     = i_req_tag_par_in;
             req_lun_d         = i_req_lun_in;
             req_lun_par_d     = i_req_lun_par_in;
             req_length_d      = i_req_length_in; 
             req_length_par_d  = i_req_length_par_in; 
             req_cdb_d         = i_req_cdb_in;
             req_cdb_par_d     = i_req_cdb_par_in;
             $display("%t %m request tag %02x cmd %02x cdb %x",$time,i_req_tag_in,i_req_cmd_in,i_req_cdb_in);
          end

        if (req_taken)
          begin
             req_v_d = 1'b0;            
          end

        // assert ready unless there's already a valid command
        ready_d      = ~req_v_d;
        i_req_r_out  = ready_q;        
        
     end

   //-------------------------------------------------------
   // error response for write payload DMA
   //-------------------------------------------------------
   reg                     wdata_valid_q, wdata_valid_d;
   reg     [cid_width-1:0] wdata_cid_q, wdata_cid_d;
   reg [cid_par_width-1:0] wdata_cid_par_q, wdata_cid_par_d;
   reg                     wdata_taken;
   reg               [5:0] cmd_pe_inj_d,cmd_pe_inj_q;

   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin
             wdata_valid_q   <= 1'b0;
             wdata_cid_q     <= zero[cid_width-1:0];
             wdata_cid_par_q <= 2'b1;
             cmd_pe_inj_q    <= 6'b000000;
          end
        else
          begin
             wdata_valid_q   <= wdata_valid_d;
             wdata_cid_q     <= wdata_cid_d;
             wdata_cid_par_q <= wdata_cid_par_d;
             cmd_pe_inj_q    <= cmd_pe_inj_d;
          end
     end

   always @*
     begin
        cmd_dma_wdata_ready  = ~wdata_valid_q;
        wdata_valid_d        = wdata_valid_q;
        wdata_cid_d          = wdata_cid_q;
        wdata_cid_par_d      = wdata_cid_par_q;

        if( ~wdata_valid_q & dma_cmd_wdata_valid & dma_cmd_wdata_error)
          begin
             wdata_valid_d    = 1'b1;
             wdata_cid_d      = dma_cmd_wdata_cid;
             wdata_cid_par_d  = dma_cmd_wdata_cid_par;
          end

        if( wdata_taken )
          begin
             wdata_valid_d = 1'b0;
          end
     end
   

   //-------------------------------------------------------
   // tracking table
   //-------------------------------------------------------

   // 13b transfer length - 4K sislite blocks
   // 3b  write buffer id 
   // 8b  instance count
   // 25b sislite length - bytes
   // 25b relative offset - bytes
   // 8b  cdb opcode
   // 8b  state
   // 36b timestamp1  - timer1 time of request (us units)
   // 20b timestamp1d - timer1 last active latency (timer1-timestamp1)
   // 16b timestamp2  - timer2 last active time (16.384ms units) - adjusted for backpressure
   // 24b debug 
   // 64b lba - 4K sislite blocks
   // 32b namespace id - translated from LUNid
   // 1b  block size - namespace block size 0=512B 1=4K
   // 15b rsp status

   localparam trkdbg_width=24;


   reg   [isq_idwidth-1:0] s2_trk_rd_sqid; // 309:306
   reg  [lunidx_width-1:0] s2_trk_rd_lunidx; // 305:298
   reg [maxxfer_width-1:0] s2_trk_rd_xferlen; // 297:285
   reg  [wbufid_width-1:0] s2_trk_rd_wbufid;  // 284:282
   reg               [7:0] s2_trk_rd_instcnt; // 281:274
   reg [datalen_width-1:0] s2_trk_rd_length;  // 273:249
   reg [datalen_width-1:0] s2_trk_rd_reloff;  // 248:224
   reg               [7:0] s2_trk_rd_opcode;  // 223:216
   reg               [7:0] s2_trk_rd_state;   // 215:208
   reg              [35:0] s2_trk_rd_tstamp1; // 207:172
   reg              [19:0] s2_trk_rd_tstamp1d;// 171:152
   reg              [15:0] s2_trk_rd_tstamp2; // 151:136
   reg  [trkdbg_width-1:0] s2_trk_rd_debug;   // 135:112
   reg              [63:0] s2_trk_rd_lba;     // 111:48
   reg              [31:0] s2_trk_rd_nsid;    // 47:16
   reg                     s2_trk_rd_blksize; // 15
   reg              [14:0] s2_trk_rd_status;  // 14:0

   reg   [isq_idwidth-1:0] s3_trk_rd_sqid; 
   reg  [lunidx_width-1:0] s3_trk_rd_lunidx;
   reg [maxxfer_width-1:0] s3_trk_rd_xferlen;
   reg  [wbufid_width-1:0] s3_trk_rd_wbufid;  
   reg               [7:0] s3_trk_rd_instcnt;
   reg [datalen_width-1:0] s3_trk_rd_length;
   reg [datalen_width-1:0] s3_trk_rd_reloff;
   reg               [7:0] s3_trk_rd_opcode;
   reg               [7:0] s3_trk_rd_state;
   reg              [35:0] s3_trk_rd_tstamp1;
   reg              [19:0] s3_trk_rd_tstamp1d;
   reg              [15:0] s3_trk_rd_tstamp2;
   reg  [trkdbg_width-1:0] s3_trk_rd_debug;
   reg              [63:0] s3_trk_rd_lba;
   reg              [31:0] s3_trk_rd_nsid;
   reg                     s3_trk_rd_blksize;
   reg              [14:0] s3_trk_rd_status;

   reg [wbufid_par_width-1:0] s3_trk_rd_wbufid_par;  

   reg      [isq_idwidth-1:0] s4_trk_wr_sqid;
   reg     [lunidx_width-1:0] s4_trk_wr_lunidx;
   reg    [maxxfer_width-1:0] s4_trk_wr_xferlen;
   reg     [wbufid_width-1:0] s4_trk_wr_wbufid;  
   reg                  [7:0] s4_trk_wr_instcnt;
   reg    [datalen_width-1:0] s4_trk_wr_length;
   reg    [datalen_width-1:0] s4_trk_wr_reloff;
   reg                  [7:0] s4_trk_wr_opcode;
   reg                  [7:0] s4_trk_wr_state;
   reg                 [35:0] s4_trk_wr_tstamp1;
   reg                 [19:0] s4_trk_wr_tstamp1d;
   reg                 [15:0] s4_trk_wr_tstamp2;
   reg     [trkdbg_width-1:0] s4_trk_wr_debug;
   reg                 [63:0] s4_trk_wr_lba;
   reg                 [31:0] s4_trk_wr_nsid;
   reg                        s4_trk_wr_blksize;
   reg                 [14:0] s4_trk_wr_status;
   
   
   localparam trk_width = isq_idwidth + lunidx_width + maxxfer_width + wbufid_width + 8 + datalen_width + datalen_width + 8 + 8 + 24 + 24 + 24 + trkdbg_width + 64 + 32 + 1 + 15;
   localparam trk_last_entry = trk_entries - 1;
   (* RAM_STYLE="block" *)  reg [trk_width-1:0] trk_mem[trk_entries-1:0];

   reg        [trk_width-1:0] trk_wrdata;
   reg        [trk_width-1:0] trk_rddata;
    (* mark_debug = "true" *)
   reg       [trk_awidth-1:0] trk_rdaddr, trk_wraddr;
    (* mark_debug = "true" *)
   reg                        trk_rdaddr_par, trk_wraddr_par;
    (* mark_debug = "true" *)
   reg                        trk_write;


    (* mark_debug = "true" *)
   reg                        s0_valid_q;
   reg                        s0_valid_d;
   reg                        s1_valid_q, s1_valid_d;
   wire                       s5_admin_fifo_valid;

   always @*
     begin       
        cmd_pe_inj_d = cmd_pe_inj_q;
        if (regs_wdata_pe_errinj_1cycle_valid & regs_sntl_pe_errinj_valid & regs_xxx_pe_errinj_decode[11:8] == 4'h1)
          begin
             cmd_pe_inj_d[0]  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
             cmd_pe_inj_d[1]  = (regs_xxx_pe_errinj_decode[3:0]==4'h1);
             cmd_pe_inj_d[2]  = (regs_xxx_pe_errinj_decode[3:0]==4'h2);
             cmd_pe_inj_d[3]  = (regs_xxx_pe_errinj_decode[3:0]==4'h3);
             cmd_pe_inj_d[4]  = (regs_xxx_pe_errinj_decode[3:0]==4'h4);
             cmd_pe_inj_d[5]  = (regs_xxx_pe_errinj_decode[3:0]==4'h5);
          end 
        if (cmd_pe_inj_q[0] & s0_valid_q)
          cmd_pe_inj_d[0] = 1'b0;
        if (cmd_pe_inj_q[1] & trk_write)
          cmd_pe_inj_d[1] = 1'b0;
        if (cmd_pe_inj_q[2] & s0_valid_q)
          cmd_pe_inj_d[2] = 1'b0;
        if (cmd_pe_inj_q[3] & s1_valid_q)
          cmd_pe_inj_d[3] = 1'b0;
        if (cmd_pe_inj_q[4] & ioq_sntl_cpl_valid)
          cmd_pe_inj_d[4] = 1'b0;
        if (cmd_pe_inj_q[5] & s5_admin_fifo_valid)
          cmd_pe_inj_d[5] = 1'b0;
     end  
  
   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(trk_awidth)
      ) ipcheck_trk_rdaddr
       (.oddpar(1'b1),.data({trk_rdaddr[trk_awidth-1:1],(trk_rdaddr[0]^cmd_pe_inj_q[0])}),.datap(trk_rdaddr_par),.check(s0_valid_q),.parerr(s1_perror[0])); 

   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(trk_awidth)
      ) ipcheck_trk_wraddr
       (.oddpar(1'b1),.data({trk_wraddr[trk_awidth-1:1],(trk_wraddr[0]^cmd_pe_inj_q[1])}),.datap(trk_wraddr_par),.check(trk_write),.parerr(s1_perror[1])); 



   always @(posedge clk)
     begin
        if (trk_write)
          trk_mem[trk_wraddr] <= trk_wrdata;
        trk_rddata <= trk_mem[trk_rdaddr];
     end
   
   //-------------------------------------------------------
   // event processing pipeline
   //-------------------------------------------------------
   
   // stage 0: select event
   // stage 1: read tracking table
   // stage 2: tracking table read out + ecc
   // stage 3: decode commands
   // stage 4: update tracking table
   // stage 5: write tracking table

   
   // round robin arbitration for stage 0 of the pipeline
   
   localparam s0_rr_width=7;
   reg      [s0_rr_width-1:0] s0_rr_valid;
   
   reg      [s0_rr_width-1:0] s0_rr_q, s0_rr_d;
   reg      [s0_rr_width-1:0] s0_rr_gnt; 
   (* mark_debug = "true" *) 
   reg      [s0_rr_width-1:0] s0_rr_gnt_q;
   reg      [s0_rr_width-1:0]  s0_rr_gnt_d;
   reg       [31:s0_rr_width] s0_rr_noused;

   reg       [trk_awidth-1:0] s0_init_q, s0_init_d;
   reg                        s0_init_par_q, s0_init_par_d; 
   reg                        s0_init_done_q, s0_init_done_d;

   // stage 0 result
   (* mark_debug = "true" *)
   reg        [cid_width-1:0] s0_cid_q;
   reg        [cid_width-1:0] s0_cid_d;
   (* mark_debug = "true" *)
   reg    [cid_par_width-1:0] s0_cid_par_q;
   reg    [cid_par_width-1:0] s0_cid_par_d;
   (* mark_debug = "true" *)
   reg                  [7:0] s0_cmd_q;
   reg                  [7:0] s0_cmd_d;
   reg    [datalen_width-1:0] s0_reloff_q, s0_reloff_d;
   reg    [datalen_width-1:0] s0_length_q, s0_length_d;
   reg                        s0_length_par_q, s0_length_par_d; 
   reg      [lunid_width-1:0] s0_lun_q, s0_lun_d;   
   reg                        s0_lun_par_q, s0_lun_par_d;
   (* mark_debug = "true" *)
   reg                [127:0] s0_data_q;
   reg                [127:0] s0_data_d;
   reg                  [7:0] s0_data_par_q, s0_data_par_d;

   // stage 1 result - wait for tracking table read
   reg        [cid_width-1:0] s1_cid_q, s1_cid_d;
   reg    [cid_par_width-1:0] s1_cid_par_q,s1_cid_par_d; 
   reg                  [7:0] s1_cmd_q, s1_cmd_d;
   reg    [datalen_width-1:0] s1_reloff_q, s1_reloff_d;
   reg    [datalen_width-1:0] s1_length_q, s1_length_d;
   reg                        s1_length_par_q, s1_length_par_d;
   reg      [lunid_width-1:0] s1_lun_q, s1_lun_d;   
   reg                        s1_lun_par_q, s1_lun_par_d;  
   reg                [127:0] s1_data_q, s1_data_d;
   reg                  [1:0] s1_data_par_q,s1_data_par_d;
   reg                        s1_debug_ack_q, s1_debug_ack_d;
   
   // stage 1 - bypass tracking table write
   reg        [trk_width-1:0] s1_trk_wrdata_q, s1_trk_wrdata_d;
   reg                        s1_trk_write_q, s1_trk_write_d;
   reg       [trk_awidth-1:0] s1_trk_wraddr_q, s1_trk_wraddr_d;


   // stage 2 result - tracking data is valid
   reg                        s2_valid_q, s2_valid_d;
   reg        [trk_width-1:0] s2_trk_data_q, s2_trk_data_d;
   reg        [cid_width-1:0] s2_cid_q, s2_cid_d;
   reg    [cid_par_width-1:0] s2_cid_par_q, s2_cid_par_d; 
   reg                  [7:0] s2_cmd_q, s2_cmd_d; 
   reg    [datalen_width-1:0] s2_reloff_q, s2_reloff_d; 
   reg    [datalen_width-1:0] s2_length_q, s2_length_d;
   reg                        s2_length_par_q, s2_length_par_d;
   reg    [datalen_width-1:0] s2_reloffp_q, s2_reloffp_d;
   reg      [lunid_width-1:0] s2_lun_q, s2_lun_d;
   reg                        s2_lun_par_q, s2_lun_par_d;
   reg                [127:0] s2_data_q, s2_data_d;
   reg                  [1:0] s2_data_par_q, s2_data_par_d;
   reg                        s2_debug_ack_q, s2_debug_ack_d;
   
   // stage 3 result - first half of decode/update results
   reg                        s3_valid_q, s3_valid_d;
   reg        [trk_width-1:0] s3_trk_data_q, s3_trk_data_d;
   reg        [cid_width-1:0] s3_cid_q, s3_cid_d;
   reg    [cid_par_width-1:0] s3_cid_par_q, s3_cid_par_d; 
   reg                  [7:0] s3_cmd_q, s3_cmd_d;
   reg    [datalen_width-1:0] s3_reloff_q, s3_reloff_d;
   reg    [datalen_width-1:0] s3_length_q, s3_length_d;
   reg                        s3_length_par_q, s3_length_par_d;
   reg    [datalen_width-1:0] s3_reloffp_q, s3_reloffp_d;
   reg      [lunid_width-1:0] s3_lun_q, s3_lun_d;
   reg      [lunid_width-1:0] s3_lun_par_q, s3_lun_par_d; 
   reg                [127:0] s3_data_q, s3_data_d;
   reg                  [7:0] s3_data_par_q, s3_data_par_d;  
   
   // stage 4 result - updated tracking table entry and results to output queues
   reg        [trk_width-1:0] s4_trk_wrdata_q;
   reg        [trk_width-1:0] s4_trk_wrdata_d;
   reg                        s4_trk_write_q;
   reg                        s4_trk_write_d;
   reg       [trk_awidth-1:0] s4_trk_wraddr_q;
   reg       [trk_awidth-1:0] s4_trk_wraddr_d;
   reg                        s4_trk_wraddr_par_q;  
   reg                        s4_trk_wraddr_par_d;

  // queue up write requests
   reg [cid_par_width+cid_width-1:0] s4_iowr_cmdid_q, s4_iowr_cmdid_d;
   reg                        s4_iowr_push_q, s4_iowr_push_d;

   // send unmap requests
   reg                        s4_unmap_req_valid_q, s4_unmap_req_valid_d;
   reg                        s4_unmap_cpl_valid_q, s4_unmap_cpl_valid_d;
   reg [cid_par_width+cid_width-1:0] s4_unmap_cmdid_q, s4_unmap_cmdid_d;
   reg                 [14:0] s4_unmap_status_q, s4_unmap_status_d;
   
   // queue up read requests
   reg [cid_par_width+cid_width-1:0] s4_iord_cmdid_q, s4_iord_cmdid_d;
   //reg                [1:0] s4_iord_cmdid_par_q, s4_iord_cmdid_par_d;
   reg                        s4_iord_push_q, s4_iord_push_d;

   // queue up write buffer requests
   reg        [cid_width-1:0] s4_wbuf_cmdid_q, s4_wbuf_cmdid_d;
   reg    [cid_par_width-1:0] s4_wbuf_cmdid_par_q, s4_wbuf_cmdid_par_d;
   reg    [datalen_width-1:0] s4_wbuf_reloff_q, s4_wbuf_reloff_d;
   reg                 [63:0] s4_wbuf_lba_q, s4_wbuf_lba_d;
   reg                 [15:0] s4_wbuf_numblks_q, s4_wbuf_numblks_d;
   reg     [wbufid_width-1:0] s4_wbuf_wbufid_q, s4_wbuf_wbufid_d;
   reg [wbufid_par_width-1:0] s4_wbuf_wbufid_par_q, s4_wbuf_wbufid_par_d;
   reg                        s4_wbuf_push_q, s4_wbuf_push_d;
   reg                        s4_wbuf_unmap_q, s4_wbuf_unmap_d;

   // free write buffer
   reg                        s4_wbuf_idfree_valid_q, s4_wbuf_idfree_valid_d;
   reg     [wbufid_width-1:0] s4_wbuf_idfree_wbufid_q, s4_wbuf_idfree_wbufid_d;
   reg [wbufid_par_width-1:0] s4_wbuf_idfree_wbufid_par_q, s4_wbuf_idfree_wbufid_par_d;

   // requests to I/O Submission queue
   reg                 [63:0] s4_ioq_lba_q, s4_ioq_lba_d;
   reg                 [15:0] s4_ioq_numblks_q, s4_ioq_numblks_d;
   reg                 [31:0] s4_ioq_nsid_q, s4_ioq_nsid_d;
   reg                  [7:0] s4_ioq_opcode_q, s4_ioq_opcode_d;
   reg        [cid_width-1:0] s4_ioq_cmdid_q, s4_ioq_cmdid_d;
   reg     [wbufid_width-1:0] s4_ioq_wbufid_q, s4_ioq_wbufid_d;
   reg    [datalen_width-1:0] s4_ioq_reloff_q, s4_ioq_reloff_d;
   reg                        s4_ioq_fua_q, s4_ioq_fua_d;
   reg      [isq_idwidth-1:0] s4_ioq_sqid_q, s4_ioq_sqid_d;
   reg                        s4_ioq_push_q, s4_ioq_push_d;
   reg                        s4_ioq_sqid_ack_q, s4_ioq_sqid_ack_d;
   
   // requests to Admin Submission Queue via microcontroller
   reg                        s4_admin_push_q, s4_admin_push_d;
   reg        [cmd_width-1:0] s4_admin_cmd_q, s4_admin_cmd_d;
   reg        [cid_width-1:0] s4_admin_cid_q, s4_admin_cid_d;
   reg      [lunid_width-1:0] s4_admin_lun_q, s4_admin_lun_d;
   reg                        s4_admin_lun_par_q, s4_admin_lun_par_d; 
   reg    [datalen_width-1:0] s4_admin_length_q, s4_admin_length_d;
   reg                [127:0] s4_admin_cdb_q, s4_admin_cdb_d;
   reg                  [7:0] s4_admin_cdb_par_q, s4_admin_cdb_par_d;
   
   // responses to sislite
   reg                        s4_rsp_push_q, s4_rsp_push_d;
   reg                 [15:0] s4_rsp_status_q, s4_rsp_status_d;
   reg                        s4_rsp_resid_over_q, s4_rsp_resid_over_d;
   reg                        s4_rsp_resid_under_q, s4_rsp_resid_under_d;
   reg                 [31:0] s4_rsp_resid_q, s4_rsp_resid_d;   
   reg                 [31:0] s4_rsp_data_q, s4_rsp_data_d;   
   reg        [tag_width-1:0] s4_rsp_tag_q, s4_rsp_tag_d;
   reg                        s4_rsp_tag_par_q, s4_rsp_tag_par_d; 
   reg     [lunidx_width-1:0] s4_rsp_lunidx_q, s4_rsp_lunidx_d;
   reg                        s4_rsp_naca_q, s4_rsp_naca_d;
   reg                        s4_rsp_flush_q, s4_rsp_flush_d;
   reg                        s4_rsp_passthru_q, s4_rsp_passthru_d;
   // response to dma lookup
   reg                        s4_dma_valid_q, s4_dma_valid_d;
   reg                        s4_dma_error_q, s4_dma_error_d;
   // latency counts
   reg                 [31:0] s4_events_q, s4_events_d;

   reg                        s4_debug_freeze_q;
   reg                        s4_debug_freeze_d;

   // write request fifo
   reg                        s5_iowr_fifo_taken;
   wire                       s5_iowr_fifo_valid;
   wire       [cid_width-1:0] s5_iowr_fifo_data;
   reg                        s5_iowr_wbufid_valid;
   reg     [wbufid_width-1:0] s5_iowr_wbufid;
   reg                        iowr_completed;
   reg          [tag_width:0] iowr_inuse_q, iowr_inuse_d;

   // read request fifo
   reg                        s5_iord_fifo_taken;
   wire                       s5_iord_fifo_valid;
   wire       [cid_width-1:0] s5_iord_fifo_data;
   wire   [cid_par_width-1:0] s5_iord_fifo_data_par;
   reg                        iord_completed;
   reg          [tag_width:0] iord_inuse_q, iord_inuse_d; 

   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin            
             s0_rr_q                <= one[s0_rr_width-1:0];
             s0_rr_gnt_q            <= zero[s0_rr_width-1:0];  
             s0_valid_q             <= 1'b0;
             s0_init_q              <= zero[trk_awidth:0];
             s0_init_par_q          <= 1'b1;
             s0_init_done_q         <= 1'b0;
             iowr_inuse_q           <= zero[tag_width:0];             
             iord_inuse_q           <= zero[tag_width:0];             
             s1_valid_q             <= 1'b0;
             s1_debug_ack_q         <= 1'b0;             
             s1_trk_write_q         <= 1'b0;             
             s2_valid_q             <= 1'b0;
             s2_debug_ack_q         <= 1'b0;
             s3_valid_q             <= 1'b0;
             s4_trk_write_q         <= 1'b0;
             s4_ioq_push_q          <= 1'b0;
             s4_ioq_sqid_ack_q      <= 1'b0;
             s4_iowr_push_q         <= 1'b0;
             s4_unmap_req_valid_q   <= 1'b0;
             s4_unmap_cpl_valid_q   <= 1'b0;
             s4_iord_push_q         <= 1'b0;
             s4_wbuf_push_q         <= 1'b0;
             s4_wbuf_idfree_valid_q <= 1'b0;
             s4_admin_push_q        <= 1'b0;
             s4_rsp_push_q          <= 1'b0;
             s4_rsp_flush_q         <= 1'b0;
             s4_rsp_passthru_q      <= 1'b0;
             s4_dma_valid_q         <= 1'b0;
             s4_debug_freeze_q      <= 1'b0;
             s4_events_q            <= 32'h0;
          end
        else
          begin      
             s0_rr_q                <= s0_rr_d;
             s0_rr_gnt_q            <= s0_rr_gnt_d;
             s0_valid_q             <= s0_valid_d;
             s0_init_q              <= s0_init_d;
             s0_init_par_q          <= s0_init_par_d;
             s0_init_done_q         <= s0_init_done_d;
             iowr_inuse_q           <= iowr_inuse_d;
             iord_inuse_q           <= iord_inuse_d;
             s1_valid_q             <= s1_valid_d;
             s1_debug_ack_q         <= s1_debug_ack_d;
             s1_trk_write_q         <= s1_trk_write_d;
             s2_valid_q             <= s2_valid_d;
             s2_debug_ack_q         <= s2_debug_ack_d;
             s3_valid_q             <= s3_valid_d;
             s4_trk_write_q         <= s4_trk_write_d;
             s4_ioq_push_q          <= s4_ioq_push_d;
             s4_ioq_sqid_ack_q      <= s4_ioq_sqid_ack_d;
             s4_iowr_push_q         <= s4_iowr_push_d;
             s4_unmap_req_valid_q   <= s4_unmap_req_valid_d;
             s4_unmap_cpl_valid_q   <= s4_unmap_cpl_valid_d;
             s4_iord_push_q         <= s4_iord_push_d;
             s4_wbuf_push_q         <= s4_wbuf_push_d;
             s4_wbuf_idfree_valid_q <= s4_wbuf_idfree_valid_d;
             s4_admin_push_q        <= s4_admin_push_d;
             s4_rsp_push_q          <= s4_rsp_push_d;
             s4_rsp_flush_q         <= s4_rsp_flush_d;
             s4_rsp_passthru_q      <= s4_rsp_passthru_d;
             s4_dma_valid_q         <= s4_dma_valid_d;
             s4_debug_freeze_q      <= s4_debug_freeze_d;
             s4_events_q            <= s4_events_d;
          end
     end // always @ (posedge clk or posedge reset)

   always @(posedge clk)
     begin        
        s0_cid_q                    <= s0_cid_d;
        s0_cid_par_q                <= s0_cid_par_d; 
        s0_cmd_q                    <= s0_cmd_d;
        s0_reloff_q                 <= s0_reloff_d;
        s0_length_q                 <= s0_length_d;
        s0_length_par_q             <= s0_length_par_d;
        s0_lun_q                    <= s0_lun_d;
        s0_lun_par_q                <= s0_lun_par_d;
        s0_data_q                   <= s0_data_d;
        s0_data_par_q               <= s0_data_par_d;

        s1_cid_q                    <= s1_cid_d;
        s1_cid_par_q                <= s1_cid_par_d;
        s1_cmd_q                    <= s1_cmd_d;
        s1_reloff_q                 <= s1_reloff_d;
        s1_length_q                 <= s1_length_d;
        s1_length_par_q             <= s1_length_par_d; 
        s1_lun_q                    <= s1_lun_d;
        s1_data_q                   <= s1_data_d;
        s1_data_par_q               <= s1_data_par_d;
        
        s1_trk_wrdata_q             <= s1_trk_wrdata_d;
        s1_trk_wraddr_q             <= s1_trk_wraddr_d;
        
        s2_trk_data_q               <= s2_trk_data_d;
        s2_cid_q                    <= s2_cid_d;
        s2_cid_par_q                <= s2_cid_par_d; 
        s2_cmd_q                    <= s2_cmd_d;
        s2_reloff_q                 <= s2_reloff_d;
        s2_length_q                 <= s2_length_d;
        s2_length_par_q             <= s2_length_par_d;
        s2_reloffp_q                <= s2_reloffp_d;
        s2_lun_q                    <= s2_lun_d;
        s2_data_q                   <= s2_data_d;
        s2_data_par_q               <= s2_data_par_d; 

        s3_trk_data_q               <= s3_trk_data_d;
        s3_cid_q                    <= s3_cid_d;
        s3_cid_par_q                <= s3_cid_par_d;
        s3_cmd_q                    <= s3_cmd_d;
        s3_reloff_q                 <= s3_reloff_d;
        s3_length_q                 <= s3_length_d;
        s3_length_par_q             <= s3_length_par_d;
        s3_reloffp_q                <= s3_reloffp_d;
        s3_lun_q                    <= s3_lun_d;
        s3_lun_par_q                <= s3_lun_par_d;
        s3_data_q                   <= s3_data_d;
        s3_data_par_q               <= s3_data_par_d;
        
        s4_trk_wrdata_q             <= s4_trk_wrdata_d;
        s4_trk_wraddr_q             <= s4_trk_wraddr_d;
        s4_trk_wraddr_par_q         <= s4_trk_wraddr_par_d;
        s4_ioq_lba_q                <= s4_ioq_lba_d;
        s4_ioq_numblks_q            <= s4_ioq_numblks_d;
        s4_ioq_nsid_q               <= s4_ioq_nsid_d;
        s4_ioq_opcode_q             <= s4_ioq_opcode_d;
        s4_ioq_cmdid_q              <= s4_ioq_cmdid_d;
        s4_ioq_wbufid_q             <= s4_ioq_wbufid_d;
        s4_ioq_reloff_q             <= s4_ioq_reloff_d;
        s4_ioq_fua_q                <= s4_ioq_fua_d;
        s4_ioq_sqid_q               <= s4_ioq_sqid_d;
        s4_iowr_cmdid_q             <= s4_iowr_cmdid_d;
        s4_unmap_cmdid_q            <= s4_unmap_cmdid_d;
        s4_unmap_status_q           <= s4_unmap_status_d;
        s4_iord_cmdid_q             <= s4_iord_cmdid_d;
        //        s4_iord_cmdid_par_q       <= s4_iord_cmdid_par_d;
        s4_wbuf_cmdid_q             <= s4_wbuf_cmdid_d;
        s4_wbuf_cmdid_par_q         <= s4_wbuf_cmdid_par_d;
        s4_wbuf_reloff_q            <= s4_wbuf_reloff_d;
        s4_wbuf_numblks_q           <= s4_wbuf_numblks_d;
        s4_wbuf_lba_q               <= s4_wbuf_lba_d;
        s4_wbuf_wbufid_q            <= s4_wbuf_wbufid_d;
        s4_wbuf_wbufid_par_q        <= s4_wbuf_wbufid_par_d;
        s4_wbuf_unmap_q             <= s4_wbuf_unmap_d;
        s4_wbuf_idfree_wbufid_q     <= s4_wbuf_idfree_wbufid_d;
        s4_wbuf_idfree_wbufid_par_q <= s4_wbuf_idfree_wbufid_par_d;
        s4_admin_cmd_q              <= s4_admin_cmd_d;
        s4_admin_cid_q              <= s4_admin_cid_d;
        s4_admin_lun_q              <= s4_admin_lun_d;
        s4_admin_lun_par_q          <= s4_admin_lun_par_d;
        s4_admin_length_q           <= s4_admin_length_d;
        s4_admin_cdb_q              <= s4_admin_cdb_d;
        s4_admin_cdb_par_q          <= s4_admin_cdb_par_d; 
        s4_rsp_status_q             <= s4_rsp_status_d;
        s4_rsp_resid_over_q         <= s4_rsp_resid_over_d;
        s4_rsp_resid_under_q        <= s4_rsp_resid_under_d;
        s4_rsp_resid_q              <= s4_rsp_resid_d;
        s4_rsp_data_q               <= s4_rsp_data_d;
        s4_rsp_tag_q                <= s4_rsp_tag_d;
        s4_rsp_tag_par_q            <= s4_rsp_tag_par_d; 
        s4_rsp_lunidx_q             <= s4_rsp_lunidx_d;
        s4_rsp_naca_q               <= s4_rsp_naca_d;
        s4_dma_error_q              <= s4_dma_error_d;         
     end
   
   //-------------------------------------------------------
   

   (* mark_debug = "false" *) reg       s5_ioq_backpressure;
   (* mark_debug = "false" *) reg       s5_admin_backpressure;
   (* mark_debug = "false" *) reg       s5_rsp_backpressure;
   (* mark_debug = "false" *) reg       s5_busy;

   
   // background process to check for timeouts and clean up on link down or shutdown
   reg                checker_valid;
   reg                checker_taken;  // checker request wins arb
   reg [trk_awidth:0] checker_tag;
   reg                checker_tag_par;
   reg          [3:0] checker_action;
   localparam CHK_READ         = 4'h1;
   localparam CHK_TIMEOUT      = 4'h2;
   localparam CHK_LINKDOWN     = 4'h3;
   localparam CHK_SHUTDOWN     = 4'h4;
   localparam CHK_LUNRESET     = 4'h5;
   localparam CHK_LUNRESET_CMP = 4'h6;
   // controls to initiate a lun reset
   reg                 s2_chk_lunreset;
   reg                 s4_checker_lunreset;
   reg [tag_width-1:0] s4_checker_lunreset_tag;
   reg                 s4_checker_lunreset_tag_par;
   reg                 checker_lunreset_stall;
  
   
   // stall requests if they collide with stage 0 or 1 output
   // tracking table results are forwarded for stages 2,3
   (* mark_debug = "true" *)
   reg                s0_dma_stall;
   reg                s0_iowr_stall;
   reg                s0_iord_stall;
   reg                s0_ioq_stall;
   reg                s0_admin_stall;
   reg                s0_req_stall;
   reg                s0_checker_stall;
   reg                s0_wdata_stall;
   reg                s0_unmap_stall;
   reg                s0_wbuf_stall;

   // check parity for decodes below 
   // no need to check dma_cmd_cid since it is generated at th output of nvme_sntl_dma.v
   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(cid_width)
      ) ipcheck_s0_cid_q
       (.oddpar(1'b1),.data({s0_cid_q[cid_width-1:1],(s0_cid_q[0]^cmd_pe_inj_q[2])}),.datap(s0_cid_par_q),.check(s0_valid_q),.parerr(s1_perror[2]));  

   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(cid_width)
      ) ipcheck_s1_cid_q
       (.oddpar(1'b1),.data({s1_cid_q[cid_width-1:1],(s1_cid_q[0]^cmd_pe_inj_q[3])}),.datap(s1_cid_par_q),.check(s1_valid_q),.parerr(s1_perror[3])); 
   
   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(cid_width)
      ) ipcheck_oq_sntl_cpl_cmdid
       (.oddpar(1'b1),.data({ioq_sntl_cpl_cmdid[cid_width-1:1],(ioq_sntl_cpl_cmdid[0]^cmd_pe_inj_q[4])}),.datap(ioq_sntl_cpl_cmdid_par),.check(ioq_sntl_cpl_valid),.parerr(s1_perror[4]));  

   wire               s0_init_par;      
   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(tag_width)
      ) ipgen_s0_init_par 
       (.oddpar(1'b1),.data(s0_init_d[tag_width-1:0]),.datap(s0_init_par)); 
   
   wire         [1:0] s5_iowr_fifo_data_par; 

   
   always @*
     begin
        s0_dma_stall      = (s0_valid_q && dma_cmd_cid==s0_cid_q) ||
                            (s1_valid_q && dma_cmd_cid==s1_cid_q) || 
                            regs_xx_freeze;
        s0_ioq_stall      = (s0_valid_q) || //  && ioq_sntl_cpl_cmdid==s0_cid_q) ||
                            (s1_valid_q) ||   //  && ioq_sntl_cpl_cmdid==s1_cid_q);
                            regs_xx_freeze;
        s0_iowr_stall     = (s0_valid_q) || //  && s5_iowr_fifo_data==s0_cid_q) ||
                            (s1_valid_q) || //  && s5_iowr_fifo_data==s1_cid_q) ||
                            (iowr_inuse_q>regs_cmd_maxiowr) ||
                            ~s5_iowr_wbufid_valid ||
                            regs_xx_freeze;
        s0_iord_stall     = (s0_valid_q) || //  && s5_iord_fifo_data==s0_cid_q) ||
                            (s1_valid_q) || //  && s5_iord_fifo_data==s1_cid_q) ||
                            (iord_inuse_q>regs_cmd_maxiord) ||
                            regs_xx_freeze;
        s0_admin_stall    = (s0_valid_q) || //  && admin_cmd_cpl_cmdid==s0_cid_q) ||
                            (s1_valid_q) || //  && admin_cmd_cpl_cmdid==s1_cid_q);
                            regs_xx_freeze;   
        s0_req_stall      = s2_chk_lunreset || 
                            checker_lunreset_stall ||
                            (s0_valid_q) || 
                            (s1_valid_q) ||                            
                            regs_xx_freeze;
        s0_checker_stall  = (s0_valid_q) || //  && checker_tag[tag_width-1:0]==s0_cid_q[tag_width-1:0]) ||
                            (s1_valid_q) ||   //  && checker_tag[tag_width-1:0]==s1_cid_q[tag_width-1:0]);
                            regs_xx_freeze;
        s0_wdata_stall    = (s0_valid_q) || //  && wdata_cid_q==s0_cid_q) ||
                            (s1_valid_q) || //  && wdata_cid_q==s1_cid_q);
                            regs_xx_freeze;
        s0_wbuf_stall     = (s0_valid_q) ||
                            (s1_valid_q) ||
                            regs_xx_freeze;
        s0_unmap_stall    = (s0_valid_q) ||
                            (s1_valid_q) ||
                            regs_xx_freeze;

     end 

   //-------------------------------------------------------
   // stage 0 input
   //-------------------------------------------------------

   localparam rr_unmap   = 6;
   localparam rr_iord    = 5;
   localparam rr_wbuf    = 4;
   localparam rr_iowr    = 3;
   localparam rr_debug   = 2;
   localparam rr_ioq     = 1;
   localparam rr_req     = 0;
   always @*
     begin
        
        // inputs to this stage:
        // dma_cmd_valid      
        //   - read or write payload dma to PSL.  Look up tracking state and update # of bytes transferred
        //   - no backpressure
        // ioq_sntl_cpl_valid 
        //   - I/O queue completion status.  Update tracking state and send status to rsp fifo
        //   - backpressure from response fifo
        // admin_cmd_cpl_valid
        //   - completion of command that used the Admin Queue.  Update tracking state and send status to rsp fifo
        //   - backpressure from response fifo
        // req_v_q
        //   - new sislite command request
        //   - backpressure from:  
        //       - ioq request register (IOQ # entries == # of sislite tags, therefore backpressure is temporary)
        //       - admin request fifo
        //       - response fifo (for invalid commands)
        // checker_valid
        //   - check for tracking entries that have timed out
        //   - backpressure from:
        //       - response fifo
        //       - admin request fifo (if abort is sent)
        // wdata_valid
        //   - DMA error on sislite write
        //   - backpressure from:
        //       - admin request fifo (if abort is sent)
        // wbuf_cmd_status_valid
        //   - write buffer request completed
        //   - backpressure from:
        //       - ioq request
        //       - response fifo
        
        // regs_cmd_trk_rd - debug read of tracking table
        //

        s5_busy                    = s5_ioq_backpressure | s5_admin_backpressure | s5_rsp_backpressure;
        
        s0_rr_d                    = s0_rr_q;
        s0_rr_gnt_d                = zero[s0_rr_width-1:0];
        s0_rr_valid[rr_ioq]        = ioq_sntl_cpl_valid & ~s5_rsp_backpressure & ~s0_ioq_stall;
        s0_rr_valid[rr_req]        = req_v_q & ~s4_debug_freeze_q & ~s5_busy & ~s0_req_stall;
        s0_rr_valid[rr_debug]      = regs_cmd_trk_rd & ~s1_debug_ack_q & ~s2_debug_ack_q;
        s0_rr_valid[rr_iord]       = s5_iord_fifo_valid & ~s5_busy & ~s0_iord_stall;
        s0_rr_valid[rr_iowr]       = s5_iowr_wbufid_valid & ~s5_busy & ~s0_iowr_stall;
        s0_rr_valid[rr_wbuf]       = wbuf_cmd_status_valid & ~s5_busy & ~s0_wbuf_stall;
        s0_rr_valid[rr_unmap]      = unmap_cmd_valid & ~s5_busy & ~s0_unmap_stall;
        
        {s0_rr_noused, s0_rr_gnt}  = roundrobin({zero[31:s0_rr_width],(s0_rr_valid & ~s0_rr_gnt_q)}, {zero[31:s0_rr_width], s0_rr_q} );
        
        s0_valid_d                 = 1'b0;
        s0_cid_d                   = 16'hffff;
        s0_cid_par_d               = 2'b11;
        s0_cmd_d                   = CMD_INVALID[7:0];
        s0_reloff_d                = zero[datalen_width-1:0];
        s0_length_d                = zero[datalen_width-1:0];
        s0_length_par_d            = 1'b1;
        s0_lun_d                   = req_lun_q;
        s0_lun_par_d               = req_lun_par_q;
        s0_data_d                  = zero[127:0];
        s0_data_par_d              = ~zero[7:0];


        cmd_admin_cpl_ack          = 1'b0;
        wdata_taken                = 1'b0;
        checker_taken              = 1'b0;
        cmd_dma_ready              = s0_init_done_q & ~s0_dma_stall;
              
        cmd_wbuf_status_ready      = 1'b0;
        
        s0_init_done_d             = s0_init_done_q;
        if( ~s0_init_done_q )
          begin
             s0_init_d = s0_init_q + one[trk_awidth-1:0];
             s0_init_par_d = s0_init_par;
             if( s0_init_q == trk_last_entry[trk_awidth-1:0] )
               begin
                  s0_init_done_d = 1'b1;
               end
          end
        else
          begin
             s0_init_d      = s0_init_q;
             s0_init_par_d  = s0_init_par_q;
          end
        
        
        if( ~s0_init_done_q )
          begin
             s0_valid_d   = 1'b1;
             s0_cid_d     = { zero[cid_width-1:trk_awidth], s0_init_q};
             s0_cid_par_d = {1'b1, s0_init_par_q};
             s0_cmd_d     = CMD_INIT[7:0];             
          end   
        else if( dma_cmd_valid & ~s0_dma_stall )
          begin
             // this has fixed timing in sntl_dma
             // result must be 4 cycles after valid==1 & ready==1
             s0_valid_d       = 1'b1;
             s0_cid_d         = dma_cmd_cid;
             s0_cid_par_d     = dma_cmd_cid_par;
             s0_cmd_d         = (dma_cmd_rnw ? CMD_RD_LOOKUP[7:0] : CMD_WR_LOOKUP[7:0]);
             s0_reloff_d      = dma_cmd_reloff;
             s0_length_d      = dma_cmd_length;     
             s0_length_par_d  = dma_cmd_length_par;     
          end
        else if( checker_valid & ~s5_admin_backpressure & ~s5_rsp_backpressure & ~s0_checker_stall )
          begin
             s0_valid_d      = 1'b1;
             s0_cid_d        = { zero[cid_width-1:trk_awidth], checker_tag };
             s0_cid_par_d    = {1'b1, checker_tag_par}; 
             s0_cmd_d        = CMD_CHECKER[7:0];
             s0_data_d[3:0]  = checker_action;
             checker_taken   = 1'b1;
          end
        else if( admin_cmd_cpl_valid & ~s5_rsp_backpressure & ~s0_admin_stall )
          begin
             s0_valid_d         = 1'b1;
             s0_cid_d           = admin_cmd_cpl_cmdid;
             s0_cid_par_d       = admin_cmd_cpl_cmdid_par;
             s0_cmd_d           = CMD_CPL_ADMIN[7:0];
             s0_length_d        = admin_cmd_cpl_length;
             s0_length_par_d    = admin_cmd_cpl_length_par;
             s0_data_d[14:0]    = admin_cmd_cpl_status;
             s0_data_d[63:32]   = admin_cmd_cpl_data;           
             cmd_admin_cpl_ack  = 1'b1;
          end
        else if( wdata_valid_q & ~s5_admin_backpressure & ~s0_wdata_stall)
          begin
             s0_valid_d   = 1'b1;
             s0_cid_d     = wdata_cid_q;
             s0_cmd_d     = CMD_WDATA_ERR[7:0]; 
             s0_cid_par_d = wdata_cid_par_q;
             wdata_taken  = 1'b1;                      
          end
        else if( (| s0_rr_gnt) )
          begin
             // round robin priority for all other requests
             s0_rr_d      = s0_rr_gnt;
             s0_rr_gnt_d  = s0_rr_gnt;                         
             s0_valid_d   = 1'b1;
             
             if( s0_rr_gnt[rr_req] )
               begin
                  s0_cid_d = {zero[cid_width-1:tag_width], req_tag_q};
                  s0_cid_par_d = {1'b1, req_tag_par_q};
                  case(req_cmd_q)
                    FCP_GSCSI_RD:  s0_cmd_d = CMD_RD[7:0];
                    FCP_GSCSI_WR:  s0_cmd_d = CMD_WR[7:0];
                    FCP_ABORT:     s0_cmd_d = CMD_ABORT[7:0];
                    FCP_TASKMAN:   s0_cmd_d = CMD_TASKMAN[7:0];
                    default:       s0_cmd_d = CMD_INVALID[7:0];
                  endcase
                  s0_reloff_d      = zero[datalen_width-1:0];
                  s0_length_d      = req_length_q;
                  s0_length_par_d  = req_length_par_q;
                  s0_data_d        = req_cdb_q;
                  s0_data_par_d    = req_cdb_par_q;
               end

             if( s0_rr_gnt[rr_ioq] )
               begin
                  s0_cid_d         = ioq_sntl_cpl_cmdid;
                  s0_cid_par_d     = ioq_sntl_cpl_cmdid_par;  
                  s0_cmd_d         = CMD_CPL_IOQ[7:0];
                  s0_data_d[14:0]  = ioq_sntl_cpl_status;
               end

             if( s0_rr_gnt[rr_debug] )
               begin
                  s0_cid_d = {zero[cid_width-1:tag_width],regs_cmd_trk_addr};
                  s0_cid_par_d ={1'b1,regs_cmd_trk_addr_par};
               end

             if( s0_rr_gnt[rr_iord] )
               begin
                  s0_cid_d                     = s5_iord_fifo_data;
                  s0_cid_par_d                 = s5_iord_fifo_data_par;
                  s0_cmd_d                     = CMD_RDQ[7:0];
               end
             
             if( s0_rr_gnt[rr_iowr] )
               begin
                  s0_cid_d                     = s5_iowr_fifo_data;
                  s0_cid_par_d                 = s5_iowr_fifo_data_par;
                  s0_cmd_d                     = CMD_WRQ[7:0];
                  s0_data_d[wbufid_width-1:0]  = s5_iowr_wbufid;
               end       
             
             if( s0_rr_gnt[rr_wbuf] )
               begin
                  s0_cid_d                     = wbuf_cmd_status_cid;
                  s0_cid_par_d                 = wbuf_cmd_status_cid_par;
                 if( wbuf_cmd_status_error )
                    begin
                       s0_cmd_d                = CMD_WRBUF_ERR[7:0];
                    end
                  else
                    begin
                       s0_cmd_d                = CMD_WRBUF[7:0];
                    end
                  s0_data_d[wbufid_width-1:0]  = wbuf_cmd_status_wbufid;
                  s0_data_par_d                = wbuf_cmd_status_wbufid_par;
                  cmd_wbuf_status_ready        = 1'b1;
               end

             if( s0_rr_gnt[rr_unmap] )
               begin
                  s0_cid_d                     = unmap_cmd_cid;
                  s0_cid_par_d                 = unmap_cmd_cid_par;
                  case(unmap_cmd_event)                    
                    4'h0:  
                      begin
                         s0_cmd_d                     = CMD_UNMAP_WBUF;
                         s0_data_d[wbufid_width-1:0]  = unmap_cmd_wbufid;
                         s0_data_par_d                = unmap_cmd_wbufid_par;
                         s0_data_d[39:32]             = unmap_cmd_reloff;
                      end
                    4'h1:
                      begin
                         s0_cmd_d                     = CMD_UNMAP_IOQ;
                         s0_data_d[wbufid_width-1:0]  = unmap_cmd_wbufid;
                         s0_data_par_d                = unmap_cmd_wbufid_par;
                         s0_data_d[39:32]             = unmap_cmd_reloff;
                      end
                    4'h2:
                      begin
                         s0_cmd_d              = CMD_UNMAP_CPL;
                         s0_data_d[14:0]       = unmap_cmd_cpl_status;
                      end                    
                    default:
                      s0_cmd_d                 = CMD_UNMAP_ERR;
                  endcase                             
               end             
          end // if ( (| s0_rr_gnt) &&...


     end // always @ *   

   //-------------------------------------------------------
   // stage 1
   //-------------------------------------------------------

   // arbitration results
   always @*
     begin        
        req_taken                = s0_rr_gnt_q[rr_req];
        sntl_ioq_cpl_ack         = s0_rr_gnt_q[rr_ioq];
        s1_debug_ack_d           = s0_rr_gnt_q[rr_debug];
        s5_iowr_fifo_taken       = s0_rr_gnt_q[rr_iowr];
        s5_iord_fifo_taken       = s0_rr_gnt_q[rr_iord];     
        cmd_unmap_ack            = s0_rr_gnt_q[rr_unmap];

        cmd_admin_lunlu_valid    = s0_rr_gnt_q[rr_req];
        cmd_admin_lunlu_idx      = s0_lun_q[lunidx_width+47:48];
        cmd_admin_lunlu_idx_par  = s0_lun_par_q;
     end
   
   
   // tracking table read input
   always @*
     begin
        trk_rdaddr       = s0_cid_q[trk_awidth-1:0];
        trk_rdaddr_par   = s0_cid_par_q[0]; 
        
        s1_valid_d       = s0_valid_q;
        s1_cid_d         = s0_cid_q;
        s1_cid_par_d     = s0_cid_par_q; 
        s1_cmd_d         = s0_cmd_q;           
        s1_reloff_d      = s0_reloff_q;
        s1_length_d      = s0_length_q;
        s1_length_par_d  = s0_length_par_q; 
        s1_lun_d         = s0_lun_q;
        s1_lun_par_d     = s0_lun_par_q;
        s1_data_d        = s0_data_q;      
        s1_data_par_d    = s0_data_par_q;   

        s1_trk_wrdata_d  = trk_wrdata;
        s1_trk_write_d   = trk_write;
        s1_trk_wraddr_d  = trk_wraddr;
     end
   

   //-------------------------------------------------------
   // stage 2
   //-------------------------------------------------------
   // - tracking table read output valid
 
   always @*
     begin
        s2_valid_d       = s1_valid_q;
        s2_cid_d         = s1_cid_q;
        s2_cid_par_d     = s1_cid_par_q; 
        s2_cmd_d         = s1_cmd_q;           
        s2_reloff_d      = s1_reloff_q;
        s2_length_d      = s1_length_q;
        s2_length_par_d  = s1_length_par_q;
        s2_lun_d         = s1_lun_q;
        s2_lun_par_d     = s1_lun_par_q;
        s2_data_d        = s1_data_q;        
        s2_data_par_d    = s1_data_par_q;     
        s2_reloffp_d     = s1_reloff_q + s1_length_q;
        s2_debug_ack_d   = s1_debug_ack_q;

        // forward writes from following stages
        if( s4_trk_write_q &&
            s4_trk_wraddr_q == s1_cid_q[trk_awidth-1:0] )
          begin
             s2_trk_data_d = s4_trk_wrdata_q;
          end
        else if( s1_trk_write_q &&
                 s1_trk_wraddr_q == s1_cid_q[trk_awidth-1:0] )
          begin
             s2_trk_data_d = s1_trk_wrdata_q;
          end
        else          
          begin
             s2_trk_data_d = trk_rddata;
          end

        cmd_regs_trk_ack = s2_debug_ack_q;
        cmd_regs_trk_data = {zero[511:trk_width], s2_trk_data_q};
     end



   reg    [63:0] s2_cdb_lba_q, s2_cdb_lba_d;                         // 4K logical block address
   reg    [31:0] s2_cdb_transfer_length_q;
   reg    [31:0] s2_cdb_transfer_length_d;  // 4K blocks
   reg     [7:0] s2_cdb_control_q,s2_cdb_control_d;
   reg     [2:0] s2_cdb_protect_q,s2_cdb_protect_d;
   reg           s2_cdb_dpo_q, s2_cdb_dpo_d;
   reg           s2_cdb_fua_q,s2_cdb_fua_d;
   reg           s2_cdb_fua_nv_q,s2_cdb_fua_nv_d;
   reg     [7:0] s2_cdb_opcode_q;
   reg     [7:0] s2_cdb_opcode_d;
   reg           s2_cdb_anchor_q,s2_cdb_anchor_d;
   reg           s2_cdb_unmap_q,s2_cdb_unmap_d;   
   reg           s2_cdb_ndob_q,s2_cdb_ndob_d;
   
   reg           s2_cdb_op_rd_q;
   reg           s2_cdb_op_wr_q;
   reg           s2_cdb_op_wrlong_q;
   reg           s2_cdb_op_wrsame_q;
   reg           s2_cdb_op_admin_q;
   reg           s2_cdb_op_adminwr_q;
   reg           s2_cdb_op_rd_d;
   reg           s2_cdb_op_wr_d;
   reg           s2_cdb_op_wrlong_d;
   reg           s2_cdb_op_wrsame_d;
   reg           s2_cdb_op_admin_d;
   reg           s2_cdb_op_adminwr_d;

   
   reg           s2_cdb_op_ilun_q,s2_cdb_op_ilun_d;
   reg           s2_cdb_op_unsup_q,s2_cdb_op_unsup_d;
   reg           s2_cdb_op_error_q,s2_cdb_op_error_d;
   
   reg    [63:0] s2_lunlu_numlba_q, s2_lunlu_numlba_d;
   reg           s2_chk_acaactive_q, s2_chk_acaactive_d;
   reg           s2_chk_lunid_err_q, s2_chk_lunid_err_d;
   reg           s2_chk_length_zero_q, s2_chk_length_zero_d;
   reg           s2_chk_length_max_q;
   reg           s2_chk_length_max_d;
   reg           s2_chk_resid_over_q;
   reg           s2_chk_resid_over_d;
   reg [31+12:0] s2_chk_resid_q,s2_chk_resid_d;
   reg           s2_chk_length_error_q;
   reg           s2_chk_length_error_d;
   reg           s2_chk_cdb_error_q;
   reg           s2_chk_cdb_error_d;
   reg           s2_chk_lunreset_d, s2_chk_lunreset_q;
   
   reg    [31:0] s2_nsid_q, s2_nsid_d;
   reg           s2_blksize_q, s2_blksize_d;



   always @(posedge clk)
     begin
        s2_cdb_op_rd_q           <= s2_cdb_op_rd_d;
        s2_cdb_op_wr_q           <= s2_cdb_op_wr_d;
        s2_cdb_op_wrlong_q       <= s2_cdb_op_wrlong_d;
        s2_cdb_op_wrsame_q       <= s2_cdb_op_wrsame_d;
        s2_cdb_op_admin_q        <= s2_cdb_op_admin_d;
        s2_cdb_op_adminwr_q      <= s2_cdb_op_adminwr_d;
        s2_cdb_op_ilun_q         <= s2_cdb_op_ilun_d;
        s2_cdb_op_unsup_q        <= s2_cdb_op_unsup_d;
        s2_cdb_op_error_q        <= s2_cdb_op_error_d;                                                                  
        s2_cdb_lba_q             <= s2_cdb_lba_d;
        s2_cdb_protect_q         <= s2_cdb_protect_d;
        s2_cdb_dpo_q             <= s2_cdb_dpo_d;           
        s2_cdb_fua_q             <= s2_cdb_fua_d;            
        s2_cdb_fua_nv_q          <= s2_cdb_fua_nv_d;
        s2_cdb_opcode_q          <= s2_cdb_opcode_d;
        s2_cdb_anchor_q          <= s2_cdb_anchor_d;
        s2_cdb_unmap_q           <= s2_cdb_unmap_d;
        s2_cdb_ndob_q            <= s2_cdb_ndob_d;
        s2_cdb_transfer_length_q <= s2_cdb_transfer_length_d;
        s2_cdb_control_q         <= s2_cdb_control_d;    
        s2_lunlu_numlba_q        <= s2_lunlu_numlba_d;
        s2_chk_acaactive_q       <= s2_chk_acaactive_d;
        s2_chk_lunid_err_q       <= s2_chk_lunid_err_d;
        s2_chk_length_zero_q     <= s2_chk_length_zero_d;
        s2_chk_length_max_q      <= s2_chk_length_max_d;
        s2_chk_resid_over_q      <= s2_chk_resid_over_d;
        s2_chk_resid_q           <= s2_chk_resid_d;
        s2_chk_length_error_q    <= s2_chk_length_error_d;
        s2_chk_cdb_error_q       <= s2_chk_cdb_error_d;
        s2_nsid_q                <= s2_nsid_d;
        s2_blksize_q             <= s2_blksize_d;
        s2_chk_lunreset_q        <= s2_chk_lunreset_d;
     end
   
   // decode CDB
   reg [7:0] s1_cdb_byte0, s1_cdb_byte1, s1_cdb_byte2, s1_cdb_byte3,
             s1_cdb_byte4, s1_cdb_byte5, s1_cdb_byte6, s1_cdb_byte7,
             s1_cdb_byte8, s1_cdb_byte9, s1_cdb_byte10, s1_cdb_byte11,
             s1_cdb_byte12, s1_cdb_byte13, s1_cdb_byte14, s1_cdb_byte15;
   always @*
     begin
        
        s2_cdb_op_rd_d            = 1'b0;
        s2_cdb_op_wr_d            = 1'b0;
        s2_cdb_op_wrlong_d        = 1'b0;
        s2_cdb_op_wrsame_d        = 1'b0;
        s2_cdb_op_admin_d         = 1'b0;
        s2_cdb_op_adminwr_d       = 1'b0;
        s2_cdb_op_ilun_d          = 1'b0;
        s2_cdb_op_unsup_d         = 1'b0;
        s2_cdb_op_error_d         = 1'b0;
        
        s2_cdb_lba_d              = zero[63:0];
        s2_cdb_protect_d          = 3'b000;
        s2_cdb_dpo_d              = 1'b0;
        s2_cdb_fua_d              = 1'b0;
        s2_cdb_fua_nv_d           = 1'b0;
        s2_cdb_transfer_length_d  = zero[31:0];
        s2_cdb_control_d          = zero[7:0];
        s2_cdb_anchor_d           = 1'b0;
        s2_cdb_unmap_d            = 1'b0;
        s2_cdb_ndob_d             = 1'b0;

        { s1_cdb_byte0,s1_cdb_byte1,s1_cdb_byte2,s1_cdb_byte3,
          s1_cdb_byte4,s1_cdb_byte5,s1_cdb_byte6,s1_cdb_byte7,
          s1_cdb_byte8,s1_cdb_byte9,s1_cdb_byte10,s1_cdb_byte11,
          s1_cdb_byte12,s1_cdb_byte13,s1_cdb_byte14,s1_cdb_byte15 } = s1_data_q;
        
        s2_cdb_opcode_d = s1_cdb_byte0;
        
        // SCSI commands handled in IOQ:
        // - Read(6|10|12|16)      
        // - Write(6|10|12|16)
        // 
        // SCSI commands handled in Admin Q
        // - INQUIRY
        // - MODE SENSE(6|10)
        // - READ CAPACITY(10|16) (SCSI_SERVICE_ACTION_IN)
        // - REPORT_LUNS
        // - Start Stop Unit               
        // - LOG SENSE
        // - Format UNIT
        // - Mode Select(6|10)
        // - Write Buffer        
        
        // SCSI commands not supported (at least intially):
        // - Write Long(10|16)    
        // - SYNCH CACHE(10|16)
        // - Request Sense
        //      

        // decode CDB "Group Code" to get control byte
        case(s1_cdb_byte0[7:5])
          3'h0: s2_cdb_control_d = s1_cdb_byte5;  
          3'h1: s2_cdb_control_d = s1_cdb_byte9;  
          3'h2: s2_cdb_control_d = s1_cdb_byte9;  
          3'h3: s2_cdb_control_d = s1_cdb_byte1;  
          3'h4: s2_cdb_control_d = s1_cdb_byte15;  
          3'h5: s2_cdb_control_d = s1_cdb_byte11;  
          3'h6: s2_cdb_control_d = zero[7:0];  
          3'h7: s2_cdb_control_d = zero[7:0]; 
        endcase // case (s1_cdb_byte0[7:5])
        
        
        case(s1_cdb_byte0) 
          SCSI_READ_6:
            begin
               s2_cdb_lba_d              = {zero[63:21], s1_cdb_byte1[4:0], s1_cdb_byte2, s1_cdb_byte3};
               s2_cdb_protect_d          = 3'b000;
               s2_cdb_dpo_d              = 1'b0;
               s2_cdb_fua_d              = 1'b0;
               s2_cdb_fua_nv_d           = 1'b0;
               s2_cdb_transfer_length_d  = {zero[31:8], s1_cdb_byte4};
               s2_cdb_control_d          = s1_cdb_byte5;
               s2_cdb_op_rd_d            = ~i_localmode & s1_valid_q;
               s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
            end               
          SCSI_READ_10:
            begin
               s2_cdb_lba_d              = {zero[63:32], s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5};                   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];
               s2_cdb_dpo_d              = s1_cdb_byte1[4];
               s2_cdb_fua_d              = s1_cdb_byte1[3];
               s2_cdb_fua_nv_d           = s1_cdb_byte1[1];
               s2_cdb_transfer_length_d  = {zero[31:16],s1_cdb_byte7, s1_cdb_byte8};
               s2_cdb_control_d          = s1_cdb_byte9;
               s2_cdb_op_rd_d            = ~i_localmode & s1_valid_q;
               s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
            end
          SCSI_READ_12:
            begin
               s2_cdb_lba_d              = {zero[63:32], s1_cdb_byte2, s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5};                   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];
               s2_cdb_dpo_d              = s1_cdb_byte1[4];
               s2_cdb_fua_d              = s1_cdb_byte1[3];
               s2_cdb_fua_nv_d           = s1_cdb_byte1[1];
               s2_cdb_transfer_length_d  = {s1_cdb_byte6, s1_cdb_byte7, s1_cdb_byte8, s1_cdb_byte9 };
               s2_cdb_control_d          = s1_cdb_byte11;
               s2_cdb_op_rd_d            = ~i_localmode & s1_valid_q;
               s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
            end
          SCSI_READ_16:
            begin
               s2_cdb_lba_d              = {s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5, s1_cdb_byte6, s1_cdb_byte7, s1_cdb_byte8, s1_cdb_byte9};   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];
               s2_cdb_dpo_d              = s1_cdb_byte1[4];
               s2_cdb_fua_d              = s1_cdb_byte1[3];
               s2_cdb_fua_nv_d           = s1_cdb_byte1[1];
               s2_cdb_transfer_length_d  = {s1_cdb_byte10, s1_cdb_byte11, s1_cdb_byte12, s1_cdb_byte13 };
               s2_cdb_control_d          = s1_cdb_byte15;
               s2_cdb_op_rd_d            = ~i_localmode & s1_valid_q;
               s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
            end
          SCSI_WRITE_6:
            begin
               s2_cdb_lba_d              = {zero[63:21], s1_cdb_byte1[4:0], s1_cdb_byte2, s1_cdb_byte3};
               s2_cdb_protect_d          = 3'b000;
               s2_cdb_dpo_d              = 1'b0;
               s2_cdb_fua_d              = 1'b0;
               s2_cdb_fua_nv_d           = 1'b0;
               s2_cdb_transfer_length_d  = {zero[31:8], s1_cdb_byte4};
               s2_cdb_control_d          = s1_cdb_byte5;
               s2_cdb_op_wr_d            = ~i_localmode & s1_valid_q;
               s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
            end               
          SCSI_WRITE_10:
            begin
               s2_cdb_lba_d              = {zero[63:32], s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5};                   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];
               s2_cdb_dpo_d              = s1_cdb_byte1[4];
               s2_cdb_fua_d              = s1_cdb_byte1[3];
               s2_cdb_fua_nv_d           = s1_cdb_byte1[1];
               s2_cdb_transfer_length_d  = {zero[31:16],s1_cdb_byte7, s1_cdb_byte8};
               s2_cdb_control_d          = s1_cdb_byte9;
               s2_cdb_op_wr_d            = ~i_localmode & s1_valid_q;
               s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
            end
          SCSI_WRITE_12:
            begin
               s2_cdb_lba_d              = {zero[63:32], s1_cdb_byte2, s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5};                   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];
               s2_cdb_dpo_d              = s1_cdb_byte1[4];
               s2_cdb_fua_d              = s1_cdb_byte1[3];
               s2_cdb_fua_nv_d           = s1_cdb_byte1[1];
               s2_cdb_transfer_length_d  = {s1_cdb_byte6, s1_cdb_byte7, s1_cdb_byte8, s1_cdb_byte9 };
               s2_cdb_control_d          = s1_cdb_byte11;
               s2_cdb_op_wr_d            = ~i_localmode & s1_valid_q;
               s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
            end
          SCSI_WRITE_16:
            begin
               s2_cdb_lba_d              = {s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5, s1_cdb_byte6, s1_cdb_byte7, s1_cdb_byte8, s1_cdb_byte9};   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];
               s2_cdb_dpo_d              = s1_cdb_byte1[4];
               s2_cdb_fua_d              = s1_cdb_byte1[3];
               s2_cdb_fua_nv_d           = s1_cdb_byte1[1];
               s2_cdb_transfer_length_d  = {s1_cdb_byte10, s1_cdb_byte11, s1_cdb_byte12, s1_cdb_byte13 };
               s2_cdb_control_d          = s1_cdb_byte15;
               s2_cdb_op_wr_d            = ~i_localmode & s1_valid_q;
               s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
            end
          SCSI_WRITE_SAME:
            begin
               s2_cdb_lba_d              = {zero[63:32], s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5};                   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];          
               s2_cdb_anchor_d           = s1_cdb_byte1[4];
               s2_cdb_unmap_d            = s1_cdb_byte1[3];
               s2_cdb_transfer_length_d  = {zero[31:16],s1_cdb_byte7, s1_cdb_byte8};
               s2_cdb_control_d          = s1_cdb_byte9;   
               if( s2_cdb_unmap_d | s2_cdb_anchor_d )
                 begin                    
                    s2_cdb_op_unsup_d         = s1_valid_q;
                 end
               else
                 begin
                    s2_cdb_op_wrsame_d        = s1_valid_q;
                 end
            end

          SCSI_WRITE_SAME_16:
            begin
               s2_cdb_lba_d              = {s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5, s1_cdb_byte6, s1_cdb_byte7, s1_cdb_byte8, s1_cdb_byte9};   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];             
               s2_cdb_anchor_d           = s1_cdb_byte1[4];
               s2_cdb_unmap_d            = s1_cdb_byte1[3];
               s2_cdb_ndob_d             = s1_cdb_byte1[0];
               s2_cdb_transfer_length_d  = {s1_cdb_byte10, s1_cdb_byte11, s1_cdb_byte12, s1_cdb_byte13 };
               s2_cdb_control_d          = s1_cdb_byte15;
               if( s2_cdb_anchor_d )
                 begin                    
                    s2_cdb_op_unsup_d         = s1_valid_q;
                 end
               else
                 begin
                    s2_cdb_op_wrsame_d        = s1_valid_q;
                 end
            end

          SCSI_SERVICE_ACTION_OUT:
            begin
               // service action 0x11 == WRITE_LONG_16
               // SNTL 5.9, SBC-3 5.42
               s2_cdb_lba_d              = {s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5, s1_cdb_byte6, s1_cdb_byte7, s1_cdb_byte8, s1_cdb_byte9}; 
               s2_cdb_transfer_length_d  = {s1_cdb_byte10, s1_cdb_byte11, s1_cdb_byte12, s1_cdb_byte13 };
               s2_cdb_control_d          = s1_cdb_byte9;
               if( s1_cdb_byte1[7]==1'b1 &&  // COR_DIS
                   s1_cdb_byte1[6]==1'b1 &&  // WR_UNCOR
                   s1_cdb_byte1[5]==1'b0 &&  // PBLOCK
                   s1_cdb_byte1[4:0] == 5'h11 ) // service action
                 begin
                    s2_cdb_op_wrlong_d        = ~i_localmode & s1_valid_q;
                    s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
                 end
               else
                 begin
                    s2_cdb_op_unsup_d         = s1_valid_q;
                 end
            end
          
          SCSI_WRITE_LONG:
            begin
               // SNTL 5.9, SBC-3 5.41
               s2_cdb_lba_d              = {zero[63:32], s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5};                   
               s2_cdb_transfer_length_d  = {zero[31:16],s1_cdb_byte7, s1_cdb_byte8};
               s2_cdb_control_d          = s1_cdb_byte9;
               if( s1_cdb_byte1[7]==1'b1 &&  // COR_DIS
                   s1_cdb_byte1[6]==1'b1 &&  // WR_UNCOR
                   s1_cdb_byte1[5]==1'b0 )   // PBLOCK
                 begin
                    s2_cdb_op_wrlong_d        = ~i_localmode & s1_valid_q;
                    s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
                 end
               else
                 begin
                    s2_cdb_op_unsup_d         = s1_valid_q;
                 end
            end          

          SCSI_WRITE_AND_VERIFY:
            begin
               s2_cdb_lba_d              = {zero[63:32], s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5};                   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];
               s2_cdb_dpo_d              = s1_cdb_byte1[4];
               s2_cdb_transfer_length_d  = {zero[31:16],s1_cdb_byte7, s1_cdb_byte8};
               s2_cdb_control_d          = s1_cdb_byte9;

               // bytchk field - either 0 or 1 may be used. 
               if( s1_cdb_byte1[2:1] == 2'b00 ||  s1_cdb_byte1[2:1] == 2'b01)
                 begin
                    s2_cdb_op_wr_d            = ~i_localmode & s1_valid_q;
                    s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
                 end
               else
                 begin
                    s2_cdb_op_unsup_d   = s1_valid_q;
                 end               
            end

          SCSI_WRITE_AND_VERIFY_16:
            begin
               s2_cdb_lba_d              = {s1_cdb_byte2,s1_cdb_byte3, s1_cdb_byte4, s1_cdb_byte5, s1_cdb_byte6, s1_cdb_byte7, s1_cdb_byte8, s1_cdb_byte9};   
               s2_cdb_protect_d          = s1_cdb_byte1[7:5];
               s2_cdb_dpo_d              = s1_cdb_byte1[4];
               s2_cdb_transfer_length_d  = {s1_cdb_byte10, s1_cdb_byte11, s1_cdb_byte12, s1_cdb_byte13 };
               s2_cdb_control_d          = s1_cdb_byte15;
               if( s1_cdb_byte1[2:1] == 2'b00 ||  s1_cdb_byte1[2:1] == 2'b01 )
                 begin
                    s2_cdb_op_wr_d            = ~i_localmode & s1_valid_q;
                    s2_cdb_op_ilun_d          = i_localmode & s1_valid_q;
                 end
               else
                 begin
                    s2_cdb_op_unsup_d   = s1_valid_q;
                 end               
            end

          
          SCSI_INQUIRY,
            SCSI_REPORT_LUNS,
            SCSI_READ_CAPACITY,
            SCSI_SERVICE_ACTION_IN,
            SCSI_FORMAT_UNIT,
            SCSI_LOG_SENSE,
            SCSI_MODE_SENSE,
            SCSI_MODE_SENSE_10,
            SCSI_MODE_SELECT,
            SCSI_MODE_SELECT_10,
            SCSI_TEST_UNIT_READY,
            8'hC0:    // NVMe passthru - vendor opcodes
              begin
                 // commands implemented in microcode
                 s2_cdb_op_admin_d  = ~i_localmode & s1_valid_q;
                 s2_cdb_op_ilun_d   = i_localmode & s1_valid_q;                 
              end
          
          SCSI_WRITE_BUFFER,
            SCSI_UNMAP,
            8'hC1:  // NVMe passthru - vendor opcodes
              begin
                 // write commands implemented in microcode
                 s2_cdb_op_adminwr_d  = ~i_localmode & s1_valid_q;
                 s2_cdb_op_ilun_d   = i_localmode & s1_valid_q;
              end
          
          
          default:
            begin
               s2_cdb_lba_d              = zero[63:0];
               s2_cdb_protect_d          = 3'b000;
               s2_cdb_dpo_d              = 1'b0;
               s2_cdb_fua_d              = 1'b0;
               s2_cdb_fua_nv_d           = 1'b0;
               s2_cdb_transfer_length_d  = zero[31:0];
               s2_cdb_control_d          = zero[7:0];      
               s2_cdb_op_unsup_d         = s1_valid_q;
            end
        endcase // case (s1_cdb_byte0)                                  


        
        
        // CDB checking for read or write operations

        // zero length read or write - don't send to NVMe
        s2_chk_length_zero_d  = (s2_cdb_transfer_length_d==zero[31:0]);
        
        //  max transfer size is lesser of:
        //  - 16M sislite limit (datalen_width parameter)
        //  - NVMe single I/O op limit - 16b number of blocks field x 512b blocks = 32M 
        //  - NMVe "Maximum Data Transfer Size (MDTS)" from Identify Controller Data Structure (NVMe 1.1b page 88)
        //  regs_xx_maxxfer is set by microcontroller to max number of 4K blocks
        //  sislite will always be 4K blocks (based on REPORT_LUNs response)
        //  if requested length is > max, return "Invalid Field in Command" status
        s2_chk_length_max_d   = (s2_cdb_transfer_length_d > {zero[31:maxxfer_width],regs_xx_maxxfer});

        // check for cdb transfer length > sislite length (FCP_DL)
        // see fcp4 9.4.2b - return check condition with no data transfer if requesting more data in CDB than the SCSI Data-In/Out buffer size.
        // error code is INVALID FIELD in Command Information Unit
        // for this case, the resid_over bit in the response must be set and according to fcp 9.5.12, resid = (cdb transfer length - FCP_DL)        
        s2_chk_resid_over_d   = ( {s2_cdb_transfer_length_d , 12'h000} >           // convert 4K blocks to bytes
                                  {zero[31+12:datalen_width], s1_length_q} ); // length is in bytes
        s2_chk_resid_d        = ( {s2_cdb_transfer_length_d, 12'h000} - {zero[31+12:datalen_width], s1_length_q} );

        s2_chk_length_error_d = s2_chk_length_zero_d |
                                s2_chk_length_max_d |
                                s2_chk_resid_over_d;

        // check for other errors in CDB
        // only fields for read or write commands checked here
        // other commands handled by microcontroller are checked separately
        // should check s2_cdb_protect here
        // s2_chk_cdb_error_d  = s2_cdb_control_q[2];  // NACA bit - NVMe SCSI translation spec 1.5 section 3.3.  Return ILLEGAL FIELD IN CDB
        s2_chk_cdb_error_d = s2_cdb_control_q[2] & disable_aca;

        // stall new requests if there's a lun reset in the pipe
        s2_chk_lunreset_d = s1_valid_q && !disable_lun_reset &&
                            s1_cmd_q == CMD_TASKMAN && 
                            s1_cdb_byte0 == SISL_TMF_LUNRESET;
        s2_chk_lunreset = s2_chk_lunreset_q;
     end       


   reg s1_lunlu_err;
   always @*
     begin

        s1_lunlu_err = 1'b0;
        
        // translate LUN to namespace id - see SAM-5 4.7
        // report_luns will only return address method=0b00 or 0b01
        // set nsid=0xffffffff for any other LUN

        // handles max of 255 LUNs
        
        case(s1_lun_q[63:62])
          2'b00:
            begin              
               // 8b LUNid in bits 55:48
               if( s1_lun_q[61:lunidx_width+48]!=zero[61:lunidx_width+48] ||
                   s1_lun_q[61:56]!=zero[61:56])
                 s1_lunlu_err = 1'b1;               
            end
          2'b01:
            begin
               // 14b LUNid in bits 61:48
               if( s1_lun_q[61:lunidx_width+48]!=zero[61:lunidx_width+48])
                 s1_lunlu_err = 1'b1;   
            end
          default:
            begin
               s1_lunlu_err = 1'b1;
            end
        endcase // case (s1_lun_q[63:62])

        
        // invalid LUNid or namespace block size
        if( s1_lunlu_err ||
            !((admin_cmd_lunlu_lbads == 8'h9) || (admin_cmd_lunlu_lbads == 8'hC)))
          begin
             s2_nsid_d           = 32'hFFFFFFFF;
             s2_blksize_d        = 1'b0;
             s2_chk_acaactive_d  = 1'b0;  // not a valid LUN
             s2_chk_lunid_err_d  = 1'b1;
          end
        else
          begin
             s2_nsid_d           = admin_cmd_lunlu_nsid;
             s2_blksize_d        = admin_cmd_lunlu_lbads == 8'hC; // 0xC=2^12 = 4K
             s2_chk_acaactive_d  = admin_cmd_lunlu_status;
             s2_chk_lunid_err_d  = 1'b0;
          end

        s2_lunlu_numlba_d = admin_cmd_lunlu_numlba;
        
        
     end        


   
   //-------------------------------------------------------
   // stage 3
   //-------------------------------------------------------




   reg              [63:0] s3_cdb_lba_q, s3_cdb_lba_d;                         // 4K logical block address
   reg              [31:0] s3_cdb_transfer_length_q;
   reg              [31:0] s3_cdb_transfer_length_d;  // 4K blocks
   reg               [7:0] s3_cdb_control_q,s3_cdb_control_d;
   reg               [2:0] s3_cdb_protect_q,s3_cdb_protect_d;
   reg                     s3_cdb_dpo_q, s3_cdb_dpo_d;
   reg                     s3_cdb_fua_q,s3_cdb_fua_d;
   reg                     s3_cdb_fua_nv_q,s3_cdb_fua_nv_d;
   reg               [7:0] s3_cdb_opcode_q;
   reg               [7:0] s3_cdb_opcode_d;
   reg                     s3_cdb_anchor_q,s3_cdb_anchor_d;
   reg                     s3_cdb_unmap_q,s3_cdb_unmap_d;   
   reg                     s3_cdb_ndob_q,s3_cdb_ndob_d;
   
   reg                     s3_cdb_op_rd_q;
   reg                     s3_cdb_op_wr_q;
   reg                     s3_cdb_op_wrlong_q;
   reg                     s3_cdb_op_wrsame_q;
   reg                     s3_cdb_op_admin_q;
   reg                     s3_cdb_op_adminwr_q;
   reg                     s3_cdb_op_rd_d;
   reg                     s3_cdb_op_wr_d;
   reg                     s3_cdb_op_wrlong_d;
   reg                     s3_cdb_op_wrsame_d;
   reg                     s3_cdb_op_admin_d;
   reg                     s3_cdb_op_adminwr_d;
   reg                     s3_cdb_op_ilun_q,s3_cdb_op_ilun_d;
   reg                     s3_cdb_op_unsup_q,s3_cdb_op_unsup_d;
   reg                     s3_cdb_op_error_q,s3_cdb_op_error_d;
   
   reg                     s3_chk_lbarange_q, s3_chk_lbarange_d;
   reg                     s3_chk_length_zero_q, s3_chk_length_zero_d;
   reg                     s3_chk_length_max_q;
   reg                     s3_chk_length_max_d;
   reg                     s3_chk_resid_over_q;
   reg                     s3_chk_resid_over_d;
   reg           [31+12:0] s3_chk_resid_q,s3_chk_resid_d;
   reg                     s3_chk_length_error_q;
   reg                     s3_chk_length_error_d;
   reg                     s3_chk_cdb_error_q;
   reg                     s3_chk_cdb_error_d;
   reg                     s3_chk_acaactive_q, s3_chk_acaactive_d;
   reg                     s3_chk_lunid_err_q, s3_chk_lunid_err_d;
   
   reg              [31:0] s3_nsid_q, s3_nsid_d;
   reg                     s3_blksize_q, s3_blksize_d;

   reg                     s3_errinj_lba_q, s3_errinj_lba_d;
   reg                     s3_errinj_lookup_q, s3_errinj_lookup_d;
   reg              [15:0] s3_errinj_status_q, s3_errinj_status_d;

   reg              [63:0] s3_ioq_lba_q, s3_ioq_lba_d;
   reg              [15:0] s3_ioq_numblks_q, s3_ioq_numblks_d;
   reg              [63:0] s3_upd_lba_q, s3_upd_lba_d;
   reg [datalen_width-1:0] s3_upd_reloff_q, s3_upd_reloff_d;
   reg [datalen_width-1:0] s3_upd_resid_q, s3_upd_resid_d;
   reg                     s3_upd_resid_zero_q, s3_upd_resid_zero_d;
   reg                     s3_upd_xfer_done_q, s3_upd_xfer_done_d;
   
   reg                     s3_reloff_eq_length_q, s3_reloff_eq_length_d; 
   reg [datalen_width-1:0] s3_length_m_reloff_q, s3_length_m_reloff_d; 
   reg                     s3_instcnt_match_q,s3_instcnt_match_d;
   reg                     s3_iotimer_elapsed_q, s3_iotimer_elapsed_d;

   always @(posedge clk)
     begin        
        s3_cdb_op_rd_q           <= s3_cdb_op_rd_d;
        s3_cdb_op_wr_q           <= s3_cdb_op_wr_d;
        s3_cdb_op_wrlong_q       <= s3_cdb_op_wrlong_d;
        s3_cdb_op_wrsame_q       <= s3_cdb_op_wrsame_d;
        s3_cdb_op_admin_q        <= s3_cdb_op_admin_d;
        s3_cdb_op_adminwr_q      <= s3_cdb_op_adminwr_d;
        s3_cdb_op_ilun_q         <= s3_cdb_op_ilun_d;
        s3_cdb_op_unsup_q        <= s3_cdb_op_unsup_d;
        s3_cdb_op_error_q        <= s3_cdb_op_error_d;                                                                  
        s3_cdb_lba_q             <= s3_cdb_lba_d;
        s3_cdb_protect_q         <= s3_cdb_protect_d;
        s3_cdb_dpo_q             <= s3_cdb_dpo_d;           
        s3_cdb_fua_q             <= s3_cdb_fua_d;            
        s3_cdb_fua_nv_q          <= s3_cdb_fua_nv_d;
        s3_cdb_opcode_q          <= s3_cdb_opcode_d;
        s3_cdb_anchor_q          <= s3_cdb_anchor_d;
        s3_cdb_unmap_q           <= s3_cdb_unmap_d;
        s3_cdb_ndob_q            <= s3_cdb_ndob_d;
        s3_cdb_transfer_length_q <= s3_cdb_transfer_length_d;
        s3_cdb_control_q         <= s3_cdb_control_d;    
        s3_chk_lbarange_q        <= s3_chk_lbarange_d;
        s3_chk_length_zero_q     <= s3_chk_length_zero_d;
        s3_chk_length_max_q      <= s3_chk_length_max_d;
        s3_chk_resid_over_q      <= s3_chk_resid_over_d;
        s3_chk_resid_q           <= s3_chk_resid_d;
        s3_chk_length_error_q    <= s3_chk_length_error_d;
        s3_chk_cdb_error_q       <= s3_chk_cdb_error_d;
        s3_chk_acaactive_q       <= s3_chk_acaactive_d;
        s3_chk_lunid_err_q       <= s3_chk_lunid_err_d;
        s3_nsid_q                <= s3_nsid_d;
        s3_blksize_q             <= s3_blksize_d;
        s3_errinj_lba_q          <= s3_errinj_lba_d;
        s3_errinj_lookup_q       <= s3_errinj_lookup_d;
        s3_errinj_status_q       <= s3_errinj_status_d;
        s3_ioq_lba_q             <= s3_ioq_lba_d;
        s3_ioq_numblks_q         <= s3_ioq_numblks_d;
        s3_upd_lba_q             <= s3_upd_lba_d;
        s3_upd_reloff_q          <= s3_upd_reloff_d;
        s3_upd_resid_q           <= s3_upd_resid_d;
        s3_upd_resid_zero_q      <= s3_upd_resid_zero_d;
        s3_upd_xfer_done_q       <= s3_upd_xfer_done_d;
        s3_reloff_eq_length_q    <= s3_reloff_eq_length_d;
        s3_length_m_reloff_q     <= s3_length_m_reloff_d;
        s3_instcnt_match_q       <= s3_instcnt_match_d;
        s3_iotimer_elapsed_q     <= s3_iotimer_elapsed_d;     
     end


   always @*
     begin
        s3_cdb_op_rd_d           = s2_cdb_op_rd_q;
        s3_cdb_op_wr_d           = s2_cdb_op_wr_q;
        s3_cdb_op_wrlong_d       = s2_cdb_op_wrlong_q;
        s3_cdb_op_wrsame_d       = s2_cdb_op_wrsame_q;
        s3_cdb_op_admin_d        = s2_cdb_op_admin_q;
        s3_cdb_op_adminwr_d      = s2_cdb_op_adminwr_q;
        s3_cdb_op_ilun_d         = s2_cdb_op_ilun_q;
        s3_cdb_op_unsup_d        = s2_cdb_op_unsup_q;
        s3_cdb_op_error_d        = s2_cdb_op_error_q;                                                                  
        s3_cdb_lba_d             = s2_cdb_lba_q;
        s3_cdb_protect_d         = s2_cdb_protect_q;
        s3_cdb_dpo_d             = s2_cdb_dpo_q;           
        s3_cdb_fua_d             = s2_cdb_fua_q;            
        s3_cdb_fua_nv_d          = s2_cdb_fua_nv_q;
        s3_cdb_opcode_d          = s2_cdb_opcode_q;
        s3_cdb_anchor_d          = s2_cdb_anchor_q;
        s3_cdb_unmap_d           = s2_cdb_unmap_q;
        s3_cdb_ndob_d            = s2_cdb_ndob_q;
        s3_cdb_transfer_length_d = s2_cdb_transfer_length_q;
        s3_cdb_control_d         = s2_cdb_control_q;    
        s3_chk_length_zero_d     = s2_chk_length_zero_q;
        s3_chk_length_max_d      = s2_chk_length_max_q;
        s3_chk_resid_over_d      = s2_chk_resid_over_q;
        s3_chk_resid_d           = s2_chk_resid_q;
        s3_chk_length_error_d    = s2_chk_length_error_q;
        s3_chk_cdb_error_d       = s2_chk_cdb_error_q;
        s3_nsid_d                = s2_nsid_q;
        s3_blksize_d             = s2_blksize_q;
        s3_chk_acaactive_d       = s2_chk_acaactive_q;
        s3_chk_lunid_err_d	 = s2_chk_lunid_err_q;
     end

   // unpack tracking table entry
   always @*
     begin     
        { s2_trk_rd_sqid,
          s2_trk_rd_lunidx,
          s2_trk_rd_xferlen,
          s2_trk_rd_wbufid,
          s2_trk_rd_instcnt,
          s2_trk_rd_length,
          s2_trk_rd_reloff,
          s2_trk_rd_opcode,
          s2_trk_rd_state,
          s2_trk_rd_tstamp1,
          s2_trk_rd_tstamp1d,
          s2_trk_rd_tstamp2,
          s2_trk_rd_debug,
          s2_trk_rd_lba,
          s2_trk_rd_nsid,
          s2_trk_rd_blksize,
          s2_trk_rd_status } = s2_trk_data_q;
     end

   reg [34:0] s3_transfer_length_m1;
   always @*
     begin
        s3_valid_d             = s2_valid_q;
        s3_trk_data_d          = s2_trk_data_q;
        s3_cid_d               = s2_cid_q;
        s3_cid_par_d           = s2_cid_par_q; 
        s3_cmd_d               = s2_cmd_q;
        s3_reloff_d            = s2_reloff_q;
        s3_length_d            = s2_length_q;
        s3_length_par_d        = s2_length_par_q;
        s3_reloffp_d           = s2_reloffp_q;
        s3_lun_d               = s2_lun_q;
        s3_lun_par_d           = s2_lun_par_q;
        s3_data_d              = s2_data_q;            
        s3_data_par_d          = s2_data_par_q;         


        // for timing, do some add/subtract/compares in this stage
        s3_reloff_eq_length_d  = s2_trk_rd_reloff == s2_trk_rd_length;
        s3_length_m_reloff_d   = s2_trk_rd_length - s2_trk_rd_reloff;
        s3_instcnt_match_d     = s2_trk_rd_instcnt==s2_cid_q[15:tag_width];
        s3_iotimer_elapsed_d   = (regs_xx_timer2[15:0] - s2_trk_rd_tstamp2[15:0]) > regs_cmd_IOtimeout2[15:0];        
        
        // check for (lba + cdb_transfer_length) >= number of lbas
        s3_chk_lbarange_d = (s2_cdb_lba_q + {zero[63:32],s2_cdb_transfer_length_q}) > s2_lunlu_numlba_q; 

        // next lba calc
        s3_transfer_length_m1  = {s2_trk_rd_xferlen, 3'b000} - one[maxxfer_width-1+3:0];

        // new requests
        // sislite uses 4k block size. Currently supported NVMe part only supports 512B block size
        // use lookup table result to allow for future 4K NVMe block size
        // NVMe uses "0-based" value for number of blocks. SCSI uses actual number of blocks 
        // calculate number of NVMe 512B blocks based on SCSI 4K blocks
        if( s2_trk_rd_blksize )
          begin
             // 4K block size
             // all other block sizes will be treated as invalid
             s3_ioq_lba_d      = s2_trk_rd_lba;             
             s3_ioq_numblks_d  = s3_transfer_length_m1[18:3];
          end
        else
          begin
             // translate 4K blocks size in request to 512B blocks in IOQ
             s3_ioq_lba_d     = { s2_trk_rd_lba[60:0], 3'b000 };
             s3_ioq_numblks_d = s3_transfer_length_m1[15:0];
          end

        // write requests - update reloff (bytes) and next lba=starting lba + new reloff(blocks)
        s3_upd_reloff_d      = s2_trk_rd_reloff + sisl_block_size[datalen_width-1:0];      
        if( s2_trk_rd_state == TRK_ST_WRSAME )
          begin
             // tracking entry doesn't get updated until the next I/O write is sent, so use updated reloff to calc lba
             s3_upd_lba_d         = s2_trk_rd_lba + s3_upd_reloff_d[datalen_width-1:sisl_block_width];
          end
        else
          begin
             // READ - trk_rd_reloff gets updated as payload is sent to sntl_rsp
             // WRITE/WRITE_AND_VERIFY - trk_rd_reloff gets updated when next 4K block is read
             s3_upd_lba_d         = s2_trk_rd_lba + s2_trk_rd_reloff[datalen_width-1:sisl_block_width];
          end        
        
        s3_upd_resid_zero_d  = s3_upd_reloff_d == s2_trk_rd_length;
        s3_upd_resid_d       = s2_trk_rd_length - s3_upd_reloff_d;

        if( ~s2_trk_rd_blksize )
          begin
             s3_upd_lba_d = { s3_upd_lba_d[60:0], 3'b000 }; // convert to 512b blocksize
          end
        
        if( s2_trk_rd_state==TRK_ST_RD )
          begin
             s3_upd_xfer_done_d = s2_trk_rd_reloff[datalen_width-1:sisl_block_width]==s2_trk_rd_xferlen;
          end
        else
          begin
             s3_upd_xfer_done_d = s3_upd_reloff_d[datalen_width-1:sisl_block_width]==s2_trk_rd_xferlen;
          end

     end


   // error injection
   reg errinj_lba_hit;
   always @*
     begin
        errinj_lba_hit = ~regs_cmd_errinj_uselba ||
                         ((regs_cmd_errinj_lba >= s2_cdb_lba_q) && 
                          (regs_cmd_errinj_lba < (s2_cdb_lba_q +  {zero[63:32],s2_cdb_transfer_length_q})));

        // inject on a specific lba
        s3_errinj_lba_d = regs_cmd_errinj_valid &&
                          errinj_lba_hit &&
                          ((regs_cmd_errinj_select==4'h1 && s2_cdb_op_wr_q) ||
                           (regs_cmd_errinj_select==4'h2 && s2_cdb_op_rd_q));
        s3_errinj_status_d = regs_cmd_errinj_status;

        // inject to cause dma lookup error status
        s3_errinj_lookup_d = regs_cmd_errinj_valid &&                          
                             ((regs_cmd_errinj_select==4'hA && s2_cmd_q==CMD_WR_LOOKUP) ||
                              (regs_cmd_errinj_select==4'hB && s2_cmd_q==CMD_RD_LOOKUP));

        cmd_regs_errinj_ack = s3_errinj_lba_q | s3_errinj_lookup_q;
        cmd_regs_errinj_cmdrd = s3_cdb_op_rd_q;
        cmd_regs_errinj_cmdwr = s3_cdb_op_wr_q;
     end
   
   //-------------------------------------------------------
   // stage 4
   //-------------------------------------------------------
   // - set up tracking table write data
   
   // unpack tracking table entry
   always @*
     begin     
        { s3_trk_rd_sqid,
          s3_trk_rd_lunidx,
          s3_trk_rd_xferlen,
          s3_trk_rd_wbufid,
          s3_trk_rd_instcnt,
          s3_trk_rd_length,
          s3_trk_rd_reloff,
          s3_trk_rd_opcode,
          s3_trk_rd_state,
          s3_trk_rd_tstamp1,
          s3_trk_rd_tstamp1d,
          s3_trk_rd_tstamp2,
          s3_trk_rd_debug,
          s3_trk_rd_lba,
          s3_trk_rd_nsid,
          s3_trk_rd_blksize,
          s3_trk_rd_status } = s3_trk_data_q;
        
        s3_trk_rd_wbufid_par = 1'b0;
     end
   
   
   reg [35:0] s4_tstamp1_delta;
   
   // update tracking table entry, output to request or response fifo
   always @*
     begin
        // status fifo controls

        s4_rsp_push_d         = 1'b0;
        s4_rsp_status_d       = { 5'h0, NVME_SCT_GENERIC, NVME_SC_G_SUCCESS };
        s4_rsp_tag_d          = s3_cid_q[tag_width-1:0]; 
        s4_rsp_tag_par_d      = s3_cid_par_q[0]; 
        s4_rsp_resid_under_d  = 1'b0;
        s4_rsp_resid_over_d   = 1'b0;
        s4_rsp_resid_d        = zero[31:0]; 
        s4_rsp_data_d         = zero[31:0]; 
        s4_rsp_flush_d        = 1'b0;
        s4_rsp_passthru_d     = 1'b0;
        s4_rsp_lunidx_d       = ~zero[lunidx_width-1:0];
        s4_rsp_naca_d         = 1'b0;
        
        // tracking table controls
        s4_trk_wraddr_d       = s3_cid_q[tag_width-1:0];
        s4_trk_wraddr_par_d   = s3_cid_par_q[0];
        s4_trk_write_d        = 1'b0;
        s4_trk_wr_sqid        = s3_trk_rd_sqid;
        s4_trk_wr_lunidx      = s3_trk_rd_lunidx;
        s4_trk_wr_xferlen     = s3_trk_rd_xferlen;
        s4_trk_wr_wbufid      = s3_trk_rd_wbufid;
        s4_trk_wr_instcnt     = s3_trk_rd_instcnt;
        s4_trk_wr_length      = s3_trk_rd_length;
        s4_trk_wr_reloff      = s3_trk_rd_reloff;
        s4_trk_wr_opcode      = s3_trk_rd_opcode;
        s4_trk_wr_state       = s3_trk_rd_state;
        s4_trk_wr_debug       = s3_trk_rd_debug;
        s4_trk_wr_lba         = s3_trk_rd_lba;
        s4_trk_wr_nsid        = s3_trk_rd_nsid;
        s4_trk_wr_blksize     = s3_trk_rd_blksize;
        s4_trk_wr_status      = s3_trk_rd_status;

        // timestamps for latency and timeout 
        s4_trk_wr_tstamp1     = s3_trk_rd_tstamp1;  // initial request time 
        s4_tstamp1_delta      = (regs_xx_timer1[35:0] - s3_trk_rd_tstamp1);
        if( s4_tstamp1_delta[35:20]==16'b0 ) 
          s4_trk_wr_tstamp1d  = s4_tstamp1_delta[19:0];
        else
          s4_trk_wr_tstamp1d  = 20'hFFFFF;  // overflow
        s4_trk_wr_tstamp2     = s3_trk_rd_tstamp2;
        
        
        s4_debug_freeze_d     = (s4_debug_freeze_q & regs_cmd_debug[0]) | regs_cmd_debug[1];

        // queue for writes
        s4_iowr_push_d        = 1'b0;
        iowr_completed        = 1'b0;


        // queue for reads
        s4_iord_push_d        = 1'b0;
        iord_completed        = 1'b0;
        
        // unmap module interface
        s4_unmap_req_valid_d  = 1'b0;
        s4_unmap_cpl_valid_d  = 1'b0;
        s4_unmap_status_d     = s3_data_q[14:0];
       
        // IOQ command request fifo controls default values
        s4_ioq_sqid_ack_d     = 1'b0;        
        s4_ioq_push_d         = 1'b0;
        if( s3_cdb_op_rd_q )
          begin
             s4_ioq_opcode_d  = NVME_IO_READ;
          end
        else if( s3_cdb_op_wrlong_q )
          begin
             s4_ioq_opcode_d  = NVME_IO_WRITE_UNCORR;
          end
        else
          begin             
             s4_ioq_opcode_d  = NVME_IO_WRITE;
          end
        
        s4_ioq_lba_d                 = s3_ioq_lba_q;  
        s4_ioq_numblks_d             = s3_ioq_numblks_q;               
        s4_ioq_nsid_d                = s3_trk_rd_nsid;
        // s4_ioq_cmdid_d            = *set after event processing*
        s4_ioq_wbufid_d              = s3_trk_rd_wbufid;
        s4_ioq_reloff_d              = s3_trk_rd_reloff;
        s4_ioq_fua_d                 = s3_cdb_fua_q;
        s4_ioq_sqid_d                = ioq_sntl_sqid;
        sntl_ioq_sqid_ack            = s4_ioq_sqid_ack_q;
        sntl_ioq_sqid                = s4_ioq_sqid_q;
        
        // interface for commands that need microcode
        s4_admin_push_d              = 1'b0;
        s4_admin_cmd_d               = s3_cmd_q; 
        s4_admin_lun_d               = s3_lun_q;  
        s4_admin_lun_par_d           = s3_lun_par_q;  
        s4_admin_length_d            = s3_length_q;
         s4_admin_cdb_d               = s3_data_q;
        s4_admin_cdb_par_d           = s3_data_par_q;   
        // s4_admin_cid_d - set after tracking table
        
        // DMA lookup results
        s4_dma_valid_d               = 1'b0;
        s4_dma_error_d               = 1'b0;
        cmd_dma_error                = s4_dma_error_q;
        cmd_dma_valid                = s4_dma_valid_q;

        s4_wbuf_push_d               = 1'b0;
        s4_wbuf_unmap_d              = 1'b0;
        s4_wbuf_cmdid_d              = s3_cid_q;
        s4_wbuf_cmdid_par_d          = s3_cid_par_q;  
        s4_wbuf_reloff_d             = zero[datalen_width-1:0]; // first 4K block
        s4_wbuf_lba_d                = s3_ioq_lba_q;  
        s4_wbuf_numblks_d            = s3_ioq_numblks_q;               
        s4_wbuf_wbufid_d             = s3_data_q[wbufid_width-1:0];  // newly allocated wbufid
        s4_wbuf_wbufid_par_d         = s3_data_par_q[wbufid_par_width-1:0];  // 

        s4_wbuf_idfree_valid_d       = 1'b0;
        s4_wbuf_idfree_wbufid_d      = s3_data_q[wbufid_width-1:0];
        s4_wbuf_idfree_wbufid_par_d  = s3_data_par_q[wbufid_width-1:0];
        cmd_wbuf_idfree_valid        = s4_wbuf_idfree_valid_q;
        cmd_wbuf_idfree_wbufid       = s4_wbuf_idfree_wbufid_q;
        cmd_wbuf_idfree_wbufid_par   = s4_wbuf_idfree_wbufid_par_q;

        cmd_admin_lunlu_clraca       = 1'b0;
        cmd_admin_lunlu_clraca_idx   = s3_lun_q[lunidx_width+47:48];

        s4_checker_lunreset          = 1'b0;
        s4_checker_lunreset_tag      = s3_cid_q[tag_width-1:0]; 
        s4_checker_lunreset_tag_par  = s3_cid_par_q[0];

        s4_events_d                  = 32'h0;
        
        // process event
        case( s3_cmd_q )
          CMD_RD, 
          CMD_WR:
            begin
               // sislite request
               s4_trk_wr_sqid                = zero[isq_idwidth-1:0];
               s4_trk_wr_lunidx              = s3_lun_q[lunidx_width+47:48];
               s4_trk_wr_xferlen             = s3_cdb_transfer_length_q[maxxfer_width-1:0];
               s4_trk_wr_wbufid              = ~zero[wbufid_width-1:0];
               s4_trk_wr_instcnt             = s3_trk_rd_instcnt + 8'h1;
               s4_trk_wr_length              = s3_length_q[datalen_width-1:0];
               s4_trk_wr_reloff              = zero[datalen_width-1:0];
               s4_trk_wr_opcode              = s3_cdb_opcode_q;                       
               s4_trk_wr_debug               = zero[trkdbg_width-1:0];
               s4_trk_wr_debug[EX_DBG_RD]    = s3_cmd_q==CMD_RD;
               s4_trk_wr_debug[EX_DBG_WR]    = s3_cmd_q==CMD_WR;
               s4_trk_wr_debug[EX_DBG_FUA]   = s3_cdb_fua_q;
               s4_trk_wr_debug[EX_DBG_NACA]  = s3_cdb_control_q[2];
               s4_trk_wr_tstamp1             = regs_xx_timer1[35:0];
               s4_trk_wr_tstamp1d            = zero[19:0];
               s4_trk_wr_tstamp2             = regs_xx_timer2[15:0];
               s4_trk_wr_lba                 = s3_cdb_lba_q;
               s4_trk_wr_nsid                = s3_nsid_q;
               s4_trk_wr_blksize             = s3_blksize_q;
               s4_trk_wr_status              = zero[14:0];
               
               if( ctl_xx_ioq_enable == 1'b0)
                 begin
                    // do not write tracking entry for this status (didn't check current state)
                    s4_rsp_push_d     = 1'b1;
                    s4_rsp_status_d   = { 5'h0, NVME_SCT_SISLITE,  NVME_SC_S_NOT_READY };                                
                 end
               else if( ctl_xx_shutdown == 1'b1 )
                 begin
                    s4_rsp_push_d     = 1'b1;
                    s4_rsp_status_d   = { 5'h0, NVME_SCT_SISLITE,  NVME_SC_S_SHUTDOWN };                                                     
                 end               
               else if( ctl_xx_csts_rdy == 1'b0 )
                 begin
                    s4_rsp_push_d     = 1'b1;
                    s4_rsp_status_d   = { 5'h0, NVME_SCT_SISLITE,  NVME_SC_S_NOT_READY };                                                                   
                 end
               else if( s3_trk_rd_state != TRK_ST_IDLE )
                 begin                    
                    // tracking entry already in use - return error and don't write entry
                    s4_rsp_push_d     = 1'b1;
                    s4_rsp_status_d   = { 5'h0, NVME_SCT_SISLITE,  NVME_SC_S_ID_CONFLICT };                    
                 end                 
               else
                 begin
                    // entry is IDLE - write new command info
                    s4_trk_write_d  = 1'b1;

                    if( s3_chk_acaactive_q && !disable_aca )
                      begin
                         s4_rsp_push_d                    = 1'b1;
                         s4_rsp_status_d                  = { 5'h0, NVME_SCT_SISLITE,  NVME_SC_S_ACAACTIVE };
                         s4_rsp_resid_d                   = { zero[31:datalen_width], s3_length_q};
                         s4_rsp_resid_under_d             = (|s3_length_q);
                         s4_trk_wr_debug[EX_DBG_STATERR]  = 1'b1;
                         s4_trk_wr_status                 = s4_rsp_status_d;       
                      end                    
                    else if( s3_cdb_op_rd_q | s3_cdb_op_wr_q )
                      begin

                         if( s3_chk_length_error_q )
                           begin
                              s4_rsp_push_d                     = 1'b1;
                              s4_rsp_status_d                   = { 5'h0, NVME_SCT_GENERIC,  NVME_SC_G_INVALID_FIELD };
                              
                              if( s3_chk_resid_over_q )
                                begin
                                   s4_rsp_resid_d                  = s3_chk_resid_q[31:0];
                                   s4_rsp_resid_over_d             = 1'b1;
                                   s4_rsp_status_d                 = { 5'h0, NVME_SCT_SISLITE,  NVME_SC_S_INVALID_FIELD };
                                   s4_debug_freeze_d               = regs_cmd_debug[2];
                                   s4_trk_wr_debug[EX_DBG_LENERR]  = 1'b1;
                                end
                              else
                                begin
                                   // length>max or zero
                                   s4_rsp_resid_d                  = { zero[31:datalen_width], s3_length_q};
                                   s4_rsp_resid_under_d            = (|s3_length_q);
                                   s4_trk_wr_debug[EX_DBG_LENERR]  = 1'b1;
                                end
                              
                              if( s3_chk_length_zero_q )
                                begin
                                   // return success for zero length                              
                                   s4_rsp_status_d = { 5'h0, NVME_SCT_GENERIC,  NVME_SC_G_SUCCESS };
                                end    

                              s4_trk_wr_status  = s4_rsp_status_d;
                           end
                         else if ( s3_chk_lbarange_q )
                           begin
                              // check LBA range before sending to NVMe because we're round the namespace size to 32MB
                              s4_rsp_push_d                   = 1'b1;
                              s4_rsp_status_d                 = { 5'h0, NVME_SCT_GENERIC,  NVME_SC_G_LBA_RANGE };
                              s4_rsp_resid_d                  = { zero[31:datalen_width], s3_length_q};
                              s4_rsp_resid_under_d            = (|s3_length_q);
                              s4_trk_wr_debug[EX_DBG_LENERR]  = 1'b1;
                              s4_trk_wr_status                = s4_rsp_status_d;
                           end
                         else if ( s3_chk_cdb_error_q |
                                   (s3_cdb_protect_q!=3'b000) )
                           begin
                              s4_trk_wr_debug[EX_DBG_CDBERR]  = 1'b1;
                              s4_rsp_push_d                   = 1'b1;
                              s4_rsp_status_d                 = { 5'h0, NVME_SCT_GENERIC,  NVME_SC_G_INVALID_FIELD };
                              s4_rsp_resid_d                  = { zero[31:datalen_width], s3_length_q};
                              s4_rsp_resid_under_d            = (|s3_length_q); 
                              s4_trk_wr_status                = s4_rsp_status_d;
                           end
                         else if ( s3_errinj_lba_q )
                           begin
                              s4_trk_wr_debug[EX_DBG_ERRINJ]  = 1'b1;
                              s4_rsp_push_d                   = 1'b1;
                              s4_rsp_status_d                 = { 1'b0, s3_errinj_status_q[14:0] };
                              if( s3_errinj_status_q[15] )
                                begin
                                   s4_rsp_resid_d             = { zero[31:datalen_width], s3_length_q};
                                   s4_rsp_resid_under_d       = (|s3_length_q);
                                end
                              else
                                begin
                                   s4_rsp_resid_d             = zero[31:0];
                                   s4_rsp_resid_under_d       = 1'b0;
                                end                              
                              s4_trk_wr_status                = s4_rsp_status_d;  
                           end                         
                         else if ( regs_cmd_debug[4] )
                           begin
                              // for latency measurement, skip I/O and return good status
                              s4_trk_wr_debug[EX_DBG_ERRINJ]  = 1'b1;
                              s4_rsp_push_d                   = 1'b1;
                              s4_rsp_status_d                 = 16'h0;                           
                              s4_rsp_resid_d                  = zero[31:0];
                              s4_rsp_resid_under_d            = 1'b0;
                              s4_trk_wr_status                = s4_rsp_status_d;  
                           end
                         else                           
                           begin                               
                              if( s3_cdb_op_rd_q )
                                begin
                                   // send read to ISQ
                                   //s4_trk_wr_state  = TRK_ST_RD;
                                   //s4_ioq_push_d    = 1'b1;
                                   // push read requests into fifo until fifo credits are available
                                   s4_trk_wr_state  = TRK_ST_RDQ;  
                                   s4_iord_push_d   = 1'b1;
                                   s4_events_d[0]   = 1'b1; // IDLE -> RDQ
                                end
                              else
                                begin                                  
                                   // push write requests into fifo until write buffer is available
                                   s4_trk_wr_state  = TRK_ST_WRQ;                                                                    
                                   s4_iowr_push_d   = 1'b1;
                                   s4_events_d[1]   = 1'b1; // IDLE -> WRQ
                                end
                           end
                      end
                    else if( s3_cdb_op_wrlong_q )
                      begin
                         if( s3_blksize_q )
                           begin
                              // namespace has 4K block size
                              s4_ioq_numblks_d  = 0;
                           end
                         else
                           begin
                              // namespace has 512B block size
                              // write_long targets 1 4K logical block, so set numblks=7
                              s4_ioq_numblks_d = 7;
                           end
                         
                         if ( s3_chk_cdb_error_q |
                              (s3_cdb_protect_q!=3'b000) )
                           begin
                              s4_trk_wr_debug[EX_DBG_CDBERR]  = 1'b1;
                              s4_rsp_push_d                   = 1'b1;
                              s4_rsp_status_d                 = { 4'h0, NVME_SCT_GENERIC,  NVME_SC_G_INVALID_FIELD };
                              s4_rsp_resid_d                  = { zero[31:datalen_width], s3_length_q};
                              s4_rsp_resid_under_d            = (|s3_length_q); 
                              s4_trk_wr_status                = s4_rsp_status_d;                            
                           end                    
                         else 
                           begin
                              // send to ISQ.  No write buffer is needed - no data transferred
                              s4_ioq_push_d      = 1'b1;
                              s4_trk_wr_sqid     = ioq_sntl_sqid;
                              s4_ioq_sqid_ack_d  = 1'b1;
                              s4_trk_wr_state    = TRK_ST_WRLONG;
                              s4_trk_wr_xferlen  = 12'd1; // ignore transfer_length, always 1 block
                           end
                      end                                   
                    else if( s3_cdb_op_wrsame_q )
                      begin
                         // WRITE_SAME(10) or WRITE_SAME(16)
                         // cdb fields:
                         //  s3_cdb_unmap_q
                         //  s3_cdb_anchor_q
                         //  s3_cdb_ndob_q
                         // Inquiry VPD fields:
                         //    page 0xB0
                         //    WSNZ=1 write same non-zero - zero transfer length is an error
                         //    max write same length = 16MB
                         //    page 0xB1
                         //    LBPWS=1   - write_same(16) can be used to unmap
                         //    LBPWS10=0 - write_same(10) cannot be used to unmap
                         //    according to SBC-3 5.43, the unmap and anchor bits can be ignored when
                         //    read_capacity LBPME=0.
                         //    added support for unmap => LBPME=1
                         
                         /* send write to queue */
                         /* when first block completes, next block will be written using same buffer */
                         /* trk_xx_xferlen == transfer length in 4K blocks */
                         /* trk_xx_reloff  == current byte offset from starting lba */
                         /* trk_xx_lba     == starting lba in 4K blocks */
                         
                         if( s3_chk_length_zero_q || s2_chk_length_max_q)
                           begin
                              s4_trk_wr_debug[EX_DBG_LENERR]  = 1'b1;
                              s4_rsp_push_d                   = 1'b1;
                              // zero transfer length means "from here to the end of the LUN"
                              // not supported
                              s4_rsp_resid_d                  = { zero[31:datalen_width], s3_length_q};
                              s4_rsp_resid_under_d            = 1'b1;
                              s4_rsp_status_d                 = { 4'h0, NVME_SCT_SISLITE,  NVME_SC_S_INVALID_FIELD };
                              s4_trk_wr_status                = s4_rsp_status_d;                         
                           end
                         else if( (s3_length_q != sisl_block_size[datalen_width-1:0]) & !s3_cdb_unmap_q )
                           begin
                              s4_trk_wr_debug[EX_DBG_LENERR]  = 1'b1;
                              s4_rsp_push_d                   = 1'b1;
                              // write same payload is 1 data block - return error status if length!=4K
                              // if unmap command, no data is transferred so allow s3_length != 4KB
                              s4_rsp_resid_d                  = { zero[31:datalen_width], s3_length_q};
                              s4_rsp_resid_under_d            = 1'b1;
                              s4_rsp_status_d                 = { 4'h0, NVME_SCT_SISLITE,  NVME_SC_S_INVALID_FIELD };
                              s4_trk_wr_status                = s4_rsp_status_d;                         
                           end
                         else if ( s3_chk_cdb_error_q | 
                                   (s3_cdb_ndob_q && !s3_cdb_unmap_q) |
                                   s3_cdb_anchor_q |
                                   (s3_cdb_protect_q!=3'b000) )
                           begin
                              s4_trk_wr_debug[EX_DBG_LENERR]  = 1'b1;
                              s4_rsp_push_d                   = 1'b1;
                              s4_rsp_status_d                 = { 4'h0, NVME_SCT_GENERIC,  NVME_SC_G_INVALID_FIELD };
                              s4_rsp_resid_d                  = { zero[31:datalen_width], s3_length_q};
                              s4_rsp_resid_under_d            = (|s3_length_q); 
                              s4_trk_wr_status                = s4_rsp_status_d;                         
                           end                    
                         else
                           begin                              
                              if( (s3_cdb_ndob_q | regs_cmd_debug[3]) & s3_cdb_unmap_q )
                                begin
                                   // send to unmap module for buffering/combining
                                   // next event: CMD_UNMAP_WBUF
                                   s4_trk_wr_state                = TRK_ST_UNMAPQ;
                                   s4_unmap_req_valid_d           = 1'b1;
                                end
                              else
                                begin
                                   // queue until write buffer is available
                                   s4_trk_wr_state  = TRK_ST_WRQ;
                                   s4_iowr_push_d   = 1'b1;
                                   s4_events_d[13]   = 1'b1; // IDLE -> WRQ wrsame
                                end
                           end
                      end // if ( s3_cdb_op_wrsame_q )
                    
                    else if( s3_cdb_op_admin_q )
                      begin                    
                         s4_trk_wr_state                = TRK_ST_ADMIN;                         
                         s4_trk_wr_debug[EX_DBG_ADMIN]  = 1'b1;                   
                         s4_admin_push_d                = 1'b1;
                      end
                    else if( s3_cdb_op_adminwr_q )
                      begin                    
                         s4_trk_wr_state                = TRK_ST_ADMINWR;
                         s4_trk_wr_debug[EX_DBG_ADMIN]  = 1'b1;                   
                         s4_admin_push_d                = 1'b1;
                      end
                    else
                      begin
                         // error - sislite read or write with unsupported CDB opcode
                         
                         s4_trk_wr_debug[EX_DBG_CDBCHK]  = 1'b1;                   
                         s4_rsp_push_d                   = 1'b1;
                         s4_rsp_resid_d                  = { zero[31:datalen_width], s3_length_q};
                         s4_rsp_resid_under_d            = (|s3_length_q);
                         s4_rsp_status_d                 = { 4'h0, NVME_SCT_SISLITE, NVME_SC_S_NOT_IMPL };
                         s4_trk_wr_status                = s4_rsp_status_d;                         
                      end               
                 end // else: !if( s3_trk_rd_state != TRK_ST_IDLE )               
            end // case: CMD_RD,...

          
          CMD_ABORT,
            CMD_TASKMAN:
              begin
                 if( s3_trk_rd_state != TRK_ST_IDLE )
                   begin                    
                      // tracking entry already in use - return error and don't write entry
                      s4_rsp_push_d    = 1'b1;
                      s4_rsp_status_d  = { 4'h0, NVME_SCT_SISLITE,  NVME_SC_S_ID_CONFLICT };
                   end                 
                 else
                   begin
                      s4_trk_write_d                   = 1'b1;
                      s4_trk_wr_sqid                   = zero[isq_idwidth-1:0];
                      s4_trk_wr_lunidx                 = s3_lun_q[lunidx_width+47:48];
                      s4_trk_wr_xferlen                = zero[maxxfer_width-1:0];
                      s4_trk_wr_wbufid                 = zero[wbufid_width-1:0];
                      s4_trk_wr_instcnt                = s3_trk_rd_instcnt + 8'h1;
                      s4_trk_wr_length                 = s3_length_q[datalen_width-1:0];
                      s4_trk_wr_reloff                 = zero[datalen_width-1:0];
                      s4_trk_wr_opcode                 = s3_cdb_opcode_q;
                      s4_trk_wr_state                  = TRK_ST_ADMIN;
                      s4_trk_wr_debug                  = zero[trkdbg_width-1:0];
                      s4_trk_wr_debug[EX_DBG_TASKMAN]  = s3_cmd_q==CMD_TASKMAN;
                      s4_trk_wr_debug[EX_DBG_NACA]     = s3_cdb_control_q[2];
                      s4_trk_wr_tstamp1                = regs_xx_timer1[35:0];
                      s4_trk_wr_tstamp1d               = zero[19:0];
                      s4_trk_wr_tstamp2                = regs_xx_timer2[15:0];
                      s4_trk_wr_lba                    = s3_cdb_lba_q;
                      s4_trk_wr_nsid                   = s3_nsid_q;
                      s4_trk_wr_blksize                = s3_blksize_q;
                      s4_trk_wr_status                 = zero[14:0];
                    
                      if( s3_cmd_q == CMD_TASKMAN && s3_cdb_opcode_q == SISL_TMF_CLEARACA && !disable_aca)
                        begin
                           s4_trk_wr_state             = TRK_ST_IDLE;
                           // handle ClearACA without microcode - just clear the flag and return good status
                           if( s3_chk_lunid_err_q )
                             begin
                                // send error response
                                s4_rsp_push_d    = 1'b1;
                                s4_rsp_status_d  = { 4'h0, NVME_SCT_SISLITE,  NVME_SC_S_TMF_LUN };                               
                             end
                           else
                             begin
                                // clear ACA bit and send good response
                                cmd_admin_lunlu_clraca = 1'b1;
                                s4_rsp_push_d    = 1'b1;
                                s4_rsp_status_d  = { 4'h0, NVME_SCT_SISLITE,  NVME_SC_S_TMF_COMP };                                
                             end
                           s4_trk_wr_status = s4_rsp_status_d;
                        end
                      else if( s3_cmd_q == CMD_TASKMAN && s3_cdb_opcode_q == SISL_TMF_LUNRESET && !disable_aca)
                        begin
                           
                           // handle lun reset with checker state machine
                           if( s3_chk_lunid_err_q )
                             begin
                                // send error response                                
                                s4_rsp_push_d    = 1'b1;
                                s4_rsp_status_d  = { 4'h0, NVME_SCT_SISLITE,  NVME_SC_S_TMF_LUN };
                                s4_trk_wr_status = s4_rsp_status_d;
                             end
                           else
                             begin
                                // activate checker state machine
                                s4_checker_lunreset = 1'b1;
                                s4_trk_wr_state     = TRK_ST_LUNRESET;
                             end                           
                        end
                      else
                        begin
                           // send all other TMF to microcode
                           s4_admin_push_d                  = 1'b1;
                        end
                   end
              end
          
          CMD_RD_LOOKUP:
            begin
               // DMA read for ADMIN command (doesn't use write buffer)
               // - check reloff/length vs request length
               // - increment tracking table reloff by number of bytes requested.  
           
               
               s4_trk_wr_tstamp2  = regs_xx_timer2[15:0];
               s4_dma_valid_d     = 1'b1;
               if(  (s3_trk_rd_state != TRK_ST_ADMINWR) ||
                    ~s3_instcnt_match_q)
                 begin
                    // tracking entry doesn't match the request
                    s4_dma_error_d = 1'b1;
                 end
               else
                 begin
                    s4_trk_write_d  = 1'b1;               
                    if( s3_reloffp_q > s3_trk_rd_length )
                      begin
                         // attempt to read out of bounds
                         s4_dma_error_d   = 1'b1;
                         s4_trk_wr_state  = TRK_ST_WRERR;
                      end
                    else if( s3_reloff_eq_length_q ||
                             s3_errinj_lookup_q )
                      begin
                         // already transferred the requested length of data                         
                         s4_dma_error_d   = 1'b1;
                         s4_trk_wr_state  = TRK_ST_WRERR;
                      end
                    else
                      begin                               
                         s4_trk_wr_reloff  = s3_trk_rd_reloff + s3_length_q;
                         s4_dma_error_d    = 1'b0;
                      end
                 end                 
            end
          
          CMD_WR_LOOKUP:
            begin
               // DMA write - check reloff/length vs request length
               // save number of bytes transferred

               s4_trk_wr_tstamp2  = regs_xx_timer2[15:0];
               s4_dma_valid_d     = 1'b1;
               
               if( (s3_trk_rd_state != TRK_ST_RD) ||
                   ~s3_instcnt_match_q)
                 begin
                    // tracking entry doesn't match the request
                    s4_dma_error_d = 1'b1;
                 end
               else
                 begin
                    s4_trk_write_d  = 1'b1;               
                    if( s3_reloffp_q > s3_trk_rd_length ||
                        s3_errinj_lookup_q )
                      begin
                         // attempt to write out of bounds
                         s4_dma_error_d   = 1'b1;
                         s4_trk_wr_state  = TRK_ST_RDERR;
                         s4_events_d[2]   = 1'b1; // RD -> RDERR
                      end
                    else
                      begin                               
                         s4_dma_error_d    = 1'b0;
                         s4_trk_wr_reloff  = s3_trk_rd_reloff + s3_length_q;
                      end
                 end
            end

          CMD_WDATA_ERR:
            begin
               // if DMA for ADMIN write payload returned an error, put into error state
               // when the admin command completes, return error status
               if( s3_trk_rd_state == TRK_ST_ADMINWR )
                 begin
                    s4_trk_write_d                    = 1'b1;                                   
                    s4_trk_wr_state                   = TRK_ST_WRERR;
                    s4_trk_wr_debug[EX_DBG_WDATAERR]  = 1'b1;                
                 end
            end          

          CMD_RDQ:
            begin
               // issue read request to ISQ

               s4_trk_wr_tstamp2              = regs_xx_timer2[15:0];
               // issue read for 4K to ISQ
               s4_ioq_opcode_d                = NVME_IO_READ;         
               s4_ioq_lba_d                   = s3_upd_lba_q;  // starting lba + reloff converted to blocks
               s4_ioq_numblks_d               = (s3_trk_rd_blksize) ? 0 : 7;               
               s4_ioq_nsid_d                  = s3_trk_rd_nsid;              
               s4_ioq_fua_d                   = s3_trk_rd_debug[EX_DBG_FUA];
               s4_trk_wr_sqid                 = ioq_sntl_sqid;
               
               s4_trk_wr_state                = TRK_ST_RD;
               s4_trk_wr_debug[EX_DBG_IORDQ]  = 1'b1;  // track number of reads outstanding
               s4_events_d[3]                 = 1'b1; // RDQ exit
               
               if( s3_trk_rd_state!=TRK_ST_RDQ || 
                   ~s3_instcnt_match_q )
                 begin
                    // while queued, the tracking entry was updated possibly by a timeout
                    iord_completed            = 1'b1;  // don't count this read as outstanding
                 end
               else
                 begin
                    s4_ioq_push_d   = 1'b1;
                    s4_ioq_sqid_ack_d  = 1'b1;
                    s4_trk_write_d  = 1'b1;
                    s4_events_d[4]  = 1'b1;  // RDQ -> RD 
                 end
            end
          
          
          CMD_WRQ:
            begin
               // WRITE, WRITE_SAME, WRITE_AND_VERIFY has a buffer allocated for the 1st 4K block
               // now issue request to wbuf to fetch the data

               s4_trk_wr_tstamp2              = regs_xx_timer2[15:0];
               s4_trk_wr_state                = TRK_ST_WRBUF;
               s4_trk_wr_wbufid               = s3_data_q[wbufid_width-1:0];  // newly allocated buffer id
               s4_trk_wr_debug[EX_DBG_IOWRQ]  = 1'b1;  // used to track number of writes outstanding and wbuf in use
               s4_events_d[5]                 = 1'b1; // WRQ exit
               if( s3_trk_rd_state != TRK_ST_WRQ ||
                   ~s3_instcnt_match_q )
                 begin
                    // while queued, the tracking entry was updated possibly by a timeout
                    iowr_completed            = 1'b1;  // don't count this write as outstanding
                    s4_wbuf_idfree_valid_d    = 1'b1; // free write buffer that was just allocated                    
                 end
               else
                 begin
                    s4_wbuf_push_d   = 1'b1;    
                    s4_trk_write_d   = 1'b1;
                    s4_events_d[6]   = 1'b1; // WRQ -> WRBUF
                 end
            end
         
          
          CMD_UNMAP_WBUF,
            CMD_UNMAP_IOQ:
            begin
               // UNMAP has a write buffer - send lba/range/offset info to wbuf
             
               s4_trk_wr_tstamp2              = regs_xx_timer2[15:0];
               if( s3_cmd_q == CMD_UNMAP_WBUF )
                 begin
                    s4_trk_wr_state                = TRK_ST_UNMAPBUF;                    
                 end
               else
                 begin
                    // this cmdid is used to send the datamanagement request
                    s4_trk_wr_state                = TRK_ST_UNMAPBREQ;                    
                 end
               s4_trk_wr_wbufid               = s3_data_q[wbufid_width-1:0];  // newly allocated buffer id
               s4_trk_wr_reloff[7:0]          = s3_data_q[39:32];             // offset into wbuf for this lba range
               s4_trk_wr_debug[EX_DBG_UNMAP]  = 1'b1;  // unmap wbufid is valid
               
               if( s3_trk_rd_state != TRK_ST_UNMAPQ ||
                   ~s3_instcnt_match_q )
                 begin
                    // 
                 end
               else
                 begin
                    s4_wbuf_push_d   = 1'b1;    
                    s4_wbuf_unmap_d  = 1'b1;
                    s4_wbuf_reloff_d = s3_data_q[39:32];      
                    s4_trk_write_d   = 1'b1;                                 
                 end
            end 
          
          CMD_WRBUF:
            begin
               // good status received from write buffer
               // data is ready in the buffer, so issue NVMe I/O command
               
               s4_trk_wr_tstamp2  = regs_xx_timer2[15:0];
               // issue write for 4K to ISQ
              
               s4_ioq_nsid_d      = s3_trk_rd_nsid;              
               s4_ioq_fua_d       = s3_trk_rd_debug[EX_DBG_FUA];
               s4_events_d[7]   = 1'b1;  // WRBUF exit
               
               if(  s3_trk_rd_state == TRK_ST_UNMAPBUF )
                 begin
                    // unmap write to buffer complete, now wait for completion
                    
                    s4_trk_wr_state    = TRK_ST_UNMAPIOQ2;
                    if( ~s3_instcnt_match_q )
                      begin                    
                         // 
                      end              
                    else
                      begin
                         s4_trk_write_d   = 1'b1;                         
                      end    
                 end
               else if( s3_trk_rd_state == TRK_ST_UNMAPBREQ )
                 begin
                    // unmap write to buffer complete, now send request to ioq and wait for completion                                       
                    // issue request to ISQ
                    s4_ioq_opcode_d    = NVME_IO_DATASET;                       
                    s4_ioq_numblks_d   = {zero[31:8],s3_trk_rd_reloff[7:0]};  // number of lba ranges - 1                   
                    s4_trk_wr_sqid     = ioq_sntl_sqid;
                    s4_trk_wr_state    = TRK_ST_UNMAPIOQ;
                    
                    if( ~s3_instcnt_match_q )
                      begin                    
                         //
                      end              
                    else
                      begin
                         s4_trk_write_d   = 1'b1;
                         s4_ioq_push_d    = 1'b1;
                         s4_ioq_sqid_ack_d  = 1'b1;
                      end               
                 end
               else
                 begin
                    s4_ioq_opcode_d    = NVME_IO_WRITE;         
                    s4_ioq_lba_d       = s3_upd_lba_q;  // starting lba + reloff converted to blocks
                    s4_ioq_numblks_d   = (s3_trk_rd_blksize) ? 0 : 7;
                    s4_trk_wr_sqid     = ioq_sntl_sqid;
                    
                    case( s3_trk_rd_opcode )
                      SCSI_WRITE_SAME, 
                      SCSI_WRITE_SAME_16: 
                        begin
                           s4_trk_wr_state  = TRK_ST_WRSAME;                    
                        end
                      SCSI_WRITE_AND_VERIFY,
                        SCSI_WRITE_AND_VERIFY_16:
                          begin
                             s4_trk_wr_state  = TRK_ST_WRVERIFY1;
                          end
                      default:
                        begin
                           s4_trk_wr_state  = TRK_ST_WR;
                        end
                    endcase // case ( s3_trk_rd_opcode )  
                    if( s3_trk_rd_state != TRK_ST_WRBUF ||
                        ~s3_instcnt_match_q )
                      begin                    
                         // free write buffer that was just completed. write buffer field in tracking entry is not valid.
                         s4_wbuf_idfree_valid_d = 1'b1;                                   
                      end
                    else
                      begin
                         s4_trk_write_d   = 1'b1;
                         s4_ioq_push_d    = 1'b1;
                         s4_ioq_sqid_ack_d  = 1'b1;
                         s4_events_d[8]   = 1'b1; // WRBUF -> WR/WRSAME/WRVERIFY
                      end               //              
                 end
                             
            end // case: CMD_WRBUF

          CMD_WRBUF_ERR:
            begin
               // got an error reading data for a write command
               // return error status to sislite
               // a DMA access was out of bounds for the command
               
               s4_rsp_push_d                    = 1'b1;               
               s4_rsp_status_d                  = {NVME_SCT_SISLITE, NVME_SC_S_WRITE_DMA_ERR};      
               s4_rsp_resid_d                   = s3_length_m_reloff_q;
               s4_rsp_resid_under_d             = ~s3_reloff_eq_length_q;
               
               s4_trk_write_d                   = 1'b1;
               s4_trk_wr_state                  = TRK_ST_IDLE;
               s4_trk_wr_status                 = s4_rsp_status_d;              
               s4_trk_wr_debug[EX_DBG_STATERR]  = 1'b1;      

               // free write buffer
               s4_wbuf_idfree_valid_d           = 1'b1; 
               s4_wbuf_idfree_wbufid_d          = s3_trk_rd_wbufid;                                           
               s4_wbuf_idfree_wbufid_par_d      = s3_trk_rd_wbufid_par;                                           
            end



          CMD_UNMAP_CPL:
            begin
               // completion for UNMAP commands that were combined
               s4_trk_wr_tstamp2     = regs_xx_timer2[15:0];                                                                  
               s4_rsp_status_d       = s3_data_q[14:0];                                                                                      
         
                             
               s4_trk_wr_state                  = TRK_ST_IDLE;
               s4_trk_wr_debug[EX_DBG_STATERR]  = s3_data_q[14:0]!=zero[14:0];
               s4_trk_wr_debug[EX_DBG_STATGOOD] = ~s4_trk_wr_debug[EX_DBG_STATERR];
               s4_trk_wr_status                 = s4_rsp_status_d;  

               if( s3_trk_rd_state != TRK_ST_UNMAPIOQ2 ||
                   ~s3_instcnt_match_q )
                 begin                    
                    //
                 end
               else
                 begin
                    s4_trk_write_d  = 1'b1;     
                    s4_rsp_push_d   = 1'b1;
                 end
            end
          
          
          CMD_CPL_IOQ:           
            begin
               // completion received from ICQ
               s4_trk_wr_tstamp2  = regs_xx_timer2[15:0];

               if( s3_instcnt_match_q )
                 begin
                    case(s3_trk_rd_state)
                      TRK_ST_RD:                     
                        begin
                           s4_trk_wr_tstamp2     = regs_xx_timer2[15:0];
                           s4_trk_write_d        = 1'b1;                                                      
                           s4_rsp_status_d       = s3_data_q[14:0];                 
                           s4_rsp_resid_d        = s3_length_m_reloff_q;
                           s4_rsp_resid_under_d  = ~s3_reloff_eq_length_q;

                           s4_ioq_opcode_d    = NVME_IO_READ;         
                           s4_ioq_lba_d       = s3_upd_lba_q;  // starting lba + reloff converted to blocks
                           s4_ioq_reloff_d    = s3_trk_rd_reloff;
                           s4_ioq_numblks_d   = (s3_trk_rd_blksize) ? 0 : 7;               
                           s4_ioq_nsid_d      = s3_trk_rd_nsid;              
                           s4_ioq_fua_d       = s3_trk_rd_debug[EX_DBG_FUA];
                           s4_events_d[9]     = 1'b1; // RD completion
                           
                           // I/O read of 1 4K block is done
                           if( s3_data_q[14:0]==zero[14:0] )
                             begin                              
                                // good status - now check if this was the last block
                                if( s3_upd_xfer_done_q )
                                  begin
                                     s4_rsp_push_d                     = 1'b1;
                                     s4_trk_wr_state                   = TRK_ST_IDLE;
                                     s4_trk_wr_status                  = s4_rsp_status_d;          
                                     s4_trk_wr_debug[EX_DBG_STATGOOD]  = 1'b1;                                  
                                  end
                                else
                                  begin
                                     // next 4K block                       
                                     s4_trk_wr_sqid     = ioq_sntl_sqid;
                                     s4_ioq_push_d      = 1'b1;
                                     s4_ioq_sqid_ack_d  = 1'b1;
                                     s4_events_d[10]    = 1'b1; // RD -> RD
                                  end
                             end
                           else
                             begin
                                // bad status
                                s4_rsp_push_d                     = 1'b1;                                                                                              
                                s4_trk_wr_state                   = TRK_ST_IDLE;                                
                                s4_trk_wr_debug[EX_DBG_STATERR]   = 1'b1;
                                s4_trk_wr_status                  = s4_rsp_status_d;
                             end
                        end
                      
                      TRK_ST_WR,  
                        TRK_ST_WRLONG,
                        TRK_ST_WRSAME,
                        TRK_ST_WRVERIFY1,
                        TRK_ST_WRVERIFY2:
                          begin              
                             // 1 block of a WRITE, WRITE_SAME, WRITE_AND_VERIFY completed
                             // check whether this was the last block
                             s4_trk_wr_tstamp2  = regs_xx_timer2[15:0];
                             s4_trk_write_d     = 1'b1;                           
                             
                             s4_rsp_status_d    = s3_data_q[14:0];                                            
                             if( s3_trk_rd_state==TRK_ST_WRSAME )
                               begin
                                  // resid doesn't make sense for write_same
                                  // if we got this far, the data was transferred ok, so set resid=0
                                  s4_rsp_resid_d        = zero[datalen_width-1:0];   
                                  s4_rsp_resid_under_d  = 1'b0;
                               end
                             else
                               begin
                                  s4_rsp_resid_d        = s3_upd_resid_q;                                                                   
                                  s4_rsp_resid_under_d  = ~s3_upd_resid_zero_q;         
                               end                           
                             
                             s4_wbuf_reloff_d      = s3_upd_reloff_q;  // next offset
                             s4_wbuf_wbufid_d      = s3_trk_rd_wbufid;
                             s4_wbuf_wbufid_par_d  = s3_trk_rd_wbufid_par;
                             
                             s4_ioq_opcode_d       = NVME_IO_WRITE;         
                             s4_ioq_lba_d          = s3_upd_lba_q;  // starting lba + reloff converted to blocks
                             s4_ioq_numblks_d      = (s3_trk_rd_blksize) ? 0 : 7;               
                             s4_ioq_nsid_d         = s3_trk_rd_nsid;              
                             s4_ioq_fua_d          = s3_trk_rd_debug[EX_DBG_FUA];
                             if( s3_trk_rd_state!=TRK_ST_WRLONG && 
                                 s3_trk_rd_state!=TRK_ST_WRVERIFY2)
                               begin
                                  s4_events_d[11]       = 1'b1;  // WR/WRSAME/WRVERIFY exit
                               end
                             
                             if( s3_data_q[14:0]==zero[14:0] )
                               begin
                                  // good status - now check if this was the last block
                                  if( s3_upd_xfer_done_q &&
                                      s3_trk_rd_state!=TRK_ST_WRVERIFY1 )
                                    begin
                                       s4_rsp_push_d                     = 1'b1;
                                       s4_trk_wr_state                   = TRK_ST_IDLE;
                                       s4_trk_wr_status                  = s4_rsp_status_d;          
                                       s4_trk_wr_debug[EX_DBG_STATGOOD]  = 1'b1;
                                       s4_trk_wr_reloff                  = s3_upd_reloff_q;
                                       
                                       // free write buffer
                                       s4_wbuf_idfree_valid_d            = s3_trk_rd_debug[EX_DBG_IOWRQ]; 
                                       s4_wbuf_idfree_wbufid_d           = s3_trk_rd_wbufid;                                    
                                       s4_wbuf_idfree_wbufid_par_d       = s3_trk_rd_wbufid_par;                                    
                                    end
                                  else
                                    begin
                                       case( s3_trk_rd_state )
                                         TRK_ST_WRSAME:                                       
                                           begin
                                              // reuse buffer with same data
                                              s4_trk_wr_reloff   = s3_upd_reloff_q;
                                              s4_ioq_push_d      = 1'b1;
                                              s4_trk_wr_sqid     = ioq_sntl_sqid;
                                              s4_ioq_sqid_ack_d  = 1'b1;
                                              s4_events_d[14]    = 1'b1; // WRSAME -> WRSAME
                                           end
                                         TRK_ST_WRVERIFY1:
                                           begin
                                              // reuse buffer with same data
                                              s4_trk_wr_state    = TRK_ST_WRVERIFY2;
                                              s4_ioq_opcode_d    = NVME_IO_COMPARE;
                                              s4_ioq_push_d      = 1'b1;                                            
                                           end
                                         default:
                                           begin
                                              // read next block from host
                                              s4_trk_wr_state    = TRK_ST_WRBUF;
                                              s4_trk_wr_reloff   = s3_upd_reloff_q;
                                              s4_wbuf_push_d     = 1'b1;
                                              s4_events_d[12]    = 1'b1; // WR -> WRBUF
                                           end
                                       endcase // case ( s3_trk_rd_state )                                     
                                    end                               
                               end
                             else
                               begin
                                  // bad status
                                  s4_rsp_push_d                    = 1'b1;
                                  
                                  s4_trk_wr_state                  = TRK_ST_IDLE;
                                  s4_trk_wr_debug[EX_DBG_STATERR]  = 1'b1;
                                  s4_trk_wr_status                 = s4_rsp_status_d;          

                                  // free write buffer
                                  s4_wbuf_idfree_valid_d           = 1'b1; 
                                  s4_wbuf_idfree_wbufid_d          = s3_trk_rd_wbufid;               
                                  s4_wbuf_idfree_wbufid_par_d      = s3_trk_rd_wbufid_par;               
                               end                                                                                         
                          end // case: TRK_ST_WR,...

                      
                      
                      TRK_ST_UNMAPIOQ:
                          begin              
                             // unmap issues a single deallocate I/O command                            
                             // forward to unmap module so it can complete combined commands                             
                             
                             s4_trk_wr_tstamp2  = regs_xx_timer2[15:0];
                             s4_trk_write_d     = 1'b1;                           
                                                                                      
                             s4_trk_wr_state                  = TRK_ST_UNMAPIOQ2;                                                      
                             s4_unmap_cpl_valid_d             = 1'b1;                                                                                                                                       
                          end 	

                      

                      TRK_ST_RDERR,
                        TRK_ST_WRERR:
                          begin
                             /* a DMA access was out of bounds for the command */
                             /* indicates a misconfiguration? */                            
                             s4_rsp_push_d                = 1'b1;
                             if( s3_trk_rd_debug[EX_DBG_WDATAERR] )
                               begin
                                  s4_rsp_status_d              = {NVME_SCT_SISLITE, NVME_SC_S_WRITE_DMA_ERR};                            
                               end
                             else
                               begin
                                  s4_trk_wr_debug[EX_DBG_DMAERR]  = 1'b1;
                                  s4_rsp_status_d                 = {NVME_SCT_SISLITE, NVME_SC_S_DMA_ACCESS_ERR};
                               end
                             s4_trk_write_d    = 1'b1;
                             s4_trk_wr_state   = TRK_ST_IDLE;
                             s4_trk_wr_status  = s4_rsp_status_d;                         
                          end                    

                      default:
                        begin
                           // 
                        end
                    endcase // case (s3_trk_rd_state)                    
                 end // if ( s3_instcnt_match_q )               
            end
          
          CMD_CPL_ADMIN:
            begin
               // completion received from Admin buffer
               s4_trk_wr_tstamp2  = regs_xx_timer2[15:0];
               if( s3_data_q[14:0]=={4'h0, NVME_SCT_SISLITE, NVME_SC_S_ABORT_COMPLETE } )
                 begin
                    // abort of I/O command completed - do nothing                    
                 end
               else
                 begin
                    s4_rsp_status_d   = s3_data_q[14:0];
                    s4_rsp_data_d     = s3_data_q[63:32];
                    s4_trk_wr_status  = s4_rsp_status_d;                                          
                    if( s3_trk_rd_opcode == 8'hC0 ||
                        s3_trk_rd_opcode == 8'hC1 )
                      begin
                         s4_rsp_passthru_d = 1'b1;
                      end

                    if( s3_trk_rd_state == TRK_ST_WRERR )
                      begin
                         s4_rsp_push_d                = 1'b1;
                         if( s3_trk_rd_debug[EX_DBG_WDATAERR] )
                           begin
                              s4_rsp_status_d              = {NVME_SCT_SISLITE, NVME_SC_S_WRITE_DMA_ERR};                            
                           end
                         else
                           begin
                              s4_trk_wr_debug[EX_DBG_DMAERR]  = 1'b1;
                              s4_rsp_status_d                 = {NVME_SCT_SISLITE, NVME_SC_S_DMA_ACCESS_ERR};
                           end
                         s4_trk_write_d    = 1'b1;
                         s4_trk_wr_state   = TRK_ST_IDLE;
                         s4_trk_wr_status  = s4_rsp_status_d;         
                      end	                    
                    else if( s3_trk_rd_state == TRK_ST_ADMINWR ||
                             s3_trk_rd_opcode == 8'hC0 ||
                             s3_trk_rd_opcode == 8'hC1 )
                      begin
                         // actual bytes transferred comes from tracking table reloff field
                         // because host buffer was used
                         s4_trk_write_d   = 1'b1;
                         s4_rsp_push_d   = 1'b1;
                         s4_rsp_resid_d  = s3_length_m_reloff_q;
                         if( !s3_reloff_eq_length_q )
                           begin                             
                              // reloff cannot be larger than length - dma is blocked for that case
                              s4_rsp_resid_under_d  = 1'b1;
                           end
                      end               
                    else if( s3_trk_rd_state == TRK_ST_ADMIN )
                      begin
                         if( s3_trk_rd_length < s3_length_q[datalen_width-1:0] )
                           begin
                              // s3_length == length of payload from microcode
                              // s3_trk_rd_length = fcp_length == size of host buffer
                              s4_rsp_resid_d       = s3_length_q - s3_trk_rd_length;
                              s4_rsp_resid_over_d  = 1'b1;
                              s4_trk_wr_reloff     = s3_length_q;
                           end
                         else
                           begin                    
                              s4_rsp_resid_d        = s3_trk_rd_length - s3_length_q;
                              s4_rsp_resid_under_d  = s3_trk_rd_length != s3_length_q[datalen_width-1:0];                     
                              s4_trk_wr_reloff      = s3_length_q;
                           end
                         
                         s4_rsp_push_d   = 1'b1;
                         s4_trk_write_d   = 1'b1;
                      end                    
                    s4_trk_wr_state                   = TRK_ST_IDLE;
                    s4_trk_wr_debug[EX_DBG_STATGOOD]  = s3_data_q[14:0]==zero[14:0];
                    s4_trk_wr_debug[EX_DBG_STATERR]   = ~s4_trk_wr_debug[EX_DBG_STATGOOD];
                 end
            end
          
          CMD_CHECKER:
            begin
               case( s3_data_q[3:0] )
                 CHK_TIMEOUT:
                   begin
                      if( s3_iotimer_elapsed_q == 1'b1 &&
                          (s3_trk_rd_state == TRK_ST_RD ||
                           s3_trk_rd_state == TRK_ST_RDERR ||
                           s3_trk_rd_state == TRK_ST_WR ||
                           s3_trk_rd_state == TRK_ST_WRLONG ||
                           s3_trk_rd_state == TRK_ST_WRERR ||
                           s3_trk_rd_state == TRK_ST_WRSAME ||
                           s3_trk_rd_state == TRK_ST_WRVERIFY1 ||
                           s3_trk_rd_state == TRK_ST_WRVERIFY2))
                         
                        begin
                           
                           // set entry to timeout state.
                           // send abort request to admin queue.  
                           // if command is in flight, this should cause a completion in the I/O queue
                           // if command was dropped somehow (bug), then no I/O completion can happen and entry will time out again
                           // if abort attempt also times out, then terminate with error response (ABORTFAIL)

                           s4_trk_wr_debug[EX_DBG_TIMEOUT]  = 1'b1;
                           
                           if( s3_trk_rd_debug[EX_DBG_TIMEOUT] )
                             begin
                                s4_trk_wr_state                    = TRK_ST_IDLE;
                                s4_trk_wr_debug[EX_DBG_ABORTFAIL]  = 1'b1;
                                s4_rsp_status_d                    = {NVME_SCT_SISLITE, NVME_SC_S_ABORT_FAIL};
                                s4_rsp_push_d                      = 1'b1;
                                s4_trk_write_d                     = 1'b1;
                                s4_trk_wr_status                   = s4_rsp_status_d;
                             end
                           else
                             begin
                                // update tstamp2 to restart timer waiting for abort
                                s4_trk_wr_tstamp2  = regs_xx_timer2[15:0];
                                s4_admin_push_d    = 1'b1;
                                s4_admin_cmd_d     = CMD_ABORT;
                                s4_admin_lun_d[isq_idwidth-1:0] = s3_trk_rd_sqid;
                                s4_trk_write_d     = 1'b1;
                             end                         
                        end 

                      if( s3_iotimer_elapsed_q==1'b1 &&
                          (s3_trk_rd_state == TRK_ST_RDQ ||
                           s3_trk_rd_state == TRK_ST_WRQ ||
                           s3_trk_rd_state == TRK_ST_WRBUF)
                          )
                        begin
                           s4_trk_wr_state                = TRK_ST_IDLE;
                           s4_trk_wr_debug[EX_DBG_ABORT]  = 1'b1;
                           s4_rsp_status_d                = {NVME_SCT_SISLITE, NVME_SC_S_ABORT_OK};
                           s4_rsp_push_d                  = 1'b1;
                           s4_trk_write_d                 = 1'b1;
                           s4_trk_wr_status               = s4_rsp_status_d;
                        end

                      // TRK_ST_UNMAP* doesn't have a timeout
                      // actual timeout should be >> 1ms
                      
                   end
                 
                 CHK_LINKDOWN:
                   begin
                      // if current state != IDLE, give a linkdown response and reset to idle
                      
                      s4_trk_wr_state                   = TRK_ST_IDLE;
                      s4_trk_wr_debug[EX_DBG_LINKDOWN]  = 1'b1;
                      s4_rsp_status_d                   = {NVME_SCT_SISLITE, NVME_SC_S_LINKDOWN};
                      s4_trk_wr_status                  = s4_rsp_status_d;
                      if( s3_trk_rd_state != TRK_ST_IDLE )
                        begin
                           s4_rsp_push_d   = 1'b1;
                           s4_trk_write_d   = 1'b1;    

                           if( s3_trk_rd_debug[EX_DBG_IOWRQ] &&
                               s3_trk_rd_state!= TRK_ST_WRBUF )
                             begin
                                s4_wbuf_idfree_valid_d   = 1'b1;
                                s4_wbuf_idfree_wbufid_d  = s3_trk_rd_wbufid;          
                                s4_wbuf_idfree_wbufid_par_d  = s3_trk_rd_wbufid_par;          
                             end                           
                        end                      
                   end
                 
                 CHK_SHUTDOWN:
                   begin
                      // if current state != IDLE, give a shutdown response with fcx=shutdown_in_progress
                      
                      s4_trk_wr_state                   = TRK_ST_IDLE;
                      s4_trk_wr_debug[EX_DBG_SHUTDOWN]  = 1'b1;
                      s4_rsp_status_d                   = {NVME_SCT_SISLITE, NVME_SC_S_SHUTDOWN_IP};
                      s4_trk_wr_status                  = s4_rsp_status_d;
                      if( s3_trk_rd_state != TRK_ST_IDLE )
                        begin
                           s4_rsp_push_d   = 1'b1;
                           s4_trk_write_d  = 1'b1;                           
                           if( s3_trk_rd_debug[EX_DBG_IOWRQ] &&
                               s3_trk_rd_state!= TRK_ST_WRBUF )
                             begin
                                s4_wbuf_idfree_valid_d   = 1'b1;
                                s4_wbuf_idfree_wbufid_d  = s3_trk_rd_wbufid;          
                                s4_wbuf_idfree_wbufid_par_d  = s3_trk_rd_wbufid_par;          
                             end           
                        end           
                   end
                 
                 CHK_LUNRESET:
                   begin
                      // if current state != IDLE, give an abortok response
                      
                      s4_trk_wr_state                   = TRK_ST_IDLE;
                      s4_trk_wr_debug[EX_DBG_LUNRESET]  = 1'b1;
                      s4_rsp_status_d                   = {NVME_SCT_SISLITE, NVME_SC_S_ABORT_OK};
                      s4_trk_wr_status                  = s4_rsp_status_d;
                      if( s3_trk_rd_state != TRK_ST_IDLE )
                        begin
                           s4_rsp_push_d   = 1'b1;
                           s4_trk_write_d  = 1'b1;                           
                           if( s3_trk_rd_debug[EX_DBG_IOWRQ] &&
                               s3_trk_rd_state!= TRK_ST_WRBUF )
                             begin
                                s4_wbuf_idfree_valid_d       = 1'b1;
                                s4_wbuf_idfree_wbufid_d      = s3_trk_rd_wbufid;          
                                s4_wbuf_idfree_wbufid_par_d  = s3_trk_rd_wbufid_par;          
                             end           
                        end           
                   end
                 CHK_LUNRESET_CMP:
                   begin
                      // expected state is TRK_ST_LUNRESET
                      s4_trk_wr_state   = TRK_ST_IDLE;
                      s4_rsp_status_d   = {NVME_SCT_SISLITE, NVME_SC_S_TMF_COMP};
                      
                      if( s3_trk_rd_state != TRK_ST_IDLE )
                        begin
                           s4_rsp_push_d   = 1'b1;
                           s4_trk_write_d  = 1'b1;                           
                           if( s3_trk_rd_debug[EX_DBG_IOWRQ] &&
                               s3_trk_rd_state!= TRK_ST_WRBUF )
                             begin
                                s4_wbuf_idfree_valid_d   = 1'b1;
                                s4_wbuf_idfree_wbufid_d  = s3_trk_rd_wbufid;          
                                s4_wbuf_idfree_wbufid_par_d  = s3_trk_rd_wbufid_par;          
                             end
                           if( s3_trk_rd_state != TRK_ST_LUNRESET )
                             begin
                                // give response with "something unexpected happened" code
                                s4_rsp_status_d = {NVME_SCT_SISLITE, NVME_SC_S_TMF_NOEXP};
                             end
                        end     
                      s4_trk_wr_status  = s4_rsp_status_d;      
                   end
                 
                 default:
                   begin
                      //
                   end                 
               endcase // case ( s3_data_q[3:0] )                         
            end
          
          CMD_INIT:
            begin
               s4_trk_write_d      = ~regs_cmd_debug[5];
               s4_trk_wr_sqid      = zero[isq_idwidth-1:0];
               s4_trk_wr_lunidx    = zero[lunidx_width-1:0];
               s4_trk_wr_xferlen   = zero[maxxfer_width-1:0];
               s4_trk_wr_wbufid    = zero[wbufid_width-1:0];
               s4_trk_wr_instcnt   = 8'hFF;
               s4_trk_wr_length    = zero[datalen_width-1:0];
               s4_trk_wr_reloff    = zero[datalen_width-1:0];
               s4_trk_wr_opcode    = 8'h00;
               s4_trk_wr_state     = TRK_ST_IDLE;
               s4_trk_wr_tstamp1   = zero[35:0];
               s4_trk_wr_tstamp1d  = zero[19:0];
               s4_trk_wr_tstamp2   = zero[15:0];
               s4_trk_wr_debug     = zero[trkdbg_width-1:0];
               s4_trk_wr_lba       = zero[63:0];
               s4_trk_wr_nsid      = zero[31:0];
               s4_trk_wr_blksize   = 1'b0;
               s4_trk_wr_status    = zero[14:0];
            end
          default:
            begin
            end	          
        endcase // case ( s3_cmd_q )
                
        // pass original request's lunid and NACA setting to response handling for setting ACA state  
        s4_rsp_lunidx_d = s4_trk_wr_lunidx;
        s4_rsp_naca_d   = s4_trk_wr_debug[EX_DBG_NACA];
        
     end // always @ *
   wire [cid_par_width-1:0] s4_cmdid_par;
   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(cid_width)
      ) ipgen_s4_cmdid 
       (.oddpar(1'b1),.data( { s4_trk_wr_instcnt, s3_cid_q[tag_width-1:0] } ),.datap(s4_cmdid_par)); 

   always @*
     begin
        s4_iowr_cmdid_d = {  s4_cmdid_par, s4_trk_wr_instcnt, s3_cid_q[tag_width-1:0] };  
        s4_unmap_cmdid_d = { s4_cmdid_par, s4_trk_wr_instcnt, s3_cid_q[tag_width-1:0] };  
        s4_iord_cmdid_d = {  s4_cmdid_par, s4_trk_wr_instcnt, s3_cid_q[tag_width-1:0] };
        
        s4_admin_cid_d  = {  s4_trk_wr_instcnt, s3_cid_q[tag_width-1:0] };    
        s4_ioq_cmdid_d  = {  s4_trk_wr_instcnt, s3_cid_q[tag_width-1:0] };
     end
   
   // pack tracking table entry
   always @*
     begin     
        s4_trk_wrdata_d = { s4_trk_wr_sqid,
                            s4_trk_wr_lunidx,
                            s4_trk_wr_xferlen,
                            s4_trk_wr_wbufid,
                            s4_trk_wr_instcnt,
                            s4_trk_wr_length,
                            s4_trk_wr_reloff,
                            s4_trk_wr_opcode,
                            s4_trk_wr_state,
                            s4_trk_wr_tstamp1,
                            s4_trk_wr_tstamp1d,
                            s4_trk_wr_tstamp2,
                            s4_trk_wr_debug,
                            s4_trk_wr_lba,
                            s4_trk_wr_nsid,
                            s4_trk_wr_blksize,
                            s4_trk_wr_status };
        trk_wrdata      = s4_trk_wrdata_q;
        trk_write       = s4_trk_write_q;
        trk_wraddr      = s4_trk_wraddr_q;
        trk_wraddr_par  = s4_trk_wraddr_par_q; 
     end
   

   //-------------------------------------------------------   
   // output fifos
   // 1. rspif_fifo - small fifo to avoid backpressure on pipeline.  drains into sislite rsp fifo
   // 2. admin_fifo - requests routed to microcontroller.  sized for max number of requests?
   // 3. ioq_fifo   - small fifo to avoid backpressure on pipeline. drains into NVMe IOQ
   // 4. iowr_fifo  - fifo to hold command ids of all possible writes until wrbuf is free
   // 5. wbuf_fifo  - fifo to hold requests to write buffer
   
   //-------------------------------------------------------
   // rsp fifo
   localparam rspif_width = lunidx_width + 1 + 1 + 16 + 2 + 32 + tag_width + 1 + 32;
   wire                   s5_rsp_fifo_valid;
   reg                    s5_rsp_fifo_taken;
   wire [rspif_width-1:0] s5_rsp_fifo_data;
   wire                   s5_rsp_fifo_almost_full;
   wire                   s5_rsp_fifo_full;
   
   nvme_fifo#(
              .width(rspif_width), 
              .words(16),
              .almost_full_thresh(6)
              ) rspif_fifo
     (.clk(clk), .reset(reset), 
      .flush(       s4_rsp_flush_q ),
      .push(        s4_rsp_push_q ),
      .din(         {s4_rsp_lunidx_q, s4_rsp_naca_q, s4_rsp_tag_par_q, s4_rsp_tag_q, s4_rsp_status_q, s4_rsp_resid_over_q, s4_rsp_resid_under_q, s4_rsp_resid_q, s4_rsp_passthru_q, s4_rsp_data_q} ),
      .dval(        s5_rsp_fifo_valid ), 
      .pop(         s5_rsp_fifo_taken ),
      .dout(        s5_rsp_fifo_data ),
      .full(        s5_rsp_fifo_full ), 
      .almost_full( s5_rsp_fifo_almost_full ), 
      .used());
   
   // translate NVMe status to sislite/SCSI/FCP status
   
   reg                      rsp_v_q;
   reg      [tag_width-1:0] rsp_tag_q;
   reg                      rsp_tag_par_q;
   reg   [fcstat_width-1:0] rsp_fc_status_q;
   reg  [fcxstat_width-1:0] rsp_fcx_status_q;
   reg                [7:0] rsp_scsi_status_q;
   reg                      rsp_sns_valid_q;
   reg                      rsp_fcp_valid_q;
   reg                      rsp_underrun_q;
   reg                      rsp_overrun_q;
   reg               [31:0] rsp_resid_q;
   reg   [beatid_width-1:0] rsp_beats_q;
   reg [rsp_info_width-1:0] rsp_info_q;

   reg                      rsp_v_d;
   reg      [tag_width-1:0] rsp_tag_d;
   reg                      rsp_tag_par_d;
   reg   [fcstat_width-1:0] rsp_fc_status_d;
   reg  [fcxstat_width-1:0] rsp_fcx_status_d;
   reg                [7:0] rsp_scsi_status_d;
   reg                      rsp_sns_valid_d;
   reg                      rsp_fcp_valid_d;
   reg                      rsp_underrun_d;
   reg                      rsp_overrun_d;
   reg               [31:0] rsp_resid_d;
   reg   [beatid_width-1:0] rsp_beats_d;
   reg [rsp_info_width-1:0] rsp_info_d;

   
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin            
             rsp_v_q           <=  1'b0;         
             rsp_tag_q         <=  zero[tag_width-1:0];
             rsp_tag_par_q     <=  1'b1;
             rsp_fc_status_q   <=  zero[fcstat_width-1:0];
             rsp_fcx_status_q  <=  zero[fcxstat_width-1:0];
             rsp_scsi_status_q <=  zero[7:0];
             rsp_sns_valid_q   <=  1'b0;
             rsp_fcp_valid_q   <=  1'b0;
             rsp_underrun_q    <=  1'b0;
             rsp_overrun_q     <=  1'b0;
             rsp_resid_q       <=  zero[31:0];
             rsp_beats_q       <=  zero[beatid_width-1:0];
             rsp_info_q        <=  zero[rsp_info_width-1:0];
          end
        else
          begin      
             rsp_v_q           <= rsp_v_d;
             rsp_tag_q         <= rsp_tag_d;
             rsp_tag_par_q     <= rsp_tag_par_d;
             rsp_fc_status_q   <= rsp_fc_status_d;
             rsp_fcx_status_q  <= rsp_fcx_status_d;
             rsp_scsi_status_q <= rsp_scsi_status_d;
             rsp_sns_valid_q   <= rsp_sns_valid_d;
             rsp_fcp_valid_q   <= rsp_fcp_valid_d;
             rsp_underrun_q    <= rsp_underrun_d;
             rsp_overrun_q     <= rsp_overrun_d;
             rsp_resid_q       <= rsp_resid_d;
             rsp_beats_q       <= rsp_beats_d;
             rsp_info_q        <= rsp_info_d;              
          end
     end

   reg  [lunidx_width-1:0] s5_rsp_lunidx;
   reg                     s5_rsp_naca;
   reg              [15:0] s5_rsp_status;
   reg                     s5_rsp_resid_over;
   reg                     s5_rsp_resid_under;
   reg              [31:0] s5_rsp_resid;   
   reg              [31:0] s5_rsp_data;   
   reg     [tag_width-1:0] s5_rsp_tag;
   reg                     s5_rsp_tag_par; 
   reg                     s5_rsp_passthru;

   reg              [19:0] s5_kcq;  // SCSI sense key & additional sense code & qualifier
   
   always @*
     begin
        {s5_rsp_lunidx, s5_rsp_naca, s5_rsp_tag_par, s5_rsp_tag, s5_rsp_status, s5_rsp_resid_over, s5_rsp_resid_under, s5_rsp_resid, s5_rsp_passthru, s5_rsp_data} = s5_rsp_fifo_data;
        s5_kcq             = {SKEY_NO_SENSE, ASCQ_NO_ERROR };

        cmd_admin_lunlu_setaca     = 1'b0;
        cmd_admin_lunlu_setaca_idx = s5_rsp_lunidx;

        if( ~rsp_v_q )
          begin             
             rsp_v_d            = s5_rsp_fifo_valid;
             s5_rsp_fifo_taken  = s5_rsp_fifo_valid;
             rsp_tag_d          = s5_rsp_tag;
             rsp_tag_par_d      = s5_rsp_tag_par; 
             rsp_underrun_d     = s5_rsp_resid_under;
             rsp_overrun_d      = s5_rsp_resid_over;
             rsp_resid_d        = s5_rsp_resid;
             rsp_beats_d        = zero[beatid_width-1:0];
             
             rsp_fc_status_d    = FCP_RSP_GOOD[fcstat_width-1:0];
             rsp_fcx_status_d   = FCX_STAT_NONE[fcxstat_width-1:0];
             rsp_scsi_status_d  = SCSI_GOOD_STATUS;
             rsp_sns_valid_d    = 1'b0;
             rsp_fcp_valid_d    = 1'b0;            
             rsp_info_d         = zero[rsp_info_width-1:0];
             
             
             case( s5_rsp_status[10:8] )
               
               // see NVM-Express-1_1b 4.6.1
               // and NVM-Express SCSI Translation 1.5 7.1
               NVME_SCT_GENERIC:
                 begin
                    case( s5_rsp_status[7:0] )
                      NVME_SC_G_SUCCESS:
                        begin
                           s5_kcq             = {SKEY_NO_SENSE, ASCQ_NO_ERROR };
                        end      
                      NVME_SC_G_INVALID_OPCODE:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST, ASCQ_INVALID_COMMAND_OPERATION_CODE };
                           rsp_sns_valid_d    = 1'b1;
                        end        
                      NVME_SC_G_INVALID_FIELD:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST, ASCQ_INVALID_FIELD_IN_CDB };
                           rsp_sns_valid_d    = 1'b1;
                        end
                      // note: status mapping not specified for this encode
                      // NVME_SC_G_ID_CONFLICT:
                      //  begin                           
                      //  end            
                      NVME_SC_G_DATA_ERROR:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_MEDIUM_ERROR, ASCQ_NO_ADDITIONAL_SENSE_CODE };
                           rsp_sns_valid_d    = 1'b1;
                        end             
                      NVME_SC_G_POWERLOSS:
                        begin
                           rsp_scsi_status_d  = SCSI_TASK_ABORTED;
                           s5_kcq             = {SKEY_ABORTED_COMMAND,  ASCQ_POWER_LOSS_EXPECTED }; 
                        end              
                      NVME_SC_G_INTERNAL:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_HARDWARE_ERROR, SKEY_HARDWARE_ERROR }; 
                        end               
                      NVME_SC_G_ABORTREQ,
                        NVME_SC_G_ABORTSQDEL,
                        NVME_SC_G_ABORTFUSE1,
                        NVME_SC_G_ABORTFUSE2:                               
                          begin
                             rsp_scsi_status_d  = SCSI_TASK_ABORTED;
                             s5_kcq             = {SKEY_ABORTED_COMMAND, ASCQ_NO_ADDITIONAL_SENSE_CODE }; 
                             rsp_sns_valid_d    = 1'b1;
                          end                                   
                      NVME_SC_G_INVALID_NSPACE:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST,  ASCQ_ACCESS_DENIED_INVALID_LU_IDENTIFIER  };                          
                           rsp_sns_valid_d    = 1'b1;
                        end         
                      NVME_SC_G_LBA_RANGE:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST,  ASCQ_LOGICAL_BLOCK_ADDRESS_OUT_OF_RANGE  };                                                   
                           rsp_sns_valid_d    = 1'b1;
                        end              
                      NVME_SC_G_CAPACITY_EXCEED:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_MEDIUM_ERROR, ASCQ_NO_ADDITIONAL_SENSE_CODE };
                           rsp_sns_valid_d    = 1'b1;
                        end        
                      NVME_SC_G_NSPACE_NOT_READY:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           if( s5_rsp_status[14] )  // NVMe status "Do Not Retry (DNR)" - NVMe 1.1 4.6.1
                             begin
                                s5_kcq             = {SKEY_NOT_READY, ASCQ_NOT_READY_CAUSE_NOT_REPORTABLE };
                             end
                           else
                             begin
                                s5_kcq             = {SKEY_NOT_READY, ASCQ_NOT_READY_BECOMING_READY };     
                             end
                           rsp_sns_valid_d    = 1'b1;
                        end       
                      NVME_SC_G_RESV_CONFLICT:
                        begin
                           rsp_scsi_status_d  = SCSI_RESERVATION_CONFLICT;
                           s5_kcq             =  {SKEY_NO_SENSE, ASCQ_NO_ERROR };
                           rsp_sns_valid_d    = 1'b1;
                        end          
                      default:
                        begin
                           // unexpected error status
                           rsp_fc_status_d = FCP_RSP_NOEXP[fcstat_width-1:0];
                           s5_kcq          = {SKEY_NO_SENSE, 1'b0,  s5_rsp_status[14:0] };
                           rsp_sns_valid_d    = 1'b1;
                        end
                    endcase // case ( s5_rsp_status[7:0] )
                    
                 end
               NVME_SCT_CMDSPEC:
                 begin
                    case( s5_rsp_status[7:0] )
                      NVME_SC_C_ABORT_LIMIT:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST, ASCQ_NO_ADDITIONAL_SENSE_CODE };  
                           rsp_sns_valid_d    = 1'b1;
                        end
                      NVME_SC_C_ATTR_CONFLICT:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST, ASCQ_INVALID_FIELD_IN_CDB };
                           rsp_sns_valid_d    = 1'b1;
                        end                          
                      NVME_SC_C_RO_WRITE:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_WRITE_PROTECT, ASCQ_WRITE_PROTECT };
                           rsp_sns_valid_d    = 1'b1;
                        end       
                      default:
                        begin
                           // unexpected error status
                           rsp_fc_status_d = FCP_RSP_NOEXP[fcstat_width-1:0];
                           s5_kcq          = {SKEY_NO_SENSE, 1'b0,  s5_rsp_status[14:0] };
                           rsp_sns_valid_d    = 1'b1;
                        end
                    endcase // case ( s5_rsp_status[7:0] )                    
                 end                
               NVME_SCT_MEDIA:
                 begin
                    case( s5_rsp_status[7:0] )
                      NVME_SC_M_WRITE_FAULT:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_MEDIUM_ERROR,  ASCQ_WRITE_FAULT };
                           rsp_sns_valid_d    = 1'b1;
                        end        
                      NVME_SC_M_UNRECOVERD_READ_ERROR:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_MEDIUM_ERROR,  ASCQ_UNRECOVERED_READ_ERROR };
                           rsp_sns_valid_d    = 1'b1;
                        end        
                      NVME_SC_M_ACCESS_DENIED:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_WRITE_PROTECT, ASCQ_ACCESS_DENIED_NO_ACCESS_RIGHTS };
                           rsp_sns_valid_d    = 1'b1;
                        end
                      // take default action for end-to-end checking related errors since end-to-end is not supported
                      default:
                        begin
                           // unexpected error status
                           rsp_fc_status_d = FCP_RSP_NOEXP[fcstat_width-1:0];
                           s5_kcq          = {SKEY_NO_SENSE, 1'b0,  s5_rsp_status[14:0] };
                           rsp_sns_valid_d    = 1'b1;
                        end
                    endcase // case ( s5_rsp_status[7:0] )                   
                 end
               NVME_SCT_VENDOR:
                 begin
                    // unexpected error status
                    rsp_fc_status_d = FCP_RSP_NOEXP[fcstat_width-1:0];
                    s5_kcq          = {SKEY_NO_SENSE, 1'b0,  s5_rsp_status[14:0] };
                    rsp_sns_valid_d    = 1'b1;
                 end
               NVME_SCT_SISLITE:
                 begin
                    case( s5_rsp_status[7:0] )                      
                      NVME_SC_S_NOT_IMPL:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST, ASCQ_INVALID_COMMAND_OPERATION_CODE };                           
                           rsp_sns_valid_d    = 1'b1;
                        end       
                      NVME_SC_S_ID_CONFLICT:
                        begin
                           rsp_fc_status_d = FCP_RSP_INUSE[fcstat_width-1:0];
                           s5_kcq          = {SKEY_NO_SENSE, ASCQ_NO_ADDITIONAL_SENSE_CODE  }; 
                           rsp_sns_valid_d = 1'b0;
                        end          
                      NVME_SC_S_INVALID_FIELD:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST,  ASCQ_INVALID_FIELD_IN_COMMAND_INFORMATION_UNIT };
                           rsp_sns_valid_d    = 1'b1;
                        end
                      NVME_SC_S_INVALID_FIELD_IN_PARAM:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST,  ASCQ_INVALID_FIELD_IN_PARAMETER_LIST };
                           rsp_sns_valid_d    = 1'b1;
                        end
                      NVME_SC_S_LOGICAL_UNIT_NOT_SUPPORTED:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_ILLEGAL_REQUEST,  ASCQ_LOGICAL_UNIT_NOT_SUPPORTED };
                           rsp_sns_valid_d    = 1'b1;
                        end
                      NVME_SC_S_DMA_ACCESS_ERR:
                        begin
                           rsp_fc_status_d = FCP_RSP_ABORTOK[fcstat_width-1:0];
                           rsp_fcx_status_d = FCX_STAT_DMAERR;
                           s5_kcq          = {SKEY_NO_SENSE, ASCQ_NO_ERROR };
                           rsp_sns_valid_d    = 1'b0;                           
                        end
                      NVME_SC_S_WRITE_DMA_ERR:
                        begin
                           rsp_fc_status_d = FCP_RSP_ABORTOK[fcstat_width-1:0];
                           rsp_fcx_status_d = FCX_STAT_WDATAERR;
                           s5_kcq          = {SKEY_NO_SENSE, ASCQ_NO_ERROR };
                           rsp_sns_valid_d    = 1'b0;                           
                        end
                      NVME_SC_S_NOT_READY:
                        begin
                           rsp_scsi_status_d  = SCSI_CHECK_CONDITION;
                           s5_kcq             = {SKEY_NOT_READY,  ASCQ_NOT_READY_CAUSE_NOT_REPORTABLE};
                           rsp_sns_valid_d    = 1'b1;
                        end
                      NVME_SC_S_SHUTDOWN:
                        begin
                           rsp_fc_status_d = FCP_RSP_SHUTDOWN[fcstat_width-1:0];
                           rsp_fcx_status_d = FCX_STAT_SHUTDOWN_NEWRQ;
                           s5_kcq          = {SKEY_NO_SENSE, ASCQ_NO_ERROR };                        
                           rsp_sns_valid_d = 1'b0;
                        end
                      NVME_SC_S_SHUTDOWN_IP:
                        begin
                           rsp_fc_status_d = FCP_RSP_SHUTDOWN[fcstat_width-1:0];
                           rsp_fcx_status_d = FCX_STAT_SHUTDOWN_INPROG;
                           s5_kcq          = {SKEY_NO_SENSE, ASCQ_NO_ERROR };                        
                           rsp_sns_valid_d = 1'b0;
                        end
                      NVME_SC_S_LINKDOWN:
                        begin
                           rsp_fc_status_d = FCP_RSP_LINKDOWN[fcstat_width-1:0];
                           s5_kcq          = {SKEY_NO_SENSE, ASCQ_NO_ERROR };                        
                           rsp_sns_valid_d = 1'b0;
                        end
                      NVME_SC_S_ABORT_FAIL:
                        begin
                           rsp_fc_status_d = FCP_RSP_ABORTFAIL[fcstat_width-1:0];
                           s5_kcq          = {SKEY_NO_SENSE, ASCQ_NO_ERROR };                        
                           rsp_sns_valid_d = 1'b0;
                        end
                      NVME_SC_S_ABORT_OK:
                        begin
                           rsp_fc_status_d = FCP_RSP_ABORTOK[fcstat_width-1:0];
                           rsp_fcx_status_d = FCX_STAT_TIMEOUT;
                           s5_kcq          = {SKEY_NO_SENSE, ASCQ_NO_ERROR };                        
                           rsp_sns_valid_d = 1'b0;
                        end    
                      NVME_SC_S_TMF_COMP,
                        NVME_SC_S_TMF_SUCCESS,
                        NVME_SC_S_TMF_REJECT,
                        NVME_SC_S_TMF_LUN,
                        NVME_SC_S_TMF_FAIL:
                          begin
                             rsp_scsi_status_d = {4'h0, s5_rsp_status[3:0]};
                             s5_kcq            = {SKEY_NO_SENSE, ASCQ_NO_ERROR };
                             rsp_sns_valid_d   = 1'b0;
                          end
                      NVME_SC_S_TMF_NOEXP:
                        begin
                           rsp_fc_status_d = FCP_RSP_NOEXP[fcstat_width-1:0];
                           rsp_fcx_status_d = FCX_STAT_TMFERROR[fcxstat_width-1:0];                           
                           s5_kcq            = {SKEY_NO_SENSE, ASCQ_NO_ERROR };
                           rsp_sns_valid_d   = 1'b0;
                        end
                                            
                      NVME_SC_S_ACAACTIVE:
                        begin
                           rsp_scsi_status_d = SCSI_ACA_ACTIVE;                           
                           s5_kcq            = {SKEY_NO_SENSE, ASCQ_NO_ERROR };
                           rsp_sns_valid_d   = 1'b0;
                        end
                      
                      default:
                        begin
                           // unexpected error status
                           rsp_fc_status_d = FCP_RSP_NOEXP[fcstat_width-1:0];
                           s5_kcq          = {SKEY_NO_SENSE, 1'b0,  s5_rsp_status[14:0] };
                           rsp_sns_valid_d    = 1'b1;
                        end               
                    endcase // case ( s5_rsp_status[7:0] )
                 end
               
               default:
                 begin
                    // unexpected error status
                    rsp_fc_status_d = FCP_RSP_NOEXP[fcstat_width-1:0];
                    s5_kcq          = {SKEY_NO_SENSE, 1'b0,  s5_rsp_status[14:0] };  
                    rsp_sns_valid_d    = 1'b1;
                 end
               
             endcase // case ( s5_rsp_status[10:8] )

             // override if using NVMe passthru
             if( s5_rsp_passthru )
               begin
                  rsp_fc_status_d    = FCP_RSP_GOOD[fcstat_width-1:0];
                  rsp_fcx_status_d   = FCX_STAT_NONE[fcxstat_width-1:0];
                  if( s5_rsp_status[14:0] == 15'h0 )
                    begin
                       rsp_scsi_status_d  = SCSI_GOOD_STATUS;
                    end
                  else
                    begin
                       rsp_scsi_status_d  = SCSI_CHECK_CONDITION;                       
                    end
                  
                  rsp_fcp_valid_d    = 1'b0;                           
                  s5_kcq          = {SKEY_NO_SENSE, 1'b0,  s5_rsp_status[14:0] };
                  rsp_sns_valid_d    = 1'b1;
                  // fixed format sense data                    
                  rsp_info_d = { 8'h70, 8'h00, 4'h0, s5_kcq[19:16], 8'h00,               
                                 8'h00, 8'h00, 8'h00, 8'd10,  // byte 7=additional sense length
                                 s5_rsp_data,
                                 s5_kcq[15:0], 8'h00, 8'h00,  // bytes 12-15 of fixed format sense data - ASC/ASCQ/FRU CODE/0x00 (SKSV=0)     
                                 8'h00, 8'h00, 8'hfb, 8'hfb };
               end             
             else if( rsp_sns_valid_d == 1'b0 )
               begin
                  // no sense data
                  rsp_info_d = zero[rsp_info_width-1:0];
               end
             else 
               begin
                  // fixed format sense data                    
                  rsp_info_d = { 8'h70, 8'h00, 4'h0, s5_kcq[19:16], 8'h00,               
                                 8'h00, 8'h00, 8'h00, 8'd10,  // byte 7=additional sense length
                                 8'h00, 8'h00, 8'h00, 8'h00,
                                 s5_kcq[15:0], 8'h00, 8'h00,  // bytes 12-15 of fixed format sense data - ASC/ASCQ/FRU CODE/0x00 (SKSV=0)     
                                 8'h00, 8'h00, 8'hfb, 8'hfb };

                  // put LUN into ACA state if there's a check condition
                  if( rsp_v_d && (rsp_scsi_status_d == SCSI_CHECK_CONDITION) && s5_rsp_naca && !disable_aca)
                    begin
                       cmd_admin_lunlu_setaca = 1'b1;
                    end                  
               end
             
          end
        else
          begin
             s5_rsp_fifo_taken  = 1'b0;
             rsp_v_d            = rsp_v_q & ~rsp_cmd_ack;
             rsp_tag_d          = rsp_tag_q;
             rsp_tag_par_d      = rsp_tag_par_q; 
             rsp_fc_status_d    = rsp_fc_status_q;
             rsp_fcx_status_d   = rsp_fcx_status_q;
             rsp_scsi_status_d  = rsp_scsi_status_q;
             rsp_sns_valid_d    = rsp_sns_valid_q;
             rsp_fcp_valid_d    = rsp_fcp_valid_q;
             rsp_underrun_d     = rsp_underrun_q;
             rsp_overrun_d      = rsp_overrun_q;
             rsp_resid_d        = rsp_resid_q;
             rsp_beats_d        = rsp_beats_q;
             rsp_info_d         = rsp_info_q;
          end

        cmd_rsp_v            = rsp_v_q;
        cmd_rsp_tag          = rsp_tag_q;
        cmd_rsp_tag_par      = rsp_tag_par_q;
        cmd_rsp_fc_status    = rsp_fc_status_q;
        cmd_rsp_fcx_status   = rsp_fcx_status_q;
        cmd_rsp_scsi_status  = rsp_scsi_status_q;
        cmd_rsp_sns_valid    = rsp_sns_valid_q;
        cmd_rsp_fcp_valid    = rsp_fcp_valid_q;
        cmd_rsp_underrun     = rsp_underrun_q;
        cmd_rsp_overrun      = rsp_overrun_q;
        cmd_rsp_resid        = rsp_resid_q;
        cmd_rsp_beats        = rsp_beats_q;
        cmd_rsp_info         = rsp_info_q;
     end

   //-------------------------------------------------------
   // I/O Write command fifo


   localparam iowr_width = cid_width+cid_par_width;
   wire                      s5_iowr_fifo_full;
   wire                      s5_iowr_fifo_almost_full;
   wire       [trk_awidth:0] s5_iowr_fifo_used;
   
   nvme_fifo#(
              .width(iowr_width), 
              .words(trk_entries),
              .almost_full_thresh(0)
              ) iowr_fifo
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        s4_iowr_push_q  ),
      .din(         s4_iowr_cmdid_q ),
      .dval(        s5_iowr_fifo_valid ), 
      .pop(         s5_iowr_fifo_taken ),
      .dout(        {s5_iowr_fifo_data_par,s5_iowr_fifo_data} ),
      .full(        s5_iowr_fifo_full ), 
      .almost_full( s5_iowr_fifo_almost_full ), 
      .used(        s5_iowr_fifo_used));

   // track number of writes in progress
   // writes will not be submitted to NVMe if iowr_inuse_q than threshold
   // writes are also limited by the number of write buffers
   reg                       iowr_inuse_decr_q, iowr_inuse_decr_d;
   always @(posedge clk)
     iowr_inuse_decr_q <= iowr_inuse_decr_d;
   
   always @*
     begin
        iowr_inuse_d = iowr_inuse_q;
        
        if( s5_iowr_fifo_taken )
          begin
             iowr_inuse_d = iowr_inuse_d + 1;
          end

        iowr_inuse_decr_d = iowr_completed | // iowr allocated but tracking entry timed out
                            (s4_trk_write_d & s4_trk_wr_debug[EX_DBG_IOWRQ] & s4_trk_wr_state==TRK_ST_IDLE & s3_trk_rd_state!=TRK_ST_IDLE);
        if( iowr_inuse_decr_q )
          begin
             iowr_inuse_d = iowr_inuse_d - 1;  
          end
     end

   // if iowr fifo output is valid, get a wbufid
   reg s5_wbufid_valid_q, s5_wbufid_valid_d;
   reg [wbufid_width-1:0] s5_wbufid_q, s5_wbufid_d;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             s5_wbufid_valid_q <= 1'b0;
             s5_wbufid_q       <= zero[wbufid_width-1:0];
          end
        else
          begin
             s5_wbufid_valid_q <= s5_wbufid_valid_d;
             s5_wbufid_q       <= s5_wbufid_d;
          end
     end

   always @*
     begin
        s5_wbufid_valid_d     = s5_wbufid_valid_q & ~s5_iowr_fifo_taken;
        s5_wbufid_d           = s5_wbufid_q;

        cmd_wbuf_id_valid     = s5_iowr_fifo_valid & ~s5_wbufid_valid_q;
        s5_iowr_wbufid_valid  = s5_wbufid_valid_q;  
        s5_iowr_wbufid        = s5_wbufid_q;
        
        if( wbuf_cmd_id_ack )
          begin
             s5_wbufid_valid_d  = 1'b1;
             s5_wbufid_d        = wbuf_cmd_id_wbufid;
          end
     end   
   
   
   //-------------------------------------------------------

   // I/O Read command fifo
   localparam iord_width = cid_par_width+cid_width;
   wire                       s5_iord_fifo_full;
   wire                       s5_iord_fifo_almost_full;
   wire        [trk_awidth:0] s5_iord_fifo_used;
   
   nvme_fifo#(
              .width(iord_width), 
              .words(trk_entries),
              .almost_full_thresh(0)
              ) iord_fifo
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        s4_iord_push_q  ),
      .din(         s4_iord_cmdid_q ),
      .dval(        s5_iord_fifo_valid ), 
      .pop(         s5_iord_fifo_taken ),
      .dout(        {s5_iord_fifo_data_par,s5_iord_fifo_data} ),
      .full(        s5_iord_fifo_full ), 
      .almost_full( s5_iord_fifo_almost_full ), 
      .used(        s5_iord_fifo_used));

   reg                        iord_inuse_decr_q, iord_inuse_decr_d;
   always @(posedge clk)
     iord_inuse_decr_q <= iord_inuse_decr_d;
   
   always @*
     begin
        iord_inuse_d = iord_inuse_q;
        
        if( s5_iord_fifo_taken )
          begin
             iord_inuse_d = iord_inuse_d + 1;
          end

        iord_inuse_decr_d = iord_completed | (s4_trk_write_d & s4_trk_wr_debug[EX_DBG_IORDQ] & s4_trk_wr_state==TRK_ST_IDLE);
        if( iord_inuse_decr_q )
          begin
             iord_inuse_d = iord_inuse_d - 1;  
          end
     end
   
   // sntl_unmap needs to know if there are any reads or writes in progress 
   reg unmap_ioidle_q;
   always @(posedge clk)
     begin
        unmap_ioidle_q <= (iowr_inuse_q==zero[tag_width:0] &&
                          iord_inuse_q==zero[tag_width:0] &&
                          !s5_iowr_fifo_valid &&
                          !s5_iord_fifo_valid) || regs_cmd_debug[8];
     end
   assign cmd_unmap_ioidle = unmap_ioidle_q;
   
   //-------------------------------------------------------
   // Write buffer request fifo
   // no backpressure.  
   // original design had # of fifo entries == number of write buffers.  only 1 write buffer request per buffer allowed
   // unmap performance change: size to match tracking table.  each tag could write to buffer for unmap command
   
   localparam wbuf_fifo_width = 64 + 16 + 1 + 2 + cid_width + datalen_width + 1 + wbufid_width;
   localparam wbuf_fifo_entries = trk_entries;
   wire                       s5_wbuf_fifo_valid;
   wire                       s5_wbuf_fifo_full;
   wire                       s5_wbuf_fifo_almost_full;
   reg                        s5_wbuf_fifo_taken;
   wire [wbuf_fifo_width-1:0] s5_wbuf_fifo_data;
   wire [$clog2(wbuf_fifo_entries):0] s5_wbuf_fifo_used;
   
   nvme_fifo#(
              .width(wbuf_fifo_width), 
              .words(wbuf_fifo_entries),
              .almost_full_thresh(0)
              ) wbuf_fifo
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        s4_wbuf_push_q  ),
      .din(         { s4_wbuf_lba_q, s4_wbuf_numblks_q, s4_wbuf_unmap_q, s4_wbuf_cmdid_par_q, s4_wbuf_cmdid_q, s4_wbuf_reloff_q, s4_wbuf_wbufid_par_q,s4_wbuf_wbufid_q} ),
      .dval(        s5_wbuf_fifo_valid ), 
      .pop(         s5_wbuf_fifo_taken ),
      .dout(        s5_wbuf_fifo_data ),
      .full(        s5_wbuf_fifo_full ), 
      .almost_full( s5_wbuf_fifo_almost_full ), 
      .used(        s5_wbuf_fifo_used));

   always @*
     begin
        cmd_wbuf_req_valid = s5_wbuf_fifo_valid;
        { cmd_wbuf_req_lba, cmd_wbuf_req_numblks, cmd_wbuf_req_unmap, cmd_wbuf_req_cid_par, cmd_wbuf_req_cid, cmd_wbuf_req_reloff, cmd_wbuf_req_wbufid_par, cmd_wbuf_req_wbufid } = s5_wbuf_fifo_data;
        s5_wbuf_fifo_taken = cmd_wbuf_req_valid & wbuf_cmd_req_ready;      
     end

   
   //-------------------------------------------------------
   // IOQ fifo
   localparam ioq_width = isq_idwidth + 64 + 16 + 32 + 8 + 16 + 1 + wbufid_width + datalen_width;
   localparam ioq_fifo_entries = 16;
   
   reg                      s5_ioq_fifo_taken;
   wire                     s5_ioq_fifo_valid;
   wire                     s5_ioq_fifo_full;
   wire                     s5_ioq_fifo_almost_full;
   wire     [ioq_width-1:0] s5_ioq_fifo_data;
   wire [$clog2(ioq_fifo_entries):0] s5_ioq_fifo_used;
   
   nvme_fifo#(
              .width(ioq_width), 
              .words(ioq_fifo_entries),
              .almost_full_thresh(6)
              ) ioq_fifo
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        s4_ioq_push_q  ),
      .din(         {s4_ioq_sqid_q, s4_ioq_lba_q, s4_ioq_numblks_q, s4_ioq_nsid_q, s4_ioq_opcode_q, s4_ioq_cmdid_q, s4_ioq_fua_q, s4_ioq_wbufid_q, s4_ioq_reloff_q } ),
      .dval(        s5_ioq_fifo_valid ), 
      .pop(         s5_ioq_fifo_taken ),
      .dout(        s5_ioq_fifo_data ),
      .full(        s5_ioq_fifo_full ), 
      .almost_full( s5_ioq_fifo_almost_full ), 
      .used(        s5_ioq_fifo_used));

   always @*
     begin
        {sntl_ioq_req_sqid, sntl_ioq_req_lba, sntl_ioq_req_numblks, sntl_ioq_req_nsid, sntl_ioq_req_opcode, sntl_ioq_req_cmdid, sntl_ioq_req_fua, sntl_ioq_req_wbufid, sntl_ioq_req_reloff } = s5_ioq_fifo_data;
        sntl_ioq_req_valid = s5_ioq_fifo_valid;
        s5_ioq_fifo_taken = ioq_sntl_req_ack;
        sntl_ioq_req_wbufid_par = 1'b0;
     end


   //-------------------------------------------------------   
   // admin fifo

   // holds a few commands going to admin/microcode
   // when this is full, sislite request interface gets backpressure
   // could resize to 256 and no backpressure or put lun & cdb in tracking table and just queue the cid?
   localparam admin_fifo_entries = 16;
   localparam admin_width = cmd_width + 16 + lunid_width + datalen_width + 128;
   localparam admin_par_width = (admin_width+63)/64;
   
   reg                      s5_admin_fifo_taken;
   reg                      s5_admin_fifo_flush;
   wire                     s5_admin_fifo_full;
   wire                     s5_admin_fifo_almost_full;
   wire   [admin_width-1:0] s5_admin_fifo_data;
   wire [$clog2(admin_fifo_entries):0] s5_admin_fifo_used;

   // gen parity for array

   wire          [admin_par_width-1:0] s4_admin_fifo_data_par;
   wire          [admin_par_width-1:0] s5_admin_fifo_data_par;

   nvme_pgen#
     (
      .bits_per_parity_bit(64),
      .width(admin_width)
      ) ipgen_s4_admin_array 
       (.oddpar(1'b1),.data({s4_admin_cmd_q, s4_admin_cid_q, s4_admin_lun_q, s4_admin_length_q, s4_admin_cdb_q}),.datap(s4_admin_fifo_data_par)); 

   //   
   nvme_fifo#(
              .width(admin_par_width + admin_width), 
              .words(admin_fifo_entries),
              .almost_full_thresh(6)
              ) admin_fifo
     (.clk(clk), .reset(reset), 
      .flush(       s5_admin_fifo_flush ),
      .push(        s4_admin_push_q  ),
      .din(         { s4_admin_fifo_data_par,s4_admin_cmd_q, 
                      s4_admin_cid_q, 
                      s4_admin_lun_q, 
                      s4_admin_length_q, 
                      s4_admin_cdb_q } ),
      .dval(        s5_admin_fifo_valid ), 
      .pop(         s5_admin_fifo_taken ),
      .dout(        {s5_admin_fifo_data_par,s5_admin_fifo_data} ),
      .full(        s5_admin_fifo_full ), 
      .almost_full( s5_admin_fifo_almost_full ), 
      .used(        s5_admin_fifo_used));

   // check fifo parity
   nvme_pcheck#
     (
      .bits_per_parity_bit(64),
      .width(admin_width)
      ) ipcheck_s5_admin_array 
       (.oddpar(1'b1),.data({s5_admin_fifo_data[admin_width-1:1],(s5_admin_fifo_data[0]^cmd_pe_inj_q[5])}),.datap(s5_admin_fifo_data_par),.check(s5_admin_fifo_valid),.parerr(s1_perror[5])); 

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(16)
      ) ipgen_cmd_admin_cid
       (.oddpar(1'b1),.data(cmd_admin_cid),.datap(cmd_admin_cid_par)); 

   always @*
     begin   
        { cmd_admin_cmd, 
          cmd_admin_cid, 
          cmd_admin_lun, 
          cmd_admin_length, 
          cmd_admin_cdb }  = s5_admin_fifo_data;
        cmd_admin_valid = s5_admin_fifo_valid;
        s5_admin_fifo_taken = admin_cmd_ack;   
     end

   always @*
     begin
        cmd_unmap_req_valid                 = s4_unmap_req_valid_q;
        cmd_unmap_cpl_valid                 = s4_unmap_cpl_valid_q;
        {cmd_unmap_cid_par, cmd_unmap_cid}  = s4_unmap_cmdid_q;
        cmd_unmap_cpl_status                = s4_unmap_status_q;
     end
   
   
   //-------------------------------------------------------   
   
   always @*
     begin
        s5_ioq_backpressure    = s5_ioq_fifo_almost_full;
        s5_admin_backpressure  = s5_admin_fifo_almost_full;
        s5_rsp_backpressure    = s5_rsp_fifo_almost_full;
     end


   //-------------------------------------------------------   
   // debug counters
   //-------------------------------------------------------   

   (* mark_debug = "false" *) 
   reg [31:0] count_q;
   reg [31:0] count_d;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             count_q <= 32'h0;
          end
        else
          begin
             count_q <= count_d;
          end
     end
   
   // counters
   always @*
     begin
        count_d[0] = s2_cmd_q==CMD_RD && s2_cdb_op_rd_q;
        count_d[1] = s2_cmd_q==CMD_WR && (s2_cdb_op_wr_q | s2_cdb_op_wrlong_q | s2_cdb_op_wrsame_q);
        count_d[2] = s2_cmd_q==CMD_TASKMAN;
        count_d[3] = (s2_cmd_q==CMD_RD || s2_cmd_q==CMD_WR) && (s2_cdb_op_admin_q | s2_cdb_op_adminwr_q);
        count_d[4] = (s2_cmd_q==CMD_RD || s2_cmd_q==CMD_WR) && s2_cdb_op_unsup_q;

        count_d[5] = rsp_cmd_ack &&  (rsp_fc_status_q==zero[fcstat_width-1:0] && rsp_scsi_status_q==8'h00);
        count_d[6] = rsp_cmd_ack && !(rsp_fc_status_q==zero[fcstat_width-1:0] && rsp_scsi_status_q==8'h00);
        
        count_d[7] = s4_trk_write_d & s4_trk_wr_debug[EX_DBG_TIMEOUT] & ~s3_trk_rd_debug[EX_DBG_TIMEOUT];
        count_d[8] = s4_trk_write_d & s4_trk_wr_debug[EX_DBG_WDATAERR] & ~s3_trk_rd_debug[EX_DBG_WDATAERR];
        count_d[9] = s4_trk_write_d & s4_trk_wr_debug[EX_DBG_DMAERR] & ~s3_trk_rd_debug[EX_DBG_DMAERR];

        count_d[10] = req_taken;
        
        count_d[31:11] = zero[31:11];
        
        cmd_regs_dbgcount = count_q;
        cmd_perf_events = s4_events_q;
     end
   

   //-------------------------------------------------------   
   // Timeout/Link Down/Shutdown handling
   //-------------------------------------------------------   

   reg [3:0] checker_state_q, checker_state_d;
   localparam [3:0] CHKSM_IDLE       = 4'h1;
   localparam [3:0] CHKSM_TIMEOUT    = 4'h2;
   localparam [3:0] CHKSM_TIMEOUT2   = 4'h3;
   localparam [3:0] CHKSM_TERMINATE  = 4'h4;
   localparam [3:0] CHKSM_TERMINATE2 = 4'h5;
   localparam [3:0] CHKSM_LUNRESET1  = 4'h6;
   localparam [3:0] CHKSM_LUNRESET2  = 4'h7;
   localparam [3:0] CHKSM_LUNRESET3  = 4'h8;
   localparam [3:0] CHKSM_LUNRESET4  = 4'h9;

   reg [trk_awidth-1:0] checker_tag_q, checker_tag_d;
   reg                  checker_tag_par_q, checker_tag_par_d;
   reg           [15:0] checker_countdown_q, checker_countdown_d;
   reg            [1:0] checker_notready_q, checker_notready_d;
   reg            [1:0] checker_shutdown_q, checker_shutdown_d;
   reg            [1:0] checker_lunreset_q, checker_lunreset_d;
   reg                  checker_admin_flush_q, checker_admin_flush_d;
   reg [trk_awidth-1:0] checker_lunreset_tag_q, checker_lunreset_tag_d;
   reg                  checker_lunreset_tag_par_q, checker_lunreset_tag_par_d;

`ifdef SIM 
   localparam checker_spacing = 16'h0010;
`else
   localparam checker_spacing = 16'h03FF;
`endif
   always @(posedge clk or posedge reset)
     begin
        if ( reset )
          begin
             checker_state_q            <= CHKSM_IDLE;
             checker_tag_q              <= zero[trk_awidth-1:0];
             checker_tag_par_q          <= 1'b1;
             checker_countdown_q        <= checker_spacing;
             checker_notready_q         <= 1'b0;
             checker_shutdown_q         <= 1'b0;
             checker_lunreset_q         <= 1'b0;
             checker_admin_flush_q      <= 1'b0;
             checker_lunreset_tag_q     <= zero[trk_awidth-1:0];
             checker_lunreset_tag_par_q <= 1'b1;
          end
        else
          begin
             checker_state_q            <= checker_state_d;
             checker_tag_q              <= checker_tag_d;
             checker_tag_par_q          <= checker_tag_par_d;
             checker_countdown_q        <= checker_countdown_d;
             checker_notready_q         <= checker_notready_d;
             checker_shutdown_q         <= checker_shutdown_d;
             checker_lunreset_q         <= checker_lunreset_d;
             checker_admin_flush_q      <= checker_admin_flush_d;
             checker_lunreset_tag_q     <= checker_lunreset_tag_d;
             checker_lunreset_tag_par_q <= checker_lunreset_tag_par_d;
          end
     end

   // parity gen 
   wire            checker_tag_par_int;          
   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(tag_width)
      ) ipgen_checker_tag_par_d 
       (.oddpar(1'b1),.data(checker_tag_d[tag_width-1:0]),.datap( checker_tag_par_int)); 

   
   always @*
     begin
        // inputs to tracking table pipeline
        checker_valid               = 1'b0;
        checker_action              = CHK_READ;
        checker_tag                 = checker_tag_q;
        checker_tag_par             = checker_tag_par_q;
        
        checker_state_d             = checker_state_q;
        checker_tag_d               = checker_tag_q;
        checker_tag_par_d           = checker_tag_par_q;
        checker_lunreset_tag_d      = checker_lunreset_tag_q;
        checker_lunreset_tag_par_d  = checker_lunreset_tag_par_q;

        // if controller goes from ready->not ready
        // this could be caused by a controller reset or a pcie link down
        // any outstanding commands will not be complete by the controller and need to be terminated
        checker_notready_d[0]       = ~ctl_xx_csts_rdy;
        checker_notready_d[1]       = checker_notready_q[1] | (~checker_notready_q[0]&~ctl_xx_csts_rdy);  // capture and hold on negedge of csts_rdy

        // flush admin commands in progress if the controller isn't ready
        checker_admin_flush_d       = 1'b0;
        s5_admin_fifo_flush         = checker_admin_flush_q;
        cmd_admin_flush             = checker_admin_flush_q;
        cmd_unmap_flush             = checker_admin_flush_q;
        
        // if controller shutdown completes, any outstanding commands needed to be terminated
        checker_shutdown_d[0]       = ctl_xx_shutdown_cmp;
        checker_shutdown_d[1]       = checker_shutdown_q[1] | (~checker_shutdown_q[0]&ctl_xx_shutdown_cmp); // capture and hold on posedge of shutdown

        // lun reset - complete all outstanding requests, reset NVMe controller
        // clear when all commands are completed and controller is ready
        checker_lunreset_d[0]       = s4_checker_lunreset;
        checker_lunreset_d[1]       = checker_lunreset_q[1] | checker_lunreset_q[0]; // hold until cleared by state machine below
        if( s4_checker_lunreset )
          begin
             checker_lunreset_tag_d      = s4_checker_lunreset_tag;
             checker_lunreset_tag_par_d  = s4_checker_lunreset_tag_par;
          end

        cmd_regs_lunreset           = 1'b0;
        checker_lunreset_stall      = s4_checker_lunreset | checker_lunreset_q[0] | checker_lunreset_q[1];
        
        // separate reads of exchange for timeout checking
        if (checker_countdown_q != 16'h0000)      
          begin
             checker_countdown_d = checker_countdown_q - 16'h0001;
          end        
        else
          begin
             checker_countdown_d = checker_countdown_q;
          end

        
        case (checker_state_q)
          CHKSM_IDLE:
            begin

               if (checker_shutdown_q[1] | checker_notready_q[1])
                 begin
                    checker_state_d        = CHKSM_TERMINATE;
                    checker_tag_d          = zero[trk_awidth-1:0];
                    checker_tag_par_d      = 1'b1;
                    checker_admin_flush_d  = 1'b1;
                 end   
               else if( checker_lunreset_q[1] && ~disable_lun_reset )
                 begin
                    checker_state_d        = CHKSM_LUNRESET1;
                    checker_tag_d          = zero[trk_awidth-1:0];
                    checker_tag_par_d      = 1'b1;
                    checker_admin_flush_d  = 1'b1;
                 end
               else if (checker_countdown_q == 16'h0000)
                 begin
                    checker_countdown_d = checker_spacing;
                    if( ~regs_cmd_disableto )
                      begin
                         checker_state_d = CHKSM_TIMEOUT;
                      end
                 end
            end

          CHKSM_TIMEOUT:
            begin
               checker_valid   = 1'b1;
               checker_action  = CHK_TIMEOUT;
               if (checker_taken)
                 begin
                    checker_state_d     = CHKSM_TIMEOUT2;
                 end
            end
          
          CHKSM_TIMEOUT2:
            begin              
               checker_state_d = CHKSM_IDLE;                    
               if (checker_tag_q == trk_last_entry[trk_awidth-1:0])
                 checker_tag_d = zero[trk_awidth-1:0];
               else
                 checker_tag_d = checker_tag_q + one[trk_awidth-1:0];    
               checker_tag_par_d = checker_tag_par_int;    
            end
          

          CHKSM_TERMINATE:
            begin
               checker_valid   = 1'b1;
               if( checker_shutdown_q[1] )
                 begin
                    checker_action  = CHK_SHUTDOWN;
                 end
               else
                 begin
                    checker_action = CHK_LINKDOWN;
                 end
               
               if( checker_taken )
                 begin
                    checker_state_d = CHKSM_TERMINATE2;
                 end
            end

          CHKSM_TERMINATE2:
            begin
               if (checker_tag_q == trk_last_entry[trk_awidth-1:0])
                 begin
                    checker_tag_d          = zero[trk_awidth-1:0];
                    checker_tag_par_d      = 1'b1;
                    checker_state_d        = CHKSM_IDLE;
                    checker_shutdown_d[1]  = 1'b0;
                    checker_notready_d[1]  = 1'b0;
                 end
               else
                 begin
                    checker_tag_d      = checker_tag_q + one[trk_awidth-1:0];
                    checker_tag_par_d  = checker_tag_par_int;    
                    checker_state_d    = CHKSM_TERMINATE;
                 end                    
            end

          CHKSM_LUNRESET1:
            begin
               // wait for microcode to reset the NVMe controller
               cmd_regs_lunreset = 1'b1;
               if( !ctl_xx_ioq_enable )
                 begin
                    checker_state_d = CHKSM_LUNRESET2;
                 end               
            end

          CHKSM_LUNRESET2:
            begin
               cmd_regs_lunreset = 1'b1;
               checker_action = CHK_LUNRESET;
               
               // walk thru all tags and terminate, skipping the tag with the lun reset request
               if( checker_tag_q == checker_lunreset_tag_q )
                 begin                    
                    checker_state_d = CHKSM_LUNRESET3;
                 end
               else
                 begin
                    checker_valid   = 1'b1;                    
                    if( checker_taken )
                      begin
                         checker_state_d = CHKSM_LUNRESET3;
                      end
                 end                                                            
            end

          CHKSM_LUNRESET3:
            begin
               cmd_regs_lunreset = 1'b1;
               if (checker_tag_q == trk_last_entry[trk_awidth-1:0])
                 begin
                    checker_tag_d      = checker_lunreset_tag_q;
                    checker_tag_par_d  = checker_lunreset_tag_par_q;
                    checker_state_d    = CHKSM_LUNRESET4;
                 end
               else
                 begin
                    checker_tag_d      = checker_tag_q + one[trk_awidth-1:0];
                    checker_tag_par_d  = checker_tag_par_int;
                    checker_state_d    = CHKSM_LUNRESET2;                   
                 end                    
            end
          
          CHKSM_LUNRESET4:
            begin
               cmd_regs_lunreset = 1'b1;
               // complete the lun reset task management entry
               checker_action = CHK_LUNRESET_CMP;

               if( ctl_xx_ioq_enable )
                 begin
                    checker_valid  = 1'b1;
                    if( checker_taken )
                      begin
                         checker_state_d = CHKSM_IDLE;
                         checker_lunreset_d = 2'h0;
                      end
                 end
            end
          
          
          default:
            begin
               checker_state_d = CHKSM_IDLE;
            end

        endcase
     end

   always @*
     begin
        sntl_regs_cmd_idle = !s5_admin_fifo_valid &&
                             !s5_ioq_fifo_valid &&  
                             !s5_wbuf_fifo_valid &&
                             !s5_iord_fifo_valid &&
                             !s5_iowr_fifo_valid &&
                             iowr_inuse_q==0 &&
                             iord_inuse_q==0 &&
                             s0_init_done_q;
     end
   
   
endmodule


