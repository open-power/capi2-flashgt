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
module capi_put_align_delay_plus
  (input clk,
   input 	  reset,
   output 	  i_r,
   input 	  i_v,
   input [0:127]  i_d,
   input [0:3] 	  i_c,
   input 	  i_e,

   output 	  i_a_r,
   input 	  i_a_v,
   input [0:3] 	  i_a_d,
   
   input 	  o_r,
   input 	  o_cmd_gen_r,
   output 	  o_v,
   output [0:127] o_d,
   output [0:3]   o_c,
   output 	  o_e,
   output         o_array_we,
   output         o_s0_array_we,
   output         o_offset_write_cycle
   );

   // hold onto adress for mux select
//   wire [0:3] 	  s1_sel;
//   wire 	  s1a_v, s1a_r;
//   base_aburp_latch#(.width(4)) ia1_lat
//     (.clk(clk),.reset(reset),
//      .i_v(i_a_v),.i_r(i_a_r),.i_d(i_a_d),
//      .o_v(s1a_v),.o_r(s1a_r),.o_d(s1_sel)
//      );
   assign i_a_r = i_r;

   // i_c==0 really means 4
   wire 	  s0_v, s0_r, s0_e;
   wire [0:3] 	  s0_c;
   wire [0:127]   s0_d;
   wire           put_data_burp_v;
   wire           s0_put_data_burp_v;
   wire           s1_put_data_burp_v;
   
   base_aburp#(.width(128+4+1)) is0_burp
     (.clk(clk),.reset(reset),
      .i_v(i_v),.i_r(i_r),.i_d({i_d,i_c,i_e}),
      .o_v(s0_v),.o_r(s0_r),.o_d({s0_d,s0_c,s0_e}),.burp_v(put_data_burp_v)
      );
   base_vlat#(.width(2)) ibeat_kch(.clk(clk), .reset(reset), .din({put_data_burp_v,s0_put_data_burp_v}), .q({s0_put_data_burp_v,s1_put_data_burp_v}));
   wire s1_valid;

 
   wire 	  s0_c_zero = s0_c == 4'b0;
   wire [0:4] 	  s0_ec = {s0_c_zero,s0_c};
   wire 	  s1b_v, s1b_r;
   wire [0:127]   s1b_d;
   wire [0:4] 	  s1b_c;
   wire 	  s1b_e;
   wire 	  s1_v, s1_r;
   base_alatch#(.width(128+5+1)) is1_lat
     (.clk(clk),.reset(reset),
      .i_v(s0_v),.i_r(s0_r),.i_d({s0_d,s0_ec,s0_e}),
      .o_v(s1_v),.o_r(s1_r),.o_d({s1b_d,s1b_c,s1b_e})
      );


   // rpt: feedback
//   wire 	  s2rpt_v, s2rpt_r;
//   wire [0:4] 	  s2rpt_c;
//   wire [0:1] 	  s1c_v, s1c_r;
//   wire 	  s1_e;
//   wire [0:4] 	  s1c_c;

	  
   // choose between new and repeated last beat
//   base_primux#(.ways(2),.width(6)) is1_cmux
//     (.i_v({1'b0,s1b_v}),.i_r({s2rpt_r,s1b_r}),.i_d({s2rpt_c,1'b0,s1b_c,s1b_e}),  // gate off pri ority valid see if that works 
//     (.i_v({s2rpt_v,s1b_v}),.i_r({s2rpt_r,s1b_r}),.i_d({s2rpt_c,1'b0,s1b_c,s1b_e}),
//      .o_v(s1c_v[0]),.o_r(s1c_r[0]),.o_d({s1c_c,s1_e}),.o_sel());

   // hang on to address for mux select and move on when the data stream ends
//   base_arfilter ia1_fltr(.i_v(s1a_v),.i_r(s1a_r),.o_v(s1c_v[1] ),.o_r(s1c_r[1]),.en(s1_e));

   // combine address and data
//   base_acombine#(.ni(2),.no(1)) is1_cmb1(.i_v(s1c_v),.i_r(s1c_r),.o_v(s1_v),.o_r(s1_r));
   wire offset_eq0 = (i_a_d == 4'h0);
   wire s0_offset_eq0 , s1_offset_eq0;
   wire offset_write_cycle = offset_eq0 & ~s0_offset_eq0;

   // save the previous line
   wire [0:127]   s1_prv_d;
   base_vlat_en#(.width(128)) is0_lat
//     (.clk(clk),.reset(reset),.din(s1b_d),.q(s1_prv_d),.enable((s1_v & s1_r) | offset_write_cycle));
     (.clk(clk),.reset(reset),.din(s1b_d),.q(s1_prv_d),.enable(s1_v & s1_r & ~s1b_e));
   
   wire s1_5_v,s1_5_r,s1_5_b_e;
   wire [0:4]  s1_5_b_c ;
   
   wire [0:127] s1_5_prv_d;
   
   base_alatch#(.width(4+1)) is1_5_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_v),.i_r(),.i_d({s1b_c[1:4],s1b_e}),
      .o_v(s1_5_v),.o_r(s1_5_r),.o_d({s1_5_b_c[1:4],a1_5_b_e})
      );

   base_vlat_en#(.width(128)) is15_lat
     (.clk(clk),.reset(reset),.din(s1_prv_d),.q(s1_5_prv_d),.enable((s1_v & s1_r) | offset_write_cycle));

   wire [0:128*16-1] s1_mux_in;
   genvar 	     i;
   assign s1_mux_in[0:127] = s1b_d;
   generate
      for(i=1; i<16; i=i+1)
	begin : gen1
	   wire [0:127] s1_in = {s1_prv_d[((16-i)*8):127],s1b_d[0:(16-i)*8-1]};
	   assign s1_mux_in[128*i:128*(i+1)-1] = s1_in;
	end
   endgenerate

   wire [0:128*16-1] s1_5_mux_in;
