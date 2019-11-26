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

//  *************************************************************************
//  File : nvme_async_fifo.v
//  *************************************************************************
//  *************************************************************************
//  Description : asynchronous fifo using xilinx IP
//                512 entries
//
//                If wfull is asserted and write is asserted, 
//                the write data is silently dropped
//
//                when rval is asserted, rdata is valid
//                when the rack input is asserted, 
//                  rval and rdata are updated on the following cycle.
//  
//  *************************************************************************

module nvme_cdc_fifo_xil#
  ( 
    parameter width = 8      
    )
   (
    input              wreset,
    input              wclk,
    input              write,
    input  [width-1:0] wdata,
    output             wfull,
    output             wrstbusy,
    output             werror,

    
    input              rreset,
    input              rclk,
    input              rack,
    output [width-1:0] rdata,
    output             rval,
    output             runderflow,
    output             rsbe,
    output             rue,
    output             rempty,
    output             rrstbusy
    
    );

   localparam maxwidth=192;

   localparam [maxwidth-1:0] zero = {maxwidth{1'h0}}; 
   wire                wr_clk;  // input wire wr_clk
   wire        [191:0] din;  // input wire din
   wire                wr_en;  // input wire wr_en
   wire                srst;  // input wire srst
   wire                injectdbiterr;  // input wire injectdbiterr
   wire                injectsbiterr;  // input wire injectsbiterr
   wire                overflow;  // output wire overflow
   wire                full;  // output wire full
   wire                wr_rst_busy;  // output wire wr_rst_busy

   assign wr_clk = wclk;

   // assert synchronous reset to fifo (synchronous to wclk)
   wire wr_clk_rreset;
   nvme_cdc cdc_rreset (.clk(wclk),.d(rreset),.q(wr_clk_rreset));

   // make srst a 1 cycle pulse when rreset and wreset are both deasserted
   reg [2:0] srst_q;
   initial
     begin
        srst_q = 3'b000;
     end
   
   always @(posedge wclk)
     begin
        srst_q[0] <= wreset | wr_clk_rreset;
        srst_q[1] <= srst_q[0];
        srst_q[2] <= srst_q[1] & ~srst_q[0];
     end
   assign srst = srst_q[2];

   generate if( maxwidth!=width )
     begin
        assign din[maxwidth-1:width] = zero[maxwidth-1:width];
     end
   endgenerate
   assign din[width-1:0] = wdata;
   assign wr_en          = write;
   assign injectdbiterr  = 1'b0;
   assign injectsbiterr  = 1'b0;
   // assign wfull          = full | wr_rst_busy;
   assign wfull          = full;
   assign wrstbusy       = wr_rst_busy;
   
   assign werror         = overflow | (write & wfull);
   
   
   wire         rd_clk;  // input wire rd_clk
   wire         rd_en;  // input wire rd_en
   wire [191:0] dout;  // output wire  dout
   wire         empty;  // output wire empty
   wire         valid;  // output wire valid  
   wire         underflow;  // output wire underflow
   wire         sbiterr;  // output wire sbiterr
   wire         dbiterr;  // output wire dbiterr
   wire         rd_rst_busy;  // output wire rd_rst_busy
   
   assign rd_clk      = rclk;
   //assign rd_en       = rack;
   //assign rval        = valid;
   //assign rdata       = dout[width-1:0];
   assign runderflow  = underflow;
   assign rsbe        = sbiterr;
   assign rue         = dbiterr;
   assign rempty      = empty | rd_rst_busy;
   assign rrstbusy    = rd_rst_busy;

   wire         s0_ready;
   assign rd_en = valid & s0_ready & ~rd_rst_busy;

   nvme_pl_burp#(.width(width), .stage(1)) s0 
     (.clk(rd_clk),.reset(rreset),
      .valid_in(valid),
      .data_in(dout[width-1:0]),
      .ready_out(s0_ready),
                 
      .data_out(rdata),
      .valid_out(rval),
      .ready_in(rack)
      ); 
   

async_fifo_512x192 xil_async_fifo (
  .srst(srst),                    // input wire srst
  .wr_clk(wr_clk),                // input wire wr_clk
  .rd_clk(rd_clk),                // input wire rd_clk
  .din(din),                      // input wire [191 : 0] din
  .wr_en(wr_en),                  // input wire wr_en
  .rd_en(rd_en),                  // input wire rd_en
  .injectdbiterr(injectdbiterr),  // input wire injectdbiterr
  .injectsbiterr(injectsbiterr),  // input wire injectsbiterr
  .dout(dout),                    // output wire [191 : 0] dout
  .full(full),                    // output wire full
  .overflow(overflow),            // output wire overflow
  .empty(empty),                  // output wire empty
  .valid(valid),                  // output wire valid
  .underflow(underflow),          // output wire underflow
  .sbiterr(sbiterr),              // output wire sbiterr
  .dbiterr(dbiterr),              // output wire dbiterr
  .wr_rst_busy(wr_rst_busy),      // output wire wr_rst_busy
  .rd_rst_busy(rd_rst_busy)      // output wire rd_rst_busy
);
   
endmodule // nvme_cdc_fifo_xil



  
