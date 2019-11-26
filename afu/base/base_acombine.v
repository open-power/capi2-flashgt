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
// syncronise ni inputs and no outputs.
// A transaction occurs on either all inputs and outputs, or none of them.  
module base_acombine#
  (
   parameter ni=1,
   parameter no=1)
		      
  (
   input [0:ni-1]  i_v,
   output [0:ni-1] i_r,
   output [0:no-1] o_v,
   input [0:no-1]  o_r
   );

   localparam n = ni+no;

   genvar j;
   genvar k;

   wire [0:n-1] i,o;
   assign i = {i_v,o_r};
   assign {i_r,o_v} = o;
   generate
      for (k=0; k<n; k=k+1) begin : u
	 wire [0:n-1] qi;
	 for (j=0; j<n; j=j+1) begin : v
	    if (j==k) 
	      assign qi[j] = 1'b1;
	    else
	      assign qi[j] = i[j];
	 end
	 assign o[k] = (& qi);
      end
   endgenerate
endmodule // base_acombine

		  
  
