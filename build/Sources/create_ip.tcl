#/ *!***************************************************************************
#/ *! Copyright 2019 International Business Machines
#/ *!
#/ *! Licensed under the Apache License, Version 2.0 (the "License");
#/ *! you may not use this file except in compliance with the License.
#/ *! You may obtain a copy of the License at
#/ *! http://www.apache.org/licenses/LICENSE-2.0 
#/ *!
#/ *! The patent license granted to you in Section 3 of the License, as applied
#/ *! to the "Work," hereby includes implementations of the Work in physical form. 
#/ *!
#/ *! Unless required by applicable law or agreed to in writing, the reference design
#/ *! distributed under the License is distributed on an "AS IS" BASIS,
#/ *! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#/ *! See the License for the specific language governing permissions and
#/ *! limitations under the License.
#/ *!***************************************************************************


set proj_dir [get_property directory [current_project]]

#create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip -version 1.2 -module_name pcie4_uscale_plus_0
create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip -module_name pcie4_uscale_plus_0


set_property -dict [list  CONFIG.enable_gen4 {true} \
CONFIG.gen4_eieos_0s7 {true} \
CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {16.0_GT/s} \
CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X8} \
CONFIG.AXISTEN_IF_EXT_512_CQ_STRADDLE {true} \
CONFIG.AXISTEN_IF_EXT_512_RC_4TLP_STRADDLE {false} \
CONFIG.axisten_if_enable_client_tag {true} \
CONFIG.PF0_CLASS_CODE {1200ff} \
CONFIG.PF0_DEVICE_ID {0628} \
CONFIG.PF0_REVISION_ID {02} \
CONFIG.PF0_SUBSYSTEM_ID {04dd} \
CONFIG.PF0_SUBSYSTEM_VENDOR_ID {1014} \
CONFIG.ins_loss_profile {Backplane} \
CONFIG.PHY_LP_TXPRESET {5} \
CONFIG.pf0_bar0_64bit {true} \
CONFIG.pf0_bar0_prefetchable {true} \
CONFIG.pf0_bar0_scale {Megabytes} \
CONFIG.pf0_bar0_size {256} \
CONFIG.pf0_bar2_enabled {true} \
CONFIG.pf0_bar2_64bit {true} \
CONFIG.pf0_bar2_prefetchable {true} \
CONFIG.pf0_bar4_enabled {true} \
CONFIG.pf0_bar4_64bit {true} \
CONFIG.pf0_bar4_prefetchable {true} \
CONFIG.pf0_bar4_scale {Gigabytes} \
CONFIG.pf0_bar4_size {256} \
CONFIG.pf0_dev_cap_max_payload {512_bytes} \
CONFIG.vendor_id {1014} \
CONFIG.ext_pcie_cfg_space_enabled {true} \
CONFIG.legacy_ext_pcie_cfg_space_enabled {true} \
CONFIG.mode_selection {Advanced} \
CONFIG.en_gt_selection {true} \
CONFIG.select_quad {GTH_Quad_225} \
CONFIG.AXISTEN_IF_EXT_512_RQ_STRADDLE {true} \
CONFIG.PF0_MSIX_CAP_PBA_BIR {BAR_1:0} \
CONFIG.PF0_MSIX_CAP_TABLE_BIR {BAR_1:0} \
CONFIG.PF2_DEVICE_ID {9048} \
CONFIG.PF3_DEVICE_ID {9048} \
CONFIG.pf2_bar2_enabled {true} \
CONFIG.pf3_bar2_enabled {true} \
CONFIG.pf1_bar2_enabled {true} \
CONFIG.pf1_bar2_type {Memory} \
CONFIG.pf1_bar4_type {Memory} \
CONFIG.pf2_bar2_type {Memory} \
CONFIG.pf2_bar4_type {Memory} \
CONFIG.pf3_bar2_type {Memory} \
CONFIG.pf3_bar4_type {Memory} \
CONFIG.pf0_bar2_type {Memory} \
CONFIG.pf0_bar4_type {Memory} \
CONFIG.pf1_bar4_enabled {true} \
CONFIG.pf1_bar4_scale {Gigabytes} \
CONFIG.pf1_vendor_id {1014} \
CONFIG.pf2_vendor_id {1014} \
CONFIG.pf3_vendor_id {1014} \
CONFIG.pf1_bar0_scale {Megabytes} \
CONFIG.pf1_bar0_size {256} \
CONFIG.axisten_if_width {512_bit} \
CONFIG.pf1_bar4_size {256} \
CONFIG.pf2_bar4_enabled {true} \
CONFIG.pf2_bar4_scale {Gigabytes} \
CONFIG.pf2_bar0_scale {Megabytes} \
CONFIG.pf2_bar0_size {256} \
CONFIG.pf2_bar4_size {256} \
CONFIG.pf3_bar4_enabled {true} \
CONFIG.pf3_bar4_scale {Gigabytes} \
CONFIG.pf3_bar0_scale {Megabytes} \
CONFIG.pf3_bar0_size {256} \
CONFIG.pf3_bar4_size {256} \
CONFIG.coreclk_freq {500} \
CONFIG.plltype {QPLL0} \
CONFIG.axisten_freq {250}] [get_ips pcie4_uscale_plus_0]


