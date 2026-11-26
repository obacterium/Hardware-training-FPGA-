.include "io.inc"
.text
.globl _start
_start:
    boot_stack
    jal ra, mmio_sys_ok
    beqz a0, mmio_fault
    jal ra, fb_clear
    li s0, RAM_KEYS
    mv a0, s0
    jal ra, ps2_init
    li s1, 0               # column, two characters per byte
    mmio_base(t0)
    li t1, 0x203
    sw t1, REG_LED(t0)

key_diag_loop:
    mv a0, s0
    li a1, 1
    jal ra, mmio_poll_keys
    beqz a0, key_diag_loop
    lw a0, K_RAW(s0)
    jal ra, fb_hex_pair
    mv a2, a0
    li a0, 1
    mv a1, s1
    jal ra, fb_write_pair
    mv a0, s0
    jal ra, ps2_frame_key
    beqz a0, key_diag_blank
    jal ra, fb_hex_pair
    mv a2, a0
    j key_diag_show
key_diag_blank:
    li a2, 32
    slli t0, a2, 16
    or a2, a2, t0
key_diag_show:
    li a0, 2
    mv a1, s1
    jal ra, fb_write_pair
    addi s1, s1, 2
    li t0, 80
    bltu s1, t0, key_diag_loop
    li s1, 0
    j key_diag_loop
