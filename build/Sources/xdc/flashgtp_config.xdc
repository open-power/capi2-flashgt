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



set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN {DIV-4} [current_design]
set_property BITSTREAM.CONFIG.BPI_1ST_READ_CYCLE 4 [current_design]
set_property BITSTREAM.CONFIG.BPI_PAGE_SIZE 8 [current_design]
set_property BITSTREAM.CONFIG.BPI_SYNC_MODE DISABLE [current_design]
set_property CONFIG_MODE BPI16 [current_design]
set_property BITSTREAM.CONFIG.TIMER_CFG 0XFFFFFFFF [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# from PSL9_WRAP.xdc - check these
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.CONFIG.PERSIST NO [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]
