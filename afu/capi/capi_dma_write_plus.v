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
module capi_dma_write_plus#
  (parameter tsize_width=12, // transaction size field
   parameter ctag_width=8, // capi tag
   parameter tag_width=3,  // dma engine tag
   parameter rc_width=1,
   parameter beat_width=3, 
   parameter width_512=5,
   parameter ea_width = 64,
   parameter tstag_width=1,
   parameter ctxtid_width = 16,
   parameter sid_width=1,
   parameter uid_width=1,
   parameter csid_width=1,
   parameter rsp_width=rc_width+sid_width+tstag_width+tag_width,
   parameter wr_width = tag_width+sid_width+1+tsize_width + 1+(1+tstag_width)+ctxtid_width + ea_width, 
   parameter wdata_addr_width=tag_width+width_512,
   parameter creq_width = ctag_width+1+csid_width+1+(1+tstag_width)+ctxtid_width+tsize_width+ea_width
   )
   (
    input 			  clk,
    input 			  reset,
    output 			  o_rm_err,
    input 			  i_force_perror,
    input 			  i_req_v,
    output 			  i_req_r,
    input [0:wr_width-1] 	  i_req_d,
    
    output 			  o_req_v,
    input 			  o_req_r,
    output [0:creq_width-1] 	  o_req_d,

    input 			  i_rsp_v,
    input [0:ctag_width-1] 	  i_rsp_ctag,
//    input [0:9] 	          i_rsp_utag,
    input [0:rc_width-1] 	  i_rsp_rc,

    input 			  i_usent_v,
    input [0:9]         	  i_usent_tag,
    input [0:2] 	          i_usent_sts,


    output 			  o_rsp_v,
    output [0:rsp_width-1] 	  o_rsp_d, 

    output 			  o_wdata_req_v,
    output [0:wdata_addr_width-1-3] o_wdata_req_a,

    input 			  i_wdata_rsp_v,
    input [0:1023] 		  i_wdata_rsp_d, // 

    input 			  i_dvalid,
    input [0:7] 		  i_dwad,

    output [0:1023] 		  d0h_ddata,
    output                        o_perror,   
    output [0:((7*3)+4)*64-1]          o_latency_d,
    input                         i_reset_lat_cntrs
    );

   localparam ltag_width = 6;
   localparam aux_width=1+(1+tstag_width)+ctxtid_width;
   
   wire [0:ltag_width+1] data_wa;
   wire                  data_we;


   localparam pwidth=2;  // parity bits per 128 bits of data
//   wire [0:pwidth-1]   data_par;
   wire [0:1023]          mem_wd;

   wire 	       s0_wdata_rsp_v;
   wire [0:1023]        s0_wdata_rsp_d;  

   base_vlat#(.width(1025)) iwdata_rsp_lat(.clk(clk),.reset(reset),.din({i_wdata_rsp_v,i_wdata_rsp_d}),.q({s0_wdata_rsp_v,s0_wdata_rsp_d})); 

   
   base_vlat#(.width(1024)) idlat(.clk(clk),.reset(reset),.din(s0_wdata_rsp_d),.q(mem_wd)); 

   wire 	       s1_rsp_v = i_rsp_v;
   wire 	       s2_rsp_v;
   wire [0:rc_width-1] s1_rsp_rc = i_rsp_rc;
   wire [0:9]          s2_utag;
   wire [0:ltag_width-1] s1_rsp_ltag = i_rsp_ctag[ctag_width-ltag_width:ctag_width-1];
