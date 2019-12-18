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
module capi_get#
  (
   
   parameter sid_width=3, // stream id
   parameter beat_width = 3,
   parameter uid_width=5,
   parameter [0:uid_width-1] uid = 0,
   parameter ea_width = 65,
   parameter rc_width=1,
   parameter ctxtid_width = 9,
   parameter aux_width=1,
   parameter tag_width = 8,
   parameter tsize_width = 12,
   parameter ssize_width = 18,
   parameter tstag_width = 1,
   parameter pea_width=ea_width-13,
   parameter ctag_width=8,
   parameter cto_width=1,
   parameter cnt_rsp_width= pea_width*2+ctxtid_width+ctag_width+4,
   parameter rd_width = tag_width+sid_width+1+1+aux_width+ctxtid_width+ea_width+tsize_width,   
   parameter rdata_addr_width = tag_width+beat_width,
   parameter rsp_width = rc_width+sid_width+tstag_width+tag_width,
   parameter [0:0] ignore_tstag_inv=0
   )
   (
    output [0:3] 		 o_dbg_cnt_inc,
    input 			 clk,
    input 			 reset,
    input 			 i_disable,
    input 			 i_timer_pulse,
    input [0:cto_width-1] 	 i_cont_timeout,
    output 			 o_rm_err, 
    /* client interface */
    input [0:ea_width-1] 	 get_addr,
    input [0:ctxtid_width-1] 	 get_ctxt,
    input [0:aux_width-1] 	 get_aux,
    input [0:ssize_width-1] 	 get_size,
    input 			 get_valid,
    output 			 get_acc,
   
    output 			 get_data_v,
    input 			 get_data_r, //  valid same cycle as get_data_valid
    output [0:ssize_width-1] 	 get_data_bcnt,
    output 			 get_data_e, // aligned with get_data_valid
    output [0:3] 		 get_data_c, // count - valid only with _e, zero = 16 
    output [0:129] 		 get_data_d, // follows get_data_valid by one cycle 
    output [0:rc_width-1] 	 get_data_rc, // tbd
   
    /* gx address interface */
    output 			 o_req_v,
    output [0:rd_width-1] 	 o_req_d,   // has ea parity in it 
    input 			 o_req_r,

    /* retry interface */
    input 			 i_rsp_v,
    input [0:rsp_width-1] 	 i_rsp_d,

    input 			 i_cnt_rsp_v,
    input [0:cnt_rsp_width-1] 	 i_cnt_rsp_d,
    output 			 o_cnt_rsp_miss,
    output [0:63] 		 o_cnt_pend_d,
    output 			 o_cnt_pend_dropped,

    input 			 i_ctxt_trm_v,
    input [0:ctxtid_width-1] 	 i_ctxt_trm_id,

    input 			 i_tstag_inv_v,
    input [0:tstag_width-1] 	 i_tstag_inv_id,

    /* gx data interface */
    input 			 i_rdata_v,
    input [0:rdata_addr_width-1] i_rdata_a,
    input [0:129] 		 i_rdata_d, 
    output [0:4]                 o_s1_perror,
    output [0:2]                 o_perror , 
    input                        i_gate_sid

    );

   localparam lcl_tag_width = tag_width-uid_width;

   wire [0:uid_width-1]     lcl_uid;
   base_const#(.width(uid_width),.value(uid)) ilcl_uid(lcl_uid);


   /* buffer and tag manager */
   wire 		    r1_v, r1_r;
   wire [0:ea_width-1] 	    r1_d_ea;
   wire         	    r1_d_ea_par; 
   wire [0:ctxtid_width-1]  r1_d_ctxt;
   wire [0:aux_width-1]     r1_d_aux;
   wire [0:ssize_width-1]   r1_d_size_raw;
   
   base_alatch#(.width(ssize_width+aux_width+ctxtid_width+ea_width)) ir1
     (
      .clk(clk), .reset(reset),
      .i_v(get_valid), .i_d({get_size,get_aux,get_ctxt,get_addr}), .i_r(get_acc),
      .o_v(r1_v), .o_d({r1_d_size_raw,r1_d_aux,r1_d_ctxt,r1_d_ea}), .o_r(r1_r)
      );

   wire  [0:1]                   s1_perror;
   capi_parcheck#(.width(ea_width-1))  r1_d_ea_pcheck(.clk(clk),.reset(reset),.i_v(r1_v),.i_d( r1_d_ea[0:ea_width-2]),.i_p( r1_d_ea[ea_width-1]),.o_error(s1_perror[0]));
   wire [0:1]				hld_perror;
   base_vlat_sr#(.width(2)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(2'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror),.q(o_perror[0]));
   
   wire [0:6] 		    r1_d_ea_lsb = r1_d_ea[ea_width-1-7:ea_width-1-1]; 
   
   wire [0:ssize_width-8]   r1_d_one_cl = {{ssize_width-8{1'b0}},1'b1};
   wire [0:ssize_width-8]   r1_d_zro_cl = {{ssize_width-8{1'b0}},1'b0};
   
   wire [0:ssize_width-1]   r1_d_size_lsb = {r1_d_zro_cl,r1_d_ea_lsb};
   wire [0:ssize_width-1]   r1_d_size = r1_d_size_raw +  r1_d_size_lsb;
   wire [0:ssize_width-8]   r1_d_cachelines = r1_d_size[0:ssize_width-8] + ((|(r1_d_size[ssize_width-7:ssize_width-1])) ? r1_d_one_cl : r1_d_zro_cl);
   wire [0:6] 		    r1_d_extra = r1_d_size[ssize_width-7:ssize_width-1];
   
   wire 		    r2_v, r2_r;
   wire [0:ea_width-8] 	    r2_d_ea;   // left size alone. this now has parity in it
   wire [0:ctxtid_width-1]  r2_d_ctxt;
   wire [0:aux_width-1]     r2_d_aux;
   wire [0:6] 		    r2_d_ea_lsb;
   wire [0:6] 		    r2_d_extra;
   wire [0:ssize_width-8]   r2_d_cachelines;

      capi_parity_gen#(.dwidth(ea_width-8),.width(1)) r1_d_ea_pgen(.i_d(r1_d_ea[0:ea_width-8-1]),.o_d(r1_d_ea_par));

   base_alatch#(.width(aux_width+ctxtid_width+(ea_width-7)+14+(ssize_width-7))) ir1ltch   
     (.clk(clk),.reset(reset),
      .i_v(r1_v),.i_r(r1_r),.i_d({r1_d_aux,r1_d_ctxt,r1_d_ea[0:ea_width-1-8],r1_d_ea_par,r1_d_ea_lsb,r1_d_extra,r1_d_cachelines}),
      .o_v(r2_v),.o_r(r2_r),.o_d({r2_d_aux,r2_d_ctxt,r2_d_ea,              r2_d_ea_lsb,r2_d_extra,r2_d_cachelines}) 
      );
   
   // compensate for the extra bytes pulled in by having to take a full first cacheline
   wire 		    s0_v, s0_r /* synthesis keep = 1 */;
   wire [0:ea_width-8] 	    s0_ea;   
   wire [0:ctxtid_width-1]  s0_ctxt;
   wire [0:aux_width-1]     s0_aux;
   wire 		    s0_e, s0_s /* synthesis keep = 1 */; /* this is the last transaction */
   wire [0:6] 		    s0_eafst_lsb;
   wire [0:6] 		    s0_ealst_lsb;
   wire [0:ssize_width-7]   s0_d_cnt;

   capi_unroll_cnt#(.iwidth(ea_width-7-1), .dwidth(aux_width+ctxtid_width+14), .cwidth(ssize_width-7)) iunrl   
     (
      .clk(clk), .reset(reset),
      .din_v(r2_v),  .din_i(r2_d_ea[0:ea_width-8-1] ), .din_c(r2_d_cachelines), .din_d({r2_d_aux,r2_d_ctxt,r2_d_ea_lsb,r2_d_extra}),     .din_r(r2_r),  
      .dout_v(s0_v), .dout_i(s0_ea[0:ea_width-8-1]), .dout_e(s0_e), .dout_s(s0_s),             .dout_d({s0_aux,s0_ctxt,s0_eafst_lsb,s0_ealst_lsb}), .dout_r(s0_r)
      );

   capi_parcheck#(.width(ea_width-8))  r2_d_ea_pcheck(.clk(clk),.reset(reset),.i_v(r2_v),.i_d( r2_d_ea[0:ea_width-8-1]),.i_p( r2_d_ea[ea_width-8]),.o_error(s1_perror[1]));
   capi_parity_gen#(.dwidth(ea_width-8),.width(1)) s0_ea_pgen(.i_d(s0_ea[0:ea_width-8-1]),.o_d(s0_ea[ea_width-8]));
   
   wire [0:lcl_tag_width-1] s1_tag; 
   wire 		    s1d_v /*synthesis keep = 1 */;
   wire 		    s1d_r /*synthesis keep = 1 */;
   
   wire [0:1] 		    s1a_v /* synthesis keep = 1 */;
   wire [0:1] 		    s1a_r /* synthesis keep = 1 */;
   
   wire [0:(ea_width-4)-4]  s1_ea;
   wire [0:ctxtid_width-1]  s1_ctxt;
   wire [0:aux_width-1]     s1_aux;
   wire [0:6] 		    s1_eafst_lsb;
   
   wire [0:6] 		    s1_ealst_lsb;
   wire 		    s1_e, s1_s;
   
   base_alatch#(.width(aux_width+ctxtid_width+ea_width+7+2)) iurltch
     (.clk(clk),.reset(reset),
      .i_v(s0_v), .i_d({s0_aux,s0_ctxt,s0_ea,s0_eafst_lsb,s0_ealst_lsb,s0_e,s0_s}),       .i_r(s0_r),
      .o_v(s1a_v[0]), .o_d({s1_aux,s1_ctxt,s1_ea,s1_eafst_lsb,s1_ealst_lsb,s1_e,s1_s}), .o_r(s1a_r[0]));

   wire		    s1b_v, s1b_r;
   base_acombine#(.ni(2),.no(1)) is1cmb
     (.i_v(s1a_v),.i_r(s1a_r),
      .o_v(s1b_v),.o_r(s1b_r)
      );
   
   /* note the tag and number of beats and bytes of last cacheline of stream */
   wire [0:ea_width-1] 	    stg2_addr;

   wire [0:rc_width-1] 	    lcl_rsp_rc;
   wire [0:uid_width-1]     lcl_rsp_uid;
   wire [0:lcl_tag_width-1] lcl_rsp_tag;
   wire [0:sid_width-1]     lcl_rsp_sid;
   wire [0:tstag_width-1]   lcl_rsp_tstag;
   assign {lcl_rsp_rc,lcl_rsp_sid,lcl_rsp_tstag,lcl_rsp_uid,lcl_rsp_tag} = i_rsp_d;
   wire 		    lcl_rsp_v = (lcl_rsp_uid == lcl_uid) & i_rsp_v;


   wire 			  stg2b_v, stg2b_r;
   wire [0:lcl_tag_width-1] 	  stg2_tag;
   wire [0:tsize_width-1] 	  s1_size;
   wire [0:uid_width-1] 	  s2_uid;
   base_const#(.width(tsize_width),.value(128)) is1_size(s1_size);

   wire [0:sid_width-1] 	  s1_sid;
   wire 			  s1_f;
   wire 			  s1_rsp_v;
   wire [0:lcl_tag_width-1] 	  s1_rsp_tag;    
   wire [0:sid_width-1] 	  s1_rsp_sid;
   wire [0:rc_width-1] 		  s1_rsp_rc;
   wire 			  s2_req_v, s2_req_r;
   wire [0:lcl_tag_width-1] 	  s2_req_tag;   
   wire [0:sid_width-1] 	  s2_req_sid;
   wire [0:aux_width+ctxtid_width+ea_width+tsize_width-1] s2_req_d;
   wire 						  s2_req_f;
   wire [0:2]         get_retry_s1_perror;
   capi_get_retry#(.tag_width(lcl_tag_width),.sid_width(sid_width),.aux_width(aux_width),.ctxtid_width(ctxtid_width),.ea_width(ea_width),.tsize_width(tsize_width),.rc_width(rc_width),.tstag_width(tstag_width),
		   .ctag_width(ctag_width),.pea_width(pea_width),.cnt_rsp_width(cnt_rsp_width),.is_get(1),
		   .cto_width(cto_width)) irtry
     (.clk(clk),.reset(reset),
      .i_timer_pulse(i_timer_pulse), .i_cont_timeout(i_cont_timeout),
      .i_tstag_inv_v(i_tstag_inv_v),.i_tstag_inv_id(i_tstag_inv_id),
      .i_ctxt_trm_v(i_ctxt_trm_v),.i_ctxt_trm_id(i_ctxt_trm_id),
      .i_cnt_rsp_v(i_cnt_rsp_v),.i_cnt_rsp_d(i_cnt_rsp_d),.o_cnt_rsp_miss(o_cnt_rsp_miss),.o_cnt_pend_d(o_cnt_pend_d),.o_cnt_pend_dropped(o_cnt_pend_dropped),
      .i_req_v(s1b_v),.i_req_r(s1b_r),.i_req_tag(s1_tag),.i_req_sid(s1_sid),.i_req_f(s1_f),.i_req_d({s1_aux,s1_ctxt,s1_ea[0:56],7'b0,s1_ea[57],s1_size}),  
      .o_req_v(s2_req_v),.o_req_r(s2_req_r),.o_req_tag(s2_req_tag),.o_req_sid(s2_req_sid),.o_req_f(s2_req_f),.o_req_d(s2_req_d),
      .i_rsp_v(lcl_rsp_v),.i_rsp_tag(lcl_rsp_tag),.i_rsp_sid(lcl_rsp_sid),.i_rsp_d(lcl_rsp_rc),.i_rsp_tstag(lcl_rsp_tstag),
      .o_rsp_v(s1_rsp_v),.o_rsp_tag(s1_rsp_tag),.o_rsp_d(s1_rsp_rc),.o_rsp_sid(),
      .o_dbg_cnt_inc(o_dbg_cnt_inc),.o_s1_perror(get_retry_s1_perror),.o_perror(o_perror[1]));
   
   base_alatch#(.width(rd_width)) istg2lat(.clk(clk), .reset(reset), .i_d({uid,s2_req_tag,s2_req_sid,s2_req_f,ignore_tstag_inv,s2_req_d}), .i_v(s2_req_v), .i_r(s2_req_r), .o_d(o_req_d), .o_v(o_req_v), .o_r(o_req_r));

   wire [0:6] 			  s1_tag_ea_lsb = s1_s ? {s1_eafst_lsb} : 7'b0;
   wire [0:6] 			  s1_tag_ea_lsb_nxt = s1_e ? s1_ealst_lsb : 7'b0;
   wire [0:1]                     get_data_s1_perror;

   capi_get_data#
     (.tag_width(tag_width),.ea_width(ea_width),.uid_width(uid_width),.uid(uid),.beat_width(beat_width),.rdata_addr_width(rdata_addr_width),.rc_width(rc_width),.bcnt_width(ssize_width),.sid_width(sid_width)) idata
       (.clk(clk),.reset(reset),
	.o_rm_err(o_rm_err),
	.i_disable(i_disable),
	.get_data_v(get_data_v),.get_data_r(get_data_r),.get_data_e(get_data_e),.get_data_c(get_data_c),.get_data_d(get_data_d),.get_data_rc(get_data_rc),.get_data_bcnt(get_data_bcnt),
	.i_rdata_a(i_rdata_a),.i_rdata_v(i_rdata_v),.i_rdata_d(i_rdata_d),
	.o_tag_v(s1a_v[1]),.o_tag_r(s1a_r[1]),.o_tag_d(s1_tag),.o_tag_sd(s1_sid),.o_tag_f(s1_f),.o_tag_e(s1_e),
	.tag_ea_lsb(s1_tag_ea_lsb),.tag_ea_lsb_nxt(s1_tag_ea_lsb_nxt),
	.i_rsp_v(s1_rsp_v),.i_rsp_tag(s1_rsp_tag),.i_rsp_rc(s1_rsp_rc),.o_s1_perror(get_data_s1_perror),.o_perror(o_perror[2]),
        .i_gate_sid(i_gate_sid)

	);	

     assign o_s1_perror = {get_retry_s1_perror,get_data_s1_perror};
//

   
endmodule // capi_get


