#include "soc_vm_common.inc"
test_setup: j enter_supervisor
s_entry:
 li sp,0xc0010000
 li s0,0xc0006000
 li t0,0x00100513 // addi a0,zero,1
 sw t0,0(s0)
 li t0,0x00008067 // ret
 sw t0,4(s0)
 fence.i
 jalr ra,s0,0
 li t0,1
 bne a0,t0,fail
 li t0,0x00200513
 sw t0,0(s0)
 fence.i
 jalr ra,s0,0
 li t0,2
 bne a0,t0,fail
 j pass
