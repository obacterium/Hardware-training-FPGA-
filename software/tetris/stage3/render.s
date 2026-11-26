.include "../stage1/layout.inc"
.include "firmware.inc"
.text
.globl render_init
.globl render_frame

render_init:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    sw s1, 4(sp)
    jal ra, fb_clear
    jal ra, render_border

    li a0, 1
    li a1, GAME_COL
    li a2, RAM_TITLE
    jal ra, render_label
    li s0, 0
render_static_hud:
    slli a0, s0, 1
    add a0, a0, s0
    addi a0, a0, 5
    li a1, 32
    slli a2, s0, 4
    addi a2, a2, RAM_LABEL_SCORE
    jal ra, render_label
    addi s0, s0, 1
    li t0, 3
    bltu s0, t0, render_static_hud
    li s0, 17
    li s1, RAM_LABEL_CONTROLS
render_help:
    mv a0, s0
    li a1, 32
    mv a2, s1
    jal ra, render_label
    addi s0, s0, 1
    addi s1, s1, 16
    li t0, 24
    bltu s0, t0, render_help

    li t0, RAM_RENDER_CACHE
    addi t1, t0, BOARD_BYTES
    li t2, -1
render_forget_cells:
    sw t2, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, render_forget_cells
    li t0, RAM_HUD_CACHE
    sw t2, 0(t0)
    sw t2, 4(t0)
    sw t2, 8(t0)
    sw t2, 12(t0)

    lw s1, 4(sp)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

render_border:
    addi sp, sp, -16
    sw ra, 12(sp)
    li a0, BORDER_ROW
    li a1, BORDER_COL
    jal ra, fb_address
    li t0, 21
    li t1, 160
    mul t0, t0, t1
    add t1, a0, t0
    li t2, 1
    slli t2, t2, 12
    addi t3, t2, 43        # '+'
    addi t4, t2, 45        # '-'
    sh t3, 0(a0)
    sh t3, 0(t1)
    mv t5, a0
    li t6, 20
render_border_horizontal:
    addi a0, a0, 2
    addi t1, t1, 2
    sh t4, 0(a0)
    sh t4, 0(t1)
    addi t6, t6, -1
    bnez t6, render_border_horizontal
    sh t3, 2(a0)
    sh t3, 2(t1)
    addi t4, t2, 124       # '|'
    li t6, BOARD_HEIGHT
render_border_vertical:
    addi t5, t5, 160
    sh t4, 0(t5)
    sh t4, 42(t5)
    addi t6, t6, -1
    bnez t6, render_border_vertical
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

# render_label(row, even_col, address_of_16_ascii_bytes)
render_label:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw a2, 0(sp)
    jal ra, fb_address
    lw a2, 0(sp)
    li t0, 8
    li t1, 1
    slli t1, t1, 12
render_label_pair:
    lbu t2, 0(a2)
    lbu t3, 1(a2)
    or t2, t2, t1
    or t3, t3, t1
    slli t3, t3, 16
    or t2, t2, t3
    sw t2, 0(a0)
    addi a0, a0, 4
    addi a2, a2, 2
    addi t0, t0, -1
    bnez t0, render_label_pair
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

# render_number(row, even_col, unsigned_32_bit_value)
render_number:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw a2, 0(sp)
    jal ra, fb_address
    lw a2, 0(sp)
    addi a0, a0, 16
    li t0, 5
    li t1, 10
    li t2, 1
    slli t2, t2, 12
    addi t2, t2, 48
render_digit_pair:
    divu t3, a2, t1
    mul t4, t3, t1
    sub t4, a2, t4
    add t4, t4, t2
    slli t4, t4, 16
    divu a2, t3, t1
    mul t5, a2, t1
    sub t5, t3, t5
    add t5, t5, t2
    or t4, t4, t5
    sw t4, 0(a0)
    addi a0, a0, -4
    addi t0, t0, -1
    bnez t0, render_digit_pair
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

# Compose settled and active tiles in RAM. Only dirty pairs reach MMIO.
render_frame:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    mv s0, a0
    li s1, RAM_DRAW_BUFFER
    mv t0, s0
    mv t1, s1
    addi t2, s0, BOARD_BYTES
render_copy_board:
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    bltu t0, t2, render_copy_board
    lw a1, G_PIECE(s0)
    bltz a1, render_compare
    lw a2, G_ROTATION(s0)
    mv a0, s0
    jal ra, game_cells
    lw t0, G_PIECE(s0)
    addi t0, t0, 1
    lw t1, G_X(s0)
    lw t2, G_Y(s0)
    li t3, 4
render_overlay_tile:
    andi t4, a0, 15
    srli t5, a0, 4
    andi t5, t5, 15
    add t4, t4, t1
    add t5, t5, t2
    slli t6, t5, 3
    slli t5, t5, 1
    add t6, t6, t5
    add t6, t6, t4
    add t6, s1, t6
    sb t0, 0(t6)
    srli a0, a0, 8
    addi t3, t3, -1
    bnez t3, render_overlay_tile

render_compare:
    li a0, GAME_ROW
    li a1, GAME_COL
    jal ra, fb_address
    li s2, RAM_RENDER_CACHE
    li t0, BOARD_HEIGHT
render_tile_row:
    li t1, BOARD_WIDTH
render_compare_tile:
    lbu t2, 0(s1)
    lbu t3, 0(s2)
    beq t2, t3, render_next_tile
    sb t2, 0(s2)
    li t4, 32
    beqz t2, render_write_tile
    lbu t4, RAM_COLORS(t2)
    slli t4, t4, 12
    ori t4, t4, 0xdb
render_write_tile:
    slli t5, t4, 16
    or t4, t4, t5
    sw t4, 0(a0)
render_next_tile:
    addi s1, s1, 1
    addi s2, s2, 1
    addi a0, a0, 4
    addi t1, t1, -1
    bnez t1, render_compare_tile
    addi a0, a0, 120
    addi t0, t0, -1
    bnez t0, render_tile_row

    li s1, 0
render_hud_field:
    slli t0, s1, 2
    add t1, t0, s0
    lw a2, G_MODE(t1)
    lw t1, RAM_HUD_CACHE(t0)
    beq a2, t1, render_hud_next
    sw a2, RAM_HUD_CACHE(t0)
    li a1, 32
    bnez s1, render_hud_number
    li a0, 14
    slli a2, a2, 4
    addi a2, a2, RAM_LABEL_PLAY
    jal ra, render_label
    j render_hud_next
render_hud_number:
    slli a0, s1, 1
    add a0, a0, s1
    addi a0, a0, 3
    jal ra, render_number
render_hud_next:
    addi s1, s1, 1
    li t0, 4
    bltu s1, t0, render_hud_field
    lw s2, 16(sp)
    lw s1, 20(sp)
    lw s0, 24(sp)
    lw ra, 28(sp)
    addi sp, sp, 32
    ret
