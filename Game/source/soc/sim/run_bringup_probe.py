#!/usr/bin/env python3
"""Snapshot the game sources and run an isolated 480p full-SoC bring-up test.

The test boots freshly built firmware on the real CPU RTL, decodes the UART
pin, checks framebuffer publication and captures the game image before/after
an A-button pulse.  Each invocation creates a new evidence directory; it does
not modify or remove prior builds.  Vendor DDR PHY and TMDS IO are modelled.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import struct
import subprocess
import sys
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
XPACK = Path.home() / "AppData/Roaming/xPacks/riscv-none-elf-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
MINGW = Path("C:/Users/user/mingw64/bin")
MSYS_BIN = Path("C:/tools/msys64/usr/bin")
VERILATOR = Path("C:/tools/msys64/mingw64/bin/verilator_bin.exe")
VERILATOR_ROOT = Path("C:/tools/msys64/mingw64/share/verilator")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], cwd: Path, env: dict[str, str], log: Path) -> None:
    print("RUN:", subprocess.list2cmdline(command), flush=True)
    with log.open("w", encoding="utf-8") as out:
        out.write("COMMAND: " + subprocess.list2cmdline(command) + "\n")
        out.flush()
        with subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True,
                              encoding="utf-8", errors="replace", bufsize=1) as proc:
            assert proc.stdout is not None
            for line in proc.stdout:
                out.write(line)
                out.flush()
                print(line, end="", flush=True)
            code = proc.wait()
        out.write(f"\nEXIT={code}\n")
    if code:
        raise RuntimeError(f"command failed with exit {code}; see {log}")


def to_mem(path: Path, data: bytes) -> None:
    if len(data) > 65536:
        raise ValueError("SRAM image exceeds 64 KiB")
    data += b"\0" * (65536 - len(data))
    words = struct.unpack("<8192Q", data)
    path.write_text("".join(f"{word:016x}\n" for word in words), encoding="ascii")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", type=int, default=180)
    parser.add_argument("--validate-only", type=Path,
                        help="recheck an existing immutable simulation evidence directory")
    parser.add_argument("--trace-writes", action="store_true")
    parser.add_argument("--reuse-sim", type=Path,
                        help="reuse a prior probe executable only when all compiled RTL/TB/C++ hashes match")
    args = parser.parse_args()
    if args.validate_only:
        return validate(args.validate_only.resolve())
    if args.frames < 1:
        parser.error("--frames must be positive")

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    out = ROOT / "build" / "bringup" / f"probe_{stamp}"
    src = out / "source"
    out.mkdir(parents=True, exist_ok=False)
    for folder in ("rtl", "sw"):
        shutil.copytree(ROOT / folder, src / folder)
    (src / "sim").mkdir()
    for name in ("build_sim.py", "tb_game_bringup.sv", "bringup_main.cpp", "run_bringup_probe.py"):
        shutil.copy2(ROOT / "sim" / name, src / "sim" / name)
    manifest = {p.relative_to(src).as_posix(): digest(p)
                for p in sorted(src.rglob("*")) if p.is_file()}
    (out / "source_sha256.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"EVIDENCE_DIR: {out}", flush=True)

    env = dict(os.environ)
    env["VERILATOR_ROOT"] = str(VERILATOR_ROOT)
    env["MAKE"] = str(MINGW / "mingw32-make.exe")
    # Verilator's generated makefile uses sh, uname, cat and xargs.  Without
    # MSYS tools mingw32-make falls back to cmd.exe and its archive step fails.
    env["PATH"] = os.pathsep.join((str(MINGW), str(MSYS_BIN), str(XPACK), env.get("PATH", "")))
    sw = src / "sw"
    arch = ["-march=rv32im_zicsr", "-mabi=ilp32", "-mcmodel=medlow", "-msmall-data-limit=0"]
    firmware = out / "game.elf"
    command = [str(XPACK / "riscv-none-elf-gcc.exe"), *arch, "-O2", "-ffreestanding",
               "-fno-builtin", "-fno-common", "-nostdlib", "-Wall", "-Wextra",
               "-Wno-unused-parameter", "-Iinclude", "-Igame", "common/start.S",
               "game/main.c", "game/game_logic.c", "game/game_render.c",
               "game/game_assets.c", "platform/soc/soc_platform.c", "-T", "common/link.ld",
               "-nostartfiles", "-Wl,--gc-sections", "-Wl,--no-relax", "-o", str(firmware)]
    run(command, sw, env, out / "firmware_build.log")
    sections = {}
    for section in ("text", "rodata", "data"):
        binary = out / f"game.{section}.bin"
        run([str(XPACK / "riscv-none-elf-objcopy.exe"), "-O", "binary",
             f"--only-section=.{section}", str(firmware), str(binary)], sw, env,
            out / f"objcopy_{section}.log")
        sections[section] = binary.read_bytes()
    to_mem(out / "game-itcm.mem", sections["text"])
    to_mem(out / "game-dtcm.mem", sections["rodata"] + sections["data"])
    print(f"FIRMWARE: text={len(sections['text'])} rodata={len(sections['rodata'])} data={len(sections['data'])}", flush=True)
    (out / "firmware_sha256.json").write_text(json.dumps(
        {p.name: digest(p) for p in (firmware, out / "game-itcm.mem", out / "game-dtcm.mem")},
        indent=2) + "\n", encoding="utf-8")

    # Independent raster reference from the same game code on the host.  A
    # completed scan or a changed picture alone does not prove valid pixels.
    host_dir = out / "host_frames"
    host_dir.mkdir()
    host_exe = out / "game_host.exe"
    run([str(MINGW / "gcc.exe"), "-O2", "-std=gnu11", "-Wall", "-Wextra",
         "-Wno-unused-parameter", "-Iinclude", "-Igame", "game/game_logic.c",
         "game/game_render.c", "game/game_assets.c", "platform/host/host_platform.c",
         "platform/host/host_main.c", "-o", str(host_exe)], sw, env, out / "host_build.log")
    run([str(host_exe), "--frames", "4000", "--dump-dir", str(host_dir)],
        out, env, out / "host_run.log")

    # Reuse the established source order, but never invoke its old build path,
    # which removes an existing guard directory.
    import importlib.util
    spec = importlib.util.spec_from_file_location("game_source_list", src / "sim" / "build_sim.py")
    assert spec and spec.loader
    listing = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(listing)
    rtl = [src / name for name in listing.SOURCES if name.startswith("rtl/")]
    obj = out / "obj"
    cmd = [str(VERILATOR), "--cc", "--exe", "--build", "-j", "2", "-DGAME_SIM",
           "--top-module", "tb_game_bringup", "-Wno-fatal", "-Wno-WIDTH", "-Wno-lint",
           "--Mdir", str(obj), "--build-jobs", "1", "-MAKEFLAGS",
           f"OPT_FAST=-O2 OPT_SLOW=-O1 PYTHON3={Path(sys.executable).as_posix()}",
           "-CFLAGS", "-O2 -DNDEBUG", "-o", "game_bringup.exe"]
    cmd += [str(p) for p in rtl] + [str(src / "sim/tb_game_bringup.sv"),
                                    str(src / "sim/bringup_main.cpp")]
    if args.reuse_sim:
        previous = args.reuse_sim.resolve()
        previous_hashes = json.loads((previous / "source_sha256.json").read_text(encoding="utf-8"))
        for path in [*rtl, src / "sim/tb_game_bringup.sv", src / "sim/bringup_main.cpp"]:
            relative = path.relative_to(src).as_posix()
            if previous_hashes.get(relative) != digest(path):
                raise RuntimeError(f"simulation reuse source mismatch: {relative}")
        previous_exe = previous / "obj/game_bringup.exe"
        obj.mkdir()
        shutil.copy2(previous_exe, obj / "game_bringup.exe")
        (out / "simulation_reuse.json").write_text(json.dumps({
            "previous_probe": str(previous), "executable_sha256": digest(previous_exe),
            "checked_compiled_source_count": len(rtl) + 2,
            "all_compiled_source_hashes_match": True}, indent=2) + "\n", encoding="utf-8")
        print("SIM_REUSE: all RTL/TB/C++ hashes match", flush=True)
    else:
        run(cmd, out, env, out / "verilator_build.log")
    # Exercise byte/halfword/word SRAM, writeback/refill, game MMIO and both
    # cached/uncached DDR paths on the very same CPU RTL before the game.
    probe_dir = out / "memory_probe"
    probe_dir.mkdir()
    probe_elf = probe_dir / "memory_probe.elf"
    run([str(XPACK / "riscv-none-elf-gcc.exe"), *arch, "-O2", "-ffreestanding",
         "-fno-builtin", "-fno-common", "-nostdlib", "-Wall", "-Wextra",
         "-Iinclude", "common/start.S", "tests/rv32_memory_probe.c", "tests/rv32_icache_probe.S", "-T", "common/link.ld",
         "-nostartfiles", "-Wl,--gc-sections", "-Wl,--no-relax", "-o", str(probe_elf)],
        sw, env, probe_dir / "firmware_build.log")
    probe_sections = {}
    for section in ("text", "rodata", "data"):
        binary = probe_dir / f"probe.{section}.bin"
        run([str(XPACK / "riscv-none-elf-objcopy.exe"), "-O", "binary",
             f"--only-section=.{section}", str(probe_elf), str(binary)], sw, env,
            probe_dir / f"objcopy_{section}.log")
        probe_sections[section] = binary.read_bytes()
    to_mem(probe_dir / "game-itcm.mem", probe_sections["text"])
    to_mem(probe_dir / "game-dtcm.mem", probe_sections["rodata"] + probe_sections["data"])
    run([str(obj / "game_bringup.exe"), "+memory_probe", "+frames=20"],
        probe_dir, env, probe_dir / "simulation.log")
    probe_log = (probe_dir / "simulation.log").read_text(encoding="utf-8")
    probe_log = re.sub(r"COVERAGE[^\r\n]*(?:\r?\n|$)", "", probe_log)
    if "RV32_MEMORY_PROBE_COMPLETE" not in probe_log or "RV32_MEMORY_FAIL" in probe_log:
        raise RuntimeError("RV32 memory probe did not pass")
    sim_cmd = [str(obj / "game_bringup.exe"), f"+frames={args.frames}"]
    if args.trace_writes:
        sim_cmd.append("+trace_writes")
    run(sim_cmd, out, env, out / "simulation.log")
    return validate(out)


def validate(out: Path) -> int:
    sources = json.loads((out / "source_sha256.json").read_text(encoding="utf-8"))
    for name, expected in sources.items():
        if digest(out / "source" / name) != expected:
            raise RuntimeError(f"snapshot source changed: {name}")
    for name, expected in json.loads((out / "firmware_sha256.json").read_text(encoding="utf-8")).items():
        if digest(out / name) != expected:
            raise RuntimeError(f"firmware changed: {name}")
    memory_log = (out / "memory_probe/simulation.log").read_text(encoding="utf-8")
    memory_log = re.sub(r"COVERAGE[^\r\n]*(?:\r?\n|$)", "", memory_log)
    if "RV32_MEMORY_PROBE_COMPLETE" not in memory_log or "RV32_MEMORY_FAIL" in memory_log:
        raise RuntimeError("RV32 memory probe did not pass")
    for marker in ("RV32_ICACHE_2WAY_OK", "RV32_FENCEI_CODE_SYNC_OK"):
        if marker not in memory_log:
            raise RuntimeError(f"missing integrated instruction-cache test: {marker}")
    host_dir = out / "host_frames"
    # CPU coverage writes share stdout with the byte-by-byte pin decoder.
    # Remove whole known coverage records, preserving every UART character.
    raw_log = (out / "simulation.log").read_text(encoding="utf-8")
    log = re.sub(r"COVERAGE[^\r\n]*(?:\r?\n|$)", "", raw_log)
    (out / "simulation_normalized.log").write_text(log, encoding="utf-8")
    if "BRINGUP_COMPLETE" not in log:
        print("RESULT: incomplete; no full displayed frame before the deadline", flush=True)
        return 1
    if "rv32_soc_Game boot" not in log or "init ok st=" not in log:
        print("RESULT: failed; expected boot and initialization UART messages missing", flush=True)
        return 1
    if "UART_FRAMING_ERROR" in log or "fatal=1" in log:
        print("RESULT: failed; UART framing error or CPU/video fatal flag", flush=True)
        return 1
    def match_fraction(actual: Path, expected: Path) -> float:
        header = b"P6\n640 360\n255\n"
        a, b = actual.read_bytes(), expected.read_bytes()
        if not a.startswith(header) or not b.startswith(header) or len(a) != len(b):
            raise ValueError("invalid or differently sized PPM raster")
        a, b = a[len(header):], b[len(header):]
        return sum(a[i:i+3] == b[i:i+3] for i in range(0, len(a), 3)) / (640*360)

    try:
        title_match = match_fraction(out / "before_a.ppm", host_dir / "host_000_title.ppm")
        game_match = match_fraction(out / "after_a.ppm", host_dir / "host_f0000_state1.ppm")
        game_match_other = match_fraction(out / "after_a_other_fb.ppm", host_dir / "host_f0000_state1.ppm")
    except (OSError, ValueError) as exc:
        print(f"RESULT: failed; raster comparison: {exc}", flush=True)
        return 1
    print(f"RASTER_MATCH: title={title_match:.6f} game={game_match:.6f} other={game_match_other:.6f}", flush=True)
    if title_match < 0.995 or game_match < 0.95 or game_match_other < 0.95:
        print("RESULT: failed; title or one of the game buffers differs from the host reference", flush=True)
        return 1
    (out / "validation.json").write_text(json.dumps({
        "validator_sha256": digest(Path(__file__)),
        "stdout_cpu_coverage_records_removed_for_uart_markers": True,
        "status": "PASS", "scope": "RTL and behavioural DDR; physical FPGA and TMDS not tested",
        "uart_boot_and_init": True, "rv32_memory_probe": "PASS", "icache_two_way_conflicts_and_fence_i": "PASS", "cpu_hz": 100000000, "two_game_framebuffers_captured": True,
        "raster_match": {"title": title_match, "game": game_match, "other": game_match_other},
        "files_sha256": {name: digest(out / name) for name in
                         ("simulation.log", "simulation_normalized.log", "before_a.ppm", "after_a.ppm", "after_a_other_fb.ppm")}
    }, indent=2) + "\n", encoding="utf-8")
    print("RESULT: UART, complete display frames, A button and both raster buffers verified", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
