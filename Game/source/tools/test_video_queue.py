"""Check actual async video-driver control flow with deterministic device events.
Only register access, CPU counter reads and barriers are replaced by host hooks;
buffer ownership logic is copied from the deployable driver unchanged.
This checks software ownership, not RISC-V ordering or the physical device.
"""
from pathlib import Path
import datetime,hashlib,json,re,subprocess,sys
from build_mario import ROOT

def main():
 out=ROOT/'build'/('video_queue_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
 source=(ROOT/'port/board.c').read_text()
 code=source[:source.index('static uint32_t io_read32(')]+'''static uint32_t io_read32(uint32_t address){return test_io_read(address);}
static void io_write32(uint32_t address,uint32_t value){test_io_write(address,value);}
'''+source[source.index('static unsigned front;'):]
 start=code.index('uint64_t soc_cycles(void)');end=code.index('uint32_t soc_millis(void)')
 code=code[:start]+'uint64_t soc_cycles(void){return test_cycles();}\n'+code[end:]
 code,n=re.subn(r'__asm__ volatile\([^;]*\);','test_barrier();',code)
 assert n==2 and '__asm__' not in code
 code='''#include <stdint.h>
uint32_t test_io_read(uint32_t);
void test_io_write(uint32_t,uint32_t);
uint64_t test_cycles(void);
void test_barrier(void);
'''+code
 (out/'driver_original.c').write_text(source);(out/'driver_host.c').write_text(code)
 inputs=['port/board.c','port/include/soc_port.h','soc/sw/include/game_regs.h','tests/native_video_queue.c','tools/test_video_queue.py']
 hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in inputs}
 (out/'sources.json').write_text(json.dumps(hashes,indent=2)+'\n')
 cc=Path('C:/Users/user/mingw64/bin/gcc.exe')
 def run_case(name,driver,expected_pass):
  exe=out/(name+'.exe');cmd=[str(cc),'-O2','-std=c11','-Wall','-Wextra','-Werror','-I'+str(ROOT/'port/include'),'-I'+str(ROOT/'soc/sw/include'),str(driver),str(ROOT/'tests/native_video_queue.c'),'-o',str(exe)]
  p=subprocess.run(cmd,capture_output=True);(out/(name+'_compile.log')).write_bytes(p.stdout+p.stderr)
  if p.returncode:raise RuntimeError('Host video-driver build failed: '+str(out))
  p=subprocess.run([str(exe)],capture_output=True,timeout=10);(out/(name+'_run.log')).write_bytes(p.stdout+p.stderr)
  if (p.returncode==0)!=expected_pass:raise RuntimeError('Unexpected video-driver test result: '+str(out))
 run_case('correct',out/'driver_host.c',True)
 old='pending_address=addr;\n    if(io_read32(MMIO_GAME_VIDEO+GVID_ERROR))return -1;'
 assert code.count(old)==1
 mutant=code.replace(old,'if(io_read32(MMIO_GAME_VIDEO+GVID_ERROR))return -1;\n    pending_address=addr;')
 (out/'driver_error_ownership_mutation.c').write_text(mutant)
 run_case('error_ownership_mutation',out/'driver_error_ownership_mutation.c',False)
 result={'passed':True,'evidence':str(out),'buffer_ownership_cases_passed':7,'accepted_error_bug_detected_by_negative_control':True,'scope':'host executes actual video ownership logic with scripted MMIO/timer events; hardware ordering separately covered by CPU RTL','physical_board_verified':False}
 (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');(ROOT/'build/LATEST_VIDEO_QUEUE.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
