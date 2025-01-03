# generated - do not edit (see `configuration.py`)

#
# scripts related configurations
#

BOARD_NAME="tangnano20k"
# used when flashing the bitstream to the FPGA

BITSTREAM_FILE="impl/pnr/riscv.fs"
# location of the bitstream file relative to project root

BITSTREAM_FLASH_TO_EXTERNAL=1
# 0 to flash the bitstream to the internal flash, 1 for the external flash

BITSTREAM_FILE_MAX_SIZE_BYTES=7340032
# used to check if the bitstream size is within the limit of flash storage

FIRMWARE_FILE_MAX_SIZE_BYTES=1048576
# used to check if the bitstream size is within the limit of flash storage

FIRMWARE_FLASH_OFFSET=0x00700000
# used to specify the offset in the flash storage where the firmware will be written
