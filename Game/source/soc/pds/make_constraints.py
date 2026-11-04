#!/usr/bin/env python3
"""Build game_board.fdc from the mainline board constraints.

Re-typing 900 pin attributes would be an easy way to introduce errors, so the
DDR, TMDS, clock, UART and LED attributes are extracted verbatim from the
verified mainline file and only the game-specific pins are added here.

Sources (read-only):
  rtl/rv32_soc_CMOS2_DDRBurst_P0_20261007_01/project/stage_ddr_hdmi/board/soc_board_camera.fdc
  sources/Pango_100K200K_MINI/3_Hardware/FPGA管脚分配/mini-base管脚映射.xlsx
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC_FDC = Path(r"D:/workspace/riscv-fpga-soc/rtl/rv32_soc_CMOS2_DDRBurst_P0_20261007_01/"
               r"project/stage_ddr_hdmi/board/soc_board_camera.fdc")
# Board-verified 480p60 variant (same board, HDMI confirmed on a real monitor):
# TMDS pins there are VCCIO 2.5 / LVDS25 because bank L5 is fed from 2.5 V.
REF_FDC = ROOT / "pds" / "constraints" / "ref" / "soc_board_camera_480p.fdc"
OUT = ROOT / "pds" / "constraints" / "game_board.fdc"

# ---------------------------------------------------------------- pin groups
# Byte pins of the (unused) second camera connector become the external pad
# port.  Order matches game_regs.h: UP, DOWN, LEFT, RIGHT, A, B, START, SELECT.
PAD_PINS = ["M22", "R23", "T23", "AB24", "P26", "M26", "AA24", "AB25"]
# USER_BUTTON1..3 and USER_BUTTON4 plus USER_BUTTON0 (C22) as the A button.
BTN_PINS = ["C23", "B22", "A22", "B20", "C22"]

KEEP_PREFIXES = (
    "mem_", "tmds_", "led[", "clk_p", "clk_n", "sys_clk", "uart_tx", "uart_rx",
)

ATTR_RE = re.compile(r"define_attribute \{p:([^}]+)\} \{([^}]+)\} \{([^}]*)\}")


def parse(path: Path) -> dict[str, list[tuple[str, str]]]:
    groups: dict[str, list[tuple[str, str]]] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = ATTR_RE.search(line)
        if not m:
            continue
        port, attr, value = m.groups()
        groups.setdefault(port, []).append((attr, value))
    return groups


def emit_port(name: str, attrs: list[tuple[str, str]], extra: dict | None = None) -> str:
    lines = []
    for attr, value in attrs:
        lines.append(f"define_attribute {{p:{name}}} {{{attr}}} {{{value}}}")
    if extra:
        for attr, value in extra.items():
            lines.append(f"define_attribute {{p:{name}}} {{{attr}}} {{{value}}}")
    return "\n".join(lines) + "\n"


def main() -> int:
    src = parse(SRC_FDC)
    ref = parse(REF_FDC)
    ref_by_loc = {}
    for _port, _attrs in ref.items():
        _loc = dict(_attrs).get("PAP_IO_LOC")
        if _loc:
            ref_by_loc.setdefault(_loc, dict(_attrs))
    out: list[str] = []
    out.append("# rv32_soc_Game board constraints (PG2L200H-6FBB676, MES2L676-200HP)\n")
    out.append("# Pin attributes for DDR3, TMDS, clocks, UART and LEDs are copied\n")
    out.append("# verbatim from the verified mainline soc_board_camera.fdc.\n\n")

    # ---- clocks ---------------------------------------------------------
    out.append("""# ---- clocks -------------------------------------------------------------
