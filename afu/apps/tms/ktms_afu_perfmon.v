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
module ktms_afu_perfmon#
  (parameter tag_width=1,
   parameter mmiobus_width=1,
   parameter mmioaddr=0,
   parameter stall_counters=1
   )
   (input clk,
    input 		       reset,

    input [0:31] 	       i_time,
    input [0:stall_counters-1] i_stall_cnt_v,
    input [0:stall_counters-1] i_stall_cnt_r,

    input 		       i_st_v,
    input [0:tag_width-1]      i_st_tag,
    input [0:31] 	       i_st_ts,

    input 		       i_s1_v,
    input [0:tag_width-1]      i_s1_tag,

    input 		       i_ed_v,
    input 		       i_ed_rnw,
    input [0:tag_width-1]      i_ed_tag,
    
    input [0:mmiobus_width-1]  i_mmiobus,
    output 		       o_mmio_ack,
    output [0:63] 	       o_mmio_data
    );

   
   wire [0:stall_counters-1]   s0_sc_en = i_stall_cnt_v & ~i_stall_cnt_r;
   wire [0:stall_counters-1]   s0_xc_en = i_stall_cnt_v & i_stall_cnt_r;
   wire [0:stall_counters-1]   s1_sc_en;
   wire [0:stall_counters-1]   s1_xc_en;

   base_vlat#(.width(stall_counters)) is1_sc_en_lat(.clk(clk),.reset(reset),.din(s0_sc_en),.q(s1_sc_en));
   base_vlat#(.width(stall_counters)) is1_xc_en_lat(.clk(clk),.reset(reset),.din(s0_xc_en),.q(s1_xc_en));

   localparam read_ways = 4+(2*stall_counters);

   
   wire [0:128*stall_counters-1] s1_sc_premux;
   
   genvar 		       i;
   generate
      for(i=0; i< stall_counters; i=i+1)
	begin : gen1
	   wire [0:63] xcnt;
	   wire [0:63] scnt;
	   base_vlat_en#(.width(64)) ixact_cnt(.clk(clk),.reset(reset),.din(xcnt+64'd1),.q(xcnt),.enable(s1_xc_en[i]));
	   base_vlat_en#(.width(64)) istal_cnt(.clk(clk),.reset(reset),.din(scnt+64'd1),.q(scnt),.enable(s1_sc_en[i]));
	   assign s1_sc_premux[(i*128):((i+1)*128)-1] = {xcnt,scnt};
	end
   endgenerate
   
   
   wire [0:31] 			     t1_s1_time;  // time of initial mmio
   base_mem#(.addr_width(tag_width),.width(32)) istart_time_mem
     (.clk(clk),
      .wa(i_st_tag),.we(i_st_v),.wd(i_st_ts),
      .ra(i_s1_tag),.re(i_s1_v),.rd(t1_s1_time)
      );

   wire [0:31] 			     t1_ed_time; // time of tag assignement
   base_mem#(.addr_width(tag_width),.width(32)) it1_time_mem
     (.clk(clk),
      .wa(i_st_tag),.we(i_st_v),.wd(i_st_ts),
      .ra(i_ed_tag),.re(i_ed_v),.rd(t1_ed_time)
      );

   wire 			     t1_st_v, t1_s1_v, t1_ed_v;
   wire 			     t1_ed_rnw;
   wire [0:31] 			     t1_st_ts, t1_time;
   base_vlat#(.width(1+32+1+32+2)) s1_rsp_lat(.clk(clk),.reset(reset),.din({i_st_v, i_st_ts, i_s1_v, i_time, i_ed_rnw,i_ed_v}),.q({t1_st_v, t1_st_ts, t1_s1_v, t1_time, t1_ed_rnw, t1_ed_v}));
   wire [0:31] 			     t1_lat1 = t1_time - t1_st_ts;       // time from rrin to tag assignment
   wire [0:31] 			     t1_lat2 = t1_time - t1_s1_time;     // time from rrin to sending to texan
   wire [0:31] 			     t1_lat3 = t1_time - t1_ed_time;     // time from rrin to posting result

   wire 			     t2_st_v;
   wire 			     t2_ed_v;
   wire [0:31] 			     t2_lat1,t2_lat2, t2_lat3;
   wire 			     t2_ed_rnw;
   base_vlat#(.width(4+32*3)) it2_rsp_lat(.clk(clk),.reset(reset),.din({t1_st_v, t1_s1_v, t1_ed_v, t1_ed_rnw, t1_lat1, t1_lat2, t1_lat3}),.q({t2_st_v, t2_s1_v, t2_ed_v,t2_ed_rnw,t2_lat1,t2_lat2,t2_lat3}));

   wire 			     t2_ed_rd_act = t2_ed_v & t2_ed_rnw;
   wire 			     t2_ed_wr_act = t2_ed_v & ~t2_ed_rnw;

   wire [0:63] 			     accum_rw_lat1, accum_rw_lat2, accum_rd_lat3, accum_wr_lat3, accum_t1_cnt, accum_t2_cnt, accum_rd_cnt, accum_wr_cnt;


   base_vlat_en#(.width(64)) iaccum_rw_lat1(.clk(clk),.reset(reset),.din(accum_rw_lat1+t2_lat1),.q(accum_rw_lat1),.enable(t2_st_v));
   base_vlat_en#(.width(64)) iaccum_rw_lat2(.clk(clk),.reset(reset),.din(accum_rw_lat2+t2_lat2),.q(accum_rw_lat2),.enable(t2_s1_v));
   base_vlat_en#(.width(64)) iaccum_rd_lat3(.clk(clk),.reset(reset),.din(accum_rd_lat3+t2_lat3),.q(accum_rd_lat3),.enable(t2_ed_rd_act));
   base_vlat_en#(.width(64)) iaccum_wr_lat3(.clk(clk),.reset(reset),.din(accum_wr_lat3+t2_lat3),.q(accum_wr_lat3),.enable(t2_ed_wr_act));

   base_vlat_en#(.width(64)) iaccum_t1_cnt(.clk(clk),.reset(reset),.din(accum_t1_cnt+1),        .q(accum_t1_cnt),.enable(t2_st_v));
   base_vlat_en#(.width(64)) iaccum_t2_cnt(.clk(clk),.reset(reset),.din(accum_t2_cnt+1),        .q(accum_t2_cnt),.enable(t2_s1_v));
   base_vlat_en#(.width(64)) iaccum_rd_cnt(.clk(clk),.reset(reset),.din(accum_rd_cnt+1),        .q(accum_rd_cnt),.enable(t2_ed_rd_act));
   base_vlat_en#(.width(64)) iaccum_wr_cnt(.clk(clk),.reset(reset),.din(accum_wr_cnt+1),        .q(accum_wr_cnt),.enable(t2_ed_wr_act));
   

   localparam mux_ways = 8+(2*stall_counters);
   localparam lcl_addr_width = $clog2(mux_ways)+1;
   
   wire [0:lcl_addr_width-1] s1_rd_ra;
   wire 	       s1_rd_v, s1_rd_r;
   wire [0:63] 			s1_rd;
   base_emux#(.width(64),.ways(mux_ways)) is1_dmux
     (.sel(s1_rd_ra[0:lcl_addr_width-2]),
      .din({
	    accum_rw_lat1,
	    accum_rw_lat2,
	    accum_rd_lat3,
	    accum_wr_lat3,
	    accum_t1_cnt,
	    accum_t2_cnt,
	    accum_rd_cnt,
	    accum_wr_cnt,
	    s1_sc_premux}),.dout(s1_rd));
   
   wire 	       s2_rd_v, s2_rd_r;
   wire [0:63] 	       s2_rd_d;
   base_alatch#(.width(64)) is2_dlat(.clk(clk),.reset(reset),.i_v(s1_rd_v),.i_r(s1_rd_r),.i_d(s1_rd),.o_v(s2_rd_v),.o_r(s2_rd_r),.o_d(s2_rd_d));
   

   wire 		       pm_cfg;  // this is config space
   wire 		       pm_rnw;  // read not write
   wire 		       pm_vld;  // valid 
   wire 		       pm_dw;   // double word
   wire [0:64] 		       pm_data;
   wire [0:24]  	       pm_addr;
   wire [0:4+24+64-1]          pm_mmiobus;
   assign {pm_vld,pm_cfg,pm_rnw,pm_dw,pm_addr,pm_data} = i_mmiobus;
   assign pm_mmiobus = {pm_vld,pm_cfg,pm_rnw,pm_dw,pm_addr[0:23],pm_data[0:63]};  
   ktms_mmrd_dec#(.lcladdr_width(lcl_addr_width),.addr(mmioaddr),.mmiobus_width(mmiobus_width-2)) immrd_dec
     (.clk(clk),.reset(reset),.i_mmiobus(pm_mmiobus),
      .o_rd_r(s1_rd_r),.o_rd_v(s1_rd_v),.o_rd_addr(s1_rd_ra),
      .i_rd_r(s2_rd_r),.i_rd_v(s2_rd_v),.i_rd_d(s2_rd_d),
      .o_mmio_rd_v(o_mmio_ack),.o_mmio_rd_d(o_mmio_data)
      );
   
endmodule // ktms_afu_stallcount

    
  
