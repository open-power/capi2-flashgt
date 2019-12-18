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
module capi_res_mgr#
  (
   parameter parity = 0,
   parameter id_width = 4,
   parameter num_res = 2 ** (id_width-parity) ,
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
    output 		  o_free_err,
    output [0:id_width-parity] o_cnt,
    output              o_perror    
    );

   
   wire [0:num_res-1] 	  busy_id_dec;
   wire [0:num_res-1] 	  free_id_dec;


   wire 		  s1_free_v;
   wire [0:id_width-1] 	  s1_free_id;
   wire 		  s1_free_ok;
   
   base_vlat#(.width(1)) is1_free_vlat(.clk(clk),.reset(reset),.din(i_free_v),.q(s1_free_v));
   base_vlat#(.width(id_width)) is1_free_dlat(.clk(clk),.reset(1'b0),.din(i_free_id),.q(s1_free_id));

   wire 		  s2_free_v, s2_free_ok;
   wire [0:id_width-1] 	  s2_free_id;
   
   base_vlat#(.width(1)) is2_free_vlat(.clk(clk),.reset(reset),.din(s1_free_v),.q(s2_free_v));
   base_vlat#(.width(id_width+1)) is2_free_dlat(.clk(clk),.reset(1'b0),.din({s1_free_id,s1_free_ok}),.q({s2_free_id,s2_free_ok}));


   

   assign o_free_err = s2_free_v & ~s2_free_ok;
   wire 		  s2_free_act = s2_free_v & s2_free_ok;

   // track  how many issued for debug
   base_incdec#(.width(id_width+1-parity)) icnt(.clk(clk),.reset(reset),.i_inc(o_avail_v & o_avail_r),.i_dec(s2_free_act),.o_cnt(o_cnt),.o_zero());
   
   wire 		  queue_init_v, queue_init_r;
   wire [0:id_width-1] 	 queue_init_id;
   base_initsm#(.COUNT(num_res), .LOG_COUNT(id_width-parity)) ism(.clk(clk),.reset(reset),.dout_r(queue_init_r),.dout_v(queue_init_v),.dout_d(queue_init_id[0:id_width-1-parity]));


   if (parity == 1) 
      capi_parity_gen#(.dwidth(id_width-1),.width(1)) queue_init_id_pgen(.i_d(queue_init_id[0:id_width-2]),.o_d(queue_init_id[id_width-1]));

   wire 		 s2_free_r;
   wire 		 s1_v, s1_r;
   wire [0:id_width-1] 	 s1_d;
   base_primux#(.ways(2),.width(id_width)) imux(.i_v({s2_free_act,queue_init_v}),.i_r({s2_free_r,queue_init_r}),.i_d({s2_free_id,queue_init_id}),
						.o_v(s1_v),.o_r(s1_r),.o_d(s1_d),.o_sel());
   
   wire 		 s2_avail_v, s2_avail_r;
   wire [0:id_width-1] 	 s2_avail_id;
   base_fifo#(.DEPTH(num_res), .LOG_DEPTH(id_width-parity), .width(id_width)) ififo(.clk(clk),.reset(reset),.i_r(s1_r),.i_v(s1_v),.i_d(s1_d),.o_v(s2_avail_v),.o_d(s2_avail_id),.o_r(s2_avail_r)); 
   base_alatch_burp#(.width(id_width)) is2_lat
     (.clk(clk),.reset(reset),
      .i_v(s2_avail_v),.i_r(s2_avail_r),.i_d(s2_avail_id),
      .o_v(o_avail_v),.o_r(o_avail_r),.o_d(o_avail_id)
      );

   wire 		 s3_avail_v;
   wire [0:id_width-1] 	 s3_avail_id;
   base_vlat#(.width(id_width)) is2_avail_dlat(.clk(clk),.reset(1'b0),.din(s2_avail_id),.q(s3_avail_id));
   base_vlat#(.width(1)) is2_avail_vlat(.clk(clk),.reset(reset),.din(s2_avail_v & s2_avail_r),.q(s3_avail_v));

   wire [0:2]            s1_perror ;  
   if (parity == 1)
   begin  					
      capi_parcheck#(.width(id_width-1)) s3_avail_id_pcheck0(.clk(clk),.reset(reset),.i_v(s3_avail_v),.i_d(s3_avail_id[0:id_width-2]),.i_p(s3_avail_id[id_width-1]),.o_error(s1_perror[0]));
      capi_parcheck#(.width(id_width-1)) s1_free_id_pcheck0(.clk(clk),.reset(reset),.i_v(s1_free_v),.i_d(s1_free_id[0:id_width-2]),.i_p(s1_free_id[id_width-1]),.o_error(s1_perror[1]));
      capi_parcheck#(.width(id_width-1)) i_free_id_pcheck0(.clk(clk),.reset(reset),.i_v(i_free_v),.i_d(i_free_id[0:id_width-2]),.i_p(i_free_id[id_width-1]),.o_error(s1_perror[2]));
   end 
   else 
   assign s1_perror = 3'b0;
   wire [0:2] 				hld_perror;
   base_vlat_sr#(.width(3)) iperror_lat(.clk(clk),.reset(reset),.set(s1_perror),.rst(3'd0),.q(hld_perror));
   base_vlat#(.width(1)) iperror_olat(.clk(clk),.reset(reset),.din(| hld_perror),.q(o_perror));
   generate
      if (tag_check   )
	begin :gen_1
	  base_vmem#(.a_width(id_width-parity)) ivmem
	    (.clk(clk),.reset(reset),
	     .i_set_v(s3_avail_v),.i_set_a(s3_avail_id[0:id_width-1-parity]),  
	     .i_rst_v(s1_free_v),         .i_rst_a(s1_free_id[0:id_width-1-parity]),
	     .i_rd_en(i_free_v),         .i_rd_a(i_free_id[0:id_width-1-parity]),
	     .o_rd_d(s1_free_ok)
	     );
	end
      else
	begin : gen_2
	   assign s1_free_ok = 1'b1;
	end
   endgenerate
	   
endmodule // capi_res_mgr
   
