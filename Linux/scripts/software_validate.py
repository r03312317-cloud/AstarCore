#!/usr/bin/env python3
"""Reject mismatched ELF class/ISA flags and unsupported kernel options."""
from pathlib import Path
import struct,sys,json
if len(sys.argv)<3:raise SystemExit('usage: software_validate.py ELF KERNEL_CONFIG')
p=Path(sys.argv[1]);data=p.read_bytes();assert data[:4]==b'\x7fELF','not ELF'
assert data[4]==1,'must be ELF32';assert data[5]==1,'must be little endian'
assert struct.unpack_from('<H',data,18)[0]==243,'not RISC-V'
flags=struct.unpack_from('<I',data,36)[0]
assert flags&7==0,f'RVC or non-soft-float ABI forbidden: flags={flags:#x}'
cfg=Path(sys.argv[2]).read_text().splitlines()
for needed in ['CONFIG_32BIT=y','CONFIG_MMU=y','CONFIG_SERIAL_RV32=y','CONFIG_SERIAL_RV32_CONSOLE=y']:
 assert needed in cfg,needed+' missing'
for forbidden in ['CONFIG_64BIT=y','CONFIG_RISCV_ISA_C=y','CONFIG_FPU=y','CONFIG_RISCV_ISA_V=y','CONFIG_EFI=y']:
 assert forbidden not in cfg,forbidden+' forbidden'
print(json.dumps({'elf':str(p),'class':'ELF32','flags':flags,'kernel_config':'PASS','note':'static compatibility check, not boot proof'}))
