"""Check the actual decoded UART bytes without diagnostic stdout interleaving."""
from pathlib import Path
import hashlib,json,os,re,subprocess,time
r=Path(__file__).resolve().parent
out=Path(os.environ.get('RV32_UART_CAPTURE_RESULTS',str(r/'reports'/('uart_capture_'+str(time.time_ns())))))
if not out.resolve().is_relative_to(r.resolve()):raise ValueError('Keep UART evidence inside this workspace')
out.mkdir()
model=r/'build/soc_capture/Vrv32_linux_soc_top'
tests=[(f'vm_{name}',r/f'build/vm/{name}.bin',1000000) for name in ('fencei','pagefault','asid','satp_fetch')]
tests += [('seip',r/'build/seip_soc/test.bin',800000),('timer',r/'build/timer_rate/timer.bin',4500000),('crypto',r/'build/crypto/crypto.bin',4000000)]
answers=(r/'build/crypto/expected_uart.txt').read_text().splitlines()
results=[]
for name,firmware,cycles in tests:
    dest=out/name;dest.mkdir()
    env=dict(os.environ,RV32_UART_CAPTURE=str(dest/'uart.raw'))
    env.pop('RV32_UART_SCRIPT',None);env.pop('RV32_UART_INPUT',None)
    started=time.monotonic()
    with (dest/'stdout.log').open('xb') as stdout,(dest/'stderr.log').open('xb') as stderr:
        proc=subprocess.run([str(model),str(firmware),str(cycles)],stdout=stdout,stderr=stderr,env=env,cwd=r)
    serial=(dest/'uart.raw').read_text().replace('\r','')
    good=proc.returncode==0
    if name.startswith('vm_'):good=good and serial.splitlines().count('PASS')==1 and 'FAIL' not in serial
    elif name=='seip':good=good and 'SEIP PERIPHERAL PASS' in serial and 'SEIP PERIPHERAL FAIL' not in serial
    elif name=='timer':
        m=re.search(r'TIMER PASS count/min/max/elapsed=([0-9a-f]{8}) ([0-9a-f]{8}) ([0-9a-f]{8}) ([0-9a-f]{8})\n',serial)
        if m:
            count,lo,hi,total=map(lambda x:int(x,16),m.groups())
            good=good and count==32 and 1000<=lo<=hi<=1500 and 32000<=total<=48000 and 'TIMER FAIL' not in serial
        else:good=False
    else:good=good and all(serial.splitlines().count(line)==1 for line in answers) and 'CRYPTO_FAIL' not in serial
    row={'test':name,'passed':bool(good),'exit_code':proc.returncode,'seconds':time.monotonic()-started,
         'firmware_sha256':hashlib.sha256(firmware.read_bytes()).hexdigest(),'model_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),
         'raw_uart_sha256':hashlib.sha256((dest/'uart.raw').read_bytes()).hexdigest(),'board_access':False}
    (dest/'result.json').write_text(json.dumps(row,indent=2),encoding='utf-8')
    results.append(row);print(name,'PASS' if good else 'FAIL',flush=True)
(out/'result.json').write_text(json.dumps({'passed':all(x['passed'] for x in results),'tests':results},indent=2),encoding='utf-8')
if not all(x['passed'] for x in results):raise SystemExit(1)
