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


module capi_dma_mc_top_plus#  
  (
   parameter uid_st = 0,
   parameter cputs = 0,
   parameter cgets = 0,   
   parameter puts = 1,
   parameter gets = 1,
   parameter ssize_width = 32,
   parameter mmio_base = 0,
   parameter tag_width=10, 
   parameter ctag_width=8,   
   parameter tsize_width =12,
   parameter ea_width = 65,
   parameter ctxtid_width = 10 ,  
   parameter tstag_width = 14,
   parameter irqsrc_width = 11,
   parameter beat_width = 3,
   parameter beat_512_width = 5,
   parameter data_latency = 4,
   parameter rc_width = 8,
   parameter afuerr_width = 64,
   parameter mmio_timeout_width=12,
   parameter cto_width=1,
   parameter ctxt_add_acks=1,
   parameter ctxt_rmv_acks=1,
   parameter ctxt_trm_acks=1,
   
   parameter uid_width = 5,         // unit id - up to 32 units
   parameter sid_width = 3,
   parameter csid_width = uid_width+sid_width,


   parameter wdata_addr_width = tag_width+beat_width,
   parameter rdata_addr_width = tag_width+beat_width,
   parameter wdata_512_addr_width = tag_width+beat_512_width,
   parameter rdata_512_addr_width = tag_width+beat_512_width,
   
   parameter mmiobus_awidth = 29,  
   parameter mmiobus_width = mmiobus_awidth+65, 
   parameter mmioaddr_bad_rsp=0,
   parameter [0:7] psl_rsp_cinv=0,

   // calculated parameters
   parameter nputs = ((puts+cputs) == 0) ? 1 : (puts+cputs),
   parameter ngets = ((gets+cgets) == 0) ? 1 : (gets+cgets),
   parameter npadrs = (puts == 0) ? 1 : puts,
   parameter ngadrs = (gets == 0) ? 1 : gets,
   parameter pea_width = ea_width-12,
   parameter cnt_rsp_width = pea_width*2+ctxtid_width+ctag_width+4,
   parameter [0:nputs-1] ignore_tstag_inv = 0 // if 1, this put engine will write even if tstag is marked invalid (but not if the timestamp is out of date)
   )

   (
    input 				clk,
    input [0:cto_width-1] 		i_cont_timeout,
    input 				i_disable,
    input [0:2] 			i_ah_cabt,
    input 				i_paren,
    input 				i_cfg_ctrm_wait,

    input [0:mmio_timeout_width-1] 	i_mmio_timeout_d,
    output [0:63] 			o_status,
    output [0:(gets+puts)*64-1] 	o_cnt_pend_d, 

    output 				o_bad_rsp_v,
    output [127:0] 			o_bad_rsp_d,
    
    input 				i_tstag_issue_v,
    input [0:tstag_width-1] 		i_tstag_issue_id,
    input [0:63] 			i_tstag_issue_d,

    // invalidate a tstag 
    input 				i_tstag_inv_v,
    input [0:tstag_width-1] 		i_tstag_inv_id, 

    output 				i_tscheck_r,
    input 				i_tscheck_v,
    input [0:tstag_width-1] 		i_tscheck_tstag,
    input [0:ctxtid_width-1] 		i_tscheck_ctxt,

    output 				i_ctxt_rst_r,
    input 				i_ctxt_rst_v,
    input [0:ctxtid_width-1] 		i_ctxt_rst_id,

    output 				o_ctxt_rst_v,
    output [0:ctxtid_width-1] 		o_ctxt_rst_id,


    input 				i_cnt_rsp_v,
    input [0:cnt_rsp_width-1] 		i_cnt_rsp_d,
    output 				o_cnt_rsp_miss,

    input 				o_tscheck_r,
    output 				o_tscheck_v,
    output 				o_tscheck_ok,
    
    output [0:gets+puts+4-1] 		o_rm_err,
    output [4:0] 			o_pipemon_v,
    output [4:0] 			o_pipemon_r,

    output [0:ngadrs-1] 		get_r,
    input [0:ngadrs-1] 			get_v,
    input [0:(ea_width*ngadrs)-1] 	get_d_addr,
    input [0:(ctxtid_width*ngadrs)-1] 	get_d_ctxt,
    input [0:(ssize_width*ngadrs)-1] 	get_d_size,
    input [0:(tstag_width*ngadrs)-1] 	get_d_tstag,
   
    input [0:ngets-1] 			get_data_r,
    output [0:ngets-1] 			get_data_v,
    output [0:(130*ngets)-1] 		get_data_d,
    output [0:(4*ngets)-1] 		get_data_c,
    output [0:ngets-1] 			get_data_e,
    output [0:ngets*rc_width-1] 	get_data_rc,
    output [0:ngets*ssize_width-1] 	get_data_bcnt,
    
    input [0:npadrs-1] 			put_addr_v,
    input [0:(ea_width * npadrs)-1] 	put_addr_d_ea,
    input [0:(ctxtid_width * npadrs)-1] put_addr_d_ctxt,
    input [0:(tstag_width*npadrs)-1] 	put_addr_d_tstag,
    output [0:npadrs-1] 		put_addr_r,
	      
    output [0:nputs-1] 			put_data_r,
    input [0:nputs-1] 			put_data_v,
    input [0:(130*nputs)-1] 		put_data_d, 
    input [0:nputs-1] 			put_data_e,
    input [0:(4*nputs)-1] 		put_data_c,
    input [0:nputs-1] 			put_data_f,
    output [0:nputs-1] 			put_done_v,
    input [0:nputs-1] 			put_done_r,
    output [0:nputs*rc_width-1] 	put_done_rc,
    output [0:nputs*ssize_width-1] 	put_done_bcnt,

    input [0:ctxt_add_acks-1] 		i_ctxt_add_ack_v,
    input [0:ctxt_rmv_acks-1] 		i_ctxt_rmv_ack_v,
    input [0:ctxt_trm_acks-1] 		i_ctxt_trm_ack_v,

    output 				o_ctxt_add_v,
    output 				o_ctxt_trm_v,
    output 				o_ctxt_rmv_v,
    output [0:ctxtid_width-1] 		o_ctxt_upd_d,

    input 				i_reset,
    input 				i_app_done,
    input                               i_fatal_error,
    input [0:afuerr_width-1] 		i_app_error, 
    input 				i_irq_v,
    output 				i_irq_r,
    input [0:ctxtid_width-1] 		i_irq_ctxt,
    input [0:tstag_width-1] 		i_irq_tstag,
    input 				i_irq_tstag_v,
    input [0:irqsrc_width-1] 		i_irq_src,
    
    
    output 				o_intr_done,
    output [0:43] 	                o_dbg_cnt_inc,

    output 				ah_paren,
    
    input 				ha_jval, // A valid job control command is present
    input [0:7] 			ha_jcom, // Job control command opcode
    input 				ha_jcompar,
    input [0:63] 			ha_jea, // Save/Restore address  
    input 				ha_jeapar,
    input [0:4] 			ha_lop, //   lpc capp ttype  not used
    input 				ha_loppar,
    input [0:6] 			ha_lsize, //   lpc size/secondary ttype
    input [0:11] 			ha_ltag, //   lpc command tag
    output 				ah_ldone, //   lpc operation is done
    output [0:11] 			ah_ldtag, //   lpc tag identifying done operation ok 
    output 				ah_ldtagpar,
    output [0:7] 			ah_lroom, //   how many LPC/Internal commands
    output 				ah_jrunning, // Accelerator is running
    output 				ah_jdone, // Accelerator is finished
    output [0:63] 			ah_jerror, // Accelerator error code. 0 = success
    output 				ah_tbreq, // timebase request (not used)
    output 				ah_jyield, // Accelerator wants to stop

   // Accelerator Command Interface
    output 				ah_cvalid, // A valid command is present
    output [0:7] 			ah_ctag, // request id 
    output 				ah_ctagpar,
    output [0:12] 			ah_com, // command PSL will execute   
    output 				ah_compar,
    output [0:2] 			ah_cpad, // prefetch inattributes
    output [0:2] 			ah_cabt, // abort if translation intr is generated
    output [0:63] 			ah_cea, // Effective byte address for command     
    output 				ah_ceapar,
    output [0:11] 			ah_csize, // Number of bytes
    output [0:15] 			ah_cch, // context handle
    output 				ah_jcack,
    input [0:7] 			ha_croom, // Commands PSL is prepared to accept

// DMA Interface 

    output 		        	d0h_dvalid, 
    output [0:9] 			d0h_req_utag, 
    output [0:8] 			d0h_req_itag, 
    output [0:2] 			d0h_dtype,  
    output [0:9] 			d0h_dsize, 
    output [0:5] 			d0h_datomic_op, 
    output       			d0h_datomic_le, 
    output [0:1023]                     d0h_ddata,

    input       			hd0_sent_utag_valid_psl, 
    input [0:9]      			hd0_sent_utag_psl, 
    input [0:2]      			hd0_sent_utag_sts_psl, 

    input                               hd0_cpl_valid,
    input [0:9]                         hd0_cpl_utag,
    input [0:2]                         hd0_cpl_type,
    input [0:6]                         hd0_cpl_laddr,
    input [0:9]                         hd0_cpl_byte_count,
    input [0:9]                         hd0_cpl_size,
    input [0:1023]                      hd0_cpl_data,



   //x PSL Response Interface
    input 				ha_rvalid, // A response is present
    input [0:7] 			ha_rtag, // Accelerator generated request ID 
    input 				ha_rtagpar,  
    input [0:8] 		        ha_rditag, // Accelerator generated request ID
    input 				ha_rditagpar,  
    input [0:7] 			ha_response, // response code
    input [0:8] 			ha_rcredits, // twos compliment number of credits
    input [0:1] 			ha_rcachestate, // Resultant Cache State
    input [0:12] 			ha_rcachepos, // Cache location id


   // Accelerator MMIO Interface
    input 				ha_mmval, // A valid MMIO is present
    input 				ha_mmrnw, // 1 = read, 0 = write
    input 				ha_mmdw, // 1 = doubleword, 0 = word
    input [0:23] 			ha_mmad, // mmio address
    input 				ha_mmadpar,
    input 				ha_mmcfg, // mmio is to afu descriptor space
    input [0:63] 			ha_mmdata, // Write data
    input 				ha_mmdatapar,
    output 				ah_mmack, // Write is complete or Read is valid
    output [0:63] 			ah_mmdata, // Read data
    output 				ah_mmdatapar,
    output 				o_reset,

    input 				i_mmack,
    input [0:63] 			i_mmdata,
    output [0:mmiobus_width-1] 		o_mmiobus, // DATA COMES ONE CYCLE AFTER ADDRESS AND VALID
    output[0:41]			o_perror,
    output[0:17+1+(gets*5)+6+(puts*3)-1]                        o_s1_perror,
    output  [0:ctxtid_width+7]          o_dbg_dma_retry_s0,
    input                               i_dma_retry_msk_pe025,
    input                               i_dma_retry_msk_pe34,
    input                               i_ah_cch_msk_pe,
    input                               i_perror_total,
    input                               i_error_status_hld,
    output[0:(((5+8+7)*3)+4)*64-1]                   o_latency_d,
    input                               i_drop_wrt_pckts,
    output                              o_xlate_start,         
    output                              o_xlate_end,
    output [0:6]                        o_xlate_ctag,
    output [0:6]                        o_xlate_rtag,
    output [0:63]                       o_xlate_ea,
    input                               i_gate_sid,
    input                               i_reset_lat_cntrs

    );

   wire 			     reset;
    wire [0:9]                        gated_utag;
    wire                              gated_utag_val; 
    wire        			hd0_sent_utag_valid = hd0_sent_utag_valid_psl | gated_utag_val ; 
    wire [0:9]      			hd0_sent_utag = hd0_sent_utag_valid_psl ? hd0_sent_utag_psl : gated_utag;
    wire [0:2]      			hd0_sent_utag_sts = hd0_sent_utag_valid_psl ? hd0_sent_utag_sts_psl : 3'b001;  
    wire                              gated_utag_taken = hd0_sent_utag_valid_psl ? 1'b0 : gated_utag_val; 


   wire xlate_cmd_start = ah_cvalid & ((ah_ctag[0:1] == 2'b10) | (ah_ctag[0:1] == 2'b01));
   wire xlate_write_start = ah_cvalid & ((ah_ctag[0:1] == 2'b10));
   wire xlate_cmd_end = ha_rvalid & ((ha_rtag[0:1] == 2'b10) | (ha_rtag[0:1] == 2'b01));
   wire [0:63] xlate_sum ;
   wire [0:63] xlate_complete;
   wire [0:9] xlate_active;

   nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_xlate (.reset(reset),.clk(clk),
                                                                  .incr(xlate_cmd_start), .decr(xlate_cmd_end), .clr(i_reset_lat_cntrs),
                                                                  .active_cnt(xlate_active), .complete_cnt(xlate_complete), .sum(xlate_sum), .clr_sum(i_reset_lat_cntrs));

   wire xlate_read_end = ha_rvalid & (ha_rtag[0:1] == 2'b01);
   wire dma_read_start = d0h_dvalid & (d0h_req_utag[0:3] == 4'b0001);
   wire [0:63] dma_xlate_read_sum ;
   wire [0:63] dma_xlate_read_complete;
   wire [0:9] dma_xlate_read_active;

   nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_xlate_read (.reset(reset),.clk(clk),
                                                                  .incr(xlate_read_end), .decr(dma_read_start), .clr(i_reset_lat_cntrs),
                                                                  .active_cnt(dma_xlate_read_active), .complete_cnt(dma_xlate_read_complete), .sum(dma_xlate_read_sum), .clr_sum(i_reset_lat_cntrs));

   wire dma_read_end = hd0_cpl_valid & (hd0_cpl_utag[0:3] == 4'b0001) & (hd0_cpl_byte_count == hd0_cpl_size) & (hd0_cpl_type == 3'b000);
   wire [0:63] dma_read_sum ;
   wire [0:63] dma_read_complete;
   wire [0:9] dma_read_active;

   nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_dma_read (.reset(reset),.clk(clk),
                                                                  .incr(dma_read_start), .decr(dma_read_end), .clr(i_reset_lat_cntrs),
                                                                  .active_cnt(dma_read_active), .complete_cnt(dma_read_complete), .sum(dma_read_sum), .clr_sum(i_reset_lat_cntrs));

   wire xlate_write_end = ha_rvalid & (ha_rtag[0:1] == 2'b10);
   wire dma_write_start = d0h_dvalid & (d0h_req_utag[0:3] == 4'b0010) & (d0h_dtype == 3'b001) ;
   wire [0:63] dma_xlate_write_sum ;
   wire [0:63] dma_xlate_write_complete;
   wire [0:9] dma_xlate_write_active;
   assign o_xlate_start = xlate_cmd_start;
   assign o_xlate_end = xlate_cmd_end;
   assign o_xlate_ctag = ah_ctag[1:7];
   assign o_xlate_rtag = ha_rtag[1:7];
   assign o_xlate_ea = ah_cea;

   nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_xlate_write (.reset(reset),.clk(clk),
                                                                  .incr(xlate_write_end), .decr(dma_write_start), .clr(i_reset_lat_cntrs),
                                                                  .active_cnt(dma_xlate_write_active), .complete_cnt(dma_xlate_write_complete), .sum(dma_xlate_write_sum), .clr_sum(i_reset_lat_cntrs));

   wire dma_write_end = hd0_sent_utag_valid & (hd0_sent_utag[0:3] == 4'b0010);
   wire [0:63] dma_write_sum ;
   wire [0:63] dma_write_complete;
   wire [0:9] dma_write_active;

   nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_dma_write (.reset(reset),.clk(clk),
                                                                  .incr(dma_write_start), .decr(dma_write_end), .clr(i_reset_lat_cntrs),
                                                                  .active_cnt(dma_write_active), .complete_cnt(dma_write_complete), .sum(dma_write_sum), .clr_sum(i_reset_lat_cntrs));
   wire [0:((7*3)+4)*64-1]                  write_tag_latency;
      wire [0:8*3*64-1]                read_tag_latency; 

   assign o_latency_d = {xlate_sum,xlate_complete,54'b0,xlate_active,
                         dma_xlate_read_sum,dma_xlate_read_complete,54'b0,dma_xlate_read_active,
                         dma_read_sum,dma_read_complete,54'b0,dma_read_active,
                         dma_xlate_write_sum,dma_xlate_write_complete,54'b0,dma_xlate_write_active,
                         dma_write_sum,dma_write_complete,54'b0,dma_write_active,
                         read_tag_latency,write_tag_latency};

   wire 				us_timer;  // pulse once per us.
   wire [0:7] 				us_timer_d;
   base_vlat#(.width(8)) ius_timer_dlat(.clk(clk),.reset(reset),.din(us_timer_d+1'd1),.q(us_timer_d));
`ifdef SIM
     base_vlat#(.width(1)) ius_timer_vlat(.clk(clk),.reset(reset),.din(us_timer_d[7]),.q(us_timer));
`else
     base_vlat#(.width(1)) ius_timer_vlat(.clk(clk),.reset(reset),.din(us_timer_d==8'd0),.q(us_timer));
`endif
   
   wire [0:6] 				hld_perror;
   wire [0:6] 				hld_perror_msk = hld_perror & {6'b11111,~i_ah_cch_msk_pe}; 
   wire                        capi_jctrl_s1_perror;
   wire [0:(gets*5-1)]                       capi_get_s1_perror;
   wire [0:5]                 dma_retry_s1_perror;
   wire [0:(puts*3-1)]               capi_put_s1_perror;
   assign o_s1_perror = {hld_perror,capi_jctrl_s1_perror,capi_get_s1_perror,dma_retry_s1_perror,capi_put_s1_perror} ;

   localparam rd_req_width = tag_width+sid_width+1+1+(1+tstag_width)+ctxtid_width+ea_width+tsize_width;  
   localparam wr_req_width = rd_req_width;
   localparam gbl_req_width = ctag_width+1+csid_width+1+1+tstag_width+ctxtid_width+tsize_width+ea_width;
   localparam rsp_width = rc_width+sid_width+tstag_width+tag_width;
   
   assign ah_paren = i_paren;


   // check mmio data parity
   wire [0:6] 				s1_perror;
   capi_parcheck#(.width(64)) imdata_pcheck(.clk(clk),.reset(reset),.i_v(ha_mmval & ~ha_mmrnw),.i_d(ha_mmdata),.i_p(ha_mmdatapar),.o_error(s1_perror[0]));
   capi_parcheck#(.width(24)) immad_pcheck(.clk(clk),.reset(reset),.i_v(ha_mmval),.i_d(ha_mmad),.i_p(ha_mmadpar),.o_error(s1_perror[1]));
   base_vlat_sr#(.width(7)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(7'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror_msk),.q(o_perror[0]));

   
   wire [0:63] 		       cycle_cnt;
   base_vlat#(.width(64)) icycle_lat(.clk(clk),.reset(reset),.din(cycle_cnt+64'd1),.q(cycle_cnt));

   // MMIO STUFF
  
   wire [0:mmiobus_width-1] ha_mmiobus = {ha_mmval,ha_mmcfg,ha_mmrnw,ha_mmdw,ha_mmad,ha_mmadpar,ha_mmdata,ha_mmdatapar};
   wire [0:mmiobus_width-1] s1_mmiobus;

   base_vlat#(.width(1))             immiobus_s1vlat(.clk(clk),.reset(reset),.din(ha_mmiobus[0]),.q(s1_mmiobus[0]));
   base_vlat#(.width(mmiobus_width-1)) immiobus_s1lat(.clk(clk),.reset(reset),.din(ha_mmiobus[1:mmiobus_width-1]),.q(s1_mmiobus[1:mmiobus_width-1]));

   // address only portion 
   wire [0:mmiobus_awidth-1] s1_mmioabus = s1_mmiobus[0:mmiobus_awidth-1];
   wire [0:64]               s1_mmiodbus = s1_mmiobus[mmiobus_awidth:mmiobus_width-1]; 
   wire 		       s1_mmval, s1_mmcfg, s1_mmrnw, s1_mmdw, s1_mmadpar; 
   wire [0:24] 		       s1_mmad;   
   assign {s1_mmval, s1_mmcfg, s1_mmrnw, s1_mmdw, s1_mmad, s1_mmadpar} = s1_mmioabus; 

   wire [0:64] 		       s2_mmiodbus; 
   wire                        s2_mmval;
   base_vlat#(.width(1+65)) immibus_s2lat(.clk(clk),.reset(reset),.din({s1_mmval,s1_mmiodbus}),.q({s2_mmval,s2_mmiodbus})); 
   assign o_mmiobus = {s1_mmioabus,s2_mmiodbus}; // data comes one cycle late
   capi_parcheck#(.width(64)) s2_mmiodbus_pcheck(.clk(clk),.reset(reset),.i_v(s2_mmval),.i_d(s2_mmiodbus[0:63]),.i_p(s2_mmiodbus[64]),.o_error(s1_perror[2]));
   capi_parcheck#(.width(24)) s1_mmioabus_pcheck(.clk(clk),.reset(reset),.i_v(s1_mmval),.i_d(s1_mmioabus[0:23]),.i_p(s1_mmioabus[24]),.o_error(s1_perror[3]));
      

   wire [0:63] s2_mmio_data = i_mmdata;

   wire [0:63] s3_mmdata;
   wire        s3_mmack;
	
   base_vlat#(.width(1)) iah_mmack(.clk(clk),.reset(reset),.din(i_mmack),.q(s3_mmack));
   base_vlat#(.width(64)) iah_mmdat(.clk(clk),.reset(1'b0),.din(s2_mmio_data),.q(s3_mmdata));

   capi_mmio_timeout#(.mmiobus_width(mmiobus_width),.mmio_addr_width(25),.timeout_width(mmio_timeout_width)) immio_watchdog
     (.clk(clk),.reset(reset),
      .i_timeout(i_mmio_timeout_d),.i_mmiobus(o_mmiobus),.i_mmack(s3_mmack),.i_mmdata(s3_mmdata),.o_mmack(ah_mmack),.o_mmdata(ah_mmdata), .o_mmpar(ah_mmdatapar)
      );
   
   wire 			     mmio_sreset = 1'b0;
   wire 			     mmio_app_done;


   wire 			     app_done = i_app_done;
   wire [0:afuerr_width-1] 	     app_error = i_app_done ? i_app_error : {afuerr_width{1'b0}};

   wire 			     s0_frc_perror, s1_frc_perror;
   assign s0_frc_perror = i_app_done & |(i_app_error);
   base_vlat#(.width(1)) ifrc_perror(.clk(clk),.reset(reset),.din(s0_frc_perror | s1_frc_perror),.q(s1_frc_perror));
   
   
   wire 			     f_reset;
   capi_reset icapi_reset(.clk(clk),.i_reset(i_reset),.o_reset(f_reset));

      // job control and reset
   wire 			     jc_cmd_sent;
   wire 			     jc_rsp_rcvd;
   wire 			     jc_cmd_en;


   localparam cred_width = 9;
   wire 		       s2_ctxt_trm_v;
   wire 		       s2_ctxt_add_v;
   capi_parcheck#(.width(ctxtid_width-1)) o_ctxt_upd_d_pcheck(.clk(clk),.reset(reset),.i_v(o_ctxt_add_v | o_ctxt_trm_v | o_ctxt_add_v),.i_d(o_ctxt_upd_d[0:ctxtid_width-2]),.i_p(o_ctxt_upd_d[ctxtid_width-1]),.o_error(s1_perror[4]));
   capi_jctrl#(.afuerr_width(afuerr_width), .cred_width(cred_width),.ctxtid_width(ctxtid_width),.ctxt_add_acks(ctxt_add_acks+1),.ctxt_rmv_acks(ctxt_rmv_acks),.ctxt_trm_acks(ctxt_trm_acks+1)) ijctrl
     (
      .clk(clk),.i_reset(f_reset),
      .i_ctxt_add_ack_v({i_ctxt_add_ack_v,s2_ctxt_add_v}),
      .i_ctxt_trm_ack_v({i_ctxt_trm_ack_v,s2_ctxt_trm_v}),
      .i_ctxt_rmv_ack_v(i_ctxt_rmv_ack_v),
      .o_ctxt_add_v(o_ctxt_add_v),
      .o_ctxt_trm_v(o_ctxt_trm_v),
      .o_ctxt_rmv_v(o_ctxt_rmv_v),
      .o_ctxt_upd_d(o_ctxt_upd_d),
      .i_app_done(app_done),
      .i_fatal_error(i_fatal_error),
      .i_app_error(app_error),
      .ha_jval(ha_jval),
      .ha_jcom(ha_jcom),
      .ha_jea(ha_jea),
      .ha_jeapar(ha_jeapar),
      .ah_jrunning(ah_jrunning),
      .ah_jcack(ah_jcack),
      .ah_jdone(ah_jdone),
      .ah_jerror(ah_jerror),
      .ah_tbreq(ah_tbreq),
      .ah_jyield(ah_jyield),
      .o_reset(reset),
      .o_cmd_en(jc_cmd_en),
      .i_cmd_sent(jc_cmd_sent),
      .i_rsp_rcvd(jc_rsp_rcvd),
      .o_dbg_cnt_inc(o_dbg_cnt_inc[11:14]),
      .o_s1_perror(capi_jctrl_s1_perror),
      .o_perror(o_perror[1])   
      );
   assign o_reset = reset;
   
   // dma request   
   wire 		       rd_req_plus_r;
   wire 		       rd_req_plus_v;
   wire [0:rd_req_width-1]     rd_req_plus_d;   

   wire 		       wr_req_r;
   wire 		       wr_req_plus_r;
   wire 		       wr_req_v;
   wire 		       wr_req_plus_v;
   wire [0:wr_req_width-1]     wr_req_d;  
   wire [0:wr_req_width-1]     wr_req_plus_d;  

   
   wire [0:gets*rsp_width-1]        capi_rd_rsp_plus_d;
   wire [0:gets-1]		       capi_rd_rsp_plus_v;

   wire [0:rsp_width-1]        capi_wr_rsp_plus_d;
   wire 		       capi_wr_rsp_plus_v;
   
   wire 		       capi_wdata_req_plus_v;
   wire [0:wdata_addr_width+2-1-3] capi_wdata_req_plus_a;
   
   wire 		       capi_wdata_rsp_plus_v;
   wire [0:1023] 	       capi_wdata_rsp_plus_d;  
   wire [0:1] 	               capi_wdata_rsp_plus_d_o;  
   
   wire [0:gets-1]		       capi_rdata_plus_v;
   wire [0:(gets)*rdata_512_addr_width-1] capi_rdata_plus_a;
   wire [0:gets*130-1] 	       capi_rdata_plus_d;


   
   
   localparam stage_ways = 4;
   // dma read mux
   localparam rmux_ways = (gets*1)+(cgets*2) + (cputs*1);
   // dma write mux
   localparam wmux_ways = (puts*1)+(cgets*1)+(cputs*2);
   // data mux
   localparam dmux_ways = puts+(cgets*1)+(cputs*2);

   localparam rmux_stages = ($clog2(rmux_ways)+1)/2;
   localparam wmux_stages = ($clog2(wmux_ways)+1)/2;
   localparam dmux_stages = ($clog2(dmux_ways)+1)/2;
   //localparam dreq_delay = data_latency - dmux_stages-1;
   localparam dreq_delay = data_latency - dmux_stages-1;

   // format: cpad(3), size, uid, tag, ctxt, ea   
   wire [0:rmux_ways-1]        rd_requ_plus_v, rd_requ_plus_r;
   wire [0:(rmux_ways * rd_req_width)-1] rd_requ_plus_d;  
   
   wire [0:wmux_ways-1] 		  wr_requ_plus_v, wr_requ_plus_r;
   wire [0:(wmux_ways * wr_req_width)-1] wr_requ_plus_d;  
 
   wire [0:dmux_ways-1] 		  capi_wdata_rspu_plus_v;
   wire [0:(dmux_ways * 1024)-1] 	  capi_wdata_rspu_plus_d;  


   wire 			     s3_ctxt_trm_v;
   wire [0:ctxtid_width-1] 	     s3_ctxt_trm_id;

   wire 			     s1_tstag_inv_v;
   wire [0:ctxtid_width-1] 	     s1_tstag_inv_id;

   wire [0:ngets+nputs-1] 	     s1_cnt_rsp_miss;
   wire [0:ngets+nputs-1] 	     s1_cnt_pend_dropped;

    
   wire [0:ngets*4-1]                o_dbg_cnt_inc_get_nc; 
   wire [0:nputs*4-1]                o_dbg_cnt_inc_put_nc;
   wire [0:3]                        crossing_enable; 
   
   genvar 			 i;
   generate


      for(i=0; i<4; i=i+1)
	begin :get_plus	   
	   wire [0:3] dbg_cnt_inc;
//	   assign o_dbg_cnt_inc[15+i*4:15+(i+1)*4-1] = dbg_cnt_inc;
	   assign o_dbg_cnt_inc_get_nc[i*4:(i+1)*4-1] = dbg_cnt_inc;
	   
	   capi_get_plus#(.ctag_width(ctag_width),.pea_width(pea_width),.cnt_rsp_width(cnt_rsp_width),
		     .uid(uid_st+i),.beat_width(beat_width),.uid_width(uid_width), .ea_width(ea_width),
		     .cto_width(cto_width),
		     .tstag_width(tstag_width),
		     .aux_width(1+tstag_width),.ctxtid_width(ctxtid_width), .tag_width(tag_width),.sid_width(sid_width), 
		     .tsize_width(tsize_width),.ssize_width(ssize_width),.rc_width(rc_width))
	   iget_plus
	    (
	     .clk(clk),
	     .reset(reset),
	     .o_dbg_cnt_inc(dbg_cnt_inc),
	     .i_cont_timeout(i_cont_timeout),
	     .i_timer_pulse(us_timer),
	     .i_disable(i_disable),
	     .i_ctxt_trm_v(s3_ctxt_trm_v),.i_ctxt_trm_id(s3_ctxt_trm_id),
	     .i_tstag_inv_v(s1_tstag_inv_v),.i_tstag_inv_id(s1_tstag_inv_id),
	     .o_rm_err(o_rm_err[4+i]),
	     .get_addr(get_d_addr[i*ea_width:((i+1)*ea_width)-1]),
             .get_aux({1'b1,get_d_tstag[i*tstag_width:((i+1)*tstag_width)-1]}), 
	     .get_ctxt(get_d_ctxt[i*ctxtid_width:((i+1)*ctxtid_width)-1]),
	     .get_size(get_d_size[i*ssize_width:((i+1)*ssize_width)-1]),
	     .get_valid(get_v[i]),
	     .get_acc(get_r[i]),
	     .get_data_r(get_data_r[i]),
	     .get_data_v(get_data_v[i]),
	     .get_data_d(get_data_d[130*i:((i+1)*130)-1]), 
	     .get_data_e(get_data_e[i]),
	     .get_data_c(get_data_c[4*i:((i+1)*4)-1]),
	     .get_data_rc(get_data_rc[rc_width*i:(i+1)*rc_width-1]),
	     .get_data_bcnt(get_data_bcnt[ssize_width*i:(i+1)*ssize_width-1]),
	     
	     .o_req_r(rd_requ_plus_r[i]),
	     .o_req_v(rd_requ_plus_v[i]),
	     .o_req_d(rd_requ_plus_d[i*rd_req_width:((i+1)*rd_req_width)-1]), 

	     .i_rsp_v(capi_rd_rsp_plus_v[i]),
	     .i_rsp_d(capi_rd_rsp_plus_d[rsp_width*i:((i+1)*rsp_width)-1]),
	     .i_cnt_rsp_v(i_cnt_rsp_v),.i_cnt_rsp_d(i_cnt_rsp_d),
	     .o_cnt_pend_d(o_cnt_pend_d[i*64:(i+1)*64-1]),
	     .o_cnt_rsp_miss(s1_cnt_rsp_miss[i]),
	     .o_cnt_pend_dropped(s1_cnt_pend_dropped[i]),
	     
	     .i_rdata_v(capi_rdata_plus_v[i]),
	     .i_rdata_a(capi_rdata_plus_a[i*rdata_512_addr_width:((i+1)*rdata_512_addr_width)-1]),
	     .i_rdata_d(capi_rdata_plus_d[i*130:((i+1)*130)-1]),
             .o_s1_perror(capi_get_s1_perror[5*i:5*i+4]),
             .o_perror(o_perror[2+3*i:2+3*i+2]),  // i= 0:4  bits 2:22
             .i_gate_sid(i_gate_sid)
	     
	     );

	end // block: get

      for(i=0;i<4;i=i+1)
	begin :put_plus
	   wire [0:3] dbg_cnt_inc;
//	   assign o_dbg_cnt_inc[15+ngets*4+(i*4):15+ngets*4+(i+1)*4-1] = dbg_cnt_inc;
	   assign o_dbg_cnt_inc_put_nc[i*4:(i+1)*4-1] = dbg_cnt_inc;

	   capi_put_plus#(.ctag_width(ctag_width),.pea_width(pea_width),.cnt_rsp_width(cnt_rsp_width),
		     .uid(uid_st+i+gets),.beat_width(beat_width),.uid_width(uid_width),.sid_width(sid_width),.ea_width(ea_width),.bcnt_width(ssize_width),
		     .cto_width(cto_width),
		     .tstag_width(tstag_width),
		     .aux_width(1+tstag_width),.ctxtid_width(ctxtid_width), .tag_width(tag_width),.tsize_width(tsize_width),.rc_width(rc_width),
		     .ignore_tstag_inv(ignore_tstag_inv[i]))
	   iput_plus_dma
	    (
	     .clk(clk),
	     .reset(reset),
	     .o_dbg_cnt_inc(dbg_cnt_inc),
	     .i_timer_pulse(us_timer),
	     .i_cont_timeout(i_cont_timeout),
	     .i_disable(i_disable),
	     .i_ctxt_trm_v(s3_ctxt_trm_v),.i_ctxt_trm_id(s3_ctxt_trm_id),
	     .i_tstag_inv_v(s1_tstag_inv_v),.i_tstag_inv_id(s1_tstag_inv_id),
	     .o_rm_err(o_rm_err[4+gets+i]),
	     .put_addr_r(put_addr_r[i]),
	     .put_addr_v(put_addr_v[i]),
	     .put_addr_d_ea(put_addr_d_ea[i*ea_width:((i+1)*ea_width)-1]),
             .put_addr_d_aux({1'b1,put_addr_d_tstag[i*tstag_width:((i+1)*tstag_width)-1]}),
	     .put_addr_d_ctxt(put_addr_d_ctxt[i*ctxtid_width:((i+1)*ctxtid_width)-1]),
	     .put_data_r(put_data_r[i]),
	     .put_data_v(put_data_v[i]),
	     .put_data_d(put_data_d[i*130:((i+1)*130)-1]), 
	     .put_data_e(put_data_e[i]),
	     .put_data_c(put_data_c[i*4:((i+1)*4)-1]),
	     .put_done_v(put_done_v[i]),
	     .put_done_r(put_done_r[i]),
	     .put_done_rc(put_done_rc[rc_width*i:(i+1)*rc_width-1]),
	     .put_done_bcnt(put_done_bcnt[ssize_width*i:(i+1)*ssize_width-1]),
	     
	     .o_req_r(wr_requ_plus_r[i]),
	     .o_req_v(wr_requ_plus_v[i]),
	     .o_req_d(wr_requ_plus_d[(i)*wr_req_width: ((i+1)*wr_req_width)-1]),

	     .i_rsp_v(capi_wr_rsp_plus_v),
	     .i_rsp_d(capi_wr_rsp_plus_d),
	     .i_cnt_rsp_v(i_cnt_rsp_v),.i_cnt_rsp_d(i_cnt_rsp_d),
	     .o_cnt_pend_d(o_cnt_pend_d[(gets+i)*64:(gets+i+1)*64-1]),
	     .o_cnt_rsp_miss(s1_cnt_rsp_miss[gets+i]),
	     .o_cnt_pend_dropped(s1_cnt_pend_dropped[gets+i]),
	     .i_wdata_req_v(capi_wdata_req_plus_v),
	     .i_wdata_req_a(capi_wdata_req_plus_a),
	     
	     .o_wdata_rsp_v(capi_wdata_rspu_plus_v[i]),
	     .o_wdata_rsp_d(capi_wdata_rspu_plus_d[i*1024 : ((i+1)*1024)-1]), 
             .o_perror(o_perror[23+2*i:23+2*i+1]), 
             .o_s1_perror(capi_put_s1_perror[3*i:3*i+2]),
             .o_crossing_enable(crossing_enable[i]),
             .i_gate_sid(i_gate_sid)
	     );

	end // block: put

      for(i=4; i<gets; i=i+1)
	begin :get
	   wire [0:3] dbg_cnt_inc;
//	   assign o_dbg_cnt_inc[15+i*4:15+(i+1)*4-1] = dbg_cnt_inc;
	   assign o_dbg_cnt_inc_get_nc[i*4:(i+1)*4-1] = dbg_cnt_inc;
	   

	   capi_get#(.ctag_width(ctag_width),.pea_width(pea_width),.cnt_rsp_width(cnt_rsp_width),
		     .uid(uid_st+i),.beat_width(beat_width),.uid_width(uid_width), .ea_width(ea_width),
		     .cto_width(cto_width),
		     .tstag_width(tstag_width),
		     .aux_width(1+tstag_width),.ctxtid_width(ctxtid_width), .tag_width(tag_width),.sid_width(sid_width), 
		     .tsize_width(tsize_width),.ssize_width(ssize_width),.rc_width(rc_width))
	   iget
	    (
	     .clk(clk),
	     .reset(reset),
	     .o_dbg_cnt_inc(dbg_cnt_inc),
	     .i_cont_timeout(i_cont_timeout),
	     .i_timer_pulse(us_timer),
	     .i_disable(i_disable),
	     .i_ctxt_trm_v(s3_ctxt_trm_v),.i_ctxt_trm_id(s3_ctxt_trm_id),
	     .i_tstag_inv_v(s1_tstag_inv_v),.i_tstag_inv_id(s1_tstag_inv_id),
	     .o_rm_err(o_rm_err[4+i]),
	     .get_addr(get_d_addr[i*ea_width:((i+1)*ea_width)-1]),
             .get_aux({1'b1,get_d_tstag[i*tstag_width:((i+1)*tstag_width)-1]}), 
	     .get_ctxt(get_d_ctxt[i*ctxtid_width:((i+1)*ctxtid_width)-1]),
	     .get_size(get_d_size[i*ssize_width:((i+1)*ssize_width)-1]),
	     .get_valid(get_v[i]),
	     .get_acc(get_r[i]),
	     .get_data_r(get_data_r[i]),
	     .get_data_v(get_data_v[i]),
	     .get_data_d(get_data_d[130*i:((i+1)*130)-1]),
	     .get_data_e(get_data_e[i]),
	     .get_data_c(get_data_c[4*i:((i+1)*4)-1]),
	     .get_data_rc(get_data_rc[rc_width*i:(i+1)*rc_width-1]),
	     .get_data_bcnt(get_data_bcnt[ssize_width*i:(i+1)*ssize_width-1]),
	     
	     .o_req_r(rd_requ_plus_r[i]),
	     .o_req_v(rd_requ_plus_v[i]),
	     .o_req_d(rd_requ_plus_d[i*rd_req_width:((i+1)*rd_req_width)-1]), 

	     .i_rsp_v(capi_rd_rsp_plus_v[i]),
	     .i_rsp_d(capi_rd_rsp_plus_d[rsp_width*i:((i+1)*rsp_width)-1]),
	     .i_cnt_rsp_v(i_cnt_rsp_v),.i_cnt_rsp_d(i_cnt_rsp_d),
	     .o_cnt_pend_d(o_cnt_pend_d[i*64:(i+1)*64-1]),
	     .o_cnt_rsp_miss(s1_cnt_rsp_miss[i]),
	     .o_cnt_pend_dropped(s1_cnt_pend_dropped[i]),
	     
	     .i_rdata_v(capi_rdata_plus_v[i]),
//	     .i_rdata_a({capi_rdata_plus_a[0:9],capi_rdata_plus_a[12:14]}),   // reduce back to 15 addr bits cause its get not get_plus
	     .i_rdata_a({capi_rdata_plus_a[i*rdata_512_addr_width:i*rdata_512_addr_width+9],capi_rdata_plus_a[i*rdata_512_addr_width+12:i*rdata_512_addr_width+14]}),   // reduce back to 15 addr bits cause its get not get_plus
	     .i_rdata_d(capi_rdata_plus_d[i*130:((i+1)*130)-1]),
             .o_s1_perror(capi_get_s1_perror[5*i:5*i+4]),
             .o_perror(o_perror[2+3*i:2+3*i+2]),  // i= 0:4  bits 2:22
             .i_gate_sid(i_gate_sid)
	     
	     );

	end // block: get



      localparam put_st = gets;

      wire [0:1] put128_dbg_cnt_inc;      

      for(i=4;i<puts;i=i+1)
	begin :put
	   wire [0:3] dbg_cnt_inc;
//	   assign o_dbg_cnt_inc[15+ngets*4+(i*4):15+ngets*4+(i+1)*4-1] = dbg_cnt_inc;
	   assign o_dbg_cnt_inc_put_nc[(i*4):(i+1)*4-1] = dbg_cnt_inc;

	   capi_put128_plus#(.ctag_width(ctag_width),.pea_width(pea_width),.cnt_rsp_width(cnt_rsp_width),
		     .uid(uid_st+i+gets),.beat_width(beat_width),.uid_width(uid_width),.sid_width(sid_width),.ea_width(ea_width),.bcnt_width(ssize_width),
		     .cto_width(cto_width),
		     .tstag_width(tstag_width),
		     .aux_width(1+tstag_width),.ctxtid_width(ctxtid_width), .tag_width(tag_width),.tsize_width(tsize_width),.rc_width(rc_width),
		     .ignore_tstag_inv(ignore_tstag_inv[i]))
	   iput128_plus
	    (
	     .clk(clk),
	     .reset(reset),
	     .o_dbg_cnt_inc(dbg_cnt_inc),
	     .i_timer_pulse(us_timer),
	     .i_cont_timeout(i_cont_timeout),
	     .i_disable(i_disable),
	     .i_ctxt_trm_v(s3_ctxt_trm_v),.i_ctxt_trm_id(s3_ctxt_trm_id),
	     .i_tstag_inv_v(s1_tstag_inv_v),.i_tstag_inv_id(s1_tstag_inv_id),
	     .o_rm_err(o_rm_err[4+gets+i]),
	     .put_addr_r(put_addr_r[i]),
	     .put_addr_v(put_addr_v[i]),
	     .put_addr_d_ea(put_addr_d_ea[i*ea_width:((i+1)*ea_width)-1]),
             .put_addr_d_aux({1'b1,put_addr_d_tstag[i*tstag_width:((i+1)*tstag_width)-1]}),
	     .put_addr_d_ctxt(put_addr_d_ctxt[i*ctxtid_width:((i+1)*ctxtid_width)-1]),
	     .put_data_r(put_data_r[i]),
	     .put_data_v(put_data_v[i]),
	     .put_data_d(put_data_d[i*130:((i+1)*130)-1]),
	     .put_data_e(put_data_e[i]),
	     .put_data_c(put_data_c[i*4:((i+1)*4)-1]),
	     .put_done_v(put_done_v[i]),
	     .put_done_r(put_done_r[i]),
	     .put_done_rc(put_done_rc[rc_width*i:(i+1)*rc_width-1]),
	     .put_done_bcnt(put_done_bcnt[ssize_width*i:(i+1)*ssize_width-1]),
	     
	     .o_req_r(wr_requ_plus_r[i]),
	     .o_req_v(wr_requ_plus_v[i]),
	     .o_req_d(wr_requ_plus_d[(i)*wr_req_width: ((i+1)*wr_req_width)-1]),

	     .i_rsp_v(capi_wr_rsp_plus_v),
	     .i_rsp_d(capi_wr_rsp_plus_d),
	     .i_cnt_rsp_v(i_cnt_rsp_v),.i_cnt_rsp_d(i_cnt_rsp_d),
	     .o_cnt_pend_d(o_cnt_pend_d[(gets+i)*64:(gets+i+1)*64-1]),
	     .o_cnt_rsp_miss(s1_cnt_rsp_miss[gets+i]),
	     .o_cnt_pend_dropped(s1_cnt_pend_dropped[gets+i]),
	     .i_wdata_req_v(capi_wdata_req_plus_v),
	     .i_wdata_req_a(capi_wdata_req_plus_a),           
	     
	     .o_wdata_rsp_v(capi_wdata_rspu_plus_v[i]),
	     .o_wdata_rsp_d(capi_wdata_rspu_plus_d[i*1024 : ((i+1)*1024)-1]), 
             .o_perror(o_perror[23+2*i:23+2*i+1]),
             .o_s1_perror(capi_put_s1_perror[3*i:3*i+2]),
             .o_put128_dbg_cnt_inc(put128_dbg_cnt_inc[i-4]),
             .i_gate_sid(i_gate_sid)
         
	     );
	end // block: put
endgenerate

// new debug inc signals 
   assign o_dbg_cnt_inc[15] = get_v[0] & get_r[0];
   assign o_dbg_cnt_inc[17] = get_v[1] & get_r[1];
   assign o_dbg_cnt_inc[19] = get_v[2] & get_r[2];
   assign o_dbg_cnt_inc[21] = get_v[3] & get_r[3];
   assign o_dbg_cnt_inc[23] = get_v[4] & get_r[4];
   assign o_dbg_cnt_inc[25] = get_v[5] & get_r[5];

   assign o_dbg_cnt_inc[16] = get_data_v[0] & get_data_r[0] & get_data_e[0];
   assign o_dbg_cnt_inc[18] = get_data_v[1] & get_data_r[1] & get_data_e[1];
   assign o_dbg_cnt_inc[20] = get_data_v[2] & get_data_r[2] & get_data_e[2];
   assign o_dbg_cnt_inc[22] = get_data_v[3] & get_data_r[3] & get_data_e[3];
   assign o_dbg_cnt_inc[24] = get_data_v[4] & get_data_r[4] & get_data_e[4];
   assign o_dbg_cnt_inc[26] = get_data_v[5] & get_data_r[5] & get_data_e[5];

   assign o_dbg_cnt_inc[27] = put_addr_v[0] & put_addr_r[0];
   assign o_dbg_cnt_inc[30] = put_addr_v[1] & put_addr_r[1];
   assign o_dbg_cnt_inc[33] = put_addr_v[2] & put_addr_r[2];
   assign o_dbg_cnt_inc[36] = put_addr_v[3] & put_addr_r[3];

   assign o_dbg_cnt_inc[28] = put_done_v[0] & put_done_r[0];
   assign o_dbg_cnt_inc[31] = put_done_v[1] & put_done_r[1];
   assign o_dbg_cnt_inc[34] = put_done_v[2] & put_done_r[2];
   assign o_dbg_cnt_inc[37] = put_done_v[3] & put_done_r[3];

   assign o_dbg_cnt_inc[29] = put_data_v[0] & put_data_r[0] & put_data_e[0];
   assign o_dbg_cnt_inc[32] = put_data_v[1] & put_data_r[1] & put_data_e[1];
   assign o_dbg_cnt_inc[35] = put_data_v[2] & put_data_r[2] & put_data_e[2];
   assign o_dbg_cnt_inc[38] = put_data_v[3] & put_data_r[3] & put_data_e[3];

   assign o_dbg_cnt_inc[39:42] = crossing_enable[0:3];






   wire s2_cnt_rsp_miss;
   base_vlat#(.width(1)) i_cnt_rsp_miss_lat(.clk(clk),.reset(reset),.din(& s1_cnt_rsp_miss),.q(s2_cnt_rsp_miss));
   assign o_cnt_rsp_miss = s2_cnt_rsp_miss;

   wire s2_cnt_pend_dropped;
   base_vlat#(.width(1)) i_cnt_pend_dropped_lat(.clk(clk),.reset(reset),.din(| s1_cnt_pend_dropped),.q(s2_cnt_pend_dropped));
   assign o_cnt_pend_dropped = s2_cnt_pend_dropped;
   

   base_amlrr_arb#(.width(rd_req_width),.stages(rmux_stages),.stage_ways(stage_ways),.ways(rmux_ways)) irmux_plus 
     (.clk(clk),.reset(reset),
      .i_r(rd_requ_plus_r),.i_v(rd_requ_plus_v),.i_d(rd_requ_plus_d),.i_h({rmux_ways{1'b0}}),
      .o_r(rd_req_plus_r), .o_v(rd_req_plus_v), .o_d(rd_req_plus_d),.o_h()
      );


   base_amlrr_arb#(.width(wr_req_width),.stages(wmux_stages),.stage_ways(stage_ways),.ways(wmux_ways)) iwmux_plus 
     (.clk(clk),.reset(reset),
      .i_r(wr_requ_plus_r),.i_v(wr_requ_plus_v),.i_d(wr_requ_plus_d),.i_h({wmux_ways{1'b0}}),
      .o_r(wr_req_plus_r), .o_v(wr_req_plus_v), .o_d(wr_req_plus_d),.o_h()
      );


   base_multicycle_mux#(.width(1024),.stages(dmux_stages),.stage_ways(stage_ways),.ways(dmux_ways),.early_valid(1)) idmux_plus
     (.clk(clk),.reset(reset),
      .i_v(capi_wdata_rspu_plus_v),.i_d({capi_wdata_rspu_plus_d}),
      .o_v(capi_wdata_rsp_plus_v),.o_d({capi_wdata_rsp_plus_d})
      );

   wire [0:ctag_width-1]       r0_rtag;
   wire                        r0_rtagpar;
   wire [7:0] 		       r0_response;
   wire [0:8] 		       r0_rcredits;

   wire 		       r0_rvalid_plus;
   wire [0:ctag_width-1]       r0_rtag_plus;
   wire                        r0_rtagpar_plus;
   wire [0:8]                  r0_rditag_plus;
   wire                        r0_rditagpar_plus;
   wire [7:0] 		       r0_response_plus;
   wire [0:8] 		       r0_rcredits_plus;
   wire [7:0]                  r0_response_plus_temp;
//   assign r0_response_plus = 8'h01;
wire response_error = 1'b0;
 
wire [0:7]   ha_error_response = response_error ? 8'h01 :8'h00; 
   
   localparam har_width=1+8+8+9;
   localparam har_plus_width=1+8+1+9+1+8+9;
   base_vlat#(.width(har_plus_width)) ir0_lat_plus
     (.clk(clk),.reset(reset),
      .din({ha_rvalid,ha_rtag,ha_rtagpar,ha_rditag,ha_rditagpar,(ha_response | ha_error_response),ha_rcredits}),
      .q({r0_rvalid_plus,r0_rtag_plus,r0_rtagpar_plus,r0_rditag_plus,r0_rditagpar_plus,r0_response_plus,r0_rcredits_plus})
//      .q({r0_rvalid_plus,r0_rtag_plus,r0_rtagpar_plus,r0_rditag_plus,r0_rditagpar_plus,r0_response_plus_temp,r0_rcredits_plus})
      );

   wire [0:ctag_width-1]       r1_rtag;
   wire [7:0] 		       r1_response;
   wire [0:8] 		       r1_rcredits;
   
   wire 		       r1_rvalid_plus;
   wire [0:ctag_width-1]       r1_rtag_plus;
   wire                        r1_rtagpar_plus;
   wire [0:8]                  r1_rditag_plus;
   wire                        r1_rditagpar_plus;
   wire [7:0] 		       r1_response_plus;
   wire [0:8] 		       r1_rcredits_plus;
   

   base_vlat#(.width(har_plus_width)) ir1_lat_plus
     (.clk(clk),.reset(reset),
      .din({r0_rvalid_plus,r0_rtag_plus,r0_rtagpar_plus,r0_rditag_plus,r0_rditagpar_plus,r0_response_plus,r0_rcredits_plus}),
      .q({r1_rvalid_plus,r1_rtag_plus,r1_rtagpar_plus,r1_rditag_plus,r1_rditagpar_plus,r1_response_plus,r1_rcredits_plus})
      );
   
   
   
   wire 		       r1_tag_outst_plus; // this tag is a good tag - it is outstangind
   wire 		       r1_rsp_cred_plus = (r1_response_plus == 8'd9); // this is just credit manipulation
   wire 		       r1_rsp_done_plus = (r1_response_plus == 8'd0);
   wire 		       r1_rsp_flushed_plus = (r1_response_plus == 8'd6);
   wire 		       r1_rsp_paged_plus = (r1_response_plus == 8'd10);
   


   wire 		       r1_tag_plus_v     = r1_rvalid_plus & ~r1_rsp_cred_plus & r1_tag_outst_plus;
   wire 		       r1_tag_error_plus = r1_rvalid_plus & ~r1_rsp_cred_plus & ~r1_tag_outst_plus;
   wire 		       r1_bad_rsp_plus   = r1_tag_plus_v & ~r1_rsp_done_plus & ~r1_rsp_flushed_plus;

   assign o_dbg_cnt_inc[1] = r1_rvalid_plus & ~r1_rsp_cred_plus;  // count responses
   assign o_dbg_cnt_inc[2] = r1_rvalid_plus & ~r1_rsp_cred_plus & ~r1_rsp_done_plus; // count error responses
   assign o_dbg_cnt_inc[4] = r1_rvalid_plus & r1_rsp_flushed_plus;
   assign o_dbg_cnt_inc[5] = r1_rvalid_plus & r1_rsp_paged_plus;
   assign o_dbg_cnt_inc[6] = i_cnt_rsp_v;
   assign o_dbg_cnt_inc[7] = s2_cnt_rsp_miss;
   assign o_dbg_cnt_inc[8] = s2_cnt_pend_dropped;
//   assign o_dbg_cnt_inc[43] = wr_req_plus_v & ~wr_req_plus_r;
   assign o_dbg_cnt_inc[43] = put128_dbg_cnt_inc[0];
   
   
   
   wire 		       dbg_bad_rsp_hld /* synthesis keep = 1 */;
   base_vlat#(.width(1)) idbg_bad_rsp_lat(.clk(clk),.reset(reset),.din(r1_bad_rsp_plus | dbg_bad_rsp_hld),.q(dbg_bad_rsp_hld));
   
   wire 		       s1_rd_req_plus_v, s1_rd_req_plus_r, s1_wr_req_plus_v, s1_wr_req_plus_r, s1_it_req_v, s1_it_req_r;
   wire [0:gbl_req_width-3]    s1_rd_req_plus_d, s1_wr_req_plus_d, s1_it_req_d;

   wire 		       r2_rvalid_plus;
   wire [0:ctag_width-1]       r2_rtag_plus;
   wire [0:9]                  r2_rutag_plus;
   wire [0:8]                  r2_ritag_plus;
   wire                        r2_ritagpar_plus;
   wire [7:0] 		       r2_response_plus;
   
   wire s1_disable;
   base_vlat#(.width(1)) is1_disable(.clk(clk),.reset(reset),.din(i_disable),.q(s1_disable));
   
   localparam nt_req_width = gbl_req_width+13-(ctag_width+csid_width+1+1+(1+tstag_width)+ctxtid_width);

   wire 		       s1_dma_req_plus_v, s1_dma_req_plus_r;
   wire [0:ctxtid_width-1]     s1_dma_req_plus_ctxt;
   wire [0:tstag_width-1]      s1_dma_req_plus_tstag;
   wire 		       s1_dma_req_plus_tstag_v;
   wire [0:ctag_width-1]       s1_dma_req_plus_tag;
   wire [0:nt_req_width-1]     s1_dma_req_plus_dat;
   wire [0:csid_width-1]       s1_dma_req_plus_sid;
   wire 		       s1_dma_req_plus_f;
   wire 		       s1_dma_req_plus_itst_inv; // ignore tstag invalidate

   wire 		       s2_dma_req_plus_v, s2_dma_req_plus_r;
   wire [0:ctag_width-1]       s2_dma_req_plus_tag;
   wire [0:4]                  s2_dma_req_plus_uid;
   wire [0:ctxtid_width-1]     s2_dma_req_plus_ctxt;
   wire [0:nt_req_width-1]     s2_dma_req_plus_dat;

   wire [0:cred_width-1]       br2_credits_plus;

   wire [0:ctxtid_width-1]     s2_ctxt_trm_id;
   wire gated_tag_val;
   wire [0:7] gated_tag;
   wire r1_tag_plus_total_v = r1_tag_plus_v | gated_tag_val;
   wire [0:7] r1_rtag_plus_total = r1_tag_plus_v ? r1_rtag_plus : gated_tag; 
   wire [0:8] r1_rditag_plus_total = r1_tag_plus_v ? r1_rditag_plus : 9'b000000000;
   wire       r1_rditagpar_plus_total = r1_tag_plus_v ? r1_rditagpar_plus : 1'b1; 
   wire [0:7]      r1_response_plus_total = r1_tag_plus_v ? r1_response_plus : 8'h00;
   wire       gated_tag_taken =  r1_tag_plus_v ? 1'b0 : gated_tag_val;  


   capi_dma_retry_plus#
     (.tag_width(ctag_width),
      .tag_prefix_width(2),
      .dat_width(nt_req_width),
      .ts_width(64),
      .tstag_width(tstag_width),
      .ctxtid_width(ctxtid_width),
      .cred_width(cred_width),
      .sid_width(csid_width),
      .rc_tsinv(psl_rsp_cinv)
      ) idma_rtry_plus
       (.clk(clk),.reset(reset),
	
	.i_enable(jc_cmd_en & ~s1_disable),
	.o_credits(br2_credits_plus),
	.ha_croom(ha_croom),
	.i_cfg_ctrm_wait(i_cfg_ctrm_wait),

	.o_rm_err(),
	.o_dbg_cnt_inc(),

	.i_ctxt_rst_r(i_ctxt_rst_r),
	.i_ctxt_rst_v(i_ctxt_rst_v),
	.i_ctxt_rst_id(i_ctxt_rst_id),

	.o_ctxt_rst_v(o_ctxt_rst_v),
	.o_ctxt_rst_id(o_ctxt_rst_id),

	
	.i_tstag_issue_v(i_tstag_issue_v),
	.i_tstag_issue_id(i_tstag_issue_id),
	.i_tstag_issue_d(i_tstag_issue_d),
	
	.i_tstag_inv_v(i_tstag_inv_v),
	.i_tstag_inv_id(i_tstag_inv_id),
	
	.i_tscheck_v(i_tscheck_v),
	.i_tscheck_r(i_tscheck_r),
	.i_tscheck_tstag(i_tscheck_tstag),
	.i_tscheck_ctxt(i_tscheck_ctxt),
	.o_tscheck_v(o_tscheck_v),
	.o_tscheck_r(o_tscheck_r),
	.o_tscheck_ok(o_tscheck_ok),

	.i_ctxt_add_v(o_ctxt_add_v),
	.i_ctxt_rmv_v(o_ctxt_rmv_v),
	.i_ctxt_trm_v(o_ctxt_trm_v),
	.i_ctxt_ctrl_id(o_ctxt_upd_d),
	
	.i_restart_dat({13'h01, {nt_req_width-14{1'b0}},1'b1}),
	.i_restart_ctxt({{ctxtid_width-1{1'b0}},1'b1}),
	.i_restart_tstag({{tstag_width-1{1'b0}},1'b1}),

	.i_rsp_v(r1_tag_plus_total_v), 
	.i_rsp_tag(r1_rtag_plus_total),
	.i_rsp_itag({r1_rditag_plus_total,r1_rditagpar_plus}),
	.i_rsp_d(r1_response_plus_total),     
	.i_rsp_credits(r1_rcredits_plus),
	.i_rsp_tag_outst(r1_tag_outst_plus),
	
	.o_rsp_v(r2_rvalid_plus),.o_rsp_tag(r2_rtag_plus),
	.o_rsp_itag({r2_ritag_plus,r2_ritagpar_plus}),
        .o_rsp_d(r2_response_plus),
	.i_req_v(s1_dma_req_plus_v),.i_req_r(s1_dma_req_plus_r),.i_req_tag(s1_dma_req_plus_tag),.i_req_tstag_v(s1_dma_req_plus_tstag_v),.i_req_tstag(s1_dma_req_plus_tstag),.i_req_ctxt(s1_dma_req_plus_ctxt),.i_req_dat(s1_dma_req_plus_dat),
	.i_req_itst_inv(s1_dma_req_plus_itst_inv),
	.i_req_sid(s1_dma_req_plus_sid),.i_req_f(1'b1),
	.o_req_v(s2_dma_req_plus_v),.o_req_r(s2_dma_req_plus_r),.o_req_tag(s2_dma_req_plus_tag),.o_req_ctxt(s2_dma_req_plus_ctxt),.o_req_uid(s2_dma_req_plus_uid),.o_req_dat(s2_dma_req_plus_dat),
	.o_ctxt_trm_v(s2_ctxt_trm_v),
	.o_ctxt_trm_id(s2_ctxt_trm_id),
	.o_ctxt_add_v(s2_ctxt_add_v),
	.o_pipemon_v(o_pipemon_v[4]),
	.o_pipemon_r(o_pipemon_r[4]),
        .o_s1_perror(dma_retry_s1_perror),
        .o_dbg_dma_retry_s0(),
        .i_dma_retry_msk_pe025(i_dma_retry_msk_pe025),
        .i_dma_retry_msk_pe34(i_dma_retry_msk_pe34),
        .o_perror(o_perror[35:36])  

	);

   base_delay#(.n(6),.width(1))            is2_ctxt_trm_ack_vdel(.clk(clk),.reset(reset),.i_d(s2_ctxt_trm_v), .o_d(s3_ctxt_trm_v));
   base_delay#(.n(6),.width(ctxtid_width)) is2_ctxt_trm_ack_ddel(.clk(clk),.reset(1'b0), .i_d(s2_ctxt_trm_id),.o_d(s3_ctxt_trm_id));
   base_delay#(.n(6),.width(1))            ii_tstag_inv_ack_vdel(.clk(clk),.reset(reset),.i_d(i_tstag_inv_v), .o_d(s1_tstag_inv_v));
   base_delay#(.n(6),.width(tstag_width)) ii_tstag_inv_ack_ddel(.clk(clk),.reset(1'b0), .i_d(i_tstag_inv_id),.o_d(s1_tstag_inv_id));

						     

   wire [0:rc_width-1] 	       r2_rc_plus = r2_response_plus[rc_width-1:0];
   wire 		       r2_rd_plus_v = r2_rvalid_plus & (r2_rtag_plus[0:1] == 2'b01);
   wire 		       r2_wr_plus_v = r2_rvalid_plus & (r2_rtag_plus[0:1] == 2'b10);
   wire 		       r2_it_plus_v = r2_rvalid_plus & (r2_rtag_plus[0:1] == 2'b11);
   wire [0:ctag_width-3]       r2_ctag_plus = r2_rtag_plus[2:ctag_width-1];

   

      wire 			  rsp_rd_ctag_v;
      wire [0:5] 	          rsp_rd_ctag;    
      wire [0:8] 	          rsp_utag; 

      wire [0:1]                  read_tag_error;

   capi_dma_read_plus#(.ea_width(ea_width),.tstag_width(tstag_width),.ctxtid_width(ctxtid_width),.tsize_width(tsize_width),.tag_width(tag_width),.uid_width(uid_width),.sid_width(sid_width), 
		  .csid_width(csid_width),.gets(gets),
		  .beat_width(beat_width),.ctag_width(ctag_width-2),.rc_width(rc_width)) idma_read_plus
     (.clk(clk),.reset(reset),
      .o_rm_err(o_rm_err[0]),
      .i_req_v(rd_req_plus_v),.i_req_r(rd_req_plus_r),.i_req_d(rd_req_plus_d),
      .o_req_v(s1_rd_req_plus_v),.o_req_r(s1_rd_req_plus_r),.o_req_d(s1_rd_req_plus_d),
      .o_rsp_v(capi_rd_rsp_plus_v),.o_rsp_d(capi_rd_rsp_plus_d),
      .o_rdata_v(capi_rdata_plus_v),.o_rdata_a(capi_rdata_plus_a),.o_rdata_d(capi_rdata_plus_d),
      .hd0_cpl_valid(hd0_cpl_valid),.hd0_cpl_utag(hd0_cpl_utag),.hd0_cpl_type(hd0_cpl_type),.hd0_cpl_laddr(hd0_cpl_laddr),.hd0_cpl_byte_count(hd0_cpl_byte_count),.hd0_cpl_data(hd0_cpl_data),.hd0_cpl_size(hd0_cpl_size),.i_tag_plus_v(r1_tag_plus_v),.i_rtag_plus(r1_rtag_plus),.i_rtag_response_plus(r1_response_plus),
      .i_sent_utag_valid(hd0_sent_utag_valid),.i_sent_utag(hd0_sent_utag[2:9]),
      .o_ctag_error_hld(),.o_rtag_error_hld(),.o_u_sent_tag_error_hld(),.o_cmplt_utag_error_hld(),
      .o_perror(o_perror[37:38]),.o_tag_error(read_tag_error), 
      .o_latency_d(read_tag_latency),.i_reset_lat_cntrs(i_reset_lat_cntrs)
      );

   // interposer to force write requests to power-of-2 naturally alligned
   wire 		       wu_req_v, wu_req_r;
   wire [0:wr_req_width-1]     wu_req_d; 

 wire       itag_dvalid;
 wire [0:7] itag_dwad;
 wire                              s0_sent_utag_valid;
 wire [0:9]      	           s0_sent_utag; 
 wire [0:2]      		   s0_sent_utag_sts; 

   capi_dma_write_plus#(.ea_width(ea_width),.sid_width(sid_width),.uid_width(uid_width),.tstag_width(tstag_width),.ctxtid_width(ctxtid_width),.csid_width(csid_width),
		   .tsize_width(tsize_width),.tag_width(tag_width),.beat_width(beat_width),.ctag_width(ctag_width-2), .rc_width(rc_width)) idma_write_plus
     (.clk(clk),.reset(reset),
      .o_rm_err(),
      .i_force_perror(s1_frc_perror),
      .i_req_v(wr_req_plus_v),.i_req_r(wr_req_plus_r),.i_req_d(wr_req_plus_d),
      .o_req_v(s1_wr_req_plus_v),.o_req_r(s1_wr_req_plus_r),.o_req_d(s1_wr_req_plus_d),
      .i_rsp_v(r2_wr_plus_v),.i_rsp_ctag(r2_ctag_plus),
      .i_rsp_rc(r2_rc_plus),
      .o_rsp_v(capi_wr_rsp_plus_v),.o_rsp_d(capi_wr_rsp_plus_d),
      .o_wdata_req_v(capi_wdata_req_plus_v),.o_wdata_req_a(capi_wdata_req_plus_a),.i_wdata_rsp_v(capi_wdata_rsp_plus_v),.i_wdata_rsp_d(capi_wdata_rsp_plus_d),
      .i_dvalid(itag_dvalid),.i_dwad(itag_dwad),.i_usent_v(s0_sent_utag_valid),.i_usent_tag(s0_sent_utag),.i_usent_sts(s0_sent_utag_sts),
      .d0h_ddata(d0h_ddata),
      .o_perror(o_perror[39]),
      .o_latency_d(write_tag_latency),.i_reset_lat_cntrs(i_reset_lat_cntrs)
      
      );

   capi_dma_intr#(.uid(uid_st+gets+puts),.uid_width(uid_width),.sid_width(sid_width),.ea_width(ea_width),.aux_width(1+1+tstag_width),.ctxtid_width(ctxtid_width), .csid_width(csid_width),.tsize_width(tsize_width),.ctag_width(ctag_width-2),.rc_width(rc_width)) idma_intr
     (.clk(clk),.reset(reset),
      .o_rm_err(o_rm_err[2]),
      .i_req_v(i_irq_v),
      .i_req_r(i_irq_r),
      .i_req_d_src(i_irq_src),
      .i_req_d_aux({1'b1,i_irq_tstag_v,i_irq_tstag}),
      .i_req_d_ctxt(i_irq_ctxt),
      .o_req_v(s1_it_req_v),.o_req_r(s1_it_req_r),.o_req_d(s1_it_req_d),
      .i_rsp_v(r2_it_plus_v),.i_rsp_ctag(r2_ctag_plus),.i_rsp_rc(r2_rc_plus),
      .o_rsp_v(o_intr_done),.o_perror(o_perror[40])
      );

   assign o_pipemon_v[0] = s1_rd_req_plus_v;
   assign o_pipemon_v[1] = s1_wr_req_plus_v;
   assign o_pipemon_v[2] = s1_it_req_v;
   assign o_pipemon_v[3] = s1_dma_req_plus_v;
   
   assign o_pipemon_r[0] = s1_rd_req_plus_r;
   assign o_pipemon_r[1] = s1_wr_req_plus_r;
   assign o_pipemon_r[2] = s1_it_req_r;
   assign o_pipemon_r[3] = s1_dma_req_plus_r;
   
   wire [0:2] 		       s1_dma_req_plus_sel;

   base_arr_arb#(.ways(3)) idma_arb_plus
     (.clk(clk),.reset(reset),
      .i_v({s1_rd_req_plus_v,s1_wr_req_plus_v,s1_it_req_v}),.i_r({s1_rd_req_plus_r,s1_wr_req_plus_r,s1_it_req_r}),.i_h(3'd0),
      .o_v(s1_dma_req_plus_v),.o_r(s1_dma_req_plus_r),.o_s(s1_dma_req_plus_sel),.o_h()
      );


   

   base_mux#(.ways(3),.width(13+gbl_req_width)) idma_mux_plus
     (.din({13'h1F00,2'b01,s1_rd_req_plus_d,    
            13'h1F01,2'b10,s1_wr_req_plus_d,
	    13'h000,2'b11,s1_it_req_d}),
      .dout({s1_dma_req_plus_dat[0:12],s1_dma_req_plus_tag     ,s1_dma_req_plus_sid, s1_dma_req_plus_f, s1_dma_req_plus_itst_inv,s1_dma_req_plus_tstag_v,s1_dma_req_plus_tstag,s1_dma_req_plus_ctxt,s1_dma_req_plus_dat[13:nt_req_width-1]}),.sel(s1_dma_req_plus_sel));
      
   // capi request pipeline
   wire 		       s2_plus_v, s2_plus_r;
   assign s2_plus_v = s2_dma_req_plus_v;
   assign s2_dma_req_plus_r = s2_plus_r;
   
   
   assign jc_cmd_sent = s2_plus_v;
   assign jc_rsp_rcvd = ~r1_rsp_cred_plus & r1_rvalid_plus & r1_tag_outst_plus;


   wire [0:ctag_width-1]       s2_ctag;
   
   wire [0:tsize_width-1]      s2_csize;
   wire [0:ea_width-1] 	       s2_cea;
   wire [0:ctxtid_width-1]     s2_cch;
   wire [0:12] 		       s2_cmd;

   localparam ahc_width = 1+ctag_width+13+ea_width+ctxtid_width+tsize_width;


   wire [0:ctxtid_width-1]     ah_lcl_cch;  //careful - ctxtid_width might be less than 16  



   wire [0:ctag_width-1]       s2_plus_ctag;
   
   wire [0:tsize_width-1]      s2_plus_csize;
   wire [0:ea_width-1] 	       s2_plus_cea;
   wire [0:ctxtid_width-1]     s2_plus_cch;
   wire [0:12] 		       s2_plus_cmd;
    		       
   assign {s2_plus_cmd,s2_plus_csize,s2_plus_cea} = s2_dma_req_plus_dat;
   assign s2_plus_cch = s2_dma_req_plus_ctxt;
   assign s2_plus_ctag = s2_dma_req_plus_tag;

   wire 		       s3_plus_v;
   wire [0:ctag_width-1]       s3_plus_ctag;  
   wire [0:12] 		       s3_plus_cmd;
   wire [0:ctxtid_width-1]     s3_plus_cch;
   wire [0:ea_width-1] 	       s3_plus_cea;
   wire [0:tsize_width-1]      s3_plus_csize;
   wire [0:4]                  s3_dma_req_plus_uid;
   wire                        nvme_port_write = (s3_dma_req_plus_uid == 5'b00111) | (s3_dma_req_plus_uid == 5'b01000) | (s3_dma_req_plus_uid == 5'b01001) | (s3_dma_req_plus_uid == 5'b01010);
   wire                        gate_nvme_port_write = ~(i_drop_wrt_pckts & nvme_port_write & (s3_plus_csize[5:11] == 7'b0000000))  ;


   base_alatch#(.width(ahc_width-1+5),.dq(1)) is3_lat_plus
     (.clk(clk),.reset(reset),
      .i_v(s2_plus_v),.i_d({s2_plus_ctag,s2_plus_cmd,s2_plus_cch,s2_plus_cea,s2_plus_csize,s2_dma_req_plus_uid}),.i_r(s2_plus_r),
      .o_v(s3_plus_v),.o_d({s3_plus_ctag,s3_plus_cmd,s3_plus_cch,s3_plus_cea,s3_plus_csize,s3_dma_req_plus_uid}),.o_r(1'b1));

   wire 		       s3_tag_outst_plus;
   base_vmem#(.a_width(ctag_width),.rports(2)) itag_vmem_plus 
     (.clk(clk),.reset(reset),
      .i_set_v(s3_plus_v),.i_set_a(s3_plus_ctag),
      .i_rst_v(r1_tag_plus_total_v),.i_rst_a(r1_rtag_plus_total),
//      .i_rst_v(r1_tag_plus_v),.i_rst_a(r1_rtag_plus),
      .i_rd_en(2'b11),.i_rd_a({s2_plus_ctag,r0_rtag_plus}),.o_rd_d({s3_tag_outst_plus,r1_tag_outst_plus})
      );




// DEBUG STUFF 
   wire 		       xx_r, xx_v /* synthesis keep = 1 */;

    wire 		       br1_v, br1_r;

    base_vlat_sr idebug_en(.clk(clk),.reset(reset),.set(app_done),.rst(~xx_v),.q(xx_r));

    wire [0:ctxtid_width-1]     r1_rctxt;
    wire [0:ea_width-1] 	       r1_rea;
    base_mem#(.addr_width(ctag_width),.width(ctxtid_width+ea_width)) ibad_rsp_mem
      (.clk(clk),
       .re(1'b1),.ra(r0_rtag_plus),.rd({r1_rctxt,r1_rea}),
       .we(s3_plus_v),.wa(s3_plus_ctag),.wd({s3_plus_cch,s3_plus_cea})
       );

   wire 		       tag_issue_error = s3_plus_v & s3_tag_outst_plus;
   wire 		       tag_return_error = r1_tag_error_plus;

   // remember that we have had an error
   wire [0:1] 		       tag_error;
   wire [0:1] 		       tag_error_in = tag_error | {tag_issue_error, tag_return_error};
   base_vlat#(.width(2)) rtag_error_lat(.clk(clk),.reset(reset),.din(tag_error_in),.q(tag_error));

   wire [0:3]                  itag_tag_error;

   assign o_bad_rsp_v     = r1_bad_rsp_plus;
   assign o_bad_rsp_d     = {{64-(ctxtid_width+9+8+8){1'b0}}, r1_rctxt, r1_rcredits,r1_response,r1_rtag,r1_rea};
   assign o_status[0:7]   = {itag_tag_error,read_tag_error,tag_error[0:1]};
   assign o_status[8:15]  = {6'd0,i_perror_total,dbg_bad_rsp_hld};  // added bad response to status
   assign o_status[16:31] = {7'd0,br2_credits_plus[0:8]};
   assign o_status[32:63] = {30'b0,s1_disable,jc_cmd_en};
   
     

   wire 		       s3_plus_ctagpar = ~(^s3_plus_ctag);  
   wire 		       s3_plus_cmdpar = ~(^s3_plus_cmd);

   wire 		       s3a_plus_v = s3_plus_v & ~s3_tag_outst_plus & gate_nvme_port_write;

   assign o_dbg_cnt_inc[0] = s3a_plus_v;
   assign o_dbg_cnt_inc[3] = s3a_plus_v & s3_plus_cmd == 13'd1; // count restarts
   wire 		       gated_tag_v = s3_plus_v & ~s3_tag_outst_plus & ~gate_nvme_port_write;

   
   nvme_fifo#(
              .width(8), 
              .words(64),
              .almost_full_thresh(6)
              ) gated_wrt_tag
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        gated_tag_v), 
      .din(         s3_plus_ctag ),
      .dval(        gated_tag_val ), 
      .pop(         gated_tag_taken),
      .dout(        gated_tag ),
      .full(        ), 
      .almost_full( ), 
      .used());
   
   

   base_vlat#(.width(ahc_width+2)) iahc_lat_plus 
     (.clk(clk),.reset(reset),
      .din({(s3a_plus_v & ~i_error_status_hld),s3_plus_ctag,s3_plus_ctagpar,s3_plus_cmd,s3_plus_cmdpar,s3_plus_cch,s3_plus_cea,s3_plus_csize}), 
      .q({ah_cvalid,ah_ctag,ah_ctagpar,ah_com,ah_compar,ah_lcl_cch,ah_cea,ah_ceapar,ah_csize}));

   base_vlat#(.width(3)) icabt_lat(.clk(clk),.reset(reset),.din(i_ah_cabt),.q(ah_cabt)); 
   capi_parcheck#(.width(ctxtid_width-1)) ah_lcl_cch_pcheck(.clk(clk),.reset(reset),.i_v(ah_cvalid),.i_d(ah_lcl_cch[0:ctxtid_width-2]),.i_p(ah_lcl_cch[ctxtid_width-1]),.o_error(s1_perror[5]));
   assign ah_cch = ah_lcl_cch[0:ctxtid_width-2]; 
   assign ah_cpad = 3'b010;
   assign ah_ldone = 1'b0;
   
   assign ah_ldtag = 12'h 000;
   assign ah_ldtagpar = 1'b 1;
   assign ah_lroom = 8'h 00;

   wire r2_tag_plus_ok = r2_rvalid_plus & (r2_response_plus == 8'h00);
 
   capi_dma_itag i_dma_itag
     (.clk(clk),.reset(reset),
       .i_v(s2_plus_v),.i_ctag(s2_plus_ctag),.i_size(s2_plus_csize),.i_cmd(s2_plus_cmd),.r2_tag_plus_ok_v(r2_tag_plus_ok),.r2_rtag_plus(r2_rtag_plus),.r2_ritag_plus(r2_ritag_plus),.r2_ritagpar_plus(r2_ritagpar_plus),
      .hd0_sent_utag_valid(hd0_sent_utag_valid),.hd0_sent_utag(hd0_sent_utag),.hd0_sent_utag_sts(hd0_sent_utag_sts),.o_s0_sent_utag_valid(s0_sent_utag_valid),.o_s0_sent_utag(s0_sent_utag),.o_s0_sent_utag_sts(s0_sent_utag_sts),
      .d0h_dvalid(d0h_dvalid),.d0h_req_utag(d0h_req_utag),.d0h_req_itag(d0h_req_itag),.d0h_dtype(d0h_dtype),.d0h_dsize(d0h_dsize),.d0h_datomic_op(d0h_datomic_op),.d0h_datomic_le(d0h_datomic_le),
      .o_dvalid(itag_dvalid),.o_dwad(itag_dwad),.itag_dma_perror(o_perror[41]),.o_tag_error(itag_tag_error),.o_rcb_req_sent(o_dbg_cnt_inc[9]),.i_usource_v(s2_dma_req_plus_v),.i_usource_ctag(s2_dma_req_plus_tag),.i_unit(s2_dma_req_plus_uid),.i_error_status_hld(i_error_status_hld),
      .o_gated_tag_val(gated_utag_val),.i_gated_tag_taken(gated_utag_taken),.o_gated_tag(gated_utag),.i_drop_wrt_pckts(i_drop_wrt_pckts) 
     );

endmodule
   
