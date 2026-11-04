#!/usr/bin/env python3
"""Install original RV32 drivers into pinned upstream Linux 6.12.9."""
import sys,shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1];src=Path(sys.argv[1])
def append(path,text,marker):
 t=path.read_text()
 if marker not in t:path.write_text(t+'\n'+text+'\n')
shutil.copyfile(root/'linux/rv32_uart.c',src/'drivers/tty/serial/rv32_uart.c')
append(src/'drivers/tty/serial/Makefile','obj-$(CONFIG_SERIAL_RV32) += rv32_uart.o','rv32_uart.o')
append(src/'drivers/tty/serial/Kconfig','''config SERIAL_RV32
 bool "RV32 custom UART v1"
 depends on OF
 select SERIAL_CORE
config SERIAL_RV32_CONSOLE
 bool "RV32 serial console"
 depends on SERIAL_RV32=y
 select SERIAL_CORE_CONSOLE
 select SERIAL_EARLYCON
''','config SERIAL_RV32')
shutil.copyfile(root/'linux/rv32_fb.c',src/'drivers/video/fbdev/rv32_fb.c')
append(src/'drivers/video/fbdev/Makefile','obj-$(CONFIG_FB_RV32) += rv32_fb.o','rv32_fb.o')
append(src/'drivers/video/fbdev/Kconfig','''config FB_RV32
 bool "RV32 RGB565 framebuffer"
 depends on FB && OF
 select FB_IOMEM_HELPERS
''','config FB_RV32')
