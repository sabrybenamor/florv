# The smallest program for tests/link.ld and tests/start.S: it stores 1 to tohost.
# Its job is to prove the layout works, in the ISS and in Spike.
#
# Build, from the repo root in the MSYS2 UCRT64 shell:
#
#   mkdir -p tests/build
#   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -T tests/link.ld \
#       tests/start.S tests/asm/hello.S -o tests/build/hello.elf

    .section .text
    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)           # tohost = 1: finished, passed
1:  j       1b
