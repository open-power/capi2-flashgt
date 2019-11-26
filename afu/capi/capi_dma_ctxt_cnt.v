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
/* WARNING: effect of inc or dec is delayed by three cycles.  */
module capi_dma_ctxt_cnt#
  (parameter id_width = 1,
   parameter cnt_width = 1
   )
   (input clk,
    input 		 reset,

    output 		 i_inc_r,
    input 		 i_inc_v,
    input [0:id_width-1] i_inc_id,

    input 		 i_dec_v,
    input [0:id_width-1] i_dec_id,

    input [0:id_width-1] i_rd_id,
    output 		 o_rd_zero
    );


   wire 		 s1_v, s1_r;
   wire [0:id_width-1] 	 s1_id;
   wire [0:1] 		 s1_sel;
   wire 		 s0_dec_r_dummy;
   
   base_primux#(.ways(2),.width(id_width)) is1_mux
     (.i_v({i_dec_v,i_inc_v}),.i_r({s0_dec_r_dummy,i_inc_r}),.i_d({i_dec_id,i_inc_id}),
      .o_v(s1_v),.o_r(s1_r),.o_d(s1_id),.o_sel(s1_sel)
      );


   // first cycle of delay
   wire 		 s2_v, s2_r;
   wire [0:1] 		 s2_sel;
   wire [0:id_width-1]  s2_id;
   base_alatch#(.width(id_width+2)) is2_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_v),.i_r(s1_r),.i_d({s1_id,s1_sel}),
      .o_v(s2_v),.o_r(s2_r),.o_d({s2_id,s2_sel})
      );

   // second cycle of delay   
   wire 		 s3_v, s3_r;
   wire [0:id_width-1] 	 s3_id;
   wire [0:1] 		 s3_sel;
   wire 		 s2_re;
   base_alatch_oe#(.width(id_width+2)) is3_lat
     (.clk(clk),.reset(reset),
      .i_v(s2_v),.i_r(s2_r),.i_d({s2_id,s2_sel}),
      .o_v(s3_v),.o_r(s3_r),.o_d({s3_id,s3_sel}),
      .o_en(s2_re)
      );

   assign s3_r = 1'b1;


   
   localparam [0:cnt_width-1] cnt_one = 1;
   
   wire [0:cnt_width-1]  s3_rd_cnt;
   wire 		 s3_cv;
   wire [0:cnt_width-1]  s3_cnt  = s3_cv ? s3_rd_cnt : {cnt_width{1'b0}};
   wire [0:cnt_width-1]  s3_upd_inc = s3_cnt + cnt_one;
   wire [0:cnt_width-1]  s3_upd_dec = s3_cnt - cnt_one;
   wire [0:cnt_width-1]  s3_upd_cnt;
   base_mux#(.width(cnt_width),.ways(2)) is3_mux(.sel(s3_sel),.din({s3_upd_dec,s3_upd_inc}),.dout(s3_upd_cnt));

   // read count = 1
   wire 		 s3_cnt_one = s3_cnt == cnt_one;

   // can only get to zero if the count is one, and we are decrementing
   wire 		 s3_upd_z  = s3_cnt_one & s3_sel[0];
   wire 		 s3_set_nz = s3_v & ~s3_upd_z;
   wire 		 s3_rst_nz = s3_v &  s3_upd_z;
   wire 		 o_rd_nz;

   base_vmem_bypass#(.a_width(id_width)) iv_mem
     (.clk(clk),.reset(reset),
      .i_set_v(s3_v),.i_set_a(s3_id),
      .i_rst_v(1'b0),.i_rst_a(),
      .i_rd_en(s2_re),.i_rd_a(s2_id),.o_rd_d(s3_cv)
      );

   // third cycle of delay
   wire [0:id_width-1] 	 s4_id;
   wire 		 s4_set_nz, s4_rst_nz;
   base_vlat#(.width(id_width)) is4_dlat(.clk(clk),.reset(1'b0),.din(s3_id),.q(s4_id));
   base_vlat#(.width(2)) is4_vlat(.clk(clk),.reset(reset),.din({s3_set_nz,s3_rst_nz}),.q({s4_set_nz,s4_rst_nz}));

   // read in third cycle will give correct answer in fourth    
   base_vmem_bypass#(.a_width(id_width)) inz_mem
     (.clk(clk),.reset(reset),
      .i_set_v(s4_set_nz),.i_set_a(s4_id),
      .i_rst_v(s4_rst_nz),.i_rst_a(s4_id),
      .i_rd_en(1'b1),.i_rd_a(i_rd_id),
      .o_rd_d(o_rd_nz)
      );
   assign o_rd_zero = ~o_rd_nz;
   
   base_mem_bypass#(.addr_width(id_width),.width(cnt_width)) icnt_mem
     (.clk(clk),
      .we(s3_v), .wa(s3_id), .wd(s3_upd_cnt),
      .re(s2_re), .ra(s2_id), .rd(s3_rd_cnt)
      );
endmodule // capi_dma_ctxt_cnt


   

   
			
			

    
