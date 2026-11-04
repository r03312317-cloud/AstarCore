/* [ARCH] 二级接收器 VMA 在预留 ITCM，LMA 在初次上传的 DDR。 */
/* [ARCH] 入口与正文配合 stage2.S 先搬运后执行。 */
/* [ARCH] 构建后检查接收器能装进 1024 字节单块。 */
/* [ARCH] 此布局不能直接用于马里奥主程序。 */
OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS {
    .bootstrap 0x84000000 : { *(.bootstrap) . = ALIGN(4); }
    __body_load = LOADADDR(.bootstrap) + SIZEOF(.bootstrap);
    .body 0x10002000 : AT(__body_load) {
        *(.text.entry) *(.text .text.*) *(.rodata .rodata.*) . = ALIGN(4);
        __body_end = .;
    }
    .unexpected : { *(.data .data.*) *(.bss .bss.*) *(.sdata .sdata.*) *(.sbss .sbss.*) *(COMMON) }
    /DISCARD/ : { *(.comment) *(.note*) *(.riscv.attributes) }
}
ASSERT(SIZEOF(.bootstrap)+SIZEOF(.body)<=1024,"bootstrap exceeds one APAL block")
ASSERT(SIZEOF(.unexpected)==0,"bootstrap must have no mutable globals")
