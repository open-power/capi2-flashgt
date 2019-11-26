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


#set_property PACKAGE_PIN G9 [get_ports quad_refclk_p]
#set_property PACKAGE_PIN F9 [get_ports quad_refclk_n]
#set_property IOSTANDARD LVDS [get_ports quad_refclk_p]
#set_property IOSTANDARD LVDS [get_ports quad_refclk_n]


set_property PACKAGE_PIN P5 [get_ports pci_pi_refclk_n1]
set_property PACKAGE_PIN K5 [get_ports pci_pi_refclk_n2]
set_property PACKAGE_PIN R30 [get_ports pci_pi_refclk_n3]
set_property PACKAGE_PIN L30 [get_ports pci_pi_refclk_n4]

# NVMe PCIe port sideband signals

set_property PACKAGE_PIN AP13 [get_ports pci_pi_nperst1]
set_property IOSTANDARD LVCMOS33 [get_ports pci_pi_nperst1]

set_property IOSTANDARD LVCMOS33 [get_ports pci_pi_nperst2]
set_property PACKAGE_PIN AK13 [get_ports pci_pi_nperst2]

set_property IOSTANDARD LVCMOS33 [get_ports pci_pi_nperst3]
set_property PACKAGE_PIN AL8 [get_ports pci_pi_nperst3]

set_property IOSTANDARD LVCMOS33 [get_ports pci_pi_nperst4]
set_property PACKAGE_PIN AE12 [get_ports pci_pi_nperst4]


set_property IOSTANDARD LVCMOS33 [get_ports pci1_o_susclk]
set_property PACKAGE_PIN AN11 [get_ports pci1_o_susclk]

set_property IOSTANDARD LVCMOS33 [get_ports pci1_b_nclkreq]
set_property PACKAGE_PIN AP10 [get_ports pci1_b_nclkreq]
set_property PULLUP true [get_ports pci1_b_nclkreq]

set_property IOSTANDARD LVCMOS33 [get_ports pci1_b_npewake]
set_property PACKAGE_PIN AP11 [get_ports pci1_b_npewake]
set_property PULLUP true [get_ports pci1_b_npewake]

set_property IOSTANDARD LVCMOS33 [get_ports pci2_o_susclk]
set_property PACKAGE_PIN AF13 [get_ports pci2_o_susclk]

set_property IOSTANDARD LVCMOS33 [get_ports pci2_b_nclkreq]
set_property PACKAGE_PIN AH13 [get_ports pci2_b_nclkreq]
set_property PULLUP true [get_ports pci2_b_nclkreq]

set_property IOSTANDARD LVCMOS33 [get_ports pci2_b_npewake]
set_property PACKAGE_PIN AJ13 [get_ports pci2_b_npewake]
set_property PULLUP true [get_ports pci2_b_npewake]

set_property IOSTANDARD LVCMOS33 [get_ports pci3_o_susclk]
set_property PACKAGE_PIN AM11 [get_ports pci3_o_susclk]

set_property IOSTANDARD LVCMOS33 [get_ports pci3_b_nclkreq]
set_property PACKAGE_PIN AP9 [get_ports pci3_b_nclkreq]
set_property PULLUP true [get_ports pci3_b_nclkreq]

set_property IOSTANDARD LVCMOS33 [get_ports pci3_b_npewake]
set_property PACKAGE_PIN AN9 [get_ports pci3_b_npewake]
set_property PULLUP true [get_ports pci3_b_npewake]

set_property IOSTANDARD LVCMOS33 [get_ports pci4_o_susclk]
set_property PACKAGE_PIN AF12 [get_ports pci4_o_susclk]

set_property IOSTANDARD LVCMOS33 [get_ports pci4_b_nclkreq]
set_property PACKAGE_PIN AG12 [get_ports pci4_b_nclkreq]
set_property PULLUP true [get_ports pci4_b_nclkreq]

set_property IOSTANDARD LVCMOS33 [get_ports pci4_b_npewake]
set_property PACKAGE_PIN AH12 [get_ports pci4_b_npewake]
set_property PULLUP true [get_ports pci4_b_npewake]

