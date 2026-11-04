#!/usr/bin/env python3
"""Tests local parsers using temporary fixtures; never opens a serial port."""
import hashlib,json,pathlib,subprocess,sys,tempfile
root=pathlib.Path(__file__).resolve().parent.parent
checks=0
def run(script,args,code):
 global checks
 r=subprocess.run([sys.executable,str(root/'scripts'/script),*map(str,args)],capture_output=True,text=True)
 assert r.returncode==code,(r.stdout,r.stderr);checks+=1;return r
with tempfile.TemporaryDirectory() as d:
 d=pathlib.Path(d);source=d/'uart';source.write_bytes(b'OpenSBI v1.6\r\nPlatform HART Count : 1\r\n')
 run('serial_smoke_capture.py',['--input',source,'--output',d/'out','--expect','OpenSBI v1.6'],0)
 j=json.loads((d/'out.json').read_text());assert j['source']=='offline-input' and not j['fpga_acceptance'];checks+=1
 assert j['sha256']==hashlib.sha256(source.read_bytes()).hexdigest();checks+=1
 run('serial_smoke_capture.py',['--input',source,'--output',d/'out'],2) # preserve existing evidence
 run('serial_smoke_capture.py',['--input',source,'--output',d/'no','--expect','Linux'],1)
 run('serial_smoke_capture.py',['--input',source,'--output',d/'short','--max-bytes','4'],2)
 m=d/'manifest.json';m.write_text('{}')
 run('check_board_inputs.py',['--manifest',m,'--report',d/'missing.json'],2)
 keys=['ddr_rtl','ddr_constraints','pin_constraints','clock_constraints','tmds_rtl','board_top','pds_project']
 fixture=d/'placeholder';fixture.write_text('test-only placeholder; not physical board input')
 m.write_text(json.dumps({k:['placeholder'] for k in keys}))
 run('check_board_inputs.py',['--manifest',m,'--report',d/'exists.json'],0)
 j=json.loads((d/'exists.json').read_text());assert j['status']=='INPUTS_EXIST_ONLY' and not j['pds_run'] and not j['board_validated'];checks+=1
 m.write_text('[');run('check_board_inputs.py',['--manifest',m],2)
print(f'PASS local utilities checks={checks}; offline fixtures only')
