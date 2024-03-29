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
module base_endian_mux#(parameter bytes=8) 
   (
    input [0:(8*bytes)-1]  i_d,
    input 		   i_ctrl,
    output [0:(8*bytes)-1] o_d
    );

   
generate
   genvar 		   i;
   for(i=0; i< bytes; i=i+1) 
     begin : gen1
	assign o_d[(i*8): ((i+1)*8)-1] = i_ctrl ? i_d[(bytes-i)*8-8 : (bytes-i)*8-1] : i_d[(i*8):((i+1)*8)-1];
     end
endgenerate
   
endmodule // base_endian_szl


	

					  
