#include "soc_vm_common.inc"
test_setup:
 li t0,0x80004400
 li t1,0x200000c7
 sw t1,0(t0)
 li t0,0x80005400
 li t1,0x201000c7
 sw t1,0(t0)
 li t0,0x80009000
 li t1,0x11112222
 sw t1,0(t0)
 li t0,0x80409000
 li t1,0x33334444
 sw t1,0(t0)
 j enter_supervisor
s_entry:
 li sp,0xc0010000
 li s0,0x40009000
 lw t0,0(s0)
 li t1,0x11112222
 bne t0,t1,fail
 li t0,0x80880005
 csrw satp,t0 // ASID2 maps same VA to distinct PA, no fence needed for new ASID
 lw t0,0(s0)
 li t1,0x33334444
 bne t0,t1,fail
 li t0,0x80480004
 csrw satp,t0 // ASID1 old cached mapping
 lw t0,0(s0)
 li t1,0x11112222
 bne t0,t1,fail
 li t0,0xc0004400
 li t1,0x201000c7
 sw t1,0(t0) // dirty cached PTE remap
 sfence.vma
 lw t0,0(s0)
 li t1,0x33334444
 bne t0,t1,fail
 j pass
