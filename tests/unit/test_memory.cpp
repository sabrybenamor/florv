#include <cstdint>

#include "doctest.h"
#include "memory.hpp"

using florv::Memory;
using florv::MemStatus;

TEST_CASE("Memory: a word written is read back") {
    Memory ram;
    const std::uint32_t first = ram.base();
    const std::uint32_t last = ram.base() + ram.size() - 4;

    REQUIRE(ram.write32(first, 0xDEADBEEFu) == MemStatus::Ok);
    REQUIRE(ram.write32(last, 0x12345678u) == MemStatus::Ok);

    std::uint32_t value = 0;
    REQUIRE(ram.read32(first, value) == MemStatus::Ok);
    CHECK(value == 0xDEADBEEFu);
    REQUIRE(ram.read32(last, value) == MemStatus::Ok);
    CHECK(value == 0x12345678u);
}

TEST_CASE("Memory: defaults are base 0x80000000 and 64 KiB, zero-filled") {
    Memory ram;
    CHECK(ram.base() == 0x80000000u);
    CHECK(ram.size() == 64u * 1024u);

    std::uint32_t value = 0xFFFFFFFFu;
    REQUIRE(ram.read32(ram.base(), value) == MemStatus::Ok);
    CHECK(value == 0u);
}

TEST_CASE("Memory: word access at the edges") {
    Memory ram;
    const std::uint32_t base = ram.base();
    const std::uint32_t end = ram.base() + ram.size();
    std::uint32_t value = 0;

    CHECK(ram.read32(base, value) == MemStatus::Ok);
    CHECK(ram.read32(end - 4, value) == MemStatus::Ok);
    CHECK(ram.read32(end, value) == MemStatus::OutOfRange);
    CHECK(ram.read32(base - 4, value) == MemStatus::OutOfRange);

    CHECK(ram.write32(base, 1u) == MemStatus::Ok);
    CHECK(ram.write32(end - 4, 1u) == MemStatus::Ok);
    CHECK(ram.write32(end, 1u) == MemStatus::OutOfRange);
    CHECK(ram.write32(base - 4, 1u) == MemStatus::OutOfRange);
}

TEST_CASE("Memory: half-word access at the edges") {
    Memory ram;
    const std::uint32_t base = ram.base();
    const std::uint32_t end = ram.base() + ram.size();
    std::uint16_t value = 0;

    CHECK(ram.read16(base, value) == MemStatus::Ok);
    CHECK(ram.read16(end - 2, value) == MemStatus::Ok);
    CHECK(ram.read16(end, value) == MemStatus::OutOfRange);
    CHECK(ram.read16(base - 2, value) == MemStatus::OutOfRange);

    CHECK(ram.write16(end - 2, 0xBEEFu) == MemStatus::Ok);
    CHECK(ram.write16(end, 0xBEEFu) == MemStatus::OutOfRange);
}

TEST_CASE("Memory: byte access at the edges") {
    Memory ram;
    const std::uint32_t base = ram.base();
    const std::uint32_t end = ram.base() + ram.size();
    std::uint8_t value = 0;

    CHECK(ram.read8(base, value) == MemStatus::Ok);
    CHECK(ram.read8(end - 1, value) == MemStatus::Ok);
    CHECK(ram.read8(end, value) == MemStatus::OutOfRange);
    CHECK(ram.read8(base - 1, value) == MemStatus::OutOfRange);

    CHECK(ram.write8(end - 1, 0x5Au) == MemStatus::Ok);
    CHECK(ram.write8(end, 0x5Au) == MemStatus::OutOfRange);
}

