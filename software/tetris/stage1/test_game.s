.include "layout.inc"

.macro begin_game(%sequence, %count, %time)
    mv a0, s0
    la a1, game_tables
    la a2, %sequence
    li a3, %count
    li a4, %time
    jal ra, game_init
.end_macro

.macro step(%key, %time)
    mv a0, s0
    li a1, %key
    li a2, %time
    jal ra, game_step
.end_macro

.macro repeat_step(%key, %count)
    li s4, %count
repeat_loop:
    step(%key, 0)
    addi s4, s4, -1
    bnez s4, repeat_loop
.end_macro

.macro check_word(%field, %value)
    lw a1, %field(s0)
    li a2, %value
    li a3, %field
    jal ra, assert_equal
.end_macro

.macro check_cell(%cell, %value)
    lbu a1, %cell(s0)
    li a2, %value
    li a3, %cell
    jal ra, assert_equal
.end_macro

.macro check_bottom_rows(%mask)
    li a0, 180
    li a2, %mask
    jal ra, check_row_mask
    li a0, 190
    li a2, %mask
    jal ra, check_row_mask
.end_macro

.data
.align 2
test_state: .space GAME_BYTES
all_pieces: .byte 0, 1, 2, 3, 4, 5, 6
only_o: .byte 1
only_i: .byte 0
only_t: .byte 2
case_pieces: .asciz "seven pieces and all four orientations"
case_walls: .asciz "walls, stacks and rejected rotations"
case_gravity: .asciz "gravity, soft drop and timer wrap"
case_lock: .asciz "floor lock, stacked lock and hard drop"
case_lines: .asciz "single to four lines and separated full rows"
case_score: .asciz "level changes, previous-level score and minimum interval"
case_pause: .asciz "pause, resume, restart and exit"
case_replay: .asciz "complete replay with a double clear and top-out"
passed: .asciz "PASS: "
failed: .asciz "FAIL: "
location: .asciz " at offset "
expected: .asciz " expected "
actual: .asciz " actual "
final_pass: .asciz "PASS: all stage1 game tests\n"

.text
.globl main
main:
    andi sp, sp, -16
    la s0, test_state

    la s3, case_pieces
    begin_game(all_pieces, 7, 0)
    li s1, 0
check_next_piece:
    lw a1, G_PIECE(s0)
    mv a2, s1
    li a3, G_PIECE
    jal ra, assert_equal
    li s2, 1
check_next_orientation:
    step(KEY_ROTATE, 0)
    lw a1, G_ROTATION(s0)
    andi a2, s2, 3
    li a3, G_ROTATION
    jal ra, assert_equal
    addi s2, s2, 1
    li t0, 5
    blt s2, t0, check_next_orientation
    step(KEY_HARD, 0)
    check_word(G_MODE, MODE_PLAY)
    addi s1, s1, 1
    li t0, 7
    blt s1, t0, check_next_piece
    check_word(G_PIECE, 0)
    jal ra, print_pass

    la s3, case_walls
    begin_game(only_o, 1, 0)
    repeat_step(KEY_LEFT, 5)
    check_word(G_X, -1)
    repeat_step(KEY_RIGHT, 9)
    check_word(G_X, 7)
    li t0, 3
    sb t0, 7(s0)
    step(KEY_LEFT, 0)
    check_word(G_X, 7)

    begin_game(only_i, 1, 0)
    step(KEY_ROTATE, 0)
    check_word(G_ROTATION, 1)
    repeat_step(KEY_LEFT, 6)
    check_word(G_X, -2)
    step(KEY_ROTATE, 0)
    check_word(G_ROTATION, 1)
    check_word(G_X, -2)

    begin_game(only_t, 1, 0)
    li t0, 3
    sb t0, 24(s0)
    step(KEY_ROTATE, 0)
    check_word(G_ROTATION, 0)
    sb zero, 24(s0)
    step(KEY_ROTATE, 0)
    check_word(G_ROTATION, 1)
    jal ra, print_pass

    la s3, case_gravity
    begin_game(only_o, 1, 0)
    step(KEY_NONE, 799)
    check_word(G_Y, 0)
    step(KEY_NONE, 800)
    check_word(G_Y, 1)
    step(KEY_SOFT, 1600)
    check_word(G_Y, 2)
    step(KEY_NONE, 2399)
    check_word(G_Y, 2)
    step(KEY_NONE, 2400)
    check_word(G_Y, 3)
    begin_game(only_o, 1, 0xffffff00)
    step(KEY_NONE, 0x21f)
    check_word(G_Y, 0)
    step(KEY_NONE, 0x220)
    check_word(G_Y, 1)
    jal ra, print_pass

    la s3, case_lock
    begin_game(only_o, 1, 0)
    repeat_step(KEY_SOFT, 18)
    check_word(G_Y, 18)
    check_cell(194, 0)
    step(KEY_NONE, 800)
    check_word(G_Y, 0)
    check_bottom_rows(0x030)
    step(KEY_HARD, 801)
    check_word(G_Y, 0)
    check_word(G_LAST_DROP, 801)
    check_cell(164, 2)
    check_cell(165, 2)
    check_cell(174, 2)
    check_cell(175, 2)
    check_cell(154, 0)
    jal ra, print_pass

    la s3, case_lines
    li s1, 1
