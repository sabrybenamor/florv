#pragma once

#include <cstddef>
#include <cstdint>

namespace florv {

// Everything one retired instruction did that can be seen from outside the core.
// The ISS fills one per step(); the VHDL core will produce the same fields, and the
// checker compares the two field by field. The field names follow RVFI.

struct RetireRecord {
    std::uint32_t order = 0;    // retire count, the first instruction is 0
    std::uint32_t pc = 0;       // address of this instruction
    std::uint32_t insn = 0;     // the instruction word
    std::uint32_t next_pc = 0;  // address of the instruction that runs next
    std::uint32_t rd_wdata = 0;
    std::uint32_t mem_addr = 0;
    std::uint32_t mem_wdata = 0;
    std::uint8_t rd = 0;
    std::uint8_t mem_mask = 0;
    bool is_load = false;
    bool is_store = false;
};

bool operator==(const RetireRecord& a, const RetireRecord& b);
bool operator!=(const RetireRecord& a, const RetireRecord& b);


constexpr std::size_t kRetireTextSize = 160;
std::size_t toString(const RetireRecord& record, char* buffer, std::size_t size);

}  // namespace florv
