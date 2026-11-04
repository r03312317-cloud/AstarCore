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


class ProtocolError(RuntimeError):
    pass


class MonitorStatusError(ProtocolError):
    def __init__(self, status, payload=b''):
        self.status, self.payload = status, payload
        super().__init__(STATUS[status] if status < len(STATUS) else f'STATUS_{status}')


def encode_packet(sequence, opcode, argument, payload=b''):
    payload = bytes(payload)
    if len(payload) > MAX_DATA:
        raise ValueError('Payload exceeds 1024 bytes')
    body = struct.pack('<4I', sequence, opcode, argument, len(payload)) + payload
    return MAGIC + body + struct.pack('<I', zlib.crc32(body))


def checked_range(address, length):
    if not (isinstance(address, int) and isinstance(length, int) and
            DDR_BASE <= address < DDR_END and 0 < length <= DDR_END-address):
        raise ValueError('DDR range must be nonempty and entirely inside 0x80000000..0x83ffffff')


def conv2d_layout(shape):
    if set(shape) != set(CONV2D_FIELDS):
        raise ValueError(f'Conv2D shape must have exactly {CONV2D_FIELDS}')
    s = {key: shape[key] for key in CONV2D_FIELDS}
    if any(not isinstance(value, int) or value < 0 or value > 0xffffffff
           for value in s.values()):
        raise ValueError('Conv2D shape fields must be uint32')
    if any(not s[key] for key in CONV2D_FIELDS if not key.startswith('pad_')):
        raise ValueError('Conv2D dimensions, stride and dilation must be nonzero')
    if s['output_c'] > 65535 or s['tile_m'] > 65535:
        raise ValueError('NPU output channels and tile rows must fit 16 bits')
    effective_h = (s['kernel_h']-1)*s['dilation_h']+1
    effective_w = (s['kernel_w']-1)*s['dilation_w']+1
    padded_h = s['input_h']+s['pad_top']+s['pad_bottom']
    padded_w = s['input_w']+s['pad_left']+s['pad_right']
    if padded_h < effective_h or padded_w < effective_w:
        raise ValueError('Kernel does not fit padded input')
    h = (padded_h-effective_h)//s['stride_h']+1
    w = (padded_w-effective_w)//s['stride_w']+1
    rows, k = h*w, s['kernel_h']*s['kernel_w']*s['input_c']
    if k > 65535:
        raise ValueError('NPU K must fit 16 bits')
    sizes = dict(input_bytes=s['input_h']*s['input_w']*s['input_c'],
                 weight_bytes=k*s['output_c'],
                 output_bytes=rows*s['output_c']*4,
                 scratch_bytes=s['tile_m']*k)
    if any(size > DDR_END-DDR_BASE for size in sizes.values()):
        raise ValueError('Conv2D buffer exceeds NPU-visible DDR aperture')
    return dict(output_h=h, output_w=w, rows=rows, k=k, **sizes)


