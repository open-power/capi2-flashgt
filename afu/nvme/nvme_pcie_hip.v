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
(* DowngradeIPIdentifiedWarnings = "yes" *)
module nvme_pcie_hip
  #(
     
     parameter [2:0] PL_LINK_CAP_MAX_LINK_SPEED            = 3'h4,  // 1- GEN1, 2 - GEN2, 4 - GEN3
     parameter [4:0] PL_LINK_CAP_MAX_LINK_WIDTH            = 5'h4,  // 1- X1, 2 - X2, 4 - X4, 8 - X8
    
 //  USER_CLK[1/2]_FREQ :[0] = Disable user clock;  [1] =  31.25 MHz;  [2] =  62.50 MHz (default);  [3] = 125.00 MHz;  [4] = 250.00 MHz;  [5] = 500.00 MHz;
     parameter  integer USER_CLK2_FREQ                     = 4,
    
     parameter       REF_CLK_FREQ                          = 0,           // 0 - 100 MHz, 1 - 125 MHz,  2 - 250 MHz
     parameter       C_DATA_WIDTH                          = 64,
     parameter       KEEP_WIDTH                            = C_DATA_WIDTH / 32,
     parameter       AXI4_CQ_TUSER_WIDTH                   = 88,
     parameter       AXI4_CC_TUSER_WIDTH                   = 33,
     parameter       AXI4_RQ_TUSER_WIDTH                   = 62,
     parameter       AXI4_RC_TUSER_WIDTH                   = 75,
     parameter port_id = 0
 
  )
  ( 

    //-------------------------------------------------------
    // PCI Express (pci_exp) Interface
    //-------------------------------------------------------
    output [PL_LINK_CAP_MAX_LINK_WIDTH-1:0] pci_exp_txp,
    output [PL_LINK_CAP_MAX_LINK_WIDTH-1:0] pci_exp_txn,
    input  [PL_LINK_CAP_MAX_LINK_WIDTH-1:0] pci_exp_rxp,
    input  [PL_LINK_CAP_MAX_LINK_WIDTH-1:0] pci_exp_rxn,
    
    input                                   pci_exp_refclk_p,
    input                                   pci_exp_refclk_n,

    //-------------------------------------------------------    
    output                                  user_clk,
    output                                  user_reset,
    output                                  user_lnk_up,

    input                                   sys_reset_n, // PERST to core

    //-------------------------------------------------------
    // Configuration/Status interfaces
    //-------------------------------------------------------

    output                                  cfg_phy_link_down,
    output                            [1:0] cfg_phy_link_status,
    output                            [2:0] cfg_negotiated_width,
    output                            [1:0] cfg_current_speed, 
    output                            [5:0] cfg_ltssm_state,
    output                                  cfg_err_fatal_out,
  
    input                                   cfg_hot_reset, 
    input                                   cfg_link_training_enable,

    //-------------------------------------------------------
    // Management Interface
    //-------------------------------------------------------
    input                             [9:0] cfg_mgmt_addr,
    input                                   cfg_mgmt_write,
    input                            [31:0] cfg_mgmt_write_data,
    input                             [3:0] cfg_mgmt_byte_enable,
    input                                   cfg_mgmt_read,
    output                           [31:0] cfg_mgmt_read_data,
    output                                  cfg_mgmt_read_write_done,
    
    //-------------------------------------------------------
    //  Transaction (AXIS) Interface
    //-------------------------------------------------------    
  
    input                           [127:0] s_axis_rq_tdata,
    input                             [3:0] s_axis_rq_tkeep,
    input                                   s_axis_rq_tlast,
    output                            [3:0] s_axis_rq_tready,
    input         [AXI4_RQ_TUSER_WIDTH-1:0] s_axis_rq_tuser,
    input                                   s_axis_rq_tvalid,
    //-------------------------------------------------------    
    
    output                          [127:0] m_axis_rc_tdata,
    output                            [3:0] m_axis_rc_tkeep,
    output                                  m_axis_rc_tlast,
    input                                   m_axis_rc_tready,
    output        [AXI4_RC_TUSER_WIDTH-1:0] m_axis_rc_tuser,
    output                                  m_axis_rc_tvalid,
    //-------------------------------------------------------    
  
    output                          [127:0] m_axis_cq_tdata,
    output                            [3:0] m_axis_cq_tkeep,
    output                                  m_axis_cq_tlast,
    input                                   m_axis_cq_tready,
    output        [AXI4_CQ_TUSER_WIDTH-1:0] m_axis_cq_tuser,
    output                                  m_axis_cq_tvalid,
    //-------------------------------------------------------     
    input                           [127:0] s_axis_cc_tdata,
    input                             [3:0] s_axis_cc_tkeep,
    input                                   s_axis_cc_tlast,
    output                            [3:0] s_axis_cc_tready,
    input         [AXI4_CC_TUSER_WIDTH-1:0] s_axis_cc_tuser,
    input                                   s_axis_cc_tvalid
    //-------------------------------------------------------    


);


  // based on example design - xilinx_pcie4_uscale_rp.v
  //-------------------------------------------------------
  // 3. Configuration (CFG) Interface - EP and RP
  //-------------------------------------------------------
  wire                             [3:0]     pcie_tfc_nph_av;
  wire                             [3:0]     pcie_tfc_npd_av;
	  
  reg                                  [1:0] pcie_cq_np_req;
  wire                              [5:0]    pcie_cq_np_req_count;
  //wire                                       cfg_phy_link_down;
  //wire                              [1:0]    cfg_phy_link_status;
  //wire                              [2:0]    cfg_negotiated_width;
  //wire                              [1:0]    cfg_current_speed;
  wire                              [1:0]    cfg_max_payload;
  wire                              [2:0]    cfg_max_read_req;
  wire                             [15:0]    cfg_function_status;
  wire                             [11:0]    cfg_function_power_state;
  wire                            [503:0]    cfg_vf_status;
  wire                            [755:0]    cfg_vf_power_state;
  wire                              [1:0]    cfg_link_power_state;

  //-------------------------------------------------------
  // Error Reporting Interface
  //-------------------------------------------------------
  wire                                       cfg_err_cor_out;
  wire                                       cfg_err_nonfatal_out;
  //wire                                       cfg_err_fatal_out;

  //wire                              [5:0]    cfg_ltssm_state;
  wire                              [3:0]    cfg_rcb_status;
  wire                              [1:0]    cfg_obff_enable;
  wire                                       cfg_pl_status_change;

  wire                              [3:0]    cfg_tph_requester_enable;
  wire                             [11:0]    cfg_tph_st_mode;
  wire                            [251:0]    cfg_vf_tph_requester_enable;
  wire                            [755:0]    cfg_vf_tph_st_mode;
  
  //-------------------------------------------------------
  // Management Interface
  //-------------------------------------------------------
  //reg                              [9:0]    cfg_mgmt_addr;
  //reg                                       cfg_mgmt_write;
  //reg                             [31:0]    cfg_mgmt_write_data;
  //reg                              [3:0]    cfg_mgmt_byte_enable;
  //reg                                       cfg_mgmt_read;
  //wire                             [31:0]   cfg_mgmt_read_data;
  //wire                                      cfg_mgmt_read_write_done;

  wire                                       cfg_msg_received;
  wire                              [7:0]    cfg_msg_received_data;
  wire                              [4:0]    cfg_msg_received_type;

  reg                                        cfg_msg_transmit;
  reg                              [2:0]     cfg_msg_transmit_type;
  reg                             [31:0]     cfg_msg_transmit_data;
  wire                                       cfg_msg_transmit_done;

  wire                              [7:0]    cfg_fc_ph;
  wire                             [11:0]    cfg_fc_pd;
  wire                              [7:0]    cfg_fc_nph;
  wire                             [11:0]    cfg_fc_npd;
  wire                              [7:0]    cfg_fc_cplh;
  wire                             [11:0]    cfg_fc_cpld;
  reg                               [2:0]    cfg_fc_sel;

  reg                               [2:0]    cfg_per_func_status_control;
  // EP only
  wire                                       cfg_hot_reset_out;
  reg                                        cfg_config_space_enable;
  reg                                        cfg_req_pm_transition_l23_ready;

  // RP only
  wire                                        cfg_hot_reset_in;

  reg                               [7:0]    cfg_ds_port_number;
  reg                               [7:0]    cfg_ds_bus_number;
  reg                               [4:0]    cfg_ds_device_number;
  
  reg                               [2:0]    cfg_per_function_number;
  reg                                        cfg_per_function_output_request;

  reg                              [63:0]    cfg_dsn;
  reg                                        cfg_power_state_change_ack;
  wire                                       cfg_power_state_change_interrupt;
  reg                                        cfg_err_cor_in;
  reg                                        cfg_err_uncor_in;  

  wire                              [3:0]    cfg_flr_in_process;
  reg                               [1:0]    cfg_flr_done;
  wire                            [251:0]    cfg_vf_flr_in_process;
  reg                               [0:0]    cfg_vf_flr_done;

  //reg                                        cfg_link_training_enable;
  wire                                       cfg_ext_read_received;
  wire                                       cfg_ext_write_received;
  wire                              [9:0]    cfg_ext_register_number;
  wire                              [7:0]    cfg_ext_function_number;
  wire                             [31:0]    cfg_ext_write_data;
  wire                              [3:0]    cfg_ext_write_byte_enable;
  reg                              [31:0]    cfg_ext_read_data;
  reg                                        cfg_ext_read_data_valid;

  //----------------------------------------------------------------------------------------------------------------//
  // EP Only   -    Interrupt Interface Signals                                                                     //
  //----------------------------------------------------------------------------------------------------------------//
  reg                               [3:0]    cfg_interrupt_int;
  reg                               [1:0]    cfg_interrupt_pending;
  wire                                       cfg_interrupt_sent;

  wire                              [3:0]    cfg_interrupt_msi_enable;
  wire                             [11:0]    cfg_interrupt_msi_mmenable;
  wire                                       cfg_interrupt_msi_mask_update;
  wire                             [31:0]    cfg_interrupt_msi_data;
  reg                               [1:0]    cfg_interrupt_msi_select;
  reg                              [31:0]    cfg_interrupt_msi_int;
  reg                              [63:0]    cfg_interrupt_msi_pending_status;
  wire                                       cfg_interrupt_msi_sent;
  wire                                       cfg_interrupt_msi_fail;
  reg                                        cfg_interrupt_msi_pending_status_data_enable;
  reg                               [3:0]    cfg_interrupt_msi_pending_status_function_num;
  reg                               [2:0]    cfg_interrupt_msi_attr;
  reg                                        cfg_interrupt_msi_tph_present;
  reg                               [1:0]    cfg_interrupt_msi_tph_type;
  reg                               [7:0]    cfg_interrupt_msi_tph_st_tag;
  reg                               [2:0]    cfg_interrupt_msi_function_number;
  //-------------------------------------------------------



   wire                              [25:0] common_commands_in;
   wire                              [83:0] pipe_rx_0_sigs;
   wire                              [83:0] pipe_rx_1_sigs;
   wire                              [83:0] pipe_rx_2_sigs;
   wire                              [83:0] pipe_rx_3_sigs;
   wire                              [83:0] pipe_rx_4_sigs;
   wire                              [83:0] pipe_rx_5_sigs;
   wire                              [83:0] pipe_rx_6_sigs;
   wire                              [83:0] pipe_rx_7_sigs;
   wire                              [83:0] pipe_rx_8_sigs;
   wire                              [83:0] pipe_rx_9_sigs;
   wire                              [83:0] pipe_rx_10_sigs;
   wire                              [83:0] pipe_rx_11_sigs;
   wire                              [83:0] pipe_rx_12_sigs;
   wire                              [83:0] pipe_rx_13_sigs;
   wire                              [83:0] pipe_rx_14_sigs;
   wire                              [83:0] pipe_rx_15_sigs;
   
   wire                              [25:0] common_commands_out;
   wire                              [83:0] pipe_tx_0_sigs;
   wire                              [83:0] pipe_tx_1_sigs;
   wire                              [83:0] pipe_tx_2_sigs;
   wire                              [83:0] pipe_tx_3_sigs;
   wire                              [83:0] pipe_tx_4_sigs;
   wire                              [83:0] pipe_tx_5_sigs;
   wire                              [83:0] pipe_tx_6_sigs;
   wire                              [83:0] pipe_tx_7_sigs;
   wire                              [83:0] pipe_tx_8_sigs;
   wire                              [83:0] pipe_tx_9_sigs;
   wire                              [83:0] pipe_tx_10_sigs;
   wire                              [83:0] pipe_tx_11_sigs;
   wire                              [83:0] pipe_tx_12_sigs;
   wire                              [83:0] pipe_tx_13_sigs;
   wire                              [83:0] pipe_tx_14_sigs;
   wire                              [83:0] pipe_tx_15_sigs;


   wire                               [4:0] cfg_local_error;

   wire                               [5:0] pcie_rq_seq_num0;
   wire                                     pcie_rq_seq_num_vld0;
   wire                               [5:0] pcie_rq_seq_num1;
   wire                                     pcie_rq_seq_num_vld1;
   wire                               [7:0] pcie_rq_tag0;
   wire                                     pcie_rq_tag_vld0;
   wire                               [7:0] pcie_rq_tag1;
   wire                                     pcie_rq_tag_vld1;
   wire                               [3:0] pcie_rq_tag_av;

   wire                                     user_reset_out;
   wire                                     user_clk_out;
   
  reg [15:0]  cfg_vend_id        = 16'h10EE;   
  reg [15:0]  cfg_dev_id_pf0     = 16'h9134;   
  reg [15:0]  cfg_subsys_id_pf0  = 16'h04dd;                                
  reg [7:0]   cfg_rev_id_pf0     = 8'h00; 
  reg [15:0]  cfg_subsys_vend_id = 16'h10EE;


   assign cfg_hot_reset_in = cfg_hot_reset;
   assign user_clk = user_clk_out;
   assign user_reset = user_reset_out;
   
   //---------- Internal GT COMMON Ports ----------------------
   wire [((PL_LINK_CAP_MAX_LINK_WIDTH-1)>>2):0] int_qpll0lock_out;   
   wire [((PL_LINK_CAP_MAX_LINK_WIDTH-1)>>2):0] int_qpll0outrefclk_out;
   wire [((PL_LINK_CAP_MAX_LINK_WIDTH-1)>>2):0] int_qpll0outclk_out;
   wire [((PL_LINK_CAP_MAX_LINK_WIDTH-1)>>2):0] int_qpll1lock_out;   
   wire [((PL_LINK_CAP_MAX_LINK_WIDTH-1)>>2):0] int_qpll1outrefclk_out;
   wire [((PL_LINK_CAP_MAX_LINK_WIDTH-1)>>2):0] int_qpll1outclk_out;

   localparam integer USER_CLK_FREQ = ((PL_LINK_CAP_MAX_LINK_SPEED == 3'h4) ? 5 : 4);


   //--------------------------------------------------------------------------------------------------------------------//
   // differential clock buffer
   //--------------------------------------------------------------------------------------------------------------------//

   wire               sys_clk_gt;
   wire               sys_clk;

   // Refer to Transceiver User Guide UG576 Table 2.2
   IBUFDS_GTE4 #(
                 .REFCLK_EN_TX_PATH(1'b0),   // reserved must be 1'b0
                 .REFCLK_HROW_CK_SEL(2'b00), // 2'b00 == ODIV2 = O (sys_clk and sys_clk_gt are same frequency)
                 .REFCLK_ICNTL_RX(2'b00)     // reserved
   ) IBUFDS_GTE4_inst (  
      .O     (sys_clk_gt),
      .ODIV2 (sys_clk),
      .CEB   (1'b0),
      .I     (pci_exp_refclk_p),
      .IB    (pci_exp_refclk_n) 
   );

  //--------------------------------------------------------------------------------------------------------------------//
  // make sure the timing of reset removal is ok
  // transfer reset to pcie clock

   wire               sys_clk_hip;
   BUFG_GT bufg_gt_sysclk (.CE (1'd1), .CEMASK (1'd0), .CLR (1'd0), .CLRMASK (1'd0), .DIV (3'd0), .I (sys_clk), .O (sys_clk_hip));

   wire               sys_reset_n_int;
   nvme_cdc cdc_sys_reset (.clk(sys_clk_hip),.d(sys_reset_n),.q(sys_reset_n_int));

  //--------------------------------------------------------------------------------------------------------------------//
  // Instantiate Root Port wrapper
  //--------------------------------------------------------------------------------------------------------------------//

`ifdef SIM
     wire   [3:0] cfg_negotiated_width_int;
     wire   [2:0] cfg_current_speed_int; 
     wire   [2:0] cfg_max_payload_int;
`endif
   
generate 
if(port_id==0) begin : port0
  // Core Top Level Wrapper
  `ifdef SIM
     // defparam pcie4_uscale_plus_x1y1x4.inst.EXT_PIPE_SIM = "TRUE";
     // defparam pcie4_uscale_plus_x1y1x4.inst.PL_DISABLE_DC_BALANCE = "TRUE";
     // defparam pcie4_uscale_plus_x1y1x4.inst.PL_SIM_FAST_LINK_TRAINING=2'h3;
     // --defparam pcie4_uscale_plus_x1y1x4.inst.PL_EQ_BYPASS_PHASE23 = 2'b01;
     defparam pcie3_sim_x1y1.inst.EXT_PIPE_SIM = "TRUE";
     defparam pcie3_sim_x1y1.inst.PL_DISABLE_GEN3_DC_BALANCE = "TRUE";

      pcie3_ultrascale_x0y1x4 pcie3_sim_x1y1 (
        `include "nvme_pcie_hip_sim.vh"
     );                                                 

  `else
      pcie4_uscale_plus_x1y1  pcie4_uscale_plus_x1y1x4 (
         `include "nvme_pcie_hip.vh"                                   
      );
  `endif        
end // block: port0

if(port_id==1) begin : port1
  // Core Top Level Wrapper
  `ifdef SIM
     defparam pcie3_sim_x1y2.inst.EXT_PIPE_SIM = "TRUE";
     defparam pcie3_sim_x1y2.inst.PL_DISABLE_GEN3_DC_BALANCE = "TRUE";

       pcie3_ultrascale_x0y1x4 pcie3_sim_x1y2 (
        `include "nvme_pcie_hip_sim.vh"
     );                                                 

  `else
     pcie4_uscale_plus_x1y2  pcie4_uscale_plus_x1y2x4 (                                                  
        `include "nvme_pcie_hip.vh"                                                   
     );
  `endif
end // block: port1

if(port_id==2) begin : port2
  // Core Top Level Wrapper
  `ifdef SIM
     defparam pcie3_sim_x0y2.inst.EXT_PIPE_SIM = "TRUE";
     defparam pcie3_sim_x0y2.inst.PL_DISABLE_GEN3_DC_BALANCE = "TRUE";
       pcie3_ultrascale_x0y1x4 pcie3_sim_x0y2 (
        `include "nvme_pcie_hip_sim.vh"
     );                                                 
  `else
      pcie4_uscale_plus_x0y2  pcie4_uscale_plus_x0y2x4 (
        `include "nvme_pcie_hip.vh"
      );
  `endif
end // block: port2

if(port_id==3) begin : port3
  // Core Top Level Wrapper
  `ifdef SIM
     defparam pcie3_sim_x0y3.inst.EXT_PIPE_SIM = "TRUE";
     defparam pcie3_sim_x0y3.inst.PL_DISABLE_GEN3_DC_BALANCE = "TRUE";
       pcie3_ultrascale_x0y1x4 pcie3_sim_x0y3 (
        `include "nvme_pcie_hip_sim.vh"
     );                                                 
  `else
      pcie4_uscale_plus_x0y3  pcie4_uscale_plus_x0y3x4 (
        `include "nvme_pcie_hip.vh"                                               
      );
  `endif
end // block: port3
endgenerate


 
`ifndef SIM
   assign common_commands_in = 0;
   assign pipe_rx_0_sigs  = 84'h0;
   assign pipe_rx_1_sigs  = 84'h0;
   assign pipe_rx_2_sigs  = 84'h0;
   assign pipe_rx_3_sigs  = 84'h0;
   assign pipe_rx_4_sigs  = 84'h0;
   assign pipe_rx_5_sigs  = 84'h0;
   assign pipe_rx_6_sigs  = 84'h0;
   assign pipe_rx_7_sigs  = 84'h0;
             
`endif


  //--------------------------------------------------------------------------------------------------------------------//
  // Configuration signals which are unused
  //--------------------------------------------------------------------------------------------------------------------//
   initial begin     
      cfg_vend_id                                    = 16'h1014;   
      cfg_dev_id_pf0                                 = 16'h0000;   
      cfg_subsys_id_pf0                              = 16'h04dd;                                
      cfg_rev_id_pf0                                 = 8'h01; 
      cfg_subsys_vend_id                             = 16'h1014;

      
      cfg_msg_transmit                              <= 0 ;// 
      cfg_msg_transmit_type                         <= 0 ;//[2:0]
      cfg_msg_transmit_data                         <= 0 ;//[31:0]  
      cfg_fc_sel                                    <= 0 ;//[2:0]     
      cfg_per_func_status_control                   <= 0 ;//[2:0] 
      pcie_cq_np_req                                <= 2'b11;// 
      cfg_config_space_enable                       <= 1'b1 ;//    
      cfg_req_pm_transition_l23_ready               <= 0 ;//                                   
     // cfg_hot_reset_in                            <= 0 ;//        
      cfg_ds_bus_number                             <= 8'h45 ;//[7:0]
      cfg_ds_device_number                          <= 4'b0001 ;//[4:0]        
      cfg_ds_port_number                            <= 8'h01 ;//[7:0]           
      cfg_per_function_number                       <= 0 ;//[2:0]     
      cfg_per_function_output_request               <= 0 ;//      
      cfg_dsn                                       <= 64'h78EE32BAD28F906B ;//[63:0]       
      cfg_power_state_change_ack                    <= 0 ;//    
      cfg_err_cor_in                                <= 0 ;
      cfg_err_uncor_in                              <= 0 ;//     
      cfg_flr_done                                  <= 0 ;//[1:0]
      cfg_vf_flr_done                               <= 0 ;//[5:0]    
     // cfg_link_training_enable                    <= 1 ;// 
      cfg_ext_read_data                             <= 32'hA234567B ;//[31:0]
      cfg_ext_read_data_valid                       <= 0 ;//
     // Interrupt Interface Signals
      cfg_interrupt_int                             <= 0 ;//[3:0]  
      cfg_interrupt_pending                         <= 0 ;//[1:0]      
     
      cfg_interrupt_msi_select                      <= 0 ;//[3:0]        
      cfg_interrupt_msi_int                         <= 0 ;//[31:0]  
      cfg_interrupt_msi_pending_status              <= 0 ;//[63:0]  
      cfg_interrupt_msi_attr                        <= 0 ;//[2:0] 
      cfg_interrupt_msi_tph_present                 <= 0 ;//        
      cfg_interrupt_msi_tph_type                    <= 0 ;//[1:0]       
      cfg_interrupt_msi_tph_st_tag                  <= 0 ;//[8:0]        
      cfg_interrupt_msi_function_number             <= 0 ;//[2:0]            
      cfg_interrupt_msi_pending_status_data_enable  <= 0 ;//  
      cfg_interrupt_msi_pending_status_function_num <= 0 ;//[3:0]  
 
   end
  //--------------------------------------------------------------------------------------------------------------------//


   
 
endmodule

