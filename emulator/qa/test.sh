#!/bin/sh
set -e
cd "$(dirname "$0")"

echo " * build rv32i for tests"

CXX="g++ -std=c++23 -O3 -fno-rtti -fno-exceptions -Wfatal-errors -Werror -Wall -Wextra -Wpedantic \
    -Wconversion -Wsign-conversion -Wswitch-default -Wimplicit-fallthrough \
    -Wshadow -Wlogical-op -Wnon-virtual-dtor -Wcast-align -Woverloaded-virtual \
    -Wduplicated-cond -Wduplicated-branches -Wnull-dereference -Wuseless-cast \
    -Wdouble-promotion -Wmisleading-indentation -Wformat=2"

CMD="$CXX -o osqa-test main.cpp"
#echo
#echo $CMD
#echo
$CMD

ls -l --color osqa-test

#
# compile test cases
#
CC=riscv64-elf-g++
OBJCOPY=riscv64-elf-objcopy
OBJDUMP=riscv64-elf-objdump

SRC=ram.S
BIN=${SRC%.*}

# -mstrict-align \
$CC -std=c++23 \
    -march=rv32i \
    -mabi=ilp32 \
    -O0 \
    -ffreestanding \
    -nostartfiles \
    -nostdlib \
    -fno-pic \
    -Wfatal-errors \
    -Wall -Wextra -pedantic \
    -Wl,-Ttext=0x0 \
    -Wl,--no-relax \
    -fno-toplevel-reorder \
    -o $BIN $SRC

$OBJCOPY $BIN --output-target=binary $BIN.bin
$OBJDUMP --disassembler-options=numeric,no-aliases --disassemble --reloc $BIN >$BIN.lst

rm $BIN

./osqa-test

echo " * build sd card test"

$CXX -o sdcard-test sdcard.cpp

# sparse images, sized above 4 GB without using the space
IMAGE="$(mktemp)"
FIRMWARE_IMAGE="$(mktemp)"
trap 'rm -f "$IMAGE" "$FIRMWARE_IMAGE"' EXIT
./sdcard-test "$IMAGE"

echo " * run sd card firmware test in the emulator"

../make.sh >/dev/null

SRC=sdcard-firmware.cpp
BIN=${SRC%.*}

# no loop is turned into a call of 'memset' or 'memcpy', there is no library
$CC -std=c++23 \
    -march=rv32i \
    -mabi=ilp32 \
    -O2 \
    -ffreestanding \
    -fno-tree-loop-distribute-patterns \
    -nostartfiles \
    -nostdlib \
    -fno-pic \
    -Wfatal-errors \
    -Wall -Wextra -pedantic \
    -Wl,-Ttext=0x0 \
    -Wl,--no-relax \
    -fno-toplevel-reorder \
    -o $BIN $SRC

$OBJCOPY $BIN --output-target=binary $BIN.bin
$OBJDUMP --disassembler-options=numeric,no-aliases --disassemble --reloc $BIN >$BIN.lst

rm $BIN

# 5 GB and one sector
truncate -s $((5 * 1024 * 1024 * 1024 + 512)) "$FIRMWARE_IMAGE"

../osqa $BIN.bin "$FIRMWARE_IMAGE" </dev/null || {
    echo "sd card firmware test $? FAILED"
    exit 1
}

# the sector above 4 GB is in the image: bytes 3, 10, 17 and 24 of the
# pattern 'seed + i * 7' with seed 3
BYTES="$(od -An -tu1 -j $((8388608 * 512)) -N4 "$FIRMWARE_IMAGE" | tr -s ' ')"
if [ "$BYTES" != " 3 10 17 24" ]; then
    echo "sd card image check FAILED: '$BYTES'"
    exit 1
fi

echo "test: PASSED"
