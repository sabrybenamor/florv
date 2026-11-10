// Every instruction word here was copied from objdump -d -M no-aliases,numeric.
// Most are the words of tests/data/decode_cases.S; the comment or text beside each
// word is the objdump line it came from. Each test puts one word at kPc, sets the
// registers it reads, calls step() once and checks the record and the state.

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "doctest.h"
#include "elf_image.hpp"
#include "iss.hpp"
#include "memory.hpp"

using florv::ByteView;
using florv::ElfImage;
using florv::Iss;
using florv::Memory;
using florv::MemStatus;
using florv::RetireRecord;
using florv::StepResult;
using florv::StepStatus;

namespace {

constexpr std::uint32_t kPc = 0x80000100u;    // where the instruction under test sits
constexpr std::uint32_t kData = 0x80001000u;  // where loads and stores go

struct Machine {
    Memory ram;
    Iss iss{ram};

    Machine() { iss.setPc(kPc); }

    // Puts word at the current pc and runs it.
    StepResult run(std::uint32_t word) {
        REQUIRE(ram.write32(iss.pc(), word) == MemStatus::Ok);
        return iss.step();
    }

    std::uint32_t word(std::uint32_t addr) const {
        std::uint32_t value = 0;
        REQUIRE(ram.read32(addr, value) == MemStatus::Ok);
        return value;
    }
};

// The record of an instruction at kPc that falls through and does nothing else.
RetireRecord plain(std::uint32_t word) {
    RetireRecord r;
    r.pc = kPc;
    r.insn = word;
    r.next_pc = kPc + 4;
    return r;
}

// The record a trap at kPc returns: only order, pc and insn.
RetireRecord trapped(std::uint32_t word) {
    RetireRecord r;
    r.pc = kPc;
    r.insn = word;
    return r;
}

}  // namespace

TEST_CASE("Iss: starts at the base of the RAM with all registers zero") {
    Memory ram;
    Iss iss(ram);
    CHECK(iss.pc() == ram.base());
    CHECK(iss.retired() == 0);
    CHECK(iss.tohostValue() == 0);
    for (unsigned i = 0; i < 32; ++i) {
        CHECK(iss.reg(i) == 0);
    }
}

