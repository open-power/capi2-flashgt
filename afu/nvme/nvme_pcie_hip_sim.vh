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


// pcie IP instance I/O binding - 
    .cfg_subsys_vend_id                             ( cfg_subsys_vend_id ),

    //---------------------------------------------------------------------------------------//
    //  PCI Express (pci_exp) Interface                                                      //
    //---------------------------------------------------------------------------------------//

    // Tx
    .pci_exp_txn                                    ( pci_exp_txn ),
    .pci_exp_txp                                    ( pci_exp_txp ),

    // Rx
    .pci_exp_rxn                                    ( pci_exp_rxn ),
    .pci_exp_rxp                                    ( pci_exp_rxp ),


    //---------------------------------------------------------------------------------------//
    //  AXI Interface                                                                        //
    //---------------------------------------------------------------------------------------//

    .user_clk                                       ( user_clk_out ),
    .user_reset                                     ( user_reset_out ),
    .user_lnk_up                                    ( user_lnk_up ),

    .s_axis_rq_tlast                                ( s_axis_rq_tlast ),
    .s_axis_rq_tdata                                ( s_axis_rq_tdata ),
    .s_axis_rq_tuser                                ( s_axis_rq_tuser[59:0] ),
    .s_axis_rq_tkeep                                ( s_axis_rq_tkeep ),
    .s_axis_rq_tready                               ( s_axis_rq_tready ),
    .s_axis_rq_tvalid                               ( s_axis_rq_tvalid ),

    .m_axis_rc_tdata                                ( m_axis_rc_tdata ),
    .m_axis_rc_tuser                                ( m_axis_rc_tuser ),
    .m_axis_rc_tlast                                ( m_axis_rc_tlast ),
    .m_axis_rc_tkeep                                ( m_axis_rc_tkeep ),
    .m_axis_rc_tvalid                               ( m_axis_rc_tvalid ),
    .m_axis_rc_tready                               ( m_axis_rc_tready ),

    .m_axis_cq_tdata                                ( m_axis_cq_tdata ),
    .m_axis_cq_tuser                                ( m_axis_cq_tuser[84:0] ),
    .m_axis_cq_tlast                                ( m_axis_cq_tlast ),
    .m_axis_cq_tkeep                                ( m_axis_cq_tkeep ),
    .m_axis_cq_tvalid                               ( m_axis_cq_tvalid ),
    .m_axis_cq_tready                               ( m_axis_cq_tready ),

    .s_axis_cc_tdata                                ( s_axis_cc_tdata ),
    .s_axis_cc_tuser                                ( s_axis_cc_tuser ),
    .s_axis_cc_tlast                                ( s_axis_cc_tlast ),
    .s_axis_cc_tkeep                                ( s_axis_cc_tkeep ),
    .s_axis_cc_tvalid                               ( s_axis_cc_tvalid ),
    .s_axis_cc_tready                               ( s_axis_cc_tready ),

    //---------------------------------------------------------------------------------------//
    //  Configuration (CFG) Interface                                                        //
    //---------------------------------------------------------------------------------------//
    .pcie_rq_seq_num                                ( pcie_rq_seq_num0[3:0] ),
    .pcie_rq_seq_num_vld                            ( pcie_rq_seq_num_vld0 ),
    .pcie_rq_tag                                    ( pcie_rq_tag0[5:0] ),
    .pcie_rq_tag_av                                 ( pcie_rq_tag_av[1:0] ),
    .pcie_rq_tag_vld                                ( pcie_rq_tag_vld0 ),
    .pcie_cq_np_req                                 ( pcie_cq_np_req[0] ),
    .pcie_cq_np_req_count                           ( pcie_cq_np_req_count ),
    .cfg_phy_link_down                              ( cfg_phy_link_down ),
    .cfg_phy_link_status                            ( cfg_phy_link_status ),
    .cfg_negotiated_width                           ( cfg_negotiated_width_int ),
    .cfg_current_speed                              ( cfg_current_speed_int ),
    .cfg_max_payload                                ( cfg_max_payload_int ),
    .cfg_max_read_req                               ( cfg_max_read_req ),
    .cfg_function_status                            ( cfg_function_status ),
    .cfg_function_power_state                       ( cfg_function_power_state ),
    .cfg_vf_status                                  ( cfg_vf_status[15:0] ),
    .cfg_vf_power_state                             ( cfg_vf_power_state[23:0] ),
    .cfg_link_power_state                           ( cfg_link_power_state ),

    // Error Reporting Interface
    .cfg_err_cor_out                                ( cfg_err_cor_out ),
    .cfg_err_nonfatal_out                           ( cfg_err_nonfatal_out ),
    .cfg_err_fatal_out                              ( cfg_err_fatal_out ),
    .cfg_local_error                                ( cfg_local_error[0] ),

    .cfg_ltr_enable                                 ( cfg_ltr_enable ),
    .cfg_ltssm_state                                ( cfg_ltssm_state ),
    .cfg_rcb_status                                 ( cfg_rcb_status ),
   // .cfg_dpa_substate_change                        ( cfg_dpa_substate_change ),
    .cfg_dpa_substate_change                        ( ),
    .cfg_obff_enable                                ( cfg_obff_enable ),
    .cfg_pl_status_change                           ( cfg_pl_status_change ),

    .cfg_tph_requester_enable                       ( cfg_tph_requester_enable ),
    .cfg_tph_st_mode                                ( cfg_tph_st_mode ),
    .cfg_vf_tph_requester_enable                    ( cfg_vf_tph_requester_enable[7:0] ),
    .cfg_vf_tph_st_mode                             ( cfg_vf_tph_st_mode[23:0] ),

    // Management Interface
    .cfg_mgmt_addr                                  ( {9'b0, cfg_mgmt_addr} ),
    .cfg_mgmt_write                                 ( cfg_mgmt_write ),
    .cfg_mgmt_write_data                            ( cfg_mgmt_write_data ),
    .cfg_mgmt_byte_enable                           ( cfg_mgmt_byte_enable ),
    .cfg_mgmt_read                                  ( cfg_mgmt_read ),
    .cfg_mgmt_read_data                             ( cfg_mgmt_read_data ),
    .cfg_mgmt_read_write_done                       ( cfg_mgmt_read_write_done ),
    // .cfg_mgmt_type1_cfg_reg_access                  ( cfg_mgmt_type1_cfg_reg_access ),
    .cfg_mgmt_type1_cfg_reg_access                  ( ),
    .pcie_tfc_nph_av                                ( pcie_tfc_nph_av[1:0] ),
    .pcie_tfc_npd_av                                ( pcie_tfc_npd_av[1:0] ),

    .cfg_msg_received                               ( cfg_msg_received ),
    .cfg_msg_received_data                          ( cfg_msg_received_data ),
    .cfg_msg_received_type                          ( cfg_msg_received_type ),

    .cfg_msg_transmit                               ( cfg_msg_transmit ),
    .cfg_msg_transmit_type                          ( cfg_msg_transmit_type ),
    .cfg_msg_transmit_data                          ( cfg_msg_transmit_data ),
    .cfg_msg_transmit_done                          ( cfg_msg_transmit_done ),

    .cfg_fc_ph                                      ( cfg_fc_ph ),
    .cfg_fc_pd                                      ( cfg_fc_pd ),
    .cfg_fc_nph                                     ( cfg_fc_nph ),
    .cfg_fc_npd                                     ( cfg_fc_npd ),
    .cfg_fc_cplh                                    ( cfg_fc_cplh ),
    .cfg_fc_cpld                                    ( cfg_fc_cpld ),
    .cfg_fc_sel                                     ( cfg_fc_sel ),


    .cfg_dsn                                        ( cfg_dsn ),
    .cfg_power_state_change_ack                     ( cfg_power_state_change_ack ),
    .cfg_power_state_change_interrupt               ( cfg_power_state_change_interrupt ),
    .cfg_err_cor_in                                 ( cfg_err_cor_in ),
    .cfg_err_uncor_in                               ( cfg_err_uncor_in ),

    .cfg_flr_in_process                             ( cfg_flr_in_process ),
    .cfg_flr_done                                   ( {2'b0,cfg_flr_done} ),
    .cfg_vf_flr_in_process                          ( cfg_vf_flr_in_process[7:0] ),
    .cfg_vf_flr_done                                ( {8{cfg_vf_flr_done}} ),
    .cfg_link_training_enable                       ( cfg_link_training_enable ),

    .cfg_per_func_status_control                    ( 3'b0  ),
    .cfg_per_func_status_data                       (  ),

    // EP only
    .cfg_hot_reset_out                              ( cfg_hot_reset_out ),
    .cfg_config_space_enable                        ( cfg_config_space_enable ),
    .cfg_req_pm_transition_l23_ready                ( cfg_req_pm_transition_l23_ready ),

    // RP only
    .cfg_hot_reset_in                               ( cfg_hot_reset_in ),
    .cfg_ds_bus_number                              ( cfg_ds_bus_number ),
    .cfg_ds_device_number                           ( cfg_ds_device_number ),
    .cfg_ds_function_number                         ( 3'h0 ),
    .cfg_ds_port_number                             ( cfg_ds_port_number ),
    .cfg_per_function_number                        ( 4'h0 ),
    .cfg_per_function_output_request                ( 1'b0 ),
    .cfg_per_function_update_done                   ( ),


//    .cfg_ext_read_received                          ( cfg_ext_read_received ),
//    .cfg_ext_write_received                         ( cfg_ext_write_received ),
//    .cfg_ext_register_number                        ( cfg_ext_register_number ),
//    .cfg_ext_function_number                        ( cfg_ext_function_number ),
//    .cfg_ext_write_data                             ( cfg_ext_write_data ),
//    .cfg_ext_write_byte_enable                      ( cfg_ext_write_byte_enable ),
//    .cfg_ext_read_data                              ( cfg_ext_read_data ),
//    .cfg_ext_read_data_valid                        ( cfg_ext_read_data_valid ),

    //-------------------------------------------------------------------------------//
    // EP Only                                                                       //
    //-------------------------------------------------------------------------------//

    // Interrupt Interface Signals
    .cfg_interrupt_int                              ( cfg_interrupt_int ),
    .cfg_interrupt_pending                          ( {2'b0,cfg_interrupt_pending} ),
    .cfg_interrupt_sent                             ( cfg_interrupt_sent ),

    .cfg_interrupt_msi_enable                       ( cfg_interrupt_msi_enable ),
    .cfg_interrupt_msi_vf_enable                    (  ),
    .cfg_interrupt_msi_mmenable                     ( cfg_interrupt_msi_mmenable ),
    .cfg_interrupt_msi_mask_update                  ( cfg_interrupt_msi_mask_update ),
    .cfg_interrupt_msi_data                         ( cfg_interrupt_msi_data ),
    .cfg_interrupt_msi_select                       ( {2'h0, cfg_interrupt_msi_select} ),
    .cfg_interrupt_msi_int                          ( cfg_interrupt_msi_int ),
    .cfg_interrupt_msi_pending_status               ( cfg_interrupt_msi_pending_status[31:0] ),
    .cfg_interrupt_msi_sent                         ( cfg_interrupt_msi_sent ),
    .cfg_interrupt_msi_fail                         ( cfg_interrupt_msi_fail ),
    .cfg_interrupt_msi_attr                         ( cfg_interrupt_msi_attr ),
    .cfg_interrupt_msi_tph_present                  ( cfg_interrupt_msi_tph_present ),
    .cfg_interrupt_msi_tph_type                     ( cfg_interrupt_msi_tph_type ),
    .cfg_interrupt_msi_tph_st_tag                   ( {1'b0,cfg_interrupt_msi_tph_st_tag} ),
    .cfg_interrupt_msi_function_number              (4'b0 ),
    .cfg_interrupt_msi_pending_status_function_num  (4'b0),
    .cfg_interrupt_msi_pending_status_data_enable   (1'b0),
    
    //--------------------------------------------------------------------------------------//
    //  PIPE interface for simulation                                                       //
    //--------------------------------------------------------------------------------------//
    .common_commands_in                             (common_commands_in ),
    .pipe_rx_0_sigs                                 (pipe_rx_0_sigs     ),
    .pipe_rx_1_sigs                                 (pipe_rx_1_sigs     ),
    .pipe_rx_2_sigs                                 (pipe_rx_2_sigs     ),
    .pipe_rx_3_sigs                                 (pipe_rx_3_sigs     ),
    .pipe_rx_4_sigs                                 (pipe_rx_4_sigs     ),
    .pipe_rx_5_sigs                                 (pipe_rx_5_sigs     ),
    .pipe_rx_6_sigs                                 (pipe_rx_6_sigs     ),
    .pipe_rx_7_sigs                                 (pipe_rx_7_sigs     ),
   
  
    .common_commands_out                            (common_commands_out),
    .pipe_tx_0_sigs                                 (pipe_tx_0_sigs     ),
    .pipe_tx_1_sigs                                 (pipe_tx_1_sigs     ),
    .pipe_tx_2_sigs                                 (pipe_tx_2_sigs     ),
    .pipe_tx_3_sigs                                 (pipe_tx_3_sigs     ),
    .pipe_tx_4_sigs                                 (pipe_tx_4_sigs     ),
    .pipe_tx_5_sigs                                 (pipe_tx_5_sigs     ),
    .pipe_tx_6_sigs                                 (pipe_tx_6_sigs     ),
    .pipe_tx_7_sigs                                 (pipe_tx_7_sigs     ),
  

   //---------- Shared Logic Internal -------------------------
    .int_qpll1lock_out                              (  ),   
    .int_qpll1outrefclk_out                         (  ),
    .int_qpll1outclk_out                            (  ),

    //--------------------------------------------------------------------------------------//
    //  System(SYS) Interface                                                               //
    //--------------------------------------------------------------------------------------//
    .sys_clk                                        ( sys_clk ),
    .sys_clk_gt                                     ( sys_clk_gt ),
    .sys_reset                                      ( sys_reset_n ),

    .phy_rdy_out                                    ( phy_rdy_out )
