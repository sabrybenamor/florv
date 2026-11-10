# LUI and AUIPC: the upper 20 bits, with the lowest, highest and sign-bit patterns,
# and the usual pairs they form with ADDI, where a negative low part makes the upper
# part one larger.

    .section .text
    # LUI: the immediate goes to bits 31..12, the low 12 bits are 0
    lui     t0, 0x00000
    lui     t1, 0x00001             # 0x00001000
    lui     t2, 0x12345             # 0x12345000
    lui     t3, 0x7FFFF             # 0x7FFFF000
    lui     t4, 0x80000             # 0x80000000
    lui     t5, 0xFFFFF             # 0xFFFFF000
    lui     zero, 0xABCDE           # discarded

    # LUI + ADDI builds any constant. When bit 11 of the constant is set, ADDI
    # subtracts, so the LUI value is one larger: 0x12345FFF = 0x12346000 - 1.
    lui     a0, 0x12346
    addi    a0, a0, -1              # 0x12345FFF
    lui     a1, 0x12345
    addi    a1, a1, 0x7FF           # 0x123457FF
    lui     a2, 0x80000
    addi    a2, a2, -1              # 0x7FFFFFFF
    lui     a3, 0xFFFFF
    addi    a3, a3, -2048           # 0xFFFFE800
    li      a4, 0xDEADBEEF          # the pair the assembler chooses
    li      a5, 0x00000800          # needs LUI 1 and ADDI -2048

    # AUIPC: the same immediate, added to the address of the instruction itself
    auipc   s0, 0x00000             # its own address
    auipc   s1, 0x00000             # 4 more than the line above
    auipc   s2, 0x00001             # + 0x1000
    auipc   s3, 0x12345
    auipc   s4, 0x7FFFF             # wraps past the top of the address space
    auipc   s5, 0x80000             # wraps to the low addresses
    auipc   s6, 0xFFFFF             # 0x1000 below
    auipc   zero, 0x00001           # discarded

    # AUIPC + ADDI reaches a label; AUIPC + a load reads it
    la      s7, word                # auipc + addi
    lw      s8, 0(s7)
    lw      s9, word                # auipc + lw with the low part as the offset
    sub     s10, s1, s0             # the two addresses above differ by 4

    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)
1:  j       1b

    .section .data
    .balign 4
word:
    .word   0xCAFEF00D
