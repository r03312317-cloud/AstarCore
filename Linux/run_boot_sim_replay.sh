#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"
out="${RV32_BOOT_RUN_OUTPUT:-$root/reports/compact_boot/run_$(date +%Y%m%d_%H%M%S)_$$}"
if [[ -e "$out" ]]; then echo 'Refusing to overwrite boot evidence'; exit 2; fi
mkdir "$out"
sha256sum rtl/*.v inputs/gui/soc_fb_commit_cdc.sv inputs/gui/rv32_framebuffer_scanout_128.sv \
 sim/compact_boot/compact_top.sv sim/compact_boot/main.cpp sim/compact_boot/uart_terminal_compact.h \
 sim/compact_boot/commands.tsv firmware/boot/* build/compact_boot/Vrv32_linux_compact_sim_top > "$out/inputs.sha256"
export RV32_UART_SCRIPT="$root/sim/compact_boot/commands.tsv"
export RV32_VIDEO_OUTPUT="$out/captures"
export RV32_VIDEO_MAX_CAPTURES=64
export RV32_CHECKPOINT="$out/model.ckpt"
export RV32_CHECKPOINT_INTERVAL=100000000
date -u +%FT%TZ > "$out/start_utc.txt"
set +e
build/compact_boot/Vrv32_linux_compact_sim_top firmware/boot/fw_jump.bin 3000000000 \
 firmware/boot/Image@80400000 firmware/boot/rv32-rv32.dtb@82000000 firmware/boot/rootfs.cpio@82400000 \
 > "$out/uart.log" 2> "$out/trace.log"
rc=$?
printf '%s\n' "$rc" > "$out/exit_code.txt"
date -u +%FT%TZ > "$out/end_utc.txt"
exit "$rc"
