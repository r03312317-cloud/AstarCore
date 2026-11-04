#!/usr/bin/env bash
# 此脚本保留本工程使用的原始启动或构建流程，具体路径和参数没有在注释版中改变。
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
work=/home/user/rv32_compact_gui_20261031_03
previous=/home/user/rv32_uart_hdmi_toolchain_20261031_01
if [ -e "$work" ]; then echo 'Refusing to overwrite GUI build' >&2; exit 2; fi
mkdir -p "$work/src" "$work/build"
cp "$root/gui_v3/main.c" "$root/gui_v3/lv_conf.h" "$root/gui_v3/generated_labels.c" "$root/gui_v3/Makefile" "$work/src/"
# Frozen LVGL object files were built from the same LVGL sources and lv_conf.h.
# Reuse copies only, never modify the prior build or its inputs.
cp -a "$previous/gui_rv32_01/build/lvgl" "$work/build/"
lvgl="$previous/gui_rv32_01/lvgl-8.3.11"
# sysroot 提供与目标 ABI 配套的头文件 启动对象和静态库。
sysroot="$previous/sysroot"
# 交叉编译目标为 riscv32 Linux musl 和 ilp32 ABI，不是 Windows 本机程序。
compiler="clang --target=riscv32-linux-musl -march=rv32ima -mabi=ilp32 --sysroot=$sysroot -fuse-ld=lld"
start="$sysroot/lib/crt1.o $sysroot/lib/crti.o"
libs="-Wl,--start-group $sysroot/lib/libm.a $sysroot/lib/libc.a $sysroot/lib/libgcc.a -Wl,--end-group"
# 在新工作目录编译用户程序，原版 LVGL 对象只复制复用，保留其来源。
make -C "$work/src" -j4 LVGL_DIR="$lvgl" BUILD="$work/build" \
    CC="$compiler" LDFLAGS='-nostdlib -static -Wl,--strip-all' CRTBEGIN="$start" LDLIBS="$libs" CRTEND="$sysroot/lib/crtn.o" \
    > "$root/gui_v3/build_rv32.log" 2>&1
# 检查产物 ELF 类型和 RISC V 属性，为实际镜像打包提供架构检查。
readelf -h -A "$work/build/rv32-gui" > "$root/gui_v3/rv32_elf.txt"
cp "$work/build/rv32-gui" "$root/gui_v3/rv32-gui-rv32-stripped"
sha256sum "$root/gui_v3/rv32-gui-rv32-stripped"
