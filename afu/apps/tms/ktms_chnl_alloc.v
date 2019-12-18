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
module ktms_chnl_alloc#
  (parameter channels=1,
   parameter afu_tag_width=1,
   parameter fc_tag_width=1,
   parameter aux_width=1,
   parameter rc_width=1,
   parameter erc_width=1,
   parameter chnlid_width=$clog2(channels)
   )
   (input clk,
    input 		       reset,
    input [0:channels-1]       i_chnl_msk,
    output [0:channels-1]      o_rm_err,
    output 		       i_r,
    input 		       i_v,
    input [0:afu_tag_width-1]  i_tag,
    input [0:channels-1]       i_portmsk,
    input [0:channels-1]       i_avail, 
    input 		       i_afu,
    input 		       i_ok,
    input [0:rc_width-1]       i_rc,
    input [0:erc_width-1]      i_erc,
    input [0:aux_width-1]      i_aux,
    input 		       o_r,
    output 		       o_v,
    output [0:fc_tag_width-1]  o_fc_tag,
    output 		       o_fc_tag_valid, // did we allocate an fc tag
    output [0:afu_tag_width-1] o_afu_tag,
    output [0:chnlid_width-1]  o_chnl,
    output 		       o_ok,
    output [0:rc_width-1]      o_rc,
    output [0:erc_width-1]     o_erc,
    output [0:aux_width-1]     o_aux,
    input 		       i_free_v,
    input [0:chnlid_width-1]   i_free_chnl,
    input [0:fc_tag_width-1]   i_free_tag,
    output [0:channels-1]      o_perror,
    output [0:channels-1]      o_allocate_fc_tag,
    output [0:channels-1]      o_free_fc_tag,
    output [0:channels-1]      o_fc_channel_stall,
//new retry interface 
    output        o_reset_afu_cmd_tag_v,
    input        o_reset_afu_cmd_tag_r,
    output [0:afu_tag_width-1]  o_reset_afu_cmd_tag,
    output        o_retry_cmd_v, 
    input         o_retry_cmd_r,
    output[0:(64+65+10)-1]        o_retry_cmd_d,
    input [0:9]   i_rcb_ctxt,
    input [0:64]  i_rcb_ea,
    input [0:63]  i_rcb_timestamp,
    input         i_rcb_hp,
    output [0:127] o_retried_cmd_cnt,
    input         i_gate_retry,
    output[0:16]   o_dbg_cnt_inc,
    output        o_retry_threshold

    );

   localparam [0:rc_width-1] afuerr_no_channel = 'h20;

   wire [0:channels-1] 	       s0_avail;
   base_vlat#(.width(channels)) is0_avail_lat(.clk(clk),.reset(reset),.din(i_avail),.q(s0_avail));

   // chnl mask from global reg 6.  Must bit-swap.
   wire [0:channels-1] 	       m0_chnl_msk;
   base_bitswap#(.width(channels)) im0_chnl_msk(.i_d(i_chnl_msk),.o_d(m0_chnl_msk));
   wire [0:channels-1] 	       s0_chnl_msk;
   base_vlat#(.width(channels)) is0_chnl_msk_lat(.clk(clk),.reset(reset),.din(m0_chnl_msk),.q(s0_chnl_msk));

   
   wire [0:channels-1] 	       s0_pm = i_portmsk & s0_avail & s0_chnl_msk;

   wire [0:channels-1] 	       s0_chnl_dec;  
   assign s0_chnl_dec[0] = s0_pm[0];
   assign s0_chnl_dec[1] = s0_pm[1];
   assign s0_chnl_dec[2] = s0_pm[2];
   assign s0_chnl_dec[3] = s0_pm[3];

		       
   wire 		       s0_pm_ok;
   wire 		       s0_ok_in = s0_pm_ok | i_afu;
   
   wire 		       s0_ok;
   wire [0:rc_width-1] 	       s0_rc;
   wire [0:erc_width-1]        s0_erc;

   wire [0:channels-1] 	       s0_avail_r;
   wire [0:channels-1] 	       s0_portmsk_r;
   base_bitswap#(.width(channels)) is0_avail_swp(.i_d(s0_avail),.o_d(s0_avail_r));
   base_bitswap#(.width(channels)) is0_portmsk_swp(.i_d(i_portmsk),.o_d(s0_portmsk_r));

   wire [0:erc_width-1]        s0_erc_in = {s0_avail_r,s0_portmsk_r};
   ktms_afu_errmux#(.rc_width(rc_width+erc_width)) ierr_mux(.i_ok(i_ok),.i_rc({i_rc,i_erc}),.i_err(~s0_ok_in),.i_err_rc({afuerr_no_channel,s0_erc_in}),.o_ok(s0_ok),.o_rc({s0_rc,s0_erc}));


   wire [0:channels-1] 	   s0_free_chnl_dec;
   wire [0:channels-1] 	   s0_tag_v, s0_tag_r;
   wire [0:channels*fc_tag_width-1] s0_tag_d;
   
   base_decode#(.enc_width(chnlid_width),.dec_width(channels)) ifree_chnl_dec
     (.en(i_free_v),.din(i_free_chnl),.dout(s0_free_chnl_dec));

   localparam cnt_width = fc_tag_width+1-1;              
   wire [0:channels*cnt_width-1]    outst_cnt;


   wire [0:fc_tag_width]             outst_cnt0_v,outst_cnt1_v,outst_cnt2_v,outst_cnt3_v;
   reg  [0:fc_tag_width]            lt_outst_cnt01,lt_outst_cnt23; 
   reg [0:1]                        lt_win01,lt_win23;
   assign outst_cnt0_v = outst_cnt[0:cnt_width-1] | {fc_tag_width{~s0_pm[0]}};
   assign outst_cnt1_v = outst_cnt[cnt_width:cnt_width*2-1] | {fc_tag_width{~s0_pm[1]}};
   assign outst_cnt2_v = 2*outst_cnt[cnt_width:cnt_width*3-1] | {fc_tag_width{~s0_pm[2]}};
   assign outst_cnt3_v = 3*outst_cnt[cnt_width:cnt_width*4-1] | {fc_tag_width{~s0_pm[3]}};

