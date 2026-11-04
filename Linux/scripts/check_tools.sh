#!/bin/sh
set -eu
verilator --version
iverilog -V 2>&1 | head -n 3
${CROSS_COMPILE:-riscv64-unknown-elf-}gcc --version | head -n 1
${CROSS_COMPILE:-riscv64-unknown-elf-}as --version | head -n 1
python3 --version
