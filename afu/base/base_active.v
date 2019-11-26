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
// track whether a stream demarked by _e is active or not 
// o_act is high when a stream is active
// o_act turns on when i_v and i_r happen.
// o_act turns off when i_e happens. - o_act and i_e do not overlap. 

module base_active#(parameter del=0)
  (input clk, input reset,
   input  i_v,
   input  i_r,
   input  i_e,
   output o_act

   );

   wire   i_act = i_v & i_r;
   wire   strm_active_fb;
   wire   strm_active = (i_act & ~i_e) | (strm_active_fb & ~(i_act & i_e));
   base_vlat#(.width(1)) istrm_act(.clk(clk),.reset(reset),.din(strm_active),.q(strm_active_fb));
   generate
      if (del) assign o_act = strm_active_fb;
      else assign o_act = strm_active;
   endgenerate
   
endmodule // base_active


   
