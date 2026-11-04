#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$ROOT/build/privilege" "$ROOT/reports/privilege"
verilator --binary --timing -j "${JOBS:-2}" -Wno-fatal --top-module tb_privilege \
 --Mdir "$ROOT/build/privilege" "$ROOT/sim/privilege/tb_privilege.sv" "$ROOT"/rtl/*.v \
 >"$ROOT/reports/privilege/build.log" 2>&1
"$ROOT/build/privilege/Vtb_privilege" >"$ROOT/reports/privilege/run.log" 2>&1
cat "$ROOT/reports/privilege/run.log"
