#include <cstdint>

#include "mmio.hpp"
#include "xil_printf.h"
#include "xparameters.h"


#ifndef XPAR_RV_RIG_0_BASEADDR
#error "rv_rig base address macro not found: check the BASEADDR name in xparameters.h"
#endif
constexpr std::uintptr_t kRigBase = XPAR_RV_RIG_0_BASEADDR;
constexpr std::size_t kRigSize = 0x20;  // 8 registers x 4 bytes

namespace reg {
constexpr std::size_t kId = 0x00;
constexpr std::size_t kScratch = 0x04;
}  // namespace reg

constexpr std::uint32_t kExpectedId = 0x52560001u;

namespace {

int g_pass = 0;
int g_total = 0;

void report(const char* name, std::uint32_t got, std::uint32_t expected) {
    const bool ok = (got == expected);
    ++g_total;
    if (ok) {
        ++g_pass;
    }
    xil_printf("  %s: got 0x%08x, expected 0x%08x -> %s\r\n", name, static_cast<unsigned>(got),
               static_cast<unsigned>(expected), ok ? "PASS" : "FAIL");
}

void testScratch(const MmioRegion& rig, const char* name, std::uint32_t pattern) {
    rig.write32(reg::kScratch, pattern);
    report(name, rig.read32(reg::kScratch), pattern);
}

void testWalkingOne(const MmioRegion& rig) {
    for (unsigned bit = 0; bit < 32; ++bit) {
        const std::uint32_t pattern = 1u << bit;
        rig.write32(reg::kScratch, pattern);
        const std::uint32_t got = rig.read32(reg::kScratch);
        if (got != pattern) {
            xil_printf("  walking one fails at bit %u\r\n", bit);
            report("scratch walking one", got, pattern);
            return;
        }
    }
    report("scratch walking one (32 bits)", 0x80000000u, 0x80000000u);
}

}  // namespace

int main() {
    xil_printf("\r\n=== florv rig: register loopback (task 1.6) ===\r\n");
    xil_printf("rv_rig base 0x%08x\r\n", static_cast<unsigned>(kRigBase));

    const MmioRegion rig(kRigBase, kRigSize);

    report("ID register", rig.read32(reg::kId), kExpectedId);

    testScratch(rig, "scratch 0x00000000", 0x00000000u);
    testScratch(rig, "scratch 0xFFFFFFFF", 0xFFFFFFFFu);
    testScratch(rig, "scratch 0xA5A5A5A5", 0xA5A5A5A5u);
    testWalkingOne(rig);

    rig.write32(reg::kId, 0xDEADBEEFu);
    report("ID read-only after write", rig.read32(reg::kId), kExpectedId);

    xil_printf("RESULT: %s (%d/%d)\r\n", g_pass == g_total ? "PASS" : "FAIL", g_pass, g_total);
    for (;;) {
    }
}