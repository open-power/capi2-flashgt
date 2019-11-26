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

module nvme_regs#
  (// afu/psl   interface parameters
   parameter tag_width       = 8,
   parameter datalen_width   = 25,
   parameter data_width      = 128,
   parameter data_bytes      = data_width/8,
   parameter bytec_width     = $clog2(data_bytes+1),
   parameter beatid_width    = datalen_width-$clog2(data_bytes),    
   parameter lunid_width     = 64, 
   parameter cmd_width       = 4, 
   parameter fcstat_width    = 8, 
   parameter fcxstat_width   = 8, 
   parameter rsp_info_width  = 160,
   parameter tag_par_width   = (tag_width + 7)/8, 
   parameter lunid_par_width = (lunid_width + 7)/8, 
   parameter data_par_width  = (data_width + 7) / 8,
   parameter status_width    = 8, // event status
  
   parameter [25:0] mmio_base  = 26'h2012000, // mmio address offset from AFU mmio base in bytes
   parameter [25:0] mmio_base2 = 26'h2060000, // debug address range - read only, no indirection or side effects please
   parameter mmio_awidth  = 12,  // address width of fc mmio address space (byte address)
   parameter mmio_awidth2 = 17,  // address width fc debug address space (byte address)

   parameter port_id = 0
   
    )
   (
   
    input                             reset,
    input                             clk,

    output reg                        led_red,
    output reg                        led_blue,
    output reg                        led_green,
    
    //-------------------------------------------------------
    // PSL mmio interface
    //-------------------------------------------------------   
    input                             ha_mmval_in,
    input                             ha_mmcfg_in,
    input                             ha_mmrnw_in,
    input                             ha_mmdw_in,
    input                      [23:0] ha_mmad_in,
    input                      [63:0] ha_mmdata_in,
    output reg                        ah_mmack_out,
    output reg                 [63:0] ah_mmdata_out,

    //-------------------------------------------------------
    // microcontroller register access
    //-------------------------------------------------------    
    input                      [31:0] ctl_regs_ioaddress,
    input                      [31:0] ctl_regs_iowrite_data,
    input                             ctl_regs_ioread_strobe, 
    input                             ctl_regs_iowrite_strobe,
    output reg                 [31:0] regs_ctl_ioread_data,
    output reg                        regs_ctl_ioack,
   
    //-------------------------------------------------------
    // FC module status events
    //-------------------------------------------------------
    output reg     [status_width-1:0] o_status_event_out,
    output reg                        o_port_ready_out,


    //-------------------------------------------------------
    // debug access to endpoint PCIe/NVMe
    //-------------------------------------------------------
    output reg                        regs_pcie_valid, // command valid
    input                             pcie_regs_ack, // command taken
    output reg                        regs_pcie_rnw, // read=1 write=0
    output reg                        regs_pcie_configop,// configop=1 (pcie) mmio=0 (nvme)
    output reg                  [3:0] regs_pcie_tag, // 4b tag for pcie op
    output reg                  [3:0] regs_pcie_be, // 4b byte enable
    output reg                 [31:0] regs_pcie_addr, // config reg # or mmio offset from NVME BAR
    output reg                 [31:0] regs_pcie_wrdata,

    input                      [31:0] pcie_regs_cpl_data, 
    input                             pcie_regs_cpl_valid,
    input                      [15:0] pcie_regs_cpl_status, // be[7:0], poison, status[2:0], errcode[3:0];
    
    //-------------------------------------------------------
    // debug 
    //-------------------------------------------------------
    output reg                        regs_cmd_trk_rd,
    output reg        [tag_width-1:0] regs_cmd_trk_addr,
    output reg                        regs_cmd_trk_addr_par,
    input                     [511:0] cmd_regs_trk_data,
    input                             cmd_regs_trk_ack,

    output reg                        regs_ioq_dbg_rd,
    output reg                  [9:0] regs_ioq_dbg_addr, // 8B offset
    input                      [63:0] ioq_regs_dbg_data,
    input                             ioq_regs_dbg_ack,

    output reg                        regs_adq_dbg_rd,
    output reg                  [9:0] regs_adq_dbg_addr, // 8B offset
    input                      [63:0] adq_regs_dbg_data,
    input                             adq_regs_dbg_ack,

    output reg                        regs_pcie_dbg_rd,
    output reg                 [15:0] regs_pcie_dbg_addr, // 8B offset
    input                      [63:0] pcie_regs_dbg_data,
    input                             pcie_regs_dbg_ack,
    
    output reg                        regs_sntl_dbg_rd,
    output reg                  [9:0] regs_sntl_dbg_addr, 
    input                      [63:0] sntl_regs_dbg_data,
    input                             sntl_regs_dbg_ack,

    // debug only configuration controls
    output reg                 [15:0] regs_cmd_debug,
    output reg                        regs_sntl_rsp_debug,
    output reg                  [7:0] regs_dma_errcpl,

    // event counters
    input                      [31:0] cmd_regs_dbgcount,
    input                             sntl_regs_rsp_cnt,
    
    //-------------------------------------------------------
    // error inject on I/O commands
    
    output reg                        regs_cmd_errinj_valid,
    output reg                  [3:0] regs_cmd_errinj_select,
    output reg                 [31:0] regs_cmd_errinj_lba,
    output reg                        regs_cmd_errinj_uselba,
    output reg                 [15:0] regs_cmd_errinj_status,
    input                             cmd_regs_errinj_ack,
    input                             cmd_regs_errinj_cmdrd,
    input                             cmd_regs_errinj_cmdwr,

    output reg                        regs_wdata_errinj_valid,
    input                             wdata_regs_errinj_ack,
    input                             wdata_regs_errinj_active,

    //-------------------------------------------------------
    // parity error inject 
    //-------------------------------------------------------
    output reg                        regs_adq_pe_errinj_valid, 
    output reg                        regs_ioq_pe_errinj_valid, 
    output reg                        regs_pcie_pe_errinj_valid , 
    output reg                        regs_sntl_pe_errinj_valid,
    output reg                 [15:0] regs_xxx_pe_errinj_decode, 
    output reg                        regs_wdata_pe_errinj_valid, 
    output reg                        regs_wdata_pe_errinj_1cycle_valid, 

    output reg                        regs_pcie_rxcq_errinj_valid,
    output reg                 [19:0] regs_pcie_rxcq_errinj_delay,
    input                             pcie_regs_rxcq_errinj_ack,
    input                             pcie_regs_rxcq_errinj_active,
    
    //-------------------------------------------------------
    // timers
    //-------------------------------------------------------
    output reg                 [35:0] regs_xx_timer1, // 1us units
    output reg                 [15:0] regs_xx_timer2, // 0x4000 * 1us
    output reg                 [15:0] regs_cmd_IOtimeout2, // timeout for I/O commands
    output reg                 [15:0] regs_ioq_icqto, // timeout when waiting for completion
    output reg                        regs_xx_tick1, // timer1 tick = 1us
    output reg                        regs_xx_tick2, // timer2 tick = 16.384ms
    output reg                        regs_cmd_disableto, 

    //-------------------------------------------------------
    // status
    //-------------------------------------------------------    
    input                             pcie_regs_sisl_backpressure,
    input                             pcie_regs_rxcq_backpressure,
    input                             sntl_regs_rdata_paused,
    input                             sntl_regs_cmd_idle,
    input                             cmd_regs_lunreset,
    
    //-------------------------------------------------------
    // misc config
    //-------------------------------------------------------
    output reg [datalen_width-1-12:0] regs_xx_maxxfer, // 4K blocks
    output reg          [tag_width:0] regs_cmd_maxiowr, // number of writes outstanding
    output reg          [tag_width:0] regs_cmd_maxiord, // number of reads outstanding

    output reg                 [11:0] regs_unmap_timer1,
    output reg                 [19:0] regs_unmap_timer2,
    output reg                  [7:0] regs_unmap_rangecount,
    output reg                  [7:0] regs_unmap_reqcount, 
    
    //-------------------------------------------------------
    // PCIe/NVMe controller status/control
    //-------------------------------------------------------
    input                             pcie_xx_link_up,
    input                             pcie_xx_init_done,
    input                      [31:0] pcie_regs_status,
    
    output                            regs_pcie_perst,
    output                      [7:0] regs_pcie_debug,
    output reg                 [31:0] regs_pcie_debug_trace,
   
    input                             ctl_xx_csts_rdy,
    input                             ctl_xx_ioq_enable,
    output reg                        regs_ctl_enable,
    output reg                        regs_ctl_ldrom,
    output reg                        regs_ctl_lunreset,
    
    output reg                        regs_ctl_shutdown,
    output reg                        regs_ctl_shutdown_abrupt,
    input                             ctl_xx_shutdown,
    input                             ctl_xx_shutdown_cmp, 
    input                             ioq_xx_isq_empty,
    input                             ioq_xx_icq_empty,

    input                      [31:0] ctl_regs_ustatus, 
    //-------------------------------------------------------
    // error reporting
    //-------------------------------------------------------    
    input                       [3:0] ioq_regs_faterr,
    input                       [3:0] ioq_regs_recerr,

    input                       [1:0] pcie_regs_dbg_error,
    input                       [3:0] pcie_regs_rxcq_error,
    input                       [3:0] wbuf_regs_error,

    input                             cdc_hold_cfg_err_fatal_out,
    input                       [3:0] admin_perror_ind,
    input                       [2:0] wbuf_perror_ind,
    input                             wdata_perror_ind,
    input                             rsp_perror_ind,
    input                       [5:0] cmd_perror_ind,
    input                       [7:0] dma_perror_ind,
    input                             ctlff_perror_ind,
    input                             cdc_ctlff_perror_ind,
    input                             rxcq_perror_ind,
    input                       [1:0] cdc_rxcq_perror_ind,
    input                             cdc_rxrc_perror_ind,
    input                       [2:0] txcc_perror_ind,
    input                       [1:0] cdc_txcc_perror_ind,
    input                             cdc_txrq_perror_ind,
    input                             adq_perror_ind,
    input                       [1:0] ioq_perror_ind,
    input                             i_fc_fatal_error,
    
    
    output reg                        regs_xx_disable_reset,
    output reg                        regs_xx_freeze,
    output reg                        o_port_fatal_error,
    output reg                        o_port_enable_pe,

    output reg                        regs_sntl_perf_reset

    );

