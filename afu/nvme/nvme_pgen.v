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
module nvme_pgen#(parameter bits_per_parity_bit = 8,
                  parameter width = 128,
                  parameter integer pwidth = ceildiv(width, bits_per_parity_bit))
   (input  [width-1:0] data,
    input  oddpar,
    output [pwidth-1:0] datap
    );

`include "nvme_func.svh"

   genvar 	       i;

   generate
      for(i=0; i< pwidth; i=i+1)
	begin :gen1
           if((i*bits_per_parity_bit+bits_per_parity_bit) > width) 
           begin
             assign datap[i]  = ^{oddpar, data[width-1:i*bits_per_parity_bit]};
           end
           else 
           begin
	     assign datap[i]  = ^{oddpar, data[i*bits_per_parity_bit+bits_per_parity_bit-1:i*bits_per_parity_bit]};
           end
	end
   endgenerate
endmodule // nvme_pgen
 
