-- *!***************************************************************************
-- *! Copyright 2019 International Business Machines
-- *!
-- *! Licensed under the Apache License, Version 2.0 (the "License");
-- *! you may not use this file except in compliance with the License.
-- *! You may obtain a copy of the License at
-- *! http://www.apache.org/licenses/LICENSE-2.0 
-- *!
-- *! The patent license granted to you in Section 3 of the License, as applied
-- *! to the "Work," hereby includes implementations of the Work in physical form. 
-- *!
-- *! Unless required by applicable law or agreed to in writing, the reference design
-- *! distributed under the License is distributed on an "AS IS" BASIS,
-- *! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- *! See the License for the specific language governing permissions and
-- *! limitations under the License.
-- *!***************************************************************************

library ieee;
use ieee.std_logic_1164.all;
Library UNISIM;
use UNISIM.vcomponents.all;

ENTITY psl_fpga IS
  PORT(
    
    -- leds
    o_led_red                                      : out   std_logic_vector(1 downto 0);
    o_led_green                                    : out   std_logic_vector(1 downto 0);
    o_led_blue                                     : out   std_logic_vector(1 downto 0);

    -- flash bus
    o_flash_oen                                    : out   std_logic;
    o_flash_wen                                    : out   std_logic;
    o_flash_rstn                                   : out   std_logic;
    o_flash_a                                      : out   std_logic_vector(25 downto 0);
    -- o_flash_a_dup: out std_logic_vector(25 to 26);
    o_flash_advn                                   : out   std_logic;
    b_flash_dq                                     : inout std_logic_vector(15 downto 4);

    -- power supply controller UCD9090 PMBUS
    b_basei2c_scl                                  : inout std_logic                     ;                                       -- clock
    b_basei2c_sda                                  : inout std_logic                     ;                                       -- data

    -- PTMON/VPD PMBUS
    b_smbus_scl                                    : inout std_logic                     ;                                       -- clock
    b_smbus_sda                                    : inout std_logic                     ;                                       -- data

    -- when i_fpga_smbus_en_n=0, host smbus is isolated from fpga/vpd/ptmon and fpga can drive scl/sda without arbitration 
    i_fpga_smbus_en_n                              : in    std_logic                     ;                                       --

    -- pci interface
    pci_pi_nperst0                                 : in    std_logic                     ;                                         -- Active low reset from the PCIe reset pin of the device
    pci_pi_refclk_p0                               : in    std_logic                     ;                                       -- 100MHz Refclk
    pci_pi_refclk_n0                               : in    std_logic                     ;                                       -- 100MHz Refclk
    
    -- Xilinx requires both pins of differential transceivers
    pci0_i_rxp_in0                                 : in    std_logic;
    pci0_i_rxn_in0                                 : in    std_logic;
    pci0_i_rxp_in1                                 : in    std_logic;
    pci0_i_rxn_in1                                 : in    std_logic;
    pci0_i_rxp_in2                                 : in    std_logic;
    pci0_i_rxn_in2                                 : in    std_logic;
    pci0_i_rxp_in3                                 : in    std_logic;
    pci0_i_rxn_in3                                 : in    std_logic;
    pci0_i_rxp_in4                                 : in    std_logic;
    pci0_i_rxn_in4                                 : in    std_logic;
    pci0_i_rxp_in5                                 : in    std_logic;
    pci0_i_rxn_in5                                 : in    std_logic;
    pci0_i_rxp_in6                                 : in    std_logic;
    pci0_i_rxn_in6                                 : in    std_logic;
    pci0_i_rxp_in7                                 : in    std_logic;
    pci0_i_rxn_in7                                 : in    std_logic;
    pci0_o_txp_out0                                : out   std_logic;
    pci0_o_txn_out0                                : out   std_logic;
    pci0_o_txp_out1                                : out   std_logic;
    pci0_o_txn_out1                                : out   std_logic;
    pci0_o_txp_out2                                : out   std_logic;
    pci0_o_txn_out2                                : out   std_logic;
    pci0_o_txp_out3                                : out   std_logic;
    pci0_o_txn_out3                                : out   std_logic;
    pci0_o_txp_out4                                : out   std_logic;
    pci0_o_txn_out4                                : out   std_logic;
    pci0_o_txp_out5                                : out   std_logic;
    pci0_o_txn_out5                                : out   std_logic;
    pci0_o_txp_out6                                : out   std_logic;
    pci0_o_txn_out6                                : out   std_logic;
    pci0_o_txp_out7                                : out   std_logic;
    pci0_o_txn_out7                                : out   std_logic;

    -- pci interface
    pci_pi_nperst1                                 : out   std_logic                     ;                                         -- Active low reset from the PCIe reset pin of the device
    pci_pi_refclk_p1                               : in    std_logic                     ;                                       -- 100MHz Refclk
    pci_pi_refclk_n1                               : in    std_logic                     ;                                       -- 100MHz Refclk

    pci1_o_susclk                                  : out   std_logic                     ;     -- 3.3V output to M.2 module - drive with 32.768KHz clock?  suspend clock
    pci1_b_nclkreq                                 : inout std_logic                     ;  -- 3.3V I/O open drain with pullup on
                                                                                            -- fpga.  pulled down by module?
    pci1_b_npewake                                 : inout std_logic                     ;   -- 3.3V I/O open drain with pullup on
                                                                                             -- fpga.  add in card asserts to request
                                                                                             -- power + refclk
    
    -- Xilinx requires both pins of differential transceivers
    pci1_i_rxp_in0                                 : in    std_logic;
    pci1_i_rxn_in0                                 : in    std_logic;
    pci1_i_rxp_in1                                 : in    std_logic;
    pci1_i_rxn_in1                                 : in    std_logic;
    pci1_i_rxp_in2                                 : in    std_logic;
    pci1_i_rxn_in2                                 : in    std_logic;
    pci1_i_rxp_in3                                 : in    std_logic;
    pci1_i_rxn_in3                                 : in    std_logic;
    
    pci1_o_txp_out0                                : out   std_logic;
    pci1_o_txn_out0                                : out   std_logic;
    pci1_o_txp_out1                                : out   std_logic;
    pci1_o_txn_out1                                : out   std_logic;
    pci1_o_txp_out2                                : out   std_logic;
    pci1_o_txn_out2                                : out   std_logic;
    pci1_o_txp_out3                                : out   std_logic;
    pci1_o_txn_out3                                : out   std_logic;
    
    -- pci interface
    pci_pi_nperst2                                 : out   std_logic                     ;                                         -- Active low reset from the PCIe reset pin of the device
    pci_pi_refclk_p2                               : in    std_logic                     ;                                       -- 100MHz Refclk
    pci_pi_refclk_n2                               : in    std_logic                     ;                                       -- 100MHz Refclk
    
    pci2_o_susclk                                  : out   std_logic                     ;     -- 3.3V output to M.2 module - drive with 32.768KHz clock?  suspend clock
    pci2_b_nclkreq                                 : inout std_logic                     ;  -- 3.3V I/O open drain with pullup on
                                                                                            -- fpga.  pulled down by module?
    pci2_b_npewake                                 : inout std_logic                     ;   -- 3.3V I/O open drain with pullup on
                                                                                             -- fpga.  add in card asserts to request
                                                                                             -- power + refclk

    -- Xilinx requires both pins of differential transceivers
    pci2_i_rxp_in0                                 : in    std_logic;
    pci2_i_rxn_in0                                 : in    std_logic;
    pci2_i_rxp_in1                                 : in    std_logic;
    pci2_i_rxn_in1                                 : in    std_logic;
    pci2_i_rxp_in2                                 : in    std_logic;
    pci2_i_rxn_in2                                 : in    std_logic;
    pci2_i_rxp_in3                                 : in    std_logic;
    pci2_i_rxn_in3                                 : in    std_logic;
    
    pci2_o_txp_out0                                : out   std_logic;
    pci2_o_txn_out0                                : out   std_logic;
    pci2_o_txp_out1                                : out   std_logic;
    pci2_o_txn_out1                                : out   std_logic;
    pci2_o_txp_out2                                : out   std_logic;
    pci2_o_txn_out2                                : out   std_logic;
    pci2_o_txp_out3                                : out   std_logic;
    pci2_o_txn_out3                                : out   std_logic;


    -- pci interface
    pci_pi_nperst3                                 : out   std_logic                     ;                                         -- Active low reset from the PCIe reset pin of the device
    pci_pi_refclk_p3                               : in    std_logic                     ;                                       -- 100MHz Refclk
    pci_pi_refclk_n3                               : in    std_logic                     ;                                       -- 100MHz Refclk

    pci3_o_susclk                                  : out   std_logic                     ;     -- 3.3V output to M.2 module - drive with 32.768KHz clock?  suspend clock
    pci3_b_nclkreq                                 : inout std_logic                     ;  -- 3.3V I/O open drain with pullup on
                                                                                            -- fpga.  pulled down by module?
    pci3_b_npewake                                 : inout std_logic                     ;   -- 3.3V I/O open drain with pullup on
                                                                                             -- fpga.  add in card asserts to request
                                                                                             -- power + refclk
    
    -- Xilinx requires both pins of differential transceivers
    pci3_i_rxp_in0                                 : in    std_logic;
    pci3_i_rxn_in0                                 : in    std_logic;
    pci3_i_rxp_in1                                 : in    std_logic;
    pci3_i_rxn_in1                                 : in    std_logic;
    pci3_i_rxp_in2                                 : in    std_logic;
    pci3_i_rxn_in2                                 : in    std_logic;
    pci3_i_rxp_in3                                 : in    std_logic;
    pci3_i_rxn_in3                                 : in    std_logic;
    
    pci3_o_txp_out0                                : out   std_logic;
    pci3_o_txn_out0                                : out   std_logic;
    pci3_o_txp_out1                                : out   std_logic;
    pci3_o_txn_out1                                : out   std_logic;
    pci3_o_txp_out2                                : out   std_logic;
    pci3_o_txn_out2                                : out   std_logic;
    pci3_o_txp_out3                                : out   std_logic;
    pci3_o_txn_out3                                : out   std_logic;
    
    -- pci interface
    pci_pi_nperst4                                 : out   std_logic                     ;                                         -- Active low reset from the PCIe reset pin of the device
    pci_pi_refclk_p4                               : in    std_logic                     ;                                       -- 100MHz Refclk
    pci_pi_refclk_n4                               : in    std_logic                     ;                                       -- 100MHz Refclk
    
    pci4_o_susclk                                  : out   std_logic                     ;     -- 3.3V output to M.2 module - drive with 32.768KHz clock?  suspend clock
    pci4_b_nclkreq                                 : inout std_logic                     ;  -- 3.3V I/O open drain with pullup on
                                                                                            -- fpga.  pulled down by module?
    pci4_b_npewake                                 : inout std_logic                     ;   -- 3.3V I/O open drain with pullup on
                                                                                             -- fpga.  add in card asserts to request
                                                                                             -- power + refclk

    -- Xilinx requires both pins of differential transceivers
    pci4_i_rxp_in0                                 : in    std_logic;
    pci4_i_rxn_in0                                 : in    std_logic;
    pci4_i_rxp_in1                                 : in    std_logic;
    pci4_i_rxn_in1                                 : in    std_logic;
    pci4_i_rxp_in2                                 : in    std_logic;
    pci4_i_rxn_in2                                 : in    std_logic;
    pci4_i_rxp_in3                                 : in    std_logic;
    pci4_i_rxn_in3                                 : in    std_logic;
    
    pci4_o_txp_out0                                : out   std_logic;
    pci4_o_txn_out0                                : out   std_logic;
    pci4_o_txp_out1                                : out   std_logic;
    pci4_o_txn_out1                                : out   std_logic;
    pci4_o_txp_out2                                : out   std_logic;
    pci4_o_txn_out2                                : out   std_logic;
    pci4_o_txp_out3                                : out   std_logic;
    pci4_o_txn_out3                                : out   std_logic

--             quad_refclk_p                               : in    std_logic                     ;               -- 266
--             quad_refclk_n                               : in    std_logic                      

    );

END psl_fpga;

