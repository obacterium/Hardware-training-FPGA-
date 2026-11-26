.include "io.inc"
.text
.globl _start
_start:
    boot_stack
    jal ra, mmio_sys_ok
    beqz a0, mmio_fault
    jal ra, fb_clear

    lui a0, 0x1
    lui a1, 0x4
    nop
    addi a0, a0, 0x41     # white A
    addi a1, a1, 0x42     # yellow B
    jal ra, fb_pack_pair
    mv a2, a0
    li a0, 0
    li a1, 0
    jal ra, fb_write_pair
    lui a2, 0x4
    li a0, 0
    li a1, 1
    addi a2, a2, 0x43     # overwrite neighbor with yellow C
    jal ra, fb_write_cell

    lui a2, 0x2
    li a0, 0
    li a1, 79
    addi a2, a2, 0xdb
    jal ra, fb_write_cell
    lui a2, 0x5
    li a0, 1
    li a1, 0
    addi a2, a2, 0xdb
    jal ra, fb_write_cell
    lui a2, 0x8
    li a0, 29
    li a1, 79
    addi a2, a2, 0x5a     # last cell shows purple Z
    jal ra, fb_write_cell
    mmio_base(t0)
    li t1, 0x202
    sw t1, REG_LED(t0)
vga_diag_hold:
    j vga_diag_hold
