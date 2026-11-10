// Every instruction word in this file was copied from objdump, not worked out by hand.
// The source was assembled at 0x80000000 with
//   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0x80000000
// and read back with
//   riscv64-unknown-elf-objdump -d -M no-aliases,numeric
// The comment beside each word is the objdump line it came from.

#include <cstdint>

#include "decoder.hpp"
#include "doctest.h"

using florv::decode;
using florv::Instruction;
using florv::Op;

TEST_CASE("decode: I-format immediate, negative") {
    const Instruction addi = decode(0xFFF10093u);  // addi x1,x2,-1
    CHECK(addi.op == Op::Addi);
    CHECK(addi.rd == 1);
    CHECK(addi.rs1 == 2);
    CHECK(addi.rs2 == 0);
    CHECK(addi.imm == -1);
    CHECK(addi.raw == 0xFFF10093u);

    const Instruction lowest = decode(0x80030293u);  // addi x5,x6,-2048
    CHECK(lowest.op == Op::Addi);
    CHECK(lowest.rd == 5);
    CHECK(lowest.rs1 == 6);
    CHECK(lowest.imm == -2048);

    const Instruction lw = decode(0xFFC42383u);  // lw x7,-4(x8)
    CHECK(lw.op == Op::Lw);
    CHECK(lw.rd == 7);
    CHECK(lw.rs1 == 8);
    CHECK(lw.imm == -4);

    const Instruction jalr = decode(0xFF4480E7u);  // jalr x1,-12(x9)
    CHECK(jalr.op == Op::Jalr);
    CHECK(jalr.rd == 1);
    CHECK(jalr.rs1 == 9);
    CHECK(jalr.imm == -12);
}

TEST_CASE("decode: S-format immediate, negative") {
    const Instruction sw = decode(0xFEA5AC23u);  // sw x10,-8(x11)
    CHECK(sw.op == Op::Sw);
    CHECK(sw.rd == 0);
    CHECK(sw.rs1 == 11);
    CHECK(sw.rs2 == 10);
    CHECK(sw.imm == -8);

    const Instruction sb = decode(0x80C68023u);  // sb x12,-2048(x13)
    CHECK(sb.op == Op::Sb);
    CHECK(sb.rd == 0);
    CHECK(sb.rs1 == 13);
    CHECK(sb.rs2 == 12);
    CHECK(sb.imm == -2048);
}

TEST_CASE("decode: B-format immediate, negative") {
    // At 0x80000018, branching back to 0x80000000.
    const Instruction beq = decode(0xFEF704E3u);  // beq x14,x15,80000000
    CHECK(beq.op == Op::Beq);
    CHECK(beq.rd == 0);
    CHECK(beq.rs1 == 14);
    CHECK(beq.rs2 == 15);
    CHECK(beq.imm == -24);
}

TEST_CASE("decode: U-format immediate, negative") {
    const Instruction lui = decode(0x80000937u);  // lui x18,0x80000
    CHECK(lui.op == Op::Lui);
    CHECK(lui.rd == 18);
    CHECK(lui.rs1 == 0);
    CHECK(lui.rs2 == 0);
    CHECK(lui.imm == INT32_MIN);  // 0x80000000, already shifted left by 12

    const Instruction auipc = decode(0xFFFFF997u);  // auipc x19,0xfffff
    CHECK(auipc.op == Op::Auipc);
    CHECK(auipc.rd == 19);
    CHECK(auipc.imm == -4096);
}

TEST_CASE("decode: J-format immediate, negative") {
    // At 0x8000002C, jumping back to 0x80000000.
    const Instruction near = decode(0xFD5FF0EFu);  // jal x1,80000000
    CHECK(near.op == Op::Jal);
    CHECK(near.rd == 1);
    CHECK(near.rs1 == 0);
    CHECK(near.rs2 == 0);
    CHECK(near.imm == -44);

    // At 0x80000030, jumping back to 0x7FFFF000: far enough to use imm[19:12].
    const Instruction far = decode(0xFD1FE06Fu);  // jal x0,7ffff000
    CHECK(far.op == Op::Jal);
    CHECK(far.rd == 0);
    CHECK(far.imm == -4144);
}

