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
use ieee.numeric_std.all;

ENTITY psl_vsec IS
  PORT(psl_clk: in std_logic;
    cfg_ext_read_received : IN STD_LOGIC;
    cfg_ext_write_received : IN STD_LOGIC;
    cfg_ext_register_number : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    cfg_ext_function_number : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    cfg_ext_write_data : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    cfg_ext_write_byte_enable : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    cfg_ext_read_data : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    cfg_ext_read_data_valid : OUT STD_LOGIC;
 
       -- --------------- --
       hi2c_cmdval: out std_logic;
       hi2c_dataval: out std_logic;
       hi2c_addr: out std_logic_vector(0 to 6);
       hi2c_rd: out std_logic;
       hi2c_cmdin: out std_logic_vector(0 to 7);
       hi2c_datain: out std_logic_vector(0 to 7);
       hi2c_blk: out std_logic;
       hi2c_bytecnt: out std_logic_vector(0 to 7);
       hi2c_cntlrsel: out std_logic_vector(0 to 2);
       i2ch_wrdatack: in std_logic;
       i2ch_dataval: in std_logic;
       i2ch_error: in std_logic;
       i2ch_dataout: in std_logic_vector(0 to 7);
       i2ch_ready: in std_logic;
       fpga_smbus_en_n: in std_logic;
     
       -- -------------- --
       pci_pi_nperst0: in std_logic;
       user_lnk_up: in std_logic;
       cpld_usergolden: in std_logic;
       cpld_softreconfigreq: out std_logic;
       cpld_user_bs_req: out std_logic;
       cpld_oe: out std_logic;
       
       -- --------------- --
       f_program_req: out std_logic;                                        -- Level --
       f_num_blocks: out std_logic_vector(0 to 9);                          -- 128KB Block Size --
       f_start_blk: out std_logic_vector(0 to 9);
       f_program_data: out std_logic_vector(0 to 31);
       f_program_data_val: out std_logic;
       f_program_data_ack: in std_logic;
       f_ready: in std_logic;
       f_done: in std_logic;
       f_stat_erase: in std_logic;
       f_stat_program: in std_logic;
       f_stat_read: in std_logic;
       f_remainder: in std_logic_vector(0 to 9);
       f_states: in std_logic_vector(0 to 31);
       f_memstat: in std_logic_vector(0 to 15);
       f_memstat_past: in std_logic_vector(0 to 15);
              
       -- -------------- --
       f_read_req: out std_logic;
       f_num_words_m1: out std_logic_vector(0 to 9);                        -- N-1 words --
       f_read_start_addr: out std_logic_vector(0 to 25);
       f_read_data: in std_logic_vector(0 to 31);
       f_read_data_val: in std_logic;
       f_read_data_ack: out std_logic;

       i2cacc_wren: out std_logic;
       i2cacc_data: out std_logic_vector(0 to 63);
       i2cacc_rden: out std_logic;
       i2cacc_rddata: in std_logic_vector(0 to 63)

  );

END psl_vsec;

ARCHITECTURE psl_vsec OF psl_vsec IS

Component psl_rise_dff
  PORT (clk   : in std_logic;
        dout  : out std_logic;
        din   : in std_logic);
End Component psl_rise_dff;

Component psl_rise_vdff
  GENERIC ( width : positive );
  PORT (clk   : in std_logic;
        dout  : out std_logic_vector(0 to width-1);
        din   : in std_logic_vector(0 to width-1));
End Component psl_rise_vdff;

Component psl_pgen32
  PORT(parity: out std_logic_vector(0 to 3);
       datain: in std_logic_vector(0 to 31));
End Component psl_pgen32;

Component psl_en_rise_vdff
  GENERIC ( width : positive );
  PORT (clk   : in std_logic;
        en    : in std_logic;
        dout  : out std_logic_vector(0 to width-1);
        din   : in std_logic_vector(0 to width-1));
End Component psl_en_rise_vdff;

Component psl_sreconfig
  PORT(psl_clk: in std_logic;
       
       -- -------------- --
       pci_pi_nperst0: in std_logic;
       cpld_softreconfigreq: out std_logic;
       cpld_user_bs_req: out std_logic;
       cpld_oe: out std_logic;
       
       -- -------------- --
       req_reconfig: in std_logic;
       req_user: in std_logic);
End Component psl_sreconfig;

Component psl_en_rise_dff
  PORT (clk   : in std_logic;
        en    : in std_logic;
        dout  : out std_logic;
        din   : in std_logic);
End Component psl_en_rise_dff;

Component psl_rise_vdff_init1
  GENERIC ( width : positive );
  PORT (clk   : in std_logic;
        dout  : out std_logic_vector(0 to width-1);
        din   : in std_logic_vector(0 to width-1));
End Component psl_rise_vdff_init1;

Component psl_en_rise_vdff_init1
  GENERIC ( width : positive );
  PORT (clk   : in std_logic;
        dout  : out std_logic_vector(0 to width-1);
        en    : in std_logic;
        din   : in std_logic_vector(0 to width-1));
End Component psl_en_rise_vdff_init1;

Component psl_ptmon
  PORT(psl_clk: in std_logic;

       -- -------------- --
       mon_power: out std_logic_vector(0 to 15);
       mon_temperature: out std_logic_vector(0 to 15);
       mon_enable: in std_logic;
       aptm_req: in std_logic;
       ptma_grant: out std_logic);
End Component psl_ptmon;


component  psl_hdk_vpd port (
      clk: in std_logic;
      nperst: in std_logic;
      user_lnk_up: in std_logic;
      vpd_adr_en: in std_logic;
      vpd_dat_en: in std_logic;
      vpd_wrdata: in std_logic_vector(0 to 31);

      vpd_adr: out std_logic_vector(0 to 31);
      vpd_dat: out std_logic_vector(0 to 31);

      i2c_cmdval: out std_logic;
      i2c_read: out std_logic;
      i2c_addr: out std_logic_vector(0 to 7);
      i2c_data: out std_logic_vector(0 to 7);
      i2c_dataval: out std_logic;
      i2c_bytecnt: out std_logic_vector(0 to 7);

      i2ch_dataval: in std_logic;
      i2ch_dataout: in std_logic_vector(0 to 7);
      i2ch_ready: in std_logic          
  );
end component psl_hdk_vpd;

