#!/usr/bin/env python3
"""Make load manifest; NOT a board Flash programmer or a fake boot result.
The initramfs occupies 0x82400000..0x83efffff. Patch DT chosen properties before
building the final firmware if using this external-initramfs loading scheme.
"""
import json,hashlib,sys
from pathlib import Path
p=Path(sys.argv[1]); initrds=[n for n in ('rootfs.cpio','rootfs.cpio.gz') if (p/n).exists()]
if len(initrds)!=1:raise SystemExit('exactly one raw or gzip initramfs required')
layout=[('fw_jump.bin',0x80000000,0x00200000),('Image',0x80400000,0x01c00000),('rv32-rv32.dtb',0x82000000,0x00400000),(initrds[0],0x82400000,0x01b00000)]
r=[]
for name,addr,limit in layout:
 data=(p/name).read_bytes()
 if len(data)>limit:raise SystemExit(f'{name} exceeds reserved range')
 r.append(dict(file=name,address=f'0x{addr:08x}',size=len(data),sha256=hashlib.sha256(data).hexdigest()))
(p/'boot_manifest.json').write_text(json.dumps({'reset_pc':'0x80000000','hartid':0,'validated_on_board':False,'images':r},indent=2)+'\n')
print('Wrote image manifest; boot and physical RAM capacity require validation.')
