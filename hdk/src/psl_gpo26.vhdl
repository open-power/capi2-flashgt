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

ENTITY psl_gpo26 IS
  PORT(pin: out std_logic_vector(0 to 25);
       od: in std_logic_vector(0 to 25);
       oe: in std_logic);   -- 0: output 1: input

END psl_gpo26;

ARCHITECTURE psl_gpo26 OF psl_gpo26 IS

Component psl_gpo
  PORT(dataout: out std_logic;
       datain: in std_logic;
       oe: in  std_logic );
End Component psl_gpo;

begin

io_0: psl_gpo PORT MAP ( dataout=>pin(0), datain=>od(0), oe=>oe );
io_1: psl_gpo PORT MAP ( dataout=>pin(1), datain=>od(1), oe=>oe );
io_2: psl_gpo PORT MAP ( dataout=>pin(2), datain=>od(2), oe=>oe );
io_3: psl_gpo PORT MAP ( dataout=>pin(3), datain=>od(3), oe=>oe );
io_4: psl_gpo PORT MAP ( dataout=>pin(4), datain=>od(4), oe=>oe );
io_5: psl_gpo PORT MAP ( dataout=>pin(5), datain=>od(5), oe=>oe );
io_6: psl_gpo PORT MAP ( dataout=>pin(6), datain=>od(6), oe=>oe );
io_7: psl_gpo PORT MAP ( dataout=>pin(7), datain=>od(7), oe=>oe );
io_8: psl_gpo PORT MAP ( dataout=>pin(8), datain=>od(8), oe=>oe );
io_9: psl_gpo PORT MAP ( dataout=>pin(9), datain=>od(9), oe=>oe );
io_10: psl_gpo PORT MAP ( dataout=>pin(10), datain=>od(10), oe=>oe );
io_11: psl_gpo PORT MAP ( dataout=>pin(11), datain=>od(11), oe=>oe );
io_12: psl_gpo PORT MAP ( dataout=>pin(12), datain=>od(12), oe=>oe );
io_13: psl_gpo PORT MAP ( dataout=>pin(13), datain=>od(13), oe=>oe );
io_14: psl_gpo PORT MAP ( dataout=>pin(14), datain=>od(14), oe=>oe );
io_15: psl_gpo PORT MAP ( dataout=>pin(15), datain=>od(15), oe=>oe );
io_16: psl_gpo PORT MAP ( dataout=>pin(16), datain=>od(16), oe=>oe );
io_17: psl_gpo PORT MAP ( dataout=>pin(17), datain=>od(17), oe=>oe );
io_18: psl_gpo PORT MAP ( dataout=>pin(18), datain=>od(18), oe=>oe );
io_19: psl_gpo PORT MAP ( dataout=>pin(19), datain=>od(19), oe=>oe );
io_20: psl_gpo PORT MAP ( dataout=>pin(20), datain=>od(20), oe=>oe );
io_21: psl_gpo PORT MAP ( dataout=>pin(21), datain=>od(21), oe=>oe );
io_22: psl_gpo PORT MAP ( dataout=>pin(22), datain=>od(22), oe=>oe );
io_23: psl_gpo PORT MAP ( dataout=>pin(23), datain=>od(23), oe=>oe );
io_24: psl_gpo PORT MAP ( dataout=>pin(24), datain=>od(24), oe=>oe );
io_25: psl_gpo PORT MAP ( dataout=>pin(25), datain=>od(25), oe=>oe );

END psl_gpo26;
