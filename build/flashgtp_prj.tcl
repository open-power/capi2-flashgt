#!/bin/sh
# tcl wrapper - next line treated as comment by vivado \
exec vivado -source "$0" $@

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



# launch synth & implementation if set
set launchruns 0
# if project already exists, force overwrite
set force 0

set project flashgtp
set srcproject flashgtp
#set part xcku15p-ffva1156-2-i-es2
set part xcku15p-ffva1156-2-i


variable script_file
set script_file "flashgtp_prj.tcl"

# Help information for this script
proc help {} {
  variable script_file
  puts "\nDescription:"
  puts "Recreate a Vivado project from this script. The created project will be"
  puts "functionally equivalent to the original project for which this script was"
  puts "generated. The script contains commands for creating a project, filesets,"
  puts "runs, adding/importing sources and setting properties on various objects.\n"
  puts "Syntax:"
  puts "$script_file"
  puts "$script_file -tclargs \[--origin_dir <path>\]"
  puts "$script_file -tclargs \[--help\]\n"
  puts "Usage:"
  puts "Name                   Description"
  puts "-------------------------------------------------------------------------"
  puts "\[--origin_dir <path>\]  Determine source file paths wrt this path. Default"
  puts "                       origin_dir path value is \".\", otherwise, the value"
  puts "                       that was set with the \"-paths_relative_to\" switch"
  puts "                       when this script was generated.\n"
  puts "\[--help\]               Print help information for this script"
  puts "-------------------------------------------------------------------------\n"
  exit 0
}
puts "argc: {$::argc} argv: {$::argv}\n"
if { $::argc > 0 } {
  for {set i 0} {$i < $::argc} {incr i} {
    set option [string trim [lindex $::argv $i]]
    puts "option: $option\n"
    switch -regexp -- $option {
      "--origin_dir" { incr i; set origin_dir [lindex $::argv $i] }
      "--project"    { incr i; set project [lindex $::argv $i] }
      "--srcproject" { incr i; set srcproject [lindex $::argv $i] }
      "--part"       { incr i; set part [lindex $::argv $i] }
      "--force"      { set force 1; puts "force=1 - existing project will be overwritten\n" }
      "--launch"     { set launchruns 1 }
      "--help"       { help }
      default {
        if { [regexp {^-} $option] } {
          puts "ERROR: Unknown option '$option' specified, please type '$script_file -tclargs --help' for usage info.\n"
          return 1
        }
      }
    }
  }
}


