#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEPS=${RV32_DEPS:-$ROOT/../software_deps}
mkdir -p "$DEPS"
fetch() {
 name=$1; url=$2; sha=$3
 [ -f "$DEPS/$name" ] || curl --fail --location --retry 2 "$url" -o "$DEPS/$name.part"
 [ ! -f "$DEPS/$name.part" ] || mv "$DEPS/$name.part" "$DEPS/$name"
 printf '%s  %s\n' "$sha" "$DEPS/$name" | sha256sum -c -
}
fetch buildroot-2025.02.1.tar.xz https://buildroot.org/downloads/buildroot-2025.02.1.tar.xz a3216907e7ce1bbd38413e20b0861641b160ecc40dd7b598febb7f12984b3206
fetch linux-6.12.9.tar.xz https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.9.tar.xz 87be0360df0931b340d2bac35161a548070fbc3a8c352c49e21e96666c26aeb4
fetch opensbi-1.6.tar.gz https://codeload.github.com/riscv-software-src/opensbi/tar.gz/refs/tags/v1.6 d11702103f177a2914e94eec57ce5ed820296d874f6b6525c4482e55d71a3667
fetch lvgl-8.3.11.tar.gz https://codeload.github.com/lvgl/lvgl/tar.gz/refs/tags/v8.3.11 83b7325a4b78cbb19a39f3ac75346c8086926d7faeab5ff2d825c20da0bbdb46
for spec in buildroot-2025.02.1:tar.xz linux-6.12.9:tar.xz opensbi-1.6:tar.gz lvgl-8.3.11:tar.gz; do
 name=${spec%:*}; ext=${spec#*:}
 [ -d "$DEPS/$name" ] || tar -C "$DEPS" -xf "$DEPS/$name.$ext"
done
