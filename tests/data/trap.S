# A program that traps: its second instruction is not RV32I. "florv iss" must exit
# with 2 after retiring one instruction.
#
# Build, from tests/data in the MSYS2 UCRT64 shell (the flags are explained in minimal.S):
#
#   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0x80000000 \
#       -Wl,-n,--no-relax trap.S -o trap.elf

    .section .text
    .globl _start
_start:
    li      a0, 1               # retires normally
    .word   0xFFFFFFFF          # illegal: traps here, at 0x80000004
1:  j       1b

    .section .data
    .balign 4
    .globl tohost
tohost:
    .word   0
