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

module capi_put_cmd_enc#
  (// afu/psl   interface parameters
   parameter ea_width = 65,
   parameter sid_width = 2
    )
   (
   
    input                       reset,
    input                       clk,


    input                       i_addr_v,
    input [0:ea_width-1] 	i_addr_ea,
    input [0:3] 	        i_data_c, // count - valid only with _e, zero = 16 
    input       	        i_data_v,
    input       	        i_data_r,
    input       	        i_data_e,
    input [0:4]                 i_cmd_tag,
    input [0:sid_width-1]       i_sid,
    input                       i_f,
    input [0:10]                i_addr_aux,
    input [0:9]                 i_addr_ctxt,
    input                       i_data_cmd_gen_r,
    input                       i_cmd_v,
    output [0:3]                o_data_align_offset,
    output [0:ea_width-1] 	o_cmd_addr_ea,
    output [0:9]                o_cmd_tsize,
    output [0:4]                o_cmd_tag,
    output                      o_cmd_v,
    output                      o_cmd_gen_v,
    output                      o_reset_beat_cnt,
    output [0:sid_width-1]      o_cmd_sid,
    output                      o_cmd_f,
    output [0:10]               o_cmd_addr_aux,
    output [0:9]                o_cmd_addr_ctxt,
    output                      o_s1_crossing_enable,
    output                      o_crossing_end,
    output                      o_s1_data_e
   );
   // register command request interface  
   reg [0:ea_width-2]       cmd_addr_q,cmd_addr_d; 
   reg                      cmd_addr_v_q,cmd_addr_v_d;
   reg [0:ea_width-2]       s0_cmd_addr_q,s0_cmd_addr_d;
   reg [0:9]                cmd_tsize_q,cmd_tsize_d;
   reg [0:9]                s1_cmd_tsize_q,s1_cmd_tsize_d;
   reg                      cmd_v_q,cmd_v_d;
   reg                      reset_beat_cnt_q,reset_beat_cnt_d;
   reg [0:2]                crossing_active_q,crossing_active_d;
   reg [0:3]                data_align_offset_q,data_align_offset_d;
   reg [0:3]                s0_data_align_offset_q,s0_data_align_offset_d;
   reg [0:9]                cmd_length_d,cmd_length_q; 
   reg                      crossing_end_enable_q, crossing_end_enable_d;                     
   reg                      s1_cross512_active_q, s1_cross512_active_d;                     
   reg                      s1_cross4k_active_q, s1_cross4k_active_d;
   reg                      s0_put_data_e_q,s0_put_data_e_d;                      
   reg                      s1_put_data_e_q,s1_put_data_e_d;
   reg                      multicycle_cmd_q,multicycle_cmd_d ;                     
   reg                      s1_multicycle_cmd_q,s1_multicycle_cmd_d ;                     
   reg                      s2_multicycle_cmd_q,s2_multicycle_cmd_d ;                     
   
   always @(posedge clk or posedge reset)
     begin
       if ( reset == 1'b1 )
       begin
          cmd_addr_q             <= 1'b0;
          cmd_addr_v_q           <= 1'b0;
          s0_cmd_addr_q          <= 1'b0;
          cmd_length_q           <= 1'b0;
          data_align_offset_q    <= 1'b0;
          s0_data_align_offset_q <= 1'b0;
          cmd_v_q                <= 1'b0;
          reset_beat_cnt_q       <= 1'b0;
          crossing_active_q      <= 3'b000;
          cmd_tsize_q            <= 1'b0;
          s1_cmd_tsize_q         <= 1'b0;
          crossing_end_enable_q  <= 1'b0;
          s1_cross512_active_q   <= 1'b0;
          s1_cross4k_active_q    <= 1'b0;
          s0_put_data_e_q        <= 1'b0;
          s1_put_data_e_q        <= 1'b0;
          multicycle_cmd_q       <= 1'b0 ;
          s1_multicycle_cmd_q    <= 1'b0 ;
          s2_multicycle_cmd_q    <= 1'b0 ;
       end
       else
       begin
          cmd_addr_q             <= cmd_addr_d;
          cmd_addr_v_q           <= cmd_addr_v_d;
          s0_cmd_addr_q          <= s0_cmd_addr_d;
          data_align_offset_q    <= data_align_offset_d; 
          s0_data_align_offset_q <= s0_data_align_offset_d; 
          cmd_v_q                <= cmd_v_d;
          reset_beat_cnt_q       <= reset_beat_cnt_d;
          cmd_length_q           <= cmd_length_d; 
          cmd_tsize_q            <= cmd_tsize_d;
          s1_cmd_tsize_q         <= s1_cmd_tsize_d;
          crossing_active_q      <= crossing_active_d;
          crossing_end_enable_q  <= crossing_end_enable_d;
          s1_cross512_active_q   <= s1_cross512_active_d;
          s1_cross4k_active_q    <= s1_cross4k_active_d;
          s0_put_data_e_q        <= s0_put_data_e_d;
          s1_put_data_e_q        <= s1_put_data_e_d;
          multicycle_cmd_q       <= multicycle_cmd_d ;
          s1_multicycle_cmd_q    <= s1_multicycle_cmd_d ;
          s2_multicycle_cmd_q    <= s2_multicycle_cmd_d ;
       end
     end

  reg                        i_datac_zero;
  reg [0:4]                  i_data_ec;
  reg [0:9]                  current_length;
  reg [0:12]                 cross4k;
  reg [0:9]                  cross512;
  reg [0:9]                  current_tsize;
  reg                        cross4k_active;
  reg                        cross512_active;
  reg                        cmd_size_eq0;
  reg                        put_data_is_valid;

   always @*
     begin

       cmd_addr_d     = cmd_addr_q;
       cmd_addr_v_d     = cmd_addr_v_q;
       s0_cmd_addr_d     = s0_cmd_addr_q;
       cmd_length_d   = cmd_length_q;
       data_align_offset_d  = data_align_offset_q;
       s0_data_align_offset_d  = data_align_offset_q;
       cmd_v_d            = 1'b0; 
       reset_beat_cnt_d   = 1'b0;        
       cmd_v_d            = cmd_v_q;         
       cmd_tsize_d          = cmd_tsize_q;
       s1_cmd_tsize_d       = cmd_tsize_q;
       multicycle_cmd_d     =  1'b0;
       s1_multicycle_cmd_d     =  multicycle_cmd_q;
       s2_multicycle_cmd_d     =  s1_multicycle_cmd_q;


       i_datac_zero = i_data_c == 4'b0;
       i_data_ec = {i_datac_zero,i_data_c};

       put_data_is_valid = i_data_v & i_data_r & ~i_data_e; 
       current_length = cmd_length_q + (i_data_ec & {5{put_data_is_valid}}) ;
       current_tsize       = cmd_length_q;

       cross4k = cmd_addr_q[52:63] + current_length;
       cross4k_active = cross4k[0];
       s1_cross4k_active_d = cross4k_active;

       cross512 = cmd_addr_q[62:63] + current_length;
       cross512_active = cross512[0];
       s1_cross512_active_d = cross512_active;

       s0_put_data_e_d = i_data_e & ~crossing_active_q[2];
       s1_put_data_e_d = s0_put_data_e_q;

       crossing_active_d = {crossing_active_q[1],crossing_active_q[2],1'b0};
       crossing_end_enable_d = 1'b0;
       if (i_addr_v)  
       begin
         cmd_addr_d = i_addr_ea[0:63];
         if (~i_data_e) 
         begin
           cmd_addr_v_d = 1'b1;
         end
       end
       if (i_cmd_v)
       begin
         cmd_v_d = 1'b0;
       end
       if (~i_data_r)   // freeze state of all latches 
       begin
         cmd_length_d = cmd_length_q;
         cmd_tsize_d         = cmd_tsize_q;
         s1_cmd_tsize_d      = s1_cmd_tsize_q;
         crossing_active_d = crossing_active_q;
         s1_cross4k_active_d = s1_cross4k_active_q;
         s1_cross512_active_d = s1_cross512_active_q;
         crossing_end_enable_d = crossing_end_enable_q;
         multicycle_cmd_d     =  multicycle_cmd_q;
         s1_multicycle_cmd_d     =  s1_multicycle_cmd_q;
         s2_multicycle_cmd_d     =  s2_multicycle_cmd_q;
         data_align_offset_d = data_align_offset_q;
         data_align_offset_d = data_align_offset_q;
         reset_beat_cnt_d   = reset_beat_cnt_q;
         s0_put_data_e_d = s0_put_data_e_q;
         s1_put_data_e_d = s1_put_data_e_q;
       end
       else  
       begin  
         if (i_data_v & i_data_r) 
         begin
           if (i_data_e) 
           begin
             cmd_length_d = 1'b0;
             data_align_offset_d = 1'b0;
             current_tsize       = cmd_length_q;
             cmd_v_d             = ~((current_tsize == 10'b0000000000) &  crossing_active_q[2]); 
             reset_beat_cnt_d    = ~((current_tsize == 10'b0000000000) &  crossing_active_q[2]); 
             crossing_end_enable_d = ((current_tsize == 10'b0000000000) &  crossing_active_q[2]);
             cmd_tsize_d         = current_tsize;
             if (~i_addr_v)
             begin
               cmd_addr_v_d        = 1'b0;
             end
             if (~cmd_addr_v_q) 
             begin  
               s0_cmd_addr_d       = i_addr_ea[0:63]; 
             end
             else
             begin          
               s0_cmd_addr_d       = cmd_addr_q;
             end         
           end
           else
           begin
             cmd_length_d = current_length;
           end
           if (cross4k_active) 
           begin 
             crossing_active_d[2] = 1'b1;
             current_tsize  = current_length - cross4k[4:12];  
             cmd_tsize_d = current_tsize;
             if (~cmd_addr_v_q) 
             begin  
               s0_cmd_addr_d[0:ea_width-2] = {cmd_addr_q[0:63] + current_tsize}; 
             end
             else
             begin          
               s0_cmd_addr_d       = cmd_addr_q;
             end         
             cmd_addr_d[0:ea_width-2] = {cmd_addr_q[0:63] + current_tsize}; 
             cmd_v_d = 1'b1;
             reset_beat_cnt_d = 1'b1;
             multicycle_cmd_d = 1'b1;
             cmd_addr_v_d = 1'b1;
             cmd_length_d = cmd_length_q - current_tsize + (({5{~i_data_e}}) & (i_data_ec));
             data_align_offset_d = cross4k[9:12];
           end 
           else  
           if (cross512_active) 
           begin 
             crossing_active_d[2] = 1'b1;
             cmd_v_d             = 1'b1;
             reset_beat_cnt_d = 1'b1;
             current_tsize = current_length - cross512[6:9]; // subtract off lsb 4 bits to keep packet lenth to >512.
             cmd_tsize_d = current_tsize;
             cmd_length_d = cmd_length_q - current_tsize + (({5{~i_data_e}}) & (i_data_ec));
             data_align_offset_d = cross512[6:9];
             if (~cmd_addr_v_q) 
             begin  
               s0_cmd_addr_d[0:ea_width-2] = {cmd_addr_q[0:63] + current_tsize}; 
             end
             else
             begin          
               s0_cmd_addr_d       = cmd_addr_q;
             end         
             cmd_addr_d[0:ea_width-2] = {cmd_addr_q[0:63] + current_tsize} ;
             s0_cmd_addr_d = cmd_addr_q;
             multicycle_cmd_d = 1'b1;
             cmd_addr_v_d = 1'b1;
           end   
         end
       end // cmd_gen_r 
     end 

   nvme_fifo#(
              .width(5+10+65+sid_width+1+11+10), 
              .words(32),
              .almost_full_thresh(6)
              ) icmd_fifo
     (.clk(clk), .reset(reset), 
      .flush(       1'b0 ),
      .push(        cmd_v_q & i_cmd_v ),
      .din(         {i_cmd_tag,cmd_tsize_q,s0_cmd_addr_q,~^(s0_cmd_addr_q),i_sid,i_f,i_addr_aux,i_addr_ctxt} ),
      .dval(        o_cmd_gen_v ), 
      .pop(         i_data_cmd_gen_r & o_cmd_gen_v ),
      .dout(        {o_cmd_tag,o_cmd_tsize,o_cmd_addr_ea,o_cmd_sid,o_cmd_f,o_cmd_addr_aux,o_cmd_addr_ctxt} ),
      .full(        ), 
      .almost_full( ), 
      .used());

    assign o_data_align_offset = (data_align_offset_q); 
    assign o_cmd_v = cmd_v_q & i_cmd_v;
    assign o_reset_beat_cnt = reset_beat_cnt_q & i_data_r;
    assign o_s1_crossing_enable =  (crossing_active_q[1] & ~s1_multicycle_cmd_q) | (crossing_active_q[0] & s2_multicycle_cmd_q);
    assign o_crossing_end = crossing_active_q[1] & crossing_end_enable_q;
    assign o_s1_data_e = crossing_active_q[2] ? i_data_e : s0_put_data_e_q;

endmodule


