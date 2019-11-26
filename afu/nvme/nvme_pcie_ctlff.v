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

// Surelock NVMe
// PCIe control request/response queue
//
// - handle requests and responses for nvme_control and
//   admin/io queue mmio doorbell writes
//
// - includes async crossing between PSL 250Mhz clock and
//   NVMe port's 250Mhz clock
//

module nvme_pcie_ctlff
  #(
    parameter clk_period = 4000,  // PSL clock period in ps
    parameter bits_per_parity_bit = 8
    )
   (
    input             clk,
    input             reset,

    //-------------------------------------------------------
    // ucontrol IO bus
    //-------------------------------------------------------
    input      [31:0] ctl_pcie_ioaddress,
    input             ctl_pcie_ioread_strobe, 
    input      [31:0] ctl_pcie_iowrite_data,
    input             ctl_pcie_iowrite_strobe,
    output reg [31:0] pcie_ctl_ioread_data,
    output reg  [3:0] pcie_ctl_ioread_datap,
    output reg        pcie_ctl_ioack,

    //-------------------------------------------------------
    // Admin Q doorbell write
    //-------------------------------------------------------
    input             adq_pcie_wrvalid,
    input      [31:0] adq_pcie_wraddr,
    input      [15:0] adq_pcie_wrdata,
    output reg        pcie_adq_wrack,
  
    //-------------------------------------------------------
    // I/O Q doorbell write
    //-------------------------------------------------------
    input             ioq_pcie_wrvalid,
    input      [31:0] ioq_pcie_wraddr,
    input      [15:0] ioq_pcie_wrdata,
    output reg        pcie_ioq_wrack, 

    
    //-------------------------------------------------------
    // debug access to PCIe/NVMe
    //-------------------------------------------------------
    input             regs_pcie_valid, // command valid
    output reg        pcie_regs_ack, // command taken
    input             regs_pcie_rnw, // read=1 write=0
    input             regs_pcie_configop,// configop=1 (pcie) mmio=0 (nvme)
    input       [3:0] regs_pcie_tag, // 4b tag for pcie op
    input       [3:0] regs_pcie_be, // 4b byte enable
    input      [31:0] regs_pcie_addr, // config reg # or mmio offset from NVME BAR
    input      [31:0] regs_pcie_wrdata,
    output reg [31:0] pcie_regs_cpl_data,
    output reg  [3:0] pcie_regs_cpl_datap, 
    output reg        pcie_regs_cpl_valid,
    output reg [15:0] pcie_regs_cpl_status, // be[7:0], poison, status[2:0], errcode[3:0];

    input             regs_xx_tick1, // 1 cycle pulse every 1 us

    //-------------------------------------------------------
    // status
    //-------------------------------------------------------
    output reg        pcie_xx_link_up,
    output reg        pcie_xx_init_done,

    output reg        ctlff_dbg_perst,

    //-------------------------------------------------------
    //  NVMe port clock domain
    //-------------------------------------------------------    
    input             user_clk,
    input             user_reset,
    input             user_lnk_up,
    //-------------------------------------------------------
    // requests to pcie
    //-------------------------------------------------------
    output reg        ctlff_txrq_valid,
    output reg        ctlff_txrq_rnw,
    output reg        ctlff_txrq_cfgop,
    output reg  [5:0] ctlff_txrq_tag,
    output reg [63:0] ctlff_txrq_addr,
    output reg [63:0] ctlff_txrq_data,
    output reg  [7:0] ctlff_txrq_datap,
    output reg  [7:0] ctlff_txrq_be,
    input             txrq_ctlff_ack,

    //-------------------------------------------------------
    // completions from pcie
    //-------------------------------------------------------
    input             rxrc_ctlff_valid,
    input      [63:0] rxrc_ctlff_data,
    input       [7:0] rxrc_ctlff_datap,
    input       [7:0] rxrc_ctlff_be,
    input       [7:0] rxrc_ctlff_tag,
    input             rxrc_ctlff_poison,
    input       [3:0] rxrc_ctlff_errcode,
    input       [2:0] rxrc_ctlff_status,
    output reg        ctlff_rxrc_ack,
   
    //------------------------------------------------------
    // parity error
   // -----------------------------------------------------
    input             regs_pcie_pe_errinj_valid,
    input      [15:0] regs_xxx_pe_errinj_decode, 
    input             user_regs_wdata_pe_errinj_valid,
    input             regs_wdata_pe_errinj_valid,
 
    output            user_ctlff_perror_ind,
    output            ctlff_perror_ind,


    // nvme clock domain trace signals
    output reg [63:0] ctlff_dbg_user_trace
 
);

