"""One manually started, exclusive V21 camera session and its real progress."""
from pathlib import Path
import argparse
import contextlib
import datetime as dt
import io
import json
import msvcrt
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import traceback

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import run_real_camera as baseline
b = baseline.b
from continuous_session import run as continuous_run
from telemetry import SessionMonitor, Cancelled, TransferMeter

NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)



def decode_console(raw):
    for encoding in ('utf-8-sig', 'gb18030'):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            pass
    return raw.decode('utf8', errors='replace')


def progress_values(raw):
    return [int(x) for x in re.findall(rb'The Progress:[^\r\n]*?(\d{1,3})%', raw)
            if 0 <= int(x) <= 100]


def ports():
    return [dict(device=p.device, description=p.description, hwid=p.hwid)
            for p in b.list_ports.comports() if (p.vid, p.pid) == (0x10c4, 0xea60)]


class LogWriter(io.TextIOBase):
    def __init__(self, callback):
        self.callback = callback
        self.pending = ''

    def write(self, value):
        self.pending += value
        while '\n' in self.pending:
            line, self.pending = self.pending.split('\n', 1)
            if line.strip():
                self.callback(line.rstrip('\r'))
        return len(value)

    def flush(self):
        if self.pending:
            self.callback(self.pending)
            self.pending = ''