test_next_line_count:
    begin_game(only_i, 1, 0)
    mv a0, s1
    jal ra, fill_gap_rows
    step(KEY_ROTATE, 0)
    step(KEY_HARD, 0)
    lw a1, G_LINES(s0)
    mv a2, s1
    li a3, G_LINES
    jal ra, assert_equal
    la t0, line_scores
    slli t1, s1, 2
    add t0, t0, t1
    lw a2, 0(t0)
    lw a1, G_SCORE(s0)
    li a3, G_SCORE
    jal ra, assert_equal
    check_cell(0, 0)
    check_cell(190, 7)
    li t0, 4
    sltu a2, s1, t0
    lbu a1, 195(s0)
    li a3, 195
    jal ra, assert_equal
    addi s1, s1, 1
    li t0, 5
    blt s1, t0, test_next_line_count

    begin_game(only_i, 1, 0)
    li a0, 4
    jal ra, fill_gap_rows
    sw zero, 172(s0)
    sw zero, 176(s0)
    sh zero, 170(s0)
    step(KEY_ROTATE, 0)
    step(KEY_HARD, 0)
    check_word(G_LINES, 3)
    check_word(G_SCORE, 500)
    check_cell(180, 7)
    check_cell(190, 0)
    check_cell(195, 1)
    jal ra, print_pass

    la s3, case_score
    begin_game(only_i, 1, 0)
    li t0, 9
    sw t0, G_LINES(s0)
    li t0, 50
    sw t0, G_SCORE(s0)
    li a0, 2
    jal ra, fill_gap_rows
    step(KEY_ROTATE, 0)
    step(KEY_HARD, 0)
    check_word(G_LINES, 11)
    check_word(G_SCORE, 350)
    check_word(G_LEVEL, 2)
    check_word(G_DROP_MS, 740)
    begin_game(only_i, 1, 0)
    li t0, 129
    sw t0, G_LINES(s0)
    li t0, 13
    sw t0, G_LEVEL(s0)
    li a0, 1
    jal ra, fill_gap_rows
    step(KEY_ROTATE, 0)
    step(KEY_HARD, 0)
    check_word(G_LINES, 130)
    check_word(G_SCORE, 1300)
    check_word(G_LEVEL, 14)
    check_word(G_DROP_MS, 80)
    jal ra, print_pass

    la s3, case_pause
    begin_game(only_o, 1, 0)
    step(KEY_PAUSE, 700)
    check_word(G_MODE, MODE_PAUSED)
    step(KEY_LEFT, 1000)
    step(KEY_HARD, 2000)
    step(KEY_NONE, 2500)
    check_word(G_Y, 0)
    check_word(G_X, 3)
    check_bottom_rows(0)
    step(KEY_PAUSE, 3000)
    check_word(G_MODE, MODE_PLAY)
    step(KEY_NONE, 3799)
    check_word(G_Y, 0)
    step(KEY_NONE, 3800)
    check_word(G_Y, 1)
    step(KEY_PAUSE, 3800)
    step(KEY_RESTART, 4000)
    check_word(G_MODE, MODE_PLAY)
    check_word(G_LAST_DROP, 4000)
    check_word(G_Y, 0)
    step(KEY_EXIT, 4000)
    step(KEY_RESTART, 4001)
    check_word(G_MODE, MODE_EXIT)
    jal ra, print_pass

    la s3, case_replay
    begin_game(only_o, 1, 0)
    repeat_step(KEY_LEFT, 4)
    step(KEY_HARD, 0)
    check_bottom_rows(0x003)
    check_word(G_LINES, 0)
    check_word(G_SCORE, 0)
    repeat_step(KEY_LEFT, 2)
    step(KEY_HARD, 0)
    check_bottom_rows(0x00f)
    check_word(G_LINES, 0)
    check_word(G_SCORE, 0)
    step(KEY_HARD, 0)
    check_bottom_rows(0x03f)
    check_word(G_LINES, 0)
    check_word(G_SCORE, 0)
    repeat_step(KEY_RIGHT, 2)
    step(KEY_HARD, 0)
    check_bottom_rows(0x0ff)
    check_word(G_LINES, 0)
    check_word(G_SCORE, 0)
    repeat_step(KEY_RIGHT, 4)
    step(KEY_HARD, 0)
    check_bottom_rows(0)
    check_word(G_LINES, 2)
    check_word(G_SCORE, 300)

    li s1, 18
