#!/bin/sh
set -e
cd $(dirname "$0")

T9KPTH=../../tang-nano-9k--riscv--cache-psram
T20KPTH=..

cp -a $T9KPTH/configuration-apply.py $T20KPTH/
cp -a $T9KPTH/build-using-gowin.sh $T20KPTH/
cp -a $T9KPTH/program-fpga.sh $T20KPTH/
cp -a $T9KPTH/make-and-flash-os.sh $T20KPTH/
cp -a $T9KPTH/flash-fpga.sh $T20KPTH/
cp -a $T9KPTH/src/core.sv $T20KPTH/src/
cp -a $T9KPTH/src/registers.sv $T20KPTH/src/
cp -a $T9KPTH/src/bram.sv $T20KPTH/src/
cp -a $T9KPTH/src/uarttx.sv $T20KPTH/src/
cp -a $T9KPTH/src/uartrx.sv $T20KPTH/src/

rm -rf $T20KPTH/emulator
rm -rf $T20KPTH/os

cp -ra $T9KPTH/emulator $T20KPTH/
cp -ra $T9KPTH/os $T20KPTH/

../configuration-apply.py
