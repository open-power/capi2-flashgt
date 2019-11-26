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
module base_afirst
  (input clk, input reset,
   input  i_r,
   input  i_v,
   input  i_e,
   output o_first
   );
   wire   active;
   base_active#(.del(1)) iact(.clk(clk),.reset(reset),.i_v(i_v),.i_r(i_r),.i_e(i_e),.o_act(active));
//   assign o_first = i_v & ~i_e & ~active;
   assign o_first = i_v & ~active;
endmodule // base_afirst

   
   
