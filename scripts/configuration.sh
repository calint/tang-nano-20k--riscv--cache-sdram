BOARD_NAME="tangnano20k"
# used when flashing the bitstream to the FPGA

#
# configure for firmware to have 1 MB at the end of the flash storage of 8 MB
#

BITSTREAM_FLASH_TO_EXTERNAL=1
# 0 to flash the bitstream to the internal flash, 1 for the external flash

BITSTREAM_FILE_MAX_SIZE_BYTES=7340032 # 7 MB
# used to check if the bitstream size is within the allocated space

FIRMWARE_FILE_MAX_SIZE_BYTES=1048576 # 1 MB
# used to check if the bitstream size is within the allocated space

FIRMWARE_FLASH_OFFSET=0x700000
# used to specify the offset in the flash storage where the bitstream will be written