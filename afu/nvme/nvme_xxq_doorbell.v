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
`timescale 1 ns / 10 ps

//  *************************************************************************
//  File : nvme_xxq_doorbell.v
//  *************************************************************************
//  *************************************************************************
//  Description : Surelock Express NVMe doorbell mmio write generator
//


module nvme_xxq_doorbell#
  (     parameter sq_num_queues = 1,
        parameter sq_ptr_width = 2,
       
        parameter cq_num_queues = 1,
        parameter cq_ptr_width = 2
                     
    )
   (
   
    input                                  reset,
    input                                  clk, 

    input                                  q_reset,
    input                           [31:0] doorbell_start_addr,
    input                            [3:0] doorbell_stride,
    
    // head/tail pointers for each queue
    input [sq_num_queues*sq_ptr_width-1:0] sq_tail,
    input [cq_num_queues*cq_ptr_width-1:0] cq_head,
    input [cq_num_queues*cq_ptr_width-1:0] cq_tail,

    //-------------------------------------------------------
    // Admin Q doorbell write
    //-------------------------------------------------------
    output reg                             xxq_pcie_wrvalid,
    output reg                      [31:0] xxq_pcie_wraddr,
    output reg                      [15:0] xxq_pcie_wrdata,
    input                                  pcie_xxq_wrack
     
    );

`include "nvme_func.svh"

   localparam cq_id_width=$clog2(cq_num_queues)+1;
   localparam sq_id_width=$clog2(sq_num_queues)+1;

 

   //-------------------------------------------------------
   // Doorbell MMIO writes
   //-------------------------------------------------------
   // send mmio write when cq_head_last != cq_head or sq_tail_last != sq_tail
   //
   reg [cq_num_queues*cq_ptr_width-1:0] cq_head_last_q; 
   reg              [cq_num_queues-1:0] cq_head_diff_q;
   reg                [cq_id_width-1:0] cq_head_idx_q;
   
   reg [sq_num_queues*sq_ptr_width-1:0] sq_tail_last_q;
   reg              [sq_num_queues-1:0] sq_tail_diff_q;
   reg                [sq_id_width-1:0] sq_tail_idx_q;

   reg                           [3:0] db_state_q;

   reg [cq_num_queues*cq_ptr_width-1:0] cq_head_last_d; 
   reg              [cq_num_queues-1:0] cq_head_diff_d;
   reg                [cq_id_width-1:0] cq_head_idx_d;
   
   reg [sq_num_queues*sq_ptr_width-1:0] sq_tail_last_d;
   reg              [sq_num_queues-1:0] sq_tail_diff_d;
   reg                [sq_id_width-1:0] sq_tail_idx_d;

   reg                            [3:0] db_state_d;
   
   localparam DB_IDLE = 4'h1;
   localparam DB_SQ   = 4'h2;
   localparam DB_CQ   = 4'h3;
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             cq_head_last_q <= zero[sq_ptr_width-1:0];
             cq_head_diff_q <= zero[cq_num_queues-1:0];
             cq_head_idx_q  <= zero[cq_id_width-1:0];
             sq_tail_last_q <= zero[sq_ptr_width-1:0];
             sq_tail_diff_q <= zero[sq_num_queues-1:0];
             sq_tail_idx_q  <= zero[sq_id_width-1:0];
             db_state_q     <= DB_IDLE;
          end
        else
          begin
             cq_head_last_q <= cq_head_last_d;
             cq_head_diff_q <= cq_head_diff_d;
             cq_head_idx_q  <= cq_head_idx_d;
             sq_tail_last_q <= sq_tail_last_d;
             sq_tail_diff_q <= sq_tail_diff_d;
             sq_tail_idx_q  <= sq_tail_idx_d;
             db_state_q     <= db_state_d;
          end
     end

   // check if any of the pointers changed since last mmio write
   wire [cq_num_queues-1:0] cq_head_diff;
   wire [sq_num_queues-1:0] sq_tail_diff;
   wire  [cq_ptr_width-1:0] cq_head_last_mx[cq_num_queues-1:0];
   wire  [sq_ptr_width-1:0] sq_tail_last_mx[sq_num_queues-1:0];
   wire  [cq_ptr_width-1:0] cq_head_last;
   wire  [sq_ptr_width-1:0] sq_tail_last;
   
 
   genvar qptr;
   generate for(qptr=0; qptr<cq_num_queues; qptr=qptr+1) begin: cq_ptr_diff
      assign cq_head_diff[qptr] = cq_head_last_q[cq_ptr_width*(qptr+1)-1:cq_ptr_width*qptr] != cq_head[cq_ptr_width*(qptr+1)-1:cq_ptr_width*qptr];
      assign cq_head_last_mx[qptr] = cq_head_last_q[cq_ptr_width*(qptr+1)-1:cq_ptr_width*qptr];
   end
   endgenerate

   generate for(qptr=0; qptr<sq_num_queues; qptr=qptr+1) begin: sq_ptr_diff     
      assign sq_tail_diff[qptr] = sq_tail_last_q[sq_ptr_width*(qptr+1)-1:sq_ptr_width*qptr] != sq_tail[sq_ptr_width*(qptr+1)-1:sq_ptr_width*qptr];
      assign sq_tail_last_mx[qptr] = sq_tail_last_q[sq_ptr_width*(qptr+1)-1:sq_ptr_width*qptr];
   end
   endgenerate      

   assign cq_head_last = cq_head_last_mx[cq_head_idx_q];
   assign sq_tail_last = sq_tail_last_mx[sq_tail_idx_q];

   reg [31:0] sq_doorbell_offset;
   reg [31:0] cq_doorbell_offset;
   always @*
     begin
        cq_head_last_d    = cq_head_last_q;
        cq_head_diff_d    = cq_head_diff_q;
        cq_head_idx_d     = cq_head_idx_q;
        sq_tail_last_d    = sq_tail_last_q;
        sq_tail_diff_d    = sq_tail_diff_q;        
        sq_tail_idx_d     = sq_tail_idx_q;        
        db_state_d        = db_state_q;

        xxq_pcie_wrvalid  = 1'b0;
        xxq_pcie_wraddr   = 32'h0;
        xxq_pcie_wrdata   = 16'h0;

        sq_doorbell_offset = {sq_tail_idx_q,3'b000};
        sq_doorbell_offset = sq_doorbell_offset<<doorbell_stride;
        cq_doorbell_offset = {cq_head_idx_q,3'b100};
        cq_doorbell_offset = cq_doorbell_offset<<doorbell_stride;
      
        if( cq_head_diff_q == zero[cq_num_queues-1:0] )
          begin
             cq_head_diff_d = cq_head_diff;
             cq_head_idx_d  = zero[cq_id_width-1:0];
             cq_head_last_d = cq_head;
          end
        
        if( sq_tail_diff_q == zero[sq_num_queues-1:0] )
          begin
             sq_tail_diff_d = sq_tail_diff;
             sq_tail_idx_d = zero[sq_id_width-1:0];
             sq_tail_last_d = sq_tail;
          end
         
                
        case(db_state_q)
          DB_IDLE:
            begin
               if( ~q_reset )
                 begin
                    if( cq_head_diff_q != zero[cq_num_queues-1:0] )
                      begin
                         db_state_d = DB_CQ;
                      end
                    else if( sq_tail_diff_q != zero[sq_num_queues-1:0] )
                      begin
                         db_state_d = DB_SQ;
                      end  
                 end             
            end
          DB_SQ:
            begin
               xxq_pcie_wrdata   = {zero[15:sq_ptr_width], sq_tail_last};
               xxq_pcie_wraddr   = doorbell_start_addr + sq_doorbell_offset;
               if( sq_tail_diff_q[sq_tail_idx_q] )
                 begin
                    xxq_pcie_wrvalid  = 1'b1;
                    if( pcie_xxq_wrack )
                      begin
                         if( cq_head_diff_q != zero[cq_num_queues-1:0] )
                           begin
                              db_state_d = DB_CQ;
                           end
                         else
                           begin
                              db_state_d = DB_IDLE;
                           end
                         sq_tail_diff_d[sq_tail_idx_q]=1'b0;
                      end
                 end
               else
                 begin
                    sq_tail_idx_d = sq_tail_idx_q + 1;
                 end               
            end
          DB_CQ:
            begin
               xxq_pcie_wrdata   = {zero[15:sq_ptr_width], cq_head_last};
               xxq_pcie_wraddr   = doorbell_start_addr + cq_doorbell_offset;
               if( cq_head_diff_q[cq_head_idx_q] )
                 begin
                    xxq_pcie_wrvalid  = 1'b1;
                    if( pcie_xxq_wrack )
                      begin
                         if( sq_tail_diff_q != zero[sq_num_queues-1:0] )
                           begin
                              db_state_d = DB_SQ;
                           end
                         else
                           begin
                              db_state_d = DB_IDLE;
                           end
                         cq_head_diff_d[cq_head_idx_q]=1'b0;
                      end                    
                 end
               else
                 begin
                    cq_head_idx_d = cq_head_idx_q+1;                  
                 end               
            end
          default:
            begin
               db_state_d = DB_IDLE;
            end
        endcase // case (db_state_q)        

        if( q_reset )
          begin
             cq_head_last_d    = zero[cq_num_queues*cq_ptr_width-1:0];
             cq_head_diff_d    = zero[cq_num_queues-1:0];
             sq_tail_last_d    = zero[cq_num_queues*sq_ptr_width-1:0];
             sq_tail_diff_d    = zero[sq_num_queues-1:0];             
          end
        
     end
   

endmodule