wire [0:channels-1] inc_hp_tag_cnt, dec_hp_tag_cnt;
wire [0:channels*10-1]    outst_hp_cnt;  // max of 512 hp tags cause thats how deep a bram is
wire [0:channels*10-1]    outst_hp_retry_cnt;  // max of 512 hp tags cause thats how deep a bram is
wire [0:channels-1] s2_retry_cmd_v,s2_retry_cmd_r;
wire [0:channels-1] s2a_retry_cmd_v,s2a_retry_cmd_r;
wire [0:channels*64-1] s2_retry_cmd_timestamp;
wire [0:channels*65-1] s2_retry_cmd_ea;
wire [0:channels*10-1] s2_retry_cmd_ctxt;
wire [0:3] s0a_retry_fifo_v,s0a_retry_fifo_r;
wire [0:3] retry_tag_avail;
wire [0:555] s2a_retry_cmd_d;
wire [0:channels-1] inc_hp_retry_cnt = s0a_retry_fifo_v & s0a_retry_fifo_r; 
wire [0:channels-1] dec_hp_retry_cnt = s2_retry_cmd_v & s2_retry_cmd_r; 
wire [0:39] s1_retried_cnt;
wire [0:39] s1_retried_fifo_cnt;
wire [0:channels-1] update_retry_ccmd_cnt;
wire [0:channels-1] update_retry_fifo_cmd_cnt;
assign o_retried_cmd_cnt = {6'b0,s1_retried_cnt[0:9],6'b0,s1_retried_cnt[10:19],6'b0,s1_retried_cnt[20:29],6'b0,s1_retried_cnt[30:39],
                            6'b0,s1_retried_fifo_cnt[0:9],6'b0,s1_retried_fifo_cnt[10:19],6'b0,s1_retried_fifo_cnt[20:29],6'b0,s1_retried_fifo_cnt[30:39]};
wire [0:3] retry_cmds_gt_fc_tags;
wire [0:39] fctags_available;
wire [0:3] retry_fifo_threshold;
   generate
      genvar                        k;
      for(k=0; k< channels; k=k+1)
      begin : gen1
`ifdef SIM_RETRY   
       capi_res_mgr#(.id_width(fc_tag_width),.num_res(4),.parity(1)) ires_mgr // sim testing
`else
       capi_res_mgr#(.id_width(fc_tag_width),.parity(1)) ires_mgr // production 
