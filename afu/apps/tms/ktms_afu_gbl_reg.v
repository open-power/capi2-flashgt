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
//----------------------------------------------------------------------------- 
// 
// IBM Confidential 
// 
// IBM Confidential Disclosure Agreement Number: 20160104OPPG01 
// Supplement Number: 20160104OPPG02
// 
// (C) Copyright IBM Corp. 2016 
// 
//    The source code for this program is not published or otherwise 
//    divested of its trade secrets, irrespective of what has been 
//    deposited with the U.S. Copyright Office. 
// 
//----------------------------------------------------------------------------- 


module ktms_afu_gbl_reg#
  (parameter mmio_addr=0,
   parameter mmiobus_width = 1,
   parameter ctxtid_width = 1,
   parameter fc_status_width = 1,
   parameter channels = 1,
   parameter msinum_width = 1
   )   
   (input         clk,
    input                       reset,

    
    input   [0:mmiobus_width-1] i_mmiobus,

    input                       i_ctxt_rmv_v, 
    input    [0:ctxtid_width-1] i_ctxt_upd_d,


    input [0:fc_status_width-1] i_fc_event,
    input                       o_intr_r,
    input                [0:63] i_fc_perror,
    output                      o_intr_v,
    output   [0:ctxtid_width-1] o_intr_ctxt, 
    output   [0:msinum_width-1] o_intr_msi,
    output                      o_localmode,

    input                [0:63] i_afu_version,
    input                       i_user_image, 
    
    output                      o_mmio_rd_v,
    output               [0:63] o_mmio_rd_d,

    output               [0:63] o_reg6,
    output               [0:63] o_reg7,
    output               [0:63] o_reg8,
    output               [0:63] o_reg9,
    output               [0:63] o_reg11, 
    output                      o_perror

   );

   localparam lcladdr_width = 4;
   localparam lcladdr_dec_width = 16;

   localparam [0:63] reg7_rstv = 64'h8040_0400_6000_0022;
   localparam [0:63] reg6_rstv = 64'h0000_0000_0000_000F;

   localparam [0:63] reg8_rstv = 64'h0000_0000_005C_0000; // rrin read timeout in us
   localparam [0:63] reg9_rstv = 64'h0000_0000_0000_0000; // rrin read timeout in us  
   localparam [0:63] reg10_rstv = 64'h0000_0000_0000_0000; // fc perror init values
   localparam [0:63] reg11_rstv = 64'h0000_0000_0000_0001; // mask false errors until fixed
   
   // logic to clear afu control register if the departing context matches the global interrupt context and msi=0
   wire [0:ctxtid_width-1] 	s1_ctxtupd_d;
   wire 			s1_ctxtupd_v;
   
   base_alatch#(.width(ctxtid_width)) is1_ctxtupd_lat(.clk(clk),.reset(reset),.i_v(i_ctxt_rmv_v),.i_r(),.i_d(i_ctxt_upd_d),.o_v(s1_ctxtupd_v),.o_r(1'b1),.o_d(s1_ctxtupd_d));

   wire 			s2_reg3_clr_v;
   wire 			s1_ctxtupd_match = (s1_ctxtupd_d[ctxtid_width-2] == o_intr_ctxt[ctxtid_width-2]) & (| o_intr_msi);
   base_vlat#(.width(1)) ictxtadd_lat(.clk(clk),.reset(reset),.din(s1_ctxtupd_match & s1_ctxtupd_v),.q(s2_reg3_clr_v));
   wire                         s1_perror;
   capi_parcheck#(.width(ctxtid_width-1)) s1_ctxtupd_d_pcheck0(.clk(clk),.reset(reset),.i_v(s1_ctxtupd_v),.i_d(s1_ctxtupd_d[0:ctxtid_width-2]),.i_p(s1_ctxtupd_d[ctxtid_width-1]),.o_error(s1_perror));
   wire  				hld_perror;
   wire  				any_hld_perror = |{hld_perror};
   base_vlat_sr#(.width(1)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(1'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(any_hld_perror),.q(o_perror));

   
   wire 		      s1_wr_v;
   wire 		      s1_wr_r;
   wire [0:lcladdr_width]     s1_wr_addr;
   wire [63:0] 		      s1_wr_d;
   
   wire 		       gbl_cfg;  // this is config space
   wire 		       gbl_rnw;  // read not write
   wire 		       gbl_vld;  // valid 
   wire 		       gbl_dw;   // double word
   wire [0:64] 		       gbl_data;   // change 63 to 64 to add parity kch 
   wire [0:24]  	       gbl_addr;
   wire [0:1+1+1+1+24+64-1]      gbl_mmiobus;
   assign {gbl_vld,gbl_cfg,gbl_rnw,gbl_dw,gbl_addr,gbl_data} = i_mmiobus; // omit any extra data bits
   assign gbl_mmiobus = {gbl_vld,gbl_cfg,gbl_rnw,gbl_dw,gbl_addr[0:23],gbl_data[0:63]};  // created to strip of parity 

   ktms_mmwr_dec#(.mmiobus_width(mmiobus_width-2),.addr(mmio_addr),.lcladdr_width(lcladdr_width+1)) immwr_dec  //added -2 stripped off parity
     (.clk(clk),.reset(reset),
      .i_mmiobus(gbl_mmiobus),
      .o_wr_r(s1_wr_r), .o_wr_v(s1_wr_v),.o_wr_addr(s1_wr_addr),.o_wr_d(s1_wr_d)
      );
   assign s1_wr_r = 1'b1;
   wire [0:lcladdr_dec_width-1] s1_wr_addr_dec;

   // only dw access is allowed to global regs
   base_decode#(.enc_width(lcladdr_width),.dec_width(lcladdr_dec_width)) is1_wr_dec
     (.din(s1_wr_addr[0:lcladdr_width-1]),.en(s1_wr_v),.dout(s1_wr_addr_dec));


   wire 		      s2_rd_v, s2_rd_r;
   wire [0:63] s2_rd_d_b;
   wire [0:lcladdr_width] s1_rd_addr;
   wire 		  s1_rd_v, s1_rd_r;
   wire [0:1] 		  s3_rd_v;
   wire [0:64*2-1] 	  s3_rd_d;
   
   ktms_mmrd_dec#(.mmiobus_width(mmiobus_width-2),.addr(mmio_addr),.lcladdr_width(lcladdr_width+1)) immrd_dec0
     (.clk(clk),.reset(reset),
      .i_mmiobus(gbl_mmiobus),
      .o_rd_v(s1_rd_v),.o_rd_r(s1_rd_r),.o_rd_addr(s1_rd_addr),
      .i_rd_v(s2_rd_v),.i_rd_r(s2_rd_r),.i_rd_d(~s2_rd_d_b),
      .o_mmio_rd_v(s3_rd_v[0]),.o_mmio_rd_d(s3_rd_d[0:63])
      );

   wire [0:lcladdr_dec_width-1] s1_rd_addr_dec;
   base_decode#(.enc_width(lcladdr_width),.dec_width(lcladdr_dec_width)) is1_rd_dec
     (.din(s1_rd_addr[0:lcladdr_width-1]),.en(s1_rd_v),.dout(s1_rd_addr_dec));
   
   wire [0:lcladdr_dec_width-1] s2_rd_addr_dec;
   
   base_alatch#(.width(lcladdr_dec_width)) s2_rd_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_rd_v),.i_r(s1_rd_r),.i_d(s1_rd_addr_dec),
      .o_v(s2_rd_v),.o_r(s2_rd_r),.o_d(s2_rd_addr_dec)
      );


   localparam aintr_width = fc_status_width;
			
   wire [0:aintr_width-1] 	s1_fc_event;
   base_vlat#(.width(aintr_width)) is1_fc_event(.clk(clk),.reset(reset),.din({i_fc_event}),.q(s1_fc_event));

   wire 			s1_clr_v = s1_wr_v & s1_wr_addr_dec[1];
   wire [0:aintr_width-1] 	s1_intr_clr = s1_clr_v ? s1_wr_d[aintr_width-1:0] : {aintr_width{1'b0}};
   wire [0:aintr_width-1] 	s1_intr_set = s1_fc_event;
			
   wire [0:aintr_width-1] 	reg0; // interupt status
   wire [0:aintr_width-1] 	reg0_in = reg0 & ~s1_intr_clr | s1_intr_set;

   // reg2 is complemented so it will come up all 1's initialy and on reset
   wire [63:0] 			reg2_b; // interupt mask

   wire [0:aintr_width-1] 	s1_new_intr_msk = s1_intr_set & reg2_b[aintr_width-1:0];
   wire [0:aintr_width-1] 	s1_rep_intr_msk = s1_clr_v ? reg0_in : {aintr_width{1'b0}};
   wire 			s1_intr_v = | {s1_new_intr_msk, s1_rep_intr_msk};
   

   wire [0:63] 	 reg3; // afu control
   wire [0:63] 	 reg4; // heartbeat
   wire [0:63] 	 reg5; // scratchpad
   wire [0:63] 	 reg6; // scratchpad
   wire [0:63] 	 reg7; // settings
   wire [0:63] 	 reg8; // rrin fetch timeout
   wire [0:63] 	 reg9;
   wire [0:63] 	 reg10; // perror status
   wire [0:63]   reg11; // perror mask
   


   wire [0:63] 	 reg4_in = reg4+64'd1;
   
   base_vlat#(.width(aintr_width)) ireg0(.clk(clk),.reset(reset),.din(reg0_in),.q(reg0)); // istat
   base_vlat_en#(.width(64)) ireg2(.clk(clk),.reset(reset),.enable(s1_wr_addr_dec[2]),.din(~s1_wr_d),.q(reg2_b)); // imask

   // special logic to clear reg3 when match context is removed
   wire 	 s1_reg3_en = s1_wr_addr_dec[3] | s2_reg3_clr_v;
   wire [0:63] 	 s1_reg3_wr_d = s2_reg3_clr_v ? 64'd0 : s1_wr_d;
   base_vlat_en#(.width(64)) ireg3(.clk(clk),.reset(reset),.enable(s1_reg3_en),.din(s1_reg3_wr_d),.q(reg3)); // afu control

   base_vlat_en#(.width(64)) ireg4(.clk(clk),.reset(reset),.enable(s2_rd_v & s2_rd_r & s2_rd_addr_dec[4]),         .din(reg4_in),.q(reg4)); // hearbeat
   base_vlat_en#(.width(64)) ireg5(.clk(clk),.reset(reset),.enable(s1_wr_addr_dec[5]),.din(s1_wr_d),.q(reg5)); // scratchpad
   base_vlat_en#(.width(64),.rstv(reg6_rstv)) ireg6(.clk(clk),.reset(reset),.enable(s1_wr_addr_dec[6]),.din(s1_wr_d),.q(reg6)); // scratchpad
   base_vlat_en#(.width(1)                        ) ireg7_0(   .clk(clk),.reset(1'b0),.enable(s1_wr_addr_dec[7]),.din(s1_wr_d[63]),.q(reg7[0])); // settings - checker enable (sticky)
   base_vlat_en#(.width(63),.rstv(reg7_rstv[1:63])) ireg7_1_63(.clk(clk),.reset(reset),.enable(s1_wr_addr_dec[7]),.din(s1_wr_d[62:0]),.q(reg7[1:63])); // settings
   base_vlat_en#(.width(64),.rstv(reg8_rstv)) ireg8(.clk(clk),.reset(reset),.enable(s1_wr_addr_dec[8]),.din(s1_wr_d),.q(reg8)); // settings
   base_vlat_en#(.width(64),.rstv(reg9_rstv)) ireg9(.clk(clk),.reset(reset),.enable(s1_wr_addr_dec[9]),.din(s1_wr_d),.q(reg9)); // settings
   base_vlat_en#(.width(64),.rstv(reg10_rstv)) ireg10(.clk(clk),.reset(1'b0),.enable(1'b1),.din(i_fc_perror),.q(reg10)); // parity error capture
   base_vlat_en#(.width(64),.rstv(reg11_rstv)) ireg11(.clk(clk),.reset(1'b0),.enable(s1_wr_addr_dec[11]),.din(s1_wr_d),.q(reg11)); // perror mask

   assign o_reg11 = reg11;
   assign o_reg9 = reg9;
   assign o_reg8 = reg8;
   assign o_reg7 = reg7;
   assign o_reg6 = reg6;

   wire [0:63] 	 reg0_d = {{64-aintr_width{1'b0}},reg0};
   
   base_mux#(.ways(11),.width(64)) is2rd_mux
     (.sel({s2_rd_addr_dec[0], s2_rd_addr_dec[2:11]}),
      .din({~reg0_d, reg2_b, ~reg3, ~reg4, ~reg5, ~reg6, ~reg7, ~reg8, ~reg9, ~reg10, ~reg11}),
      .dout(s2_rd_d_b)
      );

   capi_parity_gen#(.dwidth(9),.width(1)) igbl_pgen(.i_d(o_intr_ctxt[0:ctxtid_width-2]),.o_d(o_intr_ctxt[ctxtid_width-1]));
   assign o_intr_ctxt[0:ctxtid_width-2] = reg3[16-ctxtid_width:15];  
   assign o_intr_msi  = reg3[24-msinum_width:23];
   assign o_localmode = reg3[63];
   base_alatch#(.width(1)) iintr_req_lat(.clk(clk),.reset(reset),.i_v(s1_intr_v),.i_r(),.i_d(1'b0),.o_v(o_intr_v),.o_r(o_intr_r),.o_d());


   localparam lcladdr1_width = 1;
   localparam lcladdr1_dec_width = 2;


   wire [0:63]   s2_rd1_d;
   // 0:47=capability list, 48:55=major version, 56:63=minor version
   // all Fs for "factory image"
   wire [0:63]   interface_version = i_user_image ? 64'h0000000200 : 64'hffffffffffffffff;  

   wire [0:lcladdr1_width] s1_rd1_addr;
   wire 	 s1_rd1_v, s1_rd1_r;
   wire 	 s2_rd1_v, s2_rd1_r;
   ktms_mmrd_dec#(.mmiobus_width(mmiobus_width-2),.addr(mmio_addr+'h200),.lcladdr_width(lcladdr1_width+1)) immrd_dec1
     (.clk(clk),.reset(reset),
      .i_mmiobus(gbl_mmiobus),
      .o_rd_v(s1_rd1_v),.o_rd_r(s1_rd1_r),.o_rd_addr(s1_rd1_addr),
      .i_rd_v(s2_rd1_v),.i_rd_r(s2_rd1_r),.i_rd_d(s2_rd1_d),
      .o_mmio_rd_v(s3_rd_v[1]),.o_mmio_rd_d(s3_rd_d[64:127])
      );

   wire [0:lcladdr1_dec_width-1] s1_rd1_addr_dec;
   base_decode#(.enc_width(lcladdr1_width),.dec_width(lcladdr1_dec_width)) is1_rd1_dec
     (.din(s1_rd1_addr[0:lcladdr1_width-1]),.en(s1_rd1_v),.dout(s1_rd1_addr_dec));
   
   wire [0:lcladdr1_dec_width-1] s2_rd1_addr_dec;
   base_alatch#(.width(lcladdr1_dec_width)) s2_rd1_lat
     (.clk(clk),.reset(reset),
      .i_v(s1_rd1_v),.i_r(s1_rd1_r),.i_d(s1_rd1_addr_dec),
      .o_v(s2_rd1_v),.o_r(s2_rd1_r),.o_d(s2_rd1_addr_dec)
      );

   base_mux#(.ways(2),.width(64)) is2r1_mux
     (.sel(s2_rd1_addr_dec[0:1]),
      .din({i_afu_version, interface_version}),
      .dout(s2_rd1_d)
      );


   base_mux#(.ways(2),.width(64)) is3_rd_mux(.sel(s3_rd_v),.din(s3_rd_d),.dout(o_mmio_rd_d));
   assign o_mmio_rd_v = | s3_rd_v;

endmodule // ktms_afu_gbl_reg


   