TEST_CASE("decode: positive immediates in all five formats") {
    const Instruction addi = decode(0x7FF20193u);  // addi x3,x4,2047
    CHECK(addi.op == Op::Addi);
    CHECK(addi.rd == 3);
    CHECK(addi.rs1 == 4);
    CHECK(addi.imm == 2047);

    const Instruction sw = decode(0x7E532FA3u);  // sw x5,2047(x6)
    CHECK(sw.op == Op::Sw);
    CHECK(sw.rs1 == 6);
    CHECK(sw.rs2 == 5);
    CHECK(sw.imm == 2047);

    // At 0x80000058, branching forward to 0x80000C1C.
    const Instruction beq = decode(0x3C2082E3u);  // beq x1,x2,80000c1c
    CHECK(beq.op == Op::Beq);
    CHECK(beq.rs1 == 1);
    CHECK(beq.rs2 == 2);
    CHECK(beq.imm == 3012);

    const Instruction lui = decode(0x123450B7u);  // lui x1,0x12345
    CHECK(lui.op == Op::Lui);
    CHECK(lui.rd == 1);
    CHECK(lui.imm == 0x12345000);

    // At 0x8000005C, jumping forward to 0x80000C1C.
    const Instruction jal = decode(0x3C1000EFu);  // jal x1,80000c1c
    CHECK(jal.op == Op::Jal);
    CHECK(jal.rd == 1);
    CHECK(jal.imm == 3008);
}

TEST_CASE("decode: shifts by a constant put the amount in imm") {
    const Instruction slli = decode(0x01FA9A13u);  // slli x20,x21,0x1f
    CHECK(slli.op == Op::Slli);
    CHECK(slli.rd == 20);
    CHECK(slli.rs1 == 21);
    CHECK(slli.rs2 == 0);
    CHECK(slli.imm == 31);

    // SRAI differs from SRLI only in funct7, which must not leak into imm.
    const Instruction srai = decode(0x405BDB13u);  // srai x22,x23,0x5
    CHECK(srai.op == Op::Srai);
    CHECK(srai.rd == 22);
    CHECK(srai.rs1 == 23);
    CHECK(srai.rs2 == 0);
    CHECK(srai.imm == 5);
}

TEST_CASE("decode: register-register instructions have three registers and no immediate") {
    const Instruction add = decode(0x01AC8C33u);  // add x24,x25,x26
    CHECK(add.op == Op::Add);
    CHECK(add.rd == 24);
    CHECK(add.rs1 == 25);
    CHECK(add.rs2 == 26);
    CHECK(add.imm == 0);

    // SUB differs from ADD only in funct7.
    const Instruction sub = decode(0x41DE0DB3u);  // sub x27,x28,x29
    CHECK(sub.op == Op::Sub);
    CHECK(sub.rd == 27);
    CHECK(sub.rs1 == 28);
    CHECK(sub.rs2 == 29);
    CHECK(sub.imm == 0);
}

TEST_CASE("decode: FENCE, ECALL and EBREAK carry only op and raw") {
    const Instruction fence = decode(0x0FF0000Fu);  // fence iorw,iorw
    CHECK(fence.op == Op::Fence);
    CHECK(fence.rd == 0);
    CHECK(fence.rs1 == 0);
    CHECK(fence.rs2 == 0);
    CHECK(fence.imm == 0);
    CHECK(fence.raw == 0x0FF0000Fu);

    const Instruction ecall = decode(0x00000073u);  // ecall
    CHECK(ecall.op == Op::Ecall);
    CHECK(ecall.rs2 == 0);
    CHECK(ecall.imm == 0);

    // EBREAK is ECALL with bit 20 set; that bit must not show up as rs2 or imm.
    const Instruction ebreak = decode(0x00100073u);  // ebreak
    CHECK(ebreak.op == Op::Ebreak);
    CHECK(ebreak.rs2 == 0);
    CHECK(ebreak.imm == 0);
}

