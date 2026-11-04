from pathlib import Path
import subprocess,os,json,hashlib,argparse,datetime,shutil
r=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Reproduce in a new directory without changing packaged evidence.')
parser.add_argument('--out',type=Path)
args=parser.parse_args()
model=r/'analysis/profile/model'
o=args.out.resolve() if args.out else r/'analysis/profile'/('reproduce_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
o.mkdir(parents=True,exist_ok=False)
shutil.copy2(r/'analysis/profile/run/firmware.hex',o/'firmware.hex')
env=dict(os.environ);env['PATH']='C:/Users/user/mingw64/bin;C:/tools/msys64/mingw64/bin;'+env['PATH']
cmd=['C:/Users/user/mingw64/bin/g++.exe','-O3','-std=c++17','-DVERILATOR=1','-DVM_COVERAGE=0','-DVM_SC=0','-DVM_TIMING=0','-DVM_TRACE=0',
 '-I'+str(model),'-IC:/tools/msys64/mingw64/share/verilator/include','-IC:/tools/msys64/mingw64/share/verilator/include/vltstd',
 str(r/'tools/algorithm_observer.cpp'),str(model/'verilated.o'),str(model/'verilated_threads.o'),str(model/'Vscore__ALL.a'),
 '-pthread','-lpthread','-latomic','-o',str(o/'algorithm_observer.exe')]
(o/'compile_command.json').write_text(json.dumps(cmd,indent=2))
with (o/'compile.log').open('xb') as log:
 p=subprocess.run(cmd,cwd=r,env=env,stdout=log,stderr=subprocess.STDOUT)
print('Observer compile',p.returncode,flush=True)
if p.returncode:raise SystemExit(p.returncode)
with (o/'rtl_debug.log').open('xb') as dbg,(o/'simulation.log').open('xb') as log:
 p=subprocess.run([str(o/'algorithm_observer.exe'),'10000000'],cwd=o,env=env,stdout=dbg,stderr=log)
uart=(o/'uart_raw.log').read_bytes()
result={'exit_code':p.returncode,'same_uart_as_previous_exact_rtl':uart==(r/'analysis/profile/reference_uart.log').read_bytes(),'serial_matches_accepted':uart==(o/'uart_debug.log').read_bytes(),'simulation_is_board_score':False,'simulation_log':(o/'simulation.log').read_text(encoding='utf-8'),'observer_sha256':hashlib.sha256((r/'tools/algorithm_observer.cpp').read_bytes()).hexdigest(),'model_library_sha256':hashlib.sha256((model/'Vscore__ALL.a').read_bytes()).hexdigest()}
(o/'validation.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2),flush=True)
assert p.returncode==0 and result['same_uart_as_previous_exact_rtl'] and result['serial_matches_accepted']
