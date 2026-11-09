#include "elf_image.hpp"

#include <cstring>

namespace florv {

namespace {

// ELF32 file header: 52 bytes.
constexpr std::size_t kEhdrSize = 52;
constexpr std::size_t kEiClass = 4;
constexpr std::size_t kEiData = 5;
constexpr std::size_t kEType = 16;
constexpr std::size_t kEMachine = 18;
constexpr std::size_t kEEntry = 24;
constexpr std::size_t kEPhoff = 28;
constexpr std::size_t kEShoff = 32;
constexpr std::size_t kEPhentsize = 42;
constexpr std::size_t kEPhnum = 44;
constexpr std::size_t kEShentsize = 46;
constexpr std::size_t kEShnum = 48;

// ELF32 program header: 32 bytes.
constexpr std::size_t kPhdrSize = 32;
constexpr std::size_t kPType = 0;
constexpr std::size_t kPOffset = 4;
constexpr std::size_t kPVaddr = 8;
constexpr std::size_t kPFilesz = 16;
constexpr std::size_t kPMemsz = 20;

// ELF32 section header: 40 bytes.
constexpr std::size_t kShdrSize = 40;
constexpr std::size_t kShType = 4;
constexpr std::size_t kShOffset = 16;
constexpr std::size_t kShSize = 20;
constexpr std::size_t kShLink = 24;
constexpr std::size_t kShEntsize = 36;

// ELF32 symbol table entry: 16 bytes.
constexpr std::size_t kSymSize = 16;
constexpr std::size_t kStName = 0;
constexpr std::size_t kStValue = 4;
constexpr std::size_t kStShndx = 14;

constexpr std::uint8_t kClass32 = 1;
constexpr std::uint8_t kDataLittleEndian = 1;
constexpr std::uint16_t kTypeExecutable = 2;
constexpr std::uint16_t kMachineRiscV = 0xF3;
constexpr std::uint32_t kPtLoad = 1;
constexpr std::uint32_t kShtSymtab = 2;
constexpr std::uint32_t kShtStrtab = 3;
constexpr std::uint16_t kShnUndef = 0;

std::uint16_t read16(const std::uint8_t* p) {
    return static_cast<std::uint16_t>(static_cast<std::uint32_t>(p[0]) |
                                      (static_cast<std::uint32_t>(p[1]) << 8));
}

std::uint32_t read32(const std::uint8_t* p) {
    return static_cast<std::uint32_t>(p[0]) | (static_cast<std::uint32_t>(p[1]) << 8) |
           (static_cast<std::uint32_t>(p[2]) << 16) | (static_cast<std::uint32_t>(p[3]) << 24);
}

}  // namespace

std::optional<ElfImage> ElfImage::parse(ByteView file) {
    if (file.data == nullptr || file.size < kEhdrSize) {
        return std::nullopt;
    }
    const std::uint8_t* h = file.data;

    if (h[0] != 0x7F || h[1] != 'E' || h[2] != 'L' || h[3] != 'F') {
        return std::nullopt;
    }
    if (h[kEiClass] != kClass32 || h[kEiData] != kDataLittleEndian) {
        return std::nullopt;
    }
    if (read16(h + kEType) != kTypeExecutable || read16(h + kEMachine) != kMachineRiscV) {
        return std::nullopt;
    }

    ElfImage image;
    image.entry_ = read32(h + kEEntry);
    if (!image.readSegments(file) || !image.readSymbols(file)) {
        return std::nullopt;
    }
    return image;
}

bool ElfImage::readSegments(ByteView file) {
    const std::uint8_t* h = file.data;
    const std::size_t phoff = read32(h + kEPhoff);
    const std::size_t phnum = read16(h + kEPhnum);
    if (phnum == 0) {
        return true;
    }
    if (read16(h + kEPhentsize) != kPhdrSize) {
        return false;
    }
    if (!file.contains(phoff, phnum * kPhdrSize)) {
        return false;
    }

    for (std::size_t i = 0; i < phnum; ++i) {
        const std::uint8_t* ph = file.data + phoff + i * kPhdrSize;
        if (read32(ph + kPType) != kPtLoad) {
            continue;
        }
        const std::uint32_t offset = read32(ph + kPOffset);
        const std::uint32_t filesz = read32(ph + kPFilesz);
        const std::uint32_t memsz = read32(ph + kPMemsz);
        if (memsz == 0) {
            continue;  // nothing to load
        }
        if (filesz > memsz || !file.contains(offset, filesz)) {
            return false;
        }
        if (segmentCount_ == kMaxSegments) {
            return false;
        }
        ElfSegment& segment = segments_[segmentCount_++];
        segment.vaddr = read32(ph + kPVaddr);
        segment.bytes = file.sub(offset, filesz);
        segment.memsz = memsz;
    }
    return true;
}


bool ElfImage::readSymbols(ByteView file) {
    const std::uint8_t* h = file.data;
    const std::size_t shoff = read32(h + kEShoff);
    const std::size_t shnum = read16(h + kEShnum);
    if (shoff == 0 || shnum == 0) {
        return true;
    }
    if (read16(h + kEShentsize) != kShdrSize) {
        return false;
    }
    
    if (!file.contains(shoff, shnum * kShdrSize)) {
        return false;
    }
    const std::uint8_t* table = file.data + shoff;

    for (std::size_t i = 0; i < shnum; ++i) {
        const std::uint8_t* sym = table + i * kShdrSize;
        if (read32(sym + kShType) != kShtSymtab) {
            continue;
        }
        const std::size_t link = read32(sym + kShLink);
        if (read32(sym + kShEntsize) != kSymSize || link >= shnum) {
            return false;
        }
        const std::uint8_t* str = table + link * kShdrSize;
        if (read32(str + kShType) != kShtStrtab) {
            return false;
        }
        const std::uint32_t symOffset = read32(sym + kShOffset);
        const std::uint32_t symSize = read32(sym + kShSize);
        const std::uint32_t strOffset = read32(str + kShOffset);
        const std::uint32_t strSize = read32(str + kShSize);
        if (!file.contains(symOffset, symSize) || !file.contains(strOffset, strSize)) {
            return false;
        }
        symtab_ = file.sub(symOffset, symSize);
        strtab_ = file.sub(strOffset, strSize);
        return true; 
    }
    return true;
}

std::optional<std::uint32_t> ElfImage::findSymbol(std::string_view name) const {
    if (name.empty()) {
        return std::nullopt;
    }
    const std::size_t count = symtab_.size / kSymSize;
    for (std::size_t i = 0; i < count; ++i) {
        const std::uint8_t* sym = symtab_.data + i * kSymSize;
        if (read16(sym + kStShndx) == kShnUndef) {
            continue;  
        }
        const std::size_t nameOffset = read32(sym + kStName);
        if (nameOffset >= strtab_.size || name.size() >= strtab_.size - nameOffset) {
            continue;
        }
        const std::uint8_t* stored = strtab_.data + nameOffset;
        if (std::memcmp(stored, name.data(), name.size()) == 0 && stored[name.size()] == 0) {
            return read32(sym + kStValue);
        }
    }
    return std::nullopt;
}

}  // namespace florv
