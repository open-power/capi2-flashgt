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
 module capi_dma_read_data#
   (parameter ea_width = 65, // changed 64 to 65 to add parity kch 
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
    parameter rsp_width=rc_width+sid_width+tstag_width+tag_width,
    parameter rd_width = tag_width + sid_width+1+tsize_width + 1+ (1+tstag_width)+ctxtid_width+ea_width,
    parameter wdata_addr_width=tag_width+beat_512_width,
    parameter creq_width = ctag_width+1+csid_width+1+(1+tstag_width)+ctxtid_width+tsize_width+ea_width,
    parameter gets = 1
    )
   (
    input 			  clk,
    input 			  reset,

//      .i_v(r1a_v[1]),.i_r(r1a_r[1]),  .i_d({r1_rc,r1_ltag,r1_tag,r1_size,r1_bt,r1_sid,r1_tstag}),
  
    input  [0:1] i_v,
    output [0:1] i_r,
    input  [0:rc_width-1] i_rc,
    input  [0:5] i_ltag,
    input  [0:tag_width-1] i_tag,
    input  [0:tsize_width-1] i_size,
    input  [0:beat_512_width-1] i_bt,
    input  [0:sid_width-1] i_sid,
    input  [0:tstag_width-1] i_tstag,
    input  [0:1023]          i_d,
    input          i_sync,

    
    /* response output needs backpressure due to mux downstream */
    output 			  o_rsp_v, 
    output [0:rsp_width-1] 	  o_rsp_d, 
    
    output 			  o_rdata_v,
    output [0:wdata_addr_width-1] o_rdata_a,
    output [0:129] 		  o_rdata_d,   //  kch changed 127 to 129
    output [0:7]                  o_data_ra,
    output                        o_free_tag_v,
    output [0:5]                  o_free_ltag


     );
   localparam aux_width=1+(1+tstag_width)+ctxtid_width;
   localparam ltag_width = 6;

   wire 			   r2_v, r2_r;
   wire [0:rc_width-1] 		   r2_rc;
   wire [0:tag_width-1] 	   r2_tag;
   wire [0:tsize_width-1] 	   r2_size;
   wire [0:beat_512_width-1] 	   r2_bt;
   wire [0:beat_512_width-1] 	   r2_bt_plus = (r2_size == 12'h080) ? {2'b00,r2_bt[2:4]} : r2_bt;   // needed for pcie 512 byte transfers
   wire [0:5] 	                   r2_ltag;
   wire [0:sid_width-1] 	   r2_sid;
   wire [0:tstag_width-1] 	   r2_tstag;
   wire                            r2_wait_r;

   base_fifo#(.width(rc_width+6+tag_width+tsize_width+beat_512_width+sid_width+tstag_width),.LOG_DEPTH(7),.output_reg(1)) irsp_fifor

     (.clk(clk),.reset(reset),
      .i_v(i_v[1]),.i_r(i_r[1]),  .i_d({i_rc,i_ltag,i_tag,i_size,i_bt,i_sid,i_tstag}),
      .o_v(r2_v),    .o_r(r2_wait_r),      .o_d({r2_rc,r2_ltag,r2_tag,r2_size,r2_bt,r2_sid,r2_tstag})
      );

    

   // when we get a response, we can now transmit the data in multiple beats back to the dma engien   
   wire 		   r3_v, r3_r;
   wire [0:tag_width-1]    r3_tag;
   wire [0:beat_512_width-1]   r3_bt;
   wire [0:rc_width-1] 	   r3_rc;
   wire [0:sid_width-1]    r3_sid;
   wire [0:tstag_width-1]  r3_tstag;
   wire 		   r3_e;
   wire [0:5]              r3_ltag;
   localparam count_width = (tsize_width-4);

