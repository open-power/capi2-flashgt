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
use IEEE.math_real.all;                 -- ceil, log2

ENTITY psl_accel IS
  PORT(
    -- Command interface
    ah_cvalid          : out std_logic                  ; -- Command valid
    ah_ctag            : out std_logic_vector(0 to 7)   ; -- Command tag
    ah_ctagpar         : out std_logic                  ; -- Command tag parity
    ah_com             : out std_logic_vector(0 to 12)  ; -- Command code
    ah_compar          : out std_logic                  ; -- Command code parity
    ah_cabt            : out std_logic_vector(0 to 2)   ; -- Command ABT
    ah_cea             : out std_logic_vector(0 to 63)  ; -- Command address
    ah_ceapar          : out std_logic                  ; -- Command address parity
    ah_cch             : out std_logic_vector(0 to 15)  ; -- Command context handle
    ah_csize           : out std_logic_vector(0 to 11)  ; -- Command size
    ah_cpagesize       : OUT std_logic_vector(0 to 3)   := (others => '0'); -- ** New tie to 0000
    ha_croom           : in  std_logic_vector(0 to 7)   ; -- Command room
    -- Buffer interface
    ha_brvalid         : in  std_logic                  ; -- Buffer Read valid
    ha_brtag           : in  std_logic_vector(0 to 7)   ; -- Buffer Read tag
    ha_brtagpar        : in  std_logic                  ; -- Buffer Read tag parity
    ha_brad            : in  std_logic_vector(0 to 5)   ; -- Buffer Read address
--       ah_brlat           : out std_logic_vector(0 to 3)   ; -- Buffer Read latency
--       ah_brdata          : out std_logic_vector(0 to 1023); -- Buffer Read data
--       ah_brpar           : out std_logic_vector(0 to 15)  ; -- Buffer Read data parity
    ha_bwvalid         : in  std_logic                  ; -- Buffer Write valid
    ha_bwtag           : in  std_logic_vector(0 to 7)   ; -- Buffer Write tag
    ha_bwtagpar        : in  std_logic                  ; -- Buffer Write tag parity
    ha_bwad            : in  std_logic_vector(0 to 5)   ; -- Buffer Write address
    ha_bwdata          : in  std_logic_vector(0 to 1023); -- Buffer Write data
    ha_bwpar           : in  std_logic_vector(0 to 15)  ; -- Buffer Write data parity
    -- Response interface
    ha_rvalid          : in  std_logic                  ; -- Response valid
    ha_rtag            : in  std_logic_vector(0 to 7)   ; -- Response tag
    ha_rtagpar         : in  std_logic                  ; -- Response tag parity
    ha_rditag          : IN  std_logic_vector(0 to 8);    -- **New DMA Translation Tag for xlat_* requests
    ha_rditagpar       : IN  std_logic;                   -- **New Parity bit for above
    ha_response        : in  std_logic_vector(0 to 7)   ; -- Response
    ha_response_ext    : in  std_logic_vector(0 to 7)   ; -- **New Response Ext
    ha_rpagesize       : IN  std_logic_vector(0 to 3);    -- **New Command translated Page size.  Provided by PSL to allow
    ha_rcredits        : in  std_logic_vector(0 to 8)   ; -- Response credits
    ha_rcachestate     : in  std_logic_vector(0 to 1)   ; -- Response cache state
    ha_rcachepos       : in  std_logic_vector(0 to 12)  ; -- Response cache pos
--        ha_reoa            : IN  std_logic_vector(0 to 185);  -- **New unknown width or use
    -- MMIO interface
    ha_mmval           : in  std_logic                  ; -- A valid MMIO is present
    ha_mmcfg           : in  std_logic                  ; -- afu descriptor space access
    ha_mmrnw           : in  std_logic                  ; -- 1 = read, 0 = write
    ha_mmdw            : in  std_logic                  ; -- 1 = doubleword, 0 = word
    ha_mmad            : in  std_logic_vector(0 to 23)  ; -- mmio address
    ha_mmadpar         : in  std_logic                  ; -- mmio address parity
    ha_mmdata          : in  std_logic_vector(0 to 63)  ; -- Write data
    ha_mmdatapar       : in  std_logic                  ; -- mmio data parity
    ah_mmack           : out std_logic                  ; -- Write is complete or Read is valid
    ah_mmdata          : out std_logic_vector(0 to 63)  ; -- Read data
    ah_mmdatapar       : out std_logic                  ; -- mmio data parity
    -- Control interface
    ha_jval            : in  std_logic                  ; -- Job valid
    ha_jcom            : in  std_logic_vector(0 to 7)   ; -- Job command
    ha_jcompar         : in  std_logic                  ; -- Job command parity
    ha_jea             : in  std_logic_vector(0 to 63)  ; -- Job address
    ha_jeapar          : in  std_logic                  ; -- Job address parity
--     ha_lop             : in  std_logic_vector(0 to 4)   ; -- LPC/Internal Cache Op code
--     ha_loppar          : in  std_logic                  ; -- Job address parity
--     ha_lsize           : in  std_logic_vector(0 to 6)   ; -- Size/Secondary Op code
--     ha_ltag            : in  std_logic_vector(0 to 11)  ; -- LPC Tag/Internal Cache Tag
--     ha_ltagpar         : in  std_logic                  ; -- LPC Tag/Internal Cache Tag parity
    ah_jrunning        : out std_logic                  ; -- Job running
    ah_jdone           : out std_logic                  ; -- Job done
    ah_jcack           : out std_logic                  ; -- completion of llcmd
    ah_jerror          : out std_logic_vector(0 to 63)  ; -- Job error
-- AM. Sept08, 2016              ah_jyield          : out std_logic                  ; -- Job yield
--     ah_ldone           : out std_logic                  ; -- LPC/Internal Cache Op done
--     ah_ldtag           : out std_logic_vector(0 to 11)  ; -- ltag is done
--     ah_ldtagpar        : out std_logic                  ; -- ldtag parity
--     ah_lroom           : out std_logic_vector(0 to 7)   ; -- LPC/Internal Cache Op AFU can handle
    ah_tbreq           : out std_logic                  ; -- Timebase command request
    ah_paren           : out std_logic                  ; -- parity enable
    ha_pclock          : in  std_logic                  ;
    -- Port 0
-- New DMA Interface
-- DMA Req interface
    d0h_dvalid          : OUT std_logic                   ;            -- New PSL/AFU interface
    d0h_req_utag        : OUT std_logic_vector(0 to 9)    ;-- New PSL/AFU interface
    d0h_req_itag        : OUT std_logic_vector(0 to 8)    ;-- New PSL/AFU interface
    d0h_dtype           : OUT std_logic_vector(0 to 2)    ;-- New PSL/AFU interface
    d0h_dsize           : OUT std_logic_vector(0 to 9)    ;-- New PSL/AFU interface
    d0h_ddata           : OUT std_logic_vector(0 to 1023) ;-- New PSL/AFU interface
    d0h_datomic_op      : OUT std_logic_vector(0 to 5)    ;-- New PSL/AFU interface
    d0h_datomic_le      : OUT std_logic                   ;-- New PSL/AFU interface
--       d0h_dpar            : OUT std_logic_vector(0 to 15)   ;-- New PSL/AFU interface
-- DMA Sent interface
    hd0_sent_utag_valid : IN  std_logic                  ;
    hd0_sent_utag       : IN  std_logic_vector(0 to 9)   ;
    hd0_sent_utag_sts   : IN  std_logic_vector(0 to 2)   ;
-- DMA CPL interface
    hd0_cpl_valid       : IN  std_logic                  ;
    hd0_cpl_utag        : IN  std_logic_vector(0 to 9)   ;
    hd0_cpl_type        : IN  std_logic_vector(0 to 2)   ;
    hd0_cpl_size        : IN  std_logic_vector(0 to 9)   ;
    hd0_cpl_laddr       : IN  std_logic_vector(0 to 6)   ;
    hd0_cpl_byte_count  : IN  std_logic_vector(0 to 9)   ;
    hd0_cpl_data        : IN  std_logic_vector(0 to 1023);


    -- leds
    led_red: out std_logic_vector(3 downto 0);
    led_green: out std_logic_vector(3 downto 0);
    led_blue: out std_logic_vector(3 downto 0);

    ha_pclock_div2: in std_logic;
    pci_user_reset: in std_logic;
    gold_factory: out std_logic;

    -- pci interface
    pci_pi_nperst1: out std_logic;                                         -- Active low reset from the PCIe reset pin of the device
    pci_pi_refclk_p1: in std_logic;                                       -- 100MHz Refclk
    pci_pi_refclk_n1: in std_logic;                                       -- 100MHz Refclk
    
    pci1_o_susclk : out std_logic;     
    pci1_b_nclkreq : inout std_logic;                                           
    pci1_b_npewake : inout std_logic;                                                                                    

    -- Xilinx requires both pins of differential transceivers
    pci1_i_rxp_in0: in std_logic;
    pci1_i_rxn_in0: in std_logic;
    pci1_i_rxp_in1: in std_logic;
    pci1_i_rxn_in1: in std_logic;
    pci1_i_rxp_in2: in std_logic;
    pci1_i_rxn_in2: in std_logic;
    pci1_i_rxp_in3: in std_logic;
    pci1_i_rxn_in3: in std_logic;
    
    pci1_o_txp_out0: out std_logic;
    pci1_o_txn_out0: out std_logic;
    pci1_o_txp_out1: out std_logic;
    pci1_o_txn_out1: out std_logic;
    pci1_o_txp_out2: out std_logic;
    pci1_o_txn_out2: out std_logic;
    pci1_o_txp_out3: out std_logic;
    pci1_o_txn_out3: out std_logic;
    
    -- pci interface
    pci_pi_nperst2: out std_logic;                                         -- Active low reset from the PCIe reset pin of the device
    pci_pi_refclk_p2: in std_logic;                                       -- 100MHz Refclk
    pci_pi_refclk_n2: in std_logic;                                       -- 100MHz Refclk
    
    pci2_o_susclk : out std_logic;     
    pci2_b_nclkreq : inout std_logic;                                           
    pci2_b_npewake : inout std_logic;                                                                                    

    -- Xilinx requires both pins of differential transceivers
    pci2_i_rxp_in0: in std_logic;
    pci2_i_rxn_in0: in std_logic;
    pci2_i_rxp_in1: in std_logic;
    pci2_i_rxn_in1: in std_logic;
    pci2_i_rxp_in2: in std_logic;
    pci2_i_rxn_in2: in std_logic;
    pci2_i_rxp_in3: in std_logic;
    pci2_i_rxn_in3: in std_logic;
    
    pci2_o_txp_out0: out std_logic;
    pci2_o_txn_out0: out std_logic;
    pci2_o_txp_out1: out std_logic;
    pci2_o_txn_out1: out std_logic;
    pci2_o_txp_out2: out std_logic;
    pci2_o_txn_out2: out std_logic;
    pci2_o_txp_out3: out std_logic;
    pci2_o_txn_out3: out std_logic;
    
    -- pci interface
    pci_pi_nperst3: out std_logic;                                         -- Active low reset from the PCIe reset pin of the device
    pci_pi_refclk_p3: in std_logic;                                       -- 100MHz Refclk
    pci_pi_refclk_n3: in std_logic;                                       -- 100MHz Refclk
    
    pci3_o_susclk : out std_logic;     
    pci3_b_nclkreq : inout std_logic;                                           
    pci3_b_npewake : inout std_logic;                                                                                    
    
    -- Xilinx requires both pins of differential transceivers
    pci3_i_rxp_in0: in std_logic;
    pci3_i_rxn_in0: in std_logic;
    pci3_i_rxp_in1: in std_logic;
    pci3_i_rxn_in1: in std_logic;
    pci3_i_rxp_in2: in std_logic;
    pci3_i_rxn_in2: in std_logic;
    pci3_i_rxp_in3: in std_logic;
    pci3_i_rxn_in3: in std_logic;
    
    pci3_o_txp_out0: out std_logic;
    pci3_o_txn_out0: out std_logic;
    pci3_o_txp_out1: out std_logic;
    pci3_o_txn_out1: out std_logic;
    pci3_o_txp_out2: out std_logic;
    pci3_o_txn_out2: out std_logic;
    pci3_o_txp_out3: out std_logic;
    pci3_o_txn_out3: out std_logic;
    
    -- pci interface
    pci_pi_nperst4: out std_logic;                                         -- Active low reset from the PCIe reset pin of the device
    pci_pi_refclk_p4: in std_logic;                                       -- 100MHz Refclk
    pci_pi_refclk_n4: in std_logic;                                       -- 100MHz Refclk
    
    pci4_o_susclk : out std_logic;     
    pci4_b_nclkreq : inout std_logic;                                           
    pci4_b_npewake : inout std_logic;                                                                                    
    
    -- Xilinx requires both pins of differential transceivers
    pci4_i_rxp_in0: in std_logic;
    pci4_i_rxn_in0: in std_logic;
    pci4_i_rxp_in1: in std_logic;
    pci4_i_rxn_in1: in std_logic;
    pci4_i_rxp_in2: in std_logic;
    pci4_i_rxn_in2: in std_logic;
    pci4_i_rxp_in3: in std_logic;
    pci4_i_rxn_in3: in std_logic;
    
    pci4_o_txp_out0: out std_logic;
    pci4_o_txn_out0: out std_logic;
    pci4_o_txp_out1: out std_logic;
    pci4_o_txn_out1: out std_logic;
    pci4_o_txp_out2: out std_logic;
    pci4_o_txn_out2: out std_logic;
    pci4_o_txp_out3: out std_logic;
    pci4_o_txn_out3: out std_logic
    );
