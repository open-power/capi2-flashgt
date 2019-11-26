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
module ktms_afu_rrq#
  (
   parameter mmioaddr = 0,
   parameter mmiobus_width = 0,
   parameter ea_width = 64,
   parameter ctxtid_width = 9,
   parameter rrq_st_addr = 0,
   parameter rrq_ed_addr = 0,
   parameter aux_width = 0,
   parameter sintrid_width=4,
   parameter dma_rc_width=0,
   parameter afu_rc_width = 0,
   parameter tstag_width = 0,
   parameter [0:dma_rc_width-1] psl_rsp_paged = 0,
   parameter [0:dma_rc_width-1] psl_rsp_addr = 0,
   parameter [0:dma_rc_width-1] psl_rsp_cinv = 0,
   parameter [0:sintrid_width-1] sintr_paged=0,
   parameter [0:sintrid_width-1] sintr_rrq=0
   )
  (input clk,
   input 		      reset,

   input 		      i_errinj_rrq_fault,
   input 		      i_errinj_rrq_paged,
   input 		      i_rtry_cfg,
   
   // rrq start and end from context regs
   input 		      i_rrq_st_we,
   input 		      i_rrq_ed_we,
   input [0:ctxtid_width-1]   i_rrq_ctxt,     //parity check in ktms_afu_int kch 
   input [0:64] 	      i_rrq_wd,  // added parity kch 
		      
   output 		      i_rsp_r,
   input 		      i_rsp_v,
   input [0:ctxtid_width-1]   i_rsp_ctxt,
   input 		      i_rsp_ec,
   input 		      i_rsp_nocmpl,
   input [0:64] 	      i_rsp_d,
   input [0:sintrid_width-1]  i_rsp_sintr_id,
   input 		      i_rsp_sintr_v,
   input [0:tstag_width-1]    i_rsp_tstag,
   input [0:aux_width-1]      i_rsp_aux,

   output 		      o_rsp_v,
   input 		      o_rsp_r,
   output 		      o_rsp_nocmpl,
   output [0:aux_width-1]     o_rsp_aux,
   output 		      o_rsp_sintr_v,
   output [0:sintrid_width-1] o_rsp_sintr_id,
   
   input 		      o_put_addr_r,
   output 		      o_put_addr_v,
   output [0:tstag_width-1]   o_put_addr_tstag,
   output [0:ea_width-1]      o_put_addr_ea,
   output [0:ctxtid_width-1]  o_put_addr_ctxt,

   input 		      o_put_data_r,
   output 		      o_put_data_v,
   output [0:129] 	      o_put_data_d,
   output [0:3] 	      o_put_data_c,
   output 		      o_put_data_f,
   output 		      o_put_data_e,

   input 		      i_put_done_v,
   output 		      i_put_done_r,
   input [0:dma_rc_width-1]   i_put_done_rc,
   output [8:0] 	      o_pipemon_v,
   output [8:0] 	      o_pipemon_r,
   output 		      o_dbg_cnt_inc,

   input [0:mmiobus_width-1]  i_mmiobus,
   output 		      o_mmio_ack,
   output [0:63] 	      o_mmio_data,
   output                     o_perror

   );

     
   wire 		      s1a_r, s1a_v;
   wire [0:ctxtid_width-1]    s1_ctxt;
   wire [0:64] 		      s1_d;
   wire 		      s1_sintr_v;
   wire [0:sintrid_width-1]   s1_sintr_id;
   wire [0:tstag_width-1]     s1_tstag;
   wire [0:aux_width-1]       s1_aux;
   wire 		      s1_ec;
   wire 		      s1_nocmpl;

   wire [0:8]                 s1_perror;
   capi_parcheck#(.width(ctxtid_width-1)) i_rsp_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(i_rsp_v),.i_d(i_rsp_ctxt[0:ctxtid_width-2]),.i_p(i_rsp_ctxt[ctxtid_width-1]),.o_error(s1_perror[0]));
   wire [0:8] 		      hld_perror;
   base_vlat_sr#(.width(9)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(9'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror),.q(o_perror));


   base_amem_rd_fltr#(.awidth(ctxtid_width),.dwidth(1+1+65+1+sintrid_width+tstag_width+aux_width)) is1_lat
     (.clk(clk),.reset(reset),
      .i_v(i_rsp_v),.i_r(i_rsp_r),.i_a(i_rsp_ctxt),.i_d({i_rsp_ec,i_rsp_nocmpl,i_rsp_d,  i_rsp_sintr_v,  i_rsp_sintr_id,  i_rsp_tstag, i_rsp_aux}),
      .o_v(s1a_v),.o_r(s1a_r),      .o_a(s1_ctxt), .o_d({  s1_ec,    s1_nocmpl,   s1_d,     s1_sintr_v,     s1_sintr_id,     s1_tstag,    s1_aux})
      );

   wire 		      s5_rst;
   wire 		      s5_we;
   wire [0:64] 		      s5_wd;
   wire [0:ctxtid_width-1]    s5_wa;
   wire [0:64] 		      s1_cur;

   capi_parcheck#(.width(ctxtid_width-1)) s1_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(i_rsp_v),.i_d(s1_ctxt[0:ctxtid_width-2]),.i_p(s1_ctxt[ctxtid_width-1]),.o_error(s1_perror[1]));

   capi_parcheck#(.width(ctxtid_width-1)) s5_wa_pcheck(.clk(clk),.reset(reset),.i_v(s5_we),.i_d(s5_wa[0:ctxtid_width-2]),.i_p(s5_wa[ctxtid_width-1]),.o_error(s1_perror[2]));

   base_mem#(.width(65),.addr_width(ctxtid_width-1)) irrq_cr_mem(.clk(clk),.we(s5_we),.wa(s5_wa[0:ctxtid_width-2]),.wd(s5_wd),              .re(1'b1),.ra(s1_ctxt[0:ctxtid_width-2]),.rd(s1_cur));
   wire 		      s1_xact_outst;

   wire 		      s1_bypass = s1_sintr_v | s1_nocmpl;

   wire 		      s1b_v, s1b_r;
   base_vmem#(.a_width(ctxtid_width-1)) irrq_xoutst_mem
     (.clk(clk),.reset(reset),.i_rd_en(1'b1),.i_rd_a(s1_ctxt[0:ctxtid_width-2]),.o_rd_d(s1_xact_outst),
      .i_set_v(s1b_v & s1b_r & ~s1_bypass),.i_set_a(s1_ctxt[0:ctxtid_width-2]), .i_rst_v(s5_we & s5_rst),.i_rst_a(s5_wa[0:ctxtid_width-2]));

   base_agate is1b_gt(.i_v(s1a_v),.i_r(s1a_r),.o_v(s1b_v),.o_r(s1b_r),.en(~s1_xact_outst | s1_bypass));

   wire 		      s2a_v, s2a_r;
   wire [0:64] 		      s2_cur;
   wire [0:ctxtid_width-1]    s2_ctxt;
   wire [0:64] 		      s2_d;
   wire 		      s2_sintr_v;
   wire [0:sintrid_width-1]   s2_sintr_id;
   wire [0:tstag_width-1]     s2_tstag;
   wire [0:aux_width-1]       s2_aux;
   wire 		      s2_bypass;
   wire 		      s2_ec;
   wire 		      s2_nocmpl;
   base_alatch#(.width(65+ctxtid_width+1+1+65+1+1+sintrid_width+tstag_width+aux_width)) is2_lat
     (.clk(clk),.reset(reset),
      .i_v(s1b_v),.i_r(s1b_r),.i_d({s1_cur,s1_ctxt,s1_ec,s1_nocmpl,s1_bypass,s1_d, s1_sintr_v, s1_sintr_id, s1_tstag, s1_aux}),
      .o_v(s2a_v),.o_r(s2a_r),.o_d({s2_cur,s2_ctxt,s2_ec,s2_nocmpl,s2_bypass,s2_d, s2_sintr_v, s2_sintr_id, s2_tstag, s2_aux})
      );

   wire [0:1] 		      s2b_v, s2b_r;
   base_acombine#(.ni(1),.no(2)) is2b_cmb(.i_v(s2a_v),.i_r(s2a_r),.o_v(s2b_v),.o_r(s2b_r));

   wire 		      s2c_v, s2c_r;
   base_afilter is2_fltr(.i_v(s2b_v[0]),.i_r(s2b_r[0]),.o_v(s2c_v),.o_r(s2c_r),.en(~s2_bypass));

   wire 		      s2_put_data_v;
   wire 		      s2_put_data_r;
   base_acombine#(.ni(1),.no(2)) io_cmb(.i_v(s2c_v),.i_r(s2c_r),.o_v({o_put_addr_v,s2_put_data_v}),.o_r({o_put_addr_r,s2_put_data_r}));
   wire   o_put_addr_ea_par;
   
   capi_parcheck#(.width(64)) s2_cur_pcheck(.clk(clk),.reset(reset),.i_v(s2a_v),.i_d(s2_cur[0:63]),.i_p(s2_cur[64]),.o_error(s1_perror[3]));
   capi_parity_gen#(.dwidth(64),.width(1)) o_put_addr_ea_pgen(.i_d(o_put_addr_ea[0:63]),.o_d(o_put_addr_ea_par));

   assign o_put_addr_ea = {s2_cur[0:62],1'b0,o_put_addr_ea_par};
   assign o_put_addr_ctxt = s2_ctxt;
   assign o_put_addr_tstag = s2_tstag;
   
   base_aesplit iesplt
     (.clk(clk),.reset(reset),
      .i_v(s2_put_data_v),.i_r(s2_put_data_r),.i_e(1'b1),
      .o_v(o_put_data_v),.o_r(o_put_data_r),.o_e(o_put_data_e)
      );
   base_endian_mux#(.bytes(16)) iput_data_szl(.i_ctrl(s2_ec),.i_d({s2_d[0:62],s2_cur[63],s2_d[0:62],s2_cur[63]}),.o_d(o_put_data_d[0:127]));
   wire                       o_put_data_d_par;
   capi_parity_gen#(.dwidth(64),.width(1)) o_put_data_d_pgen(.i_d(o_put_data_d[0:63]),.o_d(o_put_data_d_par));
   assign o_put_data_d[128:129] = {o_put_data_d_par,o_put_data_d_par};
   assign o_put_data_c = 4'b1000;
   assign o_put_data_f = 1'b1;

   
   wire [0:1] 		      s3a_v, s3a_r;
   wire 		      s3_bypass;
   wire 		      s3_nocmpl;
   wire [0:64] 		      s3_cur;
   wire [0:ctxtid_width-1]    s3_ctxt;
   wire 		      s3_byp_sintr_v;
   wire [0:sintrid_width-1]   s3_byp_sintr_id;
   wire [0:aux_width-1]       s3_aux;
   base_fifo#(.LOG_DEPTH(2),.width(65+ctxtid_width+1+1+1+sintrid_width+aux_width)) is3_fifo
     (.clk(clk),.reset(reset),
      .i_v(s2b_v[1]),.i_r(s2b_r[1]),.i_d({s2_cur,s2_ctxt,s2_nocmpl,s2_bypass,    s2_sintr_v,    s2_sintr_id,s2_aux}),
      .o_v(s3a_v[1]),.o_r(s3a_r[1]),.o_d({s3_cur,s3_ctxt,s3_nocmpl,s3_bypass,s3_byp_sintr_v,s3_byp_sintr_id,s3_aux}));
   // at this point we can combine with incoming write done.
   base_aforce is3_frc(.i_v(i_put_done_v),.i_r(i_put_done_r),.o_v(s3a_v[0]),.o_r(s3a_r[0]),.en(~s3_bypass));

   wire [0:1] 		      s3b_v, s3b_r;
   base_acombine#(.ni(2),.no(2)) is3_cmb(.i_v(s3a_v),.i_r(s3a_r),.o_v(s3b_v),.o_r(s3b_r));
   
   wire [0:dma_rc_width-1]    s3_put_done_rc = i_errinj_rrq_paged ? psl_rsp_paged : (i_errinj_rrq_fault ? psl_rsp_addr : i_put_done_rc);
   wire 		      s3_paged = (s3_put_done_rc == psl_rsp_paged);
   wire 		      s3_error = (| i_put_done_rc);
   assign o_dbg_cnt_inc = i_put_done_v & i_put_done_r & (i_put_done_rc == psl_rsp_cinv);
   
   wire 		      s3_put_sintr_v = s3_error;
   wire [0:sintrid_width-1]   s3_put_sintr_id = s3_paged ? sintr_paged : sintr_rrq;

   wire 		      s3_sintr_v = s3_bypass ? s3_byp_sintr_v : s3_put_sintr_v;
   wire [0:sintrid_width-1]   s3_sintr_id = s3_bypass ? s3_byp_sintr_id : s3_put_sintr_id;
   
   // 0 goes to output
   base_alatch_burp#(.width(1+1+sintrid_width+aux_width)) ir2_lat
     (.clk(clk),.reset(reset),
      .i_v(s3b_v[0]),.i_r(s3b_r[0]),.i_d({s3_nocmpl,s3_sintr_v, s3_sintr_id, s3_aux}),
      .o_v(o_rsp_v), .o_r(o_rsp_r), .o_d({o_rsp_nocmpl,o_rsp_sintr_v,o_rsp_sintr_id,o_rsp_aux})
      );
   // 1 goes to update the pointer
   wire 		      s3c_v, s3c_r;
   base_afilter is3c_fltr(.i_v(s3b_v[1]),.i_r(s3b_r[1]),.o_v(s3c_v),.o_r(s3c_r),.en(~s3_bypass));

   wire 		      s4a_v, s4a_r;
   wire 		      s3_re;
   wire [0:64] 		      s4_cur;    // changed these from 63 to 64 kch 
   wire [0:64] 		      s4_rrq_st; //
   wire [0:64] 		      s4_rrq_ed; 
   wire [0:ctxtid_width-1]    s4_ctxt;
   wire 		      s4_error;
   
   base_alatch_oe#(.width(65+ctxtid_width+1)) is4_lat
     (.clk(clk),.reset(reset),
      .i_v(s3c_v),.i_r(s3c_r),.i_d({s3_cur,s3_ctxt,s3_error}),
      .o_v(s4a_v),.o_r(s4a_r),.o_d({s4_cur,s4_ctxt,s4_error}),.o_en(s3_re));

   capi_parcheck#(.width(ctxtid_width-1)) s3_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s3a_v[1]),.i_d(s3_ctxt[0:ctxtid_width-2]),.i_p(s3_ctxt[ctxtid_width-1]),.o_error(s1_perror[4]));
   capi_parcheck#(.width(64)) s4_rrq_st_pcheck(.clk(clk),.reset(reset),.i_v(s4a_v),.i_d(s4_rrq_st[0:63]),.i_p(s4_rrq_st[64]),.o_error(s1_perror[5]));  // change s3_re to  s4a_v
   capi_parcheck#(.width(64)) s4_rrq_ed_pcheck(.clk(clk),.reset(reset),.i_v(s4a_v),.i_d(s4_rrq_ed[0:63]),.i_p(s4_rrq_ed[64]),.o_error(s1_perror[6]));

   base_mem#(.width(65),.addr_width(ctxtid_width-1)) irrq_st_mem(.clk(clk),.we(i_rrq_st_we),.wa(i_rrq_ctxt[0:ctxtid_width-2]),.wd(i_rrq_wd),.re(s3_re),.ra(s3_ctxt[0:ctxtid_width-2]),.rd(s4_rrq_st));
   base_mem#(.width(65),.addr_width(ctxtid_width-1)) irrq_ed_mem(.clk(clk),.we(i_rrq_ed_we),.wa(i_rrq_ctxt[0:ctxtid_width-2]),.wd(i_rrq_wd),.re(s3_re),.ra(s3_ctxt[0:ctxtid_width-2]),.rd(s4_rrq_ed));
   wire [0:63] 		      s4_nxt = s4_error ? s4_cur : ((s4_cur[0:62] == s4_rrq_ed[0:62]) ? {s4_rrq_st[0:62],~s4_cur[63]} : s4_cur[0:63]+64'd8);  // added 0:63 kch 
   wire                       s4_nxt_par;

   capi_parity_gen#(.dwidth(64),.width(1)) s4_nxt_pgen(.i_d(s4_nxt[0:63]),.o_d(s4_nxt_par));


   wire 		      s4b_v, s4b_r;
   wire [0:64] 		      s4_wd;
   wire [0:ctxtid_width-1]    s4_wa;
   wire [0:1] 		      s4_sel;
   wire 		      i_rrq_st_r_dummy;

   assign i_rrq_wd_par = i_rrq_wd[63] ? i_rrq_wd[64] : ~i_rrq_wd[64];
 
   base_primux#(.ways(2),.width(65+ctxtid_width)) icm_wmux
     (.i_v({i_rrq_st_we,s4a_v}),.i_r({i_rrq_st_r_dummy,s4a_r}),.i_d({i_rrq_ctxt,i_rrq_wd[0:62],1'b1,i_rrq_wd_par,s4_ctxt,s4_nxt,s4_nxt_par}),.o_v(s4b_v),.o_r(s4b_r),.o_d({s4_wa,s4_wd}),.o_sel(s4_sel));  // add 1 and not bit 64 kch 
   assign s4b_r = 1'b1;

   base_vlat#(.width(1+ctxtid_width+65)) icr_wlat(.clk(clk),.reset(1'b0), .din({s4_sel[1],s4_wa,s4_wd}),.q({s5_rst,s5_wa,s5_wd}));
   base_vlat#(.width(1))               icr_vlat(.clk(clk),.reset(reset),.din(s4b_v),.q(s5_we));


   // log rrq writes for debug

   wire [0:127]		      l1_d;
   wire [0:ctxtid_width-1]    l1_ctxt;
   base_alatch#(.width(ctxtid_width+128)) il1_lat(.clk(clk),.reset(reset),.i_v(s2c_v & s2c_r),.i_r(),.i_d({s2_ctxt,s2_d[0:62],s2_ec,s2_cur[0:63]}),.o_v(l1_v),.o_r(1'b1),.o_d({l1_ctxt,l1_d}));
						  
   localparam la_width=2;
   localparam memaddr_width = ctxtid_width-1+la_width;  // add -1 to strip off parity bit

   localparam lcladdr_width=memaddr_width+3;
   
   wire [0:la_width-1] 	      l1_la, l1_qla;
   wire 		      l1_la_v;
   assign l1_qla = l1_la_v ? l1_la : {la_width{1'b0}};

   capi_parcheck#(.width(ctxtid_width-1)) s2_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s2a_v),.i_d(s2_ctxt[0:ctxtid_width-2]),.i_p(s2_ctxt[ctxtid_width-1]),.o_error(s1_perror[7]));
   capi_parcheck#(.width(ctxtid_width-1)) l1_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(l1_v),.i_d(l1_ctxt[0:ctxtid_width-2]),.i_p(l1_ctxt[ctxtid_width-1]),.o_error(s1_perror[8]));

   base_mem_bypass#(.width(la_width),.addr_width(ctxtid_width-1)) il1_amem(.clk(clk),.re(1'b1),.ra(s2_ctxt[0:ctxtid_width-2]),.rd(l1_la),.we(l1_v),.wa(l1_ctxt[0:ctxtid_width-2]),.wd(l1_qla+1'b1));
   base_vmem_bypass#(.a_width(ctxtid_width-1)) il1_avmem(.clk(clk),.reset(reset),.i_set_v(l1_v),.i_set_a(l1_ctxt[0:ctxtid_width-2]),.i_rst_v(i_rrq_st_we),.i_rst_a(i_rrq_ctxt[0:ctxtid_width-2]),.i_rd_en(1'b1),.i_rd_a(s2_ctxt[0:ctxtid_width-2]),.o_rd_d(l1_la_v));

   wire [0:15] 		      l1_cnt;
   wire [0:15]		      l1_qcnt = l1_la_v ? l1_cnt : 16'd0;
   base_mem_bypass#(.width(16),.addr_width(ctxtid_width-1)) il1_cmem0(.clk(clk),.re(1'b1),.ra(s2_ctxt[0:ctxtid_width-2]),.rd(l1_cnt),.we(l1_v),.wa(l1_ctxt[0:ctxtid_width-2]),.wd(l1_qcnt+1'b1));
   
   
   wire 		      m1_rd_v, m1_rd_r;
   wire [0:lcladdr_width-1]   m1_rd_ra;
   wire [0:127] 	      m2_rd_d_premux;
   wire 		      m1_rd_en;
   base_mem#(.width(128),.addr_width(ctxtid_width-1+la_width)) il1_dmem0(.clk(clk),.re(m1_rd_en),.ra(m1_rd_ra[0:memaddr_width-1]),.rd(m2_rd_d_premux),.we(l1_v),.wa({l1_ctxt[0:ctxtid_width-2],l1_qla}),.wd(l1_d));

   wire [0:15] 		      m2_cnt_d;
   base_mem#(.width(16),.addr_width(ctxtid_width-1)) il1_cmem1(.clk(clk),.re(m1_rd_en),.ra(m1_rd_ra[0:ctxtid_width-2]),.rd(m2_cnt_d),.we(l1_v),.wa(l1_ctxt[0:ctxtid_width-2]),.wd(l1_qcnt+1'b1));
   
   wire 		      m2_rd_r, m2_rd_v;
   wire [0:1] 		      m2_sel;
   base_alatch_oe#(.width(2)) im2_lat(.clk(clk),.reset(reset),.i_v(m1_rd_v),.i_r(m1_rd_r),.i_d(m1_rd_ra[memaddr_width:lcladdr_width-2]),.o_v(m2_rd_v),.o_r(m2_rd_r),.o_d(m2_sel),.o_en(m1_rd_en));

   wire [0:63] 		      m2_rd_d = m2_sel[0] ? {48'd0,m2_cnt_d} : (m2_sel[1] ? m2_rd_d_premux[64:127] : m2_rd_d_premux[0:63]);
   
   wire                       rrq_vld,rrq_cfg,rrq_rnw,rrq_dw;
   wire [0:24]                rrq_addr;
   wire [0:64]                rrq_data;
   wire [0:4+24+64-1]         rrq_mmiobus;

   assign {rrq_vld,rrq_cfg,rrq_rnw,rrq_dw,rrq_addr,rrq_data} = i_mmiobus; // omit any extra data bits kch
   assign rrq_mmiobus = {rrq_vld,rrq_cfg,rrq_rnw,rrq_dw,rrq_addr[0:23],rrq_data[0:63]};  // created to strip of parity  kch
   ktms_mmrd_dec#(.lcladdr_width(lcladdr_width),.addr(mmioaddr),.mmiobus_width(mmiobus_width-2)) immrd_dec
     (.clk(clk),.reset(reset),.i_mmiobus(rrq_mmiobus),
      .o_rd_r(m1_rd_r),.o_rd_v(m1_rd_v),.o_rd_addr(m1_rd_ra),
      .i_rd_r(m2_rd_r),.i_rd_v(m2_rd_v),.i_rd_d(m2_rd_d),
      .o_mmio_rd_v(o_mmio_ack),.o_mmio_rd_d(o_mmio_data)
      );

endmodule // ktms_afu_rrq
