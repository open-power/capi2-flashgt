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
module base_fifo#
  (
   parameter ramstyle="no_rw_check",
   parameter width=1,
   parameter LOG_DEPTH=1,
   parameter DEPTH = 2 ** LOG_DEPTH,
   parameter output_reg = 0
   )
   (
    input clk,
    input reset,
    input i_v,
    input [width-1:0] i_d,
    output 	     i_r,
		     
    output 	     o_v,
    output [width-1:0] o_d,
    input 	      o_r /* only meaningful when doutv=1.  means that dout will be accepted this cycle.  New data may be presented next cycle */
    );
   genvar 	      i;
   generate
      if (DEPTH <= 4)
	begin :gen1
	   wire [0:DEPTH-1] s_v, s_r;
	   wire [0:DEPTH*width-1] s_d;
	   base_alatch#(.width(width)) s0_lat
	     (.clk(clk),.reset(reset),
	      .i_v(i_v),.i_r(i_r),.i_d(i_d),
	      .o_v(s_v[0]),.o_r(s_r[0]),.o_d(s_d[0:width-1])
	      );
	   for(i=0; i<DEPTH-1; i=i+1)
	     begin :gen2
		base_aburp#(.width(width)) s1_lat
		 (.clk(clk),.reset(reset),
		  .i_v(s_v[i+0]),.i_r(s_r[i+0]),.i_d(s_d[(i+0)*width:(i+1)*width-1]),
		  .o_v(s_v[i+1]),.o_r(s_r[i+1]),.o_d(s_d[(i+1)*width:(i+2)*width-1]),
		  .burp_v());
	     end
	   base_alatch#(.width(width)) s2_lat
	     (.clk(clk),.reset(reset),
	      .i_v(s_v[DEPTH-1]),.i_r(s_r[DEPTH-1]),.i_d(s_d[(DEPTH-1)*width:(DEPTH)*width-1]),
	      .o_v(o_v),.o_r(o_r),.o_d(o_d)
	      );
	end
      else
	begin :gen_ram
	   wire s1_v, s1_r;
	   wire [0:width-1] s1_d;
	   
	   
	   wire 	       empty,empty_in;
	   wire        full,full_in;
	   
	   (* ramstyle = ramstyle *) reg [width-1:0]     ram[DEPTH-1:0];
	   reg [width-1:0] dout_int;
	   
	   wire [31:0] onex = 32'h1;
	   wire [LOG_DEPTH-1:0] one = onex[LOG_DEPTH-1:0];
	   
	   wire [31:0] 	depthm1 = DEPTH-1;
	   wire [LOG_DEPTH-1:0] maxptr = depthm1[LOG_DEPTH-1:0];
	   
	   wire 	wr_en;
	   assign wr_en = i_v & ~full;
	   
	   wire 	rd_en;
	   assign rd_en = ~empty & ~(s1_v & ~s1_r);
	   
	   wire 	doutv_in;
	   assign doutv_in = rd_en | (s1_v & ~s1_r);
	   
	   wire [0:LOG_DEPTH-1] din_ptr, din_ptr_in, din_ptr_nxt;
	   wire [0:LOG_DEPTH-1] dout_ptr, dout_ptr_in, dout_ptr_nxt;
	   
	   
	   assign din_ptr_nxt = (din_ptr == maxptr) ?   {LOG_DEPTH{1'b0}} : din_ptr+one;
	   assign dout_ptr_nxt = (dout_ptr == maxptr) ? {LOG_DEPTH{1'b0}} : dout_ptr+one;
	   
	   assign din_ptr_in  = wr_en ? din_ptr_nxt : din_ptr;
	   assign dout_ptr_in = rd_en ? dout_ptr_nxt: dout_ptr;
	   
	   wire 	 ptrs_eq;
	   assign ptrs_eq = (din_ptr_in == dout_ptr_in);
	   
	   assign empty_in = empty ? ~wr_en : (rd_en & ptrs_eq);
	   assign full_in  = full  ? ~rd_en : (wr_en & ptrs_eq);
	   
	   assign i_r = ~full;
	   
	   always@(posedge clk) begin
	      if (wr_en) ram[din_ptr] <= i_d;
	   end
	   
	   always@(posedge clk) begin
	      if (rd_en) dout_int <= ram[dout_ptr];
	   end
	   assign s1_d = dout_int;
	   
	   
	   base_vlat#(.width(1)) ifull(.clk(clk), .reset(reset), .din(full_in), .q(full));
           base_vlat#(.width(1),.rstv(1'b1)) iempty(.clk(clk), .reset(reset), .din(empty_in), .q(empty));
	   base_vlat#(.width(1)) idoutv(.clk(clk), .reset(reset), .din(doutv_in), .q(s1_v));
	   base_vlat#(.width(LOG_DEPTH)) idinptr(.clk(clk), .reset(reset), .din(din_ptr_in), .q(din_ptr));
	   base_vlat#(.width(LOG_DEPTH)) idoutptr(.clk(clk), .reset(reset), .din(dout_ptr_in), .q(dout_ptr));
      
	   if(output_reg)
	     begin :gen_reg
		base_alatch#(.width(width)) i_output_lat(.clk(clk),.reset(reset),.i_v(s1_v),.i_r(s1_r),.i_d(s1_d),.o_v(o_v),.o_r(o_r),.o_d(o_d));
	     end
	   else
	     begin :gen_assign
		assign o_v = s1_v;
		assign s1_r = o_r;
		assign o_d = s1_d;
	     end
	end // block: gen_ram
      
   endgenerate
   
endmodule // base_fifo


   
   
      
     

 
   


   
   


		  
  
