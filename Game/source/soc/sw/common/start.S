/* -------------------------------------------------------------------------
 * start.S -- bare-metal entry for the rv32_soc_Game RISC-V firmware.
 *
 * ITCM holds .text and .rodata and is pre-loaded by the FPGA block RAM init
 * file, so no copy is needed.  DTCM holds .data (empty in this build, also
 * pre-loaded) and .bss, which is cleared here before main() runs.
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

    .section .text, "ax", @progbits
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