ARCHITECTURE psl_fpga OF psl_fpga IS

  Component psl_accel

    PORT(
      -- Command interface
      ah_cvalid                                      : out   std_logic                    ; -- Command valid
      ah_ctag                                        : out   std_logic_vector(0 to 7)     ; -- Command tag
      ah_ctagpar                                     : out   std_logic                    ; -- Command tag parity
      ah_com                                         : out   std_logic_vector(0 to 12)    ; -- Command code
      ah_compar                                      : out   std_logic                    ; -- Command code parity
      ah_cabt                                        : out   std_logic_vector(0 to 2)     ; -- Command ABT
      ah_cea                                         : out   std_logic_vector(0 to 63)    ; -- Command address
      ah_ceapar                                      : out   std_logic                    ; -- Command address parity
      ah_cch                                         : out   std_logic_vector(0 to 15)    ; -- Command context handle
      ah_csize                                       : out   std_logic_vector(0 to 11)    ; -- Command size
      ah_cpagesize       : OUT std_logic_vector(0 to 3)   := (others => '0'); -- ** New tie to 0000
      ha_croom                                       : in    std_logic_vector(0 to 7)     ; -- Command room
      -- Buffer interface
      ha_brvalid                                     : in    std_logic                    ; -- Buffer Read valid
      ha_brtag                                       : in    std_logic_vector(0 to 7)     ; -- Buffer Read tag
      ha_brtagpar                                    : in    std_logic                    ; -- Buffer Read tag parity
      ha_brad                                        : in    std_logic_vector(0 to 5)     ; -- Buffer Read address
--       ah_brlat           : out std_logic_vector(0 to 3)   ; -- Buffer Read latency
--       ah_brdata          : out std_logic_vector(0 to 1023); -- Buffer Read data
--       ah_brpar           : out std_logic_vector(0 to 15)  ; -- Buffer Read data parity
      ha_bwvalid                                     : in    std_logic                    ; -- Buffer Write valid
      ha_bwtag                                       : in    std_logic_vector(0 to 7)     ; -- Buffer Write tag
      ha_bwtagpar                                    : in    std_logic                    ; -- Buffer Write tag parity
      ha_bwad                                        : in    std_logic_vector(0 to 5)     ; -- Buffer Write address
      ha_bwdata                                      : in    std_logic_vector(0 to 1023)  ; -- Buffer Write data
      ha_bwpar                                       : in    std_logic_vector(0 to 15)    ; -- Buffer Write data parity
      -- Response interface
      ha_rvalid                                      : in    std_logic                    ; -- Response valid
      ha_rtag                                        : in    std_logic_vector(0 to 7)     ; -- Response tag
      ha_rtagpar                                     : in    std_logic                    ; -- Response tag parity
      ha_rditag                                      : IN    std_logic_vector(0 to 8)     ;    -- **New DMA Translation Tag for xlat_* requests
      ha_rditagpar                                   : IN    std_logic                    ;                   -- **New Parity bit for above
      ha_response                                    : in    std_logic_vector(0 to 7)     ; -- Response
      ha_response_ext                                : in    std_logic_vector(0 to 7)     ; -- **New Response Ext
      ha_rpagesize                                   : IN    std_logic_vector(0 to 3)     ;    -- **New Command translated Page size.  Provided by PSL to allow
      ha_rcredits                                    : in    std_logic_vector(0 to 8)     ; -- Response credits
      ha_rcachestate                                 : in    std_logic_vector(0 to 1)     ; -- Response cache state
      ha_rcachepos                                   : in    std_logic_vector(0 to 12)    ; -- Response cache pos
--        ha_reoa            : IN  std_logic_vector(0 to 185);  -- **New unknown width or use
      -- MMIO interface
      ha_mmval                                       : in    std_logic                    ; -- A valid MMIO is present
      ha_mmcfg                                       : in    std_logic                    ; -- afu descriptor space access
      ha_mmrnw                                       : in    std_logic                    ; -- 1 = read, 0 = write
      ha_mmdw                                        : in    std_logic                    ; -- 1 = doubleword, 0 = word
      ha_mmad                                        : in    std_logic_vector(0 to 23)    ; -- mmio address
      ha_mmadpar                                     : in    std_logic                    ; -- mmio address parity
      ha_mmdata                                      : in    std_logic_vector(0 to 63)    ; -- Write data
      ha_mmdatapar                                   : in    std_logic                    ; -- mmio data parity
      ah_mmack                                       : out   std_logic                    ; -- Write is complete or Read is valid
      ah_mmdata                                      : out   std_logic_vector(0 to 63)    ; -- Read data
      ah_mmdatapar                                   : out   std_logic                    ; -- mmio data parity
      -- Control interface
      ha_jval                                        : in    std_logic                    ; -- Job valid
      ha_jcom                                        : in    std_logic_vector(0 to 7)     ; -- Job command
      ha_jcompar                                     : in    std_logic                    ; -- Job command parity
      ha_jea                                         : in    std_logic_vector(0 to 63)    ; -- Job address
      ha_jeapar                                      : in    std_logic                    ; -- Job address parity
--     ha_lop             : in  std_logic_vector(0 to 4)   ; -- LPC/Internal Cache Op code
--     ha_loppar          : in  std_logic                  ; -- Job address parity
--     ha_lsize           : in  std_logic_vector(0 to 6)   ; -- Size/Secondary Op code
--     ha_ltag            : in  std_logic_vector(0 to 11)  ; -- LPC Tag/Internal Cache Tag
--     ha_ltagpar         : in  std_logic                  ; -- LPC Tag/Internal Cache Tag parity
      ah_jrunning                                    : out   std_logic                    ; -- Job running
      ah_jdone                                       : out   std_logic                    ; -- Job done
      ah_jcack                                       : out   std_logic                    ; -- completion of llcmd
      ah_jerror                                      : out   std_logic_vector(0 to 63)    ; -- Job error
-- AM. Sept08, 2016              ah_jyield          : out std_logic                  ; -- Job yield
--     ah_ldone           : out std_logic                  ; -- LPC/Internal Cache Op done
--     ah_ldtag           : out std_logic_vector(0 to 11)  ; -- ltag is done
--     ah_ldtagpar        : out std_logic                  ; -- ldtag parity
--     ah_lroom           : out std_logic_vector(0 to 7)   ; -- LPC/Internal Cache Op AFU can handle
      ah_tbreq                                       : out   std_logic                    ; -- Timebase command request
      ah_paren                                       : out   std_logic                    ; -- parity enable
      ha_pclock                                      : in    std_logic;
      -- Port 0
-- New DMA Interface
-- DMA Req interface
      d0h_dvalid                                     : OUT   std_logic                    ;            -- New PSL/AFU interface
      d0h_req_utag                                   : OUT   std_logic_vector(0 to 9)     ;-- New PSL/AFU interface
      d0h_req_itag                                   : OUT   std_logic_vector(0 to 8)     ;-- New PSL/AFU interface
      d0h_dtype                                      : OUT   std_logic_vector(0 to 2)     ;-- New PSL/AFU interface
      d0h_dsize                                      : OUT   std_logic_vector(0 to 9)     ;-- New PSL/AFU interface
      d0h_ddata                                      : OUT   std_logic_vector(0 to 1023)  ;-- New PSL/AFU interface
      d0h_datomic_op                                 : OUT   std_logic_vector(0 to 5)     ;-- New PSL/AFU interface
      d0h_datomic_le                                 : OUT   std_logic                    ;-- New PSL/AFU interface
--       d0h_dpar            : OUT std_logic_vector(0 to 15)   ;-- New PSL/AFU interface
-- DMA Sent interface
      hd0_sent_utag_valid                            : IN    std_logic;
      hd0_sent_utag                                  : IN    std_logic_vector(0 to 9);
      hd0_sent_utag_sts                              : IN    std_logic_vector(0 to 2);
-- DMA CPL interface
      hd0_cpl_valid                                  : IN    std_logic;
      hd0_cpl_utag                                   : IN    std_logic_vector(0 to 9);
      hd0_cpl_type                                   : IN    std_logic_vector(0 to 2);
      hd0_cpl_size                                   : IN    std_logic_vector(0 to 9);
      hd0_cpl_laddr                                  : IN    std_logic_vector(0 to 6);
      hd0_cpl_byte_count                             : IN    std_logic_vector(0 to 9);
      hd0_cpl_data                                   : IN    std_logic_vector(0 to 1023);


      -- leds
      led_red                                        : out   std_logic_vector(3 downto 0);
      led_green                                      : out   std_logic_vector(3 downto 0);
      led_blue                                       : out   std_logic_vector(3 downto 0);

      ha_pclock_div2                                 : in    std_logic;
      pci_user_reset                                 : in    std_logic;
      gold_factory                                   : out   std_logic;

      -- pci interface
      pci_pi_nperst1                                 : out   std_logic                     ;                                         -- Active low reset from the PCIe reset pin of the device
      pci_pi_refclk_p1                               : in    std_logic                     ;                                       -- 100MHz Refclk
      pci_pi_refclk_n1                               : in    std_logic                     ;                                       -- 100MHz Refclk
      
      pci1_o_susclk                                  : out   std_logic;
      pci1_b_nclkreq                                 : inout std_logic;
      pci1_b_npewake                                 : inout std_logic;

      -- Xilinx requires both pins of differential transceivers
      pci1_i_rxp_in0                                 : in    std_logic;
      pci1_i_rxn_in0                                 : in    std_logic;
      pci1_i_rxp_in1                                 : in    std_logic;
      pci1_i_rxn_in1                                 : in    std_logic;
      pci1_i_rxp_in2                                 : in    std_logic;
      pci1_i_rxn_in2                                 : in    std_logic;
      pci1_i_rxp_in3                                 : in    std_logic;
      pci1_i_rxn_in3                                 : in    std_logic;
      
      pci1_o_txp_out0                                : out   std_logic;
      pci1_o_txn_out0                                : out   std_logic;
      pci1_o_txp_out1                                : out   std_logic;
      pci1_o_txn_out1                                : out   std_logic;
      pci1_o_txp_out2                                : out   std_logic;
      pci1_o_txn_out2                                : out   std_logic;
      pci1_o_txp_out3                                : out   std_logic;
      pci1_o_txn_out3                                : out   std_logic;
      
      -- pci interface
      pci_pi_nperst2                                 : out   std_logic                     ;                                         -- Active low reset from the PCIe reset pin of the device
      pci_pi_refclk_p2                               : in    std_logic                     ;                                       -- 100MHz Refclk
      pci_pi_refclk_n2                               : in    std_logic                     ;                                       -- 100MHz Refclk
      
      pci2_o_susclk                                  : out   std_logic;
      pci2_b_nclkreq                                 : inout std_logic;
      pci2_b_npewake                                 : inout std_logic;

      -- Xilinx requires both pins of differential transceivers
      pci2_i_rxp_in0                                 : in    std_logic;
      pci2_i_rxn_in0                                 : in    std_logic;
      pci2_i_rxp_in1                                 : in    std_logic;
      pci2_i_rxn_in1                                 : in    std_logic;
      pci2_i_rxp_in2                                 : in    std_logic;
      pci2_i_rxn_in2                                 : in    std_logic;
      pci2_i_rxp_in3                                 : in    std_logic;
      pci2_i_rxn_in3                                 : in    std_logic;
      
      pci2_o_txp_out0                                : out   std_logic;
      pci2_o_txn_out0                                : out   std_logic;
      pci2_o_txp_out1                                : out   std_logic;
      pci2_o_txn_out1                                : out   std_logic;
      pci2_o_txp_out2                                : out   std_logic;
      pci2_o_txn_out2                                : out   std_logic;
      pci2_o_txp_out3                                : out   std_logic;
      pci2_o_txn_out3                                : out   std_logic;
      
      -- pci interface
      pci_pi_nperst3                                 : out   std_logic                     ;                                         -- Active low reset from the PCIe reset pin of the device
      pci_pi_refclk_p3                               : in    std_logic                     ;                                       -- 100MHz Refclk
      pci_pi_refclk_n3                               : in    std_logic                     ;                                       -- 100MHz Refclk
      
      pci3_o_susclk                                  : out   std_logic;
      pci3_b_nclkreq                                 : inout std_logic;
      pci3_b_npewake                                 : inout std_logic;
      
      -- Xilinx requires both pins of differential transceivers
      pci3_i_rxp_in0                                 : in    std_logic;
      pci3_i_rxn_in0                                 : in    std_logic;
      pci3_i_rxp_in1                                 : in    std_logic;
      pci3_i_rxn_in1                                 : in    std_logic;
      pci3_i_rxp_in2                                 : in    std_logic;
      pci3_i_rxn_in2                                 : in    std_logic;
      pci3_i_rxp_in3                                 : in    std_logic;
      pci3_i_rxn_in3                                 : in    std_logic;
      
      pci3_o_txp_out0                                : out   std_logic;
      pci3_o_txn_out0                                : out   std_logic;
      pci3_o_txp_out1                                : out   std_logic;
      pci3_o_txn_out1                                : out   std_logic;
      pci3_o_txp_out2                                : out   std_logic;
      pci3_o_txn_out2                                : out   std_logic;
      pci3_o_txp_out3                                : out   std_logic;
      pci3_o_txn_out3                                : out   std_logic;
      
      -- pci interface
      pci_pi_nperst4                                 : out   std_logic                     ;                                         -- Active low reset from the PCIe reset pin of the device
      pci_pi_refclk_p4                               : in    std_logic                     ;                                       -- 100MHz Refclk
      pci_pi_refclk_n4                               : in    std_logic                     ;                                       -- 100MHz Refclk
      
      pci4_o_susclk                                  : out   std_logic;
      pci4_b_nclkreq                                 : inout std_logic;
      pci4_b_npewake                                 : inout std_logic;
      
      -- Xilinx requires both pins of differential transceivers
      pci4_i_rxp_in0                                 : in    std_logic;
      pci4_i_rxn_in0                                 : in    std_logic;
      pci4_i_rxp_in1                                 : in    std_logic;
      pci4_i_rxn_in1                                 : in    std_logic;
      pci4_i_rxp_in2                                 : in    std_logic;
      pci4_i_rxn_in2                                 : in    std_logic;
      pci4_i_rxp_in3                                 : in    std_logic;
      pci4_i_rxn_in3                                 : in    std_logic;
      
      pci4_o_txp_out0                                : out   std_logic;
      pci4_o_txn_out0                                : out   std_logic;
      pci4_o_txp_out1                                : out   std_logic;
      pci4_o_txn_out1                                : out   std_logic;
      pci4_o_txp_out2                                : out   std_logic;
      pci4_o_txn_out2                                : out   std_logic;
      pci4_o_txp_out3                                : out   std_logic;
      pci4_o_txn_out3:out std_logic

      );
  End Component psl_accel;

-- OBUF: Output Buffer
-- UltraScale
-- Xilinx HDL Libraries Guide, version 2015.4
  Component OBUF
    PORT (O : out std_logic;
          I : in std_logic);
  End Component OBUF;

