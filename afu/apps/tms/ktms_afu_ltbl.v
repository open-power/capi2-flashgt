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
module ktms_afu_ltbl#
  (parameter mmiobus_width = 1,
   parameter mmio_addr = 1,
   parameter idx_width=1,
   parameter portid_width=1,
   parameter port_io_space=4096*4,    // lun tbl not contiguous, spans 32K   
   parameter lunid_width=64,
   parameter lunid_width_w_par = 65,
   parameter aux_width=1
  )
   (input clk,
    input 		      reset,
    input [0:mmiobus_width-1] i_mmiobus,
    output 		      i_r,
    input 		      i_v,
    input 		      i_vrh, // read from table, else choose input
    input [0:portid_width-1]  i_port,
    input [0:idx_width-1]     i_idx,
    input [0:aux_width-1]     i_aux,
    input [0:lunid_width_w_par-1]   i_lunid,
    input 		      o_r,
    output 		      o_v,
    output [0:lunid_width_w_par-1]  o_lunid,
    output [0:aux_width-1]    o_aux,
    output 		      o_mmio_rd_v,
    output [0:63] 	      o_mmio_rd_d,
    output 		      o_mmio_wr_v

    );

   localparam port_addr_width = ($clog2(port_io_space))-3;
   localparam mmio_addr_width = port_addr_width + portid_width;
   localparam lcl_addr_width = idx_width+portid_width;
   localparam unused_addr_width = mmio_addr_width - lcl_addr_width;
   
   			       
   wire [0:lunid_width_w_par-1] 		     s1_wr_d;
   wire 		     s1_wr_v, s1_wr_r;

   assign o_mmio_wr_v = s1_wr_v ;

   wire [0:mmio_addr_width]  s1_wr_lcladdr;
   wire [0:mmio_addr_width]  s1_rd_lcladdr;

   wire 		       ltbl_cfg;  // this is config space
   wire 		       ltbl_rnw;  // read not write
   wire 		       ltbl_vld;  // valid 
   wire 		       ltbl_dw;   // double word
   wire [0:64] 		       ltbl_data; 
   wire [0:24]  	       ltbl_addr;
   wire [0:4+24+64-1]             ltbl_mmiobus;
   assign {ltbl_vld,ltbl_cfg,ltbl_rnw,ltbl_dw,ltbl_addr,ltbl_data} = i_mmiobus; 
   assign ltbl_mmiobus = {ltbl_vld,ltbl_cfg,ltbl_rnw,ltbl_dw,ltbl_addr[0:23],ltbl_data[0:63]}; 
   ktms_mmwr_dec#(.mmiobus_width(mmiobus_width-2),.addr(mmio_addr),.lcladdr_width(mmio_addr_width+1)) immwr_dec 
     (.clk(clk),.reset(reset), 
      .i_mmiobus(ltbl_mmiobus), 
      .o_wr_r(s1_wr_r),.o_wr_v(s1_wr_v),.o_wr_addr(s1_wr_lcladdr),.o_wr_d(s1_wr_d[0:lunid_width_w_par-2])
      );
    
   capi_parity_gen#(.dwidth(64),.width(1)) s1_wr_d_pgen(.i_d(s1_wr_d[0:lunid_width_w_par-2]),.o_d(s1_wr_d[lunid_width_w_par-1]));

   assign s1_wr_r = 1'b1;

// lun table mmio map  use address bits 10 and bits bits 13  
// port 0  0x400   psl address 0x000100   
// port 1  0x500   psl address 0x000140
// port 2  0x800   psl address 0x000200
// port 3  0x900   psl address 0x000240

   
//   wire [0:portid_width-1]   s1_wr_addr_port      = s1_wr_lcladdr[0:portid_width-1];  // original 
     wire [0:portid_width-1]   s1_wr_addr_port      = {s1_wr_lcladdr[0],s1_wr_lcladdr[3]};      // new mmio map for adding ports 2 and 3
   wire [0:idx_width-1]      s1_wr_addr_idx       = s1_wr_lcladdr[mmio_addr_width-idx_width:mmio_addr_width-1]; 

   wire [0:portid_width-1]   s1_rd_addr_port      = s1_rd_lcladdr[0:portid_width-1];  // original 
//   wire [0:portid_width-1]   s1_rd_addr_port      =  {s1_wr_lcladdr[0],s1_wr_lcladdr[3]};   // new mmio map for adding ports 2 and 3
   wire [0:idx_width-1]      s1_rd_addr_idx       = s1_rd_lcladdr[mmio_addr_width-idx_width:mmio_addr_width-1];


   wire 		     s1_wr_idx_err;
   wire 		     s1_rd_idx_err;

