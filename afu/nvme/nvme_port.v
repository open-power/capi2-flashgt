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
//  File : nvme_port.v
//  *************************************************************************
//  *************************************************************************
//  Description : Surelock NVMe - single NVMe port container
//                
//       Takes read/write commands from PSL/AFU and converts to NVMe
//
//  *************************************************************************

module nvme_port#
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
    parameter data_par_width  = (data_width + 7) /8,
    parameter data_fc_par_width = data_par_width/8,
    parameter status_width    = 8, // event status
    parameter lunidx_width    = 8, // support 255 LUNs max
    parameter wbuf_numids     = 32,  // 4KB per id
    parameter wbufid_width    = $clog2(wbuf_numids),
    
    parameter mmio_base  = 26'h2012000,
    parameter mmio_base2 = 26'h2060000,
    parameter port_id = 0,

    parameter num_isq = 16,  // max number of sntl I/O submissions queues
    parameter isq_idwidth = $clog2(num_isq+2),  // 2 submissions queues used by ucode


    parameter LINK_WIDTH=4
    )
   (
   
    input                       reset_in,
    input                       clk,
    input                       clk_div2,

    output                      led_red,
    output                      led_green,
    output                      led_blue,
    

    output     [LINK_WIDTH-1:0] pci_exp_txp,
    output     [LINK_WIDTH-1:0] pci_exp_txn,
    input      [LINK_WIDTH-1:0] pci_exp_rxp,
    input      [LINK_WIDTH-1:0] pci_exp_rxn,

    input                       pci_exp_refclk_p,
    input                       pci_exp_refclk_n,
    output                      pci_exp_nperst,

    // AFU/PSL interface
    // -----------------
   
    // request command interface
    //  req_r      - ready
    //  req_v      - valid.  xfer occurs only if valid & ready, otherwise no xfer
    //  req_cmd    - sislite command encode
    //  req_tag    - identifier for the command
    //  req_lun    - logical unit number (SCSI formatted lun)
    //  reg_length - byte length of buffer
    //  req_cdb    - SCSI CDB (big endian)
    output                      i_req_r_out,
    input                       i_req_v_in,
    input       [cmd_width-1:0] i_req_cmd_in, 
    input       [tag_width-1:0] i_req_tag_in, 
    input   [tag_par_width-1:0] i_req_tag_par_in, 
    input     [lunid_width-1:0] i_req_lun_in, 
    input [lunid_par_width-1:0] i_req_lun_par_in, 
    input   [datalen_width-1:0] i_req_length_in, 
    input                       i_req_length_par_in, 
    input               [127:0] i_req_cdb_in, 
    input                 [1:0] i_req_cdb_par_in, 

    // write data request interface. 
    output                      o_wdata_req_v_out,
    input                       o_wdata_req_r_in,
    output      [tag_width-1:0] o_wdata_req_tag_out,
    output      [tag_par_width-1:0] o_wdata_req_tag_par_out,
    output   [beatid_width-1:0] o_wdata_req_beat_out,
    output  [datalen_width-1:0] o_wdata_req_size_out,
    output  [datalen_par_width-1:0] o_wdata_req_size_par_out,

    // data response interface (writes).
    // data is big endian - 7:0 == least significant byte
    input                       i_wdata_rsp_v_in,
    output                      i_wdata_rsp_r_out,
    input                       i_wdata_rsp_e_in,
    input                       i_wdata_rsp_error_in,
    input       [tag_width-1:0] i_wdata_rsp_tag_in,
    input                       i_wdata_rsp_tag_par_in,
    input    [beatid_width-1:0] i_wdata_rsp_beat_in,
    input      [data_width-1:0] i_wdata_rsp_data_in,
    input  [data_fc_par_width-1:0] i_wdata_rsp_data_par_in,

    // read data response interface
    //   rsp_v    - valid.  
    //   rsp_e    - read data end. Must be asserted with rsp_v after last data beat for a 2K block.
    //   rsp_tag  - identifier of the corresponding read request
    //   rsp_beat - offset for this data transfer
    //   rsp_data - 1 beat of read data.  Not used when rsp_e is assserted.
    // 
    output                      o_rdata_rsp_v_out,
    input                       o_rdata_rsp_r_in,
    output                      o_rdata_rsp_e_out,
    output    [bytec_width-1:0] o_rdata_rsp_c_out,
    output   [beatid_width-1:0] o_rdata_rsp_beat_out,
    output      [tag_width-1:0] o_rdata_rsp_tag_out,
    output      [tag_par_width-1:0] o_rdata_rsp_tag_par_out,
    output     [data_width-1:0] o_rdata_rsp_data_out,
    output [data_fc_par_width-1:0] o_rdata_rsp_data_par_out,

    // command response interface
    output                      o_rsp_v_out,
    output      [tag_width-1:0] o_rsp_tag_out,
    output      [tag_par_width-1:0] o_rsp_tag_par_out,
    output   [fcstat_width-1:0] o_rsp_fc_status_out,
    output  [fcxstat_width-1:0] o_rsp_fcx_status_out,
    output                [7:0] o_rsp_scsi_status_out,
    output                      o_rsp_sns_valid_out,
    output                      o_rsp_fcp_valid_out,
    output                      o_rsp_underrun_out,
    output                      o_rsp_overrun_out,
    output               [31:0] o_rsp_resid_out,
    output   [beatid_width-1:0] o_rsp_rdata_beats_out,
    output [rsp_info_width-1:0] o_rsp_info_out,


    // FC module status events
    // --------------
    output   [status_width-1:0] o_status_event_out,
    output                      o_port_ready_out,
    output                      o_port_fatal_error,
    output                      o_port_enable_pe,
    input                       i_fc_fatal_error,

       
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
    input                       ha_mmval_in,
    input                       ha_mmcfg_in,
    input                       ha_mmrnw_in,
    input                       ha_mmdw_in,
    input                [23:0] ha_mmad_in,
    input                [63:0] ha_mmdata_in,
    output                      ah_mmack_out,
    output               [63:0] ah_mmdata_out
    );


    /*AUTOWIRE*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    wire [3:0]          admin_perror_ind;       // From nvme_sntl of nvme_sntl.v
    wire [1:0]          adq_ctl_cpl_empty;      // From nvme_ucq of nvme_ucq.v
    wire                adq_ctl_ioack;          // From nvme_ucq of nvme_ucq.v
    wire [35:0]         adq_ctl_ioread_data;    // From nvme_ucq of nvme_ucq.v
    wire [144:0]        adq_pcie_cc_data;       // From nvme_ucq of nvme_ucq.v
    wire                adq_pcie_cc_discard;    // From nvme_ucq of nvme_ucq.v
    wire                adq_pcie_cc_first;      // From nvme_ucq of nvme_ucq.v
    wire                adq_pcie_cc_last;       // From nvme_ucq of nvme_ucq.v
    wire                adq_pcie_cc_valid;      // From nvme_ucq of nvme_ucq.v
    wire                adq_pcie_pause;         // From nvme_ucq of nvme_ucq.v
    wire [31:0]         adq_pcie_wraddr;        // From nvme_ucq of nvme_ucq.v
    wire [15:0]         adq_pcie_wrdata;        // From nvme_ucq of nvme_ucq.v
    wire                adq_pcie_wrvalid;       // From nvme_ucq of nvme_ucq.v
    wire                adq_perror_ind;         // From nvme_ucq of nvme_ucq.v
    wire                adq_regs_dbg_ack;       // From nvme_ucq of nvme_ucq.v
    wire [63:0]         adq_regs_dbg_data;      // From nvme_ucq of nvme_ucq.v
    wire                cdc_ctlff_perror_ind;   // From nvme_pcie of nvme_pcie.v
    wire                cdc_hold_cfg_err_fatal_out;// From nvme_pcie of nvme_pcie.v
    wire [1:0]          cdc_rxcq_perror_ind;    // From nvme_pcie of nvme_pcie.v
    wire                cdc_rxrc_perror_ind;    // From nvme_pcie of nvme_pcie.v
    wire [1:0]          cdc_txcc_perror_ind;    // From nvme_pcie of nvme_pcie.v
    wire                cdc_txrq_perror_ind;    // From nvme_pcie of nvme_pcie.v
    wire [5:0]          cmd_perror_ind;         // From nvme_sntl of nvme_sntl.v
    wire [31:0]         cmd_regs_dbgcount;      // From nvme_sntl of nvme_sntl.v
    wire                cmd_regs_errinj_ack;    // From nvme_sntl of nvme_sntl.v
    wire                cmd_regs_errinj_cmdrd;  // From nvme_sntl of nvme_sntl.v
    wire                cmd_regs_errinj_cmdwr;  // From nvme_sntl of nvme_sntl.v
    wire                cmd_regs_lunreset;      // From nvme_sntl of nvme_sntl.v
    wire                cmd_regs_trk_ack;       // From nvme_sntl of nvme_sntl.v
    wire [511:0]        cmd_regs_trk_data;      // From nvme_sntl of nvme_sntl.v
    wire [31:0]         ctl_adq_ioaddress;      // From control of nvme_control.v
    wire                ctl_adq_ioread_strobe;  // From control of nvme_control.v
    wire [35:0]         ctl_adq_iowrite_data;   // From control of nvme_control.v
    wire                ctl_adq_iowrite_strobe; // From control of nvme_control.v
    wire [31:0]         ctl_ioq_ioaddress;      // From control of nvme_control.v
    wire                ctl_ioq_ioread_strobe;  // From control of nvme_control.v
    wire [35:0]         ctl_ioq_iowrite_data;   // From control of nvme_control.v
    wire                ctl_ioq_iowrite_strobe; // From control of nvme_control.v
    wire [31:0]         ctl_pcie_ioaddress;     // From control of nvme_control.v
    wire                ctl_pcie_ioread_strobe; // From control of nvme_control.v
    wire [35:0]         ctl_pcie_iowrite_data;  // From control of nvme_control.v
    wire                ctl_pcie_iowrite_strobe;// From control of nvme_control.v
    wire [31:0]         ctl_regs_ioaddress;     // From control of nvme_control.v
    wire                ctl_regs_ioread_strobe; // From control of nvme_control.v
    wire [35:0]         ctl_regs_iowrite_data;  // From control of nvme_control.v
    wire                ctl_regs_iowrite_strobe;// From control of nvme_control.v
    wire [31:0]         ctl_regs_ustatus;       // From control of nvme_control.v
    wire [31:0]         ctl_sntl_ioaddress;     // From control of nvme_control.v
    wire                ctl_sntl_ioread_strobe; // From control of nvme_control.v
    wire [35:0]         ctl_sntl_iowrite_data;  // From control of nvme_control.v
    wire                ctl_sntl_iowrite_strobe;// From control of nvme_control.v
    wire                ctl_xx_csts_rdy;        // From control of nvme_control.v
    wire                ctl_xx_ioq_enable;      // From control of nvme_control.v
    wire                ctl_xx_shutdown;        // From control of nvme_control.v
    wire                ctl_xx_shutdown_cmp;    // From control of nvme_control.v
    wire                ctlff_perror_ind;       // From nvme_pcie of nvme_pcie.v
    wire [7:0]          dma_perror_ind;         // From nvme_sntl of nvme_sntl.v
    wire                ioq_ctl_ioack;          // From nvme_ioq of nvme_ioq.v
    wire [31:0]         ioq_ctl_ioread_data;    // From nvme_ioq of nvme_ioq.v
    wire [144:0]        ioq_pcie_cc_data;       // From nvme_ioq of nvme_ioq.v
    wire                ioq_pcie_cc_discard;    // From nvme_ioq of nvme_ioq.v
    wire                ioq_pcie_cc_first;      // From nvme_ioq of nvme_ioq.v
    wire                ioq_pcie_cc_last;       // From nvme_ioq of nvme_ioq.v
    wire                ioq_pcie_cc_valid;      // From nvme_ioq of nvme_ioq.v
    wire                ioq_pcie_pause;         // From nvme_ioq of nvme_ioq.v
    wire [31:0]         ioq_pcie_wraddr;        // From nvme_ioq of nvme_ioq.v
    wire [15:0]         ioq_pcie_wrdata;        // From nvme_ioq of nvme_ioq.v
    wire                ioq_pcie_wrvalid;       // From nvme_ioq of nvme_ioq.v
    wire [1:0]          ioq_perror_ind;         // From nvme_ioq of nvme_ioq.v
    wire                ioq_regs_dbg_ack;       // From nvme_ioq of nvme_ioq.v
    wire [63:0]         ioq_regs_dbg_data;      // From nvme_ioq of nvme_ioq.v
    wire [3:0]          ioq_regs_faterr;        // From nvme_ioq of nvme_ioq.v
    wire [3:0]          ioq_regs_recerr;        // From nvme_ioq of nvme_ioq.v
    wire [15:0]         ioq_sntl_cpl_cmdid;     // From nvme_ioq of nvme_ioq.v
    wire [1:0]          ioq_sntl_cpl_cmdid_par; // From nvme_ioq of nvme_ioq.v
    wire [14:0]         ioq_sntl_cpl_status;    // From nvme_ioq of nvme_ioq.v
    wire                ioq_sntl_cpl_valid;     // From nvme_ioq of nvme_ioq.v
    wire                ioq_sntl_req_ack;       // From nvme_ioq of nvme_ioq.v
    wire [isq_idwidth-1:0] ioq_sntl_sqid;       // From nvme_ioq of nvme_ioq.v
    wire                ioq_sntl_sqid_valid;    // From nvme_ioq of nvme_ioq.v
    wire                ioq_xx_icq_empty;       // From nvme_ioq of nvme_ioq.v
    wire                ioq_xx_isq_empty;       // From nvme_ioq of nvme_ioq.v
    wire                pcie_adq_cc_ready;      // From nvme_pcie of nvme_pcie.v
    wire [144:0]        pcie_adq_data;          // From nvme_pcie of nvme_pcie.v
    wire                pcie_adq_discard;       // From nvme_pcie of nvme_pcie.v
    wire                pcie_adq_first;         // From nvme_pcie of nvme_pcie.v
    wire                pcie_adq_last;          // From nvme_pcie of nvme_pcie.v
    wire                pcie_adq_valid;         // From nvme_pcie of nvme_pcie.v
    wire                pcie_adq_wrack;         // From nvme_pcie of nvme_pcie.v
    wire                pcie_ctl_ioack;         // From nvme_pcie of nvme_pcie.v
    wire [31:0]         pcie_ctl_ioread_data;   // From nvme_pcie of nvme_pcie.v
    wire [3:0]          pcie_ctl_ioread_datap;  // From nvme_pcie of nvme_pcie.v
    wire                pcie_ioq_cc_ready;      // From nvme_pcie of nvme_pcie.v
    wire [144:0]        pcie_ioq_data;          // From nvme_pcie of nvme_pcie.v
    wire                pcie_ioq_discard;       // From nvme_pcie of nvme_pcie.v
    wire                pcie_ioq_first;         // From nvme_pcie of nvme_pcie.v
    wire                pcie_ioq_last;          // From nvme_pcie of nvme_pcie.v
    wire                pcie_ioq_valid;         // From nvme_pcie of nvme_pcie.v
    wire                pcie_ioq_wrack;         // From nvme_pcie of nvme_pcie.v
    wire                pcie_regs_ack;          // From nvme_pcie of nvme_pcie.v
    wire [31:0]         pcie_regs_cpl_data;     // From nvme_pcie of nvme_pcie.v
    wire [3:0]          pcie_regs_cpl_datap;    // From nvme_pcie of nvme_pcie.v
    wire [15:0]         pcie_regs_cpl_status;   // From nvme_pcie of nvme_pcie.v
    wire                pcie_regs_cpl_valid;    // From nvme_pcie of nvme_pcie.v
    wire                pcie_regs_dbg_ack;      // From nvme_pcie of nvme_pcie.v
    wire [63:0]         pcie_regs_dbg_data;     // From nvme_pcie of nvme_pcie.v
    wire [1:0]          pcie_regs_dbg_error;    // From nvme_pcie of nvme_pcie.v
    wire                pcie_regs_rxcq_backpressure;// From nvme_pcie of nvme_pcie.v
    wire                pcie_regs_rxcq_errinj_ack;// From nvme_pcie of nvme_pcie.v
    wire                pcie_regs_rxcq_errinj_active;// From nvme_pcie of nvme_pcie.v
    wire [3:0]          pcie_regs_rxcq_error;   // From nvme_pcie of nvme_pcie.v
    wire                pcie_regs_sisl_backpressure;// From nvme_pcie of nvme_pcie.v
    wire [31:0]         pcie_regs_status;       // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_adbuf_cc_ready;// From nvme_pcie of nvme_pcie.v
    wire [144:0]        pcie_sntl_adbuf_data;   // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_adbuf_discard;// From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_adbuf_first;  // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_adbuf_last;   // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_adbuf_valid;  // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_cc_ready;     // From nvme_pcie of nvme_pcie.v
    wire [144:0]        pcie_sntl_data;         // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_discard;      // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_first;        // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_last;         // From nvme_pcie of nvme_pcie.v
    wire [7:0]          pcie_sntl_rxcq_perf_events;// From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_valid;        // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_wbuf_cc_ready;// From nvme_pcie of nvme_pcie.v
    wire [144:0]        pcie_sntl_wbuf_data;    // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_wbuf_discard; // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_wbuf_first;   // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_wbuf_last;    // From nvme_pcie of nvme_pcie.v
    wire                pcie_sntl_wbuf_valid;   // From nvme_pcie of nvme_pcie.v
    wire                pcie_xx_init_done;      // From nvme_pcie of nvme_pcie.v
    wire                pcie_xx_link_up;        // From nvme_pcie of nvme_pcie.v
    wire [9:0]          regs_adq_dbg_addr;      // From regs of nvme_regs.v
    wire                regs_adq_dbg_rd;        // From regs of nvme_regs.v
    wire                regs_adq_pe_errinj_valid;// From regs of nvme_regs.v
    wire [15:0]         regs_cmd_IOtimeout2;    // From regs of nvme_regs.v
    wire [15:0]         regs_cmd_debug;         // From regs of nvme_regs.v
    wire                regs_cmd_disableto;     // From regs of nvme_regs.v
    wire [31:0]         regs_cmd_errinj_lba;    // From regs of nvme_regs.v
    wire [3:0]          regs_cmd_errinj_select; // From regs of nvme_regs.v
    wire [15:0]         regs_cmd_errinj_status; // From regs of nvme_regs.v
    wire                regs_cmd_errinj_uselba; // From regs of nvme_regs.v
    wire                regs_cmd_errinj_valid;  // From regs of nvme_regs.v
    wire [tag_width:0]  regs_cmd_maxiord;       // From regs of nvme_regs.v
    wire [tag_width:0]  regs_cmd_maxiowr;       // From regs of nvme_regs.v
    wire [tag_width-1:0] regs_cmd_trk_addr;     // From regs of nvme_regs.v
    wire                regs_cmd_trk_addr_par;  // From regs of nvme_regs.v
    wire                regs_cmd_trk_rd;        // From regs of nvme_regs.v
    wire                regs_ctl_enable;        // From regs of nvme_regs.v
    wire                regs_ctl_ioack;         // From regs of nvme_regs.v
    wire [31:0]         regs_ctl_ioread_data;   // From regs of nvme_regs.v
    wire                regs_ctl_ldrom;         // From regs of nvme_regs.v
    wire                regs_ctl_lunreset;      // From regs of nvme_regs.v
    wire                regs_ctl_shutdown;      // From regs of nvme_regs.v
    wire                regs_ctl_shutdown_abrupt;// From regs of nvme_regs.v
    wire [7:0]          regs_dma_errcpl;        // From regs of nvme_regs.v
    wire [9:0]          regs_ioq_dbg_addr;      // From regs of nvme_regs.v
    wire                regs_ioq_dbg_rd;        // From regs of nvme_regs.v
    wire [15:0]         regs_ioq_icqto;         // From regs of nvme_regs.v
    wire                regs_ioq_pe_errinj_valid;// From regs of nvme_regs.v
    wire [31:0]         regs_pcie_addr;         // From regs of nvme_regs.v
    wire [3:0]          regs_pcie_be;           // From regs of nvme_regs.v
    wire                regs_pcie_configop;     // From regs of nvme_regs.v
    wire [15:0]         regs_pcie_dbg_addr;     // From regs of nvme_regs.v
    wire                regs_pcie_dbg_rd;       // From regs of nvme_regs.v
    wire [7:0]          regs_pcie_debug;        // From regs of nvme_regs.v
    wire [31:0]         regs_pcie_debug_trace;  // From regs of nvme_regs.v
    wire                regs_pcie_pe_errinj_valid;// From regs of nvme_regs.v
    wire                regs_pcie_perst;        // From regs of nvme_regs.v
    wire                regs_pcie_rnw;          // From regs of nvme_regs.v
    wire [19:0]         regs_pcie_rxcq_errinj_delay;// From regs of nvme_regs.v
    wire                regs_pcie_rxcq_errinj_valid;// From regs of nvme_regs.v
    wire [3:0]          regs_pcie_tag;          // From regs of nvme_regs.v
    wire                regs_pcie_valid;        // From regs of nvme_regs.v
    wire [31:0]         regs_pcie_wrdata;       // From regs of nvme_regs.v
    wire [9:0]          regs_sntl_dbg_addr;     // From regs of nvme_regs.v
    wire                regs_sntl_dbg_rd;       // From regs of nvme_regs.v
    wire                regs_sntl_pe_errinj_valid;// From regs of nvme_regs.v
    wire                regs_sntl_perf_reset;   // From regs of nvme_regs.v
    wire                regs_sntl_rsp_debug;    // From regs of nvme_regs.v
    wire [7:0]          regs_unmap_rangecount;  // From regs of nvme_regs.v
    wire [7:0]          regs_unmap_reqcount;    // From regs of nvme_regs.v
    wire [11:0]         regs_unmap_timer1;      // From regs of nvme_regs.v
    wire [19:0]         regs_unmap_timer2;      // From regs of nvme_regs.v
    wire                regs_wdata_errinj_valid;// From regs of nvme_regs.v
    wire                regs_wdata_pe_errinj_1cycle_valid;// From regs of nvme_regs.v
    wire                regs_wdata_pe_errinj_valid;// From regs of nvme_regs.v
    wire                regs_xx_disable_reset;  // From regs of nvme_regs.v
    wire                regs_xx_freeze;         // From regs of nvme_regs.v
    wire [datalen_width-13:0] regs_xx_maxxfer;  // From regs of nvme_regs.v
    wire                regs_xx_tick1;          // From regs of nvme_regs.v
    wire                regs_xx_tick2;          // From regs of nvme_regs.v
    wire [35:0]         regs_xx_timer1;         // From regs of nvme_regs.v
    wire [15:0]         regs_xx_timer2;         // From regs of nvme_regs.v
    wire [15:0]         regs_xxx_pe_errinj_decode;// From regs of nvme_regs.v
    wire                rsp_perror_ind;         // From nvme_sntl of nvme_sntl.v
    wire                rxcq_perror_ind;        // From nvme_pcie of nvme_pcie.v
    wire                sntl_ctl_admin_cmd_valid;// From nvme_sntl of nvme_sntl.v
    wire                sntl_ctl_admin_cpl_valid;// From nvme_sntl of nvme_sntl.v
    wire                sntl_ctl_idle;          // From nvme_sntl of nvme_sntl.v
    wire                sntl_ctl_ioack;         // From nvme_sntl of nvme_sntl.v
    wire [31:0]         sntl_ctl_ioread_data;   // From nvme_sntl of nvme_sntl.v
    wire                sntl_ioq_cpl_ack;       // From nvme_sntl of nvme_sntl.v
    wire [15:0]         sntl_ioq_req_cmdid;     // From nvme_sntl of nvme_sntl.v
    wire                sntl_ioq_req_fua;       // From nvme_sntl of nvme_sntl.v
    wire [63:0]         sntl_ioq_req_lba;       // From nvme_sntl of nvme_sntl.v
    wire [31:0]         sntl_ioq_req_nsid;      // From nvme_sntl of nvme_sntl.v
    wire [15:0]         sntl_ioq_req_numblks;   // From nvme_sntl of nvme_sntl.v
    wire [7:0]          sntl_ioq_req_opcode;    // From nvme_sntl of nvme_sntl.v
    wire [datalen_width-1:0] sntl_ioq_req_reloff;// From nvme_sntl of nvme_sntl.v
    wire [isq_idwidth-1:0] sntl_ioq_req_sqid;   // From nvme_sntl of nvme_sntl.v
    wire                sntl_ioq_req_valid;     // From nvme_sntl of nvme_sntl.v
    wire [wbufid_width-1:0] sntl_ioq_req_wbufid;// From nvme_sntl of nvme_sntl.v
    wire [isq_idwidth-1:0] sntl_ioq_sqid;       // From nvme_sntl of nvme_sntl.v
    wire                sntl_ioq_sqid_ack;      // From nvme_sntl of nvme_sntl.v
    wire [144:0]        sntl_pcie_adbuf_cc_data;// From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_adbuf_cc_discard;// From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_adbuf_cc_first;// From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_adbuf_cc_last;// From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_adbuf_cc_valid;// From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_adbuf_pause;  // From nvme_sntl of nvme_sntl.v
    wire [144:0]        sntl_pcie_cc_data;      // From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_cc_discard;   // From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_cc_first;     // From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_cc_last;      // From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_cc_valid;     // From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_pause;        // From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_ready;        // From nvme_sntl of nvme_sntl.v
    wire [144:0]        sntl_pcie_wbuf_cc_data; // From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_wbuf_cc_discard;// From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_wbuf_cc_first;// From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_wbuf_cc_last; // From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_wbuf_cc_valid;// From nvme_sntl of nvme_sntl.v
    wire                sntl_pcie_wbuf_pause;   // From nvme_sntl of nvme_sntl.v
    wire                sntl_regs_cmd_idle;     // From nvme_sntl of nvme_sntl.v
    wire                sntl_regs_dbg_ack;      // From nvme_sntl of nvme_sntl.v
    wire [63:0]         sntl_regs_dbg_data;     // From nvme_sntl of nvme_sntl.v
    wire                sntl_regs_rdata_paused; // From nvme_sntl of nvme_sntl.v
    wire                sntl_regs_rsp_cnt;      // From nvme_sntl of nvme_sntl.v
    wire [2:0]          txcc_perror_ind;        // From nvme_pcie of nvme_pcie.v
    wire [2:0]          wbuf_perror_ind;        // From nvme_sntl of nvme_sntl.v
    wire [3:0]          wbuf_regs_error;        // From nvme_sntl of nvme_sntl.v
    wire                wdata_perror_ind;       // From nvme_sntl of nvme_sntl.v
    wire                wdata_regs_errinj_ack;  // From nvme_sntl of nvme_sntl.v
    wire                wdata_regs_errinj_active;// From nvme_sntl of nvme_sntl.v
    // End of automatics


   
   // extend reset_in for 16 cycles
   reg                  reset;
   reg            [3:0] reset_cnt_q;
   always @(posedge clk)
     begin
        if( reset_in && ~(regs_xx_disable_reset | regs_xx_freeze) )
          begin
             reset <= 1'b1;
             reset_cnt_q <= 4'hF;
          end
        else
          begin
             if( reset && reset_cnt_q != 4'h0 )
               reset_cnt_q <= reset_cnt_q - 4'h1;
             else
               reset <= 1'b0;
          end
     end
   
       
  nvme_sntl#
    (
     // afu/psl interface parameters
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
     .lunidx_width(lunidx_width),
     .wbuf_numids(wbuf_numids),
     .num_isq(num_isq),
     .isq_idwidth(isq_idwidth)
     ) nvme_sntl 
      (/*AUTOINST*/
       // Outputs
       .i_req_r_out                     (i_req_r_out),
       .o_wdata_req_v_out               (o_wdata_req_v_out),
       .o_wdata_req_tag_out             (o_wdata_req_tag_out[tag_width-1:0]),
       .o_wdata_req_tag_par_out         (o_wdata_req_tag_par_out[tag_par_width-1:0]),
       .o_wdata_req_beat_out            (o_wdata_req_beat_out[beatid_width-1:0]),
       .o_wdata_req_size_out            (o_wdata_req_size_out[datalen_width-1:0]),
       .o_wdata_req_size_par_out        (o_wdata_req_size_par_out[datalen_par_width-1:0]),
       .i_wdata_rsp_r_out               (i_wdata_rsp_r_out),
       .o_rdata_rsp_v_out               (o_rdata_rsp_v_out),
       .o_rdata_rsp_e_out               (o_rdata_rsp_e_out),
       .o_rdata_rsp_c_out               (o_rdata_rsp_c_out[bytec_width-1:0]),
       .o_rdata_rsp_beat_out            (o_rdata_rsp_beat_out[beatid_width-1:0]),
       .o_rdata_rsp_tag_out             (o_rdata_rsp_tag_out[tag_width-1:0]),
       .o_rdata_rsp_tag_par_out         (o_rdata_rsp_tag_par_out[tag_par_width-1:0]),
       .o_rdata_rsp_data_out            (o_rdata_rsp_data_out[data_width-1:0]),
       .o_rdata_rsp_data_par_out        (o_rdata_rsp_data_par_out[data_fc_par_width-1:0]),
       .o_rsp_v_out                     (o_rsp_v_out),
       .o_rsp_tag_out                   (o_rsp_tag_out[tag_width-1:0]),
       .o_rsp_tag_par_out               (o_rsp_tag_par_out[tag_par_width-1:0]),
       .o_rsp_fc_status_out             (o_rsp_fc_status_out[fcstat_width-1:0]),
       .o_rsp_fcx_status_out            (o_rsp_fcx_status_out[fcxstat_width-1:0]),
       .o_rsp_scsi_status_out           (o_rsp_scsi_status_out[7:0]),
       .o_rsp_sns_valid_out             (o_rsp_sns_valid_out),
       .o_rsp_fcp_valid_out             (o_rsp_fcp_valid_out),
       .o_rsp_underrun_out              (o_rsp_underrun_out),
       .o_rsp_overrun_out               (o_rsp_overrun_out),
       .o_rsp_resid_out                 (o_rsp_resid_out[31:0]),
       .o_rsp_rdata_beats_out           (o_rsp_rdata_beats_out[beatid_width-1:0]),
       .o_rsp_info_out                  (o_rsp_info_out[rsp_info_width-1:0]),
       .sntl_ioq_req_lba                (sntl_ioq_req_lba[63:0]),
       .sntl_ioq_req_numblks            (sntl_ioq_req_numblks[15:0]),
       .sntl_ioq_req_nsid               (sntl_ioq_req_nsid[31:0]),
       .sntl_ioq_req_opcode             (sntl_ioq_req_opcode[7:0]),
       .sntl_ioq_req_cmdid              (sntl_ioq_req_cmdid[15:0]),
       .sntl_ioq_req_wbufid             (sntl_ioq_req_wbufid[wbufid_width-1:0]),
       .sntl_ioq_req_reloff             (sntl_ioq_req_reloff[datalen_width-1:0]),
       .sntl_ioq_req_fua                (sntl_ioq_req_fua),
       .sntl_ioq_req_sqid               (sntl_ioq_req_sqid[isq_idwidth-1:0]),
       .sntl_ioq_req_valid              (sntl_ioq_req_valid),
       .sntl_ioq_sqid_ack               (sntl_ioq_sqid_ack),
       .sntl_ioq_sqid                   (sntl_ioq_sqid[isq_idwidth-1:0]),
       .sntl_ioq_cpl_ack                (sntl_ioq_cpl_ack),
       .sntl_ctl_ioread_data            (sntl_ctl_ioread_data[31:0]),
       .sntl_ctl_ioack                  (sntl_ctl_ioack),
       .sntl_pcie_pause                 (sntl_pcie_pause),
       .sntl_pcie_ready                 (sntl_pcie_ready),
       .sntl_pcie_cc_data               (sntl_pcie_cc_data[144:0]),
       .sntl_pcie_cc_first              (sntl_pcie_cc_first),
       .sntl_pcie_cc_last               (sntl_pcie_cc_last),
       .sntl_pcie_cc_discard            (sntl_pcie_cc_discard),
       .sntl_pcie_cc_valid              (sntl_pcie_cc_valid),
       .sntl_pcie_wbuf_pause            (sntl_pcie_wbuf_pause),
       .sntl_pcie_wbuf_cc_data          (sntl_pcie_wbuf_cc_data[144:0]),
       .sntl_pcie_wbuf_cc_first         (sntl_pcie_wbuf_cc_first),
       .sntl_pcie_wbuf_cc_last          (sntl_pcie_wbuf_cc_last),
       .sntl_pcie_wbuf_cc_discard       (sntl_pcie_wbuf_cc_discard),
       .sntl_pcie_wbuf_cc_valid         (sntl_pcie_wbuf_cc_valid),
       .sntl_pcie_adbuf_pause           (sntl_pcie_adbuf_pause),
       .sntl_pcie_adbuf_cc_data         (sntl_pcie_adbuf_cc_data[144:0]),
       .sntl_pcie_adbuf_cc_first        (sntl_pcie_adbuf_cc_first),
       .sntl_pcie_adbuf_cc_last         (sntl_pcie_adbuf_cc_last),
       .sntl_pcie_adbuf_cc_discard      (sntl_pcie_adbuf_cc_discard),
       .sntl_pcie_adbuf_cc_valid        (sntl_pcie_adbuf_cc_valid),
       .sntl_ctl_admin_cmd_valid        (sntl_ctl_admin_cmd_valid),
       .sntl_ctl_admin_cpl_valid        (sntl_ctl_admin_cpl_valid),
       .cmd_regs_lunreset               (cmd_regs_lunreset),
       .sntl_ctl_idle                   (sntl_ctl_idle),
       .sntl_regs_dbg_data              (sntl_regs_dbg_data[63:0]),
       .sntl_regs_dbg_ack               (sntl_regs_dbg_ack),
       .cmd_regs_trk_data               (cmd_regs_trk_data[511:0]),
       .cmd_regs_trk_ack                (cmd_regs_trk_ack),
       .cmd_regs_dbgcount               (cmd_regs_dbgcount[31:0]),
       .sntl_regs_rdata_paused          (sntl_regs_rdata_paused),
       .sntl_regs_cmd_idle              (sntl_regs_cmd_idle),
       .wbuf_regs_error                 (wbuf_regs_error[3:0]),
       .sntl_regs_rsp_cnt               (sntl_regs_rsp_cnt),
       .cmd_regs_errinj_ack             (cmd_regs_errinj_ack),
       .cmd_regs_errinj_cmdrd           (cmd_regs_errinj_cmdrd),
       .cmd_regs_errinj_cmdwr           (cmd_regs_errinj_cmdwr),
       .wdata_regs_errinj_ack           (wdata_regs_errinj_ack),
       .wdata_regs_errinj_active        (wdata_regs_errinj_active),
       .admin_perror_ind                (admin_perror_ind[3:0]),
       .wbuf_perror_ind                 (wbuf_perror_ind[2:0]),
       .wdata_perror_ind                (wdata_perror_ind),
       .cmd_perror_ind                  (cmd_perror_ind[5:0]),
       .dma_perror_ind                  (dma_perror_ind[7:0]),
       .rsp_perror_ind                  (rsp_perror_ind),
       // Inputs
       .reset                           (reset),
       .clk                             (clk),
       .i_req_v_in                      (i_req_v_in),
       .i_req_cmd_in                    (i_req_cmd_in[cmd_width-1:0]),
       .i_req_tag_in                    (i_req_tag_in[tag_width-1:0]),
       .i_req_tag_par_in                (i_req_tag_par_in[tag_par_width-1:0]),
       .i_req_lun_in                    (i_req_lun_in[lunid_width-1:0]),
       .i_req_lun_par_in                (i_req_lun_par_in[lunid_par_width-1:0]),
       .i_req_length_in                 (i_req_length_in[datalen_width-1:0]),
       .i_req_length_par_in             (i_req_length_par_in),
       .i_req_cdb_in                    (i_req_cdb_in[127:0]),
       .i_req_cdb_par_in                (i_req_cdb_par_in[1:0]),
       .o_wdata_req_r_in                (o_wdata_req_r_in),
       .i_wdata_rsp_v_in                (i_wdata_rsp_v_in),
       .i_wdata_rsp_e_in                (i_wdata_rsp_e_in),
       .i_wdata_rsp_error_in            (i_wdata_rsp_error_in),
       .i_wdata_rsp_tag_in              (i_wdata_rsp_tag_in[tag_width-1:0]),
       .i_wdata_rsp_tag_par_in          (i_wdata_rsp_tag_par_in),
       .i_wdata_rsp_beat_in             (i_wdata_rsp_beat_in[beatid_width-1:0]),
       .i_wdata_rsp_data_in             (i_wdata_rsp_data_in[data_width-1:0]),
       .i_wdata_rsp_data_par_in         (i_wdata_rsp_data_par_in[data_fc_par_width-1:0]),
       .o_rdata_rsp_r_in                (o_rdata_rsp_r_in),
       .ioq_sntl_req_ack                (ioq_sntl_req_ack),
       .ioq_sntl_sqid_valid             (ioq_sntl_sqid_valid),
       .ioq_sntl_sqid                   (ioq_sntl_sqid[isq_idwidth-1:0]),
       .ioq_sntl_cpl_status             (ioq_sntl_cpl_status[14:0]),
       .ioq_sntl_cpl_cmdid              (ioq_sntl_cpl_cmdid[15:0]),
       .ioq_sntl_cpl_cmdid_par          (ioq_sntl_cpl_cmdid_par[1:0]),
       .ioq_sntl_cpl_valid              (ioq_sntl_cpl_valid),
       .ctl_sntl_ioaddress              (ctl_sntl_ioaddress[31:0]),
       .ctl_sntl_ioread_strobe          (ctl_sntl_ioread_strobe),
       .ctl_sntl_iowrite_data           (ctl_sntl_iowrite_data[35:0]),
       .ctl_sntl_iowrite_strobe         (ctl_sntl_iowrite_strobe),
       .pcie_sntl_valid                 (pcie_sntl_valid),
       .pcie_sntl_data                  (pcie_sntl_data[144:0]),
       .pcie_sntl_first                 (pcie_sntl_first),
       .pcie_sntl_last                  (pcie_sntl_last),
       .pcie_sntl_discard               (pcie_sntl_discard),
       .pcie_sntl_cc_ready              (pcie_sntl_cc_ready),
       .pcie_sntl_wbuf_valid            (pcie_sntl_wbuf_valid),
       .pcie_sntl_wbuf_data             (pcie_sntl_wbuf_data[144:0]),
       .pcie_sntl_wbuf_first            (pcie_sntl_wbuf_first),
       .pcie_sntl_wbuf_last             (pcie_sntl_wbuf_last),
       .pcie_sntl_wbuf_discard          (pcie_sntl_wbuf_discard),
       .pcie_sntl_wbuf_cc_ready         (pcie_sntl_wbuf_cc_ready),
       .pcie_sntl_adbuf_valid           (pcie_sntl_adbuf_valid),
       .pcie_sntl_adbuf_data            (pcie_sntl_adbuf_data[144:0]),
       .pcie_sntl_adbuf_first           (pcie_sntl_adbuf_first),
       .pcie_sntl_adbuf_last            (pcie_sntl_adbuf_last),
       .pcie_sntl_adbuf_discard         (pcie_sntl_adbuf_discard),
       .pcie_sntl_adbuf_cc_ready        (pcie_sntl_adbuf_cc_ready),
       .ctl_xx_csts_rdy                 (ctl_xx_csts_rdy),
       .ctl_xx_ioq_enable               (ctl_xx_ioq_enable),
       .ctl_xx_shutdown                 (ctl_xx_shutdown),
       .ctl_xx_shutdown_cmp             (ctl_xx_shutdown_cmp),
       .regs_xx_tick1                   (regs_xx_tick1),
       .regs_xx_timer1                  (regs_xx_timer1[35:0]),
       .regs_xx_timer2                  (regs_xx_timer2[15:0]),
       .regs_cmd_IOtimeout2             (regs_cmd_IOtimeout2[15:0]),
       .regs_cmd_disableto              (regs_cmd_disableto),
       .regs_xx_maxxfer                 (regs_xx_maxxfer[datalen_width-1-12:0]),
       .regs_cmd_maxiowr                (regs_cmd_maxiowr[tag_width:0]),
       .regs_cmd_maxiord                (regs_cmd_maxiord[tag_width:0]),
       .regs_cmd_debug                  (regs_cmd_debug[15:0]),
       .regs_sntl_rsp_debug             (regs_sntl_rsp_debug),
       .regs_dma_errcpl                 (regs_dma_errcpl[7:0]),
       .regs_xx_freeze                  (regs_xx_freeze),
       .regs_unmap_timer1               (regs_unmap_timer1[11:0]),
       .regs_unmap_timer2               (regs_unmap_timer2[19:0]),
       .regs_unmap_rangecount           (regs_unmap_rangecount[7:0]),
       .regs_unmap_reqcount             (regs_unmap_reqcount[7:0]),
       .pcie_sntl_rxcq_perf_events      (pcie_sntl_rxcq_perf_events[7:0]),
       .regs_sntl_perf_reset            (regs_sntl_perf_reset),
       .regs_sntl_dbg_rd                (regs_sntl_dbg_rd),
       .regs_sntl_dbg_addr              (regs_sntl_dbg_addr[9:0]),
       .regs_cmd_trk_rd                 (regs_cmd_trk_rd),
       .regs_cmd_trk_addr               (regs_cmd_trk_addr[tag_width-1:0]),
       .regs_cmd_trk_addr_par           (regs_cmd_trk_addr_par),
       .regs_cmd_errinj_valid           (regs_cmd_errinj_valid),
       .regs_cmd_errinj_select          (regs_cmd_errinj_select[3:0]),
       .regs_cmd_errinj_lba             (regs_cmd_errinj_lba[31:0]),
       .regs_cmd_errinj_uselba          (regs_cmd_errinj_uselba),
       .regs_cmd_errinj_status          (regs_cmd_errinj_status[15:0]),
       .regs_wdata_errinj_valid         (regs_wdata_errinj_valid),
       .regs_sntl_pe_errinj_valid       (regs_sntl_pe_errinj_valid),
       .regs_xxx_pe_errinj_decode       (regs_xxx_pe_errinj_decode[15:0]),
       .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));
                 

  nvme_ioq #( .data_width(data_width),
              .wbuf_numids(wbuf_numids),
              .num_isq(num_isq),
              .isq_idwidth(isq_idwidth)
             ) nvme_ioq
       (/*AUTOINST*/
        // Outputs
        .ioq_sntl_sqid_valid            (ioq_sntl_sqid_valid),
        .ioq_sntl_sqid                  (ioq_sntl_sqid[isq_idwidth-1:0]),
        .ioq_sntl_req_ack               (ioq_sntl_req_ack),
        .ioq_sntl_cpl_status            (ioq_sntl_cpl_status[14:0]),
        .ioq_sntl_cpl_cmdid             (ioq_sntl_cpl_cmdid[15:0]),
        .ioq_sntl_cpl_cmdid_par         (ioq_sntl_cpl_cmdid_par[1:0]),
        .ioq_sntl_cpl_valid             (ioq_sntl_cpl_valid),
        .ioq_pcie_wrvalid               (ioq_pcie_wrvalid),
        .ioq_pcie_wraddr                (ioq_pcie_wraddr[31:0]),
        .ioq_pcie_wrdata                (ioq_pcie_wrdata[15:0]),
        .ioq_pcie_pause                 (ioq_pcie_pause),
        .ioq_pcie_cc_data               (ioq_pcie_cc_data[144:0]),
        .ioq_pcie_cc_first              (ioq_pcie_cc_first),
        .ioq_pcie_cc_last               (ioq_pcie_cc_last),
        .ioq_pcie_cc_discard            (ioq_pcie_cc_discard),
        .ioq_pcie_cc_valid              (ioq_pcie_cc_valid),
        .ioq_ctl_ioread_data            (ioq_ctl_ioread_data[31:0]),
        .ioq_ctl_ioack                  (ioq_ctl_ioack),
        .ioq_xx_isq_empty               (ioq_xx_isq_empty),
        .ioq_xx_icq_empty               (ioq_xx_icq_empty),
        .ioq_regs_dbg_data              (ioq_regs_dbg_data[63:0]),
        .ioq_regs_dbg_ack               (ioq_regs_dbg_ack),
        .ioq_regs_faterr                (ioq_regs_faterr[3:0]),
        .ioq_regs_recerr                (ioq_regs_recerr[3:0]),
        .ioq_perror_ind                 (ioq_perror_ind[1:0]),
        // Inputs
        .reset                          (reset),
        .clk                            (clk),
        .sntl_ioq_sqid_ack              (sntl_ioq_sqid_ack),
        .sntl_ioq_sqid                  (sntl_ioq_sqid[isq_idwidth-1:0]),
        .sntl_ioq_req_lba               (sntl_ioq_req_lba[63:0]),
        .sntl_ioq_req_numblks           (sntl_ioq_req_numblks[15:0]),
        .sntl_ioq_req_nsid              (sntl_ioq_req_nsid[31:0]),
        .sntl_ioq_req_opcode            (sntl_ioq_req_opcode[7:0]),
        .sntl_ioq_req_cmdid             (sntl_ioq_req_cmdid[15:0]),
        .sntl_ioq_req_wbufid            (sntl_ioq_req_wbufid[wbufid_width-1:0]),
        .sntl_ioq_req_reloff            (sntl_ioq_req_reloff[datalen_width-1:0]),
        .sntl_ioq_req_fua               (sntl_ioq_req_fua),
        .sntl_ioq_req_sqid              (sntl_ioq_req_sqid[isq_idwidth-1:0]),
        .sntl_ioq_req_valid             (sntl_ioq_req_valid),
        .sntl_ioq_cpl_ack               (sntl_ioq_cpl_ack),
        .pcie_ioq_wrack                 (pcie_ioq_wrack),
        .pcie_ioq_valid                 (pcie_ioq_valid),
        .pcie_ioq_data                  (pcie_ioq_data[144:0]),
        .pcie_ioq_first                 (pcie_ioq_first),
        .pcie_ioq_last                  (pcie_ioq_last),
        .pcie_ioq_discard               (pcie_ioq_discard),
        .pcie_ioq_cc_ready              (pcie_ioq_cc_ready),
        .ctl_ioq_ioaddress              (ctl_ioq_ioaddress[31:0]),
        .ctl_ioq_ioread_strobe          (ctl_ioq_ioread_strobe),
        .ctl_ioq_iowrite_data           (ctl_ioq_iowrite_data[35:0]),
        .ctl_ioq_iowrite_strobe         (ctl_ioq_iowrite_strobe),
        .ctl_xx_ioq_enable              (ctl_xx_ioq_enable),
        .regs_ioq_dbg_rd                (regs_ioq_dbg_rd),
        .regs_ioq_dbg_addr              (regs_ioq_dbg_addr[9:0]),
        .regs_ioq_icqto                 (regs_ioq_icqto[15:0]),
        .regs_xx_tick2                  (regs_xx_tick2),
        .regs_ioq_pe_errinj_valid       (regs_ioq_pe_errinj_valid),
        .regs_xxx_pe_errinj_decode      (regs_xxx_pe_errinj_decode[15:0]),
        .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));
              
  nvme_ucq nvme_ucq
       (/*AUTOINST*/
        // Outputs
        .adq_ctl_ioread_data            (adq_ctl_ioread_data[35:0]),
        .adq_ctl_ioack                  (adq_ctl_ioack),
        .adq_pcie_wrvalid               (adq_pcie_wrvalid),
        .adq_pcie_wraddr                (adq_pcie_wraddr[31:0]),
        .adq_pcie_wrdata                (adq_pcie_wrdata[15:0]),
        .adq_pcie_pause                 (adq_pcie_pause),
        .adq_pcie_cc_data               (adq_pcie_cc_data[144:0]),
        .adq_pcie_cc_first              (adq_pcie_cc_first),
        .adq_pcie_cc_last               (adq_pcie_cc_last),
        .adq_pcie_cc_discard            (adq_pcie_cc_discard),
        .adq_pcie_cc_valid              (adq_pcie_cc_valid),
        .adq_ctl_cpl_empty              (adq_ctl_cpl_empty[1:0]),
        .adq_regs_dbg_data              (adq_regs_dbg_data[63:0]),
        .adq_regs_dbg_ack               (adq_regs_dbg_ack),
        .adq_perror_ind                 (adq_perror_ind),
        // Inputs
        .reset                          (reset),
        .clk                            (clk),
        .ctl_adq_ioaddress              (ctl_adq_ioaddress[31:0]),
        .ctl_adq_ioread_strobe          (ctl_adq_ioread_strobe),
        .ctl_adq_iowrite_data           (ctl_adq_iowrite_data[35:0]),
        .ctl_adq_iowrite_strobe         (ctl_adq_iowrite_strobe),
        .pcie_adq_wrack                 (pcie_adq_wrack),
        .pcie_adq_valid                 (pcie_adq_valid),
        .pcie_adq_data                  (pcie_adq_data[144:0]),
        .pcie_adq_first                 (pcie_adq_first),
        .pcie_adq_last                  (pcie_adq_last),
        .pcie_adq_discard               (pcie_adq_discard),
        .pcie_adq_cc_ready              (pcie_adq_cc_ready),
        .regs_adq_dbg_rd                (regs_adq_dbg_rd),
        .regs_adq_dbg_addr              (regs_adq_dbg_addr[9:0]),
        .regs_adq_pe_errinj_valid       (regs_adq_pe_errinj_valid),
        .regs_xxx_pe_errinj_decode      (regs_xxx_pe_errinj_decode[15:0]),
        .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));
               
   nvme_pcie#
     (
      .port_id(port_id) 
      ) nvme_pcie 
       (/*AUTOINST*/
        // Outputs
        .pci_exp_txp                    (pci_exp_txp[LINK_WIDTH-1:0]),
        .pci_exp_txn                    (pci_exp_txn[LINK_WIDTH-1:0]),
        .pci_exp_nperst                 (pci_exp_nperst),
        .pcie_ctl_ioread_data           (pcie_ctl_ioread_data[31:0]),
        .pcie_ctl_ioread_datap          (pcie_ctl_ioread_datap[3:0]),
        .pcie_ctl_ioack                 (pcie_ctl_ioack),
        .pcie_adq_wrack                 (pcie_adq_wrack),
        .pcie_ioq_wrack                 (pcie_ioq_wrack),
        .pcie_adq_valid                 (pcie_adq_valid),
        .pcie_adq_data                  (pcie_adq_data[144:0]),
        .pcie_adq_first                 (pcie_adq_first),
        .pcie_adq_last                  (pcie_adq_last),
        .pcie_adq_discard               (pcie_adq_discard),
        .pcie_ioq_valid                 (pcie_ioq_valid),
        .pcie_ioq_data                  (pcie_ioq_data[144:0]),
        .pcie_ioq_first                 (pcie_ioq_first),
        .pcie_ioq_last                  (pcie_ioq_last),
        .pcie_ioq_discard               (pcie_ioq_discard),
        .pcie_sntl_valid                (pcie_sntl_valid),
        .pcie_sntl_data                 (pcie_sntl_data[144:0]),
        .pcie_sntl_first                (pcie_sntl_first),
        .pcie_sntl_last                 (pcie_sntl_last),
        .pcie_sntl_discard              (pcie_sntl_discard),
        .pcie_sntl_wbuf_valid           (pcie_sntl_wbuf_valid),
        .pcie_sntl_wbuf_data            (pcie_sntl_wbuf_data[144:0]),
        .pcie_sntl_wbuf_first           (pcie_sntl_wbuf_first),
        .pcie_sntl_wbuf_last            (pcie_sntl_wbuf_last),
        .pcie_sntl_wbuf_discard         (pcie_sntl_wbuf_discard),
        .pcie_sntl_adbuf_valid          (pcie_sntl_adbuf_valid),
        .pcie_sntl_adbuf_data           (pcie_sntl_adbuf_data[144:0]),
        .pcie_sntl_adbuf_first          (pcie_sntl_adbuf_first),
        .pcie_sntl_adbuf_last           (pcie_sntl_adbuf_last),
        .pcie_sntl_adbuf_discard        (pcie_sntl_adbuf_discard),
        .pcie_adq_cc_ready              (pcie_adq_cc_ready),
        .pcie_ioq_cc_ready              (pcie_ioq_cc_ready),
        .pcie_sntl_cc_ready             (pcie_sntl_cc_ready),
        .pcie_sntl_wbuf_cc_ready        (pcie_sntl_wbuf_cc_ready),
        .pcie_sntl_adbuf_cc_ready       (pcie_sntl_adbuf_cc_ready),
        .pcie_regs_ack                  (pcie_regs_ack),
        .pcie_regs_cpl_data             (pcie_regs_cpl_data[31:0]),
        .pcie_regs_cpl_datap            (pcie_regs_cpl_datap[3:0]),
        .pcie_regs_cpl_valid            (pcie_regs_cpl_valid),
        .pcie_regs_cpl_status           (pcie_regs_cpl_status[15:0]),
        .pcie_regs_dbg_data             (pcie_regs_dbg_data[63:0]),
        .pcie_regs_dbg_ack              (pcie_regs_dbg_ack),
        .pcie_regs_rxcq_errinj_ack      (pcie_regs_rxcq_errinj_ack),
        .pcie_regs_rxcq_errinj_active   (pcie_regs_rxcq_errinj_active),
        .pcie_xx_link_up                (pcie_xx_link_up),
        .pcie_xx_init_done              (pcie_xx_init_done),
        .pcie_regs_status               (pcie_regs_status[31:0]),
        .pcie_regs_sisl_backpressure    (pcie_regs_sisl_backpressure),
        .pcie_regs_rxcq_backpressure    (pcie_regs_rxcq_backpressure),
        .pcie_sntl_rxcq_perf_events     (pcie_sntl_rxcq_perf_events[7:0]),
        .pcie_regs_dbg_error            (pcie_regs_dbg_error[1:0]),
        .pcie_regs_rxcq_error           (pcie_regs_rxcq_error[3:0]),
        .cdc_hold_cfg_err_fatal_out     (cdc_hold_cfg_err_fatal_out),
        .ctlff_perror_ind               (ctlff_perror_ind),
        .cdc_ctlff_perror_ind           (cdc_ctlff_perror_ind),
        .rxcq_perror_ind                (rxcq_perror_ind),
        .cdc_rxcq_perror_ind            (cdc_rxcq_perror_ind[1:0]),
        .cdc_rxrc_perror_ind            (cdc_rxrc_perror_ind),
        .txcc_perror_ind                (txcc_perror_ind[2:0]),
        .cdc_txcc_perror_ind            (cdc_txcc_perror_ind[1:0]),
        .cdc_txrq_perror_ind            (cdc_txrq_perror_ind),
        // Inputs
        .reset                          (reset),
        .clk                            (clk),
        .pci_exp_rxp                    (pci_exp_rxp[LINK_WIDTH-1:0]),
        .pci_exp_rxn                    (pci_exp_rxn[LINK_WIDTH-1:0]),
        .pci_exp_refclk_p               (pci_exp_refclk_p),
        .pci_exp_refclk_n               (pci_exp_refclk_n),
        .ctl_pcie_ioaddress             (ctl_pcie_ioaddress[31:0]),
        .ctl_pcie_ioread_strobe         (ctl_pcie_ioread_strobe),
        .ctl_pcie_iowrite_data          (ctl_pcie_iowrite_data[31:0]),
        .ctl_pcie_iowrite_strobe        (ctl_pcie_iowrite_strobe),
        .adq_pcie_wrvalid               (adq_pcie_wrvalid),
        .adq_pcie_wraddr                (adq_pcie_wraddr[31:0]),
        .adq_pcie_wrdata                (adq_pcie_wrdata[15:0]),
        .ioq_pcie_wrvalid               (ioq_pcie_wrvalid),
        .ioq_pcie_wraddr                (ioq_pcie_wraddr[31:0]),
        .ioq_pcie_wrdata                (ioq_pcie_wrdata[15:0]),
        .adq_pcie_pause                 (adq_pcie_pause),
        .ioq_pcie_pause                 (ioq_pcie_pause),
        .sntl_pcie_pause                (sntl_pcie_pause),
        .sntl_pcie_ready                (sntl_pcie_ready),
        .sntl_pcie_wbuf_pause           (sntl_pcie_wbuf_pause),
        .sntl_pcie_adbuf_pause          (sntl_pcie_adbuf_pause),
        .adq_pcie_cc_data               (adq_pcie_cc_data[144:0]),
        .adq_pcie_cc_first              (adq_pcie_cc_first),
        .adq_pcie_cc_last               (adq_pcie_cc_last),
        .adq_pcie_cc_discard            (adq_pcie_cc_discard),
        .adq_pcie_cc_valid              (adq_pcie_cc_valid),
        .ioq_pcie_cc_data               (ioq_pcie_cc_data[144:0]),
        .ioq_pcie_cc_first              (ioq_pcie_cc_first),
        .ioq_pcie_cc_last               (ioq_pcie_cc_last),
        .ioq_pcie_cc_discard            (ioq_pcie_cc_discard),
        .ioq_pcie_cc_valid              (ioq_pcie_cc_valid),
        .sntl_pcie_cc_data              (sntl_pcie_cc_data[144:0]),
        .sntl_pcie_cc_first             (sntl_pcie_cc_first),
        .sntl_pcie_cc_last              (sntl_pcie_cc_last),
        .sntl_pcie_cc_discard           (sntl_pcie_cc_discard),
        .sntl_pcie_cc_valid             (sntl_pcie_cc_valid),
        .sntl_pcie_wbuf_cc_data         (sntl_pcie_wbuf_cc_data[144:0]),
        .sntl_pcie_wbuf_cc_first        (sntl_pcie_wbuf_cc_first),
        .sntl_pcie_wbuf_cc_last         (sntl_pcie_wbuf_cc_last),
        .sntl_pcie_wbuf_cc_discard      (sntl_pcie_wbuf_cc_discard),
        .sntl_pcie_wbuf_cc_valid        (sntl_pcie_wbuf_cc_valid),
        .sntl_pcie_adbuf_cc_data        (sntl_pcie_adbuf_cc_data[144:0]),
        .sntl_pcie_adbuf_cc_first       (sntl_pcie_adbuf_cc_first),
        .sntl_pcie_adbuf_cc_last        (sntl_pcie_adbuf_cc_last),
        .sntl_pcie_adbuf_cc_discard     (sntl_pcie_adbuf_cc_discard),
        .sntl_pcie_adbuf_cc_valid       (sntl_pcie_adbuf_cc_valid),
        .regs_pcie_valid                (regs_pcie_valid),
        .regs_pcie_rnw                  (regs_pcie_rnw),
        .regs_pcie_configop             (regs_pcie_configop),
        .regs_pcie_tag                  (regs_pcie_tag[3:0]),
        .regs_pcie_be                   (regs_pcie_be[3:0]),
        .regs_pcie_addr                 (regs_pcie_addr[31:0]),
        .regs_pcie_wrdata               (regs_pcie_wrdata[31:0]),
        .regs_pcie_perst                (regs_pcie_perst),
        .regs_pcie_debug                (regs_pcie_debug[7:0]),
        .regs_pcie_debug_trace          (regs_pcie_debug_trace[31:0]),
        .regs_xx_tick1                  (regs_xx_tick1),
        .regs_pcie_dbg_rd               (regs_pcie_dbg_rd),
        .regs_pcie_dbg_addr             (regs_pcie_dbg_addr[15:0]),
        .regs_pcie_rxcq_errinj_valid    (regs_pcie_rxcq_errinj_valid),
        .regs_pcie_rxcq_errinj_delay    (regs_pcie_rxcq_errinj_delay[19:0]),
        .regs_wdata_pe_errinj_valid     (regs_wdata_pe_errinj_valid),
        .regs_pcie_pe_errinj_valid      (regs_pcie_pe_errinj_valid),
        .regs_xxx_pe_errinj_decode      (regs_xxx_pe_errinj_decode[15:0]),
        .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid));

   nvme_control#
     (
      .port_id(port_id)
      ) control 
       (/*AUTOINST*/
        // Outputs
        .ctl_pcie_ioaddress             (ctl_pcie_ioaddress[31:0]),
        .ctl_pcie_iowrite_data          (ctl_pcie_iowrite_data[35:0]),
        .ctl_pcie_ioread_strobe         (ctl_pcie_ioread_strobe),
        .ctl_pcie_iowrite_strobe        (ctl_pcie_iowrite_strobe),
        .ctl_adq_ioaddress              (ctl_adq_ioaddress[31:0]),
        .ctl_adq_iowrite_data           (ctl_adq_iowrite_data[35:0]),
        .ctl_adq_ioread_strobe          (ctl_adq_ioread_strobe),
        .ctl_adq_iowrite_strobe         (ctl_adq_iowrite_strobe),
        .ctl_sntl_ioaddress             (ctl_sntl_ioaddress[31:0]),
        .ctl_sntl_iowrite_data          (ctl_sntl_iowrite_data[35:0]),
        .ctl_sntl_ioread_strobe         (ctl_sntl_ioread_strobe),
        .ctl_sntl_iowrite_strobe        (ctl_sntl_iowrite_strobe),
        .ctl_ioq_ioaddress              (ctl_ioq_ioaddress[31:0]),
        .ctl_ioq_iowrite_data           (ctl_ioq_iowrite_data[35:0]),
        .ctl_ioq_ioread_strobe          (ctl_ioq_ioread_strobe),
        .ctl_ioq_iowrite_strobe         (ctl_ioq_iowrite_strobe),
        .ctl_regs_ioaddress             (ctl_regs_ioaddress[31:0]),
        .ctl_regs_iowrite_data          (ctl_regs_iowrite_data[35:0]),
        .ctl_regs_ioread_strobe         (ctl_regs_ioread_strobe),
        .ctl_regs_iowrite_strobe        (ctl_regs_iowrite_strobe),
        .ctl_xx_ioq_enable              (ctl_xx_ioq_enable),
        .ctl_xx_csts_rdy                (ctl_xx_csts_rdy),
        .ctl_xx_shutdown                (ctl_xx_shutdown),
        .ctl_xx_shutdown_cmp            (ctl_xx_shutdown_cmp),
        .ctl_regs_ustatus               (ctl_regs_ustatus[31:0]),
        // Inputs
        .reset                          (reset),
        .clk                            (clk),
        .clk_div2                       (clk_div2),
        .pcie_ctl_ioread_data           (pcie_ctl_ioread_data[31:0]),
        .pcie_ctl_ioack                 (pcie_ctl_ioack),
        .adq_ctl_ioread_data            (adq_ctl_ioread_data[31:0]),
        .adq_ctl_ioack                  (adq_ctl_ioack),
        .sntl_ctl_ioread_data           (sntl_ctl_ioread_data[31:0]),
        .sntl_ctl_ioack                 (sntl_ctl_ioack),
        .ioq_ctl_ioread_data            (ioq_ctl_ioread_data[31:0]),
        .ioq_ctl_ioack                  (ioq_ctl_ioack),
        .regs_ctl_ioread_data           (regs_ctl_ioread_data[31:0]),
        .regs_ctl_ioack                 (regs_ctl_ioack),
        .regs_ctl_ldrom                 (regs_ctl_ldrom),
        .sntl_ctl_admin_cmd_valid       (sntl_ctl_admin_cmd_valid),
        .sntl_ctl_admin_cpl_valid       (sntl_ctl_admin_cpl_valid),
        .regs_ctl_enable                (regs_ctl_enable),
        .regs_ctl_shutdown              (regs_ctl_shutdown),
        .regs_ctl_shutdown_abrupt       (regs_ctl_shutdown_abrupt),
        .regs_ctl_lunreset              (regs_ctl_lunreset),
        .pcie_xx_link_up                (pcie_xx_link_up),
        .pcie_xx_init_done              (pcie_xx_init_done),
        .ioq_xx_isq_empty               (ioq_xx_isq_empty),
        .ioq_xx_icq_empty               (ioq_xx_icq_empty),
        .sntl_ctl_idle                  (sntl_ctl_idle),
        .adq_ctl_cpl_empty              (adq_ctl_cpl_empty[1:0]));


   nvme_regs#
     (
      .mmio_base(mmio_base),
      .mmio_base2(mmio_base2),
      .port_id(port_id)
      ) regs
       (/*AUTOINST*/
        // Outputs
        .led_red                        (led_red),
        .led_blue                       (led_blue),
        .led_green                      (led_green),
        .ah_mmack_out                   (ah_mmack_out),
        .ah_mmdata_out                  (ah_mmdata_out[63:0]),
        .regs_ctl_ioread_data           (regs_ctl_ioread_data[31:0]),
        .regs_ctl_ioack                 (regs_ctl_ioack),
        .o_status_event_out             (o_status_event_out[status_width-1:0]),
        .o_port_ready_out               (o_port_ready_out),
        .regs_pcie_valid                (regs_pcie_valid),
        .regs_pcie_rnw                  (regs_pcie_rnw),
        .regs_pcie_configop             (regs_pcie_configop),
        .regs_pcie_tag                  (regs_pcie_tag[3:0]),
        .regs_pcie_be                   (regs_pcie_be[3:0]),
        .regs_pcie_addr                 (regs_pcie_addr[31:0]),
        .regs_pcie_wrdata               (regs_pcie_wrdata[31:0]),
        .regs_cmd_trk_rd                (regs_cmd_trk_rd),
        .regs_cmd_trk_addr              (regs_cmd_trk_addr[tag_width-1:0]),
        .regs_cmd_trk_addr_par          (regs_cmd_trk_addr_par),
        .regs_ioq_dbg_rd                (regs_ioq_dbg_rd),
        .regs_ioq_dbg_addr              (regs_ioq_dbg_addr[9:0]),
        .regs_adq_dbg_rd                (regs_adq_dbg_rd),
        .regs_adq_dbg_addr              (regs_adq_dbg_addr[9:0]),
        .regs_pcie_dbg_rd               (regs_pcie_dbg_rd),
        .regs_pcie_dbg_addr             (regs_pcie_dbg_addr[15:0]),
        .regs_sntl_dbg_rd               (regs_sntl_dbg_rd),
        .regs_sntl_dbg_addr             (regs_sntl_dbg_addr[9:0]),
        .regs_cmd_debug                 (regs_cmd_debug[15:0]),
        .regs_sntl_rsp_debug            (regs_sntl_rsp_debug),
        .regs_dma_errcpl                (regs_dma_errcpl[7:0]),
        .regs_cmd_errinj_valid          (regs_cmd_errinj_valid),
        .regs_cmd_errinj_select         (regs_cmd_errinj_select[3:0]),
        .regs_cmd_errinj_lba            (regs_cmd_errinj_lba[31:0]),
        .regs_cmd_errinj_uselba         (regs_cmd_errinj_uselba),
        .regs_cmd_errinj_status         (regs_cmd_errinj_status[15:0]),
        .regs_wdata_errinj_valid        (regs_wdata_errinj_valid),
        .regs_adq_pe_errinj_valid       (regs_adq_pe_errinj_valid),
        .regs_ioq_pe_errinj_valid       (regs_ioq_pe_errinj_valid),
        .regs_pcie_pe_errinj_valid      (regs_pcie_pe_errinj_valid),
        .regs_sntl_pe_errinj_valid      (regs_sntl_pe_errinj_valid),
        .regs_xxx_pe_errinj_decode      (regs_xxx_pe_errinj_decode[15:0]),
        .regs_wdata_pe_errinj_valid     (regs_wdata_pe_errinj_valid),
        .regs_wdata_pe_errinj_1cycle_valid(regs_wdata_pe_errinj_1cycle_valid),
        .regs_pcie_rxcq_errinj_valid    (regs_pcie_rxcq_errinj_valid),
        .regs_pcie_rxcq_errinj_delay    (regs_pcie_rxcq_errinj_delay[19:0]),
        .regs_xx_timer1                 (regs_xx_timer1[35:0]),
        .regs_xx_timer2                 (regs_xx_timer2[15:0]),
        .regs_cmd_IOtimeout2            (regs_cmd_IOtimeout2[15:0]),
        .regs_ioq_icqto                 (regs_ioq_icqto[15:0]),
        .regs_xx_tick1                  (regs_xx_tick1),
        .regs_xx_tick2                  (regs_xx_tick2),
        .regs_cmd_disableto             (regs_cmd_disableto),
        .regs_xx_maxxfer                (regs_xx_maxxfer[datalen_width-1-12:0]),
        .regs_cmd_maxiowr               (regs_cmd_maxiowr[tag_width:0]),
        .regs_cmd_maxiord               (regs_cmd_maxiord[tag_width:0]),
        .regs_unmap_timer1              (regs_unmap_timer1[11:0]),
        .regs_unmap_timer2              (regs_unmap_timer2[19:0]),
        .regs_unmap_rangecount          (regs_unmap_rangecount[7:0]),
        .regs_unmap_reqcount            (regs_unmap_reqcount[7:0]),
        .regs_pcie_perst                (regs_pcie_perst),
        .regs_pcie_debug                (regs_pcie_debug[7:0]),
        .regs_pcie_debug_trace          (regs_pcie_debug_trace[31:0]),
        .regs_ctl_enable                (regs_ctl_enable),
        .regs_ctl_ldrom                 (regs_ctl_ldrom),
        .regs_ctl_lunreset              (regs_ctl_lunreset),
        .regs_ctl_shutdown              (regs_ctl_shutdown),
        .regs_ctl_shutdown_abrupt       (regs_ctl_shutdown_abrupt),
        .regs_xx_disable_reset          (regs_xx_disable_reset),
        .regs_xx_freeze                 (regs_xx_freeze),
        .o_port_fatal_error             (o_port_fatal_error),
        .o_port_enable_pe               (o_port_enable_pe),
        .regs_sntl_perf_reset           (regs_sntl_perf_reset),
        // Inputs
        .reset                          (reset),
        .clk                            (clk),
        .ha_mmval_in                    (ha_mmval_in),
        .ha_mmcfg_in                    (ha_mmcfg_in),
        .ha_mmrnw_in                    (ha_mmrnw_in),
        .ha_mmdw_in                     (ha_mmdw_in),
        .ha_mmad_in                     (ha_mmad_in[23:0]),
        .ha_mmdata_in                   (ha_mmdata_in[63:0]),
        .ctl_regs_ioaddress             (ctl_regs_ioaddress[31:0]),
        .ctl_regs_iowrite_data          (ctl_regs_iowrite_data[31:0]),
        .ctl_regs_ioread_strobe         (ctl_regs_ioread_strobe),
        .ctl_regs_iowrite_strobe        (ctl_regs_iowrite_strobe),
        .pcie_regs_ack                  (pcie_regs_ack),
        .pcie_regs_cpl_data             (pcie_regs_cpl_data[31:0]),
        .pcie_regs_cpl_valid            (pcie_regs_cpl_valid),
        .pcie_regs_cpl_status           (pcie_regs_cpl_status[15:0]),
        .cmd_regs_trk_data              (cmd_regs_trk_data[511:0]),
        .cmd_regs_trk_ack               (cmd_regs_trk_ack),
        .ioq_regs_dbg_data              (ioq_regs_dbg_data[63:0]),
        .ioq_regs_dbg_ack               (ioq_regs_dbg_ack),
        .adq_regs_dbg_data              (adq_regs_dbg_data[63:0]),
        .adq_regs_dbg_ack               (adq_regs_dbg_ack),
        .pcie_regs_dbg_data             (pcie_regs_dbg_data[63:0]),
        .pcie_regs_dbg_ack              (pcie_regs_dbg_ack),
        .sntl_regs_dbg_data             (sntl_regs_dbg_data[63:0]),
        .sntl_regs_dbg_ack              (sntl_regs_dbg_ack),
        .cmd_regs_dbgcount              (cmd_regs_dbgcount[31:0]),
        .sntl_regs_rsp_cnt              (sntl_regs_rsp_cnt),
        .cmd_regs_errinj_ack            (cmd_regs_errinj_ack),
        .cmd_regs_errinj_cmdrd          (cmd_regs_errinj_cmdrd),
        .cmd_regs_errinj_cmdwr          (cmd_regs_errinj_cmdwr),
        .wdata_regs_errinj_ack          (wdata_regs_errinj_ack),
        .wdata_regs_errinj_active       (wdata_regs_errinj_active),
        .pcie_regs_rxcq_errinj_ack      (pcie_regs_rxcq_errinj_ack),
        .pcie_regs_rxcq_errinj_active   (pcie_regs_rxcq_errinj_active),
        .pcie_regs_sisl_backpressure    (pcie_regs_sisl_backpressure),
        .pcie_regs_rxcq_backpressure    (pcie_regs_rxcq_backpressure),
        .sntl_regs_rdata_paused         (sntl_regs_rdata_paused),
        .sntl_regs_cmd_idle             (sntl_regs_cmd_idle),
        .cmd_regs_lunreset              (cmd_regs_lunreset),
        .pcie_xx_link_up                (pcie_xx_link_up),
        .pcie_xx_init_done              (pcie_xx_init_done),
        .pcie_regs_status               (pcie_regs_status[31:0]),
        .ctl_xx_csts_rdy                (ctl_xx_csts_rdy),
        .ctl_xx_ioq_enable              (ctl_xx_ioq_enable),
        .ctl_xx_shutdown                (ctl_xx_shutdown),
        .ctl_xx_shutdown_cmp            (ctl_xx_shutdown_cmp),
        .ioq_xx_isq_empty               (ioq_xx_isq_empty),
        .ioq_xx_icq_empty               (ioq_xx_icq_empty),
        .ctl_regs_ustatus               (ctl_regs_ustatus[31:0]),
        .ioq_regs_faterr                (ioq_regs_faterr[3:0]),
        .ioq_regs_recerr                (ioq_regs_recerr[3:0]),
        .pcie_regs_dbg_error            (pcie_regs_dbg_error[1:0]),
        .pcie_regs_rxcq_error           (pcie_regs_rxcq_error[3:0]),
        .wbuf_regs_error                (wbuf_regs_error[3:0]),
        .cdc_hold_cfg_err_fatal_out     (cdc_hold_cfg_err_fatal_out),
        .admin_perror_ind               (admin_perror_ind[3:0]),
        .wbuf_perror_ind                (wbuf_perror_ind[2:0]),
        .wdata_perror_ind               (wdata_perror_ind),
        .rsp_perror_ind                 (rsp_perror_ind),
        .cmd_perror_ind                 (cmd_perror_ind[5:0]),
        .dma_perror_ind                 (dma_perror_ind[7:0]),
        .ctlff_perror_ind               (ctlff_perror_ind),
        .cdc_ctlff_perror_ind           (cdc_ctlff_perror_ind),
        .rxcq_perror_ind                (rxcq_perror_ind),
        .cdc_rxcq_perror_ind            (cdc_rxcq_perror_ind[1:0]),
        .cdc_rxrc_perror_ind            (cdc_rxrc_perror_ind),
        .txcc_perror_ind                (txcc_perror_ind[2:0]),
        .cdc_txcc_perror_ind            (cdc_txcc_perror_ind[1:0]),
        .cdc_txrq_perror_ind            (cdc_txrq_perror_ind),
        .adq_perror_ind                 (adq_perror_ind),
        .ioq_perror_ind                 (ioq_perror_ind[1:0]),
        .i_fc_fatal_error               (i_fc_fatal_error));
   
endmodule


