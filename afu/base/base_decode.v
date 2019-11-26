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
module base_decode#
  (
   parameter enc_width=1,
   parameter dec_width = 2 ** enc_width
   )
  (
   input en,
   input [0:enc_width-1] din,
   output [0:dec_width-1] dout
   );
   
   genvar 		  i;
   generate
      for(i=0; i<dec_width; i=i+1) begin : Gen
	 assign dout[i] = en & (din == i);
      end
   endgenerate
endmodule // gx_decode