-- Component pcie4_uscale_plus_0
  Component pcie4_uscale_plus_0
    PORT(
      pci_exp_txn : out STD_LOGIC_VECTOR (7 downto 0 );
      pci_exp_txp : out STD_LOGIC_VECTOR (7 downto 0 );
      pci_exp_rxn : in STD_LOGIC_VECTOR (7 downto 0 );
      pci_exp_rxp : in STD_LOGIC_VECTOR (7 downto 0 );
      user_clk                                       : out   STD_LOGIC;
      user_reset                                     : out   STD_LOGIC;
      user_lnk_up                                    : out   STD_LOGIC;
      s_axis_rq_tdata : in STD_LOGIC_VECTOR ( 511 downto 0 );
      s_axis_rq_tkeep : in STD_LOGIC_VECTOR ( 15 downto 0 );
      s_axis_rq_tlast                                : in    STD_LOGIC;
      s_axis_rq_tready : out STD_LOGIC_VECTOR ( 3 downto 0 );
      s_axis_rq_tuser : in STD_LOGIC_VECTOR ( 136 downto 0 );
      s_axis_rq_tvalid                               : in    STD_LOGIC;
      m_axis_rc_tdata : out STD_LOGIC_VECTOR ( 511 downto 0 );
      m_axis_rc_tkeep : out STD_LOGIC_VECTOR ( 15 downto 0 );
      m_axis_rc_tlast                                : out   STD_LOGIC;
      m_axis_rc_tready : in STD_LOGIC_VECTOR ( 0 downto 0 );
      m_axis_rc_tuser : out STD_LOGIC_VECTOR ( 160 downto 0 );
      m_axis_rc_tvalid                               : out   STD_LOGIC;
      m_axis_cq_tdata : out STD_LOGIC_VECTOR ( 511 downto 0 );
      m_axis_cq_tkeep : out STD_LOGIC_VECTOR ( 15 downto 0 );
      m_axis_cq_tlast                                : out   STD_LOGIC;
      m_axis_cq_tready : in STD_LOGIC_VECTOR ( 0 downto 0 );
      m_axis_cq_tuser : out STD_LOGIC_VECTOR ( 182 downto 0 );
      m_axis_cq_tvalid                               : out   STD_LOGIC;
      s_axis_cc_tdata : in STD_LOGIC_VECTOR ( 511 downto 0 );
      s_axis_cc_tkeep : in STD_LOGIC_VECTOR ( 15 downto 0 );
      s_axis_cc_tlast                                : in    STD_LOGIC;
      s_axis_cc_tready : out STD_LOGIC_VECTOR ( 3 downto 0 );
      s_axis_cc_tuser : in STD_LOGIC_VECTOR ( 80 downto 0 );
      s_axis_cc_tvalid                               : in    STD_LOGIC;
      pcie_rq_seq_num0 : out STD_LOGIC_VECTOR ( 5 downto 0 );
      pcie_rq_seq_num_vld0                           : out   STD_LOGIC;
      pcie_rq_seq_num1 : out STD_LOGIC_VECTOR ( 5 downto 0 );
      pcie_rq_seq_num_vld1                           : out   STD_LOGIC;
      pcie_rq_tag0 : out STD_LOGIC_VECTOR ( 7 downto 0 );
      pcie_rq_tag1 : out STD_LOGIC_VECTOR ( 7 downto 0 );
      pcie_rq_tag_av : out STD_LOGIC_VECTOR ( 3 downto 0 );
      pcie_rq_tag_vld0                               : out   STD_LOGIC;
      pcie_rq_tag_vld1                               : out   STD_LOGIC;
      pcie_tfc_nph_av : out STD_LOGIC_VECTOR ( 3 downto 0 );
      pcie_tfc_npd_av : out STD_LOGIC_VECTOR ( 3 downto 0 );
      pcie_cq_np_req : in STD_LOGIC_VECTOR ( 1 downto 0 );
      pcie_cq_np_req_count : out STD_LOGIC_VECTOR ( 5 downto 0 );
      cfg_phy_link_down                              : out   STD_LOGIC;
      cfg_phy_link_status : out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_negotiated_width : out STD_LOGIC_VECTOR ( 2 downto 0 );
      cfg_current_speed : out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_max_payload : out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_max_read_req : out STD_LOGIC_VECTOR ( 2 downto 0 );
      cfg_function_status : out STD_LOGIC_VECTOR ( 15 downto 0 );
      cfg_function_power_state : out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_vf_status : out STD_LOGIC_VECTOR ( 503 downto 0 );
      cfg_vf_power_state : out STD_LOGIC_VECTOR ( 755 downto 0 );
      cfg_link_power_state : out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_mgmt_addr : in STD_LOGIC_VECTOR ( 9 downto 0 );
      cfg_mgmt_function_number : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_mgmt_write                                 : in    STD_LOGIC;
      cfg_mgmt_write_data : in STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_mgmt_byte_enable : in STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_mgmt_read                                  : in    STD_LOGIC;
      cfg_mgmt_read_data : out STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_mgmt_read_write_done                       : out   STD_LOGIC;
      cfg_mgmt_debug_access                          : in    STD_LOGIC;
      cfg_err_cor_out                                : out   STD_LOGIC;
      cfg_err_nonfatal_out                           : out   STD_LOGIC;
      cfg_err_fatal_out                              : out   STD_LOGIC;
      cfg_local_error_valid                          : out   STD_LOGIC;
--     cfg_ltr_enable : out STD_LOGIC;
      cfg_local_error_out : out STD_LOGIC_VECTOR ( 4 downto 0 );
      cfg_ltssm_state : out STD_LOGIC_VECTOR ( 5 downto 0 );
      cfg_rx_pm_state : out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_tx_pm_state : out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_rcb_status : out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_obff_enable : out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_pl_status_change                           : out   STD_LOGIC;
      cfg_tph_requester_enable : out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_tph_st_mode : out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_vf_tph_requester_enable : out STD_LOGIC_VECTOR ( 251 downto 0 );
      cfg_vf_tph_st_mode : out STD_LOGIC_VECTOR ( 755 downto 0 );
      cfg_msg_received                               : out   STD_LOGIC;
      cfg_msg_received_data : out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_msg_received_type : out STD_LOGIC_VECTOR ( 4 downto 0 );
      cfg_msg_transmit                               : in    STD_LOGIC;
      cfg_msg_transmit_type : in STD_LOGIC_VECTOR ( 2 downto 0 );
      cfg_msg_transmit_data : in STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_msg_transmit_done                          : out   STD_LOGIC;
      cfg_fc_ph : out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_fc_pd : out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_fc_nph : out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_fc_npd : out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_fc_cplh : out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_fc_cpld : out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_fc_sel : in STD_LOGIC_VECTOR ( 2 downto 0 );
      cfg_dsn : in STD_LOGIC_VECTOR ( 63 downto 0 );
      cfg_bus_number : out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_power_state_change_ack                     : in    STD_LOGIC;
      cfg_power_state_change_interrupt               : out   STD_LOGIC;
      cfg_err_cor_in                                 : in    STD_LOGIC;
      cfg_err_uncor_in                               : in    STD_LOGIC;
      cfg_flr_in_process : out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_flr_done : in STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_vf_flr_in_process : out STD_LOGIC_VECTOR ( 251 downto 0 );
      cfg_vf_flr_func_num : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_vf_flr_done : in STD_LOGIC_VECTOR ( 0 to 0 );
      cfg_link_training_enable                       : in    STD_LOGIC;
      cfg_ext_read_received                          : out   STD_LOGIC;
      cfg_ext_write_received                         : out   STD_LOGIC;
      cfg_ext_register_number : out STD_LOGIC_VECTOR ( 9 downto 0 );
      cfg_ext_function_number : out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_ext_write_data : out STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_ext_write_byte_enable : out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_ext_read_data : in STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_ext_read_data_valid                        : in    STD_LOGIC;
      cfg_interrupt_int : in STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_interrupt_pending : in STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_interrupt_sent                             : out   STD_LOGIC;

      cfg_interrupt_msi_enable : out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_interrupt_msi_mmenable : out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_interrupt_msi_mask_update                  : out   STD_LOGIC;
      cfg_interrupt_msi_data : out STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_interrupt_msi_select : in STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_interrupt_msi_int : in STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_interrupt_msi_pending_status : in STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_interrupt_msi_pending_status_data_enable   : in    STD_LOGIC;
      cfg_interrupt_msi_pending_status_function_num : in STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_interrupt_msi_sent                         : out   STD_LOGIC;
      cfg_interrupt_msi_fail                         : out   STD_LOGIC;
      cfg_interrupt_msi_attr : in STD_LOGIC_VECTOR ( 2 downto 0 );
      cfg_interrupt_msi_tph_present                  : in    STD_LOGIC;
      cfg_interrupt_msi_tph_type : in STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_interrupt_msi_tph_st_tag : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_interrupt_msi_function_number : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_pm_aspm_l1_entry_reject                    : in    STD_LOGIC;
      cfg_pm_aspm_tx_l0s_entry_disable               : in    STD_LOGIC;
      cfg_hot_reset_out                              : out   STD_LOGIC;
      cfg_config_space_enable                        : in    STD_LOGIC;
      cfg_req_pm_transition_l23_ready                : in    STD_LOGIC;
      cfg_hot_reset_in                               : in    STD_LOGIC;
      cfg_ds_port_number : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_ds_bus_number : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_ds_device_number : in STD_LOGIC_VECTOR ( 4 downto 0 );

--     cfg_pm_aspm_l1_entry_reject : in STD_LOGIC;
--     cfg_pm_aspm_tx_l0s_entry_disable : in STD_LOGIC;
--     cfg_hot_reset_out : out STD_LOGIC;
--     cfg_config_space_enable : in STD_LOGIC;
--     cfg_req_pm_transition_l23_ready : in STD_LOGIC;
--     cfg_hot_reset_in : in STD_LOGIC;
--     cfg_ds_port_number : in STD_LOGIC_VECTOR ( 7 downto 0 );
--     cfg_ds_bus_number : in STD_LOGIC_VECTOR ( 7 downto 0 );
--     cfg_ds_device_number : in STD_LOGIC_VECTOR ( 4 downto 0 );
--     cfg_ds_function_number : in STD_LOGIC_VECTOR ( 2 downto 0 );
--     cfg_subsys_vend_id : in STD_LOGIC_VECTOR ( 15 downto 0 );
--     cfg_dev_id_pf0 : in STD_LOGIC_VECTOR ( 15 downto 0 );
--     cfg_dev_id_pf1 : in STD_LOGIC_VECTOR ( 15 downto 0 );
--     cfg_dev_id_pf2 : in STD_LOGIC_VECTOR ( 15 downto 0 );
--     cfg_dev_id_pf3 : in STD_LOGIC_VECTOR ( 15 downto 0 );
--     cfg_vend_id : in STD_LOGIC_VECTOR ( 15 downto 0 );
--     cfg_rev_id_pf0 : in STD_LOGIC_VECTOR ( 7 downto 0 );
--     cfg_rev_id_pf1 : in STD_LOGIC_VECTOR ( 7 downto 0 );
--     cfg_rev_id_pf2 : in STD_LOGIC_VECTOR ( 7 downto 0 );
--     cfg_rev_id_pf3 : in STD_LOGIC_VECTOR ( 7 downto 0 );
--     cfg_subsys_id_pf0 : in STD_LOGIC_VECTOR ( 15 downto 0 );
--     cfg_subsys_id_pf1 : in STD_LOGIC_VECTOR ( 15 downto 0 );
--     cfg_subsys_id_pf2 : in STD_LOGIC_VECTOR ( 15 downto 0 );
--     cfg_subsys_id_pf3 : in STD_LOGIC_VECTOR ( 15 downto 0 );

      sys_clk                                        : in    STD_LOGIC;
      sys_clk_gt                                     : in    STD_LOGIC;
      sys_reset                                      : in    STD_LOGIC;
      phy_rdy_out                                    : out   STD_LOGIC
      
      -- New for 2016.4   
      --int_qpll0lock_out : out STD_LOGIC_VECTOR ( 1 downto 0 );
      --int_qpll0outrefclk_out : out STD_LOGIC_VECTOR ( 1 downto 0 );
      --int_qpll0outclk_out : out STD_LOGIC_VECTOR ( 1 downto 0 );
      --int_qpll1lock_out : out STD_LOGIC_VECTOR ( 1 downto 0 );
      --int_qpll1outrefclk_out : out STD_LOGIC_VECTOR ( 1 downto 0 );
      --int_qpll1outclk_out : out STD_LOGIC_VECTOR ( 1 downto 0 )
      
      );

  end Component pcie4_uscale_plus_0;

-- IBUFDS_GTE4: Gigabit Transceiver Buffer
-- UltraScale
-- Xilinx HDL Libraries Guide, version 2015.4

  Component IBUFDS_GTE4 
-- generic(
-- REFCLK_EN_TX_PATH : in std_logic;
-- REFCLK_HROW_CK_SEL : in std_logic_vector(0 to 1);
-- REFCLK_ICNTL_RX  : in std_logic_vector(0 to 1)
-- );
    PORT
      (O : out STD_LOGIC;
       ODIV2                                          : out   STD_LOGIC;
       I                                              : in    STD_LOGIC;
       CEB                                            : in    STD_LOGIC;
       IB : in STD_LOGIC
       );
  end Component IBUFDS_GTE4;

  Component IBUF
    PORT (
      O                                              : out   STD_LOGIC;
      I : in  STD_LOGIC
      );
  end Component IBUF;

  Component flashgtp_clk_wiz
    PORT ( 
      clk_in1                                        : in    STD_LOGIC;
      clk_out1                                       : out   STD_LOGIC;
      clk_out2                                       : out   STD_LOGIC;
      clk_out3                                       : out   STD_LOGIC;
      clk_out3_ce                                    : in    STD_LOGIC;
      reset                                          : in    STD_LOGIC;
      locked : out STD_LOGIC
      );
  end Component flashgtp_clk_wiz;

  Component clk_wiz_quad_freerun0
    PORT (              
      clk_out1                                       : out   STD_LOGIC;               -- 250
      clk_in1_n                                      : in   STD_LOGIC;
      clk_in1_p                                      : in    STD_LOGIC;
      reset                                          : in    STD_LOGIC;
      locked : out STD_LOGIC
      );
  end Component clk_wiz_quad_freerun0;




-- Component psl
  Component PSL9_WRAP_0
    PORT(
------        psl_clk: in std_logic;
------        psl_rst: in std_logic;
------        pcihip0_psl_clk: in std_logic;
------        pcihip0_psl_rst: in std_logic;
------        crc_error: in std_logic;
      a0h_cvalid                                     : in    std_logic;
      a0h_ctag                                       : in    std_logic_vector(0 to 7);
      a0h_com                                        : in    std_logic_vector(0 to 12);
------        a0h_cpad: in std_logic_vector(0 to 2);
      a0h_cabt                                       : in    std_logic_vector(0 to 2);
      a0h_cea                                        : in    std_logic_vector(0 to 63);
      a0h_cch                                        : in    std_logic_vector(0 to 15);
      a0h_csize                                      : in    std_logic_vector(0 to 11);
      a0h_cpagesize                                  : in    std_logic_vector(0 to 3);
      ha0_croom                                      : out   std_logic_vector(0 to 7);
      a0h_ctagpar                                    : in    std_logic;
      a0h_compar                                     : in    std_logic;
      a0h_ceapar                                     : in    std_logic;
      ha0_brvalid                                    : out   std_logic;
      ha0_brtag                                      : out   std_logic_vector(0 to 7);
      ha0_brad                                       : out   std_logic_vector(0 to 5);
      a0h_brlat                                      : in    std_logic_vector(0 to 3);
      a0h_brdata                                     : in    std_logic_vector(0 to 1023);
      a0h_brpar                                      : in    std_logic_vector(0 to 15);
      ha0_bwvalid                                    : out   std_logic;
      ha0_bwtag                                      : out   std_logic_vector(0 to 7);
      ha0_bwad                                       : out   std_logic_vector(0 to 5);
      ha0_bwdata                                     : out   std_logic_vector(0 to 1023);
      ha0_bwpar                                      : out   std_logic_vector(0 to 15);
      ha0_brtagpar                                   : out   std_logic;
      ha0_bwtagpar                                   : out   std_logic;
      ha0_rvalid                                     : out   std_logic;
      ha0_rtag                                       : out   std_logic_vector(0 to 7);
      ha0_rtagpar                                    : out   std_logic;
      ha0_rditag                                     : out   std_logic_vector(0 to 8);
      ha0_rditagpar                                  : out   std_logic;
      ha0_response                                   : out   std_logic_vector(0 to 7);
      ha0_response_ext                               : out   std_logic_vector(0 to 7);
      ha0_rpagesize                                  : out   std_logic_vector(0 to 3);
      ha0_rcredits                                   : out   std_logic_vector(0 to 8);
      ha0_rcachestate                                : out   std_logic_vector(0 to 1);
      ha0_rcachepos                                  : out   std_logic_vector(0 to 12);
      ha0_reoa                                       : out   std_logic_vector(0 to 185);

      ha0_mmval                                      : out   std_logic;
      ha0_mmcfg                                      : out   std_logic;
      ha0_mmrnw                                      : out   std_logic;
      ha0_mmdw                                       : out   std_logic;
      ha0_mmad                                       : out   std_logic_vector(0 to 23);
      ha0_mmadpar                                    : out   std_logic;
      ha0_mmdata                                     : out   std_logic_vector(0 to 63);
      ha0_mmdatapar                                  : out   std_logic;
      a0h_mmack                                      : in    std_logic;
      a0h_mmdata                                     : in    std_logic_vector(0 to 63);
      a0h_mmdatapar                                  : in    std_logic;

      ha0_jval                                       : out   std_logic;
      ha0_jcom                                       : out   std_logic_vector(0 to 7);
      ha0_jcompar                                    : out   std_logic;
      ha0_jea                                        : out   std_logic_vector(0 to 63);
      ha0_jeapar                                     : out   std_logic;
      a0h_jrunning                                   : in    std_logic;
      a0h_jdone                                      : in    std_logic;
      a0h_jcack                                      : in    std_logic;
      a0h_jerror                                     : in    std_logic_vector(0 to 63);
--        a0h_jyield: in std_logic;
      a0h_tbreq                                      : in    std_logic;
      a0h_paren                                      : in    std_logic;
      ha0_pclock                                     : out   std_logic;


      D0H_DVALID                                     : in    std_logic;
      D0H_REQ_UTAG                                   : in    std_logic_vector(0 to 9);
      D0H_REQ_ITAG                                   : in    std_logic_vector(0 to 8);
      D0H_DTYPE                                      : in    std_logic_vector(0 to 2);
--         DH_DRELAXED:in  std_logic;
      D0H_DATOMIC_OP                                 : in    std_logic_vector(0 to 5);
      D0H_DATOMIC_LE                                 : in    std_logic                    ;-- New PSL/AFU interface
      D0H_DSIZE                                      : in    std_logic_vector(0 to 9);
      D0H_DDATA                                      : in    std_logic_vector(0 to 1023);
--         D0H_DPAR: in std_logic_vector(0 to 15);  
--         // ----------------------------------------------------------------------------------------------------------------------
--         // ----------------------------
--         // PSL DMA Completion Interface
--         // ----------------------------
      HD0_CPL_VALID                                  : out   std_logic;
      HD0_CPL_UTAG                                   : out   std_logic_vector(0 to 9);
      HD0_CPL_TYPE                                   : out   std_logic_vector(0 to 2);
      HD0_CPL_LADDR                                  : out   std_logic_vector(0 to 6);
      HD0_CPL_BYTE_COUNT                             : out   std_logic_vector(0 to 9);
      HD0_CPL_SIZE                                   : out   std_logic_vector(0 to 9);
      HD0_CPL_DATA                                   : out   std_logic_vector(0 to 1023);
--         HD0_CPL_DPAR : out std_logic_vector(0 to 15);      
--         // ----------------------------------------------------------------------------------------------------------------------
--         // ----------------------
--         // PSL DMA Sent Interface
--         // ----------------------
      HD0_SENT_UTAG_VALID                            : out   std_logic;
      HD0_SENT_UTAG                                  : out   std_logic_vector(0 to 9);
      HD0_SENT_UTAG_STS                              : out   std_logic_vector(0 to 2);



      AXIS_CQ_TVALID                                 : in    std_logic;
      AXIS_CQ_TDATA                                  : in    std_logic_vector(511 downto 0);
      AXIS_CQ_TREADY                                 : out   std_logic;
      AXIS_CQ_TUSER                                  : in    std_logic_vector(182 downto 0);
      AXIS_CQ_NP_REQ                                 : out   std_logic_vector(1 downto 0);
--         //XLX IP RC Interface                                                                                             
      AXIS_RC_TVALID                                 : in    std_logic;
      AXIS_RC_TDATA                                  : in    std_logic_vector(511 downto 0);
      AXIS_RC_TREADY                                 : out   std_logic;
      AXIS_RC_TUSER                                  : in    std_logic_vector(160 downto 0);
--         //-----------------------------------------------------------------------------------------------------------------------
--         //XLX IP RQ Interface                                                                                                    
      AXIS_RQ_TVALID                                 : out   std_logic;
      AXIS_RQ_TDATA                                  : out   std_logic_vector(511 downto 0);
      AXIS_RQ_TREADY                                 : in    std_logic;
      AXIS_RQ_TLAST                                  : out   std_logic;
      AXIS_RQ_TUSER                                  : out   std_logic_vector(136 downto 0);
      AXIS_RQ_TKEEP                                  : out   std_logic_vector(15 downto 0);
--         //XLX IP CC Interface                                                                                                   
      AXIS_CC_TVALID                                 : out   std_logic;
      AXIS_CC_TDATA                                  : out   std_logic_vector(511 downto 0);
      AXIS_CC_TREADY                                 : in    std_logic;
      AXIS_CC_TLAST                                  : out   std_logic;
      AXIS_CC_TUSER                                  : out   std_logic_vector(80 downto 0);
      AXIS_CC_TKEEP                                  : out   std_logic_vector(15 downto 0);
--         //----------------------------------------------------------------------------------------------------------------------
--         // Configuration Interface
--         // cfg_fc_sel[2:0] = 101b, cfg_fc_ph[7:0], cfg_fc_pd[11:0] cfg_fc_nph[7:0]
      XIP_CFG_FC_SEL                                 : out   std_logic_vector(2 downto 0);
      XIP_CFG_FC_PH                                  : in    std_logic_vector(7 downto 0);
      XIP_CFG_FC_PD                                  : in    std_logic_vector(11 downto 0);
      XIP_CFG_FC_NP                                  : in    std_logic_vector(7 downto 0);

      psl_kill_link                                  : out   std_logic;
      psl_build_ver                                  : in    std_logic_vector(0 to 31);
      afu_clk                                        : in    std_logic;

      PSL_RST                                        : in    std_logic;
      PSL_CLK                                        : in    std_logic;
      PCIHIP_PSL_RST                                 : in    std_logic;
      PCIHIP_PSL_CLK : in std_logic                                                                                           

      );
