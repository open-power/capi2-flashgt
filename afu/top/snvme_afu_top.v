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
`include "afu_version.svh"

module snvme_afu_top#
  (
   parameter fc_tag_width    = 8,   // per port tag width
   parameter tag_width       = 10,   // afu tag width changed 9 to 10 to add parity kch 
   parameter datalen_width   = 25,  // max 16M transfer
   parameter data_width      = 128, // change fc width from 32 to 128 kch 01/04/16
   parameter data_par_width  = (data_width + 63) / 64,
   parameter data_bytes      = data_width/8,
   parameter bytec_width     = $clog2(data_bytes+1),
   parameter beatid_width    = datalen_width-$clog2(data_bytes),  
   parameter lba_width       = 48,
   parameter lunid_width     = 64,
   parameter lunid_width_w_par     = 65,
   parameter cmd_width       = 4,
   parameter fcstat_width    = 8,
   parameter fcxstat_width   = 8,   
   parameter rsp_info_width  = 160,
   parameter fc_tag_par_width   = (fc_tag_width + 63)/64, 
   parameter lunid_par_width = (lunid_width + 63)/64, 
   parameter ctxtid_width    = 10,
   parameter fc_status_width = 8,
   
   parameter LINK_WIDTH = 4

   )
  (
    
   // global reset needed for sim
   input                   i_reset,

   output            [3:0] led_red,
   output            [3:0] led_green,
   output            [3:0] led_blue,

   // NVMe PCI express port 0
   output [LINK_WIDTH-1:0] pci_exp0_txp,
   output [LINK_WIDTH-1:0] pci_exp0_txn,
   input  [LINK_WIDTH-1:0] pci_exp0_rxp,
   input  [LINK_WIDTH-1:0] pci_exp0_rxn,

   input                   pci_exp0_refclk_p,
   input                   pci_exp0_refclk_n,
   output                  pci_exp0_nperst,
   output                  pci_exp0_susclk,
   inout                   pci_exp0_npewake,
   inout                   pci_exp0_nclkreq,
   
    // NVMe PCI express port 1
   output [LINK_WIDTH-1:0] pci_exp1_txp,
   output [LINK_WIDTH-1:0] pci_exp1_txn,
   input  [LINK_WIDTH-1:0] pci_exp1_rxp,
   input  [LINK_WIDTH-1:0] pci_exp1_rxn,
    
   input                   pci_exp1_refclk_p,
   input                   pci_exp1_refclk_n,
   output                  pci_exp1_nperst,
   output                  pci_exp1_susclk,
   inout                   pci_exp1_npewake,
   inout                   pci_exp1_nclkreq,

   // NVMe PCI express port 2
   output [LINK_WIDTH-1:0] pci_exp2_txp,
   output [LINK_WIDTH-1:0] pci_exp2_txn,
   input  [LINK_WIDTH-1:0] pci_exp2_rxp,
   input  [LINK_WIDTH-1:0] pci_exp2_rxn,

   input                   pci_exp2_refclk_p,
   input                   pci_exp2_refclk_n,
   output                  pci_exp2_nperst,
   output                  pci_exp2_susclk,
   inout                   pci_exp2_npewake,
   inout                   pci_exp2_nclkreq,
   
    // NVMe PCI express port 3
   output [LINK_WIDTH-1:0] pci_exp3_txp,
   output [LINK_WIDTH-1:0] pci_exp3_txn,
   input  [LINK_WIDTH-1:0] pci_exp3_rxp,
   input  [LINK_WIDTH-1:0] pci_exp3_rxn,
    
   input                   pci_exp3_refclk_p,
   input                   pci_exp3_refclk_n,
   output                  pci_exp3_nperst,
   output                  pci_exp3_susclk,
   inout                   pci_exp3_npewake,
   inout                   pci_exp3_nclkreq,

   output                  o_reset,
      
   // psl I/Os                        
//   `include "psl_io_decls.inc"

   output                  ah_paren,
    
   input                   ha_jval, // A valid job control command is present
   input             [0:7] ha_jcom, // Job control command opcode
   input                   ha_jcompar,
   input            [0:63] ha_jea, // Save/Restore address  added parity checking kch 
   input                   ha_jeapar,
   output                  ah_jrunning, // Accelerator is running
   output                  ah_jdone, // Accelerator is finished
   output           [0:63] ah_jerror, // Accelerator error code. 0 = success
   output                  ah_tbreq, // timebase request (not used)
//   output                  ah_jyield, // Accelerator wants to stop

   // Accelerator Command Interface
   output                  ah_cvalid, // A valid command is present
   output            [0:7] ah_ctag, // request id  no parity for now kch not much coverage 
   output                  ah_ctagpar,
   output           [0:12] ah_com, // command PSL will execute    no parity for now will revisit todo kch 
   output                  ah_compar,
//   output            [0:2] ah_cpad, // prefetch inattributes
   output            [0:2] ah_cabt, // abort if translation intr is generated
   output           [0:63] ah_cea, // Effective byte address for command     
   output                  ah_ceapar,
   output           [0:11] ah_csize, // Number of bytes
   output            [0:3] ah_cpagesize,
   output           [0:15] ah_cch, // context handle
   output                  ah_jcack,
   input             [0:7] ha_croom, // Commands PSL is prepared to accept
   input                   ha_pclock, // 250MHz clock
// DMA Interface 

   output                  d0h_dvalid, 
   output            [0:9] d0h_req_utag, 
   output            [0:8] d0h_req_itag, 
   output            [0:2] d0h_dtype, 
   output            [0:9] d0h_dsize, 
   output            [0:5] d0h_datomic_op, 
   output                  d0h_datomic_le, 
   output         [0:1023] d0h_ddata,

   input                   hd0_sent_utag_valid, 
   input             [0:9] hd0_sent_utag, 
   input             [0:2] hd0_sent_utag_sts, 

   input                   hd0_cpl_valid,
   input             [0:9] hd0_cpl_utag,
   input             [0:2] hd0_cpl_type,
   input             [0:6] hd0_cpl_laddr,
   input             [0:9] hd0_cpl_byte_count,
   input             [0:9] hd0_cpl_size,
   input          [0:1023] hd0_cpl_data,

   //x PSL Response Interface
   input                   ha_rvalid, // A response is present
   input             [0:7] ha_rtag, // Accelerator generated request ID  not implementing parity yet kch 
   input                   ha_rtagpar, 
   input             [0:8] ha_rditag, // Accelerator generated request ID  not implementing parity yet kch 
   input                   ha_rditagpar, 
   input             [0:7] ha_response, // response code
   input             [0:8] ha_rcredits, // twos compliment number of credits
   input             [0:1] ha_rcachestate, // Resultant Cache State
   input            [0:12] ha_rcachepos, // Cache location id
   input             [0:7] ha_response_ext,
   input             [0:3] ha_rpagesize,

   // Accelerator MMIO Interface
   input                   ha_mmval, // A valid MMIO is present
   input                   ha_mmrnw, // 1 = read, 0 = write
   input                   ha_mmdw, // 1 = doubleword, 0 = word
   input            [0:23] ha_mmad, // mmio address
   input                   ha_mmadpar,
   input                   ha_mmcfg, // mmio is to afu descriptor space
   input            [0:63] ha_mmdata, // Write data
   input                   ha_mmdatapar,
   output                  ah_mmack, // Write is complete or Read is valid
   output           [0:63] ah_mmdata, // Read data
   output                  ah_mmdatapar,

   input                   ha_pclock_div2,
   input                   pci_user_reset,
   output                  gold_factory
   );  

`ifdef LITTLE_ENDIAN
   localparam szl = 1;
`else
   localparam szl = 0;