// ---------------------------------------------------------------------------
// Instructions that compute a value into rd.
// ---------------------------------------------------------------------------
namespace {

struct ValueCase {
    std::uint32_t word;
    const char* text;
    unsigned regA;  // 0 when the instruction reads no register
    std::uint32_t valueA;
    unsigned regB;
    std::uint32_t valueB;
    unsigned rd;
    std::uint32_t expected;
};

const ValueCase kValueCases[] = {
    {0x123452B7u, "lui x5,0x12345", 0, 0, 0, 0, 5, 0x12345000u},
    // pc-relative: 0x80000100 + 0xABCDE000 wraps round.
    {0xABCDE897u, "auipc x17,0xabcde", 0, 0, 0, 0, 17, 0x2BCDE100u},

    {0xB2EA8313u, "addi x6,x21,-1234", 21, 1000, 0, 0, 6, 0xFFFFFF16u},  // -234
    // Signed compare with the immediate.
    {0x4D23AB13u, "slti x22,x7,1234 (-5)", 7, 0xFFFFFFFBu, 0, 0, 22, 1},
    {0x4D23AB13u, "slti x22,x7,1234 (1233)", 7, 1233, 0, 0, 22, 1},
    {0x4D23AB13u, "slti x22,x7,1234 (1234)", 7, 1234, 0, 0, 22, 0},
    // The immediate -567 is sign-extended to 0xFFFFFDC9 and then compared unsigned.
    {0xDC9BB413u, "sltiu x8,x23,-567 (5)", 23, 5, 0, 0, 8, 1},
    {0xDC9BB413u, "sltiu x8,x23,-567 (0xffffffff)", 23, 0xFFFFFFFFu, 0, 0, 8, 0},
    {0x2374CC13u, "xori x24,x9,567", 9, 0xFFFF0000u, 0, 0, 24, 0xFFFF0237u},
    {0xFA7CE513u, "ori x10,x25,-89", 25, 0x00000012u, 0, 0, 10, 0xFFFFFFB7u},
    {0x0595FD13u, "andi x26,x11,89", 11, 0xFFFFFFFFu, 0, 0, 26, 0x00000059u},
    {0x013D9613u, "slli x12,x27,0x13", 27, 0x00001234u, 0, 0, 12, 0x91A00000u},
    {0x00D6DE13u, "srli x28,x13,0xd", 13, 0x80000000u, 0, 0, 28, 0x00040000u},
    // Arithmetic shift copies the sign bit; logical shift above does not.
    {0x41BED713u, "srai x14,x29,0x1b (negative)", 29, 0x80000000u, 0, 0, 14, 0xFFFFFFF0u},
    {0x41BED713u, "srai x14,x29,0x1b (positive)", 29, 0x40000000u, 0, 0, 14, 0x00000008u},

    {0x01078F33u, "add x30,x15,x16 (wraps)", 15, 0xFFFFFFFFu, 16, 2, 30, 1},
    {0x402F88B3u, "sub x17,x31,x2 (3-5)", 31, 3, 2, 5, 17, 0xFFFFFFFEu},
    // Only the low 5 bits of the shift amount count: 32 is 0, 33 is 1.
    {0x013911B3u, "sll x3,x18,x19 (by 31)", 18, 1, 19, 31, 3, 0x80000000u},
    {0x013911B3u, "sll x3,x18,x19 (by 0)", 18, 1, 19, 0, 3, 1},
    {0x013911B3u, "sll x3,x18,x19 (by 32)", 18, 1, 19, 32, 3, 1},
    {0x013911B3u, "sll x3,x18,x19 (by 33)", 18, 1, 19, 33, 3, 2},
    // The same two values compared signed and unsigned give opposite answers.
    {0x00522A33u, "slt x20,x4,x5 (-1,1)", 4, 0xFFFFFFFFu, 5, 1, 20, 1},
    {0x00522A33u, "slt x20,x4,x5 (1,-1)", 4, 1, 5, 0xFFFFFFFFu, 20, 0},
    {0x016AB333u, "sltu x6,x21,x22 (0xffffffff,1)", 21, 0xFFFFFFFFu, 22, 1, 6, 0},
    {0x016AB333u, "sltu x6,x21,x22 (1,0xffffffff)", 21, 1, 22, 0xFFFFFFFFu, 6, 1},
    {0x0083CBB3u, "xor x23,x7,x8", 7, 0xFF00FF00u, 8, 0x0FF00FF0u, 23, 0xF0F0F0F0u},
    {0x019C54B3u, "srl x9,x24,x25 (by 4)", 24, 0x80000000u, 25, 4, 9, 0x08000000u},
    {0x019C54B3u, "srl x9,x24,x25 (by 36)", 24, 0x80000000u, 25, 36, 9, 0x08000000u},
    {0x40B55D33u, "sra x26,x10,x11 (by 4)", 10, 0x80000000u, 11, 4, 26, 0xF8000000u},
    {0x40B55D33u, "sra x26,x10,x11 (by 36)", 10, 0x80000000u, 11, 36, 26, 0xF8000000u},
    {0x40B55D33u, "sra x26,x10,x11 (positive)", 10, 0x40000000u, 11, 4, 26, 0x04000000u},
    {0x40B55D33u, "sra x26,x10,x11 (by 0)", 10, 0x80000001u, 11, 0, 26, 0x80000001u},
    {0x01CDE633u, "or x12,x27,x28", 27, 0x000000F0u, 28, 0x0000000Fu, 12, 0x000000FFu},
    {0x00E6FEB3u, "and x29,x13,x14", 13, 0x000000FFu, 14, 0x0000003Cu, 29, 0x0000003Cu},
};

}  // namespace

TEST_CASE("Iss: instructions that compute a value into rd") {
    for (const ValueCase& c : kValueCases) {
        CAPTURE(c.text);
        Machine m;
        m.iss.setReg(c.regA, c.valueA);
        m.iss.setReg(c.regB, c.valueB);

        const StepResult got = m.run(c.word);

        RetireRecord want = plain(c.word);
        want.rd = static_cast<std::uint8_t>(c.rd);
        want.rd_wdata = c.expected;

        CHECK(got.status == StepStatus::Ok);
        CHECK(got.record == want);
        CHECK(m.iss.reg(c.rd) == c.expected);
        CHECK(m.iss.pc() == kPc + 4);
        CHECK(m.iss.retired() == 1);
        // The source registers are untouched (rd is a different register in every case).
        if (c.regA != 0) CHECK(m.iss.reg(c.regA) == c.valueA);
        if (c.regB != 0) CHECK(m.iss.reg(c.regB) == c.valueB);
    }
}

TEST_CASE("Iss: rd may be the same register as both sources") {
    Machine m;
    m.iss.setReg(7, 21);
    const StepResult got = m.run(0x007383B3u);  // add x7,x7,x7
    CHECK(got.status == StepStatus::Ok);
    CHECK(got.record.rd == 7);
    CHECK(got.record.rd_wdata == 42);
    CHECK(m.iss.reg(7) == 42);
}

