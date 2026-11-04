#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$ROOT/build/counter_matrix" "$ROOT/reports/counter_matrix"
verilator --binary --timing -j "${JOBS:-2}" -Wno-fatal --top-module tb_counter_matrix \
 --Mdir "$ROOT/build/counter_matrix" "$ROOT/sim/privilege/tb_counter_matrix.sv" "$ROOT"/rtl/*.v \
 >"$ROOT/reports/counter_matrix/build.log" 2>&1
"$ROOT/build/counter_matrix/Vtb_counter_matrix" >"$ROOT/reports/counter_matrix/run.log" 2>&1
tail -5 "$ROOT/reports/counter_matrix/run.log"
