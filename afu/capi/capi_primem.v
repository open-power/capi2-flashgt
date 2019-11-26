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
// dual read port memory with priority to port zero

module capi_primem#
  (parameter width=1,
   parameter addr_width=1,
   parameter aux0_width=1,
   parameter aux1_width=1
   )
   (input clk,
    input 		    reset,
    input 		    we,
    input [0:addr_width-1]  wa,
    input [0:width-1] 	    wd,
    
    input 		    i_r0_v,
    input [0:addr_width-1]  i_r0_a,
    input [0:aux0_width-1]  i_r0_aux,
    
    input 		    i_r1_v,
    output 		    i_r1_r,
    input [0:addr_width-1]  i_r1_a,
    input [0:aux1_width-1]  i_r1_aux,
    
    output 		    o_r0_v,
    output [0:width-1] 	    o_r0_d,
    output [0:aux0_width-1] o_r0_aux,

    input 		    o_r1_r,
    output 		    o_r1_v,
    output [0:width-1] 	    o_r1_d,
    output [0:aux1_width-1] o_r1_aux
    );

   wire [0:1] 		    s1_en;
   wire [0:aux1_width-1]    s1_r1_aux;
   
   base_vlat_en#(.width(aux0_width)) is1_aux0_lat(.clk(clk),.reset(1'b0),.din(i_r0_aux),.q( o_r0_aux),.enable(s1_en[0]));
   base_vlat_en#(.width(aux1_width)) is1_aux1_lat(.clk(clk),.reset(1'b0),.din(i_r1_aux),.q(s1_r1_aux),.enable(s1_en[1]));

   wire [0:1] 		    s0a_v, s0a_r;
   assign s0a_v[0] = i_r0_v;

   // don't allow low priorty entry if there is already one waiting to leave
   base_agate is0_gt1(.i_v(i_r1_v),.i_r(i_r1_r),.o_v(s0a_v[1]),.o_r(s0a_r[1]),.en(o_r1_r | ~o_r1_v));
   
   wire 		    s0_v, s0_r;
   wire [0:addr_width-1]    s0_a;
   wire [0:1] 		    s0_sel;
   base_primux#(.ways(2),.width(addr_width)) is0_mux(.i_v(s0a_v),.i_r(s0a_r),.i_d({i_r0_a,i_r1_a}),.o_v(s0_v),.o_r(s0_r),.o_d(s0_a),.o_sel(s0_sel));

   wire 		    s1_v, s1_r;
   wire [0:1] 		    s1_sel;
   wire 		    s0_en;
   base_alatch_oe#(.width(2)) is1_lat(.clk(clk),.reset(reset),.i_v(s0_v),.i_r(s0_r),.i_d(s0_sel),.o_v(s1_v),.o_r(s1_r),.o_d(s1_sel),.o_en(s0_en));

   wire [0:width-1] 	    s1_d;
   base_mem#(.addr_width(addr_width),.width(width)) imem
     (.clk(clk),
      .we(we),.wa(wa),.wd(wd),
      .re(s0_en),.ra(s0_a),.rd(s1_d)
      );

   wire [0:1] 		    s1a_v, s1a_r;
   base_ademux#(.ways(2)) is1_demux(.i_v(s1_v),.i_r(s1_r),.o_v(s1a_v),.o_r(s1a_r),.sel(s1_sel));
   assign s1_en = s1a_r | ~s1a_v;
   assign s1a_r[0] = 1'b1;
   
   base_aburp#(.width(width+aux1_width)) is1_burp(.clk(clk),.reset(reset),.i_v(s1a_v[1]),.i_r(s1a_r[1]),.i_d({s1_d,s1_r1_aux}),.o_v(o_r1_v),.o_r(o_r1_r),.o_d({o_r1_d,o_r1_aux}),.burp_v());
   assign o_r0_v = s1a_v[0];
   assign o_r0_d = s1_d;
   
   
endmodule // capi_primem

    
    
   
