#!/usr/bin/env python3
"""Qualify a frozen game build and configure the shared FPGA SRAM once.

The project-wide board lock is held across JTAG and UART use.  This program
never writes configuration Flash.  Screen appearance and buttons still need
to be checked on the physical board by the operator.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import msvcrt
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = next((p for p in ROOT.parents if (p / "PERMANENT_RETENTION.json").is_file()), ROOT.parent)
LOCK = PROJECT / "docs/BOARD_RESOURCE.lock"
STATUS = PROJECT / "docs/BOARD_RESOURCE_STATUS.md"
PDS_BIN = Path("D:/PDS_2025.2-ads-win64/pango/PDS_2025.2-ads/bin")


def utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def port_in_use(port: int) -> bool:
    with socket.socket() as sock:
        sock.settimeout(0.3)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def compare_ppm(actual: Path, expected: Path) -> float:
    header = b"P6\n640 360\n255\n"
    a, b = actual.read_bytes(), expected.read_bytes()
    require(a.startswith(header) and b.startswith(header) and len(a) == len(b),
            f"invalid raster pair: {actual} / {expected}")
    a, b = a[len(header):], b[len(header):]
    return sum(a[i:i+3] == b[i:i+3] for i in range(0, len(a), 3)) / (640*360)


def qualify(probe: Path, pds_run: Path) -> dict:
    source = probe / "source"
    require(pds_run.is_relative_to(source / "build/pds"), "PDS run is outside the supplied snapshot")
    expected_sources = json.loads((probe / "source_sha256.json").read_text(encoding="utf-8"))
    for name, digest in expected_sources.items():
        require(sha(source / name) == digest, f"snapshot source changed: {name}")
    for item in json.loads((probe / "pds_source_sha256.json").read_text(encoding="utf-8-sig")):
        require(sha(Path(item["Path"])) == item["Hash"].lower(), f"PDS source changed: {item['Path']}")
    for name in ("game-itcm.mem", "game-dtcm.mem"):
        require(sha(probe / name) == sha(pds_run / name), f"PDS firmware differs: {name}")
    require("GAME_FLOW_COMPLETE" in (pds_run / "pds.log").read_text(encoding="utf-8", errors="replace"),
            "PDS flow did not complete")
    sim = (probe / "simulation.log").read_text(encoding="utf-8", errors="replace")
    sim = re.sub(r"COVERAGE[^\r\n]*(?:\r?\n|$)", "", sim)
    for marker in ("rv32_soc_Game boot", "init ok st=", "BRINGUP_COMPLETE"):
        require(marker in sim, f"missing simulation marker: {marker}")
    require("fatal=1" not in sim and "UART_FRAMING_ERROR" not in sim,
            "simulation recorded a fatal condition or UART framing error")
    if (source / "rtl/rv32/core").is_dir():
        imported = json.loads((ROOT / "docs/cpu_rv32_import_manifest.json").read_text(encoding="utf-8"))
        for name, digest in imported["copied_cpu_sha256"].items():
            require(sha(source / "rtl/rv32/core" / name) == digest,
                    f"RV32 donor RTL differs: {name}")
        memory_log = (probe / "memory_probe/simulation.log").read_text(encoding="utf-8")
        memory_log = re.sub(r"COVERAGE[^\r\n]*(?:\r?\n|$)", "", memory_log)
        require("RV32_MEMORY_PROBE_COMPLETE" in memory_log and "RV32_MEMORY_FAIL" not in memory_log,
                "RV32 memory probe did not pass")
        if imported.get("integration", {}).get("i_cache_ways") == 2:
            for marker in ("RV32_ICACHE_2WAY_OK", "RV32_FENCEI_CODE_SYNC_OK"):
                require(marker in memory_log, f"I2W2 integrated CPU test missing: {marker}")
    host = probe / "host_frames"
    raster = {
        "title": compare_ppm(probe / "before_a.ppm", host / "host_000_title.ppm"),
        "game_fb_a": compare_ppm(probe / "after_a.ppm", host / "host_f0000_state1.ppm"),
        "game_fb_b": compare_ppm(probe / "after_a_other_fb.ppm", host / "host_f0000_state1.ppm"),
    }
    require(raster["title"] >= 0.995 and min(raster["game_fb_a"], raster["game_fb_b"]) >= 0.95,
            f"simulation raster mismatch: {raster}")

    report = pds_run / "prj_tasks/pnr_1/report_timing/report_db"
    timing = {}
    for corner in ("fast", "slow"):
        for kind in ("setup", "hold", "recovery", "removal", "mpw"):
            name = f"report_timing_{corner}_{kind}.db"
            table = ET.parse(report / name).getroot().find("table")
            require(table is not None, f"missing timing table: {name}")
            rows = [[d.text or "" for d in row.findall("data")] for row in table.findall("row")]
            require(rows, f"empty timing table: {name}")
            slack_col, fail_col = ((1, 3) if kind == "mpw" else (2, 4))
            slacks = [float(row[slack_col]) for row in rows]
            failures = sum(int(row[fail_col]) for row in rows)
            timing[f"{corner}_{kind}"] = {"worst_slack_ns": min(slacks), "failing_endpoints": failures}
            require(min(slacks) >= 0 and failures == 0, f"timing violation in {name}")
    check = ET.parse(report / "check_timing_summary.db").getroot().find("table")
    require(check is not None, "missing check_timing_summary")
    checks = {r.findtext("data", ""): [d.text or "" for d in r.findall("data")][1]
              for r in check.findall("row") if len(r.findall("data")) >= 2}
    require(checks.get("no_clock") == "0", "clock pins without an assigned clock")
    bit = pds_run / "prj_tasks/pnr_1/generate_bitstream/game_board_top.sbit"
    require(bit.is_file() and bit.stat().st_size > 0, "bitstream missing")
    return {"bitstream": str(bit), "sha256": sha(bit), "raster_match": raster,
            "timing": timing, "check_timing": checks,
            "scope": "PDS timed paths only; input/output delay warnings are recorded separately"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--pds-run", type=Path, required=True)
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--jtag-port", type=int, default=65420,
                        help="local JTAG server port; choose another if Windows reserves the default")
    parser.add_argument("--qualify-only", action="store_true",
                        help="validate hashes/simulation/timing/bitstream without using the board")
    parser.add_argument("--report", type=Path, help="write the qualification JSON here")
    args = parser.parse_args()
    probe, pds_run = args.probe.resolve(), args.pds_run.resolve()
    require(args.seconds > 0, "capture time must be positive")
    require(1024 <= args.jtag_port <= 65535, "JTAG port must be between 1024 and 65535")
    qualification = qualify(probe, pds_run)
    print("QUALIFIED", json.dumps(qualification, ensure_ascii=False), flush=True)
    if args.report:
        args.report.write_text(json.dumps(qualification, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.qualify_only:
        return 0
    out = ROOT / "build/bringup" / datetime.now().strftime("board_%Y%m%d_%H%M%S_%f")
    out.mkdir(parents=True, exist_ok=False)
    (out / "qualification.json").write_text(json.dumps(qualification, indent=2) + "\n", encoding="utf-8")
    result = {"started_utc": utc(), "status": "starting", "flash_written": False,
              "visual_and_buttons_verified": False, "evidence": str(out),
              "bitstream_sha256": qualification["sha256"], "jtag_port": args.jtag_port}
    def save() -> None:
        (out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    save()
    print("BOARD_EVIDENCE:", out, flush=True)

    lock = LOCK.open("r+b")
    claimed = locked = False
    server = serial_port = server_log = cfg = None
    try:
        lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        locked = True
        require(not port_in_use(args.jtag_port), "JTAG server is already in use by another session")
        import serial
        from serial.tools import list_ports
        ports = [p for p in list_ports.comports() if p.device.upper() == "COM14"]
        require(len(ports) == 1 and ports[0].vid == 0x10c4 and ports[0].pid == 0xea60,
                "expected CP210x COM14 is absent or ambiguous")
        serial_port = serial.Serial(port=None, baudrate=115200, timeout=0.1,
                                    bytesize=8, parity="N", stopbits=1)
        serial_port.port = "COM14"
        serial_port.dtr = False
        serial_port.rts = False
        serial_port.open()
        previous = STATUS.read_text(encoding="utf-8")
        (out / "previous_board_status.md").write_text(previous, encoding="utf-8")
        STATUS.write_text(f"# Board resource lease\n\nUTC {utc()}; current owner: rv32_soc_Game; "
                          f"SRAM-only game demo; evidence {out}.\n\n" + previous, encoding="utf-8")
        claimed = True
        flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
        server_log = (out / "jtag_server.log").open("w", encoding="utf-8")
        server = subprocess.Popen([str(PDS_BIN / "cdt_js.exe"), "-port", str(args.jtag_port), "-work_dir", str(out)],
                                  stdout=server_log, stderr=subprocess.STDOUT, creationflags=flags)
        for _ in range(60):
            if port_in_use(args.jtag_port):
                break
            require(server.poll() is None, "JTAG server exited before listening")
            time.sleep(0.1)
        else:
            raise RuntimeError("JTAG server did not start")
        common = ("cfg_set_tcl_break -flag true\n"
                  f"cfg_connect -ip 127.0.0.1 -port {args.jtag_port}\n"
                  "cfg_set_cable_property -index 0 -freq 5MHz\n"
                  "cfg_scan_chain\n")
        scan = out / "scan.tcl"
        scan.write_text(common + "cfg_read_device_property -mode 0 -device_index 0\n"
                        "cfg_disconnect\n", encoding="utf-8")
        checked = subprocess.run([str(PDS_BIN / "cdt_cfg_shell.exe"), "-file", str(scan),
                                  "-work_dir", str(out)], stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=60, creationflags=flags)
        scan_text = checked.stdout.decode(errors="replace")
        (out / "scan.log").write_text(scan_text, encoding="utf-8")
        identity = re.search(r"Executing\s*:\s*cfg_read_device_property -mode 0 -device_index 0\s*"
                             r".*?The ID value is:\s*(0x[0-9a-fA-F]+).*?"
                             r"Executing\s*:\s*cfg_read_device_property -mode 0 -device_index 0 successfully\.",
                             scan_text, re.S)
        states = re.findall(r"This device configure situation \(done bit\):\s*([01])", scan_text)
        require(checked.returncode == 0 and "PG2L200H" in scan_text and identity is not None
                and int(identity[1], 16) == 0x00603899 and len(states) == 1,
                "unexpected or ambiguous JTAG device identity")
        result["previous_design_active"] = states[0] == "1"
        bit = Path(qualification["bitstream"])
        require(sha(bit) == qualification["sha256"], "bitstream changed after qualification")
        program = out / "program.tcl"
        program.write_text(common + f"cfg_assign_file -file {{{bit.as_posix()}}} -device_index 0\n"
                           "cfg_set_device_property -device_index 0 -program 1\n"
                           "cfg_program -device_index 0\n"
                           "cfg_read_device_property -mode 3 -device_index 0\n"
                           "cfg_disconnect\n", encoding="utf-8")
        serial_port.reset_input_buffer()
        result["status"] = "programming_sram"
        save()
        print("BOARD: programming FPGA SRAM; UART capture is open", flush=True)
        payload = bytearray()
        with (out / "program.log").open("w", encoding="utf-8") as log, (out / "uart.bin").open("wb") as raw:
            cfg = subprocess.Popen([str(PDS_BIN / "cdt_cfg_shell.exe"), "-file", str(program),
                                    "-work_dir", str(out)], stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=flags)
            start = time.monotonic()
            completed_at = None
            while time.monotonic() - start < 300 + args.seconds:
                data = serial_port.read(4096)
                if data:
                    payload.extend(data)
                    raw.write(data)
                    raw.flush()
                    print(data.decode("utf-8", errors="replace"), end="", flush=True)
                if completed_at is None and cfg.poll() is not None:
                    completed_at = time.monotonic()
                    print(f"\nBOARD: programming command exited {cfg.returncode}; "
                          "inspect the display and operate the onboard buttons now", flush=True)
                if completed_at is not None and time.monotonic() - completed_at >= args.seconds:
                    break
            if cfg.poll() is None:
                cfg.terminate()
                cfg.wait(timeout=10)
                raise RuntimeError("programming timed out")
            result["program_exit"] = cfg.returncode
        program_text = (out / "program.log").read_text(encoding="utf-8", errors="replace")
        result["program_success"] = (result["program_exit"] == 0 and "Finish program" in program_text
                                     and "The done bit is 1" in program_text)
        result["uart_bytes"] = len(payload)
        result["boot_banner_seen"] = b"rv32_soc_Game boot" in payload
        result["init_message_seen"] = b"init ok st=" in payload
        result["status"] = "programmed" if result["program_success"] else "program_failed"
        save()
        print("BOARD_RESULT:", json.dumps(result, ensure_ascii=False), flush=True)
        return 0 if result["program_success"] else 1
    except Exception as exc:
        result["status"] = "error"
        result["error"] = f"{type(exc).__name__}: {exc}"
        save()
        raise
    finally:
        if cfg is not None and cfg.poll() is None:
            cfg.terminate()
            try:
                cfg.wait(timeout=10)
            except subprocess.TimeoutExpired:
                cfg.kill()
                cfg.wait(timeout=10)
        if serial_port is not None:
            serial_port.close()
        if server is not None and server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=10)
        if server_log is not None:
            server_log.close()
        if claimed:
            previous = STATUS.read_text(encoding="utf-8")
            STATUS.write_text(f"# Board resource released / rv32_soc_Game 宸查噴鏀綷n\nUTC {utc()}; "
                              f"SRAM-only session ended; evidence {out}.\n\n" + previous, encoding="utf-8")
        if locked:
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        lock.close()
        result["finished_utc"] = utc()
        save()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"BOARD_ERROR: {type(exc).__name__}: {exc}", file=sys.stderr, flush=True)
        raise SystemExit(1)