TEST_CASE("Memory: misaligned addresses are rejected") {
    Memory ram;
    const std::uint32_t base = ram.base();
    std::uint32_t word = 0;
    std::uint16_t half = 0;
    std::uint8_t byte = 0;

    CHECK(ram.read32(base + 1, word) == MemStatus::Misaligned);
    CHECK(ram.read32(base + 2, word) == MemStatus::Misaligned);
    CHECK(ram.read32(base + 3, word) == MemStatus::Misaligned);
    CHECK(ram.write32(base + 2, 1u) == MemStatus::Misaligned);

    CHECK(ram.read16(base + 1, half) == MemStatus::Misaligned);
    CHECK(ram.read16(base + 2, half) == MemStatus::Ok);
    CHECK(ram.write16(base + 3, 1u) == MemStatus::Misaligned);

    // A byte is never misaligned.
    CHECK(ram.read8(base + 1, byte) == MemStatus::Ok);
    CHECK(ram.read8(base + 3, byte) == MemStatus::Ok);
}

TEST_CASE("Memory: alignment is reported before range") {
    Memory ram;
    const std::uint32_t end = ram.base() + ram.size();
    std::uint32_t word = 0;

    CHECK(ram.read32(end + 2, word) == MemStatus::Misaligned);
}

TEST_CASE("Memory: a failed access changes nothing") {
    Memory ram;
    const std::uint32_t base = ram.base();
    const std::uint32_t end = ram.base() + ram.size();

    std::uint32_t word = 0xCAFEF00Du;
    CHECK(ram.read32(end, word) == MemStatus::OutOfRange);
    CHECK(word == 0xCAFEF00Du);
    CHECK(ram.read32(base + 2, word) == MemStatus::Misaligned);
    CHECK(word == 0xCAFEF00Du);

    REQUIRE(ram.write32(base, 0x11223344u) == MemStatus::Ok);
    CHECK(ram.write32(base + 2, 0xFFFFFFFFu) == MemStatus::Misaligned);
    REQUIRE(ram.read32(base, word) == MemStatus::Ok);
    CHECK(word == 0x11223344u);
}

TEST_CASE("Memory: storage is little-endian across widths") {
    Memory ram;
    const std::uint32_t base = ram.base();
    REQUIRE(ram.write32(base, 0x12345678u) == MemStatus::Ok);

    std::uint8_t byte = 0;
    REQUIRE(ram.read8(base + 0, byte) == MemStatus::Ok);
    CHECK(byte == 0x78u);
    REQUIRE(ram.read8(base + 1, byte) == MemStatus::Ok);
    CHECK(byte == 0x56u);
    REQUIRE(ram.read8(base + 2, byte) == MemStatus::Ok);
    CHECK(byte == 0x34u);
    REQUIRE(ram.read8(base + 3, byte) == MemStatus::Ok);
    CHECK(byte == 0x12u);

    std::uint16_t half = 0;
    REQUIRE(ram.read16(base + 0, half) == MemStatus::Ok);
    CHECK(half == 0x5678u);
    REQUIRE(ram.read16(base + 2, half) == MemStatus::Ok);
    CHECK(half == 0x1234u);

    // Narrow writes land in the right byte of the word.
    REQUIRE(ram.write8(base + 3, 0xABu) == MemStatus::Ok);
    REQUIRE(ram.write16(base + 0, 0xCDEFu) == MemStatus::Ok);
    std::uint32_t word = 0;
    REQUIRE(ram.read32(base, word) == MemStatus::Ok);
    CHECK(word == 0xAB34CDEFu);
}

TEST_CASE("Memory: custom base and size") {
    Memory ram(0x1000u, 16u);
    std::uint32_t word = 0;

    CHECK(ram.base() == 0x1000u);
    CHECK(ram.size() == 16u);
    CHECK(ram.write32(0x100Cu, 7u) == MemStatus::Ok);
    CHECK(ram.read32(0x100Cu, word) == MemStatus::Ok);
    CHECK(word == 7u);
    CHECK(ram.read32(0x1010u, word) == MemStatus::OutOfRange);
    CHECK(ram.read32(0x0FFCu, word) == MemStatus::OutOfRange);
}

TEST_CASE("Memory: a size above the capacity is reduced to the capacity") {
    Memory ram(0x80000000u, Memory::kCapacity * 2u);
    CHECK(ram.size() == Memory::kCapacity);
}
