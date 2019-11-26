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

################################################################
# This is a generated script based on design: ublaze_0
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2017.4
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   catch {common::send_msg_id "BD_TCL-109" "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source ublaze_0_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xcku15p-ffva1156-2-i
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name ublaze_0

# This script was generated for a remote BD. To create a non-remote design,
# change the variable <run_remote_bd_flow> to <0>.

set run_remote_bd_flow 0
if { $run_remote_bd_flow == 1 } {
  # Set the reference directory for source file relative paths (by default 
  # the value is script directory path)
  set origin_dir .

  # Use origin directory path location variable, if specified in the tcl shell
  if { [info exists ::origin_dir_loc] } {
     set origin_dir $::origin_dir_loc
  }

  set str_bd_folder [file normalize ${origin_dir}]
  set str_bd_filepath ${str_bd_folder}/${design_name}/${design_name}.bd

  # Check if remote design exists on disk
  if { [file exists $str_bd_filepath ] == 1 } {
     catch {common::send_msg_id "BD_TCL-110" "ERROR" "The remote BD file path <$str_bd_filepath> already exists!"}
     common::send_msg_id "BD_TCL-008" "INFO" "To create a non-remote BD, change the variable <run_remote_bd_flow> to <0>."
     common::send_msg_id "BD_TCL-009" "INFO" "Also make sure there is no design <$design_name> existing in your current project."

     return 1
  }

  # Check if design exists in memory
  set list_existing_designs [get_bd_designs -quiet $design_name]
  if { $list_existing_designs ne "" } {
     catch {common::send_msg_id "BD_TCL-111" "ERROR" "The design <$design_name> already exists in this project! Will not create the remote BD <$design_name> at the folder <$str_bd_folder>."}

     common::send_msg_id "BD_TCL-010" "INFO" "To create a non-remote BD, change the variable <run_remote_bd_flow> to <0> or please set a different value to variable <design_name>."

     return 1
  }

  # Check if design exists on disk within project
  set list_existing_designs [get_files -quiet */${design_name}.bd]
  if { $list_existing_designs ne "" } {
     catch {common::send_msg_id "BD_TCL-112" "ERROR" "The design <$design_name> already exists in this project at location:
    $list_existing_designs"}
     catch {common::send_msg_id "BD_TCL-113" "ERROR" "Will not create the remote BD <$design_name> at the folder <$str_bd_folder>."}

     common::send_msg_id "BD_TCL-011" "INFO" "To create a non-remote BD, change the variable <run_remote_bd_flow> to <0> or please set a different value to variable <design_name>."

     return 1
  }

  # Now can create the remote BD
  # NOTE - usage of <-dir> will create <$str_bd_folder/$design_name/$design_name.bd>
  create_bd_design -dir $str_bd_folder $design_name
} else {

  # Create regular design
  if { [catch {create_bd_design $design_name} errmsg] } {
     common::send_msg_id "BD_TCL-012" "INFO" "Please set a different value to variable <design_name>."

     return 1
  }
}

current_bd_design $design_name

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:blk_mem_gen:8.4\
xilinx.com:ip:iomodule:3.1\
xilinx.com:ip:lmb_bram_if_cntlr:4.0\
xilinx.com:ip:lmb_v10:3.0\
xilinx.com:ip:microblaze:10.0\
"

   set list_ips_missing ""
   common::send_msg_id "BD_TCL-006" "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_msg_id "BD_TCL-115" "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

if { $bCheckIPsPassed != 1 } {
  common::send_msg_id "BD_TCL-1003" "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set GPIO1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 GPIO1 ]
  set GPIO2 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 GPIO2 ]
  set GPIO3 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 GPIO3 ]
  set INTERRUPT [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:mbinterrupt_rtl:1.0 INTERRUPT ]
  set IO_BUS [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mcsio_bus_rtl:1.0 IO_BUS ]
  set TRACE [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mbtrace_rtl:2.0 TRACE ]

  # Create ports
  set CE [ create_bd_port -dir O CE ]
  set CE_1 [ create_bd_port -dir O CE_1 ]
  set Clk [ create_bd_port -dir I -type clk Clk ]
  set_property -dict [ list \
   CONFIG.ASSOCIATED_RESET {Reset} \
   CONFIG.FREQ_HZ {250000000} \
 ] $Clk
  set Reset [ create_bd_port -dir I -type rst Reset ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $Reset
  set UE [ create_bd_port -dir O UE ]
  set UE_1 [ create_bd_port -dir O UE_1 ]

  # Create instance: blk_mem_gen_0, and set properties
  set blk_mem_gen_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 blk_mem_gen_0 ]
  set_property -dict [ list \
   CONFIG.EN_SAFETY_CKT {false} \
   CONFIG.Enable_B {Use_ENB_Pin} \
   CONFIG.Memory_Type {True_Dual_Port_RAM} \
   CONFIG.Port_B_Clock {100} \
   CONFIG.Port_B_Enable_Rate {100} \
   CONFIG.Port_B_Write_Rate {50} \
   CONFIG.Use_RSTB_Pin {true} \
 ] $blk_mem_gen_0

  # Create instance: iomodule_0, and set properties
  set iomodule_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:iomodule:3.1 iomodule_0 ]
  set_property -dict [ list \
   CONFIG.C_GPI1_SIZE {16} \
   CONFIG.C_GPO1_SIZE {16} \
   CONFIG.C_USE_GPI1 {1} \
   CONFIG.C_USE_GPO1 {1} \
   CONFIG.C_USE_GPO2 {1} \
   CONFIG.C_USE_GPO3 {1} \
   CONFIG.C_USE_IO_BUS {1} \
 ] $iomodule_0

  # Create instance: lmb_bram_if_cntlr_0, and set properties
  set lmb_bram_if_cntlr_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 lmb_bram_if_cntlr_0 ]
  set_property -dict [ list \
   CONFIG.C_ECC {1} \
 ] $lmb_bram_if_cntlr_0

  # Create instance: lmb_bram_if_cntlr_1, and set properties
  set lmb_bram_if_cntlr_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 lmb_bram_if_cntlr_1 ]
  set_property -dict [ list \
   CONFIG.C_ECC {1} \
 ] $lmb_bram_if_cntlr_1

  # Create instance: lmb_v10_0, and set properties
  set lmb_v10_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 lmb_v10_0 ]
  set_property -dict [ list \
   CONFIG.C_LMB_NUM_SLAVES {2} \
 ] $lmb_v10_0

  # Create instance: lmb_v10_1, and set properties
  set lmb_v10_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 lmb_v10_1 ]

  # Create instance: microblaze_0, and set properties
  set microblaze_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:10.0 microblaze_0 ]
  set_property -dict [ list \
   CONFIG.C_ADDR_TAG_BITS {0} \
   CONFIG.C_DCACHE_ADDR_TAG {0} \
   CONFIG.C_DEBUG_ENABLED {0} \
   CONFIG.C_D_LMB {1} \
   CONFIG.C_FAULT_TOLERANT {1} \
   CONFIG.C_I_LMB {1} \
   CONFIG.C_TRACE {1} \
   CONFIG.C_USE_BARREL {1} \
 ] $microblaze_0

  # Create interface connections
  connect_bd_intf_net -intf_net Conn [get_bd_intf_pins lmb_bram_if_cntlr_0/SLMB] [get_bd_intf_pins lmb_v10_0/LMB_Sl_0]
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins lmb_bram_if_cntlr_1/SLMB] [get_bd_intf_pins lmb_v10_1/LMB_Sl_0]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins iomodule_0/SLMB] [get_bd_intf_pins lmb_v10_0/LMB_Sl_1]
  connect_bd_intf_net -intf_net INTERRUPT_1 [get_bd_intf_ports INTERRUPT] [get_bd_intf_pins microblaze_0/INTERRUPT]
  connect_bd_intf_net -intf_net iomodule_0_GPIO1 [get_bd_intf_ports GPIO1] [get_bd_intf_pins iomodule_0/GPIO1]
  connect_bd_intf_net -intf_net iomodule_0_GPIO2 [get_bd_intf_ports GPIO2] [get_bd_intf_pins iomodule_0/GPIO2]
  connect_bd_intf_net -intf_net iomodule_0_GPIO3 [get_bd_intf_ports GPIO3] [get_bd_intf_pins iomodule_0/GPIO3]
  connect_bd_intf_net -intf_net iomodule_0_IO_BUS [get_bd_intf_ports IO_BUS] [get_bd_intf_pins iomodule_0/IO_BUS]
  connect_bd_intf_net -intf_net lmb_bram_if_cntlr_0_BRAM_PORT [get_bd_intf_pins blk_mem_gen_0/BRAM_PORTA] [get_bd_intf_pins lmb_bram_if_cntlr_0/BRAM_PORT]
  connect_bd_intf_net -intf_net lmb_bram_if_cntlr_1_BRAM_PORT [get_bd_intf_pins blk_mem_gen_0/BRAM_PORTB] [get_bd_intf_pins lmb_bram_if_cntlr_1/BRAM_PORT]
  connect_bd_intf_net -intf_net microblaze_0_DLMB [get_bd_intf_pins lmb_v10_0/LMB_M] [get_bd_intf_pins microblaze_0/DLMB]
  connect_bd_intf_net -intf_net microblaze_0_ILMB [get_bd_intf_pins lmb_v10_1/LMB_M] [get_bd_intf_pins microblaze_0/ILMB]
  connect_bd_intf_net -intf_net microblaze_0_TRACE [get_bd_intf_ports TRACE] [get_bd_intf_pins microblaze_0/TRACE]

  # Create port connections
  connect_bd_net -net Reset_1 [get_bd_ports Reset] [get_bd_pins lmb_v10_0/SYS_Rst] [get_bd_pins lmb_v10_1/SYS_Rst] [get_bd_pins microblaze_0/Reset]
  connect_bd_net -net lmb_bram_if_cntlr_0_CE [get_bd_ports CE_1] [get_bd_pins lmb_bram_if_cntlr_0/CE]
  connect_bd_net -net lmb_bram_if_cntlr_0_UE [get_bd_ports UE_1] [get_bd_pins lmb_bram_if_cntlr_0/UE]
  connect_bd_net -net lmb_bram_if_cntlr_1_CE [get_bd_ports CE] [get_bd_pins lmb_bram_if_cntlr_1/CE]
  connect_bd_net -net lmb_bram_if_cntlr_1_UE [get_bd_ports UE] [get_bd_pins lmb_bram_if_cntlr_1/UE]
  connect_bd_net -net lmb_v10_0_LMB_Rst [get_bd_pins iomodule_0/Rst] [get_bd_pins lmb_bram_if_cntlr_0/LMB_Rst] [get_bd_pins lmb_v10_0/LMB_Rst]
  connect_bd_net -net lmb_v10_1_LMB_Rst [get_bd_pins lmb_bram_if_cntlr_1/LMB_Rst] [get_bd_pins lmb_v10_1/LMB_Rst]
  connect_bd_net -net microblaze_0_Clk [get_bd_ports Clk] [get_bd_pins iomodule_0/Clk] [get_bd_pins lmb_bram_if_cntlr_0/LMB_Clk] [get_bd_pins lmb_bram_if_cntlr_1/LMB_Clk] [get_bd_pins lmb_v10_0/LMB_Clk] [get_bd_pins lmb_v10_1/LMB_Clk] [get_bd_pins microblaze_0/Clk]

  # Create address segments
  create_bd_addr_seg -range 0x00010000 -offset 0x44A10000 [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs iomodule_0/SLMB/IO] SEG_iomodule_0_IO
  create_bd_addr_seg -range 0x00010000 -offset 0x44A00000 [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs iomodule_0/SLMB/Reg] SEG_iomodule_0_Reg
  create_bd_addr_seg -range 0x00004000 -offset 0x00000000 [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs lmb_bram_if_cntlr_0/SLMB/Mem] SEG_lmb_bram_if_cntlr_0_Mem
  create_bd_addr_seg -range 0x00004000 -offset 0x00000000 [get_bd_addr_spaces microblaze_0/Instruction] [get_bd_addr_segs lmb_bram_if_cntlr_1/SLMB/Mem] SEG_lmb_bram_if_cntlr_1_Mem


  # Restore current instance
  current_bd_instance $oldCurInst

  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


