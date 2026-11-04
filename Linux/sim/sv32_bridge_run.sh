#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p reports sim/build_sv32_bridge
verilator --binary --timing -Wno-fatal --top-module sv32_bridge_tb --Mdir sim/build_sv32_bridge rtl/rv32_linux_memory_bridge.v rtl/rv32_sv32_mmu.v rtl/rv32_atomic_memory.v sim/sv32_bridge_tb.sv > reports/sv32_bridge_build.log 2>&1
sim/build_sv32_bridge/Vsv32_bridge_tb | tee reports/sv32_bridge_test.log
