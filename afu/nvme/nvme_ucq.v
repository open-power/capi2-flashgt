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
//  File : nvme_ucq.v
//  *************************************************************************
//  *************************************************************************
//  Description : FlashGT+ NVMe submission/completion queues with
//                microcode interface
//
//  Implements Admin Submission Queue (ASQ) and Admin Completion Queue (ACQ)
//  Implements one I/O Submission Queue and I/O Completeion Queue for use
//  by ucode.
//
//    SQ entries are inserted by microcontroller interface. When inserted,
//    a mmio write to the SQ tail doorbell is generated.  The NVMe controller
//    then generates DMA reads for the SQ entry.  SQ entries are 64B.
//    
//    CQ entries are inserted by the NVMe controller using DMA writes.  The 
//    completion queue entry includes the new SQ head pointer, a phase bit
//    to help track when an entry is inserted, and a status. CQ entries are 16B.
//
//    Interfaces to/from the NVMe controller are 128b.  Interfaces to/from the
//    microcontroller are 32b.
//  *************************************************************************

module nvme_ucq#
  (     
    parameter num_entries = 4,
    parameter data_width = 128,
    parameter addr_width = 48
    )
   (
   
    input             reset,
    input             clk, 
   
    //-------------------------------------------------------
    // ucontrol IO bus
    //-------------------------------------------------------
    input      [31:0] ctl_adq_ioaddress,
    input             ctl_adq_ioread_strobe, 
    input      [35:0] ctl_adq_iowrite_data,
    input             ctl_adq_iowrite_strobe,
    output reg [35:0] adq_ctl_ioread_data, // read_data is sampled when ioack=1
    output reg        adq_ctl_ioack,

    //-------------------------------------------------------
    // Admin Q doorbell write
    //-------------------------------------------------------
    output            adq_pcie_wrvalid,
    output     [31:0] adq_pcie_wraddr,
    output     [15:0] adq_pcie_wrdata,
    input             pcie_adq_wrack,
     
    //-------------------------------------------------------
    // DMA requests to Admin Q
    //-------------------------------------------------------
  
    input             pcie_adq_valid,
    input     [144:0] pcie_adq_data,
    input             pcie_adq_first, 
    input             pcie_adq_last, 
    input             pcie_adq_discard, 
    output            adq_pcie_pause,

    //-------------------------------------------------------
    // DMA response from Admin Q
    //-------------------------------------------------------        
 
    output    [144:0] adq_pcie_cc_data,
    output            adq_pcie_cc_first,
    output            adq_pcie_cc_last,
    output            adq_pcie_cc_discard,
    output            adq_pcie_cc_valid,
    input             pcie_adq_cc_ready,
    
    //-------------------------------------------------------
    // status to microcontroller
    //-------------------------------------------------------        
    output      [1:0] adq_ctl_cpl_empty, // completion queue is empty

    //-------------------------------------------------------
    // debug
    //-------------------------------------------------------
  
    input             regs_adq_dbg_rd,
    input       [9:0] regs_adq_dbg_addr, // 8B offset
    output reg [63:0] adq_regs_dbg_data,
    output reg        adq_regs_dbg_ack,
    output            adq_perror_ind,
    // ----------------------------------------------------------
    // parity error inject 
    // ----------------------------------------------------------
    input             regs_adq_pe_errinj_valid,
    input      [15:0] regs_xxx_pe_errinj_decode, 
    input             regs_wdata_pe_errinj_1cycle_valid 
        
    );

   