# 27 MHz oscillator (D18) drives the HDMI PLL (27 MHz pixel / 135 MHz serial,
# the 480p60 profile verified on this board).
create_clock -name sys_clk -period 37.037037037 -waveform {0 18.518518519} [get_ports sys_clk]
set_clock_uncertainty 0.1 [get_clocks sys_clk]
# 125 MHz differential reference drives the CPU PLL and the DDR controller.
create_clock -name {ref_clk} [get_ports {clk_p}] -period {8.0} -waveform {0 4.0}
create_generated_clock -name cpu_clk_fast -source [get_ports {clk_p}] [get_pins {u_cpu_pll/clkout1}] -master_clock [get_clocks {ref_clk}] -multiply_by 4 -divide_by 5
set_clock_uncertainty 0.1 [get_clocks cpu_clk_fast]
create_generated_clock -name hdmi_pixel_clk -source [get_ports sys_clk] [get_pins {u_hdmi_clock/u_pll/clkout0}] -master_clock [get_clocks sys_clk] -multiply_by 1 -divide_by 1
create_generated_clock -name hdmi_serial_clk -source [get_ports sys_clk] [get_pins {u_hdmi_clock/u_pll/clkout1}] -master_clock [get_clocks sys_clk] -multiply_by 5 -divide_by 1
set_clock_uncertainty 0.1 [get_clocks hdmi_pixel_clk]
set_clock_uncertainty 0.1 [get_clocks hdmi_serial_clk]
create_generated_clock -name {rst_clk} -source [get_ports {clk_p}] [get_pins {I_ips_ddr_top.u_ddrphy_top.rst_clk_gpll/clkout0}] -master_clock [get_clocks {ref_clk}] -multiply_by {12} -divide_by {12}
create_generated_clock -name {ddrphy_sysclk} -source [get_ports {clk_p}] [get_pins {I_ips_ddr_top.u_ddrphy_top.ddrphy_gpll/clkout0}] -master_clock [get_clocks {ref_clk}] -multiply_by {12} -divide_by {16}
create_generated_clock -name {phy_dq_clk_0} -source [get_ports {clk_p}] [get_pins {I_ips_ddr_top.u_ddrphy_top.ddrphy_slice_top.i_dqs_bank[0].ddrphy_ppll/clkoutphy}] -master_clock [get_clocks {ref_clk}] -multiply_by {12} -divide_by {2}
create_generated_clock -name {phy_dq_sysclk_0} -source [get_pins {I_ips_ddr_top.u_ddrphy_top.ddrphy_slice_top.i_dqs_bank[0].ddrphy_ppll/clkoutphy}] [get_pins {I_ips_ddr_top.u_ddrphy_top.ddrphy_slice_top.i_dqs_bank[0].u_ddrphy_ioclkdiv/CLKDIVOUT}] -master_clock [get_clocks {phy_dq_clk_0}] -edges {5 13 21} -edge_shift {0 0 0}
set_multicycle_path 2 -from [get_clocks ddrphy_sysclk] -to [get_clocks phy_dq_sysclk_0]
create_generated_clock -name {phy_dq_clk_1} -source [get_ports {clk_p}] [get_pins {I_ips_ddr_top.u_ddrphy_top.ddrphy_slice_top.i_dqs_bank[1].ddrphy_ppll/clkoutphy}] -master_clock [get_clocks {ref_clk}] -multiply_by {12} -divide_by {2}
create_generated_clock -name {phy_dq_sysclk_1} -source [get_pins {I_ips_ddr_top.u_ddrphy_top.ddrphy_slice_top.i_dqs_bank[1].ddrphy_ppll/clkoutphy}] [get_pins {I_ips_ddr_top.u_ddrphy_top.ddrphy_slice_top.i_dqs_bank[1].u_ddrphy_ioclkdiv/CLKDIVOUT}] -master_clock [get_clocks {phy_dq_clk_1}] -edges {5 13 21} -edge_shift {0 0 0}
set_multicycle_path 2 -from [get_clocks ddrphy_sysclk] -to [get_clocks phy_dq_sysclk_1]
set_clock_uncertainty {0.4} -from [get_clocks {ddrphy_sysclk}] -to [get_clocks {phy_dq_sysclk_0}] -setup -hold
set_clock_uncertainty {0.4} -from [get_clocks {phy_dq_sysclk_0}] -to [get_clocks {ddrphy_sysclk}] -setup -hold
set_clock_uncertainty {0.4} -from [get_clocks {ddrphy_sysclk}] -to [get_clocks {phy_dq_sysclk_1}] -setup -hold
set_clock_uncertainty {0.4} -from [get_clocks {phy_dq_sysclk_1}] -to [get_clocks {ddrphy_sysclk}] -setup -hold
set_clock_groups -name ddr_ref -asynchronous -group [get_clocks {ref_clk}]
set_clock_groups -name ddr_rst -asynchronous -group [get_clocks {rst_clk}]
set_clock_groups -name ddr_phy0 -asynchronous -group [get_clocks {phy_dq_clk_0}]
set_clock_groups -name ddr_phy1 -asynchronous -group [get_clocks {phy_dq_clk_1}]
# hdmi_pixel_clk is sys_clk divided by 1 (27 MHz) after the 480p60 retune, so it
# must NOT be declared asynchronous to sys_clk any more.

