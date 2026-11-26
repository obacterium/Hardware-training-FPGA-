.include "../stage1/layout.inc"
.include "../stage2/io.inc"
.include "firmware.inc"
.text
.globl _start
_start:
    boot_stack
    jal ra, mmio_sys_ok
    beqz a0, mmio_fault
    jal ra, fw_init_data
    li s0, RAM_GAME
    li s1, RAM_KEYS
    mmio_base(s2)
    mv a0, s1
    jal ra, ps2_init
    mv a0, s0
    li a1, RAM_TABLES
    lw a3, REG_TICK_MS(s2)
    # The link address points to the piece source selected by the build.
    jal a2, firmware_boot_game
    j firmware_next_piece
firmware_boot_game:
    jal ra, game_init_source
    jal ra, render_init
    mv a0, s0
    jal ra, render_frame
    li t0, 6
    slli t0, t0, 12
    ori t0, t0, 13
    sw t0, REG_LED(s2)
    lw s3, REG_TICK_MS(s2)
    li s4, 0               # phase of the 16, 17, 17 ms schedule

firmware_wait:
    lw s5, REG_TICK_MS(s2)
    sub t0, s5, s3
    snez t1, s4
    addi t1, t1, 16
    bltu t0, t1, firmware_wait
    mv s3, s5
    addi s4, s4, 1
    li t0, 3
    bltu s4, t0, firmware_update
    li s4, 0
firmware_update:
    mv a0, s1
    li a1, 32
    jal ra, mmio_poll_keys
    mv a0, s1
    jal ra, ps2_frame_key
    mv s6, a0
    mv a1, a0
    mv a0, s0
    mv a2, s5
    jal ra, game_step
    li t0, KEY_RESTART
    bne s6, t0, firmware_render
    jal ra, render_init
firmware_render:
    mv a0, s0
    jal ra, render_frame
    lw t0, G_MODE(s0)
    li t1, MODE_EXIT
    bne t0, t1, firmware_wait
firmware_exited:
    j firmware_exited
