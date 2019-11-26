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
//----------------------------------------------------------------------------- 
// 
// IBM Confidential 
// 
// IBM Confidential Disclosure Agreement Number: 20160104OPPG01 
// Supplement Number: 20160104OPPG02
// 
// (C) Copyright IBM Corp. 2016 
// 
//    The source code for this program is not published or otherwise 
//    divested of its trade secrets, irrespective of what has been 
//    deposited with the U.S. Copyright Office. 
// 
//----------------------------------------------------------------------------- 
//                      MMIO ADDRESS MAP 
//  0x2000000       per context cpc 
//  0x2010000       Global Regs 
//  0x2011000       performance and error
//  0x2011100       error inject
//  0x2011200       fcport 0
//  0x2011300       fcport 1
//  0x2011400       lun table port 0
//  0x2011500       lun table port 1
//  0x2011600       fcport 2
//  0x2011700       fcport 3
//  0x2011800       lun table port 2
//  0x2011900       lun table port 2
//  0x2040000        start of afu debug
//  0x2040100       Error Monitor
//  0x2040800       Debug Count regs 
//  0x2041000       Debug Regs
//  0x2042000       Performance Counters
//  0x2042800       Trace command Address
//  0x2043000       Trace Return Data 
//  0x2045000       next available address   *******unused   ********
//  0x2048000       Tracking Table
//  0x2050000       Trace Buffer
//  0x2058000       RRQ  -- need to fix somehing here 
//  0x206000       afu debug port 0    end of AFU Debug 
//  0x208000       afu debug port 1 
//  0x20A000       afu debug port 0 
//  0x20C000       afu debug port 1 

`define DEBUG_CNT      //comment out to get rid of begug counters
`define DEBUG_REG      //comment out to get rid of begug registers
// `define DEBUG_BUF  // comment out to get rid of debug buffers
module ktms_afu#
  (
   parameter szl = 0,
   parameter id                 = 0,
   parameter ctxtid_width       = 10,
   parameter time_width         = 16,
   parameter ea_width           = 65,   // changed from 64 to 65 to add ea parity kch 
   parameter la_width           = 24,
   parameter ssize_width        = 32,
   //   parameter mmio_base          = 0,
   parameter data_latency       = 1,
   //   parameter kdw                = 128,
   //   parameter slite_width        = 32,
   parameter lunid_width        = 64,    // changed 64 to 65 to add parity kch 
   parameter lunid_width_w_par        = 65,    // changed 64 to 65 to add parity kch 
   parameter channels           = 2,  // how many serial-lite channels
   parameter chnlid_width = $clog2(channels),
   parameter max_reads          = 256, // max outstanding reads per channel
   parameter max_writes         = 256, // max outstanding writes per channel
   parameter syncid_width = 1,   
   parameter tag_width          = 10,   // changed 9 to 10 to add parity kch 
   parameter lba_width          = 32,
   parameter cdb_width = 128,
   parameter cdb_par_width = 2,
   parameter cdb_width_w_par  = 128 +2,   //added parity 
   parameter dma_rc_width = 8,
   parameter afu_rc_width = 8,
   parameter afu_erc_width=8,
   parameter datalen_width = 25,
   parameter datalen_par_width = 1, // kch
   parameter datalen_width_w_par = datalen_width+datalen_par_width,  // kch 


   // FC Interface Parameters
   parameter fc_cmd_width       = 2,
   parameter fc_tag_width       = 8,                     
   parameter fc_tag_par_width      = (fc_tag_width + 63)/64,
   parameter fc_tag_width_w_par    = fc_tag_width+fc_tag_par_width, // added kch
   parameter fc_lunid_width     = lunid_width,
   parameter fc_lunid_par_width = (fc_lunid_width + 63)/64,
   parameter fc_bufid_width     = 3,
   parameter fc_beatid_width    = datalen_width-1,
   parameter fc_data_width      = 128,   // changed from 32 to 128 kch
   parameter fc_data_par_width  = (fc_data_width + 63)/64,// parity every 64 bits 
   parameter fc_bytec_width = $clog2((fc_data_width/8)+1),
   parameter fc_status_width = 8,
   parameter log_width          = 72,
   parameter fcstat_width = 8,
   parameter fcxstat_width = 8,
   parameter scstat_width = 8,
   parameter fcinfo_width = 160,
   parameter reslen_width = 32,
   parameter sk_width = 4,
   parameter asc_width = 16
   )
   (

    // FC-0 Interface
    ////////////////////////////////////////////////////////////////
    input                     [0:channels-1] o_fc_req_r,
    output                    [0:channels-1] o_fc_req_v,
    output       [0:fc_cmd_width*channels-1] o_fc_req_cmd, 
    output       [0:fc_tag_width*channels-1] o_fc_req_tag, 
    output   [0:fc_tag_par_width*channels-1] o_fc_req_tag_par, 
    output     [0:fc_lunid_width*channels-1] o_fc_req_lun, 
    output [0:fc_lunid_par_width*channels-1] o_fc_req_lun_par,
    output          [0:cdb_width*channels-1] o_fc_req_cdb,
    output      [0:cdb_par_width*channels-1] o_fc_req_cdb_par, // added kch ,
    output      [0:datalen_width*channels-1] o_fc_req_length,
    output  [0:datalen_par_width*channels-1] o_fc_req_length_par,


    input                     [0:channels-1] i_fc_wdata_req_v,
    output                    [0:channels-1] i_fc_wdata_req_r,
    input        [0:fc_tag_width*channels-1] i_fc_wdata_req_tag,
    input    [0:fc_tag_par_width*channels-1] i_fc_wdata_req_tag_par,
    input     [0:fc_beatid_width*channels-1] i_fc_wdata_req_beat,
    input       [0:datalen_width*channels-1] i_fc_wdata_req_size,
    input                     [0:channels-1] i_fc_wdata_req_size_par, //added kch ,

    output                    [0:channels-1] o_fc_wdata_rsp_v,
    input                     [0:channels-1] o_fc_wdata_rsp_r,
    output                    [0:channels-1] o_fc_wdata_rsp_e,
    output                    [0:channels-1] o_fc_wdata_rsp_error, 
    output       [0:fc_tag_width*channels-1] o_fc_wdata_rsp_tag,
    output   [0:fc_tag_par_width*channels-1] o_fc_wdata_rsp_tag_par,
    output    [0:fc_beatid_width*channels-1] o_fc_wdata_rsp_beat,
    output      [0:fc_data_width*channels-1] o_fc_wdata_rsp_data,
    output  [0:fc_data_par_width*channels-1] o_fc_wdata_rsp_data_par,

    input                     [0:channels-1] i_fc_rdata_rsp_v,
    output                    [0:channels-1] i_fc_rdata_rsp_r,
    input                     [0:channels-1] i_fc_rdata_rsp_e,
    input      [0:fc_bytec_width*channels-1] i_fc_rdata_rsp_c,
    input     [0:fc_beatid_width*channels-1] i_fc_rdata_rsp_beat,
    input        [0:fc_tag_width*channels-1] i_fc_rdata_rsp_tag,
    input    [0:fc_tag_par_width*channels-1] i_fc_rdata_rsp_tag_par,
    input       [0:fc_data_width*channels-1] i_fc_rdata_rsp_data,
    input   [0:fc_data_par_width*channels-1] i_fc_rdata_rsp_data_par,

    input                     [0:channels-1] i_fc_rsp_v,
    input        [0:fc_tag_width*channels-1] i_fc_rsp_tag,
    input    [0:fc_tag_par_width*channels-1] i_fc_rsp_tag_par, // add parity kch
    input        [0:channels*fcstat_width-1] i_fc_rsp_fc_status,
    input        [0:channels*fcstat_width-1] i_fc_rsp_fcx_status,
    input        [0:channels*scstat_width-1] i_fc_rsp_scsi_status,
    input        [0:channels*fcinfo_width-1] i_fc_rsp_info,
    input                     [0:channels-1] i_fc_rsp_fcp_valid, 
    input                     [0:channels-1] i_fc_rsp_sns_valid,
    input                     [0:channels-1] i_fc_rsp_underrun,
    input                     [0:channels-1] i_fc_rsp_overrun,
    input                  [0:32*channels-1] i_fc_rsp_resid,
    input     [0:channels*fc_beatid_width-1] i_fc_rsp_rdata_beats,
    input     [0:fc_status_width*channels-1] i_fc_status_event,
    input                     [0:channels-1] i_fc_port_ready,
    input                     [0:channels-1] i_fc_port_fatal_error,
    input                     [0:channels-1] i_fc_port_enable_pe,


    output                    [0:channels-1] o_fc_mmval,
    output                    [0:channels-1] o_fc_mmcfg,
    output                    [0:channels-1] o_fc_mmrnw,
    output                    [0:channels-1] o_fc_mmdw,
    output           [0:la_width*channels-1] o_fc_mmad,
    output               [0:(64*channels)-1] o_fc_mmdata,
    input                     [0:channels-1] i_fc_mmack,
    input                [0:(64*channels)-1] i_fc_mmdata,

    // afu version - put at top level to avoid recompile for version change
    input                             [0:63] i_afu_version,
    // user_image - 0: factory 1: user
    input                                    i_user_image,
    
    // AFU reset command to FC
    output                                   o_reset,
    input                                    i_reset,

    output                                   o_fc_fatal_error,

// psl interface 

    output                                   ah_paren,
    input                                    ha_jval, // A valid job control command is present
    input                              [0:7] ha_jcom, // Job control command opcode
    input                                    ha_jcompar, // Job control parity
    input                             [0:63] ha_jea, // Save/Restore address
    input                                    ha_jeapar, // parity
    output                                   ah_jrunning, // Accelerator is running
    output                                   ah_jdone, // Accelerator is finished
    output                            [0:63] ah_jerror, // Accelerator error code. 0 = success
    output                                   ah_tbreq, // timebase request (not used)
    output                                   ah_jyield, // Accelerator wants to stop
    output                                   ah_jcack, 
    input                                    ha_pclock, // 250MHz clock

   // Accelerator Command Interface
    output                                   ah_cvalid, // A valid command is present
    output                             [0:7] ah_ctag, // request id
    output                                   ah_ctagpar,
    output                            [0:12] ah_com, // command PSL will execute
    output                                   ah_compar, // parity for command
    output                             [0:2] ah_cpad, // prefetch inattributes
    output                             [0:2] ah_cabt, // abort if translation intr is generated
    output                            [0:15] ah_cch, // context
    output                            [0:63] ah_cea, // Effective byte address for command
    output                                   ah_ceapar, // Effective byte address for command
    output                            [0:11] ah_csize, // Number of bytes
    input                              [0:7] ha_croom, // Commands PSL is prepared to accept

   // Accelerator MMIO Interface
    input                                    ha_mmval, // A valid MMIO is present
    input                                    ha_mmrnw, // 1 = read, 0 = write
    input                                    ha_mmdw, // 1 = doubleword, 0 = word
    input                             [0:23] ha_mmad, // mmio address
    input                                    ha_mmcfg,
    input                                    ha_mmadpar,
    input                             [0:63] ha_mmdata, // Write data
    input                                    ha_mmdatapar, // Write data
    output                                   ah_mmack, // Write is complete or Read is valid
    output                            [0:63] ah_mmdata, // Read data
    output                                   ah_mmdatapar, // Read data

   //x PSL Response Interface
    input                                    ha_rvalid, // A response is present
    input                              [0:7] ha_rtag, // Accelerator generated request ID  not implementing parity yet kch 
    input                                    ha_rtagpar,
    input                              [0:8] ha_rditag, // Accelerator generated request ID  not implementing parity yet kch 
    input                                    ha_rditagpar, 
    input                              [0:7] ha_response, // response code
    input                              [0:8] ha_rcredits, // twos compliment number of credits
    input                              [0:1] ha_rcachestate, // Resultant Cache State
    input                             [0:12] ha_rcachepos, // Cache location id


// DMA Interface 

    output                                   d0h_dvalid, 
    output                             [0:9] d0h_req_utag, 
    output                             [0:8] d0h_req_itag, 
    output                             [0:2] d0h_dtype, 
    output                             [0:9] d0h_dsize, 
    output                             [0:5] d0h_datomic_op, 
    output                                   d0h_datomic_le, 
    output                          [0:1023] d0h_ddata,

    input                                    hd0_sent_utag_valid, 
    input                              [0:9] hd0_sent_utag, 
    input                              [0:2] hd0_sent_utag_sts, 

    input                                    hd0_cpl_valid,
    input                              [0:9] hd0_cpl_utag,
    input                              [0:2] hd0_cpl_type,
    input                              [0:6] hd0_cpl_laddr,
    input                              [0:9] hd0_cpl_byte_count,
    input                              [0:9] hd0_cpl_size,
    input                           [0:1023] hd0_cpl_data

    
   
 //  `include "psl_io_decls.inc"
    );
   
   localparam afu_rsp_width = afu_rc_width+afu_erc_width;
   localparam rslt_width = afu_rsp_width+2+reslen_width+fcstat_width+fcxstat_width+scstat_width+2+fcinfo_width;

   localparam tstag_width = tag_width;
   
   localparam lidx_width = 8; // index into per-port lun table
   localparam mmiobus_awidth = 29;    // changed from 28 to 29 to add address parity kch
   localparam mmiobus_width = mmiobus_awidth+65;   // changed 64 to 65 to add address parity kch 
   localparam rh_width = 15;
   localparam msinum_width = 8;
   localparam rrqnum_width = 2;
   localparam croom_width=8;
   localparam ctxtcap_width=7;

   // per context mmio space
   localparam mmioaddr_rrin     = 'h08;
   localparam mmioaddr_rrq_st   = 'h0a;
   localparam mmioaddr_rrq_ed   = 'h0c;
   localparam mmioaddr_flow_ctrl= 'h0e; // read only

   // master context mmio space
   localparam mmioaddr_gbl_reg      = 'h804000;
   localparam mmioaddr_perferr_base = 'h804400;
   localparam mmioaddr_err_inj      = mmioaddr_perferr_base + 'h100;

   // per-context provisioning and control
   localparam mmioaddr_cpc     = 'h800000; // start of 
   localparam mmioaddr_luntbl  = 'h804000;   // start of mmio space. luntbl further decioded in luntbl.v kch  orig h805000


//   localparam mmioaddr_errmon       = 'h810000;
   localparam mmioaddr_errmon       = 'h810040;
   localparam mmioaddr_dbg_cnt      = 'h810200;
   localparam mmioaddr_dbg_reg      = 'h810400;
   localparam mmioaddr_perfmon      = 'h810800;
   localparam mmioaddr_pslrdabuffer = 'h810A00; // 0x80 entries is 0x400
   localparam mmioaddr_pslrddbuffer = 'h810C00; // address 0x2000
   localparam mmioaddr_next_avail   = 'h811400;    
   localparam mmioaddr_track        = 'h812000; // 0x2000 entries 
   localparam mmioaddr_tracebuffer  = 'h814000; // 2048 = 0x800 entries 
   localparam mmioaddr_rrq          = 'h816000;
   
   // psl reponses
   localparam [0:dma_rc_width-1] psl_rsp_paged = 'd10;
   localparam [0:dma_rc_width-1] psl_rsp_addr = 'd01;
   localparam [0:dma_rc_width-1] psl_rsp_cinv = 'd81; 
   
   // sync interupt codes
   localparam sintrid_width = 3;
   
   localparam [0:sintrid_width-1] sintr_croom = 'd4;
   localparam [0:sintrid_width-1] sintr_rcb   = 'd3;
   localparam [0:sintrid_width-1] sintr_asa   = 'd2;
   localparam [0:sintrid_width-1] sintr_rrq   = 'd1;
   localparam [0:sintrid_width-1] sintr_paged = 'd0;
   
   localparam dma_bytec_width = 4;
   
   // cycle counter for performance

   wire [0:63] 				     gbl_reg6;
   wire [0:63]                               gbl_reg7;
   wire [0:63]                               gbl_reg8;
   wire [63:0]                               gbl_reg9;
   wire [0:63]                               gbl_reg10;
   wire [0:63]                               gbl_reg11;
   

   
   wire [0:mmiobus_width-1] 		     mmiobus;
   wire [0:mmiobus_awidth-1] 		     mmio_abus=mmiobus[0:mmiobus_awidth-1];
   wire                                      iafu_ha_vld = mmio_abus[0];
   wire                                      iafu_ha_cfg = mmio_abus[1];
   wire                                      iafu_ha_rnw = mmio_abus[2];
   wire                                      iafu_ha_dw = mmio_abus[3];
   wire [0:23]                               iafu_ha_adr = mmio_abus[4:mmiobus_awidth-2];
   localparam ngets = channels+3;
   
   wire [0:(ea_width*ngets)-1] 		     get_addr_d_ea;
   wire [0:(ssize_width*ngets)-1] 	     get_addr_d_size;

   wire [0:(ctxtid_width*ngets)-1] 	     get_addr_d_ctxt;
   wire [0:(tstag_width*ngets)-1] 	     get_addr_d_tstag;
   wire [0:ngets-1] 			     get_addr_v;
   wire [0:ngets-1] 			     get_addr_r;
   
   wire [0:(130*ngets)-1] 		     get_data_d;   // changed 128 to 130 to add parity kch check from here
   wire [0:(dma_bytec_width*ngets)-1] 	     get_data_c;
   wire [0:ngets-1] 			     get_data_v;
   wire [0:ngets-1] 			     get_data_e;
   wire [0:ngets-1] 			     get_data_r;
   wire [0:dma_rc_width*ngets-1] 	     get_data_rc;
   wire [0:ssize_width*ngets-1] 	     get_data_bcnt;
   

   localparam nputs = channels+2;
   wire [0:nputs-1] 			     put_addr_v; 
   wire [0:ea_width*nputs-1] 		     put_addr_d_ea;
   wire [0:ctxtid_width*nputs-1] 	     put_addr_d_ctxt;
   wire [0:tstag_width*nputs-1] 	     put_addr_d_tstag;				
   
   wire [0:nputs-1] 			     put_addr_r;
   wire [0:nputs-1] 			     put_data_r;
   
   wire [0:nputs-1] 			     put_data_v;
   wire [0:nputs-1] 			     put_data_e;
   wire [0:(130*nputs)-1] 		     put_data_d;   
   wire [0:(4*nputs)-1] 		     put_data_c;
   wire [0:nputs-1] 			     put_data_f;
   
   wire [0:nputs-1] 			     put_done_v;
   wire [0:nputs-1] 			     put_done_r;
   wire [0:nputs*dma_rc_width-1] 	     put_done_rc;
   wire [0:nputs*ssize_width-1] 	     put_done_bcnt;

   
   wire 				     hb_addr_v; 
   wire [0:ea_width-1] 			     hb_addr_d;
   wire 				     hb_addr_r;
   
   
   wire 				     hb_data_r,rslt_r;
   wire 				     hb_data_v,rslt_v;
   wire 				     hb_data_e;
   wire [0:127] 			     hb_data_d,rslt_d;
   wire 				     hb_done;
   wire 				     rslt_done;
   
   
   wire 				     clk = ha_pclock;
   
   wire 				     reset;
   
   wire [0:channels-1] 			     fc_mmack;

   wire 				     s1_afu_disable; /* from err monitor */

   wire 				     s1_mmval, s1_mmcfg,s1_mmrnw, s1_mmdw;
   wire [0:la_width-1] 			     s1_mmad;
   wire [0:63] 				     s1_mmdata;

   wire [0:63] 				     cycle_count;
   base_vlat#(.width(64)) icycle_count(.clk(clk),.reset(reset),.din(cycle_count+64'd1),.q(cycle_count));

   wire [0:31] 				     lr_timestamp;
