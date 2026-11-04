# 架构导读：window_protocol。
# 协议字段解码与一致性检查，输入来自已保存或实时收到的板卡回复。
"""Window stats are cumulative CPU/UI counters, not additive wall time."""
import struct

# 接口 decode_window，显式输入字段：raw。
# 本函数调用入口包括 struct.unpack_from, dict, r.update, len, ValueError。
def decode_window(raw):
 # 按条件 len(raw) != 92 选择后续流程，保留原有异常和退出分支。
 if len(raw)!=92:raise ValueError('Window statistics size differs')
 h=struct.unpack_from('<8I',raw)
 # 按条件 h[:2] != (827214167, 1) 选择后续流程，保留原有异常和退出分支。
 if h[:2]!=(0x314e4957,1):raise ValueError('Window statistics schema differs')
 values=struct.unpack_from('<7Q',raw,32)
 r=dict(zip(('jobs','hardware_layers','direct_layers','software_layers','failures','last_error'),h[2:]))
 r.update(zip(('CPU_wait_ticks','DDR_read_bytes','DDR_write_bytes','cache_hits','cache_misses','UI_active_cycles','UI_stall_cycles'),values))
 r['timeout_latched']=struct.unpack_from('<I',raw,88)[0]
 return r

# 接口 graph_delta，显式输入字段：before, after, hardware, graphs。
# 本函数调用入口包括 any, tuple, ValueError, isinstance, r.values。
def graph_delta(before,after,hardware,graphs=1):
 # 按条件 not isinstance(graphs, int) or graphs < 1 选择后续流程，保留原有异常和退出分支。
 if not isinstance(graphs,int) or graphs<1:raise ValueError('Positive completed graph count required')
 keys=('jobs','hardware_layers','direct_layers','software_layers','failures','CPU_wait_ticks','DDR_read_bytes','DDR_write_bytes','cache_hits','cache_misses','UI_active_cycles','UI_stall_cycles')
 r={k:after[k]-before[k] for k in keys}
 if any(v<0 for v in r.values()):raise ValueError('Window counter reset/wrap detected')
 expected=tuple(x*graphs for x in ((757,18,42,0) if hardware else (0,0,0,18)))
 if tuple(r[k] for k in ('jobs','hardware_layers','direct_layers','software_layers'))!=expected:
  # 停止当前调用并上报异常：raise ValueError('Actual Window/direct/software counts differ')。
  raise ValueError('Actual Window/direct/software counts differ')
 if r['failures'] or after['timeout_latched']:raise ValueError('Window fault in graph')
 if hardware and r['DDR_write_bytes']!=8524800*graphs:raise ValueError('Window scratch byte count differs')
 r['fallbacks']=0
 r['scope']='Strict hardware mode rejects errors; software mode is intentional A/B, not hidden fallback'
 return r
