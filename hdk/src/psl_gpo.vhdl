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

library ieee, UNISIM;
use UNISIM.vcomponents.all;
use ieee.std_logic_1164.all;

ENTITY psl_gpo IS
  PORT(dataout:out std_logic;
       datain: in std_logic;
       oe: in std_logic);

END psl_gpo;

ARCHITECTURE psl_gpo OF psl_gpo IS

begin

OBUFT_inst : OBUFT
  port map (
  O     => dataout,  -- Buffer Output
  I     => datain,   -- Buffer Input
  T     => oe      -- 3-state enable input, high=input, low=output 
  );
  

END psl_gpo;
