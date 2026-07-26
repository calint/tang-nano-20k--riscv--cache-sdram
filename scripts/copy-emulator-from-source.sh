#!/bin/sh
set -e
cd $(dirname "$0")

cd ..
rm -rf emulator
cp -rav ../tang-nano-9k--riscv--cache-psram/emulator .
emulator/qa/test.sh
