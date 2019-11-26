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
//  File : nvme_adq_cq.v
//  *************************************************************************
//  *************************************************************************
//  Description : Surelock Express NVMe Admin Q
//
//  Admin Completion Queue
//  *************************************************************************

module nvme_ucq_cq#
  (     
        parameter num_entries = 4,
        parameter data_width = 128,
        parameter cid_width = 16,
        parameter cq_ptr_width = $clog2(num_entries),
        parameter cq_width = 128,
        parameter cq_par_width = 128/8,
        parameter cq_rdwidth = 32,
        parameter cq_par_rdwidth = 32/8,
        parameter cq_wrwidth = 128,
        parameter cq_par_wrwidth = 128/8,
        parameter cq_num_words = num_entries * (16/(cq_wrwidth/8)),
        parameter cq_num_wren = 1,
        parameter cq_addr_width = $clog2(cq_num_words),
        parameter sq_ptr_width = $clog2(num_entries),
        parameter ioaddr_base = 0
    )
   (
   
    input                                  reset,
    input                                  clk, 
   
    //-------------------------------------------------------
    // ucontrol IO bus
    //-------------------------------------------------------
    input                           [31:0] ctl_cq_ioaddress,
    input                                  ctl_cq_ioread_strobe, 
    input                           [35:0] ctl_cq_iowrite_data, // change 31 to 35 kch 
    input                                  ctl_cq_iowrite_strobe,
    output reg                      [35:0] cq_ctl_ioread_data, // read_data is sampled when ioack=1
    output reg                             cq_ctl_ioack,

    
    // ----------------------------------------------------------
    // queue controls
    // ----------------------------------------------------------
    input                                  cq_reset,
    output reg          [cq_ptr_width-1:0] cq_head, 
    output reg          [cq_ptr_width-1:0] cq_tail,
    output reg                             cq_phase,

    output reg          [sq_ptr_width-1:0] sq_head,
    output reg                             sq_head_update,
    output reg                             cq_empty,
    
    // ----------------------------------------------------------
    // queue update from endpoint
    // ----------------------------------------------------------

    input                                  cq_wren,
    input              [cq_addr_width-1:0] cq_wraddr,
    input [ cq_par_wrwidth+cq_wrwidth-1:0] cq_wrdata
    
    );

   
