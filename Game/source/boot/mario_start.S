/* [ARCH] 入口在 DDR，正文运行在 0x10004000 以上的指令 SRAM。 */
/* [ARCH] 按链接器 LMA/VMA 边界复制正文，不覆盖 loader 与 stage2。 */
/* [ARCH] 同步取指后清零 BSS，建立 16 字节对齐 C 栈。 */
/* [ARCH] 栈顶 0x88000000，常量/数据/BSS 留在 DDR。 */
/* [ARCH] mtvec 指向不依赖普通 C 栈的异常输出路径。 */
/* [ARCH] 异常通过 UART 输出 TRAP 标记后停留。 */
/* [ARCH] 真正执行 main 的是 RV32，6502 只是其中的软件模拟。 */
/* V02 DDR bootstrap: copy executable text to 0x10004000 ITCM. */
/* -------------------------------------------------------------------------
 * mario_start.S -- DDR entry for the Mario V02 RISC-V firmware.
 *
 * The uploaded DDR image contains the bootstrap, ITCM text load image,
 * rodata and data. Copy text above the loader/stage2 ITCM regions, clear
 * DDR BSS, then enter main. The linker fixes the stack top in DDR.
 *
 * mtvec resets to 0, which is outside the ITCM.  Without installing a handler
 * every exception turns into an infinite trap loop with no observable output,
 * which looks exactly like a dead core.  The handler below reports and halts.
 * ------------------------------------------------------------------------- */
    .section .text.init, "ax", @progbits
    .globl _start
    .type  _start, @function
_start:
    la      sp, __stack_top
    la      gp, __global_pointer$
    la      t0, _trap_entry
    csrw    mtvec, t0
    /* Copy executable code into unused ITCM, above loader and stage2. */
    la      t0, __itcm_load
    la      t1, __itcm_start
    la      t2, __itcm_end
4:
    bgeu    t1, t2, 5f
    lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       4b
5:
    fence   rw,rw
    .word   0x0000100f
    la      t0, __bss_start
    la      t1, __bss_end
1:
    bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    /* keep the stack 16-byte aligned for the C ABI */
    andi    sp, sp, -16
    call    main
3:
    j       3b
    .size _start, . - _start

    .section .text.boottrap, "ax", @progbits
    .align 2
    .globl _trap_entry
    .type  _trap_entry, @function
_trap_entry:
    /* Store straight into the UART transmit register.  The peripheral holds
     * req_ready low until the previous byte has been taken, so back-pressure
     * paces these writes and no polling is needed.  Prints "TRAP=<code>\n". */
    li      t0, 0x30000020
    li      t1, 'T'
    sw      t1, 0(t0)
    li      t1, 'R'
    sw      t1, 0(t0)
    li      t1, 'A'
    sw      t1, 0(t0)
    li      t1, 'P'
    sw      t1, 0(t0)
    li      t1, '='
    sw      t1, 0(t0)
    csrr    t2, mcause
    andi    t2, t2, 15
    li      t3, 10
    blt     t2, t3, 1f
    addi    t2, t2, 39          /* 'a' - '0' - 10 */
1:
    addi    t2, t2, '0'
    sw      t2, 0(t0)
    li      t1, '\n'
    sw      t1, 0(t0)
2:
    j       2b
    .size _trap_entry, . - _trap_entry
