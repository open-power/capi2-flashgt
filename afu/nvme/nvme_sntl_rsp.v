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
//  File : nvme_sntl_rsp.v
//  *************************************************************************
//  *************************************************************************
//  Description : Data & Command response interface to sislite
//                store & forward fifo
//                hold FCP_DATA & FCP_RSP results until CRC check
//                discard FCP_DATA on error
//  *************************************************************************

module nvme_sntl_rsp#
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
    parameter tag_par_width   = (tag_width + 63)/64, 
    parameter lunid_par_width = (lunid_width + 63)/64, 
    parameter data_par_width  = (data_width + 7) / 8,
    parameter data_fc_par_width  = data_par_width/8,
    parameter status_width    = 8 // event status
    )
   (
    input                              reset,
    input                              clk,

   

    // ---------------------------------------------------------
    // command response interface - valid/ack
    // ---------------------------------------------------------
    input                              cmd_rsp_v, // valid - covers cmd_rsp_info/cmd_rsp_e
    input              [tag_width-1:0] cmd_rsp_tag,
    input                              cmd_rsp_tag_par,
    input           [fcstat_width-1:0] cmd_rsp_fc_status,
    input          [fcxstat_width-1:0] cmd_rsp_fcx_status,
    input                        [7:0] cmd_rsp_scsi_status, 
    input                              cmd_rsp_underrun,
    input                              cmd_rsp_overrun,
    input                       [31:0] cmd_rsp_resid,
    input                              cmd_rsp_sns_valid,
    input                              cmd_rsp_fcp_valid,
    input         [rsp_info_width-1:0] cmd_rsp_info,
    input           [beatid_width-1:0] cmd_rsp_beats, 
    output reg                         rsp_cmd_ack,

    // ---------------------------------------------------------
    // dma header & payload interface - valid/pause
    // ---------------------------------------------------------
    input                              dma_rsp_valid,
    output reg                         rsp_dma_pause, // backpressure on TLP (128B) boundary
    input          [datalen_width-1:0] dma_rsp_reloff, // byte offset from start of payload
    input                        [9:0] dma_rsp_length, // length of this packet in bytes (max 128)
    input              [tag_width-1:0] dma_rsp_tag, // sislite interface tag
    input                              dma_rsp_tag_par, // sislite interface tag parity added kch 
    input             [data_width-1:0] dma_rsp_data, // payload data
    input      [data_fc_par_width-1:0] dma_rsp_data_par, // payload data par added kch 
    input                              dma_rsp_first, // asserted with first cycle
    input                              dma_rsp_last, // asserted with last cycle 

    // ---------------------------------------------------------
    // admin payload ready inteface - valid/ack
    // ---------------------------------------------------------
    input                              admin_rsp_req_valid, // asserted when admin_rsp_req_* is valid.  held until rsp_admin_req_ack
    output reg                         rsp_admin_req_ack, // asserted when req is taken
    input              [tag_width-1:0] admin_rsp_req_tag, // sislite interface tag
    input                              admin_rsp_req_tag_par, // sislite interface tag
    input          [datalen_width-1:0] admin_rsp_req_reloff, // byte offset from start of payload
    input                       [12:0] admin_rsp_req_length, // payload length in bytes (4KB max)

    // ---------------------------------------------------------
    // admin payload interface - valid/ready
    // ---------------------------------------------------------
    input                              admin_rsp_valid, 
    input             [data_width-1:0] admin_rsp_data, // payload data
    input      [data_fc_par_width-1:0] admin_rsp_data_par, // payload data
    input                              admin_rsp_last, // indicates last data cycle (should be consistent with admin_rsp_req_length)
    output reg                         rsp_admin_ready, // indicates data was taken this cycle
    
    // ---------------------------------------------------------
    // sislite read data response interface
    // ---------------------------------------------------------
    output reg                         o_rdata_rsp_v_out,
    input                              o_rdata_rsp_r_in,
    output reg                         o_rdata_rsp_e_out,
    output reg       [bytec_width-1:0] o_rdata_rsp_c_out,
    output reg      [beatid_width-1:0] o_rdata_rsp_beat_out,
    output reg         [tag_width-1:0] o_rdata_rsp_tag_out,
    output reg                         o_rdata_rsp_tag_par_out,
    output reg        [data_width-1:0] o_rdata_rsp_data_out,
    output reg [data_fc_par_width-1:0] o_rdata_rsp_data_par_out, // added kch 
    

    // ---------------------------------------------------------
    // sislite command response interface
    // ---------------------------------------------------------
    // rsp_v         - when asserted, rsp_* fields are valid
    // rsp_sns_valid - when asserted with rsp_v, rsp_info is the first word of sense data
    //                 may be asserted up to 4 additional cycles with additional sense data on rsp_info
    // rsp_fcp_valid - when asserted with rsp_v, rsp_info is the first word of FCP_RSP_INFO (task management)
    //                 may be asserted one additional cycle with the 2nd word of FCP_RSP_INFO
    //                 if asserted, rsp_sns_valid must be zero
    // 
    output reg                         o_rsp_v_out,
    output reg         [tag_width-1:0] o_rsp_tag_out,
    output reg                         o_rsp_tag_par_out,
    output reg      [fcstat_width-1:0] o_rsp_fc_status_out,
    output reg     [fcxstat_width-1:0] o_rsp_fcx_status_out,
    output reg                   [7:0] o_rsp_scsi_status_out,
    output reg                         o_rsp_sns_valid_out,
    output reg                         o_rsp_fcp_valid_out,
    output reg                         o_rsp_underrun_out,
    output reg                         o_rsp_overrun_out,
    output reg                  [31:0] o_rsp_resid_out,
    output reg      [beatid_width-1:0] o_rsp_rdata_beats_out,
    output reg    [rsp_info_width-1:0] o_rsp_info_out,

    // ---------------------------------------------------------
    // debug
    // ---------------------------------------------------------    
    output reg                         sntl_regs_rdata_paused,
    output reg                         sntl_regs_rsp_cnt,
    input                              regs_xx_freeze,
    output                             rsp_perror_ind,
    input                              regs_sntl_rsp_debug,
    // ----------------------------------------------------------
    // parity error inject 
    // ----------------------------------------------------------
    input                              regs_sntl_pe_errinj_valid,
    input                       [15:0] regs_xxx_pe_errinj_decode, 
    input                              regs_wdata_pe_errinj_1cycle_valid 
    );

