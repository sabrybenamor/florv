#include "iss.hpp"

#include "decoder.hpp"

namespace florv {

namespace {

bool lessSigned(std::uint32_t a, std::uint32_t b) {
    return static_cast<std::int32_t>(a) < static_cast<std::int32_t>(b);
}


std::uint32_t shiftRightArithmetic(std::uint32_t value, std::uint32_t amount) {
    const std::uint32_t shifted = value >> amount;
    const bool negative = (value & 0x80000000u) != 0;
    return negative ? (shifted | ~(0xFFFFFFFFu >> amount)) : shifted;
}


MemStatus load(const Memory& memory, std::uint32_t addr, unsigned width, std::uint32_t& value) {
    if (width == 1) {
        std::uint8_t byte = 0;
        const MemStatus status = memory.read8(addr, byte);
        value = byte;
        return status;
    }
    if (width == 2) {
        std::uint16_t half = 0;
        const MemStatus status = memory.read16(addr, half);
        value = half;
        return status;
    }
    return memory.read32(addr, value);
}

// Writes the low width bytes (1, 2 or 4) of value.
MemStatus store(Memory& memory, std::uint32_t addr, unsigned width, std::uint32_t value) {
    if (width == 1) {
        return memory.write8(addr, static_cast<std::uint8_t>(value));
    }
    if (width == 2) {
        return memory.write16(addr, static_cast<std::uint16_t>(value));
    }
    return memory.write32(addr, value);
}

}  // namespace

Iss::Iss(Memory& memory) : memory_(memory), pc_(memory.base()) {}

void Iss::reset(std::uint32_t pc) {
    regs_.fill(0);
    pc_ = pc;
    retired_ = 0;
    tohostValue_ = 0;
}

void Iss::setTohost(std::uint32_t address) {
    tohost_ = address;
    hasTohost_ = true;
}

void Iss::setReg(unsigned index, std::uint32_t value) {
    if ((index & 31u) != 0) {
        regs_[index & 31u] = value;
    }
}

StepResult Iss::step() {

    StepResult trap;
    trap.status = StepStatus::Trap;
    trap.record.order = retired_;
    trap.record.pc = pc_;

    std::uint32_t word = 0;
    if (memory_.read32(pc_, word) != MemStatus::Ok) {
        return trap;
    }
    trap.record.insn = word;

    const Instruction in = decode(word);
    const std::uint32_t a = regs_[in.rs1];  // regs_[0] is always 0, and so is an unused field
    const std::uint32_t b = regs_[in.rs2];
    const std::uint32_t imm = static_cast<std::uint32_t>(in.imm);

   
    std::uint32_t nextPc = pc_ + 4;
    std::uint32_t rdValue = 0;
    bool writesRd = false;
    unsigned loadWidth = 0;
    bool loadSigned = false;
    unsigned storeWidth = 0;
    bool halts = false;

    switch (in.op) {
        case Op::Illegal:
            return trap;

        case Op::Lui:
            rdValue = imm;
            writesRd = true;
            break;
        case Op::Auipc:
            rdValue = pc_ + imm;
            writesRd = true;
            break;

        case Op::Jal:
            rdValue = pc_ + 4;
            writesRd = true;
            nextPc = pc_ + imm;
            break;
        case Op::Jalr:
            rdValue = pc_ + 4;
            writesRd = true;
            nextPc = (a + imm) & ~1u;  // a was read before rd is written: rd may be rs1
            break;

        case Op::Beq:
            if (a == b) nextPc = pc_ + imm;
            break;
        case Op::Bne:
            if (a != b) nextPc = pc_ + imm;
            break;
        case Op::Blt:
            if (lessSigned(a, b)) nextPc = pc_ + imm;
            break;
        case Op::Bge:
            if (!lessSigned(a, b)) nextPc = pc_ + imm;
            break;
        case Op::Bltu:
            if (a < b) nextPc = pc_ + imm;
            break;
        case Op::Bgeu:
            if (a >= b) nextPc = pc_ + imm;
            break;

        case Op::Lb:
            loadWidth = 1;
            loadSigned = true;
            break;
        case Op::Lh:
            loadWidth = 2;
            loadSigned = true;
            break;
        case Op::Lw:
            loadWidth = 4;
            break;
        case Op::Lbu:
            loadWidth = 1;
            break;
        case Op::Lhu:
            loadWidth = 2;
            break;

        case Op::Sb:
            storeWidth = 1;
            break;
        case Op::Sh:
            storeWidth = 2;
            break;
        case Op::Sw:
            storeWidth = 4;
            break;

        case Op::Addi:
            rdValue = a + imm;
            writesRd = true;
            break;
        case Op::Slti:
            rdValue = lessSigned(a, imm) ? 1u : 0u;
            writesRd = true;
            break;
        case Op::Sltiu:
            rdValue = a < imm ? 1u : 0u;  // imm was sign-extended, then compared unsigned
            writesRd = true;
            break;
        case Op::Xori:
            rdValue = a ^ imm;
            writesRd = true;
            break;
        case Op::Ori:
            rdValue = a | imm;
            writesRd = true;
            break;
        case Op::Andi:
            rdValue = a & imm;
            writesRd = true;
            break;
        case Op::Slli:
            rdValue = a << (imm & 31u);
            writesRd = true;
            break;
        case Op::Srli:
            rdValue = a >> (imm & 31u);
            writesRd = true;
            break;
        case Op::Srai:
            rdValue = shiftRightArithmetic(a, imm & 31u);
            writesRd = true;
            break;

        case Op::Add:
            rdValue = a + b;
            writesRd = true;
            break;
        case Op::Sub:
            rdValue = a - b;
            writesRd = true;
            break;
        case Op::Sll:
            rdValue = a << (b & 31u);  // only the low 5 bits of the amount count
            writesRd = true;
            break;
        case Op::Slt:
            rdValue = lessSigned(a, b) ? 1u : 0u;
            writesRd = true;
            break;
        case Op::Sltu:
            rdValue = a < b ? 1u : 0u;
            writesRd = true;
            break;
        case Op::Xor:
            rdValue = a ^ b;
            writesRd = true;
            break;
        case Op::Srl:
            rdValue = a >> (b & 31u);
            writesRd = true;
            break;
        case Op::Sra:
            rdValue = shiftRightArithmetic(a, b & 31u);
            writesRd = true;
            break;
        case Op::Or:
            rdValue = a | b;
            writesRd = true;
            break;
        case Op::And:
            rdValue = a & b;
            writesRd = true;
            break;

        case Op::Fence:
            break;  // one core, nothing to order
        case Op::Ecall:
        case Op::Ebreak:
            halts = true;
            break;
    }

    // Only a jump or a taken branch can make this non-zero.
    if ((nextPc & 3u) != 0) {
        return trap;
    }

    StepResult result;
    RetireRecord& record = result.record;
    record.order = retired_;
    record.pc = pc_;
    record.insn = word;
    record.next_pc = nextPc;

    if (loadWidth != 0) {
        const std::uint32_t addr = a + imm;
        std::uint32_t value = 0;
        if (load(memory_, addr, loadWidth, value) != MemStatus::Ok) {
            return trap;
        }
        if (loadSigned) {
            const std::uint32_t sign = 1u << (loadWidth * 8u - 1u);
            value = (value ^ sign) - sign;
        }
        rdValue = value;
        writesRd = true;
        record.is_load = true;
        record.mem_addr = addr;
        record.mem_mask = static_cast<std::uint8_t>((1u << loadWidth) - 1u);
    }

    if (storeWidth != 0) {
        const std::uint32_t addr = a + imm;
        const std::uint32_t value = storeWidth == 4 ? b : b & ((1u << (storeWidth * 8u)) - 1u);
        if (store(memory_, addr, storeWidth, value) != MemStatus::Ok) {
            return trap;
        }
        record.is_store = true;
        record.mem_addr = addr;
        record.mem_mask = static_cast<std::uint8_t>((1u << storeWidth) - 1u);
        record.mem_wdata = value;

        if (hasTohost_ && storeWidth == 4 && addr == tohost_ && value != 0) {
            tohostValue_ = value;
            halts = true;
        }
    }

    // From here on the instruction retires.
    if (writesRd && in.rd != 0) {
        regs_[in.rd] = rdValue;
        record.rd = in.rd;
        record.rd_wdata = rdValue;
    }
    pc_ = nextPc;
    ++retired_;
    result.status = halts ? StepStatus::Halted : StepStatus::Ok;
    return result;
}

}  // namespace florv