END psl_accel;



ARCHITECTURE psl_accel OF psl_accel IS

  
  Component snvme_afu_top 
    PORT(
      -- Command interface
      ah_cvalid          : out std_logic                  ; -- Command valid
      ah_ctag            : out std_logic_vector(0 to 7)   ; -- Command tag
      ah_ctagpar         : out std_logic                  ; -- Command tag parity
      ah_com             : out std_logic_vector(0 to 12)  ; -- Command code
      ah_compar          : out std_logic                  ; -- Command code parity
      ah_cabt            : out std_logic_vector(0 to 2)   ; -- Command ABT
      ah_cea             : out std_logic_vector(0 to 63)  ; -- Command address
      ah_ceapar          : out std_logic                  ; -- Command address parity
      ah_cch             : out std_logic_vector(0 to 15)  ; -- Command context handle
      ah_csize           : out std_logic_vector(0 to 11)  ; -- Command size
      ah_cpagesize       : OUT std_logic_vector(0 to 3)   := (others => '0'); -- ** New tie to 0000
      ha_croom           : in  std_logic_vector(0 to 7)   ; -- Command room
      -- Buffer interface
--       ha_brvalid         : in  std_logic                  ; -- Buffer Read valid
--       ha_brtag           : in  std_logic_vector(0 to 7)   ; -- Buffer Read tag
--       ha_brtagpar        : in  std_logic                  ; -- Buffer Read tag parity
--       ha_brad            : in  std_logic_vector(0 to 5)   ; -- Buffer Read address
--       ah_brlat           : out std_logic_vector(0 to 3)   ; -- Buffer Read latency
--       ah_brdata          : out std_logic_vector(0 to 1023); -- Buffer Read data
--       ah_brpar           : out std_logic_vector(0 to 15)  ; -- Buffer Read data parity
--       ha_bwvalid         : in  std_logic                  ; -- Buffer Write valid
--       ha_bwtag           : in  std_logic_vector(0 to 7)   ; -- Buffer Write tag
--       ha_bwtagpar        : in  std_logic                  ; -- Buffer Write tag parity
--       ha_bwad            : in  std_logic_vector(0 to 5)   ; -- Buffer Write address
--       ha_bwdata          : in  std_logic_vector(0 to 1023); -- Buffer Write data
--       ha_bwpar           : in  std_logic_vector(0 to 15)  ; -- Buffer Write data parity
      -- Response interface
      ha_rvalid          : in  std_logic                  ; -- Response valid
      ha_rtag            : in  std_logic_vector(0 to 7)   ; -- Response tag
      ha_rtagpar         : in  std_logic                  ; -- Response tag parity
      ha_rditag          : IN  std_logic_vector(0 to 8);    -- **New DMA Translation Tag for xlat_* requests
      ha_rditagpar       : IN  std_logic;                   -- **New Parity bit for above
      ha_response        : in  std_logic_vector(0 to 7)   ; -- Response
      ha_response_ext    : in  std_logic_vector(0 to 7)   ; -- **New Response Ext
      ha_rpagesize       : IN  std_logic_vector(0 to 3);    -- **New Command translated Page size.  Provided by PSL to allow
      ha_rcredits        : in  std_logic_vector(0 to 8)   ; -- Response credits
      ha_rcachestate     : in  std_logic_vector(0 to 1)   ; -- Response cache state
      ha_rcachepos       : in  std_logic_vector(0 to 12)  ; -- Response cache pos
--        ha_reoa            : IN  std_logic_vector(0 to 185);  -- **New unknown width or use
      -- MMIO interface
      ha_mmval           : in  std_logic                  ; -- A valid MMIO is present
      ha_mmcfg           : in  std_logic                  ; -- afu descriptor space access
      ha_mmrnw           : in  std_logic                  ; -- 1 = read, 0 = write
      ha_mmdw            : in  std_logic                  ; -- 1 = doubleword, 0 = word
      ha_mmad            : in  std_logic_vector(0 to 23)  ; -- mmio address
      ha_mmadpar         : in  std_logic                  ; -- mmio address parity
      ha_mmdata          : in  std_logic_vector(0 to 63)  ; -- Write data
      ha_mmdatapar       : in  std_logic                  ; -- mmio data parity
      ah_mmack           : out std_logic                  ; -- Write is complete or Read is valid
      ah_mmdata          : out std_logic_vector(0 to 63)  ; -- Read data
      ah_mmdatapar       : out std_logic                  ; -- mmio data parity
      -- Control interface
      ha_jval            : in  std_logic                  ; -- Job valid
      ha_jcom            : in  std_logic_vector(0 to 7)   ; -- Job command
      ha_jcompar         : in  std_logic                  ; -- Job command parity
      ha_jea             : in  std_logic_vector(0 to 63)  ; -- Job address
      ha_jeapar          : in  std_logic                  ; -- Job address parity
--     ha_lop             : in  std_logic_vector(0 to 4)   ; -- LPC/Internal Cache Op code
--     ha_loppar          : in  std_logic                  ; -- Job address parity
--     ha_lsize           : in  std_logic_vector(0 to 6)   ; -- Size/Secondary Op code
--     ha_ltag            : in  std_logic_vector(0 to 11)  ; -- LPC Tag/Internal Cache Tag
--     ha_ltagpar         : in  std_logic                  ; -- LPC Tag/Internal Cache Tag parity
      ah_jrunning        : out std_logic                  ; -- Job running
      ah_jdone           : out std_logic                  ; -- Job done
      ah_jcack           : out std_logic                  ; -- completion of llcmd
      ah_jerror          : out std_logic_vector(0 to 63)  ; -- Job error
-- AM. Sept08, 2016              ah_jyield          : out std_logic                  ; -- Job yield
--     ah_ldone           : out std_logic                  ; -- LPC/Internal Cache Op done
--     ah_ldtag           : out std_logic_vector(0 to 11)  ; -- ltag is done
--     ah_ldtagpar        : out std_logic                  ; -- ldtag parity
--     ah_lroom           : out std_logic_vector(0 to 7)   ; -- LPC/Internal Cache Op AFU can handle
      ah_tbreq           : out std_logic                  ; -- Timebase command request
      ah_paren           : out std_logic                  ; -- parity enable
      ha_pclock          : in  std_logic                  ;
      -- Port 0
-- New DMA Interface
-- DMA Req interface
      d0h_dvalid          : OUT std_logic                   ;            -- New PSL/AFU interface
      d0h_req_utag        : OUT std_logic_vector(0 to 9)    ;-- New PSL/AFU interface
      d0h_req_itag        : OUT std_logic_vector(0 to 8)    ;-- New PSL/AFU interface
      d0h_dtype           : OUT std_logic_vector(0 to 2)    ;-- New PSL/AFU interface
      d0h_dsize           : OUT std_logic_vector(0 to 9)    ;-- New PSL/AFU interface
      d0h_ddata           : OUT std_logic_vector(0 to 1023) ;-- New PSL/AFU interface
      d0h_datomic_op      : OUT std_logic_vector(0 to 5)    ;-- New PSL/AFU interface
      d0h_datomic_le      : OUT std_logic                   ;-- New PSL/AFU interface
--       d0h_dpar            : OUT std_logic_vector(0 to 15)   ;-- New PSL/AFU interface
-- DMA Sent interface
      hd0_sent_utag_valid : IN  std_logic                  ;
      hd0_sent_utag       : IN  std_logic_vector(0 to 9)   ;
      hd0_sent_utag_sts   : IN  std_logic_vector(0 to 2)   ;
-- DMA CPL interface
      hd0_cpl_valid       : IN  std_logic                  ;
      hd0_cpl_utag        : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_type        : IN  std_logic_vector(0 to 2)   ;
      hd0_cpl_size        : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_laddr       : IN  std_logic_vector(0 to 6)   ;
      hd0_cpl_byte_count  : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_data        : IN  std_logic_vector(0 to 1023);


      -- leds
      led_red: out std_logic_vector(3 downto 0);
      led_green: out std_logic_vector(3 downto 0);
      led_blue: out std_logic_vector(3 downto 0);

      ha_pclock_div2: in std_logic;
      pci_user_reset: in std_logic;
      gold_factory: out std_logic;
      
      pci_exp0_txp: out std_logic_vector(3 downto 0);
      pci_exp0_txn: out std_logic_vector(3 downto 0);
      pci_exp0_rxp: in std_logic_vector(3 downto 0);
      pci_exp0_rxn: in std_logic_vector(3 downto 0);
      pci_exp0_refclk_p: in std_logic;
      pci_exp0_refclk_n: in std_logic;
      pci_exp0_nperst: out std_logic;
      pci_exp0_susclk : out std_logic;     
      pci_exp0_nclkreq : inout std_logic;                                           
      pci_exp0_npewake : inout std_logic;                                                                                    

      pci_exp1_txp: out std_logic_vector(3 downto 0);
      pci_exp1_txn: out std_logic_vector(3 downto 0);
      pci_exp1_rxp: in std_logic_vector(3 downto 0);
      pci_exp1_rxn: in std_logic_vector(3 downto 0);
      pci_exp1_refclk_p: in std_logic;
      pci_exp1_refclk_n: in std_logic;
      pci_exp1_nperst: out std_logic;
      pci_exp1_susclk : out std_logic;     
      pci_exp1_nclkreq : inout std_logic;                                           
      pci_exp1_npewake : inout std_logic; 
      
      pci_exp2_txp: out std_logic_vector(3 downto 0);
      pci_exp2_txn: out std_logic_vector(3 downto 0);
      pci_exp2_rxp: in std_logic_vector(3 downto 0);
      pci_exp2_rxn: in std_logic_vector(3 downto 0);
      pci_exp2_refclk_p: in std_logic;
      pci_exp2_refclk_n: in std_logic;
      pci_exp2_nperst: out std_logic;
      pci_exp2_susclk : out std_logic;     
      pci_exp2_nclkreq : inout std_logic;                                           
      pci_exp2_npewake : inout std_logic;                                                                                    

      pci_exp3_txp: out std_logic_vector(3 downto 0);
      pci_exp3_txn: out std_logic_vector(3 downto 0);
      pci_exp3_rxp: in std_logic_vector(3 downto 0);
      pci_exp3_rxn: in std_logic_vector(3 downto 0);
      pci_exp3_refclk_p: in std_logic;
      pci_exp3_refclk_n: in std_logic;
      pci_exp3_nperst: out std_logic;
      pci_exp3_susclk : out std_logic;     
      pci_exp3_nclkreq : inout std_logic;                                           
      pci_exp3_npewake : inout std_logic;                                                                                    

      i_reset : in std_logic;
      o_reset : out std_logic

      );

  End Component snvme_afu_top;

  Signal       pci_exp0_txp: std_logic_vector(3 downto 0);
  Signal       pci_exp0_txn: std_logic_vector(3 downto 0);
  Signal       pci_exp0_rxp:  std_logic_vector(3 downto 0);
  Signal       pci_exp0_rxn:  std_logic_vector(3 downto 0);
  Signal       pci_exp0_refclk_p:  std_logic;
  Signal       pci_exp0_refclk_n:  std_logic;
  Signal       pci_exp0_nperst: std_logic;
  Signal       pci_exp0_susclk : std_logic;     
  Signal       pci_exp0_nclkreq : std_logic;                                           
  Signal       pci_exp0_npewake : std_logic;          

  Signal       pci_exp1_txp:  std_logic_vector(3 downto 0);
  Signal       pci_exp1_txn:  std_logic_vector(3 downto 0);
  Signal       pci_exp1_rxp:  std_logic_vector(3 downto 0);
  Signal       pci_exp1_rxn:  std_logic_vector(3 downto 0);
  Signal       pci_exp1_refclk_p: std_logic;
  Signal       pci_exp1_refclk_n: std_logic;
  Signal       pci_exp1_nperst: std_logic;
  Signal       pci_exp1_susclk : std_logic;     
  Signal       pci_exp1_nclkreq : std_logic;                                           
  Signal       pci_exp1_npewake : std_logic;          

  Signal       pci_exp2_txp: std_logic_vector(3 downto 0);
  Signal       pci_exp2_txn: std_logic_vector(3 downto 0);
  Signal       pci_exp2_rxp:  std_logic_vector(3 downto 0);
  Signal       pci_exp2_rxn:  std_logic_vector(3 downto 0);
  Signal       pci_exp2_refclk_p:  std_logic;
  Signal       pci_exp2_refclk_n:  std_logic;
  Signal       pci_exp2_nperst: std_logic;
  Signal       pci_exp2_susclk : std_logic;     
  Signal       pci_exp2_nclkreq : std_logic;                                           
  Signal       pci_exp2_npewake : std_logic;          

  Signal       pci_exp3_txp:  std_logic_vector(3 downto 0);
  Signal       pci_exp3_txn:  std_logic_vector(3 downto 0);
  Signal       pci_exp3_rxp:  std_logic_vector(3 downto 0);
  Signal       pci_exp3_rxn:  std_logic_vector(3 downto 0);
  Signal       pci_exp3_refclk_p: std_logic;
  Signal       pci_exp3_refclk_n: std_logic;
  Signal       pci_exp3_nperst: std_logic;
  Signal       pci_exp3_susclk : std_logic;     
  Signal       pci_exp3_nclkreq : std_logic;                                           
  Signal       pci_exp3_npewake : std_logic;              

