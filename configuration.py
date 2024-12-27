#
# if file changed run `configuration-apply.py` and rebuild
#

RAM_ADDRESS_BITWIDTH = 23
# 2^23 = 8 MB SDRAM (according to hardware)

UART_BAUD_RATE = 115200
# 115200 baud, 8 bits, 1 stop bit, no parity

CACHE_LINE_INDEX_BITWIDTH = 7
# 2^7*32 = 4 KB unified instruction and data cache

FLASH_TRANSFER_BYTES = 4096  # 0x0020_0000
# number of bytes to transfer from flash at startup (2 MB)

STARTUP_WAIT_CYCLES = 0  # 1_000_000
# cycles delay at startup for flash to be initiated
