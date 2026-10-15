// tests the SD card of the emulator through its memory mapped registers, the
// way the firmware uses them; exits with 0 or the number of the failed test
//
// the image is a sparse file of 5 GB and one sector made by 'test.sh'
#include "../src/main_config.hpp"
#include <cstddef>
#include <cstdint>

// the entry at address 0: the stack below the end of memory, the exit code of
// 'run' in a0 at 'ebreak'; the constants of 'main_config.hpp' leave a data
// section current
asm(R"(
    .text
    .global _start
_start:
    li sp, 0x800000
    call run
    ebreak
)");

using namespace std;

static size_t constexpr sector_size = 512;

// the first sector whose byte offset needs more than 32 bits
static uint32_t constexpr sector_above_4gb = uint32_t(1) << 23;

// the last sector of the image
static uint32_t constexpr last_sector = 5 * (uint32_t(1) << 21);

static auto io(uint32_t const address) -> uint32_t volatile* {
    return reinterpret_cast<uint32_t volatile*>(address);
}

static auto wait_while_busy() -> void {
    while (*io(osqa::sdcard_busy) != 0) {
    }
}

static auto sdcard_read_blocking(uint32_t const sector, uint8_t* buffer)
    -> void {
    wait_while_busy();
    *io(osqa::sdcard_read_sector) = sector;
    wait_while_busy();
    for (size_t i = 0; i < sector_size; ++i) {
        buffer[i] = uint8_t(*io(osqa::sdcard_next_byte));
    }
}

static auto sdcard_write_blocking(uint32_t const sector, uint8_t const* buffer)
    -> void {
    wait_while_busy();
    for (size_t i = 0; i < sector_size; ++i) {
        *io(osqa::sdcard_next_byte) = buffer[i];
    }
    *io(osqa::sdcard_write_sector) = sector;
    wait_while_busy();
}

// bytes that differ per sector and position
static auto fill(uint8_t* buffer, uint32_t const seed) -> void {
    for (size_t i = 0; i < sector_size; ++i) {
        buffer[i] = uint8_t(seed + i * 7);
    }
}

static auto matches(uint8_t const* buffer, uint32_t const seed) -> bool {
    for (size_t i = 0; i < sector_size; ++i) {
        if (buffer[i] != uint8_t(seed + i * 7)) {
            return false;
        }
    }
    return true;
}

// writes the sector with the seed, overwrites the buffer, reads it back
static auto round_trip(uint32_t const sector, uint32_t const seed) -> bool {
    uint8_t buffer[sector_size];
    fill(buffer, seed);
    sdcard_write_blocking(sector, buffer);
    fill(buffer, seed + 1);
    sdcard_read_blocking(sector, buffer);
    return matches(buffer, seed);
}

extern "C" auto run() -> int {
    uint8_t buffer[sector_size];

    // a sector of a fresh sparse image reads zeros
    sdcard_read_blocking(1, buffer);
    for (size_t i = 0; i < sector_size; ++i) {
        if (buffer[i] != 0) {
            return 1;
        }
    }

    if (!round_trip(0, 1)) {
        return 2;
    }

    // a byte offset above 4 GB, 'test.sh' checks the bytes in the image
    if (!round_trip(sector_above_4gb, 3)) {
        return 3;
    }

    if (!round_trip(last_sector, 5)) {
        return 4;
    }

    // the other sectors are unchanged
    sdcard_read_blocking(0, buffer);
    if (!matches(buffer, 1)) {
        return 5;
    }

    return 0;
}
