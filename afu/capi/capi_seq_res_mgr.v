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
module capi_seq_res_mgr#
  (
   parameter id_width = 4,
   parameter num_res = 2 ** id_width,
   parameter tag_check = 1
   )
   (
    input 		  clk,
    input 		  reset,
    input 		  i_free_v,
    input [0:id_width-1]  i_free_id,
    output 		  o_avail_v,
    output [0:id_width-1] o_avail_id,
    input 		  o_avail_r,
    output 		  o_free_err
    );

   wire [0:id_width-1] 	iptr, optr;
   wire 		iptr_en, optr_en, empty;
   base_vlat_en#(.width(id_width)) iiptr_lat(.clk(clk),.reset(reset),.din(iptr+1'b1),.q(iptr),.enable(iptr_en));
   base_vlat_en#(.width(id_width)) ioptr_lat(.clk(clk),.reset(reset),.din(optr+1'b1),.q(optr),.enable(optr_en));
   base_incdec#(.width(id_width+1),.rstv(num_res)) icnt(.clk(clk),.reset(reset),.i_inc(iptr_en),.i_dec(optr_en),.o_cnt(),.o_zero(empty));
   
   assign o_avail_id = optr;
   assign o_avail_v = ~empty;
   assign optr_en = o_avail_v & o_avail_r;
   assign iptr_en = i_free_v;
   generate
      if(tag_check == 0)
	assign o_free_err = 1'b0;
      else
	begin : gen1
	   wire 		s0_free_err = i_free_v & ~(i_free_id == iptr);
	   base_vlat#(.width(1)) ierr_lat(.clk(clk),.reset(reset),.din(s0_free_err),.q(o_free_err));
	end
   endgenerate
endmodule // gx_res_mgr
   
