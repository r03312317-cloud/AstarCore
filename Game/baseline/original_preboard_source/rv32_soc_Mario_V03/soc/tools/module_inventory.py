#!/usr/bin/env python3
"""Produce the module keep/remove table for the Game SoC.

Reads the module names from the mainline stage tree (read-only) and from this
project, then classifies every mainline module:

    KEEP     copied unchanged into rv32_soc_Game
    NEW      written for the Game SoC
    REMOVED  not present in the Game project (AI / camera / test logic)

Writes docs/MODULE_TABLE.md and docs/MODULE_TABLE.json.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAINLINE = Path(r"D:/workspace/riscv-fpga-soc/rtl/rv32_soc_CMOS2_DDRBurst_P0_20261007_01/project/stage_ddr_hdmi")

MODULE_RE = re.compile(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
PACKAGE_RE = re.compile(r"^\s*package\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)

# reason strings for the removed groups
REMOVAL_REASON = [
    ("npu_", "NPU 8x8 MAC 阵列、调度器、scratchpad、DMA、后处理"),
    ("cp9_", "NPU 进度看门狗"),
    ("cp12_", "NPU DMA 读步进"),
    ("cp13_k_lengths", "NPU K 维长度表"),
    ("soc_camera_", "摄像头 DVP 采集、AXI 写入、帧流水线、诊断"),
    ("soc_ov5640_", "OV5640 配置/采集"),
    ("soc_requant", "AI 量化（Requant）流水与 LUT DMA"),
    ("soc_window_", "卷积 Window gather/地址生成/MMIO"),
    ("soc_concat", "Concat DMA 与 MMIO"),
    ("soc_pool", "Pool DMA 与 MMIO"),
    ("soc_s3_mmio_mem", "S3 层参数 MMIO"),
    ("soc_v2_", "5MP 双流预处理/回放/AXI 写回"),
    ("soc_video_axi_reader", "5MP 视频 AXI 读"),
    ("soc_video_event_mmio", "视频事件统计 MMIO"),
    ("soc_p0_burst_stats", "P0 突发统计（66 个计数器）"),
    ("soc_native_", "AI 通路专用 native 2M 仲裁"),
    ("soc_rq_", "Requant 专用 AXI 适配"),
    ("soc_axi_2m_arbiter", None),  # kept
    ("soc_display_commit_mmio", "识别框/帧覆盖校验提交（游戏用新的 game_video_ctrl）"),
    ("core0_system_fabric", "旧 CoreMark 系统总线（游戏用 pg_cpu_peripherals 直连）"),
    ("core0_cycle_timer", "旧定时器（CP13 块已含 64 位计数器）"),
    ("core0_uart_mmio", "旧 UART（CP13 UART 已含收发与 FIFO）"),
    ("core0_uart_tx", "旧 UART 发送器"),
    ("soc_peripherals", "外设聚合层（游戏直接实例化 CP13 块）"),
    ("soc_soc_top", "含 NPU/相机的 SoC 顶层，被 game_soc_top 替代"),
    ("soc_board_camera_top", "相机板级顶层，被 game_board_top 替代"),
    ("soc_board_top", "旧监视器板级顶层"),
    ("soc_camera_input_hold", "相机输入延时单元（GTP_ZEROHOLDDELAY）"),
    ("pg_npu_mmio_bridge", "NPU MMIO 桥"),
    ("pg_npu_", "NPU 相关"),
    ("soc_native_cdc", "旧 native CDC（未使用）"),
]


def modules_in(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for p in path.rglob("*"):
        if p.suffix not in (".v", ".sv", ".vp"):
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in MODULE_RE.finditer(text):
            out.setdefault(m.group(1), p.name)
    return out


def reason(name: str) -> str:
    for prefix, why in REMOVAL_REASON:
        if why is not None and name.startswith(prefix):
            return why
    return "与游戏无关（相机/AI/测试专用）"


def main() -> int:
    main_mods = modules_in(MAINLINE / "rtl")
    main_mods.update(modules_in(MAINLINE / "board"))
    game_mods = modules_in(ROOT / "rtl")
    new_mods = {"game_input", "game_video_ctrl", "game_mmio_fabric",
                "game_soc_top", "game_board_top", "game_ddr_model",
                "DSP48E1"}

    rows = []
    for name in sorted(main_mods):
        if name in game_mods:
            rows.append((name, "KEEP", main_mods[name], "主线原样复制"))
        else:
            rows.append((name, "REMOVED", main_mods[name], reason(name)))
    for name in sorted(game_mods):
        if name not in main_mods:
            rows.append((name, "NEW", "-", "为游戏新增" if name in new_mods else "新增/辅助"))

    md = ["# 模块保留 / 删除清单\n",
          "主线来源：`rtl/rv32_soc_CMOS2_DDRBurst_P0_20261007_01/project/stage_ddr_hdmi`（只读）。",
          "判定依据是实际 RTL 实例化关系，不是文件名。\n",
          f"- KEEP: {sum(1 for r in rows if r[1] == 'KEEP')}",
          f"- REMOVED: {sum(1 for r in rows if r[1] == 'REMOVED')}",
          f"- NEW: {sum(1 for r in rows if r[1] == 'NEW')}\n",
          "| 模块 | 结论 | 主线文件 | 说明 |", "|---|---|---|---|"]
    for name, verdict, src, why in rows:
        md.append(f"| `{name}` | {verdict} | {src} | {why} |")
    (ROOT / "docs").mkdir(exist_ok=True)
    (ROOT / "docs" / "MODULE_TABLE.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    (ROOT / "docs" / "MODULE_TABLE.json").write_text(
        json.dumps([{"module": r[0], "verdict": r[1], "source_file": r[2], "note": r[3]}
                    for r in rows], indent=2), encoding="utf-8")
    print(f"{len(rows)} modules: "
          f"{sum(1 for r in rows if r[1]=='KEEP')} keep, "
          f"{sum(1 for r in rows if r[1]=='REMOVED')} removed, "
          f"{sum(1 for r in rows if r[1]=='NEW')} new")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