#create_ip -name clk_wiz -vendor xilinx.com -library ip -version 5.4 -module_name flashgtp_clk_wiz 
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name flashgtp_clk_wiz 
set_property -dict [list CONFIG.CLKIN1_JITTER_PS {40.0} \
CONFIG.CLKOUT1_DRIVES {BUFG} \
CONFIG.CLKOUT1_JITTER {85.736} \
CONFIG.CLKOUT1_PHASE_ERROR {79.008} \
CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {250} \
CONFIG.CLKOUT2_DRIVES {BUFG} \
CONFIG.CLKOUT2_JITTER {98.122} \
CONFIG.CLKOUT2_PHASE_ERROR {79.008} \
CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125} \
CONFIG.CLKOUT2_USED {true} \
CONFIG.CLKOUT3_DRIVES {BUFGCE} \
CONFIG.CLKOUT3_JITTER {98.122} \
CONFIG.CLKOUT3_PHASE_ERROR {79.008} \
CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {125} \
CONFIG.CLKOUT3_USED {true} \
CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} \
CONFIG.MMCM_CLKFBOUT_MULT_F {5.000} \
CONFIG.MMCM_CLKIN1_PERIOD {4.000} \
CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
CONFIG.MMCM_CLKOUT0_DIVIDE_F {5.000} \
CONFIG.MMCM_CLKOUT1_DIVIDE {10} \
CONFIG.MMCM_CLKOUT2_DIVIDE {10} \
CONFIG.MMCM_DIVCLK_DIVIDE {1} \
CONFIG.NUM_OUT_CLKS {2} \
CONFIG.NUM_OUT_CLKS {3} \
CONFIG.PRIM_IN_FREQ {250}] [get_ips flashgtp_clk_wiz]

#create_ip -name sem_ultra -vendor xilinx.com -library ip -version 3.1 -module_name sem_ultra_0
create_ip -name sem_ultra -vendor xilinx.com -library ip -module_name sem_ultra_0
set_property -dict [list CONFIG.MODE {detect_only}] [get_ips sem_ultra_0]
set_property -dict [list CONFIG.CLOCK_PERIOD {10000}] [get_ips sem_ultra_0]

create_ip -name PSL9_WRAP -vendor ibm.com -library CAPI -version 2.00 -module_name PSL9_WRAP_0

