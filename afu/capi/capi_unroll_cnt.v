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
module capi_unroll_cnt#
  (
   parameter dwidth = 1,
   parameter iwidth = 1,
   parameter cwidth = 1,
   parameter dic_width = dwidth + iwidth + cwidth

   )
  (
   input 	       clk,
   input 	       reset,

   input 	       din_v,
   input [0:iwidth-1]  din_i,
   input [0:dwidth-1]  din_d,
   input [0:cwidth-1]  din_c, /* how many beats = 0 = 2^cwidth */


   output 	       din_r,

   output 	       dout_v,
   output [0:iwidth-1] dout_i,
   output [0:dwidth-1] dout_d,
   output 	       dout_e, /* this is the last output beat */
   output 	       dout_s, /* this is the first output beat */
   input 	       dout_r
   );


   wire               s0_v, s0_r;
   wire [0:dic_width-1] s0_dic;
   
   wire 	      s1_v, s1_r;
   wire 	      s1a_v, s1a_r;
   wire 	      s1b_v, s1b_r;
   wire 	      s1c_v, s1c_r;

   wire [0:cwidth-1]  s1_c;
   wire [0:dwidth-1]  s1_d;
   wire [0:iwidth-1]  s1_i;
   
   wire [0:dic_width-1]   s2_dic;
   wire 		  s2_v, s2_r;
   
   /* its the last beat if cnt=1, or if it's zero and extra is on 
      the beat is dead if cnt=0 and extra is off
   */

   wire 		  s1_s;
   wire 	       s1_e = (s1_c == {{cwidth-1{1'b0}},1'b1});
   wire [0:cwidth-1]   s1_nc = s1_c - {{cwidth-1{1'b0}},1'b1};
   wire [0:iwidth-1]   s1_ni = s1_i + {{iwidth-1{1'b0}},1'b1};

   /* burp latch so that din_r is latch bounded */
   base_aburp#(.width(dic_width)) is0
     (.clk(clk), .reset(reset),
      .i_v(din_v), .i_d({din_d, din_i, din_c}), .i_r(din_r),
      .burp_v(),
      .o_v(s0_v), .o_d(s0_dic), .o_r(s0_r));

   /* s1 := pmux(s2,s0) */
   base_primux#(.ways(2),.width(dic_width+1)) iarb1
     (.i_v({s2_v,s0_v}),
      .i_r({s2_r,s0_r}),
      .i_d({s2_dic,1'b0,s0_dic,1'b1}),
      .o_v(s1_v),
      .o_r(s1_r),
      .o_d({s1_d,s1_i,s1_c,s1_s}),
      .o_sel()
      );


   /* (s1a,s1b) = split s1 */
   base_acombine#(.ni(1),.no(2)) isplt
     (.i_v(s1_v),   .i_r(s1_r),
      .o_v({s1a_v,s1b_v}), .o_r({s1a_r,s1b_r})
      );

   base_afilter iqual
     (
      .en(~s1_e),
      .i_v(s1a_v),.i_r(s1a_r),.o_v(s1c_v),.o_r(s1c_r));

   base_alatch_burp#(.width(dic_width)) ifdback
     (.clk(clk), .reset(reset), 
      .i_v(s1c_v), .i_d({s1_d, s1_ni, s1_nc}), .i_r(s1c_r),
      .o_v(s2_v), .o_d(s2_dic), .o_r(s2_r)
      );
   
   base_alatch_burp#(.width(dwidth+iwidth+2)) iout
     (.clk(clk), .reset(reset),
      .i_v(s1b_v),.i_r(s1b_r),.i_d({s1_d,s1_i,s1_e,s1_s}),
      .o_v(dout_v), .o_r(dout_r), .o_d({dout_d,dout_i,dout_e,dout_s})
      );
endmodule // capi_unroll

					   
  
   