class Runner:
    def __init__(self, uart='', callback=None, seconds=None, root=HERE, verification='readback'):
        if verification != 'readback':
            raise ValueError('Unknown model verification mode')
        self.root = Path(root)
        self.uart = uart
        self.seconds = seconds
        self.verification = verification
        output = sys.stdout
        self.callback = callback or (lambda value: output.write(json.dumps(value, ensure_ascii=False)+'\n'))
        self.cancel = threading.Event()
        self.out = self.root/'logs'/dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
        self.out.mkdir(parents=True)
        self.events = (self.out/'events.jsonl').open('x', encoding='utf8')
        self.logfile = (self.out/'session.log').open('x', encoding='utf8')
        self.lock = None
        self.locked = False
        self.child = None
        self.stage_number = 0
        self.mon = None
        self.claimed = False
        self.last_save = 0.0
        self.last_saved_phase = None
        self.state = dict(status='starting', phase='preflight', started_utc=b.utc(),
                          firmware_build_id=b.BUILD, evidence=str(self.out),
                          process_id=os.getpid(), Flash_written=False,
                          restart_policy='Every manual start performs fresh SRAM configuration, identity, DDR, full model upload and the selected validation mode',
                          physical_panel_verified=False, hardware_started=False, model_receipts=[],
                          time_limit_seconds=seconds, pixel_loss_abort_ratio=0.10, recognition_idle_timeout=None,
                          scheduled_tasks_created=False)
        self.state['model_verification_mode'] = verification

    def save(self):
        now = time.monotonic()
        if self.state.get('phase') == 'camera_continuous_unbounded' and self.last_saved_phase == self.state.get('phase') and now-self.last_save < 1:
            return
        self.state['report_updated_utc'] = b.utc()
        temporary = self.out/'result.tmp' 
        temporary.write_text(json.dumps(self.state, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
        for attempt in range(8):
            try:
                os.replace(temporary, self.out/'result.json')
                self.last_save = now
                self.last_saved_phase = self.state.get('phase')
                return
            except PermissionError:
                if attempt == 7:
                    raise
                time.sleep(.01)

    def emit(self, kind, **fields):
        value = dict(kind=kind, time=dt.datetime.now().astimezone().isoformat(), **fields)
        self.events.write(json.dumps(value, ensure_ascii=False)+'\n')
        self.events.flush()
        self.callback(value)

    def log(self, text):
        self.logfile.write(dt.datetime.now().strftime('%H:%M:%S')+'  '+text+'\n')
        self.logfile.flush()
        self.emit('log', text=text)

    def stage(self, number, title):
        self.stage_number = number
        self.state.update(stage=number, phase=title)
        self.save()
        self.emit('stage', number=number, title=title)
        self.log(title)

    def checkpoint(self):
        if self.cancel.is_set():
            raise Cancelled('已中断。本次记录已保留；点击“重新运行”会从完整烧录开始。')

    def claim(self):
        self.stage(1, '连接串口与 JTAG')
        self.lock = b.LOCK.open('r+b')
        self.lock.seek(0)
        try:
            msvcrt.locking(self.lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as exc:
            raise RuntimeError('板卡正在被其他窗口占用。请等待该任务结束后点击重新运行。') from exc
        self.locked = True
        selected = [p for p in ports() if p['device'].casefold() == self.uart.casefold()]
        if len(selected) != 1:
            raise RuntimeError('所选 CP210x 串口已断开，请刷新串口列表。')
        for exe in ('cdt_js.exe', 'cdt_cfg_shell.exe'):
            result = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq '+exe, '/NH'],
                capture_output=True, timeout=15, creationflags=NO_WINDOW)
            if result.returncode or not result.stdout or exe.encode() in result.stdout.lower():
                raise RuntimeError('已有 JTAG 工具正在运行；本窗口不会结束其他任务，请等待释放后重试。')
        self.checkpoint()
        shell = shutil.which('pwsh') or shutil.which('powershell')
        if not shell:
            raise RuntimeError('未找到 PowerShell，无法确认 JTAG 设备。')
        command = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; @(Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'USB\\VID_0403&PID_6010\\*' } | Select-Object Status,FriendlyName,InstanceId) | ConvertTo-Json -Compress"
        result = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-Command', command],
            capture_output=True, timeout=60, creationflags=NO_WINDOW)
        if result.returncode:
            raise RuntimeError('JTAG 枚举失败：'+decode_console(result.stderr))
        devices = json.loads(decode_console(result.stdout) or '[]')
        if not isinstance(devices, list):
            devices = [devices]
        if len(devices) != 1 or devices[0]['Status'] != 'OK':
            raise RuntimeError('需要唯一且正常的 FTDI JTAG 下载器；请检查连接或移除其他下载器。')
        self.checkpoint()
        for number in range(65450, 65480):
            try:
                with socket.socket() as sock:
                    sock.bind(('127.0.0.1', number))
                self.jtag_port = number
                break
            except OSError:
                continue
        else:
            raise RuntimeError('找不到空闲的本地 JTAG 端口。')
        self.state['devices'] = dict(uart=selected[0], jtag=devices[0], tcp_port=self.jtag_port)
        self.save()
        previous=b.STATUS.read_text(encoding='utf-8')
        (self.out/'previous_board_status.txt').write_text(previous,encoding='utf-8')
        b.STATUS.write_text(f'# Board resource lease / YOLO one-click console\n\nUTC {b.utc()}; PID {os.getpid()}; evidence {self.out}\n\n'+previous,encoding='utf-8')
        self.claimed=True
        self.log(f'已选择 {self.uart} · 115200 baud；JTAG 端口自动分配为 {self.jtag_port}。')

    def program(self, qualification):
        self.stage(2, '正在烧录 FPGA')
        lease = self.out/'lease.txt'
        lease.write_text('Vision5MP / DDR_HDMI_STARTUP_02\nExclusive video window under shared board lock\n', encoding='utf8')
        command = [sys.executable, '-B', '-X', 'utf8', str(baseline.ROOT/'board_tools/program_window_sram_70.py'),
            '--bitstream', qualification['bitstream']['path'], '--expected-sha256', qualification['bitstream']['sha256'],
            '--lease-record', str(lease), '--out', str(self.out/'startup'), '--port', self.uart,
            '--jtag-port', str(self.jtag_port), '--cpu-hz', '70000000', '--expected-build', b.BUILD,
            '--startup-diagnostic-firmware', str(b.FW/'manifest.json'), '--pds-bin', str(b.PDS),
            '--seconds', '45', '--program-timeout', '240', '--replace-active',
            '--cancel-file', str(self.out/'CANCEL_REQUESTED')]
        self.state.update(startup_command=command, hardware_started=True)
        self.save()
        self.log('重新运行会完整重配 SRAM，清除上一轮采集状态；配置 Flash 保持不变。')
        seen_percent = -1
        startup_stage = False
        with (self.out/'startup_console.log').open('xb') as stream:
            self.child = subprocess.Popen(command, cwd=baseline.ROOT/'board_tools', stdout=stream,
                stderr=subprocess.STDOUT, creationflags=NO_WINDOW)
            while self.child.poll() is None:
                if self.cancel.is_set():
                    (self.out/'CANCEL_REQUESTED').touch(exist_ok=True)
                path = self.out/'startup/program.log'
                if path.exists():
                    raw = path.read_bytes()
                    values = progress_values(raw)
                    if values and values[-1] != seen_percent:
                        seen_percent = values[-1]
                        self.emit('progress', channel='fpga', value=seen_percent, total=100)
                    if not startup_stage and b'cfg_program -device_index 0 successfully' in raw:
                        startup_stage = True
                        self.stage(3, '确认固件启动与串口响应')
                time.sleep(.08)
        result_path = self.out/'startup/result.json'
        startup = json.loads(result_path.read_text(encoding='utf8')) if result_path.exists() else {}
        self.state['startup'] = startup
        self.save()
        self.checkpoint()
        if self.child.returncode or not startup.get('pass') or not startup.get('monitor_challenge', {}).get('valid'):
            detail = startup.get('error', {}).get('message', '详见 startup_console.log')
            raise RuntimeError('烧录或启动校验失败：'+detail)
        self.emit('progress', channel='fpga', value=100, total=100)
        self.stage(3, '固件身份、启动自检和串口握手通过')

    def on_camera_event(self, kind, **values):
        if kind == 'stopping':
            self.stage(7, '正在停止采集并核对板端状态')
        else:
            if kind == 'link_wait':
                self.state['link_state'] = 'waiting_for_reply'
                self.state['reply_wait_seconds'] = values['waited_seconds']
                self.save()
            elif kind in ('frame', 'telemetry', 'link_resumed'):
                self.state['link_state'] = 'responding'
                self.state['last_response_utc'] = b.utc()
            self.emit(kind, **values)

    def transfer(self, model):
        self.stage(5, '传输模型并逐字节回读验证')
        assets=[(name,asset) for name,asset in model['assets'].items() if name!='input_hwc_i8']
        total=sum(asset['path'].stat().st_size for _,asset in assets)*2
        meter=TransferMeter()
        last_emit=0.0
        def progress(opcode,count,duration):
            nonlocal last_emit
            stats=meter.record(opcode,count,duration)
            now=time.monotonic()
            self.state['model_transfer']=stats
            if now-last_emit>=.15 or stats['transferred_bytes']==total:
                last_emit=now
                self.emit('progress',channel='model',value=stats['transferred_bytes'],total=total,
                          assets=len(self.state['model_receipts']),total_assets=len(assets),
                          mode='readback',direction='上传' if opcode==3 else '回读',**stats)
        self.mon.checkpoint=self.checkpoint
        self.mon.transfer_progress=progress
        try:
            for name,asset in assets:
                self.checkpoint()
                receipt=b.upload(self.mon,asset['path'],asset['address'],asset['sha256'])
                self.state['model_receipts'].append(dict(name=name,**receipt))
                self.save()
                if len(self.state['model_receipts'])%32==0:
                    self.log(f"模型回读校验 {len(self.state['model_receipts'])} / {len(assets)}")
        finally:
            self.mon.transfer_progress=None
            self.mon.checkpoint=None
        b.require(len(self.state['model_receipts'])==317,'Incomplete model load')
        stats=meter.snapshot()
        self.state['model_transfer']=stats
        self.state['model_transfer_seconds']=stats['elapsed_seconds']
        self.save()
        self.emit('progress',channel='model',value=total,total=total,assets=317,total_assets=317,
                  mode='readback',direction='完成',complete=True,**stats)
        self.log(f"模型上传与逐字节回读完成：{stats['elapsed_seconds']:.2f} 秒；平均 {stats['average_bytes_per_second']/1024:.2f} KiB/s。")

    def run(self, check_only=False):
        try:
            self.stage(0, '检查位流、固件、模型与依赖')
            qualification, model = baseline.preflight()
            self.state['qualification'] = qualification
            self.checkpoint()
            self.log('Reviewed Graph21 固件 '+b.BUILD+'、位流及 317 个模型资产校验通过。')
            if check_only:
                self.state['status'] = 'offline_check_passed'
                return self.state
            self.claim()
            self.program(qualification)
            self.checkpoint()
            with SessionMonitor.open(self.uart, self.out/'serial', timeout=20) as mon:
                self.mon = mon
                self.state['identity'] = mon.ping(b.BUILD)
                b.check_identity(self.state['identity'])
                mon.checkpoint = self.checkpoint
                self.stage(4, '检查 DDR 读写与地址独立性')
                self.state['DDR_tests'] = b.ddr_test(mon)
                self.transfer(model)
                self.checkpoint()
                _, raw = mon.request(22, 0)
                query = b.decode_query(raw)
                self.stage(6, '实时视频识别中')
                self.state['status'] = 'running'
                mon.observation_enabled=True
                mon.cancel_event=self.cancel
                mon.wait_callback=self.on_camera_event
                writer = LogWriter(self.log)
                with contextlib.redirect_stdout(writer):
                    continuous_run(mon, model, self.state, self.save, self.out, query,
                        seconds=self.seconds, mode='preview', stop_event=self.cancel,
                        on_event=self.on_camera_event)
                writer.flush()
                self.state['identity_after'] = mon.ping(b.BUILD)
                b.check_identity(self.state['identity_after'])
                self.state.update(status='stopped', phase='stopped_and_validated')
                self.log('板端已确认停止；再次运行将重新烧录并完整初始化。')
        except Cancelled as exc:
            unknown=bool(self.mon and self.mon.failed)
            self.state.update(status='connection_unknown' if unknown else 'cancelled', error=str(exc))
            self.log(str(exc))
        except Exception as exc:
            message=str(exc)
            self.state.update(status='failed', phase_at_error=self.state.get('phase'),
                              error=message, exception=str(exc), traceback=traceback.format_exc())
            if self.mon is not None and not self.mon.failed:
                self.state['fault_snapshot']=baseline.passive_snapshot(self.mon,self.out/'fault_snapshot')
            self.log('运行未完成：'+message)
        finally:
            self.mon = None
            # The programmer has finished its own child-process cleanup before exit.
            if self.child is not None and self.child.poll() is None:
                (self.out/'CANCEL_REQUESTED').touch(exist_ok=True)
                self.child.wait()
            if self.claimed:
                previous=b.STATUS.read_text(encoding='utf-8')
                b.STATUS.write_text(f'# Board resource released / YOLO one-click console\n\nUTC {b.utc()}; status {self.state["status"]}; evidence {self.out}\n\n'+previous,encoding='utf-8')
            if self.lock is not None:
                try:
                    if self.locked:
                        self.lock.seek(0)
                        msvcrt.locking(self.lock.fileno(), msvcrt.LK_UNLCK, 1)
                finally:
                    self.lock.close()
            self.state['finished_utc'] = b.utc()
            self.last_saved_phase=None
            self.save()
            self.emit('complete', result=self.state)
            self.events.close()
            self.logfile.close()
        return self.state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--board-approved', action='store_true')
    parser.add_argument('--uart', default='COM14')
    parser.add_argument('--seconds', type=float)
    parser.add_argument('--verification', choices=('readback',), default='readback')
    args = parser.parse_args()
    if not args.check and not args.board_approved:
        parser.error('Hardware access requires --board-approved or the manual start button')
    if args.seconds is not None and args.seconds <= 0:
        parser.error('--seconds must be positive')
    result = Runner(args.uart, seconds=args.seconds, verification=args.verification).run(check_only=args.check)
    return 0 if result['status'] in ('stopped', 'offline_check_passed') else 1


if __name__ == '__main__':
    raise SystemExit(main())
