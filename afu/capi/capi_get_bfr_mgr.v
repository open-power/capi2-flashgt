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
module capi_get_bfr_mgr#
  (
   parameter tsize_width=1,
   parameter bcnt_width=1,
   parameter max_tags = 12,
   parameter tag_width = 4,
   parameter sid_width = 3,
   parameter rc_width=1
   )
   (
    input 		    clk,
    input 		    reset,
    
    // allocate a buffer 
    input 		    o_alloc_se, // synchronous end: must get write to this tag complete
    input 		    o_alloc_ae, // asynchronous end: write is implied
    input [0:tsize_width-1] o_alloc_tsize,
    input 		    o_alloc_r,
    output 		    o_alloc_v,
    output [0:tag_width-1]  o_alloc_id,
    output [0:sid_width-1]  o_alloc_sid,
    output 		    o_alloc_f,
    
    // complete - data has been written back to the buffer. this stream comes out-of-order
    input 		    i_wr_v,
    input [0:tag_width-1]   i_wr_id,
    input [0:rc_width-1]    i_wr_rc,

    // in-order stream of completed buffers
    input 		    o_rd_r,
    output 		    o_rd_v,
    output [0:tag_width-1]  o_rd_id,
    output [0:rc_width-1]   o_rd_rc,
    output [0:bcnt_width-1] o_rd_cnt, // number of bytes transferred 
    output 		    o_rd_e,

    // free - done in order vs data which may be written out of order 
    input 		    i_free_v,
    input [0:tag_width-1]   i_free_id,

    output 		    o_rm_err,
    input                   i_gate_sid
    );

   wire 		    sid_free_v = o_rd_v & o_rd_r & o_rd_e;
   wire 		    a1b_v, a1b_r;

      
   capi_seq_res_mgr#(.id_width(sid_width),.tag_check(0)) ismgr
     (.clk(clk),.reset(reset),
      .o_avail_v(a1b_v),.o_avail_r(a1b_r),.o_avail_id(o_alloc_sid),
      .i_free_v(sid_free_v),.i_free_id(),.o_free_err()
      );

   wire temp_a1b_v = a1b_v | i_gate_sid;
   wire 		    a1_e = o_alloc_se | o_alloc_ae;
   wire 		    a1c_v, a1c_r;
