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
module ktms_fc_incdec
  #(parameter id_width=1, parameter width=8)
   (input clk,
    input 		 reset,
    input 		 i_inc_v,
    input [0:id_width-1] i_inc_id,

    output 		 i_dec_r,
    input 		 i_dec_v,
    input [0:id_width-1] i_dec_id,

    input [0:id_width-1] i_rd_a,
    output 		 o_rd_z
    );


   wire 		 s1_v, s1_r;
   wire [0:1] 		 s1_sel;
   wire [0:width-1] 	 s1_id;
   wire 		 i_inc_r_dummy;
	 
   base_primux#(.ways(2),.width(id_width)) is1_mux
     (.i_v({i_inc_v,i_dec_v}),.i_r({i_inc_r_dummy,i_dec_r}),.i_d({i_inc_id,i_dec_id}),
      .o_v(s1_v),.o_r(s1_r),.o_d(s1_id),.o_sel(s1_sel));

   wire 		 s2_v;
   wire 		 s2_inc;
   wire [0:id_width-1] 	 s2_id;
   wire 		 s1_re;
   
   base_alatch_oe#(.width(id_width+1)) is2_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_v),.i_r(s1_r),.i_d({s1_sel[0],s1_id}),
      .o_v(s2_v),.o_r(1'b1),.o_d({s2_inc,s2_id}),.o_en(s1_re)
      );
   wire 		 s2_dec = ~s2_inc;

   wire 		 s2_rd_v;
   base_vmem#(.a_width(id_width)) ivmem
     (.clk(clk),.reset(reset),
      .i_set_v(s2_v),.i_set_a(s2_id),
      .i_rst_v(1'b0),.i_rst_a(),
      .i_rd_en(s1_re),.i_rd_a(s1_id),.o_rd_d(s2_rd_v)
      );
   wire [0:width-1] 	 s2_rd, s2_wd;
   wire 		 s2_we = s2_v;
   base_mem_bypass#(.addr_width(id_width),.width(width)) imem
     (.clk(clk),
      .re(s1_re),.ra(s1_id),.rd(s2_rd),
      .we(s2_we),.wa(s2_id),.wd(s2_wd)
      );

   wire [0:width-1] 	 s2_qrd = {width{s2_rd_v}} & s2_rd;
   localparam [0:width-1] one = 1;
   assign s2_wd = s2_inc ? (s2_qrd+one) : (s2_qrd-one);

   wire 		 s2_set_v = s2_we & s2_inc;
   wire 		 s2_rst_v = s2_we & s2_dec & (s2_rd == one);

   wire 		 rd_nz;
   base_vmem#(.a_width(id_width),.set_ports(2),.set_pri(1)) incmem
     (.clk(clk),.reset(reset),
      .i_set_v({i_inc_v ,s2_set_v}),.i_set_a({i_inc_id,s2_id}),
      .i_rst_v(s2_rst_v),.i_rst_a(s2_id),
      .i_rd_en(1'b1),.i_rd_a(i_rd_a),.o_rd_d(rd_nz));

   assign o_rd_z = ~rd_nz;
endmodule
   

