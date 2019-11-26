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
module capi_get_data_plus#
  (
   parameter tag_width  = 5,
   parameter beat_width = 3,
   parameter beat_512_width = 5,
   parameter ea_width = 64,
   parameter rdata_addr_width = 1,
   parameter uid_width = 1,
   parameter uid = 0,
   parameter rc_width=1,
   parameter lcl_tag_width = tag_width - uid_width,
   parameter sid_width=3,
   parameter bcnt_width=1
   )

   (
    input 			 clk,
    input 			 reset,
    input 			 i_disable,
    output 			 get_data_v,
    input 			 get_data_r, //  valid same cycle as get_data_valid
    output 			 get_data_e, // aligned with get_data_valid
    output [0:3] 		 get_data_c, // which byte ends the packet 
    output [0:129] 		 get_data_d, // follows get_data_valid by one cycle changed 127 to 129 to add parity kch
    output [0:rc_width-1] 	 get_data_rc,
    output [0:bcnt_width-1] 	 get_data_bcnt,

    /* gx data interface */
    input 			 i_rdata_v, 
    input [0:rdata_addr_width-1] i_rdata_a,
    input [0:129] 		 i_rdata_d,    // changed from 127 to 129 to add parity kch 

    /* capi response */
    input 			 i_rsp_v,
    input [0:lcl_tag_width-1] 	 i_rsp_tag,   
    input [0:rc_width-1] 	 i_rsp_rc,

    /* from tag manager */
    output 			 o_tag_v,
    input 			 o_tag_r,
    output [0:lcl_tag_width-1] 	 o_tag_d,   
    output [0:sid_width-1] 	 o_tag_sd,
    output 			 o_tag_f, // this is the first tag in this stream
    input 			 o_tag_e, // this will be the last tag in the stream

    input [0:8] 		 tag_ea_lsb,
    input [0:8] 		 tag_ea_lsb_nxt,


    output 			 o_rm_err,
    output [0:1]                 o_s1_perror,
    output                       o_perror,
    input                        i_gate_sid

    );


   localparam max_tags = 2**lcl_tag_width;


   wire  		       us0_v;
   wire  		       us0_r;
   wire 		       us0_e_sync;
   wire [0:lcl_tag_width-1]    us0_tag;  
   wire [0:rc_width-1] 	       us0_rc;
   wire [0:bcnt_width-1]       us0_bcnt;
   
   


   wire 		       us1_v, us1_r,us1_act /* synthesis keep = 1 */ ;        /* valid, end, ready */
   wire 		       tag_act = o_tag_r & o_tag_v;
   
   wire [0:lcl_tag_width-1]    lst_tag;
   base_vlat_en#(.width(lcl_tag_width)) ilsttag(.clk(clk),.reset(reset),.enable(tag_act),.din(o_tag_d),.q(lst_tag));
   
   
   wire [0:8] 		       us1_ea_lsb, us1_ea_lsb_nxt;
   wire 		       us0_act = us1_r | ~us1_v;
   base_mem#(.width(18),.addr_width(lcl_tag_width)) itagmem
     (
      .clk(clk),
      .we(tag_act),.wa(o_tag_d),.wd({tag_ea_lsb,tag_ea_lsb_nxt}),   
      .re(us0_act),.ra(us0_tag),.rd({us1_ea_lsb,us1_ea_lsb_nxt})   
      );

   wire [0:8] 		       us1_ea_lsb_end = us1_ea_lsb_nxt-9'd1;

   wire 		       us1_e_sync;
   wire [0:4] 		       us1_beat_ed = us1_ea_lsb_end[0:4];
   wire [0:3] 		       us1_byte_ed = us1_ea_lsb_nxt[5:8];
   wire [0:lcl_tag_width-1]    us1_tag;
   wire [0:rc_width-1] 	       us1_rc;
   

   base_alatch#(.width(rc_width+1+lcl_tag_width)) ius1_lat 
     (.clk(clk),.reset(reset),
      .i_d({us0_rc,us0_e_sync,us0_tag}),.i_v(us0_v),.i_r(us0_r),
      .o_d({us1_rc,us1_e_sync,us1_tag}),.o_v(us1_v),.o_r(us1_r)
      );
   
   wire 		       us1_f;
   base_afirst ius1_first(.clk(clk),.reset(reset),.i_v(us1_v),.i_r(us1_r),.i_e(us1_e_sync),.o_first(us1_f));


   wire 		       us2_v, us2_r;
   wire 		       us2_e_sync;

   // hang on to the first non-zero return value.
   wire [0:rc_width-1] 	       us2_rc;
   wire 		       us1_en = us2_r | ~us2_v;
   wire 		       us2_rc_hold = us2_v & (| us2_rc) & ~us2_e_sync;
   wire 		       us1_rc_en = us1_en & ~us2_rc_hold;
   base_vlat_en#(.width(rc_width)) ius2_rc_lat(.clk(clk),.reset(reset),.din(us1_rc),.q(us2_rc),.enable(us1_rc_en));
   
   wire [0:8] 		       us2_ea_lsb;
   wire [0:4] 		       us2_beat_ed;
   wire [0:3] 		       us2_byte_ed;
   wire [0:lcl_tag_width-1]    us2_tag;

   base_alatch#(.width(1+lcl_tag_width+9+5+4)) is1lat
     (.clk(clk),.reset(reset),
      .i_v(us1_v),.i_r(us1_r),.i_d({us1_e_sync,us1_tag,us1_ea_lsb,us1_beat_ed,us1_byte_ed}),
      .o_v(us2_v),.o_r(us2_r),.o_d({us2_e_sync,us2_tag,us2_ea_lsb,us2_beat_ed,us2_byte_ed})
      );

   wire [0:4] 		       us2_beat_st = us2_ea_lsb[0:4];
   wire [0:3] 		       us2_byte_st = us2_ea_lsb[5:8];

   wire 		       us3_v, us3_r;
   wire [0:4] 		       us3_d_beat;
   wire [0:3] 		       us3_byte_st, us3_byte_ed;

   wire 		       us3_d_s;
   wire 		       us3_d_e;
   wire [0:lcl_tag_width-1]    us3_tag;
   wire [0:rc_width-1] 	       us3_rc;
   wire 		       us3_e_sync;

   /* tracking return code.  Need to know which is the first tag */
   
   capi_unroll#(.width(rc_width+lcl_tag_width+1+4+4), .cwidth(5)) ixfr_sm
     (
      .clk(clk), .reset(reset),
      .dinv(us2_v),    .cstart(us2_beat_st), .din({us2_rc,us2_tag,us2_e_sync,us2_byte_st,us2_byte_ed}), .cend(us2_beat_ed), .din_acc(us2_r),
      .doutv(us3_v),   .cout  (us3_d_beat), .dout({us3_rc,us3_tag,us3_e_sync,     us3_byte_st,us3_byte_ed}), .dout_st(us3_d_s), .dout_ed(us3_d_e), .dout_acc(us3_r));

   wire [0:3] us3_s = us3_d_s ? us3_byte_st : 4'b0;
   wire [0:3] us3_c = us3_d_e ? us3_byte_ed : 4'b0;
   wire       us3_free_act = us3_v & us3_r & us3_d_e;

   wire [0:beat_512_width-1]    lcl_data_addr_beat;   
   wire [0:lcl_tag_width-1] lcl_data_addr_tag;   
   wire [0:uid_width-1]     lcl_data_addr_uid;


  

   assign {lcl_data_addr_uid,lcl_data_addr_tag,lcl_data_addr_beat} = i_rdata_a;   //lcl_data_addr_tag  
   wire 		    lcl_data_v = i_rdata_v & (lcl_data_addr_uid == uid);

   /*  Data Buffer */
   wire [0:lcl_tag_width+beat_512_width-1]     wa_d;
   wire 				   we_d;
 //  wire [0:127] 	us2d_data;  // commented out. not used kch 
