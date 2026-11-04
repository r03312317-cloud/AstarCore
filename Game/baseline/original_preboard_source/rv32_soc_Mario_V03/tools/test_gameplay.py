#!/usr/bin/env python3
"""Execute the actual embedded game on the host; does not claim FPGA validation."""
from pathlib import Path
import argparse,csv,datetime,hashlib,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
CC=Path('C:/Users/user/mingw64/bin/gcc.exe')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--reference',type=Path,default=ROOT/'tests/reference_fullrate');args=ap.parse_args()
 out=ROOT/'build'/('host_gameplay_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
 sources=sorted((ROOT/'src/nes').glob('*.c'))+[ROOT/'port/runtime.c',ROOT/'port/input.c',ROOT/'port/render.c',ROOT/'port/crc32.c',ROOT/'tests/native_gameplay.c']
 exe=out/'gameplay.exe';cmd=[str(CC),'-O2','-std=gnu11','-g','-fno-strict-aliasing','-Wall','-Wextra','-Wno-unused-parameter','-I'+str(ROOT/'port/include'),'-I'+str(ROOT/'src/nes'),*[str(p) for p in sources],'-o',str(exe)]
 inputs=set(sources)|set((ROOT/'port/include').glob('*.h'))|set((ROOT/'src/nes').glob('*.h'))
 (out/'sources.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(inputs)},indent=2)+'\n')
 p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/'compile.log').write_bytes(p.stdout)
 if p.returncode:print(p.stdout.decode(errors='replace'));return p.returncode
 p=subprocess.run([str(exe),str(out)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);(out/'run.log').write_bytes(p.stdout)
 print(p.stdout.decode(errors='replace'));print('EVIDENCE:',out)
 if p.returncode:return p.returncode
 rows=[{k:int(v) for k,v in row.items()} for row in csv.DictReader((out/'trace.csv').open())]
 checks={'title_mode':rows[60]['mode']==0,'start_enters_game':rows[299]['mode']==1 and rows[299]['task']==3,'right_moves':rows[334]['x']>rows[299]['x'],
         'jump_rises':min(r['y'] for r in rows[335:390])<rows[334]['y']-8,'lands_again':rows[420]['y']==rows[334]['y'],
         'left_moves':rows[465]['x']<rows[439]['x'],'pause_stops_movement':len({r['x'] for r in rows[480:505]})==1,
         'resume_moves_again':rows[590]['x']>rows[559]['x'],'collision_loses_life':min(r['lives'] for r in rows[560:])<rows[559]['lives'],
         'video_updates':rows[-1]['presents']>=400}
 if args.reference:
  previous=list(csv.DictReader((args.reference/'trace.csv').open()))
  checks['all_frames_match_reference']=len(rows)==len(previous) and all(all(current[k]==int(v) for k,v in old.items()) for current,old in zip(rows,previous))
 from PIL import Image
 images=[]
 for ppm in out.glob('*.ppm'):
  png=ppm.with_suffix('.png');Image.open(ppm).save(png);images.append(str(png))
 result={'passed':all(checks.values()),'scope':'host CPU runs actual LiteNES and bundled game; shared input/scaler checked; not RV32 or physical FPGA',
         'checks':checks,'frames':len(rows),'evidence':str(out),'reference':str(args.reference) if args.reference else None,'screenshots':images,'collision_tested':True,'level_completion_tested':False,'physical_board_verified':False}
 (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');(ROOT/'build/LATEST_HOST_GAMEPLAY.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));return 0 if result['passed'] else 1
if __name__=='__main__':sys.exit(main())
