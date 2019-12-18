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
//  File : nvme_sntl_dma.v
//  *************************************************************************
//  *************************************************************************
//  Description : FlashGT+ - SCSI to NVMe Layer payload dma 
//                
//  *************************************************************************

module nvme_sntl_dma#
  (// afu/psl   interface parameters
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
   parameter data_par_width  = ((data_width + 7) / 8) + 1,
   parameter status_width    = 8, // event status
   parameter wdata_max_req   = 4096,
   parameter wdatalen_width  = $clog2(wdata_max_req)+1,   
   parameter addr_width = 48,
   parameter cid_width = 16,
   parameter cid_par_width = 2
      
    )
   (
   
    input                           reset,
    input                           clk, 

   
    // ----------------------------------------------------
    // sislite write (DMA read to host)
    // ----------------------------------------------------

    (* mark_debug = "false" *)
    output reg                      dma_wdata_req_valid,
    (* mark_debug = "false" *)
    output reg      [tag_width-1:0] dma_wdata_req_tag, // afu req tag  
    (* mark_debug = "false" *)
    output reg                      dma_wdata_req_tag_par,
    (* mark_debug = "false" *)
    output reg  [datalen_width-1:0] dma_wdata_req_reloff, // offset from start address of this command
    (* mark_debug = "false" *)
    output reg [wdatalen_width-1:0] dma_wdata_req_length, // number of bytes to request, max 512B
    (* mark_debug = "false" *)
    output reg                      dma_wdata_req_length_par,
    (* mark_debug = "false" *)
    input                           wdata_dma_req_pause, // backpressure
   

    // ----------------------------------------------------
    // sislite write data response from host
    // ----------------------------------------------------
   
    (* mark_debug = "false" *)
    input                           wdata_dma_cpl_valid,
    (* mark_debug = "false" *)
    input           [tag_width-1:0] wdata_dma_cpl_tag,
    (* mark_debug = "false" *)
    input                           wdata_dma_cpl_tag_par,
    (* mark_debug = "false" *)
    input       [datalen_width-1:0] wdata_dma_cpl_reloff,
    (* mark_debug = "false" *)
    input                     [9:0] wdata_dma_cpl_length, // number of bytes in buffer 128B max
    input                   [129:0] wdata_dma_cpl_data,
    (* mark_debug = "false" *)
    input                           wdata_dma_cpl_first, // first cycle of this completion
    (* mark_debug = "false" *)
    input                           wdata_dma_cpl_last, // last cycle of this completion
    (* mark_debug = "false" *)
    input                           wdata_dma_cpl_error, // DMA error - asserted for all cycle of this completion
    (* mark_debug = "false" *)
    input                           wdata_dma_cpl_end, // this completion is the last for this tag

    (* mark_debug = "false" *)
    output reg                      dma_wdata_cpl_ready,

    //-------------------------------------------------------
    // sislite read data 
    //-------------------------------------------------------
    (* mark_debug = "false" *)
    output reg                      dma_rsp_valid,
    (* mark_debug = "false" *)
    input                           rsp_dma_pause,
    output reg  [datalen_width-1:0] dma_rsp_reloff,
    output reg [wdatalen_width-1:0] dma_rsp_length,
    (* mark_debug = "false" *)
    output reg      [tag_width-1:0] dma_rsp_tag,
    output reg                      dma_rsp_tag_par,
    output reg              [127:0] dma_rsp_data,
    (* mark_debug = "false" *)
    output                    [1:0] dma_rsp_data_par,
    (* mark_debug = "false" *)
    output reg                      dma_rsp_first,
    (* mark_debug = "false" *)
    output reg                      dma_rsp_last,

    //-------------------------------------------------------
    // admin command internal payload
    //-------------------------------------------------------
    output reg                      dma_admin_valid,
    output reg     [addr_width-1:0] dma_admin_addr,
    output reg              [144:0] dma_admin_data,
   
    // ----------------------------------------------------
    // admin DMA read request
    // ----------------------------------------------------

    input                           admin_dma_req_valid,
    input           [tag_width-1:0] admin_dma_req_tag, // afu req tag
    input                           admin_dma_req_tag_par,
    input       [datalen_width-1:0] admin_dma_req_reloff, // offset from start address of this command
    input      [wdatalen_width-1:0] admin_dma_req_length, // number of bytes to request, max 512B
    input                           admin_dma_req_length_par,
    output reg                      dma_admin_req_ack, 
    output reg                      dma_admin_req_cpl, 
   
    //-------------------------------------------------------
    // command tracking
    //-------------------------------------------------------

    // read/write request
    (* mark_debug = "false" *)
    output reg                      dma_cmd_valid,
    (* mark_debug = "false" *)
    output reg      [cid_width-1:0] dma_cmd_cid,
    (* mark_debug = "false" *)
    output reg  [cid_par_width-1:0] dma_cmd_cid_par,
    (* mark_debug = "false" *)
    output reg                      dma_cmd_rnw,
    (* mark_debug = "false" *)
    output reg  [datalen_width-1:0] dma_cmd_reloff,
    (* mark_debug = "false" *)
    output reg [wdatalen_width-1:0] dma_cmd_length, // length of transfer in bytes
    (* mark_debug = "false" *)
    output reg                      dma_cmd_length_par, 
    (* mark_debug = "false" *)
    input                           cmd_dma_ready, 
   
    (* mark_debug = "false" *)
    input                           cmd_dma_valid,
    (* mark_debug = "false" *)
    input                           cmd_dma_error, // 4 cycles after dma_cmd_valid & cmd_dma_ready
   
   

    //-------------------------------------------------------
    // track error status from on sisl write payload
    //-------------------------------------------------------
    output reg                      dma_cmd_wdata_valid,
    output reg      [cid_width-1:0] dma_cmd_wdata_cid,
    output reg  [cid_par_width-1:0] dma_cmd_wdata_cid_par,
    output reg                      dma_cmd_wdata_error,
    input                           cmd_dma_wdata_ready,
   
    //-------------------------------------------------------
    // DMA requests to SNTL (read/write payload)
    //-------------------------------------------------------
   
    (* mark_debug = "false" *)
    input                           pcie_sntl_valid,
    input                   [144:0] pcie_sntl_data,
    (* mark_debug = "false" *)
    input                           pcie_sntl_first, 
    (* mark_debug = "false" *)
    input                           pcie_sntl_last, 
    (* mark_debug = "false" *)
    input                           pcie_sntl_discard, 
    (* mark_debug = "false" *)
    output reg                      sntl_pcie_pause, 
    (* mark_debug = "false" *)
    output                          sntl_pcie_ready, 

    //-------------------------------------------------------
    // DMA response from SNTL
    //-------------------------------------------------------        
   
    output reg              [144:0] sntl_pcie_cc_data,
    (* mark_debug = "false" *)
    output reg                      sntl_pcie_cc_first,
    (* mark_debug = "false" *)
    output reg                      sntl_pcie_cc_last,
    (* mark_debug = "false" *)
    output reg                      sntl_pcie_cc_discard,
    (* mark_debug = "false" *)
    output                          sntl_pcie_cc_valid,
    (* mark_debug = "false" *)
    input                           pcie_sntl_cc_ready,

    //-------------------------------------------------------
    // debug and counters 
    //-------------------------------------------------------        
    input                     [7:0] regs_dma_errcpl,
    output reg               [15:0] dma_perf_events,
    output                    [7:0] dma_perror_ind,
    // ----------------------------------------------------------
    // parity error inject 
    // ----------------------------------------------------------
    input                           regs_sntl_pe_errinj_valid,
    input                    [15:0] regs_xxx_pe_errinj_decode, 
    input                           regs_wdata_pe_errinj_1cycle_valid 
   
    );