//   base_arfilter ia1_fltr(.i_v(a1b_v),.i_r(a1b_r),.o_v(a1c_v),.o_r(a1c_r),.en(a1_e));
   base_arfilter ia1_fltr(.i_v(temp_a1b_v),.i_r(a1b_r),.o_v(a1c_v),.o_r(a1c_r),.en(a1_e));

   
   wire 		    a1_en = o_alloc_v & o_alloc_r;
   base_vlat_en#(.width(1),.rstv(1'b1)) ialloc_f_lat(.clk(clk),.reset(reset),.din(a1_e),.q(o_alloc_f),.enable(a1_en));
   
   wire 		    a1a_v, a1a_r;
   capi_seq_res_mgr#(.id_width(tag_width),.num_res(max_tags)) irmgr
     (.clk(clk),.reset(reset),
      .o_avail_v(a1a_v),.o_avail_id(o_alloc_id),.o_avail_r(a1a_r),
      .i_free_v(i_free_v),.i_free_id(i_free_id),.o_free_err(o_rm_err));

   base_acombine#(.ni(2),.no(1)) ia1_cmb(.i_v({a1a_v, a1c_v}),.i_r({a1a_r,a1c_r}),.o_v(o_alloc_v),.o_r(o_alloc_r));
   
   wire  		   s1a_v, s1a_r;
   wire [0:tag_width-1]    s1_id;
   wire  		   s1_se;
   wire  		   s1_ae;
   wire [0:tsize_width-1]   s1_tsize;
   base_fifo#(.width(tsize_width+2+tag_width),.LOG_DEPTH(tag_width)) ififo
     (.clk(clk),.reset(reset),
      .i_v(o_alloc_v & o_alloc_r),.i_r(),.i_d({o_alloc_tsize,o_alloc_se,o_alloc_ae,o_alloc_id}),
      .o_v(s1a_v),.o_r(s1a_r),.o_d({s1_tsize,s1_se,s1_ae,s1_id})
      );

   // tricky code to continuously ready vmem and allow a transactio out when it is set (its write is done)
   wire [0:1] 		   s1b_v, s1b_r;
   base_acombine#(.ni(1),.no(2)) is1_cmb(.i_v(s1a_v),.i_r(s1a_r),.o_v(s1b_v[0:1]),.o_r(s1b_r[0:1]));
   wire [0:1] 		   s2a_v, s2a_r;
   wire  		   s2b_v, s2b_r;
   wire [0:tag_width-1]    s2_addr;
   wire  		   s2_se;
      wire  		   s2_ae;
   wire [0:tag_width-1]    s2_id;
   wire [0:tsize_width-1]   s2_tsize;
   
   base_aburp#(.width(tag_width))         is1_brp(.clk(clk),.reset(reset),.i_v(s1b_v[0]),.i_r(s1b_r[0]),.i_d(s1_id),       .o_v(s2a_v[0]),.o_r(s2a_r[0]),.o_d(s2_addr),.burp_v());
   base_aburp_latch#(.width(tsize_width+2+tag_width)) is1_lat(.clk(clk),.reset(reset),.i_v(s1b_v[1]),.i_r(s1b_r[1]),.i_d({s1_tsize,s1_se,s1_ae,s1_id}),.o_v(s2a_v[1]),.o_r(s2a_r[1]),.o_d({s2_tsize,s2_se,s2_ae,s2_id}));
   base_acombine#(.ni(2),.no(1)) is2_cmb(.i_v(s2a_v[0:1]),.i_r(s2a_r[0:1]),.o_v(s2b_v),.o_r(s2b_r));

   wire 		   s2_rd_v;
   base_vmem#(.a_width(tag_width)) ivmem
     (.clk(clk),.reset(reset),
      .i_set_v(i_wr_v),.i_set_a(i_wr_id),
      .i_rst_v(o_alloc_v),.i_rst_a(o_alloc_id),
      .i_rd_a(s2_addr),.i_rd_en(1'b1),.o_rd_d(s2_rd_v)
      );

   wire [0:rc_width-1] 	   s2_rd_rc;
   base_mem#(.addr_width(tag_width),.width(rc_width)) ircmem
     (.clk(clk),
      .wa(i_wr_id),.we(i_wr_v),.wd(i_wr_rc),
      .ra(s2_addr),.re(1'b1),.rd(s2_rd_rc)
      );

   wire 		   s2_gt = s2_rd_v | s2_ae;
   wire 		   s2c_v, s2c_r;
   base_agate is2_gt(.i_v(s2b_v),.i_r(s2b_r),.o_v(s2c_v),.o_r(s2c_r),.en(s2_gt));
   wire 		   s2_e = s2_se | s2_ae;

   wire 		   s3_v, s3_r;
   wire [0:tag_width-1]    s3_id;
   wire 		   s3_e;
   wire [0:tsize_width-1]   s3_tsize;
   base_alatch#(.width(tsize_width+tag_width+1)) is3_lat(.clk(clk),.reset(reset),.i_v(s2c_v),.i_r(s2c_r),.i_d({s2_tsize,s2_id,s2_e}),.o_v(s3_v),.o_r(s3_r),.o_d({s3_tsize,s3_id,s3_e}));


   wire [0:rc_width-1] 	   s2_rc = (s2c_v & s2_rd_v) ? s2_rd_rc : {rc_width {1'b0}};
   wire 		   s2_err = s2c_v & (| s2_rd_rc);
   
   wire 		   s3_en = ~s3_v | s3_r;
   wire 		   s3_err;
   wire 		   s3_err_in = s2_err | (s3_err & ~ (s3_v & s3_e));
   
   wire [0:rc_width-1] 	   s3_rc;
   wire 		   s3_rc_hold = s3_err & ~(s3_e & s3_v);
   wire 		   s3_rc_en = s3_en & ~s3_rc_hold;
   base_vlat_en#(.width(1))         is3_err_lat(.clk(clk),.reset(reset),.din(s3_err_in),.q(s3_err),.enable(s3_en));
   base_vlat_en#(.width(rc_width))  is3_rc_lat(.clk(clk),.reset(reset),.din(s2_rc),.q(s3_rc),.enable(s3_rc_en));

   // count number of bytes transfered
   wire [0:bcnt_width-1]   s3_cnt;
   wire [0:bcnt_width-1]   s3_cnt_in = s3_e ? {bcnt_width{1'b0}} : 
			               s3_err ? s3_cnt : (s3_cnt+s3_tsize);
   base_vlat_en#(.width(bcnt_width)) is3_bcnt(.clk(clk),.reset(reset),.din(s3_cnt_in),.q(s3_cnt),.enable(s3_v & s3_r));
   
   assign s3_r = o_rd_r;
   assign o_rd_cnt = s3_cnt;
   assign o_rd_v = s3_v;
   assign o_rd_id = s3_id;
   assign o_rd_rc = s3_rc;
   assign o_rd_e = s3_e;
   
endmodule
   
   
   
    
   
   
