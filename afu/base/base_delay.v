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
// a simple n-cycle delay
module base_delay#
  (parameter width = 1,
   parameter n = 1)
  (input clk,
   input reset,
   input [0:width-1]  i_d,
   output [0:width-1] o_d
   );

   generate
      if (n > 0)
	begin
	   wire [0:(n * width)-1] l_din, l_q;
	   
	   assign l_din[0:width-1] = i_d;
	   if (n > 1)
	     assign l_din [width:(n*width)-1] = l_q[0:((n-1)*width)-1];
	   
	   base_vlat#(.width(width*n)) ilat(.clk(clk),.reset(reset),.din(l_din),.q(l_q));
	   assign o_d = l_q[(n-1)*width:(n*width)-1];
	end
      else
	assign o_d = i_d;
   endgenerate
endmodule // base_delay


   
		  
