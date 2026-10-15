//
// SD card of the FPGA: a sector buffer filled from or written to an image
// file one sector at a time, so the image can be larger than memory
//
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace osqa {

using namespace std;

class sdcard final {
  public:
    static size_t constexpr sector_size = 512;

  private:
    int fd_{-1};
    // a partial sector at the end of the image is not addressable
    uint64_t sector_count_{};
    array<uint8_t, sector_size> buffer_{};
    // wraps like the 9 bit index of the hardware, so a transfer always moves
    // a whole sector
    size_t buffer_index_{};

  public:
    sdcard() = default;
    sdcard(sdcard const&) = delete;
    auto operator=(sdcard const&) -> sdcard& = delete;

    ~sdcard() {
        if (fd_ != -1) {
            close(fd_);
        }
    }

    // opens the image for reading and writing, false when it cannot be opened
    auto open(char const* const file_name) -> bool {
        fd_ = ::open(file_name, O_RDWR);
        if (fd_ == -1) {
            return false;
        }

        struct stat st{};
        if (fstat(fd_, &st) == -1) {
            close(fd_);
            fd_ = -1;
            return false;
        }

        sector_count_ = uint64_t(st.st_size) / sector_size;
        return true;
    }

    auto sector_count() const -> uint64_t { return sector_count_; }

    // copies the sector to the buffer, false when it is past the end of the
    // image or the read fails
    auto read_sector(uint32_t const sector) -> bool {
        if (sector >= sector_count_) {
            return false;
        }

        return pread(fd_, buffer_.data(), sector_size, offset(sector)) ==
               ssize_t(sector_size);
    }

    // copies the buffer to the sector, false when it is past the end of the
    // image or the write fails
    auto write_sector(uint32_t const sector) -> bool {
        if (sector >= sector_count_) {
            return false;
        }

        return pwrite(fd_, buffer_.data(), sector_size, offset(sector)) ==
               ssize_t(sector_size);
    }

    // the byte at the index, the index advances
    auto next_byte() -> uint8_t {
        uint8_t const byte = buffer_[buffer_index_];
        advance();
        return byte;
    }

    // stores the byte at the index, the index advances
    auto next_byte(uint8_t const byte) -> void {
        buffer_[buffer_index_] = byte;
        advance();
    }

  private:
    auto advance() -> void {
        buffer_index_ = (buffer_index_ + 1) % sector_size;
    }

    // the byte offset is 64 bit, images can be larger than 4 GB
    static auto offset(uint32_t const sector) -> off_t {
        return off_t(uint64_t(sector) * sector_size);
    }
};

} // namespace osqa
