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
module capi_jctrl#(parameter cred_width=1, ctxtid_width=16, parameter ctxt_add_acks=1, parameter ctxt_trm_acks=1, parameter ctxt_rmv_acks=1, parameter afuerr_width=1)
  (
   input 		     clk,
   input 		     i_reset,
   input 		     i_app_done,
   input                     i_fatal_error,
   input [0:afuerr_width-1]  i_app_error, 
   input 		     ha_jval, // A valid job control command is present
   input [0:7] 		     ha_jcom, // Job control command opcode
   input [0:63] 	     ha_jea,
   input         	     ha_jeapar, // added kch
   output 		     ah_jcack, //   lpc operation is done
   output 		     ah_jrunning, // Accelerator is running
   output 		     ah_jdone, // Accelerator is finished
   output [63:0] 	     ah_jerror, // Accelerator error code. 0 = success
   output 		     ah_tbreq, // timebase request (not used)
   output 		     ah_jyield, // Accelerator wants to stop

   output 		     o_cmd_en,
   input 		     i_cmd_sent,
   input 		     i_rsp_rcvd,

   input [0:ctxt_add_acks-1] i_ctxt_add_ack_v,
   input [0:ctxt_trm_acks-1] i_ctxt_trm_ack_v,
   input [0:ctxt_rmv_acks-1] i_ctxt_rmv_ack_v,

   output 		     o_ctxt_add_v,
   output 		     o_ctxt_trm_v,
   output 		     o_ctxt_rmv_v,
   output [0:ctxtid_width-1] o_ctxt_upd_d,
   output [11:14] 	     o_dbg_cnt_inc, 
   output 		     o_reset,
   output                    o_s1_perror,
   output                    o_perror
   );

   assign ah_tbreq = 1'b0;
   assign ah_jyield = 1'b0;

   localparam llcmdid_width=16;
   
   wire 				s1_perror;
   capi_parcheck#(.width(64)) ha_jeapar_pcheck(.clk(clk),.reset(i_reset),.i_v(ha_jval),.i_d(ha_jea),.i_p(ha_jeapar),.o_error(s1_perror));
   wire 				hld_perror;
   assign o_s1_perror = hld_perror;
   base_vlat_sr#(.width(1)) iperror_lat(.clk(clk),.reset(i_reset),.set(s1_perror),.rst(1'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(i_reset),.din(| hld_perror),.q(o_perror));
   wire                      ll_ctxt_par;
   wire [0:ctxtid_width-1] ll_ctxt = {ha_jea[64-ctxtid_width+1:63],ll_ctxt_par};  // added +1 to remove paity bit from the equation. size =10 bit ctxt size is 9 kch
   wire [0:llcmdid_width-1] ll_cmd = ha_jea[0:llcmdid_width-1];
   capi_parity_gen#(.dwidth(ctxtid_width-1),.width(1)) ijctrl_gen(.i_d(ll_ctxt[0:ctxtid_width-2]),.o_d(ll_ctxt_par));
  
   wire [0:15] 	 cmd_cnt /*synthesis keep=1*/ ;
   base_vlat_en#(.width(16)) icmd_cnt(.clk(clk),.reset(i_reset),.enable(ha_jval),.din(cmd_cnt+15'd1),.q(cmd_cnt));

   
   wire 	 ha_cmd_reset = ha_jval & (ha_jcom == 8'h80);
   wire 	 ha_cmd_start = ha_jval & (ha_jcom == 8'h90);
   wire 	 ha_cmd_ll = ha_jval & (ha_jcom == 8'h45);

   
   wire 	 s0_app_done = i_app_done;

   wire [0:afuerr_width-1] s0_app_error = i_app_done ? i_app_error : {afuerr_width{1'b0}};
   wire [0:afuerr_width-1] s1_app_error;
   base_vlat_en#(.width(afuerr_width)) is0_err(.clk(clk),.reset(i_reset),.din(s0_app_error),.q(s1_app_error),.enable(i_app_done));

   wire 	 reset_start = ha_cmd_reset;

   wire 	 s0_cmd_v = ha_cmd_reset | s0_app_done;
   wire [0:1] 	 s0_cmd_d = {ha_cmd_reset,s0_app_done};

   wire 	 s2_cmd_cmpl;
   wire 	 s1_cmd_v;
   wire  	 s1_cmd_ha_reset, s1_cmd_app_done;

   wire 	 s1_cmd_en;
   
   capi_jctrl_sm#(.cred_width(cred_width),.cmd_width(2)) ictrl_sm
     (.clk(clk),.reset(i_reset),
      .i_cmd_v(s0_cmd_v),.i_cmd_d(s0_cmd_d),
      .i_cmd_cmpl(s2_cmd_cmpl),
      .o_cmd_v(s1_cmd_v),.o_cmd_d({s1_cmd_ha_reset,s1_cmd_app_done}),
      .i_rsp_rcvd(i_rsp_rcvd),.i_cmd_sent(i_cmd_sent),
      .o_cmd_en(s1_cmd_en)
      );
   
   wire 	 s1_reset_start = s1_cmd_v & s1_cmd_ha_reset;
   wire 	 s1_apd_start = ah_jrunning & s1_cmd_v & s1_cmd_app_done;

   //  reset control logic
   wire 	 reset_1;
   base_hold_for_n#(.n(16)) ireset_hold(.clk(clk),.reset(i_reset),.i_d(s1_reset_start),.o_d(reset_1));
   wire 	 reset_2;
   base_vlat#(.width(1)) ireset_d2(.clk(clk),.reset(i_reset),.din(reset_1),.q(reset_2));
   wire 	 s2_reset;
   base_vlat#(.width(1)) ireset_s2(.clk(clk),.reset(1'b0),.din( (reset_2 | i_reset) & ~i_fatal_error),.q(s2_reset));
   wire 	 s3_reset;
   base_vlat#(.width(1)) ireset_s3(.clk(clk),.reset(1'b0),.din(s2_reset),.q(s3_reset));
   base_vlat#(.width(1)) ireset_o(.clk(clk),.reset(1'b0),.din(s3_reset),.q(o_reset));
   wire 	 reset_done_s1 = reset_2 & ~reset_1;

   wire 	 s2_apd_done;
   base_vlat#(.width(1)) iapd_done(.clk(clk),.reset(i_reset),.din(s1_apd_start),.q(s2_apd_done));
   
   assign s2_cmd_cmpl = reset_done_s1 | s2_apd_done;
   
   base_vlat_sr irunning_lat(.clk(clk),.reset(i_reset | reset_1),.set(ha_cmd_start),.rst(s2_apd_done),.q(ah_jrunning));

   wire 	 jdone_reset_s1 = (reset_done_s1 & s1_cmd_ha_reset);
   wire 	 jdone_reset_s2;
   base_vlat#(.width(1)) ijd_rst_s2(.clk(clk),.reset(i_reset),.din(jdone_reset_s1),.q(jdone_reset_s2));
   

   wire 	 jdone_s2 = jdone_reset_s2 | s2_apd_done;
   wire [0:afuerr_width-1] s2_error = s2_apd_done ? s1_app_error : {afuerr_width{1'b0}};
   wire [0:afuerr_width-1] s3_error;
   base_vlat_en#(.width(afuerr_width)) is2_jerror(.clk(clk),.reset(i_reset),.din(s2_error),.q(s3_error),.enable(jdone_s2));

   assign ah_jerror[63:afuerr_width] = {64-afuerr_width{1'b0}};
   assign ah_jerror[afuerr_width-1:0] = s3_error;
   
   base_vlat#(.width(1)) is0_jdone_lat(.clk(clk),.reset(i_reset),.din(jdone_s2),.q(ah_jdone));
   base_vlat#(.width(1)) icmd_en(.clk(clk),.reset(i_reset),.din(s1_cmd_en & ah_jrunning),.q(o_cmd_en));

   capi_llcmd#(.ctxtid_width(ctxtid_width),.ctxt_add_acks(ctxt_add_acks),.ctxt_trm_acks(ctxt_trm_acks),.ctxt_rmv_acks(ctxt_rmv_acks)) illcmd
     (
      .clk(clk),.reset(o_reset),
      .i_ctxt_add_ack_v(i_ctxt_add_ack_v),
      .i_ctxt_trm_ack_v(i_ctxt_trm_ack_v),
      .i_ctxt_rmv_ack_v(i_ctxt_rmv_ack_v),
      .o_ctxt_add_v(o_ctxt_add_v),
      .o_ctxt_trm_v(o_ctxt_trm_v),
      .o_ctxt_rmv_v(o_ctxt_rmv_v),
      .o_ctxt_upd_d(o_ctxt_upd_d),
      .o_dbg_cnt_inc(o_dbg_cnt_inc),
      .i_cmd_v(ha_cmd_ll),
      .i_cmd_ctxt(ll_ctxt),
      .i_cmd_cmd(ll_cmd),
      .o_cmd_ack(ah_jcack)
      );
   
endmodule // capi_jctrl
