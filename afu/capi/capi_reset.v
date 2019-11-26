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
module capi_reset
  ( input clk,
    input i_reset,
    output o_reset
    );


   wire [0:3] cnt, cnt_in;
   wire       cnt_zero = (cnt == 4'b0);
   wire       cnt_en = ~cnt_zero | i_reset;
   assign cnt_in = i_reset ? 4'd1: cnt+4'd1;

   base_vlat_en#(.width(4)) icnt_lat(.clk(clk),.reset(1'b0),.din(cnt_in),.q(cnt),.enable(cnt_en));
   base_vlat#(.width(1)) irst_lat(.clk(clk),.reset(1'b0),.din(~cnt_zero),.q(o_reset));
   

endmodule // capi_jctrl_reset

   
      
      
   

   
