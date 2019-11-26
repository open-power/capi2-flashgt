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
module base_or#(parameter width=1, parameter ways=1)
   (input [0:ways*width-1] i_d,
    output [0:width-1] o_d
    );

   genvar 	       i;
   genvar 	       j;
   generate
      for (i = 0; i < width; i = i + 1) begin : u
	 wire [0:ways-1] or_in;
	 for (j = 0; j < ways; j = j + 1) begin : v
	    assign or_in[j] = i_d[(j*width)+i];
	 end
	 assign o_d[i] = | or_in;
      end
   endgenerate
endmodule // base_or
