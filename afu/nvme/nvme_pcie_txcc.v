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

// Completer Completion Interface
//
// Send completions for DMA reads back to NVMe controller
// - adq:  Admin Submission Q entry data
// - ioq:  I/O Submission Q entry data
// - sntl: payload for SCSI write commands
//

// includes clock domain crossing fifo


module nvme_pcie_txcc
  #(
    parameter data_width = 145,
    parameter bits_per_parity_bit = 8
  )
  (
   input              clk,
   input              reset,
   
   input      [144:0] adq_pcie_cc_data,
   input              adq_pcie_cc_first,
   input              adq_pcie_cc_last,
   input              adq_pcie_cc_discard,
   input              adq_pcie_cc_valid,
   output reg         pcie_adq_cc_ready,

   input      [144:0] ioq_pcie_cc_data,
   input              ioq_pcie_cc_first,
   input              ioq_pcie_cc_last,
   input              ioq_pcie_cc_discard,
   input              ioq_pcie_cc_valid,
   output reg         pcie_ioq_cc_ready,

   
   input      [144:0] sntl_pcie_cc_data,
   input              sntl_pcie_cc_first,
   input              sntl_pcie_cc_last,
   input              sntl_pcie_cc_discard,
   input              sntl_pcie_cc_valid,
   output reg         pcie_sntl_cc_ready,

   input      [144:0] sntl_pcie_wbuf_cc_data,
   input              sntl_pcie_wbuf_cc_first,
   input              sntl_pcie_wbuf_cc_last,
   input              sntl_pcie_wbuf_cc_discard,
   input              sntl_pcie_wbuf_cc_valid,
   output reg         pcie_sntl_wbuf_cc_ready,
   
   input      [144:0] sntl_pcie_adbuf_cc_data,
   input              sntl_pcie_adbuf_cc_first,
   input              sntl_pcie_adbuf_cc_last,
   input              sntl_pcie_adbuf_cc_discard,
   input              sntl_pcie_adbuf_cc_valid,
   output reg         pcie_sntl_adbuf_cc_ready,

   output      [15:0] txcc_dbg_events,
   output      [15:0] txcc_dbg_user_events,
   output reg [143:0] txcc_dbg_user_tracedata,
   output reg         txcc_dbg_user_tracevalid,

   //-------------------------------------------------------
   //  Transaction (AXIS) Interface
   //   Completer Completion interface
   //-------------------------------------------------------    
   input              user_clk,
   input              user_reset,
   input              user_lnk_up,
  
    //-------------------------------------------------------     
   output reg [127:0] s_axis_cc_tdata,
   output reg   [3:0] s_axis_cc_tkeep,
   output reg         s_axis_cc_tlast,
   input        [3:0] s_axis_cc_tready,
   output reg  [32:0] s_axis_cc_tuser,
   output reg         s_axis_cc_tvalid,
   output       [2:0] txcc_perror_ind,
   output       [1:0] user_txcc_perror_ind,
   input              regs_pcie_pe_errinj_valid,
   input       [15:0] regs_xxx_pe_errinj_decode, 
   input              user_regs_wdata_pe_errinj_valid, // 1 cycle pulse in nvme domain  
   input              regs_wdata_pe_errinj_valid  // 1 cycle pulse in sislite domain
   

);

