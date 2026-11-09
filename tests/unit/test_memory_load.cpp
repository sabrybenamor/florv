#include <cstdint>

#include "doctest.h"
#include "elf_builder.hpp"
#include "elf_image.hpp"
#include "memory.hpp"

using florv::ElfImage;
using florv::Memory;
using florv::MemStatus;
using namespace elftest;

namespace {

// makeElf(2) gives these two segments.
constexpr std::uint32_t kFirst = 0x80000000u;   // 16 bytes of 0xA0, nothing beyond
constexpr std::uint32_t kSecond = 0x80001000u;  // 16 bytes of 0xA1, then 64 zero bytes
constexpr std::uint32_t kSecondMemsz = kSegmentBytes + 64u;

constexpr std::uint8_t kDirt = 0xFF;

void fill(Memory& ram, std::uint32_t addr, std::uint32_t count, std::uint8_t value) {
    for (std::uint32_t i = 0; i < count; ++i) {
        REQUIRE(ram.write8(addr + i, value) == MemStatus::Ok);
    }
}

// How many of the count bytes starting at addr hold value.
std::uint32_t countEqual(const Memory& ram, std::uint32_t addr, std::uint32_t count,
                         std::uint8_t value) {
    std::uint32_t equal = 0;
    for (std::uint32_t i = 0; i < count; ++i) {
        std::uint8_t byte = 0;
        REQUIRE(ram.read8(addr + i, byte) == MemStatus::Ok);
        if (byte == value) {
            ++equal;
        }
    }
    return equal;
}

MemStatus load(Memory& ram, const Bytes& file) {
    const auto image = ElfImage::parse(view(file));
    REQUIRE(image.has_value());
    return ram.loadSegments(*image);
}

}  // namespace

TEST_CASE("Memory: loadSegments copies each segment to its address") {
    Memory ram;
    REQUIRE(load(ram, makeElf(2)) == MemStatus::Ok);

    CHECK(countEqual(ram, kFirst, kSegmentBytes, 0xA0) == kSegmentBytes);
    CHECK(countEqual(ram, kSecond, kSegmentBytes, 0xA1) == kSegmentBytes);
}

TEST_CASE("Memory: loadSegments zero-fills a .bss-style tail over old contents") {
    Memory ram;
    fill(ram, kSecond - 8, kSecondMemsz + 16, kDirt);
    REQUIRE(load(ram, makeElf(2)) == MemStatus::Ok);

    CHECK(countEqual(ram, kSecond, kSegmentBytes, 0xA1) == kSegmentBytes);
    CHECK(countEqual(ram, kSecond + kSegmentBytes, 64, 0x00) == 64);
}

TEST_CASE("Memory: loadSegments leaves the bytes around a segment alone") {
    Memory ram;
    fill(ram, kFirst, 32, kDirt);
    fill(ram, kSecond - 8, kSecondMemsz + 16, kDirt);
    REQUIRE(load(ram, makeElf(2)) == MemStatus::Ok);

    CHECK(countEqual(ram, kFirst + kSegmentBytes, 16, kDirt) == 16);
    CHECK(countEqual(ram, kSecond - 8, 8, kDirt) == 8);
    CHECK(countEqual(ram, kSecond + kSecondMemsz, 8, kDirt) == 8);
}

TEST_CASE("Memory: loadSegments with no segments changes nothing") {
    Memory ram;
    fill(ram, kFirst, 32, kDirt);
    REQUIRE(load(ram, makeElf(0)) == MemStatus::Ok);

    CHECK(countEqual(ram, kFirst, 32, kDirt) == 32);
}

TEST_CASE("Memory: a segment may end on the last byte of memory") {
    Memory ram;
    const std::uint32_t end = ram.base() + ram.size();
    Bytes file = makeElf(2);
    fill(ram, end - kSecondMemsz, kSecondMemsz, kDirt);

    SUBCASE("exactly on the last byte") {
        put32(file, phdr(2) + kPVaddr, end - kSecondMemsz);
        REQUIRE(load(ram, file) == MemStatus::Ok);
        CHECK(countEqual(ram, end - kSecondMemsz, kSegmentBytes, 0xA1) == kSegmentBytes);
        CHECK(countEqual(ram, end - 64, 64, 0x00) == 64);
    }
    SUBCASE("one byte further is out of range") {
        put32(file, phdr(2) + kPVaddr, end - kSecondMemsz + 1);
        CHECK(load(ram, file) == MemStatus::OutOfRange);
        CHECK(countEqual(ram, end - kSecondMemsz, kSecondMemsz, kDirt) == kSecondMemsz);
    }
}

TEST_CASE("Memory: a segment that does not fit is refused and nothing is written") {
    Memory ram;
    Bytes file = makeElf(2);
    fill(ram, kFirst, 32, kDirt);
    fill(ram, kSecond, kSecondMemsz, kDirt);

    // The first segment is always valid here; only the second is moved or resized.
    SUBCASE("entirely below the base") {
        put32(file, phdr(2) + kPVaddr, 0x7FFF0000u);
    }
    SUBCASE("starts below the base and reaches into memory") {
        put32(file, phdr(2) + kPVaddr, ram.base() - 8);
    }
    SUBCASE("starts at the end of memory") {
        put32(file, phdr(2) + kPVaddr, ram.base() + ram.size());
    }
    SUBCASE("address near 4 GiB") {
        put32(file, phdr(2) + kPVaddr, 0xFFFFFFF8u);
    }
    SUBCASE("one byte larger than the whole memory") {
        put32(file, phdr(2) + kPVaddr, ram.base());
        put32(file, phdr(2) + kPMemsz, ram.size() + 1);
    }
    SUBCASE("memory size near 4 GiB") {
        put32(file, phdr(2) + kPMemsz, 0xFFFFFFFFu);
    }

    CHECK(load(ram, file) == MemStatus::OutOfRange);
    CHECK(countEqual(ram, kFirst, 32, kDirt) == 32);
    CHECK(countEqual(ram, kSecond, kSecondMemsz, kDirt) == kSecondMemsz);
}

TEST_CASE("Memory: loadSegments respects a base and size given to the constructor") {
    SUBCASE("a memory too small for the second segment") {
        Memory ram(0x80000000u, 0x1000);
        fill(ram, kFirst, 32, kDirt);
        CHECK(load(ram, makeElf(2)) == MemStatus::OutOfRange);
        CHECK(countEqual(ram, kFirst, 32, kDirt) == 32);
    }
    SUBCASE("a memory based at the second segment") {
        Memory ram(kSecond, 0x1000);
        REQUIRE(load(ram, makeElf(2)) == MemStatus::OutOfRange);

        Bytes file = makeElf(2);
        put32(file, phdr(1) + kPVaddr, kSecond + 0x800);
        REQUIRE(load(ram, file) == MemStatus::Ok);
        CHECK(countEqual(ram, kSecond, kSegmentBytes, 0xA1) == kSegmentBytes);
        CHECK(countEqual(ram, kSecond + 0x800, kSegmentBytes, 0xA0) == kSegmentBytes);
    }
}
