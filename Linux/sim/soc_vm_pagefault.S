#include "soc_vm_common.inc"
test_setup:
 li t0,0x80004400 // VPN1 256: readonly nonexecute 80400000
 li t1,0x201000c3
 sw t1,0(t0)
 j enter_supervisor
s_entry:
 li sp,0xc0010000
 la t0,supervisor_trap
 csrw stvec,t0
 li s0,0
 li s1,13
 li s2,0x50000000
 la s3,faulting_load
faulting_load:
 lw t0,0(s2)
 li t0,1
 bne s0,t0,fail
 li s1,15
 li s2,0x40000000
 la s3,faulting_store
faulting_store:
 sw zero,0(s2)
 li t0,2
 bne s0,t0,fail
 j pass
supervisor_trap:
 csrr t0,scause
 bne t0,s1,fail
 csrr t0,stval
 bne t0,s2,fail
 csrr t0,sepc
 bne t0,s3,fail
 addi t0,t0,4
 csrw sepc,t0
 addi s0,s0,1
 sret
