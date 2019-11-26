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
module base_mux#
  (
   parameter width = 1,
   parameter ways = 2
   )
  (
   input [0:(width*ways)-1] din,
   input [0:ways-1] sel,
   output [0:width-1] dout
   );
   genvar 	  i;
   genvar         j;
   generate
      if (width == 1)
	assign dout = | (sel & din);
      else
	for (i = 0; i < width; i = i + 1) begin : u
	   wire [0:ways-1] mux_in;
	   for (j = 0; j < ways; j = j + 1) begin : v
	      assign mux_in[j] = din[(j*width)+i];
	   end
	   base_mux#(.ways(ways),.width(1)) imux(.din(mux_in), .sel(sel), .dout(dout[i]));
	end
   endgenerate
endmodule // base_mux
   
		
