.include "io.inc"
.text
.globl _start
_start:
    boot_stack
    jal ra, mmio_sys_ok
    beqz a0, mmio_fault
    mmio_base(s0)
    lui s1, 0x12345
    nop
    nop
    addi s1, s1, 0x678
mmio_diag_loop:
    lw t0, REG_SW_BTN(s0)
    sw t0, REG_LED(s0)
    srli t0, t0, 14
    andi t0, t0, 1
    lw t1, REG_TICK_MS(s0)
    bnez t0, mmio_diag_show
    mv t1, s1
mmio_diag_show:
    sw t1, REG_SEG7(s0)
    j mmio_diag_loop
