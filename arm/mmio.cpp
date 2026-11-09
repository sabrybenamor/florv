#include "mmio.hpp"

#include "xil_io.h"      // the ONLY file in the project allowed to include this
#include "xil_printf.h"

MmioRegion::MmioRegion(std::uintptr_t base, std::size_t size) : base_(base), size_(size) {}

void MmioRegion::check(std::size_t offset) const {
    if (offset + 4 > size_ || (offset & 0x3u) != 0) {
        xil_printf("\r\nFATAL: MmioRegion access at offset 0x%x outside region 0x%x (size 0x%x) or misaligned\r\n",
                   static_cast<unsigned>(offset), static_cast<unsigned>(base_), static_cast<unsigned>(size_));
        for (;;) {
        }  // stop a bad register address is a programming error, never continue
    }
}

std::uint32_t MmioRegion::read32(std::size_t offset) const {
    check(offset);
    return Xil_In32(base_ + offset);
}

void MmioRegion::write32(std::size_t offset, std::uint32_t value) const {
    check(offset);
    Xil_Out32(base_ + offset, value);
}