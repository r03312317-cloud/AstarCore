#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/timer_rate reports/peripherals
CC=${RISCV_CC:-riscv64-unknown-elf-gcc}
OBJCOPY=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
MODEL=${SOC_MODEL:-build/soc/Vrv32_linux_soc_top}
test -x "$MODEL"
"$CC" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -Wl,--no-relax sim/soc_timer_rate.S -o build/timer_rate/timer.elf
"$OBJCOPY" -O binary build/timer_rate/timer.elf build/timer_rate/timer.bin
sha256sum "$MODEL" sim/soc_timer_rate.S > reports/peripherals/timer_rate_inputs.sha256
"$MODEL" build/timer_rate/timer.bin 4500000 >reports/peripherals/timer_rate_uart.log 2>reports/peripherals/timer_rate_status.log
python3 - <<'PY'
import pathlib,re
s=pathlib.Path('reports/peripherals/timer_rate_uart.log').read_text()
m=re.search(r'TIMER PASS count/min/max/elapsed=([0-9a-f]{8}) ([0-9a-f]{8}) ([0-9a-f]{8}) ([0-9a-f]{8})\n',s)
assert m and 'TIMER FAIL' not in s,s
count,lo,hi,total=(int(x,16) for x in m.groups())
assert count==32 and 1000<=lo<=hi<=1500 and 32000<=total<=48000
print(f'PASS actual RTL M timer -> S STIP -> M ecall rearm: {count} interrupts; min={lo}, max={hi}, elapsed={total} mtime ticks; nominal period=1000, 1 MHz mtime. Not a Linux boot assertion.')
PY
