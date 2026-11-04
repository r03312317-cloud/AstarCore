.option norvc
.section .text
.globl _start
_start:
 li sp,0x80010000
 la t0,machine_fail
 csrw mtvec,t0
 li t0,0x80004000
 li t1,2048
1: sw zero,0(t0)
 addi t0,t0,4
 addi t1,t1,-1
 bnez t1,1b
 // Code alias c0000000 -> 80000000, UART identity. Build two roots.
 li t0,0x80004c00
 li t1,0x200000cf
 sw t1,0(t0)
 li t0,0x80005c00
 sw t1,0(t0)
 li t0,0x80004100
 li t1,0x040000c7
 sw t1,0(t0)
 li t0,0x80005100
 sw t1,0(t0)
 j test_setup
enter_supervisor:
 li t0,0xa000
 csrw medeleg,t0 // delegate load/store page faults
 li t0,0x80480004 // Sv32 ASID1 root80004000
 csrw satp,t0
 sfence.vma
 la t0,s_entry
 li t1,0x40000000
 add t0,t0,t1
 csrw mepc,t0
 li t0,0x800
 csrw mstatus,t0
 mret
machine_fail:
 li a0,0x58
 jal ra,putc
 csrr a0,mcause
 jal ra,puthex
 csrr a0,mepc
 jal ra,puthex
 csrr a0,mtval
 jal ra,puthex
1: j 1b
puthex:
 mv a4,a0
 mv a5,ra
 li a3,8
3: srli a0,a4,28
 addi a0,a0,48
 li a6,58
 blt a0,a6,4f
 addi a0,a0,39
4: jal ra,putc
 slli a4,a4,4
 addi a3,a3,-1
 bnez a3,3b
 li a0,32
 jal ra,putc
 jr a5
putc:
 li a1,0x10000000
2: lw a2,0(a1)
 bltz a2,2b
 sw a0,0(a1)
 ret
pass:
 li a0,0x50
 jal ra,putc
 li a0,0x41
 jal ra,putc
 li a0,0x53
 jal ra,putc
 li a0,0x53
 jal ra,putc
 li a0,0x0a
 jal ra,putc
success: j success
fail:
 li a0,0x46
 jal ra,putc
 li a0,0x0a
 jal ra,putc
failed: j failed