# create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_hdk_0
# set_property -dict [list \
# CONFIG.C_NUM_PROBE_IN {2} \
# CONFIG.C_PROBE_IN0_WIDTH {16} \
# CONFIG.C_PROBE_IN1_WIDTH {16} \
# CONFIG.C_NUM_PROBE_OUT {2} \
# CONFIG.C_PROBE_OUT0_WIDTH {16} \
# CONFIG.C_PROBE_OUT1_WIDTH {16} \
# CONFIG.C_PROBE_OUT0_INIT_VAL {0x0} \
# ] [get_ips vio_hdk_0]
#
# 
# create_ip -name clk_wiz -vendor xilinx.com -library ip -version 5.4 -module_name clk_wiz_quad_freerun0
# set_property -dict [list CONFIG.ENABLE_CLOCK_MONITOR {false} CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} CONFIG.PRIM_IN_FREQ {266} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {250} CONFIG.PRIMITIVE {MMCM} CONFIG.CLKIN1_JITTER_PS {37.589999999999996} CONFIG.MMCM_DIVCLK_DIVIDE {7} CONFIG.MMCM_CLKFBOUT_MULT_F {31.250} CONFIG.MMCM_CLKIN1_PERIOD {3.759} CONFIG.MMCM_CLKIN2_PERIOD {10.0} CONFIG.MMCM_CLKOUT0_DIVIDE_F {4.750} CONFIG.CLKOUT1_JITTER {128.845} CONFIG.CLKOUT1_PHASE_ERROR {165.659}] [get_ips clk_wiz_quad_freerun0]
# 

generate_target all [get_files pcie4_uscale_plus_0.xci]
generate_target all [get_files flashgtp_clk_wiz.xci]
generate_target all [get_files sem_ultra_0.xci]
generate_target all [get_files PSL9_WRAP_0.xci]

# In Vivado 2017.4, the PCIe IP for CAPI has to be patched to add the vsec capability
set pcie4_dir [get_property IP_DIR [get_ips pcie4_uscale_plus_0]]
file copy $proj_dir/../Sources/pcie4_uscale_plus_vsec_cap_0xB0.patch $pcie4_dir/synth/
exec /bin/sh -c "cd $pcie4_dir/synth; patch -b < pcie4_uscale_plus_vsec_cap_0xB0.patch"




create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip -version 1.3 -module_name pcie4_uscale_plus_x0y2

set_property -dict [list \
CONFIG.mode_selection {Advanced} \
CONFIG.device_port_type {Root_Port_of_PCI_Express_Root_Complex} \
CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {8.0_GT/s} \
CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X4} \
CONFIG.axisten_if_enable_client_tag {true} \
CONFIG.PF0_INTERRUPT_PIN {INTA} \
CONFIG.PF0_SUBSYSTEM_ID {04dd} \
CONFIG.en_gt_selection {true} \
CONFIG.select_quad {GTY_Quad_129} \
CONFIG.pcie_blk_locn {X0Y2} \
CONFIG.gen_x0y2 {true} \
CONFIG.pf0_bar0_scale {Megabytes} \
CONFIG.pf0_bar0_size {256} \
CONFIG.pf0_dev_cap_max_payload {512_bytes} \
CONFIG.extended_tag_field {false} \
CONFIG.axisten_if_width {128_bit} \
CONFIG.pipe_sim {true} \
CONFIG.plltype {QPLL1} \
CONFIG.axisten_freq {250} \
CONFIG.en_parity {true} \
CONFIG.gtcom_in_core {1} \
CONFIG.PL_DISABLE_LANE_REVERSAL {false} \
CONFIG.ext_pcie_cfg_space_enabled true \
CONFIG.gen4_eieos_0s7 false \
CONFIG.mult_pf_des false \
CONFIG.pcie_id_if {true} \
] [get_ips pcie4_uscale_plus_x0y2]
set_property generate_synth_checkpoint false [get_files  pcie4_uscale_plus_x0y2.xci]



create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip -version 1.3 -module_name pcie4_uscale_plus_x0y3