def tensor_i8_layout(shape):
    if set(shape) != set(TENSOR_FIELDS):
        raise ValueError(f'Tensor shape must have exactly {TENSOR_FIELDS}')
    s = {key: shape[key] for key in TENSOR_FIELDS}
    if any(not isinstance(v, int) or v < 0 or v > 0xffffffff for v in s.values()):
        raise ValueError('Tensor shape fields must be uint32')
    h, w, c = s['input_h'], s['input_w'], s['input_c']
    if not (0 < h <= 4096 and 0 < w <= 4096 and 0 < c <= 65535) or s['param']:
        raise ValueError('Tensor dimensions or reserved field invalid')
    input_bytes = h*w*c
    if not 0 < input_bytes <= DDR_END-DDR_BASE:
        raise ValueError('Tensor input exceeds shared DDR aperture')
    kind = s['kind']
    aux_bytes = 0
    if kind == 1:
        ph = h+s['pad_top']+s['pad_bottom']
        pw = w+s['pad_left']+s['pad_right']
        if (s['aux_c'] or not 1 <= s['kernel_h'] <= 7 or
                not 1 <= s['kernel_w'] <= 7 or
                not 1 <= s['stride_h'] <= 4 or
                not 1 <= s['stride_w'] <= 4 or
                any(s[k] > 7 for k in ('pad_top','pad_left','pad_bottom','pad_right')) or
                ph < s['kernel_h'] or pw < s['kernel_w']):
            raise ValueError('MaxPool shape invalid')
        oh = (ph-s['kernel_h'])//s['stride_h']+1
        ow = (pw-s['kernel_w'])//s['stride_w']+1
        oc = c
    elif kind == 2:
        if (s['aux_c'] or not 1 <= s['stride_h'] <= 4 or
                not 1 <= s['stride_w'] <= 4 or h*s['stride_h'] > 4096 or
                w*s['stride_w'] > 4096 or
                any(s[k] for k in ('kernel_h','kernel_w','pad_top','pad_left',
                                     'pad_bottom','pad_right'))):
            raise ValueError('Upsample shape invalid')
        oh, ow, oc = h*s['stride_h'], w*s['stride_w'], c
    elif kind == 3:
        if (not 0 < s['aux_c'] <= 65535-c or
                any(s[k] for k in ('kernel_h','kernel_w','stride_h','stride_w',
                                     'pad_top','pad_left','pad_bottom','pad_right'))):
            raise ValueError('Concat shape invalid')
        oh, ow, oc = h, w, c+s['aux_c']
        aux_bytes = h*w*s['aux_c']
    elif kind in (4, 5):
        if (s['aux_c'] or any(s[k] for k in ('kernel_h','kernel_w','stride_h',
                                             'stride_w','pad_top','pad_left',
                                             'pad_bottom','pad_right'))):
            raise ValueError('LUT/Add shape invalid')
        oh, ow, oc = h, w, c
        aux_bytes = 256 if kind == 4 else input_bytes
    else:
        raise ValueError('Unknown INT8 tensor operator')
    output_bytes = oh*ow*oc
    if not 0 < output_bytes <= DDR_END-DDR_BASE or aux_bytes > DDR_END-DDR_BASE:
        raise ValueError('Tensor output/aux exceeds shared DDR aperture')
    return dict(output_h=oh, output_w=ow, output_c=oc,
                input_bytes=input_bytes, aux_bytes=aux_bytes,
                output_bytes=output_bytes)


def sha(data):
    return hashlib.sha256(data).hexdigest()


