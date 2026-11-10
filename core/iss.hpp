#pragma once

#include <array>
#include <cstdint>

#include "memory.hpp"
#include "retire_record.hpp"

namespace florv {

enum class StepStatus : std::uint8_t {
    Ok,      
    Halted,  
    Trap,    
};

struct StepResult {
    RetireRecord record;
    StepStatus status = StepStatus::Ok;
};


class Iss {
public:
    explicit Iss(Memory& memory);

   
    void reset(std::uint32_t pc);

    void setTohost(std::uint32_t address);

    StepResult step();

    std::uint32_t pc() const { return pc_; }
    void setPc(std::uint32_t pc) { pc_ = pc; }

    // index is 0 to 31. x0 reads as 0 and a write to it is ignored.
    std::uint32_t reg(unsigned index) const { return regs_[index & 31u]; }
    void setReg(unsigned index, std::uint32_t value);

    std::uint32_t retired() const { return retired_; }
    std::uint32_t tohostValue() const { return tohostValue_; }

private:
    Memory& memory_;
    std::array<std::uint32_t, 32> regs_{};
    std::uint32_t pc_;
    std::uint32_t retired_ = 0;
    std::uint32_t tohost_ = 0;
    std::uint32_t tohostValue_ = 0;
    bool hasTohost_ = false;
};

}  // namespace florv
