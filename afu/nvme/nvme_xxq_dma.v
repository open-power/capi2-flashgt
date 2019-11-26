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

//  *************************************************************************
//  File : nvme_xxq_dma.v
//  *************************************************************************
//  *************************************************************************
//  Description : Surelock Express NVMe DMA handler
//                read/write from PCIe endpoint to SQ/CQ/payload buffer
//


module nvme_xxq_dma#
  (     
        parameter addr_width = 48,

        parameter sq_num_queues = 1,
        parameter sq_first_id = 0,
        parameter sq_idwidth_int = $clog2(sq_num_queues+sq_first_id),
        parameter sq_idwidth = (sq_idwidth_int>0) ? sq_idwidth_int : 1,
        parameter sq_ptr_width = 2,
        parameter sq_addr_width = 2,
        parameter sq_rdwidth = 128,     
        parameter sq_par_rdwidth = 128/8,  
        parameter sq_rd_latency = 1,   
       

        parameter cq_num_queues = 1,
        parameter cq_first_id = 0,
        parameter cq_idwidth_int = $clog2(cq_num_queues+cq_first_id),
        parameter cq_idwidth = (cq_idwidth_int>0) ? cq_idwidth_int : 1,
        parameter cq_ptr_width = 2,
        parameter cq_addr_width = 2,
        parameter cq_wrwidth = 128, 
       parameter cq_par_wrwidth = 128/8                       
    )
   (
   
    input                                      reset,
    input                                      clk, 

    input                                      q_reset,
    output reg                                 q_init_done,

    // write completion queue
    output reg             [cq_addr_width-1:0] cq_wraddr,
    output reg                                 cq_wren,
    output reg                [cq_idwidth-1:0] cq_id, 
    output reg [cq_par_wrwidth+cq_wrwidth-1:0] cq_wrdata,

    // read submission queue
    output reg             [sq_addr_width-1:0] sq_rdaddr,
    output reg                                 sq_rdval,
    output reg                [sq_idwidth-1:0] sq_id,
    input     [ sq_par_rdwidth+sq_rdwidth-1:0] sq_rddata,
    
    //-------------------------------------------------------
    // DMA requests to SQ/CQ     parity generated at this level in pcie_rxcq 
    //-------------------------------------------------------
  
    input                                      pcie_xxq_valid,
    input                              [144:0] pcie_xxq_data, // changed 127 to 144 to add parity kch 
    input                                      pcie_xxq_first, 
    input                                      pcie_xxq_last, 
    input                                      pcie_xxq_discard, 
    output reg                                 xxq_pcie_pause,
    
    //-------------------------------------------------------
    // DMA response from SQ/CQ
    //-------------------------------------------------------        
 
    output reg                         [144:0] xxq_pcie_cc_data, // changed 127 to 144 kch 
    output reg                                 xxq_pcie_cc_first,
    output reg                                 xxq_pcie_cc_last,
    output reg                                 xxq_pcie_cc_discard,
    output reg                                 xxq_pcie_cc_valid,
    input                                      pcie_xxq_cc_ready,

    output reg                           [7:0] req_dbg_event,
    output                                     xxq_dma_perror,
    input                                [1:0] xxq_perror_inj,
    output                               [1:0] xxq_perror_ack 
  
    );

