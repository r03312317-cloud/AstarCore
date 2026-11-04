#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEPS=${RV32_DEPS:-$ROOT/../software_deps}
OUT=${RV32_SW_OUT:-$ROOT/../software_build}
JOBS=${JOBS:-4}
BOOT=${RV32_BOOT_DIR:-$ROOT/firmware/generated}
"$ROOT/scripts/software_fetch.sh"
make -C "$DEPS/buildroot-2025.02.1" O="$OUT" BR2_EXTERNAL="$ROOT/buildroot" rv32_rv32_defconfig
make -C "$OUT" -j"$JOBS"
KERNEL_BUILD=$(find "$OUT/build" -maxdepth 1 -type d -name "linux-6.12.9" | head -n 1)
mkdir -p "$BOOT"
cp "$KERNEL_BUILD/.config" "$BOOT/kernel.config"
python3 "$ROOT/scripts/software_validate.py" "$KERNEL_BUILD/vmlinux" "$KERNEL_BUILD/.config" > "$BOOT/kernel_validation.json"
# Buildroot's Linux toolchain supports RV32 ILP32 PIE, unlike some bare-metal ld builds.
CROSS="$OUT/host/bin/riscv32-buildroot-linux-musl-"
python3 "$ROOT/scripts/software_patch_opensbi.py" "$DEPS/opensbi-1.6"
mkdir -p "$BOOT"
"$OUT/host/bin/dtc" -I dts -O dtb "$ROOT/linux/rv32-rv32.dts" -o "$BOOT/rv32-rv32.dtb"
INITRD_END=$(python3 -c 'import os,sys; print(format(0x82400000 + os.path.getsize(sys.argv[1]), "x"))' "$OUT/images/rootfs.cpio.gz")
"$OUT/host/bin/fdtput" -t x "$BOOT/rv32-rv32.dtb" /chosen linux,initrd-start 82400000
"$OUT/host/bin/fdtput" -t x "$BOOT/rv32-rv32.dtb" /chosen linux,initrd-end "$INITRD_END"
make -C "$DEPS/opensbi-1.6" O="$OUT/opensbi" -j"$JOBS" PLATFORM=generic PLATFORM_DEFCONFIG=rv32_defconfig \
 CROSS_COMPILE="$CROSS" PLATFORM_RISCV_XLEN=32 PLATFORM_RISCV_ISA=rv32ima_zicsr_zifencei PLATFORM_RISCV_ABI=ilp32 \
 FW_TEXT_START=0x80000000 FW_JUMP_ADDR=0x80400000 FW_FDT_PATH="$BOOT/rv32-rv32.dtb"
cp "$OUT/opensbi/platform/generic/firmware/fw_jump.bin" "$BOOT/"
cp "$OUT/opensbi/platform/generic/firmware/fw_jump.elf" "$BOOT/"
cp "$OUT/images/Image" "$OUT/images/rootfs.cpio.gz" "$BOOT/"
python3 "$ROOT/scripts/software_make_boot_image.py" "$BOOT"

# Documented OpenSBI boot-print suppression only, for faster RTL diagnostics.
make -C "$DEPS/opensbi-1.6" O="$OUT/opensbi-quiet" -j"$JOBS" PLATFORM=generic PLATFORM_DEFCONFIG=rv32_defconfig \
 CROSS_COMPILE="$CROSS" PLATFORM_RISCV_XLEN=32 PLATFORM_RISCV_ISA=rv32ima_zicsr_zifencei PLATFORM_RISCV_ABI=ilp32 \
 FW_TEXT_START=0x80000000 FW_JUMP_ADDR=0x80400000 FW_FDT_PATH="$BOOT/rv32-rv32.dtb" FW_OPTIONS=0x1
cp "$OUT/opensbi-quiet/platform/generic/firmware/fw_jump.bin" "$BOOT/fw_jump_quiet.bin"
cp "$OUT/opensbi-quiet/platform/generic/firmware/fw_jump.elf" "$BOOT/fw_jump_quiet.elf"
(cd "$BOOT" && sha256sum Image rv32-rv32.dtb boot_manifest.json fw_jump.bin fw_jump.elf fw_jump_quiet.bin fw_jump_quiet.elf kernel.config kernel_validation.json rootfs.cpio.gz > SHA256SUMS)
