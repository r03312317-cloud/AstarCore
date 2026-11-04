#ifndef MMIO_BASE
#define MMIO_BASE 0x10000000
#endif
.section .text.init
.globl _start
_start:
 .option push
 .option norelax
 la gp,__global_pointer$
 .option pop
 la sp,__stack_top
 la t0,__bss_start
 la t1,__bss_end
1: bgeu t0,t1,2f
 sw zero,0(t0)
 addi t0,t0,4
 j 1b
2: call main
 li t0,MMIO_BASE+4
 sw a0,0(t0)
3: j 3b
