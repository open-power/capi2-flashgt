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
module ktms_afu_mmio_ack#
  (parameter mmiobus_awidth = 1, parameter mmio_addr_width=24,
   parameter ways = 1
  )
   (input clk,
    input reset,
    input [0:mmiobus_awidth-1] i_mmioabus,
    input [0:ways-1] i_v,
    input [0:ways*64-1] i_d,
    output o_v,
    output [0:63] o_d
    );
   wire 		       ha_cfg;  // this is config space
   wire 		       ha_rnw;  // read not write
   wire 		       ha_vld;  // valid 
   wire 		       ha_dw;   // double word
   wire [0:mmio_addr_width-1]  ha_addr;
   assign {ha_vld,ha_cfg,ha_rnw,ha_dw,ha_addr} = i_mmioabus;

   wire 		       s0_lcl_ack = ha_vld & ~ha_rnw & ((ha_addr < 'h804800) | (ha_addr >= 'h805000) | ha_cfg);
   wire 		       s1_lcl_ack;
   base_vlat is1_lcl_ack(.clk(clk),.reset(reset),.din(s0_lcl_ack),.q(s1_lcl_ack));

   wire [0:63] 		       s0_d;
   base_mux#(.ways(ways),.width(64)) is1_mux(.sel(i_v),.din(i_d),.dout(s0_d));
   
   wire 		       s0_v = | i_v;
   wire 		       s1_v;
   base_vlat is1_vlat(.clk(clk),.reset(reset),.din(s0_v),.q(s1_v));
   base_vlat#(.width(64)) is1_dlat(.clk(clk),.reset(1'b0),.din(s0_d),.q(o_d));

   assign o_v = s1_v | s1_lcl_ack;
endmodule // ktms_afu_mmio_ack

   
   
