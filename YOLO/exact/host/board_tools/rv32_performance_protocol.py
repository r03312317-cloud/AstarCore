"""Decode the candidate's read-only AST1 extensions; reserved zeros stay null."""
import struct
NAMES=('cycles','instructions_retired','I_cache_hits','I_cache_misses',
 'D_cache_hits','D_cache_misses','writebacks','FENCE_requests','maintenance_cycles',
 'MMIO_submits','MMIO_wait_cycles','uncached_DDR_requests','uncached_requests',
 'completed_legacy_maintenance','fault_flags','counter_ABI_ID','I_refills','D_refills')
def decode_cpu(raw):
 if len(raw)!=320:raise ValueError('RV32 CPU counter length')
 h=struct.unpack_from('<8I',raw)
 if h[0]!=0x31503252 or h[1]!=1 or h[7]!=18:raise ValueError('RV32 CPU counter ABI')
 before=struct.unpack_from('<18Q',raw,32);after=struct.unpack_from('<18Q',raw,176)
 delta={name:(after[i]-before[i])&((1<<(64 if i<2 else 32))-1) for i,name in enumerate(NAMES) if i not in (14,15)}
 if before[15]!=0x44323552 or after[15]!=0x44323552:raise ValueError('Wrong CPU statistics MMIO implementation')
 if not h[2] or h[5] or after[14]:raise ValueError('No clean completed workflow counter interval')
 if not delta['cycles'] or not delta['instructions_retired']:raise ValueError('Empty CPU execution interval')
 i_events=delta['I_cache_hits']+delta['I_cache_misses'];d_events=delta['D_cache_hits']+delta['D_cache_misses']
 return dict(version=1,frame_id=h[3],run_id=h[4],status=h[5],CPU_Hz=h[6],counter_before=dict(zip(NAMES,before)),counter_after=dict(zip(NAMES,after)),delta=delta,
  IPC=delta['instructions_retired']/delta['cycles'],CPI=delta['cycles']/delta['instructions_retired'],
  interval_seconds=delta['cycles']/h[6],I_hit_rate=delta['I_cache_hits']/i_events if i_events else None,D_hit_rate=delta['D_cache_hits']/d_events if d_events else None,
  hit_rate_scope='Cacheable request events only. No events means an undefined/null ratio, not0% or100% hit rate; uncached shared DDR is excluded',
  scope='CPU elapsed interval includes all waiting; activity counters overlap and cannot be summed')
def decode_layers(raw):
 if len(raw)<16:raise ValueError('RV32 logical layer header')
 ident,first,n,completed=struct.unpack_from('<4I',raw)
 if ident!=0x314c3252 or first+n>204 or len(raw)!=16+n*16:raise ValueError('RV32 logical layer ABI')
 records=[]
 for i,(ticks,status,_,__) in enumerate(struct.iter_unpack('<4I',raw[16:])):
  records.append(dict(index=first+i,ticks=ticks,valid=bool(status&0x80000000),fused_with_previous=bool(status&0x40000000),status=status&0xff,NPU_active_cycles=None,NPU_DMA_wait_cycles=None))
 return dict(completed=completed,records=records,unsupported_fields=['NPU_active_cycles','NPU_DMA_wait_cycles'],fused_contract='LUT work belongs to preceding Requant; zero exclusive ticks is not a skipped logical operator')