# ---- CDC budgets --------------------------------------------------------
# Every CPU <-> DDR crossing is an asynchronous FIFO or a two-flop level
# synchroniser; constrain the routing delay instead of pretending they are
# synchronous.  Same values the mainline uses for its own CDC paths.
set_max_delay 10.666666667 -datapath_only -from [get_clocks cpu_clk_fast] -to [get_clocks ddrphy_sysclk]
set_min_delay 0.0 -from [get_clocks cpu_clk_fast] -to [get_clocks ddrphy_sysclk]
set_max_delay 10.666666667 -datapath_only -from [get_clocks ddrphy_sysclk] -to [get_clocks cpu_clk_fast]
set_min_delay 0.0 -from [get_clocks ddrphy_sysclk] -to [get_clocks cpu_clk_fast]
set_max_delay 13.468013468 -datapath_only -from [get_clocks hdmi_pixel_clk] -to [get_clocks ddrphy_sysclk]
set_min_delay 0.0 -from [get_clocks hdmi_pixel_clk] -to [get_clocks ddrphy_sysclk]
set_max_delay 13.468013468 -datapath_only -from [get_clocks ddrphy_sysclk] -to [get_clocks hdmi_pixel_clk]
set_min_delay 0.0 -from [get_clocks ddrphy_sysclk] -to [get_clocks hdmi_pixel_clk]
set_max_delay 37.037037037 -datapath_only -from [get_clocks sys_clk] -to [get_clocks cpu_clk_fast]
set_min_delay 0.0 -from [get_clocks sys_clk] -to [get_clocks cpu_clk_fast]
set_max_delay 37.037037037 -datapath_only -from [get_clocks cpu_clk_fast] -to [get_clocks sys_clk]
set_min_delay 0.0 -from [get_clocks cpu_clk_fast] -to [get_clocks sys_clk]
# The LED panel samples ddr_ready with a two-flop synchroniser running on
# sys_clk, so that crossing needs a routing budget as well (it was the only
# -3.1 ns violation in the first routed build).
set_max_delay 37.037037037 -datapath_only -from [get_clocks ddrphy_sysclk] -to [get_clocks sys_clk]
set_min_delay 0.0 -from [get_clocks ddrphy_sysclk] -to [get_clocks sys_clk]

# Board inputs are asynchronous buttons and UART; outputs only drive LEDs and
# a 115.2 kbaud line, so a 5 ns budget is far tighter than needed.
set_false_path -from [get_ports {btn_n[*] pad_n[*] uart_rx}]
set_output_delay -max 5.0 -clock sys_clk [get_ports {uart_tx led[*]}]
set_output_delay -min 0.0 -clock sys_clk [get_ports {uart_tx led[*]}]

