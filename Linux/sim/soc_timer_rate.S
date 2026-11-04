/* Actual M timer -> delegated STIP -> S ecall rearm test. No Linux/SBI binary.
 * t3..t6 reserved for M trap, t0..t2 for S trap. S foreground uses a registers.
 * Each deadline is previous S servicing mtime + 1000 ticks (1 ms at 1 MHz).
 */
.option norvc
.section .text
.globl _start
_start:
 la t0,mtrap
 csrw mtvec,t0
 la t0,strap
 csrw stvec,t0
 li t0,32
 csrw mideleg,t0
 csrw medeleg,zero
 csrw satp,zero
 li s0,0
 li s3,-1
 li s4,0
 li s5,0
 li s7,0
 li a2,0x12345678
 li a3,0x76543210
 li a4,0
 li t0,0x0200bff8
 lw s2,0(t0)
 mv s8,s2
 addi s1,s2,1000
 li t0,0x02004000
 li t1,-1
 sw t1,4(t0)
 sw s1,0(t0)
 sw zero,4(t0)
 li t0,160
 csrw mie,t0
 la t0,foreground
 csrw mepc,t0
 li t0,0x802
 csrw mstatus,t0
 mret
.align 2
foreground:
 addi a4,a4,1
 li a5,32
 bltu s0,a5,foreground
foreground_end:
 csrci sstatus,2
 li a5,0x12345678
 bne a2,a5,fail
 li a5,0x76543210
 bne a3,a5,fail
 beqz a4,fail
 li a5,32
 bne s5,a5,fail
 bne s7,a5,fail
 sub s9,s2,s8
 li a5,32000
 bltu s9,a5,fail
 la a0,passmsg
 jal ra,puts
 mv a0,s0
 jal ra,hex
 li a0,32
 jal ra,putc
 mv a0,s3
 jal ra,hex
 li a0,32
 jal ra,putc
 mv a0,s4
 jal ra,hex
 li a0,32
 jal ra,putc
 mv a0,s9
 jal ra,hex
 li a0,10
 jal ra,putc
done: j done
.align 2
mtrap:
 csrr t3,mcause
 li t4,0x80000007
 beq t3,t4,mtimer
 li t4,9
 bne t3,t4,fail
 csrr t3,mepc
 la t4,rearm_ecall
 bne t3,t4,fail
 addi t3,t3,4
 csrw mepc,t3
 li t3,32
 csrc mip,t3
 addi s7,s7,1
 li t3,32
 beq s0,t3,mreturn
 li t3,0x02004000
 li t4,-1
 sw t4,4(t3)
 sw s1,0(t3)
 sw zero,4(t3)
 li t3,128
 csrs mie,t3
mreturn:
 mret
mtimer:
 li t3,0x0200bff8
 lw t4,0(t3)
 bltu t4,s1,fail
 csrr t3,mepc
 la t4,foreground
 bltu t3,t4,fail
 la t4,foreground_end
 bgeu t3,t4,fail
 addi s5,s5,1
 li t3,128
 csrc mie,t3
 li t3,32
 csrs mip,t3
 mret
.align 2
strap:
 csrr t0,scause
 li t1,0x80000005
 bne t0,t1,fail
 csrr s6,sepc
 la t1,foreground
 bltu s6,t1,fail
 la t1,foreground_end
 bgeu s6,t1,fail
 li t0,0x0200bff8
 lw t1,0(t0)
 sub t2,t1,s2
 li t0,1000
 bltu t2,t0,fail
 li t0,1500
 bgtu t2,t0,fail
 bgeu t2,s3,1f
 mv s3,t2
1: bleu t2,s4,2f
 mv s4,t2
2: mv s2,t1
 addi s1,t1,1000
 addi s0,s0,1
rearm_ecall:
 ecall
 csrr t0,sepc
 bne t0,s6,fail
 sret
fail:
 la a0,failmsg
 jal ra,puts
 j done
/* Printing only after timer test; retain return using a6 / a7. */
puts:
 mv a6,ra
 mv a1,a0
3: lbu a0,0(a1)
 beqz a0,4f
 jal ra,putc
 addi a1,a1,1
 j 3b
4: jr a6
hex:
 mv a6,ra
 mv a1,a0
 li a7,8
5: srli a0,a1,28
 li t0,10
 bltu a0,t0,6f
 addi a0,a0,39
6: addi a0,a0,48
 jal ra,putc
 slli a1,a1,4
 addi a7,a7,-1
 bnez a7,5b
 jr a6
putc:
 li t0,0x10000000
7: lw t1,0(t0)
 bltz t1,7b
 sw a0,0(t0)
 ret
passmsg: .asciz "TIMER PASS count/min/max/elapsed="
failmsg: .asciz "TIMER FAIL\n"
