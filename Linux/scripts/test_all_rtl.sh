#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p reports
status=0
run(){ printf '\n=== %s ===\n' "$*"; if "$@"; then echo PASS; else status=1; echo FAIL; fi; }
run ./sim/privilege/run.sh
run ./sim/privilege/run_mip_seip.sh
run ./sim/privilege/run_counter_matrix.sh
run ./sim/sv32_run.sh
run ./sim/sv32_bridge_run.sh
run ./sim/sv32_cache_fence_run.sh
run ./scripts/test_peripherals.sh
run ./scripts/test_scanout.sh
run ./scripts/test_atomic.sh
run ./scripts/build_soc_sim.sh
run ./scripts/test_soc_vm.sh
run ./scripts/test_soc_seip_rmw.sh
run ./scripts/test_soc_video.sh
run ./scripts/test_soc_timer_rate.sh
run ./scripts/test_soc_crypto.sh
run ./scripts/test_uart_terminal.sh
run ./scripts/test_uart_echo_pacing.sh
run python3 ./scripts/test_validate_linux_scanout.py
run python3 ./scripts/test_local_utilities.py
exit "$status"
