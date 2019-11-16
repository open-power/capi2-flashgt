#!/bin/sh

# 
# FlashGT+ 
# generate hex files from .elf using a temporary vivado project
#

input=$1
output=$2
mkdir -p tmp/$output
rm -rf tmp/ublaze_0
cd tmp
INPUTELF=$input OUTDIR=$output vivado -journal vivado.jou -log vivado.log -mode batch -source ../nvme_control_ublaze.tcl -notrace 
cp $output/*.mem ../$output

