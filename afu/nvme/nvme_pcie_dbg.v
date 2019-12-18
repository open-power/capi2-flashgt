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

// FlashGT+
// PCIe debug
//
// - includes async crossing between PSL 250Mhz clock and
//   NVMe port's 250Mhz clock
//

module nvme_pcie_dbg
  #(
    parameter clk_period = 4000  // PSL clock period in ps
    )
   (
    input             clk,
    input             reset,

    output reg [31:0] pcie_regs_status,
    (* mark_debug = "true" *)
    input       [7:0] regs_pcie_debug, // control misc hip signals
    input      [31:0] regs_pcie_debug_trace,

    (* mark_debug = "true" *)
    input             regs_pcie_perst, // assert perst from mmio reg (1 cycle pulse)
    (* mark_debug = "true" *)
    input             ctlff_dbg_perst, // assert perst from ucode (1 cycle pulse)

    //-------------------------------------------------------
    // PCIe sideband signals
    //-------------------------------------------------------
    output            pci_exp_nperst,
    output            sys_reset_n,
   
    //-------------------------------------------------------
    //  NVMe port clock domain
    //-------------------------------------------------------    
    input             user_clk,
    input             user_reset,
    input             user_lnk_up,
 
    //-------------------------------------------------------
    // Configuration/Status interfaces
    //-------------------------------------------------------
    input             cfg_phy_link_down,
    input       [1:0] cfg_phy_link_status,
    input       [2:0] cfg_negotiated_width,
    input       [1:0] cfg_current_speed, 
    input       [5:0] cfg_ltssm_state,
    input             cfg_err_fatal_out,
    output            cfg_hot_reset, 
    output            cfg_link_training_enable,

    //-------------------------------------------------------
    // Management Interface
    //-------------------------------------------------------
    output      [9:0] cfg_mgmt_addr,
    output            cfg_mgmt_write,
    output     [31:0] cfg_mgmt_write_data,
    output      [3:0] cfg_mgmt_byte_enable,
    output            cfg_mgmt_read,
    input      [31:0] cfg_mgmt_read_data,
    input             cfg_mgmt_read_write_done,

   //-----------------------------------------------------------
   // parity error
   //----------------------------------------------------------
   // control signals 
    input             regs_wdata_pe_errinj_valid,
    output reg        user_regs_wdata_pe_errinj_valid, // 1 cycle pulse in nvme domain
  
    input       [1:0] user_rxcq_perror_ind,
    input             user_rxrc_perror_ind,
    input       [1:0] user_txcc_perror_ind,
    input             user_txrq_perror_ind,
    input             user_ctlff_perror_ind,
   
    // pcie perror in afu clock domain 
    output reg  [1:0] cdc_rxcq_perror_ind,
    output reg        cdc_rxrc_perror_ind,
    output reg  [1:0] cdc_txcc_perror_ind,
    output reg        cdc_txrq_perror_ind,
    output reg        cdc_ctlff_perror_ind,
    output reg        cdc_hold_cfg_err_fatal_out,

    //-------------------------------------------------------
    // debug
    //-------------------------------------------------------
    input             regs_pcie_dbg_rd,
    input      [15:0] regs_pcie_dbg_addr,
    output reg [63:0] pcie_regs_dbg_data,
    output reg        pcie_regs_dbg_ack,

    input      [15:0] rxcq_dbg_events,
    input      [15:0] rxcq_dbg_user_events,
    input     [143:0] rxcq_dbg_user_tracedata,
    input             rxcq_dbg_user_tracevalid,

    input      [15:0] txcc_dbg_events,
    input      [15:0] txcc_dbg_user_events,

//    input      [2:0]  rxcq_dbg_perr  
    input     [143:0] txcc_dbg_user_tracedata,
    input             txcc_dbg_user_tracevalid,

    input      [63:0] ctlff_dbg_user_trace,

    output      [1:0] pcie_regs_dbg_error,

    input     [143:0] rxrc_dbg_user_tracedata,
    input             rxrc_dbg_user_tracevalid,
    input     [143:0] txrq_dbg_user_tracedata,
    input             txrq_dbg_user_tracevalid
       
);

`include "nvme_func.svh"

 

   //-------------------------------------------------------
   // PSL clock domain logic
   //-------------------------------------------------------

   // assert perst for > Tperst = 100us

   localparam Tperst           = 150000000 / clk_period; // clk_period is in ps
`ifdef SIM
   localparam perst_cycles = 100;
   localparam Tsys_reset_start = 90;
   localparam Tsys_reset_end   = 80;
