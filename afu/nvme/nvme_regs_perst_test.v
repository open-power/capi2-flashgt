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

module nvme_regs_perst_test
   (

    input            reset,
    input            clk,

    output reg       regs_pcie_perst,
    output reg [7:0] regs_pcie_debug,
    
    input            pcie_xx_link_up,
    input            pcie_xx_init_done,

    
    input     [31:0] pcie_regs_status,

    input            perst_in, // from mmio reg
    input      [7:0] debug_in   // from mmio reg
       
    );

   wire probe_valid;  // give perst_test control of perst & debug signals
   wire probe_perst;  // perst pulse on neg edge
   wire probe_perst2; // assert perst directly (1=asserted)
 
   (* mark_debug = "false" *) reg  perst_sm_valid;

   (* mark_debug = "false" *) reg  perst_edge = 1'b0;
   (* mark_debug = "false" *) reg  perst = 1'b0;
   (* mark_debug = "false" *) wire  [15:0] probe_debug;
   always @(posedge clk)
     begin
        perst_edge <= probe_perst;
        perst <= (perst_edge & ~probe_perst) | perst_sm_valid | probe_perst2;

        if( probe_valid )
          begin
             regs_pcie_perst <= perst;
             regs_pcie_debug <= probe_debug[7:0];
          end        
        else
          begin
             regs_pcie_perst <= perst_in;
             regs_pcie_debug <= debug_in;
          end
     end

   (* mark_debug = "false" *) wire        user_reset;  
   (* mark_debug = "false" *) wire        cfg_phy_link_down;
   (* mark_debug = "false" *) wire  [1:0] cfg_phy_link_status;
   (* mark_debug = "false" *) wire  [3:0] cfg_negotiated_width;
   (* mark_debug = "false" *) wire  [2:0] cfg_current_speed;
   (* mark_debug = "false" *) wire  [5:0] cfg_ltssm_state;
   
   assign {  user_reset, 
             cfg_phy_link_down,
             cfg_phy_link_status,
             cfg_negotiated_width,
             cfg_current_speed, 
             cfg_ltssm_state
             } = pcie_regs_status;
   

   localparam [63:0] clk_period = 32'd4;  // ns
   localparam [63:0] T1 = 64'd300000000 / clk_period;  // 300 ms
   localparam [63:0] T2 = 64'd500000000 / clk_period;  // 500 ms
   
   (* mark_debug = "false" *) reg [31:0] perst_dlycnt_q;
   (* mark_debug = "false" *) reg  [3:0] perst_sm_q;
   (* mark_debug = "false" *) reg [31:0] perst_counter_q;
   
   wire       probe_perst_test_en;
   
   localparam SM_IDLE = 0;
   localparam SM_ASSERT = 1;
   localparam SM_LINKDOWN = 2;
   localparam SM_DLY1 = 3;
   localparam SM_STATUS = 4;
   localparam SM_DLY2 = 5;
   localparam SM_ERROR1 = 6;
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             perst_dlycnt_q <= 0;
             perst_sm_q <= SM_IDLE;
             perst_sm_valid <= 0;
             perst_counter_q <= 0;
          end
        else
          begin            
             case(perst_sm_q)
               SM_IDLE:
                 begin
                    perst_sm_valid <= 0;
                    if(probe_perst_test_en)
                      perst_sm_q <= SM_ASSERT;
                 end
               SM_ASSERT:
                 begin
                    perst_sm_valid <= 1;
                    perst_sm_q <= SM_LINKDOWN;
                 end
               SM_LINKDOWN:
                 begin
                    if( cfg_ltssm_state == 6'h00 )
                      begin
                         perst_sm_valid <= 0;
                         perst_sm_q <= SM_DLY1;
                         perst_dlycnt_q <= T1[31:0];
                      end
                    else if( probe_perst_test_en == 1'b0 )
                      perst_sm_q <= SM_IDLE;
                 end
               SM_DLY1:
                 begin
                    if( perst_dlycnt_q == 0 )
                      perst_sm_q <= SM_STATUS;
                    else
                      perst_dlycnt_q <= perst_dlycnt_q - 1;
                 end
               SM_STATUS:
                 begin
                    if( cfg_ltssm_state == 6'h10 )
                      begin
                         perst_sm_q <= SM_DLY2;
                         perst_dlycnt_q <= T2[31:0];
                      end	
                    else if( probe_perst_test_en == 1'b0 )
                      perst_sm_q <= SM_IDLE;
                 end
               SM_DLY2:
                 begin
                    if( perst_dlycnt_q == 0 )
                      perst_sm_q <= SM_IDLE;
                    else
                      perst_dlycnt_q <= perst_dlycnt_q - 1;
                 end
               SM_ERROR1:
                 begin
                    if( probe_perst_test_en == 1'b0 )
                      perst_sm_q <= SM_IDLE;
                 end
               
               default:
                 begin
                    perst_sm_q <= SM_IDLE;
                 end
             endcase // case (perst_sm_q)    
             
             if( regs_pcie_perst == 1'b0 && perst == 1'b1 )
               perst_counter_q <= perst_counter_q +1;
          end
     end // always @ (posedge clk or posedge reset)

   
   wire [15 : 0] probe_in0;
   wire [15 : 0] probe_in1;
   wire [15 : 0] probe_in2;
   wire [15 : 0] probe_in3;
   wire [15 : 0] probe_in4;
   wire [15 : 0] probe_in5;
   wire [31 : 0] probe_in6;
   wire [31 : 0] probe_in7;
   wire [31 : 0] probe_in8;
   wire [31 : 0] probe_in9;

   assign probe_in0 = user_reset;
   assign probe_in1 = cfg_phy_link_down;
   assign probe_in2 = cfg_phy_link_status;
   assign probe_in3 = cfg_negotiated_width;
   assign probe_in4 = cfg_current_speed;
   assign probe_in5 = cfg_ltssm_state;
   assign probe_in6 = perst_sm_q;
   assign probe_in7 = perst_dlycnt_q;
   assign probe_in8 = perst_counter_q;
   assign probe_in9 = {debug_in, perst_in, pcie_xx_link_up, pcie_xx_init_done};
   
   // wire  [0 : 0] probe_out0;
   // wire  [0 : 0] probe_out1;
   wire [31 : 0] probe_out2;
   wire [31 : 0] probe_out3;
   wire [15 : 0] probe_out4;
   wire [15 : 0] probe_out5;
   wire  [0 : 0] probe_out6;
   wire  [0 : 0] probe_out7;
   wire  [0 : 0] probe_out8;
   wire  [0 : 0] probe_out9;


  vio_1 vio_1 (
  .clk(clk),                // input wire clk
  .probe_in0(probe_in0),    // input wire [15 : 0] probe_in0
  .probe_in1(probe_in1),    // input wire [15 : 0] probe_in1
  .probe_in2(probe_in2),    // input wire [15 : 0] probe_in2
  .probe_in3(probe_in3),    // input wire [15 : 0] probe_in3
  .probe_in4(probe_in4),    // input wire [15 : 0] probe_in4
  .probe_in5(probe_in5),    // input wire [15 : 0] probe_in5
  .probe_in6(probe_in6),    // input wire [15 : 0] probe_in6
  .probe_in7(probe_in7),    // input wire [15 : 0] probe_in7
  .probe_in8(probe_in8),    // input wire [15 : 0] probe_in8
  .probe_in9(probe_in9),    // input wire [15 : 0] probe_in9
  .probe_out0(probe_perst),  // output wire [0 : 0] probe_out0
  .probe_out1(probe_valid),  // output wire [0 : 0] probe_out1
  .probe_out2(probe_out2[31:0]),  // output wire [31 : 0] probe_out2
  .probe_out3(probe_out3[31:0]),  // output wire [31 : 0] probe_out3
  .probe_out4(probe_debug[7:0] ),  // output wire [15 : 0] probe_out4
  .probe_out5(probe_out5),  // output wire [15 : 0] probe_out5
  .probe_out6(probe_perst_test_en),  // output wire [0 : 0] probe_out6
  .probe_out7(probe_perst2),  // output wire [0 : 0] probe_out7
  .probe_out8(probe_out8),  // output wire [0 : 0] probe_out8
  .probe_out9(probe_out9)  // output wire [0 : 0] probe_out9
);

 
   
endmodule


