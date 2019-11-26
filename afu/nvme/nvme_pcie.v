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
//  File : nvme_pcie.v
//  *************************************************************************
//  *************************************************************************
//  Description : Surelock Express NVMe PCIe port
//                
//       Xilinx PCIe IP plus async fifos for each interface
//
//  *************************************************************************

module nvme_pcie#
  ( 
    parameter port_id = 0,
    parameter LINK_WIDTH = 4,
    parameter data_width = 145,
    parameter AXI4_CQ_TUSER_WIDTH = 88,
    parameter AXI4_CC_TUSER_WIDTH = 33,
    parameter AXI4_RQ_TUSER_WIDTH = 62,
    parameter AXI4_RC_TUSER_WIDTH = 75

    )
   (

    // afu clock domain
    input                   reset,
    input                   clk, 
    //-------------------------------------------------------
    // PCI Express (pci_exp) Interface
    //-------------------------------------------------------
    output [LINK_WIDTH-1:0] pci_exp_txp,
    output [LINK_WIDTH-1:0] pci_exp_txn,
    input  [LINK_WIDTH-1:0] pci_exp_rxp,
    input  [LINK_WIDTH-1:0] pci_exp_rxn,

    output                  pci_exp_nperst,

    input                   pci_exp_refclk_p, // 100Mhz refclk
    input                   pci_exp_refclk_n, // 100Mhz refclk

    //-------------------------------------------------------
    // ucontrol IO bus
    //-------------------------------------------------------
    input            [31:0] ctl_pcie_ioaddress,
    input                   ctl_pcie_ioread_strobe, 
    input            [31:0] ctl_pcie_iowrite_data,
    input                   ctl_pcie_iowrite_strobe,
    output           [31:0] pcie_ctl_ioread_data, // read_data is sampled when ready=1
    output            [3:0] pcie_ctl_ioread_datap,
    output                  pcie_ctl_ioack,

    //-------------------------------------------------------
    // Admin Q doorbell write
    //-------------------------------------------------------
    input                   adq_pcie_wrvalid,
    input            [31:0] adq_pcie_wraddr,
    input            [15:0] adq_pcie_wrdata,
    output                  pcie_adq_wrack,
  
    //-------------------------------------------------------
    // I/O Q doorbell write
    //-------------------------------------------------------
    input                   ioq_pcie_wrvalid,
    input            [31:0] ioq_pcie_wraddr,
    input            [15:0] ioq_pcie_wrdata,
    output                  pcie_ioq_wrack, 
       
    //-------------------------------------------------------
    // DMA requests to Admin Q
    //-------------------------------------------------------
  
    output                  pcie_adq_valid,
    output          [144:0] pcie_adq_data, 
    output                  pcie_adq_first, 
    output                  pcie_adq_last, 
    output                  pcie_adq_discard, 
    input                   adq_pcie_pause, 

    //-------------------------------------------------------
    // DMA requests to I/O Q
    //-------------------------------------------------------

    output                  pcie_ioq_valid,
    output          [144:0] pcie_ioq_data,
    output                  pcie_ioq_first, 
    output                  pcie_ioq_last,
    output                  pcie_ioq_discard,
    input                   ioq_pcie_pause,

    //-------------------------------------------------------
    // DMA requests to SNTL
    //-------------------------------------------------------        
    output                  pcie_sntl_valid,
    output          [144:0] pcie_sntl_data,
    output                  pcie_sntl_first, 
    output                  pcie_sntl_last,
    output                  pcie_sntl_discard,
    input                   sntl_pcie_pause,
    input                   sntl_pcie_ready,

    //-------------------------------------------------------
    // DMA requests to SNTL write buffer
    //-------------------------------------------------------        
    output                  pcie_sntl_wbuf_valid,
    output          [144:0] pcie_sntl_wbuf_data,
    output                  pcie_sntl_wbuf_first, 
    output                  pcie_sntl_wbuf_last,
    output                  pcie_sntl_wbuf_discard,
    input                   sntl_pcie_wbuf_pause,

    //-------------------------------------------------------
    // DMA requests to SNTL admin buffer
    //-------------------------------------------------------        
    output                  pcie_sntl_adbuf_valid,
    output          [144:0] pcie_sntl_adbuf_data,
    output                  pcie_sntl_adbuf_first, 
    output                  pcie_sntl_adbuf_last,
    output                  pcie_sntl_adbuf_discard,
    input                   sntl_pcie_adbuf_pause,
    
    //-------------------------------------------------------
    // DMA response from Admin Q
    //-------------------------------------------------------        
   
    input           [144:0] adq_pcie_cc_data,
    input                   adq_pcie_cc_first,
    input                   adq_pcie_cc_last,
    input                   adq_pcie_cc_discard,
    input                   adq_pcie_cc_valid,
    output                  pcie_adq_cc_ready,

    //-------------------------------------------------------
    // DMA response from I/O Q
    //-------------------------------------------------------        

    input           [144:0] ioq_pcie_cc_data,
    input                   ioq_pcie_cc_first,
    input                   ioq_pcie_cc_last,
    input                   ioq_pcie_cc_discard,
    input                   ioq_pcie_cc_valid,
    output                  pcie_ioq_cc_ready,

    //-------------------------------------------------------
    // DMA response from SNTL
    //-------------------------------------------------------        

    input           [144:0] sntl_pcie_cc_data,
    input                   sntl_pcie_cc_first,
    input                   sntl_pcie_cc_last,
    input                   sntl_pcie_cc_discard,
    input                   sntl_pcie_cc_valid,
    output                  pcie_sntl_cc_ready,
    
    //-------------------------------------------------------
    // DMA response from SNTL write buffer
    //-------------------------------------------------------        

    input           [144:0] sntl_pcie_wbuf_cc_data,
    input                   sntl_pcie_wbuf_cc_first,
    input                   sntl_pcie_wbuf_cc_last,
    input                   sntl_pcie_wbuf_cc_discard,
    input                   sntl_pcie_wbuf_cc_valid,
    output                  pcie_sntl_wbuf_cc_ready,
    
    //-------------------------------------------------------
    // DMA response from SNTL admin buffer
    //-------------------------------------------------------        

    input           [144:0] sntl_pcie_adbuf_cc_data,
    input                   sntl_pcie_adbuf_cc_first,
    input                   sntl_pcie_adbuf_cc_last,
    input                   sntl_pcie_adbuf_cc_discard,
    input                   sntl_pcie_adbuf_cc_valid,
    output                  pcie_sntl_adbuf_cc_ready,
    
    //-------------------------------------------------------
    // debug access to endpoint PCIe/NVMe
    //-------------------------------------------------------
    input                   regs_pcie_valid, // command valid
    output                  pcie_regs_ack, // command taken
    input                   regs_pcie_rnw, // read=1 write=0
    input                   regs_pcie_configop,// configop=1 (pcie) mmio=0 (nvme)
    input             [3:0] regs_pcie_tag, // 4b tag for pcie op
    input             [3:0] regs_pcie_be, // 4b byte enable
    input            [31:0] regs_pcie_addr, // config reg # or mmio offset from NVME BAR
    input            [31:0] regs_pcie_wrdata,
    output           [31:0] pcie_regs_cpl_data,
    output            [3:0] pcie_regs_cpl_datap, 
    output                  pcie_regs_cpl_valid,
    output           [15:0] pcie_regs_cpl_status, // be[7:0], poison, status[2:0], errcode[3:0];

    input                   regs_pcie_perst,
    input             [7:0] regs_pcie_debug,
    input            [31:0] regs_pcie_debug_trace,

    input                   regs_xx_tick1, // 1 cycle pulse every 1 us

    //-------------------------------------------------------
    // debug
    //-------------------------------------------------------
  
    input                   regs_pcie_dbg_rd,
    input            [15:0] regs_pcie_dbg_addr,
    output           [63:0] pcie_regs_dbg_data,
    output                  pcie_regs_dbg_ack,

    //-------------------------------------------------------
    // error inject
    //-------------------------------------------------------

    input                   regs_pcie_rxcq_errinj_valid,
    input            [19:0] regs_pcie_rxcq_errinj_delay,
    output                  pcie_regs_rxcq_errinj_ack,
    output                  pcie_regs_rxcq_errinj_active,

    
    //-------------------------------------------------------
    // status
    //-------------------------------------------------------
    output                  pcie_xx_link_up,
    output                  pcie_xx_init_done,

    output           [31:0] pcie_regs_status,
    output                  pcie_regs_sisl_backpressure,
    output                  pcie_regs_rxcq_backpressure, 
    output            [7:0] pcie_sntl_rxcq_perf_events,

    output            [1:0] pcie_regs_dbg_error,
    output            [3:0] pcie_regs_rxcq_error,
     
    output                  cdc_hold_cfg_err_fatal_out,
    output                  ctlff_perror_ind, 
    output                  cdc_ctlff_perror_ind, 
    output                  rxcq_perror_ind, 
    output            [1:0] cdc_rxcq_perror_ind, 
    output                  cdc_rxrc_perror_ind, 
    output            [2:0] txcc_perror_ind, 
    output            [1:0] cdc_txcc_perror_ind, 
    output                  cdc_txrq_perror_ind,
   
    input                   regs_wdata_pe_errinj_valid,
    input                   regs_pcie_pe_errinj_valid,
    input            [15:0] regs_xxx_pe_errinj_decode ,
    input                   regs_wdata_pe_errinj_1cycle_valid 
     
    );

   localparam PL_LINK_CAP_MAX_LINK_WIDTH = 4;



   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [1:0]           cfg_current_speed;      // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 cfg_err_fatal_out;      // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 cfg_hot_reset;          // From pcie_dbg of nvme_pcie_dbg.v
   wire                 cfg_link_training_enable;// From pcie_dbg of nvme_pcie_dbg.v
   wire [5:0]           cfg_ltssm_state;        // From nvme_pcie_hip of nvme_pcie_hip.v
   wire [9:0]           cfg_mgmt_addr;          // From pcie_dbg of nvme_pcie_dbg.v
   wire [3:0]           cfg_mgmt_byte_enable;   // From pcie_dbg of nvme_pcie_dbg.v
   wire                 cfg_mgmt_read;          // From pcie_dbg of nvme_pcie_dbg.v
   wire [31:0]          cfg_mgmt_read_data;     // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 cfg_mgmt_read_write_done;// From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 cfg_mgmt_write;         // From pcie_dbg of nvme_pcie_dbg.v
   wire [31:0]          cfg_mgmt_write_data;    // From pcie_dbg of nvme_pcie_dbg.v
   wire [2:0]           cfg_negotiated_width;   // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 cfg_phy_link_down;      // From nvme_pcie_hip of nvme_pcie_hip.v
   wire [1:0]           cfg_phy_link_status;    // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 ctlff_dbg_perst;        // From pcie_ctlff of nvme_pcie_ctlff.v
   wire [63:0]          ctlff_dbg_user_trace;   // From pcie_ctlff of nvme_pcie_ctlff.v
   wire                 ctlff_rxrc_ack;         // From pcie_ctlff of nvme_pcie_ctlff.v
   wire [63:0]          ctlff_txrq_addr;        // From pcie_ctlff of nvme_pcie_ctlff.v
   wire [7:0]           ctlff_txrq_be;          // From pcie_ctlff of nvme_pcie_ctlff.v
   wire                 ctlff_txrq_cfgop;       // From pcie_ctlff of nvme_pcie_ctlff.v
   wire [63:0]          ctlff_txrq_data;        // From pcie_ctlff of nvme_pcie_ctlff.v
   wire [7:0]           ctlff_txrq_datap;       // From pcie_ctlff of nvme_pcie_ctlff.v
   wire                 ctlff_txrq_rnw;         // From pcie_ctlff of nvme_pcie_ctlff.v
   wire [5:0]           ctlff_txrq_tag;         // From pcie_ctlff of nvme_pcie_ctlff.v
   wire                 ctlff_txrq_valid;       // From pcie_ctlff of nvme_pcie_ctlff.v
   wire [127:0]         m_axis_cq_tdata;        // From nvme_pcie_hip of nvme_pcie_hip.v
   wire [3:0]           m_axis_cq_tkeep;        // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 m_axis_cq_tlast;        // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 m_axis_cq_tready;       // From pcie_rxcq of nvme_pcie_rxcq.v
   wire [AXI4_CQ_TUSER_WIDTH-1:0] m_axis_cq_tuser;// From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 m_axis_cq_tvalid;       // From nvme_pcie_hip of nvme_pcie_hip.v
   wire [127:0]         m_axis_rc_tdata;        // From nvme_pcie_hip of nvme_pcie_hip.v
   wire [3:0]           m_axis_rc_tkeep;        // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 m_axis_rc_tlast;        // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 m_axis_rc_tready;       // From pcie_rxrc of nvme_pcie_rxrc.v
   wire [AXI4_RC_TUSER_WIDTH-1:0] m_axis_rc_tuser;// From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 m_axis_rc_tvalid;       // From nvme_pcie_hip of nvme_pcie_hip.v
   wire [15:0]          rxcq_dbg_events;        // From pcie_rxcq of nvme_pcie_rxcq.v
   wire [15:0]          rxcq_dbg_user_events;   // From pcie_rxcq of nvme_pcie_rxcq.v
   wire [143:0]         rxcq_dbg_user_tracedata;// From pcie_rxcq of nvme_pcie_rxcq.v
   wire                 rxcq_dbg_user_tracevalid;// From pcie_rxcq of nvme_pcie_rxcq.v
   wire [7:0]           rxrc_ctlff_be;          // From pcie_rxrc of nvme_pcie_rxrc.v
   wire [63:0]          rxrc_ctlff_data;        // From pcie_rxrc of nvme_pcie_rxrc.v
   wire [7:0]           rxrc_ctlff_datap;       // From pcie_rxrc of nvme_pcie_rxrc.v
   wire [3:0]           rxrc_ctlff_errcode;     // From pcie_rxrc of nvme_pcie_rxrc.v
   wire                 rxrc_ctlff_poison;      // From pcie_rxrc of nvme_pcie_rxrc.v
   wire [2:0]           rxrc_ctlff_status;      // From pcie_rxrc of nvme_pcie_rxrc.v
   wire [7:0]           rxrc_ctlff_tag;         // From pcie_rxrc of nvme_pcie_rxrc.v
   wire                 rxrc_ctlff_valid;       // From pcie_rxrc of nvme_pcie_rxrc.v
   wire [143:0]         rxrc_dbg_user_tracedata;// From pcie_rxrc of nvme_pcie_rxrc.v
   wire                 rxrc_dbg_user_tracevalid;// From pcie_rxrc of nvme_pcie_rxrc.v
   wire [127:0]         s_axis_cc_tdata;        // From pcie_txcc of nvme_pcie_txcc.v
   wire [3:0]           s_axis_cc_tkeep;        // From pcie_txcc of nvme_pcie_txcc.v
   wire                 s_axis_cc_tlast;        // From pcie_txcc of nvme_pcie_txcc.v
   wire [3:0]           s_axis_cc_tready;       // From nvme_pcie_hip of nvme_pcie_hip.v
   wire [32:0]          s_axis_cc_tuser;        // From pcie_txcc of nvme_pcie_txcc.v
   wire                 s_axis_cc_tvalid;       // From pcie_txcc of nvme_pcie_txcc.v
   wire [127:0]         s_axis_rq_tdata;        // From pcie_txrq of nvme_pcie_txrq.v
   wire [3:0]           s_axis_rq_tkeep;        // From pcie_txrq of nvme_pcie_txrq.v
   wire                 s_axis_rq_tlast;        // From pcie_txrq of nvme_pcie_txrq.v
   wire [3:0]           s_axis_rq_tready;       // From nvme_pcie_hip of nvme_pcie_hip.v
   wire [61:0]          s_axis_rq_tuser;        // From pcie_txrq of nvme_pcie_txrq.v
   wire                 s_axis_rq_tvalid;       // From pcie_txrq of nvme_pcie_txrq.v
   wire                 sys_reset_n;            // From pcie_dbg of nvme_pcie_dbg.v
   wire [15:0]          txcc_dbg_events;        // From pcie_txcc of nvme_pcie_txcc.v
   wire [15:0]          txcc_dbg_user_events;   // From pcie_txcc of nvme_pcie_txcc.v
   wire [143:0]         txcc_dbg_user_tracedata;// From pcie_txcc of nvme_pcie_txcc.v
   wire                 txcc_dbg_user_tracevalid;// From pcie_txcc of nvme_pcie_txcc.v
   wire                 txrq_ctlff_ack;         // From pcie_txrq of nvme_pcie_txrq.v
   wire [143:0]         txrq_dbg_user_tracedata;// From pcie_txrq of nvme_pcie_txrq.v
   wire                 txrq_dbg_user_tracevalid;// From pcie_txrq of nvme_pcie_txrq.v
   wire                 user_clk;               // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 user_ctlff_perror_ind;  // From pcie_ctlff of nvme_pcie_ctlff.v
   wire                 user_lnk_up;            // From nvme_pcie_hip of nvme_pcie_hip.v
   wire                 user_regs_wdata_pe_errinj_valid;// From pcie_dbg of nvme_pcie_dbg.v
   wire                 user_reset;             // From nvme_pcie_hip of nvme_pcie_hip.v
   wire [1:0]           user_rxcq_perror_ind;   // From pcie_rxcq of nvme_pcie_rxcq.v
   wire                 user_rxrc_perror_ind;   // From pcie_rxrc of nvme_pcie_rxrc.v
   wire [1:0]           user_txcc_perror_ind;   // From pcie_txcc of nvme_pcie_txcc.v
   wire                 user_txrq_perror_ind;   // From pcie_txrq of nvme_pcie_txrq.v
   // End of automatics

   /*AUTOREG*/
     
   nvme_pcie_ctlff pcie_ctlff
     (/*AUTOINST*/
      // Outputs
      .pcie_ctl_ioread_data             (pcie_ctl_ioread_data[31:0]),
      .pcie_ctl_ioread_datap            (pcie_ctl_ioread_datap[3:0]),
      .pcie_ctl_ioack                   (pcie_ctl_ioack),
      .pcie_adq_wrack                   (pcie_adq_wrack),
      .pcie_ioq_wrack                   (pcie_ioq_wrack),
      .pcie_regs_ack                    (pcie_regs_ack),
      .pcie_regs_cpl_data               (pcie_regs_cpl_data[31:0]),
      .pcie_regs_cpl_datap              (pcie_regs_cpl_datap[3:0]),
      .pcie_regs_cpl_valid              (pcie_regs_cpl_valid),
      .pcie_regs_cpl_status             (pcie_regs_cpl_status[15:0]),
      .pcie_xx_link_up                  (pcie_xx_link_up),
      .pcie_xx_init_done                (pcie_xx_init_done),
      .ctlff_dbg_perst                  (ctlff_dbg_perst),
      .ctlff_txrq_valid                 (ctlff_txrq_valid),
      .ctlff_txrq_rnw                   (ctlff_txrq_rnw),
      .ctlff_txrq_cfgop                 (ctlff_txrq_cfgop),
      .ctlff_txrq_tag                   (ctlff_txrq_tag[5:0]),
      .ctlff_txrq_addr                  (ctlff_txrq_addr[63:0]),
      .ctlff_txrq_data                  (ctlff_txrq_data[63:0]),
      .ctlff_txrq_datap                 (ctlff_txrq_datap[7:0]),
      .ctlff_txrq_be                    (ctlff_txrq_be[7:0]),
      .ctlff_rxrc_ack                   (ctlff_rxrc_ack),
      .user_ctlff_perror_ind            (user_ctlff_perror_ind),
      .ctlff_perror_ind                 (ctlff_perror_ind),
      .ctlff_dbg_user_trace             (ctlff_dbg_user_trace[63:0]),
      // Inputs
      .clk                              (clk),
      .reset                            (reset),
      .ctl_pcie_ioaddress               (ctl_pcie_ioaddress[31:0]),
      .ctl_pcie_ioread_strobe           (ctl_pcie_ioread_strobe),
      .ctl_pcie_iowrite_data            (ctl_pcie_iowrite_data[31:0]),
      .ctl_pcie_iowrite_strobe          (ctl_pcie_iowrite_strobe),
      .adq_pcie_wrvalid                 (adq_pcie_wrvalid),
      .adq_pcie_wraddr                  (adq_pcie_wraddr[31:0]),
      .adq_pcie_wrdata                  (adq_pcie_wrdata[15:0]),
      .ioq_pcie_wrvalid                 (ioq_pcie_wrvalid),
      .ioq_pcie_wraddr                  (ioq_pcie_wraddr[31:0]),
      .ioq_pcie_wrdata                  (ioq_pcie_wrdata[15:0]),
      .regs_pcie_valid                  (regs_pcie_valid),
      .regs_pcie_rnw                    (regs_pcie_rnw),
      .regs_pcie_configop               (regs_pcie_configop),
      .regs_pcie_tag                    (regs_pcie_tag[3:0]),
      .regs_pcie_be                     (regs_pcie_be[3:0]),
      .regs_pcie_addr                   (regs_pcie_addr[31:0]),
      .regs_pcie_wrdata                 (regs_pcie_wrdata[31:0]),
      .regs_xx_tick1                    (regs_xx_tick1),
      .user_clk                         (user_clk),
      .user_reset                       (user_reset),
      .user_lnk_up                      (user_lnk_up),
      .txrq_ctlff_ack                   (txrq_ctlff_ack),
      .rxrc_ctlff_valid                 (rxrc_ctlff_valid),
      .rxrc_ctlff_data                  (rxrc_ctlff_data[63:0]),
      .rxrc_ctlff_datap                 (rxrc_ctlff_datap[7:0]),
      .rxrc_ctlff_be                    (rxrc_ctlff_be[7:0]),
      .rxrc_ctlff_tag                   (rxrc_ctlff_tag[7:0]),
      .rxrc_ctlff_poison                (rxrc_ctlff_poison),
      .rxrc_ctlff_errcode               (rxrc_ctlff_errcode[3:0]),
      .rxrc_ctlff_status                (rxrc_ctlff_status[2:0]),
      .regs_pcie_pe_errinj_valid        (regs_pcie_pe_errinj_valid),
      .regs_xxx_pe_errinj_decode        (regs_xxx_pe_errinj_decode[15:0]),
      .user_regs_wdata_pe_errinj_valid  (user_regs_wdata_pe_errinj_valid),
      .regs_wdata_pe_errinj_valid       (regs_wdata_pe_errinj_valid));


   nvme_pcie_txrq pcie_txrq 
     (/*AUTOINST*/
      // Outputs
      .txrq_ctlff_ack                   (txrq_ctlff_ack),
      .s_axis_rq_tdata                  (s_axis_rq_tdata[127:0]),
      .s_axis_rq_tkeep                  (s_axis_rq_tkeep[3:0]),
      .s_axis_rq_tlast                  (s_axis_rq_tlast),
      .s_axis_rq_tuser                  (s_axis_rq_tuser[61:0]),
      .s_axis_rq_tvalid                 (s_axis_rq_tvalid),
      .user_txrq_perror_ind             (user_txrq_perror_ind),
      .txrq_dbg_user_tracedata          (txrq_dbg_user_tracedata[143:0]),
      .txrq_dbg_user_tracevalid         (txrq_dbg_user_tracevalid),
      // Inputs
      .ctlff_txrq_valid                 (ctlff_txrq_valid),
      .ctlff_txrq_rnw                   (ctlff_txrq_rnw),
      .ctlff_txrq_cfgop                 (ctlff_txrq_cfgop),
      .ctlff_txrq_tag                   (ctlff_txrq_tag[5:0]),
      .ctlff_txrq_addr                  (ctlff_txrq_addr[63:0]),
      .ctlff_txrq_data                  (ctlff_txrq_data[63:0]),
      .ctlff_txrq_datap                 (ctlff_txrq_datap[7:0]),
      .ctlff_txrq_be                    (ctlff_txrq_be[7:0]),
      .user_clk                         (user_clk),
      .user_reset                       (user_reset),
      .user_lnk_up                      (user_lnk_up),
      .s_axis_rq_tready                 (s_axis_rq_tready[3:0]),
      .regs_pcie_pe_errinj_valid        (regs_pcie_pe_errinj_valid),
      .regs_xxx_pe_errinj_decode        (regs_xxx_pe_errinj_decode[15:0]),
      .user_regs_wdata_pe_errinj_valid  (user_regs_wdata_pe_errinj_valid));
   
   nvme_pcie_txcc pcie_txcc 
     (/*AUTOINST*/
      // Outputs
      .pcie_adq_cc_ready                (pcie_adq_cc_ready),
      .pcie_ioq_cc_ready                (pcie_ioq_cc_ready),
      .pcie_sntl_cc_ready               (pcie_sntl_cc_ready),
      .pcie_sntl_wbuf_cc_ready          (pcie_sntl_wbuf_cc_ready),
      .pcie_sntl_adbuf_cc_ready         (pcie_sntl_adbuf_cc_ready),
      .txcc_dbg_events                  (txcc_dbg_events[15:0]),
      .txcc_dbg_user_events             (txcc_dbg_user_events[15:0]),
      .txcc_dbg_user_tracedata          (txcc_dbg_user_tracedata[143:0]),
      .txcc_dbg_user_tracevalid         (txcc_dbg_user_tracevalid),
      .s_axis_cc_tdata                  (s_axis_cc_tdata[127:0]),
      .s_axis_cc_tkeep                  (s_axis_cc_tkeep[3:0]),
      .s_axis_cc_tlast                  (s_axis_cc_tlast),
      .s_axis_cc_tuser                  (s_axis_cc_tuser[32:0]),
      .s_axis_cc_tvalid                 (s_axis_cc_tvalid),
      .txcc_perror_ind                  (txcc_perror_ind[2:0]),
      .user_txcc_perror_ind             (user_txcc_perror_ind[1:0]),
      // Inputs
      .clk                              (clk),
      .reset                            (reset),
      .adq_pcie_cc_data                 (adq_pcie_cc_data[144:0]),
      .adq_pcie_cc_first                (adq_pcie_cc_first),
      .adq_pcie_cc_last                 (adq_pcie_cc_last),
      .adq_pcie_cc_discard              (adq_pcie_cc_discard),
      .adq_pcie_cc_valid                (adq_pcie_cc_valid),
      .ioq_pcie_cc_data                 (ioq_pcie_cc_data[144:0]),
      .ioq_pcie_cc_first                (ioq_pcie_cc_first),
      .ioq_pcie_cc_last                 (ioq_pcie_cc_last),
      .ioq_pcie_cc_discard              (ioq_pcie_cc_discard),
      .ioq_pcie_cc_valid                (ioq_pcie_cc_valid),
      .sntl_pcie_cc_data                (sntl_pcie_cc_data[144:0]),
      .sntl_pcie_cc_first               (sntl_pcie_cc_first),
      .sntl_pcie_cc_last                (sntl_pcie_cc_last),
      .sntl_pcie_cc_discard             (sntl_pcie_cc_discard),
      .sntl_pcie_cc_valid               (sntl_pcie_cc_valid),
      .sntl_pcie_wbuf_cc_data           (sntl_pcie_wbuf_cc_data[144:0]),
      .sntl_pcie_wbuf_cc_first          (sntl_pcie_wbuf_cc_first),
      .sntl_pcie_wbuf_cc_last           (sntl_pcie_wbuf_cc_last),
      .sntl_pcie_wbuf_cc_discard        (sntl_pcie_wbuf_cc_discard),
      .sntl_pcie_wbuf_cc_valid          (sntl_pcie_wbuf_cc_valid),
      .sntl_pcie_adbuf_cc_data          (sntl_pcie_adbuf_cc_data[144:0]),
      .sntl_pcie_adbuf_cc_first         (sntl_pcie_adbuf_cc_first),
      .sntl_pcie_adbuf_cc_last          (sntl_pcie_adbuf_cc_last),
      .sntl_pcie_adbuf_cc_discard       (sntl_pcie_adbuf_cc_discard),
      .sntl_pcie_adbuf_cc_valid         (sntl_pcie_adbuf_cc_valid),
      .user_clk                         (user_clk),
      .user_reset                       (user_reset),
      .user_lnk_up                      (user_lnk_up),
      .s_axis_cc_tready                 (s_axis_cc_tready[3:0]),
      .regs_pcie_pe_errinj_valid        (regs_pcie_pe_errinj_valid),
      .regs_xxx_pe_errinj_decode        (regs_xxx_pe_errinj_decode[15:0]),
      .user_regs_wdata_pe_errinj_valid  (user_regs_wdata_pe_errinj_valid),
      .regs_wdata_pe_errinj_valid       (regs_wdata_pe_errinj_valid));

   nvme_pcie_rxcq pcie_rxcq 
     (/*AUTOINST*/
      // Outputs
      .pcie_adq_valid                   (pcie_adq_valid),
      .pcie_adq_data                    (pcie_adq_data[data_width-1:0]),
      .pcie_adq_first                   (pcie_adq_first),
      .pcie_adq_last                    (pcie_adq_last),
      .pcie_adq_discard                 (pcie_adq_discard),
      .pcie_ioq_valid                   (pcie_ioq_valid),
      .pcie_ioq_data                    (pcie_ioq_data[data_width-1:0]),
      .pcie_ioq_first                   (pcie_ioq_first),
      .pcie_ioq_last                    (pcie_ioq_last),
      .pcie_ioq_discard                 (pcie_ioq_discard),
      .pcie_sntl_valid                  (pcie_sntl_valid),
      .pcie_sntl_data                   (pcie_sntl_data[data_width-1:0]),
      .pcie_sntl_first                  (pcie_sntl_first),
      .pcie_sntl_last                   (pcie_sntl_last),
      .pcie_sntl_discard                (pcie_sntl_discard),
      .pcie_sntl_wbuf_valid             (pcie_sntl_wbuf_valid),
      .pcie_sntl_wbuf_data              (pcie_sntl_wbuf_data[data_width-1:0]),
      .pcie_sntl_wbuf_first             (pcie_sntl_wbuf_first),
      .pcie_sntl_wbuf_last              (pcie_sntl_wbuf_last),
      .pcie_sntl_wbuf_discard           (pcie_sntl_wbuf_discard),
      .pcie_sntl_adbuf_valid            (pcie_sntl_adbuf_valid),
      .pcie_sntl_adbuf_data             (pcie_sntl_adbuf_data[data_width-1:0]),
      .pcie_sntl_adbuf_first            (pcie_sntl_adbuf_first),
      .pcie_sntl_adbuf_last             (pcie_sntl_adbuf_last),
      .pcie_sntl_adbuf_discard          (pcie_sntl_adbuf_discard),
      .pcie_regs_sisl_backpressure      (pcie_regs_sisl_backpressure),
      .pcie_regs_rxcq_backpressure      (pcie_regs_rxcq_backpressure),
      .pcie_regs_rxcq_error             (pcie_regs_rxcq_error[3:0]),
      .pcie_sntl_rxcq_perf_events       (pcie_sntl_rxcq_perf_events[7:0]),
      .rxcq_dbg_events                  (rxcq_dbg_events[15:0]),
      .rxcq_dbg_user_events             (rxcq_dbg_user_events[15:0]),
      .rxcq_dbg_user_tracedata          (rxcq_dbg_user_tracedata[143:0]),
      .rxcq_dbg_user_tracevalid         (rxcq_dbg_user_tracevalid),
      .pcie_regs_rxcq_errinj_ack        (pcie_regs_rxcq_errinj_ack),
      .pcie_regs_rxcq_errinj_active     (pcie_regs_rxcq_errinj_active),
      .m_axis_cq_tready                 (m_axis_cq_tready),
      .rxcq_perror_ind                  (rxcq_perror_ind),
      .user_rxcq_perror_ind             (user_rxcq_perror_ind[1:0]),
      // Inputs
      .clk                              (clk),
      .reset                            (reset),
      .adq_pcie_pause                   (adq_pcie_pause),
      .ioq_pcie_pause                   (ioq_pcie_pause),
      .sntl_pcie_pause                  (sntl_pcie_pause),
      .sntl_pcie_ready                  (sntl_pcie_ready),
      .sntl_pcie_wbuf_pause             (sntl_pcie_wbuf_pause),
      .sntl_pcie_adbuf_pause            (sntl_pcie_adbuf_pause),
      .regs_xx_tick1                    (regs_xx_tick1),
      .regs_pcie_rxcq_errinj_valid      (regs_pcie_rxcq_errinj_valid),
      .regs_pcie_rxcq_errinj_delay      (regs_pcie_rxcq_errinj_delay[19:0]),
      .user_clk                         (user_clk),
      .user_reset                       (user_reset),
      .user_lnk_up                      (user_lnk_up),
      .m_axis_cq_tdata                  (m_axis_cq_tdata[127:0]),
      .m_axis_cq_tkeep                  (m_axis_cq_tkeep[3:0]),
      .m_axis_cq_tlast                  (m_axis_cq_tlast),
      .m_axis_cq_tuser                  (m_axis_cq_tuser[87:0]),
      .m_axis_cq_tvalid                 (m_axis_cq_tvalid),
      .regs_pcie_pe_errinj_valid        (regs_pcie_pe_errinj_valid),
      .regs_xxx_pe_errinj_decode        (regs_xxx_pe_errinj_decode[15:0]),
      .user_regs_wdata_pe_errinj_valid  (user_regs_wdata_pe_errinj_valid),
      .regs_wdata_pe_errinj_valid       (regs_wdata_pe_errinj_valid));
   
   nvme_pcie_rxrc pcie_rxrc 
     (/*AUTOINST*/
      // Outputs
      .rxrc_ctlff_valid                 (rxrc_ctlff_valid),
      .rxrc_ctlff_data                  (rxrc_ctlff_data[63:0]),
      .rxrc_ctlff_datap                 (rxrc_ctlff_datap[7:0]),
      .rxrc_ctlff_be                    (rxrc_ctlff_be[7:0]),
      .rxrc_ctlff_tag                   (rxrc_ctlff_tag[7:0]),
      .rxrc_ctlff_poison                (rxrc_ctlff_poison),
      .rxrc_ctlff_errcode               (rxrc_ctlff_errcode[3:0]),
      .rxrc_ctlff_status                (rxrc_ctlff_status[2:0]),
      .m_axis_rc_tready                 (m_axis_rc_tready),
      .user_rxrc_perror_ind             (user_rxrc_perror_ind),
      .rxrc_dbg_user_tracedata          (rxrc_dbg_user_tracedata[143:0]),
      .rxrc_dbg_user_tracevalid         (rxrc_dbg_user_tracevalid),
      // Inputs
      .ctlff_rxrc_ack                   (ctlff_rxrc_ack),
      .user_clk                         (user_clk),
      .user_reset                       (user_reset),
      .user_lnk_up                      (user_lnk_up),
      .m_axis_rc_tdata                  (m_axis_rc_tdata[127:0]),
      .m_axis_rc_tkeep                  (m_axis_rc_tkeep[3:0]),
      .m_axis_rc_tlast                  (m_axis_rc_tlast),
      .m_axis_rc_tuser                  (m_axis_rc_tuser[74:0]),
      .m_axis_rc_tvalid                 (m_axis_rc_tvalid),
      .regs_pcie_pe_errinj_valid        (regs_pcie_pe_errinj_valid),
      .regs_xxx_pe_errinj_decode        (regs_xxx_pe_errinj_decode[15:0]),
      .user_regs_wdata_pe_errinj_valid  (user_regs_wdata_pe_errinj_valid));

        
   nvme_pcie_hip# 
     (
      .port_id(port_id)
      ) nvme_pcie_hip 
       (/*AUTOINST*/
        // Outputs
        .pci_exp_txp                    (pci_exp_txp[PL_LINK_CAP_MAX_LINK_WIDTH-1:0]),
        .pci_exp_txn                    (pci_exp_txn[PL_LINK_CAP_MAX_LINK_WIDTH-1:0]),
        .user_clk                       (user_clk),
        .user_reset                     (user_reset),
        .user_lnk_up                    (user_lnk_up),
        .cfg_phy_link_down              (cfg_phy_link_down),
        .cfg_phy_link_status            (cfg_phy_link_status[1:0]),
        .cfg_negotiated_width           (cfg_negotiated_width[2:0]),
        .cfg_current_speed              (cfg_current_speed[1:0]),
        .cfg_ltssm_state                (cfg_ltssm_state[5:0]),
        .cfg_err_fatal_out              (cfg_err_fatal_out),
        .cfg_mgmt_read_data             (cfg_mgmt_read_data[31:0]),
        .cfg_mgmt_read_write_done       (cfg_mgmt_read_write_done),
        .s_axis_rq_tready               (s_axis_rq_tready[3:0]),
        .m_axis_rc_tdata                (m_axis_rc_tdata[127:0]),
        .m_axis_rc_tkeep                (m_axis_rc_tkeep[3:0]),
        .m_axis_rc_tlast                (m_axis_rc_tlast),
        .m_axis_rc_tuser                (m_axis_rc_tuser[AXI4_RC_TUSER_WIDTH-1:0]),
        .m_axis_rc_tvalid               (m_axis_rc_tvalid),
        .m_axis_cq_tdata                (m_axis_cq_tdata[127:0]),
        .m_axis_cq_tkeep                (m_axis_cq_tkeep[3:0]),
        .m_axis_cq_tlast                (m_axis_cq_tlast),
        .m_axis_cq_tuser                (m_axis_cq_tuser[AXI4_CQ_TUSER_WIDTH-1:0]),
        .m_axis_cq_tvalid               (m_axis_cq_tvalid),
        .s_axis_cc_tready               (s_axis_cc_tready[3:0]),
        // Inputs
        .pci_exp_rxp                    (pci_exp_rxp[PL_LINK_CAP_MAX_LINK_WIDTH-1:0]),
        .pci_exp_rxn                    (pci_exp_rxn[PL_LINK_CAP_MAX_LINK_WIDTH-1:0]),
        .pci_exp_refclk_p               (pci_exp_refclk_p),
        .pci_exp_refclk_n               (pci_exp_refclk_n),
        .sys_reset_n                    (sys_reset_n),
        .cfg_hot_reset                  (cfg_hot_reset),
        .cfg_link_training_enable       (cfg_link_training_enable),
        .cfg_mgmt_addr                  (cfg_mgmt_addr[9:0]),
        .cfg_mgmt_write                 (cfg_mgmt_write),
        .cfg_mgmt_write_data            (cfg_mgmt_write_data[31:0]),
        .cfg_mgmt_byte_enable           (cfg_mgmt_byte_enable[3:0]),
        .cfg_mgmt_read                  (cfg_mgmt_read),
        .s_axis_rq_tdata                (s_axis_rq_tdata[127:0]),
        .s_axis_rq_tkeep                (s_axis_rq_tkeep[3:0]),
        .s_axis_rq_tlast                (s_axis_rq_tlast),
        .s_axis_rq_tuser                (s_axis_rq_tuser[AXI4_RQ_TUSER_WIDTH-1:0]),
        .s_axis_rq_tvalid               (s_axis_rq_tvalid),
        .m_axis_rc_tready               (m_axis_rc_tready),
        .m_axis_cq_tready               (m_axis_cq_tready),
        .s_axis_cc_tdata                (s_axis_cc_tdata[127:0]),
        .s_axis_cc_tkeep                (s_axis_cc_tkeep[3:0]),
        .s_axis_cc_tlast                (s_axis_cc_tlast),
        .s_axis_cc_tuser                (s_axis_cc_tuser[AXI4_CC_TUSER_WIDTH-1:0]),
        .s_axis_cc_tvalid               (s_axis_cc_tvalid));

           
   nvme_pcie_dbg  pcie_dbg 
       (/*AUTOINST*/
        // Outputs
        .pcie_regs_status               (pcie_regs_status[31:0]),
        .pci_exp_nperst                 (pci_exp_nperst),
        .sys_reset_n                    (sys_reset_n),
        .cfg_hot_reset                  (cfg_hot_reset),
        .cfg_link_training_enable       (cfg_link_training_enable),
        .cfg_mgmt_addr                  (cfg_mgmt_addr[9:0]),
        .cfg_mgmt_write                 (cfg_mgmt_write),
        .cfg_mgmt_write_data            (cfg_mgmt_write_data[31:0]),
        .cfg_mgmt_byte_enable           (cfg_mgmt_byte_enable[3:0]),
        .cfg_mgmt_read                  (cfg_mgmt_read),
        .user_regs_wdata_pe_errinj_valid(user_regs_wdata_pe_errinj_valid),
        .cdc_rxcq_perror_ind            (cdc_rxcq_perror_ind[1:0]),
        .cdc_rxrc_perror_ind            (cdc_rxrc_perror_ind),
        .cdc_txcc_perror_ind            (cdc_txcc_perror_ind[1:0]),
        .cdc_txrq_perror_ind            (cdc_txrq_perror_ind),
        .cdc_ctlff_perror_ind           (cdc_ctlff_perror_ind),
        .cdc_hold_cfg_err_fatal_out     (cdc_hold_cfg_err_fatal_out),
        .pcie_regs_dbg_data             (pcie_regs_dbg_data[63:0]),
        .pcie_regs_dbg_ack              (pcie_regs_dbg_ack),
        .pcie_regs_dbg_error            (pcie_regs_dbg_error[1:0]),
        // Inputs
        .clk                            (clk),
        .reset                          (reset),
        .regs_pcie_debug                (regs_pcie_debug[7:0]),
        .regs_pcie_debug_trace          (regs_pcie_debug_trace[31:0]),
        .regs_pcie_perst                (regs_pcie_perst),
        .ctlff_dbg_perst                (ctlff_dbg_perst),
        .user_clk                       (user_clk),
        .user_reset                     (user_reset),
        .user_lnk_up                    (user_lnk_up),
        .cfg_phy_link_down              (cfg_phy_link_down),
        .cfg_phy_link_status            (cfg_phy_link_status[1:0]),
        .cfg_negotiated_width           (cfg_negotiated_width[2:0]),
        .cfg_current_speed              (cfg_current_speed[1:0]),
        .cfg_ltssm_state                (cfg_ltssm_state[5:0]),
        .cfg_err_fatal_out              (cfg_err_fatal_out),
        .cfg_mgmt_read_data             (cfg_mgmt_read_data[31:0]),
        .cfg_mgmt_read_write_done       (cfg_mgmt_read_write_done),
        .regs_wdata_pe_errinj_valid     (regs_wdata_pe_errinj_valid),
        .user_rxcq_perror_ind           (user_rxcq_perror_ind[1:0]),
        .user_rxrc_perror_ind           (user_rxrc_perror_ind),
        .user_txcc_perror_ind           (user_txcc_perror_ind[1:0]),
        .user_txrq_perror_ind           (user_txrq_perror_ind),
        .user_ctlff_perror_ind          (user_ctlff_perror_ind),
        .regs_pcie_dbg_rd               (regs_pcie_dbg_rd),
        .regs_pcie_dbg_addr             (regs_pcie_dbg_addr[15:0]),
        .rxcq_dbg_events                (rxcq_dbg_events[15:0]),
        .rxcq_dbg_user_events           (rxcq_dbg_user_events[15:0]),
        .rxcq_dbg_user_tracedata        (rxcq_dbg_user_tracedata[143:0]),
        .rxcq_dbg_user_tracevalid       (rxcq_dbg_user_tracevalid),
        .txcc_dbg_events                (txcc_dbg_events[15:0]),
        .txcc_dbg_user_events           (txcc_dbg_user_events[15:0]),
        .txcc_dbg_user_tracedata        (txcc_dbg_user_tracedata[143:0]),
        .txcc_dbg_user_tracevalid       (txcc_dbg_user_tracevalid),
        .ctlff_dbg_user_trace           (ctlff_dbg_user_trace[63:0]),
        .rxrc_dbg_user_tracedata        (rxrc_dbg_user_tracedata[143:0]),
        .rxrc_dbg_user_tracevalid       (rxrc_dbg_user_tracevalid),
        .txrq_dbg_user_tracedata        (txrq_dbg_user_tracedata[143:0]),
        .txrq_dbg_user_tracevalid       (txrq_dbg_user_tracevalid));
   
endmodule


