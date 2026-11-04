/* -------------------------------------------------------------------------
 * link.ld -- rv32_soc_Game firmware memory layout.
 *
 *   ITCM 0x10000000 64 KiB : .text.init, .text   (code SRAM, cached)
 *   DTCM 0x20000000 64 KiB : .rodata, .data, .bss, stack (grows down)
 *
 * RV32 accesses both initialized SRAM banks through its caches. The legacy
 * ITCM/DTCM names and addresses are retained for firmware compatibility.
 * Read-only data remains ahead of .data in the data SRAM image.
 *
 * Both SRAM banks are pre-loaded from *.mem files at bitstream generation, so the
 * board boots the game with no host or UART download.
 * ------------------------------------------------------------------------- */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  ITCM (rx) : ORIGIN = 0x10000000, LENGTH = 64K
  DTCM (rw) : ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS
{
  .text : ALIGN(4)
  {
    *(.text.init)
    *(.text .text.*)
  } > ITCM

  .rodata : ALIGN(4)
  {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
    . = ALIGN(4);
  } > DTCM

  .data : ALIGN(4)
  {
    *(.data .data.*)
    *(.sdata .sdata.*)
    . = ALIGN(4);
  } > DTCM

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DTCM

  __global_pointer$ = ORIGIN(DTCM) + 0x800;
  __stack_top = ORIGIN(DTCM) + LENGTH(DTCM);

  /DISCARD/ : { *(.comment) *(.note*) *(.riscv.attributes) }
}

ASSERT(__bss_end + 4096 <= __stack_top, "DTCM overflow: stack needs 4 KiB")
ASSERT(SIZEOF(.text) <= 64K, "ITCM overflow")
/* .rodata and .data are one contiguous DTCM image, so they must start at the
 * DTCM base for the .mem file to line up with the RAM array index. */
ASSERT(ADDR(.rodata) == ORIGIN(DTCM), "DTCM image must start with .rodata")
ASSERT(ADDR(.data) == ADDR(.rodata) + SIZEOF(.rodata), ".data must follow .rodata")
ASSERT(__bss_start == ADDR(.data) + SIZEOF(.data), ".bss must follow .data")