`endif                                
           (.clk(clk),.reset(reset),
            .o_free_err(o_rm_err[k]),
            .i_free_v(s0_free_chnl_dec[k]),.i_free_id(i_free_tag),
            .o_avail_v(s0_tag_v[k]),.o_avail_r(s0_tag_r[k]),.o_avail_id(s0_tag_d[fc_tag_width*k:fc_tag_width*(k+1)-1]),.o_cnt(),
            .o_perror(o_perror[k]));
         base_incdec#(.width(cnt_width)) icnt(.clk(clk),.reset(reset),.i_inc(s0_tag_v[k]&s0_tag_r[k]),.i_dec(s0_free_chnl_dec[k]),.o_zero(),.o_cnt(outst_cnt[cnt_width*k:cnt_width*(k+1)-1]));
         base_incdec#(.width(10)) icnt_hp(.clk(clk),.reset(reset),.i_inc(inc_hp_tag_cnt[k]),.i_dec(dec_hp_tag_cnt[k]),.o_zero(),.o_cnt(outst_hp_cnt [10*k:10*(k+1)-1]));
         base_incdec#(.width(10)) icnt_hp_retry(.clk(clk),.reset(reset),.i_inc(inc_hp_retry_cnt[k]),.i_dec(dec_hp_retry_cnt[k]),.o_zero(),.o_cnt(outst_hp_retry_cnt[10*k:10*(k+1)-1]));
`ifdef SIM_RETRY   
         base_fifo#(.width(64+65+10),.LOG_DEPTH(4),.output_reg(1)) i_retry_cmd_fifo    
`else
         base_fifo#(.width(64+65+10),.LOG_DEPTH(9),.output_reg(1)) i_retry_cmd_fifo    
`endif                                
            (.clk(clk),.reset(reset),
             .i_v(s0a_retry_fifo_v[k]),.i_r(s0a_retry_fifo_r[k]),.i_d({i_rcb_timestamp,i_rcb_ea,i_rcb_ctxt}),
             .o_v(s2_retry_cmd_v[k]),.o_r(s2_retry_cmd_r[k]),.o_d({s2_retry_cmd_timestamp[64*k:64*(k+1)-1],s2_retry_cmd_ea[65*k:65*(k+1)-1],s2_retry_cmd_ctxt[10*k:10*(k+1)-1]}));
`ifdef SIM_RETRY   
       assign  fctags_available[10*k:10*(k+1)-1] = 10'h004 - {1'b0,outst_cnt[cnt_width*k:cnt_width*(k+1)-1]}; 
       assign retry_fifo_threshold[k] =  outst_hp_retry_cnt[10*k:10*(k+1)-1] >= 10'd12;
`else
       assign  fctags_available[10*k:10*(k+1)-1] = 10'h100 - {1'b0,outst_cnt[cnt_width*k:cnt_width*(k+1)-1]}; 
       assign retry_fifo_threshold[k] =  outst_hp_retry_cnt[10*k:10*(k+1)-1] >= 10'd448;
