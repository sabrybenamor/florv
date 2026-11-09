# The smallest program that has everything the ELF loader handles: code, initialised
# data between the signature labels, the tohost word and zero-initialised space.
# tests/unit/test_elf_file.cpp loads minimal.elf and checks it against the addresses
# and words that readelf, nm and objdump report for it.
#
# Build, from tests/data in the MSYS2 UCRT64 shell:
#
#   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0x80000000 \
#       -Wl,-n,--no-relax minimal.S -o minimal.elf
#
# -Wl,-n keeps the ELF headers out of the loadable segment, so it starts at 0x80000000.
# -Wl,--no-relax keeps "la" independent of the gp register, which this program never sets.

    .section .text
    .globl _start
_start:
    li      a0, 1
    la      a1, tohost
    sw      a0, 0(a1)           # tohost = 1 is the convention for "test passed"
1:  j       1b

    .section .data
    .balign 4
    .globl begin_signature
begin_signature:
    .word   0x11223344
    .word   0xAABBCCDD
    .globl end_signature
end_signature:

    .globl tohost
tohost:
    .word   0

    .section .bss
    .balign 4
    .globl scratch
scratch:
    .space  64
