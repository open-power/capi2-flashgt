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
module base_emux#
  (
   parameter width = 1,
   parameter ways = 1,
   parameter sel_width=$clog2(ways)
   )
  (
   input [0:(width*ways)-1] din,
   input [0:sel_width-1]    sel,
   output [0:width-1] 	    dout
   );

   wire [0:ways-1] 	    sel_dec;
   base_decode#(.enc_width(sel_width),.dec_width(ways)) ienc(.en(1'b1),.din(sel),.dout(sel_dec));
   base_mux#(.width(width),.ways(ways)) imux(.sel(sel_dec),.din(din),.dout(dout));

endmodule // base_emux
   
		
