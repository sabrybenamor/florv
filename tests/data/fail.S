# A program that reports failure: it stores 2 to tohost. "florv iss" must exit with 1.
#
# Build, from tests/data in the MSYS2 UCRT64 shell (the flags are explained in minimal.S):
#
#   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0x80000000 \
#       -Wl,-n,--no-relax fail.S -o fail.elf

    .section .text
    .globl _start
_start:
    li      a0, 2
    la      a1, tohost
    sw      a0, 0(a1)           # any value but 1 means "test failed"
1:  j       1b

    .section .data
    .balign 4
    .globl tohost
tohost:
    .word   0
