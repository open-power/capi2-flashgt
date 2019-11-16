
#* *!***************************************************************************
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
#/


#
# FlashGT+ ublaze 
# minimal vivado project script for generating hex files
#

set origin_dir "."
set inputelf $::env(INPUTELF)
set orig_proj_dir "[file normalize "$origin_dir/nvme_control_ublaze"]"

# Create project
create_project -force nvme_control_ublaze $orig_proj_dir

set obj [get_projects nvme_control_ublaze]
set_property "default_lib" "xil_defaultlib" $obj
set_property "part" "xcku060-ffva1156-2-e" $obj
set_property "sim.ip.auto_export_scripts" "1" $obj
set_property "simulator_language" "Mixed" $obj
set_property "target_simulator" "IES" $obj

if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

source $origin_dir/../ublaze_0_bd.tcl
set obj [get_filesets sources_1]
set files [list \
 "[file normalize "$origin_dir/../../nvme/nvme_control.v"]"\
 "[file normalize "$origin_dir/../$inputelf"]"\
]
add_files -norecurse -fileset $obj $files

# Set 'sources_1' fileset file properties for remote files
set file "$origin_dir/ublaze_0/ublaze_0.bd"
set file [file normalize $file]
set file_obj [get_files -of_objects [get_filesets sources_1] [list "*$file"]]
if { ![get_property "is_locked" $file_obj] } {
  set_property "generate_synth_checkpoint" "0" $file_obj
}

set file "$origin_dir/../$inputelf"
set file [file normalize $file]
set file_obj [get_files -of_objects [get_filesets sources_1] [list "*$file"]]
set_property "scoped_to_cells" "microblaze_0" $file_obj
set_property "scoped_to_ref" "ublaze_0" $file_obj
set_property "used_in" "implementation" $file_obj
set_property "used_in_simulation" "0" $file_obj


# Set 'sources_1' fileset properties
set obj [get_filesets sources_1]
set_property "top" "nvme_control" $obj

# Create 'sim_1' fileset (if not found)
if {[string equal [get_filesets -quiet sim_1] ""]} {
  create_fileset -simset sim_1
}

# Set 'sim_1' fileset object
set obj [get_filesets sim_1]
set files [list \
 "[file normalize "$origin_dir/../$inputelf"]"\
]
add_files -norecurse -fileset $obj $files

# Set 'sim_1' fileset file properties for remote files
set file "$origin_dir/../$inputelf"
set file [file normalize $file]
set file_obj [get_files -of_objects [get_filesets sim_1] [list "*$file"]]
set_property "scoped_to_cells" "microblaze_0" $file_obj
set_property "scoped_to_ref" "ublaze_0" $file_obj
set_property "used_in" "simulation" $file_obj
set_property "used_in_implementation" "0" $file_obj


generate_target all [get_files ublaze_0/ublaze_0.bd]
generate_mem_files $::env(OUTDIR)

puts "INFO: Project created:nvme_control_ublaze"
