#!/usr/bin/env python3
"""Create the hand-over archive of rv32_soc_Game.

The archive contains the complete project (RTL, PDS scripts and constraints,
firmware sources, generated assets, simulation, docs) but not the build
directory.  A manifest with every file's SHA-256 is written next to the ZIP so
the receiver can verify the archive.

    python tools/package.py
"""
from __future__ import annotations

import hashlib
import json
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT.parent / "deliverables"
SKIP_DIRS = {"build", "__pycache__", ".git", "obj", "obj2"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def collect() -> list[Path]:
    files = []
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        if p.suffix.lower() in (".zip", ".pyc"):
            continue
        files.append(p)
    return files


def main() -> int:
    stamp = datetime.now().strftime("%Y%m%d")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = OUT_DIR / f"rv32_soc_Game_{stamp}.zip"
    files = collect()
    manifest = {
        "created": datetime.now().isoformat(timespec="seconds"),
        "root": "rv32_soc_Game",
        "files": [],
    }
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for p in files:
            rel = p.relative_to(ROOT).as_posix()
            zf.write(p, f"rv32_soc_Game/{rel}")
            manifest["files"].append({"path": rel, "bytes": p.stat().st_size,
                                      "sha256": sha256(p)})
    digest = sha256(zip_path)
    manifest["zip"] = zip_path.name
    manifest["zip_bytes"] = zip_path.stat().st_size
    manifest["zip_sha256"] = digest
    (OUT_DIR / f"rv32_soc_Game_{stamp}.manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8")
    (OUT_DIR / f"rv32_soc_Game_{stamp}.zip.sha256").write_text(
        f"{digest}  {zip_path.name}\n", encoding="ascii")
    print(f"{zip_path}  {zip_path.stat().st_size/1e6:.2f} MB  {len(files)} files")
    print(f"sha256 {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