`include "nvme_func.svh"

   wire         [2:0] s1_perror;
   wire         [2:0] txcc_perror_int;

   wire         [1:0] s1_uperror;
   wire         [1:0] txcc_uperror_int;

   // set/reset/ latch for parity errors 
   nvme_srlat#
     (.width(3))  itxcc_sr   
       (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(txcc_perror_int));

   nvme_srlat#
     (.width(2))  itxcc_usr   
       (.clk(user_clk),.reset(user_reset),.set_in(s1_uperror),.hold_out(txcc_uperror_int));

   assign txcc_perror_ind = txcc_perror_int;

   assign user_txcc_perror_ind = txcc_uperror_int;

   
   //-------------------------------------------------------
   // PSL clock domain logic
   //-------------------------------------------------------
   localparam cpl_fifo_width = data_width + 3;
   localparam cpl_fifo_pwidth = 17;
  
   (* mark_debug = "false" *) reg  [cpl_fifo_width-1:0] cpl_wdata;
   (* mark_debug = "false" *) reg                       cpl_write;
   (* mark_debug = "false" *) wire                      cpl_wfull;


   reg                       wr_last;

   // header - cycle 0 of *_pcie_data
   // { addr_type[1:0],     // from original request
   //   attr[2:0],          // from original request
   //    tc[2:0],           // from original request
   //    byte_count[12:0],  // remaining bytes to be transferred including this packet
   //    cpl_status[2:0],   // 0x0 - success; 0x1 - unsupported request; 0x2 - completer abort
   //    cpl_dwords[10:0],  // number of dwords in this packet
   //    pcie_tag[7:0],     // from original request
   //    lower_addr[6:0] }  // least significant 7b of byte address of this packet
   localparam hdr_width=2+3+3+13+3+11+8+7;


   //-------------------------------------------------------
   // arbitration

   localparam cpl_rr_width=5;
   reg [cpl_rr_width-1:0] cpl_rr_valid, cpl_rr_ready;
   reg [cpl_rr_width-1:0] cpl_rr_q, cpl_rr_d;
   reg [cpl_rr_width-1:0] cpl_rr_gnt, cpl_rr_active; 
   reg [cpl_rr_width-1:0] cpl_rr_gnt_q, cpl_rr_gnt_d;
   reg  [31:cpl_rr_width] cpl_rr_noused;

   reg                    ioq_gnt, adq_gnt, sntl_gnt, wbuf_gnt, adbuf_gnt;

   reg              [3:0] wr_state_q, wr_state_d;
   localparam WR_IDLE = 4'h1;
   localparam WR_BUSY = 4'h2;
      
   reg          [2:0]        txcc_pe_inj_d,txcc_pe_inj_q;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             cpl_rr_q      <= one[cpl_rr_width-1:0];
             cpl_rr_gnt_q  <= zero[cpl_rr_width-1:0];
             wr_state_q    <= WR_IDLE;
             txcc_pe_inj_q <= 3'b0;
          end
        else
          begin
             cpl_rr_q      <= cpl_rr_d;
             cpl_rr_gnt_q  <= cpl_rr_gnt_d;
             wr_state_q    <= wr_state_d;
             txcc_pe_inj_q <= txcc_pe_inj_d;
          end
     end

   always @*
     begin



        cpl_rr_d                     = cpl_rr_q;
        cpl_rr_gnt_d                 = cpl_rr_gnt_q;
        wr_state_d                   = wr_state_q;
      
        cpl_write                    = 1'b0;        
        cpl_rr_ready                 = zero[cpl_rr_width-1:0];
       
        cpl_rr_valid                 = {ioq_pcie_cc_valid, adq_pcie_cc_valid, sntl_pcie_cc_valid, sntl_pcie_wbuf_cc_valid,sntl_pcie_adbuf_cc_valid};
        {cpl_rr_noused, cpl_rr_gnt}  = roundrobin({zero[31:cpl_rr_width],cpl_rr_valid}, {zero[31:cpl_rr_width], cpl_rr_q} );

        cpl_rr_active                = cpl_rr_gnt_q & cpl_rr_valid;
        
        // arbitration is on a packet boundary
        case( wr_state_q )
          WR_IDLE:
            begin
               cpl_rr_gnt_d = cpl_rr_gnt;
               if( ~cpl_wfull & (cpl_rr_valid != zero[cpl_rr_width-1:0]) )
                 begin
                    cpl_write     = 1'b1;
                    cpl_rr_ready  = cpl_rr_gnt;
                    cpl_rr_d      = cpl_rr_gnt;
                    if( ~wr_last )
                      wr_state_d = WR_BUSY;                    
                 end
            end
          
          WR_BUSY:
            begin               
               if( ~cpl_wfull ) 
                 begin
                    cpl_rr_ready = cpl_rr_gnt_q;
                    if(cpl_rr_active!=zero[cpl_rr_width-1:0])
                      begin                 
                         cpl_write = 1'b1;
                         if( wr_last )
                           begin
                              wr_state_d = WR_IDLE;
                           end
                      end
                 end               
            end
          
          default:
            begin
               wr_state_d = WR_IDLE;
            end
        endcase // case ( wr_state_q )
     end // always @ *

   always @*
     begin

        // mux cmd/data/address with arbitration grant
        { ioq_gnt, adq_gnt, sntl_gnt, wbuf_gnt, adbuf_gnt } = cpl_rr_gnt_d;

        cpl_wdata = ({cpl_fifo_width{ioq_gnt}} & {ioq_pcie_cc_data[data_width-1:data_width-cpl_fifo_pwidth], ioq_pcie_cc_discard, ioq_pcie_cc_first, ioq_pcie_cc_last, ioq_pcie_cc_data[127:0]}) | 
                    ({cpl_fifo_width{adq_gnt}} & {adq_pcie_cc_data[data_width-1:data_width-cpl_fifo_pwidth], adq_pcie_cc_discard, adq_pcie_cc_first, adq_pcie_cc_last, adq_pcie_cc_data[127:0]}) | 
                    ({cpl_fifo_width{sntl_gnt}} & {sntl_pcie_cc_data[data_width-1:data_width-cpl_fifo_pwidth], sntl_pcie_cc_discard, sntl_pcie_cc_first, sntl_pcie_cc_last, sntl_pcie_cc_data[127:0]}) |                 
                    ({cpl_fifo_width{wbuf_gnt}} & {sntl_pcie_wbuf_cc_data[data_width-1:data_width-cpl_fifo_pwidth],sntl_pcie_wbuf_cc_discard, sntl_pcie_wbuf_cc_first, sntl_pcie_wbuf_cc_last, sntl_pcie_wbuf_cc_data[127:0]}) |
                    ({cpl_fifo_width{adbuf_gnt}} & {sntl_pcie_adbuf_cc_data[data_width-1:data_width-cpl_fifo_pwidth],sntl_pcie_adbuf_cc_discard, sntl_pcie_adbuf_cc_first, sntl_pcie_adbuf_cc_last, sntl_pcie_adbuf_cc_data[127:0]});
            
        wr_last = (ioq_gnt & ioq_pcie_cc_last) |
                  (adq_gnt & adq_pcie_cc_last) |
                  (sntl_gnt & sntl_pcie_cc_last) |
                  (wbuf_gnt & sntl_pcie_wbuf_cc_last) |
                  (adbuf_gnt & sntl_pcie_adbuf_cc_last);
        
   
        { pcie_ioq_cc_ready, pcie_adq_cc_ready, pcie_sntl_cc_ready, pcie_sntl_wbuf_cc_ready, pcie_sntl_adbuf_cc_ready } = cpl_rr_ready;
     end

    wire                      cpl_rval;
    wire                      s1_valid;
    reg                       s1_taken;

    always @*
      begin
         txcc_pe_inj_d = txcc_pe_inj_q;       
         if (regs_wdata_pe_errinj_valid  & regs_pcie_pe_errinj_valid & regs_xxx_pe_errinj_decode[15:8] == 4'h8)
           begin
              txcc_pe_inj_d[0]  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);   // clk
              txcc_pe_inj_d[1]  = (regs_xxx_pe_errinj_decode[3:0]==4'h1);   // clk
              txcc_pe_inj_d[2]  = (regs_xxx_pe_errinj_decode[3:0]==4'h2);  // clk 
           end 
         if  (txcc_pe_inj_q[0] & adq_pcie_cc_valid)
           txcc_pe_inj_d[0] = 1'b0; 
         if  (txcc_pe_inj_q[1] & ioq_pcie_cc_valid)
           txcc_pe_inj_d[1] = 1'b0; 
         if  (txcc_pe_inj_q[2] & sntl_pcie_cc_valid)
           txcc_pe_inj_d[2] = 1'b0; 
      end  



   nvme_pcheck#(.bits_per_parity_bit(8), .width(cpl_fifo_width-cpl_fifo_pwidth)) cc0_pchck_adq
     (.data({adq_pcie_cc_discard, adq_pcie_cc_first, adq_pcie_cc_last, adq_pcie_cc_data[127:1],(adq_pcie_cc_data[0]^txcc_pe_inj_q[0])}),
      .oddpar(1'b1),
      .datap(adq_pcie_cc_data[data_width-1:data_width-cpl_fifo_pwidth]),
      .check(adq_pcie_cc_valid),
      .parerr(s1_perror[0])   //clk 
      );

   nvme_pcheck#(.bits_per_parity_bit(8), .width(cpl_fifo_width-cpl_fifo_pwidth)) cc0_pchck_ioq
     (.data({ioq_pcie_cc_discard, ioq_pcie_cc_first, ioq_pcie_cc_last, ioq_pcie_cc_data[127:1],(ioq_pcie_cc_data[0]^txcc_pe_inj_q[1])}),
      .oddpar(1'b1),
      .datap(ioq_pcie_cc_data[data_width-1:data_width-cpl_fifo_pwidth]),
      .check(ioq_pcie_cc_valid),
      .parerr(s1_perror[1])   // clk
      );

   nvme_pcheck#(.bits_per_parity_bit(8), .width(cpl_fifo_width-cpl_fifo_pwidth)) cc0_pchck_sntl
     (.data({sntl_pcie_cc_discard, sntl_pcie_cc_first, sntl_pcie_cc_last, sntl_pcie_cc_data[127:1],(sntl_pcie_cc_data[0]^txcc_pe_inj_q[2])}),
      .oddpar(1'b1),
      .datap(sntl_pcie_cc_data[data_width-1:data_width-cpl_fifo_pwidth]),
      .check(sntl_pcie_cc_valid),
      .parerr(s1_perror[2])  //clk
      );
   //   nvme_pgen#(.bits_per_parity_bit(8), .width(cpl_fifo_width-cpl_fifo_pwidth)) cc0_pgen
   //     (.data(cpl_wdata[cpl_fifo_width-1-cpl_fifo_pwidth:0]),
   //      .oddpar(1'b1),
   //      .datap(rd_data[data_width-1 : data_width-data_pwidth] ),
   //     );


   // debug counts
   reg [15:0] cnt_event_q;   
   always @(posedge clk)
     begin
        if( reset )
          begin
             cnt_event_q <= 16'h0;           
          end
        else
          begin
             cnt_event_q[0]  <= cpl_write & ~cpl_wfull;
             cnt_event_q[1]  <= cpl_write & cpl_wfull;
             cnt_event_q[2]  <= cpl_write & ~cpl_wfull & wr_last;        
             cnt_event_q[3]  <= cpl_write & ioq_gnt & ioq_pcie_cc_first;        
             cnt_event_q[4]  <= cpl_write & adq_gnt & adq_pcie_cc_first;        
             cnt_event_q[5]  <= cpl_write & sntl_gnt & sntl_pcie_cc_first;             
             cnt_event_q[6]  <= cpl_write & ioq_gnt & ~ioq_pcie_cc_first;        
             cnt_event_q[7]  <= cpl_write & adq_gnt & ~adq_pcie_cc_first;        
             cnt_event_q[8]  <= cpl_write & sntl_gnt & ~sntl_pcie_cc_first;
             cnt_event_q[9]  <= cpl_write & wbuf_gnt & sntl_pcie_wbuf_cc_first;
             cnt_event_q[10] <= cpl_write & wbuf_gnt & ~sntl_pcie_wbuf_cc_first;
           end  
     end
   
   assign txcc_dbg_events = cnt_event_q;


   // timing fix
   wire                      cpl_ready;
   (* mark_debug = "true" *)
   wire [cpl_fifo_width-1:0] s1_cpl_wdata;
   wire                      s1_cpl_valid;
   wire                      s1_cpl_wfull;
   wire                      s1_cpl_wrstbusy;
   wire                      s1_cpl_wready;
   (* mark_debug = "true" *)
   wire                      s1_cpl_write;
   nvme_pl_burp#(.width(cpl_fifo_width), .stage(1)) s0_cpl
     (.clk(clk),.reset(reset),
      .valid_in(cpl_write),
      .data_in(cpl_wdata),
      .ready_out(cpl_ready),
      
      .data_out(s1_cpl_wdata),
      .valid_out(s1_cpl_valid),
      .ready_in(s1_cpl_wready)
      ); 

   assign s1_cpl_wready = ~s1_cpl_wfull & ~s1_cpl_wrstbusy;
   assign s1_cpl_write  = s1_cpl_valid & ~s1_cpl_wfull;
   assign cpl_wfull     = ~cpl_ready;
   
   //-------------------------------------------------------
   // Async fifo for domain crossing
   //-------------------------------------------------------

   
   reg                       cpl_rack; 
   wire [cpl_fifo_width-1:0] cpl_rdata;
   wire                      cpl_rerr;
   wire                      cpl_rrstbusy;
   
   
   // sized at 512 entries to match xilinx BRAM size
   // - 128B completion is 9 entries -> max 56 packets (7KB)
   // - MRd is 1 entry
   //nvme_async_fifo#
   //  ( .width(cpl_fifo_width),
   //    .awidth(9)               // 512 entries
   nvme_cdc_fifo_xil#(.width(cpl_fifo_width)
       ) cpl_fifo
       (
          // write
        .wclk                           (clk),
        .wreset                         (reset),
        .write                          (s1_cpl_write),
        .wdata                          (s1_cpl_wdata),
        .wfull                          (s1_cpl_wfull),
        .wrstbusy                       (s1_cpl_wrstbusy),
        //.wafull	                        (),
        .werror	                        (),
        
        // read
        .rclk                           (user_clk),
        .rreset                         (user_reset),
        .rack                           (cpl_rack),
        .rdata                          (cpl_rdata),
        .rval                           (cpl_rval),
        //.rerr                           (cpl_rerr)
        .runderflow                     (cpl_rerr),
        .rsbe                           (),
        .rue                            (),
        .rempty                         (),
        .rrstbusy                       (cpl_rrstbusy)
        );
   
   //-------------------------------------------------------
   // NVME clock domain logic
   //-------------------------------------------------------
   
   reg                 [6:0] rd_lower_addr;  // least significant 7b of byte address of this packet
   reg                 [7:0] rd_tag;         // from original request
   reg                [10:0] rd_cpl_dcount;  // number of dwords in this packet
   reg                 [2:0] rd_cpl_status;  // 0x0 - success; 0x1 - unsupported request; 0x2 - completer abort
   reg                [12:0] rd_byte_count;  // remaining bytes to be transferred including this packet
   reg                 [2:0] rd_tc;          // from original request
   reg                 [2:0] rd_attr;        // from original request
   reg                 [1:0] rd_at;          // from the original request
   reg                       rd_discard;
   reg                       rd_first;
   reg                       rd_last;

   reg                       rd_locked_read;
   reg                       rd_poisoned;
   reg                [15:0] rd_requester_id;
   reg                [15:0] rd_completer_id;
   reg                       rd_completer_id_enable;  // must be 1?  only applies to endpoints
   reg                       rd_force_ecrc;
   reg                [95:0] rd_descriptor;
   
   reg                 [3:0] rd_state_q, rd_state_d;

   reg       [hdr_width-1:0] rd_hdr_q, rd_hdr_d;
   reg               [127:0] rd_data_q, rd_data_d;

   // completer completion interface signals
   reg                       tvalid;
   reg               [127:0] tdata;
   reg                 [3:0] tkeep;
   reg                       tlast;
   reg                       tdiscontinue;
   reg                       cc_tready;
   reg                       tfirst; // for debug only
   
   localparam RD_IDLE = 4'h1;
   localparam RD_HDR  = 4'h2;
   localparam RD_DATA = 4'h3;
   localparam RD_CMP  = 4'h4;
   
   reg                 [0:2] user_txcc_pe_inj_q,user_txcc_pe_inj_d;
   always @(posedge user_clk or posedge user_reset)
     begin
        if( user_reset )
          begin
             rd_state_q         <= RD_IDLE;
             rd_hdr_q           <= zero[hdr_width-1:0];             
             rd_data_q          <= zero[127:0];
             user_txcc_pe_inj_q <= 3'b0;
          end
        else
          begin
             rd_state_q         <= rd_state_d;
             rd_hdr_q           <= rd_hdr_d;
             rd_data_q          <= rd_data_d;
             user_txcc_pe_inj_q <= user_txcc_pe_inj_d;
          end
     end

   wire                s2_valid;

   always @*
     begin
        user_txcc_pe_inj_d = user_txcc_pe_inj_q;       
        if (user_regs_wdata_pe_errinj_valid  & regs_pcie_pe_errinj_valid & regs_xxx_pe_errinj_decode[15:8] == 4'h8)
          begin
             user_txcc_pe_inj_d[0]  = (regs_xxx_pe_errinj_decode[3:0]==4'h3);  // user clk
             user_txcc_pe_inj_d[1]  = (regs_xxx_pe_errinj_decode[3:0]==4'h4); // user clk 
             user_txcc_pe_inj_d[2]  = (regs_xxx_pe_errinj_decode[3:0]==4'h5); // user clk 
          end 
        if  (user_txcc_pe_inj_q[0] & cpl_rval)
          user_txcc_pe_inj_d[0] = 1'b0; 
        if  (user_txcc_pe_inj_q[1] & s1_valid)
          user_txcc_pe_inj_d[1] = 1'b0; 
        if  (user_txcc_pe_inj_q[2] & s2_valid)
          user_txcc_pe_inj_d[2] = 1'b0; 
     end  

   
   always @*
     begin
        rd_state_d    = rd_state_q;
        rd_hdr_d      = rd_hdr_q;
        rd_data_d     = rd_data_q;

        tvalid        = 1'b0;
        tdata         = { cpl_rdata[31:0], rd_data_q[127:32] };  // dw4, dw3, dw2, dw1 - shift by 1 dword
        tkeep         = 4'hF;
        tlast         = 1'b0;
        tdiscontinue  = 1'b0;
        tfirst        = 1'b0;
        
        // unpack fifo data
        { rd_discard, 
          rd_first, 
          rd_last }  = cpl_rdata[130:128];
        
        // descriptor fields from fifo
        { rd_at, rd_attr, rd_tc, rd_byte_count, 
          rd_cpl_status, rd_cpl_dcount,
          rd_tag, rd_lower_addr }     = rd_hdr_q[hdr_width-1:0];

        if( rd_cpl_status != 3'h0 )
          begin
             // UR/CA completion must have dcount=0
             rd_cpl_dcount = 11'h0;
          end
        

        // other descriptor fields
        rd_locked_read          = 1'b0;
        rd_requester_id         = 16'h0100; 
        rd_completer_id         = 16'h0000;
        rd_completer_id_enable  = 1'b1;

        rd_force_ecrc           = 1'b0; // ECRC not enabled
        rd_poisoned             = 1'b0; // not using poison
      

        // see pg156-ultrascale-pcie-gen3.pdf Sept30, 2015 (pg156) Figure 3-28 for descriptor definitions
        rd_descriptor  = { rd_force_ecrc, rd_attr, rd_tc, rd_completer_id_enable, rd_completer_id, rd_tag,
                       rd_requester_id, 1'b0, rd_poisoned, rd_cpl_status, rd_cpl_dcount, 2'b00,
                       rd_locked_read, rd_byte_count, zero[7:2], rd_at, 1'b0, rd_lower_addr };        

        cpl_rack = 1'b0;
        
        case(rd_state_q)
          RD_IDLE:
            begin
               rd_data_d = zero[127:0];
               if( cpl_rval )
                 begin
                    if( rd_first )
                      begin
                         rd_hdr_d = cpl_rdata[hdr_width-1:0];

                         if( rd_last )
                           begin
                              // completion with no data
                              // see pg156 - page 140 
                              cpl_rack = 1'b1;
                           end
                         else
                           begin
                              rd_state_d = RD_HDR;                             
                              cpl_rack = 1'b1;                
                           end
                      end
                    else
                      begin
                         // error - expecting first to be active
                         cpl_rack = 1'b1;
                      end
                 end
            end
          
          RD_HDR, RD_DATA:
            begin
               tvalid = cpl_rval;
               tlast = 1'b0;
               tdiscontinue = rd_discard;
               
               if( cpl_rval && cc_tready )
                 begin
                    if( rd_state_q == RD_HDR )
                      begin
                         tfirst = 1'b1;
                         tdata = { cpl_rdata[31:0], rd_descriptor };                                    
                      end                    
                    rd_data_d = cpl_rdata[127:0];
                    if( rd_last )
                      begin                         
                         if( rd_cpl_dcount[1:0]==2'd1 )                                                 
                           begin
                              rd_state_d = RD_IDLE;                              
                              tlast = 1'b1;
                           end
                         else
                           begin
                              rd_state_d = RD_CMP;                             
                           end                   
                      end                    
                    else
                      begin                        
                         rd_state_d = RD_DATA;
                      end
                    cpl_rack = 1'b1;
                 end
            end

          RD_CMP:
            begin

               if( rd_cpl_status != 3'h0 )
                 begin
                    tkeep = 4'hF;
                    tdata = zero[127:0];  // spec says this should be descriptor from request
                 end
               else
                 begin               
                    // last 1-3 dwords
                    case( rd_cpl_dcount[1:0] )
                      2'h2: tkeep = 4'h1;
                      2'h3: tkeep = 4'h3;
                      2'h0: tkeep = 4'h7;
                      default: tkeep = 4'h0;
                    endcase // case ( rd_cpl_dcount[1:0] )
                 end
               
               tvalid = 1'b1;
               tlast = 1'b1;
               if( cc_tready )
                 begin                              
                    rd_state_d = RD_IDLE;
                 end            
            end
                           
          default:
            begin
            end
        endcase // case (rd_state_q)        
     end

   nvme_pcheck#(.bits_per_parity_bit(8), .width(cpl_fifo_width-cpl_fifo_pwidth)) cc1_pchck_rdata
     (.data({cpl_rdata[cpl_fifo_width-1-cpl_fifo_pwidth:1],(cpl_rdata[0]^user_txcc_pe_inj_q[0])}),
      .oddpar(1'b1),
      .datap(cpl_rdata[cpl_fifo_width-1:cpl_fifo_width-cpl_fifo_pwidth]),
      .check(cpl_rval),
      .parerr(s1_uperror[0])
      );

   //-------------------------------------------------------
   // stage 1
   //-------------------------------------------------------
   // store and forward to avoid possible underrun
   // interface does not allow for gaps

   localparam s1_pwidth = 16;   
   localparam s1_width = 128 + 1 + 4 + 1 + 1+ s1_pwidth; 
   reg                  s1_write;
   reg   [s1_width-1:0] s1_din;
   wire [s1_pwidth-1:0] s1_din_par;
   
   wire  [s1_width-1:0] s1_dout;
   wire                 s1_ready;
   wire                 s1_full;
   wire                 s1_almost_full;

   reg            [4:0] s1_frmcnt_q, s1_frmcnt_d;

   always @(posedge user_clk or posedge user_reset)
     begin
        if( user_reset )
          begin
             s1_frmcnt_q <= 1'b0;
          end
        else
          begin
             s1_frmcnt_q <= s1_frmcnt_d;
          end
     end

   // track number of "last"s in fifo
   always @*
     begin
        s1_frmcnt_d = s1_frmcnt_q;
        if( s1_write & tlast )
          begin
             s1_frmcnt_d = s1_frmcnt_d + 1;
          end
        if( s1_taken & s1_dout[s1_width-1-s1_pwidth] )
          begin
             s1_frmcnt_d = s1_frmcnt_d - 1;
          end        
     end
   
   always @*
     begin
        cc_tready = ~s1_almost_full;
        s1_write = tvalid && cc_tready;        
        s1_din = {s1_din_par, tlast, tfirst, tdiscontinue, tkeep, tdata};     // added s1_din_par, 
        
        s1_taken = s1_valid && s1_ready && s1_frmcnt_q!=0;
     end
   
   nvme_fifo#(.width(s1_width), 
              .words(16),
              .almost_full_thresh(1)
              ) s1_fifo
     (.clk(user_clk), .reset(user_reset), 
      .flush(       1'b0 ),
      .push(        s1_write ),
      .din(         s1_din ),
      
      .dval(        s1_valid ), 
      .pop(         s1_taken ),
      .dout(        s1_dout ),
      .full(        s1_full ), 
      .almost_full( s1_almost_full ), 
      .used());


   nvme_pgen#(.bits_per_parity_bit(8), .width(128)) s1_pgen
     (.data(s1_din[127:0]),
      .oddpar(1'b1),
      .datap(s1_din_par)
      );

   nvme_pcheck#(.bits_per_parity_bit(8), .width(128)) cc2_pchck_rdata
     (.data({s1_dout[127:1],(s1_dout[0]^user_txcc_pe_inj_q[1])}),
      .oddpar(1'b1),
      .datap(s1_dout[s1_width-1:s1_width-s1_pwidth]),
      .check(s1_valid),
      .parerr(s1_uperror[1])
      );

   //-------------------------------------------------------
   // stage 2
   //-------------------------------------------------------
   // output stage for timing
   localparam s2_pwidth = 16; 
   localparam s2_width = 128 + 1 + 4 + 1 + 1 + s2_pwidth;
   wire [s2_width-1:0] s2_dout;
   wire [15:0]         s2_din_par;
   reg                 s2_ready;
   reg                 s2_discontinue;
   reg                 s2_first;

   nvme_pl_burp#(.width(s2_width), .stage(1)) s2
     (.clk(user_clk),.reset(user_reset),
      .valid_in(s1_taken),
      .data_in(s1_dout), 
      .ready_out(s1_ready),
                 
      .data_out(s2_dout),
      .valid_out(s2_valid),
      .ready_in(s2_ready)
      ); 

   always @*
     begin
        s2_ready = s_axis_cc_tready==4'hF;
        s_axis_cc_tvalid = s2_valid;
        { s_axis_cc_tlast, s2_first, s2_discontinue, s_axis_cc_tkeep, s_axis_cc_tdata } = s2_dout;	            
        s_axis_cc_tuser = { zero[15:0], s2_din_par[15:1],s2_din_par[0]^user_txcc_pe_inj_q[2], s2_discontinue };         
     end

   //generate parity for just 128 bit interface to pci hip
   nvme_pgen#(.bits_per_parity_bit(8), .width(128)) s2_pgen
     (.data(s2_dout[127:0]),
      .oddpar(1'b1),
      .datap(s2_din_par)
      );

   //-------------------------------------------------------
   // debug counts
   //-------------------------------------------------------
   reg [15:0] cnt_event_user_q;
   
   always @(posedge user_clk)
     begin
        if( user_reset )
          begin
             cnt_event_user_q <= 16'h0;           
          end
        else
          begin
             cnt_event_user_q[0] <= s2_valid && s2_ready ;
             cnt_event_user_q[1] <= s2_valid && s2_ready &&  s_axis_cc_tlast;
             cnt_event_user_q[2] <= (rd_state_q==RD_HDR || rd_state_q==RD_DATA) && !cpl_rval;  // gap in tvalid?
             cnt_event_user_q[3] <= s2_valid && !s2_ready;
             cnt_event_user_q[4] <= tvalid && !cc_tready;
           end  
     end

   assign txcc_dbg_user_events = cnt_event_user_q;

   always @(posedge user_clk)
     begin
        txcc_dbg_user_tracedata  <= s2_dout;
        txcc_dbg_user_tracevalid <= s2_valid & s2_ready;
     end

   
endmodule

