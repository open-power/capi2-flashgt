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
module capi_cmd_credit#(parameter cred_width=9,parameter ld_delay=10)
  (input clk,
   input 		   reset,
   input [0:cred_width-1]  i_init_cred,

   
   input 		   i_cred_add_v,
   input [0:cred_width-1]  i_cred_add_d,

   input 		   i_cred_inc_v,
   input 		   i_cred_dec_v,

   output 		   o_en,

   output [0:cred_width-1] o_credits

   );

   wire [0:1] os_out;
   base_vlat#(.width(1)) i_oneshotd0(.clk(clk),.reset(reset),.din(1'b1),.q(os_out[0]));
   base_vlat#(.width(1)) i_oneshotd1(.clk(clk),.reset(reset),.din(os_out[0]),.q(os_out[1]));
   wire  ld_trg = os_out[0] & ~os_out[1];
   wire  ld_trg_d;
   base_delay#(.width(1),.n(ld_delay)) ionshot_del(.clk(clk),.reset(reset),.i_d(ld_trg),.o_d(ld_trg_d));

   localparam [0:cred_width-1] cred_one = 1;
   localparam [0:cred_width-1] cred_zro = 0;
   wire [0:cred_width-1] crd_din;
   wire [0:cred_width-1] crd_q;

   wire [0:cred_width-1] cred_inc1 = i_cred_add_v ? i_cred_add_d : cred_zro;
   wire [0:cred_width-1] cred_inc2 = i_cred_inc_v ? cred_one : cred_zro;

   wire [0:cred_width-1] cred_inc3;

   base_vlat#(.width(cred_width)) is1_cred_lat(.clk(clk),.reset(reset),.din(cred_inc1 + cred_inc2),.q(cred_inc3));
   
   wire [0:cred_width-1] cred_dec = {cred_width {i_cred_dec_v}};
   assign crd_din = ld_trg_d ? i_init_cred : (crd_q + cred_inc3 + cred_dec);
   base_vlat#(.width(cred_width)) icre_lat(.clk(clk), .reset(reset),.din(crd_din),.q(crd_q));

   wire 		 cred_avail = | crd_q;
   assign o_en = cred_avail;
		 
   base_vlat#(.width(cred_width)) icredit_lat(.clk(clk),.reset(1'b0),.din(crd_q),.q(o_credits));
					   
endmodule // capi_cmd_credit

   
   
