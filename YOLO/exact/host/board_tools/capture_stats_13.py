"""Optional opcode26/0xfffffffe diagnostics for source-qualified12 firmware."""
import struct
FIELDS=('magic','version','active','attempted','completed','capture_rejected','capture_recovered','fatal','last_error','last_bad_frame','last_bad_run','last_capture_errors')
def decode(raw):
    if len(raw)!=48:raise ValueError('Capture stats must have48bytes')
    d=dict(zip(FIELDS,struct.unpack('<12I',raw)))
    if d['magic']!=0x32533243 or d['version']!=1 or d['active']>1:raise ValueError('Capture stats ABI')
    if d['completed']+d['capture_rejected']>d['attempted'] or d['capture_recovered']>d['capture_rejected'] or d['fatal']>d['attempted']:raise ValueError('Capture counters inconsistent')
    d['active']=bool(d['active'])
    return d
