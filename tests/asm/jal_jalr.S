# JAL and JALR: forward and backward jumps, calls and returns, an indirect call
# through a register, an offset in JALR, a target with bit 0 set (JALR clears it),
# and JALR with the same register as source and destination.

    .section .text
    li      a0, 0
    j       main                    # jal x0: a forward jump that saves nothing

# The functions sit before main, so calling them is a backward jump.
add_two:
    addi    a0, a0, 2
    ret                             # jalr x0, 0(ra)

add_four:
    addi    a0, a0, 4
    nop
    addi    a0, a0, 8               # entered here by "jalr ra, 8(t0)"
    jalr    zero, 0(ra)

main:
    jal     ra, add_two             # backward call
    jal     ra, add_two             # again: ra changes with the call site
    jal     t1, forward             # a call that links through t1, not ra
    addi    a0, a0, 16              # the return lands here

    la      t0, add_four
    jalr    ra, 0(t0)               # indirect call
    jalr    ra, 8(t0)               # indirect call with an offset: enters at +8

    addi    t2, t0, 1               # the address of add_four with bit 0 set
    jalr    ra, 0(t2)               # bit 0 is cleared: still enters add_four

    addi    t2, t0, 9               # +8, with bit 0 set
    jalr    ra, 0(t2)               # enters at +8

    la      t3, same_reg
    jalr    t3, 0(t3)               # jumps to the old t3, then t3 = return address
    addi    a0, a0, 100             # skipped
same_reg:
    addi    a0, a0, 32

    jal     zero, done              # forward, nothing saved
    addi    a0, a0, 100             # skipped

forward:
    addi    a0, a0, 64
    jalr    zero, 0(t1)             # return through t1

done:
    li      t0, 1
    la      t1, tohost
    sw      t0, 0(t1)
1:  j       1b
