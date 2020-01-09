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
//  File : nvme_sntl_wdata.v
//  *************************************************************************
//  *************************************************************************
//  Description : sislite write command payload
//
//  sends request for up to 4KB to sislite afu
//  responses are returned in order
//  buffer up responses into 128B packets before returning to nvme
//
//  *************************************************************************

module nvme_sntl_wdata#
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
   parameter tag_par_width   = (tag_width + 64)/64, 
   parameter lunid_par_width = (lunid_width + 63)/64, 
   parameter data_par_width  = (data_width + 7) / 8,
   parameter data_fc_par_width = data_par_width/8,
   parameter status_width    = 8, // event status
   parameter wdata_max_req   = 4096,
   parameter wdatalen_width  = $clog2(wdata_max_req)+1,   
   parameter wdatalen_par_width  = (wdatalen_width+63)/64 ,   
   parameter wbuf_numids     = 6,  // 4KB per id
   parameter wbufid_width    = $clog2(wbuf_numids),
   parameter wbufid_par_width = (wbufid_width + 7)/8
    )
   (
    input                              reset,
    input                              clk,

    // ----------------------------------------------------
    // sislite write data request interface
    // ----------------------------------------------------
    (* mark_debug = "false" *)
    output reg                         o_wdata_req_v_out,
    (* mark_debug = "false" *)
    input                              o_wdata_req_r_in,
    (* mark_debug = "false" *)
    output reg         [tag_width-1:0] o_wdata_req_tag_out,
    (* mark_debug = "false" *)
    output reg                         o_wdata_req_tag_par_out, 
    (* mark_debug = "false" *)
    output reg      [beatid_width-1:0] o_wdata_req_beat_out,
    (* mark_debug = "false" *)
    output reg     [datalen_width-1:0] o_wdata_req_size_out,
    (* mark_debug = "false" *)
    output reg                         o_wdata_req_size_par_out, 

    // ----------------------------------------------------
    // data response interface (writes).  
    // ----------------------------------------------------
    (* mark_debug = "false" *)
    input                              i_wdata_rsp_v_in,
    (* mark_debug = "false" *)
    output                             i_wdata_rsp_r_out,
    (* mark_debug = "false" *)
    input                              i_wdata_rsp_e_in,
    (* mark_debug = "false" *)
    input                              i_wdata_rsp_error_in,
    (* mark_debug = "false" *)
    input              [tag_width-1:0] i_wdata_rsp_tag_in,
    (* mark_debug = "false" *)
    input                              i_wdata_rsp_tag_par_in,
    input           [beatid_width-1:0] i_wdata_rsp_beat_in,
    input             [data_width-1:0] i_wdata_rsp_data_in,
    input      [data_fc_par_width-1:0] i_wdata_rsp_data_par_in,
    // ----------------------------------------------------
    // sislite write (DMA read to host)
    // ----------------------------------------------------

    (* mark_debug = "false" *)
    input                              dma_wdata_req_valid,
    (* mark_debug = "false" *)
    input              [tag_width-1:0] dma_wdata_req_tag, // afu req tag
    (* mark_debug = "false" *)
    input                              dma_wdata_req_tag_par, // afu req tag par
    (* mark_debug = "false" *)
    input          [datalen_width-1:0] dma_wdata_req_reloff, // offset from start address of this command
    (* mark_debug = "false" *)
    input         [wdatalen_width-1:0] dma_wdata_req_length, // number of bytes to request, max 4KB
    input                              dma_wdata_req_length_par,
    (* mark_debug = "false" *)
    output reg                         wdata_dma_req_pause, // backpressure
  

    // ----------------------------------------------------
    // sislite write data response from host
    // ----------------------------------------------------
   
    (* mark_debug = "false" *)
    output reg                         wdata_dma_cpl_valid,
    (* mark_debug = "false" *)
    output reg         [tag_width-1:0] wdata_dma_cpl_tag,
    (* mark_debug = "false" *)
    output reg                         wdata_dma_cpl_tag_par,
    (* mark_debug = "false" *)
    output reg     [datalen_width-1:0] wdata_dma_cpl_reloff, // starting offset in bytes of the first beat
    (* mark_debug = "false" *)
    output reg                   [9:0] wdata_dma_cpl_length, // number of bytes 128B max
    output reg                 [129:0] wdata_dma_cpl_data, // payload data  
    (* mark_debug = "false" *)
    output reg                         wdata_dma_cpl_first, // header cycle for this packet - data not valid
    (* mark_debug = "false" *)
    output reg                         wdata_dma_cpl_last, // last beat of this packet
    (* mark_debug = "false" *)
    output reg                         wdata_dma_cpl_error, // error was returned by afu
    (* mark_debug = "false" *)
    output reg                         wdata_dma_cpl_end, // indicates final packet for this tag
    (* mark_debug = "false" *)
    input                              dma_wdata_cpl_ready,


    // ----------------------------------------------------
    // write buffer request (DMA read to host)
    // ----------------------------------------------------   
    input                              wbuf_wdata_req_valid, 
    input              [tag_width-1:0] wbuf_wdata_req_tag, //    afu req tag  
    input          [tag_par_width-1:0] wbuf_wdata_req_tag_par, //    
    input          [datalen_width-1:0] wbuf_wdata_req_reloff, // offset from start address of this command  
    // input      [datalen_par_width-1:0] wbuf_wdata_req_reloff_par, 
    input         [wdatalen_width-1:0] wbuf_wdata_req_length, // number of bytes to request, max 4096B
    input     [wdatalen_par_width-1:0] wbuf_wdata_req_length_par, // number of bytes to request, max 4096B
    input           [wbufid_width-1:0] wbuf_wdata_req_wbufid, // buffer id
    input       [wbufid_par_width-1:0] wbuf_wdata_req_wbufid_par, // buffer id
    output reg                         wdata_wbuf_req_ready, 
   
    // ----------------------------------------------------
    // write buffer response from host
    // ----------------------------------------------------
    output reg                         wdata_wbuf_rsp_valid,
    output reg                         wdata_wbuf_rsp_end,
    output reg                         wdata_wbuf_rsp_error,
    output reg         [tag_width-1:0] wdata_wbuf_rsp_tag,
    output reg     [tag_par_width-1:0] wdata_wbuf_rsp_tag_par,
    output reg      [wbufid_width-1:0] wdata_wbuf_rsp_wbufid,
    output reg  [wbufid_par_width-1:0] wdata_wbuf_rsp_wbufid_par,
    output reg      [beatid_width-1:0] wdata_wbuf_rsp_beat,
    output reg        [data_width-1:0] wdata_wbuf_rsp_data,
    output reg [data_fc_par_width-1:0] wdata_wbuf_rsp_data_par,
    input                              wbuf_wdata_rsp_ready,
   
    // ----------------------------------------------------
    input                              regs_wdata_errinj_valid,
    output reg                         wdata_regs_errinj_ack,
    output reg                         wdata_regs_errinj_active,
    output                             wdata_perror_ind,
    // ----------------------------------------------------------
    // parity error inject 
    // ----------------------------------------------------------
    input                              regs_sntl_pe_errinj_valid,
    input                       [15:0] regs_xxx_pe_errinj_decode, 
    input                              regs_wdata_pe_errinj_1cycle_valid 
  
    );


   `include "nvme_func.svh"


   // ----------------------------------------------------
   // fifo for requests
   // ----------------------------------------------------

   wire                            req_valid;
   reg          [wbufid_width-1:0] req_wbufid;
   reg      [wbufid_par_width-1:0] req_wbufid_par;
   reg                       [1:0] req_source;  // 1=dma 2=wbuf 3=admin
   reg             [tag_width-1:0] req_tag;
   reg                             req_tag_par;
   reg         [datalen_width-1:0] req_reloff;
   reg        [wdatalen_width-1:0] req_length;
   reg                             req_length_par;
   reg                             req_taken;
   reg                             req_flush;
   
   localparam req_fifo_width=wbufid_width + 1 + 2 + tag_width+1+datalen_width+wdatalen_width+1;  // added +1 for tag parity and +1 for size parity and  buf_id_par
   reg                             req_fifo_push;
   reg        [req_fifo_width-1:0] req_fifo_wrdata;
   wire       [req_fifo_width-1:0] req_fifo_rddata;
   wire                            req_fifo_full;
   wire                            req_fifo_afull;
   
   // 256 entries for 8b pcie tag.  Note: currently supported NVMe part doesn't support extended tag so this is oversized
   // 1 entry for admin request
   nvme_fifo#(
              .width(req_fifo_width), 
              .words(262),
              .almost_full_thresh(6)
              ) req_fifo
     (.clk(clk), 
      .reset(reset), 
      .flush(       req_flush ),
      .push(        req_fifo_push ),
      .din(         req_fifo_wrdata  ),
      .dval(        req_valid ), 
      .pop(         req_taken ),
      .dout(        req_fifo_rddata ),
      .full(        req_fifo_full ),
      .almost_full( req_fifo_afull ),
      .used( )
      );

   always @*
     begin
        req_fifo_push = dma_wdata_req_valid | wbuf_wdata_req_valid;
        
        if( dma_wdata_req_valid )
          begin
             req_fifo_wrdata = { zero[wbufid_width-1:0],  zero[wbufid_par_width-1:0], 1'b0, 2'b01, dma_wdata_req_tag, dma_wdata_req_tag_par, dma_wdata_req_reloff, dma_wdata_req_length, dma_wdata_req_length_par};
          end
        else
          begin
             req_fifo_wrdata = {  wbuf_wdata_req_wbufid, wbuf_wdata_req_wbufid_par, 2'b10, wbuf_wdata_req_tag, wbuf_wdata_req_tag_par, wbuf_wdata_req_reloff, wbuf_wdata_req_length, wbuf_wdata_req_length_par};
          end
        
        wdata_dma_req_pause = req_fifo_afull;
        wdata_wbuf_req_ready = ~req_fifo_afull & ~dma_wdata_req_valid;
        req_flush = 1'b0;

        { req_wbufid, req_wbufid_par, req_source, req_tag, req_tag_par, req_reloff, req_length, req_length_par} = req_fifo_rddata; 
     end

   
   // ----------------------------------------------------
   // send requests to afu
   // ----------------------------------------------------

   // save wbufid for requests from wbuf
   // only 1 request per wbufid can be outstanding
   localparam wbuf_fifo_width = 1 + wbufid_width + 1 + tag_width;
   reg                        wbuf_fifo_flush;
   reg                        wbuf_fifo_push;
   reg  [wbuf_fifo_width-1:0] wbuf_fifo_wrdata;
   wire                       wbuf_fifo_valid;
   reg                        wbuf_fifo_taken;
   wire [wbuf_fifo_width-1:0] wbuf_fifo_rddata;   
   wire                       wbuf_fifo_full;
   wire                       wbuf_fifo_afull;
 
   nvme_fifo#(
              .width(wbuf_fifo_width), 
              .words(wbuf_numids+1),
              .almost_full_thresh(1)
              ) wbuf_fifo
     (.clk(clk), 
      .reset(reset), 
      .flush(       wbuf_fifo_flush ),
      .push(        wbuf_fifo_push ),
      .din(         wbuf_fifo_wrdata  ),
      .dval(        wbuf_fifo_valid ), 
      .pop(         wbuf_fifo_taken ),
      .dout(        wbuf_fifo_rddata ),
      .full(        wbuf_fifo_full ),
      .almost_full( wbuf_fifo_afull ),
      .used( )
      );


   // send request to sislite
   always @*
     begin
        o_wdata_req_v_out         = req_valid; 
        o_wdata_req_tag_out       = req_tag;
        o_wdata_req_tag_par_out   = req_tag_par; 
        // convert reloff to beats.  reloff is bytes,  beats is data_width/8 bytes
        o_wdata_req_beat_out      = req_reloff[datalen_width-1:datalen_width-beatid_width];
        o_wdata_req_size_out      = {zero[datalen_width-1:wdatalen_width], req_length};
        o_wdata_req_size_par_out  = req_length_par;

        req_taken                 = req_valid & o_wdata_req_r_in;
     end

   reg [wbufid_width-1:0] wbuf_fifo_wbufid;
   reg                    wbuf_fifo_wbufid_par;
   reg    [tag_width-1:0] wbuf_fifo_tag;
   reg                    wbuf_fifo_tag_par;
   always @*
     begin
        wbuf_fifo_flush   = 1'b0;        
        wbuf_fifo_push    = req_source==2'b10 && req_taken;
        wbuf_fifo_wrdata  = { req_wbufid_par, req_wbufid, req_tag_par, req_tag };
        {wbuf_fifo_wbufid_par, wbuf_fifo_wbufid, wbuf_fifo_tag_par, wbuf_fifo_tag } = wbuf_fifo_rddata;   

        wbuf_fifo_taken   = wdata_wbuf_rsp_valid & wdata_wbuf_rsp_end;
     end
   

   
   // ---------------------------------------------------------
   // Receive data from AFU
   // ---------------------------------------------------------


   localparam s0_width = tag_width +1 + beatid_width + data_width + data_fc_par_width  + 1 + 1;
   wire [s0_width-1:0] s0_wdata_dout;
   wire                s0_wdata_valid;
   wire                s0_wdata_ready;
   
   nvme_pl_burp#(.width(s0_width), .stage(1)) s0 
     (.clk(clk),.reset(reset),
      .valid_in(i_wdata_rsp_v_in),
      .data_in( { i_wdata_rsp_tag_in,i_wdata_rsp_tag_par_in,i_wdata_rsp_beat_in, i_wdata_rsp_data_in,i_wdata_rsp_data_par_in[1],i_wdata_rsp_data_par_in[0],i_wdata_rsp_e_in,i_wdata_rsp_error_in } ),
      .ready_out( i_wdata_rsp_r_out ),
                 
      .data_out(s0_wdata_dout),
      .valid_out(s0_wdata_valid),
      .ready_in(s0_wdata_ready)
      ); 
   
   // backpressure from frame buffers for dma module when no buffers are available
   // or if wbuf isn't ready
   reg dma_ready;
   assign s0_wdata_ready = dma_ready & wbuf_wdata_rsp_ready;
   
   reg                         s0_wdata_e;
   reg                         s0_wdata_error;
   reg         [tag_width-1:0] s0_wdata_tag;
   reg                         s0_wdata_tag_par;
   reg      [beatid_width-1:0] s0_wdata_beat;
   reg        [data_width-1:0] s0_wdata_data_in;   
   reg        [data_width-1:0] s0_wdata_data;   
   reg [data_fc_par_width-1:0] s0_wdata_data_par_in;   
   reg [data_fc_par_width-1:0] s0_wdata_data_par;   

   always @*
     begin
        { s0_wdata_tag, s0_wdata_tag_par, s0_wdata_beat, s0_wdata_data_in, s0_wdata_data_par_in, s0_wdata_e, s0_wdata_error } = s0_wdata_dout;
        s0_wdata_data     = byteswap128(s0_wdata_data_in);  // sislite is big-endian, NVMe is little endian
        s0_wdata_data_par = {s0_wdata_data_par_in[0],s0_wdata_data_par_in[1]};
     end


   // check tag parity 

   wire    s1_perror;
   wire    wdata_perror_int ;

   reg     wdata_pe_inj_d,wdata_pe_inj_q;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             wdata_pe_inj_q <= 1'b0;
          end
        else
          begin
             wdata_pe_inj_q <=  wdata_pe_inj_d;
          end
     end

   always @*
     begin  
        wdata_pe_inj_d =  wdata_pe_inj_q;    
        if (regs_wdata_pe_errinj_1cycle_valid & regs_sntl_pe_errinj_valid & regs_xxx_pe_errinj_decode[11:8] == 4'h5)
          begin
             wdata_pe_inj_d  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
          end
        if (wdata_pe_inj_q & s0_wdata_valid)
          wdata_pe_inj_d = 1'b0;          
     end  

   nvme_pcheck#
     (.bits_per_parity_bit(8),.width(tag_width)) 
   ipcheck_s0_wdata_tag
     (.oddpar(1'b1),.data({s0_wdata_tag[tag_width-1:1],(s0_wdata_tag[0]^wdata_pe_inj_q)}),.datap(s0_wdata_tag_par),.check(s0_wdata_valid),.parerr(s1_perror)); 


   // set/reset/ latch for parity errors 
   nvme_srlat#
     (.width(1))  iwbuf_sr   
       (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(wdata_perror_int));

   assign wdata_perror_ind = wdata_perror_int; 

   
   // route response
   // - if tag matches wbuf request, sent data directly to wbuf
   // - else fill frame buffers 128B at a time before sending to dma
   // optionally inject error
   //    
   reg wdata_errinj;
   reg wdata_errinj_v_q, wdata_errinj_v_d;
   
   reg wdata_dma_v;
   reg wdata_e;
   reg wdata_error;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             wdata_errinj_v_q <= 1'b0;
          end
        else
          begin
             wdata_errinj_v_q <=  wdata_errinj_v_d;
          end
     end

   reg wbuf_match;
   always @*
     begin
        // does this tag belong to wbuf or dma?
        wbuf_match       = wbuf_fifo_valid & s0_wdata_tag==wbuf_fifo_tag;
        
        wdata_errinj_v_d = wdata_errinj_v_q;
        wdata_errinj     = s0_wdata_valid & s0_wdata_ready & regs_wdata_errinj_valid;
        if( ~wdata_errinj_v_q & wdata_errinj )
          begin
             wdata_errinj_v_d      = 1'b1;
             wdata_wbuf_rsp_valid  = wbuf_match;
             wdata_dma_v           = ~wbuf_match;
             wdata_e               = 1'b1;
             wdata_error           = 1'b1;
          end
        else if( wdata_errinj_v_q )
          begin
             wdata_dma_v           = 1'b0;
             wdata_wbuf_rsp_valid  = 1'b0;
             wdata_e               = 1'b0;
             wdata_error           = 1'b0;
             if( s0_wdata_e & s0_wdata_valid )
               begin
                  wdata_errinj_v_d = 1'b0;
               end
          end
        else
          begin
             wdata_dma_v           = s0_wdata_valid & ~wbuf_match & s0_wdata_ready;
             wdata_wbuf_rsp_valid  = s0_wdata_valid & wbuf_match & s0_wdata_ready;
             wdata_e               = s0_wdata_e;
             wdata_error           = s0_wdata_error;                            
          end
        
        wdata_regs_errinj_active  = ~wdata_errinj_v_q & s0_wdata_valid & s0_wdata_e & s0_wdata_ready;
        wdata_regs_errinj_ack     = ~wdata_errinj_v_q & wdata_errinj;

     end // always @ *

   reg                         wdata_dma_e;
   reg                         wdata_dma_error;
   reg         [tag_width-1:0] wdata_dma_tag;
   reg                         wdata_dma_tag_par;
   reg      [beatid_width-1:0] wdata_dma_beat;
   reg        [data_width-1:0] wdata_dma_data;
   reg [data_fc_par_width-1:0] wdata_dma_data_par;
   always @*
     begin        
        wdata_wbuf_rsp_end         = wdata_e;
        wdata_wbuf_rsp_error       = wdata_error;
        wdata_wbuf_rsp_tag         = s0_wdata_tag;
        wdata_wbuf_rsp_tag_par     = s0_wdata_tag_par;
        wdata_wbuf_rsp_wbufid      = wbuf_fifo_wbufid;
        wdata_wbuf_rsp_wbufid_par  = wbuf_fifo_wbufid_par;
        wdata_wbuf_rsp_beat        = s0_wdata_beat;
        wdata_wbuf_rsp_data        = s0_wdata_data;
        wdata_wbuf_rsp_data_par    = s0_wdata_data_par;
        
        wdata_dma_e                = wdata_e;
        wdata_dma_error            = wdata_error;
        wdata_dma_tag              = s0_wdata_tag;
        wdata_dma_tag_par          = s0_wdata_tag_par;
        wdata_dma_beat             = s0_wdata_beat;
        wdata_dma_data             = s0_wdata_data;        
        wdata_dma_data_par         = s0_wdata_data_par;        
     end   

   // ---------------------------------------------------------
   // store data and header into fifo
   // ---------------------------------------------------------

   localparam framebuf_width=data_width;                       // width in bits
   localparam framebuf_par_width=data_fc_par_width;            
   localparam framebuf_size=128;                               // bytes per buffer entry
   localparam framebuf_entries=16;                             // number of buffer entries
   localparam framebuf_beats=framebuf_size/(framebuf_width/8); // number of beats per entry
   localparam framebuf_last_beat=framebuf_beats-1;             // last beat number in an entry
   localparam framebuf_awidth=$clog2(framebuf_beats);          // # address bits in one buffer entry
   localparam fbptr_width=$clog2(framebuf_entries);

   localparam fb_memsize = framebuf_beats * framebuf_entries;
   localparam fb_addrsize = $clog2(fb_memsize);
   reg [framebuf_par_width+framebuf_width-1:0] framebuf[0:fb_memsize-1];
   reg [framebuf_par_width+framebuf_width-1:0] framebuf_wdata, framebuf_rdata;    
   reg                       [fb_addrsize-1:0] framebuf_waddr, framebuf_raddr;
   reg                                         framebuf_write;
   reg                                         framebuf_push;
   reg                                         framebuf_pop;
   
   localparam framehdr_width = tag_width +1 + beatid_width + framebuf_awidth+1 + 1 + 1; 
   reg                    [framehdr_width-1:0] framehdr[0:framebuf_entries-1];
   reg                    [framehdr_width-1:0] framehdr_wdata, framehdr_rdata;
   reg                       [fbptr_width-1:0] framehdr_waddr, framehdr_raddr;
   reg                                         framehdr_write;
   reg                                         framehdr_push;
   reg                                         framehdr_pop;

   always @(posedge clk)
     begin
        if (framebuf_write)
          framebuf[framebuf_waddr] <= framebuf_wdata;   // parity included in wdata 
        framebuf_rdata <= framebuf[framebuf_raddr];
        
        if (framehdr_write)
          framehdr[framehdr_waddr] <= framehdr_wdata;
        framehdr_rdata <= framehdr[framehdr_raddr];
     end


   // ---------------------------------------------------------
   // state machine to control writing of data into buffers

   localparam [3:0] WR_IDLE     = 4'h1;
   localparam [3:0] WR_RCV      = 4'h2;
   localparam [3:0] WR_RCVEND   = 4'h3;
   
   reg               [3:0] fbwr_state_q, fbwr_state_d;
   reg   [fbptr_width-1:0] fb_head_q, fb_head_d;
   reg   [fbptr_width-1:0] fb_tail_q, fb_tail_d;
   reg     [fbptr_width:0] fb_inuse_q, fb_inuse_d;
   reg [framebuf_awidth:0] fb_offset_q, fb_offset_d;
   
   reg     [tag_width-1:0] fb_hdr_tag_q, fb_hdr_tag_d;
   reg                     fb_hdr_tag_par_q, fb_hdr_tag_par_d;

   reg  [beatid_width-1:0] fb_hdr_beat_q, fb_hdr_beat_d;
   reg [framebuf_awidth:0] fb_hdr_numbeats_q, fb_hdr_numbeats_d;
   reg                     fb_hdr_error_q, fb_hdr_error_d;
   reg                     fb_hdr_end_q, fb_hdr_end_d;
   
   reg   [fbptr_width-1:0] fb_hdr_head_q, fb_hdr_head_d;
   reg   [fbptr_width-1:0] fb_hdr_tail_q, fb_hdr_tail_d;
   reg     [fbptr_width:0] fb_hdr_inuse_q, fb_hdr_inuse_d;

  
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             fbwr_state_q      <= WR_IDLE;        
             fb_head_q         <= zero[fbptr_width-1:0];
             fb_tail_q         <= zero[fbptr_width-1:0];
             fb_inuse_q        <= zero[fbptr_width:0];
             fb_offset_q       <= zero[framebuf_awidth:0];
            
             fb_hdr_tag_q      <= zero[tag_width-1:0];
             fb_hdr_tag_par_q  <= 1'b0; 
             fb_hdr_beat_q     <= zero[beatid_width-1:0];
             fb_hdr_numbeats_q <= zero[framebuf_awidth:0];
             fb_hdr_error_q    <= 1'b0;            
             fb_hdr_end_q      <= 1'b0;            
             fb_hdr_head_q     <= zero[fbptr_width-1:0];
             fb_hdr_tail_q     <= zero[fbptr_width-1:0];
             fb_hdr_inuse_q    <= zero[fbptr_width:0];
          end
        else
          begin
             fbwr_state_q      <= fbwr_state_d;           
             fb_head_q         <= fb_head_d;
             fb_tail_q         <= fb_tail_d;
             fb_inuse_q        <= fb_inuse_d;
             fb_offset_q       <= fb_offset_d;
             
             fb_hdr_tag_q      <= fb_hdr_tag_d;
             fb_hdr_tag_par_q  <= fb_hdr_tag_par_d;
             fb_hdr_beat_q     <= fb_hdr_beat_d;
             fb_hdr_numbeats_q <= fb_hdr_numbeats_d;
             fb_hdr_error_q    <= fb_hdr_error_d;
             fb_hdr_end_q      <= fb_hdr_end_d;         
             fb_hdr_head_q     <= fb_hdr_head_d;
             fb_hdr_tail_q     <= fb_hdr_tail_d;
             fb_hdr_inuse_q    <= fb_hdr_inuse_d;           
          end
     end


   always @*
     begin
        // payload buffer fifo controls
        fb_tail_d       = fb_tail_q;      // next free buffer
        fb_head_d       = fb_head_q;      // buffer to read from
        fb_inuse_d      = fb_inuse_q;     // number of buffers in use

        fb_hdr_tail_d   = fb_hdr_tail_q;  
        fb_hdr_head_d   = fb_hdr_head_q;  
        fb_hdr_inuse_d  = fb_hdr_inuse_q;

        if( framebuf_push )
          begin
             fb_tail_d = fb_tail_d + one[fbptr_width-1:0];
             if( fb_tail_q == (framebuf_entries[fbptr_width-1:0]-one[fbptr_width-1:0]))
               begin
                  fb_tail_d = zero[fbptr_width-1:0];                  
               end
             fb_inuse_d = fb_inuse_d + one[fbptr_width:0];
          end
        
        if( framebuf_pop )
          begin
             fb_head_d = fb_head_d + one[fbptr_width-1:0];
             if( fb_head_q == (framebuf_entries[fbptr_width-1:0]-one[fbptr_width-1:0]))
               begin
                  fb_head_d = zero[fbptr_width-1:0];                  
               end
             fb_inuse_d = fb_inuse_d - one[fbptr_width:0];
          end

        if( framehdr_push )
          begin 
             fb_hdr_tail_d = fb_hdr_tail_d + one[fbptr_width-1:0];
             if( fb_hdr_tail_q == (framebuf_entries[fbptr_width-1:0]-one[fbptr_width-1:0]))
               begin
                  fb_hdr_tail_d = zero[fbptr_width-1:0];                  
               end
             fb_hdr_inuse_d = fb_hdr_inuse_d + one[fbptr_width:0];
          end

        if( framehdr_pop )
          begin
             fb_hdr_head_d = fb_hdr_head_d + one[fbptr_width-1:0];
             if( fb_hdr_head_q == (framebuf_entries[fbptr_width-1:0]-one[fbptr_width-1:0]))
               begin
                  fb_hdr_head_d = zero[fbptr_width-1:0];                  
               end
             fb_hdr_inuse_d = fb_hdr_inuse_d - one[fbptr_width:0];
          end        
     end

   // ---------------------------------------------------------
   // receive data from host and store in frame buffer 
   reg                 dma_ready_q, dma_ready_d;
   always @(posedge clk)
     begin       
        dma_ready_q <= dma_ready_d;     
     end
                                         
   always @*
     begin
        dma_ready_d        = (fb_inuse_q < (framebuf_entries[fbptr_width:0]-one[fbptr_width:0]));
        dma_ready          = dma_ready_q;
     end

   always @*
     begin
        fbwr_state_d       = fbwr_state_q;
        fb_offset_d        = fb_offset_q;    // beat number within current buffer
        
        framebuf_push      = 1'b0;
        framebuf_write     = 1'b0;
        framebuf_waddr     = { fb_tail_q, fb_offset_q[framebuf_awidth-1:0] };
        framebuf_wdata     = {wdata_dma_data_par,wdata_dma_data};
       
        // header fifo controls
        fb_hdr_tag_d       = fb_hdr_tag_q;
        fb_hdr_tag_par_d   = fb_hdr_tag_par_q;  
        fb_hdr_beat_d      = fb_hdr_beat_q;      // beat at start of buffer
        fb_hdr_numbeats_d  = fb_hdr_numbeats_q;  // number of valid beats in this buffer
        fb_hdr_error_d     = fb_hdr_error_q;     // error indication from afu
        fb_hdr_end_d       = fb_hdr_end_q;       // end of this response
        
        framehdr_push      = 1'b0;        
        framehdr_write     = 1'b0;
        framehdr_waddr     = { fb_hdr_tail_q };
        framehdr_wdata     = { fb_hdr_tag_q,  fb_hdr_tag_par_q, fb_hdr_beat_q, fb_hdr_numbeats_q, fb_hdr_error_q, fb_hdr_end_q };

        case(fbwr_state_q)
          WR_IDLE:
            begin 
               // receive first beat of data for a new tag
               fb_hdr_tag_d       = wdata_dma_tag;
               fb_hdr_tag_par_d   = wdata_dma_tag_par; 
               fb_hdr_beat_d      = wdata_dma_beat;   
               fb_hdr_numbeats_d  = fb_offset_q;
               fb_hdr_error_d     = wdata_dma_error;
               fb_hdr_end_d       = wdata_dma_e;         
 
               if( wdata_dma_v )
                 begin
                    if( wdata_dma_e )
                      begin
                         // end is asserted *after* the last data cycle
                         // if end is asserted in this state, no data was received
                         // this is only expected if the afu also asserts error
                         framebuf_push   = 1'b1;
                         framehdr_write  = 1'b1;                         
                         framehdr_wdata  = { fb_hdr_tag_d, fb_hdr_beat_d, fb_hdr_numbeats_d, fb_hdr_error_d, fb_hdr_end_d };
                         framehdr_push   = 1'b1;                        
                      end
                    else
                      begin
                         framebuf_write   = 1'b1;
                         fb_offset_d      = fb_offset_q + one[framebuf_awidth:0];
                         fbwr_state_d     = WR_RCV;
                      end
                 end
            end

          WR_RCV:
            begin              
               if( wdata_dma_v  )
                 begin
                    fb_hdr_error_d     = fb_hdr_error_q | wdata_dma_error;
                    fb_hdr_end_d       = wdata_dma_e;
                    fb_hdr_numbeats_d  = fb_offset_q;
                    
                    if( wdata_dma_e )
                      begin
                         // end of this request - no data this cycle
                         // write the frame header info
                         framehdr_write  = 1'b1;
                         framehdr_wdata  = { fb_hdr_tag_q, fb_hdr_tag_par_q, fb_hdr_beat_q, fb_hdr_numbeats_d, fb_hdr_error_d, fb_hdr_end_d };
                         framehdr_push   = 1'b1;
                         framebuf_push   = 1'b1;          
                         fb_offset_d     = zero[framebuf_awidth:0];
                         fbwr_state_d    = WR_IDLE;
                      end
                    else
                      begin
                         framebuf_write   = 1'b1;
                         fb_offset_d = fb_offset_q + one[framebuf_awidth:0];
                         if( fb_offset_q==framebuf_last_beat[framebuf_awidth:0] )
                           begin
                              // end of a 128B chunk
                              // next cycle could be more data or an end indicator
                              // wait to write header info until we know if this is the end                                                    
                              framebuf_push      = 1'b1;                              
                              fbwr_state_d       = WR_RCVEND;
                              fb_hdr_numbeats_d  = fb_offset_d;  // save number of beats written for next cycle
                              fb_offset_d        = zero[framebuf_awidth:0];
                           end
                      end
                 end
            end

          WR_RCVEND:
            begin
               // expect either the start of a new 128B buffer or the end indicator for this transfer
               if( wdata_dma_v )
                 begin
                    fb_hdr_error_d     = fb_hdr_error_q | wdata_dma_error;
                    fb_hdr_end_d       = wdata_dma_e;

                    // write the header info for the framebuf completed on the previous cycle
                    framehdr_write     = 1'b1;                     
                    framehdr_wdata     = { fb_hdr_tag_q, fb_hdr_tag_par_q, fb_hdr_beat_q, fb_hdr_numbeats_q, fb_hdr_error_d, fb_hdr_end_d };
                    framehdr_push      = 1'b1;
                    fb_hdr_numbeats_d  = zero[framebuf_awidth:0];
                    
                    if( wdata_dma_e )
                      begin
                         // end of this request - no data this cycle                                      
                         fbwr_state_d  = WR_IDLE;
                      end
                    else
                      begin
                         // write beat 0 of new buffer
                         framebuf_write  = 1'b1;                         
                         fb_offset_d     = one[framebuf_awidth:0];                             
                         fbwr_state_d    = WR_RCV;

                         // save header info for the new buffer
                         fb_hdr_tag_d    = wdata_dma_tag;
                         fb_hdr_tag_par_d    = wdata_dma_tag_par;
                         fb_hdr_beat_d   = wdata_dma_beat;                           
                         fb_hdr_error_d  = wdata_dma_error;
                         fb_hdr_end_d    = 1'b0;
                      end
                 end
            end
          
          default:
            begin
               fbwr_state_d = WR_IDLE;
            end
        endcase

     end // always @ *




   // ---------------------------------------------------------
   // read data from buffer and send to dma module
   // ---------------------------------------------------------

   reg   [fbptr_width-1:0] s0_hdr_raddr;
   reg                     s0_valid;
   
   reg                     s1_ready;
   reg                     s1_valid_q, s1_valid_d;
   reg                     s1_first_q, s1_first_d;
   reg   [fbptr_width-1:0] s1_hdr_raddr_q, s1_hdr_raddr_d;
   reg [framebuf_awidth:0] s1_offset_q, s1_offset_d;
   
   reg                     s2_ready;
   reg   [fb_addrsize-1:0] s2_raddr_q, s2_raddr_d;
   reg                     s2_valid_q, s2_valid_d;
   reg     [tag_width-1:0] s2_tag_q, s2_tag_d;
   reg                     s2_tag_par_q, s2_tag_par_d;
   reg [datalen_width-1:0] s2_reloff_q, s2_reloff_d;
   reg               [9:0] s2_length_q, s2_length_d;
   reg                     s2_first_q, s2_first_d;
   reg                     s2_last_q, s2_last_d;
   reg                     s2_error_q, s2_error_d;
   reg                     s2_end_q, s2_end_d;


   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             s1_valid_q     <= 1'b0;
             s1_first_q     <= 1'b0;
             s1_hdr_raddr_q <= zero[fbptr_width-1:0];
             s1_offset_q    <= zero[framebuf_awidth:0];

             s2_valid_q     <= 1'b0;
             s2_raddr_q     <= zero[fb_addrsize-1:0];
             s2_tag_q       <= zero[tag_width-1:0];
             s2_tag_par_q   <= 1'b0;
             s2_reloff_q    <= zero[datalen_width-1:0];
             s2_length_q    <= zero[9:0];
             s2_first_q     <= 1'b0;
             s2_last_q      <= 1'b0;
             s2_error_q     <= 1'b0;
             s2_end_q       <= 1'b0;
          end
        else
          begin
             s1_valid_q     <= s1_valid_d;
             s1_first_q     <= s1_first_d;
             s1_hdr_raddr_q <= s1_hdr_raddr_d;
             s1_offset_q    <= s1_offset_d;

             s2_valid_q     <= s2_valid_d;
             s2_raddr_q     <= s2_raddr_d;
             s2_tag_q       <= s2_tag_d;
             s2_tag_par_q   <= s2_tag_par_d;
             s2_reloff_q    <= s2_reloff_d;
             s2_length_q    <= s2_length_d;
             s2_first_q     <= s2_first_d;
             s2_last_q      <= s2_last_d;
             s2_error_q     <= s2_error_d;
             s2_end_q       <= s2_end_d;
         end
     end
   
   // stage s0 - read header
   always @*
     begin    
        s0_valid      = fb_hdr_inuse_q != zero[fbptr_width:0];
        s0_hdr_raddr  = fb_hdr_head_q;
       
        if( s1_ready )
          begin
             framehdr_raddr  = s0_hdr_raddr;
             framehdr_pop    = s0_valid;                    
          end
        else
          begin                     
             framehdr_raddr  = s1_hdr_raddr_q;
             framehdr_pop    = 1'b0;
          end
     end

   // stage s1 - header is valid.  read payload buffer. 0 to 8 cycles of payload.
   reg     [tag_width-1:0] s1_hdr_tag;
   reg                     s1_hdr_tag_par;
   reg  [beatid_width-1:0] s1_hdr_beat;
   reg [framebuf_awidth:0] s1_hdr_numbeats;
   reg                     s1_hdr_error;
   reg                     s1_hdr_end;   
   reg                     s1_last;
   reg [framebuf_awidth:0] s1_offset_p1;
   always @*
     begin        

        // read from payload buffer
        if( s2_ready )
          begin
             framebuf_raddr = { fb_head_q, s1_offset_q[framebuf_awidth-1:0] };
          end
        else
          begin
             framebuf_raddr = s2_raddr_q;
          end

        // header result from header buffer
        { s1_hdr_tag, s1_hdr_tag_par, s1_hdr_beat, s1_hdr_numbeats, s1_hdr_error, s1_hdr_end } = framehdr_rdata; 
        
        s1_offset_p1 = s1_offset_q + one[framebuf_awidth:0];

        // is this the last valid payload cycle for this buffer?
        s1_last          = s1_valid_q &&
                           (s1_offset_p1==s1_hdr_numbeats || s1_hdr_numbeats==zero[framebuf_awidth:0]) &&
                           s2_ready;
  
        framebuf_pop = s1_last;
              
        s1_ready         = ~s1_valid_q | s1_last;

        if( s1_ready )
          begin
             // start new buffer
             s1_hdr_raddr_d  = s0_hdr_raddr;            
             s1_valid_d      = s0_valid;
             s1_first_d      = 1'b1;
             s1_offset_d     = zero[framebuf_awidth-1:0];
          end
        else
          begin
             s1_hdr_raddr_d  = s1_hdr_raddr_q;             
             s1_valid_d      = s1_valid_q;
             s1_first_d      = s1_first_q;
             if( s2_ready )
               begin
                  // advance the payload beat offset after the first non-data cycle
                  if( s1_first_q )
                    s1_offset_d = s1_offset_q;
                  else
                    s1_offset_d  = s1_offset_p1;
                  s1_first_d   = 1'b0;
               end
             else
               begin
                  s1_offset_d  = s1_offset_q;
               end
          end       
     end   

   // stage 2 - payload data valid.  load interface regs
   always @*
     begin
        
        s2_ready         = ~s2_valid_q | dma_wdata_cpl_ready;

        if( s2_ready )
          begin
             s2_valid_d   = s1_valid_q;
             s2_raddr_d   = framebuf_raddr;
             s2_tag_d     = s1_hdr_tag;
             s2_tag_par_d = s1_hdr_tag_par;  
             s2_reloff_d  = {      s1_hdr_beat[beatid_width-1:0], zero[datalen_width-beatid_width-1:0] };  // convert beats to bytes
             s2_length_d  = { s1_hdr_numbeats[framebuf_awidth:0], zero[datalen_width-beatid_width-1:0] };  // convert beats to bytes
             s2_first_d   = s1_first_q;
             s2_last_d    = s1_last;
             s2_error_d   = s1_hdr_error;
             s2_end_d     = s1_hdr_end;
          end
        else
          begin
             s2_valid_d   = s2_valid_q;
             s2_raddr_d   = s2_raddr_q;
             s2_tag_d     = s2_tag_q;
             s2_tag_par_d = s2_tag_par_q;
             s2_reloff_d  = s2_reloff_q;
             s2_length_d  = s2_length_q;
             s2_first_d   = s2_first_q;
             s2_last_d    = s2_last_q;
             s2_error_d   = s2_error_q;
             s2_end_d     = s2_end_q;
          end
       

        wdata_dma_cpl_valid   = s2_valid_q;
        wdata_dma_cpl_tag     = s2_tag_q;
        wdata_dma_cpl_tag_par = s2_tag_par_q;
        wdata_dma_cpl_reloff  = s2_reloff_q;
        wdata_dma_cpl_length  = s2_length_q;
        wdata_dma_cpl_data    = framebuf_rdata;
        wdata_dma_cpl_first   = s2_first_q;
        wdata_dma_cpl_last    = s2_last_q;
        wdata_dma_cpl_error   = s2_error_q;
        wdata_dma_cpl_end     = s2_end_q;
     
     end
   



  
endmodule 
