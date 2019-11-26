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
module capi_put128_plus #  (
   parameter uid_width = 1,
   parameter uid = 0,
   parameter ea_width = 65,
   parameter ea_width_nopar = ea_width-1,
   parameter ctxtid_width = 9,
   parameter aux_width=1,
   parameter beat_width = 3,
   parameter width_512 = 5,
   parameter tag_width = 1+uid_width,
   parameter tstag_width = 1,
   parameter tsize_width = 8,
   parameter rc_width = 1,
   parameter sid_width=1,
   parameter pea_width=ea_width_nopar-12,
   parameter ctag_width=8,
   parameter cto_width=1,
   parameter cnt_rsp_width = pea_width*2+ctxtid_width+ctag_width+4,
   parameter rsp_width = rc_width + sid_width+tstag_width+tag_width,
   parameter wdata_addr_width = tag_width + width_512,
   parameter rdata_addr_width = tag_width + width_512,
   parameter wr_width = tsize_width+tag_width+sid_width+1+1+aux_width+ctxtid_width+ea_width,
   parameter bcnt_width = 25,
   parameter [0:0] ignore_tstag_inv=0
   )
   (
    input 			 clk,
    input 			 reset,
    input 			 i_ctxt_trm_v,
    input [0:ctxtid_width-1] 	 i_ctxt_trm_id,

    input 			 i_tstag_inv_v,
    input [0:tstag_width-1] 	 i_tstag_inv_id,

    input 			 i_disable,
    input 			 i_timer_pulse,
    input [0:cto_width-1] 	 i_cont_timeout,

    output 			 o_rm_err,
    input 			 put_addr_v, 
    input [0:ea_width-1] 	 put_addr_d_ea,
    input [0:aux_width-1] 	 put_addr_d_aux,
    input [0:ctxtid_width-1] 	 put_addr_d_ctxt,
    output 			 put_addr_r,
   

   /* data comes one cycle after address */
    output 			 put_data_r,
    input 			 put_data_v,
    input 			 put_data_e,
    input [0:3] 		 put_data_c, // count - valid only with _e, zero = 16 
    input [0:129] 		 put_data_d, /* follows put_data_valid etc by one cycle */ // change 127 to 129 kch
    output 			 put_done_v,
    input 			 put_done_r,
    output [0:rc_width-1] 	 put_done_rc,
    output [0:bcnt_width-1] 	 put_done_bcnt, // number of bytes successfully transfered

// temp changes to run co-sim with iput 3/22/17 kch 
//    input 			 put_data_r_temp,

   // gx address interface
    output 			 o_req_v,
    output [0:wr_width-1] 	 o_req_d,    // tag is bits 5:11 local id is 0:4 
    input 			 o_req_r,

   // gx response ack or retry
    input 			 i_rsp_v,
    input [0:rsp_width-1] 	 i_rsp_d,

   // response for continue
    input 			 i_cnt_rsp_v,
    input [0:cnt_rsp_width-1] 	 i_cnt_rsp_d,
    output 			 o_cnt_rsp_miss,
    output [0:63] 		 o_cnt_pend_d,
    output 			 o_cnt_pend_dropped,

   
   // gx data interface
    input 			 i_wdata_req_v,
    input [0:wdata_addr_width-1-3] i_wdata_req_a,   // need to add 2 bits to this kchh  take off bottom, 3 bits cause array is now 128 bytes instead of 16 
    output [0:1023] 		 o_wdata_rsp_d,   //change 127 to 129 kch
    output 			 o_wdata_rsp_v,
    output [0:3] 		 o_dbg_cnt_inc,
    output [0:1]                 o_perror,         // added o_perror kch 
    output [0:2]                 o_s1_perror,
    output                       o_put128_dbg_cnt_inc,
    input                        i_gate_sid
 );

   localparam lcl_tag_width = tag_width - uid_width;
   localparam max_tags = 2 ** lcl_tag_width;

   wire [0:uid_width-1]      lcl_uid;
   base_const#(.width(uid_width),.value(uid)) ilcl_uid(lcl_uid);

   
   wire 		     as1_addr_v, as1_addr_r;
   wire [0:aux_width-1]      as1_addr_d_aux;
   wire [0:ctxtid_width-1]   as1_addr_d_ctxt;
   wire [0:ea_width-1] 	     as1_addr_d_ea;

   wire [0:1] 		     as0_v, as0_r;
   wire s1_put_cmd_v;
   wire                      put_cmd_v;

   wire 		    s0_e;
   base_acombine#(.ni(1),.no(2)) ias0_cmb
     (.i_v(put_addr_v),.i_r(put_addr_r),  // added s0_e see if this works 
      .o_v(as0_v),.o_r(as0_r));
   

   wire [0:4] 		   s1_v, s1_r;
   wire 		   s1_cl_rdy = s1_put_cmd_v ;               // make this for flash_gt plus doesn't work kchh
   assign o_put128_dbg_cnt_inc = ~ s1_r[4];    // fix for new command creation needs to stop data bus  

   base_aburp_latch#(.width(aux_width+ctxtid_width+ea_width)) iinb_addr
     (.clk(clk),.reset(reset),
      .i_v(as0_v[0]),.i_r(as0_r[0]),.i_d({put_addr_d_aux,put_addr_d_ctxt,put_addr_d_ea}),  
      .o_v(as1_addr_v),.o_r(as1_addr_r),.o_d({as1_addr_d_aux,as1_addr_d_ctxt,as1_addr_d_ea})
      );

   wire [0:2] 		    s0_v, s0_r;
   wire [0:129] 	    s0_d;   // changed 127 to 129 kch
   wire [0:3] 		    s0_c;  /* last beat count */
