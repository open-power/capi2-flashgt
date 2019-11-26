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
// mux to handle single-word reads from mmio space
module capi_mmio_sw_mux
  (input ha_mmdw,
   input 	 ha_mmad,
   input [0:63]  din,
   output [0:63] dout
   );

   wire 	 upr_sel_lwr = ~ha_mmdw & ~ha_mmad;
   wire 	 lwr_sel_upr = ~ha_mmdw & ha_mmad;
   assign dout[00:31] = upr_sel_lwr ? din[32:63] : din[00:31];
   assign dout[32:63] = lwr_sel_upr ? din[00:31] : din[32:63];
endmodule
   
   
			
  
