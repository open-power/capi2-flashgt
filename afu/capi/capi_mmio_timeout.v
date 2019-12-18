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
module capi_mmio_timeout#
  (parameter mmiobus_width=1, parameter mmio_addr_width=24, parameter timeout_width=1)
   (input clk,
    input 		      reset,

    input [0:timeout_width-1] i_timeout, 
    input 		      i_mmack,
    input [0:63] 	      i_mmdata,
    input [0:mmiobus_width-1] i_mmiobus, // DATA COMES ONE CYCLE AFTER ADDRESS AND VALID

    output 		      o_mmack,
    output [0:63] 	      o_mmdata,
    output 		      o_mmpar

    );

   // pull apart the mmio bus    
   wire 		       ha_cfg;  // this is config space
   wire 		       ha_rnw;  // read not write
   wire 		       ha_vld;  // valid 
   wire 		       ha_dw;   // double word
   wire [0:mmio_addr_width-1]  ha_addr;
   wire [0:64] 		       ha_wd;   

   
   
   assign {ha_vld,ha_cfg,ha_rnw,ha_dw,ha_addr,ha_wd} = i_mmiobus;
   
   wire 			 o_error_unexpected_mmio;
   wire 			 o_error_unexpected_ack; 
   wire 			 o_error_timeout;
   wire [0:mmio_addr_width-1] o_error_addr;
   wire 			 o_error_cfg;
   wire 			 o_error_rnw;
   

   wire s0_mmack = i_mmack;
   wire [0:63] s0_mmdata = i_mmdata;


   wire 		      s1_mmack;
   wire 		      mmio_act;
   wire 		      timeout_reached;
   //track when an mmio is active
   base_vlat_sr immio_act(.clk(clk),.reset(reset),.set(ha_vld),.rst(s1_mmack),.q(mmio_act));


   // generate ack when timeout is reached. 
   assign s1_mmack = s0_mmack | timeout_reached;
   wire [0:63] s1_mmdata = s0_mmack ? s0_mmdata : ~(64'd0);

   
   wire [0:timeout_width-1]   timeout_cnt_in, timeout_cnt;
   assign timeout_reached = mmio_act & ~(|timeout_cnt);

   wire [0:timeout_width-1]    timeout_one;
   base_const#(.width(timeout_width),.value(1)) itimeout_one(timeout_one);
   assign timeout_cnt_in = ha_vld ? i_timeout : timeout_cnt - timeout_one;
   wire 		       timeout_en = ha_vld | mmio_act;
   base_vlat_en#(.width(timeout_width)) itimeout_cntr(.clk(clk),.reset(reset),.din(timeout_cnt_in),.q(timeout_cnt),.enable(timeout_en));
   wire 		       s1_mmpar;
   capi_parity_gen#(.width(1)) ipgen(.i_d(s1_mmdata),.o_d(s1_mmpar));

   base_vlat#(.width(65)) is2_mmdata(.clk(clk),.reset(1'b0),.din({s1_mmpar,s1_mmdata}),.q({o_mmpar,o_mmdata}));
   base_vlat#(.width(1)) is2_mmack(.clk(clk),.reset(reset),.din(s1_mmack),.q(o_mmack));


   
endmodule // capi_mmio_timeout


   
    
