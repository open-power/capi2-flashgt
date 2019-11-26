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
module base_vlat_sr#(parameter width=1)
  (
   input 	      clk,
   input [0:width-1]  set,
   input [0:width-1]  rst,
   input 	      reset,
   output [0:width-1] q
   );

   
   reg [0:width-1]    q_int;
   initial q_int = 0;

   genvar 	      i;
   generate
      for(i=0; i< width; i=i+1)
	begin : u0
	   always@(posedge clk or posedge reset) 
	     if (reset) q_int[i] <= 1'b0;
	     else if (set[i] | rst[i]) q_int[i] <= set[i];
	end
   endgenerate
   assign q = q_int;
endmodule // base_vlat_sr


   
  