class Monitor:
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
    def open(cls, port, evidence_dir, timeout=8.0):
        import serial
        transport = serial.Serial()
        transport.port, transport.baudrate = port, 115200
        transport.timeout, transport.write_timeout = 0.05, 2.0
        transport.dtr = transport.rts = False
        transport.open()
        try:
            return cls(transport, evidence_dir, timeout)
        except BaseException:
            transport.close()
            raise

    def _record(self, direction, data):
        if not data:
            return
        raw = self.rx_file if direction == 'rx' else self.tx_file
        raw.write(data); raw.flush()
        event = dict(utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                     elapsed_seconds=time.monotonic()-self.started,
                     direction=direction, bytes=len(data), hex=data.hex())
        self.trace.write(json.dumps(event)+'\n'); self.trace.flush()

    def _fill(self, count, deadline):
        while len(self.buffer) < count:
            if time.monotonic() >= deadline:
                raise TimeoutError('AST1 reply deadline expired; no command retry was made')
            chunk = self.transport.read(max(1, min(4096, count-len(self.buffer))))
            self._record('rx', chunk)
            self.buffer.extend(chunk)

    def _reply(self, sequence, opcode, deadline):
        while True:
            self._fill(4, deadline)
            if self.buffer[:4] != MAGIC:
                del self.buffer[0]  # Startup banner is retained in raw evidence.
                continue
            self._fill(20, deadline)
            seq, op, status, length = struct.unpack('<4I', self.buffer[4:20])
            if length > MAX_DATA:
                raise ProtocolError(f'Invalid response length: {length}')
            self._fill(24+length, deadline)
            frame = bytes(self.buffer[:24+length]); del self.buffer[:24+length]
            if zlib.crc32(frame[4:-4]) != struct.unpack('<I', frame[-4:])[0]:
                raise ProtocolError('Response CRC mismatch')
            if seq != sequence:
                continue  # Ignore an intact stale reply; never resend the request.
            if op != opcode | 0x80000000:
                raise ProtocolError(f'Response opcode mismatch: {op:#x}')
            return status, frame[20:-4]

    def request(self, opcode, argument=0, payload=b'', *, allow_status=()):
        if self.closed or self.failed:
            raise ProtocolError('Transport closed or uncertain after a prior failure; reopen explicitly')
        self.sequence = (self.sequence+1) & 0xffffffff
        packet = encode_packet(self.sequence, opcode, argument, payload)
        try:
            sent = 0
            while sent < len(packet):
                n = self.transport.write(packet[sent:])
                if not n:
                    raise TimeoutError('Serial write made no progress')
                self._record('tx', packet[sent:sent+n]); sent += n
            self.transport.flush()
            status, response = self._reply(self.sequence, opcode, time.monotonic()+self.timeout)
        except (TimeoutError, ProtocolError, OSError):
            self.failed = True
            raise
        if status in (8, 12):  # A timed-out DMA/capture may remain in flight.
            self.failed = True
        if status and status not in allow_status:
            raise MonitorStatusError(status, response)
        return status, response

    def ping(self, expected_build=None):
        nonce = secrets.token_bytes(32)
        _, response = self.request(1, payload=nonce)
        if len(response) != 64+len(nonce) or response[64:] != nonce:
            self.failed = True
            raise ProtocolError('Live nonce echo mismatch')
        words = struct.unpack('<12I', response[:48])
        if words[0] != 1 or words[2] != MAX_DATA or words[7:9] != (DDR_BASE, DDR_END):
            raise ProtocolError('Incompatible monitor protocol or DDR aperture')
        build = response[48:64].decode('ascii')
        if expected_build and build != expected_build:
            raise ProtocolError(f'Unexpected firmware build: {build}')
        self.identity = dict(protocol=words[0], cpu_hz=words[1], max_payload=words[2],
                             gpio_status=words[3], npu_id=words[4], npu_version=words[5],
                             npu_features=words[6], ddr_base=words[7], ddr_end=words[8],
                             uart_errors=words[9], npu_status=words[10], npu_errors=words[11],
                             build_id=build, nonce=nonce.hex(), nonce_echo_matched=True,
                             response_hex=response.hex())
        (self.out/'identity.json').write_text(json.dumps(self.identity, indent=2)+'\n', encoding='utf-8')
        return self.identity

    def read_memory(self, address, length):
        checked_range(address, length)
        result = bytearray()
        while len(result) < length:
            count = min(MAX_DATA, length-len(result))
            _, chunk = self.request(2, address+len(result), struct.pack('<I', count))
            if len(chunk) != count:
                self.failed = True
                raise ProtocolError('Read response length mismatch')
            result.extend(chunk)
        return bytes(result)

    def write_memory(self, address, data):
        data = bytes(data)
        checked_range(address, len(data))
        for offset in range(0, len(data), MAX_DATA):
            _, response = self.request(3, address+offset, data[offset:offset+MAX_DATA])
            if response:
                raise ProtocolError('Write acknowledgement must have no payload')

    def load_file(self, filename, address):
        data = Path(filename).read_bytes()
        self.write_memory(address, data)
        actual = self.read_memory(address, len(data))
        result = dict(file=str(Path(filename).resolve()), address=address, bytes=len(data),
                      file_sha256=sha(data), readback_sha256=sha(actual), pass_=actual == data,
                      verification='Entire file read back through CPU DDR reads')
        result['pass'] = result.pop('pass_')
        (self.out/'load_result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
        if not result['pass']:
            raise ProtocolError('File readback mismatch; all commands and returned bytes retained')
        return result

    def run_npu(self, words):
        if len(words) != 12:
            raise ValueError('NPU command requires 12 uint32 words for MMIO 0x20..0x4c')
        status, response = self.request(4, payload=struct.pack('<12I', *words), allow_status=(9,))
        if len(response) != 32:
            raise ProtocolError('NPU completion payload must be 32 bytes')
        tag, error, cycles, lo, hi, sticky, irq, cpu_ticks = struct.unpack('<8I', response)
        return dict(status=status, tag=tag, error=error, cycles=cycles, macs=lo+(hi<<32),
                    error_sticky=sticky, irq=irq, cpu_ticks=cpu_ticks)

    @staticmethod
    def _camera_words(response, status):
        if len(response) != 32:
            raise ProtocolError('Camera response must contain eight uint32 words')
        ident, flags, base, dimensions, written, sensor, faults, ticks = struct.unpack('<8I', response)
        if ident != 0x43414d31 or dimensions != ((720 << 16) | 1280):
            raise ProtocolError('Unexpected camera register identity or dimensions')
        return dict(status=status, flags=flags, base=base, dimensions=dimensions,
                    pixels_written=written, sensor_pixels=sensor, errors=faults,
                    cpu_ticks=ticks, frame_valid=bool(flags & 8))

    def camera_status(self):
        status, response = self.request(5)
        return self._camera_words(response, status)

    def camera_set_base(self, address):
        checked_range(address, 1280*720*2)
        if address & 255:
            raise ValueError('Camera frame base must be 256-byte aligned')
        _, response = self.request(6, address)
        if len(response) != 4 or struct.unpack('<I', response)[0] != address:
            raise ProtocolError('Camera frame base readback mismatch')

    def camera_capture(self):
        status, response = self.request(7, allow_status=(11, 12, 13))
        return self._camera_words(response, status)

    def camera_diagnostics(self, snapshot=True, channel=0):
        if channel not in (0, 1):
            raise ValueError('Camera diagnostic channel must be 0 or 1')
        _, response = self.request(23, int(snapshot) | (channel << 1))
        if len(response) != 64:
            raise ProtocolError('Camera diagnostic response must contain 16 uint32 words')
        words = struct.unpack('<16I', response)
        if words[0] != 0x31474443 or words[1] >> 16 != 1:
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
        return result

    def camera_configuration(self, channel=0):
        if channel not in (0, 1):
            raise ValueError('Camera configuration channel must be 0 or 1')
        _, response = self.request(24, channel)
        if len(response) < 40:
            raise ProtocolError('Camera configuration response truncated')
        ident, version, returned_channel, count, before, after, ok, errors, ticks = struct.unpack_from('<8IQ', response)
        if (ident, version, returned_channel) != (0x31424353, 1, channel) or len(response) != 40+8*count:
            raise ProtocolError('Camera configuration identity/length mismatch')
        records = []
        names = {0:'OK',1:'BUS_NOT_IDLE',2:'CLOCK_TIMEOUT',3:'WRITE_ADDR_NACK',
                 4:'REG_HIGH_NACK',5:'REG_LOW_NACK',6:'READ_ADDR_NACK',
                 7:'STOP_ERROR',255:'NOT_RUN'}
        for i in range(count):
            packed, acks = struct.unpack_from('<2I', response, 40+8*i)
            error = packed >> 24
            records.append(dict(register=packed & 65535, value=(packed >> 16) & 255,
                                error=error, error_name=names.get(error, 'UNKNOWN'),ack_mask=acks))
        if ok != sum(x['error'] == 0 for x in records) or errors != count-ok:
            raise ProtocolError('Camera configuration counts inconsistent')
        return dict(id=ident,version=version,channel=channel,count=count,
                    io_levels_before=before,io_levels_after=after,successful_reads=ok,
                    failed_reads=errors,cpu_ticks=ticks,registers=records)

    def fill_test_frame(self, source):
        checked_range(source, FRAME_BYTES)
        if source & 1:
            raise ValueError('RGB565 source must be halfword aligned')
        _, response = self.request(9, source)
        if len(response) != 20:
            raise ProtocolError('Test-frame response must contain five uint32 words')
        ident, base, size, ticks, crc = struct.unpack('<5I', response)
        if (ident, base, size) != (PREPROCESS_ID, source, FRAME_BYTES):
            raise ProtocolError('Test-frame response identity/range mismatch')
        return dict(source=base, bytes=size, cpu_ticks=ticks, crc32=f'{crc:08x}')

    def preprocess_frame(self, source, destination):
        checked_range(source, FRAME_BYTES)
        checked_range(destination, TENSOR_BYTES)
        if source & 1 or (source < destination+TENSOR_BYTES and
                          destination < source+FRAME_BYTES):
            raise ValueError('RGB565 source and RGB888 destination must be disjoint')
        _, response = self.request(8, source, struct.pack('<I', destination))
        if len(response) != 28:
            raise ProtocolError('Preprocess response must contain seven uint32 words')
        ident, src, dst, size, compute_ticks, crc, crc_ticks = struct.unpack('<7I', response)
        if (ident, src, dst, size) != (PREPROCESS_ID, source, destination, TENSOR_BYTES):
            raise ProtocolError('Preprocess response identity/range mismatch')
        return dict(source=src, destination=dst, bytes=size,
                    compute_ticks=compute_ticks, crc32=f'{crc:08x}', crc_ticks=crc_ticks)

    def run_conv2d_i8_i32(self, source, weights, output, scratch, shape):
        layout = conv2d_layout(shape)
        ranges = ((source, layout['input_bytes']),
                  (weights, layout['weight_bytes']),
                  (output, layout['output_bytes']),
                  (scratch, layout['scratch_bytes']))
        for address, length in ranges:
            checked_range(address, length)
        if output & 3:
            raise ValueError('INT32 output must be 4-byte aligned')
        if any(a < b+bl and b < a+al
               for i, (a, al) in enumerate(ranges)
               for b, bl in ranges[i+1:]):
            raise ValueError('Conv2D DDR buffers must be disjoint')
        words = (weights, output, scratch)+tuple(shape[key] for key in CONV2D_FIELDS)
        _, response = self.request(10, source, struct.pack('<18I', *words))
        if len(response) != 48:
            raise ProtocolError('Conv2D response must contain twelve uint32 words')
        ident, src, dst, rows, k, n, tiles, im2col_ticks, npu_ticks, npu_cycles, elapsed, crc = struct.unpack('<12I', response)
        if (ident, src, dst, rows, k, n) != (CONV2D_ID, source, output,
                                            layout['rows'], layout['k'], shape['output_c']):
            raise ProtocolError('Conv2D response identity/shape mismatch')
        return dict(source=src, output=dst, rows=rows, k=k, n=n, tiles=tiles,
                    im2col_ticks=im2col_ticks, npu_ticks=npu_ticks,
                    npu_cycles=npu_cycles, elapsed_ticks=elapsed,
                    output_crc32=f'{crc:08x}', layout=layout)

    def requant_i32_i8(self, source, output, bias, multiplier, shift,
                       elements, channels, output_zero_point, clamp_min,
                       clamp_max, rounding_mode):
        if not (isinstance(elements, int) and isinstance(channels, int) and
                elements > 0 and channels > 0 and elements % channels == 0 and
                elements <= (DDR_END-DDR_BASE)//4 and
                channels <= (DDR_END-DDR_BASE)//4):
            raise ValueError('Requant elements/channels are invalid')
        if not (-128 <= output_zero_point <= 127 and
                -128 <= clamp_min <= clamp_max <= 127 and
                rounding_mode in (0, 1, 2)):
            raise ValueError('Requant output range or rounding mode is invalid')
        ranges = ((source, elements*4), (output, elements),
                  (bias, channels*4), (multiplier, channels*4),
                  (shift, channels*4))
        for address, length in ranges:
            checked_range(address, length)
        if (source|bias|multiplier|shift) & 3:
            raise ValueError('INT32 source and parameter arrays must be aligned')
        if any(a < b+bl and b < a+al
               for i, (a, al) in enumerate(ranges)
               for b, bl in ranges[i+1:]):
            raise ValueError('Requant DDR buffers must be disjoint')
        payload = struct.pack('<6I3iI', output, bias, multiplier, shift,
                              elements, channels, output_zero_point,
                              clamp_min, clamp_max, rounding_mode)
        _, response = self.request(11, source, payload)
        if len(response) != 28:
            raise ProtocolError('Requant response must contain seven uint32 words')
        ident, src, dst, count, compute_ticks, crc, crc_ticks = struct.unpack('<7I', response)
        if (ident, src, dst, count) != (REQUANT_ID, source, output, elements):
            raise ProtocolError('Requant response identity/range mismatch')
        return dict(source=src, output=dst, elements=count,
                    compute_ticks=compute_ticks, output_crc32=f'{crc:08x}',
                    crc_ticks=crc_ticks)

    def run_tensor_i8(self, source, output, aux, shape):
        layout = tensor_i8_layout(shape)
        ranges = [(source, layout['input_bytes']), (output, layout['output_bytes'])]
        if layout['aux_bytes']:
            ranges.append((aux, layout['aux_bytes']))
        elif aux:
            raise ValueError('Aux address must be zero when unused')
        for address, length in ranges:
            checked_range(address, length)
        if any(a < b+bl and b < a+al
               for i, (a, al) in enumerate(ranges)
               for b, bl in ranges[i+1:]):
            raise ValueError('Tensor DDR buffers must be disjoint')
        payload = struct.pack('<16I', output, aux,
                              *(shape[key] for key in TENSOR_FIELDS))
        _, response = self.request(12, source, payload)
        if len(response) != 40:
            raise ProtocolError('Tensor response must contain ten uint32 words')
        ident, kind, src, auxiliary, dst, oh, ow, oc, compute_ticks, crc = struct.unpack('<10I', response)
        if (ident, kind, src, auxiliary, dst, oh, ow, oc) != (
                TENSOR_OPS_ID, shape['kind'], source, aux, output,
                layout['output_h'], layout['output_w'], layout['output_c']):
            raise ProtocolError('Tensor response identity/shape mismatch')
        return dict(kind=kind, source=src, aux=auxiliary, output=dst,
                    compute_ticks=compute_ticks, output_crc32=f'{crc:08x}',
                    layout=layout)

    def gpio_sample(self, output_value=None):
        if output_value is not None and not (isinstance(output_value, int) and
                                              0 <= output_value <= 15):
            raise ValueError('GPIO test output must fit four LED bits')
        _, response = self.request(13, 0xffffffff if output_value is None
                                   else output_value)
        if len(response) != 16:
            raise ProtocolError('GPIO response must contain four uint32 words')
        previous, observed, inputs, ticks = struct.unpack('<4I', response)
        if output_value is not None and observed & 15 != output_value:
            raise ProtocolError('GPIO output readback mismatch')
        return dict(previous=previous, observed=observed, inputs=inputs,
                    ticks=ticks)

    def run_graph(self, descriptor_base, count, trace_base, final_output,
                  final_bytes):
        if not isinstance(count, int) or not 1 <= count <= 16:
            raise ValueError('Graph needs 1..16 operations')
        if descriptor_base & 3 or trace_base & 3:
            raise ValueError('Graph descriptor and trace bases must be aligned')
        checked_range(descriptor_base, count*96)
        checked_range(trace_base, count*24)
        checked_range(final_output, final_bytes)
        ranges=((descriptor_base,count*96),(trace_base,count*24))
        if ranges[0][0] < ranges[1][0]+ranges[1][1] and \
           ranges[1][0] < ranges[0][0]+ranges[0][1]:
            raise ValueError('Graph descriptor and trace ranges must be disjoint')
        payload=struct.pack('<4I',count,trace_base,final_output,final_bytes)
        _,response=self.request(14,descriptor_base,payload)
        if len(response)!=32:
            raise ProtocolError('Graph response must contain eight uint32 words')
        ident,planned,completed,failed,elapsed,trace,trace_crc,final_crc=struct.unpack(
            '<8I',response)
        if (ident,planned,completed,failed,trace)!=(
                GRAPH_ID,count,count,0xffffffff,trace_base):
            raise ProtocolError('Graph completion identity/count mismatch')
        trace_bytes=self.read_memory(trace_base,count*24)
        if zlib.crc32(trace_bytes)!=trace_crc:
            raise ProtocolError('Graph trace CRC mismatch')
        rows=[]
        for i in range(count):
            index,opcode,status,ticks,crc,output=struct.unpack_from('<6I',
                trace_bytes,i*24)
            if index!=i or opcode not in (10,11,12) or status:
                raise ProtocolError('Graph trace step identity/status mismatch')
            rows.append(dict(index=index,opcode=opcode,status=status,ticks=ticks,
                             output_crc32=f'{crc:08x}',output=output))
        return dict(count=count,completed=completed,elapsed_ticks=elapsed,
                    trace_base=trace,trace_crc32=f'{trace_crc:08x}',
                    final_crc32=f'{final_crc:08x}',trace=rows)

    def run_yolov5_detections(self, heads, descriptor_base, output, scratch,
                              *, class_count, image_w, image_h,
                              score_threshold_q15, iou_threshold_q15,
                              max_candidates=512, max_results=64):
        """Decode preloaded signed INT8 YOLOv5 heads on the RV32 board CPU.

        Each head supplies tensor, grid_w, grid_h, stride, anchors_wh and
        sigmoid_q15 DDR addresses. Quantized tensor, six uint16 anchors and
        256 uint16 LUT entries must already be loaded at those addresses.
        """
        if not 1 <= len(heads) <= 3 or not 1 <= class_count <= 80:
            raise ValueError('Expected 1..3 heads and 1..80 classes')
        if not 1 <= max_results <= 64 or not max_results <= max_candidates <= 1024:
            raise ValueError('Detection result/candidate capacity invalid')
        if descriptor_base & 3 or output & 3 or scratch & 3:
            raise ValueError('Descriptor, output and scratch must be word aligned')
        checked_range(descriptor_base, len(heads)*32)
        checked_range(output, max_results*24)
        checked_range(scratch, max_candidates*24)
        fields = ('tensor', 'grid_w', 'grid_h', 'stride', 'anchors_wh', 'sigmoid_q15')
        descriptors = bytearray()
        for head in heads:
            if set(head) != set(fields):
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
        if len(response) != 28:
            raise ProtocolError('Detection response must contain seven uint32 words')
        ident, candidates, count, elapsed, returned_output, length, crc = struct.unpack(
            '<7I', response)
        if ident != DETECTION_ID or returned_output != output or length != count*24 or \
                count > max_results or candidates > max_candidates:
            raise ProtocolError('Detection completion identity/count mismatch')
        raw = self.read_memory(output, length) if length else b''
        if (zlib.crc32(raw) if raw else 0) != crc:
            raise ProtocolError('Detection result CRC mismatch')
        detections = []
        for index in range(count):
            x1,y1,x2,y2,score,cls = struct.unpack_from('<6I', raw, index*24)
            if x1 >= x2 or y1 >= y2 or cls >= class_count or score > 32767:
                raise ProtocolError('Malformed detection result')
            detections.append(dict(x1_q16=x1, y1_q16=y1,
                                   x2_q16=x2, y2_q16=y2,
                                   score_q15=score, class_id=cls))
        return dict(candidates=candidates, count=count,
                    elapsed_ticks=elapsed, output=output,
                    result_crc32=f'{crc:08x}', detections=detections)

    def close(self):
        if self.closed:
            return
        self.closed = True
        try:
            self.transport.close()
        finally:
            self.trace.close(); self.rx_file.close(); self.tx_file.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


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
    try:
        with Monitor.open(args.port, args.out, args.timeout) as monitor:
            result['identity'] = monitor.ping(args.expect_build)
            if args.command == 'load':
                result['load'] = monitor.load_file(args.file, args.address)
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


if __name__ == '__main__':
    raise SystemExit(main())
