#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build/atomic" "$ROOT/reports/atomic"
for top in atomic_tb atomic_random_tb; do
  iverilog -g2012 -s "$top" -o "$ROOT/build/atomic/$top" "$ROOT/sim/$top.sv" "$ROOT/rtl/rv32_atomic_memory.v"
  vvp "$ROOT/build/atomic/$top" | tee "$ROOT/reports/atomic/$top.log"
done
verilator --binary --timing -j "${JOBS:-2}" -Wno-fatal --top-module atomic_order_tb \
  --Mdir "$ROOT/build/atomic/order" "$ROOT/sim/atomic_order_tb.sv" "$ROOT"/rtl/*.v \
  >"$ROOT/reports/atomic/order_build.log" 2>&1
"$ROOT/build/atomic/order/Vatomic_order_tb" | tee "$ROOT/reports/atomic/order.log"
verilator --binary --timing -j "${JOBS:-2}" -Wno-fatal --top-module atomic_random_tb \
  --Mdir "$ROOT/build/atomic/random_verilator" "$ROOT/sim/atomic_random_tb.sv" "$ROOT/rtl/rv32_atomic_memory.v" \
  >"$ROOT/reports/atomic/random_build.log" 2>&1
"$ROOT/build/atomic/random_verilator/Vatomic_random_tb" | tee "$ROOT/reports/atomic/random_verilator.log"
