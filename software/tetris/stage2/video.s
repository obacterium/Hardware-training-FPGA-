.text
.globl fb_address
.globl fb_pack_pair
.globl fb_write_pair
.globl fb_write_cell
.globl fb_clear
.globl fb_hex_pair

# fb_address(row, col), with byte addresses increasing across the row.
fb_address:
    lui t0, 0xffff1
    slli t1, a0, 7
    slli t2, a0, 5
    add t0, t0, t1
    add t0, t0, t2
    slli a1, a1, 1
    add a0, t0, a1
    ret

# fb_pack_pair(left_cell, right_cell) packs two 16-bit cells for SW.
fb_pack_pair:
    slli a0, a0, 16
    srli a0, a0, 16
    slli a1, a1, 16
    or a0, a0, a1
    ret

# fb_write_pair(row, even_col, word) and fb_write_cell(row, col, halfword).
fb_write_pair:
    addi sp, sp, -16
    sw ra, 12(sp)
    jal ra, fb_address
    sw a2, 0(a0)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret
fb_write_cell:
    addi sp, sp, -16
    sw ra, 12(sp)
    jal ra, fb_address
    sh a2, 0(a0)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

fb_clear:
    lui t0, 0xffff1
    li t1, 32
    slli t2, t1, 16
    or t1, t1, t2
    li t2, 1200
fb_clear_word:
    sw t1, 0(t0)
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, fb_clear_word
    ret

# fb_hex_pair(byte) produces two white hexadecimal characters.
fb_hex_pair:
    srli t0, a0, 4
    andi t0, t0, 15
    andi t1, a0, 15
    li t2, 10
    bltu t0, t2, fb_hex_low
    addi t0, t0, 7
fb_hex_low:
    bltu t1, t2, fb_hex_ascii
    addi t1, t1, 7
fb_hex_ascii:
    addi t0, t0, 48
    addi t1, t1, 48
    li t2, 1
    slli t2, t2, 12
    or t0, t0, t2
    or t1, t1, t2
    slli t1, t1, 16
    or a0, t0, t1
    ret