// new logic for performance

   wire             r2_rd_data_rdy;
   wire             r3_ra_v;
   wire [0:rc_width-1] 		   r2_rc_hld;
   wire [0:tag_width-1] 	   r2_tag_hld;
   wire [0:tsize_width-1] 	   r2_size_hld;
   wire [0:beat_512_width-1] 	   r2_bt_plus_hld;  
   wire [0:5] 	                   r2_ltag_hld;
   wire [0:sid_width-1] 	   r2_sid_hld;
   wire [0:tstag_width-1] 	   r2_tstag_hld;

   assign o_free_tag_v =           r3_e;
   assign o_free_ltag = 	   r3_e ? r3_ltag:6'b000000;

   base_vlat_sr#(.width(1)) idat_rdy0 (.clk(clk),.reset(reset),.set(r2_v),.rst(r3_e),.q(r2_rd_data_rdy));
   base_vlat_en#(.width(rc_width+6+tag_width+tsize_width+beat_512_width+sid_width+tstag_width)) ir2_dly 
   (.clk(clk),.reset(reset),.enable(r2_v & r2_wait_r),.din({r2_rc,r2_ltag,r2_tag,r2_size,r2_bt_plus,r2_sid,r2_tstag}),.q({r2_rc_hld,r2_ltag_hld,r2_tag_hld,r2_size_hld,r2_bt_plus_hld,r2_sid_hld,r2_tstag_hld}));
   wire r2_data_valid = r2_rd_data_rdy & i_sync & ~r3_e;
   assign r2_wait_r = (r2_r & ~ r2_rd_data_rdy) | r3_e;
