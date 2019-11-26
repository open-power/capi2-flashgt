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

ENTITY psl_reversebus16 IS
  PORT(dest: out std_logic_vector(0 to 15);
       din: in std_logic_vector(0 to 15));

END psl_reversebus16;

ARCHITECTURE psl_reversebus16 OF psl_reversebus16 IS

--Signal version: std_logic_vector(0 to 31);  -- int

begin

--    version <= "00000000000000000000000000000010" ;
    dest <= ( din(15) & din(14) & din(13) & din(12) & din(11) & din(10) & din(9) & din(8) & din(7) & din(6) & din(5) & din(4) & din(3) & din(2) & din(1) & din(0) );

END psl_reversebus16;
