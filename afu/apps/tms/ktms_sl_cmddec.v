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
module ktms_sl_cmddec#
  (
   parameter channels=1,
   parameter ea_width = 1,
   parameter ctxtid_width = 1,
   parameter rh_width = 1,
   parameter lunid_width = 64,
   parameter lunid_width_w_par = 65,
   parameter datalen_width = 25,
   parameter datalen_par_width = 1,
   parameter datalen_width_w_par = datalen_width+datalen_par_width,
   parameter ioadllen_width = 1,
   parameter msinum_width = 1,
   parameter rrqnum_width = 1,
   parameter cdb_width = 128 ,
   parameter cdb_par_width = 2,
   parameter cdb_width_w_par = cdb_width+cdb_par_width,

   parameter dma_rc_width = 1,
   parameter flgs_width=5,
   parameter [0:dma_rc_width-1] psl_rsp_paged = 0,
   parameter [0:dma_rc_width-1] psl_rsp_addr = 0
   )
  (
   input 		       clk,
   input 		       reset,
   output 		       i_r,
   input 		       i_v,
   input 		       i_e,
   input [0:129] 	       i_d,     // changed 127 to 129 to add parity kch
   input [0:dma_rc_width-1]    i_rc,

   output 		       i_ec_r,
   input 		       i_ec_v,
   input 		       i_ec_d,
   

   input 		       i_errinj_rcb_fault,
   input 		       i_errinj_rcb_paged,

   output 		       o_v,
   input 		       o_r,
   output [0:flgs_width-1]     o_flgs,
   output [0:7] 	       o_afu_opc,
   output [0:7] 	       o_afu_mod,

   output [0:rh_width-1]       o_rh,
   output [0:lunid_width_w_par-1]    o_lunid,
   output [0:ioadllen_width-1] o_ioadllen,
   output [0:datalen_width_w_par-1]  o_data_len,     // has parity kch. 
   output [0:ctxtid_width-1]   o_data_ctxt,  // has parity kch 
   output                      o_data_ctxt_v, // added ctxt valid bit kch 
   output [0:ea_width-1]       o_data_ea,
   output [0:msinum_width-1]   o_msinum,
   output [0:rrqnum_width-1]   o_rrq,
   output [0:cdb_width_w_par-1]      o_cdb,  // added w_par kch 
   output [0:channels-1]       o_portmsk,
   output [0:dma_rc_width-1]   o_rc,
   output [0:1] 	       o_timeout_flg,
   output [0:15] 	       o_timeout_d,
   output                      o_perror
   );

   wire 		       s1a_v, s1a_r;
   base_arfilter iec_fltr(.i_v(i_ec_v),.i_r(i_ec_r),.o_v(s1a_v),.o_r(s1a_r),.en(i_e));
   

   wire [0:2] 		      s1_beat_in, s1_beat;
   wire 		      s1_v, s1_r, s1_e;
   base_acombine#(.ni(2),.no(1)) is1_cmb(.i_v({i_v,s1a_v}),.i_r({i_r,s1a_r}),.o_v(s1_v),.o_r(s1_r));
   assign s1_e = i_e;
   
   wire 		      s1_act = s1_v & s1_r;
   assign s1_beat_in = s1_e ? 3'b0 : (s1_beat + 3'd1);
   base_vlat_en#(.width(3)) is1_beat_lat(.clk(clk),.reset(reset),.din(s1_beat_in),.q(s1_beat),.enable(s1_act));

   localparam ctxt_st = 15;
   localparam ctxt_ed = 0;
   
   localparam wnr_st = 31;
   localparam sule_st = 30;
   localparam vrh_st = 16;
   localparam rh_st = 63;
   localparam lunid_st = 127;
   localparam datalen_st = 31;
   localparam ioadllen_st = 63;
   localparam dataea_st = 127;
   localparam msinum_st = 7;
   localparam rrqnum_st = 15;
   localparam cdb0_st = 127;
   localparam cdb1_st = 63;

   
   wire [15:0] 		      s1_hw0;
   wire [0:15] 		      s1_hw1;
   wire [31:0] 		      s1_sw0;
   wire [31:0] 		      s1_sw1;
   wire [63:0] 		      s1_dw1;

   wire [0:1]                 s1_perror;
   capi_parcheck#(.width(64)) id_pcheck0(.clk(clk),.reset(reset),.i_v(i_v),.i_d(i_d[0:63]),.i_p(i_d[128]),.o_error(s1_perror[0]));
   capi_parcheck#(.width(64)) id_pcheck1(.clk(clk),.reset(reset),.i_v(i_v),.i_d(i_d[64:127]),.i_p(i_d[129]),.o_error(s1_perror[1]));
   wire [0:1] 				hld_perror;
   wire  				any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(2)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(2'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(any_hld_perror),.q(o_perror));

   base_endian_mux#(.bytes(2)) ihw0(.i_ctrl(i_ec_d),.i_d(i_d[00:15]),.o_d(s1_hw0));
   base_endian_mux#(.bytes(2)) ihw1(.i_ctrl(i_ec_d),.i_d(i_d[16:31]),.o_d(s1_hw1));
   base_endian_mux#(.bytes(4)) isw0(.i_ctrl(i_ec_d),.i_d(i_d[00:31]),.o_d(s1_sw0));
   base_endian_mux#(.bytes(4)) isw1(.i_ctrl(i_ec_d),.i_d(i_d[32:63]),.o_d(s1_sw1));
   base_endian_mux#(.bytes(8)) idw1(.i_ctrl(i_ec_d),.i_d(i_d[64:127]),.o_d(s1_dw1));
   
   wire [7:0] 		      s1_b0 = i_d[0:7];
   wire [7:0] 		      s1_b1 = i_d[8:15];
   wire                       s1_hw0_par;
   capi_parity_gen#(.dwidth(9),.width(1)) cmddec_pgen(.i_d(s1_hw0[ctxtid_width-2:0]),.o_d(s1_hw0_par));

   wire [0:ctxtid_width-1]    s1_data_ctxt = ({s1_hw0[ctxtid_width-2:0],s1_hw0_par});
   wire [0:1] 		      s1_timeout_flg = s1_hw1[8:9];
   wire 		      s1_vrh      = s1_hw1[0];
   wire 		      s1_sule     = s1_hw1[1];
   wire                       s1_tmgmt    = s1_hw1[13];
   wire 		      s1_afu_cmd  = s1_hw1[14];
   wire 		      s1_wnr      = s1_hw1[15];
   
   wire [0:rh_width-1] 	      s1_rh       = s1_sw1[rh_width-1:0];

   // portmask - bit order must be swapped
   wire [0:channels-1] 	      s1_portmsk;
   base_bitswap#(.width(channels)) is1_pmsk(.i_d(s1_sw1[channels-1:0]),.o_d(s1_portmsk));

   wire                       s1_sw0_par ;                      
   capi_parity_gen#(.dwidth(datalen_width),.width(1)) s1_sw0_pgen(.i_d(s1_sw0[datalen_width-1:0]),.o_d(s1_sw0_par));

   
   wire [0:lunid_width_w_par-1]     s1_lunid    = {s1_dw1[63:0],i_d[129]};
   wire [0:datalen_width_w_par-1]   s1_datalen  = {s1_sw0[datalen_width-1:0],s1_sw0_par};
   wire [0:ioadllen_width-1]  s1_ioadllen = s1_sw1[ioadllen_width-1:0];
   wire [0:ea_width-1] 	      s1_dataea   = {s1_dw1[ea_width-2:0],i_d[129]}; // sim 73520 kch 
   wire [0:msinum_width-1]    s1_msinum   = s1_b0[msinum_width-1:0];
   wire [0:rrqnum_width-1]    s1_rrq      = s1_b1[rrqnum_width-1:0];
   wire [0:63] 		      s1_cdb0     = i_d[64:127];
   wire  		      s1_cdb0_par = i_d[129];   // added parity kch 
   wire [0:63] 		      s1_cdb1     = i_d[0:63];
   wire  		      s1_cdb1_par = i_d[128];   // added parity kch 
   wire [0:15] 		      s1_timeout_d  = s1_hw1;

   wire 		      s1_ctxt_en      = s1_act & (s1_beat == 3'd0);
   wire 		      s1_flag_en      = s1_act & (s1_beat == 3'd0);
   wire 		      s1_rh_en        = s1_act & (s1_beat == 3'd0);
   wire 		      s1_portmsk_en   = s1_act & (s1_beat == 3'd0);
   wire 		      s1_lunid_en     = s1_act & (s1_beat == 3'd0);
   wire 		      s1_datalen_en   = s1_act & (s1_beat == 3'd1);
   wire 		      s1_ioadllen_en  = s1_act & (s1_beat == 3'd1);
   wire 		      s1_dataea_en    = s1_act & (s1_beat == 3'd1);
   wire 		      s1_msinum_en    = s1_act & (s1_beat == 3'd2);
   wire 		      s1_rrq_en       = s1_act & (s1_beat == 3'd2);
   wire 		      s1_timeout_en   = s1_act & (s1_beat == 3'd2);
   wire  	              s1_cdb0_en      = s1_act & (s1_beat == 3'd2);
   wire  	              s1_cdb1_en      = s1_act & (s1_beat == 3'd3);
   wire                       s1_rc_en        = s1_act & (s1_beat == 3'd3);
   
   wire [0:dma_rc_width-1]    s1_rc = i_errinj_rcb_paged ? psl_rsp_paged : (i_errinj_rcb_fault ? psl_rsp_addr : i_rc);
   
    

   wire [0:129] 	      s2_cdb;    // changed 127 to 129 kch 
   wire [0:flgs_width-1]      s1_flgs;
   assign s1_flgs[0] = s1_vrh;
   assign s1_flgs[1] = s1_afu_cmd;
   assign s1_flgs[2] = s1_sule;
   assign s1_flgs[3] = s1_tmgmt;
   assign s1_flgs[4] = s1_wnr;
   // output latches
   base_vlat#(.width(1)) ictxt_en (.clk(clk),.reset(reset),.din(s1_ctxt_en),.q(o_data_ctxt_v));
   base_vlat_en#(.width(ctxtid_width))   idtactxt   (.clk(clk),.reset(1'b0),.din(s1_data_ctxt),  .q(o_data_ctxt),  .enable(s1_ctxt_en));
   base_vlat_en#(.width(flgs_width))       iflgs    (.clk(clk),.reset(1'b0),.din(s1_flgs),       .q(o_flgs),       .enable(s1_flag_en));
   base_vlat_en#(.width(2))                iafu_tof (.clk(clk),.reset(1'b0),.din(s1_timeout_flg),.q(o_timeout_flg),.enable(s1_flag_en));
   base_vlat_en#(.width(16))               itimeout (.clk(clk),.reset(1'b0),.din(s1_timeout_d),  .q(o_timeout_d),  .enable(s1_timeout_en));
   
   base_vlat_en#(.width(8))                iafu_opc (.clk(clk),.reset(1'b0),.din(s1_cdb0[0:7]),  .q(o_afu_opc),    .enable(s1_cdb0_en));
   base_vlat_en#(.width(8))                iafu_mod (.clk(clk),.reset(1'b0),.din(s1_cdb0[8:15]), .q(o_afu_mod),    .enable(s1_cdb0_en));

   base_vlat_en#(.width(rh_width))       irh      (.clk(clk),.reset(1'b0),.din(s1_rh),      .q(o_rh),          .enable(s1_rh_en));
   base_vlat_en#(.width(channels))       ipmsk    (.clk(clk),.reset(1'b0),.din(s1_portmsk), .q(o_portmsk),     .enable(s1_portmsk_en));
   base_vlat_en#(.width(lunid_width_w_par))    ilunid   (.clk(clk),.reset(1'b0),.din(s1_lunid),   .q(o_lunid),       .enable(s1_lunid_en));
   base_vlat_en#(.width(datalen_width_w_par))  idatalen (.clk(clk),.reset(1'b0),.din(s1_datalen), .q(o_data_len),     .enable(s1_datalen_en));
   base_vlat_en#(.width(ioadllen_width)) iioadllen(.clk(clk),.reset(1'b0),.din(s1_ioadllen),.q(o_ioadllen),    .enable(s1_ioadllen_en));
   base_vlat_en#(.width(ea_width))       idataea  (.clk(clk),.reset(1'b0),.din(s1_dataea),  .q(o_data_ea),      .enable(s1_dataea_en));
   base_vlat_en#(.width(msinum_width))   imsinum  (.clk(clk),.reset(1'b0),.din(s1_msinum),  .q(o_msinum),      .enable(s1_msinum_en));
   base_vlat_en#(.width(rrqnum_width))   irrq     (.clk(clk),.reset(1'b0),.din(s1_rrq),     .q(o_rrq),         .enable(s1_rrq_en));
   base_vlat_en#(.width(64))               icdb0    (.clk(clk),.reset(1'b0),.din(s1_cdb0),    .q(s2_cdb[0:63] ), .enable(s1_cdb0_en));
   base_vlat_en#(.width(64))               icdb1    (.clk(clk),.reset(1'b0),.din(s1_cdb1),    .q(s2_cdb[64:127]),.enable(s1_cdb1_en));
   base_vlat_en#(.width(1))                icdb0_par    (.clk(clk),.reset(1'b0),.din(s1_cdb0_par),.q(s2_cdb[128] ), .enable(s1_cdb0_en));  // added parity kch 
   base_vlat_en#(.width(1))                icdb1_par    (.clk(clk),.reset(1'b0),.din(s1_cdb1_par),.q(s2_cdb[129]),.enable(s1_cdb1_en));    // added parity kch 
   base_vlat_en#(.width(dma_rc_width))     irclat   (.clk(clk),.reset(1'b0),.din(s1_rc),      .q(o_rc),          .enable(s1_rc_en));
   
   assign o_cdb = s2_cdb[128-cdb_width:129]; // changed 127 to 129 kch 

   wire 		      s2_v, s2_r;
   
   base_alatch#(.width(1)) is1_lat(.clk(clk),.reset(reset),.i_v(s1_v),.i_r(s1_r),.i_d(1'b0),.o_v(s2_v),.o_r(s2_r),.o_d());
   wire 		      s2_en = s1_beat == 3'd0;
   base_afilter is2_fltr(.i_v(s2_v),.i_r(s2_r),.o_v(o_v),.o_r(o_r),.en(s2_en));
   
endmodule // ktms_sl_cmddec
