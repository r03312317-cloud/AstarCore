#include "soc_vm_common.inc"
test_setup:
 // Clone the executable into a different physical megapage, then change only
 // the first instruction after the SATP switch at the same virtual address.
 li t0,0x80000000
 li t1,0x80400000
 li t2,1024
1: lw t3,0(t0)
 sw t3,0(t1)
 addi t0,t0,4
 addi t1,t1,4
 addi t2,t2,-1
 bnez t2,1b
 la t0,changed_instruction
 li t1,0x00400000
 add t0,t0,t1
 li t1,0x00200413 // addi s0,zero,2
 sw t1,0(t0)
 li t0,0x80005c00
 li t1,0x201000cf // second root c0000000 -> 80400000
 sw t1,0(t0)
 fence.i
 j enter_supervisor
s_entry:
 li sp,0xc0010000
 li t0,0x80880005
 csrw satp,t0
changed_instruction:
 li s0,1 // physical old mapping gives1; new mapping must give2
 li t0,2
 bne s0,t0,fail
 j pass
