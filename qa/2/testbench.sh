#!/bin/sh
#
# tools used:
#   iverilog: Icarus Verilog version 12.0 (stable)
#        vvp: Icarus Verilog runtime version 12.0 (stable)
#
set -e
cd $(dirname "$0")

SRCPTH=../../src

iverilog -g2012 -Winfloop -pfileline=1 -o iverilog.vvp -s testbench testbench.sv \
    ~/apps/gowin/IDE/simlib/gw2a/prim_sim.v \
    $SRCPTH/configuration.sv \
    $SRCPTH/emulators/flash.sv \
    $SRCPTH/emulators/MT48LC2M32B2.v \
    $SRCPTH/sdram_controller_hs/sdram_controller_hs.vo \
    $SRCPTH/gowin_rpll/gowin_rpll.v \
    $SRCPTH/bram.sv \
    $SRCPTH/cache.sv \
    $SRCPTH/ramio.sv \
    $SRCPTH/uarttx.sv \
    $SRCPTH/uartrx.sv \
    $SRCPTH/core.sv \
    $SRCPTH/registers.sv \
    $SRCPTH/top.sv

vvp iverilog.vvp
rm iverilog.vvp