-- End Component psl;
  End Component PSL9_WRAP_0;



  Component psl_hdk_wrap
    PORT(
      cfg_ext_read_received                          : IN    STD_LOGIC;
      cfg_ext_write_received                         : IN    STD_LOGIC;
      cfg_ext_register_number                        : IN    STD_LOGIC_VECTOR(9 DOWNTO 0);
      cfg_ext_function_number                        : IN    STD_LOGIC_VECTOR(7 DOWNTO 0);
      cfg_ext_write_data                             : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
      cfg_ext_write_byte_enable                      : IN    STD_LOGIC_VECTOR(3 DOWNTO 0);
      cfg_ext_read_data                              : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
      cfg_ext_read_data_valid                        : OUT   STD_LOGIC;

      o_flash_oen                                    : out   std_logic;
      o_flash_wen                                    : out   std_logic;
      o_flash_rstn                                   : out   std_logic;
      o_flash_a                                      : out   std_logic_vector(25 downto 0);
      o_flash_advn                                   : out   std_logic;
      b_flash_dq                                     : inout std_logic_vector(15 downto 4);

      pci_pi_nperst0                                 : in    std_logic;
      user_lnk_up                                    : in    std_logic;
      pcihip0_psl_clk                                : in    std_logic;
      icap_clk                                       : in    std_logic;
      cpld_usergolden                                : in    std_logic                     ;  -- bool
      crc_error                                      : out   std_logic;
      -- power supply controller UCD9090 PMBUS
      b_basei2c_scl                                  : inout std_logic                     ;                                       -- clock
      b_basei2c_sda                                  : inout std_logic                     ;                                       -- data
      -- PTMON/VPD PMBUS
      b_smbus_scl                                    : inout std_logic                     ;      -- clock
      b_smbus_sda                                    : inout std_logic                     ;       -- data
      i_fpga_smbus_en_n                              : in std_logic);
  END Component psl_hdk_wrap;



  attribute mark_debug : string;  
  Signal psl_rst: std_logic;     -- AM. TBD
  Signal a0h_brdata: std_logic_vector(0 to 1023);  -- hline
  Signal a0h_brlat: std_logic_vector(0 to 3);  -- v4bit
  Signal a0h_brpar: std_logic_vector(0 to 15);  -- v8bit
  Signal a0h_cabt: std_logic_vector(0 to 2);  -- cabt
  Signal a0h_cch: std_logic_vector(0 to 15);  -- ctxhndl
  Signal a0h_cea: std_logic_vector(0 to 63);  -- ead
  Signal a0h_ceapar: std_logic;  -- bool
  Signal a0h_com: std_logic_vector(0 to 12);  -- apcmd
  Signal a0h_compar: std_logic;  -- bool
  Signal a0h_csize: std_logic_vector(0 to 11);  -- v12bit
  Signal a0h_ctag: std_logic_vector(0 to 7);  -- acctag
  Signal a0h_ctagpar: std_logic;  -- bool
  Signal a0h_cvalid: std_logic;  -- bool
  Signal a0h_jcack: std_logic;  -- bool
  Signal a0h_jdone: std_logic;  -- bool
  Signal a0h_jerror: std_logic_vector(0 to 63);  -- v64bit
  Signal a0h_jrunning: std_logic;  -- bool
  Signal a0h_jyield: std_logic;  -- bool
  Signal a0h_mmack: std_logic;  -- bool
  Signal a0h_mmdata: std_logic_vector(0 to 63);  -- v64bit
  Signal a0h_mmdatapar: std_logic;  -- bool
  Signal a0h_paren: std_logic;  -- bool
  Signal a0h_tbreq: std_logic;  -- bool
  Signal a0h_cpagesize: std_logic_vector(0 to 3);
  Signal ha0_brad: std_logic_vector(0 to 5);  -- v6bit
  Signal ha0_brtag: std_logic_vector(0 to 7);  -- acctag
  Signal ha0_brtagpar: std_logic;  -- bool
  Signal ha0_brvalid: std_logic;  -- bool
  Signal ha0_bwad: std_logic_vector(0 to 5);  -- v6bit
  Signal ha0_bwdata: std_logic_vector(0 to 1023);  -- hline
  Signal ha0_bwpar: std_logic_vector(0 to 15);  -- v8bit
  Signal ha0_bwtag: std_logic_vector(0 to 7);  -- acctag
  Signal ha0_bwtagpar: std_logic;  -- bool
  Signal ha0_bwvalid: std_logic;  -- bool
  Signal ha0_croom: std_logic_vector(0 to 7);  -- v8bit
  Signal ha0_jcom: std_logic_vector(0 to 7);  -- jbcom
  Signal ha0_jcompar: std_logic;  -- bool
  Signal ha0_jea: std_logic_vector(0 to 63);  -- v64bit
  Signal ha0_jeapar: std_logic;  -- bool
  Signal ha0_jval: std_logic;  -- bool
  Signal ha0_mmad: std_logic_vector(0 to 23);  -- v24bit
  Signal ha0_mmadpar: std_logic;  -- bool
  Signal ha0_mmcfg: std_logic;  -- bool
  Signal ha0_mmdata: std_logic_vector(0 to 63);  -- v64bit
  Signal ha0_mmdatapar: std_logic;  -- bool
  Signal ha0_mmdw: std_logic;  -- bool
  Signal ha0_mmrnw: std_logic;  -- bool
  Signal ha0_mmval: std_logic;  -- bool
  Signal ha0_pclock: std_logic;  -- bool
  Signal ha0_rcachepos: std_logic_vector(0 to 12);  -- v13bit
  Signal ha0_rcachestate: std_logic_vector(0 to 1);  -- statespec
  Signal ha0_rpagesize: std_logic_vector(0 to 3);
  Signal ha0_rcredits: std_logic_vector(0 to 8);  -- v9bit
  Signal ha0_reoa: std_logic_vector(0 to 185);
  Signal ha0_response: std_logic_vector(0 to 7);  -- apresp
  Signal ha0_response_ext: std_logic_vector(0 to 7);  -- apresp
  Signal ha0_rtag: std_logic_vector(0 to 7);  -- acctag
  Signal ha0_rtagpar: std_logic;  -- bool
  Signal ha0_rditag: std_logic_vector(0 to 8);  -- 
  Signal ha0_rditagpar: std_logic;
  Signal ha0_rvalid: std_logic;  -- bool

  Signal hip_npor0: std_logic;  -- bool
  Signal i_cpld_sda: std_logic;  -- bool
  Signal cpld_usergolden: std_logic;  -- bool
  Signal crc_error: std_logic;  -- bool
  Signal i_therm_sda: std_logic;  -- bool
  Signal i_ucd_sda: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_app_int_ack: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_app_msi_ack: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_cfg_par_err: std_logic;  -- bool
  Signal pcihip0_psl_coreclkout_hip: std_logic;  -- bool
  Signal pcihip0_psl_cseb_addr: std_logic_vector(0 to 32);  -- v33bit
  Signal pcihip0_psl_cseb_addr_parity: std_logic_vector(0 to 4);  -- v5bit
  Signal pcihip0_psl_cseb_be: std_logic_vector(0 to 3);  -- v4bit
  Signal pcihip0_psl_cseb_rden: std_logic;  -- bool
  Signal pcihip0_psl_cseb_wrdata: std_logic_vector(0 to 31);  -- v32bit
  Signal pcihip0_psl_cseb_wrdata_parity: std_logic_vector(0 to 3);  -- v4bit
  Signal pcihip0_psl_cseb_wren: std_logic;  -- bool
  Signal pcihip0_psl_cseb_wrresp_req: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_derr_cor_ext_rcv: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_derr_cor_ext_rpl: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_derr_rpl: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_hip_reconfig_readdata: std_logic_vector(0 to 15);  -- v16bit
-- Apr13 Signal pcihip0_psl_ko_cpl_spc_data: std_logic_vector(0 to 11);  -- v12bit
-- Apr13 Signal pcihip0_psl_ko_cpl_spc_header: std_logic_vector(0 to 7);  -- v8bit
-- Apr13 Signal pcihip0_psl_lmi_ack: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_lmi_dout: std_logic_vector(0 to 31);  -- v32bit
  Signal pcihip0_psl_pld_clk_inuse: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_pme_to_sr: std_logic;  -- bool
  Signal pcihip0_psl_reset_status: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_rx_par_err: std_logic;  -- bool
  Signal pcihip0_psl_rx_st_bar: std_logic_vector(0 to 7);  -- v8bit
  Signal pcihip0_psl_rx_st_data: std_logic_vector(0 to 255);  -- v256bit
  Signal pcihip0_psl_rx_st_empty: std_logic_vector(0 to 1);  -- v2bit
  Signal pcihip0_psl_rx_st_eop: std_logic;  -- bool
  Signal pcihip0_psl_rx_st_err: std_logic;  -- bool
  Signal pcihip0_psl_rx_st_parity: std_logic_vector(0 to 31);  -- v32bit
  Signal pcihip0_psl_rx_st_sop: std_logic;  -- bool
  Signal pcihip0_psl_rx_st_valid: std_logic;  -- bool
-- Apr13 Signal pcihip0_psl_testin_zero: std_logic;  -- bool
  Signal pcihip0_psl_tl_cfg_add: std_logic_vector(0 to 3);  -- v4bit
  Signal pcihip0_psl_tl_cfg_ctl: std_logic_vector(0 to 31);  -- v32bit
-- Apr13 Signal pcihip0_psl_tl_cfg_sts: std_logic_vector(0 to 52);  -- v53bit
  Signal pcihip0_psl_tx_cred_datafccp: std_logic_vector(0 to 11);  -- v12bit
  Signal pcihip0_psl_tx_cred_datafcnp: std_logic_vector(0 to 11);  -- v12bit
  Signal pcihip0_psl_tx_cred_datafcp: std_logic_vector(0 to 11);  -- v12bit
  Signal pcihip0_psl_tx_cred_fchipcons: std_logic_vector(0 to 5);  -- v6bit
  Signal pcihip0_psl_tx_cred_fcinfinite: std_logic_vector(0 to 5);  -- v6bit
  Signal pcihip0_psl_tx_cred_hdrfccp: std_logic_vector(0 to 7);  -- v8bit
  Signal pcihip0_psl_tx_cred_hdrfcnp: std_logic_vector(0 to 7);  -- v8bit
  Signal pcihip0_psl_tx_cred_hdrfcp: std_logic_vector(0 to 7);  -- v8bit