// further decode lun table into 2 separate 8k by checkinking to make sure bit 01 is either a 01 or 10 spaces. each port has 256 entries non contiguous so bit 4 is always a 0. 

   assign s1_wr_idx_err = (s1_wr_lcladdr[0]~^s1_wr_lcladdr[1]) | (s1_wr_lcladdr[4]);
   assign s1_rd_idx_err = (s1_rd_lcladdr[0]~^s1_rd_lcladdr[1]) | (s1_rd_lcladdr[4]);

//   generate
//      if (unused_addr_width > 0)
//	begin : gen1
//	   wire [0:unused_addr_width-1] s1_wr_addr_unused = s1_wr_lcladdr[portid_width:portid_width+unused_addr_width-1];
//	   assign s1_wr_idx_err = | s1_wr_addr_unused;
//	   wire [0:unused_addr_width-1] s1_rd_addr_unused = s1_rd_lcladdr[portid_width:portid_width+unused_addr_width-1];
//	   assign s1_rd_idx_err = | s1_rd_addr_unused;
//	end
  //    else
//	begin : gen2
//	   assign s1_wr_idx_err = 1'b0;
//	   assign s1_rd_idx_err = 1'b0;
//	end
  // endgenerate

   wire 			s1_v, s1_r, s1_vrh;  
//   wire 			s1_we = s1_wr_v & s1_wr_r & ~s1_wr_idx_err;  // orig
   wire 			s1_we = s1_wr_v & s1_wr_r & ~s1_wr_idx_err;
   wire [0:lcl_addr_width-1] 	s1_wa = {s1_wr_addr_port,s1_wr_addr_idx};
   wire [0:lunid_width_w_par-1] 	s1_lunid_a;
   wire [0:aux_width-1] 	s1_aux;
   base_alatch#(.width(aux_width+lunid_width_w_par+1)) is1_lat(.clk(clk),.reset(reset),.i_v(i_v),.i_r(i_r),.i_d({i_aux,i_lunid,i_vrh}),.o_v(s1_v),.o_r(s1_r),.o_d({s1_aux,s1_lunid_a,s1_vrh}));

   wire 			s0_re = s1_r | ~s1_v;
   wire [0:lcl_addr_width-1] 	s0_ra = {i_port,i_idx};
   wire [0:lunid_width_w_par-1] 	s1_lunid_b;
   base_mem#(.width(65),.addr_width(lcl_addr_width)) imem0(.clk(clk),.we(s1_we),.wa(s1_wa),.wd(s1_wr_d),.re(s0_re),.ra(s0_ra),.rd(s1_lunid_b));
   wire [0:lunid_width_w_par-1] 	s1_lunid = s1_vrh ? s1_lunid_b : s1_lunid_a;

   base_alatch#(.width(aux_width+lunid_width_w_par)) is2_lat(.clk(clk),.reset(reset),.i_v(s1_v),.i_r(s1_r),.i_d({s1_aux,s1_lunid}),.o_v(o_v),.o_r(o_r),.o_d({o_aux,o_lunid}));


   wire 			s1_rd_v, s1_rd_r;
   wire 			s1_rd_en;
   wire 			s2_rd_idx_err;
   wire 			s2_rd_v, s2_rd_r;
   wire [0:63] 			s2_rd_d;
   base_alatch_oe#(.width(1)) is2_rd_lat(.clk(clk),.reset(reset),.i_v(s1_rd_v & ~s1_rd_idx_err),.i_r(s1_rd_r),.i_d(s1_rd_idx_err),.o_v(s2_rd_v),.o_r(s2_rd_r),.o_d(s2_rd_idx_err),.o_en(s1_rd_en));

   wire [0:lcl_addr_width-1] 	s1_rd_a = {s1_rd_addr_port,s1_rd_addr_idx};
   base_mem#(.width(64),.addr_width(lcl_addr_width)) imem1(.clk(clk),.we(s1_we),.wa(s1_wa),.wd(s1_wr_d[0:lunid_width_w_par-2]),.re(s1_rd_en),.ra(s1_rd_a),.rd(s2_rd_d));

   wire [0:63] 			s2_rd_qd = s2_rd_idx_err ? 64'd0 : ~s2_rd_d;
   ktms_mmrd_dec#(.mmiobus_width(mmiobus_width-2),.addr(mmio_addr),.lcladdr_width(mmio_addr_width+1)) immrd_dec
     (.clk(clk),.reset(reset),
      .i_mmiobus(ltbl_mmiobus),
      .o_rd_v(s1_rd_v),.o_rd_r(s1_rd_r),.o_rd_addr(s1_rd_lcladdr),
      .i_rd_v(s2_rd_v),.i_rd_r(s2_rd_r),.i_rd_d(~s2_rd_qd),
      .o_mmio_rd_v(o_mmio_rd_v),.o_mmio_rd_d(o_mmio_rd_d)
      );
	     
endmodule // ktms_afu_ltbl
	     
    
