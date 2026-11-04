#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$ROOT/build/mip_seip" "$ROOT/reports/mip_seip"
verilator --binary --timing -j "${JOBS:-2}" -Wno-fatal --top-module tb_mip_seip \
 --Mdir "$ROOT/build/mip_seip" "$ROOT/sim/privilege/tb_mip_seip.sv" "$ROOT"/rtl/*.v \
 >"$ROOT/reports/mip_seip/build.log" 2>&1
"$ROOT/build/mip_seip/Vtb_mip_seip" >"$ROOT/reports/mip_seip/run.log" 2>&1
cat "$ROOT/reports/mip_seip/run.log"
