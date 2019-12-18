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
//  File : nvme_sntl_wbuf.v
//  *************************************************************************
//  *************************************************************************
//  Description : FlashGT+ - SCSI to NVMe Layer payload write buffer
//                
//  *************************************************************************

module nvme_sntl_wbuf#
  (// afu/psl   interface parameters
   parameter tag_width       = 8,
   parameter datalen_width   = 25,
   parameter data_width      = 128,
   parameter data_bytes      = data_width/8,
   parameter bytec_width     = $clog2(data_bytes+1),
   parameter beatid_width    = datalen_width-$clog2(data_bytes),    
   parameter lunid_width     = 64, 
   parameter cmd_width       = 4, 
   parameter fcstat_width    = 8, 
   parameter fcxstat_width   = 8, 
   parameter rsp_info_width  = 160,
   parameter tag_par_width   = (tag_width + 7)/8, 
   parameter lunid_par_width = (lunid_width + 7)/8, 
   parameter data_par_width  = (data_width + 7) / 8,
   parameter data_fc_par_width = data_par_width/8,
   parameter status_width    = 8, // event status
   parameter wdata_max_req   = 4096,
   parameter wdatalen_width  = $clog2(wdata_max_req)+1,
   parameter wdatalen_par_width  = (wdatalen_width+63)/64 ,   
   parameter wbuf_size       = 4096, // 4KB per write buffer
   parameter wbuf_numids     = 6,  
   parameter wbufid_width    = $clog2(wbuf_numids),
   parameter wbufid_par_width = (wbufid_width + 7)/8,
   
   parameter addr_width = 48,
   parameter cid_width = 16,
   parameter cid_par_width = 16/8
      
    )
   (
   
    input                                  reset,
    input                                  clk, 

    //-------------------------------------------------------
    // request from command tracking
    //-------------------------------------------------------
    input                                  cmd_wbuf_req_valid,
    input                  [cid_width-1:0] cmd_wbuf_req_cid,
    input              [cid_par_width-1:0] cmd_wbuf_req_cid_par, 
    input              [datalen_width-1:0] cmd_wbuf_req_reloff, // offset from start address of this command  
    input               [wbufid_width-1:0] cmd_wbuf_req_wbufid,
    input           [wbufid_par_width-1:0] cmd_wbuf_req_wbufid_par,
    input                           [63:0] cmd_wbuf_req_lba,
    input                           [15:0] cmd_wbuf_req_numblks,
    input                                  cmd_wbuf_req_unmap,
    output reg                             wbuf_cmd_req_ready,

    //-------------------------------------------------------
    // status to command tracking
    //-------------------------------------------------------
    output reg                             wbuf_cmd_status_valid, // asserted when data transfer for a cid/wbufid is complete
    output reg          [wbufid_width-1:0] wbuf_cmd_status_wbufid,
    output reg      [wbufid_par_width-1:0] wbuf_cmd_status_wbufid_par,
    output reg             [cid_width-1:0] wbuf_cmd_status_cid,
    output reg         [cid_par_width-1:0] wbuf_cmd_status_cid_par,
    output reg                             wbuf_cmd_status_error, // 0 = data is in the buffer  1 = error, data is not valid
    input                                  cmd_wbuf_status_ready,

    //-------------------------------------------------------
    // buffer management
    //-------------------------------------------------------
    input                                  cmd_wbuf_id_valid, // need wbufid
    output reg                             wbuf_cmd_id_ack, // wbufid granted
    output reg          [wbufid_width-1:0] wbuf_cmd_id_wbufid,
    output reg      [wbufid_par_width-1:0] wbuf_cmd_id_wbufid_par,
    
    input                                  cmd_wbuf_idfree_valid, // done with with wbufid
    input               [wbufid_width-1:0] cmd_wbuf_idfree_wbufid, 
    input           [wbufid_par_width-1:0] cmd_wbuf_idfree_wbufid_par,

    input                                  unmap_wbuf_valid, // need wbufid
    output reg                             wbuf_unmap_ack, 
    output reg          [wbufid_width-1:0] wbuf_unmap_wbufid,
    output reg      [wbufid_par_width-1:0] wbuf_unmap_wbufid_par,

    input                                  unmap_wbuf_idfree_valid, // done with with wbufid
    output reg                             wbuf_unmap_idfree_ack,
    input               [wbufid_width-1:0] unmap_wbuf_idfree_wbufid, 
    input           [wbufid_par_width-1:0] unmap_wbuf_idfree_wbufid_par,


    // ----------------------------------------------------
    // sislite write (DMA read to host)
    // ----------------------------------------------------   
    output reg                             wbuf_wdata_req_valid, 
    output reg             [tag_width-1:0] wbuf_wdata_req_tag, //    afu req tag  
    output reg         [tag_par_width-1:0] wbuf_wdata_req_tag_par,
    output reg         [datalen_width-1:0] wbuf_wdata_req_reloff, // offset from start address of this command  
    output reg        [wdatalen_width-1:0] wbuf_wdata_req_length, // number of bytes to request, max 4096B
    output reg    [wdatalen_par_width-1:0] wbuf_wdata_req_length_par,
    output reg          [wbufid_width-1:0] wbuf_wdata_req_wbufid, // buffer id
    output reg      [wbufid_par_width-1:0] wbuf_wdata_req_wbufid_par, 
    input                                  wdata_wbuf_req_ready, 
   
    // ----------------------------------------------------
    // sislite write data response from host
    // ----------------------------------------------------
    input                                  wdata_wbuf_rsp_valid,
    input                                  wdata_wbuf_rsp_end,
    input                                  wdata_wbuf_rsp_error,
    input                  [tag_width-1:0] wdata_wbuf_rsp_tag,
    input              [tag_par_width-1:0] wdata_wbuf_rsp_tag_par, 
    input               [wbufid_width-1:0] wdata_wbuf_rsp_wbufid,
    input           [wbufid_par_width-1:0] wdata_wbuf_rsp_wbufid_par,
    input               [beatid_width-1:0] wdata_wbuf_rsp_beat,
    input                 [data_width-1:0] wdata_wbuf_rsp_data,
    input          [data_fc_par_width-1:0] wdata_wbuf_rsp_data_par,
    output reg                             wbuf_wdata_rsp_ready,
   

    //-------------------------------------------------------
    // NVMe/PCIe DMA requests to SNTL write buffer
    //-------------------------------------------------------
     
    input                                  pcie_sntl_wbuf_valid,
    input    [data_par_width+data_width:0] pcie_sntl_wbuf_data, 
    input                                  pcie_sntl_wbuf_first, 
    input                                  pcie_sntl_wbuf_last, 
    input                                  pcie_sntl_wbuf_discard, 
    output                                 sntl_pcie_wbuf_pause, 

    //-------------------------------------------------------
    // NVMe/PCIe DMA response from SNTL write buffer
    //-------------------------------------------------------   
    output [data_par_width + data_width:0] sntl_pcie_wbuf_cc_data, 
    output                                 sntl_pcie_wbuf_cc_first, 
    output                                 sntl_pcie_wbuf_cc_last,
    output                                 sntl_pcie_wbuf_cc_discard, 
    output                                 sntl_pcie_wbuf_cc_valid, 
    input                                  pcie_sntl_wbuf_cc_ready,

    
    //-------------------------------------------------------
    // RAS
    //-------------------------------------------------------
    output reg                       [3:0] wbuf_regs_error,
    output                           [2:0] wbuf_perror_ind,
    // ----------------------------------------------------------
    // parity error inject 
    // ----------------------------------------------------------
    input                                  regs_sntl_pe_errinj_valid,
    input                           [15:0] regs_xxx_pe_errinj_decode, 
    input                                  regs_wdata_pe_errinj_1cycle_valid 

   
    );


