/* Peripheral-driven mip.SEIP RMW test. Interrupt delivery disabled deliberately:
 * UART TX-ready drives PLIC S context SEIP, then is removed and claimed/completed.
 * Hardware SEIP must be visible to reads, but not captured by CSRRS/RC[I]. */
.option norvc
.section .text
.globl _start
_start:
 csrw mie,zero
 csrw mstatus,zero
 li t0,0x200
 csrw mideleg,t0
 csrw mip,zero
 li t0,0x0c000004
 li t1,1
 sw t1,0(t0)
 li t0,0x0c002080
 li t1,2
 sw t1,0(t0)
 li s0,0
next_case:
 csrw mip,zero
 li t0,1
 beq s0,t0,setup_clear_stip
 li t0,3
 beq s0,t0,setup_clear_ssip
 j source_on
setup_clear_stip:
 li t0,32
 csrw mip,t0
 j source_on
setup_clear_ssip:
 li t0,2
 csrw mip,t0
source_on:
 li t0,0x1000000c
 li t1,2
 sw t1,0(t0)
 li t2,1000
wait_high:
 csrr t1,mip
 andi t1,t1,512
 bnez t1,rmw
 addi t2,t2,-1
 bnez t2,wait_high
 j fail
rmw:
 beqz s0,set_stip
 li t0,1
 beq s0,t0,clear_stip
 li t0,2
 beq s0,t0,set_ssip
 csrrci s2,mip,2
 li s1,0
 j source_off
set_stip:
 li t0,32
 csrrs s2,mip,t0
 li s1,32
 j source_off
clear_stip:
 li t0,32
 csrrc s2,mip,t0
 li s1,0
 j source_off
set_ssip:
 csrrsi s2,mip,2
 li s1,2
source_off:
 andi t0,s2,512
 beqz t0,fail
 li t0,0x1000000c
 sw zero,0(t0)
 li t0,0x0c201004
 lw t1,0(t0)
 li t2,1
 bne t1,t2,fail
 sw t1,0(t0)
 lw t1,0(t0)
 bnez t1,fail
 csrr t1,mip
 andi t1,t1,0x222
 bne t1,s1,fail
 addi s0,s0,1
 li t0,4
 bltu s0,t0,next_case
 /* Explicit CSRRW must retain software-writable SEIP functionality. */
 li t0,512
 csrrw s2,mip,t0
 csrr t1,mip
 andi t1,t1,512
 beqz t1,fail
 csrrw s2,mip,zero
 andi t1,s2,512
 beqz t1,fail
 csrr t1,mip
 andi t1,t1,0x222
 bnez t1,fail
 la a0,passmsg
 j print
fail:
 la a0,failmsg
print:
 lbu t2,0(a0)
 beqz t2,done
 li t0,0x10000000
wait_tx:
 lw t1,0(t0)
 bltz t1,wait_tx
 sw t2,0(t0)
 addi a0,a0,1
 j print
done: j done
passmsg: .asciz "SEIP PERIPHERAL PASS CSRRS CSRRC CSRRSI CSRRCI CSRRW\n"
failmsg: .asciz "SEIP PERIPHERAL FAIL\n"