-- Apr13 Signal pcihip0_psl_tx_par_err: std_logic_vector(0 to 1);  -- v2bit
  Signal pcihip0_psl_tx_st_ready: std_logic;  -- bool
  Signal pfl_flash_grant: std_logic;  -- bool
  Signal pfl_flash_reqn: std_logic;  -- bool
  Signal psl_clk: std_logic;  -- bool
  Signal psl_clk_div2: std_logic;  -- bool
  Signal psl_pll_clk_125: std_logic;  -- bool

  Signal         sys_clk_p   :  std_logic ;
  Signal         sys_clk_n   : std_logic ;
  Signal         sys_rst_n   : std_logic ;
  Signal         pci_exp_txn : STD_LOGIC_VECTOR (7 downto 0 );
  Signal         pci_exp_txp : STD_LOGIC_VECTOR (7 downto 0 );
  Signal         pci_exp_rxn : STD_LOGIC_VECTOR (7 downto 0 );
  Signal         pci_exp_rxp : STD_LOGIC_VECTOR (7 downto 0 );

  Signal psl_pcihip0_app_msi_num: std_logic_vector(0 to 4);  -- v5bit
  Signal psl_pcihip0_app_msi_req: std_logic;  -- bool
  Signal psl_pcihip0_app_msi_tc: std_logic_vector(0 to 2);  -- v3bit
  Signal psl_pcihip0_cpl_err: std_logic_vector(0 to 6);  -- v7bit
  Signal psl_pcihip0_cpl_pending: std_logic;  -- bool
  Signal psl_pcihip0_cseb_rddata: std_logic_vector(0 to 31);  -- v32bit
  Signal cseb_rddata_parity: std_logic_vector(0 to 3);  -- v4bit
  Signal psl_pcihip0_cseb_rdresponse: std_logic_vector(0 to 4);  -- v5bit
  Signal psl_pcihip0_cseb_waitrequest: std_logic;  -- bool
  Signal psl_pcihip0_cseb_wrresp_valid: std_logic;  -- bool
  Signal psl_pcihip0_cseb_wrresponse: std_logic_vector(0 to 4);  -- v5bit
  Signal psl_pcihip0_cseb_rddata_parity: std_logic_vector(0 to 3);  -- v4bit
  Signal psl_pcihip0_cseb_rden_l: std_logic;  -- bool
-- Apr13 Signal psl_pcihip0_freeze: std_logic;  -- bool
  Signal psl_pcihip0_hip_reconfig_address: std_logic_vector(0 to 9);  -- v10bit
  Signal psl_pcihip0_hip_reconfig_byte_en: std_logic_vector(0 to 1);  -- v2bit
  Signal psl_pcihip0_hip_reconfig_clk: std_logic;  -- bool
  Signal psl_pcihip0_hip_reconfig_read: std_logic;  -- bool
  Signal psl_pcihip0_hip_reconfig_rst_n: std_logic;  -- bool
  Signal psl_pcihip0_hip_reconfig_write: std_logic;  -- bool
  Signal psl_pcihip0_hip_reconfig_writedata: std_logic_vector(0 to 15);  -- v16bit
  Signal psl_pcihip0_interface_sel: std_logic;  -- bool
  Signal psl_pcihip0_lmi_addr: std_logic_vector(0 to 11);  -- v12bit
  Signal psl_pcihip0_lmi_din: std_logic_vector(0 to 31);  -- v32bit
  Signal psl_pcihip0_lmi_rden: std_logic;  -- bool
  Signal psl_pcihip0_lmi_wren: std_logic;  -- bool
  Signal psl_pcihip0_nfreeze: std_logic;  -- bool
  Signal psl_pcihip0_pm_auxpwr: std_logic;  -- bool
  Signal psl_pcihip0_pm_data: std_logic_vector(0 to 9);  -- v10bit
  Signal psl_pcihip0_pm_event: std_logic;  -- bool
  Signal psl_pcihip0_pme_to_cr: std_logic;  -- bool
  Signal psl_pcihip0_rx_st_mask: std_logic;  -- bool
  Signal psl_pcihip0_rx_st_ready: std_logic;  -- bool
  Signal psl_pcihip0_ser_shift_load: std_logic;  -- bool
  Signal psl_pcihip0_simu_mode_pipe: std_logic;  -- bool
  Signal psl_pcihip0_test_in: std_logic_vector(0 to 31);  -- v32bit
  Signal psl_pcihip0_tx_st_data: std_logic_vector(0 to 255);  -- v256bit
  Signal psl_pcihip0_tx_st_empty: std_logic_vector(0 to 1);  -- v2bit
  Signal psl_pcihip0_tx_st_eop: std_logic;  -- bool
  Signal psl_pcihip0_tx_st_err: std_logic;  -- bool
  Signal psl_pcihip0_tx_st_parity: std_logic_vector(0 to 31);  -- v32bit
  Signal psl_pcihip0_tx_st_sop: std_logic;  -- bool
  Signal psl_pcihip0_tx_st_valid: std_logic;  -- bool
-- Apr13 Signal psl_pcihip_freeze: std_logic;  -- bool
  Signal rgb_led_pat: std_logic_vector(0 to 5);  -- v6bit
-- Apr13Signal crc_errorinternal: std_logic;  -- bool


  Signal d0h_dvalid: std_logic;
  Signal d0h_req_utag: std_logic_vector(0 to 9);
  Signal d0h_req_itag: std_logic_vector(0 to 8);
  Signal d0h_dtype: std_logic_vector(0 to 2);
--Signal d0h_drelaxed: std_logic;
  Signal d0h_datomic_op: std_logic_vector(0 to 5);
  Signal d0h_datomic_le: std_logic;
  Signal d0h_dsize: std_logic_vector(0 to 9);
  Signal d0h_ddata: std_logic_vector(0 to 1023);
-- Signal d0h_dpar: std_logic_vector(0 to 15);

  Signal hd0_cpl_valid: std_logic;
  Signal hd0_cpl_utag: std_logic_vector(0 to 9);
  Signal hd0_cpl_type: std_logic_vector(0 to 2);
-- Signal hd0_cpl_laddr_0_6: std_logic_vector(0 to 6)   ;
  Signal hd0_cpl_laddr: std_logic_vector(0 to 6)   ;
  Signal hd0_cpl_byte_count: std_logic_vector(0 to 9)   ;
  Signal hd0_cpl_size: std_logic_vector(0 to 9);
  Signal hd0_cpl_data: std_logic_vector(0 to 1023);
-- Signal hd0_cpl_dpar: std_logic_vector(0 to 15);
  Signal hd0_sent_utag_valid: std_logic;
  Signal hd0_sent_utag: std_logic_vector(0 to 9);
  Signal hd0_sent_utag_sts: std_logic_vector(0 to 2);

  Signal afp_xil_reset: std_logic;
  Signal afp_xil_packet_in_tdata: std_logic_vector(511 downto 0);
  Signal afp_xil_packet_in_tkeep: std_logic_vector(63 downto 0);
  Signal afp_xil_packet_in_tlast: std_logic;
  Signal afp_xil_packet_in_tvalid: std_logic;
  Signal xil_afp_valid: std_logic;
  Signal xil_afp_packet_type: std_logic_vector(7 downto 0);

-- Signal a0hm_cpagesize: std_logic_vector(0 to 3);

-- Signal a0hm_brdata: std_logic_vector(0 to 1023);  -- hline
-- Signal a0hm_brlat: std_logic_vector(0 to 3);  -- v4bit
-- Signal a0hm_brpar: std_logic_vector(0 to 15);  -- v8bit
-- Signal a0hm_cabt: std_logic_vector(0 to 2);  -- cabt
-- Signal a0hm_cch: std_logic_vector(0 to 15);  -- ctxhndl
-- Signal a0hm_cea: std_logic_vector(0 to 63);  -- ead
-- Signal a0hm_ceapar: std_logic;  -- bool
-- Signal a0hm_com: std_logic_vector(0 to 12);  -- apcmd
-- Signal a0hm_compar: std_logic;  -- bool
-- Apr13 Signal a0hm_cpad: std_logic_vector(0 to 2);  -- pade
-- Signal a0hm_csize: std_logic_vector(0 to 11);  -- v12bit
-- Signal a0hm_ctag: std_logic_vector(0 to 7);  -- acctag
-- Signal a0hm_ctagpar: std_logic;  -- bool
-- Signal a0hm_cvalid: std_logic;  -- bool
-- Signal a0hm_jcack: std_logic;  -- bool
-- Signal a0hm_jdone: std_logic;  -- bool
-- Signal a0hm_jerror: std_logic_vector(0 to 63);  -- v64bit
-- Signal a0hm_jrunning: std_logic;  -- bool
-- Signal a0hm_jyield: std_logic;  -- bool
-- Signal a0hm_mmack: std_logic;  -- bool
-- Signal a0hm_mmdata: std_logic_vector(0 to 63);  -- v64bit
-- Signal a0hm_mmdatapar: std_logic;  -- bool
-- Signal a0hm_paren: std_logic;  -- bool
-- Signal a0hm_tbreq: std_logic;  -- bool

-- Signal ha0m_brad: std_logic_vector(0 to 5);  -- v6bit
-- Signal ha0m_brtag: std_logic_vector(0 to 7);  -- acctag
-- Signal ha0m_brtagpar: std_logic;  -- bool
-- Signal ha0m_brvalid: std_logic;  -- bool
-- Signal ha0m_bwad: std_logic_vector(0 to 5);  -- v6bit
-- Signal ha0m_bwdata: std_logic_vector(0 to 511);  -- hline
-- Signal ha0m_bwpar: std_logic_vector(0 to 7);  -- v8bit
-- Signal ha0m_bwtag: std_logic_vector(0 to 7);  -- acctag
-- Signal ha0m_bwtagpar: std_logic;  -- bool
-- Signal ha0m_bwvalid: std_logic;  -- bool
-- Signal ha0m_croom: std_logic_vector(0 to 7);  -- v8bit
-- Signal ha0m_jcom: std_logic_vector(0 to 7);  -- jbcom
-- Signal ha0m_jcompar: std_logic;  -- bool
-- Signal ha0m_jea: std_logic_vector(0 to 63);  -- v64bit
-- Signal ha0m_jeapar: std_logic;  -- bool
-- Signal ha0m_jval: std_logic;  -- bool
-- Signal ha0m_mmad: std_logic_vector(0 to 23);  -- v24bit
-- Signal ha0m_mmadpar: std_logic;  -- bool
-- Signal ha0m_mmcfg: std_logic;  -- bool
-- Signal ha0m_mmdata: std_logic_vector(0 to 63);  -- v64bit
-- Signal ha0m_mmdatapar: std_logic;  -- bool
-- Signal ha0m_mmdw: std_logic;  -- bool
-- Signal ha0m_mmrnw: std_logic;  -- bool
-- Signal ha0m_mmval: std_logic;  -- bool
-- Signal ha0m_pclock: std_logic;  -- bool
-- Signal ha0m_rcachepos: std_logic_vector(0 to 12);  -- v13bit
-- Signal ha0m_rcachestate: std_logic_vector(0 to 1);  -- statespec
-- Signal ha0m_rcredits: std_logic_vector(0 to 8);  -- v9bit
-- Signal ha0m_response: std_logic_vector(0 to 7);  -- apresp
-- Signal ha0m_rtag: std_logic_vector(0 to 7);  -- acctag
-- Signal ha0m_rtagpar: std_logic;  -- bool
-- Signal ha0m_rvalid: std_logic;  -- bool
-- Signal ha0m_rdtag: std_logic_vector(0 to 10);
-- Signal ha0m_rdtagpar: std_logic;
-- Signal ha0m_response_ext: std_logic_vector(0 to 7);
-- Signal ha0m_rpagesize: std_logic_vector(0 to 3);
-- Signal ha0m_reoa: std_logic_vector(0 to 185); -- 173);

  Signal ha_lop: std_logic_vector(0 to 4);            -- LPC/Internal Cache Op code
  Signal ha_loppar: std_logic;                        -- Job address parity
  Signal ha_lsize: std_logic_vector(0 to 6);          -- Size/Secondary Op code
  Signal ha_ltag: std_logic_vector(0 to 11);          -- LPC Tag/Internal Cache Tag
  Signal ha_ltagpar: std_logic;                       -- LPC Tag/Internal Cache Tag parity
  Signal ah_ldone: std_logic;                        -- LPC/Internal Cache Op done
  Signal ah_ldtag: std_logic_vector(0 to 11);        -- ltag is done
  Signal ah_ldtagpar: std_logic;                     -- ldtag parity
  Signal ah_lroom: std_logic_vector(0 to 7);         -- LPC/Internal Cache Op AFU can handle

  Signal tieup: std_logic;

  Signal green_led_in: std_logic_vector(0 to 3);
  Signal red_led_in: std_logic_vector(0 to 3);

  signal        axis_cq_tvalid : std_logic;
  signal        axis_cq_tdata  : std_logic_vector(511 downto 0);
  signal        axis_cq_tready : std_logic;
  signal        axis_cq_tready_22 : std_logic_vector(0 downto 0);
  signal        axis_cq_tuser  : std_logic_vector(182 downto 0);
  signal        axis_cq_np_req : std_logic_vector(1 downto 0);
--         //XLX IP RC Interface                                                                                             
  signal        axis_rc_tvalid  : std_logic;
  signal        axis_rc_tdata   : std_logic_vector(511 downto 0);
  signal        axis_rc_tready  : std_logic;
-- signal        axis_rc_tready_22  : std_logic_vector(0 downto 0);
  signal        axis_rc_tready_22  : std_logic;
  signal        axis_rc_tuser   : std_logic_vector(160 downto 0);
--         //-----------------------------------------------------------------------------------------------------------------------
--         //XLX IP RQ Interface                                                                                                    
  signal        axis_rq_tvalid  : std_logic;
  signal        axis_rq_tdata   : std_logic_vector(511 downto 0);
  signal        axis_rq_tready  : std_logic_vector(3 downto 0);
  signal        axis_rq_tlast   : std_logic;
  signal        axis_rq_tuser   : std_logic_vector(136 downto 0);
  signal        axis_rq_tkeep   : std_logic_vector(15 downto 0);
--         //XLX IP CC Interface                                                                                                   
  signal        axis_cc_tvalid  : std_logic;
  signal        axis_cc_tdata   : std_logic_vector(511 downto 0);
  signal        axis_cc_tready  : std_logic_vector(3 downto 0);
  signal        axis_cc_tlast   : std_logic;
  signal        axis_cc_tuser   : std_logic_vector(80 downto 0);
  signal        axis_cc_tkeep   : std_logic_vector(15 downto 0);

  Signal pcihip0_psl_clk  : std_logic;
  Signal pcihip0_psl_rst  : std_logic;
  Signal user_lnk_up  : std_logic;
  
  Signal cfg_function_status : STD_LOGIC_VECTOR ( 15 downto 0 );
--signal debug_clk250 : std_logic;

  Signal xip_cfg_fc_sel_sig   : std_logic_vector(2 downto 0);
  Signal xip_cfg_fc_ph_sig    : std_logic_vector(7 downto 0);
  Signal xip_cfg_fc_pd_sig    : std_logic_vector(11 downto 0);
  Signal xip_cfg_fc_np_sig    : std_logic_vector(7 downto 0); 
  Signal cfg_dsn_sig  : std_logic_vector(63 downto 0);

  Signal sys_clk    : std_logic;
  Signal sys_clk_gt   : std_logic;
  Signal sys_rst_n_c   : std_logic;

  signal clk_wiz_2_locked : std_logic;
  
  signal efes32             : std_logic_vector(31 downto 0);
  signal one1             : std_logic;
  signal two2             : std_logic_vector(1 downto 0);


  signal psl_build_ver: std_logic_vector(0 to 31);


  Signal icap_clk: std_logic;  -- 125Mhz clock from PCIe refclk
  Signal icap_clk_ce: std_logic;  -- bool
  Signal icap_clk_ce_din: std_logic;  -- bool

  Signal cfg_ext_read_received : STD_LOGIC;
  Signal cfg_ext_write_received : STD_LOGIC;
  Signal cfg_ext_register_number : STD_LOGIC_VECTOR(9 DOWNTO 0);
  Signal cfg_ext_function_number : STD_LOGIC_VECTOR(7 DOWNTO 0);
  Signal cfg_ext_write_data : STD_LOGIC_VECTOR(31 DOWNTO 0);
  Signal cfg_ext_write_byte_enable : STD_LOGIC_VECTOR(3 DOWNTO 0);
  Signal cfg_ext_read_data : STD_LOGIC_VECTOR(31 DOWNTO 0);
  Signal cfg_ext_read_data_valid : STD_LOGIC;


  signal efes16:  std_logic_vector(0 to 15);
  signal efes64:  std_logic_vector(0 to 63);

  Signal gold_factory: std_logic;

  Signal led_red : std_logic_vector(3 downto 0);
  Signal led_green : std_logic_vector(3 downto 0);
  Signal led_blue : std_logic_vector(3 downto 0);

