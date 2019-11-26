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
//  File : nvme_adq_sq.v
//  *************************************************************************
//  *************************************************************************
//  Description : Surelock Express NVMe microcode queue
//
//  NVMe Submission Queue
//  *************************************************************************

module nvme_ucq_sq#
  (     
        parameter num_entries = 4,
        parameter sq_width = 128,
        parameter sq_par_width = sq_width/8,
        parameter sq_entry_bytes = 64,
        parameter sq_rdwidth = 128,
        parameter sq_par_rdwidth = sq_rdwidth/8,
        parameter sq_wrwidth = 32,
        parameter sq_par_wrwidth = sq_wrwidth/8,
        
        parameter sq_words_per_entry = sq_entry_bytes/(sq_rdwidth/8),
        parameter sq_words_per_q = num_entries * sq_words_per_entry,
        parameter sq_num_words = sq_words_per_q,
        parameter sq_num_wren = sq_rdwidth / sq_wrwidth,
        parameter sq_addr_width = $clog2(sq_num_words),
        parameter sq_ptr_width = $clog2(num_entries),

        parameter ioaddr_base = 0

    )
   (
   
    input                                       reset,
    input                                       clk, 
   
    //-------------------------------------------------------
    // ucontrol IO bus
    //-------------------------------------------------------
    input                                [31:0] ctl_sq_ioaddress,
    input                                       ctl_sq_ioread_strobe, 
    input                                [35:0] ctl_sq_iowrite_data, // change 31 to 35 kch 
    input                                       ctl_sq_iowrite_strobe,
    output reg                           [35:0] sq_ctl_ioread_data, // read_data is sampled when ioack=1
    output reg                                  sq_ctl_ioack,

    input                   [sq_addr_width-1:0] sq_rdaddr,
    input                                       sq_rdval, 
    output reg [ sq_par_rdwidth+sq_rdwidth-1:0] sq_rddata,
    output reg                                  sq_rddata_val,

    output reg               [sq_ptr_width-1:0] sq_head, // read pointer
    output reg               [sq_ptr_width-1:0] sq_tail, // write pointer
    input                                       sq_head_update, // update when completion queue entry is processed
    input                    [sq_ptr_width-1:0] sq_head_new, // update when completion queue entry is processed

    input                                       q_reset,
    output reg                                  sq_reset,

    output reg                            [1:0] debug_cnt


    );

   
