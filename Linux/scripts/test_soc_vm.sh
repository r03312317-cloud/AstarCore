#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/vm reports
CC=${RISCV_CC:-riscv64-unknown-elf-gcc}
OBJCOPY=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
result=0
for test in ${VM_TESTS:-fencei pagefault asid satp_fetch}; do
 "$CC" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -Wl,--no-relax -Isim "sim/soc_vm_${test}.S" -o "build/vm/${test}.elf"
 "$OBJCOPY" -O binary "build/vm/${test}.elf" "build/vm/${test}.bin"
 build/soc/Vrv32_linux_soc_top "build/vm/${test}.bin" 1000000 >"reports/soc_vm_${test}_uart.log" 2>"reports/soc_vm_${test}_status.log"
 python3 - "$test" <<'PY' || result=1
import sys,pathlib
name=sys.argv[1]
s=pathlib.Path(f'reports/soc_vm_{name}_uart.log').read_text()
if 'PASS\n' not in s: raise SystemExit(f'{name}: no actual UART PASS; inspect logs: {s!r}')
print(f'SOC VM {name}: PASS (real RTL UART)')
PY
done
exit "$result"
