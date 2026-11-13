# The words of tb/tb_rv_core_insns.vhd, part 2: instructions that must trap.
# This file is not one program. The testbench builds a program of four words
# for each case and runs it from 0x80000000:
#
#   word 0   lui  x1, 0x80000
#   word 1   addi x1, x1, 0x100       x1 = 0x80000100
#   word 2   addi x2, x0, -1          (or, for a branch case, a branch that is
#                                      not taken)
#   word 3   the instruction that must trap
#
# So three instructions retire, the fourth traps at 0x8000000c, and nothing but
# the four fetches reaches the memory port.
#
# Build, from the repo root (the ELF is not committed; no test reads it):
#
#   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
#       -Ttext=0x80000000 -Wl,-n,--no-relax \
#       tests/data/core_traps.S -o tests/build/core_traps.elf
#   riscv64-unknown-elf-objdump -d -M no-aliases,numeric tests/build/core_traps.elf
#
# Every jump or branch to an address that is not a multiple of 4 goes to its
# own address + 2, so it is the same word wherever it stands.

    .option norvc           # 32-bit encodings only, no compressed instructions

    .section .text
    .globl _start
_start:
prefix:
    lui   x1, 0x80000
    addi  x1, x1, 0x100
    addi  x2, x0, -1

# ---- Cases of one word: it is word 3 -------------------------------------
single_cases:
    # A load from an address that is not a multiple of its size
    lh    x3, 1(x1)
    lh    x3, 3(x1)
    lhu   x3, 1(x1)
    lhu   x3, 3(x1)
    lw    x3, 1(x1)
    lw    x3, 2(x1)
    lw    x3, 3(x1)

    # A store to an address that is not a multiple of its size
    sh    x2, 1(x1)
    sh    x2, 3(x1)
    sw    x2, 1(x1)
    sw    x2, 2(x1)
    sw    x2, 3(x1)

    # A jump to an address that is not a multiple of 4
    jal   x3, . + 2
    jalr  x3, 2(x1)             # to 0x80000102
    jalr  x3, -1(x1)            # to 0x800000ff, and bit 0 is cleared: 0x800000fe

# ---- Cases of two words: words 2 and 3 -----------------------------------
# The same branch to its own address + 2, first with operands that do not take
# it (it retires and the core goes on), then with operands that take it (trap).
# x1 = 0x80000100 is negative as a signed number and large as an unsigned one.
branch_cases:
    beq   x1, x0, . + 2          # not taken
    beq   x0, x0, . + 2          # taken

    bne   x0, x0, . + 2          # not taken
    bne   x1, x0, . + 2          # taken

    blt   x0, x1, . + 2          # not taken
    blt   x1, x0, . + 2          # taken

    bge   x1, x0, . + 2          # not taken
    bge   x0, x1, . + 2          # taken

    bltu  x1, x0, . + 2          # not taken
    bltu  x0, x1, . + 2          # taken

    bgeu  x0, x1, . + 2          # not taken
    bgeu  x1, x0, . + 2          # taken
end_cases:
