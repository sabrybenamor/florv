# The program of tb/tb_rv_core_insns.vhd, part 1. It runs each of the 40 RV32I
# instructions at least once, and every load and store at every legal offset
# inside a word. The testbench holds the words of this file and, for each
# instruction that retires, the record the ISS gives for it.
#
# Build, from the repo root (the ELF is not committed; no test reads it):
#
#   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
#       -Ttext=0x80000000 -Wl,-n,--no-relax \
#       tests/data/core_insns.S -o tests/build/core_insns.elf
#   riscv64-unknown-elf-objdump -d -M no-aliases,numeric tests/build/core_insns.elf
#
# Rules: the code stays below 0x80000400 and the data is at 0x80000400 and up
# (the testbench has 2 KiB of RAM); there is no tohost, so in "florv iss" the
# program ends at the ecall. In the testbench it goes on to the ebreak and then
# traps on the illegal word at "stop".

    .option norvc           # 32-bit encodings only, no compressed instructions

    .section .text
    .globl _start
_start:
    # ---- Values the rest of the program uses ------------------------------
    lui   x1, 0x12345
    addi  x1, x1, 0x678         # x1 = 0x12345678
    addi  x2, x0, -1            # x2 = 0xffffffff: -1 signed, the largest unsigned
    addi  x3, x0, 5             # x3 = 5
    lui   x4, 0x80000           # x4 = 0x80000000: the most negative number

    # ---- Register and immediate -------------------------------------------
    slti  x10, x2, 1            # -1 < 1 signed: 1 (unsigned it would be 0)
    sltiu x11, x3, -1           # 5 < 0xffffffff unsigned: 1 (signed it would be 0)
    xori  x12, x1, -1           # every bit inverted
    ori   x13, x1, 0x700
    andi  x14, x1, 0x0f0
    slli  x15, x1, 4
    srli  x16, x4, 4            # zeros come in from the left
    srai  x17, x4, 4            # copies of the sign bit come in

    # ---- Register and register --------------------------------------------
    add   x18, x1, x2
    sub   x19, x1, x2
    sll   x20, x1, x3
    slt   x21, x2, x3           # -1 < 5 signed: 1
    sltu  x22, x2, x3           # 0xffffffff < 5 unsigned: 0
    xor   x23, x1, x2
    srl   x24, x4, x3
    sra   x25, x4, x3
    or    x26, x1, x3
    and   x27, x1, x17
    sll   x28, x3, x2           # only the low 5 bits of x2 count: a shift by 31

    auipc x29, 0x1              # this pc + 0x1000
    fence

    # ---- x0 ---------------------------------------------------------------
    addi  x0, x1, 1             # the destination is x0: nothing is written
    add   x30, x0, x0           # x0 still reads as 0

    # ---- Loads at every legal offset --------------------------------------
    lui   x5, 0x80000
    addi  x5, x5, 0x400         # x5 = 0x80000400, the data
    lui   x6, 0xe1a27
    addi  x6, x6, 0x384         # x6 = 0xe1a27384: bytes 84 73 a2 e1 from the lowest

    sw    x6, 0(x5)
    lw    x10, 0(x5)
    lb    x11, 0(x5)            # 84: negative
    lb    x12, 1(x5)            # 73: positive
    lb    x13, 2(x5)            # a2: negative
    lb    x14, 3(x5)            # e1: negative
    lbu   x15, 0(x5)
    lbu   x16, 1(x5)
    lbu   x17, 2(x5)
    lbu   x18, 3(x5)
    lh    x19, 0(x5)            # 7384: positive
    lh    x20, 2(x5)            # e1a2: negative
    lhu   x21, 0(x5)
    lhu   x22, 2(x5)
    lw    x0, 0(x5)             # a load into x0: the read happens, nothing is written

    # ---- Stores at every legal offset -------------------------------------
    # Six words are filled with 0x11223344, then one byte or one half of each is
    # overwritten, and each word is read back: the other bytes must be unchanged.
    lui   x7, 0x11223
    addi  x7, x7, 0x344         # x7 = 0x11223344
    sw    x7, 8(x5)
    sw    x7, 12(x5)
    sw    x7, 16(x5)
    sw    x7, 20(x5)
    sw    x7, 24(x5)
    sw    x7, 28(x5)
    sb    x6, 8(x5)             # byte 0
    sb    x6, 13(x5)            # byte 1
    sb    x6, 18(x5)            # byte 2
    sb    x6, 23(x5)            # byte 3
    sh    x6, 24(x5)            # lower half
    sh    x6, 30(x5)            # upper half
    lw    x23, 8(x5)
    lw    x24, 12(x5)
    lw    x25, 16(x5)
    lw    x26, 20(x5)
    lw    x27, 24(x5)
    lw    x28, 28(x5)

    # ---- Negative offsets -------------------------------------------------
    addi  x8, x5, 64            # x8 = 0x80000440
    sw    x1, -4(x8)            # to 0x8000043c
    lw    x9, -4(x8)
    sb    x3, -5(x8)            # to 0x8000043b, byte 3 of its word
    lbu   x10, -5(x8)

    # ---- Branches that are not taken --------------------------------------
    beq   x2, x3, stop
    bne   x3, x3, stop
    blt   x3, x2, stop          # 5 < -1 signed: no
    blt   x3, x3, stop          # equal: no
    bge   x2, x3, stop          # -1 >= 5 signed: no
    bltu  x2, x3, stop          # 0xffffffff < 5 unsigned: no
    bltu  x3, x3, stop          # equal: no
    bgeu  x3, x2, stop          # 5 >= 0xffffffff unsigned: no

    # ---- Branches that are taken ------------------------------------------
    # Each one jumps over a jump to "stop".
    beq   x3, x3, 1f
    jal   x0, stop
1:  bne   x2, x3, 1f
    jal   x0, stop
1:  blt   x2, x3, 1f            # -1 < 5 signed
    jal   x0, stop
1:  bge   x3, x2, 1f            # 5 >= -1 signed
    jal   x0, stop
1:  bge   x3, x3, 1f            # equal
    jal   x0, stop
1:  bltu  x3, x2, 1f            # 5 < 0xffffffff unsigned
    jal   x0, stop
1:  bgeu  x2, x3, 1f            # 0xffffffff >= 5 unsigned
    jal   x0, stop
1:  bgeu  x3, x3, 1f            # equal
    jal   x0, stop
1:

    # ---- A branch backwards: a loop of three rounds -----------------------
    addi  x11, x0, 3
loop:
    addi  x11, x11, -1
    bne   x11, x0, loop         # taken twice, then not taken

    # ---- Jumps ------------------------------------------------------------
    jal   x0, forward           # no link: the destination is x0
func:
    addi  x12, x12, 1
    jalr  x0, 0(x1)             # return; no link
forward:
    addi  x12, x0, 10
    jal   x1, func              # a jump backwards, with the link in x1

    auipc x13, 0                # x13 = this pc
    jalr  x13, 13(x13)          # to this pc + 8: bit 0 of the target is cleared.
                                # rs1 and rd are the same register: the target
                                # comes from the old value, then x13 = pc + 4
    jal   x0, stop              # jumped over

    auipc x14, 0                # x14 = this pc
    addi  x14, x14, 20
    jalr  x15, -4(x14)          # a negative offset: to the auipc + 16
    jal   x0, stop              # jumped over

    # ---- The two instructions that halt the ISS ---------------------------
    ecall
    ebreak

stop:
    .word 0x00000000            # an illegal word: the core traps here