// check and regen parity since bytes may be aligned differently kch 
   wire [0:1]		    so_d_par;		    
   wire [0:3] 				s1_perror;
   capi_parcheck#(.width(ea_width-1)) put_data_d_pcheck0(.clk(clk),.reset(reset),.i_v((put_data_v & ~put_data_e)),.i_d(put_data_d[0:63]),.i_p(put_data_d[128]),.o_error(s1_perror[0]));
   capi_parcheck#(.width(ea_width-1)) put_data_d_pcheck1(.clk(clk),.reset(reset),.i_v((put_data_v & ~put_data_e)),.i_d(put_data_d[64:127]),.i_p(put_data_d[129]),.o_error(s1_perror[1]));
   capi_parity_gen#(.dwidth(64),.width(1)) s0_d_pgen0(.i_d(s0_d[0:63]),.o_d(so_d_par[0]));
   capi_parity_gen#(.dwidth(64),.width(1)) s0_d_pgen1(.i_d(s0_d[64:127]),.o_d(so_d_par[1]));
   assign s0_d[128:129] = so_d_par;
   wire [0:3] 				hld_perror;
   base_vlat_sr#(.width(4)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(4'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror),.q(o_perror[0]));

    wire [0:3]                put_data_align_offset;
    wire [0:ea_width-1]       put_cmd_ea;
    wire [0:9]                put_cmd_tsize;
    wire [0:ea_width-1]       s1_put_cmd_ea;
    wire [0:9]                s1_put_cmd_tsize;

   wire crossing_enable;
   wire s0_crossing_enable;
             wire s1_crossing_enable;
   wire crossing_end;
   wire s1_put_data_e;
   wire 		    s1tag_v, s1tag_r;
   wire [0:4]               s1_put_cmd_tag;   
   wire [0:lcl_tag_width-1] s1_tag;
   wire                     reset_beat_cnt;
   wire [0:sid_width-1]                 s1_put_cmd_sid;
   wire                       s1_put_cmd_f;
   wire [0:10]                s1_put_cmd_addr_aux;
   wire [0:9]                 s1_put_cmd_addr_ctxt;
   wire [0:sid_width-1]     s1_sid;
   wire 		    s1_f;
   wire [0:aux_width-1]    s1_addr_aux;
   wire [0:ctxtid_width-1] s1_addr_ctxt;
   wire       s0_align_data_v;
   wire                     buf_wd_v;

   capi_put128_cmd_enc#(.sid_width(sid_width)) icmdenc12
     (.clk(clk),.reset(reset),
          .i_addr_v(as1_addr_v & as1_addr_r),.i_addr_ea(as1_addr_d_ea),.i_data_c(s0_c),.i_data_v(s0_v[0]),.i_data_r(s0_r[0]),.i_data_e(s0_e),.i_cmd_tag(s1_tag),.i_data_cmd_gen_r(s1_r[4]),.i_cmd_v(s1tag_v),
          .i_sid(s1_sid),.i_f(s1_f),.i_addr_aux(s1_addr_aux),.i_addr_ctxt(s1_addr_ctxt),
          .o_data_align_offset(put_data_align_offset),.o_cmd_addr_ea(s1_put_cmd_ea),.o_cmd_tsize(s1_put_cmd_tsize),.o_cmd_tag(s1_put_cmd_tag),.o_cmd_v(s1_put_cmd_v),.o_cmd_gen_v(s1_put_cmd_gen_v),.o_reset_beat_cnt(reset_beat_cnt),
          .o_s1_crossing_enable(s1_crossing_enable),.o_crossing_end(crossing_end),.o_s1_data_e(s1_put_data_e),
          .o_cmd_sid(s1_put_cmd_sid),.o_cmd_f(s1_put_cmd_f),.o_cmd_addr_aux(s1_put_cmd_addr_aux),.o_cmd_addr_ctxt(s1_put_cmd_addr_ctxt)
      ); 
   
  
   wire put_data_array_space_r;
   wire 		    s2tag_v, s3tag_v;
   wire                     s0_align_burp_v;
   wire                     align_burp_v;