`endif
	
   wire              [0:2] ah_cpad;
	    
   wire                        fc0_req_r;
   wire                        fc0_req_v;
   wire [       cmd_width-1:0] fc0_req_cmd;
   wire [    fc_tag_width-1:0] fc0_req_tag;
   wire [fc_tag_par_width-1:0] fc0_req_tag_par;
   wire [     lunid_width-1:0] fc0_req_lun;
   wire [ lunid_par_width-1:0] fc0_req_lun_par;
   wire [               127:0] fc0_req_cdb;
   wire [                 1:0] fc0_req_cdb_par;    // added kch 
   wire [   datalen_width-1:0] fc0_req_length;
   
   wire                        fc0_wdata_req_v;
   wire                        fc0_wdata_req_r;
   wire [    fc_tag_width-1:0] fc0_wdata_req_tag;
   wire [fc_tag_par_width-1:0] fc0_wdata_req_tag_par;   
   wire [    beatid_width-1:0] fc0_wdata_req_beat;
   wire [   datalen_width-1:0] fc0_wdata_req_size;
   wire                        fc0_wdata_req_size_par; // added kch 
   
   wire                        fc0_wdata_rsp_v;
   wire                        fc0_wdata_rsp_r;
   wire                        fc0_wdata_rsp_e;
   wire                        fc0_wdata_rsp_error;
   wire [    fc_tag_width-1:0] fc0_wdata_rsp_tag;
   wire [    fc_tag_par_width-1:0] fc0_wdata_rsp_tag_par;   // added kch need to add input in svme kch 
   wire [    beatid_width-1:0] fc0_wdata_rsp_beat;
   wire [      data_width-1:0] fc0_wdata_rsp_data;
   wire [  data_par_width-1:0] fc0_wdata_rsp_data_par;
   
   
   wire                        fc0_rdata_rsp_v;
   wire                        fc0_rdata_rsp_r;
   wire                        fc0_rdata_rsp_e;
   wire [     bytec_width-1:0] fc0_rdata_rsp_c;
   wire [    beatid_width-1:0] fc0_rdata_rsp_beat;
   wire [    fc_tag_width-1:0] fc0_rdata_rsp_tag;
   wire [    fc_tag_par_width-1:0] fc0_rdata_rsp_tag_par;
   wire [      data_width-1:0] fc0_rdata_rsp_data;
   wire [  data_par_width-1:0] fc0_rdata_rsp_data_par;
  //  wire [  data_par_width-1:0] fc0_rdata_rsp_data_par_kch;
   
   wire                        fc0_rsp_v;
   wire [    fc_tag_width-1:0] fc0_rsp_tag;
   wire [fc_tag_par_width-1:0] fc0_rsp_tag_par;
   wire [    fcstat_width-1:0] fc0_rsp_fc_status;
   wire [   fcxstat_width-1:0] fc0_rsp_fcx_status;
   wire [                 7:0] fc0_rsp_scsi_status;
   wire                        fc0_rsp_sns_valid;
   wire                        fc0_rsp_fcp_valid;
   wire                        fc0_rsp_underrun;
   wire                        fc0_rsp_overrun;
   wire [                31:0] fc0_rsp_resid;
   wire [  rsp_info_width-1:0] fc0_rsp_info;
   wire [    beatid_width-1:0] fc0_rsp_rdata_beats;

   wire [ fc_status_width-1:0] fc0_status_event;
   wire                        fc0_port_ready;
   wire                        fc0_nvme_port_fatal_error;

   wire                        fc0_rxp;
   wire                        fc0_txp;
   wire                        fc0_ha_mmval;
   wire                        fc0_ha_mmcfg;
   wire                        fc0_ha_mmrnw;
   wire                        fc0_ha_mmdw;
   wire [                23:0] fc0_ha_mmad;
   wire [                63:0] fc0_ha_mmdata;
   wire                        fc0_ah_mmack;
   wire [                63:0] fc0_ah_mmdata;

   wire                        fc1_req_r;
   wire                        fc1_req_v;
   wire [       cmd_width-1:0] fc1_req_cmd;
   wire [    fc_tag_width-1:0] fc1_req_tag;
   wire [fc_tag_par_width-1:0] fc1_req_tag_par;
   wire [     lunid_width-1:0] fc1_req_lun;
   wire [ lunid_par_width-1:0] fc1_req_lun_par;
   wire [               127:0] fc1_req_cdb;
   wire [                 1:0] fc1_req_cdb_par;    // added kch 
   wire [   datalen_width-1:0] fc1_req_length;
   
   wire                        fc1_wdata_req_v;
   wire                        fc1_wdata_req_r;
   wire [    fc_tag_width-1:0] fc1_wdata_req_tag;
   wire [fc_tag_par_width-1:0] fc1_wdata_req_tag_par;    
   wire [    beatid_width-1:0] fc1_wdata_req_beat;
   wire [   datalen_width-1:0] fc1_wdata_req_size;
   wire                        fc1_wdata_req_size_par;
   
   wire                        fc1_wdata_rsp_v;
   wire                        fc1_wdata_rsp_r;
   wire                        fc1_wdata_rsp_e;
   wire                        fc1_wdata_rsp_error;
   wire [    fc_tag_width-1:0] fc1_wdata_rsp_tag;
    wire [    fc_tag_par_width-1:0] fc1_wdata_rsp_tag_par;   // added kch need to add input in svme kch 
  wire [    beatid_width-1:0] fc1_wdata_rsp_beat;
   wire [      data_width-1:0] fc1_wdata_rsp_data;
   wire [  data_par_width-1:0] fc1_wdata_rsp_data_par;
   
   
   wire                        fc1_rdata_rsp_v;
   wire                        fc1_rdata_rsp_r;
   wire                        fc1_rdata_rsp_e;
   wire [     bytec_width-1:0] fc1_rdata_rsp_c;
   wire [    beatid_width-1:0] fc1_rdata_rsp_beat;
   wire [    fc_tag_width-1:0] fc1_rdata_rsp_tag;
   wire [    fc_tag_par_width-1:0] fc1_rdata_rsp_tag_par;
   wire [      data_width-1:0] fc1_rdata_rsp_data;
   wire [  data_par_width-1:0] fc1_rdata_rsp_data_par;
// wire [  data_par_width-1:0] fc1_rdata_rsp_data_par_kch;
  
   wire                        fc1_rsp_v;
   wire [    fc_tag_width-1:0] fc1_rsp_tag;
   wire [fc_tag_par_width-1:0] fc1_rsp_tag_par;
   wire [    fcstat_width-1:0] fc1_rsp_fc_status;
   wire [   fcxstat_width-1:0] fc1_rsp_fcx_status;
   wire [                 7:0] fc1_rsp_scsi_status;
   wire                        fc1_rsp_sns_valid;
   wire                        fc1_rsp_fcp_valid;
   wire                        fc1_rsp_underrun;
   wire                        fc1_rsp_overrun;
   wire [                31:0] fc1_rsp_resid;
   wire [  rsp_info_width-1:0] fc1_rsp_info;
   wire [    beatid_width-1:0] fc1_rsp_rdata_beats;

   wire [ fc_status_width-1:0] fc1_status_event;
   wire                        fc1_port_ready;
   wire                        fc1_nvme_port_fatal_error;

   wire                        fc1_rxp;
   wire                        fc1_txp;
   wire                        fc1_ha_mmval;
   wire                        fc1_ha_mmcfg;
   wire                        fc1_ha_mmrnw;
   wire                        fc1_ha_mmdw;
   wire [                23:0] fc1_ha_mmad;
   wire [                63:0] fc1_ha_mmdata;
   wire                        fc1_ah_mmack;
   wire [                63:0] fc1_ah_mmdata;

   wire                        fc2_req_r;
   wire                        fc2_req_v;
   wire [       cmd_width-1:0] fc2_req_cmd;
   wire [    fc_tag_width-1:0] fc2_req_tag;
   wire [fc_tag_par_width-1:0] fc2_req_tag_par;
   wire [     lunid_width-1:0] fc2_req_lun;
   wire [ lunid_par_width-1:0] fc2_req_lun_par;
   wire [               127:0] fc2_req_cdb;
   wire [                 1:0] fc2_req_cdb_par;    // added kch 
   wire [   datalen_width-1:0] fc2_req_length;
   wire                        fc2_wdata_req_v;
   wire                        fc2_wdata_req_r;
   wire [    fc_tag_width-1:0] fc2_wdata_req_tag;
   wire [fc_tag_par_width-1:0] fc2_wdata_req_tag_par;   
   wire [    beatid_width-1:0] fc2_wdata_req_beat;
   wire [   datalen_width-1:0] fc2_wdata_req_size;
   wire                        fc2_wdata_req_size_par; // added kch 
   wire                        fc2_wdata_rsp_v;
   wire                        fc2_wdata_rsp_r;
   wire                        fc2_wdata_rsp_e;
   wire                        fc2_wdata_rsp_error;
   wire [    fc_tag_width-1:0] fc2_wdata_rsp_tag;
   wire [    fc_tag_par_width-1:0] fc2_wdata_rsp_tag_par;   // added kch need to add input in svme kch 
   wire [    beatid_width-1:0] fc2_wdata_rsp_beat;
   wire [      data_width-1:0] fc2_wdata_rsp_data;
   wire [  data_par_width-1:0] fc2_wdata_rsp_data_par;
   wire                        fc2_rdata_rsp_v;
   wire                        fc2_rdata_rsp_r;
   wire                        fc2_rdata_rsp_e;
   wire [     bytec_width-1:0] fc2_rdata_rsp_c;
   wire [    beatid_width-1:0] fc2_rdata_rsp_beat;
   wire [    fc_tag_width-1:0] fc2_rdata_rsp_tag;
   wire [    fc_tag_par_width-1:0] fc2_rdata_rsp_tag_par;
   wire [      data_width-1:0] fc2_rdata_rsp_data;
   wire [  data_par_width-1:0] fc2_rdata_rsp_data_par;
  //  wire [  data_par_width-1:0] fc2_rdata_rsp_data_par_kch;
   wire                        fc2_rsp_v;
   wire [    fc_tag_width-1:0] fc2_rsp_tag;
   wire [fc_tag_par_width-1:0] fc2_rsp_tag_par;
   wire [    fcstat_width-1:0] fc2_rsp_fc_status;
   wire [   fcxstat_width-1:0] fc2_rsp_fcx_status;
   wire [                 7:0] fc2_rsp_scsi_status;
   wire                        fc2_rsp_sns_valid;
   wire                        fc2_rsp_fcp_valid;
   wire                        fc2_rsp_underrun;
   wire                        fc2_rsp_overrun;
   wire [                31:0] fc2_rsp_resid;
   wire [  rsp_info_width-1:0] fc2_rsp_info;
   wire [    beatid_width-1:0] fc2_rsp_rdata_beats;
   wire [ fc_status_width-1:0] fc2_status_event;
   wire                        fc2_port_ready;
   wire                        fc2_nvme_port_fatal_error;
   wire                        fc2_rxp;
   wire                        fc2_txp;
   wire                        fc2_ha_mmval;
   wire                        fc2_ha_mmcfg;
   wire                        fc2_ha_mmrnw;
   wire                        fc2_ha_mmdw;
   wire [                23:0] fc2_ha_mmad;
   wire [                63:0] fc2_ha_mmdata;
   wire                        fc2_ah_mmack;
   wire [                63:0] fc2_ah_mmdata;

   wire                        fc3_req_r;
   wire                        fc3_req_v;
   wire [       cmd_width-1:0] fc3_req_cmd;
   wire [    fc_tag_width-1:0] fc3_req_tag;
   wire [fc_tag_par_width-1:0] fc3_req_tag_par;
   wire [     lunid_width-1:0] fc3_req_lun;
   wire [ lunid_par_width-1:0] fc3_req_lun_par;
   wire [               127:0] fc3_req_cdb;
   wire [                 1:0] fc3_req_cdb_par;    // added kch 
   wire [   datalen_width-1:0] fc3_req_length;
   wire                        fc3_wdata_req_v;
   wire                        fc3_wdata_req_r;
   wire [    fc_tag_width-1:0] fc3_wdata_req_tag;
   wire [fc_tag_par_width-1:0] fc3_wdata_req_tag_par;    
   wire [    beatid_width-1:0] fc3_wdata_req_beat;
   wire [   datalen_width-1:0] fc3_wdata_req_size;
   wire                        fc3_wdata_req_size_par;
   wire                        fc3_wdata_rsp_v;
   wire                        fc3_wdata_rsp_r;
   wire                        fc3_wdata_rsp_e;
   wire                        fc3_wdata_rsp_error;
   wire [    fc_tag_width-1:0] fc3_wdata_rsp_tag;
    wire [    fc_tag_par_width-1:0] fc3_wdata_rsp_tag_par;   // added kch need to add input in svme kch 
  wire [    beatid_width-1:0] fc3_wdata_rsp_beat;
   wire [      data_width-1:0] fc3_wdata_rsp_data;
   wire [  data_par_width-1:0] fc3_wdata_rsp_data_par;
   wire                        fc3_rdata_rsp_v;
   wire                        fc3_rdata_rsp_r;
   wire                        fc3_rdata_rsp_e;
   wire [     bytec_width-1:0] fc3_rdata_rsp_c;
   wire [    beatid_width-1:0] fc3_rdata_rsp_beat;
   wire [    fc_tag_width-1:0] fc3_rdata_rsp_tag;
   wire [    fc_tag_par_width-1:0] fc3_rdata_rsp_tag_par;
   wire [      data_width-1:0] fc3_rdata_rsp_data;
   wire [  data_par_width-1:0] fc3_rdata_rsp_data_par;
// wire [  data_par_width-1:0] fc3_rdata_rsp_data_par_kch;
   wire                        fc3_rsp_v;
   wire [    fc_tag_width-1:0] fc3_rsp_tag;
   wire [fc_tag_par_width-1:0] fc3_rsp_tag_par;
   wire [    fcstat_width-1:0] fc3_rsp_fc_status;
   wire [   fcxstat_width-1:0] fc3_rsp_fcx_status;
   wire [                 7:0] fc3_rsp_scsi_status;
   wire                        fc3_rsp_sns_valid;
   wire                        fc3_rsp_fcp_valid;
   wire                        fc3_rsp_underrun;
   wire                        fc3_rsp_overrun;
   wire [                31:0] fc3_rsp_resid;
   wire [  rsp_info_width-1:0] fc3_rsp_info;
   wire [    beatid_width-1:0] fc3_rsp_rdata_beats;
   wire [ fc_status_width-1:0] fc3_status_event;
   wire                        fc3_port_ready;
   wire                        fc3_nvme_port_fatal_error;
   wire                        fc3_rxp;
   wire                        fc3_txp;
   wire                        fc3_ha_mmval;
   wire                        fc3_ha_mmcfg;
   wire                        fc3_ha_mmrnw;
   wire                        fc3_ha_mmdw;
   wire [                23:0] fc3_ha_mmad;
   wire [                63:0] fc3_ha_mmdata;
   wire                        fc3_ah_mmack;
   wire [                63:0] fc3_ah_mmdata;

   wire                        reset;
   wire                        fc_fatal_error;
   wire                        fc0_port_fatal_error;
   wire                        fc1_port_fatal_error;
   wire                        fc2_port_fatal_error;
   wire                        fc3_port_fatal_error;
   wire                        fc0_port_enable_pe;
   wire                        fc1_port_enable_pe;
   wire                        fc2_port_enable_pe;
   wire                        fc3_port_enable_pe;


// drive "gold_factory" 1 for user image
// use a register with initial value to allow modifying bitstream without rerunning

   (* dont_touch = "yes" *)
   `ifdef FACTORY_IMAGE
   reg  user_image_q = 1'b0;
   `else
   reg  user_image_q = 1'b1;
   `endif
   
   always @(posedge ha_pclock) user_image_q <= user_image_q;   
   assign gold_factory = user_image_q;

