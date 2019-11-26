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
module base_mem#
  (
   parameter width = 1,
   parameter addr_width = 1,
   parameter depth = 2 ** addr_width,
   parameter wdelay = 0
   )
   (
   input clk,
   input we,
   input [addr_width-1:0] wa,
   input [width-1:0] 	  wd,
   input re,
   input [addr_width-1:0] ra,
   output [width-1:0] 	  rd
    );
   
   reg [width-1:0] 	  rd_int;
   reg [width-1:0] 	  ram[depth-1:0];

   wire 		  we_d;
   wire [addr_width-1:0]  wa_d;
   wire [width-1:0] 	  wd_d;

   base_delay#(.width(1+addr_width+width),.n(wdelay)) idel
     (
      .clk(clk),.reset(1'b0),
      .i_d({we,wa,wd}),
      .o_d({we_d,wa_d,wd_d})
      );

   always@(posedge clk) begin
      if (we_d) ram[wa_d] <= wd_d;
   end 
   always@(posedge clk) begin 
      if (re) rd_int <= ram[ra];
   end 
   assign rd = rd_int;
endmodule // base_mem

   
   
		  
