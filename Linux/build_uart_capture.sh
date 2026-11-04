#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"
export PATH="$root/tools:$PATH"
mkdir -p build/soc_capture
capture_run="$root/reports/uart_capture_$(date +%Y%m%d_%H%M%S)_$$"
mkdir "$capture_run"
export RV32_UART_CAPTURE_RESULTS="$capture_run/checks"
verilator --cc --exe --build -j 2 -Wno-fatal --top-module rv32_linux_soc_top \
 --Mdir "$root/build/soc_capture" -MAKEFLAGS 'OPT_FAST=-O3' \
 rtl/*.v "$root/sim/linux_soc_capture.cpp" > "$capture_run/build.log" 2>&1
python3 verify_uart_capture.py
