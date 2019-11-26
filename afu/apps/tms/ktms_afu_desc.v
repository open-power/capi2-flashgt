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
`define MULTI_CONTEXT
module ktms_afu_desc#
  (parameter ctxtid_width=8,
   parameter ctag_width=8,
   parameter pea_width=52,
   parameter cnt_rsp_width=2*pea_width+ctxtid_width+ctag_width+4
   )
   /* note: we swizlle the data because apparently kernel software is converting this from le to be.  So, we have to make it come out le
    */
  (input                      clk,
   input 		      reset, 
   input 		      ha_mmval, // A valid MMIO is present
   input 		      ha_mmrnw, // 1 = read, 0 = write
   input 		      ha_mmdw, // 1 = doubleword, 0 = word
   input [0:23] 	      ha_mmad, // mmio address
   input 		      ha_mmcfg,
   input [0:63] 	      ha_mmdata,   
   input         	      ha_mmdatapar,   
   output 		      ah_mmack, // Write is complete or Read is valid
   output [0:63] 	      ah_mmdata, // Read data
   output 		      o_cnt_rsp_v,
   output [0:cnt_rsp_width-1] o_cnt_rsp_d,
   output [0:63] 	      o_rega,
   output [0:63] 	      o_regb,
   output                     o_perror
   );
   
`ifdef MULTI_CONTEXT
   wire [0:63] 	  reg0; //0x00
   assign reg0[0:15] = 16'd0; // number of interupts per process
   assign reg0[16:31] = 16'd512; // number of processes
   assign reg0[32:47] = 16'd1; // number of configuration records
   assign reg0[48] = 1'b1; // multiple proramming models are supported
   assign reg0[49:58] = 10'd0;
   assign reg0[59] = 1'b0; // dedicated process supported
   assign reg0[60] = 1'b0; // reserved
   assign reg0[61] = 1'b1; // afu directed supported
   assign reg0[62] = 1'b0; // reserved
   assign reg0[63] = 1'b0; // shared time-slice not supported

   wire [0:63] 	  reg1 = 64'b0;
   wire [0:63] 	  reg2 = 64'b0;
   wire [0:63] 	  reg3 = 64'b0;
   wire [0:63]    reg4;         // 0x20
   assign reg4 = 64'h01;        // configuration record length = 256B
   wire [0:63]    reg5;         // 0x28
   assign reg5 = 64'h0100;      // configuration record offset = 256B from start of AFU descriptor
   

   wire [0:63] 	  reg6; // 0x030
   assign reg6[0:5]    = 7'd0;
   assign reg6[6]      = 1'b1; // per process problem state
   assign reg6[7]      = 1'b1; // problem state area required
   assign reg6[8:63]   = 56'd16; // 64k psa per process
   wire [0:63] 	  reg7 = 64'b0;