`include "nvme_func.svh"

   // first instance is the Admin Submission Queue  (SQ0)
   // second instance is the Admin Completion Queue (CQ0)
   // third instance is I/O Submission Queue        (SQ1)
   // fourth instnace is I/O Completion Queue       (CQ1)
   //
   // SQ0 & SQ1 have the same sizes
   // CQ0 & CQ1 have the same sizes
   localparam sq_width = 128;
   localparam sq_par_width = sq_width/8;
   localparam sq_entry_bytes = 64;
   localparam sq_rdwidth = 128;
   localparam sq_par_rdwidth = sq_rdwidth/8;
   localparam sq_wrwidth = 32;
   localparam sq_par_wrwidth = sq_wrwidth/8;
   localparam sq_words_per_entry = sq_entry_bytes/(sq_rdwidth/8);
   localparam sq_words_per_q = num_entries * sq_words_per_entry;
   localparam sq_num_words = sq_words_per_q;
   localparam sq_num_wren = sq_rdwidth / sq_wrwidth;
   localparam sq_addr_width = $clog2(sq_num_words);
   localparam sq_ptr_width = $clog2(num_entries);

   localparam cq_ptr_width = $clog2(num_entries);
   localparam cq_width = 128;
   localparam cq_par_width = cq_width/8;
   localparam cq_rdwidth = 32;
   localparam cq_par_rdwidth = cq_rdwidth/8;
   localparam cq_wrwidth = 128;
   localparam cq_par_wrwidth = cq_wrwidth/8;
   localparam cq_num_words = num_entries * (16/(cq_wrwidth/8));
   localparam cq_num_wren = 1;
   localparam cq_addr_width = $clog2(cq_num_words);

   wire                          q0_reset;
   wire       [cq_ptr_width-1:0] cq0_head;            
   wire       [cq_ptr_width-1:0] cq0_tail;            
   wire       [sq_ptr_width-1:0] sq0_head;            
   wire       [sq_ptr_width-1:0] sq0_head_new;       
   wire                          sq0_head_update;      
   wire       [sq_ptr_width-1:0] sq0_tail;           
   
   wire                          cq0_ctl_ioack;        
   wire                   [35:0] cq0_ctl_ioread_data;   
   wire                          sq0_ctl_ioack;         
   wire                   [35:0] sq0_ctl_ioread_data;   
   
   wire      [sq_addr_width-1:0] sq_rdaddr;
   wire                          sq0_rdval;
   wire                    [1:0] sq0_debug_cnt;
 
   wire [ sq_par_rdwidth+sq_rdwidth-1:0] sq0_rddata;
   wire                                  sq0_rddata_val;
   wire [ sq_par_rdwidth+sq_rdwidth-1:0] sq_rddata;
   
   nvme_ucq_sq#
     (.num_entries(num_entries),
      .sq_width(sq_width),
      .sq_rdwidth(sq_rdwidth),
      .sq_wrwidth(sq_wrwidth),
      .ioaddr_base(0)
      ) asq0
     (
      // Outputs
      .sq_reset                       (q0_reset),
      .sq_ctl_ioread_data             (sq0_ctl_ioread_data[35:0]),
      .sq_ctl_ioack                   (sq0_ctl_ioack),
      .sq_head                        (sq0_head[sq_ptr_width-1:0]),
      .sq_tail                        (sq0_tail[sq_ptr_width-1:0]),
      .sq_rddata                      (sq0_rddata),
      .sq_rddata_val                  (sq0_rddata_val),
      .debug_cnt                      (sq0_debug_cnt),
      // Inputs
      .reset                          (reset),
      .clk                            (clk),
      .ctl_sq_ioaddress               (ctl_adq_ioaddress[31:0]),
      .ctl_sq_ioread_strobe           (ctl_adq_ioread_strobe),
      .ctl_sq_iowrite_data            (ctl_adq_iowrite_data[35:0]),
      .ctl_sq_iowrite_strobe          (ctl_adq_iowrite_strobe),

      .q_reset                        (1'b0),
      .sq_head_update                 (sq0_head_update),
      .sq_head_new                    (sq0_head_new),
      .sq_rdaddr                      (sq_rdaddr[sq_addr_width-1:0]),
      .sq_rdval                       (sq0_rdval)
      );
   

   
   wire                                  cq0_wren;
   wire              [cq_addr_width-1:0] cq_wraddr;
   wire [ cq_par_wrwidth+cq_wrwidth-1:0] cq_wrdata;
   wire                                  cq0_phase;
   
   nvme_ucq_cq#
     (.num_entries(num_entries),
      .cq_width(cq_width),
      .cq_rdwidth(cq_rdwidth),
      .cq_wrwidth(cq_wrwidth),
      .ioaddr_base(0)
      ) acq0
     (
      // Outputs
      .cq_ctl_ioread_data             (cq0_ctl_ioread_data[35:0]),
      .cq_ctl_ioack                   (cq0_ctl_ioack),
      .cq_head                        (cq0_head[cq_ptr_width-1:0]),
      .cq_tail                        (cq0_tail[cq_ptr_width-1:0]),
      .sq_head                        (sq0_head_new[sq_ptr_width-1:0]),
      .sq_head_update                 (sq0_head_update),
      .cq_empty                       (adq_ctl_cpl_empty[0]),
      .cq_phase                       (cq0_phase),
      // Inputs
      .reset                          (reset),
      .clk                            (clk),
      .ctl_cq_ioaddress               (ctl_adq_ioaddress[31:0]),
      .ctl_cq_ioread_strobe           (ctl_adq_ioread_strobe),
      .ctl_cq_iowrite_data            (ctl_adq_iowrite_data[35:0]),
      .ctl_cq_iowrite_strobe          (ctl_adq_iowrite_strobe),
      
      .cq_reset                       (q0_reset),
      .cq_wren                        (cq0_wren),
      .cq_wraddr                      (cq_wraddr[cq_addr_width-1:0]),
      .cq_wrdata                      (cq_wrdata[cq_par_wrwidth+cq_wrwidth-1:0])      
      );
   
   wire       [cq_ptr_width-1:0] cq1_head;            
   wire       [cq_ptr_width-1:0] cq1_tail;           
   wire       [sq_ptr_width-1:0] sq1_head;            
   wire       [sq_ptr_width-1:0] sq1_head_new;       
   wire                          sq1_head_update;     
   wire       [sq_ptr_width-1:0] sq1_tail;         
   wire                          sq1_rdval;
   
   wire                          cq1_ctl_ioack;          
   wire                   [35:0] cq1_ctl_ioread_data;    
   wire                          sq1_ctl_ioack;         
   wire                   [35:0] sq1_ctl_ioread_data;    
   
   wire                    [1:0] sq1_debug_cnt;
 
   wire [ sq_par_rdwidth+sq_rdwidth-1:0] sq1_rddata;
   wire                                  sq1_rddata_val;
   
   
   nvme_ucq_sq#
     (.num_entries(num_entries),
      .sq_width(sq_width),
      .sq_rdwidth(sq_rdwidth),
      .sq_wrwidth(sq_wrwidth),
      .ioaddr_base(1)
      ) sq1
     (
      // Outputs
      .sq_reset                       (),
      .sq_ctl_ioread_data             (sq1_ctl_ioread_data[35:0]),
      .sq_ctl_ioack                   (sq1_ctl_ioack),
      .sq_head                        (sq1_head[sq_ptr_width-1:0]),
      .sq_tail                        (sq1_tail[sq_ptr_width-1:0]),
      .sq_rddata                      (sq1_rddata),
      .sq_rddata_val                  (sq1_rddata_val),
      .debug_cnt                      (sq1_debug_cnt),
      // Inputs
      .reset                          (reset),
      .clk                            (clk),
      .ctl_sq_ioaddress               (ctl_adq_ioaddress[31:0]),
      .ctl_sq_ioread_strobe           (ctl_adq_ioread_strobe),
      .ctl_sq_iowrite_data            (ctl_adq_iowrite_data[35:0]),
      .ctl_sq_iowrite_strobe          (ctl_adq_iowrite_strobe),

      .q_reset                        (q0_reset),
      .sq_head_update                 (sq1_head_update),
      .sq_head_new                    (sq1_head_new),
      .sq_rdaddr                      (sq_rdaddr[sq_addr_width-1:0]),
      .sq_rdval                       (sq1_rdval)
      );
   
   
   wire                                  cq1_wren;
   wire                                  cq1_phase;
   
   nvme_ucq_cq#
     (.num_entries(num_entries),
      .cq_width(cq_width),
      .cq_rdwidth(cq_rdwidth),
      .cq_wrwidth(cq_wrwidth),
      .ioaddr_base(1)
      ) cq1
     (
      // Outputs
      .cq_ctl_ioread_data             (cq1_ctl_ioread_data[35:0]),
      .cq_ctl_ioack                   (cq1_ctl_ioack),
      .cq_head                        (cq1_head[cq_ptr_width-1:0]),
      .cq_tail                        (cq1_tail[cq_ptr_width-1:0]),
      .sq_head                        (sq1_head_new[sq_ptr_width-1:0]),
      .sq_head_update                 (sq1_head_update),
      .cq_empty                       (adq_ctl_cpl_empty[1]),
      .cq_phase                       (cq1_phase),
      // Inputs
      .reset                          (reset),
      .clk                            (clk),
      .ctl_cq_ioaddress               (ctl_adq_ioaddress[31:0]),
      .ctl_cq_ioread_strobe           (ctl_adq_ioread_strobe),
      .ctl_cq_iowrite_data            (ctl_adq_iowrite_data[35:0]),
      .ctl_cq_iowrite_strobe          (ctl_adq_iowrite_strobe),
      
      .cq_reset                       (q0_reset),
      .cq_wren                        (cq1_wren),
      .cq_wraddr                      (cq_wraddr[cq_addr_width-1:0]),
      .cq_wrdata                      (cq_wrdata[cq_par_wrwidth+cq_wrwidth-1:0])      
      );
   

   
   
   //-------------------------------------------------------
   // microcontroller interface response
   //-------------------------------------------------------

   always @(posedge clk)
     begin
        adq_ctl_ioack <= cq0_ctl_ioack | sq0_ctl_ioack | cq1_ctl_ioack | sq1_ctl_ioack;       
        adq_ctl_ioread_data <= sq0_ctl_ioack ? sq0_ctl_ioread_data : 
                               cq0_ctl_ioack ? cq0_ctl_ioread_data :
                               sq1_ctl_ioack ? sq0_ctl_ioread_data :
                               cq0_ctl_ioread_data;                               
     end


   //-------------------------------------------------------
   // DMA access to ASQ/ACQ from NVMe controller
   //-------------------------------------------------------

   // parity error injection
   reg               [1:0] cq_pe_inj_d,cq_pe_inj_q;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin           
             cq_pe_inj_q <= 1'b0;
          end
        else
          begin
             cq_pe_inj_q <= cq_pe_inj_d;
          end
     end
   wire [1:0] xxq_perror_ack;
   always @*
     begin       
        cq_pe_inj_d = cq_pe_inj_q;
        if (regs_wdata_pe_errinj_1cycle_valid & regs_adq_pe_errinj_valid & regs_xxx_pe_errinj_decode[11:8] == 4'hA)   
          begin
             cq_pe_inj_d[0]  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
             cq_pe_inj_d[1]  = (regs_xxx_pe_errinj_decode[3:0]==4'h1);
          end 
        if (cq_pe_inj_q[0] & xxq_perror_ack[0])
          cq_pe_inj_d[0] = 1'b0;         
        if (cq_pe_inj_q[1] & xxq_perror_ack[1])
          cq_pe_inj_d[1] = 1'b0;         
     end  
   
   wire [1:0] xxq_perror_inj = cq_pe_inj_q;

   
   wire [3:0] doorbell_stride = 4'd0; // 4 bytes between doorbell addresses
   (* mark_debug = "false" *)
   wire [7:0] req_dbg_event;
   wire       adq_init_done;

   assign sq_rddata = (sq0_rddata_val) ? sq0_rddata : sq1_rddata;

   wire       cq_wrid, sq_rdid, cq_wren, sq_rdval;

   assign cq0_wren = cq_wren & ~cq_wrid;
   assign cq1_wren = cq_wren & cq_wrid;
   assign sq0_rdval = sq_rdval & ~sq_rdid;
   assign sq1_rdval = sq_rdval & sq_rdid;
   
   
   nvme_xxq_dma#
     (.addr_width(addr_width),
   
      .sq_num_queues(2),
      .sq_ptr_width(sq_ptr_width),
      .sq_addr_width(sq_addr_width),
      .sq_rdwidth(sq_rdwidth),
       
      .cq_num_queues(2),
      .cq_ptr_width(cq_ptr_width),
      .cq_addr_width(cq_addr_width),
      .cq_wrwidth(cq_wrwidth)
        
      ) dma
       (  
          .reset                         (reset),
          .clk                           (clk),
                
          .q_reset                       (q0_reset),
          .q_init_done                   (adq_init_done),


          .cq_wren                       (cq_wren),
          .cq_wraddr                     (cq_wraddr),
          .cq_id                         (cq_wrid),
          .cq_wrdata                     (cq_wrdata),

          .sq_rdaddr                     (sq_rdaddr),
          .sq_rdval                      (sq_rdval),
          .sq_id                         (sq_rdid),
          .sq_rddata                     (sq_rddata),

          .pcie_xxq_valid                (pcie_adq_valid),
          .pcie_xxq_data                 (pcie_adq_data),
          .pcie_xxq_first                (pcie_adq_first),
          .pcie_xxq_last                 (pcie_adq_last),
          .pcie_xxq_discard              (pcie_adq_discard),        
          .xxq_pcie_pause                (adq_pcie_pause),
          
          .xxq_pcie_cc_data              (adq_pcie_cc_data),
          .xxq_pcie_cc_first             (adq_pcie_cc_first),
          .xxq_pcie_cc_last              (adq_pcie_cc_last),
          .xxq_pcie_cc_discard           (adq_pcie_cc_discard),
          .xxq_pcie_cc_valid             (adq_pcie_cc_valid),   
          .pcie_xxq_cc_ready             (pcie_adq_cc_ready),
          
          .req_dbg_event                 (req_dbg_event),
          .xxq_dma_perror                (adq_perror_ind),
          .xxq_perror_inj                (xxq_perror_inj),
          .xxq_perror_ack                (xxq_perror_ack));



   nvme_xxq_doorbell#
     (
      .sq_num_queues(2),
      .sq_ptr_width(sq_ptr_width),
          
      .cq_num_queues(2),
      .cq_ptr_width(cq_ptr_width)

      ) doorbell
       (  
          .reset                         (reset),
          .clk                           (clk),
                
          .sq_tail                       ({sq1_tail,sq0_tail}),
          .cq_head                       ({cq1_head,cq0_head}),
          .cq_tail                       ({cq1_tail,cq0_tail}),

          .q_reset                       (q0_reset),
          .doorbell_start_addr           (NVME_REG_SQ0TDBL),
          .doorbell_stride               (doorbell_stride),
          

          .xxq_pcie_wrvalid              (adq_pcie_wrvalid),
          .xxq_pcie_wraddr               (adq_pcie_wraddr),
          .xxq_pcie_wrdata               (adq_pcie_wrdata),
          .pcie_xxq_wrack                (pcie_adq_wrack)
          );
 
   //-------------------------------------------------------
   // debug/performance counters
   //-------------------------------------------------------

   reg [31:0] cnt_acq_dmawr_q, cnt_acq_dmawr_d;
   reg [31:0] cnt_asq_cmd_q, cnt_asq_cmd_d;
   reg [31:0] cnt_asq_cpl_q, cnt_asq_cpl_d;
   reg [31:0] cnt_asq_dmard_q, cnt_asq_dmard_d;
    
   reg [63:0] dbg_data_q, dbg_data_d;
   always @(posedge clk)
     begin
        dbg_data_q <= dbg_data_d;
     end

   reg dbg_rdack_q, dbg_rdack_d;
   reg [4:0] cnt_incr_q, cnt_incr_d;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             dbg_rdack_q     <= 1'b0;
             cnt_acq_dmawr_q <= 32'h0;
             cnt_asq_cmd_q   <= 32'h0;
             cnt_asq_cpl_q   <= 32'h0;
             cnt_asq_dmard_q <= 32'h0;             
             cnt_incr_q      <= 5'h0;
          end
        else
          begin
             dbg_rdack_q     <= dbg_rdack_d;
             cnt_acq_dmawr_q <= cnt_acq_dmawr_d;
             cnt_asq_cmd_q   <= cnt_asq_cmd_d;
             cnt_asq_cpl_q   <= cnt_asq_cpl_d;
             cnt_asq_dmard_q <= cnt_asq_dmard_d;
             cnt_incr_q      <= cnt_incr_d;
          end
     end

   always @*
     begin
        cnt_incr_d[0]    = cq0_wren & adq_init_done;
        cnt_incr_d[4:1]  = {sq1_debug_cnt,sq0_debug_cnt};        
        cnt_acq_dmawr_d  = cnt_acq_dmawr_q  + ((cnt_incr_q[0]) ? 1: 0);
        cnt_asq_cmd_d    = cnt_asq_cmd_q + ((cnt_incr_q[1]) ? 1: 0);
        cnt_asq_cpl_d    = cnt_asq_cpl_q   + ((cnt_incr_q[2]) ? 1: 0);
        cnt_asq_dmard_d  = cnt_asq_dmard_q + ((cnt_incr_q[3]) ? 1: 0);     
     end

   always @*
     begin
        dbg_rdack_d = 1'b0;

        if( regs_adq_dbg_addr<24 )
          begin
             dbg_rdack_d = regs_adq_dbg_rd & ~dbg_rdack_q;
             case(regs_adq_dbg_addr)
               0: dbg_data_d = {cq0_phase, zero[30:cq_ptr_width], cq0_head, zero[31:cq_ptr_width],cq0_tail};
               1: dbg_data_d = {zero[63:32], cnt_acq_dmawr_q};
               2: dbg_data_d = {zero[31:sq_ptr_width], sq0_head, zero[31:sq_ptr_width],sq0_tail};
               3: dbg_data_d = {zero[63:32] ,cnt_asq_cmd_q};             
               4: dbg_data_d = {zero[63:32] ,cnt_asq_cpl_q};
               5: dbg_data_d = {zero[63:32] ,cnt_asq_dmard_q};
               default: dbg_data_d = zero[63:0];
             endcase // case (regs_adq_dbg_addr)             
          end
        else
          begin
             dbg_data_d = zero[63:0];
             dbg_rdack_d = regs_adq_dbg_rd & ~dbg_rdack_q;
          end                                     
         
        adq_regs_dbg_ack = dbg_rdack_q;
        adq_regs_dbg_data = dbg_data_q;
     end   
   
   
endmodule


