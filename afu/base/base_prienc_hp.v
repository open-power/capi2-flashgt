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
/* priority encoder. din[0] has highest priority */
module base_prienc_hp#
  (parameter ways=2
   )
   (
    input [0:ways-1]  din,
    output [0:ways-1] dout,
    output [0:ways-1] kill
    );
   assign kill[0] = 1'b0;
   generate
      if (ways > 1)
	begin : gen1 
	   assign kill[1:ways-1] = din[0:ways-2] | kill[0:ways-2];
	end
   endgenerate
   assign dout = din & ~kill;

endmodule // gx_prienc


   
   
   