// ---------------------------------------------------------------------------
// Branches.
// ---------------------------------------------------------------------------
namespace {

struct BranchCase {
    std::uint32_t word;
    const char* text;
    unsigned regA;
    std::uint32_t valueA;
    unsigned regB;
    std::uint32_t valueB;
    std::int32_t offset;  // from the pc of the branch to the next instruction
};

const std::uint32_t kMinus1 = 0xFFFFFFFFu;

const BranchCase kBranchCases[] = {
    // 80000010: beq x6,x21,80000000
    {0xFF5308E3u, "beq equal", 6, 7, 21, 7, -16},
    {0xFF5308E3u, "beq different", 6, 7, 21, 8, 4},
    // 80000014: bne x22,x7,80000094
    {0x087B1063u, "bne different", 22, 7, 7, 8, 128},
    {0x087B1063u, "bne equal", 22, 7, 7, 7, 4},
    // 80000018: blt x8,x23,80000000    signed: -1 < 1
    {0xFF7444E3u, "blt -1,1", 8, kMinus1, 23, 1, -24},
    {0xFF7444E3u, "blt 1,-1", 8, 1, 23, kMinus1, 4},
    {0xFF7444E3u, "blt equal", 8, 5, 23, 5, 4},
    // 8000001c: bge x24,x10,80000094   signed: 1 >= -1
    {0x06AC5C63u, "bge 1,-1", 24, 1, 10, kMinus1, 120},
    {0x06AC5C63u, "bge equal", 24, 5, 10, 5, 120},
    {0x06AC5C63u, "bge -1,1", 24, kMinus1, 10, 1, 4},
    // 80000020: bltu x11,x25,80000000  unsigned: 1 < 0xffffffff
    {0xFF95E0E3u, "bltu 1,0xffffffff", 11, 1, 25, kMinus1, -32},
    {0xFF95E0E3u, "bltu 0xffffffff,1", 11, kMinus1, 25, 1, 4},
    {0xFF95E0E3u, "bltu equal", 11, 5, 25, 5, 4},
    // 80000024: bgeu x26,x12,80000094  unsigned: 0xffffffff >= 1
    {0x06CD7863u, "bgeu 0xffffffff,1", 26, kMinus1, 12, 1, 112},
    {0x06CD7863u, "bgeu equal", 26, 5, 12, 5, 112},
    {0x06CD7863u, "bgeu 1,0xffffffff", 26, 1, 12, kMinus1, 4},
};

}  // namespace

TEST_CASE("Iss: branches, taken and not taken, signed and unsigned") {
    for (const BranchCase& c : kBranchCases) {
        CAPTURE(c.text);
        Machine m;
        m.iss.setReg(c.regA, c.valueA);
        m.iss.setReg(c.regB, c.valueB);

        const StepResult got = m.run(c.word);

        RetireRecord want = plain(c.word);
        want.next_pc = kPc + static_cast<std::uint32_t>(c.offset);

        CHECK(got.status == StepStatus::Ok);
        CHECK(got.record == want);  // no register written, no memory access
        CHECK(m.iss.pc() == want.next_pc);
        CHECK(m.iss.retired() == 1);
    }
}

// ---------------------------------------------------------------------------
// Jumps.
// ---------------------------------------------------------------------------
TEST_CASE("Iss: JAL writes the return address and jumps relative to the pc") {
    Machine m;
    const StepResult got = m.run(0x08C000EFu);  // 80000008: jal x1,80000094

    RetireRecord want = plain(0x08C000EFu);
    want.next_pc = kPc + 140;
    want.rd = 1;
    want.rd_wdata = kPc + 4;

    CHECK(got.status == StepStatus::Ok);
    CHECK(got.record == want);
    CHECK(m.iss.reg(1) == kPc + 4);
    CHECK(m.iss.pc() == kPc + 140);
}

TEST_CASE("Iss: JAL backwards with rd x0 writes no register") {
    Machine m;
    const StepResult got = m.run(0xF6DFF06Fu);  // 80000094: jal x0,80000000

    RetireRecord want = plain(0xF6DFF06Fu);
    want.next_pc = kPc - 148;

    CHECK(got.status == StepStatus::Ok);
    CHECK(got.record == want);
    CHECK(m.iss.pc() == kPc - 148);
}

TEST_CASE("Iss: JALR to an odd sum lands on the even address below it") {
    Machine m;
    m.iss.setReg(20, 0x80001101u - 291u);        // the sum is 0x80001101
    const StepResult got = m.run(0x123A04E7u);  // jalr x9,291(x20)

    RetireRecord want = plain(0x123A04E7u);
    want.next_pc = 0x80001100u;
    want.rd = 9;
    want.rd_wdata = kPc + 4;

    CHECK(got.status == StepStatus::Ok);
    CHECK(got.record == want);
    CHECK(m.iss.reg(9) == kPc + 4);
    CHECK(m.iss.pc() == 0x80001100u);
}

TEST_CASE("Iss: JALR with rd equal to rs1 jumps to the old value") {
    Machine m;
    m.iss.setReg(5, 0x80002000u);
    const StepResult got = m.run(0x000282E7u);  // jalr x5,0(x5)

    CHECK(got.status == StepStatus::Ok);
    CHECK(got.record.next_pc == 0x80002000u);
    CHECK(got.record.rd == 5);
    CHECK(got.record.rd_wdata == kPc + 4);
    CHECK(m.iss.reg(5) == kPc + 4);
    CHECK(m.iss.pc() == 0x80002000u);
}