// added pipeline for timing kch 
   wire [0:lcl_tag_width+beat_512_width-1]     wa_d1;
   wire 				   we_d1;
   wire [0:129]                            wd_d1;

   

   
   base_vlat#(.width(1)) iwe(.clk(clk), .reset(reset), .din(lcl_data_v), .q(we_d));
   base_vlat#(.width(lcl_tag_width+beat_512_width)) iwa(.clk(clk), .reset(reset), .din({lcl_data_addr_tag,lcl_data_addr_beat}), .q(wa_d));
// added pipeline for timing kch 
   base_vlat#(.width(1)) iwed(.clk(clk), .reset(reset), .din(we_d), .q(we_d1));
   base_vlat#(.width(lcl_tag_width+beat_512_width)) iwad(.clk(clk), .reset(reset), .din(wa_d), .q(wa_d1));
   base_vlat#(.width(130)) iwdd(.clk(clk), .reset(reset), .din(i_rdata_d), .q(wd_d1));

   wire 		us4_r, us4_v;
   wire [0:129] 	us4_data_d;  // changed from 127 to 129 for parity kch
   base_mem#(.width(130), .addr_width(lcl_tag_width+beat_512_width)) idbuf(.clk(clk), .we(we_d1), .wa(wa_d1), .wd(wd_d1),  .re(us4_r| ~us4_v), .ra({us3_tag,us3_d_beat}), .rd(us4_data_d));

   // end on last beat of last tag
   wire 		us3_e = us3_e_sync & us3_d_e;
   wire 		us4_err;
   wire [0:rc_width-1] 	us4_rc;
   wire 		us4_e;
   wire [0:3] 		us4_c, us4_s;
   wire 		us3_badrc = |us3_rc;

   wire us3a_v, us3a_r;
   wire s1_disable;
   base_vlat#(.width(1)) is1_disable(.clk(clk),.reset(reset),.din(i_disable),.q(s1_disable));
   base_agate ius3_gt(.i_v(us3_v),.i_r(us3_r),.o_v(us3a_v),.o_r(us3a_r),.en(~s1_disable));
   
      /* Latch data outputs */
   base_alatch#(.width(1+rc_width+9)) ius1c(.clk(clk), .reset(reset), .i_v(us3a_v), .i_d({us3_badrc,us3_rc,us3_e,us3_s,us3_c}), .i_r(us3a_r), .o_v(us4_v), .o_d({us4_err,us4_rc,us4_e,us4_s,us4_c}),.o_r(us4_r));