BEGIN

  s0 : snvme_afu_top
    PORT MAP (

      ah_cvalid          => ah_cvalid,		-- : out std_logic                  ; -- Command valid
      ah_ctag            => ah_ctag,			-- : out std_logic_vector(0 to 7)   ; -- Command tag
      ah_ctagpar         => ah_ctagpar,		-- : out std_logic                  ; -- Command tag parity
      ah_com             => ah_com,			-- : out std_logic_vector(0 to 12)  ; -- Command code
      ah_compar          => ah_compar,		-- : out std_logic                  ; -- Command code parity
      ah_cabt            => ah_cabt,			-- : out std_logic_vector(0 to 2)   ; -- Command ABT
      ah_cea             => ah_cea,			-- : out std_logic_vector(0 to 63)  ; -- Command address
      ah_ceapar          => ah_ceapar,		-- : out std_logic                  ; -- Command address parity
      ah_cch             => ah_cch,			-- : out std_logic_vector(0 to 15)  ; -- Command context handle
      ah_csize           => ah_csize,			-- : out std_logic_vector(0 to 11)  ; -- Command size
      ah_cpagesize       => ah_cpagesize,		-- : OUT std_logic_vector(0 to 3)   := (others => '0'); -- ** New tie to 0000
      ha_croom           => ha_croom,			-- : in  std_logic_vector(0 to 7)   ; -- Command room
      -- Buffer interface
--       ha_brvalid         => ha_brvalid,		-- : in  std_logic                  ; -- Buffer Read valid
--        ha_brtag           => ha_brtag,			-- : in  std_logic_vector(0 to 7)   ; -- Buffer Read tag
--        ha_brtagpar        => ha_brtagpar,		-- : in  std_logic                  ; -- Buffer Read tag parity
--        ha_brad            => ha_brad,			-- : in  std_logic_vector(0 to 5)   ; -- Buffer Read address
--        ah_brlat           => ah_brlat,			-- : out std_logic_vector(0 to 3)   ; -- Buffer Read latency
--        ah_brdata          => ah_brdata,		-- : out std_logic_vector(0 to 1023); -- Buffer Read data
--        ah_brpar           => ah_brpar,			-- : out std_logic_vector(0 to 15)  ; -- Buffer Read data parity
--        ha_bwvalid         => ha_bwvalid,		-- : in  std_logic                  ; -- Buffer Write valid
--        ha_bwtag           => ha_bwtag,			-- : in  std_logic_vector(0 to 7)   ; -- Buffer Write tag
--        ha_bwtagpar        => ha_bwtagpar,		-- : in  std_logic                  ; -- Buffer Write tag parity
--        ha_bwad            => ha_bwad,			-- : in  std_logic_vector(0 to 5)   ; -- Buffer Write address
--        ha_bwdata          => ha_bwdata,		-- : in  std_logic_vector(0 to 1023); -- Buffer Write data
--        ha_bwpar           => ha_bwpar,			-- : in  std_logic_vector(0 to 15)  ; -- Buffer Write data parity
      -- Response interface
      ha_rvalid          => ha_rvalid,		-- : in  std_logic                  ; -- Response valid
      ha_rtag            => ha_rtag,			-- : in  std_logic_vector(0 to 7)   ; -- Response tag
      ha_rtagpar         => ha_rtagpar,		-- : in  std_logic                  ; -- Response tag parity
      ha_rditag          => ha_rditag,		-- : IN  std_logic_vector(0 to 8);    -- **New DMA Translation Tag for xlat_* requests
      ha_rditagpar       => ha_rditagpar,		-- : IN  std_logic;                   -- **New Parity bit for above
      ha_response        => ha_response,		-- : in  std_logic_vector(0 to 7)   ; -- Response
      ha_response_ext    => ha_response_ext,		-- : in  std_logic_vector(0 to 7)   ; -- **New Response Ext
      ha_rpagesize       => ha_rpagesize,		-- : IN  std_logic_vector(0 to 3);    -- **New Command translated Page size.  Provided by PSL to allow
      ha_rcredits        => ha_rcredits,		-- : in  std_logic_vector(0 to 8)   ; -- Response credits
      ha_rcachestate     => ha_rcachestate,		-- : in  std_logic_vector(0 to 1)   ; -- Response cache state
      ha_rcachepos       => ha_rcachepos,		-- : in  std_logic_vector(0 to 12)  ; -- Response cache pos
--        ha_reoa            => ha_reoa,			-- : IN  std_logic_vector(0 to 185);  -- **New unknown width or use
      -- MMIO interface
      ha_mmval           => ha_mmval,			-- : in  std_logic                  ; -- A valid MMIO is present
      ha_mmcfg           => ha_mmcfg,			-- : in  std_logic                  ; -- afu descriptor space access
      ha_mmrnw           => ha_mmrnw,			-- : in  std_logic                  ; -- 1 = read, 0 = write
      ha_mmdw            => ha_mmdw,			-- : in  std_logic                  ; -- 1 = doubleword, 0 = word
      ha_mmad            => ha_mmad,			-- : in  std_logic_vector(0 to 23)  ; -- mmio address
      ha_mmadpar         => ha_mmadpar,		-- : in  std_logic                  ; -- mmio address parity
      ha_mmdata          => ha_mmdata,		-- : in  std_logic_vector(0 to 63)  ; -- Write data
      ha_mmdatapar       => ha_mmdatapar,		-- : in  std_logic                  ; -- mmio data parity
      ah_mmack           => ah_mmack,			-- : out std_logic                  ; -- Write is complete or Read is valid
      ah_mmdata          => ah_mmdata,		-- : out std_logic_vector(0 to 63)  ; -- Read data
      ah_mmdatapar       => ah_mmdatapar,		-- : out std_logic                  ; -- mmio data parity
      -- Control interface
      ha_jval            => ha_jval,			-- : in  std_logic                  ; -- Job valid
      ha_jcom            => ha_jcom,			-- : in  std_logic_vector(0 to 7)   ; -- Job command
      ha_jcompar         => ha_jcompar,		-- : in  std_logic                  ; -- Job command parity
      ha_jea             => ha_jea,			-- : in  std_logic_vector(0 to 63)  ; -- Job address
      ha_jeapar          => ha_jeapar,		-- : in  std_logic                  ; -- Job address parity
      ah_jrunning        => ah_jrunning,		-- : out std_logic                  ; -- Job running
      ah_jdone           => ah_jdone,			-- : out std_logic                  ; -- Job done
      ah_jcack           => ah_jcack,			-- : out std_logic                  ; -- completion of llcmd
      ah_jerror          => ah_jerror,		-- : out std_logic_vector(0 to 63)  ; -- Job error
--     h_jyield          => ah_jyield,		-- : out std_logic                  ; -- Job yield
      ah_tbreq           => ah_tbreq,			-- : out std_logic                  ; -- Timebase command request
      ah_paren           => ah_paren,			-- : out std_logic                  ; -- parity enable
      ha_pclock          => ha_pclock,		-- : in  std_logic                  ;
-- New DMA0 Interface
-- DMA0 Req interface
      d0h_dvalid          => d0h_dvalid,		-- : OUT std_logic                   := '0';            -- New PSL/AFU interface
      d0h_req_utag        => d0h_req_utag,		-- : OUT std_logic_vector(0 to 9)    := (others => '0');-- New PSL/AFU interface
      d0h_req_itag        => d0h_req_itag,		-- : OUT std_logic_vector(0 to 8)    := (others => '0');-- New PSL/AFU interface
      d0h_dtype           => d0h_dtype,		-- : OUT std_logic_vector(0 to 2)    := (others => '0');-- New PSL/AFU interface
      d0h_dsize           => d0h_dsize,		-- : OUT std_logic_vector(0 to 9)    := (others => '0');-- New PSL/AFU interface
      d0h_ddata           => d0h_ddata,		-- : OUT std_logic_vector(0 to 1023) := (others => '0');-- New PSL/AFU interface
      d0h_datomic_op      => d0h_datomic_op,           -- : OUT std_logic_vector(0 to 5);   := (others => '0');-- New PSL/AFU interface
      d0h_datomic_le      => d0h_datomic_le,           -- : OUT std_logic                   := '0';
--        d0h_dpar            => d0h_dpar,		-- : OUT std_logic_vector(0 to 15)   := (others => '0');-- New PSL/AFU interface
-- DMA0 Sent interface
      hd0_sent_utag_valid => hd0_sent_utag_valid,	-- : IN  std_logic                  ;
      hd0_sent_utag       => hd0_sent_utag,		-- : IN  std_logic_vector(0 to 9)   ;
      hd0_sent_utag_sts   => hd0_sent_utag_sts,	-- : IN  std_logic_vector(0 to 2)   ;
-- DMA0 CPL interface
      hd0_cpl_valid       => hd0_cpl_valid,		-- : IN  std_logic                  ;
      hd0_cpl_utag        => hd0_cpl_utag,		-- : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_type        => hd0_cpl_type,		-- : IN  std_logic_vector(0 to 2)   ;
      hd0_cpl_size        => hd0_cpl_size,		-- : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_laddr       => hd0_cpl_laddr,            -- : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_byte_count  => hd0_cpl_byte_count,       -- : IN  std_logic_vector(0 to 9)   ;
      hd0_cpl_data        => hd0_cpl_data,		-- : IN  std_logic_vector(0 to 1023);




      --
      ha_pclock_div2 =>    ha_pclock_div2
      , pci_user_reset   =>    pci_user_reset         
      , gold_factory     =>    gold_factory 
      , i_reset => '0'
      , o_reset => open
      
      , led_red => led_red
      , led_green => led_green
      , led_blue => led_blue

      , pci_exp0_txp  => pci_exp0_txp
      , pci_exp0_txn  => pci_exp0_txn
      , pci_exp0_rxp  => pci_exp0_rxp
      , pci_exp0_rxn  => pci_exp0_rxn
      , pci_exp0_refclk_p  => pci_exp0_refclk_p
      , pci_exp0_refclk_n  => pci_exp0_refclk_n
      , pci_exp0_nperst => pci_exp0_nperst
      , pci_exp0_susclk => pci_exp0_susclk
      , pci_exp0_nclkreq =>  pci_exp0_nclkreq
      , pci_exp0_npewake => pci_exp0_npewake

      , pci_exp1_txp  => pci_exp1_txp
      , pci_exp1_txn  => pci_exp1_txn
      , pci_exp1_rxp  => pci_exp1_rxp
      , pci_exp1_rxn  => pci_exp1_rxn
      , pci_exp1_refclk_p => pci_exp1_refclk_p
      , pci_exp1_refclk_n => pci_exp1_refclk_n
      , pci_exp1_nperst => pci_exp1_nperst
      , pci_exp1_susclk => pci_exp1_susclk
      , pci_exp1_nclkreq =>  pci_exp1_nclkreq
      , pci_exp1_npewake => pci_exp1_npewake

      , pci_exp2_txp  => pci_exp2_txp
      , pci_exp2_txn  => pci_exp2_txn
      , pci_exp2_rxp  => pci_exp2_rxp
      , pci_exp2_rxn  => pci_exp2_rxn
      , pci_exp2_refclk_p  => pci_exp2_refclk_p
      , pci_exp2_refclk_n  => pci_exp2_refclk_n
      , pci_exp2_nperst => pci_exp2_nperst
      , pci_exp2_susclk => pci_exp2_susclk
      , pci_exp2_nclkreq =>  pci_exp2_nclkreq
      , pci_exp2_npewake => pci_exp2_npewake

      , pci_exp3_txp  => pci_exp3_txp
      , pci_exp3_txn  => pci_exp3_txn
      , pci_exp3_rxp  => pci_exp3_rxp
      , pci_exp3_rxn  => pci_exp3_rxn
      , pci_exp3_refclk_p => pci_exp3_refclk_p
      , pci_exp3_refclk_n => pci_exp3_refclk_n
      , pci_exp3_nperst => pci_exp3_nperst
      , pci_exp3_susclk => pci_exp3_susclk
      , pci_exp3_nclkreq =>  pci_exp3_nclkreq
      , pci_exp3_npewake => pci_exp3_npewake


      );


  pci_pi_nperst1    <= pci_exp0_nperst;
  pci_exp0_refclk_p <= pci_pi_refclk_p1;
  pci_exp0_refclk_n <= pci_pi_refclk_n1;
  pci1_o_susclk     <= pci_exp0_susclk;
  pci_exp0_nclkreq  <= pci1_b_nclkreq;
  pci_exp0_npewake  <= pci1_b_npewake;

  pci_exp0_rxp(0) <= pci1_i_rxp_in0;
  pci_exp0_rxn(0) <= pci1_i_rxn_in0;
  pci_exp0_rxp(1) <= pci1_i_rxp_in1;
  pci_exp0_rxn(1) <= pci1_i_rxn_in1;
  pci_exp0_rxp(2) <= pci1_i_rxp_in2;
  pci_exp0_rxn(2) <= pci1_i_rxn_in2;
  pci_exp0_rxp(3) <= pci1_i_rxp_in3;
  pci_exp0_rxn(3) <= pci1_i_rxn_in3;
  
  pci1_o_txp_out0 <= pci_exp0_txp(0);
  pci1_o_txn_out0 <= pci_exp0_txn(0);
  pci1_o_txp_out1 <= pci_exp0_txp(1);
  pci1_o_txn_out1 <= pci_exp0_txn(1);
  pci1_o_txp_out2 <= pci_exp0_txp(2);
  pci1_o_txn_out2 <= pci_exp0_txn(2);
  pci1_o_txp_out3 <= pci_exp0_txp(3);
  pci1_o_txn_out3 <= pci_exp0_txn(3);
  

  pci_pi_nperst2 <= pci_exp1_nperst;
  pci_exp1_refclk_p <= pci_pi_refclk_p2;
  pci_exp1_refclk_n <= pci_pi_refclk_n2;
  pci2_o_susclk     <= pci_exp1_susclk;
  pci_exp1_nclkreq  <= pci2_b_nclkreq;
  pci_exp1_npewake  <= pci2_b_npewake;

  pci_exp1_rxp(0) <= pci2_i_rxp_in0;
  pci_exp1_rxn(0) <= pci2_i_rxn_in0;
  pci_exp1_rxp(1) <= pci2_i_rxp_in1;
  pci_exp1_rxn(1) <= pci2_i_rxn_in1;
  pci_exp1_rxp(2) <= pci2_i_rxp_in2;
  pci_exp1_rxn(2) <= pci2_i_rxn_in2;
  pci_exp1_rxp(3) <= pci2_i_rxp_in3;
  pci_exp1_rxn(3) <= pci2_i_rxn_in3;
  
  pci2_o_txp_out0 <= pci_exp1_txp(0);
  pci2_o_txn_out0 <= pci_exp1_txn(0);
  pci2_o_txp_out1 <= pci_exp1_txp(1);
  pci2_o_txn_out1 <= pci_exp1_txn(1);
  pci2_o_txp_out2 <= pci_exp1_txp(2);
  pci2_o_txn_out2 <= pci_exp1_txn(2);
  pci2_o_txp_out3 <= pci_exp1_txp(3);
  pci2_o_txn_out3 <= pci_exp1_txn(3);


  pci_pi_nperst3    <= pci_exp2_nperst;
  pci_exp2_refclk_p <= pci_pi_refclk_p3;
  pci_exp2_refclk_n <= pci_pi_refclk_n3;
  pci3_o_susclk     <= pci_exp2_susclk;
  pci_exp2_nclkreq  <= pci3_b_nclkreq;
  pci_exp2_npewake  <= pci3_b_npewake;

  pci_exp2_rxp(0) <= pci3_i_rxp_in0;
  pci_exp2_rxn(0) <= pci3_i_rxn_in0;
  pci_exp2_rxp(1) <= pci3_i_rxp_in1;
  pci_exp2_rxn(1) <= pci3_i_rxn_in1;
  pci_exp2_rxp(2) <= pci3_i_rxp_in2;
  pci_exp2_rxn(2) <= pci3_i_rxn_in2;
  pci_exp2_rxp(3) <= pci3_i_rxp_in3;
  pci_exp2_rxn(3) <= pci3_i_rxn_in3;
  
  pci3_o_txp_out0 <= pci_exp2_txp(0);
  pci3_o_txn_out0 <= pci_exp2_txn(0);
  pci3_o_txp_out1 <= pci_exp2_txp(1);
  pci3_o_txn_out1 <= pci_exp2_txn(1);
  pci3_o_txp_out2 <= pci_exp2_txp(2);
  pci3_o_txn_out2 <= pci_exp2_txn(2);
  pci3_o_txp_out3 <= pci_exp2_txp(3);
  pci3_o_txn_out3 <= pci_exp2_txn(3);
  

  pci_pi_nperst4 <= pci_exp3_nperst;
  pci_exp3_refclk_p <= pci_pi_refclk_p4;
  pci_exp3_refclk_n <= pci_pi_refclk_n4;
  pci4_o_susclk     <= pci_exp3_susclk;
  pci_exp3_nclkreq  <= pci4_b_nclkreq;
  pci_exp3_npewake  <= pci4_b_npewake;

  pci_exp3_rxp(0) <= pci4_i_rxp_in0;
  pci_exp3_rxn(0) <= pci4_i_rxn_in0;
  pci_exp3_rxp(1) <= pci4_i_rxp_in1;
  pci_exp3_rxn(1) <= pci4_i_rxn_in1;
  pci_exp3_rxp(2) <= pci4_i_rxp_in2;
  pci_exp3_rxn(2) <= pci4_i_rxn_in2;
  pci_exp3_rxp(3) <= pci4_i_rxp_in3;
  pci_exp3_rxn(3) <= pci4_i_rxn_in3;
  
  pci4_o_txp_out0 <= pci_exp3_txp(0);
  pci4_o_txn_out0 <= pci_exp3_txn(0);
  pci4_o_txp_out1 <= pci_exp3_txp(1);
  pci4_o_txn_out1 <= pci_exp3_txn(1);
  pci4_o_txp_out2 <= pci_exp3_txp(2);
  pci4_o_txn_out2 <= pci_exp3_txn(2);
  pci4_o_txp_out3 <= pci_exp3_txp(3);
  pci4_o_txn_out3 <= pci_exp3_txn(3);


END psl_accel;
