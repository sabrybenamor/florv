#include "elf_image.hpp"

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
constexpr std::size_t kEPhentsize = 42;
constexpr std::size_t kEPhnum = 44;

// ELF32 program header: 32 bytes.
constexpr std::size_t kPhdrSize = 32;
constexpr std::size_t kPType = 0;
constexpr std::size_t kPOffset = 4;
constexpr std::size_t kPVaddr = 8;
constexpr std::size_t kPFilesz = 16;
constexpr std::size_t kPMemsz = 20;

constexpr std::uint8_t kClass32 = 1;
constexpr std::uint8_t kDataLittleEndian = 1;
constexpr std::uint16_t kTypeExecutable = 2;
constexpr std::uint16_t kMachineRiscV = 0xF3;
constexpr std::uint32_t kPtLoad = 1;

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

    const std::size_t phoff = read32(h + kEPhoff);
    const std::size_t phnum = read16(h + kEPhnum);
    if (phnum == 0) {
        return image;
    }
    if (read16(h + kEPhentsize) != kPhdrSize) {
        return std::nullopt;
    }
    // phnum is at most 65535, so phnum * 32 cannot overflow.
    if (!file.contains(phoff, phnum * kPhdrSize)) {
        return std::nullopt;
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
            return std::nullopt;
        }
        if (image.segmentCount_ == kMaxSegments) {
            return std::nullopt;
        }
        ElfSegment& segment = image.segments_[image.segmentCount_++];
        segment.vaddr = read32(ph + kPVaddr);
        segment.bytes = file.sub(offset, filesz);
        segment.memsz = memsz;
    }
    return image;
}

}  // namespace florv
