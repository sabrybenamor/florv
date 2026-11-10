#pragma once

#include <cstdint>

namespace florv {


enum class Op : std::uint8_t {
    Illegal,

    Lui,
    Auipc,
    Jal,
    Jalr,

    Beq,
    Bne,
    Blt,
    Bge,
    Bltu,
    Bgeu,

    Lb,
    Lh,
    Lw,
    Lbu,
    Lhu,

    Sb,
    Sh,
    Sw,

    Addi,
    Slti,
    Sltiu,
    Xori,
    Ori,
    Andi,
    Slli,
    Srli,
    Srai,

    Add,
    Sub,
    Sll,
    Slt,
    Sltu,
    Xor,
    Srl,
    Sra,
    Or,
    And,

    Fence,
    Ecall,
    Ebreak,
};


struct Instruction {
    Op op = Op::Illegal;
    std::uint8_t rd = 0;
    std::uint8_t rs1 = 0;
    std::uint8_t rs2 = 0;
    std::int32_t imm = 0;
    std::uint32_t raw = 0;
};

static_assert(sizeof(Instruction) == 12, "Instruction should stay small");

}  // namespace florv
