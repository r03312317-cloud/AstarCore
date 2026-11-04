"""Window stats are cumulative CPU/UI counters, not additive wall time."""
import struct

def decode_window(raw):
 if len(raw)!=92:raise ValueError('Window statistics size differs')
 h=struct.unpack_from('<8I',raw)
 if h[:2]!=(0x314e4957,1):raise ValueError('Window statistics schema differs')
 values=struct.unpack_from('<7Q',raw,32)
 r=dict(zip(('jobs','hardware_layers','direct_layers','software_layers','failures','last_error'),h[2:]))
 r.update(zip(('CPU_wait_ticks','DDR_read_bytes','DDR_write_bytes','cache_hits','cache_misses','UI_active_cycles','UI_stall_cycles'),values))
 r['timeout_latched']=struct.unpack_from('<I',raw,88)[0]
 return r

def graph_delta(before,after,hardware,graphs=1):
 if not isinstance(graphs,int) or graphs<1:raise ValueError('Positive completed graph count required')
 keys=('jobs','hardware_layers','direct_layers','software_layers','failures','CPU_wait_ticks','DDR_read_bytes','DDR_write_bytes','cache_hits','cache_misses','UI_active_cycles','UI_stall_cycles')
 r={k:after[k]-before[k] for k in keys}
 if any(v<0 for v in r.values()):raise ValueError('Window counter reset/wrap detected')
 expected=tuple(x*graphs for x in ((757,18,42,0) if hardware else (0,0,0,18)))
 if tuple(r[k] for k in ('jobs','hardware_layers','direct_layers','software_layers'))!=expected:
  raise ValueError('Actual Window/direct/software counts differ')
 if r['failures'] or after['timeout_latched']:raise ValueError('Window fault in graph')
 if hardware and r['DDR_write_bytes']!=8524800*graphs:raise ValueError('Window scratch byte count differs')
 r['fallbacks']=0
 r['scope']='Strict hardware mode rejects errors; software mode is intentional A/B, not hidden fallback'
 return r
