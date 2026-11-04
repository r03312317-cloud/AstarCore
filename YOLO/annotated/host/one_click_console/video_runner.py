# 架构导读：video_runner。
# 执行独占上板流程，串联文件检查、SRAM 下载、DDR 检查、模型回读和连续识别。
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

# 维护本地状态/计算值：HERE = Path(__file__).resolve().parent。
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import run_real_camera as baseline
# 维护本地状态/计算值：b = baseline.b。
b = baseline.b
from continuous_session import run as continuous_run
from telemetry import SessionMonitor, Cancelled, TransferMeter

# 维护本地状态/计算值：NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)。
NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)



# 接口 decode_console，显式输入字段：raw。
# 本函数调用入口包括 raw.decode。
def decode_console(raw):
    # 迭代/等待条件：('utf-8-sig', 'gb18030')；退出由原循环条件及显式 break/异常决定。
    for encoding in ('utf-8-sig', 'gb18030'):
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            # 向调用方返回本步骤结果：raw.decode(encoding)。
            return raw.decode(encoding)
        except UnicodeDecodeError:
            pass
    # 向调用方返回本步骤结果：raw.decode('utf8', errors='replace')。
    return raw.decode('utf8', errors='replace')


# 接口 progress_values，显式输入字段：raw。
# 本函数调用入口包括 int, re.findall。
def progress_values(raw):
    # 向调用方返回本步骤结果：[int(x) for x in re.findall(rb'The Progress:[^\r\n]*?(\d{1,3})%', raw)。
    return [int(x) for x in re.findall(rb'The Progress:[^\r\n]*?(\d{1,3})%', raw)
            if 0 <= int(x) <= 100]


# 接口 ports，显式输入字段：无位置参数。
# 本函数调用入口包括 dict, b.list_ports.comports。
def ports():
    # 向调用方返回本步骤结果：[dict(device=p.device, description=p.description, hwid=p.hwid)。
    return [dict(device=p.device, description=p.description, hwid=p.hwid)
            for p in b.list_ports.comports() if (p.vid, p.pid) == (0x10c4, 0xea60)]


# 对象 LogWriter 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class LogWriter(io.TextIOBase):
    # 接口 __init__，显式输入字段：callback。
    # 该函数直接更新本地状态或返回计算值，具体返回对象见函数体。
    def __init__(self, callback):
        # 维护本地状态/计算值：self.callback = callback。
        self.callback = callback
        # 维护本地状态/计算值：self.pending = ''。
        self.pending = ''

    # 接口 write，显式输入字段：value。
    # 本函数调用入口包括 len, self.pending.split, line.strip, self.callback, line.rstrip。
    def write(self, value):
        # 维护本地状态/计算值：self.pending += value。
        self.pending += value
        # 迭代/等待条件：'\n' in self.pending；退出由原循环条件及显式 break/异常决定。
        while '\n' in self.pending:
            # 维护本地状态/计算值：line, self.pending = self.pending.split('\n', 1)。
            line, self.pending = self.pending.split('\n', 1)
            # 按条件 line.strip() 选择后续流程，保留原有异常和退出分支。
            if line.strip():
                self.callback(line.rstrip('\r'))
        # 向调用方返回本步骤结果：len(value)。
        return len(value)

    # 接口 flush，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.callback。
    def flush(self):
        # 按条件 self.pending 选择后续流程，保留原有异常和退出分支。
        if self.pending:
            self.callback(self.pending)
            # 维护本地状态/计算值：self.pending = ''。
            self.pending = ''


