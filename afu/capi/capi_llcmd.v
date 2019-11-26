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
module capi_llcmd#(parameter ctxtid_width=16, parameter ctxt_add_acks=1, parameter ctxt_rmv_acks=1, parameter ctxt_trm_acks=1)
  (
   input 		     clk,
   input 		     reset,
   input 		     i_cmd_v,
   input [0:15] 	     i_cmd_cmd,
   input [0:ctxtid_width-1]  i_cmd_ctxt,
   output 		     o_cmd_ack,
   output 		     o_ctxt_add_v,
   output 		     o_ctxt_rmv_v,
   output 		     o_ctxt_trm_v,
   output [0:ctxtid_width-1] o_ctxt_upd_d,

   input [0:ctxt_add_acks-1] i_ctxt_add_ack_v,
   input [0:ctxt_rmv_acks-1] i_ctxt_rmv_ack_v,
   input [0:ctxt_trm_acks-1] i_ctxt_trm_ack_v,
   output [11:14] 	     o_dbg_cnt_inc
   );

   wire 		    s1_v;

   wire [0:15] 		    s1_cmd;
   wire [0:ctxtid_width-1]  s1_ctxt;
   
   base_vlat#(.width(16+ctxtid_width)) is1_lat(.clk(clk),.reset(1'b0),.din({i_cmd_cmd,i_cmd_ctxt}),.q({s1_cmd, s1_ctxt}));
   base_vlat#(.width(1))              is1_vlat(.clk(clk),.reset(reset),.din(i_cmd_v),.q(s1_v));
   
   wire 		    s1_cmd_add = s1_cmd == 16'd5;
   wire 		    s1_cmd_rmv = s1_cmd == 16'd2;
   wire 		    s1_cmd_trm = s1_cmd == 16'd1;
   wire 		    s1_inc_pe = s1_v & s1_cmd_add;
   wire 		    s1_dec_pe = s1_v & s1_cmd_trm;

   wire 		    s1_trm = s1_v & s1_cmd_trm;
   wire 		    s1_rmv = s1_v & s1_cmd_rmv;
   wire 		    s1_add = s1_v & s1_cmd_add;
   
   wire 		    s2_v, s2_add, s2_trm, s2_rmv;
   wire [0:ctxtid_width-1]  s2_ctxt;
   base_vlat#(.width(4+ctxtid_width)) is2_vlat(.clk(clk),.reset(reset),.din({s1_v,s1_add,s1_trm,s1_rmv,s1_ctxt}),.q({s2_v, s2_add, s2_trm, s2_rmv, s2_ctxt}));



   assign o_ctxt_add_v = s2_add;
   assign o_ctxt_rmv_v = s2_rmv;
   assign o_ctxt_trm_v = s2_trm;
   assign o_ctxt_upd_d = s2_ctxt;

   wire [0:ctxt_add_acks-1] s2_add_ack_v;
   wire [0:ctxt_trm_acks-1] s2_trm_ack_v;
   wire [0:ctxt_rmv_acks-1] s2_rmv_ack_v;
   wire 		    s2_add_ack = &s2_add_ack_v;
   wire 		    s2_trm_ack = &s2_trm_ack_v;
   wire 		    s2_rmv_ack = &s2_rmv_ack_v;

   assign o_dbg_cnt_inc[11] = s2_add;
   assign o_dbg_cnt_inc[12] = s2_trm;
   assign o_dbg_cnt_inc[13] = s2_add_ack;
   assign o_dbg_cnt_inc[14] = s2_trm_ack;
   
   base_vlat_sr#(.width(ctxt_add_acks)) iadd_ack_lat(.clk(clk),.reset(reset),.set(i_ctxt_add_ack_v),.rst({ctxt_add_acks{s2_add_ack}}),.q(s2_add_ack_v));
   base_vlat_sr#(.width(ctxt_trm_acks)) itrm_ack_lat(.clk(clk),.reset(reset),.set(i_ctxt_trm_ack_v),.rst({ctxt_trm_acks{s2_trm_ack}}),.q(s2_trm_ack_v));
   base_vlat_sr#(.width(ctxt_rmv_acks)) irmv_ack_lat(.clk(clk),.reset(reset),.set(i_ctxt_rmv_ack_v),.rst({ctxt_rmv_acks{s2_rmv_ack}}),.q(s2_rmv_ack_v));

   wire 		    s2_ack = s2_add_ack | s2_trm_ack | s2_rmv_ack;
   assign o_cmd_ack = s2_ack;
   
   
endmodule // capi_jctrl

