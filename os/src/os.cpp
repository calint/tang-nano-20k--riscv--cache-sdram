//
// source for the FPGA build
//
#include "os_config.hpp"

// standard types
using int8_t = char;
using uint8_t = unsigned char;
using int16_t = short;
using uint16_t = unsigned short;
using int32_t = int;
using uint32_t = unsigned int;
using int64_t = long long;
using uint64_t = unsigned long long;
using size_t = uint32_t;

// symbols that mark start and end of bss section
extern char __bss_start;
extern char __bss_end;

// symbol that marks the start of heap memory
extern char __heap_start;

static auto initiate_bss() -> void;
// freestanding does not automatically initialize bss section

static auto initiate_statics() -> void;
// freestanding does not automatically initiate statics

static auto exit(int code) -> void;
// FPGA has no exit

static constexpr char CHAR_CARRIAGE_RETURN = 0x0d;
// freestanding serial terminal uses carriage return for newline

#include "os_common.hpp"
// the platform independent source

// FPGA I/O

static auto led_set(int32_t const bits) -> void { *LED = bits; }

static auto uart_send_str(char const *str) -> void {
  while (*str) {
    while (*UART_OUT != -1)
      ;
    *UART_OUT = *str++;
  }
}

static auto uart_send_char(char const ch) -> void {
  while (*UART_OUT != -1)
    ;
  *UART_OUT = ch;
}

static auto uart_read_char() -> char {
  int ch;
  while ((ch = *UART_IN) == -1)
    ;
  return char(ch);
}

// simple test of FPGA memory
static auto action_mem_test() -> void {
  uart_send_str("testing memory (write)\r\n");
  char *ptr = &__heap_start;
  // uart_send_str(" heap starts at: ");
  // uart_send_hex_byte(char(uint32_t(ptr) >> 24));
  // uart_send_hex_byte(char(uint32_t(ptr) >> 16));
  // uart_send_char(':');
  // uart_send_hex_byte(char(uint32_t(ptr) >> 8));
  // uart_send_hex_byte(char(uint32_t(ptr)));
  // uart_send_str("\r\n");
  char const *const end = reinterpret_cast<char *>(MEMORY_END - 0x1'0000);
  // ??? 0x1'0000 bytes reserved for stack, something more solid would be better
  // ??? don't forget about this when the application grows
  char ch = 0;
  while (ptr < end) {
    *ptr = ch;
    ++ptr;
    ++ch;
  }
  uart_send_str("testing memory (read)\r\n");
  ptr = &__heap_start;
  // ptr = reinterpret_cast<char *>(0x1'0000);
  ch = 0;
  bool failed = false;
  while (ptr < end) {
    if (*ptr != ch) {
      uart_send_str("at ");
      uart_send_hex_byte(char(uint32_t(ptr) >> 24));
      uart_send_hex_byte(char(uint32_t(ptr) >> 16));
      uart_send_char(':');
      uart_send_hex_byte(char(uint32_t(ptr) >> 8));
      uart_send_hex_byte(char(uint32_t(ptr)));
      uart_send_str(" expected ");
      uart_send_hex_byte(ch);
      uart_send_str(" got ");
      uart_send_hex_byte(*ptr);
      uart_send_str("\r\n");
      failed = true;
    }
    ++ptr;
    ++ch;
  }

  if (failed) {
    uart_send_str("testing memory FAILED\r\n");
  } else {
    uart_send_str("testing memory succeeded\r\n");
  }
}

static auto action_sdcard_test_read() -> void {
  int8_t buf[512];
  sdcard_read_blocking(1, buf);
  for (size_t i = 0; i < sizeof(buf); ++i) {
    uart_send_char(buf[i]);
  }
  uart_send_str("\r\n");
}

static auto action_sdcard_test_write() -> void {
  int8_t const buf[512] =
      "Hello world! Writing to second sector on SD card!\r\n";
  sdcard_write_blocking(1, buf);
}

static auto action_sdcard_status() -> void {
  uint32_t const status = *SDCARD_STATUS;
  uart_send_str("SDCARD_STATUS: 0x");
  uart_send_hex_byte(char(status >> 24));
  uart_send_hex_byte(char(status >> 16));
  uart_send_char(':');
  uart_send_hex_byte(char(status >> 8));
  uart_send_hex_byte(char(status));
  uart_send_str("\r\n");
}

static auto sdcard_read_blocking(size_t const sector,
                                 int8_t *buffer512B) -> void {
  while (*SDCARD_BUSY)
    ;
  *SDCARD_READ_SECTOR = sector;
  while (*SDCARD_BUSY)
    ;
  for (size_t i = 0; i < 512; ++i) {
    *buffer512B = char(*SDCARD_NEXT_BYTE);
    ++buffer512B;
  }
}

static auto sdcard_write_blocking(size_t const sector,
                                  int8_t const *buffer512B) -> void {
  while (*SDCARD_BUSY)
    ;
  for (size_t i = 0; i < 512; ++i) {
    *SDCARD_NEXT_BYTE = *buffer512B;
    ++buffer512B;
  }
  *SDCARD_WRITE_SECTOR = sector;
  while (*SDCARD_BUSY)
    ;
}

// built-in function called by compiler
extern "C" auto memset(void *str, int ch, int n) -> void * {
  char *ptr = reinterpret_cast<char *>(str);
  while (n--) {
    *ptr = char(ch);
    ++ptr;
  }
  return str;
}

// built-in function called by compiler
extern "C" auto memcpy(void *dst, void const *src, size_t n) -> void * {
  char *p1 = reinterpret_cast<char *>(dst);
  char const *p2 = reinterpret_cast<char const *>(src);
  while (n--) {
    *p1 = *p2;
    ++p1;
    ++p2;
  }
  return dst;
}

// zero bss section
static auto initiate_bss() -> void {
  memset(&__bss_start, 0, &__bss_end - &__bss_start);
}

static auto initiate_statics() -> void {}

static auto exit(int code) -> void {}