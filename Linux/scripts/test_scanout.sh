#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/peripherals reports/peripherals
verilator --lint-only --top-module rv32_framebuffer_scanout rtl/rv32_framebuffer_scanout.v 2>&1 | tee reports/peripherals/scanout_lint.log
for t in peripherals_scanout_tb peripherals_scanout_fault_tb; do
  iverilog -g2012 -s "$t" -o "build/peripherals/$t.vvp" rtl/rv32_framebuffer_scanout.v "sim/$t.sv"
  vvp "build/peripherals/$t.vvp" | tee "reports/peripherals/$t.log"
done