//   wire r2_wait_v = r2_v & ~ r2_rd_data_rdy & ~r3_e;
   wire r2_wait_v =  r2_rd_data_rdy & i_sync & ~r3_e;

   capi_read_unroll_cnt#(.dwidth(rc_width+6+tag_width+sid_width+tstag_width),.iwidth(beat_512_width),.cwidth(count_width))iunrl
      (.clk(clk),.reset(reset),
       .din_v(r2_wait_v),.din_r(r2_r),
       .din_c(r2_size_hld[0:count_width-1]),    // number of beats
       .din_i(r2_bt_plus_hld),                       // starting beat 
       .din_d({r2_rc_hld,r2_ltag_hld,r2_tag_hld,r2_sid_hld,r2_tstag_hld}),              // constant value
       .sync_v(1'b0),
       .dout_v(r3_v),.dout_r(r3_r),
       .dout_d({r3_rc,r3_ltag,r3_tag,r3_sid,r3_tstag}),
       .dout_i(r3_bt),
       .dout_s(),
       .dout_e(r3_e),
       .dout_ra_v(r3_ra_v)
       );
   wire 		  s1_r3_v, s1_r3_r;
   wire 		  s2_r3_v, s2_r3_r;
   wire rd_data_port_v;
   wire [0:5]  r4_ltag;
   wire [0:beat_512_width-1]   s1_r3_bt;
   wire [0:beat_512_width-3]   s2_r3_beat;
   wire 		  r4_v, r4_r;
   wire [0:tag_width-1]   s1_r3_tag;
   wire [0:tag_width-1]   r4_tag;
   
   assign o_data_ra =  (r3_ra_v) ? {r3_ltag,r3_bt[0:1]} : 8'h00;  
   assign r3_e_all_ports = r3_e;
   assign r3_ltag_all_ports = r3_e ? r3_ltag : 6'b000000;
   assign o_rdata_v = s1_r3_v;    
   assign o_rdata_a = {s1_r3_tag,s1_r3_bt};
   wire [0:beat_512_width-3]  r5_beat;
   wire [0:1023]               s1_data_rd;
   

//   base_vlat#(.width(beat_512_width-2)) ir5_blat(.clk(clk),.reset(reset),.din(r4_bt[2:beat_512_width-1]),.q(r4_beat));
   base_vlat#(.width(beat_512_width)) is1r3_lat(.clk(clk),.reset(reset),.din(r3_bt),.q(s1_r3_bt));
   base_vlat#(.width(beat_512_width-2)) is2r3_beat(.clk(clk),.reset(reset),.din(s1_r3_bt[2:beat_512_width-1]),.q(s2_r3_beat));
   base_vlat#(.width(tag_width)) is1r3_tag(.clk(clk),.reset(reset),.din(r3_tag),.q(s1_r3_tag));
   base_vlat#(.width(2)) is1r3_vr(.clk(clk),.reset(reset),.din({r3_v,r3_r}),.q({s1_r3_v,s1_r3_r}));
   base_vlat#(.width(2)) is1r3_2_vr(.clk(clk),.reset(reset),.din({s1_r3_v,s1_r3_r}),.q({s2_r3_v,s2_r3_r}));
   base_vlat#(.width(1)) idatard(.clk(clk),.reset(reset),.din(r3_ra_v),.q(rd_data_port_v));
   base_vlat_en#(.width(1024)) is1_dat(.clk(clk), .reset(1'b0), .enable(rd_data_port_v), .din(i_d), .q(s1_data_rd));  
   base_emux#(.width(128),.ways(8)) idmux(.din(s1_data_rd),.sel(s2_r3_beat),.dout(o_rdata_d[0:127]));  // changed from 128 to 130 to add parity kch 

   capi_parity_gen#(.dwidth(64),.width(1)) o_rdata_d_pgen0(.i_d(o_rdata_d[0:63]),.o_d(o_rdata_d[128]));     // gen parity for byte alligned data kch
   capi_parity_gen#(.dwidth(64),.width(1)) o_rdata_d_pgen1(.i_d(o_rdata_d[64:127]),.o_d(o_rdata_d[129]));


   wire 		  r3f_v, r3f_r;
   base_afilter ir3_fltr(.en(r3_e),.i_v(r3_v),.i_r(r3_r),.o_v(r3f_v),.o_r(r3f_r));

   wire [0:rc_width-1] 	  r4_rc;
   wire [0:sid_width-1]   r4_sid;
   wire [0:tstag_width-1] r4_tstag;


   base_alatch#(.width(rc_width+sid_width+tstag_width+tag_width+6)) ir4_lat
     (.clk(clk),.reset(reset),.i_v(r3f_v),.i_r(r3f_r),.i_d({r3_rc,r3_sid,r3_tstag,r3_tag,r3_ltag}),.o_v(r4_v),.o_r(r4_r),.o_d({r4_rc,r4_sid,r4_tstag,r4_tag,r4_ltag}));

   wire 		  r4a_v, r4a_r;
   wire [0:rc_width-1] 	  r4a_rc;
   wire [0:sid_width-1]   r4a_sid;
   wire [0:tstag_width-1] r4a_tstag;
   wire [0:tag_width-1]   r4a_tag;
   wire [0:5]  r4a_ltag;
   wire [0:5]  r5_ltag;
   
   base_primux#(.ways(2),.width(rc_width+sid_width+tstag_width+tag_width+6)) ir4_mux
     (.i_v({i_v[0],r4_v}),.i_r({i_r[0],r4_r}),
      .i_d({i_rc,i_sid,i_tstag,i_tag,i_ltag,
	    r4_rc,r4_sid,r4_tstag,r4_tag,r4_ltag}),
      .o_v(r4a_v),.o_r(r4a_r),.o_d({r4a_rc,r4a_sid,r4a_tstag,r4a_tag,r4a_ltag}),.o_sel());

   base_alatch#(.width(rc_width+sid_width+tstag_width+tag_width+6)) ir5_lat
     (.clk(clk),.reset(reset),
      .i_v(r4a_v),.i_r(r4a_r),.i_d({r4a_rc,r4a_sid,r4a_tstag,r4a_tag,r4a_ltag}),
      .o_v(o_rsp_v),.o_r(1'b1),.o_d({o_rsp_d,r5_ltag}));

endmodule // capi_dma_read_data




   

   
   

   
    
   
