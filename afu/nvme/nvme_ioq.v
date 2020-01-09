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
//  File : nvme_ioq.v
//  *************************************************************************
//  *************************************************************************
//  Description : FlashGT+ NVMe I/O Q
//
//  Implements I/O Submission Queue (ISQ) and I/O Completion Queue (ICQ)
//
//    ISQ entries are inserted from the sislite interface. When inserted,
//    a mmio write to the ASQ tail doorbell is generated.  The NVMe controller
//    then generates DMA reads for the ISQ entry.  ISQ entries are 64B.
//    
//    ICQ entries are inserted by the NVMe controller using DMA writes.  The 
//    completion queue entry includes the new ISQ head pointer, a phase bit
//    to help track when an entry is inserted, and a status. ICQ entries are 16B.
//
//    Interfaces to/from the NVMe controller are 128b.
//
//  Number of Queues/Entries:
//
//    completion queues:  1
//      Currently sized at 256 entries to match number of keys on sislite interface.  
//      probably should be smaller
//
//    submissions queues: 16 max
//      1 queue is not enough to keep the NVMe controller busy.
//      16 queues max is based on fio performance tests
//      Need to have enough entries to avoid backpressure on the sislite interface.
//        NVMe spec says a queue is full when there's one entry unused, so need to
//        take care here.
//    
//  *************************************************************************

module nvme_ioq#
  (     
    parameter data_width   = 128,
    parameter addr_width   = 48,
    parameter cid_width    = 16,
    parameter wbuf_size    = 4096, // 4KB per write buffer
    parameter wbuf_numids  = 16,    // number of write buffers
    parameter wbufid_width = $clog2(wbuf_numids),

    parameter datalen_width   = 25,  
    parameter data_bytes      = data_width/8,
    parameter beatid_width    = datalen_width-$clog2(data_bytes),    
        
    parameter num_isq = 16,  // max number of I/O submissions queues
    parameter isq_first_id = 2,
    parameter isq_idwidth = $clog2(num_isq+isq_first_id),
    parameter isq_num_entries = 32,  // must have num_isq*(isq_num_entries-1) > # of fc tags (256) to avoid backpressure here.  one entry per queue is unusable
    parameter isq_ptr_width = $clog2(num_isq*isq_num_entries),  // size for configuration with only 1 queue
        
    parameter num_icq = 1,
    parameter icq_num_entries = 512,    
    parameter icq_ptr_width = $clog2(icq_num_entries)
    )
   (
   
    input                     reset,
    input                     clk, 

    
    //-------------------------------------------------------
    // sntl insert into ISQ
    //-------------------------------------------------------

    output                    ioq_sntl_sqid_valid, // there's a submission queue entry available
    output  [isq_idwidth-1:0] ioq_sntl_sqid, // id of the submission queue with fewest entries in use
    input                     sntl_ioq_sqid_ack,
    input   [isq_idwidth-1:0] sntl_ioq_sqid, // id used by command

    
    input              [63:0] sntl_ioq_req_lba, // 512B or 4K block size supported
    input              [15:0] sntl_ioq_req_numblks, // number of blocks - 1 
    input              [31:0] sntl_ioq_req_nsid,
    input               [7:0] sntl_ioq_req_opcode, //  Read  = 0x02 Write = 0x01 Flush = 0x00  Write Uncorrectable = 0x04 Dataset Management = 0x09
    input              [15:0] sntl_ioq_req_cmdid,
    input  [wbufid_width-1:0] sntl_ioq_req_wbufid,
    input [datalen_width-1:0] sntl_ioq_req_reloff,
    input                     sntl_ioq_req_fua,
    input   [isq_idwidth-1:0] sntl_ioq_req_sqid,
    input                     sntl_ioq_req_valid,
    output reg                ioq_sntl_req_ack,
    
    //-------------------------------------------------------
    // sntl completions from ICQ
    //-------------------------------------------------------

    output reg         [14:0] ioq_sntl_cpl_status,
    output reg         [15:0] ioq_sntl_cpl_cmdid,
    output reg          [1:0] ioq_sntl_cpl_cmdid_par,
    output reg                ioq_sntl_cpl_valid,
    input                     sntl_ioq_cpl_ack, 
    
    //-------------------------------------------------------
    // Admin Q doorbell write
    //-------------------------------------------------------
    output reg                ioq_pcie_wrvalid,
    output reg         [31:0] ioq_pcie_wraddr,
    output reg         [15:0] ioq_pcie_wrdata,
    input                     pcie_ioq_wrack,
     
    //-------------------------------------------------------
    // DMA requests to I/O Q
    //-------------------------------------------------------
  
    input                     pcie_ioq_valid,
    input             [144:0] pcie_ioq_data, 
    input                     pcie_ioq_first, 
    input                     pcie_ioq_last, 
    input                     pcie_ioq_discard, 
    output                    ioq_pcie_pause,
    
    //-------------------------------------------------------
    // DMA response from I/O Q
    //-------------------------------------------------------        
 
    output            [144:0] ioq_pcie_cc_data,
    output                    ioq_pcie_cc_first,
    output                    ioq_pcie_cc_last,
    output                    ioq_pcie_cc_discard,
    output                    ioq_pcie_cc_valid,
    input                     pcie_ioq_cc_ready,

    //-------------------------------------------------------
    // ucontrol IO bus
    //-------------------------------------------------------
    input              [31:0] ctl_ioq_ioaddress,
    input                     ctl_ioq_ioread_strobe, 
    input              [35:0] ctl_ioq_iowrite_data,
    input                     ctl_ioq_iowrite_strobe,
    output reg         [31:0] ioq_ctl_ioread_data, 
    output reg                ioq_ctl_ioack,
    
    //-------------------------------------------------------
    // from microcontroller
    //-------------------------------------------------------

    input                     ctl_xx_ioq_enable,

    output                    ioq_xx_isq_empty,
    output reg                ioq_xx_icq_empty,

    //-------------------------------------------------------
    // debug
    //-------------------------------------------------------
  
    input                     regs_ioq_dbg_rd,
    input               [9:0] regs_ioq_dbg_addr, // 8B offset
    output reg         [63:0] ioq_regs_dbg_data,
    output reg                ioq_regs_dbg_ack,
    
    //-------------------------------------------------------
    // error reports & timeouts
    //-------------------------------------------------------
    input              [15:0] regs_ioq_icqto,
    input                     regs_xx_tick2, // 16.384 ms per tick
    
    output reg          [3:0] ioq_regs_faterr,
    output reg          [3:0] ioq_regs_recerr,
    output              [1:0] ioq_perror_ind,
    // ----------------------------------------------------------
    // parity error inject 
    // ----------------------------------------------------------
    input                     regs_ioq_pe_errinj_valid,
    input              [15:0] regs_xxx_pe_errinj_decode, 
    input                     regs_wdata_pe_errinj_1cycle_valid 
    

    );

