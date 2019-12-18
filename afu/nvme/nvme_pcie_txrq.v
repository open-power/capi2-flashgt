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

`timescale 1ns/1ns

// Xilinx Requester reQuest interface handler
// 4 or 8B config or mmio ops only
//
// - CfgRd0, CfgWr0, MRd_64, MWr_64 from microcontroller for init
// - MWr_64 from Admin and I/O Queues for doorbell writes
//

module nvme_pcie_txrq
  #(
    parameter dummy = 0,
    parameter bits_per_parity_bit = 8
  )
  ( 
    //-------------------------------------------------------
    // control interface requests
    //-------------------------------------------------------
    input              ctlff_txrq_valid,
    input              ctlff_txrq_rnw,
    input              ctlff_txrq_cfgop,
    input        [5:0] ctlff_txrq_tag,
    input       [63:0] ctlff_txrq_addr,
    input       [63:0] ctlff_txrq_data,
    input        [7:0] ctlff_txrq_datap,
    input        [7:0] ctlff_txrq_be,
    output reg         txrq_ctlff_ack,
  
 
    //-------------------------------------------------------
    //  Transaction (AXIS) Interface
    //   - Requester reQuest interface
    //-------------------------------------------------------    
    input              user_clk,
    input              user_reset,
    input              user_lnk_up,
    //-------------------------------------------------------    
  
    output reg [127:0] s_axis_rq_tdata,
    output reg   [3:0] s_axis_rq_tkeep,
    output reg         s_axis_rq_tlast,
    input        [3:0] s_axis_rq_tready,
    output reg  [61:0] s_axis_rq_tuser,
    output reg         s_axis_rq_tvalid,
    output             user_txrq_perror_ind,

    output reg [143:0] txrq_dbg_user_tracedata,
    output reg         txrq_dbg_user_tracevalid,
    input              regs_pcie_pe_errinj_valid,
    input       [15:0] regs_xxx_pe_errinj_decode, 
    input              user_regs_wdata_pe_errinj_valid  // 1 cycle pulse in nvme domain 
  
);

`include "nvme_func.svh"
   
   wire                s1_uperror;
   wire                txrq_uperror_int;

   assign  s1_uperror = 1'b0;

   // set/reset/ latch for parity errors 
   nvme_srlat#
     (.width(1))  itxrq_sr   
       (.clk(user_clk),.reset(user_reset),.set_in(s1_uperror),.hold_out(txrq_uperror_int));

   assign user_txrq_perror_ind = txrq_uperror_int;


   //-------------------------------------------------------
   // drive xilinx requester interface
   //-------------------------------------------------------
   // Ref:  xilinx doc pg156-ultrascale-pcie-gen3.pdf Sept 30, 2015
   //
   // cycle 0:  descriptor format, tuser sideband
   // cycle 1:  data - 2 dwords max
   //
   // xilinx core options:
   // - dword alignment
   // - client tag management
   //
   //-------------------------------------------------------    
   // rq_tdata descriptor format
   //-------------------------------------------------------    
   // 63:0    = Address[63:2], Address Type[1:0] (Memory Requests)
   // 63:0    = Reserved[63:12], Ext Reg Num[3:0], Reg Number[7:0], Reserved[1:0] - config ops
   // 74:64   = dword count
   // 78:75   = request type
   // 79      = poisoned request
   // 87:80   = requester function/device
   // 95:88   = requester bus
   // 103:96  = tag
   // 119:104 = completer id
   // 120     = requester id enable (1 for root port)
   // 123:121 = transaction class
   // 126:124 = attributes
   // 127     = force ECRC

   reg [63:2] addr;
   reg  [1:0] addrtype;
   reg [10:0] dword_count;
   reg  [3:0] req_type;
   reg        poison;
   reg [15:0] requester_id;
   reg  [7:0] tag;
   reg [15:0] completer_id;
   reg        requester_id_en;
   reg  [2:0] trans_class;
   reg  [2:0] attrib;
   reg        force_ecrc;
   
   // client tag management is enabled
   // when disabled, xilinx core can manage tags for non-posted commands
   // and the allocated tag is returned on pcie_rq_tag/pcie_rq_tag_vld

   //-------------------------------------------------------    
   // rq_tuser sideband signals
   //-------------------------------------------------------    
   // 3:0     = first_be[3:0]
   // 7:4     = last_be[3:0]
   // 10:8    = addr_offset[2:0] (address aligned mode ?)
   // 11      = discontinue
   // 12      = TPH present
   // 14:13   = TPH type
   // 15      = TPH indirect tag enable
   // 23:16   = TPH steering tag
   // 27:24   = seq_num for tracking progress in tx pipeline
   // 59:28   = parity of tdata (if enabled)

   reg   [3:0] first_be;
   reg   [3:0] last_be;
   reg   [2:0] addr_offset;
   reg         discontinue;
   reg  [11:0] tph;
   reg   [3:0] seq_num;
   reg  [31:0] parity;
   reg  [15:0] tdatap_q, tdatap_d;
   wire [15:0] tdatap;

   always @*
     begin
        addr             = ctlff_txrq_addr[63:2];
        addrtype         = 2'b00;   // address is untranslated   
        if( ctlff_txrq_cfgop )
          begin      
             dword_count    = 11'd1;
          end
        else
          begin
             if( ctlff_txrq_be[7:4] != 4'h0 )
               begin
                  dword_count = 11'd2;
               end
             else
               begin
                  dword_count = 11'd1;
               end
          end
        case ( {ctlff_txrq_cfgop,ctlff_txrq_rnw} )
          2'b00:   req_type = 4'h1; // Memory Write Request
          2'b01:   req_type = 4'h0; // Memory Read Request
          2'b10:   req_type = 4'hA; // Type 0 Config Write
          default: req_type = 4'h8; // Type 0 Config Read
        endcase
        poison           = 1'b0;     // could force this for error inject
        requester_id     = 16'h0000; // bus[7:0],dev[4:0],func[2:0]        
        tag              = { 2'b00, ctlff_txrq_tag };
        completer_id     = 16'h0100;
        requester_id_en  = 1'b1;     // must be set for root complex
        trans_class      = 3'h0; 
        attrib           = 3'h0;     // {ID-Based Ordering, Relaxed Ordering, No Snoop}
        force_ecrc       = 1'b0;     // for error inject

        first_be         = ctlff_txrq_be[3:0];
        last_be          = ctlff_txrq_be[7:4];
        addr_offset      = 3'h0;     // not used because xilinx core is generated in dword alignment mode
        discontinue      = 1'b0;
        tph              = 12'h0;    // transaction processing hint not present
        seq_num          = 4'h0;     // not used (for tracking request internal to xilinx core)
        parity           = {16'h0000, tdatap_d};
     end
   
   // state machine for request interface
   reg [3:0]  state_q, state_d;
   localparam [3:0] S_IDLE = 4'h1;
   localparam [3:0] S_DESC = 4'h2;
   localparam [3:0] S_DATA = 4'h3;

   // request interface registers
   reg [127:0] tdata_q, tdata_d;
   reg   [3:0] tkeep_q, tkeep_d;
   reg         tlast_q, tlast_d;  
   reg  [59:0] tuser_q, tuser_d;
   reg         tvalid_q, tvalid_d;
   reg         txrq_pe_inj_d,txrq_pe_inj_q;
  
   always @(posedge user_clk or posedge user_reset)
     begin
        if( user_reset )
          begin
             state_q       <= S_IDLE;
             tdata_q       <= zero[127:0];
             tdatap_q      <= zero[127:0];
             tkeep_q       <= zero[3:0];
             tlast_q       <= 1'b0;
             tuser_q       <= zero[59:0];
             tvalid_q      <= 1'b0; 
             txrq_pe_inj_q <= 1'b0;       
          end
        else
          begin
             state_q       <= state_d;
             tdata_q       <= tdata_d;
             tdatap_q      <= tdatap_d;
             tkeep_q       <= tkeep_d;
             tlast_q       <= tlast_d;
             tuser_q       <= tuser_d;
             tvalid_q      <= tvalid_d;  
             txrq_pe_inj_q <= txrq_pe_inj_d;        
          end
     end


   always @*
     begin
        txrq_pe_inj_d = txrq_pe_inj_q;       
        if (user_regs_wdata_pe_errinj_valid  & regs_pcie_pe_errinj_valid & regs_xxx_pe_errinj_decode[15:8] == 4'h9)
          begin
             txrq_pe_inj_d  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
          end 
        if  (txrq_pe_inj_q & tvalid_q)
          txrq_pe_inj_d = 1'b0; 
     end  


   always @*
     begin        
        s_axis_rq_tdata   = {tdata_q[127:1],tdata_q[0] ^ txrq_pe_inj_q};
        s_axis_rq_tkeep   = tkeep_q;
        s_axis_rq_tlast   = tlast_q;       
        s_axis_rq_tuser   = tuser_q;        
        s_axis_rq_tvalid  = tvalid_q;

        state_d        = state_q;

        tdatap_d  =  tdatap;
        tdata_d = { force_ecrc,
                    attrib,
                    trans_class,
                    requester_id_en,
                    completer_id,
                    tag,
                    requester_id,
                    poison,
                    req_type,
                    dword_count,                   
                    addr,
                    addrtype
                    };
        tuser_d = {parity,
                   seq_num,
                   tph,
                   discontinue,
                   addr_offset,
                   last_be,
                   first_be
                   };
        tkeep_d = tkeep_q;
        tlast_d = tlast_q;
        tvalid_d = tvalid_q;

        txrq_ctlff_ack = 1'b0;
        
        case (state_q)
          S_IDLE:
            begin               
               if( ctlff_txrq_valid )
                 begin
                    state_d = S_DESC;
                    tvalid_d = 1'b1;                   
                    if( ctlff_txrq_rnw )
                      tlast_d = 1'b1;
                    else
                      tlast_d = 1'b0;
                    tkeep_d[3:0] = 4'hf;                    
                 end
            end
          S_DESC:
            begin
               if( s_axis_rq_tready==4'hF )
                 begin
                    txrq_ctlff_ack = 1'b1;
                    if( ctlff_txrq_rnw )
                      begin
                         // read - no payload
                         state_d   = S_IDLE;
                         tvalid_d  = 1'b0;
                         tlast_d   = 1'b0;
                         tkeep_d   = 4'h0;
                      end
                    else
                      begin
                         state_d   = S_DATA;
                         tlast_d   = 1'b1;
                         tkeep_d   = { 2'b00, (|last_be), (|first_be)};
                         tdatap_d  = tdatap;
                         tdata_d   = { zero[127:64], ctlff_txrq_data };
                      end
                 end
            end
          S_DATA:
            begin               
               tdatap_d  =  tdatap;
               tdata_d = tdata_q;
               if( s_axis_rq_tready==4'hF )
                 begin
                    state_d   = S_IDLE;
                    tvalid_d  = 1'b0;
                    tlast_d   = 1'b0;
                    tkeep_d   = 4'h0;
                 end
            end
          default:
            begin
               state_d = S_IDLE;
            end
        endcase // case (state_q)
        
     end

   // debug count
   (* mark_debug = "false" *) reg [19:0] tx_val_cnt_q;
   (* mark_debug = "false" *) reg [19:0] tx_packet_cnt_q;
   always @(posedge user_clk)
     begin
        if( user_reset )
          begin
             tx_val_cnt_q    <= 0;
             tx_packet_cnt_q <= 0;
          end
        else
          begin
             if(  s_axis_rq_tvalid & s_axis_rq_tready==4'hF )
               begin
                  if( s_axis_rq_tlast )
                    tx_packet_cnt_q <= tx_packet_cnt_q + 1;
                  tx_val_cnt_q <= tx_val_cnt_q + 1;
               end             
           end  
     end

   always @(posedge user_clk)
     begin
        txrq_dbg_user_tracedata[143:0] <= { tuser_q[10:0], tkeep_q[3:0], tlast_q, tdata_q};
        txrq_dbg_user_tracevalid <= tvalid_q & s_axis_rq_tready==4'hF;
     end
   
   nvme_pgen#(.bits_per_parity_bit(8), .width(128)) txrq_pgen
     (.data(tdata_d),
      .oddpar(1'b1),
      .datap(tdatap)
      );   

endmodule