`ifdef SIM
   assign lr_timestamp = cycle_count[32:63];
`else
   assign lr_timestamp = cycle_count[32:63];
`endif 				      

   
   base_vlat#(.width(4))           ifc_mmout_ctrl_lat(.clk(clk),.reset(reset),.din({ha_mmval,ha_mmcfg,ha_mmrnw,ha_mmdw}),.q({s1_mmval,s1_mmcfg,s1_mmrnw,s1_mmdw}));

   base_vlat#(.width(la_width+64)) ifc_mmout_data_lat(.clk(clk),.reset(1'b0),.din({ha_mmad,ha_mmdata}),.q({s1_mmad,s1_mmdata}));

   
   assign o_fc_mmval = {channels{s1_mmval}};
   assign o_fc_mmcfg = {channels{s1_mmcfg}};
   assign o_fc_mmdw  = {channels{s1_mmdw}};
   assign o_fc_mmrnw = {channels{s1_mmrnw}};
   assign o_fc_mmad  = {channels{s1_mmad}};
   assign o_fc_mmdata = {channels{s1_mmdata}};

   wire [0:(64*channels)-1] 		     fc_mmdata;
   base_vlat#(.width(65*channels)) ifc0_mmin_lat(.clk(clk),.reset(1'b0),.din({i_fc_mmack,i_fc_mmdata}),.q({fc_mmack,fc_mmdata}));


   localparam dbg_cnt_regs=71+28+8+21; // added +14 for 2 additional ports kch   made it 128 bits added 2 more
   
   wire [0:dbg_cnt_regs-1]                   dbg_cnt_inc;
//   assign dbg_cnt_inc[50:53] = 4'b0000; 
//   assign dbg_cnt_inc[64:67] = 4'b0000; 
//   assign dbg_cnt_inc[79:80] = 2'b00;

   wire                                      dbgc_mmack;
   wire [0:63]                               dbgc_mmdata;

   wire 				     dbgr_mmack;
   wire [0:63] 				     dbgr_mmdata;
   
   wire 				     desc_mmack;
   wire [0:63] 				     desc_mmdata;
   localparam ctag_width = 8;
   localparam pea_width  = ea_width-13; //changed 12 to 13 for ea parity kch 
   localparam cnt_rsp_width = pea_width*2+ctxtid_width+ctag_width+4;
   wire 				     s1_cnt_rsp_v;
   wire [0:cnt_rsp_width-1] 		     s1_cnt_rsp_d;
   wire [0:63] 				     s1_desc_rega, s1_desc_regb;

   
   wire [0:72]                               o_perror;
   wire [0:6]                                s1_perror;
   wire                                      perror_total;
   wire                                      perror_unmasked;
   assign perror_unmasked = (o_perror[0:72] & ~{9'h0,gbl_reg11[0:63]}) != 73'h0;
   base_vlat#(.width(1)) iperror_total(.clk(clk),.reset(reset),.din(perror_unmasked),.q(perror_total));

   
   ktms_afu_desc#(.ctxtid_width(ctxtid_width),.ctag_width(ctag_width),.pea_width(pea_width),.cnt_rsp_width(cnt_rsp_width)) iafu_desc
     (.clk(clk),.reset(reset),.ha_mmval(ha_mmval),.ha_mmcfg(ha_mmcfg),.ha_mmdw(ha_mmdw),.ha_mmad(ha_mmad),.ha_mmrnw(ha_mmrnw),.ha_mmdata(ha_mmdata),.ha_mmdatapar(ha_mmdatapar),
      .ah_mmack(desc_mmack),.ah_mmdata(desc_mmdata),.o_cnt_rsp_v(s1_cnt_rsp_v),.o_cnt_rsp_d(s1_cnt_rsp_d),
      .o_rega(s1_desc_rega),.o_regb(s1_desc_regb),.o_perror(o_perror[0])
      );

   
   wire 				     reg_mmack;
   wire [0:63] 				     reg_mmdata;
   wire 				     s1_intr0_v, s1_intr0_r;
   wire [0:msinum_width-1] 		     s1_intr0_msi;
   wire [0:ctxtid_width-1] 		     s1_intr0_ctxt;
   // no transaction associated with async interupts, so don't use timestamp to validate
   wire [0:tstag_width-1] 		     s1_intr0_tstag = {tstag_width{1'b0}};
   wire 				     s1_intr0_tstag_v = 1'b0;
   wire [0:63] 				     s1_errinj;

   wire [0:ctxtid_width-1] 		     s1_ctxt_upd_d;
   wire 				     s1_ctxt_add_v;
   wire 				     s1_ctxt_upd_v;
   wire 				     s1_ctxt_rmv_v;
   wire 				     s1_ctxt_trm_v;


   wire                                      o_localmode; // not used

   ktms_afu_gbl_reg#
     (.mmio_addr(mmioaddr_gbl_reg),.mmiobus_width(mmiobus_width),  
      .fc_status_width(channels*fc_status_width),.channels(channels),.msinum_width(msinum_width),
      .ctxtid_width(ctxtid_width)) igbl_reg
       (.clk(clk),.reset(reset),.i_mmiobus(mmiobus),
	.i_fc_event(i_fc_status_event),
	.i_fc_perror(o_perror[0:63]),  
	.i_ctxt_rmv_v(s1_ctxt_rmv_v),
	.i_ctxt_upd_d(s1_ctxt_upd_d),
        .i_afu_version(i_afu_version),
        .i_user_image(i_user_image),
	.o_mmio_rd_v(reg_mmack),.o_mmio_rd_d(reg_mmdata),
	.o_reg7(gbl_reg7),
	.o_reg6(gbl_reg6),
	.o_reg8(gbl_reg8),
	.o_reg9(gbl_reg9),
        .o_reg11(gbl_reg11),
	.o_intr_r(s1_intr0_r),
	.o_intr_v(s1_intr0_v),
	.o_intr_ctxt(s1_intr0_ctxt),
	.o_intr_msi(s1_intr0_msi),
	.o_localmode(o_localmode),
        .o_perror(o_perror[1])

	);
   
   wire 				     s2_mmack;
   wire [0:63] 				     s2_mmdata_in;

   wire 				     rrq_mmack;
   wire [0:63] 				     rrq_mmdata;
   wire 				     trk_mmack;
   wire [0:63] 				     trk_mmdata;
   wire 				     stl_mmack;
   wire [0:63] 				     stl_mmdata;
   wire 				     err_mmack;
   wire [0:63] 				     err_mmdata;
   wire [0:63] 				     cpc_mmdata;
   wire 				     cpc_mmack;
   wire [0:63] 				     int_mmdata;
   wire 				     int_mmack;
   wire [0:63] 				     tbf_mmdata;
   wire 				     tbf_mmack;
   wire [0:63] 				     ltb_mmdata;
   wire 				     ltb_mmack;
   wire [0:63] 				     pslrddtb_mmdata;
   wire 				     pslrddtb_mmack;
   wire [0:63] 				     pslrdatb_mmdata;
   wire 				     pslrdatb_mmack;
   
   
   ktms_afu_mmio_ack#(.mmiobus_awidth(mmiobus_awidth-1),.ways(14+channels)) immdata_mux   //strip off parity kch
     (.clk(clk),.reset(reset),.i_mmioabus(mmio_abus[0:mmiobus_awidth-2]),   // strip off parity kch 
      .i_v({int_mmack,  cpc_mmack,  dbgc_mmack, dbgr_mmack,  reg_mmack, rrq_mmack,trk_mmack, stl_mmack, desc_mmack,  fc_mmack, err_mmack, tbf_mmack,  ltb_mmack, pslrddtb_mmack, pslrdatb_mmack}),
      .i_d({int_mmdata, cpc_mmdata, dbgc_mmdata,dbgr_mmdata, reg_mmdata,rrq_mmdata,trk_mmdata,stl_mmdata,desc_mmdata, fc_mmdata,err_mmdata,tbf_mmdata, ltb_mmdata, pslrddtb_mmdata, pslrdatb_mmdata}),
      .o_v(s2_mmack),
      .o_d(s2_mmdata_in)
      );
   
   wire 				     irq_v, irq_r;
   wire [0:msinum_width-1] 		     irq_src;
   wire [0:ctxtid_width-1] 		     irq_ctxt;
   wire [0:tstag_width-1] 		     irq_tstag;
   wire 				     irq_tstag_v;
   

   wire 				     s2_ctxt_add_ack_v;
   wire 				     s1_tstag_issue_v;
   wire [0:tstag_width-1] 		     s1_tstag_issue_id;
   wire [0:63] 				     s1_tstag_issue_d;


   wire 				     s1_timeout_v;
   wire [0:tstag_width-1] 		     s1_timeout_id;
 		     
   wire 				     s1_tscheck_v;
   wire 				     s1_tscheck_r;
   wire [0:tstag_width-1] 		     s1_tscheck_tstag;
   wire [0:ctxtid_width-1] 		     s1_tscheck_ctxt;

   wire 				     s1_tscheck_rsp_v;
   wire 				     s1_tscheck_rsp_r;
   wire 				     s1_tscheck_rsp_ok;
   

   // read, write, intr, retry, gets, puts
   localparam dma_rm_err_width = 4+ngets+nputs;

   // write buffer and tag per channel + afu tag + tstag
   localparam afu_rm_err_width = (channels * 2) + 2;
   
   localparam rm_err_width = afu_rm_err_width + dma_rm_err_width;
   wire [0:rm_err_width-1] 		     s1_rm_err;


   // parity/fatal error handling
   wire                                      checker_enable;       
   wire                                      checker_reset;
   wire                               [0:63] checker_data;
   wire                                      fatal_error;
   wire                                      fatal_error_dbg;
   
   wire 				     checker_error = perror_total | (|i_fc_port_fatal_error) | s1_errinj[0];

   // stop AFU on fatal error
   //   wire 				     s0_app_done = (i_checker_error & o_checker_enable) | s1_errinj[0];   // original
   wire 				     s0_app_done = checker_error & checker_enable & ~fatal_error;
   wire                                      s0_fatal_error = ((checker_error & checker_enable) | fatal_error) & ~checker_reset;
   wire                                      s0_fatal_error_dbg = ((checker_error & ah_jrunning) | fatal_error_dbg) & ~checker_reset;
   base_vlat#(.width(1)) ifatal_error(.clk(clk),.reset(1'b0),.din(s0_fatal_error),.q(fatal_error));
   base_vlat#(.width(1)) ifatal_error_dbg(.clk(clk),.reset(1'b0),.din(s0_fatal_error_dbg),.q(fatal_error_dbg));


   wire [0:6] 				hld_perror;
   wire [0:6] 				hld_perror_msk = hld_perror & {~gbl_reg11[63],3'b111,~gbl_reg11[62],2'b11};
   wire                                 any_hld_perror_msk = |(hld_perror_msk);

   assign o_fc_fatal_error = fatal_error;  // freeze nvme ports
   assign checker_data = {fatal_error_dbg, fatal_error, i_fc_port_fatal_error, perror_total, hld_perror};  // dbg_reg1
   assign checker_enable = ~gbl_reg7[0] & ah_jrunning;

   // only reset checker with gbl_reg7 to avoid afu reset wiping out debug data
   assign checker_reset = gbl_reg7[8];


   wire 				     s2_ctxt_rst_v;
   wire [0:ctxtid_width-1] 		     s2_ctxt_rst_id;

   wire 				     s1_ctxt_rst_v;
   wire 				     s1_ctxt_rst_r;
   wire [0:ctxtid_width-1] 		     s1_ctxt_rst_id;
   
   wire [4:0] 				     dma_pipemon_v;
   wire [4:0] 				     dma_pipemon_r;
   localparam mmio_timeout_width=12;

   wire 				     s1_dma_bad_rsp_v;
   wire [0:127] 			     s1_dma_bad_rsp_d;
   wire [0:63] 				     s1_dma_status;
   wire [0:64*(ngets+nputs)-1] 		     s1_cnt_pend_d;
   wire 				     s1_cnt_rsp_miss;
   
   localparam cto_width=16;

   wire [0:43]          		     dma_dbg_cnt_inc;
   assign dbg_cnt_inc[25:39] = dma_dbg_cnt_inc[0:14];
//   assign dbg_cnt_inc[dbg_cnt_regs-29:dbg_cnt_regs-2] = dma_dbg_cnt_inc[15:42];
//   assign dbg_cnt_inc[99:126] = dma_dbg_cnt_inc[15:42];
   assign dbg_cnt_inc[99:122] = dma_dbg_cnt_inc[15:38];

//   assign dbg_cnt_inc[127] = dma_dbg_cnt_inc[43];

   wire [0:mmiobus_awidth-1] pc_mmioabus = mmiobus[0:mmiobus_awidth-1];
   wire [0:64]               pc_mmiodbus = mmiobus[mmiobus_awidth:mmiobus_width-1];
   wire 		       pc_mmval, pc_mmcfg, pc_mmrnw, pc_mmdw, pc_mmadpar; 
   wire [0:23] 		       pc_mmad;
   assign {pc_mmval, pc_mmcfg, pc_mmrnw, pc_mmdw, pc_mmad, pc_mmadpar} = pc_mmioabus;
 

   capi_parcheck#(.width(64)) pc_mmdata_pcheck(.clk(clk),.reset(reset),.i_v(s1_mmval & ~pc_mmrnw),.i_d(pc_mmiodbus[0:63]),.i_p(pc_mmiodbus[64]),.o_error(s1_perror[0]));
   capi_parcheck#(.width(24)) pc_mmad_pcheck(.clk(clk),.reset(reset),.i_v(pc_mmval),.i_d(pc_mmad),.i_p(pc_mmadpar),.o_error(s1_perror[1]));
   base_vlat_sr#(.width(7)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(7'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror_msk),.q(o_perror[2]));

   wire [0:76]     dma_top_s1_perror;
   wire [0:ctxtid_width+7]            dbg_dma_retry_s0               ;
   (* mark_debug = "true" *)
   wire                              error_status_hld;
   wire freeze_on_error;   
   wire [0:(((5+8+7)*3)+4)*64-1] dma_latency;

   (* dont_touch = "yes" *)
   reg  freeze_on_error_q = 1'b0;
   always @(posedge ha_pclock) freeze_on_error_q <= freeze_on_error_q;   
 
   wire xlate_start;       
   wire xlate_end;
   wire [0:6] xlate_ctag;
   wire [0:6] xlate_rtag;
   wire [0:63] xlate_ea;

   capi_dma_mc_top_plus#
     (
      .mmio_timeout_width(mmio_timeout_width),
      .mmio_base(mmioaddr_perferr_base),
      .puts(nputs),.gets(ngets),.cgets(0),.cputs(0),.rc_width(dma_rc_width),
      .ignore_tstag_inv({{channels{1'b0}},2'b11}),
      .ssize_width(ssize_width),.data_latency(data_latency),.ctxtid_width(ctxtid_width),.tstag_width(tstag_width),
      .afuerr_width(8),
      .ctag_width(ctag_width),.pea_width(pea_width),.cnt_rsp_width(cnt_rsp_width),
      .cto_width(cto_width),
      .psl_rsp_cinv(psl_rsp_cinv)
      ) idma_plus
       (.clk(clk),.i_reset(i_reset),.o_reset(reset),
//`include "psl_io_bindings.inc"
	.o_rm_err(s1_rm_err[afu_rm_err_width:afu_rm_err_width+dma_rm_err_width-1]),
	.o_perror(o_perror[3:44]),       
	.o_dbg_cnt_inc(dma_dbg_cnt_inc),
	.o_pipemon_v(dma_pipemon_v),
	.o_pipemon_r(dma_pipemon_r),
	.o_bad_rsp_v(s1_dma_bad_rsp_v),
	.o_bad_rsp_d(s1_dma_bad_rsp_d),
	.o_status(s1_dma_status),
	.o_cnt_pend_d(s1_cnt_pend_d),
	.i_cont_timeout(gbl_reg9[cto_width-1:0]),
	.i_disable(s1_afu_disable),
	.i_ah_cabt(gbl_reg7[61:63]),
	.i_paren(gbl_reg7[9]),
	.i_cfg_ctrm_wait(gbl_reg7[60]),
	.o_ctxt_upd_d(s1_ctxt_upd_d),   // parity checked in dma_top kch
	.o_ctxt_add_v(s1_ctxt_add_v),
	.o_ctxt_rmv_v(s1_ctxt_rmv_v),
	.o_ctxt_trm_v(s1_ctxt_trm_v),
	.i_ctxt_add_ack_v(s2_ctxt_add_ack_v),
	.i_ctxt_rmv_ack_v(s1_ctxt_rmv_v),
	.i_ctxt_trm_ack_v(s1_ctxt_trm_v),
	.i_ctxt_rst_v(s1_ctxt_rst_v),
	.i_ctxt_rst_r(s1_ctxt_rst_r),
	.i_ctxt_rst_id(s1_ctxt_rst_id),
	.o_ctxt_rst_v(s2_ctxt_rst_v),.o_ctxt_rst_id(s2_ctxt_rst_id),
	.i_cnt_rsp_v(s1_cnt_rsp_v),.i_cnt_rsp_d(s1_cnt_rsp_d),.o_cnt_rsp_miss(s1_cnt_rsp_miss),
	
	.i_mmio_timeout_d(12'd230),
	
	.i_tstag_issue_v(s1_tstag_issue_v),
	.i_tstag_issue_id(s1_tstag_issue_id),
	.i_tstag_issue_d(s1_tstag_issue_d),

	.i_tstag_inv_v(s1_timeout_v),
	.i_tstag_inv_id(s1_timeout_id),

	.i_tscheck_v(s1_tscheck_v),
	.i_tscheck_r(s1_tscheck_r),
	.i_tscheck_tstag(s1_tscheck_tstag),
	.i_tscheck_ctxt(s1_tscheck_ctxt),
	.o_tscheck_v(s1_tscheck_rsp_v),
	.o_tscheck_r(s1_tscheck_rsp_r),
	.o_tscheck_ok(s1_tscheck_rsp_ok),

	.get_v(get_addr_v),
	.get_r(get_addr_r),
	.get_d_addr(get_addr_d_ea),
	.get_d_size(get_addr_d_size),
	.get_d_ctxt(get_addr_d_ctxt),
	.get_d_tstag(get_addr_d_tstag),
	.get_data_r(get_data_r),
	.get_data_v(get_data_v),
	.get_data_d(get_data_d),
	.get_data_c(get_data_c),
	.get_data_e(get_data_e),
	.get_data_rc(get_data_rc),
	.get_data_bcnt(),

	.put_addr_r(put_addr_r),
	.put_addr_v(put_addr_v),
	.put_addr_d_ea(put_addr_d_ea),
	.put_addr_d_ctxt(put_addr_d_ctxt),
	.put_addr_d_tstag(put_addr_d_tstag),
	.put_data_r(put_data_r),
	.put_data_v(put_data_v),
	.put_data_d(put_data_d),
	.put_data_e(put_data_e),
	.put_data_c(put_data_c),
	.put_data_f(put_data_f),
	.put_done_v(put_done_v),
	.put_done_r(put_done_r),
	.put_done_rc(put_done_rc),
	.put_done_bcnt(),
	//	.put_done_rc(),

	.i_mmdata(s2_mmdata_in),
	.i_mmack(s2_mmack),
	.i_irq_src({{11-msinum_width{1'b0}},irq_src}),
	.i_irq_ctxt(irq_ctxt),
	.i_irq_tstag(irq_tstag),
	.i_irq_tstag_v(irq_tstag_v),
	.i_irq_v(irq_v),
	.i_irq_r(irq_r),
	.i_app_done(s0_app_done),
        .i_fatal_error(fatal_error),
	.i_app_error(8'd01),
	.o_intr_done(),
	.o_mmiobus(mmiobus),
        .i_perror_total(perror_total),
        .o_dbg_dma_retry_s0(dbg_dma_retry_s0),
        .o_s1_perror(dma_top_s1_perror),
        .i_dma_retry_msk_pe025(gbl_reg11[58]), 
        .i_dma_retry_msk_pe34(gbl_reg11[59]),
        .i_ah_cch_msk_pe(gbl_reg11[60]),

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
       .ah_jyield( ah_jyield ),
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
//       .ha_croom( 8'h0F ),    // temp reduction of croom to 16 for lab debug

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

       .hd0_sent_utag_valid_psl(hd0_sent_utag_valid), 
       .hd0_sent_utag_psl(hd0_sent_utag), 
       .hd0_sent_utag_sts_psl(hd0_sent_utag_sts), 

       .hd0_cpl_valid(hd0_cpl_valid),
       .hd0_cpl_utag(hd0_cpl_utag),
       .hd0_cpl_type(hd0_cpl_type),
       .hd0_cpl_laddr(hd0_cpl_laddr),
       .hd0_cpl_byte_count(hd0_cpl_byte_count),
       .hd0_cpl_size(hd0_cpl_size),
       .hd0_cpl_data(hd0_cpl_data),
       .i_error_status_hld(freeze_on_error & freeze_on_error_q),  // temp remove kchh when done with debug
       .o_latency_d(dma_latency),
       .i_drop_wrt_pckts(gbl_reg7[2]),
       .i_gate_sid(gbl_reg7[3]),
       .o_xlate_start(xlate_start),       
       .o_xlate_end(xlate_end),
       .o_xlate_ctag(xlate_ctag),
       .o_xlate_rtag(xlate_rtag),
       .o_xlate_ea(xlate_ea),
       .i_reset_lat_cntrs(gbl_reg7[6])

        );

   assign o_reset = reset;

// xlate debug logic

   wire [0:31] r1_lr_timestamp, r2_lr_timestamp, s1_lr_timestamp, s2_lr_timestamp ;
   wire [0:63] r1_xlate_ea, r2_xlate_ea;
   wire        s1_xlate_end, s2_xlate_end;
   wire        s1_xlate_read,s2_xlate_read;
   base_mem#(.addr_width(7),.width(32)) xlate_mem_tag
     (.clk(clk),
      .we(xlate_start), .wa(xlate_ctag),.wd(lr_timestamp), 
      .re(1'b1),        .ra(xlate_rtag),.rd(r1_lr_timestamp) 
      );
   base_mem#(.addr_width(7),.width(64)) xlate_mem_adr
     (.clk(clk),
      .we(xlate_start), .wa(xlate_ctag),.wd(xlate_ea), 
      .re(1'b1),        .ra(xlate_rtag),.rd(r1_xlate_ea) 
      );

   base_vlat#(.width(34)) ir_ts(.clk(clk),.reset(reset),.din({xlate_end,lr_timestamp,xlate_rtag[0]}),.q({s1_xlate_end,s1_lr_timestamp,s1_xlate_read}));
   base_vlat#(.width(2)) ir2_ts(.clk(clk),.reset(reset),.din({s1_xlate_end,s1_xlate_read}),.q({s2_xlate_end,s2_xlate_read}));
   base_vlat#(.width(64)) ir3_ts(.clk(clk),.reset(reset),.din({r1_xlate_ea}),.q({r2_xlate_ea}));
   
   wire [0:31] xlate_latency = s1_lr_timestamp - r1_lr_timestamp ;
   wire [0:31] s1_xlate_latency;
   base_vlat#(.width(32)) ixlate_ts(.clk(clk),.reset(reset),.din(xlate_latency),.q(s1_xlate_latency));
   wire xlate_rd_lt_32 = (s1_xlate_latency < 32'd32) & s2_xlate_read & s2_xlate_end;       
   wire xlate_rd_lt_512 = (s1_xlate_latency < 32'd512) & s2_xlate_read & ~xlate_rd_lt_32  & s2_xlate_end;       
   wire xlate_rd_lt_4K = (s1_xlate_latency < 32'd4096) & s2_xlate_read & ~xlate_rd_lt_512  & ~xlate_rd_lt_32 & s2_xlate_end ;       
   wire xlate_rd_lt_16K = (s1_xlate_latency < 32'd16384) & s2_xlate_read & ~xlate_rd_lt_512  & ~xlate_rd_lt_32 & s2_xlate_end ;       
   wire xlate_rd_gt_16K = s2_xlate_read & ~xlate_rd_lt_16K & ~xlate_rd_lt_4K & ~xlate_rd_lt_512  & ~xlate_rd_lt_32 & s2_xlate_end;       
   wire xlate_wrt_lt_32 = (s1_xlate_latency < 32'd32) & ~s2_xlate_read & s2_xlate_end;       
   wire xlate_wrt_lt_512 = (s1_xlate_latency < 32'd512) & ~s2_xlate_read  & ~xlate_wrt_lt_32 & s2_xlate_end;       
   wire xlate_wrt_lt_4K = (s1_xlate_latency < 32'd4096) & ~s2_xlate_read & ~xlate_wrt_lt_512  & ~xlate_wrt_lt_32  & s2_xlate_end ;       
   wire xlate_wrt_lt_16K = (s1_xlate_latency < 32'd16384) & ~s2_xlate_read & ~xlate_wrt_lt_4K & ~xlate_wrt_lt_512  & ~xlate_wrt_lt_32 & s2_xlate_end; 
   wire xlate_wrt_gt_16K =  ~s2_xlate_read & ~xlate_wrt_lt_16K & ~xlate_wrt_lt_4K & ~xlate_wrt_lt_512  & ~xlate_wrt_lt_32 & s2_xlate_end; 
   wire [0:31] xlate_rd_max;
   wire update_rd_max = (xlate_rd_max < s1_xlate_latency) & s2_xlate_read  & s2_xlate_end;
   base_vlat_en#(.width(32)) ird_xlat_max (.clk(clk),.reset(reset),.din(s1_xlate_latency),.q(xlate_rd_max),.enable(update_rd_max));
   wire [0:31] xlate_wrt_max;
   wire update_wrt_max = (xlate_wrt_max < s1_xlate_latency) & ~s2_xlate_read & s2_xlate_end;
   base_vlat_en#(.width(32)) iwrt_xlat_max (.clk(clk),.reset(reset),.din(s1_xlate_latency),.q(xlate_wrt_max),.enable(update_wrt_max));

//   assign dbg_cnt_inc[123:127] = {xlate_wrt_lt_32,xlate_wrt_lt_512,xlate_wrt_lt_4K,xlate_wrt_lt_16K,xlate_wrt_gt_16K};

 
   
        



   localparam flgs_width = 5;
   wire 				     s1_cmd_v, s1_cmd_r;

   wire [0:tag_width-1] 		     s1_cmd_tag;
   wire [0:ctxtid_width-1]                   s1_cmd_rcb_ctxt;
   wire                                      s1_cmd_rcb_ec;   // endian control
   wire [0:ea_width-1]                       s1_cmd_rcb_ea;
   wire [0:63]                               s1_cmd_rcb_timestamp;
   wire                                      s1_cmd_rcb_hp;
   wire [0:rh_width-1]                       s1_cmd_rh;
   wire [0:lunid_width_w_par-1]                      s1_cmd_lun;
   wire [0:flgs_width-1]                     s1_cmd_flgs;
   
   wire [0:datalen_width_w_par-1] 	     s1_cmd_data_len;     // added w_par kch 
   wire [0:ctxtid_width-1] 		     s1_cmd_data_ctxt;
   wire [0:ea_width-1] 			     s1_cmd_data_ea;
   wire [0:msinum_width-1] 		     s1_cmd_msinum;
   wire [0:rrqnum_width-1] 		     s1_cmd_rrqnum;
   wire [0:cdb_width_w_par-1] 		     s1_cmd_cdb;   // added w_par kch 
   wire [0:lba_width-1] 		     s1_cmd_lba;
   wire [0:channels-1] 			     s1_cmd_portmsk;
   wire [0:afu_rc_width-1] 		     s1_cmd_rc;
   wire [0:afu_erc_width-1] 		     s1_cmd_erc;
   wire 				     s1_cmd_ok;
   wire [0:syncid_width-1] 		     s1_cmd_syncid;
   wire 				     s1_cmd_nocmpl;

   wire 				     s1_cmpl_v;
   wire [0:syncid_width-1] 		     s1_cmpl_syncid;
   wire [0:tag_width-1] 		     s1_cmpl_tag;


   localparam stall_counters = 13+channels;
   wire [0:stall_counters-1] 		     stallcount_v, stallcount_r;
   wire 				     trk0_v;
   wire [0:tag_width-1] 		     trk0_tag;
   wire [0:63] 				     trk0_ts;


   wire [0:ctxtid_width-2] 		     croom_wa;   // no parity kch ???
   wire [0:croom_width-1] 		     croom_wd;
   wire 				     croom_we;
   wire 				     s1_croom_err_v;
   wire 				     s1_croom_err_r;
   wire [0:ctxtid_width-1] 		     s1_croom_err_ctxt;




   wire 				     s1_to_v, s1_to_r;
   wire [0:1] 				     s1_to_flg;
   wire [0:15] 				     s1_to_d;
   wire [0:tag_width-1] 		     s1_to_tag;
   wire [0:63] 				     s1_to_ts;
   wire 				     s1_to_sync;
   wire 				     s1_to_ok;
   
   
   
   wire 				     s1_cap_wr_v;
   wire [0:ctxtid_width-1] 		     s1_cap_wr_ctxt;
   wire [0:ctxtcap_width-1] 		     s1_cap_wr_d;

   wire [0:31]                               s1_cmd_dbg_reg;  
   wire [63:0] 				     s1a_pipemon_v;
   wire [63:0] 				     s1a_pipemon_r;

   wire [63:0] 				     s1b_pipemon_v;
   wire [63:0] 				     s1b_pipemon_r;

   wire [21:0] 				     cmd_pipemon_v, cmd_pipemon_r;


   wire 				     s1_ec_set, s1_ec_rst;
   wire [0:ctxtid_width-1] 		     s1_ec_id;

   wire 				     s4_abrt_v, s4_abrt_r;
   wire [0:tag_width-1] 		     s4_abrt_tag;
   wire [0:chnlid_width-1] 		     s4_abrt_chnl;
   
   wire [0:ctxtid_width-1] 		     s4_abrt_ctxt;
   wire 				     s4_abrt_ec;
   wire [0:ea_width-1] 			     s4_abrt_ea;
   wire [0:msinum_width-1] 		     s4_abrt_msinum;
   wire [0:syncid_width-1] 		     s4_abrt_syncid;
   wire 				     s4_abrt_sule;
   wire 				     s4_abrt_rnw;
   wire                                      cmpl_error_hld;
   wire                                      tag_error_hld;
   wire                                      no_afu_tags;
   wire                                      allocate_afu_tag,free_afu_tag;
   wire retry_v,retry_r;
   wire                                      retry_cmd_v,retry_cmd_r;
   wire [0:(64+65+10)-1]                               retry_cmd_d;
   wire                                      reset_afu_cmd_tag_v,reset_afu_cmd_tag_r;
   wire [0:9]                                reset_afu_cmd_tag;
   wire                                      alloc_hp_cmd,cmd_hp_cmd;
   wire [0:10]                                alloc_hp_cmd_d,cmd_hp_cmd_d;
   wire                                      dec_croom_v,dec_croom_r;
   wire [0:9]                                croom_ctxt; 
   wire [0:3*64-1]                           arrin_fifo_latency;
   wire [0:63]                               arrin_cycles;
   wire                                      retry_threshold;


   ktms_afu_cmd#
     (.mmiobus_width(mmiobus_width),
      .mmiobus_awidth(mmiobus_awidth),
      .channels(channels),
      .syncid_width(syncid_width),
      .ctxtid_width(ctxtid_width),
      .dma_rc_width(dma_rc_width),
      .afu_rc_width(afu_rc_width),
      .afu_erc_width(afu_erc_width),
      .ctxtcap_width(ctxtcap_width),
      .ea_width(ea_width),
      .lba_width(lba_width),
      .rh_width(rh_width),
      .lunid_width(lunid_width),
      .datalen_width(datalen_width),
      .ioadllen_width(16),
      .msinum_width(msinum_width),
      .rrqnum_width(rrqnum_width),
      .cdb_width(cdb_width),
      .la_width(la_width),
      .rrin_addr(mmioaddr_rrin),
      .flow_ctrl_addr(mmioaddr_flow_ctrl),
      .tag_width(tag_width),
      .tstag_width(tag_width),
      .ssize_width(ssize_width),
      .psl_rsp_paged(psl_rsp_paged),
      .psl_rsp_addr(psl_rsp_addr),
      .afuerr_rcb_dma('h40),
      .afuerr_ok(0)
      ) icmd
       (.clk(clk),.reset(reset),
	.o_rm_err(s1_rm_err[0:1]),
	.i_timestamp(cycle_count),
	.i_rrin_to(gbl_reg8),
	.i_mmiobus(mmiobus),

	.i_ec_set(s1_ec_set),
	.i_ec_rst(s1_ec_rst),
	.i_ec_id(s1_ec_id),  //parity cheecked in afu_int kch 

	.i_cap_wr_v(s1_cap_wr_v),
	.i_cap_wr_ctxt(s1_cap_wr_ctxt),
	.i_cap_wr_d(s1_cap_wr_d),

	.i_errinj_croom(s1_errinj[63]),
	.i_errinj_rcb_fault(s1_errinj[62]),
	.i_errinj_rcb_paged(s1_errinj[61]),

	.o_tstag_issue_v(s1_tstag_issue_v),
	.o_tstag_issue_id(s1_tstag_issue_id),
	.o_tstag_issue_d(s1_tstag_issue_d),

        .o_croom_we(croom_we),
        .o_croom_wa(croom_wa),
        .o_croom_wd(croom_wd),
        .i_croom_max(gbl_reg7[16:23]),

        .o_croom_err_v(s1_croom_err_v),
        .o_croom_err_r(s1_croom_err_r),
        .o_croom_err_ctxt(s1_croom_err_ctxt),

        .o_to_v(s1_to_v),.o_to_r(s1_to_r),.o_to_d(s1_to_d),.o_to_flg(s1_to_flg),.o_to_tag(s1_to_tag),.o_to_ts(s1_to_ts), .o_to_sync(s1_to_sync),.o_to_ok(s1_to_ok),

	.o_abrt_v(s4_abrt_v),.o_abrt_r(s4_abrt_r),
	.o_abrt_tag(s4_abrt_tag), .o_abrt_ctxt(s4_abrt_ctxt),.o_abrt_ec(s4_abrt_ec),.o_abrt_ea(s4_abrt_ea),.o_abrt_msinum(s4_abrt_msinum),.o_abrt_syncid(s4_abrt_syncid),.o_abrt_sule(s4_abrt_sule),.o_abrt_rnw(s4_abrt_rnw),
	
	.i_ctxt_add_v(s1_ctxt_add_v),
	.i_ctxt_add_d(s1_ctxt_upd_d),
	.o_ctxt_add_ack_v(s2_ctxt_add_ack_v),
	.o_get_addr_v(get_addr_v[channels]),
	.o_get_addr_r(get_addr_r[channels]),
	.o_get_addr_ea(get_addr_d_ea[ea_width*channels:ea_width*(channels+1)-1]),
	.o_get_addr_tstag(get_addr_d_tstag[tstag_width*channels:tstag_width*(channels+1)-1]),
	.o_get_addr_ctxt(get_addr_d_ctxt[ctxtid_width*channels:ctxtid_width*(channels+1)-1]),
	.o_get_addr_size(get_addr_d_size[ssize_width*channels:ssize_width*(channels+1)-1]),
	.i_get_data_v(get_data_v[channels]),
	.i_get_data_r(get_data_r[channels]),
	.i_get_data_d(get_data_d[130*channels:130*(channels+1)-1]),
	.i_get_data_e(get_data_e[channels]),
	.i_get_data_rc(get_data_rc[dma_rc_width*channels:dma_rc_width*(channels+1)-1]),

	// debug and performance
	.o_trk0_v(trk0_v),
	.o_trk0_tag(trk0_tag),
	.o_trk0_timestamp(trk0_ts),
	.o_cmd_dropped(dbg_cnt_inc[24]),
	.o_dbg_cnt_inc(dbg_cnt_inc[21:23]),
	.o_dbg_reg(s1_cmd_dbg_reg),
	.o_pipemon_v(cmd_pipemon_v),
	.o_pipemon_r(cmd_pipemon_r),
	.o_sc_v(stallcount_v[0]),
	.o_sc_r(stallcount_r[0]),

	.o_v(s1_cmd_v),
        .o_r(s1_cmd_r),
        .o_flgs(s1_cmd_flgs),

        .o_tag(s1_cmd_tag),    // has parity kch 
        .o_syncid(s1_cmd_syncid),
        .o_rcb_ctxt(s1_cmd_rcb_ctxt),
        .o_rcb_ec(s1_cmd_rcb_ec),
        .o_rcb_ea(s1_cmd_rcb_ea),
        .o_rcb_timestamp(s1_cmd_rcb_timestamp),
        .o_rcb_hp(s1_cmd_rcb_hp),
        .o_rh(s1_cmd_rh),
        .o_lunid(s1_cmd_lun),
        .o_lba(s1_cmd_lba),
	.o_ioadllen(),
	.o_data_len(s1_cmd_data_len),
	.o_data_ctxt(s1_cmd_data_ctxt),
	.o_data_ea(s1_cmd_data_ea),    //has parity kch 
	.o_msinum(s1_cmd_msinum),
	.o_rrq(s1_cmd_rrqnum),
	.o_cdb(s1_cmd_cdb),
	.o_portmsk(s1_cmd_portmsk),
	.o_rc(s1_cmd_rc),
	.o_erc(s1_cmd_erc),
	.o_ok(s1_cmd_ok),
	.o_nocmpl(s1_cmd_nocmpl),

	.i_cmpl_v(s1_cmpl_v),
	.i_cmpl_tag(s1_cmpl_tag),
	.i_cmpl_syncid(s1_cmpl_syncid),
        .o_perror(o_perror[45:48]),    // addded o_perror kch 
        .o_cmpl_error_hld(cmpl_error_hld),
        .o_tag_error_hld(tag_error_hld),
        .o_allocate_afu_tag(allocate_afu_tag),.o_free_afu_tag(free_afu_tag),.o_no_afu_tags(no_afu_tags),.i_threshold_zero(gbl_reg7[4]),
        .i_retry_cmd_v(retry_cmd_v),.i_retry_cmd_r(retry_cmd_r),.i_retry_cmd_d(retry_cmd_d),
        .i_reset_afu_cmd_tag_v(reset_afu_cmd_tag_v),.i_reset_afu_cmd_tag_r(reset_afu_cmd_tag_r),.i_reset_afu_cmd_tag(reset_afu_cmd_tag),
        .o_arrin_cycles(arrin_cycles),.o_arrin_fifo_latency(arrin_fifo_latency),.i_arrin_cnt_reset(gbl_reg7[6]),
        .i_retry_threshold(retry_threshold)
        

        );

    assign dbg_cnt_inc[81] = no_afu_tags;
  
   wire [0:63] afu_tag_sum ;
   wire [0:63] afu_tag_complete;
   wire [0:9] afu_tag_active;

   nvme_perf_count#(.sum_width(64),.active_width(10)) iafu_tag_perf (.reset(reset),.clk(clk),
                                                                  .incr(allocate_afu_tag), .decr(free_afu_tag), .clr(gbl_reg7[6]),
                                                                  .active_cnt(afu_tag_active), .complete_cnt(afu_tag_complete), .sum(afu_tag_sum), .clr_sum(gbl_reg7[6]));
   wire [0:63] afu_tag_active_cycles ;
   wire [0:63] afu_tag_active_cycles_in = gbl_reg7[6] ? 64'b0 : afu_tag_active_cycles+64'd1;
   wire afu_tag_active_ne_0 = (afu_tag_active != 10'b0000000000);
   wire afu_tag_active_cnt_enable = afu_tag_active_ne_0 | gbl_reg7[6];
   base_vlat_en#(.width(64)) tag_a_cycles(.clk(clk),.reset(reset),.din(afu_tag_active_cycles_in),.q(afu_tag_active_cycles),.enable(afu_tag_active_ne_0));

   wire afu_tag_lt_25 = (afu_tag_active < 10'd25) & afu_tag_active_ne_0; 
   wire afu_tag_lt_50 = (afu_tag_active < 10'd50) & ~(afu_tag_active < 10'd25) & afu_tag_active_ne_0;      
   wire afu_tag_lt_75 = (afu_tag_active < 10'd75) & ~(afu_tag_active < 10'd50) & ~(afu_tag_active < 10'd25) & afu_tag_active_ne_0;      
   wire afu_tag_lt_100 = (afu_tag_active < 10'd100) & ~(afu_tag_active < 10'd75) & ~(afu_tag_active < 10'd50) & ~(afu_tag_active < 10'd25) & afu_tag_active_ne_0;      
   wire afu_tag_gt_100 = ~(afu_tag_active < 10'd100) & ~(afu_tag_active < 10'd75) & ~(afu_tag_active < 10'd50) & ~(afu_tag_active < 10'd25) & afu_tag_active_ne_0; 

   assign dbg_cnt_inc[123:127] = {afu_tag_lt_25,afu_tag_lt_50,afu_tag_lt_75,afu_tag_lt_100,afu_tag_gt_100};

     
   wire [0:4*64-1] afu_tag_latency = {afu_tag_sum,afu_tag_complete,54'b0,afu_tag_active,afu_tag_active_cycles}; 

   // assign o_perror[57] = 1'b0;   // fixit this kch renumber o_perror when done with make

   capi_parcheck#(.width(9)) s1_cmd_tag_pcheck(.clk(clk),.reset(reset),.i_v(s1_cmd_v),.i_d(s1_cmd_tag[0:tag_width-2]),.i_p(s1_cmd_tag[tag_width-1]),.o_error(s1_perror[6]));

   // debug count 0 = command fetches,
   // debug count 1 = commands received
   assign dbg_cnt_inc[0] = get_addr_v[channels] & get_addr_r[channels];
   assign dbg_cnt_inc[1] = s1_cmd_v & s1_cmd_r;

   wire 				     s2_cmd_v, s2_cmd_r;
   wire [0:cdb_width_w_par-1] 		     s2_cmd_cdb;
   wire [0:lba_width-1] 		     s2_cmd_lba;
   wire [0:lunid_width_w_par-1] 		     s2_cmd_lun;
   wire [0:ea_width-1] 			     s2_cmd_data_ea;
   wire [0:ctxtid_width-1] 		     s2_cmd_data_ctxt;
   wire [0:tag_width-1] 		     s2_cmd_tag;
   wire [0:datalen_width_w_par-1]	     s2_cmd_data_len;   // w_par kch 
   wire [0:afu_rc_width-1] 		     s2_cmd_rc;
   wire [0:afu_erc_width-1] 		     s2_cmd_erc;
   wire [0:channels-1] 			     s2_cmd_portmsk;
   wire [0:lidx_width-1] 		     s2_cmd_lidx;
   wire 				     s2_cmd_ok;
   wire 				     s2_cmd_plun;
   wire [0:flgs_width-1] 		     s2_cmd_flgs;


   wire                                      s1a_cmd_v, s1a_cmd_r;
   base_afilter is1a_fltr(.i_v(s1_cmd_v),.i_r(s1_cmd_r),.o_v(s1a_cmd_v),.o_r(s1a_cmd_r),.en(~s1_cmd_nocmpl));
   assign dbg_cnt_inc[50] = s1a_cmd_v & s1a_cmd_r;

   wire                                      trk3_v;
   wire [0:tag_width-1]                      trk3_tag;
   wire [0:47] 				     trk3_d;
   wire [0:7]                                s1_vrh_erc_hld;
 				     
   ktms_afu_rht#
     (.mmio_cpc_addr(mmioaddr_cpc),.mmiobus_width(mmiobus_width),
      .ctxtid_width(ctxtid_width),.rh_width(rh_width),.lba_width(lba_width),
      .rc_width(afu_rc_width),.erc_width(afu_erc_width),.dma_rc_width(dma_rc_width),.tstag_width(tstag_width),
      .dma_rc_paged(psl_rsp_paged),
      .dma_rc_addr(psl_rsp_addr),
      
      .lunid_width(lunid_width),.lidx_width(lidx_width),
      .ea_width(ea_width),.channels(channels),.ssize_width(ssize_width),
      .aux_width(flgs_width-1+tag_width+datalen_width_w_par+ea_width+cdb_width_w_par+ctxtid_width)  // added w_par kch
      ) irht
       (
	.clk(clk),.reset(reset),
	.i_ec_set(s1_ec_set),
	.i_ec_rst(s1_ec_rst),
	.i_ec_id(s1_ec_id),   //parity cheecked in afu_int kch 

	.i_errinj(s1_errinj[47:50]),
	.i_ctxt_rst_v(s1_ctxt_rmv_v),.i_ctxt_rst_d(s1_ctxt_upd_d),
	.i_req_v(s1a_cmd_v),.i_req_r(s1a_cmd_r),
	.i_req_wnr(s1_cmd_flgs[4]),
	.i_req_rc(s1_cmd_rc),.i_req_erc(s1_cmd_erc),.i_req_ok(s1_cmd_ok),
	.i_mmiobus(mmiobus),
	.i_req_portmsk(s1_cmd_portmsk),
	.i_req_ctxt(s1_cmd_data_ctxt),
	.i_req_rh(s1_cmd_rh),
	.i_req_lba(s1_cmd_lba),
	.i_req_lunid(s1_cmd_lun),
	.i_req_vrh(s1_cmd_flgs[0]),
        .i_req_transfer_len(s1_cmd_cdb[10*8:14*8-1]),  
	.i_req_tstag(s1_cmd_tag),   //done kch 
	.i_req_aux({s1_cmd_flgs[1:flgs_width-1],s1_cmd_tag,s1_cmd_data_len,s1_cmd_data_ea,s1_cmd_cdb,s1_cmd_data_ctxt}),  
	.o_req_aux({s2_cmd_flgs[1:flgs_width-1],s2_cmd_tag,s2_cmd_data_len,s2_cmd_data_ea,s2_cmd_cdb,s2_cmd_data_ctxt}), 

	.o_trk_v(trk3_v),.o_trk_tag(trk3_tag),.o_trk_d(trk3_d),
	.o_sc_v(stallcount_v[1:3]),
	.o_sc_r(stallcount_r[1:3]),

	.o_req_v(s2_cmd_v),.o_req_r(s2_cmd_r),
	.o_req_ok(s2_cmd_ok),.o_req_rc(s2_cmd_rc),.o_req_erc(s2_cmd_erc),
	.o_req_lba(s2_cmd_lba),.o_req_lunid(s2_cmd_lun),.o_req_portmsk(s2_cmd_portmsk),.o_req_lidx(s2_cmd_lidx),.o_req_vrh(s2_cmd_flgs[0]), .o_req_plun(s2_cmd_plun),
	.o_get_addr_v(get_addr_v[channels+1:channels+2]),
	.o_get_addr_r(get_addr_r[channels+1:channels+2]),
	.o_get_addr_ea(get_addr_d_ea[ea_width*(channels+1):ea_width*(channels+3)-1]),                 // parity added kch
	.o_get_addr_tstag(get_addr_d_tstag[tstag_width*(channels+1):tstag_width*(channels+3)-1]),
	.o_get_addr_ctxt(get_addr_d_ctxt[ctxtid_width*(channels+1):ctxtid_width*(channels+3)-1]),  
	.o_get_addr_size(get_addr_d_size[ssize_width*(channels+1):ssize_width*(channels+3)-1]),
	.i_get_data_v(get_data_v[channels+1:channels+2]),
	.i_get_data_r(get_data_r[channels+1:channels+2]),
	.i_get_data_d(get_data_d[130*(channels+1):130*(channels+3)-1]),
	.i_get_data_e(get_data_e[channels+1:channels+2]),
	.i_get_data_rc(get_data_rc[dma_rc_width*(channels+1):dma_rc_width*(channels+3)-1]),
        .o_perror(o_perror[49:52]),   //added o_perror kch 
        .o_vrh_erc_hld(s1_vrh_erc_hld)
        );

   assign dbg_cnt_inc[51] = s2_cmd_v & s2_cmd_r;

   wire                                      s3_cmd_v, s3_cmd_r;
   wire                                      s3_cmd_ok;
   wire [0:afu_rc_width-1] 		     s3_cmd_rc;
   wire [0:afu_erc_width-1] 		     s3_cmd_erc;

   wire [0:lunid_width_w_par-1] 		     s3_cmd_lun;
   wire [0:fc_tag_width_w_par-1] 	     s3_cmd_fc_tag;   // added w_par kch
   wire [0:chnlid_width-1] 		     s3_cmd_chnl;
   wire [0:tag_width-1] 		     s3_cmd_afu_tag;
   wire [0:lidx_width-1] 		     s3_cmd_lidx;

   wire 				     s3_cmd_fc_tag_valid;

   wire 				     s2_rsp_v, s2_rsp_r;
   wire [0:chnlid_width-1] 		     s2_rsp_chnl;
   wire [0:fc_tag_width_w_par-1] 	     s2_rsp_fc_tag;    // added w_par kch 
   wire 				     s2_rsp_fc_tag_valid;
   wire 				     s2_rsp_nc; // no channel
   wire 				     s3_vrh;


   localparam cmd_aux_width = cdb_width_w_par+datalen_width_w_par+ctxtid_width+ea_width+flgs_width-1;
   wire [0:cmd_aux_width-1] 		     s3_cmd_aux;
   wire 				     s3_cmd_vrh;
   wire [0:cdb_width_w_par-1] 		     s2_cmd_cdb_out;   // added w_par kch 
   wire 				     s2_cmd_vrh = s2_cmd_flgs[0];

   capi_parcheck#(.width(64)) s2_cmd_cdb_pcheck0(.clk(clk),.reset(reset),.i_v(s2_cmd_v),.i_d(s2_cmd_cdb[0:63]),.i_p(s2_cmd_cdb[128]),.o_error(s1_perror[2]));
   capi_parcheck#(.width(64)) s2_cmd_cdb_pcheck1(.clk(clk),.reset(reset),.i_v(s2_cmd_v),.i_d(s2_cmd_cdb[64:127]),.i_p(s2_cmd_cdb[129]),.o_error(s1_perror[3]));

   assign s2_cmd_cdb_out [0:2*8-1] = s2_cmd_cdb[0:2*8-1];
   assign s2_cmd_cdb_out [2*8:(10*8)-lba_width-1]      = s2_cmd_vrh ? {63-lba_width{1'b0}} : s2_cmd_cdb[2*8:(10*8)-lba_width-1];
   assign s2_cmd_cdb_out [(10*8)-lba_width : (10*8)-1] = s2_cmd_vrh ? s2_cmd_lba :          s2_cmd_cdb [(10*8)-lba_width : (10*8)-1];
   assign s2_cmd_cdb_out [10*8:cdb_width-1]            = s2_cmd_cdb[10*8:cdb_width-1];

   capi_parity_gen#(.dwidth(64),.width(1)) s2_cmd_cdb_out_pgen0(.i_d(s2_cmd_cdb_out[0:63]),.o_d(s2_cmd_cdb_out[128]));
   capi_parity_gen#(.dwidth(64),.width(1)) s2_cmd_cdb_out_pgen1(.i_d(s2_cmd_cdb_out[64:127]),.o_d(s2_cmd_cdb_out[129]));

   wire [0:channels-1]  allocate_fc_tag,free_fc_tag,fc_channel_stall;
   wire [0:ctxtid_width-1]           s2_retry_rcb_ctxt;
   wire [0:ea_width-1]               s2_retry_rcb_ea;
   wire                              s2_retry_rcb_hp;
   wire [0:63]                       s2_retry_rcb_timestamp;
   wire [0:127]                       retried_cmd_cnt;
   wire [0:16]                        alloc_dbg_cnt_inc;

   ktms_chnl_alloc#(.channels(4),.rc_width(afu_rc_width),.erc_width(afu_erc_width),
                    .fc_tag_width(fc_tag_width_w_par),.afu_tag_width(tag_width),.aux_width(1+lunid_width_w_par+lidx_width+cmd_aux_width)) ichnl_alloc    
     (.clk(clk),.reset(reset),
      .o_rm_err(s1_rm_err[2:channels+1]),
      .i_chnl_msk(gbl_reg6[64-channels:63]),
      .i_v(s2_cmd_v),.i_r(s2_cmd_r),.i_tag(s2_cmd_tag),.i_afu(s2_cmd_flgs[1]),.i_portmsk(s2_cmd_portmsk),.i_ok(s2_cmd_ok),.i_rc(s2_cmd_rc),.i_erc(s2_cmd_erc),.i_avail(i_fc_port_ready),
      .o_v(s3_cmd_v),.o_r(s3_cmd_r),.o_fc_tag_valid(s3_cmd_fc_tag_valid), .o_fc_tag(s3_cmd_fc_tag),.o_afu_tag(s3_cmd_afu_tag),.o_chnl(s3_cmd_chnl),.o_ok(s3_cmd_ok), .o_rc(s3_cmd_rc),.o_erc(s3_cmd_erc),
      .i_aux({s2_cmd_vrh & ~s2_cmd_plun,s2_cmd_lun,s2_cmd_lidx,s2_cmd_cdb_out,s2_cmd_data_len,s2_cmd_data_ctxt,s2_cmd_data_ea,s2_cmd_flgs[1:flgs_width-1]}), 
      .i_rcb_timestamp(s2_retry_rcb_timestamp),.i_rcb_ctxt(s2_retry_rcb_ctxt),.i_rcb_ea(s2_retry_rcb_ea),.i_rcb_hp(s2_retry_rcb_hp),
      .o_aux({s3_cmd_vrh,              s3_cmd_lun,s3_cmd_lidx,s3_cmd_aux}),
      .i_free_v(s2_rsp_v & s2_rsp_r & s2_rsp_fc_tag_valid),.i_free_chnl(s2_rsp_chnl),.i_free_tag(s2_rsp_fc_tag),.o_perror(o_perror[53:56]),
      .o_allocate_fc_tag(allocate_fc_tag),.o_free_fc_tag(free_fc_tag),.o_fc_channel_stall(fc_channel_stall),
      .o_retry_cmd_v(retry_cmd_v),.o_retry_cmd_r(retry_cmd_r),.o_retry_cmd_d(retry_cmd_d),
      .o_reset_afu_cmd_tag_v(reset_afu_cmd_tag_v),.o_reset_afu_cmd_tag_r(reset_afu_cmd_tag_r),.o_reset_afu_cmd_tag(reset_afu_cmd_tag),
      .o_retried_cmd_cnt(retried_cmd_cnt),.i_gate_retry(gbl_reg7[5]),.o_dbg_cnt_inc(alloc_dbg_cnt_inc),.o_retry_threshold(retry_threshold)

      );
  assign dbg_cnt_inc[52:53] = alloc_dbg_cnt_inc[0:1];
  assign dbg_cnt_inc[64:67] = alloc_dbg_cnt_inc[2:5];
  assign dbg_cnt_inc[78:80] = alloc_dbg_cnt_inc[6:8];
  assign dbg_cnt_inc[16:20] = alloc_dbg_cnt_inc[9:13];
  assign dbg_cnt_inc[35] = alloc_dbg_cnt_inc[14] ;
  assign dbg_cnt_inc[96:97] = alloc_dbg_cnt_inc[15:16] ;

   wire [0:63] fc_tag_ch0_sum ;
   wire [0:63] fc_tag_ch0_complete;
   wire [0:9] fc_tag_ch0_active;

   nvme_perf_count#(.sum_width(64),.active_width(10)) ifc_tag_ch0 (.reset(reset),.clk(clk),
                                                                  .incr(allocate_fc_tag[0]), .decr(free_fc_tag[0]), .clr(gbl_reg7[6]),
                                                                  .active_cnt(fc_tag_ch0_active), .complete_cnt(fc_tag_ch0_complete), .sum(fc_tag_ch0_sum), .clr_sum(gbl_reg7[6]));

   wire [0:63] fc_tag_ch1_sum ;
   wire [0:63] fc_tag_ch1_complete;
   wire [0:9] fc_tag_ch1_active;

   nvme_perf_count#(.sum_width(64),.active_width(10)) ifc_tag_ch1 (.reset(reset),.clk(clk),
                                                                  .incr(allocate_fc_tag[1]), .decr(free_fc_tag[1]), .clr(gbl_reg7[6]),
                                                                  .active_cnt(fc_tag_ch1_active), .complete_cnt(fc_tag_ch1_complete), .sum(fc_tag_ch1_sum), .clr_sum(gbl_reg7[6]));

   wire [0:63] fc_tag_ch2_sum ;
   wire [0:63] fc_tag_ch2_complete;
   wire [0:9] fc_tag_ch2_active;

   nvme_perf_count#(.sum_width(64),.active_width(10)) ifc_tag_ch2 (.reset(reset),.clk(clk),
                                                                  .incr(allocate_fc_tag[2]), .decr(free_fc_tag[2]), .clr(gbl_reg7[6]),
                                                                  .active_cnt(fc_tag_ch2_active), .complete_cnt(fc_tag_ch2_complete), .sum(fc_tag_ch2_sum), .clr_sum(gbl_reg7[6]));

   wire [0:63] fc_tag_ch3_sum ;
   wire [0:63] fc_tag_ch3_complete;
   wire [0:9] fc_tag_ch3_active;

   nvme_perf_count#(.sum_width(64),.active_width(10)) ifc_tag_ch3 (.reset(reset),.clk(clk),
                                                                  .incr(allocate_fc_tag[3]), .decr(free_fc_tag[3]), .clr(gbl_reg7[6]),
                                                                  .active_cnt(fc_tag_ch3_active), .complete_cnt(fc_tag_ch3_complete), .sum(fc_tag_ch3_sum), .clr_sum(gbl_reg7[6]));

   wire [0:64*4*3-1] fc_tag_latency = {fc_tag_ch0_sum,fc_tag_ch0_complete,54'b0,fc_tag_ch0_active,
                                     fc_tag_ch1_sum,fc_tag_ch1_complete,54'b0,fc_tag_ch1_active,
                                     fc_tag_ch2_sum,fc_tag_ch2_complete,54'b0,fc_tag_ch2_active,
                                     fc_tag_ch3_sum,fc_tag_ch3_complete,54'b0,fc_tag_ch3_active};

   assign dbg_cnt_inc[2]    = s3_cmd_v & s3_cmd_r;

   assign dbg_cnt_inc[92:95] = fc_channel_stall;

   capi_parcheck#(.width(64)) s3_cmd_aux_pcheck0(.clk(clk),.reset(reset),.i_v(s3_cmd_v),.i_d(s3_cmd_aux[0:63]),.i_p(s3_cmd_aux[128]),.o_error(s1_perror[4]));
   capi_parcheck#(.width(64)) s3_cmd_aux_pcheck1(.clk(clk),.reset(reset),.i_v(s3_cmd_v),.i_d(s3_cmd_aux[64:127]),.i_p(s3_cmd_aux[129]),.o_error(s1_perror[5]));

   wire [0:lba_width-1] 		     s3_cmd_lba = s3_cmd_aux[80-lba_width:80-1];  // todo possible parity check here kch 
   


   // insert stage here

   wire 				     s4_cmd_v, s4_cmd_r;
   wire 				     s4_cmd_ok;
   wire [0:afu_rc_width-1] 		     s4_cmd_rc;
   wire [0:afu_erc_width-1] 		     s4_cmd_erc;

   wire [0:cdb_width_w_par-1] 		     s4_cmd_cdb;    // added w_par kch 
   wire [0:lunid_width_w_par-1] 		     s4_cmd_lun;
   wire [0:ea_width-1] 			     s4_cmd_data_ea;
   wire [0:ctxtid_width-1] 		     s4_cmd_data_ctxt;
   wire 				     s4_cmd_fc_tag_valid;
   wire [0:fc_tag_width_w_par-1] 	     s4_cmd_fc_tag;   // added w_par kch 
   wire [0:chnlid_width-1] 		     s4_cmd_chnl;
   wire [0:tag_width-1] 		     s4_cmd_afu_tag;
   wire [0:datalen_width_w_par-1] 	     s4_cmd_data_len;   // added w_par kch 
   wire [1:flgs_width-1] 		     s4_cmd_flgs;

   wire [0:63] 				     s1_dbg_reg3;
   wire 				     s1_dbg_reg3_en;
   base_vlat_en#(.width(64)) is1_dbg_reg3(.clk(clk),.reset(reset),.din(cycle_count),.q(s1_dbg_reg3),.enable(s1_dbg_reg3_en));
   
   ktms_afu_ltbl#
     (.mmiobus_width(mmiobus_width),.mmio_addr(mmioaddr_luntbl),.idx_width(lidx_width),.portid_width(chnlid_width),.lunid_width(lunid_width_w_par),
      .aux_width(1+fc_tag_width_w_par+tag_width+chnlid_width+1+afu_rc_width+afu_erc_width+cmd_aux_width)) ilun_tbl    // added w_par twice  to cmd_aux_width kch 
       (.clk(clk),.reset(reset),
	.i_mmiobus(mmiobus),
	.i_v(s3_cmd_v),.i_r(s3_cmd_r),.i_port(s3_cmd_chnl),.i_idx(s3_cmd_lidx),.i_lunid(s3_cmd_lun),.i_vrh(s3_cmd_vrh),
	.i_aux({s3_cmd_fc_tag_valid,s3_cmd_fc_tag,s3_cmd_afu_tag,s3_cmd_chnl,s3_cmd_ok,s3_cmd_rc,s3_cmd_erc,s3_cmd_aux}),
	.o_mmio_rd_v(ltb_mmack),
	.o_mmio_rd_d(ltb_mmdata),
	.o_mmio_wr_v(s1_dbg_reg3_en),
	.o_v(s4_cmd_v),.o_r(s4_cmd_r),.o_lunid(s4_cmd_lun),
	.o_aux({s4_cmd_fc_tag_valid,s4_cmd_fc_tag,s4_cmd_afu_tag,s4_cmd_chnl,s4_cmd_ok,s4_cmd_rc,s4_cmd_erc,s4_cmd_cdb,s4_cmd_data_len,s4_cmd_data_ctxt,s4_cmd_data_ea,s4_cmd_flgs[1:flgs_width-1]}));
   

   wire [0:channels] 			     s4_cmda_v, s4_cmda_r;
   wire [0:channels] 			     s4_cmd_chnl_dec;

   // send to a channel if it's ok and not an afu command
   wire 				     s4_cmd_afu = s4_cmd_flgs[1];
   wire 				     s4_cmd_for_chnl = s4_cmd_ok & ~s4_cmd_afu;
   base_decode#(.enc_width(chnlid_width),.dec_width(channels)) ichnl_dec(.en(s4_cmd_for_chnl),.din(s4_cmd_chnl),.dout(s4_cmd_chnl_dec[0:channels-1]));
   assign s4_cmd_chnl_dec[channels] = ~s4_cmd_for_chnl;
   base_ademux#(.ways(channels+1)) icq3_demux(.i_v(s4_cmd_v),.i_r(s4_cmd_r),.o_v(s4_cmda_v),.o_r(s4_cmda_r),.sel(s4_cmd_chnl_dec));


   wire [0:channels] 			     s1_rsp_r, s1_rsp_v;
   wire [0:((channels)*rslt_width)-1] 	     s1_rsp_stat;
   wire [0:((channels)*fc_tag_width_w_par)-1]      s1_rsp_fc_tag;   // added w_par kch 
   
   // response from afu only commands or commands that hit an error before channel allocation
   wire [0:tag_width-1] 		     s1_nc_rsp_tag;
   wire [0:afu_rc_width-1] 		     s1_nc_rsp_rc;
   wire [0:afu_erc_width-1] 		     s1_nc_rsp_erc;
   wire 				     s1_nc_rsp_ok;
   wire 				     s1_nc_rsp_fc_tag_valid;
   wire [0:fc_tag_width_w_par-1] 	     s1_nc_rsp_fc_tag;            // added w_par kch 
   wire [0:chnlid_width-1] 		     s1_nc_rsp_chnl;


   // error prior to channel allocation bypasses the fc channel and goes straight to response.
   base_alatch_burp#(.width(chnlid_width+1+fc_tag_width_w_par+tag_width+1+afu_rc_width+afu_erc_width)) is4_cmd_err_lat    //added w_par kch 
     (.clk(clk),.reset(reset),
      .i_v(s4_cmda_v[channels] ),.i_r(s4_cmda_r[channels]),.i_d({s4_cmd_chnl,      s4_cmd_fc_tag, s4_cmd_fc_tag_valid,   s4_cmd_afu_tag,    s4_cmd_ok,    s4_cmd_rc,    s4_cmd_erc}),
      .o_v(s1_rsp_v[channels]),  .o_r(s1_rsp_r[channels]), .o_d({s1_nc_rsp_chnl, s1_nc_rsp_fc_tag, s1_nc_rsp_fc_tag_valid, s1_nc_rsp_tag, s1_nc_rsp_ok, s1_nc_rsp_rc, s1_nc_rsp_erc}));

   // build a status for the case where we don't go through a channel
   localparam [0:afu_rc_width-1] afu_to_rc = 'h51;
   localparam [0:afu_rc_width-1] afu_eto_rc = 'h50;
   
   
   wire [0:rslt_width-1] 		     s1_nc_rsp_rslt = {s1_nc_rsp_rc,s1_nc_rsp_erc,{rslt_width-afu_rsp_width{1'b0}}};
   wire [0:(fc_bufid_width+1)*channels-1]    s1_rm_cnt = {fc_bufid_width*channels{1'b0}};
   
   wire [0:63] 				     s1_dbg_reg0;
   wire [0:63] 				     s1_dbg_reg0_chnl;  // ktms_fc_chnl does not drive anything using dbg reg0 for debug of parity errors kch 

   wire 				     s4_cmd_tmgmt = s4_cmd_flgs[3];
   wire 				     s4_cmd_wnr = s4_cmd_flgs[4];
   wire 				     s4_cmd_wr =  s4_cmd_wnr & ~s4_cmd_tmgmt;
   wire 				     s4_cmd_rd = ~s4_cmd_wnr & ~s4_cmd_tmgmt;
   genvar 				     i;
   
   assign s1_rm_err[channels+2:channels+2+1] = {channels{1'b0}};  // used to be write buffer resource manager

   wire [0:channels-1] 			     s1_tochk_v, s1_tochk_r, s1_tochk_rnw;
   wire [0:channels*tag_width-1] 	     s1_tochk_tag;
   wire [0:channels-1] 			     s2_tochk_v, s2_tochk_ok;
   wire [0:3]                                dbg_cnt_nc;
   generate
      for(i=0; i<channels; i=i+1)
	begin : gen1

	   ktms_fc_channel#
	    (.ea_width(ea_width),
	     .ctxtid_width(ctxtid_width),
	     .cdb_width(cdb_width),
	     .max_reads(max_reads),
	     .max_writes(max_writes),
	     .tag_width(fc_tag_width),
	     .tstag_width(tag_width),
	     .channel_width(1),
	     .channel(i),
	     .lunid_width(lunid_width),
	     .beatid_width(fc_beatid_width),
	     .datalen_width(datalen_width),
	     .afu_data_width(130),                 //changed from 128 to 130 to add parity kch
	     .afu_bytec_width(dma_bytec_width),
	     .fc_data_width(fc_data_width),

	     .fc_cmd_width(fc_cmd_width),
	     .fcstat_width(fcstat_width),
	     .fcxstat_width(fcxstat_width),
	     .scstat_width(scstat_width),
	     .fcinfo_width(fcinfo_width),
	     .afu_rc_width(afu_rc_width),
	     .afu_erc_width(afu_erc_width),
	     .reslen_width(reslen_width),

	     .ssize_width(ssize_width),
	     .dma_rc_width(dma_rc_width),
	     .dma_rc_paged(psl_rsp_paged),
	     .dma_rc_addr(psl_rsp_addr)

	     )
	   ichnl
	    (
	     .clk(clk),
	     .reset(reset),
//	     .o_dbg_inc(dbg_cnt_inc[i*14+40:(i+1)*14+40-1]), // 40:53,54:67,68:81,82:95,
	     .o_dbg_inc({dbg_cnt_inc[i*14+40:(i+1)*14+36-1],dbg_cnt_nc}), // 40:49,54:63,68:79,82:91,
             .o_dbg_reg(s1_dbg_reg0_chnl[16*i:16*(i+1)-1]),
	     .o_stallcount_v(stallcount_v[13+i]),
	     .o_stallcount_r(stallcount_r[13+i]),
	     .i_errinj(s1_errinj[(i*3)+51:(i*3)+53]),
	     .i_cmd_v(s4_cmda_v[i]),
	     .i_cmd_r(s4_cmda_r[i]),
	     .i_cmd_rd(s4_cmd_rd),
	     .i_cmd_wr(s4_cmd_wr),
	     .i_cmd_tag(s4_cmd_fc_tag), 
	     .i_cmd_cdb(s4_cmd_cdb),   // has parity in bits 128 and 129 kch 
	     .i_cmd_lun(s4_cmd_lun),
	     .i_cmd_ea(s4_cmd_data_ea),
	     .i_cmd_tstag(s4_cmd_afu_tag),
	     .i_cmd_ctxt(s4_cmd_data_ctxt),
	     .i_cmd_data_len(s4_cmd_data_len),    // has parity kch 
	     .put_addr_r(put_addr_r[i]),
	     .put_addr_v(put_addr_v[i]),
	     .put_addr_ea(put_addr_d_ea[(ea_width*i):(ea_width*(i+1))-1]),      //has parity kch
	     .put_addr_tstag(put_addr_d_tstag[(tstag_width*i):(tstag_width*(i+1))-1]),
	     .put_addr_ctxt(put_addr_d_ctxt[(ctxtid_width*i):(ctxtid_width*(i+1))-1]),
	     .put_data_r(put_data_r[i]),
	     .put_data_v(put_data_v[i]),
	     .put_data_d(put_data_d[(130*i):(130*(i+1))-1]),
	     .put_data_e(put_data_e[i]),
	     .put_data_c(put_data_c[4*i:4*(i+1)-1]),
	     .put_data_f(put_data_f[i]),
	     .put_done_v(put_done_v[i]),
	     .put_done_r(put_done_r[i]),
	     .put_done_rc(put_done_rc[dma_rc_width*i:dma_rc_width*(i+1)-1]),
	     .get_addr_r(get_addr_r[i]),
	     .get_addr_v(get_addr_v[i]),
	     .get_addr_d_ea(get_addr_d_ea[(ea_width*i):(ea_width*(i+1))-1]),
	     .get_addr_d_tstag(get_addr_d_tstag[(tstag_width*i):(tstag_width*(i+1))-1]),
	     .get_addr_d_ctxt(get_addr_d_ctxt[ctxtid_width*i:ctxtid_width*(i+1)-1]),  
	     .get_addr_d_size(get_addr_d_size[ssize_width*i:ssize_width*(i+1)-1]),
	     .get_data_r(get_data_r[i]),
	     .get_data_v(get_data_v[i]),
	     .get_data_d(get_data_d[(130*i):(130*(i+1))-1]),
	     .get_data_e(get_data_e[i]),
	     .get_data_rc(get_data_rc[dma_rc_width*i:dma_rc_width*(i+1)-1]),
	     .get_data_c(get_data_c[dma_bytec_width*i:dma_bytec_width*(i+1)-1]),

	     .o_tochk_v(s1_tochk_v[i]),
	     .o_tochk_r(s1_tochk_r[i]),
	     .o_tochk_tag(s1_tochk_tag[tag_width*i:tag_width*(i+1)-1]),
	     .o_tochk_rnw(s1_tochk_rnw[i]),
	     .i_tochk_v(s2_tochk_v[i]),
	     .i_tochk_ok(s2_tochk_ok[i]),
	     
	     .o_rslt_r(s1_rsp_r[i]),
	     .o_rslt_v(s1_rsp_v[i]),
	     .o_rslt_tag(s1_rsp_fc_tag[(fc_tag_width_w_par*i):(fc_tag_width_w_par*(i+1))-1]),   // added w_par kch 
	     .o_rslt_stat(s1_rsp_stat[(rslt_width*i):(rslt_width*(i+1))-1]),

	     .o_fc_req_v(o_fc_req_v[i]),
	     .o_fc_req_r(o_fc_req_r[i]),
	     .o_fc_req_cmd(o_fc_req_cmd[i*fc_cmd_width:(i+1)*fc_cmd_width-1]),
	     .o_fc_req_tag(o_fc_req_tag[i*fc_tag_width:(i+1)*fc_tag_width-1]),   
	     .o_fc_req_tag_par(o_fc_req_tag_par[i*fc_tag_par_width:(i+1)*fc_tag_par_width-1]),   
	     .o_fc_req_lun(o_fc_req_lun[i*fc_lunid_width:(i+1)*fc_lunid_width-1]),
	     .o_fc_req_lun_par(o_fc_req_lun_par[i]),
	     .o_fc_req_cdb(o_fc_req_cdb[i*cdb_width:(i+1)*cdb_width-1]),
	     .o_fc_req_cdb_par(o_fc_req_cdb_par[i*cdb_par_width:(i+1)*cdb_par_width-1]),                       // added kch 
	     .o_fc_req_length(o_fc_req_length[i*datalen_width:(i+1)*datalen_width-1]),
	     .o_fc_req_length_par(o_fc_req_length_par[i]),

	      
	     .i_fc_wdata_req_v(i_fc_wdata_req_v[i]),
	     .i_fc_wdata_req_r(i_fc_wdata_req_r[i]),
	     .i_fc_wdata_req_tag(i_fc_wdata_req_tag[i*fc_tag_width:(i+1)*fc_tag_width-1]),
	     .i_fc_wdata_req_tag_par(i_fc_wdata_req_tag_par[i*fc_tag_par_width:(i+1)*fc_tag_par_width-1]),
	     .i_fc_wdata_req_beat(i_fc_wdata_req_beat[i*fc_beatid_width:(i+1)*fc_beatid_width-1]),
	     .i_fc_wdata_req_size(i_fc_wdata_req_size[i*datalen_width:(i+1)*datalen_width-1]),
	     .i_fc_wdata_req_size_par(i_fc_wdata_req_size_par[i]),    // added kch 

	     .o_fc_wdata_rsp_v(o_fc_wdata_rsp_v[i]),
	     .o_fc_wdata_rsp_r(o_fc_wdata_rsp_r[i]),
	     .o_fc_wdata_rsp_e(o_fc_wdata_rsp_e[i]),
	     .o_fc_wdata_rsp_error(o_fc_wdata_rsp_error[i]),
	     .o_fc_wdata_rsp_tag(o_fc_wdata_rsp_tag[i*fc_tag_width:(i+1)*fc_tag_width-1]),
	     .o_fc_wdata_rsp_tag_par(o_fc_wdata_rsp_tag_par[i*fc_tag_par_width:(i+1)*fc_tag_par_width-1]),
	     .o_fc_wdata_rsp_beat(o_fc_wdata_rsp_beat[i*fc_beatid_width:(i+1)*fc_beatid_width-1]),
	     .o_fc_wdata_rsp_data(o_fc_wdata_rsp_data[i*fc_data_width:(i+1)*fc_data_width-1]),
	     .o_fc_wdata_rsp_data_par(o_fc_wdata_rsp_data_par[i*fc_data_par_width:(i+1)*fc_data_par_width-1]),  // added kch 

	     .i_fc_rdata_rsp_v(i_fc_rdata_rsp_v[i]),
	     .i_fc_rdata_rsp_r(i_fc_rdata_rsp_r[i]),
	     .i_fc_rdata_rsp_e(i_fc_rdata_rsp_e[i]),
	     .i_fc_rdata_rsp_c(i_fc_rdata_rsp_c[fc_bytec_width*i:fc_bytec_width*(i+1)-1]),
	     .i_fc_rdata_rsp_tag(i_fc_rdata_rsp_tag[i*fc_tag_width:(i+1)*fc_tag_width-1]),
	     .i_fc_rdata_rsp_tag_par(i_fc_rdata_rsp_tag_par[i*fc_tag_par_width:(i+1)*fc_tag_par_width-1]),
	     .i_fc_rdata_rsp_beat(i_fc_rdata_rsp_beat[i*fc_beatid_width:(i+1)*fc_beatid_width-1]),
	     .i_fc_rdata_rsp_data(i_fc_rdata_rsp_data[i*fc_data_width:(i+1)*fc_data_width-1]),
	     .i_fc_rdata_rsp_data_par(i_fc_rdata_rsp_data_par[i*fc_data_par_width:(i+1)*fc_data_par_width-1]),

	     .i_fc_rsp_v(i_fc_rsp_v[i]),
	     .i_fc_rsp_tag(i_fc_rsp_tag[i*fc_tag_width:(i+1)*fc_tag_width-1]),
	     .i_fc_rsp_tag_par(i_fc_rsp_tag_par[i*fc_tag_par_width:(i+1)*fc_tag_par_width-1]),
	     .i_fc_rsp_fcstat(i_fc_rsp_fc_status[i*fcstat_width:(i+1)*fcstat_width-1]),
	     .i_fc_rsp_fcxstat(i_fc_rsp_fcx_status[i*fcxstat_width:(i+1)*fcxstat_width-1]),
	     .i_fc_rsp_scstat(i_fc_rsp_scsi_status[i*scstat_width:(i+1)*scstat_width-1]),
	     .i_fc_rsp_info(i_fc_rsp_info[i*fcinfo_width:(i+1)*fcinfo_width-1]),
	     .i_fc_rsp_fcp_valid(i_fc_rsp_fcp_valid[i]),
	     .i_fc_rsp_sns_valid(i_fc_rsp_sns_valid[i]),
             .i_fc_rsp_rdata_beats(i_fc_rsp_rdata_beats[i*fc_beatid_width:(i+1)*fc_beatid_width-1]),
	     .i_fc_rsp_underrun(i_fc_rsp_underrun[i]),
	     .i_fc_rsp_overrun(i_fc_rsp_overrun[i]),
	     .i_fc_rsp_resid(i_fc_rsp_resid[i*32:(i+1)*32-1]),
             .o_perror(o_perror[57+2*i:57+2*i+1])   // added o_perror kch bits 57:64 
	     );

	end // for (i=0; i<channels; i++)
   endgenerate




   // TODO: Hook these up when functions supported    completed kch commented theses out
 //  assign o_fc_req_tag_par[0:fc_tag_par_width-1] = {fc_tag_par_width{1'b0}};
//   assign o_fc_req_lun_par[0:fc_lunid_par_width-1] = {fc_lunid_par_width{1'b0}};
//   assign o_fc_wdata_rsp_data_par[0:fc_data_par_width-1] = {fc_data_par_width{1'b0}};


   // completed instructions from timeout.
   // could be timed out instructions that never got sent out fc link
   // or could be sync instructions completing normally


   wire 			     s1a_rsp_v, s1a_rsp_r;
   wire [0:fc_tag_width_w_par-1]     s1a_rsp_fc_tag;     // added w_par
   wire [0:rslt_width-1] 	     s1a_rsp_stat;

   wire [0:channels] 		     s1_rsp_sel;
   base_arr_mux#(.ways(channels+1),.width(fc_tag_width_w_par)) is1rsp_mux            // added w_par kch 
     (
      .clk(clk),.reset(reset),
      .i_v(s1_rsp_v),.i_r(s1_rsp_r),.i_d({s1_rsp_fc_tag, s1_nc_rsp_fc_tag}),  // follow both back fixit kch
      .o_v(s1a_rsp_v),.o_r(s1a_rsp_r),.o_d(s1a_rsp_fc_tag),.o_sel(s1_rsp_sel));
   assign dbg_cnt_inc[3] = s1a_rsp_v & s1a_rsp_r;


   base_mux#(.ways(channels+1),.width(rslt_width)) is1rsp_stat_mux(.din({s1_rsp_stat,s1_nc_rsp_rslt}),.dout(s1a_rsp_stat),.sel(s1_rsp_sel));
   wire 			     s1a_rsp_fc_tag_valid;
   base_mux#(.ways(channels+1),.width(1))          is1rsp_fcv_mux (.din({{channels{1'b1}},s1_nc_rsp_fc_tag_valid}),.dout(s1a_rsp_fc_tag_valid),.sel(s1_rsp_sel));

   // encode channel   
   wire [0:chnlid_width-1] 	     s1_rsp_chnl;
   base_encode#(.enc_width(chnlid_width),.dec_width(channels)) is1a_rsp_chnl_enc(.i_d(s1_rsp_sel[0:channels-1]),.o_d(s1_rsp_chnl),.o_v());

   // record which channel (0 for timeout)
   wire [0:chnlid_width-1] 	     s1a_rsp_chnl;
   base_mux#(.ways(channels+1),.width(chnlid_width)) is1rsp_chnl_mux (.din({{channels{s1_rsp_chnl}},s1_nc_rsp_chnl}),.dout(s1a_rsp_chnl),.sel(s1_rsp_sel));

   wire [0:rslt_width-1] 	     s2_rsp_stat;
   wire [0:tag_width-1] 	     s2_nc_rsp_afu_tag;
   wire 			     s1a_rsp_re;
   wire 			     s2_rsp_tagret;
   wire 			     s1_rsp_nc = | s1_rsp_sel[channels];
   wire [0:tag_width-1] 	     s1a_nc_rsp_tag = s1_nc_rsp_tag;
 	     
   base_alatch_oe#(.width(rslt_width+1+fc_tag_width_w_par+tag_width+chnlid_width+1)) is2_rsp_lat
     (.clk(clk),.reset(reset),
      .i_v(s1a_rsp_v),.i_r(s1a_rsp_r),.i_d({s1a_rsp_stat,  s1a_rsp_fc_tag_valid, s1a_rsp_fc_tag, s1a_nc_rsp_tag,    s1a_rsp_chnl, s1_rsp_nc}),.o_en(s1a_rsp_re),
      .o_v(s2_rsp_v), .o_r(s2_rsp_r), .o_d({ s2_rsp_stat,   s2_rsp_fc_tag_valid,  s2_rsp_fc_tag, s2_nc_rsp_afu_tag,  s2_rsp_chnl, s2_rsp_nc}));

   wire [0:tag_width-1] 	     s2_fc_rsp_afu_tag;
   base_mem#(.addr_width(chnlid_width+fc_tag_width),.width(tag_width)) ifctag_mem
     (.clk(clk),
      .we(s4_cmd_fc_tag_valid & s4_cmd_v), .wa({ s4_cmd_chnl, s4_cmd_fc_tag[0:fc_tag_width_w_par-2]}),.wd(   s4_cmd_afu_tag),  // stripped off parity for wa kch 
      .re(s1a_rsp_re),                     .ra({s1a_rsp_chnl,s1a_rsp_fc_tag[0:fc_tag_width_w_par-2]}),.rd(s2_fc_rsp_afu_tag)   // stripped off parity for ra kch  
      );

   wire [0:tag_width-1] 	     s2_rsp_afu_tag = s2_rsp_nc ? s2_nc_rsp_afu_tag : s2_fc_rsp_afu_tag;
   
   wire [0:rslt_width-1] 	     s3_rsp_stat;
   wire [0:tag_width-1] 	     s3_rsp_afu_tag;
   wire [0:chnlid_width-1] 	     s3_rsp_chnl;
   wire 			     s3_rsp_v, s3_rsp_r;
   wire 			     s3_rsp_tagret;
   wire 			     s3_rsp_nocmpl;
   

   wire 			     s4a_rsp_v, s4a_rsp_r;
   wire [0:rslt_width-1] 	     s4a_rsp_stat;
   wire [0:tag_width-1] 	     s4a_rsp_afu_tag;
   wire [0:chnlid_width-1] 	     s4a_rsp_chnl;
   wire 			     s4a_rsp_tagret; // return the tag - off for timeouts
   wire 			     s4a_rsp_nocmpl;
   wire 			     s3_rsp_re;
   base_alatch_oe#(.width(rslt_width+tag_width+chnlid_width+1+1)) is4a_rsp_lat
     (.clk(clk),.reset(reset),.i_v(s3_rsp_v),.i_r(s3_rsp_r),.i_d({s3_rsp_stat,s3_rsp_afu_tag,s3_rsp_chnl,s3_rsp_tagret,s3_rsp_nocmpl}),.o_en(s3_rsp_re),
      .o_v(s4a_rsp_v),.o_r(s4a_rsp_r),.o_d({s4a_rsp_stat,s4a_rsp_afu_tag,s4a_rsp_chnl,s4a_rsp_tagret,s4a_rsp_nocmpl}));
   assign dbg_cnt_inc[4] = s4a_rsp_v & s4a_rsp_r;
   wire [0:ctxtid_width-1] 	     s4a_rsp_ctxt;
   wire 			     s4a_rsp_ec;

   wire [0:ea_width-1] 		     s4a_rsp_ea;
   wire [0:msinum_width-1] 	     s4a_rsp_msinum;
   wire [0:syncid_width-1] 	     s4a_rsp_syncid;
   wire 			     s4a_rsp_rnw;
   wire 			     s4a_rsp_sule;
   
   wire                              s1_cmd_wnr = s1_cmd_flgs[4];
   wire                              s1_cmd_sule = s1_cmd_flgs[2];
   wire                              s2_retry_rcb_re;
   wire [0:8]                        s2_retry_rcb_afu_tag;

   base_mem#(.addr_width(tag_width-1),.width(1+1+msinum_width+ctxtid_width+1+ea_width+syncid_width)) icmdmem   //added -1 to reduce addrwidth for parity kch 
     (.clk(clk),
      .wa(s1_cmd_tag[0:tag_width-2]),    .wd({~s1_cmd_wnr,s1_cmd_sule,s1_cmd_msinum, s1_cmd_rcb_ctxt,s1_cmd_rcb_ec, s1_cmd_rcb_ea, s1_cmd_syncid}),.we(s1_cmd_v),  // add [0:tag_width-2] to strip off parity kch  
      .ra(s3_rsp_afu_tag[0:tag_width-2]),.rd({ s4a_rsp_rnw,s4a_rsp_sule,s4a_rsp_msinum,     s4a_rsp_ctxt,    s4a_rsp_ec,     s4a_rsp_ea, s4a_rsp_syncid}),.re(s3_rsp_re)   // add [0:tag_width-2] to strip off parity kch
      );

   base_mem#(.addr_width(tag_width-1),.width(ctxtid_width+ea_width+1+64)) icmd_retry_mem   //added -1 to reduce addrwidth for parity kch 
     (.clk(clk),
      .wa(s1_cmd_tag[0:tag_width-2]),    .wd({s1_cmd_rcb_ctxt,s1_cmd_rcb_ea,s1_cmd_rcb_timestamp,s1_cmd_rcb_hp}),.we(s1_cmd_v),  //  
      .ra(s2_cmd_tag[0:tag_width-2]),.rd({s2_retry_rcb_ctxt,s2_retry_rcb_ea,s2_retry_rcb_timestamp,s2_retry_rcb_hp}),.re(1'b1)   
      );

   wire s3_rsp_check_v;
   wire s2_cmd_check_v;
   wire [0:8] s2_cmd_check_tag;
   wire [0:8] s3_rsp_check_tag;
   base_vlat#(.width(10)) i_dlay_cmplt_tag(.clk(clk),.reset(reset),.din({(s3_rsp_v & s3_rsp_r),s3_rsp_afu_tag[0:8]}),.q({s3_rsp_check_v,s3_rsp_check_tag}));
   base_vlat#(.width(10)) i_dlay_tag(.clk(clk),.reset(reset),.din({(s1_cmd_v & s1_cmd_r),s1_cmd_tag[0:8]}),.q({s2_cmd_check_v,s2_cmd_check_tag}));

   base_vmem#(.a_width(tag_width-1),.rports(2)) ots_rcb  // added -1 kch 
     (.clk(clk),.reset(reset),
      .i_set_v(s1_cmd_v),.i_set_a(s1_cmd_tag[0:tag_width-2]),  // added [0:tag_width-2] kch
      .i_rst_v(s3_rsp_v & s3_rsp_r),.i_rst_a(s3_rsp_afu_tag[0:tag_width-2]),  // added 0:tag_width-2 kch
      .i_rd_en(2'b11),.i_rd_a({s3_rsp_afu_tag[0:tag_width-2],s1_cmd_tag[0:tag_width-2]}),.o_rd_d({s1_read_outst,s2_write_outst})
      );
   wire s3_read_error = s3_rsp_check_v & ~(s1_read_outst);
   wire s2_write_error = s2_cmd_check_v & (s2_write_outst);
   wire rcb_read_error_hld;
   wire rcb_write_error_hld;
//   assign dbg_cnt_inc[128] = s3_read_error ;
//   assign dbg_cnt_inc[127] = s2_write_error;
   wire [0:tag_width-2] 		     s2_cmd_error_tag;
   wire [0:tag_width-2]  write_error_tag;

    base_vlat_en#(.width(1))  icmplterror (.clk(clk),.reset(reset),.din(s3_read_error),  .q(rcb_read_error_hld),    .enable(s3_read_error));
    base_vlat_en#(.width(1))  itagerror (.clk(clk),.reset(reset),.din(s2_write_error),  .q(rcb_write_error_hld),    .enable(s2_write_error));
    base_vlat#(.width(9))  is2_tag (.clk(clk),.reset(reset),.din(s1_cmd_tag[0:tag_width-2]),  .q(s2_cmd_error_tag));
    base_vlat_en#(.width(9))  iwrt_error_tag (.clk(clk),.reset(reset),.din(s2_cmd_error_tag[0:tag_width-2]),  .q(write_error_tag),    .enable(s2_write_error & ~rcb_write_error_hld));

   wire 			     s4_abrt_nocmpl = 1'b0;
   wire 			     s4_abrt_tagret = 1'b1;
   wire [0:rslt_width-1] 	     s4_abrt_stat = {afu_eto_rc,{rslt_width-afu_rc_width{1'b0}}};
 	     
   wire 			     s4_rsp_v, s4_rsp_r;
   wire [0:rslt_width-1] 	     s4_rsp_stat;
   wire [0:tag_width-1] 	     s4_rsp_afu_tag;
   wire [0:chnlid_width-1] 	     s4_rsp_chnl;
   wire 			     s4_rsp_tagret; // return the tag - off for timeouts
   wire 			     s4_rsp_nocmpl;
   wire [0:ctxtid_width-1] 	     s4_rsp_ctxt;
   wire 			     s4_rsp_ec;
   wire [0:ea_width-1] 		     s4_rsp_ea;
   wire [0:msinum_width-1] 	     s4_rsp_msinum;
   wire [0:syncid_width-1] 	     s4_rsp_syncid;
   wire 			     s4_rsp_rnw;
   wire 			     s4_rsp_sule;

   base_primux#(.ways(2),.width(rslt_width+tag_width+chnlid_width+1+1+ctxtid_width+1+ea_width+msinum_width+syncid_width+1+1)) is4_rsp_mux
     (.i_v({s4a_rsp_v,s4_abrt_v}),.i_r({s4a_rsp_r,s4_abrt_r}),
      .i_d({ s4a_rsp_stat, s4a_rsp_afu_tag, s4a_rsp_chnl,  s4a_rsp_tagret, s4a_rsp_nocmpl, s4a_rsp_ctxt, s4a_rsp_ec, s4a_rsp_ea, s4a_rsp_msinum, s4a_rsp_syncid, s4a_rsp_rnw, s4a_rsp_sule,
	     s4_abrt_stat,     s4_abrt_tag, s4_abrt_chnl,  s4_abrt_tagret, s4_abrt_nocmpl, s4_abrt_ctxt, s4_abrt_ec, s4_abrt_ea, s4_abrt_msinum, s4_abrt_syncid, s4_abrt_rnw, s4_abrt_sule}),
      .o_v(s4_rsp_v),.o_r(s4_rsp_r),
      .o_d({ s4_rsp_stat, s4_rsp_afu_tag, s4_rsp_chnl,  s4_rsp_tagret, s4_rsp_nocmpl, s4_rsp_ctxt, s4_rsp_ec, s4_rsp_ea, s4_rsp_msinum,s4_rsp_syncid,s4_rsp_rnw,s4_rsp_sule}),.o_sel()
      );

   
   
   localparam put_asa = channels+1;
   
   wire 			     s5_rsp_v, s5_rsp_r;
   
   wire [0:ctxtid_width-1] 	     s5_rsp_ctxt;
   wire 			     s5_rsp_ec;
   wire [0:ea_width-1] 		     s5_rsp_ea;
   wire [0:syncid_width-1] 	     s5_rsp_syncid;
   wire 			     s5_rsp_rnw;
   wire [0:msinum_width-1] 	     s5_rsp_msinum;
   wire [0:tag_width-1] 	     s5_rsp_afu_tag;
   wire [0:sintrid_width-1] 	     s5_rsp_sintr_id;
   wire 			     s5_rsp_sintr_v;
   wire 			     s5_rsp_nocmpl;
   wire 			     s5_rsp_tagret;
   
   wire [11:0] 			     ioasa_pipemon_v;
   wire [11:0] 			     ioasa_pipemon_r;

   
   ktms_afu_ioasa#
     (
      .ctxtid_width(ctxtid_width),
      .ea_width(ea_width),
      .aux_width(syncid_width+1+msinum_width+tag_width+1),

      // error reporting widths      
      .afu_rc_width(afu_rc_width),
      .afu_erc_width(afu_erc_width),
      .fcstat_width(fcstat_width),
      .fcxstat_width(fcxstat_width),
      .scstat_width(scstat_width),
      .fcinfo_width(fcinfo_width),
      .reslen_width(reslen_width),
      .tstag_width(tag_width),
      .dma_rc_width(dma_rc_width),
      .time_width(time_width),
      .chnlid_width(chnlid_width),
      .psl_rsp_paged(psl_rsp_paged),
      .psl_rsp_addr(psl_rsp_addr),
      .psl_rsp_cinv(psl_rsp_cinv),
      .sintrid_width(sintrid_width),
      .sintr_asa(sintr_asa),
      .sintr_rcb(sintr_rcb),
      .sintr_paged(sintr_paged)

      ) iasa
       (.clk(clk),.reset(reset),
	.i_errinj_asa_fault(s1_errinj[60]),
	.i_errinj_asa_paged(s1_errinj[59]),
	.i_rtry_cfg(gbl_reg7[49:54]),
	.i_rsp_v(s4_rsp_v),
	.i_rsp_r(s4_rsp_r),
	.i_rsp_tstag(s4_rsp_afu_tag),
	.i_rsp_ctxt(s4_rsp_ctxt),
	.i_rsp_ec(s4_rsp_ec),
	.i_rsp_ea(s4_rsp_ea),
	.i_rsp_stat(s4_rsp_stat),
	.i_rsp_chnl(s4_rsp_chnl),
	.i_rsp_sule(s4_rsp_sule),
	.i_rsp_nocmpl(s4_rsp_nocmpl),
	.i_rsp_aux({s4_rsp_syncid,s4_rsp_rnw,s4_rsp_msinum,s4_rsp_afu_tag,s4_rsp_tagret}),
	
	.o_rsp_v(s5_rsp_v),
	.o_rsp_r(s5_rsp_r),
	.o_rsp_ctxt(s5_rsp_ctxt),
	.o_rsp_ec(s5_rsp_ec),
	.o_rsp_nocmpl(s5_rsp_nocmpl),

	.o_rsp_tstag(),
	.o_rsp_ea(s5_rsp_ea),
	.o_rsp_aux({s5_rsp_syncid,s5_rsp_rnw,s5_rsp_msinum,s5_rsp_afu_tag,s5_rsp_tagret}),
	.o_rsp_sintr_v(s5_rsp_sintr_v),
	.o_rsp_sintr_id(s5_rsp_sintr_id),
	
	.o_put_addr_v(put_addr_v[put_asa]),
	.o_put_addr_r(put_addr_r[put_asa]),
	.o_put_addr_ctxt(put_addr_d_ctxt[put_asa*ctxtid_width:(put_asa+1)*ctxtid_width-1]),
	.o_put_addr_ea(put_addr_d_ea[put_asa*ea_width:(put_asa+1)*ea_width-1]),                 //has parity kch
	.o_put_addr_tstag(put_addr_d_tstag[put_asa*tstag_width:(put_asa+1)*tstag_width-1]),
	
	.i_put_done_v(put_done_v[put_asa]),
	.i_put_done_r(put_done_r[put_asa]),
	.i_put_done_rc(put_done_rc[dma_rc_width*put_asa:dma_rc_width*(put_asa+1)-1]),
	
	.o_put_data_v(put_data_v[put_asa]),
	.o_put_data_r(put_data_r[put_asa]),
	.o_put_data_d(put_data_d[130*put_asa:130*(put_asa+1)-1]),
        .o_put_data_f(put_data_f[put_asa]),
        .o_put_data_e(put_data_e[put_asa]),
        .o_put_data_c(put_data_c[4*put_asa:4*(put_asa+1)-1]),
//      .o_dbg_cnt_inc(dbg_cnt_inc[96:97]),
        .o_dbg_cnt_inc(),
        .o_pipemon_v(ioasa_pipemon_v),
        .o_pipemon_r(ioasa_pipemon_r),
        .o_perror(o_perror[65])

	);
   // monitor rrq input for backup
   assign stallcount_v[4] = s5_rsp_v;
   assign stallcount_r[4] = s5_rsp_r;
   assign dbg_cnt_inc[5] = s5_rsp_v & s5_rsp_r;
   
   assign stallcount_v[5] = put_addr_v[put_asa];
   assign stallcount_r[5] = put_addr_r[put_asa];
   assign stallcount_v[6] = put_data_v[put_asa];
   assign stallcount_r[6] = put_data_r[put_asa];
   assign stallcount_v[7] = put_done_v[put_asa];
   assign stallcount_r[7] = put_done_r[put_asa];


   assign stallcount_v[8] = put_data_v[0];
   assign stallcount_v[9] = put_data_v[1];
   assign stallcount_r[8] = put_data_r[0];
   assign stallcount_r[9] = put_data_r[1];
   


   wire 			     s6a_rsp_v, s6a_rsp_r;
   wire 			     s6_rsp_rnw;
   wire [0:ctxtid_width-1] 	     s6_rsp_ctxt;
   wire [0:msinum_width-1] 	     s6_rsp_msinum;
   wire [0:sintrid_width-1] 	     s6_rsp_sintr_id;
   wire 			     s6_rsp_sintr_v;
   wire [0:syncid_width-1] 	     s6_rsp_syncid;
   wire [0:tag_width-1] 	     s6_rsp_afu_tag;
   wire 			     s6_rsp_nocmpl;
   wire 			     s6_rsp_tagret;
   

   wire [0:8] 			     rrq_pipemon_v;
   wire [0:8] 			     rrq_pipemon_r;

   wire 			     s1_rrq_st_we;
   wire 			     s1_rrq_ed_we;
   wire [0:ctxtid_width-1] 	     s1_rrq_ctxt;
   wire [0:64] 			     s1_rrq_wd;

   ktms_afu_rrq#
     (.ea_width(ea_width),
      .ctxtid_width(ctxtid_width),
      .dma_rc_width(dma_rc_width),
      .afu_rc_width(afu_rc_width),
      .sintrid_width(sintrid_width),
      .tstag_width(tag_width),
      .rrq_st_addr(mmioaddr_rrq_st),
      .rrq_ed_addr(mmioaddr_rrq_ed),
      .psl_rsp_paged(psl_rsp_paged),
      .psl_rsp_addr(psl_rsp_addr),
      .sintr_paged(sintr_paged),
      .sintr_rrq(sintr_rrq),
      .aux_width(syncid_width+1+tag_width+1+ctxtid_width+msinum_width),
      .mmioaddr(mmioaddr_rrq),
      .mmiobus_width(mmiobus_width)
      ) 
   irrq
     (.clk(clk),.reset(reset),
      .o_pipemon_v(rrq_pipemon_v),
      .o_pipemon_r(rrq_pipemon_r),

      .i_mmiobus(mmiobus),
      .o_mmio_ack(rrq_mmack),.o_mmio_data(rrq_mmdata),

      .i_rrq_st_we(s1_rrq_st_we),
      .i_rrq_ed_we(s1_rrq_ed_we),
      .i_rrq_ctxt(s1_rrq_ctxt),
      .i_rrq_wd(s1_rrq_wd),

      .i_errinj_rrq_fault(s1_errinj[58]),
      .i_errinj_rrq_paged(s1_errinj[57]),
      .i_rtry_cfg(gbl_reg7[55]),      
      .i_rsp_v(s5_rsp_v),
      .i_rsp_r(s5_rsp_r),
      .i_rsp_ctxt(s5_rsp_ctxt),
      .i_rsp_ec(s5_rsp_ec),
      .i_rsp_nocmpl(s5_rsp_nocmpl),
      .i_rsp_tstag(s5_rsp_afu_tag),
      .i_rsp_d(s5_rsp_ea),
      .i_rsp_aux({s5_rsp_syncid,s5_rsp_rnw,s5_rsp_afu_tag,s5_rsp_tagret,s5_rsp_ctxt,s5_rsp_msinum}),
      .i_rsp_sintr_v(s5_rsp_sintr_v),
      .i_rsp_sintr_id(s5_rsp_sintr_id),

      .o_put_addr_v(put_addr_v[channels]),
      .o_put_addr_r(put_addr_r[channels]),
      .o_put_addr_ctxt(put_addr_d_ctxt[channels*ctxtid_width:(channels+1)*ctxtid_width-1]),
      .o_put_addr_tstag(put_addr_d_tstag[channels*tstag_width:(channels+1)*tstag_width-1]),
      .o_put_addr_ea(put_addr_d_ea[channels*ea_width:(channels+1)*ea_width-1]),

      .o_put_data_v(put_data_v[channels]),
      .o_put_data_r(put_data_r[channels]),
      .o_put_data_d(put_data_d[130*channels:130*(channels+1)-1]),
      .o_put_data_f(put_data_f[channels]),
      .o_put_data_e(put_data_e[channels]),
      .o_put_data_c(put_data_c[4*channels:4*(channels+1)-1]),

      .i_put_done_v(put_done_v[channels]),
      .i_put_done_r(put_done_r[channels]),
      .i_put_done_rc(put_done_rc[dma_rc_width*channels:dma_rc_width*(channels+1)-1]),
      .o_rsp_v(s6a_rsp_v),
      .o_rsp_r(s6a_rsp_r),
      .o_rsp_nocmpl(s6_rsp_nocmpl),
      .o_rsp_sintr_v(s6_rsp_sintr_v),
      .o_rsp_sintr_id(s6_rsp_sintr_id),
      .o_dbg_cnt_inc(dbg_cnt_inc[98]),
      .o_rsp_aux({s6_rsp_syncid,s6_rsp_rnw,s6_rsp_afu_tag,s6_rsp_tagret,s6_rsp_ctxt,s6_rsp_msinum}),
      .o_perror(o_perror[66])    // added o_perror kch   
    );


   assign stallcount_v[10] = put_addr_v[channels];
   assign stallcount_r[10] = put_addr_r[channels];
   assign stallcount_v[11] = put_data_v[channels];
   assign stallcount_r[11] = put_data_r[channels];
   assign stallcount_v[12] = put_done_v[channels];
   assign stallcount_r[12] = put_done_r[channels];

   // 0 - generates normal completion interupt
   // 1 - genrates sintr interupt
   // 2 - tag return
   wire [0:2] 			     s6b_rsp_v, s6b_rsp_r;
   base_acombine#(.ni(1),.no(3)) is6_cmb(.i_v(s6a_rsp_v),.i_r(s6a_rsp_r),.o_v(s6b_rsp_v),.o_r(s6b_rsp_r));

   // normal completion interupt
   wire 			     s1_intr2_v, s1_intr2_r;
   wire 			     s6_rsp_irq_en = |s6_rsp_msinum;
   wire [0:2] 			     s6_rsp_fltr_en;
   assign s6_rsp_fltr_en[0] = s6_rsp_irq_en & ~s6_rsp_sintr_v & ~s6_rsp_nocmpl;
   assign s6_rsp_fltr_en[1] = s6_rsp_sintr_v;
   assign s6_rsp_fltr_en[2] = s6_rsp_tagret;
   wire [0:2] 			     s6c_rsp_v, s6c_rsp_r;
   base_afilter is6_rsp_fltr0(.i_v(s6b_rsp_v[0]),.i_r(s6b_rsp_r[0]),.o_v(s6c_rsp_v[0]),.o_r(s6c_rsp_r[0]),.en(s6_rsp_fltr_en[0]));
   base_afilter is6_rsp_fltr1(.i_v(s6b_rsp_v[1]),.i_r(s6b_rsp_r[1]),.o_v(s6c_rsp_v[1]),.o_r(s6c_rsp_r[1]),.en(s6_rsp_fltr_en[1]));
   base_afilter is6_rsp_fltr2(.i_v(s6b_rsp_v[2]),.i_r(s6b_rsp_r[2]),.o_v(s6c_rsp_v[2]),.o_r(s6c_rsp_r[2]),.en(s6_rsp_fltr_en[2]));
   
   assign s1_intr2_v = s6c_rsp_v[0];
   assign s6c_rsp_r[0] = s1_intr2_r;
   
   
   // only send completion interupt if sintr is not valid, and msinum is not zero and we are not retrying
   wire [0:msinum_width-1] 	     s1_intr2_msi = s6_rsp_msinum;
   wire [0:ctxtid_width-1] 	     s1_intr2_ctxt = s6_rsp_ctxt;
   wire 			     s1_intr2_tstag_v = 1'b1;  //use tstag for normal completion
   wire [0:tstag_width-1] 	     s1_intr2_tstag = s6_rsp_afu_tag;
   
   // tag return
   base_alatch_burp#(.width(syncid_width+tag_width)) is1_cmpl_lat
     (.clk(clk),.reset(reset),
      .i_v(s6c_rsp_v[2]),.i_r(s6c_rsp_r[2]),.i_d({s6_rsp_syncid,  s6_rsp_afu_tag}),
      .o_v(s1_cmpl_v),   .o_r(1'b1),   .o_d({s1_cmpl_syncid,s1_cmpl_tag}));

   wire 			     s1_intr1_v, s1_intr1_r;

   assign dbg_cnt_inc[6] = s6a_rsp_v & s6a_rsp_r; // output from rrq
   assign dbg_cnt_inc[7] = s6c_rsp_v[1] & s6c_rsp_r[1]; // synchronous interupt
   assign dbg_cnt_inc[8] = s1_timeout_v;
   assign dbg_cnt_inc[9] = s6a_rsp_v & s6a_rsp_r & ~s6_rsp_irq_en & ~s6_rsp_sintr_v;
   assign dbg_cnt_inc[10] = s6a_rsp_v & s6a_rsp_r & ~s6_rsp_sintr_v & s6_rsp_nocmpl;

   assign dbg_cnt_inc[11] = s1_intr0_v & s1_intr0_r;  // async interrupt
   assign dbg_cnt_inc[12] = s1_intr1_v & s1_intr1_r;  // sync interrupt
   assign dbg_cnt_inc[13] = s1_intr2_v & s1_intr2_r;  // normal completion

   assign dbg_cnt_inc[14] = s1_croom_err_v & s1_croom_err_r;
   assign dbg_cnt_inc[15] = s4_abrt_v & s4_abrt_r;
//   assign dbg_cnt_inc[35] = 1'b0;


   // 26:31 is dma
   
   // signaltap timing
   wire 			     st_ha_jval /*synthesis keep=1*/ ;
   wire [0:7] 			     st_ha_jcom /*synthesis keep=1*/ ;
   wire [0:63] 			     st_ha_jea /*synthesis keep=1*/ ;
   
   base_vlat#(.width(1)) iha_jval_lat(.clk(clk),.reset(reset),.din(ha_jval),.q(st_ha_jval));
   base_vlat#(.width(8)) iha_jcom_lat(.clk(clk),.reset(reset),.din(ha_jcom),.q(st_ha_jcom));
   base_vlat#(.width(64)) iha_jea_lat(.clk(clk),.reset(reset),.din(ha_jea),.q(st_ha_jea));

   
   wire [0:9] 			     s1_rtry_cnt = 10'd0;
   wire 			     s1_rtry_hw= 1'b0;
   wire [0:5]                        timeout_s1_perror;
  
   wire [0:9]                        tbf_wa;
   assign        		     s1_dbg_reg0 = {dma_top_s1_perror,2'b00,error_status_hld};
   wire [0:63] 			     s1_dbg_reg1 = checker_data;
//   wire [0:63] 			     s1_dbg_reg2 = {7'd0,tbf_wa,s1_cmd_dbg_reg[0:31],s1_vrh_erc_hld,2'd0,timeout_s1_perror};
   wire [0:63] 			     s1_dbg_reg2 = {7'd0,tbf_wa,s1_cmd_dbg_reg[0:31],s1_vrh_erc_hld,ha_croom};  // added croom
   wire [0:63]                       s1_dbg_reg13 = {40'b0,7'b0,write_error_tag,4'b0,cmpl_error_hld,tag_error_hld,rcb_read_error_hld,rcb_write_error_hld};
   wire [0:127] wrt_rd_xlate_state;    
`ifdef DEBUG_CNT   
   ktms_debug_cnt#(.n(dbg_cnt_regs),.mmioaddr(mmioaddr_dbg_cnt),.mmiobus_width(mmiobus_width)) idbg_cnt
     (.clk(clk),.reset(reset),
      .i_mmiobus(mmiobus),
      .i_inc(dbg_cnt_inc[0:dbg_cnt_regs-1]),
      .o_mmio_rd_v(dbgc_mmack),.o_mmio_rd_d(dbgc_mmdata)
      );

`else // !`ifdef DEBUG_CNT
   assign dbgc_mmack = 1'b0;
   assign dbgc_mmdata = 64'd0;
`endif // !`ifdef DEBUG_CNT


`ifdef DEBUG_REG   
   ktms_debug_reg#(.regs(4+nputs+ngets+1+64+1+12+4+2+2+3+1),.cr_depth(1),.mmioaddr(mmioaddr_dbg_reg),.mmioaddr_err_inj(mmioaddr_err_inj), .mmiobus_width(mmiobus_width)) idbg_reg
     (.clk(clk),.reset(reset),
      .i_mmiobus(mmiobus),
      .i_dbg_reg({s1_dbg_reg0,s1_dbg_reg1,s1_dbg_reg2,s1_dbg_reg3,s1_cnt_pend_d,s1_dbg_reg13,dma_latency,xlate_rd_max,xlate_wrt_max,fc_tag_latency,afu_tag_latency,wrt_rd_xlate_state,retried_cmd_cnt,arrin_fifo_latency,arrin_cycles}),
      .i_rega(s1_desc_rega),.i_regb(s1_desc_regb),.i_cnt_rsp_miss(s1_cnt_rsp_miss),
      .o_mmio_rd_v(dbgr_mmack),.o_mmio_rd_d(dbgr_mmdata),
      .o_errinj(s1_errinj)
      );
`else // !`ifdef DEBUG_REG
   assign dbgr_mmack = 1'b0;
   assign dbgr_mmdata = 64'd0;
`endif // !`ifdef DEBUG_REG

   // TODO - fix these, some sources are too big
   assign s1a_pipemon_v[0] = s1_cmd_v;
   assign s1a_pipemon_v[1] = s2_cmd_v;
   assign s1a_pipemon_v[2] = s3_cmd_v;
   assign s1a_pipemon_v[3] = s4_cmd_v;
   assign s1a_pipemon_v[5:4] = s4_cmda_v[0:1];
   assign s1a_pipemon_v[7:6] = s1_rsp_v[0:1]; // need one more bit for error response
   assign s1a_pipemon_v[8] = s1a_rsp_v;
   assign s1a_pipemon_v[9] = s2_rsp_v;
   assign s1a_pipemon_v[10] = s3_rsp_v;
   assign s1a_pipemon_v[11] = s4a_rsp_v;
   assign s1a_pipemon_v[12] = s5_rsp_v;
   assign s1a_pipemon_v[13] = s6a_rsp_v;
   assign s1a_pipemon_v[23:14] = ioasa_pipemon_v;
   assign s1a_pipemon_v[32:24] = rrq_pipemon_v;

   assign s1a_pipemon_v[37:33] = get_addr_v;
   assign s1a_pipemon_v[42:38] = get_data_v;
   assign s1a_pipemon_v[46:43] = put_addr_v;
   assign s1a_pipemon_v[50:47] = put_data_v;
   assign s1a_pipemon_v[54:51] = put_done_v;
   assign s1a_pipemon_v[63:55] = {9'd0};
   assign s1b_pipemon_v[4:0] = dma_pipemon_v;
   assign s1b_pipemon_v[7:5] = {3'd0};
   assign s1b_pipemon_v[11:8] = s6b_rsp_v;
   assign s1b_pipemon_v[33:12] = cmd_pipemon_v;
   assign s1b_pipemon_v[63:34] = {30'd0};


   assign s1a_pipemon_r[0] = s1_cmd_r;
   assign s1a_pipemon_r[1] = s2_cmd_r;
   assign s1a_pipemon_r[2] = s3_cmd_r;
   assign s1a_pipemon_r[3] = s4_cmd_r;
   assign s1a_pipemon_r[5:4] = s4_cmda_r[0:1];
   assign s1a_pipemon_r[7:6] = s1_rsp_r[0:1]; // need one more bit
   assign s1a_pipemon_r[8] = s1a_rsp_r;
   assign s1a_pipemon_r[9] = s2_rsp_r;
   assign s1a_pipemon_r[10] = s3_rsp_r;
   assign s1a_pipemon_r[11] = s4a_rsp_r;
   assign s1a_pipemon_r[12] = s5_rsp_r;
   assign s1a_pipemon_r[13] = s6a_rsp_r;
   assign s1a_pipemon_r[23:14] = ioasa_pipemon_r;
   assign s1a_pipemon_r[32:24] = rrq_pipemon_r;

   assign s1a_pipemon_r[37:33] = get_addr_r;
   assign s1a_pipemon_r[42:38] = get_data_r;
   assign s1a_pipemon_r[46:43] = put_addr_r;
   assign s1a_pipemon_r[50:47] = put_data_r;
   assign s1a_pipemon_r[54:51] = put_done_r;
   assign s1a_pipemon_r[63:55] = {9'd0};
   assign s1b_pipemon_r[4:0] = dma_pipemon_r;
   assign s1b_pipemon_r[7:5] = {3'd0};
   assign s1b_pipemon_r[11:8] = s6b_rsp_r;
   assign s1b_pipemon_r[33:12] = cmd_pipemon_r;
   assign s1b_pipemon_r[63:34] = {30'd0};
   
   ktms_afu_errmon#(.width(rm_err_width),.mmio_addr(mmioaddr_errmon),.mmiobus_width(mmiobus_width)) ierrmon
     (.clk(clk),.reset(reset),.i_mmiobus(mmiobus),
//      .i_rm_err(s1_rm_err),
      .i_rm_err(27'b0),
      .i_rm_cnt({{16-(fc_bufid_width+1){1'b0}},s1_rm_cnt[0:fc_bufid_width],{16-(fc_bufid_width+1){1'b0}},s1_rm_cnt[fc_bufid_width+1:2*(fc_bufid_width+1)-1]}),
      .i_rm_msk(gbl_reg7[47-(rm_err_width-1): 47]),
      .i_pipemon_v({s1b_pipemon_v,s1a_pipemon_v}),
      .i_pipemon_r({s1b_pipemon_r,s1a_pipemon_r}),
      .i_dma_status(s1_dma_status),
      .o_mmio_rd_v(err_mmack),.o_mmio_rd_d(err_mmdata),
      .o_afu_disable(s1_afu_disable)
      );

   wire croom_error_hld;
   assign freeze_on_error = (rcb_read_error_hld | rcb_write_error_hld);
   wire croom_error_in = s1_croom_err_v & s1_croom_err_r;
   base_vlat_en#(.width()) icroomerr(.clk(clk),.reset(reset),.din(croom_error_in),.q(croom_error_hld),.enable(s1_croom_err_v & s1_croom_err_r));

   wire wrt_or_rd_ctag = (ah_ctag[0:1] == 2'b01) | (ah_ctag[0:1] == 2'b10);
   wire wrt_or_read_ctag_v = ah_cvalid & wrt_or_rd_ctag;
   wire wrt_or_rd_rtag = (ha_rtag[0:1] == 2'b01) | (ha_rtag[0:1] == 2'b10);
   wire wrt_or_read_rtag_v = ha_rvalid & wrt_or_rd_rtag;

`ifdef DEBUG_BUF   
//   wire trace_v = (((iafu_ha_adr[10:23] == 14'b00000000001110) & iafu_ha_rnw & s2_mmack) | ((iafu_ha_adr[10:23] == 14'b00000000001000) & ~iafu_ha_rnw & s2_mmack)) & ~croom_error_hld;
//   wire trace_v = xlate_wrt_lt_4K | xlate_wrt_lt_16K;
   wire trace_v = get_data_v[channels] & get_data_r[channels];


   ktms_trace_buffer#(.addr_width(10),.width(2),.mmiobus_width(mmiobus_width),.mmio_base(mmioaddr_tracebuffer)) itrace_buffer
     (.clk(clk),.reset(reset),.i_mmiobus(mmiobus),
      .i_v(trace_v),
      .i_d({get_data_d[130*channels:130*(channels+1)-3]}),
      .o_mmio_ack(tbf_mmack),
      .o_mmio_data(tbf_mmdata),
      .o_wa(tbf_wa)
      );

   ktms_tag_trace_buffer#(.addr_width(7),.width(2),.mmiobus_width(mmiobus_width),.mmio_base(mmioaddr_pslrdabuffer)) itag_pslrda_trace_buffer
     (.clk(clk),.reset(reset),.i_mmiobus(mmiobus),
      .i_v( wrt_or_read_ctag_v),
      .i_ctag(ah_ctag[1:7]),
      .i_d({ah_cea,32'b0,lr_timestamp}),
      .o_mmio_ack(pslrdatb_mmack),
      .o_mmio_data(pslrdatb_mmdata)
      );

   ktms_tag_trace_buffer#(.addr_width(6),.width(7),.mmiobus_width(mmiobus_width),.mmio_base(mmioaddr_pslrddbuffer)) itag_pslrdd_trace_buffer  
     (.clk(clk),.reset(reset),.i_mmiobus(mmiobus),
      .i_v(hd0_cpl_valid & ~error_status_hld & (hd0_cpl_size == 10'h080)),
      .i_ctag(hd0_cpl_utag[4:9]),
      .i_d(hd0_cpl_data[0:7*64-1]),
      .o_mmio_ack(pslrddtb_mmack),
      .o_mmio_data(pslrddtb_mmdata)
      );                               
  


`else // !`ifdef DEBUG_BUF
   assign tbf_mmack = 1'b0;
   assign tbf_mmdata = 64'b0;
   assign pslrdatb_mmack = 1'b0;
   assign pslrdatb_mmdata = 64'b0;
   assign pslrddtb_mmack = 1'b0;
   assign pslrddtb_mmdata = 64'h0;
`endif // !`ifdef DEBUG_BUF
  
   wire [0:127] set_xlate_tag;
   wire [0:127] reset_xlate_tag;
   
base_vlat_sr#(.width(128)) iea_valid (.clk(clk),.reset(reset),.set(set_xlate_tag),.rst(reset_xlate_tag),.q(wrt_rd_xlate_state));

   base_decode#(.enc_width(7),.dec_width(128)) iset_tag(.en(wrt_or_read_ctag_v),.din(ah_ctag[1:7]),.dout(set_xlate_tag));
   base_decode#(.enc_width(7),.dec_width(128)) ireset_tag(.en(wrt_or_read_rtag_v),.din(ha_rtag[1:7]),.dout(reset_xlate_tag));



   


   wire 			     s1_perfmon_v;
   wire [0:tag_width-1] 	     s1_perfmon_tag;
			     
   ktms_afu_track#(.mmioaddr(mmioaddr_track),.mmiobus_width(mmiobus_width),.tag_width(tag_width-1),.ea_width(ea_width),.ctxtid_width(ctxtid_width),.lba_width(lba_width), //added -1 kch 
		   .chnlid_width(chnlid_width),.lidx_width(lidx_width),.rslt_width(rslt_width),
		   .afu_rc_width(afu_rc_width),.afu_erc_width(afu_erc_width),.fcstat_width(fcstat_width),.fcxstat_width(fcxstat_width),.scstat_width(scstat_width),.reslen_width(reslen_width)) iafu_track
     (.clk(clk),.reset(reset),.i_mmiobus(mmiobus),
      .i_cp0_v(trk0_v),.i_cp0_tag(trk0_tag[0:tag_width-2]),.i_cp0_ts(trk0_ts),
      .i_cp1_v(s1_cmd_v),.i_cp1_tag(s1_cmd_tag[0:tag_width-2]),.i_cp1_ts(lr_timestamp),.i_cp1_ctxt(s1_cmd_rcb_ctxt),.i_cp1_ea(s1_cmd_rcb_ea),.i_cp1_lba(s1_cmd_lba),.i_cp1_rc(s1_cmd_rc), // added s1_cmd_rc
      .i_cpvrh_v(trk3_v),.i_cpvrh_tag(trk3_tag[0:tag_width-2]),.i_cpvrh_d(trk3_d),
      .i_cp2_v(s3_cmd_v),.i_cp2_tag(s3_cmd_afu_tag[0:tag_width-2]),.i_cp2_ts(lr_timestamp),.i_cp2_lba(s3_cmd_lba),.i_cp2_chnl(s3_cmd_chnl),.i_cp2_lidx(s3_cmd_lidx),.i_cp2_vrh(s3_cmd_vrh),.i_cp2_rc(s3_cmd_rc),
      .i_cp3_v(s4_cmd_v),.i_cp3_tag(s4_cmd_afu_tag[0:tag_width-2]),.i_cp3_lun(s4_cmd_lun),
      
      .i_cp4_v(s3_rsp_v),.i_cp4_tag(s3_rsp_afu_tag[0:tag_width-2]),.i_cp4_ts(lr_timestamp),.i_cp4_stat(s3_rsp_stat),
      .i_cp5_v(s6a_rsp_v),.i_cp5_tag(s6_rsp_afu_tag[0:tag_width-2]),.i_cp5_ts(lr_timestamp),
      .i_freeze_on_error(freeze_on_error & freeze_on_error_q),
      .o_error_status_hld(error_status_hld),
      .o_mmio_ack(trk_mmack),.o_mmio_data(trk_mmdata));

   wire 			     s6_rsp_act = s6a_rsp_v & s6a_rsp_r;
   
   ktms_afu_perfmon#(.mmioaddr(mmioaddr_perfmon),.mmiobus_width(mmiobus_width),.tag_width(tag_width-1),.stall_counters(stall_counters)) iafu_perfmon
     (.clk(clk),.reset(reset),.i_mmiobus(mmiobus),
      .i_time(lr_timestamp),
      .i_st_v(trk0_v),.i_st_tag(trk0_tag[0:tag_width-2]),
`ifdef SIM
      .i_st_ts(trk0_ts[32:63]),
`else
      .i_st_ts(trk0_ts[32:63]),
`endif

      .i_s1_v(s1_perfmon_v),.i_s1_tag(s1_perfmon_tag[0:tag_width-2]),
      .i_ed_v(s6_rsp_act),.i_ed_tag(s6_rsp_afu_tag[0:tag_width-2]),.i_ed_rnw(s6_rsp_rnw),
      .i_stall_cnt_v(stallcount_v),
      .i_stall_cnt_r(stallcount_r),
      .o_mmio_ack(stl_mmack),.o_mmio_data(stl_mmdata));
   

   ktms_afu_cpc#
     (.mmiobus_width(mmiobus_width),.ctxtid_width(ctxtid_width),.ctxtcap_width(ctxtcap_width),.mmioaddr_cpc(mmioaddr_cpc),.mmioaddr_mbox(18)) icpc
       (.clk(clk),.reset(reset),
	.i_mmiobus(mmiobus),
	.i_cfg_mbxclr(gbl_reg7[59]),
	.i_ctxt_add_v(s1_ctxt_add_v),
	.i_ctxt_rmv_v(s1_ctxt_rmv_v),
	.i_ctxt_upd_d(s1_ctxt_upd_d),
        .i_cfg_capwprot_override(gbl_reg7[1]),
	.o_cap_wr_v(s1_cap_wr_v),
	.o_cap_wr_ctxt(s1_cap_wr_ctxt),
	.o_cap_wr_d(s1_cap_wr_d),
	.o_mmio_rd_v(cpc_mmack),
	.o_mmio_rd_d(cpc_mmdata),
        .o_perror(o_perror[67:69])
	);

   wire [0:msinum_width-1] 	     s1_intr1_msi;
   wire [0:ctxtid_width-1] 	     s1_intr1_ctxt;
   wire [0:tstag_width-1] 	     s1_intr1_tstag = {tstag_width{1'b0}};
   wire 			     s1_intr1_tstag_v = 1'b0;

   wire 				     s3_ctxt_rst_v;
   wire [0:ctxtid_width-1] 		     s3_ctxt_rst_id;
   
   ktms_afu_int#
     (.mmiobus_width(mmiobus_width),
      .mmio_ht_addr(0),
      .mmio_cpc_addr(mmioaddr_cpc),
      .ctxtid_width(ctxtid_width),
      .msi_width(msinum_width),
      .sintrid_width(sintrid_width),
      .sintr_croom(sintr_croom),
      .croom_width(croom_width),
      .tstag_width(tstag_width),
      .nintrs(5)
      ) isint
       (.clk(clk),.reset(reset),.i_mmiobus(mmiobus),
	.i_ctxt_add_v(s1_ctxt_add_v),.i_ctxt_add_d(s1_ctxt_upd_d),
	.o_mmio_rd_v(int_mmack),
	.o_mmio_rd_d(int_mmdata),
	.i_croom_err_v(s1_croom_err_v),
	.i_croom_err_r(s1_croom_err_r),
	.i_croom_err_ctxt(s1_croom_err_ctxt),

	.i_ctxt_rst_ack_v(s3_ctxt_rst_v),
	.i_ctxt_rst_ack_id(s3_ctxt_rst_id),

	.o_ctxt_rst_v(s1_ctxt_rst_v),
	.o_ctxt_rst_r(s1_ctxt_rst_r),
	.o_ctxt_rst_id(s1_ctxt_rst_id),
	
	
        .i_sintr_v(s6c_rsp_v[1]),
	.i_sintr_r(s6c_rsp_r[1]),
	.i_sintr_ctxt(s6_rsp_ctxt),
	.i_sintr_id(s6_rsp_sintr_id),
	.i_sintr_tstag(s6_rsp_afu_tag),
	.i_croom_we(croom_we),
	.i_croom_wa(croom_wa),
	.i_croom_wd(croom_wd),

	.o_tscheck_v(s1_tscheck_v),
	.o_tscheck_r(s1_tscheck_r),
	.o_tscheck_tstag(s1_tscheck_tstag),
	.o_tscheck_ctxt(s1_tscheck_ctxt),
	.i_tscheck_v(s1_tscheck_rsp_v),
	.i_tscheck_r(s1_tscheck_rsp_r),
	.i_tscheck_ok(s1_tscheck_rsp_ok),

	.o_intr_r(s1_intr1_r),
	.o_intr_v(s1_intr1_v),
	.o_intr_ctxt(s1_intr1_ctxt),
	.o_intr_msi(s1_intr1_msi),
	.o_rrq_st_we(s1_rrq_st_we),
	.o_rrq_ed_we(s1_rrq_ed_we),
	.o_rrq_ctxt(s1_rrq_ctxt),
	.o_rrq_wd(s1_rrq_wd),
	.o_ec_set(s1_ec_set),
	.o_ec_rst(s1_ec_rst),
	.o_ec_id(s1_ec_id),
	
//	.o_dbg_cnt_inc(dbg_cnt_inc[16:20]),
	.o_dbg_cnt_inc(),
        .o_perror(o_perror[70:71])
        );

//  assign dbg_cnt_inc[16:20] = {xlate_rd_lt_32,xlate_rd_lt_512,xlate_rd_lt_4K,xlate_rd_lt_16K,xlate_rd_gt_16K};
   wire                              s1a_irq_v, s1a_irq_r;
   wire                              s1_irq_tstag_v;
   wire [0:tstag_width-1]            s1_irq_tstag;
   wire [0:ctxtid_width-1] 	     s1_irq_ctxt;
   wire [0:msinum_width-1] 	     s1_irq_src;
   
   base_arr_mux#(.ways(3),.width(1+tstag_width+ctxtid_width+msinum_width)) iintr_mux
     (.clk(clk),.reset(reset),
      .i_v({s1_intr0_v,s1_intr1_v,s1_intr2_v}),
      .i_r({s1_intr0_r,s1_intr1_r,s1_intr2_r}),
      .i_d({s1_intr0_tstag_v, s1_intr0_tstag,s1_intr0_ctxt,s1_intr0_msi,
            s1_intr1_tstag_v, s1_intr1_tstag,s1_intr1_ctxt,s1_intr1_msi,
            s1_intr2_tstag_v, s1_intr2_tstag,s1_intr2_ctxt,s1_intr2_msi}),
      .o_v(s1a_irq_v),
      .o_r(s1a_irq_r),
      .o_d({s1_irq_tstag_v, s1_irq_tstag, s1_irq_ctxt, s1_irq_src}),
      .o_sel()
      );




   wire 			     s2_irq_v, s2_irq_r;
   base_alatch_burp#(1+tstag_width+ctxtid_width+msinum_width) iintr_lat
     (.clk(clk),.reset(reset),
      .i_v(s1a_irq_v),.i_r(s1a_irq_r),.i_d({s1_irq_tstag_v, s1_irq_tstag, s1_irq_ctxt, s1_irq_src}),
      .o_v(s2_irq_v),.o_r(s2_irq_r),
      .o_d({irq_tstag_v, irq_tstag, irq_ctxt,irq_src})
      );

   // don't send src=0   
   base_afilter iintr_fltr(.i_v(s2_irq_v),.i_r(s2_irq_r),.o_v(irq_v),.o_r(irq_r),.en(|irq_src));

   ktms_afu_timeout#(.tag_width(tag_width),.ctxtid_width(ctxtid_width),.rc_width(afu_rc_width),.channels(channels),.rslt_width(rslt_width),.aux_width(chnlid_width)) itimeout
     (.clk(clk),.reset(reset),
      .i_timestamp(cycle_count),
      .i_cmd_r(s1_to_r),
      .i_cmd_v(s1_to_v),
      .i_cmd_tag(s1_to_tag),
      .i_cmd_flg(s1_to_flg),
      .i_cmd_d(s1_to_d),
      .i_cmd_ts(s1_to_ts),
      .i_cmd_sync(s1_to_sync),
      .i_cmd_ok(s1_to_ok),

      // cancel timeouts as soon as we have a response

      .i_cmpl_v(s2_rsp_v),
      .i_cmpl_r(s2_rsp_r),
      .i_cmpl_tag(s2_rsp_afu_tag),
      .i_cmpl_rslt(s2_rsp_stat),
      .i_cmpl_aux(s2_rsp_chnl),

     // cancel timeouts as soon as tag is retried 

       .i_reset_afu_cmd_tag_v(reset_afu_cmd_tag_v),
       .i_reset_afu_cmd_tag_r(reset_afu_cmd_tag_r),
       .i_reset_afu_cmd_tag(reset_afu_cmd_tag),


      .o_cmpl_v(s3_rsp_v),
      .o_cmpl_r(s3_rsp_r),
      .o_cmpl_tag(s3_rsp_afu_tag),
      .o_cmpl_rslt(s3_rsp_stat),
      .o_cmpl_aux(s3_rsp_chnl),
      .o_cmpl_tagret(s3_rsp_tagret),
      .o_cmpl_nocmpl(s3_rsp_nocmpl),

      .i_fcreq_v(s1_tochk_v),
      .i_fcreq_r(s1_tochk_r),
      .i_fcreq_tag(s1_tochk_tag),
      .i_fcreq_rnw(s1_tochk_rnw),
      
      .o_fcreq_v(s2_tochk_v),
      .o_fcreq_ok(s2_tochk_ok),

      .o_perfmon_v(s1_perfmon_v),
      .o_perfmon_tag(s1_perfmon_tag),

      // these transactions timed out
      .o_abort_r(1'b1),
      .o_abort_v(s1_timeout_v),
      .o_abort_tag(s1_timeout_id),


      .i_ctxt_add_v(s1_ctxt_add_v),.i_ctxt_add_d(s1_ctxt_upd_d),

      .i_cr_v(s2_ctxt_rst_v),.i_cr_id(s2_ctxt_rst_id),
      .o_cr_v(s3_ctxt_rst_v),
      .o_cr_id(s3_ctxt_rst_id),
      .o_s1_perror(timeout_s1_perror),
      .i_timeout_msk_pe(gbl_reg11[61]),
      .o_perror(o_perror[72])
      );

endmodule // stream_app



