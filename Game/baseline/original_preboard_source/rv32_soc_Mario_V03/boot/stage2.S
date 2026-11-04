.section .bootstrap,"ax",@progbits
.global _start
_start:
    li sp, 0x2000e000
    lui t0, %hi(__body_load)
    addi t0, t0, %lo(__body_load)
    li t1, 0x10002000
    lui t2, %hi(__body_end)
    addi t2, t2, %lo(__body_end)
1:  lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    bltu t1, t2, 1b
    fence rw,rw
    .word 0x0000100f
    li t0, 0x10002000
    jr t0
