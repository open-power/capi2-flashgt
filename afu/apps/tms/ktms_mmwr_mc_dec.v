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
// handle mmio multi-context reads.
// detect address match, split local context and address
// address lsb must be 0
// sw write zeros upper 32 bits
// WARNING: ha_data COMES ONE CYCLE LATE
module ktms_mmwr_mc_dec#
  (parameter addr_width=24,
   parameter mmiobus_width=4+addr_width+64,
   parameter ctxtid_start=14,
   parameter ctxtid_width=10,
   parameter lcladdr_width=1,
   parameter [addr_width-1:0] addr=0,
   parameter lat=1 // data latencsy
   )
   (input clk,
    input 		       reset,
    input [0:mmiobus_width-1]  i_mmiobus, // can be given a larger bus (e.g.with data)

    input 		       o_wr_r, // limited backpressure
    output 		       o_wr_v,
    output [lcladdr_width-1:0] o_wr_addr, // ignore lsb
    output [0:ctxtid_width-1]  o_wr_ctxt,  // done kch
    output [0:63] 	       o_wr_d
    );


   wire 		       ha_cfg;  // this is config space
   wire 		       ha_rnw;  // read not write
   wire 		       ha_vld;  // valid 
   wire 		       ha_dw;   // double word
   wire [addr_width-1:0]       ha_addr;
   wire [0:63] 		       ha_data;

   assign {ha_vld,ha_cfg,ha_rnw,ha_dw,ha_addr,ha_data} = i_mmiobus; // omit any extra data bits

   wire 		       s0_addr_matchl = (ha_addr[ctxtid_start-1:lcladdr_width] == addr[ctxtid_start-1:lcladdr_width]);
   wire 		       s0_addr_matchh = (ha_addr[addr_width-1:ctxtid_start+ctxtid_width-1] == addr[addr_width-1:ctxtid_start+ctxtid_width-1]); //added -1 kch

   wire 		       s0_v = ~ha_addr[0] & s0_addr_matchl & s0_addr_matchh & ha_vld & ~ha_rnw & ~ha_cfg;

   wire                        s0_ctxt_par;
   wire [0:ctxtid_width-1]     s0_ctxt = {ha_addr[ctxtid_start+ctxtid_width-2:ctxtid_start],s0_ctxt_par}; // changed -1 to -2 kch
   wire [0:lcladdr_width-1]    s0_lcladdr = ha_addr [lcladdr_width-1:0];

   wire [lcladdr_width-1:0]    s1_ra;
   wire [0:ctxtid_width-1]     s1_rc;
   wire 		       s1_dw;
   
   wire  		       s1a_v,s1a_r;
   wire  		       s1b_v,s1b_r;
   wire [0:63] 		       s1_wr_d;


   capi_parity_gen#(.dwidth(ctxtid_width-1),.width(1)) ipgen(.i_d(s0_ctxt[0:ctxtid_width-2]),.o_d(s0_ctxt_par)); // added kch
   
   base_arealign#(.adv_width(ctxtid_width+lcladdr_width+1),.del_width(64)) is1_lat
     (.clk(clk),.reset(reset),
      .i_v(s0_v),.i_r(),.i_d_adv({s0_ctxt,s0_lcladdr,ha_dw}),.i_d_del(ha_data),
      .o_v(o_wr_v),.o_r(o_wr_r),.o_d_adv({o_wr_ctxt,o_wr_addr,s1_dw}),.o_d_del(s1_wr_d));

   // zero the upper 32 bits for a sw write to lower address
   assign o_wr_d[0:31] = s1_dw ? s1_wr_d[0:31] : 32'd0;
   assign o_wr_d[32:63] = s1_wr_d[32:63];
endmodule // ktms_mc_mmwr_dec


			       
   
   
   
   
    
   