`include "nvme_func.svh"
   



   // address map (byte addresses):
   // mmio_base = 0x2012000 for port 0, 0x2013000 for port 1
   // mmio_base2 = 0x2060000 for port 0, 0x2080000 for port 1

   // 0x2012000 - 0x2012280 = MTIP core regs
   // 0x2012300 - 0x2012FF8 = fc_module regs
   // 0x2060000 - 0x2060280 = MTIP core regs (read only debug copy)
   // 0x2060300 - 0x2060FF8 = fc_module regs (read only debug copy)
   // 0x2068000 - 0x206BFFF = exchange table dump
   // 0x2070000 - 0x207FFFF = trace buffer dump if enabled
  
   
   // addresses - byte offset from mmio_base
  
   // implement online/offline bits of these regs for compatibility with FC
   localparam FC_MTIP_CMDCONFIG = 20'h010;
   localparam FC_MTIP_STATUS    = 20'h018;

   // fc_module registers
   localparam FC_PNAME          = 20'h300;
   localparam FC_NNAME          = 20'h308;
   
   localparam FC_CONFIG         = 20'h320;
   localparam FC_CONFIG2        = 20'h328;   
   localparam FC_STATUS         = 20'h330;
   localparam FC_TIMER          = 20'h338;
   localparam FC_E_D_TOV        = 20'h340;
   localparam FC_STATUS2        = 20'h348;
   localparam FC_CONFIG3        = 20'h350;   
   localparam FC_CONFIG4        = 20'h358;   

   localparam FC_ERROR          = 20'h380;
   localparam FC_ERRCAP         = 20'h388;
   localparam FC_ERRMSK         = 20'h390;
   localparam FC_ERRSET         = 20'h398;
   localparam FC_ERRINJ         = 20'h3A0;
   localparam FC_ERRINJ_DATA    = 20'h3A8;
   localparam FC_PE_ERRINJ      = 20'h3B0;  // added parity error inject kch 
   localparam FC_PE_ERRINJ_DATA = 20'h3B8;  // added parity error inject kch 
   localparam FC_PE_STATUS      = 20'h3C0;  // added parity error inject kch
   localparam FC_PE_ERRMSK      = 20'h3C8;   
   localparam FC_PE_INFO        = 20'h3D0;   

   localparam FC_TGT_PNAME      = 20'h408;
   localparam FC_TGT_NNAME      = 20'h410;
   localparam FC_TGT_MAXXFER    = 20'h418;

   localparam FC_CNT_LINKERR    = 20'h530;
   localparam FC_CNT_CRCERR     = 20'h538;
   localparam FC_CNT_CRCERRRO   = 20'h540;
   localparam FC_CNT_OTHERERR   = 20'h548;
   localparam FC_CNT_TIMEOUT    = 20'h550;
   localparam FC_CRC_THRESH     = 20'h580;
   localparam FC_TIMER3         = 20'h588;
      
   localparam FC_DBGDISP        = 20'h600;
   localparam FC_DBGDATA        = 20'h608;

   localparam FC_CNT_CRCTOT     = 20'h610;
   localparam FC_CNT_AFURD      = 20'h618;
   localparam FC_CNT_AFUWR      = 20'h620;
   localparam FC_CNT_AFUABORT   = 20'h628;
   localparam FC_CNT_RSPOVER    = 20'h630;
   localparam FC_CNT_RXRSP      = 20'h660;
   localparam FC_CNT_AFUTASK    = 20'h668;
   localparam FC_CNT_AFUADMIN   = 20'h670;
   localparam FC_CNT_AFUUNSUP   = 20'h678;
   localparam FC_CNT_REQCNT     = 20'h680;
   
   localparam NVME_FW_STATUS    = 20'h700;
   localparam NVME_FW_ACTIVE    = 20'h708;
   localparam NVME_FW_NEXT      = 20'h710;
   
   localparam NVME_DBG_CONTROL  = 20'h720; 
   localparam NVME_DBG_ADDR     = 20'h728;
   localparam NVME_DBG_DATA     = 20'h730;
   localparam NVME_DBG_STATUS   = 20'h738;

   
   //-------------------------------------------------------
   // config registers
   // the following 3 registers have a power up value but are not affected by reset
   reg         [63:0] pname_q = 64'h0;
   reg         [63:0] nname_q = 64'h0;
   reg         [63:0] pname_d;
   reg         [63:0] nname_d;
   reg         [63:0] config3_q = {16'd16,16'd32,32'h08};  // 16 iosq, 32 entries each.  bit 3 = ignore ndob in write_same command
   reg         [63:0] config3_d = {16'd16,16'd32,32'h08};

   // 
   reg          [6:0] mtip_cmd_config_q, mtip_cmd_config_d; // mimic online/offline function of FC core
   reg          [5:0] mtip_status_q, mtip_status_d;	   // mimic online/offline status reporting
   
   reg         [63:0] config_q, config_d, config_init;
   reg         [63:0] config2_q, config2_d, config2_init;
   reg         [63:0] config4_q, config4_d, config4_init;
   reg         [63:0] status_q, status_d;
   reg         [63:0] status2_q, status2_d;
   reg         [35:0] timer1_q, timer1_d;
   reg         [35:0] timer2_q, timer2_d;
   reg         [19:0] timer3_q, timer3_d;
   reg         [31:0] timer4_q, timer4_d;
   reg         [19:0] timer3_max_q, timer3_max_d;
   reg                timer3_max_reset;
   reg         [31:0] e_d_tov_q,e_d_tov_d;

   reg         [63:0] tgt_pname_q, tgt_pname_d;
   reg         [63:0] tgt_nname_q, tgt_nname_d;
   reg         [31:0] tgt_maxxfer_q, tgt_maxxfer_d;   

   // debug counters
   reg         [15:0] mtip_sync_lost_q, mtip_sync_lost_d;
   reg         [15:0] mtip_online_lost_q, mtip_online_lost_d;

   reg         [31:0] cnt_crc_err_q, cnt_crc_err_d;
   reg         [31:0] cnt_other_err_q, cnt_other_err_d;
   reg         [31:0] cnt_timeout_q, cnt_timeout_d;
   reg         [31:0] crc_thresh_q, crc_thresh_d;
   reg         [31:0] cnt_crctot_q, cnt_crctot_d;

   
   reg         [31:0] cnt_afurd_q, cnt_afurd_d;
   reg         [31:0] cnt_afuwr_q, cnt_afuwr_d;
   reg         [31:0] cnt_afuabort_q, cnt_afuabort_d;
   reg         [31:0] cnt_afutask_q, cnt_afutask_d;
   reg         [31:0] cnt_afuadmin_q, cnt_afuadmin_d;
   reg         [31:0] cnt_afuunsup_q, cnt_afuunsup_d;
   reg         [31:0] cnt_rspover_q, cnt_rspover_d;
   reg         [31:0] cnt_rxrsp_q, cnt_rxrsp_d;
   reg  [tag_width:0] cnt_reqoutst_q, cnt_reqoutst_d;
   reg         [31:0] cnt_req_thresh1_q, cnt_req_thresh1_d;
   reg         [31:0] cnt_req_thresh2_q, cnt_req_thresh2_d;

   // RAS registers  
   reg         [31:0] errinj_q, errinj_d;
   reg         [47:0] errinj_data_q, errinj_data_d;
   reg         [63:0] error_q, error_d, error_set;
   reg         [63:0] errcap_q, errcap_d;
   reg         [63:0] errmsk_q, errmsk_d;
   reg         [31:0] pe_errinj_q, pe_errinj_d;   // added kch 
   reg                pe_errinj_s1_q, pe_errinj_s1_d;   // added kch 
   reg         [31:0] pe_errinj_data_q, pe_errinj_data_d;   // added kch 
   reg         [63:0] pe_status_data_q = 64'h0000000000000000;   // added kch 
   reg         [63:0] pe_status_data_d;
   reg         [63:0] pe_errmsk_q = 64'h0000000000000000;
   reg         [63:0] pe_errmsk_d;
   reg         [31:0] pe_info_q, pe_info_d;   // added kch 
   
   
   reg         [31:0] dbgdisp_q,dbgdisp_d;
   reg         [63:0] dbgdisp_data_q,dbgdisp_data_d;


   // NVME firmware revision information
   reg         [15:0] nvme_fw_status_q, nvme_fw_status_d;
   reg         [63:0] nvme_fw_active_q, nvme_fw_active_d;
   reg         [63:0] nvme_fw_next_q, nvme_fw_next_d;

   // PCIe/NVME register access
   reg         [31:0] nvme_dbg_control_q, nvme_dbg_control_d;   
   reg         [31:0] nvme_dbg_addr_q, nvme_dbg_addr_d;   
   reg         [31:0] nvme_dbg_data_q, nvme_dbg_data_d;   
   reg         [31:0] nvme_dbg_status_q, nvme_dbg_status_d;   

   
   //-------------------------------------------------------
   // interface registers
   //-------------------------------------------------------
   reg                ha_mmval_q;
   reg                ha_mmcfg_q;
   reg                ha_mmrnw_q;
   reg                ha_mmdw_q;
   reg [23:0]         ha_mmad_q;
   reg [63:0]         ha_mmdata_q;
   reg [63:0]         ah_mmdata_q, ah_mmdata_d;
   reg                ah_mmack_q, ah_mmack_d;
   reg                ha_mm_done;

   
   //-------------------------------------------------------
   // PSL mmio interface
   //-------------------------------------------------------

   // make a 1 cycle synchronous reset pulses
   // use this for mmio interface state machine
   // because afu can be out of reset while fc reset is asserted
   reg [1:0]            reset_int_q;   
   reg [2:0]            regs_pe_valid_q = 3'b0; // okay to sample parity errors  
   reg [2:0]            regs_pe_valid_d = 3'b0; 

   always @(posedge clk)
     begin
        reset_int_q <= {reset & ~reset_int_q[0], reset};
     end
   
   // register the interface with PSL
   // -------------------------------
   always @(posedge clk)
     begin
        // capture 1 cycle valid pulse 
        ha_mmval_q  <= (ha_mmval_q & ~ha_mm_done & ~reset_int_q[1]) |  ha_mmval_in ;
        ah_mmdata_q <= ah_mmdata_d;
        ah_mmack_q  <= ah_mmack_d;
     end
   
   always @(posedge clk)
     begin
        // hold mmio data/address until done
        if (ha_mmval_q == 1'b0)
          begin
             ha_mmcfg_q  <= ha_mmcfg_in;  // 0 for mmio
             ha_mmrnw_q  <= ha_mmrnw_in;
             ha_mmdw_q   <= ha_mmdw_in;
             ha_mmad_q   <= ha_mmad_in;        
             ha_mmdata_q <= ha_mmdata_in;
          end
     end    
   
   
   initial
     begin       
        ah_mmack_d          = 1'b0;  
        ah_mmdata_d         = zero[31:0];    
        o_port_ready_out    = 1'b0;
        o_status_event_out  = zero[status_width-1:0];
        ha_mm_done          = 1'b0;
     end

   //-------------------------------------------------------
   // microcontroller register access
   //-------------------------------------------------------    

   (* mark_debug = "false" *)
   reg [31:0] uc_addr_q, uc_addr_d;
   reg [31:0] uc_wrdata_q, uc_wrdata_d;
   (* mark_debug = "false" *)
   reg        uc_read_q, uc_read_d;
   (* mark_debug = "false" *)
   reg        uc_write_q, uc_write_d;
   reg        uc_ack;
   reg [31:0] uc_data;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             uc_addr_q   <= 32'h0;
             uc_wrdata_q <= 32'h0;
             uc_read_q   <= 1'b0;
             uc_write_q  <= 1'b0;
          end
        else
          begin   
             uc_addr_q   <= uc_addr_d;
             uc_wrdata_q <= uc_wrdata_d;
             uc_read_q   <= uc_read_d;
             uc_write_q  <= uc_write_d;
          end
     end

   // capture 1 cycle strobe and hold until ackd
   always @*
     begin
        uc_addr_d    = uc_addr_q;
        uc_wrdata_d  = uc_wrdata_q;
        uc_read_d    = uc_read_q & ~uc_ack;
        uc_write_d   = uc_write_q & ~uc_ack;

        if( ~uc_read_q & ~uc_write_q )
          begin
             uc_addr_d    = ctl_regs_ioaddress;
             uc_wrdata_d  = ctl_regs_iowrite_data;
             uc_read_d    = ctl_regs_ioread_strobe;
             uc_write_d   = ctl_regs_iowrite_strobe;
          end   
        regs_ctl_ioack        = uc_ack;
        regs_ctl_ioread_data  = uc_data;
     end

   
   //-------------------------------------------------------
   // register op state machine

   (* mark_debug = "false" *)
   reg   	[7:0] state_q, state_d;
   reg                rd_q,rd_d;
   (* mark_debug = "false" *)
   reg                wr_hi_q,wr_hi_d;
   (* mark_debug = "false" *)
   reg                wr_lo_q,wr_lo_d;
   (* mark_debug = "false" *)
   reg                wr_valid_q, wr_valid_d;
   reg                dw_q,dw_d;   
   reg         [25:0] addr_q,addr_d;  // byte address
   reg         [63:0] wrdata_q,wrdata_d;
   reg                addr_is_fc_q, addr_is_fc_d;
   reg                addr_is_fcdbg_q, addr_is_fcdbg_d;
   reg                addr_is_fcdbg2_q, addr_is_fcdbg2_d;
   
   // internal register decode
   reg         [63:0] rddata_q, rddata_d;   
   reg                dbg_req;
   reg                dbg_valid;
   reg                dbg_ack_q, dbg_ack_d;
   reg          [2:0] dbg_word;
   reg          [6:0] dbg_select;
   reg         [15:0] dbg_offset;
   reg         [63:0] dbg_data_q, dbg_data_d;
   reg                dbg_trk_rd_q, dbg_trk_rd_d;
   reg                dbg_ioq_rd_q, dbg_ioq_rd_d;
   reg                dbg_adq_rd_q, dbg_adq_rd_d;
   reg                dbg_pcie_rd_q, dbg_pcie_rd_d;
   reg                dbg_sntl_rd_q, dbg_sntl_rd_d;
   reg         [15:0] dbg_offset_q, dbg_offset_d;

   // state machine to update internal registers
   // or pass to mtip core
   // ------------------------------------------
   localparam SM_IDLE    = 8'h01;
   localparam SM_AFUDEC1 = 8'h02;
   localparam SM_AFUDEC2 = 8'h03;
   localparam SM_UCDEC1  = 8'h04;
   localparam SM_UCDEC2  = 8'h05;
   localparam SM_WAITRST = 8'h07;


   always @(posedge clk)
     begin 
        if( reset_int_q[1] == 1'b1 )
          begin
             state_q          <= SM_IDLE;
             addr_q           <= 26'h0;
             wrdata_q         <= 64'h0;
             rddata_q         <= 64'h0;
             rd_q             <= 1'b0;
             wr_hi_q          <= 1'b0;
             wr_lo_q          <= 1'b0;
             wr_valid_q       <= 1'b0;
             dw_q             <= 1'b0;
             addr_is_fc_q     <= 1'b0;
             addr_is_fcdbg_q  <= 1'b0;
             addr_is_fcdbg2_q <= 1'b0;
             dbg_ack_q        <= 1'b0;
             dbg_data_q       <= 32'b0;
             dbg_trk_rd_q     <= 1'b0;
             dbg_ioq_rd_q     <= 1'b0;
             dbg_adq_rd_q     <= 1'b0;
             dbg_pcie_rd_q    <= 1'b0;
             dbg_sntl_rd_q    <= 1'b0;
             dbg_offset_q     <= 16'h0;
          end
        else
          begin
             state_q          <= state_d;
             addr_q           <= addr_d;
             wrdata_q         <= wrdata_d;
             rddata_q         <= rddata_d;
             rd_q             <= rd_d;
             wr_hi_q          <= wr_hi_d;
             wr_lo_q          <= wr_lo_d;
             wr_valid_q       <= wr_valid_d;
             dw_q             <= dw_d;      
             addr_is_fc_q     <= addr_is_fc_d;
             addr_is_fcdbg_q  <= addr_is_fcdbg_d;
             addr_is_fcdbg2_q <= addr_is_fcdbg2_d;
             dbg_ack_q        <= dbg_ack_d;
             dbg_data_q       <= dbg_data_d;
             dbg_trk_rd_q     <= dbg_trk_rd_d;
             dbg_ioq_rd_q     <= dbg_ioq_rd_d;
             dbg_adq_rd_q     <= dbg_adq_rd_d;
             dbg_pcie_rd_q    <= dbg_pcie_rd_d;
             dbg_sntl_rd_q    <= dbg_sntl_rd_d;
             dbg_offset_q     <= dbg_offset_d;
          end
     end

   always @*
     begin
        state_d = state_q;
        addr_d = addr_q;
        wrdata_d = wrdata_q;        
        rd_d = rd_q;
        wr_hi_d = wr_hi_q;
        wr_lo_d = wr_lo_q;
        dw_d = dw_q;  
        ah_mmack_d = 1'b0;

        if( dw_q ) 
          ah_mmdata_d = rddata_q;
        else
          if( addr_q[2] )
            ah_mmdata_d = {rddata_q[63:32],rddata_q[63:32]};
          else
            ah_mmdata_d = {rddata_q[31:0],rddata_q[31:0]};
               
        ah_mmack_out = ah_mmack_q;
        ah_mmdata_out = ah_mmdata_q;
        ha_mm_done = 1'b0;

        addr_is_fc_d = addr_is_fc_q;
        addr_is_fcdbg_d = addr_is_fcdbg_q;
        addr_is_fcdbg2_d = addr_is_fcdbg2_q;
        wr_valid_d = 1'b0;
        dbg_req = 1'b0;

        uc_ack = 1'b0;
        uc_data = addr_q[2] ? rddata_q[63:32] : rddata_q[31:0];
        
        case(state_q)
          SM_IDLE:
            begin
               if (ha_mmval_q == 1'b1 & ~ah_mmack_q)                 
                 begin
                    // capture mmio op and data
                    rd_d      = ha_mmrnw_q;                    
                    wr_hi_d   = ~ha_mmrnw_q & (ha_mmdw_q ? ~ha_mmad_q[0] : ha_mmad_q[0]);
                    wr_lo_d   = ~ha_mmrnw_q & (ha_mmdw_q ? ~ha_mmad_q[0] : ~ha_mmad_q[0]);
                    dw_d      = ha_mmdw_q;                    
                    wrdata_d  = ha_mmdata_q;
                    
                    // ha_mmad_q is 23:0 - 32b word address.  addr_q is 25:0 (byte address).
                    // change to byte addresses for all address decoding
                    addr_d         = {ha_mmad_q,2'b00};                    
                    addr_is_fc_d   = ha_mmcfg_q == 1'b0 & (addr_d[25:mmio_awidth] == mmio_base[25:mmio_awidth]);
                    
                    // readonly address space for debug
                    // 0x2060xxx
                    addr_is_fcdbg_d =  ha_mmcfg_q == 1'b0 & (addr_d[25:mmio_awidth] == mmio_base2[25:mmio_awidth]);
                    // 0x2061000 - 0x207FFFF
                    addr_is_fcdbg2_d =  ~addr_is_fcdbg_d & ha_mmcfg_q == 1'b0 & (addr_d[25:mmio_awidth2] == mmio_base2[25:mmio_awidth2]);
                    
                    if( reset_int_q[0] )
                      state_d = SM_WAITRST;
                    else 
                      state_d = SM_AFUDEC1;
                 end
               else if( uc_read_q | uc_write_q )
                 begin
                    // capture mmio op and data
                    rd_d              = uc_read_q;                    
                    wr_hi_d           = uc_write_q & uc_addr_q[2];
                    wr_lo_d           = uc_write_q & ~uc_addr_q[2];
                    dw_d              = 1'b0;                    
                    wrdata_d          = {uc_wrdata_q, uc_wrdata_q};                    
                    addr_d            = uc_addr_q[25:0];             
                    addr_is_fc_d      = 1'b1;
                    addr_is_fcdbg_d   = 1'b0;
                    addr_is_fcdbg2_d  = 1'b0;
                    state_d           = SM_UCDEC1;                    
                 end
                       
            end // case: SM_IDLE

          // wait for reset to be deasserted before continuing
          SM_WAITRST:
            begin
               if( ~reset_int_q[0] )
                 state_d = SM_AFUDEC1;
            end

          SM_AFUDEC1:
            begin             
               wr_valid_d = addr_is_fc_q & (wr_hi_q|wr_lo_q); 
               state_d = SM_AFUDEC2;
            end
          
          // decode address from psl mmio interface
          SM_AFUDEC2:
            begin
               if( addr_is_fc_q | addr_is_fcdbg_q ) 
                 begin
                    // address maps to fc registers.  Give an ack.  Read data is captured above.                       
                    state_d     = SM_IDLE;

                    // if address doesn't match:
                    //  - drop writes
                    //  - return 1s for reads (default rddata if no address match)
                    ah_mmack_d  = 1'b1;                           
                    ha_mm_done  = 1'b1;                    
                 end
               else if( addr_is_fcdbg2_q )
                 begin
                    // map exchange table, trace arrays to mmio space
                    dbg_req  = 1'b1;
                    if( dbg_ack_q == 1'b1 )
                      begin
                         state_d      = SM_IDLE;
                         ah_mmdata_d  = dbg_data_q;
                         ah_mmack_d   = 1'b1;                         
                         ha_mm_done   = 1'b1;
                      end               
                 end
               else
                 begin
                    // not my address.  don't ack.  Wait for next mmio valid.
                    state_d     = SM_IDLE;
                    ha_mm_done  = 1'b1;
                 end
            end


          SM_UCDEC1:
            begin             
               wr_valid_d = addr_is_fc_q & (wr_hi_q|wr_lo_q); 
               state_d = SM_UCDEC2;
            end
          
          // decode address from microcontroller
          SM_UCDEC2:
            begin
               state_d = SM_IDLE;
               uc_ack  = 1'b1;
            end 
          
         
          default:
            begin
               state_d = SM_IDLE;                
            end         
        endcase // case (state_q)
       

        if (state_d == SM_IDLE)
          begin
             rd_d     = 1'b0;
             wr_hi_d  = 1'b0;                          
             wr_lo_d  = 1'b0;                                       
          end
     end

        
   // internal config registers + other related regs
   // ------------------------

   // other regs
   // async interrupt generation
   reg              [1:0] mtip_sync_q, mtip_sync_d;   
   reg              [7:0] mtip_online_q, mtip_online_d;
   reg                    mtip_online2offline_q, mtip_online2offline_d;
   reg                    mtip_offline2online_q, mtip_offline2online_d;
   reg                    port_error_q, port_error_d;
   reg              [1:0] crc_threshold_q, crc_threshold_d;
   reg              [1:0] event_other_q, event_other_d;
   reg              [1:0] event_logo_q, event_logo_d;
   reg              [1:0] event_logiretry_q, event_logiretry_d;
   reg              [1:0] event_logifail_q, event_logifail_d;
   reg              [1:0] event_ioqenable_q, event_ioqenable_d;   
   reg [status_width-1:0] event_q, event_d;

   // RAS
   reg                    errcap_v_q, errcap_v_d;
   reg                    errinj_period_done_q,errinj_period_done_d;
   reg             [15:0] errinj_count_q, errinj_count_d;
   reg                    errinj_event_int;

   
   reg                    freeze_q=1'b0;
   reg                    freeze_d=1'b0;

   always @(posedge clk or posedge reset)
     begin 
        if( reset == 1'b1 )
          begin
             config_q              <= config_init;             
             config2_q             <= config2_init;
             config4_q             <= config4_init;
             status_q              <= 64'h0; 
             status2_q             <= 64'h0; 
             e_d_tov_q             <= 64'd20000000>>14;  // 20 seconds - units of e_d_tov == usec/2^14
             tgt_pname_q           <= 64'h0;             
             tgt_nname_q           <= 64'h0;
             tgt_maxxfer_q         <= 32'h1000;  // 4096x4096KB=16M  // should set this with microcode if limited by NVMe capabilities
             mtip_cmd_config_q     <= 7'b0100000;  // reset to "online"
             mtip_status_q         <= 6'd0;
             mtip_sync_lost_q      <= 16'h0;
             mtip_online_lost_q    <= 16'h0;
             mtip_online_q         <= 8'h00;
             mtip_offline2online_q <= 1'b0;
             mtip_online2offline_q <= 1'b0;
             mtip_sync_q           <= 2'b00;
             
             cnt_crc_err_q         <= 32'h0;
             cnt_other_err_q       <= 32'h0;
             crc_thresh_q          <= 32'h0;
             cnt_timeout_q         <= 32'h0;
             cnt_crctot_q          <= 32'h0;
             cnt_afurd_q           <= 32'h0;
             cnt_afuwr_q           <= 32'h0;
             cnt_afuabort_q        <= 32'h0;
             cnt_rspover_q         <= 32'h0;
             cnt_afutask_q         <= 32'h0;
             cnt_afuadmin_q        <= 32'h0;
             cnt_afuunsup_q        <= 32'h0;
             cnt_rxrsp_q           <= 32'h0;
             cnt_reqoutst_q        <= zero[tag_width:0];
             cnt_req_thresh1_q     <= 32'h0;
             cnt_req_thresh2_q     <= 32'h0;

             error_q               <= 64'h0;         
             errcap_q              <= 64'h0;    
             errcap_v_q            <= 1'b0;
             port_error_q          <= 1'b0;
             errmsk_q              <= 64'h0;             
             errinj_q              <= 32'h0;
             pe_errinj_q           <= 32'h0;  // added kch 
             pe_errinj_s1_q        <= 1'h0;  // added kch 
             pe_errinj_data_q      <= 32'h0;  // added kch
             pe_info_q             <= 32'h0;
             errinj_data_q         <= 48'h0;
	     errinj_count_q        <= 16'h0;	     
             errinj_period_done_q  <= 1'b0;
             dbgdisp_q             <= 32'h0;
             dbgdisp_data_q        <= 64'h0;
             event_q               <= zero[status_width-1:0];
             crc_threshold_q       <= 2'b00;
             event_other_q         <= 2'b00;
             event_logo_q          <= 2'b00;
             event_logifail_q      <= 2'b00;
             event_logiretry_q     <= 2'b00;
             event_ioqenable_q     <= 2'b00;

             nvme_fw_status_q      <= zero[15:0];
             nvme_fw_active_q      <= zero[63:0];
             nvme_fw_next_q        <= zero[63:0];
             nvme_dbg_control_q    <= zero[31:0];   
             nvme_dbg_addr_q       <= zero[31:0];   
             nvme_dbg_data_q       <= zero[31:0];   
             nvme_dbg_status_q     <= zero[31:0];
          end
        else
          begin
             config_q              <= config_d;
             config2_q             <= config2_d;
             config4_q             <= config4_d;
             status_q              <= status_d;
             status2_q             <= status2_d;
             e_d_tov_q             <= e_d_tov_d;             
             tgt_pname_q           <= tgt_pname_d;             
             tgt_nname_q           <= tgt_nname_d;
             tgt_maxxfer_q         <= tgt_maxxfer_d;

             mtip_cmd_config_q     <= mtip_cmd_config_d;
             mtip_status_q         <= mtip_status_d;
             mtip_sync_lost_q      <= mtip_sync_lost_d;
             mtip_online_lost_q    <= mtip_online_lost_d;
             mtip_online_q         <= mtip_online_d;
             mtip_offline2online_q <= mtip_offline2online_d;
             mtip_online2offline_q <= mtip_online2offline_d;
             mtip_sync_q           <= mtip_sync_d;
             
             cnt_crc_err_q         <= cnt_crc_err_d;
             cnt_other_err_q       <= cnt_other_err_d;
             crc_thresh_q          <= crc_thresh_d;
             cnt_timeout_q         <= cnt_timeout_d;
             cnt_crctot_q          <= cnt_crctot_d;
             cnt_afurd_q           <= cnt_afurd_d;
             cnt_afuwr_q           <= cnt_afuwr_d;
             cnt_afuabort_q        <= cnt_afuabort_d;
             cnt_rspover_q         <= cnt_rspover_d;
             cnt_afutask_q         <= cnt_afutask_d;
             cnt_afuadmin_q        <= cnt_afuadmin_d;
             cnt_afuunsup_q        <= cnt_afuunsup_d;
             cnt_rxrsp_q           <= cnt_rxrsp_d;
             cnt_reqoutst_q        <= cnt_reqoutst_d;
             cnt_req_thresh1_q     <= cnt_req_thresh1_d;
             cnt_req_thresh2_q     <= cnt_req_thresh2_d;
            
             error_q               <= error_d;                        
             errcap_q              <= errcap_d;
             errcap_v_q            <= errcap_v_d; 
             port_error_q          <= port_error_d;
             errmsk_q              <= errmsk_d;                        
             errinj_q              <= errinj_d;
             pe_errinj_q           <= pe_errinj_d;   // added kch 
             pe_errinj_s1_q        <= pe_errinj_s1_d;   // added kch 
             errinj_data_q         <= errinj_data_d;
             pe_errinj_data_q      <= pe_errinj_data_d;   // added kch
             pe_info_q             <= pe_info_d;
	     errinj_count_q        <= errinj_count_d;	     
             errinj_period_done_q  <= errinj_period_done_d;
             dbgdisp_q             <= dbgdisp_d;
             dbgdisp_data_q        <= dbgdisp_data_d;
             event_q               <= event_d;
             crc_threshold_q       <= crc_threshold_d;
             event_other_q         <= event_other_d;
             event_logo_q          <= event_logo_d;
             event_logifail_q      <= event_logifail_d;
             event_logiretry_q     <= event_logiretry_d;
             event_ioqenable_q     <= event_ioqenable_d;

             nvme_fw_status_q      <= nvme_fw_status_d;
             nvme_fw_active_q      <= nvme_fw_active_d;   
             nvme_fw_next_q        <= nvme_fw_next_d;   
             nvme_dbg_control_q    <= nvme_dbg_control_d;   
             nvme_dbg_addr_q       <= nvme_dbg_addr_d;   
             nvme_dbg_data_q       <= nvme_dbg_data_d;   
             nvme_dbg_status_q     <= nvme_dbg_status_d;   


             end // else: !if( reset == 1'b1 )
     end // always @ (posedge clk or posedge reset)

   // these do not get reset so they can be loaded with unique values
   // after por and not after every reset
   always @(posedge clk)
     begin
        pname_q <= pname_d;
        nname_q <= nname_d;
        config3_q <= config3_d;
        freeze_q  <= freeze_d;
        regs_pe_valid_q <= regs_pe_valid_d;
 //       pe_enable_q <= {~pe_  fixit
        pe_status_data_q <= pe_status_data_d;  
        pe_errmsk_q      <= pe_errmsk_d;
     end


   // set inputs to internal config registers
   // address decode - double word aligned, little endian 32b access
   reg errinj_wr;
   reg freeze_on_error;
   reg      [63:0]  nvme_pe_error;
   reg              check_pe;
   reg              nvme_pe_error_set;
   always @*
     begin        
        
        pname_d             = pname_q;
        nname_d             = nname_q;        
        config_d            = config_q;
        config2_d           = config2_q;
        config3_d           = config3_q;
        config4_d           = config4_q;
        regs_pe_valid_d    = regs_pe_valid_q;
        pe_status_data_d    = pe_status_data_q;
        status_d            = status_q;
        status2_d           = status2_q;
        e_d_tov_d           = e_d_tov_q;
        config_init         = 64'h0;
        config2_init        = 64'h0;
        config4_init        = 64'h0;

        tgt_pname_d         = tgt_pname_q;             
        tgt_nname_d         = tgt_nname_q;
        tgt_maxxfer_d       = tgt_maxxfer_q;

        dbgdisp_d           = dbgdisp_q;
        dbgdisp_data_d      = dbgdisp_data_q;

        // mimic mtip online/offline function
        mtip_cmd_config_d   = mtip_cmd_config_q;
        regs_ctl_enable     = mtip_cmd_config_q[5] & ~mtip_cmd_config_q[6];  // online & not offline
        
        mtip_status_d[5]    = ctl_xx_csts_rdy; // online
        mtip_status_d[4]    = ~ctl_xx_csts_rdy; // offline
        mtip_status_d[3:0]  = 4'h0;
        
        // debug counts

        // count number of times link goes from online to offline
        // only count if link stays online for at least 128 cycles
        // mtip_online2offline and mtip_offline2online also used to generate interrupts
        // don't send interrupt or count if a lun reset is in progress
        mtip_online_d[7:0]  = (cmd_regs_lunreset) ? mtip_online_q :
                              (ctl_xx_csts_rdy & pcie_xx_init_done) ? 
                             ((mtip_online_q[7]) ? mtip_online_q : mtip_online_q+8'h1) :
                             8'h00;
        mtip_online2offline_d = mtip_online_q[7] & ~mtip_online_d[7];
        mtip_offline2online_d = ~mtip_online_q[7] & mtip_online_d[7];
        mtip_online_lost_d = (mtip_online2offline_q) ? mtip_online_lost_q + 16'h01 : mtip_online_lost_q;

        mtip_sync_d[1:0] = {mtip_sync_q[0], pcie_xx_link_up};          // edge detect
        mtip_sync_lost_d = (mtip_sync_q[1] & ~mtip_sync_q[0]) ? mtip_sync_lost_q + 16'h01 : mtip_sync_lost_q;
      
        cnt_crc_err_d = cnt_crc_err_q;

        // clear crc error count on read.  write data overrides this below.
        if (addr_is_fc_q & addr_q[mmio_awidth-1:3]==FC_CNT_CRCERR[mmio_awidth-1:3] & ah_mmack_d)
          begin
             cnt_crc_err_d = {zero[31:1],1'b0};
          end

        
        cnt_afurd_d         = cnt_afurd_q     + (cmd_regs_dbgcount[0] ? 32'h1 : 32'h0);
        cnt_afuwr_d         = cnt_afuwr_q     + (cmd_regs_dbgcount[1] ? 32'h1 : 32'h0);
        cnt_afutask_d       = cnt_afutask_q   + (cmd_regs_dbgcount[2] ? 32'h1 : 32'h0);
        cnt_afuadmin_d      = cnt_afuadmin_q  + (cmd_regs_dbgcount[3] ? 32'h1 : 32'h0);
        cnt_afuunsup_d      = cnt_afuunsup_q  + (cmd_regs_dbgcount[4] ? 32'h1 : 32'h0);        
        cnt_rxrsp_d         = cnt_rxrsp_q     + (cmd_regs_dbgcount[5] ? 32'h1 : 32'h0);
        cnt_rspover_d       = cnt_rspover_q   + (cmd_regs_dbgcount[6] ? 32'h1 : 32'h0);
        cnt_timeout_d       = cnt_timeout_q   + (cmd_regs_dbgcount[7] ? 32'h1 : 32'h0);
        cnt_afuabort_d      = cnt_afuabort_q  + (cmd_regs_dbgcount[8] ? 32'h1 : 32'h0);
        cnt_other_err_d     = cnt_other_err_q + (cmd_regs_dbgcount[9] ? 32'h1 : 32'h0);
        cnt_crctot_d        = cnt_crctot_q;

        // increment request outstanding counter when cmd module arbitration selects it
        // decrement when a response is sent to sislite
        cnt_reqoutst_d      = cnt_reqoutst_q  + (cmd_regs_dbgcount[10] ? one[tag_width:0] : zero[tag_width:0]);
        cnt_reqoutst_d      = cnt_reqoutst_d  - (sntl_regs_rsp_cnt ? one[tag_width:0] : zero[tag_width:0]);

        // count cycles that that the number of requests outstanding is above a threshold
        cnt_req_thresh1_d   = cnt_req_thresh1_q + (cnt_reqoutst_q > config2_q[31:24] ? 32'h1 : 32'h0);
        cnt_req_thresh2_d   = cnt_req_thresh2_q + (cnt_reqoutst_q > config2_q[39:32] ? 32'h1 : 32'h0);
     
              
        // threshold for reporting crc errors
        // generate 1 cycle pulse when threshold is exceeded
        crc_thresh_d        = crc_thresh_q;
        crc_threshold_d[0]  = cnt_crc_err_q > crc_thresh_q;
        crc_threshold_d[1]  = crc_threshold_q[0];

        // error capture registers
        // map NVMe errors so that only severe errors cause a reset     
        error_set[15:0]     = zero[15:0]; // login errors - set by microcode
        error_set[20:16]    = ioq_regs_recerr;       
        error_set[21]       = 1'b0;
        error_set[22]       = 1'b0;
        error_set[23]       = 1'b0;     
        error_set[27:24]    = ioq_regs_faterr;      
        error_set[29:28]    = pcie_regs_dbg_error;
        error_set[30]       = 1'b0;
        error_set[31]       = 1'b0;
        error_set[35:32]    = wbuf_regs_error;
        error_set[39:36]    = pcie_regs_rxcq_error;
        error_set[47:37]    = zero[63:40];
        error_set[48]       = nvme_pe_error_set;
        error_set[63:49]    = zero[63:40];

        // set error bits with write to FC_ERRSET
        if( wr_valid_q & wr_lo_q & addr_q[mmio_awidth-1:3]==FC_ERRSET[mmio_awidth-1:3] )
          error_set[31:0] = error_set[31:0] | wrdata_q[31:0];
        if( wr_valid_q & wr_hi_q & addr_q[mmio_awidth-1:3]==FC_ERRSET[mmio_awidth-1:3] )
          error_set[63:32]  = error_set[63:32] | wrdata_q[63:32];
        
        error_d             = error_q | error_set; 

        // enable parity error capture after reset has been asserted for a couple cycles
        regs_pe_valid_d     = {reset, regs_pe_valid_d[2] & reset,(regs_pe_valid_q[1]|regs_pe_valid_q[0])} ;
        check_pe            = regs_pe_valid_q[0] & ~reset; 
        o_port_enable_pe    = regs_pe_valid_q[0];

        // capture first unmasked error
        errcap_d            = (errcap_q == 64'h0) ? (error_q & ~errmsk_q) : errcap_q;
        errcap_v_d          = |errcap_q;
        port_error_d        = |errcap_q[47:16];  // bring down the port until error is reset
	errmsk_d            = errmsk_q;        

        // edge detect on error events for interrupt generation
        event_logifail_d    = { event_logifail_q[0], (|errcap_q[7:0])}; // errors 7:0 - no link reset
        event_logiretry_d   = { event_logiretry_q[0], (|errcap_q[15:8])}; // errors 15:8 - link reset by driver to recover        
        event_logo_d        = { event_logo_q[0], (|errcap_q[23:16]) };  // errors 23:16 - non-login, no link reset
        event_other_d       = { event_other_q[0],(|errcap_q[47:24]) };  // errors 31:24 - non-login, link reset by driver to recover
        event_ioqenable_d   = (cmd_regs_lunreset) ? event_ioqenable_q : // ignore changes during lunreset
                              { event_ioqenable_q[0],ctl_xx_ioq_enable};
        // fatal errors
        o_port_fatal_error  = (|errcap_q[63:48]);   
        
        errinj_d            = errinj_q;
        errinj_data_d       = errinj_data_q;

        pe_errinj_d         = pe_errinj_q;   // added kch 
        pe_errinj_s1_d      = pe_errinj_s1_q;   // added kch 
        pe_errinj_data_d    = pe_errinj_data_q;   // added kch 

        nvme_pe_error       = {cdc_hold_cfg_err_fatal_out,  // 38
                               admin_perror_ind,     // 37:34
                               wbuf_perror_ind,      // 33:31
                               wdata_perror_ind,     // 30
                               rsp_perror_ind,       // 29
                               cmd_perror_ind,       // 28:23
                               dma_perror_ind,       // 22:15
                               ctlff_perror_ind,     // 14
                               cdc_ctlff_perror_ind, // 13
                               rxcq_perror_ind,      // 12
                               cdc_rxcq_perror_ind,  // 11:10
                               cdc_rxrc_perror_ind,  // 9
                               txcc_perror_ind,      // 8:6
                               cdc_txcc_perror_ind,  // 4:5
                               cdc_txrq_perror_ind,  // 3
                               adq_perror_ind,       // 2
                               ioq_perror_ind};      // 1:0
        pe_status_data_d      = pe_status_data_q | ({64{check_pe}} & nvme_pe_error);
        pe_errmsk_d           = pe_errmsk_q;
        pe_info_d             = pe_info_q;
        nvme_pe_error_set     = (pe_status_data_q & ~pe_errmsk_q) != 64'h0;

        errinj_wr             = 1'b0;

        nvme_fw_status_d      = nvme_fw_status_q;
        nvme_fw_active_d      = nvme_fw_active_q;   
        nvme_fw_next_d        = nvme_fw_next_q;   
        nvme_dbg_control_d    = nvme_dbg_control_q;   
        nvme_dbg_addr_d       = nvme_dbg_addr_q;   
        nvme_dbg_data_d       = nvme_dbg_data_q;   
        nvme_dbg_status_d     = nvme_dbg_status_q;   

        timer3_max_reset      = 1'b0;   
        
        // address decode
        case(addr_q[mmio_awidth-1:3])
          FC_MTIP_CMDCONFIG[mmio_awidth-1:3]:
            begin
               rddata_d = {zero[63:7],mtip_cmd_config_q};
               if (wr_valid_q & wr_lo_q & ~freeze_q)
                 mtip_cmd_config_d[6:0] = wrdata_q[6:0];
            end
          FC_MTIP_STATUS[mmio_awidth-1:3]:
            begin
               rddata_d = {zero[63:6],mtip_status_q};            
            end
          
          FC_PNAME[mmio_awidth-1:3]:
            begin
               rddata_d = pname_q;
               if (wr_valid_q & wr_hi_q)
                 pname_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 pname_d[31:0] = wrdata_q[31:0];
            end
          
          FC_NNAME[mmio_awidth-1:3]:
            begin
               rddata_d = nname_q;
               if (wr_valid_q & wr_hi_q)
                 nname_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 nname_d[31:0] = wrdata_q[31:0];
            end          
          

          FC_CONFIG[mmio_awidth-1:3]:
            begin
               rddata_d = config_q;               
               if (wr_valid_q & wr_hi_q)
                 config_d[63:32] = wrdata_q[63:32];               
               if (wr_valid_q & wr_lo_q)
                 config_d[31:0] = wrdata_q[31:0];               
            end
          
          FC_CONFIG2[mmio_awidth-1:3]:
            begin
               rddata_d = config2_q;
              
               if (wr_valid_q & wr_hi_q)
                 config2_d[63:32] = wrdata_q[63:32];               
               if (wr_valid_q & wr_lo_q)
                 config2_d[31:0] = wrdata_q[31:0];               
            end
          
          FC_CONFIG3[mmio_awidth-1:3]:
            begin
               rddata_d = config3_q;
              
               if (wr_valid_q & wr_hi_q)
                 config3_d[63:32] = wrdata_q[63:32];               
               if (wr_valid_q & wr_lo_q)
                 config3_d[31:0] = wrdata_q[31:0];               
            end
          
          FC_CONFIG4[mmio_awidth-1:3]:
            begin
               rddata_d = config4_q;
              
               if (wr_valid_q & wr_hi_q)
                 config4_d[63:32] = wrdata_q[63:32];               
               if (wr_valid_q & wr_lo_q)
                 config4_d[31:0] = wrdata_q[31:0];               
            end
          
          FC_STATUS[mmio_awidth-1:3]:
            begin
               rddata_d = status_q; 
               if (wr_valid_q & wr_hi_q)
                 status_d[63:32] = wrdata_q[63:32]; 
               if (wr_valid_q & wr_lo_q)
                 status_d[31:0] = wrdata_q[31:0]; 
            end
          
          FC_STATUS2[mmio_awidth-1:3]:
            begin
               rddata_d = status2_q; 
               if (wr_valid_q & wr_hi_q)
                 status2_d[63:32] = wrdata_q[63:32]; 
               if (wr_valid_q & wr_lo_q)
                 status2_d[31:0] = wrdata_q[31:0]; 
            end          
          
          FC_TIMER[mmio_awidth-1:3]:
            begin
               rddata_d = {timer2_q[35:14],zero[64-22-1:36],timer1_q[35:0]}; 
            end
          
          FC_TIMER3[mmio_awidth-1:3]:
            begin
               rddata_d = {timer4_q,12'h0,timer3_max_q};

               // optionally clear timer3_max on read
               if (config2_q[8] & addr_is_fc_q & ah_mmack_d)
                 begin
                    timer3_max_reset = 1'b1;
                 end

               // clear timer3 on write
               if (wr_valid_q & wr_lo_q)
                 begin
                    timer3_max_reset = 1'b1;
                 end
            end
          
          FC_E_D_TOV[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0,e_d_tov_q}; 
               if (wr_valid_q & wr_lo_q)
                 e_d_tov_d = wrdata_q[31:0];  
            end


          FC_TGT_PNAME[mmio_awidth-1:3]:
            begin
               rddata_d = tgt_pname_q;
               if (wr_valid_q & wr_hi_q)
                 tgt_pname_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 tgt_pname_d[31:0] = wrdata_q[31:0];
            end


          FC_TGT_NNAME[mmio_awidth-1:3]:
            begin
               rddata_d = tgt_nname_q;
               if (wr_valid_q & wr_hi_q)
                 tgt_nname_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 tgt_nname_d[31:0] = wrdata_q[31:0];
            end
          
          FC_TGT_MAXXFER[mmio_awidth-1:3]:
            begin
               rddata_d = {zero[31:0],tgt_maxxfer_q};
               if (wr_valid_q & wr_lo_q)
                 tgt_maxxfer_d[31:0] = wrdata_q[31:0];
            end
          
          FC_ERRINJ[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, errinj_q};
               if (wr_valid_q & wr_lo_q)
                 begin
                    errinj_wr = 1'b1;
                    errinj_d = wrdata_q[31:0];
                 end
            end
          FC_ERRINJ_DATA[mmio_awidth-1:3]:
            begin
               rddata_d = {zero[63:48], errinj_data_q};
               if (wr_valid_q & wr_hi_q)
                 errinj_data_d[47:32] = wrdata_q[47:32];
               if (wr_valid_q & wr_lo_q)
                 errinj_data_d[31:0] = wrdata_q[31:0];
                 errinj_d[31] = pe_errinj_q[0];
            end
          FC_PE_ERRINJ[mmio_awidth-1:3]:   // added kch 
            begin
               rddata_d = {32'h0, pe_errinj_q};
               if (wr_valid_q & wr_lo_q)
                 begin
                   pe_errinj_d[31:0] = wrdata_q[31:0];
                   pe_info_d[0] = wrdata_q[0] & ~(| pe_errinj_data_q);
                   pe_info_d[1] = wrdata_q[0] & pe_errinj_q[0];
                 end
            end
          FC_PE_ERRINJ_DATA[mmio_awidth-1:3]:   // added kch 
            begin
               rddata_d = {32'h0, pe_errinj_data_q};
               if (wr_valid_q & wr_lo_q)
                 begin
                   pe_errinj_data_d[31:0] = wrdata_q[31:0];
                   pe_info_d[2] = pe_errinj_q[0];
                 end
            end
          FC_PE_STATUS[mmio_awidth-1:3]:   // added kch 
            begin
               rddata_d = {pe_status_data_q};
               if (wr_valid_q & wr_hi_q)
                 pe_status_data_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 pe_status_data_d[31:0] = wrdata_q[31:0];
            end
          FC_PE_ERRMSK[mmio_awidth-1:3]:
            begin
               rddata_d = {pe_errmsk_q};
               if (wr_valid_q & wr_hi_q)
                 pe_errmsk_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 pe_errmsk_d[31:0] = wrdata_q[31:0];
            end
          FC_PE_INFO[mmio_awidth-1:3]:
            begin
               rddata_d = {pe_info_q};
               if (wr_valid_q & wr_lo_q)
                 pe_info_d[31:0] = wrdata_q[31:0];
            end


 
          FC_ERROR[mmio_awidth-1:3]:
            begin
               rddata_d = error_q;

               // writes to error reg are "write 1 to clear" W1C
               if (wr_valid_q & wr_hi_q & ~freeze_q)
                 error_d[63:32] = (error_d[63:32] & ~wrdata_q[63:32]);
               if (wr_valid_q & wr_lo_q & ~freeze_q)
                 error_d[31:0] = (error_d[31:0] & ~wrdata_q[31:0]);              
            end
          FC_ERRCAP[mmio_awidth-1:3]:
            begin
               rddata_d = errcap_q;
               if (wr_valid_q & wr_hi_q & ~freeze_q)
                 errcap_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q & ~freeze_q)
                 errcap_d[31:0] = wrdata_q[31:0];
            end
          
          FC_ERRMSK[mmio_awidth-1:3]:
            begin
               rddata_d = errmsk_q;
               if (wr_valid_q & wr_hi_q)
                 errmsk_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 errmsk_d[31:0] = wrdata_q[31:0];
            end

          FC_DBGDISP[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, dbgdisp_q};
               if (wr_valid_q & wr_lo_q)
                 dbgdisp_d = wrdata_q[31:0];
            end

          FC_DBGDATA[mmio_awidth-1:3]:
            begin
               rddata_d = {dbgdisp_data_q};
               if (wr_valid_q & wr_hi_q)
                 dbgdisp_data_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 dbgdisp_data_d[31:0] = wrdata_q[31:0];
            end
          
          FC_CNT_LINKERR[mmio_awidth-1:3]:
            begin
               rddata_d = { 16'h0, mtip_sync_lost_q, 16'h0, mtip_online_lost_q};
            end

          FC_CNT_CRCERR[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_crc_err_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_crc_err_d[31:0] = wrdata_q[31:0];
            end
          FC_CNT_CRCERRRO[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_crc_err_q};             
            end
          FC_CRC_THRESH[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, crc_thresh_q};
               if (wr_valid_q & wr_lo_q)
                 crc_thresh_d[31:0] = wrdata_q[31:0];
            end
          
          FC_CNT_OTHERERR[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_other_err_q};             
               if (wr_valid_q & wr_lo_q)
                 cnt_other_err_d = wrdata_q[31:0];
            end          

          FC_CNT_TIMEOUT[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_timeout_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_timeout_d[31:0] = wrdata_q[31:0];
            end
          
          FC_CNT_CRCTOT[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_crctot_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_crctot_d = wrdata_q[31:0];
            end
                    
          FC_CNT_AFURD[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_afurd_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_afurd_d = wrdata_q[31:0];
            end
          
          FC_CNT_AFUTASK[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_afutask_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_afutask_d = wrdata_q[31:0];
            end
          
          FC_CNT_AFUADMIN[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_afuadmin_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_afuadmin_d = wrdata_q[31:0];
            end
          FC_CNT_AFUUNSUP[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_afuunsup_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_afuunsup_d = wrdata_q[31:0];
            end
          
          FC_CNT_AFUWR[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_afuwr_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_afuwr_d = wrdata_q[31:0];
            end
          
          FC_CNT_AFUABORT[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_afuabort_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_afuabort_d = wrdata_q[31:0];
            end
          
          FC_CNT_RSPOVER[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_rspover_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_rspover_d = wrdata_q[31:0];
            end
                    
          FC_CNT_RXRSP[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, cnt_rxrsp_q};
               if (wr_valid_q & wr_lo_q)
                 cnt_rxrsp_d = wrdata_q[31:0];
            end

          FC_CNT_REQCNT[mmio_awidth-1:3]:
            begin
               rddata_d = {cnt_req_thresh2_q, cnt_req_thresh1_q};
            end


          NVME_FW_STATUS[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, 16'h0, nvme_fw_status_q};
               if (wr_valid_q & wr_lo_q)
                 nvme_fw_status_d = wrdata_q[15:0];
            end
          
          NVME_FW_ACTIVE[mmio_awidth-1:3]:
            begin
               rddata_d = nvme_fw_active_q;  
               if (wr_valid_q & wr_hi_q)
                 nvme_fw_active_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 nvme_fw_active_d[31:0] = wrdata_q[31:0];           
            end
          NVME_FW_NEXT[mmio_awidth-1:3]:
            begin
               rddata_d = nvme_fw_next_q;
               if (wr_valid_q & wr_hi_q)
                 nvme_fw_next_d[63:32] = wrdata_q[63:32];
               if (wr_valid_q & wr_lo_q)
                 nvme_fw_next_d[31:0] = wrdata_q[31:0];           
            end

          NVME_DBG_CONTROL[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, nvme_dbg_control_q};
               if (wr_valid_q & wr_lo_q)
                 nvme_dbg_control_d[31:0] = wrdata_q[31:0];
            end
          NVME_DBG_ADDR[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, nvme_dbg_addr_q};
               if (wr_valid_q & wr_lo_q)
                 nvme_dbg_addr_d[31:0] = wrdata_q[31:0];
            end
          NVME_DBG_DATA[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, nvme_dbg_data_q};
               if (wr_valid_q & wr_lo_q)
                 nvme_dbg_data_d[31:0] = wrdata_q[31:0];
            end
          NVME_DBG_STATUS[mmio_awidth-1:3]:
            begin
               rddata_d = {32'h0, nvme_dbg_status_q};
               if (wr_valid_q & wr_lo_q)
                 nvme_dbg_status_d[31:0] = wrdata_q[31:0];
            end
                    
          default
            begin
               rddata_d = 64'hFFFF_FFFF_FFFF_FFFF;
            end
        endcase // case (addr_q[mmio_awidth-1:3])        

        // config reg initial values
        // -------------
        config_init[0]      = 1'b1; // enable login after link up.  0 = perst to NVMe link
        config_init[1]      = 1'b0; // N/A (Surelock FC = single login)
        config_init[2]      = 1'b0; // N/A (Surelock FC = send LOGO and log out) 
        config_init[3]      = 1'b0; // N/A (Surelock FC = send LOGO before login)
        
        config_init[4]      = 1'b0; // perst (was hard reset)
        config_init[5]      = 1'b0; // N/A (mask crc errors)
        config_init[6]      = 1'b0; // N/A (command/resp arb mode: 0 - host cmd hi priority 1 - round robin)
        config_init[7]      = 1'b0; // 1=disable I/O timeouts

        config_init[15:8]   = 8'h00; // N/A
        config_init[23:16]  = 8'h00; // perst debug controls
        config_init[26:24]  = 3'b000; // leds: blue/green/red
        config_init[34:27]  = 8'h00;  // N/A
              
`ifdef FC_FAST_TIMEOUT
        config_init[35]     = 1'b1;
