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
module base_aesplit
  (input clk,
   input  reset,
   output i_r,
   input  i_v,
   input  i_e,
   input  o_r,
   output o_v,
   output o_e
   );

   wire [0:1] s0_v, s0_r;
   base_acombine#(.ni(1),.no(2)) is0c(.i_v(i_v),.i_r(i_r),.o_v(s0_v),.o_r(s0_r));

   wire       s0_e_v, s0_e_r;
   base_afilter is0f(.i_v(s0_v[1]),.i_r(s0_r[1]),.o_v(s0_e_v),.o_r(s0_e_r),.en(i_e));

   wire       s1_e_v, s1_e_r;
   base_alatch#(.width(1)) is1b(.clk(clk),.reset(reset),.i_v(s0_e_v),.i_r(s0_e_r),.i_d(1'b0),.o_v(s1_e_v),.o_r(s1_e_r),.o_d());

   base_primux#(.ways(2),.width(1)) iemux
     (.i_v({s1_e_v,s0_v[0]}),.i_r({s1_e_r,s0_r[0]}),.i_d(2'b10),.o_v(o_v),.o_r(o_r),.o_d(o_e),.o_sel());

endmodule // base_aesplit

   
