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
module ktms_afu_int#
  (parameter mmiobus_width=1,
   parameter mmio_ht_addr=0,
   parameter mmio_cpc_addr=0,
   parameter ctxtid_width=0,
   parameter msi_width=0,
   parameter croom_width=0,
   parameter tstag_width=0,
   parameter sintrid_width = 0,
   parameter [0:sintrid_width-1] sintr_croom=1,
   parameter nintrs = 1
   )
   (
    input 		      clk,
    input 		      reset,
    input [0:mmiobus_width-1] i_mmiobus,

    input 		      i_ctxt_add_v,
    input [0:ctxtid_width-1]  i_ctxt_add_d,

    input 		      o_ctxt_rst_r,
    output 		      o_ctxt_rst_v,
    output [0:ctxtid_width-1] o_ctxt_rst_id,

    input 		      i_ctxt_rst_ack_v,
    input [0:ctxtid_width-1]  i_ctxt_rst_ack_id,   // parity checked in afu_timeout kch 
    
    // limited backpressure possible here
    output 		      i_croom_err_r,
    input 		      i_croom_err_v,
    input [0:ctxtid_width-1]  i_croom_err_ctxt,

    output 		      i_sintr_r,
    input 		      i_sintr_v,
    input [0:tstag_width-1]   i_sintr_tstag, 
    input [0:ctxtid_width-1]  i_sintr_ctxt,
    input [0:sintrid_width-1] i_sintr_id,

    input 		      i_croom_we,
    input [0:ctxtid_width-2]  i_croom_wa,   // no parity on this kch 
    input [0:croom_width-1]   i_croom_wd,

    input 		      o_tscheck_r,
    output 		      o_tscheck_v,
    output [0:tstag_width-1]  o_tscheck_tstag,
    output [0:ctxtid_width-1] o_tscheck_ctxt,

    output 		      i_tscheck_r,
    input 		      i_tscheck_v,
    input 		      i_tscheck_ok,

    output 		      o_rrq_st_we,
    output 		      o_rrq_ed_we,
    output [0:ctxtid_width-1] o_rrq_ctxt,
    output [0:64] 	      o_rrq_wd, 
    
    input 		      o_intr_r,
    output 		      o_intr_v,
    output [0:ctxtid_width-1] o_intr_ctxt,
    output [0:msi_width-1]    o_intr_msi,

    output 		      o_mmio_rd_v,
    output [0:63] 	      o_mmio_rd_d,
    output [0:nintrs-1]       o_dbg_cnt_inc,
    
    output 		      o_ec_set,
    output 		      o_ec_rst,
    output [0:ctxtid_width-1] o_ec_id,
    output [0:1]              o_perror
    
    );

   /* offets
    0 - endian control.    r/w here
    1 - interupt status(6) mmio-read, local read, ext update
    2 - interupt clear  mmio-write - affectst status
    3 - interupt mask(6)   mmio read/write, local read 
    4 - ioarrin (not implemented here)
    5 - rrq ea start (mmio-read/mmio-write)
    6 - rrq ea end   (mmio-read/mmio-write) 
    7 - cmd-room 
    8 - context control (mmio-read/mmio-write) local read few bits
    */

   localparam lcladdr_width = 4;
   localparam lcladdr_dec_width = 16;
 

   // context add
   wire 		      s1_ca_v, s1_ca_r;
   wire [0:ctxtid_width-1]    s1_ca_id;
   base_alatch#(.width(ctxtid_width)) is1_ctxt_add_lat(.clk(clk),.reset(reset),.i_v(i_ctxt_add_v),.i_r(),.i_d(i_ctxt_add_d),.o_v(s1_ca_v),.o_r(s1_ca_r),.o_d(s1_ca_id));

   // mmio write
   wire 		      s1_wr_r;
   wire 		      s1_wr_v;
   wire [0:lcladdr_width-1]   s1_wr_addr;
   wire 		      s1_wr_addr_dummy;
   
   wire 		       int_cfg;  // this is config space
   wire 		       int_rnw;  // read not write
   wire 		       int_vld;  // valid 
   wire 		       int_dw;   // double word
   wire [0:64] 		       int_data;   // change 63 to 64 to add parity kch 
   wire [0:24]  	       int_addr;
   wire [0:4+24+64-1]          int_mmiobus;
   assign {int_vld,int_cfg,int_rnw,int_dw,int_addr,int_data} = i_mmiobus; // omit any extra data bits
   assign int_mmiobus = {int_vld,int_cfg,int_rnw,int_dw,int_addr[0:23],int_data[0:63]};  // created to strip of parity 
   wire [0:ctxtid_width-1]    s1_wr_ctxt;
   wire [63:0] 		      s1_wr_d;
   ktms_mmwr_mc_dec#(.mmiobus_width(mmiobus_width-2),.addr(mmio_ht_addr),.lcladdr_width(lcladdr_width+1)) immwr_dec
     (.clk(clk),.reset(reset),
      .i_mmiobus(int_mmiobus),
      .o_wr_r(s1_wr_r),.o_wr_v(s1_wr_v),.o_wr_addr({s1_wr_addr,s1_wr_addr_dummy}),.o_wr_ctxt(s1_wr_ctxt),.o_wr_d(s1_wr_d)
      );

   wire                       s1_wr_d_par;
   capi_parity_gen#(.dwidth(64),.width(1)) s1_wr_d_pgen0(.i_d(s1_wr_d[63:0]),.o_d(s1_wr_d_par));



   // latch cmcroom error
   wire 		      s0_croom_err_v, s0_croom_err_r;
   wire [0:ctxtid_width-1]    s0_croom_err_ctxt;
   base_alatch#(.width(ctxtid_width)) is0_croom_lat
     (.clk(clk),.reset(reset),
      .i_v(i_croom_err_v),.i_r(i_croom_err_r),.i_d(i_croom_err_ctxt),
      .o_v(s0_croom_err_v),.o_r(s0_croom_err_r),.o_d(s0_croom_err_ctxt)
      );


   // make sure the context is still current before we go and post an interupt
   wire 		      s1a_sintr_v, s1a_sintr_r;
   wire [0:sintrid_width-1]   s1_sintr_id;
   wire [0:ctxtid_width-1]    s1_sintr_ctxt;
   wire [0:tstag_width-1]     s1_sintr_tstag;
   base_alatch_burp#(.width(sintrid_width+ctxtid_width+tstag_width)) is0_intr_lat
     (.clk(clk),.reset(reset),
      .i_v(i_sintr_v),.i_r(i_sintr_r),.i_d({i_sintr_id, i_sintr_ctxt, i_sintr_tstag}),
      .o_v(s1a_sintr_v),.o_r(s1a_sintr_r),.o_d({s1_sintr_id, s1_sintr_ctxt, s1_sintr_tstag}));

   wire 		      s1b_sintr_v, s1b_sintr_r;   
   base_acombine#(.ni(1),.no(2)) is1_sintr_cmb
     (.i_v(s1a_sintr_v),.i_r(s1a_sintr_r),
      .o_v({s1b_sintr_v,o_tscheck_v}),
      .o_r({s1b_sintr_r,o_tscheck_r}));
   assign o_tscheck_ctxt = s1_sintr_ctxt;
   assign o_tscheck_tstag = s1_sintr_tstag;
   
   wire 		      s2a_sintr_v, s2a_sintr_r;
   wire [0:sintrid_width-1]   s2_sintr_id;
   wire [0:ctxtid_width-1]    s2_sintr_ctxt;
   base_alatch#(.width(sintrid_width+ctxtid_width)) is2_intr_lat
     (.clk(clk),.reset(reset),
      .i_v(s1b_sintr_v),.i_r(s1b_sintr_r),.i_d({s1_sintr_id, s1_sintr_ctxt}),
      .o_v(s2a_sintr_v),.o_r(s2a_sintr_r),.o_d({s2_sintr_id, s2_sintr_ctxt}));

   wire 		      s2b_sintr_v, s2b_sintr_r;   
   base_acombine#(.ni(2),.no(1)) is2_cmb
     (.i_v({s2a_sintr_v,i_tscheck_v}),
      .i_r({s2a_sintr_r,i_tscheck_r}),
      .o_v(s2b_sintr_v),.o_r(s2b_sintr_r));

   wire 		      s2c_sintr_v, s2c_sintr_r;
   base_afilter is2_intr_fltr(.i_v(s2b_sintr_v),.i_r(s2b_sintr_r),.o_v(s2c_sintr_v),.o_r(s2c_sintr_r),.en(i_tscheck_ok));

   // mux between croom error, and error from completion logic   
   wire [0:ctxtid_width-1]    s0_err_ctxt;
   wire [0:sintrid_width-1]   s0_err_id;
   wire 		      s0_v, s0_r;
   base_primux#(.ways(2),.width(sintrid_width + ctxtid_width)) ierr_arb
     (.i_v({s0_croom_err_v,s2c_sintr_v}),
      .i_r({s0_croom_err_r,s2c_sintr_r}),
      .i_d({s0_croom_err_ctxt,sintr_croom,s2_sintr_ctxt,s2_sintr_id}),
      .o_v(s0_v),.o_r(s0_r),.o_d({s0_err_ctxt,s0_err_id}),.o_sel()
      );

   // decode error number: bit 0 on the right so we can grow
   wire [0:nintrs-1] 	      s0_err_sel, s0_err_sel_r;
   base_decode#(.enc_width(sintrid_width),.dec_width(nintrs)) is0_dec(.din(s0_err_id),.dout(s0_err_sel_r),.en(1'b1));
   base_bitswap#(.width(nintrs)) is0_rev(.i_d(s0_err_sel_r),.o_d(s0_err_sel));
      
   wire 		      s1_er_v, s1_er_r;
   wire [0:ctxtid_width-1]    s1_er_ctxt;
   wire [0:nintrs-1] 	      s1_src;
   
   base_alatch_burp#(.width(ctxtid_width+nintrs)) is1_lat
     (.clk(clk),.reset(reset),
      .i_v(s0_v),.i_r(s0_r),.i_d({s0_err_ctxt,s0_err_sel}),
      .o_v(s1_er_v),.o_r(s1_er_r),.o_d({s1_er_ctxt,s1_src}));

   // debug count
   wire 		   s1_er_act = s1_er_v & s1_er_r;
   assign o_dbg_cnt_inc = {nintrs {s1_er_act}} & s1_src;

   
   // mux between context add, inbound error and mmio
   wire 		      s1b_v, s1b_r;
   wire [0:ctxtid_width-1]    s1_ctxt;
   wire [0:2] 		      s1_sel;
   wire [0:nintrs-1] 	      nintrs_zero = {nintrs{1'b0}};
   // 0: context add. 1: write to clear reg, 2: write to mask reg, 3: interupt event   
   base_primux#(.ways(3),.width(ctxtid_width)) iupd_mux
     (.i_v({s1_ca_v, s1_wr_v, s1_er_v}),
      .i_r({s1_ca_r, s1_wr_r, s1_er_r}),
      .i_d({s1_ca_id, 
	    s1_wr_ctxt, 
	    s1_er_ctxt}),
      .o_v(s1b_v),.o_r(s1b_r),.o_d(s1_ctxt),.o_sel(s1_sel)
      );

   wire [0:4] 				s1_perror;
   capi_parcheck#(.width(ctxtid_width-1)) s1_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s1b_v),.i_d(s1_ctxt[0:ctxtid_width-2]),.i_p(s1_ctxt[ctxtid_width-1]),.o_error(s1_perror[0]));
   wire [0:4] 				hld_perror;
   wire  				any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(5)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(5'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(any_hld_perror),.q(o_perror[0]));

   // given context and error
   // read current interupt status
   // read mask
   // update status
   // optionally generate interupt
   // only allow one transaction at a time in the three-stage pipe to avoid bypass logic
   wire 		      s1c_v, s1c_r;
   wire 		      s3_v,s3_r;
   wire 		      s2_v,s2_r;
   base_agate is1_gt(.i_v(s1b_v),.i_r(s1b_r),.o_v(s1c_v),.o_r(s1c_r),.en(~s2_v & ~s3_v));

   wire [0:ctxtid_width-1]    s2_ctxt;
   wire [0:nintrs-1] 	      s2_src;
   wire [0:2] 		      s2_sel;
   wire [63:0] 		      s2_wr_d;
   wire  		      s2_wr_d_par;
   wire [0:lcladdr_width-1]   s2_wr_addr;
   base_alatch#(.width(ctxtid_width+nintrs+3+lcladdr_width+65)) is2_lat
     (.clk(clk),.reset(reset),
      .i_v(s1c_v),.i_r(s1c_r),.i_d({s1_ctxt, s1_src, s1_sel,s1_wr_addr,s1_wr_d,s1_wr_d_par}),
      .o_v(s2_v), .o_r(s2_r), .o_d({s2_ctxt, s2_src, s2_sel,s2_wr_addr,s2_wr_d,s2_wr_d_par}));


      // control and result of reading interupt regs for active context
   wire               s1_en = s2_r | ~s2_v;
   wire [0:nintrs-1] 	      s2_stat, s2_msk;

   wire [0:ctxtid_width-1]    s3_ctxt;
   wire [0:nintrs-1] 	      s3_src, s3_stat, s3_msk;
   wire [0:2] 		      s3_sel;
   wire [63:0] 		      s3_wr_d;
   wire  		      s3_wr_d_par;
   wire [0:lcladdr_width-1]   s3_wr_addr;
   base_alatch#(.width(ctxtid_width+nintrs*3+3+lcladdr_width+64+1)) is3_lat
     (.clk(clk),.reset(reset),
      .i_v(s2_v), .i_r(s2_r), .i_d({s2_ctxt, s2_src, s2_stat, s2_msk, s2_sel,s2_wr_addr,s2_wr_d,s2_wr_d_par}),
      .o_v(s3_v), .o_r(s3_r), .o_d({s3_ctxt, s3_src, s3_stat, s3_msk, s3_sel,s3_wr_addr,s3_wr_d,s3_wr_d_par}));
   assign s3_r = 1'b1;

   capi_parcheck#(.width(ctxtid_width-1)) s3_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s3_v),.i_d(s3_ctxt[0:ctxtid_width-2]),.i_p(s3_ctxt[ctxtid_width-1]),.o_error(s1_perror[1]));


   wire [0:lcladdr_dec_width-1] s3_wr_addr_dec;
   base_decode#(.enc_width(lcladdr_width),.dec_width(lcladdr_dec_width)) is3addr_dec(.din(s3_wr_addr),.dout(s3_wr_addr_dec),.en(1'b1));

   capi_parcheck#(.width(64)) s3_wr_d_pcheck(.clk(clk),.reset(reset),.i_v(s3_v),.i_d(s3_wr_d[63:0]),.i_p(s3_wr_d_par),.o_error(s1_perror[4]));


   
   // how to update status on write to clear register
   wire [0:nintrs-1]  s3_upd_clr = s3_stat & ~s3_wr_d[nintrs-1:0];
   wire 	      s3_irq_clr = | (s3_upd_clr & ~s3_msk);

   // how to update status and whether to generate an interupt on new error 
   wire [0:nintrs-1]  s3_upd_err = s3_stat | s3_src;
   wire 	      s3_irq_err = | (s3_src & ~s3_stat & ~s3_msk);
   
   wire 	      s3_act = s3_v & s3_r;



   wire 	      s3_r0_we = s3_act & (
					   s3_sel[0] // context add
					   | (s3_sel[1] & s3_wr_addr_dec[0])
					   );

   wire 	      s3_r1_we = s3_act & ( 
					    s3_sel[0] // context add
					    | (s3_sel[1] & s3_wr_addr_dec[2]) // write to clear reg
					    | s3_sel[2] // interupt event
					    );

   
   wire 	      s3_irq_wr = s3_wr_addr_dec[2] & s3_irq_clr;
   wire [0:nintrs-1]  s3_r1_wd;
   base_mux#(.ways(3),.width(nintrs)) is3_stat_wd_mux(.sel(s3_sel[0:2]),.din({nintrs_zero,s3_upd_clr,s3_upd_err}),.dout(s3_r1_wd));

   
   // how and when to update mask register
   wire 	      s3_r3_we = s3_act & (
					   s3_sel[0] // context add
					   | (s3_sel[1] & s3_wr_addr_dec[3]) // write to mask reg
					   );
   wire [0:nintrs-1]  s3_r3_wd = s3_sel[0] ? ~nintrs_zero : s3_wr_d[nintrs-1:0];
   

  // how and when to update other regs
   wire [63:0] 	      s3_rx_wd = s3_sel[0] ? 64'd0 : s3_wr_d;
   wire 	      s3_rx_wd_par = s3_sel[0] ? 1'd1 : s3_wr_d_par;

   wire 	      s3_r4_we = s3_act & (
					   s3_sel[0] // context add
					   | (s3_sel[1] & s3_wr_addr_dec[4])
					   );

   wire 	      s3_cr_cancel = s3_act & s3_sel[0];
   
   wire 	      s3_r5_we = s3_act & (
					   s3_sel[0] // context add
					   | (s3_sel[1] & s3_wr_addr_dec[5])
					   );
   
   wire 	      s3_r6_we = s3_act & (
					   s3_sel[0] // context add
					   | (s3_sel[1] & s3_wr_addr_dec[6])
					   );

   wire 	      s3_r8_we = s3_act & (
					   s3_sel[0] // context add
					   | (s3_sel[1] & s3_wr_addr_dec[8])
					   );


   // inform the rrq logic of updates to rrq regs
   assign o_rrq_st_we = s3_r5_we;
   assign o_rrq_ed_we = s3_r6_we;
   assign o_rrq_ctxt = s3_ctxt;
   assign o_rrq_wd = {s3_rx_wd,s3_rx_wd_par};
   
   
   wire 		   s3_irq;
   base_mux#(.ways(2),.width(1)) is3_mux
     (.sel(s3_sel[1:2]),
      .din({s3_irq_wr,s3_irq_err}),
      .dout(s3_irq)
      );


      // interupt status memory      
   base_mem#(.addr_width(ctxtid_width-1),.width(nintrs)) iistat_mem
     (.clk(clk),
      .re(s1_en),.ra(s1_ctxt[0:ctxtid_width-2]),.rd(s2_stat),
      .we(s3_r1_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_r1_wd)
      );

      // interupt mask memory 
   base_mem#(.addr_width(ctxtid_width-1),.width(nintrs)) iimsk_mem0
     (.clk(clk),
      .re(s1_en),.ra(s1_ctxt[0:ctxtid_width-2]),.rd(s2_msk),
      .we(s3_r3_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_r3_wd)
      );

   // interupt generation
   localparam [0:ctxtid_width-2] ctxt_one = 1;
   
   wire 		      t0_en;
   wire [0:ctxtid_width-1]    t0_ctxt;
   wire                       t0_ctxt_par;
   wire [0:ctxtid_width-2]  t0_ctxt_plus1 = t0_ctxt[0:ctxtid_width-2]+ctxt_one;
   capi_parity_gen#(.dwidth(9),.width(1)) t0_ctxt_pgen(.i_d(t0_ctxt_plus1),.o_d(t0_ctxt_par));

   base_vlat_en#(.width(ctxtid_width)) it0_ctxt_lat
     (.clk(clk),.reset(reset),.din({(t0_ctxt_plus1),t0_ctxt_par}),.q(t0_ctxt),.enable(t0_en));
   wire 		      t1_v, t1_r;
   wire [0:ctxtid_width-1]    t1_ctxt;

   wire 		      t0_v, t0_r;
   assign t0_v = 1'b1;
   
   base_alatch#(.width(ctxtid_width)) it1_lat(.clk(clk),.reset(reset),.i_v(t0_v),.i_r(t0_r),.i_d(t0_ctxt),.o_v(t1_v),.o_r(t1_r),.o_d(t1_ctxt));
   assign t0_en = t1_r | ~t1_v;
   wire 		      t1_intr_pending;
   base_vmem#(.a_width(ctxtid_width-1)) iip_mem
     (.clk(clk),.reset(reset),
      .i_set_v(s3_v & s3_r & s3_irq),.i_set_a(s3_ctxt[0:ctxtid_width-2]),
      .i_rst_v(t0_v & t0_r),.i_rst_a(t0_ctxt[0:ctxtid_width-2]),
      .i_rd_en(t0_en),.i_rd_a(t0_ctxt[0:ctxtid_width-2]),.o_rd_d(t1_intr_pending)
      );

   // written by mmio offset 8
   wire [0:msi_width-1]       t1_msi;
   base_mem#(.addr_width(ctxtid_width-1),.width(msi_width)) imsi_mem
     (.clk(clk),
      .re(t0_en),.ra(t0_ctxt[0:ctxtid_width-2]),.rd(t1_msi),
      .we(s3_r8_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_rx_wd[msi_width-1:0])
      );
   
   wire 		      t1b_v, t1b_r;

   base_afilter iintr_fltr(.i_v(t1_v),.i_r(t1_r),.o_v(t1b_v),.o_r(t1b_r),.en(t1_intr_pending));
   base_aburp#(.width(ctxtid_width+msi_width)) iintr_lat(.clk(clk),.reset(reset),.i_v(t1b_v),.i_r(t1b_r),.i_d({t1_ctxt,t1_msi}),.o_v(o_intr_v),.o_r(o_intr_r),.o_d({o_intr_ctxt,o_intr_msi}),.burp_v());

   // MMIO READS
   wire 		      s1_rd_v, s1_rd_r;
   wire [0:lcladdr_width]     s1_rd_addr; // purposely one extra
   wire [0:ctxtid_width-1]    s1_rd_ctxt;


   wire [0:lcladdr_dec_width-1]     s1_rd_addr_dec;
   base_decode#(.enc_width(lcladdr_width),.dec_width(lcladdr_dec_width)) is1rd_dec(.din(s1_rd_addr[0:lcladdr_width-1]),.en(1'b1),.dout(s1_rd_addr_dec));

   wire 			    s2_rd_v, s2_rd_r;
   wire [0:lcladdr_dec_width-1] s2_rd_addr_dec;
   wire [0:ctxtid_width-1] 	s2_rd_ctxt;
   
   base_alatch#(.width(lcladdr_dec_width+ctxtid_width)) s2_rd_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_rd_v),.i_r(s1_rd_r),.i_d({s1_rd_addr_dec,s1_rd_ctxt}),
      .o_v(s2_rd_v),.o_r(s2_rd_r),.o_d({s2_rd_addr_dec,s2_rd_ctxt})
      );

   wire 		       s1_rd_en = s2_rd_r | ~s2_rd_v;

   // interrupt status

   wire [0:64-1] 	       s2_rd_d0;
   base_mem#(.addr_width(ctxtid_width-1),.width(64)) rmem_mem0
     (.clk(clk),
      .we(s3_r0_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_rx_wd),
      .re(s1_rd_en),.ra(s1_rd_ctxt[0:ctxtid_width-2]),.rd(s2_rd_d0)
      );

   wire s3_ec_rst = s3_r0_we &  (s3_rx_wd[63] | s3_rx_wd[7]);      // set to big endian
   wire s3_ec_set = s3_r0_we & ~(s3_rx_wd[63] | s3_rx_wd[7]);  // set to little endian
   base_vlat#(.width(ctxtid_width)) iec_id_lat(.clk(clk),.reset(1'b0),.din(s3_ctxt),.q(o_ec_id));
   capi_parcheck#(.width(ctxtid_width-1)) o_ec_id_pcheck(.clk(clk),.reset(reset),.i_v(o_ec_set | o_ec_rst),.i_d(o_ec_id[0:ctxtid_width-2]),.i_p(o_ec_id[ctxtid_width-1]),.o_error(s1_perror[3]));
   base_vlat#(.width(2)) iec_sr_lat(.clk(clk),.reset(reset),.din({s3_ec_set,s3_ec_rst}),.q({o_ec_set,o_ec_rst}));
      
   wire [0:nintrs-1] 	       s2_rd_d1;

   // don't update for write to interupt mask
   // interrupt status reg
   base_mem#(.addr_width(ctxtid_width-1),.width(nintrs)) rmem_mem1
     (.clk(clk),
      .we(s3_r1_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_r1_wd),
      .re(s1_rd_en),.ra(s1_rd_ctxt[0:ctxtid_width-2]),.rd(s2_rd_d1)
      );
   
   // interrupt mask reg
   wire [0:nintrs-1]        s2_rd_d3;
   base_mem#(.addr_width(ctxtid_width-1),.width(nintrs)) rmem_mem3
     (.clk(clk),
      .we(s3_r3_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_r3_wd),
      .re(s1_rd_en),.ra(s1_rd_ctxt[0:ctxtid_width-2]),.rd(s2_rd_d3)
      );

   wire [0:63] 		    s2_rd_d4;
   base_mem#(.addr_width(ctxtid_width-1),.width(63)) rmem_mem4
     (.clk(clk),
      .we(s3_r4_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_rx_wd[63:1]),
      .re(s1_rd_en),.ra(s1_rd_ctxt[0:ctxtid_width-2]),.rd(s2_rd_d4[0:62])
      );

   // rrq0 start
   wire [0:63] 		       s2_rd_d5;
   base_mem#(.addr_width(ctxtid_width-1),.width(64)) rmem_mem5
     (.clk(clk),
      .we(s3_r5_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_rx_wd),
      .re(s1_rd_en),.ra(s1_rd_ctxt[0:ctxtid_width-2]),.rd(s2_rd_d5)
      );

   // rrq0 end
   wire [0:63] 		       s2_rd_d6;
   base_mem#(.addr_width(ctxtid_width-1),.width(64)) rmem_mem6
     (.clk(clk),
      .we(s3_r6_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_rx_wd),
      .re(s1_rd_en),.ra(s1_rd_ctxt[0:ctxtid_width-2]),.rd(s2_rd_d6)
      );

   // croom
   wire [0:croom_width-1]      s2_rd_d7;
   base_mem#(.addr_width(ctxtid_width-1),.width(croom_width)) rmem_mem7   // added -1 to strip off parity kch 
     (.clk(clk),
      .we(i_croom_we),.wa(i_croom_wa),.wd(i_croom_wd),   // i_crom_wa does not have parity kch 
      .re(s1_rd_en),.ra(s1_rd_ctxt[0:ctxtid_width-2]),.rd(s2_rd_d7)
      );

   // ctxt-ctrl
   wire [0:msi_width-1] 	       s2_rd_d8;
   base_mem#(.addr_width(ctxtid_width-1),.width(msi_width)) rmem_mem8
     (.clk(clk),
      .we(s3_r8_we),.wa(s3_ctxt[0:ctxtid_width-2]),.wd(s3_rx_wd[msi_width-1:0]),
      .re(s1_rd_en),.ra(s1_rd_ctxt[0:ctxtid_width-2]),.rd(s2_rd_d8)
      );


   // mux the read results


   wire [0:63] s2_rd_dd0 = s2_rd_d0;
   wire [0:63] s2_rd_dd1 = {{ 64-nintrs{1'b0}},s2_rd_d1};
   wire [0:63] s2_rd_dd3 = {{ 64-nintrs{1'b0}},s2_rd_d3};
   wire [0:63] s2_rd_dd4 = s2_rd_d4;
   wire [0:63] s2_rd_dd5 = s2_rd_d5;
   wire [0:63] s2_rd_dd6 = s2_rd_d6;
   wire [0:63] s2_rd_dd7 = {{ 64-croom_width{1'b0}},s2_rd_d7};
   wire [0:63] s2_rd_dd8 = {1'b1,{63-msi_width{1'b0}},s2_rd_d8}; // 2017/4/23 - use bit 0 (msb) to indicate write_same/unmap support
   //   wire [0:63] s2_rd_dd9 =s2_rd_d9;
   
   wire [0:63] s2_rd_d_b;

   base_mux#(.ways(8),.width(64)) is2rd_mux

     (.sel({s2_rd_addr_dec[0:1], s2_rd_addr_dec[3], s2_rd_addr_dec[4:8]}),
      .din({~s2_rd_dd0, ~s2_rd_dd1, ~s2_rd_dd3, ~s2_rd_dd4, ~s2_rd_dd5, ~s2_rd_dd6, ~s2_rd_dd7, ~s2_rd_dd8}),

      .dout(s2_rd_d_b)
      );

   
   ktms_mmrd_mc_dec#(.mmiobus_width(mmiobus_width),.addr(mmio_ht_addr),.lcladdr_width(lcladdr_width+1)) immrd_dec
     (.clk(clk),.reset(reset),
      .i_mmiobus(i_mmiobus),
      .o_rd_v(s1_rd_v),.o_rd_r(s1_rd_r),.o_rd_addr(s1_rd_addr),.o_rd_ctxt(s1_rd_ctxt),
      .i_rd_v(s2_rd_v),.i_rd_r(s2_rd_r),.i_rd_d(~s2_rd_d_b),.i_rd_cancel(1'b0),
      .o_mmio_rd_v(o_mmio_rd_v),.o_mmio_rd_d(o_mmio_rd_d),.o_perror(o_perror[1])
      );

   capi_parcheck#(.width(ctxtid_width-1)) s1_rd_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s1_rd_v),.i_d(s1_rd_ctxt[0:ctxtid_width-2]),.i_p(s1_rd_ctxt[ctxtid_width-1]),.o_error(s1_perror[2]));


   // context reset
   wire        s2_ctxt_rst_act;
   wire [0:ctxtid_width-1] s1_ctxt_rst_id;
   localparam [0:ctxtid_width-2] ctxtid_one=1;
   
   wire        s1_ctxt_rst_id_par;
   wire [0:ctxtid_width-2]  s1_ctxt_rst_id_plus1 = s1_ctxt_rst_id[0:ctxtid_width-2]+ctxtid_one;
   capi_parity_gen#(.dwidth(9),.width(1)) s1_ctxt_rst_id_pgen(.i_d(s1_ctxt_rst_id_plus1),.o_d(s1_ctxt_rst_id_par));

   base_vlat_en#(.width(ctxtid_width)) is1_ctxt_rst_id_lat(.clk(clk),.reset(reset),.din({s1_ctxt_rst_id_plus1,s1_ctxt_rst_id_par}),.q(s1_ctxt_rst_id),.enable(s2_ctxt_rst_act));

   wire [0:ctxtid_width-1] s2_ctxt_rst_id;
   base_vlat_en#(.width(ctxtid_width)) is2_ctxt_rst_id_lat(.clk(clk),.reset(reset),.din(s1_ctxt_rst_id),.q(s2_ctxt_rst_id),.enable(s2_ctxt_rst_act));

   wire 		   s2_ctxt_rst_v, s2_ctxt_rst_r;
   assign  s2_ctxt_rst_act = s2_ctxt_rst_r | ~s2_ctxt_rst_v;

   // for sending reset reqeust - reset as soon as read
   base_vmem#(.a_width(ctxtid_width-1 ),.rst_ports(2)) ictxt_rst_vmem0
     (.clk(clk),.reset(reset),
      .i_set_v(s3_r4_we & s3_rx_wd[0]),.i_set_a(s3_ctxt[0:ctxtid_width-2]),
      .i_rst_v({s2_ctxt_rst_act, s3_cr_cancel}),.i_rst_a({s2_ctxt_rst_id[0:ctxtid_width-2],s3_ctxt[0:ctxtid_width-2]}),
      .i_rd_en(s2_ctxt_rst_act),.i_rd_a({s1_ctxt_rst_id[0:ctxtid_width-2]}),.o_rd_d(s2_ctxt_rst_v)
      );

   // for rrin register read - reset on ack
   base_vmem#(.a_width(ctxtid_width-1),.rst_ports(2)) ictxt_rst_vmem1
     (.clk(clk),.reset(reset),
      .i_set_v(s3_r4_we & s3_rx_wd[0]),.i_set_a(s3_ctxt[0:ctxtid_width-2]),
      .i_rst_v({i_ctxt_rst_ack_v,s3_cr_cancel}),.i_rst_a({i_ctxt_rst_ack_id[0:ctxtid_width-2],s3_ctxt[0:ctxtid_width-2]}),
      .i_rd_en(s1_rd_en),.i_rd_a(s1_rd_ctxt[0:ctxtid_width-2]),.o_rd_d(s2_rd_d4[63])
      );
   
   // only allow one context reset outstanding at a time
   wire 		   s2_ctxt_rst_outst;
   base_vlat_sr icrst_outst_lat(.clk(clk),.reset(reset),.set(s2_ctxt_rst_v & s2_ctxt_rst_r),.rst(i_ctxt_rst_ack_v),.q(s2_ctxt_rst_outst));

   wire 		   s2d_ctxt_rst_v, s2d_ctxt_rst_r;
   base_agate is2_ctxt_rst_gt(.o_v(s2d_ctxt_rst_v),.o_r(s2d_ctxt_rst_r),.i_v(s2_ctxt_rst_v),.i_r(s2_ctxt_rst_r),.en(~s2_ctxt_rst_outst));
   base_aburp#(.width(ctxtid_width)) is3_ctxt_rst_lat(.clk(clk),.reset(reset),.i_v(s2d_ctxt_rst_v),.i_r(s2d_ctxt_rst_r),.i_d(s2_ctxt_rst_id),.o_v(o_ctxt_rst_v),.o_r(o_ctxt_rst_r),.o_d(o_ctxt_rst_id),.burp_v());
   
   
endmodule // ktms_afu_int