// ---------------------------------------------------------------------------
// Loads.
// ---------------------------------------------------------------------------
namespace {

struct LoadCase {
    std::uint32_t word;
    const char* text;
    unsigned base;         // the register holding the base address
    std::int32_t imm;      // the offset in the instruction
    std::uint32_t addr;    // where the data is
    unsigned rd;
    std::uint32_t expected;
    std::uint8_t mask;
};

// What the tests put in memory: the byte 0x80 and the half word 0x8000 are the values
// where sign extension and zero extension differ; 0x7F and 0x7FFF are where they agree.
constexpr std::uint32_t kByte80 = kData;        // 0x80
constexpr std::uint32_t kByte7F = kData + 1;    // 0x7F
constexpr std::uint32_t kHalf8000 = kData + 4;  // 0x8000
constexpr std::uint32_t kHalf7FFF = kData + 6;  // 0x7FFF
constexpr std::uint32_t kWord = kData + 8;      // 0x89ABCDEF

const LoadCase kLoadCases[] = {
    {0xEDDD8683u, "lb x13,-291(x27) of 0x80", 27, -291, kByte80, 13, 0xFFFFFF80u, 0x1},
    {0xEDDD8683u, "lb x13,-291(x27) of 0x7f", 27, -291, kByte7F, 13, 0x0000007Fu, 0x1},
    {0x04D84F03u, "lbu x30,77(x16) of 0x80", 16, 77, kByte80, 30, 0x00000080u, 0x1},
    {0x04D84F03u, "lbu x30,77(x16) of 0x7f", 16, 77, kByte7F, 30, 0x0000007Fu, 0x1},
    {0x45671E03u, "lh x28,1110(x14) of 0x8000", 14, 1110, kHalf8000, 28, 0xFFFF8000u, 0x3},
    {0x45671E03u, "lh x28,1110(x14) of 0x7fff", 14, 1110, kHalf7FFF, 28, 0x00007FFFu, 0x3},
    {0xFB3FD883u, "lhu x17,-77(x31) of 0x8000", 31, -77, kHalf8000, 17, 0x00008000u, 0x3},
    {0xFB3FD883u, "lhu x17,-77(x31) of 0x7fff", 31, -77, kHalf7FFF, 17, 0x00007FFFu, 0x3},
    {0xBAAEA783u, "lw x15,-1110(x29)", 29, -1110, kWord, 15, 0x89ABCDEFu, 0xF},
    // A byte and a half taken from inside the word: little-endian, lowest byte first.
    {0x04D84F03u, "lbu x30,77(x16) byte 1 of the word", 16, 77, kWord + 1, 30, 0xCDu, 0x1},
    {0xFB3FD883u, "lhu x17,-77(x31) upper half of the word", 31, -77, kWord + 2, 17, 0x89ABu, 0x3},
};

void fillData(Machine& m) {
    REQUIRE(m.ram.write8(kByte80, 0x80) == MemStatus::Ok);
    REQUIRE(m.ram.write8(kByte7F, 0x7F) == MemStatus::Ok);
    REQUIRE(m.ram.write16(kHalf8000, 0x8000) == MemStatus::Ok);
    REQUIRE(m.ram.write16(kHalf7FFF, 0x7FFF) == MemStatus::Ok);
    REQUIRE(m.ram.write32(kWord, 0x89ABCDEFu) == MemStatus::Ok);
}

}  // namespace

TEST_CASE("Iss: loads extend with the sign or with zeros") {
    for (const LoadCase& c : kLoadCases) {
        CAPTURE(c.text);
        Machine m;
        fillData(m);
        m.iss.setReg(c.base, c.addr - static_cast<std::uint32_t>(c.imm));

        const StepResult got = m.run(c.word);

        RetireRecord want = plain(c.word);
        want.rd = static_cast<std::uint8_t>(c.rd);
        want.rd_wdata = c.expected;
        want.is_load = true;
        want.mem_addr = c.addr;
        want.mem_mask = c.mask;

        CHECK(got.status == StepStatus::Ok);
        CHECK(got.record == want);
        CHECK(m.iss.reg(c.rd) == c.expected);
        CHECK(m.iss.pc() == kPc + 4);
    }
}

// ---------------------------------------------------------------------------
// Stores.
// ---------------------------------------------------------------------------
namespace {

struct StoreCase {
    std::uint32_t word;
    const char* text;
    unsigned base;
    std::int32_t imm;
    unsigned source;
    std::uint32_t wdata;     // what the record reports as stored
    std::uint8_t mask;
    std::uint32_t wordAfter;  // the whole word at kData afterwards
};

// Memory at kData starts as 0x11111111 and the source register holds 0xAABBCCDD.
const StoreCase kStoreCases[] = {
    {0x132181A3u, "sb x18,291(x3)", 3, 291, 18, 0x000000DDu, 0x1, 0x111111DDu},
    {0xEC499EA3u, "sh x4,-291(x19)", 19, -291, 4, 0x0000CCDDu, 0x3, 0x1111CCDDu},
    {0x4542AB23u, "sw x20,1110(x5)", 5, 1110, 20, 0xAABBCCDDu, 0xF, 0xAABBCCDDu},
};

}  // namespace

