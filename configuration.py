#
# if file changed run `configuration-apply.py` and rebuild
#

BOARD_NAME = "tangnano20k"
# used when flashing the bitstream to the FPGA and creating the SDC file

CLOCK_FREQUENCY_HZ = 27_000_000
# frequency of clock in (signal 'clk')

CPU_FREQUENCY_HZ = 60_000_000
# frequency that CPU runs on

RAM_ADDRESS_BITWIDTH = 21
# 2 ^ 21 x 32 b = 8 MB SDRAM (according to hardware)

RAM_ADDRESSING_MODE = 2
# amount of data stored per address
#    mode:
#       0: 1 B (byte addressed)
#       1: 2 B
#       2: 4 B
#       3: 8 B

UART_BAUD_RATE = 115200
# 115200 baud, 8 bits, 1 stop bit, no parity

CACHE_COLUMN_INDEX_BITWIDTH = 3
# 2 ^ 3 = 8 entries (32 B) per cache line

CACHE_LINE_INDEX_BITWIDTH = 11
# 2 ^ 11 * 32 B = 64 KB unified instruction and data cache
#   1 to 6  : cache implemented with SSRAM
#   7 to 11 : cache implemented with BSRAM
#        12 : exceeds resources

FLASH_TRANSFER_FROM_ADDRESS = 0x70_0000
# flash read start address

FLASH_TRANSFER_BYTE_COUNT = 0x10_0000
# number of bytes to transfer from flash at startup (1 MB)

STARTUP_WAIT_CYCLES = 1_000_000
# cycles delay at startup for flash to be initiated

#
# scripts related configuration
#

BITSTREAM_FILE = "impl/pnr/riscv.fs"
# location of the bitstream file relative to project root

#
# configure for firmware to have 1 MB at the end of the flash storage of 8 MB
#

BITSTREAM_FLASH_TO_EXTERNAL = True
# False to flash the bitstream to the internal flash, True for the external flash

BITSTREAM_FILE_MAX_SIZE_BYTES = 0x70_0000
# used to check if the bitstream size is within the allocated space

FIRMWARE_FILE = "os/os.bin"
# location of the firmware file relative to project root

FIRMWARE_FILE_MAX_SIZE_BYTES = 0x10_0000
# used to check if the firmware size is within the allocated space

FIRMWARE_FLASH_OFFSET = 0x70_0000
# used to specify the offset in the flash storage where the firmware will be written
