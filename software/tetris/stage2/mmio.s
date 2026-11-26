.include "io.inc"
.text
.globl mmio_sys_ok
.globl mmio_poll_keys
.globl mmio_random_piece
.globl mmio_fault

mmio_sys_ok:
    lui t0, 0xffff0
    lui t2, 0x43505
    nop
    lw t1, REG_SYS_ID(t0)
    addi t2, t2, 0x556
    xor a0, t1, t2
    seqz a0, a0
    ret

# mmio_poll_keys(state, max_bytes) returns bytes consumed this call.
mmio_poll_keys:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    mv s0, a0
    mv s1, a1
    li s2, 0
    mmio_base(s3)
mmio_poll_next:
    beq s1, s2, mmio_poll_return
    lw t0, REG_KEY_STATUS(s3)
    andi t1, t0, KEY_STATUS_OVERFLOW
    beqz t1, mmio_after_overflow
    sw t0, 0(sp)
    mv a0, s0
    jal ra, ps2_overflow
    lw t0, 0(sp)
mmio_after_overflow:
    andi t0, t0, KEY_STATUS_EMPTY
    bnez t0, mmio_fifo_empty
    lw a1, REG_KEY_DATA(s3)
    lw t0, K_RESYNC(s0)
    andi a1, a1, 255
    sw a1, K_RAW(s0)
    addi s2, s2, 1
    bnez t0, mmio_poll_next
    mv a0, s0
    jal ra, ps2_feed
    j mmio_poll_next
mmio_fifo_empty:
    sw zero, K_RESYNC(s0)
mmio_poll_return:
    mv a0, s2
    lw s3, 12(sp)
    lw s2, 16(sp)
    lw s1, 20(sp)
    lw s0, 24(sp)
    lw ra, 28(sp)
    addi sp, sp, 32
    ret

# Use DIVU/MUL/SUB so an immediate consumer uses the ordinary ALU bypass.
mmio_random_piece:
    mmio_base(t0)
    lw t1, REG_RNG(t0)
    li t2, 7
    divu t3, t1, t2
    mul t3, t3, t2
    sub a0, t1, t3
    ret

mmio_fault:
    mmio_base(t0)
    li t1, 14
    slli t1, t1, 12
    ori t1, t1, 1
    sw t1, REG_LED(t0)
mmio_fault_hold:
    j mmio_fault_hold
