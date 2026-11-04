#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/crypto reports/crypto
python3 sim/crypto_reference.py build/crypto "${LINUX_TESTMGR:-../software_deps/linux-6.12.9/crypto/testmgr.h}" | tee reports/crypto/reference.log
cp build/crypto/reference_provenance.txt build/crypto/expected_uart.txt reports/crypto/
${HOST_CC:-gcc} -O2 -std=c99 -DHOST_REFERENCE -Ibuild/crypto sim/crypto_chacha.c -o build/crypto/host
build/crypto/host > reports/crypto/host.log
diff -u build/crypto/expected_uart.txt reports/crypto/host.log
CC=${RISCV_CC:-riscv64-unknown-elf-gcc}
"$CC" -O2 -march=rv32ima_zicsr_zifencei -mabi=ilp32 -ffreestanding -fno-builtin -fno-stack-protector -msmall-data-limit=0 -nostdlib -nostartfiles -Wl,-T,sim/crypto_link.ld -Wl,--no-relax -Ibuild/crypto sim/crypto_start.S sim/crypto_chacha.c -o build/crypto/crypto.elf
${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy} -O binary build/crypto/crypto.elf build/crypto/crypto.bin
${RISCV_OBJDUMP:-riscv64-unknown-elf-objdump} -d build/crypto/crypto.elf > reports/crypto/disasm.txt
# Snapshot only: do not rebuild or overwrite the active boot simulator executable.
cp "${SOC_SIM:-build/soc/Vrv32_linux_soc_top}" build/crypto/linux_soc_sim
sha256sum build/crypto/linux_soc_sim build/crypto/crypto.elf build/crypto/crypto.bin > reports/crypto/sha256.txt
env -u RV32_UART_INPUT -u RV32_UART_SCRIPT build/crypto/linux_soc_sim build/crypto/crypto.bin "${CRYPTO_CYCLES:-4000000}" > reports/crypto/rtl_uart.log 2>reports/crypto/rtl_status.log
python3 - <<'PY'
from pathlib import Path
expected=Path('build/crypto/expected_uart.txt').read_text().splitlines()
actual=Path('reports/crypto/rtl_uart.log').read_text()
for line in expected:
    assert actual.splitlines().count(line)==1, f'actual UART missing/duplicate full answer: {line}'
assert 'CRYPTO_FAIL' not in actual
print('PASS actual RV32+cache ChaCha20: complete output vectors verified; firmware compared all2048 answer bytes')
PY
