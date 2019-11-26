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
module ktms_afu_cmd#
  (
   parameter croom_width = 8,
   parameter croom = 4,
   parameter channels=0,
   parameter syncid_width=1,
   parameter mmiobus_width = 0,
   parameter mmiobus_awidth = 1,
   parameter ctxtid_width = 10,
   parameter dma_rc_width = 0,
   parameter afu_rc_width = 1,
   parameter afu_erc_width =1,
   parameter ea_width = 65,   //changed  to 65 to add ea parity kch
   parameter lba_width = 1,
   parameter rh_width = 1,
   parameter lunid_width = 64,
   parameter lunid_width_w_par = 65,
   parameter datalen_width = 25,
   parameter datalen_par_width = 1,
   parameter datalen_width_w_par = datalen_width+datalen_par_width,
   parameter ioadllen_width = 1,
   parameter msinum_width = 1,
   parameter rrqnum_width = 1,
   parameter cdb_width = 128,
   parameter cdb_width_w_par  = 128 +2,   //added parity 
   parameter la_width = 1,
   parameter rrin_addr = 0,
   parameter flow_ctrl_addr = 0,
   parameter tag_width = 1,      // this is changed to include parity kch 
   parameter tstag_width=tag_width,   // this is changed to include parity kch 
   parameter ssize_width=1,
   parameter ctxtcap_width=1,
   parameter flgs_width = 5, // vhr,sule,tmgmt,afu_cmd,wnr
   parameter [0:dma_rc_width-1] psl_rsp_paged = 0,
   parameter [0:dma_rc_width-1] psl_rsp_addr = 0,
   parameter [0:afu_rc_width-1] afuerr_rcb_dma = 'h40,
   parameter [0:afu_rc_width-1] afuerr_cap = 'h21,
   parameter [0:afu_rc_width-1] afuerr_sync = 'h22,
   parameter [0:afu_rc_width-1] afuerr_ok = 0
   )
  (
   input 					 clk,
   input 					 reset,

   
   output [0:1] 				 o_rm_err, // resource management internal error
   output [0:2] 				 o_dbg_cnt_inc, // debug counters
   output [0:31]                                o_dbg_reg, // 
   output [21:0] 				 o_pipemon_v, // performance monitor
   output [21:0] 				 o_pipemon_r,

   // Update the readable copy of croom register
   output 					 o_croom_we,
   output [0:ctxtid_width-2] 			 o_croom_wa,   // does not have parity kch   changed -1 to -2 cause no parity 
   output [0:croom_width-1] 			 o_croom_wd,
   input [0:7]                                   i_croom_max,

   
   input [0:63] 				 i_rrin_to, // timeout for rrin to rcb fetch in usec

   // change the endian control for a context
   input 					 i_ec_set,
   input 					 i_ec_rst,
   input [0:ctxtid_width-1] 			 i_ec_id,


   // note writes to the context capabilities register    
   input 					 i_cap_wr_v,
   input [0:ctxtid_width-1] 			 i_cap_wr_ctxt, 
   input [0:ctxtcap_width-1] 			 i_cap_wr_d,

   input [0:63] 				 i_timestamp, // current time in cycles
   
   input [0:mmiobus_width-1] 			 i_mmiobus, // mmio bus

   // error injection   
   input 					 i_errinj_croom,
   input 					 i_errinj_rcb_fault,
   input 					 i_errinj_rcb_paged,


   // context add   
   input 					 i_ctxt_add_v,
   input [0:ctxtid_width-1] 			 i_ctxt_add_d, 
   output 					 o_ctxt_add_ack_v,

   // dma engine address interface for reading RCBs
   input 					 o_get_addr_r,
   output 					 o_get_addr_v,
   output [0:ea_width-1] 			 o_get_addr_ea,  // parity added kch 
   output [0:tstag_width-1] 			 o_get_addr_tstag, // parity added kch 
   output [0:ctxtid_width-1] 			 o_get_addr_ctxt,
   output [0:ssize_width-1] 			 o_get_addr_size,

   // dma engine data interface
   output 					 i_get_data_r,
   input 					 i_get_data_v,
   input 					 i_get_data_e,
   input [0:129] 				 i_get_data_d, // changed 127 to 129 to add parity kch
   input [0:dma_rc_width-1] 			 i_get_data_rc, 

   // tag return syncid is no longer used for anything 
   input 					 i_cmpl_v,
   input [0:tag_width-1] 			 i_cmpl_tag,
   input [0:syncid_width-1] 			 i_cmpl_syncid,

   /* note the time when the command bearing a given tag first arrived. 
    this is compared with the time of context attatchment when performing DMA or Interupt
    activites.  If the context attached after the command arrived, DMA or Interupt requests 
    for this tag are ignored.  At one time tstag and tag were potentially different - tstag 
    had a larger range.  In more recent AFUs they are the same. 
    */
   output 					 o_tstag_issue_v,
   output [0:tstag_width-1] 			 o_tstag_issue_id,
   output [0:63] 				 o_tstag_issue_d,
   
   // note the arriaval of a command for debug and performance monitoring
   output 					 o_trk0_v,
   output [0:tag_width-1] 			 o_trk0_tag,     // this has parity kch 
   output [0:63] 				 o_trk0_timestamp,

   /* we inform the timeout unit of every command issued, unless the rrin timeout value has expired. 
      the timeout unit is responsible for timing out commands if reqeusted, and for completing 
      heavy-weight sync commands
    */
   input 					 o_to_r,
   output 					 o_to_v,
   output [0:tag_width-1] 			 o_to_tag, // parity added kch 
   output [0:15] 				 o_to_d, // timeout value
   output [0:1] 				 o_to_flg, // timeout flag
   output [0:63] 				 o_to_ts, // arrival timestamp (cycles)
   output 					 o_to_sync, // 1 if this command is a heavyweight sync
   output 					 o_to_ok, // 1 if this comand was properly fetched.  Not sure why we even bother sending commands where this is 0


   // these timed out before we could issue them.  No timeout had been issued for them.
   // they will never be issued, so just complete them and return the tag
   input 					 o_abrt_r,
   output 					 o_abrt_v,
   output [0:tag_width-1] 			 o_abrt_tag, // parity added kch 
   output [0:ctxtid_width-1] 			 o_abrt_ctxt,         
   output 					 o_abrt_ec, // endian control for this tag
   output [0:ea_width-1] 			 o_abrt_ea, // effective address of the RCB
   output [0:msinum_width-1] 			 o_abrt_msinum, // completion msi
   output [0:syncid_width-1] 			 o_abrt_syncid, // no longer used
   output 					 o_abrt_sule, // suppress underrun (should never be used, since we are aborting)
   output 					 o_abrt_rnw, // this was a read, not a write, command (for per monitor and debug)

   // performance counting
   output 					 o_sc_v,
   output 					 o_sc_r,
   // report flow control errors
   input 					 o_croom_err_r,
   output 					 o_croom_err_v,
   output [0:ctxtid_width-1] 			 o_croom_err_ctxt,

   // command output   
   output 					 o_v,
   input 					 o_r,
   output [0:flgs_width-1] 			 o_flgs, // various flags: see assignment to s1_flgs in ktms_sl_cmddec for definition of the bits
   output 					 o_nocmpl, // don't complete this command (eg sync)
   output [0:syncid_width-1] 			 o_syncid, // no longer used
   output [0:tag_width-1] 			 o_tag, // afu tag for this command - unique per command in flight parity added kch 
   output [0:ctxtid_width-1]                     o_rcb_ctxt, // context for writing ioasa and rrq, and completion interupt
   output                                        o_rcb_ec, // endian control for rcb context
   output [0:ea_width-1]                         o_rcb_ea, // effective address of rcb
   output [0:63]                                 o_rcb_timestamp,
   output                                        o_rcb_hp,
   output [0:rh_width-1]                         o_rh, // resource handle
   output [0:lunid_width_w_par-1]                        o_lunid, // lunid
   output [0:ioadllen_width-1]                   o_ioadllen, // ioadl length
   output [0:datalen_width_w_par-1] 		 o_data_len, // data length
   output [0:ctxtid_width-1] 			 o_data_ctxt, // context for data buffers
   output [0:ea_width-1] 			 o_data_ea, // effective address for data buffers
   output [0:msinum_width-1] 			 o_msinum, // msi number for completion
   output [0:rrqnum_width-1] 			 o_rrq, // rrq number for completion 
   output [0:lba_width-1] 			 o_lba, // lba
   output [0:cdb_width_w_par-1] 			 o_cdb, // cdb
   output [0:channels-1] 			 o_portmsk, // which ports to use
   output [0:afu_rc_width-1] 			 o_rc, // current result code (only valid if o_ok=0, ie something has gone wrong)
   output [0:afu_erc_width-1] 			 o_erc, // current extended result code (only valid if o_ok=0, ie something has gone wrong)
   output 					 o_ok, // 1 if all is ok, 0 if something has gone wrong

   // note when commands are dropped b/c we ran out of room in the input buffer - for debug only, should never happen if sw is well behaved
   output 					 o_cmd_dropped,
   output [0:3]                                  o_perror ,      // added o_perror kch  
   output                                        o_cmpl_error_hld,
   output                                        o_tag_error_hld,
   output                                        o_allocate_afu_tag,
   output                                        o_free_afu_tag,
   output                                        o_no_afu_tags,
   input                                         i_threshold_zero,
   input                                         i_retry_cmd_v,
   output                                        i_retry_cmd_r,
   input [0:(64+65+10)-1]                      i_retry_cmd_d,
   input                                         i_reset_afu_cmd_tag_v,
   output                                        i_reset_afu_cmd_tag_r,
   input [0:9]                                   i_reset_afu_cmd_tag,
   output [0:3*64-1]                             o_arrin_fifo_latency,
   output [0:63]                                 o_arrin_cycles,
   input                                         i_arrin_cnt_reset,
   input                                         i_retry_threshold
   );

   wire [0:2]                                    dbg_cnt_in;
   base_vlat#(.width(3)) idbg_cnt2_lat(.clk(clk),.reset(1'b0),.din(dbg_cnt_in),.q(o_dbg_cnt_inc));

   assign o_rm_err[0] = 1'b0;
   assign o_syncid = 0;
   assign o_abrt_syncid = 0;
   

   // compute a timeout value. drop lower 8 bits to make us
   wire [0:55] 					 s0_rrin_to = i_timestamp[0:55] - {24'd0,i_rrin_to[32:63]};
   wire 					 s0_rrin_to_v = |i_rrin_to;

   wire [0:55] 					 s1_rrin_to;
   wire 					 s1_rrin_to_v;
   base_vlat#(.width(1+56)) s1_rrin_to_lat(.clk(clk),.reset(1'b0),.din({s0_rrin_to_v, s0_rrin_to}),.q({s1_rrin_to_v,s1_rrin_to}));

   
   

   base_const#(.width(ssize_width),.value(64)) icmd_addr_d_size(o_get_addr_size);

   wire 		      mmio_cmd_addr_v;
      wire 		      mmio_cmd_addr_r;
   wire [0:64] 		      mmio_cmd_addr_ea;
   wire [0:ctxtid_width-1]    mmio_cmd_addr_ctxt;

   capi_mmio_mc_reg#(.addr(rrin_addr)) immio_cmd_addr(.clk(clk),.reset(reset),.i_mmiobus(i_mmiobus),.q(mmio_cmd_addr_ea),.trg(mmio_cmd_addr_v),.ctxt(mmio_cmd_addr_ctxt),.o_perror(o_perror[2]));
     
   wire 		      s0_addr_v, s0_addr_r;
   wire [0:ea_width-1]                s0_addr_ea;    // change 63 to ea_width-1 kch 
   wire [0:ctxtid_width-1]    s0_addr_ctxt;
   wire [0:63]                s0_addr_timestamp;

   wire [0:ea_width-1]        s0a_addr_ea;    // change 63 to ea_width-1 kch 
   wire [0:ctxtid_width-1]    s0a_addr_ctxt;
   wire [0:63]                s0a_addr_timestamp;
   wire                       s0a_addr_hp;

   wire [0:ctxtid_width-1]    r1_ctxt;
   wire [0:ea_width-1]        r1_ea;
   wire [0:63] 		      r1_timestamp;

   wire 		      r0a_r, r0a_v;
   wire [0:ctxtid_width-1]    r0_ctxt;
   wire [0:ea_width-1] 	      r0_ea;
   wire 		      mmio_cmd_v = mmio_cmd_addr_v & ~mmio_cmd_addr_ea[63];

   wire [0:5] 				s1_perror;
   capi_parcheck#(.width(64)) mmio_cmd_addr_ea_pcheck(.clk(clk),.reset(reset),.i_v(mmio_cmd_v),.i_d(mmio_cmd_addr_ea[0:63]),.i_p(mmio_cmd_addr_ea[64]),.o_error(s1_perror[0]));
   wire [0:5] 				hld_perror;
   wire                                 any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(6)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(6'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(any_hld_perror),.q(o_perror[0]));
   
   base_alatch#(.width(65+ctxtid_width)) ir0_lat    // changed 64 to 65 kch 
     (.clk(clk),.reset(reset),
      .i_v(mmio_cmd_v),.i_d({mmio_cmd_addr_ctxt,mmio_cmd_addr_ea}),.i_r(mmio_cmd_addr_r),
      .o_r(r0a_r), .o_v(r0a_v),.o_d({r0_ctxt,r0_ea})
      );

   // count number of rrins we have that are not context reset
   assign dbg_cnt_in[0] = r0a_v & r0a_r;

   // note when we drop a command because we ran out of room
   assign o_cmd_dropped = mmio_cmd_v & ~mmio_cmd_addr_r & ~mmio_cmd_addr_ea[63];
   
   
   wire 		      r0b_v, r0b_r;
`ifdef TIMEOUT_TEST   
   wire [0:tag_width-1] 	     r0_cnt;
   base_vlat#(.width(tag_width-1)) ir0_cnt_lat(.clk(clk),.reset(reset),.din(r0_cnt[0:tag_width-2]+1),.q(r0_cnt[0:tag_width-2]));   // strip off parity kch 
   wire 			     r0_en = r0_cnt == 9'd100;
`else
   wire                              r0_en = 1'b1;
`endif   

   wire [0:1] r1a_v,r1a_r; 
   base_agate ir0_cmd_gt(.i_v(r0a_v),.i_r(r0a_r),.o_v(r0b_v),.o_r(r0b_r),.en(r0_en));
   base_alatch#(.width(64+65+ctxtid_width)) ir1_lat  // changed 64 to 64 for ea parity kch 
     (.clk(clk),.reset(reset),
      .i_v(r0b_v),.i_d({i_timestamp,r0_ctxt,r0_ea}),.i_r(r0b_r),
      .o_r(r1a_r[0]), .o_v(r1a_v[0]),.o_d({r1_timestamp,r1_ctxt,r1_ea})
      );

   wire 		      r1b_v, r1b_r;
   base_acombine#(.ni(2),.no(1)) ir1_cmb(.i_v(r1a_v),.i_r(r1a_r),.o_v(r1b_v),.o_r(r1b_r));

   wire [0:1] 		      r1c_v, r1c_r;
   wire 		      r1_croom_err;
   
   base_ademux#(.ways(2)) ir1_demux(.i_v(r1b_v),.i_r(r1b_r),.o_v(r1c_v),.o_r(r1c_r),.sel({r1_croom_err,~r1_croom_err}));
   assign o_croom_err_v = r1c_v[0];
   assign r1c_r[0] = o_croom_err_r;
   assign o_croom_err_ctxt = r1_ctxt;



   
`ifdef SIM_RETRY   
   base_fifo#(.width(64+65+ctxtid_width),.LOG_DEPTH(4),.output_reg(1)) immio_cmd_fifo    // changed 64 to 65 for ea parity  
`else
   base_fifo#(.width(64+65+ctxtid_width),.LOG_DEPTH(11),.output_reg(1)) immio_cmd_fifo    // changed 64 to 65 for ea parity  
`endif                                
     (.clk(clk),.reset(reset),
      .i_v(r1c_v[1]),.i_r(r1c_r[1]),.i_d({r1_timestamp,r1_ea,r1_ctxt}),
      .o_v(s0_addr_v),.o_r(s0_addr_r),.o_d({s0_addr_timestamp,s0_addr_ea,s0_addr_ctxt}));

   assign dbg_cnt_in[1] = s0_addr_v & s0_addr_r ;   // count commands out of fifo

  wire cmd_enter_fifo = r1c_v[1] & r1c_r[1];
  wire cmd_exit_fifo = s0_addr_v & s0_addr_r;
  wire [0:9] arrin_active;
  wire [0:63] arrin_complete,arrin_sum;

  nvme_perf_count#(.sum_width(64),.active_width(10)) iafu_tag_perf (.reset(reset),.clk(clk),
                                                                  .incr(cmd_enter_fifo), .decr(cmd_exit_fifo), .clr(i_arrin_cnt_reset),
                                                                  .active_cnt(arrin_active), .complete_cnt(arrin_complete), .sum(arrin_sum), .clr_sum(i_arrin_cnt_reset));

   assign o_arrin_fifo_latency = {arrin_sum,arrin_complete,54'b0,arrin_active}; 


 wire [0:63] arrin_cycles;
 wire [0:15] arrin_cnt;
 wire arrin_cycle_enable = ((arrin_cnt != 16'd10000) & (arrin_cnt != 16'd0)) | i_arrin_cnt_reset ;
// wire arrin_cnt_enable = ((r1c_v[1] & r1c_r[1]) | i_arrin_cnt_reset);
 wire arrin_cnt_enable = ((r1c_v[1] & r1c_r[1] & (arrin_cnt != 16'd10000)) | i_arrin_cnt_reset) ;
 wire [0:15] arrin_cnt_in = i_arrin_cnt_reset ? 16'h0000 : arrin_cnt+16'd1;
 wire [0:63] arrin_cycles_in = i_arrin_cnt_reset ? 64'h0000 : o_arrin_cycles+64'd1;

 
 base_vlat_en#(.width(16)) iarrin_cnt(.clk(clk),.reset(reset),.din(arrin_cnt_in),.q(arrin_cnt),.enable(arrin_cnt_enable));
 base_vlat_en#(.width(64)) iarrin_cycles (.clk(clk),.reset(reset),.din(arrin_cycles_in),.q(o_arrin_cycles),.enable(arrin_cycle_enable));

   
//   wire                     s0_addr_timedout = s1_rrin_to_v & ~s1_rrin_to[0] & (s0_addr_timestamp[0:55] < s1_rrin_to);
   wire                       s0a_addr_timedout = s1_rrin_to_v & ~s1_rrin_to[0] & (s0a_addr_timestamp[0:55] < s1_rrin_to);
   
   wire                       s1a_addr_v, s1a_addr_r;
   wire [0:ea_width-1]                s1_addr_ea;
   wire [0:ctxtid_width-1]    s1_addr_ctxt;
   wire [0:63]                s1_addr_timestamp;
   wire                       s1_addr_hp;
   wire                       s0a_addr_v,s0a_addr_r;


//   assign dbg_cnt_in[1] = s0_addr_v & s0_addr_r & s0_addr_timedout;

   base_agate retry_gt(.i_v(s0_addr_v),.i_r(s0_addr_r),.o_v(s0g_addr_v),.o_r(s0g_addr_r),.en(~i_retry_threshold));

//kkkkkg
   base_primux#(.ways(2),.width(64+65+10+1)) icmd_mux(.i_v({i_retry_cmd_v,s0g_addr_v}),.i_r({i_retry_cmd_r,s0g_addr_r}),.i_d({i_retry_cmd_d,1'b1,s0_addr_timestamp,s0_addr_ea,s0_addr_ctxt,1'b0}),
                                                       .o_v(s0a_addr_v),.o_r(s0a_addr_r),.o_d({s0a_addr_timestamp,s0a_addr_ea,s0a_addr_ctxt,s0a_addr_hp}),.o_sel());


   
   base_alatch#(.width(1+64+65+ctxtid_width+1)) is1_addr_lat     //changed 64 to 65 for ea parity,
     (.clk(clk),.reset(reset),
      .i_v(s0a_addr_v), .i_r(s0a_addr_r), .i_d({s0a_addr_timedout,s0a_addr_timestamp,s0a_addr_ea,s0a_addr_ctxt,s0a_addr_hp}),
      .o_v(s1a_addr_v),.o_r(s1a_addr_r),.o_d({s1_addr_timedout,s1_addr_timestamp,s1_addr_ea,s1_addr_ctxt,s1_addr_hp}));

   
   wire                       s1_tag_v, s1_tag_r;
   wire [0:tag_width-1]       s1_tag;
   wire                       i_cmpl_r_nc;
   wire                       cmb_cmpl_v;
   wire [0:9]                 cmb_cmpl_tag;  

   base_primux#(.ways(2),.width(10)) ireset_mux(.i_v({i_cmpl_v,i_reset_afu_cmd_tag_v}),.i_r({i_cmpl_r_nc,i_reset_afu_cmd_tag_r}),.i_d({i_cmpl_tag,i_reset_afu_cmd_tag}),
                                                       .o_v(cmb_cmpl_v),.o_r(1'b1),.o_d(cmb_cmpl_tag),.o_sel());


   capi_res_mgr#(.id_width(tag_width),.parity(1)) itag_mgr        // s1_tag has parity 
     (.clk(clk),.reset(reset),
      .o_free_err(o_rm_err[1]),
      .i_free_v(cmb_cmpl_v),.i_free_id(cmb_cmpl_tag),
      .o_avail_v(s1_tag_v),.o_avail_r(s1_tag_r),.o_avail_id(s1_tag),.o_cnt(),.o_perror(o_perror[1]));  // has parity kch 

    assign o_allocate_afu_tag = s1_tag_v & s1_tag_r;
    assign o_free_afu_tag = cmb_cmpl_v; 
   

   // check for tag errors 
   wire s1_cmpl_tag_v;
   wire s2_tag_check_v;
   base_vlat#(.width(1)) i_dlay_cmplt_tag(.clk(clk),.reset(reset),.din(cmb_cmpl_v),.q(s1_cmpl_tag_v));
   base_vlat#(.width(1)) i_dlay_tag(.clk(clk),.reset(reset),.din(s1_tag_v & s1_tag_r),.q(s2_tag_check_v));
   base_vmem#(.a_width(tag_width-1),.rports(2)) ots_vmem  // added -1 kch 
     (.clk(clk),.reset(reset),
      .i_set_v(s1_tag_v & s1_tag_r),.i_set_a(s1_tag[0:tag_width-2]),  // added [0:tag_width-2] kch
      .i_rst_v(cmb_cmpl_v),.i_rst_a(cmb_cmpl_tag[0:tag_width-2]),  // added 0:tag_width-2 kch
      .i_rd_en(2'b11),.i_rd_a({cmb_cmpl_tag[0:tag_width-2],s1_tag[0:tag_width-2]}),.o_rd_d({s1_cmpl_outst,s2_tag_outst})
      );
   wire s1_cmpl_error = s1_cmpl_tag_v & ~(s1_cmpl_outst);
   wire s2_tag_error = s2_tag_check_v & (s2_tag_outst);

    base_vlat_en#(.width(1))  icmplterror (.clk(clk),.reset(reset),.din(s1_cmpl_error),  .q(o_cmpl_error_hld),    .enable(s1_cmpl_error));
    base_vlat_en#(.width(1))  itagerror (.clk(clk),.reset(reset),.din(s2_tag_error),  .q(o_tag_error_hld),    .enable(s2_tag_error));


   wire [0:tag_width-1] 	      s1_tag_cnt;  // added -1 to strip off parity 
   // chicken switch to set threshold = 0 
   localparam [0:tag_width-1-1] tag_threshold = 2;  
   wire [0:tag_width-1-1] temp_tag_threshold = i_threshold_zero ? 0 : tag_threshold; 
   
   base_incdec#(.width(tag_width+1-1),.rstv(1<<(tag_width-1))) itag_cnt   // added -1 to strip off parity kch 
     (.clk(clk),.reset(reset),
      .i_dec(s1_tag_v & s1_tag_r),
      .i_inc(cmb_cmpl_v),
      .o_cnt(s1_tag_cnt),.o_zero()
      );
//   wire                     s1_tag_en = (s1_tag_cnt > tag_threshold) | s1_addr_timedout;
   wire 		      s1_tag_en = (s1_tag_cnt > temp_tag_threshold) | s1_addr_timedout;
   wire 		      s1a_tag_v, s1a_tag_r;
   wire [0:9]                 s1_threshold = tag_threshold;
   base_agate is1_tag_gt(.i_v(s1_tag_v),.i_r(s1_tag_r),.o_v(s1a_tag_v),.o_r(s1a_tag_r),.en(s1_tag_en));

   assign o_no_afu_tags = ~s1_tag_en;
   
   base_alatch#(.width(tag_width+64)) itstag_issue_lat
     (.clk(clk),.reset(reset),.i_v(s1a_tag_v & s1a_tag_r),.i_r(),.i_d({s1_tag,s1_addr_timestamp}),.o_v(o_tstag_issue_v),.o_r(1'b1),.o_d({o_tstag_issue_id,o_tstag_issue_d}));

   // 0: get address
   // 1: fifo
   // 2: croom counter
   wire [0:2]		      s1_v, s1_r;
   base_acombine#(.ni(2),.no(3)) is1_cmb(.i_v({s1a_addr_v,s1a_tag_v}),.i_r({s1a_addr_r,s1a_tag_r}),.o_v(s1_v),.o_r(s1_r));

   wire                       s1a_v, s1a_r;
   // don't decrement flow control count for retried transactions
   base_afilter is1a_fltr(.i_v(s1_v[2]),.i_r(s1_r[2]),.o_v(s1a_v),.o_r(s1a_r),.en(~s1_addr_hp));  
   
   // track the assignment of tag for performance 
   assign o_trk0_v = s1_v[0] & s1_r[0];
   assign o_trk0_tag = s1_tag;
   assign o_trk0_timestamp = s1_addr_timestamp;

   wire [0:croom_width-1]     wmax_outst;
   base_const#(.value(croom),.width(croom_width)) imax_outst(wmax_outst);

   wire [0:croom_width-1]     t1_croom_woutst;

   ktms_mc_incdec#(.id_width(ctxtid_width-1),.width(croom_width),.maxv(croom)) ifc_incdec   // added -1 to ctxtid_width to strip of parity kch 
     (.clk(clk),.reset(reset),
      .i_rst_v(i_ctxt_add_v),.i_rst_id(i_ctxt_add_d[0:ctxtid_width-2]),.o_rst_ack(o_ctxt_add_ack_v),         // add ctxtid_width -2 to inputs kch  
      .i_inc_v(mmio_cmd_v),.i_inc_id(mmio_cmd_addr_ctxt[0:ctxtid_width-2]),.i_inc_frc_oflw(i_errinj_croom),
      .o_inc_v(r1a_v[1]),.o_inc_r(r1a_r[1]),.o_inc_err(r1_croom_err),
      .i_dec_v(s1a_v),.i_dec_r(s1a_r),.i_dec_id(s1_addr_ctxt[0:ctxtid_width-2]),
      .i_maxv(i_croom_max[0:7]),
      .o_we(o_croom_we),.o_wa(o_croom_wa),.o_wd(t1_croom_woutst)
      );
//   wire [0:croom_width-1]     t1_croom_wd = wmax_outst - t1_croom_woutst;
   wire [0:croom_width-1]     t1_croom_wd = i_croom_max[0:7] - t1_croom_woutst;
   assign o_croom_wd = t1_croom_wd;

   wire 		      s1_addr_misaligned = | s1_addr_ea[60:63];

   capi_parcheck#(.width(64)) s1_addr_ea_pcheck(.clk(clk),.reset(reset),.i_v(s1a_addr_v),.i_d(s1_addr_ea[0:63]),.i_p(s1_addr_ea[64]),.o_error(s1_perror[1]));

   base_afilter is1_addr_fltr(.i_v(s1_v[0]),.i_r(s1_r[0]),.o_v(o_get_addr_v),.o_r(o_get_addr_r),.en(~s1_addr_misaligned));
   
   // force 8 byte allignment
   assign o_get_addr_ea = s1_addr_ea;
   assign o_get_addr_tstag = s1_tag;
   assign o_get_addr_ctxt = s1_addr_ctxt;

      
   // track when this gets full
   assign o_sc_v = s1_v[1];
   assign o_sc_r = s1_r[1];
   
   wire 		      s2_v, s2_r;
   wire [0:tag_width-1]       s2_tag;
   wire [0:ctxtid_width-1]    s2_rcb_ctxt;
   wire [0:ea_width-1] 	      s2_rcb_ea;
   wire                       s2_addr_misaligned;
   wire [0:63]                s2_timestamp;
   wire                       s2_timedout;
   wire                       s2_hp;
   localparam aux_width=1+tag_width+ctxtid_width+ea_width+64;

   
   base_fifo#(.LOG_DEPTH(3),.width(aux_width+1+1),.output_reg(1)) is2_fifo // no ec for this stage    
     (.clk(clk),.reset(reset),
      .i_v(s1_v[1]),.i_r(s1_r[1]),.i_d({s1_addr_misaligned,s1_tag,s1_addr_ctxt,s1_addr_ea,s1_addr_timestamp,s1_addr_timedout,s1_addr_hp}),
      .o_v(s2_v),   .o_r(s2_r),   .o_d({s2_addr_misaligned,s2_tag, s2_rcb_ctxt, s2_rcb_ea,s2_timestamp,s2_timedout,s2_hp}));

   wire                       s3a_v, s3a_r;
   wire [0:tag_width-1]       s3_tag;
   wire [0:ctxtid_width-1]    s3_rcb_ctxt;
   wire [0:ea_width-1]        s3_rcb_ea;
   wire                       s3_addr_misaligned;
   wire [0:63]                s3_timestamp;
   wire                       s3_timeout;
   wire                       s3_hp;

   wire                       s2_en;
   base_alatch_oe#(.width(aux_width+1+1)) is3_lat // no ec  
     (.clk(clk),.reset(reset),
      .i_v(s2_v),   .i_r(s2_r),   .i_d({s2_addr_misaligned,s2_tag, s2_rcb_ctxt, s2_rcb_ea,s2_timestamp,s2_timedout,s2_hp}),
      .o_v(s3a_v),   .o_r(s3a_r), .o_d({s3_addr_misaligned,s3_tag, s3_rcb_ctxt, s3_rcb_ea,s3_timestamp,s3_timedout,s3_hp}),.o_en(s2_en));

   // get rcb endianness
   wire                       s3_rcb_ec;
   base_vmem#(.a_width(ctxtid_width-1)) is3_vmem   // added -1 to strip of parity kch 
     (.clk(clk),.reset(reset),
      .i_set_v(i_ec_set),.i_set_a(i_ec_id[0:ctxtid_width-2]),
      .i_rst_v(i_ec_rst),.i_rst_a(i_ec_id[0:ctxtid_width-2]),
      .i_rd_en(s2_en),.i_rd_a(s2_rcb_ctxt[0:ctxtid_width-2]),.o_rd_d(s3_rcb_ec)
      );

   //0: endian control mux
   //1: next stage
   wire [0:1] 		      s3b_v, s3b_r;
   base_acombine#(.ni(1),.no(2)) is3_cmb(.i_v(s3a_v),.i_r(s3a_r),.o_v(s3b_v),.o_r(s3b_r));

   wire 		      s3c_v, s3c_r;
   base_afilter is3_fltr(.i_v(s3b_v[0]),.i_r(s3b_r[0]),.o_v(s3c_v),.o_r(s3c_r),.en(~s3_addr_misaligned));

   wire 		      s4a_v, s4a_r;
   wire [0:7] 		      s4_afu_opc;
   wire [0:7] 		      s4_afu_mod;
   
   wire [0:msinum_width-1]    s4_msinum;
   wire [0:rrqnum_width-1]    s4_rrq;
   
   wire [0:rh_width-1] 	      s4_rh;
   wire [0:lunid_width_w_par-1]     s4_lunid;
   wire [0:ioadllen_width-1]  s4_ioadllen;
   wire [0:datalen_width_w_par-1]   s4_data_len;
   wire [0:ctxtid_width-1]    s4_data_ctxt;
   wire 		      s4_data_ctxt_v;
   wire [0:ea_width-1] 	      s4_data_ea;
   wire [0:cdb_width_w_par-1]       s4_cdb;
   wire [0:channels-1] 	      s4_portmsk;       
   wire [0:dma_rc_width-1]    s4_dma_rc;
   wire [0:1] 		      s4_to_flg;
   wire [0:15] 		      s4_to_d;
   wire [0:flgs_width-1]      s4_flgs;

   ktms_sl_cmddec#
     (
      .channels(channels),
      .ea_width(ea_width),
      .ctxtid_width(ctxtid_width),
      .rh_width(rh_width),
      .lunid_width(lunid_width),
      .datalen_width(datalen_width),
      .ioadllen_width(ioadllen_width),
      .msinum_width(msinum_width),
      .rrqnum_width(rrqnum_width),
      .cdb_width(cdb_width),
      .dma_rc_width(dma_rc_width),
      .psl_rsp_paged(psl_rsp_paged),
      .psl_rsp_addr(psl_rsp_addr),
      .flgs_width(flgs_width)
      ) isl_dec
   (.clk(clk),.reset(reset),
    .i_ec_v(s3c_v),
    .i_ec_r(s3c_r),
    .i_ec_d(s3_rcb_ec),

    .i_r(i_get_data_r),.i_v(i_get_data_v),.i_e(i_get_data_e),.i_d(i_get_data_d),.i_rc(i_get_data_rc),
    .i_errinj_rcb_fault(i_errinj_rcb_fault),
    .i_errinj_rcb_paged(i_errinj_rcb_paged),
    .o_afu_opc(s4_afu_opc),
    .o_afu_mod(s4_afu_mod),
    .o_rh(s4_rh),
    .o_portmsk(s4_portmsk),
    .o_lunid(s4_lunid),
    .o_ioadllen(s4_ioadllen),
    .o_data_len(s4_data_len),
    .o_data_ea(s4_data_ea),
    .o_data_ctxt(s4_data_ctxt),
    .o_data_ctxt_v(s4_data_ctxt_v),    
    .o_msinum(s4_msinum),
    .o_timeout_flg(s4_to_flg),
    .o_timeout_d(s4_to_d),
    .o_rrq(s4_rrq),
    .o_cdb(s4_cdb),
    .o_rc(s4_dma_rc),
    .o_flgs(s4_flgs),
    .o_v(s4a_v),
    .o_r(s4a_r),
    .o_perror(o_perror[3])   // added o_perror kch 
);
   
   wire [0:1] 		      s4_v, s4_r;

   // latch to allow capability lookup for the context
   wire [0:tag_width-1]       s4_tag;
   wire [0:ctxtid_width-1]      s4_rcb_ctxt;
   wire 		      s4_rcb_ec; // endian control
   wire [0:ea_width-1] 	      s4_rcb_ea;
   wire                       s4_addr_misaligned;
   wire [0:63]                s4_timestamp;
   wire                       s4_timedout;
   wire                       s4_hp;
   base_alatch#(.width(aux_width+1+1+1)) is4_lat  
     (.clk(clk),.reset(reset),
      .i_v(s3b_v[1]),.i_r(s3b_r[1]), .i_d({      s3_addr_misaligned, s3_tag,  s3_rcb_ctxt, s3_rcb_ea, s3_timestamp, s3_rcb_ec, s3_timedout,s3_hp}),
      .o_v(s4_v[1]),.o_r(s4_r[1]),   .o_d({      s4_addr_misaligned, s4_tag,  s4_rcb_ctxt, s4_rcb_ea, s4_timestamp, s4_rcb_ec, s4_timedout,s4_hp}));

   base_aforce is4_frc(.i_v(s4a_v),.i_r(s4a_r),.o_v(s4_v[0]),.o_r(s4_r[0]),.en(~s4_addr_misaligned));
   
   
   capi_parcheck#(.width(ctxtid_width-1)) s4_rcb_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s4_v[1]),.i_d(s4_rcb_ctxt[0:ctxtid_width-2]),.i_p(s4_rcb_ctxt
[ctxtid_width-1]),.o_error(s1_perror[2]));
   capi_parcheck#(.width(ctxtid_width-1)) s4_data_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s4_data_ctxt_v),.i_d(s4_data_ctxt[0:ctxtid_width-2]),.i_p(s4_data_ctxt[ctxtid_width-1]),.o_error(s1_perror[3]));
   capi_parcheck#(.width(64)) s4_cdb_pcheck0(.clk(clk),.reset(reset),.i_v(s4a_v),.i_d(s4_cdb[0:63]),.i_p(s4_cdb[128]),.o_error(s1_perror[4]));
   capi_parcheck#(.width(64)) s4_cdb_pcheck1(.clk(clk),.reset(reset),.i_v(s4a_v),.i_d(s4_cdb[64:127]),.i_p(s4_cdb[129]),.o_error(s1_perror[5]));
   
   wire                       s4_afu_cmd = s4_flgs[1];
   wire [63:0] 		      s4_lba = s4_cdb[2*8:10*8-1];
   wire 		      s4_opc_read = ~s4_afu_cmd & (s4_cdb[0:7] == 8'h88);
   wire 		      s4_opc_write = ~s4_afu_cmd & ((s4_cdb[0:7] == 8'h8A) ||(s4_cdb[0:7] == 8'h93)) ;  // 0x8A=WRITE(16)  0x93=WRITE_SAME
   wire 		      s4_proxy = ~s4_afu_cmd & ~(s4_data_ctxt == s4_rcb_ctxt);
   wire 		      s4_err_dma = | s4_dma_rc;

   wire [0:afu_rc_width-1]      s4_rc = (s4_addr_misaligned | s4_err_dma) ? afuerr_rcb_dma : afuerr_ok;
   wire [0:afu_erc_width-1] 	s4_erc = s4_err_dma & ~s4_addr_misaligned ? s4_dma_rc : {afu_erc_width{1'b0}};
   wire 			s4_ok = ~s4_err_dma & ~s4_addr_misaligned;
   wire 			s4_sync = s4_afu_cmd & (s4_afu_opc == 8'hC0) & ((s4_afu_mod == 8'h1) | (s4_afu_mod == 8'h2));
   
   wire 		      s4b_v, s4b_r;
   base_acombine#(.ni(2),.no(1)) is4_cmb(.i_v(s4_v),.i_r(s4_r),.o_v(s4b_v),.o_r(s4b_r));


  

   localparam zero_width = lunid_width_w_par+ioadllen_width+datalen_width_w_par+ctxtid_width+ea_width+cdb_width_w_par+channels+rh_width+afu_rc_width+afu_erc_width+lba_width;
   localparam [0:zero_width-1] s6_zero = 0;
   localparam [0:flgs_width-1] s6_flgs = 5'b01000;

   localparam omux_width = 1+1+tag_width+ctxtid_width+1+ea_width+msinum_width+rrqnum_width+flgs_width+zero_width;

   wire                        s5a_v;
   wire 		       s5a_r;
   wire 		       s5_sync;
   wire [0:tag_width-1]        s5_tag;
   wire [0:ctxtid_width-1]     s5_rcb_ctxt;
   wire 		       s5_rcb_ec;
   wire [0:ea_width-1] 	       s5_rcb_ea;
   wire [0:msinum_width-1]     s5_msinum;
   wire [0:rrqnum_width-1]     s5_rrq;
   wire [0:flgs_width-1]       s5_flgs;
   
   wire [0:lunid_width_w_par-1]      s5_lunid;
   wire [0:ioadllen_width-1]   s5_ioadllen;
   wire [0:datalen_width_w_par-1]    s5_data_len;
   wire [0:ctxtid_width-1]     s5_data_ctxt;
   wire [0:ea_width-1] 	       s5_data_ea;
   wire [0:cdb_width_w_par-1]        s5_cdb;
   wire [0:channels-1] 	       s5_portmsk;
   wire [0:rh_width-1] 	       s5_rh;
   wire 		       s5_wnr; 
   wire 		       s5_sule;
   wire [0:afu_rc_width-1]     s5_rc_in;
   wire [0:afu_erc_width-1]    s5_erc_in;
   wire [0:lba_width-1]        s5_lba;
   wire 		       s5_proxy;
   wire 		       s5_ok_in;
   wire 		       s5_opc_read;
   wire 		       s5_opc_write;
   wire 		       s5_timedout;
   wire                        s4_re;

   wire [0:63]                 s5_timestamp;
   wire                        s5_hp;
   wire [0:15]                 s5_to_d;
   wire [0:1]                  s5_to_flg;
   
   base_alatch_oe#(.width(64+16+2+4+omux_width+1)) is5_lat  
     (.clk(clk),.reset(reset),
      .i_v(s4b_v),
      .i_r(s4b_r),
      .i_d({s4_timestamp,s4_to_d,s4_to_flg,s4_timedout,s4_opc_read,s4_opc_write,s4_proxy, s4_sync, s4_ok,   s4_tag,s4_rcb_ctxt,s4_rcb_ec,s4_rcb_ea,s4_msinum,s4_rrq,s4_flgs,s4_lunid,s4_ioadllen,s4_data_len,s4_data_ctxt,s4_data_ea,s4_cdb,s4_portmsk,s4_rh,s4_rc,  s4_erc,    s4_lba[lba_width-1:0],s4_hp}),
      .o_d({s5_timestamp,s5_to_d,s5_to_flg,s5_timedout,s5_opc_read,s5_opc_write,s5_proxy, s5_sync, s5_ok_in,s5_tag,s5_rcb_ctxt,s5_rcb_ec,s5_rcb_ea,s5_msinum,s5_rrq,s5_flgs,s5_lunid,s5_ioadllen,s5_data_len,s5_data_ctxt,s5_data_ea,s5_cdb,s5_portmsk,s5_rh,s5_rc_in,s5_erc_in,s5_lba,s5_hp}),
      .o_v(s5a_v),.o_r(s5a_r),
      .o_en(s4_re)
      );
   wire [0:ctxtcap_width-1]    s5_data_ctxtcap;
   base_mem#(.addr_width(ctxtid_width-1),.width(ctxtcap_width)) is5_data_capmem   // added -1 to strip off parity kch 
     (.clk(clk),
      .re(s4_re),.ra(s4_data_ctxt[0:ctxtid_width-2]),.rd(s5_data_ctxtcap),   // added -2 to strip parity off kch 
      .we(i_cap_wr_v),.wa(i_cap_wr_ctxt[0:ctxtid_width-2]),.wd(i_cap_wr_d)    // added -2 to strip parity off kch 
      );

   wire [0:ctxtcap_width-1]   s5_rcb_ctxtcap;
   base_mem#(.addr_width(ctxtid_width-1),.width(ctxtcap_width)) is5_rcb_capmem    // added -1 to strip off parity kch 
     (.clk(clk),
      .re(s4_re),.ra(s4_rcb_ctxt[0:ctxtid_width-2]),.rd(s5_rcb_ctxtcap),    // added -2 to strip parity off kch 
      .we(i_cap_wr_v),.wa(i_cap_wr_ctxt[0:ctxtid_width-2]),.wd(i_cap_wr_d)   // added -2 to strip parity off kch 
      );
   // error handling
   localparam ccap_proxy_src  = 0;
   localparam ccap_real_mode  = 1;
   localparam ccap_proxy_tgt  = 2;
   localparam ccap_afu_cmds   = 3;
   localparam ccap_gscsi_cmds = 4;
   localparam ccap_write_cmds = 5;
   localparam ccap_read_cmds  = 6;

   wire [0:ctxtcap_width-1] 		      s5_perm_req;
   wire 				      s5_afu_cmd = s5_flgs[1];
   wire 				      s5_vrh = s5_flgs[0];
   assign s5_perm_req[ccap_proxy_src] =  ~s5_afu_cmd & s5_proxy;
   assign s5_perm_req[ccap_real_mode] =  ~s5_afu_cmd & ~s5_vrh;
   assign s5_perm_req[ccap_proxy_tgt] =  ~s5_afu_cmd & s5_proxy;
   assign s5_perm_req[ccap_afu_cmds]  =   s5_afu_cmd & ~s5_sync;  // no special permission needed for hw sync
   assign s5_perm_req[ccap_gscsi_cmds] = ~s5_afu_cmd & ~s5_opc_read & ~s5_opc_write;
   assign s5_perm_req[ccap_write_cmds] = ~s5_afu_cmd & s5_opc_write;
   assign s5_perm_req[ccap_read_cmds]  = ~s5_afu_cmd & s5_opc_read;


   
   wire [0:ctxtcap_width-1] 		      s5_perm_gnt = {s5_rcb_ctxtcap[0:1],s5_data_ctxtcap[2],s5_rcb_ctxtcap[3:6]};
   wire [0:ctxtcap_width-1] 		      s5_perm_err = s5_perm_req & ~s5_perm_gnt;
   wire [0:afu_erc_width-1] 		      s5_erc_perm_err = s5_perm_err;
   
   wire 				      s5_err_perm = | s5_perm_err;
//   wire 				      s5_err_perm = 1'b1;  // force cap error
   
   wire [0:afu_rc_width-1] 		      s5_err_rc = afuerr_cap;
   wire 				      s5_err = s5_err_perm ;
   
   wire [0:afu_rc_width-1] 		      s5_rc;
   wire [0:afu_erc_width-1] 		      s5_erc;
   wire 				      s5_ok;

   wire  [0:31]                               error_21_hld ; 
   wire                                       error21_nz = |(error_21_hld);                  

   wire  [0:31]                               error21_in = (s5_err_perm & s5a_v & ~error21_nz) ? {7'd0,s5_data_ctxt[0:ctxtid_width-2],1'b0,s5_perm_gnt,1'b0,s5_perm_req} : error_21_hld;

   base_vlat#(.width(32)) ie21_lat(.clk(clk),.reset(reset),.din(error21_in),.q(error_21_hld));
   assign o_dbg_reg = error_21_hld;


   ktms_afu_errmux#(.rc_width(afu_rc_width+afu_erc_width)) is5_errmux
     (.i_ok(s5_ok_in),.i_rc({s5_rc_in,s5_erc_in}),.i_err(s5_err),.i_err_rc({s5_err_rc,s5_erc_perm_err}), .o_ok(s5_ok),.o_rc({s5_rc,s5_erc}));


   // paths for output
   // 0:  timed out instructions go nowhere else
   // 1:  instructions without error get logged in timeout module
   // 2:  instructions that are not syncs or have errors go to normal output
   
      
   // two paths - 0 for normal instruction, 1 for hw sync
   wire [0:2] 				      s5_en;
   wire [0:2] 				      s5b_v, s5b_r;
   base_acombine#(.ni(1),.no(3)) is5_cmb(.i_v(s5a_v),.i_r(s5a_r),.o_v(s5b_v),.o_r(s5b_r));

   //0: abort due to early timeout
   //1: to timeout unit
   //2: to command path
   
   assign s5_en[0]  = s5_timedout;
   assign s5_en[1] = ~s5_timedout;
   assign s5_en[2] = ~s5_timedout;

   wire [0:2] 				      s5c_v, s5c_r;
   base_afilter is5_fltr0(.en(s5_en[0]),.i_v(s5b_v[0]),.i_r(s5b_r[0]),.o_v(s5c_v[0]),.o_r(s5c_r[0]));
   base_afilter is5_fltr1(.en(s5_en[1]),.i_v(s5b_v[1]),.i_r(s5b_r[1]),.o_v(s5c_v[1]),.o_r(s5c_r[1]));
   base_afilter is5_fltr2(.en(s5_en[2]),.i_v(s5b_v[2]),.i_r(s5b_r[2]),.o_v(s5c_v[2]),.o_r(s5c_r[2]));


//   assign dbg_cnt_in[1] = s5c_v[0] & s5c_r[0];
   assign dbg_cnt_in[2] = s5c_v[1] & s5c_r[1];

   assign s5_wnr = 1'b0;
   
   // 0: timed out commands are aborted here   
   base_alatch_burp#(.width(tag_width+ctxtid_width+1+ea_width+msinum_width+1+1)) iabrt_lat  
     (.clk(clk),.reset(reset),
      .i_v(s5c_v[0]),.i_r(s5c_r[0]),.i_d({    s5_tag, s5_rcb_ctxt, s5_rcb_ec, s5_rcb_ea     ,s5_msinum,         ~s5_wnr,     s5_sule}),
      .o_v(o_abrt_v),.o_r(o_abrt_r),.o_d({o_abrt_tag, o_abrt_ctxt, o_abrt_ec, o_abrt_ea, o_abrt_msinum,      o_abrt_rnw, o_abrt_sule})
      );

   //1; commands registered with timeout module for later timeout or sync completion
   assign o_to_v = s5c_v[1];
   assign s5c_r[1] = o_to_r;
   assign o_to_sync = s5_sync;
   assign o_to_tag = s5_tag;
   assign o_to_d = s5_to_d;
   assign o_to_flg = s5_to_flg;
   assign o_to_ts = s5_timestamp;
   assign o_to_ok = s5_ok;
   

   
   wire                                       s5_nocmpl = s5_sync & s5_ok;// ok syncs will be completed by the timeout unit

   //2: normal command output
   base_alatch#(.width(omux_width+1+64)) is6_olat
     (.clk(clk),.reset(reset),
      .i_v(s5c_v[2]),.i_r(s5c_r[2]),.o_v(o_v),.o_r(o_r),
      .i_d({s5_nocmpl,s5_ok,s5_tag,s5_rcb_ctxt,s5_rcb_ec,s5_rcb_ea,s5_msinum,s5_rrq,s5_flgs,s5_lunid,s5_ioadllen,s5_data_len,s5_data_ctxt,s5_data_ea,s5_cdb,s5_portmsk,s5_rh,s5_rc,s5_erc,s5_lba,s5_timestamp,s5_hp}),
      .o_d({  o_nocmpl,o_ok,  o_tag,  o_rcb_ctxt,  o_rcb_ec,  o_rcb_ea,  o_msinum,  o_rrq,  o_flgs,  o_lunid,  o_ioadllen,  o_data_len,  o_data_ctxt,  o_data_ea,  o_cdb,  o_portmsk,  o_rh,  o_rc,  o_erc,  o_lba, o_rcb_timestamp, o_rcb_hp}));

   assign o_pipemon_v[0] = 1'b0;
   assign o_pipemon_v[1] = r1c_v[1];
   assign o_pipemon_v[2] = s0_addr_v;
   assign o_pipemon_v[3] = s1a_addr_v;
   assign o_pipemon_v[4] = s1a_addr_v;
   assign o_pipemon_v[5] = 1'b0;
   assign o_pipemon_v[6] = s1a_addr_v;
   assign o_pipemon_v[7] = s1_tag_v;
   assign o_pipemon_v[8] = s1_v[0];
   assign o_pipemon_v[9] = s1_v[1];
   assign o_pipemon_v[10] = s1_v[2];
   assign o_pipemon_v[11] = s2_v;
   assign o_pipemon_v[12] = s4_v[0];
   assign o_pipemon_v[13] = s4_v[1];
   assign o_pipemon_v[14] = s4_v;
   assign o_pipemon_v[15] = 1'b0;
   assign o_pipemon_v[16] = s5a_v;
   assign o_pipemon_v[17] = s5b_v[0];
   assign o_pipemon_v[18] = s5b_v[1];
   assign o_pipemon_v[19] = 1'b0;
   assign o_pipemon_v[20] = 1'b0;
   
   assign o_pipemon_v[21] = s5c_v[2];

   assign o_pipemon_r[0] = 1'b1;
   assign o_pipemon_r[1] = r1c_r[1];
   assign o_pipemon_r[2] = s0_addr_r;
   assign o_pipemon_r[3] = s1a_addr_r;
   assign o_pipemon_r[4] = s1a_addr_r;
   assign o_pipemon_r[5] = 1'b1;
   assign o_pipemon_r[6] = s1a_addr_r;
   assign o_pipemon_r[7] = s1_tag_r;
   assign o_pipemon_r[8] = s1_r[0];
   assign o_pipemon_r[9] = s1_r[1];
   assign o_pipemon_r[10] = s1_r[2];
   assign o_pipemon_r[11] = s2_r;
   assign o_pipemon_r[12] = s4_r[0];
   assign o_pipemon_r[13] = s4_r[1];
   assign o_pipemon_r[14] = s4b_r;
   assign o_pipemon_r[15] = 1'b1;
   assign o_pipemon_r[16] = s5a_r;
   assign o_pipemon_r[17] = s5b_r[0];
   assign o_pipemon_r[18] = s5b_r[1];
   assign o_pipemon_r[19] = 1'b1;
   assign o_pipemon_r[20] = 1'b1;
   assign o_pipemon_r[21] = s5c_r[2];


endmodule // ktms_afu_cmd

 