""")

    out.append("# ---- pin attributes ------------------------------------------------------\n")

    missing = []
    for port in sorted(src):
        if not port.startswith(KEEP_PREFIXES):
            continue
        if port.startswith("tmds_"):
            # Take the whole attribute set from the board-verified 480p file:
            # VCCIO 2.5 + LVDS25 + DRIVE 3.5.  Bank L5 on this baseboard is
            # supplied from 2.5 V, so the old 3.3 V / TMDS33 combination would
            # have described hardware that does not exist.
            out.append(emit_port(port, ref.get(port, src[port])))
            continue
        if port.startswith("led[") or port in ("sys_clk", "clk_p", "clk_n", "uart_tx", "uart_rx"):
            out.append(emit_port(port, src[port]))
        elif port.startswith(("mem_", "tmds_")):
            out.append(emit_port(port, src[port]))
        else:
            missing.append(port)

    # new game-specific pins
    out.append("\n# ---- game buttons (USER_BUTTON1..4 + USER_BUTTON0 = A) --------------------\n")
    for idx, pin in enumerate(BTN_PINS):
        out.append(emit_port(f"btn_n[{idx}]", [
            ("PAP_IO_DIRECTION", "INPUT"),
            ("PAP_IO_LOC", pin),
            ("PAP_IO_NONE", "TRUE"),
            ("PAP_IO_PULLUP", "TRUE"),
            ("PAP_IO_STANDARD", "LVCMOS33"),
            ("PAP_IO_VCCIO", "3.3"),
        ]))
    out.append("\n# ---- external pads on the unused camera connector ------------------------\n")
    for idx, pin in enumerate(PAD_PINS):
        # Same physical pin, same bank voltage as the camera connector: M22 /
        # R23 / T23 / P26 / M26 sit in the 2.5 V group, the rest are 3.3 V.
        r = ref_by_loc.get(pin, {})
        vccio = r.get("PAP_IO_VCCIO", "3.3")
        std = r.get("PAP_IO_STANDARD", "LVCMOS33")
        out.append(emit_port(f"pad_n[{idx}]", [
            ("PAP_IO_DIRECTION", "INPUT"),
            ("PAP_IO_LOC", pin),
            ("PAP_IO_NONE", "TRUE"),
            ("PAP_IO_PULLUP", "TRUE"),
            ("PAP_IO_STANDARD", std),
            ("PAP_IO_VCCIO", vccio),
        ]))

    # DDR PHY placement attributes
    out.append("\n# ---- DDR PHY placement ---------------------------------------------------\n")
    for key in ("i:I_ips_ddr_top.u_ddrphy_top.u_ddrphy_cpd",
                "i:I_ips_ddr_top.u_ddrphy_top.ddrphy_reset_ctrl.ddrphy_ioclk_gate[0]",
                "i:I_ips_ddr_top.u_ddrphy_top.ddrphy_reset_ctrl.ddrphy_ioclk_gate[1]"):
        for line in SRC_FDC.read_text(encoding="utf-8", errors="replace").splitlines():
            if f"{{{key}}}" in line:
                out.append(line + "\n")

    # ---- HDMI TX physical region (from the verified 480p recipe) ----------
    out.append("\n# ---- HDMI TX physical region --------------------------------------------\n")
    out.append("# region_tx keeps the TMDS serializer next to the GTP output pins; the\n")
    out.append("# board-verified 480p recipe carries the same overlay.\n")
    out.append("define_global_attribute {PAP_REGION} {region_tx(0,60,105,125)[CLMA,CLMS];}\n")
    out.append("define_attribute {i:u_hdmi_tx.u_tx} {PAP_REGION} {region_tx}\n")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(out), encoding="utf-8")
    print(f"wrote {OUT} ({len(out)} blocks, {OUT.stat().st_size} bytes)")
    if missing:
        print("unhandled ports:", missing)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
