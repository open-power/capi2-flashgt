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

module ktms_afu_timeout#
  (parameter tag_width=1,
   parameter rc_width=8,
   parameter ctxtid_width=1,
   parameter channels=4,
   parameter rslt_width=1,
   parameter aux_width=1
  )
   (input clk,
    input 			   reset,
    input [0:63] 		   i_timestamp,
    output 			   i_cmd_r,
    input 			   i_cmd_v,
    input [0:tag_width-1] 	   i_cmd_tag, 
    input [0:1] 		   i_cmd_flg,
    input [0:15] 		   i_cmd_d,
    input [0:63] 		   i_cmd_ts,
    input                          i_cmd_sync,
    input                          i_cmd_ok,

    // this tag retried by ch_alloc don't time it anymore
    input                          i_reset_afu_cmd_tag_v,
    input                          i_reset_afu_cmd_tag_r,
    input [0:9]                    i_reset_afu_cmd_tag,
 

    // this tag has been completed - don't time it out any more.
    output                         i_cmpl_r,
    input 			   i_cmpl_v,
    input [0:tag_width-1] 	   i_cmpl_tag,
    input [0:rslt_width-1] 	   i_cmpl_rslt,
    input [0:aux_width-1] 	   i_cmpl_aux,

    input 			   o_cmpl_r,
    output 			   o_cmpl_v,
    output [0:tag_width-1] 	   o_cmpl_tag, 
    output [0:rslt_width-1] 	   o_cmpl_rslt, 
    output [0:aux_width-1] 	   o_cmpl_aux,
    output 			   o_cmpl_tagret,
    output 			   o_cmpl_nocmpl,

    // these commands have gone to FC - cannot complete them due to timeout.
    // they must be aborted at the FC interface
    // these two paths must be independent. One should not slow down the other
    output [0:channels-1] 	   i_fcreq_r,
    input [0:channels-1] 	   i_fcreq_v,
    input [0:channels*tag_width-1] i_fcreq_tag,
    input [0:channels-1] 	   i_fcreq_rnw,

    output [0:channels-1] 	   o_fcreq_v,
    output [0:channels-1] 	   o_fcreq_ok,
    
    // abort this tag
    // sets result code to timed out
    // prevents further dma activity
    input 			   o_abort_r,
    output 			   o_abort_v,
    output [0:tag_width-1] 	   o_abort_tag, 

    output 			   o_perfmon_v,
    output [0:tag_width-1] 	   o_perfmon_tag,
  
    // complete these commands either because they are syncs or
    // because they are timeouts that have not been issued to fc channel
    

    input 			   i_cr_v,
    input [0:ctxtid_width-1] 	   i_cr_id,

    input 			   i_ctxt_add_v,
    input [0:ctxtid_width-1] 	   i_ctxt_add_d,

    output 			   o_cr_v,
    output [0:ctxtid_width-1] 	   o_cr_id,
    output [0:5]                   o_s1_perror,
    output                         o_perror,
    input                          i_timeout_msk_pe
		  
    );

   assign i_cmd_r = 1'b1;
   wire 			   s1_cmd_v;
   wire [0:tag_width-1] 	   s1_cmd_tag; 
   wire [0:1] 			   s1_cmd_flg;
   wire [0:15] 			   s1_cmd_d;
   wire [0:63] 			   s1_cmd_ts;
   wire 			   s1_cmd_sync;
   wire 			   s1_cmd_ok;
   
   base_alatch#(.width(tag_width+2+16+64+1+1)) is1_cmd_lat
     (.clk(clk),.reset(reset),
      .i_v(i_cmd_v),.i_r(),.i_d({i_cmd_tag,i_cmd_flg,i_cmd_d,i_cmd_ts,i_cmd_sync,i_cmd_ok}),
      .o_v(s1_cmd_v),.o_r(1'b1),.o_d({s1_cmd_tag,s1_cmd_flg,s1_cmd_d,s1_cmd_ts,s1_cmd_sync,s1_cmd_ok})
      );

   // track the age of the oldest transaction in the system
   wire [0:63] 		   ts_oldst_d, ts2_oldst_din;
   wire 		   ts_oldst_v, ts2_oldst_vin;
   wire 		               ts2_oldst_en;
   
   base_vlat_en#(.width(1))  its_oldet_vlat(.clk(clk),.reset(reset),.din(ts2_oldst_vin),.q(ts_oldst_v),.enable(ts2_oldst_en));
   base_vlat_en#(.width(64)) its_oldst_dlat(.clk(clk),.reset(1'b0), .din(ts2_oldst_din),.q(ts_oldst_d),.enable(ts2_oldst_en));
      
   wire 		   t1_v = 1;
   localparam [0:tag_width-2] tag_one = 1;
   wire [0:tag_width-1]    t1_tag;
   wire [0:tag_width-2]    t1_tag_in = t1_tag[0:tag_width-2]+tag_one;
   wire 		   t1_r;
   base_vlat_en#(.width(tag_width-1))it1_lat(.clk(clk),.reset(reset),.din(t1_tag_in),.q(t1_tag[0:tag_width-2]),.enable(t1_r));
  
  capi_parity_gen#(.dwidth(tag_width-1),.width(1)) t1_tag_pgen(.i_d(t1_tag[0:tag_width-2]),.o_d(t1_tag[tag_width-1]));

   wire 		   s1a_cmpl_v, s1a_cmpl_r;
   wire [0:tag_width-1]    s1_cmpl_tag;
   wire [0:rslt_width-1]   s1_cmpl_rslt;
   wire [0:aux_width-1]    s1_cmpl_aux;
   base_aburp#(.width(tag_width+rslt_width+aux_width)) is1_cmpl_lat
     (.clk(clk),.reset(reset),
      .i_v(i_cmpl_v),.i_r(i_cmpl_r),.i_d({i_cmpl_tag,i_cmpl_rslt,i_cmpl_aux}),
      .o_v(s1a_cmpl_v),.o_r(s1a_cmpl_r),.o_d({s1_cmpl_tag,s1_cmpl_rslt,s1_cmpl_aux}),
      .burp_v());

   // completion must be pushed through the timeout pipe so that we never timeout  an expired tag
   wire [0:1] 		   s1b_cmpl_v, s1b_cmpl_r;
   base_acombine#(.ni(1),.no(2)) is1_cmb
     (.i_v(s1a_cmpl_v),.i_r(s1a_cmpl_r),.o_v(s1b_cmpl_v),.o_r(s1b_cmpl_r));

   wire 		   s2a_cmpl_v, s2a_cmpl_r;
   wire [0:rslt_width-1]   s2_cmpl_rslt;
   wire [0:aux_width-1]    s2_cmpl_aux;
   base_alatch_burp#(.width(rslt_width+aux_width)) is2_cmpl_lat
     (.clk(clk),.reset(reset),
      .i_v(s1b_cmpl_v[0]),.i_r(s1b_cmpl_r[0]),.i_d({s1_cmpl_rslt,s1_cmpl_aux}),
      .o_v(s2a_cmpl_v),   .o_r(s2a_cmpl_r),.o_d({s2_cmpl_rslt,s2_cmpl_aux})
      );

   wire 		   t1a_v, t1a_r;
   wire [0:tag_width-1]    t1a_tag;
   wire [0:1] 		   t1a_sel;
   base_primux#(.ways(2),.width(tag_width)) is1_mux
     (.i_v({s1b_cmpl_v[1],t1_v}),
      .i_r({s1b_cmpl_r[1],t1_r}),
      .i_d({s1_cmpl_tag,t1_tag}),  
      .o_v(t1a_v),
      .o_r(t1a_r),
      .o_d(t1a_tag),
      .o_sel(t1a_sel)
      );
   
   wire 		   t2_v, t2_r, t1_en;
   wire [0:tag_width-1]    t2_tag;
   wire 		   t2_nrml_cmpl; // this is a normal completion, not a timeout or sync
   base_alatch_oe#(.width(tag_width+1)) it2_lat(.clk(clk),.reset(reset),.i_v(t1a_v),.i_r(t1a_r),.i_d({t1a_tag,t1a_sel[0]}),.o_v(t2_v),.o_r(t2_r),.o_d({t2_tag,t2_nrml_cmpl}),.o_en(t1_en));
   
   wire [0:63] 		   t2_ts;
   wire 		   t2_sync;
   wire [0:1] 		   t2_flg;
   wire [0:15] 		   t2_tod;
   wire 		   t2_ok;
   base_mem#(.addr_width(tag_width-1),.width(64+1+2+16+1)) its_mem
     (.clk(clk),
      .we(s1_cmd_v),.wa(s1_cmd_tag[0:tag_width-2]),.wd({s1_cmd_ts,s1_cmd_sync,s1_cmd_flg,s1_cmd_d,s1_cmd_ok}), 
      .re(t1_en),.ra(t1_tag[0:tag_width-2]),.rd({t2_ts,t2_sync,t2_flg,t2_tod,t2_ok}) // can avoid the mux on read address by using t1_tag, not t1a_tag. The result won't be used for normal completion
      );
   wire 		   t2_tag_v;
   wire 		   tag_rst_v;
   wire [0:tag_width-1]    tag_rst_tag;

   wire [0:5]              s1_perror;
   capi_parcheck#(.width(tag_width-1)) tag_rst_tag_pcheck(.clk(clk),.reset(reset),.i_v(tag_rst_v),.i_d(tag_rst_tag[0:tag_width-2]),.i_p(tag_rst_tag[tag_width-1]),.o_error(s1_perror[0]));
   wire [0:5] 				hld_perror;
   wire [0:5]                           hld_perror_msk = hld_perror & {2'b11,~i_timeout_msk_pe,3'b111};
   base_vlat_sr#(.width(6)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(6'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror_msk),.q(o_perror));
   assign o_s1_perror = hld_perror;


   // track whether each tag is valid
   base_vmem#(.a_width(tag_width-1),.rst_ports(2)) its_vmem
     (.clk(clk),.reset(reset),
      .i_set_v(s1_cmd_v),.i_set_a(s1_cmd_tag[0:tag_width-2]),
      .i_rst_v({tag_rst_v,(i_reset_afu_cmd_tag_v & i_reset_afu_cmd_tag_r)}),.i_rst_a({tag_rst_tag[0:tag_width-2],i_reset_afu_cmd_tag[0:tag_width-2]}),
      .i_rd_en(t1_en),.i_rd_a(t1_tag[0:tag_width-2]),.o_rd_d(t2_tag_v)
      );
   
   wire [0:43] t2_ts0_inc = {      t2_tod,28'd0};
   wire [0:43] t2_ts1_inc = {10'd0,t2_tod,18'd0};
   wire [0:43] t2_ts2_inc = {20'd0,t2_tod,08'd0};
   wire [0:43] t2_ts3_inc = {28'd0,t2_tod};
   wire [0:43] t2_ts_inc;
   wire        t2_ts_vld = t2_ok & (|(t2_tod));
   
   base_emux#(.width(44),.ways(4)) it2_dmux(.din({t2_ts0_inc,t2_ts1_inc,t2_ts2_inc,t2_ts3_inc}),.dout(t2_ts_inc),.sel(t2_flg));
   
   wire [0:channels] t2_sel;
   wire 	     t2a_v, t2a_r;
   wire [0:tag_width-1] t2a_tag;
   base_arr_mux#(.ways(channels+1),.width(tag_width)) it2_mux
     (.clk(clk),.reset(reset),
      .i_v({i_fcreq_v,t2_v}),.i_r({i_fcreq_r,t2_r}),.i_d({i_fcreq_tag,t2_tag}),
      .o_v(t2a_v),.o_r(t2a_r),.o_d(t2a_tag),.o_sel(t2_sel)
      );

   wire 		t2_rnw;
   base_mux#(.ways(4),.width(1)) it2_wnr_mux(.din(i_fcreq_rnw),.dout(t2_rnw),.sel(t2_sel[0:channels-1]));
   
   wire 		t2a_nrml_cmpl = t2_sel[channels] ? t2_nrml_cmpl : 1'b0;
   wire 		t2_tag_zero = ~(|t2_tag[0:tag_width-2]) & t2_sel[channels] & ~t2_nrml_cmpl;
   wire 		t3_v, t3_r;
   wire [0:tag_width-1] t3_tag;
   wire [0:63] 		t3_ts;
   wire [0:43] 		t3_ts_inc;
   wire 		t3_tag_v;
   wire 		t3_ts_vld;
   wire 		t3_sync;
   wire 		t3_tag_zero;
   wire [0:channels] 	t3_sel;
   wire 		t3_ok;
   wire 		t3_rnw;
   
   base_alatch#(.width(1+1+tag_width+64+44+3+(channels+1)+1)) it3_lat
     (.clk(clk),.reset(reset),
      .i_v(t2a_v),.i_r(t2a_r),.i_d({t2_rnw,t2_tag_zero,t2a_tag,t2_ts,t2_ts_inc,t2_tag_v & t2_sel[channels] & ~t2a_nrml_cmpl,t2_ts_vld,t2_sync & t2_ok,t2_sel,t2a_nrml_cmpl}),
      .o_v(t3_v),.o_r(t3_r),  .o_d({t3_rnw,t3_tag_zero, t3_tag,t3_ts,t3_ts_inc,t3_tag_v,                   t3_ts_vld,t3_sync,        t3_sel, t3_nrml_cmpl})
      );

   assign o_perfmon_v = t3_v & ~t3_sel[channels];
   assign o_perfmon_tag = t3_tag;

   // dont allow read reqeusts through.
   wire 		t3a_v, t3a_r;
   base_afilter it3_fltr(.i_v(t3_v),.i_r(t3_r),.o_v(t3a_v),.o_r(t3a_r),.en(~t3_rnw));
   
   // compute the oldest transaction in the system
   wire 		   t3_act = t3a_v & t3a_r;
   wire 		   t3_cur_oldst_v;
   wire [0:63] 		   t3_cur_oldst_t;
   wire [0:63] 		   t3_cur_oldst_in = t3_tag_zero ? {64{1'b1}} : t3_cur_oldst_t;
   wire [0:63] 		   t3_cur_older    = t3_tag_v & (t3_ts < t3_cur_oldst_in);
   wire 		   t3_nxt_oldst_v  =  (t3_cur_oldst_v & ~t3_tag_zero) | t3_tag_v;
   wire [0:63] 		   t3_nxt_oldst_t  = t3_cur_older ? t3_ts : t3_cur_oldst_in;
   base_vlat_en#(.width(1))  t3_oldst_vlat(.clk(clk),.reset(reset),.din(t3_nxt_oldst_v),.q(t3_cur_oldst_v),.enable(t3_act));
   base_vlat_en#(.width(64)) t3_oldst_dlat(.clk(clk),.reset(1'b0), .din(t3_nxt_oldst_t),.q(t3_cur_oldst_t),.enable(t3_act));
   
   wire [0:63] ts1_oldst_din = t3_cur_oldst_t;
   wire ts1_oldst_vin = t3_cur_oldst_v;
   wire ts1_oldst_en  = t3_tag_zero & t3_act;

   // register to help with timing;
   base_alatch#(.width(64+1)) its2_lat(.clk(clk),.reset(reset),.i_r(),.i_v(ts1_oldst_en),.i_d({ts1_oldst_vin,ts1_oldst_din}),.o_r(1'b1),.o_v(ts2_oldst_en),.o_d({ts2_oldst_vin,ts2_oldst_din}));

   wire [0:63] 		   t3_to_time = t3_ts+t3_ts_inc;
   wire                    t3_sync_cmpl = (t3_ts == ts_oldst_d) & t3_sync & t3_tag_v & ts_oldst_v;
   
   wire 		   t4_v, t4_r;
   wire [0:tag_width-1]    t4_tag;
   wire [0:63] 		   t4_ts;
   wire [0:43] 		   t4_ts_inc;
   wire 		   t4_tag_v;
   wire 		   t4_ts_vld;
   wire 		   t4_sync;
   wire [0:63] 		   t4_to_time;
   wire [0:channels] 	   t4_sel;
   wire 		   t4_nrml_cmpl;
   base_alatch#(.width(tag_width+64+64+4+(channels+1)+1)) it4_lat
     (.clk(clk),.reset(reset),
      .i_v(t3a_v),.i_r(t3a_r),.i_d({t3_tag,t3_ts,t3_to_time,t3_tag_v,t3_ts_vld,t3_sync,t3_sync_cmpl,t3_sel,t3_nrml_cmpl}),
      .o_v(t4_v),.o_r(t4_r),.o_d({t4_tag,t4_ts,t4_to_time,t4_tag_v,t4_ts_vld,t4_sync,t4_sync_cmpl,t4_sel,t4_nrml_cmpl})
      );

   wire 		   t4_timeout = (t4_to_time < i_timestamp) & t4_ts_vld & t4_tag_v & ~t4_nrml_cmpl;


   wire 		   t5_v, t5_r;
   wire [0:tag_width-1]    t5_tag;
   wire [0:63] 		   t5_ts;
   wire [0:43] 		   t5_ts_inc;
   wire 		   t5_tag_v;
   wire 		   t5_ts_vld;
   wire 		   t5_sync;
   wire [0:63] 		   t5_to_time;
   wire 		   t5_timeout;
   wire [0:channels] 	   t5_sel;
   wire 		   t5_nrml_cmpl;
   wire 		   t4_en;

   // don't allow back-to-back transactions with the same tag
   // this way we don't need bypass logic on the vmems
   wire 		t4_gt_en = ~(t5_v & (t4_tag[0:tag_width-2] == t5_tag[0:tag_width-2]));  
   wire 		t4a_v, t4a_r;
   base_agate it4_gt(.i_v(t4_v),.i_r(t4_r),.o_v(t4a_v),.o_r(t4a_r),.en(t4_gt_en));

   base_alatch_oe#(.width(tag_width+64+64+4+1+(channels+1)+1)) it5_lat
     (.clk(clk),.reset(reset),
      .i_v(t4a_v),.i_r(t4a_r),.i_d({t4_tag,t4_ts,t4_to_time,t4_tag_v,t4_ts_vld,t4_sync,t4_sync_cmpl,t4_timeout,t4_sel,t4_nrml_cmpl}),
      .o_v(t5_v), .o_r(t5_r), .o_d({t5_tag,t5_ts,t5_to_time,t5_tag_v,t5_ts_vld,t5_sync,t5_sync_cmpl,t5_timeout,t5_sel,t5_nrml_cmpl}),
      .o_en(t4_en)
      );

   // track whether
   wire 		t5d_v, t5d_r;
   wire 		t5_not_rsp; // we haven't yet responded to this tag - is there any way it could be off when it should be on
   // option 1 - we didn't get cmd_v
   // option 2 - we got t5_nr_rst

   capi_parcheck#(.width(ctxtid_width-1)) t5_tag_pcheck(.clk(clk),.reset(reset),.i_v(t5_v),.i_d(t5_tag[0:tag_width-2]),.i_p(t5_tag[tag_width-1]),.o_error(s1_perror[1]));
   capi_parcheck#(.width(ctxtid_width-1)) t4_tag_pcheck(.clk(clk),.reset(reset),.i_v(t4_v),.i_d(t4_tag[0:tag_width-2]),.i_p(t4_tag[tag_width-1]),.o_error(s1_perror[2]));
 
   wire 		t5_nr_rst = t5d_v & t5d_r & t5_sel[channels];
   base_vmem#(.a_width(tag_width-1)) its_nr_vmem  
     (.clk(clk),.reset(reset),
      .i_set_v(s1_cmd_v),.i_set_a(s1_cmd_tag[0:tag_width-2]), 
      .i_rst_v(t5_nr_rst),.i_rst_a(t5_tag[0:tag_width-2]),
      .i_rd_en(t4_en),.i_rd_a(t4_tag[0:tag_width-2]),.o_rd_d(t5_not_rsp)
      );

   wire 		t5_fc_sent; // this tag has been sent to the fc interface, cannot abort now
   wire 		t5_fcsent_set = t5_v & t5_r & ~t5_sel[channels];
   base_vmem#(.a_width(tag_width-1)) ifc_sent_mem 
     (.clk(clk),.reset(reset),
      .i_rst_v(tag_rst_v),.i_rst_a(tag_rst_tag[0:tag_width-2]),
      .i_set_v(t5_fcsent_set),.i_set_a(t5_tag[0:tag_width-2]), 
      .i_rd_en(t4_en),.i_rd_a(t4_tag[0:tag_width-2]),.o_rd_d(t5_fc_sent));



   
   wire [0:channels] 	t5a_v, t5a_r;
   base_ademux#(.ways(channels+1)) it5_demux(.i_v(t5_v),.i_r(t5_r),.o_v(t5a_v),.o_r(t5a_r),.sel(t5_sel));

   // respond to fcreq request - ok if tag not yet timedout
   base_vlat#(.width(channels)) ifcreq_vlat(.clk(clk),.reset(reset),.din(t5a_v[0:channels-1]),.q(o_fcreq_v));
   base_vlat#(.width(channels)) ifcreq_dlat(.clk(clk),.reset(1'b0), .din({channels{t5_not_rsp}}),.q(o_fcreq_ok));
   assign t5a_r[0:channels-1] = {channels{1'b1}}; // no backpressure for fcreq response
   
   // 0 - timeout, 1 - completion
   wire [0:1] 		   t5b_v, t5b_r;
   base_acombine#(.ni(1),.no(2)) it5b_cmb(.i_v(t5a_v[channels]),.i_r(t5a_r[channels]),.o_v(t5b_v),.o_r(t5b_r));

   // abort on timeout - prevents further dma activity
   wire 		   t5_to_en = t5_timeout & t5_not_rsp;
   wire [0:1] 		   t5c_v, t5c_r;
   base_afilter it5_fltr0(.i_v(t5b_v[0]),.i_r(t5b_r[0]),.o_v(t5c_v[0]),.o_r(t5c_r[0]),.en(t5_to_en));
   base_alatch#(.width(tag_width)) it6_abrt_lat(.clk(clk),.reset(reset),.i_v(t5c_v[0]),.i_r(t5c_r[0]),.i_d(t5_tag),.o_v(o_abort_v),.o_r(o_abort_r),.o_d(o_abort_tag));


   // complete if this timing out and not already sent to fc channel, or this is a sync completing  or a normal completion
   wire 		   t5_cmpl_en = (t5_to_en & ~t5_fc_sent) | t5_sync_cmpl | t5_nrml_cmpl;

   base_afilter it5_fltr1(.i_v(t5b_v[1]),.i_r(t5b_r[1]),.o_v(t5c_v[1]),.o_r(t5c_r[1]),.en(t5_cmpl_en));
   localparam [0:rc_width-1] rc_ok=0;
   localparam [0:rc_width-1] rc_to='h51;
   wire [0:rc_width-1] 	   t5_cmpl_rc = t5_sync_cmpl ? rc_ok : rc_to;
   wire 		   t5_tagret = t5_nrml_cmpl | t5_sync;
   wire 		   t5_nocmpl = ~t5_not_rsp;
   wire [0:rslt_width-1]   t5_cmpl_rslt = {t5_cmpl_rc,{rslt_width-rc_width{1'b0}}};
   wire [0:aux_width-1]    t5_cmpl_aux = {aux_width{1'b0}};
   
   wire 		   s2_cmpl_en;
   base_aforce is2_cmpl_frc(.i_v(s2a_cmpl_v),.i_r(s2a_cmpl_r),.o_v(s2b_cmpl_v),.o_r(s2b_cmpl_r),.en(t5_nrml_cmpl));

   base_acombine#(.ni(2),.no(1)) it5d_cmb
     (.i_v({t5c_v[1],s2b_cmpl_v}),.i_r({t5c_r[1],s2b_cmpl_r}),.o_v(t5d_v),.o_r(t5d_r));

   wire [0:rslt_width-1]   t5_rslt;
   wire [0:aux_width-1]    t5_aux;
   base_mux#(.width(rslt_width+aux_width)) it5_rslt_mux(.din({s2_cmpl_rslt,s2_cmpl_aux,t5_cmpl_rslt,t5_cmpl_aux}),.dout({t5_rslt,t5_aux}),.sel({t5_nrml_cmpl,~t5_nrml_cmpl}));
   
   base_alatch_burp#(.width(tag_width+rslt_width+aux_width+1+1)) it6_cmpl_lat
     (.clk(clk),.reset(reset),
      .i_v(t5d_v),.i_r(t5d_r),.i_d({    t5_tag,     t5_rslt,     t5_aux, t5_nocmpl, t5_tagret}),
      .o_v(o_cmpl_v),.o_r(o_cmpl_r),.o_d({o_cmpl_tag, o_cmpl_rslt, o_cmpl_aux,  o_cmpl_nocmpl,  o_cmpl_tagret}));

   // register to reset for timing
   base_alatch#(.width(tag_width)) it5_sync_rst_lat(.clk(clk),.reset(reset),.i_v(t5c_v[1] & t5c_r[1]),.i_r(),.i_d(t5_tag),.o_v(tag_rst_v),.o_d(tag_rst_tag),.o_r(1'b1));

   
   
   // context reset
   wire 		   c1_v = 1;
   localparam [0:ctxtid_width-2] ctxt_one = 1;
   wire [0:ctxtid_width-1] c1_id;
   wire [0:ctxtid_width-2]    c1_id_in = c1_id[0:ctxtid_width-2]+ctxt_one;
   wire 		      c1_r;
   base_vlat_en#(.width(ctxtid_width-1))ic1_lat(.clk(clk),.reset(reset),.din(c1_id_in),.q(c1_id[0:ctxtid_width-2]),.enable(c1_r));


   // only allow this to start a new cycle through the contexts when ts_oldest is updated
   // we must make sure that the ts_oldest machine makes one complete cycle before we look at its result
   wire 		      c1_en = |(c1_id[0:ctxtid_width-2]) | ts2_oldst_en;
   wire 		      c1a_v, c1a_r;
   
   base_agate ic1_gt(.i_v(c1_v),.i_r(c1_r),.o_v(c1a_v),.o_r(c1a_r),.en(c1_en));
   
   wire 		      c2_v, c2_r, c1_re;
   wire [0:ctxtid_width-1]    c2_id;
   base_alatch_oe#(.width(ctxtid_width)) ic2_lat(.clk(clk),.reset(reset),.i_v(c1a_v),.i_r(c1a_r),.i_d(c1_id),.o_v(c2_v),.o_r(c2_r),.o_d(c2_id),.o_en(c1_re));

  capi_parity_gen#(.dwidth(ctxtid_width-1),.width(1)) c1_id_pgen(.i_d(c1_id[0:ctxtid_width-2]),.o_d(c1_id[ctxtid_width-1])); 
 
   wire [0:63] 		      c2_ts;
   capi_parcheck#(.width(ctxtid_width-1)) i_cr_id_pcheck(.clk(clk),.reset(reset),.i_v(i_cr_v),.i_d(i_cr_id[0:ctxtid_width-2]),.i_p(i_cr_id[ctxtid_width-1]),.o_error(s1_perror[3]));
   capi_parcheck#(.width(ctxtid_width-1)) o_cr_id_pcheck(.clk(clk),.reset(reset),.i_v(o_cr_v),.i_d(o_cr_id[0:ctxtid_width-2]),.i_p(o_cr_id[ctxtid_width-1]),.o_error(s1_perror[4]));

   base_mem#(.addr_width(ctxtid_width-1),.width(64)) icr_tmem
     (.clk(clk),
      .we(i_cr_v),.wa(i_cr_id[0:ctxtid_width-2]),.wd(i_timestamp),
      .re(c1_re),   .ra(c1_id[0:ctxtid_width-2]),.rd(c2_ts)
      );

   
   wire 		      c2_cr_v;
   base_vmem#(.a_width(ctxtid_width-1),.rst_ports(2)) icr_vmem
     (.clk(clk),.reset(reset),
      .i_set_v(i_cr_v),.i_set_a(i_cr_id[0:ctxtid_width-2]),
      .i_rst_v({i_ctxt_add_v,o_cr_v}),.i_rst_a({i_ctxt_add_d[0:ctxtid_width-2],o_cr_id[0:ctxtid_width-2]}),
      .i_rd_en(c1_re),.i_rd_a(c1_id[0:ctxtid_width-2]),.o_rd_d(c2_cr_v)
      );

   wire [0:1] 		      c2_gc;
   wire 		      cm_we;
   wire [0:ctxtid_width-1]    cm_wa;
   wire [0:1] 		      cm_wd;
   base_mem#(.addr_width(ctxtid_width-1),.width(2)) icr_cmem
     (.clk(clk),
      .we(cm_we),.wa(cm_wa[0:ctxtid_width-2]),.wd(cm_wd),
      .re(c1_re),.ra(c1_id[0:ctxtid_width-2]),.rd(c2_gc)
      );

   wire [0:1] 		      c3_gc;
   wire [0:ctxtid_width-1]    c3_id;
   wire [0:63] 		      c3_ts;
   wire 		      c3_cr_v;
   base_alatch#(.width(2+ctxtid_width+64+1)) ic3_lat
     (.clk(clk),.reset(reset),
      .i_v(c2_v),.i_r(c2_r),.i_d({c2_gc,c2_id,c2_ts,c2_cr_v}),
      .o_v(c3_v),.o_r(c3_r),.o_d({c3_gc,c3_id,c3_ts,c3_cr_v})
      );

   assign cm_we = (c3_v & ~(& c3_gc)) | i_cr_v;

   capi_parcheck#(.width(ctxtid_width-1)) c3_id_pcheck(.clk(clk),.reset(reset),.i_v(c3_v),.i_d(c3_id[0:ctxtid_width-2]),.i_p(c3_id[ctxtid_width-1]),.o_error(s1_perror[5])); 

   assign cm_wa = i_cr_v ? i_cr_id : c3_id;
   assign cm_wd = i_cr_v ? 0 : (c3_gc+2'd1);

   // if there is a known oldest transaciton we must be older.  If not we must have been arround for 2 generations   
   wire 		      c3_cr_en = c3_cr_v & (ts_oldst_v ? (c3_ts < ts_oldst_d) : c3_gc[0]);
   wire 		      c3a_v, c3a_r;
   base_afilter ic3_fltr(.i_v(c3_v),.i_r(c3_r),.o_v(c3a_v),.o_r(c3a_r),.en(c3_cr_en));
   base_alatch#(.width(ctxtid_width)) ic4_lat(.clk(clk),.reset(reset),.i_v(c3a_v),.i_r(c3a_r),.i_d(c3_id),.o_v(o_cr_v),.o_r(1'b1),.o_d(o_cr_id));
   
		       
endmodule // ktms_afu_timeout

