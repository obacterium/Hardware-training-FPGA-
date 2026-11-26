.include "layout.inc"
.text
.globl game_init
.globl game_step
.globl game_cells

# game_init(state, tables, sequence, sequence_length, now_ms)
# Supply a nonempty sequence of piece IDs 0..6. The sequence repeats.
game_init:
    sw a1, G_TABLES(a0)
    sw a2, G_SEQUENCE(a0)
    sw a3, G_SEQUENCE_LEN(a0)
    mv a1, a4
    j game_restart

# game_restart(state, now_ms)
game_restart:
    mv t0, a0
    addi t1, a0, BOARD_BYTES
game_clear_board:
    sw zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, game_clear_board
    sw zero, G_MODE(a0)
    sw zero, G_SCORE(a0)
    sw zero, G_LINES(a0)
    sw zero, G_SEQUENCE_INDEX(a0)
    li t0, 1
    sw t0, G_LEVEL(a0)
    li t0, 800
    sw t0, G_DROP_MS(a0)
    sw a1, G_LAST_DROP(a0)
    j game_spawn

# game_step(state, key, now_ms) handles one frame and at most one lock.
game_step:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    sw s1, 4(sp)
    mv s0, a0
    mv s1, a2
    lw t0, G_MODE(s0)
    li t1, MODE_EXIT
    beq t0, t1, game_step_return
    li t1, KEY_EXIT
    beq a1, t1, game_exit
    li t1, KEY_RESTART
    beq a1, t1, game_step_restart
    li t1, KEY_PAUSE
    beq a1, t1, game_pause
    bnez t0, game_step_return

    li t0, KEY_HARD
    beq a1, t0, game_hard_drop
    li t0, KEY_SOFT
    beq a1, t0, game_step_down
    li t0, KEY_LEFT
    beq a1, t0, game_step_left
    li t0, KEY_RIGHT
    beq a1, t0, game_step_right
    li t0, KEY_ROTATE
    bne a1, t0, game_step_gravity
    li a1, 0
    li a2, 0
    li a3, 1
    j game_step_move

game_step_left:
    li a1, -1
    j game_step_horizontal
game_step_right:
    li a1, 1
game_step_horizontal:
    li a2, 0
    li a3, 0
game_step_move:
    mv a0, s0
    jal ra, game_move
game_step_gravity:
    lw t0, G_LAST_DROP(s0)
    lw t1, G_DROP_MS(s0)
    sub t0, s1, t0
    bltu t0, t1, game_step_return
game_step_down:
    sw s1, G_LAST_DROP(s0)
    mv a0, s0
    li a1, 0
    li a2, 1
    li a3, 0
    jal ra, game_move
    bnez a0, game_step_return
    j game_step_lock

game_hard_drop:
    sw s1, G_LAST_DROP(s0)
game_hard_drop_next:
    mv a0, s0
    li a1, 0
    li a2, 1
    li a3, 0
    jal ra, game_move
    bnez a0, game_hard_drop_next
game_step_lock:
    mv a0, s0
    jal ra, game_lock
    j game_step_return

game_pause:
    li t1, MODE_PAUSED
    bltu t1, t0, game_step_return
    xori t0, t0, 1
    sw t0, G_MODE(s0)
    bnez t0, game_step_return
    sw s1, G_LAST_DROP(s0)
    j game_step_return
game_step_restart:
    mv a1, s1
    jal ra, game_restart
    j game_step_return
game_exit:
    li t0, MODE_EXIT
    sw t0, G_MODE(s0)
game_step_return:
    lw s1, 4(sp)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

# game_cells(state, piece, rotation) returns the four packed cell offsets.
game_cells:
    lw t0, G_TABLES(a0)
    slli t1, a1, 4
    slli t2, a2, 2
    add t0, t0, t1
    add t0, t0, t2
    lw a0, 0(t0)
    ret

# game_fits(state, cells, x, y) returns 1 if all four cells fit.
game_fits:
    li t0, 4
    li t5, BOARD_WIDTH
    li t6, BOARD_HEIGHT
game_fits_cell:
    andi t1, a1, 15
    add t1, t1, a2
    bgeu t1, t5, game_cell_blocked
    srli t2, a1, 4
    andi t2, t2, 15
    add t2, t2, a3
    bgeu t2, t6, game_cell_blocked
    slli t3, t2, 3
    slli t4, t2, 1
    add t3, t3, t4
    add t3, t3, t1
    add t3, a0, t3
    lbu t3, 0(t3)
    bnez t3, game_cell_blocked
    srli a1, a1, 8
    addi t0, t0, -1
    bnez t0, game_fits_cell
    li a0, 1
    ret
game_cell_blocked:
    li a0, 0
    ret

