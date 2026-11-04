#!/usr/bin/env python3
"""Build deterministic RV32IM CoreMark ELF and 64 KiB TCM images."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import subprocess
from pathlib import Path


UPSTREAM_COMMIT = "1f483d5b8316753a742cbf5590caf5bd0a4e4777"
# 本轮默认官方 RV32 ELF GNU toolchain；旧镜像构建前缀仍可显式覆盖。
TOOL_PREFIX = "riscv32-unknown-elf-"
# 本包（soc_fourstage_PDS_CoreMark_0911）的目录布局。
UPSTREAM_DIR = ("sw", "coremark", "upstream")
PORT_DIR = ("sw", "coremark", "port")
ITCM_BASE = 0x10000000
DTCM_BASE = 0x20000000
TCM_BYTES = 65536
MARCH = "rv32im_zicsr"
MABI = "ilp32"
SAFE_FLAGS = {
    "-mbranch-cost=1", "-mbranch-cost=2", "-mbranch-cost=3",
    "-funroll-loops", "-fno-code-hoisting", "-fno-if-conversion2",
    "-flto",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def run(command: list[str], cwd: Path, toolchain: Path) -> str:
    environment = os.environ.copy()
    environment["PATH"] = str(toolchain) + os.pathsep + environment.get("PATH", "")
    result = subprocess.run(
        command, cwd=cwd, text=True, capture_output=True, env=environment
    )
    if result.returncode != 0:
        raise SystemExit(
            "CORE0_COREMARK_BUILD_CHAIN_FAIL "
            f"exit={result.returncode} command={json.dumps(command)}\n"
            f"{result.stdout}{result.stderr}"
        )
    return result.stdout


def parse_load_segments(elf_path: Path) -> tuple[int, list[tuple[int, bytes]]]:
    raw = elf_path.read_bytes()
    if raw[:4] != b"\x7fELF" or raw[4] != 1 or raw[5] != 1:
        raise SystemExit("CORE0_COREMARK_BUILD_CHAIN_FAIL elf_not_little_endian_elf32")
    entry, phoff = struct.unpack_from("<II", raw, 24)
    phentsize, phnum = struct.unpack_from("<HH", raw, 42)
    segments: list[tuple[int, bytes]] = []
    for index in range(phnum):
        offset = phoff + index * phentsize
        p_type, p_offset, p_vaddr, _p_paddr, p_filesz = struct.unpack_from(
            "<IIIII", raw, offset
        )
        if p_type == 1 and p_filesz:
            segments.append((p_vaddr, raw[p_offset : p_offset + p_filesz]))
    return entry, segments


def materialize_region(
    segments: list[tuple[int, bytes]], base: int, size: int, name: str
) -> bytes:
    highest = 0
    image = bytearray(size)
    for address, payload in segments:
        if not (base <= address < base + size):
            continue
        end = address - base + len(payload)
        if end > size:
            raise SystemExit(f"CORE0_COREMARK_BUILD_CHAIN_FAIL {name}_overflow")
        image[address - base : end] = payload
        highest = max(highest, end)
    if highest == 0:
        raise SystemExit(f"CORE0_COREMARK_BUILD_CHAIN_FAIL {name}_empty")
    highest = (highest + 3) & ~3
    return bytes(image[:highest])


def write_mem(path: Path, payload: bytes) -> int:
    words = []
    for offset in range(0, len(payload), 4):
        word = int.from_bytes(payload[offset : offset + 4].ljust(4, b"\0"), "little")
        words.append(f"{word:08x}")
    with path.open("w", encoding="ascii", newline="\n") as stream:
        stream.write("\n".join(words) + "\n")
    return len(words)


def resolve_tool(toolchain: Path, stem: str, prefix: str = TOOL_PREFIX) -> Path:
    suffix = ".exe" if os.name == "nt" else ""
    candidate = toolchain / f"{prefix}{stem}{suffix}"
    if not candidate.is_file():
        raise SystemExit(f"CORE0_COREMARK_BUILD_CHAIN_FAIL tool_missing={candidate}")
    return candidate


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--toolchain-bin", type=Path, required=True)
    parser.add_argument("--run-kind", choices=("performance", "validation"), required=True)
    parser.add_argument("--cpu-hz", type=int, choices=(27000000, 150000000, 155000000, 160000000, 170000000, 175000000, 180000000, 190000000, 200000000, 210000000), default=210000000,
                        help="Port time conversion only; must match board clock for real runs")
    parser.add_argument("--iterations", type=int, required=True)
    parser.add_argument("--optimization", choices=("O2", "O3"), default="O2")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--config-json", type=Path)
    parser.add_argument("--runtime-libgcc", type=Path,
                        help="Explicit compatible RV32IM/ILP32 libgcc.a; recorded in manifest")
    parser.add_argument("--tool-prefix", default=TOOL_PREFIX,
                        help="RISC-V 工具链可执行文件前缀")
    args = parser.parse_args()

    extra_flags = []
    if args.config_json is not None:
        config = json.loads(args.config_json.read_text(encoding="utf-8"))
        if not isinstance(config, dict) or set(config) != {"march", "extra_cflags"}:
            raise SystemExit("SI_BUILD_CONFIG_REJECT schema")
        if config["march"] != MARCH:
            raise SystemExit("SI_BUILD_ISA_REJECT")
        extra_flags = config["extra_cflags"]
        if (not isinstance(extra_flags, list)
                or any(not isinstance(flag, str) or flag not in SAFE_FLAGS for flag in extra_flags)
                or len(set(extra_flags)) != len(extra_flags)
                or sum(flag.startswith("-mbranch-cost=") for flag in extra_flags) > 1):
            raise SystemExit("SI_BUILD_FLAG_REJECT")

    root = args.repo_root.resolve()
    source = root.joinpath(*UPSTREAM_DIR)
    port = root.joinpath(*PORT_DIR)
    commit_file = source / "UPSTREAM_COMMIT"
    if not commit_file.is_file() or commit_file.read_text(encoding="ascii").strip() != UPSTREAM_COMMIT:
        raise SystemExit("CORE0_COREMARK_BUILD_CHAIN_FAIL upstream_identity")
    if args.iterations <= 0:
        raise SystemExit("CORE0_COREMARK_BUILD_CHAIN_FAIL iterations_must_be_positive")

    output = args.output_dir.resolve()
    if output.exists():
        raise SystemExit(f"SI_BUILD_OUTPUT_EXISTS {output}")
    output.mkdir(parents=True)

    prefix = args.tool_prefix
    bindir = args.toolchain_bin.resolve()
    gcc = resolve_tool(bindir, "gcc", prefix)
    readelf = resolve_tool(bindir, "readelf", prefix)
    compiler_version = run([str(gcc), "--version"], root, bindir).splitlines()[0]
    elf = output / "coremark.elf"
    map_path = output / "coremark.map"
    defines = [
        "-DPERFORMANCE_RUN=1" if args.run_kind == "performance" else "-DVALIDATION_RUN=1",
        "-DPROFILE_RUN=0",
        f"-DITERATIONS={args.iterations}",
        "-DTOTAL_DATA_SIZE=2000",
        f"-DCORE0_CPU_HZ={args.cpu_hz}u",
    ]
    flags = [
        f"-march={MARCH}",
        f"-mabi={MABI}",
        f"-{args.optimization}",
        "-ffreestanding",
        "-fno-builtin",
        "-fno-common",
        "-fno-pic",
        "-mno-relax",
        "-mcmodel=medany",
        "-msmall-data-limit=0",
        "-Wall",
        "-Wextra",
        "-Werror",
        *extra_flags,
    ]
    sources = [
        port / "start.S",
        port / "core_portme.c",
        source / "core_list_join.c",
        source / "core_main.c",
        source / "core_matrix.c",
        source / "core_state.c",
        source / "core_util.c",
    ]
    command = [
        str(gcc),
        *flags,
        *defines,
        f'-DCOMPILER_VERSION="{compiler_version}"',
        f'-DCOMPILER_FLAGS="{" ".join(flags)}"',
        f"-I{port}",
        f"-I{source}",
        "-nostdlib",
        "-nostartfiles",
        f"-T{port / 'link.ld'}",
        "-Wl,--build-id=none",
        f"-Wl,-Map={map_path}",
        *[str(path) for path in sources],
        str(args.runtime_libgcc.resolve()) if args.runtime_libgcc else "-lgcc",
        "-o",
        str(elf),
    ]
    run(command, root, bindir)
    header = run([str(readelf), "-h", str(elf)], root, bindir)
    entry, segments = parse_load_segments(elf)
    if entry != ITCM_BASE or "RISC-V" not in header:
        raise SystemExit(
            f"CORE0_COREMARK_BUILD_CHAIN_FAIL elf_identity entry=0x{entry:08x}"
        )

    itcm_mem = output / "coremark-itcm.mem"
    dtcm_mem = output / "coremark-dtcm.mem"
    itcm_words = write_mem(itcm_mem, materialize_region(segments, ITCM_BASE, TCM_BYTES, "itcm"))
    dtcm_words = write_mem(dtcm_mem, materialize_region(segments, DTCM_BASE, TCM_BYTES, "dtcm"))

    tool_files = {
        name: resolve_tool(bindir, name, prefix)
        for name in ("gcc", "ld", "objcopy", "objdump", "nm", "readelf", "size")
    }
    artifacts = {
        "coremark.elf": {"sha256": sha256(elf), "bytes": elf.stat().st_size},
        "coremark-itcm.mem": {"sha256": sha256(itcm_mem), "words": itcm_words},
        "coremark-dtcm.mem": {"sha256": sha256(dtcm_mem), "words": dtcm_words},
        "coremark.map": {"sha256": sha256(map_path), "bytes": map_path.stat().st_size},
    }
    manifest = {
        "schema": "core0-coremark-image-v1",
        "source_commit": UPSTREAM_COMMIT,
        "run_kind": args.run_kind,
        "expected_seed_crc": "E9F5" if args.run_kind == "performance" else "18F2",
        "iterations": args.iterations,
        "cpu_hz": args.cpu_hz,
        "march": MARCH,
        "mabi": MABI,
        "optimization": f"-{args.optimization}",
        "extra_cflags": extra_flags,
        "memory": {
            "itcm_base": f"0x{ITCM_BASE:08X}",
            "itcm_bytes": TCM_BYTES,
            "dtcm_base": f"0x{DTCM_BASE:08X}",
            "dtcm_bytes": TCM_BYTES,
        },
        "toolchain": {
            name: {"path": str(path), "sha256": sha256(path)}
            for name, path in tool_files.items()
        },
        "command": command,
        "compiler_version": compiler_version,
        "runtime_libgcc": ({"path": str(args.runtime_libgcc.resolve()),
                            "sha256": sha256(args.runtime_libgcc)}
                           if args.runtime_libgcc else None),
        "source_sha256": {str(path.relative_to(root)): sha256(path) for path in sources},
        "files": artifacts,
    }
    manifest_path = output / "coremark-image.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(
        "CORE0_COREMARK_BUILD_CHAIN_PASS "
        f"run={args.run_kind} entry=0x{entry:08x} "
        f"itcm_words={itcm_words} dtcm_words={dtcm_words}"
    )


if __name__ == "__main__":
    main()
