# 架构导读：program_window_sram_70。
# 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
"""Monitor-only SRAM programming with explicit 5MHz discovery and AST1 challenge.

Copied from the successful Graph204 control programming path; no baud
investigation, BIST/CoreMark mode, or nonvolatile programming is exposed.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import secrets
import socket
import struct
import subprocess
import sys
import time
import zlib


# 接口 utc_now，显式输入字段：无位置参数。
# 本函数调用入口包括 datetime.datetime.now(datetime.timezone.utc).isoformat, datetime.datetime.now。
def utc_now():
    # 向调用方返回本步骤结果：datetime.datetime.now(datetime.timezone.utc).isoformat()。
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


# 接口 port_listening，显式输入字段：port。
# 本函数调用入口包括 socket.socket, connection.settimeout, connection.connect_ex。
def port_listening(port):
    # 资源上下文：with socket.socket() as connection:；离开上下文时执行对应清理约定。
    with socket.socket() as connection:
        connection.settimeout(0.5)
        # 向调用方返回本步骤结果：connection.connect_ex(('127.0.0.1', port)) == 0。
        return connection.connect_ex(('127.0.0.1', port)) == 0


# 维护本地状态/计算值：p = argparse.ArgumentParser(description=__doc__)。
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--bitstream', type=Path, required=True)
p.add_argument('--expected-sha256', required=True)
p.add_argument('--lease-record', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--port', required=True)
p.add_argument('--jtag-port', type=int, default=65420)
p.add_argument('--baud',type=int,choices=[115200],default=115200)
p.add_argument('--seconds', type=int, default=120,
               help='Maximum capture seconds after the programming process exits')
p.add_argument('--program-timeout', type=int, default=600,
               help='Absolute programming plus capture time limit, in seconds')
p.add_argument('--cpu-hz', type=int, choices=[70000000], default=70000000)
p.add_argument('--kind', choices=['monitor'], default='monitor')
p.add_argument('--expected-build', help='Required for monitor: firmware manifest build_id')
p.add_argument('--startup-diagnostic-firmware',type=Path,help='D1: verify exact ELF/MEM startup diagnostics before any AST1 challenge')
p.add_argument('--replace-active', action='store_true', help='Explicit manual rerun: reconfigure SRAM even when DONE=1')
p.add_argument('--cancel-file', type=Path, help='Cooperative cancellation request from the owning window')
p.add_argument('--pds-bin', type=Path,
               required=True)
# 维护本地状态/计算值：a = p.parse_args()。
a = p.parse_args()
# 按条件 not 1024 <= a.jtag_port <= 65535 选择后续流程，保留原有异常和退出分支。
if not 1024 <= a.jtag_port <= 65535:
    p.error('--jtag-port must be in 1024..65535')
# 维护本地状态/计算值：bit = a.bitstream.resolve()。
bit = a.bitstream.resolve()
# 维护本地状态/计算值：out = a.out.resolve()。
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=False)
# 维护本地状态/计算值：started = time.monotonic()。
started = time.monotonic()
# 维护本地状态/计算值：record = {'started_utc': utc_now(), 'kind': a.kind, 'port': a.port,。
record = {'started_utc': utc_now(), 'kind': a.kind, 'port': a.port,
          'jtag_server_port': a.jtag_port,
          'baud': a.baud, 'cpu_hz': a.cpu_hz, 'bitstream': str(bit),
          'capture_seconds_after_program': a.seconds,
          'program_and_capture_timeout_seconds': a.program_timeout,
          'program_target': 'FPGA SRAM; no nonvolatile programming',
          'physical_uart': True, 'previous_design_active': None}
# 维护本地状态/计算值：result = {'pass': False, 'status': 'in_progress', 'kind': a.kind,。
result = {'pass': False, 'status': 'in_progress', 'kind': a.kind,
          'program_process_exit': None, 'program_success_marker': False,
          'previous_design_active': None, 'startup_proven': False,
          'uart_bytes': 0, 'uart_terminal_check': False,
          'capture_complete': False, 'uart_content_validated': False,
          'cleanup_errors': [],
          'scope': 'SRAM-only startup evidence: target ID, configuration state and active AST1 identity. No DDR/model/HDMI acceptance.'}
# 维护本地状态/计算值：flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, 'CREATE_NO_WINDOW') else 0。
flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, 'CREATE_NO_WINDOW') else 0
# 维护本地状态/计算值：server = server_log = cfg = cfg_log = uart = events = scan_process = None。
server = server_log = cfg = cfg_log = uart = events = scan_process = None
# 维护本地状态/计算值：payload = bytearray()。
payload = bytearray()
# 维护本地状态/计算值：phase = 'initialization'。
phase = 'initialization'


# 接口 save_result，显式输入字段：无位置参数。
# 本函数调用入口包括 (out / 'result.json').write_text, json.dumps。
def save_result():
    (out/'result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')


# 接口 checkpoint，显式输入字段：无位置参数。
# 本函数调用入口包括 a.cancel_file.exists, KeyboardInterrupt。
def checkpoint():
    # 按条件 a.cancel_file and a.cancel_file.exists() 选择后续流程，保留原有异常和退出分支。
    if a.cancel_file and a.cancel_file.exists():
        # 停止当前调用并上报异常：raise KeyboardInterrupt('Operator requested cancellation; next run requires fresh SRAM configuration')。
        raise KeyboardInterrupt('Operator requested cancellation; next run requires fresh SRAM configuration')


# 接口 event，显式输入字段：name。
# 本函数调用入口包括 events.write, events.flush, utc_now, time.monotonic, json.dumps。
def event(name, **fields):
    # 维护本地状态/计算值：entry = {'utc': utc_now(), 'elapsed_seconds': time.monotonic()-started,。
    entry = {'utc': utc_now(), 'elapsed_seconds': time.monotonic()-started,
             'event': name, **fields}
    events.write(json.dumps(entry)+'\n')
    events.flush()


# 接口 cleanup，显式输入字段：name, operation。
# 本函数调用入口包括 operation, result['cleanup_errors'].append, type。
def cleanup(name, operation):
    # Each cleanup action must run even if a different resource refuses to close.
    try:
        operation()
    except BaseException as exc:
        result['cleanup_errors'].append({'resource': name,
                                         'error': f'{type(exc).__name__}: {exc}'})


# 接口 stop_process，显式输入字段：process。
# 本函数调用入口包括 process.terminate, process.poll, process.wait, process.kill。
def stop_process(process):
    # 按条件 process.poll() is not None 选择后续流程，保留原有异常和退出分支。
    if process.poll() is not None:
        # 向调用方返回本步骤结果：None。
        return
    process.terminate()
    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


# 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
try:
    # After creating a new output directory, record failed/interrupted attempts too.
    save_result()
    # 维护本地状态/计算值：events = (out/'uart_events.jsonl').open('a', encoding='utf-8')。
    events = (out/'uart_events.jsonl').open('a', encoding='utf-8')
    event('capture_attempt_started')
    # 按条件 not bit.is_file() or bit.suffix.lower() != '.sbit' 选择后续流程，保留原有异常和退出分支。
    if not bit.is_file() or bit.suffix.lower() != '.sbit':
        # 停止当前调用并上报异常：raise ValueError('Expected an existing .sbit file')。
        raise ValueError('Expected an existing .sbit file')
    # 按条件 a.seconds <= 0 or a.program_timeout <= 0 or a.cpu_hz <= 0 选择后续流程，保留原有异常和退出分支。
    if a.seconds <= 0 or a.program_timeout <= 0 or a.cpu_hz <= 0:
        # 停止当前调用并上报异常：raise ValueError('seconds, program-timeout and cpu-hz must be positive')。
        raise ValueError('seconds, program-timeout and cpu-hz must be positive')
    # 按条件 a.kind == 'monitor' and (a.expected_build is None or not re.fullmatch('[0-9a-f]{16}', a.expected_build)) 选择后续流程，保留原有异常和退出分支。
    if a.kind == 'monitor' and (a.expected_build is None or not re.fullmatch('[0-9a-f]{16}', a.expected_build)):
        # 停止当前调用并上报异常：raise ValueError('Monitor requires --expected-build with the firmware build ID')。
        raise ValueError('Monitor requires --expected-build with the firmware build ID')
    # 维护本地状态/计算值：record['expected_build'] = a.expected_build。
    record['expected_build'] = a.expected_build
    # 维护本地状态/计算值：record['bitstream_sha256'] = hashlib.sha256(bit.read_bytes()).hexdigest()。
    record['bitstream_sha256'] = hashlib.sha256(bit.read_bytes()).hexdigest()
    (out/'inputs.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    # 按条件 record['bitstream_sha256'] != a.expected_sha256.lower() 选择后续流程，保留原有异常和退出分支。
    if record['bitstream_sha256'] != a.expected_sha256.lower():
        # 停止当前调用并上报异常：raise ValueError('Bitstream does not match the reviewed SHA256')。
        raise ValueError('Bitstream does not match the reviewed SHA256')
    # 维护本地状态/计算值：lease_header = '\n'.join(a.lease_record.read_text(encoding='utf-8').splitlines()[:4])。
    lease_header = '\n'.join(a.lease_record.read_text(encoding='utf-8').splitlines()[:4])
    # 按条件 'Vision5MP / DDR_HDMI_STARTUP_02' not in lease_header or '空闲' in lease_header 选择后续流程，保留原有异常和退出分支。
    if 'Vision5MP / DDR_HDMI_STARTUP_02' not in lease_header or '空闲' in lease_header:
        # 停止当前调用并上报异常：raise RuntimeError('Current exclusive startup lease is absent')。
        raise RuntimeError('Current exclusive startup lease is absent')
    # 按条件 port_listening(a.jtag_port) 选择后续流程，保留原有异常和退出分支。
    if port_listening(a.jtag_port):
        # 停止当前调用并上报异常：raise RuntimeError('Existing JTAG server detected; do not attach to it')。
        raise RuntimeError('Existing JTAG server detected; do not attach to it')
    import serial

    checkpoint()
    # 维护本地状态/计算值：phase = 'open_uart'。
    phase = 'open_uart'
    # 维护本地状态/计算值：uart = serial.Serial()。
    uart = serial.Serial()
    # 维护本地状态/计算值：uart.port = a.port。
    uart.port = a.port
    # 维护本地状态/计算值：uart.baudrate = a.baud。
    uart.baudrate = a.baud
    # 维护本地状态/计算值：uart.timeout = 0.1。
    uart.timeout = 0.1
    # 维护本地状态/计算值：uart.dtr = False。
    uart.dtr = False
    # 维护本地状态/计算值：uart.rts = False。
    uart.rts = False
    uart.open()
    uart.reset_input_buffer()
    event('uart_buffer_cleared', boundary='port_open')
    # 维护本地状态/计算值：phase = 'start_jtag_server'。
    phase = 'start_jtag_server'
    # 按条件 not port_listening(a.jtag_port) 选择后续流程，保留原有异常和退出分支。
    if not port_listening(a.jtag_port):
        # 维护本地状态/计算值：server_log = (out/'jtag_server.log').open('w', encoding='utf-8')。
        server_log = (out/'jtag_server.log').open('w', encoding='utf-8')
        # 维护本地状态/计算值：server = subprocess.Popen(。
        server = subprocess.Popen(
            [str(a.pds_bin/'cdt_js.exe'), '-port', str(a.jtag_port), '-work_dir', str(out)],
            stdout=server_log, stderr=subprocess.STDOUT, creationflags=flags)
        # 迭代/等待条件：range(40)；退出由原循环条件及显式 break/异常决定。
        for _ in range(40):
            checkpoint()
            # 维护本地状态/计算值：server_text = (out/'jtag_server.log').read_text(encoding='utf-8', errors='replace')。
            server_text = (out/'jtag_server.log').read_text(encoding='utf-8', errors='replace')
            # 按条件 'Socket bind error' in server_text 选择后续流程，保留原有异常和退出分支。
            if 'Socket bind error' in server_text:
                # 停止当前调用并上报异常：raise RuntimeError(f'JTAG server could not bind requested port {a.jtag_port}')。
                raise RuntimeError(f'JTAG server could not bind requested port {a.jtag_port}')
            # 维护本地状态/计算值：advertised = re.search(r'use port\s*:\s*(\d+)', server_text)。
            advertised = re.search(r'use port\s*:\s*(\d+)', server_text)
            # 按条件 advertised and int(advertised.group(1)) != a.jtag_port 选择后续流程，保留原有异常和退出分支。
            if advertised and int(advertised.group(1)) != a.jtag_port:
                # 停止当前调用并上报异常：raise RuntimeError(f'JTAG server selected {advertised.group(1)}, not requested port {a.jtag_port}')。
                raise RuntimeError(f'JTAG server selected {advertised.group(1)}, not requested port {a.jtag_port}')
            # 按条件 port_listening(a.jtag_port) 选择后续流程，保留原有异常和退出分支。
            if port_listening(a.jtag_port):
                break
            # 按条件 server.poll() is not None 选择后续流程，保留原有异常和退出分支。
            if server.poll() is not None:
                # 停止当前调用并上报异常：raise RuntimeError('JTAG server exited')。
                raise RuntimeError('JTAG server exited')
            time.sleep(0.1)
        else:
            # 停止当前调用并上报异常：raise RuntimeError('JTAG server did not listen')。
            raise RuntimeError('JTAG server did not listen')

    # 维护本地状态/计算值：phase = 'scan_jtag'。
    phase = 'scan_jtag'
    # 维护本地状态/计算值：scan = out/'scan.tcl'。
    scan = out/'scan.tcl'
    # cfg_close shuts down the server. Disconnect only; EOF exits this client.
    scan.write_text('cfg_set_tcl_break -flag true\n'
                    f'cfg_connect -ip 127.0.0.1 -port {a.jtag_port}\n'
                    'cfg_set_cable_property -index 0 -freq 5MHz\ncfg_scan_chain\n'
                    'cfg_read_device_property -mode 0 -device_index 0\n'
                    'cfg_disconnect\n', encoding='utf-8')
    event('fresh_scan_started')
    # 资源上下文：with (out/'scan.log').open('wb') as scan_log:；离开上下文时执行对应清理约定。
    with (out/'scan.log').open('wb') as scan_log:
        # 维护本地状态/计算值：scan_process = subprocess.Popen(。
        scan_process = subprocess.Popen(
            [str(a.pds_bin/'cdt_cfg_shell.exe'), '-file', str(scan), '-work_dir', str(out)],
            stdout=scan_log, stderr=subprocess.STDOUT, creationflags=flags)
        # 维护本地状态/计算值：scan_deadline = time.monotonic() + 45。
        scan_deadline = time.monotonic() + 45
        # 迭代/等待条件：scan_process.poll() is None；退出由原循环条件及显式 break/异常决定。
        while scan_process.poll() is None:
            checkpoint()
            # 按条件 time.monotonic() > scan_deadline 选择后续流程，保留原有异常和退出分支。
            if time.monotonic() > scan_deadline:
                # 停止当前调用并上报异常：raise TimeoutError('Fresh JTAG scan deadline expired')。
                raise TimeoutError('Fresh JTAG scan deadline expired')
            time.sleep(.05)
    # 维护本地状态/计算值：scan_text = (out/'scan.log').read_bytes().decode('utf-8', errors='replace')。
    scan_text = (out/'scan.log').read_bytes().decode('utf-8', errors='replace')
    # Match the explicitly queried index, not an ID elsewhere in a chain log.
    identity = re.search(
        r'Executing\s*:\s*cfg_read_device_property -mode 0 -device_index 0\s*'
        r'.*?The ID value is:\s*(0x[0-9a-fA-F]+).*?'
        r'Executing\s*:\s*cfg_read_device_property -mode 0 -device_index 0 successfully\.',
        scan_text, re.S)
    # 维护本地状态/计算值：done_states = re.findall(r'This device configure situation \(done bit\):\s*([01])', scan_text)。
    done_states = re.findall(r'This device configure situation \(done bit\):\s*([01])', scan_text)
    # 按条件 scan_process.returncode or 'PG2L200H' not in scan_text or identity is None or (int(identity[1], 16) != 6305... 选择后续流程，保留原有异常和退出分支。
    if (scan_process.returncode or 'PG2L200H' not in scan_text or identity is None
            or int(identity[1], 16) != 0x00603899 or len(done_states) != 1):
        # 停止当前调用并上报异常：raise RuntimeError('Unexpected or ambiguous JTAG chain/device identity')。
        raise RuntimeError('Unexpected or ambiguous JTAG chain/device identity')
    # 维护本地状态/计算值：previous_active = done_states[0] == '1'。
    previous_active = done_states[0] == '1'
    # 维护本地状态/计算值：record['previous_design_active'] = result['previous_design_active'] = previous_active。
    record['previous_design_active'] = result['previous_design_active'] = previous_active
    # 维护本地状态/计算值：result['startup_proven'] = not previous_active。
    result['startup_proven'] = not previous_active
    # 维护本地状态/计算值：result['startup_attribution_note'] = (。
    result['startup_attribution_note'] = (
        'Fresh scan found DONE=1. The prior design can emit UART until programming '
        'takes effect; a second buffer clear and host receive timestamps cannot '
        'prove which design emitted every byte. Preserve programming/capture/content '
        'results, but withhold overall pass pending independent startup-boundary '
        'evidence.' if previous_active else
        'Fresh single-device scan found DONE=0; no configured prior design was active.')
    (out/'inputs.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    event('fresh_scan_completed', previous_design_active=previous_active)

    checkpoint()
    # 按条件 previous_active and (not a.replace_active) 选择后续流程，保留原有异常和退出分支。
    if previous_active and not a.replace_active:
        # 停止当前调用并上报异常：raise RuntimeError('FPGA DONE=1: existing design active; do not overwrite. Resolve ownership and power-cycl...。
        raise RuntimeError('FPGA DONE=1: existing design active; do not overwrite. Resolve ownership and power-cycle before starting.')
    # 维护本地状态/计算值：result['explicit_active_replacement'] = bool(previous_active and a.replace_active)。
    result['explicit_active_replacement'] = bool(previous_active and a.replace_active)
    event('manual_rerun_policy', replace_active=a.replace_active)

    # Assign the image only after the fresh, index-specific identity check.
    prog = out/'program.tcl'
    prog.write_text('cfg_set_tcl_break -flag true\n'
                   f'cfg_connect -ip 127.0.0.1 -port {a.jtag_port}\n'
                   'cfg_set_cable_property -index 0 -freq 5MHz\ncfg_scan_chain\n'
                   +f'cfg_assign_file -file {{{bit.as_posix()}}} -device_index 0\n'
                   +'cfg_set_device_property -device_index 0 -program 1\n'
                   'cfg_program -device_index 0\n'
                   'cfg_read_device_property -mode 3 -device_index 0\n'
                   'cfg_disconnect\n', encoding='utf-8')
    # 维护本地状态/计算值：cfg_log = (out/'program.log').open('w', encoding='utf-8')。
    cfg_log = (out/'program.log').open('w', encoding='utf-8')
    # 维护本地状态/计算值：phase = 'program_and_capture'。
    phase = 'program_and_capture'
    uart.reset_input_buffer()
    event('uart_buffer_cleared', boundary='after_fresh_scan_before_program')
    # 维护本地状态/计算值：cfg = subprocess.Popen(。
    cfg = subprocess.Popen(
        [str(a.pds_bin/'cdt_cfg_shell.exe'), '-file', str(prog), '-work_dir', str(out)],
        stdout=cfg_log, stderr=subprocess.STDOUT, creationflags=flags)
    event('program_process_started', pid=cfg.pid)
    # 维护本地状态/计算值：capture_start = time.monotonic()。
    capture_start = time.monotonic()
    # 维护本地状态/计算值：last_data = capture_start。
    last_data = capture_start
    # 维护本地状态/计算值：program_finished_at = None。
    program_finished_at = None
    # 维护本地状态/计算值：bytes_at_program_finish = None。
    bytes_at_program_finish = None
    # 维护本地状态/计算值：terminal = False。
    terminal = False
    # 资源上下文：with (out/'uart.bin').open('wb') as raw_uart:；离开上下文时执行对应清理约定。
    with (out/'uart.bin').open('wb') as raw_uart:
        # 迭代/等待条件：True；退出由原循环条件及显式 break/异常决定。
        while True:
            checkpoint()
            # 维护本地状态/计算值：now = time.monotonic()。
            now = time.monotonic()
            # 按条件 now - capture_start >= a.program_timeout 选择后续流程，保留原有异常和退出分支。
            if now-capture_start >= a.program_timeout:
                # 维护本地状态/计算值：result['capture_stop_reason'] = 'absolute_program_capture_timeout'。
                result['capture_stop_reason'] = 'absolute_program_capture_timeout'
                break
            # 按条件 program_finished_at is not None and now - program_finished_at >= a.seconds 选择后续流程，保留原有异常和退出分支。
            if program_finished_at is not None and now-program_finished_at >= a.seconds:
                # 维护本地状态/计算值：result['capture_stop_reason'] = 'post_program_capture_timeout'。
                result['capture_stop_reason'] = 'post_program_capture_timeout'
                break
            # 维护本地状态/计算值：data = uart.read(4096)。
            data = uart.read(4096)
            # 按条件 data 选择后续流程，保留原有异常和退出分支。
            if data:
                # 维护本地状态/计算值：offset = len(payload)。
                offset = len(payload)
                payload.extend(data)
                raw_uart.write(data)
                raw_uart.flush()
                # 维护本地状态/计算值：last_data = time.monotonic()。
                last_data = time.monotonic()
                event('uart_rx', offset=offset, length=len(data), data_hex=data.hex())
                print(data.decode('ascii', errors='backslashreplace'), end='', flush=True)
            # 维护本地状态/计算值：ended = cfg.poll() is not None。
            ended = cfg.poll() is not None
            # 按条件 ended and program_finished_at is None 选择后续流程，保留原有异常和退出分支。
            if ended and program_finished_at is None:
                # 维护本地状态/计算值：program_finished_at = time.monotonic()。
                program_finished_at = time.monotonic()
                # 维护本地状态/计算值：bytes_at_program_finish = len(payload)。
                bytes_at_program_finish = len(payload)
                # 维护本地状态/计算值：result['uart_bytes_at_program_finish'] = bytes_at_program_finish。
                result['uart_bytes_at_program_finish'] = bytes_at_program_finish
                # 维护本地状态/计算值：result['program_elapsed_seconds'] = program_finished_at-capture_start。
                result['program_elapsed_seconds'] = program_finished_at-capture_start
                event('program_process_exited', returncode=cfg.returncode)
            # Require a complete final line, not a truncated success prefix.
            pattern = rb'SOC_MONITOR_READY[^\r\n]*\r?\n'
            # 维护本地状态/计算值：terminal = re.search(pattern, payload) is not None。
            terminal = re.search(pattern, payload) is not None
            # 按条件 ended and terminal and (time.monotonic() - last_data > 2) 选择后续流程，保留原有异常和退出分支。
            if ended and terminal and time.monotonic()-last_data > 2:
                result['capture_stop_reason'] = 'complete_terminal_and_quiet'
                result['capture_complete'] = True
                break
            # 按条件 ended and cfg.returncode 选择后续流程，保留原有异常和退出分支。
            if ended and cfg.returncode:
                result['capture_stop_reason'] = 'program_process_failed'
                break
    cfg_log.flush()
    program_text = (out/'program.log').read_text(errors='replace')
    (out/'uart.txt').write_bytes(payload)
    program_ok = cfg.poll() == 0 and 'cfg_program -device_index 0 successfully' in program_text
    result['program_process_exit'] = cfg.poll()
    result['program_success_marker'] = program_ok
    result['uart_complete_terminal'] = terminal
    statuses = re.findall(r'Status Register:\s*(0x[0-9a-fA-F]+)', program_text)
    status_value = int(statuses[-1], 16) if statuses else None
    result['configuration_status'] = hex(status_value) if status_value is not None else None
    required_status_bits = (1<<18)|(1<<17)|(1<<16)|(1<<12)|(1<<10)|(1<<5)
    result['configuration_user_mode_ready'] = (status_value is not None
        and status_value & required_status_bits == required_status_bits
        and status_value & 0x1f == 0)
    # 按条件 a.kind == 'monitor' 选择后续流程，保留原有异常和退出分支。
    if a.kind == 'monitor':
        # 按条件 a.startup_diagnostic_firmware 选择后续流程，保留原有异常和退出分支。
        if a.startup_diagnostic_firmware:
            phase='image_bound_startup_diagnostic'
            from startup_diag_contract import inspect,verify_capture
            contract=inspect(a.startup_diagnostic_firmware)
            # 按条件 contract['firmware_build_id'] != a.expected_build 选择后续流程，保留原有异常和退出分支。
            if contract['firmware_build_id']!=a.expected_build:
                # 停止当前调用并上报异常：raise ValueError('Diagnostic firmware build differs from target SRAM identity')。
                raise ValueError('Diagnostic firmware build differs from target SRAM identity')
            (out/'startup_diagnostic_expected.json').write_text(json.dumps(contract,indent=2)+'\n')
            result['startup_diagnostic']=verify_capture(bytes(payload),contract)
            result['startup_diagnostic_firmware_manifest_sha256']=contract['firmware_manifest_sha256']
        phase = 'monitor_challenge'
        uart_ok = False
        result['expected_monitor_cpu_hz'] = a.cpu_hz
        result['scope'] = ('Physical SRAM configuration and fresh AST1 monitor challenge; '
                           'does not qualify DDR, NPU arithmetic, or a model.')
        # 按条件 program_ok and result['configuration_user_mode_ready'] 选择后续流程，保留原有异常和退出分支。
        if program_ok and result['configuration_user_mode_ready']:
            nonce = secrets.token_bytes(16)
            sequence = secrets.randbits(32)
            body = struct.pack('<4I', sequence, 1, 0, len(nonce))+nonce
            request = b'AST1'+body+struct.pack('<I', zlib.crc32(body))
            event('monitor_challenge_tx', data_hex=request.hex(), expected_build=a.expected_build)
            uart.write(request); uart.flush()
            response = bytearray(); deadline = time.monotonic()+5
            # 迭代/等待条件：time.monotonic() < deadline；退出由原循环条件及显式 break/异常决定。
            while time.monotonic()<deadline:
                checkpoint()
                chunk = uart.read(4096)
                # 按条件 chunk 选择后续流程，保留原有异常和退出分支。
                if chunk:
                    offset = len(payload); payload.extend(chunk); response.extend(chunk)
                    # 资源上下文：with (out/'uart.bin').open('ab') as raw_uart:；离开上下文时执行对应清理约定。
                    with (out/'uart.bin').open('ab') as raw_uart:
                        raw_uart.write(chunk)
                    event('monitor_challenge_rx', offset=offset, length=len(chunk), data_hex=chunk.hex())
                start = response.find(b'AST1')
                # 按条件 start >= 0 and len(response) >= start + 20 选择后续流程，保留原有异常和退出分支。
                if start>=0 and len(response)>=start+20:
                    seq,op,status,length = struct.unpack_from('<4I',response,start+4)
                    # 按条件 length > 1024 选择后续流程，保留原有异常和退出分支。
                    if length>1024:
                        break
                    # 按条件 len(response) >= start + 24 + length 选择后续流程，保留原有异常和退出分支。
                    if len(response)>=start+24+length:
                        frame = bytes(response[start:start+24+length])
                        data = frame[20:-4]
                        crc_ok = zlib.crc32(frame[4:-4])==struct.unpack_from('<I',frame,len(frame)-4)[0]
                        uart_ok = (crc_ok and seq==sequence and op==0x80000001 and status==0
                                   and len(data)==80 and data[48:64]==a.expected_build.encode('ascii')
                                   and data[64:]==nonce and struct.unpack_from('<I',data,4)[0]==a.cpu_hz)
                        result['monitor_challenge'] = {'valid':uart_ok,'sequence':sequence,
                            'nonce_hex':nonce.hex(),'response_hex':frame.hex(),'crc_valid':crc_ok}
                        break
            # 按条件 uart_ok 选择后续流程，保留原有异常和退出分支。
            if uart_ok:
                result['capture_complete'] = True
                result['startup_proven'] = True
                result['startup_attribution_note'] = (
                    'Successful shutdown reconfiguration with user mode enabled, followed by a fresh '
                    'random nonce response from the expected firmware build. This proves the current '
                    'configured firmware and a live UART receive/transmit path.')
    result['banner_observed'] = result['uart_terminal_check'] = terminal
    result['uart_content_validated'] = uart_ok
    result['pass'] = (program_ok and result['capture_complete']
                      and uart_ok and result['startup_proven'])
    result['status'] = ('passed' if result['pass'] else
                        'startup_attribution_unverified'
                        if program_ok and result['capture_complete'] and uart_ok else 'failed')
except BaseException as exc:
    result['pass'] = False
    result['status'] = 'interrupted' if isinstance(exc, KeyboardInterrupt) else 'error'
    result['error'] = {'phase': phase, 'type': type(exc).__name__, 'message': str(exc)}
    # 按条件 isinstance(exc, subprocess.TimeoutExpired) and exc.output 选择后续流程，保留原有异常和退出分支。
    if isinstance(exc, subprocess.TimeoutExpired) and exc.output:
        target = 'scan.log' if phase == 'scan_jtag' else 'challenge_timeout.log'
        output = exc.output.encode() if isinstance(exc.output, str) else exc.output
        cleanup('timeout_output', lambda: (out/target).write_bytes(output))
finally:
    # Save evidence before cleanup, then finalize it after each independent action.
    result['uart_bytes'] = len(payload)
    result['elapsed_seconds'] = time.monotonic()-started
    # 按条件 cfg is not None 选择后续流程，保留原有异常和退出分支。
    if cfg is not None:
        result['program_process_exit'] = cfg.poll()
    cleanup('uart.txt', lambda: (out/'uart.txt').write_bytes(payload))
    cleanup('initial_result', save_result)
    # 按条件 events is not None 选择后续流程，保留原有异常和退出分支。
    if events is not None:
        cleanup('final_event', lambda: event('capture_attempt_finished', status=result['status']))
    # 按条件 cfg is not None 选择后续流程，保留原有异常和退出分支。
    if cfg is not None:
        cleanup('program_process', lambda: stop_process(cfg))
    # 按条件 scan_process is not None 选择后续流程，保留原有异常和退出分支。
    if scan_process is not None:
        cleanup('scan_process', lambda: stop_process(scan_process))
    # 按条件 uart is not None 选择后续流程，保留原有异常和退出分支。
    if uart is not None:
        cleanup('uart', uart.close)
    # 按条件 server is not None 选择后续流程，保留原有异常和退出分支。
    if server is not None:
        cleanup('jtag_server', lambda: stop_process(server))
    # 迭代/等待条件：[('program_log', cfg_log), ('server_log', server_log), ('events', events)]；退出由原循环条件及显式 break/异常决定。
    for name, stream in [('program_log', cfg_log), ('server_log', server_log), ('events', events)]:
        # 按条件 stream is not None 选择后续流程，保留原有异常和退出分支。
        if stream is not None:
            cleanup(name, stream.close)
    # 按条件 result['cleanup_errors'] 选择后续流程，保留原有异常和退出分支。
    if result['cleanup_errors']:
        result['pass'] = False
        result['status'] = 'cleanup_error'
    result['finished_utc'] = utc_now()
    result['elapsed_seconds'] = time.monotonic()-started
    save_result()
    print(json.dumps(result, indent=2), flush=True)

# 停止当前调用并上报异常：raise SystemExit(0 if result['pass'] else 1)。
raise SystemExit(0 if result['pass'] else 1)


