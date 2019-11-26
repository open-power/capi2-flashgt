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
//  File : nvme_sntl_wbuf.v
//  *************************************************************************
//  *************************************************************************
//  Description : SurelockNVME - SCSI to NVMe Layer payload write buffer
//                
//  *************************************************************************

module nvme_sntl_unmap#
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
   parameter data_par_width  = (data_width + 7) / 8,
   parameter data_fc_par_width = data_par_width/8,
   parameter status_width    = 8, // event status
   parameter wdata_max_req   = 4096,
   parameter wdatalen_width  = $clog2(wdata_max_req)+1,
   parameter wdatalen_par_width  = (wdatalen_width+63)/64 ,   
   parameter wbuf_size       = 4096, // 4KB per write buffer
   parameter wbuf_numids     = 6,  
   parameter wbufid_width    = $clog2(wbuf_numids),
   parameter wbufid_par_width = (wbufid_width + 7)/8,

   parameter trk_entries      = (1<<tag_width),
   parameter trk_awidth       = tag_width,
   
   parameter cid_width = 16,
   parameter cid_par_width = 16/8
      
    )
   (
   
    input                             reset,
    input                             clk, 

    input                             regs_xx_tick1, // 1us
    input                      [11:0] regs_unmap_timer1, // delay before sending 1st cmd
    input                      [19:0] regs_unmap_timer2, // gap between sequential cmds
    input                       [7:0] regs_unmap_rangecount, // max cmds to combine in one dataset management cmd
    input                       [7:0] regs_unmap_reqcount, // max requests to queue before overriding timer1/timer2
    //-------------------------------------------------------
    // request from command tracking
    //-------------------------------------------------------
    input                             cmd_unmap_req_valid,
    input                             cmd_unmap_cpl_valid,
    input             [cid_width-1:0] cmd_unmap_cid,
    input         [cid_par_width-1:0] cmd_unmap_cid_par,
    input                      [14:0] cmd_unmap_cpl_status,
    input                             cmd_unmap_flush,
    input                             cmd_unmap_ioidle,

    // event to command tracking
    output reg                        unmap_cmd_valid,
    output reg        [cid_width-1:0] unmap_cmd_cid,
    output reg    [cid_par_width-1:0] unmap_cmd_cid_par,
    output reg                  [3:0] unmap_cmd_event, // 0=write wbuf  1=write wbuf last 2=cpl
    output reg     [wbufid_width-1:0] unmap_cmd_wbufid,
    output reg [wbufid_par_width-1:0] unmap_cmd_wbufid_par,
    output reg                 [14:0] unmap_cmd_cpl_status,
    output reg                  [7:0] unmap_cmd_reloff,
    input                             cmd_unmap_ack, 

  
    //-------------------------------------------------------
    // buffer management
    //-------------------------------------------------------
    output reg                        unmap_wbuf_valid, // need wbufid
    input          [wbufid_width-1:0] wbuf_unmap_wbufid,
    input      [wbufid_par_width-1:0] wbuf_unmap_wbufid_par,
    input                             wbuf_unmap_ack,

    output reg                        unmap_wbuf_idfree_valid, // done with with wbufid
    output reg     [wbufid_width-1:0] unmap_wbuf_idfree_wbufid, 
    output reg [wbufid_par_width-1:0] unmap_wbuf_idfree_wbufid_par,
    input                             wbuf_unmap_idfree_ack   

    );