set_property -dict [list \
CONFIG.mode_selection {Advanced} \
CONFIG.device_port_type {Root_Port_of_PCI_Express_Root_Complex} \
CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {8.0_GT/s} \
CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X4} \
CONFIG.axisten_if_enable_client_tag {true} \
CONFIG.PF0_INTERRUPT_PIN {INTA} \
CONFIG.PF0_SUBSYSTEM_ID {04dd} \
CONFIG.en_gt_selection {true} \
CONFIG.select_quad {GTY_Quad_130} \
CONFIG.pcie_blk_locn {X0Y3} \
CONFIG.gen_x0y3 {true} \
CONFIG.pf0_bar0_scale {Megabytes} \
CONFIG.pf0_bar0_size {256} \
CONFIG.pf0_dev_cap_max_payload {512_bytes} \
CONFIG.extended_tag_field {false} \
CONFIG.axisten_if_width {128_bit} \
CONFIG.pipe_sim {true} \
CONFIG.plltype {QPLL1} \
CONFIG.axisten_freq {250} \
CONFIG.en_parity {true} \
CONFIG.gtcom_in_core {1} \
CONFIG.PL_DISABLE_LANE_REVERSAL {false} \
CONFIG.ext_pcie_cfg_space_enabled true \
CONFIG.gen4_eieos_0s7 false \
CONFIG.mult_pf_des false \
CONFIG.pcie_id_if {true} \
] [get_ips pcie4_uscale_plus_x0y3]
set_property generate_synth_checkpoint false [get_files  pcie4_uscale_plus_x0y3.xci]



create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip -version 1.3 -module_name pcie4_uscale_plus_x1y1

set_property -dict [list \
CONFIG.mode_selection {Advanced} \
CONFIG.device_port_type {Root_Port_of_PCI_Express_Root_Complex} \
CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {8.0_GT/s} \
CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X4} \
CONFIG.axisten_if_enable_client_tag {true} \
CONFIG.PF0_INTERRUPT_PIN {INTA} \
CONFIG.PF0_SUBSYSTEM_ID {04dd} \
CONFIG.en_gt_selection {true} \
CONFIG.select_quad {GTH_Quad_227} \
CONFIG.pcie_blk_locn {X1Y1} \
CONFIG.gen_x1y1 {true} \
CONFIG.pf0_bar0_scale {Megabytes} \
CONFIG.pf0_bar0_size {256} \
CONFIG.pf0_dev_cap_max_payload {512_bytes} \
CONFIG.extended_tag_field {false} \
CONFIG.axisten_if_width {128_bit} \
CONFIG.pipe_sim {true} \
CONFIG.plltype {QPLL1} \
CONFIG.axisten_freq {250} \
CONFIG.en_parity {true} \
CONFIG.gtcom_in_core {1} \
CONFIG.PL_DISABLE_LANE_REVERSAL {false} \
CONFIG.ext_pcie_cfg_space_enabled true \
CONFIG.gen4_eieos_0s7 false \
CONFIG.mult_pf_des false \
CONFIG.pcie_id_if {true} \
] [get_ips pcie4_uscale_plus_x1y1]
set_property generate_synth_checkpoint false [get_files  pcie4_uscale_plus_x1y1.xci]



create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip -version 1.3 -module_name pcie4_uscale_plus_x1y2

set_property -dict [list \
CONFIG.mode_selection {Advanced} \
CONFIG.device_port_type {Root_Port_of_PCI_Express_Root_Complex} \
CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {8.0_GT/s} \
CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X4} \
CONFIG.axisten_if_enable_client_tag {true} \
CONFIG.PF0_INTERRUPT_PIN {INTA} \
CONFIG.PF0_SUBSYSTEM_ID {04dd} \
CONFIG.en_gt_selection {true} \
CONFIG.select_quad {GTH_Quad_228} \
CONFIG.pcie_blk_locn {X1Y2} \
CONFIG.gen_x1y2 {true} \
CONFIG.pf0_bar0_scale {Megabytes} \
CONFIG.pf0_bar0_size {256} \
CONFIG.pf0_dev_cap_max_payload {512_bytes} \
CONFIG.extended_tag_field {false} \
CONFIG.axisten_if_width {128_bit} \
CONFIG.pipe_sim {true} \
CONFIG.plltype {QPLL1} \
CONFIG.axisten_freq {250} \
CONFIG.en_parity {true} \
CONFIG.gtcom_in_core {1} \
CONFIG.PL_DISABLE_LANE_REVERSAL {false} \
CONFIG.ext_pcie_cfg_space_enabled true \
CONFIG.gen4_eieos_0s7 false \
CONFIG.mult_pf_des false \
CONFIG.pcie_id_if {true} \
] [get_ips pcie4_uscale_plus_x1y2]
set_property generate_synth_checkpoint false [get_files  pcie4_uscale_plus_x1y2.xci]

