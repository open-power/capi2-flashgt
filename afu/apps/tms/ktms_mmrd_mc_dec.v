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
// handle mmio multi-context reads.
// detect address match, split local context and address
// mux result in case of single-word read
module ktms_mmrd_mc_dec#
  (parameter addr_width=24,
   parameter mmiobus_width=4+addr_width,
   parameter ctxtid_width=10,
   parameter ctxtid_start = 14,
   parameter lcladdr_width=1,
   parameter [addr_width-1:0] addr=0,
   parameter lat=1 // data latencsy
   )
   (input clk,
    input 		       reset,
    input [0:mmiobus_width-1]  i_mmiobus, // can be given a larger bus (e.g.with data)
    input 		       o_rd_r,
    output 		       o_rd_v,
    output [0:lcladdr_width-1] o_rd_addr, // ignore lsb
    output [0:ctxtid_width-1]  o_rd_ctxt,

    output 		       i_rd_r,
    input 		       i_rd_cancel,
    input 		       i_rd_v,
    input [0:63] 	       i_rd_d,

    output 		       o_mmio_rd_v,
    output [0:63] 	       o_mmio_rd_d,
    output                     o_perror
    );

//   localparam used_addr_width = ctxtid_start-lcladdr_width;
//   localparam [ctxtid_start-1:0] addr_mask = ((1<<used_addr_width)-1) << lcladdr_width;

   wire 		       ha_cfg;  // this is config space
   wire 		       ha_rnw;  // read not write
   wire 		       ha_vld;  // valid 
   wire 		       ha_dw;   // double word
   wire [addr_width-1:0]       ha_addr;

   assign {ha_vld,ha_cfg,ha_rnw,ha_dw,ha_addr} = i_mmiobus[0:addr_width+4-1]; // omit any extra data bits

//   wire 		       s0_is_per_ctxt = ~ha_cfg & ~(| ha_addr[addr_width-1:(ctxtid_width+ctxtid_start)]);

   wire 		       s0_addr_matchl = (ha_addr[ctxtid_start-1:lcladdr_width] == addr[ctxtid_start-1:lcladdr_width]);
   wire 		       s0_addr_matchh = (ha_addr[addr_width-1:ctxtid_start+ctxtid_width-1] == addr[addr_width-1:ctxtid_start+ctxtid_width-1]);
						 
   wire 		       s0_v = s0_addr_matchl & s0_addr_matchh & ha_vld & ha_rnw & ~ha_cfg;

   wire                        s0_ctxt_par;
   wire [0:ctxtid_width-1]     s0_ctxt = {ha_addr[ctxtid_start+ctxtid_width-2:ctxtid_start],s0_ctxt_par};
   wire [0:lcladdr_width-1]    s0_lcladdr = ha_addr [lcladdr_width-1:0];

   wire [lcladdr_width-1:0]    s1_ra;
   wire [0:ctxtid_width-1]     s1_rc;
   wire 		       s1_dw;
   
   wire  		       s1a_v,s1a_r;
   wire  		       s1b_v,s1b_r;

   capi_parity_gen#(.dwidth(ctxtid_width-1),.width(1)) immrd_mc_pgen(.i_d(s0_ctxt[0:ctxtid_width-2]),.o_d(s0_ctxt_par));
   base_alatch#(.width(1+ctxtid_width+lcladdr_width)) is1_lat
     (.clk(clk),.reset(reset),
      .i_v(s0_v),.i_r(),.i_d({ha_dw,s0_ctxt,s0_lcladdr}),
      .o_v(s1a_v),.o_r(s1a_r),.o_d({s1_dw,s1_rc,s1_ra}));

  wire                         s1_perror;
   capi_parcheck#(.width(ctxtid_width-1)) s1_rc_ctxt_pcheck(.clk(clk),.reset(reset),.i_v(s1a_v),.i_d(s1_rc[0:ctxtid_width-2]),.i_p(s1_rc[ctxtid_width-1]),.o_error(s1_perror));
   wire  				hld_perror;
   wire  				any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(1)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(1'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(any_hld_perror),.q(o_perror));


   base_acombine#(.ni(1),.no(2)) is1_cmb(.i_v(s1a_v),.i_r(s1a_r),.o_v({s1b_v,o_rd_v}),.o_r({s1b_r,o_rd_r}));
   assign o_rd_ctxt = s1_rc;   
   assign o_rd_addr = s1_ra;

   wire 		       s2_ra, s2_dw;
   wire [0:1] 		       s2_v, s2_r;
   
   base_alatch#(.width(2)) is2_lat
     (.clk(clk),.reset(reset),
      .i_v(s1b_v),.i_r(s1b_r),.i_d({s1_ra[0],s1_dw}),
      .o_v(s2_v[1]),.o_r(s2_r[1]),.o_d({s2_ra,s2_dw})
      );

   base_acombine#(.ni(2),.no(1)) is2_cmb(.i_v({i_rd_v,s2_v[1]}),.i_r({i_rd_r,s2_r[1]}),.o_v(s2_v[0]),.o_r(s2_r[0]));

   wire [0:63] 		       s2_rd;
   capi_mmio_sw_mux imux(.ha_mmdw(s2_dw),.ha_mmad(s2_ra),.din(i_rd_d),.dout(s2_rd));
   
   base_vlat#(.width(64)) is3_lat(.clk(clk),.reset(1'b0),.din(s2_rd),.q(o_mmio_rd_d));
   base_vlat#(.width(1))  is3_vlat(.clk(clk),.reset(reset),.din(s2_v[0] & ~i_rd_cancel),.q(o_mmio_rd_v));
   assign s2_r[0] = 1'b1;
   
endmodule // ktms_mc_mmwr_dec


			       
   
   
   
   
    
   