`include "nvme_func.svh"

   // Parity error srlat 

   wire                              [1:0] s1_perror;
   wire                              [2:0] wbuf_perror_int;

   // set/reset/ latch for parity errors
   nvme_srlat#
     (.width(2))  iwbuf_sr   
       (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(wbuf_perror_int[2:1]));

   assign wbuf_perror_ind = wbuf_perror_int;


   
   //-------------------------------------------------------
   // wbuf id management
   //-------------------------------------------------------

   reg                                     wbufid_fifo_push;
   reg [wbufid_par_width+wbufid_width-1:0] wbufid_fifo_wdata;
   wire                                    wbufid_fifo_full;
   wire                                    wbufid_fifo_valid;
   reg                                     wbufid_fifo_taken;
   wire [wbufid_par_width+wbufid_width-1:0] wbufid_fifo_rdata;
   
    nvme_fifo#(
              .width(wbufid_par_width+wbufid_width), 
              .words(wbuf_numids)           
              ) wbufid_fifo
     (.clk(clk), .reset(reset), 
      .flush(        1'b0                  ),
      .push(         wbufid_fifo_push      ),
      .din(          wbufid_fifo_wdata     ),
      .dval(         wbufid_fifo_valid     ),
      .pop(          wbufid_fifo_taken     ),
      .dout(         wbufid_fifo_rdata     ),
      .full(         wbufid_fifo_full      ), 
      .almost_full(                        ), 
      .used());

   // initialize fifo with list of wbufids
   reg                  [wbufid_width-1:0] wbufid_init_q, wbufid_init_d;
   reg              [wbufid_par_width-1:0] wbufid_init_par_q, wbufid_init_par_d;
   reg                                     wbufid_init_done_q, wbufid_init_done_d;
   reg                                     idfree_v_q, idfree_v_d;
   reg                  [wbufid_width-1:0] idfree_wbufid_q, idfree_wbufid_d;
   reg              [wbufid_par_width-1:0] idfree_wbufid_par_q, idfree_wbufid_par_d;
   reg                               [3:0] wbuf_pe_inj_d,wbuf_pe_inj_q;
   reg                                     wbufid_ferror;

   localparam wbufid_rr_width = 2;
   reg [wbufid_rr_width-1:0] wbufid_rr_q, wbufid_rr_d;
   reg [wbufid_rr_width-1:0] wbufid_rr_valid;
   reg [wbufid_rr_width-1:0] wbufid_rr_gnt;
   reg  [31:wbufid_rr_width] wbufid_rr_unused;
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             wbufid_init_q       <= zero[wbufid_width:0];
             wbufid_init_par_q   <= one[wbufid_par_width:0];
             wbufid_init_done_q  <= 1'b0;
             idfree_v_q          <= 1'b0;
             idfree_wbufid_q     <= zero[wbufid_width-1:0];
             idfree_wbufid_par_q <= zero[wbufid_par_width-1:0];
             wbuf_pe_inj_q       <= 4'b0;
             wbufid_rr_q         <= one[wbufid_rr_width-1:0];
          end
        else
          begin             
             wbufid_init_q       <= wbufid_init_d;
             wbufid_init_par_q   <= wbufid_init_par_d;
             wbufid_init_done_q  <= wbufid_init_done_d;
             idfree_v_q          <= idfree_v_d;
             idfree_wbufid_q     <= idfree_wbufid_d;
             idfree_wbufid_par_q <= idfree_wbufid_par_d;
             wbuf_pe_inj_q       <= wbuf_pe_inj_d;
             wbufid_rr_q         <= wbufid_rr_d;
          end
     end

   wire [wbufid_par_width-1:0] wbufid_init_par;        
   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(wbufid_width)
      ) ipgen_wbufid_width 
       (.oddpar(1'b1),.data(wbufid_init_d),.datap(wbufid_init_par)); 

   
   always @*
     begin                
        wbufid_init_d         = wbufid_init_q;
        wbufid_init_par_d     = wbufid_init_par_q;
        wbufid_init_done_d    = wbufid_init_done_q;
        
        wbufid_rr_d = wbufid_rr_q;        
        wbufid_rr_valid = { cmd_wbuf_id_valid, unmap_wbuf_valid };        
        {wbufid_rr_unused, wbufid_rr_gnt} = roundrobin({zero[31:wbufid_rr_width],wbufid_rr_valid}, {zero[31:wbufid_rr_width], wbufid_rr_q} );
        
        wbuf_unmap_ack = 1'b0; 
        { wbuf_unmap_wbufid_par, wbuf_unmap_wbufid } = wbufid_fifo_rdata;
        wbuf_cmd_id_ack = 1'b0;
        { wbuf_cmd_id_wbufid_par, wbuf_cmd_id_wbufid } = wbufid_fifo_rdata;      
        wbufid_fifo_taken     = 1'b0;
        
        wbufid_fifo_push      = 1'b0;
        wbufid_fifo_wdata     = {wbufid_init_par_q[wbufid_par_width-1:0],wbufid_init_q[wbufid_width-1:0]};
        
        wbufid_ferror         =  wbufid_fifo_full & wbufid_fifo_push;
        
        if( wbufid_init_done_q==1'b0 )
          begin
             wbufid_init_d      = wbufid_init_q + one[wbufid_width:0];
             wbufid_fifo_push   = 1'b1;
            
             if( wbufid_init_q == (wbuf_numids[wbufid_width:0]-one[wbufid_width:0])  )
               begin
                  wbufid_init_done_d = 1'b1;
               end
          end
        else if( idfree_v_q ) 
          begin                                     
             wbufid_fifo_push   = 1'b1;
             wbufid_fifo_wdata  = {idfree_wbufid_par_q, idfree_wbufid_q};
          end
        else
          begin
             // wbufid_stat has idfree_v_q as higher prior than wbufid_fifo_taken
             // so only ack wbufid requests when idfree_v_q=0
             if( wbufid_fifo_valid )
               begin
                  { wbuf_cmd_id_ack, wbuf_unmap_ack } = wbufid_rr_gnt;
                  if( wbufid_rr_gnt != zero[wbufid_rr_width-1:0] )
                    begin
                       wbufid_rr_d = wbufid_rr_gnt;
                       wbufid_fifo_taken = 1'b1;
                    end
               end             
          end              
     end // always @ *


   
   // flag to track whether wbufid is in use for error checking
   reg                              wbufid_stat_mem[wbuf_numids-1:0];
   reg                              wbufid_stat_rddata, wbufid_stat_wrdata;
   reg           [wbufid_width-1:0] wbufid_stat_rdaddr, wbufid_stat_wraddr;
   reg                              wbufid_stat_write;
   reg                        [1:0] wbufid_stat_ferror;
   
   always @(posedge clk)   
     wbufid_stat_rddata <= wbufid_stat_mem[wbufid_stat_rdaddr];
   
   always @(posedge clk)
     if (wbufid_stat_write)
       wbufid_stat_mem[wbufid_stat_wraddr] <= wbufid_stat_wrdata;

   reg                              wbufid_stat_idfree_q, wbufid_stat_idfree_d;
   reg                              wbufid_stat_alloc_q, wbufid_stat_alloc_d;
   always @(posedge clk)
     begin
        wbufid_stat_idfree_q <= wbufid_stat_idfree_d;
        wbufid_stat_alloc_q  <= wbufid_stat_alloc_d;   
        if( wbufid_stat_alloc_d )
          $display("%t %m wbuf alloc id %x",$time,wbufid_stat_wraddr);
        if( wbufid_stat_idfree_d )
          $display("%t %m wbuf free id %x",$time,wbufid_stat_wraddr);
     end        
   
   always @*
     begin                
     
        wbufid_stat_write     = 1'b0;
        wbufid_stat_wraddr    = wbufid_init_q[wbufid_width-1:0];
        wbufid_stat_wrdata    = 1'b0;
        wbufid_stat_rdaddr    = wbufid_fifo_rdata[wbufid_width-1:0];
        
        wbufid_stat_idfree_d  = 1'b0;
        wbufid_stat_alloc_d   = 1'b0;
                      
        if( wbufid_init_done_q==1'b0 )
          begin           
             wbufid_stat_write  = 1'b1;           
          end
        else
          begin           
             if( idfree_v_q )
               begin
                  wbufid_stat_write     = 1'b1;
                  wbufid_stat_wraddr    = idfree_wbufid_q;
                  wbufid_stat_wrdata    = 1'b0;
                  wbufid_stat_rdaddr    = idfree_wbufid_q;
                  wbufid_stat_idfree_d  = 1'b1;                  
               end             
             else if ( wbufid_fifo_taken )
               begin
                  wbufid_stat_write    = 1'b1;
                  wbufid_stat_wraddr   = wbufid_fifo_rdata[wbufid_width-1:0];
                  wbufid_stat_wrdata   = 1'b1;
                  wbufid_stat_rdaddr   = wbufid_fifo_rdata[wbufid_width-1:0];
                  wbufid_stat_alloc_d  = 1'b1;                   
               end                  
          end

        wbufid_stat_ferror[0] = (wbufid_stat_idfree_q && !wbufid_stat_rddata);  // freeing id but status is already free        
        wbufid_stat_ferror[1] = (wbufid_stat_alloc_q && wbufid_stat_rddata);  // allocating id but status is in use
        
     end // always @ *

   
   // free a wbufid
   // cmd has higher priority, no backpressure.  unmap gets an ack if taken
   always @*
     begin
        idfree_v_d             = 1'b0;
        idfree_wbufid_d        = cmd_wbuf_idfree_wbufid;
        idfree_wbufid_par_d    = cmd_wbuf_idfree_wbufid_par;
        wbuf_unmap_idfree_ack  = 1'b0;
        
        if( cmd_wbuf_idfree_valid )
          begin
             idfree_v_d   = 1'b1;
          end
        else
          begin
             idfree_wbufid_d      = unmap_wbuf_idfree_wbufid;
             idfree_wbufid_par_d  = unmap_wbuf_idfree_wbufid_par;
             if(  unmap_wbuf_idfree_valid )
               begin
                  idfree_v_d = 1'b1;                  
                  wbuf_unmap_idfree_ack = 1'b1;
               end
          end
     end   
       

   
   //-------------------------------------------------------
   // RAM for write buffers
   //-------------------------------------------------------
   
   localparam wbuf_width = data_width; 
   localparam wbuf_par_width = data_par_width; 
   localparam wbuf_words_per_entry = wbuf_size/(wbuf_width/8);
   localparam wbuf_entry_awidth = $clog2(wbuf_words_per_entry);
   localparam wbuf_words_total = wbuf_numids * wbuf_words_per_entry;
   localparam wbuf_addr_width = $clog2(wbuf_words_total);

   // need to memory initialize to good parity
   // unmap doesn't write full buffer.  Don't assume NVMe controller won't
   // read more than it needs to.
   
   reg                [wbuf_width-1:0] wbuf_wrdata;
   reg            [wbuf_par_width-1:0] wbuf_wrdata_par;
   wire          [wbuf_addr_width-1:0] wbuf_wraddr;
   reg         [     wbufid_width-1:0] wbuf_wr_wbufid;
   reg         [wbuf_entry_awidth-1:0] wbuf_wr_offset;
   reg                                 wbuf_write;
   wire        [       wbuf_width-1:0] wbuf_rddata;
   wire        [   wbuf_par_width-1:0] wbuf_rddata_par;
   wire         [ wbuf_addr_width-1:0] wbuf_rdaddr;
   wire                                wbuf_read;
   reg             [wbuf_addr_width:0] wbuf_init_q;
   reg                                 wbuf_init_done_q;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             wbuf_init_q <= zero[wbuf_addr_width:0];
             wbuf_init_done_q <= 1'b0;
          end
        else
          begin
             if( wbuf_init_q != wbuf_words_total[wbuf_addr_width:0] )
               begin
                  wbuf_init_q <= wbuf_init_q + one[wbuf_addr_width:0];
               end
             else
               begin
                  wbuf_init_done_q <= 1'b1;
               end             
          end
     end

   assign wbuf_wraddr = { wbuf_wr_wbufid, wbuf_wr_offset };
   

   wire wbuf_rddbiterr;
   // xpm_memory_sdpram: Simple Dual Port RAM
       // Xilinx Parameterized Macro, Version 2016.4
   xpm_memory_sdpram # (
  
         // Common module parameters
         .MEMORY_SIZE        (wbuf_width*wbuf_words_total),            //positive integer
         .MEMORY_PRIMITIVE   ("ultra"),          //string; "auto", "distributed", "block" or "ultra";
         .CLOCKING_MODE      ("common_clock"),  //string; "common_clock", "independent_clock" 
         .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem" 
         .MEMORY_INIT_PARAM  (""    ),          //string;
         .USE_MEM_INIT       (1),               //integer; 0,1
         .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin" 
         .MESSAGE_CONTROL    (0),               //integer; 0,1
         .ECC_MODE           ("both_encode_and_decode"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode" 
         .AUTO_SLEEP_TIME    (0),               //Do not Change
       
         // Port A module parameters
         .WRITE_DATA_WIDTH_A (wbuf_width),              //positive integer
         .BYTE_WRITE_WIDTH_A (wbuf_width),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
         .ADDR_WIDTH_A       (wbuf_addr_width),               //positive integer
       
         // Port B module parameters
         .READ_DATA_WIDTH_B  (wbuf_width),              //positive integer
         .ADDR_WIDTH_B       (wbuf_addr_width),               //positive integer
         .READ_RESET_VALUE_B ("0"),             //string
         .READ_LATENCY_B     (1),               //non-negative integer
         .WRITE_MODE_B       ("read_first")     //string; "write_first", "read_first", "no_change" 
       
       ) xpm_memory_sdpram_inst (
       
         // Common module ports
         .sleep          (1'b0),
       
         // Port A module ports
         .clka           (clk),
         .ena            (1'b1),
         .wea            (wbuf_write),
         .addra          (wbuf_wraddr),
         .dina           (wbuf_wrdata),
         .injectsbiterra (1'b0),
         .injectdbiterra (1'b0),
       
         // Port B module ports
         .clkb           (1'b0),
         .rstb           (1'b0),
         .enb            (1'b1),
         .regceb         (1'b1),
         .addrb          (wbuf_rdaddr),
         .doutb          (wbuf_rddata),
         .sbiterrb       (),
         .dbiterrb       (wbuf_rddbiterr) // fatal error       
       );
    assign s1_perror[1] = wbuf_rddbiterr;

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(wbuf_width)
      ) ipgen_wbuf_rddata 
       (.oddpar(1'b1),.data(wbuf_rddata),.datap(wbuf_rddata_par)); 

   reg                                 stat_valid_q, stat_valid_d;
   wire                          [1:0] xxq_perror_ack;

   always @*
     begin       
        wbuf_pe_inj_d      = wbuf_pe_inj_q;
        if (regs_wdata_pe_errinj_1cycle_valid & regs_sntl_pe_errinj_valid & regs_xxx_pe_errinj_decode[11:8] == 4'h4)
          begin
             wbuf_pe_inj_d[0]  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
             wbuf_pe_inj_d[1]  = (regs_xxx_pe_errinj_decode[3:0]==4'h1);
             wbuf_pe_inj_d[2]  = (regs_xxx_pe_errinj_decode[3:0]==4'h2);
             wbuf_pe_inj_d[3]  = (regs_xxx_pe_errinj_decode[3:0]==4'h3);
          end 
        if (wbuf_pe_inj_q[0] & stat_valid_d)
          wbuf_pe_inj_d[0] = 1'b0;
        if (wbuf_pe_inj_q[1] & wbuf_read)
          wbuf_pe_inj_d[1] = 1'b0;
        if (wbuf_pe_inj_q[2] & xxq_perror_ack[0])
          wbuf_pe_inj_d[2] = 1'b0;
        if (wbuf_pe_inj_q[3] & xxq_perror_ack[1])
          wbuf_pe_inj_d[3] = 1'b0;
     end  

   wire    [1:0]    xxq_perror_inj = wbuf_pe_inj_q[3:2];

   //-------------------------------------------------------
   // request to wdata
   //-------------------------------------------------------


   // save cid and upper part of reloff for comparision with response
   localparam wbuf_beatid_lower = wbuf_entry_awidth + $clog2(data_bytes); 
   localparam wbuf_stat_width = 2 + cid_width + beatid_width - wbuf_beatid_lower;
   reg [wbuf_stat_width-1:0] stat_wrdata, stat_rddata;
   reg    [wbufid_width-1:0] stat_wraddr, stat_rdaddr;
   reg                       stat_write;   
   reg [1+wbuf_stat_width-1:0] stat_mem[wbuf_numids-1:0];

   // save request info to unmap data
   reg                        unmap_valid_q, unmap_valid_d;   
   reg                        unmap_stat_valid_q, unmap_stat_valid_d;   
   reg        [cid_width-1:0] unmap_cid_q, unmap_cid_d;
   reg    [cid_par_width-1:0] unmap_cid_par_q, unmap_cid_par_d; 
   reg     [wbufid_width-1:0] unmap_wbufid_q, unmap_wbufid_d;
   reg [wbufid_par_width-1:0] unmap_wbufid_par_q, unmap_wbufid_par_d; 
   reg                 [63:0] unmap_lba_q, unmap_lba_d;
   reg                 [15:0] unmap_numblks_q, unmap_numblks_d;
   reg [wbuf_entry_awidth-1:0] unmap_offset_q, unmap_offset_d;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             unmap_valid_q      <= 1'b0;   
             unmap_stat_valid_q <= 1'b0;               
          end
        else
          begin             
             unmap_valid_q      <= unmap_valid_d;   
             unmap_stat_valid_q <= unmap_stat_valid_d;                
          end
     end
   
   always @(posedge clk)
     begin
        unmap_cid_q        <= unmap_cid_d;
        unmap_cid_par_q    <= unmap_cid_par_d; 
        unmap_wbufid_q     <= unmap_wbufid_d;
        unmap_wbufid_par_q <= unmap_wbufid_par_d; 
        unmap_lba_q        <= unmap_lba_d;
        unmap_numblks_q    <= unmap_numblks_d;
        unmap_offset_q     <= unmap_offset_d;
     end
   
   //Parity gen for stat_mem 
   wire                        stat_wrdata_par ;
   reg                         stat_rddata_par ;   

   nvme_pgen#
     (
      .bits_per_parity_bit(wbuf_stat_width),
      .width(wbuf_stat_width)
      ) ipgen_stat_mem 
       (.oddpar(1'b1),.data(stat_wrdata),.datap(stat_wrdata_par)); 

   always @(posedge clk)   
     {stat_rddata_par,stat_rddata} <= stat_mem[stat_rdaddr] ;
   
   always @(posedge clk)
     if (stat_write)
       stat_mem[stat_wraddr] <= {stat_wrdata_par,stat_wrdata};

   always @*
     begin
        // send request directly to wdata (except unmap)
        wbuf_wdata_req_valid       = cmd_wbuf_req_valid & ~cmd_wbuf_req_unmap & ~unmap_valid_q;
        wbuf_wdata_req_tag         = cmd_wbuf_req_cid[tag_width-1:0] ;
        wbuf_wdata_req_tag_par     = cmd_wbuf_req_cid_par[0];
        wbuf_wdata_req_reloff      = cmd_wbuf_req_reloff;
        wbuf_wdata_req_length      = wbuf_size[wdatalen_width-1:0];
        wbuf_wdata_req_length_par  = 1'b0;
        
        wbuf_wdata_req_wbufid      = cmd_wbuf_req_wbufid;
        wbuf_wdata_req_wbufid_par  = cmd_wbuf_req_wbufid_par;
        wbuf_cmd_req_ready         = wdata_wbuf_req_ready & ~unmap_valid_q & wbuf_init_done_q;
       
        // save reloff & cid for when wdata responds
        stat_write                 = cmd_wbuf_req_valid & wdata_wbuf_req_ready;
        stat_wraddr                = cmd_wbuf_req_wbufid;  
        stat_wrdata                = { cmd_wbuf_req_reloff[beatid_width-1:wbuf_beatid_lower], cmd_wbuf_req_cid_par, cmd_wbuf_req_cid };
        
     end

   //-------------------------------------------------------
   // response from wdata
   //-------------------------------------------------------

   reg                        stat_rd_q, stat_rd_d;   
   reg        [cid_width-1:0] stat_cid_q, stat_cid_d;
   reg    [cid_par_width-1:0] stat_cid_par_q, stat_cid_par_d;  
   reg     [wbufid_width-1:0] stat_wbufid_q, stat_wbufid_d;
   reg [wbufid_par_width-1:0] stat_wbufid_par_q, stat_wbufid_par_d; 
   reg                        stat_error_q, stat_error_d;

   // check mem parity 
   nvme_pcheck#
     (
      .bits_per_parity_bit(wbuf_stat_width),
      .width(wbuf_stat_width)
      ) ipcheck_stat_mem 
       (.oddpar(1'b1),.data({stat_rddata[wbuf_stat_width-1:1],(stat_rddata[0]^wbuf_pe_inj_q[0])}),.datap(stat_rddata_par),.check(stat_valid_d),.parerr(s1_perror[0])); 


   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin             
             stat_valid_q <= 1'b0;
          end
        else
          begin           
             stat_valid_q <= stat_valid_d;
          end        
     end

   always @(posedge clk)
     begin
        stat_rd_q         <= stat_rd_d;
        stat_cid_q        <= stat_cid_d;
        stat_cid_par_q    <= stat_cid_par_d; 
        stat_wbufid_q     <= stat_wbufid_d;
        stat_wbufid_par_q <= stat_wbufid_par_d;
        stat_error_q      <= stat_error_d;
     end   
     



   wire [data_par_width+data_width-1:data_width] wbuf_data_unmap_par;
   wire                         [data_width-1:0] wbuf_data_unmap = {unmap_lba_q, {16'h00, unmap_numblks_q}, 32'h0};
   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(data_width)
      ) ipgen_unmap
       (.oddpar(1'b1),.data(wbuf_data_unmap),.datap(wbuf_data_unmap_par));      

   reg stat_ferror;   
   always @*
     begin       
        // hold unmap data until written and response sent to cmd
        unmap_valid_d              = unmap_valid_q;   
        unmap_stat_valid_d         = unmap_stat_valid_q;   
        unmap_cid_d                = unmap_cid_q;
        unmap_cid_par_d            = unmap_cid_par_q; 
        unmap_wbufid_d             = unmap_wbufid_q;
        unmap_wbufid_par_d         = unmap_wbufid_par_q; 
        unmap_lba_d                = unmap_lba_q;
        unmap_numblks_d            = unmap_numblks_q;
        unmap_offset_d             = unmap_offset_q;
        wbuf_write                 = 1'b0;
        
        if( cmd_wbuf_req_valid && cmd_wbuf_req_unmap && !unmap_valid_q)
          begin             
             unmap_valid_d      = 1'b1;
             unmap_stat_valid_d = 1'b0;
             unmap_cid_d        = cmd_wbuf_req_cid;
             unmap_cid_par_d    = cmd_wbuf_req_cid_par;
             unmap_wbufid_d     = cmd_wbuf_req_wbufid;
             unmap_wbufid_par_d = cmd_wbuf_req_wbufid_par; 
             unmap_lba_d        = cmd_wbuf_req_lba;
             unmap_numblks_d    = cmd_wbuf_req_numblks + 16'h1;   // numblks is 0s based but dataset management range length is not
             unmap_offset_d     = cmd_wbuf_req_reloff[wbuf_entry_awidth-1:0];
          end
        
        wbuf_wdata_rsp_ready  = ~(stat_rd_q || stat_valid_q);
        if( !wbuf_init_done_q )
          begin
             wbuf_wrdata      = zero[wbuf_width-1:0];
             wbuf_wrdata_par  = ~zero[wbuf_par_width-1:0];
             { wbuf_wr_wbufid, wbuf_wr_offset } = wbuf_init_q;            
             wbuf_write       = 1'b1;
          end
        else if( wdata_wbuf_rsp_valid )
          begin
             wbuf_wrdata      = wdata_wbuf_rsp_data;
             wbuf_wrdata_par  = wdata_wbuf_rsp_data_par;
             wbuf_wr_wbufid   = wdata_wbuf_rsp_wbufid;
             wbuf_wr_offset   = wdata_wbuf_rsp_beat[wbuf_entry_awidth-1:0];
             wbuf_write       = ~wdata_wbuf_rsp_end & wbuf_wdata_rsp_ready;
          end
        else
          begin
             // unmap request is lower priority
             // see NVMe 1.2 section 6.7 dataset management for data layout
             wbuf_wrdata         = wbuf_data_unmap;
             wbuf_wrdata_par     = wbuf_data_unmap_par;
             wbuf_wr_wbufid      = unmap_wbufid_q;
             wbuf_wr_offset      = unmap_offset_q;
             if( unmap_valid_q & ~unmap_stat_valid_q )
               begin
                  wbuf_write          = 1'b1;                
                  unmap_stat_valid_d  = 1'b1;                
               end
          end
                
        stat_rd_d                   = 1'b0;
        stat_valid_d                = stat_valid_q;
        stat_cid_d                  = stat_cid_q;
        stat_cid_par_d              = stat_cid_par_q;
        stat_wbufid_d               = stat_wbufid_q;
        stat_wbufid_par_d           = stat_wbufid_par_q;
        stat_error_d                = stat_error_q;
                
        stat_ferror                 = 1'b0;

        // read stat_mem and check tag, beat vs cid, reloff
        stat_rdaddr                 = wdata_wbuf_rsp_wbufid;


        if( wbuf_wdata_rsp_ready & wdata_wbuf_rsp_valid & wdata_wbuf_rsp_end )
          begin
             stat_rd_d                  = 1'b1;
             stat_cid_d[tag_width-1:0]  = wdata_wbuf_rsp_tag;
             stat_cid_par_d[0]          = wdata_wbuf_rsp_tag_par;
             stat_wbufid_d              = wdata_wbuf_rsp_wbufid;
             stat_wbufid_par_d          = wdata_wbuf_rsp_wbufid_par;
             stat_error_d               = wdata_wbuf_rsp_error;                 
          end

        if( stat_rd_q )    
          begin         
             stat_valid_d    = 1'b1;
             stat_cid_d      = stat_rddata[cid_width-1:0];
             stat_cid_par_d  = stat_rddata[cid_par_width + cid_width-1:cid_width]; 
             if( stat_cid_q[tag_width-1:0] != stat_rddata[tag_width-1:0] )
               begin
                  // tag mismatch - fatal error
                  stat_ferror = 1'b1;
               end
          end
        
        wbuf_cmd_status_valid = unmap_stat_valid_q | stat_valid_q;
        if( unmap_stat_valid_q )
          begin                  
             wbuf_cmd_status_cid         = unmap_cid_q;
             wbuf_cmd_status_cid_par     = unmap_cid_par_q;
             wbuf_cmd_status_wbufid      = unmap_wbufid_q;
             wbuf_cmd_status_wbufid_par  = unmap_wbufid_par_q;
             wbuf_cmd_status_error       = 1'b0;
             if( cmd_wbuf_status_ready )
               begin
                  unmap_valid_d = 1'b0;
                  unmap_stat_valid_d = 1'b0;
               end
          end
        else
          begin
             wbuf_cmd_status_cid         = stat_cid_q;
             wbuf_cmd_status_cid_par     = stat_cid_par_q;
             wbuf_cmd_status_wbufid      = stat_wbufid_q;
             wbuf_cmd_status_wbufid_par  = stat_wbufid_par_q;
             wbuf_cmd_status_error       = stat_error_q;
             if( stat_valid_q & cmd_wbuf_status_ready )
               begin
                  stat_valid_d = 1'b0;
               end
          end
               
     end

      
   //-------------------------------------------------------
   // DMA access to wbuf
   //-------------------------------------------------------


   nvme_xxq_dma#
     (
      .addr_width(addr_width),
      .sq_num_queues(1),
      .sq_ptr_width(1),
      .sq_addr_width(wbuf_addr_width),
      .sq_rdwidth(data_width),
      .sq_rd_latency(2)
      
      ) dma
       (  
          .reset                         (reset),
          .clk                           (clk),
                
          .q_reset                       (1'b0),
          .q_init_done                   (),
       
          .sq_rdaddr                     (wbuf_rdaddr),
          .sq_rdval                      (wbuf_read),
          .sq_id                         (),
          .sq_rddata                     ({wbuf_rddata_par,wbuf_rddata}),

          // ignore writes to wbuf
          .cq_wren                       (),
          .cq_id                         (),
          .cq_wraddr                     (),
          .cq_wrdata                     (),
       
          .pcie_xxq_valid                (pcie_sntl_wbuf_valid),
          .pcie_xxq_data                 (pcie_sntl_wbuf_data),
          .pcie_xxq_first                (pcie_sntl_wbuf_first),
          .pcie_xxq_last                 (pcie_sntl_wbuf_last),
          .pcie_xxq_discard              (pcie_sntl_wbuf_discard),        
          .xxq_pcie_pause                (sntl_pcie_wbuf_pause),
          
          .xxq_pcie_cc_data              (sntl_pcie_wbuf_cc_data),
          .xxq_pcie_cc_first             (sntl_pcie_wbuf_cc_first),
          .xxq_pcie_cc_last              (sntl_pcie_wbuf_cc_last),
          .xxq_pcie_cc_discard           (sntl_pcie_wbuf_cc_discard),
          .xxq_pcie_cc_valid             (sntl_pcie_wbuf_cc_valid),   
          .pcie_xxq_cc_ready             (pcie_sntl_wbuf_cc_ready),
          
          .req_dbg_event                (),
          .xxq_dma_perror               (wbuf_perror_int[0]),
          .xxq_perror_inj               (xxq_perror_inj),
          .xxq_perror_ack               (xxq_perror_ack)
          );

   
   always @*
     begin
        wbuf_regs_error[0] = stat_ferror;
        wbuf_regs_error[1] = wbufid_ferror;
        wbuf_regs_error[3:2] = wbufid_stat_ferror;        
     end
   
endmodule