TEST_CASE("Iss: stores write only the low bytes of the register") {
    for (const StoreCase& c : kStoreCases) {
        CAPTURE(c.text);
        Machine m;
        REQUIRE(m.ram.write32(kData, 0x11111111u) == MemStatus::Ok);
        REQUIRE(m.ram.write32(kData + 4, 0x22222222u) == MemStatus::Ok);
        m.iss.setReg(c.base, kData - static_cast<std::uint32_t>(c.imm));
        m.iss.setReg(c.source, 0xAABBCCDDu);

        const StepResult got = m.run(c.word);

        RetireRecord want = plain(c.word);
        want.is_store = true;
        want.mem_addr = kData;
        want.mem_mask = c.mask;
        want.mem_wdata = c.wdata;

        CHECK(got.status == StepStatus::Ok);
        CHECK(got.record == want);  // rd is 0: a store writes no register
        CHECK(m.word(kData) == c.wordAfter);
        CHECK(m.word(kData + 4) == 0x22222222u);  // the next word is untouched
        CHECK(m.iss.pc() == kPc + 4);
    }
}

TEST_CASE("Iss: a store to the upper bytes of a word leaves the lower ones") {
    Machine m;
    REQUIRE(m.ram.write32(kData, 0x11111111u) == MemStatus::Ok);
    m.iss.setReg(19, kData + 2 + 291);
    m.iss.setReg(4, 0xAABBCCDDu);
    const StepResult got = m.run(0xEC499EA3u);  // sh x4,-291(x19)
    CHECK(got.status == StepStatus::Ok);
    CHECK(got.record.mem_addr == kData + 2);
    CHECK(m.word(kData) == 0xCCDD1111u);
}

// ---------------------------------------------------------------------------
// x0.
// ---------------------------------------------------------------------------
TEST_CASE("Iss: x0 stays zero and a write to it is reported as no register") {
    struct X0Case {
        std::uint32_t word;
        const char* text;
    };
    const X0Case cases[] = {
        {0x07B28013u, "addi x0,x5,123"},
        {0xFFFFF037u, "lui x0,0xfffff"},
        {0x0002A003u, "lw x0,0(x5)"},
        {0x00008067u, "jalr x0,0(x1)"},
        {0xF6DFF06Fu, "jal x0,80000000"},
    };
    for (const X0Case& c : cases) {
        CAPTURE(c.text);
        Machine m;
        REQUIRE(m.ram.write32(kData, 0x89ABCDEFu) == MemStatus::Ok);
        m.iss.setReg(5, kData);
        m.iss.setReg(1, 0x80002000u);

        const StepResult got = m.run(c.word);

        CHECK(got.status == StepStatus::Ok);
        CHECK(got.record.rd == 0);
        CHECK(got.record.rd_wdata == 0);
        CHECK(m.iss.reg(0) == 0);
        CHECK(m.iss.retired() == 1);
    }
}

TEST_CASE("Iss: a load into x0 still reads memory") {
    Machine m;
    REQUIRE(m.ram.write32(kData, 0x89ABCDEFu) == MemStatus::Ok);
    m.iss.setReg(5, kData);
    const StepResult ok = m.run(0x0002A003u);  // lw x0,0(x5)
    CHECK(ok.status == StepStatus::Ok);
    CHECK(ok.record.is_load);
    CHECK(ok.record.mem_addr == kData);
    CHECK(ok.record.mem_mask == 0xF);

    // So it traps like any other load when the address is bad.
    Machine bad;
    bad.iss.setReg(5, 0x90000000u);
    CHECK(bad.run(0x0002A003u).status == StepStatus::Trap);
}

TEST_CASE("Iss: setReg ignores x0") {
    Machine m;
    m.iss.setReg(0, 0x12345678u);
    CHECK(m.iss.reg(0) == 0);
    m.iss.setReg(31, 0x12345678u);
    CHECK(m.iss.reg(31) == 0x12345678u);
}

// ---------------------------------------------------------------------------
// Traps: nothing changes.
// ---------------------------------------------------------------------------
TEST_CASE("Iss: a fetch from outside the RAM traps") {
    Machine m;
    m.iss.setPc(0x70000000u);
    const StepResult got = m.iss.step();

    RetireRecord want;
    want.pc = 0x70000000u;

    CHECK(got.status == StepStatus::Trap);
    CHECK(got.record == want);
    CHECK(m.iss.pc() == 0x70000000u);
    CHECK(m.iss.retired() == 0);
}

