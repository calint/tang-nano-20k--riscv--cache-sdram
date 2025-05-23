#!/bin/sh
set -e
cd $(dirname "$0")

echo copy common files
T9KPTH=../../tang-nano-9k--riscv--cache-psram
T20KPTH=..


cp -a $T9KPTH/src/core.sv $T20KPTH/src/
cp -a $T9KPTH/src/registers.sv $T20KPTH/src/
cp -a $T9KPTH/src/bram.sv $T20KPTH/src/
cp -a $T9KPTH/src/uarttx.sv $T20KPTH/src/
cp -a $T9KPTH/src/uartrx.sv $T20KPTH/src/
cp -a $T9KPTH/src/sdcard.sv $T20KPTH/src/
cp -a $T9KPTH/src/emulators/flash.sv $T20KPTH/src/emulators/

cp -arf $T9KPTH/src/ip/regymm/ $T20KPTH/src/ip/


rm -rf $T20KPTH/emulator
cp -ra $T9KPTH/emulator/ $T20KPTH/
rm $T20KPTH/emulator/osqa

rm -rf $T20KPTH/os/
cp -ra $T9KPTH/os/ $T20KPTH/
rm -f $T20KPTH/os/console_application
rm -f $T20KPTH/os/os
rm -f $T20KPTH/os/os.bin
rm -f $T20KPTH/os/os.dat
rm -f $T20KPTH/os/os.lst

cp -rfa $T9KPTH/.vscode/* $T20KPTH/.vscode/

cp -rfa $T9KPTH/scripts/* $T20KPTH/scripts/

echo run tests
../scripts/run-tests.sh

echo done
