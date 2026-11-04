"""Rebuild the candidate camera FDC from its pinned stage153 board/DDR FDC.

The base FDC retains the audited pin/electrical assignments. This script only
changes CPU/NPU clock topology and bounded CDC paths; it never cuts NPU paths.
Run with --check before PDS, or --write to restore the generated FDC.
"""
import argparse
import hashlib
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--write", action="store_true")
args = parser.parse_args()
here = Path(__file__).resolve().parent
base = here / "soc_board_camera_stage153_base.fdc"
output = here / "soc_board_camera.fdc"
base_bytes = base.read_bytes()
assert hashlib.sha256(base_bytes).hexdigest() == (
    "b1f6971d7eb9bd57e8e8eaf6caaa616833c9958ac854f1f3ced0c6b4241a9bfd"
), "The stage153 input FDC changed; audit its pin/DDR constraints first"
text = base_bytes.decode("utf-8")
eol = "\r\n"


def once(old: str, new: str) -> None:
    global text
    assert text.count(old) == 1, f"Expected exactly one occurrence: {old!r}"
    text = text.replace(old, new, 1)


once("# CPU GPLL uses 125 MHz differential ref; NPU/camera use 27 MHz.",
     "# CPU and NPU use separate 125 MHz-referenced GPLLs; board control uses 27 MHz.")
once("set_clock_uncertainty 0.1 [get_clocks cpu_clk_fast]" + eol,
     "set_clock_uncertainty 0.1 [get_clocks cpu_clk_fast]" + eol +
     "create_generated_clock -name npu_clk_fast -source [get_ports {clk_p}] "
     "[get_pins {u_npu_pll/clkout1}] -master_clock [get_clocks {ref_clk}] "
     "-multiply_by 39 -divide_by 25" + eol +
     "set_clock_uncertainty 0.1 [get_clocks npu_clk_fast]" + eol)
once("# Independent CPU oscillator to HMIC user domain: constrain routing of" + eol +
     "# Gray pointers, level synchronizers and held FIFO payloads to one" + eol +
     "# fastest-domain cycle. Do not cut these domains with clock_groups.",
     "# Board 27 MHz control to HMIC user domain. These are synchronizer paths;" + eol +
     "# constrain routing without hiding CDC or altering the functional clocks.")
once("# CPU<->DDR and CPU<->27 MHz synchronizers/FIFOs: one fastest-domain cycle.",
     "# NPU 195 MHz CDC FIFOs and level synchronizers to DDR and CPU." + eol +
     "set_max_delay 5.128205128 -datapath_only -from [get_clocks npu_clk_fast] -to [get_clocks ddrphy_sysclk]" + eol +
     "set_min_delay 0.0 -from [get_clocks npu_clk_fast] -to [get_clocks ddrphy_sysclk]" + eol +
     "set_max_delay 5.128205128 -datapath_only -from [get_clocks ddrphy_sysclk] -to [get_clocks npu_clk_fast]" + eol +
     "set_min_delay 0.0 -from [get_clocks ddrphy_sysclk] -to [get_clocks npu_clk_fast]" + eol +
     "set_max_delay 5.128205128 -datapath_only -from [get_clocks npu_clk_fast] -to [get_clocks cpu_clk_fast]" + eol +
     "set_min_delay 0.0 -from [get_clocks npu_clk_fast] -to [get_clocks cpu_clk_fast]" + eol +
     "set_max_delay 5.128205128 -datapath_only -from [get_clocks cpu_clk_fast] -to [get_clocks npu_clk_fast]" + eol +
     "set_min_delay 0.0 -from [get_clocks cpu_clk_fast] -to [get_clocks npu_clk_fast]" + eol +
     "# CPU<->DDR and CPU<->27 MHz synchronizers/FIFOs: one CPU cycle.")
generated = text.encode("utf-8")
if args.write:
    output.write_bytes(generated)
else:
    assert output.read_bytes() == generated, "Candidate FDC does not match the reproducible recipe"
print(f"FDC {'written' if args.write else 'verified'}: {output}; sha256={hashlib.sha256(generated).hexdigest()}")
