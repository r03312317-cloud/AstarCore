#!/usr/bin/env python3
"""RV32 game simulation entry point.

    python sim/build_sim.py build [--frames 180]
    python sim/run_bringup_probe.py --frames 180

Both create independent firmware/RTL/evidence snapshots and verify the actual
RV32 CPU with SRAM/DDR probes, pin UART and captured game display rasters.
SOURCES is also the authoritative active RTL list imported by pds/flow.py.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

SOURCES = [
    'rtl/rv32/core/rv32_address_classify.v',
    'rtl/rv32/core/rv32_arithmetic.v',
    'rtl/rv32/core/rv32_committed_ras.v',
    'rtl/rv32/core/rv32_execute.v',
    'rtl/rv32/core/rv32_hybrid_predictor.v',
    'rtl/rv32/core/rv32_instruction_flags.v',
    'rtl/rv32/core/rv32_issue_bank.v',
    'rtl/rv32/core/rv32_issue_scheduler.v',
    'rtl/rv32/core/rv32_memory_system.v',
    'rtl/rv32/core/rv32_mul_stream.v',
    'rtl/rv32/core/rv32_ooo_core.v',
    'rtl/rv32/core/rv32_ooo_frontend.v',
    'rtl/rv32/core/rv32_ooo_soc_top.v',
    'rtl/rv32/core/rv32_queue_allocator.v',
    'rtl/rv32/rv32_game_cpu_tile.sv',
    'rtl/rv32/rv32_game_line_memory.sv',
    'rtl/rv32/rv32_game_periph.sv',
    'rtl/rv32/rv32_game_sram.sv',
    'rtl/rv32/rv32_line128_adapter.sv',
    'rtl/interconnect/pg_three_request_mux.sv',
    'rtl/interconnect/pg_ddr_burst_bridge.sv',
    'rtl/interconnect/pg_sync_fifo.sv',
    'rtl/interconnect/soc_board_mmio_router.sv',
    'rtl/cdc/soc_reset_sync.sv',
    'rtl/cdc/soc_level_sync.sv',
    'rtl/cdc/pg_level_sync.sv',
    'rtl/cdc/pg_memory_cdc.sv',
    'rtl/cdc/pg_mmio_cdc.sv',
    'rtl/cdc/pg_source_level_register.sv',
    'rtl/cdc/soc_async_fifo.sv',
    'rtl/cdc/pg_async_fifo_dc.sv',
    'rtl/cdc/pg_reset_sync.sv',
    'rtl/peripheral/pg_cpu_peripherals.sv',
    'rtl/peripheral/pg_uart.sv',
    'rtl/peripheral/pg_gpio.sv',
    'rtl/video/soc_mini_hdmi_tx.sv',
    'rtl/video/soc_hdmi_ddr_scanout.sv',
    'rtl/video/soc_hdmi_axi_reader.sv',
    'rtl/video/soc_display_async_fifo.sv',
    'rtl/video/soc_stereo_osd.sv',
    'rtl/video/soc_hmic_axi_adapter.sv',
    'rtl/video/soc_axi_2m_arbiter.sv',
    'rtl/game/game_input.sv',
    'rtl/game/game_video_ctrl.sv',
    'rtl/game/game_mmio_fabric.sv',
    'rtl/top/game_soc_top.sv',
    'rtl/top/game_board_top.sv',
    'rtl/sim/game_ddr_model.sv',
    'sim/tb_game_board.sv',
    'sim/sim_main.cpp',
]


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    if sys.argv[1] not in ("build", "both", "verify"):
        print("Use build/verify to create a new immutable simulation run. See --help.")
        return 2
    return subprocess.call([sys.executable, str(ROOT / "sim/run_bringup_probe.py"),
                            *sys.argv[2:]], cwd=ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
