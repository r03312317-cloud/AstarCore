#!/usr/bin/env python3
"""Idempotent adaptation of official OpenSBI v1.6, no upstream notices removed."""
from pathlib import Path
import sys, shutil
root=Path(__file__).resolve().parents[1]; src=Path(sys.argv[1])
serial=src/'lib/utils/serial'
shutil.copyfile(root/'firmware/opensbi/fdt_serial_rv32.c',serial/'fdt_serial_rv32.c')
p=serial/'objects.mk'; t=p.read_text()
addition='\ncarray-fdt_serial_drivers-$(CONFIG_FDT_SERIAL_RV32) += fdt_serial_rv32\nlibsbiutils-objs-$(CONFIG_FDT_SERIAL_RV32) += serial/fdt_serial_rv32.o\n'
if 'fdt_serial_rv32.o' not in t:p.write_text(t+addition)
p=serial/'Kconfig'; t=p.read_text()
if 'config FDT_SERIAL_RV32' not in t:p.write_text(t.replace('if FDT_SERIAL\n','if FDT_SERIAL\n\nconfig FDT_SERIAL_RV32\n\tbool "RV32 UART FDT driver"\n\tdefault n\n'))
shutil.copyfile(root/'firmware/opensbi/defconfig',src/'platform/generic/configs/rv32_defconfig')
