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
//  *************************************************************************
//  File : nvme_cdc.v
//  *************************************************************************
//  *************************************************************************
//  Description : clock domain crossing
//  *************************************************************************

module nvme_cdc#(
                 parameter stages = 3
                 )
   (
    input  clk,
    input  d,
    output q
    );
  
   (* ASYNC_REG="TRUE",SHIFT_EXTRACT = "NO" *) reg [stages-1:0] meta_q = 2'b00; 
   always @(posedge clk)
     begin
        meta_q <= { meta_q[stages-2:0],d};
     end

   assign q = meta_q[stages-1];
endmodule // nvme_cdc
