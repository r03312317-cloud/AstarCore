#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build/terminal_echo" "$ROOT/reports/terminal_echo"
"${CXX:-g++}" -std=c++17 -O2 -Wall -Wextra -Werror "$ROOT/sim/uart_echo_pacing_test.cpp" -o "$ROOT/build/terminal_echo/test"
"$ROOT/build/terminal_echo/test" "$ROOT/sim/linux_echo_paced_commands.tsv" "$ROOT/build/terminal_echo/initial_terminal.bin" | tee "$ROOT/reports/terminal_echo/test.log"
sha256sum "$ROOT/sim/linux_echo_paced_commands.tsv" "$ROOT/build/terminal_echo/initial_terminal.bin" > "$ROOT/reports/terminal_echo/sha256.txt"
