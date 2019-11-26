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
module capi_parcheck#(parameter width=1)
   (input clk,
    input reset,
    input [0:width-1] i_d,
    input i_p,
    input i_v,
 (* mark_debug = "false" *)
    output o_error
    );
   

   wire    s1_v, s1_p;
   wire [0:width-1] s1_d;
   
   base_vlat#(.width(width+2)) is1_lat(.clk(clk),.reset(reset),.din({i_v,i_p,i_d}),.q({s1_v,s1_p,s1_d}));
   wire 	    s1_p_gen;
   capi_parity_gen#(.dwidth(width),.width(1)) ipgen(.i_d(s1_d),.o_d(s1_p_gen));

   wire 	    s1_err = (s1_p_gen ^ s1_p) & s1_v;
   base_vlat#(.width(1)) is2_lat(.clk(clk),.reset(reset),.din(s1_err),.q(o_error));
endmodule // capi_parcheck

   
