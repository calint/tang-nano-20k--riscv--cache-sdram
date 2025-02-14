#!/bin/bash
set -e
cd $(dirname "$0")

echo " * build console application"
./make-console-application.sh
echo " * test console application"
qa-console/test.sh

echo " * build fpga flash binary"
./make-fpga-flash-binary.sh
echo " * build emulator"
../emulator/make.sh
echo " * test 'os.bin' with sd card 'sample.txt' using emulator"
qa-emulator/test.sh
