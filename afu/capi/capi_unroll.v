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
module capi_unroll#
  (
   parameter width = 1,
   parameter cwidth = 1,
   parameter pwidth = width + cwidth + cwidth
   )
  (
   input 	       clk,
   input 	       reset,

   input 	       dinv,
   input [0:width-1]   din,
   input [0:cwidth-1]  cstart,
   input [0:cwidth-1]  cend,
   output 	       din_acc,

   output 	       doutv,
   output [0:width-1]  dout,
   output [0:cwidth-1] cout,
   output 	       dout_st,
   output              dout_ed,
   input 	       dout_acc
   );


   wire 	       s1v, s1r, s2v, s2r, s3v, s3r, s4v, s4r, s5v, s5r;

   wire [0:cwidth-1]   s1_cstart, s1_cend;
   wire [0:width-1]    s1_dat;
   wire [0:cwidth-1]   cwidth_one = {{cwidth-1{1'b0}},1'b1};
   wire [0:cwidth-1]   s1_cstart_nxt = s1_cstart + cwidth_one;
   
   wire 	       s1_first_beat;
   wire 	       s1_last_beat = s1_cstart == s1_cend;

   base_asml#(.width(pwidth+1)) ism
     (.clk(clk),.reset(reset),
      .ir_r(din_acc),.ir_v(dinv),.ir_d({din,cstart,cend,1'b1}),
      .if_v(~s1_last_beat),.if_d({s1_dat,s1_cstart_nxt,s1_cend,1'b0}),
      .o_v(s1v),.o_r(s1r),.o_d({s1_dat,s1_cstart,s1_cend,s1_first_beat})
      );

   base_alatch_burp#(.width(width+cwidth+2)) iout
     (.clk(clk), .reset(reset),
      .i_v(s1v),   .i_r(s1r),      .i_d({s1_dat,s1_cstart,s1_last_beat,s1_first_beat}),
      .o_v(doutv), .o_r(dout_acc), .o_d({dout,cout,dout_ed,dout_st})
      );
endmodule // gx_unroll

					   
  
   
