#!/usr/bin/env python3
"""Execute the deployable Mario image on the actual CPU/cache/SoC RTL.
Checks the first four emulation frames and physical input/video interfaces.
DDR preload skips the UART transfer only. This is not a full-game RTL test.
"""
from pathlib import Path
import argparse,csv,datetime,hashlib,importlib.util,json,os,re,shutil,struct,subprocess,sys
from build_mario import ROOT,CROSS
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--reuse-model',type=Path);a=ap.parse_args()
 program=json.loads((ROOT/'build/LATEST_MARIO.json').read_text());host=json.loads((ROOT/'build/LATEST_HOST_GAMEPLAY.json').read_text())
 if not host['passed']:raise RuntimeError('Host gameplay test not passed')
 host_dir=ROOT/'build'/Path(host['evidence']).name
 for rel,digest in json.loads((host_dir/'sources.json').read_text()).items():
  if sha(ROOT/rel)!=digest:raise RuntimeError('Host source mismatch: '+rel)
 binary=ROOT/'build'/Path(program['binary']).parent.name/'mario.bin'
 if sha(binary)!=program['binary_sha256']:raise RuntimeError('Firmware SHA mismatch')
 out=ROOT/'build'/('mario_rtl_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir();print('EVIDENCE_DIR:',out,flush=True)
 src=out/'source';shutil.copytree(ROOT/'soc/rtl',src/'rtl');(src/'sim').mkdir();(src/'tests').mkdir()
 shutil.copy2(ROOT/'tests/tb_mario_bringup.sv',src/'sim/tb_mario_bringup.sv');shutil.copy2(ROOT/'soc/sim/bringup_main.cpp',src/'sim/bringup_main.cpp');shutil.copy2(ROOT/'tests/entry_ddr.c',src/'tests/entry_ddr.c')
 spec=importlib.util.spec_from_file_location('baseline',ROOT/'soc/sim/run_bringup_probe.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
 sys.path.insert(0,str(ROOT/'soc/sim'));from build_sim import SOURCES
 inputs=[src/s for s in SOURCES if s.startswith('rtl/')]+[src/'sim/tb_mario_bringup.sv',src/'sim/bringup_main.cpp']
 hashes={p.relative_to(src).as_posix():sha(p) for p in inputs};(out/'source_sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
 env=os.environ.copy();env['PATH']=';'.join(map(str,(base.MINGW,base.MSYS_BIN,base.VERILATOR.parent)))+';'+env['PATH'];env['PYTHON3']=sys.executable;env['VERILATOR_ROOT']=str(base.VERILATOR_ROOT);env['MAKE']=str(base.MINGW/'mingw32-make.exe')
 def run(cmd,cwd,log,timeout=None):
  with log.open('w',encoding='utf-8') as f:
   f.write('COMMAND '+subprocess.list2cmdline(list(map(str,cmd)))+'\n');f.flush()
   p=subprocess.run(list(map(str,cmd)),cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
  if p.returncode:raise RuntimeError(f'command exit {p.returncode}: {log}')
 exe=out/'obj/mario_rtl.exe'
 if a.reuse_model:
  if json.loads((a.reuse_model/'source_sha256.json').read_text())!=hashes:raise RuntimeError('RTL/model source mismatch')
  exe.parent.mkdir();shutil.copy2(a.reuse_model/'obj/mario_rtl.exe',exe)
 else:
  print('RTL_MODEL_BUILDING',flush=True)
  run([base.VERILATOR,'--cc','--exe','--build','-j','2','-DGAME_SIM','--top-module','tb_game_bringup','-Wno-fatal','-Wno-WIDTH','-Wno-lint','--Mdir',out/'obj','--build-jobs','1','-MAKEFLAGS',f'OPT_FAST=-O2 OPT_SLOW=-O1 PYTHON3={Path(sys.executable).as_posix()}','-CFLAGS','-O2 -DNDEBUG','-o','mario_rtl.exe',*inputs],out,out/'verilator_build.log')
 print('RTL_MODEL_READY',flush=True)
 app=out/'engine';app.mkdir();cross=str(CROSS);elf=app/'entry.elf'
 run([cross+'gcc.exe','-march=rv32im_zicsr','-mabi=ilp32','-mcmodel=medlow','-msmall-data-limit=0','-O2','-nostdlib','-nostartfiles','-ffunction-sections','-fdata-sections','-I'+str(ROOT/'port/include'),'-I'+str(ROOT/'soc/sw/include'),ROOT/'soc/sw/common/start.S',src/'tests/entry_ddr.c',ROOT/'port/board.c','-T',ROOT/'soc/sw/common/link.ld','-Wl,--gc-sections','-Wl,--no-relax','-lgcc','-o',elf],app,app/'entry_build.log')
 parts={}
 for section in ['text','rodata','data']:
  p=app/(section+'.bin');subprocess.run([cross+'objcopy.exe','-O','binary','--only-section=.'+section,str(elf),str(p)],check=True);parts[section]=p.read_bytes()
 for name,data in [('game-itcm.mem',parts['text']),('game-dtcm.mem',parts['rodata']+parts['data'])]:
  if len(data)>65536:raise RuntimeError('Entry SRAM overflow')
  (app/name).write_text(''.join(f'{v:016x}\n' for v in struct.unpack('<8192Q',data+bytes(65536-len(data)))) )
 data=binary.read_bytes();data+=bytes((-len(data))%32)
 memory='@200000\n'+''.join(data[i:i+32][::-1].hex()+'\n' for i in range(0,len(data),32))
 prefills=[];header=(ROOT/'port/include/soc_port.h').read_text()
 for name,color in [('SOC_VIDEO_FB0',0x39e7),('SOC_VIDEO_FB1',0xf81f)]:
  address=int(re.search(r'#define\s+'+name+r'\s+(0x[0-9a-fA-F]+)',header).group(1),16)
  if address<0x80000000 or address+640*360*2>0x88000000:raise RuntimeError('Test framebuffer outside behavioral DDR')
  memory+=f'@{(address-0x80000000)//32:x}\n'+((struct.pack('<H',color)*16)[::-1].hex()+'\n')*(640*360*2//32)
  prefills.append({'address':hex(address),'bytes':640*360*2,'initial_rgb565':hex(color)})
 (app/'mario-ddr.mem').write_text(memory)
 (out/'firmware.json').write_text(json.dumps({'program':program,'host_reference':host,'nonzero_framebuffer_prefills':prefills,'scope':'first four actual game-emulation frames, input and HDMI; DDR preload; not physical FPGA'},indent=2)+'\n')
 print('RTL_EXECUTING:',app/'simulation.log',flush=True)
 run([exe,'+mario_preload','+frames=160'],app,app/'simulation.log',2400)
 log=(app/'simulation.log').read_text();clean=re.sub(r'COVERAGE[^\r\n]*(?:\r?\n|$)','',log)
 clean=re.sub(r'\nSIM:[^\r\n]*\n','',clean);(app/'uart_normalized.log').write_text(clean)
 row=list(csv.DictReader((host_dir/'trace.csv').open()))[3]
 checkpoint=f"MARIO_CHECKPOINT RAM={int(row['ram_crc']):08x} PC={int(row['cpu_pc']):04x}"
 markers=['MARIO_RTL_TIMER64_ROLLOVER_PASS','SOC_MARIO_V03 DDR ENTRY','MARIO_ROM_OK; LITENES_READY','MARIO_VIDEO_READY',checkpoint,'MARIO_KEY=1 DOWN=1','MARIO_RTL_BOOT_INPUT_VIDEO_PASS']
 if not all(m in clean for m in markers) or any(m in clean for m in ['MARIO_VIDEO_TIMEOUT','MARIO_EXIT','UART_FRAMING_ERROR','TRAP=']):raise RuntimeError('Mario RTL acceptance markers failed')
 completed=re.search(r'MARIO_RTL_BOOT_INPUT_VIDEO_PASS: presented=(\d+)',clean)
 if completed is None or int(completed[1])==0:raise RuntimeError('HDMI did not complete a valid frame; black fallback is not display acceptance')
 from PIL import Image
 import numpy as np
 pix=np.asarray(Image.open(app/'mario_boot.ppm'));ref=np.asarray(Image.open(host_dir/'frame_0003.ppm'))
 mask=np.array([248,252,248],dtype=np.uint8);match=float(np.all((pix&mask)==(ref&mask),axis=2).mean())
 Image.fromarray(pix).save(app/'mario_boot.png')
 if match!=1.0:raise RuntimeError(f'Raster mismatch: {match}')
 result={'passed':True,'evidence':str(out),'program_sha256':sha(binary),'simulator_sha256':sha(exe),'first_four_emulation_frames_ram_crc_match':True,'nes_pc_match':True,'physical_button_pin_to_am_event':True,'hdmi_raster_match':match,'complete_hdmi_frames_presented':int(completed[1]),'nonzero_framebuffer_prefills':prefills,'prefilled_front_frame_matches_reference':True,'preloaded_memory_sha256':sha(app/'mario-ddr.mem'),'physical_board_verified':False,'full_gameplay_on_rtl_verified':False,'scope':'real CPU/cache/SoC RTL, first four emulation frames, UART/input/HDMI with nonzero framebuffer prefill; not title/gameplay or physical board qualification'}
 result.update(timer64_monotonic_across_low_word_rollover=True,timer_test_source_sha256=sha(src/'tests/entry_ddr.c'))
 (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');(ROOT/'build/LATEST_RTL.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));return 0
if __name__=='__main__':sys.exit(main())
