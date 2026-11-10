# Start-up code linked in front of every test program (see tests/link.ld).
#
# It sets the stack pointer to the top of the RAM and then falls into the test: there
# is no jump, the test's .text is simply placed right after this code. So a test
# starts with its first instruction in .text and needs no entry label.
#
# It also owns tohost and fromhost, so a test only has to store to tohost to finish:
#
#       li   t0, 1
#       la   t1, tohost
#       sw   t0, 0(t1)          # 1 means "test passed"
#   1:  j    1b

    .section .text.init, "ax"
    .globl _start
_start:
    la      sp, _stack_top

    # Each is 8 bytes, as Spike's host interface expects. A test writes the low word.
    .section .tohost, "aw", @progbits
    .balign 64
    .globl tohost
tohost:
    .dword  0
    .balign 64
    .globl fromhost
fromhost:
    .dword  0
