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
module ktms_afu_errmon#
  (parameter mmiobus_width=1,
   parameter width = 1,
   parameter mmio_addr=0
   )
   (
    input 		      clk, 
    input 		      reset,
    input [0:mmiobus_width-1] i_mmiobus,
    input [0:width-1] 	      i_rm_err,
    input [0:width-1] 	      i_rm_msk,
    input [0:31] 	      i_rm_cnt,
    input [0:127] 	      i_pipemon_v,
    input [0:127] 	      i_pipemon_r,

    input [0:63] 	      i_dma_status,
    
    output 		      o_mmio_rd_v,
    output [0:63] 	      o_mmio_rd_d,

    output 		      o_afu_disable
    );


   localparam lcladdr_width = 3;
   localparam lcl_regs = 7;

   wire 		      s1_rst;
   wire 		       errmon_cfg;  // this is config space
   wire 		       errmon_rnw;  // read not write
   wire 		       errmon_vld;  // valid 
   wire 		       errmon_dw;   // double word
   wire [0:64] 		       errmon_data;
   wire [0:24]  	       errmon_addr;
   wire [0:4+24+64-1]          errmon_mmiobus;
   assign {errmon_vld,errmon_cfg,errmon_rnw,errmon_dw,errmon_addr,errmon_data} = i_mmiobus; 
   assign errmon_mmiobus = {errmon_vld,errmon_cfg,errmon_rnw,errmon_dw,errmon_addr[0:23],errmon_data[0:63]}; 
   capi_mmio_reg#(.addr(mmio_addr)) immio_rst(.clk(clk),.reset(reset),.i_mmiobus(errmon_mmiobus-2),.q(),.trg(s1_rst));
   
   wire [0:width-1] s2_err_d;
   base_vlat_sr#(.width(width)) isr_lat(.clk(clk),.reset(reset),.set(i_rm_err),.rst({width{s1_rst}}),.q(s2_err_d));
   base_vlat#(.width(1)) is2_err_lat(.clk(clk),.reset(reset),.din(|(s2_err_d & ~i_rm_msk)),.q(o_afu_disable));
   
   wire [0:127] 	    s2_pipemon_v;
   base_vlat#(.width(128)) is2_pmv_lat(.clk(clk),.reset(reset),.din(i_pipemon_v),.q(s2_pipemon_v));
				      
   wire [0:127] 	    s2_pipemon_r;
   base_vlat#(.width(128)) is2_pmr_lat(.clk(clk),.reset(reset),.din(i_pipemon_r),.q(s2_pipemon_r));
				      
   wire 	    s1_v, s1_r;
   wire 	    s2_v, s2_r;
   wire [0:lcladdr_width] s1_rd_a;
   wire [0:lcladdr_width-1] s2_rd_a;
   
   base_alatch#(.width(lcladdr_width)) is2_lat(.clk(clk),.reset(reset),.i_v(s1_v),.i_r(s1_r),.i_d(s1_rd_a[0:lcladdr_width-1]),.o_v(s2_v),.o_r(s2_r),.o_d(s2_rd_a));
   wire [0:63] 	  s2_d;
   base_emux#(.ways(lcl_regs),.width(64)) is2_mux(.sel(s2_rd_a),.din({i_rm_cnt,{32-width{1'b0}},s2_err_d,  64'd0,s2_pipemon_v,s2_pipemon_r,i_dma_status}),.dout(s2_d));
   
   ktms_mmrd_dec#(.mmiobus_width(mmiobus_width-2),.lcladdr_width(lcladdr_width+1),.addr(mmio_addr)) immrd_dec
     (.clk(clk),.reset(reset),.i_mmiobus(errmon_mmiobus),
     .o_rd_r(s1_r),.o_rd_v(s1_v),.o_rd_addr(s1_rd_a),
     .i_rd_r(s2_r),.i_rd_v(s2_v),.i_rd_d(s2_d),
     .o_mmio_rd_v(o_mmio_rd_v),.o_mmio_rd_d(o_mmio_rd_d)
      );

endmodule // ktms_afu_errmon