`include "nvme_func.svh"


   //-------------------------------------------------------
   // Admin Completion Queue (CQ)
   //-------------------------------------------------------


   // 16B per queue entry
   // same number of entries as submission queue
   // 
   // read interface width:   4B - 4x4B per entry
   // write interface width: 16B - 16x1 per entry


   localparam cq_last_entry = num_entries-1;

   reg [   cq_par_width+cq_width-1:0] cq_mem[cq_num_words-1:0];
   
   reg  [   cq_par_wrwidth+cq_wrwidth-1:0] cq_rddata;
   reg                 [cq_addr_width-1:0] cq_rdaddr;
   reg  [   cq_par_rdwidth+cq_rdwidth-1:0] cq_rddata_dw;
   
   always @(posedge clk)   
      cq_rddata <= cq_mem[cq_rdaddr];
  
   always @(posedge clk)
     if (cq_wren)
       cq_mem[cq_wraddr] <= cq_wrdata;      


   reg [cq_ptr_width-1:0] cq_head_q, cq_head_d; // read pointer
   reg [cq_ptr_width-1:0] cq_tail_q, cq_tail_d; // write pointer
   reg                     cq_phase_q, cq_phase_d;
   reg                     cq_full;   // NVMe spec says full when head=tail+1
   reg                     cq_empty_q, cq_empty_d;  // head=tail
   reg                     cq_head_inc;  // incremented when microcontroller finishes reading completion queue entry
   
   reg                     cq_wrack;
   reg                     cq_rdack;
   
   reg                     cq_rdvalid_q, cq_rdvalid_d;

   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             cq_head_q    <= zero[cq_ptr_width-1:0];
             cq_tail_q    <= zero[cq_ptr_width-1:0];
             cq_phase_q   <= 1'b1;
             cq_rdvalid_q <= 1'b0;     
             cq_empty_q   <= 1'b0;            
          end
        else
          begin
             cq_head_q    <= cq_head_d;
             cq_tail_q    <= cq_tail_d;
             cq_phase_q   <= cq_phase_d;
             cq_rdvalid_q <= cq_rdvalid_d;
             cq_empty_q   <= cq_empty_d;            
          end
     end


   // manage head & tail pointers
   always @*
     begin
        cq_head_d  = cq_head_q + (cq_head_inc ? one[cq_ptr_width-1:0] : zero[cq_ptr_width-1:0]);
        cq_tail_d  = cq_tail_q + (cq_wren ? one[cq_ptr_width-1:0] : zero[cq_ptr_width-1:0]);
        cq_full    = cq_head_q==(cq_tail_q+one[cq_ptr_width-1:0]);
        
        // flip the expected phase bit on rollover	
        if( cq_head_inc &&           
            cq_head_q == cq_last_entry[cq_ptr_width-1:0] )
          begin
             cq_phase_d = ~cq_phase_q;
          end
        else
          begin
             cq_phase_d = cq_phase_q;
          end
        
        if( cq_reset )
          begin
             cq_head_d  = zero[cq_ptr_width-1:0];
             cq_tail_d  = zero[cq_ptr_width-1:0];
             cq_phase_d = 1'b1;
          end
        
        cq_empty_d      = cq_head_d==cq_tail_d;
        cq_empty        = cq_empty_q;

     end

   wire                    cq_cntl_par;
   nvme_pgen#
     (
      .bits_per_parity_bit(3),
      .width(3)
      ) ipgen_cq_cntl 
       (.oddpar(1'b1),.data({cq_empty_q, cq_full, cq_phase_q!=cq_rddata[32*3+16]}),.datap(cq_cntl_par)); 


   // read CQ from microcontroller
   // write to CQ to free entry at head
   always @*
     begin

        // offset 0x80, 0x84, 0x88, 0x8C - CQ_ENTRY
        cq_rdaddr = cq_head_q;
        case(ctl_cq_ioaddress[3:2])
          2'h0:    cq_rddata_dw  = {cq_rddata[131:128],cq_rddata[31:0]};
          2'h1:    cq_rddata_dw  = {cq_rddata[135:132],cq_rddata[63:32]};
          2'h2:    cq_rddata_dw  = {cq_rddata[139:132],cq_rddata[95:64]};
          default: cq_rddata_dw  = {cq_rddata[143:140],cq_rddata[127:96]};
        endcase // case (ctl_cq_ioaddress[3:2])
        
        cq_rdvalid_d = 1'b0;                
        if( ctl_cq_ioread_strobe )
          begin
             // ack for offset 0x80-0xFC
             if (ctl_cq_ioaddress[11:7] == {ioaddr_base[3:0],1'b1})
               begin
                  cq_rdvalid_d = 1'b1;
               end
          end
        if( ctl_cq_ioaddress[7:4]==4'hB )
          begin
             // offset 0xB0 - CQ_STATUS
             // phase bit is DW3 bit 16.  bit 0 of CQ_STATUS=0 if phase bits match (entry is valid)
             cq_rddata_dw = { one[35:33],cq_cntl_par,zero[31:3],cq_empty_q, cq_full, cq_phase_q!=cq_rddata[32*3+16] };
          end
        cq_rdack = cq_rdvalid_q;

        sq_head        = cq_rddata[sq_ptr_width-1+64:64];
        sq_head_update = 1'b0;
        
        cq_wrack = 1'b0;
        cq_head_inc = 1'b0;
        if( ctl_cq_iowrite_strobe )
          begin
             if (ctl_cq_ioaddress[11:7] == {ioaddr_base,1'b1})
               begin                  
                  cq_wrack = 1'b1;
                  if( ctl_cq_ioaddress[7:0]==8'hC0 )
                    begin
                       // offset 0xC0 - CQ_REMOVE
                       cq_head_inc = ~cq_empty_q;
                       sq_head_update = 1'b1;
                    end
               end
          end  
        
     end // always @ *

   always @*
     begin
        cq_ctl_ioread_data  = cq_rddata_dw;
        cq_ctl_ioack        = cq_wrack | cq_rdack;
        cq_head             = cq_head_q;
        cq_tail             = cq_tail_q;
        cq_phase            = cq_phase_q;
     end
   
   
 
   
endmodule


