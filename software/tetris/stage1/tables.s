.data
.align 2
.globl game_tables

# I O T S Z J L, with clockwise rotations 0 through 3 for each piece.
# One little-endian word per orientation; each byte encodes (row << 4) | col.
game_tables:
    .word 0x13121110, 0x32221202, 0x23222120, 0x31211101
    .word 0x12110201, 0x12110201, 0x12110201, 0x12110201
    .word 0x12111001, 0x21121101, 0x21121110, 0x21111001
    .word 0x11100201, 0x22121101, 0x21201211, 0x21111000
    .word 0x12110100, 0x21121102, 0x22211110, 0x20111001
    .word 0x12111000, 0x21110201, 0x22121110, 0x21201101
    .word 0x12111002, 0x22211101, 0x20121110, 0x21110100
    .half 0, 100, 300, 500, 800, 0, 0, 0
