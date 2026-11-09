#include "memory.hpp"

namespace florv {

Memory::Memory(std::uint32_t base, std::uint32_t size)
    : base_(base), size_(size > kCapacity ? kCapacity : size) {}

MemStatus Memory::locate32(std::uint32_t addr, std::uint32_t& offset) const {
    if ((addr & 0x3u) != 0) {
        return MemStatus::Misaligned;
    }
    const std::uint32_t off = addr - base_;
    if (size_ < 4 || off > size_ - 4) {
        return MemStatus::OutOfRange;
    }
    offset = off;
    return MemStatus::Ok;
}

MemStatus Memory::read32(std::uint32_t addr, std::uint32_t& value) const {
    std::uint32_t off = 0;
    const MemStatus status = locate32(addr, off);
    if (status != MemStatus::Ok) {
        return status;
    }
    value = static_cast<std::uint32_t>(bytes_[off]) |
            (static_cast<std::uint32_t>(bytes_[off + 1]) << 8) |
            (static_cast<std::uint32_t>(bytes_[off + 2]) << 16) |
            (static_cast<std::uint32_t>(bytes_[off + 3]) << 24);
    return MemStatus::Ok;
}

MemStatus Memory::write32(std::uint32_t addr, std::uint32_t value) {
    std::uint32_t off = 0;
    const MemStatus status = locate32(addr, off);
    if (status != MemStatus::Ok) {
        return status;
    }
    bytes_[off] = static_cast<std::uint8_t>(value);
    bytes_[off + 1] = static_cast<std::uint8_t>(value >> 8);
    bytes_[off + 2] = static_cast<std::uint8_t>(value >> 16);
    bytes_[off + 3] = static_cast<std::uint8_t>(value >> 24);
    return MemStatus::Ok;
}

}  
