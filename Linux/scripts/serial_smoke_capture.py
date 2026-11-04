#!/usr/bin/env python3
"""Read-only serial evidence capture. Never transmits, downloads or flashes.
Offline --input verifies parser only, not hardware. Optional pyserial is needed
only for a real port. Requested DTR/RTS low does not guarantee glitch-free open.
"""
import argparse, hashlib, json, pathlib, time, sys

def main():
    p=argparse.ArgumentParser(description=__doc__)
    src=p.add_mutually_exclusive_group(required=True)
    src.add_argument('--port', help='Explicit local serial device, e.g. COM14 or /dev/ttyUSB0')
    src.add_argument('--input',type=pathlib.Path,help='Offline captured bytes; never a board test')
    p.add_argument('--baud',type=int,default=115200)
    p.add_argument('--seconds',type=float,default=60)
    p.add_argument('--max-bytes',type=int,default=64*1024*1024,help='Safety limit for evidence kept in memory')
    p.add_argument('--output',type=pathlib.Path,required=True)
    p.add_argument('--expect',action='append',default=[],help='Required UTF-8 substring; may be repeated')
    a=p.parse_args()
    if a.baud<=0 or a.max_bytes<=0 or not 0<a.seconds<=86400:p.error('baud must be positive and seconds in (0,86400]')
    if a.output.exists() or a.output.with_suffix(a.output.suffix+'.json').exists():
        p.error('output already exists; choose a new path to preserve earlier evidence')
    if a.input and a.input.resolve()==a.output.resolve():p.error('input and output must differ')
    a.output.parent.mkdir(parents=True,exist_ok=True)
    started=time.time();error=None;data=bytearray()
    try:
        if a.input:
            with a.input.open('rb') as f:data.extend(f.read(a.max_bytes+1))
            if len(data)>a.max_bytes:
                del data[a.max_bytes:];raise RuntimeError('capture byte limit exceeded; evidence is truncated')
        else:
            try:import serial
            except ImportError:raise RuntimeError('pyserial is required for a real port; install it locally from PyPI before running this script')
            dev=serial.Serial(port=None,baudrate=a.baud,bytesize=8,parity='N',stopbits=1,timeout=.1,xonxoff=False,rtscts=False,dsrdtr=False)
            dev.dtr=False;dev.rts=False;dev.port=a.port
            try:
                dev.open();deadline=time.monotonic()+a.seconds
                while time.monotonic()<deadline:
                    data.extend(dev.read(max(1,min(dev.in_waiting,65536,a.max_bytes-len(data)))))
                    if len(data)>=a.max_bytes:raise RuntimeError('capture byte limit reached; evidence may be truncated')
            finally:
                if dev.is_open:dev.close()
    except (Exception,KeyboardInterrupt) as e:error=f'{type(e).__name__}: {e}'
    # Exclusive create protects raw evidence if another process claimed the path.
    with a.output.open('xb') as f:f.write(data)
    matches={s:s.encode() in data for s in a.expect}
    result={'source':'offline-input' if a.input else 'serial-port','input':str(a.input) if a.input else None,
        'port':a.port,'baud':a.baud,'format':'8N1','requested_seconds':a.seconds,
        'elapsed_seconds':round(time.time()-started,3),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),
        'expected_substrings':matches,'error':error,'linux_boot_validated':False,'fpga_acceptance':False}
    summary=a.output.with_suffix(a.output.suffix+'.json')
    with summary.open('x') as f:json.dump(result,f,indent=2,ensure_ascii=False);f.write('\n')
    print(json.dumps(result,ensure_ascii=False))
    if error:return 2
    if not all(matches.values()):return 1
    print('CAPTURE COMPLETE; substring checks passed only. No Linux/FPGA acceptance implied.' if matches else 'CAPTURE COMPLETE; no success markers were requested.')
    return 0
if __name__=='__main__':sys.exit(main())