`else   
   localparam perst_cycles = Tperst;
   localparam Tsys_reset_start = 100000000 / clk_period;
   localparam Tsys_reset_end   =  90000000 / clk_period;
`endif
   localparam perst_cnt_width = $clog2(Tperst);

   (* mark_debug = "true" *)
   reg [perst_cnt_width-1:0] perst_cnt_q;
   (* mark_debug = "true" *)
   reg                       nperst1, nperst2;
   (* mark_debug = "true" *)
   reg                       sys_reset_n_q;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             perst_cnt_q <= perst_cycles[perst_cnt_width-1:0];
             nperst1 <= 1'b0;  // assert perst at reset
             nperst2 <= 1'b0;
             sys_reset_n_q <= 1'b0;
          end
        else
          begin
             if( nperst1 & (regs_pcie_perst | ctlff_dbg_perst) )
               begin
                  perst_cnt_q <= perst_cycles[perst_cnt_width-1:0];
               end
             else if( (|perst_cnt_q) )
               begin
                  // advance counter until sys_reset is asserted
                  // and then wait until perst control input is deasserted
                  if( sys_reset_n_q | ~(regs_pcie_perst | ctlff_dbg_perst) )
                    begin
                       perst_cnt_q <= perst_cnt_q - one[perst_cnt_width-1:0];
                    end
               end

             nperst1 <= ~(|perst_cnt_q);
             nperst2 <= nperst1 & ~regs_pcie_debug[2];  // route to perst pin            

             
             if( perst_cnt_q == Tsys_reset_start[perst_cnt_width-1:0] )
               begin
                  sys_reset_n_q <= 1'b0;
               end
             else if( perst_cnt_q == Tsys_reset_end[perst_cnt_width-1:0] )
               begin
                  sys_reset_n_q <= 1'b1;
               end             
          end
     end
   
   assign sys_reset_n = sys_reset_n_q;

   OBUF obuf_perst 
     (
      .O (pci_exp_nperst),
      .I (nperst2)
      );

   //-------------------------------------------------------
   // debug register read
   //-------------------------------------------------------

   // response to regs
   reg [63:0] dbg_data_q, dbg_data_d;
   reg        dbg_rdack_q, dbg_rdack_d;
   reg  [7:0] dbg_timeout_q, dbg_timeout_d;
   always @(posedge clk)
     begin
        dbg_data_q <= dbg_data_d;
        dbg_timeout_q <= dbg_timeout_d;
     end

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

   // interface to user_clk domain
   
   reg        dbg_rd_user_q, dbg_rd_user_d;
   (* ASYNC_REG = "TRUE" *) 
   reg [15:0] dbg_rdaddr_user_q;
   reg [15:0] dbg_rdaddr_user_d;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             dbg_rd_user_q     <= 1'b0;
             dbg_rdaddr_user_q <= zero[15:0];
           
          end
        else
          begin
             dbg_rd_user_q     <= dbg_rd_user_d;
             dbg_rdaddr_user_q <= dbg_rdaddr_user_d;       
          end
     end

   reg [63:0] dbg_user_data;  // user_clk   
   reg        dbg_user_ack;   // user_clk
   wire       dbg_user_ack_meta; // clk
   (* ASYNC_REG = "TRUE" *) 
   reg [63:0] dbg_user_data_meta_q;
   nvme_cdc cdc_user_ack (.clk(clk),.d(dbg_user_ack),.q(dbg_user_ack_meta));
   always @(posedge clk)
     dbg_user_data_meta_q <= dbg_user_data;
 

   genvar i;
   generate
      for( i=0; i<16; i = i + 1 ) 
        begin : cnt
           reg [19:0] cnt_rxcq_q;
           reg [19:0] cnt_txcc_q;
           always @(posedge clk or posedge reset)
             begin
                if( reset )
                  begin
                     cnt_rxcq_q <= 20'h0;
                     cnt_txcc_q <= 20'h0;
                  end
                else
                  begin
                     cnt_rxcq_q <= cnt_rxcq_q + (rxcq_dbg_events[i] ? 1 : 0);
                     cnt_txcc_q <= cnt_txcc_q + (txcc_dbg_events[i] ? 1 : 0);
                  end
             end
        end
   endgenerate
   

   integer loop;
   always @*
     begin      
        dbg_data_d         = ~zero[63:0];       
        dbg_rd_user_d      = 1'b0;
        dbg_rdaddr_user_d  = regs_pcie_dbg_addr;
        dbg_timeout_d      = dbg_timeout_q;

        if( regs_pcie_dbg_rd )
          begin
             if( dbg_timeout_q!=8'hff )
               dbg_timeout_d      = dbg_timeout_q + 8'h1;
          end
        else
          begin
             dbg_timeout_d = 8'h00;
          end
        
            
        if( regs_pcie_dbg_addr[15]==1'b0 )
          begin
             if( regs_pcie_dbg_addr[9:0] <16 )
               begin
                  dbg_data_d[63:20] = zero[63:20];
                  dbg_rdack_d = regs_pcie_dbg_rd & ~dbg_rdack_q;
                  case(regs_pcie_dbg_addr[3:0])
                    0: dbg_data_d[19:0] = cnt[0].cnt_rxcq_q;
                    1: dbg_data_d[19:0] = cnt[1].cnt_rxcq_q;
                    2: dbg_data_d[19:0] = cnt[2].cnt_rxcq_q;
                    3: dbg_data_d[19:0] = cnt[3].cnt_rxcq_q;
                    4: dbg_data_d[19:0] = cnt[4].cnt_rxcq_q;
                    5: dbg_data_d[19:0] = cnt[5].cnt_rxcq_q;
                    6: dbg_data_d[19:0] = cnt[6].cnt_rxcq_q;
                    7: dbg_data_d[19:0] = cnt[7].cnt_rxcq_q;
                    8: dbg_data_d[19:0] = cnt[8].cnt_rxcq_q;
                    9: dbg_data_d[19:0] = cnt[9].cnt_rxcq_q;
                    10: dbg_data_d[19:0] = cnt[10].cnt_rxcq_q;
                    11: dbg_data_d[19:0] = cnt[11].cnt_rxcq_q;
                    12: dbg_data_d[19:0] = cnt[12].cnt_rxcq_q;
                    13: dbg_data_d[19:0] = cnt[13].cnt_rxcq_q;
                    14: dbg_data_d[19:0] = cnt[14].cnt_rxcq_q;
                    15: dbg_data_d[19:0] = cnt[15].cnt_rxcq_q;                              
                    default: dbg_data_d = zero[63:0];
                  endcase // case (regs_pcie_dbg_addr)
               end
             else if( regs_pcie_dbg_addr[9:0]<32 )
               begin
                  dbg_data_d[63:20] = zero[63:20];
                  dbg_rdack_d = regs_pcie_dbg_rd & ~dbg_rdack_q;
                  case(regs_pcie_dbg_addr[3:0])
                    0: dbg_data_d[19:0] = cnt[0].cnt_txcc_q;
                    1: dbg_data_d[19:0] = cnt[1].cnt_txcc_q;
                    2: dbg_data_d[19:0] = cnt[2].cnt_txcc_q;
                    3: dbg_data_d[19:0] = cnt[3].cnt_txcc_q;
                    4: dbg_data_d[19:0] = cnt[4].cnt_txcc_q;
                    5: dbg_data_d[19:0] = cnt[5].cnt_txcc_q;
                    6: dbg_data_d[19:0] = cnt[6].cnt_txcc_q;
                    7: dbg_data_d[19:0] = cnt[7].cnt_txcc_q;
                    8: dbg_data_d[19:0] = cnt[8].cnt_txcc_q;
                    9: dbg_data_d[19:0] = cnt[9].cnt_txcc_q;
                    10: dbg_data_d[19:0] = cnt[10].cnt_txcc_q;
                    11: dbg_data_d[19:0] = cnt[11].cnt_txcc_q;
                    12: dbg_data_d[19:0] = cnt[12].cnt_txcc_q;
                    13: dbg_data_d[19:0] = cnt[13].cnt_txcc_q;
                    14: dbg_data_d[19:0] = cnt[14].cnt_txcc_q;
                    15: dbg_data_d[19:0] = cnt[15].cnt_txcc_q;                              
                    default: dbg_data_d = zero[63:0];
                  endcase // case (regs_pcie_dbg_addr)
               end
             else if( regs_pcie_dbg_addr[9:0]>=10'h200 )
               begin
                  // get regs from user_clk domain
                  dbg_rd_user_d = regs_pcie_dbg_rd;
                  dbg_rdack_d = dbg_user_ack_meta & regs_pcie_dbg_rd;
                  dbg_data_d = dbg_user_data_meta_q;
               end
             else
               begin
                  // unused
                  dbg_rdack_d = regs_pcie_dbg_rd & ~dbg_rdack_q;
               end
          end // if ( regs_pcie_dbg_addr[15]==1'b0 )
        else
          begin
             // PCIe trace arrays
             dbg_rd_user_d = regs_pcie_dbg_rd;
             dbg_rdack_d = dbg_user_ack_meta & regs_pcie_dbg_rd;
             dbg_data_d = dbg_user_data_meta_q;            
          end // else: !if( regs_pcie_dbg_addr[15]==1'b0 )

        // if there's no user_clk running, make sure register reads to user_clk complete
        if( dbg_timeout_q==8'hff )
          begin
             dbg_rdack_d = 1'b1;
             dbg_data_d = ~64'h0;
          end
        pcie_regs_dbg_ack = dbg_rdack_q;
        pcie_regs_dbg_data = dbg_data_q;
     end


   //-------------------------------------------------------
   // clock domain crossing: PSL->NVME
   //-------------------------------------------------------
     
   wire user_hot_reset;
   nvme_cdc cdc_user_hot_reset (.clk(user_clk),.d(regs_pcie_debug[0]),.q(user_hot_reset));
   wire user_link_training_disable;
   nvme_cdc cdc_linktraindis (.clk(user_clk),.d(regs_pcie_debug[1]),.q(user_link_training_disable));

   // read valid & address domain crossing
   wire dbg_user_read;
   nvme_cdc cdc_user_read (.clk(user_clk),.d(dbg_rd_user_q),.q(dbg_user_read));
   (* ASYNC_REG="TRUE" *) reg [15:0] dbg_user_addr_q;
   always @(posedge user_clk)
     begin    
        dbg_user_addr_q <= dbg_rdaddr_user_q;       
     end
    
   
   //-------------------------------------------------------
   // clock domain crossing: NVME->PSL
   //-------------------------------------------------------
   
   localparam status_width=1+2+4+3+6+1;
   wire [status_width-1:0] status_rdata;
   wire                    status_rval;
   wire                    status_rerr;
   reg                     status_write;
   reg  [status_width-1:0] status_wdata;
   wire                    status_wfull;

   reg               [3:0] cfg_negotiated_width_int;
   reg               [2:0] cfg_current_speed_int; 

   always @*
     begin
        pcie_regs_status[31:status_width+1]=zero[31:status_width+1];
        pcie_regs_status = {status_rval, status_rdata};

        // map from Ultrascale pcie3 to Ultrascale+ pcie4
        case(cfg_negotiated_width)
          3'h0: cfg_negotiated_width_int = 4'h1;
          3'h1: cfg_negotiated_width_int = 4'h2;
          3'h2: cfg_negotiated_width_int = 4'h4;
          3'h3: cfg_negotiated_width_int = 4'h8;       
          default: cfg_negotiated_width_int = 4'h0;
        endcase // case (cfg_negotiated_width)

        case(cfg_current_speed)
          2'h0: cfg_current_speed_int = 3'h1; // 2.5
          2'h1: cfg_current_speed_int = 3'h2; // 5.0
          2'h2: cfg_current_speed_int = 3'h4; // 8.0
          default: cfg_current_speed_int = 3'h0; 
        endcase
     end
   
   always @*
     begin
        status_write = 1'b1;
        status_wdata = {  user_reset, 
                          cfg_phy_link_down,
                          cfg_phy_link_status,
                          {cfg_negotiated_width_int},
                          {cfg_current_speed_int}, 
                          cfg_ltssm_state
                          };
     end
   
   // use async fifo to keep signals in sync across clock domain crossing
   // read and write clock frequency must be the same
   // if there's drift over time, overflow or underflow is ignored
   nvme_async_fifo#
     ( .width(status_width),
       .awidth(3)
       ) status_fifo
       (

        // read
        .rclk                           (clk),
        .rreset                         (reset),
        .rack                           (status_rval),
        .rdata                          (status_rdata),
        .rval                           (status_rval),
        .rerr                           (status_rerr),
        
        // write
        .wclk                           (user_clk),
        .wreset                         (1'b0), // treat user_reset as a status signal
        .write                          (status_write),
        .wdata                          (status_wdata),
        .wfull                          (status_wfull),
        .wafull	                        ()
        );

    //------------------------------------------------------
    // parity error 
    //------------------------------------------------------
   wire [1:0] clk_rxcq_perror_ind_meta;
   nvme_cdc cdc_rxcq_uperror_1 (.clk(clk),.d(user_rxcq_perror_ind[1]),.q(clk_rxcq_perror_ind_meta[1]));
   nvme_cdc cdc_rxcq_uperror_0 (.clk(clk),.d(user_rxcq_perror_ind[0]),.q(clk_rxcq_perror_ind_meta[0]));
   wire  clk_rxrc_perror_ind_meta;
   nvme_cdc cdc_rxrc_uperror_0 (.clk(clk),.d(user_rxrc_perror_ind),.q(clk_rxrc_perror_ind_meta));
   wire [1:0] clk_txcc_perror_ind_meta;
   nvme_cdc cdc_txcc_uperror_1 (.clk(clk),.d(user_txcc_perror_ind[1]),.q(clk_txcc_perror_ind_meta[1]));
   nvme_cdc cdc_txcc_uperror_0 (.clk(clk),.d(user_txcc_perror_ind[0]),.q(clk_txcc_perror_ind_meta[0]));
   wire clk_txrq_perror_ind_meta;
   nvme_cdc cdc_txrq_uperror_0 (.clk(clk),.d(user_txrq_perror_ind),.q(clk_txrq_perror_ind_meta));
   wire clk_ctlff_perror_ind_meta;
   nvme_cdc cdc_ctlff_uperror_0 (.clk(clk),.d(user_ctlff_perror_ind),.q(clk_ctlff_perror_ind_meta));

   reg        pe_errinj_d,pe_errinj_q;
   wire user_regs_wdata_pe_errinj_valid_meta;
   nvme_cdc cdc_pe_pcieinj_valid (.clk(user_clk),.d(regs_wdata_pe_errinj_valid),.q(user_regs_wdata_pe_errinj_valid_meta));


//-------------------------------------------------------------------
// pcie core fatal error
//-------------------------------------------------------------------
  wire user_hold_cfg_err_fatal_out;
  wire clk_hold_cfg_err_fatal_out_meta;

    nvme_srlat#
    (.width(1))  icfg_err_fatal   
    (.clk(user_clk),.reset(user_reset),.set_in(cfg_err_fatal_out),.hold_out(user_hold_cfg_err_fatal_out));

   nvme_cdc cdc_rxcq_uperror (.clk(clk),.d(user_hold_cfg_err_fatal_out),.q(clk_hold_cfg_err_fatal_out_meta));



   always @(posedge clk)
     begin
        cdc_rxcq_perror_ind        <= clk_rxcq_perror_ind_meta;
        cdc_rxrc_perror_ind        <= clk_rxrc_perror_ind_meta;
        cdc_txcc_perror_ind        <= clk_txcc_perror_ind_meta;
        cdc_txrq_perror_ind        <= clk_txrq_perror_ind_meta;
        cdc_ctlff_perror_ind       <= clk_ctlff_perror_ind_meta;
        cdc_hold_cfg_err_fatal_out <= clk_hold_cfg_err_fatal_out_meta;
     end   

   //-------------------------------------------------------
   // NVME clock domain logic
   //-------------------------------------------------------
   // control these by mmio
   assign cfg_hot_reset            = user_hot_reset;   
   assign cfg_link_training_enable = ~user_link_training_disable;


   // enable parity checking via write to config register in core
   wire     need_config_changes_d;
   reg      start_cfg_loop_q = 1'b0;
   reg      start_cfg_loop_qq = 1'b0;
   wire     start_cfg_pulse;
   reg      user_reset_q;
   reg [3:0] nxt_state;
   reg [3:0] state_q;
   reg  [9:0] cfg_address_q;
   reg [31:0] cfg_wdata_q;
   wire last_config_op_done;

   assign cfg_mgmt_addr = cfg_address_q;
   assign cfg_mgmt_write = ((state_q == 4'b0001) | (state_q == 4'b0010)) ? 1'b1 : 1'b0;
   assign cfg_mgmt_write_data = cfg_wdata_q;
   assign cfg_mgmt_byte_enable = 4'hF;
   assign cfg_mgmt_read = (state_q == 4'b1000) ? 1'b1 : 1'b0;
   // [31:0] cfg_mgmt_read_data,
   //  cfg_mgmt_read_write_done,

   always @(posedge user_clk)
     begin
       user_reset_q <= user_reset;
       start_cfg_loop_qq <= start_cfg_loop_q;
     end

   always @(posedge user_clk)
     begin
       if(~user_reset & user_reset_q)
         start_cfg_loop_q <= 1'b1;
       else if(last_config_op_done)
         start_cfg_loop_q <= 1'b0;
       else
         start_cfg_loop_q <= start_cfg_loop_q;
     end

   assign start_cfg_pulse = start_cfg_loop_q & ~start_cfg_loop_qq;
   assign last_config_op_done = (cfg_address_q == 10'b0001001011) & cfg_mgmt_read_write_done;

   always @*
     begin
        if (user_reset)
          begin
             nxt_state    <= 4'b0000;         
          end
        else if (start_cfg_pulse | cfg_mgmt_read_write_done)
          begin
             nxt_state    <= state_q + 4'b0001;
          end
        else
          begin
             nxt_state    <= state_q;
          end
     end

   always @(posedge user_clk)
     begin
       state_q <= nxt_state;
     end

   always @(posedge user_clk or posedge user_reset)
     begin
        if (user_reset)
          begin
             cfg_address_q    <= 10'b0000000000;
             cfg_wdata_q      <= 32'h00000000;         
          end
        else if (nxt_state == 4'b0001)
          begin
             cfg_address_q    <= 10'b0001000010;
             cfg_wdata_q      <= 32'h00000000;
          end
        else if (nxt_state == 4'b0010)
          begin
             cfg_address_q    <= 10'b0001001011;
             cfg_wdata_q      <= 32'h00000007;
          end
        else
          begin
             cfg_address_q    <= cfg_address_q;
             cfg_wdata_q      <= cfg_wdata_q;
          end
     end

   //-------------------------------------------------------
   // timer for debug trace
   //-------------------------------------------------------
     
   // 1us timestamp 
   reg   [7:0] timer1_us_q; 
   reg  [31:0] timer1_q;
   reg         tick1_q;

   initial
     begin
        timer1_q    = 32'h0;         
        timer1_us_q = 8'h0;
        tick1_q     = 1'b0;
     end
   
   always @(posedge user_clk)
     begin
        // 1 us period free running counter, no reset
        if (timer1_us_q >= 8'd249)
          begin
             timer1_us_q  <= 8'h0;   
             tick1_q      <= 1'b1;
          end
        else
          begin
             timer1_us_q  <= timer1_us_q+8'h1;
             tick1_q      <= 1'b0;
          end

        if( tick1_q )
          begin
             timer1_q[31:0] <= timer1_q[31:0] + 32'h1;  
          end
        else
          begin
             timer1_q     <= timer1_q;
          end
     end
   
   //-------------------------------------------------------
   // RXCQ last request for each tag
   //-------------------------------------------------------
   // memory descriptor fields
   reg                 [1:0] rxcq_addr_type;
   reg                [63:2] rxcq_addr;
   reg                [10:0] rxcq_dcount;
   reg                 [3:0] rxcq_reqtype;
   reg                       rxcq_resv1;
   reg                [15:0] rxcq_bdf;
   reg                 [7:0] rxcq_tag; 
   reg                 [7:0] rxcq_target;
   reg                 [8:0] rxcq_bar;
   reg                 [2:0] rxcq_tc;
   reg                 [2:0] rxcq_attr;
   reg                       rxcq_resv2;
   // sideband
   reg                 [3:0] rxcq_last_be;
   reg                 [3:0] rxcq_first_be;
   reg                       rxcq_req_rd;
   reg                       rxcq_discard;
   reg                       rxcq_first;
   reg                       rxcq_last;
   reg                 [3:0] rxcq_keep;

   // unpack descriptor - see pg156-ultrascale-pcie doc figure 3-22.
   always @*
     begin
        {rxcq_req_rd, rxcq_first, rxcq_last, rxcq_discard, rxcq_first_be, rxcq_last_be, rxcq_keep,
         rxcq_resv2, rxcq_attr, rxcq_tc, rxcq_bar, rxcq_target, rxcq_tag, rxcq_bdf,
         rxcq_resv1, rxcq_reqtype, rxcq_dcount, rxcq_addr, rxcq_addr_type} = rxcq_dbg_user_tracedata;
     end
   
   localparam rxcq_stat_width=32 + 4 + 4 + 11 + 62;
   // 256 entries - extended tags
   reg      [rxcq_stat_width-1:0] rxcq_stat_mem[255:0];
   reg      [rxcq_stat_width-1:0] rxcq_stat_wrdata;
   reg                      [7:0] rxcq_stat_wraddr;
   reg                            rxcq_stat_write;
   reg      [rxcq_stat_width-1:0] rxcq_stat_rddata;

   always @(posedge user_clk)
     begin
        if (rxcq_stat_write)
          rxcq_stat_mem[rxcq_stat_wraddr] <= rxcq_stat_wrdata;
        rxcq_stat_rddata <= rxcq_stat_mem[dbg_user_addr_q[7+1:1]];
     end   
     
   always @*
     begin      
        rxcq_stat_wrdata = {timer1_q, rxcq_first_be, rxcq_last_be, rxcq_dcount, rxcq_addr};
        rxcq_stat_wraddr = rxcq_tag;        
        rxcq_stat_write = rxcq_dbg_user_tracevalid & rxcq_first & rxcq_req_rd & ~rxcq_discard;
     end

   //-------------------------------------------------------
   // TXCC last completion for each tag
   //-------------------------------------------------------   
   // see pg156-ultrascale-pcie-gen3.pdf Sept30, 2015 (pg156) Figure 3-28 for descriptor definitions
   reg                 [6:0] txcc_lower_addr; 
   reg                 [7:0] txcc_tag;         
   reg                [10:0] txcc_cpl_dcount;  
   reg                 [2:0] txcc_cpl_status; 
   reg                [12:0] txcc_byte_count;  
   reg                 [2:0] txcc_tc;          
   reg                 [2:0] txcc_attr;        
   reg                 [1:0] txcc_at;         

   reg                       txcc_resv1;
   reg                 [1:0] txcc_resv2;
   reg                 [7:2] txcc_resv3;
   reg                       txcc_resv4;   
   reg                       txcc_locked_read;
   reg                       txcc_poisoned;
   reg                [15:0] txcc_requester_id;
   reg                [15:0] txcc_completer_id;
   reg                       txcc_completer_id_enable; 
   reg                       txcc_force_ecrc;

   // sideband/data
   reg                [31:0] txcc_dw0;
   reg                       txcc_discontinue;
   reg                       txcc_first;
   reg                       txcc_last;
   reg                 [3:0] txcc_keep;

   always @*
     begin
        { txcc_last, txcc_first, txcc_discontinue, txcc_keep, txcc_dw0, txcc_force_ecrc, txcc_attr, txcc_tc, txcc_completer_id_enable, txcc_completer_id, txcc_tag,
          txcc_requester_id, txcc_resv1, txcc_poisoned, txcc_cpl_status, txcc_cpl_dcount, txcc_resv2,
          txcc_locked_read, txcc_byte_count, txcc_resv3, txcc_at, txcc_resv4, txcc_lower_addr } = txcc_dbg_user_tracedata;
     end
   
   localparam txcc_stat_width=32 + 11 + 3 + 13 + 7;
   // 256 entries - extended tags
   reg      [txcc_stat_width-1:0] txcc_stat_mem[255:0];
   reg      [txcc_stat_width-1:0] txcc_stat_wrdata;
   reg                      [7:0] txcc_stat_wraddr;
   reg                            txcc_stat_write;
   reg      [txcc_stat_width-1:0] txcc_stat_rddata;

   always @(posedge user_clk)
     begin
        if (txcc_stat_write)
          txcc_stat_mem[txcc_stat_wraddr] <= txcc_stat_wrdata;
        txcc_stat_rddata <= txcc_stat_mem[dbg_user_addr_q[7+1:1]];
     end
     
   always @*
     begin      
        txcc_stat_wrdata = {timer1_q,txcc_lower_addr,txcc_byte_count,txcc_cpl_status, txcc_cpl_dcount};
        txcc_stat_wraddr = txcc_tag;        
        txcc_stat_write = txcc_dbg_user_tracevalid & txcc_first;
     end

   //-------------------------------------------------------
   // check for tag reuse
   //-------------------------------------------------------

   reg [255:0] tag_busy_q, tag_busy_d;
   reg         txcc_tag_error_q, txcc_tag_error_d;
   reg         rxcq_tag_error_d, rxcq_tag_error_q;
   always @(posedge user_clk or posedge user_reset)
     begin
        if( user_reset )
          begin
             tag_busy_q       <= 256'h0;
             txcc_tag_error_q <= 1'b0;
             rxcq_tag_error_q <= 1'b0;
             pe_errinj_q <= 1'b0; 
          end
        else
          begin
             tag_busy_q       <= tag_busy_d;
             txcc_tag_error_q <= txcc_tag_error_d;
             rxcq_tag_error_q <= rxcq_tag_error_d;
             pe_errinj_q <= pe_errinj_d;  
          end
     end

    always @*
     begin
       pe_errinj_d = user_regs_wdata_pe_errinj_valid_meta; 
       user_regs_wdata_pe_errinj_valid = user_regs_wdata_pe_errinj_valid_meta & ~pe_errinj_q; 
     end 

   always @*
     begin
        tag_busy_d = tag_busy_q;
        txcc_tag_error_d = txcc_tag_error_q;
        rxcq_tag_error_d = rxcq_tag_error_q;

        if( txcc_stat_write  && 
            (txcc_byte_count[12:2]<=txcc_cpl_dcount[10:0] ||
             txcc_cpl_status!=3'b000))
          begin
             tag_busy_d[txcc_stat_wraddr] = 1'b0;
             txcc_tag_error_d = txcc_tag_error_q | ~tag_busy_q[txcc_stat_wraddr];
          end

        if( rxcq_stat_write)
          begin
             tag_busy_d[rxcq_stat_wraddr] = 1'b1;
             rxcq_tag_error_d = rxcq_tag_error_q | tag_busy_q[rxcq_stat_wraddr];
          end                
     end
   
   nvme_cdc cdc_txcc_tag_error (.clk(clk),.d(txcc_tag_error_q),.q(pcie_regs_dbg_error[0]));      
   nvme_cdc cdc_rxcq_tag_error (.clk(clk),.d(rxcq_tag_error_q),.q(pcie_regs_dbg_error[1]));      
   

   //-------------------------------------------------------
   // trace buffers
   //-------------------------------------------------------

  

   localparam rxcq_trace_width=1+32+144;
   localparam rxcq_trace_entries=512;
   localparam rxcq_trace_awidth=$clog2(rxcq_trace_entries);

   wire    [rxcq_trace_width:0] rxcq_trace_rddata;
   wire [rxcq_trace_awidth-1:0] rxcq_trace_wrtail;
   wire                         rxcq_trace_wrphase;

   reg   [rxcq_trace_width-1:0] rxcq_trace_wrdata;
   reg                          rxcq_trace_write;

   always @*
     begin
        if( regs_pcie_debug[3] )
          begin
             rxcq_trace_write = rxcq_dbg_user_tracevalid & (rxcq_first | ~regs_pcie_debug[6]);  // debug[6]=1 to only capture first cycle
             rxcq_trace_wrdata = {1'b1, timer1_q, rxcq_dbg_user_tracedata};
          end
        else
          begin
             rxcq_trace_write = rxrc_dbg_user_tracevalid;
             rxcq_trace_wrdata = {1'b0, timer1_q, rxrc_dbg_user_tracedata};
          end
     end

   `ifdef NVME_PCIE_DEBUG
   nvme_pcie_trace#
     (
      .width(rxcq_trace_width),
      .entries(rxcq_trace_entries)      
      ) trace_rxcq
     (
      // Outputs
      .rddata                           (rxcq_trace_rddata[rxcq_trace_width:0]),
      .wrtail                           (rxcq_trace_wrtail[rxcq_trace_awidth-1:0]),
      .wrphase                          (rxcq_trace_wrphase),
      // Inputs
      .clk                              (user_clk),
      .reset                            (1'b0),
      .wrdata                           (rxcq_trace_wrdata),
      .wrvalid                          (rxcq_trace_write),
      .rdaddr                           (dbg_user_addr_q[rxcq_trace_awidth-1+2:2])
      );
   `else
   assign rxcq_trace_rddata = '0;
   assign rxcq_trace_wrtail = '0;
   assign rxcq_trace_phase = 1'b0;
   `endif
   
   //-------------------------------------------------------

   localparam txcc_trace_width=1+32+144;
   localparam txcc_trace_entries=512;
   localparam txcc_trace_awidth=$clog2(txcc_trace_entries);

   wire    [txcc_trace_width:0] txcc_trace_rddata;
   wire [txcc_trace_awidth-1:0] txcc_trace_wrtail;
   wire                         txcc_trace_wrphase;

   reg   [txcc_trace_width-1:0] txcc_trace_wrdata;
   reg                          txcc_trace_write;

   always @*
     begin
        if( regs_pcie_debug[4] )
          begin
             txcc_trace_write = txcc_dbg_user_tracevalid & (txcc_first | ~regs_pcie_debug[7]);  // debug[7]=1 to only capture first cycle
             txcc_trace_wrdata = {1'b1, timer1_q, txcc_dbg_user_tracedata};
          end
        else
          begin
             txcc_trace_write = txrq_dbg_user_tracevalid;
             txcc_trace_wrdata = {1'b0, timer1_q, txrq_dbg_user_tracedata};
          end
     end
   `ifdef NVME_PCIE_DEBUG
   nvme_pcie_trace#
     (
      .width(txcc_trace_width),
      .entries(txcc_trace_entries)      
      ) trace_txcc
     (
      // Outputs
      .rddata                           (txcc_trace_rddata[txcc_trace_width:0]),
      .wrtail                           (txcc_trace_wrtail[txcc_trace_awidth-1:0]),
      .wrphase                          (txcc_trace_wrphase),
      // Inputs
      .clk                              (user_clk),
      .reset                            (1'b0),
      .wrdata                           (txcc_trace_wrdata),
      .wrvalid                          (txcc_trace_write),
      .rdaddr                           (dbg_user_addr_q[txcc_trace_awidth-1+2:2])
      );
   `else
   assign txcc_trace_rddata = '0;
   assign txcc_trace_wrtail = '0;
   assign txcc_trace_wrphase = 1'b0;
   `endif

   //-------------------------------------------------------

   localparam ctlff_trace_width=32+22+9+64;
   localparam ctlff_trace_entries=512;
   localparam ctlff_trace_awidth=$clog2(ctlff_trace_entries);

   wire    [ctlff_trace_width:0] ctlff_trace_rddata;
   wire [ctlff_trace_awidth-1:0] ctlff_trace_wrtail;
   wire                         ctlff_trace_wrphase;
   reg                          ctlff_trace_write;
   reg  [ctlff_trace_width-1:0] ctlff_trace_wrdata;

   `ifdef NVME_PCIE_DEBUG
   nvme_pcie_trace#
     (
      .width(ctlff_trace_width),
      .entries(ctlff_trace_entries)      
      ) trace_ctlff
     (
      // Outputs
      .rddata                           (ctlff_trace_rddata[ctlff_trace_width:0]),
      .wrtail                           (ctlff_trace_wrtail[ctlff_trace_awidth-1:0]),
      .wrphase                          (ctlff_trace_wrphase),
      // Inputs
      .clk                              (user_clk),
      .reset                            (1'b0),
      .wrdata                           (ctlff_trace_wrdata),
      .wrvalid                          (ctlff_trace_write),
      .rdaddr                           (dbg_user_addr_q[ctlff_trace_awidth-1+1:1])
      );
   `else
   assign ctlff_trace_rddata = '0;
   assign ctlff_trace_wrtail = '0;
   assign ctlff_trace_wrphase = 1'b0;
   `endif
   
   // write ctlff fifo only on change
   reg  [ctlff_trace_width-1:0] ctlff_trace_lastdata_q,  ctlff_trace_lastdata_d;
   reg                          ctlff_trace_write_q, ctlff_trace_write_d;
   reg                    [5:0] ltssm_q, ltssm_d;
   reg                   [31:0] regs_debug_trace_q, regs_debug_trace_d;

   initial
     begin
        ctlff_trace_write_q = 1'b0;
        ctlff_trace_lastdata_q = zero[ctlff_trace_width-1:0];
        ltssm_q = zero[5:0];
        regs_debug_trace_q = zero[31:0];
     end
   
   always @(posedge user_clk)
     begin
        ctlff_trace_write_q <= ctlff_trace_write_d;
        ctlff_trace_lastdata_q <= ctlff_trace_lastdata_d;
        ltssm_q <= ltssm_d;
        regs_debug_trace_q <= regs_debug_trace_d;
     end

   always @*
     begin
        ltssm_d =  cfg_ltssm_state[5:0];
        regs_debug_trace_d = regs_pcie_debug_trace; // clock domain crossing - no synchronizer
        
        ctlff_trace_lastdata_d = { timer1_q[31:0],ltssm_q, regs_debug_trace_q[21:0],   user_lnk_up, user_reset, cfg_phy_link_down, ctlff_dbg_user_trace};
        
        if(  regs_pcie_debug[5]==0 ||  // if set, only write trace once
             ctlff_trace_wrphase==1'b1 )
          begin
             //  only write on change.  ignore timer1 changes and ltssm changes when link up==1
             if( user_lnk_up ) 
               ctlff_trace_write_d =  ctlff_trace_lastdata_q[ctlff_trace_width-32-6-1:0]!=ctlff_trace_lastdata_d[ctlff_trace_width-32-6-1:0];
             else
               ctlff_trace_write_d =  ctlff_trace_lastdata_q[ctlff_trace_width-32-1:0]!=ctlff_trace_lastdata_d[ctlff_trace_width-32-1:0];              
          end
        else
          begin
             ctlff_trace_write_d = 1'b0;
          end        

        ctlff_trace_wrdata = ctlff_trace_lastdata_q;
        ctlff_trace_write = ctlff_trace_write_q;
     end   

   
   //-------------------------------------------------------
   // debug counters in user_clk domain
   //-------------------------------------------------------
   
   generate
      for( i=0; i<16; i = i + 1 ) 
        begin : cnt_user
           reg [19:0] cnt_rxcq_q;
           reg [19:0] cnt_txcc_q;
           always @(posedge user_clk or posedge user_reset)
             begin
                if( user_reset )
                  begin
                     cnt_rxcq_q <= 20'h0;
                     cnt_txcc_q <= 20'h0;
                  end
                else
                  begin
                     cnt_rxcq_q <= cnt_rxcq_q + (rxcq_dbg_user_events[i] ? 1 : 0);
                     cnt_txcc_q <= cnt_txcc_q + (txcc_dbg_user_events[i] ? 1 : 0);
                  end
             end
        end
   endgenerate


   
   // interface to host clock domain
   
   reg dbg_user_ack_q, dbg_user_ack_d;
   reg dbg_user_dly_q, dbg_user_dly_d;
   always @(posedge user_clk or posedge user_reset)
     begin
        if( user_reset )
          begin
             dbg_user_ack_q <= 1'b0;
             dbg_user_dly_q <= 1'b0;
          end
        else
          begin
             dbg_user_ack_q <= dbg_user_ack_d;
             dbg_user_dly_q <= dbg_user_dly_d;
          end
     end

   (* ASYNC_REG = "TRUE" *) 
   reg [63:0] dbg_user_data_q;
   reg [63:0] dbg_user_data_d;
   always @(posedge user_clk)
     begin
        dbg_user_data_q <= dbg_user_data_d;
     end
   
   always @*
     begin
        dbg_user_ack_d = 1'b0;        
        dbg_user_data_d = dbg_user_data_q;

        dbg_user_ack  = dbg_user_ack_q;
        dbg_user_data = dbg_user_data_q;

        dbg_user_dly_d = dbg_user_read;  // delay 1 cycle for sram access
        
        if( dbg_user_read )
          begin
             if( dbg_user_addr_q[15]==1'b0 )
               begin
                  dbg_user_ack_d = 1'b1;
                  dbg_user_data_d[63:20] = zero[63:20];
                  if( dbg_user_addr_q[8:0]<32 )
                    begin      
                       // 512-543
                       case(dbg_user_addr_q[4:0])
                         0: dbg_user_data_d[19:0] = cnt_user[0].cnt_rxcq_q;
                         1: dbg_user_data_d[19:0] = cnt_user[1].cnt_rxcq_q;
                         2: dbg_user_data_d[19:0] = cnt_user[2].cnt_rxcq_q;
                         3: dbg_user_data_d[19:0] = cnt_user[3].cnt_rxcq_q;
                         4: dbg_user_data_d[19:0] = cnt_user[4].cnt_rxcq_q;
                         5: dbg_user_data_d[19:0] = cnt_user[5].cnt_rxcq_q;
                         6: dbg_user_data_d[19:0] = cnt_user[6].cnt_rxcq_q;
                         7: dbg_user_data_d[19:0] = cnt_user[7].cnt_rxcq_q;
                         8: dbg_user_data_d[19:0] = cnt_user[8].cnt_rxcq_q;
                         9: dbg_user_data_d[19:0] = cnt_user[9].cnt_rxcq_q;
                         10: dbg_user_data_d[19:0] = cnt_user[10].cnt_rxcq_q;
                         11: dbg_user_data_d[19:0] = cnt_user[11].cnt_rxcq_q;
                         12: dbg_user_data_d[19:0] = cnt_user[12].cnt_rxcq_q;
                         13: dbg_user_data_d[19:0] = cnt_user[13].cnt_rxcq_q;
                         14: dbg_user_data_d[19:0] = cnt_user[14].cnt_rxcq_q;
                         15: dbg_user_data_d[19:0] = cnt_user[15].cnt_rxcq_q;                              
                         default: dbg_user_data_d = zero[63:0];
                       endcase
                    end
                  else if( dbg_user_addr_q[8:0]<64 )
                    begin       
                       // 544-573
                       dbg_user_data_d[63:20] = zero[63:20];
                       case(dbg_user_addr_q[4:0])
                         0: dbg_user_data_d[19:0] = cnt_user[0].cnt_txcc_q;
                         1: dbg_user_data_d[19:0] = cnt_user[1].cnt_txcc_q;
                         2: dbg_user_data_d[19:0] = cnt_user[2].cnt_txcc_q;
                         3: dbg_user_data_d[19:0] = cnt_user[3].cnt_txcc_q;
                         4: dbg_user_data_d[19:0] = cnt_user[4].cnt_txcc_q;
                         5: dbg_user_data_d[19:0] = cnt_user[5].cnt_txcc_q;
                         6: dbg_user_data_d[19:0] = cnt_user[6].cnt_txcc_q;
                         7: dbg_user_data_d[19:0] = cnt_user[7].cnt_txcc_q;
                         8: dbg_user_data_d[19:0] = cnt_user[8].cnt_txcc_q;
                         9: dbg_user_data_d[19:0] = cnt_user[9].cnt_txcc_q;
                         10: dbg_user_data_d[19:0] = cnt_user[10].cnt_txcc_q;
                         11: dbg_user_data_d[19:0] = cnt_user[11].cnt_txcc_q;
                         12: dbg_user_data_d[19:0] = cnt_user[12].cnt_txcc_q;
                         13: dbg_user_data_d[19:0] = cnt_user[13].cnt_txcc_q;
                         14: dbg_user_data_d[19:0] = cnt_user[14].cnt_txcc_q;
                         15: dbg_user_data_d[19:0] = cnt_user[15].cnt_txcc_q;                              
                         default: dbg_user_data_d = zero[63:0];
                       endcase
                    end

                  else
                    begin
                       // 704-1023
                       if( dbg_user_addr_q[8:0]==192 )
                         begin
                            dbg_user_data_d = { ctlff_trace_wrphase, ctlff_trace_wrtail, timer1_q};
                         end
                       else
                         begin
                            dbg_user_data_d = ~zero[63:0];
                         end                                     
                    end
               end // if ( dbg_user_addr_q[15]==1'b0 )
             else
               begin
                  // PCIe trace                 
                  dbg_user_ack_d = dbg_user_dly_q;
                  case( dbg_user_addr_q[14:12] )
                    3'b000:
                      begin
                         // first 16KB of PCIe trace address space
                         if( dbg_user_addr_q[0] == 1'b0)
                           dbg_user_data_d = ctlff_trace_rddata[63:0];                          
                         else 
                           dbg_user_data_d = ctlff_trace_rddata[ctlff_trace_width:64];
                      end
                    3'b010:
                      begin
                         // next 32KB of PCIe trace address space
                         case(dbg_user_addr_q[1:0])
                           0: dbg_user_data_d = rxcq_trace_rddata[63:0];
                           1: dbg_user_data_d = rxcq_trace_rddata[127:64];
                           2: dbg_user_data_d = { zero[191:rxcq_trace_width+1], rxcq_trace_rddata[rxcq_trace_width:128]};
                           default: dbg_user_data_d = {rxcq_trace_wrphase, rxcq_trace_wrtail, timer1_q};
                         endcase // case (dbg_user_addr_q[1:0])
                      end
                    3'b011:                  
                      begin
                         // last 32KB of PCIe trace address space
                         case(dbg_user_addr_q[1:0])
                           0: dbg_user_data_d = txcc_trace_rddata[63:0];
                           1: dbg_user_data_d = txcc_trace_rddata[127:64];
                           2: dbg_user_data_d = { zero[191:txcc_trace_width+1], txcc_trace_rddata[txcc_trace_width:128] };
                           default: dbg_user_data_d = {txcc_trace_wrphase, txcc_trace_wrtail, timer1_q};
                         endcase // case (dbg_user_addr_q[1:0]) 
                      end
                    3'b100:
                      begin
                         // 256 entries in rxcq_stat, 16B each
                         if( dbg_user_addr_q[11:9]==4'h0 )
                           begin                            
                              if( dbg_user_addr_q[0] )
                                begin
                                   dbg_user_data_d = {zero[127:rxcq_stat_width],rxcq_stat_rddata[rxcq_stat_width-1:64]};
                                end	
                              else
                                begin
                                   dbg_user_data_d = rxcq_stat_rddata[63:0];
                                end                       
                           end          
                         else if( dbg_user_addr_q[11:9]==4'h1 )                    
                           begin
                              // 256 entries in txcc_stat, 16B each
                              if( dbg_user_addr_q[0] )
                                begin
                                   dbg_user_data_d = {zero[127:txcc_stat_width],txcc_stat_rddata[txcc_stat_width-1:64]};
                                end
                              else
                                begin
                                   dbg_user_data_d = txcc_stat_rddata[63:0];
                                end                  
                           end
                         else
                           begin
                              dbg_user_data_d = ~zero[63:0];
                           end                         
                      end                    
                    
                    default:
                      begin
                         dbg_user_data_d = ~zero[63:0];
                      end
                  endcase
             
               end // else: !if( dbg_user_addr_q[15]==1'b0 )             
          end // if ( dbg_user_read_q[2] )
        else
          begin
             dbg_user_ack_d = 1'b0;
             dbg_user_data_d = dbg_user_data_q;
          end // always @ *               
     end


endmodule

