#!/bin/sh
set -e
cd $(dirname "$0")

echo copy common files
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
rm $T20KPTH/emulator/osqa

cp -ra $T9KPTH/os $T20KPTH/
rm -f $T20KPTH/os/console_application
rm -f $T20KPTH/os/os
rm -f $T20KPTH/os/os.bin
rm -f $T20KPTH/os/os.dat
rm -f $T20KPTH/os/os.lst

rm -rf $T20KPTH/notes/samples
cp -ra $T9KPTH/notes/samples $T20KPTH/notes/

echo apply configuraiton
../configuration-apply.py

echo make emulator and firmware
../emulator/make.sh
../os/make-console-application.sh
../os/make-fpga-flash-binary.sh

echo done