#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build/uart_terminal" "$ROOT/reports/uart_terminal"
"${CXX:-g++}" -std=c++17 -O2 -Wall -Wextra -Werror "$ROOT/sim/uart_terminal_test.cpp" -o "$ROOT/build/uart_terminal/test"
printf 'A\n' > "$ROOT/build/uart_terminal/legacy.bin"
printf '%s\t%s\n' 'login:' 'root\n' > "$ROOT/build/uart_terminal/staged.tsv"
"$ROOT/build/uart_terminal/test" "$ROOT/build/uart_terminal/legacy.bin" "$ROOT/build/uart_terminal/staged.tsv" | tee "$ROOT/reports/uart_terminal/test.log"
"${CXX:-g++}" -std=c++17 -O2 -Wall -Wextra -Werror "$ROOT/sim/uart_terminal_checkpoint_test.cpp" -o "$ROOT/build/uart_terminal/checkpoint_test"
"$ROOT/build/uart_terminal/checkpoint_test" | tee "$ROOT/reports/uart_terminal/checkpoint_test.log"
