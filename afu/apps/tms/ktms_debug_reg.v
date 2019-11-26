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
module ktms_debug_reg#
  (
   parameter regs=16,
   parameter cr_depth=16,
   parameter mmioaddr=1,
   parameter mmioaddr_err_inj=1,
   parameter mmiobus_width=1
   )
   (input clk,
    input 		      reset,
    input [0:mmiobus_width-1] i_mmiobus,
    input [0:64*regs-1]       i_dbg_reg,
    input [0:63] 	      i_rega, 
    input [0:63] 	      i_regb,
    input 		      i_cnt_rsp_miss,

    output 		      o_mmio_rd_v,
    output [0:63] 	      o_mmio_rd_d,
    output [0:63] 	      o_errinj
    );

   wire [0:128*cr_depth-1]    s1_cr_reg;
   wire [0:128*cr_depth-1]    s1_cr_reg_in;
   generate
      if (cr_depth > 1)
	assign s1_cr_reg_in = {i_rega,i_regb,s1_cr_reg[0:128*(cr_depth-1)-1]};
      else
	assign s1_cr_reg_in = {i_rega,i_regb};
   endgenerate      

   base_vlat_en#(.width(128*cr_depth)) icr_reg_lat(.clk(clk),.reset(reset),.din(s1_cr_reg_in),.q(s1_cr_reg),.enable(i_cnt_rsp_miss));
					     
   localparam m = regs; // number of extra debug registers
   localparam awidth=1+$clog2(m+cr_depth*2);
   

   wire [0:64*m-1]     s1_dbg_reg;
   base_vlat#(.width(64*m)) ir0_lat(.clk(clk),.reset(1'b0),.din(i_dbg_reg),.q(s1_dbg_reg));
   
   wire 	       s1_v, s1_r;
   wire [awidth-1:0]   s1_addr;
   wire 	       s2_v, s2_r;
   wire [0:63] 	       s1_d, s2_d;

   base_emux#(.ways(m+cr_depth*2),.width(64)) imux(.sel(s1_addr[awidth-1:1]),.din({s1_dbg_reg,s1_cr_reg}),.dout(s1_d));
	      
   wire 		       debug_reg_cfg;  // this is config space
   wire 		       debug_reg_rnw;  // read not write
   wire 		       debug_reg_vld;  // valid 
   wire 		       debug_reg_dw;   // double word
   wire [0:64] 		       debug_reg_data;   // change 63 to 64 to add parity kch 
   wire [0:24]  	       debug_reg_addr;
    wire [0:4+24+64-1]         debug_reg_mmiobus;
   assign {debug_reg_vld,debug_reg_cfg,debug_reg_rnw,debug_reg_dw,debug_reg_addr,debug_reg_data} = i_mmiobus; // omit any extra data bits
   assign debug_reg_mmiobus = {debug_reg_vld,debug_reg_cfg,debug_reg_rnw,debug_reg_dw,debug_reg_addr[0:23],debug_reg_data[0:63]};  // created to strip of parity 
   base_alatch#(.width(64)) ilat(.clk(clk),.reset(reset),.i_v(s1_v),.i_r(s1_r),.i_d(s1_d),.o_v(s2_v),.o_r(s2_r),.o_d(s2_d));
   ktms_mmrd_dec#(.mmiobus_width(mmiobus_width-2),.lcladdr_width(awidth),.addr(mmioaddr)) immrd_dec
     (.clk(clk),.reset(reset),.i_mmiobus(debug_reg_mmiobus),
      .o_rd_r(s1_r),.o_rd_v(s1_v),.o_rd_addr(s1_addr),
      .i_rd_r(s2_r),.i_rd_v(s2_v),.i_rd_d({s2_d}),
      .o_mmio_rd_v(o_mmio_rd_v),.o_mmio_rd_d(o_mmio_rd_d));


   wire 	       mmio_errin_v;
   wire [0:63] 	       mmio_errin_d;
   
	
   capi_mmio_reg#(.addr(mmioaddr_err_inj)) immio_errinj(.clk(clk),.reset(reset),.i_mmiobus(debug_reg_mmiobus),.q(mmio_errin_d),.trg(mmio_errin_v));
   base_vlat_en#(.width(64)) ierrinj_lat(.clk(clk),.reset(reset),.din(mmio_errin_d),.q(o_errinj),.enable(mmio_errin_v));
   
endmodule // ktms_debug_cnt

   
