# 架构导读：graph_executor_protocol。
# 协议字段解码与一致性检查，输入来自已保存或实时收到的板卡回复。
"""Read-only GRAPH_EXECUTOR1 diagnostics; importing this module never touches hardware."""
import struct
# 接口 decode，显式输入字段：raw。
# 本函数调用入口包括 struct.unpack, dict, result.update, len, ValueError。
def decode(raw):
    # 按条件 len(raw) != 112 选择后续流程，保留原有异常和退出分支。
    if len(raw)!=112:raise ValueError('GRAPH_EXECUTOR diagnostics must be 112 bytes')
    v=struct.unpack('<28I',raw)
    # 按条件 v[:2] != (827871303, 1) 选择后续流程，保留原有异常和退出分支。
    if v[:2]!=(0x31585047,1):raise ValueError('Unsupported GRAPH_EXECUTOR diagnostics')
    keys=('id','version','firmware_stage','cpu_hz','status','program_words','program_crc32',
          'model_epoch','frame_epoch','pc','completed_nodes','failure','last_device_read',
          'elapsed_cpu_ticks','executed_instructions','device_writes','device_reads','node',
          'capacity_words','program_generation','starts','finishes','cpu_polls','program_ready')
    result=dict(zip(keys,v[:24]))
    result.update(busy=bool(v[4]&1),done=bool(v[4]&2),program_valid=bool(v[4]&4),
                  poison=bool(v[4]&8),input_consumed=bool(v[4]&32),
                  compile_cpu_ticks=v[24]|v[25]<<32,cpu_poll_ticks=v[26]|v[27]<<32)
    return result
