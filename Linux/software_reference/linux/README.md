# Linux BSP and reproducible software

Target: one RV32IMA_Zicsr_Zifencei hart, ILP32 soft-float, Sv32, 64 MiB
**simulation RAM**. The uploaded baseline does not contain an integrated DDR
controller or physical HDMI transmitter. This BSP does not establish board boot.

From the project root run `scripts/software_build.sh` (or invoke it by absolute
path from another directory) after installing the
host dependencies required by Buildroot (C/C++ compiler, make, patch, tar, gzip,
xz, bzip2, cpio, rsync, perl, Python3, wget, unzip, file, bc, flex, bison).
`RV32_DEPS`, `RV32_SW_OUT`, `RV32_BOOT_DIR`, and `JOBS` override source/output locations
and parallelism. Use absolute paths for overridden directory variables. Network access is needed for official pinned upstream packages.
The Buildroot external tree builds its own RV32 musl cross-toolchain, BusyBox,
kernel, LVGL application, initramfs, and device-tree tools. OpenSBI is then built
with that Linux toolchain: some bare-metal linkers cannot produce required PIE.
Hashes and licenses are in `SOFTWARE_SOURCES.md` and package hash files; retain
upstream source archives and use Buildroot `make legal-info` for redistribution.

## Boot layout

| Object | Physical address |
|---|---:|
| OpenSBI `fw_jump.bin` (embedded DTB) | 0x80000000 |
| Linux `Image` (RV32 requires 4 MiB alignment) | 0x80400000 |
| Initramfs: gzip for CPU-only boot-v1; raw CPIO for video-v4 | 0x82400000 |
| Reserved two RGB565 frames | 0x83f00000, 0x83f70800 |

Boot hart ID is zero. OpenSBI embeds its DTB, so reset `a1=0` is acceptable for
these images. Initrd bounds are inserted from the actual loaded byte length
(gzip for boot-v1, raw CPIO for boot-video-v4). Never
mix firmware with an older DTB/initrd size. `software_make_boot_image.py` writes
addresses, lengths and SHA-256 hashes; this is a load manifest, not a boot result.

## Drivers and ownership

`rv32_uart.c` implements the custom UART v1 register interface and ttyAS0,
including IRQ-driven serial_core operation and early console. It is not 16550.
The command console owns UART; GUI commands use a separate private FIFO.

`rv32_fb.c` implements 640×360 RGB565 double buffering. The display engine
is present in the integrated generic scanout simulation. The source DTS and
CPU-only boot-v1 leave its node disabled; the preferred boot-video-v4 explicitly
enables it. This configuration is not itself Linux fbdev/GUI acceptance. The
mapped reserved RAM is **not inherently uncached** on Sv32. Page flipping uses
a platform-specific RV32 contract: FENCE.I cleans all dirty D-cache lines and the
following MMIO stalls until maintenance finishes. Architectural FENCE.I alone
does not promise this. Applications write only the inactive buffer, then pan;
the driver waits for vblank ownership transfer and checks the active base.
Changes to cache RTL require revalidating this contract before enabling display.

## Evidence boundaries

Host LVGL screenshots and fake-fbdev tests exercise UI logic and buffer ownership,
not physical scanout. QEMU virt uses its own 16550 and PLIC model and is a
software-reference test only, never RV32 acceptance. Real RV32 RTL UART transcripts
are maintained separately by the SoC integration tests. The rootfs boot script
runs actual uname, proc inspection, directory listing and ps between explicit
markers; their output must be captured from a running kernel, not prefilled.
