#!/usr/bin/env python3
"""Build a fresh PDS run from a run_bringup_probe.py source/firmware snapshot.

Example: python pds/run_snapshot.py --probe build/bringup/probe_YYYYMMDD_HHMMSS_xxxxxx
The PDS files, constraints, RTL, firmware and hashes stay together in that
probe directory.  Existing builds and reports are never removed or replaced.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--probe", type=Path, required=True)
    p.add_argument("--stage", choices=("syn", "full"), default="full")
    args = p.parse_args()
    probe = args.probe.resolve()
    source = probe / "source"
    hashes = json.loads((probe / "source_sha256.json").read_text(encoding="utf-8"))
    for relative, expected in hashes.items():
        if sha(source / relative) != expected:
            raise RuntimeError(f"snapshot source changed: {relative}")
    pds = source / "pds"
    if pds.exists():
        raise RuntimeError(f"{pds} already exists; use a new probe to keep evidence immutable")
    shutil.copytree(ROOT / "pds", pds)
    fw = source / "build/sw/device"
    fw.mkdir(parents=True, exist_ok=False)
    for name in ("game-itcm.mem", "game-dtcm.mem"):
        shutil.copy2(probe / name, fw / name)
    pds_hashes = [{"Path": str(path.resolve()), "Hash": sha(path)}
                  for path in sorted(pds.rglob("*")) if path.is_file()]
    (probe / "pds_source_sha256.json").write_text(json.dumps(pds_hashes, indent=2) + "\n",
                                                  encoding="utf-8")
    cmd = [sys.executable, "-u", str(pds / "flow.py"), args.stage, "--direct"]
    print("PDS_SNAPSHOT:", probe, flush=True)
    with (probe / "pds_launcher.log").open("w", encoding="utf-8") as log:
        log.write("COMMAND: " + subprocess.list2cmdline(cmd) + "\n")
        log.flush()
        proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, errors="replace")
        assert proc.stdout is not None
        for line in proc.stdout:
            print(line, end="", flush=True)
            log.write(line)
            log.flush()
        code = proc.wait()
        log.write(f"EXIT={code}\n")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