`else
        config_init[35]     = 1'b0;  // timeout override:  0 = normal timeouts.  1 = short timeout     
`endif

        config_init[39:36]   = 3'h0; // N/A
        
        config2_init[4]      = 1'b0;  // shutdown
        config2_init[5]      = 1'b0;  // shutdown abrupt
        config2_init[8]      = 1'b0;  // clear timer3 max count on read
        config2_init[13:12]  = 2'b00; // timer3 input select        
        config2_init[31:24]  = 8'd0;  // perf count - cnt_req_thresh1
        config2_init[39:32]  = 8'd250; // perf count - cnt_req_thresh2
        config2_init[47:40]  = 8'hff; // max writes outstanding
        config2_init[55:48]  = 8'd169; // max reads outstanding - must correlate to fifo size in nvme_pcie_rxcq

        config4_init[11:0] = 12'd100; // regs_unmap_timer1 - delay in us before sending 1st unmap
        config4_init[31:12] = 20'd35000; // regs_unmap_timer2 - delay in us before sending next unmap
        config4_init[39:32] = 8'd255;  // max number of unmaps to combine
        config4_init[47:40] = 8'd250;  // override timer1/2 if this many unmap requests are queued

        // connect status reg inputs
        // ----------------
        status_d[0]                        = mtip_sync_q[1];
        status_d[1]                        = mtip_online_q[7];
        status_d[2]                        = ctl_xx_ioq_enable;  // ready for I/O
        status_d[3]                        = pcie_xx_init_done;  // PCIe init is done, cleared on link down
        status_d[4]                        = ctl_xx_shutdown;
        status_d[5]                        = ctl_xx_shutdown_cmp;
        status_d[6]                        = ioq_xx_isq_empty;
        status_d[7]                        = ioq_xx_icq_empty;
        status_d[8]                        = sntl_regs_cmd_idle;
        status_d[9]                        = cmd_regs_lunreset;
        status_d[tag_width+16:16]          = cnt_reqoutst_q;        
        status_d[31]                       = freeze_on_error & (status_q[31] | errcap_v_q);
        freeze_d                           = status_q[31];
        regs_xx_freeze                     = freeze_q;
        status_d[63:32]                    = ctl_regs_ustatus;

        status2_d[31:0]                    = pcie_regs_status;

        o_port_ready_out                   = (status_q[2]|status_q[9]) & status_q[3] & ~port_error_q;
        regs_ctl_lunreset                  = status_q[9];
        


        // RAS registers + outputs
        // ---------------

        // errinj:
        // [31]    - enable injection on next frame
        // [30]    - single injection completed
        //
        // [23:20] - select
        //            x0 - disabled
        //            x1 - override NVMe status on specific lba for Write
        //            x2 - override NVMe status on specific lba for Read
        //            x3 - override data on Write
        //            x4 - override data on Read
        //            x5 - override NVMe status for Admin command
        //            x6 - events
        //            x7 - set error status on NVMe PCIe DMA read response
        //            x8 - set error status on NVMe PCIe DMA write data
        //            x9 - set error on wdata response
        //            xA - set DMA lookup error on read
        //            xB - set DMA lookup error on write
        //            xC - inject a pause on the rxrq pcie interface
        //
        // [17:16] - mode
        //            0b00 - single inject after x delay cycles
        //            0b01 - single inject after x frames
        //            0b10 - periodic inject after every x cycles
        //            0b11 - periodic inject after every x frames
        //            
        // [15:0]  - frame/cycle interval for injection
        //

        // send error inject to rx & tx interfaces
        regs_cmd_errinj_valid              = (errinj_q[23:20] == 4'h1 || errinj_q[23:20] == 4'h2||errinj_q[23:20] == 4'hA || errinj_q[23:20] == 4'hB) && errinj_q[31];
        regs_cmd_errinj_select             = errinj_q[23:20];
        regs_cmd_errinj_uselba             = (errinj_q[23:20] == 4'h1 || errinj_q[23:20] == 4'h2);
        regs_cmd_errinj_lba                = errinj_data_q[31:0];
        regs_cmd_errinj_status             = errinj_data_q[47:32];
        
        errinj_event_int                   = errinj_q[23:20] == 4'h6 & errinj_q[31];
        regs_wdata_errinj_valid            = errinj_q[23:20] == 4'h9 && errinj_q[31]; 
        regs_pcie_rxcq_errinj_valid        = errinj_q[23:20] == 4'hC && errinj_q[31];
        regs_pcie_rxcq_errinj_delay        = errinj_data_q[19:0];

        // send parity error injection  
        // bits 15:8 function decode 
        // bits 7:0  individual decode 
        // function decode bits 15:8
        // 0x01 = regs  not yet implemented 
        // 0x02 = adq
        // 0x04 = ioq 
        // 0x08 = pcie
        // 0x10 = sntl
         
        regs_adq_pe_errinj_valid           = pe_errinj_data_q[17];       
        regs_ioq_pe_errinj_valid           = pe_errinj_data_q[18];       
        regs_pcie_pe_errinj_valid          = pe_errinj_data_q[19];       
        regs_sntl_pe_errinj_valid          = pe_errinj_data_q[20];
        regs_xxx_pe_errinj_decode          = pe_errinj_data_q[15:0]; 
        regs_wdata_pe_errinj_valid         = pe_errinj_q[0];   
        pe_errinj_s1_d                     = pe_errinj_q[0] ; 
        regs_wdata_pe_errinj_1cycle_valid  = pe_errinj_q[0] & ~ pe_errinj_s1_q;        
           
        // set enable periodically - count frames or cycles
	errinj_period_done_d               = errinj_period_done_q | (errinj_count_q[15:0] == errinj_q[15:0]);
        if (errinj_wr)
          begin
             errinj_period_done_d = 1'b0;
             errinj_count_d = 16'h0000;
          end
        else
          begin
             // clear enable when error happens
             if ( (errinj_q[23:20] == 4'h1 & cmd_regs_errinj_ack) | 
                  (errinj_q[23:20] == 4'h2 & cmd_regs_errinj_ack) |
                  (errinj_q[23:20] == 4'hA & cmd_regs_errinj_ack) |
                  (errinj_q[23:20] == 4'hB & cmd_regs_errinj_ack) |
                  (errinj_q[23:20] == 4'h3) |
                  (errinj_q[23:20] == 4'h4) |
                  (errinj_q[23:20] == 4'h6) |
                  (errinj_q[23:20] == 4'h9 & wdata_regs_errinj_ack) |
                  (errinj_q[23:20] == 4'hC & pcie_regs_rxcq_errinj_ack))
               begin
                  errinj_d[31] = 1'b0;
                  errinj_d[30] = 1'b1;
               end
             
             errinj_count_d = errinj_count_q;
             if ((errinj_q[23:20] != 4'h0) & 
                 ((errinj_q[16] == 1'b0) |  // cycles
                  (errinj_q[16] == 1'b1 &&   // frames
                   ((errinj_q[23:20] == 4'h1 && cmd_regs_errinj_cmdwr) | 
                    (errinj_q[23:20] == 4'h2 && cmd_regs_errinj_cmdrd) |
                    (errinj_q[23:20] == 4'hA && cmd_regs_errinj_cmdwr) |
                    (errinj_q[23:20] == 4'hB && cmd_regs_errinj_cmdrd) |
                    (errinj_q[23:20] == 4'h9 && wdata_regs_errinj_active ) | 
                    (errinj_q[23:20] == 4'hC && pcie_regs_rxcq_errinj_active)))))
               begin
                  if (errinj_period_done_q)
                    begin
                       errinj_period_done_d = 1'b0;
                       errinj_count_d = 16'h0000;
                       // enable error injection if periodic mode or single hasn't occurred yet
                       if (errinj_q[17] | 
                           (~errinj_q[31] & ~errinj_q[30]))
                         begin
                            errinj_d[31] = 1'b1;
                         end
                    end
                  else
                    begin
                       errinj_count_d = errinj_count_q + 16'h0001;
                    end
               end
          end

        // capture debug read data
        if( dbgdisp_d[31] == 1'b1 & dbg_req == 1'b0 & dbg_ack_q )
          begin
             dbgdisp_d[31] = 1'b0;
             dbgdisp_data_d = dbg_data_q;
          end

        
       
        // connect config to outputs
        // ----------------
   
        // NVME debug
        // indirect config or mmio access to PCIE & NVME registers
        regs_pcie_valid     = nvme_dbg_control_q[0] & ~nvme_dbg_status_q[1];
        regs_pcie_rnw       = nvme_dbg_control_q[1];
        regs_pcie_configop  = nvme_dbg_control_q[2];
        regs_pcie_be        = nvme_dbg_control_q[7:4];
        regs_pcie_tag       = nvme_dbg_control_q[15:12];
        regs_pcie_addr      = nvme_dbg_control_q[2] ? 
                              {zero[31:10], nvme_dbg_control_q[27:18]} :
                              nvme_dbg_addr_q;
        regs_pcie_wrdata      = nvme_dbg_data_q;
        nvme_dbg_status_d[1]  = nvme_dbg_status_d[1] | pcie_regs_ack; // command sent
        if( nvme_dbg_control_q[2] | nvme_dbg_control_q[1] ) 
          nvme_dbg_status_d[0] = nvme_dbg_status_d[0] | pcie_regs_cpl_valid; // non-posted
        else
          nvme_dbg_status_d[0] = nvme_dbg_status_d[0] | pcie_regs_ack; // posted
       
        if( pcie_regs_cpl_valid )
          begin
             nvme_dbg_status_d[18:4]  = pcie_regs_cpl_status;
             nvme_dbg_data_d          = pcie_regs_cpl_data;
          end    


        // use ~config_q[0] to assert perst continuously
        // use config[4] to start a perst for 100us
        // one cycle pulse, config[4] automatically cleared
        // regs_pcie_perst = config_q[4] | ~config_q[0] | i_fc_fatal_error;   // added i_fc_fata_error for fc detected perrors kch 
        // config_q[4], config_q[23:16] are used in perst module below
        if( config_q[4] )
          config_d[4]             = 1'b0;

        regs_cmd_disableto        = config_q[7];
        
        led_red                   = ~config_q[24];
        led_green                 = ~config_q[25];
        led_blue                  = ~config_q[26];

        regs_unmap_timer1         = config4_q[11:0];
        regs_unmap_timer2         = config4_q[31:12];
        regs_unmap_rangecount     = config4_q[39:32];
        regs_unmap_reqcount       = config4_q[47:40];
        
        regs_ctl_shutdown         = config2_q[4];
        regs_ctl_shutdown_abrupt  = config2_q[5];
        
        regs_cmd_maxiowr          = { 1'b0, config2_q[47:40]};
        regs_cmd_maxiord          = { 1'b0, config2_q[56:48]};
      
        regs_cmd_debug            = config3_q[15:0];

        // error types - {wdata, lookup, address decode, byteen} 
        // 2b per error type - 
        // 00:return deadbeef
        // 01:completer abort
        // 10:unsupported request
        regs_dma_errcpl           = config3_q[31:24];

        regs_xx_disable_reset     = config3_q[16];
        freeze_on_error           = config3_q[17];
        regs_sntl_rsp_debug       = config3_q[18];

        // config3(20) - clear performance counters. return-to-zero bit
        regs_sntl_perf_reset      = config3_q[20];
        if( config3_q[20] )
          begin
             config3_d[20] = 1'b0;
          end
        


        regs_xx_maxxfer           = tgt_maxxfer_q[datalen_width-1-12:0];
       
        
     end // always @ *

     wire regs_perst_in = config_q[4] | ~config_q[0] | i_fc_fatal_error;


   nvme_regs_perst_test perst
   (
    // Outputs
    .regs_pcie_perst                    (regs_pcie_perst),
    .regs_pcie_debug                    (regs_pcie_debug[7:0]),
    // Inputs
    .reset                              (reset),
    .clk                                (clk),
    .pcie_xx_link_up                    (pcie_xx_link_up),
    .pcie_xx_init_done                  (pcie_xx_init_done),
    .pcie_regs_status                   (pcie_regs_status[31:0]),
//    .perst_in                           (config_q[4] | ~config_q[0]),
    .perst_in                           (regs_perst_in),                         // added in pe errors kch 
    .debug_in                           (config_q[23:16]));

// generate parity just cause its easier kch dbg_offset_q
   wire        regs_cmd_trk_addr_par_in;
   nvme_pgen#
  (
   .bits_per_parity_bit(8),
   .width(tag_width)
  ) ipgen_dbg_offset_q 
  (.oddpar(1'b1),.data(dbg_offset_q[tag_width-1:0]),.datap(regs_cmd_trk_addr_par_in)); 

   
   always @*
     begin
        // array reads for debug
        // access indirectly through dbgdisp/dbgdisp_data registers
        // GA2: map to mmio space directly
        // port 0

        // 0x2060000 - 0x2060FFF = mmio config regs
        // 0x2061000 - 0x2061FFF = SNTL dump - 512 regs
        // 0x2062000 - 0x2063FFF = IOQ dump  - 1536 regs
        // 0x2065000 - 0x2065FFF = ADQ dump  -  512 regs
        // 0x2066000 - 0x2067FFF = PCIE dump - 1024 regs
        // 0x2068000 - 0x206BFF8 = exchange table dump - 2048 regs (512b per entry)
        // 0x206C000 - 0x206FFFF = PCIE traces - 16KB
        // 0x2070000 - 0x207FFFF = PCIE traces - 64KB
        

        // ---------------
        // dbgdisp[31]    = read enable
        // dbgdisp[30:24] = array select
        //                  0x00 = exchange table
        //                  0x01 = NVMe admin payload override
        //                  0x02 = NVMe admin payload read
        //                  0x03 = IOQ 
        //                  0x04 = ADQ 
        //                  0x05 = PCIE 
        //                  0x06 = SNTL
        //
        //                  0x55 = microcode write
        //                  0x56 = microcode read
        // dbgdisp[18:16] = word select
        // dbgdisp[15:0]  = tag/address

        dbg_valid = 1'b0;
        dbg_ack_d = 1'b1;
        dbg_select = 7'h00;
        dbg_word[2:0] = addr_q[5:3];
        dbg_offset = 16'h0000;
        dbg_data_d = ~zero[63:0];
        
        if( dbg_req && ~dbg_ack_q )
          begin
             // direct access via mmio           

             if( addr_q[16:12]>5'h0 &&
                 addr_q[16:12]<5'h2) 
               begin
                  dbg_valid = 1'b1;
                  dbg_ack_d = 1'b0;
                  // SNTL dump 
                  dbg_offset[15:0] = {7'b0, addr_q[11:3]};  
                  dbg_select[6:0] = 7'h06;               
               end                      
             if( addr_q[16:12]>5'd1 &&
                 addr_q[16:12]<5'd5 )
               begin
                  dbg_valid = 1'b1;
                  dbg_ack_d = 1'b0;
                  // IOQ dump
                  dbg_offset[15:0] = {5'b0, ~addr_q[13], addr_q[12:3]};  
                  dbg_select[6:0] = 7'h03;  
               end       
             if( addr_q[16:12]>5'd4 &&
                 addr_q[16:12]<5'd6 )
               begin
                  dbg_valid = 1'b1;
                  dbg_ack_d = 1'b0;
                  // ADQ dump
                  dbg_offset[15:0] = {7'b0, addr_q[11:3]};  
                  dbg_select[6:0] = 7'h04;  
               end                 
             if( addr_q[16:12]>5'd5 &&
                 addr_q[16:12]<5'd8 )
               begin
                  dbg_valid = 1'b1;
                  dbg_ack_d = 1'b0;
                  // PCIE dump
                  dbg_offset[15:0] = {6'b0, addr_q[12:3]};  
                  dbg_select[6:0] = 7'h05;  
               end
             if( addr_q[16:12]>5'h7 &&
                 addr_q[16:12]<5'hC) 
               begin
                  dbg_valid = 1'b1;
                  dbg_ack_d = 1'b0;
                  // exchange table dump - 16KB
                  dbg_offset[15:0] = {7'b0, addr_q[14:6]};  
                  dbg_select[6:0] = 7'h00;               
               end
             if( addr_q[16:12]>=5'h0C &&
                 addr_q[16:12]< 5'h10 )
               begin
                  dbg_valid = 1'b1;
                  dbg_ack_d = 1'b0;
                  // PCIE trace - first 16KB
                  dbg_offset[15:0] = {3'b100, 2'b00, addr_q[13:3]};  
                  dbg_select[6:0] = 7'h05;  
               end             
             if( addr_q[16:12]>=5'h10 )
               begin
                  dbg_valid = 1'b1;
                  dbg_ack_d = 1'b0;
                  // PCIE trace - 64KB
                  dbg_offset[15:0] = {3'b101, addr_q[15:3]};  
                  dbg_select[6:0] = 7'h05;  
               end             
          end
        else
          begin
             // indirect mmio access
             dbg_valid = dbgdisp_q[31];
             dbg_ack_d = 1'b0;
             dbg_select[6:0] = dbgdisp_q[30:24];
             dbg_word[2:0] = dbgdisp_q[18:16];
             dbg_offset[15:0] = dbgdisp_q[15:0];
          end     
   
        dbg_offset_d = dbg_offset;
        dbg_trk_rd_d = dbg_valid & dbg_select==7'h00;
        regs_cmd_trk_rd = dbg_trk_rd_q & ~dbg_ack_q;
        regs_cmd_trk_addr = dbg_offset_q[tag_width-1:0];
        regs_cmd_trk_addr_par = regs_cmd_trk_addr_par_in;
        if (cmd_regs_trk_ack)
          begin
             dbg_ack_d = 1'b1;
             case (dbg_word)
               3'b000: dbg_data_d = cmd_regs_trk_data[63:0];
               3'b001: dbg_data_d = cmd_regs_trk_data[127:64];
               3'b010: dbg_data_d = {cmd_regs_trk_data[191:128]};
               3'b011: dbg_data_d = {cmd_regs_trk_data[255:192]};
               3'b100: dbg_data_d = cmd_regs_trk_data[319:256];
               3'b101: dbg_data_d = cmd_regs_trk_data[383:320];
               3'b110: dbg_data_d = {cmd_regs_trk_data[447:384]};
               3'b111: dbg_data_d = {cmd_regs_trk_data[511:448]};              
               default: dbg_data_d = dbgdisp_data_q;
             endcase
          end
        
        dbg_ioq_rd_d = dbg_valid & dbg_select==7'h03;
        regs_ioq_dbg_rd   = dbg_ioq_rd_q & ~dbg_ack_q;
        regs_ioq_dbg_addr = dbg_offset_q;
        if (ioq_regs_dbg_ack)
          begin
             dbg_ack_d = 1'b1;
             dbg_data_d = ioq_regs_dbg_data[63:0];
          end

        dbg_adq_rd_d = dbg_valid & dbg_select==7'h04;
        regs_adq_dbg_rd   = dbg_adq_rd_q & ~dbg_ack_q;
        regs_adq_dbg_addr = dbg_offset_q;
        if (adq_regs_dbg_ack)
          begin
             dbg_ack_d = 1'b1;
             dbg_data_d = adq_regs_dbg_data[63:0];
          end

        dbg_pcie_rd_d = dbg_valid & dbg_select==7'h05;
        regs_pcie_dbg_rd   = dbg_pcie_rd_q & ~dbg_ack_q;
        regs_pcie_dbg_addr = dbg_offset_q;
        if (pcie_regs_dbg_ack)
          begin
             dbg_ack_d = 1'b1;
             dbg_data_d = pcie_regs_dbg_data[63:0];
          end
        
        dbg_sntl_rd_d = dbg_valid & dbg_select==7'h06;
        regs_sntl_dbg_rd   = dbg_sntl_rd_q & ~dbg_ack_q;
        regs_sntl_dbg_addr = dbg_offset_q;
        if (sntl_regs_dbg_ack)
          begin
             dbg_ack_d = 1'b1;
             dbg_data_d = sntl_regs_dbg_data[63:0];
          end

        
        // access to microcode data/program space indirect through microcode loader
        regs_ctl_ldrom = dbg_valid & (dbg_select==7'h55 | dbg_select==7'h56 | dbg_select==7'h01 | dbg_select==7'h02 );
       
     end // always @ *

   
   // status events
   always @*
     begin
        event_d[0] = mtip_offline2online_q;
        event_d[1] = mtip_online2offline_q;
        event_d[2] = event_ioqenable_q[0] & ~event_ioqenable_q[1]; // "login succeed" - ready for I/O
        event_d[3] = event_logifail_q[0] & ~event_logifail_q[1];
        event_d[4] = event_logiretry_q[0] & ~event_logiretry_q[1];
        event_d[5] = crc_threshold_q[0] & ~crc_threshold_q[1];
        event_d[6] = event_logo_q[0] & ~event_logo_q[1];
        event_d[7] = event_other_q[0] & ~event_other_q[1];
        if (errinj_event_int)
          event_d = event_d | dbgdisp_data_q[7:0];
        o_status_event_out = event_q;
     end


   // debug to pcie debug trace
   always @*
     begin
        regs_pcie_debug_trace[31:0] = { zero[31:22] , event_q, errcap_v_q, reset, error_q[3:0], status_q[39:32] };
     end
   
 
   // timer function
   // ------------------------------
   // timer1 is free running
   // timer2 is runs when there's no RX backpressure
   reg          [7:0] timer1_us_tick_q, timer1_us_tick_d; 
   reg          [7:0] timer2_us_tick_q, timer2_us_tick_d;
   reg          [7:0] timer3_us_tick_q, timer3_us_tick_d;  // measure how long backpressure is on at rdata interface
   reg          [7:0] timer4_us_tick_q, timer4_us_tick_d;
   reg                tick1_q, tick1_d;
   reg                tick2_q, tick2_d;

   always @(posedge clk or posedge reset)
     begin
        if (reset)
          begin
             timer1_q         <= 36'h0;
             timer2_q         <= 36'h0;
             timer3_q         <= 20'h0;
             timer3_max_q     <= 20'h0;
             timer4_q         <= 32'h0;
             timer1_us_tick_q <= 8'h0;
             timer2_us_tick_q <= 8'h0;
             timer3_us_tick_q <= 8'h0;
             timer4_us_tick_q <= 8'h0;
             tick1_q          <= 1'b0;	
             tick2_q          <= 1'b0;	
          end
        else
          begin
             timer1_q         <= timer1_d;           
             timer2_q         <= timer2_d;           
             timer3_q         <= timer3_d;           
             timer3_max_q     <= timer3_max_d;           
             timer4_q         <= timer4_d;           
             timer1_us_tick_q <= timer1_us_tick_d;
             timer2_us_tick_q <= timer2_us_tick_d;
             timer3_us_tick_q <= timer3_us_tick_d;
             timer4_us_tick_q <= timer4_us_tick_d;
             tick1_q          <= tick1_d;
             tick2_q          <= tick2_d;           
          end
     end


   always @*
     begin
       

        timer1_d          = timer1_q;
        timer1_us_tick_d  = timer1_us_tick_q;  // 1 us free running
        
        timer1_us_tick_d  = timer1_us_tick_q+8'h1;
        if (timer1_us_tick_q >= 8'd249)
          begin
             timer1_us_tick_d  = 8'h0;   
             tick1_d = 1'b1;
          end
        else
          begin
             tick1_d = 1'b0;
          end

        if( tick1_q )
          begin
             timer1_d[35:0] = timer1_q[35:0] + 36'h1;  
          end  
        regs_xx_tick1 = tick1_q;
        regs_xx_timer1 = timer1_q;  // 1us
     end

   always @*
     begin
        timer2_d          = timer2_q;
        timer2_us_tick_d  = timer2_us_tick_q;  // 1us with backpressure
        tick2_d           = 1'b0;
        regs_xx_tick2     = tick2_q;
        
        if( pcie_regs_sisl_backpressure == 1'b0 )
          begin
             timer2_us_tick_d = timer2_us_tick_q+8'h1;
             if (timer2_us_tick_q == 8'd249)
               begin
                  timer2_us_tick_d = 8'h0;                                 
                  timer2_d[35:0] = timer2_q[35:0] + 35'h1; 
                  if( timer2_q[13:0] == 14'h3FFF )
                    begin
                       tick2_d = 1'b1;
                    end                            
               end             
          end

        // use fast timeout?
        if( config_q[35] )
          regs_xx_timer2 = timer2_q[15:0]; // 1us
        else
          regs_xx_timer2 = timer2_q[29:14];  // 16.384 ms

        regs_cmd_IOtimeout2 = e_d_tov_q[15:0];
        regs_ioq_icqto      = e_d_tov_q[15:0];
     end


   // measure duration of backpressure on rdata interface
   always @*
     begin
        timer3_d          = timer3_q;
        if( timer3_max_reset )
          timer3_max_d    = 20'h0;
        else          
          timer3_max_d    = timer3_max_q;
        timer3_us_tick_d  = timer3_us_tick_q;  // 1us with backpressure
      
        
        if( (config2_q[13:12]==2'b00 && sntl_regs_rdata_paused == 1'b1) || 
            (config2_q[13:12]==2'b01 && pcie_regs_sisl_backpressure == 1'b1) ||
            (config2_q[13:12]==2'b10 && pcie_regs_rxcq_backpressure == 1'b1) )       
          begin             
             timer3_us_tick_d = timer3_us_tick_q+8'h1;
             if (timer3_us_tick_q == 8'd249)
               begin
                  timer3_us_tick_d = 8'h0;       
                  if( timer3_q != 20'hFFFFF )
                    begin
                       timer3_d[19:0] = timer3_q[19:0] + 20'h1;
                    end
               end             
          end      
        else
          begin
             timer3_us_tick_d  = 8'h0;
             timer3_d          = 20'h0;
             if( timer3_q > timer3_max_q )
               begin
                  timer3_max_d = timer3_q;
               end
          end     
     end

   

   // measure total backpressure on rdata, sntl_dma, or rxcq interfaces
   always @*
     begin
        timer4_d          = timer4_q;    
        timer4_us_tick_d  = timer4_us_tick_q;  // 1us with backpressure
              
        if( (config2_q[13:12]==2'b00 && sntl_regs_rdata_paused == 1'b1) || 
            (config2_q[13:12]==2'b01 && pcie_regs_sisl_backpressure == 1'b1) ||
            (config2_q[13:12]==2'b10 && pcie_regs_rxcq_backpressure == 1'b1) )       
          begin             
             timer4_us_tick_d = timer4_us_tick_q+8'h1;
             if (timer4_us_tick_q == 8'd249)
               begin
                  timer4_us_tick_d = 8'h0;                                 
                  timer4_d[31:0] = timer4_q[31:0] + 32'h1;
               end             
          end      
     end


endmodule

   
