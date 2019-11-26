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
//  File : nvme_sntl_perf.v
//  *************************************************************************
//  *************************************************************************
//  Description : SurelockNVME - SCSI to NVMe Layer performance counters
//                
//  *************************************************************************

module nvme_sntl_perf#
  (
    parameter dbg_dma = 0
    )
   (
   
    input             reset,
    input             clk, 

    input      [31:0] cmd_perf_events,
    input      [15:0] dma_perf_events,
    input       [7:0] pcie_sntl_rxcq_perf_events,

    input             regs_sntl_perf_reset,
       
    input             regs_sntl_dbg_rd,
    input       [9:0] regs_sntl_dbg_addr,
    output reg [63:0] sntl_regs_dbg_data,
    output reg        sntl_regs_dbg_ack
 
    );


`include "nvme_func.svh"

   //------------------------------------------------
   // nvme_sntl_dma unit counters
   
   (* mark_debug = "false" *) 
   reg [15:0] dma_events_q;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin         
             dma_events_q  <= 16'h0;
          end
        else
          begin	          
             dma_events_q  <= dma_perf_events;
          end
     end

   localparam cnt_width=32;
   genvar i;
   generate
      for( i=0; i<16; i = i + 1 )
        begin : cnt
           reg [cnt_width-1:0] cnt_q;
           if( dbg_dma == 1'b1 )
             begin            
                always @(posedge clk or posedge reset)
                  begin
                     if( reset )
                       begin
                          cnt_q <= zero[cnt_width-1:0];                    
                       end
                     else
                       begin                    
                          cnt_q <= cnt_q + (dma_events_q[i] ? 1 : 0);
                       end
                  end
             end
           else
             begin
                always @(posedge clk)
                  cnt_q <= zero[cnt_width-1:0];
             end
        end
   endgenerate



   // latency measurement
   // s4_events_d[0] = 1'b1; // IDLE -> RDQ
   // s4_events_d[1] = 1'b1; // IDLE -> WRQ
   // s4_events_d[2] = 1'b1; // RD -> RDERR
   // s4_events_d[3] = 1'b1; // RDQ exit
   // s4_events_d[4] = 1'b1;  // RDQ -> RD 
   // s4_events_d[5] = 1'b1; // WRQ exit
   // s4_events_d[6] = 1'b1; // WRQ -> WRBUF
   // s4_events_d[7] = 1'b1;  // WRBUF exit
   // s4_events_d[8] = 1'b1; // WRBUF -> WR/WRSAME/WRVERIFY
   // s4_events_d[9] = 1'b1; // RD completion
   // s4_events_d[10] = 1'b1; // RD -> RD
   // s4_events_d[11] = 1'b1;  // WR/WRSAME/WRVERIFY exit
   // s4_events_d[12] = 1'b1; // WR -> WRBUF
   // s4_events_d[13] = 1'b1; // IDLE -> WRQ wrsame

   // rxcq_perf_events[0] = mwr_fifo_push
   // rxcq_perf_events[1] = mwr_fifo_pop
                                   

   // count # of ops in each state
   reg [9:0] perf_rdq_q, perf_rdq_d;
   reg [9:0] perf_rd_q, perf_rd_d;
   reg [9:0] perf_wrq_q, perf_wrq_d;
   reg [9:0] perf_wrbuf_q, perf_wrbuf_d;
   reg [9:0] perf_wr_q, perf_wr_d;
   reg [15:0] perf_mwr_q, perf_mwr_d;

   // sum of perf_xxx_q per cycle
   reg [63:0] perf_sum_rdq_q, perf_sum_rdq_d;
   reg [63:0] perf_sum_rd_q, perf_sum_rd_d;
   reg [63:0] perf_sum_wrq_q, perf_sum_wrq_d;
   reg [63:0] perf_sum_wrbuf_q, perf_sum_wrbuf_d;
   reg [63:0] perf_sum_wr_q, perf_sum_wr_d;
   reg [63:0] perf_sum_mwr_q, perf_sum_mwr_d;

   // count # of commands completed at each state
   reg [63:0] perf_cnt_rdq_q, perf_cnt_rdq_d;
   reg [63:0] perf_cnt_rd_q, perf_cnt_rd_d;
   reg [63:0] perf_cnt_wrq_q, perf_cnt_wrq_d;
   reg [63:0] perf_cnt_wrbuf_q, perf_cnt_wrbuf_d;
   reg [63:0] perf_cnt_wr_q, perf_cnt_wr_d;
   reg [63:0] perf_cnt_mwr_q, perf_cnt_mwr_d;

   reg [63:0] perf_cnt_cycles_q;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             perf_rdq_q   <= '0;
             perf_rd_q    <= '0;
             perf_wrq_q   <= '0;
             perf_wrbuf_q <= '0;
             perf_wr_q    <= '0;
             perf_mwr_q   <= '0;
          end
        else
          begin
             perf_rdq_q   <= perf_rdq_d;
             perf_rd_q    <= perf_rd_d;
             perf_wrq_q   <= perf_wrq_d;
             perf_wrbuf_q <= perf_wrbuf_d;
             perf_wr_q    <= perf_wr_d;
             perf_mwr_q   <= perf_mwr_d;
          end
     end

   reg [7:0] rxcq_perf_events_q;
   always @(posedge clk) rxcq_perf_events_q <= pcie_sntl_rxcq_perf_events;

   always @*
     begin
        perf_rdq_d   = perf_rdq_q;
        perf_rd_d    = perf_rd_q;
        perf_wrq_d   = perf_wrq_q;
        perf_wrbuf_d = perf_wrbuf_q;
        perf_wr_d    = perf_wr_q;
        perf_mwr_d   = perf_mwr_q;

        if( cmd_perf_events[0] ) perf_rdq_d = perf_rdq_d + 10'd1;
        if( cmd_perf_events[3] ) perf_rdq_d = perf_rdq_d - 10'd1;
        
        if( cmd_perf_events[4] | cmd_perf_events[10] ) perf_rd_d = perf_rd_d + 10'd1;
        if( cmd_perf_events[9] ) perf_rd_d = perf_rd_d - 10'd1;
        
        if( cmd_perf_events[1] | cmd_perf_events[13] ) perf_wrq_d = perf_wrq_d + 10'd1;
        if( cmd_perf_events[5] ) perf_wrq_d = perf_wrq_d - 10'd1;
        
        if( cmd_perf_events[6] | cmd_perf_events[12] ) perf_wrbuf_d = perf_wrbuf_d + 10'd1;
        if( cmd_perf_events[7] ) perf_wrbuf_d = perf_wrbuf_d - 10'd1;

        if( cmd_perf_events[8] | cmd_perf_events[14] ) perf_wr_d = perf_wr_d + 10'd1;
        if( cmd_perf_events[11] ) perf_wr_d = perf_wr_d - 10'd1;
        
        if( rxcq_perf_events_q[0]  ) perf_mwr_d = perf_mwr_d + 16'd1;
        if( rxcq_perf_events_q[1] ) perf_mwr_d = perf_mwr_d - 16'd1;

     end
        
     always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             perf_cnt_rdq_q   <= '0;
             perf_cnt_rd_q    <= '0;
             perf_cnt_wrq_q   <= '0;
             perf_cnt_wrbuf_q <= '0;
             perf_cnt_wr_q    <= '0;
             perf_cnt_mwr_q   <= '0;
             perf_cnt_cycles_q <= '0;
          end
        else
          begin
             perf_cnt_rdq_q   <= perf_cnt_rdq_d;
             perf_cnt_rd_q    <= perf_cnt_rd_d;
             perf_cnt_wrq_q   <= perf_cnt_wrq_d;
             perf_cnt_wrbuf_q <= perf_cnt_wrbuf_d;
             perf_cnt_wr_q    <= perf_cnt_wr_d;
             perf_cnt_mwr_q   <= perf_cnt_mwr_d;
             perf_cnt_cycles_q <= perf_cnt_cycles_q + 64'h1;
          end
     end

   always @*
     begin
        perf_cnt_rdq_d   = perf_cnt_rdq_q;
        perf_cnt_rd_d    = perf_cnt_rd_q;
        perf_cnt_wrq_d   = perf_cnt_wrq_q;
        perf_cnt_wrbuf_d = perf_cnt_wrbuf_q;
        perf_cnt_wr_d    = perf_cnt_wr_q;
        perf_cnt_mwr_d   = perf_cnt_mwr_q;

        if( cmd_perf_events[0] ) perf_cnt_rdq_d = perf_cnt_rdq_d + 10'd1;
        if( cmd_perf_events[4] | cmd_perf_events[10] ) perf_cnt_rd_d = perf_cnt_rd_d + 10'd1;
        if( cmd_perf_events[1] ) perf_cnt_wrq_d = perf_cnt_wrq_d + 10'd1;
        if( cmd_perf_events[6] | cmd_perf_events[12] ) perf_cnt_wrbuf_d = perf_cnt_wrbuf_d + 10'd1;
        if( cmd_perf_events[8] ) perf_cnt_wr_d = perf_cnt_wr_d + 10'd1;
        if( rxcq_perf_events_q[1] ) perf_cnt_mwr_d = perf_cnt_mwr_d + 10'd1;

        // functional reset of counters
        if( regs_sntl_perf_reset )
          begin
             perf_cnt_rdq_d   = '0;
             perf_cnt_rd_d    = '0;
             perf_cnt_wrq_d   = '0;
             perf_cnt_wrbuf_d = '0;
             perf_cnt_wr_d    = '0;
             perf_cnt_mwr_d   = '0;
          end
     end
              
        
     always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             perf_sum_rdq_q   <= '0;
             perf_sum_rd_q    <= '0;
             perf_sum_wrq_q   <= '0;
             perf_sum_wrbuf_q <= '0;
             perf_sum_wr_q    <= '0;
             perf_sum_mwr_q    <= '0;
          end
        else
          begin
             perf_sum_rdq_q   <= perf_sum_rdq_d;
             perf_sum_rd_q    <= perf_sum_rd_d;
             perf_sum_wrq_q   <= perf_sum_wrq_d;
             perf_sum_wrbuf_q <= perf_sum_wrbuf_d;
             perf_sum_wr_q    <= perf_sum_wr_d;
             perf_sum_mwr_q   <= perf_sum_mwr_d;
          end
     end

   always @*
     begin
        perf_sum_rdq_d   = perf_sum_rdq_q + perf_rdq_q;
        perf_sum_rd_d    = perf_sum_rd_q + perf_rd_q;
        perf_sum_wrq_d   = perf_sum_wrq_q + perf_wrq_q;
        perf_sum_wrbuf_d = perf_sum_wrbuf_q + perf_wrbuf_q;
        perf_sum_wr_d    = perf_sum_wr_q + perf_wr_q;
        perf_sum_mwr_d    = perf_sum_mwr_q + perf_mwr_q;

        // functional reset of counters
        if( regs_sntl_perf_reset )
          begin
             perf_sum_rdq_d   = '0;
             perf_sum_rd_d    = '0;
             perf_sum_wrq_d   = '0;
             perf_sum_wrbuf_d = '0;
             perf_sum_wr_d    = '0;
             perf_sum_mwr_d   = '0;
          end
     end              

   
   //-------------------------------------------------------
   // debug register read
   //-------------------------------------------------------
   
   
   reg [63:0] dbg_data_q, dbg_data_d;
   always @(posedge clk)
     begin
        dbg_data_q <= dbg_data_d;    
     end

   reg dbg_rdack_q, dbg_rdack_d;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             dbg_rdack_q      <= 1'b0;            
          end
        else
          begin
             dbg_rdack_q      <= dbg_rdack_d;           
          end
     end

   always @*
     begin       
        dbg_data_d = zero[63:0];

        if( regs_sntl_dbg_addr<64 )
          begin
             dbg_rdack_d = regs_sntl_dbg_rd & ~dbg_rdack_q;
             case(regs_sntl_dbg_addr[5:0])
               0: dbg_data_d[cnt_width-1:0] = cnt[0].cnt_q;
               1: dbg_data_d[cnt_width-1:0] = cnt[1].cnt_q;
               2: dbg_data_d[cnt_width-1:0] = cnt[2].cnt_q;
               3: dbg_data_d[cnt_width-1:0] = cnt[3].cnt_q;
               4: dbg_data_d[cnt_width-1:0] = cnt[4].cnt_q;
               5: dbg_data_d[cnt_width-1:0] = cnt[5].cnt_q;
               6: dbg_data_d[cnt_width-1:0] = cnt[6].cnt_q;
               7: dbg_data_d[cnt_width-1:0] = cnt[7].cnt_q;
               8: dbg_data_d[cnt_width-1:0] = cnt[8].cnt_q;
               9: dbg_data_d[cnt_width-1:0] = cnt[9].cnt_q;
               10: dbg_data_d[cnt_width-1:0] = cnt[10].cnt_q;
               11: dbg_data_d[cnt_width-1:0] = cnt[11].cnt_q;
               12: dbg_data_d[cnt_width-1:0] = cnt[12].cnt_q;
               13: dbg_data_d[cnt_width-1:0] = cnt[13].cnt_q;
               14: dbg_data_d[cnt_width-1:0] = cnt[14].cnt_q;
               15: dbg_data_d[cnt_width-1:0] = cnt[15].cnt_q;

               16: dbg_data_d[9:0] = perf_rdq_q;
               17: dbg_data_d[9:0] = perf_rd_q;
               18: dbg_data_d[9:0] = perf_wrq_q;
               19: dbg_data_d[9:0] = perf_wrbuf_q;
               20: dbg_data_d[9:0] = perf_wr_q;

               21: dbg_data_d = perf_cnt_rdq_q;
               22: dbg_data_d = perf_cnt_rd_q;
               23: dbg_data_d = perf_cnt_wrq_q;
               24: dbg_data_d = perf_cnt_wrbuf_q;
               25: dbg_data_d = perf_cnt_wr_q;

               26: dbg_data_d = perf_sum_rdq_q;
               27: dbg_data_d = perf_sum_rd_q;
               28: dbg_data_d = perf_sum_wrq_q;
               29: dbg_data_d = perf_sum_wrbuf_q;
               30: dbg_data_d = perf_sum_wr_q;
               31: dbg_data_d = perf_cnt_cycles_q;


               32: dbg_data_d = perf_mwr_q;
               33: dbg_data_d = perf_cnt_mwr_q;
               34: dbg_data_d = perf_sum_mwr_q;
               
               default: dbg_data_d = zero[63:0];
             endcase // case (regs_sntl_dbg_addr)
          end      
        else
          begin
             dbg_rdack_d = regs_sntl_dbg_rd & ~dbg_rdack_q;
          end
        
        sntl_regs_dbg_ack = dbg_rdack_q;
        sntl_regs_dbg_data = dbg_data_q;
     end

   
endmodule