create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name async_fifo_512x192
set_property -dict [list \
CONFIG.Fifo_Implementation {Independent_Clocks_Builtin_FIFO} \
CONFIG.Performance_Options {First_Word_Fall_Through} \
CONFIG.Input_Data_Width {192} \
CONFIG.Input_Depth {512} \
CONFIG.Output_Data_Width {192} \
CONFIG.Output_Depth {512} \
CONFIG.Enable_ECC {true} \
CONFIG.Use_Embedded_Registers {false} \
CONFIG.Valid_Flag {true} \
CONFIG.Underflow_Flag {true} \
CONFIG.Overflow_Flag {true} \
CONFIG.Inject_Sbit_Error {true} \
CONFIG.Inject_Dbit_Error {true} \
CONFIG.ecc_pipeline_reg {true} \
CONFIG.Data_Count_Width {9} \
CONFIG.Write_Data_Count_Width {9} \
CONFIG.Read_Data_Count_Width {9} \
CONFIG.Read_Clock_Frequency {250} \
CONFIG.Write_Clock_Frequency {250} \
CONFIG.Full_Threshold_Assert_Value {511} \
CONFIG.Full_Threshold_Negate_Value {510} \
CONFIG.Empty_Threshold_Assert_Value {6} \
CONFIG.Empty_Threshold_Negate_Value {7}] [get_ips async_fifo_512x192]
generate_target {instantiation_template} [get_files async_fifo_512x192.xci]


create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0
set_property -dict [list \
CONFIG.C_PROBE_IN6_WIDTH {1} \
CONFIG.C_PROBE_IN5_WIDTH {1} \
CONFIG.C_PROBE_IN4_WIDTH {1} \
CONFIG.C_PROBE_IN3_WIDTH {1} \
CONFIG.C_PROBE_IN2_WIDTH {1} \
CONFIG.C_PROBE_IN1_WIDTH {1} \
CONFIG.C_PROBE_IN0_WIDTH {64} \
CONFIG.C_NUM_PROBE_OUT {0} \
CONFIG.C_NUM_PROBE_IN {7} \
] [get_ips vio_0]
set_property generate_synth_checkpoint false [get_files  vio_0.xci]
generate_target all [get_files  vio_0.xci]



create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_1
set_property -dict [list \
CONFIG.C_PROBE_IN9_WIDTH {32} \
CONFIG.C_PROBE_IN8_WIDTH {32} \
CONFIG.C_PROBE_IN7_WIDTH {32} \
CONFIG.C_PROBE_IN6_WIDTH {32} \
CONFIG.C_PROBE_IN5_WIDTH {16} \
CONFIG.C_PROBE_IN4_WIDTH {16} \
CONFIG.C_PROBE_IN3_WIDTH {16} \
CONFIG.C_PROBE_IN2_WIDTH {16} \
CONFIG.C_PROBE_IN1_WIDTH {16} \
CONFIG.C_PROBE_IN0_WIDTH {16} \
CONFIG.C_PROBE_OUT9_WIDTH {1} \
CONFIG.C_PROBE_OUT8_WIDTH {1} \
CONFIG.C_PROBE_OUT7_WIDTH {1} \
CONFIG.C_PROBE_OUT6_WIDTH {1} \
CONFIG.C_PROBE_OUT5_WIDTH {16} \
CONFIG.C_PROBE_OUT4_WIDTH {16} \
CONFIG.C_PROBE_OUT3_WIDTH {32} \
CONFIG.C_PROBE_OUT2_WIDTH {32} \
CONFIG.C_PROBE_OUT1_WIDTH {1} \
CONFIG.C_PROBE_OUT0_WIDTH {1} \
CONFIG.C_NUM_PROBE_OUT {10} \
CONFIG.C_NUM_PROBE_IN {10} \
] [get_ips vio_1]
set_property generate_synth_checkpoint false [get_files  vio_1.xci]
generate_target all [get_files  vio_1.xci]

