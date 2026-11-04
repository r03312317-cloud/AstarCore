#!/bin/bash
# Optional local, unprivileged Debian amd64 tools. No system installation.
set -euo pipefail
ROOT="${RV32_TOOLS:-$PWD/.tools}"
mkdir -p "$ROOT/debs" "$ROOT/local" "$ROOT/bin"
fetch(){ local name="$1" url="$2"; test -s "$ROOT/debs/$name" || curl --fail --location --retry 2 "$url" -o "$ROOT/debs/$name"; dpkg-deb -x "$ROOT/debs/$name" "$ROOT/local"; }
fetch verilator.deb https://deb.debian.org/debian/pool/main/v/verilator/verilator_5.032-1+b2_amd64.deb
fetch iverilog.deb https://deb.debian.org/debian/pool/main/i/iverilog/iverilog_12.0-2+b1_amd64.deb
fetch gcc-riscv.deb https://deb.debian.org/debian/pool/main/g/gcc-riscv64-unknown-elf/gcc-riscv64-unknown-elf_14.2.0+19_amd64.deb
fetch binutils-riscv.deb https://deb.debian.org/debian/pool/main/b/binutils-riscv64-unknown-elf/binutils-riscv64-unknown-elf_2.44-3+7+b1_amd64.deb
cat > "$ROOT/bin/iverilog" <<WRAP
#!/bin/sh
exec "$ROOT/local/usr/bin/iverilog" -B "$ROOT/local/usr/lib/x86_64-linux-gnu/ivl" "\$@"
WRAP
chmod +x "$ROOT/bin/iverilog"
cat > "$ROOT/env.sh" <<ENV
export RV32_TOOLS="$ROOT"
export PATH="$ROOT/bin:$ROOT/local/usr/bin:\$PATH"
export VERILATOR_ROOT="$ROOT/local/usr/share/verilator"
ENV
sha256sum "$ROOT"/debs/*.deb > "$ROOT/downloaded_sha256.txt"
echo "Source $ROOT/env.sh then run scripts/check_tools.sh"