`endif 
         assign o_retry_threshold = (retry_fifo_threshold != 4'h0);
         assign retry_tag_avail[k] = outst_hp_cnt[10*k:10*(k+1)-1] < fctags_available [10*k:10*(k+1)-1]; // retry tag available if available tag cnt is greater than retried command sent 
         base_agate iretry_tag_gate   (.i_v(s2_retry_cmd_v[k]),.i_r(s2_retry_cmd_r[k]),.o_v(s2a_retry_cmd_v[k]),.o_r(s2a_retry_cmd_r[k]),.en(retry_tag_avail[k]));
         assign s2a_retry_cmd_d[(64+65+10)*k:(64+65+10)*(k+1)-1] = {s2_retry_cmd_timestamp[64*k:64*(k+1)-1],s2_retry_cmd_ea[65*k:65*(k+1)-1],s2_retry_cmd_ctxt[10*k:10*(k+1)-1]};
         assign update_retry_ccmd_cnt[k] = outst_hp_cnt[10*k:10*(k+1)-1] > s1_retried_cnt[10*k:10*(k+1)-1];
         base_vlat_en#(.width(10)) iretried_cmd(.clk(clk), .reset(reset), .enable(update_retry_ccmd_cnt[k]), .din(outst_hp_cnt[10*k:10*(k+1)-1]), .q(s1_retried_cnt[10*k:10*(k+1)-1]));  
         assign update_retry_fifo_cmd_cnt[k] = outst_hp_retry_cnt[10*k:10*(k+1)-1] > s1_retried_fifo_cnt[10*k:10*(k+1)-1];
         base_vlat_en#(.width(10)) iretried_fifo_cmd(.clk(clk), .reset(reset), .enable(update_retry_fifo_cmd_cnt[k]), .din(outst_hp_retry_cnt[10*k:10*(k+1)-1]), .q(s1_retried_fifo_cnt[10*k:10*(k+1)-1]));  
         

         
      end
   endgenerate
   base_amlrr_arb#(.ways(channels),.width(64+65+10),.stage_ways(channels)) iretry_mux   
     (.clk(clk),.reset(reset),
      .i_r(s2a_retry_cmd_r),.i_v(s2a_retry_cmd_v),.i_d(s2a_retry_cmd_d),.i_h(4'b0),
      .o_r(o_retry_cmd_r), .o_v(o_retry_cmd_v), .o_d(o_retry_cmd_d),.o_h()
      );

   assign o_dbg_cnt_inc[9:12] = s2a_retry_cmd_v & s2a_retry_cmd_r;
   assign o_dbg_cnt_inc[13:16] = s2_retry_cmd_v & s2_retry_cmd_r;


   assign  o_allocate_fc_tag = s0_tag_v & s0_tag_r;
   assign  o_free_fc_tag = s0_free_chnl_dec;
   wire s0a_tag_v, s0a_tag_r;
   wire [0:fc_tag_width-1] s0a_tag_d;
   wire [0:chnlid_width-1] s0_chnl;

   base_encode#(.enc_width(chnlid_width),.dec_width(channels)) ichnl_enc
     (.i_d(s0_chnl_dec),.o_d(s0_chnl),.o_v(s0_pm_ok));
   
   base_amux#(.ways(channels)) icmux(.sel(s0_chnl_dec),.i_v(s0_tag_v),.i_r(s0_tag_r),.o_v(s0a_tag_v),.o_r(s0a_tag_r));
   base_emux#(.ways(channels),.width(fc_tag_width)) iemux(.sel(s0_chnl),.din(s0_tag_d),.dout(s0a_tag_d));
   // don't allocate a channel if there is already an error or if this is an afu only command
   wire                    s0_force = ~s0_ok | i_afu;

   assign o_fc_channel_stall = i_v ? s0_chnl_dec & s0_force & ~s0_tag_v : 4'h0 ;

   wire                    s0b_tag_v, s0b_tag_r;
   wire [0:2]              s0_v, s0_r;
   assign s0b_tag_r = s0_r[2];
   wire send_to_fc;
   wire s0_gated_v,s0_gated_r;
   base_aforce is0_frc(.i_v(s0a_tag_v),.i_r(s0a_tag_r),.o_v(s0b_tag_v),.o_r(s0b_tag_r),.en(~s0_force & s0_gated_v & send_to_fc)); 

   wire [0:1] s0_retry_fifo_v,s0_retry_fifo_r;
   wire       s0_retry_v,s0_retry_r;
   wire s1_dly_v,s1_dly_r;
   wire [0:afu_tag_width-1] s1_tag;


  wire s1_valid_cycle;

  base_vlat#(.width(1)) irv_dly_latc(.clk(clk),.reset(reset),.din(i_v & i_r),.q(s1_valid_cycle));

  wire retry_fifo_full;
  base_agate icmd_gate   (.i_v(i_v),.i_r(i_r),.o_v(s0_gated_v),.o_r(s0_gated_r),.en(~s1_valid_cycle & ~((i_gate_retry | i_rcb_hp | retry_fifo_full) & ~s0a_tag_v) ));

  assign o_dbg_cnt_inc[0] = s0_gated_v & s0_gated_r & ~i_rcb_hp; 
  assign o_dbg_cnt_inc[1] = s0_gated_v & s0_gated_r & i_rcb_hp; 


  base_acombine#(.ni(1),.no(2)) icmb(.i_v(s0_gated_v),.i_r(s0_gated_r),.o_v(s0_v[0:1]),.o_r(s0_r[0:1]));
  wire lp_tag_avail;
   wire [0:9] port_outst_hp_cnt;
   wire [0:9] port_outst_hp_retry_cnt;
   wire       port_retry_tag_avail;
   base_emux#(.ways(channels),.width(10)) ihpmux(.sel(s0_chnl),.din(outst_hp_cnt),.dout(port_outst_hp_cnt));
   base_emux#(.ways(channels),.width(10)) ihpretrymux(.sel(s0_chnl),.din(outst_hp_retry_cnt),.dout(port_outst_hp_retry_cnt));
   base_emux#(.ways(channels),.width(1)) iretrytag_availmux(.sel(s0_chnl),.din(retry_tag_avail),.dout(port_retry_tag_avail));
   wire [0:cnt_width-1] port_outst_cnt;
   base_emux#(.ways(channels),.width(cnt_width)) icntmux(.sel(s0_chnl),.din(outst_cnt),.dout(port_outst_cnt)); 
   wire retry_fifo_ready;
   assign retry_fifo_full = ~retry_fifo_ready;
   base_emux#(.ways(channels),.width(1)) irdymux(.sel(s0_chnl),.din(s0a_retry_fifo_r),.dout(retry_fifo_ready)); 
   assign port_outst_cnt_retry_eq_0 = (port_outst_hp_retry_cnt == 10'b000000000);

   assign lp_tag_avail =  (port_outst_cnt_retry_eq_0 & port_retry_tag_avail) | retry_fifo_full ;
  assign send_to_fc = (s0a_tag_v & (lp_tag_avail | i_rcb_hp  | i_gate_retry)) | s0_force  ;
  wire cmd_is_retried = (~(lp_tag_avail | i_rcb_hp  | i_gate_retry) | (~s0a_tag_v & ~retry_fifo_full)) & ~s0_force ;
  wire [0:channels-1] send_to_retry = cmd_is_retried ? s0_chnl_dec : 4'h0;

   base_afilter itag_filter   (.i_v(s0_v[0]),.i_r(s0_r[0]),.o_v(s0_v[2]),.o_r(s0_r[2]),.en(send_to_fc));
   base_afilter inotag_filter (.i_v(s0_v[1]),.i_r(s0_r[1]),.o_v(s0_retry_v),.o_r(s0_retry_r),.en(cmd_is_retried));
   assign o_dbg_cnt_inc[2:4] = s0_v & s0_r; 
  
   base_acombine#(.ni(1),.no(2)) icmb_retry(.i_v(s0_retry_v),.i_r(s0_retry_r),.o_v(s0_retry_fifo_v),.o_r(s0_retry_fifo_r));

   base_ademux#(.ways(4)) irtry_demux(.i_v(s0_retry_fifo_v[0]),.i_r(s0_retry_fifo_r[0]),.o_v(s0a_retry_fifo_v),.o_r(s0a_retry_fifo_r),.sel(s0_chnl_dec & ~s0_force));

   assign o_dbg_cnt_inc[5:6] = s0_retry_fifo_v & s0_retry_fifo_r;

   base_fifo#(.width(afu_tag_width),.LOG_DEPTH(5),.output_reg(1)) i_reset_afu_cmd_tag_fifo    
     (.clk(clk),.reset(reset),
      .i_v(s0_retry_fifo_v[1]),.i_r(s0_retry_fifo_r[1]),.i_d(i_tag),
      .o_v(o_reset_afu_cmd_tag_v),.o_r(o_reset_afu_cmd_tag_r),.o_d(o_reset_afu_cmd_tag));

   assign o_dbg_cnt_inc[7] = o_reset_afu_cmd_tag_v & o_reset_afu_cmd_tag_r; 
   assign o_dbg_cnt_inc[8] = o_retry_cmd_v & o_retry_cmd_r;

     assign inc_hp_tag_cnt = s2_retry_cmd_v & s2_retry_cmd_r;
   assign dec_hp_tag_cnt = s0_v[2] & s0_r[2] & i_rcb_hp ? s0_chnl_dec & ~s0_force : 4'h0;


   assign o_croom_ctxt = i_rcb_ctxt;  

   base_alatch#(.width(afu_tag_width+1+fc_tag_width+chnlid_width+1+rc_width+erc_width+aux_width)) is1_lat
     (.clk(clk),.reset(reset),
      .i_v(s0_v[2]),.i_r(s0_r[2]),.i_d({i_tag, ~s0_force, s0a_tag_d, s0_chnl,s0_ok,s0_rc,s0_erc,i_aux}),
      .o_v(o_v),.o_r(o_r),.o_d({o_afu_tag,o_fc_tag_valid, o_fc_tag,o_chnl,o_ok,o_rc,o_erc,o_aux})
      );
endmodule // ktms_chnl_alloc
				      
				      
				      
	
		    
    
    
   
