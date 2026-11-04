"""Check comments-only C edits with the actual RV32 GCC and fixed board ID."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT=Path('/mnt/d/workspace/rv32_soc/deliverables/YOLO_G21_20261104')
OUT=Path('/mnt/d/workspace/rv32_soc/work/yolo_source_delivery_20261104_01/recompile_final_reviewed')
OUT.mkdir(exist_ok=False)
manifest=json.loads((ROOT/'artifacts/firmware/manifest.json').read_text())
link=manifest['command']
common=link[:link.index('-O2')]
names=['start','main','preprocess_rgb565','preprocess320_i8','conv2d_int8','requant_i32_i8','tensor_ops_int8','yolov5_postprocess','preprocess5mp_v2','display_resize','display_cmos2','memory_helpers']
records=[];log=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for name in names:
    source=(ROOT/'exact/runtime_policy/workspace/project/reference/v15/sw/coremark/port/start.S' if name=='start' else ROOT/'annotated/project/firmware_displayready_src'/(name+'.c'))
    opt='-O2' if name in ('requant_i32_i8','yolov5_postprocess') else '-Os'
    cmd=[*common,opt,'-c',str(source),'-o',str(OUT/(name+'.o'))]
    result=subprocess.run(cmd,capture_output=True,text=True)
    log.append(json.dumps(cmd)+'\n'+result.stdout+result.stderr)
    result.check_returncode()
    expected=ROOT/'artifacts/firmware'/(name+'.o')
    record=dict(source=str(source),object=name+'.o',original_sha256=sha(expected),recompiled_sha256=sha(OUT/(name+'.o')))
    record['byte_identical']=record['original_sha256']==record['recompiled_sha256']
    records.append(record)
    print(name, 'BYTE_IDENTICAL' if record['byte_identical'] else 'DIFF',flush=True)
command=[]
for item in link:
    if item.startswith('-T'):item='-T'+str(ROOT/'exact/runtime_policy/workspace/project/reference/v15/sw/coremark/port/link.ld')
    elif item.startswith('-Wl,-Map='):item='-Wl,-Map='+str(OUT/'monitor.map')
    elif item.endswith('.o'):item=str(OUT/Path(item).name)
    elif item.endswith('monitor.elf'):item=str(OUT/'monitor.elf')
    command.append(item)
result=subprocess.run(command,capture_output=True,text=True)
log.append(json.dumps(command)+'\n'+result.stdout+result.stderr);result.check_returncode()
elf=dict(original_sha256=sha(ROOT/'artifacts/firmware/monitor.elf'),recompiled_sha256=sha(OUT/'monitor.elf'))
elf['byte_identical']=elf['original_sha256']==elf['recompiled_sha256']
report=dict(status='PASS' if elf['byte_identical'] and all(x['byte_identical'] for x in records) else 'DIFF',
            note='Actual archived compiler/optimization flags with BOARD_BUILD_ID fixed to the tested ed37c7c631dc7896. The identity-hashing builder itself would assign a new ID to changed comment bytes.',
            objects=records,ELF=elf,
            annotated_source_sha256={p.name:sha(p) for p in (ROOT/'annotated/project/firmware_displayready_src').iterdir() if p.suffix in ('.c','.h')},
            annotation_audit_sha256=sha(ROOT/'audit/COMMENT_RATE_AND_TOKEN_EQUIVALENCE.json'))
(ROOT/'audit/ANNOTATED_C_RECOMPILE.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
(ROOT/'audit/ANNOTATED_C_RECOMPILE.log').write_text('\n'.join(log),encoding='utf-8')
print(json.dumps({'status':report['status'],'ELF':elf}),flush=True)
assert report['status']=='PASS'
