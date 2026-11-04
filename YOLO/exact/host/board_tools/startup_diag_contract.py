"""Read the exact linked ELF/MEM, derive startup expectations, and check safe TCM ownership."""
from pathlib import Path
import argparse,hashlib,json,re,struct,zlib

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()


def inspect(firmware):
 firmware=Path(firmware).resolve();fw=json.loads(firmware.read_text());elf=firmware.parent/'monitor.elf';raw=elf.read_bytes()
 if raw[:6]!=b'\x7fELF\x01\x01':raise ValueError('Expected little endian ELF32')
 fields=struct.unpack_from('<16sHHIIIIIHHHHHH',raw)
 shoff,shent,shnum,shstr=fields[6],fields[11],fields[12],fields[13]
 sections=[struct.unpack_from('<10I',raw,shoff+i*shent)for i in range(shnum)]
 strings=raw[sections[shstr][4]:sections[shstr][4]+sections[shstr][5]]
 names={strings[s[0]:].split(b'\0',1)[0].decode():s for s in sections}
 ro=names['.rodata'];content=raw[ro[4]:ro[4]+ro[5]]
 symbols={}
 for s in sections:
  if s[1]!=2:continue
  table=sections[s[6]];strings2=raw[table[4]:table[4]+table[5]]
  for off in range(s[4],s[4]+s[5],s[9]):
   n,value,size,info,other,index=struct.unpack_from('<IIIBBH',raw,off)
   name=strings2[n:].split(b'\0',1)[0].decode()
   if name:symbols[name]=dict(address=value,bytes=size)
 if ro[3]!=0x20000000 or symbols['__rodata_start']['address']!=ro[3] or symbols['__rodata_end']['address']!=ro[3]+ro[5]:
  raise ValueError('Diagnostic rodata range differs from linked section')
 mem=firmware.parent/'coremark-dtcm.mem'
 binary=b''.join(struct.pack('<I',int(v,16))for v in mem.read_text().split())
 if binary[:len(content)]!=content:raise ValueError('Diagnostic normal MEM differs from ELF rodata')
 scratch=symbols['boot_tcm_scratch'];table=symbols['crc_table'];stack=symbols['__stack_top']['address'];end=symbols['__bss_end']['address']
 if scratch['bytes']!=256 or table['bytes']!=1024 or scratch['address']%32 or end>=stack or scratch['address']<ro[3]+ro[5]:
  raise ValueError('Diagnostic scratch/CRC layout violates bounded ownership')
 if not(scratch['address']+scratch['bytes']<=table['address'] or table['address']+table['bytes']<=scratch['address']):
  raise ValueError('Diagnostic scratch overlaps CRC table')
 crc=zlib.crc32(content)
 text=(f"SOC_TCM_DIAG v=1 build={fw['build_id']} rodata_bytes={len(content):08x} byte_crc={crc:08x} word_crc={crc:08x} table_crc=6fcf9e13 word_err=00000000 byte_err=00000000 first_word=ffffffff want=00000000 got=00000000 fault=00000000\r\n")
 return dict(scope='Exact linked image and owned TCM scratch contract; no RTL/board result',
  firmware_build_id=fw['build_id'],firmware_manifest_sha256=sha(firmware),ELF_sha256=sha(elf),
  DTCM_sha256=sha(mem),rodata_address=ro[3],rodata_bytes=len(content),expected_rodata_CRC32=crc,
  expected_startup_line=text,owned_scratch=scratch,CRC_table=table,BSS_end=end,stack_top=stack,layout_valid=True)


def verify_capture(raw,contract):
 expected=contract['expected_startup_line'].encode('ascii')
 if raw.count(expected)!=1:raise ValueError('Exact image-bound diagnostic line absent, altered, or duplicated')
 banner=('SOC_MONITOR_READY build='+contract['firmware_build_id']+' cpu_hz=70000000 protocol=1\r\n').encode()
 if expected+banner not in raw:raise ValueError('READY did not follow the complete passing diagnostic line')
 return dict(pass_result=True,scope='Image-bound physical startup diagnostic text; no DDR/model acceptance',
  capture_sha256=hashlib.sha256(raw).hexdigest(),expected_rodata_CRC32=contract['expected_rodata_CRC32'])


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--firmware',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--capture',type=Path);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);r=inspect(a.firmware)
 if a.capture:r['capture']=verify_capture(a.capture.read_bytes(),r)
 (a.out/'result.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items()if k!='expected_startup_line'},indent=2))


if __name__=='__main__':main()
