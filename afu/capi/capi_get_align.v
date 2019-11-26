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
module capi_get_align#(parameter rc_width=1, parameter bcnt_width=1)
  (input clk,
   input 		 reset,
   output 		 i_r,
   input 		 i_v,
   input [0:129] 	 i_d,   // changed from 127 to 129 for parity kch
   input [0:3] 		 i_s,
   input [0:3] 		 i_c,
   input 		 i_e,
   input [0:rc_width-1]  i_rc,
   
   input 		 o_r,
   output 		 o_v,
   output [0:129] 	 o_d,  // changed 127 to 129 to add parity kch 
   output [0:3] 	 o_c,
   output 		 o_e,
   output [0:bcnt_width-1] o_bcnt,
   output [0:rc_width-1] o_rc,
   output [0:1]          o_s1_perror,
   output                o_perror   // added o_peror kch 
);




   // detect the first beat of the stream   
   wire 	  s0_f;
   base_afirst is0_fst(.clk(clk),.reset(reset),.i_v(i_v),.i_r(i_r),.i_e(i_e),.o_first(s0_f));

   // save the "start" value on first beat for mux select 
   wire 	  s0_s_en = i_v & i_r & s0_f;
   wire 	  s0_s_zero = ~(|i_s);
   wire [0:3] 	  s1_s;
   wire 	  s1_s_zero;
   base_vlat_en#(.width(5)) is1_slat(.clk(clk),.reset(reset),.din({s0_s_zero,i_s}),.q({s1_s_zero,s1_s}),.enable(s0_s_en));

   // extend i_c 
   wire [0:5] 	  s0_c;
   assign s0_c[0] = 1'b0;
   assign s0_c[1] = ~ (|i_c);
   assign s0_c[2:5] = i_c;

   wire 	       s0_rc_zero = ~(|i_rc);

   wire 	       s1_v, s1_r, s1_e, s1_f;
   wire [0:129]   s1_d;   // changed 127 to 129 to add parity kch
   wire [0:3] 	  s1_c;
   wire [0:5] 	  s1_c_diff;
   wire [0:rc_width-1] s1_rc;
   wire 	       s1_rc_zero;
   
   base_alatch#(.width(130+4+1+1+1+rc_width)) is1_lat        //changed 128 to 130 to add parity kch 
     (.clk(clk),.reset(reset),
      .i_v(i_v), .i_r(i_r),. i_d({ i_d,s1_c_diff[2:5],s0_f,i_e,s0_rc_zero,i_rc}),
      .o_v(s1_v),.o_r(s1_r),.o_d({s1_d,s1_c,s1_f,s1_e,s1_rc_zero,s1_rc}));

   // qualified version of mux select     
   wire [0:5] s1_sq = s1_v ? {2'd0,s1_s} : 5'd0;

   // look at the difference between the end point, and the qualified mux select.      
   assign 	  s1_c_diff = i_e ? (s0_c - s1_sq) : 6'd0;
   wire 	  s1_c_eq = s0_c == s1_sq;

   // if the difference is negative or they are equal, we are ending here. 
   wire 	  s1_ee = (s1_c_diff[0] | s1_c_eq) & i_e & ~s1_e;
   
   wire s1b_e = s1_ee | s1_e;
   // if we end early, use the computed difference
   // if we end normally, use the saved difference
   wire [0:3] 	  s1b_c;
   base_mux#(.ways(2),.width(4)) is1_cmux(.sel({s1_ee,s1_e}),.din({s1_c_diff[2:5],s1_c}),.dout(s1b_c));

   wire 	  s1b_v, s1b_r;
   // wait for beat behind to be valid 
   base_agate is1_gt(.i_v(s1_v),.i_r(s1_r),.o_v(s1b_v),.o_r(s1b_r),.en(i_v | s1_e));

   // if we are valid, and ending early, filter out the last beat of input
   wire s1_set_flush = s1b_v & s1b_r & s1_ee;
   wire s1_rst_flush = s1b_v & s1b_r & s1_e;
   wire s1_flush;
   base_vlat_sr iflush_lat(.clk(clk),.reset(reset),.set(s1_set_flush),.rst(s1_rst_flush),.q(s1_flush));
   			   
   wire s1c_v, s1c_r;
   base_afilter is1_fltr(.i_v(s1b_v),.i_r(s1b_r),.o_v(s1c_v),.o_r(s1c_r),.en(~s1_flush));
   
   wire [0:128*16-1] s1_mux_in;

   wire [0:1] 				s1_perror;
   capi_parcheck#(.width(64)) s1_d_pcheck0(.clk(clk),.reset(reset),.i_v(s1_v),.i_d(s1_d[0:63]),.i_p(s1_d[128]),.o_error(s1_perror[0]));
   capi_parcheck#(.width(64)) s1_d_pcheck1(.clk(clk),.reset(reset),.i_v(s1_v),.i_d(s1_d[64:127]),.i_p(s1_d[129]),.o_error(s1_perror[1]));

   wire [0:1] 				hld_perror;
   base_vlat_sr#(.width(2)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(2'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror),.q(o_perror));
   assign o_s1_perror = hld_perror;

   assign s1_mux_in[0:127] = s1_d[0:127]; // strip off parity and check 
   genvar 	     i;
   generate
      for(i=1; i<16; i=i+1)
	begin : gen1
	   assign s1_mux_in[128*i:128*(i+1)-1] = {s1_d[i*8:127],i_d[0:i*8-1]};
	end
   endgenerate


   wire s1_rc_nz = | s1_rc;
   wire s0_rc = i_e ? {rc_width{1'b0}} : i_rc;

   // choose s1 rc if it is non zero, or if the select is zero
   wire [0:rc_width-1] s1b_rc = (~s1_rc_zero | s1_s_zero) ? s1_rc : s0_rc;

   wire [0:129] s1b_d;    // changed 127 to 129 to add parity kch
   base_emux#(.ways(16),.width(128)) is1_mux 
     (.sel(s1_s),
      .din(s1_mux_in),
      .dout(s1b_d[0:127])
      );

   capi_parity_gen#(.dwidth(64),.width(1)) s1b_d_pgen0(.i_d(s1b_d[0:63]),.o_d(s1b_d[128]));     // gen parity for byte alligned data kch
   capi_parity_gen#(.dwidth(64),.width(1)) s1b_d_pgen1(.i_d(s1b_d[64:127]),.o_d(s1b_d[129]));


   // how many bytes were successfuly transfered in stage s1 if s0 has an error condition
   wire [0:4] 	s1_err_inc = 5'd16 - {1'b0,s1_s};

   wire [0:bcnt_width-1] s1_bcnt;
   wire [0:4] 		 s1_bcnt_inc = 
			 s1_rc ? 5'd0 : 
			 s0_rc ? s1_err_inc : 5'd16;
   			 
   wire [0:bcnt_width-1] s1_bcnt_in = (s1_f ? {bcnt_width{1'b0}} : s1_bcnt) + s1_bcnt_inc;
   base_vlat_en#(.width(bcnt_width)) is1_bcnt(.clk(clk),.reset(reset),.din(s1_bcnt_in),.q(s1_bcnt),.enable(s1_v & s1_r));
   
   
   base_alatch_burp#(.width(130+4+1+rc_width+bcnt_width)) is2_lat  // changed 128 to 130 to add parity kch 
     (.clk(clk),.reset(reset),
      .i_v(s1c_v),.i_r(s1c_r),.i_d({s1b_d,s1b_c,s1b_e,s1b_rc,s1_bcnt_in}),
      .o_v(o_v),.o_r(o_r),.o_d({o_d,o_c,o_e,o_rc,o_bcnt})
      );
   
endmodule // capi_get_align

   
   
   
