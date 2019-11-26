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
// i_d_adv comes in the same cycle as i_v and i_r are both high
// i_d_del comes one cycle later. 
// o_d_adv and o_d_del both come in the same cycle as o_v and o_r are both high
module base_arealign#
  (
   parameter del_width=1,
   parameter adv_width=1
   )
  (
   input 		  clk,
   input 		  reset,
   input 		  i_v,
   input [0:adv_width-1]  i_d_adv,
   input [0:del_width-1]  i_d_del,
   output 		  i_r,

   output 		  o_v,
   output [0:adv_width-1] o_d_adv,
   output [0:del_width-1] o_d_del,
   input 		  o_r
   );
   

   wire 	      din_act = i_v & i_r;
   wire 	      dout_act = o_v & o_r;

   wire [0:del_width-1] din_ltch;
   wire 		din_act_d;
   base_vlat_en#(.width(del_width)) idlatch
     (.clk(clk),
      .reset(reset),
      .din(i_d_del),
      .q(din_ltch),
      .enable(din_act_d)
      );
   
   base_alatch#(.width(adv_width)) ivltch
     (.clk(clk),
      .reset(reset),
      .i_v(i_v),
      .i_d(i_d_adv),
      .i_r(i_r),
      .o_v(o_v),
      .o_d(o_d_adv),
      .o_r(o_r)
      );

   base_vlat idinactl
     (.clk(clk),
      .reset(reset),
      .din(din_act),
      .q(din_act_d)
      );

   wire 		mux_sel;
   wire 	      mux_sel_in = mux_sel ^ dout_act ^ din_act_d;
   base_vlat imuxsel
     (.clk(clk),
      .reset(reset),
      .din(mux_sel_in),
      .q(mux_sel)
      );

   assign o_d_del = mux_sel ? din_ltch : i_d_del;
   
endmodule // base_arealign


   
   
   
   


   
