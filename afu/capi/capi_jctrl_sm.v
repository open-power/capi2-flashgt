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
module capi_jctrl_sm #(parameter cred_width=1,parameter cmd_width=1)
  (
   input 		  clk,
   input 		  reset,

   input 		  i_cmd_v, // ap_done command
   input [0:cmd_width-1]  i_cmd_d,

   input 		  i_cmd_cmpl,

   output 		  o_cmd_v,
   output [0:cmd_width-1] o_cmd_d,

   // tracking outstanding commands
   input 		  i_rsp_rcvd,
   input 		  i_cmd_sent,
   output 		  o_cmd_en
   );

   // track the number of outstanding commands
   wire   outst_zero;
   base_incdec#(.width(cred_width)) icmd_outst
     (.clk(clk),.reset(reset),.i_inc(i_cmd_sent),.i_dec(i_rsp_rcvd),.o_zero(outst_zero),.o_cnt());

   // hang onto commands until we are ready for them
   wire   s1_cmd_v;
   wire [0:cmd_width-1] s1_cmd_d;
   base_alatch#(.width(cmd_width)) iad_l1(.clk(clk),.reset(reset),.i_v(i_cmd_v),.i_r(),.i_d(i_cmd_d),.o_v(s1_cmd_v),.o_r(i_cmd_cmpl),.o_d(s1_cmd_d));


      // states   
   localparam ST_IDLE        = 2'd0; 
   localparam ST_DISABLE     = 2'd1; // ah_c commands are disabled, waiting for disable to take effect
   localparam ST_QUIET  = 2'd2; // waiting for all responses to come back from outstanding commands
   localparam ST_EXECUTE     = 2'd3; // executing the command

   wire [0:1] 	 cmd_state; // track which state we are in
   wire [0:3] 	 cmd_time;  // timer for st_disable state
   wire 	 cmd_st_adv;  // advance the state
   wire 	 cmd_time_adv; //advance the time
   
   base_vlat_en#(.width(2))  icmd_state(.clk(clk),.reset(reset),.din(cmd_state+2'd1),.q(cmd_state),.enable(cmd_st_adv));
   base_vlat_en#(.width(4)) icmd_time(.clk(clk),.reset(reset),.din(cmd_time-4'd1),.q(cmd_time),.enable(cmd_time_adv));
   wire 	 cmd_time_zero = (cmd_time == 4'd0);
   wire 	 cmd_time_one  = (cmd_time == 4'd1);
   wire [0:3]	 cmd_st_dec;
   base_decode#(.enc_width(2),.dec_width(4)) icmd_st_dec(.din(cmd_state),.dout(cmd_st_dec),.en(1'b1));


   wire 	 cmd_adv_disable = cmd_st_dec[ST_IDLE] & s1_cmd_v;  // advance to disable state
   wire 	 cmd_adv_quiet   = cmd_st_dec[ST_DISABLE] & cmd_time_one; // advance to quiet state
   wire 	 cmd_adv_execute = cmd_st_dec[ST_QUIET] & outst_zero; // advance to execute state
   wire 	 cmd_adv_idle    = cmd_st_dec[ST_EXECUTE] & i_cmd_cmpl; // advance to idle state
		 
   assign cmd_st_adv = cmd_adv_disable | cmd_adv_quiet | cmd_adv_execute | cmd_adv_idle;
   assign cmd_time_adv = cmd_st_dec[ST_DISABLE];
   
   assign o_cmd_v = cmd_adv_execute;
   assign o_cmd_d = s1_cmd_d;

   base_vlat#(.width(1)) icmd_en(.clk(clk),.reset(reset),.din(cmd_st_dec[ST_IDLE]),.q(o_cmd_en));
endmodule // capi_jctrl_sm