//   genvar 	     i;
   assign s1_5_mux_in[0:127] = s1_prv_d;
   generate
      for(i=1; i<16; i=i+1)
	begin : gen1_5
	   wire [0:127] s1_5_in = {s1_5_prv_d[((16-i)*8):127],s1_prv_d[0:(16-i)*8-1]};
	   assign s1_5_mux_in[128*i:128*(i+1)-1] = s1_5_in;
	end
   endgenerate

//   wire [0:4] s1_nc = s1_sel + s1c_c;
//   wire       s1_rpt_en = ~s1_e & (s1_nc > 5'd16);

   // split into repeat and output streams
//   wire [0:1] s1d_r, s1d_v;
//   base_acombine#(.ni(1),.no(2)) is1_cmb2(.i_v(s1_v),.i_r(s1_r),.o_v(s1d_v),.o_r(s1d_r));

   // break the combinational backpressure loop.
//   assign s1d_r[1] = 1'b1;
   
   // only repeate when needed
//   wire       s1e_v, s1e_r;
//   base_afilter irpt1_fltr(.i_v(s1d_v[1]),.i_r(),.o_v(s1e_v),.o_r(s1e_r),.en(s1_rpt_en));
//   wire       s2a_v, s2a_r;

//   wire [0:4] s1c_nc = s1c_c - 5'd16;
//   base_alatch#(.width(5)) is1_rpt_lat(.clk(clk),.reset(reset),.i_v(s1e_v),.i_r(s1e_r),.i_d(s1c_nc),.o_v(s2a_v),.o_r(s2a_r),.o_d(s2rpt_c));

   // wait for input to be valid before deciding whether to repeat
//   wire       s2b_v, s2b_r;
//   base_agate is2_gt(.i_v(s2a_v),.i_r(s2a_r),.o_v(s2b_v),.o_r(s2b_r),.en(s1b_v));

   // only repeate when input is about to end
 //  wire       s2c_v, s2c_r;
 //  base_afilter is2_fltr(.i_v(s2b_v),.i_r(s2b_r),.o_v(s2rpt_v),.o_r(s2rpt_r),.en(s1b_e));
      
   
   // work out the actual count
//   wire [0:3] s1_c =  s1_rpt_en ? 4'd0 : s1_nc[1:4];
   wire [0:3] s1_c =  4'd0;
   
   wire [0:127] s1_d;
   base_emux#(.ways(16),.width(128)) is1_mux
     (.sel(i_a_d),
      .din(s1_mux_in),
      .dout(s1_d)
      );

   wire [0:127] s1_5_d;
   base_emux#(.ways(16),.width(128)) is1_5s1_mux
     (.sel(i_a_d),
      .din(s1_5_mux_in),
      .dout(s1_5_d)
      );


   base_alatch#(.width(128)) is2_5_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_5_v),.i_r(s1_5_r),.i_d({s1_5_d}),
      .o_v(),.o_r(o_r & o_cmd_gen_r),.o_d({o_d})
      );

   base_alatch#(.width(4+1)) is2_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_v),.i_r(s1_r),.i_d({s1b_c[1:4],s1b_e}),
      .o_v(o_v),.o_r(o_r & o_cmd_gen_r),.o_d({o_c,o_e})
      );

   base_vlat#(.width(2),.rstv(3'b111)) ipoffset(.clk(clk), .reset(reset), .din({offset_eq0,s0_offset_eq0}), .q({s0_offset_eq0,s1_offset_eq0}));
   wire array_we =  (o_v & ~o_e & o_r) | offset_write_cycle ; 
   wire s0_array_we, s1_array_we;
   base_vlat#(.width(2)) iarray_we(.clk(clk), .reset(reset), .din({array_we,s0_array_we}), .q({s0_array_we,s1_array_we}));
   assign o_array_we = s0_array_we;
   assign o_s0_array_we = s1_array_we;
   assign o_offset_write_cycle = offset_write_cycle;

endmodule // capi_get_align

   
   
   
