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


module psl_hdk_vpd#
  (
   parameter NXTCAP = 8'h00,
   parameter CAPID = 8'h03
   )

   (
    input            clk,
    input            nperst,
    input            user_lnk_up,

    (* mark_debug = "true" *)
    input            vpd_adr_en,
    (* mark_debug = "true" *)
    input            vpd_dat_en,
    (* mark_debug = "true" *)
    input     [0:31] vpd_wrdata,
    
    (* mark_debug = "true" *)
    output    [0:31] vpd_adr,
    (* mark_debug = "true" *)
    output    [0:31] vpd_dat,
    
    (* mark_debug = "true" *)
    output reg       i2c_cmdval,
    (* mark_debug = "true" *)
    output reg       i2c_read,
    (* mark_debug = "true" *)
    output reg [7:0] i2c_addr, 
    (* mark_debug = "true" *)
    output reg [7:0] i2c_data,
    (* mark_debug = "true" *)
    output reg       i2c_dataval,
    (* mark_debug = "true" *)
    output reg [7:0] i2c_bytecnt,
    
    
    (* mark_debug = "true" *)
    input            i2ch_dataval,
    (* mark_debug = "true" *)
    input      [7:0] i2ch_dataout,
    (* mark_debug = "true" *)
    input            i2ch_ready
   
);

   wire              reset = ~nperst;
   
   // ram to hold vpd data
   (* ram_style="distributed" *)
   reg     [31:0] vpdbuf_mem [63:0];
   reg      [5:0] vpdbuf_rdaddr;
   reg      [7:0] vpdbuf_byte_wraddr;
   reg            vpdbuf_byte_write;
   wire    [31:0] vpdbuf_rddata;
   reg      [7:0] vpdbuf_wrdata;
   reg            vpdbuf_valid;
   always @(posedge clk)
     begin
        if( vpdbuf_byte_write )
          begin
             if( vpdbuf_byte_wraddr[1:0]==2'b00 ) vpdbuf_mem[vpdbuf_byte_wraddr[7:2]][7:0] = vpdbuf_wrdata;
             if( vpdbuf_byte_wraddr[1:0]==2'b01 ) vpdbuf_mem[vpdbuf_byte_wraddr[7:2]][15:8] = vpdbuf_wrdata;
             if( vpdbuf_byte_wraddr[1:0]==2'b10 ) vpdbuf_mem[vpdbuf_byte_wraddr[7:2]][23:16] = vpdbuf_wrdata;
             if( vpdbuf_byte_wraddr[1:0]==2'b11 ) vpdbuf_mem[vpdbuf_byte_wraddr[7:2]][31:24] = vpdbuf_wrdata;
          end
     end
   assign vpdbuf_rddata = vpdbuf_mem[vpdbuf_rdaddr];

   // rom to hold default vpd if reading from I2C fails
   reg [31:0] vpdrom_rddata;
   always @*
     begin
        case(vpdbuf_rdaddr)
          0: vpdrom_rddata = 32'h46001b82;
          1: vpdrom_rddata = 32'h6873616c;
          2: vpdrom_rddata = 32'h202b5447;
          3: vpdrom_rddata = 32'h65494350;
          4: vpdrom_rddata = 32'h50414320;
          5: vpdrom_rddata = 32'h41203249;
          6: vpdrom_rddata = 32'h74706164;
          7: vpdrom_rddata = 32'h8e907265;
          8: vpdrom_rddata = 32'h074e5000;
          9: vpdrom_rddata = 32'h48443130;
          10: vpdrom_rddata = 32'h45383837;
          11: vpdrom_rddata = 32'h31500643;
          12: vpdrom_rddata = 32'h37313031;
          13: vpdrom_rddata = 32'h30074e46;
          14: vpdrom_rddata = 32'h37484431;
          15: vpdrom_rddata = 32'h4e533934;
          16: vpdrom_rddata = 32'h30313707;
          17: vpdrom_rddata = 32'h58585839;
          18: vpdrom_rddata = 32'h45043156;
          19: vpdrom_rddata = 32'h564b314a;
          20: vpdrom_rddata = 32'h38350432;
          21: vpdrom_rddata = 32'h33564443;
          22: vpdrom_rddata = 32'h30303004;
          23: vpdrom_rddata = 32'h10355630;
          24: vpdrom_rddata = 32'h30303030;
          25: vpdrom_rddata = 32'h30303030;
          26: vpdrom_rddata = 32'h30303030;
          27: vpdrom_rddata = 32'h30303030;
          28: vpdrom_rddata = 32'h30103656;
          29: vpdrom_rddata = 32'h30303030;
          30: vpdrom_rddata = 32'h30303030;
          31: vpdrom_rddata = 32'h30303030;
          32: vpdrom_rddata = 32'h56303030;
          33: vpdrom_rddata = 32'h30301037;
          34: vpdrom_rddata = 32'h30303030;
          35: vpdrom_rddata = 32'h30303030;
          36: vpdrom_rddata = 32'h30303030;
          37: vpdrom_rddata = 32'h38563030;
          38: vpdrom_rddata = 32'h30303010;
          39: vpdrom_rddata = 32'h30303030;
          40: vpdrom_rddata = 32'h30303030;
          41: vpdrom_rddata = 32'h30303030;
          42: vpdrom_rddata = 32'h03565230;
          43: vpdrom_rddata = 32'h780000a2;
          default: vpdrom_rddata = 32'h0;
        endcase // case (vpdbuf_rdaddr)        
     end
   
   
   //-------------------------------------------------------
   // state machine to handle vpd reads and writes
   // at pcie link up, read vpd data from i2c
   // or write 4B from data reg if request from adr reg

   (* dont_touch = "yes" *)
   reg                   use_fixed_q = 1'b0;    
   always @(posedge clk) use_fixed_q <= use_fixed_q;

 
   localparam SM_INIT    = 4'h1;
   localparam SM_RDREQ   = 4'h2;
   localparam SM_RDRDY   = 4'h3;
   localparam SM_RDACK   = 4'h4;
   localparam SM_READY   = 4'h5;
   localparam SM_WRREQ   = 4'h6;
   localparam SM_WRRDY   = 4'h7;
   localparam SM_WRACK   = 4'h8;
                         
    (* mark_debug = "true" *)
   reg      [3:0] i2csm_q, i2csm_d;
    (* mark_debug = "true" *)
   reg      [7:0] rd_addr_q, rd_addr_d;
    (* mark_debug = "true" *)
   reg      [2:0] wr_addr_q, wr_addr_d;
    (* mark_debug = "true" *)
   reg     [20:0] wr_delay_q, wr_delay_d;

    (* mark_debug = "true" *)
   reg [31:16] vpd_adr_q, vpd_adr_d; 
    (* mark_debug = "true" *)
   reg [31:0]  vpd_dat_q, vpd_dat_d;

   reg            vpd_req_wr_val, vpd_req_wr_ack;
   reg      [5:0] vpd_req_wr_addr;

   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             i2csm_q <= SM_INIT;
          end
        else
          begin
             i2csm_q <= i2csm_d;
          end
     end

   always @(posedge clk)
     begin
        rd_addr_q <= rd_addr_d;
        wr_addr_q <= wr_addr_d;
        wr_delay_q <= wr_delay_d;
     end
       
   
   always @*
     begin
        i2csm_d             = i2csm_q;
        rd_addr_d           = rd_addr_q;
        wr_addr_d           = wr_addr_q;
        wr_delay_d          = wr_delay_q;

        vpdbuf_byte_wraddr  = rd_addr_q;
        vpdbuf_byte_write   = 1'b0;
        vpdbuf_wrdata       = i2ch_dataout;
        
        vpdbuf_valid        = 1'b0;

        vpd_req_wr_ack      = 1'b0;
        
        i2c_cmdval          = 1'b0;
        i2c_read            = 1'b1;
        i2c_addr            = rd_addr_q;       
        i2c_dataval         = 1'b0;
        i2c_bytecnt         = 8'h01;
        case(wr_addr_q[1:0])
          0:        i2c_data = vpd_dat_q[7:0];
          1:        i2c_data = vpd_dat_q[15:8];
          2:        i2c_data = vpd_dat_q[23:16];
          default:  i2c_data = vpd_dat_q[31:24];
        endcase
       
        case(i2csm_q)
          SM_INIT:
            begin
               if( i2ch_ready & user_lnk_up )
                 begin
                    i2csm_d = SM_RDREQ;
                 end
               rd_addr_d = 8'h00;
            end
          SM_RDREQ:
            begin
               i2c_cmdval  = 1'b1;
               i2c_bytecnt = 8'hff; // read 255 bytes (max for 1 op)
               i2csm_d = SM_RDRDY;
            end
          SM_RDRDY:
            begin
               // wait for ready to deassert, then wait for data
               if( ~i2ch_ready )
                 begin
                    i2csm_d = SM_RDACK;
                 end
            end
          SM_RDACK:
            begin
               if( i2ch_dataval )
                 begin
                    vpdbuf_byte_write = 1'b1;
                    rd_addr_d = rd_addr_q + 8'h01;
                 end
               
               if( i2ch_ready )
                 begin               
                    i2csm_d = SM_READY;
                 end
            end          
          // todo: check vpd checksum and reread if mismatch
          
          SM_READY:
            begin
              
               vpdbuf_valid =  ~use_fixed_q;
               // after current vpd data is read into buffer, handle vpd writes   
               wr_addr_d = 3'b000;
               i2c_read = 1'b0;
               i2c_addr = { vpd_req_wr_addr, wr_addr_q[1:0]};

               if( vpd_req_wr_val )
                 begin
                    if(  vpd_adr_q[30:24]!=7'h0 )
                      begin
                         // reread if write to addr>255
                         i2csm_d = SM_INIT;
                         vpd_req_wr_ack = 1'b1;
                      end
                    else if( i2ch_ready)
                      begin
                         i2csm_d = SM_WRREQ;
                      end
                 end
               else if( !user_lnk_up )
                 begin
                    // reread if the link goes down
                    i2csm_d = SM_INIT;
                 end               
            end
          
          SM_WRREQ:
            begin
               i2c_cmdval = 1'b1;
               i2c_read = 1'b0;
               i2c_addr = { vpd_req_wr_addr, wr_addr_q[1:0]};
               i2c_dataval = 1'b1;
               wr_delay_d = 21'h0;
               i2csm_d = SM_WRRDY; 
            end
          
          SM_WRRDY:
            begin
               i2c_read = 1'b0;
               i2c_addr = { vpd_req_wr_addr, wr_addr_q[1:0]};
               if( ~i2ch_ready )
                 begin
                   i2csm_d = SM_WRACK; 
                 end               
            end
   
          SM_WRACK:
            begin
               i2c_read = 1'b0;
               i2c_addr = { vpd_req_wr_addr, wr_addr_q[1:0]};
               if( i2ch_ready )
                 begin
                    wr_delay_d = wr_delay_q+21'h1;
                    if( wr_delay_q==21'h1312d0 )    // 5ms                  
                      begin
                         if( wr_addr_q==3'b011 )
                           begin
                              i2csm_d = SM_READY;
                              vpd_req_wr_ack = 1'b1;
                           end                
                         else
                           begin
                              i2csm_d = SM_WRREQ;
                              wr_addr_d = wr_addr_q+3'd1;
                           end
                      end
                 end
            end
                    
          default:
            begin
               i2csm_d = SM_INIT;
            end
        endcase
     end

   //-------------------------------------------------------
   // handle vpd config register accesses

   reg        vpd_req_rd_q, vpd_req_rd_d;
   reg        vpd_req_wr_q, vpd_req_wr_d;
   
   always @(posedge clk or posedge reset)
     begin
        if( reset )
          begin
             vpd_adr_q <= 16'h0;
             vpd_dat_q <= 32'h0;
             vpd_req_rd_q <= 1'b0;
             vpd_req_wr_q <= 1'b0;
          end
        else
          begin
             vpd_adr_q <= vpd_adr_d; 
             vpd_dat_q <= vpd_dat_d;
             vpd_req_rd_q <= vpd_req_rd_d;
             vpd_req_wr_q <= vpd_req_wr_d;
          end
     end
   
   always @*
     begin
        vpd_adr_d = vpd_adr_q;
        vpd_dat_d = vpd_dat_q;
        
        vpd_req_rd_d = 1'b0;
        vpdbuf_rdaddr = vpd_adr_q[23:18];

        vpd_req_wr_d = vpd_req_wr_q;
        vpd_req_wr_val = vpd_req_wr_q;
        vpd_req_wr_addr = vpd_adr_q[23:18];


        // config space write of vpd_adr register
        if( vpd_adr_en )
          begin
             vpd_adr_d = vpd_wrdata[0:15];
             vpd_req_rd_d = ~vpd_wrdata[0];
             vpd_req_wr_d = vpd_wrdata[0];
          end

        // config space write of vpd_dat register
        if( vpd_dat_en )
          begin
             vpd_dat_d = vpd_wrdata;
          end

        if( vpd_req_rd_q )
          begin
             // vpd_req_rd_q is 1 cycle pulse to capture ram/rom vpd data
             // 256B of vpd are implemented on flashGT+ card
             // return Fs for other addresses
             if( vpd_adr_q[30:24]==7'h0 )
               begin
                  if(vpdbuf_valid)
                    vpd_dat_d = vpdbuf_rddata;
                  else
                    vpd_dat_d = vpdrom_rddata;
               end
             else if( use_fixed_q & vpd_adr_q[24] )
               begin
                  vpd_dat_d = vpdbuf_rddata;
               end
             else
               begin
                  vpd_dat_d = 32'hffffffff;
               end
             
             // set rdy bit for read completed
             vpd_adr_d[31] = 1'b1;
          end

        // write completed
        if( vpd_req_wr_q & vpd_req_wr_ack )
          begin
             vpd_adr_d[31] = 1'b0;
             vpd_req_wr_d = 1'b0;
          end
        
     end

   // vpd_adr format:  1b rdy, 15b addr, 1B nxtcap ptr, 1B capability id
   assign vpd_adr = {vpd_adr_q , NXTCAP[7:0] , CAPID[7:0]};
   assign vpd_dat = vpd_dat_q;
          
               
   
endmodule

