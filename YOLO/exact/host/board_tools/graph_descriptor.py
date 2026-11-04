"""Versioned, fixed-width DDR graph descriptors and activation reuse planner.

The target firmware consumes only opcodes 10/11/12 from this format. Weights,
quantization arrays, LUTs and source tensors are supplied separately by the
model package; this module does not guess YOLO scales or tensor shapes.
"""
from dataclasses import dataclass
import struct
import zlib

from board_monitor import DDR_BASE, DDR_END, checked_range

GRAPH_ID = 0x31505247  # "GRP1" little endian
DESCRIPTOR_WORDS = 24
DESCRIPTOR_BYTES = 4*DESCRIPTOR_WORDS
MAX_OPS = 16
PAYLOAD_WORDS = {10: 18, 11: 10, 12: 16}


def descriptor(opcode, source, payload_words):
    if opcode not in PAYLOAD_WORDS:
        raise ValueError('Graph opcode must be Conv, Requant, or INT8 tensor op')
    words = tuple(payload_words)
    if len(words) != PAYLOAD_WORDS[opcode]:
        raise ValueError('Graph operator payload length does not match opcode')
    checked_range(source, 1)
    if any(not isinstance(x, int) or not 0 <= x <= 0xffffffff for x in words):
        raise ValueError('Graph descriptor fields must be uint32')
    header = (opcode, source, 4*len(words), 0)
    return struct.pack('<24I', *(header+words+(0,)*(20-len(words))))


def graph_blob(descriptors):
    descriptors = tuple(descriptors)
    if not 1 <= len(descriptors) <= MAX_OPS:
        raise ValueError('Graph needs 1..16 descriptors')
    if any(len(blob) != DESCRIPTOR_BYTES for blob in descriptors):
        raise ValueError('Every descriptor must be 96 bytes')
    return b''.join(descriptors)


@dataclass(frozen=True)
class TensorLife:
    name: str
    size: int
    born: int
    last_use: int


def plan_activations(lifetimes, base, capacity, alignment=64):
    """First-fit live-range allocation; returns address/size and peak bytes.

    A tensor can share an allocation only after the previous tensor's last
    consumer, so producer and consumer cannot alias on the same operation.
    """
    checked_range(base, capacity)
    if base % alignment or alignment <= 0 or alignment & (alignment-1):
        raise ValueError('Activation base/alignment must be power-of-two aligned')
    lifetimes = tuple(lifetimes)
    if len({life.name for life in lifetimes}) != len(lifetimes):
        raise ValueError('Tensor names must be unique')
    active = []
    placements = {}
    peak = 0
    for life in sorted(lifetimes, key=lambda x: (x.born, x.name)):
        if not (life.name and life.size > 0 and
                0 <= life.born <= life.last_use):
            raise ValueError('Invalid tensor lifetime')
        active = [item for item in active if item[0] >= life.born]
        length = (life.size+alignment-1)//alignment*alignment
        offset = 0
        for _, used_offset, used_length in sorted(active, key=lambda x: x[1]):
            if offset+length <= used_offset:
                break
            offset = max(offset, used_offset+used_length)
        if offset+length > capacity:
            raise MemoryError('Live activations exceed the chosen DDR arena')
        active.append((life.last_use, offset, length))
        placements[life.name] = dict(address=base+offset, bytes=life.size,
                                     allocated_bytes=length,
                                     born=life.born, last_use=life.last_use)
        peak = max(peak, offset+length)
    return dict(placements=placements, peak_arena_bytes=peak,
                arena_base=base, arena_capacity=capacity, alignment=alignment)


def blob_crc32(blob):
    return f'{zlib.crc32(blob):08x}'