begin

  psl_build_ver   <= x"00006900";    -- March 22, 2017 With fixes and With Subsystem ID = x060f for capi_flash script

  a0h_brdata <= (others=>'0');
  a0h_brlat <=  (others=>'0');
  a0h_brpar  <= (others=>'1');



  a0:           psl_accel

    PORT MAP (

      ah_cvalid          => a0h_cvalid,  -- : out std_logic                  ; -- Command valid
      ah_ctag            => a0h_ctag,   -- : out std_logic_vector(0 to 7)   ; -- Command tag
      ah_ctagpar         => a0h_ctagpar,  -- : out std_logic                  ; -- Command tag parity
      ah_com             => a0h_com,   -- : out std_logic_vector(0 to 12)  ; -- Command code
      ah_compar          => a0h_compar,  -- : out std_logic                  ; -- Command code parity
      ah_cabt            => a0h_cabt,   -- : out std_logic_vector(0 to 2)   ; -- Command ABT
      ah_cea             => a0h_cea,   -- : out std_logic_vector(0 to 63)  ; -- Command address
      ah_ceapar          => a0h_ceapar,  -- : out std_logic                  ; -- Command address parity
      ah_cch             => a0h_cch,   -- : out std_logic_vector(0 to 15)  ; -- Command context handle
      ah_csize           => a0h_csize,   -- : out std_logic_vector(0 to 11)  ; -- Command size
      ah_cpagesize       => a0h_cpagesize,  -- : OUT std_logic_vector(0 to 3)   := (others => '0'); -- ** New tie to 0000
      ha_croom           => ha0_croom,   -- : in  std_logic_vector(0 to 7)   ; -- Command room
      -- Buffer interface
      ha_brvalid         => ha0_brvalid,  -- : in  std_logic                  ; -- Buffer Read valid
      ha_brtag           => ha0_brtag,   -- : in  std_logic_vector(0 to 7)   ; -- Buffer Read tag
      ha_brtagpar        => ha0_brtagpar,  -- : in  std_logic                  ; -- Buffer Read tag parity
      ha_brad            => ha0_brad,   -- : in  std_logic_vector(0 to 5)   ; -- Buffer Read address
--       ah_brlat           => a0h_brlat,   -- : out std_logic_vector(0 to 3)   ; -- Buffer Read latency
--       ah_brdata          => a0h_brdata,  -- : out std_logic_vector(0 to 1023); -- Buffer Read data
--       ah_brpar           => a0h_brpar,   -- : out std_logic_vector(0 to 15)  ; -- Buffer Read data parity
      ha_bwvalid         => ha0_bwvalid,  -- : in  std_logic                  ; -- Buffer Write valid
      ha_bwtag           => ha0_bwtag,   -- : in  std_logic_vector(0 to 7)   ; -- Buffer Write tag
      ha_bwtagpar        => ha0_bwtagpar,  -- : in  std_logic                  ; -- Buffer Write tag parity
      ha_bwad            => ha0_bwad,   -- : in  std_logic_vector(0 to 5)   ; -- Buffer Write address
      ha_bwdata          => ha0_bwdata,  -- : in  std_logic_vector(0 to 1023); -- Buffer Write data
      ha_bwpar           => ha0_bwpar,   -- : in  std_logic_vector(0 to 15)  ; -- Buffer Write data parity
      -- Response interface
      ha_rvalid          => ha0_rvalid,  -- : in  std_logic                  ; -- Response valid
      ha_rtag            => ha0_rtag,   -- : in  std_logic_vector(0 to 7)   ; -- Response tag
      ha_rtagpar         => ha0_rtagpar,  -- : in  std_logic                  ; -- Response tag parity
      ha_rditag          => ha0_rditag,  -- : IN  std_logic_vector(0 to 8);    -- **New DMA Translation Tag for xlat_* requests
      ha_rditagpar       => ha0_rditagpar,  -- : IN  std_logic;                   -- **New Parity bit for above
      ha_response        => ha0_response,  -- : in  std_logic_vector(0 to 7)   ; -- Response
      ha_response_ext    => ha0_response_ext,  -- : in  std_logic_vector(0 to 7)   ; -- **New Response Ext
      ha_rpagesize       => ha0_rpagesize,  -- : IN  std_logic_vector(0 to 3);    -- **New Command translated Page size.  Provided by PSL to allow
      ha_rcredits        => ha0_rcredits,  -- : in  std_logic_vector(0 to 8)   ; -- Response credits
      ha_rcachestate     => ha0_rcachestate,  -- : in  std_logic_vector(0 to 1)   ; -- Response cache state
      ha_rcachepos       => ha0_rcachepos,  -- : in  std_logic_vector(0 to 12)  ; -- Response cache pos
--        ha_reoa            => ha0_reoa,   -- : IN  std_logic_vector(0 to 185);  -- **New unknown width or use
      -- MMIO interface
      ha_mmval           => ha0_mmval,   -- : in  std_logic                  ; -- A valid MMIO is present
      ha_mmcfg           => ha0_mmcfg,   -- : in  std_logic                  ; -- afu descriptor space access
      ha_mmrnw           => ha0_mmrnw,   -- : in  std_logic                  ; -- 1 = read, 0 = write
      ha_mmdw            => ha0_mmdw,   -- : in  std_logic                  ; -- 1 = doubleword, 0 = word
      ha_mmad            => ha0_mmad,   -- : in  std_logic_vector(0 to 23)  ; -- mmio address
      ha_mmadpar         => ha0_mmadpar,  -- : in  std_logic                  ; -- mmio address parity
      ha_mmdata          => ha0_mmdata,  -- : in  std_logic_vector(0 to 63)  ; -- Write data
      ha_mmdatapar       => ha0_mmdatapar,  -- : in  std_logic                  ; -- mmio data parity
      ah_mmack           => a0h_mmack,   -- : out std_logic                  ; -- Write is complete or Read is valid
      ah_mmdata          => a0h_mmdata,  -- : out std_logic_vector(0 to 63)  ; -- Read data
      ah_mmdatapar       => a0h_mmdatapar,  -- : out std_logic                  ; -- mmio data parity
      -- Control interface
      ha_jval            => ha0_jval,   -- : in  std_logic                  ; -- Job valid
      ha_jcom            => ha0_jcom,   -- : in  std_logic_vector(0 to 7)   ; -- Job command
      ha_jcompar         => ha0_jcompar,  -- : in  std_logic                  ; -- Job command parity
      ha_jea             => ha0_jea,   -- : in  std_logic_vector(0 to 63)  ; -- Job address
      ha_jeapar          => ha0_jeapar,  -- : in  std_logic                  ; -- Job address parity
--     ha_lop             => ,    -- : in  std_logic_vector(0 to 4)   ; -- LPC/Internal Cache Op code
--     ha_loppar          => ,    -- : in  std_logic                  ; -- Job address parity
--     ha_lsize           => ,    -- : in  std_logic_vector(0 to 6)   ; -- Size/Secondary Op code
--     ha_ltag            => ,    -- : in  std_logic_vector(0 to 11)  ; -- LPC Tag/Internal Cache Tag
--     ha_ltagpar         => ,    -- : in  std_logic                  ; -- LPC Tag/Internal Cache Tag parity
      ah_jrunning        => a0h_jrunning,  -- : out std_logic                  ; -- Job running
      ah_jdone           => a0h_jdone,   -- : out std_logic                  ; -- Job done
      ah_jcack           => a0h_jcack,   -- : out std_logic                  ; -- completion of llcmd
      ah_jerror          => a0h_jerror,  -- : out std_logic_vector(0 to 63)  ; -- Job error
--     h_jyield          => a0h_jyield,  -- : out std_logic                  ; -- Job yield
--     ah_ldone           => ,    -- : out std_logic                  ; -- LPC/Internal Cache Op done
--     ah_ldtag           => ,    -- : out std_logic_vector(0 to 11)  ; -- ltag is done
--     ah_ldtagpar        => ,    -- : out std_logic                  ; -- ldtag parity
--     ah_lroom           => ,    -- : out std_logic_vector(0 to 7)   ; -- LPC/Internal Cache Op AFU can handle
      ah_tbreq           => a0h_tbreq,   -- : out std_logic                  ; -- Timebase command request
      ah_paren           => a0h_paren,   -- : out std_logic                  ; -- parity enable
      ha_pclock          => ha0_pclock,  -- : in  std_logic                  ;
-- New DMA0 Interface
-- DMA0 Req interface
      d0h_dvalid          => d0h_dvalid,  -- : OUT std_logic                   := '0';            -- New PSL/AFU interface
      d0h_req_utag        => d0h_req_utag,  -- : OUT std_logic_vector(0 to 9)    := (others => '0');-- New PSL/AFU interface
      d0h_req_itag        => d0h_req_itag,  -- : OUT std_logic_vector(0 to 8)    := (others => '0');-- New PSL/AFU interface
      d0h_dtype           => d0h_dtype,  -- : OUT std_logic_vector(0 to 2)    := (others => '0');-- New PSL/AFU interface
      d0h_dsize           => d0h_dsize,  -- : OUT std_logic_vector(0 to 9)    := (others => '0');-- New PSL/AFU interface
      d0h_ddata           => d0h_ddata,  -- : OUT std_logic_vector(0 to 1023) := (others => '0');-- New PSL/AFU interface
      d0h_datomic_op      => d0h_datomic_op,           -- : OUT std_logic_vector(0 to 5);   := (others => '0');-- New PSL/AFU interface
      d0h_datomic_le      => d0h_datomic_le,           -- : OUT std_logic                   := '0';
--        d0h_dpar            => d0h_dpar,  -- : OUT std_logic_vector(0 to 15)   := (others => '0');-- New PSL/AFU interface
-- DMA0 Sent interface
      hd0_sent_utag_valid => hd0_sent_utag_valid, -- : IN  std_logic                  ;
      hd0_sent_utag       => hd0_sent_utag,  -- : IN  std_logic_vector(0 to 9)   ;
      hd0_sent_utag_sts   => hd0_sent_utag_sts, -- : IN  std_logic_vector(0 to 2)   ;
-- DMA0 CPL interface
      hd0_cpl_valid       => hd0_cpl_valid,  -- : IN  std_logic                  ;
      hd0_cpl_utag        => hd0_cpl_utag,  -- : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_type        => hd0_cpl_type,  -- : IN  std_logic_vector(0 to 2)   ;
      hd0_cpl_size        => hd0_cpl_size,  -- : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_laddr       => hd0_cpl_laddr,            -- : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_byte_count  => hd0_cpl_byte_count,       -- : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_data        => hd0_cpl_data,  -- : IN  std_logic_vector(0 to 1023);


      led_red => led_red,
      led_green => led_green,
      led_blue => led_blue,

      ha_pclock_div2   =>    psl_clk_div2,
      pci_user_reset   =>    pcihip0_psl_rst,     
      gold_factory     => gold_factory, --set to one to indicate user image    

      pci_pi_nperst1 => pci_pi_nperst1,                                
      pci_pi_refclk_p1 => pci_pi_refclk_p1,       
      pci_pi_refclk_n1 => pci_pi_refclk_n1,                                       
      pci1_o_susclk => pci1_o_susclk,
      pci1_b_nclkreq => pci1_b_nclkreq,
      pci1_b_npewake => pci1_b_npewake,
      pci1_i_rxp_in0 => pci1_i_rxp_in0,
      pci1_i_rxn_in0 => pci1_i_rxn_in0,
      pci1_i_rxp_in1 => pci1_i_rxp_in1,
      pci1_i_rxn_in1 => pci1_i_rxn_in1,
      pci1_i_rxp_in2 => pci1_i_rxp_in2,
      pci1_i_rxn_in2 => pci1_i_rxn_in2,
      pci1_i_rxp_in3 => pci1_i_rxp_in3,
      pci1_i_rxn_in3 => pci1_i_rxn_in3,
      
      pci1_o_txp_out0 => pci1_o_txp_out0,
      pci1_o_txn_out0 => pci1_o_txn_out0,
      pci1_o_txp_out1 => pci1_o_txp_out1,
      pci1_o_txn_out1 => pci1_o_txn_out1,
      pci1_o_txp_out2 => pci1_o_txp_out2,
      pci1_o_txn_out2 => pci1_o_txn_out2,
      pci1_o_txp_out3 => pci1_o_txp_out3,
      pci1_o_txn_out3 => pci1_o_txn_out3,
      
      pci_pi_nperst2 => pci_pi_nperst2,                                
      pci_pi_refclk_p2 => pci_pi_refclk_p2,       
      pci_pi_refclk_n2 => pci_pi_refclk_n2,                                       
      pci2_o_susclk => pci2_o_susclk,
      pci2_b_nclkreq => pci2_b_nclkreq,
      pci2_b_npewake => pci2_b_npewake,
      pci2_i_rxp_in0 => pci2_i_rxp_in0,
      pci2_i_rxn_in0 => pci2_i_rxn_in0,
      pci2_i_rxp_in1 => pci2_i_rxp_in1,
      pci2_i_rxn_in1 => pci2_i_rxn_in1,
      pci2_i_rxp_in2 => pci2_i_rxp_in2,
      pci2_i_rxn_in2 => pci2_i_rxn_in2,
      pci2_i_rxp_in3 => pci2_i_rxp_in3,
      pci2_i_rxn_in3 => pci2_i_rxn_in3,
      
      pci2_o_txp_out0 => pci2_o_txp_out0,
      pci2_o_txn_out0 => pci2_o_txn_out0,
      pci2_o_txp_out1 => pci2_o_txp_out1,
      pci2_o_txn_out1 => pci2_o_txn_out1,
      pci2_o_txp_out2 => pci2_o_txp_out2,
      pci2_o_txn_out2 => pci2_o_txn_out2,
      pci2_o_txp_out3 => pci2_o_txp_out3,
      pci2_o_txn_out3 => pci2_o_txn_out3,
      
      pci_pi_nperst3 => pci_pi_nperst3,                                
      pci_pi_refclk_p3 => pci_pi_refclk_p3,       
      pci_pi_refclk_n3 => pci_pi_refclk_n3,                                       
      pci3_o_susclk => pci3_o_susclk,
      pci3_b_nclkreq => pci3_b_nclkreq,
      pci3_b_npewake => pci3_b_npewake,
      pci3_i_rxp_in0 => pci3_i_rxp_in0,
      pci3_i_rxn_in0 => pci3_i_rxn_in0,
      pci3_i_rxp_in1 => pci3_i_rxp_in1,
      pci3_i_rxn_in1 => pci3_i_rxn_in1,
      pci3_i_rxp_in2 => pci3_i_rxp_in2,
      pci3_i_rxn_in2 => pci3_i_rxn_in2,
      pci3_i_rxp_in3 => pci3_i_rxp_in3,
      pci3_i_rxn_in3 => pci3_i_rxn_in3,
      
      pci3_o_txp_out0 => pci3_o_txp_out0,
      pci3_o_txn_out0 => pci3_o_txn_out0,
      pci3_o_txp_out1 => pci3_o_txp_out1,
      pci3_o_txn_out1 => pci3_o_txn_out1,
      pci3_o_txp_out2 => pci3_o_txp_out2,
      pci3_o_txn_out2 => pci3_o_txn_out2,
      pci3_o_txp_out3 => pci3_o_txp_out3,
      pci3_o_txn_out3 => pci3_o_txn_out3,
      
      pci_pi_nperst4 => pci_pi_nperst4,                                
      pci_pi_refclk_p4 => pci_pi_refclk_p4,       
      pci_pi_refclk_n4 => pci_pi_refclk_n4,                                       
      pci4_o_susclk => pci4_o_susclk,
      pci4_b_nclkreq => pci4_b_nclkreq,
      pci4_b_npewake => pci4_b_npewake,
      pci4_i_rxp_in0 => pci4_i_rxp_in0,
      pci4_i_rxn_in0 => pci4_i_rxn_in0,
      pci4_i_rxp_in1 => pci4_i_rxp_in1,
      pci4_i_rxn_in1 => pci4_i_rxn_in1,
      pci4_i_rxp_in2 => pci4_i_rxp_in2,
      pci4_i_rxn_in2 => pci4_i_rxn_in2,
      pci4_i_rxp_in3 => pci4_i_rxp_in3,
      pci4_i_rxn_in3 => pci4_i_rxn_in3,
      
      pci4_o_txp_out0 => pci4_o_txp_out0,
      pci4_o_txn_out0 => pci4_o_txn_out0,
      pci4_o_txp_out1 => pci4_o_txp_out1,
      pci4_o_txn_out1 => pci4_o_txn_out1,
      pci4_o_txp_out2 => pci4_o_txp_out2,
      pci4_o_txn_out2 => pci4_o_txn_out2,
      pci4_o_txp_out3 => pci4_o_txp_out3,
      pci4_o_txn_out3 => pci4_o_txn_out3
      


      );


  -- PSL logic
  p:            PSL9_WRAP_0
    PORT MAP (
      a0h_cvalid => a0h_cvalid,
      a0h_ctag => a0h_ctag,
      a0h_com => a0h_com,
      a0h_cabt => a0h_cabt,
      a0h_cea => a0h_cea,
      a0h_cch => a0h_cch,
      a0h_csize => a0h_csize,
      a0h_cpagesize => a0h_cpagesize,
      ha0_croom => ha0_croom,
      a0h_ctagpar => a0h_ctagpar,
      a0h_compar => a0h_compar,
      a0h_ceapar => a0h_ceapar,
      ha0_brvalid => ha0_brvalid,
      ha0_brtag => ha0_brtag,
      ha0_brad => ha0_brad,
      a0h_brlat => a0h_brlat,
      a0h_brdata => a0h_brdata,
      a0h_brpar => a0h_brpar,
      ha0_bwvalid => ha0_bwvalid,
      ha0_bwtag => ha0_bwtag,
      ha0_bwad => ha0_bwad,
      ha0_bwdata => ha0_bwdata,
      ha0_bwpar => ha0_bwpar,
      ha0_brtagpar => ha0_brtagpar,
      ha0_bwtagpar => ha0_bwtagpar,
      ha0_rcredits => ha0_rcredits,

      ha0_response_ext => ha0_response_ext,
      ha0_rditag => ha0_rditag,
      ha0_rditagpar => ha0_rditagpar,
      ha0_rpagesize => ha0_rpagesize,

      ha0_rvalid => ha0_rvalid,
      ha0_rtag => ha0_rtag,
      ha0_response => ha0_response,
      ha0_rcachestate => ha0_rcachestate,
      ha0_rcachepos => ha0_rcachepos,
      ha0_rtagpar => ha0_rtagpar,
      ha0_reoa => ha0_reoa,

      ha0_mmval => ha0_mmval,
      ha0_mmrnw => ha0_mmrnw,
      ha0_mmdw => ha0_mmdw,
      ha0_mmad => ha0_mmad,
      ha0_mmdata => ha0_mmdata,
      ha0_mmcfg => ha0_mmcfg,
      a0h_mmack => a0h_mmack,
      a0h_mmdata => a0h_mmdata,
      ha0_mmadpar => ha0_mmadpar,
      ha0_mmdatapar => ha0_mmdatapar,
      a0h_mmdatapar => a0h_mmdatapar,

      ha0_jval => ha0_jval,
      ha0_jcom => ha0_jcom,
      ha0_jea => ha0_jea,
      a0h_jrunning => a0h_jrunning,
      a0h_jdone => a0h_jdone,
      a0h_jcack => a0h_jcack,
      a0h_jerror => a0h_jerror,
      a0h_tbreq => a0h_tbreq,
--          a0h_jyield => a0h_jyield,
      ha0_jeapar => ha0_jeapar,
      ha0_jcompar => ha0_jcompar,
      a0h_paren => a0h_paren,
      ha0_pclock => ha0_pclock,

      D0H_DVALID => d0h_dvalid,
      D0H_REQ_UTAG => d0h_req_utag,
      D0H_REQ_ITAG => d0h_req_itag,
      D0H_DTYPE => d0h_dtype,
      D0H_DATOMIC_OP => d0h_datomic_op,
      D0H_DATOMIC_LE => d0h_datomic_le,
--        DH_DRELAXED => d0h_drelaxed,
      D0H_DSIZE => d0h_dsize,
      D0H_DDATA => d0h_ddata,
--         D0H_DPAR => d0h_dpar,

      HD0_CPL_VALID => hd0_cpl_valid,
      HD0_CPL_UTAG => hd0_cpl_utag,
      HD0_CPL_TYPE => hd0_cpl_type,
      HD0_CPL_LADDR => hd0_cpl_laddr,
      HD0_CPL_BYTE_COUNT => hd0_cpl_byte_count,
      HD0_CPL_SIZE => hd0_cpl_size,
      HD0_CPL_DATA => hd0_cpl_data,
--         HD0_CPL_DPAR => hd0_cpl_dpar,
--
      HD0_SENT_UTAG_VALID => hd0_sent_utag_valid,
      HD0_SENT_UTAG => hd0_sent_utag,
      HD0_SENT_UTAG_STS => hd0_sent_utag_sts,




      AXIS_CQ_TVALID  => axis_cq_tvalid,
      AXIS_CQ_TDATA   => axis_cq_tdata,
      AXIS_CQ_TREADY  => axis_cq_tready,
      AXIS_CQ_TUSER   => axis_cq_tuser,
      AXIS_CQ_NP_REQ  => axis_cq_np_req,
--         //XLX IP RC Interface                                                                                             
      AXIS_RC_TVALID  => axis_rc_tvalid,
      AXIS_RC_TDATA   => axis_rc_tdata,
      AXIS_RC_TREADY  => axis_rc_tready,
      AXIS_RC_TUSER   => axis_rc_tuser,
--         //-----------------------------------------------------------------------------------------------------------------------
--         //XLX IP RQ Interface                                                                                                    
      AXIS_RQ_TVALID  => axis_rq_tvalid,
      AXIS_RQ_TDATA   => axis_rq_tdata,
      AXIS_RQ_TREADY  => axis_rq_tready(0),
      AXIS_RQ_TLAST   => axis_rq_tlast,
      AXIS_RQ_TUSER   => axis_rq_tuser,
      AXIS_RQ_TKEEP   => axis_rq_tkeep,
--         //XLX IP CC Interface                                                                                                   
      AXIS_CC_TVALID  => axis_cc_tvalid,
      AXIS_CC_TDATA   => axis_cc_tdata,
      AXIS_CC_TREADY  => axis_cc_tready(0),
      AXIS_CC_TLAST   => axis_cc_tlast,
      AXIS_CC_TUSER   => axis_cc_tuser,
      AXIS_CC_TKEEP   => axis_cc_tkeep,
--         //----------------------------------------------------------------------------------------------------------------------
--         // Configuration Interface
--         // cfg_fc_sel[2:0] = 101b, cfg_fc_ph[7:0], cfg_fc_pd[11:0] cfg_fc_nph[7:0]
      XIP_CFG_FC_SEL  => xip_cfg_fc_sel_sig,
      XIP_CFG_FC_PH   => xip_cfg_fc_ph_sig,
      XIP_CFG_FC_PD   => xip_cfg_fc_pd_sig,
      XIP_CFG_FC_NP   => xip_cfg_fc_np_sig,
      
      psl_kill_link  => open,
      psl_build_ver   => psl_build_ver,
      afu_clk         => psl_clk,         

      -- PSL_RST and PCIHIP_PSL_RST must both be asserted if one is asserted
      -- If only 1 is asserted, async fifo gets into invalid state
      PSL_RST         => pcihip0_psl_rst,
      PSL_CLK         => psl_clk,
      PCIHIP_PSL_RST  => pcihip0_psl_rst,
      PCIHIP_PSL_CLK  => pcihip0_psl_clk

      );

  cfg_dsn_sig <= x"00000001" & x"01" & x"000A35";

  efes32   <= x"00000000";
  one1   <= '1';
  two2   <= one1 & one1;

  sys_clk_p   <= pci_pi_refclk_p0 ;
  sys_clk_n   <= pci_pi_refclk_n0;
  sys_rst_n   <= pci_pi_nperst0;
  pci0_o_txn_out0 <= pci_exp_txn(0);
  pci0_o_txp_out0 <= pci_exp_txp(0);
  pci_exp_rxn(0) <= pci0_i_rxp_in0;
  pci_exp_rxp(0) <= pci0_i_rxn_in0;
  pci0_o_txn_out1 <= pci_exp_txn(1);
  pci0_o_txp_out1 <= pci_exp_txp(1);
  pci_exp_rxn(1) <= pci0_i_rxp_in1;
  pci_exp_rxp(1) <= pci0_i_rxn_in1;
  pci0_o_txn_out2 <= pci_exp_txn(2);
  pci0_o_txp_out2 <= pci_exp_txp(2);
  pci_exp_rxn(2) <= pci0_i_rxp_in2;
  pci_exp_rxp(2) <= pci0_i_rxn_in2;
  pci0_o_txn_out3 <= pci_exp_txn(3);
  pci0_o_txp_out3 <= pci_exp_txp(3);
  pci_exp_rxn(3) <= pci0_i_rxp_in3;
  pci_exp_rxp(3) <= pci0_i_rxn_in3;
  pci0_o_txn_out4 <= pci_exp_txn(4);
  pci0_o_txp_out4 <= pci_exp_txp(4);
  pci_exp_rxn(4) <= pci0_i_rxp_in4;
  pci_exp_rxp(4) <= pci0_i_rxn_in4;
  pci0_o_txn_out5 <= pci_exp_txn(5);
  pci0_o_txp_out5 <= pci_exp_txp(5);
  pci_exp_rxn(5) <= pci0_i_rxp_in5;
  pci_exp_rxp(5) <= pci0_i_rxn_in5;
  pci0_o_txn_out6 <= pci_exp_txn(6);
  pci0_o_txp_out6 <= pci_exp_txp(6);
  pci_exp_rxn(6) <= pci0_i_rxp_in6;
  pci_exp_rxp(6) <= pci0_i_rxn_in6;
  pci0_o_txn_out7 <= pci_exp_txn(7);
  pci0_o_txp_out7 <= pci_exp_txp(7);
  pci_exp_rxn(7) <= pci0_i_rxp_in7;
  pci_exp_rxp(7) <= pci0_i_rxn_in7;


  pcihip0:      pcie4_uscale_plus_0
    PORT MAP (
      pci_exp_txn =>  pci_exp_txn ,   -- out STD_LOGIC_VECTOR ( 15 downto 0 );
      pci_exp_txp =>  pci_exp_txp ,   -- out STD_LOGIC_VECTOR ( 15 downto 0 );
      pci_exp_rxn =>  pci_exp_rxn ,   -- in STD_LOGIC_VECTOR ( 15 downto 0 );
      pci_exp_rxp =>  pci_exp_rxp ,   -- in STD_LOGIC_VECTOR ( 15 downto 0 );

      user_clk  => pcihip0_psl_clk,     -- out STD_LOGIC;
      user_reset  => pcihip0_psl_rst,     -- out STD_LOGIC;
      user_lnk_up => user_lnk_up,      -- out STD_LOGIC;

      s_axis_rq_tdata => axis_rq_tdata,     -- in  STD_LOGIC_VECTOR ( 511 downto 0 );
      s_axis_rq_tkeep => axis_rq_tkeep,     -- in  STD_LOGIC_VECTOR ( 15 downto 0 );
      s_axis_rq_tlast => axis_rq_tlast,     -- in  STD_LOGIC;
      s_axis_rq_tready => axis_rq_tready,   -- out STD_LOGIC_VECTOR ( 3 downto 0 );
      s_axis_rq_tuser => axis_rq_tuser,     -- in  STD_LOGIC_VECTOR ( 136 downto 0 );
      s_axis_rq_tvalid => axis_rq_tvalid,   -- in  STD_LOGIC;
      m_axis_rc_tdata => axis_rc_tdata,     -- out STD_LOGIC_VECTOR ( 511 downto 0 );
      m_axis_rc_tkeep => open,      -- out STD_LOGIC_VECTOR ( 15 downto 0 );
      m_axis_rc_tlast => open,      -- out STD_LOGIC;
      m_axis_rc_tready(0) => axis_rc_tready,  -- axis_rc_tready,    -- in  STD_LOGIC_VECTOR ( 21 downto 0 );
      m_axis_rc_tuser => axis_rc_tuser,     -- out STD_LOGIC_VECTOR ( 160 downto 0 );
      m_axis_rc_tvalid => axis_rc_tvalid,   -- out STD_LOGIC;
      m_axis_cq_tdata => axis_cq_tdata,     -- out STD_LOGIC_VECTOR ( 511 downto 0 );
      m_axis_cq_tkeep => open,      -- out STD_LOGIC_VECTOR ( 15 downto 0 );
      m_axis_cq_tlast => open,      -- out STD_LOGIC;
      m_axis_cq_tready(0) => axis_cq_tready,  -- axis_cq_tready,    -- in  STD_LOGIC_VECTOR ( 21 downto 0 );
      m_axis_cq_tuser => axis_cq_tuser,     -- out STD_LOGIC_VECTOR ( 182 downto 0 );
      m_axis_cq_tvalid => axis_cq_tvalid,    -- out STD_LOGIC;
      s_axis_cc_tdata => axis_cc_tdata,     -- in  STD_LOGIC_VECTOR ( 511 downto 0 );
      s_axis_cc_tkeep => axis_cc_tkeep,     -- in  STD_LOGIC_VECTOR ( 15 downto 0 );
      s_axis_cc_tlast => axis_cc_tlast,     -- in  STD_LOGIC;
      s_axis_cc_tready => axis_cc_tready,    -- out STD_LOGIC_VECTOR ( 3 downto 0 );
      s_axis_cc_tuser => axis_cc_tuser,     -- in  STD_LOGIC_VECTOR ( 80 downto 0 );
      s_axis_cc_tvalid => axis_cc_tvalid,    -- in  STD_LOGIC;

      pcie_rq_seq_num0 => open,      -- out STD_LOGIC_VECTOR ( 5 downto 0 );
      pcie_rq_seq_num_vld0 => open,     -- out STD_LOGIC;
      pcie_rq_seq_num1 => open,      -- out STD_LOGIC_VECTOR ( 5 downto 0 );
      pcie_rq_seq_num_vld1 => open,     -- out STD_LOGIC;
      pcie_rq_tag0 => open,      -- out STD_LOGIC_VECTOR ( 7 downto 0 );
      pcie_rq_tag1 => open,      -- out STD_LOGIC_VECTOR ( 7 downto 0 );
      pcie_rq_tag_av => open,      -- out STD_LOGIC_VECTOR ( 3 downto 0 );
      pcie_rq_tag_vld0 => open,      -- out STD_LOGIC;
      pcie_rq_tag_vld1 => open,      -- out STD_LOGIC;
      pcie_tfc_nph_av => open,      -- out STD_LOGIC_VECTOR ( 3 downto 0 );
      pcie_tfc_npd_av => open,      -- out STD_LOGIC_VECTOR ( 3 downto 0 );
      pcie_cq_np_req => two2,    -- in  STD_LOGIC_VECTOR ( 1 downto 0 );     -- Jan 27, 2017
      pcie_cq_np_req_count => open,     -- out STD_LOGIC_VECTOR ( 5 downto 0 );

      cfg_phy_link_down => open,     -- out STD_LOGIC;
      cfg_phy_link_status => open,     -- out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_negotiated_width => open,     -- out STD_LOGIC_VECTOR ( 2 downto 0 );
      cfg_current_speed => open,     -- out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_max_payload => open,      -- out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_max_read_req => open,      -- out STD_LOGIC_VECTOR ( 2 downto 0 );
      cfg_function_status => cfg_function_status,     -- out STD_LOGIC_VECTOR ( 15 downto 0 );
      cfg_function_power_state => open,     -- out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_vf_status => open,      -- out STD_LOGIC_VECTOR ( 503 downto 0 );
      cfg_vf_power_state => open,     -- out STD_LOGIC_VECTOR ( 755 downto 0 );
      cfg_link_power_state => open,     -- out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_mgmt_addr => efes32(9 downto 0),--(others => '0'),     -- in  STD_LOGIC_VECTOR ( 9 downto 0 );
      cfg_mgmt_function_number => efes32(7 downto 0),--(others => '0'),   -- in  STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_mgmt_write =>  '0',      -- in  STD_LOGIC;
      cfg_mgmt_write_data => efes32,    --(others => '0'),    -- in  STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_mgmt_byte_enable => efes32(3 downto 0),    -- (others => '0'),    -- in  STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_mgmt_read => '0',      -- in  STD_LOGIC;
      cfg_mgmt_read_data => open,     -- out STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_mgmt_read_write_done => open,     -- out STD_LOGIC;
      cfg_mgmt_debug_access => '0',     -- in  STD_LOGIC;
      cfg_err_cor_out => open,      -- out STD_LOGIC;
      cfg_err_nonfatal_out => open,     -- out STD_LOGIC;
      cfg_err_fatal_out => open,     -- out STD_LOGIC;
      cfg_local_error_valid => open,     -- out STD_LOGIC;
--     cfg_ltr_enable => open,     -- out STD_LOGIC;
      cfg_local_error_out => open,     -- out STD_LOGIC_VECTOR ( 4 downto 0 );
      cfg_ltssm_state => open,      -- out STD_LOGIC_VECTOR ( 5 downto 0 );
      cfg_rx_pm_state => open,      -- out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_tx_pm_state => open,      -- out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_rcb_status => open,       -- out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_obff_enable => open,       -- out STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_pl_status_change => open,      -- out STD_LOGIC;
      cfg_tph_requester_enable => open,     -- out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_tph_st_mode => open,       -- out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_vf_tph_requester_enable => open,     -- out STD_LOGIC_VECTOR ( 251 downto 0 );
      cfg_vf_tph_st_mode => open,      -- out STD_LOGIC_VECTOR ( 755 downto 0 );
      cfg_msg_received => open,      -- out STD_LOGIC;
      cfg_msg_received_data => open,      -- out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_msg_received_type => open,      -- out STD_LOGIC_VECTOR ( 4 downto 0 );
      cfg_msg_transmit => '0',       -- in  STD_LOGIC;
      cfg_msg_transmit_type => efes32(2 downto 0),    -- (others => '0'),    -- in  STD_LOGIC_VECTOR ( 2 downto 0 );
      cfg_msg_transmit_data => efes32, --(others => '0'),    -- in  STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_msg_transmit_done => open,      -- out STD_LOGIC;
      cfg_fc_ph => xip_cfg_fc_ph_sig,      -- out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_fc_pd => xip_cfg_fc_pd_sig,      -- out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_fc_nph => xip_cfg_fc_np_sig,      -- out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_fc_npd => open,       -- out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_fc_cplh => open,       -- out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_fc_cpld => open,       -- out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_fc_sel => xip_cfg_fc_sel_sig,     -- in  STD_LOGIC_VECTOR ( 2 downto 0 );
--     cfg_dsn => (others => '0'),      -- in  STD_LOGIC_VECTOR ( 63 downto 0 );
      cfg_dsn => cfg_dsn_sig,       -- in  STD_LOGIC_VECTOR ( 63 downto 0 );
      cfg_bus_number => open,       -- out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_power_state_change_ack => '0',     -- in  STD_LOGIC;
      cfg_power_state_change_interrupt => open,    -- out STD_LOGIC;
      cfg_err_cor_in => '0',       -- in  STD_LOGIC;
      cfg_err_uncor_in => '0',       -- in  STD_LOGIC;
      cfg_flr_in_process => open,      -- out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_flr_done => (others => '0'),      -- in  STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_vf_flr_in_process => open,      -- out STD_LOGIC_VECTOR ( 251 downto 0 );
      cfg_vf_flr_func_num => (others => '0'),      -- in  STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_vf_flr_done => (others => '0'),       -- in  STD_LOGIC_VECTOR ( 0 to 0 );
--     cfg_link_training_enable => '0',       -- in  STD_LOGIC;
      cfg_link_training_enable => '1',       -- in  STD_LOGIC;
      cfg_ext_read_received => cfg_ext_read_received,     -- out STD_LOGIC;
      cfg_ext_write_received => cfg_ext_write_received,   -- out STD_LOGIC;
      cfg_ext_register_number => cfg_ext_register_number, -- out STD_LOGIC_VECTOR ( 9 downto 0 );
      cfg_ext_function_number => cfg_ext_function_number,       -- out STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_ext_write_data => cfg_ext_write_data,      -- out STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_ext_write_byte_enable => cfg_ext_write_byte_enable,     -- out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_ext_read_data => cfg_ext_read_data,      -- in  STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_ext_read_data_valid => cfg_ext_read_data_valid,  -- in  STD_LOGIC;
      cfg_interrupt_int => efes32(3 downto 0),      -- in  STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_interrupt_pending => efes32(3 downto 0),    -- in  STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_interrupt_sent => open,        -- out STD_LOGIC;


      cfg_interrupt_msi_enable => open,       -- : out STD_LOGIC_VECTOR ( 3 downto 0 );
      cfg_interrupt_msi_mmenable => open,       -- : out STD_LOGIC_VECTOR ( 11 downto 0 );
      cfg_interrupt_msi_mask_update => open,       -- : out STD_LOGIC;
      cfg_interrupt_msi_data => open,         -- : out STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_interrupt_msi_select => (others => '0'),        -- : in STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_interrupt_msi_int => (others => '0'),        -- : in STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_interrupt_msi_pending_status => (others => '0'),       -- : in STD_LOGIC_VECTOR ( 31 downto 0 );
      cfg_interrupt_msi_pending_status_data_enable => '0',     -- : in STD_LOGIC;
      cfg_interrupt_msi_pending_status_function_num => (others => '0'),   -- : in STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_interrupt_msi_sent => open,         -- : out STD_LOGIC;
      cfg_interrupt_msi_fail => open,         -- : out STD_LOGIC;
      cfg_interrupt_msi_attr => (others => '0'),        -- : in STD_LOGIC_VECTOR ( 2 downto 0 );
      cfg_interrupt_msi_tph_present => '0',       -- : in STD_LOGIC;
      cfg_interrupt_msi_tph_type => (others => '0'),        -- : in STD_LOGIC_VECTOR ( 1 downto 0 );
      cfg_interrupt_msi_tph_st_tag => (others => '0'),       -- : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_interrupt_msi_function_number => (others => '0'),       -- : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_pm_aspm_l1_entry_reject => '0',       -- : in STD_LOGIC;
      cfg_pm_aspm_tx_l0s_entry_disable => '1',       -- : in STD_LOGIC;
      cfg_hot_reset_out => open,         -- : out STD_LOGIC;
      cfg_config_space_enable => '1',        -- : in STD_LOGIC;
      cfg_req_pm_transition_l23_ready => '0',       -- : in STD_LOGIC;
      cfg_hot_reset_in => '0',         -- : in STD_LOGIC;
      cfg_ds_port_number => (others => '0'),         -- : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_ds_bus_number => (others => '0'),         -- : in STD_LOGIC_VECTOR ( 7 downto 0 );
      cfg_ds_device_number => (others => '0'),        -- : in STD_LOGIC_VECTOR ( 4 downto 0 );

      sys_clk => sys_clk,         -- in  STD_LOGIC;
      sys_clk_gt => sys_clk_gt,        -- in  STD_LOGIC;
      sys_reset =>  sys_rst_n_c,  -- in  STD_LOGIC
      
      phy_rdy_out => open 
       
      ); 


  OBUF_LED_0 : OBUF
    port map (
      O => o_led_red(0), -- 1-bit output: Buffer output (connect directly to top-level port)
      I => led_red(0) -- 1-bit input: Buffer input
      );

  OBUF_LED_1 : OBUF
    port map (
      O => o_led_red(1), -- 1-bit output: Buffer output (connect directly to top-level port)
      I => led_red(1) -- 1-bit input: Buffer input
      );

  OBUF_LED_2 : OBUF
    port map (
      O => o_led_green(0), -- 1-bit output: Buffer output (connect directly to top-level port)
      I => led_green(0)  -- 1-bit input: Buffer input
      );

  OBUF_LED_3 : OBUF
    port map (
      O => o_led_green(1), -- 1-bit output: Buffer output (connect directly to top-level port)
      I => led_green(1)  -- 1-bit input: Buffer input
      );

  OBUF_LED_4 : OBUF
    port map (
      O => o_led_blue(0), -- 1-bit output: Buffer output (connect directly to top-level port)
      I => led_blue(0) -- 1-bit input: Buffer input
      );

  OBUF_LED_5 : OBUF
    port map (
      O => o_led_blue(1), -- 1-bit output: Buffer output (connect directly to top-level port)
      I => led_blue(1) -- 1-bit input: Buffer input
      );


  hdk_inst : psl_hdk_wrap
    PORT map (
      cfg_ext_read_received       => cfg_ext_read_received,
      cfg_ext_write_received      => cfg_ext_write_received,
      cfg_ext_register_number     => cfg_ext_register_number,
      cfg_ext_function_number     => cfg_ext_function_number,
      cfg_ext_write_data          => cfg_ext_write_data,
      cfg_ext_write_byte_enable   => cfg_ext_write_byte_enable,
      cfg_ext_read_data           => cfg_ext_read_data,
      cfg_ext_read_data_valid     => cfg_ext_read_data_valid,
      
      o_flash_oen                 => o_flash_oen,
      o_flash_wen                 => o_flash_wen,
      o_flash_rstn                => o_flash_rstn,
      o_flash_a                   => o_flash_a,
      o_flash_advn                => o_flash_advn,
      b_flash_dq                  => b_flash_dq,

      pci_pi_nperst0              => sys_rst_n_c,
      user_lnk_up                 => user_lnk_up,
      pcihip0_psl_clk             => pcihip0_psl_clk,
      icap_clk                    => icap_clk,
      cpld_usergolden             => gold_factory,
      crc_error                   => crc_error,
      b_basei2c_scl               => b_basei2c_scl,
      b_basei2c_sda               => b_basei2c_sda,        
      b_smbus_scl                 => b_smbus_scl,
      b_smbus_sda                 => b_smbus_sda,
      i_fpga_smbus_en_n           => i_fpga_smbus_en_n     
      );      


