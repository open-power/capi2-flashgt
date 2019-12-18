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
// requires tags*8 sw addresses

module ktms_afu_track#
  (parameter tag_width=1,
   parameter mmiobus_width=1,
   parameter mmioaddr=0,
   parameter ctxtid_width=1,
   parameter ea_width=1,
   parameter lba_width=48,
   parameter lidx_width=8,
   parameter chnlid_width=1,
   parameter rslt_width=1,
   parameter afu_rc_width=1,
   parameter afu_erc_width=1,
   parameter reslen_width=1,
   parameter fcstat_width=1,
   parameter fcxstat_width=1,
   parameter scstat_width=1
   )
   (input clk,
    input 		      reset,

    input 		      i_cp0_v,
    input [0:tag_width-1]     i_cp0_tag,
    input [0:63] 	      i_cp0_ts,

    input 		      i_cpvrh_v,
    input [0:tag_width-1]     i_cpvrh_tag,
    input [0:47] 	      i_cpvrh_d,
    
    input 		      i_cp1_v,
    input [0:tag_width-1]     i_cp1_tag,
    input [0:31] 	      i_cp1_ts,
    input [0:ctxtid_width-1]  i_cp1_ctxt,
    input [0:ea_width-1]      i_cp1_ea,
    input [0:lba_width-1]     i_cp1_lba,
    input [0:7]               i_cp1_rc,

    input 		      i_cp2_v,
    input [0:tag_width-1]     i_cp2_tag,
    input [0:31] 	      i_cp2_ts,
    input [0:lba_width-1]     i_cp2_lba, //48
    input [0:chnlid_width-1]  i_cp2_chnl,
    input [0:lidx_width-1]    i_cp2_lidx,
    input 		      i_cp2_vrh,
    input [0:7]               i_cp2_rc,
//    input [0:7]               i_cp2_erc,

    input 		      i_cp3_v,
    input [0:tag_width-1]     i_cp3_tag,
    input [0:64] 	      i_cp3_lun,

    input 		      i_cp4_v,
    input [0:tag_width-1]     i_cp4_tag,
    input [0:31] 	      i_cp4_ts,
    input [0:rslt_width-1]    i_cp4_stat,

    input 		      i_cp5_v,
    input [0:tag_width-1]     i_cp5_tag,
    input [0:31] 	      i_cp5_ts,
    input                     i_freeze_on_error,
    output                    o_error_status_hld,
    
    
    input [0:mmiobus_width-1] i_mmiobus,
    output 		      o_mmio_ack,
    output [0:63] 	      o_mmio_data
    );

   

   localparam mux_ways = 8;
   localparam sel_bits = $clog2(mux_ways);

   localparam lcladdr_width = tag_width+sel_bits+1;
   
   wire [0:lcladdr_width-1]    s1_rd_ra;
   
   wire [0:sel_bits-1] 	       s1_rd_sel = s1_rd_ra[tag_width:tag_width+sel_bits-1];
   wire [0:mux_ways-1] 	       s1_rd_en;
   wire 		       s2_rd_r, s2_rd_v;
   base_decode#(.enc_width(sel_bits),.dec_width(mux_ways)) is1_rd_dec(.en(s2_rd_r | ~s2_rd_v),.din(s1_rd_sel),.dout(s1_rd_en));
   
   wire [0:(64*mux_ways)-1]    s2_rd_d_premux;
   wire error_status_hld;

   base_mem#(.addr_width(tag_width),.width(64)) ivrh_mem
     (.clk(clk),
      .wa(i_cpvrh_tag),.wd({16'b0,i_cpvrh_d}),.we(i_cpvrh_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[64*3:(64*3)+63]),.re(s1_rd_en[3]));
   
   base_mem#(.addr_width(tag_width),.width(64)) icmd_time0_mem
     (.clk(clk),
      .wa(i_cp0_tag),.wd(i_cp0_ts),.we(i_cp0_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[(64*0):(64*0)+63]),.re(s1_rd_en[0])
      );
   
   base_mem#(.addr_width(tag_width),.width(32)) icmd_time1_mem
     (.clk(clk),
      .wa(i_cp1_tag),.wd(i_cp1_ts),.we(i_cp1_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[(64*1):(64*1)+31]),.re(s1_rd_en[1])
      );
   
   base_mem#(.addr_width(tag_width),.width(32)) icmd_time2_mem
     (.clk(clk),
      .wa(i_cp2_tag),.wd(i_cp2_ts),.we(i_cp2_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[(64*1)+32:(64*1)+63]),.re(s1_rd_en[1])
      );

   localparam afu_rc_st=0;
   localparam afu_erc_st = afu_rc_st+afu_rc_width;
   localparam fc_rc_st = afu_erc_st+afu_erc_width + 2 + reslen_width;
   localparam sc_rc_st =  fc_rc_st+fcstat_width+fcxstat_width;

   wire [0:31] cp4_wd = {
			 i_cp4_stat[afu_rc_st:afu_rc_st+afu_rc_width-1],
			 i_cp4_stat[afu_erc_st:afu_erc_st+afu_erc_width-1],
			 i_cp4_stat[fc_rc_st:fc_rc_st+fcstat_width-1],
			 i_cp4_stat[sc_rc_st:sc_rc_st+scstat_width-1]
			 };
   
   base_mem#(.addr_width(tag_width),.width(32)) icmd_time3_mem
     (.clk(clk),
      .wa(i_cp4_tag),.wd(cp4_wd),.we(i_cp4_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[(64*2):(64*2)+31]),.re(s1_rd_en[2])
      );
   
   base_mem#(.addr_width(tag_width),.width(32)) icmd_time4_mem
     (.clk(clk),
      .wa(i_cp5_tag),.wd(i_cp5_ts),.we(i_cp5_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[(64*2)+32:(64*2)+63]),.re(s1_rd_en[2])
      );
   
   base_mem#(.addr_width(tag_width),.width(64)) icmd_mem4
     (.clk(clk),
      .wa(i_cp1_tag),.wd(i_cp1_ea[0:ea_width-2]),.we(i_cp1_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[(64*4):(64*4)+63]),.re(s1_rd_en[4])
      );
   
   base_mem#(.addr_width(tag_width),.width(64)) icmd_mem5
     (.clk(clk),
      .wa(i_cp1_tag),.wd({i_cp1_lba,i_cp1_rc[2:7],i_cp1_ctxt}),.we(i_cp1_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[(64*5):(64*5)+63]),.re(s1_rd_en[5])
      );

   wire [63:0] cp2_wd;
   assign cp2_wd[47:0]  = i_cp2_lba;
   assign cp2_wd[55:48] = i_cp2_lidx;
//   assign cp2_wd[59:56] = {3'b0,i_cp2_chnl};
//   assign cp2_wd[63:60] = {3'b0,i_cp2_vrh};
   assign cp2_wd[58:56] = {i_cp2_chnl,i_cp2_vrh};
   assign cp2_wd[63:59] = {i_cp2_rc[3:7]};
   
   base_mem#(.addr_width(tag_width),.width(64)) icmd_mem6
     (.clk(clk),
      .wa(i_cp2_tag),.wd(cp2_wd),.we(i_cp2_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[(64*6):(64*6)+63]),.re(s1_rd_en[6])
      );
   
   base_mem#(.addr_width(tag_width),.width(64)) icmd_mem7
     (.clk(clk),
      .wa(i_cp3_tag),.wd(i_cp3_lun[0:63]),.we(i_cp3_v & ~i_freeze_on_error),
      .ra(s1_rd_ra[0:tag_width-1]),.rd(s2_rd_d_premux[(64*7):(64*7)+63]),.re(s1_rd_en[7])
      );
   
   
   wire [0:sel_bits-1] 	       s2_rd_sel;
   wire 		       s1_rd_v, s1_rd_r;
   wire error_rsp = (|(i_cp1_rc)& i_cp1_v) | (|(i_cp2_rc) & i_cp2_v);
   base_vlat#(.width(1)) ierror_status(.clk(clk),.reset(reset),.din(error_rsp | error_status_hld),.q(error_status_hld));
   base_alatch#(.width(sel_bits)) is2_rd_lat(.clk(clk),.reset(reset),.i_v(s1_rd_v),.i_r(s1_rd_r),.i_d(s1_rd_sel),.o_v(s2_rd_v),.o_r(s2_rd_r),.o_d(s2_rd_sel));


   
   wire [0:63] 		       s2_rd_d;
   base_emux#(.width(64),.ways(mux_ways),.sel_width(sel_bits)) is2_dmux(.sel(s2_rd_sel),.din(s2_rd_d_premux),.dout(s2_rd_d));
   
   
   wire 		       at_cfg;  // this is config space
   wire 		       at_rnw;  // read not write
   wire 		       at_vld;  // valid 
   wire 		       at_dw;   // double word
   wire [0:64] 		       at_data; 
   wire [0:24]  	       at_addr;
   wire [0:4+24+64-1]          at_mmiobus;
   assign {at_vld,at_cfg,at_rnw,at_dw,at_addr,at_data} = i_mmiobus; // omit any extra data bits
   assign at_mmiobus = {at_vld,at_cfg,at_rnw,at_dw,at_addr[0:23],at_data[0:63]}; 
   ktms_mmrd_dec#(.lcladdr_width(lcladdr_width),.addr(mmioaddr),.mmiobus_width(mmiobus_width-2)) immrd_dec
     (.clk(clk),.reset(reset),.i_mmiobus(at_mmiobus),
      .o_rd_r(s1_rd_r),.o_rd_v(s1_rd_v),.o_rd_addr(s1_rd_ra),
      .i_rd_r(s2_rd_r),.i_rd_v(s2_rd_v),.i_rd_d(s2_rd_d),
      .o_mmio_rd_v(o_mmio_ack),.o_mmio_rd_d(o_mmio_data)
      );
  assign o_error_status_hld = error_status_hld;
   
endmodule // ktms_afu_track

    
  
