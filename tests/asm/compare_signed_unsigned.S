# SLT, SLTU, SLTI and SLTIU on pairs where the signed and the unsigned answer are
# opposite: -1 is just below 0 when signed and the largest value when unsigned.

    .section .text
    li      s0, -1                  # 0xFFFFFFFF
    li      s1, 1
    li      s2, 0x80000000          # most negative signed, 2^31 unsigned
    li      s3, 0x7FFFFFFF          # largest signed
    li      s4, 0
    li      s5, 5
    li      s6, 5

    # -1 against 1
    slt     t0, s0, s1              # signed:   -1 < 1            -> 1
    sltu    t1, s0, s1              # unsigned: 0xFFFFFFFF < 1    -> 0
    slt     t2, s1, s0              # 0
    sltu    t3, s1, s0              # 1

    # 0x80000000 against 0x7FFFFFFF
    slt     t4, s2, s3              # 1
    sltu    t5, s2, s3              # 0
    slt     t6, s3, s2              # 0
    sltu    a0, s3, s2              # 1

    # Equal values, and zero
    slt     a1, s5, s6              # 0
    sltu    a2, s5, s6              # 0
    slt     a3, s4, s1              # 0 < 1 -> 1
    slt     a4, s0, s4              # -1 < 0 -> 1
    sltu    a5, s0, s4              # 0
    sltu    a6, s4, s0              # 1
    sltu    a7, zero, s5            # "is s5 not zero": 1
    sltu    t0, zero, s4            # 0

    # The immediate forms. SLTIU sign-extends its immediate and then compares
    # unsigned, so -1 means 0xFFFFFFFF.
    slti    t1, s0, 0               # -1 < 0 -> 1
    slti    t2, s1, 0               # 0
    slti    t3, s5, 5               # equal -> 0
    slti    t4, s5, 6               # 1
    slti    t5, s5, -1              # 5 < -1 -> 0
    slti    t6, s0, -1              # equal -> 0
    slti    a0, s2, -2048           # 1
    slti    a1, s3, 2047            # 0
    sltiu   a2, s5, 6               # 1
    sltiu   a3, s5, 5               # 0
    sltiu   a4, s5, -1              # 5 < 0xFFFFFFFF -> 1
    sltiu   a5, s0, -1              # equal -> 0
    sltiu   a6, s4, 1               # "is s4 zero": 1
    sltiu   a7, s5, 1               # 0
    sltiu   t0, s2, -2048           # 0x80000000 < 0xFFFFF800 -> 1
    sltiu   t1, s0, 2047            # 0

    # The result replaces one of its sources
    slt     s0, s0, s1              # 1
    sltu    s2, s3, s2              # 1

    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)
1:  j       1b
