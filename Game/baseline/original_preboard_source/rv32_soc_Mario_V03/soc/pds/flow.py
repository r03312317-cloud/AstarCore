#!/usr/bin/env python3
"""PDS (Pango Design Suite) implementation flow for rv32_soc_Game.

    python pds/flow.py syn     # compile + synthesize + resource report
    python pds/flow.py full    # compile ... gen_bit_stream

Every run gets its own directory under build/pds/run_<timestamp>/ containing
the Tcl script, the firmware init files and the PDS logs, so a synthesis report
can always be traced back to the exact sources used.  Runs start directly by
default; --guarded explicitly opts into the optional resource guard.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PDS = Path(r"D:/PDS_2025.2-ads-win64/pango/PDS_2025.2-ads/bin/pds_shell.exe")
TOP = "game_board_top"

def rtl_files() -> list[Path]:
    import importlib.util
    spec = importlib.util.spec_from_file_location("game_sources", ROOT / "sim/build_sim.py")
    listing = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(listing)
    out = [ROOT / name for name in listing.SOURCES
           if name.startswith("rtl/") and not name.startswith("rtl/sim/")]
    out.extend(ROOT / name for name in (
        "rtl/video/soc_mini_hdmi_clock.sv", "rtl/video/tmds_encoder.v",
        "pds/ipcore/soc_cpu100_pll_probe/soc_cpu100_pll_probe.v",
        "pds/ipcore/soc_hdmi_7425/clk_hdmi.v"))
    out.extend(p for p in sorted((ROOT / "pds/ipcore/soc_ddr800").rglob("*"))
               if p.is_file() and p.suffix in (".v", ".vp"))
    return out


def make_run_dir() -> Path:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run = ROOT / "build" / "pds" / f"run_{stamp}"
    run.mkdir(parents=True, exist_ok=False)
    for name in ("game-itcm.mem", "game-dtcm.mem"):
        src = ROOT / "build" / "sw" / "device" / name
        if not src.exists():
            raise SystemExit(f"missing {src}; build the firmware first")
        words = src.read_text(encoding="ascii").split()
        if len(words) != 8192 or any(len(word) != 16 or
                any(c not in "0123456789abcdefABCDEF" for c in word) for word in words):
            raise SystemExit(f"{src}: RV32 requires 8192 little-endian 64-bit hex words; rebuild firmware with sw/tools/elf2mem.py")
        shutil.copy2(src, run / name)
    # the DDR IP uses `include "./define.vh"`, resolved from the run directory
    shutil.copy2(ROOT / "pds" / "ipcore" / "soc_ddr800" / "define.vh", run / "define.vh")
    shutil.copy2(ROOT / "pds" / "constraints" / "game_board.fdc", run / "game_board.fdc")
    # The DDR PHY ships routing-priority directives in an .rcf that the
    # reference flow adds as a third constraint file.  Without it the PHY
    # clocks are routed like ordinary nets and calibration becomes unreliable.
    shutil.copy2(ROOT / "pds" / "ipcore" / "soc_ddr800" / "pnr" / "soc_ddr800.rcf",
                 run / "soc_ddr800.rcf")
    return run


def write_tcl(run: Path, stage: str) -> None:
    lines = []
    lines.append(f"# rv32_soc_Game PDS flow, stage={stage}")
    lines.append("set run_root [file normalize [file dirname [info script]]]")
    lines.append("cd $run_root")
    lines.append("set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676")
    lines.append("set_option max_threads 2")  # This flow's chosen PDS setting.
    for p in rtl_files():
        lines.append(f'add_design "{p.as_posix()}" -library work')
    lines.append('add_constraint [file join $run_root game_board.fdc]')
    # Same order as the verified camera flow: board pins first, then the DDR
    # PHY routing priorities.
    lines.append('add_constraint [file join $run_root soc_ddr800.rcf]')
    # The TCM image must be handed over as an absolute path.  Relying on the
    # relative default inside the RTL leaves the memories uninitialised: the
    # core then fetches 0x00000000 at the reset vector, takes an illegal
    # instruction trap, and loops silently at mtvec = 0.  The verified camera
    # flow passes these with -defined_parameters as well.
    itcm = (run / "game-itcm.mem").as_posix()
    dtcm = (run / "game-dtcm.mem").as_posix()
    lines.append(
        f'compile -top_module {TOP} -verilog_standard SystemVerilog '
        # SYNTHESIS drops the simulation-only $fatal checks; the verified camera
        # flow defines it too.  Leaving them in feeds unsupported system tasks
        # to the synthesiser.
        f'-compiler_directives {{SYNTHESIS}} '
        f'-defined_parameters {{ITCM_INIT_FILE "{itcm}" DTCM_INIT_FILE "{dtcm}"}}')
    lines.append('puts "GAME_STAGE synthesize"')
    lines.append('synthesize -ads -force_to_run')
    lines.append('save_project')
    if stage == "full":
        lines.append('puts "GAME_STAGE dev_map"')
        lines.append('dev_map')
        lines.append('puts "GAME_STAGE place"')
        lines.append('place -dc_duplication Global -planning_before_place Enable -refineplacement_iteration 30')
        lines.append("set_option max_threads 4")
        lines.append('puts "GAME_STAGE route"')
        lines.append('route -route_mode normal -slack_weight 90')
        lines.append('puts "GAME_STAGE route_optimize"')
        lines.append('route_optimize -fix_hold_violation_in_route TRUE')
        lines.append("set_option max_threads 2")
        lines.append('puts "GAME_STAGE report_timing"')
        lines.append('report_timing -nworst 10 -max_path 100 -input_pins TRUE')
        lines.append('save_project')
        lines.append('puts "GAME_STAGE gen_bit_stream"')
        lines.append('gen_bit_stream')
        lines.append('save_project')
    lines.append('puts "GAME_FLOW_COMPLETE"')
    (run / "run.tcl").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    stage = args[0] if args else "syn"
    if stage not in ("syn", "full"):
        print(__doc__)
        return 2
    run = make_run_dir()
    write_tcl(run, stage)
    files = rtl_files()
    (run / "sources.json").write_text(json.dumps(
        {"top": TOP, "stage": stage,
         "files": [p.as_posix() for p in files]}, indent=2), encoding="utf-8")
    print(f"run dir: {run}")
    print(f"sources: {len(files)} files")
    print(f"pds: {PDS}")

    if "--guarded" not in flags:
        # The 2026-10-27 project decision dropped the mandatory resource guard.
        # --direct remains accepted for compatibility with older launchers.
        log = open(run / "pds.log", "w", encoding="utf-8")
        rc = subprocess.call([str(PDS), "-file", "run.tcl"], cwd=str(run),
                             stdout=log, stderr=subprocess.STDOUT)
        log.close()
    else:
        guard_out = ROOT / "build" / "pds" / (run.name + "_guard")
        cmd = [sys.executable, str(ROOT / "tools" / "run_guarded.py"),
               "--out", str(guard_out), "--cwd", str(run), "--",
               str(PDS), "-file", "run.tcl"]
        rc = subprocess.call(cmd, cwd=str(ROOT))
    print(f"pds exit={rc}; logs in {run}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