TEST_CASE("Iss: a fetch from a pc that is not a multiple of 4 traps") {
    Machine m;
    REQUIRE(m.ram.write32(kPc, 0x007383B3u) == MemStatus::Ok);
    m.iss.setPc(kPc + 2);
    const StepResult got = m.iss.step();
    CHECK(got.status == StepStatus::Trap);
    CHECK(got.record.pc == kPc + 2);
    CHECK(got.record.insn == 0);
    CHECK(m.iss.pc() == kPc + 2);
    CHECK(m.iss.retired() == 0);
}

TEST_CASE("Iss: an illegal word traps and the record names it") {
    for (const std::uint32_t word : {0x00000000u, 0xFFFFFFFFu}) {
        CAPTURE(word);
        Machine m;
        const StepResult got = m.run(word);
        CHECK(got.status == StepStatus::Trap);
        CHECK(got.record == trapped(word));
        CHECK(m.iss.pc() == kPc);
        CHECK(m.iss.retired() == 0);
    }
}

TEST_CASE("Iss: a misaligned or out-of-range load traps and leaves rd alone") {
    struct BadLoad {
        std::uint32_t word;
        const char* text;
        unsigned base;
        std::int32_t imm;
        unsigned rd;
        std::uint32_t addr;
    };
    const BadLoad cases[] = {
        {0xBAAEA783u, "lw x15,-1110(x29) at an odd address", 29, -1110, 15, kData + 1},
        {0xBAAEA783u, "lw x15,-1110(x29) at address 2 of 4", 29, -1110, 15, kData + 2},
        {0x45671E03u, "lh x28,1110(x14) at an odd address", 14, 1110, 28, kData + 1},
        {0xBAAEA783u, "lw x15,-1110(x29) above the RAM", 29, -1110, 15, 0x80010000u},
        {0xEDDD8683u, "lb x13,-291(x27) below the RAM", 27, -291, 13, 0x7FFFFFFFu},
    };
    for (const BadLoad& c : cases) {
        CAPTURE(c.text);
        Machine m;
        m.iss.setReg(c.base, c.addr - static_cast<std::uint32_t>(c.imm));
        m.iss.setReg(c.rd, 0x55555555u);

        const StepResult got = m.run(c.word);

        CHECK(got.status == StepStatus::Trap);
        CHECK(got.record == trapped(c.word));
        CHECK(m.iss.reg(c.rd) == 0x55555555u);
        CHECK(m.iss.pc() == kPc);
        CHECK(m.iss.retired() == 0);
    }
}

TEST_CASE("Iss: a misaligned or out-of-range store traps and writes nothing") {
    {
        Machine m;
        REQUIRE(m.ram.write32(kData, 0x11111111u) == MemStatus::Ok);
        m.iss.setReg(5, kData + 2 - 1110);
        m.iss.setReg(20, 0xAABBCCDDu);
        const StepResult got = m.run(0x4542AB23u);  // sw x20,1110(x5), address 2 of 4
        CHECK(got.status == StepStatus::Trap);
        CHECK(got.record == trapped(0x4542AB23u));
        CHECK(m.word(kData) == 0x11111111u);
        CHECK(m.iss.pc() == kPc);
        CHECK(m.iss.retired() == 0);
    }
    {
        Machine m;
        REQUIRE(m.ram.write32(kData, 0x11111111u) == MemStatus::Ok);
        m.iss.setReg(19, kData + 1 + 291);
        m.iss.setReg(4, 0xAABBCCDDu);
        const StepResult got = m.run(0xEC499EA3u);  // sh x4,-291(x19), odd address
        CHECK(got.status == StepStatus::Trap);
        CHECK(m.word(kData) == 0x11111111u);
    }
    {
        Machine m;
        m.iss.setReg(3, 0x80010000u - 291);
        m.iss.setReg(18, 0xAABBCCDDu);
        const StepResult got = m.run(0x132181A3u);  // sb x18,291(x3), first byte above the RAM
        CHECK(got.status == StepStatus::Trap);
        CHECK(got.record == trapped(0x132181A3u));
        CHECK(m.iss.pc() == kPc);
    }
}

TEST_CASE("Iss: a jump to an address that is not a multiple of 4 traps") {
    Machine m;
    m.iss.setReg(20, 0x80001102u - 291u);  // the sum is 0x80001102
    m.iss.setReg(9, 0x55555555u);
    const StepResult got = m.run(0x123A04E7u);  // jalr x9,291(x20)

    CHECK(got.status == StepStatus::Trap);
    CHECK(got.record == trapped(0x123A04E7u));
    CHECK(m.iss.reg(9) == 0x55555555u);  // the return address was not written
    CHECK(m.iss.pc() == kPc);
    CHECK(m.iss.retired() == 0);

    // 0x80001103 has bit 0 cleared to give 0x80001102, which is still misaligned.
    Machine odd;
    odd.iss.setReg(20, 0x80001103u - 291u);
    CHECK(odd.run(0x123A04E7u).status == StepStatus::Trap);
}

