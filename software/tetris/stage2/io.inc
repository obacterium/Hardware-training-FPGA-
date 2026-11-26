.eqv REG_SYS_ID 0x00
.eqv REG_SW_BTN 0x04
.eqv REG_LED 0x08
.eqv REG_SEG7 0x0c
.eqv REG_TICK_MS 0x10
.eqv REG_KEY_DATA 0x18
.eqv REG_KEY_STATUS 0x1c
.eqv REG_RNG 0x20
.eqv KEY_STATUS_EMPTY 1
.eqv KEY_STATUS_OVERFLOW 4

.eqv K_HEAD 0
.eqv K_TAIL 4
.eqv K_PREFIX 8
.eqv K_HELD 12
.eqv K_HW_OVF 16
.eqv K_SW_DROPS 20
.eqv K_RESYNC 24
.eqv K_RAW 28
.eqv K_RING 32
.eqv K_MASK 31
.eqv K_BYTES 64

.eqv RAM_GAME 0x000
.eqv RAM_KEYS 0x140
.eqv RAM_TABLES 0x180

# The baseline CPU supplies the real LUI value on the WB bypass.
.macro mmio_base(%reg)
    lui %reg, 0xffff0
    nop
    nop
.end_macro

.macro boot_stack
    lui sp, 0x8
    nop
    nop
    csrrci zero, fflags, 1 # Baseline CPU treats CSRRCI as clearing board IRQ enable.
.end_macro