`include "nvme_func.svh"

   wire           s1_perror; 
   wire     [1:0] ioq_perror_int;  


// set/reset/ latch for parity errors
    nvme_srlat#
    (.width(1))  iioq_sr   
    (.clk(clk),.reset(reset),.set_in(s1_perror),.hold_out(ioq_perror_int[1]));

  assign ioq_perror_ind = ioq_perror_int;


   //-------------------------------------------------------
   // I/O Submission Queue (ISQ)
   //-------------------------------------------------------

   // 64B per queue entry
   // 2 entries minimum per spec
   // 
   // read interface width:  16B - 4x16B per entry
   // write interface width: 16B - 4x16B per entry

   // one memory array shared between all ISQs
   
   localparam isq_entry_bytes = 64;
   localparam isq_rdwidth = 128;
   localparam isq_par_rdwidth = 128/8;
   localparam isq_wrwidth = 128;
   localparam isq_par_wrwidth = 128/8;
   localparam isq_words_per_entry = isq_entry_bytes/(isq_rdwidth/8);
   localparam isq_words_per_q = isq_num_entries * isq_words_per_entry;
   localparam isq_num_words = num_isq*isq_words_per_q;
   localparam isq_num_wren = isq_rdwidth / isq_wrwidth;
   localparam isq_addr_width = clogb2(isq_num_words);

   (* ram_style = "ultra" *)
   reg  [    isq_par_wrwidth+isq_rdwidth-1:0] isq_mem[isq_num_words-1:0];
   
   reg                 [    isq_wrwidth-1:0] isq_wrdata;
   reg                                       isq_wren;
   reg                 [ isq_addr_width-1:0] isq_wraddr;
   reg [    isq_par_wrwidth+isq_rdwidth-1:0] isq_rddata;
   reg                  [isq_addr_width-1:0] isq_rdaddr;
   
   wire                                      isq_rdval;
   wire                 [isq_addr_width-1:0] isq_rdoffset;

   // generate isq_wrdata parity
   wire                [isq_par_wrwidth-1:0] isq_wrdata_par;

   nvme_pgen#
  (
   .bits_per_parity_bit(8),
   .width(128)
  ) ipgen_isq_wrdata 
  (.oddpar(1'b1),.data(isq_wrdata),.datap(isq_wrdata_par)); 
  


   
   always @(posedge clk)   
      isq_rddata <= isq_mem[isq_rdaddr];
  
   always @(posedge clk)
     if (isq_wren)
       isq_mem[isq_wraddr] <= {isq_wrdata_par,isq_wrdata};

   reg isq_rddbg_q, isq_rddbg_d;
   reg isq_cfg_rddbg_q, isq_cfg_rddbg_d;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             isq_rddbg_q <= 1'b0;
             isq_cfg_rddbg_q <= 1'b0;
          end
        else
          begin
             isq_rddbg_q <= isq_rddbg_d;
             isq_cfg_rddbg_q <= isq_cfg_rddbg_d;
          end
     end

   // select read address
   // if there's a read from pcie, select that otherwise allow debug read
   reg dbg_rd_isq;
   reg [isq_addr_width-1:0] dbg_rd_isq_addr;
   always @*
     begin        
        isq_rdaddr = isq_rdoffset;
        isq_rddbg_d = 1'b0;
       
        // debug - read access
        if( ~isq_rdval && dbg_rd_isq && ~isq_rddbg_q)
          begin            
             isq_rdaddr = dbg_rd_isq_addr;
             isq_rddbg_d = 1'b1;
          end        
     end
          
   //-------------------------------------------------------
   // configuration for each ISQ
   //-------------------------------------------------------

   // each ISQ has the following:
   // base address - set by ucode with starting address in isq_mem
   // size - set by ucode with number of entries
   // tail - updated by isq state machine.  init by ucode
   // head - updated with value from icq.  init by ucode
   // doorbell offset - read by isq to generate doorbell write.  init by ucode.
   // full, empty - flags updated when either head or tail is updated
   // used - number of entries allocated
   //        incremented when isq is selected by sntl_cmd
   //        decremented when icq completes a command

   wire [num_isq-1:0] isq_empty, isq_full, isq_enable;

   // track when a command completes
   reg [isq_idwidth-1:0] icq_cmp_sqid;
   reg                   icq_cmp_valid;

   // update the queue size via ucode
   reg                   isq_upd_valid;
   reg [isq_idwidth-1:0] isq_upd_sqid;
   reg [isq_ptr_width:0] isq_upd_size;
   
   genvar isq;
   generate
      for( isq=isq_first_id; isq<(num_isq+isq_first_id); isq=isq+1)
        begin :isq_regs
           reg enable_q, enable_d;
           reg empty_q, empty_d;
           reg full_q, full_d;
           reg [isq_ptr_width:0] used_q, used_d;
           reg [isq_ptr_width:0] last_q, last_d;

           always @(posedge clk or posedge reset)
             begin
                if( reset )
                  begin
                     enable_q <= 1'b0;
                     empty_q <= 1'b1;
                     full_q <= 1'b1;
                     used_q <= zero[isq_ptr_width:0];
                     last_q <= zero[isq_ptr_width:0];
                  end
                else
                  begin
                     enable_q <= enable_d;
                     empty_q <= empty_d;
                     full_q <= full_d;
                     used_q <= used_d;
                     last_q <= last_d;
                  end
             end

           assign isq_empty[isq-isq_first_id] = empty_q;
           assign isq_full[isq-isq_first_id] = full_q;
           assign isq_enable[isq-isq_first_id] = enable_q;

           
           always @*
             begin
                enable_d = enable_q;
                full_d = full_q;
                empty_d = empty_q;
                used_d = used_q;
                last_d = last_q;

                // track number of isq entries in use
                // decrement when completion is read from icq
                if( icq_cmp_valid && icq_cmp_sqid==isq )
                  begin
                     used_d = used_d - 1;                    
                  end
                // increment when sntl_cmd allocates a command to a isq
                if( sntl_ioq_sqid_ack && sntl_ioq_sqid==isq )
                  begin
                     used_d = used_d + 1;                                      
                  end

                // update size and whether the isq is enabled
                if( isq_upd_valid && isq_upd_sqid==isq )
                  begin
                     last_d = isq_upd_size-1;
                     enable_d = isq_upd_size!=0;
                  end
                
                if( ctl_xx_ioq_enable==1'b0 )
                  begin
                     used_d = 0;                     
                  end

                full_d = used_q==last_q;   
                empty_d = used_q==0;
             end
        end
   endgenerate

   // use distributed ram for base address, size, head, tail, and doorbell registers
   // addr = { regno, sqid }
   //           1 = { doorbell offset, base }
   //           0 = { head, tail, size }
  
   localparam isq_cfg_width=48;
   localparam isq_cfg_words=num_isq*2;
   localparam isq_cfg_awidth=$clog2(isq_cfg_words);
   (* ram_style="distributed" *)
   reg [isq_cfg_width-1:0] isq_cfg_mem [isq_cfg_words-1:0];
   reg   [isq_idwidth-1:0] isq_cfg_sqid;
   reg                     isq_cfg_addr;
   reg [isq_cfg_awidth-1:0] isq_cfg_rdaddr, isq_cfg_wraddr;
   reg  [isq_cfg_width-1:0] isq_cfg_rddata, isq_cfg_wrdata;
   reg                [2:0] isq_cfg_wren;

   always @*
     begin
        isq_cfg_rdaddr[isq_cfg_awidth-2:0] = isq_cfg_sqid - isq_first_id[isq_idwidth-1:0];
        isq_cfg_rdaddr[isq_cfg_awidth-1] = isq_cfg_addr;
        isq_cfg_wraddr = isq_cfg_rdaddr;
     end
   
   
   always @(posedge clk)
     begin
        if (isq_cfg_wren[0])
          isq_cfg_mem[isq_cfg_wraddr][15:0] <= isq_cfg_wrdata[15:0];
        if (isq_cfg_wren[1])
          isq_cfg_mem[isq_cfg_wraddr][31:16] <= isq_cfg_wrdata[31:16];  
        if (isq_cfg_wren[2])
          isq_cfg_mem[isq_cfg_wraddr][47:32] <= isq_cfg_wrdata[47:32];  
     end

   always @*   
      isq_cfg_rddata <= isq_cfg_mem[isq_cfg_rdaddr];
   
   // updates to the head come from the completion queue
   reg                      icq_isq_head_valid;
   reg                      isq_icq_head_ack;
   reg    [isq_idwidth-1:0] icq_isq_head_sqid;
   reg  [isq_ptr_width-1:0] icq_isq_head;

   // isq state machine reads all of the ram contents for a isq
   // and then writes the tail pointer after an insert
   // this is highest priority so no backpressure
   reg    [isq_idwidth-1:0] isqsm_cfg_sqid;
   reg                      isqsm_cfg_addr;
   reg  [isq_cfg_width-1:0] isqsm_cfg_wrdata;
   reg                      isqsm_cfg_rdvalid;
   reg                [2:0] isqsm_cfg_wren;
  
   assign ioq_xx_isq_empty = (&isq_empty);

   reg                      iowrite_strobe_q, ioread_strobe_q;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             iowrite_strobe_q <= 1'b0;
             ioread_strobe_q <= 1'b0;
          end
        else
          begin
             iowrite_strobe_q <= ctl_ioq_iowrite_strobe | (iowrite_strobe_q & ~ioq_ctl_ioack);
             ioread_strobe_q <= ctl_ioq_ioread_strobe | (ioread_strobe_q & ~ioq_ctl_ioack);
          end
     end
   

          
   reg                      isq_cfg_rd;
   always @*
     begin

        icq_cmp_valid = 1'b0;
        icq_cmp_sqid = icq_isq_head_sqid;
        
        isq_upd_valid = 1'b0;
        isq_upd_sqid = ctl_ioq_ioaddress[isq_idwidth+3:4]+isq_first_id;
        isq_upd_size = ctl_ioq_iowrite_data[isq_ptr_width:0];
        
        isq_icq_head_ack     = 1'b0;
        ioq_ctl_ioack        = 1'b0;
        if( ctl_ioq_ioaddress[2] )
          ioq_ctl_ioread_data = isq_cfg_rddata[47:16];
        else
          ioq_ctl_ioread_data  = {16'h0,isq_cfg_rddata[15:0]};
        
        // highest priority is isqsm
        isq_cfg_sqid           = isqsm_cfg_sqid;
        isq_cfg_addr           = isqsm_cfg_addr;        
        isq_cfg_wrdata         = isqsm_cfg_wrdata;        
        isq_cfg_wren           = isqsm_cfg_wren;
        isq_cfg_rd             = isqsm_cfg_rdvalid;
       
        // next priority is icq completions
        if( icq_isq_head_valid && isq_cfg_wren==3'b000 && isq_cfg_rd==1'b0 )
          begin
             // write head and read tail, size
             isq_cfg_sqid           = icq_isq_head_sqid;
             isq_cfg_addr           = 1'b0;
             isq_cfg_wrdata[47:32]  = icq_isq_head;
             isq_cfg_wren[2]        = 1'b1; // write only the head pointer
             isq_icq_head_ack       = 1'b1;
             icq_cmp_valid          = 1'b1;
          end

         if( isq_cfg_wren==3'b000 && isq_cfg_rd==1'b0 )
           begin
              // map ucode address for 32b register to ram
              // ioaddress[7:4]=sq id
              // ioaddress[3:2]:
              //   0 = resv/size
              //   1 = head/tail
              //   2 = resv/base
              //   3 = doorbell addr
              if( iowrite_strobe_q )
                begin
                   isq_cfg_addr  = ctl_ioq_ioaddress[3];
                   isq_cfg_sqid  = ctl_ioq_ioaddress[isq_idwidth+3:4]+isq_first_id;
                   
                   if( ctl_ioq_ioaddress[2] )
                     begin
                        isq_cfg_wren    = 3'b110;
                        isq_cfg_wrdata  = {ctl_ioq_iowrite_data[31:0],16'h0};
                     end
                   else
                     begin
                        isq_cfg_wren   = 3'b001;
                        isq_cfg_wrdata  = {32'h0,ctl_ioq_iowrite_data[15:0]};
                        isq_upd_valid  = ~ctl_ioq_ioaddress[3];  // update enabled flag and copy of # of entries in the queue
                     end
                   ioq_ctl_ioack   = 1'b1;
                end
              else if( ioread_strobe_q )
                begin
                   isq_cfg_addr     = ctl_ioq_ioaddress[3];
                   isq_cfg_sqid     = ctl_ioq_ioaddress[isq_idwidth+3:4]+isq_first_id;                   
                   isq_cfg_rd       = 1'b1;
                   ioq_ctl_ioack    = 1'b1;
                end
           end

        // debug read
        if( isq_cfg_wren==3'b000 && isq_cfg_rd==1'b0 )
          begin
             isq_cfg_rddbg_d = 1'b1;
             isq_cfg_addr = regs_ioq_dbg_addr[0];
             isq_cfg_sqid = regs_ioq_dbg_addr[isq_cfg_awidth:1]+isq_first_id;             
          end
        else
          begin
             isq_cfg_rddbg_d = 1'b0;
          end
           
     end

   //-------------------------------------------------------
   // pick ISQ with fewest used entries
   //-------------------------------------------------------

   wire [num_isq*(isq_ptr_width+2)-1:0] isq_cmp_used;
   wire     [num_isq*(isq_idwidth)-1:0] isq_cmp_id;
   wire               [isq_ptr_width:0] isq_cmp_winner;
   wire               [isq_idwidth-1:0] isq_cmp_winner_id;
   wire                                 isq_cmp_winner_invalid;

   genvar                               isq2;
   generate
      for( isq2=0; isq2<num_isq; isq2=isq2+1)
        begin : isq_cmp
           assign isq_cmp_used[(isq2+1)*(isq_ptr_width+2)-1:isq2*(isq_ptr_width+2)] = 
            {(~isq_regs[isq2+isq_first_id].enable_q|isq_regs[isq2+isq_first_id].full_q), isq_regs[isq2+isq_first_id].used_q};
           assign isq_cmp_id[(isq2+1)*(isq_idwidth)-1:isq2*isq_idwidth] = isq2+isq_first_id;
        end
   endgenerate
   nvme_cmp #(.count(num_isq),.width(isq_ptr_width+2),.id_width(isq_idwidth)) cmp0 (.data(isq_cmp_used),.id(isq_cmp_id),.dout({isq_cmp_winner_invalid, isq_cmp_winner}),.dout_id(isq_cmp_winner_id));

   reg isq_cmp_winner_valid_q;
   reg [isq_idwidth-1:0] isq_cmp_winner_id_q;
   always @(posedge clk)
     begin
        isq_cmp_winner_valid_q <= ~isq_cmp_winner_invalid;
        isq_cmp_winner_id_q <= isq_cmp_winner_id;
     end	
   
   assign ioq_sntl_sqid_valid = isq_cmp_winner_valid_q;
   assign ioq_sntl_sqid = isq_cmp_winner_id_q;
   
   //-------------------------------------------------------
   // insert ISQ entry
   //-------------------------------------------------------

   reg             [3:0] isq_state_q, isq_state_d;
   reg            [31:0] isq_doorbell_q, isq_doorbell_d;
   reg [isq_ptr_width:0] isq_base_q, isq_base_d;
   reg [isq_ptr_width:0] isq_head_q, isq_head_d;
   reg [isq_ptr_width:0] isq_tail_q, isq_tail_d;
   reg [isq_ptr_width:0] isq_size_q, isq_size_d;
   
   localparam ISQ_IDLE = 4'h1;
   localparam ISQ_CFG1 = 4'h2;
   localparam ISQ_CFG2 = 4'h3;
   localparam ISQ_INS0 = 4'h4;
   localparam ISQ_INS1 = 4'h5;
   localparam ISQ_INS2 = 4'h6;
   localparam ISQ_INS3 = 4'h7;
   localparam ISQ_DOORBELL = 4'h8;

   wire      icq_init_done;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             isq_state_q <= ISQ_IDLE;
          end
        else
          begin
             isq_state_q <= isq_state_d;
          end
     end

   always @(posedge clk)
     begin
        isq_doorbell_q <= isq_doorbell_d;
        isq_base_q     <= isq_base_d;
        isq_head_q     <= isq_head_d;
        isq_tail_q     <= isq_tail_d;
        isq_size_q     <= isq_size_d; 
     end
   

   // build submission queue entry for I/O commands
   // supported opcodes:
   //  Read  = 0x02
   //  Write = 0x01
   //  Flush = 0x00
   //  Dataset Management = 0x09
   // DW0 = { command identifier[15:0], SGL, rsvd[4:0], fuse[1:0], opcode[7:0] }
   // DW1 = { namespace id }
   // DW2 = reserved
   // DW3 = reserved
   // DW5,4 = metadata pointer
   // DW7,6 = PRP Entry 1
   // DW9,8 = PRP Entry 2
   // DW10,11 = starting lba
   // DW12 = { Limited Retry, Force Unit Access, PrInfo[3:0], rsvd[9:0], number of blocks[15:0] }
   // DW13 = { rsvd[31:8], Data Set Management[7:0] }
   // DW14 = Protection Info
   // DW15 = Protection Info

   reg                [63:0] prp1;
   reg                [63:0] prp2;
   reg                       fua;
   reg                       lr;
   reg                 [3:0] prinfo;
   reg                 [7:0] dsm;

  
   reg                       isq_pcie_wrvalid;
   reg                [31:0] isq_pcie_wraddr;
   reg                [15:0] isq_pcie_wrdata;
   reg                       pcie_isq_wrack;


   always @*
     begin
        isq_state_d        = isq_state_q;
        isq_doorbell_d     = isq_doorbell_q;
        isq_base_d         = isq_base_q;
        isq_head_d         = isq_head_q;
        isq_tail_d         = isq_tail_q;
        isq_size_d         = isq_size_q; 

        isq_wrdata         = 128'h0;
        isq_wraddr         = {isq_base_q,2'b00};
        isq_wren           = 1'b0;      
              
        ioq_sntl_req_ack   = 1'b0;

        isqsm_cfg_sqid     = sntl_ioq_req_sqid;
        isqsm_cfg_addr     = 1'b0;
        isqsm_cfg_wrdata   = 48'h0;
        isqsm_cfg_wrdata[31:16] = isq_tail_q;
        isqsm_cfg_wren     = 3'b000;
        
        isqsm_cfg_rdvalid  = 1'b0;        

        isq_pcie_wrvalid = 1'b0;
        isq_pcie_wraddr  = isq_doorbell_q;
        isq_pcie_wrdata  = isq_tail_q;   

        // PRP list entries
        //   address = 4b region, 16b command id, 4b reserved, 28b offset
        // 28b offset covers the 128MB max page size allowed by NVMe spec
        // sislite max is 16MB       
        if( sntl_ioq_req_opcode==NVME_IO_READ )
          begin             
             prp1 = { zero[63:52], ENUM_ADDR_SISL, sntl_ioq_req_cmdid[cid_width-1:0], zero[31:datalen_width], sntl_ioq_req_reloff[datalen_width-1:0]};          
          end
        else
          begin
             // max transfer for a write is 1 write buffer (wbuf_size=4KB)
             // include write buffer id in offset part of address
             prp1 = { zero[63:52], ENUM_ADDR_WBUF,               zero[cid_width-1:0], zero[3:0], zero[27:wbufid_width+$clog2(wbuf_size)], sntl_ioq_req_wbufid[wbufid_width-1:0], zero[$clog2(wbuf_size)-1:0] };            
          end
        prp2 = zero[63:0];
        
        fua               = sntl_ioq_req_fua;            // force unit access - 1=force read from NVM (instead of cache?)
        lr                = 1'b0;                        // limited retry
        prinfo            = 4'h0;                        // protection info - PRACT=0 (pass through), PRCHK=3'b000 (no end-to-end checking enabled) 
        dsm               = { 1'b0, 1'b0, 2'b00, 4'h0 }; // incompressable=0, sequential access=0, access latency=0, access frequency=0 -> no information provided                      

      
        case( isq_state_q )
          ISQ_IDLE:
            begin            
               if( sntl_ioq_req_valid & ctl_xx_ioq_enable & icq_init_done )
                 begin                   
                    isq_state_d = ISQ_CFG1;
                 end
            end
          ISQ_CFG1:
            begin
               // read doorbell & base address of the selected isq
               isqsm_cfg_sqid     = sntl_ioq_req_sqid;
               isqsm_cfg_addr     = 1'b1;
               isq_doorbell_d     = isq_cfg_rddata[47:16];
               isq_base_d         = isq_cfg_rddata[15:0];               
               isqsm_cfg_rdvalid  = 1'b1;
               isq_state_d = ISQ_CFG2;
            end
          
          ISQ_CFG2:
            begin
               // read current head/tail/size for the selected isq
               isqsm_cfg_sqid     = sntl_ioq_req_sqid;
               isqsm_cfg_addr     = 1'b0;
               isq_head_d = isq_cfg_rddata[47:32];
               isq_tail_d = isq_cfg_rddata[31:16];
               isq_size_d = isq_cfg_rddata[15:0];
               isq_base_d = isq_base_q + isq_tail_d;  // make base_q point to start of current entry
               isqsm_cfg_rdvalid  = 1'b1;
               isq_state_d = ISQ_INS0;
            end
          
          ISQ_INS0:
            begin
               isq_state_d  = ISQ_INS1;                             
               isq_wren     = 1'b1;         
               isq_wraddr   = {isq_base_q,2'b00};
               //                    DW3, DW2, DW1, DW0
               isq_wrdata   = { zero[31:0], zero[31:0], sntl_ioq_req_nsid, sntl_ioq_req_cmdid, 1'b0, zero[4:0], zero[1:0], sntl_ioq_req_opcode };
`ifdef SIM
               // sim model doesn't support dataset management command
               // change opcode to a write and manually check the rest of the command function
                if(  sntl_ioq_req_opcode == NVME_IO_DATASET )
                  begin
                     isq_wrdata = { zero[31:0], zero[31:0], sntl_ioq_req_nsid, sntl_ioq_req_cmdid, 1'b0, zero[4:0], zero[1:0], NVME_IO_WRITE };
                  end
`endif
                                             
            end
          
          ISQ_INS1:
            begin
               isq_state_d            = ISQ_INS2;
               isq_wren               = 1'b1;         
               isq_wraddr             = {isq_base_q,2'b01};
              
               //                    DW7, DW6, DW5, DW4
               isq_wrdata             = { prp1, zero[63:0]};
              
            end
          ISQ_INS2:
            begin
               isq_state_d  = ISQ_INS3;
               isq_wren     = 1'b1;         
               isq_wraddr   = {isq_base_q,2'b10};
              
               if(  sntl_ioq_req_opcode == NVME_IO_DATASET )
                 begin
                    //                    DW11, DW10, DW9, DW8
                    // DW10 7:0 = number of ranges.  0 means 1 range
                    // DW11 bit 2 = deallocate                    
                    isq_wrdata           = { 32'h4,{24'h0,sntl_ioq_req_numblks[7:0]}, prp2 };
                 end
               else
                 begin
                    //                    DW11, DW10, DW9, DW8
                    isq_wrdata           = { sntl_ioq_req_lba , prp2 };
                  end  

               // increment tail register.  wrap to zero in next cycle if needed
               isq_tail_d = isq_tail_q + 1;          
            end
          ISQ_INS3:
            begin
               isq_state_d  = ISQ_DOORBELL;
               isq_wren     = 1'b1;         
               isq_wraddr   = {isq_base_q,2'b11};

               if(  sntl_ioq_req_opcode == NVME_IO_DATASET )
                 begin
                    isq_wrdata           = zero[127:0];
                 end
               else
                 begin
                    //                    DW15, DW14, DW13, DW12
                    isq_wrdata           = { zero[63:0], zero[31:8], dsm, lr, fua, prinfo, zero[25:16], sntl_ioq_req_numblks };
                 end

               // wrap tail register back to zero if needed
               if( isq_tail_q == isq_size_q )
                 isq_tail_d = zero[isq_ptr_width-1:0];               
            end

          ISQ_DOORBELL:
            begin
               isq_pcie_wrvalid = 1'b1;
               // write new tail register to doorbell
               if( pcie_isq_wrack )
                 begin
                    ioq_sntl_req_ack = 1'b1;
                    isqsm_cfg_wren = 3'b010;  // save tail register
                    isq_state_d = ISQ_IDLE;
                 end                   
            end
          default:
            begin
               isq_state_d = ISQ_IDLE;
            end
        endcase // case ( isq_state_q )

     end
   

   //-------------------------------------------------------
   // I/O Completion Queue (ICQ)
   //-------------------------------------------------------


   // 16B per queue entry
   // 
   // read interface width:   4B - 4x4B per entry
   // write interface width: 16B - 16x1 per entry

   localparam icq_rdwidth = 32;
   localparam icq_wrwidth = 128;
   localparam icq_num_words = icq_num_entries * (16/(icq_wrwidth/8));
   localparam icq_num_wren = 1;
   localparam icq_addr_width = clogb2(icq_num_words);
   localparam icq_last_entry = icq_num_entries-1;

   reg [ icq_wrwidth+16-1:0] icq_mem[icq_num_words-1:0]; 
   
   wire [icq_wrwidth+16-1:0] icq_wrdata;  
   wire                      icq_wren;
   wire [icq_addr_width-1:0] icq_wraddr;
   reg  [icq_wrwidth+16-1:0] icq_rddata;  
   reg  [icq_addr_width-1:0] icq_rdaddr;

   always @(posedge clk)   
      icq_rddata <= icq_mem[icq_rdaddr];
  
   always @(posedge clk)
     if (icq_wren)
       icq_mem[icq_wraddr] <= icq_wrdata;      



   reg   [icq_ptr_width-1:0] icq_head_q; // read pointer
   reg   [icq_ptr_width-1:0] icq_tail_q; // write pointer
   reg                       icq_phase_q;
   reg                       icq_full;   // NVMe spec says full when head=tail+1
   reg                       icq_empty_q;  // head=tail
   reg   [icq_ptr_width-1:0] icq_head_d; // read pointer
   reg   [icq_ptr_width-1:0] icq_tail_d; // write pointer
   reg                       icq_phase_d;
   reg                       icq_empty_d;  // head=tail
   
   reg                       icq_head_inc;  // incremented when completion info has been sent to sntl
   reg                       icq_rddbg_q, icq_rddbg_d;

   reg                 [3:0] cpl_state_q;
   reg                 [3:0] cpl_state_d;
   reg                [14:0] cpl_status_q, cpl_status_d;
   reg                [15:0] cpl_cmdid_q, cpl_cmdid_d; 
   reg                 [1:0] cpl_cmdid_par_q, cpl_cmdid_par_d; 


   localparam CPL_IDLE = 4'h1;
   localparam CPL_BUSY = 4'h2;
   localparam CPL_UPD  = 4'h3;
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             icq_head_q      <= zero[icq_ptr_width-1:0];
             icq_tail_q      <= zero[icq_ptr_width-1:0];
             icq_phase_q     <= 1'b1;
             icq_empty_q     <= 1'b1;
             icq_rddbg_q     <= 1'b0;
             cpl_status_q    <= zero[14:0];
             cpl_cmdid_q     <= zero[15:0];
             cpl_cmdid_par_q <= ~zero[1:0];
             cpl_state_q     <= CPL_IDLE;             
          end
        else
          begin
             icq_head_q      <= icq_head_d;
             icq_tail_q      <= icq_tail_d;
             icq_phase_q     <= icq_phase_d;
             icq_empty_q     <= icq_empty_d;
             icq_rddbg_q     <= icq_rddbg_d;
             cpl_status_q    <= cpl_status_d;
             cpl_cmdid_q     <= cpl_cmdid_d;
             cpl_cmdid_par_q <= cpl_cmdid_par_d;
             cpl_state_q     <= cpl_state_d;
          end
     end

   // manage head & tail pointers
   always @*
     begin
        icq_head_d  = icq_head_q + (icq_head_inc ? one[icq_ptr_width-1:0] : zero[icq_ptr_width-1:0]);
        icq_tail_d  = icq_tail_q + (icq_wren ? one[icq_ptr_width-1:0] : zero[icq_ptr_width-1:0]);
        icq_full    = icq_head_q==(icq_tail_q+one[icq_ptr_width-1:0]);
        icq_empty_d = icq_head_q==icq_tail_q;        

        // flip the expected phase bit on rollover
        if( icq_head_inc &&           
            icq_head_q == icq_last_entry[icq_ptr_width-1:0] )
          begin
             icq_phase_d = ~icq_phase_q;
          end
        else
          begin
             icq_phase_d = icq_phase_q;
          end

        if( ctl_xx_ioq_enable == 1'b0 )
          begin
             // force queue pointers to zero if I/O Queue is disabled
             // then can happen after a NVMe controller reset
             icq_head_d    = zero[icq_ptr_width-1:0];
             icq_tail_d    = zero[icq_ptr_width-1:0];
             icq_phase_d   = 1'b1;
          end

        ioq_xx_icq_empty = icq_empty_q;
     end

   //-------------------------------------------------------
   // pop CQ entries and send to SNTL
   //-------------------------------------------------------

   reg icq_timer_enable_q, icq_timer_enable_d;
   reg [2:0] ioq_pe_inj_d,ioq_pe_inj_q;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             icq_timer_enable_q <= 1'b0;
             ioq_pe_inj_q       <= 3'b0;
          end
        else
          begin
             icq_timer_enable_q <= icq_timer_enable_d;
             ioq_pe_inj_q       <= ioq_pe_inj_d;
          end
     end

   // DW0 - command specific
   // DW1 - reserved
   // DW2 - SQ Id, SQ head pointer
   // DW3 - status[14:0], phase, command id

   reg               icq_rd_phase;
   reg        [31:0] icq_rd_dw0;
   reg        [31:0] icq_rd_dw1;
   reg        [15:0] icq_rd_sqid;
   reg        [15:0] icq_rd_sqhead;
   reg        [14:0] icq_rd_status;
   reg        [15:0] icq_rd_cid;
   reg        [15:0] icq_rddata_par;

   //  check icq_rddata 
   wire        [1:0] xxq_perror_ack;
   always @*
     begin
        ioq_pe_inj_d = ioq_pe_inj_q;       
        if (regs_wdata_pe_errinj_1cycle_valid & regs_ioq_pe_errinj_valid & regs_xxx_pe_errinj_decode[11:8] == 4'hB)
          begin
             ioq_pe_inj_d[0]  = (regs_xxx_pe_errinj_decode[3:0]==4'h0);
             ioq_pe_inj_d[1]  = (regs_xxx_pe_errinj_decode[3:0]==4'h1);
             ioq_pe_inj_d[2]  = (regs_xxx_pe_errinj_decode[3:0]==4'h2);
          end 
        if (ioq_pe_inj_q [0] )
          ioq_pe_inj_d[0] = 1'b0;         
        if (ioq_pe_inj_q [1] & xxq_perror_ack[0])
          ioq_pe_inj_d[1] = 1'b0;         
        if (ioq_pe_inj_q [2] & xxq_perror_ack[1])
          ioq_pe_inj_d[2] = 1'b0;         
     end  

   wire      [1:0] xxq_perror_inj = ioq_pe_inj_q[2:1];

   nvme_pcheck#
     (
      .bits_per_parity_bit(8),
      .width(128)
      ) ipcheck_icq_rddata
       (.oddpar(1'b1),.data({icq_rddata[127:1],(icq_rddata[0]^ioq_pe_inj_q[0])}),.datap(icq_rddata[143:128]),.check(icq_init_done),.parerr(s1_perror)); 


   wire      [1:0] icq_rd_cid_par;

   nvme_pgen#
     (
      .bits_per_parity_bit(8),
      .width(16)
      ) ipgen_icq_rd_cid 
       (.oddpar(1'b1),.data(icq_rd_cid),.datap(icq_rd_cid_par)); 
   

   
   reg                          dbg_rd_icq;
   reg     [icq_addr_width-1:0] dbg_rd_icq_addr;
   reg                          cpl_state_fatal;

   reg                          icq_pcie_wrvalid;
   reg                   [31:0] icq_pcie_wraddr;
   reg                   [15:0] icq_pcie_wrdata;
   reg                          pcie_icq_wrack;

   
   reg                      icq_isq_head_valid_q, icq_isq_head_valid_d;
   reg    [isq_idwidth-1:0] icq_isq_head_sqid_q, icq_isq_head_sqid_d;
   reg  [isq_ptr_width-1:0] icq_isq_head_q, icq_isq_head_d;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             icq_isq_head_valid_q <= 1'b0;
             icq_isq_head_sqid_q <= '0;
             icq_isq_head_q <= '0;
          end
        else
          begin
             icq_isq_head_valid_q <= icq_isq_head_valid_d;
             icq_isq_head_sqid_q <= icq_isq_head_sqid_d;
             icq_isq_head_q <= icq_isq_head_d;
          end
     end

   
   always @*
     begin
        icq_rdaddr          = icq_head_q;
        icq_rddbg_d         = 1'b0;
        ioq_sntl_cpl_valid  = 1'b0;
        icq_head_inc        = 1'b0;
        
        cpl_status_d        = cpl_status_q;
        cpl_cmdid_d         = cpl_cmdid_q;
        cpl_cmdid_par_d     = cpl_cmdid_par_q;
        cpl_state_d         = cpl_state_q;
        cpl_state_fatal     = 1'b0;

        icq_pcie_wrvalid = 1'b0;
        icq_pcie_wraddr = NVME_REG_CQ2HDBL;  // shouldn't hardcode but use doorbell stride instead
        icq_pcie_wrdata = icq_head_q;

        icq_timer_enable_d = ctl_xx_ioq_enable && icq_init_done && (icq_rd_phase == icq_phase_q) && (&isq_empty)==1'b0;     
        
        { icq_rddata_par, icq_rd_status, icq_rd_phase, icq_rd_cid, icq_rd_sqid, icq_rd_sqhead, icq_rd_dw1, icq_rd_dw0 } = icq_rddata;
        

        icq_isq_head_valid_d   = 1'b0;
        icq_isq_head_sqid_d    = icq_rd_sqid;
        icq_isq_head_d         = icq_rd_sqhead;
        icq_isq_head_valid = icq_isq_head_valid_q;
        icq_isq_head_sqid  = icq_isq_head_sqid_q;
        icq_isq_head       = icq_isq_head_q;

        
        case(cpl_state_q)
          CPL_IDLE:
            begin
               cpl_status_d        = icq_rd_status;
               cpl_cmdid_d         = icq_rd_cid;
               cpl_cmdid_par_d     = icq_rd_cid_par;

               if( dbg_rd_icq && icq_rddbg_q==1'b0 )
                 begin
                    // debug read of completion queue
                    icq_rdaddr  = dbg_rd_icq_addr;
                    icq_rddbg_d = 1'b1;
                 end
               else if( ctl_xx_ioq_enable && icq_init_done && (icq_rd_phase == icq_phase_q) && (icq_rddbg_q==1'b0) )
                 begin
                    // phase matches, therefore this completion entry is valid
                    icq_isq_head_valid_d = 1'b1;
                    if( isq_icq_head_ack )
                      begin
                         icq_isq_head_valid_d = 1'b0;
                         cpl_state_d   = CPL_BUSY;
                      end
                 end             
            end

          CPL_BUSY:
            begin
               ioq_sntl_cpl_valid  = 1'b1;               
               icq_timer_enable_d  = 1'b0;
               if( sntl_ioq_cpl_ack )
                 begin                    
                    icq_head_inc      = 1'b1;
                    cpl_state_d       = CPL_UPD;
                 end              
            end      

          CPL_UPD:
            begin
               // wait for icq_rddata to be valid
               // write new icq_head doorbell value
               icq_pcie_wrvalid = 1'b1;
               if( pcie_icq_wrack )
                 begin
                    cpl_state_d = CPL_IDLE;
                 end
            end          
          
          default:
            begin
               cpl_state_fatal = 1'b1;
               cpl_state_d     = CPL_IDLE;
            end
        endcase
                    
        ioq_sntl_cpl_status    = cpl_status_q;
        ioq_sntl_cpl_cmdid     = cpl_cmdid_q;        
        ioq_sntl_cpl_cmdid_par = cpl_cmdid_par_q;        
                             
     end // always @ *

   // doorbell writes - select isq or icq
   always @*
     begin
        ioq_pcie_wrvalid = isq_pcie_wrvalid | icq_pcie_wrvalid;
        ioq_pcie_wraddr = isq_pcie_wraddr;
        ioq_pcie_wrdata = isq_pcie_wrdata;
        pcie_isq_wrack  = isq_pcie_wrvalid & pcie_ioq_wrack;

        if( ~isq_pcie_wrvalid )
          begin
             ioq_pcie_wraddr = icq_pcie_wraddr;
             ioq_pcie_wrdata = icq_pcie_wrdata;
          end
        pcie_icq_wrack  = ~isq_pcie_wrvalid & pcie_ioq_wrack;
     end
   

   //-------------------------------------------------------
   // timeout detection
   //-------------------------------------------------------

   // if ISQ is not empty, detect when we're waiting for a completion a long time
   // timeout is disabled if timeout value is zero
   
   reg [15:0] icq_timer_q, icq_timer_d;
   reg        icq_timeout_q, icq_timeout_d;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             icq_timer_q   <= zero[15:0];
             icq_timeout_q <= 1'b0;
          end
        else
          begin
             icq_timer_q   <= icq_timer_d;
             icq_timeout_q <= icq_timeout_d;
          end
     end   

   always @*
     begin
        icq_timeout_d = icq_timer_enable_q &&
                        icq_timer_q==zero[15:0] &&
                        regs_ioq_icqto!=zero[15:0];
        
        if( regs_xx_tick2 &&
            icq_timer_enable_q &&
            icq_timer_q != zero[15:0] )
          begin
             icq_timer_d   = icq_timer_q - 1;
          end
        else if( !icq_timer_enable_q )
          begin
             icq_timer_d = regs_ioq_icqto;
          end
        else
          begin             
             icq_timer_d  = icq_timer_q;
          end
     end
        
   
   //-------------------------------------------------------
   // DMA access to ISQ/ICQ from NVMe controller
   //-------------------------------------------------------

   (* mark_debug = "false" *)
   wire [7:0] req_dbg_event;

   nvme_xxq_dma#
     (
      .addr_width(addr_width),

      .sq_num_queues(num_isq),
      .sq_first_id(isq_first_id),
      .sq_ptr_width(isq_ptr_width),
      .sq_addr_width(isq_addr_width),
      .sq_rdwidth(isq_rdwidth),
       
      .cq_num_queues(num_icq),      
      .cq_ptr_width(icq_ptr_width),
      .cq_addr_width(icq_addr_width),
      .cq_wrwidth(icq_wrwidth)

      ) dma
       (  
          .reset                         (reset),
          .clk                           (clk),
                
          .q_reset                       (~ctl_xx_ioq_enable),
          .q_init_done                   (icq_init_done),
                    
          .sq_rdaddr                     (isq_rdoffset),
          .sq_rdval                      (isq_rdval),
          .sq_id                         (),
          .sq_rddata                     (isq_rddata),
         
          .cq_wren                       (icq_wren),
          .cq_id                         (),
          .cq_wraddr                     (icq_wraddr),
          .cq_wrdata                     (icq_wrdata),  
         
          .pcie_xxq_valid                (pcie_ioq_valid),
          .pcie_xxq_data                 (pcie_ioq_data),
          .pcie_xxq_first                (pcie_ioq_first),
          .pcie_xxq_last                 (pcie_ioq_last),
          .pcie_xxq_discard              (pcie_ioq_discard),        
          .xxq_pcie_pause                (ioq_pcie_pause),
          
          .xxq_pcie_cc_data              (ioq_pcie_cc_data),
          .xxq_pcie_cc_first             (ioq_pcie_cc_first),
          .xxq_pcie_cc_last              (ioq_pcie_cc_last),
          .xxq_pcie_cc_discard           (ioq_pcie_cc_discard),
          .xxq_pcie_cc_valid             (ioq_pcie_cc_valid),   
          .pcie_xxq_cc_ready             (pcie_ioq_cc_ready),
          
          .req_dbg_event                (req_dbg_event),
          .xxq_dma_perror               (ioq_perror_int[0]),
          .xxq_perror_inj               (xxq_perror_inj),
          .xxq_perror_ack               (xxq_perror_ack)
          );


   //-------------------------------------------------------
   // errors
   //-------------------------------------------------------

   always @*
     begin
        ioq_regs_recerr[0] = req_dbg_event[0] | req_dbg_event[3];  // read req without last or unexpected request type
        ioq_regs_recerr[1] = req_dbg_event[4];                     // write to unexpected address
        ioq_regs_recerr[2] = 1'b0; 
        ioq_regs_recerr[3] = 1'b0;
        ioq_regs_faterr[0] = 1'b0;                    
        ioq_regs_faterr[1] = cpl_state_fatal;
        ioq_regs_faterr[2] = req_dbg_event[1] | req_dbg_event[2];  // unaligned address 
        ioq_regs_faterr[3] = icq_timeout_q;
     end
   
   //-------------------------------------------------------
   // debug/performance counters
   //-------------------------------------------------------

   reg [31:0] cnt_icq_dmawr_q, cnt_icq_dmawr_d;
   
   reg [31:0] cnt_isq0_cmdwr_q, cnt_isq0_cmdwr_d;
   reg [31:0] cnt_isq1_cmdwr_q, cnt_isq1_cmdwr_d;
   reg [31:0] cnt_isq2_cmdwr_q, cnt_isq2_cmdwr_d;
   reg [31:0] cnt_isq3_cmdwr_q, cnt_isq3_cmdwr_d;
   
   reg [31:0] cnt_isq0_cmdrd_q, cnt_isq0_cmdrd_d;
   reg [31:0] cnt_isq1_cmdrd_q, cnt_isq1_cmdrd_d;
   reg [31:0] cnt_isq2_cmdrd_q, cnt_isq2_cmdrd_d;
   reg [31:0] cnt_isq3_cmdrd_q, cnt_isq3_cmdrd_d;
   
   reg [31:0] cnt_isq0_cpl_q, cnt_isq0_cpl_d;
   reg [31:0] cnt_isq1_cpl_q, cnt_isq1_cpl_d;
   reg [31:0] cnt_isq2_cpl_q, cnt_isq2_cpl_d;
   reg [31:0] cnt_isq3_cpl_q, cnt_isq3_cpl_d;
   
   reg [31:0] cnt_isq0_dmard_q, cnt_isq0_dmard_d;
   reg [31:0] cnt_isq1_dmard_q, cnt_isq1_dmard_d;
   reg [31:0] cnt_isq2_dmard_q, cnt_isq2_dmard_d;
   reg [31:0] cnt_isq3_dmard_q, cnt_isq3_dmard_d;

   reg [19:0] cnt_dbg0_q, cnt_dbg0_d;
   reg [19:0] cnt_dbg1_q, cnt_dbg1_d;
   reg [19:0] cnt_dbg2_q, cnt_dbg2_d;
   reg [19:0] cnt_dbg3_q, cnt_dbg3_d;
   reg [19:0] cnt_dbg4_q, cnt_dbg4_d;
   reg [19:0] cnt_dbg5_q, cnt_dbg5_d;
   reg [19:0] cnt_dbg6_q, cnt_dbg6_d;
   reg [19:0] cnt_dbg7_q, cnt_dbg7_d;
   
   
   reg [63:0] dbg_data_q, dbg_data_d;
   always @(posedge clk)
     begin
        dbg_data_q <= dbg_data_d;
     end

   reg dbg_rdack_q, dbg_rdack_d;
   reg [16:0] cnt_incr_q, cnt_incr_d;
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             dbg_rdack_q      <= 1'b0;
             cnt_icq_dmawr_q  <= 32'h0;
             cnt_isq0_cmdwr_q <= 32'h0;
             cnt_isq1_cmdwr_q <= 32'h0;
             cnt_isq2_cmdwr_q <= 32'h0;
             cnt_isq3_cmdwr_q <= 32'h0;
             cnt_isq0_cmdrd_q <= 32'h0;
             cnt_isq1_cmdrd_q <= 32'h0;
             cnt_isq2_cmdrd_q <= 32'h0;
             cnt_isq3_cmdrd_q <= 32'h0;
             cnt_isq0_cpl_q   <= 32'h0;
             cnt_isq1_cpl_q   <= 32'h0;
             cnt_isq2_cpl_q   <= 32'h0;
             cnt_isq3_cpl_q   <= 32'h0;
             cnt_isq0_dmard_q <= 32'h0;
             cnt_isq1_dmard_q <= 32'h0;
             cnt_isq2_dmard_q <= 32'h0;
             cnt_isq3_dmard_q <= 32'h0;
             cnt_incr_q       <= 17'h0;
             cnt_dbg0_q       <= 20'h0;
             cnt_dbg1_q       <= 20'h0;
             cnt_dbg2_q       <= 20'h0;
             cnt_dbg3_q       <= 20'h0;
             cnt_dbg4_q       <= 20'h0;
             cnt_dbg5_q       <= 20'h0;
             cnt_dbg6_q       <= 20'h0;
             cnt_dbg7_q       <= 20'h0;
          end
        else
          begin
             dbg_rdack_q      <= dbg_rdack_d;
             cnt_icq_dmawr_q  <= cnt_icq_dmawr_d;
             cnt_isq0_cmdwr_q <= cnt_isq0_cmdwr_d;
             cnt_isq1_cmdwr_q <= cnt_isq1_cmdwr_d;
             cnt_isq2_cmdwr_q <= cnt_isq2_cmdwr_d;
             cnt_isq3_cmdwr_q <= cnt_isq3_cmdwr_d;
             cnt_isq0_cmdrd_q <= cnt_isq0_cmdrd_d;
             cnt_isq1_cmdrd_q <= cnt_isq1_cmdrd_d;
             cnt_isq2_cmdrd_q <= cnt_isq2_cmdrd_d;
             cnt_isq3_cmdrd_q <= cnt_isq3_cmdrd_d;
             cnt_isq0_cpl_q   <= cnt_isq0_cpl_d;
             cnt_isq1_cpl_q   <= cnt_isq1_cpl_d;
             cnt_isq2_cpl_q   <= cnt_isq2_cpl_d;
             cnt_isq3_cpl_q   <= cnt_isq3_cpl_d;
             cnt_isq0_dmard_q <= cnt_isq0_dmard_d;
             cnt_isq1_dmard_q <= cnt_isq1_dmard_d;
             cnt_isq2_dmard_q <= cnt_isq2_dmard_d;
             cnt_isq3_dmard_q <= cnt_isq3_dmard_d;
             cnt_incr_q       <= cnt_incr_d;
             cnt_dbg0_q       <= cnt_dbg0_d;
             cnt_dbg1_q       <= cnt_dbg1_d;
             cnt_dbg2_q       <= cnt_dbg2_d;
             cnt_dbg3_q       <= cnt_dbg3_d;
             cnt_dbg4_q       <= cnt_dbg4_d;
             cnt_dbg5_q       <= cnt_dbg5_d;
             cnt_dbg6_q       <= cnt_dbg6_d;
             cnt_dbg7_q       <= cnt_dbg7_d;
          end
     end

   always @*
     begin
        cnt_incr_d[0]     = icq_wren & icq_init_done;
        cnt_incr_d[15:1]  = 15'd0; 
                
        cnt_icq_dmawr_d   = cnt_icq_dmawr_q  + ((cnt_incr_q[0]) ? 1: 0);
        cnt_isq0_cmdwr_d  = cnt_isq0_cmdwr_q + ((cnt_incr_q[1]) ? 1: 0);
        cnt_isq1_cmdwr_d  = cnt_isq1_cmdwr_q + ((cnt_incr_q[2]) ? 1: 0);
        cnt_isq2_cmdwr_d  = cnt_isq2_cmdwr_q + ((cnt_incr_q[3]) ? 1: 0);
        cnt_isq3_cmdwr_d  = cnt_isq3_cmdwr_q + ((cnt_incr_q[4]) ? 1: 0);
        cnt_isq0_cmdrd_d  = cnt_isq0_cmdrd_q + ((cnt_incr_q[5]) ? 1: 0);
        cnt_isq1_cmdrd_d  = cnt_isq1_cmdrd_q + ((cnt_incr_q[6]) ? 1: 0);
        cnt_isq2_cmdrd_d  = cnt_isq2_cmdrd_q + ((cnt_incr_q[7]) ? 1: 0);
        cnt_isq3_cmdrd_d  = cnt_isq3_cmdrd_q + ((cnt_incr_q[8]) ? 1: 0);
        cnt_isq0_cpl_d    = cnt_isq0_cpl_q   + ((cnt_incr_q[9]) ? 1: 0);
        cnt_isq1_cpl_d    = cnt_isq1_cpl_q   + ((cnt_incr_q[10]) ? 1: 0);
        cnt_isq2_cpl_d    = cnt_isq2_cpl_q   + ((cnt_incr_q[11]) ? 1: 0);
        cnt_isq3_cpl_d    = cnt_isq3_cpl_q   + ((cnt_incr_q[12]) ? 1: 0);
        cnt_isq0_dmard_d  = cnt_isq0_dmard_q + ((cnt_incr_q[13]) ? 1: 0);
        cnt_isq1_dmard_d  = cnt_isq1_dmard_q + ((cnt_incr_q[14]) ? 1: 0);
        cnt_isq2_dmard_d  = cnt_isq2_dmard_q + ((cnt_incr_q[15]) ? 1: 0);
        cnt_isq3_dmard_d  = cnt_isq3_dmard_q + ((cnt_incr_q[16]) ? 1: 0);
        
        cnt_dbg0_d        = cnt_dbg0_q + ((req_dbg_event[0]) ? 1: 0);
        cnt_dbg1_d        = cnt_dbg1_q + ((req_dbg_event[1]) ? 1: 0);
        cnt_dbg2_d        = cnt_dbg2_q + ((req_dbg_event[2]) ? 1: 0);
        cnt_dbg3_d        = cnt_dbg3_q + ((req_dbg_event[3]) ? 1: 0);
        cnt_dbg4_d        = cnt_dbg4_q + ((req_dbg_event[4]) ? 1: 0);
        cnt_dbg5_d        = cnt_dbg5_q + ((req_dbg_event[5]) ? 1: 0);
        cnt_dbg6_d        = cnt_dbg6_q + ((req_dbg_event[6]) ? 1: 0);
        cnt_dbg7_d        = cnt_dbg7_q + ((req_dbg_event[7]) ? 1: 0);
     end


   // performance counters
   // counts number of words written but not yet read to get a measure of the latency from insert to
   // when the nvme controller reads the command block
   wire [9:0] isq0_active, isq1_active, isq2_active, isq3_active;
   wire [63:0] isq0_complete, isq1_complete, isq2_complete, isq3_complete;
   wire [63:0] isq0_sum, isq1_sum, isq2_sum, isq3_sum;

   nvme_perf_count#(.sum_width(64),.active_width(10)) iperf_isq0 (.reset(reset),.clk(clk),
                                                                  .incr(isq_wren), .decr(isq_rdval), .clr(~ctl_xx_ioq_enable),
                                                                  .active_cnt(isq0_active), .complete_cnt(isq0_complete), .sum(isq0_sum), .clr_sum(1'b0));
  
   genvar dbg_idx;

   
   always @*
     begin
        dbg_rdack_d     = 1'b0;
        dbg_rd_isq      = 1'b0;
        dbg_rd_isq_addr = {regs_ioq_dbg_addr[isq_addr_width-1-2:0] - 128, 2'b00}; // isq starts at addr 128. only read 1st 16B out of 64B
        dbg_rd_icq      = 1'b0;
        dbg_rd_icq_addr = regs_ioq_dbg_addr[icq_addr_width-1:0] ^ 10'h200; // isq starts at addr 512
        
        if( regs_ioq_dbg_addr<64 )
          begin
             dbg_rdack_d = regs_ioq_dbg_rd & ~dbg_rdack_q;
             case(regs_ioq_dbg_addr)
               0: dbg_data_d = {icq_phase_q, zero[30:icq_ptr_width], icq_head_q, zero[31:icq_ptr_width],icq_tail_q};
               1: dbg_data_d = {zero[63:32], cnt_icq_dmawr_q};
               8: dbg_data_d = {zero[63:32] ,cnt_isq0_cmdrd_q};
               9: dbg_data_d = {zero[63:32] ,cnt_isq1_cmdrd_q};
               10: dbg_data_d = {zero[63:32] ,cnt_isq2_cmdrd_q};
               11: dbg_data_d = {zero[63:32] ,cnt_isq3_cmdrd_q};
               12: dbg_data_d = {zero[63:32] ,cnt_isq0_cmdwr_q};
               13: dbg_data_d = {zero[63:32] ,cnt_isq1_cmdwr_q};
               14: dbg_data_d = {zero[63:32] ,cnt_isq2_cmdwr_q};
               15: dbg_data_d = {zero[63:32] ,cnt_isq3_cmdwr_q};
               16: dbg_data_d = {zero[63:32] ,cnt_isq0_cpl_q};
               17: dbg_data_d = {zero[63:32] ,cnt_isq1_cpl_q};
               18: dbg_data_d = {zero[63:32] ,cnt_isq2_cpl_q};
               19: dbg_data_d = {zero[63:32] ,cnt_isq3_cpl_q};
               20: dbg_data_d = {zero[63:32] ,cnt_isq0_dmard_q};
               21: dbg_data_d = {zero[63:32] ,cnt_isq1_dmard_q};
               22: dbg_data_d = {zero[63:32] ,cnt_isq2_dmard_q};
               23: dbg_data_d = {zero[63:32] ,cnt_isq3_dmard_q};
               24: dbg_data_d = {zero[63:20] ,cnt_dbg0_q};
               25: dbg_data_d = {zero[63:20] ,cnt_dbg1_q};
               26: dbg_data_d = {zero[63:20] ,cnt_dbg2_q};
               27: dbg_data_d = {zero[63:20] ,cnt_dbg3_q};
               28: dbg_data_d = {zero[63:20] ,cnt_dbg4_q};
               29: dbg_data_d = {zero[63:20] ,cnt_dbg5_q};
               30: dbg_data_d = {zero[63:20] ,cnt_dbg6_q};
               31: dbg_data_d = {zero[63:20] ,cnt_dbg7_q};
               32: dbg_data_d = {zero[15:10],isq3_active,zero[15:10],isq2_active,zero[15:10],isq1_active,zero[15:10],isq0_active};
               36: dbg_data_d = isq0_complete;
               37: dbg_data_d = isq1_complete;
               38: dbg_data_d = isq2_complete;
               39: dbg_data_d = isq3_complete;
               40: dbg_data_d = isq0_sum;
               41: dbg_data_d = isq1_sum;
               42: dbg_data_d = isq2_sum;
               43: dbg_data_d = isq3_sum;               
               default: dbg_data_d = zero[63:0];
             endcase // case (regs_ioq_dbg_addr)
             
          end // if ( regs_ioq_dbg_addr<64 )
        else if( regs_ioq_dbg_addr>=64 &&
                 regs_ioq_dbg_addr<128 )
          begin
             // IOSQ configuration
             dbg_rdack_d = regs_ioq_dbg_rd & ~dbg_rdack_q & isq_cfg_rddbg_q;
             dbg_data_d = isq_cfg_rddata;                               
          end
        else if( regs_ioq_dbg_addr>=128 &&
                 regs_ioq_dbg_addr<512)
          begin
             dbg_rdack_d = regs_ioq_dbg_rd & ~dbg_rdack_q;
             case( regs_ioq_dbg_addr[3:0] )
               0: dbg_data_d = {isq_regs[2].empty_q, isq_regs[2].enable_q,zero[31:isq_ptr_width+1],isq_regs[2].used_q};
               1: dbg_data_d = {isq_regs[3].empty_q, isq_regs[3].enable_q,zero[31:isq_ptr_width+1],isq_regs[3].used_q};
               2: dbg_data_d = {isq_regs[4].empty_q, isq_regs[4].enable_q,zero[31:isq_ptr_width+1],isq_regs[4].used_q};
               3: dbg_data_d = {isq_regs[5].empty_q, isq_regs[5].enable_q,zero[31:isq_ptr_width+1],isq_regs[5].used_q};
               4: dbg_data_d = {isq_regs[6].empty_q, isq_regs[6].enable_q,zero[31:isq_ptr_width+1],isq_regs[6].used_q};
               5: dbg_data_d = {isq_regs[7].empty_q, isq_regs[7].enable_q,zero[31:isq_ptr_width+1],isq_regs[7].used_q};
               6: dbg_data_d = {isq_regs[8].empty_q, isq_regs[8].enable_q,zero[31:isq_ptr_width+1],isq_regs[8].used_q};
               7: dbg_data_d = {isq_regs[9].empty_q, isq_regs[9].enable_q,zero[31:isq_ptr_width+1],isq_regs[9].used_q};
               8: dbg_data_d = {isq_regs[10].empty_q, isq_regs[10].enable_q,zero[31:isq_ptr_width+1],isq_regs[10].used_q};
               9: dbg_data_d = {isq_regs[11].empty_q, isq_regs[11].enable_q,zero[31:isq_ptr_width+1],isq_regs[11].used_q};
               10: dbg_data_d = {isq_regs[12].empty_q, isq_regs[12].enable_q,zero[31:isq_ptr_width+1],isq_regs[12].used_q};
               11: dbg_data_d = {isq_regs[13].empty_q, isq_regs[13].enable_q,zero[31:isq_ptr_width+1],isq_regs[13].used_q};
               12: dbg_data_d = {isq_regs[14].empty_q, isq_regs[14].enable_q,zero[31:isq_ptr_width+1],isq_regs[14].used_q};
               13: dbg_data_d = {isq_regs[15].empty_q, isq_regs[15].enable_q,zero[31:isq_ptr_width+1],isq_regs[15].used_q};
               14: dbg_data_d = {isq_regs[16].empty_q, isq_regs[16].enable_q,zero[31:isq_ptr_width+1],isq_regs[16].used_q};
               15: dbg_data_d = {isq_regs[17].empty_q, isq_regs[17].enable_q,zero[31:isq_ptr_width+1],isq_regs[17].used_q};
               default:    dbg_data_d = 64'h0;
             endcase
          end        
        else if( regs_ioq_dbg_addr>=512 &&
                 regs_ioq_dbg_addr<(512+isq_num_entries*num_isq))
          begin
             dbg_rd_isq = regs_ioq_dbg_rd & ~dbg_rdack_q;
             dbg_data_d = {zero[31:0],isq_rddata[31:0]};  // DW0 of submission queue entry             
             dbg_rdack_d = isq_rddbg_q;
          end        
        else if( regs_ioq_dbg_addr>=1024 &&
                 regs_ioq_dbg_addr<(1024+icq_num_entries))
          begin
             dbg_rd_icq = regs_ioq_dbg_rd & ~dbg_rdack_q;
             dbg_data_d = icq_rddata[127:64];  // DW3&DW2 of completion entry
             dbg_rdack_d = icq_rddbg_q;
          end
        else
          begin
             dbg_data_d = zero[63:0];
             dbg_rdack_d = regs_ioq_dbg_rd & ~dbg_rdack_q;
          end                                     
         
        ioq_regs_dbg_ack  = dbg_rdack_q;
        ioq_regs_dbg_data = dbg_data_q;
     end // always @ *
 
   
endmodule


