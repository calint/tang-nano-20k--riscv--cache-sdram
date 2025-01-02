#!/bin/sh
set -e
cd $(dirname "$0")

# default configuration
FIRMWARE_FILE="os/os.bin"
FIRMWARE_FLASH_OFFSET=0x00000000
FIRMWARE_FILE_MAX_SIZE_BYTES=0x100000

# override configuration
. ./configuration.sh

cd ..

echo
echo "building firmware"

os/make-fpga-flash-binary.sh

# check result
if [ ! -f "$FIRMWARE_FILE" ]; then
    echo
    echo -e "\e[31mbuild failed. firmware file '$FIRMWARE_FILE' not created.\e[0m"
    exit 1
fi

# check file size
FILE_SIZE=$(stat -c %s "$FIRMWARE_FILE")

echo -e "\e[32m"
echo "file: $FIRMWARE_FILE"
echo "size: $FILE_SIZE B"
echo " max: $FIRMWARE_FILE_MAX_SIZE_BYTES B"
echo -e "\e[0m"

if [ "$FILE_SIZE" -gt "$FIRMWARE_FILE_MAX_SIZE_BYTES" ]; then
    echo -e "\e[31mfirmware size exceeds allocated flash storage.\e[0m"
    exit 1
fi

echo "flashing '$FIRMWARE_FILE' to '$BOARD_NAME' at offset $FIRMWARE_FLASH_OFFSET"
echo

openFPGALoader --offset $FIRMWARE_FLASH_OFFSET --verify --external-flash "$FIRMWARE_FILE"