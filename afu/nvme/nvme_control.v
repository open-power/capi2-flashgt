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
//  File : nvme_control.v
//  *************************************************************************
//  *************************************************************************
//  Description : FlashGT+ NVMe microcontroller
//                
//       - PCIe init/enumeration
//       - NVMe initialization
//       - Admin functions from SNTL/sislite
//
//  *************************************************************************

module nvme_control#
  ( 
    parameter port_id = 0,
     
    // bit definitions for GPIO in & out
    parameter gpo_csts_rdy     = 0,
    parameter gpo_ioq_enable   = 1,
    parameter gpo_shutdown     = 2,
    parameter gpo_shutdown_cmp = 3,

  
    parameter gpi_admin_cmd       = 0,
    parameter gpi_admin_cpl       = 1,
    parameter gpi_ctl_enable      = 2,
    parameter gpi_link_up         = 3,
    parameter gpi_init_done       = 4,
    parameter gpi_adq_cq0_empty   = 5,
    parameter gpi_adq_cq1_empty   = 6,
    parameter gpi_sntl_idle       = 7,
    parameter gpi_ld_rom          = 8,
    parameter gpi_shutdown        = 9,
    parameter gpi_shutdown_abrupt = 10,
    parameter gpi_isq_empty       = 11,
    parameter gpi_icq_empty       = 12,
    parameter gpi_t1_expired      = 13,
    parameter gpi_lunreset        = 14
    )
   (
   
    input             reset,
    input             clk,
    input             clk_div2,
   
    //-------------------------------------------------------
    // I/O read/write interface from xilinx iomodule
    //-------------------------------------------------------

    // PCIe port interface for MMIO & CFG ops
    output reg [31:0] ctl_pcie_ioaddress, //      valid with ioread_strobe or iowrite_strobe
    output reg [35:0] ctl_pcie_iowrite_data, //   valid with iowrite_strobe
    output reg        ctl_pcie_ioread_strobe, //  1 cycle pulse
    output reg        ctl_pcie_iowrite_strobe, // 1 cycle pulse
    input      [31:0] pcie_ctl_ioread_data, //    valid with ioack if ioread_strobe was asserted
    input             pcie_ctl_ioack, //          asserted on same cycle as ioread_strobe or iowrite_strobe or later

    // Admin Queue interface
    output reg [31:0] ctl_adq_ioaddress,
    output reg [35:0] ctl_adq_iowrite_data, 
    output reg        ctl_adq_ioread_strobe, 
    output reg        ctl_adq_iowrite_strobe,
    input      [31:0] adq_ctl_ioread_data,
    input             adq_ctl_ioack,

    // SCSI to NVME Translation interface
    output reg [31:0] ctl_sntl_ioaddress,
    output reg [35:0] ctl_sntl_iowrite_data, 
    output reg        ctl_sntl_ioread_strobe, 
    output reg        ctl_sntl_iowrite_strobe,
    input      [31:0] sntl_ctl_ioread_data,
    input             sntl_ctl_ioack,

    // IOQ configuration interface
    output reg [31:0] ctl_ioq_ioaddress,
    output reg [35:0] ctl_ioq_iowrite_data, 
    output reg        ctl_ioq_ioread_strobe, 
    output reg        ctl_ioq_iowrite_strobe,
    input      [31:0] ioq_ctl_ioread_data,
    input             ioq_ctl_ioack,
   
   
    // mmio register access
    output reg [31:0] ctl_regs_ioaddress,
    output reg [35:0] ctl_regs_iowrite_data,
    output reg        ctl_regs_ioread_strobe, 
    output reg        ctl_regs_iowrite_strobe,
    input      [31:0] regs_ctl_ioread_data,
    input             regs_ctl_ioack,
    input             regs_ctl_ldrom,

    //-------------------------------------------------------
    // SCSI command translation buffer status to microcontroller
    //-------------------------------------------------------
    input             sntl_ctl_admin_cmd_valid,
    input             sntl_ctl_admin_cpl_valid,

    //-------------------------------------------------------
    // NVMe port status to regs & other modules
    //-------------------------------------------------------
    output reg        ctl_xx_ioq_enable, //    asserted when I/O SW & CQ are enabled
    output reg        ctl_xx_csts_rdy, //      NVMe CSTS register ready
    output reg        ctl_xx_shutdown, //      NVMe shutdown processing is active
    output reg        ctl_xx_shutdown_cmp, //  NVMe shutdown status = completed
    output reg [31:0] ctl_regs_ustatus, //     status encodes for debug
   
    input             regs_ctl_enable, //         0=offline 1=online
    input             regs_ctl_shutdown, //       begin normal shutdown
    input             regs_ctl_shutdown_abrupt,// begin abrupt shutdown
    input             regs_ctl_lunreset,

    input             pcie_xx_link_up,
    input             pcie_xx_init_done,

    input             ioq_xx_isq_empty,
    input             ioq_xx_icq_empty,
    input             sntl_ctl_idle,
   
    input       [1:0] adq_ctl_cpl_empty  // Admin Completion Queue Empty

    );

   // ublaze with fault tolerance/ECC didn't close timing at 250Mhz
   // use 125Mhz clock instead
   reg                reset_div2;
   always @(posedge clk_div2 or posedge reset)
     if( reset )
       reset_div2 <= 1'b1;
     else
       reset_div2 <= 1'b0;
   
   // 125Mhz signals
   wire               IO_BUS_addr_strobe;   
   wire        [31:0] IO_BUS_address;        
   wire         [3:0] IO_BUS_byte_enable;    
   wire               IO_BUS_read_strobe;   
   wire        [31:0] IO_BUS_write_data;      
   wire         [3:0] IO_BUS_write_data_par;  
   wire               IO_BUS_write_strobe;        
   wire               IO_BUS_ready;
   wire        [31:0] IO_BUS_read_data;

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(32)
      ) ipgen_IO_BUS_write_data 
       (.oddpar(1'b1),.data(IO_BUS_write_data),.datap(IO_BUS_write_data_par)); 

   
   // convert 125Mhz strobe to 250Mhz
   // with register divide, clk_div2 is skewed late relative to clk
   // To make timing, all clk_div->clk paths must go to directly to reg with no logic
   // just to keep things simple, include this even if low clock skew buffer is used
   (* mark_debug = "true" *) 
   reg         [31:0] io_addr_q;
   (* mark_debug = "true" *) 
   reg         [35:0] io_wrdata_q; 
   (* mark_debug = "true" *) 
   reg          [1:0] io_read_q, io_write_q;
   always @(posedge clk) 
     begin
        if( reset )
          begin
             io_read_q  <= 2'b00;
             io_write_q <= 2'b00;
          end
        else
          begin            
             io_read_q  <= {io_read_q[0], IO_BUS_read_strobe};
             io_write_q <= {io_write_q[0],IO_BUS_write_strobe};
          end
     end
   always @(posedge clk) io_addr_q   <= IO_BUS_address;
   always @(posedge clk) io_wrdata_q <= {IO_BUS_write_data_par,IO_BUS_write_data};

   reg         sntl_addr_dec;
   reg         pcie_addr_dec;
   reg         adq_addr_dec;
   reg         ioq_addr_dec;	
   reg         regs_addr_dec;
   
   // 250Mhz logic
   always @*
     begin
        // Address decode for microblaze IO range
        // 0x44A0_0000 to 0x44A0_FFFF is decoded by the iomodule
        // subdivide this into 5 subregions:
        //  addr[15:13]:
        //    00x - sntl
        //    01x - pcie
        //    100 - adq
        //    101 - ioq
        //    11x - regs
        sntl_addr_dec  = io_addr_q[15:14]==2'b00;
        pcie_addr_dec  = io_addr_q[15:14]==2'b01;
        adq_addr_dec   = io_addr_q[15:13]==3'b100;
        ioq_addr_dec   = io_addr_q[15:13]==3'b101;
        regs_addr_dec  = io_addr_q[15:14]==2'b11;
        
        ctl_pcie_ioaddress           = io_addr_q;
        ctl_pcie_iowrite_data        = io_wrdata_q;
        ctl_pcie_ioread_strobe       = io_read_q==2'b01 & pcie_addr_dec;
        ctl_pcie_iowrite_strobe      = io_write_q==2'b01 & pcie_addr_dec;

        ctl_adq_ioaddress            = io_addr_q;
        ctl_adq_iowrite_data         = io_wrdata_q;
        ctl_adq_ioread_strobe        = io_read_q==2'b01 & adq_addr_dec;
        ctl_adq_iowrite_strobe       = io_write_q==2'b01 & adq_addr_dec;

        ctl_sntl_ioaddress           = io_addr_q;
        ctl_sntl_iowrite_data        = io_wrdata_q;
        ctl_sntl_ioread_strobe       = io_read_q==2'b01 & sntl_addr_dec;
        ctl_sntl_iowrite_strobe      = io_write_q==2'b01 & sntl_addr_dec;

        ctl_ioq_ioaddress            = io_addr_q;
        ctl_ioq_iowrite_data         = io_wrdata_q;
        ctl_ioq_ioread_strobe        = io_read_q==2'b01 & ioq_addr_dec;
        ctl_ioq_iowrite_strobe       = io_write_q==2'b01 & ioq_addr_dec;

        ctl_regs_ioaddress           = io_addr_q;
        ctl_regs_iowrite_data        = io_wrdata_q;
        ctl_regs_ioread_strobe       = io_read_q==2'b01 & regs_addr_dec;
        ctl_regs_iowrite_strobe      = io_write_q==2'b01 & regs_addr_dec;

     end // always @ *

   
   //* convert 250Mhz ready/data to 125Mhz
   (* mark_debug = "false" *) reg   [1:0] io_ready_q;
   reg  [31:0] io_read_data_q;
   always @(posedge clk)
     begin
        io_ready_q[0] <= pcie_ctl_ioack |
                         adq_ctl_ioack |
                         ioq_ctl_ioack |
                         sntl_ctl_ioack |
                         regs_ctl_ioack;
        io_ready_q[1] <= io_ready_q[0];

        if( io_ready_q == 2'b00 )
          begin
             io_read_data_q <= (pcie_ctl_ioread_data & {32{pcie_ctl_ioack}}) |
                               (adq_ctl_ioread_data & {32{adq_ctl_ioack}}) |
                               (ioq_ctl_ioread_data & {32{ioq_ctl_ioack}}) |
                               (sntl_ctl_ioread_data & {32{sntl_ctl_ioack}}) |
                               (regs_ctl_ioread_data & {32{regs_ctl_ioack}});
          end
     end                          
   assign IO_BUS_ready     = io_ready_q[0] | io_ready_q[1];
   assign IO_BUS_read_data = io_read_data_q;



   // GPIO outputs
   // convert 125Mhz to 250Mhz
   wire        [15:0] GPIO1_tri_o;
   wire        [31:0] GPIO2_tri_o;
   wire        [31:0] GPIO3_tri_o;
   reg         [15:0] gpio1_q;  
   reg         [31:0] gpio2_q;  
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             gpio1_q <= 16'h0;
             gpio2_q <= 32'h0;
          end
        else
          begin
             gpio1_q <= GPIO1_tri_o;
             gpio2_q <= GPIO2_tri_o;
          end
     end
   
   always @*
     begin
        ctl_xx_ioq_enable    = gpio1_q[gpo_ioq_enable];
        ctl_xx_csts_rdy      = gpio1_q[gpo_csts_rdy];
        ctl_xx_shutdown      = gpio1_q[gpo_shutdown];
        ctl_xx_shutdown_cmp  = gpio1_q[gpo_shutdown_cmp];
        ctl_regs_ustatus     = gpio2_q;
     end

   // use GPIO3 output to control timer
   // GPIO3[31]=enable (set to 0 to clear current expired status)
   // GPIO3[25:0]=reload value (microseconds)
   // could use IO module's PIT instead
   reg t1_enable;
   reg [24:0] t1_preload;
   always @*
     begin
        t1_enable  = GPIO3_tri_o[31];
        t1_preload = GPIO3_tri_o[24:0];
     end
   
   reg  [6:0] t1_us_q, t1_us_d;
   reg [25:0] t1_q, t1_d;
   reg        t1_expired_q, t1_expired_d;
   always @(posedge clk_div2 or posedge reset_div2)
     begin
        if( reset_div2 )
          begin
             t1_us_q      <= 7'h0;
             t1_q         <= 26'h0;
             t1_expired_q <= 1'b0;
          end
        else
          begin
             t1_us_q      <= t1_us_d;
             t1_q         <= t1_d;
             t1_expired_q <= t1_expired_d;
          end
     end
   
   always @*
     begin
        t1_expired_d  = t1_expired_q;
        t1_us_d       = t1_us_q;
        t1_d          = t1_q;
        
        if( t1_enable & !t1_expired_q)
          begin
             t1_us_d = t1_us_d + 7'b1;
             if( t1_us_q == 7'd124 )
               begin
                  t1_us_d = 6'd0;
                  if( t1_q == 26'd0 )
                    begin
                       t1_expired_d = 1'b1;
                    end
                  else
                    begin
                       t1_d = t1_q - 26'd1;
                    end
               end
          end
        else
          begin
             if( !t1_enable )
               begin
                  t1_d          = t1_preload;
                  t1_expired_d  = 1'b0;
                  t1_us_d       = 7'd0;
               end
          end
     end
   
   
   // GPIO inputs
   reg         [15:0] GPIO1_tri_i;
   always @*
     begin
        GPIO1_tri_i[15:0]                 = 16'h0;
        GPIO1_tri_i[gpi_admin_cmd]        = sntl_ctl_admin_cmd_valid;
        GPIO1_tri_i[gpi_admin_cpl]        = sntl_ctl_admin_cpl_valid;
        GPIO1_tri_i[gpi_ctl_enable]       = regs_ctl_enable;
        GPIO1_tri_i[gpi_link_up]          = pcie_xx_link_up;
        GPIO1_tri_i[gpi_init_done]        = pcie_xx_init_done;
        GPIO1_tri_i[gpi_adq_cq0_empty]    = adq_ctl_cpl_empty[0];
        GPIO1_tri_i[gpi_adq_cq1_empty]    = adq_ctl_cpl_empty[1];
        GPIO1_tri_i[gpi_sntl_idle]        = sntl_ctl_idle;
        GPIO1_tri_i[gpi_ld_rom]           = regs_ctl_ldrom;
        GPIO1_tri_i[gpi_shutdown]         = regs_ctl_shutdown;
        GPIO1_tri_i[gpi_shutdown_abrupt]  = regs_ctl_shutdown_abrupt;
        GPIO1_tri_i[gpi_isq_empty]        = ioq_xx_isq_empty;
        GPIO1_tri_i[gpi_icq_empty]        = ioq_xx_icq_empty;
        GPIO1_tri_i[gpi_t1_expired]       = t1_expired_q;
        GPIO1_tri_i[gpi_lunreset]         = regs_ctl_lunreset;
     end
   

   // 125Mhz trace bus - dangling at this level, used for debug only
   wire        TRACE_data_access;
   wire [0:31] TRACE_data_address;
   wire  [0:3] TRACE_data_byte_enable;
   wire        TRACE_data_read;
   wire        TRACE_data_write;
   wire [0:31] TRACE_data_write_value;
   wire        TRACE_dcache_hit;
   wire        TRACE_dcache_rdy;
   wire        TRACE_dcache_read;
   wire        TRACE_dcache_req;
   wire        TRACE_delay_slot;
   wire        TRACE_ex_piperun;
   wire  [0:4] TRACE_exception_kind;
   wire        TRACE_exception_taken;
   wire        TRACE_icache_hit;
   wire        TRACE_icache_rdy;
   wire        TRACE_icache_req;
   (* mark_debug = "true" *) 
   wire [0:31] TRACE_instruction;
   wire        TRACE_jump_hit;
   wire        TRACE_jump_taken;
   wire        TRACE_mb_halted;
   wire        TRACE_mem_piperun;
   wire [0:14] TRACE_msr_reg;
   (* mark_debug = "true" *) 
   wire [0:31] TRACE_new_reg_value;
   wire        TRACE_of_piperun;
   (* mark_debug = "true" *) 
   wire [0:31] TRACE_pc;
   wire  [0:7] TRACE_pid_reg;
   (* mark_debug = "true" *) 
   wire  [0:4] TRACE_reg_addr;
   (* mark_debug = "true" *) 
   wire        TRACE_reg_write;
   (* mark_debug = "true" *) 
   wire        TRACE_valid_instr;
   
   wire        CE, CE_1;
   wire        UE, UE_1;

   // interrupt connections - not used
   wire [0:31] INTERRUPT_address;
   wire        INTERRUPT_interrupt;
   wire  [0:1] INTERRUPT_ack;

   assign INTERRUPT_interrupt = 1'b0;
   assign INTERRUPT_address = 32'h0;
   
   ublaze_0 ublaze_0     
     (
      .Clk                              (clk_div2),
      .Reset                            (reset_div2),
      /*AUTOINST*/
      // Outputs
      .CE                               (CE),
      .CE_1                             (CE_1),
      .GPIO1_tri_o                      (GPIO1_tri_o[15:0]),
      .GPIO2_tri_o                      (GPIO2_tri_o[31:0]),
      .GPIO3_tri_o                      (GPIO3_tri_o[31:0]),
      .INTERRUPT_ack                    (INTERRUPT_ack[0:1]),
      .IO_BUS_addr_strobe               (IO_BUS_addr_strobe),
      .IO_BUS_address                   (IO_BUS_address[31:0]),
      .IO_BUS_byte_enable               (IO_BUS_byte_enable[3:0]),
      .IO_BUS_read_strobe               (IO_BUS_read_strobe),
      .IO_BUS_write_data                (IO_BUS_write_data[31:0]),
      .IO_BUS_write_strobe              (IO_BUS_write_strobe),
      .TRACE_data_access                (TRACE_data_access),
      .TRACE_data_address               (TRACE_data_address[0:31]),
      .TRACE_data_byte_enable           (TRACE_data_byte_enable[0:3]),
      .TRACE_data_read                  (TRACE_data_read),
      .TRACE_data_write                 (TRACE_data_write),
      .TRACE_data_write_value           (TRACE_data_write_value[0:31]),
      .TRACE_dcache_hit                 (TRACE_dcache_hit),
      .TRACE_dcache_rdy                 (TRACE_dcache_rdy),
      .TRACE_dcache_read                (TRACE_dcache_read),
      .TRACE_dcache_req                 (TRACE_dcache_req),
      .TRACE_delay_slot                 (TRACE_delay_slot),
      .TRACE_ex_piperun                 (TRACE_ex_piperun),
      .TRACE_exception_kind             (TRACE_exception_kind[0:4]),
      .TRACE_exception_taken            (TRACE_exception_taken),
      .TRACE_icache_hit                 (TRACE_icache_hit),
      .TRACE_icache_rdy                 (TRACE_icache_rdy),
      .TRACE_icache_req                 (TRACE_icache_req),
      .TRACE_instruction                (TRACE_instruction[0:31]),
      .TRACE_jump_hit                   (TRACE_jump_hit),
      .TRACE_jump_taken                 (TRACE_jump_taken),
      .TRACE_mb_halted                  (TRACE_mb_halted),
      .TRACE_mem_piperun                (TRACE_mem_piperun),
      .TRACE_msr_reg                    (TRACE_msr_reg[0:14]),
      .TRACE_new_reg_value              (TRACE_new_reg_value[0:31]),
      .TRACE_of_piperun                 (TRACE_of_piperun),
      .TRACE_pc                         (TRACE_pc[0:31]),
      .TRACE_pid_reg                    (TRACE_pid_reg[0:7]),
      .TRACE_reg_addr                   (TRACE_reg_addr[0:4]),
      .TRACE_reg_write                  (TRACE_reg_write),
      .TRACE_valid_instr                (TRACE_valid_instr),
      .UE                               (UE),
      .UE_1                             (UE_1),
      // Inputs
      .GPIO1_tri_i                      (GPIO1_tri_i[15:0]),
      .INTERRUPT_address                (INTERRUPT_address[0:31]),
      .INTERRUPT_interrupt              (INTERRUPT_interrupt),
      .IO_BUS_read_data                 (IO_BUS_read_data[31:0]),
      .IO_BUS_ready                     (IO_BUS_ready));
  

endmodule

// for xemacs verilog-mode AUTOINST
// Local Variables:
// verilog-library-directories:("." "../../ip/2017.2/ublaze_0/hdl")
// End:
