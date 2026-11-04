#!/usr/bin/env bash
# 此脚本保留本工程使用的原始启动或构建流程，具体路径和参数没有在注释版中改变。
# Build pinned upstream psplash with an explicit RV32 fbdev adaptation.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
id="${1:-01}"
case "$id" in *[!0-9]*|'') echo 'Expected a numeric build id' >&2; exit 2;; esac
work="/home/user/rv32_psplash_20261101_$id"
# sysroot 提供与目标 ABI 配套的头文件 启动对象和静态库。
sysroot=/home/user/rv32_uart_hdmi_toolchain_20261031_01/sysroot
out="$root/build_$id"
if [ -e "$work" ] || [ -e "$out" ]; then
    echo 'Refusing to overwrite build or evidence' >&2
    exit 2
fi
mkdir -p "$work" "$out"
cp -a "$root/psplash_adapted/." "$work/"
cd "$work"
gdk-pixbuf-csource --macros base-images/psplash-poky.png | sed -e 's/MY_PIXBUF/POKY_IMG/g' -e 's/guint8/uint8/g' > psplash-poky-img.h
gdk-pixbuf-csource --macros base-images/psplash-bar.png | sed -e 's/MY_PIXBUF/BAR_IMG/g' -e 's/guint8/uint8/g' > psplash-bar-img.h
cp psplash-poky-img.h psplash-bar-img.h "$out/"
defs=(-D_GNU_SOURCE '-DFONT_HEADER="radeon-font.h"' -DFONT_DEF=radeon_font -DPSPLASH_DISABLE_PROGRESS_BAR)
start=("$sysroot/lib/crt1.o" "$sysroot/lib/crti.o")
libs=(-Wl,--start-group "$sysroot/lib/libm.a" "$sysroot/lib/libc.a" "$sysroot/lib/libgcc.a" -Wl,--end-group)
clang --target=riscv32-linux-musl -march=rv32ima -mabi=ilp32 --sysroot="$sysroot" -fuse-ld=lld -O2 -Wall -Wextra "${defs[@]}" -nostdlib -static -Wl,--strip-all "${start[@]}" psplash.c psplash-fb.c psplash-console.c "${libs[@]}" "$sysroot/lib/crtn.o" -o "$out/psplash-rv32" > "$out/rv32-build.log" 2>&1
clang --target=riscv32-linux-musl -march=rv32ima -mabi=ilp32 --sysroot="$sysroot" -fuse-ld=lld -O2 -Wall -Wextra -nostdlib -static -Wl,--strip-all "${start[@]}" psplash-write.c "${libs[@]}" "$sysroot/lib/crtn.o" -o "$out/psplash-write-rv32" >> "$out/rv32-build.log" 2>&1
cc -O2 -Wall -Wextra "${defs[@]}" psplash.c psplash-fb.c psplash-console.c -o "$out/psplash-host" > "$out/host-build.log" 2>&1
# 检查产物 ELF 类型和 RISC V 属性，为实际镜像打包提供架构检查。
readelf -h -A "$out/psplash-rv32" > "$out/rv32-elf.txt"
sha256sum "$out/psplash-rv32" "$out/psplash-write-rv32" > "$out/SHA256SUMS"
echo "Built RV32 and host psplash executables."
