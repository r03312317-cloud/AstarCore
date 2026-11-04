#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/seip_soc reports/peripherals
CC=${RISCV_CC:-riscv64-unknown-elf-gcc}
OBJCOPY=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
MODEL=${SOC_MODEL:-build/seip_soc/Vrv32_linux_soc_top}
LABEL=${SEIP_LABEL:-fixed}
[[ "$LABEL" =~ ^[a-zA-Z0-9_-]+$ ]]
if [[ ${SEIP_BUILD:-1} == 1 ]]; then
 verilator --cc --exe --build -j "${BUILD_JOBS:-2}" -Wno-fatal --top-module rv32_linux_soc_top --Mdir build/seip_soc rtl/*.v "$PWD/sim/linux_soc_main.cpp" >reports/peripherals/seip_soc_build.log 2>&1
fi
"$CC" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -Wl,--no-relax sim/soc_seip_rmw.S -o build/seip_soc/test.elf
"$OBJCOPY" -O binary build/seip_soc/test.elf build/seip_soc/test.bin
sha256sum "$MODEL" sim/soc_seip_rmw.S >"reports/peripherals/seip_${LABEL}_inputs.sha256"
"$MODEL" build/seip_soc/test.bin 800000 >"reports/peripherals/seip_${LABEL}_uart.log" 2>"reports/peripherals/seip_${LABEL}_status.log"
python3 - "$LABEL" "${SEIP_EXPECT:-PASS}" <<'PY'
import pathlib,sys,re
label,expected=sys.argv[1:]
assert expected in ('PASS','FAIL')
s=pathlib.Path(f'reports/peripherals/seip_{label}_uart.log').read_text()
# Core diagnostic printf shares stdout and may interleave serial characters.
s=re.sub(r'COVERAGE[^\n]*\n','',s)
assert f'SEIP PERIPHERAL {expected}' in s,s
assert f"SEIP PERIPHERAL {'FAIL' if expected=='PASS' else 'PASS'}" not in s,s
print(f'SEIP peripheral-driven actual RTL regression: observed {expected} ({label}); UART TX-ready -> PLIC S -> mip RMW -> UART off/claim/complete.')
PY
