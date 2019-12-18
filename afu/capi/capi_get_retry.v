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
module capi_get_retry#
  (parameter tag_width=1,
   parameter sid_width=1,
   parameter aux_width=1,
   parameter ctxtid_width=1,
   parameter ea_width=64,
   parameter tsize_width=1,
   parameter req_width = aux_width+ctxtid_width+ea_width+tsize_width,  
   parameter rc_width=8,
   parameter pea_width=ea_width-12-1,
   parameter ctag_width=8,
   parameter tstag_width=1,
   parameter cnt_rsp_width = pea_width*2+ctxtid_width+ctag_width+4,
   parameter cto_width = 16,
  
   parameter is_get = 1,
   parameter [0:rc_width-1] rc_ok = 0,
   parameter [0:rc_width-1] rc_aerror = 1,
   parameter [0:rc_width-1] rc_sid  = 'h80,
   parameter [0:rc_width-1] rc_ctxt = 'h0b,
   parameter [0:rc_width-1] rc_cred = 'h09, 
   parameter [0:rc_width-1] rc_flushed = 'h06,
   parameter [0:rc_width-1] rc_paged = 'h0a,
   parameter [0:rc_width-1] rc_paged_coming= 'h8a,
   parameter [0:rc_width-1] rc_paged_late   = 'h8b,
   parameter [0:3] cr_ok = 0,
   parameter [0:3] cr_aerr = 1,
   parameter [0:3] cr_rerr = 2,
   parameter [0:3] cr_werr = 3
   )
  (input clk,
   input 		     reset,

   input [0:cto_width-1]     i_cont_timeout,
   input 		     i_ctxt_trm_v,
   input [0:ctxtid_width-1]  i_ctxt_trm_id,
   input 		     i_tstag_inv_v,
   input [0:tstag_width-1]   i_tstag_inv_id,

   input 		     i_timer_pulse,
   input 		     i_req_v,
   output 		     i_req_r,
   input [0:tag_width-1]     i_req_tag,
   input [0:sid_width-1]     i_req_sid,
   input 		     i_req_f, // first request in this stream - clear the failed bits.
   input [0:req_width-1]     i_req_d, 

   input 		     i_rsp_v,
   input [0:tag_width-1]     i_rsp_tag,
   input [0:sid_width-1]     i_rsp_sid,
   input [0:tstag_width-1]   i_rsp_tstag,
   input [0:rc_width-1]      i_rsp_d,

   output 		     o_req_v,
   input 		     o_req_r,
   output [0:tag_width-1]    o_req_tag,
   output [0:sid_width-1]    o_req_sid,
   output 		     o_req_f, 
   output [0:req_width-1]    o_req_d, 

   output 		     o_rsp_v,
   output [0:tag_width-1]    o_rsp_tag,
   output [0:sid_width-1]    o_rsp_sid,
   output [0:rc_width-1]     o_rsp_d,

   // continue response received via mmio

   input 		     i_cnt_rsp_v,
   input [0:cnt_rsp_width-1] i_cnt_rsp_d,   
   output 		     o_cnt_rsp_miss,
   output [0:63] 	     o_cnt_pend_d,  
   output 		     o_cnt_pend_dropped,
   output [0:3] 	     o_dbg_cnt_inc,
   output [0:2]              o_s1_perror,
   output                    o_perror
   );
   

   // rc_sid is a possibly transient condition due to paged, so they should be retried.
   // we will catch the permenant failure here, to avoid infinite retry. 
   wire 		    s0_rsp_sid     = i_rsp_d == rc_sid;
   wire 		    s0_rsp_paged   = i_rsp_d == rc_paged;
   wire 		    s0_rsp_epaged  = i_rsp_d == rc_paged_coming;  // pged response, will get paged late lter
      wire 		    s0_rsp_lpaged  = i_rsp_d == rc_paged_late;    // paged response, had paged coming earlier
   wire 		    s0_rsp_flushed = i_rsp_d == rc_flushed;
   wire 		    s0_rsp_ok      = i_rsp_d == {rc_width{1'b0}};
   wire [0:1] 		    s0_rsp_sel;
   assign 		  s0_rsp_sel[0] = s0_rsp_lpaged | s0_rsp_epaged | s0_rsp_paged | s0_rsp_flushed | s0_rsp_sid; // retry if paged or flushed or sid
   assign		  s0_rsp_sel[1] = ~s0_rsp_sel[0]; // otherwise don't retry 
   
   

   // 0: retry
   // 1: respond
   wire [0:1] 		  s0_rsp_v, s0_rsp_r;
   base_ademux#(.ways(2)) is0_rsp_dmux(.i_v(i_rsp_v),.i_r(),.o_v(s0_rsp_v),.o_r(2'b11),.sel(s0_rsp_sel));
   
   

   // fifo to hold responses waiting to be reried   
   wire 		   s1_rsp_v;
   wire [0:tag_width-1]    s1_rsp_tag;
   wire [0:sid_width-1]    s1_rsp_sid;
   wire [0:tstag_width-1]  s1_rsp_tstag;
   wire [0:rc_width-1] 	   s1_rsp_rc;
   wire [0:ea_width-1] 	   s1_rsp_req_ea;
   wire [0:ctxtid_width-1] s1_rsp_req_ctxt;
   wire [0:tsize_width-1]  s1_rsp_req_tsize;
   wire 		   s1_rsp_req_f;
   wire [0:aux_width-1]    s1_rsp_req_aux;
   wire 		   s1_rsp_paged = (s1_rsp_rc == rc_paged);
   wire 		   s1_rsp_lpaged = (s1_rsp_rc == rc_paged_late);
   wire 		   s1_rsp_paged_coming = (s1_rsp_rc == rc_paged_coming);

   wire 		   s1a_v;
   base_afilter is1a_fltr(.i_v(s1_rsp_v),.i_r(),.o_v(s1a_rsp_v),.o_r(1'b1),.en(~s1_rsp_paged_coming));
   
   wire [0:tag_width-1]    s2_rsp_tag;
   wire [0:sid_width-1]    s2_rsp_sid;
   wire [0:rc_width-1] 	   s2_rsp_rc;
   wire 		   s2_rsp_paged;

   wire 		   s2_rsp_v, s2_rsp_r;
   
   base_fifo#(.LOG_DEPTH(tag_width),.width(tag_width+sid_width+1+rc_width)) irsp_fifo
     (.clk(clk),.reset(reset),.i_v(s1a_rsp_v),.i_r(),.i_d({s1_rsp_tag,s1_rsp_sid,(s1_rsp_paged | s1_rsp_lpaged),s1_rsp_rc}),.o_v(s2_rsp_v),.o_r(s2_rsp_r),.o_d({s2_rsp_tag,s2_rsp_sid,s2_rsp_paged,s2_rsp_rc}));

   
   // track whether we have a continue pending
   wire 		   cnt_pend_v;
   wire 		   cnt_pend_set = s1_rsp_v & (s1_rsp_paged | s1_rsp_paged_coming) & ~cnt_pend_v;
   assign o_cnt_pend_dropped            = s1_rsp_v & (s1_rsp_paged | s1_rsp_paged_coming) & cnt_pend_v;

   //events that end continue pending condition
   wire 		   cto_zero;     // timeout
   wire 		   s1_ctrm_v;    // the context terminated
   wire 		   s1_tstag_inv_v; // the tstag invalidated (due to timeout)
   wire 		   s2_cnt_rsp_v; // got a response
   wire 		   cto_enable;
   wire 		   cnt_pend_rst = ~cnt_pend_set & (s1_tstag_inv_v | s1_ctrm_v | (cto_zero  & cto_enable) | s2_cnt_rsp_v); // eventually -timeout or matching mmio or context terminates

   // timeout
   base_vlat#(.width(1)) icto_disable_lat(.clk(clk),.reset(reset),.din(|i_cont_timeout),.q(cto_enable));
   
   wire [0:cto_width-1]    cto_init = i_cont_timeout;
   wire [0:cto_width-1]    cto_d;
   assign 		   cto_zero = ~(|cto_d);
   wire 		   s1_cnt_rsp_match;


   wire [0:cto_width-1]    cto_din = cnt_pend_set ? cto_init : cto_d - 1'b1;
   wire 		   cto_dec_en = cnt_pend_set | (i_timer_pulse & ~cto_zero);


   // track how long it takes to get a continue response
   wire [31:0] 		   cnt_pend_time;
   wire [31:0] 		   cnt_pend_time_in = cnt_pend_set ? 0 : cnt_pend_time+1;
   base_vlat_en#(.width(32)) icnt_pend_time_lat(.clk(clk),.reset(1'b0),.din(cnt_pend_time_in),.q(cnt_pend_time),.enable(cnt_pend_set | i_timer_pulse));

   wire 		   cto_1ms  = | cnt_pend_time[31:9];
   wire 		   cto_16ms = | cnt_pend_time[31:13];
   wire 		   cto_256ms = | cnt_pend_time[31:17];
   wire [0:2] 		   s2_cto;
   base_vlat#(.width(3)) icto_hist_lat(.clk(clk),.reset(reset),.din({cto_1ms,cto_16ms,cto_256ms}),.q(s2_cto));
   assign o_dbg_cnt_inc[0:3] = {1'b1,s2_cto} & {4{s2_cnt_rsp_v}};
   
   
   base_vlat_en#(.width(cto_width))   icnt_pend_tlat(.clk(clk),.reset(reset),.din(cto_din),.q(cto_d),.enable(cto_dec_en));
   base_vlat_sr                       icnt_pend_vlat(.clk(clk),.reset(reset),.set(cnt_pend_set),.rst(cnt_pend_rst),.q(cnt_pend_v));
   wire [0:pea_width-1]    cnt_pend_pea;
   wire [0:ctxtid_width-1] cnt_pend_ctxt;
   wire [0:sid_width-1]    cnt_pend_sid;
   wire [0:tstag_width-1]  cnt_pend_tstag;

   wire [0:2]              s1_perror;

   capi_parcheck#(.width(ea_width-1)) s1_rsp_req_ea_pcheck(.clk(clk),.reset(reset),.i_v(s1_rsp_v),.i_d(s1_rsp_req_ea[0:ea_width-2]),.i_p(s1_rsp_req_ea[ea_width-1]),.o_error(s1_perror[0]));

   base_vlat_en#(.width(tstag_width+sid_width+ctxtid_width+pea_width)) icnt_pend_dlat
     (.clk(clk),.reset(1'b0),.din({s1_rsp_tstag,s1_rsp_sid,s1_rsp_req_ctxt,s1_rsp_req_ea[0:pea_width-1]}),.q({cnt_pend_tstag,cnt_pend_sid,cnt_pend_ctxt,cnt_pend_pea}),.enable(cnt_pend_set));  

//   base_vlat#(.width(pea_width+ctxtid_width+1)) icnt_pend_olat(.clk(clk),.reset(1'b0),.din({cnt_pend_pea,cnt_pend_ctxt,cnt_pend_v}),.q(o_cnt_pend_d[pea_width+ctxtid_width:0]));  original 
     base_vlat#(.width(pea_width+ctxtid_width+1)) icnt_pend_olat(.clk(clk),.reset(1'b0),.din({cnt_pend_pea,cnt_pend_ctxt,cnt_pend_v}),.q(o_cnt_pend_d[63-(pea_width+ctxtid_width):63-0])); 
   assign o_cnt_pend_d[63-63:63-(pea_width+ctxtid_width+1)] = {64-(pea_width+ctxtid_width+1){1'b0}};

   // handle mmio response to continue
   wire [0:pea_width-1]    s0_cnt_rsp_pea;
   wire [0:pea_width-1]    s0_cnt_rsp_msk;
   wire [0:ctxtid_width-1] s0_cnt_rsp_ctxt;
   wire [0:ctag_width-1]   s0_cnt_rsp_ctag;
   wire [0:3] 		   s0_cnt_rsp_rc;
   assign {s0_cnt_rsp_msk,s0_cnt_rsp_pea,s0_cnt_rsp_ctxt,s0_cnt_rsp_ctag,s0_cnt_rsp_rc} = i_cnt_rsp_d;
   wire 		   s0_cnt_rsp_pea_match = (s0_cnt_rsp_msk & s0_cnt_rsp_pea) == (cnt_pend_pea & s0_cnt_rsp_msk);
   wire 		   s0_cnt_rsp_ctxt_match = s0_cnt_rsp_ctxt == cnt_pend_ctxt;
   wire 		   s0_cnt_rsp_disq;
   generate
      if (is_get == 0)
	assign s0_cnt_rsp_disq = s0_cnt_rsp_rc == cr_rerr;
      else
	assign s0_cnt_rsp_disq = s0_cnt_rsp_rc == cr_werr;
   endgenerate
   wire 		   s0_cnt_rsp_v = i_cnt_rsp_v & cnt_pend_v & s0_cnt_rsp_pea_match & s0_cnt_rsp_ctxt_match & ~s0_cnt_rsp_disq;
   base_vlat#(.width(1)) icnt_rsp_miss_lat(.clk(clk),.reset(reset),.q(o_cnt_rsp_miss),.din(i_cnt_rsp_v & ~s0_cnt_rsp_v));
   
   wire 		   s1_cnt_rsp_v;
   wire [0:sid_width-1]    s1_cnt_rsp_sid;
   wire [0:3] 		   s1_cnt_rsp_rc;
   base_alatch#(.width(sid_width+4)) is1_cnt_rsp_match(.clk(clk),.reset(reset),.i_v(s0_cnt_rsp_v),.i_r(),.i_d({cnt_pend_sid,s0_cnt_rsp_rc}),.o_v(s1_cnt_rsp_v),.o_r(1'b1),.o_d({s1_cnt_rsp_sid,s1_cnt_rsp_rc}));
   base_vlat#(.width(1)) is2_cnt_rsp_lat(.clk(clk),.reset(reset),.din(s1_cnt_rsp_v),.q(s2_cnt_rsp_v));

   capi_parcheck#(.width(ctxtid_width-1)) i_ctxt_trm_id_pcheck(.clk(clk),.reset(reset),.i_v(i_ctxt_trm_v),.i_d(i_ctxt_trm_id[0:ctxtid_width-2]),.i_p(i_ctxt_trm_id[ctxtid_width-1]),.o_error(s1_perror[1]));
   capi_parcheck#(.width(ctxtid_width-1)) cnt_pend_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(cnt_pend_v),.i_d(cnt_pend_ctxt[0:ctxtid_width-2]),.i_p(cnt_pend_ctxt[ctxtid_width-1]),.o_error(s1_perror[2]));

   wire [0:2] 				hld_perror;
   base_vlat_sr#(.width(3)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(3'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| s1_perror),.q(o_perror));
   assign o_s1_perror = hld_perror;

   wire 		   s0_ctrm_v = (i_ctxt_trm_id[0:ctxtid_width-2] == cnt_pend_ctxt[0:ctxtid_width-2]) & cnt_pend_v & i_ctxt_trm_v;
   base_vlat#(.width(1)) is1_ctrm_lat(.clk(clk),.reset(reset),.din(s0_ctrm_v),.q(s1_ctrm_v));

   wire 		   s0_tstag_inv_v = (i_tstag_inv_id == cnt_pend_tstag) & cnt_pend_v & i_tstag_inv_v;
   base_vlat#(.width(1)) is1_tstag_inv_lat(.clk(clk),.reset(reset),.din(s0_tstag_inv_v),.q(s1_tstag_inv_v));
   
   
   // stop when we get to paged response if paged is pending
   wire 		   s2a_rsp_v, s2a_rsp_r;
   wire 		   s2_rsp_hold = cnt_pend_v & s2_rsp_paged;
   base_agate is2_rsp_gt(.i_v(s2_rsp_v),.i_r(s2_rsp_r),.o_v(s2a_rsp_v),.o_r(s2a_rsp_r),.en(~s2_rsp_hold));
   
   // split into two streams for abort and request lookup
   wire [0:1] 		   s2b_rsp_v,s2b_rsp_r;
   base_acombine#(.ni(1),.no(2)) is2_rsp_splt(.i_v(s2a_rsp_v),.i_r(s2a_rsp_r),.o_v(s2b_rsp_v),.o_r(s2b_rsp_r));

   wire 		   s2_rsp_re;
   wire [0:1] 		   s3_rsp_v, s3_rsp_r;
   base_alatch_oe#(.width(1)) is3_rsp_lat(.clk(clk),.reset(reset),.i_v(s2b_rsp_v[0]),.i_r(s2b_rsp_r[0]),.i_d(),.o_v(s3_rsp_v[0]),.o_r(s3_rsp_r[0]),.o_en(s2_rsp_re),.o_d());
   // read abort memories

   wire [0:1] 		   s3_rsp_fail;
   // set sid as aborted if not retrying and not ok
   base_vmem#(.a_width(sid_width)) istrm_abrt_mem
     (.clk(clk),.reset(reset),
      .i_set_v(s0_rsp_v[1] & ~s0_rsp_ok),.i_set_a(i_rsp_sid),
      .i_rst_v(i_req_v & i_req_f),.i_rst_a(i_req_sid),
      .i_rd_en(s2_rsp_re),.i_rd_a(s2_rsp_sid),.o_rd_d(s3_rsp_fail[0]));

   wire 		  s3_rsp_rrc_v;
   
   base_vmem#(.a_width(sid_width)) icnt_rsp_rc_vmem
     (.clk(clk),.reset(reset),
      .i_set_v(s1_cnt_rsp_v & |(s1_cnt_rsp_rc)),.i_set_a(s1_cnt_rsp_sid),
      .i_rst_v(i_req_v & i_req_f),.i_rst_a(i_req_sid),
      .i_rd_en(s2_rsp_re),.i_rd_a(s2_rsp_sid),.o_rd_d(s3_rsp_fail[1])
      );
   wire 		  s3_rsp_abrt = | s3_rsp_fail;

   // combine response stream 0 from above, and 1 from sram lookup
   wire 		   s3a_rsp_v, s3a_rsp_r;
   base_acombine#(.ni(2),.no(1)) is3_cmb(.i_v(s3_rsp_v),.i_r(s3_rsp_r),.o_v(s3a_rsp_v),.o_r(s3a_rsp_r));
   
   // don't allow inbound requests if there is a continue pending
   wire 		   s0_req_v,s0_req_r;
   base_agate s0_req_gt(.i_v(i_req_v),.i_r(i_req_r),.o_v(s0_req_v),.o_r(s0_req_r),.en(~cnt_pend_v));
   

   // choose between sending response queue output to retry or response outputs
   wire [0:1] 		  s3c_rsp_v, s3c_rsp_r;
   base_ademux#(.ways(2)) is3_rsp_demux(.i_v(s3a_rsp_v),.i_r(s3a_rsp_r),.o_v({s3c_rsp_v}),.o_r({s3c_rsp_r}),.sel({~s3_rsp_abrt,s3_rsp_abrt}));

   wire [0:tag_width-1]    s3_rsp_tag;
   wire [0:sid_width-1]    s3_rsp_sid;
   wire [0:rc_width-1] 	   s3_rsp_rc;
   wire [0:ea_width-1] 	   s3_rsp_req_ea;
   wire [0:ctxtid_width-1] s3_rsp_req_ctxt;
   wire [0:tsize_width-1]  s3_rsp_req_tsize;
   wire 		   s3_rsp_req_f;
   wire [0:aux_width-1]    s3_rsp_req_aux;
   wire 		   s3_rsp_paged;

   // if we got a failed response back from a continue, return address error
   wire [0:rc_width-1] 	   s3_rsp_rrc = s3_rsp_fail[1] ? rc_aerror : s3_rsp_rc;

   // reactivate the sid if we are restarting from a paged response
   wire 		   s3_rsp_f = s3_rsp_paged;
   
   // choose between retry request and new request   
   base_primux#(.ways(2),.width(tag_width+sid_width+1+req_width)) is3_req_mux
     (.i_v({s3c_rsp_v[0],s0_req_v}),.i_r({s3c_rsp_r[0],s0_req_r}),
      .i_d({s3_rsp_tag,s3_rsp_sid,s3_rsp_f, s3_rsp_req_aux,s3_rsp_req_ctxt,s3_rsp_req_ea,s3_rsp_req_tsize,
	     i_req_tag, i_req_sid,     i_req_f, i_req_d}),
      .o_v(o_req_v),.o_r(o_req_r),.o_d({o_req_tag,o_req_sid,o_req_f,o_req_d}),.o_sel());

   wire 		   s4_rsp_v;
   wire [0:tag_width-1]    s4_rsp_tag;
   wire [0:sid_width-1]    s4_rsp_sid;
   wire [0:rc_width-1] 	   s4_rsp_rc;

  
   // response output
   base_primux#(.ways(2),.width(tag_width+sid_width+rc_width)) is0_rsp_pmux
     (.i_v({s0_rsp_v[1],s3c_rsp_v[1]}),.i_r({s0_rsp_r[1],s3c_rsp_r[1]}),.i_d({i_rsp_tag,i_rsp_sid,i_rsp_d,s3_rsp_tag,s3_rsp_sid,s3_rsp_rrc}),
      .o_v(s4_rsp_v),               .o_r(1'b1),                  .o_d({s4_rsp_tag,s4_rsp_sid,s4_rsp_rc}),.o_sel());

   wire 		   s5_rsp_v;
   wire [0:tag_width-1]    s5_rsp_tag;
   wire [0:sid_width-1]    s5_rsp_sid;
   wire [0:rc_width-1] 	   s5_rsp_rc;
   wire 		   s4_rsp_re;
   
   base_alatch_oe#(.width(tag_width+sid_width+rc_width)) is5_rsp_lat
     (.clk(clk),.reset(reset),
      .i_v(s4_rsp_v), .i_r(),       .i_d({s4_rsp_tag,s4_rsp_sid,s4_rsp_rc}),
      .o_v(s5_rsp_v), .o_r(1'b1),   .o_d({s5_rsp_tag,s5_rsp_sid,s5_rsp_rc}),.o_en(s4_rsp_re));

   // remember the first non-zero result code for each sid 
   wire 		   s5_rsp_rc_set;
   wire 		   s5_rsp_mem_rc_v;
   base_vmem_bypass#(.a_width(sid_width)) is4_nzrc_vmem
     (.clk(clk),.reset(reset),
      .i_set_a(s5_rsp_sid),.i_set_v(s5_rsp_rc_set),
      .i_rst_a(i_req_sid),.i_rst_v(i_req_v),
      .i_rd_a(s4_rsp_sid),.i_rd_en(s4_rsp_re),.o_rd_d(s5_rsp_mem_rc_v)
      );
   wire [0:rc_width-1] 	   s5_rsp_mem_rc;
   base_mem_bypass#(.addr_width(sid_width),.width(rc_width)) is4_rc_mem
     (.clk(clk),
      .ra(s4_rsp_sid),.re(s4_rsp_re),.rd(s5_rsp_mem_rc),
      .wa(s5_rsp_sid),.we(s5_rsp_rc_set),.wd(s5_rsp_rc)
      );

   wire 		   s5_rsp_rc_nz = (|s5_rsp_rc);
   
   assign s5_rsp_rc_set = s5_rsp_rc_nz & ~s5_rsp_mem_rc_v;
   assign o_rsp_d = s5_rsp_mem_rc_v ? s5_rsp_mem_rc : s5_rsp_rc;
   assign o_rsp_v = s5_rsp_v;
   assign o_rsp_tag = s5_rsp_tag;
   assign o_rsp_sid = s5_rsp_sid;
   
      
   // need a memory in which we store stuff about a request.  Specifically, we need EA.  We cannot wait for retry pipe exit because we might miss the restart MMIO
   capi_primem#(.width(sid_width+aux_width+ctxtid_width+ea_width+tsize_width),.addr_width(tag_width),.aux0_width(tstag_width+tag_width+rc_width),.aux1_width(tag_width+rc_width+1)) ireq_mem
     (.clk(clk),.reset(reset),
      .we(i_req_v),.wa(i_req_tag),.wd({i_req_sid,i_req_d}),
      .i_r0_v(s0_rsp_v[0]),                       .i_r0_a( i_rsp_tag),.i_r0_aux({i_rsp_tstag,i_rsp_tag,i_rsp_d}),
      .i_r1_v(s2b_rsp_v[1]),.i_r1_r(s2b_rsp_r[1]),.i_r1_a(s2_rsp_tag),.i_r1_aux({s2_rsp_tag,s2_rsp_rc,s2_rsp_paged}),
      .o_r0_v(s1_rsp_v),                        .o_r0_aux({s1_rsp_tstag,s1_rsp_tag,s1_rsp_rc}), .o_r0_d({s1_rsp_sid,s1_rsp_req_aux,s1_rsp_req_ctxt,s1_rsp_req_ea,s1_rsp_req_tsize}),
      .o_r1_v(s3_rsp_v[1]),.o_r1_r(s3_rsp_r[1]),.o_r1_aux({s3_rsp_tag,s3_rsp_rc,s3_rsp_paged}), .o_r1_d({s3_rsp_sid,s3_rsp_req_aux,s3_rsp_req_ctxt,s3_rsp_req_ea,s3_rsp_req_tsize})
      );


   
endmodule // capi_get_retry
