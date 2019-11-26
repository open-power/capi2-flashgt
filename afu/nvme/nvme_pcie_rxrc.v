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

// PCIe Receive Requester Completion
//
// Requests are transmitted by pcie_txrq. A request can originate
// from the the control unit, the Admin Q, or the IO Q but only
// the control unit can send non-posted requests Tags for the
// control unit have the upper 2 bits set to zero, while the
// adq/ioq tags have non-zero upper 2 bits.
//
// Only data lengths of 0B, 4B, or 8B are supported.
//

module nvme_pcie_rxrc
  #(
     parameter dummy = 0,
     parameter bits_per_parity_bit = 8
  )
  ( 
  
    output reg         rxrc_ctlff_valid,
    output reg  [63:0] rxrc_ctlff_data,
    output reg   [7:0] rxrc_ctlff_datap,
    output reg   [7:0] rxrc_ctlff_be,
    output reg   [7:0] rxrc_ctlff_tag,
    output reg         rxrc_ctlff_poison,
    output reg   [3:0] rxrc_ctlff_errcode,
    output reg   [2:0] rxrc_ctlff_status,
    input              ctlff_rxrc_ack,
 
    //-------------------------------------------------------
    //  Transaction (AXIS) Interface
    //   - Requester Completion  interface
    //-------------------------------------------------------    
    input              user_clk,
    input              user_reset,
    input              user_lnk_up,
    //-------------------------------------------------------    
  
    input      [127:0] m_axis_rc_tdata,
    input        [3:0] m_axis_rc_tkeep,
    input              m_axis_rc_tlast,
    output reg         m_axis_rc_tready,
    input       [74:0] m_axis_rc_tuser,
    input              m_axis_rc_tvalid,
    output             user_rxrc_perror_ind,
    input              regs_pcie_pe_errinj_valid,
    input       [15:0] regs_xxx_pe_errinj_decode, 
    input              user_regs_wdata_pe_errinj_valid, // 1 cycle pulse in nvme domain kch 

    output reg [143:0] rxrc_dbg_user_tracedata,
    output reg         rxrc_dbg_user_tracevalid

  
);
   
