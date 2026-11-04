#!/usr/bin/env python3
"""Convert the firmware ELF into the two TCM init files used by the bitstream.

The TCMs are inferred block RAMs initialised with $readmemh(): one 64-bit word
per line, no @address records, because the RAM array index is the CPU address
minus the TCM base.  .text goes to ITCM; .rodata and .data form the DTCM image;
.bss is cleared by start.S and is therefore not part of it.
"""
from __future__ import annotations

import struct
import subprocess
import sys
from pathlib import Path

OBJCOPY_CANDIDATES = [
    "riscv-none-elf-objcopy",
    str(Path.home() / "AppData/Roaming/xPacks/riscv-none-elf-gcc/"
        "xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objcopy.exe"),
]


def find_objcopy(explicit: str | None) -> str:
    if explicit:
        return explicit
    for cand in OBJCOPY_CANDIDATES:
        if Path(cand).exists():
            return cand
    raise SystemExit("riscv-none-elf-objcopy not found; pass it as argv[3]")


def section_bytes(elf: Path, objcopy: str, name: str) -> bytes:
    out = elf.with_suffix(f".{name}.bin")
    subprocess.run([objcopy, "-O", "binary", f"--only-section={name}", str(elf), str(out)],
                   check=True)
    data = out.read_bytes()
    out.unlink()
    return data


def words(data: bytes) -> list[int]:
    if len(data) > 65536:
        raise ValueError("SRAM image exceeds 64 KiB")
    data = data + b"\x00" * (65536 - len(data))
    return list(struct.unpack("<8192Q", data))


def write_mem(path: Path, data: bytes):
    ws = words(data)
    if not ws:
        ws = [0]
    path.write_text("".join(f"{w:016x}\n" for w in ws), encoding="ascii")


def symbol_value(elf: Path, objcopy: str, name: str) -> int | None:
    """Read one symbol's address so the generated image can be cross-checked
    against the linker map; objcopy lives next to nm, so reuse its directory."""
    nm = Path(objcopy).with_name(Path(objcopy).name.replace("objcopy", "nm"))
    if not nm.exists():
        return None
    out = subprocess.run([str(nm), str(elf)], capture_output=True, text=True)
    for line in out.stdout.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == name:
            return int(parts[0], 16)
    return None


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    elf = Path(sys.argv[1])
    itcm_out = Path(sys.argv[2])
    dtcm_out = Path(sys.argv[3])
    objcopy = find_objcopy(sys.argv[4] if len(sys.argv) > 4 else None)

    text = section_bytes(elf, objcopy, ".text")
    rodata = section_bytes(elf, objcopy, ".rodata")
    data = section_bytes(elf, objcopy, ".data")

    # Preserve the code/data bank addresses; RV32 fills eight 64-bit beats.
    itcm = text
    dtcm = rodata + data
    write_mem(itcm_out, itcm)
    write_mem(dtcm_out, dtcm)
    print(f"ITCM {len(itcm):6d} bytes ({len(words(itcm))} words)")
    print(f"DTCM {len(dtcm):6d} bytes ({len(words(dtcm))} words) "
          f"[rodata {len(rodata)} + data {len(data)}]")
    if len(itcm) > 64 * 1024:
        print("ERROR: ITCM overflow", file=sys.stderr)
        return 1
    if len(dtcm) > 64 * 1024 - 4096:
        print("ERROR: DTCM overflow (needs room for a 4 KiB stack)", file=sys.stderr)
        return 1
    bss_start = symbol_value(elf, objcopy, "__bss_start")
    expected = 0x20000000 + len(dtcm)
    if bss_start is not None and bss_start != expected:
        print(f"ERROR: __bss_start=0x{bss_start:08x} but the DTCM image ends at "
              f"0x{expected:08x}; the .mem layout would not match the linker map",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
