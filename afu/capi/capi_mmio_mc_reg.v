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
module capi_mmio_mc_reg#
  (
   parameter addr_width = 25,
   parameter addr = 0,
   parameter ctxtid_width=10,  
   parameter ctxtid_start=14,
   parameter addr_mask = ((1<<ctxtid_width-1)-1) << ctxtid_start,  
   parameter mmiobus_width=4+addr_width+65 
   )
  (
   input 		     clk,
   input 		     reset,
   input [0:mmiobus_width-1] i_mmiobus,
   
   output [0:64] 	     q,

   output [0:ctxtid_width-1] ctxt, 
   output 		     trg,
   output                    o_perror
   );

   localparam width=64;
   wire 		       ha_cfg;  // this is config space
   wire 		       ha_rnw;  // read not write
   wire 		       ha_vld;  // valid 
   wire 		       ha_dw;   // double word
   wire [0:addr_width-1]       ha_addr;
   wire [0:64] 	       ha_wd;
   
   assign {ha_vld,ha_cfg,ha_rnw,ha_dw,ha_addr,ha_wd} = i_mmiobus;

   wire 		       we = ~ha_cfg & ~ha_rnw & ha_vld;
   wire [0:addr_width-1]       wa = ha_addr;
   wire 		       enable;
   capi_mmio_trigger#(.addr_mask(addr_mask), .addr(addr), .addr_width(addr_width))    ien(.clk(clk), .reset(reset), .wa(wa), .we(we), .trigger(enable));

   wire 		       s1_dw;
   base_vlat#(.width(1)) is1_dw(.clk(clk),.reset(1'b0),.din(ha_dw),.q(s1_dw));

   wire [0:31] 		       s1_wd = s1_dw ? ha_wd[0:31] : 32'd0;
   wire                        s1_wd_par;

   capi_parity_gen#(.dwidth(width),.width(1)) ipgen(.i_d({s1_wd,ha_wd[32:63]}),.o_d(s1_wd_par));

   base_vlat_en#(.width(width+1)) idta(.clk(clk), .reset(reset), .enable(enable), .din({s1_wd,ha_wd[32:63],s1_wd_par}), .q(q));
   base_vlat#(.width(1)) itrg(.clk(clk),.reset(reset),.din(enable), .q(trg));
   
   localparam ctxt_lsb = (addr_width-1)-ctxtid_start-1;  
   localparam ctxt_msb = (addr_width-1)-ctxtid_start-(ctxtid_width-1);
   capi_parity_gen#(.dwidth(ctxtid_width-1),.width(1)) icpgen(.i_d(wa[ctxt_msb:ctxt_lsb]),.o_d(ctxtpar));
   wire  				s1_perror;
   wire                                 ctxt_val;
   base_vlat#(.width(1+ctxtid_width)) ictxt(.clk(clk),.reset(reset),.din({we,wa[ctxt_msb:ctxt_lsb],ctxtpar}),.q({ctxt_val,ctxt}));
   capi_parcheck#(.width(ctxtid_width-1)) ctxt_pcheck(.clk(clk),.reset(reset),.i_v(ctxt_val),.i_d(ctxt[0:ctxtid_width-2]),.i_p(ctxt[ctxtid_width-1]),.o_error(s1_perror));
   wire  				hld_perror;
   base_vlat_sr#(.width(1)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(1'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror),.q(o_perror));
   
endmodule // mmio_reg

  
   
   
    
