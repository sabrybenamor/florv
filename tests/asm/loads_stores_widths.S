# LB, LBU, LH, LHU, LW and SB, SH, SW. Loads of bytes and half words whose top bit is
# set and clear, with positive and negative offsets; stores of each width, read back
# as words to see which bytes changed.

    .section .text
    la      s0, values
    la      s1, scratch

    # Words
    lw      t0, 0(s0)               # 0x89ABCDEF
    lw      t1, 4(s0)               # 0x7F80FF00
    lw      t2, 8(s0)               # 0x7FFF8000

    # Bytes of 0x7F80FF00, lowest address first: 00 FF 80 7F
    lb      t3, 4(s0)               # 0x00
    lb      t4, 5(s0)               # 0xFF -> -1
    lb      t5, 6(s0)               # 0x80 -> 0xFFFFFF80
    lb      t6, 7(s0)               # 0x7F
    lbu     a0, 4(s0)
    lbu     a1, 5(s0)               # 0x000000FF
    lbu     a2, 6(s0)               # 0x00000080
    lbu     a3, 7(s0)

    # Half words of 0x7FFF8000: 0x8000 then 0x7FFF
    lh      a4, 8(s0)               # 0xFFFF8000
    lh      a5, 10(s0)              # 0x00007FFF
    lhu     a6, 8(s0)               # 0x00008000
    lhu     a7, 10(s0)

    # Negative offsets, from a pointer past the data
    addi    s2, s0, 12
    lw      t0, -12(s2)
    lh      t1, -4(s2)
    lhu     t2, -2(s2)
    lb      t3, -6(s2)
    lbu     t4, -11(s2)             # byte 1 of 0x89ABCDEF: 0xCD

    # Stores. scratch starts as 0x11111111 0x22222222 0x33333333 0x44444444.
    li      s3, 0xAABBCCDD
    sw      s3, 0(s1)               # the whole word
    lw      t0, 0(s1)

    sh      s3, 4(s1)               # low half only: 0x2222CCDD
    lw      t1, 4(s1)
    sh      s3, 6(s1)               # upper half too: 0xCCDDCCDD
    lw      t2, 4(s1)

    sb      s3, 8(s1)               # one byte at a time
    lw      t3, 8(s1)               # 0x333333DD
    sb      s3, 9(s1)
    sb      s3, 10(s1)
    sb      s3, 11(s1)
    lw      t4, 8(s1)               # 0xDDDDDDDD

    # Negative offsets for stores
    addi    s4, s1, 16
    sw      s0, -4(s4)              # an address as data
    sh      s3, -2(s4)
    sb      s3, -3(s4)
    lw      t5, 12(s1)

    # What was stored, read back in the other widths
    lb      t6, 0(s1)               # 0xDD -> negative
    lbu     a0, 0(s1)
    lh      a1, 0(s1)               # 0xCCDD -> negative
    lhu     a2, 2(s1)               # 0xAABB
    lb      a3, 3(s1)               # 0xAA -> negative

    # Zero, and x0 as the source of a store
    sw      zero, 0(s1)
    lw      a4, 0(s1)
    sb      zero, 5(s1)
    lw      a5, 4(s1)

    # A load into x0 is discarded
    lw      zero, 0(s0)

    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)
1:  j       1b

    .section .data
    .balign 4
values:
    .word   0x89ABCDEF
    .word   0x7F80FF00
    .word   0x7FFF8000
scratch:
    .word   0x11111111
    .word   0x22222222
    .word   0x33333333
    .word   0x44444444
