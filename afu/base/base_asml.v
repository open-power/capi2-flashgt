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
module base_asml#
  (
   parameter width = 1
  )
  (input clk, input reset,
   output 	      ir_r, 
   input [0:width-1]  ir_d, // reset input 
   input 	      ir_v, 

   input [0:width-1]  if_d, // feedback input
   input 	      if_v, 

   input 	      o_r, 
   output 	      o_v, 
   output [0:width-1] o_d
   );

   wire [0:width-1] s0_d;
   wire 	    s0_v, s0_r;
   wire 	    if_r;  // purposely disconnected

   wire 	    sel_rst = ~if_v | ~o_v;
   
	
   wire [0:width]   ltch_in = sel_rst ? {ir_v,ir_d} : {o_v,if_d};
   wire 	    ltch_en = o_r | ~o_v;
   assign ir_r = sel_rst & ltch_en;
   

   base_vlat_en#(.width(width+1)) idl
     (.clk(clk),.reset(reset),.enable(ltch_en),.din(ltch_in),.q({o_v,o_d}));

endmodule // baase_asm

    
   
  
		 
