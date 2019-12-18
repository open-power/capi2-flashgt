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

module ktms_afu_rht#
  (parameter mmio_cpc_addr=0,
   parameter mmiobus_width=0,
   parameter ctxtid_width=0,
   parameter rh_width=0,
   parameter lba_width=0,
   parameter lidx_width=0,
   parameter aux_width=1,
   parameter rc_width = 8,
   parameter erc_width = 8,
   parameter lunid_width=64,
   parameter lunid_width_w_par= 65,
   parameter ea_width=0,
   parameter tstag_width=0,
   parameter channels=0,
   parameter ssize_width=0,
   parameter dma_rc_width=0,
   parameter [0:dma_rc_width-1] dma_rc_paged=1,
   parameter [0:dma_rc_width-1] dma_rc_addr=1
   
   )
   (input clk,
    input                          reset,
    input      [0:mmiobus_width-1] i_mmiobus,
    input                    [0:3] i_errinj,

    // note when context is removed so that resources can be invalidated
    input                          i_ctxt_rst_v,
    input       [0:ctxtid_width-1] i_ctxt_rst_d,

    // note endianness on a per-context basis 
    input                          i_ec_set,
    input                          i_ec_rst,
    input       [0:ctxtid_width-1] i_ec_id,

    // inbound request interface
    output                         i_req_r,
    input                          i_req_v,
    input                          i_req_ok, // 1 if no errors so far
    input                          i_req_wnr, // write (not read)
    input           [0:rc_width-1] i_req_rc, // current result code (valid when ok=0)
    input          [0:erc_width-1] i_req_erc, // current extended result code (valid when ok=0)
    input        [0:tstag_width-1] i_req_tstag, // timestamp tag
    input       [0:ctxtid_width-1] i_req_ctxt, // context
    input           [0:rh_width-1] i_req_rh, // resource handle
    input          [0:lba_width-1] i_req_lba, // lba
    input                   [0:31] i_req_transfer_len,// cdb transfer length
    input           [0:channels-1] i_req_portmsk, // port mask
    input  [0:lunid_width_w_par-1] i_req_lunid, // lunid
    input          [0:aux_width-1] i_req_aux, // uninterpreted data that we just pass through
    input                          i_req_vrh, // virtual resource - resource translation on 

    // stallcount: performance monitoring 
    output                   [0:2] o_sc_v,
    output                   [0:2] o_sc_r,

    // output (translated) requests
    input                          o_req_r,
    output                         o_req_v,
    output                         o_req_vrh, // resource translation on 
    output                         o_req_plun, // physical lun (rht format 1)
    output                         o_req_ok, // 1 if all ok, 0 if error
    output          [0:rc_width-1] o_req_rc, // afu result code (valid if ok=0)
    output         [0:erc_width-1] o_req_erc, // afu extended result code rc (valid if ok=0)
    output        [0:lidx_width-1] o_req_lidx, // lun index (index into lun table)
    output         [0:lba_width-1] o_req_lba, // lba
    output [0:lunid_width_w_par-1] o_req_lunid, // lunid (non-virtual, or format 1)
    output          [0:channels-1] o_req_portmsk, // valid ports to use

    output         [0:aux_width-1] o_req_aux, // uninterpreted pass-through data

    // tracking for debug and performance
    output                         o_trk_v,
    output       [0:tstag_width-1] o_trk_tag,
    output                  [0:47] o_trk_d,

    // dma get address (0=rht, 1=lxt)
    input                    [0:1] o_get_addr_r,
    output                   [0:1] o_get_addr_v,
    output        [0:ea_width*2-1] o_get_addr_ea,
    output    [0:ctxtid_width*2-1] o_get_addr_ctxt,
    output     [0:ssize_width*2-1] o_get_addr_size,
    output     [0:tstag_width*2-1] o_get_addr_tstag,

    // dma get data (0=rht, 1=lxt)
    output                   [0:1] i_get_data_r,
    input                    [0:1] i_get_data_v,
    input              [0:130*2-1] i_get_data_d,
    input                    [0:1] i_get_data_e,
    input     [0:dma_rc_width*2-1] i_get_data_rc,
    output                   [0:3] o_perror , 
    output                   [0:7] o_vrh_erc_hld
    
    );

   localparam [0:rc_width-1] afuerr_none = 'h00;        // all good
   localparam [0:rc_width-1] afuerr_rht_invalid = 'h01; // rht is invalid
   localparam [0:rc_width-1] afuerr_rht_allign = 'h02;  // rht is misaligned
   localparam [0:rc_width-1] afuerr_rht_bounds = 'h03;  // rht out of bounds access

   localparam [0:rc_width-1] afuerr_rhe_dma = 'h04;    // dma error obtaining rht entry 
   localparam [0:rc_width-1] afuerr_rhe_perm = 'h05;   // entry indicates wrong permissions
   localparam [0:erc_width-1] afuxerr_rht_invalid = 'h01;  // table is invalid
   localparam [0:erc_width-1] afuxerr_rhe_fmt = 'h02;      // entry has invalid format
   localparam [0:erc_width-1] afuxerr_rhe_invalid = 'h03;  // entry is invalid
   
   localparam [0:rc_width-1] afuerr_lxt_allign = 'h12;
   localparam [0:rc_width-1] afuerr_lxt_bounds = 'h13;
   localparam [0:erc_width-1] afuxerr_lxt_vlen = 'h01;  // lxt_bounds error subcode - invalid transfer length
   localparam [0:rc_width-1] afuerr_lxt_dma = 'h14;
   localparam [0:rc_width-1] afuerr_lxt_perm = 'h15;
   localparam [0:rc_width-1] afuerr_xl_badctxt = 'h1a;


   wire [0:2] 			 s0b_v, s0b_r;
   base_acombine#(.ni(1),.no(3)) is0_cmb(.i_v(i_req_v),.i_r(i_req_r),.o_v(s0b_v),.o_r(s0b_r));
				
   wire    		         s1_v, s1_r;
   wire 			 s1_wnr;
   wire 			 s1_vrh; // virtual resource handle specified
   wire [0:rh_width-1] 		 s1_rh;
   wire [0:lba_width-1] 	 s1_lba;
   wire                          s1_transfer_eq_1;
   wire [0:ctxtid_width-1] 	 s1_ctxt;
   wire 			 s1_ok;
   wire [0:rc_width-1] 		 s1_rc;
   wire [0:erc_width-1] 	 s1_erc;
   wire [0:tstag_width-1] 	 s1_tstag;
 	 

   base_aburp_latch#(.width(1+1+rc_width+erc_width+1+rh_width+lba_width+tstag_width+ctxtid_width+1)) is1_lat
     (.clk(clk),.reset(reset),
      .i_r(s0b_r[0]),.i_v(s0b_v[0]),.i_d({i_req_ok,i_req_wnr,i_req_rc,i_req_erc,i_req_vrh,i_req_rh,i_req_lba,i_req_tstag,i_req_ctxt, (i_req_transfer_len==32'h1)}),
      .o_r(s1_r),    .o_v(s1_v),    .o_d({s1_ok,      s1_wnr,   s1_rc,   s1_erc,   s1_vrh,   s1_rh,   s1_lba,   s1_tstag,   s1_ctxt, s1_transfer_eq_1}));

   wire [0:64] 			 mmio_rht0_d, mmio_rht1_d, mmio_rht2_d;  
   wire [0:ctxtid_width-1] 	 mmio_rht0_ctxt, mmio_rht1_ctxt, mmio_rht2_ctxt;
   wire 			 mmio_rht0_v, mmio_rht1_v, mmio_rht2_v;
   capi_mmio_mc_reg#(.addr(mmio_cpc_addr),.ctxtid_start(5))   immio_rht0(.clk(clk),.reset(reset),.i_mmiobus(i_mmiobus),.q(mmio_rht0_d),.trg(mmio_rht0_v),.ctxt(mmio_rht0_ctxt),.o_perror(o_perror[1])); 
   capi_mmio_mc_reg#(.addr(mmio_cpc_addr+2),.ctxtid_start(5)) immio_rht1(.clk(clk),.reset(reset),.i_mmiobus(i_mmiobus),.q(mmio_rht1_d),.trg(mmio_rht1_v),.ctxt(mmio_rht1_ctxt),.o_perror(o_perror[2]));
   capi_mmio_mc_reg#(.addr(mmio_cpc_addr+4),.ctxtid_start(5)) immio_rht2(.clk(clk),.reset(reset),.i_mmiobus(i_mmiobus),.q(mmio_rht2_d),.trg(mmio_rht2_v),.ctxt(mmio_rht2_ctxt),.o_perror(o_perror[3]));

   wire [0:7]                    s1_perror;
   capi_parcheck#(.width(ea_width-1)) mmio_rht2_d_pcheck(.clk(clk),.reset(reset),.i_v(mmio_rht2_v),.i_d(mmio_rht2_d[0:ea_width-2]),.i_p(mmio_rht2_d[ea_width-1]),.o_error(s1_perror[0]));
   wire [0:7] 				hld_perror;
   wire  				any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(8)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(8'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror),.q(o_perror[0]));
   wire 			 cpc_set_v = mmio_rht2_v & mmio_rht2_d[2];
   wire 			 cpc_rst_v = mmio_rht2_v & ~mmio_rht2_d[2];

   
   // stage 2: memory read data
   wire 			 s2_r, s2_v;
   wire 			 s2_vrh;
   wire 			 s2_wnr;
   
   wire [0:rh_width-1] 		 s2_rh;
   wire [0:lba_width-1] 	 s2_lba;
   wire                          s2_transfer_eq_1;
   wire [0:tstag_width-1] 	 s2_tstag;
   wire 			 s1_rd_en = s2_r | ~s2_v;
   wire [0:ea_width-1]		 s2_rht0_d, s2_rht1_d;
   wire  			 s2_rht0_v;
   wire  			 s2_rht1_v;
   wire 			 s2_ok;
   wire [0:rc_width-1] 		 s2_rc;
   wire [0:erc_width-1] 	 s2_erc;


   base_mem#(.width(ea_width),.addr_width(ctxtid_width-1)) irht0_mem(.clk(clk),.we(mmio_rht0_v),.wa(mmio_rht0_ctxt[0:ctxtid_width-2]),.wd(mmio_rht0_d),.ra(s1_ctxt[0:ctxtid_width-2]),.re(s1_rd_en),.rd(s2_rht0_d));
   base_mem#(.width(ea_width),.addr_width(ctxtid_width-1)) irht1_mem(.clk(clk),.we(mmio_rht1_v),.wa(mmio_rht1_ctxt[0:ctxtid_width-2]),.wd(mmio_rht1_d),.ra(s1_ctxt[0:ctxtid_width-2]),.re(s1_rd_en),.rd(s2_rht1_d));
   base_vmem#(.a_width(ctxtid_width-1)) irht0_vmem(.clk(clk),.reset(reset),.i_set_a(mmio_rht0_ctxt[0:ctxtid_width-2]),.i_set_v(mmio_rht0_v),.i_rst_a(i_ctxt_rst_d[0:ctxtid_width-2]),.i_rst_v(i_ctxt_rst_v),.i_rd_a(s1_ctxt[0:ctxtid_width-2]),.i_rd_en(s1_rd_en),.o_rd_d(s2_rht0_v));
   base_vmem#(.a_width(ctxtid_width-1)) irht1_vmem(.clk(clk),.reset(reset),.i_set_a(mmio_rht1_ctxt[0:ctxtid_width-2]),.i_set_v(mmio_rht1_v),.i_rst_a(i_ctxt_rst_d[0:ctxtid_width-2]),.i_rst_v(i_ctxt_rst_v),.i_rd_a(s1_ctxt[0:ctxtid_width-2]),.i_rd_en(s1_rd_en),.o_rd_d(s2_rht1_v));


   base_alatch#(.width(1+rc_width+erc_width+1+rh_width+lba_width+tstag_width+1+1)) is2_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_v),.i_r(s1_r),.i_d({s1_ok,s1_rc,s1_erc,s1_vrh,s1_rh,s1_lba,s1_tstag,s1_wnr,s1_transfer_eq_1}),
      .o_v(s2_v),.o_r(s2_r),.o_d({s2_ok,s2_rc,s2_erc,s2_vrh,s2_rh,s2_lba,s2_tstag,s2_wnr,s2_transfer_eq_1}));

   capi_parcheck#(.width(ea_width-1)) s2_rht1_d_pcheck(.clk(clk),.reset(reset),.i_v(s2_v & s2_vrh),.i_d(s2_rht1_d[0:ea_width-2]),.i_p(s2_rht1_d[ea_width-1]),.o_error(s1_perror[1])); 

   wire [0:15] 			 s2_rht_cnt = s2_rht1_d[0:15];
   wire                          s2_rht_ctxt_par;
   wire [0:ctxtid_width-1] 	 s2_rht_ctxt = {s2_rht1_d[31-ctxtid_width+2:31],s2_rht_ctxt_par}; 
   capi_parity_gen#(.dwidth(ctxtid_width-1),.width(1)) s2_rht_ctxt_pgen(.i_d(s2_rht_ctxt[0:ctxtid_width-2]),.o_d(s2_rht_ctxt_par));
   capi_parcheck#(.width(ea_width-1)) s2_rht0_pcheck(.clk(clk),.reset(reset),.i_v(s2_v & s2_vrh),.i_d(s2_rht0_d[0:ea_width-2]),.i_p(s2_rht0_d[ea_width-1]),.o_error(s1_perror[2])); 
   
   
   wire [0:ea_width-1] 		 s2_rht_addr;
   assign s2_rht_addr[0:ea_width-2] = s2_rht0_d[0:ea_width-2] + {s2_rh,4'd0};
   capi_parity_gen#(.dwidth(ea_width-1),.width(1)) s2_rht_addr_pgen(.i_d(s2_rht_addr[0:ea_width-2]),.o_d(s2_rht_addr[ea_width-1])); 
   wire 			 s2_rht_rhv = s2_rht_cnt > s2_rh;
   wire 			 s2_rht_v = s2_rht0_v & s2_rht1_v;
   wire 			 s2_rht_algn_err = | s2_rht0_d[60:63];
   

   // stage 3: send address   
   wire 			     s3_v, s3_r;
   wire 			     s3_vrh;
   wire 			     s3_wnr;
   wire [0:lba_width-1] 	     s3_lba;
   wire                              s3_transfer_eq_1;
   wire [0:ctxtid_width-1] 	     s3_rht_ctxt;
   wire [0:ea_width-1] 		     s3_rht_addr;
   wire 			     s3_rht_v, s3_rht_rhv, s3_rht_algn_err;
   wire 			     s3_ok_in;
   wire [0:rc_width-1] 		     s3_rc_in;
   wire [0:erc_width-1] 	     s3_erc_in;
   wire [0:tstag_width-1] 	     s3_tstag;
   wire 			     s2_re;
   base_alatch_oe#(.width(1+rc_width+erc_width+4+lba_width+ctxtid_width+ea_width+tstag_width+1+1)) is3_lat
     (.clk(clk),.reset(reset),
      .i_v(s2_v),.i_r(s2_r),.i_d({s2_ok,   s2_rc,    s2_erc,    s2_vrh,s2_rht_v,s2_rht_rhv,s2_rht_algn_err,s2_lba,s2_rht_ctxt,s2_rht_addr,s2_tstag,s2_wnr,s2_transfer_eq_1}),
      .o_v(s3_v),.o_r(s3_r),.o_d({s3_ok_in,s3_rc_in, s3_erc_in, s3_vrh,s3_rht_v,s3_rht_rhv,s3_rht_algn_err,s3_lba,s3_rht_ctxt,s3_rht_addr,s3_tstag,s3_wnr,s3_transfer_eq_1}),.o_en(s2_re));
   wire 			     s3_ec;
   base_vmem#(.a_width(ctxtid_width-1)) iec_mem(.clk(clk),.reset(reset),.i_set_v(i_ec_set),.i_set_a(i_ec_id[0:ctxtid_width-2]),.i_rst_v(i_ec_rst),.i_rst_a(i_ec_id[0:ctxtid_width-2]),.i_rd_en(s2_re),.i_rd_a(s2_rht_ctxt[0:ctxtid_width-2]),.o_rd_d(s3_ec));

   wire 		 s3_rht_ok = s3_ok_in & s3_rht_v & s3_rht_rhv & ~s3_rht_algn_err;
   wire [0:2] 		 s3_err_mux_sel;
   wire 		 s3_rc_rht_inv = ~s3_rht_v;
   wire 		 s3_rc_rht_rh_inv = ~s3_rht_rhv;
   wire 		 s3_rc_rht_align_inv = s3_rht_algn_err;
   base_prienc_hp#(.ways(3)) is3_prienc(.din({s3_rc_rht_inv, s3_rc_rht_rh_inv,s3_rc_rht_align_inv}),.dout(s3_err_mux_sel),.kill());
   wire [0:rc_width-1] 	 s3_tr_rc;
   wire [0:erc_width-1]  s3_tr_erc;
   localparam [0:erc_width-1] erc_ok = 0;
   base_mux#(.ways(3),.width(rc_width+erc_width)) is3_rc_mux
     (.sel(s3_err_mux_sel),
      .din({afuerr_rht_invalid,afuxerr_rht_invalid,
	    afuerr_rht_bounds,erc_ok,
	    afuerr_rht_allign,erc_ok}),.dout({s3_tr_rc,s3_tr_erc}));

   wire [0:rc_width-1] 	 s3_ntr_rc = afuerr_none;
   wire 		 s3_ok;
   wire [0:rc_width-1] 	 s3_rc;
   wire [0:erc_width-1]  s3_erc;

   ktms_afu_errmux#(.rc_width(rc_width+erc_width)) is3err_mux(.i_rc({s3_rc_in,s3_erc_in}),.i_ok(s3_ok_in),.i_err((~s3_rht_ok) & s3_vrh),.i_err_rc({s3_tr_rc,s3_tr_erc}),.o_rc({s3_rc,s3_erc}),.o_ok(s3_ok));

   // monitor input to this stage for backup   
   assign o_sc_v[0] = s3_v;
   assign o_sc_r[0] = s3_r;
   
   wire [0:1] s3b_v, s3b_r;
   base_acombine#(.ni(1),.no(2)) is3a_cmb(.i_v(s3_v),.i_r(s3_r),.o_v(s3b_v),.o_r(s3b_r));

   //only send address if all is good
   base_afilter is3_fltr(.i_v(s3b_v[0]),.i_r(s3b_r[0]),.o_v(o_get_addr_v[0]),.o_r(o_get_addr_r[0]),.en(s3_ok & s3_vrh));
   base_const#(.width(ssize_width),.value(16)) is3get_size(o_get_addr_size[0:ssize_width-1]);
   assign o_get_addr_ctxt[0:ctxtid_width-1] = s3_rht_ctxt;
   assign o_get_addr_tstag[0:tstag_width-1] = s3_tstag;
   assign o_get_addr_ea[0:ea_width-1] = s3_rht_addr;

   // stage 4: rendevous with data
   wire [0:1]                  s4a_v, s4a_r;
   wire 		       s4_vrh;
   wire 		       s4_wnr;
   wire 		       s4_ok_in;
   wire [0:tstag_width-1]      s4_tstag;   
   wire [0:rc_width-1] 	       s4_rc_in;
   wire [0:erc_width-1]        s4_erc_in;
   wire [0:lba_width-1]        s4_lba;
   wire                        s4_transfer_eq_1;
   wire [0:ctxtid_width-1]     s4_rht_ctxt;
   wire 		       s4_ec;
   base_fifo#(.LOG_DEPTH(4),.width(1+1+rc_width+erc_width+lba_width+ctxtid_width+1+tstag_width+1+1),.output_reg(1)) is4_lat
     (.clk(clk),.reset(reset),
      .i_v(s3b_v[1]),.i_r(s3b_r[1]),.i_d({s3_vrh,s3_ok,    s3_rc,    s3_erc,    s3_lba, s3_rht_ctxt, s3_ec,s3_tstag,s3_wnr,s3_transfer_eq_1}),
      .o_v(s4a_v[1]),.o_r(s4a_r[1]),.o_d({s4_vrh,s4_ok_in, s4_rc_in, s4_erc_in, s4_lba, s4_rht_ctxt, s4_ec,s4_tstag,s4_wnr,s4_transfer_eq_1}));
   base_aforce is4_frc(.i_v(i_get_data_v[0]),.i_r(i_get_data_r[0]),.o_v(s4a_v[0]),.o_r(s4a_r[0]),.en(s4_ok_in & s4_vrh));
  
   capi_parcheck#(.width(64)) i_get_data_d_pcheck0(.clk(clk),.reset(reset),.i_v(i_get_data_v[0]),.i_d(i_get_data_d[0:63]),.i_p(i_get_data_d[128]),.o_error(s1_perror[3]));
   capi_parcheck#(.width(64)) i_get_data_d_pcheck1(.clk(clk),.reset(reset),.i_v(i_get_data_v[1]),.i_d(i_get_data_d[64:127]),.i_p(i_get_data_d[129]),.o_error(s1_perror[4]));
 
   wire [0:ea_width-1] s4_lxt_start_lunid;
   wire [0:31] s4_lxt_cnt;
   base_endian_mux#(.bytes(8)) is4_szl0(.i_ctrl(s4_ec),.i_d(i_get_data_d[0:63]),.o_d(s4_lxt_start_lunid[0:ea_width-2]));  
   base_endian_mux#(.bytes(4)) is4_szl1(.i_ctrl(s4_ec),.i_d(i_get_data_d[64:95]),.o_d(s4_lxt_cnt)); 
   wire [0:3]  s4_lxt_fmt = i_get_data_d[112:115];
   wire        s4_lunid_vld = i_get_data_d[64];
   wire        s4_lxt_wp = i_get_data_d[118];
   wire        s4_lxt_rp = i_get_data_d[119];
   assign       s4_lxt_start_lunid[ea_width-1] = i_get_data_d[128];
   wire [0:channels-1] s4_fmt1_pmsk;
   base_bitswap#(.width(channels)) is4_fmt_pmsk_swp(.i_d(i_get_data_d[128-channels:127]),.o_d(s4_fmt1_pmsk));

   wire 		 s4_fmt_zero = (s4_lxt_fmt == 4'd0) & s4_vrh;
   wire 		 s4_fmt_one = (s4_lxt_fmt == 4'd1) & s4_vrh;

   wire [0:dma_rc_width-1] s4_dmarc = i_errinj[0] ? dma_rc_paged : (i_errinj[1] ? dma_rc_addr : i_get_data_rc[0:dma_rc_width-1]);

   /* five possible errors in order of priority */
   wire 		 s4_dma_err = | s4_dmarc ;
   wire 		 s4_fmt_err = (| s4_lxt_fmt[1:2]) & s4_vrh; 
   wire 		 s4_inv_err = s4_fmt_one & ~s4_lunid_vld;
   wire 		 s4_perm_err = (s4_wnr ? ~s4_lxt_wp : ~s4_lxt_rp) & s4_vrh;  
   wire                  s4_vlength_err = s4_fmt_zero & ~s4_transfer_eq_1;
   
	
   localparam nmsk_width = 8;
   wire [0:nmsk_width-1] s4_lxt_nmsk = i_get_data_d[120:127];

   

   wire [0:rc_width-1] 	   s4_err_rc = 
			     s4_dma_err                ? afuerr_rhe_dma : 
			     (s4_fmt_err | s4_inv_err) ? afuerr_rht_invalid:
                             s4_perm_err               ? afuerr_rhe_perm:
                                                         afuerr_lxt_bounds; // vlength_err

   wire [0:erc_width-1]    s4_err_erc = 
			     s4_dma_err  ? s4_dmarc : 
			     s4_fmt_err  ? afuxerr_rhe_fmt  :
			     s4_inv_err  ? afuxerr_rhe_invalid :
			     s4_perm_err ? erc_ok :
                                           afuxerr_lxt_vlen;
   
   wire 		   s4_err_v = (s4_dma_err | s4_fmt_err | s4_inv_err | s4_perm_err | s4_vlength_err) & s4_vrh;
   wire [0:7]              vrh_error_hld;
   wire [0:7]              vrh_error_in = (s4_err_v & s4a_v[1] & (vrh_error_hld == 8'h00)) ? s4_err_erc : vrh_error_hld;

   base_vlat#(.width(8)) ivrherclat(.clk(clk),.reset(reset),.din(vrh_error_in),.q(vrh_error_hld));
   assign o_vrh_erc_hld = vrh_error_hld;

      
   
   wire [0:erc_width-1]  s4_erc;
   wire [0:rc_width-1] 	 s4_rc;
   wire 		 s4_ok;
   ktms_afu_errmux#(.rc_width(rc_width+erc_width)) is4err_mux(.i_rc({s4_rc_in,s4_erc_in}),.i_ok(s4_ok_in),.i_err(s4_err_v),.i_err_rc({s4_err_rc,s4_err_erc}),.o_rc({s4_rc,s4_erc}),.o_ok(s4_ok));

   wire s4b_v, s4b_r;
   base_acombine#(.ni(2),.no(1)) is4_cmb(.i_v(s4a_v),.i_r(s4a_r),.o_v(s4b_v),.o_r(s4b_r));

   wire                    s5_v, s5_r;
   wire 		   s5_vrh;
   wire [0:1] 		   s5_fmt;
   wire [0:channels-1] 	   s5_fmt1_pmsk;
   wire 		   s5_wnr;
   wire 		   s5_ok_in;
   wire [0:rc_width-1] 	   s5_rc_in;
   wire [0:erc_width-1]    s5_erc_in;
   wire [0:lba_width-1]    s5_lba;
   wire [0:tstag_width-1]  s5_tstag;   
   wire [0:nmsk_width-1]   s5_lxt_nmsk;
   wire [0:ea_width-1] 	   s5_lxt_start_lunid;
   wire [0:31] 		   s5_lxt_cnt;
   wire [0:ctxtid_width-1] s5_rht_ctxt;
   wire 		   s5_ec;
  
   base_alatch#(.width(1+1+1+1+rc_width+erc_width+lba_width+nmsk_width+ea_width+32+ctxtid_width+1+tstag_width+1+channels)) is5_lat
   (.clk(clk),.reset(reset),
    .i_v(s4b_v),  .i_r(s4b_r),.i_d({s4_vrh,s4_ok,    s4_fmt_zero, s4_fmt_one, s4_rc,    s4_erc,    s4_lba,s4_lxt_nmsk,s4_lxt_start_lunid,s4_lxt_cnt,s4_rht_ctxt,s4_ec,s4_tstag,s4_wnr,s4_fmt1_pmsk}),
    .o_v(s5_v),   .o_r(s5_r), .o_d({s5_vrh,s5_ok_in, s5_fmt[0:1]            , s5_rc_in, s5_erc_in, s5_lba,s5_lxt_nmsk,s5_lxt_start_lunid,s5_lxt_cnt,s5_rht_ctxt,s5_ec,s5_tstag,s5_wnr,s5_fmt1_pmsk}));

   wire [0:nmsk_width-1] s5_ntr_nmsk;
   base_const#(.value(lba_width),.width(nmsk_width)) is5_ntr_nmsk(s5_ntr_nmsk);
   
   // preserve lba if translation is off
   wire [0:nmsk_width-1] s5_nmsk = (s5_vrh & s5_fmt[0]) ? s5_lxt_nmsk : s5_ntr_nmsk;

   // stage 5 compute chunk and mask
   wire [0:lba_width-1] s5_chunk;
   base_shift_right#(.swidth(nmsk_width),.width(lba_width)) is5_shftr(.i_samt(s5_nmsk),.i_d(s5_lba),.o_d(s5_chunk));

   // extract offset
   wire [0:lba_width-1] s5_lba_msk_b;

   base_shift_left#(.swidth(nmsk_width),.width(lba_width)) is5_shftl(.i_samt(s5_nmsk),.i_d({lba_width{1'b1}}),.o_d(s5_lba_msk_b));
   wire [0:lba_width-1] s5_lba_lsb = s5_lba & ~s5_lba_msk_b;

   // detect alignment error
   capi_parcheck#(.width(64)) s5_lxt_start_lunid_pcheck(.clk(clk),.reset(reset),.i_v(s5_v & s5_vrh),.i_d(s5_lxt_start_lunid[0:ea_width-2]),.i_p(s5_lxt_start_lunid[ea_width-1]),.o_error(s1_perror[5])); 
   wire 		s5_tr_err = s5_fmt[0] & (|(s5_lxt_start_lunid[61:63])); 
   
   wire s5_ok;
   wire [0:rc_width-1] s5_rc;
   wire [0:erc_width-1] s5_erc;
   ktms_afu_errmux#(.rc_width(rc_width+erc_width)) is5err_mux(.i_rc({s5_rc_in,s5_erc_in}),.i_ok(s5_ok_in),.i_err(s5_tr_err & s5_vrh),.i_err_rc({afuerr_lxt_allign,erc_ok}),.o_rc({s5_rc,s5_erc}),.o_ok(s5_ok));
   
   // lots of shifting - better latch!
   wire                   s6_v, s6_r;
   wire 		  s6_vrh;
   wire 		  s6_wnr;
   wire [0:1] 		  s6_fmt;
   wire [0:channels-1] 	  s6_fmt1_pmsk;
      wire 		  s6_ok_in;
   wire [0:rc_width-1] 	  s6_rc_in;
   wire [0:erc_width-1]   s6_erc_in;
   wire [0:nmsk_width-1]  s6_lxt_nmsk;
   wire [0:lba_width-1]   s6_chunk;
   wire [0:tstag_width-1] s6_tstag;   
   wire [0:lba_width-1]   s6_lba_lsb;
   wire [0:ea_width-1] 	  s6_lxt_start_lunid;
   wire [0:31] 		  s6_lxt_cnt;
   wire [0:ctxtid_width-1] s6_rht_ctxt;
   wire 		   s6_ec;
   
   base_alatch#(.width(1+1+2+rc_width+erc_width+nmsk_width+lba_width+lba_width+ea_width+32+ctxtid_width+1+tstag_width+1+channels)) is6_lat
   (.clk(clk),.reset(reset),
   .i_v(s5_v),.i_r(s5_r),.i_d({s5_vrh,s5_ok,   s5_fmt,s5_rc,   s5_erc,    s5_nmsk,    s5_chunk,s5_lba_lsb,s5_lxt_start_lunid,s5_lxt_cnt,s5_rht_ctxt,s5_ec,s5_tstag,s5_wnr,s5_fmt1_pmsk}),
   .o_v(s6_v),.o_r(s6_r),.o_d({s6_vrh,s6_ok_in,s6_fmt,s6_rc_in,s6_erc_in, s6_lxt_nmsk,s6_chunk,s6_lba_lsb,s6_lxt_start_lunid,s6_lxt_cnt,s6_rht_ctxt,s6_ec,s6_tstag,s6_wnr,s6_fmt1_pmsk}));

   // stage 6: compute address
   capi_parcheck#(.width(64)) s6_lxt_start_lunid_pcheck(.clk(clk),.reset(reset),.i_v(s6_v & s6_vrh),.i_d(s6_lxt_start_lunid[0:ea_width-2]),.i_p(s6_lxt_start_lunid[ea_width-1]),.o_error(s1_perror[6]));
   wire                   s6_get_ea_par;
   wire [0:ea_width-1] s6_get_ea;
   assign s6_get_ea[0:ea_width-2] = s6_lxt_start_lunid[0:ea_width-2] + {s6_chunk,3'b0};
   assign s6_get_ea[ea_width-1] = s6_get_ea_par;
   
   capi_parity_gen#(.dwidth(ea_width-1),.width(1)) s6_get_ea_pgen(.i_d(s6_get_ea[0:ea_width-2]),.o_d(s6_get_ea_par)); 
   wire s6_lba_ok = s6_chunk < s6_lxt_cnt;
   wire s6_tr_err = s6_fmt[0] & (~s6_lba_ok);
   wire s6_ok;
   wire [0:rc_width-1] s6_rc;
   wire [0:erc_width-1] s6_erc;
   ktms_afu_errmux#(.rc_width(rc_width+erc_width)) is6err_mux(.i_rc({s6_rc_in,s6_erc_in}),.i_ok(s6_ok_in),.i_err(s6_tr_err & s6_vrh),.i_err_rc({afuerr_lxt_bounds,erc_ok}),.o_rc({s6_rc,s6_erc}),.o_ok(s6_ok));
   

   wire                  s7a_v, s7a_r;
   wire 		 s7_vrh;
   wire [0:1] 		 s7_fmt;
   wire [0:channels-1] 	 s7_fmt1_pmsk;
   wire 		 s7_wnr;
   wire 		 s7_ok;
   wire [0:rc_width-1] 	 s7_rc;
   wire [0:erc_width-1]  s7_erc;
   wire [0:tstag_width-1] s7_tstag;   
   wire [ea_width-1:0] 	  s7_get_ea;
//   wire 		  s7_dmux_sel = s7_get_ea[3];
   wire [0:nmsk_width-1]  s7_lxt_nmsk;
   wire [0:lba_width-1]   s7_lba_lsb;
   wire [0:ctxtid_width-1] s7_rht_ctxt;
   wire 		   s7_ec;
   wire [0:lunid_width_w_par-1]  s7_fmt1_lunid;

   assign o_trk_v = s6_v;
   assign o_trk_tag = s6_tstag;
   // 8 bits fmt, 8bits nmsk, 32 bits cnt
   assign o_trk_d = {6'b0,s6_fmt,s6_lxt_nmsk,s6_lxt_cnt};


   base_alatch#(.width(1+1+2+rc_width+erc_width+ea_width+nmsk_width+lunid_width_w_par+lba_width+ctxtid_width+1+tstag_width+1+channels)) is7_lat    
   (.clk(clk),.reset(reset),
    .i_v(s6_v), .i_r(s6_r), .i_d({s6_vrh,s6_ok,s6_fmt,s6_rc,   s6_erc,    s6_get_ea,s6_lxt_nmsk,s6_lxt_start_lunid,s6_lba_lsb,s6_rht_ctxt,s6_ec,s6_tstag,s6_wnr,s6_fmt1_pmsk}),
    .o_v(s7a_v),.o_r(s7a_r),.o_d({s7_vrh,s7_ok,s7_fmt,s7_rc,   s7_erc,    s7_get_ea,s7_lxt_nmsk,s7_fmt1_lunid,     s7_lba_lsb,s7_rht_ctxt,s7_ec,s7_tstag,s7_wnr,s7_fmt1_pmsk}));
   
   // stage 7: send address
   wire [0:1] s7b_v, s7b_r;
   base_acombine#(.ni(1),.no(2)) is7_cmb(.i_v(s7a_v),.i_r(s7a_r),.o_v(s7b_v),.o_r(s7b_r));
   base_afilter is7_fltr(.i_v(s7b_v[0]),.i_r(s7b_r[0]),.o_v(o_get_addr_v[1]),.o_r(o_get_addr_r[1]),.en(s7_ok & s7_vrh & s7_fmt[0]));
   assign o_get_addr_ctxt[ctxtid_width:ctxtid_width*2-1] = s7_rht_ctxt;
   assign o_get_addr_tstag[tstag_width:tstag_width*2-1] = s7_tstag;
   base_const#(.width(ssize_width),.value(8)) is7get_size(o_get_addr_size[ssize_width:ssize_width*2-1]);
   assign o_get_addr_ea[ea_width:(ea_width*2)-1] = s7_get_ea;
   
   wire [0:2] s8a_v, s8a_r;
   wire [0:1] s8_fmt;
   wire [0:channels-1] s8_fmt1_pmsk;
   wire s8_vrh;
   wire s8_wnr;
   wire s8_ok_in;
   wire [0:rc_width-1] s8_rc_in;
   wire [0:erc_width-1] s8_erc_in;
//   wire s8_dmux_sel;
   wire [0:nmsk_width-1] s8_lxt_nmsk;
   wire [0:lba_width-1] s8_lba_lsb;
   wire [0:ctxtid_width-1] s8_rht_ctxt;
   wire 		   s8_ec;
   wire [0:lunid_width_w_par-1]  s8_fmt1_lunid;
   // monitor input to this stage for backup   
   assign o_sc_v[1] = s7b_v[1];
   assign o_sc_r[1] = s7b_r[1];
   
   base_fifo#(.LOG_DEPTH(4),.width(1+1+2+rc_width+erc_width+nmsk_width+lunid_width_w_par+lba_width+ctxtid_width+1+1+channels),.output_reg(1)) is8_lat
   (.clk(clk),.reset(reset),
    .i_v(s7b_v[1]),.i_r(s7b_r[1]),.i_d({s7_vrh,s7_ok,   s7_fmt,s7_rc,   s7_erc,   s7_lxt_nmsk,s7_fmt1_lunid,s7_lba_lsb,s7_rht_ctxt,s7_ec,s7_wnr,s7_fmt1_pmsk}),
    .o_v(s8a_v[1]),.o_r(s8a_r[1]),.o_d({s8_vrh,s8_ok_in,s8_fmt,s8_rc_in,s8_erc_in,s8_lxt_nmsk,s8_fmt1_lunid,s8_lba_lsb,s8_rht_ctxt,s8_ec,s8_wnr,s8_fmt1_pmsk}));

   capi_parcheck#(.width(ctxtid_width-1)) s8_rht_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s8a_v[1] & s8_vrh),.i_d(s8_rht_ctxt[0:ctxtid_width-2]),.i_p(s8_rht_ctxt[ctxtid_width-1]),.o_error(s1_perror[7])); 

   wire [0:channels-1] 	s8_ntr_pmsk;
   wire [0:lunid_width_w_par-1] s8_org_lunid;

   // monitor input to this stage for backup   
   assign o_sc_v[2] = s0b_v[0];
   assign o_sc_r[2] = s0b_r[0];

   base_fifo#(.LOG_DEPTH(5),.width(lunid_width_w_par+channels)) intr_s8
     (.clk(clk),.reset(reset),
      .i_v(s0b_v[2]),.i_r(s0b_r[2]),.i_d({i_req_lunid,i_req_portmsk}),
      .o_v(s8a_v[2]),.o_r(s8a_r[2]),.o_d({s8_org_lunid,s8_ntr_pmsk}));

   wire [0:lunid_width_w_par-1] s8_lunid = s8_vrh & s8_fmt[1] ? s8_fmt1_lunid : s8_org_lunid;

   // stage 8: get result
   wire 		  s8_frc_en = s8_ok_in & s8_vrh & s8_fmt[0];
   base_aforce is8_frc(.i_v(i_get_data_v[1]),.i_r(i_get_data_r[1]),.o_v(s8a_v[0]),.o_r(s8a_r[0]),.en(s8_frc_en));
   wire 		  s8b_v, s8b_r;
   base_acombine#(.ni(3),.no(1)) is8_cmb(.i_v(s8a_v),.i_r(s8a_r),.o_v(s8b_v),.o_r(s8b_r));
   wire [0:63] 		  s8_get_data_d0;
   assign s8_get_data_d0 = i_get_data_d[130:130+63];
   
   
   wire [0:63] 		  s8_get_data_d1;
   base_endian_mux#(.bytes(8)) is8_szl(.i_ctrl(s8_ec),.i_d(s8_get_data_d0),.o_d(s8_get_data_d1));

   wire [47:0] 		  s8_chunk_raw = s8_get_data_d1[0:47];
   wire [7:0] 		  s8_lidx_raw = s8_get_data_d1[48:55];
         
   wire [0:lba_width-1]   s8_chunk = s8_chunk_raw[lba_width-1:0];

   // force to 0 on error so we don't get "X" showing up when we write the port field of ioasa
   wire [0:lidx_width-1]  s8_lidx    = s8_lidx_raw[lidx_width-1:0];
   wire [0:3] 		  s8_tr_pmsk = s8_fmt[0] ? {s8_get_data_d1[63],s8_get_data_d1[62],s8_get_data_d1[61],s8_get_data_d1[60]} : s8_fmt1_pmsk;

   wire 			 s8_perm_wp = s8_get_data_d1[58];
   wire 			 s8_perm_rp = s8_get_data_d1[59];
   wire 			 s8_perm_err = (s8_wnr ? ~s8_perm_wp : ~s8_perm_rp);
   

   wire [0:lba_width-1] 	 s8_lba_msb;
   base_shift_left#(.swidth(nmsk_width),.width(lba_width)) is8_shftl(.i_samt(s8_lxt_nmsk),.i_d(s8_chunk),.o_d(s8_lba_msb));
   wire [0:lba_width-1] 	 s8_lba = s8_lba_msb | s8_lba_lsb;
   wire [0:dma_rc_width-1] 	 s8_dmarc = i_errinj[2] ? dma_rc_paged : (i_errinj[3] ? dma_rc_addr : i_get_data_rc[dma_rc_width:dma_rc_width*2-1]);

   wire 			 s8_dma_err = | s8_dmarc ;
   wire [0:rc_width-1] 		 s8_err_rc = s8_dma_err ? afuerr_lxt_dma : afuerr_lxt_perm;
   wire [0:erc_width-1] 	 s8_err_erc = s8_dma_err ? s8_dmarc : {erc_width{1'b0}};
   wire 			 s8_err_v = (s8_dma_err | s8_perm_err) & s8_vrh & s8_fmt[0];
   
   wire 			 s8_ok;
   wire [0:rc_width-1] 		 s8_rc;
   wire [0:erc_width-1] 	 s8_erc;
   
   wire [0:channels-1] 		 s8_pmsk = s8_vrh ? s8_tr_pmsk : s8_ntr_pmsk;
   ktms_afu_errmux#(.rc_width(rc_width+erc_width)) is8err_mux(.i_rc({s8_rc_in,s8_erc_in}),.i_ok(s8_ok_in),.i_err(s8_err_v),.i_err_rc({s8_err_rc,s8_err_erc}),.o_rc({s8_rc,s8_erc}),.o_ok(s8_ok));

   wire 			 s9_v, s9_r;
   wire 			 s9_vrh;
   wire 			 s9_plun;
   
   wire 			 s9_ok,s9_ok_in;
   wire [0:rc_width-1] 		 s9_rc,s9_rc_in;
   wire [0:erc_width-1] 	 s9_erc;
   wire [0:lidx_width-1] 	 s9_lidx_in;
   wire [0:lba_width-1] 	 s9_lba;
   wire [0:lunid_width_w_par-1] 	 s9_lunid;
   wire [0:channels-1] 		 s9_portmsk_in;
   
   base_alatch#(.width(2+1+rc_width+erc_width+lidx_width+lba_width+lunid_width_w_par+channels)) is9_lat
     (.clk(clk),.reset(reset),
      .i_v(s8b_v),  .i_r(s8b_r),  .i_d({s8_vrh,s8_ok,   s8_fmt[1],s8_rc,   s8_erc, s8_lidx,   s8_lba,s8_lunid, s8_pmsk}),
      .o_v(s9_v),.o_r(s9_r),      .o_d({s9_vrh,s9_ok_in,s9_plun,  s9_rc_in,s9_erc, s9_lidx_in,s9_lba,s9_lunid, s9_portmsk_in}));

   wire [0:lidx_width-1] 	 s9_lidx = s9_ok_in ? s9_lidx_in : {lidx_width{1'b0}};
   wire [0:channels-1] 		 s9_portmsk = s9_ok_in ? s9_portmsk_in : {channels{1'b0}};
 		 
   wire 			 s9_rht_ctxt_v;
   wire 			 s8_rd_en = s9_r | ~s9_v;


   base_vmem#(.a_width(ctxtid_width-1),.rst_ports(2)) icpc2_vmem
     (.clk(clk),.reset(reset),
      .i_set_v(cpc_set_v),.i_set_a(mmio_rht2_ctxt[0:ctxtid_width-2]),
      .i_rst_v({i_ctxt_rst_v,cpc_rst_v}),.i_rst_a({i_ctxt_rst_d[0:ctxtid_width-2],mmio_rht2_ctxt[0:ctxtid_width-2]}),
      .i_rd_en(s8_rd_en),.i_rd_a(s8_rht_ctxt[0:ctxtid_width-2]),.o_rd_d(s9_rht_ctxt_v)
      );

   ktms_afu_errmux#(.rc_width(rc_width)) is9err_mux(.i_rc(s9_rc_in),.i_ok(s9_ok_in),.i_err(~s9_rht_ctxt_v & s9_vrh),.i_err_rc(afuerr_xl_badctxt),.o_rc(s9_rc),.o_ok(s9_ok));
   
   wire [0:1] 			 s10_v, s10_r;

   base_alatch#(.width(1+1+1+rc_width+erc_width+lidx_width+lba_width+lunid_width_w_par+channels)) is10_lat
     (.clk(clk),.reset(reset),
      .i_v(s9_v),  .i_r(s9_r),      .i_d({   s9_vrh,  s9_plun,  s9_ok,   s9_rc,   s9_erc,    s9_lidx,   s9_lba,   s9_lunid,     s9_portmsk}),
      .o_v(s10_v[0]),.o_r(s10_r[0]),.o_d({o_req_vrh, o_req_plun, o_req_ok,o_req_rc,o_req_erc, o_req_lidx,o_req_lba,o_req_lunid,  o_req_portmsk}));

   base_fifo#(.LOG_DEPTH(6),.width(aux_width)) iaux_del(.clk(clk),.reset(reset),.i_v(s0b_v[1]),.i_r(s0b_r[1]),.i_d(i_req_aux),.o_v(s10_v[1]),.o_r(s10_r[1]),.o_d({o_req_aux}));

   base_acombine#(.ni(2),.no(1)) is10_cmb(.i_v(s10_v),.i_r(s10_r),.o_v(o_req_v),.o_r(o_req_r));

   
   
endmodule // ktms_afu_rht
