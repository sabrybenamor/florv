# SLL, SRL, SRA and SLLI, SRLI, SRAI. Shift amounts 0, 1 and 31, and register amounts
# of 32, 33 and 63, of which only the low 5 bits count. Negative and positive values
# for the arithmetic shift.

    .section .text
    li      s0, 0x80000001          # negative, with bit 0 set
    li      s1, 0x7FFFFFFE          # positive
    li      s2, 0xDEADBEEF
    li      s3, 1

    li      a0, 0
    li      a1, 1
    li      a2, 31
    li      a3, 32                  # counts as 0
    li      a4, 33                  # counts as 1
    li      a5, 63                  # counts as 31
    li      a6, -1                  # low 5 bits are 31
    li      a7, 4

    # Shift left
    sll     t0, s2, a0
    sll     t1, s2, a1
    sll     t2, s3, a2              # 1 << 31 = 0x80000000
    sll     t3, s2, a3              # by 32: unchanged
    sll     t4, s2, a4              # by 33: as by 1
    sll     t5, s3, a5              # by 63: as by 31
    sll     t6, s3, a6
    sll     t0, s2, a7

    # Shift right logical: zeros come in at the top
    srl     t1, s0, a0
    srl     t2, s0, a1
    srl     t3, s0, a2              # 1
    srl     t4, s0, a3              # by 32: unchanged
    srl     t5, s0, a4
    srl     t6, s0, a5
    srl     t0, s2, a7

    # Shift right arithmetic: copies of the sign bit come in at the top
    sra     t1, s0, a0
    sra     t2, s0, a1              # 0xC0000000
    sra     t3, s0, a2              # -1
    sra     t4, s0, a3              # by 32: unchanged
    sra     t5, s0, a4
    sra     t6, s0, a5
    sra     t0, s1, a1              # positive: zeros come in
    sra     t1, s1, a2              # 0
    sra     t2, s2, a7

    # The immediate forms
    slli    t3, s2, 0
    slli    t4, s2, 1
    slli    t5, s3, 31
    slli    t6, s2, 16
    srli    t0, s0, 0
    srli    t1, s0, 1
    srli    t2, s0, 31
    srli    t3, s2, 16
    srai    t4, s0, 0
    srai    t5, s0, 1
    srai    t6, s0, 31              # -1
    srai    t0, s1, 31              # 0
    srai    t1, s2, 16

    # A value shifted by itself, and into x0
    sll     s3, s3, s3              # 1 << 1 = 2
    srl     zero, s2, a1

    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)
1:  j       1b