//   wire [0:127] us4_d =  us4_err ? (128'd0):us4_data_d;  // changed from 127 to 129 added chaged 2'd1 to 2'b11 to fix false parity detect 11/4/16 kch  
   wire [0:129] us4_d =  us4_err ? ({128'd0,2'b11}):us4_data_d;  // changed from 127 to 129 added chaged 2'd1 to 2'b11 to fix false parity detect 11/4/16 kch  

      /* pipeline for timing */
   wire 		us5_r, us5_v;
   wire [0:129] 	us5_d;  // changed from 127 to 129 for parity kch
   wire 		us5_err;
   wire [0:rc_width-1] 	us5_rc;
   wire 		us5_e;
   wire [0:3] 		us5_c, us5_s;
   base_alatch#(.width(1+rc_width+9+130)) ius2c(.clk(clk), .reset(reset), .i_v(us4_v), .i_d({us4_err,us4_rc,us4_e,us4_s,us4_c,us4_d}), .i_r(us4_r), .o_v(us5_v), .o_d({us5_err,us5_rc,us5_e,us5_s,us5_c,us5_d}),.o_r(us5_r));


   capi_get_align_plus#(.rc_width(rc_width),.bcnt_width(bcnt_width)) ialign    
     (
      .clk(clk),.reset(reset),
      .i_v(us5_v),.i_r(us5_r),.i_rc(us5_rc),.i_e(us5_e),.i_s(us5_s),.i_c(us5_c),.i_d(us5_d),
      .o_v(get_data_v),.o_r(get_data_r),.o_d(get_data_d),.o_e(get_data_e),.o_c(get_data_c),.o_rc(get_data_rc),.o_bcnt(get_data_bcnt),.o_s1_perror(o_s1_perror),.o_perror(o_perror)
      );

   wire 		    us4_free_act;
   wire [0:lcl_tag_width-1] us4_tag;
   base_vlat#(.width(lcl_tag_width+1)) ius3tag(.clk(clk),.reset(reset),.din({us3_free_act,us3_tag}),.q({us4_free_act,us4_tag}));

   
   capi_get_bfr_mgr#(.max_tags(max_tags), .tag_width(lcl_tag_width),.rc_width(rc_width),.sid_width(sid_width)) 
   ibfr_mgr(.clk(clk), .reset(reset), 
	    .o_alloc_v(o_tag_v), .o_alloc_id(o_tag_d), .o_alloc_r(o_tag_r),.o_alloc_se(o_tag_e),.o_alloc_ae(1'b0),.o_alloc_tsize(),       // output: allocate a buffer
	    .o_alloc_sid(o_tag_sd),.o_alloc_f(o_tag_f),
	    .i_wr_v(i_rsp_v), .i_wr_id(i_rsp_tag), .i_wr_rc(i_rsp_rc),                               // input:  write data into the buffer
	    .o_rd_v(us0_v),.o_rd_id(us0_tag), .o_rd_rc(us0_rc), .o_rd_e(us0_e_sync), .o_rd_r(us0_r),.o_rd_cnt(),                  // output: read data out of the  buffer
	    .i_free_v(us4_free_act), .i_free_id(us4_tag), .o_rm_err(o_rm_err) ,                                  // input:  free the buffer
            .i_gate_sid(i_gate_sid)
	    );

endmodule // capi_get_data

		     
