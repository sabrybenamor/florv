#pragma once
 
#include <cstddef>
#include <cstdint>
 
class MmioRegion {
public:
    MmioRegion(std::uintptr_t base, std::size_t size);
 
    std::uint32_t read32(std::size_t offset) const;
    void write32(std::size_t offset, std::uint32_t value) const;
 
    std::uintptr_t base() const { return base_; }
    std::size_t size() const { return size_; }
 
private:
    void check(std::size_t offset) const;
 
    std::uintptr_t base_;
    std::size_t size_;
};