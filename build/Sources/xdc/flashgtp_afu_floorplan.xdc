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

#Floorplan
# full area {SLICE_X0Y0:SLICE_X104Y658 DSP48E2_X0Y0:DSP48E2_X7Y261 RAMB18_X0Y0:RAMB18_X7Y261
# RAMB36_X0Y0:RAMB36_X7Y130 URAM288_X0Y0:URAM288_X0Y123}
# initial base pblock {SLICE_X0Y0:SLICE_X104Y225 DSP48E2_X0Y0:DSP48E2_X7Y89 RAMB18_X0Y0:RAMB18_X7Y89 RAMB36_X0Y0:RAMB36_X7Y44 URAM288_X0Y0:URAM288_X0Y11} -locs keep_all

create_pblock afu
add_cells_to_pblock [get_pblocks afu] [get_cells -quiet [list a0]]

# full clock regions, include all PCIE blocks
resize_pblock  [get_pblocks afu] -add {CLOCKREGION_X0Y4:CLOCKREGION_X3Y10}

# not full clock regions, can't include all PCIE clocks
#resize_pblock afu -add {SLICE_X0Y261:SLICE_X104Y659 DSP48E2_X0Y106:DSP48E2_X7Y263 RAMB18_X0Y106:RAMB18_X7Y263 RAMB36_X0Y53:RAMB36_X7Y131 URAM288_X0Y24:URAM288_X0Y127} 
# remove PCIe IP.  Placement gives errors for these unless the full clockregion is used

remove_cells_from_pblock afu [get_cells [list a0/s0/nvme_top/nvme_port0/nvme_pcie/nvme_pcie_hip]]
remove_cells_from_pblock afu [get_cells [list a0/s0/nvme_top/nvme_port1/nvme_pcie/nvme_pcie_hip]]
remove_cells_from_pblock afu [get_cells [list a0/s0/nvme_top/nvme_port2/nvme_pcie/nvme_pcie_hip]]
remove_cells_from_pblock afu [get_cells [list a0/s0/nvme_top/nvme_port3/nvme_pcie/nvme_pcie_hip]]