// ---------------------------------------------------------------------------
// Order, sequences and reset.
// ---------------------------------------------------------------------------
TEST_CASE("Iss: order counts retired instructions and a trap does not count") {
    Machine m;
    m.iss.setReg(7, 1);

    const StepResult first = m.run(0x007383B3u);  // add x7,x7,x7
    const StepResult second = m.run(0x007383B3u);
    CHECK(first.record.order == 0);
    CHECK(second.record.order == 1);
    CHECK(second.record.pc == first.record.next_pc);
    CHECK(m.iss.reg(7) == 4);

    const StepResult bad = m.run(0xFFFFFFFFu);
    CHECK(bad.status == StepStatus::Trap);
    CHECK(bad.record.order == 2);
    CHECK(m.iss.retired() == 2);

    const StepResult third = m.run(0x007383B3u);  // replaces the illegal word, same pc
    CHECK(third.status == StepStatus::Ok);
    CHECK(third.record.order == 2);
    CHECK(third.record.pc == bad.record.pc);
    CHECK(m.iss.retired() == 3);
}

TEST_CASE("Iss: reset clears the registers and the count, and keeps the tohost address") {
    Machine m;
    m.iss.setTohost(kData);
    m.iss.setReg(7, 21);
    m.iss.setReg(5, kData);
    m.iss.setReg(6, 9);
    CHECK(m.run(0x007383B3u).status == StepStatus::Ok);      // add x7,x7,x7
    CHECK(m.run(0x0062A023u).status == StepStatus::Halted);  // sw x6,0(x5)
    CHECK(m.iss.tohostValue() == 9);

    m.iss.reset(kPc);
    CHECK(m.iss.pc() == kPc);
    CHECK(m.iss.retired() == 0);
    CHECK(m.iss.tohostValue() == 0);
    for (unsigned i = 0; i < 32; ++i) {
        CHECK(m.iss.reg(i) == 0);
    }

    // The tohost address survived the reset.
    m.iss.setReg(5, kData);
    m.iss.setReg(6, 3);
    CHECK(m.run(0x0062A023u).status == StepStatus::Halted);
    CHECK(m.iss.tohostValue() == 3);
}

// ---------------------------------------------------------------------------
// Halting.
// ---------------------------------------------------------------------------
TEST_CASE("Iss: a word store of a non-zero value to tohost retires and halts") {
    Machine m;
    m.iss.setTohost(kData);
    m.iss.setReg(5, kData);
    m.iss.setReg(6, 1);
    const StepResult got = m.run(0x0062A023u);  // sw x6,0(x5)

    RetireRecord want = plain(0x0062A023u);
    want.is_store = true;
    want.mem_addr = kData;
    want.mem_mask = 0xF;
    want.mem_wdata = 1;

    CHECK(got.status == StepStatus::Halted);
    CHECK(got.record == want);            // the record is complete
    CHECK(m.word(kData) == 1);            // memory was written
    CHECK(m.iss.tohostValue() == 1);
    CHECK(m.iss.pc() == kPc + 4);         // and the instruction retired
    CHECK(m.iss.retired() == 1);
}

TEST_CASE("Iss: stores that do not halt") {
    SUBCASE("a zero word to tohost") {
        Machine m;
        m.iss.setTohost(kData);
        m.iss.setReg(5, kData);
        CHECK(m.run(0x0062A023u).status == StepStatus::Ok);  // sw x6,0(x5), x6 is 0
        CHECK(m.iss.tohostValue() == 0);
    }
    SUBCASE("a non-zero word next to tohost") {
        Machine m;
        m.iss.setTohost(kData);
        m.iss.setReg(5, kData + 4);
        m.iss.setReg(6, 1);
        CHECK(m.run(0x0062A023u).status == StepStatus::Ok);
        CHECK(m.iss.tohostValue() == 0);
    }
    SUBCASE("a half word to tohost") {
        Machine m;
        m.iss.setTohost(kData);
        m.iss.setReg(5, kData);
        m.iss.setReg(6, 1);
        CHECK(m.run(0x00629023u).status == StepStatus::Ok);  // sh x6,0(x5)
        CHECK(m.iss.tohostValue() == 0);
    }
    SUBCASE("a byte to tohost") {
        Machine m;
        m.iss.setTohost(kData);
        m.iss.setReg(5, kData);
        m.iss.setReg(6, 1);
        CHECK(m.run(0x00628023u).status == StepStatus::Ok);  // sb x6,0(x5)
        CHECK(m.iss.tohostValue() == 0);
    }
    SUBCASE("no tohost address was set") {
        Machine m;
        m.iss.setReg(5, kData);
        m.iss.setReg(6, 1);
        CHECK(m.run(0x0062A023u).status == StepStatus::Ok);
        CHECK(m.iss.tohostValue() == 0);
    }
    SUBCASE("no tohost address was set and the RAM starts at address 0") {
        // Address 0 is what an unset tohost address would be if it were compared.
        Memory ram(0, 4096);
        Iss iss(ram);
        REQUIRE(ram.write32(0x100, 0x0062A023u) == MemStatus::Ok);  // sw x6,0(x5)
        iss.setPc(0x100);
        iss.setReg(6, 1);  // x5 is 0, so the store goes to address 0
        const StepResult got = iss.step();
        CHECK(got.status == StepStatus::Ok);
        CHECK(got.record.mem_addr == 0);
        CHECK(iss.tohostValue() == 0);
    }
}

