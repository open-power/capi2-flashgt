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
//----------------------------------------------------------------------------- 
// 
// IBM Confidential 
// 
// IBM Confidential Disclosure Agreement Number: 20160104OPPG01 
// Supplement Number: 20160104OPPG02
// 
// (C) Copyright IBM Corp. 2016 
// 
//    The source code for this program is not published or otherwise 
//    divested of its trade secrets, irrespective of what has been 
//    deposited with the U.S. Copyright Office. 
// 
//----------------------------------------------------------------------------- 

module ktms_afu_ioasa
  #(
    parameter ctxtid_width       = 10,  //changed to 10 to add parity
    parameter ea_width           = 65, //changed to 65 to add parity
    parameter dma_rc_width = 0,
    parameter afu_rc_width = 8,
    parameter afu_erc_width =8,
    parameter fcstat_width=8,
    parameter fcxstat_width=8,
    parameter scstat_width=8,
    parameter fcinfo_width=160,
    parameter time_width = 16,
    parameter reslen_width = 32,
    parameter rslt_width = afu_rc_width+afu_erc_width+2+reslen_width+fcstat_width+fcxstat_width+scstat_width+2+fcinfo_width,
    parameter aux_width = 1,
    parameter chnlid_width = 2,
    parameter sintrid_width=4,
    parameter tstag_width=1,
    parameter [0:dma_rc_width-1] psl_rsp_paged = 0,
    parameter [0:dma_rc_width-1] psl_rsp_addr = 0,
    parameter [0:dma_rc_width-1] psl_rsp_cinv = 0,
    parameter [0:sintrid_width-1] sintr_asa=0,
    parameter [0:sintrid_width-1] sintr_paged = 0,
    parameter [0:sintrid_width-1] sintr_rcb = 0
    )
   (input clk,
    input 		       reset,

    input [0:5] 	       i_rtry_cfg, 
    input 		       i_errinj_asa_fault,
    input 		       i_errinj_asa_paged,
    input 		       o_put_addr_r,
    output 		       o_put_addr_v,
    output [0:ea_width-1]      o_put_addr_ea,
    output [0:ctxtid_width-1]    o_put_addr_ctxt,  
    output [0:tstag_width-1]   o_put_addr_tstag,

    output 		       i_put_done_r,
    input 		       i_put_done_v,
    input [0:dma_rc_width-1]   i_put_done_rc,
    
    input 		       o_put_data_r,
    output 		       o_put_data_v,
    output [0:129] 	       o_put_data_d,   // changed 127 to 129 to add parity kch 
    output [0:3] 	       o_put_data_c,
    output 		       o_put_data_f,
    output 		       o_put_data_e,
			      
    output 		       i_rsp_r,
    input 		       i_rsp_v,
    input [0:chnlid_width-1]   i_rsp_chnl,    // kch fix this  added //
    input [0:ctxtid_width-1]   i_rsp_ctxt,  
    input 		       i_rsp_ec,
    input 		       i_rsp_nocmpl,
    input [0:tstag_width-1]    i_rsp_tstag, 
    input [0:ea_width-1]       i_rsp_ea,
    input [0:rslt_width-1]     i_rsp_stat,
    input 		       i_rsp_sule,
    input [0:aux_width-1]      i_rsp_aux,

    input 		       o_rsp_r,
    output 		       o_rsp_v,
    output [0:ctxtid_width-1]  o_rsp_ctxt, 
    output 		       o_rsp_ec,
    output 		       o_rsp_nocmpl,
    output [0:ea_width-1]      o_rsp_ea,
    output [0:tstag_width-1]   o_rsp_tstag,
    output [0:aux_width-1]     o_rsp_aux,
    output 		       o_rsp_sintr_v,
    output [0:sintrid_width-1] o_rsp_sintr_id,

    output [11:0] 	       o_pipemon_v,
    output [11:0] 	       o_pipemon_r,
    output [0:1] 	       o_dbg_cnt_inc,
    output                     o_perror
    );

   wire  		      s1a_r;
   wire 		      s1a_v;
   wire [0:ctxtid_width-1]      s1_ctxt; 
   wire 		      s1_ec;
   wire [0:tstag_width-1]     s1_tstag;
   wire [0:ea_width-1] 	      s1_ea;
   wire [0:rslt_width-1]      s1_stat;
   wire [0:aux_width-1]       s1_aux;
   wire [0:chnlid_width-1]    s1_chnl;
   wire 		      s1_sule;
   wire 		      s1_nocmpl;
   
   base_alatch#(.width(tstag_width+ctxtid_width+1+ea_width+1+rslt_width+aux_width+chnlid_width+1)) is1_lat    
     (.clk(clk),.reset(reset),
      .i_v(i_rsp_v),.i_r(i_rsp_r),.i_d({i_rsp_tstag,i_rsp_ctxt,i_rsp_ec,i_rsp_ea,i_rsp_sule,i_rsp_stat,i_rsp_aux,i_rsp_chnl,i_rsp_nocmpl}),
      .o_v(s1a_v),.o_r(s1a_r),    .o_d({   s1_tstag,   s1_ctxt,   s1_ec,   s1_ea,   s1_sule,   s1_stat,   s1_aux,   s1_chnl,   s1_nocmpl})
      );

   
   wire 		      s1_underrun, s1_overrun;
   wire [0:reslen_width-1]    s1_rlen;
   wire [0:fcstat_width-1]    s1_fc_rc;
   wire [0:scstat_width-1]    s1_sc_rc;
   wire [0:afu_rc_width-1]    s1_afu_rc;
   wire [0:afu_erc_width-1]   s1_afu_erc;
   wire [0:fcinfo_width-1]    s1_fc_info;
   wire 		      s1_sns_vld;
   wire 		      s1_fcp_vld;
   wire [0:fcxstat_width-1]   s1_fc_extra;

   

   assign {s1_afu_rc,s1_afu_erc,s1_underrun,s1_overrun,s1_rlen,s1_fc_rc,s1_fc_extra,s1_sc_rc,s1_sns_vld,s1_fcp_vld,s1_fc_info} = s1_stat;


   wire 		      s1_afu_rcb_dmaerr = (s1_afu_rc == 8'h40);
   wire 		      s1_afu_rcb_paged = (s1_afu_rc == 8'h40) & (s1_afu_erc == 8'h0a);
   wire 		      s1_afu_lxt_paged = (s1_afu_rc == 8'h04) & (s1_afu_erc == 8'h0a);
   wire 		      s1_afu_rht_paged = (s1_afu_rc == 8'h14) & (s1_afu_erc == 8'h0a);
   wire 		      s1_afu_dta_paged = (s1_afu_rc == 8'h31) & (s1_afu_erc == 8'h0a);
   wire 		      s1_afu_tmp_error = (s1_afu_rc == 8'h30);
   wire 		      s1_afu_rcb_inv = (s1_afu_rc == 8'h40) & (s1_afu_erc == psl_rsp_cinv);

   // count when we tried to get an rcb but the context was no longer valid
 //  assign o_dbg_cnt_inc[0] = s1a_v & s1a_r & s1_afu_rcb_inv;
     assign o_dbg_cnt_inc[0] = s1a_v & s1a_r & (s1_afu_rc == 8'h13);
     assign o_dbg_cnt_inc[1] = s1a_v & s1a_r & (s1_afu_rc == 8'h21);
   


   // don't do synchronous interupt if we have already timed out the command
   wire 		      s1_sintr_v = s1_afu_rcb_dmaerr & ~s1_nocmpl;
   wire [0:sintrid_width-1]   s1_sintr_id = s1_afu_rcb_paged ?  sintr_paged : sintr_rcb;
   
   // remaining 4 bits specify the intrupt status
   wire 		      s1_underrun_qual = s1_underrun & ~s1_sule;
   
   wire 		      s1_write_ioasc = ~s1_sintr_v & ((|s1_afu_rc) | (|s1_fc_rc) | (|s1_sc_rc) | s1_underrun_qual | s1_overrun | s1_sns_vld | s1_fcp_vld) & ~s1_nocmpl;
   wire 		      s1_bypass = ~s1_write_ioasc;

   wire [0:1] 		      s1b_v, s1b_r;  // dmux output: 0=bypass path, 1=write ioasc path
   base_ademux#(.ways(2)) is1b_demux(.i_v(s1a_v),.i_r(s1a_r),.o_v(s1b_v),.o_r(s1b_r),.sel({s1_bypass,~s1_bypass}));

   // bypass path - just goes through a latch
   wire  		      t1_v, t1_r;
   wire [0:ea_width-1] 	      t1_ea;
   wire [0:tstag_width-1]     t1_tstag;
   wire [0:ctxtid_width-1]      t1_ctxt;  
   wire 		      t1_ec;
   wire [0:aux_width-1]       t1_aux;
   wire 		      t1_sintr_v;
   wire [0:sintrid_width-1]   t1_sintr_id;
   wire 		      t1_rtry_v;
   wire 		      t1_nocmpl;
   
   base_alatch_burp#(.width(1+sintrid_width+ea_width+tstag_width+ctxtid_width+1+aux_width+1)) ibyp_ltch  
     (.clk(clk),.reset(reset),
      .i_v(s1b_v[0]),.i_r(s1b_r[0]),.i_d({s1_sintr_v, s1_sintr_id, s1_ea, s1_tstag, s1_ctxt,s1_ec,s1_aux,s1_nocmpl}),
      .o_v(t1_v),    .o_r(t1_r),    .o_d({t1_sintr_v, t1_sintr_id, t1_ea, t1_tstag, t1_ctxt,t1_ec,t1_aux,t1_nocmpl}));

   // bad path 
   wire [0:2] 		      s1c_v, s1c_r;
   base_acombine#(.ni(1),.no(3)) s1c_cmb(.i_v(s1b_v[1]),.i_r(s1b_r[1]),.o_v(s1c_v),.o_r(s1c_r));

   localparam owidth = ea_width+1+sintrid_width+tstag_width+ctxtid_width+1+1+aux_width;

   wire                s1_perror;
   capi_parcheck#(.width(ea_width-1)) s1_ea_pcheck(.clk(clk),.reset(reset),.i_v(s1a_v),.i_d(s1_ea[0:63]),.i_p(s1_ea[64]),.o_error(s1_perror));
   wire  				hld_perror;
   wire  				any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(1)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(1'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(any_hld_perror),.q(o_perror));

   wire [0:ea_width-1] s1_put_addr_ea;
   capi_parity_gen#(.dwidth(ea_width-1),.width(1)) s1_put_addr_ea_pgen(.i_d(s1_put_addr_ea[0:ea_width-2]),.o_d(s1_put_addr_ea[ea_width-1]));
   assign              s1_put_addr_ea[0:ea_width-2] = s1_ea[0:ea_width-2] + 'h40;

   wire [0:7] 	       s1_flags;
   wire [0:7] 	       s1_port = {{8-chnlid_width{1'b0}},s1_chnl};
   wire [0:7] 	       s1_scsi_extra = 8'b0;

   
   

   assign s1_flags[0] = s1_sns_vld;
   assign s1_flags[1] = s1_fcp_vld;
   assign s1_flags[2] = s1_overrun;
   assign s1_flags[3] = s1_underrun_qual;
   assign s1_flags[4:7] = 3'd0;
   

   wire [0:31] 		   s1_szl_rlen;
   wire [0:15] 		   s1_szl_asc;

   wire [0:3]              s1_put_data_dpar; // added parity kch 
   capi_parity_gen#(.dwidth(64),.width(1)) s1_put_data_d_pgen0(.i_d({s1_flags, s1_afu_rc, s1_sc_rc, s1_fc_rc, s1_szl_rlen}),.o_d(s1_put_data_dpar[0]));   
   capi_parity_gen#(.dwidth(64),.width(1)) s1_put_data_d_pgen1(.i_d({s1_port, s1_afu_erc,s1_scsi_extra,s1_fc_extra,s1_fc_info[0:31]}),.o_d(s1_put_data_dpar[1]));
   capi_parity_gen#(.dwidth(64),.width(1)) s1_put_data_d_pgen2(.i_d({s1_fc_info[32:95]}),.o_d(s1_put_data_dpar[2]));
   capi_parity_gen#(.dwidth(64),.width(1)) s1_put_data_d_pgen3(.i_d({s1_fc_info[96:159]}),.o_d(s1_put_data_dpar[3]));

   base_endian_mux#(.bytes(4)) irln_szl(.i_ctrl(s1_ec),.i_d(s1_rlen),.o_d(s1_szl_rlen));
   wire [0:259] 	   s1_put_data_d = {s1_flags, s1_afu_rc, s1_sc_rc, s1_fc_rc, s1_szl_rlen,
					    s1_port, s1_afu_erc,s1_scsi_extra,s1_fc_extra,s1_fc_info[0:31],s1_put_data_dpar[0:1],
					    s1_fc_info[32:95],
					    s1_fc_info[96:159],s1_put_data_dpar[2:3]};
   

   // send address
   wire [0:ea_width-1] 	   s2_put_addr_ea;
   wire [0:ctxtid_width-1] s2_put_addr_ctxt;
   base_alatch#(.width(tstag_width+ctxtid_width+ea_width)) is2_alat  
     (.clk(clk),.reset(reset),.i_v(s1c_v[1]),.i_r(s1c_r[1]),.i_d({s1_tstag, s1_ctxt,s1_put_addr_ea}),.o_v(o_put_addr_v),.o_r(o_put_addr_r),.o_d({o_put_addr_tstag,o_put_addr_ctxt,o_put_addr_ea}));


   // send data
   wire [0:259] 	   s2_put_data_d;
   wire 		   s2a_v, s2a_r;
   base_alatch#(.width(260)) is2_dlat
     (.clk(clk),.reset(reset),.i_v(s1c_v[2]),.i_r(s1c_r[2]),.i_d(s1_put_data_d),.o_v(s2a_v),.o_r(s2a_r),.o_d({s2_put_data_d}));

   wire 		   s2_put_data_beat;
   wire 		   s2b_v, s2b_r;
   base_arfilter is2_dfltr(.i_v(s2a_v),.i_r(s2a_r),.o_v(s2b_v),.o_r(s2b_r),.en(s2_put_data_beat));
   
   base_vlat_en#(.width(1)) is2_blat(.clk(clk),.reset(reset),.din(~s2_put_data_beat),.q(s2_put_data_beat),.enable(s2b_v & s2b_r));

   assign o_put_data_d = s2_put_data_beat ? s2_put_data_d[130:259] : s2_put_data_d[0:129]; 

   base_aesplit iesplt
     (.clk(clk),.reset(reset),
      .i_v(s2b_v),.i_r(s2b_r),.i_e(s2_put_data_beat),
      .o_v(o_put_data_v),.o_r(o_put_data_r),.o_e(o_put_data_e)
      );
			      
   assign o_put_data_c = 4'd0;
   assign o_put_data_f = 1'b0;

   wire [0:1] 		      sl_v, sl_r;
   wire [0:ea_width-1] 	      sl_ea;
   wire [0:tstag_width-1]     sl_tstag;
   wire [0:ctxtid_width-1]      sl_ctxt; 
   wire [0:aux_width-1]       sl_aux;
   wire 		      sl_ec;
   
   // save aux data from bad result for put_done   
   base_fifo#(.LOG_DEPTH(3),.width(ea_width+tstag_width+ctxtid_width+1+aux_width)) iaux_fifo 
     (.clk(clk),.reset(reset),
      .i_v(s1c_v[0]),.i_r(s1c_r[0]),.i_d({s1_ea, s1_tstag, s1_ctxt,s1_ec,s1_aux}),.o_v(sl_v[0]),.o_r(sl_r[0]),.o_d({sl_ea,sl_tstag,sl_ctxt,sl_ec,sl_aux}));

   // release bad result when we get put_done.   
   base_acombine#(.ni(2),.no(1)) isl_cmb(.i_v({i_put_done_v,sl_v[0]}),.i_r({i_put_done_r,sl_r[0]}),.o_v(sl_v[1]),.o_r(sl_r[1]));
   wire [0:dma_rc_width-1]    sl_put_done_rc = i_errinj_asa_paged ? psl_rsp_paged : (i_errinj_asa_fault ? psl_rsp_addr : i_put_done_rc);
   wire 		      sl_rsp_paged = (sl_put_done_rc == psl_rsp_paged);
   wire 		      sl_rsp_cinv = (sl_put_done_rc == psl_rsp_cinv);
   
   wire 		      sl_rsp_error = (| sl_put_done_rc) & ~sl_rsp_paged;
   wire 		      sl_sintr_v = sl_rsp_error;
   wire [0:sintrid_width-1]   sl_sintr_id = sl_rsp_paged ? sintr_paged : sintr_asa;
//   assign o_dbg_cnt_inc[1]  = sl_v[1] & sl_r[1] & sl_rsp_cinv;
   
   wire 		      t2_v, t2_r;
   wire [0:owidth-1] 	      t2_d;
   // mux between good result and bad result   
   base_arr_mux#(.ways(2),.width(owidth)) iomux  
     (.clk(clk),.reset(reset),
      .i_v({sl_v[1],t1_v}),.i_r({sl_r[1],t1_r}),
      .i_d({sl_ea,sl_sintr_v, sl_sintr_id, sl_tstag, sl_ctxt, sl_ec, 1'b0, sl_aux,  
	    t1_ea,t1_sintr_v, t1_sintr_id, t1_tstag, t1_ctxt, t1_ec, t1_nocmpl, t1_aux}),
      .o_v(t2_v),.o_r(t2_r),.o_d(t2_d),
      .o_sel()
      );

   base_aburp_latch#(.width(owidth)) it2_lat  
     (.clk(clk),.reset(reset),
      .i_v(t2_v),.i_r(t2_r),.i_d(t2_d),
      .o_v(o_rsp_v),.o_r(o_rsp_r),.o_d({o_rsp_ea,o_rsp_sintr_v, o_rsp_sintr_id, o_rsp_tstag, o_rsp_ctxt, o_rsp_ec, o_rsp_nocmpl, o_rsp_aux}));


   assign o_pipemon_v[0]   = s1a_v;
   assign o_pipemon_v[2:1] = s1b_v;
   assign o_pipemon_v[4:3] = s1c_v;
   assign o_pipemon_v[5] = s2b_v;
   assign o_pipemon_v[6] = o_put_addr_v;
   assign o_pipemon_v[7] = o_put_data_v;
   assign o_pipemon_v[8] = i_put_done_v;
   assign o_pipemon_v[10:9] = sl_v;
   assign o_pipemon_v[11] = t1_v;

   assign o_pipemon_r[0] = s1a_r;
   assign o_pipemon_r[2:1] = s1b_r;
   assign o_pipemon_r[4:3] = s1c_r;
   assign o_pipemon_r[5] = s2b_r;
   assign o_pipemon_r[6] = o_put_addr_r;
   assign o_pipemon_r[7] = o_put_data_r;
   assign o_pipemon_r[8] = i_put_done_r;
   assign o_pipemon_r[10:9] = sl_r;
   assign o_pipemon_r[11] = t1_r;

endmodule // ktms_ioasa
