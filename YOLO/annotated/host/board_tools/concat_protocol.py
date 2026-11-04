# 架构导读：concat_protocol。
# 协议字段解码与一致性检查，输入来自已保存或实时收到的板卡回复。
"""Concat cumulative counters: CPU70MHz and UI93.75MHz remain separate."""
import struct

ID=0x31544143
FLAG=0x02000000
# 接口 decode_concat，显式输入字段：raw。
# 本函数调用入口包括 struct.unpack_from, dict, value.update, len, ValueError。
def decode_concat(raw):
    # 按条件 len(raw) != 76 选择后续流程，保留原有异常和退出分支。
    if len(raw)!=76:raise ValueError('Concat statistics size differs')
    words=struct.unpack_from('<8I',raw)
    # 按条件 words[:2] != (ID, 1) 选择后续流程，保留原有异常和退出分支。
    if words[:2]!=(ID,1):raise ValueError('Concat statistics schema differs')
    value=dict(zip(('jobs','software_layers','fallbacks','failures','last_error','unaligned_fallbacks'),words[2:]))
    value.update(zip(('CPU_wait_ticks','DDR_read_bytes','DDR_write_bytes','UI_active_cycles','UI_stall_cycles'),struct.unpack_from('<5Q',raw,32)))
    value['timeout_latched']=struct.unpack_from('<I',raw,72)[0]
    return value

# 接口 graph_delta，显式输入字段：before, after, hardware, graphs。
# 本函数调用入口包括 any, ValueError, isinstance, value.values。
def graph_delta(before,after,hardware,graphs=1):
    # 按条件 not isinstance(graphs, int) or graphs < 1 选择后续流程，保留原有异常和退出分支。
    if not isinstance(graphs,int) or graphs<1:raise ValueError('Positive completed graph count required')
    keys=('jobs','software_layers','fallbacks','failures','unaligned_fallbacks','CPU_wait_ticks','DDR_read_bytes','DDR_write_bytes','UI_active_cycles','UI_stall_cycles')
    value={k:after[k]-before[k] for k in keys}
    if any(v<0 for v in value.values()):raise ValueError('Concat counter reset/wrap detected')
    expected=(15*graphs,0) if hardware else (0,15*graphs)
    if (value['jobs'],value['software_layers'])!=expected:raise ValueError('Actual hardware/software Concat layer count differs')
    if value['fallbacks'] or value['unaligned_fallbacks'] or value['failures'] or after['timeout_latched']:
        # 停止当前调用并上报异常：raise ValueError('Concat graph fallback/error/timeout')。
        raise ValueError('Concat graph fallback/error/timeout')
    wanted=1113600*graphs if hardware else 0
    if (value['DDR_read_bytes'],value['DDR_write_bytes'])!=(wanted,wanted):raise ValueError('Actual Concat DDR byte count differs')
    value['scope']='Same graph shape contract; software mode intentional A/B; waits/activity overlap and must not be added'
    return value

