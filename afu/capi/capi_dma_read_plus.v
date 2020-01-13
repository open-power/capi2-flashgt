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
 module capi_dma_read_plus#
   (parameter ea_width = 65,
    parameter ctxtid_width = 16,
    parameter tstag_width = 1,
    parameter tsize_width=12, // transaction size field
    parameter ctag_width=8, // capi tag
    parameter tag_width=3,  // dma engine tag
    parameter beat_width=3,
    parameter beat_512_width=5,
    parameter rc_width=1,
    parameter sid_width=1,
    parameter uid_width=1,
    parameter csid_width=1,
    parameter gets = 1,
    parameter rsp_width=rc_width+sid_width+tstag_width+tag_width,
    parameter rd_width = tag_width + sid_width+1+tsize_width + 1+ (1+tstag_width)+ctxtid_width+ea_width,
    parameter wdata_addr_width=tag_width+beat_512_width,
    parameter creq_width = ctag_width+1+csid_width+1+(1+tstag_width)+ctxtid_width+tsize_width+ea_width
    )
   (
    input 			  clk,
    input 			  reset,
    output 			  o_rm_err,
    
    input 			  i_req_v,
    output 			  i_req_r,
    input [0:rd_width-1] 	  i_req_d,  
     
    output 			  o_req_v,
    input 			  o_req_r,
    output [0:creq_width-1] 	  o_req_d,
    
    /* response output needs backpressure due to mux downstream */
    output [0:gets-1]			  o_rsp_v,
    output [0:gets*rsp_width-1] 	  o_rsp_d, 
    
    output [0:gets-1]			  o_rdata_v,
    output [0:gets*wdata_addr_width-1] o_rdata_a,
    output [0:gets*130-1] 		  o_rdata_d,

    input                         i_tag_plus_v ,
    input [0:7]                   i_rtag_plus,
    input [0:7]                   i_rtag_response_plus,
    input                         i_sent_utag_valid,
    input [0:7]                   i_sent_utag,   

    // dma interface ///
      input                       hd0_cpl_valid,
      input [0:9]                 hd0_cpl_utag,
      input [0:2]                 hd0_cpl_type,
      input [0:9]                 hd0_cpl_size,
      input [0:9]                 hd0_cpl_byte_count,
      input [0:1023]              hd0_cpl_data,
      input [0:6]                 hd0_cpl_laddr,
      output o_ctag_error_hld,
      output o_rtag_error_hld,
      output o_u_sent_tag_error_hld,
      output o_cmplt_utag_error_hld,


    output [0:1]        	  o_perror,  
    output [0:1]                  o_tag_error,
    output [0:8*3*64-1]           o_latency_d,
    input                         i_reset_lat_cntrs
     );
   localparam aux_width=1+(1+tstag_width)+ctxtid_width;
   localparam ltag_width = 6;

   wire [0:9]         s1_hd0_cpl_size;
   wire               size_eq_80 = (s1_hd0_cpl_size == 9'h080);



   wire quad_init_v;
   wire [0:5] quad_init_adr;
   wire [0:1] quad_rd;
   wire [0:5] s1_cpl_utag;
   wire [0:5] quad_wa = quad_init_v ? quad_init_adr : s1_cpl_utag;
   wire [0:1] quad_wd = (quad_init_v | size_eq_80) ?  2'b00 : quad_rd + 2'b01;
   wire       s1_cpl_utag_v;
   wire       quad_we = quad_init_v ? quad_init_v : s1_cpl_utag_v;

   base_initsm#(.COUNT(64), .LOG_COUNT(6)) ism(.clk(clk),.reset(reset),.dout_r(1'b1),.dout_v(quad_init_v),.dout_d(quad_init_adr)); 
   base_vlat#(.width(7)) icpl_u_tag_d1 (.clk(clk),.reset(reset),.din({hd0_cpl_valid,hd0_cpl_utag[4:9]}),.q({s1_cpl_utag_v,s1_cpl_utag}));

   

   base_mem_bypass#(.width(2),.addr_width(6)) imem_quad   
     (.clk(clk),
      .re(1'b1),.ra(hd0_cpl_utag[4:9]),.rd(quad_rd),
      .we(quad_we),.wa(quad_wa),.wd(quad_wd)
      );
   

   wire               s1_hd0_cpl_valid;
   wire [0:1023]      s1_hd0_cpl_data;
   wire [0:5]         s1_hd0_cpl_utag;
   wire [0:9]         s1_hd0_cpl_byte_count;
   wire [0:2]         s1_hd0_cpl_type;


   base_vlat#(.width(1+1024+6+10+10+3)) s1_cpl (.clk(clk),.reset(reset),.din({hd0_cpl_valid,hd0_cpl_data,hd0_cpl_utag[4:9],hd0_cpl_size,hd0_cpl_byte_count,hd0_cpl_type}),.q({s1_hd0_cpl_valid,s1_hd0_cpl_data,s1_hd0_cpl_utag,s1_hd0_cpl_size,s1_hd0_cpl_byte_count,s1_hd0_cpl_type}));
  
   wire read_cmplt_utag_v = s1_hd0_cpl_valid & (s1_hd0_cpl_type != 3'd1) & (s1_hd0_cpl_size == s1_hd0_cpl_byte_count);
   wire  [0:5] read_cmplt_utag = s1_hd0_cpl_utag;
   wire read_cmplt_ok = ~((s1_hd0_cpl_type == 3'd2) || (s1_hd0_cpl_type == 3'd3));
   wire [0:7] read_cmplt_rc = {5'b00000,s1_hd0_cpl_type};

//   wire [0:8] 		           data_ra;
   wire [0:7*8-1]                  data_ra;
   wire [0:7] 		           data_ra_total = data_ra[0:7] | data_ra[8:15] | data_ra[16:23] | data_ra[24:31]  | data_ra[32:39] | data_ra[40:47] | data_ra[48:55];
   wire [0:1023] 		   data_wrt = hd0_cpl_data;
   wire [0:1023] 		   data_rd;
   base_mem#(.width(1024),.addr_width(8)) imem   
     (.clk(clk),
      .re(1'b1),.ra(data_ra_total),.rd(data_rd),
      .we(s1_hd0_cpl_valid),.wa({s1_hd0_cpl_utag,quad_rd}),.wd({s1_hd0_cpl_data})
      );
   
   
    /* send read reqeust as soon as we have a tag */
   wire 			   tag_v, tag_r;
   wire [0:5] 	                   r5_ltag;
   wire [0:5] 	                   s1_ltag;
   wire                            r1_utag_read_ctag_valid;
   wire                            r1_rtag_ctag_valid;
   wire                            r1_utag_sent_ctag_valid;
   wire                            r1_utag_read_rtag_valid;
   wire                            r1_ctag_rtag_valid;
   wire                            r1_utag_sent_rtag_valid;
   wire                            s1_read_utag_outst;
   wire 			   r1_v, r1_r;

// create a ctag and utag for a command
   wire [0:gets-1]        r3_e;
   wire [0:gets*6-1]      r3_ltag;
   wire 		   r3_e_total = |(r3_e);
   wire [0:5]              r3_ltag_total    = r3_ltag[0:5] | r3_ltag[6:11] | r3_ltag[12:17] | r3_ltag[18:23] | r3_ltag[24:29] | r3_ltag[30:35]  | r3_ltag[36:41];
   

   capi_res_mgr#(.id_width(6)) irmgr
     (.clk(clk),.reset(reset),.o_avail_v(tag_v),.o_avail_r(tag_r),.o_avail_id(s1_ltag),
      .i_free_v(r3_e_total),.i_free_id(r3_ltag_total),.o_free_err(o_rm_err),.o_cnt(),.o_perror(o_perror[1])   
      );

   wire tag_allocate = tag_v & tag_r;
   wire tag_deallocate = | (o_rsp_v);
   wire [0:63] tag_allocate_sum ;
   wire [0:63] tag_allocate_complete;
   wire [0:9] tag_allocate_active;
   wire [0:64*3-1] tag_latency_d;

   nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_tag_allocate (.reset(reset),.clk(clk),
                                                                  .incr(tag_allocate), .decr(tag_deallocate), .clr(i_reset_lat_cntrs),
                                                                  .active_cnt(tag_allocate_active), .complete_cnt(tag_allocate_complete ), .sum(tag_allocate_sum ), .clr_sum(i_reset_lat_cntrs));

  assign tag_latency_d = {tag_allocate_sum,tag_allocate_complete,54'b0,tag_allocate_active};
   base_vmem#(.a_width(6),.rports(3)) ictag_valid  
     (.clk(clk),.reset(reset),
      .i_set_v(tag_v & tag_r),.i_set_a(s1_ltag),
      .i_rst_v(read_cmplt_utag_v),.i_rst_a(read_cmplt_utag),
      .i_rd_en(3'b111),.i_rd_a({read_cmplt_utag,i_rtag_plus[2:7],i_sent_utag[2:7]}),.o_rd_d({r1_utag_read_ctag_valid,r1_rtag_ctag_valid,r1_utag_sent_ctag_valid})
      );

   base_vmem#(.a_width(6),.rports(3)) irtag_valid 
     (.clk(clk),.reset(reset),
      .i_set_v(i_tag_plus_v & (i_rtag_plus[0:1] == 2'b01)),.i_set_a(i_rtag_plus[2:7]),
      .i_rst_v(read_cmplt_utag_v),.i_rst_a(read_cmplt_utag),
      .i_rd_en(3'b111),.i_rd_a({read_cmplt_utag,s1_ltag,i_sent_utag[2:7]}),.o_rd_d({r1_utag_read_rtag_valid,r1_ctag_rtag_valid,r1_utag_sent_rtag_valid})
      );

   base_vmem#(.a_width(6),.rports(3)) iustag_valid 
     (.clk(clk),.reset(reset),
      .i_set_v(i_sent_utag_valid & (i_sent_utag[0:1] == 2'b01)),.i_set_a(i_sent_utag[2:7]),
      .i_rst_v(read_cmplt_utag_v),.i_rst_a(read_cmplt_utag),
      .i_rd_en(3'b111),.i_rd_a({read_cmplt_utag,i_rtag_plus[2:7],s1_ltag}),.o_rd_d({r1_utag_read_usent_valid,r1_rtag_usent_valid,r1_ctag_usent_valid})
      );
    wire ctag_error = (tag_v & tag_r) | (r1_ctag_rtag_valid | r1_ctag_usent_valid);
    wire rtag_error = (i_tag_plus_v & (i_rtag_plus[0:1] == 2'b01)) |  (~r1_rtag_ctag_valid | r1_rtag_usent_valid);
    wire usent_tag_error = (i_sent_utag_valid & (i_sent_utag[0:1] == 2'b01)) | ( ~r1_utag_sent_ctag_valid | ~r1_utag_sent_rtag_valid);
    wire cmplt_utag_error = read_cmplt_utag_v &  (~r1_utag_read_ctag_valid | ~r1_utag_read_rtag_valid | ~r1_utag_read_usent_valid);

   wire ctag_error_hld;
   wire rtag_error_hld;
   wire u_sent_tag_error_hld;
   wire cmplt_utag_error_hld;

   base_vlat#(.width(1)) ictag_error_hld (.clk(clk),.reset(reset),.din(ctag_error | ctag_error_hld),.q(ctag_error_hld));
   base_vlat#(.width(1)) irtag_error_hld (.clk(clk),.reset(reset),.din(rtag_error | rtag_error_hld),.q(rtag_error_hld));
   base_vlat#(.width(1)) iusent_tag_error_hld (.clk(clk),.reset(reset),.din(usent_tag_error | u_sent_tag_error_hld),.q(u_sent_tag_error_hld));
   base_vlat#(.width(1)) icmplt_utag_error_hld (.clk(clk),.reset(reset),.din(cmplt_utag_error | cmplt_utag_error_hld),.q(cmplt_utag_error_hld));

   assign o_ctag_error_hld = ctag_error_hld;
   assign o_rtag_error_hld = rtag_error_hld;
   assign o_u_sent_tag_error_hld = u_sent_tag_error_hld;
   assign o_cmplt_utag_error_hld = cmplt_utag_error_hld;

   assign o_tag_error = 2'b00;
   
   wire [0:tag_width-1] 	   s1_tag;
   wire [0:tsize_width-1] 	   s1_size;
   wire [0:ea_width-1] 		   s1_ea;
   wire [0:aux_width-1] 	   s1_aux;
   wire [0:tstag_width-1] 	   s1_tstag = s1_aux[2:tstag_width+2-1];

   wire [0:sid_width-1] 	   s1_sid;
   wire 			   s1_f;
   assign {s1_tag,s1_sid,s1_f,s1_aux,s1_ea,s1_size} = i_req_d;

   wire [0:6] rsp_port;
   wire [0:6] req_port;
   assign req_port[0] = (s1_tag[0:4] == 5'b00000) & i_req_v & i_req_r;
   assign req_port[1] = (s1_tag[0:4] == 5'b00001) & i_req_v & i_req_r;
   assign req_port[2] = (s1_tag[0:4] == 5'b00010) & i_req_v & i_req_r;
   assign req_port[3] = (s1_tag[0:4] == 5'b00011) & i_req_v & i_req_r;
   assign req_port[4] = (s1_tag[0:4] == 5'b00100) & i_req_v & i_req_r;
   assign req_port[5] = (s1_tag[0:4] == 5'b00101) & i_req_v & i_req_r;
   assign req_port[6] = (s1_tag[0:4] == 5'b00110) & i_req_v & i_req_r;
   wire tag_allocate_get[0:7];
   wire tag_deallocate_get[0:7];
   wire [0:64*7-1] get_tag_allocate_sum ;
   wire [0:64*7-1] get_tag_allocate_complete;
   wire [0:10*7-1] get_tag_allocate_active;
   wire [0:64*7*3-1] port_latency_d;


   genvar 			 i;
   generate
      for(i=0; i<7; i=i+1)
      begin : gen1
   assign tag_allocate_get[i] = i_req_v & i_req_r & req_port[i];
   assign tag_deallocate_get[i] = o_rsp_v & rsp_port[i];


        nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_tag_allocate_get (.reset(reset),.clk(clk),
                                                                  .incr(req_port[i]), .decr(o_rsp_v[i]), .clr(i_reset_lat_cntrs),.active_cnt(get_tag_allocate_active[i*10:(i+1)*10-1]), .complete_cnt(get_tag_allocate_complete[i*64:(i+1)*64-1]), .sum(get_tag_allocate_sum[i*64:(i+1)*64-1]), .clr_sum(i_reset_lat_cntrs));
        assign port_latency_d [i*3*64:(i+1)*3*64-1] = {get_tag_allocate_sum[i*64:(i+1)*64-1],get_tag_allocate_complete[i*64:(i+1)*64-1],54'b0,get_tag_allocate_active[i*10:(i+1)*10-1]};
      end 

   endgenerate

  assign o_latency_d = {tag_latency_d,port_latency_d};   



   wire     			   s1_perror;
   wire                            hld_perror;
   base_vlat_sr#(.width(1)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(1'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror),.q(o_perror[0]));

   capi_parcheck#(.width(ea_width-1)) s1_ea_pcheck(.clk(clk),.reset(reset),.i_v(i_req_v),.i_d(s1_ea[0:ea_width-2]),.i_p(s1_ea[ea_width-1]),.o_error(s1_perror));
   wire [0:beat_width-1] 	   s1_beat_st = s1_ea[ea_width-1-4-beat_512_width:ea_width-1-4-1];  
 
   wire                            s1_ea_clapar;
   wire                            s1_size_is_128 = (s1_size == 8'h80);
   
   wire [0:ea_width-1] 		   s1_ea_cla;
   wire [0:ea_width-1] 		   s1_ea_cla_128 = {s1_ea[0:ea_width-1-(beat_width+4)-1],{beat_width+4{1'b0}},s1_ea_clapar};
   wire [0:ea_width-1] 		   s1_ea_cla_512 = {s1_ea[0:ea_width-1-(beat_512_width+4)-1],{beat_512_width+4{1'b0}},s1_ea_clapar}; 

   assign s1_ea_cla = s1_size_is_128 ? s1_ea_cla_128 : s1_ea_cla_512;
   capi_parity_gen#(.dwidth(ea_width-1),.width(1)) s1_ea_cla_pgen(.i_d(s1_ea_cla[0:63]),.o_d(s1_ea_clapar));
   
   wire 			   s1_v = i_req_v;
   wire 			   s1_r;
   assign i_req_r = s1_r;
   base_acombine#(.ni(2),.no(1)) is1_cmb
     (.i_v({s1_v,tag_v}),.i_r({s1_r,tag_r}),.o_v(o_req_v),.o_r(o_req_r));  
   

   wire [0:ctag_width-1]  s1_ctag;
   localparam tag_pad_width = ctag_width-ltag_width;
   generate
      if(tag_pad_width == 0) 
	assign s1_ctag = s1_ltag;
      else
	assign s1_ctag = {{tag_pad_width{1'b0}},s1_ltag};
   endgenerate

   assign o_req_d = {s1_ctag, s1_tag[0:uid_width-1], s1_sid, s1_f,s1_aux, s1_size, s1_ea_cla};

   wire 		  i_cmplt_ok = read_cmplt_ok; // response errors reported elsewhere
   wire [0:5]             i_cmplt_ltag = read_cmplt_utag;
   wire [0:rc_width-1] 	  i_cmplt_rc = read_cmplt_rc;
   wire 		  i_cmplt_v = read_cmplt_utag_v;
   
   wire 			   r1_ok;
   wire [0:rc_width-1] 		   r1_rc;
   wire [0:tag_width-1] 	   r1_tag;
   wire [0:tsize_width-1] 	   r1_size;
   wire [0:beat_512_width-1] 	   r1_bt;
   wire [0:5]                      r1_ltag;
   wire [0:sid_width-1] 	   r1_sid;
   wire [0:tstag_width-1] 	   r1_tstag;
   wire [0:6]                      s2_read_utag;

// need 2 fifos for cmplt response and command response the mux them
 wire cmplt_tag_val;
 wire cmplt_tag_taken;
 wire r0_cmplt_ok;
 wire [0:5] r0_cmplt_ltag;
 wire [0:7] r0_cmplt_rc;

   nvme_fifo#(
              .width(1+6+8), 
              .words(64),
              .almost_full_thresh(6)
              ) cmplt_tag
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        i_cmplt_v),
      .din(         {i_cmplt_ok,i_cmplt_ltag,i_cmplt_rc} ),
      .dval(        cmplt_tag_val ), 
      .pop(         cmplt_tag_taken),
      .dout(        {r0_cmplt_ok,r0_cmplt_ltag,r0_cmplt_rc} ),
      .full(        ), 
      .almost_full( ), 
      .used());

  wire tag_plus_nok = |(i_rtag_response_plus);
  wire tag_plus_ok  = ~tag_plus_nok;
  wire tag_plus_v = i_tag_plus_v & tag_plus_nok;
  wire response_tag_val;
  wire response_tag_taken;
  wire r0_response_ok;
  wire [0:5] r0_response_ltag;
  wire [0:7] r0_response_rc;

   nvme_fifo#(
              .width(1+6+8), 
              .words(64),
              .almost_full_thresh(6)
              ) response_tag
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        tag_plus_v),
      .din(         {tag_plus_ok,i_rtag_plus[2:7],i_rtag_response_plus} ),
      .dval(        response_tag_val ), 
      .pop(         response_tag_taken),
      .dout(        {r0_response_ok,r0_response_ltag,r0_response_rc} ),
      .full(        ), 
      .almost_full( ), 
      .used());

   wire r0_v = cmplt_tag_val | response_tag_val;
   wire r0_ok = response_tag_val ?  r0_response_ok :  r0_cmplt_ok;
   wire [0:5] r0_ltag = response_tag_val ? r0_response_ltag : r0_cmplt_ltag;
   wire [0:7] r0_rc = response_tag_val ? r0_response_rc: r0_cmplt_rc;
   assign cmplt_tag_taken = cmplt_tag_val & ~response_tag_val;
   assign response_tag_taken = response_tag_val;
    

 	   
   base_alatch#(.width(1+rc_width+6)) ir3_lat(.clk(clk),.reset(reset),.i_v(r0_v),.i_r(),.i_d({r0_ok,r0_rc,r0_ltag}),.o_v(r1_v),.o_r(1'b1),.o_d({r1_ok,r1_rc,r1_ltag}));

   base_mem#(.addr_width(6),.width(tag_width+tsize_width+beat_512_width+sid_width+tstag_width)) utag_mem
     (.clk(clk),
      .re(1'b1),.ra(r0_ltag), .rd({r1_tag,r1_size,r1_bt,r1_sid,r1_tstag}),
      .we(tag_v & tag_r),.wa(s1_ltag),.wd({s1_tag,s1_size,s1_ea[ea_width-1-4-beat_512_width:ea_width-1-4-1],s1_sid,s1_tstag}) 
      );


   //   bypass for non-zero returns do that they don't get overtaken by ctxt terminate or timeouts
   wire [0:1] 			   r1a_v, r1a_r;
   wire [0:7]                      r1_dr_v;
   base_ademux#(.ways(2)) ir1_demux(.i_v(r1_v),.i_r(),.o_v(r1a_v),.o_r(r1a_r),.sel({~r1_ok,r1_ok}));
   base_decode#(.enc_width(3)) idread_dec (.en(1'b1),.din(r1_tag[2:4]),.dout(r1_dr_v));

   wire [0:7]   shift_reg;
   base_vlat#(.width(8),.rstv(8'h80)) ishift_reg(.clk(clk),.reset(reset),.din({shift_reg[7],shift_reg[0:6]}),.q(shift_reg));


   generate
      for(i=0; i<gets; i=i+1)
	begin :dmaread
	   

           capi_dma_read_data#(.ea_width(ea_width),.tstag_width(tstag_width),.ctxtid_width(ctxtid_width),.tsize_width(tsize_width),.tag_width(tag_width),.uid_width(uid_width),.sid_width(sid_width), 
		  .csid_width(csid_width),.gets(gets),.wdata_addr_width(wdata_addr_width),
		  .beat_width(beat_width),.ctag_width(ctag_width-2),.rc_width(rc_width)) idma_read_data
	    (
             .clk(clk),.reset(reset),
              // let all good and bad response go through good machine path logic 
             .i_v({1'b0,(r1_v & r1_dr_v[i])} ),.i_r(r1a_r),.i_rc(r1_rc),.i_ltag(r1_ltag),.i_tag(r1_tag),.i_size(r1_size),.i_bt(r1_bt),.i_sid(r1_sid),.i_tstag(r1_tstag),.i_d(data_rd),.i_sync(shift_reg[i]),
             .o_rsp_v(o_rsp_v[i]),.o_rsp_d(o_rsp_d[rsp_width*i:((i+1)*rsp_width)-1]),
             .o_rdata_v(o_rdata_v[i]),.o_rdata_a(o_rdata_a[wdata_addr_width*i:((i+1)*wdata_addr_width)-1]),.o_rdata_d(o_rdata_d[130*i:((i+1)*130)-1]),.o_data_ra(data_ra[8*i:((i+1)*8)-1]),
             .o_free_tag_v(r3_e[i]),.o_free_ltag(r3_ltag[6*i:((i+1)*6)-1])
             );

	end 
  endgenerate



endmodule




   

   
   

   
    
   