`include "nvme_func.svh"
   
   //-------------------------------------------------------
   // push new requests into fifo
   // no backpressure - sized to hold all cmdids
   
   localparam req_width = cid_par_width + cid_width; 
   wire                           req_fifo_valid;
   reg                            req_fifo_taken;
   wire                           req_fifo_full;
   wire                           req_fifo_almost_full;
   wire            [trk_awidth:0] req_fifo_used;
   wire           [req_width-1:0] req_fifo_data;
   
   nvme_fifo#(
              .width(req_width), 
              .words(trk_entries),
              .almost_full_thresh(0)
              ) req_fifo
     (.clk(clk), .reset(reset), 
      .flush(       cmd_unmap_flush ),
      .push(        cmd_unmap_req_valid ),
      .din(         { cmd_unmap_cid_par, cmd_unmap_cid} ),
      .dval(        req_fifo_valid ), 
      .pop(         req_fifo_taken ),
      .dout(        req_fifo_data ),
      .full(        req_fifo_full ), 
      .almost_full( req_fifo_almost_full ), 
      .used(        req_fifo_used));

 
   // push cmdid into response fifo when state machine below starts working on it   
   wire                           rsp_fifo_valid;
   reg                            rsp_fifo_taken;
   wire                           rsp_fifo_full;
   wire                           rsp_fifo_almost_full;
   wire                     [8:0] rsp_fifo_used;
   wire           [req_width-1:0] rsp_fifo_data;
   
   nvme_fifo#(
              .width(req_width), 
              .words(trk_entries),
              .almost_full_thresh(0)
              ) rsp_fifo
     (.clk(clk), .reset(reset), 
      .flush(       cmd_unmap_flush ),
      .push(        req_fifo_taken ),
      .din(         req_fifo_data ),
      .dval(        rsp_fifo_valid ), 
      .pop(         rsp_fifo_taken ),
      .dout(        rsp_fifo_data ),
      .full(        rsp_fifo_full ), 
      .almost_full( rsp_fifo_almost_full ), 
      .used(        rsp_fifo_used));


   // use timers to determine when to allocate a write buffer and how many requests to combine in one buffer
   // start timer when the request fifo becomes valid
   // when the timer expires, allocate a buffer
   // then pull up to 64 cmdids from the request fifo.  For each cmdid, write its lba/range to the wbuf via unmap_cmd_*.
   // push cmdid into response fifo
   // Mark last cmdid as the one to issues the dataset management/deallocate command
   // reset timer (start if fifo is still valid)  
   // when cmd_unmap_cpl_valid, send status on unmap_cmd_* for each cmdid in the rsp fifo
      

   reg                      [7:0] count_q, count_d;
   reg                      [3:0] state_q, state_d;
   reg                     [11:0] req_timer1_q, req_timer1_d;  // us timer 
   reg                            req_timer1_done_q, req_timer1_done_d;
   reg                     [19:0] req_timer2_q, req_timer2_d;  // us timer 
   reg                            req_timer2_done_q, req_timer2_done_d;
   reg                     [11:0] req_timer3_q, req_timer3_d;  // us timer 
   reg                            req_timer3_done_q, req_timer3_done_d;
   reg         [wbufid_width-1:0] wbufid_q, wbufid_d;
   reg     [wbufid_par_width-1:0] wbufid_par_q, wbufid_par_d;
   reg                            rsp_status_q, rsp_status_d;
   reg            [cid_width-1:0] req_cmdid_q, req_cmdid_d;
   reg        [cid_par_width-1:0] req_cmdid_par_q, req_cmdid_par_d;

   localparam [3:0] SM_IDLE    = 4'h1;
   localparam [3:0] SM_WBUF    = 4'h2;
   localparam [3:0] SM_REQ     = 4'h3;
   localparam [3:0] SM_REQ2    = 4'h4;
   localparam [3:0] SM_RSP     = 4'h5;
   localparam [3:0] SM_RSP2    = 4'h6;
   localparam [3:0] SM_RSP3    = 4'h7;
   localparam [3:0] SM_RSP4    = 4'h8;
   localparam [3:0] SM_FREEBUF = 4'h9;
  
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             count_q           <= 8'h0;
             state_q           <= SM_IDLE;
             req_timer1_q      <= 12'h0;
             req_timer1_done_q <= 1'b0;
             req_timer2_q      <= 20'h0;
             req_timer2_done_q <= 1'b1;
             req_timer3_q      <= 12'h0;
             req_timer3_done_q <= 1'b1;
             wbufid_q          <= zero[wbufid_width-1:0];
             wbufid_par_q      <= zero[wbufid_par_width-1:0];
             rsp_status_q      <= 15'h0;
             req_cmdid_q       <= 16'hffff;
             req_cmdid_par_q   <= zero[cid_par_width-1:0];
          end
        else
          begin
             count_q           <= count_d;
             state_q           <= state_d;
             req_timer1_q      <= req_timer1_d;
             req_timer1_done_q <= req_timer1_done_d;
             req_timer2_q      <= req_timer2_d;
             req_timer2_done_q <= req_timer2_done_d;
             req_timer3_q      <= req_timer3_d;
             req_timer3_done_q <= req_timer3_done_d;
             wbufid_q          <= wbufid_d;
             wbufid_par_q      <= wbufid_par_d;
             rsp_status_q      <= rsp_status_d;
             req_cmdid_q       <= req_cmdid_d;
             req_cmdid_par_q   <= req_cmdid_par_d;
          end
     end

   reg reset_timer;
   
   always @*
     begin
        count_d                       = count_q;
        state_d                       = state_q;
        req_cmdid_d                   = req_cmdid_q;
        req_cmdid_par_d               = req_cmdid_par_q;
        wbufid_d                      = wbufid_q;
        wbufid_par_d                  = wbufid_par_q;
        rsp_status_d                  = rsp_status_q;

        req_fifo_taken                = 1'b0;
        rsp_fifo_taken                = 1'b0;

        unmap_wbuf_valid              = 1'b0;
        
        unmap_cmd_valid               = 1'b0;
        unmap_cmd_cid                 = req_cmdid_q;
        unmap_cmd_cid_par             = req_cmdid_par_q;
        unmap_cmd_event               = 4'h0; // 0=write wbuf  1=write wbuf last 2=cpl
        unmap_cmd_wbufid              = wbufid_q;
        unmap_cmd_wbufid_par          = wbufid_par_q;
        unmap_cmd_cpl_status          = rsp_status_q;
        unmap_cmd_reloff              = count_q;

        unmap_wbuf_idfree_valid       = 1'b0;
        unmap_wbuf_idfree_wbufid      = wbufid_q;
        unmap_wbuf_idfree_wbufid_par  = wbufid_par_q;
        
        reset_timer                   = 1'b0;

        case(state_q)
          SM_IDLE:
            begin
               if( ((req_timer1_done_q & req_timer2_done_q) || (req_fifo_used>=regs_unmap_reqcount) ||  (req_fifo_valid & req_timer3_done_q)) 
                   && ~cmd_unmap_flush )
                 begin
                    // there's something in the request fifo and the timers expired
                    // or the request fifo is filling up
                    // or there's no reads or writes
                    // get a buffer
                    state_d = SM_WBUF;
                 end
            end
          SM_WBUF:
            begin
               unmap_wbuf_valid                = 1'b1;
               wbufid_d                        = wbuf_unmap_wbufid;
               wbufid_par_d                    = wbuf_unmap_wbufid_par;
               count_d                         = 8'h0;
               {req_cmdid_par_d, req_cmdid_d}  = req_fifo_data;
               if( wbuf_unmap_ack )
                 begin
                    // we have a buffer, now start sending requests
                    if( cmd_unmap_flush )
                      begin
                         state_d = SM_FREEBUF;
                      end
                    else
                      begin
                         state_d        = SM_REQ;                  
                         req_fifo_taken = 1'b1;
                      end
                 end
            end
          SM_REQ:
            begin
               // send write wbuf request to command processor
               unmap_cmd_valid = 1'b1;
               unmap_cmd_event = 4'h0;
               if( cmd_unmap_flush )
                 begin
                    state_d = SM_FREEBUF;
                 end
               else
                 begin
                    if( count_q == regs_unmap_rangecount ||
                        count_q == 8'd250 ||
                        req_fifo_valid==1'b0)
                      begin
                         unmap_cmd_event  = 4'h1;  // last wbuf write
                         if( cmd_unmap_ack )
                           begin
                              state_d          = SM_RSP;
                              reset_timer      = 1'b1;
                           end
                      end
                    else
                      begin
                         // next cmdid
                         if( cmd_unmap_ack )
                           begin
                              state_d = SM_REQ2;
                           end	
                      end	                    
                 end               
            end
          SM_REQ2:
            begin
               if( cmd_unmap_flush )
                 begin
                    state_d = SM_FREEBUF;
                 end
               else
                 begin
                    // get next cmdid from fifo
                    state_d                         = SM_REQ;
                    count_d                         = count_d + 8'd1;
                    {req_cmdid_par_d, req_cmdid_d}  = req_fifo_data;
                    req_fifo_taken                  = 1'b1;
                 end
            end
          SM_RSP:
            begin
               // wait for completion
               rsp_status_d                    = cmd_unmap_cpl_status;
               {req_cmdid_par_d, req_cmdid_d}  = rsp_fifo_data;
               if( cmd_unmap_flush )
                 begin
                    state_d = SM_FREEBUF;
                 end
               else if( cmd_unmap_cpl_valid )
                 begin
                    state_d = SM_RSP2;
                    rsp_fifo_taken = 1'b1;
                 end
            end
          SM_RSP2:
            begin
               unmap_wbuf_idfree_valid = 1'b1;              
               if( wbuf_unmap_idfree_ack & ~cmd_unmap_flush)
                 begin
                    state_d = SM_RSP3;
                 end
               else if( cmd_unmap_flush )
                 begin
                    state_d = SM_FREEBUF;
                 end              
            end
          SM_RSP3:
            begin
               // send completions for every cmdid in the response fifo
               unmap_cmd_event = 4'h2; // completion             
               unmap_cmd_valid = 1'b1;
               if( cmd_unmap_flush )
                 begin
                    state_d = SM_IDLE;
                 end
               else if( cmd_unmap_ack )
                 begin
                    state_d = SM_RSP4;
                 end                                
            end
          SM_RSP4:
            begin
               {req_cmdid_par_d, req_cmdid_d}  = rsp_fifo_data;
               if( rsp_fifo_valid & ~cmd_unmap_flush)
                 begin
                    state_d = SM_RSP3;
                    rsp_fifo_taken = 1'b1;
                 end
               else
                 begin
                    state_d = SM_IDLE;
                 end
            end
          SM_FREEBUF:
            begin
               // free wrbuf due to flush (linkdown/shutdown)
               unmap_wbuf_idfree_valid = 1'b1;
               if( wbuf_unmap_idfree_ack )
                 begin
                    state_d = SM_IDLE;
                 end
            end
          default:
            begin
               state_d = SM_IDLE;
            end
        endcase // case (state_q)
      
     end

   wire tick1;
`ifdef SIM
   assign tick1 = 1'b1;
