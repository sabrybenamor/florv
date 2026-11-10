# ADD, SUB, AND, OR, XOR and their immediate forms, on values that wrap around,
# change sign or have every bit set. No program here checks its own results: the
# trace is compared with Spike instruction by instruction.
#
# Rules for every program in tests/asm:
#   - give a register a value before reading it (Spike starts with values in t0, a0
#     and a1; the ISS starts with zeros);
#   - no ecall, no ebreak, nothing that traps;
#   - end by storing 1 to tohost, then loop.
# Build all of them with tools\build_tests.bat.

    .section .text
    li      s0, 0x12345678
    li      s1, 0x0F0F0F0F
    li      s2, -1                  # 0xFFFFFFFF
    li      s3, 1
    li      s4, 0x7FFFFFFF          # the largest positive value
    li      s5, 0x80000000          # the most negative value

    # Register-register
    add     t0, s0, s1
    add     t1, s2, s3              # -1 + 1 wraps to 0
    add     t2, s4, s3              # 0x7FFFFFFF + 1 becomes 0x80000000
    add     t3, s5, s5              # 0x80000000 * 2 wraps to 0
    sub     t4, s0, s1
    sub     t5, s3, s2              # 1 - (-1) = 2
    sub     t6, zero, s3            # 0 - 1 = -1
    sub     a0, s5, s3              # 0x80000000 - 1 becomes 0x7FFFFFFF
    sub     a1, s0, s0              # 0
    and     a2, s0, s1
    and     a3, s0, s2              # and with all ones: unchanged
    or      a4, s0, s1
    or      a5, s0, zero            # or with zero: unchanged
    xor     a6, s0, s1
    xor     a7, s0, s0              # xor with itself: 0
    xor     s6, s0, s2              # xor with all ones: every bit flipped

    # Register-immediate, at both ends of the 12-bit range
    addi    t0, s0, 2047
    addi    t1, s0, -2048
    addi    t2, s2, 1               # wraps to 0
    addi    t3, s4, 1               # becomes 0x80000000
    addi    t4, zero, -1
    andi    t5, s0, 0x0FF
    andi    t6, s0, -256            # the immediate is sign-extended to 0xFFFFFF00
    andi    a0, s2, 2047
    ori     a1, s0, 0x700
    ori     a2, zero, -1            # all ones
    ori     a3, s5, 1
    xori    a4, s0, -1              # flips every bit
    xori    a5, s0, 0x555
    xori    a6, s2, -1              # 0

    # x0 as the destination: the write is discarded
    add     zero, s0, s1
    addi    zero, s0, 100
    add     a7, zero, zero          # still 0

    # The destination is also a source
    add     s0, s0, s0
    sub     s1, s1, s3
    xori    s2, s2, 0x0F0

    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)               # tohost = 1: finished
1:  j       1b
