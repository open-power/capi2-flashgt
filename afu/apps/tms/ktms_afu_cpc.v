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
module ktms_afu_cpc#
  (parameter mmiobus_width=1,
   parameter mmioaddr_cpc=0,
   parameter mmioaddr_mbox=0,
   parameter ctxtid_width=0,
   parameter ctxtcap_width=0
   )
  (
    input 		       clk,
    input 		       reset,
    input 		       i_cfg_capwprot_override, 
    input [0:mmiobus_width-1]  i_mmiobus,

    input 		       i_ctxt_add_v,
    input 		       i_ctxt_rmv_v, 
    input [0:ctxtid_width-1]   i_ctxt_upd_d,

    output 		       o_cap_wr_v,
    output [0:ctxtid_width-1]  o_cap_wr_ctxt,
    output [0:ctxtcap_width-1] o_cap_wr_d,
 
    output 		       o_mmio_rd_v,
    output [0:63] 	       o_mmio_rd_d,
    input 		       i_cfg_mbxclr,
    output [0:2]               o_perror


   );


   localparam ctxtid_start = 5;
   localparam lcladdr_width = 2;

   wire 		      s1a_wr_r, s1a_wr_v;
   wire [0:lcladdr_width-1]   s1a_wr_addr;
   wire 		      s1a_wr_addr_lsb;
   
   wire [0:ctxtid_width-1]    s1a_wr_ctxt;
   wire [0:64] 		      s1a_wr_d;
   wire 		      s1a_wr_dw; 

   wire 		      s1_ctxtupd_v, s1_ctxtupd_r;
   wire [0:ctxtid_width-1]    s1_ctxtupd_d;
   
   base_alatch#(.width(ctxtid_width)) ictxtadd_lat(.clk(clk),.reset(reset),.i_v(i_ctxt_add_v | i_ctxt_rmv_v),.i_r(),.i_d(i_ctxt_upd_d),.o_v(s1_ctxtupd_v),.o_r(s1_ctxtupd_r),.o_d(s1_ctxtupd_d));
   
   wire 		       cpc_cfg;  // this is config space
   wire 		       cpc_rnw;  // read not write
   wire 		       cpc_vld;  // valid 
   wire 		       cpc_dw;   // double word
   wire [0:64] 		       cpc_data;
   wire [0:24]  	       cpc_addr;
   wire [0:4+24+64-1]          cpc_mmiobus;
   assign {cpc_vld,cpc_cfg,cpc_rnw,cpc_dw,cpc_addr,cpc_data} = i_mmiobus;
   assign cpc_mmiobus = {cpc_vld,cpc_cfg,cpc_rnw,cpc_dw,cpc_addr[0:23],cpc_data[0:63]};
   ktms_mmwr_mc_dec#(.mmiobus_width(mmiobus_width-2),.addr(mmioaddr_cpc),.lcladdr_width(lcladdr_width+1),.ctxtid_start(ctxtid_start)) immwr_dec
     (.clk(clk),.reset(reset),
      .i_mmiobus(cpc_mmiobus),
      .o_wr_r(s1a_wr_r),.o_wr_v(s1a_wr_v),.o_wr_addr({s1a_wr_addr,s1a_wr_addr_lsb}),.o_wr_ctxt(s1a_wr_ctxt),.o_wr_d(s1a_wr_d[0:63])
      );

    capi_parity_gen#(.dwidth(64),.width(1)) s1a_wr_d_pgen(.i_d(s1a_wr_d[0:63]),.o_d(s1a_wr_d[64]));
  
   wire 		      s1b_wr_v, s1b_wr_r;
   wire [0:ctxtid_width-1]    s1b_wr_ctxt;
   localparam [0:lcladdr_width-1]    cap_lcladdr = 2;
   localparam [0:lcladdr_width-1]   mbox_lcladdr = 3;
   wire [0:64] 		      s1b_wr_d;
   capi_mmio_mc_reg#(.addr(mmioaddr_mbox)) immio_cmd_addr(.clk(clk),.reset(reset),.i_mmiobus(i_mmiobus),.q(s1b_wr_d),.trg(s1b_wr_v),.ctxt(s1b_wr_ctxt),.o_perror(o_perror[2]));

   wire 		      s1_wr_v, s1_wr_r;
   wire [0:ctxtid_width-1]    s1_wr_ctxt;
   wire [0:lcladdr_width-1]   s1_wr_addr;
   wire [0:64] 		      s1_wr_d;
   wire [0:2] 		      s1_wr_sel;
   
   base_primux#(.width(ctxtid_width+lcladdr_width+65),.ways(3)) is1_wr_mux
     (.i_v({s1b_wr_v,s1a_wr_v,s1_ctxtupd_v}),
      .i_r({s1b_wr_r,s1a_wr_r,s1_ctxtupd_r}),
      .i_d({s1b_wr_ctxt, mbox_lcladdr,                  s1b_wr_d, // mmio write to mbox
	    s1a_wr_ctxt, s1a_wr_addr[0:lcladdr_width-1],s1a_wr_d, // mmio write to cpc reg 
	    s1_ctxtupd_d, cap_lcladdr,                  65'd0}),  // context update
      .o_v(s1_wr_v),
      .o_r(s1_wr_r),
      .o_d({s1_wr_ctxt,s1_wr_addr,s1_wr_d}),
      .o_sel(s1_wr_sel)
      );
   wire 		      s2_wr_v, s2_wr_r;
   wire [0:ctxtid_width-1]    s2_wr_ctxt;
   wire [0:lcladdr_width-1]   s2_wr_addr;
   wire [0:64] 		      s2_wr_d;
   wire 		      s1_wr_mbox = s1_wr_addr == mbox_lcladdr;
   wire 		      s1_wr_cap = s1_wr_addr == cap_lcladdr;
   wire 		      s2_wr_mbox;
   wire 		      s2_wr_cap;
   wire 		      s2_wr_ctxt_upd;
   
   base_alatch#(.width(3+ctxtid_width+lcladdr_width+65)) is2_wr_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_wr_v),
      .i_r(s1_wr_r),
      .i_d({s1_wr_sel[2],s1_wr_mbox,s1_wr_cap,s1_wr_ctxt,s1_wr_addr,s1_wr_d}),
      .o_v(s2_wr_v),
      .o_r(s2_wr_r),
      .o_d({s2_wr_ctxt_upd, s2_wr_mbox,s2_wr_cap,s2_wr_ctxt,s2_wr_addr,s2_wr_d}));

   wire [0:2] 				s1_perror;
   capi_parcheck#(.width(ctxtid_width-1)) s2_wr_ctxt_pcheck (.clk(clk),.reset(reset),.i_v(s2_wr_v),.i_d(s2_wr_ctxt[0:ctxtid_width-2]),.i_p(s2_wr_ctxt[ctxtid_width-1]),.o_error(s1_perror[0]));
   wire [0:2] 				hld_perror;
   wire                                 any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(3)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(3'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(any_hld_perror),.q(o_perror[0]));


   // MMIO READS
   wire 		      s1_rd_v, s1_rd_r;
   wire [0:lcladdr_width-1]     s1_rd_addr;
   wire 			s1_rd_addr_lsb;
   wire [0:ctxtid_width-1]    s1_rd_ctxt;


   wire 		      s2_rd_v, s2_rd_r;

   wire [0:63] 		      s2_rd_qd_b;

   ktms_mmrd_mc_dec#(.mmiobus_width(mmiobus_width),.addr(mmioaddr_cpc),.lcladdr_width(lcladdr_width+1),.ctxtid_start(ctxtid_start)) immrd_dec
     (.clk(clk),.reset(reset),
      .i_mmiobus(i_mmiobus),
      .o_rd_v(s1_rd_v),.o_rd_r(s1_rd_r),.o_rd_addr({s1_rd_addr,s1_rd_addr_lsb}),.o_rd_ctxt(s1_rd_ctxt),
      .i_rd_v(s2_rd_v),.i_rd_r(s2_rd_r),.i_rd_d(~s2_rd_qd_b),.i_rd_cancel(1'b0),
      .o_mmio_rd_v(o_mmio_rd_v),.o_mmio_rd_d(o_mmio_rd_d),.o_perror(o_perror[1]) 
      );

   wire [0:ctxtid_width-1+lcladdr_width-1] s1_rd_a = {s1_rd_ctxt[0:ctxtid_width-2],s1_rd_addr}; 
   wire [0:ctxtid_width-1+lcladdr_width-1] s2_wr_a = {s2_wr_ctxt[0:ctxtid_width-2],s2_wr_addr}; 

   wire 				 s1_rd_mbox = s1_rd_addr == mbox_lcladdr;
   
   wire 				 s1_rd_en = s2_rd_r | ~s2_rd_v;
   wire 				 s2_rd_mbox;
   wire [0:ctxtid_width-1] 		 s2_rd_ctxt;
   base_alatch#(.width(1+ctxtid_width)) s2_rd_lat(.clk(clk),.reset(reset),.i_v(s1_rd_v),.i_r(s1_rd_r),.i_d({s1_rd_mbox,s1_rd_ctxt}),.o_v(s2_rd_v),.o_r(s2_rd_r),.o_d({s2_rd_mbox,s2_rd_ctxt}));
   capi_parcheck#(.width(ctxtid_width-1)) s1_rd_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s1_rd_v),.i_d(s1_rd_ctxt[0:ctxtid_width-2]),.i_p(s1_rd_ctxt[ctxtid_width-1]),.o_error(s1_perror[1]));
   capi_parcheck#(.width(ctxtid_width-1)) s2_rd_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s2_rd_v),.i_d(s2_rd_ctxt[0:ctxtid_width-2]),.i_p(s2_rd_ctxt[ctxtid_width-1]),.o_error(s1_perror[2]));

   wire 				 s2_wr_mbox_read;
   wire s2_cap_write_abort = s2_wr_cap & ~s2_wr_mbox_read & ~s2_wr_ctxt_upd & ~i_cfg_capwprot_override;
   wire s2_wr_en = s2_wr_v & s2_wr_r & ~s2_cap_write_abort;


   wire [0:64] 				 s2_rd_d;
   assign s2_wr_r = 1'b1;
   base_mem#(.width(65),.addr_width(ctxtid_width-1+lcladdr_width)) imem 
     (.clk(clk),
      .re(s1_rd_en),.ra(s1_rd_a[0:ctxtid_width-2+lcladdr_width]),.rd(s2_rd_d),
      .we(s2_wr_en),.wa(s2_wr_a[0:ctxtid_width-2+lcladdr_width]),.wd(s2_wr_d)
      );
   
   wire 				 s2_rd_act = s2_rd_r & s2_rd_v;
   wire 				 s2_rd_mbox_valid;
   wire 				 s2_rd_clr = s2_rd_act & s2_rd_mbox & i_cfg_mbxclr;

   wire 				 s0_ctxt_upd_v = i_ctxt_add_v | i_ctxt_rmv_v;
   base_vmem#(.a_width(ctxtid_width-1),.rst_ports(2)) imbox_vmem 
     (.clk(clk),.reset(reset),
      .i_set_v(s2_wr_v & s2_wr_mbox),              .i_set_a(s2_wr_ctxt[0:ctxtid_width-2]),
      .i_rst_v({s0_ctxt_upd_v,s2_rd_clr}),.i_rst_a({i_ctxt_upd_d[0:ctxtid_width-2],s2_rd_ctxt[0:ctxtid_width-2]}),
      .i_rd_en(s1_rd_en),.i_rd_a(s1_rd_ctxt[0:ctxtid_width-2]), 
      .o_rd_d(s2_rd_mbox_valid)
      );

   base_vmem#(.a_width(ctxtid_width-1),.rst_ports(1)) imbox_read_vmem 
     (.clk(clk),.reset(reset),
      .i_set_v(s1_rd_v & s1_rd_r & s1_rd_mbox), .i_set_a(s1_rd_ctxt[0:ctxtid_width-2]),
      .i_rst_v(s0_ctxt_upd_v),.i_rst_a(i_ctxt_upd_d[0:ctxtid_width-2]),
      .i_rd_en(s1_rd_en),.i_rd_a(s1_rd_ctxt[0:ctxtid_width-2]),
      .o_rd_d(s2_wr_mbox_read)
      );



   wire 				 s2_rd_zero = (s2_rd_mbox & ~s2_rd_mbox_valid);
   assign s2_rd_qd_b = ~(s2_rd_zero ? 64'h0 : s2_rd_d[0:63]); 

   // let remote know about cap update
   assign o_cap_wr_v = (s2_wr_v & s2_wr_cap & ~s2_cap_write_abort);
   assign o_cap_wr_ctxt = s2_wr_ctxt;

   // bit 2 is translation source - implemented in ktms_afu_rht
   assign o_cap_wr_d = {s2_wr_d[0:1],s2_wr_d[3],s2_wr_d[60:63]};

endmodule // ktms_afu_cpc