`else
   assign tick1 = regs_xx_tick1;
`endif

   // timer1 - delay after receiving an unmap request in order
   //          to combine any additional unmaps that arrive within regs_unmap_timer1 usec
   always @*
     begin
        req_timer1_d      = req_timer1_q;
        req_timer1_done_d = req_timer1_done_q;
   
        if( req_fifo_valid && !req_timer1_done_q && tick1)
          begin
             req_timer1_d = req_timer1_q + 12'd1;
             if( (req_timer1_q == regs_unmap_timer1) )
               begin
                  req_timer1_done_d = 1'b1;
               end             
          end

        if( reset_timer || cmd_unmap_flush )
          begin
             req_timer1_d = 12'h0;
             req_timer1_done_d = 1'b0;
          end        
     end

   // timer2 - after sending an unmap request, delay the next unmap to avoid impacting read/write performance
  always @*
     begin
        req_timer2_d      = req_timer2_q;
        req_timer2_done_d = req_timer2_done_q;
   
        if( !req_timer2_done_q && tick1)
          begin
             req_timer2_d = req_timer2_q + 20'd1;
             if( req_timer2_q == regs_unmap_timer2 )
               begin
                  req_timer2_done_d = 1'b1;
               end             
          end

        if( reset_timer ||  cmd_unmap_flush)
          begin
             req_timer2_d = 20'h0;
             req_timer2_done_d =  cmd_unmap_flush;
          end      
       
     end

   
   // timer3 - let unmap commands flow if there's no read/write commands
   //          increment timer while ioidle=1
   //          reset if ioidle=0
   always @*
     begin
        req_timer3_d      = req_timer3_q;
        req_timer3_done_d = req_timer3_done_q;
   
        if( cmd_unmap_ioidle && !req_timer3_done_q && tick1)
          begin
             req_timer3_d = req_timer3_q + 12'd1;
             if( (req_timer3_q == regs_unmap_timer1) )
               begin
                  req_timer3_done_d = 1'b1;
               end             
          end

        if( reset_timer || cmd_unmap_flush || !cmd_unmap_ioidle )
          begin
             req_timer3_d = 12'h0;
             req_timer3_done_d = 1'b0;
          end        
     end
   
endmodule // nvme_sntl_unmap

    
