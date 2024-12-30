#
# if file changed run `configuration-apply.py` and rebuild
#

BOARD_NAME = "tang_nano_20k"
# used when generating files

CLOCK_FREQUENCY_HZ = 27_000_000
# frequency of in clock (signal 'clk')

CPU_FREQUENCY_HZ = 27_000_000
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

CACHE_LINE_INDEX_BITWIDTH = 1
# 2 ^ 11 * 32 B = 64 KB unified instruction and data cache
#   1 to 6  : cache implemented with SSRAM; max freq 66 MHz
#   7 to 11 : cache implemented with BSRAM; max freq 52 MHz

FLASH_TRANSFER_FROM_ADDRESS = 0
# flash read start address

FLASH_TRANSFER_BYTE_COUNT = 2048  # 0x0020_0000
# number of bytes to transfer from flash at startup (2 MB)

STARTUP_WAIT_CYCLES = 0  # 1_000_000
# cycles delay at startup for flash to be initiated
