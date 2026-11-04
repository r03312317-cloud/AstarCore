.option norvc
.section .text
.globl _start
_start:
 li sp,0x80010000
 // Page0: two colors at first two pixels and a blue pair in a later row.
 li t0,0x83f00000
 li t1,0x07e0f800
 sw t1,0(t0)
 li t0,0x83f1f4c8
 li t1,0x001f001f
 sw t1,0(t0)
 fence.i
 li s0,0x10001000
 li t0,0x83f00000
 sw t0,0(s0)
 li t0,1
 sw t0,4(s0)
 sw t0,8(s0)
1: lw t0,8(s0)
 bnez t0,1b
 // Page1 may be drawn while page0 scans. It becomes visible only on next vblank.
 li t0,0x83f70800
 li t1,0xffe0ffff
 sw t1,0(t0)
 fence.i
 li t0,0x83f70800
 sw t0,0(s0)
 li t0,1
 sw t0,8(s0)
2: lw t0,8(s0)
 bnez t0,2b
 li a0,86
 jal ra,putc
 li a0,10
 jal ra,putc
3: j 3b
putc:
 li a1,0x10000000
4: lw a2,0(a1)
 bltz a2,4b
 sw a0,0(a1)
 ret