`include "nvme_func.svh"


   
   // ---------------------------------------------------------
   // Receive data or response status 
   // ---------------------------------------------------------

   // cmd_rsp_v            - 1 cycle response status.  no data payload for this interface
   // admin_rsp_req_valid  - 1 cycle indicating admin payload is ready.  data payload uses a separate interface.
   // dma_rsp_valid        - 1-8 cycles of payload.  push to hdrff on last cycle.  backpressure on frame (128B) boundary

   // ---------------------------------------------------------
   // header fifo is used for keeping responses in order with payload
   // sislite interface requires that payload is complete before sending status

   localparam hdrff_cmd_width = 4 + 1 + 1+ tag_width + fcstat_width + fcxstat_width + 8 + 1 + 1 + 32 + 1 + 1 + rsp_info_width + beatid_width;  // added +1 for tag_parity kch 
   localparam hdrff_adm_width = 4 + 1 + tag_width + datalen_width + 13;   // added +1 for tag parity kch 
   localparam hdrff_dma_width = 4 + 1+ tag_width + datalen_width + 10;   // added +1 for tag_parity 
   localparam hdrff_tmp_width = (hdrff_dma_width > hdrff_adm_width) ? hdrff_dma_width : hdrff_adm_width;
   localparam hdrff_width = (hdrff_tmp_width > hdrff_cmd_width) ? hdrff_tmp_width : hdrff_cmd_width;
   localparam hdrff_par_width = (hdrff_width + 63)/64;
   localparam hdrff_total_width = hdrff_par_width + hdrff_width;

   // encode for type of header
   localparam [3:0] HDRFF_T_CMD = 4'h1;
   localparam [3:0] HDRFF_T_ADM = 4'h2;
   localparam [3:0] HDRFF_T_DMA = 4'h4;

// set/reset/ latch for parity errors kch 

    wire              s1_perror;
    wire              rsp_perror_int;

    nvme_srlat#
    (.width(1))  rsp_sr   
    (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(rsp_perror_int));

    assign rsp_perror_ind = rsp_perror_int;

   
   reg                              hdrff_push;   
   reg            [hdrff_width-1:0] hdrff_wdata;
   reg                              hdrff_flush;
   
   wire                             hdrff_valid;
   reg                              hdrff_pop;
   wire           [hdrff_width-1:0] hdrff_rdata;
   wire                             hdrff_almost_full;
   wire                             hdrff_full;

   // lets just put parity on the array also kch 

   wire       [hdrff_par_width-1:0] hdrff_wdata_par;
   wire       [hdrff_par_width-1:0] hdrff_rdata_par;

   nvme_pgen#
     (
      .bits_per_parity_bit(64),
      .width(hdrff_width)
      ) ipgen_hdrff_wdata 
       (.oddpar(1'b1),.data(hdrff_wdata[hdrff_width-1:0]),.datap(hdrff_wdata_par)); 
   

   
   nvme_fifo#(
              .width(hdrff_total_width), 
              .words(64),
              .almost_full_thresh(6)  // allow at least 1 current + 1 new dma_rsp_* packet 
              ) hdrff
     (.clk(clk), .reset(reset), 
      .flush(       hdrff_flush ),
      .push(        hdrff_push  ),
      .din(         {hdrff_wdata_par,hdrff_wdata} ),
      .dval(        hdrff_valid ), 
      .pop(         hdrff_pop   ),
      .dout(        {hdrff_rdata_par, hdrff_rdata} ),
      .full(        hdrff_full  ), 
      .almost_full( hdrff_almost_full ), 
      .used());


   reg                              rsp_pe_inj_d,rsp_pe_inj_q;
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin
             rsp_pe_inj_q <= 1'b0;
          end
        else
          begin
             rsp_pe_inj_q <= rsp_pe_inj_d;
          end
     end

   always @*
     begin       
        rsp_pe_inj_d = rsp_pe_inj_q;
        if (regs_wdata_pe_errinj_1cycle_valid & regs_sntl_pe_errinj_valid & regs_xxx_pe_errinj_decode[11:8] == 4'h3)
          begin
             rsp_pe_inj_d  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
          end 
        if (rsp_pe_inj_q & hdrff_valid)
          rsp_pe_inj_d = 1'b0; 
     end  
   // check fifo parity kch fixit

   nvme_pcheck#
     (
      .bits_per_parity_bit(64),
      .width(hdrff_width)
      ) ipcheck_hdrff_rdata
       (.oddpar(1'b1),.data({hdrff_rdata[hdrff_width-1:1],(hdrff_rdata[0]^rsp_pe_inj_q)}),.datap(hdrff_rdata_par),.check(hdrff_valid),.parerr(s1_perror)); 


   always @*
     begin
        hdrff_push         = 1'b0;
        hdrff_wdata        = zero[hdrff_width-1:0];
        hdrff_flush        = 1'b0;
        rsp_admin_req_ack  = 1'b0;
        rsp_cmd_ack        = 1'b0;
        
        // arbitration for pushing to header fifo
        if( dma_rsp_valid & dma_rsp_last )
          begin
             hdrff_wdata[hdrff_dma_width-1:0] = {dma_rsp_length, dma_rsp_reloff, dma_rsp_tag_par, dma_rsp_tag,  HDRFF_T_DMA};
             hdrff_push = 1'b1;
          end
        else if( ~hdrff_almost_full )
          begin
             if( admin_rsp_req_valid )
               begin
                  hdrff_wdata[hdrff_adm_width-1:0] = {admin_rsp_req_length, admin_rsp_req_reloff, admin_rsp_req_tag_par, admin_rsp_req_tag,  HDRFF_T_ADM};
                  hdrff_push = 1'b1;
                  rsp_admin_req_ack = 1'b1;
               end
             else if( cmd_rsp_v )
               begin                  
                  hdrff_wdata[hdrff_cmd_width-1:0] = { cmd_rsp_fc_status, cmd_rsp_fcx_status, cmd_rsp_scsi_status,  
                                                       cmd_rsp_underrun, cmd_rsp_overrun, cmd_rsp_resid, cmd_rsp_sns_valid,
                                                       cmd_rsp_fcp_valid, cmd_rsp_info, cmd_rsp_beats, cmd_rsp_tag_par ,  cmd_rsp_tag, HDRFF_T_CMD};
                  hdrff_push = 1'b1;
                  rsp_cmd_ack = 1'b1;                                                    
               end
          end        
     end

   // ---------------------------------------------------------
   // payload fifo

   localparam payldff_width = data_fc_par_width + data_width + 2;
   localparam payldff_size  = 1024 * 8;  // size in bytes = 8KB
   localparam payldff_words = payldff_size / (data_width/8);  // size in beats
   localparam payldff_threshold = (128/(data_width/8)) * 6;  // backpressure when there's room for 3 256B packets
   
   reg                              payldff_push;   
   reg          [payldff_width-1:0] payldff_wdata;
   reg                              payldff_flush;
   
   wire                             payldff_valid;
   reg                              payldff_pop;
   wire         [payldff_width-1:0] payldff_rdata;
   wire                             payldff_almost_full;
   wire                             payldff_full;
   
   nvme_fifo#(
              .width(payldff_width), 
              .words(payldff_words),
              .almost_full_thresh(payldff_threshold)
              ) payldff
     (.clk(clk), .reset(reset), 
      .flush(       payldff_flush ),
      .push(        payldff_push  ),
      .din(         payldff_wdata ),
      .dval(        payldff_valid ), 
      .pop(         payldff_pop   ),
      .dout(        payldff_rdata ),
      .full(        payldff_full  ), 
      .almost_full( payldff_almost_full ), 
      .used());

   always @*
     begin
        payldff_flush = 1'b0;
        payldff_push = dma_rsp_valid;
        payldff_wdata = {dma_rsp_first, dma_rsp_last, dma_rsp_data_par, dma_rsp_data};
     end
   
   
   // ---------------------------------------------------------
   // read from header fifo
   // ---------------------------------------------------------

   reg [3:0] s1_state_q;
   reg [3:0] s1_state_d;
   localparam ST_IDLE   = 4'h1;
   localparam ST_DMA    = 4'h2;
   localparam ST_ADM    = 4'h3;
   localparam ST_END    = 4'h4;
   localparam ST_ADMEND = 4'h5;
   
   reg  [datalen_width-1:0] s0_dma_reloff;
   reg                [9:0] s0_dma_length;
   reg      [tag_width-1:0] s0_dma_tag;
   
   reg  [datalen_width-1:0] s0_adm_reloff;
   reg               [12:0] s0_adm_length;
   reg      [tag_width-1:0] s0_adm_tag;
   
   reg                [3:0] s0_hdr_type;

   reg                      s1_cmd_v_q, s1_cmd_v_d;
   reg      [tag_width-1:0] s1_cmd_tag_q, s1_cmd_tag_d;
   reg                      s1_cmd_tag_par_q, s1_cmd_tag_par_d;
   reg   [fcstat_width-1:0] s1_cmd_fc_status_q, s1_cmd_fc_status_d;
   reg  [fcxstat_width-1:0] s1_cmd_fcx_status_q, s1_cmd_fcx_status_d;
   reg                [7:0] s1_cmd_scsi_status_q, s1_cmd_scsi_status_d; 
   reg                      s1_cmd_underrun_q, s1_cmd_underrun_d;
   reg                      s1_cmd_overrun_q, s1_cmd_overrun_d;
   reg               [31:0] s1_cmd_resid_q, s1_cmd_resid_d;
   reg                      s1_cmd_sns_valid_q, s1_cmd_sns_valid_d;
   reg                      s1_cmd_fcp_valid_q, s1_cmd_fcp_valid_d;
   reg [rsp_info_width-1:0] s1_cmd_info_q, s1_cmd_info_d;
   reg   [beatid_width-1:0] s1_cmd_beats_q, s1_cmd_beats_d; 


   reg                      s1_payld_valid_q, s1_payld_valid_d;
   reg                      s1_admin_valid_q;
   reg                      s1_admin_valid_d;
   reg  [datalen_width-1:0] s1_reloff_q, s1_reloff_d;
   reg               [12:0] s1_length_q, s1_length_d;
   reg   [beatid_width-1:0] s1_beat_q;
   reg      [tag_width-1:0] s1_tag_q;
   reg                      s1_tag_par_q;
   reg   [beatid_width-1:0] s1_beat_d;
   reg      [tag_width-1:0] s1_tag_d;
   reg                      s1_tag_par_d;

   reg                      s1_payld_continue_q, s1_payld_continue_d;

   reg                      s1_ready, s1_taken;

   reg                      rdata_paused_q, rdata_paused_d;
   
   // parity gen kch 
   reg                      s0_dma_tag_par;
   reg                      s0_adm_tag_par;

   //   nvme_pgen#
   //  (
   //   .bits_per_parity_bit(8),
   //   .width(8)
   //  ) ipgen_s0_dma_tag 
   //  (.oddpar(1'b1),.data(s0_dma_tag),.datap(s0_dma_tag_par)); 
   
   //   nvme_pgen#
   //  (
   //   .bits_per_parity_bit(8),
   //   .width(8)
   //  ) ipgen_s0_adm_tag 
   //  (.oddpar(1'b1),.data(s0_adm_tag),.datap(s0_adm_tag_par)); 
   
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin
             s1_state_q           <= ST_IDLE;
             s1_cmd_v_q           <= 1'b0;         
             s1_cmd_tag_q         <= zero[tag_width-1:0];
             s1_cmd_tag_par_q     <= 1'b1;
             s1_cmd_fc_status_q   <= zero[fcstat_width-1:0];
             s1_cmd_fcx_status_q  <= zero[fcxstat_width-1:0];
             s1_cmd_scsi_status_q <= zero[7:0];
             s1_cmd_sns_valid_q   <= 1'b0;
             s1_cmd_fcp_valid_q   <= 1'b0;
             s1_cmd_underrun_q    <= 1'b0;
             s1_cmd_overrun_q     <= 1'b0;
             s1_cmd_resid_q       <= zero[31:0];
             s1_cmd_beats_q       <= zero[beatid_width-1:0];
             s1_cmd_info_q        <= zero[rsp_info_width-1:0];
             s1_payld_valid_q     <= 1'b0;
             s1_admin_valid_q     <= 1'b0;
             s1_reloff_q          <= zero[datalen_width-1:0];
             s1_beat_q            <= zero[beatid_width-1:0];
             s1_length_q          <= zero[13:0];
             s1_tag_q             <= zero[tag_width-1:0];
             s1_tag_par_q         <= 1'b1; 
             s1_payld_continue_q  <= 1'b0;
             rdata_paused_q       <= 1'b0;
          end
        else
          begin
             s1_state_q           <= s1_state_d;
             s1_cmd_v_q           <= s1_cmd_v_d;
             s1_cmd_tag_q         <= s1_cmd_tag_d;
             s1_cmd_tag_par_q     <= s1_cmd_tag_par_d;
             s1_cmd_fc_status_q   <= s1_cmd_fc_status_d;
             s1_cmd_fcx_status_q  <= s1_cmd_fcx_status_d;
             s1_cmd_scsi_status_q <= s1_cmd_scsi_status_d;
             s1_cmd_sns_valid_q   <= s1_cmd_sns_valid_d;
             s1_cmd_fcp_valid_q   <= s1_cmd_fcp_valid_d;
             s1_cmd_underrun_q    <= s1_cmd_underrun_d;
             s1_cmd_overrun_q     <= s1_cmd_overrun_d;
             s1_cmd_resid_q       <= s1_cmd_resid_d;
             s1_cmd_beats_q       <= s1_cmd_beats_d;
             s1_cmd_info_q        <= s1_cmd_info_d;              
             s1_payld_valid_q     <= s1_payld_valid_d;
             s1_admin_valid_q     <= s1_admin_valid_d;
             s1_reloff_q          <= s1_reloff_d;
             s1_beat_q            <= s1_beat_d;
             s1_length_q          <= s1_length_d;
             s1_tag_q             <= s1_tag_d;
             s1_tag_par_q         <= s1_tag_par_d;
             s1_payld_continue_q  <= s1_payld_continue_d;
             rdata_paused_q       <= rdata_paused_d;
          end
     end

   reg s0_dma_valid;
   always @*
     begin
        hdrff_pop = 1'b0;
        

        // unpack hdr fifo output
        s0_hdr_type = hdrff_rdata[3:0];
        {s0_dma_length, s0_dma_reloff, s0_dma_tag_par,  s0_dma_tag} = hdrff_rdata[hdrff_dma_width-1:4];
        {s0_adm_length, s0_adm_reloff, s0_adm_tag_par,  s0_adm_tag} = hdrff_rdata[hdrff_adm_width-1:4];

        s0_dma_valid = 1'b0;

        {s1_cmd_fc_status_d, s1_cmd_fcx_status_d, s1_cmd_scsi_status_d,  
          s1_cmd_underrun_d, s1_cmd_overrun_d, s1_cmd_resid_d, s1_cmd_sns_valid_d,
          s1_cmd_fcp_valid_d, s1_cmd_info_d, s1_cmd_beats_d,  s1_cmd_tag_par_d, s1_cmd_tag_d}  
                          = hdrff_rdata[hdrff_cmd_width-1:4];

        
        s1_cmd_v_d        = 1'b0; 

        s1_payld_valid_d  = s1_payld_valid_q & ~s1_taken;
        s1_admin_valid_d  = s1_admin_valid_q & ~s1_taken;
        s1_reloff_d       = s1_reloff_q;
        s1_length_d       = s1_length_q;
        s1_tag_d          = s1_tag_q;
        s1_tag_par_d      = s1_tag_par_q;
      
        if( hdrff_valid & ~regs_xx_freeze )
          begin
             if( s0_hdr_type == HDRFF_T_CMD )
               begin
                  // assert response valid to sislite at most every other cycle.  1 cycle pulse, no backpressure                  
                  if( ~s1_cmd_v_q && 
                      s1_state_q==ST_IDLE )  // wait for payload to be idle so response can't pass its payload
                    begin
                       hdrff_pop = 1'b1;
                       s1_cmd_v_d = 1'b1; 
                    end
               end
             else if( s0_hdr_type == HDRFF_T_DMA )
               begin
                  s0_dma_valid = 1'b1;
                  if( s1_ready )
                    begin
                       hdrff_pop         = 1'b1;
                       s1_payld_valid_d  = 1'b1;  // debug: drop I/O read payload for performance check
                       s1_reloff_d       = s0_dma_reloff;
                       s1_length_d       = s0_dma_length;
                       s1_tag_d          = s0_dma_tag;
                       s1_tag_par_d      = s0_dma_tag_par;
                    end
               end
             else if( s0_hdr_type == HDRFF_T_ADM )
               begin
                  if( s1_ready )
                    begin
                       hdrff_pop         = 1'b1;
                       s1_admin_valid_d  = 1'b1;
                       s1_reloff_d       = s0_adm_reloff;
                       s1_length_d       = s0_adm_length;
                       s1_tag_d          = s0_adm_tag;
                       s1_tag_par_d      = s0_adm_tag_par;
                    end
               end
             else
               begin
                  // todo: error
               end
          end
     end // always @ *

   reg s1_first;
   reg s1_last;
   reg [beatid_width-1:0] s1_firstbeat;
   reg  [bytec_width-1:0] s1_last_bytec;

   always @*
     begin
        rsp_dma_pause             = hdrff_almost_full | payldff_almost_full;

        s1_taken                  = 1'b0;
        s1_ready                  = ~(s1_payld_valid_q | s1_admin_valid_q);
                
        o_rdata_rsp_v_out         = 1'b0;  
        o_rdata_rsp_e_out         = 1'b0;
        o_rdata_rsp_c_out         = { 1'b1, zero[bytec_width-2:0] };  // number of bytes valid this cycle = data_width/8
        o_rdata_rsp_beat_out      = s1_beat_q[beatid_width-1:0];
        o_rdata_rsp_tag_out       = s1_tag_q[tag_width-1:0];
        o_rdata_rsp_tag_par_out   = s1_tag_par_q;
        {s1_first, s1_last}       = payldff_rdata[data_width+data_fc_par_width+1:data_width+data_fc_par_width];
        o_rdata_rsp_data_out      = byteswap128(payldff_rdata[127:0]);
        o_rdata_rsp_data_par_out  = {payldff_rdata[128],payldff_rdata[129]};  // added kch 

        s1_beat_d = s1_beat_q;
        s1_state_d = s1_state_q;

        // continue without "end" cycle if next dma payload has the same tag and relative offset is sequential
        s1_payld_continue_d = s0_dma_valid &&
                              s0_dma_tag == s1_tag_q &&
                              s0_dma_reloff == (s1_reloff_q+s1_length_q);
        
        s1_firstbeat = s1_reloff_q[datalen_width-1:datalen_width-beatid_width];
        if( s1_length_q[bytec_width-2:0] == zero[bytec_width-2:0])
          begin
             s1_last_bytec = {1'b1, s1_length_q[bytec_width-2:0]};
          end
        else
          begin
             s1_last_bytec = {1'b0, s1_length_q[bytec_width-2:0]};
          end

        payldff_pop = 1'b0;
        rsp_admin_ready  = 1'b0;
        
        case( s1_state_q )
          ST_IDLE:
            begin
               o_rdata_rsp_beat_out  = s1_firstbeat;
               s1_beat_d             = s1_firstbeat;

               
               if( s1_payld_valid_q )
                 begin
                    o_rdata_rsp_v_out = payldff_valid & ~regs_sntl_rsp_debug;
                    if( s1_last )
                      begin                              
                         o_rdata_rsp_c_out = s1_last_bytec;
                      end
                    if( o_rdata_rsp_r_in | regs_sntl_rsp_debug )
                      begin
                         // todo: check length vs last for consistency
                         if( s1_last )
                           begin                            
                              s1_state_d = ST_END;
                           end
                         else
                           begin
                              s1_state_d = ST_DMA;
                           end
                         payldff_pop  = 1'b1;
                         s1_beat_d    = s1_firstbeat + one[beatid_width-1:0];
                      end
                 end

               if( s1_admin_valid_q )
                 begin
                    o_rdata_rsp_v_out         = admin_rsp_valid;
                    o_rdata_rsp_data_out      = byteswap128(admin_rsp_data);
                    o_rdata_rsp_data_par_out  = {admin_rsp_data_par[0],admin_rsp_data_par[1]};
                    if( admin_rsp_last )
                      begin                              
                         o_rdata_rsp_c_out = s1_last_bytec;
                      end
                    if( o_rdata_rsp_r_in )
                      begin
                         // todo: check length vs last for consistency
                         if( admin_rsp_last )
                           begin                            
                              s1_state_d = ST_ADMEND;
                           end
                         else
                           begin
                              s1_state_d = ST_ADM;
                           end
                         rsp_admin_ready  = 1'b1;
                         s1_beat_d    = s1_firstbeat + one[beatid_width-1:0];
                      end
                 end
              
            end

          ST_END:
            begin
               // after last cycle of data, assert end indicator
               // data is not valid on this cycle
               o_rdata_rsp_v_out =  ~regs_sntl_rsp_debug;
               if( o_rdata_rsp_r_in  | regs_sntl_rsp_debug)
                 begin
                    o_rdata_rsp_e_out  = 1'b1;
                    s1_state_d         = ST_IDLE;
                    s1_taken           = 1'b1;                  
                 end
            end

          ST_DMA:
            begin
               if( s1_last )
                 begin                              
                    o_rdata_rsp_c_out = s1_last_bytec;
                 end
               
               o_rdata_rsp_v_out = payldff_valid & ~regs_sntl_rsp_debug;
               if( o_rdata_rsp_r_in  | regs_sntl_rsp_debug)
                 begin
                    // todo: check length vs last for consistency
                    if( s1_last )
                      begin
                         if( s1_payld_continue_q )
                           begin
                              // next 128B is sequential with current 128 - continue without asserting end
                              s1_state_d  = ST_IDLE;
                              s1_taken    = 1'b1;
                           end
                         else
                           begin
                              s1_state_d = ST_END;
                           end                         
                      end
                    payldff_pop  = 1'b1;
                    s1_beat_d    = s1_beat_q + one[beatid_width-1:0];                    
                 end
            end

          ST_ADM:
            begin
               o_rdata_rsp_data_out      = byteswap128(admin_rsp_data);
               o_rdata_rsp_data_par_out  = {admin_rsp_data_par[0],admin_rsp_data_par[1]};
               
               if( admin_rsp_last )
                 begin                              
                    o_rdata_rsp_c_out    = s1_last_bytec;
                 end
               
               o_rdata_rsp_v_out = admin_rsp_valid;
               if( o_rdata_rsp_r_in )
                 begin
                    // todo: check length vs last for consistency
                    if( admin_rsp_last )
                      begin                            
                         s1_state_d = ST_ADMEND;
                      end
                    rsp_admin_ready  = 1'b1;
                    s1_beat_d    = s1_beat_q + one[beatid_width-1:0];                    
                 end
            end
                

          ST_ADMEND:
            begin
               // after last cycle of data, assert end indicator
               // data is not valid on this cycle
               o_rdata_rsp_v_out =  1'b1;
               if( o_rdata_rsp_r_in )
                 begin
                    o_rdata_rsp_e_out  = 1'b1;
                    s1_state_d         = ST_IDLE;
                    s1_taken           = 1'b1;                  
                 end
            end
    
          default:
            begin
               s1_state_d = ST_IDLE;
            end
        endcase // case ( s1_state_q )
      
        // debug
        rdata_paused_d         = o_rdata_rsp_v_out & ~o_rdata_rsp_r_in;
        sntl_regs_rdata_paused = rdata_paused_q;
     end

 
   always @*
     begin
        o_rsp_v_out            = s1_cmd_v_q;
        o_rsp_tag_out          = s1_cmd_tag_q;
        o_rsp_tag_par_out      = s1_cmd_tag_par_q;
        o_rsp_fc_status_out    = s1_cmd_fc_status_q;
        o_rsp_fcx_status_out   = s1_cmd_fcx_status_q;
        o_rsp_scsi_status_out  = s1_cmd_scsi_status_q;
        o_rsp_sns_valid_out    = s1_cmd_sns_valid_q;
        o_rsp_fcp_valid_out    = s1_cmd_fcp_valid_q;
        o_rsp_underrun_out     = s1_cmd_underrun_q;
        o_rsp_overrun_out      = s1_cmd_overrun_q;
        o_rsp_resid_out        = s1_cmd_resid_q;
        o_rsp_rdata_beats_out  = s1_cmd_beats_q;
        o_rsp_info_out         = s1_cmd_info_q;

        sntl_regs_rsp_cnt      = s1_cmd_v_q;
        if( o_rsp_v_out )
          $display("%t %m rsp tag %02x",$time,s1_cmd_tag_q);
     end

endmodule 
