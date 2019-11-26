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
module ktms_mc_incdec#
  (parameter id_width=1,
   parameter width=1,
   parameter maxv=1
   )

  (
   input 		 clk,
   input 		 reset,
   input 		 i_rst_v,
   input [0:id_width-1]  i_rst_id,
   output 		 o_rst_ack,
   
   input 		 i_inc_v,
   input [0:id_width-1]  i_inc_id,
   input 		 i_inc_frc_oflw,

   input 		 o_inc_r,
   output 		 o_inc_v,
   output 		 o_inc_err,

   output 		 i_dec_r,
   input 		 i_dec_v,
   input [0:id_width-1]  i_dec_id,
   input [0:width-1]     i_maxv,

   output 		 o_we,
   output [0:id_width-1] o_wa,
   output [0:width-1] 	 o_wd
   
   );



   // mux between inrement and decrement

   wire 		i_inc_r_dummy;  // no backpressure on increment
   wire 		s0a_rst_v, s0a_rst_r;
   wire [0:id_width-1] 	s0_rst_id;
   wire 		s0_rst_re;
   base_alatch_oe#(.width(id_width)) irst_lat(.clk(clk),.reset(reset),.i_v(i_rst_v),.i_r(),.i_d(i_rst_id),.o_v(s0a_rst_v),.o_r(s0a_rst_r),.o_d(s0_rst_id),.o_en(s0_rst_re));
   assign o_rst_ack = s0a_rst_r & s0a_rst_v;

   // only reset the first time a context is added
   wire 		s0_rst_suppress;
   base_vmem#(.a_width(id_width)) irst_mem
     (.clk(clk),.reset(reset),
      .i_set_v(s0a_rst_r & s0a_rst_v),.i_set_a(s0_rst_id),
      .i_rst_v(1'b0),.i_rst_a(),
      .i_rd_en(s0_rst_re),.i_rd_a(i_rst_id),.o_rd_d(s0_rst_suppress)
      );

   wire s0b_rst_v, s0b_rst_r;
   base_afilter is0_rst_fltr(.i_v(s0a_rst_v),.i_r(s0a_rst_r),.o_v(s0b_rst_v),.o_r(s0b_rst_r),.en(~s0_rst_suppress));
   
   wire 		s0_inc_v, s0_inc_r;
   wire [0:id_width-1] 	s0_inc_id;
   wire 		s0_inc_frc_oflw;
   base_alatch#(.width(1+id_width)) is0_inc_lat(.clk(clk),.reset(reset),.i_v(i_inc_v),.i_r(),.i_d({i_inc_frc_oflw,i_inc_id}),.o_v(s0_inc_v),.o_r(s0_inc_r),.o_d({s0_inc_frc_oflw,s0_inc_id}));

   wire 		s0a_v, s0a_r;
   wire [0:2] 		s0_incdec_sel;
   wire [0:id_width-1] 	s0_incdec_id;
   wire 		s0_incdec_frc_oflw;
   
   base_primux#(.width(1+id_width),.ways(3)) iinc_dec_mux
     (.i_v({s0_inc_v,s0b_rst_v,i_dec_v}),.i_r({s0_inc_r,s0b_rst_r,i_dec_r}),.i_d({s0_inc_frc_oflw,s0_inc_id,1'b0,s0_rst_id,1'b0,i_dec_id}),
      .o_r(s0a_r),.o_v(s0a_v),.o_d({s0_incdec_frc_oflw, s0_incdec_id}),.o_sel(s0_incdec_sel)
      );
   
   // avoid read/write hazards by leaving 1 cycle gap between transactions
   wire 		s0b_v, s0b_r;
   wire 		s1a_v;
   base_agate is1_gt(.i_v(s0a_v),.i_r(s0a_r),.o_v(s0b_v),.o_r(s0b_r),.en(~s1a_v));
   
   wire 		s1a_r;
   wire [0:2] 		s1_incdec_sel;
   wire [0:id_width-1] 	s1_incdec_id;
   wire 		s1_incdec_frc_oflw;

   wire 		s0_re;
   base_alatch#(.width(1+id_width+3)) is1_incdec_lat
     (.clk(clk),.reset(reset),
      .i_v(s0b_v),.i_r(s0b_r),.i_d({s0_incdec_frc_oflw, s0_incdec_id,s0_incdec_sel}),
      .o_v(s1a_v),.o_r(s1a_r),.o_d({s1_incdec_frc_oflw, s1_incdec_id,s1_incdec_sel})
      );


   wire [0:1] 		s1b_v, s1b_r;
   base_acombine#(.ni(1),.no(2)) is1_cmb(.i_v(s1a_v),.i_r(s1a_r),.o_v(s1b_v),.o_r(s1b_r));
   

   
   wire [0:width-1] 	s1_incdec_d;
   wire 		s1_incdec_uflw = s1_incdec_sel[2] & (s1_incdec_d == {width{1'b0}});
   wire 		s1_incdec_oflw = s1_incdec_sel[0] & (s1_incdec_frc_oflw | (s1_incdec_d == i_maxv));
   wire                 s1_wb_suppress = s1_incdec_frc_oflw | s1_incdec_uflw | s1_incdec_oflw;
   wire 		s1_incdec_we = s1b_v[0] & ~s1_wb_suppress;
   assign s1b_r[0] = 1'b1;
   

   // output the result of increment
   base_afilter is1b_fltr(.i_v(s1b_v[1]),.i_r(s1b_r[1]),.o_v(o_inc_v),.o_r(o_inc_r),.en(s1_incdec_sel[0]));
   assign o_inc_err = s1_incdec_oflw;
   

   wire [0:width-1] 	one;
   base_const#(.width(width),.value(1)) ione(one);
   wire [0:width-1] s1_incdec_wd;
   wire [0:width-1] s1_incdec_dinc = s1_incdec_d+one;
   wire [0:width-1] s1_incdec_ddec = s1_incdec_d-one;
   
   base_mux#(.ways(3),.width(width)) is1_mux
     (.din({s1_incdec_dinc,{width{1'b0}},s1_incdec_ddec}),.dout(s1_incdec_wd),.sel(s1_incdec_sel)
      );
   
   base_mem#(.addr_width(id_width),.width(width)) icmem1
     (.clk(clk),
      .ra(s0_incdec_id),.re(s1b_r[0] | ~s1b_v[0]),.rd(s1_incdec_d),
      .wa(s1_incdec_id),.we(s1_incdec_we),.wd(s1_incdec_wd)
      );

   assign o_wa = s1_incdec_id;
   assign o_we = s1_incdec_we;
   assign o_wd = s1_incdec_wd;

endmodule
   

   
