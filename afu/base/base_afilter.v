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
// filter.   if qual=1, then input goes to output.
//           if qual=0, then input is discarded. 
module base_afilter#(parameter width=1)
  (input  [0:width-1]en,
   input  [0:width-1]i_v,
   output [0:width-1]i_r,

   output [0:width-1]o_v,
   input  [0:width-1]o_r);

   assign i_r = o_r | ~en;
   assign o_v = i_v & en;
endmodule // base_afilter

