#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"
export PATH="$root/tools:$PATH"
mkdir -p build/compact_boot reports/compact_boot
# Directed regressions retain the Core_01 diagnostic checks. This long boot
# model uses the synthesis RTL branch to avoid evaluating diagnostic shadow
# machines on every cycle; guest execution and actual serial/pixel ports remain.
verilator --savable --cc --exe --build -j 2 -UVERILATOR -Wno-fatal \
 --top-module rv32_linux_compact_sim_top --Mdir "$root/build/compact_boot" \
 -CFLAGS '-std=c++17 -DRV32_SAVABLE' -MAKEFLAGS 'OPT_FAST=-O3' \
 rtl/*.v inputs/gui/soc_fb_commit_cdc.sv inputs/gui/rv32_framebuffer_scanout_128.sv \
 sim/compact_boot/compact_top.sv "$root/sim/compact_boot/main.cpp" \
 > reports/compact_boot/build.log 2>&1
sha256sum build/compact_boot/Vrv32_linux_compact_sim_top > reports/compact_boot/model.sha256
