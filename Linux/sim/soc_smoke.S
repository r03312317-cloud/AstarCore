.option norvc
.section .text
.globl _start
_start:
 li sp,0x80010000
 li t0,0x10000000
 li t1,0x4d
 sw t1,0(t0)
 li t0,0x80004000
 li t1,1024
1: sw zero,0(t0)
 addi t0,t0,4
 addi t1,t1,-1
 bnez t1,1b
 li t0,0x80004c00
 li t1,0x200000cf
 sw t1,0(t0)
 li t0,0x80004100
 li t1,0x040000c7
 sw t1,0(t0)
 li t0,0x80080004
 csrw satp,t0
 sfence.vma
 la t0,s_entry
 li t1,0x40000000
 add t0,t0,t1
 csrw mepc,t0
 li t0,0x800
 csrw mstatus,t0
 mret
s_entry:
 li sp,0xc0010000
 li a0,0x53
 jal ra,putc
 li t0,0xc0005000
 li t1,7
 sw t1,0(t0)
 li t1,3
 amoadd.w t2,t1,(t0)
 li t3,7
 bne t2,t3,fail
 lw t2,0(t0)
 li t3,10
 bne t2,t3,fail
 lr.w t2,(t0)
 li t1,12
 sc.w t3,t1,(t0)
 bnez t3,fail
 lw t2,0(t0)
 bne t2,t1,fail
 li a0,0x41
 jal ra,putc
 li a0,0x0a
 jal ra,putc
success: j success
fail:
 li a0,0x46
 jal ra,putc
 j fail
putc:
 li a1,0x10000000
2: lw a2,0(a1)
 bltz a2,2b
 sw a0,0(a1)
 ret
