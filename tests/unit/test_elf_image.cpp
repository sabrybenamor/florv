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

// Offsets inside the ELF32 header, a section header and a symbol table entry.
constexpr std::size_t kEShoff = 32;
constexpr std::size_t kEShentsize = 46;
constexpr std::size_t kEShnum = 48;
constexpr std::size_t kShdrSize = 40;
constexpr std::size_t kShType = 4;
constexpr std::size_t kShOffset = 16;
constexpr std::size_t kShSize = 20;
constexpr std::size_t kShLink = 24;
constexpr std::size_t kShEntsize = 36;
constexpr std::size_t kSymSize = 16;
constexpr std::size_t kStName = 0;
constexpr std::size_t kStValue = 4;
constexpr std::size_t kStShndx = 14;

// Section numbers in the file built by makeSymbolElf().
constexpr std::size_t kSecText = 1;
constexpr std::size_t kSecSymtab = 2;
constexpr std::size_t kSecStrtab = 3;
constexpr std::size_t kSectionCount = 4;

struct TestSymbol {
    const char* name;
    std::uint32_t value;
    std::uint16_t section;  // 0 means undefined
};

// Symbol table entry 0 is the empty one every ELF has, so these are entries 1 to 6.
// The second is a section symbol: defined, but with no name, as linkers emit them.
// end_signature is last, so its name ends the string table.
constexpr TestSymbol kSymbols[] = {
    {"_start", 0x80000000u, kSecText},
    {"", 0x80000000u, kSecText},
    {"tohost", 0x80001000u, kSecText},
    {"begin_signature", 0x80002000u, kSecText},
    {"extern_hook", 0x12345678u, 0},
    {"end_signature", 0x80002040u, kSecText},
};
constexpr std::size_t kSymbolCount = sizeof(kSymbols) / sizeof(kSymbols[0]);
constexpr std::size_t kTohostEntry = 3;

struct SymbolElf {
    Bytes bytes;
    std::size_t strtab = 0;  // file offset of the string table
    std::size_t strtabSize = 0;
    std::size_t symtab = 0;  // file offset of the symbol table
    std::size_t symtabSize = 0;
    std::size_t shdrs = 0;  // file offset of the section header table

    std::size_t shdr(std::size_t section) const { return shdrs + section * kShdrSize; }
    std::size_t sym(std::size_t entry) const { return symtab + entry * kSymSize; }
};

