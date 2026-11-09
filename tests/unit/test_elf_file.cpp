// Loads tests/data/minimal.elf, built by the RISC-V GCC from tests/data/minimal.S.
// The expected numbers below were copied by hand from readelf -lW, nm and objdump -d
// run on that file, so they do not come from the code under test.

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "doctest.h"
#include "elf_image.hpp"
#include "memory.hpp"

using florv::ByteView;
using florv::ElfImage;
using florv::Memory;
using florv::MemStatus;

namespace {

const std::string kPath = FLORV_TEST_DATA_DIR "/minimal.elf";

// readelf -lW: one LOAD segment.
constexpr std::uint32_t kEntry = 0x80000000u;
constexpr std::uint32_t kFileSize = 0x1020;
constexpr std::uint32_t kMemSize = 0x1060;

// nm.
constexpr std::uint32_t kBeginSignature = 0x80001014u;
constexpr std::uint32_t kEndSignature = 0x8000101Cu;
constexpr std::uint32_t kTohost = 0x8000101Cu;
constexpr std::uint32_t kScratch = 0x80001020u;
constexpr std::uint32_t kScratchBytes = 64;

// An empty vector means the file could not be read.
std::vector<std::uint8_t> readFile(const std::string& path) {
    std::vector<std::uint8_t> bytes;
    std::FILE* file = std::fopen(path.c_str(), "rb");
    if (file == nullptr) {
        return bytes;
    }
    std::uint8_t chunk[4096];
    std::size_t got = 0;
    while ((got = std::fread(chunk, 1, sizeof(chunk), file)) > 0) {
        bytes.insert(bytes.end(), chunk, chunk + got);
    }
    std::fclose(file);
    return bytes;
}

std::uint32_t wordAt(const Memory& ram, std::uint32_t addr) {
    std::uint32_t value = 0;
    REQUIRE(ram.read32(addr, value) == MemStatus::Ok);
    return value;
}

}  // namespace

TEST_CASE("ELF file: a program built by the RISC-V compiler is parsed") {
    const std::vector<std::uint8_t> file = readFile(kPath);
    REQUIRE_MESSAGE(!file.empty(), "cannot read " << kPath << " (build it: see tests/data/minimal.S)");

    const auto image = ElfImage::parse(ByteView{file.data(), file.size()});
    REQUIRE(image.has_value());

    CHECK(image->entry() == kEntry);
    REQUIRE(image->segmentCount() == 1);
    CHECK(image->segment(0).vaddr == kEntry);
    CHECK(image->segment(0).bytes.size == kFileSize);
    CHECK(image->segment(0).memsz == kMemSize);

    CHECK(image->findSymbol("_start") == kEntry);
    CHECK(image->findSymbol("tohost") == kTohost);
    CHECK(image->findSymbol("begin_signature") == kBeginSignature);
    CHECK(image->findSymbol("end_signature") == kEndSignature);
    CHECK(image->findSymbol("scratch") == kScratch);
    CHECK_FALSE(image->findSymbol("fromhost").has_value());
}

TEST_CASE("ELF file: a program built by the RISC-V compiler is loaded") {
    const std::vector<std::uint8_t> file = readFile(kPath);
    REQUIRE_MESSAGE(!file.empty(), "cannot read " << kPath << " (build it: see tests/data/minimal.S)");
    const auto image = ElfImage::parse(ByteView{file.data(), file.size()});
    REQUIRE(image.has_value());

    // Old contents where .bss will be, and one word just past the end of the segment.
    Memory ram;
    for (std::uint32_t i = 0; i < kScratchBytes + 4; i += 4) {
        REQUIRE(ram.write32(kScratch + i, 0xFFFFFFFFu) == MemStatus::Ok);
    }
    REQUIRE(ram.loadSegments(*image) == MemStatus::Ok);

    // objdump -d: the first two instructions, li a0,1 and auipc a1,0x1.
    CHECK(wordAt(ram, kEntry) == 0x00100513u);
    CHECK(wordAt(ram, kEntry + 4) == 0x00001597u);

    // The two signature words and the tohost word from minimal.S.
    CHECK(wordAt(ram, kBeginSignature) == 0x11223344u);
    CHECK(wordAt(ram, kBeginSignature + 4) == 0xAABBCCDDu);
    CHECK(wordAt(ram, kTohost) == 0u);

    // .bss is not in the file: the loader zeroes it, and stops where the segment ends.
    for (std::uint32_t i = 0; i < kScratchBytes; i += 4) {
        CHECK(wordAt(ram, kScratch + i) == 0u);
    }
    CHECK(kScratch + kScratchBytes == kEntry + kMemSize);
    CHECK(wordAt(ram, kScratch + kScratchBytes) == 0xFFFFFFFFu);
}