`include "nvme_func.svh"

   localparam req_fifo_width = 64;  /* 512x72 is widest xilinx bram */
   //localparam req_fifo_pwidth = $rtoi($ceil($itor(req_fifo_width)/bits_per_parity_bit));
   localparam req_fifo_pwidth = ceildiv(req_fifo_width, bits_per_parity_bit);

   wire           s1_uperror;
   wire           ctlff_uperror_int;
   wire           s1_perror;
   wire           ctlff_perror_int;


   // set/reset/ latch for parity errors kch 
   nvme_srlat#
     (.width(1))  ictlff_sr  
       (.clk(user_clk),.reset(user_reset),.set_in(s1_uperror),.hold_out(ctlff_uperror_int));

   nvme_srlat#
     (.width(1))  ictlff_usr   
       (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(ctlff_perror_int));

   assign user_ctlff_perror_ind = ctlff_uperror_int;
   assign ctlff_perror_ind      = ctlff_perror_int;


   //-------------------------------------------------------
   // clock domain crossing - link status & reset from pcie core
   //-------------------------------------------------------

      

   wire clk_lnk_up_meta;
   nvme_cdc cdc_lnkup (.clk(clk),.d(user_lnk_up),.q(clk_lnk_up_meta));
   wire clk_reset_meta;
   nvme_cdc cdc_clk_reset (.clk(clk),.d(user_reset),.q(clk_reset_meta));

   always @(posedge clk)
     begin
        pcie_xx_link_up <= clk_lnk_up_meta;
     end   
   
   //-------------------------------------------------------
   // microcontroller interface
   //-------------------------------------------------------
   
   // ucontrol interface register byte offsets
   // 0x00 - cmd
   // 0x04 - status
   // 0x08 - data0 (lsb)
   // 0x0c - data1 (msb)
   // 0x10 - addr0 (msb)
   // 0x14 - addr1 (msb)
   // 0x18 - init_done flag
   // 0x1c - link_up flag
   // 0x20 - perst (write to 1 to assert perst#)
   // 0x24 - timeout in us
   
   // cmd reg:
   // 0 - valid
   // 1 - read
   // 2 - configop
   // 3 - reserved
   // 11:4 - byte enables
   // 15:12 - tag
   // 17:16 - reserved 
   // 23:18 - reg number (when configop is set)
   // 27:24 - ext reg number (when configop is set)
   // 30:28 - reserved
   // 31    - timeout disable

   // status reg:
   // 0     - command complete  - cleared when cmd.valid is set
   // 1     - command sent      - cleared when cmd.valid is set
   // 2     - set by link down  - cleared when cmd.valid is set
   // 3     - set by link reset - cleared when cmd.valid is set
   // 7:4   - errcode (xilinx pcie IP encode)
   //           x0 - normal
   //           x1 - poisoned
   //           x2 - error completion (UR, CA, CRS status)
   //           x3 - byte count mismatch
   //           x4 - req_id, tc, attr mismatch
   //           x5 - starting address mismatch
   //           x6 - invalid tag
   //           x8 - function level reset
   //           x9 - completion timeout 
   // 10:8  - status
   //           x0 - success
   //           x1 - UR unsupported request
   //           x2 - CRS configuration request retry status
   //           x4 - CA completer abort
   // 11    - poison
   // 19:12 - byte enables
   // 22:20 - reserved
   // 23    - timeout indicator when timeout completion is disabled by cmd_q[31]=1
   // 31:24 - reserved zero
   
   reg     [31:0] cmd_q,   cmd_d;
   reg     [31:0] status_q, status_d;
   reg     [31:0] data0_q, data0_d;
   reg     [31:0] data1_q, data1_d;
   reg     [31:0] addr0_q, addr0_d;
   reg     [31:0] addr1_q, addr1_d;
   reg     [31:0] rddata_q, rddata_d;
   wire    [3:0]  rddatap;   // added kch 
   reg     [3:0]  rddatap_q, rddatap_d;
   reg            ack_q,   ack_d;
   reg            init_done_q, init_done_d;
   reg            link_up_q, link_up_d;
   reg            perst_q, perst_d;
   reg     [19:0] cpl_timeout_q, cpl_timeout_d;
   //   reg            ack_q,   ack_d;

`ifdef SIM
   localparam ctl_np_timeout = 20'd20;
