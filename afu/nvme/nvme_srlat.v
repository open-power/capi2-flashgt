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
module nvme_srlat#(parameter width = 128)
   (input  [width-1:0] set_in,
    input  reset ,
    input  clk,
    output  [width-1:0] hold_out
    );

`include "nvme_func.svh"

   reg    [width-1:0] srlat_d , srlat_q;

    always @(posedge clk or posedge reset)
    begin
        if ( reset == 1'b1 )
           srlat_q           <= zero[width-1:0];         
        else
           srlat_q          <= srlat_d;         
     end

     genvar 	       i;
     generate 
       for(i=0; i< width; i=i+1) 
       begin: gen1
         always @*
         begin
           srlat_d[i]       <= srlat_q[i];         
           if  ((set_in[i] == 1) & ~reset)
            srlat_d[i]           <= 1'b1; 
           end 
        end
     endgenerate

      assign hold_out = srlat_q;


endmodule // nvme_srlat

