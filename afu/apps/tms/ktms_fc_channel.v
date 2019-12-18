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
module ktms_fc_channel#
  (
   parameter ea_width = 64,
   parameter ctxtid_width = 9,
   parameter cdb_width=128,
   parameter cdb_width_w_par=128+2,
   parameter max_reads = 256,
   parameter max_writes = 256,
   parameter tag_width = 8,
   parameter tag_par_width      = (tag_width + 63)/64,
   parameter tag_width_w_par    = tag_width+tag_par_width,
   parameter tstag_width = 1,
   parameter channel_width = 1,
   parameter channel = 0,
   parameter lunid_width = 64,
   parameter lunid_width_w_par = 65,
   parameter datalen_width = 25,
   parameter datalen_par_width = 1,
   parameter datalen_width_w_par = datalen_width+datalen_par_width,


   parameter fc_data_width = 128,
   parameter fc_data_par_width = fc_data_width/64,
   parameter fc_data_width_w_par = fc_data_width + fc_data_par_width,
   parameter fc_data_bytes = fc_data_width/8,
   parameter fc_bytec_width = $clog2(fc_data_bytes+1),

   parameter beatid_width = datalen_width-$clog2(fc_data_bytes),
   parameter afu_data_width = 130,
   parameter afu_bytec_width = 4,
   
   parameter fc_cmd_width=2,
   parameter fc_tag_width       = 8,         
   parameter fc_tag_par_width      = (fc_tag_width + 63)/64,
   parameter fc_tag_width_w_par    = fc_tag_width+fc_tag_par_width,
   parameter fcstat_width=1,
   parameter fcxstat_width=1,
   parameter scstat_width=1,
   parameter fcinfo_width=1,
   parameter afu_rc_width = 1, //major response code
   parameter afu_erc_width = 1, //extra info
   parameter reslen_width = 32,
   parameter [0:afu_rc_width-1] afuerr_dma_error='h31,
   parameter [0:afu_rc_width-1] afuerr_int_error='h60,
   parameter [0:afu_rc_width-1] afuerr_unexpected_read_data='h61,
   parameter [0:afu_rc_width-1] afuerr_unexpected_write_data='h62,
   parameter ssize_width=1,
   parameter dma_rc_width=1,
   parameter [0:dma_rc_width-1] dma_rc_paged=1,
   parameter [0:dma_rc_width-1] dma_rc_addr=1,
   parameter rslt_width = afu_rc_width+afu_erc_width+2+reslen_width+fcstat_width+fcxstat_width+scstat_width+2+fcinfo_width
   )
   (
    input 			clk,
    input 			reset,
    input [0:2] 		i_errinj,

    // commands
    output [0:13] 		o_dbg_inc,
    output [15:0] 		o_dbg_reg,
    output 			o_stallcount_v,
    output 			o_stallcount_r,
    output 			i_cmd_r,
    input 			i_cmd_v,
    input 			i_cmd_rd,
    input 			i_cmd_wr,
    input [0:tag_width_w_par-1] i_cmd_tag,
    input [0:cdb_width_w_par-1] 	i_cmd_cdb,
    input [0:lunid_width_w_par-1] 	i_cmd_lun,
    input [0:ctxtid_width-1] 	i_cmd_ctxt,
    input [0:tstag_width-1] 	i_cmd_tstag,   
    input [0:ea_width-1] 	i_cmd_ea,
    input [0:datalen_width_w_par-1] 	i_cmd_data_len,


    // check to make sure this tag has not timed out.
    // max one outstanding at a time
    // checking has the side effect of inhibiting
    // timeout response.  We won't get a response back for reads, but
    // we send them for performance monitor
    input 			o_tochk_r,
    output 			o_tochk_v,
    output [0:tstag_width-1] 	o_tochk_tag,   
    output 			o_tochk_rnw,

    // ok=1: not timed out, ok=0: timed out
    input 			i_tochk_v,
    input 			i_tochk_ok,

    // dma interface
    input 			put_addr_r,
    output 			put_addr_v,
    output [0:ea_width-1] 	put_addr_ea,
    output [0:tstag_width-1] 	put_addr_tstag, 
    output [0:ctxtid_width-1] 	put_addr_ctxt,

    input 			put_data_r,
    output 			put_data_v,
    output [0:afu_data_width-1] put_data_d,
    output 			put_data_e,
    output [0:3] 		put_data_c,
    output 			put_data_f,
    input 			put_done_v,
    output 			put_done_r,
    input [0:dma_rc_width-1] 	put_done_rc, 
    // dma interface
    input 			get_addr_r,
    output 			get_addr_v,
    output [0:ea_width-1] 	get_addr_d_ea,
    output [0:tstag_width-1] 	get_addr_d_tstag,   
    output [0:ctxtid_width-1] 	get_addr_d_ctxt,
    output [0:ssize_width-1] 	get_addr_d_size,

    output 			get_data_r,
    input 			get_data_v,
    input [0:afu_data_width-1] 	get_data_d,
    input 			get_data_e,
    input [0:afu_bytec_width-1] get_data_c,
    input [0:dma_rc_width-1] 	get_data_rc,


    // completion interface
    input 			o_rslt_r,
    output 			o_rslt_v,
    output [0:tag_width_w_par-1] 	o_rslt_tag,
    output [0:rslt_width-1] 	o_rslt_stat,
   
    input 			o_fc_req_r,
    output 			o_fc_req_v,
    output [0:fc_cmd_width-1] 	o_fc_req_cmd,   
    output [0:tag_width-1] 	o_fc_req_tag, 
    output [0:tag_par_width-1] 	o_fc_req_tag_par, 

    output [0:lunid_width_w_par-2] 	o_fc_req_lun, 
    output              	o_fc_req_lun_par,   
    output [0:datalen_width_w_par-2] 	o_fc_req_length,
    output              	o_fc_req_length_par,
    output [0:cdb_width-1] 	o_fc_req_cdb,
     output [0:1]       	o_fc_req_cdb_par,
  
    // write data request interface
    output 			i_fc_wdata_req_r, // backpressure for write data requests 
    input 			i_fc_wdata_req_v,
    input [0:tag_width-1] 	i_fc_wdata_req_tag,
    input               	i_fc_wdata_req_tag_par,
    input [0:datalen_width-1] 	i_fc_wdata_req_size, // how much data is being requested (bytes) - we might never use the full range here, but no reason to limit ourselves
    input               	i_fc_wdata_req_size_par,
    input [0:beatid_width-1] 	i_fc_wdata_req_beat, // where in the data stream does this start (beats) 

    // data response interface (writes) - will come in the same order as requests
    input 			o_fc_wdata_rsp_r,
    output 			o_fc_wdata_rsp_v,
    output [0:fc_data_width-1] 	o_fc_wdata_rsp_data,
    output [0:1]        	o_fc_wdata_rsp_data_par, 
    output 			o_fc_wdata_rsp_e, // this is the last beat of the transfer
    output 			o_fc_wdata_rsp_error, // there was an error - abort this exchange. only valid when rsp_e and rsp_v are both high
   
    output [0:tag_width-1] 	o_fc_wdata_rsp_tag, // which  exchange is this stream part of
    output              	o_fc_wdata_rsp_tag_par,
    output [0:beatid_width-1] 	o_fc_wdata_rsp_beat, // which beat is this of the transfer  
   

    // read data response interface
    output 			i_fc_rdata_rsp_r,
    input 			i_fc_rdata_rsp_v,
    input 			i_fc_rdata_rsp_e,
    input [0:fc_bytec_width-1] 	i_fc_rdata_rsp_c,
    input [0:beatid_width-1] 	i_fc_rdata_rsp_beat, // global to the entire exchange, not just local to this data transfer 
    input [0:tag_width-1] 	i_fc_rdata_rsp_tag,
    input               	i_fc_rdata_rsp_tag_par,
    input [0:fc_data_width-1] 	i_fc_rdata_rsp_data,
    input [0:fc_data_par_width-1] i_fc_rdata_rsp_data_par,

    // command response interface
    input 			i_fc_rsp_v,
    input [0:tag_width-1] 	i_fc_rsp_tag,
    input [0:tag_par_width-1] 	i_fc_rsp_tag_par, 
    input 			i_fc_rsp_underrun,
    input 			i_fc_rsp_overrun,
    input [0:32-1] 		i_fc_rsp_resid,
    input [0:fcstat_width-1] 	i_fc_rsp_fcstat,
    input [0:fcxstat_width-1] 	i_fc_rsp_fcxstat,
    input [0:scstat_width-1] 	i_fc_rsp_scstat,
    input [0:fcinfo_width-1] 	i_fc_rsp_info,
    input 			i_fc_rsp_fcp_valid,
    input 			i_fc_rsp_sns_valid,
    input [0:beatid_width-1] 	i_fc_rsp_rdata_beats, // number of beats of read data sent. 
    output [0:1]                o_perror
    );

   localparam afu_rsp_width = afu_rc_width+afu_erc_width;
   localparam [0:fc_cmd_width-1] fcp_gscsi_rd = 'h03;
   localparam [0:fc_cmd_width-1] fcp_gscsi_wr = 'h04;
   localparam [0:fc_cmd_width-1] fcp_abort = 'h05;
   localparam [0:fc_cmd_width-1] fcp_tmgmt = 'h06;

   localparam [0:afu_rc_width-1] afu_to_rc = 'h51;

   assign o_stallcount_v = i_fc_rdata_rsp_v;
   assign o_stallcount_r = i_fc_rdata_rsp_r;
   // latch inbound command
   wire 		       ec2_r;
   wire 		       ec2_v;
   wire 		       ec2_rd;
   wire 		       ec2_wr;
   wire [0:tag_width_w_par-1]  ec2_tag;  
   wire [0:lunid_width_w_par-1]      ec2_lun;
   wire [0:ea_width-1] 	       ec2_ea;
   wire [0:tstag_width-1]      ec2_tstag; 
   wire [0:ctxtid_width-1]     ec2_ctxt;
   wire [0:datalen_width_w_par-1]    ec2_datalen;
   wire [0:cdb_width_w_par-1]        ec2_cdb;  
   base_fifo#(.LOG_DEPTH(tag_width),.width(2+tag_width_w_par+lunid_width_w_par+tstag_width+ctxtid_width+ea_width+datalen_width_w_par+cdb_width_w_par)) iec2_lat 
     (.clk(clk),.reset(reset),
      .i_v(i_cmd_v),.i_r(i_cmd_r),.i_d({i_cmd_rd,i_cmd_wr, i_cmd_tag,i_cmd_lun,i_cmd_tstag,i_cmd_ctxt,i_cmd_ea,i_cmd_data_len,i_cmd_cdb}),
      .o_v(ec2_v),  .o_r(ec2_r),  .o_d({  ec2_rd,  ec2_wr,  ec2_tag,  ec2_lun,  ec2_tstag,    ec2_ctxt,ec2_ea,ec2_datalen,ec2_cdb})
      );



   // before sending to FC interface, check to make sure this tag has not timed out. 
   wire [0:1] 		       ec2a_v, ec2a_r; // 0: to check, 1: next stage
   base_acombine#(.ni(1),.no(2)) iec2_split(.i_v(ec2_v),.i_r(ec2_r),.o_v(ec2a_v),.o_r(ec2a_r));
   base_alatch_burp#(.width(1+tstag_width)) itochk_lat(.clk(clk),.reset(reset),.i_v(ec2a_v[0]),.i_r(ec2a_r[0]),.i_d({ec2_rd,ec2_tstag}),.o_v(o_tochk_v),.o_r(o_tochk_r),.o_d({o_tochk_rnw,o_tochk_tag})); 
   

   wire 		       ec3a_v, ec3a_r, ec3a_ok;
   base_alatch#(.width(1)) iec3a_lat(.clk(clk),.reset(reset),.i_v(i_tochk_v),.i_r(),.i_d(i_tochk_ok),.o_v(ec3a_v),.o_r(ec3a_r),.o_d(ec3a_ok));
     
   wire [0:tag_width_w_par-1]  ec3_tag; 
   wire [0:lunid_width_w_par-1]      ec3_lun;
   wire 		       ec3_rd;
   wire 		       ec3_wr;
   wire [0:cdb_width_w_par-1]        ec3_cdb; 
   wire [0:datalen_width_w_par-1]    ec3_datalen;
   wire [0:1] 		       ec3b_v, ec3b_r; // 0: to check, 1: prev stage
   base_alatch#(.width(2+tag_width_w_par+lunid_width_w_par+cdb_width_w_par+datalen_width_w_par)) iec3_lat 
     (.clk(clk),.reset(reset),.i_v(ec2a_v[1]),.i_r(ec2a_r[1]),.i_d({ec2_rd,ec2_wr,ec2_tag,ec2_lun,ec2_cdb,ec2_datalen}),.o_v(ec3b_v[1]),.o_r(ec3b_r[1]), .o_d({ec3_rd, ec3_wr, ec3_tag,ec3_lun,ec3_cdb,ec3_datalen}));

   base_aforce iec3b_frc(.i_v(ec3a_v),.i_r(ec3a_r),.o_v(ec3b_v[0]),.o_r(ec3b_r[0]),.en(~ec3_rd));
   wire 		       ec3_ok = ec3_rd | ec3a_ok;  // timeout manager says this tag has not timed out and is ok to send.
   
   wire 		       ec3c_v, ec3c_r;
   base_acombine#(.ni(2),.no(1)) iec3_cmb(.i_v(ec3b_v),.i_r(ec3b_r),.o_v(ec3c_v),.o_r(ec3c_r));

   wire [0:1] 		       ec3d_v, ec3d_r; // 0: to fc unit, 1: timeout response
   base_ademux#(.ways(2)) iec3_dmux(.i_v(ec3c_v),.i_r(ec3c_r),.o_v(ec3d_v),.o_r(ec3d_r),.sel({ec3_ok,~ec3_ok}));

   wire [0:fc_cmd_width-1]     ec3_cmd = 
			       ec3_rd ? fcp_gscsi_rd :
			       ec3_wr ? fcp_gscsi_wr :
			       fcp_tmgmt;
   
   wire [0:fc_cmd_width-1]     ec4_cmd;
   wire [0:cdb_width_w_par-1]        ec4_cdb; 
   wire [0:datalen_width_w_par-1]    ec4_datalen;
   wire [0:tag_width_w_par-1]        ec4_tag;
   wire [0:lunid_width_w_par-1]      ec4_lun;
   wire 		       ec4_v, ec4_r;
   
   base_aburp#(.width(fc_cmd_width+cdb_width_w_par+datalen_width_w_par+tag_width_w_par+lunid_width_w_par)) iec4_lat 
     (.clk(clk),.reset(reset),
      .i_v(ec3d_v[0]),.i_r(ec3d_r[0]),.i_d({ec3_cmd,ec3_cdb,ec3_datalen,ec3_tag,ec3_lun}),
      .o_v(ec4_v),.o_r(ec4_r),.o_d({ec4_cmd,ec4_cdb,ec4_datalen,ec4_tag,ec4_lun}),.burp_v());
   
   assign ec4_r = o_fc_req_r;
   assign o_fc_req_v = ec4_v;
   assign o_fc_req_cmd = ec4_cmd;
   assign o_fc_req_tag = ec4_tag[0:tag_width_w_par-2];
   assign o_fc_req_tag_par = ec4_tag[tag_width_w_par-1];
   assign o_fc_req_lun = ec4_lun[0:lunid_width_w_par-2];
   assign o_fc_req_lun_par = ec4_lun[lunid_width_w_par-1];
   assign o_fc_req_length = ec4_datalen[0:datalen_width_w_par-2];
   assign o_fc_req_length_par = ec4_datalen[datalen_width_w_par-1];
   assign o_fc_req_cdb = ec4_cdb[0:cdb_width-1];
   assign o_fc_req_cdb_par = ec4_cdb[128:129];


   //----------------------------------------------------------------------
   // Response from fiber channel

   wire 			    s1_rsp_v, s1_rsp_r /* synthesis keep = 1 */;
   wire [0:tag_width_w_par-1] 	    s1_rsp_tag;
   wire 			    s0_rsp_en = s1_rsp_r | ~s1_rsp_v;

   // write data request
   wire 			    wd0_v, wd0_r;
   wire [0:tag_width_w_par-1] 	    wd0_tag; 
   wire [0:datalen_width_w_par-1] 	    wd0_size; 
   wire [0:beatid_width-1] 	    wd0_beat;
   base_aburp_latch#(.width(tag_width_w_par+datalen_width_w_par+beatid_width)) iwd0_lat
     (.clk(clk),.reset(reset),
      .i_v(i_fc_wdata_req_v),.i_r(i_fc_wdata_req_r),.i_d({i_fc_wdata_req_tag,i_fc_wdata_req_tag_par,i_fc_wdata_req_size,i_fc_wdata_req_size_par,i_fc_wdata_req_beat}), 
      .o_v(wd0_v),.o_r(wd0_r),.o_d({wd0_tag,wd0_size,wd0_beat}));

   wire 			    wd1_v, wd1_r, wd1_re;
   wire [0:tag_width_w_par-1] 	    wd1_tag;  
   wire [0:datalen_width_w_par-1] 	    wd1_size; 
   wire [0:beatid_width-1] 	    wd1_beat;
			    
   // from memory
   wire 			    wd1_wr;
   wire [0:tstag_width-1] 	    wd1_tstag;   
   wire [0:ctxtid_width-1] 	    wd1_ctxt;
   wire [0:ea_width-1] 		    wd1_ea;
   wire [0:datalen_width_w_par-1] 	    wd1_max_datalen;

   
   base_alatch_oe#(.width(tag_width_w_par+datalen_width_w_par+beatid_width)) iwd1_lat
     (.clk(clk),.reset(reset),
      .i_v(wd0_v),.i_r(wd0_r),.i_d({wd0_tag,wd0_size,wd0_beat}),
      .o_v(wd1_v),.o_r(wd1_r),.o_d({wd1_tag,wd1_size,wd1_beat}),.o_en(wd1_re));

   wire [0:tag_width_w_par-1] 	    rd1_tag;
   wire [0:tag_width_w_par-1] 	    wd4_tag;
   wire [0:tag_width_w_par-1] 	    s2_rsp_tag;
   wire 			    wd4_v, wd4_r, wd4_e;
   wire 			    rd1_v, rd1_r, rd1_e;
   wire 			    s2a_rsp_v, s2a_rsp_r;

   wire [0:12]                       s1_perror;
   capi_parcheck#(.width(tag_width)) ec2_tag_pcheck(.clk(clk),.reset(reset),.i_v(ec2_v),.i_d(ec2_tag[0:tag_width_w_par-2]),.i_p(ec2_tag[tag_width_w_par-1]),.o_error(s1_perror[0]));
   capi_parcheck#(.width(tag_width)) wd0_tag_pcheck(.clk(clk),.reset(reset),.i_v(wd0_v),.i_d(wd0_tag[0:tag_width_w_par-2]),.i_p(wd0_tag[tag_width_w_par-1]),.o_error(s1_perror[1]));
   capi_parcheck#(.width(tag_width)) ec3_tag_pcheck(.clk(clk),.reset(reset),.i_v(ec3b_v[1]),.i_d(ec3_tag[0:tag_width_w_par-2]),.i_p(ec3_tag[tag_width_w_par-1]),.o_error(s1_perror[2]));
   capi_parcheck#(.width(tag_width)) o_rslt_tag_pcheck(.clk(clk),.reset(reset),.i_v(o_rslt_v),.i_d(o_rslt_tag[0:tag_width_w_par-2]),.i_p(o_rslt_tag[tag_width_w_par-1]),.o_error(s1_perror[3]));
   capi_parcheck#(.width(tag_width)) rd1_tag_pcheck(.clk(clk),.reset(reset),.i_v(rd1_v),.i_d(rd1_tag[0:tag_width_w_par-2]),.i_p(rd1_tag[tag_width_w_par-1]),.o_error(s1_perror[4]));
   capi_parcheck#(.width(tag_width)) wd4_tag_pcheck(.clk(clk),.reset(reset),.i_v(wd4_v),.i_d(wd4_tag[0:tag_width_w_par-2]),.i_p(wd4_tag[tag_width_w_par-1]),.o_error(s1_perror[5]));
   capi_parcheck#(.width(tag_width)) s2_rsp_tag_pcheck(.clk(clk),.reset(reset),.i_v(s2a_rsp_v),.i_d(s2_rsp_tag[0:tag_width_w_par-2]),.i_p(s2_rsp_tag[tag_width_w_par-1]),.o_error(s1_perror[6]));
   wire [0:12] 				hld_perror;
   wire                                 any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(13)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(13'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror),.q(o_perror[0]));


   base_mem#(.addr_width(tag_width),.width(1+tstag_width+ctxtid_width+ea_width+datalen_width_w_par)) iwcmd_wmem   
     (.clk(clk),
      .we(ec2_v & ec2_r),.wa(ec2_tag[0:tag_width_w_par-2]),.wd({ec2_wr,ec2_tstag,ec2_ctxt,ec2_ea,    ec2_datalen}),
      .re(wd1_re),       .ra(wd0_tag[0:tag_width_w_par-2]),.rd({wd1_wr,wd1_tstag,wd1_ctxt,wd1_ea,wd1_max_datalen})
      );

   wire 			    wd1_tag_v;
   base_vmem#(.a_width(tag_width),.rports(1)) iwcmd_vmem
     (.clk(clk),.reset(reset),
      .i_set_v(ec3d_v[0] & ec3d_r[0]),.i_set_a(ec3_tag[0:tag_width_w_par-2]),
      .i_rst_v(o_rslt_v & o_rslt_r),.i_rst_a(o_rslt_tag[0:tag_width_w_par-2]),
      .i_rd_en(wd1_re),.i_rd_a(wd0_tag[0:tag_width_w_par-2]),.o_rd_d(wd1_tag_v));

   localparam beat_shift = $clog2(fc_data_width/8);

   wire [0:datalen_width-1] 	    wd1_posn = {wd1_beat,{beat_shift{1'b0}}};
   capi_parcheck#(.width(datalen_width)) wd1_size_pcheck(.clk(clk),.reset(reset),.i_v(wd1_v),.i_d(wd1_size[0:datalen_width_w_par-2]),.i_p(wd1_size[datalen_width_w_par-1]),.o_error(s1_perror[7]));
   wire [0:datalen_width-1] 	    wd1_rdata_len = wd1_size[0:datalen_width_w_par-2] + {wd1_beat,{beat_shift{1'b0}}};

   capi_parcheck#(.width(datalen_width)) wd1_max_datalen_pcheck(.clk(clk),.reset(reset),.i_v(wd1_v),.i_d(wd1_max_datalen[0:datalen_width_w_par-2]),.i_p(wd1_max_datalen[datalen_width_w_par-1]),.o_error(s1_perror[11]));
  

   wire 			    wd1_len_ok = wd1_rdata_len <= wd1_max_datalen[0:datalen_width_w_par-2];
   wire [0:2] 			    wd1_error = {~wd1_len_ok,~wd1_tag_v,~wd1_wr};
   
   wire 			    wd1_ok = ~(|wd1_error);

   wire                            wd1_st_ea_par  ; 
   wire [0:ea_width-1] 		    wd1_st_ea = {(wd1_ea[0:ea_width-2] + wd1_posn),wd1_st_ea_par};
   capi_parcheck#(.width(64)) wd1_ea_pcheck(.clk(clk),.reset(reset),.i_v(wd1_v),.i_d(wd1_ea[0:ea_width-2]),.i_p(wd1_ea[ea_width-1]),.o_error(s1_perror[8]));
   capi_parity_gen#(.dwidth(ea_width-1),.width(1)) ch_pgen(.i_d(wd1_st_ea[0:ea_width-2]),.o_d(wd1_st_ea_par));

   wire 			    wd2_v, wd2_r, wd2_ok;
   wire [0:2] 			    wd2_error;
   wire [0:beatid_width-1] 	    wd2_starting_beat;
   wire [0:tag_width_w_par-1] 	    wd2_tag;
   wire [0:tstag_width-1] 	    wd2_tstag; 
   wire [0:ctxtid_width-1] 	    wd2_ctxt;
   wire [0:datalen_width_w_par-1] 	    wd2_size;  
   wire [0:ea_width-1] 		    wd2_ea;
   base_alatch#(.width(1+3+beatid_width+tag_width_w_par+tstag_width+ctxtid_width+datalen_width_w_par+ea_width)) iwd2_lat     
     (.clk(clk),.reset(reset),
      .i_v(wd1_v),.i_r(wd1_r),.i_d({wd1_ok,wd1_error,wd1_beat,         wd1_tag,wd1_tstag,wd1_ctxt,wd1_size,wd1_st_ea}),
      .o_v(wd2_v),.o_r(wd2_r),.o_d({wd2_ok,wd2_error,wd2_starting_beat,wd2_tag,wd2_tstag,wd2_ctxt,wd2_size,wd2_ea})
      );

   wire [0:1] 			    wd2a_v, wd2a_r;
   base_acombine#(.ni(1),.no(2)) iwd2_cmb(.i_v(wd2_v),.i_r(wd2_r),.o_v(wd2a_v),.o_r(wd2a_r));
   base_afilter iwd2_flt(.i_v(wd2a_v[0]),.i_r(wd2a_r[0]),.o_v(get_addr_v),.o_r(get_addr_r),.en(wd2_ok));
   assign get_addr_d_ea = wd2_ea;
   assign get_addr_d_size = wd2_size[0:datalen_width_w_par-2]; 
   assign get_addr_d_tstag = wd2_tstag;
   assign get_addr_d_ctxt = wd2_ctxt;

   wire [0:3] 			    wd3_error;
   wire [0:beatid_width-1] 	    wd3_starting_beat;
   wire [0:tag_width_w_par-1] 	    wd3_tag;
   wire 			    wd3_ok;
   wire 			    wd3b_v, wd3b_r;
   base_fifo#(.LOG_DEPTH(2),.width(1+3+beatid_width+tag_width_w_par)) iwda_fifo
     (.clk(clk),.reset(reset),
      .i_v(wd2a_v[1]),.i_r(wd2a_r[1]),.i_d({wd2_ok,wd2_error,      wd2_starting_beat,wd2_tag}),
      .o_v(wd3b_v),   .o_r(wd3b_r),   .o_d({wd3_ok,wd3_error[0:2], wd3_starting_beat,wd3_tag})
      );


   // response data
   wire 			    g1a_v, g1a_r, g1_e;
   base_aesplit iget_aesplit(.clk(clk),.reset(reset),.i_v(get_data_v),.i_r(get_data_r),.i_e(get_data_e),.o_v(g1a_v),.o_r(g1a_r),.o_e(g1_e));
      
   // note that an error has occurred - we send error with end signal
   wire 			    g1_err = |get_data_rc;
   wire 			    g1_set_error = g1a_v & g1a_r & (g1_err & ~g1_e);
   wire 			    g1_rst_error = g1a_v & g1a_r & g1_e;
   wire 			    g1_cum_err;
   // capture the first error
   wire 			    g1_rcap_en = g1a_v & g1a_r & g1_err & ~g1_cum_err;
   
   // filter out any beats with an error, or after an error has ocurred except the end beat.
   base_vlat_sr iget_error_lat(.clk(clk),.reset(reset),.set(g1_set_error),.rst(g1_rst_error),.q(g1_cum_err));
   wire 			    g1b_v, g1b_r;                           
   base_afilter ig1_efltr(.i_v(g1a_v),.i_r(g1a_r),.o_v(g1b_v),.o_r(g1b_r),.en(g1_e | ~(g1_cum_err | g1_err)));
   wire [0:dma_rc_width-1] 	    g1_dma_rc;
   base_vlat_en#(.width(dma_rc_width)) ig1_errlat(.clk(clk),.reset(reset),.din(get_data_rc),.q(g1_dma_rc),.enable(g1_rcap_en));

   wire 			    wd3a_v, wd3a_r, wd3a_e;
   wire [0:fc_data_width-1+2] 	    wd3_d;
   wire 			    wd3_data_error;
   wire [0:dma_rc_width-1] 	    wd3_dma_rc;
   
   //   base_aegasket#(.ni(16),.no(fc_data_width/8),.width(8),.eaux_width(1+dma_rc_width)) iwd_gasket
 //  base_dncvt#(.ni(16),.no(fc_data_width/8),.width(8),.eaux_width(1+dma_rc_width)) iwd_gasket
 //    (.clk(clk),.reset(reset),
 //     .i_v(g1b_v),.i_r(g1b_r),.i_d(get_data_d), .i_e(g1_e),  .i_eaux({g1_cum_err,g1_dma_rc}),     .i_c({~(|get_data_c),get_data_c}),
 //     .o_v(wd3a_v),.o_r(wd3a_r),.o_d(wd3_d),    .o_e(wd3a_e),.o_eaux({wd3_data_error,wd3_dma_rc}),.o_c());

   assign wd3a_v = g1b_v;
   assign g1b_r = wd3a_r;
   assign wd3_d = get_data_d;
   assign wd3a_e = g1_e;
   assign wd3_data_error = g1_cum_err;
   assign wd3_dma_rc = g1_dma_rc;


   // force an empty response if we failed to send and address
   wire [0:1] 			    wd3c_v, wd3c_r;
   base_aforce wd3a_frc(.i_v(wd3a_v),.i_r(wd3a_r),.o_v(wd3c_v[0]),.o_r(wd3c_r[0]),.en(wd3_ok));
//   wire 			    wd3_e = wd3a_e | ~wd3_ok; rplace wd3a_e with g1_e
   wire 			    wd3_e = g1_e | ~wd3_ok;
   assign wd3_error[3] = wd3_ok & wd3_data_error;

   // repeat the addres info until the data stream ends
   base_arfilter wd3b_rfltr(.i_v(wd3b_v),.i_r(wd3b_r),.o_v(wd3c_v[1]),.o_r(wd3c_r[1]),.en(wd3_e));
   
   // combine the data and address streams
   wire 			    wd3_v, wd3_r;
   base_acombine#(.ni(2),.no(1)) iwd3_cmb(.i_v(wd3c_v),.i_r(wd3c_r),.o_v(wd3_v),.o_r(wd3_r));

   // detect first beat of new stream
   wire 			    wd3_f;
   base_afirst iwd3_fst(.clk(clk),.reset(reset),.i_v(wd3_v),.i_r(wd3_r),.i_e(wd3_e),.o_first(wd3_f));
   
   // track which beat we are on
   wire 			    wd3_beat_en = wd3_v & wd3_r;
   localparam [0:beatid_width-1] beat_one = 1;
   wire [0:beatid_width-1] 	    wd4_beat;
   wire [0:beatid_width-1] 	    wd3_beat_nxt = wd4_beat + beat_one;
   wire [0:beatid_width-1] 	    wd3_beat_in = wd3_f ? wd3_starting_beat : wd3_beat_nxt;
   base_vlat_en#(.width(beatid_width)) iwd4_beat_lat
     (.clk(clk),.reset(1'b0),
      .din(wd3_beat_in),.q(wd4_beat),.enable(wd3_beat_en));
   wire [0:3] 			    wd4_error;
   wire [0:fc_data_width_w_par-1] 	    wd4_d;                                    
   wire [0:dma_rc_width-1] 	    wd4_dma_rc;
   base_alatch#(.width(4+1+tag_width_w_par+dma_rc_width+fc_data_width_w_par)) iwd4_lat  
     (.clk(clk),.reset(reset),
      .i_v(wd3_v),.i_r(wd3_r),.i_d({wd3_error,wd3_e,wd3_tag,wd3_dma_rc,wd3_d}),
      .o_v(wd4_v),.o_r(wd4_r),.o_d({wd4_error,wd4_e,wd4_tag,wd4_dma_rc,wd4_d})
      );
   wire 			    wd4_is_error = wd4_e & (| wd4_error);

   wire 			    wd4_dma_error = wd4_error[3];
   wire 			    wd4_afu_int_error = |wd4_error[0:1];
   wire 			    wd4_uexp_wr_error = wd4_error[2];
   wire [0:2] 			    wd4_pe_error;
   base_prienc_hp#(.ways(3)) iwd4_prienc(.din({wd4_uexp_wr_error,wd4_afu_int_error,wd4_dma_error}),.dout(wd4_pe_error),.kill());
   wire [0:afu_rc_width-1] 	    wd4_afu_rc;
   base_mux#(.ways(3),.width(afu_rc_width)) iwd4_afu_rc_mux
     (.din({afuerr_unexpected_write_data,afuerr_int_error,afuerr_dma_error}),.sel(wd4_pe_error),.dout(wd4_afu_rc));
   
   wire [0:afu_erc_width-1] 	    wd4_afu_erc = wd4_pe_error[2] ? wd4_dma_rc : {1'b1,wd4_error};
   wire [0:1] 			    wd4a_v, wd4a_r;
   base_acombine#(.ni(1),.no(2)) iwd4_cmb(.i_v(wd4_v),.i_r(wd4_r),.o_v(wd4a_v),.o_r(wd4a_r));
     
   
   
   // final output - burp for backpresure timing
   base_aburp_latch#(.width(1+1+tag_width_w_par+beatid_width+fc_data_width_w_par)) iwd5_lat 
     (.clk(clk),.reset(reset),
      .i_v(wd4a_v[0]),.i_r(wd4a_r[0]),.i_d({wd4_is_error,wd4_e,wd4_tag,wd4_beat,wd4_d}),
      .o_v(o_fc_wdata_rsp_v),.o_r(o_fc_wdata_rsp_r),.o_d({o_fc_wdata_rsp_error,o_fc_wdata_rsp_e,o_fc_wdata_rsp_tag,o_fc_wdata_rsp_tag_par,o_fc_wdata_rsp_beat,o_fc_wdata_rsp_data,o_fc_wdata_rsp_data_par})
      );

   // record any errors for final response
   wire [0:1] 			    s1_error_v, s1_error_r, s1_error_e, s2_error_v, s2_error_r;
   
   wire [0:tag_width_w_par*2-1] 	    s1_error_tag,  s2_error_tag;
   wire [0:afu_rsp_width*2-1] 	    s1_error_d;
   
   base_afilter wd4_fltr(.i_v(wd4a_v[1]),.i_r(wd4a_r[1]),.o_v(s1_error_v[0]),.o_r(s1_error_r[0]),.en(wd4_is_error));
   assign s1_error_tag[0:tag_width_w_par-1] = wd4_tag; 
   assign s1_error_d[0:afu_rsp_width-1] = {wd4_afu_rc,wd4_afu_erc};
   assign s1_error_e[0] = 1'b1;
   assign s2_error_r[0] = 1'b1;
   

   //-------------------------------------------------------------------
   // read data
   //------------------------------------------------------------------
   wire [0:fc_bytec_width-1] 	    rd1_c;
   wire [0:beatid_width-1] 	    rd1_beat;
   wire [0:fc_data_width_w_par-1] 	    rd1_d;

   wire 			    rd0_f;
   base_afirst ird1_fst(.clk(clk),.reset(reset),.i_v(i_fc_rdata_rsp_v),.i_r(i_fc_rdata_rsp_r),.i_e(i_fc_rdata_rsp_e),.o_first(rd0_f));

   wire 			    rd1_f;
   base_aburp_latch#(.width(2+fc_bytec_width+beatid_width+tag_width_w_par+fc_data_width+fc_data_par_width)) ird1_lat
     (.clk(clk),.reset(reset),
      .i_v(i_fc_rdata_rsp_v),.i_r(i_fc_rdata_rsp_r),.i_d({rd0_f,i_fc_rdata_rsp_e,i_fc_rdata_rsp_c,i_fc_rdata_rsp_beat,i_fc_rdata_rsp_tag,i_fc_rdata_rsp_tag_par,i_fc_rdata_rsp_data,i_fc_rdata_rsp_data_par}),
      .o_v(rd1_v),.o_r(rd1_r),.o_d({rd1_f,rd1_e,rd1_c,rd1_beat,rd1_tag,rd1_d})
      );

   wire [0:fc_bytec_width-1] 	    rd1a_c;
   assign rd1a_c[1:fc_bytec_width-1] = rd1_c[1:fc_bytec_width-1];
   assign rd1a_c[0] = ~(|rd1_c) | rd1_c[0];
   


   wire [0:beatid_width-1] 	    rd2_beat_calc;
   wire [0:beatid_width-1] 	    rd1_beat_calc = rd1_f ? rd1_beat : rd2_beat_calc+beat_one;
   wire [0:datalen_width-1] 	    rd1_st_byte = {rd1_beat,{beat_shift{1'b0}}};
   wire [0:datalen_width-1] 	    rd1_end = rd1_st_byte+rd1a_c;

   wire 			    rd2_v, rd2_r, rd2_f, rd2_e;
   wire [0:fc_bytec_width-1] 	    rd2_c;
   wire [0:beatid_width-1] 	    rd2_beat;
   wire [0:tag_width_w_par-1] 	    rd2_tag;
   wire [0:fc_data_width_w_par-1] 	    rd2_d;
   wire 			    rd2_re;
   wire [0:datalen_width-1] 	    rd2_st_byte;
   wire [0:datalen_width-1] 	    rd2_end;
   base_alatch_oe#(.width(1+1+fc_bytec_width+beatid_width+tag_width_w_par+fc_data_width_w_par+datalen_width+datalen_width)) ird2_lat 
     (.clk(clk),.reset(reset),
      .i_v(rd1_v),.i_r(rd1_r),.i_d({rd1_f,rd1_e,rd1a_c,rd1_beat,rd1_tag,rd1_d,rd1_end,rd1_st_byte}),
      .o_v(rd2_v),.o_r(rd2_r),.o_d({rd2_f,rd2_e,rd2_c,rd2_beat,rd2_tag,rd2_d,rd2_end,rd2_st_byte}),.o_en(rd2_re)
      );

   base_vlat_en#(.width(beatid_width)) ird2_beat_lat
     (.clk(clk),.reset(reset),
      .din(rd1_beat_calc),.q(rd2_beat_calc),.enable(rd1_v & rd1_r)
      );
   
   wire 			    rd2_rd;
   wire [0:tstag_width-1] 	    rd2_tstag;  
   wire [0:ctxtid_width-1] 	    rd2_ctxt;
   wire [0:ea_width-1] 		    rd2_base_ea;
   wire [0:datalen_width_w_par-1] 	    rd2_max_datalen;
   
   base_mem#(.addr_width(tag_width),.width(1+tstag_width+ctxtid_width+ea_width+datalen_width_w_par)) ircmd_wmem
     (.clk(clk),
      .we(ec2_v & ec2_r),.wa(ec2_tag[0:tag_width_w_par-2]),.wd({ec2_rd,ec2_tstag,ec2_ctxt,ec2_ea,    ec2_datalen}),  
      .re(rd2_re),       .ra(rd1_tag[0:tag_width_w_par-2]),.rd({rd2_rd,rd2_tstag,rd2_ctxt,rd2_base_ea,rd2_max_datalen})
      );
   wire 			    rd2_tag_v;

   // only allow dma write if the command is a valid read command
   base_vmem#(.a_width(tag_width),.rports(1)) ircmd_vmem
     (.clk(clk),.reset(reset),
      .i_set_v(ec3d_v[0] & ec3d_r[0] & ec3_rd),.i_set_a(ec3_tag[0:tag_width_w_par-2]),
      .i_rst_v(o_rslt_v & o_rslt_r),.i_rst_a(o_rslt_tag[0:tag_width_w_par-2]),
      .i_rd_en(rd2_re),.i_rd_a(rd1_tag[0:tag_width_w_par-2]),.o_rd_d(rd2_tag_v));

   wire                            rd2_ea_par ;  
   wire [0:ea_width-1] 		    rd2_ea  = {rd2_base_ea[0:ea_width-2]+rd2_st_byte,rd2_ea_par};
   capi_parcheck#(.width(64)) rd2_base_ea_pcheck(.clk(clk),.reset(reset),.i_v(rd2_v),.i_d(rd2_base_ea[0:ea_width-2]),.i_p(rd2_base_ea[ea_width-1]),.o_error(s1_perror[9]));
   capi_parity_gen#(.dwidth(ea_width-1),.width(1)) ch_pgen1(.i_d(rd2_ea[0:ea_width-2]),.o_d(rd2_ea_par));
   wire 			    rd2_in_range = rd2_e | (rd2_end <= rd2_max_datalen);
   wire 			    rd2_beat_ok = rd2_e | (rd2_beat == rd2_beat_calc);
   wire [0:3] 			    rd2_error = {~rd2_tag_v,~rd2_in_range,~rd2_beat_ok,~rd2_rd};
   
   // ---------------Read Stage 3-------------------------------------
   wire 			    rd3_v, rd3_r, rd3_f, rd3_e;
   wire [0:beatid_width-1] 	    rd3_beat;
   wire [0:tag_width_w_par-1] 	    rd3_tag;
   wire [0:ctxtid_width-1] 	    rd3_ctxt;
   wire [0:tstag_width-1] 	    rd3_tstag;   
   wire [0:ea_width-1] 		    rd3_ea;
   wire [0:3] 			    rd3_error;
   wire [0:fc_bytec_width-1] 	    rd3_c;
   wire [0:fc_data_width_w_par-1] 	    rd3_d;
   base_alatch#(.width(beatid_width+tag_width_w_par+ctxtid_width+tstag_width+ea_width+4+1+1+fc_bytec_width+fc_data_width_w_par)) ird3_lat 
     (.clk(clk),.reset(reset),
      .i_v(rd2_v),.i_r(rd2_r),.i_d({rd2_beat_calc,rd2_tag,rd2_ctxt,rd2_tstag,rd2_ea,rd2_error,rd2_f,rd2_e,rd2_c,rd2_d}),
      .o_v(rd3_v),.o_r(rd3_r),.o_d({rd3_beat,     rd3_tag,rd3_ctxt,rd3_tstag,rd3_ea,rd3_error,rd3_f,rd3_e,rd3_c,rd3_d})
      );
   
   // proceed if the beat is in range, the tag is valid and it is a read command
   wire 			    rd3_ok = ~(|rd3_error);
   
   // send address if ok and first beat
   wire 			    rd3_adr_en = rd3_ok & rd3_f;

   // note that adddress has been sent
   wire 			    rd3_act = rd3_v & rd3_r;
   wire 			    rd3_asent = rd3_act & rd3_adr_en;
   wire 			    rd4_end;
   wire 			    rd4_a_v;
   base_vlat_sr ird4_avld(.clk(clk),.reset(reset),.set(rd3_asent),.rst(rd4_end),.q(rd4_a_v)); // relies on set winning over reset

   wire [0:3] 			    rd3_rst = {4{rd4_end}};
   wire [0:3] 			    rd3_set = {4{rd3_act}} & rd3_error;
   wire [0:3] 			    rd4_error;
   base_vlat_sr#(.width(4)) ird3_error_lat
     (.clk(clk),.reset(reset),
      .set(rd3_set),
      .rst(rd3_rst),
      .q(rd4_error)
      );
   
   wire 			    rd4_v, rd4_r, rd4_f, rd4_e;
   wire [0:beatid_width-1] 	    rd4_beat;
   wire [0:tag_width_w_par-1] 	    rd4_tag;
   wire [0:ctxtid_width-1] 	    rd4_ctxt;
   wire [0:tstag_width-1] 	    rd4_tstag;
   wire [0:ea_width-1] 		    rd4_ea;
   wire [0:fc_bytec_width-1] 	    rd4_c;
   wire [0:fc_data_width_w_par-1] 	    rd4_d;
   assign  rd4_end = rd4_v & rd4_r & rd4_e;

   base_alatch#(.width(beatid_width+tag_width_w_par+ctxtid_width+tstag_width+ea_width+2+fc_bytec_width+fc_data_width_w_par)) ird4_lat  
     (.clk(clk),.reset(reset),
      .i_v(rd3_v),.i_r(rd3_r),.i_d({rd3_beat,rd3_tag,rd3_ctxt,rd3_tstag,rd3_ea,rd3_f,rd3_e,rd3_c,rd3_d}),
      .o_v(rd4_v),.o_r(rd4_r),.o_d({rd4_beat,rd4_tag,rd4_ctxt,rd4_tstag,rd4_ea,rd4_f,rd4_e,rd4_c,rd4_d})
      );

   // split into three streams
   wire [0:2] 			    rd4a_v, rd4a_r;
   base_acombine#(.ni(1),.no(3)) ird4_cmb(.i_v(rd4_v),.i_r(rd4_r),.o_v(rd4a_v),.o_r(rd4a_r));

   // 0: goes to address
   // if the address is not out-of-range, and it is the first beat, send write address
   wire 			    rd4_adr_en = rd4_a_v & rd4_f;
   base_afilter rd4_fltr0(.i_v(rd4a_v[0]),.i_r(rd4a_r[0]),.o_v(put_addr_v),.o_r(put_addr_r),.en(rd4_adr_en));
   assign put_addr_ea = rd4_ea;  
   assign put_addr_ctxt = rd4_ctxt;
   assign put_addr_tstag = rd4_tstag;

   // 1: goes to data
   // send data if we sent an address, and this beat is OK or we are at the end
   wire 			    rd4_ok = ~(|rd4_error);
   wire 			    rd4_dta_en = rd4_a_v & (rd4_ok | rd4_e);
   wire 			    rd4b_v, rd4b_r;
   base_afilter rd3_fltr1(.i_v(rd4a_v[1]),.i_r(rd4a_r[1]),.o_v(rd4b_v),.o_r(rd4b_r),.en(rd4_dta_en));

   assign put_data_c = rd4_c[1:afu_bytec_width]; 
   assign put_data_e = rd4_e;
   assign put_data_d = rd4_d;
   assign rd4b_r = put_data_r;
   assign put_data_v = rd4b_v;
   
   // 2: last beat goes to completion
   wire 			    rd4c_v, rd4c_r;
   base_afilter ird4c_fltr
     (.i_v(rd4a_v[2]),.i_r(rd4a_r[2]),.o_v(rd4c_v), .o_r(rd4c_r),.en(rd4_e));

   wire [0:1] 			    rd5a_v, rd5a_r;
   wire 			    rd5_a_v;
   wire [0:3] 			    rd5_error;
   wire [0:tag_width_w_par-1] 	    rd5_tag; 
   wire [0:beatid_width-1] 	    rd5_beat; 			    
   base_fifo#(.LOG_DEPTH(3),.width(1+4+tag_width_w_par+beatid_width),.output_reg(1)) irda_fifo
     (.clk(clk),.reset(reset),
      .i_v(rd4c_v),    .i_r(rd4c_r),     .i_d({rd4_a_v,rd4_error,rd4_tag,rd4_beat}),
      .o_v(rd5a_v[0]), .o_r(rd5a_r[0]),  .o_d({rd5_a_v,rd5_error,rd5_tag,rd5_beat})
      );


   // force put done if we didn't send an address
   base_aforce ird5_frc
     (.i_v(put_done_v),.i_r(put_done_r),.o_v(rd5a_v[1]),.o_r(rd5a_r[1]),.en(rd5_a_v));

	
   wire  			    rd5_v, rd5_r;
   base_acombine#(.ni(2),.no(1)) ird5_cmb(.i_v(rd5a_v),.i_r(rd5a_r),.o_v(rd5_v),.o_r(rd5_r));


   // track the beat of the last beat so we know when it is ok to send a response
   wire [0:tag_width_w_par-1] 	    s2a_rsp_tag;
   wire [0:beatid_width-1] 	    s2_rsp_act_beats;
   wire 			    s2_rsp_act_v;

   wire [0:tag_width_w_par-1] 	    rd5_tag_del; 
   wire [0:beatid_width-1] 	    rd5_beat_del;
   wire 			    rd5_wen_del;

   base_vlat#(.width(tag_width_w_par+beatid_width)) ilst_beat_wlat
     (.clk(clk),.reset(1'b0),.din({rd5_tag,rd5_beat}),.q({rd5_tag_del,rd5_beat_del}));

   
   // finally, sort out what error codes we will end
   wire 			    rd5_dma_error = rd5_a_v & (|put_done_rc);
   wire 			    rd5_afu_int_error = |rd5_error[0:2];
   wire 			    rd5_uexp_rd_error = rd5_error[3];
   wire [0:2] 			    rd5_pe_error;
   base_prienc_hp#(.ways(3)) ird5_prienc(.din({rd5_uexp_rd_error,rd5_afu_int_error,rd5_dma_error}),.dout(rd5_pe_error),.kill());
   wire [0:afu_rc_width-1] 	    rd5_afu_rc;
   base_mux#(.ways(3),.width(afu_rc_width)) ird5_afu_rc_mux
     (.din({afuerr_unexpected_read_data,afuerr_int_error,afuerr_dma_error}),.sel(rd5_pe_error),.dout(rd5_afu_rc));
   
   wire [0:afu_erc_width-1] 	    rd5_afu_erc = rd5_pe_error[2] ? put_done_rc : {1'b0,rd5_error};
   
   wire 			    rd5_ok = ~(|{rd5_error,rd5_dma_error});

   wire 			    s1_rd_error_v, s1_rd_error_r;
   wire [0:tag_width_w_par-1] 	    s1_rd_error_d;

   assign s1_error_v[1] = rd5_v;
   assign rd5_r = s1_error_r[1];
   assign s1_error_e[1] = ~rd5_ok;
   assign s1_error_tag[tag_width_w_par:2*tag_width_w_par-1] = rd5_tag; 
   assign s1_error_d[(afu_rsp_width): 2*afu_rsp_width-1] = {rd5_afu_rc,rd5_afu_erc};


   // responses
   localparam aux_width = rslt_width-afu_rsp_width;
   
   wire [0:tag_width_w_par-1] 	    s0_rsp_tag; 
   wire [0:aux_width-1] 	    s0_rsp_aux;
   wire [0:beatid_width-1] 	    s0_rsp_rdata_beats;
   wire 			    s0_rsp_v, s0_rsp_r;
     
   base_alatch#(.width(tag_width_w_par+aux_width+beatid_width)) irsp_s1
     (.clk(clk),.reset(reset),
      .i_v(i_fc_rsp_v),.i_r(),      
      .i_d({i_fc_rsp_tag,i_fc_rsp_tag_par, 
	    i_fc_rsp_underrun,i_fc_rsp_overrun,i_fc_rsp_resid,i_fc_rsp_fcstat,i_fc_rsp_fcxstat,i_fc_rsp_scstat,i_fc_rsp_sns_valid,i_fc_rsp_fcp_valid,i_fc_rsp_info,i_fc_rsp_rdata_beats}),
      .o_v(s0_rsp_v),.o_r(s0_rsp_r),.o_d({s0_rsp_tag, s0_rsp_aux,s0_rsp_rdata_beats}));

   wire [0:aux_width-1] 	    s1_rsp_aux;
   wire [0:beatid_width-1] 	    s1_rsp_rdata_beats;

   base_fifo#(.LOG_DEPTH(tag_width),.width(tag_width_w_par+aux_width+beatid_width),.output_reg(1)) irsp_fifo  
     (.clk(clk),.reset(reset),
      .i_v(s0_rsp_v),.i_r(s0_rsp_r),.i_d({s0_rsp_tag, s0_rsp_aux,s0_rsp_rdata_beats}),
      .o_v(s1_rsp_v),.o_r(s1_rsp_r),.o_d({s1_rsp_tag, s1_rsp_aux,s1_rsp_rdata_beats}));

   

   // look up to see whether there is an afu error associated with this tag
   wire 			    s1_rsp_beats_zero = ~(|s1_rsp_rdata_beats);
   wire [0:aux_width-1] 	    s2_rsp_aux;
   wire [0:beatid_width-1] 	    s2_rsp_rdata_beats;
   wire 			    s2_rsp_beats_zero;
   wire [0:afu_rsp_width-1] 	    s2_afu_rsp;
   wire 			    s2_afu_rsp_vld;
   
   // track errors
   ktms_fc_error#(.width(afu_rsp_width),.tag_width(tag_width),.ways(2),.aux_width(aux_width+beatid_width+1)) ifc_error
     (.clk(clk),.reset(reset),
      .i_v(s1_error_v),.i_r(s1_error_r),.i_tag(s1_error_tag),.i_d(s1_error_d),.i_error(s1_error_e),
      .o_v(s2_error_v),.o_r(s2_error_r),.o_tag(s2_error_tag),
      .i_rd_v(s1_rsp_v),.i_rd_r(s1_rsp_r),.i_rd_tag(s1_rsp_tag),.i_rd_aux({s1_rsp_aux,s1_rsp_rdata_beats,s1_rsp_beats_zero}),
      .o_rd_v(s2a_rsp_v),.o_rd_r(s2a_rsp_r),.o_rd_tag(s2_rsp_tag),.o_rd_aux({s2_rsp_aux,s2_rsp_rdata_beats,s2_rsp_beats_zero}),
      .o_rd_d(s2_afu_rsp),.o_rd_dv(s2_afu_rsp_vld),.o_perror(o_perror[1])
      );

   // track read data puts outstanding
   // rd5 indicates that the put has completed.  the rc has been written into ktms_fc_error
   // but it could take a couple of cycles before it gets recorded.
   // one cycle later, s2_rsp_rdoutst_z will go high
   // one cycle later, we set s2_en_d which allows s2a_rsp to proceed. 
   wire s2_rsp_rdoutst_z;
   wire rd6_v, rd6_r;
   wire [0:tag_width_w_par-1] rd6_tag; 
   assign rd6_v = s2_error_v[1];
   assign s2_error_r[1] = rd6_r;
   assign rd6_tag = s2_error_tag[1*tag_width_w_par:2*tag_width_w_par-1];


   // increment the read data packet count as soon as we see it arrive, even if backpressure keeps us from accepting it
   // right away.  B/C, once it is valid on the interface, we could get a repsonse, and we need to know that the data has not
   // yet been transfered so we dont respond back to software until it has
   wire 		rd0_fv = i_fc_rdata_rsp_v & rd0_f;
   wire 		rd0_supress;
   wire 		rd0_supress_set = rd0_fv & ~i_fc_rdata_rsp_r;
   wire 		rd0_supress_rst = i_fc_rdata_rsp_r;
   base_vlat_sr ird1_suppress_lat(.clk(clk),.reset(reset),.set(rd0_supress_set),.rst(rd0_supress_rst),.q(rd0_supress));
   wire 		rd0a_v = rd0_fv & ~rd0_supress;
   wire 		rd1a_inc_v;
   wire [0:tag_width_w_par-1] rd1a_inc_tag;

   base_alatch#(.width(tag_width_w_par)) ird1a_inc_lat(.clk(clk),.reset(reset),.i_v(rd0a_v),.i_r(),.i_d({i_fc_rdata_rsp_tag,i_fc_rdata_rsp_tag_par}),.o_v(rd1a_inc_v),.o_r(1'b1),.o_d(rd1a_inc_tag));

   capi_parcheck#(.width(tag_width_w_par-1)) rd1a_inc_tag_pcheck(.clk(clk),.reset(reset),.i_v(put_addr_v),.i_d(rd1a_inc_tag[0:tag_width_w_par-2]),.i_p(rd1a_inc_tag[tag_width_w_par-1]),.o_error(s1_perror[12]));


   // rd6_v doesn't happen until the data transfer is complete and we have registered any error that might have occured. 
   ktms_fc_incdec#(.id_width(tag_width),.width(8)) irsp_incdec
     (.clk(clk),.reset(reset),
      .i_inc_v(rd1a_inc_v),.i_inc_id(rd1a_inc_tag[0:tag_width_w_par-2]),
      .i_dec_v(rd6_v),.i_dec_r(rd6_r),.i_dec_id(rd6_tag[0:tag_width_w_par-2]),
      .i_rd_a(s2_rsp_tag[0:tag_width_w_par-2]),.o_rd_z(s2_rsp_rdoutst_z)
      );

   wire 		s2_rsp_wdoutst;
   base_vmem#(.a_width(tag_width)) iwdoutst
     (.clk(clk),.reset(reset),
      .i_set_v(wd0_v),.i_set_a(wd0_tag[0:tag_width_w_par-2]),
      .i_rst_v(wd4_v & wd4_e),.i_rst_a(wd4_tag[0:tag_width_w_par-2]),
      .i_rd_a(s2_rsp_tag[0:tag_width_w_par-2]),.i_rd_en(1'b1),.o_rd_d(s2_rsp_wdoutst)
      );
   
   assign s2a_rsp_tag = s2_rsp_tag;
   
   
   wire [0:afu_rsp_width-1] 	    s2_rsp_afu = {afu_rsp_width{s2_afu_rsp_vld}} & s2_afu_rsp;


   // delay enable for 1 cycle for timing. 
   wire 			    s2_en_d;

   wire 			    s2_set_en = s2a_rsp_v & s2_rsp_rdoutst_z & ~s2_rsp_wdoutst & ~s2_en_d;   // can't respond until there are 0 outstanding data transfers for this tag
   wire 			    s2_rst_en = s2a_rsp_v & s2a_rsp_r & s2_en_d;           // reset enable when the response happens
   base_vlat_sr s2_en_lat(.clk(clk),.reset(reset),.set(s2_set_en),.rst(s2_rst_en),.q(s2_en_d));
   
   
   wire 			    s2b_rsp_v, s2b_rsp_r;
   base_agate is2_gt(.i_v(s2a_rsp_v),.i_r(s2a_rsp_r),.o_v(s2b_rsp_v),.o_r(s2b_rsp_r),.en(s2_en_d));

   wire [0:tag_width_w_par-1] 	    s3_rslt_tag;
   wire [0:rslt_width-1] 	    s3_rslt_stat;
   wire 			    s3_rslt_v, s3_rslt_r;
   // send response
   base_alatch_burp#(.width(tag_width_w_par+rslt_width)) is3_lat
     (.clk(clk),.reset(reset),
      .i_v(s2b_rsp_v),.i_r(s2b_rsp_r),.i_d({s2_rsp_tag,s2_rsp_afu,s2_rsp_aux}),
      .o_v(s3_rslt_v),.o_r(s3_rslt_r),.o_d({s3_rslt_tag,s3_rslt_stat})
      );

   wire 			    s3b_rslt_v, s3b_rslt_r;
   wire [0:tag_width_w_par-1] 	    s3b_rsp_tag;
   wire [0:rslt_width-1] 	    s3b_rsp_stat;
   base_primux#(.width(tag_width_w_par+rslt_width),.ways(2)) is4_mux
     (.i_v({s3_rslt_v,ec3d_v[1]}),.i_r({s3_rslt_r,ec3d_r[1]}),.i_d({s3_rslt_tag,s3_rslt_stat,ec3_tag,afu_to_rc,{rslt_width-afu_rc_width{1'b0}}}),   
      .o_v(s3b_rslt_v),.o_r(s3b_rslt_r),.o_d({s3b_rsp_tag,s3b_rsp_stat}),.o_sel()
      );

   
   // send response
   base_alatch_burp#(.width(tag_width_w_par+rslt_width)) is4_lat
     (.clk(clk),.reset(reset),
      .i_v(s3b_rslt_v),.i_r(s3b_rslt_r),.i_d({s3b_rsp_tag,s3b_rsp_stat}),
      .o_v(o_rslt_v),.o_r(o_rslt_r),.o_d({o_rslt_tag,o_rslt_stat})
      );

   // request and response i/o
   assign o_dbg_inc[0] = i_cmd_v & i_cmd_r;
   assign o_dbg_inc[1] = o_fc_req_v & o_fc_req_r;
   assign o_dbg_inc[2] = i_fc_rsp_v;
   assign o_dbg_inc[3] = o_rslt_v & o_rslt_r;

   // are we writing to an address that is not 8byte alligned.
 
   capi_parcheck#(.width(64)) put_addr_ea_pcheck(.clk(clk),.reset(reset),.i_v(put_addr_v),.i_d(put_addr_ea[0:ea_width-2]),.i_p(put_addr_ea[ea_width-1]),.o_error(s1_perror[10]));

   assign o_dbg_inc[4] = put_addr_v & put_addr_r & put_addr_ea[ea_width-3];
   
   assign o_dbg_inc[5] = i_cmd_v & i_cmd_r & i_cmd_rd;
   assign o_dbg_inc[6] = i_cmd_v & i_cmd_r & i_cmd_wr;

   // write data requests
   assign o_dbg_inc[7] = i_fc_wdata_req_v & i_fc_wdata_req_r;
   assign o_dbg_inc[8] = o_fc_wdata_rsp_v & o_fc_wdata_rsp_r & o_fc_wdata_rsp_e;
   assign o_dbg_inc[9] = o_fc_wdata_rsp_v & o_fc_wdata_rsp_r & o_fc_wdata_rsp_e & o_fc_wdata_rsp_error;

  // read data requests
//   assign o_dbg_inc[10] = i_fc_rdata_rsp_v & i_fc_rdata_rsp_r & i_fc_rdata_rsp_e;
  // assign o_dbg_inc[11] = put_done_v & put_done_r & (|put_done_rc);
  // assign o_dbg_inc[12] = i_fc_rdata_rsp_v & i_fc_rdata_rsp_r & rd0_f;
  // assign o_dbg_inc[13] = i_fc_rdata_rsp_v & i_fc_rdata_rsp_r & rd0_f & i_fc_rdata_rsp_beat[beatid_width-1];


   // debug 
   wire 				us_timer;  // pulse once per us.
   wire [0:7] 				us_timer_d;
   base_vlat#(.width(8)) ius_timer_dlat(.clk(clk),.reset(reset),.din(us_timer_d+1'd1),.q(us_timer_d));
`ifdef SIM
     base_vlat#(.width(1)) ius_timer_vlat(.clk(clk),.reset(reset),.din(us_timer_d[7]),.q(us_timer));
`else
     base_vlat#(.width(1)) ius_timer_vlat(.clk(clk),.reset(reset),.din(us_timer_d==8'd0),.q(us_timer));
`endif

   // note 16ms intervals.

   wire [0:13] 				itimer_d;
   base_vlat_en#(.width(14)) itimer_dlat(.clk(clk),.reset(reset),.din(itimer_d+1'b1),.q(itimer_d),.enable(us_timer));

   wire 				s0_idone = &itimer_d;
   
   wire 				s1_idone;  //interval is done
   base_vlat#(.width(1)) s1_idone_lat(.clk(clk),.reset(reset),.din(us_timer & s0_idone),.q(s1_idone));


   // count number of cycles without ready on
   wire [0:22] 				s1_bpcnt_in, s1_bpcnt;
   wire [0:22] 				s1_bpcnt_nxt = s1_bpcnt + 23'b1;
   assign s1_bpcnt_in = s1_idone ? 23'b0 : (put_data_r ? s1_bpcnt_nxt : s1_bpcnt);
   
   base_vlat#(.width(23)) s1_bpcnt_lat(.clk(clk),.reset(reset),.din(s1_bpcnt_in),.q(s1_bpcnt));
   wire 				s1_bpcnt_lt1_4  = s1_idone & ~ (| s1_bpcnt[0:2]);
   wire 				s1_bpcnt_lt1_16 = s1_idone & ~ (| s1_bpcnt[0:4]);
   wire 				s1_bpcnt_lt1_64 = s1_idone & ~ (| s1_bpcnt[0:6]);
   wire 				s1_bpcnt_zro    = s1_idone & ~(| s1_bpcnt);
   base_vlat#(.width(4)) s2_bpcnt_lat(.clk(clk),.reset(reset),.din({s1_bpcnt_lt1_4, s1_bpcnt_lt1_16, s1_bpcnt_lt1_64, s1_bpcnt_zro}),.q(o_dbg_inc[10:13]));
   
   
endmodule // ktms_channel
