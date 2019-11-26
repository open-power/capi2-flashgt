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

`timescale 1ns/1ns

// pipeline stage to "burp" on backpressure for timing
// based on Andy Martin's base_aburp

module nvme_pl_burp
  #(
    parameter width = 128,
    parameter stage = 0   // if 1, add a pipeline state on input
  )
  (
   input              clk,
   input              reset,
   
   input              valid_in,
   input  [width-1:0] data_in,
   output             ready_out,

   output             valid_out,
   output [width-1:0] data_out,
   input              ready_in
   
);

   // pipeline with zero latency valid/ready
   // pipeline advances if valid & ready (data is taken)
   // output comes from burp register if its valid
   // otherwise output=input


   // pipeline stage registers
   reg                valid_q;
   reg    [width-1:0] data_q;


   // pipeline stall registers
   reg                s_valid_q;
   reg    [width-1:0] s_data_q;
   wire               s_ready;
   
   generate 
      if (stage==1)        
        begin
           // add pipeline stage on input
           always @(posedge clk or posedge reset) 
             if( reset )       
               valid_q <= 1'b0;   
             else
               valid_q <= valid_in | (~s_ready & valid_q);
           
           always @(posedge clk)
             if( s_ready | ~valid_q )
               data_q <= data_in;

           assign ready_out = s_ready | ~valid_q;
        end
      else
        begin
           always @*
             begin
                valid_q = valid_in;
                data_q  = data_in;                
             end
           assign ready_out = s_ready;
        end
   endgenerate
   
         
   always @(posedge clk or posedge reset) 
     if( reset )       
       s_valid_q <= 1'b0;   
     else	        
       s_valid_q <= ~ready_in & (s_valid_q | valid_q);                	

   always @(posedge clk)
     if( ~s_valid_q )
       s_data_q <= data_q;
              
   assign s_ready = ~s_valid_q;
   assign data_out  = (s_valid_q) ? s_data_q  : data_q;
   assign valid_out = (s_valid_q) ? s_valid_q : valid_q;

endmodule