proc create_flashgtp_project {} {
    

    # Set the reference directory for source file relative paths (by default the value is script directory path)
    set origin_dir "."

    # Use origin directory path location variable, if specified in the tcl shell
    if { [info exists ::origin_dir_loc] } {
      set origin_dir $::origin_dir_loc
    }

    create_project $::project ./$::project -part $::part -force
    
    # Set the directory path for the new project
    set proj_dir [get_property directory [current_project]]

    # Reconstruct message rules
    # None

    # Set project properties
    set obj [get_projects $::project]
    set_property -name "default_lib" -value "work" -objects $obj
    set_property -name "ip_cache_permissions" -value "disable" -objects $obj
    set_property -name "part" -value "$::part" -objects $obj
    set_property -name "sim.ip.auto_export_scripts" -value "1" -objects $obj
    set_property -name "simulator_language" -value "Mixed" -objects $obj
    set_property -name "target_simulator" -value "IES" -objects $obj
    set_property -name "xpm_libraries" -value "XPM_CDC XPM_MEMORY" -objects $obj
    set_property -name "xsim.array_display_limit" -value "64" -objects $obj

    # Create 'sources_1' fileset (if not found)
    if {[string equal [get_filesets -quiet sources_1] ""]} {
        create_fileset -srcset sources_1
    }

    # Set IP repository paths
    set obj [get_filesets sources_1]
    set_property "ip_repo_paths" "[file normalize "$origin_dir/../psl/ip_repo"]" $obj

    # Rebuild user ip_repo's index before adding any source files
    update_ip_catalog -rebuild


    # Create 'constrs_1' fileset (if not found)
    if {[string equal [get_filesets -quiet constrs_1] ""]} {
        create_fileset -constrset constrs_1
    }

    # Set 'constrs_1' fileset object
    set obj [get_filesets constrs_1]

    # Add/Import constrs file and set constrs file properties
    set file "[file normalize "$origin_dir/Sources/xdc/flashgtp_config.xdc"]"
    set file_added [add_files -norecurse -fileset $obj $file]
    set file "$origin_dir/Sources/xdc/flashgtp_config.xdc"
    set file [file normalize $file]
    set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property -name "file_type" -value "XDC" -objects $file_obj
    set_property -name "library" -value "work" -objects $file_obj

    # Add/Import constrs file and set constrs file properties
    set file "[file normalize "$origin_dir/Sources/xdc/flashgtp_psl_timing.xdc"]"
    set file_added [add_files -norecurse -fileset $obj $file]
    set file "$origin_dir/Sources/xdc/flashgtp_psl_timing.xdc"
    set file [file normalize $file]
    set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property -name "file_type" -value "XDC" -objects $file_obj
    set_property -name "library" -value "work" -objects $file_obj

    # Add/Import constrs file and set constrs file properties
    set file "[file normalize "$origin_dir/Sources/xdc/flashgtp_psl_io.xdc"]"
    set file_added [add_files -norecurse -fileset $obj $file]
    set file "$origin_dir/Sources/xdc/flashgtp_psl_io.xdc"
    set file [file normalize $file]
    set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property -name "file_type" -value "XDC" -objects $file_obj
    set_property -name "library" -value "work" -objects $file_obj

    # Add/Import constrs file and set constrs file properties
    set file "[file normalize "$origin_dir/Sources/xdc/flashgtp_psl_floorplan.xdc"]"
    set file_added [add_files -norecurse -fileset $obj $file]
    set file "$origin_dir/Sources/xdc/flashgtp_psl_floorplan.xdc"
    set file [file normalize $file]
    set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property -name "file_type" -value "XDC" -objects $file_obj
    set_property -name "is_enabled" -value "1" -objects $file_obj
    set_property -name "library" -value "work" -objects $file_obj

    # Add/Import constrs file and set constrs file properties
    set file "[file normalize "$origin_dir/Sources/xdc/flashgtp_afu_timing.xdc"]"
    set file_added [add_files -norecurse -fileset $obj $file]
    set file "$origin_dir/Sources/xdc/flashgtp_afu_timing.xdc"
    set file [file normalize $file]
    set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property -name "file_type" -value "XDC" -objects $file_obj
    set_property -name "library" -value "work" -objects $file_obj

    # Add/Import constrs file and set constrs file properties
    set file "[file normalize "$origin_dir/Sources/xdc/flashgtp_afu_io.xdc"]"
    set file_added [add_files -norecurse -fileset $obj $file]
    set file "$origin_dir/Sources/xdc/flashgtp_afu_io.xdc"
    set file [file normalize $file]
    set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property -name "file_type" -value "XDC" -objects $file_obj
    set_property -name "library" -value "work" -objects $file_obj

    # Add/Import constrs file and set constrs file properties
    set file "[file normalize "$origin_dir/Sources/xdc/flashgtp_afu_floorplan.xdc"]"
    set file_added [add_files -norecurse -fileset $obj $file]
    set file "$origin_dir/Sources/xdc/flashgtp_afu_floorplan.xdc"
    set file [file normalize $file]
    set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property -name "file_type" -value "XDC" -objects $file_obj
    set_property -name "is_enabled" -value "0" -objects $file_obj
    set_property -name "library" -value "work" -objects $file_obj

    # Add/Import constrs file and set constrs file properties
    set file "[file normalize "$origin_dir/Sources/xdc/target.xdc"]"
    set file_added [add_files -norecurse -fileset $obj $file]
    set file "$origin_dir/Sources/xdc/target.xdc"
    set file [file normalize $file]
    set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property -name "file_type" -value "XDC" -objects $file_obj
    set_property -name "library" -value "work" -objects $file_obj
    set_property -name "used_in" -value "implementation" -objects $file_obj
    set_property -name "used_in_synthesis" -value "0" -objects $file_obj

    # Set 'constrs_1' fileset properties
    set obj [get_filesets constrs_1]
    set_property -name "target_constrs_file" -value "[file normalize "$origin_dir/Sources/xdc/target.xdc"]" -objects $obj

    # Create 'sim_1' fileset (if not found)
    if {[string equal [get_filesets -quiet sim_1] ""]} {
        create_fileset -simset sim_1
    }


    # Set 'sim_1' fileset properties
    set obj [get_filesets sim_1]
    set_property -name "ies.elaborate.ncelab.more_options" -value "-timescale 1ns/1ps" -objects $obj
    set_property -name "top" -value "psl_fpga" -objects $obj

    # Create 'synth_1' run (if not found)
    if {[string equal [get_runs -quiet synth_1] ""]} {
        create_run -name synth_1 -part $::part -flow {Vivado Synthesis 2017} -strategy "Vivado Synthesis Defaults" -constrset constrs_1
    } else {
        set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
        set_property flow "Vivado Synthesis 2017" [get_runs synth_1]
    }
    set obj [get_runs synth_1]
    set_property -name "needs_refresh" -value "1" -objects $obj
    set_property -name "part" -value "$::part" -objects $obj


    # set the current synth run
    current_run -synthesis [get_runs synth_1]


    if {[string equal [get_filesets -quiet utils_1] ""]} {
        create_fileset -constrset utils_1
    }
    add_files -fileset utils_1 [glob Sources/pre_*.tcl Sources/post_*.tcl]

    # create implementation runs
    # initial settings for each run are the same
    # pre_place.tcl script uses the run name to modify a constraint to produce different placement for each run
    for {set run 1} {$run < 40} {incr run} {  
        set impl "impl_$run"
        if {[string equal [get_runs -quiet $impl] ""]} {
            create_run -name $impl -part $::part -flow {Vivado Implementation 2017} -strategy "Performance_Explore" -constrset constrs_1 -parent_run synth_1
        } else {
            set_property strategy "Performance_Explore" [get_runs $impl]
            set_property flow "Vivado Implementation 2017" [get_runs $impl]
        }
        set obj [get_runs $impl]
        set_property -name "needs_refresh" -value "1" -objects $obj
        set_property -name "part" -value "$::part" -objects $obj
        set_property -name "steps.opt_design.args.directive" -value "ExploreWithRemap" -objects $obj
        set_property -name "steps.place_design.args.directive" -value "Explore" -objects $obj
        set_property -name "steps.phys_opt_design.is_enabled" -value "1" -objects $obj
        set_property -name "steps.phys_opt_design.args.directive" -value "AggressiveExplore" -objects $obj
        set_property -name "steps.route_design.args.directive" -value "Explore" -objects $obj
        set_property -name "steps.route_design.args.more options" -value "-tns_cleanup" -objects $obj
        set_property -name "steps.post_route_phys_opt_design.is_enabled" -value "0" -objects $obj
        set_property -name "steps.post_route_phys_opt_design.args.directive" -value "Explore" -objects $obj
        set_property -name "steps.write_bitstream.args.readback_file" -value "0" -objects $obj
        set_property -name "steps.write_bitstream.args.verbose" -value "0" -objects $obj
        set_property -name {steps.place_design.args.more options} -value "-no_bufg_opt" -objects $obj

        set_property STEPS.OPT_DESIGN.TCL.PRE        [get_files pre_opt.tcl] $obj
        set_property STEPS.PLACE_DESIGN.TCL.PRE      [get_files pre_place.tcl] $obj
        set_property STEPS.PLACE_DESIGN.TCL.POST     [get_files post_place.tcl] $obj
        set_property STEPS.PHYS_OPT_DESIGN.TCL.POST  [get_files post_timing.tcl] $obj
        set_property STEPS.ROUTE_DESIGN.TCL.POST     [get_files post_timing.tcl] $obj
        set_property STEPS.WRITE_BITSTREAM.TCL.POST  [get_files post_bitstream.tcl] $obj
    }


    # set the current impl run
    current_run -implementation [get_runs impl_1]

    puts "INFO: Project created:$::project"

    add_files -norecurse $origin_dir/../hdk/src/
    add_files -norecurse $origin_dir/../afu/capi
    add_files -norecurse $origin_dir/../afu/base
    add_files -norecurse $origin_dir/../afu/apps/tms
    add_files -norecurse $origin_dir/../afu/nvme
    add_files -norecurse $origin_dir/../afu/top/snvme_afu_top.v
    add_files -norecurse $origin_dir/../afu/ucode/mb_nvme_control.elf
    set_property file_type SystemVerilog [get_files -filter {FILE_TYPE == "Verilog" && IS_GENERATED==0} *afu/*.v]

    source ./Sources/create_ip.tcl
    source ./Sources/ublaze_0_bd.tcl
    set_property synth_checkpoint_mode None [get_files ublaze_0.bd]

    set obj [get_filesets sources_1]
    set_property -name "top" -value "psl_fpga" -objects $obj


    set file "$origin_dir/../afu/ucode/mb_nvme_control.elf"
    set file [file normalize $file]
    set file_obj [get_files -of_objects [get_filesets sources_1] [list "*$file"]]
    set_property -name "scoped_to_cells" -value "microblaze_0" -objects $file_obj
    set_property -name "scoped_to_ref" -value "ublaze_0" -objects $file_obj
    set_property -name "used_in_implementation" -value "1" -objects $file_obj

    update_compile_order -fileset sources_1
 
    create_ip_run [get_files -of_objects [get_fileset sources_1] [get_files PSL9_WRAP_0.xci]]
    set_property strategy "Vivado Synthesis Defaults" [get_runs PSL9_WRAP_0_synth_1]

}

###-------------------------------------------------------------------------------
### main
###-------------------------------------------------------------------------------


# build any generated files
exec "make"


if { ([file exists ./$project/$project.xpr] == 0) || ($force == 1) } {
    create_flashgtp_project
} else {
    open_project ./$project/$project.xpr
}

if { $launchruns == 1 } { 
    launch_runs impl_1 -to_step write_bitstream -jobs 12
}
