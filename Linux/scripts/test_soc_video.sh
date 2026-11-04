#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/video reports/peripherals
CC=${RISCV_CC:-riscv64-unknown-elf-gcc}
OBJCOPY=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
"$CC" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -Wl,--no-relax sim/soc_video.S -o build/video/video.elf
"$OBJCOPY" -O binary build/video/video.elf build/video/video.bin
verilator --cc --exe --build -j 2 -Wno-fatal --top-module rv32_linux_video_top --Mdir build/video rtl/*.v "$PWD/sim/linux_video_main.cpp" >reports/peripherals/video_build.log 2>&1
build/video/Vrv32_linux_video_top build/video/video.bin 5000000 >reports/peripherals/video_soc.log 2>reports/peripherals/video_soc_status.log
grep 'PASS CPU video ownership' reports/peripherals/video_soc.log
