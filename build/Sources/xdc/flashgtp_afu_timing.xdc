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


# afu constraints


create_clock -period 10.000 -name pcie_clk1 -waveform {0.000 5.000} [get_ports pci_pi_refclk_p1]
set_input_jitter [get_clocks -of_objects [get_ports pci_pi_refclk_p1]] 0.200

create_clock -period 10.000 -name pcie_clk2 -waveform {0.000 5.000} [get_ports pci_pi_refclk_p2]
set_input_jitter [get_clocks -of_objects [get_ports pci_pi_refclk_p2]] 0.200

create_clock -period 10.000 -name pcie_clk3 -waveform {0.000 5.000} [get_ports pci_pi_refclk_p3]
set_input_jitter [get_clocks -of_objects [get_ports pci_pi_refclk_p3]] 0.200

create_clock -period 10.000 -name pcie_clk4 -waveform {0.000 5.000} [get_ports pci_pi_refclk_p4]
set_input_jitter [get_clocks -of_objects [get_ports pci_pi_refclk_p4]] 0.200

# create_clock -period 3.75 -name quad_clk  [get_ports quad_refclk_p]
set_clock_groups -asynchronous -group [get_clocks [get_ports quad_refclk_p] -include_generated_clocks ]


# 7/14/2016 
# don't use clock_groups - difficult to ensure async crossings are correct with this
# instead, set set_max_delay -datapath_only 

set p0_userclk [get_clocks -of_objects [get_nets {a0/s0/nvme_top/nvme_port0/nvme_pcie/user_clk}]]
set p1_userclk [get_clocks -of_objects [get_nets {a0/s0/nvme_top/nvme_port1/nvme_pcie/user_clk}]]
set p2_userclk [get_clocks -of_objects [get_nets {a0/s0/nvme_top/nvme_port2/nvme_pcie/user_clk}]]
set p3_userclk [get_clocks -of_objects [get_nets {a0/s0/nvme_top/nvme_port3/nvme_pcie/user_clk}]]
set host_userclk [get_clocks -of_objects [get_nets psl_clk]]

set_max_delay -datapath_only -from $p0_userclk -to $host_userclk 4.0
set_max_delay -datapath_only -from $p1_userclk -to $host_userclk 4.0
set_max_delay -datapath_only -from $p2_userclk -to $host_userclk 4.0
set_max_delay -datapath_only -from $p3_userclk -to $host_userclk 4.0

set_max_delay -datapath_only -from $host_userclk -to $p0_userclk 4.0
set_max_delay -datapath_only -from $host_userclk -to $p1_userclk 4.0
set_max_delay -datapath_only -from $host_userclk -to $p2_userclk 4.0
set_max_delay -datapath_only -from $host_userclk -to $p3_userclk 4.0

set_max_delay -datapath_only -from $host_userclk -to [get_clocks pcie_clk1] 4.0
set_max_delay -datapath_only -from $host_userclk -to [get_clocks pcie_clk2] 4.0
set_max_delay -datapath_only -from $host_userclk -to [get_clocks pcie_clk3] 4.0
set_max_delay -datapath_only -from $host_userclk -to [get_clocks pcie_clk4] 4.0

set_output_delay -max -10 -clock $host_userclk [get_ports pci_pi_nperst1]
set_output_delay -max -10 -clock $host_userclk [get_ports pci_pi_nperst2]
set_output_delay -max -10 -clock $host_userclk [get_ports pci_pi_nperst3]
set_output_delay -max -10 -clock $host_userclk [get_ports pci_pi_nperst4]
set_output_delay -max -10 -clock $host_userclk [get_ports o_led_*]

