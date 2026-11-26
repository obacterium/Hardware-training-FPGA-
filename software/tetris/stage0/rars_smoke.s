.data
.align 2
scratch: .space 8
pass_message: .asciz "PASS: stage0 RAM probe\n"
fail_message: .asciz "FAIL: stage0 RAM probe\n"

.text
.globl main
main:
    andi sp, sp, -16
    la a0, scratch
    jal ra, ram_probe
    bnez a0, smoke_fail

    la a0, pass_message
    li a7, 4
    ecall
    li a0, 0
    j smoke_exit

smoke_fail:
    la a0, fail_message
    li a7, 4
    ecall
    li a0, 1

smoke_exit:
    li a7, 93
    ecall