wire put_data_array_space_r_kch;
wire [0:127] s0_d_kch;
wire s0_v_kch,s0_e_kch,s0_align_burp_v_kch,align_burp_v_kch;
wire [0:3] s0_c_kch;
wire       array_we;
wire       s0_array_we;
wire       as0_r_kch;
wire       o_offset_write_cycle;


   capi_put_align_delay_plus ialign_plus_delay
     (.clk(clk),.reset(reset),
      .i_v(put_data_v),.i_r(put_data_r),.i_d(put_data_d[0:127]),.i_c(put_data_c),.i_e(put_data_e),
      .i_a_v(as0_v[1]),.i_a_r(as0_r[1]),.i_a_d(put_data_align_offset),   // added s1_crossing enable for4K and 512 cros
       .o_v(s0_v[0]),.o_r(s0_r[0]),.o_cmd_gen_r(1'b1),.o_d(s0_d[0:127]),.o_c(s0_c),.o_e(s0_e),.o_array_we(array_we),.o_s0_array_we(s0_array_we),.o_offset_write_cycle(offset_write_cycle)
      );

   

   wire [0:ctxtid_width-1] s0_addr_ctxt;
   wire [0:aux_width-1]    s0_addr_aux;
   wire [0:ea_width-1] 	   s0_addr_ea;
   wire [0:ea_width_nopar-8] 	   s0_addr_cl_in;  //nopar kch
   wire [0:6] 		   s0_addr_bt_in;
   wire [0:4] 		   s0_beat_cnt, s0_beat_cnt_in;
   wire 		   s0_last_beat = (s0_beat_cnt == 3'b111);
   
   assign s0_addr_cl_in = s0_last_beat ? s0_addr_ea[0:ea_width_nopar-8]+1 : s0_addr_ea[0:ea_width_nopar-8]; 
   assign s0_addr_bt_in = s0_last_beat ? 7'b0 :                    s0_addr_ea[ea_width_nopar-7:ea_width_nopar-1];
   assign s0_beat_cnt_in  = s0_beat_cnt+3'b1;
   
   capi_parcheck#(.width(ea_width-1)) as1_addr_d_ea_pcheck0(.clk(clk),.reset(reset),.i_v(as1_addr_v),.i_d(as1_addr_d_ea[0:ea_width-2]),.i_p(as1_addr_d_ea[ea_width-1]),.o_error(s1_perror[2]));
   base_vlat#(.width(2)) is2_tag_v(.clk(clk),.reset(reset),.din({s1tag_v,s2tag_v}),.q({s2tag_v,s3tag_v}));
   wire stall_array_write = ~(s2tag_v & ~ s3tag_v);

   base_asml#(.width(aux_width+ctxtid_width+ea_width+2+2)) inbsm 
      (.clk(clk),.reset(reset),
       .ir_v(as1_addr_v), .ir_r(as1_addr_r), .ir_d({as1_addr_d_aux,as1_addr_d_ctxt,as1_addr_d_ea[0:ea_width-2],5'b00000}),
       .if_v(~(s0_e)),.if_d({s0_addr_aux,s0_addr_ctxt,s0_addr_cl_in,s0_addr_bt_in,s0_beat_cnt_in}),   // original
       .o_v(s0_v[1]),.o_r(s0_r[1]), .o_d({s0_addr_aux,s0_addr_ctxt,s0_addr_ea[0:ea_width_nopar-1],s0_beat_cnt})); // add put_data_r to freeze beat count

   capi_parity_gen#(.dwidth(64),.width(1)) s0_addr_ea_pgen(.i_d(s0_addr_ea[0:63]),.o_d(s0_addr_ea[64]));

   base_acombine#(.ni(2),.no(1)) is0_cmb(.i_v(s0_v[0:1]),.i_r(s0_r[0:1]),.o_v(s0_v[2]),.o_r(s0_r[2]));

   wire 		   s1_e;
   wire 		   s1_last_beat;
   wire [0:ea_width-1] 	   s1_addr_ea;
   wire [0:4] 		   s1_beat_cnt;
   wire [0:3] 		   s1_c;
   wire [0:129] 	   s1_d;   // changed 127 to 129
   wire                    s1_offset_write_cycle; 
   
   base_alatch#(.width(1+1+4+aux_width+ctxtid_width+ea_width+5+1)) is1_lat  //changed 128 to 130 kch
     (.clk(clk),.reset(reset),
      .i_v(s0_v[2]),.i_r(s0_r[2]),.i_d({s0_e,s0_last_beat,s0_c,s0_addr_aux,s0_addr_ctxt,s0_addr_ea,s0_beat_cnt,offset_write_cycle}),
      .o_v(s1_v[0]),.o_r(s1_r[0]),.o_d({s1_e,s1_last_beat,s1_c,s1_addr_aux,s1_addr_ctxt,s1_addr_ea,s1_beat_cnt,s1_offset_write_cycle})
      );

   base_alatch#(.width(130)) is1_dat  //changed 128 to 130 kch
     (.clk(clk),.reset(reset),
      .i_v(s0_v[2] | offset_write_cycle),.i_r(),.i_d({s0_d}),
      .o_v(),.o_r(s1_r[0] | offset_write_cycle),.o_d({s1_d})
      );

   capi_parcheck#(.width(ea_width-1)) s1_addr_ea_pcheck2(.clk(clk),.reset(reset),.i_v(s1_v[0]),.i_d(s1_addr_ea[0:ea_width-2]),.i_p(s1_addr_ea[ea_width-1]),.o_error(s1_perror[3]));

   // don't proceed unless this is the end of the stream, or the next beat is valid
   wire 		   s1a_en = s0_v[2] | s1_cl_rdy | s1_put_data_e | s1_crossing_enable;
   base_agate is1a_gt(.i_v(s1_v[0]),.i_r(s1_r[0]),.o_v(s1_v[1]),.o_r(s1_r[1]),.en(s1a_en));

   wire [0:lcl_tag_width-1] lcl_rsp_tag;
   wire [0:rc_width-1] 	    lcl_rsp_rc;
   wire [0:uid_width-1]     lcl_rsp_uid;
   wire [0:sid_width-1]     lcl_rsp_sid;
   wire [0:tstag_width-1]   lcl_rsp_tstag;
   assign {lcl_rsp_rc,lcl_rsp_sid,lcl_rsp_tstag,lcl_rsp_uid,lcl_rsp_tag} = i_rsp_d;
   wire 		    lcl_rsp_v = (lcl_rsp_uid == lcl_uid) & i_rsp_v;

   wire 		    pd0_v, pd0_r, pd0_e;
   wire [0:rc_width-1] 	    pd0_rc;
   wire [0:lcl_tag_width-1] pd0_id;
   wire 		    pd0a_v, pd0a_r;

   // enough for 16M
   
   wire [0:bcnt_width-1]    pd0_bcnt;
   
   wire [0:tsize_width-1]   s1_tsize;
   wire 			  s1_rsp_v;
   wire [0:lcl_tag_width-1] 	  s1_rsp_tag;
   wire [0:sid_width-1] 	  s1_rsp_sid;
   wire [0:rc_width-1] 		  s1_rsp_rc;


   capi_get_bfr_mgr#(.tag_width(lcl_tag_width),.max_tags(max_tags),.rc_width(rc_width),.tsize_width(tsize_width),.bcnt_width(bcnt_width),.sid_width(sid_width)) itagmgr
     (.clk(clk),.reset(reset),
      .o_alloc_v(s1tag_v),.o_alloc_r(s1tag_r),.o_alloc_id(s1_tag),.o_alloc_se(s1_put_data_e | crossing_end),.o_alloc_ae(1'b0),.o_alloc_tsize(12'h000),.o_alloc_sid(s1_sid),.o_alloc_f(s1_f),  /// alway a complete packet with a tag kch 
      .i_wr_v(s1_rsp_v),.i_wr_id(s1_rsp_tag),.i_wr_rc(s1_rsp_rc),
      .o_rd_v(pd0_v),.o_rd_r(pd0_r),.o_rd_id(pd0_id),.o_rd_e(pd0_e),.o_rd_rc(pd0_rc), .o_rd_cnt(pd0_bcnt),
      .i_free_v(pd0_v & pd0_r),.i_free_id(pd0_id), .o_rm_err(o_rm_err),
      .i_gate_sid(i_gate_sid)
      );
   base_afilter ipd_fltr(.i_v(pd0_v),.i_r(pd0_r),.o_v(pd0a_v),.o_r(pd0a_r),.en(pd0_e));

   wire 		    s1_disable;
   base_vlat#(.width(1)) is1_disable(.clk(clk),.reset(reset),.din(i_disable),.q(s1_disable));

   wire 		    pd0b_v, pd0b_r;
   base_agate ipd_gate(.i_v(pd0a_v),.i_r(pd0a_r),.o_v(pd0b_v),.o_r(pd0b_r),.en(~s1_disable));
   base_alatch_burp#(.width(bcnt_width+rc_width)) ipd_lat(.clk(clk),.reset(reset),.i_v(pd0b_v),.i_r(pd0b_r),.i_d({pd0_rc,pd0_bcnt}),.o_v(put_done_v),.o_r(put_done_r),.o_d({put_done_rc,put_done_bcnt}));


   
     wire s1tag_r_unused;
     assign s1tag_r = s1_cl_rdy ;  
   // filter until cl is ready
   wire 		   s1_cl_rdy_old = s1_e || s1_last_beat || (s0_v[2] & s0_e); // flash_gt
   base_arfilter itag_fltr (.en(s1_cl_rdy),.i_v(s1tag_v),.i_r(s1tag_r_unused),.o_v(s1_v[2]),.o_r(s1_r[4]));   // use bit 4 instead of 2

   base_acombine#(.ni(2),.no(1)) is1_cmb
     (.i_v(s1_v[1:2]),.i_r(s1_r[1:2]),
      .o_v(s1_v[3]),.o_r(s1_r[3]));
   wire [0:lcl_tag_width-1] buf_wa;
   wire [0:2]               buf_wa_beat;
   wire 		    buf_we;
   wire [0:129] 	    buf_wd;    // changfed 127 to 129 kch 
   wire [0:lcl_tag_width-1] s2_tag;
   wire [0:lcl_tag_width-1] idbuf_wr_tag;
   wire [0:lcl_tag_width-1] s1_tag_hold;
   wire s2_crossing_enable;
   
   wire [0:4] s2_tag_in = put_data_r ? s1_tag : s2_tag;
   wire [0:4] s1_tag_hold_in = s1_r[4] ? s1_tag : s1_tag_hold;
   base_vlat#(.width(lcl_tag_width)) tag_hold(.clk(clk), .reset(reset), .din(s1_tag_hold_in), .q(s1_tag_hold));  //use hold value when read go inactive
   wire [0:4] s1_tag_or_hold = s1_r[4] ? s1_tag : s1_tag_hold; 
   base_vlat#(.width(lcl_tag_width)) tag_delay(.clk(clk), .reset(reset), .din(s2_tag_in), .q(s2_tag));  // delay tag by 1 cycle for crossing cases 
   base_vlat#(.width(1)) cross_delay(.clk(clk), .reset(reset), .din(s1_crossing_enable), .q(s2_crossing_enable));  


   
   wire s2_put_cmd_v;
   wire s2_put_cmd_v_in = put_data_r ? s1_put_cmd_v : s2_put_cmd_v;
   base_vlat is2_put_cmd(.clk(clk), .reset(reset), .din(s2_put_cmd_v_in), .q(s2_put_cmd_v)); 
     wire hold_beat_cnt = ~(s1_v[0] & s1_r[0] & (~s1_e | offset_write_cycle) );
   wire [0:4] buf_beat_cnt_out;
   wire [0:4] func_beat_cnt = hold_beat_cnt ? buf_beat_cnt_out : buf_beat_cnt_out + 5'b00001;
   wire [0:4] buf_beat_cnt_in = reset_beat_cnt ? 5'b00000 : func_beat_cnt;
   base_vlat#(.width(5)) ibeat_kch(.clk(clk), .reset(reset), .din(buf_beat_cnt_in), .q(buf_beat_cnt_out));

   wire  s2ns1_tag = (reset_beat_cnt & ~(s2_put_cmd_v & put_data_r));   // try this to simplify design hope it works........   offset might have to be non-zero
//   assign  idbuf_wr_tag = s2ns1_tag ? s2_tag : s1_tag;
// ******uncomment out this line when done testing
   assign  idbuf_wr_tag = s2ns1_tag ? s2_tag : s1_tag_or_hold;  // made change cause put_128 had it in . think I missed a change

   base_vlat#(.width(lcl_tag_width+3)) ibwa(.clk(clk), .reset(reset), .din({idbuf_wr_tag,buf_beat_cnt_out[2:4]}), .q({buf_wa,buf_wa_beat}));
// fix for timing 
   wire [0:lcl_tag_width-1] s1_buf_wa;
   wire [0:2]               s1_buf_wa_beat;
   
   base_vlat#(.width(lcl_tag_width+3)) is1bwa(.clk(clk), .reset(reset), .din({buf_wa,buf_wa_beat}), .q({s1_buf_wa,s1_buf_wa_beat}));
   wire [0:127] s1_data;
   base_vlat#(.width(128)) idat1(.clk(clk),.reset(1'b0),.din(s0_d[0:127]),.q(s1_data[0:127]));  // change 128 to 130 kch
   base_vlat#(.width(128)) ibwd(.clk(clk),.reset(1'b0),.din(s1_d[0:127]),.q(buf_wd[0:127]));  // change 128 to 130 kch
   
   // discard end beat 
   wire 		    s1_en4 = s1_cl_rdy ;  // get rid of ~s1_e to fix
   base_afilter is0fltr (.en(1'b1), .i_v(s1_v[3]), .i_r(s1_r[3]), .o_v(s1_v[4]), .o_r(s1_r[4]));

   
   // determine a tsize based on the beat count 

   wire 			  s2_req_v, s2_req_r;
   wire [0:lcl_tag_width-1] 	  s2_req_tag;
   wire [0:sid_width-1] 	  s2_req_sid;
   wire [0:aux_width+ctxtid_width+ea_width+tsize_width-1] s2_req_d;
   wire 						    s2_req_f;
   wire [0:aux_width-1]    s2_addr_aux;
   wire [0:ctxtid_width-1] s2_addr_ctxt;
   wire [0:ea_width-1] 	   s2_addr_ea;
   wire [0:tsize_width-1]   s2_tsize;

   

   capi_get_retry#(.tag_width(lcl_tag_width),.sid_width(sid_width),.aux_width(aux_width),.ctxtid_width(ctxtid_width),.ea_width(ea_width),.tsize_width(tsize_width),.rc_width(rc_width),.tstag_width(tstag_width),
         	   .ctag_width(ctag_width),.pea_width(pea_width),.cnt_rsp_width(cnt_rsp_width),.is_get(0),
		   .cto_width(cto_width)) irtry
     (.clk(clk),.reset(reset),
      .i_ctxt_trm_v(i_ctxt_trm_v),.i_ctxt_trm_id(i_ctxt_trm_id),
      .i_tstag_inv_v(i_tstag_inv_v),.i_tstag_inv_id(i_tstag_inv_id),
      .i_timer_pulse(i_timer_pulse), .i_cont_timeout(i_cont_timeout),
      .i_cnt_rsp_v(i_cnt_rsp_v),.i_cnt_rsp_d(i_cnt_rsp_d),.o_cnt_rsp_miss(o_cnt_rsp_miss),.o_cnt_pend_d(o_cnt_pend_d),.o_cnt_pend_dropped(o_cnt_pend_dropped),
      .i_req_v(s1_put_cmd_gen_v),.i_req_r(s1_r[4]),.i_req_tag(s1_put_cmd_tag),.i_req_sid(s1_put_cmd_sid),.i_req_f(s1_put_cmd_f),.i_req_d({s1_put_cmd_addr_aux,s1_put_cmd_addr_ctxt,s1_put_cmd_ea,2'b00,s1_put_cmd_tsize}),  // was s1_v[4]
      .o_req_v(s2_req_v),.o_req_r(s2_req_r),.o_req_tag(s2_req_tag),.o_req_sid(s2_req_sid),.o_req_f(s2_req_f),.o_req_d(s2_req_d),
      .i_rsp_v(lcl_rsp_v),.i_rsp_tag(lcl_rsp_tag),.i_rsp_sid(lcl_rsp_sid),.i_rsp_d(lcl_rsp_rc),.i_rsp_tstag(lcl_rsp_tstag),
      .o_rsp_v(s1_rsp_v),.o_rsp_tag(s1_rsp_tag),.o_rsp_d(s1_rsp_rc),.o_rsp_sid(),
      .o_dbg_cnt_inc(o_dbg_cnt_inc),.o_s1_perror(o_s1_perror),.o_perror(o_perror[1])
);

   assign {s2_addr_aux,s2_addr_ctxt,s2_addr_ea,s2_tsize} = s2_req_d;

   // latch final transaction for capi request
   base_aburp_latch#(.width(tag_width +sid_width+1+1+aux_width+ctxtid_width+ea_width+tsize_width)) is2_lat
     (.clk(clk), .reset(reset),
      .i_r(s2_req_r),.i_v(s2_req_v), .i_d({lcl_uid,s2_req_tag,s2_req_sid,s2_req_f,ignore_tstag_inv,s2_req_d}), 
      .o_v(o_req_v), .o_d(o_req_d),.o_r(o_req_r));

   // fetch data   
   wire [0:uid_width-1] 	lcl_data_req_uid;
   wire [0:lcl_tag_width-1] 	lcl_data_req_tag;
   wire [0:width_512-1-3] 	lcl_data_req_beat;
   assign {lcl_data_req_uid,lcl_data_req_tag,lcl_data_req_beat} = i_wdata_req_a;
   
   wire 		    lcl_data_req_v = i_wdata_req_v & (lcl_data_req_uid == uid);

   wire [0:7]               buf_we_slice;
   wire                     put_tsize_align16 = (s1_put_cmd_tsize[6:9] == 4'h0);
   base_vlat#(.width(1)) iwed(.clk(clk),.reset(1'b0),.din((s1_v[0] & s1_r[0] & ~(s1_e)) | offset_write_cycle),.q(buf_wd_v));
//fix for timing 
   wire s1_buf_wd_v; 
   base_vlat#(.width(1)) is1wed(.clk(clk),.reset(1'b0),.din(buf_wd_v),.q(s1_buf_wd_v));

   base_decode#(.enc_width(3),.dec_width(8)) ibuf_dec
     (.en(s1_buf_wd_v),.din(s1_buf_wa_beat),.dout(buf_we_slice));



// increase meem by 4X deeper. 128 tags each can hold 512 bytes 
 
   base_mem#(.width(128), .addr_width(lcl_tag_width)) idbuf0(.clk(clk), .we(buf_we_slice[0]), .wa(s1_buf_wa), .wd(buf_wd[0:127]),  .re(lcl_data_req_v), .ra({lcl_data_req_tag}), .rd(o_wdata_rsp_d[0:127])); 
   base_mem#(.width(128), .addr_width(lcl_tag_width)) idbuf1(.clk(clk), .we(buf_we_slice[1]), .wa(s1_buf_wa), .wd(buf_wd[0:127]),  .re(lcl_data_req_v), .ra({lcl_data_req_tag}), .rd(o_wdata_rsp_d[128:255])); 
   base_mem#(.width(128), .addr_width(lcl_tag_width)) idbuf2(.clk(clk), .we(buf_we_slice[2]), .wa(s1_buf_wa), .wd(buf_wd[0:127]),  .re(lcl_data_req_v), .ra({lcl_data_req_tag}), .rd(o_wdata_rsp_d[256:383])); 
   base_mem#(.width(128), .addr_width(lcl_tag_width)) idbuf3(.clk(clk), .we(buf_we_slice[3]), .wa(s1_buf_wa), .wd(buf_wd[0:127]),  .re(lcl_data_req_v), .ra({lcl_data_req_tag}), .rd(o_wdata_rsp_d[384:511])); 
   base_mem#(.width(128), .addr_width(lcl_tag_width)) idbuf4(.clk(clk), .we(buf_we_slice[4]), .wa(s1_buf_wa), .wd(buf_wd[0:127]),  .re(lcl_data_req_v), .ra({lcl_data_req_tag}), .rd(o_wdata_rsp_d[512:639])); 
   base_mem#(.width(128), .addr_width(lcl_tag_width)) idbuf5(.clk(clk), .we(buf_we_slice[5]), .wa(s1_buf_wa), .wd(buf_wd[0:127]),  .re(lcl_data_req_v), .ra({lcl_data_req_tag}), .rd(o_wdata_rsp_d[640:767])); 
   base_mem#(.width(128), .addr_width(lcl_tag_width)) idbuf6(.clk(clk), .we(buf_we_slice[6]), .wa(s1_buf_wa), .wd(buf_wd[0:127]),  .re(lcl_data_req_v), .ra({lcl_data_req_tag}), .rd(o_wdata_rsp_d[768:895])); 
   base_mem#(.width(128), .addr_width(lcl_tag_width)) idbuf7(.clk(clk), .we(buf_we_slice[7]), .wa(s1_buf_wa), .wd(buf_wd[0:127]),  .re(lcl_data_req_v), .ra({lcl_data_req_tag}), .rd(o_wdata_rsp_d[896:1023])); 

   assign o_wdata_rsp_v = lcl_data_req_v;

endmodule



