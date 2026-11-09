#include <cstddef>
#include <cstdint>
#include <vector>

#include "doctest.h"
#include "elf_image.hpp"

using florv::ByteView;
using florv::ElfImage;

namespace {

// Offsets inside the ELF32 header and a program header.
constexpr std::size_t kEhdrSize = 52;
constexpr std::size_t kPhdrSize = 32;
constexpr std::size_t kEiClass = 4;
constexpr std::size_t kEiData = 5;
constexpr std::size_t kEType = 16;
constexpr std::size_t kEMachine = 18;
constexpr std::size_t kEEntry = 24;
constexpr std::size_t kEPhoff = 28;
constexpr std::size_t kEPhentsize = 42;
constexpr std::size_t kEPhnum = 44;
constexpr std::size_t kPType = 0;
constexpr std::size_t kPOffset = 4;
constexpr std::size_t kPVaddr = 8;
constexpr std::size_t kPFilesz = 16;
constexpr std::size_t kPMemsz = 20;

constexpr std::uint32_t kEntry = 0x80000000u;
constexpr std::uint32_t kSegmentBytes = 16;

using Bytes = std::vector<std::uint8_t>;

void put16(Bytes& b, std::size_t offset, std::uint16_t value) {
    b[offset] = static_cast<std::uint8_t>(value);
    b[offset + 1] = static_cast<std::uint8_t>(value >> 8);
}

void put32(Bytes& b, std::size_t offset, std::uint32_t value) {
    for (std::size_t i = 0; i < 4; ++i) {
        b[offset + i] = static_cast<std::uint8_t>(value >> (8 * i));
    }
}

ByteView view(const Bytes& b) {
    return ByteView{b.data(), b.size()};
}

// Offset of program header number index (0 is the non-load one, 1.. are the loads).
std::size_t phdr(std::size_t index) {
    return kEhdrSize + index * kPhdrSize;
}

// A valid RV32 executable: header, one non-load program header (4 bytes at file offset 0),
// loadCount PT_LOAD headers, then 16 bytes of payload per load. Load i sits at 0x80000000 + i * 0x1000, is filled with
// the byte 0xA0 + i, and has a memory size of 16 + i * 64.
Bytes makeElf(std::size_t loadCount) {
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

bool accepted(const Bytes& b) {
    return ElfImage::parse(view(b)).has_value();
}

}  // namespace

TEST_CASE("ElfImage: a valid RV32 executable is accepted") {
    const Bytes file = makeElf(2);
    const auto image = ElfImage::parse(view(file));

    REQUIRE(image.has_value());
    CHECK(image->entry() == kEntry);
    REQUIRE(image->segmentCount() == 2);

    const auto& first = image->segment(0);
    CHECK(first.vaddr == 0x80000000u);
    CHECK(first.bytes.size == kSegmentBytes);
    CHECK(first.memsz == kSegmentBytes);
    CHECK(first.bytes.data[0] == 0xA0u);

    // The second segment has a .bss-style tail: memory size above file size.
    const auto& second = image->segment(1);
    CHECK(second.vaddr == 0x80001000u);
    CHECK(second.bytes.size == kSegmentBytes);
    CHECK(second.memsz == kSegmentBytes + 64u);
    CHECK(second.bytes.data[0] == 0xA1u);
}

TEST_CASE("ElfImage: segments point into the caller's buffer, nothing is copied") {
    const Bytes file = makeElf(2);
    const auto image = ElfImage::parse(view(file));
    REQUIRE(image.has_value());
    REQUIRE(image->segmentCount() == 2);

    const std::size_t payload = kEhdrSize + 3 * kPhdrSize;
    CHECK(image->segment(0).bytes.data == file.data() + payload);
    CHECK(image->segment(1).bytes.data == file.data() + payload + kSegmentBytes);
}

TEST_CASE("ElfImage: a truncated file is rejected") {
    const Bytes file = makeElf(2);

    SUBCASE("shorter than the ELF header") {
        const Bytes cut(file.begin(), file.begin() + (kEhdrSize - 1));
        CHECK_FALSE(accepted(cut));
    }
    SUBCASE("cut inside the program header table") {
        const Bytes cut(file.begin(), file.begin() + (kEhdrSize + kPhdrSize + 5));
        CHECK_FALSE(accepted(cut));
    }
    SUBCASE("cut one byte before the end of the last segment") {
        const Bytes cut(file.begin(), file.end() - 1);
        CHECK_FALSE(accepted(cut));
    }
    SUBCASE("every shorter length") {
        std::size_t acceptedCount = 0;
        for (std::size_t length = 0; length < file.size(); ++length) {
            const Bytes cut(file.begin(), file.begin() + static_cast<std::ptrdiff_t>(length));
            if (accepted(cut)) {
                ++acceptedCount;
            }
        }
        CHECK(acceptedCount == 0);
    }
}

TEST_CASE("ElfImage: an empty view is rejected") {
    CHECK_FALSE(ElfImage::parse(ByteView{}).has_value());
}

TEST_CASE("ElfImage: wrong header fields are rejected") {
    Bytes file = makeElf(1);
    REQUIRE(accepted(file));

    SUBCASE("bad magic") {
        file[0] = 0x7E;
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("ELFCLASS64") {
        file[kEiClass] = 2;
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("big-endian") {
        file[kEiData] = 2;
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("relocatable object, not an executable") {
        put16(file, kEType, 1);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("shared object, not an executable") {
        put16(file, kEType, 3);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("ARM machine") {
        put16(file, kEMachine, 40);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("x86-64 machine") {
        put16(file, kEMachine, 62);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("program header entry size is not 32") {
        put16(file, kEPhentsize, 56);
        CHECK_FALSE(accepted(file));
    }
}

TEST_CASE("ElfImage: offsets and sizes that leave the file are rejected") {
    Bytes file = makeElf(1);
    REQUIRE(accepted(file));
    const std::size_t load = phdr(1);

    SUBCASE("program header table just past the end") {
        put32(file, kEPhoff, static_cast<std::uint32_t>(file.size()));
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("program header table near 4 GiB") {
        put32(file, kEPhoff, 0xFFFFFFF0u);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("segment offset near 4 GiB") {
        put32(file, load + kPOffset, 0xFFFFFFF8u);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("segment one byte longer than the file") {
        put32(file, load + kPFilesz, kSegmentBytes + 1);
        put32(file, load + kPMemsz, kSegmentBytes + 1);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("segment size near 4 GiB") {
        put32(file, load + kPFilesz, 0xFFFFFFFFu);
        put32(file, load + kPMemsz, 0xFFFFFFFFu);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("file size above memory size") {
        put32(file, load + kPMemsz, kSegmentBytes - 1);
        CHECK_FALSE(accepted(file));
    }
}

TEST_CASE("ElfImage: only loadable segments with a size are listed") {
    SUBCASE("a file with no program headers has no segments") {
        Bytes file = makeElf(0);
        file.resize(kEhdrSize);
        put16(file, kEPhnum, 0);
        const auto image = ElfImage::parse(view(file));
        REQUIRE(image.has_value());
        CHECK(image->segmentCount() == 0);
        CHECK(image->entry() == kEntry);
    }
    SUBCASE("a non-load program header is skipped") {
        const Bytes file = makeElf(0);
        const auto image = ElfImage::parse(view(file));
        REQUIRE(image.has_value());
        CHECK(image->segmentCount() == 0);
    }
    SUBCASE("a load with zero memory size is skipped") {
        Bytes file = makeElf(2);
        put32(file, phdr(1) + kPFilesz, 0);
        put32(file, phdr(1) + kPMemsz, 0);
        const auto image = ElfImage::parse(view(file));
        REQUIRE(image.has_value());
        REQUIRE(image->segmentCount() == 1);
        CHECK(image->segment(0).vaddr == 0x80001000u);
    }
}

TEST_CASE("ElfImage: the segment limit") {
    SUBCASE("kMaxSegments loads are accepted") {
        const Bytes file = makeElf(ElfImage::kMaxSegments);
        const auto image = ElfImage::parse(view(file));
        REQUIRE(image.has_value());
        CHECK(image->segmentCount() == ElfImage::kMaxSegments);
        CHECK(image->segment(ElfImage::kMaxSegments - 1).bytes.data[0] == 0xA7u);
    }
    SUBCASE("one more is rejected") {
        CHECK_FALSE(accepted(makeElf(ElfImage::kMaxSegments + 1)));
    }
}
