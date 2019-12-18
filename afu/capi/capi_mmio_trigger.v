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
module capi_mmio_trigger #
  (
   parameter addr_mask = 0,
   parameter addr_width = 25, 
   parameter addr = 0
   )
   (
    input 		   clk,
    input 		   reset,
    input [0:addr_width-1] wa,
    input 		   we,
    output 		   trigger
    );
   localparam [0:addr_width-2]   our_addr = addr;   
   localparam [0:addr_width-2]   our_mask = addr_mask;  

   wire [0:addr_width-2]   mskd_addr = ~our_mask & wa[0:addr_width-2]; 
   
   wire 		   addr_match = (our_addr == mskd_addr);
   wire 		   trigger_in = we & addr_match;
   base_vlat#(.width(1)) itrg(.clk(clk), .reset(reset), .din(trigger_in), .q(trigger));
endmodule

  
   
   
    
