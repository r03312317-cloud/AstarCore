#!/bin/sh
# Source this after installing tools, or supply standard tools in PATH.
if [ -n "${RV32_TOOLS:-}" ]; then
 export PATH="$RV32_TOOLS/bin:$RV32_TOOLS/local/usr/bin:$PATH"
 export VERILATOR_ROOT="$RV32_TOOLS/local/usr/share/verilator"
fi
