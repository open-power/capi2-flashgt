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
//  File : nvme_fifo.v
//  *************************************************************************
//  *************************************************************************
//  Description : fifo with valid output
//                when valid is asserted, dout is valid and may be popped
//                when full is asserted, push is discarded
//  *************************************************************************

module nvme_fifo#
  ( 
    parameter width = 8,
    parameter words = 256,
    parameter almost_full_thresh = 0,  // assert almost_full when thresh entries are free
    parameter awidth = $clog2(words)
    )
   (
    input                  reset,
    input                  clk,

    input                  push,
    input                  pop,
    input      [width-1:0] din,
    input                  flush,

    output reg             dval,
    output reg [width-1:0] dout, 
    output reg             full,
    output reg             almost_full,
    output reg  [awidth:0] used
 
    );

   localparam [511:0] zero = 512'd0;
   localparam [511:0]  one = {511'd0, 1'b1};
  
     
   reg         [width-1:0] fifo[0:words-1];
   reg                     write;
   
   reg        [awidth-1:0] wptr_q, wptr_d;
   reg        [awidth-1:0] rptr_q, rptr_d;
   reg          [awidth:0] used_q, used_d;
   reg                     empty_q, empty_d;
   reg                     full_q, full_d;
   reg                     almost_full_q, almost_full_d;

   reg                     read;
   reg                     read_taken;
   reg         [width-1:0] read_dout;
   reg                     read_v_q, read_v_d;
   
   // output register
   reg         [width-1:0] rdata_q, rdata_d;
   reg                     rdata_v_q, rdata_v_d;

   // ram with old data for read-during-write
   always @(posedge clk)
     begin
        if (write)
          fifo[wptr_q] <= din;
        if (read)
          read_dout <= fifo[rptr_q];
     end
   
   always @(posedge clk or posedge reset)
     begin
        if ( reset == 1'b1 )
          begin
             wptr_q        <= zero[awidth-1:0]; 
             rptr_q        <= zero[awidth-1:0];
             used_q        <= zero[awidth:0];
             empty_q       <= 1'b1;
             full_q        <= 1'b0;
             almost_full_q <= 1'b0;
             read_v_q      <= 1'b0;
             rdata_q       <= zero[width-1:0];
             rdata_v_q     <= 1'b0;
          end
        else
          begin
             wptr_q        <= wptr_d; 
             rptr_q        <= rptr_d;
             used_q        <= used_d;  
             empty_q       <= empty_d;
             full_q        <= full_d;
             almost_full_q <= almost_full_d;
             read_v_q      <= read_v_d;
             rdata_q       <= rdata_d;
             rdata_v_q     <= rdata_v_d;
          end
     end

   
   always @*
     begin
        write      = 1'b0;
        wptr_d     = wptr_q;
        rptr_d     = rptr_q;
        used_d     = used_q;

        read       = 1'b0;
        read_v_d   = read_v_q & ~read_taken;
        
        if( push & ~full_q )
          begin
             write   = 1'b1;
             wptr_d  = wptr_q + one[awidth-1:0];
             used_d  = used_d + one[awidth:0];
          end
    
        if( ~empty_q & ~read_v_d )
          begin
             read      = 1'b1;
             read_v_d  = 1'b1;
             rptr_d    = rptr_q + one[awidth-1:0];
             used_d    = used_d - one[awidth:0];
          end

        if( flush )
          begin
             wptr_d  = zero[awidth-1:0];
             rptr_d  = zero[awidth-1:0];
             used_d  = zero[awidth:0];
          end

        
        // pointer wrap for non power of 2 sizes
        if( rptr_d == words[awidth-1:0] )
          rptr_d  = zero[awidth-1:0];
        if( wptr_d == words[awidth-1:0] )
          wptr_d  = zero[awidth-1:0];

        empty_d        = (used_d == zero[awidth:0]);
        full_d         = (used_d == words[awidth:0]);
        almost_full_d  = (used_d >= (words[awidth:0]-almost_full_thresh[awidth:0]));

        full           = full_q;
        almost_full    = almost_full_q;
        used           = used_q;

     end

   
   // load output register
   always @*
     begin
        read_taken = 1'b0;

        rdata_d    = rdata_q;
        rdata_v_d  = rdata_v_q;       

        if( pop | ~rdata_v_q)
          begin
             if( read_v_q )
               begin     
                  read_taken = 1'b1;
                  rdata_v_d  = 1'b1;
                  rdata_d    = read_dout;
               end
             else
               begin
                  rdata_v_d  = 1'b0;
               end
          end

        if( flush )
          begin
             rdata_v_d  = 1'b0;
          end

        dval  = rdata_v_q;
        dout  = rdata_q;       
               
     end

endmodule // nvme_fifo


  