# 对象 Runner 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class Runner:
    # 接口 __init__，显式输入字段：uart, callback, seconds, root, verification。
    # 本函数调用入口包括 Path, threading.Event, self.out.mkdir, (self.out / 'events.jsonl').open, (self.out / 'session.log').open。
    def __init__(self, uart='', callback=None, seconds=None, root=HERE, verification='readback'):
        # 按条件 verification != 'readback' 选择后续流程，保留原有异常和退出分支。
        if verification != 'readback':
            # 停止当前调用并上报异常：raise ValueError('Unknown model verification mode')。
            raise ValueError('Unknown model verification mode')
        # 维护本地状态/计算值：self.root = Path(root)。
        self.root = Path(root)
        # 维护本地状态/计算值：self.uart = uart。
        self.uart = uart
        # 维护本地状态/计算值：self.seconds = seconds。
        self.seconds = seconds
        # 维护本地状态/计算值：self.verification = verification。
        self.verification = verification
        # 维护本地状态/计算值：output = sys.stdout。
        output = sys.stdout
        # 维护本地状态/计算值：self.callback = callback or (lambda value: output.write(json.dumps(value, ensure_ascii=False)+'\n'))。
        self.callback = callback or (lambda value: output.write(json.dumps(value, ensure_ascii=False)+'\n'))
        # 维护本地状态/计算值：self.cancel = threading.Event()。
        self.cancel = threading.Event()
        # 维护本地状态/计算值：self.out = self.root/'logs'/dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f')。
        self.out = self.root/'logs'/dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
        self.out.mkdir(parents=True)
        # 维护本地状态/计算值：self.events = (self.out/'events.jsonl').open('x', encoding='utf8')。
        self.events = (self.out/'events.jsonl').open('x', encoding='utf8')
        # 维护本地状态/计算值：self.logfile = (self.out/'session.log').open('x', encoding='utf8')。
        self.logfile = (self.out/'session.log').open('x', encoding='utf8')
        # 维护本地状态/计算值：self.lock = None。
        self.lock = None
        # 维护本地状态/计算值：self.locked = False。
        self.locked = False
        # 维护本地状态/计算值：self.child = None。
        self.child = None
        # 维护本地状态/计算值：self.stage_number = 0。
        self.stage_number = 0
        # 维护本地状态/计算值：self.mon = None。
        self.mon = None
        # 维护本地状态/计算值：self.claimed = False。
        self.claimed = False
        # 维护本地状态/计算值：self.last_save = 0.0。
        self.last_save = 0.0
        # 维护本地状态/计算值：self.last_saved_phase = None。
        self.last_saved_phase = None
        # 维护本地状态/计算值：self.state = dict(status='starting', phase='preflight', started_utc=b.utc(),。
        self.state = dict(status='starting', phase='preflight', started_utc=b.utc(),
                          firmware_build_id=b.BUILD, evidence=str(self.out),
                          process_id=os.getpid(), Flash_written=False,
                          restart_policy='Every manual start performs fresh SRAM configuration, identity, DDR, full model upload and the selected validation mode',
                          physical_panel_verified=False, hardware_started=False, model_receipts=[],
                          time_limit_seconds=seconds, pixel_loss_abort_ratio=0.10, recognition_idle_timeout=None,
                          scheduled_tasks_created=False)
        # 维护本地状态/计算值：self.state['model_verification_mode'] = verification。
        self.state['model_verification_mode'] = verification

    # 接口 save，显式输入字段：无位置参数。
    # 本函数调用入口包括 time.monotonic, b.utc, temporary.write_text, range, self.state.get。
    def save(self):
        # 维护本地状态/计算值：now = time.monotonic()。
        now = time.monotonic()
        # 按条件 self.state.get('phase') == 'camera_continuous_unbounded' and self.last_saved_phase == self.state.get('phase... 选择后续流程，保留原有异常和退出分支。
        if self.state.get('phase') == 'camera_continuous_unbounded' and self.last_saved_phase == self.state.get('phase') and now-self.last_save < 1:
            # 向调用方返回本步骤结果：None。
            return
        # 维护本地状态/计算值：self.state['report_updated_utc'] = b.utc()。
        self.state['report_updated_utc'] = b.utc()
        # 维护本地状态/计算值：temporary = self.out/'result.tmp'。
        temporary = self.out/'result.tmp' 
        temporary.write_text(json.dumps(self.state, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
        # 迭代/等待条件：range(8)；退出由原循环条件及显式 break/异常决定。
        for attempt in range(8):
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:
                os.replace(temporary, self.out/'result.json')
                # 维护本地状态/计算值：self.last_save = now。
                self.last_save = now
                # 维护本地状态/计算值：self.last_saved_phase = self.state.get('phase')。
                self.last_saved_phase = self.state.get('phase')
                # 向调用方返回本步骤结果：None。
                return
            except PermissionError:
                # 按条件 attempt == 7 选择后续流程，保留原有异常和退出分支。
                if attempt == 7:
                    # 停止当前调用并上报异常：raise。
                    raise
                time.sleep(.01)

    # 接口 emit，显式输入字段：kind。
    # 本函数调用入口包括 dict, self.events.write, self.events.flush, self.callback, dt.datetime.now().astimezone().isoformat。
    def emit(self, kind, **fields):
        # 维护本地状态/计算值：value = dict(kind=kind, time=dt.datetime.now().astimezone().isoformat(), **fields)。
        value = dict(kind=kind, time=dt.datetime.now().astimezone().isoformat(), **fields)
        self.events.write(json.dumps(value, ensure_ascii=False)+'\n')
        self.events.flush()
        self.callback(value)

    # 接口 log，显式输入字段：text。
    # 本函数调用入口包括 self.logfile.write, self.logfile.flush, self.emit, dt.datetime.now().strftime, dt.datetime.now。
    def log(self, text):
        self.logfile.write(dt.datetime.now().strftime('%H:%M:%S')+'  '+text+'\n')
        self.logfile.flush()
        self.emit('log', text=text)

    # 接口 stage，显式输入字段：number, title。
    # 本函数调用入口包括 self.state.update, self.save, self.emit, self.log。
    def stage(self, number, title):
        # 维护本地状态/计算值：self.stage_number = number。
        self.stage_number = number
        self.state.update(stage=number, phase=title)
        self.save()
        self.emit('stage', number=number, title=title)
        self.log(title)

    # 接口 checkpoint，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.cancel.is_set, Cancelled。
    def checkpoint(self):
        # 按条件 self.cancel.is_set() 选择后续流程，保留原有异常和退出分支。
        if self.cancel.is_set():
            # 停止当前调用并上报异常：raise Cancelled('已中断。本次记录已保留；点击“重新运行”会从完整烧录开始。')。
            raise Cancelled('已中断。本次记录已保留；点击“重新运行”会从完整烧录开始。')

    # 接口 claim，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.stage, b.LOCK.open, self.lock.seek, self.checkpoint, subprocess.run。
    def claim(self):
        self.stage(1, '连接串口与 JTAG')
        self.lock = b.LOCK.open('r+b')
        self.lock.seek(0)
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            msvcrt.locking(self.lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as exc:
            # 停止当前调用并上报异常：raise RuntimeError('板卡正在被其他窗口占用。请等待该任务结束后点击重新运行。') from exc。
            raise RuntimeError('板卡正在被其他窗口占用。请等待该任务结束后点击重新运行。') from exc
        self.locked = True
        selected = [p for p in ports() if p['device'].casefold() == self.uart.casefold()]
        # 按条件 len(selected) != 1 选择后续流程，保留原有异常和退出分支。
        if len(selected) != 1:
            # 停止当前调用并上报异常：raise RuntimeError('所选 CP210x 串口已断开，请刷新串口列表。')。
            raise RuntimeError('所选 CP210x 串口已断开，请刷新串口列表。')
        # 迭代/等待条件：('cdt_js.exe', 'cdt_cfg_shell.exe')；退出由原循环条件及显式 break/异常决定。
        for exe in ('cdt_js.exe', 'cdt_cfg_shell.exe'):
            result = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq '+exe, '/NH'],
                capture_output=True, timeout=15, creationflags=NO_WINDOW)
            # 按条件 result.returncode or not result.stdout or exe.encode() in result.stdout.lower() 选择后续流程，保留原有异常和退出分支。
            if result.returncode or not result.stdout or exe.encode() in result.stdout.lower():
                # 停止当前调用并上报异常：raise RuntimeError('已有 JTAG 工具正在运行；本窗口不会结束其他任务，请等待释放后重试。')。
                raise RuntimeError('已有 JTAG 工具正在运行；本窗口不会结束其他任务，请等待释放后重试。')
        self.checkpoint()
        shell = shutil.which('pwsh') or shutil.which('powershell')
        # 按条件 not shell 选择后续流程，保留原有异常和退出分支。
        if not shell:
            # 停止当前调用并上报异常：raise RuntimeError('未找到 PowerShell，无法确认 JTAG 设备。')。
            raise RuntimeError('未找到 PowerShell，无法确认 JTAG 设备。')
        command = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; @(Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'USB\\VID_0403&PID_6010\\*' } | Select-Object Status,FriendlyName,InstanceId) | ConvertTo-Json -Compress"
        result = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-Command', command],
            capture_output=True, timeout=60, creationflags=NO_WINDOW)
        # 按条件 result.returncode 选择后续流程，保留原有异常和退出分支。
        if result.returncode:
            # 停止当前调用并上报异常：raise RuntimeError('JTAG 枚举失败：'+decode_console(result.stderr))。
            raise RuntimeError('JTAG 枚举失败：'+decode_console(result.stderr))
        devices = json.loads(decode_console(result.stdout) or '[]')
        # 按条件 not isinstance(devices, list) 选择后续流程，保留原有异常和退出分支。
        if not isinstance(devices, list):
            devices = [devices]
        # 按条件 len(devices) != 1 or devices[0]['Status'] != 'OK' 选择后续流程，保留原有异常和退出分支。
        if len(devices) != 1 or devices[0]['Status'] != 'OK':
            # 停止当前调用并上报异常：raise RuntimeError('需要唯一且正常的 FTDI JTAG 下载器；请检查连接或移除其他下载器。')。
            raise RuntimeError('需要唯一且正常的 FTDI JTAG 下载器；请检查连接或移除其他下载器。')
        self.checkpoint()
        # 迭代/等待条件：range(65450, 65480)；退出由原循环条件及显式 break/异常决定。
        for number in range(65450, 65480):
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:
                # 资源上下文：with socket.socket() as sock:；离开上下文时执行对应清理约定。
                with socket.socket() as sock:
                    sock.bind(('127.0.0.1', number))
                self.jtag_port = number
                break
            except OSError:
                continue
        else:
            # 停止当前调用并上报异常：raise RuntimeError('找不到空闲的本地 JTAG 端口。')。
            raise RuntimeError('找不到空闲的本地 JTAG 端口。')
        self.state['devices'] = dict(uart=selected[0], jtag=devices[0], tcp_port=self.jtag_port)
        self.save()
        previous=b.STATUS.read_text(encoding='utf-8')
        (self.out/'previous_board_status.txt').write_text(previous,encoding='utf-8')
        b.STATUS.write_text(f'# Board resource lease / YOLO one-click console\n\nUTC {b.utc()}; PID {os.getpid()}; evidence {self.out}\n\n'+previous,encoding='utf-8')
        self.claimed=True
        self.log(f'已选择 {self.uart} · 115200 baud；JTAG 端口自动分配为 {self.jtag_port}。')

    # 接口 program，显式输入字段：qualification。
    # 本函数调用入口包括 self.stage, lease.write_text, self.state.update, self.save, self.log。
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
        # 资源上下文：with (self.out/'startup_console.log').open('xb') as stream:；离开上下文时执行对应清理约定。
        with (self.out/'startup_console.log').open('xb') as stream:
            self.child = subprocess.Popen(command, cwd=baseline.ROOT/'board_tools', stdout=stream,
                stderr=subprocess.STDOUT, creationflags=NO_WINDOW)
            # 迭代/等待条件：self.child.poll() is None；退出由原循环条件及显式 break/异常决定。
            while self.child.poll() is None:
                # 按条件 self.cancel.is_set() 选择后续流程，保留原有异常和退出分支。
                if self.cancel.is_set():
                    (self.out/'CANCEL_REQUESTED').touch(exist_ok=True)
                path = self.out/'startup/program.log'
                # 按条件 path.exists() 选择后续流程，保留原有异常和退出分支。
                if path.exists():
                    raw = path.read_bytes()
                    values = progress_values(raw)
                    # 按条件 values and values[-1] != seen_percent 选择后续流程，保留原有异常和退出分支。
                    if values and values[-1] != seen_percent:
                        seen_percent = values[-1]
                        self.emit('progress', channel='fpga', value=seen_percent, total=100)
                    # 按条件 not startup_stage and b'cfg_program -device_index 0 successfully' in raw 选择后续流程，保留原有异常和退出分支。
                    if not startup_stage and b'cfg_program -device_index 0 successfully' in raw:
                        startup_stage = True
                        self.stage(3, '确认固件启动与串口响应')
                time.sleep(.08)
        result_path = self.out/'startup/result.json'
        startup = json.loads(result_path.read_text(encoding='utf8')) if result_path.exists() else {}
        self.state['startup'] = startup
        self.save()
        self.checkpoint()
        # 按条件 self.child.returncode or not startup.get('pass') or (not startup.get('monitor_challenge', {}).get('valid')) 选择后续流程，保留原有异常和退出分支。
        if self.child.returncode or not startup.get('pass') or not startup.get('monitor_challenge', {}).get('valid'):
            detail = startup.get('error', {}).get('message', '详见 startup_console.log')
            # 停止当前调用并上报异常：raise RuntimeError('烧录或启动校验失败：'+detail)。
            raise RuntimeError('烧录或启动校验失败：'+detail)
        self.emit('progress', channel='fpga', value=100, total=100)
        self.stage(3, '固件身份、启动自检和串口握手通过')

    # 接口 on_camera_event，显式输入字段：kind。
    # 本函数调用入口包括 self.stage, self.emit, self.save, b.utc。
    def on_camera_event(self, kind, **values):
        # 按条件 kind == 'stopping' 选择后续流程，保留原有异常和退出分支。
        if kind == 'stopping':
            self.stage(7, '正在停止采集并核对板端状态')
        else:
            # 按条件 kind == 'link_wait' 选择后续流程，保留原有异常和退出分支。
            if kind == 'link_wait':
                self.state['link_state'] = 'waiting_for_reply'
                self.state['reply_wait_seconds'] = values['waited_seconds']
                self.save()
            # 按条件 kind in ('frame', 'telemetry', 'link_resumed') 选择后续流程，保留原有异常和退出分支。
            elif kind in ('frame', 'telemetry', 'link_resumed'):
                self.state['link_state'] = 'responding'
                self.state['last_response_utc'] = b.utc()
            self.emit(kind, **values)

    # 接口 transfer，显式输入字段：model。
    # 本函数调用入口包括 self.stage, TransferMeter, b.require, meter.snapshot, self.save。
    def transfer(self, model):
        self.stage(5, '传输模型并逐字节回读验证')
        assets=[(name,asset) for name,asset in model['assets'].items() if name!='input_hwc_i8']
        total=sum(asset['path'].stat().st_size for _,asset in assets)*2
        meter=TransferMeter()
        last_emit=0.0
        # 接口 progress，显式输入字段：opcode, count, duration。
        # 本函数调用入口包括 meter.record, time.monotonic, self.emit, len。
        def progress(opcode,count,duration):
            nonlocal last_emit
            stats=meter.record(opcode,count,duration)
            now=time.monotonic()
            self.state['model_transfer']=stats
            # 按条件 now - last_emit >= 0.15 or stats['transferred_bytes'] == total 选择后续流程，保留原有异常和退出分支。
            if now-last_emit>=.15 or stats['transferred_bytes']==total:
                last_emit=now
                self.emit('progress',channel='model',value=stats['transferred_bytes'],total=total,
                          assets=len(self.state['model_receipts']),total_assets=len(assets),
                          mode='readback',direction='上传' if opcode==3 else '回读',**stats)
        self.mon.checkpoint=self.checkpoint
        self.mon.transfer_progress=progress
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            # 迭代/等待条件：assets；退出由原循环条件及显式 break/异常决定。
            for name,asset in assets:
                self.checkpoint()
                receipt=b.upload(self.mon,asset['path'],asset['address'],asset['sha256'])
                self.state['model_receipts'].append(dict(name=name,**receipt))
                self.save()
                # 按条件 len(self.state['model_receipts']) % 32 == 0 选择后续流程，保留原有异常和退出分支。
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

    # 接口 run，显式输入字段：check_only。
    # 本函数调用入口包括 self.stage, baseline.preflight, self.checkpoint, self.log, self.claim。
    def run(self, check_only=False):
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            self.stage(0, '检查位流、固件、模型与依赖')
            qualification, model = baseline.preflight()
            self.state['qualification'] = qualification
            self.checkpoint()
            self.log('Reviewed Graph21 固件 '+b.BUILD+'、位流及 317 个模型资产校验通过。')
            # 按条件 check_only 选择后续流程，保留原有异常和退出分支。
            if check_only:
                self.state['status'] = 'offline_check_passed'
                # 向调用方返回本步骤结果：self.state。
                return self.state
            self.claim()
            self.program(qualification)
            self.checkpoint()
            # 资源上下文：with SessionMonitor.open(self.uart, self.out/'serial', timeout=20) as mon:；离开上下文时执行对应清理约定。
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
                # 资源上下文：with contextlib.redirect_stdout(writer):；离开上下文时执行对应清理约定。
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
            # 按条件 self.mon is not None and (not self.mon.failed) 选择后续流程，保留原有异常和退出分支。
            if self.mon is not None and not self.mon.failed:
                self.state['fault_snapshot']=baseline.passive_snapshot(self.mon,self.out/'fault_snapshot')
            self.log('运行未完成：'+message)
        finally:
            self.mon = None
            # The programmer has finished its own child-process cleanup before exit.
            if self.child is not None and self.child.poll() is None:
                (self.out/'CANCEL_REQUESTED').touch(exist_ok=True)
                self.child.wait()
            # 按条件 self.claimed 选择后续流程，保留原有异常和退出分支。
            if self.claimed:
                previous=b.STATUS.read_text(encoding='utf-8')
                b.STATUS.write_text(f'# Board resource released / YOLO one-click console\n\nUTC {b.utc()}; status {self.state["status"]}; evidence {self.out}\n\n'+previous,encoding='utf-8')
            # 按条件 self.lock is not None 选择后续流程，保留原有异常和退出分支。
            if self.lock is not None:
                # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
                try:
                    # 按条件 self.locked 选择后续流程，保留原有异常和退出分支。
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
        # 向调用方返回本步骤结果：self.state。
        return self.state


