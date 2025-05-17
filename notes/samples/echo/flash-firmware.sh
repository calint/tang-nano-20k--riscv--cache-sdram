#!/bin/sh
set -e
cd $(dirname "$0")

openFPGALoader -b tangnano20k --write-flash --external-flash --offset 0x700000 firmware.bin
