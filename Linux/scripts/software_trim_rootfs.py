#!/usr/bin/env python3
"""Remove only unused libstdc++ runtime entries from an immutable newc CPIO.
All retained archive records are copied byte-for-byte. Refuse if any retained
ELF DT_NEEDED refers to libstdc++; host GNU readelf is required.
"""
from pathlib import Path
import hashlib,json,subprocess,sys,tempfile
if len(sys.argv)!=3:raise SystemExit('usage: software_trim_rootfs.py INPUT.cpio NEW_OUTPUT.cpio')
src,dst=map(Path,sys.argv[1:]);assert not dst.exists(),'refusing existing output'
data=src.read_bytes();records=[];offset=0;removed=[];needed=[]
while data[offset:offset+6]==b'070701':
 start=offset;f=[int(data[offset+6+i*8:offset+14+i*8],16) for i in range(13)]
 name=data[offset+110:offset+110+f[11]-1].decode();offset=(offset+110+f[11]+3)&~3
 body=data[offset:offset+f[6]];offset=(offset+f[6]+3)&~3
 record=data[start:offset]
 if name.startswith('usr/lib/libstdc++.so'):
  assert f[4]==1,'unexpected hardlinked C++ runtime; do not remove'
  removed.append({'name':name,'payload_bytes':len(body),'record_sha256':hashlib.sha256(record).hexdigest()})
 else:
  records.append(record)
  if body[:4]==b'\x7fELF':
   with tempfile.NamedTemporaryFile() as tmp:
    tmp.write(body);tmp.flush();result=subprocess.check_output(['readelf','-d',tmp.name],text=True)
   deps=[l.strip() for l in result.splitlines() if 'NEEDED' in l]
   assert not any('libstdc++' in d for d in deps),name+' depends on removed runtime'
   needed.append({'name':name,'needed':deps})
 if name=='TRAILER!!!':break
else:raise SystemExit('missing newc trailer or unsupported format')
assert len(removed)==4,'expected exactly library, two symlinks and GDB helper'
out=b''.join(records);out+=b'\0'*((-len(out))%512);dst.write_bytes(out)
report={'input_sha256':hashlib.sha256(data).hexdigest(),'input_bytes':len(data),'output_sha256':hashlib.sha256(out).hexdigest(),'output_bytes':len(out),'removed':removed,'retained_elf_dependencies':needed,'retained_records_byte_identical':True}
dst.with_name(dst.name+'.trim.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'bytes':len(out),'sha256':report['output_sha256'],'removed':len(removed)}))
