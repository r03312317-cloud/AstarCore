#!/usr/bin/env python3
"""Package the checked 2026-10-31 game candidate without touching old builds.

The archive contains the working sources, the matching SRAM bitstream and
firmware, and selected original verification evidence.  Output names contain
microseconds and are created exclusively; existing archives are never replaced.
"""
from __future__ import annotations

from datetime import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

from program_game_sram import qualify

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "build/bringup/probe_20261031_135219_203459"
RUN = PROBE / "source/build/pds/run_20261031_135236"
OUT = ROOT.parent / "deliverables"
PREFIX = "rv32_soc_Game/"
EXPECTED_BIT = "791b601db36d4dbc16c3664ee622e9d09cc6c26d030847d19ae1a7139b7aa47b"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    checked = qualify(PROBE.resolve(), RUN.resolve())
    if checked["sha256"] != EXPECTED_BIT:
        raise RuntimeError("the candidate bitstream changed")

    # The bitstream was produced from the frozen snapshot.  Fail instead of
    # combining it with later RTL/firmware edits in the working tree.
    frozen = PROBE / "source"
    expected = json.loads((PROBE / "source_sha256.json").read_text(encoding="utf-8"))
    for name, digest in expected.items():
        current = ROOT / name
        if not current.is_file() or sha(current.read_bytes()) != digest:
            raise RuntimeError(f"working source differs from candidate: {name}")
    pds_differences = []
    for path in sorted((frozen / "pds").rglob("*")):
        if not path.is_file() or "__pycache__" in path.parts:
            continue
        rel = path.relative_to(frozen)
        current = ROOT / rel
        if not current.is_file() or sha(current.read_bytes()) != sha(path.read_bytes()):
            pds_differences.append(rel.as_posix())
    if pds_differences != ["pds/flow.py"]:
        raise RuntimeError(f"unexpected PDS source changes: {pds_differences}")

    files: dict[str, Path] = {}

    def add(name: str, path: Path) -> None:
        key = PurePosixPath(name).as_posix()
        if key.startswith("/") or ".." in PurePosixPath(key).parts or key in files:
            raise RuntimeError(f"invalid or duplicate archive path: {key}")
        if not path.is_file():
            raise FileNotFoundError(path)
        files[key] = path

    add("README.md", ROOT / "README.md")
    for folder in ("rtl", "pds", "sw", "sim", "docs", "tools"):
        for path in sorted((ROOT / folder).rglob("*")):
            rel = path.relative_to(ROOT)
            if not path.is_file() or "__pycache__" in rel.parts or path.suffix == ".pyc":
                continue
            if rel.as_posix() == "tools/heavy_compute.lock":
                continue
            add(rel.as_posix(), path)

    add("release/game_board_top.sbit", Path(checked["bitstream"]))
    for name in ("game.elf", "game-itcm.mem", "game-dtcm.mem"):
        add(f"build/sw/device/{name}", PROBE / name)

    ev = "evidence/20261031"
    for name in ("validation.json", "qualification_preboard.json", "simulation.log",
                 "host_run.log", "source_sha256.json", "pds_source_sha256.json",
                 "firmware_sha256.json", "firmware_build.log", "before_a.png",
                 "after_a.png", "before_a.ppm", "after_a.ppm", "after_a_other_fb.ppm"):
        add(f"{ev}/simulation/{name}", PROBE / name)
    for name in ("host_000_title.ppm", "host_f0000_state1.ppm"):
        add(f"{ev}/simulation/host_frames/{name}", PROBE / "host_frames" / name)
    for name in ("run.tcl", "sources.json", "pds.log"):
        add(f"{ev}/pds/{name}", RUN / name)
    add(f"{ev}/pds/flow_at_build.py", frozen / "pds/flow.py")
    report = RUN / "prj_tasks/pnr_1/report_timing/report_db"
    for name in ("check_timing_summary.db", "report_timing_clock_summary.db",
                 "report_timing_fmax.db"):
        add(f"{ev}/pds/timing/{name}", report / name)
    for corner in ("fast", "slow"):
        for kind in ("setup", "hold", "recovery", "removal", "mpw"):
            name = f"report_timing_{corner}_{kind}.db"
            add(f"{ev}/pds/timing/{name}", report / name)
    for src, dst in (
        (ROOT / "build/bringup/fabric_test_20261031_1341/test.log", "fabric_test.log"),
        (ROOT / "build/bringup/double_buffer_after_20261031/result.log", "double_buffer.log"),
        (ROOT / "build/bringup/host_inputs_only_20261031/run.log", "host_inputs_only.log"),
        (ROOT / "build/bringup/host_inputs_only_20261031/host_main_inputs_only.c", "host_main_inputs_only.c"),
        (ROOT / "build/bringup/fast_add_native_probe_20261031/gate_result.log", "fast_add_gate.log"),
        (ROOT / "build/bringup/if_router_native_probe_20261031/gate_result.log", "if_router_gate.log"),
    ):
        add(f"{ev}/tests/{dst}", src)
    for name in ("scan.log", "result.json"):
        add(f"{ev}/board_failed/{name}", ROOT / "build/bringup/board_20261031_142621_960677" / name)

    note = f"""# rv32_soc_Game 工程交付说明（候选版）

此包包含工程源码、PDS IP 与约束、匹配的固件初始化文件、已生成位流和验证证据。
该候选已完成仿真和 PDS 实现，**尚未完成实体板验收**：首次 JTAG 扫描未识别到 FPGA，未下载。

- `release/game_board_top.sbit` 是 SRAM 演示位流，SHA-256：`{EXPECTED_BIT}`。
- `build/sw/device/` 中的 ELF、ITCM/DTCM 初始化文件与上述位流构建一致。
- `rtl/`、`sw/`、`sim/`、`pds/`、`docs/`、`tools/` 是完整工程工作源码。
- `evidence/20261031/` 有关键仿真、正式时序摘要、PDS 原生日志与首次板卡扫描记录；大型构建缓存和中间网表未放入本包。
- `SHA256SUMS.txt` 逐文件记录包内文件的校验值；同目录的 `.zip.sha256` 校验整个压缩包。

## 构建与使用

器件为 PG2L200H-6FBB676，使用 PDS 2025.2；本机 PDS 路径见 `pds/flow.py`。解压后，在工程目录执行 `python pds/flow.py full --direct`，会根据已附带的 `build/sw/device/*.mem` 在新的 `build/pds/run_*` 目录生成 PDS 工程及位流。修改固件后需先用本机 RISC-V 工具链重新生成两个 `.mem`，再重新实现。

如需先做 RTL 仿真，运行 `python sim/run_bringup_probe.py --frames 120 --trace-writes`；该脚本和 Makefile 引用了原机器的 PDS、RISC-V、MinGW、Verilator 路径，在其他机器上请按实际安装位置调整。`tools/program_game_sram.py` 依赖原工作区的板卡锁和完整候选快照，不是此精简包独立的烧录入口；可在原工作区使用，或在板卡独占且确认器件后用 PDS 配置工具选择本包的 `.sbit` 下载至 SRAM。

视频为 HDMI 720×480p60，游戏图像 640×360 居中。USER_BUTTON0 为 A/确认，USER_BUTTON1～4 为上、下、左、右。上电/下载时勿按 A，以免进入诊断模式。

PDS 快/慢角 setup、hold、recovery、removal、MPW 的报告失败端点均为 0，最紧 setup 0.803 ns、hold 0.041 ns；仍有 39 个输入和 79 个输出缺少 I/O 延迟约束。实际 DDR、HDMI、按键及稳定性必须在板卡上检查。PDS 日志提示本机许可证约 3 天后失效。

历史日志和 `docs/09_20261031_游戏上板排障.md` 中的绝对路径或 `build/bringup` 路径指原工作区，压缩包只选取关键证据。包内 PDS 启动脚本相对构建时仅调整了资源保护器的默认执行方式及说明；构建当时的原版脚本保留在 `evidence/20261031/pds/flow_at_build.py`。
""".encode("utf-8")

    OUT.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    target = OUT / f"rv32_soc_Game_Candidate_{stamp}.zip"
    manifest: dict[str, dict[str, object]] = {}
    with zipfile.ZipFile(target, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name, path in sorted(files.items()):
            content = path.read_bytes()
            z.writestr(PREFIX + name, content)
            manifest[name] = {"sha256": sha(content), "bytes": len(content)}
        z.writestr(PREFIX + "交付说明.md", note)
        manifest["交付说明.md"] = {"sha256": sha(note), "bytes": len(note)}
        sums = "".join(f"{manifest[n]['sha256']}  {n}\n" for n in sorted(manifest)).encode("utf-8")
        z.writestr(PREFIX + "SHA256SUMS.txt", sums)

    with zipfile.ZipFile(target) as z:
        bad = z.testzip()
        if bad:
            raise RuntimeError(f"ZIP CRC failure: {bad}")
        for name, item in manifest.items():
            if sha(z.read(PREFIX + name)) != item["sha256"]:
                raise RuntimeError(f"ZIP content hash mismatch: {name}")
        if z.read(PREFIX + "SHA256SUMS.txt") != sums:
            raise RuntimeError("ZIP manifest mismatch")

    digest = sha(target.read_bytes())
    sidecar = target.with_suffix(target.suffix + ".sha256")
    with sidecar.open("x", encoding="ascii") as f:
        f.write(f"{digest}  {target.name}\n")
    metadata = target.with_suffix(".manifest.json")
    with metadata.open("x", encoding="utf-8") as f:
        json.dump({"archive": target.name, "archive_sha256": digest,
                   "archive_bytes": target.stat().st_size, "files": manifest}, f,
                  ensure_ascii=False, indent=2)
        f.write("\n")
    print(json.dumps({"archive": str(target), "sha256": digest,
                      "bytes": target.stat().st_size, "files": len(manifest),
                      "sidecar": str(sidecar), "manifest": str(metadata)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
