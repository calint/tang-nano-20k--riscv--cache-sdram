#!/bin/sh
#
# tools used:
#   iverilog: Icarus Verilog version 12.0 (stable)
#        vvp: Icarus Verilog runtime version 12.0 (stable)
#
set -e
cd $(dirname "$0")

SRCPTH=../../src

iverilog -g2005-sv -Winfloop -pfileline=1 -o iverilog.vvp -s testbench testbench.sv \
    ../../impl/pnr/riscv.vo \
    $SRCPTH/emulators/flash.sv \
    $SRCPTH/emulators/MT48LC2M32B2.v \
    ~/apps/gowin/IDE/simlib/gw2a/prim_sim.v

vvp iverilog.vvp
rm iverilog.vvp
