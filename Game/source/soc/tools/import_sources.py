#!/usr/bin/env python3
"""Copy the verified rv32_soc mainline RTL subset into rv32_soc_Game.

Every copied file keeps its original module name and header comments so that
the mainline and the Game project can be compared line by line.  The script
writes docs/RTL_PROVENANCE.json with source path, size and SHA-256 for each
file, which is the audit trail required by the project rules.

The mainline tree is only read, never modified.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

SRC_ROOT = Path(r"D:/workspace/riscv-fpga-soc/rtl/rv32_soc_CMOS2_DDRBurst_P0_20261007_01/project/stage_ddr_hdmi")
DST_ROOT = Path(__file__).resolve().parents[1]

# mainline relative path -> game relative path
FILES = {
    # ---- CPU core (unchanged, four-stage in-order single-issue) ----
    "rtl/core/dc_realtime_core_pkg.sv": "rtl/core/dc_realtime_core_pkg.sv",
    "rtl/core/dc_realtime_core_decode.sv": "rtl/core/dc_realtime_core_decode.sv",
    "rtl/core/dc_realtime_core_regfile.sv": "rtl/core/dc_realtime_core_regfile.sv",
    "rtl/core/dc_realtime_core_bpu.sv": "rtl/core/dc_realtime_core_bpu.sv",
    "rtl/core/dc_realtime_core_btb_bank.sv": "rtl/core/dc_realtime_core_btb_bank.sv",
    "rtl/core/dc_realtime_core_fetch_queue.sv": "rtl/core/dc_realtime_core_fetch_queue.sv",
    "rtl/core/dc_realtime_core_loop_predictor.sv": "rtl/core/dc_realtime_core_loop_predictor.sv",
    "rtl/core/dc_realtime_core_mul.sv": "rtl/core/dc_realtime_core_mul.sv",
    "rtl/core/dc_realtime_core_div.sv": "rtl/core/dc_realtime_core_div.sv",
    "rtl/core/dc_realtime_core_mdu.sv": "rtl/core/dc_realtime_core_mdu.sv",
    "rtl/core/dc_realtime_core_csr.sv": "rtl/core/dc_realtime_core_csr.sv",
    "rtl/core/dc_realtime_core_fast_irq.sv": "rtl/core/dc_realtime_core_fast_irq.sv",
    "rtl/core/dc_realtime_cpu_core.sv": "rtl/core/dc_realtime_cpu_core.sv",
    # ---- TCM / caches ----
    "rtl/memory/dc_realtime_core_itcm_channel.sv": "rtl/memory/dc_realtime_core_itcm_channel.sv",
    "rtl/memory/dc_realtime_core_tcm_channel.sv": "rtl/memory/dc_realtime_core_tcm_channel.sv",
    "rtl/memory/dc_realtime_core_tcm_bram.sv": "rtl/memory/dc_realtime_core_tcm_bram.sv",
    "rtl/memory/dc_realtime_core_split_bus.sv": "rtl/memory/dc_realtime_core_split_bus.sv",
    "rtl/cache/pg_cache2way.sv": "rtl/cache/pg_cache2way.sv",
    "rtl/cache/pg_cache_data_ram.sv": "rtl/cache/pg_cache_data_ram.sv",
    "rtl/cache/pg_cached_data_router.sv": "rtl/cache/pg_cached_data_router.sv",
    # ---- interconnect ----
    "rtl/interconnect/dc_realtime_core_npu_router.sv": "rtl/interconnect/dc_realtime_core_npu_router.sv",
    "rtl/interconnect/soc_ordered_if_router.sv": "rtl/interconnect/soc_ordered_if_router.sv",
    "rtl/interconnect/pg_three_request_mux.sv": "rtl/interconnect/pg_three_request_mux.sv",
    "rtl/interconnect/pg_ddr_burst_bridge.sv": "rtl/interconnect/pg_ddr_burst_bridge.sv",
    "rtl/interconnect/pg_sync_fifo.sv": "rtl/interconnect/pg_sync_fifo.sv",
    "rtl/interconnect/soc_board_mmio_router.sv": "rtl/interconnect/soc_board_mmio_router.sv",
    # ---- clock domain crossing ----
    "rtl/cdc/soc_reset_sync.sv": "rtl/cdc/soc_reset_sync.sv",
    "rtl/cdc/pg_level_sync.sv": "rtl/cdc/pg_level_sync.sv",
    "rtl/cdc/pg_memory_cdc.sv": "rtl/cdc/pg_memory_cdc.sv",
    "rtl/cdc/pg_mmio_cdc.sv": "rtl/cdc/pg_mmio_cdc.sv",
    "rtl/cdc/pg_source_level_register.sv": "rtl/cdc/pg_source_level_register.sv",
    "rtl/cdc/soc_async_fifo.sv": "rtl/cdc/soc_async_fifo.sv",
    "rtl/cdc/pg_async_fifo_dc.sv": "rtl/cdc/pg_async_fifo_dc.sv",
    "rtl/cdc/pg_reset_sync.sv": "rtl/cdc/pg_reset_sync.sv",
    "rtl/cdc/soc_level_sync.sv": "rtl/cdc/soc_level_sync.sv",
    # ---- CPU peripherals (timer / UART / GPIO) ----
    "rtl/peripheral/pg_cpu_peripherals.sv": "rtl/peripheral/pg_cpu_peripherals.sv",
    "rtl/peripheral/pg_uart.sv": "rtl/peripheral/pg_uart.sv",
    "rtl/peripheral/pg_gpio.sv": "rtl/peripheral/pg_gpio.sv",
    # ---- CPU tile ----
    "rtl/top/soc_cpu_tile_v15.sv": "rtl/top/soc_cpu_tile_v15.sv",
    # ---- vendor primitive shims (multiplication backend + Pango APM) ----
    "fpga/vendor/dc_realtime_mul_backend.sv": "rtl/vendor/dc_realtime_mul_backend.sv",
    "fpga/vendor/dsp48e1_pango_compat.sv": "rtl/vendor/dsp48e1_pango_compat.sv",
    # ---- video path (display side of the mainline) ----
    "board/soc_mini_hdmi_clock.sv": "rtl/video/soc_mini_hdmi_clock.sv",
    "board/soc_mini_hdmi_tx.sv": "rtl/video/soc_mini_hdmi_tx.sv",
    "board/hdmi_vendor/tmds_encoder.v": "rtl/video/tmds_encoder.v",
    "board/soc_hdmi_ddr_scanout.sv": "rtl/video/soc_hdmi_ddr_scanout.sv",
    "board/soc_hdmi_axi_reader.sv": "rtl/video/soc_hdmi_axi_reader.sv",
    "board/soc_display_async_fifo.sv": "rtl/video/soc_display_async_fifo.sv",
    "board/soc_stereo_osd.sv": "rtl/video/soc_stereo_osd.sv",
    "board/soc_hmic_axi_adapter.sv": "rtl/video/soc_hmic_axi_adapter.sv",
    "board/soc_axi_2m_arbiter.sv": "rtl/video/soc_axi_2m_arbiter.sv",
    "board/soc_axi_2m_arbiter.sv": "rtl/video/soc_axi_2m_arbiter.sv",
}

# IP cores are copied as whole directories (vendor generated sources).
IP_DIRS = {
    "ipcore/soc_cpu100_pll_probe": "pds/ipcore/soc_cpu100_pll_probe",
    "ipcore/soc_hdmi_7425": "pds/ipcore/soc_hdmi_7425",
    "ipcore/soc_ddr800": "pds/ipcore/soc_ddr800",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if not SRC_ROOT.is_dir():
        print(f"mainline source tree missing: {SRC_ROOT}", file=sys.stderr)
        return 2
    records = []
    for rel_src, rel_dst in FILES.items():
        src = SRC_ROOT / rel_src
        dst = DST_ROOT / rel_dst
        if not src.is_file():
            print(f"missing source {src}", file=sys.stderr)
            return 3
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        records.append({
            "game_path": rel_dst.replace("\\", "/"),
            "source_path": str(src).replace("\\", "/"),
            "bytes": dst.stat().st_size,
            "sha256": sha256(dst),
        })
    ip_records = []
    for rel_src, rel_dst in IP_DIRS.items():
        src = SRC_ROOT / rel_src
        dst = DST_ROOT / rel_dst
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        for p in sorted(dst.rglob("*")):
            if p.is_file():
                ip_records.append({
                    "game_path": str(p.relative_to(DST_ROOT)).replace("\\", "/"),
                    "source_path": str(src / p.relative_to(dst)).replace("\\", "/"),
                    "bytes": p.stat().st_size,
                    "sha256": sha256(p),
                })
    out = {
        "mainline_root": str(SRC_ROOT).replace("\\", "/"),
        "note": "Files copied byte-identical; no mainline file was modified.",
        "rtl": records,
        "ipcore": ip_records,
    }
    manifest = DST_ROOT / "docs" / "RTL_PROVENANCE.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"copied {len(records)} RTL files, {len(ip_records)} IP files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