`else
   localparam ctl_np_timeout = 20'd900000;
`endif
   reg     [19:0] timeout_q, timeout_d;
   reg            timeout_valid;

   reg            ctl_valid;
   reg            ctl_ack;
   
   // completion interface - ucontrol non-posted ops only
   reg            cmp_valid;
   reg     [63:0] cmp_data;
   wire     [3:0] cmp_datap;
   reg      [7:0] cmp_be;
   reg      [7:0] cmp_tag;
   reg            cmp_poison;
   reg      [3:0] cmp_errcode;
   reg      [2:0] cmp_status;
   

   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             cmd_q         <= zero[31:0];
             status_q      <= zero[31:0];
             data0_q       <= zero[31:0];
             data1_q       <= zero[31:0];
             addr0_q       <= zero[31:0];
             addr1_q       <= zero[31:0];
             rddata_q      <= zero[31:0];
             rddatap_q     <= zero[3:0];
             ack_q         <= 1'b0;
             init_done_q   <= 1'b0;
             link_up_q     <= 1'b0;
             timeout_q     <= 16'h0;
             cpl_timeout_q <= ctl_np_timeout;
             perst_q       <= 1'b0;
          end
        else
          begin
             cmd_q         <= cmd_d;
             status_q      <= status_d;
             data0_q       <= data0_d;
             data1_q       <= data1_d;
             addr0_q       <= addr0_d;
             addr1_q       <= addr1_d;   
             rddata_q      <= rddata_d;
             rddatap_q     <= rddatap_d;
             ack_q         <= ack_d;
             init_done_q   <= init_done_d;
             link_up_q     <= link_up_d;
             timeout_q     <= timeout_d;
             cpl_timeout_q <= cpl_timeout_d;
             perst_q       <= perst_d;
          end
     end

   //-------------------------------------------------------
   // microcontroller interface registers
   always @*
     begin

        /* arbitration request */
        ctl_valid        = cmd_q[0] & ~status_q[1];

        cmd_d            = cmd_q;
        status_d[0]      = status_q[0];           // command complete
        status_d[1]      = status_q[1] | ctl_ack; // command sent
        status_d[2]      = status_q[2] | ~link_up_q;
        status_d[3]      = status_q[3] | clk_reset_meta;    // user_reset
        status_d[23:4]   = status_q[23:4];
        status_d[31:24]  = zero[31:24]; // reserved, not implemented
        data0_d          = data0_q;
        data1_d          = data1_q;
        addr0_d          = addr0_q;
        addr1_d          = addr1_q;
        ack_d            = 1'b0;
        rddata_d         = rddata_q;
        rddatap_d        = rddatap_q ; // added kch 
        cpl_timeout_d    = cpl_timeout_q;

        init_done_d      = init_done_q; // cleared if link up goes inactive after pcie init is completed
        link_up_d        = link_up_q;  // cleared if link up goes inactive after pcie init starts
        perst_d          = 1'b0;
        ctlff_dbg_perst  = perst_q;
        
        // decode lower address bits for register access from microcontroller

        if( timeout_valid )
          begin
             if( cmd_q[31]== 1'b1)
               begin
                  // timeout is disabled, just report via status
                  status_d[23]=1'b1;
               end
             else
               begin
                  status_d[0]      = 1'b1;     // command complete
                  status_d[7:4]    = 4'b1001;  // use completion timeout error code from xilinx interface
               end
          end
                        
        if( ctl_pcie_iowrite_strobe )
          begin
             ack_d = 1'b1;
             case (ctl_pcie_ioaddress[7:0])
               8'h00: 
                 begin
                    cmd_d    = ctl_pcie_iowrite_data;
                    // clear completion flags for new command if valid=1
                    if( ctl_pcie_iowrite_data[0] )
                      status_d[3:0] = 4'b0000;  
                 end
               8'h08: data0_d        = ctl_pcie_iowrite_data;
               8'h0c: data1_d        = ctl_pcie_iowrite_data;
               8'h10: addr0_d        = ctl_pcie_iowrite_data;
               8'h14: addr1_d        = ctl_pcie_iowrite_data;
               8'h18: init_done_d    = 1'b1;  // microcode indicates PCIe init completed
               8'h1c: link_up_d      = 1'b1; // microcode indicates PCIe init started
               8'h20: perst_d        = 1'b1;
               8'h24: cpl_timeout_d  = ctl_pcie_iowrite_data[19:0];
               default:
                 begin
                 end
             endcase // case (ctl_pcie_ioaddress[7:0])                        
          end

        if (ctl_pcie_ioread_strobe )
          begin
             ack_d = 1'b1;
             rddatap_d     = rddatap ; // added kch 
             case (ctl_pcie_ioaddress[7:0])
               8'h00: rddata_d  = cmd_q;
               8'h04: rddata_d  = status_q;
               8'h08: rddata_d  = data0_q;
               8'h0c: rddata_d  = data1_q;
               8'h10: rddata_d  = addr0_q;
               8'h14: rddata_d  = addr1_q;
               8'h18: rddata_d  = {31'h0, init_done_q};
               8'h1c: rddata_d  = {31'h0, link_up_q};
               8'h20: rddata_d  = 32'h0;
               8'h24: rddata_d  = {12'h0, cpl_timeout_q};
               default:
                 begin 
                    // nop, ucode bug
                    rddata_d = 32'h0;
                 end
             endcase
          end

        if( cmp_valid )
          begin
             if( cmp_tag[5:0] == { 2'b00, cmd_q[15:12] } )
               begin
                  status_d[0]      = 1'b1;  // command complete
                  if( cmd_q[1] )
                    begin
                       data0_d     = cmp_data[31:0];
                       data1_d     = cmp_data[63:32];
                    end
                  status_d[7:4]    = cmp_errcode;
                  status_d[10:8]   = cmp_status;
                  status_d[11]     = cmp_poison;
                  status_d[19:12]  = cmp_be;      
               end
             else if( cmp_tag[5:4]!=2'b11 )             
               begin
                  // mismatched tag in completion
                  // currently just ignore this
               end
          end

        // reset init done flag if the link goes down
        if( ~clk_lnk_up_meta )
          begin
             init_done_d = 1'b0;
             link_up_d = 1'b0;
          end        
        
        pcie_xx_init_done = init_done_q;
        
        
        pcie_ctl_ioread_data  = rddata_q;
        pcie_ctl_ioread_datap = rddatap_q;
        pcie_ctl_ioack        = ack_q;
     end // always @ *


   
   always @*
     begin
        timeout_valid = 1'b0;
        timeout_d = timeout_q;
   
        // if ucontroller pcie request is valid and not completed
        // timeout counts down to zero
        // 50ms timeout
        // 9/19/16 - make timeout controllable by microcode for SW363607
        if( cmd_q[0] & ~status_q[0])
          begin
             if( timeout_q==20'h0 )
               begin
                  timeout_valid = 1;
               end
             else
               begin
                  if( regs_xx_tick1 )  // 1us
                    begin
                       timeout_d = timeout_q-20'd1;
                    end
               end
          end
        else
          begin            
             timeout_d = cpl_timeout_q;
          end
     end
   

   reg regs_valid;
   always @*
     begin
        regs_valid            = regs_pcie_valid & ~pcie_regs_ack;
        pcie_regs_cpl_valid   = cmp_valid & cmp_tag[5:4]==2'b11;
        pcie_regs_cpl_data    = cmp_data[31:0];
        pcie_regs_cpl_datap   = cmp_datap[3:0];
        pcie_regs_cpl_status  = {cmp_be, cmp_poison, cmp_status, cmp_errcode}; 
     end


   //-------------------------------------------------------
   
  
   reg             adq_valid_q, adq_valid_d;
   reg      [31:0] adq_addr_q, adq_addr_d;
   reg      [15:0] adq_data_q, adq_data_d;
   reg             adq_ack;
  
   reg             ioq_valid_q, ioq_valid_d;
   reg      [31:0] ioq_addr_q, ioq_addr_d;
   reg      [15:0] ioq_data_q, ioq_data_d;
   reg             ioq_ack;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             adq_valid_q <= 1'b0;
             adq_addr_q  <= 32'h0;
             adq_data_q  <= 16'h0;
             ioq_valid_q <= 1'b0;
             ioq_addr_q  <= 32'h0;
             ioq_data_q  <= 16'h0;
          end
        else
          begin
             adq_valid_q <= adq_valid_d;
             adq_addr_q  <= adq_addr_d;
             adq_data_q  <= adq_data_d;
             ioq_valid_q <= ioq_valid_d;
             ioq_addr_q  <= ioq_addr_d;
             ioq_data_q  <= ioq_data_d;
          end
     end

   always @*
     begin
        if( adq_pcie_wrvalid & ~adq_valid_q )
          begin
             adq_valid_d     = 1'b1;
             adq_addr_d      = adq_pcie_wraddr;
             adq_data_d      = adq_pcie_wrdata;
             pcie_adq_wrack  = 1'b1;
          end
        else
          begin
             pcie_adq_wrack  = 1'b0;
             adq_valid_d     = adq_valid_q & ~adq_ack;
             adq_addr_d      = adq_addr_q;
             adq_data_d      = adq_data_q;             
          end                
     end   

   always @*
     begin
        if( ioq_pcie_wrvalid & ~ioq_valid_q )
          begin
             ioq_valid_d     = 1'b1;
             ioq_addr_d      = ioq_pcie_wraddr;
             ioq_data_d      = ioq_pcie_wrdata;
             pcie_ioq_wrack  = 1'b1;
          end
        else
          begin
             pcie_ioq_wrack  = 1'b0;
             ioq_valid_d     = ioq_valid_q & ~ioq_ack;
             ioq_addr_d      = ioq_addr_q;
             ioq_data_d      = ioq_data_q;             
          end                
     end   
                  
   //-------------------------------------------------------
   // arbitration

   localparam req_rr_width=4;
   reg [req_rr_width-1:0] req_rr_valid;
   reg [req_rr_width-1:0] req_rr_q, req_rr_d;
   reg [req_rr_width-1:0] req_rr_gnt_q, req_rr_gnt_d;
   reg  [31:req_rr_width] req_rr_noused;

   reg                    ioq_gnt, adq_gnt, ctl_gnt, regs_gnt;
   
   reg             [31:0] req_cmd;
   reg             [63:0] req_addr;
   reg             [63:0] req_data;
   reg                    req_valid;
   reg                    req_taken;
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             req_rr_q     <= one[req_rr_width-1:0];
             req_rr_gnt_q <= zero[req_rr_width-1:0];
          end
        else
          begin
             req_rr_q     <= req_rr_d;             
             req_rr_gnt_q <= req_rr_gnt_d;             
          end
     end

   always @*
     begin

        ioq_ack = 1'b0;
        adq_ack = 1'b0;
        ctl_ack = 1'b0;
        pcie_regs_ack = 1'b0;
        
        req_valid = 1'b0;
        // default to ioq_gnt for timing
        req_cmd = 32'h000100F1;
        req_data = { 32'h0, ioq_data_q };
        req_addr = { NVME_BAR1, NVME_BAR0 | ioq_addr_q};
        
        req_rr_valid = {ioq_valid_q, adq_valid_q, ctl_valid, regs_valid } & ~req_rr_gnt_q;

        if( req_rr_gnt_q == zero[req_rr_width-1:0] || req_taken )
          {req_rr_noused, req_rr_gnt_d} = roundrobin({zero[31:req_rr_width],req_rr_valid}, {zero[31:req_rr_width], req_rr_q} );
        else
          req_rr_gnt_d = req_rr_gnt_q;

        if( (|req_rr_gnt_d) )
          req_rr_d = req_rr_gnt_d;
        else
          req_rr_d = req_rr_q;

        // mux cmd/data/address with registered grant - held until req_taken
        { ioq_gnt, adq_gnt, ctl_gnt, regs_gnt } = req_rr_gnt_q;
       
        if( ioq_gnt )
          begin      
             req_valid = 1'b1;
             req_cmd = 32'h000100F1;
             req_data = { 32'h0, ioq_data_q };
             req_addr = { NVME_BAR1, NVME_BAR0 | ioq_addr_q};
             if( req_taken )
               begin
                  ioq_ack = 1'b1;
               end
          end
        if( adq_gnt )
          begin      
             req_valid = 1'b1;
             req_cmd = 32'h000200F1;
             req_data = { 32'h0, adq_data_q };
             req_addr = { NVME_BAR1, NVME_BAR0 | adq_addr_q };
             if( req_taken )
               begin
                  adq_ack = 1'b1;
               end
          end
        if( ctl_gnt )
          begin      
             req_valid = 1'b1;
             req_cmd = cmd_q;
             req_data = {data1_q, data0_q};
             req_addr = {addr1_q, addr0_q};
             if( req_taken )
               begin
                  ctl_ack = 1'b1;
               end
          end
        if( regs_gnt )
          begin      
             req_valid = 1'b1;
             req_cmd = { 4'h0, regs_pcie_addr[9:0], 2'b11, regs_pcie_tag, 4'h0, regs_pcie_be, 1'b0, regs_pcie_configop, regs_pcie_rnw, 1'b1};
             req_data = {32'h0, regs_pcie_wrdata};
             req_addr = {NVME_BAR1, NVME_BAR0 | regs_pcie_addr };
             if( req_taken )
               begin
                  pcie_regs_ack = 1'b1;
               end
          end      
     end

   
   //-------------------------------------------------------
   // when command valid is set, transfer command/address/data to fifo
   
   reg [3:0] rq_wstate_q, rq_wstate_d;
   localparam RQW_IDLE = 4'h1;
   localparam RQW_ADDR = 4'h2;
   localparam RQW_DATA = 4'h3;

      
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             rq_wstate_q <= RQW_IDLE;             
          end
        else
          begin
             rq_wstate_q <= rq_wstate_d;           
          end
     end

   reg  [ req_fifo_width-1:0] rq_wdata;
   wire [req_fifo_pwidth-1:0] rq_wdatap;
   reg                        rq_write;
   wire                       rq_wfull;
   wire                       rq_wrstbusy;
   wire                       rq_wready;
   assign rq_wready = ~rq_wfull & ~rq_wrstbusy;

   always @*
     begin
        rq_wstate_d  = rq_wstate_q;
        rq_wdata     = {zero[63:32],req_cmd};
        rq_write     = 1'b0;
        req_taken    = 1'b0;
   
        
        case (rq_wstate_q)
          RQW_IDLE:
            begin
               if( rq_wready &&
                   clk_lnk_up_meta && // link is up
                   ~clk_reset_meta && // and pcie is not in reset
                   req_valid ) 
                 begin
                    rq_wstate_d = RQW_ADDR;
                    rq_write = 1'b1;
                 end
            end    
      
          RQW_ADDR:
            begin
               rq_wdata = req_addr;
               if( rq_wready )
                 begin
                    rq_wstate_d = RQW_DATA;
                    rq_write = 1'b1;                    
                 end
            end

          RQW_DATA:
            begin
               rq_wdata = req_data;
               if( rq_wready )
                 begin
                    rq_wstate_d = RQW_IDLE;
                    rq_write = 1'b1;
                    req_taken = 1'b1;
                 end
            end
 
          default:
            begin
               rq_wstate_d = RQW_IDLE;
            end
        endcase
     end // always @ *


   nvme_pgen#(.bits_per_parity_bit(8), .width(32)) rddata_d_pgen
     (.data(rddata_d),
      .oddpar(1'b1),
      .datap(rddatap)
      );

   nvme_pgen#(.bits_per_parity_bit(8), .width(req_fifo_width)) rq_wdata_pgen
     (.data(rq_wdata),
      .oddpar(1'b1),
      .datap(rq_wdatap)
      );
   
   //-------------------------------------------------------
   // Async fifo for domain crossing
   //-------------------------------------------------------

   reg                        rq_rack; 
   wire  [req_fifo_width-1:0] rq_rdata;
   wire [req_fifo_pwidth-1:0] rq_rdatap;
   wire                       rq_rval;
   wire                       rq_rerr;
   
   // requests PSL->NVMe

   nvme_cdc_fifo_xil#
     (.width(req_fifo_pwidth+req_fifo_width)
      ) req_fifo
       (
        // write
        .wclk                           (clk),
        .wreset                         (reset),
        .write                          (rq_write),
        .wdata                          ({rq_wdatap, rq_wdata}),
        .wfull                          (rq_wfull),
        .wrstbusy                       (rq_wrstbusy),
        // .wafull	                        (),
        .werror                         (),

        // read
        .rclk                           (user_clk),
        .rreset                         (user_reset),
        .rack                           (rq_rack),
        .rdata                          ({rq_rdatap, rq_rdata}),
        .rval                           (rq_rval),
        .runderflow                     (rq_rerr),
        .rsbe                           (),
        .rue                            (),
        .rempty                         (),
        .rrstbusy                       ()
        );


   //-------------------------------------------------------
   // NVME clock domain logic
   //-------------------------------------------------------

   // clock domain crossing - reset from PSL domain
   wire                       user_clk_reset_meta;
   nvme_cdc cdc_user_reset (.clk(user_clk),.d(reset),.q(user_clk_reset_meta));

   // create 1 cycle pulse in nvme domain to inject pe
   reg                        ctlff_pe_inj_d,ctlff_pe_inj_q;

   always @(posedge user_clk or posedge user_reset)
     begin
        if( user_reset )
          begin
             ctlff_pe_inj_q  <= 1'b0;        
          end
        else
          begin
             ctlff_pe_inj_q  <= ctlff_pe_inj_d;                
          end
     end
   
   reg        rq_rvalid_q, rq_rvalid_d;
   wire       cmp_rval;

   always @*
     begin
        ctlff_pe_inj_d   = ctlff_pe_inj_q;        
        
        if (regs_wdata_pe_errinj_valid & regs_pcie_pe_errinj_valid & regs_xxx_pe_errinj_decode[15:8] == 4'h9)
          begin
             ctlff_pe_inj_d  = (regs_xxx_pe_errinj_decode[3:0]==4'h1);
          end 
        if (cmp_rval & ctlff_pe_inj_q) 
          ctlff_pe_inj_d =1'b0;           
     end  
   

   
   reg        rq_rrnw_q, rq_rrnw_d;
   reg        rq_rcfgop_q, rq_rcfgop_d;
   reg  [5:0] rq_rtag_q, rq_rtag_d;
   reg [63:0] rq_raddr_q, rq_raddr_d;
   reg [63:0] rq_rdata_q, rq_rdata_d;
   reg  [7:0] rq_rdatap_q, rq_rdatap_d;
   reg  [7:0] rq_rbe_q, rq_rbe_d; 
   
   // read command from fifo
         
   reg [3:0] rq_rstate_q, rq_rstate_d;
   localparam RQR_IDLE = 4'h1;
   localparam RQR_ADDR = 4'h2;
   localparam RQR_DATA = 4'h3;
   localparam RQR_CMP  = 4'h4;   

   reg        user_ctlff_pe_inj_d,user_ctlff_pe_inj_q;

   always @(posedge user_clk or posedge user_reset)
     begin
        if( user_reset )
          begin
             rq_rstate_q         <= RQR_IDLE;   
             rq_rvalid_q         <= 1'b0;
             rq_rrnw_q           <= 1'b0;
             rq_rcfgop_q         <= 1'b0;
             rq_rtag_q           <= 4'h0;
             rq_raddr_q          <= zero[63:0];
             rq_rdata_q          <= zero[63:0];
             rq_rdatap_q         <= zero[63:0];
             rq_rbe_q            <= zero[7:0]; 
             user_ctlff_pe_inj_q <= 1'b0;            
          end
        else
          begin
             rq_rstate_q         <= rq_rstate_d;           
             rq_rvalid_q         <= rq_rvalid_d;
             rq_rrnw_q           <= rq_rrnw_d;
             rq_rcfgop_q         <= rq_rcfgop_d;
             rq_rtag_q           <= rq_rtag_d;
             rq_raddr_q          <= rq_raddr_d;
             rq_rdata_q          <= rq_rdata_d;
             rq_rdatap_q         <= rq_rdatap_d;
             rq_rbe_q            <= rq_rbe_d;
             user_ctlff_pe_inj_q <= user_ctlff_pe_inj_d;
          end
     end

   always @*
     begin
        user_ctlff_pe_inj_d  = user_ctlff_pe_inj_q;        
        
        if (user_regs_wdata_pe_errinj_valid & regs_pcie_pe_errinj_valid & regs_xxx_pe_errinj_decode[15:8] == 4'h9)
          begin
             user_ctlff_pe_inj_d  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
          end 
        if (rq_rvalid_q & user_ctlff_pe_inj_q) 
          user_ctlff_pe_inj_d = 1'b0;
     end  
   

    always @*
     begin
        rq_rstate_d  = rq_rstate_q;
        rq_rvalid_d  = rq_rvalid_q;
        rq_rrnw_d    = rq_rrnw_q;
        rq_rcfgop_d  = rq_rcfgop_q;
        rq_rtag_d    = rq_rtag_q;
        rq_raddr_d   = rq_raddr_q;
        rq_rdata_d   = rq_rdata_q;
        rq_rdatap_d  = rq_rdatap;
        rq_rbe_d     = rq_rbe_q;

        rq_rack      = 1'b0;
        
        case (rq_rstate_q)
          RQR_IDLE:
            begin
               if( rq_rval && 
                   ~rq_rvalid_q )
                 begin
                    rq_rstate_d  = RQR_ADDR;
                    rq_rack      = 1'b1;
                    // 0 - valid
                    // 1 - read
                    // 2 - configop
                    // 3 - reserved
                    // 11:4 - byte enables
                    // 17:12 - tag                    
                    // 23:18 - reg number  (when configop is set)
                    // 27:24 - ext reg number (when configop is set)
                    rq_rrnw_d    = rq_rdata[1];
                    rq_rcfgop_d  = rq_rdata[2];
                    rq_rbe_d     = rq_rdata[11:4];
                    rq_rtag_d    = rq_rdata[17:12];
                    rq_raddr_d   = { zero[63:12], rq_rdata[27:18], zero[1:0] };                           
                 end
            end
          
          RQR_ADDR:
            begin               
               if( rq_rval )
                 begin
                    rq_rstate_d = RQR_DATA;
                    rq_rack = 1'b1;                 
                    if( ~rq_rcfgop_q )
                      rq_raddr_d[63:0] = rq_rdata;
                 end
            end

          RQR_DATA:
            begin
              if( rq_rval )
                 begin
                    rq_rstate_d = RQR_CMP;
                    rq_rack = 1'b1;
                    rq_rvalid_d = 1'b1;
                    rq_rdata_d[63:0] = rq_rdata;
                 end	
            end

          RQR_CMP:
            begin
               if( txrq_ctlff_ack )
                 begin
                    rq_rstate_d = RQR_IDLE;
                    rq_rvalid_d = 1'b0;
                 end
            end
          
          default:
            begin
               rq_rstate_d = RQR_IDLE;
            end
        endcase // case (rq_rstate_q)

        // if the PSL clock domain is reset,
        // any requests in progress here are dropped
        if( user_clk_reset_meta )
          begin
             rq_rvalid_d = 1'b0;
             rq_rstate_d = RQR_IDLE;
          end
        
        ctlff_txrq_valid  = rq_rvalid_q;
        ctlff_txrq_rnw    = rq_rrnw_q;
        ctlff_txrq_cfgop  = rq_rcfgop_q;
        ctlff_txrq_tag    = rq_rtag_q;
        ctlff_txrq_addr   = rq_raddr_q;
        ctlff_txrq_data   = rq_rdata_q;
        ctlff_txrq_datap  = rq_rdatap_q;
        ctlff_txrq_be     = rq_rbe_q;  
     end


   nvme_pcheck#(.bits_per_parity_bit(8), .width(64)) pchck_rq_rdata
     (.data({rq_rdata[63:1],(rq_rdata[0]^user_ctlff_pe_inj_q)}),
      .oddpar(1'b1),
      .datap(rq_rdatap),
      .check(rq_rval),
      .parerr(s1_uperror)   // user_clk kch
      );

   //-------------------------------------------------------
   // PSL clock domain logic - completions
   //-------------------------------------------------------

   // read completion info from fifo and set cmp_* interface
   // which is used to set cmd/status/data registers above
   
   localparam cmp_fifo_width = 32;
   //localparam cmp_fifo_pwidth = $rtoi($ceil($itor(cmp_fifo_width)/bits_per_parity_bit));
   localparam cmp_fifo_pwidth = ceildiv(cmp_fifo_width, bits_per_parity_bit);
   
   reg                        cmp_rack; 
   wire  [cmp_fifo_width-1:0] cmp_rdata;
   wire [cmp_fifo_pwidth-1:0] cmp_rdatap;
   wire                       cmp_rerr;

   localparam CMPR_IDLE = 4'h1;
   localparam CMPR_D0   = 4'h2;
   localparam CMPR_D1   = 4'h3;
   reg                 [3:0] cmp_rstate_q, cmp_rstate_d;
   
   reg                       cmp_rvalid_q, cmp_rvalid_d;
   reg                [63:0] cmp_rdata_q, cmp_rdata_d;
   reg                 [7:0] cmp_rbe_q, cmp_rbe_d;
   reg                 [7:0] cmp_rtag_q, cmp_rtag_d;
   reg                       cmp_rpoison_q, cmp_rpoison_d;
   reg                 [3:0] cmp_rerrcode_q, cmp_rerrcode_d;
   reg                 [2:0] cmp_rstatus_q, cmp_rstatus_d;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             cmp_rstate_q   <= CMPR_IDLE;
             cmp_rvalid_q   <= 1'b0;
             cmp_rdata_q    <= zero[63:0];        
             cmp_rbe_q      <= zero[7:0];
             cmp_rtag_q     <= zero[7:0];
             cmp_rpoison_q  <= 1'b0;
             cmp_rerrcode_q <= zero[3:0];
             cmp_rstatus_q  <= zero[2:0];
          end
        else
          begin
             cmp_rstate_q   <= cmp_rstate_d;
             cmp_rvalid_q   <= cmp_rvalid_d;
             cmp_rdata_q    <= cmp_rdata_d;
             cmp_rbe_q      <= cmp_rbe_d;
             cmp_rtag_q     <= cmp_rtag_d;
             cmp_rpoison_q  <= cmp_rpoison_d;
             cmp_rerrcode_q <= cmp_rerrcode_d;
             cmp_rstatus_q  <= cmp_rstatus_d;
          end
     end
   
   always @*
     begin

        cmp_rstate_d   = cmp_rstate_q;
        cmp_rvalid_d   = cmp_rvalid_q;
        cmp_rdata_d    = cmp_rdata_q;
        cmp_rbe_d      = cmp_rbe_q;
        cmp_rtag_d     = cmp_rtag_q;
        cmp_rpoison_d  = cmp_rpoison_q;
        cmp_rerrcode_d = cmp_rerrcode_q;
        cmp_rstatus_d  = cmp_rstatus_q;

        cmp_rack = 1'b0;
        case(cmp_rstate_q)
          CMPR_IDLE:
            begin
               cmp_rvalid_d = 1'b0;
               if( cmp_rval )
                 begin
                    { cmp_rpoison_d, cmp_rstatus_d, cmp_rerrcode_d, cmp_rtag_d, cmp_rbe_d } = cmp_rdata[23:0];
                    cmp_rstate_d = CMPR_D0;
                    cmp_rack = 1'b1;
                 end
            end
          CMPR_D0:
            begin
               if( cmp_rval )
                 begin
                    cmp_rdata_d[31:0] = cmp_rdata;
                    cmp_rstate_d = CMPR_D1;
                    cmp_rack = 1'b1;
                 end
            end
          CMPR_D1:
            begin
               if( cmp_rval )
                 begin
                    cmp_rdata_d[63:32] = cmp_rdata;
                    cmp_rstate_d = CMPR_IDLE;
                    cmp_rack = 1'b1;
                    cmp_rvalid_d = 1'b1;
                 end
            end
          default:
            begin
               cmp_rstate_d = CMPR_IDLE;
            end
        endcase // case (cmp_rstate_q)
                
        // interface to command/status registers
        cmp_valid    = cmp_rvalid_q;
        cmp_data     = cmp_rdata_q;        
        cmp_be       = cmp_rbe_q;
        cmp_tag      = cmp_rtag_q;
        cmp_poison   = cmp_rpoison_q;
        cmp_errcode  = cmp_rerrcode_q;
        cmp_status   = cmp_rstatus_q;
     end

   //Gen parity again for new data format

   //Check parity of data out of async fifo
   nvme_pcheck#(.bits_per_parity_bit(8), .width(cmp_fifo_width)) rc_pchck_cmp_rdata
     (.data({cmp_rdata[31:1],(cmp_rdata[0]^ctlff_pe_inj_q)}),
      .oddpar(1'b1),
      .datap(cmp_rdatap),
      .check(cmp_rval),
      .parerr(s1_perror)   // clk
      );

   nvme_pgen#(.bits_per_parity_bit(8), .width(32)) cmp_data_pgen
     (.data(cmp_data[31:0]),
      .oddpar(1'b1),
      .datap(cmp_datap)
      );

   //-------------------------------------------------------
   // Async fifo for domain crossing
   //-------------------------------------------------------
   
   reg  [cmp_fifo_width-1:0] cmp_wdata;
   wire [cmp_fifo_pwidth-1:0] cmp_wdatap;
   reg                       cmp_write;
   wire                      cmp_wfull;
   wire                      cmp_rrstbusy;

   wire                      cmp_wrstbusy;
   wire                      cmp_wready;
   wire                      cmp_rempty;
   wire                      cmp_werror;
   
   assign cmp_wready = ~cmp_wfull & ~cmp_wrstbusy;
   
//   nvme_async_fifo#
//     ( .width(cmp_fifo_width),
//       .awidth(3)

   nvme_cdc_fifo_xil#
     (.width(cmp_fifo_pwidth + cmp_fifo_width)
       ) cmp_fifo
       (
        // read
        .rclk                           (clk),
        .rreset                         (reset),
        .rack                           (cmp_rack),
        .rdata                          ({cmp_rdatap, cmp_rdata}),
        .rval                           (cmp_rval),
        .runderflow                     (cmp_rerr),         
        .rsbe                           (),
        .rue                            (),
        .rempty                         (cmp_rempty),
        .rrstbusy			(cmp_rrstbusy),

        // write
        .wclk                           (user_clk),
        .wreset                         (user_reset),
        .write                          (cmp_write),
        .wdata                          ({cmp_wdatap, cmp_wdata}),
        .wfull                          (cmp_wfull),
        .wrstbusy                       (cmp_wrstbusy),
        //.wafull	                        ()
        .werror                         (cmp_werror)
        );


   //-------------------------------------------------------
   // NVME clock domain logic
   //-------------------------------------------------------

   // write completions from pcie into fifo
   // cycle 0: {8'h0,poison,status,errcode,tag,be}
   // cycle 1: data[31:0]
   // cycle 2: data[63:32]

   localparam CMPW_IDLE = 4'h1;
   localparam CMPW_D0   = 4'h2;
   localparam CMPW_D1   = 4'h3;
   reg                 [3:0] cmp_wstate_q, cmp_wstate_d;

   always @(posedge user_clk or posedge user_reset)
     begin
        if( user_reset )
          begin
             cmp_wstate_q <= CMPW_IDLE;
          end
        else
          begin
             cmp_wstate_q <= cmp_wstate_d;
          end
     end
   
   always @*
     begin
        cmp_write = 1'b0;
        cmp_wdata = {zero[31:24], rxrc_ctlff_poison,rxrc_ctlff_status,rxrc_ctlff_errcode, rxrc_ctlff_tag,rxrc_ctlff_be};
        cmp_wstate_d = cmp_wstate_q;
        ctlff_rxrc_ack = 1'b0;

        case(cmp_wstate_q)
          CMPW_IDLE:
            begin
               if( cmp_wready &
                   rxrc_ctlff_valid )
                 begin
                    cmp_wstate_d = CMPW_D0;
                    cmp_write = 1'b1;                    
                 end
            end
          CMPW_D0:
            begin
               if( cmp_wready )
                 begin
                    cmp_wstate_d = CMPW_D1;
                    cmp_wdata = rxrc_ctlff_data[31:0];
                    cmp_write = 1'b1;
                 end
            end
          CMPW_D1:
            begin
               if( cmp_wready )
                 begin
                    cmp_wstate_d = CMPW_IDLE;
                    cmp_wdata = rxrc_ctlff_data[63:32];
                    cmp_write = 1'b1;
                    ctlff_rxrc_ack = 1'b1;
                 end
            end
          default:
            begin
               cmp_wstate_d = CMPW_IDLE;
            end
        endcase // case (cmp_wstate_q)
     end

   //regen parity for 32 bit data bus
   nvme_pgen#(.bits_per_parity_bit(8), .width(cmp_fifo_width)) cmp_wdata_pgen
     (.data(cmp_wdata),
      .oddpar(1'b1),
      .datap(cmp_wdatap)
      );



   
   //-------------------------------------------------------
   // NVME clock domain logic - trace
   //-------------------------------------------------------

   // clock domain crossing from PSL to NVMe for debug
   wire user_dbg_init_done;
   nvme_cdc cdc_user_dbg1 (.clk(user_clk),.d(init_done_q),.q(user_dbg_init_done));
   wire user_dbg_link_up;
   nvme_cdc cdc_user_dbg2 (.clk(user_clk),.d(link_up_q),.q(user_dbg_link_up));
   wire user_dbg_perst;
   nvme_cdc cdc_user_dbg3 (.clk(user_clk),.d(perst_q),.q(user_dbg_perst));
   
   wire user_cmp_rack;
   nvme_cdc cdc_user_dbg4 (.clk(user_clk),.d(cmp_rack),.q(user_cmp_rack));
   wire user_cmp_rval;
   nvme_cdc cdc_user_dbg5 (.clk(user_clk),.d(cmp_rval),.q(user_cmp_rval));
   wire user_cmp_rempty;
   nvme_cdc cdc_user_dbg6 (.clk(user_clk),.d(cmp_rempty),.q(user_cmp_rempty));
   wire user_cmp_rrstbusy;
   nvme_cdc cdc_user_dbg7 (.clk(user_clk),.d(cmp_rrstbusy),.q(user_cmp_rrstbusy));

   always @(posedge user_clk)
     begin
        ctlff_dbg_user_trace[25:0]  <= {rq_rstate_q[3:0], ctlff_txrq_tag[5:0], txrq_ctlff_ack, ctlff_txrq_rnw, ctlff_txrq_cfgop,  ctlff_txrq_addr[12:0]};
        ctlff_dbg_user_trace[44:26] <= { cmp_wstate_q[3:0], ctlff_rxrc_ack,  rxrc_ctlff_poison, rxrc_ctlff_status[2:0], rxrc_ctlff_errcode[3:0], rxrc_ctlff_tag[5:0] };
        ctlff_dbg_user_trace[45]    <= user_dbg_init_done;
        ctlff_dbg_user_trace[46]    <= user_dbg_link_up;
        ctlff_dbg_user_trace[47]    <= user_dbg_perst;
        ctlff_dbg_user_trace[48]    <= cmp_wfull;
        ctlff_dbg_user_trace[49]    <= rxrc_ctlff_valid;
        ctlff_dbg_user_trace[50]    <= user_cmp_rack;
        ctlff_dbg_user_trace[51]    <= user_cmp_rval;
        ctlff_dbg_user_trace[52]    <= cmp_werror;
        ctlff_dbg_user_trace[53]    <= user_cmp_rempty;
        ctlff_dbg_user_trace[54]    <= cmp_wrstbusy;
        ctlff_dbg_user_trace[55]    <= user_cmp_rrstbusy;
        ctlff_dbg_user_trace[63:56] <= zero[63:56];        
     end
endmodule

