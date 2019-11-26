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
module base_incdec#
  (parameter width=0,
   parameter rstv=0
   )
   (
    input 	       clk,
    input 	       reset,
    input 	       i_inc,
    input 	       i_dec,
    output [0:width-1] o_cnt,
    output 	       o_zero
    );

   wire [0:width-1] cnt_one = {{width-1{1'b0}},1'b1};
   wire [0:width-1] cnt_d;
   wire [0:width-1] cnt_in = ({width{i_inc}} & (cnt_d + cnt_one)) | ({width{i_dec}} & (cnt_d - cnt_one));
   base_vlat_en#(.width(width),.rstv(rstv)) icnt_l(.clk(clk),.reset(reset),.enable(i_inc ^ i_dec),.din(cnt_in),.q(cnt_d));
   assign o_zero = (cnt_d == {width{1'b0}});
   assign o_cnt = cnt_d;
endmodule // base_incdec


		    
  
