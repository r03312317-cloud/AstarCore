from pathlib import Path
from datetime import datetime
import os,subprocess,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'build/cache_tests'/datetime.now().strftime('%Y%m%d_%H%M%S_%f')
out.mkdir(parents=True,exist_ok=False)
rtl=ROOT/'rtl/rv32/core/rv32_memory_system.v'
test=ROOT/'sim/tests/i2w2_cache_test.cpp'
env=dict(os.environ,VERILATOR_ROOT='C:/tools/msys64/mingw64/share/verilator',MAKE='C:/Users/user/mingw64/bin/mingw32-make.exe')
env['PATH']='C:/Users/user/mingw64/bin;C:/tools/msys64/usr/bin;C:/tools/msys64/mingw64/bin;'+env['PATH']
cmd=['C:/tools/msys64/mingw64/bin/verilator_bin.exe','--cc','--exe','--build','--assert','-j','2','--unroll-count','1024','--unroll-stmts','100000','-Wno-fatal','--top-module','rv32_memory_system','--prefix','Vcache','-GI_INDEX_BITS=7','-GI_WAYS=2','-GD_INDEX_BITS=6','-GD_WAYS=2','-GENABLE_FAST_ICROSS=1','-Mdir',str(out/'obj'),'-CFLAGS','-O2 -std=c++17','-MAKEFLAGS','PYTHON3=D:/anaconda/python.exe OPT_FAST=-O2 SHELL=C:/tools/msys64/usr/bin/sh.exe','-o','cache_test.exe',str(rtl),str(test)]
with (out/'build.log').open('wb') as log:
    log.write((' '.join(cmd)+'\n').encode());log.flush()
    subprocess.run(cmd,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
r=subprocess.run([str(out/'obj/cache_test.exe')],cwd=out,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
(out/'simulation.log').write_bytes(r.stdout)
result={'passed':r.returncode==0,'rtl_sha256':hashlib.sha256(rtl.read_bytes()).hexdigest(),'test_sha256':hashlib.sha256(test.read_bytes()).hexdigest(),'exit_code':r.returncode}
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print('CACHE_EVIDENCE',out,flush=True)
print(r.stdout.decode(errors='replace'),flush=True)
raise SystemExit(r.returncode)