TEST_CASE("Iss: ECALL and EBREAK retire and halt; FENCE retires and does nothing") {
    {
        Machine m;
        const StepResult got = m.run(0x00000073u);  // ecall
        CHECK(got.status == StepStatus::Halted);
        CHECK(got.record == plain(0x00000073u));
        CHECK(m.iss.pc() == kPc + 4);
        CHECK(m.iss.retired() == 1);
        CHECK(m.iss.tohostValue() == 0);
    }
    {
        Machine m;
        const StepResult got = m.run(0x00100073u);  // ebreak
        CHECK(got.status == StepStatus::Halted);
        CHECK(got.record == plain(0x00100073u));
        CHECK(m.iss.retired() == 1);
    }
    {
        Machine m;
        const StepResult got = m.run(0x0FF0000Fu);  // fence iorw,iorw
        CHECK(got.status == StepStatus::Ok);
        CHECK(got.record == plain(0x0FF0000Fu));
        CHECK(m.iss.pc() == kPc + 4);
        CHECK(m.iss.retired() == 1);
    }
}

// ---------------------------------------------------------------------------
// A whole program: tests/data/minimal.elf, loaded the way the real tools will.
// objdump of it:
//   80000000: 00100513  addi  x10,x0,1
//   80000004: 00001597  auipc x11,0x1
//   80000008: 01858593  addi  x11,x11,24     # 8000101c, tohost
//   8000000c: 00a5a023  sw    x10,0(x11)
//   80000010: 0000006f  jal   x0,80000010
// ---------------------------------------------------------------------------
namespace {

std::vector<std::uint8_t> readFile(const std::string& path) {
    std::vector<std::uint8_t> bytes;
    std::FILE* file = std::fopen(path.c_str(), "rb");
    if (file == nullptr) {
        return bytes;
    }
    std::uint8_t chunk[4096];
    std::size_t got = 0;
    while ((got = std::fread(chunk, 1, sizeof(chunk), file)) > 0) {
        bytes.insert(bytes.end(), chunk, chunk + got);
    }
    std::fclose(file);
    return bytes;
}

}  // namespace

TEST_CASE("Iss: minimal.elf halts with tohost 1 on exactly its store") {
    const std::vector<std::uint8_t> file = readFile(FLORV_TEST_DATA_DIR "/minimal.elf");
    REQUIRE_FALSE(file.empty());
    const auto image = ElfImage::parse(ByteView{file.data(), file.size()});
    REQUIRE(image.has_value());
    const auto tohost = image->findSymbol("tohost");
    REQUIRE(tohost.has_value());

    Memory ram;
    REQUIRE(ram.loadSegments(*image) == MemStatus::Ok);
    Iss iss(ram);
    iss.reset(image->entry());
    iss.setTohost(*tohost);

    RetireRecord want;

    StepResult got = iss.step();  // addi x10,x0,1
    want.order = 0;
    want.pc = 0x80000000u;
    want.insn = 0x00100513u;
    want.next_pc = 0x80000004u;
    want.rd = 10;
    want.rd_wdata = 1;
    CHECK(got.status == StepStatus::Ok);
    CHECK(got.record == want);

    got = iss.step();  // auipc x11,0x1
    want.order = 1;
    want.pc = 0x80000004u;
    want.insn = 0x00001597u;
    want.next_pc = 0x80000008u;
    want.rd = 11;
    want.rd_wdata = 0x80001004u;
    CHECK(got.status == StepStatus::Ok);
    CHECK(got.record == want);

    got = iss.step();  // addi x11,x11,24
    want.order = 2;
    want.pc = 0x80000008u;
    want.insn = 0x01858593u;
    want.next_pc = 0x8000000Cu;
    want.rd = 11;
    want.rd_wdata = 0x8000101Cu;
    CHECK(got.status == StepStatus::Ok);
    CHECK(got.record == want);

    got = iss.step();  // sw x10,0(x11)
    want = RetireRecord{};
    want.order = 3;
    want.pc = 0x8000000Cu;
    want.insn = 0x00A5A023u;
    want.next_pc = 0x80000010u;
    want.is_store = true;
    want.mem_addr = 0x8000101Cu;
    want.mem_mask = 0xF;
    want.mem_wdata = 1;
    CHECK(got.status == StepStatus::Halted);
    CHECK(got.record == want);

    CHECK(iss.tohostValue() == 1);
    CHECK(iss.retired() == 4);
    CHECK(iss.pc() == 0x80000010u);

    std::uint32_t stored = 0;
    REQUIRE(ram.read32(*tohost, stored) == MemStatus::Ok);
    CHECK(stored == 1);
}
