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
module base_initsm#
  (
   parameter LOG_COUNT = 1,
   parameter COUNT = 2 ** LOG_COUNT
   )
   (
    input 		   clk,
    input 		   reset,
    output 		   dout_v,
    output [0:LOG_COUNT-1] dout_d,
    input 		   dout_r
    );
   
   wire [0:LOG_COUNT-1] count_in,count;
   wire 		act_in,act;

   assign act_in = !(count == 0);
   assign count_in = act_in ? count-{{LOG_COUNT-1{1'b0}},1'b1} : {LOG_COUNT{1'b0}};

   wire 		en = ~dout_v | dout_r;
   
   base_vlat_en#(.width(LOG_COUNT),.rstv(COUNT-1)) countl(.clk(clk), .reset(reset), .enable(en),.din(count_in), .q(count));
   base_vlat_en#(.width(1),.rstv(1'b1))                        actl(.clk(clk), .reset(reset), .enable(en),.din(act_in), .q(act));
   assign dout_d = count;
   assign dout_v = act;
   
endmodule
 
   
   
