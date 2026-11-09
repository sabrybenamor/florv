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