`include "nvme_func.svh"


   //-------------------------------------------------------
   // PCIe requests and completions
   //-------------------------------------------------------

   // Request header:
   //    { addr_type[1:0], 
   //      attr[2:0], 
   //      tc[2:0], 
   //      dcount[10:0],              - number of 32b words to return.  read 64B for 1 entry, but allow up to 4KB
   //      last_be[3:0],              - expect 0xF but accept any non-zero
   //      first_be[3:0],             - expect 0xF but accept any non-zero
   //      req_other, req_rd, req_wr, - expect either rd or wr
   //      pcie_tag[7:0], 
   //      addr_region[3:0],          - expect ENUM_ADDR_ADQ or ENUM_ADDR_IOQ
   //      addr[addr_width-1:0] }     - queue id/base/offset encoded in the address
   //
   // Completion header:
   // { addr_type[1:0],     // from original request
   //   attr[2:0],          // from original request
   //    tc[2:0],           // from original request
   //    byte_count[12:0],  // remaining bytes to be transferred including this packet
   //    cpl_status[2:0],   // 0x0 - success; 0x1 - unsupported request; 0x2 - completer abort
   //    cpl_dwords[10:0],  // number of dwords in the completion packet
   //    pcie_tag[7:0],     // from original request
   //    lower_addr[6:0] }  // least significant 7b of byte address of this packet
   
   localparam req_hdr_width = 2 + 3 + 3 + 11 + 4 + 4 + 3 +  8 + 4 + addr_width;  //78  bits wide 
   localparam req_hdr_par_width = (req_hdr_width +63)/64;
   localparam cpl_hdr_width = 2 + 3 + 3 + 13 + 3 + 11 + 8 + 7;  // 50 bits wide 
   localparam cpl_hdr_par_width = (cpl_hdr_width + 7)/8;

   reg [req_hdr_par_width+req_hdr_width-1:0] req_hdr_q, req_hdr_d;

   reg                     cpl_valid;
   reg                     cpl_ack;
   
   reg [3:0] req_state_q, req_state_d;
   localparam REQ_IDLE = 4'h1;
   localparam REQ_WR   = 4'h2;
   localparam REQ_RD   = 4'h3;

   reg [cq_addr_width-1:0] req_addr_q, req_addr_d;
   reg               [7:0] req_cqid_q, req_cqid_d;
   
   localparam cq_init_width=cq_addr_width+cq_idwidth;
   reg   [cq_init_width:0] cq_init_q, cq_init_d;

   reg             [7:0] req_dbg_event_q, req_dbg_event_d;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             req_state_q     <= REQ_IDLE;
             req_hdr_q       <= zero[req_hdr_par_width+req_hdr_width-1:0];  
             req_addr_q      <= zero[cq_addr_width-1:0];
             req_cqid_q      <= 8'h0;
             cq_init_q       <= zero[cq_init_width:0];
             req_dbg_event_q <= zero[7:0];
          end
        else
          begin
             req_state_q     <= req_state_d;
             req_hdr_q       <= req_hdr_d;
             req_addr_q      <= req_addr_d;
             req_cqid_q      <= req_cqid_d;
             cq_init_q       <= cq_init_d;
             req_dbg_event_q <= req_dbg_event_d;
          end	
     end


   // request header fields
   reg                     [1:0] req_hdr_par; 
   reg                     [1:0] req_addr_type; 
   reg          [addr_width-1:0] req_addr;
   reg                     [3:0] req_last_be;
   reg                     [3:0] req_first_be;
   reg                     [7:0] req_tag;
   reg                     [3:0] req_addr_region;
   reg                           req_rd;
   reg                           req_wr;
   reg                           req_other;
   reg                     [2:0] req_tc;
   reg                     [2:0] req_attr;
   reg                    [10:0] req_dcount;

   // generate parity on register header kch 
   wire  [req_hdr_par_width-1:0] pcie_xxq_hdr_par;

   nvme_pgen#
     (
      .bits_per_parity_bit(64),
      .width(req_hdr_width)
      ) ipgen_pcie_xxq_data 
       (.oddpar(1'b1),.data(pcie_xxq_data[req_hdr_width-1:0]),.datap(pcie_xxq_hdr_par[req_hdr_par_width-1:0])); 

  wire           [1:0]  s1_perror;
  wire           [1:0]  xxq_dma_perror_int;
   

   // set/reset/ latch for parity errors kch 
   nvme_srlat#
     (.width(2))  ixxq_sr   
       (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(xxq_dma_perror_int[1:0]));

   assign xxq_dma_perror = |(xxq_dma_perror_int);

   // check parity kch 
   nvme_pcheck#
     (
      .bits_per_parity_bit(64),
      .width(req_hdr_width)
      ) ipcheck_req_hdr_q
       (.oddpar(1'b1),.data({req_hdr_q[req_hdr_width-1:1],(req_hdr_q[0]^xxq_perror_inj[0])}),.datap(req_hdr_q[req_hdr_par_width+req_hdr_width-1:req_hdr_width]),.check(cpl_valid),.parerr(s1_perror[0])); 


   
   // parse request header   
   always @*
     begin
        
        // unpack header cycle on data interface
        if( req_state_q == REQ_IDLE )
          req_hdr_d = {pcie_xxq_hdr_par[req_hdr_par_width-1:0],pcie_xxq_data[req_hdr_width-1:0]};   
        else
          req_hdr_d = req_hdr_q;

        { req_hdr_par,
          req_addr_type, 
          req_attr, 
          req_tc, 
          req_dcount, 
          req_last_be,
          req_first_be,
          req_other, 
          req_rd, 
          req_wr, 
          req_tag, 
          req_addr_region,         
          req_addr} = req_hdr_d;
     end


   // handle read or write requests
   always @*
     begin

        req_state_d        = req_state_q;
        cpl_valid          = 1'b0;

        cq_wren            = 1'b0;
        req_addr_d         = req_addr_q;
        req_cqid_d         = req_cqid_q;
        cq_wraddr          = req_addr_q;
        cq_wrdata          = pcie_xxq_data;
        cq_id              = req_cqid_q[cq_idwidth-1:0];

        req_dbg_event_d    = zero[7:0];
        req_dbg_event      = req_dbg_event_q;
            
        cq_init_d          = cq_init_q;
        if( ~cq_init_q[cq_init_width] )
        begin
        cq_init_d   = cq_init_q + one[cq_init_width:0];
        cq_wren     = 1'b1;
        cq_wraddr   = cq_init_q[cq_addr_width-1:0];
             cq_wrdata   = {16'hFFFF,zero[cq_wrwidth-1:0]};  // note: this resets the phase bit to zero as required
          end
        
        if( q_reset )
          begin
             cq_init_d = zero[cq_init_width:0];
             cq_wren   = 1'b0;
          end

        q_init_done = cq_init_q[cq_init_width];
        
        // pause on packet boundary when not idle
        xxq_pcie_pause = 1'b1;

        case(req_state_q)
          REQ_IDLE:
            begin
               xxq_pcie_pause = ~cq_init_q[cq_init_width];
               if( pcie_xxq_valid & pcie_xxq_first & ~pcie_xxq_discard )
                 begin
                    if( req_rd )
                      begin
                         req_state_d = REQ_RD;                        
                         // pcie_xxq_last should be set
                         req_dbg_event_d[0] = ~pcie_xxq_last;
                      end
                    else if( req_wr )
                      begin
                         req_state_d         = REQ_WR;
                         req_addr_d          = req_addr[cq_addr_width+4-1:4];  // 16B address
                         req_cqid_d          = req_addr[47:40];
                         req_dbg_event_d[1]  = req_addr[3:2]!=2'b00;
                         req_dbg_event_d[2]  = req_first_be!=4'hF || req_last_be!=4'hF;                        
                      end
                    else
                      begin
                         req_dbg_event_d[3]  = 1'b1;
                      end                                        
                 end               
            end
          
          REQ_WR:
            begin
               if(pcie_xxq_valid)
                 begin
                    if( req_cqid_q[6:0] < cq_num_queues &&
                        req_cqid_q[7] == 1'b1 )
                      begin
                         // write to valid ICQ
                         cq_wren = 1'b1;                         
                      end
                    else
                      begin
                         // drop writes to other addresses
                         req_dbg_event_d[4] = 1'b1;
                      end
                    
                    req_addr_d = req_addr_q + one[cq_addr_width-1:0];

                    if( pcie_xxq_last )
                      begin
                         req_state_d = REQ_IDLE;
                      end    
                 end               
            end
          
          REQ_RD:            
            begin
               // hand off to completion state machine            
               cpl_valid = 1'b1;
               if( cpl_ack )
                 begin
                    req_state_d = REQ_IDLE;
                 end
            end
    
          default:
            begin
               req_state_d = REQ_IDLE;
            end
        endcase // case (req_state_q)
                   
     end // always @ *


   //-------------------------------------------------------
   // generate completions
   //-------------------------------------------------------

   // build completion header from request header
   reg [req_hdr_par_width+req_hdr_width-1:0] cpl_s0_req_hdr_q, cpl_s0_req_hdr_d;
   reg              [12:0] bytes_sent_q, bytes_sent_d;
   reg              [12:0] bytes_total;
   reg              [12:0] bytes_first;
   reg              [12:0] bytes_last;
   
   reg              [10:0] dwords_sent_q, dwords_sent_d;
   reg              [10:0] dwords_not_sent;
   
   reg               [1:0] cpl_s0_req_addr_type; 
   reg    [addr_width-1:0] cpl_s0_req_addr;
   reg               [3:0] cpl_s0_req_last_be;
   reg               [3:0] cpl_s0_req_first_be;
   reg               [7:0] cpl_s0_req_tag;
   reg               [3:0] cpl_s0_req_addr_region;
   reg                     cpl_s0_req_rd;
   reg                     cpl_s0_req_wr;
   reg                     cpl_s0_req_other;
   reg               [2:0] cpl_s0_req_tc;
   reg               [2:0] cpl_s0_req_attr;
   reg              [10:0] cpl_s0_req_dcount;
   
   // completion header fields
   reg [cpl_hdr_width-1:0] cpl_s0_hdr;   // added cpl_hdr_par_width kch 
   wire  [cpl_hdr_par_width-1:0] cpl_s0_hdr_par;   // added cpl_hdr_par_width kch 
   reg              [10:0] cpl_dcount;  // number of dwords in this packet
   reg               [2:0] cpl_status;  // 0x0 - success; 0x1 - unsupported request; 0x2 - completer abort
   reg              [12:0] byte_count;  // remaining bytes to be transferred including this packet
   reg               [6:0] lower_addr;  // starting offset of this packet



   // build completion header fields
   always @*
     begin
        { cpl_s0_req_addr_type, 
          cpl_s0_req_attr, 
          cpl_s0_req_tc, 
          cpl_s0_req_dcount, 
          cpl_s0_req_last_be,
          cpl_s0_req_first_be,
          cpl_s0_req_other, 
          cpl_s0_req_rd, 
          cpl_s0_req_wr, 
          cpl_s0_req_tag, 
          cpl_s0_req_addr_region, 
          cpl_s0_req_addr} = cpl_s0_req_hdr_q;

        
        cpl_status = 3'h0; // success

        dwords_not_sent = cpl_s0_req_dcount - dwords_sent_q;
        if( dwords_not_sent > 11'd32 )
          begin
             // more than 128B left to send
             cpl_dcount = 11'd32;
          end
        else
          begin
             cpl_dcount = dwords_not_sent;
          end

        // calculate lower_address & byte_count - see "PCI Express System Architecture" pg 187
        // note: only the first case is expected, but handle correctly anyway
        lower_addr[6:2] = cpl_s0_req_addr[6:2];
        if( cpl_s0_req_first_be[0] )
          begin
             bytes_first      = 11'd4;
             lower_addr[1:0]  = 2'b00;
          end
        else if( cpl_s0_req_first_be[1] )
          begin
             bytes_first      = 11'd3;
             lower_addr[1:0]  = 2'b01;
          end             
        else if( cpl_s0_req_first_be[2] )
          begin
             bytes_first      = 11'd2;
             lower_addr[1:0]  = 2'b10;
          end         
        else if(cpl_s0_req_first_be[3] )
          begin
             bytes_first      = 11'd1;
             lower_addr[1:0]  = 2'b11;
          end        
        else         
          begin
             bytes_first      = 11'd0;
             lower_addr[1:0]  = 2'b00;
          end     
      
        if( dwords_sent_q != zero[11:0] )
          begin
             lower_addr[1:0] = 2'b00;
          end

        
        if( cpl_s0_req_last_be[3] )
          begin
             bytes_last      = 11'd4;            
          end
        else if( cpl_s0_req_last_be[2] )
          begin
             bytes_last      = 11'd3;           
          end             
        else if( cpl_s0_req_last_be[1] )
          begin
             bytes_last      = 11'd2;           
          end         
        else if(cpl_s0_req_last_be[0] )
          begin
             bytes_last      = 11'd1;           
          end        
        else         
          begin
             bytes_last      = 11'd0;           
          end     

        bytes_total = {cpl_s0_req_dcount, 2'b00} - 11'd8 + bytes_first + bytes_last;

        byte_count = bytes_total - bytes_sent_q;
        
        cpl_s0_hdr = { cpl_s0_req_addr_type, 
                       cpl_s0_req_attr, 
                       cpl_s0_req_tc, 
                       byte_count,
                       cpl_status,
                       cpl_dcount,
                       cpl_s0_req_tag, 
                       lower_addr};
     end


   
   reg    [addr_width-1:0] cpl_s0_addr_q, cpl_s0_addr_d;
   reg    [addr_width-1:0] cpl_s0_end_addr_q, cpl_s0_end_addr_d;
   reg                     cpl_s0_valid_q, cpl_s0_valid_d;
   reg               [2:0] cpl_s0_paycnt_q, cpl_s0_paycnt_d;
   reg                     cpl_s0_valid;
   reg                     cpl_s0_first;
   reg                     cpl_s0_last;   
  
   reg                     cpl_s1_ready;
   reg                     cpl_s1_valid_q, cpl_s1_valid_d;
   reg                     cpl_s1_rdval_q, cpl_s1_rdval_d;
   reg    [addr_width-1:0] cpl_s1_addr_q, cpl_s1_addr_d;
   reg                     cpl_s1_first_q, cpl_s1_first_d;
   reg                     cpl_s1_last_q, cpl_s1_last_d;
   reg                     cpl_s1_discard_q, cpl_s1_discard_d;
   reg                     cpl_s1_cntl_par_q, cpl_s1_cntl_par_d;
   reg [cpl_hdr_par_width+cpl_hdr_width-1:0] cpl_s1_hdr_q, cpl_s1_hdr_d;  // added cpl_hdr_par_width kch 
   reg             [16+127:0] cpl_s1_data;   // added 16+
   
   wire                   cpl_s2_ready;
  

   (* mark_debug = "false" *)  
   reg              [3:0] cpl_s0_state_q;
   reg              [3:0] cpl_s0_state_d;
   localparam CPL_IDLE = 4'h1;
   localparam CPL_PAY  = 4'h2;

   // check parity kch 
   nvme_pcheck#
     (
      .bits_per_parity_bit(64),
      .width(req_hdr_width)
      ) ipcheck_cpl_s0_req_hdr_q
       (.oddpar(1'b1),.data({cpl_s0_req_hdr_q[req_hdr_width-1:1],(cpl_s0_req_hdr_q[0]^xxq_perror_inj[1])}),.datap(cpl_s0_req_hdr_q[req_hdr_par_width+req_hdr_width-1:req_hdr_width]),.check(cpl_s1_ready),.parerr(s1_perror[1])); 

   assign  xxq_perror_ack = {cpl_s1_ready, cpl_valid}; 



   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             bytes_sent_q      <= zero[12:0];
             dwords_sent_q     <= zero[10:0];
             cpl_s0_state_q    <= CPL_IDLE;
             cpl_s0_req_hdr_q  <= zero[req_hdr_par_width+req_hdr_width-1:0];
             cpl_s0_addr_q     <= zero[addr_width-1:0];
             cpl_s0_end_addr_q <= zero[addr_width-1:0];
             cpl_s0_valid_q    <= zero[0];
             cpl_s0_paycnt_q   <= zero[2:0];
             cpl_s1_valid_q    <= zero[0];
             cpl_s1_addr_q     <= zero[addr_width-1:0];
             cpl_s1_rdval_q    <= 1'b0;
             cpl_s1_first_q    <= zero[0];
             cpl_s1_last_q     <= zero[0];
             cpl_s1_discard_q  <= zero[0];
             cpl_s1_cntl_par_q <= one[0];
             cpl_s1_hdr_q      <= zero[cpl_hdr_par_width+cpl_hdr_width-1:0];  // adeed cpl_hdr_par_width kch           
          end
        else
          begin
             bytes_sent_q      <= bytes_sent_d;
             dwords_sent_q     <= dwords_sent_d;
             cpl_s0_state_q    <= cpl_s0_state_d;
             cpl_s0_req_hdr_q  <= cpl_s0_req_hdr_d;
             cpl_s0_addr_q     <= cpl_s0_addr_d;
             cpl_s0_end_addr_q <= cpl_s0_end_addr_d;
             cpl_s0_valid_q    <= cpl_s0_valid_d;
             cpl_s0_paycnt_q   <= cpl_s0_paycnt_d;
             cpl_s1_valid_q    <= cpl_s1_valid_d;
             cpl_s1_addr_q     <= cpl_s1_addr_d;
             cpl_s1_rdval_q    <= cpl_s1_rdval_d;
             cpl_s1_first_q    <= cpl_s1_first_d;
             cpl_s1_last_q     <= cpl_s1_last_d;
             cpl_s1_discard_q  <= cpl_s1_discard_d;
             cpl_s1_cntl_par_q <= cpl_s1_cntl_par_d;
             cpl_s1_hdr_q      <= cpl_s1_hdr_d;     
          end     
     end

   // number of byte address bits to strip off for an entry address
   localparam sq_entry_addr_bits = (sq_addr_width-sq_ptr_width)+$clog2(sq_rdwidth/8);
   
   // stage s0 - completion request register 
   always @*
     begin
        cpl_s0_state_d     = cpl_s0_state_q;
        cpl_s0_valid_d     = cpl_s0_valid_q;        
        cpl_s0_addr_d      = cpl_s0_addr_q;
        cpl_s0_end_addr_d  = cpl_s0_end_addr_q;
        cpl_s0_req_hdr_d   = cpl_s0_req_hdr_q;
        cpl_s0_paycnt_d    = cpl_s0_paycnt_q;
        bytes_sent_d       = bytes_sent_q;
        dwords_sent_d      = dwords_sent_q;
        cpl_ack            = 1'b0;

       
        if( cpl_s0_valid_q == 1'b0 )
          begin
             if( cpl_valid )
               begin
                  cpl_ack            = 1'b1;
                  cpl_s0_valid_d     = 1'b1;
                  // add sq base from addr[39:28] to offset in lower byte address
                  cpl_s0_addr_d[47:40] = req_addr[47:40];
                  cpl_s0_addr_d[39:28] = 12'h0;
                  cpl_s0_addr_d[27:0] = req_addr[27:0] + {req_addr[39:28],zero[sq_entry_addr_bits-1:0]};
                  cpl_s0_end_addr_d  = cpl_s0_addr_d + {req_dcount, 2'h0};
                  cpl_s0_req_hdr_d   = req_hdr_q;
                  bytes_sent_d       = zero[12:0];
                  dwords_sent_d      = zero[10:0];
               end         
          end

        // generate 1 or more completions
        cpl_s0_valid = 1'b0;
        cpl_s0_first = 1'b0;
        cpl_s0_last  = 1'b0;
        case( cpl_s0_state_q )
          CPL_IDLE:
            begin
               cpl_s0_paycnt_d = 3'd0;
               if(cpl_s0_valid_q & cpl_s1_ready)
                 begin                    
                    cpl_s0_state_d  = CPL_PAY;                   
                    cpl_s0_first    = 1'b1;
                    cpl_s0_valid    = 1'b1;
                 end
            end
          
          CPL_PAY:
            begin
               if( cpl_s1_ready )
                 begin
                    // address is expected to be aligned on 16B boundary (addr[3:2]==0)
                    cpl_s0_addr_d = cpl_s0_addr_q + {one[addr_width-5:0],4'h0};  // 16B per read
                    dwords_sent_d = dwords_sent_q + 11'd4;
                    if( bytes_sent_q == 13'h0 )
                      begin
                         bytes_sent_d = 13'd12 + bytes_first;
                      end
                    else
                      begin
                         bytes_sent_d = bytes_sent_q + 13'd16;
                      end                    
                    
                    cpl_s0_valid = 1'b1;
                    
                    // end of transfer
                    if( cpl_s0_addr_d == cpl_s0_end_addr_q )
                      begin
                         cpl_s0_last = 1'b1;
                         cpl_s0_state_d = CPL_IDLE;
                         cpl_s0_valid_d = 1'b0;
                      end
                    
                    // start a new packet if 8th payload cycle (128B max packet size)
                    cpl_s0_paycnt_d = cpl_s0_paycnt_q + 3'd1; 
                    if( cpl_s0_paycnt_q == 3'd7 )
                      begin
                         cpl_s0_last = 1'b1;
                         cpl_s0_state_d = CPL_IDLE;
                      end                    
                 end               
            end
          
          default:
            begin
               cpl_s0_state_d = CPL_IDLE;
            end
          
        endcase // case ( cpl_s0_state_q )
          
     end

   // parity gen cpl_s1_control
   wire                cpl_s1_cntl_par;
   nvme_pgen#
     (
      .bits_per_parity_bit(3),
      .width(3)
      ) ipgen_cpl_s1_cntl 
       (.oddpar(1'b1),.data({cpl_s1_first_d,cpl_s1_last_d,cpl_s1_discard_d}),.datap(cpl_s1_cntl_par)); 

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(cpl_hdr_width)
      ) ipgen_cpl_s0_hdr 
       (.oddpar(1'b1),.data({cpl_s0_hdr}),.datap(cpl_s0_hdr_par)); 



   always @*
     begin
        cpl_s1_ready  = ~cpl_s1_valid_q | cpl_s2_ready;
        sq_rdval      = 1'b0;
        sq_id         = cpl_s0_addr_q[46:40];

        if( cpl_s1_ready )
          begin
             cpl_s1_hdr_d      = {cpl_s0_hdr_par,cpl_s0_hdr};
             cpl_s1_first_d    = cpl_s0_first;
             cpl_s1_last_d     = cpl_s0_last;
             cpl_s1_discard_d  = 1'b0;  // placeholder for parity error reading data from SQ
             cpl_s1_cntl_par_d = cpl_s1_cntl_par;
             cpl_s1_valid_d    = cpl_s0_valid;
             cpl_s1_addr_d     = cpl_s0_addr_q;
             // convert byte address from request to address for SQ memory
             sq_rdaddr         = cpl_s0_addr_q[sq_addr_width-1+clogb2(sq_rdwidth/8):clogb2(sq_rdwidth/8)];
             
             if( ~cpl_s0_first &&
                 cpl_s0_valid )
               begin
                  sq_rdval = 1'b1;
               end
             cpl_s1_rdval_d    = sq_rdval;
          end
        else
          begin
             cpl_s1_hdr_d       = cpl_s1_hdr_q;
             cpl_s1_first_d     = cpl_s1_first_q;
             cpl_s1_last_d      = cpl_s1_last_q;
             cpl_s1_discard_d   = cpl_s1_discard_q;
             cpl_s1_cntl_par_d  = cpl_s1_cntl_par_q;
             cpl_s1_valid_d     = cpl_s1_valid_q;
             cpl_s1_addr_d      = cpl_s1_addr_q;
             cpl_s1_rdval_d     = cpl_s1_rdval_q;
             
             sq_rdaddr          = cpl_s1_addr_q[sq_addr_width-1+clogb2(sq_rdwidth/8):clogb2(sq_rdwidth/8)];   
             sq_id              = cpl_s1_addr_q[46:40];          
             sq_rdval           = cpl_s1_rdval_q;
          end

        if( cpl_s1_first_q )
          begin
             cpl_s1_data =  { 7'b1111111,cpl_s1_hdr_q[cpl_hdr_par_width-1+cpl_hdr_width:cpl_hdr_width],zero[127:cpl_hdr_width], cpl_s1_hdr_q[cpl_hdr_width-1:0] }; // testing kch 
             // cpl_s1_data =  { one[143:128+cpl_hdr_par_width],cpl_s1_hdr_q[cpl_hdr_par_width+cpl_hdr_width:cpl_hdr_par_width],zero[127:cpl_hdr_width], cpl_s1_hdr_q[cpl_hdr_width-1:0] }; // added header
          end
        else if( cpl_s1_rdval_q != zero[sq_num_queues-1:0] )
          begin
             cpl_s1_data = sq_rddata;
          end
        else
          begin
             cpl_s1_data = {16'hFFFF,zero[127:0]}; // added 17+ kch
          end
     end   


   // stage 2 - with pipeline backpressure relief
   wire [1+sq_par_rdwidth+sq_rdwidth-1+3:0] cpl_s2_pl_data; // added 17 bits parity 
   wire                                     cpl_s2_valid;
   nvme_pl_burp#(.width(1+sq_par_rdwidth+sq_rdwidth+3), .stage(1)) cpl_s2  // added sq_par_rdwidth kch 
     (.clk(clk),.reset(reset),
      .valid_in(cpl_s1_valid_q),
      .data_in( {cpl_s1_first_q,cpl_s1_last_q,cpl_s1_discard_q,cpl_s1_cntl_par_q,cpl_s1_data} ),
      .ready_out(cpl_s2_ready),
      
      .data_out(cpl_s2_pl_data),
      .valid_out(cpl_s2_valid),
      .ready_in(pcie_xxq_cc_ready)
      ); 
   
   always @*
     begin               
        { xxq_pcie_cc_first,
          xxq_pcie_cc_last, 
          xxq_pcie_cc_discard,
          xxq_pcie_cc_data } = cpl_s2_pl_data;
        xxq_pcie_cc_valid    = cpl_s2_valid;        
     end
   



endmodule