// ---------------------------------------------------------------------------
// One case per instruction: the 37 computational, memory and control
// instructions. The words are the objdump output for tests/data/decode_cases.S,
// in the same order, assembled at 0x80000000. A branch or jump offset is the
// target address minus the instruction's own address; both are in the text.
// ---------------------------------------------------------------------------
namespace {

struct Case {
    std::uint32_t word;
    Op op;
    int rd;
    int rs1;
    int rs2;
    std::int32_t imm;
    const char* text;  // the objdump line the word came from
};

// A field the instruction does not have is expected to be 0.
const Case kCases[] = {
    // Upper immediate and jumps
    {0x123452B7u, Op::Lui, 5, 0, 0, 0x12345000, "lui x5,0x12345"},
    {0xABCDE897u, Op::Auipc, 17, 0, 0, -0x54322000, "auipc x17,0xabcde"},  // 0xABCDE000
    {0x08C000EFu, Op::Jal, 1, 0, 0, 140, "80000008: jal x1,80000094"},
    {0x123A04E7u, Op::Jalr, 9, 20, 0, 291, "jalr x9,291(x20)"},

    // Branches
    {0xFF5308E3u, Op::Beq, 0, 6, 21, -16, "80000010: beq x6,x21,80000000"},
    {0x087B1063u, Op::Bne, 0, 22, 7, 128, "80000014: bne x22,x7,80000094"},
    {0xFF7444E3u, Op::Blt, 0, 8, 23, -24, "80000018: blt x8,x23,80000000"},
    {0x06AC5C63u, Op::Bge, 0, 24, 10, 120, "8000001c: bge x24,x10,80000094"},
    {0xFF95E0E3u, Op::Bltu, 0, 11, 25, -32, "80000020: bltu x11,x25,80000000"},
    {0x06CD7863u, Op::Bgeu, 0, 26, 12, 112, "80000024: bgeu x26,x12,80000094"},

    // Loads
    {0xEDDD8683u, Op::Lb, 13, 27, 0, -291, "lb x13,-291(x27)"},
    {0x45671E03u, Op::Lh, 28, 14, 0, 1110, "lh x28,1110(x14)"},
    {0xBAAEA783u, Op::Lw, 15, 29, 0, -1110, "lw x15,-1110(x29)"},
    {0x04D84F03u, Op::Lbu, 30, 16, 0, 77, "lbu x30,77(x16)"},
    {0xFB3FD883u, Op::Lhu, 17, 31, 0, -77, "lhu x17,-77(x31)"},

    // Stores
    {0x132181A3u, Op::Sb, 0, 3, 18, 291, "sb x18,291(x3)"},
    {0xEC499EA3u, Op::Sh, 0, 19, 4, -291, "sh x4,-291(x19)"},
    {0x4542AB23u, Op::Sw, 0, 5, 20, 1110, "sw x20,1110(x5)"},

    // Register-immediate
    {0xB2EA8313u, Op::Addi, 6, 21, 0, -1234, "addi x6,x21,-1234"},
    {0x4D23AB13u, Op::Slti, 22, 7, 0, 1234, "slti x22,x7,1234"},
    {0xDC9BB413u, Op::Sltiu, 8, 23, 0, -567, "sltiu x8,x23,-567"},
    {0x2374CC13u, Op::Xori, 24, 9, 0, 567, "xori x24,x9,567"},
    {0xFA7CE513u, Op::Ori, 10, 25, 0, -89, "ori x10,x25,-89"},
    {0x0595FD13u, Op::Andi, 26, 11, 0, 89, "andi x26,x11,89"},
    {0x013D9613u, Op::Slli, 12, 27, 0, 19, "slli x12,x27,0x13"},
    {0x00D6DE13u, Op::Srli, 28, 13, 0, 13, "srli x28,x13,0xd"},
    {0x41BED713u, Op::Srai, 14, 29, 0, 27, "srai x14,x29,0x1b"},

    // Register-register
    {0x01078F33u, Op::Add, 30, 15, 16, 0, "add x30,x15,x16"},
    {0x402F88B3u, Op::Sub, 17, 31, 2, 0, "sub x17,x31,x2"},
    {0x013911B3u, Op::Sll, 3, 18, 19, 0, "sll x3,x18,x19"},
    {0x00522A33u, Op::Slt, 20, 4, 5, 0, "slt x20,x4,x5"},
    {0x016AB333u, Op::Sltu, 6, 21, 22, 0, "sltu x6,x21,x22"},
    {0x0083CBB3u, Op::Xor, 23, 7, 8, 0, "xor x23,x7,x8"},
    {0x019C54B3u, Op::Srl, 9, 24, 25, 0, "srl x9,x24,x25"},
    {0x40B55D33u, Op::Sra, 26, 10, 11, 0, "sra x26,x10,x11"},
    {0x01CDE633u, Op::Or, 12, 27, 28, 0, "or x12,x27,x28"},
    {0x00E6FEB3u, Op::And, 29, 13, 14, 0, "and x29,x13,x14"},
};

}  // namespace

TEST_CASE("decode: every computational, memory and control instruction") {
    // 37 rows, and no instruction listed twice: together these mean none is missing.
    CHECK(sizeof(kCases) / sizeof(kCases[0]) == 37);
    bool seen[256] = {};
    for (const Case& c : kCases) {
        CAPTURE(c.text);
        CHECK_FALSE(seen[static_cast<std::uint8_t>(c.op)]);
        seen[static_cast<std::uint8_t>(c.op)] = true;
    }

    for (const Case& c : kCases) {
        CAPTURE(c.text);  // a failure prints which instruction it was
        const Instruction got = decode(c.word);
        CHECK(got.op == c.op);
        CHECK(got.rd == c.rd);
        CHECK(got.rs1 == c.rs1);
        CHECK(got.rs2 == c.rs2);
        CHECK(got.imm == c.imm);
        CHECK(got.raw == c.word);
    }
}

TEST_CASE("decode: JAL backwards, the last line of decode_cases.S") {
    const Instruction jal = decode(0xF6DFF06Fu);  // 80000094: jal x0,80000000
    CHECK(jal.op == Op::Jal);
    CHECK(jal.rd == 0);
    CHECK(jal.imm == -148);
}
