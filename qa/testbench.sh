#!/bin/sh
#
# runs the testbench in folder specified by first parameter
#
# tools used:
#   iverilog: Icarus Verilog version 12.0 (stable)
#        vvp: Icarus Verilog runtime version 12.0 (stable)
#
set -e
cd $(dirname "$0")

PRIMLIBPTH=~/apps/gowin/IDE/simlib/gw2a
SRCPTH=../../src

cd $1
pwd

iverilog -g2012 -Winfloop -pfileline=1 -o iverilog.vvp -s testbench \
    ~/apps/gowin/IDE/simlib/gw2a/prim_sim.v \
    $SRCPTH/ip/micron/MT48LC2M32B2.v \
    $SRCPTH/ip/etron/sdr2mx32.v \
    $SRCPTH/ip/sdram_controller_hs/sdram_controller_hs.vo \
    $SRCPTH/ip/regymm/sd_controller.v \
    $SRCPTH/configuration.sv \
    $SRCPTH/emulators/flash.sv \
    $SRCPTH/bram.sv \
    $SRCPTH/cache.sv \
    $SRCPTH/uarttx.sv \
    $SRCPTH/uartrx.sv \
    $SRCPTH/sdcard.sv \
    $SRCPTH/ramio.sv \
    $SRCPTH/registers.sv \
    $SRCPTH/core.sv \
    $SRCPTH/top.sv \
    testbench.sv

vvp iverilog.vvp
rm iverilog.vvp
