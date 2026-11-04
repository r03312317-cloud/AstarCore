# 架构导读：board_monitor。
# AST1 串口传输与封包校验，保留原始 TX/RX 和命令序号，不自动重发命令。
"""Stop-and-wait AST1 host, with raw serial evidence and DDR readback verification.

This client never retries a command automatically, particularly NPU submissions.
Only the uncached 64 MiB shared DDR aperture is writable. Nothing is persisted
to FPGA configuration flash. Importing this module never opens a serial port.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import secrets
import struct
import time
import zlib

MAGIC = b'AST1'
MAX_DATA = 1024
DDR_BASE, DDR_END = 0x80000000, 0x88000000
FRAME_BYTES = 1280*720*2
TENSOR_BYTES = 640*640*3
PREPROCESS_ID = 0x4c423634
CONV2D_ID = 0x32435631
REQUANT_ID = 0x31515452
TENSOR_OPS_ID = 0x31504f54
GRAPH_ID = 0x31505247
DETECTION_ID = 0x31544544
TENSOR_FIELDS = ('kind', 'input_h', 'input_w', 'input_c', 'aux_c',
                 'kernel_h', 'kernel_w', 'stride_h', 'stride_w',
                 'pad_top', 'pad_left', 'pad_bottom', 'pad_right', 'param')
CONV2D_FIELDS = ('input_h', 'input_w', 'input_c', 'output_c',
                 'kernel_h', 'kernel_w', 'stride_h', 'stride_w',
                 'dilation_h', 'dilation_w', 'pad_top', 'pad_left',
                 'pad_bottom', 'pad_right', 'tile_m')
STATUS = ['OK', 'BAD_CRC', 'BAD_LENGTH', 'BAD_RANGE', 'RX_TIMEOUT',
          'BAD_COMMAND', 'DDR_UNAVAILABLE', 'NPU_BUSY', 'NPU_TIMEOUT',
          'NPU_ERROR', 'UART_ERROR', 'CAMERA_NOT_READY',
          'CAMERA_TIMEOUT', 'CAMERA_BAD_FRAME', 'CONV_BAD_SHAPE',
          'REQUANT_BAD_PARAMS', 'REQUANT_BIAS_OVERFLOW', 'TENSOR_BAD_SHAPE',
          'GRAPH_BAD_DESCRIPTOR', 'DETECT_BAD_PARAMS',
          'DETECT_CANDIDATE_OVERFLOW',
          'V2_SOFTWARE_ERROR','DISPLAY_BAD_STATE','DISPLAY_WRITE_ERROR',
          'DISPLAY_WRITE_TIMEOUT','V2_HARDWARE_ERROR','V2_HARDWARE_TIMEOUT',
          'HDMI_FRAME_ERROR','HDMI_FRAME_TIMEOUT','WINDOW_GATHER_ERROR',
          'WINDOW_GATHER_TIMEOUT','CONCAT_HARDWARE_ERROR',
          'CONCAT_HARDWARE_TIMEOUT']


# 对象 ProtocolError 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class ProtocolError(RuntimeError):
    pass


# 对象 MonitorStatusError 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class MonitorStatusError(ProtocolError):
    # 接口 __init__，显式输入字段：status, payload。
    # 本函数调用入口包括 super().__init__, super, len。
    def __init__(self, status, payload=b''):
        self.status, self.payload = status, payload
        super().__init__(STATUS[status] if status < len(STATUS) else f'STATUS_{status}')


# 接口 encode_packet，显式输入字段：sequence, opcode, argument, payload。
# 本函数调用入口包括 bytes, len, ValueError, struct.pack, zlib.crc32。
def encode_packet(sequence, opcode, argument, payload=b''):
    payload = bytes(payload)
    # 按条件 len(payload) > MAX_DATA 选择后续流程，保留原有异常和退出分支。
    if len(payload) > MAX_DATA:
        # 停止当前调用并上报异常：raise ValueError('Payload exceeds 1024 bytes')。
        raise ValueError('Payload exceeds 1024 bytes')
    body = struct.pack('<4I', sequence, opcode, argument, len(payload)) + payload
    # 向调用方返回本步骤结果：MAGIC + body + struct.pack('<I', zlib.crc32(body))。
    return MAGIC + body + struct.pack('<I', zlib.crc32(body))


# 接口 checked_range，显式输入字段：address, length。
# 本函数调用入口包括 ValueError, isinstance。
def checked_range(address, length):
    # 按条件 not (isinstance(address, int) and isinstance(length, int) and (DDR_BASE <= address < DDR_END) and (0 < leng... 选择后续流程，保留原有异常和退出分支。
    if not (isinstance(address, int) and isinstance(length, int) and
            DDR_BASE <= address < DDR_END and 0 < length <= DDR_END-address):
        # 停止当前调用并上报异常：raise ValueError('DDR range must be nonempty and entirely inside 0x80000000..0x83ffffff')。
        raise ValueError('DDR range must be nonempty and entirely inside 0x80000000..0x83ffffff')


# 接口 conv2d_layout，显式输入字段：shape。
# 本函数调用入口包括 any, dict, set, ValueError, s.values。
def conv2d_layout(shape):
    # 按条件 set(shape) != set(CONV2D_FIELDS) 选择后续流程，保留原有异常和退出分支。
    if set(shape) != set(CONV2D_FIELDS):
        # 停止当前调用并上报异常：raise ValueError(f'Conv2D shape must have exactly {CONV2D_FIELDS}')。
        raise ValueError(f'Conv2D shape must have exactly {CONV2D_FIELDS}')
    s = {key: shape[key] for key in CONV2D_FIELDS}
    # 按条件 any((not isinstance(value, int) or value < 0 or value > 4294967295 for value in s.values())) 选择后续流程，保留原有异常和退出分支。
    if any(not isinstance(value, int) or value < 0 or value > 0xffffffff
           for value in s.values()):
        # 停止当前调用并上报异常：raise ValueError('Conv2D shape fields must be uint32')。
        raise ValueError('Conv2D shape fields must be uint32')
    # 按条件 any((not s[key] for key in CONV2D_FIELDS if not key.startswith('pad_'))) 选择后续流程，保留原有异常和退出分支。
    if any(not s[key] for key in CONV2D_FIELDS if not key.startswith('pad_')):
        # 停止当前调用并上报异常：raise ValueError('Conv2D dimensions, stride and dilation must be nonzero')。
        raise ValueError('Conv2D dimensions, stride and dilation must be nonzero')
    # 按条件 s['output_c'] > 65535 or s['tile_m'] > 65535 选择后续流程，保留原有异常和退出分支。
    if s['output_c'] > 65535 or s['tile_m'] > 65535:
        # 停止当前调用并上报异常：raise ValueError('NPU output channels and tile rows must fit 16 bits')。
        raise ValueError('NPU output channels and tile rows must fit 16 bits')
    effective_h = (s['kernel_h']-1)*s['dilation_h']+1
    effective_w = (s['kernel_w']-1)*s['dilation_w']+1
    padded_h = s['input_h']+s['pad_top']+s['pad_bottom']
    padded_w = s['input_w']+s['pad_left']+s['pad_right']
    # 按条件 padded_h < effective_h or padded_w < effective_w 选择后续流程，保留原有异常和退出分支。
    if padded_h < effective_h or padded_w < effective_w:
        # 停止当前调用并上报异常：raise ValueError('Kernel does not fit padded input')。
        raise ValueError('Kernel does not fit padded input')
    h = (padded_h-effective_h)//s['stride_h']+1
    w = (padded_w-effective_w)//s['stride_w']+1
    rows, k = h*w, s['kernel_h']*s['kernel_w']*s['input_c']
    # 按条件 k > 65535 选择后续流程，保留原有异常和退出分支。
    if k > 65535:
        # 停止当前调用并上报异常：raise ValueError('NPU K must fit 16 bits')。
        raise ValueError('NPU K must fit 16 bits')
    sizes = dict(input_bytes=s['input_h']*s['input_w']*s['input_c'],
                 weight_bytes=k*s['output_c'],
                 output_bytes=rows*s['output_c']*4,
                 scratch_bytes=s['tile_m']*k)
    # 按条件 any((size > DDR_END - DDR_BASE for size in sizes.values())) 选择后续流程，保留原有异常和退出分支。
    if any(size > DDR_END-DDR_BASE for size in sizes.values()):
        # 停止当前调用并上报异常：raise ValueError('Conv2D buffer exceeds NPU-visible DDR aperture')。
        raise ValueError('Conv2D buffer exceeds NPU-visible DDR aperture')
    # 向调用方返回本步骤结果：dict(output_h=h, output_w=w, rows=rows, k=k, **sizes)。
    return dict(output_h=h, output_w=w, rows=rows, k=k, **sizes)


# 接口 tensor_i8_layout，显式输入字段：shape。
# 本函数调用入口包括 any, dict, set, ValueError, s.values。
def tensor_i8_layout(shape):
    # 按条件 set(shape) != set(TENSOR_FIELDS) 选择后续流程，保留原有异常和退出分支。
    if set(shape) != set(TENSOR_FIELDS):
        # 停止当前调用并上报异常：raise ValueError(f'Tensor shape must have exactly {TENSOR_FIELDS}')。
        raise ValueError(f'Tensor shape must have exactly {TENSOR_FIELDS}')
    s = {key: shape[key] for key in TENSOR_FIELDS}
    # 按条件 any((not isinstance(v, int) or v < 0 or v > 4294967295 for v in s.values())) 选择后续流程，保留原有异常和退出分支。
    if any(not isinstance(v, int) or v < 0 or v > 0xffffffff for v in s.values()):
        # 停止当前调用并上报异常：raise ValueError('Tensor shape fields must be uint32')。
        raise ValueError('Tensor shape fields must be uint32')
    h, w, c = s['input_h'], s['input_w'], s['input_c']
    # 按条件 not (0 < h <= 4096 and 0 < w <= 4096 and (0 < c <= 65535)) or s['param'] 选择后续流程，保留原有异常和退出分支。
    if not (0 < h <= 4096 and 0 < w <= 4096 and 0 < c <= 65535) or s['param']:
        # 停止当前调用并上报异常：raise ValueError('Tensor dimensions or reserved field invalid')。
        raise ValueError('Tensor dimensions or reserved field invalid')
    input_bytes = h*w*c
    # 按条件 not 0 < input_bytes <= DDR_END - DDR_BASE 选择后续流程，保留原有异常和退出分支。
    if not 0 < input_bytes <= DDR_END-DDR_BASE:
        # 停止当前调用并上报异常：raise ValueError('Tensor input exceeds shared DDR aperture')。
        raise ValueError('Tensor input exceeds shared DDR aperture')
    kind = s['kind']
    aux_bytes = 0
    # 按条件 kind == 1 选择后续流程，保留原有异常和退出分支。
    if kind == 1:
        ph = h+s['pad_top']+s['pad_bottom']
        pw = w+s['pad_left']+s['pad_right']
        # 按条件 s['aux_c'] or not 1 <= s['kernel_h'] <= 7 or (not 1 <= s['kernel_w'] <= 7) or (not 1 <= s['stride_h'] <= 4)... 选择后续流程，保留原有异常和退出分支。
        if (s['aux_c'] or not 1 <= s['kernel_h'] <= 7 or
                not 1 <= s['kernel_w'] <= 7 or
                not 1 <= s['stride_h'] <= 4 or
                not 1 <= s['stride_w'] <= 4 or
                any(s[k] > 7 for k in ('pad_top','pad_left','pad_bottom','pad_right')) or
                ph < s['kernel_h'] or pw < s['kernel_w']):
            # 停止当前调用并上报异常：raise ValueError('MaxPool shape invalid')。
            raise ValueError('MaxPool shape invalid')
        oh = (ph-s['kernel_h'])//s['stride_h']+1
        ow = (pw-s['kernel_w'])//s['stride_w']+1
        oc = c
    # 按条件 kind == 2 选择后续流程，保留原有异常和退出分支。
    elif kind == 2:
        # 按条件 s['aux_c'] or not 1 <= s['stride_h'] <= 4 or (not 1 <= s['stride_w'] <= 4) or (h * s['stride_h'] > 4096) or... 选择后续流程，保留原有异常和退出分支。
        if (s['aux_c'] or not 1 <= s['stride_h'] <= 4 or
                not 1 <= s['stride_w'] <= 4 or h*s['stride_h'] > 4096 or
                w*s['stride_w'] > 4096 or
                any(s[k] for k in ('kernel_h','kernel_w','pad_top','pad_left',
                                     'pad_bottom','pad_right'))):
            # 停止当前调用并上报异常：raise ValueError('Upsample shape invalid')。
            raise ValueError('Upsample shape invalid')
        oh, ow, oc = h*s['stride_h'], w*s['stride_w'], c
    # 按条件 kind == 3 选择后续流程，保留原有异常和退出分支。
    elif kind == 3:
        # 按条件 not 0 < s['aux_c'] <= 65535 - c or any((s[k] for k in ('kernel_h', 'kernel_w', 'stride_h', 'stride_w', 'pad... 选择后续流程，保留原有异常和退出分支。
        if (not 0 < s['aux_c'] <= 65535-c or
                any(s[k] for k in ('kernel_h','kernel_w','stride_h','stride_w',
                                     'pad_top','pad_left','pad_bottom','pad_right'))):
            # 停止当前调用并上报异常：raise ValueError('Concat shape invalid')。
            raise ValueError('Concat shape invalid')
        oh, ow, oc = h, w, c+s['aux_c']
        aux_bytes = h*w*s['aux_c']
    # 按条件 kind in (4, 5) 选择后续流程，保留原有异常和退出分支。
    elif kind in (4, 5):
        # 按条件 s['aux_c'] or any((s[k] for k in ('kernel_h', 'kernel_w', 'stride_h', 'stride_w', 'pad_top', 'pad_left', 'p... 选择后续流程，保留原有异常和退出分支。
        if (s['aux_c'] or any(s[k] for k in ('kernel_h','kernel_w','stride_h',
                                             'stride_w','pad_top','pad_left',
                                             'pad_bottom','pad_right'))):
            # 停止当前调用并上报异常：raise ValueError('LUT/Add shape invalid')。
            raise ValueError('LUT/Add shape invalid')
        oh, ow, oc = h, w, c
        aux_bytes = 256 if kind == 4 else input_bytes
    else:
        # 停止当前调用并上报异常：raise ValueError('Unknown INT8 tensor operator')。
        raise ValueError('Unknown INT8 tensor operator')
    output_bytes = oh*ow*oc
    # 按条件 not 0 < output_bytes <= DDR_END - DDR_BASE or aux_bytes > DDR_END - DDR_BASE 选择后续流程，保留原有异常和退出分支。
    if not 0 < output_bytes <= DDR_END-DDR_BASE or aux_bytes > DDR_END-DDR_BASE:
        # 停止当前调用并上报异常：raise ValueError('Tensor output/aux exceeds shared DDR aperture')。
        raise ValueError('Tensor output/aux exceeds shared DDR aperture')
    # 向调用方返回本步骤结果：dict(output_h=oh, output_w=ow, output_c=oc,。
    return dict(output_h=oh, output_w=ow, output_c=oc,
                input_bytes=input_bytes, aux_bytes=aux_bytes,
                output_bytes=output_bytes)


# 接口 sha，显式输入字段：data。
# 本函数调用入口包括 hashlib.sha256(data).hexdigest, hashlib.sha256。
def sha(data):
    # 向调用方返回本步骤结果：hashlib.sha256(data).hexdigest()。
    return hashlib.sha256(data).hexdigest()


# 对象 Monitor 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class Monitor:
    # 接口 __init__，显式输入字段：transport, evidence_dir, timeout。
    # 本函数调用入口包括 Path, self.out.mkdir, (self.out / 'serial_trace.jsonl').open, (self.out / 'rx.bin').open, (self.out / 'tx.bin').open。
    def __init__(self, transport, evidence_dir, timeout=8.0):
        self.transport, self.timeout = transport, timeout
        self.out = Path(evidence_dir)
        self.out.mkdir(parents=True, exist_ok=True)
        self.trace = (self.out/'serial_trace.jsonl').open('x', encoding='utf-8')
        self.rx_file = (self.out/'rx.bin').open('xb')
        self.tx_file = (self.out/'tx.bin').open('xb')
        self.sequence = secrets.randbits(31)
        self.buffer = bytearray()
        self.closed = False
        self.failed = False
        self.identity = None
        self.started = time.monotonic()

    @classmethod
    # 接口 open，显式输入字段：port, evidence_dir, timeout。
    # 本函数调用入口包括 serial.Serial, transport.open, cls, transport.close。
    def open(cls, port, evidence_dir, timeout=8.0):
        import serial
        transport = serial.Serial()
        transport.port, transport.baudrate = port, 115200
        transport.timeout, transport.write_timeout = 0.05, 2.0
        transport.dtr = transport.rts = False
        transport.open()
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            # 向调用方返回本步骤结果：cls(transport, evidence_dir, timeout)。
            return cls(transport, evidence_dir, timeout)
        except BaseException:
            transport.close()
            # 停止当前调用并上报异常：raise。
            raise

    # 接口 _record，显式输入字段：direction, data。
    # 本函数调用入口包括 raw.write, raw.flush, dict, self.trace.write, self.trace.flush。
    def _record(self, direction, data):
        # 按条件 not data 选择后续流程，保留原有异常和退出分支。
        if not data:
            # 向调用方返回本步骤结果：None。
            return
        raw = self.rx_file if direction == 'rx' else self.tx_file
        raw.write(data); raw.flush()
        event = dict(utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                     elapsed_seconds=time.monotonic()-self.started,
                     direction=direction, bytes=len(data), hex=data.hex())
        self.trace.write(json.dumps(event)+'\n'); self.trace.flush()

    # 接口 _fill，显式输入字段：count, deadline。
    # 本函数调用入口包括 len, self.transport.read, self._record, self.buffer.extend, time.monotonic。
    def _fill(self, count, deadline):
        # 迭代/等待条件：len(self.buffer) < count；退出由原循环条件及显式 break/异常决定。
        while len(self.buffer) < count:
            # 按条件 time.monotonic() >= deadline 选择后续流程，保留原有异常和退出分支。
            if time.monotonic() >= deadline:
                # 停止当前调用并上报异常：raise TimeoutError('AST1 reply deadline expired; no command retry was made')。
                raise TimeoutError('AST1 reply deadline expired; no command retry was made')
            chunk = self.transport.read(max(1, min(4096, count-len(self.buffer))))
            self._record('rx', chunk)
            self.buffer.extend(chunk)

    # 接口 _reply，显式输入字段：sequence, opcode, deadline。
    # 本函数调用入口包括 self._fill, struct.unpack, bytes, ProtocolError, zlib.crc32。
    def _reply(self, sequence, opcode, deadline):
        # 迭代/等待条件：True；退出由原循环条件及显式 break/异常决定。
        while True:
            self._fill(4, deadline)
            # 按条件 self.buffer[:4] != MAGIC 选择后续流程，保留原有异常和退出分支。
            if self.buffer[:4] != MAGIC:
                del self.buffer[0]  # Startup banner is retained in raw evidence.
                continue
            self._fill(20, deadline)
            seq, op, status, length = struct.unpack('<4I', self.buffer[4:20])
            # 按条件 length > MAX_DATA 选择后续流程，保留原有异常和退出分支。
            if length > MAX_DATA:
                # 停止当前调用并上报异常：raise ProtocolError(f'Invalid response length: {length}')。
                raise ProtocolError(f'Invalid response length: {length}')
            self._fill(24+length, deadline)
            frame = bytes(self.buffer[:24+length]); del self.buffer[:24+length]
            # 按条件 zlib.crc32(frame[4:-4]) != struct.unpack('<I', frame[-4:])[0] 选择后续流程，保留原有异常和退出分支。
            if zlib.crc32(frame[4:-4]) != struct.unpack('<I', frame[-4:])[0]:
                # 停止当前调用并上报异常：raise ProtocolError('Response CRC mismatch')。
                raise ProtocolError('Response CRC mismatch')
            # 按条件 seq != sequence 选择后续流程，保留原有异常和退出分支。
            if seq != sequence:
                continue  # Ignore an intact stale reply; never resend the request.
            # 按条件 op != opcode | 2147483648 选择后续流程，保留原有异常和退出分支。
            if op != opcode | 0x80000000:
                # 停止当前调用并上报异常：raise ProtocolError(f'Response opcode mismatch: {op:#x}')。
                raise ProtocolError(f'Response opcode mismatch: {op:#x}')
            # 向调用方返回本步骤结果：status, frame[20:-4]。
            return status, frame[20:-4]

    # 接口 request，显式输入字段：opcode, argument, payload。
    # 本函数调用入口包括 encode_packet, ProtocolError, self.transport.flush, self._reply, MonitorStatusError。
    def request(self, opcode, argument=0, payload=b'', *, allow_status=()):
        # 按条件 self.closed or self.failed 选择后续流程，保留原有异常和退出分支。
        if self.closed or self.failed:
            # 停止当前调用并上报异常：raise ProtocolError('Transport closed or uncertain after a prior failure; reopen explicitly')。
            raise ProtocolError('Transport closed or uncertain after a prior failure; reopen explicitly')
        self.sequence = (self.sequence+1) & 0xffffffff
        packet = encode_packet(self.sequence, opcode, argument, payload)
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            sent = 0
            # 迭代/等待条件：sent < len(packet)；退出由原循环条件及显式 break/异常决定。
            while sent < len(packet):
                n = self.transport.write(packet[sent:])
                # 按条件 not n 选择后续流程，保留原有异常和退出分支。
                if not n:
                    # 停止当前调用并上报异常：raise TimeoutError('Serial write made no progress')。
                    raise TimeoutError('Serial write made no progress')
                self._record('tx', packet[sent:sent+n]); sent += n
            self.transport.flush()
            status, response = self._reply(self.sequence, opcode, time.monotonic()+self.timeout)
        except (TimeoutError, ProtocolError, OSError):
            self.failed = True
            # 停止当前调用并上报异常：raise。
            raise
        # 按条件 status in (8, 12) 选择后续流程，保留原有异常和退出分支。
        if status in (8, 12):  # A timed-out DMA/capture may remain in flight.
            self.failed = True
        # 按条件 status and status not in allow_status 选择后续流程，保留原有异常和退出分支。
        if status and status not in allow_status:
            # 停止当前调用并上报异常：raise MonitorStatusError(status, response)。
            raise MonitorStatusError(status, response)
        # 向调用方返回本步骤结果：status, response。
        return status, response

    # 接口 ping，显式输入字段：expected_build。
    # 本函数调用入口包括 secrets.token_bytes, self.request, struct.unpack, response[48:64].decode, dict。
    def ping(self, expected_build=None):
        nonce = secrets.token_bytes(32)
        _, response = self.request(1, payload=nonce)
        # 按条件 len(response) != 64 + len(nonce) or response[64:] != nonce 选择后续流程，保留原有异常和退出分支。
        if len(response) != 64+len(nonce) or response[64:] != nonce:
            self.failed = True
            # 停止当前调用并上报异常：raise ProtocolError('Live nonce echo mismatch')。
            raise ProtocolError('Live nonce echo mismatch')
        words = struct.unpack('<12I', response[:48])
        # 按条件 words[0] != 1 or words[2] != MAX_DATA or words[7:9] != (DDR_BASE, DDR_END) 选择后续流程，保留原有异常和退出分支。
        if words[0] != 1 or words[2] != MAX_DATA or words[7:9] != (DDR_BASE, DDR_END):
            # 停止当前调用并上报异常：raise ProtocolError('Incompatible monitor protocol or DDR aperture')。
            raise ProtocolError('Incompatible monitor protocol or DDR aperture')
        build = response[48:64].decode('ascii')
        # 按条件 expected_build and build != expected_build 选择后续流程，保留原有异常和退出分支。
        if expected_build and build != expected_build:
            # 停止当前调用并上报异常：raise ProtocolError(f'Unexpected firmware build: {build}')。
            raise ProtocolError(f'Unexpected firmware build: {build}')
        self.identity = dict(protocol=words[0], cpu_hz=words[1], max_payload=words[2],
                             gpio_status=words[3], npu_id=words[4], npu_version=words[5],
                             npu_features=words[6], ddr_base=words[7], ddr_end=words[8],
                             uart_errors=words[9], npu_status=words[10], npu_errors=words[11],
                             build_id=build, nonce=nonce.hex(), nonce_echo_matched=True,
                             response_hex=response.hex())
        (self.out/'identity.json').write_text(json.dumps(self.identity, indent=2)+'\n', encoding='utf-8')
        # 向调用方返回本步骤结果：self.identity。
        return self.identity

    # 接口 read_memory，显式输入字段：address, length。
    # 本函数调用入口包括 checked_range, bytearray, bytes, len, min。
    def read_memory(self, address, length):
        checked_range(address, length)
        result = bytearray()
        # 迭代/等待条件：len(result) < length；退出由原循环条件及显式 break/异常决定。
        while len(result) < length:
            count = min(MAX_DATA, length-len(result))
            _, chunk = self.request(2, address+len(result), struct.pack('<I', count))
            # 按条件 len(chunk) != count 选择后续流程，保留原有异常和退出分支。
            if len(chunk) != count:
                self.failed = True
                # 停止当前调用并上报异常：raise ProtocolError('Read response length mismatch')。
                raise ProtocolError('Read response length mismatch')
            result.extend(chunk)
        # 向调用方返回本步骤结果：bytes(result)。
        return bytes(result)

    # 接口 write_memory，显式输入字段：address, data。
    # 本函数调用入口包括 bytes, checked_range, range, len, self.request。
    def write_memory(self, address, data):
        data = bytes(data)
        checked_range(address, len(data))
        # 迭代/等待条件：range(0, len(data), MAX_DATA)；退出由原循环条件及显式 break/异常决定。
        for offset in range(0, len(data), MAX_DATA):
            _, response = self.request(3, address+offset, data[offset:offset+MAX_DATA])
            # 按条件 response 选择后续流程，保留原有异常和退出分支。
            if response:
                # 停止当前调用并上报异常：raise ProtocolError('Write acknowledgement must have no payload')。
                raise ProtocolError('Write acknowledgement must have no payload')

    # 接口 load_file，显式输入字段：filename, address。
    # 本函数调用入口包括 Path(filename).read_bytes, self.write_memory, self.read_memory, dict, result.pop。
    def load_file(self, filename, address):
        data = Path(filename).read_bytes()
        self.write_memory(address, data)
        actual = self.read_memory(address, len(data))
        result = dict(file=str(Path(filename).resolve()), address=address, bytes=len(data),
                      file_sha256=sha(data), readback_sha256=sha(actual), pass_=actual == data,
                      verification='Entire file read back through CPU DDR reads')
        result['pass'] = result.pop('pass_')
        (self.out/'load_result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
        # 按条件 not result['pass'] 选择后续流程，保留原有异常和退出分支。
        if not result['pass']:
            # 停止当前调用并上报异常：raise ProtocolError('File readback mismatch; all commands and returned bytes retained')。
            raise ProtocolError('File readback mismatch; all commands and returned bytes retained')
        # 向调用方返回本步骤结果：result。
        return result

    # 接口 run_npu，显式输入字段：words。
    # 本函数调用入口包括 self.request, struct.unpack, dict, len, ValueError。
    def run_npu(self, words):
        # 按条件 len(words) != 12 选择后续流程，保留原有异常和退出分支。
        if len(words) != 12:
            # 停止当前调用并上报异常：raise ValueError('NPU command requires 12 uint32 words for MMIO 0x20..0x4c')。
            raise ValueError('NPU command requires 12 uint32 words for MMIO 0x20..0x4c')
        status, response = self.request(4, payload=struct.pack('<12I', *words), allow_status=(9,))
        # 按条件 len(response) != 32 选择后续流程，保留原有异常和退出分支。
        if len(response) != 32:
            # 停止当前调用并上报异常：raise ProtocolError('NPU completion payload must be 32 bytes')。
            raise ProtocolError('NPU completion payload must be 32 bytes')
        tag, error, cycles, lo, hi, sticky, irq, cpu_ticks = struct.unpack('<8I', response)
        # 向调用方返回本步骤结果：dict(status=status, tag=tag, error=error, cycles=cycles, macs=lo+(hi<<32),。
        return dict(status=status, tag=tag, error=error, cycles=cycles, macs=lo+(hi<<32),
                    error_sticky=sticky, irq=irq, cpu_ticks=cpu_ticks)

    @staticmethod
    # 接口 _camera_words，显式输入字段：response, status。
    # 本函数调用入口包括 struct.unpack, dict, len, ProtocolError, bool。
    def _camera_words(response, status):
        # 按条件 len(response) != 32 选择后续流程，保留原有异常和退出分支。
        if len(response) != 32:
            # 停止当前调用并上报异常：raise ProtocolError('Camera response must contain eight uint32 words')。
            raise ProtocolError('Camera response must contain eight uint32 words')
        ident, flags, base, dimensions, written, sensor, faults, ticks = struct.unpack('<8I', response)
        # 按条件 ident != 1128353073 or dimensions != 720 << 16 | 1280 选择后续流程，保留原有异常和退出分支。
        if ident != 0x43414d31 or dimensions != ((720 << 16) | 1280):
            # 停止当前调用并上报异常：raise ProtocolError('Unexpected camera register identity or dimensions')。
            raise ProtocolError('Unexpected camera register identity or dimensions')
        # 向调用方返回本步骤结果：dict(status=status, flags=flags, base=base, dimensions=dimensions,。
        return dict(status=status, flags=flags, base=base, dimensions=dimensions,
                    pixels_written=written, sensor_pixels=sensor, errors=faults,
                    cpu_ticks=ticks, frame_valid=bool(flags & 8))

    # 接口 camera_status，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.request, self._camera_words。
    def camera_status(self):
        status, response = self.request(5)
        # 向调用方返回本步骤结果：self._camera_words(response, status)。
        return self._camera_words(response, status)

    # 接口 camera_set_base，显式输入字段：address。
    # 本函数调用入口包括 checked_range, self.request, ValueError, ProtocolError, len。
    def camera_set_base(self, address):
        checked_range(address, 1280*720*2)
        # 按条件 address & 255 选择后续流程，保留原有异常和退出分支。
        if address & 255:
            # 停止当前调用并上报异常：raise ValueError('Camera frame base must be 256-byte aligned')。
            raise ValueError('Camera frame base must be 256-byte aligned')
        _, response = self.request(6, address)
        # 按条件 len(response) != 4 or struct.unpack('<I', response)[0] != address 选择后续流程，保留原有异常和退出分支。
        if len(response) != 4 or struct.unpack('<I', response)[0] != address:
            # 停止当前调用并上报异常：raise ProtocolError('Camera frame base readback mismatch')。
            raise ProtocolError('Camera frame base readback mismatch')

    # 接口 camera_capture，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.request, self._camera_words。
    def camera_capture(self):
        status, response = self.request(7, allow_status=(11, 12, 13))
        # 向调用方返回本步骤结果：self._camera_words(response, status)。
        return self._camera_words(response, status)

    # 接口 camera_diagnostics，显式输入字段：snapshot, channel。
    # 本函数调用入口包括 self.request, struct.unpack, dict, bool, ValueError。
    def camera_diagnostics(self, snapshot=True, channel=0):
        # 按条件 channel not in (0, 1) 选择后续流程，保留原有异常和退出分支。
        if channel not in (0, 1):
            # 停止当前调用并上报异常：raise ValueError('Camera diagnostic channel must be 0 or 1')。
            raise ValueError('Camera diagnostic channel must be 0 or 1')
        _, response = self.request(23, int(snapshot) | (channel << 1))
        # 按条件 len(response) != 64 选择后续流程，保留原有异常和退出分支。
        if len(response) != 64:
            # 停止当前调用并上报异常：raise ProtocolError('Camera diagnostic response must contain 16 uint32 words')。
            raise ProtocolError('Camera diagnostic response must contain 16 uint32 words')
        words = struct.unpack('<16I', response)
        # 按条件 words[0] != 826754115 or words[1] >> 16 != 1 选择后续流程，保留原有异常和退出分支。
        if words[0] != 0x31474443 or words[1] >> 16 != 1:
            # 停止当前调用并上报异常：raise ProtocolError('Unsupported camera diagnostic identity/version')。
            raise ProtocolError('Unsupported camera diagnostic identity/version')
        names = ('id', 'status', 'snapshot_sequence', 'pclk_edges', 'measurement_mem_ticks',
                 'observed_frame_sequence', 'frame_vsync_low_pclk_cycles', 'href_bytes',
                 'complete_lines', 'min_line_bytes', 'max_line_bytes', 'short_lines',
                 'long_lines', 'odd_lines', 'frame_flags', 'dropped_diagnostic_frames')
        result = dict(zip(names, words))
        result['frame_available'] = bool(words[1] & 1)
        result['frequency_available'] = bool(words[1] & 2)
        # UI frequency belongs to this candidate's verified PLL configuration;
        # this is an approximate edge measurement, not oscilloscope waveform QA.
        result['approximate_pclk_hz'] = (words[3]*93750000/words[4]
            if result['frequency_available'] and words[4] else None)
        result['measurement_is_window_average_edge_rate'] = True
        result['measurement_note'] = ('Counts received PCLK rising edges over the UI window; '
            'if the sensor gates PCLK, this does not establish its active-cycle frequency, '
            'pulse width, jitter, or input setup/hold margin.')
        # 向调用方返回本步骤结果：result。
        return result

    # 接口 camera_configuration，显式输入字段：channel。
    # 本函数调用入口包括 self.request, struct.unpack_from, range, dict, ValueError。
    def camera_configuration(self, channel=0):
        # 按条件 channel not in (0, 1) 选择后续流程，保留原有异常和退出分支。
        if channel not in (0, 1):
            # 停止当前调用并上报异常：raise ValueError('Camera configuration channel must be 0 or 1')。
            raise ValueError('Camera configuration channel must be 0 or 1')
        _, response = self.request(24, channel)
        # 按条件 len(response) < 40 选择后续流程，保留原有异常和退出分支。
        if len(response) < 40:
            # 停止当前调用并上报异常：raise ProtocolError('Camera configuration response truncated')。
            raise ProtocolError('Camera configuration response truncated')
        ident, version, returned_channel, count, before, after, ok, errors, ticks = struct.unpack_from('<8IQ', response)
        # 按条件 (ident, version, returned_channel) != (826426195, 1, channel) or len(response) != 40 + 8 * count 选择后续流程，保留原有异常和退出分支。
        if (ident, version, returned_channel) != (0x31424353, 1, channel) or len(response) != 40+8*count:
            # 停止当前调用并上报异常：raise ProtocolError('Camera configuration identity/length mismatch')。
            raise ProtocolError('Camera configuration identity/length mismatch')
        records = []
        names = {0:'OK',1:'BUS_NOT_IDLE',2:'CLOCK_TIMEOUT',3:'WRITE_ADDR_NACK',
                 4:'REG_HIGH_NACK',5:'REG_LOW_NACK',6:'READ_ADDR_NACK',
                 7:'STOP_ERROR',255:'NOT_RUN'}
        # 迭代/等待条件：range(count)；退出由原循环条件及显式 break/异常决定。
        for i in range(count):
            packed, acks = struct.unpack_from('<2I', response, 40+8*i)
            error = packed >> 24
            records.append(dict(register=packed & 65535, value=(packed >> 16) & 255,
                                error=error, error_name=names.get(error, 'UNKNOWN'),ack_mask=acks))
        # 按条件 ok != sum((x['error'] == 0 for x in records)) or errors != count - ok 选择后续流程，保留原有异常和退出分支。
        if ok != sum(x['error'] == 0 for x in records) or errors != count-ok:
            # 停止当前调用并上报异常：raise ProtocolError('Camera configuration counts inconsistent')。
            raise ProtocolError('Camera configuration counts inconsistent')
        # 向调用方返回本步骤结果：dict(id=ident,version=version,channel=channel,count=count,。
        return dict(id=ident,version=version,channel=channel,count=count,
                    io_levels_before=before,io_levels_after=after,successful_reads=ok,
                    failed_reads=errors,cpu_ticks=ticks,registers=records)

    # 接口 fill_test_frame，显式输入字段：source。
    # 本函数调用入口包括 checked_range, self.request, struct.unpack, dict, ValueError。
    def fill_test_frame(self, source):
        checked_range(source, FRAME_BYTES)
        # 按条件 source & 1 选择后续流程，保留原有异常和退出分支。
        if source & 1:
            # 停止当前调用并上报异常：raise ValueError('RGB565 source must be halfword aligned')。
            raise ValueError('RGB565 source must be halfword aligned')
        _, response = self.request(9, source)
        # 按条件 len(response) != 20 选择后续流程，保留原有异常和退出分支。
        if len(response) != 20:
            # 停止当前调用并上报异常：raise ProtocolError('Test-frame response must contain five uint32 words')。
            raise ProtocolError('Test-frame response must contain five uint32 words')
        ident, base, size, ticks, crc = struct.unpack('<5I', response)
        # 按条件 (ident, base, size) != (PREPROCESS_ID, source, FRAME_BYTES) 选择后续流程，保留原有异常和退出分支。
        if (ident, base, size) != (PREPROCESS_ID, source, FRAME_BYTES):
            # 停止当前调用并上报异常：raise ProtocolError('Test-frame response identity/range mismatch')。
            raise ProtocolError('Test-frame response identity/range mismatch')
        # 向调用方返回本步骤结果：dict(source=base, bytes=size, cpu_ticks=ticks, crc32=f'{crc:08x}')。
        return dict(source=base, bytes=size, cpu_ticks=ticks, crc32=f'{crc:08x}')

    # 接口 preprocess_frame，显式输入字段：source, destination。
    # 本函数调用入口包括 checked_range, self.request, struct.unpack, dict, ValueError。
    def preprocess_frame(self, source, destination):
        checked_range(source, FRAME_BYTES)
        checked_range(destination, TENSOR_BYTES)
        # 按条件 source & 1 or (source < destination + TENSOR_BYTES and destination < source + FRAME_BYTES) 选择后续流程，保留原有异常和退出分支。
        if source & 1 or (source < destination+TENSOR_BYTES and
                          destination < source+FRAME_BYTES):
            # 停止当前调用并上报异常：raise ValueError('RGB565 source and RGB888 destination must be disjoint')。
            raise ValueError('RGB565 source and RGB888 destination must be disjoint')
        _, response = self.request(8, source, struct.pack('<I', destination))
        # 按条件 len(response) != 28 选择后续流程，保留原有异常和退出分支。
        if len(response) != 28:
            # 停止当前调用并上报异常：raise ProtocolError('Preprocess response must contain seven uint32 words')。
            raise ProtocolError('Preprocess response must contain seven uint32 words')
        ident, src, dst, size, compute_ticks, crc, crc_ticks = struct.unpack('<7I', response)
        # 按条件 (ident, src, dst, size) != (PREPROCESS_ID, source, destination, TENSOR_BYTES) 选择后续流程，保留原有异常和退出分支。
        if (ident, src, dst, size) != (PREPROCESS_ID, source, destination, TENSOR_BYTES):
            # 停止当前调用并上报异常：raise ProtocolError('Preprocess response identity/range mismatch')。
            raise ProtocolError('Preprocess response identity/range mismatch')
        return dict(source=src, destination=dst, bytes=size,
                    compute_ticks=compute_ticks, crc32=f'{crc:08x}', crc_ticks=crc_ticks)

    # 接口 run_conv2d_i8_i32，显式输入字段：source, weights, output, scratch, shape。
    # 本函数调用入口包括 conv2d_layout, any, self.request, struct.unpack, dict。
    def run_conv2d_i8_i32(self, source, weights, output, scratch, shape):
        layout = conv2d_layout(shape)
        ranges = ((source, layout['input_bytes']),
                  (weights, layout['weight_bytes']),
                  (output, layout['output_bytes']),
                  (scratch, layout['scratch_bytes']))
        # 迭代/等待条件：ranges；退出由原循环条件及显式 break/异常决定。
        for address, length in ranges:
            checked_range(address, length)
        # 按条件 output & 3 选择后续流程，保留原有异常和退出分支。
        if output & 3:
            # 停止当前调用并上报异常：raise ValueError('INT32 output must be 4-byte aligned')。
            raise ValueError('INT32 output must be 4-byte aligned')
        # 按条件 any((a < b + bl and b < a + al for i, (a, al) in enumerate(ranges) for b, bl in ranges[i + 1:])) 选择后续流程，保留原有异常和退出分支。
        if any(a < b+bl and b < a+al
               for i, (a, al) in enumerate(ranges)
               for b, bl in ranges[i+1:]):
            # 停止当前调用并上报异常：raise ValueError('Conv2D DDR buffers must be disjoint')。
            raise ValueError('Conv2D DDR buffers must be disjoint')
        words = (weights, output, scratch)+tuple(shape[key] for key in CONV2D_FIELDS)
        _, response = self.request(10, source, struct.pack('<18I', *words))
        # 按条件 len(response) != 48 选择后续流程，保留原有异常和退出分支。
        if len(response) != 48:
            # 停止当前调用并上报异常：raise ProtocolError('Conv2D response must contain twelve uint32 words')。
            raise ProtocolError('Conv2D response must contain twelve uint32 words')
        ident, src, dst, rows, k, n, tiles, im2col_ticks, npu_ticks, npu_cycles, elapsed, crc = struct.unpack('<12I', response)
        # 按条件 (ident, src, dst, rows, k, n) != (CONV2D_ID, source, output, layout['rows'], layout['k'], shape['output_c']) 选择后续流程，保留原有异常和退出分支。
        if (ident, src, dst, rows, k, n) != (CONV2D_ID, source, output,
                                            layout['rows'], layout['k'], shape['output_c']):
            # 停止当前调用并上报异常：raise ProtocolError('Conv2D response identity/shape mismatch')。
            raise ProtocolError('Conv2D response identity/shape mismatch')
        return dict(source=src, output=dst, rows=rows, k=k, n=n, tiles=tiles,
                    im2col_ticks=im2col_ticks, npu_ticks=npu_ticks,
                    npu_cycles=npu_cycles, elapsed_ticks=elapsed,
                    output_crc32=f'{crc:08x}', layout=layout)

    # 接口 requant_i32_i8，显式输入字段：source, output, bias, multiplier, shift, elements, channels, output_zero_point, clamp_min, clamp_max, rounding_mode。
    # 本函数调用入口包括 any, struct.pack, self.request, struct.unpack, dict。
    def requant_i32_i8(self, source, output, bias, multiplier, shift,
                       elements, channels, output_zero_point, clamp_min,
                       clamp_max, rounding_mode):
        # 按条件 not (isinstance(elements, int) and isinstance(channels, int) and (elements > 0) and (channels > 0) and (ele... 选择后续流程，保留原有异常和退出分支。
        if not (isinstance(elements, int) and isinstance(channels, int) and
                elements > 0 and channels > 0 and elements % channels == 0 and
                elements <= (DDR_END-DDR_BASE)//4 and
                channels <= (DDR_END-DDR_BASE)//4):
            # 停止当前调用并上报异常：raise ValueError('Requant elements/channels are invalid')。
            raise ValueError('Requant elements/channels are invalid')
        # 按条件 not (-128 <= output_zero_point <= 127 and -128 <= clamp_min <= clamp_max <= 127 and (rounding_mode in (0, 1... 选择后续流程，保留原有异常和退出分支。
        if not (-128 <= output_zero_point <= 127 and
                -128 <= clamp_min <= clamp_max <= 127 and
                rounding_mode in (0, 1, 2)):
            # 停止当前调用并上报异常：raise ValueError('Requant output range or rounding mode is invalid')。
            raise ValueError('Requant output range or rounding mode is invalid')
        ranges = ((source, elements*4), (output, elements),
                  (bias, channels*4), (multiplier, channels*4),
                  (shift, channels*4))
        # 迭代/等待条件：ranges；退出由原循环条件及显式 break/异常决定。
        for address, length in ranges:
            checked_range(address, length)
        # 按条件 (source | bias | multiplier | shift) & 3 选择后续流程，保留原有异常和退出分支。
        if (source|bias|multiplier|shift) & 3:
            # 停止当前调用并上报异常：raise ValueError('INT32 source and parameter arrays must be aligned')。
            raise ValueError('INT32 source and parameter arrays must be aligned')
        # 按条件 any((a < b + bl and b < a + al for i, (a, al) in enumerate(ranges) for b, bl in ranges[i + 1:])) 选择后续流程，保留原有异常和退出分支。
        if any(a < b+bl and b < a+al
               for i, (a, al) in enumerate(ranges)
               for b, bl in ranges[i+1:]):
            # 停止当前调用并上报异常：raise ValueError('Requant DDR buffers must be disjoint')。
            raise ValueError('Requant DDR buffers must be disjoint')
        payload = struct.pack('<6I3iI', output, bias, multiplier, shift,
                              elements, channels, output_zero_point,
                              clamp_min, clamp_max, rounding_mode)
        _, response = self.request(11, source, payload)
        # 按条件 len(response) != 28 选择后续流程，保留原有异常和退出分支。
        if len(response) != 28:
            # 停止当前调用并上报异常：raise ProtocolError('Requant response must contain seven uint32 words')。
            raise ProtocolError('Requant response must contain seven uint32 words')
        ident, src, dst, count, compute_ticks, crc, crc_ticks = struct.unpack('<7I', response)
        # 按条件 (ident, src, dst, count) != (REQUANT_ID, source, output, elements) 选择后续流程，保留原有异常和退出分支。
        if (ident, src, dst, count) != (REQUANT_ID, source, output, elements):
            # 停止当前调用并上报异常：raise ProtocolError('Requant response identity/range mismatch')。
            raise ProtocolError('Requant response identity/range mismatch')
        return dict(source=src, output=dst, elements=count,
                    compute_ticks=compute_ticks, output_crc32=f'{crc:08x}',
                    crc_ticks=crc_ticks)

    # 接口 run_tensor_i8，显式输入字段：source, output, aux, shape。
    # 本函数调用入口包括 tensor_i8_layout, any, struct.pack, self.request, struct.unpack。
    def run_tensor_i8(self, source, output, aux, shape):
        layout = tensor_i8_layout(shape)
        ranges = [(source, layout['input_bytes']), (output, layout['output_bytes'])]
        # 按条件 layout['aux_bytes'] 选择后续流程，保留原有异常和退出分支。
        if layout['aux_bytes']:
            ranges.append((aux, layout['aux_bytes']))
        # 按条件 aux 选择后续流程，保留原有异常和退出分支。
        elif aux:
            # 停止当前调用并上报异常：raise ValueError('Aux address must be zero when unused')。
            raise ValueError('Aux address must be zero when unused')
        # 迭代/等待条件：ranges；退出由原循环条件及显式 break/异常决定。
        for address, length in ranges:
            checked_range(address, length)
        # 按条件 any((a < b + bl and b < a + al for i, (a, al) in enumerate(ranges) for b, bl in ranges[i + 1:])) 选择后续流程，保留原有异常和退出分支。
        if any(a < b+bl and b < a+al
               for i, (a, al) in enumerate(ranges)
               for b, bl in ranges[i+1:]):
            # 停止当前调用并上报异常：raise ValueError('Tensor DDR buffers must be disjoint')。
            raise ValueError('Tensor DDR buffers must be disjoint')
        payload = struct.pack('<16I', output, aux,
                              *(shape[key] for key in TENSOR_FIELDS))
        _, response = self.request(12, source, payload)
        # 按条件 len(response) != 40 选择后续流程，保留原有异常和退出分支。
        if len(response) != 40:
            # 停止当前调用并上报异常：raise ProtocolError('Tensor response must contain ten uint32 words')。
            raise ProtocolError('Tensor response must contain ten uint32 words')
        ident, kind, src, auxiliary, dst, oh, ow, oc, compute_ticks, crc = struct.unpack('<10I', response)
        # 按条件 (ident, kind, src, auxiliary, dst, oh, ow, oc) != (TENSOR_OPS_ID, shape['kind'], source, aux, output, layou... 选择后续流程，保留原有异常和退出分支。
        if (ident, kind, src, auxiliary, dst, oh, ow, oc) != (
                TENSOR_OPS_ID, shape['kind'], source, aux, output,
                layout['output_h'], layout['output_w'], layout['output_c']):
            # 停止当前调用并上报异常：raise ProtocolError('Tensor response identity/shape mismatch')。
            raise ProtocolError('Tensor response identity/shape mismatch')
        return dict(kind=kind, source=src, aux=auxiliary, output=dst,
                    compute_ticks=compute_ticks, output_crc32=f'{crc:08x}',
                    layout=layout)

    # 接口 gpio_sample，显式输入字段：output_value。
    # 本函数调用入口包括 self.request, struct.unpack, dict, ValueError, len。
    def gpio_sample(self, output_value=None):
        # 按条件 output_value is not None and (not (isinstance(output_value, int) and 0 <= output_value <= 15)) 选择后续流程，保留原有异常和退出分支。
        if output_value is not None and not (isinstance(output_value, int) and
                                              0 <= output_value <= 15):
            # 停止当前调用并上报异常：raise ValueError('GPIO test output must fit four LED bits')。
            raise ValueError('GPIO test output must fit four LED bits')
        _, response = self.request(13, 0xffffffff if output_value is None
                                   else output_value)
        # 按条件 len(response) != 16 选择后续流程，保留原有异常和退出分支。
        if len(response) != 16:
            # 停止当前调用并上报异常：raise ProtocolError('GPIO response must contain four uint32 words')。
            raise ProtocolError('GPIO response must contain four uint32 words')
        previous, observed, inputs, ticks = struct.unpack('<4I', response)
        # 按条件 output_value is not None and observed & 15 != output_value 选择后续流程，保留原有异常和退出分支。
        if output_value is not None and observed & 15 != output_value:
            # 停止当前调用并上报异常：raise ProtocolError('GPIO output readback mismatch')。
            raise ProtocolError('GPIO output readback mismatch')
        return dict(previous=previous, observed=observed, inputs=inputs,
                    ticks=ticks)

    # 接口 run_graph，显式输入字段：descriptor_base, count, trace_base, final_output, final_bytes。
    # 本函数调用入口包括 checked_range, struct.pack, self.request, struct.unpack, self.read_memory。
    def run_graph(self, descriptor_base, count, trace_base, final_output,
                  final_bytes):
        # 按条件 not isinstance(count, int) or not 1 <= count <= 16 选择后续流程，保留原有异常和退出分支。
        if not isinstance(count, int) or not 1 <= count <= 16:
            # 停止当前调用并上报异常：raise ValueError('Graph needs 1..16 operations')。
            raise ValueError('Graph needs 1..16 operations')
        # 按条件 descriptor_base & 3 or trace_base & 3 选择后续流程，保留原有异常和退出分支。
        if descriptor_base & 3 or trace_base & 3:
            # 停止当前调用并上报异常：raise ValueError('Graph descriptor and trace bases must be aligned')。
            raise ValueError('Graph descriptor and trace bases must be aligned')
        checked_range(descriptor_base, count*96)
        checked_range(trace_base, count*24)
        checked_range(final_output, final_bytes)
        ranges=((descriptor_base,count*96),(trace_base,count*24))
        # 按条件 ranges[0][0] < ranges[1][0] + ranges[1][1] and ranges[1][0] < ranges[0][0] + ranges[0][1] 选择后续流程，保留原有异常和退出分支。
        if ranges[0][0] < ranges[1][0]+ranges[1][1] and \
           ranges[1][0] < ranges[0][0]+ranges[0][1]:
            # 停止当前调用并上报异常：raise ValueError('Graph descriptor and trace ranges must be disjoint')。
            raise ValueError('Graph descriptor and trace ranges must be disjoint')
        payload=struct.pack('<4I',count,trace_base,final_output,final_bytes)
        _,response=self.request(14,descriptor_base,payload)
        # 按条件 len(response) != 32 选择后续流程，保留原有异常和退出分支。
        if len(response)!=32:
            # 停止当前调用并上报异常：raise ProtocolError('Graph response must contain eight uint32 words')。
            raise ProtocolError('Graph response must contain eight uint32 words')
        ident,planned,completed,failed,elapsed,trace,trace_crc,final_crc=struct.unpack(
            '<8I',response)
        # 按条件 (ident, planned, completed, failed, trace) != (GRAPH_ID, count, count, 4294967295, trace_base) 选择后续流程，保留原有异常和退出分支。
        if (ident,planned,completed,failed,trace)!=(
                GRAPH_ID,count,count,0xffffffff,trace_base):
            # 停止当前调用并上报异常：raise ProtocolError('Graph completion identity/count mismatch')。
            raise ProtocolError('Graph completion identity/count mismatch')
        trace_bytes=self.read_memory(trace_base,count*24)
        # 按条件 zlib.crc32(trace_bytes) != trace_crc 选择后续流程，保留原有异常和退出分支。
        if zlib.crc32(trace_bytes)!=trace_crc:
            # 停止当前调用并上报异常：raise ProtocolError('Graph trace CRC mismatch')。
            raise ProtocolError('Graph trace CRC mismatch')
        rows=[]
        # 迭代/等待条件：range(count)；退出由原循环条件及显式 break/异常决定。
        for i in range(count):
            index,opcode,status,ticks,crc,output=struct.unpack_from('<6I',
                trace_bytes,i*24)
            # 按条件 index != i or opcode not in (10, 11, 12) or status 选择后续流程，保留原有异常和退出分支。
            if index!=i or opcode not in (10,11,12) or status:
                # 停止当前调用并上报异常：raise ProtocolError('Graph trace step identity/status mismatch')。
                raise ProtocolError('Graph trace step identity/status mismatch')
            rows.append(dict(index=index,opcode=opcode,status=status,ticks=ticks,
                             output_crc32=f'{crc:08x}',output=output))
        return dict(count=count,completed=completed,elapsed_ticks=elapsed,
                    trace_base=trace,trace_crc32=f'{trace_crc:08x}',
                    final_crc32=f'{final_crc:08x}',trace=rows)

    # 接口 run_yolov5_detections，显式输入字段：heads, descriptor_base, output, scratch。
    # 本函数调用入口包括 checked_range, bytearray, self.write_memory, struct.pack, self.request。
    def run_yolov5_detections(self, heads, descriptor_base, output, scratch,
                              *, class_count, image_w, image_h,
                              score_threshold_q15, iou_threshold_q15,
                              max_candidates=512, max_results=64):
        """Decode preloaded signed INT8 YOLOv5 heads on the RV32 board CPU.

        Each head supplies tensor, grid_w, grid_h, stride, anchors_wh and
        sigmoid_q15 DDR addresses. Quantized tensor, six uint16 anchors and
        256 uint16 LUT entries must already be loaded at those addresses.
        """
        # 按条件 not 1 <= len(heads) <= 3 or not 1 <= class_count <= 80 选择后续流程，保留原有异常和退出分支。
        if not 1 <= len(heads) <= 3 or not 1 <= class_count <= 80:
            # 停止当前调用并上报异常：raise ValueError('Expected 1..3 heads and 1..80 classes')。
            raise ValueError('Expected 1..3 heads and 1..80 classes')
        # 按条件 not 1 <= max_results <= 64 or not max_results <= max_candidates <= 1024 选择后续流程，保留原有异常和退出分支。
        if not 1 <= max_results <= 64 or not max_results <= max_candidates <= 1024:
            # 停止当前调用并上报异常：raise ValueError('Detection result/candidate capacity invalid')。
            raise ValueError('Detection result/candidate capacity invalid')
        # 按条件 descriptor_base & 3 or output & 3 or scratch & 3 选择后续流程，保留原有异常和退出分支。
        if descriptor_base & 3 or output & 3 or scratch & 3:
            # 停止当前调用并上报异常：raise ValueError('Descriptor, output and scratch must be word aligned')。
            raise ValueError('Descriptor, output and scratch must be word aligned')
        checked_range(descriptor_base, len(heads)*32)
        checked_range(output, max_results*24)
        checked_range(scratch, max_candidates*24)
        fields = ('tensor', 'grid_w', 'grid_h', 'stride', 'anchors_wh', 'sigmoid_q15')
        descriptors = bytearray()
        # 迭代/等待条件：heads；退出由原循环条件及显式 break/异常决定。
        for head in heads:
            # 按条件 set(head) != set(fields) 选择后续流程，保留原有异常和退出分支。
            if set(head) != set(fields):
                # 停止当前调用并上报异常：raise ValueError(f'Detection head fields must be {fields}')。
                raise ValueError(f'Detection head fields must be {fields}')
            tensor_bytes = head['grid_w']*head['grid_h']*3*(class_count+5)
            checked_range(head['tensor'], tensor_bytes)
            checked_range(head['anchors_wh'], 12)
            checked_range(head['sigmoid_q15'], 512)
            descriptors += struct.pack('<8I', *(head[key] for key in fields), 0, 0)
        self.write_memory(descriptor_base, descriptors)
        payload = struct.pack('<10I', len(heads), class_count, image_w, image_h,
                              score_threshold_q15, iou_threshold_q15,
                              max_candidates, max_results, output, scratch)
        _, response = self.request(15, descriptor_base, payload)
        # 按条件 len(response) != 28 选择后续流程，保留原有异常和退出分支。
        if len(response) != 28:
            # 停止当前调用并上报异常：raise ProtocolError('Detection response must contain seven uint32 words')。
            raise ProtocolError('Detection response must contain seven uint32 words')
        ident, candidates, count, elapsed, returned_output, length, crc = struct.unpack(
            '<7I', response)
        # 按条件 ident != DETECTION_ID or returned_output != output or length != count * 24 or (count > max_results) or (can... 选择后续流程，保留原有异常和退出分支。
        if ident != DETECTION_ID or returned_output != output or length != count*24 or \
                count > max_results or candidates > max_candidates:
            # 停止当前调用并上报异常：raise ProtocolError('Detection completion identity/count mismatch')。
            raise ProtocolError('Detection completion identity/count mismatch')
        raw = self.read_memory(output, length) if length else b''
        # 按条件 (zlib.crc32(raw) if raw else 0) != crc 选择后续流程，保留原有异常和退出分支。
        if (zlib.crc32(raw) if raw else 0) != crc:
            # 停止当前调用并上报异常：raise ProtocolError('Detection result CRC mismatch')。
            raise ProtocolError('Detection result CRC mismatch')
        detections = []
        # 迭代/等待条件：range(count)；退出由原循环条件及显式 break/异常决定。
        for index in range(count):
            x1,y1,x2,y2,score,cls = struct.unpack_from('<6I', raw, index*24)
            # 按条件 x1 >= x2 or y1 >= y2 or cls >= class_count or (score > 32767) 选择后续流程，保留原有异常和退出分支。
            if x1 >= x2 or y1 >= y2 or cls >= class_count or score > 32767:
                # 停止当前调用并上报异常：raise ProtocolError('Malformed detection result')。
                raise ProtocolError('Malformed detection result')
            detections.append(dict(x1_q16=x1, y1_q16=y1,
                                   x2_q16=x2, y2_q16=y2,
                                   score_q15=score, class_id=cls))
        return dict(candidates=candidates, count=count,
                    elapsed_ticks=elapsed, output=output,
                    result_crc32=f'{crc:08x}', detections=detections)

    # 接口 close，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.transport.close, self.trace.close, self.rx_file.close, self.tx_file.close。
    def close(self):
        # 按条件 self.closed 选择后续流程，保留原有异常和退出分支。
        if self.closed:
            return
        self.closed = True
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            self.transport.close()
        finally:
            self.trace.close(); self.rx_file.close(); self.tx_file.close()

    # 接口 __enter__，显式输入字段：无位置参数。
    # 该函数直接更新本地状态或返回计算值，具体返回对象见函数体。
    def __enter__(self):
        return self

    # 接口 __exit__，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.close。
    def __exit__(self, *_):
        self.close()


# 接口 main，显式输入字段：无位置参数。
# 本函数调用入口包括 argparse.ArgumentParser, parser.add_argument, parser.add_subparsers, sub.add_parser, load.add_argument。
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', default='COM14')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=8.0)
    parser.add_argument('--expect-build')
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('ping')
    load = sub.add_parser('load'); load.add_argument('file', type=Path)
    load.add_argument('address', type=lambda s: int(s, 0))
    read = sub.add_parser('read'); read.add_argument('address', type=lambda s: int(s, 0))
    read.add_argument('length', type=lambda s: int(s, 0))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    result = dict(pass_=False, port=args.port, command=args.command, physical_uart=True)
    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        # 资源上下文：with Monitor.open(args.port, args.out, args.timeout) as monitor:；离开上下文时执行对应清理约定。
        with Monitor.open(args.port, args.out, args.timeout) as monitor:
            result['identity'] = monitor.ping(args.expect_build)
            # 按条件 args.command == 'load' 选择后续流程，保留原有异常和退出分支。
            if args.command == 'load':
                result['load'] = monitor.load_file(args.file, args.address)
            # 按条件 args.command == 'read' 选择后续流程，保留原有异常和退出分支。
            elif args.command == 'read':
                data = monitor.read_memory(args.address, args.length)
                (args.out/'readback.bin').write_bytes(data)
                result['read'] = dict(address=args.address, bytes=len(data), sha256=sha(data))
            result['pass_'] = True
    except Exception as exc:
        result['error'] = f'{type(exc).__name__}: {exc}'
    result['pass'] = result.pop('pass_')
    (args.out/'result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if result['pass'] else 1


# 按条件 __name__ == '__main__' 选择后续流程，保留原有异常和退出分支。
if __name__ == '__main__':
    # 停止当前调用并上报异常：raise SystemExit(main())。
    raise SystemExit(main())
