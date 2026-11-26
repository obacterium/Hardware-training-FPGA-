.include "io.inc"
.include "../stage1/layout.inc"

.macro feed(%byte)
    mv a0, s0
    li a1, %byte
    jal ra, ps2_feed
.end_macro
.macro expect_key(%key)
    mv a0, s0
    jal ra, ps2_frame_key
    li t0, %key
    bne a0, t0, driver_fail
.end_macro
.macro check_state(%offset, %value)
    lw t0, %offset(s0)
    li t1, %value
    bne t0, t1, driver_fail
.end_macro
.macro check_address(%row,%col,%addr)
    li a0, %row
    li a1, %col
    jal ra, fb_address
    li t0, %addr
    bne a0, t0, driver_fail
.end_macro

.data
.align 2
key_state: .space K_BYTES
case_1: .asciz "PS/2 split prefixes and break filtering"
case_2: .asciz "PS/2 last direction and control queue"
case_3: .asciz "PS/2 repeat, wrap and overflow recovery"
case_4: .asciz "VGA address, halfword ordering and hex rendering"
ok: .asciz "PASS: "
bad: .asciz "FAIL: "
test_pass: .asciz "PASS: all stage2 driver tests\n"

.text
.globl main
main:
    andi sp, sp, -16
    la s0, key_state
    la s2, case_1
    mv a0, s0
    jal ra, ps2_init
    feed(0xe0)
    expect_key(KEY_NONE)
    check_state(K_PREFIX, 1)
    feed(0x6b)
    expect_key(KEY_LEFT)
    feed(0xe0)
    feed(0xf0)
    expect_key(KEY_NONE)
    check_state(K_PREFIX, 3)
    feed(0x6b)
    feed(0x6b)
    expect_key(KEY_NONE)
    check_state(K_PREFIX, 0)
    jal ra, driver_case_pass

    la s2, case_2
    feed(0xe0)
    feed(0x75)
    feed(0xe0)
    feed(0x74)
    expect_key(KEY_RIGHT)
    feed(0x29)
    feed(0xe0)
    feed(0x72)
    feed(0x4d)
    feed(0x2d)
    feed(0x76)
    expect_key(KEY_HARD)
    expect_key(KEY_PAUSE)
    expect_key(KEY_RESTART)
    expect_key(KEY_EXIT)
    expect_key(KEY_NONE)
    jal ra, driver_case_pass

    la s2, case_3
    feed(0x4d)
    expect_key(KEY_NONE)
    feed(0xf0)
    feed(0x4d)
    feed(0x4d)
    expect_key(KEY_PAUSE)
    mv a0, s0
    jal ra, ps2_init
    li s1, 32
driver_queue_fill:
    feed(0xe0)
    feed(0x6b)
    addi s1, s1, -1
    bnez s1, driver_queue_fill
    check_state(K_SW_DROPS, 1)
    expect_key(KEY_LEFT)
    check_state(K_TAIL, 31)
    feed(0xe0)
    feed(0x74)
    expect_key(KEY_RIGHT)
    check_state(K_TAIL, 0)
    feed(0xe0)
    mv a0, s0
    jal ra, ps2_overflow
    check_state(K_PREFIX, 0)
    check_state(K_HELD, 0)
    check_state(K_RESYNC, 1)
    check_state(K_HW_OVF, 1)
    expect_key(KEY_NONE)
    jal ra, driver_case_pass

    la s2, case_4
    check_address(0,0,0xffff1000)
    check_address(0,79,0xffff109e)
    check_address(1,0,0xffff10a0)
    check_address(29,79,0xffff22be)
    li a0, 0x1041
    li a1, 0x40db
    jal ra, fb_pack_pair
    li t0, 0x40db1041
    bne a0, t0, driver_fail
    li a0, 0xe0
    jal ra, fb_hex_pair
    li t0, 0x10301045
    bne a0, t0, driver_fail
    jal ra, driver_case_pass

    la a0, test_pass
    li a7, 4
    ecall
    li a0, 0
    li a7, 93
    ecall

driver_case_pass:
    la a0, ok
    li a7, 4
    ecall
    mv a0, s2
    ecall
    li a0, 10
    li a7, 11
    ecall
    ret
driver_fail:
    la a0, bad
    li a7, 4
    ecall
    mv a0, s2
    ecall
    li a0, 10
    li a7, 11
    ecall
    li a0, 1
    li a7, 93
    ecall
