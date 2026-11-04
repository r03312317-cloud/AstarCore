#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"
export PATH="$root/tools:$PATH"
check_id="tool_recheck_$(date +%Y%m%d_%H%M%S)_$$"
check_reports="$root/reports/$check_id"
check_build="$root/build/$check_id"
mkdir "$check_reports"
mkdir -p "$check_build"
for top in sv32_tb atomic_random_tb; do
 if [[ $top == sv32_tb ]]; then sources=(rtl/rv32_sv32_mmu.v sim/sv32_tb.sv); else sources=(rtl/rv32_atomic_memory.v sim/atomic_random_tb.sv); fi
 verilator --binary --timing -j 2 -Wno-fatal --top-module "$top" --Mdir "$check_build/$top" "${sources[@]}" >"$check_reports/${top}_build.log" 2>&1
 "$check_build/$top/V$top" >"$check_reports/${top}_test.log" 2>&1
 cat "$check_reports/${top}_test.log"
done
