#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/cache_fence reports
iverilog -g2012 -s sv32_cache_fence_tb -o build/cache_fence/test rtl/rv32_memory_system.v sim/sv32_cache_fence_tb.sv
vvp build/cache_fence/test | tee reports/sv32_cache_fence_test.log
