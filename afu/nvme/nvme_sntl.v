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
//  File : nvme_sntl.v
//  *************************************************************************
//  *************************************************************************
//  Description : FlashGT+ - SCSI to NVMe Layer
//                
//  *************************************************************************

module nvme_sntl#
  (// afu/psl   interface parameters
    parameter tag_width       = 8,
    parameter datalen_width   = 25,
    parameter datalen_par_width   = 1,
    parameter data_width      = 128,
    parameter data_bytes      = data_width/8,
    parameter bytec_width     = $clog2(data_bytes+1),
    parameter beatid_width    = datalen_width-$clog2(data_bytes),    
    parameter lunid_width     = 64, 
    parameter cmd_width       = 4, 
    parameter fcstat_width    = 8, 
    parameter fcxstat_width   = 8, 
    parameter rsp_info_width  = 160,
    parameter tag_par_width   = (tag_width + 63)/64, 
    parameter lunid_par_width = (lunid_width + 63)/64, 
    parameter data_par_width  = (data_width + 7) /8,
    parameter data_fc_par_width  = data_par_width/8,
    parameter status_width    = 8, // event status
    parameter wdata_max_req   = 4096,
    parameter wdatalen_width  = $clog2(wdata_max_req)+1,
    parameter wdatalen_par_width  = (wdatalen_width+63)/64,
    parameter sisl_block_size = 4096, // all namespaces are mapped to 4K blocks
    parameter sisl_block_width = $clog2(sisl_block_size-1), // number of bits to convert from bytes to blocks
    parameter maxxfer_width   = datalen_width-sisl_block_width,

    parameter lunidx_width    = 8, // support 255 LUNs max
    parameter addr_width = 48,
    parameter cid_width = 16,
    parameter cid_par_width = 2,
 

    parameter wbuf_numids     = 16,  // 4KB per id
    parameter wbufid_width    = $clog2(wbuf_numids),
    parameter wbufid_par_width = (wbufid_width + 7)/8,

    parameter num_isq = 16,  // max number of I/O submissions queues
    parameter isq_idwidth = $clog2(num_isq+2)

    )
   (
   
    input                          reset,
    input                          clk, 

    //-------------------------------------------------------
    // AFU/PSL interface
    //-------------------------------------------------------
   
    // request command interface
    //  req_r    - ready
    //  req_v    - valid.  xfer occurs only if valid & ready, otherwise no xfer
    //  req_cmd  - tbd: define encodes.  use SCSI opcodes?
    //  req_tag  - identifier for the command
    //  req_lun  - logical unit number
    output                         i_req_r_out,
    input                          i_req_v_in,
    input          [cmd_width-1:0] i_req_cmd_in, 
    input          [tag_width-1:0] i_req_tag_in, 
    input      [tag_par_width-1:0] i_req_tag_par_in, 
    input        [lunid_width-1:0] i_req_lun_in, 
    input    [lunid_par_width-1:0] i_req_lun_par_in, 
    input      [datalen_width-1:0] i_req_length_in, 
    input                          i_req_length_par_in, 
    input                  [127:0] i_req_cdb_in, 
    input                    [1:0] i_req_cdb_par_in,
    // write data request interface. 
    output                         o_wdata_req_v_out,
    input                          o_wdata_req_r_in,
    output         [tag_width-1:0] o_wdata_req_tag_out,
    output     [tag_par_width-1:0] o_wdata_req_tag_par_out,
    output      [beatid_width-1:0] o_wdata_req_beat_out,
    output     [datalen_width-1:0] o_wdata_req_size_out,
    output [datalen_par_width-1:0] o_wdata_req_size_par_out,

    // data response interface (writes).  
    input                          i_wdata_rsp_v_in,
    output                         i_wdata_rsp_r_out,
    input                          i_wdata_rsp_e_in,
    input                          i_wdata_rsp_error_in,
    input          [tag_width-1:0] i_wdata_rsp_tag_in,
    input                          i_wdata_rsp_tag_par_in,
    input       [beatid_width-1:0] i_wdata_rsp_beat_in,
    input         [data_width-1:0] i_wdata_rsp_data_in,
    input  [data_fc_par_width-1:0] i_wdata_rsp_data_par_in,

    // read data response interface
    //   rsp_v    - valid.  
    //   rsp_e    - read data end. Must be asserted with rsp_v after last data beat for a 2K block.
    //   rsp_tag  - identifier of the corresponding read request
    //   rsp_beat - word offset for this data transfer
    //   rsp_data - 32b of read data.  Not used when rsp_e is assserted.
    // 
    output                         o_rdata_rsp_v_out,
    input                          o_rdata_rsp_r_in,
    output                         o_rdata_rsp_e_out,
    output       [bytec_width-1:0] o_rdata_rsp_c_out,
    output      [beatid_width-1:0] o_rdata_rsp_beat_out,
    output         [tag_width-1:0] o_rdata_rsp_tag_out,
    output     [tag_par_width-1:0] o_rdata_rsp_tag_par_out,
    output        [data_width-1:0] o_rdata_rsp_data_out,
    output [data_fc_par_width-1:0] o_rdata_rsp_data_par_out,

    // command response interface
    output                         o_rsp_v_out,
    output         [tag_width-1:0] o_rsp_tag_out,
    output     [tag_par_width-1:0] o_rsp_tag_par_out,
    output      [fcstat_width-1:0] o_rsp_fc_status_out,
    output     [fcxstat_width-1:0] o_rsp_fcx_status_out,
    output                   [7:0] o_rsp_scsi_status_out,
    output                         o_rsp_sns_valid_out,
    output                         o_rsp_fcp_valid_out,
    output                         o_rsp_underrun_out,
    output                         o_rsp_overrun_out,
    output                  [31:0] o_rsp_resid_out,
    output      [beatid_width-1:0] o_rsp_rdata_beats_out,
    output    [rsp_info_width-1:0] o_rsp_info_out,

    //-------------------------------------------------------
    // sntl insert into ISQ
    //-------------------------------------------------------

    output                  [63:0] sntl_ioq_req_lba,
    output                  [15:0] sntl_ioq_req_numblks,
    output                  [31:0] sntl_ioq_req_nsid,
    output                   [7:0] sntl_ioq_req_opcode,
    output                  [15:0] sntl_ioq_req_cmdid,
    output      [wbufid_width-1:0] sntl_ioq_req_wbufid,
    output     [datalen_width-1:0] sntl_ioq_req_reloff,
    output                         sntl_ioq_req_fua,
    output reg   [isq_idwidth-1:0] sntl_ioq_req_sqid,
    output                         sntl_ioq_req_valid,
    input                          ioq_sntl_req_ack,

    // which IOSQ to use
    input                          ioq_sntl_sqid_valid, // there's a submission queue entry available
    input        [isq_idwidth-1:0] ioq_sntl_sqid, // id of the submission queue with fewest entries in use
    output                         sntl_ioq_sqid_ack,
    output       [isq_idwidth-1:0] sntl_ioq_sqid,

    //-------------------------------------------------------
    // sntl completions from ICQ
    //-------------------------------------------------------

    input                   [14:0] ioq_sntl_cpl_status,
    input                   [15:0] ioq_sntl_cpl_cmdid,
    input                    [1:0] ioq_sntl_cpl_cmdid_par,
    input                          ioq_sntl_cpl_valid,
    output                         sntl_ioq_cpl_ack, 

    //-------------------------------------------------------
    // ucontrol IO bus
    //-------------------------------------------------------
    input                   [31:0] ctl_sntl_ioaddress,
    input                          ctl_sntl_ioread_strobe, 
    input                   [35:0] ctl_sntl_iowrite_data,
    input                          ctl_sntl_iowrite_strobe,
    output                  [31:0] sntl_ctl_ioread_data, 
    output                         sntl_ctl_ioack,

     
    //-------------------------------------------------------
    // DMA requests to SNTL (read/write payload)
    //-------------------------------------------------------
  
    input                          pcie_sntl_valid,
    input                  [144:0] pcie_sntl_data, 
    input                          pcie_sntl_first, 
    input                          pcie_sntl_last, 
    input                          pcie_sntl_discard, 
    output                         sntl_pcie_pause, 
    output                         sntl_pcie_ready, 

    //-------------------------------------------------------
    // DMA response from SNTL
    //-------------------------------------------------------        
 
    output                 [144:0] sntl_pcie_cc_data, 
    output                         sntl_pcie_cc_first,
    output                         sntl_pcie_cc_last,
    output                         sntl_pcie_cc_discard,
    output                         sntl_pcie_cc_valid,
    input                          pcie_sntl_cc_ready,

    
    //-------------------------------------------------------
    // NVMe/PCIe DMA requests to SNTL write buffer
    //-------------------------------------------------------
   
    input                          pcie_sntl_wbuf_valid,
    input                  [144:0] pcie_sntl_wbuf_data, 
    input                          pcie_sntl_wbuf_first, 
    input                          pcie_sntl_wbuf_last, 
    input                          pcie_sntl_wbuf_discard, 
    output                         sntl_pcie_wbuf_pause, 

    //-------------------------------------------------------
    // NVMe/PCIe DMA response from SNTL write buffer
    //-------------------------------------------------------   
    output                 [144:0] sntl_pcie_wbuf_cc_data, 
    output                         sntl_pcie_wbuf_cc_first, 
    output                         sntl_pcie_wbuf_cc_last,
    output                         sntl_pcie_wbuf_cc_discard, 
    output                         sntl_pcie_wbuf_cc_valid, 
    input                          pcie_sntl_wbuf_cc_ready,

    //-------------------------------------------------------
    // NVMe/PCIe DMA requests to SNTL admin buffer
    //-------------------------------------------------------
   
    input                          pcie_sntl_adbuf_valid,
    input                  [144:0] pcie_sntl_adbuf_data, 
    input                          pcie_sntl_adbuf_first, 
    input                          pcie_sntl_adbuf_last, 
    input                          pcie_sntl_adbuf_discard, 
    output                         sntl_pcie_adbuf_pause, 

    //-------------------------------------------------------
    // NVMe/PCIe DMA response from SNTL write buffer
    //-------------------------------------------------------   
    output                 [144:0] sntl_pcie_adbuf_cc_data, 
    output                         sntl_pcie_adbuf_cc_first, 
    output                         sntl_pcie_adbuf_cc_last,
    output                         sntl_pcie_adbuf_cc_discard, 
    output                         sntl_pcie_adbuf_cc_valid, 
    input                          pcie_sntl_adbuf_cc_ready,

    //-------------------------------------------------------
    // status to microcontroller
    //-------------------------------------------------------
    output                         sntl_ctl_admin_cmd_valid,
    output                         sntl_ctl_admin_cpl_valid,

    //-------------------------------------------------------
    // misc
    //-------------------------------------------------------
    input                          ctl_xx_csts_rdy,
    input                          ctl_xx_ioq_enable,
    input                          ctl_xx_shutdown,
    input                          ctl_xx_shutdown_cmp,
    output                         cmd_regs_lunreset,
    
    output                         sntl_ctl_idle,

    input                          regs_xx_tick1,
    input                   [35:0] regs_xx_timer1, // 1us per count - free running
    input                   [15:0] regs_xx_timer2, // 16.384ms per count - timer stops when backpressured
    input                   [15:0] regs_cmd_IOtimeout2, // timeout for I/O commands
    input                          regs_cmd_disableto,

    input   [datalen_width-1-12:0] regs_xx_maxxfer,
    input            [tag_width:0] regs_cmd_maxiowr, // number of writes outstanding
    input            [tag_width:0] regs_cmd_maxiord, // number of reads outstanding

    input                   [15:0] regs_cmd_debug,
    input                          regs_sntl_rsp_debug,
    input                    [7:0] regs_dma_errcpl,

    input                          regs_xx_freeze,

    input                   [11:0] regs_unmap_timer1,
    input                   [19:0] regs_unmap_timer2,
    input                    [7:0] regs_unmap_rangecount,
    input                    [7:0] regs_unmap_reqcount,

    input                    [7:0] pcie_sntl_rxcq_perf_events,
    input                          regs_sntl_perf_reset,

    //-------------------------------------------------------
    // debug
    //-------------------------------------------------------
  
    input                          regs_sntl_dbg_rd,
    input                    [9:0] regs_sntl_dbg_addr,
    output                  [63:0] sntl_regs_dbg_data,
    output                         sntl_regs_dbg_ack,
  
    input                          regs_cmd_trk_rd,
    input          [tag_width-1:0] regs_cmd_trk_addr,
    input                          regs_cmd_trk_addr_par,
    output                 [511:0] cmd_regs_trk_data,
    output                         cmd_regs_trk_ack,
    
    output                  [31:0] cmd_regs_dbgcount, // count requests/completions
    
    output                         sntl_regs_rdata_paused,
    output                         sntl_regs_cmd_idle,
    output                   [3:0] wbuf_regs_error,
    
    output                         sntl_regs_rsp_cnt,
    //-------------------------------------------------------
    // error inject on I/O commands
    
    input                          regs_cmd_errinj_valid,
    input                    [3:0] regs_cmd_errinj_select,
    input                   [31:0] regs_cmd_errinj_lba,
    input                          regs_cmd_errinj_uselba,
    input                   [15:0] regs_cmd_errinj_status,
    output                         cmd_regs_errinj_ack,
    output                         cmd_regs_errinj_cmdrd,
    output                         cmd_regs_errinj_cmdwr,

    input                          regs_wdata_errinj_valid,
    output                         wdata_regs_errinj_ack,
    output                         wdata_regs_errinj_active,
    output                   [3:0] admin_perror_ind,
    output                   [2:0] wbuf_perror_ind,
    output                         wdata_perror_ind,
    output                   [5:0] cmd_perror_ind,
    output                   [7:0] dma_perror_ind,
    output                         rsp_perror_ind,
    input                          regs_sntl_pe_errinj_valid,
    input                   [15:0] regs_xxx_pe_errinj_decode, 
    input                          regs_wdata_pe_errinj_1cycle_valid 

   
    );
   
   
   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire                 admin_cmd_ack;          // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [15:0]          admin_cmd_cpl_cmdid;    // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [1:0]           admin_cmd_cpl_cmdid_par;// From nvme_sntl_admin of nvme_sntl_admin.v
   wire [31:0]          admin_cmd_cpl_data;     // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [datalen_width-1:0] admin_cmd_cpl_length;// From nvme_sntl_admin of nvme_sntl_admin.v
   wire                 admin_cmd_cpl_length_par;// From nvme_sntl_admin of nvme_sntl_admin.v
   wire [14:0]          admin_cmd_cpl_status;   // From nvme_sntl_admin of nvme_sntl_admin.v
   wire                 admin_cmd_cpl_valid;    // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [7:0]           admin_cmd_lunlu_lbads;  // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [31:0]          admin_cmd_lunlu_nsid;   // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [63:0]          admin_cmd_lunlu_numlba; // From nvme_sntl_admin of nvme_sntl_admin.v
   wire                 admin_cmd_lunlu_status; // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [wdatalen_width-1:0] admin_dma_req_length;// From nvme_sntl_admin of nvme_sntl_admin.v
   wire                 admin_dma_req_length_par;// From nvme_sntl_admin of nvme_sntl_admin.v
   wire [datalen_width-1:0] admin_dma_req_reloff;// From nvme_sntl_admin of nvme_sntl_admin.v
   wire [tag_width-1:0] admin_dma_req_tag;      // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [0:0]           admin_dma_req_tag_par;  // From nvme_sntl_admin of nvme_sntl_admin.v
   wire                 admin_dma_req_valid;    // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [data_width-1:0] admin_rsp_data;        // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [data_fc_par_width-1:0] admin_rsp_data_par;// From nvme_sntl_admin of nvme_sntl_admin.v
   wire                 admin_rsp_last;         // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [12:0]          admin_rsp_req_length;   // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [datalen_width-1:0] admin_rsp_req_reloff;// From nvme_sntl_admin of nvme_sntl_admin.v
   wire [tag_width-1:0] admin_rsp_req_tag;      // From nvme_sntl_admin of nvme_sntl_admin.v
   wire                 admin_rsp_req_tag_par;  // From nvme_sntl_admin of nvme_sntl_admin.v
   wire                 admin_rsp_req_valid;    // From nvme_sntl_admin of nvme_sntl_admin.v
   wire                 admin_rsp_valid;        // From nvme_sntl_admin of nvme_sntl_admin.v
   wire [127:0]         cmd_admin_cdb;          // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [15:0]          cmd_admin_cid;          // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [1:0]           cmd_admin_cid_par;      // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [cmd_width-1:0] cmd_admin_cmd;          // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_admin_cpl_ack;      // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_admin_flush;        // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [datalen_width-1:0] cmd_admin_length;   // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [lunid_width-1:0] cmd_admin_lun;        // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_admin_lunlu_clraca; // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [lunidx_width-1:0] cmd_admin_lunlu_clraca_idx;// From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [lunidx_width-1:0] cmd_admin_lunlu_idx; // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_admin_lunlu_idx_par;// From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_admin_lunlu_setaca; // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [lunidx_width-1:0] cmd_admin_lunlu_setaca_idx;// From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_admin_lunlu_valid;  // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_admin_valid;        // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_dma_error;          // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_dma_ready;          // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_dma_valid;          // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_dma_wdata_ready;    // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [31:0]          cmd_perf_events;        // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [beatid_width-1:0] cmd_rsp_beats;       // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [fcstat_width-1:0] cmd_rsp_fc_status;   // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_rsp_fcp_valid;      // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [fcxstat_width-1:0] cmd_rsp_fcx_status; // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [rsp_info_width-1:0] cmd_rsp_info;      // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_rsp_overrun;        // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [31:0]          cmd_rsp_resid;          // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [7:0]           cmd_rsp_scsi_status;    // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_rsp_sns_valid;      // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [tag_width-1:0] cmd_rsp_tag;            // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_rsp_tag_par;        // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_rsp_underrun;       // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_rsp_v;              // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_unmap_ack;          // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [cid_width-1:0] cmd_unmap_cid;          // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [cid_par_width-1:0] cmd_unmap_cid_par;  // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [14:0]          cmd_unmap_cpl_status;   // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_unmap_cpl_valid;    // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_unmap_flush;        // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_unmap_ioidle;       // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_unmap_req_valid;    // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_wbuf_id_valid;      // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_wbuf_idfree_valid;  // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [wbufid_width-1:0] cmd_wbuf_idfree_wbufid;// From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [wbufid_par_width-1:0] cmd_wbuf_idfree_wbufid_par;// From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [cid_width-1:0] cmd_wbuf_req_cid;       // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [cid_par_width-1:0] cmd_wbuf_req_cid_par;// From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [63:0]          cmd_wbuf_req_lba;       // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [15:0]          cmd_wbuf_req_numblks;   // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [datalen_width-1:0] cmd_wbuf_req_reloff;// From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_wbuf_req_unmap;     // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_wbuf_req_valid;     // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [wbufid_width-1:0] cmd_wbuf_req_wbufid; // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [wbufid_par_width-1:0] cmd_wbuf_req_wbufid_par;// From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire                 cmd_wbuf_status_ready;  // From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [addr_width-1:0] dma_admin_addr;        // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [144:0]         dma_admin_data;         // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_admin_req_ack;      // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_admin_req_cpl;      // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_admin_valid;        // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [cid_width-1:0] dma_cmd_cid;            // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [cid_par_width-1:0] dma_cmd_cid_par;    // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [wdatalen_width-1:0] dma_cmd_length;    // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_cmd_length_par;     // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [datalen_width-1:0] dma_cmd_reloff;     // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_cmd_rnw;            // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_cmd_valid;          // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [cid_width-1:0] dma_cmd_wdata_cid;      // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [cid_par_width-1:0] dma_cmd_wdata_cid_par;// From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_cmd_wdata_error;    // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_cmd_wdata_valid;    // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [15:0]          dma_perf_events;        // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [127:0]         dma_rsp_data;           // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [1:0]           dma_rsp_data_par;       // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_rsp_first;          // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_rsp_last;           // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [wdatalen_width-1:0] dma_rsp_length;    // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [datalen_width-1:0] dma_rsp_reloff;     // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [tag_width-1:0] dma_rsp_tag;            // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_rsp_tag_par;        // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_rsp_valid;          // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_wdata_cpl_ready;    // From nvme_sntl_dma of nvme_sntl_dma.v
   wire [wdatalen_width-1:0] dma_wdata_req_length;// From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_wdata_req_length_par;// From nvme_sntl_dma of nvme_sntl_dma.v
   wire [datalen_width-1:0] dma_wdata_req_reloff;// From nvme_sntl_dma of nvme_sntl_dma.v
   wire [tag_width-1:0] dma_wdata_req_tag;      // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_wdata_req_tag_par;  // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 dma_wdata_req_valid;    // From nvme_sntl_dma of nvme_sntl_dma.v
   wire                 rsp_admin_ready;        // From nvme_sntl_rsp of nvme_sntl_rsp.v
   wire                 rsp_admin_req_ack;      // From nvme_sntl_rsp of nvme_sntl_rsp.v
   wire                 rsp_cmd_ack;            // From nvme_sntl_rsp of nvme_sntl_rsp.v
   wire                 rsp_dma_pause;          // From nvme_sntl_rsp of nvme_sntl_rsp.v
   wire [wbufid_par_width-1:0] sntl_ioq_req_wbufid_par;// From nvme_sntl_cmd of nvme_sntl_cmd.v
   wire [cid_width-1:0] unmap_cmd_cid;          // From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire [cid_par_width-1:0] unmap_cmd_cid_par;  // From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire [14:0]          unmap_cmd_cpl_status;   // From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire [3:0]           unmap_cmd_event;        // From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire [7:0]           unmap_cmd_reloff;       // From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire                 unmap_cmd_valid;        // From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire [wbufid_width-1:0] unmap_cmd_wbufid;    // From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire [wbufid_par_width-1:0] unmap_cmd_wbufid_par;// From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire                 unmap_wbuf_idfree_valid;// From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire [wbufid_width-1:0] unmap_wbuf_idfree_wbufid;// From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire [wbufid_par_width-1:0] unmap_wbuf_idfree_wbufid_par;// From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire                 unmap_wbuf_valid;       // From nvme_sntl_unmap of nvme_sntl_unmap.v
   wire                 wbuf_cmd_id_ack;        // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wbufid_width-1:0] wbuf_cmd_id_wbufid;  // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wbufid_par_width-1:0] wbuf_cmd_id_wbufid_par;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire                 wbuf_cmd_req_ready;     // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [cid_width-1:0] wbuf_cmd_status_cid;    // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [cid_par_width-1:0] wbuf_cmd_status_cid_par;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire                 wbuf_cmd_status_error;  // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire                 wbuf_cmd_status_valid;  // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wbufid_width-1:0] wbuf_cmd_status_wbufid;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wbufid_par_width-1:0] wbuf_cmd_status_wbufid_par;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire                 wbuf_unmap_ack;         // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire                 wbuf_unmap_idfree_ack;  // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wbufid_width-1:0] wbuf_unmap_wbufid;   // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wbufid_par_width-1:0] wbuf_unmap_wbufid_par;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wdatalen_width-1:0] wbuf_wdata_req_length;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wdatalen_par_width-1:0] wbuf_wdata_req_length_par;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [datalen_width-1:0] wbuf_wdata_req_reloff;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [tag_width-1:0] wbuf_wdata_req_tag;     // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [tag_par_width-1:0] wbuf_wdata_req_tag_par;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire                 wbuf_wdata_req_valid;   // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wbufid_width-1:0] wbuf_wdata_req_wbufid;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [wbufid_par_width-1:0] wbuf_wdata_req_wbufid_par;// From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire                 wbuf_wdata_rsp_ready;   // From nvme_sntl_wbuf of nvme_sntl_wbuf.v
   wire [129:0]         wdata_dma_cpl_data;     // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_dma_cpl_end;      // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_dma_cpl_error;    // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_dma_cpl_first;    // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_dma_cpl_last;     // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [9:0]           wdata_dma_cpl_length;   // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [datalen_width-1:0] wdata_dma_cpl_reloff;// From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [tag_width-1:0] wdata_dma_cpl_tag;      // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_dma_cpl_tag_par;  // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_dma_cpl_valid;    // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_dma_req_pause;    // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_wbuf_req_ready;   // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [beatid_width-1:0] wdata_wbuf_rsp_beat; // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [data_width-1:0] wdata_wbuf_rsp_data;   // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [data_fc_par_width-1:0] wdata_wbuf_rsp_data_par;// From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_wbuf_rsp_end;     // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_wbuf_rsp_error;   // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [tag_width-1:0] wdata_wbuf_rsp_tag;     // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [tag_par_width-1:0] wdata_wbuf_rsp_tag_par;// From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire                 wdata_wbuf_rsp_valid;   // From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [wbufid_width-1:0] wdata_wbuf_rsp_wbufid;// From nvme_sntl_wdata of nvme_sntl_wdata.v
   wire [wbufid_par_width-1:0] wdata_wbuf_rsp_wbufid_par;// From nvme_sntl_wdata of nvme_sntl_wdata.v
   // End of automatics
      
  nvme_sntl_cmd#
    (
     // afu/psl interface parameters
     .tag_width(tag_width), 
     .datalen_width(datalen_width),  
     .beatid_width(beatid_width),
     .data_width(data_width),
     .lunid_width(lunid_width),
     .cmd_width(cmd_width),
     .fcstat_width(fcstat_width),
     .fcxstat_width(fcxstat_width),
     .rsp_info_width(rsp_info_width),
     .lunidx_width(lunidx_width),
     .wbuf_numids(wbuf_numids),
     .isq_idwidth(isq_idwidth)
     ) nvme_sntl_cmd 
      (/*AUTOINST*/
       // Outputs
       .i_req_r_out                     (i_req_r_out),
       .cmd_admin_valid                 (cmd_admin_valid),
       .cmd_admin_cmd                   (cmd_admin_cmd[cmd_width-1:0]),
       .cmd_admin_cid                   (cmd_admin_cid[15:0]),
       .cmd_admin_cid_par               (cmd_admin_cid_par[1:0]),
       .cmd_admin_lun                   (cmd_admin_lun[lunid_width-1:0]),
       .cmd_admin_length                (cmd_admin_length[datalen_width-1:0]),
       .cmd_admin_cdb                   (cmd_admin_cdb[127:0]),
       .cmd_admin_flush                 (cmd_admin_flush),
       .cmd_admin_lunlu_valid           (cmd_admin_lunlu_valid),
       .cmd_admin_lunlu_idx             (cmd_admin_lunlu_idx[lunidx_width-1:0]),
       .cmd_admin_lunlu_idx_par         (cmd_admin_lunlu_idx_par),
       .cmd_admin_lunlu_setaca          (cmd_admin_lunlu_setaca),
       .cmd_admin_lunlu_setaca_idx      (cmd_admin_lunlu_setaca_idx[lunidx_width-1:0]),
       .cmd_admin_lunlu_clraca          (cmd_admin_lunlu_clraca),
       .cmd_admin_lunlu_clraca_idx      (cmd_admin_lunlu_clraca_idx[lunidx_width-1:0]),
       .cmd_rsp_v                       (cmd_rsp_v),
       .cmd_rsp_tag                     (cmd_rsp_tag[tag_width-1:0]),
       .cmd_rsp_tag_par                 (cmd_rsp_tag_par),
       .cmd_rsp_fc_status               (cmd_rsp_fc_status[fcstat_width-1:0]),
       .cmd_rsp_fcx_status              (cmd_rsp_fcx_status[fcxstat_width-1:0]),
       .cmd_rsp_scsi_status             (cmd_rsp_scsi_status[7:0]),
       .cmd_rsp_sns_valid               (cmd_rsp_sns_valid),
       .cmd_rsp_fcp_valid               (cmd_rsp_fcp_valid),
       .cmd_rsp_underrun                (cmd_rsp_underrun),
       .cmd_rsp_overrun                 (cmd_rsp_overrun),
       .cmd_rsp_resid                   (cmd_rsp_resid[31:0]),
       .cmd_rsp_beats                   (cmd_rsp_beats[beatid_width-1:0]),
       .cmd_rsp_info                    (cmd_rsp_info[rsp_info_width-1:0]),
       .sntl_ioq_req_lba                (sntl_ioq_req_lba[63:0]),
       .sntl_ioq_req_numblks            (sntl_ioq_req_numblks[15:0]),
       .sntl_ioq_req_nsid               (sntl_ioq_req_nsid[31:0]),
       .sntl_ioq_req_opcode             (sntl_ioq_req_opcode[7:0]),
       .sntl_ioq_req_cmdid              (sntl_ioq_req_cmdid[15:0]),
       .sntl_ioq_req_wbufid             (sntl_ioq_req_wbufid[wbufid_width-1:0]),
       .sntl_ioq_req_wbufid_par         (sntl_ioq_req_wbufid_par[wbufid_par_width-1:0]),
       .sntl_ioq_req_reloff             (sntl_ioq_req_reloff[datalen_width-1:0]),
       .sntl_ioq_req_fua                (sntl_ioq_req_fua),
       .sntl_ioq_req_sqid               (sntl_ioq_req_sqid[isq_idwidth-1:0]),
       .sntl_ioq_req_valid              (sntl_ioq_req_valid),
       .sntl_ioq_sqid_ack               (sntl_ioq_sqid_ack),
       .sntl_ioq_sqid                   (sntl_ioq_sqid[isq_idwidth-1:0]),
       .sntl_ioq_cpl_ack                (sntl_ioq_cpl_ack),
       .cmd_wbuf_req_valid              (cmd_wbuf_req_valid),
       .cmd_wbuf_req_cid                (cmd_wbuf_req_cid[cid_width-1:0]),
       .cmd_wbuf_req_cid_par            (cmd_wbuf_req_cid_par[cid_par_width-1:0]),
       .cmd_wbuf_req_reloff             (cmd_wbuf_req_reloff[datalen_width-1:0]),
       .cmd_wbuf_req_wbufid             (cmd_wbuf_req_wbufid[wbufid_width-1:0]),
       .cmd_wbuf_req_wbufid_par         (cmd_wbuf_req_wbufid_par[wbufid_par_width-1:0]),
       .cmd_wbuf_req_lba                (cmd_wbuf_req_lba[63:0]),
       .cmd_wbuf_req_numblks            (cmd_wbuf_req_numblks[15:0]),
       .cmd_wbuf_req_unmap              (cmd_wbuf_req_unmap),
       .cmd_wbuf_status_ready           (cmd_wbuf_status_ready),
       .cmd_wbuf_id_valid               (cmd_wbuf_id_valid),
       .cmd_wbuf_idfree_valid           (cmd_wbuf_idfree_valid),
       .cmd_wbuf_idfree_wbufid          (cmd_wbuf_idfree_wbufid[wbufid_width-1:0]),
       .cmd_wbuf_idfree_wbufid_par      (cmd_wbuf_idfree_wbufid_par[wbufid_par_width-1:0]),
       .cmd_unmap_req_valid             (cmd_unmap_req_valid),
       .cmd_unmap_cpl_valid             (cmd_unmap_cpl_valid),
       .cmd_unmap_cid                   (cmd_unmap_cid[cid_width-1:0]),
       .cmd_unmap_cid_par               (cmd_unmap_cid_par[cid_par_width-1:0]),
       .cmd_unmap_cpl_status            (cmd_unmap_cpl_status[14:0]),
       .cmd_unmap_flush                 (cmd_unmap_flush),
       .cmd_unmap_ioidle                (cmd_unmap_ioidle),
       .cmd_unmap_ack                   (cmd_unmap_ack),
       .cmd_admin_cpl_ack               (cmd_admin_cpl_ack),
       .cmd_dma_ready                   (cmd_dma_ready),
       .cmd_dma_valid                   (cmd_dma_valid),
       .cmd_dma_error                   (cmd_dma_error),
       .cmd_dma_wdata_ready             (cmd_dma_wdata_ready),
       .cmd_regs_lunreset               (cmd_regs_lunreset),
       .cmd_regs_trk_data               (cmd_regs_trk_data[511:0]),
       .cmd_regs_trk_ack                (cmd_regs_trk_ack),
       .cmd_regs_dbgcount               (cmd_regs_dbgcount[31:0]),
       .cmd_perf_events                 (cmd_perf_events[31:0]),
       .sntl_regs_cmd_idle              (sntl_regs_cmd_idle),
       .cmd_regs_errinj_ack             (cmd_regs_errinj_ack),
       .cmd_regs_errinj_cmdrd           (cmd_regs_errinj_cmdrd),
       .cmd_regs_errinj_cmdwr           (cmd_regs_errinj_cmdwr),
       .cmd_perror_ind                  (cmd_perror_ind[5:0]),
       // Inputs
       .reset                           (reset),
       .clk                             (clk),
       .i_req_v_in                      (i_req_v_in),
       .i_req_cmd_in                    (i_req_cmd_in[cmd_width-1:0]),
       .i_req_tag_in                    (i_req_tag_in[tag_width-1:0]),
       .i_req_tag_par_in                (i_req_tag_par_in[tag_par_width-1:0]),
       .i_req_lun_in                    (i_req_lun_in[lunid_width-1:0]),
       .i_req_lun_par_in                (i_req_lun_par_in[lunid_par_width-1:0]),
       .i_req_length_in                 (i_req_length_in[datalen_width-1:0]),
       .i_req_length_par_in             (i_req_length_par_in),
       .i_req_cdb_in                    (i_req_cdb_in[127:0]),
       .i_req_cdb_par_in                (i_req_cdb_par_in[1:0]),
       .admin_cmd_ack                   (admin_cmd_ack),
       .admin_cmd_lunlu_nsid            (admin_cmd_lunlu_nsid[31:0]),
       .admin_cmd_lunlu_lbads           (admin_cmd_lunlu_lbads[7:0]),
       .admin_cmd_lunlu_numlba          (admin_cmd_lunlu_numlba[63:0]),
       .admin_cmd_lunlu_status          (admin_cmd_lunlu_status),
       .rsp_cmd_ack                     (rsp_cmd_ack),
       .ioq_sntl_req_ack                (ioq_sntl_req_ack),
       .ioq_sntl_sqid_valid             (ioq_sntl_sqid_valid),
       .ioq_sntl_sqid                   (ioq_sntl_sqid[isq_idwidth-1:0]),
       .ioq_sntl_cpl_status             (ioq_sntl_cpl_status[14:0]),
       .ioq_sntl_cpl_cmdid              (ioq_sntl_cpl_cmdid[15:0]),
       .ioq_sntl_cpl_cmdid_par          (ioq_sntl_cpl_cmdid_par[1:0]),
       .ioq_sntl_cpl_valid              (ioq_sntl_cpl_valid),
       .wbuf_cmd_req_ready              (wbuf_cmd_req_ready),
       .wbuf_cmd_status_valid           (wbuf_cmd_status_valid),
       .wbuf_cmd_status_wbufid          (wbuf_cmd_status_wbufid[wbufid_width-1:0]),
       .wbuf_cmd_status_wbufid_par      (wbuf_cmd_status_wbufid_par[wbufid_par_width-1:0]),
       .wbuf_cmd_status_cid             (wbuf_cmd_status_cid[cid_width-1:0]),
       .wbuf_cmd_status_cid_par         (wbuf_cmd_status_cid_par[cid_par_width-1:0]),
       .wbuf_cmd_status_error           (wbuf_cmd_status_error),
       .wbuf_cmd_id_ack                 (wbuf_cmd_id_ack),
       .wbuf_cmd_id_wbufid              (wbuf_cmd_id_wbufid[wbufid_width-1:0]),
       .wbuf_cmd_id_wbufid_par          (wbuf_cmd_id_wbufid_par[wbufid_par_width-1:0]),
       .unmap_cmd_valid                 (unmap_cmd_valid),
       .unmap_cmd_cid                   (unmap_cmd_cid[cid_width-1:0]),
       .unmap_cmd_cid_par               (unmap_cmd_cid_par[cid_par_width-1:0]),
       .unmap_cmd_event                 (unmap_cmd_event[3:0]),
       .unmap_cmd_wbufid                (unmap_cmd_wbufid[wbufid_width-1:0]),
       .unmap_cmd_wbufid_par            (unmap_cmd_wbufid_par[wbufid_par_width-1:0]),
       .unmap_cmd_cpl_status            (unmap_cmd_cpl_status[14:0]),
       .unmap_cmd_reloff                (unmap_cmd_reloff[7:0]),
       .admin_cmd_cpl_status            (admin_cmd_cpl_status[14:0]),
       .admin_cmd_cpl_cmdid             (admin_cmd_cpl_cmdid[15:0]),
       .admin_cmd_cpl_cmdid_par         (admin_cmd_cpl_cmdid_par[1:0]),
       .admin_cmd_cpl_data              (admin_cmd_cpl_data[31:0]),
       .admin_cmd_cpl_length            (admin_cmd_cpl_length[datalen_width-1:0]),
       .admin_cmd_cpl_length_par        (admin_cmd_cpl_length_par),
       .admin_cmd_cpl_valid             (admin_cmd_cpl_valid),
       .dma_cmd_valid                   (dma_cmd_valid),
       .dma_cmd_cid                     (dma_cmd_cid[cid_width-1:0]),
       .dma_cmd_cid_par                 (dma_cmd_cid_par[cid_par_width-1:0]),
       .dma_cmd_rnw                     (dma_cmd_rnw),
       .dma_cmd_reloff                  (dma_cmd_reloff[datalen_width-1:0]),
       .dma_cmd_length                  (dma_cmd_length[wdatalen_width-1:0]),
       .dma_cmd_length_par              (dma_cmd_length_par),
       .dma_cmd_wdata_valid             (dma_cmd_wdata_valid),
       .dma_cmd_wdata_cid               (dma_cmd_wdata_cid[cid_width-1:0]),
       .dma_cmd_wdata_cid_par           (dma_cmd_wdata_cid_par[cid_par_width-1:0]),
       .dma_cmd_wdata_error             (dma_cmd_wdata_error),
       .ctl_xx_csts_rdy                 (ctl_xx_csts_rdy),
       .ctl_xx_ioq_enable               (ctl_xx_ioq_enable),
       .ctl_xx_shutdown                 (ctl_xx_shutdown),
       .ctl_xx_shutdown_cmp             (ctl_xx_shutdown_cmp),
       .regs_xx_timer1                  (regs_xx_timer1[35:0]),
       .regs_xx_timer2                  (regs_xx_timer2[15:0]),
       .regs_cmd_IOtimeout2             (regs_cmd_IOtimeout2[15:0]),
       .regs_xx_maxxfer                 (regs_xx_maxxfer[maxxfer_width-1:0]),
       .regs_cmd_maxiowr                (regs_cmd_maxiowr[tag_width:0]),
       .regs_cmd_maxiord                (regs_cmd_maxiord[tag_width:0]),
       .regs_xx_freeze                  (regs_xx_freeze),
       .regs_cmd_trk_rd                 (regs_cmd_trk_rd),
       .regs_cmd_trk_addr               (regs_cmd_trk_addr[tag_width-1:0]),
       .regs_cmd_trk_addr_par           (regs_cmd_trk_addr_par),
       .regs_cmd_debug                  (regs_cmd_debug[15:0]),
       .regs_cmd_disableto              (regs_cmd_disableto),
       .regs_cmd_errinj_valid           (regs_cmd_errinj_valid),
       .regs_cmd_errinj_select          (regs_cmd_errinj_select[3:0]),
       .regs_cmd_errinj_lba             (regs_cmd_errinj_lba[31:0]),
       .regs_cmd_errinj_uselba          (regs_cmd_errinj_uselba),
       .regs_cmd_errinj_status          (regs_cmd_errinj_status[15:0]),
       .regs_sntl_pe_errinj_valid       (regs_sntl_pe_errinj_valid),
       .regs_xxx_pe_errinj_decode       (regs_xxx_pe_errinj_decode[15:0]),
       .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));
                 
   
      
  nvme_sntl_rsp#
    (
     // afu/psl interface parameters
     .tag_width(tag_width), 
     .datalen_width(datalen_width),  
     .beatid_width(beatid_width),
     .data_width(data_width),
     .lunid_width(lunid_width),
     .cmd_width(cmd_width),
     .fcstat_width(fcstat_width),
     .fcxstat_width(fcxstat_width),
     .rsp_info_width(rsp_info_width)
     ) nvme_sntl_rsp
      (/*AUTOINST*/
       // Outputs
       .rsp_cmd_ack                     (rsp_cmd_ack),
       .rsp_dma_pause                   (rsp_dma_pause),
       .rsp_admin_req_ack               (rsp_admin_req_ack),
       .rsp_admin_ready                 (rsp_admin_ready),
       .o_rdata_rsp_v_out               (o_rdata_rsp_v_out),
       .o_rdata_rsp_e_out               (o_rdata_rsp_e_out),
       .o_rdata_rsp_c_out               (o_rdata_rsp_c_out[bytec_width-1:0]),
       .o_rdata_rsp_beat_out            (o_rdata_rsp_beat_out[beatid_width-1:0]),
       .o_rdata_rsp_tag_out             (o_rdata_rsp_tag_out[tag_width-1:0]),
       .o_rdata_rsp_tag_par_out         (o_rdata_rsp_tag_par_out),
       .o_rdata_rsp_data_out            (o_rdata_rsp_data_out[data_width-1:0]),
       .o_rdata_rsp_data_par_out        (o_rdata_rsp_data_par_out[data_fc_par_width-1:0]),
       .o_rsp_v_out                     (o_rsp_v_out),
       .o_rsp_tag_out                   (o_rsp_tag_out[tag_width-1:0]),
       .o_rsp_tag_par_out               (o_rsp_tag_par_out),
       .o_rsp_fc_status_out             (o_rsp_fc_status_out[fcstat_width-1:0]),
       .o_rsp_fcx_status_out            (o_rsp_fcx_status_out[fcxstat_width-1:0]),
       .o_rsp_scsi_status_out           (o_rsp_scsi_status_out[7:0]),
       .o_rsp_sns_valid_out             (o_rsp_sns_valid_out),
       .o_rsp_fcp_valid_out             (o_rsp_fcp_valid_out),
       .o_rsp_underrun_out              (o_rsp_underrun_out),
       .o_rsp_overrun_out               (o_rsp_overrun_out),
       .o_rsp_resid_out                 (o_rsp_resid_out[31:0]),
       .o_rsp_rdata_beats_out           (o_rsp_rdata_beats_out[beatid_width-1:0]),
       .o_rsp_info_out                  (o_rsp_info_out[rsp_info_width-1:0]),
       .sntl_regs_rdata_paused          (sntl_regs_rdata_paused),
       .sntl_regs_rsp_cnt               (sntl_regs_rsp_cnt),
       .rsp_perror_ind                  (rsp_perror_ind),
       // Inputs
       .reset                           (reset),
       .clk                             (clk),
       .cmd_rsp_v                       (cmd_rsp_v),
       .cmd_rsp_tag                     (cmd_rsp_tag[tag_width-1:0]),
       .cmd_rsp_tag_par                 (cmd_rsp_tag_par),
       .cmd_rsp_fc_status               (cmd_rsp_fc_status[fcstat_width-1:0]),
       .cmd_rsp_fcx_status              (cmd_rsp_fcx_status[fcxstat_width-1:0]),
       .cmd_rsp_scsi_status             (cmd_rsp_scsi_status[7:0]),
       .cmd_rsp_underrun                (cmd_rsp_underrun),
       .cmd_rsp_overrun                 (cmd_rsp_overrun),
       .cmd_rsp_resid                   (cmd_rsp_resid[31:0]),
       .cmd_rsp_sns_valid               (cmd_rsp_sns_valid),
       .cmd_rsp_fcp_valid               (cmd_rsp_fcp_valid),
       .cmd_rsp_info                    (cmd_rsp_info[rsp_info_width-1:0]),
       .cmd_rsp_beats                   (cmd_rsp_beats[beatid_width-1:0]),
       .dma_rsp_valid                   (dma_rsp_valid),
       .dma_rsp_reloff                  (dma_rsp_reloff[datalen_width-1:0]),
       .dma_rsp_length                  (dma_rsp_length[9:0]),
       .dma_rsp_tag                     (dma_rsp_tag[tag_width-1:0]),
       .dma_rsp_tag_par                 (dma_rsp_tag_par),
       .dma_rsp_data                    (dma_rsp_data[data_width-1:0]),
       .dma_rsp_data_par                (dma_rsp_data_par[data_fc_par_width-1:0]),
       .dma_rsp_first                   (dma_rsp_first),
       .dma_rsp_last                    (dma_rsp_last),
       .admin_rsp_req_valid             (admin_rsp_req_valid),
       .admin_rsp_req_tag               (admin_rsp_req_tag[tag_width-1:0]),
       .admin_rsp_req_tag_par           (admin_rsp_req_tag_par),
       .admin_rsp_req_reloff            (admin_rsp_req_reloff[datalen_width-1:0]),
       .admin_rsp_req_length            (admin_rsp_req_length[12:0]),
       .admin_rsp_valid                 (admin_rsp_valid),
       .admin_rsp_data                  (admin_rsp_data[data_width-1:0]),
       .admin_rsp_data_par              (admin_rsp_data_par[data_fc_par_width-1:0]),
       .admin_rsp_last                  (admin_rsp_last),
       .o_rdata_rsp_r_in                (o_rdata_rsp_r_in),
       .regs_xx_freeze                  (regs_xx_freeze),
       .regs_sntl_rsp_debug             (regs_sntl_rsp_debug),
       .regs_sntl_pe_errinj_valid       (regs_sntl_pe_errinj_valid),
       .regs_xxx_pe_errinj_decode       (regs_xxx_pe_errinj_decode[15:0]),
       .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));
                 
      
      
  nvme_sntl_dma#
    (
     // afu/psl interface parameters
     .tag_width(tag_width), 
     .datalen_width(datalen_width),  
     .beatid_width(beatid_width),
     .data_width(data_width),
     .addr_width(addr_width),
     .cid_width(cid_width)
        
     ) nvme_sntl_dma
      (/*AUTOINST*/
       // Outputs
       .dma_wdata_req_valid             (dma_wdata_req_valid),
       .dma_wdata_req_tag               (dma_wdata_req_tag[tag_width-1:0]),
       .dma_wdata_req_tag_par           (dma_wdata_req_tag_par),
       .dma_wdata_req_reloff            (dma_wdata_req_reloff[datalen_width-1:0]),
       .dma_wdata_req_length            (dma_wdata_req_length[wdatalen_width-1:0]),
       .dma_wdata_req_length_par        (dma_wdata_req_length_par),
       .dma_wdata_cpl_ready             (dma_wdata_cpl_ready),
       .dma_rsp_valid                   (dma_rsp_valid),
       .dma_rsp_reloff                  (dma_rsp_reloff[datalen_width-1:0]),
       .dma_rsp_length                  (dma_rsp_length[wdatalen_width-1:0]),
       .dma_rsp_tag                     (dma_rsp_tag[tag_width-1:0]),
       .dma_rsp_tag_par                 (dma_rsp_tag_par),
       .dma_rsp_data                    (dma_rsp_data[127:0]),
       .dma_rsp_data_par                (dma_rsp_data_par[1:0]),
       .dma_rsp_first                   (dma_rsp_first),
       .dma_rsp_last                    (dma_rsp_last),
       .dma_admin_valid                 (dma_admin_valid),
       .dma_admin_addr                  (dma_admin_addr[addr_width-1:0]),
       .dma_admin_data                  (dma_admin_data[144:0]),
       .dma_admin_req_ack               (dma_admin_req_ack),
       .dma_admin_req_cpl               (dma_admin_req_cpl),
       .dma_cmd_valid                   (dma_cmd_valid),
       .dma_cmd_cid                     (dma_cmd_cid[cid_width-1:0]),
       .dma_cmd_cid_par                 (dma_cmd_cid_par[cid_par_width-1:0]),
       .dma_cmd_rnw                     (dma_cmd_rnw),
       .dma_cmd_reloff                  (dma_cmd_reloff[datalen_width-1:0]),
       .dma_cmd_length                  (dma_cmd_length[wdatalen_width-1:0]),
       .dma_cmd_length_par              (dma_cmd_length_par),
       .dma_cmd_wdata_valid             (dma_cmd_wdata_valid),
       .dma_cmd_wdata_cid               (dma_cmd_wdata_cid[cid_width-1:0]),
       .dma_cmd_wdata_cid_par           (dma_cmd_wdata_cid_par[cid_par_width-1:0]),
       .dma_cmd_wdata_error             (dma_cmd_wdata_error),
       .sntl_pcie_pause                 (sntl_pcie_pause),
       .sntl_pcie_ready                 (sntl_pcie_ready),
       .sntl_pcie_cc_data               (sntl_pcie_cc_data[144:0]),
       .sntl_pcie_cc_first              (sntl_pcie_cc_first),
       .sntl_pcie_cc_last               (sntl_pcie_cc_last),
       .sntl_pcie_cc_discard            (sntl_pcie_cc_discard),
       .sntl_pcie_cc_valid              (sntl_pcie_cc_valid),
       .dma_perf_events                 (dma_perf_events[15:0]),
       .dma_perror_ind                  (dma_perror_ind[7:0]),
       // Inputs
       .reset                           (reset),
       .clk                             (clk),
       .wdata_dma_req_pause             (wdata_dma_req_pause),
       .wdata_dma_cpl_valid             (wdata_dma_cpl_valid),
       .wdata_dma_cpl_tag               (wdata_dma_cpl_tag[tag_width-1:0]),
       .wdata_dma_cpl_tag_par           (wdata_dma_cpl_tag_par),
       .wdata_dma_cpl_reloff            (wdata_dma_cpl_reloff[datalen_width-1:0]),
       .wdata_dma_cpl_length            (wdata_dma_cpl_length[9:0]),
       .wdata_dma_cpl_data              (wdata_dma_cpl_data[129:0]),
       .wdata_dma_cpl_first             (wdata_dma_cpl_first),
       .wdata_dma_cpl_last              (wdata_dma_cpl_last),
       .wdata_dma_cpl_error             (wdata_dma_cpl_error),
       .wdata_dma_cpl_end               (wdata_dma_cpl_end),
       .rsp_dma_pause                   (rsp_dma_pause),
       .admin_dma_req_valid             (admin_dma_req_valid),
       .admin_dma_req_tag               (admin_dma_req_tag[tag_width-1:0]),
       .admin_dma_req_tag_par           (admin_dma_req_tag_par),
       .admin_dma_req_reloff            (admin_dma_req_reloff[datalen_width-1:0]),
       .admin_dma_req_length            (admin_dma_req_length[wdatalen_width-1:0]),
       .admin_dma_req_length_par        (admin_dma_req_length_par),
       .cmd_dma_ready                   (cmd_dma_ready),
       .cmd_dma_valid                   (cmd_dma_valid),
       .cmd_dma_error                   (cmd_dma_error),
       .cmd_dma_wdata_ready             (cmd_dma_wdata_ready),
       .pcie_sntl_valid                 (pcie_sntl_valid),
       .pcie_sntl_data                  (pcie_sntl_data[144:0]),
       .pcie_sntl_first                 (pcie_sntl_first),
       .pcie_sntl_last                  (pcie_sntl_last),
       .pcie_sntl_discard               (pcie_sntl_discard),
       .pcie_sntl_cc_ready              (pcie_sntl_cc_ready),
       .regs_dma_errcpl                 (regs_dma_errcpl[7:0]),
       .regs_sntl_pe_errinj_valid       (regs_sntl_pe_errinj_valid),
       .regs_xxx_pe_errinj_decode       (regs_xxx_pe_errinj_decode[15:0]),
       .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));

       
      
  nvme_sntl_admin#
    ( .addr_width(addr_width),
      .lunidx_width(lunidx_width)  
     ) nvme_sntl_admin
      (/*AUTOINST*/
       // Outputs
       .admin_cmd_ack                   (admin_cmd_ack),
       .admin_dma_req_valid             (admin_dma_req_valid),
       .admin_dma_req_tag               (admin_dma_req_tag[tag_width-1:0]),
       .admin_dma_req_tag_par           (admin_dma_req_tag_par[0:0]),
       .admin_dma_req_reloff            (admin_dma_req_reloff[datalen_width-1:0]),
       .admin_dma_req_length            (admin_dma_req_length[wdatalen_width-1:0]),
       .admin_dma_req_length_par        (admin_dma_req_length_par),
       .admin_cmd_cpl_status            (admin_cmd_cpl_status[14:0]),
       .admin_cmd_cpl_cmdid             (admin_cmd_cpl_cmdid[15:0]),
       .admin_cmd_cpl_cmdid_par         (admin_cmd_cpl_cmdid_par[1:0]),
       .admin_cmd_cpl_data              (admin_cmd_cpl_data[31:0]),
       .admin_cmd_cpl_length            (admin_cmd_cpl_length[datalen_width-1:0]),
       .admin_cmd_cpl_length_par        (admin_cmd_cpl_length_par),
       .admin_cmd_cpl_valid             (admin_cmd_cpl_valid),
       .sntl_ctl_ioread_data            (sntl_ctl_ioread_data[31:0]),
       .sntl_ctl_ioack                  (sntl_ctl_ioack),
       .sntl_ctl_admin_cmd_valid        (sntl_ctl_admin_cmd_valid),
       .sntl_ctl_admin_cpl_valid        (sntl_ctl_admin_cpl_valid),
       .admin_cmd_lunlu_nsid            (admin_cmd_lunlu_nsid[31:0]),
       .admin_cmd_lunlu_lbads           (admin_cmd_lunlu_lbads[7:0]),
       .admin_cmd_lunlu_numlba          (admin_cmd_lunlu_numlba[63:0]),
       .admin_cmd_lunlu_status          (admin_cmd_lunlu_status),
       .admin_rsp_req_valid             (admin_rsp_req_valid),
       .admin_rsp_req_tag               (admin_rsp_req_tag[tag_width-1:0]),
       .admin_rsp_req_tag_par           (admin_rsp_req_tag_par),
       .admin_rsp_req_reloff            (admin_rsp_req_reloff[datalen_width-1:0]),
       .admin_rsp_req_length            (admin_rsp_req_length[12:0]),
       .admin_rsp_valid                 (admin_rsp_valid),
       .admin_rsp_data                  (admin_rsp_data[data_width-1:0]),
       .admin_rsp_data_par              (admin_rsp_data_par[data_fc_par_width-1:0]),
       .admin_rsp_last                  (admin_rsp_last),
       .sntl_pcie_adbuf_pause           (sntl_pcie_adbuf_pause),
       .sntl_pcie_adbuf_cc_data         (sntl_pcie_adbuf_cc_data[144:0]),
       .sntl_pcie_adbuf_cc_first        (sntl_pcie_adbuf_cc_first),
       .sntl_pcie_adbuf_cc_last         (sntl_pcie_adbuf_cc_last),
       .sntl_pcie_adbuf_cc_discard      (sntl_pcie_adbuf_cc_discard),
       .sntl_pcie_adbuf_cc_valid        (sntl_pcie_adbuf_cc_valid),
       .admin_perror_ind                (admin_perror_ind[3:0]),
       // Inputs
       .reset                           (reset),
       .clk                             (clk),
       .cmd_admin_valid                 (cmd_admin_valid),
       .cmd_admin_cmd                   (cmd_admin_cmd[cmd_width-1:0]),
       .cmd_admin_cid                   (cmd_admin_cid[15:0]),
       .cmd_admin_cid_par               (cmd_admin_cid_par[1:0]),
       .cmd_admin_lun                   (cmd_admin_lun[lunid_width-1:0]),
       .cmd_admin_length                (cmd_admin_length[datalen_width-1:0]),
       .cmd_admin_cdb                   (cmd_admin_cdb[127:0]),
       .cmd_admin_flush                 (cmd_admin_flush),
       .dma_admin_valid                 (dma_admin_valid),
       .dma_admin_addr                  (dma_admin_addr[addr_width-1:0]),
       .dma_admin_data                  (dma_admin_data[16+127:0]),
       .dma_admin_req_ack               (dma_admin_req_ack),
       .dma_admin_req_cpl               (dma_admin_req_cpl),
       .cmd_admin_cpl_ack               (cmd_admin_cpl_ack),
       .ctl_sntl_ioaddress              (ctl_sntl_ioaddress[31:0]),
       .ctl_sntl_ioread_strobe          (ctl_sntl_ioread_strobe),
       .ctl_sntl_iowrite_data           (ctl_sntl_iowrite_data[35:0]),
       .ctl_sntl_iowrite_strobe         (ctl_sntl_iowrite_strobe),
       .cmd_admin_lunlu_valid           (cmd_admin_lunlu_valid),
       .cmd_admin_lunlu_idx             (cmd_admin_lunlu_idx[lunidx_width-1:0]),
       .cmd_admin_lunlu_setaca          (cmd_admin_lunlu_setaca),
       .cmd_admin_lunlu_setaca_idx      (cmd_admin_lunlu_setaca_idx[lunidx_width-1:0]),
       .cmd_admin_lunlu_clraca          (cmd_admin_lunlu_clraca),
       .cmd_admin_lunlu_clraca_idx      (cmd_admin_lunlu_clraca_idx[lunidx_width-1:0]),
       .rsp_admin_req_ack               (rsp_admin_req_ack),
       .rsp_admin_ready                 (rsp_admin_ready),
       .pcie_sntl_adbuf_valid           (pcie_sntl_adbuf_valid),
       .pcie_sntl_adbuf_data            (pcie_sntl_adbuf_data[144:0]),
       .pcie_sntl_adbuf_first           (pcie_sntl_adbuf_first),
       .pcie_sntl_adbuf_last            (pcie_sntl_adbuf_last),
       .pcie_sntl_adbuf_discard         (pcie_sntl_adbuf_discard),
       .pcie_sntl_adbuf_cc_ready        (pcie_sntl_adbuf_cc_ready),
       .regs_sntl_pe_errinj_valid       (regs_sntl_pe_errinj_valid),
       .regs_xxx_pe_errinj_decode       (regs_xxx_pe_errinj_decode[15:0]),
       .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));
                 
            
  nvme_sntl_wdata#    
    (
     .data_width(data_width),
     .datalen_width(datalen_width),
     .wbuf_numids(wbuf_numids)   
     ) nvme_sntl_wdata
      (/*AUTOINST*/
       // Outputs
       .o_wdata_req_v_out               (o_wdata_req_v_out),
       .o_wdata_req_tag_out             (o_wdata_req_tag_out[tag_width-1:0]),
       .o_wdata_req_tag_par_out         (o_wdata_req_tag_par_out),
       .o_wdata_req_beat_out            (o_wdata_req_beat_out[beatid_width-1:0]),
       .o_wdata_req_size_out            (o_wdata_req_size_out[datalen_width-1:0]),
       .o_wdata_req_size_par_out        (o_wdata_req_size_par_out),
       .i_wdata_rsp_r_out               (i_wdata_rsp_r_out),
       .wdata_dma_req_pause             (wdata_dma_req_pause),
       .wdata_dma_cpl_valid             (wdata_dma_cpl_valid),
       .wdata_dma_cpl_tag               (wdata_dma_cpl_tag[tag_width-1:0]),
       .wdata_dma_cpl_tag_par           (wdata_dma_cpl_tag_par),
       .wdata_dma_cpl_reloff            (wdata_dma_cpl_reloff[datalen_width-1:0]),
       .wdata_dma_cpl_length            (wdata_dma_cpl_length[9:0]),
       .wdata_dma_cpl_data              (wdata_dma_cpl_data[129:0]),
       .wdata_dma_cpl_first             (wdata_dma_cpl_first),
       .wdata_dma_cpl_last              (wdata_dma_cpl_last),
       .wdata_dma_cpl_error             (wdata_dma_cpl_error),
       .wdata_dma_cpl_end               (wdata_dma_cpl_end),
       .wdata_wbuf_req_ready            (wdata_wbuf_req_ready),
       .wdata_wbuf_rsp_valid            (wdata_wbuf_rsp_valid),
       .wdata_wbuf_rsp_end              (wdata_wbuf_rsp_end),
       .wdata_wbuf_rsp_error            (wdata_wbuf_rsp_error),
       .wdata_wbuf_rsp_tag              (wdata_wbuf_rsp_tag[tag_width-1:0]),
       .wdata_wbuf_rsp_tag_par          (wdata_wbuf_rsp_tag_par[tag_par_width-1:0]),
       .wdata_wbuf_rsp_wbufid           (wdata_wbuf_rsp_wbufid[wbufid_width-1:0]),
       .wdata_wbuf_rsp_wbufid_par       (wdata_wbuf_rsp_wbufid_par[wbufid_par_width-1:0]),
       .wdata_wbuf_rsp_beat             (wdata_wbuf_rsp_beat[beatid_width-1:0]),
       .wdata_wbuf_rsp_data             (wdata_wbuf_rsp_data[data_width-1:0]),
       .wdata_wbuf_rsp_data_par         (wdata_wbuf_rsp_data_par[data_fc_par_width-1:0]),
       .wdata_regs_errinj_ack           (wdata_regs_errinj_ack),
       .wdata_regs_errinj_active        (wdata_regs_errinj_active),
       .wdata_perror_ind                (wdata_perror_ind),
       // Inputs
       .reset                           (reset),
       .clk                             (clk),
       .o_wdata_req_r_in                (o_wdata_req_r_in),
       .i_wdata_rsp_v_in                (i_wdata_rsp_v_in),
       .i_wdata_rsp_e_in                (i_wdata_rsp_e_in),
       .i_wdata_rsp_error_in            (i_wdata_rsp_error_in),
       .i_wdata_rsp_tag_in              (i_wdata_rsp_tag_in[tag_width-1:0]),
       .i_wdata_rsp_tag_par_in          (i_wdata_rsp_tag_par_in),
       .i_wdata_rsp_beat_in             (i_wdata_rsp_beat_in[beatid_width-1:0]),
       .i_wdata_rsp_data_in             (i_wdata_rsp_data_in[data_width-1:0]),
       .i_wdata_rsp_data_par_in         (i_wdata_rsp_data_par_in[data_fc_par_width-1:0]),
       .dma_wdata_req_valid             (dma_wdata_req_valid),
       .dma_wdata_req_tag               (dma_wdata_req_tag[tag_width-1:0]),
       .dma_wdata_req_tag_par           (dma_wdata_req_tag_par),
       .dma_wdata_req_reloff            (dma_wdata_req_reloff[datalen_width-1:0]),
       .dma_wdata_req_length            (dma_wdata_req_length[wdatalen_width-1:0]),
       .dma_wdata_req_length_par        (dma_wdata_req_length_par),
       .dma_wdata_cpl_ready             (dma_wdata_cpl_ready),
       .wbuf_wdata_req_valid            (wbuf_wdata_req_valid),
       .wbuf_wdata_req_tag              (wbuf_wdata_req_tag[tag_width-1:0]),
       .wbuf_wdata_req_tag_par          (wbuf_wdata_req_tag_par[tag_par_width-1:0]),
       .wbuf_wdata_req_reloff           (wbuf_wdata_req_reloff[datalen_width-1:0]),
       .wbuf_wdata_req_length           (wbuf_wdata_req_length[wdatalen_width-1:0]),
       .wbuf_wdata_req_length_par       (wbuf_wdata_req_length_par[wdatalen_par_width-1:0]),
       .wbuf_wdata_req_wbufid           (wbuf_wdata_req_wbufid[wbufid_width-1:0]),
       .wbuf_wdata_req_wbufid_par       (wbuf_wdata_req_wbufid_par[wbufid_par_width-1:0]),
       .wbuf_wdata_rsp_ready            (wbuf_wdata_rsp_ready),
       .regs_wdata_errinj_valid         (regs_wdata_errinj_valid),
       .regs_sntl_pe_errinj_valid       (regs_sntl_pe_errinj_valid),
       .regs_xxx_pe_errinj_decode       (regs_xxx_pe_errinj_decode[15:0]),
       .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));


              
  nvme_sntl_wbuf#    
    (
     .data_width(data_width),
     .datalen_width(datalen_width),
     .addr_width(addr_width) ,
     .wbuf_numids(wbuf_numids),
     .cid_width(cid_width) 
     ) nvme_sntl_wbuf
      (/*AUTOINST*/
       // Outputs
       .wbuf_cmd_req_ready              (wbuf_cmd_req_ready),
       .wbuf_cmd_status_valid           (wbuf_cmd_status_valid),
       .wbuf_cmd_status_wbufid          (wbuf_cmd_status_wbufid[wbufid_width-1:0]),
       .wbuf_cmd_status_wbufid_par      (wbuf_cmd_status_wbufid_par[wbufid_par_width-1:0]),
       .wbuf_cmd_status_cid             (wbuf_cmd_status_cid[cid_width-1:0]),
       .wbuf_cmd_status_cid_par         (wbuf_cmd_status_cid_par[cid_par_width-1:0]),
       .wbuf_cmd_status_error           (wbuf_cmd_status_error),
       .wbuf_cmd_id_ack                 (wbuf_cmd_id_ack),
       .wbuf_cmd_id_wbufid              (wbuf_cmd_id_wbufid[wbufid_width-1:0]),
       .wbuf_cmd_id_wbufid_par          (wbuf_cmd_id_wbufid_par[wbufid_par_width-1:0]),
       .wbuf_unmap_ack                  (wbuf_unmap_ack),
       .wbuf_unmap_wbufid               (wbuf_unmap_wbufid[wbufid_width-1:0]),
       .wbuf_unmap_wbufid_par           (wbuf_unmap_wbufid_par[wbufid_par_width-1:0]),
       .wbuf_unmap_idfree_ack           (wbuf_unmap_idfree_ack),
       .wbuf_wdata_req_valid            (wbuf_wdata_req_valid),
       .wbuf_wdata_req_tag              (wbuf_wdata_req_tag[tag_width-1:0]),
       .wbuf_wdata_req_tag_par          (wbuf_wdata_req_tag_par[tag_par_width-1:0]),
       .wbuf_wdata_req_reloff           (wbuf_wdata_req_reloff[datalen_width-1:0]),
       .wbuf_wdata_req_length           (wbuf_wdata_req_length[wdatalen_width-1:0]),
       .wbuf_wdata_req_length_par       (wbuf_wdata_req_length_par[wdatalen_par_width-1:0]),
       .wbuf_wdata_req_wbufid           (wbuf_wdata_req_wbufid[wbufid_width-1:0]),
       .wbuf_wdata_req_wbufid_par       (wbuf_wdata_req_wbufid_par[wbufid_par_width-1:0]),
       .wbuf_wdata_rsp_ready            (wbuf_wdata_rsp_ready),
       .sntl_pcie_wbuf_pause            (sntl_pcie_wbuf_pause),
       .sntl_pcie_wbuf_cc_data          (sntl_pcie_wbuf_cc_data[data_par_width+data_width:0]),
       .sntl_pcie_wbuf_cc_first         (sntl_pcie_wbuf_cc_first),
       .sntl_pcie_wbuf_cc_last          (sntl_pcie_wbuf_cc_last),
       .sntl_pcie_wbuf_cc_discard       (sntl_pcie_wbuf_cc_discard),
       .sntl_pcie_wbuf_cc_valid         (sntl_pcie_wbuf_cc_valid),
       .wbuf_regs_error                 (wbuf_regs_error[3:0]),
       .wbuf_perror_ind                 (wbuf_perror_ind[2:0]),
       // Inputs
       .reset                           (reset),
       .clk                             (clk),
       .cmd_wbuf_req_valid              (cmd_wbuf_req_valid),
       .cmd_wbuf_req_cid                (cmd_wbuf_req_cid[cid_width-1:0]),
       .cmd_wbuf_req_cid_par            (cmd_wbuf_req_cid_par[cid_par_width-1:0]),
       .cmd_wbuf_req_reloff             (cmd_wbuf_req_reloff[datalen_width-1:0]),
       .cmd_wbuf_req_wbufid             (cmd_wbuf_req_wbufid[wbufid_width-1:0]),
       .cmd_wbuf_req_wbufid_par         (cmd_wbuf_req_wbufid_par[wbufid_par_width-1:0]),
       .cmd_wbuf_req_lba                (cmd_wbuf_req_lba[63:0]),
       .cmd_wbuf_req_numblks            (cmd_wbuf_req_numblks[15:0]),
       .cmd_wbuf_req_unmap              (cmd_wbuf_req_unmap),
       .cmd_wbuf_status_ready           (cmd_wbuf_status_ready),
       .cmd_wbuf_id_valid               (cmd_wbuf_id_valid),
       .cmd_wbuf_idfree_valid           (cmd_wbuf_idfree_valid),
       .cmd_wbuf_idfree_wbufid          (cmd_wbuf_idfree_wbufid[wbufid_width-1:0]),
       .cmd_wbuf_idfree_wbufid_par      (cmd_wbuf_idfree_wbufid_par[wbufid_par_width-1:0]),
       .unmap_wbuf_valid                (unmap_wbuf_valid),
       .unmap_wbuf_idfree_valid         (unmap_wbuf_idfree_valid),
       .unmap_wbuf_idfree_wbufid        (unmap_wbuf_idfree_wbufid[wbufid_width-1:0]),
       .unmap_wbuf_idfree_wbufid_par    (unmap_wbuf_idfree_wbufid_par[wbufid_par_width-1:0]),
       .wdata_wbuf_req_ready            (wdata_wbuf_req_ready),
       .wdata_wbuf_rsp_valid            (wdata_wbuf_rsp_valid),
       .wdata_wbuf_rsp_end              (wdata_wbuf_rsp_end),
       .wdata_wbuf_rsp_error            (wdata_wbuf_rsp_error),
       .wdata_wbuf_rsp_tag              (wdata_wbuf_rsp_tag[tag_width-1:0]),
       .wdata_wbuf_rsp_tag_par          (wdata_wbuf_rsp_tag_par[tag_par_width-1:0]),
       .wdata_wbuf_rsp_wbufid           (wdata_wbuf_rsp_wbufid[wbufid_width-1:0]),
       .wdata_wbuf_rsp_wbufid_par       (wdata_wbuf_rsp_wbufid_par[wbufid_par_width-1:0]),
       .wdata_wbuf_rsp_beat             (wdata_wbuf_rsp_beat[beatid_width-1:0]),
       .wdata_wbuf_rsp_data             (wdata_wbuf_rsp_data[data_width-1:0]),
       .wdata_wbuf_rsp_data_par         (wdata_wbuf_rsp_data_par[data_fc_par_width-1:0]),
       .pcie_sntl_wbuf_valid            (pcie_sntl_wbuf_valid),
       .pcie_sntl_wbuf_data             (pcie_sntl_wbuf_data[data_par_width+data_width:0]),
       .pcie_sntl_wbuf_first            (pcie_sntl_wbuf_first),
       .pcie_sntl_wbuf_last             (pcie_sntl_wbuf_last),
       .pcie_sntl_wbuf_discard          (pcie_sntl_wbuf_discard),
       .pcie_sntl_wbuf_cc_ready         (pcie_sntl_wbuf_cc_ready),
       .regs_sntl_pe_errinj_valid       (regs_sntl_pe_errinj_valid),
       .regs_xxx_pe_errinj_decode       (regs_xxx_pe_errinj_decode[15:0]),
       .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));


              
  nvme_sntl_unmap#    
    (
     .data_width(data_width),
     .datalen_width(datalen_width),
     .wbuf_numids(wbuf_numids),
     .cid_width(cid_width) 
     ) nvme_sntl_unmap
      (/*AUTOINST*/
       // Outputs
       .unmap_cmd_valid                 (unmap_cmd_valid),
       .unmap_cmd_cid                   (unmap_cmd_cid[cid_width-1:0]),
       .unmap_cmd_cid_par               (unmap_cmd_cid_par[cid_par_width-1:0]),
       .unmap_cmd_event                 (unmap_cmd_event[3:0]),
       .unmap_cmd_wbufid                (unmap_cmd_wbufid[wbufid_width-1:0]),
       .unmap_cmd_wbufid_par            (unmap_cmd_wbufid_par[wbufid_par_width-1:0]),
       .unmap_cmd_cpl_status            (unmap_cmd_cpl_status[14:0]),
       .unmap_cmd_reloff                (unmap_cmd_reloff[7:0]),
       .unmap_wbuf_valid                (unmap_wbuf_valid),
       .unmap_wbuf_idfree_valid         (unmap_wbuf_idfree_valid),
       .unmap_wbuf_idfree_wbufid        (unmap_wbuf_idfree_wbufid[wbufid_width-1:0]),
       .unmap_wbuf_idfree_wbufid_par    (unmap_wbuf_idfree_wbufid_par[wbufid_par_width-1:0]),
       // Inputs
       .reset                           (reset),
       .clk                             (clk),
       .regs_xx_tick1                   (regs_xx_tick1),
       .regs_unmap_timer1               (regs_unmap_timer1[11:0]),
       .regs_unmap_timer2               (regs_unmap_timer2[19:0]),
       .regs_unmap_rangecount           (regs_unmap_rangecount[7:0]),
       .regs_unmap_reqcount             (regs_unmap_reqcount[7:0]),
       .cmd_unmap_req_valid             (cmd_unmap_req_valid),
       .cmd_unmap_cpl_valid             (cmd_unmap_cpl_valid),
       .cmd_unmap_cid                   (cmd_unmap_cid[cid_width-1:0]),
       .cmd_unmap_cid_par               (cmd_unmap_cid_par[cid_par_width-1:0]),
       .cmd_unmap_cpl_status            (cmd_unmap_cpl_status[14:0]),
       .cmd_unmap_flush                 (cmd_unmap_flush),
       .cmd_unmap_ioidle                (cmd_unmap_ioidle),
       .cmd_unmap_ack                   (cmd_unmap_ack),
       .wbuf_unmap_wbufid               (wbuf_unmap_wbufid[wbufid_width-1:0]),
       .wbuf_unmap_wbufid_par           (wbuf_unmap_wbufid_par[wbufid_par_width-1:0]),
       .wbuf_unmap_ack                  (wbuf_unmap_ack),
       .wbuf_unmap_idfree_ack           (wbuf_unmap_idfree_ack));


              
  nvme_sntl_perf#    
    (     
     .dbg_dma(0) 
     ) nvme_sntl_perf
      (/*AUTOINST*/
       // Outputs
       .sntl_regs_dbg_data              (sntl_regs_dbg_data[63:0]),
       .sntl_regs_dbg_ack               (sntl_regs_dbg_ack),
       // Inputs
       .reset                           (reset),
       .clk                             (clk),
       .cmd_perf_events                 (cmd_perf_events[31:0]),
       .dma_perf_events                 (dma_perf_events[15:0]),
       .pcie_sntl_rxcq_perf_events      (pcie_sntl_rxcq_perf_events[7:0]),
       .regs_sntl_perf_reset            (regs_sntl_perf_reset),
       .regs_sntl_dbg_rd                (regs_sntl_dbg_rd),
       .regs_sntl_dbg_addr              (regs_sntl_dbg_addr[9:0]));


   assign sntl_ctl_idle = sntl_regs_cmd_idle;
                            
endmodule


