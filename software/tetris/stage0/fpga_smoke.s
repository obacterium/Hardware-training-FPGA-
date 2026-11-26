.text
.globl _start
_start:
    # SP starts one byte past RAM. The probe allocates before accessing it.
    lui sp, 0x8
    lui a0, 0x7
    jal ra, ram_probe

    lui t3, 0xffff0
    li t4, 0x101
    bnez a0, smoke_signal

    lui t1, 0x43505
    lw t0, 0(t3)             # SYS_ID
    li t4, 0x102
    addi t1, t1, 0x556      # Consume LUI after two independent instructions.
    bne t0, t1, smoke_signal
    li t4, 0x60
    slli t4, t4, 8
    addi t4, t4, 0x00d

smoke_signal:
    sw t4, 8(t3)             # LED

smoke_hold:
    j smoke_hold
