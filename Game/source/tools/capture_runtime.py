"""Capture the already running game without sending bytes or resetting it."""
from pathlib import Path
import argparse,datetime,json,msvcrt,time
import serial
from serial.tools import list_ports
from program_mario import ROOT,LOCK,STATUS,utc
from analyze_uart import analyze

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--seconds',type=int,default=120);args=ap.parse_args()
    if not 1<=args.seconds<=600:raise ValueError('seconds must be 1..600')
    out=ROOT/'build/bringup'/datetime.datetime.now().strftime('capture_%Y%m%d_%H%M%S_%f');out.mkdir(parents=True)
    locked=False;port=None;raw=bytearray();lock=LOCK.open('r+b')
    result={'mode':'receive_only_no_reset_no_programming','started_utc':utc(),'evidence':str(out)}
    def status(message):STATUS.write_text(message+'\n\n'+STATUS.read_text(encoding='utf-8'),encoding='utf-8')
    try:
        lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1);locked=True
        status('# Board resource lease / rv32_soc_Mario_V03 UART capture\n\nUTC '+utc()+'; evidence '+str(out))
        ports=[p for p in list_ports.comports() if p.vid==0x10c4 and p.pid==0xea60]
        if len(ports)!=1:raise RuntimeError('Expected one CP210x UART, found '+str(len(ports)))
        port=serial.Serial(baudrate=115200,timeout=.1);port.dtr=False;port.rts=False;port.port=ports[0].device;port.open()
        result['port']=port.port;print('CAPTURE_READY: '+str(out),flush=True)
        end=time.monotonic()+args.seconds
        with (out/'mario_uart.bin').open('wb') as f:
            while time.monotonic()<end:
                data=port.read(1024)
                if data:raw.extend(data);f.write(data);f.flush()
        (out/'mario_uart.log').write_text(raw.decode('utf-8',errors='replace'),encoding='utf-8')
        report=analyze(bytes(raw));(out/'performance.json').write_text(json.dumps(report,indent=2)+'\n')
        result['status']='captured';print(json.dumps(report,indent=2),flush=True)
    except Exception as exc:result.update(status='failed',error=str(exc));raise
    finally:
        if port is not None:port.close()
        if locked:
            status('# Board resource released / rv32_soc_Mario_V03 UART capture released\n\nUTC '+utc()+'; evidence '+str(out))
            lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
        lock.close();result['finished_utc']=utc();(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
