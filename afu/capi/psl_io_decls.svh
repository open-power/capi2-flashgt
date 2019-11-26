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
   output 	  ah_paren,
   input 	  ha_jval, // A valid job control command is present
   input [0:7] 	  ha_jcom, // Job control command opcode
   input 	  ha_jcompar, // Job control parity
   input [0:63]   ha_jea, // Save/Restore address
   input 	  ha_jeapar, // parity
   input [0:4] 	  ha_lop, //   lpc capp ttype
   input 	  ha_loppar, //   lpc capp ttype
   input [0:6] 	  ha_lsize, //   lpc size/secondary ttype
   input [0:11]   ha_ltag, //   lpc command tag
   output 	  ah_ldone, //   lpc operation is done
   output [0:11]  ah_ldtag, //   lpc tag identifying done operation
   output 	  ah_ldtagpar, //   lpc tag identifying done operation
   output [0:7]   ah_lroom, //   how many LPC/Internal commands
   output 	  ah_jrunning, // Accelerator is running
   output 	  ah_jdone, // Accelerator is finished
   output [0:63]  ah_jerror, // Accelerator error code. 0 = success
   output 	  ah_tbreq, // timebase request (not used)
   output 	  ah_jyield, // Accelerator wants to stop
   output 	  ah_jcack, 
   input 	  ha_pclock, // 250MHz clock

   // Accelerator Command Interface
   output 	  ah_cvalid, // A valid command is present
   output [0:7]   ah_ctag, // request id
   output 	  ah_ctagpar,
   output [0:12]  ah_com, // command PSL will execute
   output 	  ah_compar, // parity for command
   output [0:2]   ah_cpad, // prefetch inattributes
   output [0:2]   ah_cabt, // abort if translation intr is generated
   output [0:15]  ah_cch, // context
   output [0:63]  ah_cea, // Effective byte address for command
   output 	  ah_ceapar, // Effective byte address for command
   output [0:11]  ah_csize, // Number of bytes
   input [0:7] 	  ha_croom, // Commands PSL is prepared to accept

   // Accelerator Buffer Interface
   input 	  ha_brvalid, // A read transfer is present
   input [0:7] 	  ha_brtag, // Accelerator generated ID for read
   input 	  ha_brtagpar,
   input [0:5] 	  ha_brad, // half line index of read data; ha_brad(5) is the halfline sel for the read.
   output [0:3]   ah_brlat, // Read data ready latency
   output [0:511] ah_brdata, // Read data
   output [0:7]   ah_brpar, // Read data parity

   input 	  ha_bwvalid, // A write data transfer is present
   input [0:7] 	  ha_bwtag, // Accelerator ID of the write
   input 	  ha_bwtagpar,
   input [0:5] 	  ha_bwad, // half line index of write data
   input [0:511]  ha_bwdata, // Write data
   input [0:7] 	  ha_bwpar, // Write data parity
   input 	  ha_rvalid, // A response is present
   input [0:7] 	  ha_rtag, // Accelerator generated request ID
   input 	  ha_rtagpar,
   input [0:7] 	  ha_response, // response code
   input [0:8] 	  ha_rcredits, // twos compliment number of credits
   input [0:1] 	  ha_rcachestate, // Resultant Cache State
   input [0:12]   ha_rcachepos, // Cache location id

   // Accelerator MMIO Interface
   input 	  ha_mmval, // A valid MMIO is present
   input 	  ha_mmrnw, // 1 = read, 0 = write
   input 	  ha_mmdw, // 1 = doubleword, 0 = word
   input [0:23]   ha_mmad, // mmio address
   input 	  ha_mmcfg,
   input 	  ha_mmadpar,
   input [0:63]   ha_mmdata, // Write data
   input 	  ha_mmdatapar, // Write data
   output 	  ah_mmack, // Write is complete or Read is valid
   output [0:63]  ah_mmdata, // Read data
   output 	  ah_mmdatapar // Read data
