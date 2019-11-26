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


# use with post bitstream generate tcl hook
set script_dir [file dirname [file normalize [info script]]]

set afuver_file $script_dir/../../afu/capi/afu_version.svh

set afuver_fh [open $afuver_file r]
set afuver [read $afuver_fh]
foreach line [split $afuver "\n"] {
  if {[regexp {AFU_VERSION_NUMBER \"(\S+)\"} $line -> sub1]} {
     set afuv $sub1
  }
}
 
set version "$afuv"


# convert to bin for host based capi_flash
file rename -force "psl_fpga.bit" "flashgtp.$version.user.bit"
write_cfgmem -format bin -interface bpix16 -size 128 -loadbit "up 0x0 flashgtp.$version.user.bit" -file "flashgtp.$version.user.bin" -force

# convert to mcs for writing flash via jtag
#write_cfgmem -format mcs -interface bpix16 -size 128 -loadbit "up 0x02000000 flashgtp.$version.user.bit" -file "flashgtp.$version.user.mcs" -force

exec $script_dir/prepend_papr_header_flashgt.pl -i flashgtp.$version.user.bin -o 1410000614103306.00000001$version

file copy -force "psl_fpga.mmi" "flashgtp.$version.user.mmi"
#file copy "flashgtp_p8/flashgtp_p8.runs/impl_1/psl_fpga.bmm" "flashgtp.$version.user.bmm"
catch {write_debug_probes -no_partial_ltxfile -quiet -force "flashgtp.$version.user.ltx"}


# factory image
# change init value for afu verison register to "0"
set_property INIT {1'b0} [get_cells  {a0/s0/afu_version_q_reg[63]}]
set_property INIT {1'b0} [get_cells  {a0/s0/afu_version_q_reg[62]}]
set_property INIT {1'b0} [get_cells  {a0/s0/afu_version_q_reg[61]}]
set_property INIT {1'b0} [get_cells  {a0/s0/afu_version_q_reg[60]}]

# change init value for "golden_factory" flag to PSL
set_property INIT {1'b0} [get_cells  {a0/s0/user_image_q_reg}]

write_bitstream ./flashgtp.$version.factory.bit
write_cfgmem -format mcs -size 128 -interface BPIx16 -loadbit "up 0x0 flashgtp.$version.factory.bit up 0x02000000 flashgtp.$version.user.bit" flashgtp.$version.mcs

catch { exec /bin/sh -c "gzip flashgtp.$version.user.* flashgtp.$version.factory.bit flashgtp.$version.mcs" }