`include "nvme_func.svh"


   //-------------------------------------------------------
   // Admin Submission Queue (SQ)
   //-------------------------------------------------------

   // 64B per queue entry
   // 2 entries minimum per spec
   // 
   // read interface width: 16B - 4x16B per entry
   // write interface width: 4B - 16x4 per entry


   reg          [    sq_par_width+sq_width-1:0] sq_mem[sq_num_words-1:0];
   
   reg          [sq_par_wrwidth+sq_wrwidth-1:0] sq_wrdata;
   reg          [sq_par_wrwidth+sq_wrwidth-1:0] sq_wrdata_d,sq_wrdata_q;
   reg          [sq_par_rdwidth+sq_rdwidth-1:0] rmw_sq_wrdata;
   reg                      [  sq_num_wren-1:0] sq_wren;
   reg                      [  sq_num_wren-1:0] rmw_sq_wren_d,rmw_sq_wren_q;
   reg                                          rmw_sq_wren;
   reg                      [sq_addr_width-1:0] sq_wraddr;
   reg                      [sq_addr_width-1:0] rmw_sq_wraddr_d,rmw_sq_wraddr_q;
   reg                      [sq_addr_width-1:0] rmw_sq_rdaddr;
   reg                                          sq_rdval_q, sq_rdval_d;
   
   wire                                         sq_cnt_rddma;
   reg                                          sq_cnt_req;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             rmw_sq_wren_q   <= 1'b0;
             rmw_sq_wraddr_q <= 1'b0;
             sq_wrdata_q     <= zero[sq_par_wrwidth+sq_wrwidth-1:0];
             sq_rdval_q      <= 1'b0;
          end
        else
          begin
             rmw_sq_wren_q   <= rmw_sq_wren_d;
             rmw_sq_wraddr_q <= rmw_sq_wraddr_d;
             sq_wrdata_q     <= sq_wrdata_d;
             sq_rdval_q      <= sq_rdval_d;
          end
     end


   generate
      genvar i;
      for (i = 0; i < sq_num_wren; i = i+1) begin: dword_write
         always @*
           begin
              if (rmw_sq_wren_q[i])
                begin
                   // sq_mem[sq_wraddr][(i+1)*sq_wrwidth-1:i*sq_wrwidth] <= sq_wrdata[sq_wrwidth-1:0];
                   // sq_mem[sq_wraddr][(128+(i+1)*sq_par_wrwidth)-1:128+i*sq_par_wrwidth] <= sq_wrdata[sq_wrwidth+sq_par_wrwidth-1:sq_wrwidth];  // kch 
                   rmw_sq_wrdata[(i+1)*sq_wrwidth-1:i*sq_wrwidth] <= sq_wrdata_q[sq_wrwidth-1:0];
                   rmw_sq_wrdata[(128+(i+1)*sq_par_wrwidth)-1:128+i*sq_par_wrwidth] <= sq_wrdata_q[sq_wrwidth+sq_par_wrwidth-1:sq_wrwidth];  // kch 
                end 
              else 
                begin
                   rmw_sq_wrdata[(i+1)*sq_wrwidth-1:i*sq_wrwidth] <= sq_rddata[(i+1)*sq_wrwidth-1:i*sq_wrwidth];
                   rmw_sq_wrdata[(128+(i+1)*sq_par_wrwidth)-1:128+i*sq_par_wrwidth] <= sq_rddata[(128+(i+1)*sq_par_wrwidth)-1:128+i*sq_par_wrwidth];  // kch 
                end
           end
      end
   endgenerate

   // read modify write logic 
   always @*
     begin
        rmw_sq_rdaddr    = (sq_wren == 4'h0) ? sq_rdaddr : sq_wraddr;
        rmw_sq_wren_d    = sq_wren;
        rmw_sq_wren      = |(rmw_sq_wren_q);
        rmw_sq_wraddr_d  = sq_wraddr;
        sq_wrdata_d      = sq_wrdata;
        //             microcode only submits one command per sq so there won't be a collision
        //             (read/modify/write added for parity coverage)
        sq_rdval_d       = sq_rdval;
        sq_rddata_val    = sq_rdval_q;
     end
     
   always @(posedge clk)   
      sq_rddata <= sq_mem[rmw_sq_rdaddr];

   always @(posedge clk)
     if (rmw_sq_wren)
       sq_mem[rmw_sq_wraddr_q] <= rmw_sq_wrdata;      


   reg [sq_ptr_width-1:0] sq_head_q, sq_head_d; // read pointer
   reg [sq_ptr_width-1:0] sq_tail_q, sq_tail_d; // write pointer
   reg  [sq_addr_width:0] sq_init_q, sq_init_d;
   reg                     sq_rdvalid_q, sq_rdvalid_d;
   reg                     sq_full;   // NVMe spec says full when head=tail+1
   reg                     sq_empty;  // head=tail
   reg                     sq_tail_inc;    // incremented when microcontroller inserts entry
   
   reg                     sq_wrack;
   reg                     sq_rdack;
   
   // pgen sq data kch
   wire                    sq_cntl_par;
   nvme_pgen#
     (
      .bits_per_parity_bit(3),
      .width(3)
      ) ipgen_sq_cntl 
       (.oddpar(1'b1),.data({sq_init_q[sq_addr_width], sq_full, sq_empty}),.datap(sq_cntl_par)); 


   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             sq_head_q    <= zero[sq_ptr_width-1:0];
             sq_tail_q    <= zero[sq_ptr_width-1:0];
             sq_init_q    <= zero[sq_addr_width:0];
             sq_rdvalid_q <= 1'b0;
          end
        else
          begin
             sq_head_q    <= sq_head_d;
             sq_tail_q    <= sq_tail_d;
             sq_init_q    <= sq_init_d;
             sq_rdvalid_q <= sq_rdvalid_d;
          end
     end

   // manage head & tail pointers
   always @*
     begin
        
        sq_head_d = (sq_head_update) ? sq_head_new : sq_head_q;
        sq_tail_d = sq_tail_q + (sq_tail_inc ? one[sq_ptr_width-1:0] : zero[sq_ptr_width-1:0]);
        sq_full   = sq_head_q==(sq_tail_q+one[sq_ptr_width-1:0]);
        sq_empty  = sq_head_q==sq_tail_q;
        if( sq_reset | q_reset)
          begin
             sq_head_d = zero[sq_ptr_width-1:0];
             sq_tail_d = zero[sq_ptr_width-1:0];
          end
     end

   
   // ucontrol writes to SQ
   // ucontrol reads of SQ status
   always @*
     begin
        sq_reset    = 1'b0;
        sq_tail_inc = 1'b0;
        sq_wrack    = 1'b0;
        sq_cnt_req  = 1'b0;
        
        // 4B write to tail + offset from microcontroller
        sq_wrdata = ctl_sq_iowrite_data;
        sq_wren   = zero[sq_num_wren-1:0];
        sq_wraddr = { sq_tail_q, ctl_sq_ioaddress[5:4] };

        sq_init_d = sq_init_q;
        if( ~sq_init_q[sq_addr_width] )
          begin
             sq_init_d  = sq_init_q + one[sq_addr_width:0];
             sq_wren    = ~zero[sq_num_wren-1:0];
             sq_wraddr  = sq_init_q[sq_addr_width-1:0];
             sq_wrdata  = {~zero[sq_par_wrwidth+sq_wrwidth-1:sq_wrwidth],zero[sq_wrwidth-1:0]};
          end
        
        if( ctl_sq_iowrite_strobe && ctl_sq_ioaddress[11:7]=={ioaddr_base[3:0],1'b0} )
          begin
             sq_wrack = 1'b1;
             if (ctl_sq_ioaddress[7:6] == 2'b00)
               begin
                  // write to offset 0x00-0x3c - SQ_DW0-DW15
                  sq_wren[ctl_sq_ioaddress[3:2]] = 1'b1;
               end
             else if(ctl_sq_ioaddress[7:0] == 8'h40)
               begin
                  // write to offset 0x4x to increment tail pointer and trigger doorbell mmio
                  if( ~sq_full )
                    begin
                       sq_tail_inc  = 1'b1;
                       sq_cnt_req   = 1'b1;
                    end
               end 
             else if(ctl_sq_ioaddress[7:4] == 4'h6)
               begin
                  // write to offset 0x60,0x64,0x68,0x6c to initialize entry to all zeros
                  sq_wren    = ~zero[sq_num_wren-1:0];
                  sq_wrdata  = {~zero[sq_par_wrwidth+sq_wrwidth-1:sq_wrwidth],zero[sq_wrwidth-1:0]};
                  sq_wraddr  = { sq_tail_q, ctl_sq_ioaddress[3:2] };
               end
             else if(ctl_sq_ioaddress[7:0] == 8'h70)
               begin                  
                  // when the NVMe controller is reset, the SQ/ACQ pointers must be reset as well
                  // use write to offset 0x70 for queue reset
                  sq_reset = 1'b1;
               end

           
          end


        sq_ctl_ioread_data = {4'hF,zero[31:0]};
        sq_rdvalid_d = 1'b0;
        if( ctl_sq_ioread_strobe )
          begin
             if (ctl_sq_ioaddress[11:7] == {ioaddr_base[3:0],1'b0})
               begin
                  sq_rdvalid_d = 1'b1;
               end
          end     
        if( ctl_sq_ioaddress[7:4]==4'h5 )
          begin
             // offset 0x50 - SQ status
             sq_ctl_ioread_data = { 3'b1,sq_cntl_par,zero[31:3], sq_init_q[sq_addr_width], sq_full, sq_empty };
          end
        sq_rdack = sq_rdvalid_q;
     end // always @ *

   always @*
     begin
        sq_ctl_ioack  = sq_rdack | sq_wrack;
        sq_head       = sq_head_q;
        sq_tail       = sq_tail_q;
        debug_cnt[0]  = sq_cnt_req;
        debug_cnt[1]  = sq_head_update;
     end   


endmodule


