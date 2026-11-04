#!/usr/bin/env python3
"""Qualify and load Mario through the proven SRAM loader and stage2 receiver.
Default: qualification only. --execute programs SRAM and uploads the game.
One board/UART lock is held across configuration, stage2 and game startup.

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


def qualify() -> dict:
    from board_artifacts import qualify as check
    return check()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=int, default=8)
    parser.add_argument("--jtag-port", type=int, default=61420,
                        help="local JTAG server port; choose another if Windows reserves the default")
    parser.add_argument("--qualify-only", action="store_true",
                        help="validate hashes/simulation/timing/bitstream without using the board")
    parser.add_argument("--report", type=Path, help="write the qualification JSON here")
    parser.add_argument("--execute", action="store_true", help="program SRAM and load Mario; default validates only")
    parser.add_argument("--capture-seconds", type=int, default=120)
    args = parser.parse_args()
    require(1 <= args.capture_seconds <= 600, "runtime capture must be 1..600 seconds")
    require(args.seconds > 0, "capture time must be positive")
    require(1024 <= args.jtag_port <= 65535, "JTAG port must be between 1024 and 65535")
    qualification = qualify()
    print("QUALIFIED", json.dumps(qualification, ensure_ascii=False), flush=True)
    if args.report:
        args.report.write_text(json.dumps(qualification, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.qualify_only or not args.execute:
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
        STATUS.write_text(f"# Board resource lease\n\nUTC {utc()}; current owner: rv32_soc_Mario_V03; "
                          f"SRAM-only Mario loader; evidence {out}.\n\n" + previous, encoding="utf-8")
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
                          "waiting for compatible APAL loader DDR-ready UART marker", flush=True)
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
        # The first UART byte during FPGA configuration can be garbled. Ask
        # the now-stable, successfully configured loader to repeat its banner.
        if result["program_success"] and b"APAL_READY V01 100MHz" not in payload:
            from uart_mario import packet
            serial_port.write(packet(0, 0))
            serial_port.flush()
            deadline = time.monotonic() + 5
            with (out / "uart.bin").open("ab") as raw:
                while time.monotonic() < deadline:
                    data = serial_port.read(256)
                    if data:
                        payload.extend(data); raw.write(data); raw.flush()
                        print(data.decode("utf-8", errors="replace"), end="", flush=True)
                    if b"APAL_READY V01 100MHz" in payload:
                        break
        result["uart_bytes"] = len(payload)
        result["boot_banner_seen"] = b"APAL_READY V01 100MHz" in payload
        result["init_message_seen"] = b"APAL_READY V01 100MHz" in payload
        result["status"] = ("loader_ready" if result["init_message_seen"] else "loader_no_uart") if result["program_success"] else "program_failed"
        save()
        if result["program_success"] and result["init_message_seen"]:
            from uart_mario import upload_mario
            result["runtime"] = upload_mario(serial_port, qualification, out, args.capture_seconds)
            result["status"] = "mario_running_uart_verified"
        print("BOARD_RESULT:", json.dumps(result, ensure_ascii=False), flush=True)
        return 0 if result.get("runtime", {}).get("runtime_progress_seen") else 1
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
            STATUS.write_text(f"# Board resource released / rv32_soc_Mario_V03 released\n\nUTC {utc()}; "
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
