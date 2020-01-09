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

`timescale 1 ns / 10 ps

//  *************************************************************************
//  File : nvme_top.v
//  *************************************************************************
//  *************************************************************************
//  Description : FlashGT+ NVMe top level
//                Includes four NVMe port instances

//  *************************************************************************

module nvme_top#
  ( // afu/psl   interface parameters
    parameter tag_width       = 8,
    parameter datalen_width   = 25,
    parameter datalen_par_width   = 1,
    parameter data_width      = 128,
    parameter data_bytes      = data_width/8,
    parameter bytec_width     = $clog2(data_bytes+1),
    parameter beatid_width    = datalen_width-$clog2(data_bytes),    
    parameter lunid_width     = 64, 
    parameter cmd_width       = 4, 
    parameter fcstat_width    = 8, 
    parameter fcxstat_width   = 8, 
    parameter rsp_info_width  = 160,
    parameter tag_par_width   = (tag_width + 63)/64,  
    parameter lunid_par_width = (lunid_width + 63)/64, 
    parameter data_par_width  = (data_width + 7)/8 ,  
    parameter data_fc_par_width = data_par_width/8,
    parameter status_width    = 8, // event status
    
    parameter fc0_mmio_base  = 26'h2012000, 
    parameter fc1_mmio_base  = 26'h2013000,
    parameter fc0_mmio_base2 = 26'h2060000, 
    parameter fc1_mmio_base2 = 26'h2080000,
    parameter fc2_mmio_base  = 26'h2016000, 
    parameter fc3_mmio_base  = 26'h2017000,
    parameter fc2_mmio_base2 = 26'h20A0000, 
    parameter fc3_mmio_base2 = 26'h20C0000,

  
    parameter LINK_WIDTH = 4
    )
   (

    // afu 250Mhz clock
    input                          ha_pclock,
    input                          ha_pclock_div2,
    

    // reset from AFU command
    input                          reset_in,

    output                   [3:0] led_red,
    output                   [3:0] led_green,
    output                   [3:0] led_blue,

    input                          i_fc_fatal_error,

   
    // AFU/PSL interface port 0
    // -----------------
   
    // request command interface
    //  req_r    - ready
    //  req_v    - valid.  xfer occurs only if valid & ready, otherwise no xfer
    //  req_cmd  - command encode FCP_*
    //  req_tag  - identifier for the command
    //  req_lba  - logical block address
    //  req_lun  - logical unit number
    output                         i_fc0_req_r_out,
    input                          i_fc0_req_v_in,
    input          [cmd_width-1:0] i_fc0_req_cmd_in, 
    input          [tag_width-1:0] i_fc0_req_tag_in, 
    input      [tag_par_width-1:0] i_fc0_req_tag_par_in, 
    input        [lunid_width-1:0] i_fc0_req_lun_in, 
    input    [lunid_par_width-1:0] i_fc0_req_lun_par_in, 
    input                  [127:0] i_fc0_req_cdb_in, 
    input                    [1:0] i_fc0_req_cdb_par_in, 
    input      [datalen_width-1:0] i_fc0_req_length_in, 
    input                          i_fc0_req_length_par_in, 

    // write data request interface.  No backpressure?
    //   req_v    - valid
    //   req_beat - 32b word offset into wbuf. Must be sequential within 2K block
    output                         o_fc0_wdata_req_v_out,
    input                          o_fc0_wdata_req_r_in,
    output         [tag_width-1:0] o_fc0_wdata_req_tag_out,
    output     [tag_par_width-1:0] o_fc0_wdata_req_tag_par_out,
    output      [beatid_width-1:0] o_fc0_wdata_req_beat_out,
    output     [datalen_width-1:0] o_fc0_wdata_req_size_out,
    output [datalen_par_width-1:0] o_fc0_wdata_req_size_par_out,
    
    // data response interface (writes).  
    //
    input                          i_fc0_wdata_rsp_v_in,
    output                         i_fc0_wdata_rsp_r_out,
    input                          i_fc0_wdata_rsp_e_in,
    input                          i_fc0_wdata_rsp_error_in,
    input          [tag_width-1:0] i_fc0_wdata_rsp_tag_in,
    input                          i_fc0_wdata_rsp_tag_par_in,
    input       [beatid_width-1:0] i_fc0_wdata_rsp_beat_in,
    input         [data_width-1:0] i_fc0_wdata_rsp_data_in,
    input  [data_fc_par_width-1:0] i_fc0_wdata_rsp_data_par_in,

    // read data response interface
    //   rsp_v    - valid.
    //   rsp_r    - ready
    //   rsp_e    - read data end. Must be asserted with rsp_v after last data beat for a tag.
    //   rsp_c    - byte count for last word
    //   rsp_tag  - identifier of the corresponding read request
    //   rsp_beat - word offset for this data transfer
    //   rsp_data - 32b of read data.  Not used when rsp_e is assserted.
    // 
    output                         o_fc0_rdata_rsp_v_out,
    input                          o_fc0_rdata_rsp_r_in,
    output                         o_fc0_rdata_rsp_e_out,
    output       [bytec_width-1:0] o_fc0_rdata_rsp_c_out,
    output      [beatid_width-1:0] o_fc0_rdata_rsp_beat_out,
    output         [tag_width-1:0] o_fc0_rdata_rsp_tag_out,
    output     [tag_par_width-1:0] o_fc0_rdata_rsp_tag_par_out,
    output        [data_width-1:0] o_fc0_rdata_rsp_data_out,
    output [data_fc_par_width-1:0] o_fc0_rdata_rsp_data_par_out,


    // command response interface
    output                         o_fc0_rsp_v_out,
    output         [tag_width-1:0] o_fc0_rsp_tag_out,
    output     [tag_par_width-1:0] o_fc0_rsp_tag_par_out,
    output      [fcstat_width-1:0] o_fc0_rsp_fc_status_out,
    output     [fcxstat_width-1:0] o_fc0_rsp_fcx_status_out,
    output                   [7:0] o_fc0_rsp_scsi_status_out,
    output                         o_fc0_rsp_sns_valid_out,
    output                         o_fc0_rsp_fcp_valid_out,
    output                         o_fc0_rsp_underrun_out,
    output                         o_fc0_rsp_overrun_out,
    output                  [31:0] o_fc0_rsp_resid_out,
    output    [rsp_info_width-1:0] o_fc0_rsp_info_out,
    output      [beatid_width-1:0] o_fc0_rsp_rdata_beats_out,


    // FC module status events
    // --------------
    output      [status_width-1:0] o_fc0_status_event_out,
    output                         o_fc0_port_ready_out,
    output                         o_fc0_port_fatal_error_out,
    output                         o_fc0_port_enable_pe,

   
    // mmio interface
    // defined by PSL
    //   ha_mmval  - asserted for a single cycle. Other mm i/f signals are valid on this cycle.
    //   ha_mmrnw  - 1 = read, 0 = write
    //   ha_mmdw   - 1 = double word (64b), 0 = word (32 bits)
    //   ha_mmad   - 24b word address (aligned for doubleword access)
    //   ha_mmdata - 64b write data.  For word write, data will be replicated on both halves.
    //   ah_mmack  - asserted for 1 cycle to acknowledge that the write is complete or the
    //               read data is valid.  Ack is only asserted for addresses owned by this unit.
    //   ah_mmdata - read data.  For word reads, data should be supplied on both halves.
    input                          ha0_mmval_in,
    input                          ha0_mmcfg_in,
    input                          ha0_mmrnw_in,
    input                          ha0_mmdw_in,
    input                   [23:0] ha0_mmad_in,
    input                   [63:0] ha0_mmdata_in,
    output                         ah0_mmack_out,
    output                  [63:0] ah0_mmdata_out,
   
    // AFU/PSL interface port 1
    // -----------------

    // request command interface
    //  req_r    - ready
    //  req_v    - valid.  xfer occurs only if valid & ready, otherwise no xfer
    //  req_cmd  - command encode FCP_*
    //  req_tag  - identifier for the command
    //  req_lba  - logical block address
    //  req_lun  - logical unit number
    output                         i_fc1_req_r_out,
    input                          i_fc1_req_v_in,
    input          [cmd_width-1:0] i_fc1_req_cmd_in, 
    input          [tag_width-1:0] i_fc1_req_tag_in, 
    input      [tag_par_width-1:0] i_fc1_req_tag_par_in, 
    input        [lunid_width-1:0] i_fc1_req_lun_in, 
    input    [lunid_par_width-1:0] i_fc1_req_lun_par_in, 
    input                  [127:0] i_fc1_req_cdb_in, 
    input                    [1:0] i_fc1_req_cdb_par_in, 
    input      [datalen_width-1:0] i_fc1_req_length_in, 
    input                          i_fc1_req_length_par_in, 

    // write data request interface.  No backpressure?
    //   req_v    - valid
    //   req_beat - 32b word offset into wbuf. Must be sequential within 2K block
    output                         o_fc1_wdata_req_v_out,
    input                          o_fc1_wdata_req_r_in,
    output         [tag_width-1:0] o_fc1_wdata_req_tag_out,
    output     [tag_par_width-1:0] o_fc1_wdata_req_tag_par_out,
    output      [beatid_width-1:0] o_fc1_wdata_req_beat_out,
    output     [datalen_width-1:0] o_fc1_wdata_req_size_out,
    output [datalen_par_width-1:0] o_fc1_wdata_req_size_par_out,
    
    // data response interface (writes).  
    //
    input                          i_fc1_wdata_rsp_v_in,
    output                         i_fc1_wdata_rsp_r_out,
    input                          i_fc1_wdata_rsp_e_in,
    input                          i_fc1_wdata_rsp_error_in,
    input          [tag_width-1:0] i_fc1_wdata_rsp_tag_in,
    input                          i_fc1_wdata_rsp_tag_par_in,
    input       [beatid_width-1:0] i_fc1_wdata_rsp_beat_in,
    input         [data_width-1:0] i_fc1_wdata_rsp_data_in,
    input  [data_fc_par_width-1:0] i_fc1_wdata_rsp_data_par_in,

    // read data response interface
    //   rsp_v    - valid.
    //   rsp_r    - ready
    //   rsp_e    - read data end. Must be asserted with rsp_v after last data beat for a tag.
    //   rsp_c    - byte count for last word
    //   rsp_tag  - identifier of the corresponding read request
    //   rsp_beat - word offset for this data transfer
    //   rsp_data - 32b of read data.  Not used when rsp_e is assserted.
    // 
    output                         o_fc1_rdata_rsp_v_out,
    input                          o_fc1_rdata_rsp_r_in,
    output                         o_fc1_rdata_rsp_e_out,
    output       [bytec_width-1:0] o_fc1_rdata_rsp_c_out,
    output      [beatid_width-1:0] o_fc1_rdata_rsp_beat_out,
    output         [tag_width-1:0] o_fc1_rdata_rsp_tag_out,
    output     [tag_par_width-1:0] o_fc1_rdata_rsp_tag_par_out,
    output        [data_width-1:0] o_fc1_rdata_rsp_data_out,
    output [data_fc_par_width-1:0] o_fc1_rdata_rsp_data_par_out,

    // command response interface
    output                         o_fc1_rsp_v_out,
    output         [tag_width-1:0] o_fc1_rsp_tag_out,
    output     [tag_par_width-1:0] o_fc1_rsp_tag_par_out,
    output      [fcstat_width-1:0] o_fc1_rsp_fc_status_out,
    output     [fcxstat_width-1:0] o_fc1_rsp_fcx_status_out,
    output                   [7:0] o_fc1_rsp_scsi_status_out,
    output                         o_fc1_rsp_sns_valid_out,
    output                         o_fc1_rsp_fcp_valid_out,
    output                         o_fc1_rsp_underrun_out,
    output                         o_fc1_rsp_overrun_out,
    output                  [31:0] o_fc1_rsp_resid_out,
    output    [rsp_info_width-1:0] o_fc1_rsp_info_out,
    output      [beatid_width-1:0] o_fc1_rsp_rdata_beats_out,


    // FC module status events
    // --------------
    output      [status_width-1:0] o_fc1_status_event_out,
    output                         o_fc1_port_ready_out,
    output                         o_fc1_port_fatal_error_out,
    output                         o_fc1_port_enable_pe,


    //   ha_mmval  - asserted for a single cycle. Other mm i/f signals are valid on this cycle.
    //   ha_mmrnw  - 1 = read, 0 = write
    //   ha_mmdw   - 1 = double word (64b), 0 = word (32 bits)
    //   ha_mmad   - 24b word address (aligned for doubleword access)
    //   ha_mmdata - 64b write data.  For word write, data will be replicated on both halves.
    //   ah_mmack  - asserted for 1 cycle to acknowledge that the write is complete or the
    //               read data is valid.  Ack is only asserted for addresses owned by this unit.
    //   ah_mmdata - read data.  For word reads, data should be supplied on both halves.
    input                          ha1_mmval_in,
    input                          ha1_mmcfg_in,
    input                          ha1_mmrnw_in,
    input                          ha1_mmdw_in,
    input                   [23:0] ha1_mmad_in,
    input                   [63:0] ha1_mmdata_in,
    output                         ah1_mmack_out,
    output                  [63:0] ah1_mmdata_out,

    // AFU/PSL interface port 2
    // -----------------
   
    // request command interface
    //  req_r    - ready
    //  req_v    - valid.  xfer occurs only if valid & ready, otherwise no xfer
    //  req_cmd  - command encode FCP_*
    //  req_tag  - identifier for the command
    //  req_lba  - logical block address
    //  req_lun  - logical unit number
    output                         i_fc2_req_r_out,
    input                          i_fc2_req_v_in,
    input          [cmd_width-1:0] i_fc2_req_cmd_in, 
    input          [tag_width-1:0] i_fc2_req_tag_in, 
    input      [tag_par_width-1:0] i_fc2_req_tag_par_in, 
    input        [lunid_width-1:0] i_fc2_req_lun_in, 
    input    [lunid_par_width-1:0] i_fc2_req_lun_par_in, 
    input                  [127:0] i_fc2_req_cdb_in, 
    input                    [1:0] i_fc2_req_cdb_par_in, 
    input      [datalen_width-1:0] i_fc2_req_length_in, 
    input                          i_fc2_req_length_par_in, 

    // write data request interface.  No backpressure?
    //   req_v    - valid
    //   req_beat - 32b word offset into wbuf. Must be sequential within 2K block
    output                         o_fc2_wdata_req_v_out,
    input                          o_fc2_wdata_req_r_in,
    output         [tag_width-1:0] o_fc2_wdata_req_tag_out,
    output     [tag_par_width-1:0] o_fc2_wdata_req_tag_par_out,
    output      [beatid_width-1:0] o_fc2_wdata_req_beat_out,
    output     [datalen_width-1:0] o_fc2_wdata_req_size_out,
    output [datalen_par_width-1:0] o_fc2_wdata_req_size_par_out,
    
    // data response interface (writes).  
    //
    input                          i_fc2_wdata_rsp_v_in,
    output                         i_fc2_wdata_rsp_r_out,
    input                          i_fc2_wdata_rsp_e_in,
    input                          i_fc2_wdata_rsp_error_in,
    input          [tag_width-1:0] i_fc2_wdata_rsp_tag_in,
    input                          i_fc2_wdata_rsp_tag_par_in,
    input       [beatid_width-1:0] i_fc2_wdata_rsp_beat_in,
    input         [data_width-1:0] i_fc2_wdata_rsp_data_in,
    input  [data_fc_par_width-1:0] i_fc2_wdata_rsp_data_par_in,

    // read data response interface
    //   rsp_v    - valid.
    //   rsp_r    - ready
    //   rsp_e    - read data end. Must be asserted with rsp_v after last data beat for a tag.
    //   rsp_c    - byte count for last word
    //   rsp_tag  - identifier of the corresponding read request
    //   rsp_beat - word offset for this data transfer
    //   rsp_data - 32b of read data.  Not used when rsp_e is assserted.
    // 
    output                         o_fc2_rdata_rsp_v_out,
    input                          o_fc2_rdata_rsp_r_in,
    output                         o_fc2_rdata_rsp_e_out,
    output       [bytec_width-1:0] o_fc2_rdata_rsp_c_out,
    output      [beatid_width-1:0] o_fc2_rdata_rsp_beat_out,
    output         [tag_width-1:0] o_fc2_rdata_rsp_tag_out,
    output     [tag_par_width-1:0] o_fc2_rdata_rsp_tag_par_out,
    output        [data_width-1:0] o_fc2_rdata_rsp_data_out,
    output [data_fc_par_width-1:0] o_fc2_rdata_rsp_data_par_out,


    // command response interface
    output                         o_fc2_rsp_v_out,
    output         [tag_width-1:0] o_fc2_rsp_tag_out,
    output     [tag_par_width-1:0] o_fc2_rsp_tag_par_out,
    output      [fcstat_width-1:0] o_fc2_rsp_fc_status_out,
    output     [fcxstat_width-1:0] o_fc2_rsp_fcx_status_out,
    output                   [7:0] o_fc2_rsp_scsi_status_out,
    output                         o_fc2_rsp_sns_valid_out,
    output                         o_fc2_rsp_fcp_valid_out,
    output                         o_fc2_rsp_underrun_out,
    output                         o_fc2_rsp_overrun_out,
    output                  [31:0] o_fc2_rsp_resid_out,
    output    [rsp_info_width-1:0] o_fc2_rsp_info_out,
    output      [beatid_width-1:0] o_fc2_rsp_rdata_beats_out,

    // FC module status events
    // --------------
    output      [status_width-1:0] o_fc2_status_event_out,
    output                         o_fc2_port_ready_out,
    output                         o_fc2_port_fatal_error_out,
    output                         o_fc2_port_enable_pe,

   
    // mmio interface
    // defined by PSL
    //   ha_mmval  - asserted for a single cycle. Other mm i/f signals are valid on this cycle.
    //   ha_mmrnw  - 1 = read, 0 = write
    //   ha_mmdw   - 1 = double word (64b), 0 = word (32 bits)
    //   ha_mmad   - 24b word address (aligned for doubleword access)
    //   ha_mmdata - 64b write data.  For word write, data will be replicated on both halves.
    //   ah_mmack  - asserted for 1 cycle to acknowledge that the write is complete or the
    //               read data is valid.  Ack is only asserted for addresses owned by this unit.
    //   ah_mmdata - read data.  For word reads, data should be supplied on both halves.
    input                          ha2_mmval_in,
    input                          ha2_mmcfg_in,
    input                          ha2_mmrnw_in,
    input                          ha2_mmdw_in,
    input                   [23:0] ha2_mmad_in,
    input                   [63:0] ha2_mmdata_in,
    output                         ah2_mmack_out,
    output                  [63:0] ah2_mmdata_out,

    // AFU/PSL interface port 3
    // -----------------
   
    // request command interface
    //  req_r    - ready
    //  req_v    - valid.  xfer occurs only if valid & ready, otherwise no xfer
    //  req_cmd  - command encode FCP_*
    //  req_tag  - identifier for the command
    //  req_lba  - logical block address
    //  req_lun  - logical unit number
    output                         i_fc3_req_r_out,
    input                          i_fc3_req_v_in,
    input          [cmd_width-1:0] i_fc3_req_cmd_in, 
    input          [tag_width-1:0] i_fc3_req_tag_in, 
    input      [tag_par_width-1:0] i_fc3_req_tag_par_in, 
    input        [lunid_width-1:0] i_fc3_req_lun_in, 
    input    [lunid_par_width-1:0] i_fc3_req_lun_par_in, 
    input                  [127:0] i_fc3_req_cdb_in, 
    input                    [1:0] i_fc3_req_cdb_par_in, 
    input      [datalen_width-1:0] i_fc3_req_length_in, 
    input                          i_fc3_req_length_par_in, 

    // write data request interface.  No backpressure?
    //   req_v    - valid
    //   req_beat - 32b word offset into wbuf. Must be sequential within 2K block
    output                         o_fc3_wdata_req_v_out,
    input                          o_fc3_wdata_req_r_in,
    output         [tag_width-1:0] o_fc3_wdata_req_tag_out,
    output     [tag_par_width-1:0] o_fc3_wdata_req_tag_par_out,
    output      [beatid_width-1:0] o_fc3_wdata_req_beat_out,
    output     [datalen_width-1:0] o_fc3_wdata_req_size_out,
    output [datalen_par_width-1:0] o_fc3_wdata_req_size_par_out,
    
    // data response interface (writes).  
    //
    input                          i_fc3_wdata_rsp_v_in,
    output                         i_fc3_wdata_rsp_r_out,
    input                          i_fc3_wdata_rsp_e_in,
    input                          i_fc3_wdata_rsp_error_in,
    input          [tag_width-1:0] i_fc3_wdata_rsp_tag_in,
    input                          i_fc3_wdata_rsp_tag_par_in,
    input       [beatid_width-1:0] i_fc3_wdata_rsp_beat_in,
    input         [data_width-1:0] i_fc3_wdata_rsp_data_in,
    input  [data_fc_par_width-1:0] i_fc3_wdata_rsp_data_par_in,

    // read data response interface
    //   rsp_v    - valid.
    //   rsp_r    - ready
    //   rsp_e    - read data end. Must be asserted with rsp_v after last data beat for a tag.
    //   rsp_c    - byte count for last word
    //   rsp_tag  - identifier of the corresponding read request
    //   rsp_beat - word offset for this data transfer
    //   rsp_data - 32b of read data.  Not used when rsp_e is assserted.
    // 
    output                         o_fc3_rdata_rsp_v_out,
    input                          o_fc3_rdata_rsp_r_in,
    output                         o_fc3_rdata_rsp_e_out,
    output       [bytec_width-1:0] o_fc3_rdata_rsp_c_out,
    output      [beatid_width-1:0] o_fc3_rdata_rsp_beat_out,
    output         [tag_width-1:0] o_fc3_rdata_rsp_tag_out,
    output     [tag_par_width-1:0] o_fc3_rdata_rsp_tag_par_out,
    output        [data_width-1:0] o_fc3_rdata_rsp_data_out,
    output [data_fc_par_width-1:0] o_fc3_rdata_rsp_data_par_out,


    // command response interface
    output                         o_fc3_rsp_v_out,
    output         [tag_width-1:0] o_fc3_rsp_tag_out,
    output     [tag_par_width-1:0] o_fc3_rsp_tag_par_out,
    output      [fcstat_width-1:0] o_fc3_rsp_fc_status_out,
    output     [fcxstat_width-1:0] o_fc3_rsp_fcx_status_out,
    output                   [7:0] o_fc3_rsp_scsi_status_out,
    output                         o_fc3_rsp_sns_valid_out,
    output                         o_fc3_rsp_fcp_valid_out,
    output                         o_fc3_rsp_underrun_out,
    output                         o_fc3_rsp_overrun_out,
    output                  [31:0] o_fc3_rsp_resid_out,
    output    [rsp_info_width-1:0] o_fc3_rsp_info_out,
    output      [beatid_width-1:0] o_fc3_rsp_rdata_beats_out,

    // FC module status events
    // --------------
    output      [status_width-1:0] o_fc3_status_event_out,
    output                         o_fc3_port_ready_out,
    output                         o_fc3_port_fatal_error_out,
    output                         o_fc3_port_enable_pe,

   
    // mmio interface
    // defined by PSL
    //   ha_mmval  - asserted for a single cycle. Other mm i/f signals are valid on this cycle.
    //   ha_mmrnw  - 1 = read, 0 = write
    //   ha_mmdw   - 1 = double word (64b), 0 = word (32 bits)
    //   ha_mmad   - 24b word address (aligned for doubleword access)
    //   ha_mmdata - 64b write data.  For word write, data will be replicated on both halves.
    //   ah_mmack  - asserted for 1 cycle to acknowledge that the write is complete or the
    //               read data is valid.  Ack is only asserted for addresses owned by this unit.
    //   ah_mmdata - read data.  For word reads, data should be supplied on both halves.
    input                          ha3_mmval_in,
    input                          ha3_mmcfg_in,
    input                          ha3_mmrnw_in,
    input                          ha3_mmdw_in,
    input                   [23:0] ha3_mmad_in,
    input                   [63:0] ha3_mmdata_in,
    output                         ah3_mmack_out,
    output                  [63:0] ah3_mmdata_out,
   
    // NVMe PCI express port 0
    output        [LINK_WIDTH-1:0] pci_exp0_txp,
    output        [LINK_WIDTH-1:0] pci_exp0_txn,
    input         [LINK_WIDTH-1:0] pci_exp0_rxp,
    input         [LINK_WIDTH-1:0] pci_exp0_rxn,

    input                          pci_exp0_refclk_p,
    input                          pci_exp0_refclk_n,
    output                         pci_exp0_nperst,

    // NVMe PCI express port 1
    output        [LINK_WIDTH-1:0] pci_exp1_txp,
    output        [LINK_WIDTH-1:0] pci_exp1_txn,
    input         [LINK_WIDTH-1:0] pci_exp1_rxp,
    input         [LINK_WIDTH-1:0] pci_exp1_rxn,
    
    input                          pci_exp1_refclk_p,
    input                          pci_exp1_refclk_n,
    output                         pci_exp1_nperst,

    // NVMe PCI express port 2
    output        [LINK_WIDTH-1:0] pci_exp2_txp,
    output        [LINK_WIDTH-1:0] pci_exp2_txn,
    input         [LINK_WIDTH-1:0] pci_exp2_rxp,
    input         [LINK_WIDTH-1:0] pci_exp2_rxn,

    input                          pci_exp2_refclk_p,
    input                          pci_exp2_refclk_n,
    output                         pci_exp2_nperst,

    // NVMe PCI express port 3
    output        [LINK_WIDTH-1:0] pci_exp3_txp,
    output        [LINK_WIDTH-1:0] pci_exp3_txn,
    input         [LINK_WIDTH-1:0] pci_exp3_rxp,
    input         [LINK_WIDTH-1:0] pci_exp3_rxn,
    
    input                          pci_exp3_refclk_p,
    input                          pci_exp3_refclk_n,
    output                         pci_exp3_nperst

    );
   
   nvme_port#
     ( // afu/psl interface parameters
       .tag_width(tag_width), 
       .datalen_width(datalen_width),  
       .beatid_width(beatid_width),
       .data_width(data_width),
       .lunid_width(lunid_width),
       .cmd_width(cmd_width),
       .fcstat_width(fcstat_width),
       .fcxstat_width(fcxstat_width),
       .rsp_info_width(rsp_info_width),
       .status_width(status_width),
       .mmio_base(fc0_mmio_base),
       .mmio_base2(fc0_mmio_base2),
       .port_id(0)
   
       ) nvme_port0
       (

        .reset_in                           (reset_in),
        .clk                                (ha_pclock),
        .clk_div2                           (ha_pclock_div2),

        .led_red(led_red[0]),
        .led_green(led_green[0]),
        .led_blue(led_blue[0]),
               
        .i_req_r_out(i_fc0_req_r_out),
        .i_req_v_in(i_fc0_req_v_in),
        .i_req_cmd_in(i_fc0_req_cmd_in), 
        .i_req_tag_in(i_fc0_req_tag_in), 
        .i_req_tag_par_in(i_fc0_req_tag_par_in), 
        .i_req_lun_in(i_fc0_req_lun_in), 
        .i_req_lun_par_in(i_fc0_req_lun_par_in), 
        .i_req_cdb_in(i_fc0_req_cdb_in), 
        .i_req_cdb_par_in(i_fc0_req_cdb_par_in), 
        .i_req_length_in(i_fc0_req_length_in), 
        .i_req_length_par_in(i_fc0_req_length_par_in), 

        
        .o_wdata_req_v_out(o_fc0_wdata_req_v_out),
        .o_wdata_req_r_in(o_fc0_wdata_req_r_in),
        .o_wdata_req_tag_out(o_fc0_wdata_req_tag_out),
        .o_wdata_req_tag_par_out(o_fc0_wdata_req_tag_par_out),
        .o_wdata_req_beat_out(o_fc0_wdata_req_beat_out),
        .o_wdata_req_size_out(o_fc0_wdata_req_size_out),
        .o_wdata_req_size_par_out(o_fc0_wdata_req_size_par_out),
        
        
        .i_wdata_rsp_v_in(i_fc0_wdata_rsp_v_in),
        .i_wdata_rsp_r_out(i_fc0_wdata_rsp_r_out),
        .i_wdata_rsp_e_in(i_fc0_wdata_rsp_e_in),
        .i_wdata_rsp_error_in(i_fc0_wdata_rsp_error_in),
        .i_wdata_rsp_tag_in(i_fc0_wdata_rsp_tag_in),
        .i_wdata_rsp_tag_par_in(i_fc0_wdata_rsp_tag_par_in),
        .i_wdata_rsp_beat_in(i_fc0_wdata_rsp_beat_in),
        .i_wdata_rsp_data_in(i_fc0_wdata_rsp_data_in),
        .i_wdata_rsp_data_par_in(i_fc0_wdata_rsp_data_par_in),

        
        .o_rdata_rsp_v_out(o_fc0_rdata_rsp_v_out),
        .o_rdata_rsp_r_in(o_fc0_rdata_rsp_r_in),
        .o_rdata_rsp_e_out(o_fc0_rdata_rsp_e_out),
        .o_rdata_rsp_c_out(o_fc0_rdata_rsp_c_out),
        .o_rdata_rsp_beat_out(o_fc0_rdata_rsp_beat_out),
        .o_rdata_rsp_tag_out(o_fc0_rdata_rsp_tag_out),
        .o_rdata_rsp_tag_par_out(o_fc0_rdata_rsp_tag_par_out),
        .o_rdata_rsp_data_out(o_fc0_rdata_rsp_data_out),
        .o_rdata_rsp_data_par_out(o_fc0_rdata_rsp_data_par_out),


        .o_rsp_v_out(o_fc0_rsp_v_out),
        .o_rsp_tag_out(o_fc0_rsp_tag_out),
        .o_rsp_tag_par_out(o_fc0_rsp_tag_par_out),
        .o_rsp_fc_status_out(o_fc0_rsp_fc_status_out),
        .o_rsp_fcx_status_out(o_fc0_rsp_fcx_status_out),
        .o_rsp_scsi_status_out(o_fc0_rsp_scsi_status_out),
        .o_rsp_sns_valid_out(o_fc0_rsp_sns_valid_out),
        .o_rsp_fcp_valid_out(o_fc0_rsp_fcp_valid_out),
        .o_rsp_underrun_out(o_fc0_rsp_underrun_out),
        .o_rsp_overrun_out(o_fc0_rsp_overrun_out),
        .o_rsp_resid_out(o_fc0_rsp_resid_out),
        .o_rsp_info_out(o_fc0_rsp_info_out),
        .o_rsp_rdata_beats_out(o_fc0_rsp_rdata_beats_out),

        .o_status_event_out(o_fc0_status_event_out),
        .o_port_ready_out(o_fc0_port_ready_out),
        .o_port_fatal_error(o_fc0_port_fatal_error_out),
        .o_port_enable_pe(o_fc0_port_enable_pe),

        .pci_exp_txp         (pci_exp0_txp[LINK_WIDTH-1:0]),
        .pci_exp_txn         (pci_exp0_txn[LINK_WIDTH-1:0]),      
        .pci_exp_rxp         (pci_exp0_rxp[LINK_WIDTH-1:0]),
        .pci_exp_rxn         (pci_exp0_rxn[LINK_WIDTH-1:0]),
        .pci_exp_refclk_p    (pci_exp0_refclk_p),
        .pci_exp_refclk_n    (pci_exp0_refclk_n),
        .pci_exp_nperst      (pci_exp0_nperst),


        .i_fc_fatal_error(i_fc_fatal_error),
        
        
        // mmio interface from PSL
        .ha_mmval_in(ha0_mmval_in),
        .ha_mmcfg_in(ha0_mmcfg_in),
        .ha_mmrnw_in(ha0_mmrnw_in), 
        .ha_mmdw_in(ha0_mmdw_in), 
        .ha_mmad_in(ha0_mmad_in), 
        .ha_mmdata_in(ha0_mmdata_in),
        .ah_mmdata_out(ah0_mmdata_out),
        .ah_mmack_out(ah0_mmack_out)
        
        );
   

   nvme_port#
     ( // afu/psl interface parameters
       .tag_width(tag_width), 
       .datalen_width(datalen_width),  
       .beatid_width(beatid_width),
       .data_width(data_width),
       .lunid_width(lunid_width),
       .cmd_width(cmd_width),
       .fcstat_width(fcstat_width),
       .fcxstat_width(fcxstat_width),
       .rsp_info_width(rsp_info_width),
       .status_width(status_width),
      
       .mmio_base(fc1_mmio_base),
       .mmio_base2(fc1_mmio_base2),
       .port_id(1)       
       ) nvme_port1
       (

        .reset_in                           (reset_in),
        .clk                                (ha_pclock),
        .clk_div2                           (ha_pclock_div2),

   
        .led_red(led_red[1]),
        .led_green(led_green[1]),
        .led_blue(led_blue[1]),
               
        .i_req_r_out(i_fc1_req_r_out),
        .i_req_v_in(i_fc1_req_v_in),
        .i_req_cmd_in(i_fc1_req_cmd_in), 
        .i_req_tag_in(i_fc1_req_tag_in), 
        .i_req_tag_par_in(i_fc1_req_tag_par_in), 
        .i_req_lun_in(i_fc1_req_lun_in), 
        .i_req_lun_par_in(i_fc1_req_lun_par_in), 
        .i_req_cdb_in(i_fc1_req_cdb_in), 
        .i_req_cdb_par_in(i_fc1_req_cdb_par_in), 
        .i_req_length_in(i_fc1_req_length_in), 
        .i_req_length_par_in(i_fc1_req_length_par_in), 
        
        .o_wdata_req_v_out(o_fc1_wdata_req_v_out),
        .o_wdata_req_r_in(o_fc1_wdata_req_r_in),
        .o_wdata_req_tag_out(o_fc1_wdata_req_tag_out),
        .o_wdata_req_tag_par_out(o_fc1_wdata_req_tag_par_out),
        .o_wdata_req_beat_out(o_fc1_wdata_req_beat_out),
        .o_wdata_req_size_out(o_fc1_wdata_req_size_out),
        .o_wdata_req_size_par_out(o_fc1_wdata_req_size_par_out),
        
        .i_wdata_rsp_v_in(i_fc1_wdata_rsp_v_in),
        .i_wdata_rsp_r_out(i_fc1_wdata_rsp_r_out),
        .i_wdata_rsp_e_in(i_fc1_wdata_rsp_e_in),
        .i_wdata_rsp_error_in(i_fc1_wdata_rsp_error_in),
        .i_wdata_rsp_tag_in(i_fc1_wdata_rsp_tag_in),
        .i_wdata_rsp_tag_par_in(i_fc1_wdata_rsp_tag_par_in),
        .i_wdata_rsp_beat_in(i_fc1_wdata_rsp_beat_in),
        .i_wdata_rsp_data_in(i_fc1_wdata_rsp_data_in),
        .i_wdata_rsp_data_par_in(i_fc1_wdata_rsp_data_par_in),

        
        .o_rdata_rsp_v_out(o_fc1_rdata_rsp_v_out),
        .o_rdata_rsp_r_in(o_fc1_rdata_rsp_r_in),
        .o_rdata_rsp_e_out(o_fc1_rdata_rsp_e_out),
        .o_rdata_rsp_c_out(o_fc1_rdata_rsp_c_out),
        .o_rdata_rsp_beat_out(o_fc1_rdata_rsp_beat_out),
        .o_rdata_rsp_tag_out(o_fc1_rdata_rsp_tag_out),
        .o_rdata_rsp_tag_par_out(o_fc1_rdata_rsp_tag_par_out),
        .o_rdata_rsp_data_out(o_fc1_rdata_rsp_data_out),
        .o_rdata_rsp_data_par_out(o_fc1_rdata_rsp_data_par_out),

        .o_rsp_v_out(o_fc1_rsp_v_out),
        .o_rsp_tag_out(o_fc1_rsp_tag_out),
        .o_rsp_tag_par_out(o_fc1_rsp_tag_par_out),
        .o_rsp_fc_status_out(o_fc1_rsp_fc_status_out),
        .o_rsp_fcx_status_out(o_fc1_rsp_fcx_status_out),
        .o_rsp_scsi_status_out(o_fc1_rsp_scsi_status_out),
        .o_rsp_sns_valid_out(o_fc1_rsp_sns_valid_out),
        .o_rsp_fcp_valid_out(o_fc1_rsp_fcp_valid_out),
        .o_rsp_underrun_out(o_fc1_rsp_underrun_out),
        .o_rsp_overrun_out(o_fc1_rsp_overrun_out),
        .o_rsp_resid_out(o_fc1_rsp_resid_out),
        .o_rsp_info_out(o_fc1_rsp_info_out),
        .o_rsp_rdata_beats_out(o_fc1_rsp_rdata_beats_out),

        .o_status_event_out(o_fc1_status_event_out),
        .o_port_ready_out(o_fc1_port_ready_out),
        .o_port_fatal_error(o_fc1_port_fatal_error_out),
        .o_port_enable_pe(o_fc1_port_enable_pe),

        .pci_exp_txp         (pci_exp1_txp[LINK_WIDTH-1:0]),
        .pci_exp_txn         (pci_exp1_txn[LINK_WIDTH-1:0]),      
        .pci_exp_rxp         (pci_exp1_rxp[LINK_WIDTH-1:0]),
        .pci_exp_rxn         (pci_exp1_rxn[LINK_WIDTH-1:0]),
        .pci_exp_refclk_p    (pci_exp1_refclk_p),
        .pci_exp_refclk_n    (pci_exp1_refclk_n),
        .pci_exp_nperst      (pci_exp1_nperst),

        .i_fc_fatal_error(i_fc_fatal_error),     
          
        .ha_mmval_in(ha1_mmval_in),
        .ha_mmcfg_in(ha1_mmcfg_in),
        .ha_mmrnw_in(ha1_mmrnw_in), 
        .ha_mmdw_in(ha1_mmdw_in), 
        .ha_mmad_in(ha1_mmad_in), 
        .ha_mmdata_in(ha1_mmdata_in),
        .ah_mmdata_out(ah1_mmdata_out),
        .ah_mmack_out(ah1_mmack_out)

     
        );

   nvme_port#
     ( // afu/psl interface parameters
       .tag_width(tag_width), 
       .datalen_width(datalen_width),  
       .beatid_width(beatid_width),
       .data_width(data_width),
       .lunid_width(lunid_width),
       .cmd_width(cmd_width),
       .fcstat_width(fcstat_width),
       .fcxstat_width(fcxstat_width),
       .rsp_info_width(rsp_info_width),
       .status_width(status_width),
       .mmio_base(fc2_mmio_base),
       .mmio_base2(fc2_mmio_base2),
       .port_id(2)
   
       ) nvme_port2
       (

        .reset_in                           (reset_in),
        .clk                                (ha_pclock),
        .clk_div2                           (ha_pclock_div2),        

        .led_red(led_red[2]),
        .led_green(led_green[2]),
        .led_blue(led_blue[2]),
               
        .i_req_r_out(i_fc2_req_r_out),
        .i_req_v_in(i_fc2_req_v_in),
        .i_req_cmd_in(i_fc2_req_cmd_in), 
        .i_req_tag_in(i_fc2_req_tag_in), 
        .i_req_tag_par_in(i_fc2_req_tag_par_in), 
        .i_req_lun_in(i_fc2_req_lun_in), 
        .i_req_lun_par_in(i_fc2_req_lun_par_in), 
        .i_req_cdb_in(i_fc2_req_cdb_in), 
        .i_req_cdb_par_in(i_fc2_req_cdb_par_in), 
        .i_req_length_in(i_fc2_req_length_in), 
        .i_req_length_par_in(i_fc2_req_length_par_in), 

        
        .o_wdata_req_v_out(o_fc2_wdata_req_v_out),
        .o_wdata_req_r_in(o_fc2_wdata_req_r_in),
        .o_wdata_req_tag_out(o_fc2_wdata_req_tag_out),
        .o_wdata_req_tag_par_out(o_fc2_wdata_req_tag_par_out),
        .o_wdata_req_beat_out(o_fc2_wdata_req_beat_out),
        .o_wdata_req_size_out(o_fc2_wdata_req_size_out),
        .o_wdata_req_size_par_out(o_fc2_wdata_req_size_par_out),
        
        
        .i_wdata_rsp_v_in(i_fc2_wdata_rsp_v_in),
        .i_wdata_rsp_r_out(i_fc2_wdata_rsp_r_out),
        .i_wdata_rsp_e_in(i_fc2_wdata_rsp_e_in),
        .i_wdata_rsp_error_in(i_fc2_wdata_rsp_error_in),
        .i_wdata_rsp_tag_in(i_fc2_wdata_rsp_tag_in),
        .i_wdata_rsp_tag_par_in(i_fc2_wdata_rsp_tag_par_in),
        .i_wdata_rsp_beat_in(i_fc2_wdata_rsp_beat_in),
        .i_wdata_rsp_data_in(i_fc2_wdata_rsp_data_in),
        .i_wdata_rsp_data_par_in(i_fc2_wdata_rsp_data_par_in),

        
        .o_rdata_rsp_v_out(o_fc2_rdata_rsp_v_out),
        .o_rdata_rsp_r_in(o_fc2_rdata_rsp_r_in),
        .o_rdata_rsp_e_out(o_fc2_rdata_rsp_e_out),
        .o_rdata_rsp_c_out(o_fc2_rdata_rsp_c_out),
        .o_rdata_rsp_beat_out(o_fc2_rdata_rsp_beat_out),
        .o_rdata_rsp_tag_out(o_fc2_rdata_rsp_tag_out),
        .o_rdata_rsp_tag_par_out(o_fc2_rdata_rsp_tag_par_out),
        .o_rdata_rsp_data_out(o_fc2_rdata_rsp_data_out),
        .o_rdata_rsp_data_par_out(o_fc2_rdata_rsp_data_par_out),


        .o_rsp_v_out(o_fc2_rsp_v_out),
        .o_rsp_tag_out(o_fc2_rsp_tag_out),
        .o_rsp_tag_par_out(o_fc2_rsp_tag_par_out),
        .o_rsp_fc_status_out(o_fc2_rsp_fc_status_out),
        .o_rsp_fcx_status_out(o_fc2_rsp_fcx_status_out),
        .o_rsp_scsi_status_out(o_fc2_rsp_scsi_status_out),
        .o_rsp_sns_valid_out(o_fc2_rsp_sns_valid_out),
        .o_rsp_fcp_valid_out(o_fc2_rsp_fcp_valid_out),
        .o_rsp_underrun_out(o_fc2_rsp_underrun_out),
        .o_rsp_overrun_out(o_fc2_rsp_overrun_out),
        .o_rsp_resid_out(o_fc2_rsp_resid_out),
        .o_rsp_info_out(o_fc2_rsp_info_out),
        .o_rsp_rdata_beats_out(o_fc2_rsp_rdata_beats_out),

        .o_status_event_out(o_fc2_status_event_out),
        .o_port_ready_out(o_fc2_port_ready_out),
        .o_port_fatal_error(o_fc2_port_fatal_error_out),
        .o_port_enable_pe(o_fc2_port_enable_pe),


        .pci_exp_txp         (pci_exp2_txp[LINK_WIDTH-1:0]),
        .pci_exp_txn         (pci_exp2_txn[LINK_WIDTH-1:0]),      
        .pci_exp_rxp         (pci_exp2_rxp[LINK_WIDTH-1:0]),
        .pci_exp_rxn         (pci_exp2_rxn[LINK_WIDTH-1:0]),
        .pci_exp_refclk_p    (pci_exp2_refclk_p),
        .pci_exp_refclk_n    (pci_exp2_refclk_n),
        .pci_exp_nperst      (pci_exp2_nperst),


        .i_fc_fatal_error(i_fc_fatal_error),
        
        
        // mmio interface from PSL
        .ha_mmval_in(ha2_mmval_in),
        .ha_mmcfg_in(ha2_mmcfg_in),
        .ha_mmrnw_in(ha2_mmrnw_in), 
        .ha_mmdw_in(ha2_mmdw_in), 
        .ha_mmad_in(ha2_mmad_in), 
        .ha_mmdata_in(ha2_mmdata_in),
        .ah_mmdata_out(ah2_mmdata_out),
        .ah_mmack_out(ah2_mmack_out)
        
        );

   nvme_port#
     ( // afu/psl interface parameters
       .tag_width(tag_width), 
       .datalen_width(datalen_width),  
       .beatid_width(beatid_width),
       .data_width(data_width),
       .lunid_width(lunid_width),
       .cmd_width(cmd_width),
       .fcstat_width(fcstat_width),
       .fcxstat_width(fcxstat_width),
       .rsp_info_width(rsp_info_width),
       .status_width(status_width),
       .mmio_base(fc3_mmio_base),
       .mmio_base2(fc3_mmio_base2),
       .port_id(3)
   
       ) nvme_port3
       (

        .reset_in                           (reset_in),
        .clk                                (ha_pclock),
        .clk_div2                           (ha_pclock_div2),

        .led_red(led_red[3]),
        .led_green(led_green[3]),
        .led_blue(led_blue[3]),
               

        .i_req_r_out(i_fc3_req_r_out),
        .i_req_v_in(i_fc3_req_v_in),
        .i_req_cmd_in(i_fc3_req_cmd_in), 
        .i_req_tag_in(i_fc3_req_tag_in), 
        .i_req_tag_par_in(i_fc3_req_tag_par_in), 
        .i_req_lun_in(i_fc3_req_lun_in), 
        .i_req_lun_par_in(i_fc3_req_lun_par_in), 
        .i_req_cdb_in(i_fc3_req_cdb_in), 
        .i_req_cdb_par_in(i_fc3_req_cdb_par_in), 
        .i_req_length_in(i_fc3_req_length_in), 
        .i_req_length_par_in(i_fc3_req_length_par_in), 

        
        .o_wdata_req_v_out(o_fc3_wdata_req_v_out),
        .o_wdata_req_r_in(o_fc3_wdata_req_r_in),
        .o_wdata_req_tag_out(o_fc3_wdata_req_tag_out),
        .o_wdata_req_tag_par_out(o_fc3_wdata_req_tag_par_out),
        .o_wdata_req_beat_out(o_fc3_wdata_req_beat_out),
        .o_wdata_req_size_out(o_fc3_wdata_req_size_out),
        .o_wdata_req_size_par_out(o_fc3_wdata_req_size_par_out),
        
        
        .i_wdata_rsp_v_in(i_fc3_wdata_rsp_v_in),
        .i_wdata_rsp_r_out(i_fc3_wdata_rsp_r_out),
        .i_wdata_rsp_e_in(i_fc3_wdata_rsp_e_in),
        .i_wdata_rsp_error_in(i_fc3_wdata_rsp_error_in),
        .i_wdata_rsp_tag_in(i_fc3_wdata_rsp_tag_in),
        .i_wdata_rsp_tag_par_in(i_fc3_wdata_rsp_tag_par_in),
        .i_wdata_rsp_beat_in(i_fc3_wdata_rsp_beat_in),
        .i_wdata_rsp_data_in(i_fc3_wdata_rsp_data_in),
        .i_wdata_rsp_data_par_in(i_fc3_wdata_rsp_data_par_in),

        
        .o_rdata_rsp_v_out(o_fc3_rdata_rsp_v_out),
        .o_rdata_rsp_r_in(o_fc3_rdata_rsp_r_in),
        .o_rdata_rsp_e_out(o_fc3_rdata_rsp_e_out),
        .o_rdata_rsp_c_out(o_fc3_rdata_rsp_c_out),
        .o_rdata_rsp_beat_out(o_fc3_rdata_rsp_beat_out),
        .o_rdata_rsp_tag_out(o_fc3_rdata_rsp_tag_out),
        .o_rdata_rsp_tag_par_out(o_fc3_rdata_rsp_tag_par_out),
        .o_rdata_rsp_data_out(o_fc3_rdata_rsp_data_out),
        .o_rdata_rsp_data_par_out(o_fc3_rdata_rsp_data_par_out),


        .o_rsp_v_out(o_fc3_rsp_v_out),
        .o_rsp_tag_out(o_fc3_rsp_tag_out),
        .o_rsp_tag_par_out(o_fc3_rsp_tag_par_out),
        .o_rsp_fc_status_out(o_fc3_rsp_fc_status_out),
        .o_rsp_fcx_status_out(o_fc3_rsp_fcx_status_out),
        .o_rsp_scsi_status_out(o_fc3_rsp_scsi_status_out),
        .o_rsp_sns_valid_out(o_fc3_rsp_sns_valid_out),
        .o_rsp_fcp_valid_out(o_fc3_rsp_fcp_valid_out),
        .o_rsp_underrun_out(o_fc3_rsp_underrun_out),
        .o_rsp_overrun_out(o_fc3_rsp_overrun_out),
        .o_rsp_resid_out(o_fc3_rsp_resid_out),
        .o_rsp_info_out(o_fc3_rsp_info_out),
        .o_rsp_rdata_beats_out(o_fc3_rsp_rdata_beats_out),

        .o_status_event_out(o_fc3_status_event_out),
        .o_port_ready_out(o_fc3_port_ready_out),
        .o_port_fatal_error(o_fc3_port_fatal_error_out),
        .o_port_enable_pe(o_fc3_port_enable_pe),


        .pci_exp_txp         (pci_exp3_txp[LINK_WIDTH-1:0]),
        .pci_exp_txn         (pci_exp3_txn[LINK_WIDTH-1:0]),      
        .pci_exp_rxp         (pci_exp3_rxp[LINK_WIDTH-1:0]),
        .pci_exp_rxn         (pci_exp3_rxn[LINK_WIDTH-1:0]),
        .pci_exp_refclk_p    (pci_exp3_refclk_p),
        .pci_exp_refclk_n    (pci_exp3_refclk_n),
        .pci_exp_nperst      (pci_exp3_nperst),

        .i_fc_fatal_error(i_fc_fatal_error),
        
        
        // mmio interface from PSL
        .ha_mmval_in(ha3_mmval_in),
        .ha_mmcfg_in(ha3_mmcfg_in),
        .ha_mmrnw_in(ha3_mmrnw_in), 
        .ha_mmdw_in(ha3_mmdw_in), 
        .ha_mmad_in(ha3_mmad_in), 
        .ha_mmdata_in(ha3_mmdata_in),
        .ah_mmdata_out(ah3_mmdata_out),
        .ah_mmack_out(ah3_mmack_out)

        
        );

   

endmodule 
