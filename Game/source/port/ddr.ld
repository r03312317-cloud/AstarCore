/* [ARCH] 同时描述 DDR 装载位置和 ITCM 正文运行位置。 */
/* [ARCH] .boot 保留入口和异常输出，.text 的装载镜像仍在 APP 区。 */
/* [ARCH] .ddr_text 放置选定紧凑循环，常量/数据/BSS 保留在 DDR。 */
/* [ARCH] 搬运边界符号与 mario_start.S 构成共同约定。 */
/* [ARCH] NOLOAD BSS 不占传输字节，但启动时要清零。 */
/* [ARCH] 链接断言限制 ITCM 与 APP 容量。 */
/* [ARCH] ELF 文件大小不等于运行时内存占用。 */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { APP (rwx) : ORIGIN = 0x84000000, LENGTH = 8M
         ITCM (rwx) : ORIGIN = 0x10004000, LENGTH = 48K }
PHDRS { boot PT_LOAD FLAGS(5); code PT_LOAD FLAGS(5); rodata PT_LOAD FLAGS(4); data PT_LOAD FLAGS(6); }
SECTIONS {
 .boot : ALIGN(16) { KEEP(*(.text.init)) KEEP(*(.text.boottrap)) } > APP :boot
 .ddr_text : ALIGN(16) { *(.ddr_text .ddr_text.*) } > APP :boot
 .text : ALIGN(16) { __itcm_start = .; *(.text .text.*) . = ALIGN(16); __itcm_end = .; } > ITCM AT>APP :code
 __itcm_load = LOADADDR(.text);
 .rodata : ALIGN(16) { *(.rodata .rodata.* .srodata .srodata.*) } > APP :rodata
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
ASSERT(__itcm_end <= 0x10010000, "Mario executable text exceeds reserved ITCM")
