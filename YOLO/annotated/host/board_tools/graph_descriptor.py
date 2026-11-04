# 架构导读：graph_descriptor。
# 主机侧工程工具，管理本文件定义的数据解析、检查或运行流程。
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


# 接口 descriptor，显式输入字段：opcode, source, payload_words。
# 本函数调用入口包括 tuple, checked_range, any, struct.pack, ValueError。
def descriptor(opcode, source, payload_words):
    # 按条件 opcode not in PAYLOAD_WORDS 选择后续流程，保留原有异常和退出分支。
    if opcode not in PAYLOAD_WORDS:
        # 停止当前调用并上报异常：raise ValueError('Graph opcode must be Conv, Requant, or INT8 tensor op')。
        raise ValueError('Graph opcode must be Conv, Requant, or INT8 tensor op')
    words = tuple(payload_words)
    # 按条件 len(words) != PAYLOAD_WORDS[opcode] 选择后续流程，保留原有异常和退出分支。
    if len(words) != PAYLOAD_WORDS[opcode]:
        # 停止当前调用并上报异常：raise ValueError('Graph operator payload length does not match opcode')。
        raise ValueError('Graph operator payload length does not match opcode')
    checked_range(source, 1)
    # 按条件 any((not isinstance(x, int) or not 0 <= x <= 4294967295 for x in words)) 选择后续流程，保留原有异常和退出分支。
    if any(not isinstance(x, int) or not 0 <= x <= 0xffffffff for x in words):
        # 停止当前调用并上报异常：raise ValueError('Graph descriptor fields must be uint32')。
        raise ValueError('Graph descriptor fields must be uint32')
    header = (opcode, source, 4*len(words), 0)
    return struct.pack('<24I', *(header+words+(0,)*(20-len(words))))


# 接口 graph_blob，显式输入字段：descriptors。
# 本函数调用入口包括 tuple, any, b''.join, ValueError, len。
def graph_blob(descriptors):
    descriptors = tuple(descriptors)
    # 按条件 not 1 <= len(descriptors) <= MAX_OPS 选择后续流程，保留原有异常和退出分支。
    if not 1 <= len(descriptors) <= MAX_OPS:
        # 停止当前调用并上报异常：raise ValueError('Graph needs 1..16 descriptors')。
        raise ValueError('Graph needs 1..16 descriptors')
    # 按条件 any((len(blob) != DESCRIPTOR_BYTES for blob in descriptors)) 选择后续流程，保留原有异常和退出分支。
    if any(len(blob) != DESCRIPTOR_BYTES for blob in descriptors):
        # 停止当前调用并上报异常：raise ValueError('Every descriptor must be 96 bytes')。
        raise ValueError('Every descriptor must be 96 bytes')
    return b''.join(descriptors)


@dataclass(frozen=True)
# 对象 TensorLife 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class TensorLife:
    name: str
    size: int
    born: int
    last_use: int


# 接口 plan_activations，显式输入字段：lifetimes, base, capacity, alignment。
# 本函数调用入口包括 checked_range, tuple, sorted, dict, ValueError。
def plan_activations(lifetimes, base, capacity, alignment=64):
    """First-fit live-range allocation; returns address/size and peak bytes.

    A tensor can share an allocation only after the previous tensor's last
    consumer, so producer and consumer cannot alias on the same operation.
    """
    checked_range(base, capacity)
    # 按条件 base % alignment or alignment <= 0 or alignment & alignment - 1 选择后续流程，保留原有异常和退出分支。
    if base % alignment or alignment <= 0 or alignment & (alignment-1):
        # 停止当前调用并上报异常：raise ValueError('Activation base/alignment must be power-of-two aligned')。
        raise ValueError('Activation base/alignment must be power-of-two aligned')
    lifetimes = tuple(lifetimes)
    # 按条件 len({life.name for life in lifetimes}) != len(lifetimes) 选择后续流程，保留原有异常和退出分支。
    if len({life.name for life in lifetimes}) != len(lifetimes):
        # 停止当前调用并上报异常：raise ValueError('Tensor names must be unique')。
        raise ValueError('Tensor names must be unique')
    active = []
    placements = {}
    peak = 0
    # 迭代/等待条件：sorted(lifetimes, key=lambda x: (x.born, x.name))；退出由原循环条件及显式 break/异常决定。
    for life in sorted(lifetimes, key=lambda x: (x.born, x.name)):
        # 按条件 not (life.name and life.size > 0 and (0 <= life.born <= life.last_use)) 选择后续流程，保留原有异常和退出分支。
        if not (life.name and life.size > 0 and
                0 <= life.born <= life.last_use):
            # 停止当前调用并上报异常：raise ValueError('Invalid tensor lifetime')。
            raise ValueError('Invalid tensor lifetime')
        active = [item for item in active if item[0] >= life.born]
        length = (life.size+alignment-1)//alignment*alignment
        offset = 0
        # 迭代/等待条件：sorted(active, key=lambda x: x[1])；退出由原循环条件及显式 break/异常决定。
        for _, used_offset, used_length in sorted(active, key=lambda x: x[1]):
            # 按条件 offset + length <= used_offset 选择后续流程，保留原有异常和退出分支。
            if offset+length <= used_offset:
                break
            offset = max(offset, used_offset+used_length)
        if offset+length > capacity:
            # 停止当前调用并上报异常：raise MemoryError('Live activations exceed the chosen DDR arena')。
            raise MemoryError('Live activations exceed the chosen DDR arena')
        active.append((life.last_use, offset, length))
        placements[life.name] = dict(address=base+offset, bytes=life.size,
                                     allocated_bytes=length,
                                     born=life.born, last_use=life.last_use)
        peak = max(peak, offset+length)
    return dict(placements=placements, peak_arena_bytes=peak,
                arena_base=base, arena_capacity=capacity, alignment=alignment)


# 接口 blob_crc32，显式输入字段：blob。
# 本函数调用入口包括 zlib.crc32。
def blob_crc32(blob):
    return f'{zlib.crc32(blob):08x}'
