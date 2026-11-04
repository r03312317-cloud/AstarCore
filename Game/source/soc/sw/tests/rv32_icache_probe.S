.section .text.icache_conflicts,"ax",@progbits
.option norvc
.balign 8192
.global rv32_ic_a
.type rv32_ic_a,@function
rv32_ic_a:
    addi a0,a0,49
    ret
.size rv32_ic_a,.-rv32_ic_a
.balign 8192
.global rv32_ic_b
.type rv32_ic_b,@function
rv32_ic_b:
    addi a0,a0,67
    ret
.size rv32_ic_b,.-rv32_ic_b
.balign 8192
.global rv32_ic_c
.type rv32_ic_c,@function
rv32_ic_c:
    addi a0,a0,83
    ret
.size rv32_ic_c,.-rv32_ic_c
.balign 64
.space 60
.global rv32_ic_cross
.type rv32_ic_cross,@function
rv32_ic_cross:
    addi a0,a0,7
    ret
.size rv32_ic_cross,.-rv32_ic_cross