`else
   wire [0:63] 	  reg0; //0x00
   assign reg0[0:15] = 16'd0; // number of interupts per process
   assign reg0[16:31] = 16'd512; // number of processes
   assign reg0[32:47] = 16'd0; // number of configuration records
   assign reg0[48] = 1'b1; // multiple proramming models are supported
   assign reg0[49:58] = 10'd0;
   assign reg0[59] = 1'b1; // dedicated process supported
   assign reg0[60] = 1'b0; // reserved
   assign reg0[61] = 1'b0; // afu directed supported
   assign reg0[62] = 1'b0; // reserved
   assign reg0[63] = 1'b0; // shared time-slice not supported

   wire [0:63] 	  reg1 = 64'b0;
   wire [0:63] 	  reg2 = 64'b0;
   wire [0:63] 	  reg3 = 64'b0;
   wire [0:63] 	  reg4 = 64'b0;
   wire [0:63] 	  reg5 = 64'b0;

   wire [0:63] 	  reg6; // 0x030
   assign reg6[0:5]    = 7'd0;
   assign reg6[6]      = 1'b0; // per process problem state
   assign reg6[7]      = 1'b1; // problem state area required
   assign reg6[8:63]   = 56'd0; // 64k psa per process
   wire [0:63] 	  reg7 = 64'b0;
`endif // !`ifdef MULTI_CONTEXT
  
   wire [0:63]    reg8=64'b0;
   wire [0:63] 	  reg9=64'b0;
   wire [0:63] 	  rega;   // 0x50 continue response
   wire [0:63] 	  regb;   // 0x58 continue response
   wire [0:63] 	  regc=64'b0;
   wire [0:63] 	  regd=64'b0;
   wire [0:63] 	  rege=64'b0;
   wire [0:63] 	  regf=64'b0;


   // implement registers a and b (0x50 and 0x58) for completing the Continue response 
   wire 	  s0_reg_ab_we = ha_mmval & ~ha_mmrnw & ha_mmcfg & (ha_mmad[0:21] == 22'h05);
   wire [0:3] 	  s0_reg_ab_adec;
   base_decode#(.enc_width(2),.dec_width(4)) is0_reg_ab_dec(.din(ha_mmad[22:23]),.dout(s0_reg_ab_adec),.en(s0_reg_ab_we));

   // word write enables   
   wire [0:3] 	  s0_reg_ab_wwe;
   assign s0_reg_ab_wwe[0] = s0_reg_ab_adec[0];
   assign s0_reg_ab_wwe[1] = ha_mmdw ? s0_reg_ab_adec[0] : s0_reg_ab_adec[1];
   assign s0_reg_ab_wwe[2] = s0_reg_ab_adec[2];
   assign s0_reg_ab_wwe[3] = ha_mmdw ? s0_reg_ab_adec[2] : s0_reg_ab_adec[3];
   wire [0:3] 	  s1_reg_ab_we;
   base_vlat#(.width(4)) is1_reg_ab_we_lat(.clk(clk),.reset(reset),.din(s0_reg_ab_wwe),.q(s1_reg_ab_we));

   wire [0:64] 	  s1_mmdata;   // changed 63 to 64 kch
   wire           s1_mmwr;
   base_vlat#(.width(65)) is1_mmdata_lat(.clk(clk),.reset(reset),.din({ha_mmdata,ha_mmdatapar}),.q(s1_mmdata));  // 64 to 65 kch
   base_vlat#(.width(1)) is1_mmwr_lat(.clk(clk),.reset(reset),.din(ha_mmval & ~ha_mmrnw),.q(s1_mmwr));  
   wire s1_reg_ab_we_act = (s1_reg_ab_we[0]|s1_reg_ab_we[1]|s1_reg_ab_we[2]|s1_reg_ab_we[3]);
   wire           s1_perror;
   capi_parcheck#(.width(64)) s1_mmdata_pcheck(.clk(clk),.reset(reset),.i_v(s1_mmwr),.i_d(s1_mmdata[00:63]),.i_p(s1_mmdata[64]),.o_error(s1_perror));
   wire  				hld_perror;
   wire  				any_hld_perror = |(hld_perror);
   base_vlat_sr#(.width(1)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(1'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(any_hld_perror),.q(o_perror));

   // bit 0 is defined to be 1
   assign rega[0] = 1'b1;
   base_vlat_en#(.width(31)) ireg_a0_lat(.clk(clk),.reset(reset),.din(s1_mmdata[01:31]),.q(rega[01:31]),.enable(s1_reg_ab_we[0]));
   base_vlat_en#(.width(32)) ireg_a1_lat(.clk(clk),.reset(reset),.din(s1_mmdata[32:63]),.q(rega[32:63]),.enable(s1_reg_ab_we[1]));
   base_vlat_en#(.width(32)) ireg_b0_lat(.clk(clk),.reset(reset),.din(s1_mmdata[00:31]),.q(regb[00:31]),.enable(s1_reg_ab_we[2]));
   base_vlat_en#(.width(32)) ireg_b1_lat(.clk(clk),.reset(reset),.din(s1_mmdata[32:63]),.q(regb[32:63]),.enable(s1_reg_ab_we[3]));
      
   
   wire 	  s0_mmack = ha_mmval & ha_mmrnw & ha_mmcfg & 
                             ((ha_mmad[2:18] == 17'h0000) |    // afu descriptor regs
                              (ha_mmad[2:17] == 16'h0001));    // descriptor configuration record
   wire 	  s1_mmack;
   wire [17:23]   s1_mmad;
   wire 	  s1_mmdw;
   base_vlat#(.width(1+7)) is1_adlat(.clk(clk),.reset(1'b0),.din({ha_mmdw,ha_mmad[17:23]}),.q({s1_mmdw,s1_mmad}));
   base_vlat#(.width(1))    is1_vlat (.clk(clk),.reset(reset),.din(s0_mmack),.q(s1_mmack));

   wire [0:63] 	  s1_desc_dout_dw;

   base_emux#(.ways(16),.width(64)) idmux(.din({reg0,reg1,reg2,reg3,reg4,reg5,reg6,reg7,reg8,reg9,rega,regb,regc,regd,rege,regf}),.dout(s1_desc_dout_dw),.sel(s1_mmad[19:22]));

   // config record at offset 0x100
   wire [0:63]    creg0;  // 0x100
   wire [0:63]    creg1;  // 0x108
   wire [0:63]    creg2;  // 0x110
   wire [0:63]    creg3;  // 0x118
   wire [0:63]    creg4;  // 0x120
   wire [0:63]    creg5;  // 0x128
   wire [0:63]    creg6;  // 0x130

   assign creg0[48:63] = 16'h1014;  // vendor id - bytes 1&0
   assign creg0[32:47] = 16'h0600;  // device id - bytes 3&2 - 0x0600 for FlashGT and FlashGT+
   assign creg0[16:31] = 16'h0000;  // command 
   assign creg0[0:15]  = 16'h0010;  // status
   assign creg1[56:63] = 8'h02;     // revision id
   assign creg1[32:55] = 24'h018000; // Class code/subclass/progif - 0x0180 = mass storage/other
   assign creg1[24:31] = 8'h00; // Cache Line
   assign creg1[16:23] = 8'h00; // Latency Time
   assign creg1[8:15]  = 8'h00; // Header Type
   assign creg1[0:7]   = 8'h00; // BIST
   assign creg2[0:63]  = 64'h0; // BARs/reserved
   assign creg3[0:63]  = 64'h0; // BARs/reserved
   assign creg4[0:63]  = 64'h0; // BARs/reserved
   assign creg5[32:63] = 32'h0; // reserved (cardbus CIS pointer)
   assign creg5[16:31] = 16'h1014; // subsystem vendor id
   assign creg5[0:15]  = 16'h0633; // subsystem id 0x0600 for FlashGT, 0x0633 for FlashGT+
   assign creg6[32:63] = 32'h0; // reserved (expansion rom base address)
   assign creg6[24:31] = 8'h00; // Capabilities Pointer
   assign creg6[0:23]  = 24'h0; // reserved
   
   wire [0:63] 	  s1_cfg_dout_dw;
   wire [0:63]    s1_cfg_dout_dw_be;
   base_emux#(.ways(16),.width(64)) icmux(.din({creg0,creg1,creg2,creg3,creg4,creg5,creg6,{64'd0},{512'd0}}),.dout(s1_cfg_dout_dw),.sel(s1_mmad[19:22]));
   // swap little endian config record -> big endian mmio interface
   base_endian_szl#(.bytes(8),.szl(1)) icszl(.i_d(s1_cfg_dout_dw),.o_d(s1_cfg_dout_dw_be));
   
   wire [0:63]    s1_dout_dw;
   assign s1_dout_dw = (s1_mmad[17:18] == 2'b00) ? s1_desc_dout_dw :
                       ((s1_mmad[17:18] == 2'b10) ? s1_cfg_dout_dw_be : 64'h0);
  
   wire [0:63] 	  s2_dout_xe;
   capi_mmio_sw_mux isw_mux(.ha_mmdw(s1_mmdw),.ha_mmad(~s1_mmad[23]),.din(s1_dout_dw),.dout(ah_mmdata));
   assign ah_mmack  = s1_mmack;


   // continue resonse MMIO
   wire 	  s2_cnt_rsp_v;
   base_vlat#(.width(1)) is2_cnt_rsp_vlat(.clk(clk),.reset(reset),.din(s1_reg_ab_we[3]),.q(s2_cnt_rsp_v));
   wire s2_cnt_rsp_ctxt_par;
   wire [0:ctxtid_width-1] s2_cnt_rsp_ctxt = {rega[64-ctxtid_width+1:64-1],s2_cnt_rsp_ctxt_par};  //  added +1 to compensate for parity in ctxt width (went from 9 to 10)
   capi_parity_gen#(.dwidth(9),.width(1)) afu_desc_pgen(.i_d(s2_cnt_rsp_ctxt[0:ctxtid_width-2]),.o_d(s2_cnt_rsp_ctxt_par));  // added parity kch 
   wire [0:ctag_width-1]   s2_cnt_rsp_ctag = rega[32-ctag_width:32-1];
   wire [0:pea_width-1]    s2_cnt_rsp_addr = regb[0:pea_width-1];
   wire [0:3] 		   s2_cnt_rsp_rc   = regb[52:55];
   wire [0:5] 		   s2_cnt_rsp_pgsz = regb[58:63];
   wire [0:pea_width-1]    s2_cnt_rsp_pgsz_tdec;
   base_tdec#(.enc_width(6),.dec_width(pea_width)) is2_cnt_rsp_dec(.i_d(s2_cnt_rsp_pgsz),.o_d(s2_cnt_rsp_pgsz_tdec));

   wire [0:pea_width-1]    s2_cnt_rsp_pgsz_msk_b;
   base_bitswap#(.width(pea_width)) is2_cnt_rsp_bswp(.i_d(s2_cnt_rsp_pgsz_tdec),.o_d(s2_cnt_rsp_pgsz_msk_b));
   wire [0:pea_width-1]    s2_cnt_rsp_pgsz_msk = ~s2_cnt_rsp_pgsz_msk_b;
   
   base_alatch#(.width(cnt_rsp_width)) is3_cnt_rsp_lat
     (.clk(clk),.reset(reset),
      .i_v(s2_cnt_rsp_v),.i_r(),.i_d({s2_cnt_rsp_pgsz_msk,s2_cnt_rsp_addr,s2_cnt_rsp_ctxt,s2_cnt_rsp_ctag,s2_cnt_rsp_rc}),
      .o_v(o_cnt_rsp_v),.o_r(1'b1),.o_d(o_cnt_rsp_d)
      );
   assign o_rega = rega;
   assign o_regb = regb;
   
endmodule // ktms_afu_desc

   
