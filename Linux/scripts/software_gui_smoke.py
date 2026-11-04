#!/usr/bin/env python3
"""Exercise actual LVGL host rendering and command navigation; not FPGA proof."""
import hashlib, os, pathlib, subprocess, tempfile, time, struct, zlib
root=pathlib.Path(__file__).resolve().parents[1]
exe=root/'gui/build/rv32-gui'; out=root/'reports/gui_test';out.mkdir(parents=True,exist_ok=True)
results=[]
with tempfile.TemporaryDirectory(prefix='rv32-gui-') as temp:
 for page in ('home','status','settings'):
  fifo=pathlib.Path(temp)/'commands';image=out/(page+'.rgb565')
  with (out/(page+'.log')).open('w') as log:
   child=subprocess.Popen([str(exe),'--headless',str(image),'--fifo',str(fifo)],stdout=log,stderr=log)
   try:
    for _ in range(200):
     if fifo.exists():break
     if child.poll() is not None:raise RuntimeError('GUI exited early')
     time.sleep(.01)
    with fifo.open('w') as f:f.write(page+'\n')
    time.sleep(2.2 if page=='status' else .15)
    with fifo.open('w') as f:f.write('quit\n')
    if child.wait(timeout=5):raise RuntimeError('GUI failed')
   finally:
    if child.poll() is None:child.terminate();child.wait(timeout=5)
  data=image.read_bytes();assert len(data)==640*360*2 and len(set(data))>20
  rgb=bytearray()
  for (v,) in struct.iter_unpack('<H',data):
   rgb.extend((((v>>11)&31)*255//31,((v>>5)&63)*255//63,(v&31)*255//31))
  def chunk(kind,payload):
   return struct.pack('>I',len(payload))+kind+payload+struct.pack('>I',zlib.crc32(kind+payload)&0xffffffff)
  rows=b''.join(b'\0'+rgb[y*640*3:(y+1)*640*3] for y in range(360))
  png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',640,360,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
  (out/(page+'.png')).write_bytes(png)
  results.append(f'{page}: PASS bytes={len(data)} sha256={hashlib.sha256(data).hexdigest()}')
 assert len({(out/(page+'.rgb565')).read_bytes() for page in ('home','status','settings')})==3
text='\n'.join(results)+'\n';(out/'RESULTS.txt').write_text(text);print(text)
