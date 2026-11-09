#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>

#include "byte_view.hpp"

namespace florv {


struct ElfSegment {
    std::uint32_t vaddr = 0;  
    ByteView bytes;           
    std::uint32_t memsz = 0;  
};

// A validated view of a 32-bit little-endian RISC-V executable.
// The image does not own the file: its segments point into the buffer given to parse(),
// which must stay alive and unchanged for as long as the image is used.
class ElfImage {
public:
    static constexpr std::size_t kMaxSegments = 8;

    
    static std::optional<ElfImage> parse(ByteView file);

    std::uint32_t entry() const { return entry_; }

    std::size_t segmentCount() const { return segmentCount_; }

    
    const ElfSegment& segment(std::size_t index) const { return segments_[index]; }

    
    std::optional<std::uint32_t> findSymbol(std::string_view name) const;

private:
    ElfImage() = default;

    bool readSegments(ByteView file);
    bool readSymbols(ByteView file);

    std::uint32_t entry_ = 0;
    std::size_t segmentCount_ = 0;
    std::array<ElfSegment, kMaxSegments> segments_{};
    ByteView symtab_;
    ByteView strtab_;
};

}  
