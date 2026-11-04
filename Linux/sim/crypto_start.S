.section .text.start,"ax"
.global _start
_start:
 la sp,_stack_top
 la t0,trap
 csrw mtvec,t0
 call main
1: j 1b
trap:
 li t0,0x10000000
 li t1,0x45
 sw t1,0(t0)
2: j 2b
