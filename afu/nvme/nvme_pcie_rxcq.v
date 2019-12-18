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

`timescale 1ns/1ns

//
// Completion reQuest interface 
//
// route DMA requests (MRd_64/MWr_64) from NVMe controller to one of:
// - Admin Q
// - I/O Q
// - SNTL (payload)
// 

module nvme_pcie_rxcq
  #(     
         parameter data_width = 145,
         parameter addr_width = 48,
         parameter bits_per_parity_bit = 8
         )
   ( 

     input                       clk,
     input                       reset,
     
     output reg                  pcie_adq_valid,
     output reg [data_width-1:0] pcie_adq_data, //    first data cycle = 
                                                 //    { addr_type[1:0], attr[2:0], tc[2:0], dcount[10:0], last_be[3:0], first_be[3:0], 
                                                 //        req_other, req_rd, req_wr, pcie_tag[7:0], addr_region[3:0],  addr[addr_width-1:0] }                                                     
     output reg                  pcie_adq_first, //   asserted with the first (header) cycle of the packet
     output reg                  pcie_adq_last, //    asserted with valid on the last cycle of the packet
     output reg                  pcie_adq_discard, // asserted with last if TLP should be discarded due to error
     input                       adq_pcie_pause, //   backpressure on frame boundary - asserted when less than 9 fifo entries available
     
     output reg                  pcie_ioq_valid,
     output reg [data_width-1:0] pcie_ioq_data,
     output reg                  pcie_ioq_first, 
     output reg                  pcie_ioq_last,
     output reg                  pcie_ioq_discard,
     input                       ioq_pcie_pause,
          
     output reg                  pcie_sntl_valid,
     output reg [data_width-1:0] pcie_sntl_data,
     output reg                  pcie_sntl_first, 
     output reg                  pcie_sntl_last,
     output reg                  pcie_sntl_discard,
     input                       sntl_pcie_pause, // backpressure on frame boundary (payload buffer has less than 128B free)
     input                       sntl_pcie_ready, // temp backpressure

     output reg                  pcie_sntl_wbuf_valid,
     output reg [data_width-1:0] pcie_sntl_wbuf_data,
     output reg                  pcie_sntl_wbuf_first, 
     output reg                  pcie_sntl_wbuf_last,
     output reg                  pcie_sntl_wbuf_discard,
     input                       sntl_pcie_wbuf_pause, // backpressure on frame boundary

     output reg                  pcie_sntl_adbuf_valid,
     output reg [data_width-1:0] pcie_sntl_adbuf_data,
     output reg                  pcie_sntl_adbuf_first, 
     output reg                  pcie_sntl_adbuf_last,
     output reg                  pcie_sntl_adbuf_discard,
     input                       sntl_pcie_adbuf_pause, // backpressure on frame boundary
     
     output reg                  pcie_regs_sisl_backpressure, // for timer2 control - stall when backpressured
     output reg                  pcie_regs_rxcq_backpressure, // for performance measurement
     output                [3:0] pcie_regs_rxcq_error,
     output reg            [7:0] pcie_sntl_rxcq_perf_events,

     output               [15:0] rxcq_dbg_events,
     output               [15:0] rxcq_dbg_user_events,
     output reg          [143:0] rxcq_dbg_user_tracedata,
     output reg                  rxcq_dbg_user_tracevalid,

     input                       regs_xx_tick1, // 1 cycle pulse every 1 us

     input                       regs_pcie_rxcq_errinj_valid,
     input                [19:0] regs_pcie_rxcq_errinj_delay,
     output reg                  pcie_regs_rxcq_errinj_ack,
     output reg                  pcie_regs_rxcq_errinj_active,

     //-------------------------------------------------------
     //  Transaction (AXIS) Interface
     //   - Completer reQuest interface
     //-------------------------------------------------------    
     input                       user_clk,
     input                       user_reset,
     input                       user_lnk_up,
     //-------------------------------------------------------    
   
     input               [127:0] m_axis_cq_tdata,
     input                 [3:0] m_axis_cq_tkeep,
     input                       m_axis_cq_tlast,
     output reg                  m_axis_cq_tready,
     input                [87:0] m_axis_cq_tuser,
     input                       m_axis_cq_tvalid,

     
     output                      rxcq_perror_ind, 
     output                [1:0] user_rxcq_perror_ind, 
     input                       regs_pcie_pe_errinj_valid,
     input                [15:0] regs_xxx_pe_errinj_decode, 
     input                       user_regs_wdata_pe_errinj_valid, // 1 cycle pulse in nvme domain
     input                       regs_wdata_pe_errinj_valid  // 1 cycle pulse in sislite domain
   
     );

   //-------------------------------------------------------    

`include "nvme_func.svh"

   // Parity error srlat 
   wire                          s1_perror; 
   wire                          rxcq_perror_int;
   wire                    [1:0] s1_uperror; 
   wire                    [1:0] rxcq_uperror_int;

   // set/reset/ latch for parity errors
   nvme_srlat#
     (.width(1))  irxcq_sr   
       (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(rxcq_perror_int));

   nvme_srlat#
     (.width(2))  irxcq_usr   
       (.clk(user_clk),.reset(user_reset),.set_in(s1_uperror),.hold_out(rxcq_uperror_int));

   assign rxcq_perror_ind = rxcq_perror_int;
   assign user_rxcq_perror_ind = rxcq_uperror_int;
   

   
   //-------------------------------------------------------
   // PSL clock domain logic
   //-------------------------------------------------------
   //localparam req_fifo_pwidth = $rtoi($ceil($itor(req_fifo_width)/bits_per_parity_bit));
   localparam req_fifo_width = data_width + 3;
   localparam req_fifo_pwidth = ceildiv(req_fifo_width-17, bits_per_parity_bit);
   //localparam data_pwidth =  $rtoi($ceil($itor(data_width)/bits_per_parity_bit));
   localparam data_pwidth = ceildiv(req_fifo_width-17, bits_per_parity_bit);

   //-------------------------------------------------------
   // read from async fifo and route MRd/MWr requests
   //-------------------------------------------------------

   (* mark_debug = "true" *)
   reg                        [1:0] s0_addr_type;
   (* mark_debug = "true" *)
   reg [data_width-data_pwidth-1:0] s0_data;  
   reg            [data_pwidth-1:0] s0_data_par;
   (* mark_debug = "true" *)
   reg             [addr_width-1:0] s0_addr;
   (* mark_debug = "true" *)
   reg                        [3:0] s0_last_be;
   (* mark_debug = "true" *)
   reg                        [3:0] s0_first_be;
   (* mark_debug = "true" *)
   reg                        [7:0] s0_tag;

   (* mark_debug = "true" *)
   reg                        [3:0] s0_addr_region;
   (* mark_debug = "true" *)
   reg                              s0_req_rd;
   (* mark_debug = "true" *)
   reg                              s0_req_wr;
   (* mark_debug = "true" *)
   reg                              s0_req_other;
   (* mark_debug = "true" *)
   reg                        [2:0] s0_tc;
   (* mark_debug = "true" *)
   reg                        [2:0] s0_attr;
   (* mark_debug = "true" *)
   reg                              s0_discard;
   (* mark_debug = "true" *)
   reg                              s0_first;
   (* mark_debug = "true" *)
   reg                              s0_last;
   (* mark_debug = "true" *)
   reg                       [10:0] s0_dcount;
   

   (* mark_debug = "true" *)
   reg                        [3:0] s0_state_q, s0_state_d;
   reg                              sisl_bp_q, sisl_bp_d;
   reg                              rxcq_bp_q, rxcq_bp_d;
   reg                        [1:0] s0_error_q, s0_error_d;
   
   // controls for fifo holding MWr TLPs going to SNTL and IOQ
   wire                          mwr_fifo_full;
   reg                           mwr_fifo_push;

   // controls for fifo holding MRd TLPs going to SNTL and IOQ
   wire                          mrd_fifo_full;
   reg                           mrd_fifo_push;

   // valids for TLPs going to ADQ or WBUF
   reg                           adq_val;
   reg                           wbuf_val;
   reg                           adbuf_val;

   // read interface for async crossing fifo
   // localparam req_fifo_width = data_width + 3;
   (* mark_debug = "true" *)
   reg                           req_rack; 
   (* mark_debug = "true" *)
   wire     [req_fifo_width-1:0] req_rdata;
   (* mark_debug = "true" *)
   wire                          req_rval;
   (* mark_debug = "true" *)
   wire                          req_rerr;

   // error inject for injecting long pauses
   reg                           errinj_pause;

   localparam S0SM_DEC    = 4'h1;
   localparam S0SM_ADQ    = 4'h2;
   localparam S0SM_WBUF   = 4'h3;
   localparam S0SM_ADBUF  = 4'h4;
   localparam S0SM_MWR    = 4'h5;
   localparam S0SM_OTHER  = 4'h6;
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             s0_state_q <= S0SM_DEC;
             sisl_bp_q  <= 1'b0;
             rxcq_bp_q  <= 1'b0;
             s0_error_q <= 2'b00;
          end
        else
          begin
             s0_state_q <= s0_state_d;
             sisl_bp_q  <= sisl_bp_d;
             rxcq_bp_q  <= rxcq_bp_d;
             s0_error_q <= s0_error_d;
          end
     end

   reg [6:0] cnt_event;

   always @*
     begin        
       
        req_rack                     = 1'b0;
        adq_val                      = 1'b0;
        wbuf_val                     = 1'b0;
        adbuf_val                    = 1'b0;
        mrd_fifo_push                = 1'b0;
        mwr_fifo_push                = 1'b0;
        s0_state_d                   = s0_state_q;
        s0_error_d                   = 2'b00;
        cnt_event                    = 7'h0;
        rxcq_bp_d                    = 1'b0;
        pcie_regs_rxcq_backpressure  = rxcq_bp_q;
        
        // unpack
        { s0_data_par[data_pwidth-1:0],
          s0_discard, 
          s0_first, 
          s0_last, 
          s0_data }  = req_rdata;

        // only valid in S0SM_DEC stage
        { s0_addr_type, s0_attr, s0_tc, s0_dcount, s0_last_be, s0_first_be, s0_req_other, s0_req_rd, s0_req_wr, s0_tag, s0_addr_region, s0_addr} = req_rdata[req_fifo_width - req_fifo_pwidth - 1:0];

        case(s0_state_q)
          S0SM_DEC:
            begin
               if( req_rval & !errinj_pause )
                 begin
                    if( s0_first )
                      begin
                         
                         if( s0_req_other )
                           begin
                              // not a memory read or write
                              cnt_event[0] = 1'b1;
                              req_rack = 1'b1;
                              if( ~s0_last )
                                begin                                   
                                   s0_state_d = S0SM_OTHER;
                                end                         
                           end
                         else
                           begin
                              case(s0_addr_region)
                                ENUM_ADDR_ADQ:
                                  begin
                                     if( ~adq_pcie_pause )                                  
                                       begin
                                          adq_val  = 1'b1;
                                          req_rack = 1'b1;
                                          if( ~s0_last )
                                            begin
                                               s0_state_d = S0SM_ADQ;
                                            end
                                       end           
                                  end                                
                                ENUM_ADDR_WBUF:
                                  begin
                                     if( ~sntl_pcie_wbuf_pause )                                
                                       begin
                                          wbuf_val  = 1'b1;
                                          req_rack = 1'b1;
                                          if( ~s0_last )
                                            begin
                                               s0_state_d = S0SM_WBUF;
                                            end
                                       end         
                                  end
                                ENUM_ADDR_INTN:
                                  begin
                                     if( ~sntl_pcie_adbuf_pause )                                
                                       begin
                                          adbuf_val  = 1'b1;
                                          req_rack = 1'b1;
                                          if( ~s0_last )
                                            begin
                                               s0_state_d = S0SM_ADBUF;
                                            end
                                       end         
                                  end
                           
                                default:
                                  // ENUM_ADDR_SISL,ENUM_ADDR_IOQ:
                                  // IOQ is included with SISL for ordering
                                  begin
                                     // if address doesn't map to SISL or INTN, sntl will respond with unsupported request or deadbeef completion                                     
                                     if( (!mrd_fifo_full && s0_req_rd) ||
                                         (!mwr_fifo_full && s0_req_wr))
                                       begin
                                          cnt_event[1] = s0_addr_region==ENUM_ADDR_SISL;
                                          cnt_event[2] = s0_addr_region==ENUM_ADDR_INTN;
                                          cnt_event[3] = ~cnt_event[1] & ~cnt_event[2];
                                          
                                          req_rack = 1'b1;
                                          
                                          if( s0_req_rd )
                                            begin                                              
                                               if( ~s0_last )
                                                 begin
                                                    // error - MRd should be 1 cycle
                                                    s0_error_d[0] = 1'b1;
                                                    s0_state_d = S0SM_OTHER;
                                                 end
                                               else
                                                 begin
                                                     mrd_fifo_push = 1'b1;
                                                 end
                                            end
                                          else
                                            begin
                                               mwr_fifo_push = 1'b1;
                                               if( ~s0_last )
                                                 begin
                                                    s0_state_d = S0SM_MWR;
                                                 end
                                            end                                                                          
                                       end   
                                     else
                                       begin                                          
                                          cnt_event[4] = 1'b1;                                         
                                       end                                
                                  end
                                
                              endcase
                           end
                      end // if ( s0_first )
                    else
                      begin
                         // error - first was expected                      
                         // pop from fifo until first
                         s0_error_d[1] = 1'b1;
                         cnt_event[5] = 1'b1;
                         req_rack = 1'b1;
                      end // else: !if( s0_first )     
                 end   
            end
          S0SM_ADQ:
            begin
               if( req_rval )
                 begin
                    adq_val  = 1'b1;
                    req_rack = 1'b1;
                    if( s0_last )
                      begin
                         s0_state_d = S0SM_DEC;
                      end
                 end
            end
          S0SM_WBUF:
            begin
               if( req_rval )
                 begin
                    wbuf_val   = 1'b1;
                    req_rack = 1'b1;
                    if( s0_last )
                      begin
                         s0_state_d = S0SM_DEC;
                      end
                 end
            end          
          S0SM_ADBUF:
            begin
               if( req_rval )
                 begin
                    adbuf_val   = 1'b1;
                    req_rack = 1'b1;
                    if( s0_last )
                      begin
                         s0_state_d = S0SM_DEC;
                      end
                 end
            end          
          S0SM_MWR:
            begin
               if( !mwr_fifo_full && req_rval )
                 begin
                    mwr_fifo_push = 1'b1;
                    req_rack = 1'b1;
                    if( s0_last )
                      begin
                         s0_state_d = S0SM_DEC;
                      end
                 end
            end          
          S0SM_OTHER:
            begin
               // not a valid read or write command 
               if( req_rval )
                 begin                   
                    req_rack = 1'b1;
                    if( s0_last )
                      begin
                         cnt_event[6] = 1'b1;
                         s0_state_d = S0SM_DEC;
                      end
                 end
            end
          default:
            begin               
               s0_state_d = S0SM_DEC;
            end
        endcase // case (s0_state_q)

        
        rxcq_bp_d                = req_rval & ~req_rack;
                          
        // outputs
        
        pcie_adq_valid           = adq_val;
        pcie_adq_data            = {s0_data_par,s0_data};
        pcie_adq_first           = s0_first;
        pcie_adq_last            = s0_last;
        pcie_adq_discard         = s0_discard;

        pcie_sntl_wbuf_valid     = wbuf_val;
        pcie_sntl_wbuf_data      = {s0_data_par,s0_data};
        pcie_sntl_wbuf_first     = s0_first;
        pcie_sntl_wbuf_last      = s0_last;
        pcie_sntl_wbuf_discard   = s0_discard;
        
        pcie_sntl_adbuf_valid    = adbuf_val;
        pcie_sntl_adbuf_data     = {s0_data_par,s0_data};
        pcie_sntl_adbuf_first    = s0_first;
        pcie_sntl_adbuf_last     = s0_last;
        pcie_sntl_adbuf_discard  = s0_discard;
     end // always @ *

   //-------------------------------------------------------
   // error inject pause
   //-------------------------------------------------------

   reg [19:0] errinj_timer_q, errinj_timer_d;
   reg        errinj_ack_q, errinj_ack_d;
   reg        errinj_active_q, errinj_active_d;
   reg        errinj_pause_q, errinj_pause_d;
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             errinj_timer_q  <= 20'h0;
             errinj_ack_q    <= 1'b0;
             errinj_active_q <= 1'b0;
             errinj_pause_q  <= 1'b0;
          end
        else
          begin
             errinj_timer_q  <= errinj_timer_d;
             errinj_ack_q    <= errinj_ack_d;
             errinj_active_q <= errinj_active_d;
             errinj_pause_q  <= errinj_pause_d;
          end
     end

   always @*
     begin
        // start a pause timer using us tick when errinj is valid
        
        errinj_timer_d                = errinj_timer_q;
        errinj_pause_d                = errinj_pause_q;
        errinj_ack_d                  = 1'b0;
        errinj_active_d               = req_rack;

        // load
        if( regs_pcie_rxcq_errinj_valid && !errinj_pause_q && ~errinj_ack_q)
          begin
             errinj_timer_d = regs_pcie_rxcq_errinj_delay;
             errinj_pause_d = 1'b1;
          end

        // count down
        if( errinj_timer_q!=20'h0 && regs_xx_tick1 && s0_state_q==S0SM_DEC && req_rval )
          begin
             errinj_timer_d = errinj_timer_q - 20'h1;
          end        

        // end
        if( errinj_pause_q && errinj_timer_q==20'h0 )
          begin
             errinj_pause_d = 1'b0;
             errinj_ack_d   = 1'b1;
          end                     
        
        errinj_pause                  = errinj_pause_q;
        pcie_regs_rxcq_errinj_ack     = errinj_ack_q;
        pcie_regs_rxcq_errinj_active  = errinj_active_q;
        
     end
   

   //-------------------------------------------------------
   // buffer requests going to SNTL and IOQ
   //-------------------------------------------------------
   // include IOQ to keep completions ordered behind payload
   // allow MRd to pass MWr


   wire                      mwr_fifo1_valid;
   wire [req_fifo_width-1:0] mwr_fifo1_dout;
   
   wire                      mwr_fifo2_full;
   wire                      mwr_fifo2_push;   
   wire                      mwr_fifo2_valid;
   wire [req_fifo_width-1:0] mwr_fifo2_dout;
   
   wire                      mwr_fifo3_full;
   wire                      mwr_fifo3_push;   
   
   wire                      mwr_fifo_valid;
   wire [req_fifo_width-1:0] mwr_fifo_dout;
   wire                      mwr_fifo_pop;   

   // for timing, break up into multiple fifos
   
   // this fifo is sized to hold the payload, header, and ICQ write for every outstanding I/O Read
   // the full output should not go active unless the number reads exceeds # of read credits

   //   9 cycles per 128B MWr packet
   // x 32 packets per 4KB I/O read
   // + 2 cycles for ICQ MWr
   // = 290 cycles per 4KB I/O read
   //
   // 4096 * 12 / 290 = 169 == # of read credits
   
   
   nvme_fifo_ultra#(.width(req_fifo_width), .uram_width(144), 
              .words(4096*4),   
              .almost_full_thresh(0)
              ) mwr_fifo1
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        mwr_fifo_push ),
      .din(         req_rdata ),
      
      .dval(        mwr_fifo1_valid ), 
      .pop(         mwr_fifo2_push ),
      .dout(        mwr_fifo1_dout ),
      .full(        mwr_fifo_full ), 
      .almost_full(          ), 
      .used(                 ));

   assign mwr_fifo2_push = mwr_fifo1_valid & ~mwr_fifo2_full;


   nvme_fifo_ultra#(.width(req_fifo_width), .uram_width(144), 
              .words(4096*4),   
              .almost_full_thresh(0)
              ) mwr_fifo2
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        mwr_fifo2_push ),
      .din(         mwr_fifo1_dout ),

      .dval(        mwr_fifo2_valid ), 
      .pop(         mwr_fifo3_push ),
      .dout(        mwr_fifo2_dout ),
      .full(        mwr_fifo2_full ), 
      .almost_full(          ), 
      .used(                 ));

   assign mwr_fifo3_push = mwr_fifo2_valid & ~mwr_fifo3_full;

   nvme_fifo_ultra#(.width(req_fifo_width), .uram_width(144), 
              .words(4096*4),   
              .almost_full_thresh(0)
              ) mwr_fifo3
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        mwr_fifo3_push ),
      .din(         mwr_fifo2_dout ),
      
      .dval(        mwr_fifo_valid ), 
      .pop(         mwr_fifo_pop ),
      .dout(        mwr_fifo_dout ),
      .full(        mwr_fifo3_full ), 
      .almost_full(          ), 
      .used(                 ));

   
   wire                      mrd_fifo_valid;
   reg                       mrd_fifo_taken;
   wire [req_fifo_width-1:0] mrd_fifo_dout;
   
   // sized for max 256 non-posted requests   
   nvme_fifo#(.width(req_fifo_width), 
              .words(256), // max non-posted
              .almost_full_thresh(0)
              ) mrd_fifo
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        mrd_fifo_push ),
      .din(         req_rdata ),
      
      .dval(        mrd_fifo_valid ), 
      .pop(         mrd_fifo_taken ),
      .dout(        mrd_fifo_dout ),
      .full(        mrd_fifo_full ), 
      .almost_full(          ), 
      .used(                 ));

   // timing stage
   wire                      s1_mwr_ready;
   wire [req_fifo_width-1:0] s1_mwr_data;
   wire                      s1_mwr_valid;
   reg                       s2_mwr_ready;
   nvme_pl_burp#(.width(req_fifo_width), .stage(1)) s1_mwr
     (.clk(clk),.reset(reset),
      .valid_in(mwr_fifo_valid),
      .data_in(mwr_fifo_dout),
      .ready_out(s1_mwr_ready),
      
      .data_out(s1_mwr_data),
      .valid_out(s1_mwr_valid),
      .ready_in(s2_mwr_ready)
      );
   assign mwr_fifo_pop = mwr_fifo_valid & s1_mwr_ready;
   
   //-------------------------------------------------------
   // decode header and route to either SNTL or IOQ
   
   reg                 [1:0] s2_addr_type;
   reg      [data_width-1:0] s2_data;
   //reg     [data_pwidth-1:0] s2_data_par;   
   reg      [addr_width-1:0] s2_addr;
   reg                 [3:0] s2_last_be;
   reg                 [3:0] s2_first_be;
   reg                 [7:0] s2_tag;
   reg                 [3:0] s2_addr_region;
   reg                       s2_req_rd;
   reg                       s2_req_wr;
   reg                       s2_req_other;
   reg                 [2:0] s2_tc;
   reg                 [2:0] s2_attr;
   reg                       s2_discard;
   reg                       s2_first;
   reg                       s2_last;
   reg                [10:0] s2_dcount;
   

   reg                 [3:0] s2_state_q, s2_state_d;
   reg                 [1:0] s2_error_q, s2_error_d;

   
   localparam s2_rr_width=2;
   reg [s2_rr_width-1:0] s2_rr_valid, s2_rr_gnt;
   reg [s2_rr_width-1:0] s2_rr_q, s2_rr_d;
   reg  [31:s2_rr_width] s2_rr_noused;


   localparam S1SM_DEC    = 4'h1;
   localparam S1SM_IOQ    = 4'h2;
   localparam S1SM_SNTL   = 4'h3;
  
   reg                 rxcq_pe_inj_d,rxcq_pe_inj_q;
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             s2_state_q    <= S1SM_DEC;           
             s2_error_q    <= 2'b00;
             s2_rr_q       <= one[s2_rr_width-1:0];
             rxcq_pe_inj_q <= 1'b0;
          end
        else
          begin
             s2_state_q    <= s2_state_d;           
             s2_error_q    <= s2_error_d;
             s2_rr_q       <= s2_rr_d;
             rxcq_pe_inj_q <= rxcq_pe_inj_d;
          end
     end

   reg                      req_write;

   always @*
     begin  
        rxcq_pe_inj_d = rxcq_pe_inj_q;
        
        if (regs_wdata_pe_errinj_valid  & regs_pcie_pe_errinj_valid & regs_xxx_pe_errinj_decode[15:8] == 4'h6)
          begin
             rxcq_pe_inj_d  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
          end 
        if (rxcq_pe_inj_q & req_rval)
          rxcq_pe_inj_d = 1'b0;
     end  


   nvme_pcheck#(.bits_per_parity_bit(8), .width(req_fifo_width-req_fifo_pwidth)) cq2_pchrck
     (.data({req_rdata[req_fifo_width-1-req_fifo_pwidth:1],(req_rdata[0]^rxcq_pe_inj_q)}),
      .oddpar(1'b1),
      .datap(req_rdata[req_fifo_width-1:req_fifo_width-req_fifo_pwidth]),
      .check(req_rval),
      .parerr(s1_perror)        // clk
      );
   
   reg ioq_val;
   reg sntl_val;
   reg s2_fifo_valid;
   reg s2_fifo_taken;
   reg s2_mrd_gnt, s2_mwr_gnt;


   always @*
     begin        
       
        sntl_val    = 1'b0;
        ioq_val     = 1'b0;

        sisl_bp_d                    = 1'b0;
        pcie_regs_sisl_backpressure  = sisl_bp_q;
        
        s2_state_d  = s2_state_q;      
        s2_error_d  = 2'b00;

        // arbitration
        s2_rr_valid = { mrd_fifo_valid, s1_mwr_valid };        
        {s2_rr_noused, s2_rr_gnt} = roundrobin({zero[31:s2_rr_width],s2_rr_valid}, {zero[31:s2_rr_width], s2_rr_q} );
        if( s2_state_q==S1SM_DEC && s2_rr_valid!=zero[s2_rr_width-1:0] )
          begin            
             s2_rr_d = s2_rr_gnt;
          end
        else
          begin
             s2_rr_d = s2_rr_q;             
          end
        { s2_mrd_gnt, s2_mwr_gnt } = s2_rr_d;
         
        s2_fifo_valid  = (s2_rr_valid & s2_rr_d)!=zero[s2_rr_width-1:0];
        s2_fifo_taken = 1'b0;

        if( s2_mrd_gnt )
          begin
             // unpack
             {  s2_data[data_width-1:data_width-data_pwidth],
               s2_discard, 
               s2_first, 
               s2_last, 
               s2_data[data_width-data_pwidth-1:0] }  = mrd_fifo_dout;
          end
        else
          begin
             { s2_data[data_width-1:data_width-data_pwidth],
               s2_discard, 
               s2_first, 
               s2_last, 
               s2_data[data_width-data_pwidth-1:0] }  = s1_mwr_data;
          end

        // only valid in RDSM_DEC stage
        { s2_addr_type, s2_attr, s2_tc, s2_dcount, s2_last_be, s2_first_be, s2_req_other, s2_req_rd, s2_req_wr, s2_tag, s2_addr_region, s2_addr} = s2_data;

        case(s2_state_q)
          S1SM_DEC:
            begin               
               if( s2_fifo_valid  )
                 begin
                    if( s2_first )
                      begin                         
                         if( s2_addr_region==ENUM_ADDR_IOQ )                           
                           begin
                              if( ~ioq_pcie_pause )                                  
                                begin
                                   ioq_val        = 1'b1;
                                   s2_fifo_taken  = 1'b1;
                                   if( ~s2_last )
                                     begin
                                        // if TLP is a MRd, it should be 1 cycle
                                        if( ~s2_mrd_gnt )
                                          begin                                             
                                             s2_state_d = S1SM_IOQ;
                                          end
                                        else
                                          begin
                                             s2_error_d[0] = 1'b1;
                                          end                                        
                                     end
                                end           	
                           end                                                      
                         else
                           // ENUM_ADDR_SISL,ENUM_ADDR_INTN,ENUM_ADDR_IOQ:
                           begin
                              if( ~sntl_pcie_pause & sntl_pcie_ready )
                                begin                                          
                                   sntl_val = 1'b1;
                                   s2_fifo_taken = 1'b1;
                                   if( ~s2_last )
                                     begin
                                        if( ~s2_mrd_gnt )
                                          begin
                                             s2_state_d = S1SM_SNTL;
                                          end
                                        else
                                          begin
                                             s2_error_d[0] = 1'b1;
                                          end                                                              
                                     end                                   
                                end
                              else
                                begin
                                   sisl_bp_d = sntl_pcie_pause;
                                end
                           end
                      end // if ( s2_first )
                    else
                      begin
                         // error - first was expected                      
                         // pop from fifo until first
                         s2_error_d[1] = 1'b1;
                         s2_fifo_taken = 1'b1;
                      end // else: !if( s2_first )     
                 end //        
            end
          S1SM_IOQ:
            begin
               if( s2_fifo_valid )
                 begin
                    ioq_val        = 1'b1;
                    s2_fifo_taken  = 1'b1;
                    if( s2_last )
                      begin
                         s2_state_d = S1SM_DEC;
                      end
                 end
            end
          S1SM_SNTL:
            begin
               if( s2_fifo_valid & sntl_pcie_ready )
                 begin
                    sntl_val   = 1'b1;
                    s2_fifo_taken = 1'b1;
                    if( s2_last )
                      begin
                         s2_state_d = S1SM_DEC;
                      end
                 end
            end          
       
          default:
            begin               
               s2_state_d = S1SM_DEC;
            end
        endcase // case (s2_state_q)
        
        mrd_fifo_taken = s2_fifo_taken & s2_mrd_gnt;
        s2_mwr_ready = s2_fifo_taken & s2_mwr_gnt;
        
        pcie_ioq_valid    = ioq_val;
        pcie_ioq_data     = {s2_data};
        pcie_ioq_first    = s2_first;
        pcie_ioq_last     = s2_last;
        pcie_ioq_discard  = s2_discard;

        pcie_sntl_valid    = sntl_val;
        pcie_sntl_data     = {s2_data};
        pcie_sntl_first    = s2_first;
        pcie_sntl_last     = s2_last;
        pcie_sntl_discard  = s2_discard;

     end // always @ *
   
   //-------------------------------------------------------
   // debug counters
   //-------------------------------------------------------
   reg [15:0] cnt_event_q;
   
   always @(posedge clk)
     begin
        if( reset )
          begin
             cnt_event_q <= 16'h0;           
          end
        else
          begin
             cnt_event_q[0] <= req_rack;
             cnt_event_q[1] <= req_rack & s0_first;
             cnt_event_q[2] <= s2_fifo_taken & s2_first & sntl_val & s2_req_rd;
             cnt_event_q[3] <= s2_fifo_taken & s2_first & ioq_val & s2_req_rd;
             cnt_event_q[4] <= req_rack & s0_first & adq_val & s0_req_rd;
             cnt_event_q[5] <= s2_fifo_taken & s2_first & sntl_val;
             cnt_event_q[6] <= s2_fifo_taken & s2_first & ioq_val;
             cnt_event_q[7] <= req_rack & s0_first & adq_val;
             cnt_event_q[8] <= rxcq_bp_q; // req_rack & s0_discard;
             cnt_event_q[9] <= mrd_fifo_valid & ~mrd_fifo_taken;
             cnt_event_q[10] <= s1_mwr_valid & ~s1_mwr_ready;
             cnt_event_q[11] <= cnt_event[1];
             cnt_event_q[12] <= cnt_event[2];
             cnt_event_q[13] <= cnt_event[3];
             cnt_event_q[14] <= cnt_event[4];
             cnt_event_q[15] <= cnt_event[6];
             // cnt_event_q[15:11] <= cnt_event[6:0];
         
           end  
     end
   
   assign rxcq_dbg_events = cnt_event_q;

   assign pcie_regs_rxcq_error = s2_error_q & s0_error_q;


   always @*
     begin
        pcie_sntl_rxcq_perf_events = '0;
        pcie_sntl_rxcq_perf_events[0] = mwr_fifo_push;
        pcie_sntl_rxcq_perf_events[1] = mwr_fifo_pop;
     end
   
   //-------------------------------------------------------
   // Async fifo for domain crossing
   //-------------------------------------------------------
   
   reg [req_fifo_width-1:0] req_wdata;
   wire                     req_wfull;
   wire                     req_wrstbusy;

   
   // sized at 512 entries to match xilinx BRAM size
   // - 128B MWr is 9 entries -> max 56 packets (7KB)
   // - MRd is 1 entry
   //nvme_async_fifo#
   //  ( .width(req_fifo_width),
   //    .awidth(9)               // 512 entries

   nvme_cdc_fifo_xil#(.width(req_fifo_width)
       ) req_fifo
       (
        // read
        .rclk                           (clk),
        .rreset                         (reset),
        .rack                           (req_rack),
        .rdata                          (req_rdata),
        .rval                           (req_rval),
        //.rerr                           (req_rerr),         
        .runderflow                     (req_rerr),
        .rsbe                           (),
        .rue                            (),
        .rempty                         (),
        .rrstbusy                       (),

        // write
        .wclk                           (user_clk),
        .wreset                         (user_reset),
        .write                          (req_write),
        .wdata                          (req_wdata),
        .wfull                          (req_wfull),
        .wrstbusy                       (req_wrstbusy),
        //.wafull	                        ()
        .werror                         ()
        );

   
   
   //-------------------------------------------------------
   // NVME clock domain logic
   //-------------------------------------------------------

   reg                 [1:0] addr_type;
   reg      [addr_width-1:0] addr;
   reg                 [3:0] last_be;
   reg                 [3:0] first_be;
   reg                 [7:0] tag;
   reg                 [3:0] addr_region;
   reg                       req_rd;
   reg                       req_wr;
   reg                       req_other;
   reg                 [2:0] tc;
   reg                 [2:0] attr;
   reg                       discard;
   reg                       first;
   reg                       last;
   reg                [10:0] dcount;

   reg  [req_fifo_width-1:0] s0u_wdata;
   wire    [data_pwidth-1:0] s0u_wdata_par;
   wire    [data_pwidth-1:0] m_axis_cq_tdata_par;
   reg                       s0u_valid;
   wire                      s0u_ready;
   
   wire [req_fifo_width-1:0] s1u_wdata;
   wire                      s1u_valid;
   reg                       s1u_ready;   

   always @*
     begin
        
            
        // 1st cycle descriptor fields
        addr_type             = m_axis_cq_tdata[1:0];  
        addr[1:0]             = 2'b00;
        addr[addr_width-1:2]  = m_axis_cq_tdata[addr_width-1:2];  
        addr_region           = m_axis_cq_tdata[3+addr_width:addr_width];      
        dcount                = m_axis_cq_tdata[74:64];
        req_rd                = m_axis_cq_tdata[78:75] == 4'h0;  // memory read
        req_wr                = m_axis_cq_tdata[78:75] == 4'h1;  // memory write
        req_other             = ~(req_rd|req_wr);     
        tag                   = m_axis_cq_tdata[103:96];
        tc                    = m_axis_cq_tdata[123:121];
        attr                  = m_axis_cq_tdata[126:124];
        first                 = m_axis_cq_tuser[40]; // sop
        last                  = m_axis_cq_tlast;
        first_be              = m_axis_cq_tuser[3:0]; 
        last_be               = m_axis_cq_tuser[7:4];
        discard               = m_axis_cq_tuser[41]; // discontinue - asserted with last
                
        if( first )
          begin
             s0u_wdata[data_width-data_pwidth-1:0]  = { addr_type, attr, tc, dcount, last_be, first_be, req_other, req_rd, req_wr, tag, addr_region, addr};
             s0u_wdata[data_width+2-data_pwidth:data_width-data_pwidth] = {discard,first,last};
             s0u_wdata[data_width+2:data_width+3-data_pwidth]  = s0u_wdata_par;
          end
        else
          begin
             s0u_wdata  = {m_axis_cq_tdata_par, discard, first, last, m_axis_cq_tdata};
          end
             
        s0u_valid          = m_axis_cq_tvalid;
        m_axis_cq_tready  = s0u_ready;       
     end

   
   reg [1:0] user_rxcq_pe_inj_q , user_rxcq_pe_inj_d;

   //rblack parity check/regen
   nvme_pcheck#(.bits_per_parity_bit(8), .width(128)) cq0_pchrck
     (.data({m_axis_cq_tdata[127:1],(m_axis_cq_tdata[0]^user_rxcq_pe_inj_q[0])}),
      .oddpar(1'b1),
      .datap(m_axis_cq_tuser[68:53]),
      .check(m_axis_cq_tvalid),
      .parerr(s1_uperror[1])         // user_clk 
      );

   nvme_pgen#(.bits_per_parity_bit(8), .width(req_fifo_width-req_fifo_pwidth)) cq0_pgen
     (.data(s0u_wdata[req_fifo_width-req_fifo_pwidth-1:0]),
      .oddpar(1'b1),
      .datap(s0u_wdata_par)
      );

   nvme_pgen#(.bits_per_parity_bit(8), .width(req_fifo_width-req_fifo_pwidth)) m_axis_cq_tdata_pgen
     (.data({discard, first, last, m_axis_cq_tdata}),
      .oddpar(1'b1),
      .datap(m_axis_cq_tdata_par)
      );


   nvme_pl_burp#(.width(req_fifo_width), .stage(1)) s0u_pl 
     (.clk(user_clk),.reset(user_reset),
      .valid_in(s0u_valid),
      .data_in(s0u_wdata),
      .ready_out(s0u_ready),
                 
      .data_out(s1u_wdata),
      .valid_out(s1u_valid),
      .ready_in(s1u_ready)
      ); 

   always @*
     begin
        req_wdata = s1u_wdata;
        req_write = s1u_valid & ~req_wfull & ~req_wrstbusy;
        s1u_ready = ~req_wfull & ~req_wrstbusy;
     end

   nvme_pcheck#(.bits_per_parity_bit(8), .width(req_fifo_width-req_fifo_pwidth)) cq1_pchrck
     (.data({req_wdata[req_fifo_width-1-req_fifo_pwidth:1],(req_wdata[0]^user_rxcq_pe_inj_q[1])}),
      .oddpar(1'b1),
      .datap(req_wdata[req_fifo_width-1:req_fifo_width-req_fifo_pwidth]),
      .check(req_write),
      .parerr(s1_uperror[0])  
      );
  
   // debug counts
   reg [15:0] cnt_event_user_q;
   
   always @(posedge user_clk)
     begin
        if( user_reset )
          begin
             cnt_event_user_q <= 16'h0;  
             user_rxcq_pe_inj_q <= 2'b0;         
          end
        else
          begin
             cnt_event_user_q[0] <= m_axis_cq_tvalid &  m_axis_cq_tready &  first;
             cnt_event_user_q[1] <= m_axis_cq_tvalid &  m_axis_cq_tready &  first & req_rd;
             cnt_event_user_q[2] <= m_axis_cq_tvalid &  m_axis_cq_tready;
             cnt_event_user_q[3] <= req_write;
             cnt_event_user_q[4] <= req_write & req_wfull;
             cnt_event_user_q[5] <= m_axis_cq_tvalid & ~m_axis_cq_tready;
             user_rxcq_pe_inj_q  <= user_rxcq_pe_inj_d;
           end  
     end

   assign rxcq_dbg_user_events = cnt_event_user_q;

   always @*
     begin  
        user_rxcq_pe_inj_d = user_rxcq_pe_inj_q;
        
        if (user_regs_wdata_pe_errinj_valid  & regs_pcie_pe_errinj_valid & regs_xxx_pe_errinj_decode[15:8] == 4'h6)
          begin
             user_rxcq_pe_inj_d[0]  = (regs_xxx_pe_errinj_decode[3:0]==4'h1);
             user_rxcq_pe_inj_d[1]  = (regs_xxx_pe_errinj_decode[3:0]==4'h2);
          end 
        if (user_rxcq_pe_inj_q[0] & m_axis_cq_tvalid)
          user_rxcq_pe_inj_d[0] = 1'b0;
        if (user_rxcq_pe_inj_q[1] & req_write)
          user_rxcq_pe_inj_d[1] = 1'b0;
     end  
   
   always @(posedge user_clk)
     begin
        rxcq_dbg_user_tracedata  <= {req_rd, first, last, discard, first_be, last_be, m_axis_cq_tkeep, m_axis_cq_tdata};
        rxcq_dbg_user_tracevalid <= m_axis_cq_tvalid & m_axis_cq_tready;        
     end
   
   
endmodule

