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
// records the first value written for each tag, and ignores subsequent writes until tag is read.
module ktms_fc_error#
  (parameter tag_width=1,
   parameter tag_par_width=1,
   parameter tag_width_w_par=tag_width+tag_par_width,
   parameter width=1,
   parameter ways=1,
   parameter aux_width=1
   )
   (input clk,
    input 			reset,
    input [0:ways-1] 		i_v,
    output [0:ways-1] 		i_r,
    input [0:ways-1] 		i_error,
    input [0:ways*tag_width_w_par-1] 	i_tag,
    input [0:ways*width-1] 	i_d,

    input [0:ways-1] 		o_r, 
    output [0:ways-1] 		o_v,
    output [0:ways*tag_width_w_par-1] o_tag,
    
    input 			i_rd_v,
    output 			i_rd_r,
    input [0:tag_width_w_par-1] 	i_rd_tag,
    input [0:aux_width-1] 	i_rd_aux,
    
    input 			o_rd_r,
    output 			o_rd_v,
    output 			o_rd_dv, // this tag has been written since last read
    output [0:width-1] 		o_rd_d, // last value written
    output [0:aux_width-1] 	o_rd_aux,
    output [0:tag_width_w_par-1] 	o_rd_tag ,
    output                      o_perror
    );


   wire 		       rd1_v, rd1_r;
   wire [0:aux_width-1]        rd1_aux;
   wire [0:tag_width_w_par-1]        rd1_tag;

   base_alatch#(.width(tag_width_w_par+aux_width)) ird1_lat(.clk(clk),.reset(reset),.i_v(i_rd_v),.i_r(i_rd_r),.i_d({i_rd_tag,i_rd_aux}),.o_v(rd1_v),.o_r(rd1_r),.o_d({rd1_tag,rd1_aux}));

   wire 		       rd2_v, rd2_r,rd2_en;
   wire [0:aux_width-1]        rd2_aux;
   wire [0:tag_width_w_par-1]        rd2_tag;
   
   base_amem_rd_fltr#(.awidth(tag_width_w_par),.dwidth(aux_width)) ird2_lat
     (.clk(clk),.reset(reset),
      .i_v(rd1_v),.i_r(rd1_r),.i_a(rd1_tag),.i_d(rd1_aux),
      .o_v(rd2_v),.o_r(rd2_r),.o_a(rd2_tag),.o_d(rd2_aux)
      );

   wire [0:width-1] 	       rd2_d,s2_d;
   wire 		       s2_we;
   wire [0:tag_width_w_par-1]        s2_tag;

   wire 		       s1a_v, s1a_r;
   wire 		       s2_v, s2_r;
   wire [0:tag_width_w_par-1]        s1a_tag;
   wire [0:2]                   s1_perror;
   capi_parcheck#(.width(tag_width)) rd2_tag_pcheck(.clk(clk),.reset(reset),.i_v(rd2_v),.i_d(rd2_tag[0:tag_width_w_par-2]),.i_p(rd2_tag[tag_width_w_par-1]),.o_error(s1_perror[0]));
   capi_parcheck#(.width(tag_width)) s2_tag_pcheck(.clk(clk),.reset(reset),.i_v(s2_v),.i_d(s2_tag[0:tag_width_w_par-2]),.i_p(s2_tag[tag_width_w_par-1]),.o_error(s1_perror[1]));
   capi_parcheck#(.width(tag_width)) s1a_tag_pcheck1(.clk(clk),.reset(reset),.i_v(s1a_v),.i_d(s1a_tag[0:tag_width_w_par-2]),.i_p(s1a_tag[tag_width_w_par-1]),.o_error(s1_perror[2]));
   wire [0:2] 				hld_perror;
   wire 				any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(3)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(3'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(any_hld_perror),.q(o_perror));
   
   base_mem_bypass#(.addr_width(tag_width),.width(width)) irc_mem
     (.clk(clk),
      .re(1'b1),.ra(rd2_tag[0:tag_width_w_par-2]),.rd(rd2_d),
      .we(s2_we),.wa(s2_tag[0:tag_width_w_par-2]),.wd(s2_d)  
      );
   wire 		       s1_en;
   wire 		       rd2_dv, s2_dv;
   
   base_vmem_bypass#(.a_width(tag_width),.rports(2)) ivmem
     (.clk(clk),.reset(reset),
      .i_rd_en({1'b1,s1_en}),.i_rd_a({rd2_tag[0:tag_width_w_par-2],s1a_tag[0:tag_width_w_par-2]}),.o_rd_d({rd2_dv,s2_dv}),  
      .i_set_v(s2_we),.i_set_a(s2_tag[0:tag_width_w_par-2]),   
      .i_rst_v(o_rd_v & o_rd_r),.i_rst_a(o_rd_tag[0:tag_width_w_par-2])
      );

   // don't allow read while write is pending 
   base_agate ird2_gt(.i_v(rd2_v),.i_r(rd2_r),.o_v(o_rd_v),.o_r(o_rd_r),.en(rd2_en));
   assign o_rd_tag = rd2_tag;
   assign o_rd_aux = rd2_aux;
   assign o_rd_d   = rd2_d;
   assign o_rd_dv  = rd2_dv;

   wire [0:ways-1] 	       s1_v, s1_r;
   wire [0:tag_width_w_par*ways-1]   s1_tag;
   wire [0:width*ways-1]       s1_d;
   wire [0:ways-1] 	       s1_error;
   wire [0:ways-1] 	       s2a_v, s2a_r;

   genvar 		       i;
   generate
      for(i=0; i<ways; i=i+1)
	begin : gen1
	   base_alatch_burp#(.width(1+tag_width_w_par+width)) is1_burp
	    (.clk(clk),.reset(reset),
	     .i_v(i_v[i]),.i_r(i_r[i]),.i_d({i_error[i],i_tag[i*tag_width_w_par:(i+1)*tag_width_w_par-1],i_d[i*width:(i+1)*width-1]}),
	     .o_v(s1_v[i]),.o_r(s1_r[i]),.o_d({s1_error[i],s1_tag[i*tag_width_w_par:(i+1)*tag_width_w_par-1],s1_d[i*width:(i+1)*width-1]})
	     );
	   base_alatch_burp#(.width(tag_width_w_par)) is2_burp(.clk(clk),.reset(reset),.i_v(s2a_v[i]),.i_r(s2a_r[i]),.i_d(s2_tag),.o_v(o_v[i]),.o_r(o_r[i]),.o_d(o_tag[i*tag_width_w_par:(i+1)*tag_width_w_par-1]));
		
	end
      endgenerate

   // write stage 1 : mux and read valid
   wire [0:ways-1] 	       s1_sel;
   base_arr_mux#(.ways(ways),.width(tag_width_w_par)) is1_tag_mux
     (.clk(clk),.reset(reset),.i_v(s1_v),.i_r(s1_r),.i_d(s1_tag),.o_v(s1a_v),.o_r(s1a_r),.o_d(s1a_tag),.o_sel(s1_sel));

   wire [0:width-1] 	       s1a_d;
   base_mux#(.ways(ways),.width(width)) is1_dmux(.din(s1_d),.dout(s1a_d),.sel(s1_sel));

   wire 		       s1a_error;
   base_mux#(.ways(ways),.width(1)) is1_emux(.din(s1_error),.dout(s1a_error),.sel(s1_sel));

   wire 		       s2_error;
   wire [0:ways-1] 	       s2_sel;
   base_alatch_oe#(.width(1+ways+tag_width_w_par+width)) is2_lat
     (.clk(clk),.reset(reset),
      .i_v(s1a_v),.i_r(s1a_r),.i_d({s1a_error,s1_sel,s1a_tag,s1a_d}),
      .o_v(s2_v),.o_r(s2_r),.o_d({s2_error,s2_sel,s2_tag,s2_d}),.o_en(s1_en));

   base_ademux#(.ways(ways)) is2_demux(.i_v(s2_v),.i_r(s2_r),.o_v(s2a_v),.o_r(s2a_r),.sel(s2_sel));
   
   assign s2_we = s2_v & s2_error & ~s2_dv;
   assign rd2_en = ~s1a_v;
   
endmodule // ktms_fc_error
