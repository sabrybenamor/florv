#pragma once

#include <array>
#include <cstdint>

namespace florv {

enum class MemStatus : std::uint8_t {
    Ok,
    OutOfRange,
    Misaligned,
};

// Flat little-endian RAM as the RISC-V program sees it.
// Addresses are RISC-V addresses: base() maps to byte 0 of the storage.
// The storage is a fixed array inside the object (no heap), so on the ARM a Memory
// must be a static or global object, never a local: it is 64 KiB.
class Memory {
public:
    static constexpr std::uint32_t kDefaultBase = 0x80000000u;
    static constexpr std::uint32_t kCapacity = 64u * 1024u;

    explicit Memory(std::uint32_t base = kDefaultBase, std::uint32_t size = kCapacity);

    // A failed read leaves value untouched; a failed write changes nothing.
    MemStatus read8(std::uint32_t addr, std::uint8_t& value) const;
    MemStatus read16(std::uint32_t addr, std::uint16_t& value) const;
    MemStatus read32(std::uint32_t addr, std::uint32_t& value) const;

    MemStatus write8(std::uint32_t addr, std::uint8_t value);
    MemStatus write16(std::uint32_t addr, std::uint16_t value);
    MemStatus write32(std::uint32_t addr, std::uint32_t value);

    std::uint32_t base() const { return base_; }
    std::uint32_t size() const { return size_; }

private:
    // width is 1, 2 or 4 bytes. Alignment is checked before range.
    MemStatus locate(std::uint32_t addr, std::uint32_t width, std::uint32_t& offset) const;

    std::uint32_t base_;
    std::uint32_t size_;
    std::array<std::uint8_t, kCapacity> bytes_{};
};

}  // namespace florv
