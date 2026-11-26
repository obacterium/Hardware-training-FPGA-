.include "layout.inc"
.data
.align 2
demo_state: .space GAME_BYTES
demo_sequence: .byte 0, 1, 2, 3, 4, 5, 6
input_line: .space 32
frame: .space 261           # 20 rows of 13 characters and a terminator
piece_chars: .ascii ".IOTSZJL"
command_keys:
    # a b c d e f g h i j k l m n o p q r s t u v w x y z
    .byte 1,0,0,2,0,0,0,5,0,0,0,0,0,0,0,6,8,7,4,0,0,0,3,0,0,0
intro: .asciz "Falling Blocks (RARS)\nA/D move  W rotate  S soft drop  H/Space hard drop\nP pause/resume  R restart  T/Enter advance 100 ms  Q quit\n"
border: .asciz "+----------+\n"
score_label: .asciz "Score="
line_label: .asciz "  Lines="
level_label: .asciz "  Level="
mode_label: .asciz "  "
playing: .asciz "PLAY\n"
paused: .asciz "PAUSED\n"
game_over: .asciz "GAME OVER\n"
prompt: .asciz "> "
unknown: .asciz "Unknown command. Use A/D/W/S/H/P/R/T/Q or Enter.\n"
goodbye: .asciz "Exited.\n"
.align 2
mode_names: .word playing, paused, game_over

.text
.globl main
main:
    andi sp, sp, -16
    la s0, demo_state
    li s1, 0
    mv a0, s0
    la a1, game_tables
    la a2, demo_sequence
    li a3, 7
    mv a4, s1
    jal ra, game_init
    la a0, intro
    li a7, 4
    ecall

demo_loop:
    jal ra, demo_draw
demo_read:
    la a0, prompt
    li a7, 4
    ecall
    la a0, input_line
    li a1, 32
    li a7, 8
    ecall
    la t0, input_line
    lbu t0, 0(t0)
    beqz t0, demo_quit
    li t1, 32
    beq t0, t1, demo_hard
    li t1, 10
    beq t0, t1, demo_tick
    ori t0, t0, 32
    li t1, 116             # 't'
    beq t0, t1, demo_tick
    addi t0, t0, -97       # 'a'
    li t1, 26
    bgeu t0, t1, demo_invalid
    la t1, command_keys
    add t1, t1, t0
    lbu a1, 0(t1)
    bnez a1, demo_step
demo_invalid:
    la a0, unknown
    li a7, 4
    ecall
    j demo_read
demo_tick:
    addi s1, s1, 100
    li a1, KEY_NONE
    j demo_step
demo_hard:
    li a1, KEY_HARD
    j demo_step
demo_quit:
    li a1, KEY_EXIT
demo_step:
    mv a0, s0
    mv a2, s1
    jal ra, game_step
    lw t0, G_MODE(s0)
    li t1, MODE_EXIT
    bne t0, t1, demo_loop
    la a0, goodbye
    li a7, 4
    ecall
    li a0, 0
    li a7, 93
    ecall

# Render settled pieces in uppercase and overlay the active piece in lowercase.
demo_draw:
    addi sp, sp, -16
    sw ra, 12(sp)
    la t0, frame
    la t1, piece_chars
    li t2, BOARD_HEIGHT
    mv t3, s0
    li t5, 124             # '|'
    li t6, 10              # newline
demo_draw_row:
    sb t5, 0(t0)
    addi t0, t0, 1
    li t4, BOARD_WIDTH
demo_draw_cell:
    lbu a0, 0(t3)
    add a0, t1, a0
    lbu a0, 0(a0)
    sb a0, 0(t0)
    addi t3, t3, 1
    addi t0, t0, 1
    addi t4, t4, -1
    bnez t4, demo_draw_cell
    sb t5, 0(t0)
    sb t6, 1(t0)
    addi t0, t0, 2
    addi t2, t2, -1
    bnez t2, demo_draw_row
    sb zero, 0(t0)

    lw a1, G_PIECE(s0)
    bltz a1, demo_print_frame
    mv a0, s0
    lw a2, G_ROTATION(s0)
    jal ra, game_cells
    lw t0, G_PIECE(s0)
    la t1, piece_chars
    add t0, t1, t0
    lbu t0, 1(t0)
    ori t0, t0, 32
    lw t2, G_X(s0)
    lw t3, G_Y(s0)
    la t4, frame
    li t5, 4
demo_overlay_cell:
    andi a1, a0, 15
    add a1, a1, t2
    srli a2, a0, 4
    andi a2, a2, 15
    add a2, a2, t3
    slli t6, a2, 3
    slli a3, a2, 2
    add t6, t6, a3
    add t6, t6, a2
    add t6, t6, a1
    add t6, t4, t6
    sb t0, 1(t6)
    srli a0, a0, 8
    addi t5, t5, -1
    bnez t5, demo_overlay_cell

demo_print_frame:
    li a7, 4
    la a0, border
    ecall
    la a0, frame
    ecall
    la a0, border
    ecall
    la a0, score_label
    ecall
    lw a0, G_SCORE(s0)
    li a7, 36
    ecall
    la a0, line_label
    li a7, 4
    ecall
    lw a0, G_LINES(s0)
    li a7, 36
    ecall
    la a0, level_label
    li a7, 4
    ecall
    lw a0, G_LEVEL(s0)
    li a7, 36
    ecall
    la a0, mode_label
    li a7, 4
    ecall
    lw t0, G_MODE(s0)
    slli t0, t0, 2
    la t1, mode_names
    add t1, t1, t0
    lw a0, 0(t1)
    ecall
    lw ra, 12(sp)
    addi sp, sp, 16
    ret
