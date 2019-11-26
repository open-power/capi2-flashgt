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
// address lsb must be 0
// sw write zeros upper 32 bits
module ktms_mmwr_dec#
  (parameter addr_width=24,
   parameter mmiobus_width=4+addr_width+64,
   parameter lcladdr_width=1,
   parameter addr=0,
   parameter lat=1 // data latencsy
   )
   (input clk,
    input 		       reset,
    input [0:mmiobus_width-1]  i_mmiobus, // can be given a larger bus (e.g.with data)
    input 		       o_wr_r,
    output 		       o_wr_v,
    output [lcladdr_width-1:0] o_wr_addr, // ignore lsb
    output [0:63] 	       o_wr_d
    );

   localparam [addr_width-1:0] addr_mask = ((1<<addr_width)-1) << lcladdr_width;
   
   wire 		       ha_cfg;  // this is config space
   wire 		       ha_rnw;  // read not write
   wire 		       ha_vld;  // valid 
   wire 		       ha_dw;   // double word
   wire [0:63] 		       ha_data;
   wire [addr_width-1:0]       ha_addr;

   assign {ha_vld,ha_cfg,ha_rnw,ha_dw,ha_addr,ha_data} = i_mmiobus; // omit any extra data bits

// temp stuff to unserdtand what is going on
   wire [addr_width-1:0] addr_mask_wire = addr_mask;
   wire [addr_width-1:0] addr_match_wire = addr;

   wire 		       s0_addr_match = (ha_addr[addr_width-1:1] & addr_mask[addr_width-1:1]) == addr[addr_width-1:1];
   wire 		       s0_v = ~ha_addr[0] & s0_addr_match & ha_vld & ~ha_cfg & ~ha_rnw;

   wire [0:lcladdr_width-1]    s0_lcladdr = ha_addr [lcladdr_width-1:0];

   wire [0:63] 		       s1_wr_d;
   wire 		       s1_dw;
   base_arealign#(.adv_width(lcladdr_width+1),.del_width(64)) is1_lat
     (.clk(clk),.reset(reset),
      .i_v(s0_v),.i_r(),
      .i_d_adv({s0_lcladdr,ha_dw}), .i_d_del(ha_data),
      .o_v(o_wr_v),.o_r(o_wr_r),.o_d_adv({o_wr_addr,s1_dw}),.o_d_del(s1_wr_d));

   assign o_wr_d[0:31] = s1_dw ? s1_wr_d[0:31] : 32'd0;
   assign o_wr_d[32:63] = s1_wr_d[32:63];

endmodule // ktms_mmwr_dec
