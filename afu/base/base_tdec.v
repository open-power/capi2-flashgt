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
/* dencode a number into "thermometer decoded" output
   n dec  tdec 
   0 100  000
   1 010  100 
   2 001  110 
   3 000  111
   4 000  111 
  Input must be in ths format
 */
module base_tdec#(parameter dec_width=1,parameter enc_width = 1)
   (input [0:enc_width-1] i_d,
    output [0:dec_width-1] o_d
    );


   wire [0:dec_width-1]    s0_dec;
   base_decode#(.enc_width(enc_width),.dec_width(dec_width)) idec(.din(i_d),.dout(s0_dec),.en(1'b1));
   genvar 			      i;
   generate
      for(i=0; i<dec_width; i=i+1)
	begin : gen1
	   assign o_d[i] = ~ (| s0_dec[0:i]);
	   
	end
   endgenerate
endmodule // base_tenc

