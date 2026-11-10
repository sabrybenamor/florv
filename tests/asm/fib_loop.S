# A real loop: computes the first 24 Fibonacci numbers into an array, then adds the
# array up with a second loop. Loads, stores, adds and backward branches run many
# times with changing values.

    .set    COUNT, 24

    .section .text
    la      s0, table               # where the next number goes
    li      s1, COUNT               # how many are left
    li      t0, 0                   # fib(n)
    li      t1, 1                   # fib(n+1)

fill:
    sw      t0, 0(s0)
    add     t2, t0, t1              # fib(n+2)
    mv      t0, t1
    mv      t1, t2
    addi    s0, s0, 4
    addi    s1, s1, -1
    bnez    s1, fill

    # Sum the array from its last entry back to its first
    la      s2, table
    li      a0, 0                   # the sum
sum:
    addi    s0, s0, -4
    lw      t3, 0(s0)
    add     a0, a0, t3
    bne     s0, s2, sum

    # The sum of fib(0) to fib(23) is fib(25) - 1 = 75024, and t0 is now fib(24) =
    # 46368. Leave both in memory, the sum also as a half word and a byte.
    la      s3, result
    sw      a0, 0(s3)
    sw      t0, 4(s3)
    sh      a0, 8(s3)
    sb      a0, 10(s3)
    lhu     a1, 8(s3)
    lbu     a2, 10(s3)

    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)
1:  j       1b

    .section .bss
    .balign 4
table:
    .space  4 * COUNT
result:
    .space  12
