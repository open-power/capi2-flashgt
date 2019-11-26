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
module base_multicycle_mux#
  (parameter width = 1,
   parameter stages = 1,     
   parameter early_valid=1,
   parameter stage_ways=4,
   parameter ways = stage_ways ** stages
   )
   (
    input 		       clk,
    input 		       reset,
    input [0:ways-1] 	       i_v, /* preceeds the data by one cycle */
    input [0:(ways * width)-1] i_d,
    output 		       o_v,
    output [0:width-1] 	       o_d
    );

   localparam exp_ways = stage_ways ** stages;
   wire [0:stage_ways-1] 	s1_v;
   wire [0:(stage_ways*width)-1] s1_d;

   wire [0:exp_ways-1] ii_v;    // 2*4=8
   wire [0:(exp_ways*width)-1] ii_d;

   assign ii_v[0:ways-1] = i_v[0:ways-1];   // 0:4
   assign ii_d[0:(ways * width)-1] = i_d[0:(ways * width)-1];
   wire [0:stage_ways-1]       sel;
   generate
      if (ways < exp_ways)  // 5 < 8
	begin
	   assign ii_v[ways:exp_ways-1] = {(exp_ways-ways){1'b0}};
	   assign ii_d[(ways*width):(exp_ways*width)-1] = {(exp_ways-ways)*width{1'b0}};
	end
      if (stages <= 1) // false
	begin
	   assign s1_v = ii_v;
	   assign s1_d = ii_d;
	end
      else
	begin
	   genvar 			i;
	   for(i=0; i<stage_ways; i=i+1)  //i=[0,1,2,3]
	     begin : way
		base_multicycle_mux#(.width(width),.stage_ways(stage_ways),.stages(stages-1)) irec
		 (.clk(clk),.reset(reset),
		  .i_v(ii_v[(i*stage_ways):((i+1)*stage_ways)-1]),.i_d(ii_d[(i*stage_ways*width):((i+1)*stage_ways*width)-1]),
		  .o_v(s1_v[i]),.o_d(s1_d[i*width:((i+1)*width)-1]));
	     end
	   end

      if (early_valid) 
	base_vlat#(.width(stage_ways)) isel(.clk(clk),.reset(1'b0),.din(s1_v),.q(sel));
      else
	assign sel=s1_v;
   endgenerate
   
   wire [0:width-1] 			   s2_d;
   base_mux#(.ways(stage_ways),.width(width)) imux
     (
      .sel(sel),.din(s1_d),.dout(s2_d)
      );
   base_vlat#(.width(width)) io_d(.clk(clk),.reset(1'b0),.din(s2_d),.q(o_d));
   wire 				   o_v_in = | s1_v;
   base_vlat#(.width(1)) io_v(.clk(clk),.reset(reset),.din(o_v_in),.q(o_v));

endmodule // base_multicycle_mux

	

    
     

   
