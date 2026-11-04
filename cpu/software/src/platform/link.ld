OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 64K }
SECTIONS {
 .text : { KEEP(*(.text.init)) *(.text .text.*) } > RAM
 .rodata : { *(.rodata .rodata.*) } > RAM
 . = ALIGN(16);
 .data : { *(.data .data.*) *(.sdata .sdata.*) } > RAM
 __global_pointer$ = . + 0x800;
 .bss (NOLOAD) : {
   . = ALIGN(16); __bss_start = .;
   *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
   . = ALIGN(16); __bss_end = .;
 } > RAM
 __stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;
 ASSERT(__bss_end < __stack_top - 8192, "Less than 8 KiB stack remains")
 /DISCARD/ : { *(.comment) *(.eh_frame*) }
}
