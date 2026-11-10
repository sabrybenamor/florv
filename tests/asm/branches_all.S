# All six branches, each taken and not taken, forwards and backwards. a0 counts the
# paths that ran: a branch that goes the wrong way changes the trace at once.

    .section .text
    li      a0, 0
    li      s0, -1                  # 0xFFFFFFFF
    li      s1, 1
    li      s2, 1
    li      s3, 0x80000000
    li      s4, 0x7FFFFFFF

    # BEQ
    beq     s1, s2, 1f              # equal: taken
    addi    a0, a0, 100             # skipped
1:  beq     s0, s1, 2f              # different: not taken
    addi    a0, a0, 1
2:
    # BNE
    bne     s0, s1, 3f              # taken
    addi    a0, a0, 100
3:  bne     s1, s2, 4f              # not taken
    addi    a0, a0, 1
4:
    # BLT, signed
    blt     s0, s1, 5f              # -1 < 1: taken
    addi    a0, a0, 100
5:  blt     s1, s0, 6f              # not taken
    addi    a0, a0, 1
6:  blt     s1, s2, 7f              # equal: not taken
    addi    a0, a0, 1
7:  blt     s3, s4, 8f              # most negative < largest: taken
    addi    a0, a0, 100
8:
    # BGE, signed
    bge     s1, s0, 9f              # 1 >= -1: taken
    addi    a0, a0, 100
9:  bge     s1, s2, 10f             # equal: taken
    addi    a0, a0, 100
10: bge     s0, s1, 11f             # not taken
    addi    a0, a0, 1
11:
    # BLTU, unsigned
    bltu    s1, s0, 12f             # 1 < 0xFFFFFFFF: taken
    addi    a0, a0, 100
12: bltu    s0, s1, 13f             # not taken
    addi    a0, a0, 1
13: bltu    s1, s2, 14f             # equal: not taken
    addi    a0, a0, 1
14: bltu    s4, s3, 15f             # 0x7FFFFFFF < 0x80000000: taken
    addi    a0, a0, 100
15:
    # BGEU, unsigned
    bgeu    s0, s1, 16f             # taken
    addi    a0, a0, 100
16: bgeu    s1, s2, 17f             # equal: taken
    addi    a0, a0, 100
17: bgeu    s1, s0, 18f             # not taken
    addi    a0, a0, 1
18:
    # Comparing with x0
    beq     zero, zero, 19f         # always taken
    addi    a0, a0, 100
19: bne     zero, zero, 20f         # never taken
    addi    a0, a0, 1
20:
    # Backward branches: three loops counting down from 3
    li      t0, 3
21: addi    a0, a0, 1
    addi    t0, t0, -1
    bne     t0, zero, 21b           # taken twice, then falls through

    li      t0, 3
22: addi    a0, a0, 1
    addi    t0, t0, -1
    blt     zero, t0, 22b           # while 0 < t0

    li      t0, 3
23: addi    a0, a0, 1
    addi    t0, t0, -1
    bgeu    t0, s1, 23b             # while t0 >= 1, unsigned

    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)
1:  j       1b
