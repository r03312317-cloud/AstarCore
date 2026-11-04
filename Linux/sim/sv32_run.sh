#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p reports sim/build_sv32
verilator --binary --timing -Wno-fatal --top-module sv32_tb --Mdir sim/build_sv32 rtl/rv32_sv32_mmu.v sim/sv32_tb.sv > reports/sv32_build.log 2>&1
sim/build_sv32/Vsv32_tb | tee reports/sv32_test.log