function gate_and (gate : std_logic; din : std_logic_vector) return std_logic_vector is
begin
  if (gate = '1') then
    return din;
  else
    return (0 to din'length-1 => '0');
  end if;
end gate_and;

Signal cseb_addr_l: std_logic_vector(0 to 32);  -- v33bit
Signal cseb_addr_parity_l: std_logic_vector(0 to 4);  -- v5bit
Signal cseb_be_l: std_logic_vector(0 to 3);  -- v4bit
Signal cseb_rddata_in: std_logic_vector(0 to 31);  -- v32bit
Signal cseb_rddata_parity_in: std_logic_vector(0 to 3);  -- v4bit
Signal cseb_rden_l_sig: std_logic;  -- bool
Signal cseb_rdresponse_d: std_logic_vector(0 to 4);  -- v5bit
Signal cseb_wrdata_l: std_logic_vector(0 to 31);  -- v32bit
Signal cseb_wrdata_parity_l: std_logic_vector(0 to 3);  -- v4bit
Signal cseb_wren_l: std_logic;  -- bool
Signal cseb_wrresp_req_l: std_logic;  -- bool
Signal cseb_wrresp_valid_in: std_logic;  -- bool
Signal cseb_wrresponse_d: std_logic_vector(0 to 4);  -- v5bit

Signal cfg_ext_read_received_valid: std_logic;
Signal cfg_ext_write_received_i: std_logic;
Signal    cseb_addr									: std_logic_vector(0 to 32);  		-- v33bit
Signal    cseb_be                                        : std_logic_vector(0 to 3);          -- v4bit

Signal f_program_data_val_d: std_logic;  -- bool
Signal flash_rd_req: std_logic;  -- bool
Signal image_loaded: std_logic;  -- bool
Signal nafu_en: std_logic;  -- bool
Signal num_afus_d: std_logic_vector(0 to 3);  -- v4bit
Signal num_afus_enabled: std_logic_vector(0 to 3);  -- v4bit
Signal num_afus_lsb: std_logic;  -- bool
Signal num_afus_msbs: std_logic_vector(0 to 2);  -- v3bit
Signal nxt_cap_id: std_logic_vector(0 to 15);  -- v16bit
Signal one_afu_reset: std_logic;  -- bool
-- Signal rden_pulse: std_logic;  -- bool
Signal rden_pulse_in: std_logic;  -- bool
Signal reconfig_cntl_d: std_logic_vector(0 to 1);  -- v2bit
Signal reconfig_cntl_q: std_logic_vector(0 to 1);  -- v2bit
Signal req_reconfig: std_logic;  -- bool
Signal req_user: std_logic;  -- bool
Signal sreconfig_en: std_logic;  -- bool
Signal sreconfig_rdat2: std_logic;  -- bool
Signal sreconfig_rdat3: std_logic;  -- bool
Signal sreconfig_wdat2: std_logic;  -- bool
Signal sreconfig_wdat3: std_logic;  -- bool
Signal sreconfig_wrdat: std_logic_vector(0 to 1);  -- v2bit
Signal v10const: std_logic_vector(0 to 27);  -- v28bit
Signal v8const: std_logic_vector(0 to 27);  -- v28bit
--Signal version: std_logic_vector(0 to 31);  -- int
Signal vfadr_en: std_logic;  -- bool
Signal vfctl_en: std_logic;  -- bool
Signal vfppc_en: std_logic;  -- bool
Signal vfppp_en: std_logic;  -- bool
signal vfi2c_lo_en: std_logic;
signal vfi2c_hi_en: std_logic;
Signal vfrddp_en: std_logic;  -- bool
Signal vfrddp_read: std_logic;  -- bool
Signal vfrddp_val: std_logic;  -- bool
Signal vfrddp_val_d: std_logic;  -- bool
Signal vfsize_en: std_logic;  -- bool
Signal vfwrdp_en: std_logic;  -- bool
Signal vpd40data: std_logic_vector(0 to 31);  -- v32bit
Signal vpd44data: std_logic_vector(0 to 31);  -- v32bit
Signal vpd44data_d: std_logic_vector(0 to 31);  -- v32bit
Signal vpd44data_q: std_logic_vector(0 to 31);  -- v32bit
Signal vpd44_update: std_logic;
Signal vpd44data_be: std_logic_vector(0 to 31); -- v32bit
Signal vpd_usehardcoded: std_logic;  -- bool
Signal vpd_usei2cdata_q: std_logic;  -- bool
Signal vpd_hardcoded_q: std_logic;  -- bool
Signal vpd_0x40: std_logic;  -- bool
Signal vpd_0x44: std_logic;  -- bool
Signal vpd_base: std_logic;  -- bool
Signal vpd_rdy_flag: std_logic;  -- bool
Signal vpd_rdy_flag_d: std_logic;  -- bool
Signal vpd_rdy_flag_q: std_logic;  -- bool
Signal update_vpd_rdy_flag: std_logic;  -- bool
Signal vpd_read_done_d: std_logic;
Signal vpd_read_done_q: std_logic;
Signal vpd_write_done_d: std_logic;
Signal vpd_write_done_q: std_logic;
Signal vpdadr: std_logic_vector(0 to 5);  -- v5bit
Signal vsec10data: std_logic_vector(0 to 31);  -- v32bit
Signal vsec14data: std_logic_vector(0 to 31);  -- v32bit
Signal vsec38data: std_logic_vector(0 to 31);  -- v32bit
Signal vsec3Cdata: std_logic_vector(0 to 31);  -- v32bit
Signal vsec40data: std_logic_vector(0 to 31);  -- v32bit
Signal vsec44data: std_logic_vector(0 to 31);  -- v32bit
Signal vsec50data: std_logic_vector(0 to 31);  -- v32bit
Signal vsec54data: std_logic_vector(0 to 31);  -- v32bit
Signal vsec58data: std_logic_vector(0 to 31);  -- v32bit
Signal vsec5C_reg_en: std_logic;  -- bool
Signal vsec5Cdata: std_logic_vector(0 to 31);  -- v32bit
Signal vsec5Cdata_d: std_logic_vector(0 to 31);  -- v32bit
Signal vsec8data: std_logic_vector(0 to 31);  -- v32bit
Signal vsecCdata: std_logic_vector(0 to 31);  -- v32bit
Signal vsec_0x00: std_logic;  -- bool
Signal vsec_0x04: std_logic;  -- bool
Signal vsec_0x08: std_logic;  -- bool
Signal vsec_0x0C: std_logic;  -- bool
Signal vsec_0x10: std_logic;  -- bool
Signal vsec_0x20: std_logic;  -- bool
Signal vsec_0x24: std_logic;  -- bool
Signal vsec_0x28: std_logic;  -- bool
Signal vsec_0x2C: std_logic;  -- bool
Signal vsec_0x40: std_logic;  -- bool
Signal vsec_0x44: std_logic;  -- bool
Signal vsec_0x50: std_logic;  -- bool
Signal vsec_0x54: std_logic;  -- bool
Signal vsec_0x58: std_logic;  -- bool
Signal vsec_0x5C: std_logic;  -- bool
Signal vsec_addr: std_logic_vector(0 to 32);  -- v33bit
Signal vsec_base: std_logic;  -- bool
Signal vsec_fadr: std_logic_vector(0 to 25);  -- v26bit
Signal vsec_fsize: std_logic_vector(0 to 9);  -- v10bit
Signal vsec_rddata: std_logic_vector(0 to 31);  -- v32bit
Signal vsec_wrdata: std_logic_vector(0 to 31);  -- v32bit
Signal vvpdadr_en: std_logic;  -- bool
Signal vvpdadr_en1: std_logic; -- bool
Signal vvpdadr_en_q1: std_logic; -- bool
Signal vvpdadr_en_q2: std_logic; -- bool
Signal vvpdadr_en_q3: std_logic; -- bool
Signal vvpdadr_en_q4: std_logic; -- bool
Signal vvpdadr_en_q5: std_logic; -- bool
Signal vvpdwrdat_en: std_logic;  -- bool
-- Signal waitrequest: std_logic;  -- bool
-- Signal waitrequest_in: std_logic;  -- bool
-- Signal waitrequest_rst_sig: std_logic;  -- bool
-- Signal wren_pulse: std_logic;  -- bool
Signal wren_pulse_in: std_logic;  -- bool
Signal xilinxvsecCdata: std_logic_vector(0 to 31);  -- v32bit
-- Signal cseb_waitrequestinternal: std_logic;  -- bool
Signal f_program_data_valinternal: std_logic;  -- bool
Signal f_program_reqinternal: std_logic;  -- bool
Signal f_read_reqinternal: std_logic;  -- bool
Signal hi2c_cmdval_d: std_logic;
Signal hi2c_dataval_d: std_logic;
Signal hi2c_rd_d: std_logic;
Signal hi2c_cmdin_d: std_logic_vector(0 to 7);
Signal hi2c_datain_d: std_logic_vector(0 to 7);
Signal i2ch_ready_d: std_logic;
Signal hi2c_cmdval_q: std_logic;
Signal hi2c_cmdval_q1: std_logic;
Signal hi2c_cmdval_q2: std_logic;
Signal hi2c_cmdval_q3: std_logic;
Signal hi2c_cmdval_q4: std_logic;
Signal hi2c_cmdval_q5: std_logic;
Signal hi2c_dataval_q: std_logic;
Signal hi2c_rd_q: std_logic;
Signal hi2c_cmdin_q: std_logic_vector(0 to 7);
Signal hi2c_datain_q: std_logic_vector(0 to 7);
Signal i2ch_ready_q: std_logic;
Signal i2c_byteop_d: std_logic_vector(0 to 2);
Signal i2c_byteop_q: std_logic_vector(0 to 2);
Signal i2c_monitor_ready_d: std_logic;
Signal i2c_monitor_ready_q: std_logic;
Signal vpdwrdat: std_logic_vector(0 to 31);
Signal eeprom_wdelay_count_d: std_logic_vector(0 to 20);
Signal eeprom_wdelay_count_q: std_logic_vector(0 to 20);

attribute dont_touch : string;
attribute dont_touch of vpd_hardcoded_q : signal is "true";

attribute mark_debug : string;

attribute mark_debug of vsec_addr : signal is "false";
attribute mark_debug of vsec_base : signal is "false";
attribute mark_debug of vsec_fadr : signal is "false";
attribute mark_debug of vsec_fsize : signal is "false";
attribute mark_debug of vsec_rddata : signal is "false";
attribute mark_debug of vsec_wrdata : signal is "false";
attribute mark_debug of vfadr_en : signal is "false";
attribute mark_debug of vfctl_en : signal is "false";
attribute mark_debug of vfppc_en : signal is "false";
attribute mark_debug of vfppp_en : signal is "false";
attribute mark_debug of vfrddp_en : signal is "false";
attribute mark_debug of vfrddp_read : signal is "false";
attribute mark_debug of vfrddp_val : signal is "false";
attribute mark_debug of vfrddp_val_d : signal is "false";
attribute mark_debug of vsec58data : signal is "false";
attribute mark_debug of vsec5C_reg_en : signal is "false";
attribute mark_debug of vsec5Cdata : signal is "false";
attribute mark_debug of vsec5Cdata_d : signal is "false";
attribute mark_debug of vvpdadr_en : signal is "false";
attribute mark_debug of vvpdadr_en_q1 : signal is "false";
attribute mark_debug of vvpdadr_en_q2 : signal is "false";
attribute mark_debug of vvpdadr_en_q3 : signal is "false";
attribute mark_debug of vvpdadr_en_q4 : signal is "false";
attribute mark_debug of vvpdadr_en_q5 : signal is "false";
attribute mark_debug of vvpdwrdat_en : signal is "false";
attribute mark_debug of vsec_0x58 : signal is "false";
attribute mark_debug of vsec_0x5C : signal is "false";
attribute mark_debug of vpd40data : signal is "false";
attribute mark_debug of vpd44data : signal is "false";
attribute mark_debug of vpd44data_d : signal is "false";
attribute mark_debug of vpd44data_q : signal is "false";
attribute mark_debug of vpd44_update : signal is "false";
attribute mark_debug of vpd44data_be : signal is "false";
attribute mark_debug of vpd_0x40 : signal is "false";
attribute mark_debug of vpd_0x44 : signal is "false";
attribute mark_debug of vpd_base : signal is "false";
attribute mark_debug of vpd_rdy_flag : signal is "false";
attribute mark_debug of vpd_rdy_flag_d : signal is "false";
attribute mark_debug of vpd_rdy_flag_q : signal is "false";
attribute mark_debug of update_vpd_rdy_flag : signal is "false";
attribute mark_debug of vpd_read_done_d : signal is "false";
attribute mark_debug of vpd_read_done_q : signal is "false";
attribute mark_debug of vpd_write_done_d : signal is "false";
attribute mark_debug of vpd_write_done_q : signal is "false";
attribute mark_debug of vpdadr : signal is "false";

attribute mark_debug of hi2c_cmdval_d : signal is "false";
attribute mark_debug of hi2c_dataval_d : signal is "false";
attribute mark_debug of hi2c_rd_d : signal is "false";
attribute mark_debug of hi2c_cmdin_d : signal is "false";
attribute mark_debug of hi2c_datain_d : signal is "false";
attribute mark_debug of i2ch_ready_d : signal is "false";
attribute mark_debug of hi2c_cmdval_q : signal is "false";
attribute mark_debug of hi2c_cmdval_q1 : signal is "false";
attribute mark_debug of hi2c_cmdval_q2 : signal is "false";
attribute mark_debug of hi2c_cmdval_q3 : signal is "false";
attribute mark_debug of hi2c_cmdval_q4 : signal is "false";
attribute mark_debug of hi2c_cmdval_q5 : signal is "false";
attribute mark_debug of hi2c_dataval_q : signal is "false";
attribute mark_debug of hi2c_rd_q : signal is "false";
attribute mark_debug of hi2c_cmdin_q : signal is "false";
attribute mark_debug of hi2c_datain_q : signal is "false";
attribute mark_debug of i2ch_ready_q : signal is "false";
attribute mark_debug of i2c_byteop_d : signal is "false";
attribute mark_debug of i2c_byteop_q : signal is "false";
attribute mark_debug of i2c_monitor_ready_d : signal is "false";
attribute mark_debug of i2c_monitor_ready_q : signal is "false";
attribute mark_debug of vpdwrdat : signal is "false";
attribute mark_debug of eeprom_wdelay_count_d : signal is "false";

-- New signals for Performance Measurement Logic
Signal vsec_0x14: std_logic;  -- bool
Signal vsec_0x14_en: std_logic;  -- bool
Signal vsec_0x18: std_logic;  -- bool
Signal vsec_0x1C: std_logic;  -- bool
Signal vsec_0x30: std_logic;  -- bool
Signal vsec_0x34: std_logic;  -- bool
Signal vsec_0x38: std_logic;  -- bool
Signal vsec_0x3C: std_logic;  -- bool
Signal vsec_0x48: std_logic;  -- bool
Signal vsec_0x4C: std_logic;  -- bool
Signal vsec_0x60: std_logic;  -- bool
Signal vsec_0x64: std_logic;  -- bool
Signal vsec_0x68: std_logic;  -- bool
Signal vsec_0x6c: std_logic;  -- bool
Signal vsec_0x70: std_logic;  -- bool
Signal vsec_0x74: std_logic;  -- bool
Signal vsec_0x78: std_logic;  -- bool


Signal psl_ptmon_lo_en: std_logic;  -- bool
Signal psl_ptmon_hi_en: std_logic;  -- bool
Signal pslreg_psl_ptmon: std_logic_vector(0 to 18);  -- psl_ptmon
Signal pslreg_psl_ptmon_mon_en_q: std_logic;  -- bool
Signal pslreg_psl_ptmon_pwr_en_q: std_logic;  -- bool
Signal pslreg_psl_ptmon_pwr_trip_q: std_logic_vector(0 to 7);  -- v8bit
Signal pslreg_psl_ptmon_temp_en_q: std_logic;  -- bool
Signal pslreg_psl_ptmon_temp_trip_q: std_logic_vector(0 to 7);  -- v8bit
Signal rddat_psl_ptmon: std_logic_vector(0 to 63);  -- v64bit
Signal mon_power: std_logic_vector(0 to 15);
Signal mon_temperature: std_logic_vector(0 to 15);
Signal mon_enable: std_logic;
Signal aptm_req: std_logic;  -- bool


begin


--    version <= "00000000000000000000000000010101" ;

--============================================================================================
---- Misc. Logic
--==============================================================================================--
 -- ----------------------------------- --
 -- Interface Control                   --
 -- ----------------------------------- --


    cseb_wrresponse_d <= "00000" ;
    cseb_rdresponse_d <= "00000" ;

    cfg_ext_read_data_valid           <= cseb_rden_l_sig;
    
    
    --read data enable - byte offset 0x400 for vsec and 0xB0 for vpd
      --  decode regno>=0x100 or (regno>=0x2C and regno < 0x40)
      cfg_ext_read_received_valid <= '1' when ((cfg_ext_read_received = '1') and 
                                               ((cfg_ext_register_number(9 downto 8) /= "00") or 
                                               ((cfg_ext_register_number(9 downto 0) >= "0000101100") and (cfg_ext_register_number(9 downto 0) < "0001000000")))) else '0';
     
 -- Latch Inputs                        --
    dff_cseb_rden_l: psl_rise_dff PORT MAP (
         dout => cseb_rden_l_sig,
         din => cfg_ext_read_received_valid,
         clk   => psl_clk
    );

  cfg_ext_write_received_i  <=  '1' when ((cfg_ext_write_received = '1') and 
                                           ((cfg_ext_register_number(9 downto 8) /= "00") or 
                                           ((cfg_ext_register_number(9 downto 0) >= "0000101100") and (cfg_ext_register_number(9 downto 0) < "0001000000")))) else '0';
  
    dff_cseb_wren_l: psl_rise_dff PORT MAP (
         dout => cseb_wren_l,
         din => cfg_ext_write_received_i,
         clk   => psl_clk
    );

    dff_cseb_wrresp_req_l: psl_rise_dff PORT MAP (
         dout => cseb_wrresp_req_l,
         din => '0',
         clk   => psl_clk
    );
    
    
-- address and  Byte enables
      cseb_addr(21 to 30)       <=   cfg_ext_register_number;
      cseb_addr(0 to 20)        <=   "000000000000000000000";
      cseb_addr(31 to 32)       <=   "00";
      cseb_be                   <=   cfg_ext_write_byte_enable;
      
    dff_cseb_addr_l: psl_rise_vdff GENERIC MAP ( width => 33 ) PORT MAP (
         dout => cseb_addr_l,
         din => cseb_addr,
         clk   => psl_clk
    );

    dff_cseb_addr_parity_l: psl_rise_vdff GENERIC MAP ( width => 5 ) PORT MAP (
         dout => cseb_addr_parity_l,
         din => "00000",
         clk   => psl_clk
    );

    dff_cseb_be_l: psl_rise_vdff GENERIC MAP ( width => 4 ) PORT MAP (
         dout => cseb_be_l,
         din => cseb_be,
         clk   => psl_clk
    );

    dff_cseb_wrdata_l: psl_rise_vdff GENERIC MAP ( width => 32 ) PORT MAP (
         dout => cseb_wrdata_l,
         din => cfg_ext_write_data,
         clk   => psl_clk
    );

    dff_cseb_wrdata_parity_l: psl_rise_vdff GENERIC MAP ( width => 4 ) PORT MAP (
         dout => cseb_wrdata_parity_l,
         din => "0000",
         clk   => psl_clk
    );

    wren_pulse_in <= cseb_wren_l ;
    rden_pulse_in <= cseb_rden_l_sig;

    dff_image_loaded: psl_rise_dff PORT MAP (
         dout => image_loaded,
         din => cpld_usergolden,
         clk   => psl_clk
    );
	cfg_ext_read_data		<= cseb_rddata_in;	
    cseb_wrresp_valid_in <=  not (f_program_data_valinternal  and  cseb_wrresp_req_l  and  cseb_wren_l  and  vsec_0x5C) ;

 -- -- End Section -- --

--============================================================================================
---- Read Mux
--==============================================================================================--

    vsec_rddata <= gate_and(vpd_0x40,vpd40data) or
                   gate_and(vpd_0x44,vpd44data) or
                   gate_and(vsec_0x00,"00000000000000010000000000001011") or
                   gate_and(vsec_0x04,"00001000000000000001001010000000") or
                   gate_and(vsec_0x08,vsec8data) or
                   gate_and(vsec_0x0C,vsecCdata) or
                   gate_and(vsec_0x10,vsec10data) or
                   gate_and(vsec_0x20,"00000000000000000000000100000000") or
                   gate_and(vsec_0x24,"00000000000000000000000001000000") or
                   gate_and(vsec_0x28,"00000000000000000000001000000000") or
                   gate_and(vsec_0x2C,"00000000000000000000010000000000") or
                   gate_and(vsec_0x40,vsec40data) or
                   gate_and(vsec_0x44,vsec44data) or
                   gate_and(vsec_0x50,vsec50data) or
                   gate_and(vsec_0x54,vsec54data) or
                   gate_and(vsec_0x58,vsec58data) or

                   -- reserved registers
                   gate_and(vsec_0x14,vsec14data) or
                   gate_and(vsec_0x18,i2cacc_rddata(32 to 63)) or
                   gate_and(vsec_0x1C,i2cacc_rddata(0 to 31)) or
                   gate_and(vsec_0x30,rddat_psl_ptmon(32 to 63)) or
                   gate_and(vsec_0x34,rddat_psl_ptmon(0 to 31)) or

 --                  gate_and(vsec_0x38,vsec38data) or
 --                  gate_and(vsec_0x3C,vsec3Cdata) or

 --                gate_and(vsec_0x38,prf_32_5_bits_of_prf_data_l2) or
 --                    gate_and(vsec_0x3C,prf_32_6_bits_of_prf_data_l2) or
 --                   gate_and(vsec_0x48,prf_32_7_bits_of_prf_data_l2) or
 --                gate_and(vsec_0x4C,prf_32_8_bits_of_prf_data_l2) or
 --                gate_and(vsec_0x60,prf_32_9_bits_of_prf_data_l2) or
 --                gate_and(vsec_0x64,prf_32_10_bits_of_prf_data_l2) or
 --                gate_and(vsec_0x68,prf_32_11_bits_of_prf_data_l2) or
 --                gate_and(vsec_0x6C,prf_32_12_bits_of_prf_data_l2) or                  
 --                gate_and(vsec_0x70,prf_32_13_bits_of_prf_data_l2) or
 --                gate_and(vsec_0x74,prf_32_14_bits_of_prf_data_l2) or
 --                gate_and(vsec_0x78,prf_32_15_bits_of_prf_data_l2) or

                   gate_and(vsec_0x5C,vsec5Cdata);



    --reversebus(type=v32bit) (cseb_rddata_in, vsec_rddata);
    cseb_rddata_in <= vsec_rddata ;
-- AM Feb26, 2017    pgen_cseb_rddata_parity_in: psl_pgen32
-- AM Feb26, 2017. Currently parity is not in use
-- AM Feb26, 2017      PORT MAP (
-- AM Feb26, 2017         parity => cseb_rddata_parity_in,
-- AM Feb26, 2017         datain => cseb_rddata_in
-- AM Feb26, 2017    );

--============================================================================================
---- VSEC Registers
--==============================================================================================--
    --reversebus(type=v32bit) (vsec_wrdata, cseb_wrdata_l);
    vsec_wrdata <= cseb_wrdata_l ;

 -- ----------------------------------- --
 -- Number of AFUs VSEC Field           --
 -- ----------------------------------- --
-- In VU3P wren_pulse is active one cycle LATER THAN vsec_address and cseb_be_l signals
-- AM Feb26, 2017    nafu_en <= vsec_0x08  and  cseb_be_l(3)  and  wren_pulse ;
    nafu_en <= vsec_0x08  and  cseb_be_l(3)  and  wren_pulse_in ;

    --mux(type=v4bit) (num_afus_d, psl_dl_done, num_afu_ports, vsec_wrdata[28..31]);--
    one_afu_reset <=  not vsec_wrdata(31) ;
    num_afus_d <= ( vsec_wrdata(28 to 30) & one_afu_reset );

    endff_num_afus_enabled: psl_en_rise_vdff GENERIC MAP ( width => 4 ) PORT MAP (
         dout => num_afus_enabled,
         en => nafu_en,
         din => num_afus_d,
         clk   => psl_clk
    );


    v8const <= "0000000000100001000010000000" ;

    num_afus_msbs <= num_afus_enabled(0 to 2) ;
    num_afus_lsb <=  not num_afus_enabled(3) ;
    vsec8data <= ( v8const & num_afus_msbs & num_afus_lsb );

 -- -- End Section -- --

 -- -------------------------------------- --
 -- CAIA/PSL Version  --
 -- -------------------------------------- --
 -- xilinxvsecCdata <= "00000001000000000011000000000001" ;
    xilinxvsecCdata <= "00000010000000000011000000000001" ;


    vsecCdata <= xilinxvsecCdata ;
 -- -------------------------------------- --
 -- Soft Reconfiguration Status / Control  --
 -- -------------------------------------- --
 -- AM Feb27, 2017    sreconfig_en <= vsec_0x10  and  cseb_be_l(0)  and  wren_pulse ;
    sreconfig_en <= vsec_0x10  and  cseb_be_l(0)  and  wren_pulse_in ;

    sreconfig_wdat2 <=  not vsec_wrdata(2) ;
    -- image_loaded: 0=factory 1=user.  If this is user image, invert bit 3
    -- (aka bit 28 - image select) so that default is to reload same image
    sreconfig_wdat3 <=  image_loaded xor vsec_wrdata(3) ;
    sreconfig_wrdat <= ( sreconfig_wdat2 & sreconfig_wdat3 );

    -- v2bit reconfig_cntl_d = vsec_wrdata.[2..3];
    reconfig_cntl_d <= sreconfig_wrdat ;
    endff_reconfig_cntl_q: psl_en_rise_vdff GENERIC MAP ( width => 2 ) PORT MAP (
         dout => reconfig_cntl_q,
         en => sreconfig_en,
         din => reconfig_cntl_d,
         clk   => psl_clk
    );

    v10const <= "0000000000000000000000000000" ;  -- Base Image Revision --

    sreconfig_rdat2 <=  not reconfig_cntl_q(0) ;
    sreconfig_rdat3 <=  image_loaded xor reconfig_cntl_q(1) ;
    --concat(type=v32bit) (vsec10data, image_loaded, 0b0, reconfig_cntl_q, v10const);
    vsec10data <= ( image_loaded & '0' & sreconfig_rdat2 & sreconfig_rdat3 & v10const );

    req_reconfig <= vsec10data(2) ;
    req_user <= vsec10data(3) ;

    scfg: psl_sreconfig
      PORT MAP (
         pci_pi_nperst0 => pci_pi_nperst0,
         cpld_softreconfigreq => cpld_softreconfigreq,
         cpld_user_bs_req => cpld_user_bs_req,
         cpld_oe => cpld_oe,
         req_reconfig => req_reconfig,
         req_user => req_user,
         psl_clk => psl_clk
    );

 -- -- End Section -- --

-- ----------------------------------- --
 -- I2C interface                --
 -- ----------------------------------- --
    vfi2c_lo_en <= vsec_0x18  and  cseb_be_l(0)  and  cseb_be_l(2)  and 
                                cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse_in ;
    vfi2c_hi_en <= vsec_0x1C  and  cseb_be_l(0)  and  cseb_be_l(2)  and 
                                cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse_in ;
 
    i2cacc_wren <= vfi2c_hi_en;
    i2cacc_rden <= vsec_0x1C and cseb_be_l(0)  and  cseb_be_l(2)  and 
                                cseb_be_l(1)  and  cseb_be_l(0)  and rden_pulse_in;

    endff_vsec18data: psl_en_rise_vdff GENERIC MAP ( width => 32 ) PORT MAP (
         dout => i2cacc_data(32 to 63),
         en => vfi2c_lo_en,
         din => vsec_wrdata,
         clk   => psl_clk
    );

    endff_vsec1Cdata: psl_en_rise_vdff GENERIC MAP ( width => 32 ) PORT MAP (
         dout => i2cacc_data(0 to 31),
         en => vfi2c_hi_en,
         din => vsec_wrdata,
         clk   => psl_clk
    );


   -- used a reserved bit in I2C interface to control access to VPD data
   -- defaults to hardcoded VPD to work around bad VPD data
   endff_vpd_usei2cdata: psl_en_rise_dff PORT MAP (
         dout => vpd_usei2cdata_q,
         en => vfi2c_hi_en,
         din => vsec_wrdata(3),
         clk   => psl_clk
    );

    -- ECO placeholder
    -- allow simple edit of checkpoint netlist to enable I2C vpd data
    endff_vpd_dbg_hardcoded: psl_rise_dff PORT MAP (
         dout => vpd_hardcoded_q,
         din => vpd_hardcoded_q,
         clk => psl_clk
      );
    vpd_usehardcoded <= not(vpd_usei2cdata_q or not(vpd_hardcoded_q));

    -- read access via reserved register
    vsec14data <= x"0000000" & "00" & vpd_hardcoded_q & vpd_usei2cdata_q;


 -- -- End Section -- --


 -- ----------------------------------- --
 -- PSL Programming Port                --
 -- ----------------------------------- --
    vfppp_en <= vsec_0x40  and  cseb_be_l(0)  and  cseb_be_l(2)  and 
 -- AM Feb27, 2017                               cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse ;
                                cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse_in ;
 
    endff_vsec40data: psl_en_rise_vdff GENERIC MAP ( width => 32 ) PORT MAP (
         dout => vsec40data,
         en => vfppp_en,
         din => vsec_wrdata,
         clk   => psl_clk
    );


 -- -- End Section -- --


 -- ----------------------------------- --
 -- PSL Programming Port                --
 -- ----------------------------------- --
 -- AM Feb27, 2017   vfppc_en <= vsec_0x44  and  cseb_be_l(0)  and  wren_pulse ;
    vfppc_en <= vsec_0x44  and  cseb_be_l(0)  and  wren_pulse_in ;

    endff_vsec44data: psl_en_rise_vdff GENERIC MAP ( width => 32 ) PORT MAP (
         dout => vsec44data,
         en => vfppc_en,
         din => vsec_wrdata,
         clk   => psl_clk
    );

 -- -- End Section -- --

 -- ----------------------------------- --
 -- VPD Address Register                --
 -- ----------------------------------- --

-- VPD Read Procedure:
-- 1. Write vpd flag bit(0) and vpd addr field bits(1:15) at the same time. Bits 14:15 must be 0 to create dword aligned address. Write accomplished by pcie config write to legacy space address 0x40.
-- 2. Hardware will always read out precisely 4 bytes from vpd storage unit per specification. In this impelemntation, 4 bytes are written via I2C. vpd flag bit will be set to 1 when transfer is complete.
-- 3. Software polls vpd flag. When it sees the 1, it reads vpd data register at offset 0x44 for 4 bytes of vpd infromation. Operation is complete. Address and data fields may not be modified prior to flag being set.

-- VPD Write Procedure:
-- 1. Write 4 bytes of data to vpd data register (pci config offset 0x44)
-- 2. Write vpd address field to desired 4 byte location and write vpd flag to a 1 at the same time.
-- 3. Software monitors the vpd flag, and when set to 0, write operation is complete. Do not write to update vpd address or data fields before flag is reset to 0.

    vvpdadr_en <= vpd_0x40  and  (cseb_be_l(3)  or  cseb_be_l(2)  or 
                                 cseb_be_l(1)  or  cseb_be_l(0))  and  wren_pulse_in ;

    vvpdwrdat_en <= vpd_0x44  and  (cseb_be_l(3)  or  cseb_be_l(2)  or
                                 cseb_be_l(1)  or  cseb_be_l(0))  and  wren_pulse_in ;



   vpd: psl_hdk_vpd port map (
      clk => psl_clk,
      nperst => pci_pi_nperst0,
      user_lnk_up => user_lnk_up,

      vpd_adr_en => vvpdadr_en,
      vpd_dat_en => vvpdwrdat_en,
      vpd_wrdata => vsec_wrdata,

      vpd_adr => vpd40data,
      vpd_dat => vpd44data,

      i2c_cmdval => hi2c_cmdval,
      i2c_read => hi2c_rd,
      i2c_addr => hi2c_cmdin,
      i2c_data => hi2c_datain,
      i2c_dataval => hi2c_dataval,
      i2c_bytecnt => hi2c_bytecnt,

      i2ch_dataval => i2ch_dataval,
      i2ch_dataout => i2ch_dataout,
      i2ch_ready => i2ch_ready_q
    );

    i2ch_ready_d <= i2ch_ready;
    dff_i2ch_ready_q: psl_rise_dff PORT MAP (
         dout => i2ch_ready_q,
         din => i2ch_ready_d,
         clk   => psl_clk
    );

  hi2c_addr <= "1010001"; --target the second lowest pages of the EEPROM. First 4 bits must be "1010"
  hi2c_blk <= '0'; --not used
  hi2c_cntlrsel <= "000"; --not used


 -- ----------------------------------- --
 -- Flash Address Register              --
 -- ----------------------------------- --
    vfadr_en <= vsec_0x50  and  cseb_be_l(3)  and  cseb_be_l(2)  and 
 -- AM Feb27, 2017                               cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse ;
                                cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse_in ;

    endff_vsec_fadr: psl_en_rise_vdff GENERIC MAP ( width => 26 ) PORT MAP (
         dout => vsec_fadr,
         en => vfadr_en,
         din => vsec_wrdata(6 to 31),
         clk   => psl_clk
    );


    vsec50data <= ( "000000" & vsec_fadr );


    f_start_blk <= vsec50data(6 to 15) ;
    --v26bit f_read_start_addr = vsec_fadr;
 -- -- End Section -- --

 -- ----------------------------------- --
 -- Flash Mux                           --
 -- ----------------------------------- --
    f_read_start_addr <= vsec_fadr ;
    f_read_reqinternal <= flash_rd_req ;
 -- -- End Section -- --

 -- ----------------------------------- --
 -- Flash Size Register                 --
 -- ----------------------------------- --
    vfsize_en <= vsec_0x54  and  cseb_be_l(2)  and 
 -- AM Feb27, 2017                                cseb_be_l(3)  and  wren_pulse ;
                                 cseb_be_l(3)  and  wren_pulse_in ;


    endff_vsec_fsize: psl_en_rise_vdff GENERIC MAP ( width => 10 ) PORT MAP (
         dout => vsec_fsize,
         en => vfsize_en,
         din => vsec_wrdata(22 to 31),
         clk   => psl_clk
    );


    vsec54data <= ( "0000000000000000000000" & vsec_fsize );


    f_num_blocks <= std_logic_vector(unsigned(vsec_fsize) + 1) ;
    f_num_words_m1 <= vsec_fsize;


 -- -- End Section -- --

 -- ----------------------------------- --
 -- Flash Control / Status Register     --
 -- ----------------------------------- --
 -- AM Feb27, 2017   vfctl_en <= vsec_0x58  and  cseb_be_l(0)  and  wren_pulse ;
    vfctl_en <= vsec_0x58  and  cseb_be_l(0)  and  wren_pulse_in ;


    endff_f_program_req: psl_en_rise_dff PORT MAP (
         dout => f_program_reqinternal,
         en => vfctl_en,
         din => vsec_wrdata(5),
         clk   => psl_clk
    );

    endff_flash_rd_req: psl_en_rise_dff PORT MAP (
         dout => flash_rd_req,
         en => vfctl_en,
         din => vsec_wrdata(4),
         clk   => psl_clk
    );


    --concat(type=v32bit) (vsec58data, f_ready, f_done, 0b00, flash_rd_req, f_program_req, 0b0000000000, 
    --                                 f_stat_erase, f_stat_program, f_stat_read, 0b000, f_remainder);
    vsec58data <= ( f_ready & f_done & "00" & flash_rd_req & f_program_reqinternal & "0000000000" & f_stat_erase & f_stat_program & f_stat_read & f_program_data_valinternal & "00" & f_remainder );

 -- -- End Section -- --

 -- ------------------------------------------ --
 -- Flash Read / Write Data Port Register      --
 -- ------------------------------------------ --
    -- READ --
    vfrddp_read <= (vsec_0x5C)  and  cseb_be_l(3)  and  cseb_be_l(2)  and  --alpha data vpd not read from flash, shouldn't affect flash registers
                                               cseb_be_l(1)  and  cseb_be_l(0)  and  rden_pulse_in ;

    vfrddp_en <= f_read_data_val  and   not vfrddp_val  and  f_read_reqinternal ;

    vfrddp_val_d <=  not (vfrddp_read  and  vfrddp_val)  and  (f_read_data_val  or  vfrddp_val) and f_read_reqinternal;
    dff_vfrddp_val: psl_rise_dff PORT MAP (
         dout => vfrddp_val,
         din => vfrddp_val_d,
         clk   => psl_clk
    );


    f_read_data_ack <=  not vfrddp_val ;

    -- WRITE --
    vfwrdp_en <= vsec_0x5C  and  cseb_be_l(3)  and  cseb_be_l(2)  and 
 -- AM Feb27, 2017                                cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse  and  f_program_reqinternal ;
                                 cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse_in  and  f_program_reqinternal ;


    f_program_data <= vsec5Cdata ;

    f_program_data_val_d <=  not f_program_data_ack  and  (vfwrdp_en  or  f_program_data_valinternal) ;
    dff_f_program_data_val: psl_rise_dff PORT MAP (
         dout => f_program_data_valinternal,
         din => f_program_data_val_d,
         clk   => psl_clk
    );


    -- LATCH --
    vsec5Cdata_d <= f_read_data when f_read_reqinternal='1' else vsec_wrdata;

    vsec5C_reg_en <= vfrddp_en  or  (vfwrdp_en  and   not f_program_data_valinternal) ;

    endff_vsec5Cdata: psl_en_rise_vdff GENERIC MAP ( width => 32 ) PORT MAP (
         dout => vsec5Cdata,
         en => vsec5C_reg_en,
         din => vsec5Cdata_d,
         clk   => psl_clk
    );


 -- -- End Section -- --
--============================================================================================
---- Address Decode
--==============================================================================================--
    --reversebus(type=v33bit) (vsec_addr, cseb_addr_l);
    vsec_addr <= cseb_addr_l ;

    vsec_base <= '1' when (vsec_addr(21 to 24)  =  "0100") else '0';  -- 0x4xx Base for Xilinx --
    vpd_base <= '1' when (vsec_addr(21 to 24)  =  "0000") else '0';

    -- 5/1/2017 UltraScale+ - change from 0x40 to 0xB0
    vpd_0x40 <= vpd_base when (vsec_addr(25 to 32) = "10110000") else '0';  -- 0x0B0 -- VPD Capability Structure--
    vpd_0x44 <= vpd_base when (vsec_addr(25 to 32) = "10110100") else '0';  -- 0x0B4 -- VPD Data Port--

    vsec_0x00 <= vsec_base when (vsec_addr(25 to 32) = "00000000") else '0'; -- 0x00 -- Next Capability, Version, ID--
    vsec_0x04 <= vsec_base when (vsec_addr(25 to 32) = "00000100") else '0'; -- 0x04 -- VSEC Length, Rev, ID--
    vsec_0x08 <= vsec_base when (vsec_addr(25 to 32) = "00001000") else '0'; -- 0x08 -- Mode Control, Num AFUs--
    vsec_0x0C <= vsec_base when (vsec_addr(25 to 32) = "00001100") else '0'; -- 0x0C -- CAIA Version, PSL Version--

    vsec_0x10 <= vsec_base when (vsec_addr(25 to 32) = "00010000") else '0'; -- 0x10 -- Base Image Revision --
    vsec_0x14 <= vsec_base when (vsec_addr(25 to 32) = "00010100") else '0'; -- /* 0x14 -- Reserved --
    vsec_0x18 <= vsec_base when (vsec_addr(25 to 32) = "00011000") else '0'; -- /* 0x18 -- Reserved --
    vsec_0x1C <= vsec_base when (vsec_addr(25 to 32) = "00011100") else '0'; -- /* 0x1C -- Reserved --

    vsec_0x20 <= vsec_base when (vsec_addr(25 to 32) = "00100000") else '0'; -- 0x20 -- AFU Descriptor Offset --
    vsec_0x24 <= vsec_base when (vsec_addr(25 to 32) = "00100100") else '0'; -- 0x24 -- AFU Descriptor Size --
    vsec_0x28 <= vsec_base when (vsec_addr(25 to 32) = "00101000") else '0'; -- 0x28 -- Problem State Offset --
    vsec_0x2C <= vsec_base when (vsec_addr(25 to 32) = "00101100") else '0'; -- 0x2C -- Problem State Size --

    vsec_0x30 <= vsec_base when (vsec_addr(25 to 32) = "00110000") else '0'; -- /* 0x30 -- Reserved --
    vsec_0x34 <= vsec_base when (vsec_addr(25 to 32) = "00110100") else '0'; -- /* 0x34 -- Reserved --
    vsec_0x38 <= vsec_base when (vsec_addr(25 to 32) = "00111000") else '0'; -- /* 0x38 -- Reserved --
    vsec_0x3C <= vsec_base when (vsec_addr(25 to 32) = "00111100") else '0'; -- /* 0x3C -- Reserved --

    vsec_0x40 <= vsec_base when (vsec_addr(25 to 32) = "01000000") else '0'; -- 0x40 -- PSL Programming Port--
    vsec_0x44 <= vsec_base when (vsec_addr(25 to 32) = "01000100") else '0'; -- 0x44 -- PSL Programming Control--
    vsec_0x48 <= vsec_base when (vsec_addr(25 to 32) = "01001000") else '0'; -- /* 0x48 -- Reserved --
    vsec_0x4C <= vsec_base when (vsec_addr(25 to 32) = "01001100") else '0'; -- /* 0x4C -- Reserved --

    vsec_0x50 <= vsec_base when (vsec_addr(25 to 32) = "01010000") else '0'; -- 0x50 -- Flash Address Register--
    vsec_0x54 <= vsec_base when (vsec_addr(25 to 32) = "01010100") else '0'; -- 0x54 -- Flash Size Register--
    vsec_0x58 <= vsec_base when (vsec_addr(25 to 32) = "01011000") else '0'; -- 0x58 -- Flash Status / Control --
    vsec_0x5C <= vsec_base when (vsec_addr(25 to 32) = "01011100") else '0'; -- 0x5C -- Flash Data Port --

    vsec_0x60 <= vsec_base when (vsec_addr(25 to 32) = "01100000") else '0'; -- /* 0x60 -- Reserved --
    vsec_0x64 <= vsec_base when (vsec_addr(25 to 32) = "01100100") else '0'; -- /* 0x64 -- Reserved --
    vsec_0x68 <= vsec_base when (vsec_addr(25 to 32) = "01101000") else '0'; -- /* 0x68 -- Reserved --
    vsec_0x6C <= vsec_base when (vsec_addr(25 to 32) = "01101100") else '0'; -- /* 0x6C -- Reserved --

    vsec_0x70 <= vsec_base when (vsec_addr(25 to 32) = "01110000") else '0'; -- /* 0x70 -- Reserved --
    vsec_0x74 <= vsec_base when (vsec_addr(25 to 32) = "01110100") else '0'; -- /* 0x74 -- Reserved --
    vsec_0x78 <= vsec_base when (vsec_addr(25 to 32) = "01111000") else '0'; -- /* 0x78 -- Reserved --
--     vsec_0x7C <= vsec_base when (vsec_addr(25 to 32) = "01111100") else '0'; -- /* 0x7C -- Reserved --
  
--  cseb_waitrequest <= cseb_waitrequestinternal; 
  f_program_data_val <= f_program_data_valinternal; 
  f_program_req <= f_program_reqinternal; 
  f_read_req <= f_read_reqinternal; 


   -- -----------------------------------
   -- --- Register : psl_ptmon

    psl_ptmon_lo_en <= vsec_0x30  and  cseb_be_l(0)  and  cseb_be_l(2)  and
                                cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse_in ;
    psl_ptmon_hi_en <= vsec_0x34  and  cseb_be_l(0)  and  cseb_be_l(2)  and
                                cseb_be_l(1)  and  cseb_be_l(0)  and  wren_pulse_in ;

    endff_pslreg_psl_ptmon_temp_trip_q: psl_en_rise_vdff GENERIC MAP ( width => 8 ) PORT MAP (
         dout => pslreg_psl_ptmon_temp_trip_q,
         en => psl_ptmon_hi_en,
         din => vsec_wrdata(0 to 7),
         clk   => psl_clk
    );

    endff_pslreg_psl_ptmon_temp_en_q: psl_en_rise_dff PORT MAP (
         dout => pslreg_psl_ptmon_temp_en_q,
         en => psl_ptmon_hi_en,
         din => vsec_wrdata(15),
         clk   => psl_clk
    );

    endff_pslreg_psl_ptmon_pwr_trip_q: psl_en_rise_vdff GENERIC MAP ( width => 8 ) PORT MAP (
         dout => pslreg_psl_ptmon_pwr_trip_q,
         en => psl_ptmon_lo_en,
         din => vsec_wrdata(0 to 7),
         clk   => psl_clk
    );

    endff_pslreg_psl_ptmon_mon_en_q: psl_en_rise_dff PORT MAP (
         dout => pslreg_psl_ptmon_mon_en_q,
         en => psl_ptmon_lo_en,
         din => vsec_wrdata(14),
         clk   => psl_clk
    );

    endff_pslreg_psl_ptmon_pwr_en_q: psl_en_rise_dff PORT MAP (
         dout => pslreg_psl_ptmon_pwr_en_q,
         en => psl_ptmon_lo_en,
         din => vsec_wrdata(15),
         clk   => psl_clk
    );

    -- 0x30
    rddat_psl_ptmon(32 to 63) <= ( pslreg_psl_ptmon_pwr_trip_q & "000000" & pslreg_psl_ptmon_mon_en_q & pslreg_psl_ptmon_pwr_en_q & mon_power(0 to 15) );
    -- 0x34
    rddat_psl_ptmon(0 to 31)  <= ( pslreg_psl_ptmon_temp_trip_q & "0000000" & pslreg_psl_ptmon_temp_en_q & mon_temperature(0 to 15) );


    pslreg_psl_ptmon(0 to 7) <= pslreg_psl_ptmon_temp_trip_q ;
    pslreg_psl_ptmon(8) <= pslreg_psl_ptmon_temp_en_q ;
    pslreg_psl_ptmon(9 to 16) <= pslreg_psl_ptmon_pwr_trip_q ;
    pslreg_psl_ptmon(17) <= pslreg_psl_ptmon_mon_en_q ;
    pslreg_psl_ptmon(18) <= pslreg_psl_ptmon_pwr_en_q ;

    -- over_temp <= (mon_temperature(0 to 7) > pslreg_psl_ptmon(0 to 7))  and  pslreg_psl_ptmon(8) ;
    -- over_pwr <= (mon_power(0 to 7)       > pslreg_psl_ptmon(9 to 16) )  and  pslreg_psl_ptmon(18) ;
    mon_enable <= pslreg_psl_ptmon(17) ;

    -- Power Temperature Monitoring
    ptmon: psl_ptmon
      PORT MAP (
         mon_power => mon_power,
         mon_temperature => mon_temperature,
         mon_enable => mon_enable,
         aptm_req => aptm_req,
         ptma_grant => open,
         psl_clk => psl_clk
    );

    aptm_req <= '0' ;

END psl_vsec;