// set AFU version string from include file
// use register to allow modification in bitstream
   (* dont_touch = "yes" *)
   reg                  [0:63] afu_version_q =  `AFU_VERSION_NUMBER;     
   always @(posedge ha_pclock) afu_version_q <= afu_version_q;   

   
   nvme_top#
     (
      .tag_width        (fc_tag_width),
      .datalen_width    (datalen_width),
      .beatid_width     (beatid_width),
      .data_width       (data_width),
      .lunid_width      (lunid_width),
      .cmd_width        (cmd_width),
      .fcstat_width     (fcstat_width),
      .fcxstat_width    (fcxstat_width),
      .status_width     (fc_status_width),
      .tag_par_width    (fc_tag_par_width),
      .lunid_par_width  (lunid_par_width),
      .data_par_width   (data_par_width)
      )
   nvme_top
     (
      .ha_pclock(ha_pclock),
      .ha_pclock_div2(ha_pclock_div2),

      .reset_in(reset),

      .i_fc_fatal_error(fc_fatal_error),

      // LEDs
      .led_red(led_red),
      .led_green(led_green),
      .led_blue(led_blue),
      
      .i_fc0_req_r_out(fc0_req_r),
      .i_fc0_req_v_in(fc0_req_v),
      .i_fc0_req_cmd_in(fc0_req_cmd),
      .i_fc0_req_tag_in(fc0_req_tag),
      .i_fc0_req_tag_par_in(fc0_req_tag_par),
      .i_fc0_req_lun_in(fc0_req_lun),
      .i_fc0_req_lun_par_in(fc0_req_lun_par),
      .i_fc0_req_cdb_in(fc0_req_cdb),
      .i_fc0_req_cdb_par_in(fc0_req_cdb_par),
//      .i_fc0_req_cdb_in(fc0_req_cdb),    //fixit  nnedd to add and connect????
      .i_fc0_req_length_in(fc0_req_length),
      .i_fc0_req_length_par_in(fc0_req_length_par),

      .o_fc0_wdata_req_v_out(fc0_wdata_req_v),
      .o_fc0_wdata_req_r_in(fc0_wdata_req_r),
      .o_fc0_wdata_req_tag_out(fc0_wdata_req_tag),
      .o_fc0_wdata_req_tag_par_out(fc0_wdata_req_tag_par),
      .o_fc0_wdata_req_beat_out(fc0_wdata_req_beat),
      .o_fc0_wdata_req_size_out(fc0_wdata_req_size),
      .o_fc0_wdata_req_size_par_out(fc0_wdata_req_size_par),
      
      .i_fc0_wdata_rsp_v_in(fc0_wdata_rsp_v),
      .i_fc0_wdata_rsp_r_out(fc0_wdata_rsp_r),
      .i_fc0_wdata_rsp_e_in(fc0_wdata_rsp_e),
      .i_fc0_wdata_rsp_error_in(fc0_wdata_rsp_error),      
      .i_fc0_wdata_rsp_tag_in(fc0_wdata_rsp_tag),
      .i_fc0_wdata_rsp_tag_par_in(fc0_wdata_rsp_tag_par),
      .i_fc0_wdata_rsp_beat_in(fc0_wdata_rsp_beat),
      .i_fc0_wdata_rsp_data_in(fc0_wdata_rsp_data),
      .i_fc0_wdata_rsp_data_par_in(fc0_wdata_rsp_data_par),
      
      .o_fc0_rdata_rsp_v_out(fc0_rdata_rsp_v),
      .o_fc0_rdata_rsp_r_in(fc0_rdata_rsp_r),
      .o_fc0_rdata_rsp_e_out(fc0_rdata_rsp_e),     
      .o_fc0_rdata_rsp_c_out(fc0_rdata_rsp_c),     
      .o_fc0_rdata_rsp_beat_out(fc0_rdata_rsp_beat),
      .o_fc0_rdata_rsp_tag_out(fc0_rdata_rsp_tag),
      .o_fc0_rdata_rsp_tag_par_out(fc0_rdata_rsp_tag_par),
      .o_fc0_rdata_rsp_data_out(fc0_rdata_rsp_data),
      .o_fc0_rdata_rsp_data_par_out(fc0_rdata_rsp_data_par),

      .o_fc0_rsp_v_out(fc0_rsp_v),
      .o_fc0_rsp_tag_out(fc0_rsp_tag),
      .o_fc0_rsp_tag_par_out(fc0_rsp_tag_par),
      .o_fc0_rsp_fc_status_out(fc0_rsp_fc_status),
      .o_fc0_rsp_fcx_status_out(fc0_rsp_fcx_status),
      .o_fc0_rsp_scsi_status_out(fc0_rsp_scsi_status),
      .o_fc0_rsp_sns_valid_out(fc0_rsp_sns_valid),
      .o_fc0_rsp_fcp_valid_out(fc0_rsp_fcp_valid),
      .o_fc0_rsp_underrun_out(fc0_rsp_underrun),
      .o_fc0_rsp_overrun_out(fc0_rsp_overrun),
      .o_fc0_rsp_resid_out(fc0_rsp_resid),
      .o_fc0_rsp_info_out(fc0_rsp_info),
      .o_fc0_rsp_rdata_beats_out(fc0_rsp_rdata_beats),

      .o_fc0_status_event_out(fc0_status_event),
      .o_fc0_port_ready_out(fc0_port_ready),
      .o_fc0_port_fatal_error_out(fc0_port_fatal_error),
      .o_fc0_port_enable_pe(fc0_port_enable_pe),
      
      .ha0_mmval_in(fc0_ha_mmval),
      .ha0_mmcfg_in(fc0_ha_mmcfg),
      .ha0_mmrnw_in(fc0_ha_mmrnw),
      .ha0_mmdw_in(fc0_ha_mmdw),
      .ha0_mmad_in(fc0_ha_mmad),
      .ha0_mmdata_in(fc0_ha_mmdata),
      .ah0_mmack_out(fc0_ah_mmack),
      .ah0_mmdata_out(fc0_ah_mmdata),

      .i_fc1_req_r_out(fc1_req_r),
      .i_fc1_req_v_in(fc1_req_v),
      .i_fc1_req_cmd_in(fc1_req_cmd),
      .i_fc1_req_tag_in(fc1_req_tag),
      .i_fc1_req_tag_par_in(fc1_req_tag_par),
      .i_fc1_req_lun_in(fc1_req_lun),
      .i_fc1_req_lun_par_in(fc1_req_lun_par),
      .i_fc1_req_cdb_in(fc1_req_cdb),
      .i_fc1_req_cdb_par_in(fc1_req_cdb_par),
      .i_fc1_req_length_in(fc1_req_length),
      .i_fc1_req_length_par_in(fc1_req_length_par),

      .o_fc1_wdata_req_v_out(fc1_wdata_req_v),
      .o_fc1_wdata_req_r_in(fc1_wdata_req_r),
      .o_fc1_wdata_req_tag_out(fc1_wdata_req_tag),
      .o_fc1_wdata_req_tag_par_out(fc1_wdata_req_tag_par),
      .o_fc1_wdata_req_beat_out(fc1_wdata_req_beat),
      .o_fc1_wdata_req_size_out(fc1_wdata_req_size),
      .o_fc1_wdata_req_size_par_out(fc1_wdata_req_size_par),
      
      .i_fc1_wdata_rsp_v_in(fc1_wdata_rsp_v),
      .i_fc1_wdata_rsp_r_out(fc1_wdata_rsp_r),
      .i_fc1_wdata_rsp_e_in(fc1_wdata_rsp_e),
      .i_fc1_wdata_rsp_error_in(fc1_wdata_rsp_error),      
      .i_fc1_wdata_rsp_tag_in(fc1_wdata_rsp_tag),
      .i_fc1_wdata_rsp_tag_par_in(fc1_wdata_rsp_tag_par),
      .i_fc1_wdata_rsp_beat_in(fc1_wdata_rsp_beat),
      .i_fc1_wdata_rsp_data_in(fc1_wdata_rsp_data),
      .i_fc1_wdata_rsp_data_par_in(fc1_wdata_rsp_data_par),
      
      .o_fc1_rdata_rsp_v_out(fc1_rdata_rsp_v),
      .o_fc1_rdata_rsp_r_in(fc1_rdata_rsp_r),
      .o_fc1_rdata_rsp_e_out(fc1_rdata_rsp_e),  
      .o_fc1_rdata_rsp_c_out(fc1_rdata_rsp_c),  
      .o_fc1_rdata_rsp_beat_out(fc1_rdata_rsp_beat),
      .o_fc1_rdata_rsp_tag_out(fc1_rdata_rsp_tag),
      .o_fc1_rdata_rsp_tag_par_out(fc1_rdata_rsp_tag_par),
      .o_fc1_rdata_rsp_data_out(fc1_rdata_rsp_data),
      .o_fc1_rdata_rsp_data_par_out(fc1_rdata_rsp_data_par),

      .o_fc1_rsp_v_out(fc1_rsp_v),
      .o_fc1_rsp_tag_out(fc1_rsp_tag),
      .o_fc1_rsp_tag_par_out(fc1_rsp_tag_par),
      .o_fc1_rsp_fc_status_out(fc1_rsp_fc_status),
      .o_fc1_rsp_fcx_status_out(fc1_rsp_fcx_status),
      .o_fc1_rsp_scsi_status_out(fc1_rsp_scsi_status),
      .o_fc1_rsp_sns_valid_out(fc1_rsp_sns_valid),
      .o_fc1_rsp_fcp_valid_out(fc1_rsp_fcp_valid),
      .o_fc1_rsp_underrun_out(fc1_rsp_underrun),
      .o_fc1_rsp_overrun_out(fc1_rsp_overrun),
      .o_fc1_rsp_resid_out(fc1_rsp_resid),
      .o_fc1_rsp_info_out(fc1_rsp_info),
      .o_fc1_rsp_rdata_beats_out(fc1_rsp_rdata_beats),

      .o_fc1_status_event_out(fc1_status_event),
      .o_fc1_port_ready_out(fc1_port_ready),
      .o_fc1_port_fatal_error_out(fc1_port_fatal_error),
      .o_fc1_port_enable_pe(fc1_port_enable_pe),

      .ha1_mmval_in(fc1_ha_mmval),
      .ha1_mmcfg_in(fc1_ha_mmcfg),
      .ha1_mmrnw_in(fc1_ha_mmrnw),
      .ha1_mmdw_in(fc1_ha_mmdw),
      .ha1_mmad_in(fc1_ha_mmad),
      .ha1_mmdata_in(fc1_ha_mmdata),
      .ah1_mmack_out(fc1_ah_mmack),
      .ah1_mmdata_out(fc1_ah_mmdata),

      .i_fc2_req_r_out(fc2_req_r),
      .i_fc2_req_v_in(fc2_req_v),
      .i_fc2_req_cmd_in(fc2_req_cmd),
      .i_fc2_req_tag_in(fc2_req_tag),
      .i_fc2_req_tag_par_in(fc2_req_tag_par),
      .i_fc2_req_lun_in(fc2_req_lun),
      .i_fc2_req_lun_par_in(fc2_req_lun_par),
      .i_fc2_req_cdb_in(fc2_req_cdb),
      .i_fc2_req_cdb_par_in(fc2_req_cdb_par),
//      .i_fc2_req_cdb_in(fc2_req_cdb),    //fixit  nnedd to add and connect????
      .i_fc2_req_length_in(fc2_req_length),
      .i_fc2_req_length_par_in(fc2_req_length_par),
      .o_fc2_wdata_req_v_out(fc2_wdata_req_v),
      .o_fc2_wdata_req_r_in(fc2_wdata_req_r),
      .o_fc2_wdata_req_tag_out(fc2_wdata_req_tag),
      .o_fc2_wdata_req_tag_par_out(fc2_wdata_req_tag_par),
      .o_fc2_wdata_req_beat_out(fc2_wdata_req_beat),
      .o_fc2_wdata_req_size_out(fc2_wdata_req_size),
      .o_fc2_wdata_req_size_par_out(fc2_wdata_req_size_par),
      .i_fc2_wdata_rsp_v_in(fc2_wdata_rsp_v),
      .i_fc2_wdata_rsp_r_out(fc2_wdata_rsp_r),
      .i_fc2_wdata_rsp_e_in(fc2_wdata_rsp_e),
      .i_fc2_wdata_rsp_error_in(fc2_wdata_rsp_error),      
      .i_fc2_wdata_rsp_tag_in(fc2_wdata_rsp_tag),
      .i_fc2_wdata_rsp_tag_par_in(fc2_wdata_rsp_tag_par),
      .i_fc2_wdata_rsp_beat_in(fc2_wdata_rsp_beat),
      .i_fc2_wdata_rsp_data_in(fc2_wdata_rsp_data),
      .i_fc2_wdata_rsp_data_par_in(fc2_wdata_rsp_data_par),
      .o_fc2_rdata_rsp_v_out(fc2_rdata_rsp_v),
      .o_fc2_rdata_rsp_r_in(fc2_rdata_rsp_r),
      .o_fc2_rdata_rsp_e_out(fc2_rdata_rsp_e),     
      .o_fc2_rdata_rsp_c_out(fc2_rdata_rsp_c),     
      .o_fc2_rdata_rsp_beat_out(fc2_rdata_rsp_beat),
      .o_fc2_rdata_rsp_tag_out(fc2_rdata_rsp_tag),
      .o_fc2_rdata_rsp_tag_par_out(fc2_rdata_rsp_tag_par),
      .o_fc2_rdata_rsp_data_out(fc2_rdata_rsp_data),
      .o_fc2_rdata_rsp_data_par_out(fc2_rdata_rsp_data_par),
      .o_fc2_rsp_v_out(fc2_rsp_v),
      .o_fc2_rsp_tag_out(fc2_rsp_tag),
      .o_fc2_rsp_tag_par_out(fc2_rsp_tag_par),
      .o_fc2_rsp_fc_status_out(fc2_rsp_fc_status),
      .o_fc2_rsp_fcx_status_out(fc2_rsp_fcx_status),
      .o_fc2_rsp_scsi_status_out(fc2_rsp_scsi_status),
      .o_fc2_rsp_sns_valid_out(fc2_rsp_sns_valid),
      .o_fc2_rsp_fcp_valid_out(fc2_rsp_fcp_valid),
      .o_fc2_rsp_underrun_out(fc2_rsp_underrun),
      .o_fc2_rsp_overrun_out(fc2_rsp_overrun),
      .o_fc2_rsp_resid_out(fc2_rsp_resid),
      .o_fc2_rsp_info_out(fc2_rsp_info),
      .o_fc2_rsp_rdata_beats_out(fc2_rsp_rdata_beats),
      .o_fc2_status_event_out(fc2_status_event),
      .o_fc2_port_ready_out(fc2_port_ready),
      .o_fc2_port_fatal_error_out(fc2_port_fatal_error),
      .o_fc2_port_enable_pe(fc2_port_enable_pe),
      .ha2_mmval_in(fc2_ha_mmval),
      .ha2_mmcfg_in(fc2_ha_mmcfg),
      .ha2_mmrnw_in(fc2_ha_mmrnw),
      .ha2_mmdw_in(fc2_ha_mmdw),
      .ha2_mmad_in(fc2_ha_mmad),
      .ha2_mmdata_in(fc2_ha_mmdata),
      .ah2_mmack_out(fc2_ah_mmack),
      .ah2_mmdata_out(fc2_ah_mmdata),

      .i_fc3_req_r_out(fc3_req_r),
      .i_fc3_req_v_in(fc3_req_v),
      .i_fc3_req_cmd_in(fc3_req_cmd),
      .i_fc3_req_tag_in(fc3_req_tag),
      .i_fc3_req_tag_par_in(fc3_req_tag_par),
      .i_fc3_req_lun_in(fc3_req_lun),
      .i_fc3_req_lun_par_in(fc3_req_lun_par),
      .i_fc3_req_cdb_in(fc3_req_cdb),
      .i_fc3_req_cdb_par_in(fc3_req_cdb_par),
      .i_fc3_req_length_in(fc3_req_length),
      .i_fc3_req_length_par_in(fc3_req_length_par),
      .o_fc3_wdata_req_v_out(fc3_wdata_req_v),
      .o_fc3_wdata_req_r_in(fc3_wdata_req_r),
      .o_fc3_wdata_req_tag_out(fc3_wdata_req_tag),
      .o_fc3_wdata_req_tag_par_out(fc3_wdata_req_tag_par),
      .o_fc3_wdata_req_beat_out(fc3_wdata_req_beat),
      .o_fc3_wdata_req_size_out(fc3_wdata_req_size),
      .o_fc3_wdata_req_size_par_out(fc3_wdata_req_size_par),
      .i_fc3_wdata_rsp_v_in(fc3_wdata_rsp_v),
      .i_fc3_wdata_rsp_r_out(fc3_wdata_rsp_r),
      .i_fc3_wdata_rsp_e_in(fc3_wdata_rsp_e),
      .i_fc3_wdata_rsp_error_in(fc3_wdata_rsp_error),      
      .i_fc3_wdata_rsp_tag_in(fc3_wdata_rsp_tag),
      .i_fc3_wdata_rsp_tag_par_in(fc3_wdata_rsp_tag_par),
      .i_fc3_wdata_rsp_beat_in(fc3_wdata_rsp_beat),
      .i_fc3_wdata_rsp_data_in(fc3_wdata_rsp_data),
      .i_fc3_wdata_rsp_data_par_in(fc3_wdata_rsp_data_par),
      .o_fc3_rdata_rsp_v_out(fc3_rdata_rsp_v),
      .o_fc3_rdata_rsp_r_in(fc3_rdata_rsp_r),
      .o_fc3_rdata_rsp_e_out(fc3_rdata_rsp_e),  
      .o_fc3_rdata_rsp_c_out(fc3_rdata_rsp_c),  
      .o_fc3_rdata_rsp_beat_out(fc3_rdata_rsp_beat),
      .o_fc3_rdata_rsp_tag_out(fc3_rdata_rsp_tag),
      .o_fc3_rdata_rsp_tag_par_out(fc3_rdata_rsp_tag_par),
      .o_fc3_rdata_rsp_data_out(fc3_rdata_rsp_data),
      .o_fc3_rdata_rsp_data_par_out(fc3_rdata_rsp_data_par),
      .o_fc3_rsp_v_out(fc3_rsp_v),
      .o_fc3_rsp_tag_out(fc3_rsp_tag),
      .o_fc3_rsp_tag_par_out(fc3_rsp_tag_par),
      .o_fc3_rsp_fc_status_out(fc3_rsp_fc_status),
      .o_fc3_rsp_fcx_status_out(fc3_rsp_fcx_status),
      .o_fc3_rsp_scsi_status_out(fc3_rsp_scsi_status),
      .o_fc3_rsp_sns_valid_out(fc3_rsp_sns_valid),
      .o_fc3_rsp_fcp_valid_out(fc3_rsp_fcp_valid),
      .o_fc3_rsp_underrun_out(fc3_rsp_underrun),
      .o_fc3_rsp_overrun_out(fc3_rsp_overrun),
      .o_fc3_rsp_resid_out(fc3_rsp_resid),
      .o_fc3_rsp_info_out(fc3_rsp_info),
      .o_fc3_rsp_rdata_beats_out(fc3_rsp_rdata_beats),
      .o_fc3_status_event_out(fc3_status_event),
      .o_fc3_port_ready_out(fc3_port_ready),
      .o_fc3_port_fatal_error_out(fc3_port_fatal_error),
      .o_fc3_port_enable_pe(fc3_port_enable_pe),
      .ha3_mmval_in(fc3_ha_mmval),
      .ha3_mmcfg_in(fc3_ha_mmcfg),
      .ha3_mmrnw_in(fc3_ha_mmrnw),
      .ha3_mmdw_in(fc3_ha_mmdw),
      .ha3_mmad_in(fc3_ha_mmad),
      .ha3_mmdata_in(fc3_ha_mmdata),
      .ah3_mmack_out(fc3_ah_mmack),
      .ah3_mmdata_out(fc3_ah_mmdata),


      .pci_exp0_txp(pci_exp0_txp[LINK_WIDTH-1:0]),
      .pci_exp0_txn(pci_exp0_txn[LINK_WIDTH-1:0]),
      .pci_exp0_rxp(pci_exp0_rxp[LINK_WIDTH-1:0]),
      .pci_exp0_rxn(pci_exp0_rxn[LINK_WIDTH-1:0]),
      .pci_exp0_refclk_p(pci_exp0_refclk_p),
      .pci_exp0_refclk_n(pci_exp0_refclk_n),
      .pci_exp0_nperst(pci_exp0_nperst),
      
      .pci_exp1_txp(pci_exp1_txp[LINK_WIDTH-1:0]),
      .pci_exp1_txn(pci_exp1_txn[LINK_WIDTH-1:0]),
      .pci_exp1_rxp(pci_exp1_rxp[LINK_WIDTH-1:0]),
      .pci_exp1_rxn(pci_exp1_rxn[LINK_WIDTH-1:0]),
      .pci_exp1_refclk_p(pci_exp1_refclk_p),
      .pci_exp1_refclk_n(pci_exp1_refclk_n),
      .pci_exp1_nperst(pci_exp1_nperst),
      
      .pci_exp2_txp(pci_exp2_txp[LINK_WIDTH-1:0]),
      .pci_exp2_txn(pci_exp2_txn[LINK_WIDTH-1:0]),
      .pci_exp2_rxp(pci_exp2_rxp[LINK_WIDTH-1:0]),
      .pci_exp2_rxn(pci_exp2_rxn[LINK_WIDTH-1:0]),
      .pci_exp2_refclk_p(pci_exp2_refclk_p),
      .pci_exp2_refclk_n(pci_exp2_refclk_n),
      .pci_exp2_nperst(pci_exp2_nperst),
      
      .pci_exp3_txp(pci_exp3_txp[LINK_WIDTH-1:0]),
      .pci_exp3_txn(pci_exp3_txn[LINK_WIDTH-1:0]),
      .pci_exp3_rxp(pci_exp3_rxp[LINK_WIDTH-1:0]),
      .pci_exp3_rxn(pci_exp3_rxn[LINK_WIDTH-1:0]),
      .pci_exp3_refclk_p(pci_exp3_refclk_p),
      .pci_exp3_refclk_n(pci_exp3_refclk_n),
      .pci_exp3_nperst(pci_exp3_nperst)
      
      );

   
   ktms_afu#
     (
      .szl(szl),
      .id(0),
      .channels(4),
      .tag_width(tag_width),
      .fc_tag_width(fc_tag_width),
      .lba_width(lba_width),
      .ctxtid_width(ctxtid_width),
      .lunid_width(lunid_width),
      .fc_cmd_width(cmd_width),
      .fc_lunid_width(lunid_width),
      .fc_beatid_width(beatid_width),
      .datalen_width(datalen_width),
      .fc_data_width(data_width),
      .fcstat_width(fcstat_width),
      .fcxstat_width(fcxstat_width),
      .fc_status_width(fc_status_width),
      .fcinfo_width(rsp_info_width),
      .log_width(72)
      )
   iafu
     (

      .i_afu_version(afu_version_q),
      .i_user_image(user_image_q),

      .o_fc_req_r({fc0_req_r,fc1_req_r,fc2_req_r,fc3_req_r}),                                             
      .o_fc_req_v({fc0_req_v,fc1_req_v,fc2_req_v,fc3_req_v}),                                             
      .o_fc_req_cmd({fc0_req_cmd,fc1_req_cmd,fc2_req_cmd,fc3_req_cmd}),                                   
      .o_fc_req_tag({fc0_req_tag,fc1_req_tag,fc2_req_tag,fc3_req_tag}),                                   
      .o_fc_req_tag_par({fc0_req_tag_par,fc1_req_tag_par,fc2_req_tag_par,fc3_req_tag_par}),               
      .o_fc_req_lun({fc0_req_lun,fc1_req_lun,fc2_req_lun,fc3_req_lun}),                                   
      .o_fc_req_lun_par({fc0_req_lun_par,fc1_req_lun_par,fc2_req_lun_par,fc3_req_lun_par}),               
      .o_fc_req_cdb({fc0_req_cdb,fc1_req_cdb,fc2_req_cdb,fc3_req_cdb}),                                   
      .o_fc_req_cdb_par({fc0_req_cdb_par,fc1_req_cdb_par,fc2_req_cdb_par,fc3_req_cdb_par}),   //          
      .o_fc_req_length({fc0_req_length,fc1_req_length,fc2_req_length,fc3_req_length}),                    
      .o_fc_req_length_par({fc0_req_length_par,fc1_req_length_par,fc2_req_length_par,fc3_req_length_par}),  // added _par kch 
      .i_fc_wdata_req_v({fc0_wdata_req_v,fc1_wdata_req_v,fc2_wdata_req_v,fc3_wdata_req_v}),                                   
      .i_fc_wdata_req_r({fc0_wdata_req_r,fc1_wdata_req_r,fc2_wdata_req_r,fc3_wdata_req_r}),                                   
      .i_fc_wdata_req_tag({fc0_wdata_req_tag,fc1_wdata_req_tag,fc2_wdata_req_tag,fc3_wdata_req_tag}),                         
      .i_fc_wdata_req_tag_par({fc0_wdata_req_tag_par,fc1_wdata_req_tag_par,fc2_wdata_req_tag_par,fc3_wdata_req_tag_par}),     
      .i_fc_wdata_req_beat({fc0_wdata_req_beat,fc1_wdata_req_beat,fc2_wdata_req_beat,fc3_wdata_req_beat}),                    
      .i_fc_wdata_req_size({fc0_wdata_req_size,fc1_wdata_req_size,fc2_wdata_req_size,fc3_wdata_req_size}),                    
      .i_fc_wdata_req_size_par({fc0_wdata_req_size_par,fc1_wdata_req_size_par,fc2_wdata_req_size_par,fc3_wdata_req_size_par}),  
      .o_fc_wdata_rsp_v({fc0_wdata_rsp_v,fc1_wdata_rsp_v,fc2_wdata_rsp_v,fc3_wdata_rsp_v}),
      .o_fc_wdata_rsp_r({fc0_wdata_rsp_r,fc1_wdata_rsp_r,fc2_wdata_rsp_r,fc3_wdata_rsp_r}),
      .o_fc_wdata_rsp_e({fc0_wdata_rsp_e,fc1_wdata_rsp_e,fc2_wdata_rsp_e,fc3_wdata_rsp_e}),
      .o_fc_wdata_rsp_error({fc0_wdata_rsp_error,fc1_wdata_rsp_error,fc2_wdata_rsp_error,fc3_wdata_rsp_error}),
      .o_fc_wdata_rsp_tag({fc0_wdata_rsp_tag,fc1_wdata_rsp_tag,fc2_wdata_rsp_tag,fc3_wdata_rsp_tag}),
      .o_fc_wdata_rsp_tag_par({fc0_wdata_rsp_tag_par,fc1_wdata_rsp_tag_par,fc2_wdata_rsp_tag_par,fc3_wdata_rsp_tag_par}),    // added kch
      .o_fc_wdata_rsp_beat({fc0_wdata_rsp_beat,fc1_wdata_rsp_beat,fc2_wdata_rsp_beat,fc3_wdata_rsp_beat}),
      .o_fc_wdata_rsp_data({fc0_wdata_rsp_data,fc1_wdata_rsp_data,fc2_wdata_rsp_data,fc3_wdata_rsp_data}),
      .o_fc_wdata_rsp_data_par({fc0_wdata_rsp_data_par,fc1_wdata_rsp_data_par,fc2_wdata_rsp_data_par,fc3_wdata_rsp_data_par}),
      .i_fc_rdata_rsp_v({fc0_rdata_rsp_v,fc1_rdata_rsp_v,fc2_rdata_rsp_v,fc3_rdata_rsp_v}),
      .i_fc_rdata_rsp_r({fc0_rdata_rsp_r,fc1_rdata_rsp_r,fc2_rdata_rsp_r,fc3_rdata_rsp_r}),
      .i_fc_rdata_rsp_e({fc0_rdata_rsp_e,fc1_rdata_rsp_e,fc2_rdata_rsp_e,fc3_rdata_rsp_e}),
      .i_fc_rdata_rsp_c({fc0_rdata_rsp_c,fc1_rdata_rsp_c,fc2_rdata_rsp_c,fc3_rdata_rsp_c}),
      .i_fc_rdata_rsp_beat({fc0_rdata_rsp_beat,fc1_rdata_rsp_beat,fc2_rdata_rsp_beat,fc3_rdata_rsp_beat}),
      .i_fc_rdata_rsp_tag({fc0_rdata_rsp_tag,fc1_rdata_rsp_tag,fc2_rdata_rsp_tag,fc3_rdata_rsp_tag}),
      .i_fc_rdata_rsp_tag_par({fc0_rdata_rsp_tag_par,fc1_rdata_rsp_tag_par,fc2_rdata_rsp_tag_par,fc3_rdata_rsp_tag_par}),
      .i_fc_rdata_rsp_data({fc0_rdata_rsp_data,fc1_rdata_rsp_data,fc2_rdata_rsp_data,fc3_rdata_rsp_data}),
      .i_fc_rdata_rsp_data_par({fc0_rdata_rsp_data_par,fc1_rdata_rsp_data_par,fc2_rdata_rsp_data_par,fc3_rdata_rsp_data_par}),
      .i_fc_rsp_v({fc0_rsp_v,fc1_rsp_v,fc2_rsp_v,fc3_rsp_v}),
      .i_fc_rsp_tag({fc0_rsp_tag,fc1_rsp_tag,fc2_rsp_tag,fc3_rsp_tag}),
      .i_fc_rsp_tag_par({fc0_rsp_tag_par,fc1_rsp_tag_par,fc2_rsp_tag_par,fc3_rsp_tag_par}),   // added kch need input generator
      .i_fc_rsp_fc_status({fc0_rsp_fc_status,fc1_rsp_fc_status,fc2_rsp_fc_status,fc3_rsp_fc_status}),
      .i_fc_rsp_fcx_status({fc0_rsp_fcx_status,fc1_rsp_fcx_status,fc2_rsp_fcx_status,fc3_rsp_fcx_status}),
      .i_fc_rsp_scsi_status({fc0_rsp_scsi_status,fc1_rsp_scsi_status,fc2_rsp_scsi_status,fc3_rsp_scsi_status}),
      .i_fc_rsp_info({fc0_rsp_info,fc1_rsp_info,fc2_rsp_info,fc3_rsp_info}),
      .i_fc_rsp_sns_valid({fc0_rsp_sns_valid,fc1_rsp_sns_valid,fc2_rsp_sns_valid,fc3_rsp_sns_valid}),
      .i_fc_rsp_fcp_valid({fc0_rsp_fcp_valid,fc1_rsp_fcp_valid,fc2_rsp_fcp_valid,fc3_rsp_fcp_valid}),
      .i_fc_rsp_underrun({fc0_rsp_underrun,fc1_rsp_underrun,fc2_rsp_underrun,fc3_rsp_underrun}),
      .i_fc_rsp_overrun({fc0_rsp_overrun,fc1_rsp_overrun,fc2_rsp_overrun,fc3_rsp_overrun}),
      .i_fc_rsp_resid({fc0_rsp_resid,fc1_rsp_resid,fc2_rsp_resid,fc3_rsp_resid}),
      .i_fc_rsp_rdata_beats({fc0_rsp_rdata_beats,fc1_rsp_rdata_beats,fc2_rsp_rdata_beats,fc3_rsp_rdata_beats}),
//      .i_fc_status_event({fc0_status_event,fc1_status_event,fc2_status_event,fc3_status_event}),  // orig kch 
      .i_fc_status_event({fc2_status_event,fc3_status_event,fc0_status_event,fc1_status_event}),  // swap event bytes per spec bye 2,3,0,1
      .i_fc_port_ready({fc0_port_ready,fc1_port_ready,fc2_port_ready,fc3_port_ready}),
      .i_fc_port_fatal_error({fc0_port_fatal_error,fc1_port_fatal_error,fc2_port_fatal_error,fc3_port_fatal_error}),
      .i_fc_port_enable_pe({fc0_port_enable_pe,fc1_port_enable_pe,fc2_port_enable_pe,fc3_port_enable_pe}),
      .o_fc_mmval({fc0_ha_mmval,fc1_ha_mmval,fc2_ha_mmval,fc3_ha_mmval}),
      .o_fc_mmcfg({fc0_ha_mmcfg,fc1_ha_mmcfg,fc2_ha_mmcfg,fc3_ha_mmcfg}),
      .o_fc_mmrnw({fc0_ha_mmrnw,fc1_ha_mmrnw,fc2_ha_mmrnw,fc3_ha_mmrnw}),
      .o_fc_mmdw({fc0_ha_mmdw,fc1_ha_mmdw,fc2_ha_mmdw,fc3_ha_mmdw}),
      .o_fc_mmad({fc0_ha_mmad,fc1_ha_mmad,fc2_ha_mmad,fc3_ha_mmad}),
      .o_fc_mmdata({fc0_ha_mmdata,fc1_ha_mmdata,fc2_ha_mmdata,fc3_ha_mmdata}),
      .i_fc_mmack({fc0_ah_mmack,fc1_ah_mmack,fc2_ah_mmack,fc3_ah_mmack}),
      .i_fc_mmdata({fc0_ah_mmdata,fc1_ah_mmdata,fc2_ah_mmdata,fc3_ah_mmdata}),

      .o_reset(reset),
      .i_reset(i_reset),   
      .ha_pclock(ha_pclock),
      .o_fc_fatal_error(fc_fatal_error),
//`include "psl_io_bindings.inc"

      .ah_paren(ah_paren),
       // bind the psl ports
       .ha_jval( ha_jval ),
       .ha_jcom( ha_jcom ),
       .ha_jcompar( ha_jcompar ),
       .ha_jea( ha_jea ),
       .ha_jeapar( ha_jeapar ),

       .ah_jrunning( ah_jrunning ),
       .ah_jdone( ah_jdone ),
       .ah_jerror( ah_jerror ),
       .ah_tbreq( ah_tbreq ),
       .ah_jyield(  ),
       .ah_jcack( ah_jcack),
      
       .ah_cvalid( ah_cvalid ),
       .ah_ctag( ah_ctag ),
       .ah_ctagpar( ah_ctagpar),
       .ah_com( ah_com ),
       .ah_compar( ah_compar ),
       .ah_cpad( ah_cpad ),
       .ah_cabt( ah_cabt ),
       .ah_cea( ah_cea ),
       .ah_ceapar( ah_ceapar ),
       .ah_cch( ah_cch ),
       .ah_csize( ah_csize ),
       .ha_croom( ha_croom ),

      .ha_rvalid( ha_rvalid ),
      .ha_rtag( ha_rtag ),
      .ha_rtagpar( ha_rtagpar ),
      .ha_rditag( ha_rditag ),
      .ha_rditagpar( ha_rditagpar ),
      
      .ha_response( ha_response ),
      .ha_rcredits( ha_rcredits ),
      .ha_rcachestate( ha_rcachestate ),
      .ha_rcachepos( ha_rcachepos ),
      
      .ha_mmval( ha_mmval ),
      .ha_mmrnw( ha_mmrnw),
      .ha_mmdw( ha_mmdw),
      .ha_mmad( ha_mmad ),
      .ha_mmcfg(ha_mmcfg),
      .ha_mmadpar( ha_mmadpar ),
      .ha_mmdata( ha_mmdata ),
      .ha_mmdatapar( ha_mmdatapar ),
      .ah_mmack( ah_mmack ),
      .ah_mmdata(ah_mmdata),
      .ah_mmdatapar(ah_mmdatapar),

      .d0h_dvalid(d0h_dvalid), 
      .d0h_req_utag(d0h_req_utag), 
      .d0h_req_itag(d0h_req_itag), 
      .d0h_dtype(d0h_dtype),  
      .d0h_dsize(d0h_dsize), 
      .d0h_datomic_op(d0h_datomic_op), 
      .d0h_datomic_le(d0h_datomic_le), 
      .d0h_ddata(d0h_ddata),

       .hd0_sent_utag_valid(hd0_sent_utag_valid), 
       .hd0_sent_utag(hd0_sent_utag), 
       .hd0_sent_utag_sts(hd0_sent_utag_sts), 

       .hd0_cpl_valid(hd0_cpl_valid),
       .hd0_cpl_utag(hd0_cpl_utag),
       .hd0_cpl_type(hd0_cpl_type),
       .hd0_cpl_laddr(hd0_cpl_laddr),
       .hd0_cpl_byte_count(hd0_cpl_byte_count),
       .hd0_cpl_size(hd0_cpl_size),
       .hd0_cpl_data(hd0_cpl_data)

      );

   assign ah_cpagesize = 4'h0;
   assign o_reset = reset;

  
   // suspend clock
   // todo: 32.678kHz clock for low power mode
   wire pci_exp0_susclk_out;
   assign pci_exp0_susclk_out = 1'b0;
   OBUF pci0_susclk_buf (
      .O(pci_exp0_susclk),    // 1-bit output: Buffer output (connect directly to top-level port)
      .I(pci_exp0_susclk_out) // 1-bit input: Buffer input
   );

   
   // PEWAKE# - open drain active low I/O
   wire pci_exp0_npewake_in;
   wire pci_exp0_npewake_out;
   assign pci_exp0_npewake_out = 1'b1;   
   IOBUF pci0_npewake_buf
     (
      .O     (pci_exp0_npewake_in),  // Buffer output
      .IO    (pci_exp0_npewake),      // Buffer inout port (connect directly to top-level port)
      .I     (pci_exp0_npewake_out),   // Buffer input
      .T     (1'b1)                   // 3-state enable input, high=input, low=output 
      );

   // CLKREQ# - open drain active low I/O
   wire pci_exp0_nclkreq_in;
   wire pci_exp0_nclkreq_out;
   assign pci_exp0_nclkreq_out = 1'b1;   
   IOBUF pci0_nclkreq_buf
     (
      .O     (pci_exp0_nclkreq_in),  // Buffer output
      .IO    (pci_exp0_nclkreq),      // Buffer inout port (connect directly to top-level port)
      .I     (pci_exp0_nclkreq_out),   // Buffer input
      .T     (1'b1)                   // 3-state enable input, high=input, low=output 
      );


  
   // suspend clock
   // todo: 32.678kHz clock for low power mode
   wire pci_exp1_susclk_out;
   assign pci_exp1_susclk_out = 1'b0;
   OBUF pci1_susclk_buf (
      .O(pci_exp1_susclk),    // 1-bit output: Buffer output (connect directly to top-level port)
      .I(pci_exp1_susclk_out) // 1-bit input: Buffer input
   );

   
   // PEWAKE# - open drain active low I/O
   wire pci_exp1_npewake_in;
   wire pci_exp1_npewake_out;
   assign pci_exp1_npewake_out = 1'b1;   
   IOBUF pci1_npewake_buf
     (
      .O     (pci_exp1_npewake_in),  // Buffer output
      .IO    (pci_exp1_npewake),      // Buffer inout port (connect directly to top-level port)
      .I     (pci_exp1_npewake_out),   // Buffer input
      .T     (1'b1)                   // 3-state enable input, high=input, low=output 
      );

   // CLKREQ# - open drain active low I/O
   wire pci_exp1_nclkreq_in;
   wire pci_exp1_nclkreq_out;
   assign pci_exp1_nclkreq_out = 1'b1;   
   IOBUF pci1_nclkreq_buf
     (
      .O     (pci_exp1_nclkreq_in),  // Buffer output
      .IO    (pci_exp1_nclkreq),      // Buffer inout port (connect directly to top-level port)
      .I     (pci_exp1_nclkreq_out),   // Buffer input
      .T     (1'b1)                   // 3-state enable input, high=input, low=output 
      );

   // suspend clock
   // todo: 32.678kHz clock for low power mode
   wire pci_exp2_susclk_out;
   assign pci_exp2_susclk_out = 1'b0;
   OBUF pci2_susclk_buf (
      .O(pci_exp2_susclk),    // 1-bit output: Buffer output (connect directly to top-level port)
      .I(pci_exp2_susclk_out) // 1-bit input: Buffer input
   );

   
   // PEWAKE# - open drain active low I/O
   wire pci_exp2_npewake_in;
   wire pci_exp2_npewake_out;
   assign pci_exp2_npewake_out = 1'b1;   
   IOBUF pci2_npewake_buf
     (
      .O     (pci_exp2_npewake_in),  // Buffer output
      .IO    (pci_exp2_npewake),      // Buffer inout port (connect directly to top-level port)
      .I     (pci_exp2_npewake_out),   // Buffer input
      .T     (1'b1)                   // 3-state enable input, high=input, low=output 
      );

   // CLKREQ# - open drain active low I/O
   wire pci_exp2_nclkreq_in;
   wire pci_exp2_nclkreq_out;
   assign pci_exp2_nclkreq_out = 1'b1;   
   IOBUF pci2_nclkreq_buf
     (
      .O     (pci_exp2_nclkreq_in),  // Buffer output
      .IO    (pci_exp2_nclkreq),      // Buffer inout port (connect directly to top-level port)
      .I     (pci_exp2_nclkreq_out),   // Buffer input
      .T     (1'b1)                   // 3-state enable input, high=input, low=output 
      );


  
   // suspend clock
   // todo: 32.678kHz clock for low power mode
   wire pci_exp3_susclk_out;
   assign pci_exp3_susclk_out = 1'b0;
   OBUF pci3_susclk_buf (
      .O(pci_exp3_susclk),    // 1-bit output: Buffer output (connect directly to top-level port)
      .I(pci_exp3_susclk_out) // 1-bit input: Buffer input
   );

   
   // PEWAKE# - open drain active low I/O
   wire pci_exp3_npewake_in;
   wire pci_exp3_npewake_out;
   assign pci_exp3_npewake_out = 1'b1;   
   IOBUF pci3_npewake_buf
     (
      .O     (pci_exp3_npewake_in),  // Buffer output
      .IO    (pci_exp3_npewake),      // Buffer inout port (connect directly to top-level port)
      .I     (pci_exp3_npewake_out),   // Buffer input
      .T     (1'b1)                   // 3-state enable input, high=input, low=output 
      );

   // CLKREQ# - open drain active low I/O
   wire pci_exp3_nclkreq_in;
   wire pci_exp3_nclkreq_out;
   assign pci_exp3_nclkreq_out = 1'b1;   
   IOBUF pci3_nclkreq_buf
     (
      .O     (pci_exp3_nclkreq_in),  // Buffer output
      .IO    (pci_exp3_nclkreq),      // Buffer inout port (connect directly to top-level port)
      .I     (pci_exp3_nclkreq_out),   // Buffer input
      .T     (1'b1)                   // 3-state enable input, high=input, low=output 
      );


vio_0 vio_snvme_top (
  .clk(ha_pclock),              // input wire clk
  .probe_in0(afu_version_q),  // input wire [63 : 0] probe_in0
  .probe_in1(ah_jrunning),  // input wire [0 : 0] probe_in1
  .probe_in2(fc0_port_ready),  // input wire [0 : 0] probe_in2
  .probe_in3(fc1_port_ready),  // input wire [0 : 0] probe_in3
  .probe_in4(fc2_port_ready),  // input wire [0 : 0] probe_in4
  .probe_in5(fc3_port_ready),  // input wire [0 : 0] probe_in5
  .probe_in6(gold_factory)  // input wire [0 : 0] probe_in6
  
);

   
endmodule 

