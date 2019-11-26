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

ENTITY psl_gpo1 IS
  PORT(pin: out std_logic;
       od: in std_logic;
       oe: in std_logic);              -- 0: output 1: input

END psl_gpo1;

ARCHITECTURE psl_gpo1 OF psl_gpo1 IS

Component psl_gpo
  PORT(dataout: out std_logic;
       datain: in std_logic;
       oe: in  std_logic );
End Component psl_gpo;

begin

io_0: psl_gpo PORT MAP ( dataout=>pin, datain=>od, oe=>oe );

END psl_gpo1;
