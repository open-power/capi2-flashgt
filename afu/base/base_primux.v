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
module base_primux#
  (   
      parameter ways = 2,
      parameter width = 1
      )
   (
    input [0:ways-1] 	     i_v,
    input [0:(ways*width)-1] i_d,
    output [0:ways-1] 	     i_r,
    output 		     o_v,
    output [0:width-1] 	     o_d, 
    input 		     o_r,
    output [0:ways-1] 	     o_sel
   );

   wire [0:ways-1]   sel;
   base_priarb#(.ways(ways)) iarb
     (.i_v(i_v), .i_r(i_r),
      .o_v(sel), .o_r(o_r)
      );
   base_mux#(.ways(ways),.width(width)) imux
     (.din(i_d), .sel(sel), .dout(o_d));
   assign o_v = | i_v;
   assign o_sel = sel;
   
endmodule // base_pri_arb

		     