`include "nvme_func.svh"

   reg                 valid_q, valid_d;
   reg           [3:0] state_q, state_d;
   reg          [63:0] data_q, data_d;
   reg           [7:0] datap_q, datap_d;
   wire          [7:0] datap;
   reg           [7:0] be_q, be_d;
   reg           [7:0] tag_q, tag_d;
   reg                 poison_q, poison_d;
   reg           [3:0] errcode_q, errcode_d;
   reg           [2:0] status_q, status_d;
   reg                 int_error_q, int_error_d;
   reg                 rxrc_pe_inj_d,rxrc_pe_inj_q;
   
   localparam S_IDLE = 4'h1;
   localparam S_D1   = 4'h2;
   localparam S_ERR  = 4'h3;
   localparam S_CMP  = 4'h4;
   
   always @(posedge user_clk or posedge user_reset)
     begin
        if( user_reset )
          begin
             valid_q       <= 1'b0;
             state_q       <= S_IDLE;
             data_q        <= zero[63:0];
             datap_q       <= zero[7:0];
             be_q          <= zero[7:0];
             tag_q         <= zero[7:0];
             poison_q      <= 1'b0;
             errcode_q     <= zero[3:0];
             status_q      <= zero[2:0];
             int_error_q   <= 1'b0;
             rxrc_pe_inj_q <= 1'b0;
          end
        else
          begin
             valid_q       <= valid_d;
             state_q       <= state_d;
             data_q        <= data_d;
             datap_q       <= datap_d;
             be_q          <= be_d;
             tag_q         <= tag_d;
             poison_q      <= poison_d;
             errcode_q     <= errcode_d;
             status_q      <= status_d;
             int_error_q   <= int_error_d;
             rxrc_pe_inj_q <= rxrc_pe_inj_d;
          end
     end

   always @*
     begin        
        m_axis_rc_tready  = ~valid_q;

        valid_d           = valid_q & ~ctlff_rxrc_ack;
        state_d           = state_q;
        data_d            = data_q;        
        datap_d           = datap_q;        
        be_d              = be_q;
        tag_d             = tag_q;
        poison_d          = poison_q;
        errcode_d         = errcode_q;
        status_d          = status_q;
        int_error_d       = int_error_q;

        case(state_q)
          S_IDLE:
            begin
               if( m_axis_rc_tvalid & ~valid_q & user_lnk_up)
                 begin
                    // ignore completion if "request completed" isn't asserted
                    if( m_axis_rc_tdata[30] )
                      begin
                         if( m_axis_rc_tlast )
                           begin
                              state_d = S_IDLE;
                              valid_d = 1'b1;
                           end
                         else
                           begin
                              state_d = S_D1;
                           end
                         // lower address          = m_axis_rc_tdata[11:0];
                         errcode_d                 = m_axis_rc_tdata[15:12];
                         // byte_count             = m_axis_rc_tdata[28:16];  // todo: should be 0, 4, or 8
                         // locked read completion = m_axis_rc_tdata[29];                         
                         // dword_count            = m_axis_rc_tdata[42:32];  // todo: should be 0 or 1
                         status_d                  = m_axis_rc_tdata[45:43];
                         poison_d                  = m_axis_rc_tdata[46];
                         // requester_id           = m_axis_rc_tdata[63:48];
                         tag_d                     = m_axis_rc_tdata[71:64];
                         // completer_id           = m_axis_rc_tdata[87:72];
                         // transaction_class      = m_axis_rc_tdata[91:89];
                         // attributes             = m_axis_rc_tdata[94:92];
                         // note: requester_id,completer_id,transaction class, attributes are checked by the core
                         //       any error is reported in the errcode
                         datap_d                   = datap;
                         data_d[31:0]              = m_axis_rc_tdata[127:96]; // DW0, dword aligned mode
                         data_d[63:32]             = zero[63:32];
                         be_d[3:0]                 = m_axis_rc_tuser[15:12];
                         // parity[15:0]           = m_axis_rc_tuser[58:43]; 

                         // internal error - bad length or something else unexpected
                         int_error_d               = 1'b0; // todo

                         // m_axis_rc_tkeep - not used
                      end
                    else
                      begin
                         if( ~m_axis_rc_tlast )
                           state_d = S_ERR;
                      end
                 end
            end // case: S_IDLE
          
          S_D1:
            begin
               // get dword 1 for a 8B transfer
               if( ~user_lnk_up )
                 begin
                    state_d = S_IDLE;
                 end
               else if( m_axis_rc_tvalid )
                 begin
                    // expect only 1 dword with last set
                    if( m_axis_rc_tlast )
                      begin
                         valid_d        = 1'b1;
                         state_d        = S_IDLE;
                         datap_d        = datap;
                         data_d[63:32]  = m_axis_rc_tdata[31:0];  // DW1, dword aligned mode
                         be_d[7:4]      = m_axis_rc_tuser[3:0];
                         // todo: parity check
                         if( m_axis_rc_tuser[42] )
                           begin
                              // discontinue bit - core error detected reading payload
                              // todo: ignore entire TLP or just mark payload invalid?
                              int_error_d = 1'b1;
                           end
                      end
                    else
                      begin
                         int_error_d = 1'b1;
                      end
                 end
            end
          
          S_ERR:
            begin
               // wait for last indication for TLP with error
               if( m_axis_rc_tvalid & m_axis_rc_tlast )
                 begin
                    state_d = S_IDLE;
                 end
            end
     
          default:
            begin
            end
        endcase // case (state_q)
        
        // outputs
        rxrc_ctlff_valid    = valid_q;
        rxrc_ctlff_data     = data_q;
        rxrc_ctlff_datap    = datap_q;
        rxrc_ctlff_be       = be_q;
        rxrc_ctlff_tag      = tag_q;
        rxrc_ctlff_poison   = poison_q;
        rxrc_ctlff_errcode  = errcode_q;
        rxrc_ctlff_status   = status_q;
    end
   
   nvme_pgen#(.bits_per_parity_bit(8), .width(64)) rxrc_pgen
     (.data(data_d),
      .oddpar(1'b1),
      .datap(datap)
      );

   always @*
     begin       
        rxrc_pe_inj_d = rxrc_pe_inj_q;
        if (user_regs_wdata_pe_errinj_valid  & regs_pcie_pe_errinj_valid & regs_xxx_pe_errinj_decode[15:8] == 4'h7)
          begin
             rxrc_pe_inj_d  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
          end
        // don't bother to clear pe_inj_q here.  it caused a timing problem
        // and the parity error capture below doesn't get reset
        // if (rxrc_pe_inj_q & m_axis_rc_tvalid)
        //  rxrc_pe_inj_d = 1'b0;
     end 

   wire s1_uperror;

   nvme_pcheck#(.bits_per_parity_bit(8), .width(128)) rc_pchck_maxis
     (.data({m_axis_rc_tdata[127:1],(m_axis_rc_tdata[0]^rxrc_pe_inj_q)}),
      .oddpar(1'b1),
      .datap(m_axis_rc_tuser[58:43]),
      .check(m_axis_rc_tvalid),
      .parerr(s1_uperror)
      );

   // set/reset/ latch for parity errors kch 
   wire rxrc_uperror_int;

   nvme_srlat#
     (.width(1))  irxrc_sr   
       (.clk(user_clk),.reset(user_reset),.set_in(s1_uperror),.hold_out(rxrc_uperror_int));

   assign user_rxrc_perror_ind = rxrc_uperror_int;

   always @(posedge user_clk)
     begin
        rxrc_dbg_user_tracedata[143:0] <= {  m_axis_rc_tuser[42], m_axis_rc_tuser[15:12],  m_axis_rc_tuser[3:0], m_axis_rc_tkeep, m_axis_rc_tlast, m_axis_rc_tdata};
        rxrc_dbg_user_tracevalid       <=  m_axis_rc_tvalid & ~valid_q;
     end
   
                                    
endmodule

