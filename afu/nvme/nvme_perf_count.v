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
//  File : nvme_perf_count.v
//  *************************************************************************
//  *************************************************************************
//  Description :
//  *************************************************************************

module nvme_perf_count#
  ( 
    parameter sum_width = 64,
    parameter active_width = 10
    )
   (
    input                     reset,
    input                     clk,

    // event count controls
    input                     incr, // start of event
    input                     decr, // end of event
    input                     clr, // clears active_cnt

    // results
    output [active_width-1:0] active_cnt,
    output    [sum_width-1:0] complete_cnt,
    output    [sum_width-1:0] sum,
    input                     clr_sum  // clear sum, complete_cnt
 
    );


   reg                        incr_q, decr_q;
   always @(posedge clk)
     begin
        incr_q <= incr;
        decr_q <= decr;
     end
   
   // counter incremented when event starts, decremented at end of event
   reg [9:0] active_cnt_q, active_cnt_d;

   // summation of active_cnt_q 
   reg [63:0] sum_q, sum_d;
 
   // count completed events (number of decrements)
   reg [63:0] complete_cnt_q, complete_cnt_d;
 
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             active_cnt_q   <= '0;
             sum_q          <= '0;
             complete_cnt_q <= '0;          
          end
        else
          begin
             sum_q          <= sum_d;
             complete_cnt_q <= complete_cnt_d;
             active_cnt_q   <= active_cnt_d;   
          end
     end
   
   
   always @*
     begin
        if( clr )
          begin
             active_cnt_d = '0;
          end
        else
          begin
             active_cnt_d   = active_cnt_q;	
             
             // should handle overflow/underflow as error - counters will be wrong
             if( incr_q ) active_cnt_d = active_cnt_d + 'd1;
             if( decr_q ) active_cnt_d = active_cnt_d - 'd1;
          end

        if( clr_sum )
          begin
             complete_cnt_d = '0;
             sum_d = '0;
          end
        else
          begin
             if( decr_q )
               begin
                  complete_cnt_d = complete_cnt_q + 10'd1;
               end
             else
               begin
                  complete_cnt_d   = complete_cnt_q;
               end
             
             sum_d = sum_q + active_cnt_q;
          end
        
     end

   assign active_cnt = active_cnt_q;
   assign complete_cnt = complete_cnt_q;
   assign sum = sum_q;

   
endmodule


  
