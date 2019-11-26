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
//  File : nvme_sntl_admin.v
//  *************************************************************************
//  *************************************************************************
//  Description : Interface to microcontroller for handling admin commands

//  *************************************************************************

module nvme_sntl_admin#
  ( // afu/psl   interface parameters
    parameter tag_width       = 8,
    parameter datalen_width   = 25,
    parameter data_width      = 128,
    parameter data_bytes      = data_width/8,
    parameter bytec_width     = $clog2(data_bytes+1),
    parameter beatid_width    = datalen_width-$clog2(data_bytes),    
    parameter lunid_width     = 64, 
    parameter cmd_width       = 4, 
    parameter fcstat_width    = 8, 
    parameter fcxstat_width   = 8, 
    parameter rsp_info_width  = 160,
    parameter tag_par_width   = (tag_width + 7)/8, 
    parameter lunid_par_width = (lunid_width + 7)/8, 
    parameter data_par_width  = (data_width + 7) / 8,
    parameter data_fc_par_width = data_par_width/8,
    parameter status_width    = 8, // event status
    parameter wdatalen_width  = 13,
    //
    parameter lunidx_width    = 8, // support 255 LUNs max
    parameter addr_width      = 48,
    parameter cid_width       = 16
    )
   (
    input                              reset,
    input                              clk,

    //-------------------------------------------------------
    // requests from sislite 
    // this interface is checked at output of nvme_sntl_cmd.v  - no parity coverage needed kch 
    //-------------------------------------------------------
    input                              cmd_admin_valid,
    output reg                         admin_cmd_ack,
    input              [cmd_width-1:0] cmd_admin_cmd, 
    input                       [15:0] cmd_admin_cid, 
    input                        [1:0] cmd_admin_cid_par, // added kch 
    input            [lunid_width-1:0] cmd_admin_lun, 
    input          [datalen_width-1:0] cmd_admin_length, 
    input                      [127:0] cmd_admin_cdb,
    input                              cmd_admin_flush,
    
    //-------------------------------------------------------
    // payload from NVMe or host
    //-------------------------------------------------------
  
    input                              dma_admin_valid,
    input             [addr_width-1:0] dma_admin_addr, 
    input                   [16+127:0] dma_admin_data, // added 16+ for parity  
    
    // ----------------------------------------------------
    // admin host DMA read request
    // ----------------------------------------------------

    output reg                         admin_dma_req_valid,
    output reg         [tag_width-1:0] admin_dma_req_tag, // afu req tag
    output reg                   [0:0] admin_dma_req_tag_par, // added kch 
    output reg     [datalen_width-1:0] admin_dma_req_reloff, // offset from start address of this command
    output reg    [wdatalen_width-1:0] admin_dma_req_length, // number of bytes to request, max 512B
    output reg                         admin_dma_req_length_par, 
    input                              dma_admin_req_ack, 
    input                              dma_admin_req_cpl, 
        
    //-------------------------------------------------------
    // sntl completions for admin commands
    //-------------------------------------------------------

    output reg                  [14:0] admin_cmd_cpl_status, // NVMe encoded status
    output reg                  [15:0] admin_cmd_cpl_cmdid, // command id
    output reg                   [1:0] admin_cmd_cpl_cmdid_par, // command id
    output reg                  [31:0] admin_cmd_cpl_data,
    output reg     [datalen_width-1:0] admin_cmd_cpl_length, // actual length of payload for resid calc
    output reg                         admin_cmd_cpl_length_par, 
    output reg                         admin_cmd_cpl_valid,
    input                              cmd_admin_cpl_ack,

    //-------------------------------------------------------
    // ucontrol IO bus
    //-------------------------------------------------------
    input                       [31:0] ctl_sntl_ioaddress,
    input                              ctl_sntl_ioread_strobe, 
    input                       [35:0] ctl_sntl_iowrite_data,
    input                              ctl_sntl_iowrite_strobe,
    output reg                  [31:0] sntl_ctl_ioread_data, 
    output reg                         sntl_ctl_ioack,
    
    //-------------------------------------------------------
    // status to microcontroller
    //-------------------------------------------------------
    output reg                         sntl_ctl_admin_cmd_valid,
    output reg                         sntl_ctl_admin_cpl_valid,
    
    //-------------------------------------------------------
    // sislite LUN to namespace info lookup
    //-------------------------------------------------------
    input                              cmd_admin_lunlu_valid,
    input           [lunidx_width-1:0] cmd_admin_lunlu_idx, // index into lun lookup table
    output reg                  [31:0] admin_cmd_lunlu_nsid, // namespace id.  1 cycle after valid
    output reg                   [7:0] admin_cmd_lunlu_lbads, // blocksize in bytes = 2**lbads
    output reg                  [63:0] admin_cmd_lunlu_numlba, // number of 4K blocks
    output reg                         admin_cmd_lunlu_status,

    input                              cmd_admin_lunlu_setaca,
    input           [lunidx_width-1:0] cmd_admin_lunlu_setaca_idx,

    input                              cmd_admin_lunlu_clraca,
    input           [lunidx_width-1:0] cmd_admin_lunlu_clraca_idx,
    
    // ---------------------------------------------------------
    // admin payload ready inteface - valid/ack
    // ---------------------------------------------------------
    output reg                         admin_rsp_req_valid, // asserted when admin_rsp_req_* is valid.  held until rsp_admin_req_ack
    input                              rsp_admin_req_ack, // asserted when req is taken
    output reg         [tag_width-1:0] admin_rsp_req_tag, // sislite interface tag
    output reg                         admin_rsp_req_tag_par, 
    output reg     [datalen_width-1:0] admin_rsp_req_reloff, // byte offset from start of payload
    output reg                  [12:0] admin_rsp_req_length, // payload length in bytes (4KB max)

    // ---------------------------------------------------------
    // admin payload interface - valid/ready
    // ---------------------------------------------------------
    output reg                         admin_rsp_valid, 
    output reg        [data_width-1:0] admin_rsp_data, // payload data
    output reg [data_fc_par_width-1:0] admin_rsp_data_par, // payload data
    output reg                         admin_rsp_last, // indicates last data cycle (should be consistent with admin_rsp_req_length)
    input                              rsp_admin_ready, // indicates data was taken this cycle,

    //-------------------------------------------------------
    // NVMe/PCIe DMA requests to SNTL admin buffer
    //-------------------------------------------------------
     
    input                              pcie_sntl_adbuf_valid,
    input                      [144:0] pcie_sntl_adbuf_data, 
    input                              pcie_sntl_adbuf_first, 
    input                              pcie_sntl_adbuf_last, 
    input                              pcie_sntl_adbuf_discard, 
    output                             sntl_pcie_adbuf_pause, 

    //-------------------------------------------------------
    // NVMe/PCIe DMA response from SNTL write buffer
    //-------------------------------------------------------   
    output                     [144:0] sntl_pcie_adbuf_cc_data, 
    output                             sntl_pcie_adbuf_cc_first, 
    output                             sntl_pcie_adbuf_cc_last,
    output                             sntl_pcie_adbuf_cc_discard, 
    output                             sntl_pcie_adbuf_cc_valid, 
    input                              pcie_sntl_adbuf_cc_ready,

    
    // ----------------------------------------------------------
    // parity error inject 
    // ----------------------------------------------------------
    output                       [3:0] admin_perror_ind,
    input                              regs_sntl_pe_errinj_valid,
    input                       [15:0] regs_xxx_pe_errinj_decode, 
    input                              regs_wdata_pe_errinj_1cycle_valid 

    
    );

