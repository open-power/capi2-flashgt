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
module ktms_debug_cnt#
  (parameter n=16,
   parameter mmioaddr=1,
   parameter mmiobus_width=1
   )
   (input clk,
    input 		      reset,
    input [0:mmiobus_width-1] i_mmiobus,
    input [0:n-1] 	      i_inc,

    output 		      o_mmio_rd_v,
    output [0:63] 	      o_mmio_rd_d
    );

   localparam awidth=1+$clog2(n);

   wire 	       s1_v, s1_r;
   wire [awidth-1:0]   s1_addr;
   wire 	       s2_v, s2_r;
   wire [0:63] 	       s2_d;

   wire [0:n-1]        s1_inc;
   base_delay#(.n(2),.width(n)) iinc_del(.clk(clk),.reset(reset),.i_d(i_inc),.o_d(s1_inc));

   base_sram_cntrs#(.width(64),.n(n)) icntrs
     (.clk(clk),.reset(reset),
      .i_inc(s1_inc),
      .i_rd_a(s1_addr[awidth-1:1]),.i_rd_v(s1_v),.i_rd_r(s1_r),
      .o_rd_d(s2_d),.o_rd_v(s2_v),.o_rd_r(s2_r)
      );
					     
   
   wire 		       debug_cnt_cfg;  // this is config space
   wire 		       debug_cnt_rnw;  // read not write
   wire 		       debug_cnt_vld;  // valid 
   wire 		       debug_cnt_dw;   // double word
   wire [0:64] 		       debug_cnt_data;   // change 63 to 64 to add parity kch 
   wire [0:24]  	       debug_cnt_addr;
   wire [0:4+24+64-1]         debug_cnt_mmiobus;
   assign {debug_cnt_vld,debug_cnt_cfg,debug_cnt_rnw,debug_cnt_dw,debug_cnt_addr,debug_cnt_data} = i_mmiobus; // omit any extra data bits
   assign debug_cnt_mmiobus = {debug_cnt_vld,debug_cnt_cfg,debug_cnt_rnw,debug_cnt_dw,debug_cnt_addr[0:23],debug_cnt_data[0:63]};  // created to strip of parity 
   ktms_mmrd_dec#(.mmiobus_width(mmiobus_width-2),.lcladdr_width(awidth),.addr(mmioaddr)) immrd_dec
     (.clk(clk),.reset(reset),.i_mmiobus(debug_cnt_mmiobus),
      .o_rd_r(s1_r),.o_rd_v(s1_v),.o_rd_addr(s1_addr),
      .i_rd_r(s2_r),.i_rd_v(s2_v),.i_rd_d({s2_d}),
      .o_mmio_rd_v(o_mmio_rd_v),.o_mmio_rd_d(o_mmio_rd_d));
   
endmodule // ktms_debug_cnt

   
