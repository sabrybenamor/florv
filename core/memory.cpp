#include "memory.hpp"

namespace florv {

Memory::Memory(std::uint32_t base, std::uint32_t size)
    : base_(base), size_(size > kCapacity ? kCapacity : size) {}

MemStatus Memory::locate(std::uint32_t addr, std::uint32_t width, std::uint32_t& offset) const {
    if ((addr & (width - 1u)) != 0) {
        return MemStatus::Misaligned;
    }
    // An address below base_ wraps to a huge offset and fails the range test.
    const std::uint32_t off = addr - base_;
    if (size_ < width || off > size_ - width) {
        return MemStatus::OutOfRange;
    }
    offset = off;
    return MemStatus::Ok;
}

MemStatus Memory::read8(std::uint32_t addr, std::uint8_t& value) const {
    std::uint32_t off = 0;
    const MemStatus status = locate(addr, 1, off);
    if (status != MemStatus::Ok) {
        return status;
    }
    value = bytes_[off];
    return MemStatus::Ok;
}

MemStatus Memory::read16(std::uint32_t addr, std::uint16_t& value) const {
    std::uint32_t off = 0;
    const MemStatus status = locate(addr, 2, off);
    if (status != MemStatus::Ok) {
        return status;
    }
    value = static_cast<std::uint16_t>(static_cast<std::uint32_t>(bytes_[off]) |
                                       (static_cast<std::uint32_t>(bytes_[off + 1]) << 8));
    return MemStatus::Ok;
}

MemStatus Memory::read32(std::uint32_t addr, std::uint32_t& value) const {
    std::uint32_t off = 0;
    const MemStatus status = locate(addr, 4, off);
    if (status != MemStatus::Ok) {
        return status;
    }
    value = static_cast<std::uint32_t>(bytes_[off]) |
            (static_cast<std::uint32_t>(bytes_[off + 1]) << 8) |
            (static_cast<std::uint32_t>(bytes_[off + 2]) << 16) |
            (static_cast<std::uint32_t>(bytes_[off + 3]) << 24);
    return MemStatus::Ok;
}

MemStatus Memory::write8(std::uint32_t addr, std::uint8_t value) {
    std::uint32_t off = 0;
    const MemStatus status = locate(addr, 1, off);
    if (status != MemStatus::Ok) {
        return status;
    }
    bytes_[off] = value;
    return MemStatus::Ok;
}

MemStatus Memory::write16(std::uint32_t addr, std::uint16_t value) {
    std::uint32_t off = 0;
    const MemStatus status = locate(addr, 2, off);
    if (status != MemStatus::Ok) {
        return status;
    }
    bytes_[off] = static_cast<std::uint8_t>(value);
    bytes_[off + 1] = static_cast<std::uint8_t>(value >> 8);
    return MemStatus::Ok;
}

MemStatus Memory::write32(std::uint32_t addr, std::uint32_t value) {
    std::uint32_t off = 0;
    const MemStatus status = locate(addr, 4, off);
    if (status != MemStatus::Ok) {
        return status;
    }
    bytes_[off] = static_cast<std::uint8_t>(value);
    bytes_[off + 1] = static_cast<std::uint8_t>(value >> 8);
    bytes_[off + 2] = static_cast<std::uint8_t>(value >> 16);
    bytes_[off + 3] = static_cast<std::uint8_t>(value >> 24);
    return MemStatus::Ok;
}

}  // namespace florv