`include "nvme_func.svh"

   // command flow:
   // 1. command valid bit is zero.  receive command request and load request registers
   // 2. microcontroller detects command by polling on I/O port
   // 3. ucode reads command request registers and issues a admin command
   // 4. admin command payload is loaded into adq payload buffer by dma from NVMe
   // 5. ucode polls for command completion
   // 6. ucode reads adq payload buffer
   // 7. ucode clears sislite payload buffer by writing sisl_clear reg
   // 8. ucode writes sislite payload buffer
   // 9. ucode writes sisl_reloff/sisl_cid/sisl_length
   // 10. ucode writes sisl_payload register.  payload state machine starts sending payload to sntl_rsp
   // 11. ucode writes status regs. response state machine sends completion and clears valid bits.
   // 12. ucode polls for completion done.  goto step 1.

   // microcontroller address map for admin command handling
   //
   // ctl_sntl_ioaddress[13:0] = byte address offset for sntl registers
   // each access is a dword  (4B)
   //
   // subregions:
   // address[13:12]  description
   //              0 command/status registers    
   //              1 sislite payload buffer (4K)
   //              2 adq payload buffer (4K)
   //              3 namespace id table/namespace size table
   
   reg          iowrite_regs_ack;
   reg          iowrite_sisl_ack;
   reg          iowrite_adq_ack;
   reg          iowrite_other_ack;   
   
   reg          ioread_regs_ack;
   (* mark_debug = "false" *)
   reg          ioread_sisl_ack_q, ioread_sisl_ack_d;   
   reg          ioread_adq_ack_q, ioread_adq_ack_d;
   reg          ioread_other_ack;
   
   reg   [31:0] ioread_regs_data;
   reg   [31:0] ioread_sisl_data;
   reg [4+31:0] ioread_adq_data;   // added 4+ kch 
   reg   [31:0] ioread_other_data;
   
   wire   [3:0] admin_perror_int;
   wire   [3:0] s1_perror; 

   // Parity error srlat 

   // set/reset/ latch for parity errors kch 
   nvme_srlat#
     (.width(4))  iadmin_sr   
       (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(admin_perror_int));

   assign admin_perror_ind = admin_perror_int;

   reg    [3:0] admin_pe_inj_d,admin_pe_inj_q;

   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin  
             admin_pe_inj_q <= 1'b0;     
          end
        else
          begin            
             admin_pe_inj_q <= admin_pe_inj_d;      
          end
     end
   
   always @*
     begin       
        admin_pe_inj_d = admin_pe_inj_q;      
        if (regs_wdata_pe_errinj_1cycle_valid & regs_sntl_pe_errinj_valid & regs_xxx_pe_errinj_decode[11:8] == 4'h0)
          begin
             admin_pe_inj_d[0]  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
             admin_pe_inj_d[1]  = (regs_xxx_pe_errinj_decode[3:0]==4'h1);
             admin_pe_inj_d[2]  = (regs_xxx_pe_errinj_decode[3:0]==4'h2);
             admin_pe_inj_d[3]  = (regs_xxx_pe_errinj_decode[3:0]==4'h3);
          end 
        if (admin_pe_inj_q[0] & ctl_sntl_iowrite_strobe)
          admin_pe_inj_d[0] = 1'b0;
        if (admin_pe_inj_q[1] & ioread_adq_ack_q)
          admin_pe_inj_d[1] = 1'b0;
        if (admin_pe_inj_q[2] & admin_cmd_cpl_valid) 
          admin_pe_inj_d[2] = 1'b0;
        if (admin_pe_inj_q[3] & admin_cmd_cpl_valid)
          admin_pe_inj_d[3] = 1'b0;
     end  
   // parity check dw read 
   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(32)
      ) ipcheck_ioread_adq_data
       (.oddpar(1'b1),.data({ioread_adq_data[31:1],(ioread_adq_data[0]^admin_pe_inj_q[1])}),.datap(ioread_adq_data[35:32]),.check(ioread_adq_ack_q),.parerr(s1_perror[1])); 

   always @(posedge clk)
     begin
        sntl_ctl_ioack <=  iowrite_regs_ack |
                           iowrite_sisl_ack |
                           iowrite_adq_ack |
                           iowrite_other_ack |
                           ioread_regs_ack |
                           ioread_sisl_ack_q |
                           ioread_adq_ack_q |
                           ioread_other_ack;
        sntl_ctl_ioread_data <= (ioread_regs_data  & {32{ioread_regs_ack}}) |
                                (ioread_sisl_data  & {32{ioread_sisl_ack_q}}) |
                                (ioread_adq_data   & {32{ioread_adq_ack_q}}) |
                                (ioread_other_data & {32{ioread_other_ack}});
     end
   
   // ---------------------------------------------------------
   // region 0 - command/status registers
   // ---------------------------------------------------------
   // 
   // offset   description
   //          request registers
   // x00      command
   //            15    - valid
   //            7:0 - sislite command
   // x04      length
   // x08      lun[31:0] 
   // x0c      lun[63:32]
   // x10      cdb0-3
   // x14      cdb4-7
   // x18      cdb8-11
   // x1c      cdb12-15
   //
   //          response registers
   // x20      sisl_cid
   //            15:0 sislite command id  (instcnt/tag)
   //            16 - set when dma to host completes
   //            17 - set submit dma request to host.  cleared when complete.
   //            18 - dma data buffer:  0: sislbuf  1: adbuf
   // x24      sisl_reloff
   //            25:0 - starting byte address of sisl payload (must be 16B aligned)
   // x28      sisl_length
   //            12:0 - length in bytes of sisl payload
   // 
   // x2c      status0
   //            15    - completion valid
   //            14    - Do Not retry
   //            13    - More
   //            12:11 - reserved
   //            10:8  - status code type
   //            7:0   - status code
   // x30      status1
   //            31:0 - DW0 from NVMe completion
   // x40      sisl_clear
   //            31:0 - don't care.  any write causes sisl payload buffer to be cleared
   // x44      sisl_payload
   //            31:0 - don't care.  write causes payload to be sent
   // x48      adbuf_clear
   //            31:0 - don't care.  any write causes admin buffer to be cleared
   
   reg                      [15:0] command_q;
   reg         [datalen_width-1:0] length_q;
   reg           [lunid_width-1:0] lun_q;
   reg                     [127:0] cdb_q;
   reg                      [18:0] sisl_cid_q;
   reg                       [1:0] sisl_cid_par_q;
   reg         [datalen_width-1:0] sisl_reloff_q;
   reg                             sisl_reloff_par_q;
   reg                      [12:0] sisl_length_q;   
   reg                             sisl_length_par_q;   
   reg                      [15:0] status_q;
   reg                      [31:0] status_dw0_q;
   reg                             sisl_clear_q;
   reg                             sisl_clear_reset;
   (* mark_debug = "false" *)
   reg                             sisl_payload_q;
   reg                             sisl_payload_reset;
   reg                             adbuf_clear_q;
   reg                             adbuf_clear_reset;
   
   reg                      [15:0] command_d;
   reg         [datalen_width-1:0] length_d;
   reg           [lunid_width-1:0] lun_d;
   reg                     [127:0] cdb_d;
   reg                      [18:0] sisl_cid_d;
   reg                       [1:0] sisl_cid_par_d;
   reg         [datalen_width-1:0] sisl_reloff_d;
   reg                             sisl_reloff_par_d;
   reg                      [12:0] sisl_length_d;   
   reg                             sisl_length_par_d;   
   reg                      [15:0] status_d;
   reg                      [31:0] status_dw0_d;
   reg                             sisl_clear_d;
   reg                             sisl_payload_d;
   reg                             adbuf_clear_d;
   
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin        
             command_q         <= zero[15:0];        
             length_q          <= zero[datalen_width-1:0];
             lun_q             <= zero[lunid_width-1:0];
             cdb_q             <= zero[127:0];
             sisl_cid_q        <= zero[18:0];
             sisl_cid_par_q    <= 2'b11;
             sisl_reloff_q     <= zero[datalen_width-1:0];
             sisl_reloff_par_q <= 1'b1;
             sisl_length_q     <= zero[12:0];
             sisl_length_par_q <= 1'b1;
             status_q          <= zero[15:0];
             status_dw0_q      <= zero[31:0];
             sisl_clear_q      <= 1'b1;
             sisl_payload_q    <= 1'b0;
             adbuf_clear_q     <= 1'b1;
         end
        else
          begin            
             command_q         <= command_d;           
             length_q          <= length_d;
             lun_q             <= lun_d;
             cdb_q             <= cdb_d;
             sisl_cid_q        <= sisl_cid_d;
             sisl_cid_par_q    <= sisl_cid_par_d;
             sisl_reloff_q     <= sisl_reloff_d;
             sisl_reloff_par_q <= sisl_reloff_par_d;
             sisl_length_q     <= sisl_length_d;
             sisl_length_par_q <= sisl_length_par_d;
             status_q          <= status_d;
             status_dw0_q      <= status_dw0_d;  
             sisl_clear_q      <= sisl_clear_d;
             sisl_payload_q    <= sisl_payload_d;
             adbuf_clear_q     <= adbuf_clear_d;
          end
     end
   // check parity 

   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(32)
      ) ipcheck_ctl_sntl_iowrite_data
       (.oddpar(1'b1),.data({ctl_sntl_iowrite_data[31:1],(ctl_sntl_iowrite_data[0]^admin_pe_inj_q[0])}),.datap(ctl_sntl_iowrite_data[35:32]),.check(ctl_sntl_iowrite_strobe),.parerr(s1_perror[0])); 

   // pgen sisl_reloff_d fixit 
   
   wire                      sisl_reloff_par;
   nvme_pgen#
     (
      .bits_per_parity_bit(64),
      .width(datalen_width)
      ) ipgen_sisl_reloff_d 
       (.oddpar(1'b1),.data(sisl_reloff_d),.datap(sisl_reloff_par)); 

   wire                      sisl_length_par;
   nvme_pgen#
     (
      .bits_per_parity_bit(64),
      .width(13)
      ) ipgen_sisl_length_d 
       (.oddpar(1'b1),.data(sisl_length_d),.datap(sisl_length_par)); 

   wire                      admin_cmd_cpl_length_par_in;
   nvme_pgen#
     (
      .bits_per_parity_bit(64),
      .width(datalen_width)
      ) ipgen_admin_cmd_cpl_length 
       (.oddpar(1'b1),.data(admin_cmd_cpl_length),.datap(admin_cmd_cpl_length_par_in)); 

   // parity check fixit 
   nvme_pcheck#
     (
      .bits_per_parity_bit(64),
      .width(datalen_width)
      ) ipcheck_sisl_reloff_q
       (.oddpar(1'b1),.data({sisl_reloff_q[datalen_width-1:1],(sisl_reloff_q[0]^admin_pe_inj_q[2])}),.datap(sisl_reloff_par_q),.check(admin_cmd_cpl_valid),.parerr(s1_perror[2])); 

   // parity check fixit 
   nvme_pcheck#
     (
      .bits_per_parity_bit(64),
      .width(13)
      ) ipcheck_sisl_length_q
       (.oddpar(1'b1),.data({sisl_length_q[12:1],(sisl_length_q[0]^admin_pe_inj_q[3])}),.datap(sisl_length_par_q),.check(admin_cmd_cpl_valid),.parerr(s1_perror[3])); 


   always @*
     begin
        command_d          = command_q;           
        length_d           = length_q;
        lun_d              = lun_q;
        cdb_d              = cdb_q;
        sisl_cid_d         = sisl_cid_q;
        sisl_cid_par_d     = sisl_cid_par_q;
        sisl_reloff_d      = sisl_reloff_q;
        sisl_reloff_par_d  = sisl_reloff_par_q;
        sisl_length_d      = sisl_length_q;
        sisl_length_par_d  = sisl_length_par_q;
        status_d           = status_q;
        status_dw0_d       = status_dw0_q;
        sisl_clear_d       = sisl_clear_q & ~sisl_clear_reset;
        sisl_payload_d     = sisl_payload_q & ~sisl_payload_reset;
        adbuf_clear_d      = adbuf_clear_q & ~adbuf_clear_reset;

        if( cmd_admin_valid & ~command_q[15] )
          begin
             command_d       = {1'b1, zero[14:cmd_width], cmd_admin_cmd };
             sisl_cid_d      = { 3'b000, cmd_admin_cid};
             sisl_cid_par_d  = cmd_admin_cid_par;
             length_d        = cmd_admin_length;
             lun_d           = cmd_admin_lun;
             cdb_d           = cmd_admin_cdb;
             status_d        = zero[15:0];
             status_dw0_d    = zero[31:0];
             admin_cmd_ack   = 1'b1;             
          end
        else
          begin
             admin_cmd_ack = 1'b0;
          end

        if( ctl_sntl_iowrite_strobe & ctl_sntl_ioaddress[13:12]==2'd0 )
          begin
             sisl_reloff_par_d         =  sisl_reloff_par;
             sisl_length_par_d         =  sisl_length_par;
             case(ctl_sntl_ioaddress[11:0])
               12'h000: command_d      = ctl_sntl_iowrite_data;
               12'h004: length_d       = ctl_sntl_iowrite_data[datalen_width-1:0];
               12'h008: lun_d[31:0]    = ctl_sntl_iowrite_data;
               12'h00c: lun_d[63:32]   = ctl_sntl_iowrite_data;
               12'h010: cdb_d[127:96]  = ctl_sntl_iowrite_data;
               12'h014: cdb_d[95:64]   = ctl_sntl_iowrite_data;
               12'h018: cdb_d[63:32]   = ctl_sntl_iowrite_data;
               12'h01c: cdb_d[31:0]    = ctl_sntl_iowrite_data;
               12'h020: sisl_cid_d     = ctl_sntl_iowrite_data[18:0];
               12'h024: sisl_reloff_d  = ctl_sntl_iowrite_data[datalen_width-1:0];
               12'h028: sisl_length_d  = ctl_sntl_iowrite_data[12:0];
               12'h02c: status_d       = ctl_sntl_iowrite_data[15:0];
               12'h030: status_dw0_d   = ctl_sntl_iowrite_data;
               12'h040: sisl_clear_d   = 1'b1;
               12'h044: sisl_payload_d = 1'b1;
               12'h048: adbuf_clear_d  = 1'b1;
              default:
                 begin
                    // drop writes to invalid offset
                 end
             endcase // case (ctl_sntl_ioaddress[11:0])
             // if writing the sisl_clear or adbuf_clear reg, hold off the ack until clear is completed
             iowrite_regs_ack = ~(sisl_clear_d | adbuf_clear_d);              
          end
        else
          begin
             // delayed ack at end of sisl_clear
             iowrite_regs_ack = (sisl_clear_q & sisl_clear_reset) |  (adbuf_clear_q & adbuf_clear_reset);
          end

        // send completion when ucode set valid bit
        // wait until payload header is accepted before sending completion for ordering
        admin_cmd_cpl_valid       = status_q[15] & ~sisl_payload_q;
        admin_cmd_cpl_status      = status_q[14:0];
        admin_cmd_cpl_data        = status_dw0_q;
        admin_cmd_cpl_cmdid       = sisl_cid_q[15:0];
        admin_cmd_cpl_cmdid_par   = sisl_cid_par_q[1:0];
        admin_cmd_cpl_length      = sisl_length_q + sisl_reloff_q;  // total payload before taking fcp_length into account
        admin_cmd_cpl_length_par  = admin_cmd_cpl_length_par_in;
        if( cmd_admin_cpl_ack | cmd_admin_flush )
          begin
             command_d[15] = 1'b0;
             status_d[15]  = 1'b0;
          end

        sntl_ctl_admin_cmd_valid  = command_q[15];
        sntl_ctl_admin_cpl_valid  = status_q[15];


        admin_dma_req_valid       = sisl_cid_q[17];
        admin_dma_req_tag         = sisl_cid_q[tag_width-1:0];
        admin_dma_req_tag_par     = sisl_cid_par_q[0];
        admin_dma_req_reloff      = sisl_reloff_q;
        admin_dma_req_length      = sisl_length_q;    
        admin_dma_req_length_par  = sisl_length_par_q;        
        if( dma_admin_req_ack & sisl_cid_q[17] )
          begin
             sisl_cid_d[17] = 1'b0;
          end
        
        if( dma_admin_req_cpl  )
          begin
             sisl_cid_d[16] = 1'b1;
          end
        
     end
       

   always @*
     begin
        ioread_regs_ack = ctl_sntl_ioread_strobe & ctl_sntl_ioaddress[13:12]==2'd0;
        case(ctl_sntl_ioaddress[11:0])
          12'h000: ioread_regs_data = command_q; 
          12'h004: ioread_regs_data = {zero[31:datalen_width],length_q}; 
          12'h008: ioread_regs_data = lun_q[31:0]; 
          12'h00c: ioread_regs_data = lun_q[63:32]; 
          12'h010: ioread_regs_data = cdb_q[127:96]; 
          12'h014: ioread_regs_data = cdb_q[95:64]; 
          12'h018: ioread_regs_data = cdb_q[63:32]; 
          12'h01c: ioread_regs_data = cdb_q[31:0]; 
          12'h020: ioread_regs_data = {zero[31:19],sisl_cid_q}; 
          12'h024: ioread_regs_data = {zero[31:datalen_width],sisl_reloff_q}; 
          12'h028: ioread_regs_data = {zero[31:13],sisl_length_q}; 
          12'h02c: ioread_regs_data = {zero[31:16],status_q}; 
          12'h030: ioread_regs_data = status_dw0_q; 
          12'h040: ioread_regs_data = zero[31:0]; 
          12'h044: ioread_regs_data = zero[31:0]; 
          default:
            begin
               ioread_regs_data = ~zero[31:0];
            end
        endcase // case (ctl_sntl_ioaddress[11:0])
     end
   
   
   // ---------------------------------------------------------
   // region 1 - sislite payload buffer
   // ---------------------------------------------------------

   // read:  sislite DMA request - 16B
   // write: microcode - 4B
   // write: sislite DMA request - 16B

   localparam sislbuf_width = 128;
   localparam sislbuf_par_width = 128/8;
   localparam sislbuf_rdwidth = 128;
   localparam sislbuf_par_rdwidth = 128/8;
   localparam sislbuf_wrwidth = 32;
   localparam sislbuf_par_wrwidth = 4;
   localparam sislbuf_num_words = 4096 / (sislbuf_width/8);
   localparam sislbuf_num_wren = sislbuf_width / sislbuf_wrwidth;
   localparam sislbuf_addr_width = clogb2(sislbuf_num_words);

   reg [       sislbuf_par_width+sislbuf_width-1:0] sislbuf_mem[sislbuf_num_words-1:0];
   
   reg     [   sislbuf_par_width+sislbuf_width-1:0] sislbuf_wrdata;
   reg     [   sislbuf_par_width+sislbuf_width-1:0] sislbuf_wrdata_d,sislbuf_wrdata_q;
   reg [   sislbuf_par_rdwidth+sislbuf_rdwidth-1:0] rmw_sislbuf_wrdata;
   reg                     [  sislbuf_num_wren-1:0] sislbuf_wren;
   reg                     [  sislbuf_num_wren-1:0] rmw_sislbuf_wren_d,rmw_sislbuf_wren_q;
   reg                                              rmw_sislbuf_wren;
   reg                     [sislbuf_addr_width-1:0] sislbuf_wraddr;
   reg                     [sislbuf_addr_width-1:0] rmw_sislbuf_wraddr_d,rmw_sislbuf_wraddr_q;
   reg     [   sislbuf_par_width+sislbuf_width-1:0] sislbuf_rddata;
   reg                     [sislbuf_addr_width-1:0] sislbuf_rdaddr;
   reg                     [sislbuf_addr_width-1:0] rmw_sislbuf_rdaddr;
   reg                                              sislbuf_read;
   reg [   sislbuf_par_wrwidth+sislbuf_wrwidth-1:0] sislbuf_rddata_dw;

   // conver 8 bit parity to 64 bit parity  kch 
   wire                     [data_fc_par_width-1:0] sislbuf_rddata_fc_par;
   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(data_par_width)
      ) ipgen_sislbuf_rddata_fc_par 
       (.oddpar(1'b1),.data(sislbuf_rddata[data_par_width+data_width-1:data_width]),.datap(sislbuf_rddata_fc_par)); 

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             rmw_sislbuf_wren_q   <= 1'b0;
             rmw_sislbuf_wraddr_q <= 1'b0;
             sislbuf_wrdata_q     <= zero[sislbuf_par_wrwidth+sislbuf_wrwidth-1:0];
          end
        else
          begin
             rmw_sislbuf_wren_q   <= rmw_sislbuf_wren_d;
             rmw_sislbuf_wraddr_q <= rmw_sislbuf_wraddr_d;
             sislbuf_wrdata_q     <= sislbuf_wrdata_d;
          end
     end

   generate
      genvar                i;
      for (i = 0; i < sislbuf_num_wren; i = i+1) begin: dword_write
         always @*
           if (rmw_sislbuf_wren_q[i])
             begin
                rmw_sislbuf_wrdata[(i+1)*sislbuf_wrwidth-1:i*sislbuf_wrwidth] <= sislbuf_wrdata_q[(i+1)*sislbuf_wrwidth-1:i*sislbuf_wrwidth];
                rmw_sislbuf_wrdata[(128+(i+1)*sislbuf_par_wrwidth)-1:128+i*sislbuf_par_wrwidth] <= sislbuf_wrdata_q[(128+(i+1)*sislbuf_par_wrwidth)-1:128+i*sislbuf_par_wrwidth];
             end 
           else 
             begin
                rmw_sislbuf_wrdata[(i+1)*sislbuf_wrwidth-1:i*sislbuf_wrwidth] <= sislbuf_rddata[(i+1)*sislbuf_wrwidth-1:i*sislbuf_wrwidth];
                rmw_sislbuf_wrdata[(128+(i+1)*sislbuf_par_wrwidth)-1:128+i*sislbuf_par_wrwidth] <= sislbuf_rddata[(128+(i+1)*sislbuf_par_wrwidth)-1:128+i*sislbuf_par_wrwidth];
             end
      end
   endgenerate
   reg      rmw_sislbuf_read;

   // read modify write logic 
   always @*
     begin
        rmw_sislbuf_rdaddr    = (sislbuf_wren == 4'h0) ? sislbuf_rdaddr : sislbuf_wraddr;
        rmw_sislbuf_wren_d    = sislbuf_wren;
        rmw_sislbuf_wren      = |(rmw_sislbuf_wren_q);
        rmw_sislbuf_wraddr_d  = sislbuf_wraddr;
        sislbuf_wrdata_d      = sislbuf_wrdata;
        rmw_sislbuf_read      = sislbuf_read || (sislbuf_wren != 4'h0);
     end
   

   always @(posedge clk)  
     if( rmw_sislbuf_read ) /// added sislbuf_wren kch 
       sislbuf_rddata <= sislbuf_mem[rmw_sislbuf_rdaddr];

   always @(posedge clk)
     begin
        if (rmw_sislbuf_wren)
          sislbuf_mem[rmw_sislbuf_wraddr_q] <= rmw_sislbuf_wrdata;      
     end
   
   reg [sislbuf_addr_width:0] sislbuf_init_q, sislbuf_init_d;
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin        
             sislbuf_init_q <= zero[sislbuf_addr_width:0];           
          end
        else
          begin                        
             sislbuf_init_q <= sislbuf_init_d;           
          end
     end

   // write from host/sislite DMA request
   // write from ucode
   always @*
     begin

        if( dma_admin_valid && !sisl_cid_q[18] )
          begin
             sislbuf_wren   = ~zero[sislbuf_num_wren-1:0];
          end
        else
          begin
             sislbuf_wren   = zero[sislbuf_num_wren-1:0];
          end
        
        sislbuf_wraddr      = dma_admin_addr[11:4];
        sislbuf_wrdata      = dma_admin_data;
       
        sisl_clear_reset  = 1'b0;
        if( sisl_clear_q ) 
          begin
             // clear the 4KB buffer with one register write
             sislbuf_init_d  = sislbuf_init_q + one[sislbuf_addr_width:0];
             sislbuf_wren    = ~zero[sislbuf_num_wren-1:0];
             sislbuf_wrdata  = {~zero[sislbuf_par_width+sislbuf_width:sislbuf_width],zero[sislbuf_width-1:0]};
             sislbuf_wraddr  = sislbuf_init_q[sislbuf_addr_width-1:0];
             if( sislbuf_init_q[sislbuf_addr_width] )
               begin
                  sislbuf_wren      = zero[sislbuf_num_wren-1:0];
                  sisl_clear_reset  = 1'b1;
               end
          end
        else
          begin
             sislbuf_init_d = zero[sislbuf_addr_width:0];
          end
        
        
        if( ctl_sntl_iowrite_strobe & ctl_sntl_ioaddress[13:12] == 2'd1 )
          begin                          
             sislbuf_wren[ctl_sntl_ioaddress[3:2]]  = 1'b1;
             sislbuf_wraddr                         = ctl_sntl_ioaddress[11:4];
             sislbuf_wrdata                         = { {4{ctl_sntl_iowrite_data[35:32]}} , {4{ctl_sntl_iowrite_data[31:0]}} };  // split out parity for 32b writes;        
             iowrite_sisl_ack                       = 1'b1;
          end
        else
          begin
             iowrite_sisl_ack = 1'b0;
          end
     end
   
   
   // reads from sislbuf
   (* mark_debug = "false" *)
   reg [3:0] s0_sisl_state_q;
   reg [3:0] s0_sisl_state_d;
   localparam ST_IDLE = 4'h1;
   localparam ST_HDR  = 4'h2;
   localparam ST_PAY  = 4'h3;

   reg [sislbuf_addr_width-1:0] s0_sisl_addr_q, s0_sisl_addr_d;
   reg                   [12:0] s0_sisl_bytes_q, s0_sisl_bytes_d;
   reg                          s0_sisl_last;
   reg                   [12:0] s0_sisl_length_q, s0_sisl_length_d;
   
   reg                          s1_sisl_valid_q;
   reg                          s1_sisl_valid_d;
   reg                          s1_sisl_last_q;
   reg                          s1_sisl_last_d;
   reg                          s1_sisl_ready;
   
   reg         [data_width-1:0] s2_sisl_data_q, s2_sisl_data_d;
   reg  [data_fc_par_width-1:0] s2_sisl_data_par_q, s2_sisl_data_par_d;
   reg                          s2_sisl_valid_q;
   reg                          s2_sisl_valid_d;
   reg                          s2_sisl_last_q;
   reg                          s2_sisl_last_d;
   reg                          s2_sisl_ready;

   (* mark_debug = "false" *)
   reg                   [11:2] sisl_iord_addr_q, sisl_iord_addr_d;
   (* mark_debug = "false" *)
   reg                          sisl_iord_q, sisl_iord_d;
   
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin        
             s0_sisl_state_q    <= ST_IDLE;
             s0_sisl_addr_q     <= zero[sislbuf_addr_width-1:0];
             s0_sisl_bytes_q    <= zero[12:0];
             s0_sisl_length_q   <= zero[12:0];
             s1_sisl_valid_q    <= 1'b0;
             s1_sisl_last_q     <= 1'b0;  
             s2_sisl_data_q     <= zero[data_width-1:0];
             s2_sisl_data_par_q <= one[data_par_width-1:0];
             s2_sisl_valid_q    <= 1'b0;
             s2_sisl_last_q     <= 1'b0;
             sisl_iord_addr_q   <= 10'b0;
             sisl_iord_q        <= 1'b0;
          end
        else
          begin                        
             s0_sisl_state_q    <= s0_sisl_state_d;
             s0_sisl_addr_q     <= s0_sisl_addr_d;
             s0_sisl_bytes_q    <= s0_sisl_bytes_d;
             s0_sisl_length_q   <= s0_sisl_length_d;
             s1_sisl_valid_q    <= s1_sisl_valid_d;
             s1_sisl_last_q     <= s1_sisl_last_d;             
             s2_sisl_data_q     <= s2_sisl_data_d;
             s2_sisl_data_par_q <= s2_sisl_data_par_d;
             s2_sisl_valid_q    <= s2_sisl_valid_d;
             s2_sisl_last_q     <= s2_sisl_last_d;
             sisl_iord_addr_q   <= sisl_iord_addr_d;
             sisl_iord_q        <= sisl_iord_d;
          end
     end
   
   always @*
     begin
        // handle reads from microcontroller
        ioread_sisl_ack_d  = 1'b0;
        sisl_iord_d        = sisl_iord_q;
        sisl_iord_addr_d   = sisl_iord_addr_q;
        if( ctl_sntl_ioread_strobe & ctl_sntl_ioaddress[13:12] == 2'd1 )
          begin
             sisl_iord_d = 1'b1;
             sisl_iord_addr_d = ctl_sntl_ioaddress[11:2];             
          end                 
        case(sisl_iord_addr_q[3:2])
          2'h0:    sislbuf_rddata_dw  = {sislbuf_rddata[131:128],sislbuf_rddata[31:0]};
          2'h1:    sislbuf_rddata_dw  = {sislbuf_rddata[135:132],sislbuf_rddata[63:32]};
          2'h2:    sislbuf_rddata_dw  = {sislbuf_rddata[139:136],sislbuf_rddata[95:64]};
          default: sislbuf_rddata_dw  = {sislbuf_rddata[143:140],sislbuf_rddata[127:96]};
        endcase // case (ctl_sntl_ioaddress[3:2])
        ioread_sisl_data = sislbuf_rddata_dw;

        // pipeline for reads for sisl payload
        s0_sisl_state_d        = s0_sisl_state_q;

        admin_rsp_req_valid    = 1'b0;
        admin_rsp_req_tag      = sisl_cid_q[tag_width-1:0];
        admin_rsp_req_tag_par  = sisl_cid_par_q[0];
        admin_rsp_req_reloff   = sisl_reloff_q;

        // truncate on overrun
        if( sisl_length_q < (length_q - sisl_reloff_q) )
          s0_sisl_length_d  = sisl_length_q;
        else
          s0_sisl_length_d  = length_q - sisl_reloff_q;
        
        admin_rsp_req_length  = s0_sisl_length_q;
          
        sislbuf_read          = 1'b0;        
        sislbuf_rdaddr        = s0_sisl_addr_q;
        
        s0_sisl_addr_d        = s0_sisl_addr_q;
        s0_sisl_bytes_d       = s0_sisl_bytes_q;

        s0_sisl_last          = (s0_sisl_length_q - s0_sisl_bytes_q) <= 13'd16;
        
        sisl_payload_reset    = 1'b0;
        
        case( s0_sisl_state_q )
          ST_IDLE:
            begin
               // wait until ucode signals that payload is ready
               // then send header to response handler
               if( sisl_payload_q )
                 begin
                    s0_sisl_state_d     = ST_HDR;
                    s0_sisl_addr_d      = sisl_reloff_q[11:4];
                    s0_sisl_bytes_d     = zero[12:0];                    
                 end   
               else if( sisl_iord_q )
                 begin
                    sislbuf_read       = 1'b1;
                    sislbuf_rdaddr     = sisl_iord_addr_q[11:4];
                    ioread_sisl_ack_d  = 1'b1;
                    sisl_iord_d        = 1'b0;
                 end               
            end
          
          ST_HDR:
            begin
               admin_rsp_req_valid = 1'b1;
               if( rsp_admin_req_ack )
                 begin
                    sislbuf_read = 1'b1;
                    if( s0_sisl_last )
                      begin
                         sisl_payload_reset  = 1'b1;
                         s0_sisl_state_d     = ST_IDLE;
                      end
                    else
                      begin                      
                         s0_sisl_state_d = ST_PAY;
                      end
                    s0_sisl_addr_d   = s0_sisl_addr_q + one[sislbuf_addr_width-1:0];
                    s0_sisl_bytes_d  = s0_sisl_bytes_q + 13'd16;                 
                 end
            end
          
          ST_PAY:
            begin
               if( s1_sisl_ready )
                 begin
                    sislbuf_read = 1'b1;
                    if( s0_sisl_last )
                      begin
                         sisl_payload_reset  = 1'b1;
                         s0_sisl_state_d     = ST_IDLE;
                      end	
                    else
                      begin                      
                         s0_sisl_state_d = ST_PAY;
                      end
                    s0_sisl_addr_d   = s0_sisl_addr_q + one[sislbuf_addr_width-1:0];
                    s0_sisl_bytes_d  = s0_sisl_bytes_q + 13'd16;                
                 end               
            end

          default:
            begin
               s0_sisl_state_d = ST_IDLE;
            end
        endcase // case ( s0_sisl_state_q )
           
     end

   always @*
     begin
        s1_sisl_valid_d  = s1_sisl_valid_q;
        s1_sisl_last_d   = s1_sisl_last_q;

        s1_sisl_ready    = ~s1_sisl_valid_q | s2_sisl_ready;
        if( s1_sisl_ready )
          begin
             s1_sisl_valid_d = sislbuf_read & sisl_payload_q;
             s1_sisl_last_d  = s0_sisl_last;
          end
     end

   always @*
     begin
        s2_sisl_ready = ~s2_sisl_valid_q | rsp_admin_ready;
                        
        if( s2_sisl_ready )
          begin
             s2_sisl_valid_d     = s1_sisl_valid_q;
             s2_sisl_data_d      = sislbuf_rddata[data_width-1:0];
             s2_sisl_data_par_d  = sislbuf_rddata_fc_par;
             s2_sisl_last_d      = s1_sisl_last_q;
          end
        else
          begin
             s2_sisl_valid_d     = s2_sisl_valid_q;
             s2_sisl_data_d      = s2_sisl_data_q;
             s2_sisl_data_par_d  = s2_sisl_data_par_q;
             s2_sisl_last_d      = s2_sisl_last_q;
          end
        
        admin_rsp_valid     = s2_sisl_valid_q;
        admin_rsp_data      = s2_sisl_data_q;
        admin_rsp_data_par  = s2_sisl_data_par_q;
        admin_rsp_last      = s2_sisl_last_q;  
     end
  
   // ---------------------------------------------------------
   // region 2 - adq payload buffer
   // ---------------------------------------------------------

   // read:  microcode 4B
   // write: microcode 4B
   // read:  NVMe DMA - 16B
   // write: NVMe DMA - 16B

   localparam adbuf_width = 128;
   localparam adbuf_par_width = 128/8;
   localparam adbuf_rdwidth = 32;
   localparam adbuf_wrwidth = 32;
   localparam adbuf_par_wrwidth = 32/8;
   localparam adbuf_par_rdwidth = 32/8;
   localparam adbuf_num_words = 4096 / (adbuf_width/8);
   localparam adbuf_num_wren = (adbuf_width/adbuf_rdwidth);
   localparam adbuf_addr_width = clogb2(adbuf_num_words);


   reg [     adbuf_par_width+adbuf_width-1:0] adbuf_mem[adbuf_num_words-1:0];   
   reg [     adbuf_par_width+adbuf_width-1:0] adbuf_wrdata;  // added par_width kch 
   reg [     adbuf_par_width+adbuf_width-1:0] adbuf_wrdata_d,adbuf_wrdata_q;
   reg [     adbuf_par_width+adbuf_width-1:0] rmw_adbuf_wrdata;
   reg              [     adbuf_num_wren-1:0] adbuf_wren;
   reg              [     adbuf_num_wren-1:0] rmw_adbuf_wren_d,rmw_adbuf_wren_q;
   reg                                        rmw_adbuf_wren;
   reg            [     adbuf_addr_width-1:0] adbuf_wraddr;
   reg                 [adbuf_addr_width-1:0] rmw_adbuf_wraddr_d,rmw_adbuf_wraddr_q;
   reg [     adbuf_par_width+adbuf_width-1:0] adbuf_rddata;  // added par_width kch 
   reg            [     adbuf_addr_width-1:0] adbuf_rdaddr;   
   reg                 [adbuf_addr_width-1:0] rmw_adbuf_rdaddr;
   reg [ adbuf_par_rdwidth+adbuf_rdwidth-1:0] adbuf_rddata_dw;    

   wire [    adbuf_par_width+adbuf_width-1:0] adbuf_pcie_wrdata;
   wire                                       adbuf_pcie_wren;
   wire           [     adbuf_addr_width-1:0] adbuf_pcie_wraddr;
  
   wire           [     adbuf_addr_width-1:0] adbuf_pcie_rdaddr;
   wire                                       adbuf_pcie_rdval;

   //   reg    [adbuf_par_wrwidth+adbuf_wrwidth-1:0] adbuf_rddata_dw;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             rmw_adbuf_wren_q   <= 1'b0;
             rmw_adbuf_wraddr_q <= 1'b0;
             adbuf_wrdata_q     <= {~zero[adbuf_par_wrwidth+adbuf_wrwidth:adbuf_wrwidth],zero[adbuf_wrwidth-1:0]};
          end
        else
          begin
             rmw_adbuf_wren_q   <= rmw_adbuf_wren_d;
             rmw_adbuf_wraddr_q <= rmw_adbuf_wraddr_d;
             adbuf_wrdata_q     <= adbuf_wrdata_d;
          end
     end
   

   generate
      genvar                adq;
      for (adq = 0; adq < adbuf_num_wren; adq = adq+1) begin: adq_dword_write
         always @*
           if (rmw_adbuf_wren_q[adq])
             begin
                rmw_adbuf_wrdata[(adq+1)*adbuf_wrwidth-1:adq*adbuf_wrwidth] <= adbuf_wrdata_q[(adq+1)*adbuf_wrwidth-1:adq*adbuf_wrwidth];
                rmw_adbuf_wrdata[(128+(adq+1)*adbuf_par_wrwidth)-1:128+adq*adbuf_par_wrwidth] <= adbuf_wrdata_q[(128+(adq+1)*adbuf_par_wrwidth)-1:128+adq*adbuf_par_wrwidth];  // kch 
             end
           else 
             begin
                rmw_adbuf_wrdata[(adq+1)*adbuf_wrwidth-1:adq*adbuf_wrwidth] <= adbuf_rddata[(adq+1)*adbuf_wrwidth-1:adq*adbuf_wrwidth];
                rmw_adbuf_wrdata[(128+(adq+1)*adbuf_par_wrwidth)-1:128+adq*adbuf_par_wrwidth] <= adbuf_rddata[(128+(adq+1)*adbuf_par_wrwidth)-1:128+adq*adbuf_par_wrwidth];  // kch 
             end
      end
   endgenerate
   
   // read modify write logic 
   always @*
     begin
        rmw_adbuf_rdaddr    = (adbuf_wren == 4'h0) ? adbuf_rdaddr : adbuf_wraddr;
        rmw_adbuf_wren_d    = adbuf_wren;
        rmw_adbuf_wren      = |(rmw_adbuf_wren_q);
        rmw_adbuf_wraddr_d  = adbuf_wraddr;
        adbuf_wrdata_d      = adbuf_wrdata;
     end


   reg [3:2] ioread_addr_q, ioread_addr_d;
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin        
             ioread_adq_ack_q  <= 1'b0;
             ioread_sisl_ack_q <= 1'b0;
             ioread_addr_q     <= 2'd0;             
          end
        else
          begin                        
             ioread_adq_ack_q  <= ioread_adq_ack_d;
             ioread_sisl_ack_q <= ioread_sisl_ack_d;
             ioread_addr_q     <= ioread_addr_d;
          end
     end

   always @(posedge clk)   
     adbuf_rddata <= adbuf_mem[adbuf_rdaddr];
   
   always @(posedge clk)
     if (rmw_adbuf_wren)
       adbuf_mem[rmw_adbuf_wraddr_q] <= rmw_adbuf_wrdata;  

   reg [adbuf_addr_width:0] adbuf_init_q, adbuf_init_d;
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin        
             adbuf_init_q <= zero[adbuf_addr_width:0];           
          end
        else
          begin                        
             adbuf_init_q <= adbuf_init_d;           
          end
     end


   // read/write from microcontroller
   always @*
     begin

        if( dma_admin_valid && sisl_cid_q[18] )
          begin
             adbuf_wren   = ~zero[adbuf_num_wren-1:0];
          end
        else
          begin
             adbuf_wren   = zero[adbuf_num_wren-1:0];
          end
        
        adbuf_wraddr      = dma_admin_addr[11:4];
        adbuf_wrdata      = dma_admin_data;
       
        adbuf_clear_reset  = 1'b0;
        if( adbuf_clear_q ) 
          begin
             // clear the 4KB buffer with one register write
             adbuf_init_d  = adbuf_init_q + one[adbuf_addr_width:0];
             adbuf_wren    = ~zero[adbuf_num_wren-1:0];
             adbuf_wrdata  = {~zero[adbuf_par_width+adbuf_width:adbuf_width],zero[adbuf_width-1:0]};
             adbuf_wraddr  = adbuf_init_q[adbuf_addr_width-1:0];
             if( adbuf_init_q[adbuf_addr_width] )
               begin
                  adbuf_wren      = zero[adbuf_num_wren-1:0];
                  adbuf_clear_reset  = 1'b1;
               end
          end
        else
          begin
             adbuf_init_d = zero[adbuf_addr_width:0];
          end
        
        
        adbuf_rdaddr      = ctl_sntl_ioaddress[11:4];
        ioread_adq_ack_d  = ctl_sntl_ioread_strobe & ctl_sntl_ioaddress[13:12] == 2'd2;
        ioread_addr_d     = ctl_sntl_ioaddress[3:2];
        case(ioread_addr_q)
          2'h0:    adbuf_rddata_dw  = {adbuf_rddata[131:128],adbuf_rddata[31:0]};
          2'h1:    adbuf_rddata_dw  = {adbuf_rddata[135:132],adbuf_rddata[63:32]};
          2'h2:    adbuf_rddata_dw  = {adbuf_rddata[139:136],adbuf_rddata[95:64]};
          default: adbuf_rddata_dw  = {adbuf_rddata[143:140],adbuf_rddata[127:96]};
        endcase // case (ctl_sntl_ioaddress[3:2])
        ioread_adq_data = adbuf_rddata_dw;

        if( ctl_sntl_iowrite_strobe & ctl_sntl_ioaddress[13:12] == 2'd2 )
          begin
             iowrite_adq_ack                      = 1'b1;
        
             adbuf_wren        = zero[adbuf_num_wren-1:0];
             adbuf_wraddr      = ctl_sntl_ioaddress[11:4];
             adbuf_wrdata      = { {4{ctl_sntl_iowrite_data[35:32]}} , {4{ctl_sntl_iowrite_data[31:0]}} };  // split out parity for 32b writes
 
             adbuf_wren[ctl_sntl_ioaddress[3:2]]  = 1'b1;
          end
        else
          begin
             iowrite_adq_ack = 1'b0;
          end

        if( adbuf_pcie_wren )
          begin
             adbuf_wren   = ~zero[adbuf_num_wren-1:0];
             adbuf_wraddr = adbuf_pcie_wraddr;
             adbuf_wrdata = adbuf_pcie_wrdata;
          end
        
        if( adbuf_pcie_rdval )
          begin
             adbuf_rdaddr = adbuf_pcie_rdaddr;
          end
     end

   
   nvme_xxq_dma#
     (.addr_width(addr_width),
   
      .sq_num_queues(1),
      .sq_ptr_width(1),
      .sq_addr_width(adbuf_addr_width),
      .sq_rdwidth(adbuf_width),
       
      .cq_num_queues(1),
      .cq_ptr_width(1),
      .cq_addr_width(adbuf_addr_width),
      .cq_wrwidth(adbuf_width)
        
      ) dma
       (  
          .reset                         (reset),
          .clk                           (clk),                
          .q_reset                       (1'b0),
          .q_init_done                   (),

          .cq_wren                       (adbuf_pcie_wren),
          .cq_wraddr                     (adbuf_pcie_wraddr),
          .cq_wrdata                     (adbuf_pcie_wrdata),
          .cq_id                         (),

          .sq_rdaddr                     (adbuf_pcie_rdaddr),
          .sq_rdval                      (adbuf_pcie_rdval),
          .sq_id                         (),
          .sq_rddata                     (adbuf_rddata),

          .pcie_xxq_valid                (pcie_sntl_adbuf_valid),
          .pcie_xxq_data                 (pcie_sntl_adbuf_data),
          .pcie_xxq_first                (pcie_sntl_adbuf_first),
          .pcie_xxq_last                 (pcie_sntl_adbuf_last),
          .pcie_xxq_discard              (pcie_sntl_adbuf_discard),        
          .xxq_pcie_pause                (sntl_pcie_adbuf_pause),
          
          .xxq_pcie_cc_data              (sntl_pcie_adbuf_cc_data),
          .xxq_pcie_cc_first             (sntl_pcie_adbuf_cc_first),
          .xxq_pcie_cc_last              (sntl_pcie_adbuf_cc_last),
          .xxq_pcie_cc_discard           (sntl_pcie_adbuf_cc_discard),
          .xxq_pcie_cc_valid             (sntl_pcie_adbuf_cc_valid),   
          .pcie_xxq_cc_ready             (pcie_sntl_adbuf_cc_ready),
          
          .req_dbg_event                 (),
          .xxq_dma_perror                (),
          .xxq_perror_inj                (2'b0),
          .xxq_perror_ack                ());


   // ---------------------------------------------------------
   // region 3 - namespace ids and blocksize
   // ---------------------------------------------------------

   
   
   reg [31:0] nsid_table_q, nsid_table_d;  // index=lunid  entry=NSID[31:0]   
   reg  [7:0] lbads_table_q, lbads_table_d; // index=lunid entry=lbads[7:0]
   reg [63:0] numlba_table_q, numlba_table_d; // index=lunid entry=number of 4K blocks
   reg        lunstatus_table_q, lunstatus_table_d; // index=lunid entry=ACA state
   
   reg [31:0] lunlu_nsid_q, lunlu_nsid_d;
   reg  [7:0] lunlu_lbads_q, lunlu_lbads_d;
   reg [63:0] lunlu_numlba_q, lunlu_numlba_d;
   reg        lunlu_status_q, lunlu_status_d;	
   
   
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin                    
             nsid_table_q      <= zero[31:0];
             lbads_table_q     <= zero[7:0];
             numlba_table_q    <= zero[63:0];
             lunstatus_table_q <= 1'b0;
             
             lunlu_nsid_q      <= zero[31:0];
             lunlu_lbads_q     <= zero[7:0];
             lunlu_numlba_q    <= zero[63:0];
             lunlu_status_q    <= 1'b0;
         end
        else
          begin                       
             nsid_table_q      <= nsid_table_d;
             lbads_table_q     <= lbads_table_d;
             numlba_table_q    <= numlba_table_d;
             lunstatus_table_q <= lunstatus_table_d;
             
             lunlu_nsid_q      <= lunlu_nsid_d;
             lunlu_lbads_q     <= lunlu_lbads_d;
             lunlu_numlba_q    <= lunlu_numlba_d;
             lunlu_status_q    <= lunlu_status_d;
          end
     end

    
   
   always @*
     begin
        nsid_table_d       = nsid_table_q;
        lbads_table_d      = lbads_table_q;
        numlba_table_d     = numlba_table_q;
        lunstatus_table_d  = lunstatus_table_q;
        

        if( ctl_sntl_iowrite_strobe & ctl_sntl_ioaddress[13:12]==2'd3 )
          begin
             // namespace config tables - only 1 namespace supported currently
             case(ctl_sntl_ioaddress[11:0])
               12'h000: nsid_table_d           = ctl_sntl_iowrite_data[31:0];             
               12'h800: lbads_table_d          = ctl_sntl_iowrite_data[7:0];
               12'h804: lunstatus_table_d      = ctl_sntl_iowrite_data[0];
               12'hC00: numlba_table_d[31:0]   = ctl_sntl_iowrite_data[31:0];
               12'hC04: numlba_table_d[63:32]  = ctl_sntl_iowrite_data[31:0];
              default:
                 begin
                    // drop writes to invalid offset
                 end
             endcase // case (ctl_sntl_ioaddress[11:0])            
             iowrite_other_ack = 1'b1;              
          end
        else
          begin
             iowrite_other_ack = 1'b0;     
          end

        if( ctl_sntl_ioread_strobe & ctl_sntl_ioaddress[13:12]==2'd3 )
          begin
             case(ctl_sntl_ioaddress[11:0])
               12'h000:  ioread_other_data = nsid_table_q;              
               12'h800:  ioread_other_data = lbads_table_q;
               12'h804:  ioread_other_data = lunstatus_table_q;
               12'hC00:  ioread_other_data = numlba_table_q[31:0];             
               12'hC0C:  ioread_other_data = numlba_table_q[63:32];             
               default:
                 begin
                    ioread_other_data = 32'hFFFFFFFF;
                 end
             endcase // case (ctl_sntl_ioaddress[11:0])           
             ioread_other_ack = 1'b1;              
          end
        else
          begin
             ioread_other_data = 32'hFFFFFFFF;
             ioread_other_ack = 1'b0;     
          end

        if( cmd_admin_lunlu_setaca && cmd_admin_lunlu_setaca_idx==zero[lunidx_width-1:0] )
          begin
             lunstatus_table_d = 1'b1;
          end
        
        if( cmd_admin_lunlu_clraca && cmd_admin_lunlu_clraca_idx==zero[lunidx_width-1:0] )
          begin
             lunstatus_table_d = 1'b0;
          end

     end // always @ *

   always @*
     begin
        lunlu_nsid_d    = lunlu_nsid_q;
        lunlu_lbads_d   = lunlu_lbads_q;
        lunlu_numlba_d  = lunlu_numlba_q;
        lunlu_status_d  = lunlu_status_q;
              
        // read nsid table for I/O LUNID->nsid mapping
        // only entry 0 is implemented
        // return nsid = 0xFFFFFFFF for other entries
        if( cmd_admin_lunlu_valid && cmd_admin_lunlu_idx == zero[lunidx_width-1:0])
          begin
             lunlu_nsid_d    = nsid_table_q;
             lunlu_lbads_d   = lbads_table_q;
             lunlu_numlba_d  = numlba_table_q;
             lunlu_status_d  = lunstatus_table_q;
          end
        else
          begin
             lunlu_nsid_d    = ~zero[31:0];
             lunlu_lbads_d   = zero[7:0];   
             lunlu_numlba_d  = zero[63:0];
             lunlu_status_d  = 1'b0;
          end

        admin_cmd_lunlu_nsid    = lunlu_nsid_q;
        admin_cmd_lunlu_lbads   = lunlu_lbads_q;
        admin_cmd_lunlu_numlba  = lunlu_numlba_q;
        admin_cmd_lunlu_status  = lunlu_status_q;
     end
  
endmodule 