# game_move(state, dx, dy, rotation_delta) commits a pose only if it fits.
game_move:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw a0, 0(sp)
    lw t0, G_X(a0)
    add t0, t0, a1
    sw t0, 4(sp)
    lw t0, G_Y(a0)
    add t0, t0, a2
    sw t0, 8(sp)
    lw t0, G_ROTATION(a0)
    add t0, t0, a3
    andi a2, t0, 3
    sw a2, 12(sp)
    lw a1, G_PIECE(a0)
    jal ra, game_cells
    mv a1, a0
    lw a0, 0(sp)
    lw a2, 4(sp)
    lw a3, 8(sp)
    jal ra, game_fits
    beqz a0, game_move_return
    lw t0, 0(sp)
    lw t1, 4(sp)
    lw t2, 8(sp)
    lw t3, 12(sp)
    sw t1, G_X(t0)
    sw t2, G_Y(t0)
    sw t3, G_ROTATION(t0)
game_move_return:
    lw ra, 28(sp)
    addi sp, sp, 32
    ret

game_spawn:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw a0, 0(sp)
    lw t0, G_SEQUENCE_INDEX(a0)
    lw t1, G_SEQUENCE(a0)
    add t1, t1, t0
    lbu t2, 0(t1)
    sw t2, G_PIECE(a0)
    addi t0, t0, 1
    lw t1, G_SEQUENCE_LEN(a0)
    bltu t0, t1, game_spawn_set_index
    li t0, 0
game_spawn_set_index:
    sw t0, G_SEQUENCE_INDEX(a0)
    li t0, 3
    sw t0, G_X(a0)
    sw zero, G_Y(a0)
    sw zero, G_ROTATION(a0)
    li a1, 0
    li a2, 0
    li a3, 0
    jal ra, game_move
    bnez a0, game_spawn_return
    lw t0, 0(sp)
    li t1, MODE_OVER
    sw t1, G_MODE(t0)
    li t1, -1
    sw t1, G_PIECE(t0)
game_spawn_return:
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

# Stamp the current valid pose, compact rows, then spawn the next piece.
game_lock:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    mv s0, a0
    lw a1, G_PIECE(s0)
    lw a2, G_ROTATION(s0)
    jal ra, game_cells
    lw t0, G_PIECE(s0)
    addi t0, t0, 1
    lw t1, G_X(s0)
    lw t2, G_Y(s0)
    li t3, 4
game_stamp_cell:
    andi t4, a0, 15
    add t4, t4, t1
    srli t5, a0, 4
    andi t5, t5, 15
    add t5, t5, t2
    slli t6, t5, 3
    slli t5, t5, 1
    add t6, t6, t5
    add t6, t6, t4
    add t6, s0, t6
    sb t0, 0(t6)
    srli a0, a0, 8
    addi t3, t3, -1
    bnez t3, game_stamp_cell
    mv a0, s0
    jal ra, game_compact_rows
    beqz a0, game_lock_spawn
    mv a1, a0
    mv a0, s0
    jal ra, game_score_lines
game_lock_spawn:
    mv a0, s0
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    j game_spawn

# Walk bottom to top, copying each surviving row down once.
game_compact_rows:
    li t0, LAST_ROW          # read row offset
    li t1, LAST_ROW          # write row offset
    li t2, 0                # cleared rows
    li t6, BOARD_WIDTH
game_inspect_row:
    add t3, a0, t0
    li t4, 0
game_inspect_cell:
    add t5, t3, t4
    lbu t5, 0(t5)
    beqz t5, game_keep_row
    addi t4, t4, 1
    bltu t4, t6, game_inspect_cell
    addi t2, t2, 1
    j game_next_row
game_keep_row:
    beq t0, t1, game_kept_row
    add a1, a0, t1
    li t4, BOARD_WIDTH
game_copy_cell:
    lbu t5, 0(t3)
    sb t5, 0(a1)
    addi t3, t3, 1
    addi a1, a1, 1
    addi t4, t4, -1
    bnez t4, game_copy_cell
game_kept_row:
    addi t1, t1, -BOARD_WIDTH
game_next_row:
    addi t0, t0, -BOARD_WIDTH
    bgez t0, game_inspect_row
    addi t1, t1, 9
    bltz t1, game_compact_return
game_zero_cell:
    add t0, a0, t1
    sb zero, 0(t0)
    addi t1, t1, -1
    bgez t1, game_zero_cell
game_compact_return:
    mv a0, t2
    ret

# Score using the level before this lock, then update the next interval.
game_score_lines:
    lw t0, G_LINES(a0)
    add t0, t0, a1
    sw t0, G_LINES(a0)
    slli t1, a1, 1
    lw t2, G_TABLES(a0)
    add t2, t2, t1
    lhu t2, SCORE_TABLE_OFFSET(t2)
    lw t3, G_LEVEL(a0)
    mul t2, t2, t3
    lw t3, G_SCORE(a0)
    add t3, t3, t2
    sw t3, G_SCORE(a0)

    li t1, 10
    divu t0, t0, t1
    addi t1, t0, 1
    sw t1, G_LEVEL(a0)
    li t1, 12
    li t2, 80
    bgeu t0, t1, game_set_interval
    li t1, 60
    mul t0, t0, t1
    li t2, 800
    sub t2, t2, t0
game_set_interval:
    sw t2, G_DROP_MS(a0)
    ret
