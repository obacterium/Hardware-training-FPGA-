.data
.align 7
    # Addresses relative to the stage 1 table base, then 16-byte labels.
    .byte 0, 6, 4, 8, 5, 2, 7, 3
    .word 0, 0
    .ascii "FALLING BLOCKS  "
    .ascii "SCORE           "
    .ascii "LINES           "
    .ascii "LEVEL           "
    .ascii "PLAYING         "
    .ascii "PAUSED          "
    .ascii "GAME OVER       "
    .ascii "EXITED          "
    .ascii "LEFT/RIGHT MOVE "
    .ascii "UP ROTATE       "
    .ascii "DOWN SOFT DROP  "
    .ascii "SPACE HARD DROP "
    .ascii "P PAUSE/RESUME  "
    .ascii "R RESTART       "
    .ascii "ESC EXIT        "
