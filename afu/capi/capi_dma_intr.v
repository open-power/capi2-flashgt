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
module capi_dma_intr#
  (parameter tsize_width=12, // transaction size field
   parameter ctag_width=8, // capi tag
   parameter tag_width=3,  // dma engine tag
   parameter beat_width=3,
   parameter ea_width = 64,
   parameter ctxtid_width=16,
   parameter aux_width=1,
   parameter sid_width=1,
   parameter uid_width=1,
   parameter csid_width=1,
   parameter irqsrc_width=11,
   parameter rc_width=1,
   parameter [0:uid_width-1] uid=0,
   parameter wdata_addr_width=tag_width+beat_width,
   parameter creq_width = ctag_width + csid_width+1+tsize_width + aux_width+ctxtid_width+ea_width
   )
   (
    input 		     clk,
    input 		     reset,
    output 		     o_rm_err,
    
    output 		     i_req_r,
    input 		     i_req_v,
    input [0:ctxtid_width-1] i_req_d_ctxt,
    input [0:irqsrc_width-1] i_req_d_src,
    input [0:aux_width-1]    i_req_d_aux,
    
    output 		     o_req_v,
    input 		     o_req_r,
    output [0:creq_width-1]  o_req_d,

    input 		     i_rsp_v,
    input [ctag_width-1:0]   i_rsp_ctag,
    input [0:rc_width-1]     i_rsp_rc,

    output 		     o_rsp_v,
    output                   o_perror
    );

   localparam ltag_width = 2;

   wire [0:ltag_width-1]     s0_ltag;
   wire [0:ltag_width-1]     s0_rsp_ltag = i_rsp_ctag[ltag_width-1:0];
   wire 		     tag_v;
   wire 		     tag_r;
   capi_res_mgr#(.id_width(ltag_width)) irmgr
     (.clk(clk),.reset(reset),.o_avail_v(tag_v),.o_avail_r(tag_r),.o_avail_id(s0_ltag),
      .i_free_v(i_rsp_v),.i_free_id(s0_rsp_ltag),.o_free_err(o_rm_err),.o_cnt(),.o_perror(o_perror)
      );

   wire [0:ctag_width-1] s0_ctag = {{ctag_width-ltag_width{1'b0}},s0_ltag};
   localparam eamsb_width = ea_width-1-irqsrc_width;  // added -1 to get rid of parity kch 
   wire                           s0_ea_par;
   wire [0:ea_width-1] 		  s0_ea = {{eamsb_width{1'b0}},i_req_d_src,s0_ea_par};
   capi_parity_gen#(.dwidth(ea_width-1),.width(1)) s0_ea_pgen(.i_d(s0_ea[0:63]),.o_d(s0_ea_par));
   wire [0:tsize_width-1] 	  s0_tsize;
   base_const#(.width(tsize_width),.value('h80)) is0_tsize(s0_tsize);

   wire [0:ctxtid_width-1] 	  s0_ctxt = i_req_d_ctxt;
   wire [0:aux_width-1] 	  s0_aux = i_req_d_aux;

   wire [0:creq_width-1] 	  s0_req_d = {s0_ctag, uid, {sid_width{1'b0}}, 1'b1, s0_aux, s0_ctxt, s0_tsize, s0_ea};

   wire 			  s0_v, s0_r;
   base_acombine#(.ni(2),.no(1)) is0_cmb(.i_v({tag_v,i_req_v}),.i_r({tag_r,i_req_r}),.o_v(s0_v),.o_r(s0_r));
   
   base_alatch#(.width(creq_width)) i_req_lat
     (.clk(clk),.reset(reset),.i_v(s0_v),.i_r(s0_r),.i_d(s0_req_d),.o_v(o_req_v),.o_r(o_req_r),.o_d(o_req_d));

   assign o_rsp_v = i_rsp_v;

endmodule // capi_dma_put




   

   
   

   
    
   
