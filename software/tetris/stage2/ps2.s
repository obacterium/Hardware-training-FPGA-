.include "io.inc"
.include "../stage1/layout.inc"
.text
.globl ps2_init
.globl ps2_overflow
.globl ps2_feed
.globl ps2_frame_key

ps2_init:
    sw zero, K_HEAD(a0)
    sw zero, K_TAIL(a0)
    sw zero, K_PREFIX(a0)
    sw zero, K_HELD(a0)
    sw zero, K_HW_OVF(a0)
    sw zero, K_SW_DROPS(a0)
    sw zero, K_RESYNC(a0)
    sw zero, K_RAW(a0)
    ret

# Stop interpreting the byte stream until the hardware FIFO is empty.
ps2_overflow:
    lw t0, K_HW_OVF(a0)
    addi t0, t0, 1
    sw t0, K_HW_OVF(a0)
    sw zero, K_HEAD(a0)
    sw zero, K_TAIL(a0)
    sw zero, K_PREFIX(a0)
    sw zero, K_HELD(a0)
    li t0, 1
    sw t0, K_RESYNC(a0)
    ret

# ps2_feed(state, raw_byte). The caller drains bytes in resync mode.
ps2_feed:
    lw t0, K_PREFIX(a0)
    li t1, 0xe0
    beq a1, t1, ps2_extended
    li t1, 0xf0
    beq a1, t1, ps2_break
    sw zero, K_PREFIX(a0)
    andi t1, t0, 1
    beqz t1, ps2_plain_code
    li t1, 0x6b
    li t2, KEY_LEFT
    beq a1, t1, ps2_direction
    li t1, 0x74
    li t2, KEY_RIGHT
    beq a1, t1, ps2_direction
    li t1, 0x75
    li t2, KEY_ROTATE
    beq a1, t1, ps2_direction
    li t1, 0x72
    li t2, KEY_SOFT
    bne a1, t1, ps2_return
ps2_direction:
    andi t0, t0, 2
    bnez t0, ps2_return
    li t3, 0
    j ps2_enqueue

ps2_plain_code:
    li t1, 0x29
    li t2, KEY_HARD
    beq a1, t1, ps2_control
    li t1, 0x4d
    li t2, KEY_PAUSE
    beq a1, t1, ps2_control
    li t1, 0x2d
    li t2, KEY_RESTART
    beq a1, t1, ps2_control
    li t1, 0x76
    li t2, KEY_EXIT
    bne a1, t1, ps2_return
ps2_control:
    li t3, 1
    sll t3, t3, t2
    lw t4, K_HELD(a0)
    andi t0, t0, 2
    bnez t0, ps2_release
    and t0, t4, t3
    bnez t0, ps2_return

ps2_enqueue:
    lw t0, K_HEAD(a0)
    lw t1, K_TAIL(a0)
    addi t5, t0, 1
    andi t5, t5, K_MASK
    beq t5, t1, ps2_drop_key
    add t0, a0, t0
    sb t2, K_RING(t0)
    sw t5, K_HEAD(a0)
    beqz t3, ps2_return
    or t4, t4, t3
    sw t4, K_HELD(a0)
ps2_return:
    ret
ps2_release:
    not t3, t3
    and t4, t4, t3
    sw t4, K_HELD(a0)
    ret
ps2_drop_key:
    lw t0, K_SW_DROPS(a0)
    addi t0, t0, 1
    sw t0, K_SW_DROPS(a0)
    ret
ps2_extended:
    ori t0, t0, 1
    sw t0, K_PREFIX(a0)
    ret
ps2_break:
    ori t0, t0, 2
    sw t0, K_PREFIX(a0)
    ret

# Keep the last direction for this frame. Control keys take priority and
# remain in FIFO order, with at most one returned per frame.
ps2_frame_key:
    lw t0, K_HEAD(a0)
    lw t1, K_TAIL(a0)
    mv t2, t1
    li a1, KEY_NONE
    li a2, KEY_NONE
    li t5, KEY_HARD
ps2_reduce_next:
    beq t1, t0, ps2_reduced
    add t3, a0, t1
    lbu t4, K_RING(t3)
    addi t1, t1, 1
    andi t1, t1, K_MASK
    bltu t4, t5, ps2_reduce_direction
    beqz a2, ps2_first_control
    add t3, a0, t2
    sb t4, K_RING(t3)
    addi t2, t2, 1
    andi t2, t2, K_MASK
    j ps2_reduce_next
ps2_reduce_direction:
    mv a1, t4
    j ps2_reduce_next
ps2_first_control:
    mv a2, t4
    j ps2_reduce_next
ps2_reduced:
    lw t1, K_TAIL(a0)
    bne t2, t1, ps2_save_queue
    # Advance both ring indices when no control events remain.
    mv t2, t0
    sw t2, K_TAIL(a0)
ps2_save_queue:
    sw t2, K_HEAD(a0)
    mv a0, a1
    beqz a2, ps2_frame_return
    mv a0, a2
ps2_frame_return:
    ret
