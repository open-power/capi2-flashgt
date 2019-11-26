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
module base_encode#(parameter enc_width=1, parameter dec_width=2)
   (input [0:dec_width-1] i_d,
    output [0:enc_width-1] o_d,
    output o_v
    );

   wire [0:enc_width*dec_width-1] mux_in;
   genvar 			  i;
   generate
      for(i=0; i< dec_width; i=i+1)
	begin : gen1
	   base_const#(.width(enc_width),.value(i)) iconst(mux_in[enc_width*i:enc_width*(i+1)-1]);
	end
   endgenerate
   base_mux#(.width(enc_width),.ways(dec_width)) imux(.sel(i_d),.din(mux_in),.dout(o_d));
   assign o_v = | i_d;
endmodule // base_encode
