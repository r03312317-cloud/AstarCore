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
