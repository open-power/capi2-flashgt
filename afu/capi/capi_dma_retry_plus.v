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
module capi_dma_retry_plus#
  (
   parameter cred_width=0,
   parameter tstag_width=1,
   parameter ts_width=1,
   parameter tag_width=1, 
   parameter dat_width=1,
   parameter ctxtid_width=1,
   parameter tag_prefix_width=2,
   parameter sid_width=1,
   parameter rc_width=8,
   parameter [0:tag_prefix_width-1] rst_tag_prefix = 0,
   parameter [0:rc_width-1] rc_ok  = 0,
   parameter [0:rc_width-1] rc_sid  = 'h80,
   parameter [0:rc_width-1] rc_tsinv  = 'h81,
   parameter [0:rc_width-1] rc_paged_coming = 'h8a,
   parameter [0:rc_width-1] rc_ctxt = 'h0b,
   parameter [0:rc_width-1] rc_cred = 9, 
   parameter [0:rc_width-1] rc_flushed = 6,
   parameter [0:rc_width-1] rc_paged = 10
   )
   (input  clk,
    input 		      reset,

    // credit management
    input [0:7] 	      ha_croom,
    input 		      i_enable,
    output [0:cred_width-1]   o_credits,
 
    output 		      o_rm_err,
    output 		      i_req_r,
    input 		      i_req_v,
    input [0:tag_width-1]     i_req_tag,
    input [0:dat_width-1]     i_req_dat,
    input [0:ctxtid_width-1]  i_req_ctxt,
    input [0:tstag_width-1]   i_req_tstag,
    input 		      i_req_tstag_v,
    input 		      i_req_itst_inv, // ignore timestamp invalid and proceed with request
    input [0:sid_width-1]     i_req_sid,
    input 		      i_req_f,
 
    input 		      o_req_r,
    output 		      o_req_v,
    output [0:tag_width-1]    o_req_tag,
    output [0:4]              o_req_uid,
    output [0:dat_width-1]    o_req_dat,
    output [0:ctxtid_width-1] o_req_ctxt,

    input [0:dat_width-1]     i_restart_dat,
    input [0:ctxtid_width-1]  i_restart_ctxt, 
    input [0:tstag_width-1]   i_restart_tstag,

    input 		      i_rsp_v,
    input [0:rc_width-1]      i_rsp_d,
    input [0:tag_width-1]     i_rsp_tag,
    input [0:9]               i_rsp_itag,
    input 		      i_rsp_tag_outst,
    input [0:cred_width-1]    i_rsp_credits, // how many credits being returned

    output 		      o_rsp_v,
    output [0:tag_width-1]    o_rsp_tag,
    output [0:9]              o_rsp_itag,
    output [0:rc_width-1]     o_rsp_d,

    input 		      i_ctxt_add_v,
    input 		      i_ctxt_rmv_v,
    input 		      i_ctxt_trm_v,
    input [0:ctxtid_width-1]  i_ctxt_ctrl_id,  

    output 		      i_ctxt_rst_r,
    input 		      i_ctxt_rst_v,
    input [0:ctxtid_width-1]  i_ctxt_rst_id, 

    output 		      o_ctxt_rst_v,
    output [0:ctxtid_width-1] o_ctxt_rst_id,  

    output 		      o_ctxt_trm_v,
    output [0:ctxtid_width-1] o_ctxt_trm_id,  

    output 		      o_ctxt_add_v,

    input 		      i_cfg_ctrm_wait,

    input 		      i_tstag_issue_v,
    input [0:tstag_width-1]   i_tstag_issue_id,
    input [0:63] 	      i_tstag_issue_d,

    input 		      i_tstag_inv_v,
    input [0:tstag_width-1]   i_tstag_inv_id,

    output 		      i_tscheck_r,
    input 		      i_tscheck_v,
    input [0:tstag_width-1]   i_tscheck_tstag,
    input [0:ctxtid_width-1]  i_tscheck_ctxt,  
    
    input 		      o_tscheck_r,
    output 		      o_tscheck_v,
    output 		      o_tscheck_ok,

    output [9:10] 	      o_dbg_cnt_inc,
    output 		      o_pipemon_v,
    output 		      o_pipemon_r,
    output [0:5]              o_s1_perror,
    output [0:ctxtid_width+7]   o_dbg_dma_retry_s0,  
    output [0:1]              o_perror,   
    input                     i_dma_retry_msk_pe025,
    input                     i_dma_retry_msk_pe34
    );

   
   wire [0:ts_width-1] 	      cycle_count;
   localparam [0:ts_width-1] ts_one = 1;
   base_vlat#(.width(ts_width)) icycle_count_lat(.clk(clk),.reset(reset),.din(cycle_count+ts_one),.q(cycle_count));

   

   wire 		      s0_rsp_cred = (i_rsp_d == rc_cred); // credit manipulation only
   wire 		      s0_rsp_done = (i_rsp_d == rc_ok);
   wire 		      s0_rsp_flushed = (i_rsp_d == rc_flushed);
   wire 		      s0_rsp_for_restart = (i_rsp_tag[0:tag_prefix_width-1] == rst_tag_prefix);
   wire 		      s0_rsp_continue = (i_rsp_d == rc_paged);
		      

   wire 		      s0_rsp_v = i_rsp_v & ~s0_rsp_cred;
   
   wire [0:1] 		 s0a_rsp_v;
   base_acombine#(.ni(1),.no(2)) is0_cmb(.i_v(s0_rsp_v),.i_r(),.o_v(s0a_rsp_v),.o_r(2'b11));

   // send these responses to originator, but filter out restarts
   wire 		 s0c_rsp_v, s0c_rsp_r;
   base_afilter is0_fltra(.i_v(s0a_rsp_v[0]),.i_r(),.o_v(s0c_rsp_v),.o_r(1'b1),.en(~s0_rsp_for_restart));

   // lookup tag to get the tstag
   wire 		 s1_rsp_v;
   wire [0:rc_width-1] 	 s1_rsp_rc;
   wire [0:tag_width-1]  s1_rsp_tag;
   wire [0:9]            s1_rsp_itag;
   wire 		 s1_rsp_tstag_v;
   wire [0:tstag_width-1] s1_rsp_tstag;
   wire [0:sid_width-1]   s1_rsp_sid;
   wire 		  s1_rsp_flushed;
   
   
   base_alatch#(.width(rc_width+tag_width+1+10)) is1_rsp_lat(.clk(clk),.reset(reset),.i_v(s0c_rsp_v),.i_r(),.i_d({i_rsp_d,i_rsp_tag,i_rsp_itag,s0_rsp_flushed}),.o_v(s1_rsp_v),.o_r(1'b1),.o_d({s1_rsp_rc,s1_rsp_tag,s1_rsp_itag,s1_rsp_flushed}));
   base_mem#(.addr_width(tag_width),.width(1+tstag_width+sid_width)) is1_rsp_tmem
     (.clk(clk),
      .we(i_req_v),.wa(i_req_tag),.wd({(i_req_tstag_v & ~i_req_itst_inv),i_req_tstag,i_req_sid}),
      .re(1'b1),.ra(i_rsp_tag),.rd({s1_rsp_tstag_v,s1_rsp_tstag,s1_rsp_sid})
      );

   // don't mark the stream bad because of flushed transactions.    
   wire 		  s1_rsp_nok = (| s1_rsp_rc) & ~s1_rsp_flushed;

   wire 		 s2_rsp_v;
   wire 		 s2_rsp_r; // nosink
   
   wire [0:rc_width-1] 	 s2_rsp_rc;
   wire [0:tag_width-1]  s2_rsp_tag;
   wire [0:9]            s2_rsp_itag;
   wire 		 s2_rsp_tstag_v;
   wire [0:sid_width-1]  s2_rsp_sid;
   wire 		 s2_rsp_nok;
   
   base_alatch#(.width(rc_width+tag_width+10+2+sid_width)) is2_rsp_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_rsp_v),.i_r(),    .i_d({s1_rsp_rc,s1_rsp_tag,s1_rsp_itag,s1_rsp_tstag_v,s1_rsp_nok,s1_rsp_sid}),
      .o_v(s2_rsp_v),.o_r(1'b1),.o_d({s2_rsp_rc,s2_rsp_tag,s2_rsp_itag,s2_rsp_tstag_v,s2_rsp_nok,s2_rsp_sid}));
   wire 		 s2_rsp_tstag_vld;
   wire 		 s2_rsp_abrt = s2_rsp_tstag_v & ~s2_rsp_tstag_vld;
   wire [0:rc_width-1] 	 s2_rsp_qrc = s2_rsp_abrt ? rc_tsinv : s2_rsp_rc;

   // reset the validity of this sid
   wire 		 s2_rsp_sid_rst = s2_rsp_v & (s2_rsp_nok | s2_rsp_abrt);
   

   // if the response is not done, not credit manipulation, and it is not in response to a restart, hang on to it for retry or restart
   wire 		 s0b_rsp_v, s0b_rsp_r;
   base_afilter is0_fltrb(.i_v(s0a_rsp_v[1]),.i_r(),.o_v(s0b_rsp_v),.o_r(1'b1),.en(~s0_rsp_flushed & ~s0_rsp_done & ~s0_rsp_for_restart));

   wire 		 s1_rtry_v, s1_rtry_r;
   wire [0:tag_width-1]  s1_rtry_tag;

   wire 		 s1_rtry_cnt_zro;
   base_incdec#(.width(tag_width)) irst_cnt
     (.clk(clk),.reset(reset),
      .i_inc(s0b_rsp_v),
      .i_dec(s1_rtry_v & s1_rtry_r),
      .o_zero(s1_rtry_cnt_zro),.o_cnt()
      );
   assign s1_rtry_v = ~s1_rtry_cnt_zro;
   
   wire 		 s2_rtry_v, s2_rtry_r;
   base_alatch#(.width(1)) is2_rtry_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_rtry_v),.i_r(s1_rtry_r),.i_d(1'b0),
      .o_v(s2_rtry_v),.o_r(s2_rtry_r),.o_d()
      );
      
   localparam rst_tag_width = tag_width-tag_prefix_width;

   wire 		 s1a_rst_tag_v, s1a_rst_tag_r;
   wire [0:rst_tag_width-1]  s1a_rst_tag;
   
   // tag manager for restart
   capi_res_mgr#(.id_width(rst_tag_width)) ires_mgr
     (.clk(clk),.reset(reset),
      .i_free_v(s0_rsp_v & ~s0_rsp_cred & s0_rsp_for_restart),.i_free_id(i_rsp_tag[tag_prefix_width:tag_width-1]),
      .o_avail_v(s1a_rst_tag_v),.o_avail_r(s1a_rst_tag_r),.o_avail_id(s1a_rst_tag),.o_free_err(o_rm_err),.o_cnt(),.o_perror(o_perror[1]) 
      );

   // use the tag from the tag manager iff this is a restart

   wire [0:tag_width-1]  s2b_rtry_tag = {rst_tag_prefix,s1a_rst_tag};
   wire 		 s2b_rtry_v, s2b_rtry_r;
   base_acombine#(.ni(2),.no(1)) is2_rtry_cmb(.i_v({s1a_rst_tag_v,s2_rtry_v}),.i_r({s1a_rst_tag_r,s2_rtry_r}),.o_v(s2b_rtry_v),.o_r(s2b_rtry_r));
   
   wire 		 s3_rtry_r, s3_rtry_v;
   wire [0:tag_width-1]  s3_rtry_tag;

   base_alatch#(.width(tag_width)) is3_lat
     (.clk(clk),.reset(reset),
      .i_v(s2b_rtry_v),.i_r(s2b_rtry_r),.i_d(s2b_rtry_tag),
      .o_v(s3_rtry_v),.o_r(s3_rtry_r),.o_d(s3_rtry_tag)
      );


   wire [0:sid_width+1+1+1+tstag_width+ctxtid_width+dat_width-1] s3_rtry_dat = {{sid_width{1'b0}},1'b0,1'b0,1'b0,i_restart_tstag,i_restart_ctxt,i_restart_dat};

   wire 					  s2_req_v, s2_req_r;
   wire [0:tag_width-1] 			  s2_req_tag;
   wire [0:sid_width-1] 			  s2_req_sid;
   wire 					  s2_req_f;
   wire [0:tstag_width-1] 			  s2_req_tstag;
   wire 					  s2_req_tstag_v;
   wire 					  s2_req_itst_inv;
   
   wire [0:ctxtid_width-1] 			  s2_req_ctxt;
   wire [0:dat_width-1] 			  s2_req_dat;
   wire 					  s2_req_is_restart;
   
   base_primux#(.ways(2),.width(1+tag_width+sid_width+1+1+1+tstag_width+ctxtid_width+dat_width)) is2_mux
     (.i_v({s3_rtry_v,i_req_v}),
      .i_r({s3_rtry_r,i_req_r}),
      .i_d({1'b1, s3_rtry_tag, s3_rtry_dat, 
	    1'b0,   i_req_tag,  i_req_sid,  i_req_f,  i_req_itst_inv,  i_req_tstag_v,  i_req_tstag,  i_req_ctxt,  i_req_dat}),
      .o_d({s2_req_is_restart, s2_req_tag, s2_req_sid, s2_req_f, s2_req_itst_inv, s2_req_tstag_v, s2_req_tstag, s2_req_ctxt, s2_req_dat}),
      .o_v(s2_req_v),.o_r(s2_req_r),.o_sel()
      );

   wire 		   s3_req_is_restart;
   wire [0:tag_width-1]    s3_req_tag;
   wire [0:sid_width-1]    s3_req_sid;
   wire 		   s3_req_f;
   wire 		   s3_req_tstag_v;
      wire 		   s3_req_itst_inv;
   
   wire [0:tstag_width-1]  s3_req_tstag;
   wire [0:ctxtid_width-1] s3_req_ctxt;
   wire [0:dat_width-1]    s3_req_dat;

   wire 		   s3a_req_v;
   wire 		   s3a_req_r;

   base_aburp_latch#(.width(1+tag_width+sid_width+1+1+1+tstag_width+ctxtid_width+dat_width)) is3_req_lat
     (.clk(clk),.reset(reset),
      .i_v(s2_req_v), .i_r(s2_req_r), .i_d({s2_req_is_restart,s2_req_tag,s2_req_sid,s2_req_f,s2_req_itst_inv,s2_req_tstag_v, s2_req_tstag, s2_req_ctxt,s2_req_dat}),
      .o_v(s3a_req_v),.o_r(s3a_req_r),.o_d({s3_req_is_restart,s3_req_tag,s3_req_sid,s3_req_f,s3_req_itst_inv,s3_req_tstag_v, s3_req_tstag, s3_req_ctxt,s3_req_dat})
      );


   wire 		   s8_cred_inc;
   wire 		   s3_cred_en;
   
   // check and obtain a credit   
   capi_cmd_credit#(.cred_width(cred_width),.ld_delay(10)) idma_cred
     (.clk(clk),.reset(reset),.i_init_cred({1'b0,ha_croom}),
      .i_cred_add_v(i_rsp_v),.i_cred_add_d(i_rsp_credits),
      .i_cred_inc_v(s8_cred_inc),
      .o_en(s3_cred_en),
      .i_cred_dec_v(s3a_req_v & s3a_req_r),
      .o_credits(o_credits)
      );

   wire 		   s3_restart_pending;
   base_vlat_sr irs_pending_lat(.clk(clk),.reset(reset),.set(s3a_req_v & s3a_req_r & s3_req_is_restart),.rst(s0_rsp_v & s0_rsp_for_restart),.q(s3_restart_pending));

   // hang on to context control request and put it through the request pipe.
   // it has to not overtake the request ahead of it so we don't send invalid requests after we

   // if so configured, stop all traffic until context termination is done.
   wire 		   s2_ctxt_trm_pending;

   // for timing, need to go straight into latch after this gate
   wire 		   s3b_req_v, s3b_req_r;
   base_agate is3_gt(.i_v(s3a_req_v),.i_r(s3a_req_r),.o_v(s3b_req_v),.o_r(s3b_req_r),.en(~s3_restart_pending & ~s2_ctxt_trm_pending & s3_cred_en & i_enable));
   
   wire 		   s4_req_is_restart;
   wire [0:tag_width-1]    s4_req_tag;
   wire [0:sid_width-1]    s4_req_sid;
   wire 		   s4_req_f;
   wire 		   s4_req_itst_inv;
   wire 		   s4_req_tstag_v;
   wire [0:dat_width-1]    s4_req_dat;
   
   wire [0:tstag_width-1]  s4a_req_tstag;
   wire [0:ctxtid_width-1] s4a_req_ctxt;

   wire 		   s4a_req_v;
   wire 		   s4a_req_r;

   base_alatch#(.width(1+tag_width+sid_width+1+1+1+tstag_width+ctxtid_width+dat_width)) is4_req_lat
     (.clk(clk),.reset(reset),
      .i_v(s3b_req_v),.i_r(s3b_req_r),.i_d({s3_req_is_restart,s3_req_tag,s3_req_sid,s3_req_f,s3_req_itst_inv,s3_req_tstag_v, s3_req_tstag, s3_req_ctxt,s3_req_dat}),
      .o_v(s4a_req_v),.o_r(s4a_req_r),.o_d({s4_req_is_restart,s4_req_tag,s4_req_sid,s4_req_f,s4_req_itst_inv,s4_req_tstag_v, s4a_req_tstag, s4a_req_ctxt,s4_req_dat})
      );

   // context control - add, terminate, and reset
   wire [0:1] 		   s0_ctxt_ctrl_dummy_r;
   wire [0:1] 		   s0_ctxt_ctrl_sel;
   wire 		   s0_ctxt_ctrl_r, s0_ctxt_ctrl_v;
   wire [0:ctxtid_width-1] s0_ctxt_ctrl_id;

   
   base_primux#(.ways(2),.width(ctxtid_width)) is0_ctxt_mux
     (.i_v({i_ctxt_add_v, i_ctxt_trm_v}),.i_r({s0_ctxt_ctrl_dummy_r}),.i_d({i_ctxt_ctrl_id,i_ctxt_ctrl_id}),
      .o_v(s0_ctxt_ctrl_v),.o_r(s0_ctxt_ctrl_r),.o_d(s0_ctxt_ctrl_id),.o_sel(s0_ctxt_ctrl_sel));
   
   wire [0:1] 		   s1_ctxt_ctrl_dummy_r;
   wire [0:1] 		   s1_ctxt_ctrl_sel;
   wire 		   s1_ctxt_ctrl_r, s1_ctxt_ctrl_v;
   wire [0:ctxtid_width-1] s1_ctxt_ctrl_id;
   base_alatch#(.width(2+ctxtid_width)) is1_ctxt_ctrl_lat
     (.clk(clk),.reset(reset),
      .i_v(s0_ctxt_ctrl_v),.i_r(s0_ctxt_ctrl_r),.i_d({s0_ctxt_ctrl_sel,s0_ctxt_ctrl_id}),
      .o_v(s1_ctxt_ctrl_v),.o_r(s1_ctxt_ctrl_r),.o_d({s1_ctxt_ctrl_sel,s1_ctxt_ctrl_id})      
      );

   wire 		   s1a_ctxt_ctrl_v, s1a_ctxt_ctrl_r;
   wire [0:ctxtid_width-1] s1a_ctxt_ctrl_id;
   wire [0:2] 		   s1a_ctxt_ctrl_sel;
   base_primux#(.ways(2),.width(ctxtid_width+3)) is1_ctxt_mux
     (.i_v({s1_ctxt_ctrl_v, i_ctxt_rst_v}),.i_r({s1_ctxt_ctrl_r,i_ctxt_rst_r}),.i_d({s1_ctxt_ctrl_sel,1'b0,s1_ctxt_ctrl_id, 3'b001,i_ctxt_rst_id}),
      .o_v(s1a_ctxt_ctrl_v),.o_r(s1a_ctxt_ctrl_r),.o_d({s1a_ctxt_ctrl_sel,s1a_ctxt_ctrl_id}),.o_sel());

   wire [0:1] 		   s2_ctxt_ctrl_dummy_r;
   wire [0:2] 		   s2_ctxt_ctrl_sel;
   wire 		   s2_ctxt_ctrl_r, s2_ctxt_ctrl_v;
   wire [0:ctxtid_width-1] s2_ctxt_ctrl_id;
   base_alatch#(.width(3+ctxtid_width)) is2_ctxt_ctrl_lat
     (.clk(clk),.reset(reset),
      .i_v(s1a_ctxt_ctrl_v),.i_r(s1a_ctxt_ctrl_r),.i_d({s1a_ctxt_ctrl_sel,s1a_ctxt_ctrl_id}),
      .o_v(s2_ctxt_ctrl_v),.o_r(s2_ctxt_ctrl_r),.o_d({s2_ctxt_ctrl_sel,s2_ctxt_ctrl_id})      
      );

   assign s2_ctxt_trm_pending = 1'b0;
   
   
   wire [0:tstag_width-1]  s4_req_tstag;
   wire [0:ctxtid_width-1] s4_req_ctxt;
   wire [0:2] 		   s4_sel;
   wire 		   s4_req_v, s4_req_r;
   base_primux#(.width(tstag_width+ctxtid_width),.ways(3)) is4_mux
     (.i_v({s2_ctxt_ctrl_v,i_tscheck_v,s4a_req_v}),
      .i_r({s2_ctxt_ctrl_r,i_tscheck_r,s4a_req_r}),
      .i_d({{{tstag_width-3{1'b0}}, s2_ctxt_ctrl_sel}, s2_ctxt_ctrl_id, i_tscheck_tstag,i_tscheck_ctxt, s4a_req_tstag, s4a_req_ctxt}),
      .o_v(s4_req_v),.o_r(s4_req_r),.o_d({s4_req_tstag,s4_req_ctxt}),
      .o_sel(s4_sel));
   wire 		   s4_xreq = s4_sel[1];  // this is an external request
   wire 		   s4_ctrl = s4_sel[0];  // this is context termination
   wire 		   s4_dma  = s4_sel[2];


   
   wire 		   s5_req_v, s5_req_r;
   wire 		   s5_req_is_restart;
   wire [0:tag_width-1]    s5_req_tag;
   wire [0:sid_width-1]    s5_req_sid;
   wire 		   s5_req_itst_inv;
   wire 		   s5_req_tstag_v;
   wire [0:tstag_width-1]  s5_req_tstag;
   wire [0:ctxtid_width-1] s5_req_ctxt;
   wire [0:dat_width-1]    s5_req_dat;
   wire 		   s5_xreq;
   wire 		   s5_ctrl;
   wire 		   s5_req_f;
   wire 		   s5_dma;
   
   

   base_alatch#(.width(1+tag_width+sid_width+1+1+1+tstag_width+ctxtid_width+dat_width+3)) is5_req_lat
     (.clk(clk),.reset(reset),
      .i_v(s4_req_v),.i_r(s4_req_r),.i_d({s4_req_is_restart,s4_req_tag,s4_req_sid,s4_req_f,s4_req_itst_inv,s4_req_tstag_v, s4_req_tstag,s4_req_ctxt,s4_req_dat,s4_xreq,s4_ctrl,s4_dma}),
      .o_v(s5_req_v),.o_r(s5_req_r),.o_d({s5_req_is_restart,s5_req_tag,s5_req_sid,s5_req_f,s5_req_itst_inv,s5_req_tstag_v, s5_req_tstag,s5_req_ctxt,s5_req_dat,s5_xreq,s5_ctrl,s5_dma})
      );

   
   wire 		   s6_req_v, s6_req_r;
   wire 		   s6_req_is_restart;
   wire [0:tag_width-1]    s6_req_tag;
   wire [0:sid_width-1]    s6_req_sid;
   wire 		   s6_req_itst_inv;
   wire 		   s6_req_tstag_v;
   wire [0:tstag_width-1]  s6_req_tstag;
   wire 		   s6_req_tstag_inv;
   wire [0:ctxtid_width-1] s6_req_ctxt;
   wire [0:dat_width-1]    s6_req_dat;
   wire [0:ts_width-1] 	   s6_req_tag_ts;
   wire [0:ts_width-1] 	   s6_req_ctxt_ts;
   wire 		   s6_xreq;
   wire 		   s6_ctrl;

      
   wire 		   s5_req_re;
   base_alatch_oe#(.width(1+tag_width+sid_width+1+1+tstag_width+ctxtid_width+dat_width+2)) is6_req_lat
     (.clk(clk),.reset(reset),
      .i_v(s5_req_v),.i_r(s5_req_r),.i_d({s5_req_is_restart,s5_req_tag,s5_req_sid,s5_req_itst_inv,s5_req_tstag_v, s5_req_tstag,s5_req_ctxt,s5_req_dat,s5_xreq,s5_ctrl}),
      .o_v(s6_req_v),.o_r(s6_req_r),.o_d({s6_req_is_restart,s6_req_tag,s6_req_sid,s6_req_itst_inv,s6_req_tstag_v, s6_req_tstag,s6_req_ctxt,s6_req_dat,s6_xreq,s6_ctrl}),
      .o_en(s5_req_re)
      );

   base_mem#(.width(ts_width),.addr_width(tstag_width)) itag_ts_mem
     (.clk(clk),
      .re(s5_req_re),.ra(s5_req_tstag),.rd(s6_req_tag_ts),
      .we(i_tstag_issue_v),.wa(i_tstag_issue_id),.wd(i_tstag_issue_d));


   
   wire 		   s6_req_tstag_vld;
   base_vmem#(.a_width(tstag_width),.rports(2)) itag_ts_vmem
     (.clk(clk),.reset(reset),
      .i_rd_en({s5_req_re,1'b1}),.i_rd_a({s5_req_tstag,s1_rsp_tstag}),.o_rd_d({s6_req_tstag_vld,s2_rsp_tstag_vld}),
      .i_set_v(i_tstag_issue_v),.i_set_a(i_tstag_issue_id),
      .i_rst_v(i_tstag_inv_v),.i_rst_a(i_tstag_inv_id)
      );
   
   wire 		   s6_req_abrt = s6_req_tstag_v  & (~(s6_req_tstag_vld | s6_req_itst_inv));
   

   wire [0:5]              s1_perror;
   wire [0:5] 				hld_perror;
   wire [0:5]              hld_perror_msk = hld_perror & {~i_dma_retry_msk_pe025,1'b1,~i_dma_retry_msk_pe025,~i_dma_retry_msk_pe34,~i_dma_retry_msk_pe34,~i_dma_retry_msk_pe025};
   wire [0:ctxtid_width+1]     dbg_dma_retry_s0;
   base_vlat_sr#(.width(6)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(6'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror_msk),.q(o_perror[0]));
   base_delay#(.n(2),.width(ctxtid_width+2)) s1_pe0_del_del(.clk(clk),.reset(reset),.i_d({s5_req_r,s5_req_v,s5_req_ctxt}),.o_d(dbg_dma_retry_s0));
   base_vlat_sr#(.width(6)) idbg_s0_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(6'd0),.q(hld_perror));
   capi_parcheck#(.width(ctxtid_width-1)) s5_req_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s5_req_v),.i_d(s5_req_ctxt[0:ctxtid_width-2]),.i_p(s5_req_ctxt[ctxtid_width-1]),.o_error(s1_perror[0]));
   wire [0:ctxtid_width+7]  gated_s0_in = {dbg_dma_retry_s0,s1_perror} & {ctxtid_width+7{(s1_perror[0] & ~hld_perror[0])}};   
   wire [0:ctxtid_width+7] dbg_s0_hld_in = gated_s0_in | o_dbg_dma_retry_s0;
   base_vlat#(.width(ctxtid_width+8)) idbg_s0_hold(.clk(clk),.reset(reset),.din(dbg_s0_hld_in),.q(o_dbg_dma_retry_s0));
   capi_parcheck#(.width(ctxtid_width-1)) s1_ctxt_ctrl_id_pcheck(.clk(clk),.reset(reset),.i_v(s1_ctxt_ctrl_v),.i_d(s1_ctxt_ctrl_id[0:ctxtid_width-2]),.i_p(s1_ctxt_ctrl_id[ctxtid_width-1]),.o_error(s1_perror[1]));

   assign                  o_s1_perror = hld_perror;
	   
   // update timestamp on context control action
   base_mem#(.width(ts_width),.addr_width(ctxtid_width-1)) ictx_ts_mem
     (.clk(clk),
      .re(s5_req_re),.ra(s5_req_ctxt[0:ctxtid_width-2]),.rd(s6_req_ctxt_ts),
      .we(s1_ctxt_ctrl_v),.wa(s1_ctxt_ctrl_id[0:ctxtid_width-2]),.wd(cycle_count));
   
   
   wire 		   s7_req_v, s7_req_r;
   wire 		   s7_req_is_restart;
   wire [0:tag_width-1]    s7_req_tag;
   wire [0:tstag_width-1]  s7_req_tstag;
   wire 		   s7_req_tstag_v;
   wire [0:ctxtid_width-1] s7_req_ctxt;
   wire [0:dat_width-1]    s7_req_dat;
   wire [0:ts_width-1] 	   s7_req_tag_ts;
   wire [0:ts_width-1] 	   s7_req_ctxt_ts;
   wire 		   s7_req_abrt;
   wire 		   s7_xreq;
   wire 		   s7_ctrl;
   wire 		   s6_req_re;
   wire [0:4]              s6_req_uid = s6_req_sid[0:4];
   wire [0:4]              s7_req_uid;
   base_alatch_oe#(.width(1+tag_width+1+1+tstag_width+ctxtid_width+dat_width+2*ts_width+2+5)) is7_req_lat
     (.clk(clk),.reset(reset),
      .i_v(s6_req_v),.i_r(s6_req_r),.i_d({s6_req_is_restart,s6_req_tag,s6_req_abrt,s6_req_tstag_v, s6_req_tstag,s6_req_ctxt,s6_req_dat,s6_req_ctxt_ts,s6_req_tag_ts,s6_xreq,s6_ctrl,s6_req_uid}),
      .o_v(s7_req_v),.o_r(s7_req_r),.o_d({s7_req_is_restart,s7_req_tag,s7_req_abrt,s7_req_tstag_v, s7_req_tstag,s7_req_ctxt,s7_req_dat,s7_req_ctxt_ts,s7_req_tag_ts,s7_xreq,s7_ctrl,s7_req_uid}),
      .o_en(s6_req_re)
      );

   capi_parcheck#(.width(ctxtid_width-1)) s6_req_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s6_req_v),.i_d(s6_req_ctxt[0:ctxtid_width-2]),.i_p(s6_req_ctxt[ctxtid_width-1]),.o_error(s1_perror[2]));
   wire 		   s7_req_ctxt_vld;
   base_vmem#(.a_width(ctxtid_width-1),.rports(1)) ictxt_vmem
     (.clk(clk),.reset(reset),
      .i_set_v(s1_ctxt_ctrl_v & s1_ctxt_ctrl_sel[0]),.i_set_a(s1_ctxt_ctrl_id[0:ctxtid_width-2]),  // set on add
      .i_rst_v(s1_ctxt_ctrl_v & s1_ctxt_ctrl_sel[1]),.i_rst_a(s1_ctxt_ctrl_id[0:ctxtid_width-2]),  // reset on terminate
      .i_rd_en(s6_req_re),.i_rd_a(s6_req_ctxt[0:ctxtid_width-2]),.o_rd_d(s7_req_ctxt_vld)
      );
   wire 		   s7_req_sid_vld;
   base_vmem#(.a_width(sid_width)) isid_vmem
     (.clk(clk),.reset(reset),
      .i_set_v(s5_dma & s5_req_v & s5_req_r & s5_req_f),.i_set_a(s5_req_sid),
      .i_rst_v(s2_rsp_sid_rst),.i_rst_a(s2_rsp_sid),
      .i_rd_en(s6_req_re),.i_rd_a(s6_req_sid),.o_rd_d(s7_req_sid_vld)
      );
 	      
   // abort this transaction if (the context is invalid or too new) and it is not a restart (restarts don't have a context)
   wire 		   s7_req_tag_old = (s7_req_tag_ts < s7_req_ctxt_ts);
   wire [0:2] 		   s7_req_ctrl_sel = s7_req_tstag[tstag_width-3:tstag_width-1];
   
   wire 		   s8_req_v, s8_req_r;
   wire [0:tag_width-1]    s8_req_tag;
   wire [0:ctxtid_width-1] s8_req_ctxt;
   wire [0:dat_width-1]    s8_req_dat;
   wire 		   s8_xreq;
   wire 		   s8_ctrl;
   wire 		   s8_req_abrt;
   wire 		   s8_req_tag_old;
   wire 		   s8_req_tstag_v;
   wire 		   s8_req_ctxt_vld;
      wire 		   s8_req_sid_vld;
   wire 		   s8_req_is_restart;
   wire [0:2] 		   s8_req_ctrl_sel;
   wire [0:4]              s8_req_uid;
   
   base_alatch_burp#(.width(tag_width+ctxtid_width+dat_width+3+8+5)) is8_req_lat
     (.clk(clk),.reset(reset),
      .i_v(s7_req_v),.i_r(s7_req_r),.i_d({s7_req_tag,s7_req_ctxt,s7_req_dat, s7_req_ctrl_sel,s7_xreq,s7_ctrl,s7_req_abrt,s7_req_tag_old,s7_req_tstag_v,s7_req_ctxt_vld,s7_req_sid_vld,s7_req_is_restart,s7_req_uid}),
      .o_v(s8_req_v),.o_r(s8_req_r),.o_d({s8_req_tag,s8_req_ctxt,s8_req_dat, s8_req_ctrl_sel,s8_xreq,s8_ctrl,s8_req_abrt,s8_req_tag_old,s8_req_tstag_v,s8_req_ctxt_vld,s8_req_sid_vld,s8_req_is_restart,s8_req_uid})
      );

   wire 		   s8_req_abort = ((s8_req_tag_old & s8_req_tstag_v) | ~s8_req_ctxt_vld | ~s8_req_sid_vld) & ~s8_req_is_restart | s8_req_abrt;
      
   wire [0:rc_width-1] 	   s8_req_abrt_rc = s8_req_abrt ? rc_tsinv : (~s8_req_sid_vld ? rc_sid : rc_ctxt); 
   wire [0:3] 		   s8_req_dmux_sel;
   assign s8_req_dmux_sel[0] = s8_xreq; // this is just a request for timestamp read
   assign s8_req_dmux_sel[1] = s8_ctrl;
   assign s8_req_dmux_sel[2] = ~s8_ctrl & ~s8_xreq &  s8_req_abort;
   assign s8_req_dmux_sel[3] = ~s8_ctrl & ~s8_xreq & ~s8_req_abort;

   wire 		   s8a_req_v, s8a_req_r; // aborted request - send response
   wire 		   s8b_req_v, s8b_req_r; // not aborted - do request
   wire 		   s8_ctxt_ctrl_v, s8_ctxt_ctrl_r;
   
   base_ademux#(.ways(4)) is8_req_dmux(.i_v(s8_req_v),.i_r(s8_req_r),.o_v({o_tscheck_v, s8_ctxt_ctrl_v, s8a_req_v,s8b_req_v}),.o_r({o_tscheck_r, s8_ctxt_ctrl_r, s8a_req_r,s8b_req_r}),.sel(s8_req_dmux_sel));

   // allow context termination to proceed if we are not configured to stop it (hence penindg = 0) or the transaction count has reached 0
   wire 		   s8_ctxt_ctrl_gt_en = 1'b1;
   wire 		   s8b_ctxt_ctrl_v, s8b_ctxt_ctrl_r;
   
   base_agate is8_ctxt_trm_gt(.i_v(s8_ctxt_ctrl_v),.i_r(s8_ctxt_ctrl_r),.o_v(s8b_ctxt_ctrl_v),.o_r(s8b_ctxt_ctrl_r),.en(s8_ctxt_ctrl_gt_en));

   
   
   // don't allow more requests after a restart until the restart has completed
      
   assign o_tscheck_ok = ~s8_req_tag_old;
   assign o_req_tag = s8_req_tag;
   assign o_req_uid = s8_req_uid;
   assign o_req_dat = s8_req_dat;
   assign o_req_ctxt = s8_req_ctxt;

   wire [0:1] 		   s8c_req_v, s8c_req_r;
   base_acombine#(.ni(1),.no(2)) is8_cmb(.i_v(s8b_req_v),.i_r(s8b_req_r),.o_v(s8c_req_v),.o_r(s8c_req_r));

   // filter out restarts for the purpuse of incrementing outstanding transaction count for the context
   // because restarts don't have a context
   wire 		   s8d_req_v, s8d_req_r;
   base_afilter is8d_fltr(.i_v(s8c_req_v[1]),.i_r(s8c_req_r[1]),.o_v(s8d_req_v),.o_r(s8d_req_r),.en(~s8_req_is_restart));
   
   assign o_req_v = s8c_req_v[0];
   assign s8c_req_r[0] = o_req_r;

   wire 		     s2a_rsp_v, s2a_rsp_r;
   wire [0:tag_width-1]      s2a_rsp_tag;
   wire [0:9]                s2a_rsp_itag;
   wire [0:rc_width-1] 	     s2a_rsp_d;

   // give back the credit if we are going to abort
   assign s8_cred_inc = s8a_req_v & s8a_req_r;
   
   // choose between inbound response (which we cannot stall) and response due to invalid context or failed sid  
   base_primux#(.ways(2),.width(tag_width+10+rc_width)) irsp_mux(.i_v({s2_rsp_v,s8a_req_v}),.i_r({s2_rsp_r,s8a_req_r}),.i_d({s2_rsp_tag,s2_rsp_itag,s2_rsp_qrc,s8_req_tag,10'b0000000001,s8_req_abrt_rc}),.o_v(s2a_rsp_v),.o_r(1'b1),.o_d({s2a_rsp_tag,s2a_rsp_itag,s2a_rsp_d}),.o_sel());
   
   // latch for timing
   base_vlat#(.width(1+tag_width+10+rc_width)) is3_rsp_lat(.clk(clk),.reset(reset),.din({s2a_rsp_v,s2a_rsp_tag,s2a_rsp_itag,s2a_rsp_d}),.q({o_rsp_v,o_rsp_tag,o_rsp_itag,o_rsp_d}));


   wire [0:ctxtid_width-1]   t1_rsp_ctxt;
   // track number of outstanding transactions on a per-context basis
   // to do this, we must remember which context each tag came form.
   base_mem#(.addr_width(tag_width),.width(ctxtid_width)) ictxtid_mem
     (.clk(clk),
      .we(o_req_v),.wa(o_req_tag),.wd(o_req_ctxt),
      .re(1'b1),.ra(i_rsp_tag),.rd(t1_rsp_ctxt));

   wire 		     t0_rsp_v = s0_rsp_v & ~s0_rsp_for_restart & ~s0_rsp_cred;
   wire 		     t1_rsp_v;
   base_vlat it1_vlat(.clk(clk),.reset(reset),.din(t0_rsp_v),.q(t1_rsp_v));


   // add 3 cycles of delay b/c capi_dma_ctxt_cnt has 3 cycles of delay from inc/dec to result being visible.
   // so, once the last transaction for the terminating context goes through the pipe, we must wait three cycles before checking the count
   wire [0:ctxtid_width-1] s9_ctxt_ctrl_id;
   wire [0:2] 		   s9_ctxt_ctrl_sel;
   wire 		   s9_ctxt_ctrl_v, s9_ctxt_ctrl_r;
   base_alatch#(.width(ctxtid_width+3)) is9_ctxt_ctrl_lat
     (.clk(clk),.reset(reset),.i_v(s8b_ctxt_ctrl_v),.i_r(s8b_ctxt_ctrl_r),.i_d({s8_req_ctxt,s8_req_ctrl_sel}),.o_v(s9_ctxt_ctrl_v),.o_r(s9_ctxt_ctrl_r),.o_d({s9_ctxt_ctrl_id,s9_ctxt_ctrl_sel}));
   wire [0:ctxtid_width-1] s10_ctxt_ctrl_id;
   wire [0:2] 		   s10_ctxt_ctrl_sel;
      wire 		   s10_ctxt_ctrl_v, s10_ctxt_ctrl_r;
   base_alatch#(.width(ctxtid_width+3)) is10_ctxt_ctrl_lat
     (.clk(clk),.reset(reset),.i_v(s9_ctxt_ctrl_v),.i_r(s9_ctxt_ctrl_r),.i_d({s9_ctxt_ctrl_id,s9_ctxt_ctrl_sel}),.o_v(s10_ctxt_ctrl_v),.o_r(s10_ctxt_ctrl_r),.o_d({s10_ctxt_ctrl_id,s10_ctxt_ctrl_sel}));
   wire [0:ctxtid_width-1] s11_ctxt_ctrl_id;
   wire [0:2] 		   s11_ctxt_ctrl_sel;
      wire 		   s11_ctxt_ctrl_v, s11_ctxt_ctrl_r;
   base_alatch#(.width(ctxtid_width+3)) is11_ctxt_ctrl_lat
     (.clk(clk),.reset(reset),.i_v(s10_ctxt_ctrl_v),.i_r(s10_ctxt_ctrl_r),.i_d({s10_ctxt_ctrl_id,s10_ctxt_ctrl_sel}),.o_v(s11_ctxt_ctrl_v),.o_r(s11_ctxt_ctrl_r),.o_d({s11_ctxt_ctrl_id,s11_ctxt_ctrl_sel}));
   // wait to ack a context term until it has 0 outstanding transactions
   wire [0:ctxtid_width-1]   s12_ctxt_ctrl_id;
   wire [0:2] 		     s12_ctxt_ctrl_sel;
   wire 		     s12_ctxt_ctrl_v, s12_ctxt_ctrl_r;
   base_amem_rd_fltr#(.awidth(ctxtid_width),.dwidth(3)) is8_rd_fltr
     (.clk(clk),.reset(reset),
      .i_v(s11_ctxt_ctrl_v),.i_r(s11_ctxt_ctrl_r),.i_a(s11_ctxt_ctrl_id),.i_d(s11_ctxt_ctrl_sel),
      .o_v(s12_ctxt_ctrl_v),.o_r(s12_ctxt_ctrl_r),.o_a(s12_ctxt_ctrl_id),.o_d(s12_ctxt_ctrl_sel)
      );

//  check aprity for t1_rsp_ctxt, s8_req_ctxt, s12_ctxt_ctrl_id 
   capi_parcheck#(.width(ctxtid_width-1)) t1_rsp_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(t1_rsp_v),.i_d(t1_rsp_ctxt[0:ctxtid_width-2]),.i_p(t1_rsp_ctxt[ctxtid_width-1]),.o_error(s1_perror[3]));
   capi_parcheck#(.width(ctxtid_width-1)) s8_req_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s8d_req_v),.i_d(s8_req_ctxt[0:ctxtid_width-2]),.i_p(s8_req_ctxt[ctxtid_width-1]),.o_error(s1_perror[4]));
   capi_parcheck#(.width(ctxtid_width-1)) s12_ctxt_ctrl_id_pcheck(.clk(clk),.reset(reset),.i_v(s12_ctxt_ctrl_v),.i_d(s12_ctxt_ctrl_id[0:ctxtid_width-2]),.i_p(s12_ctxt_ctrl_id[ctxtid_width-1]),.o_error(s1_perror[5]));
   // increment will not take effect for three cycles
   wire 		     s12_ctxt_ctrl_zero;
   capi_dma_ctxt_cnt#(.id_width(ctxtid_width-1),.cnt_width(cred_width+1)) ictxt_cnt
     (.clk(clk),.reset(reset),
      .i_dec_v(t1_rsp_v),.i_dec_id(t1_rsp_ctxt[0:ctxtid_width-2]),
      .i_inc_v(s8d_req_v),.i_inc_r(s8d_req_r),.i_inc_id(s8_req_ctxt[0:ctxtid_width-2]),
      .i_rd_id(s12_ctxt_ctrl_id[0:ctxtid_width-2]),.o_rd_zero(s12_ctxt_ctrl_zero)
      );

   wire 		     s12b_ctxt_ctrl_v;
   wire 		     s12b_ctxt_ctrl_r;

   assign o_pipemon_r = s12_ctxt_ctrl_r;
   assign o_pipemon_v = s12_ctxt_ctrl_v;
   
   base_agate is12_cc_gt(.i_v(s12_ctxt_ctrl_v),.i_r(s12_ctxt_ctrl_r),.o_v(s12b_ctxt_ctrl_v),.o_r(s12b_ctxt_ctrl_r),.en(s12_ctxt_ctrl_zero));

   wire [0:2] 		     s12c_ctxt_ctrl_v, s12c_ctxt_ctrl_r;
   base_ademux#(.ways(3)) is12ctxttrm_demux(.i_v(s12b_ctxt_ctrl_v),.i_r(s12b_ctxt_ctrl_r),.o_v(s12c_ctxt_ctrl_v),.o_r(s12c_ctxt_ctrl_r),.sel(s12_ctxt_ctrl_sel));

   assign o_ctxt_add_v = s12c_ctxt_ctrl_v[0];
   
   assign o_ctxt_trm_v = s12c_ctxt_ctrl_v[1];
   assign o_ctxt_trm_id =  s12_ctxt_ctrl_id;
   
   assign o_ctxt_rst_v = s12c_ctxt_ctrl_v[2];
   assign o_ctxt_rst_id = s12_ctxt_ctrl_id;
   assign s12c_ctxt_ctrl_r[0:2] = 3'b111;


   assign o_dbg_cnt_inc[9] = s8a_req_v & s8a_req_r;
   assign o_dbg_cnt_inc[10] = s8b_req_v & s8b_req_r;

endmodule // capi_dma_retry

      
								    
								    

   