`include "nvme_func.svh"

   // Parity error srlat 

   wire                       [7:0] s1_perror;
   wire                       [7:0] dma_perror_int;

   // set/reset/ latch for parity errors
   nvme_srlat#
     (.width(8))  idma_sr   
       (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(dma_perror_int));

   assign dma_perror_ind = dma_perror_int;

  
   //-------------------------------------------------------
   // PCIe requests and completions
   //-------------------------------------------------------

   // Request header:
   //    { addr_type[1:0], 
   //      attr[2:0], 
   //      tc[2:0], 
   //      dcount[10:0],              - number of 32b words to return.  expect this to be 64B but allow up to 512B?
   //      last_be[3:0],              - expect 0xF but accept any non-zero
   //      first_be[3:0],             - expect 0xF but accept any non-zero
   //      req_other, req_rd, req_wr, - expect either rd or wr
   //      pcie_tag[7:0], 
   //      addr_region[3:0],          - expect ENUM_ADDR_SISL or ENUM_ADDR_INTN
   //      addr[addr_width-1:0] }     - offset within queue.  return zeros if out of range?
   //
   // Completion header:
   // { addr_type[1:0],     // from original request
   //   attr[2:0],          // from original request
   //    tc[2:0],           // from original request
   //    byte_count[12:0],  // remaining bytes to be transferred including this packet
   //    cpl_status[2:0],   // 0x0 - success; 0x1 - unsupported request; 0x2 - completer abort
   //    cpl_dwords[10:0],  // number of dwords in the completion packet
   //    pcie_tag[7:0],     // from original request
   //    lower_addr[6:0] }  // least significant 7b of byte address of this packet
   
   localparam req_hdr_width =  2 + 3 + 3 + 11 + 4 + 4 + 3 + 8 + 4 + addr_width; 
   localparam req_hdr_par_width =  (req_hdr_width+7)/8;
   localparam cpl_hdr_width = 2 + 3 + 3 + 13 + 3 + 11 + 8 + 7;
   localparam cpl_hdr_par_width = (cpl_hdr_width + 7)/8;

   wire                                      s0_valid;
   reg                                       s0_first;
   reg                                       s0_last;
   reg                                       s0_discard;
   reg       [data_par_width+data_width-1:0] s0_data; 
   reg                                       s0_ready;
   
   reg [req_hdr_par_width+req_hdr_width-1:0] s0_req_hdr_q, s0_req_hdr_d;  
   reg                                       s0_chkdma_q, s0_chkdma_d;
   reg                                 [1:0] s0_error_q, s0_error_d;
   reg                                       s0_discard_q, s0_discard_d;

   reg                                       s1_valid_q, s1_valid_d;
   reg                                       s1_first_q, s1_first_d;
   reg                                       s1_last_q, s1_last_d;
   reg                                       s1_discard_q, s1_discard_d;
   reg                                 [1:0] s1_error_q, s1_error_d;
   reg                                       s1_rnw_q, s1_rnw_d;
   reg       [data_par_width+data_width-1:0] s1_data_q, s1_data_d; 
   reg                                       s1_chkdma_q, s1_chkdma_d;

   reg                                       s2_valid_q, s2_valid_d;
   reg                                       s2_first_q, s2_first_d;
   reg                                       s2_last_q, s2_last_d;
   reg                                       s2_discard_q, s2_discard_d;
   reg                                 [1:0] s2_error_q, s2_error_d;
   reg                                       s2_rnw_q, s2_rnw_d;
   reg       [data_par_width+data_width-1:0] s2_data_q, s2_data_d; 
   reg                                       s2_chkdma_q, s2_chkdma_d;

   reg                                       s3_valid_q, s3_valid_d;
   reg                                       s3_first_q, s3_first_d;
   reg                                       s3_last_q, s3_last_d;
   reg                                       s3_discard_q, s3_discard_d;
   reg                                 [1:0] s3_error_q, s3_error_d;
   reg                                       s3_rnw_q, s3_rnw_d;
   reg       [data_par_width+data_width-1:0] s3_data_q, s3_data_d;  
   reg                                       s3_chkdma_q, s3_chkdma_d;
   
   reg                                       s4_valid_q, s4_valid_d;
   reg                                       s4_first_q, s4_first_d;
   reg                                       s4_last_q, s4_last_d;
   reg                                       s4_discard_q, s4_discard_d;
   reg                                 [1:0] s4_error_q, s4_error_d;
   reg                                       s4_rnw_q, s4_rnw_d;
   reg       [data_par_width+data_width-1:0] s4_data_q, s4_data_d;
   reg                                       s4_chkdma_q, s4_chkdma_d;
   
   (* mark_debug = "false" *)
   reg                                       s5_valid_q;
   reg                                       s5_valid_d;
   (* mark_debug = "false" *)
   reg                                       s5_first_q;
   reg                                       s5_first_d;
   (* mark_debug = "false" *)
   reg                                       s5_last_q;
   reg                                       s5_last_d;
   (* mark_debug = "false" *)
   reg                                       s5_discard_q;
   reg                                       s5_discard_d;
   (* mark_debug = "false" *)
   reg                                 [1:0] s5_error_q;
   reg                                 [1:0] s5_error_d;
   (* mark_debug = "false" *)
   reg                                       s5_rnw_q;
   reg                                       s5_rnw_d;
   reg       [data_par_width+data_width-1:0] s5_data_q, s5_data_d;
   (* mark_debug = "false" *)
   reg                                       s5_cmd_error;
   reg                                       s5_chkdma_q, s5_chkdma_d;

   
   (* mark_debug = "false" *)
   reg                       [3:0] s6_req_state_q;
   reg                       [3:0] s6_req_state_d;
   reg         [datalen_width-1:0] s6_req_reloff_q, s6_req_reloff_d;
   reg        [wdatalen_width-1:0] s6_req_length_q, s6_req_length_d;
   reg                      [15:0] s6_req_cid_q, s6_req_cid_d;
   reg                       [1:0] s6_req_cid_par_q, s6_req_cid_par_d; 
   reg         [datalen_width-1:0] s6_req_addr_q, s6_req_addr_d;
  
   localparam REQ_IDLE    = 4'h1;
   localparam REQ_WRSISL1 = 4'h2;
   localparam REQ_WRSISL2 = 4'h3;
   localparam REQ_WRINTN  = 4'h4;

   // DMA read requests for microcode/admin functions
   reg                             admin_valid_q, admin_valid_d;
   reg             [tag_width-1:0] admin_tag_q, admin_tag_d;
   reg                             admin_tag_par_q, admin_tag_par_d;
   reg         [datalen_width-1:0] admin_reloff_q, admin_reloff_d;
   reg        [wdatalen_width-1:0] admin_length_q, admin_length_d;
   reg                       [7:0] dma_pe_inj_d,dma_pe_inj_q;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin      
             s0_req_hdr_q     <= zero[req_hdr_par_width+req_hdr_width-1:0];
             s0_chkdma_q      <= 1'b0;
             s0_error_q       <= 2'b00;
             s0_discard_q     <= 1'b0;

             s1_valid_q       <= 1'b0;
             s1_first_q       <= 1'b0;
             s1_last_q        <= 1'b0;
             s1_discard_q     <= 1'b0;
             s1_error_q       <= 2'b00;
             s1_rnw_q         <= 1'b0;
             s1_chkdma_q      <= 1'b0;
             
             s2_valid_q       <= 1'b0;
             s2_first_q       <= 1'b0;
             s2_last_q        <= 1'b0;
             s2_discard_q     <= 1'b0;
             s2_error_q       <= 2'b00;
             s2_rnw_q         <= 1'b0;
             s2_chkdma_q      <= 1'b0;
                           
             s3_valid_q       <= 1'b0;
             s3_first_q       <= 1'b0;
             s3_last_q        <= 1'b0;
             s3_discard_q     <= 1'b0;
             s3_error_q       <= 2'b00;
             s3_rnw_q         <= 1'b0;
             s3_chkdma_q      <= 1'b0;
             
             s4_valid_q       <= 1'b0;
             s4_first_q       <= 1'b0;
             s4_last_q        <= 1'b0;
             s4_discard_q     <= 1'b0;
             s4_error_q       <= 2'b00;
             s4_rnw_q         <= 1'b0;
             s4_chkdma_q      <= 1'b0;
               
             s5_valid_q       <= 1'b0;
             s5_first_q       <= 1'b0;
             s5_last_q        <= 1'b0;
             s5_discard_q     <= 1'b0;
             s5_error_q       <= 2'b00;
             s5_rnw_q         <= 1'b0;
             s5_chkdma_q      <= 1'b0;

             s6_req_state_q   <= REQ_IDLE;
             s6_req_reloff_q  <= zero[datalen_width-1:0];
             s6_req_length_q  <= zero[wdatalen_width-1:0];
             s6_req_cid_q     <= zero[15:0];              
             s6_req_cid_par_q <= one[1:0];   
             s6_req_addr_q    <= zero[datalen_width-1:0];

             admin_valid_q    <= 1'b0;
             admin_tag_q      <= zero[tag_width-1:0];
             admin_tag_par_q  <= 1'b0;                      
             admin_reloff_q   <= zero[datalen_width-1:0];
             admin_length_q   <= zero[wdatalen_width-1:0];
             dma_pe_inj_q     <= 8'h0;
             
          end
        else
          begin
             s0_req_hdr_q     <= s0_req_hdr_d;
             s0_chkdma_q      <= s0_chkdma_d;
             s0_error_q       <= s0_error_d;
             s0_discard_q     <= s0_discard_d;

             s1_valid_q       <= s1_valid_d;
             s1_first_q       <= s1_first_d;
             s1_last_q        <= s1_last_d;
             s1_discard_q     <= s1_discard_d;
             s1_error_q       <= s1_error_d;
             s1_rnw_q         <= s1_rnw_d;
             s1_chkdma_q      <= s1_chkdma_d;
  
             s2_valid_q       <= s2_valid_d;
             s2_first_q       <= s2_first_d;
             s2_last_q        <= s2_last_d;
             s2_discard_q     <= s2_discard_d;
             s2_error_q       <= s2_error_d;
             s2_rnw_q         <= s2_rnw_d;
             s2_chkdma_q      <= s2_chkdma_d;
  
             s3_valid_q       <= s3_valid_d;
             s3_first_q       <= s3_first_d;
             s3_last_q        <= s3_last_d;
             s3_discard_q     <= s3_discard_d;
             s3_error_q       <= s3_error_d;
             s3_rnw_q         <= s3_rnw_d;
             s3_chkdma_q      <= s3_chkdma_d;
             
             s4_valid_q       <= s4_valid_d;
             s4_first_q       <= s4_first_d;
             s4_last_q        <= s4_last_d;
             s4_discard_q     <= s4_discard_d;
             s4_error_q       <= s4_error_d;
             s4_rnw_q         <= s4_rnw_d;
             s4_chkdma_q      <= s4_chkdma_d;
           
             s5_valid_q       <= s5_valid_d;
             s5_first_q       <= s5_first_d;
             s5_last_q        <= s5_last_d;
             s5_discard_q     <= s5_discard_d;
             s5_error_q       <= s5_error_d;
             s5_rnw_q         <= s5_rnw_d;
             s5_chkdma_q      <= s5_chkdma_d;

             s6_req_state_q   <= s6_req_state_d;
             s6_req_reloff_q  <= s6_req_reloff_d;
             s6_req_length_q  <= s6_req_length_d;
             s6_req_cid_q     <= s6_req_cid_d;                     
             s6_req_cid_par_q <= s6_req_cid_par_d;      
             s6_req_addr_q    <= s6_req_addr_d;
             
             admin_valid_q    <= admin_valid_d;
             admin_tag_q      <= admin_tag_d;
             admin_tag_par_q  <= admin_tag_par_d;
             admin_reloff_q   <= admin_reloff_d;
             admin_length_q   <= admin_length_d;
             dma_pe_inj_q     <= dma_pe_inj_d;
          end
     end

   always @(posedge clk)
     begin
        s1_data_q       <= s1_data_d;
        s2_data_q       <= s2_data_d;
        s3_data_q       <= s3_data_d;
        s4_data_q       <= s4_data_d;
        s5_data_q       <= s5_data_d;
     end   

   // request header fields
   reg                   [1:0] req_addr_type; 
   reg        [addr_width-1:0] req_addr;
   reg                   [3:0] req_last_be;
   reg                   [3:0] req_first_be;
   reg                   [7:0] req_tag;
   reg         [cid_width-1:0] req_cid;
   reg                   [3:0] req_addr_region;
   reg                         req_rd;
   reg                         req_wr;
   reg                         req_other;
   reg                   [2:0] req_tc;
   reg                   [2:0] req_attr;
   reg                  [10:0] req_dcount;

   reg                         s0_chk_dma;
   reg                   [1:0] s0_error;
   reg [req_hdr_par_width-1:0] s0_reg_par;
   reg                   [1:0] s0_req_addr_type; 
   reg        [addr_width-1:0] s0_req_addr;
   reg                   [3:0] s0_req_last_be;
   reg                   [3:0] s0_req_first_be;
   reg                   [7:0] s0_req_tag;
   reg         [cid_width-1:0] s0_req_cid;
   reg                   [3:0] s0_req_addr_region;
   reg                         s0_req_rd;
   reg                         s0_req_wr;
   reg                         s0_req_other;
   reg                   [2:0] s0_req_tc;
   reg                   [2:0] s0_req_attr;
   reg                  [10:0] s0_req_dcount;

   reg                   [1:0] s5_req_addr_type; 
   reg        [addr_width-1:0] s5_req_addr;
   reg                   [3:0] s5_req_last_be;
   reg                   [3:0] s5_req_first_be;
   reg                   [7:0] s5_req_tag;
   reg         [cid_width-1:0] s5_req_cid;
   reg                   [3:0] s5_req_addr_region;
   reg                         s5_req_rd;
   reg                         s5_req_wr;
   reg                         s5_req_other;
   reg                   [2:0] s5_req_tc;
   reg                   [2:0] s5_req_attr;
   reg                  [10:0] s5_req_dcount;


   // check if request is valid on 1st cycle
   reg                   [1:0] req_error;
   reg                         req_chk_dma;
   wire                        cpl_fifo_valid;
   (* mark_debug = "false" *)


   always @*
     begin
        dma_pe_inj_d = dma_pe_inj_q ;      
        if (regs_wdata_pe_errinj_1cycle_valid & regs_sntl_pe_errinj_valid & regs_xxx_pe_errinj_decode[11:8] == 4'h2)
          begin
             dma_pe_inj_d[0]  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
             dma_pe_inj_d[1]  = (regs_xxx_pe_errinj_decode[3:0]==4'h1);
             dma_pe_inj_d[2]  = (regs_xxx_pe_errinj_decode[3:0]==4'h2);
             dma_pe_inj_d[3]  = (regs_xxx_pe_errinj_decode[3:0]==4'h3);
             dma_pe_inj_d[4]  = (regs_xxx_pe_errinj_decode[3:0]==4'h4);
             dma_pe_inj_d[5]  = (regs_xxx_pe_errinj_decode[3:0]==4'h5);
             dma_pe_inj_d[6]  = (regs_xxx_pe_errinj_decode[3:0]==4'h6);
             dma_pe_inj_d[7]  = (regs_xxx_pe_errinj_decode[3:0]==4'h7);
          end 
        if (dma_pe_inj_q[0] & pcie_sntl_valid)
          dma_pe_inj_d[0] = 1'b0;
        if (dma_pe_inj_q[1] & pcie_sntl_valid)
          dma_pe_inj_d[1] = 1'b0;
        if (dma_pe_inj_q[2] & s0_valid)
          dma_pe_inj_d[2] = 1'b0;
        if (dma_pe_inj_q[3] & s4_valid_q)
          dma_pe_inj_d[3] = 1'b0;
        if (dma_pe_inj_q[4] & admin_valid_q)
          dma_pe_inj_d[4] = 1'b0;
        if (dma_pe_inj_q[5] & wdata_dma_cpl_valid)
          dma_pe_inj_d[5] = 1'b0;
        if (dma_pe_inj_q[6] & wdata_dma_cpl_valid)
          dma_pe_inj_d[6] = 1'b0;
        if (dma_pe_inj_q[7] & cpl_fifo_valid)
          dma_pe_inj_d[7] = 1'b0;
     end  

   // parity checking / generation logic 
   
   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(data_width)
      ) ipcheck_pcie_sntl_data 
       (.oddpar(1'b1),.data({pcie_sntl_data[data_width-1:1],(pcie_sntl_data[0]^dma_pe_inj_q[0])}),.datap(pcie_sntl_data[data_par_width-1+data_width-1:data_width]),.check(pcie_sntl_valid),.parerr(s1_perror[0])); 

   nvme_pcheck#
     (
      .bits_per_parity_bit(3),
      .width(3)
      ) ipcheck_pcie_sntl_ctrl 
       (.oddpar(1'b1),.data({pcie_sntl_first,pcie_sntl_last,(pcie_sntl_discard^dma_pe_inj_q[1])}),.datap(pcie_sntl_data[data_par_width+data_width-1]),.check(pcie_sntl_valid),.parerr(s1_perror[1])); 



   always @*
     begin

        { req_addr_type, 
          req_attr, 
          req_tc, 
          req_dcount, 
          req_last_be,
          req_first_be,
          req_other, 
          req_rd, 
          req_wr,
          req_tag, 
          req_addr_region,         
          req_addr} = pcie_sntl_data[req_hdr_width-1:0];    
        req_cid = req_addr[addr_width-1:addr_width-cid_width];
        
        req_error = 2'b00;
        req_chk_dma = 1'b0;
        
        if( req_first_be != 4'hF ||
            req_last_be != 4'hF )
          begin
             // unexpected byte enables
             req_error = 2'b10;  // completer abort
          end
        
        if( req_rd && ~pcie_sntl_first)
          begin               
             req_error = 2'b01;  // unsupported request - read request should be 1 cycle                  
          end

        if( req_other )
          begin
             req_error = 2'b01;
          end

        if( ! (req_addr_region == ENUM_ADDR_SISL ||
               req_addr_region == ENUM_ADDR_INTN))
          begin
             req_error = 2'b01;
          end

        if( req_error==2'b00 && req_addr_region == ENUM_ADDR_SISL )
          begin
             // check command tracking for accesses to host memory
             req_chk_dma = 1'b1;
          end

     end // always @ *

   
   localparam s0_width = 6 + data_par_width + data_width;  
   reg           [s0_width-1:0] s0_din;
   wire          [s0_width-1:0] s0_dout;
   wire [req_hdr_par_width-1:0] s0_dout_hdr_par;

   nvme_pl_burp#(.width(s0_width), .stage(1)) s0 
     (.clk(clk),.reset(reset),
      .valid_in(pcie_sntl_valid),
      .data_in(s0_din),
      .ready_out(sntl_pcie_ready),
                 
      .data_out(s0_dout),
      .valid_out(s0_valid),
      .ready_in(s0_ready)
      ); 
   // check s0_data parity 

   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(data_width)
      ) ipcheck_s0_data 
       (.oddpar(1'b1),.data({s0_data[data_width-1:1],(s0_data[0]^dma_pe_inj_q[2])}),.datap(s0_data[data_par_width-1 +data_width-1:data_width]),.check(s0_valid),.parerr(s1_perror[2])); 
  



   // generate header parity
   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(req_hdr_width)
      ) ipgen_s0_dout 
       (.oddpar(1'b1),.data(s0_dout[req_hdr_width-1:0]),.datap(s0_dout_hdr_par[req_hdr_par_width-1:0])); 
   
   always @*
     begin
        s0_din = {pcie_sntl_first, pcie_sntl_last, pcie_sntl_discard, req_chk_dma, req_error, pcie_sntl_data};  
        { s0_first, s0_last, s0_discard, s0_chk_dma, s0_error, s0_data} = s0_dout;   
     end

   // gen parity on s0_req_cid 
   wire [cid_par_width-1:0] s0_req_cid_par;
   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(cid_width)
      ) ipgen_s0_req_cid 
       (.oddpar(1'b1),.data(s0_req_cid),.datap(s0_req_cid_par)); 
   

   // save header until last cycle
   always @*
     begin

        if( s0_valid & s0_first )
          begin
             s0_req_hdr_d  = {s0_dout_hdr_par,s0_dout[req_hdr_width-1:0]}; 
             s0_chkdma_d   = s0_chk_dma;
             s0_error_d    = s0_error;
             s0_discard_d  = s0_discard;
          end
        else
          begin
             // hold until last
             s0_req_hdr_d  = s0_req_hdr_q;
             s0_chkdma_d   = s0_chkdma_q;
             s0_error_d    = s0_error_q;
             // accumulate discard on any valid cycle
             s0_discard_d  = s0_discard_q | (s0_valid & s0_discard);
          end         

        { s0_reg_par,              
          s0_req_addr_type, 
          s0_req_attr, 
          s0_req_tc, 
          s0_req_dcount, 
          s0_req_last_be,
          s0_req_first_be,
          s0_req_other, 
          s0_req_rd, 
          s0_req_wr, 
          s0_req_tag, 
          s0_req_addr_region,            
          s0_req_addr} = s0_req_hdr_d;
        s0_req_cid = s0_req_addr[addr_width-1:addr_width-cid_width];

     end

 

   wire      s0_req_dcount_par;

   nvme_pgen#
     (
      .bits_per_parity_bit(11),
      .width(11)
      ) ipgen_s0_req_dcount
       (.oddpar(1'b1),.data(s0_req_dcount),.datap(s0_req_dcount_par)); 

   // send request info to command tracking table on last cycle unless there's an error
   always @*
     begin

        dma_cmd_valid       = s0_valid & s0_last & s0_chkdma_d & ~s0_discard_d;
        s0_ready            = cmd_dma_ready | ~dma_cmd_valid;
        
        dma_cmd_cid         = s0_req_cid;
        dma_cmd_cid_par     = s0_req_cid_par;
        dma_cmd_rnw         = s0_req_rd;
        dma_cmd_reloff      = s0_req_addr;
        dma_cmd_length      = { s0_req_dcount[wdatalen_width-1-2:0], 2'b00 };
        dma_cmd_length_par  = s0_req_dcount_par ;

        s1_valid_d          = s0_valid & s0_ready;
        s1_first_d          = s0_first;
        s1_last_d           = s0_last;
        s1_discard_d        = s0_discard_d;
        s1_error_d          = s0_error_d;
        s1_rnw_d            = s0_req_rd;
        s1_data_d           = s0_data;
        s1_chkdma_d         = s0_chkdma_d;        
     end
   
   // stage 2 - tracking table latency
   always @*
     begin
        s2_valid_d    = s1_valid_q;
        s2_first_d    = s1_first_q;
        s2_last_d     = s1_last_q;
        s2_discard_d  = s1_discard_q;
        s2_error_d    = s1_error_q;
        s2_rnw_d      = s1_rnw_q;
        s2_data_d     = s1_data_q;        
        s2_chkdma_d   = s1_chkdma_q;        
     end
   
   // stage 3 - tracking table latency
   always @*
     begin
        s3_valid_d    = s2_valid_q;
        s3_first_d    = s2_first_q;
        s3_last_d     = s2_last_q;
        s3_discard_d  = s2_discard_q;
        s3_error_d    = s2_error_q;
        s3_rnw_d      = s2_rnw_q;
        s3_data_d     = s2_data_q;        
        s3_chkdma_d   = s2_chkdma_q;        
     end
   // stage 4 - tracking table latency
   always @*
     begin
        s4_valid_d    = s3_valid_q;
        s4_first_d    = s3_first_q;
        s4_last_d     = s3_last_q;
        s4_discard_d  = s3_discard_q;
        s4_error_d    = s3_error_q;
        s4_rnw_d      = s3_rnw_q;
        s4_data_d     = s3_data_q;        
        s4_chkdma_d   = s3_chkdma_q;        
     end

   // stage 5 
   always @*
     begin
        s5_valid_d    = s4_valid_q;
        s5_first_d    = s4_first_q;
        s5_last_d     = s4_last_q;
        s5_discard_d  = s4_discard_q;
        s5_error_d    = s4_error_q;
        s5_rnw_d      = s4_rnw_q;
        s5_data_d     = s4_data_q;
        s5_chkdma_d   = s4_chkdma_q;        
     end

   // completion header fifo
   localparam cpl_fifo_par_width = ((req_hdr_width + 3) + 63)/64;
   localparam cpl_fifo_width = cpl_fifo_par_width + req_hdr_width + 3;
 

   reg                       cpl_fifo_flush;
   (* mark_debug = "false" *)
   reg                       cpl_fifo_push;
   reg                 [2:0] cpl_fifo_req_error;
   
   (* mark_debug = "false" *)
   reg                       cpl_fifo_taken;
   wire [cpl_fifo_width-1:0] cpl_fifo_data;
   
   (* mark_debug = "false" *)
   wire                      cpl_fifo_full;
   (* mark_debug = "false" *)
   wire                      cpl_fifo_almost_full;


   reg                       pcie_admin_valid;
   reg      [addr_width-1:0] pcie_admin_addr;
   reg               [144:0] pcie_admin_data;
    
 
   // stage 4 
   // send read requests to wdata + completion header fifo
   // send write requests to rsp fifo
   //
   // check parity 
   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(data_width)
      ) ipcheck_s4_data 
       (.oddpar(1'b1),.data({s4_data_q[data_width-1:1],(s4_data_q[0]^dma_pe_inj_q[3])}),.datap(s4_data_q[data_par_width-1+data_width-1:data_width]),.check(s4_valid_q),.parerr(s1_perror[3])); 
   // gen tag parity 

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(data_par_width-1)
      ) ipgen_dma_rsp_data 
       (.oddpar(1'b1),.data(s5_data_q[data_par_width-1+data_width-1:data_width]),.datap(dma_rsp_data_par)); 
   

   wire                      s5_req_cid_par;  
   wire                      s5_req_dcount_par;  

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(tag_width)
      ) ipgen_s5_req_cid 
       (.oddpar(1'b1),.data(s5_req_cid[tag_width-1:0]),.datap(s5_req_cid_par)); 
   
   nvme_pgen#
     (
      .bits_per_parity_bit(11),
      .width(11)
      ) ipgen_s5_req_dcount 
       (.oddpar(1'b1),.data( s5_req_dcount),.datap(s5_req_dcount_par)); 
   

   always @*
     begin
        s5_cmd_error  = (~cmd_dma_valid | cmd_dma_error) & s5_chkdma_q & ~s5_discard_q;

        { s5_req_addr_type, 
          s5_req_attr, 
          s5_req_tc, 
          s5_req_dcount, 
          s5_req_last_be,
          s5_req_first_be,
          s5_req_other, 
          s5_req_rd, 
          s5_req_wr, 
          s5_req_tag, 
          s5_req_addr_region, 
          s5_req_addr}            = s5_data_q;
        s5_req_cid = s5_req_addr[addr_width-1:addr_width-cid_width];

        
        s6_req_state_d            = s6_req_state_q;

        // DMA reads
        dma_wdata_req_valid       = 1'b0;
        dma_wdata_req_tag         = s5_req_cid;       
        dma_wdata_req_tag_par     = s5_req_cid_par;  
        dma_wdata_req_reloff      = s5_req_addr[datalen_width-1:0]; // offset from start address of this command
        dma_wdata_req_length      = {s5_req_dcount[wdatalen_width-1-2:0], 2'b00};    // number of bytes to request, max 512B
        dma_wdata_req_length_par  = s5_req_dcount_par; 
        cpl_fifo_flush            = 1'b0;
        cpl_fifo_push             = 1'b0;
        cpl_fifo_req_error        = 3'b000;  // {cmd lookup error, completer_abort, unsupported request}
      

        // DMA writes
        s6_req_reloff_d           = s6_req_reloff_q;
        s6_req_length_d           = s6_req_length_q;
        s6_req_cid_d              = s6_req_cid_q;
        s6_req_cid_par_d          = s6_req_cid_par_q;   
        s6_req_addr_d             = s6_req_addr_q;
        dma_rsp_valid             = 1'b0;  
        dma_rsp_first             = 1'b0;
        dma_rsp_last              = 1'b0;

        pcie_admin_valid          = 1'b0;
        dma_admin_req_ack         = 1'b0;
        
        // block on a TLP boundary when:
        // - no room for DMA read requests in pipeline
        // - no room for 128B DMA write x 2
        // - no room for DMA read completion headers
        sntl_pcie_pause           = wdata_dma_req_pause | rsp_dma_pause | cpl_fifo_almost_full; 
        
        
        case(s6_req_state_q)
          REQ_IDLE:
            begin                 
               if( s5_valid_q )
                 begin
                    if( s5_rnw_q ) 
                      begin
                         // a read request is one cycle on the interface, so last should be asserted
                         if( s5_last_q & ~s5_discard_q )
                           begin                   
                              if( s5_error_q!=2'b00 ||
                                  s5_cmd_error )
                                begin
                                   // either address was invalid or some other unexpected field
                                   cpl_fifo_push = 1'b1;
                                   cpl_fifo_req_error = {s5_cmd_error, s5_error_q};
                                end
                              else
                                begin
                                   dma_wdata_req_valid = 1'b1;
                                   cpl_fifo_push = 1'b1;
                                end
                           end
                      end
                    else
                      begin                      
                         if( s5_first_q )
                           begin
                              // save header fields of a DMA write (sislite read or admin)
                              s6_req_reloff_d = s5_req_addr[datalen_width-1:0];
                              s6_req_length_d = {s5_req_dcount[wdatalen_width-1-2:0], 2'b00};
                              s6_req_cid_d    = s5_req_cid;
                              s6_req_cid_par_d    = s5_req_cid_par; 
                              s6_req_addr_d   = s5_req_addr[datalen_width-1:0];

                              if( ~s5_last_q )
                                begin
                                   if( s5_req_addr_region == ENUM_ADDR_SISL )
                                     begin
                                        // payload for SISL read command
                                        s6_req_state_d = REQ_WRSISL1;
                                     end
                                   else if( s5_req_addr_region == ENUM_ADDR_INTN )
                                     begin
                                        // payload for Admin command for microcontroller
                                        s6_req_state_d = REQ_WRINTN;
                                     end
                                   // else - ignore writes to invalid address space
                                end
                              // else - ignore writes that have no data
                           end
                      end                                                 
                 end 
               else if( admin_dma_req_valid & ~wdata_dma_req_pause & ~admin_valid_q)
                 begin
                    dma_wdata_req_valid   = 1'b1;
                    dma_wdata_req_tag     = admin_dma_req_tag;       
                    dma_wdata_req_tag_par     = admin_dma_req_tag_par;  
                    dma_wdata_req_reloff  = admin_dma_req_reloff;
                    dma_wdata_req_length  = admin_dma_req_length;
                    dma_wdata_req_length_par  = admin_dma_req_length_par; 
                    dma_admin_req_ack     = 1'b1;
                 end                                
            end
          
          REQ_WRSISL1:
            begin
               // send SISL Read payload to response fifo
               dma_rsp_first = 1'b1;
               if( s5_valid_q )
                 begin
                    dma_rsp_valid = 1'b1;
                    s6_req_addr_d = s6_req_addr_q  + {zero[datalen_width-1:8],8'd16};
                    if( s5_last_q )
                      begin
                         dma_rsp_last = 1'b1;
                         s6_req_state_d = REQ_IDLE;
                      end        
                    else
                      begin
                         s6_req_state_d = REQ_WRSISL2;
                      end
                  end
            end
          
          REQ_WRSISL2:
            begin
               // send SISL Read payload to response fifo
               if( s5_valid_q )
                 begin
                    dma_rsp_valid = 1'b1;
                    s6_req_addr_d = s6_req_addr_q + {zero[datalen_width-1:8],8'd16};
                    if( s5_last_q )
                      begin
                         dma_rsp_last = 1'b1;
                         s6_req_state_d = REQ_IDLE;
                      end                    
                  end
            end
          
          REQ_WRINTN:
            begin
               // send payload for microcontroller Admin commands to internal memory
               if( s5_valid_q )
                  begin
                     pcie_admin_valid = 1'b1;
                     s6_req_addr_d = s6_req_addr_q + {zero[datalen_width-1:8],8'd16};
                     if( s5_last_q )
                       begin
                          s6_req_state_d = REQ_IDLE;
                       end                     
                  end
            end
          

          default:
            begin            
               s6_req_state_d = REQ_IDLE;
            end
        endcase // case (s6_req_state_q)
               
        dma_rsp_reloff   = s6_req_reloff_q;
        dma_rsp_length   = s6_req_length_q;             
        dma_rsp_tag      = s6_req_cid_q[tag_width-1:0];
        dma_rsp_tag_par  = s6_req_cid_par_q[0];
        dma_rsp_data     = s5_data_q;  // PCIe data starts 1 cycle after header fields, so use s3 here

        pcie_admin_addr  = s6_req_addr_q;     
        pcie_admin_data  = s5_data_q;

     end // always @ *

   //-------------------------------------------------------
   // fifo for DMA read headers
   //-------------------------------------------------------
 

   wire     [cpl_fifo_par_width-1:0]   cpl_fifo_par;
   nvme_pgen#
     (
      .bits_per_parity_bit(64),
      .width(3 + req_hdr_width)
      ) ipgen_s4_data_q_hdr 
       (.oddpar(1'b1),.data({cpl_fifo_req_error,s5_data_q[req_hdr_width-1:0]}),.datap(cpl_fifo_par)); 

   
   nvme_fifo#(
              .width(cpl_fifo_width), 
              .words(260),
              .almost_full_thresh(4)
              ) cpl_fifo
     (.clk(clk), .reset(reset), 
      .flush(       cpl_fifo_flush ),
      .push(        cpl_fifo_push ),
      .din(           {cpl_fifo_par, cpl_fifo_req_error, s5_data_q[req_hdr_width-1:0]} ),
      .dval(        cpl_fifo_valid ), 
      .pop(         cpl_fifo_taken ),
      .dout(        cpl_fifo_data ),
      .full(        cpl_fifo_full ), 
      .almost_full( cpl_fifo_almost_full ), 
      .used());  

   // check fifo parity 
   nvme_pcheck#
     (
      .bits_per_parity_bit(64),
      .width(cpl_fifo_width-cpl_fifo_par_width)
      ) ipcheck_cpl_fifo_data 
       (.oddpar(1'b1),.data({cpl_fifo_data[cpl_fifo_width-cpl_fifo_par_width-1:1],(cpl_fifo_data[0]^dma_pe_inj_q[7])}),.datap(cpl_fifo_data[cpl_fifo_width-1:cpl_fifo_width-cpl_fifo_par_width]),.check(cpl_fifo_valid),.parerr(s1_perror[7])); 





   //-------------------------------------------------------
   // generate completions
   //-------------------------------------------------------


   reg                         [144:0] cpl_s0_data;     // added byte parity 
   reg                                 cpl_s0_first;
   reg                                 cpl_s0_last;
   reg                                 cpl_s0_discard;
   reg                                 cpl_s0_valid;
   wire                                cpl_s0_ready;
   
   // build completion header from request header
   reg                          [12:0] cpl_bytes_total;
   reg                          [12:0] cpl_bytes_first;
   reg                          [12:0] cpl_bytes_last;
   
   (* mark_debug = "false" *) 
   reg                          [10:0] cpl_dwords_sent_q;
   reg                          [10:0] cpl_dwords_sent_d;
   reg                          [10:0] cpl_dwords_not_sent;
   reg                          [10:0] cpl_dwords_sent_inc;

   (* mark_debug = "false" *) 
   reg                           [2:0] cpl_s0_req_error;  // {lookup error, completer abort, unsupported request} - no wdata request/response
   reg        [cpl_fifo_par_width-1:0] cpl_s0_req_fifo_par;
   reg                           [1:0] cpl_s0_req_addr_type; 
   reg                [addr_width-1:0] cpl_s0_req_addr;
   reg                           [3:0] cpl_s0_req_last_be;
   reg                           [3:0] cpl_s0_req_first_be;
   reg                           [7:0] cpl_s0_req_tag;
   reg                 [cid_width-1:0] cpl_s0_req_cid;
   wire            [cid_par_width-1:0] cpl_s0_req_cid_par;
   reg                           [3:0] cpl_s0_req_addr_region;
   reg                                 cpl_s0_req_rd;
   reg                                 cpl_s0_req_wr;
   reg                                 cpl_s0_req_other;
   reg                           [2:0] cpl_s0_req_tc;
   reg                           [2:0] cpl_s0_req_attr;
   (* mark_debug = "false" *) 
   reg                          [10:0] cpl_s0_req_dcount;
   
   // completion header fields
   reg             [cpl_hdr_width-1:0] cpl_s0_hdr;
   (* mark_debug = "false" *)
   reg                          [10:0] cpl_dcount;  // number of dwords in this packet
   (* mark_debug = "false" *)
   reg                           [2:0] cpl_status;  // 0x0 - success; 0x1 - unsupported request; 0x2 - completer abort
   (* mark_debug = "false" *)
   reg                          [12:0] cpl_byte_count;  // remaining bytes to be transferred including this packet
   reg                           [6:0] cpl_lower_addr;  // starting offset of this packet

   // state machine for sending UR or CA responses - two cycles on sntl_pcie_cc_* interface
   localparam [3:0] CPLSM_IDLE   = 4'h1;
   localparam [3:0] CPLSM_WAIT   = 4'h2; // wait for last
   localparam [3:0] CPLSM_HDR    = 4'h3; // send descriptor cycle on sntl_pcie_cc_*
   localparam [3:0] CPLSM_PAYLD  = 4'h4; // send payload data on sntl_pcie_cc_*
   localparam [3:0] CPLSM_ERRDAT = 4'h5; // send up to 8 cycles of "DEADBEEF" on sntl_pcie_cc_*
   localparam [3:0] CPLSM_END    = 4'h6; // send payload last cycle to sntl_pcie_cc_*
   localparam [3:0] CPLSM_STAT   = 4'h7; // send error indication to command tracking
   (* mark_debug = "false" *) 
   reg                           [3:0] cplsm_q;
   reg                           [3:0] cplsm_d;
   (* mark_debug = "false" *) 
   reg            [wdatalen_width-1:0] cpl_err_length_q, cpl_err_length_d;  // 128B max
   
   reg                                 cpl_wdata_valid;
   reg                 [tag_width-1:0] cpl_wdata_tag;
   reg             [datalen_width-1:0] cpl_wdata_reloff;
   reg                           [9:0] cpl_wdata_length; // number of bytes in buffer 128B max
   reg                         [143:0] cpl_wdata_data;   
   reg                                 cpl_wdata_first; // first cycle of this completion
   reg                                 cpl_wdata_last; // last cycle of this completion

   (* mark_debug = "false" *) 
   wire                                wdata_is_admin;
   (* mark_debug = "false" *) 
   wire                                wdata_is_pcie;
   
   
   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(tag_width)
      ) ipcheck_admin_tag_q 
       (.oddpar(1'b1),.data({admin_tag_q[tag_width-1:1],(admin_tag_q[0]^dma_pe_inj_q[4])}),.datap(admin_tag_par_q),.check(admin_valid_q),.parerr(s1_perror[4])); 

   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(tag_width)
      ) ipcheck_wdata_dma_cpl_tag
       (.oddpar(1'b1),.data({wdata_dma_cpl_tag[tag_width-1:1],(wdata_dma_cpl_tag[0]^dma_pe_inj_q[5])}),.datap(wdata_dma_cpl_tag_par),.check(wdata_dma_cpl_valid),.parerr(s1_perror[5])); 


   assign wdata_is_admin = wdata_dma_cpl_valid & admin_valid_q && wdata_dma_cpl_tag==admin_tag_q; // wdata is for admin buffer
   assign wdata_is_pcie  = wdata_dma_cpl_valid & cpl_fifo_valid && cpl_s0_req_error==3'b000 && (wdata_dma_cpl_tag==cpl_s0_req_cid[tag_width-1:0]);

   // pcheck wdata_dma_cpl_data
   
   nvme_pcheck#
     (
      .bits_per_parity_bit(64),
      .width(128)
      ) ipcheck_wdata_dma_cpl_data
       (.oddpar(1'b1),.data({wdata_dma_cpl_data[127:1],(wdata_dma_cpl_data[0]^dma_pe_inj_q[6])}),.datap(wdata_dma_cpl_data[129:128]),.check(wdata_dma_cpl_valid),.parerr(s1_perror[6])); 

   wire                         [15:0] wdata_dma_cpl_data_byte_par;

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(128)
      ) ipgen_wdata_dma_cpl_data 
       (.oddpar(1'b1),.data(wdata_dma_cpl_data[127:0]),.datap(wdata_dma_cpl_data_byte_par)); 
   


   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin            
             cpl_dwords_sent_q <= zero[10:0];
             cplsm_q           <= CPLSM_IDLE;
             cpl_err_length_q  <= zero[wdatalen_width-1:0];
          end
        else
          begin           
             cpl_dwords_sent_q <= cpl_dwords_sent_d;
             cplsm_q           <= cplsm_d;
             cpl_err_length_q  <= cpl_err_length_d;
          end
     end

   // gen parity on cpl_s0_req_cid
   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(cid_width)
      ) ipgen_cpl_s0_req_cid 
       (.oddpar(1'b1),.data(cpl_s0_req_cid),.datap(cpl_s0_req_cid_par));
   
   reg [1:0] cpl_errcfg;
   always @*
     begin
        cplsm_d                = cplsm_q;
        cpl_err_length_d       = cpl_err_length_q;

        dma_cmd_wdata_valid    = 1'b0;
        dma_cmd_wdata_error    = 1'b1;
        dma_cmd_wdata_cid      = cpl_s0_req_cid;
        dma_cmd_wdata_cid_par  = cpl_s0_req_cid_par; 

        cpl_wdata_valid        = 1'b0;
        cpl_wdata_tag          = wdata_dma_cpl_tag;
        cpl_wdata_reloff       = wdata_dma_cpl_reloff;
        cpl_wdata_length       = wdata_dma_cpl_length;
        cpl_wdata_data         = {wdata_dma_cpl_data_byte_par,wdata_dma_cpl_data[127:0]};
        cpl_wdata_first        = 1'b0;
        cpl_wdata_last         = 1'b0;
        
        cpl_fifo_taken         = 1'b0;

        cpl_status             = 3'b000;  // success encode
        cpl_errcfg             = regs_dma_errcpl[1:0];

        case(cplsm_q)
          CPLSM_IDLE:
            begin                  
               if( cpl_fifo_valid && 
                   cpl_s0_req_error!=3'b000 )
                 begin
                    // if sending UR or CA status, 1st cycle is cpl_s0_hdr (used to build descriptor)
                    cplsm_d          = CPLSM_HDR;
                 end
               else if( wdata_is_pcie )
                 begin
                    if( ~wdata_dma_cpl_first | wdata_dma_cpl_error | wdata_dma_cpl_last)
                      begin
                         // error or runt data from wdata
                         if( wdata_dma_cpl_last && wdata_dma_cpl_end)
                           begin
                              cplsm_d = CPLSM_HDR;
                           end
                         else
                           begin
                              cplsm_d = CPLSM_WAIT;
                           end
                      end                            
                    else
                      begin
                         cpl_wdata_valid  = 1'b1;
                         cpl_wdata_first  = 1'b1;        
                         if( cpl_s0_ready )
                           begin
                              cplsm_d = CPLSM_PAYLD;
                           end
                      end
                 end
            end
          
          CPLSM_PAYLD:
            begin
               // normal payload - wait for last on wdata interface
               cpl_wdata_valid = wdata_dma_cpl_valid;
               cpl_wdata_last  = wdata_dma_cpl_last;        
               if( cpl_s0_ready & wdata_dma_cpl_valid & wdata_dma_cpl_last )
                 begin
                    if( wdata_dma_cpl_end )
                      begin
                         cpl_fifo_taken = 1'b1;
                      end
                    cplsm_d = CPLSM_IDLE;
                 end                  
            end
          
      
          CPLSM_WAIT:
            begin
               // wait for last+end on wdata interface
               cpl_wdata_valid = 1'b0;
               if( wdata_dma_cpl_valid & wdata_dma_cpl_last && wdata_dma_cpl_end )
                 begin
                    cplsm_d = CPLSM_HDR;
                 end                  
            end
          
          CPLSM_HDR:
            begin               
               // send 1st cycle of UR/CA or header for data completion
               cpl_wdata_valid = 1'b1;
               cpl_wdata_first = 1'b1;
               cpl_wdata_last  = 1'b0;
              
               // set the number of bytes of error payload remaining
               if( cpl_dwords_not_sent >= (128/4) )
                 begin
                    cpl_err_length_d = 128;
                 end
               else
                 begin
                    cpl_err_length_d = {cpl_dwords_not_sent[wdatalen_width-3:0],2'b00};  // dwords * 4 = bytes                    
                 end
               cpl_wdata_length = cpl_err_length_d;

               cpl_status = 3'b000;
               // 4 possible error cases:
               // 1) DMA request error - alignment
               // 2) DMA request bad address
               // 3) dma table lookup error
               // 4) wdata response error
               case(cpl_s0_req_error)
                 3'b000:  // wdata error
                   begin
                      cpl_errcfg = regs_dma_errcpl[7:6];
                   end
                 3'b001:  // DMA request error
                   begin
                      cpl_errcfg = regs_dma_errcpl[1:0];
                   end
                 3'b010: // DMA request bad address
                   begin
                      cpl_errcfg = regs_dma_errcpl[3:2];
                   end
                 default: // dma table lookup error
                   begin
                      cpl_errcfg = regs_dma_errcpl[5:4];
                   end
               endcase // case (cpl_s0_req_error)                                

               case(cpl_errcfg)
                 2'b00:  cpl_status = 3'b000; // success
                 2'b01:  cpl_status = 3'b001; // completer abort
                 default: cpl_status = 3'b010; // unsupported request
               endcase // case (cpl_errcfg)
                              
               if( cpl_s0_ready )
                 begin              
                    if( cpl_status == 3'b000 )
                      begin
                         cplsm_d = CPLSM_ERRDAT;
                      end
                    else
                      begin
                         // 2nd cycle of CA/UR response
                         cplsm_d = CPLSM_END;
                      end
                 end   
            end
          
          CPLSM_ERRDAT:
            begin
               // send dummy payload instead of UR/CA
               cpl_wdata_valid = 1'b1;
               cpl_wdata_last = 1'b0;
               if( cpl_s0_ready )
                 begin
                    cpl_err_length_d = cpl_err_length_q - 16;
                    if( cpl_err_length_q <= 16 )
                      begin
                         cpl_wdata_last = 1'b1;
                         if( cpl_dwords_not_sent <= 4 )
                           begin
                              cplsm_d = CPLSM_STAT;
                           end
                         else
                           begin
                              cplsm_d = CPLSM_HDR;
                           end
                      end
                 end   
            end
          
          CPLSM_END:
            begin
               // send 2nd cycle of UR/CA
               cpl_wdata_valid  = 1'b1;
               cpl_wdata_last   = 1'b1;
               if( cpl_s0_ready )
                 begin                   
                    cplsm_d = CPLSM_STAT;
                 end   
            end

          CPLSM_STAT:
            begin
               // send NVMe ABORT for this tag
               dma_cmd_wdata_valid = 1'b1;
               if( cmd_dma_wdata_ready )
                 begin
                    cpl_fifo_taken = 1'b1;
                    cplsm_d = CPLSM_IDLE;
                 end
            end
          
          default:
            begin            
               cplsm_d = CPLSM_IDLE;
            end
        endcase // case (cplsm_q)
     end // always @ *
   
   // build completion header fields
   // see xilinx PG156 - ultrascale pcie gen3 table 3-10
   always @*
     begin
        { cpl_s0_req_fifo_par,
          cpl_s0_req_error,
          cpl_s0_req_addr_type, 
          cpl_s0_req_attr, 
          cpl_s0_req_tc, 
          cpl_s0_req_dcount, 
          cpl_s0_req_last_be,
          cpl_s0_req_first_be,
          cpl_s0_req_other, 
          cpl_s0_req_rd, 
          cpl_s0_req_wr, 
          cpl_s0_req_tag, 
          cpl_s0_req_addr_region,           
          cpl_s0_req_addr} = cpl_fifo_data; 
        cpl_s0_req_cid = cpl_s0_req_addr[addr_width-1:addr_width-cid_width];

        // reset progress counts when idle or at the end of a completion
        if( ~cpl_fifo_valid | cpl_fifo_taken )
          cpl_dwords_sent_d      = zero[10:0];         
        else
          cpl_dwords_sent_d      = cpl_dwords_sent_q + cpl_dwords_sent_inc;
    
        cpl_dwords_not_sent = cpl_s0_req_dcount - cpl_dwords_sent_q;

        cpl_dcount = {3'b000, cpl_wdata_length[9:2]}; 

        // calculate cpl_lower_address & cpl_byte_count - see "PCI Express System Architecture" pg 187
        // note: only the first case is expected, but handle correctly anyway
        cpl_lower_addr[6:2] = cpl_s0_req_addr[6:2];
        if( cpl_s0_req_first_be[0] )
          begin
             cpl_bytes_first      = 11'd4;
             cpl_lower_addr[1:0]  = 2'b00;
          end
        else if( cpl_s0_req_first_be[1] )
          begin
             cpl_bytes_first      = 11'd3;
             cpl_lower_addr[1:0]  = 2'b01;
          end             
        else if( cpl_s0_req_first_be[2] )
          begin
             cpl_bytes_first      = 11'd2;
             cpl_lower_addr[1:0]  = 2'b10;
          end         
        else if(cpl_s0_req_first_be[3] )
          begin
             cpl_bytes_first      = 11'd1;
             cpl_lower_addr[1:0]  = 2'b11;
          end        
        else         
          begin
             cpl_bytes_first      = 11'd0;
             cpl_lower_addr[1:0]  = 2'b00;
          end     
      
        if( cpl_dwords_sent_q != zero[11:0] )
          begin
             cpl_lower_addr[1:0] = 2'b00;
          end

        
        if( cpl_s0_req_last_be[3] )
          begin
             cpl_bytes_last      = 11'd4;            
          end
        else if( cpl_s0_req_last_be[2] )
          begin
             cpl_bytes_last      = 11'd3;           
          end             
        else if( cpl_s0_req_last_be[1] )
          begin
             cpl_bytes_last      = 11'd2;           
          end         
        else if(cpl_s0_req_last_be[0] )
          begin
             cpl_bytes_last      = 11'd1;           
          end        
        else         
          begin
             cpl_bytes_last      = 11'd0;           
          end     

        cpl_bytes_total = {cpl_s0_req_dcount, 2'b00} - 11'd8 + cpl_bytes_first + cpl_bytes_last;

        cpl_byte_count = cpl_bytes_total - {cpl_dwords_sent_q, 2'b00};
        
        cpl_s0_hdr = { cpl_s0_req_addr_type, 
                       cpl_s0_req_attr, 
                       cpl_s0_req_tc, 
                       cpl_byte_count,
                       cpl_status,
                       cpl_dcount,
                       cpl_s0_req_tag, 
                       cpl_lower_addr};
     end

   wire           [cpl_hdr_par_width-1:0]   cpl_s0_hdr_par;

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(cpl_hdr_width)
      ) ipgen_cpl_s0_hdr
       (.oddpar(1'b1),.data(cpl_s0_hdr),.datap(cpl_s0_hdr_par)); 

   wire                                     cpl_s0_req_be_par;

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(8)
      ) ipgen_bes 
       (.oddpar(1'b1),.data({cpl_s0_req_last_be, cpl_s0_req_first_be}),.datap(cpl_s0_req_be_par)); 


   // send header or payload to pcie
   // cases:
   // 1) payload from host to nvme, no errors
   // 2) payload from host to nvme with error indication
   // 3) no payload from host due to request error, send UR to nvme
   // 4) payload from host to admin buffer, no errors  (does not go to pcie)
   // 5) payload from host to admin buffer with error indication (does not go to pcie)

   always @*
     begin

        dma_wdata_cpl_ready   = ( ((cpl_s0_ready && (cplsm_q==CPLSM_IDLE || cplsm_q==CPLSM_PAYLD)) ||   // no error - pass pcie ready to wdata
                                   cplsm_q==CPLSM_WAIT ) &&                                             // error    - drop wdata
                                  wdata_is_pcie
                                ) ||                                
                                wdata_is_admin; 

     end

   // gen cntl par   
   wire          cpl_s0_cntl_par;

   nvme_pgen#
     (
      .bits_per_parity_bit(3),
      .width(3)
      ) ipgen_cpl_s0_cntl 
       (.oddpar(1'b1),.data({cpl_s0_first, cpl_s0_last, cpl_s0_discard}),.datap(cpl_s0_cntl_par)); 

   
   always @*
     begin

        case( cplsm_q )                  
          CPLSM_IDLE,CPLSM_HDR:
            begin         
               // header
               cpl_s0_data   = {cpl_s0_cntl_par,~zero[15:cpl_hdr_par_width],cpl_s0_hdr_par,zero[127:cpl_hdr_width], cpl_s0_hdr};
            end          
          CPLSM_PAYLD:
            begin
               // normal data
               cpl_s0_data   = {cpl_s0_cntl_par,cpl_wdata_data};             
            end
          CPLSM_END:
            begin
               // error completion
               // use 2nd cycle DW0 for UR/CA completion descriptor - see xilinx PG156 - ultrascale pcie gen3 Fig 3-35
               cpl_s0_data   = {cpl_s0_cntl_par,~zero[15:1],cpl_s0_req_be_par,zero[127:8],  cpl_s0_req_last_be, cpl_s0_req_first_be};  
            end
          default: 
            begin
               cpl_s0_data[127:0]    = {4{32'hEFBEADDE}}; //pairty is 0101
               cpl_s0_data[143:128]  = {4{4'h5}}; //pairty is 0101
               cpl_s0_data[144]      = cpl_s0_cntl_par;
            end
        endcase
        

        cpl_s0_first    = cpl_wdata_first; 
        cpl_s0_last     = cpl_wdata_last; 
        cpl_s0_discard  = 1'b0;

        cpl_dwords_sent_inc   = 11'd0;

        
        // data transfer from host/sislite wdata interface to pcie
        if( cpl_wdata_valid )
          begin
             
             cpl_s0_valid    =  1'b1;             
             if( cpl_s0_ready & ~cpl_wdata_first)
               begin                                       
                  cpl_dwords_sent_inc = 11'd4;                                                                     
               end
          end
        else
          begin
             cpl_s0_valid    = 1'b0;
          end
     end // always @ *


   
   localparam cpl_s1_width = 3 + 128 + 17;
   reg   [cpl_s1_width-1:0] cpl_s0_din;
   wire  [cpl_s1_width-1:0] cpl_s1_dout;

   nvme_pl_burp#(.width(cpl_s1_width), .stage(1)) cpl_s1
     (.clk(clk),.reset(reset),
      .valid_in(cpl_s0_valid),
      .data_in(cpl_s0_din),
      .ready_out(cpl_s0_ready),
                 
      .data_out(cpl_s1_dout),
      .valid_out(sntl_pcie_cc_valid),
      .ready_in(pcie_sntl_cc_ready)
      ); 

   always @*
     begin
        cpl_s0_din = {cpl_s0_first, cpl_s0_last, cpl_s0_discard, cpl_s0_data };
        {sntl_pcie_cc_first, sntl_pcie_cc_last, sntl_pcie_cc_discard, sntl_pcie_cc_data } = cpl_s1_dout;
     end


   
   // -------------------------------------------------
   // transfer data from NVMe or host to admin buffer
   // note: there's no collision checking.
   // Its up to microcode to only have 1 request outstanding that targets the admin buffer
   always @*
     begin
        dma_admin_valid = pcie_admin_valid;
        dma_admin_addr = pcie_admin_addr;
        dma_admin_data = pcie_admin_data;
        
        dma_admin_req_cpl = 1'b0;
        
        // save request info for admin->host dma request
        admin_valid_d         = admin_valid_q;
        admin_tag_d           = admin_tag_q;
        admin_tag_par_d       = admin_tag_par_q;
        admin_reloff_d        = admin_reloff_q;
        admin_length_d        = admin_length_q;

        if( dma_admin_req_ack )
          begin
             admin_valid_d         = 1'b1;
             admin_tag_d           = admin_dma_req_tag;
             admin_tag_par_d       = admin_dma_req_tag_par;
             admin_reloff_d        = admin_dma_req_reloff;
             admin_length_d        = admin_dma_req_length;
          end

        if( wdata_is_admin  )
          begin
             dma_admin_valid = wdata_dma_cpl_valid;
             dma_admin_addr = admin_reloff_q;
             dma_admin_data = {1'b0,wdata_dma_cpl_data_byte_par,wdata_dma_cpl_data[127:0]};

             if( wdata_dma_cpl_valid & 
                 ~wdata_dma_cpl_first)  // ignore first cycle header used for pcie
               begin                                   
                  if( wdata_dma_cpl_last  )
                    begin
                       dma_admin_req_cpl = 1'b1;
                       admin_valid_d = 1'b0;
                    end                  
                  admin_reloff_d = admin_reloff_q + 16;
               end             
          end                
     end


   always @*
     begin        
        dma_perf_events[0] = cpl_fifo_push;  // DMA read request
        dma_perf_events[1] = cpl_fifo_push & cpl_fifo_req_error[0];  // DMA read request error
        dma_perf_events[2] = cpl_fifo_push & cpl_fifo_req_error[1];  // DMA read request error
        dma_perf_events[3] = cpl_fifo_push & cpl_fifo_req_error[2];  // DMA read request error
        dma_perf_events[4] = s5_valid_q & s5_last_q;
        dma_perf_events[5] = s5_valid_q & s5_last_q & s5_discard_q;
        dma_perf_events[6] = dma_cmd_valid & s0_ready;
        dma_perf_events[7] = dma_cmd_valid & ~s0_ready;
        dma_perf_events[8] = cpl_s0_ready && cplsm_q==CPLSM_HDR; // error response sent
        dma_perf_events[9] = cpl_s0_ready && cpl_s0_valid && cpl_s0_first;
        dma_perf_events[10] = cpl_s0_ready && cpl_s0_valid && ~cpl_s0_first;  
        dma_perf_events[11] = wdata_dma_cpl_valid & wdata_dma_cpl_first & wdata_dma_cpl_error & wdata_dma_cpl_end;
        dma_perf_events[15:12] = zero[15:12];   
     end   

   
endmodule


