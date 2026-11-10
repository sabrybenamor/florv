    .option norvc           # 32-bit encodings only, no compressed instructions

    .section .text
    .globl _start
_start:
back:
    # Upper immediate and jumps
    lui   x5, 0x12345
    auipc x17, 0xABCDE
    jal   x1, ahead
    jalr  x9, 291(x20)

    # Branches
    beq   x6, x21, back
    bne   x22, x7, ahead
    blt   x8, x23, back
    bge   x24, x10, ahead
    bltu  x11, x25, back
    bgeu  x26, x12, ahead

    # Loads
    lb    x13, -291(x27)
    lh    x28, 1110(x14)
    lw    x15, -1110(x29)
    lbu   x30, 77(x16)
    lhu   x17, -77(x31)

    # Stores
    sb    x18, 291(x3)
    sh    x4, -291(x19)
    sw    x20, 1110(x5)

    # Register-immediate
    addi  x6, x21, -1234
    slti  x22, x7, 1234
    sltiu x8, x23, -567
    xori  x24, x9, 567
    ori   x10, x25, -89
    andi  x26, x11, 89
    slli  x12, x27, 19
    srli  x28, x13, 13
    srai  x14, x29, 27

    # Register-register
    add   x30, x15, x16
    sub   x17, x31, x2
    sll   x3, x18, x19
    slt   x20, x4, x5
    sltu  x6, x21, x22
    xor   x23, x7, x8
    srl   x9, x24, x25
    sra   x26, x10, x11
    or    x12, x27, x28
    and   x29, x13, x14

ahead:
    jal   x0, back          # a backward jump, so JAL is seen with both signs
