"""Stage2 and Mario transfer over an already exclusively owned UART.
The original loader accepts one stage2 block; stage2 receives the whole game.
Wire format and CRC/readback acknowledgements match the proven PAL loader.
"""
from pathlib import Path
import hashlib,json,re,statistics,struct,time,zlib
def packet(cmd,address,payload=b'',size=None,crc=None):
 return struct.pack('<4sIIII',b'APAL',cmd,address,len(payload) if size is None else size,zlib.crc32(payload) if crc is None else crc)+payload
def upload_mario(port,qualification,out,capture_seconds):
 stage2=Path(qualification['stage2']).read_bytes();program=Path(qualification['binary']).read_bytes()
 if hashlib.sha256(stage2).hexdigest()!=qualification['stage2_sha256'] or hashlib.sha256(program).hexdigest()!=qualification['binary_sha256']:raise RuntimeError('Upload artifact changed')
 if not 0<len(stage2)<=1024 or not 0<len(program)<=0x800000:raise RuntimeError('Invalid image size')
 raw=bytearray();result={'flash_written':False,'game_rom_embedded':True,'binary_sha256':qualification['binary_sha256'],'physical_display_confirmed':False,'physical_gameplay_confirmed':False}
 def save():(out/'mario_runtime.json').write_text(json.dumps(result,indent=2)+'\n')
 try:
  with (out/'mario_uart.bin').open('wb') as log:
   def record(data):raw.extend(data);log.write(data);log.flush()
   def until(marker,since,seconds=10):
    deadline=time.monotonic()+seconds
    while marker not in raw[since:]:
     if time.monotonic()>deadline:raise TimeoutError('Missing '+repr(marker))
     data=port.read(256)
     if data:record(data)
   def send(data):
    if port.write(data)!=len(data):raise RuntimeError('Partial UART write')
    port.flush()
   def block(address,data):
    port.timeout=5;send(packet(1,address,data));ack=port.read(1);record(ack)
    if ack!=b'K':raise RuntimeError(f'CRC/readback ACK failed at {address:08x}: {ack!r}')
    port.timeout=.1
   def ping():
    before=len(raw);send(packet(0,0));until(b'APAL_READY V01 100MHz',before)
   port.reset_input_buffer();port.timeout=.1;ping()
   block(0x84000000,stage2);before=len(raw);send(packet(2,0x84000000,size=len(stage2),crc=zlib.crc32(stage2)))
   until(b'APAL_GO',before);until(b'APAL_STAGE2_READY',before);ping();result['stage2_ready']=True;save();print('MARIO: proven stage2 receiver ready',flush=True)
   started=time.monotonic()
   for offset in range(0,len(program),1024):block(0x84000000+offset,program[offset:offset+1024])
   before=len(raw);send(packet(2,0x84000000,size=len(program),crc=zlib.crc32(program)));until(b'APAL_GO',before,30)
   result['transfer_seconds']=round(time.monotonic()-started,3);result['status']='uploaded_and_jump_acknowledged';save()
   print('MARIO: game loaded; capturing real board UART',flush=True)
   capture_started=time.monotonic();deadline=capture_started+capture_seconds
   last_progress_at=None;last_progress_frame=-1;progress_events=[]
   while time.monotonic()<deadline:
    data=port.read(1024)
    if data:
     record(data);print(data.decode('utf-8',errors='replace'),end='',flush=True)
     for value in re.findall(rb'MARIO_FRAME=(\d+) DELTA=\d+ CYCLES=\d+',raw[-4096:]):
      frame=int(value)
      if frame>last_progress_frame:
       last_progress_frame=frame;last_progress_at=time.monotonic();progress_events.append({'capture_seconds':round(last_progress_at-capture_started,6),'emulation_frame':frame})
   result['last_progress_age_seconds']=round(time.monotonic()-last_progress_at,3) if last_progress_at is not None else None
   result['progress_recent_at_capture_end']=last_progress_at is not None and result['last_progress_age_seconds']<=5.0
   (out/'progress_timeline.json').write_text(json.dumps(progress_events,indent=2)+'\n')
  (out/'mario_uart.log').write_text(raw.decode('utf-8',errors='replace'),encoding='utf-8')
  from analyze_uart import analyze
  performance=analyze(bytes(raw));(out/'performance.json').write_text(json.dumps(performance,indent=2)+'\n')
  result['performance_report']=str(out/'performance.json')
  frames=[tuple(map(int,m)) for m in re.findall(rb'MARIO_FRAME=(\d+) DELTA=(\d+) CYCLES=(\d+)',raw)]
  rates=[100000000*delta/cycles for _,delta,cycles in frames if cycles]
  result.update(ddr_entry_seen=b'SOC_MARIO_V03 DDR ENTRY' in raw,rom_ready=b'MARIO_ROM_OK; LITENES_READY' in raw,video_ready=b'MARIO_VIDEO_READY' in raw,checkpoint_seen=b'MARIO_CHECKPOINT' in raw,runtime_progress_seen=len(frames)>=2 and frames[-1][0]>frames[0][0],last_emulation_frame=frames[-1][0] if frames else None,median_emulation_fps=round(statistics.median(rates),2) if rates else None,keys_seen=sorted({int(x) for x in re.findall(rb'MARIO_KEY=(\d+)',raw)}))
  result['checkpoint_matches_reference']=qualification['expected_checkpoint'].encode() in raw
  if not result['checkpoint_matches_reference']:raise RuntimeError('Mario RAM/PC checkpoint differs from the verified reference')
  if any(x in raw for x in [b'MARIO_VIDEO_TIMEOUT',b'MARIO_VIDEO_BAD_REQUEST',b'MARIO_ROM_REJECTED',b'MARIO_EXIT',b'TRAP=']):raise RuntimeError('Board runtime reported an error')
  if not all(result[k] for k in ['ddr_entry_seen','rom_ready','video_ready','checkpoint_seen','runtime_progress_seen']):raise RuntimeError('Mario board startup/progress evidence incomplete')
  if not result['progress_recent_at_capture_end']:raise RuntimeError('Game progress absent for more than five seconds at capture end; check power/reset/disconnection versus runtime stall')
  result['status']='uart_startup_and_progress_verified';save();return result
 except Exception as exc:result.update(status='failed',error=str(exc));save();raise
