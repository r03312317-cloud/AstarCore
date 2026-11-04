#!/bin/sh
# Enable only the integrated simulation scanout; this does not enable HDMI hardware.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEPS=${RV32_DEPS:-$ROOT/../software_deps}
OUT=${RV32_SW_OUT:-$ROOT/../software_build}
CPU=${1:?usage: software_video_bundle.sh CPU_BUNDLE NEW_VIDEO_BUNDLE}
VIDEO=${2:?missing new video directory}
[ ! -e "$VIDEO" ] || { echo "Refusing to replace an existing bundle" >&2; exit 1; }
mkdir -p "$VIDEO"
VIDEO=$(CDPATH= cd -- "$VIDEO" && pwd)
for FILE in Image rootfs.cpio.gz kernel.config kernel_validation.json rv32-rv32.dtb; do cp "$CPU/$FILE" "$VIDEO/"; done
"$OUT/host/bin/fdtput" -t s "$VIDEO/rv32-rv32.dtb" /soc/framebuffer@10001000 status okay
# OpenSBI inserts its actual firmware reservations; do not duplicate them.
if "$OUT/host/bin/fdtget" -l "$VIDEO/rv32-rv32.dtb" /reserved-memory | grep -qx opensbi@80000000; then
 "$OUT/host/bin/fdtput" -r "$VIDEO/rv32-rv32.dtb" /reserved-memory/opensbi@80000000
fi
# Initramfs requires Buildroot /init to mount devtmpfs before /sbin/init.
ARGS=$("$OUT/host/bin/fdtget" "$VIDEO/rv32-rv32.dtb" /chosen bootargs | sed 's@rdinit=/sbin/init@rdinit=/init@g')
"$OUT/host/bin/fdtput" -t s "$VIDEO/rv32-rv32.dtb" /chosen bootargs "$ARGS"
INITRD=rootfs.cpio.gz
if [ "${RV32_RAW_INITRD:-0}" = 1 ]; then
 gzip -dc "$VIDEO/rootfs.cpio.gz" > "$VIDEO/rootfs.cpio"
 rm "$VIDEO/rootfs.cpio.gz"
 INITRD=rootfs.cpio
 if [ "${RV32_TRIM_CXX:-0}" = 1 ]; then
  mv "$VIDEO/rootfs.cpio" "$VIDEO/rootfs-untrimmed.cpio"
  python3 "$ROOT/scripts/software_trim_rootfs.py" "$VIDEO/rootfs-untrimmed.cpio" "$VIDEO/rootfs.cpio"
  rm "$VIDEO/rootfs-untrimmed.cpio"
 fi
 END=$(python3 -c 'import os,sys; print(hex(0x82400000+os.path.getsize(sys.argv[1])))' "$VIDEO/$INITRD")
 "$OUT/host/bin/fdtput" -t x "$VIDEO/rv32-rv32.dtb" /chosen linux,initrd-end "$END"
fi
for MODE in normal quiet; do
 OPTIONS=0; [ "$MODE" != quiet ] || OPTIONS=0x1
 make -C "$DEPS/opensbi-1.6" O="$OUT/opensbi-video-$MODE" -j"${JOBS:-4}" PLATFORM=generic PLATFORM_DEFCONFIG=rv32_defconfig \
  CROSS_COMPILE="$OUT/host/bin/riscv32-buildroot-linux-musl-" PLATFORM_RISCV_XLEN=32 PLATFORM_RISCV_ISA=rv32ima_zicsr_zifencei PLATFORM_RISCV_ABI=ilp32 \
  FW_TEXT_START=0x80000000 FW_JUMP_ADDR=0x80400000 FW_FDT_PATH="$VIDEO/rv32-rv32.dtb" FW_OPTIONS="$OPTIONS"
 SUFFIX=; [ "$MODE" != quiet ] || SUFFIX=_quiet
 for EXT in bin elf; do cp "$OUT/opensbi-video-$MODE/platform/generic/firmware/fw_jump.$EXT" "$VIDEO/fw_jump$SUFFIX.$EXT"; done
done
python3 "$ROOT/scripts/software_make_boot_image.py" "$VIDEO"
(cd "$VIDEO" && sha256sum Image rv32-rv32.dtb boot_manifest.json fw_jump.bin fw_jump.elf fw_jump_quiet.bin fw_jump_quiet.elf kernel.config kernel_validation.json "$INITRD" > SHA256SUMS)

if [ -f "$VIDEO/rootfs.cpio.trim.json" ]; then (cd "$VIDEO" && sha256sum rootfs.cpio.trim.json >> SHA256SUMS); fi
