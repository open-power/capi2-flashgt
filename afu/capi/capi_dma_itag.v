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


`timescale 1 ns / 10 ps


module capi_dma_itag#
  (// afu/psl   interface parameters
   parameter ea_width = 65,
   parameter utag_width = 10
    )
   (
   
    input                       reset,
    input                       clk,

   // Accelerator DMA Interface
    output 				d0h_dvalid, 
    output [0:9] 			d0h_req_utag, 
    output [0:8] 			d0h_req_itag, 
    output [0:2] 			d0h_dtype,  
    output [0:9] 			d0h_dsize, 
    output [0:5] 			d0h_datomic_op, 
    output       			d0h_datomic_le, 
    input       			hd0_sent_utag_valid, 
    input [0:9]      			hd0_sent_utag, 
    input [0:2]      			hd0_sent_utag_sts, 

    output                              o_s0_sent_utag_valid,
    output [0:9]      			o_s0_sent_utag, 
    output [0:2]      			o_s0_sent_utag_sts, 


    input 				r2_tag_plus_ok_v, 
    input [0:7] 			r2_rtag_plus,  
    input [0:8] 			r2_ritag_plus, 
    input        			r2_ritagpar_plus, 


    input  				i_v, 
    input [0:7] 			i_ctag, 
    input [0:11]			i_size, 
    input [0:12]                        i_cmd,
    output                              o_dvalid,
    output [0:7]                        o_dwad, 

    output                              itag_dma_perror,
    output [0:3]                        o_tag_error,
    output                              o_rcb_req_sent,
    input                               i_usource_v,
    input [0:7]                         i_usource_ctag,
    input [0:4]                         i_unit,
    input                               i_error_status_hld,
    input                               i_drop_wrt_pckts,
    output                              o_gated_tag_val, 
    input                               i_gated_tag_taken,
    output [0:9]                        o_gated_tag          
   );

    reg [0:7] write_active_d, write_active_q;
    reg [0:7] read_active_d, read_active_q;
    reg       rdnwrt_pri_q,rdnwrt_pri_d;
    reg       s1_dvalid_q,s1_dvalid_d;
    reg       s2_dvalid_q,s2_dvalid_d;
    reg       s3_dvalid_q,s3_dvalid_d;
    reg       s4_dvalid_q,s4_dvalid_d;
    reg [0:1] num_cycles_xferd_q,num_cycles_xferd_d; 
    reg       s0_sent_utag_valid_q,s0_sent_utag_valid_d;     
    reg        itag_write_taken_q,itag_write_taken_d; 
    reg        itag_read_taken_q,itag_read_taken_d; 
    reg        s3_write_val_q,s3_write_val_d;      
    reg        s3_read_val_q,s3_read_val_d; 
    reg        r2_tag_plus_v_q, r2_tag_plus_v_d;   
    reg        r3_utag_v_q, r3_utag_v_d;   
 
   always @(posedge clk or posedge reset)
     begin
       if ( reset == 1'b1 )
       begin
         write_active_q <= 8'h00;
         read_active_q <= 8'h00;
         rdnwrt_pri_q <= 1'b0;
         s1_dvalid_q <= 1'b0;
         s2_dvalid_q <= 1'b0;
         s3_dvalid_q <= 1'b0;
         s4_dvalid_q <= 1'b0;
         num_cycles_xferd_q <= 2'b00; 
         s0_sent_utag_valid_q <= 1'b0;     
         itag_write_taken_q <=1'b0; 
         itag_read_taken_q <= 1'b0; 
         s3_write_val_q <= 1'b0; 
         s3_read_val_q <= 1'b0; 
         r2_tag_plus_v_q <= 1'b0;
       end
       else
       begin
         write_active_q <= write_active_d;
         read_active_q <= read_active_d;
         rdnwrt_pri_q <= rdnwrt_pri_d;
         s1_dvalid_q <= s1_dvalid_d;      
         s2_dvalid_q <= s2_dvalid_d;      
         s3_dvalid_q <= s3_dvalid_d;      
         s4_dvalid_q <= s4_dvalid_d;      
         num_cycles_xferd_q <= num_cycles_xferd_d;
         s0_sent_utag_valid_q <= s0_sent_utag_valid_d;      
         itag_write_taken_q <= itag_write_taken_d; 
         itag_read_taken_q <= itag_read_taken_d; 
         s3_write_val_q <= s3_write_val_d;
         s3_read_val_q <= s3_read_val_d;
         r2_tag_plus_v_q <= r2_tag_plus_v_d;
       end
     end

   reg [0:9]  s0_dsize_q,s0_dsize_d;
   reg [0:9]  s0_req_utag_q,s0_req_utag_d;      
   reg [0:8]  s0_req_itag_q,s0_req_itag_d;      
   reg        s0_req_itagpar_q,s0_req_itagpar_d;      
   reg [0:9]  s0_sent_utag_q,s0_sent_utag_d; 
   reg [0:2]  s0_sent_utag_sts_q,s0_sent_utag_sts_d; 
   reg [0:2]  s2_dtype_q,s2_dtype_d;
   reg [0:2]  s3_dtype_q,s3_dtype_d;
   reg [0:2]  s4_dtype_q,s4_dtype_d;
   reg [0:9]  s1_dsize_q,s1_dsize_d;
   reg [0:4]  s1_usource_q,s1_usource_d;
   reg [0:9]  s2_dsize_q,s2_dsize_d;
   reg [0:9]  s3_dsize_q,s3_dsize_d;
   reg [0:9]  s4_dsize_q,s4_dsize_d;
   reg [0:9]  s1_req_utag_q,s1_req_utag_d;      
   reg [0:8]  s1_req_itag_q,s1_req_itag_d;      
   reg        s1_req_itagpar_q,s1_req_itagpar_d;      
   reg [0:9]  s2_req_utag_q,s2_req_utag_d;      
   reg [0:8]  s2_req_itag_q,s2_req_itag_d;      
   reg        s2_req_itagpar_q,s2_req_itagpar_d;      
   reg [0:9]  s3_req_utag_q,s3_req_utag_d;      
   reg [0:8]  s3_req_itag_q,s3_req_itag_d;      
   reg        s3_req_itagpar_q,s3_req_itagpar_d;      
   reg [0:9]  s4_req_utag_q,s4_req_utag_d;      
   reg [0:8]  s4_req_itag_q,s4_req_itag_d;      
   reg        s4_req_itagpar_q,s4_req_itagpar_d;      


   reg [0:9] write_active0_utag_q,write_active0_utag_d;
   reg [0:9] write_active1_utag_q,write_active1_utag_d;
   reg [0:9] write_active2_utag_q,write_active2_utag_d;
   reg [0:9] write_active3_utag_q,write_active3_utag_d;
   reg [0:9] write_active4_utag_q,write_active4_utag_d;
   reg [0:9] write_active5_utag_q,write_active5_utag_d;
   reg [0:9] write_active6_utag_q,write_active6_utag_d;
   reg [0:9] write_active7_utag_q,write_active7_utag_d;
   reg [0:9] read_active0_utag_q,read_active0_utag_d;
   reg [0:9] read_active1_utag_q,read_active1_utag_d;
   reg [0:9] read_active2_utag_q,read_active2_utag_d;
   reg [0:9] read_active3_utag_q,read_active3_utag_d;
   reg [0:9] read_active4_utag_q,read_active4_utag_d;
   reg [0:9] read_active5_utag_q,read_active5_utag_d;
   reg [0:9] read_active6_utag_q,read_active6_utag_d;
   reg [0:9] read_active7_utag_q,read_active7_utag_d;
   reg       s0_dwad_inc_d,s0_dwad_inc_q;
   reg [0:7] s1_dwad_d,s1_dwad_q;
   reg [0:8] r2_rditag_plus_q, r2_rditag_plus_d;
   reg       r2_rditagpar_plus_q, r2_rditagpar_plus_d;
   reg [0:7] r2_rtag_plus_q, r2_rtag_plus_d;
   reg [0:8] s1_write_utag_q, s1_write_utag_d;
   reg [0:2]  s1_dtype_q,s1_dtype_d;

   always @(posedge clk)
     begin
       s1_dtype_q <= s1_dtype_d;      
       s0_sent_utag_q <= s0_sent_utag_d; 
       s0_sent_utag_sts_q <= s0_sent_utag_sts_d;
       s0_req_utag_q <= s0_req_utag_d;
       s0_req_itag_q <= s0_req_itag_d; 
       s0_req_itagpar_q <= s0_req_itagpar_d; 
       s0_dsize_q <= s0_dsize_d;
       s2_dtype_q <= s2_dtype_d;      
       s3_dtype_q <= s3_dtype_d;      
       s4_dtype_q <= s4_dtype_d;      
       s1_dsize_q <= s1_dsize_d;
       s1_usource_q <= s1_usource_d;
       s2_dsize_q <= s2_dsize_d;
       s3_dsize_q <= s3_dsize_d;
       s4_dsize_q <= s4_dsize_d;
       s1_req_utag_q <= s1_req_utag_d;      
       s1_req_itag_q <= s1_req_itag_d;      
       s1_req_itagpar_q <= s1_req_itagpar_d; 
       s2_req_utag_q <= s2_req_utag_d;      
       s2_req_itag_q <= s2_req_itag_d;      
       s2_req_itagpar_q <= s2_req_itagpar_d; 
       s3_req_utag_q <= s3_req_utag_d;      
       s3_req_itag_q <= s3_req_itag_d;      
       s3_req_itagpar_q <= s3_req_itagpar_d; 
       s4_req_utag_q <= s4_req_utag_d;      
       s4_req_itag_q <= s4_req_itag_d;      
       s4_req_itagpar_q <= s4_req_itagpar_d; 
       write_active0_utag_q <= write_active0_utag_d;
       write_active1_utag_q <= write_active1_utag_d;
       write_active2_utag_q <= write_active2_utag_d;
       write_active3_utag_q <= write_active3_utag_d;
       write_active4_utag_q <= write_active4_utag_d;
       write_active5_utag_q <= write_active5_utag_d;
       write_active6_utag_q <= write_active6_utag_d;
       write_active7_utag_q <= write_active7_utag_d;
       read_active0_utag_q <= read_active0_utag_d;
       read_active1_utag_q <= read_active1_utag_d;
       read_active2_utag_q <= read_active2_utag_d;
       read_active3_utag_q <= read_active3_utag_d;
       read_active4_utag_q <= read_active4_utag_d;
       read_active5_utag_q <= read_active5_utag_d;
       read_active6_utag_q <= read_active6_utag_d;
       read_active7_utag_q <= read_active7_utag_d;
       s0_dwad_inc_q <= s0_dwad_inc_d;
       s1_dwad_q <= s1_dwad_d;
       r2_rditag_plus_q <= r2_rditag_plus_d;
       r2_rditagpar_plus_q <= r2_rditagpar_plus_d;
       r2_rtag_plus_q <= r2_rtag_plus_d;
       s1_write_utag_q <=  s1_write_utag_d;
     end


    
  reg [0:9] o_size;
  reg [0:12] o_cmd;
  wire [0:9] s2_size;
  wire [0:12] s2_cmd;
  reg [0:4] o_usource;
    

   assign itag_dma_perror = 1'b0;

   reg [0:4] usource_mem[0:255];

   always @(posedge clk)   
     {o_usource} <= usource_mem[r2_rtag_plus];
  
   always @(posedge clk)
     if (i_usource_v)
       usource_mem[i_usource_ctag] <= {i_unit};




   reg [12+13-1:0] cmd_mem[0:255];

   always @(posedge clk)   
     {o_size,o_cmd} <= cmd_mem[r2_rtag_plus];
  
   always @(posedge clk)
     if (i_v)
       cmd_mem[i_ctag] <= {i_size,i_cmd};

  wire s2_write_val;
  wire s2_read_val;
  wire [0:9] s2_write_size;
  wire [0:12] s2_write_cmd;
  wire [0:9] s2_read_size;
  wire [0:12] s2_read_cmd;
  wire [0:1] num_cycles = |(o_size[3:9]) + o_size[2] + 2*o_size[1] + 4*o_size[0] - 1'b1;
  wire [0:1] s2_num_cycles;
  wire [0:8] s2_write_rditag;
  wire       s2_write_rditagpar;
  wire [0:9] s2_write_utag;
  wire [0:8] s2_read_rditag;
  wire       s2_read_rditagpar;
  wire [0:9] s2_read_utag;
  reg itag_write_valid;
  reg itag_read_valid;



  wire write_sent_utag_v = hd0_sent_utag_valid & hd0_sent_utag[0];
  wire [0:8] write_sent_utag = hd0_sent_utag[1:utag_width-1];
  wire [0:8] write_utag;
  wire       r1_utag_outst;
  wire       s1_utag_outst;
  wire       s4_write_dvalid = s4_dvalid_q & s4_req_utag_q[0] & (s4_dtype_q == 3'd1);  // only check first cycle of dma write 
  

// check for valid write utag 

   base_vmem#(.a_width(utag_width-1),.rports(2)) utag_vmem_plus  
     (.clk(clk),.reset(reset),
      .i_set_v(s4_write_dvalid),.i_set_a(s4_req_utag_q[1:9]),
      .i_rst_v(write_sent_utag_v),.i_rst_a(write_sent_utag),
      .i_rd_en(2'b11),.i_rd_a({write_sent_utag,s4_req_utag_q[1:9]}),.o_rd_d({r1_utag_outst,s1_utag_outst})
      );

   wire r1_write_sent_utag_v ;
   wire s1_write_sent_utag_v ;

   base_vlat#(.width(2)) utag_d1 (.clk(clk),.reset(reset),.din({write_sent_utag_v,s4_write_dvalid}),.q({r1_write_sent_utag_v,s1_write_sent_utag_v}));

   wire write_sent_utag_error = r1_write_sent_utag_v & ~r1_utag_outst;
   wire write_dma_utag_error = s1_write_sent_utag_v & s1_utag_outst;

   
// check for valid itag 
   
  wire       s1_itag_outst;
  wire       r1_itag_outst;
  wire       s4_itag_valid = s4_dvalid_q & ((s4_dtype_q == 3'd0) | (s4_dtype_q == 3'd1)) ;
  wire       r2_itag_valid = r2_tag_plus_ok_v & ((r2_rtag_plus[0:1] == 2'b10) | (r2_rtag_plus[0:1] == 2'b01)) ;

   base_vmem#(.a_width(9),.rports(2)) itag_vmem_plus 
     (.clk(clk),.reset(reset),
      .i_set_v(r2_itag_valid),.i_set_a(r2_ritag_plus),
      .i_rst_v(s4_itag_valid),.i_rst_a(s4_req_itag_q),
      .i_rd_en(2'b11),.i_rd_a({r2_ritag_plus,s4_req_itag_q}),.o_rd_d({r1_itag_outst,s1_itag_outst})
      );

   wire r2_tag_plus_v ;
   wire s2_tag_plus_v ;

   base_vlat#(.width(2)) itag_d1 (.clk(clk),.reset(reset),.din({r2_tag_plus_ok_v,s4_itag_valid}),.q({r2_tag_plus_v,s2_tag_plus_v}));

   wire itag_receive_error = (r2_tag_plus_v & r1_itag_outst & ((r2_rtag_plus_q[0:1] == 2'b10) | (r2_rtag_plus_q[0:1] == 2'b01)) & ~i_drop_wrt_pckts) ;
   wire itag_send_error = s2_tag_plus_v & ~s1_itag_outst;
   wire [0:3] tag_error;
   wire [0:3] tag_error_in = tag_error | {write_sent_utag_error,write_dma_utag_error,itag_receive_error,itag_send_error};

   base_vlat#(.width(4)) tag_error_lat(.clk(clk),.reset(reset),.din(tag_error_in),.q(tag_error));

   assign o_tag_error = tag_error;
   
   reg write_active;
   reg read_active;
   reg [0:1] num_cycles_left;
   wire write_complete = write_active && (num_cycles_left == 2'b00);
   wire [0:5] s2_rtag_plus;
   wire write_fifo_full;
   wire read_fifo_full;
   wire [6:0] write_fifo_used;
   wire [6:0] read_fifo_used;
   wire [4:0] rd_usource;
   wire [4:0] wrt_usource;

   nvme_fifo#(
              .width(9+1+10+10+13+2+6+5), 
              .words(64),
              .almost_full_thresh(6)
              ) itag_write_fifo
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        itag_write_valid ),
      .din(         {r2_rditag_plus_q,r2_rditagpar_plus_q,1'b0,s1_write_utag_q,o_size,o_cmd,num_cycles,r2_rtag_plus_q[2:7],o_usource} ),
      .dval(        s2_write_val ), 
      .pop(         write_complete),
      .dout(        {s2_write_rditag,s2_write_rditagpar,s2_write_utag,s2_write_size,s2_write_cmd,s2_num_cycles,s2_rtag_plus,wrt_usource} ),
      .full(write_fifo_full         ), 
      .almost_full( ), 
      .used(write_fifo_used));

   
   nvme_fifo#(
              .width(9+1+10+10+13+5), 
              .words(64),
              .almost_full_thresh(6)
              ) itag_read_fifo
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        itag_read_valid ),
      .din(         {r2_rditag_plus_q,r2_rditagpar_plus_q,2'b00,r2_rtag_plus_q,o_size,o_cmd,o_usource} ),
      .dval(        s2_read_val ), 
      .pop(         read_active ),
      .dout(        {s2_read_rditag,s2_read_rditagpar,s2_read_utag,s2_read_size,s2_read_cmd,rd_usource} ),
      .full(read_fifo_full        ), 
      .almost_full( ), 
      .used(read_fifo_used));

 reg gate_write_valid;

   nvme_fifo#(
              .width(10), 
              .words(64),
              .almost_full_thresh(6)
              ) gated_wrt_tag
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        write_complete & gate_write_valid), 
      .din(         s2_write_utag ),
      .dval(        o_gated_tag_val ), 
      .pop(         i_gated_tag_taken),
      .dout(        o_gated_tag ),
      .full(        ), 
      .almost_full( ), 
      .used());
   
   reg write_full;
   reg read_full;
   reg write_empty;
   reg read_empty;
   reg [0:7] write_busy ;
   reg [0:7] read_busy ;
   reg [0:7] write_free;
   reg [0:7] read_free;
   reg dec_read_dma;            
   reg dec_write_dma;
   wire write_dma_full; 
   wire read_dma_full; 


   always @*
     begin
       write_full = &(write_active_q);
       read_full  = &(read_active_q);
       write_empty = ~|(write_active_q);
       read_empty  = ~|(read_active_q);
       itag_write_valid = r2_tag_plus_v_q & (r2_rtag_plus_q[0:1] == 2'b10); 
       itag_read_valid = r2_tag_plus_v_q & (r2_rtag_plus_q[0:1] == 2'b01);
       read_active =  rdnwrt_pri_q & s2_read_val & ~read_full & ~itag_read_taken_q;
       dec_read_dma = 1'b0;
       dec_write_dma = 1'b0;
       write_active = ~rdnwrt_pri_q & s2_write_val & ~write_full & ~itag_write_taken_q;
       gate_write_valid = i_drop_wrt_pckts & (s2_write_size[3:9] == 7'b0000000) & ((wrt_usource == 5'b00111) | (wrt_usource == 5'b01000) | (wrt_usource == 5'b01001) | (wrt_usource == 5'b01010));
       s1_dvalid_d = (write_active & ~gate_write_valid) | read_active;
       s2_dvalid_d = s1_dvalid_q; 
       s3_dvalid_d = s2_dvalid_q; 
       s4_dvalid_d = s3_dvalid_q & ~i_error_status_hld;
       num_cycles_xferd_d = num_cycles_xferd_q; 
       num_cycles_left = (s2_num_cycles - num_cycles_xferd_q);
       rdnwrt_pri_d = rdnwrt_pri_q ? (~s2_write_val | write_full) : ~(~s2_read_val | read_full | (write_active & (num_cycles_left != 2'b00)))  ; 
       itag_write_taken_d = write_complete;
       itag_read_taken_d = read_active;
       s1_dtype_d = s1_dtype_q; 
       s2_dtype_d = s1_dtype_q; 
       s3_dtype_d = s2_dtype_q; 
       s4_dtype_d = s3_dtype_q; 
       s1_req_itag_d = rdnwrt_pri_q ? s2_read_rditag : s2_write_rditag;
       s1_req_itagpar_d = rdnwrt_pri_q ? s2_read_rditagpar : s2_write_rditagpar;
       s2_req_itag_d = s1_req_itag_q;
       s2_req_itagpar_d <= s1_req_itagpar_q; 
       s3_req_itag_d = s2_req_itag_q;
       s3_req_itagpar_d <= s2_req_itagpar_q; 
       s4_req_itag_d = s3_req_itag_q;
       s4_req_itagpar_d <= s3_req_itagpar_q; 
       s1_req_utag_d = rdnwrt_pri_q ? s2_read_utag : s2_write_utag;
       s2_req_utag_d = s1_req_utag_q;
       s3_req_utag_d = s2_req_utag_q;
       s4_req_utag_d = s3_req_utag_q;
       s1_dsize_d = rdnwrt_pri_q ? s2_read_size : s2_write_size;
       s1_usource_d = rdnwrt_pri_q ? rd_usource : wrt_usource;
       s2_dsize_d = s1_dsize_q;
       s3_dsize_d = s2_dsize_q;
       s4_dsize_d = s3_dsize_q;
       s3_write_val_d = s2_write_val;
       s3_read_val_d = s2_read_val;
       s0_dwad_inc_d = 1'b0;
       s1_dwad_d = s1_dwad_q;
       r2_tag_plus_v_d = r2_tag_plus_ok_v;
       r2_rditag_plus_d = r2_ritag_plus;
       r2_rditagpar_plus_d = r2_ritagpar_plus;
       r2_rtag_plus_d = r2_rtag_plus;
       s1_write_utag_d = {2'b00,r2_rtag_plus};   // use command tag as utag 


       write_active0_utag_d  = write_active0_utag_q;
       write_active1_utag_d  = write_active1_utag_q;
       write_active2_utag_d  = write_active2_utag_q;
       write_active3_utag_d  = write_active3_utag_q;
       write_active4_utag_d  = write_active4_utag_q;
       write_active5_utag_d  = write_active5_utag_q;
       write_active6_utag_d  = write_active6_utag_q;
       write_active7_utag_d  = write_active7_utag_q;
       read_active0_utag_d   = read_active0_utag_q;
       read_active1_utag_d   = read_active1_utag_q;
       read_active2_utag_d   = read_active2_utag_q;
       read_active3_utag_d   = read_active3_utag_q;
       read_active4_utag_d   = read_active4_utag_q;
       read_active5_utag_d   = read_active5_utag_q;
       read_active6_utag_d   = read_active6_utag_q;
       read_active7_utag_d   = read_active7_utag_q;

       if (write_active)   
       begin
         s1_dtype_d = 3'd1;
         s1_dwad_d = s0_dwad_inc_q ? (s1_dwad_q + 8'h01) : {s2_rtag_plus,2'b00};
         if (num_cycles_left != 2'b00)
         begin
           num_cycles_xferd_d = num_cycles_xferd_q + 2'b01;
           s0_dwad_inc_d = 1'b1;
         end
         else
         begin
           itag_write_taken_d = 1'b1;
           num_cycles_xferd_d = 2'b00;
           s0_dwad_inc_d = 1'b0;
         end
         if (num_cycles_xferd_q != 2'b00)
         begin
           s1_dtype_d = 3'd2;
         end           
       end
       if (read_active)   
       begin
         s1_dtype_d = 3'd0;
       end

       write_active_d = write_active_q;
       read_active_d = read_active_q;
       write_free[0] = ~write_active_q[0];
       write_free[1] = write_active_q[0] & ~write_active_q[1];
       write_free[2] = write_active_q[0] & write_active_q[1] & ~write_active_q[2];
       write_free[3] = write_active_q[0] & write_active_q[1] & write_active_q[2] & ~write_active_q[3];
       write_free[4] = write_active_q[0] & write_active_q[1] & write_active_q[2] & write_active_q[3] & ~write_active_q[4];
       write_free[5] = write_active_q[0] & write_active_q[1] & write_active_q[2] & write_active_q[3] & write_active_q[4] & ~write_active_q[5];
       write_free[6] = write_active_q[0] & write_active_q[1] & write_active_q[2] & write_active_q[3] & write_active_q[4] & write_active_q[5] & ~write_active_q[6];
       write_free[7] = write_active_q[0] & write_active_q[1] & write_active_q[2] & write_active_q[3] & write_active_q[4] & write_active_q[5] & write_active_q[6] & ~write_active_q[7];
       read_free[0] = ~read_active_q[0];
       read_free[1] = read_active_q[0] & ~read_active_q[1];
       read_free[2] = read_active_q[0] & read_active_q[1] & ~read_active_q[2];
       read_free[3] = read_active_q[0] & read_active_q[1] & read_active_q[2] & ~read_active_q[3];
       read_free[4] = read_active_q[0] & read_active_q[1] & read_active_q[2] & read_active_q[3] & ~read_active_q[4];
       read_free[5] = read_active_q[0] & read_active_q[1] & read_active_q[2] & read_active_q[3] & read_active_q[4] & ~read_active_q[5];
       read_free[6] = read_active_q[0] & read_active_q[1] & read_active_q[2] & read_active_q[3] & read_active_q[4] & read_active_q[5] & ~read_active_q[6];
       read_free[7] = read_active_q[0] & read_active_q[1] & read_active_q[2] & read_active_q[3] & read_active_q[4] & read_active_q[5] & read_active_q[6] & ~read_active_q[7];

       if (write_complete) 
       begin
         if (write_free[0])
         begin
           write_active_d[0] = 1'b1;
           write_active0_utag_d = s2_write_utag;
         end
         if (write_free[1])
         begin
           write_active_d[1] = 1'b1;
           write_active1_utag_d = s2_write_utag;
         end
         if (write_free[2])
         begin
           write_active_d[2] = 1'b1;
           write_active2_utag_d = s2_write_utag;
         end
         if (write_free[3])
         begin
           write_active_d[3] = 1'b1;
           write_active3_utag_d = s2_write_utag;
         end
         if (write_free[4])
         begin
           write_active_d[4] = 1'b1;
           write_active4_utag_d = s2_write_utag;
         end
         if (write_free[5])
         begin
           write_active_d[5] = 1'b1;
           write_active5_utag_d = s2_write_utag;
         end
         if (write_free[6])
         begin
           write_active_d[6] = 1'b1;
           write_active6_utag_d = s2_write_utag;
         end
         if (write_free[7])
         begin
           write_active_d[7] = 1'b1;
           write_active7_utag_d = s2_write_utag;
         end
       end
   
       if (read_active) 
       begin
         if (read_free[0])
         begin
           read_active_d[0] = 1'b1;
           read_active0_utag_d = s2_read_utag;
         end 
         if (read_free[1])
         begin
           read_active_d[1] = 1'b1;
           read_active1_utag_d = s2_read_utag;
         end 
         if (read_free[2])
         begin
           read_active_d[2] = 1'b1;
           read_active2_utag_d = s2_read_utag;
         end 
         if (read_free[3])
         begin
           read_active_d[3] = 1'b1;
           read_active3_utag_d = s2_read_utag;
         end 
         if (read_free[4])
         begin
           read_active_d[4] = 1'b1;
           read_active4_utag_d = s2_read_utag;
         end 
         if (read_free[5])
         begin
           read_active_d[5] = 1'b1;
           read_active5_utag_d = s2_read_utag;
         end 
         if (read_free[6])
         begin
           read_active_d[6] = 1'b1;
           read_active6_utag_d = s2_read_utag;
         end 
         if (read_free[7])
         begin
           read_active_d[7] = 1'b1;
           read_active7_utag_d = s2_read_utag;
         end 
       end

       s0_sent_utag_valid_d = hd0_sent_utag_valid; 
       s0_sent_utag_d =	hd0_sent_utag;
       s0_sent_utag_sts_d = hd0_sent_utag_sts; 

       if (s0_sent_utag_valid_q)
       begin
         if (write_active_q[0] & (write_active0_utag_q == s0_sent_utag_q)) 
         begin 
           dec_write_dma = 1'b1;            
           write_active_d[0] = 1'b0;
         end
         if (read_active_q[0] & (read_active0_utag_q == s0_sent_utag_q))
         begin             
           dec_read_dma = 1'b1;            
           read_active_d[0] = 1'b0;
         end
         if (write_active_q[1] & (write_active1_utag_q == s0_sent_utag_q)) 
         begin             
           dec_write_dma = 1'b1;            
           write_active_d[1] = 1'b0;
         end
         if (read_active_q[1] & (read_active1_utag_q == s0_sent_utag_q))
         begin             
           dec_read_dma = 1'b1;            
           read_active_d[1] = 1'b0;
         end
         if (write_active_q[2] & (write_active2_utag_q == s0_sent_utag_q)) 
         begin             
           dec_write_dma = 1'b1;            
           write_active_d[2] = 1'b0;
         end
         if (read_active_q[2] & (read_active2_utag_q == s0_sent_utag_q))
         begin             
           dec_read_dma = 1'b1;            
           read_active_d[2] = 1'b0;
         end
         if (write_active_q[3] & (write_active3_utag_q == s0_sent_utag_q)) 
         begin             
           dec_write_dma = 1'b1;            
           write_active_d[3] = 1'b0;
         end
         if (read_active_q[3] & (read_active3_utag_q == s0_sent_utag_q))
         begin             
           dec_read_dma = 1'b1;            
           read_active_d[3] = 1'b0;
         end
         if (write_active_q[4] & (write_active4_utag_q == s0_sent_utag_q)) 
         begin             
           dec_write_dma = 1'b1;            
           write_active_d[4] = 1'b0;
         end
         if (read_active_q[4] & (read_active4_utag_q == s0_sent_utag_q))
         begin             
           dec_read_dma = 1'b1;            
           read_active_d[4] = 1'b0;
         end
         if (write_active_q[5] & (write_active5_utag_q == s0_sent_utag_q)) 
         begin             
           dec_write_dma = 1'b1;            
           write_active_d[5] = 1'b0;
         end
         if (read_active_q[5] & (read_active5_utag_q == s0_sent_utag_q))
         begin             
           dec_read_dma = 1'b1;            
           read_active_d[5] = 1'b0;
         end
         if (write_active_q[6] & (write_active6_utag_q == s0_sent_utag_q)) 
         begin             
           dec_write_dma = 1'b1;            
           write_active_d[6] = 1'b0;
         end
         if (read_active_q[6] & (read_active6_utag_q == s0_sent_utag_q))
         begin             
           dec_read_dma = 1'b1;            
           read_active_d[6] = 1'b0;
         end
         if (write_active_q[7] & (write_active7_utag_q == s0_sent_utag_q)) 
         begin             
           write_active_d[7] = 1'b0;
           dec_write_dma = 1'b1;            
         end
         if (read_active_q[7] & (read_active7_utag_q == s0_sent_utag_q))
         begin             
           dec_read_dma = 1'b1;            
           read_active_d[7] = 1'b0;
         end
       end
       
     end 
 
 

   wire inc_write_dma = d0h_dvalid & (s4_dtype_q == 3'b001);
   wire inc_read_dma = d0h_dvalid & (s4_dtype_q == 3'b000);
   wire [0:3] dma_write_cnt,dma_read_cnt;

//    track  how many DMA issued
   base_incdec#(.width(4)) icnt_dma_write(.clk(clk),.reset(reset),.i_inc(write_complete),.i_dec(dec_write_dma),.o_cnt(dma_write_cnt),.o_zero());  
   base_incdec#(.width(4)) icnt_dma_read(.clk(clk),.reset(reset),.i_inc(inc_read_dma),.i_dec(dec_read_dma),.o_cnt(dma_read_cnt),.o_zero());
   assign write_dma_full = (dma_write_cnt == 4'h8); 
   assign read_dma_full = (dma_read_cnt == 4'h8); 
   wire dma_write_overrun = (dma_write_cnt > 4'h8); 
   wire dma_read_overrun = (dma_read_cnt > 4'h8); 




   assign d0h_dvalid = s4_dvalid_q ; 
   assign d0h_req_utag = s4_req_utag_q; 
   assign d0h_req_itag = s4_req_itag_q; 
   assign d0h_dtype = s4_dtype_q;  
   assign d0h_dsize = s4_dsize_q; 
   assign d0h_datomic_op = 6'b000000; 
   assign d0h_datomic_le = 1'b0;

   assign o_dvalid =  s1_dvalid_q;
   assign o_dwad  =  s1_dwad_q;

   assign o_rsp_rd_ctag_v = r2_tag_plus_v  & (r2_rtag_plus[0:1] == 2'b01);  // read tag 
   assign o_rsp_rd_ctag = r2_rtag_plus[2:7];


   assign o_s0_sent_utag_valid = s0_sent_utag_valid_q && (s0_sent_utag_sts_q == 3'd1);
   assign o_s0_sent_utag       = s0_sent_utag_q ;
   assign o_s0_sent_utag_sts   = s0_sent_utag_sts_q; 
   assign o_rcb_req_sent = (s1_dtype_q == 3'b000) & (s1_dsize_q == 10'h080) & s1_dvalid_q & (s1_usource_q == 5'h04);



   

endmodule