// makeElf(1) followed by a string table, a symbol table and four section headers:
// the empty one, a .text-style section, the symbol table and the string table.
SymbolElf makeSymbolElf() {
    SymbolElf elf;
    Bytes& b = elf.bytes;
    b = makeElf(1);

    elf.strtab = b.size();
    std::size_t nameOffset[kSymbolCount] = {};
    b.push_back(0);
    for (std::size_t i = 0; i < kSymbolCount; ++i) {
        if (kSymbols[i].name[0] == '\0') {
            continue;  // name offset 0, the empty string every string table starts with
        }
        nameOffset[i] = b.size() - elf.strtab;
        for (const char* c = kSymbols[i].name; *c != '\0'; ++c) {
            b.push_back(static_cast<std::uint8_t>(*c));
        }
        b.push_back(0);
    }
    elf.strtabSize = b.size() - elf.strtab;

    elf.symtab = b.size();
    elf.symtabSize = (kSymbolCount + 1) * kSymSize;
    b.resize(b.size() + elf.symtabSize, 0);
    for (std::size_t i = 0; i < kSymbolCount; ++i) {
        const std::size_t entry = elf.sym(i + 1);
        put32(b, entry + kStName, static_cast<std::uint32_t>(nameOffset[i]));
        put32(b, entry + kStValue, kSymbols[i].value);
        put16(b, entry + kStShndx, kSymbols[i].section);
    }

    elf.shdrs = b.size();
    b.resize(b.size() + kSectionCount * kShdrSize, 0);
    put32(b, elf.shdr(kSecText) + kShType, 1);
    put32(b, elf.shdr(kSecText) + kShOffset, static_cast<std::uint32_t>(kEhdrSize + 2 * kPhdrSize));
    put32(b, elf.shdr(kSecText) + kShSize, kSegmentBytes);
    put32(b, elf.shdr(kSecSymtab) + kShType, 2);
    put32(b, elf.shdr(kSecSymtab) + kShOffset, static_cast<std::uint32_t>(elf.symtab));
    put32(b, elf.shdr(kSecSymtab) + kShSize, static_cast<std::uint32_t>(elf.symtabSize));
    put32(b, elf.shdr(kSecSymtab) + kShLink, static_cast<std::uint32_t>(kSecStrtab));
    put32(b, elf.shdr(kSecSymtab) + kShEntsize, static_cast<std::uint32_t>(kSymSize));
    put32(b, elf.shdr(kSecStrtab) + kShType, 3);
    put32(b, elf.shdr(kSecStrtab) + kShOffset, static_cast<std::uint32_t>(elf.strtab));
    put32(b, elf.shdr(kSecStrtab) + kShSize, static_cast<std::uint32_t>(elf.strtabSize));

    put32(b, kEShoff, static_cast<std::uint32_t>(elf.shdrs));
    put16(b, kEShentsize, static_cast<std::uint16_t>(kShdrSize));
    put16(b, kEShnum, static_cast<std::uint16_t>(kSectionCount));
    return elf;
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

TEST_CASE("ElfImage: tohost and the signature bounds are found by name") {
    const SymbolElf elf = makeSymbolElf();
    const auto image = ElfImage::parse(view(elf.bytes));
    REQUIRE(image.has_value());

    CHECK(image->findSymbol("tohost") == 0x80001000u);
    CHECK(image->findSymbol("begin_signature") == 0x80002000u);
    CHECK(image->findSymbol("end_signature") == 0x80002040u);
    CHECK(image->findSymbol("_start") == 0x80000000u);

    // The symbol tables change nothing about the entry point and the segments.
    CHECK(image->entry() == kEntry);
    REQUIRE(image->segmentCount() == 1);
    CHECK(image->segment(0).vaddr == 0x80000000u);
}

TEST_CASE("ElfImage: only an exact, defined name matches") {
    const SymbolElf elf = makeSymbolElf();
    const auto image = ElfImage::parse(view(elf.bytes));
    REQUIRE(image.has_value());

    SUBCASE("a name that is not in the file") {
        CHECK_FALSE(image->findSymbol("fromhost").has_value());
    }
    SUBCASE("the start of a real name") {
        CHECK_FALSE(image->findSymbol("tohos").has_value());
        CHECK_FALSE(image->findSymbol("end").has_value());
    }
    SUBCASE("a real name with more after it") {
        CHECK_FALSE(image->findSymbol("tohost2").has_value());
        CHECK_FALSE(image->findSymbol("end_signature_").has_value());
    }
    SUBCASE("the tail of a real name") {
        // "signature" is in the string table, inside both signature names,
        // but no symbol's name starts there.
        CHECK_FALSE(image->findSymbol("signature").has_value());
    }
    SUBCASE("the empty name") {
        CHECK_FALSE(image->findSymbol("").has_value());
    }
    SUBCASE("an undefined symbol has no address") {
        CHECK_FALSE(image->findSymbol("extern_hook").has_value());
    }
}

TEST_CASE("ElfImage: a file without a symbol table parses and has no symbols") {
    SUBCASE("no section header table") {
        const Bytes file = makeElf(1);
        const auto image = ElfImage::parse(view(file));
        REQUIRE(image.has_value());
        CHECK_FALSE(image->findSymbol("tohost").has_value());
    }
    SUBCASE("a section count of zero") {
        SymbolElf elf = makeSymbolElf();
        put16(elf.bytes, kEShnum, 0);
        const auto image = ElfImage::parse(view(elf.bytes));
        REQUIRE(image.has_value());
        CHECK_FALSE(image->findSymbol("tohost").has_value());
    }
    SUBCASE("sections, but none is a symbol table") {
        SymbolElf elf = makeSymbolElf();
        put32(elf.bytes, elf.shdr(kSecSymtab) + kShType, 1);
        const auto image = ElfImage::parse(view(elf.bytes));
        REQUIRE(image.has_value());
        CHECK_FALSE(image->findSymbol("tohost").has_value());
    }
}

TEST_CASE("ElfImage: a section or symbol table that leaves the file is rejected") {
    SymbolElf elf = makeSymbolElf();
    Bytes& file = elf.bytes;
    REQUIRE(accepted(file));
    const std::size_t symtab = elf.shdr(kSecSymtab);
    const std::size_t strtab = elf.shdr(kSecStrtab);

    SUBCASE("section header entry size is not 40") {
        put16(file, kEShentsize, 64);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("section header table just past the end") {
        put32(file, kEShoff, static_cast<std::uint32_t>(file.size()));
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("section header table near 4 GiB") {
        put32(file, kEShoff, 0xFFFFFFF0u);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("one section header more than the file holds") {
        put16(file, kEShnum, static_cast<std::uint16_t>(kSectionCount + 1));
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("symbol entry size is not 16") {
        put32(file, symtab + kShEntsize, 24);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("symbol table offset near 4 GiB") {
        put32(file, symtab + kShOffset, 0xFFFFFFF0u);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("symbol table runs past the end of the file") {
        put32(file, symtab + kShSize, static_cast<std::uint32_t>(file.size() - elf.symtab + 1));
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("string table link is not a section number") {
        put32(file, symtab + kShLink, static_cast<std::uint32_t>(kSectionCount));
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("string table link is one past the table, where a string table header sits") {
        // Bytes that would pass as a fifth section header, but the header count says four.
        const Bytes extra(file.begin() + static_cast<std::ptrdiff_t>(strtab),
                          file.begin() + static_cast<std::ptrdiff_t>(strtab + kShdrSize));
        file.insert(file.end(), extra.begin(), extra.end());
        put32(file, symtab + kShLink, static_cast<std::uint32_t>(kSectionCount));
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("string table link names a section that is not a string table") {
        put32(file, symtab + kShLink, static_cast<std::uint32_t>(kSecText));
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("string table offset near 4 GiB") {
        put32(file, strtab + kShOffset, 0xFFFFFFF0u);
        CHECK_FALSE(accepted(file));
    }
    SUBCASE("string table runs past the end of the file") {
        put32(file, strtab + kShSize, static_cast<std::uint32_t>(file.size() - elf.strtab + 1));
        CHECK_FALSE(accepted(file));
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

TEST_CASE("ElfImage: a bad name in the symbol table matches nothing and harms nothing") {
    SymbolElf elf = makeSymbolElf();
    Bytes& file = elf.bytes;

    SUBCASE("name offset at the end of the string table") {
        put32(file, elf.sym(kTohostEntry) + kStName, static_cast<std::uint32_t>(elf.strtabSize));
        const auto image = ElfImage::parse(view(file));
        REQUIRE(image.has_value());
        CHECK_FALSE(image->findSymbol("tohost").has_value());
        CHECK(image->findSymbol("end_signature") == 0x80002040u);
    }
    SUBCASE("name offset near 4 GiB") {
        put32(file, elf.sym(kTohostEntry) + kStName, 0xFFFFFFF0u);
        const auto image = ElfImage::parse(view(file));
        REQUIRE(image.has_value());
        CHECK_FALSE(image->findSymbol("tohost").has_value());
        CHECK(image->findSymbol("begin_signature") == 0x80002000u);
    }
    SUBCASE("last name has no terminator inside the string table") {
        // The string table now ends on the final 'e' of end_signature. The byte after it
        // in the file is still zero, so a lookup that read past the table would match.
        put32(file, elf.shdr(kSecStrtab) + kShSize, static_cast<std::uint32_t>(elf.strtabSize - 1));
        const auto image = ElfImage::parse(view(file));
        REQUIRE(image.has_value());
        CHECK_FALSE(image->findSymbol("end_signature").has_value());
        CHECK(image->findSymbol("tohost") == 0x80001000u);
    }
    SUBCASE("symbol table cut in the middle of its last entry") {
        put32(file, elf.shdr(kSecSymtab) + kShSize, static_cast<std::uint32_t>(elf.symtabSize - 8));
        const auto image = ElfImage::parse(view(file));
        REQUIRE(image.has_value());
        CHECK_FALSE(image->findSymbol("end_signature").has_value());
        CHECK(image->findSymbol("tohost") == 0x80001000u);
    }
}