# 接口 main，显式输入字段：无位置参数。
# 本函数调用入口包括 argparse.ArgumentParser, parser.add_argument, parser.parse_args, Runner(args.uart, seconds=args.seconds, verification=args...。
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--board-approved', action='store_true')
    parser.add_argument('--uart', default='COM14')
    parser.add_argument('--seconds', type=float)
    parser.add_argument('--verification', choices=('readback',), default='readback')
    args = parser.parse_args()
    # 按条件 not args.check and (not args.board_approved) 选择后续流程，保留原有异常和退出分支。
    if not args.check and not args.board_approved:
        parser.error('Hardware access requires --board-approved or the manual start button')
    # 按条件 args.seconds is not None and args.seconds <= 0 选择后续流程，保留原有异常和退出分支。
    if args.seconds is not None and args.seconds <= 0:
        parser.error('--seconds must be positive')
    result = Runner(args.uart, seconds=args.seconds, verification=args.verification).run(check_only=args.check)
    # 向调用方返回本步骤结果：0 if result['status'] in ('stopped', 'offline_check_passed') else 1。
    return 0 if result['status'] in ('stopped', 'offline_check_passed') else 1


# 按条件 __name__ == '__main__' 选择后续流程，保留原有异常和退出分支。
if __name__ == '__main__':
    # 停止当前调用并上报异常：raise SystemExit(main())。
    raise SystemExit(main())
