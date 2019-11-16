
#/ *!***************************************************************************
#/ *! Copyright 2019 International Business Machines
#/ *!
#/ *! Licensed under the Apache License, Version 2.0 (the "License");
#/ *! you may not use this file except in compliance with the License.
#/ *! You may obtain a copy of the License at
#/ *! http://www.apache.org/licenses/LICENSE-2.0 
#/ *!
#/ *! The patent license granted to you in Section 3 of the License, as applied
#/ *! to the "Work," hereby includes implementations of the Work in physical form. 
#/ *!
#/ *! Unless required by applicable law or agreed to in writing, the reference design
#/ *! distributed under the License is distributed on an "AS IS" BASIS,
#/ *! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#/ *! See the License for the specific language governing permissions and
#/ *! limitations under the License.
#/ *!***************************************************************************

#
# FlashGT+ Microblaze controller 
#

ARCH = mb
PROGRAM = mb_nvme_control
MEM = ublaze_0_blk_mem_gen_0_0.mem

# check enviroment
ifeq ("$(shell { type $(ARCH)-as; } 2>/dev/null)","")
$(error mb-as not found.  Xilinx SDK with gnu microblaze assembler must be on the PATH)
endif

ifeq ($(shell { type vivado; } 2>/dev/null)","")
$(error vivado not found.  Xilinx vivado must be on the PATH)
endif

all : $(MEM) $(MEM).sim

$(PROGRAM).s: $(PROGRAM).S
	$(CPP) $(PROGRAM).S -o $(PROGRAM).s

$(PROGRAM).sim.s: $(PROGRAM).S
	$(CPP) -DSIM $(CPPFLAGS) $(PROGRAM).S -o $(PROGRAM).sim.s

$(PROGRAM).elf : $(PROGRAM).s $(PROGRAM).linkerscript
	$(ARCH)-as -mlittle-endian $(PROGRAM).s -o $(PROGRAM).o
	$(ARCH)-ld -EL -T $(PROGRAM).linkerscript $(PROGRAM).o -o $(PROGRAM).elf
	$(ARCH)-size $(PROGRAM).elf

$(PROGRAM).sim.elf : $(PROGRAM).sim.s $(PROGRAM).linkerscript
	$(ARCH)-as -mlittle-endian $(PROGRAM).sim.s -o $(PROGRAM).sim.o
	$(ARCH)-ld -EL -T $(PROGRAM).linkerscript $(PROGRAM).sim.o -o $(PROGRAM).sim.elf
	$(ARCH)-size $(PROGRAM).sim.elf


$(MEM).sim: $(PROGRAM).sim.elf
	./gen_mem.sh $(PROGRAM).sim.elf $(MEM).sim

$(MEM): $(PROGRAM).elf
	./gen_mem.sh $(PROGRAM).elf $(MEM)

clean :
	rm -f $(PROGRAM).o $(PROGRAM).elf $(PROGRAM).s
	rm -f $(PROGRAM).sim.o $(PROGRAM).sim.elf $(PROGRAM).sim.s
	rm -rf tmp
	rm -f $(MEM) $(MEM).sim
