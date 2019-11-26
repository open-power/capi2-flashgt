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
module base_hold_for_n#
  (parameter n = 2, logn = $clog2(n))
   (input clk,
    input reset,
    input i_d,
    output o_d
    );

   wire [0:logn] wire_n;
   base_const#(.width(logn+1),.value(n)) iwire_n(wire_n);

   wire [0:logn] cnt, cnt_in;
   wire 	 cnt_zero = ~ (| cnt);
   wire [0:logn] wire_zero  = {logn+1{1'b0}};
   wire [0:logn] cnt_m1 = cnt-{{logn{1'b0}},1'b1};
   assign cnt_in = i_d ? wire_n : (cnt_zero ? wire_zero : cnt_m1);
   base_vlat#(.width(logn+1)) icnt_d(.clk(clk),.reset(reset),.din(cnt_in),.q(cnt));
   base_vlat#(.width(1)) io_d(.clk(clk),.reset(reset),.din(~cnt_zero),.q(o_d));
endmodule // base_hold_for_n


   
    