test_next_stack:
    step(KEY_HARD, 0)
    jal ra, check_replay_stack
    check_word(G_LINES, 2)
    check_word(G_SCORE, 300)
    beqz s1, test_top_out
    check_word(G_MODE, MODE_PLAY)
    addi s1, s1, -2
    j test_next_stack
test_top_out:
    check_word(G_MODE, MODE_OVER)
    check_word(G_PIECE, -1)
    step(KEY_HARD, 800)
    step(KEY_PAUSE, 800)
    check_word(G_MODE, MODE_OVER)
    jal ra, check_replay_stack
    step(KEY_RESTART, 900)
    check_word(G_MODE, MODE_PLAY)
    check_word(G_PIECE, 1)
    check_word(G_SCORE, 0)
    check_word(G_LINES, 0)
    check_word(G_LEVEL, 1)
    check_word(G_DROP_MS, 800)
    check_word(G_LAST_DROP, 900)
    li s1, BOARD_HEIGHT
    jal ra, check_replay_stack
    jal ra, print_pass

    la a0, final_pass
    li a7, 4
    ecall
    li a0, 0
    li a7, 93
    ecall

# Set up rows with a gap at col 5, plus a marker on the surviving row above.
fill_gap_rows:
    li t0, LAST_ROW
    li t1, BOARD_WIDTH
    li t2, 5
    li t3, 2
fill_next_row:
    li t4, 0
    add t5, s0, t0
fill_next_cell:
    beq t4, t2, skip_gap
    sb t3, 0(t5)
skip_gap:
    addi t5, t5, 1
    addi t4, t4, 1
    blt t4, t1, fill_next_cell
    addi t0, t0, -BOARD_WIDTH
    addi a0, a0, -1
    bnez a0, fill_next_row
    add t0, s0, t0
    li t1, 7
    sb t1, 0(t0)
    ret

# Check the occupancy of a row given its byte offset and expected bit mask.
check_row_mask:
    mv a3, a0
    add t0, s0, a0
    li a1, 0
    li t1, 0
    li t2, BOARD_WIDTH
check_mask_cell:
    lbu t3, 0(t0)
    snez t3, t3
    sll t3, t3, t1
    or a1, a1, t3
    addi t0, t0, 1
    addi t1, t1, 1
    blt t1, t2, check_mask_cell
    j assert_equal

# Every settled row at or below s1 has O cells at cols 4 and 5 only.
check_replay_stack:
    li t0, 0
    li a3, 0
    li t4, BOARD_HEIGHT
    li t5, BOARD_WIDTH
check_stack_row:
    li t1, 0
check_stack_cell:
    li a2, 0
    blt t0, s1, check_stack_value
    addi t2, t1, -4
    li t3, 2
    bgeu t2, t3, check_stack_value
    li a2, 2
check_stack_value:
    add t2, s0, a3
    lbu a1, 0(t2)
    bne a1, a2, assert_equal
    addi a3, a3, 1
    addi t1, t1, 1
    blt t1, t5, check_stack_cell
    addi t0, t0, 1
    blt t0, t4, check_stack_row
    ret

assert_equal:
    beq a1, a2, assert_pass
    mv s1, a1
    mv s2, a2
    mv s4, a3
    li a7, 4
    la a0, failed
    ecall
    mv a0, s3
    ecall
    la a0, location
    ecall
    mv a0, s4
    li a7, 1
    ecall
    li a7, 4
    la a0, expected
    ecall
    mv a0, s2
    li a7, 1
    ecall
    li a7, 4
    la a0, actual
    ecall
    mv a0, s1
    li a7, 1
    ecall
    li a0, 10
    li a7, 11
    ecall
    li a0, 1
    li a7, 93
    ecall
assert_pass:
    ret

print_pass:
    li a7, 4
    la a0, passed
    ecall
    mv a0, s3
    ecall
    li a0, 10
    li a7, 11
    ecall
    ret

.data
.align 2
line_scores: .word 0, 100, 300, 500, 800
