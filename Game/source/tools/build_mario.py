#!/usr/bin/env python3
"""Build a standalone RV32IM Mario/LiteNES firmware with embedded ROM."""
from pathlib import Path
import datetime,hashlib,json,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
CROSS=Path.home()/'AppData/Roaming/xPacks/riscv-none-elf-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 out=ROOT/'build'/('mario_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir();(out/'obj').mkdir()
 cc=str(CROSS)+'gcc.exe';arch=['-march=rv32im_zicsr','-mabi=ilp32','-mcmodel=medany','-msmall-data-limit=0','-mstrict-align']
 includes=[ROOT/'port/include',ROOT/'src/nes',ROOT/'soc/sw/include']
 flags=arch+['--specs=nano.specs','-O2','-flto','-g','-std=gnu11','-ffunction-sections','-fdata-sections','-fno-strict-aliasing','-D_GNU_SOURCE','-Wall','-Wextra','-Wno-unused-parameter']+['-I'+str(p) for p in includes]
 sources=sorted((ROOT/'src/nes').glob('*.c'))+sorted(p for p in (ROOT/'port').glob('*.c') if p.name!='display.c')+[ROOT/'boot/mario_start.S']
 inputs=set(sources)|{ROOT/'port/ddr.ld'}
 for folder in includes:inputs.update(folder.glob('*.h'))
 frozen={}
 for p in sorted(inputs):
  rel=p.relative_to(ROOT);dest=out/'source'/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest);frozen[rel.as_posix()]=sha(p)
 (out/'input_sha256.json').write_text(json.dumps(frozen,indent=2)+'\n')
 records=[];print('BUILD_DIR:',out,flush=True)
 for i,p in enumerate(sources):
  obj=out/'obj'/f'{i:02d}_{p.stem}.o';cmd=[cc,*flags,'-c',str(p),'-o',str(obj)]
  run=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/f'{i:02d}_{p.stem}.log').write_bytes(run.stdout)
  records.append({'source':str(p.relative_to(ROOT)),'sha256':sha(p),'object':str(obj),'command':cmd,'exit':run.returncode})
  if run.returncode:print(run.stdout.decode(errors='replace'));return run.returncode
 (out/'sources.json').write_text(json.dumps(records,indent=2)+'\n')
 elf=out/'mario.elf';binary=out/'mario.bin'
 cmd=[cc,*arch,'--specs=nano.specs','-O2','-flto','-nostartfiles','-T',str(ROOT/'port/ddr.ld'),'-Wl,--gc-sections','-Wl,--no-relax','-Wl,-Map,'+str(out/'mario.map'),*[r['object'] for r in records],'-Wl,--start-group','-lc','-lm','-lgcc','-Wl,--end-group','-o',str(elf)]
 run=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/'link.log').write_bytes(run.stdout)
 if run.returncode:print(run.stdout.decode(errors='replace'));return run.returncode
 subprocess.run([str(CROSS)+'objcopy.exe','-O','binary',str(elf),str(binary)],check=True)
 size=subprocess.check_output([str(CROSS)+'size.exe',str(elf)],text=True);(out/'size.txt').write_text(size);print(size)
 result={'status':'BUILT_NOT_BOARD_VALIDATED','elf':str(elf),'binary':str(binary),'binary_bytes':binary.stat().st_size,'binary_sha256':sha(binary),'elf_sha256':sha(elf),'entry':'0x84000000','cpu_hz':100000000,'isa':'rv32im_zicsr/ilp32','embedded_rom':True,'audio':False,'physical_board_verified':False}
 (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');(ROOT/'build/LATEST_MARIO.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));return 0
if __name__=='__main__':sys.exit(main())