-- Xilinx component which is required to generate correct clocks towards PCIHIP
  refclk_ibuf : IBUFDS_GTE4
-- generic map (
-- REFCLK_EN_TX_PATH  => '0',  -- Refer to Transceiver User Guide
-- REFCLK_HROW_CK_SEL  => "00",  -- Refer to Transceiver User Guide
-- REFCLK_ICNTL_RX  => "00"  -- Refer to Transceiver User Guide
-- )
    port map (
      O   => sys_clk_gt,   -- 1-bit output: Refer to Transceiver User Guide
      ODIV2  => sys_clk,   -- 1-bit output: Refer to Transceiver User Guide
      CEB   => '0',        -- 1-bit input: Refer to Transceiver User Guide
      I   => sys_clk_p,   -- 1-bit input: Refer to Transceiver User Guide
      IB   => sys_clk_n   -- 1-bit input: Refer to Transceiver User Guide
      );
-- End of IBUFDS_GTE4_inst instantiation


  IBUF_inst : IBUF
    port map (
      O => sys_rst_n_c,  -- 1-bit output: Buffer output
      I => sys_rst_n   -- 1-bit input: Buffer input
      );


--        gate icap_clk until clocks are stable after link up
--        avoid glitches to sem core to prevent false errors or worse
--        also used to clock multiboot logic so keep enabled when link goes down
  icap_clk_ce_din <= icap_clk_ce or (not(pcihip0_psl_rst) and user_lnk_up and clk_wiz_2_locked);
  process (pcihip0_psl_clk)
  begin
    if pcihip0_psl_clk'event and pcihip0_psl_clk = '1' then
      icap_clk_ce  <= icap_clk_ce_din;
    end if;
  end process;

-- MMCM to generate PSL clock (100...250MHz)
  pll0:         flashgtp_clk_wiz
    PORT MAP  ( 
      clk_in1  => pcihip0_psl_clk, -- Driven by PCIHIP
      clk_out1  => psl_clk,   -- Goes to PSL logic
      clk_out2    => psl_clk_div2, -- Goes to PSL logic
      clk_out3  => icap_clk,     -- Goes to SEM, multiboot
      clk_out3_ce => icap_clk_ce,     -- gate off while unstable to prevent SEM errors
      -- reset was pcihip0_psl_rst.  this killed the clock to icap before a reconfig could complete
      reset   => '0',
      locked   => clk_wiz_2_locked
      );


--debug_clk: clk_wiz_quad_freerun0
--PORT MAP ( 
--              clk_out1  => debug_clk250,              --   : out   STD_LOGIC;               -- 250
--              clk_in1_n => quad_refclk_n,             --   : in   STD_LOGIC;
--              clk_in1_p => quad_refclk_p,             --   : in    STD_LOGIC;
--              reset     => '0',                        --   : in    STD_LOGIC;
--              locked    => open -- : out STD_LOGIC
--  );



END psl_fpga;
