#pragma once

// Builds small RV32 ELF files in memory for the unit tests.

#include <cstddef>
#include <cstdint>
#include <vector>

#include "byte_view.hpp"

namespace elftest {

// Offsets inside the ELF32 header and a program header.
inline constexpr std::size_t kEhdrSize = 52;
inline constexpr std::size_t kPhdrSize = 32;
inline constexpr std::size_t kEiClass = 4;
inline constexpr std::size_t kEiData = 5;
inline constexpr std::size_t kEType = 16;
inline constexpr std::size_t kEMachine = 18;
inline constexpr std::size_t kEEntry = 24;
inline constexpr std::size_t kEPhoff = 28;
inline constexpr std::size_t kEPhentsize = 42;
inline constexpr std::size_t kEPhnum = 44;
inline constexpr std::size_t kPType = 0;
inline constexpr std::size_t kPOffset = 4;
inline constexpr std::size_t kPVaddr = 8;
inline constexpr std::size_t kPFilesz = 16;
inline constexpr std::size_t kPMemsz = 20;

inline constexpr std::uint32_t kEntry = 0x80000000u;
inline constexpr std::uint32_t kSegmentBytes = 16;

using Bytes = std::vector<std::uint8_t>;

inline void put16(Bytes& b, std::size_t offset, std::uint16_t value) {
    b[offset] = static_cast<std::uint8_t>(value);
    b[offset + 1] = static_cast<std::uint8_t>(value >> 8);
}

inline void put32(Bytes& b, std::size_t offset, std::uint32_t value) {
    for (std::size_t i = 0; i < 4; ++i) {
        b[offset + i] = static_cast<std::uint8_t>(value >> (8 * i));
    }
}

inline florv::ByteView view(const Bytes& b) {
    return florv::ByteView{b.data(), b.size()};
}

// Offset of program header number index (0 is the non-load one, 1.. are the loads).
inline std::size_t phdr(std::size_t index) {
    return kEhdrSize + index * kPhdrSize;
}

// A valid RV32 executable: header, one non-load program header (4 bytes at file offset 0),
// loadCount PT_LOAD headers, then 16 bytes of payload per load. Load i sits at
// 0x80000000 + i * 0x1000, is filled with the byte 0xA0 + i, and has a memory size
// of 16 + i * 64.
inline Bytes makeElf(std::size_t loadCount) {
    const std::size_t phnum = loadCount + 1;
    const std::size_t payload = kEhdrSize + phnum * kPhdrSize;
    Bytes b(payload + loadCount * kSegmentBytes, 0);

    b[0] = 0x7F;
    b[1] = 'E';
    b[2] = 'L';
    b[3] = 'F';
    b[kEiClass] = 1;
    b[kEiData] = 1;
    put16(b, kEType, 2);
    put16(b, kEMachine, 0xF3);
    put32(b, kEEntry, kEntry);
    put32(b, kEPhoff, static_cast<std::uint32_t>(kEhdrSize));
    put16(b, kEPhentsize, static_cast<std::uint16_t>(kPhdrSize));
    put16(b, kEPhnum, static_cast<std::uint16_t>(phnum));

    // The non-load header has a real size, so a parser that forgot to skip it would list it.
    put32(b, phdr(0) + kPType, 0x70000003u);
    put32(b, phdr(0) + kPFilesz, 4);
    put32(b, phdr(0) + kPMemsz, 4);

    for (std::size_t i = 0; i < loadCount; ++i) {
        const std::size_t ph = phdr(i + 1);
        const std::size_t data = payload + i * kSegmentBytes;
        put32(b, ph + kPType, 1);
        put32(b, ph + kPOffset, static_cast<std::uint32_t>(data));
        put32(b, ph + kPVaddr, kEntry + static_cast<std::uint32_t>(i) * 0x1000u);
        put32(b, ph + kPFilesz, kSegmentBytes);
        put32(b, ph + kPMemsz, kSegmentBytes + static_cast<std::uint32_t>(i) * 64u);
        for (std::size_t n = 0; n < kSegmentBytes; ++n) {
            b[data + n] = static_cast<std::uint8_t>(0xA0 + i);
        }
    }
    return b;
}

}  // namespace elftest
