// tests 'osqa::sdcard' on a sparse image larger than 4 GB, the image file is
// the argument and is resized by the test
#include "../src/sdcard.hpp"
#include <cstdio>
#include <cstdlib>

using namespace std;

// 5 GB and one sector, so sectors past the 32 bit byte offset exist
static uint64_t constexpr image_sector_count = 5 * (uint64_t(1) << 21) + 1;

// the first sector whose byte offset needs more than 32 bits
static uint32_t constexpr sector_above_4gb = uint32_t(1) << 23;

auto assert(bool const condition, int32_t const test_number) -> void {
    if (!condition) {
        printf("test %d FAILED\n", test_number);
        exit(test_number);
    }
}

// fills the buffer with bytes that differ per sector and position
static auto fill(osqa::sdcard& card, uint32_t const seed) -> void {
    for (size_t i = 0; i < osqa::sdcard::sector_size; ++i) {
        card.next_byte(uint8_t(seed + i * 7));
    }
}

static auto matches(osqa::sdcard& card, uint32_t const seed) -> bool {
    bool equal = true;
    for (size_t i = 0; i < osqa::sdcard::sector_size; ++i) {
        equal = card.next_byte() == uint8_t(seed + i * 7) && equal;
    }
    return equal;
}

auto main(int argc, char** argv) -> int {
    if (argc != 2) {
        printf("Usage: %s <image>\n", argv[0]);
        return 1;
    }

    char const* const image = argv[1];

    {
        osqa::sdcard card;
        assert(!card.open("/nonexistent/sdcard.img"), 1);
    }

    int const fd = open(image, O_RDWR);
    assert(fd != -1, 2);
    off_t const image_size =
        off_t(image_sector_count * osqa::sdcard::sector_size);
    assert(ftruncate(fd, image_size) == 0, 3);

    {
        osqa::sdcard card;
        assert(card.open(image), 4);
        assert(card.sector_count() == image_sector_count, 5);

        // a sector of a fresh sparse image reads zeros
        assert(card.read_sector(1), 6);
        bool zeros = true;
        for (size_t i = 0; i < osqa::sdcard::sector_size; ++i) {
            zeros = card.next_byte() == 0 && zeros;
        }
        assert(zeros, 7);

        // write then read back, the buffer is overwritten in between
        fill(card, 1);
        assert(card.write_sector(0), 8);
        fill(card, 2);
        assert(card.read_sector(0), 9);
        assert(matches(card, 1), 10);

        // a byte offset above 4 GB
        fill(card, 3);
        assert(card.write_sector(sector_above_4gb), 11);
        fill(card, 4);
        assert(card.read_sector(sector_above_4gb), 12);
        assert(matches(card, 3), 13);

        // the last sector
        uint32_t const last = uint32_t(image_sector_count - 1);
        fill(card, 5);
        assert(card.write_sector(last), 14);
        fill(card, 6);
        assert(card.read_sector(last), 15);
        assert(matches(card, 5), 16);

        // past the end the transfer fails and the image does not grow
        assert(!card.read_sector(last + 1), 17);
        assert(!card.write_sector(last + 1), 18);
        assert(!card.write_sector(0xffff'ffff), 19);

        // the index wraps to the first byte after a sector
        assert(card.read_sector(0), 20);
        uint8_t const first = card.next_byte();
        for (size_t i = 1; i < osqa::sdcard::sector_size; ++i) {
            card.next_byte();
        }
        assert(card.next_byte() == first, 21);
    }

    struct stat st{};
    assert(fstat(fd, &st) == 0 && st.st_size == image_size, 22);

    // the writes are in the file at their 64 bit offsets
    {
        osqa::sdcard card;
        assert(card.open(image), 23);
        assert(card.read_sector(sector_above_4gb), 24);
        assert(matches(card, 3), 25);
    }

    uint8_t byte{};
    off_t const offset =
        off_t(uint64_t(sector_above_4gb) * osqa::sdcard::sector_size + 1);
    assert(pread(fd, &byte, 1, offset) == 1 && byte == uint8_t(3 + 7), 26);

    close(fd);

    return 0;
}
