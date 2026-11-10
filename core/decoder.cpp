#include "decoder.hpp"

namespace florv {

namespace {

enum class Format : std::uint8_t {
    R,      // rd, rs1, rs2
    I,      // rd, rs1, 12-bit immediate
    Shift,  // rd, rs1, 5-bit shift amount
    S,      // rs1, rs2, 12-bit immediate
    B,      // rs1, rs2, 13-bit branch offset
    U,      // rd, upper 20 bits
    J,      // rd, 21-bit jump offset
    None,   // no fields: FENCE, ECALL, EBREAK
};


struct Row {
    std::uint32_t mask;
    std::uint32_t match;
    Op op;
    Format format;
};

constexpr std::uint32_t kOpcodeOnly = 0x0000007Fu;
constexpr std::uint32_t kWithFunct3 = 0x0000707Fu;
constexpr std::uint32_t kWithFunct7 = 0xFE00707Fu;
constexpr std::uint32_t kWholeWord = 0xFFFFFFFFu;

constexpr std::uint32_t kLui = 0x37;
constexpr std::uint32_t kAuipc = 0x17;
constexpr std::uint32_t kJal = 0x6F;
constexpr std::uint32_t kJalr = 0x67;
constexpr std::uint32_t kBranch = 0x63;
constexpr std::uint32_t kLoad = 0x03;
constexpr std::uint32_t kStore = 0x23;
constexpr std::uint32_t kOpImm = 0x13;
constexpr std::uint32_t kOpReg = 0x33;
constexpr std::uint32_t kMiscMem = 0x0F;

constexpr Row byOpcode(std::uint32_t opcode, Op op, Format format) {
    return {kOpcodeOnly, opcode, op, format};
}

constexpr Row byFunct3(std::uint32_t opcode, std::uint32_t funct3, Op op, Format format) {
    return {kWithFunct3, opcode | (funct3 << 12), op, format};
}

constexpr Row byFunct7(std::uint32_t opcode, std::uint32_t funct3, std::uint32_t funct7,
                       Op op, Format format) {
    return {kWithFunct7, opcode | (funct3 << 12) | (funct7 << 25), op, format};
}

constexpr Row kTable[] = {
    byOpcode(kLui, Op::Lui, Format::U),
    byOpcode(kAuipc, Op::Auipc, Format::U),
    byOpcode(kJal, Op::Jal, Format::J),
    byFunct3(kJalr, 0, Op::Jalr, Format::I),

    byFunct3(kBranch, 0, Op::Beq, Format::B),
    byFunct3(kBranch, 1, Op::Bne, Format::B),
    byFunct3(kBranch, 4, Op::Blt, Format::B),
    byFunct3(kBranch, 5, Op::Bge, Format::B),
    byFunct3(kBranch, 6, Op::Bltu, Format::B),
    byFunct3(kBranch, 7, Op::Bgeu, Format::B),

    byFunct3(kLoad, 0, Op::Lb, Format::I),
    byFunct3(kLoad, 1, Op::Lh, Format::I),
    byFunct3(kLoad, 2, Op::Lw, Format::I),
    byFunct3(kLoad, 4, Op::Lbu, Format::I),
    byFunct3(kLoad, 5, Op::Lhu, Format::I),

    byFunct3(kStore, 0, Op::Sb, Format::S),
    byFunct3(kStore, 1, Op::Sh, Format::S),
    byFunct3(kStore, 2, Op::Sw, Format::S),

    byFunct3(kOpImm, 0, Op::Addi, Format::I),
    byFunct3(kOpImm, 2, Op::Slti, Format::I),
    byFunct3(kOpImm, 3, Op::Sltiu, Format::I),
    byFunct3(kOpImm, 4, Op::Xori, Format::I),
    byFunct3(kOpImm, 6, Op::Ori, Format::I),
    byFunct3(kOpImm, 7, Op::Andi, Format::I),
    byFunct7(kOpImm, 1, 0x00, Op::Slli, Format::Shift),
    byFunct7(kOpImm, 5, 0x00, Op::Srli, Format::Shift),
    byFunct7(kOpImm, 5, 0x20, Op::Srai, Format::Shift),

    byFunct7(kOpReg, 0, 0x00, Op::Add, Format::R),
    byFunct7(kOpReg, 0, 0x20, Op::Sub, Format::R),
    byFunct7(kOpReg, 1, 0x00, Op::Sll, Format::R),
    byFunct7(kOpReg, 2, 0x00, Op::Slt, Format::R),
    byFunct7(kOpReg, 3, 0x00, Op::Sltu, Format::R),
    byFunct7(kOpReg, 4, 0x00, Op::Xor, Format::R),
    byFunct7(kOpReg, 5, 0x00, Op::Srl, Format::R),
    byFunct7(kOpReg, 5, 0x20, Op::Sra, Format::R),
    byFunct7(kOpReg, 6, 0x00, Op::Or, Format::R),
    byFunct7(kOpReg, 7, 0x00, Op::And, Format::R),

    byFunct3(kMiscMem, 0, Op::Fence, Format::None),
    {kWholeWord, 0x00000073u, Op::Ecall, Format::None},
    {kWholeWord, 0x00100073u, Op::Ebreak, Format::None},
};


constexpr std::uint32_t bits(std::uint32_t word, unsigned high, unsigned low) {
    return (word >> low) & ((1u << (high - low + 1u)) - 1u);
}

constexpr std::int32_t signExtend(std::uint32_t value, unsigned width) {
    const std::uint32_t sign = 1u << (width - 1u);
    return static_cast<std::int32_t>((value ^ sign) - sign);
}

constexpr std::int32_t immI(std::uint32_t raw) {
    return signExtend(bits(raw, 31, 20), 12);
}

constexpr std::int32_t immS(std::uint32_t raw) {
    return signExtend((bits(raw, 31, 25) << 5) | bits(raw, 11, 7), 12);
}

constexpr std::int32_t immB(std::uint32_t raw) {
    return signExtend((bits(raw, 31, 31) << 12) | (bits(raw, 7, 7) << 11) |
                          (bits(raw, 30, 25) << 5) | (bits(raw, 11, 8) << 1),
                      13);
}

constexpr std::int32_t immU(std::uint32_t raw) {
    return static_cast<std::int32_t>(raw & 0xFFFFF000u);
}

constexpr std::int32_t immJ(std::uint32_t raw) {
    return signExtend((bits(raw, 31, 31) << 20) | (bits(raw, 19, 12) << 12) |
                          (bits(raw, 20, 20) << 11) | (bits(raw, 30, 21) << 1),
                      21);
}

}  // namespace

Instruction decode(std::uint32_t raw) {
    Instruction result;
    result.raw = raw;

    const Row* found = nullptr;
    for (const Row& row : kTable) {
        if ((raw & row.mask) == row.match) {
            found = &row;
            break;
        }
    }
    if (found == nullptr) {
        return result;  // op is Illegal, every field but raw is 0
    }
    result.op = found->op;

    const auto rd = static_cast<std::uint8_t>(bits(raw, 11, 7));
    const auto rs1 = static_cast<std::uint8_t>(bits(raw, 19, 15));
    const auto rs2 = static_cast<std::uint8_t>(bits(raw, 24, 20));

    switch (found->format) {
        case Format::R:
            result.rd = rd;
            result.rs1 = rs1;
            result.rs2 = rs2;
            break;
        case Format::I:
            result.rd = rd;
            result.rs1 = rs1;
            result.imm = immI(raw);
            break;
        case Format::Shift:
            result.rd = rd;
            result.rs1 = rs1;
            result.imm = static_cast<std::int32_t>(rs2);  // the shift amount sits where rs2 would
            break;
        case Format::S:
            result.rs1 = rs1;
            result.rs2 = rs2;
            result.imm = immS(raw);
            break;
        case Format::B:
            result.rs1 = rs1;
            result.rs2 = rs2;
            result.imm = immB(raw);
            break;
        case Format::U:
            result.rd = rd;
            result.imm = immU(raw);
            break;
        case Format::J:
            result.rd = rd;
            result.imm = immJ(raw);
            break;
        case Format::None:
            break;
    }
    return result;
}

}  // namespace florv
