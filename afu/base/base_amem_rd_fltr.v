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
// Continuously read an SRAM, updating the data outputs as the SRAM is updated, until the output is accepted.
// This can be used to wait for a particular contition to be reached.
// i_a: the address to be used to read the SRAM
// i_d: data to be passed transparently to the output.
// o_a: address output - drive sram read address with this output
// o_d: i_d that was supplied with the address.
// ouput is limited to one transaction per 2 cycles. 
module base_amem_rd_fltr#
  (parameter awidth=1,
   parameter dwidth=1
   )
   (
    input 		clk,
    input 		reset,
    output 		i_r,
    input 		i_v,
    input [0:awidth-1] 	i_a,
    input [0:dwidth-1] 	i_d,
    input 		o_r,
    output 		o_v,
    output [0:awidth-1] o_a,
    output [0:dwidth-1] o_d
    );

   wire [0:1] 		    s1_v, s1_r;
   wire [0:1] 		    s2_v, s2_r;


   base_acombine#(.ni(1),.no(2)) is1_cmb(.i_v(i_v),.i_r(i_r),.o_v(s1_v),.o_r(s1_r));
   base_aburp#(.width(awidth)) is1_addr_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_v[0]),.i_r(s1_r[0]),.i_d(i_a), 
      .o_v(s2_v[0]),.o_r(s2_r[0]),.o_d(o_a),
      .burp_v());
   base_aburp_latch#(.width(dwidth)) is1_aux_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_v[1]),.i_r(s1_r[1]),.i_d(i_d),
      .o_v(s2_v[1]),.o_r(s2_r[1]),.o_d(o_d));
   base_acombine#(.ni(2),.no(1)) is2_cmb(.i_v(s2_v),.i_r(s2_r),.o_v(o_v),.o_r(o_r));
endmodule
   
