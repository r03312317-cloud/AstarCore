OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { APP (rwx) : ORIGIN = 0x84000000, LENGTH = 8M }
PHDRS { code PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }
SECTIONS {
 .text : ALIGN(16) { KEEP(*(.text.init)) *(.text .text.*) } > APP :code
 .rodata : ALIGN(16) { *(.rodata .rodata.* .srodata .srodata.*) } > APP :code
 .data : ALIGN(16) { *(.data .data.* .sdata .sdata.*) } > APP :data
 .init_array : ALIGN(4) { PROVIDE_HIDDEN(__init_array_start = .); KEEP(*(.init_array*)) PROVIDE_HIDDEN(__init_array_end = .); } > APP :data
 .fini_array : ALIGN(4) { PROVIDE_HIDDEN(__fini_array_start = .); KEEP(*(.fini_array*)) PROVIDE_HIDDEN(__fini_array_end = .); } > APP :data
 __image_end = .;
 .bss (NOLOAD) : ALIGN(16) { __bss_start = .; *(.bss .bss.* .sbss .sbss.*) *(COMMON) . = ALIGN(16); __bss_end = .; } > APP :data
 __global_pointer$ = ORIGIN(APP)+0x800;
 __stack_top = 0x88000000;
 /DISCARD/ : { *(.comment) *(.note*) }
}
ASSERT(__bss_end <= 0x84800000, "Mario program exceeds 8 MiB")
