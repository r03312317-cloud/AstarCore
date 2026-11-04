OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
 . = 0x80000000;
 .text : { *(.text.start) *(.text*) }
 .rodata : { *(.rodata*) }
 .data : { *(.data*) *(.sdata*) }
 .bss : { *(.bss*) *(.sbss*) *(COMMON) }
 _stack_top = 0x83e00000;
}
