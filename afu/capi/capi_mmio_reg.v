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
// addr is a word address low bit off on dw write
// ha_wd: COMES ONE CYCLE LATE
// no sw access to upper 32 bits is allowed
// sw access to lower 32 bits clears upper 32 bits
module capi_mmio_reg#
  (
   parameter addr_width = 24,
   parameter addr = 0,
   parameter mmiobus_width=4+addr_width+64,
   parameter [0:63] rstv = 0
   )
   (
    input 		      clk,
    input 		      reset,
    input [0:mmiobus_width-1] i_mmiobus,
    
    output [0:63] 	      q,
    output 		      trg
   );

   localparam width=64;
   
   wire 		       ha_cfg;  // this is config space
   wire 		       ha_rnw;  // read not write
   wire 		       ha_vld;  // valid 
   wire 		       ha_dw;   // double word
   wire [addr_width-1:0]       ha_addr;
   wire [0:width-1] 	       ha_wd;
   
   assign {ha_vld,ha_cfg,ha_rnw,ha_dw,ha_addr,ha_wd} = i_mmiobus;

   // always write the high-order bits
   wire 		       we = ~ha_cfg & ~ha_rnw & ha_vld;
   wire [0:addr_width-1]       wa = ha_addr;
   wire 		       en;

   capi_mmio_trigger#(.addr(addr), .addr_width(addr_width),.addr_mask(0))    ien(.clk(clk), .reset(reset), .wa(wa), .we(we), .trigger(en));

   wire 		       s1_dw;
   base_vlat#(.width(1)) idwlat(.clk(clk),.reset(1'b0),.din({ha_dw}),.q({s1_dw}));
   
   wire [0:31] 		       s1_wd = s1_dw ? ha_wd[0:31] : 32'd0;
 
   base_vlat_en#(.rstv(rstv),.width(64)) idtal(.clk(clk), .reset(reset), .enable(en), .din({s1_wd,ha_wd[32:63]}),        .q(q));

   base_vlat#(.width(1)) itrg(.clk(clk),.reset(reset),.din(en), .q(trg));
   
endmodule // mmio_reg

  
   
   
    
