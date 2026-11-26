.text
.globl ram_probe

# a0 points to two writable, aligned words. Returns zero on success.
ram_probe:
    # Leave two independent instructions between each LUI and its consumer.
    # The current pipeline forwards the LUI value correctly from WB.
    lui t0, 0x1357a
    lui t1, 0x2468b
    addi sp, sp, -16
    sw zero, 4(a0)
    addi t0, t0, -1057      # 0x13579bdf
    addi t1, t1, -800       # 0x2468ace0
    sw t0, 0(a0)
    sw t1, 0(sp)

    lw t2, 0(a0)
    bne t2, t0, ram_probe_fail
    lw t2, 4(a0)
    bnez t2, ram_probe_fail
    lw t2, 0(sp)
    bne t2, t1, ram_probe_fail

    li a0, 0
    j ram_probe_return

ram_probe_fail:
    li a0, 1

ram_probe_return:
    addi sp, sp, 16
    ret