//   base_vlat#(.width(10)) iutag_lat(.clk(clk),.reset(reset),.din(i_rsp_utag),.q(s2_utag));  
   base_vlat#(.width(1)) s2_rsp_lat(.clk(clk),.reset(reset),.din(s1_rsp_v),.q(s2_rsp_v));  


   wire 		 s0_dvalid;
   wire [0:7] 		 s0_dwad;
   
   base_alatch#(.width(8)) is0_brlat
     (.clk(clk),.reset(reset),
      .i_v(i_dvalid),.i_r(),.i_d(i_dwad),
      .o_v(s0_dvalid),.o_r(1'b1),.o_d(s0_dwad)
      );
   
   wire [0:1023] 	 s1_ddata;
   wire [0:15] 		 s1_brpar;
//   wire [0:7] 		 s1_brvld0, s1_brvld1;
	   base_mem#(.width(1024),.addr_width(ltag_width+2)) imem
	    (.clk(clk),
	     .we(data_we),.wa(data_wa),.wd(mem_wd),
	     .re(s0_dvalid),.ra(s0_dwad),.rd(s1_ddata)
	     );
//	   base_vmem#(.a_width(ltag_width)) ivmem0
//	     (.clk(clk),.reset(reset),
//	      .i_set_a(data_wa[0:ltag_width-1]),.i_set_v(data_we[i] & ~data_wa[ltag_width]),
//	      .i_rst_a(s1_rsp_ltag),.i_rst_v(s1_rsp_v),
//	      .i_rd_a(s0_brtag[ctag_width-ltag_width:ctag_width-1]),.i_rd_en(s0_brvalid),.o_rd_d(s1_brvld0[i])
//	      );
//	   base_vmem#(.a_width(ltag_width)) ivmem1
//	     (.clk(clk),.reset(reset),
//	      .i_set_a(data_wa[0:ltag_width-1]),.i_set_v(data_we[i] & data_wa[ltag_width]),
//	      .i_rst_a(s1_rsp_ltag),.i_rst_v(s1_rsp_v),
//	      .i_rd_a(s0_brtag[ctag_width-ltag_width:ctag_width-1]),.i_rd_en(s0_brvalid),.o_rd_d(s1_brvld1[i])
//	      );
   wire s2_brad_5;
//   base_vlat#(.width(1)) is2_brad5(.clk(clk),.reset(reset),.din(s0_brad[5]),.q(s1_brad_5));

//   wire [0:3]   s1_brvld = s1_brad_5 ? s1_brvld1 : s1_brvld0;

     wire [0:1023] s2_ddata;
//   wire [0:7] 	s2_brpar;
//   wire [0:3] 	s2_brvld;
   
   base_vlat#(.width(1024)) is2_brdata(.clk(clk),.reset(1'b0),.din(s1_ddata),.q(s2_ddata));

   assign d0h_ddata = s2_ddata;
 //  base_vlat#(.width(16))  is2_brpar(.clk(clk),.reset(1'b0),.din(s1_brpar),.q(s2_brpar));
//   base_vlat#(.width(8))  is2_brvld(.clk(clk),.reset(1'b0),.din(s1_brvld),.q(s2_brvld));

//   wire [0:511] s2a_brdata;
//   wire [0:7] 	s2a_brpar;
//   genvar 	j;
//   generate
//      for(j=0; j<4; j=j+1)
//	begin : p0
//	   assign s2a_brdata[128*j:128*(j+1)-1] = s2_brvld[j] ? s2_brdata[128*j:128*(j+1)-1] : {128{1'b0}};
//	   assign s2a_brpar[2*j:2*(j+1)-1] = s2_brvld[j] ? ({i_force_perror,1'b0} ^ s2_brpar[2*j:2*(j+1)-1]) : {2'b11};
//	end
//   endgenerate

//   base_vlat#(.width(1024)) is3_brdata(.clk(clk),.reset(1'b0),.din(s2a_brdata),.q(d0h_ddata));
//   base_vlat#(.width(16))  is3_brpar(.clk(clk),.reset(1'b0),.din(s2a_brpar),.q(ah_brpar));
   
   wire [0:tag_width-1]   s1_tag;
   wire tag_v, tag_r;
   wire [0:ltag_width-1] s1_ltag;
   wire [0:sid_width-1]  s1_sid;
   wire [0:tstag_width-1] s1_tstag;
 
   wire [0:tag_width-1]  s2_rsp_tag;
   wire [0:sid_width-1]  s2_rsp_sid;
   wire [0:tstag_width-1] s2_rsp_tstag;

   wire [0:tag_width-1]  s2_usent_tag;
   wire [0:sid_width-1]  s2_usent_sid;
   wire [0:tstag_width-1] s2_usent_tstag;
   
   wire [0:5]          s1_usent_tag = i_usent_tag[4:9];
// usent complete command info

   base_mem#(.addr_width(ltag_width),.width(sid_width+tstag_width+tag_width)) iusent_tag_mem
     (.clk(clk),.re(1'b1),.ra(s1_usent_tag),.rd({s2_usent_sid,s2_usent_tstag,s2_usent_tag}),
      .we(tag_v & tag_r),.wa(s1_ltag),.wd({s1_sid,s1_tstag,s1_tag}));

// non 0 response rc command info
   wire [0:tag_width-1]  s2_response_tag;
   wire [0:sid_width-1]  s2_response_sid;
   wire [0:tstag_width-1] s2_response_tstag;

   base_mem#(.addr_width(ltag_width),.width(sid_width+tstag_width+tag_width)) irsp_tag_mem
     (.clk(clk),.re(1'b1),.ra(s1_rsp_ltag),.rd({s2_response_sid,s2_response_tstag,s2_response_tag}),
      .we(tag_v & tag_r),.wa(s1_ltag),.wd({s1_sid,s1_tstag,s1_tag}));

   wire [0:tag_width-1]  s3_rsp_tag;
   wire [0:sid_width-1]  s3_rsp_sid;
   wire [0:tstag_width-1] s3_rsp_tstag;
   wire [0:ltag_width-1] s3_ltag_free_tag;
   

   wire [0:ltag_width-1]   s2_rsp_ltag;
   wire [0:rc_width-1] 	 s2_rsp_rc;

// add utag array for DMA interface 

   wire 	       s1_usent_v = i_usent_v;
   wire [0:7]          s1_usent_sts = i_usent_sts;
//   wire [0:9]          s1_usent_tag = i_usent_tag;
   wire                usent_error = (s1_usent_sts == 3'd2) ||  (s1_usent_sts == 3'd3); 
   wire [0:7]          s1_usent_rc = usent_error ?8'h01 : 8'h00;

//   base_mem#(.addr_width(10),.width(sid_width+tstag_width+tag_width+ltag_width)) utag_mem
//     (.clk(clk),.re(1'b1),.ra(s1_usent_tag),.rd({s3_rsp_sid,s3_rsp_tstag,s3_rsp_tag,s3_ltag_free_tag}),
//      .we(s2_rsp_v),.wa(s2_utag),.wd({s2_rsp_sid,s2_rsp_tstag,s2_rsp_tag,s2_ltag_free_tag}));

   wire 	       s2_usent_v;
   wire [0:7]          s2_usent_rc;
   wire [0:5]          s2_usent_ltag;
   
   base_vlat#(.width(1+8+6))  is2_usent (.clk(clk),.reset(1'b0),.din({s1_usent_v,s1_usent_rc,s1_usent_tag}),.q({s2_usent_v,s2_usent_rc,s2_usent_ltag}));

// need 2 fifos for usent response and command response the mux them
 wire usent_tag_val;
 wire usent_tag_taken;
 wire [0:5] s3_fifo_usent_ltag;
 wire [0:7] s3_fifo_usent_rc;
  wire [0:sid_width-1] s3_fifo_usent_sid;
  wire [0:tstag_width-1] s3_fifo_usent_tstag;
  wire [0:tag_width-1]    s3_fifo_usent_tag;

   nvme_fifo#(
              .width(6+8+sid_width+tstag_width+tag_width), 
              .words(64),
              .almost_full_thresh(6)
              ) usent_tag
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        s2_usent_v),
      .din(         {s2_usent_ltag,s2_usent_rc,s2_usent_sid,s2_usent_tstag,s2_usent_tag} ),
      .dval(        usent_tag_val ), 
      .pop(         usent_tag_taken),
      .dout(        {s3_fifo_usent_ltag,s3_fifo_usent_rc,s3_fifo_usent_sid,s3_fifo_usent_tstag,s3_fifo_usent_tag} ),
      .full(        ), 
      .almost_full( ), 
      .used());

  wire response_tag_plus_v = s1_rsp_v & |(s1_rsp_rc);
  wire response_tag_val;
  wire response_tag_taken;
  wire r0_response_ok;

  wire s2_response_tag_plus_v;
  wire [0:7]  s2_response_rc;
  wire [0:5]  s2_response_ltag;
  wire [0:7]  s3_fifo_response_rc;
  wire [0:5]  s3_fifo_response_ltag;
  wire [0:sid_width-1] s3_fifo_response_sid;
  wire [0:tstag_width-1] s3_fifo_response_tstag;
  wire [0:tag_width-1]    s3_fifo_response_tag;

   base_vlat#(.width(1+8+6))  is2_response (.clk(clk),.reset(1'b0),.din({response_tag_plus_v,s1_rsp_rc,s1_rsp_ltag}),.q({s2_response_tag_plus_v,s2_response_rc,s2_response_ltag}));

   nvme_fifo#(
              .width(6+8+sid_width+tstag_width+tag_width), 
              .words(64),
              .almost_full_thresh(6)
              ) response_tag
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        s2_response_tag_plus_v),
      .din(         {s2_response_ltag,s2_response_rc,s2_response_sid,s2_response_tstag,s2_response_tag} ),
      .dval(        response_tag_val ), 
      .pop(         response_tag_taken),
      .dout(        {s3_fifo_response_ltag,s3_fifo_response_rc,s3_fifo_response_sid,s3_fifo_response_tstag,s3_fifo_response_tag} ),
      .full(        ), 
      .almost_full( ), 
      .used());

   wire s3_both_v = usent_tag_val | response_tag_val;
   wire [0:5] s3_both_ltag = response_tag_val ? s3_fifo_response_ltag : s3_fifo_usent_ltag;
   wire [0:7] s3_both_rc = response_tag_val ? s3_fifo_response_rc: s3_fifo_usent_rc;
   wire [0:sid_width-1] s3_both_sid = response_tag_val  ? s3_fifo_response_sid : s3_fifo_usent_sid;
   wire [0:tstag_width-1] s3_both_tstag = response_tag_val  ? s3_fifo_response_tstag : s3_fifo_usent_tstag;
   wire [0:tstag_width-1] s3_both_tag = response_tag_val  ? s3_fifo_response_tag : s3_fifo_usent_tag;
   assign usent_tag_taken = usent_tag_val & ~response_tag_val;
   assign response_tag_taken = response_tag_val;
    

 	   

   
   wire [0:7]  s4_rsp_rc;
   wire [0:sid_width-1] s4_rsp_sid;
   wire [0:tstag_width-1] s4_rsp_tstag;
   wire [0:tag_width-1] s4_rsp_tag;
   wire [0:5] s4_rsp_ltag;

   base_alatch#(.width(8+ltag_width+sid_width+tstag_width+tag_width)) is2_rsp
     (.clk(clk),.reset(reset),
      .i_v(s3_both_v),.i_r(),.i_d({s3_both_rc,s3_both_ltag,s3_both_sid,s3_both_tstag,s3_both_tag}),
      .o_v(o_rsp_v),.o_r(1'b1),.o_d({s4_rsp_rc,s4_rsp_ltag,s4_rsp_sid,s4_rsp_tstag,s4_rsp_tag}));

//    wire [0:7]  s3_rsp_total_rc = s2_usent_sts | s3_rsp_rc;

   assign o_rsp_d = {s4_rsp_rc,s4_rsp_sid,s4_rsp_tstag,s4_rsp_tag};

   capi_res_mgr#(.id_width(ltag_width)) irmgr
     (.clk(clk),.reset(reset),.o_avail_v(tag_v),.o_avail_r(tag_r),.o_avail_id(s1_ltag),
      .i_free_v(o_rsp_v),.i_free_id(s4_rsp_ltag),.o_free_err(o_rm_err),.o_cnt(),.o_perror(o_perror)  // free up command tag after utag sent  
      );

   wire tag_allocate = tag_v & tag_r;
   wire tag_deallocate = o_rsp_v;
   wire [0:63] tag_allocate_sum ;
   wire [0:63] tag_allocate_complete;
   wire [0:9] tag_allocate_active;
   wire [0:64*3-1] tag_latency_d;

   nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_tag_allocate (.reset(reset),.clk(clk),
                                                                  .incr(tag_allocate), .decr(tag_deallocate), .clr(i_reset_lat_cntrs),
                                                                  .active_cnt(tag_allocate_active), .complete_cnt(tag_allocate_complete ), .sum(tag_allocate_sum ), .clr_sum(i_reset_lat_cntrs));

  assign tag_latency_d = {tag_allocate_sum,tag_allocate_complete,54'b0,tag_allocate_active};


/* ===============request path===================================== */   
   wire 		 s1_v, s1_r;

   base_acombine#(.ni(2),.no(1)) is1_cmb
     (.i_v({i_req_v,tag_v}),.i_r({i_req_r,tag_r}),.o_v(s1_v),.o_r(s1_r));

   wire [0:tsize_width-1] s1_size;
   wire [0:ea_width-1] 	  s1_ea;
   wire [0:aux_width-1] s1_aux;
   wire 		   s1_f;
   assign s1_tstag = s1_aux[2:2+tstag_width-1];
   assign {s1_tag,s1_sid,s1_f,s1_aux,s1_ea,s1_size} = i_req_d;

   wire [0:5] rsp_port;
   wire [0:5] req_port;
   assign rsp_port[0] = (s4_rsp_tag[0:4] == 5'b00111) & o_rsp_v;
   assign req_port[0] = (s1_tag[0:4] == 5'b00111) & i_req_v & i_req_r;
   assign rsp_port[1] = (s4_rsp_tag[0:4] == 5'b01000) & o_rsp_v;
   assign req_port[1] = (s1_tag[0:4] == 5'b01000) & i_req_v & i_req_r;
   assign rsp_port[2] = (s4_rsp_tag[0:4] == 5'b01001) & o_rsp_v;
   assign req_port[2] = (s1_tag[0:4] == 5'b01001) & i_req_v & i_req_r;
   assign rsp_port[3] = (s4_rsp_tag[0:4] == 5'b01010) & o_rsp_v;
   assign req_port[3] = (s1_tag[0:4] == 5'b01010) & i_req_v & i_req_r;
   assign rsp_port[4] = (s4_rsp_tag[0:4] == 5'b01011) & o_rsp_v;
   assign req_port[4] = (s1_tag[0:4] == 5'b01011) & i_req_v & i_req_r;
   assign rsp_port[5] = (s4_rsp_tag[0:4] == 5'b01100) & o_rsp_v;
   assign req_port[5] = (s1_tag[0:4] == 5'b01100) & i_req_v & i_req_r;

   wire tag_allocate_put[0:6];
   wire tag_deallocate_put[0:6];
   wire [0:64*6-1] put_tag_allocate_sum ;
   wire [0:64*6-1] put_tag_allocate_complete;
   wire [0:10*6-1] put_tag_allocate_active;
   wire [0:64*6*3-1] port_latency_d;

   genvar 			 i;
   generate
      for(i=0; i<6; i=i+1)
      begin : gen1

   assign tag_allocate_put[i] = i_req_v & i_req_r & req_port[i];
   assign tag_deallocate_put[i] = o_rsp_v & rsp_port[i];

        nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_tag_allocate_put (.reset(reset),.clk(clk),
                                                                  .incr(req_port[i]), .decr(rsp_port[i]), .clr(i_reset_lat_cntrs),
                                                                  .active_cnt(put_tag_allocate_active[i*10:(i+1)*10-1]), .complete_cnt(put_tag_allocate_complete[i*64:(i+1)*64-1]), .sum(put_tag_allocate_sum[i*64:(i+1)*64-1]), .clr_sum(i_reset_lat_cntrs));
        assign port_latency_d [i*3*64:(i+1)*3*64-1] = {put_tag_allocate_sum[i*64:(i+1)*64-1],put_tag_allocate_complete[i*64:(i+1)*64-1],54'b0,put_tag_allocate_active[i*10:(i+1)*10-1]};
      end // block: get

   endgenerate

  wire [0:63] total_dma_writes0;
  wire [0:63] total_dma_writes1;
  wire [0:63] total_dma_writes2;
  wire [0:63] total_dma_writes3;

     base_vlat_en#(.width(64)) avg_write_cmd0 (.clk(clk),.reset(reset),.enable(i_req_v & req_port[0]),.din(total_dma_writes0 + {52'b0,s1_size}),.q(total_dma_writes0));
     base_vlat_en#(.width(64)) avg_write_cmd1 (.clk(clk),.reset(reset),.enable(i_req_v & req_port[1]),.din(total_dma_writes1 + {52'b0,s1_size}),.q(total_dma_writes1));
     base_vlat_en#(.width(64)) avg_write_cmd2 (.clk(clk),.reset(reset),.enable(i_req_v & req_port[2]),.din(total_dma_writes2 + {52'b0,s1_size}),.q(total_dma_writes2));
     base_vlat_en#(.width(64)) avg_write_cmd3 (.clk(clk),.reset(reset),.enable(i_req_v & req_port[3]),.din(total_dma_writes3 + {52'b0,s1_size}),.q(total_dma_writes3));

    

  assign o_latency_d = {tag_latency_d,port_latency_d,total_dma_writes0,total_dma_writes1,total_dma_writes2,total_dma_writes3};   


   wire [0:tsize_width-1] s1_size_sum = s1_size;  // address no longer in count calculation for p9psld

   localparam count_width = (tsize_width-4);
   wire [0:count_width-1-3] s1_cnt_raw = s1_size_sum[tsize_width-4-count_width:tsize_width-4-1-3]; 
   wire [0:count_width-1] s1_cnt = (|s1_size_sum[tsize_width-4-3:tsize_width-1]) ? s1_cnt_raw+1 : s1_cnt_raw;       
      

   
   wire [0:width_512-1-3]  s1_beat_st = 5'b00;
   wire 		  s2a_v, s2a_r;
   wire [0:tag_width-1]   s2_tag;
   wire [0:ltag_width-1]  s2_ltag;
   wire [0:tsize_width-1] s2_tsize;
   wire [0:ea_width-1] 	  s2_ea;
   wire [0:aux_width-1] s2_aux;
   wire [0:width_512-1-3]  s2_beat;
   wire 		  s2_e;
   wire [0:sid_width-1]   s2_sid;
   wire 		  s2_f;

//   assign s2a_v = s1_v;
//   assign s1_r = s2a_r;
//   assign s2_tag = s1_tag;
//   assign s2_sid = s1_sid;
//   assign s2_ltag = s1_ltag;
//   assign s2_tsize = s1_size;
//   assign s2_aux = s1_aux;
//   assign s2_ea = s1_ea; 
//   assign s2_e = 1'b1; 
   
   capi_unroll_cnt#(.dwidth(tag_width+sid_width+1+ltag_width+tsize_width+aux_width+ea_width),.iwidth(width_512-3),.cwidth(count_width))iunrl
     (.clk(clk),.reset(reset),
      .din_v(s1_v),.din_r(s1_r),
      .din_c(s1_cnt),       // number of beats
      .din_i(s1_beat_st),                     // starting beat
      .din_d({s1_tag,s1_sid,s1_f,s1_ltag,s1_size,s1_aux,s1_ea}), // constant value
      .dout_v(s2a_v),.dout_r(s2a_r),
      .dout_d({s2_tag,s2_sid,s2_f,s2_ltag,s2_tsize,s2_aux,s2_ea}),  
      .dout_i(s2_beat),
      .dout_s(),
      .dout_e(s2_e)
      );

   wire [0:csid_width-1]  s2_csid = {s2_tag[0:uid_width-1],s2_sid};
 
   // at this point we have one output per beat, with increasing beats fan this out to three places
   // the ultimate capi request[0], a fifo to match with responses[2] and the data request[1]
   wire [0:2] 		  s2b_v, s2b_r;
   base_acombine#(.ni(1),.no(3)) is2_cmb(.i_v(s2a_v),.i_r(s2a_r),.o_v(s2b_v),.o_r(s2b_r));

   // save the tsize and ea of last beat to send to capi
   wire 		  s2c_v, s2c_r;     
   base_afilter is2c_fltr(.i_v(s2b_v[0]),.i_r(s2b_r[0]),.o_v(s2c_v),.o_r(s2c_r),.en(s2_e));



   // hold it up until we get the last beat of the response
   wire [0:1] 		  r1c_v, r1c_r;
   wire [0:tsize_width-1] r1_tsize;
   wire [0:aux_width-1]   r1_aux;
   wire [0:ea_width-1] 	  r1_ea;
   base_alatch#(.width(tsize_width+aux_width+ea_width)) is3ltch
     (.clk(clk),.reset(reset),
      .i_v(s2c_v),.i_r(s2c_r),.i_d({s2_tsize,s2_aux,s2_ea}),
      .o_v(r1c_v[0]),.o_r(r1c_r[0]),.o_d({r1_tsize, r1_aux, r1_ea}));

   // latch for timing
   base_vlat#(.width(1))                iwdreq_vlat(.clk(clk),.reset(reset),.din(s2b_v[1]),        .q(o_wdata_req_v));
   base_vlat#(.width(wdata_addr_width-3)) iwdreq_dlat(.clk(clk),.reset(1'b0), .din({s2_tag,s2_beat}),.q(o_wdata_req_a));
   assign s2b_r[1] = 1'b1;

   // save requests to match up with responses
   wire 		  r1a_v, r1a_r, r1_e;
   wire [0:ltag_width-1]  r1_ltag;
   wire [0:width_512-1-3]  r1_beat;
   wire [0:csid_width-1]  r1_csid;
   wire 		  r1_f;
   
   base_fifo#(.width(1+csid_width+1+ltag_width+width_512-3),.LOG_DEPTH(4)) itag_fifo
     (.clk(clk),.reset(reset),
      .i_v(s2b_v[2]),.i_r(s2b_r[2]),.i_d({s2_e,s2_csid,s2_f,s2_ltag,s2_beat}),
      .o_v(r1a_v),.o_r(r1a_r),.o_d({r1_e,r1_csid,r1_f,r1_ltag,r1_beat})
      );
   
   // combine resonses and requests to write to the dram
   wire 		  dummy_wdata_rsp_r;
   wire 		  r1b_v, r1b_r;
   base_acombine#(.ni(2),.no(1)) ir1_cmb
     (.i_v({r1a_v,s0_wdata_rsp_v}),.i_r({r1a_r,dummy_wdata_rsp_r}),.o_v(r1b_v),.o_r(r1b_r));


   wire 		  r2_v;
   wire [0:ltag_width-1]  r2_ltag;
   wire [0:width_512-1-3]  r2_beat;
   base_vlat#(.width(ltag_width+1+3+2-3)) ir2_lat(.clk(clk),.reset(reset),.q({r2_v,r2_ltag,r2_beat}),.din({r1b_v,r1_ltag,r1_beat}));

   wire [0:7] 		  r2_data_we;
   base_vlat#(.width(ltag_width+2+1)) ir3_lat(.clk(clk),.reset(reset),.q({data_we,data_wa}),.din({r2_v,r2_ltag,r2_beat[0:1]}));

   // when we have written the last beat of data, send request to capi   
   base_afilter ir1_fltr(.en(r1_e),.i_v(r1b_v),.i_r(r1b_r),.o_v(r1c_v[1]),.o_r(r1c_r[1]));
   wire 		  r1d_v, r1d_r;
   base_acombine#(.ni(2),.no(1)) ir1d_cmb(.i_v(r1c_v),.i_r(r1c_r),.o_v(r1d_v),.o_r(r1d_r));

   wire [0:ctag_width-1]  r1_ctag;
   localparam tag_pad_width = ctag_width-ltag_width;
   generate
      if(tag_pad_width == 0) 
	assign r1_ctag = r1_ltag;
      else
	assign r1_ctag = {{tag_pad_width{1'b0}},r1_ltag};
   endgenerate
   
   base_fifo#(.width(creq_width),.LOG_DEPTH(ltag_width)) ireq_fifo
     (.clk(clk),.reset(reset),
      .i_v(r1d_v),.i_r(r1d_r),.i_d({r1_ctag, r1_csid, r1_f, r1_aux,r1_tsize,r1_ea}),
      .o_v(o_req_v),.o_r(o_req_r),.o_d(o_req_d)
      );


endmodule




   

   
   

   
    
   
