OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    ITCM (rx)  : ORIGIN = 0x10000000, LENGTH = 64K
    DTCM (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS {
    .text : ALIGN(4) {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > ITCM

    .rodata : ALIGN(4) {
        __rodata_start = .;
        *(.srodata .srodata.*)
        *(.rodata .rodata.*)
        __rodata_end = .;
    } > DTCM

    .data : ALIGN(4) {
        *(.sdata .sdata.*)
        *(.data .data.*)
    } > DTCM

    .bss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DTCM

    __stack_top = ORIGIN(DTCM) + LENGTH(DTCM) - 0x1000;
    ASSERT(__bss_end <= __stack_top, "CoreMark DTCM data overlaps stack")
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.riscv.attributes) }
}
