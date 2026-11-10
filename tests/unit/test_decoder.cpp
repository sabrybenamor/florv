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
