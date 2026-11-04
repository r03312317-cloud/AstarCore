#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/peripherals reports/peripherals
sources=(rtl/rv32_clint.v rtl/rv32_plic.v rtl/rv32_uart.v rtl/rv32_framebuffer.v rtl/rv32_linux_peripherals.v)
iverilog -g2012 -s peripherals_tb -o build/peripherals/test.vvp "${sources[@]}" sim/peripherals_tb.sv
vvp build/peripherals/test.vvp | tee reports/peripherals/module_test.log
verilator --lint-only --top-module rv32_linux_peripherals "${sources[@]}" 2>&1 | tee reports/peripherals/lint.log
iverilog -g2012 -s peripherals_plic_tb -o build/peripherals/plic.vvp rtl/rv32_plic.v sim/peripherals_plic_tb.sv
vvp build/peripherals/plic.vvp | tee reports/peripherals/plic_test.log
