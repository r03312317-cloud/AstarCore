"""GraphExecutor21 candidate build. No serial, JTAG, Flash or board access.

prepare snapshots the exact selected sources; run executes one PDS phase.
All downstream phases consume databases produced in that NEW run only.
"""
from pathlib import Path, PurePosixPath
import argparse, hashlib, json, os, re, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parent / 'runtime_policy'
STAGES = ('synthesis', 'route', 'timing', 'bitstream')

def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(4*1024*1024),b''): h.update(b)
    return h.hexdigest()

def load(p): return json.loads(Path(p).read_text(encoding='utf8'))
def save(p,x): Path(p).write_text(json.dumps(x,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
def within(root,relative):
    rel=PurePosixPath(relative)
    if rel.is_absolute() or '..' in rel.parts or ':' in relative or '\\' in relative:
        raise ValueError('Unsafe relative path: '+relative)
    p=root.joinpath(*rel.parts).resolve()
    if not p.is_relative_to(root.resolve()): raise ValueError('Path outside project: '+relative)
    return p

def tq(p):
    s=Path(p).resolve().as_posix()
    if any(x in s for x in '{}\r\n'): raise ValueError('Unsupported Tcl path: '+s)
    return '{'+s+'}'

def verify(root,hashes):
    for rel,expected in hashes.items():
        p=within(root,rel)
        if not p.is_file() or sha(p)!=expected: raise ValueError('Input missing or changed: '+str(p))

def snapshot_rel(cfg,rel):
    prefix=cfg['snapshot_prefix']+'/'
    if not rel.startswith(prefix):raise ValueError('Input outside profile source tree: '+rel)
    return rel[len(prefix):]

def database(out,stage,top):
    task={'synthesis':f'syn_1/synthesize/{top}_syn.adf',
          'route':f'pnr_1/place_route/{top}_pnr.adf',
          'bitstream':f'pnr_1/generate_bitstream/{top}.sbit'}[stage]
    return out/stage/'project/prj_tasks'/task

def write_scripts(out,cfg):
    top=cfg['top'];snap=out/'snapshot'
    for phase in STAGES:
        d=out/phase;d.mkdir()  # PDS must create its own project directory
        for src,name in cfg['working_files'].items(): shutil.copy2(within(snap,snapshot_rel(cfg,src)),d/name)
        lines=['cd '+tq(d),'create_project '+tq(d/'project'/f'{top}.pds')+' -project_type rtl -syn_tool ads -in_process',
               'set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676',
               'set_option -options {max_threads 2 max_parallel_jobs 1} [current_project]']
        # PDS resolves relative ROM images from the project folder. Preserve
        # staged inputs and copy them after create_project has made the folder.
        lines += ['file copy '+tq(d/name)+' '+tq(d/'project'/name)
                  for name in cfg['working_files'].values()]
        if phase=='synthesis':
            lines += ['add_design '+tq(within(snap,snapshot_rel(cfg,x)))+' -library work' for x in cfg['sources']]
        lines += ['add_constraint '+tq(within(snap,snapshot_rel(cfg,x))) for x in cfg['constraints']]
        if phase=='synthesis':
            cmd='compile -top_module '+top+' -loop_limit 65536 -force_to_run'
            if cfg['systemverilog']: cmd+=' -verilog_standard SystemVerilog -compiler_directives {SYNTHESIS}'
            if cfg['mode']=='game':
                # Match the original verified PDS front-end spelling: the
                # parameter values are quoted HDL strings inside one Tcl word.
                itcm=(d/'game-itcm.mem').resolve().as_posix()
                dtcm=(d/'game-dtcm.mem').resolve().as_posix()
                cmd+=' -defined_parameters {ITCM_INIT_FILE "'+itcm+'" DTCM_INIT_FILE "'+dtcm+'"}'
            lines += [cmd,cfg['synthesize']]
        elif phase=='route':
            lines += ['dev_map -input_db_file '+tq(database(out,'synthesis',top))+' -force_to_run']
            lines += cfg['route_commands']
        elif phase=='timing':
            lines += ['report_timing -input_db_file '+tq(database(out,'route',top))+' -nworst 5 -max_path 100 -input_pins TRUE -force_to_run']
        else:
            lines += ['gen_bit_stream -input_db_file '+tq(database(out,'route',top))+' -scbv {High Voltage} -compress_bitstream TRUE -optimize_compress TRUE -disable_cyclic_redundancy_checking FALSE -write_drm_data TRUE -force_to_run']
        lines += ['puts "UNIFIED_'+phase.upper()+'_COMPLETE"','flush stdout']
        (d/'run.tcl').write_text('\n'.join(lines)+'\n',encoding='utf8')

def prepare(mode,out):
    cfg=load(ROOT/'profiles.json')[mode]
    verify(ROOT,cfg['input_sha256'])
    out=out.resolve()
    if out.exists(): raise FileExistsError('Choose a new output directory: '+str(out))
    if out.is_relative_to(ROOT/'sources'): raise ValueError('Build outside sources/')
    # Reject Tcl-invalid paths before creating a partial snapshot.
    tq(out)
    snapshot_hashes={snapshot_rel(cfg,rel):value for rel,value in cfg['input_sha256'].items()}
    if os.name=='nt' and any(len(str(out/'snapshot'/rel))>=255 for rel in snapshot_hashes):
        raise ValueError('PDS/Windows path too long; use a short build path such as F:/b/y1')
    out.mkdir(parents=True)
    for rel in cfg['input_sha256']:
        dest=within(out/'snapshot',snapshot_rel(cfg,rel));dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(within(ROOT,rel),dest)
    write_scripts(out,cfg)
    generated={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file() and not p.is_relative_to(out/'snapshot')}
    save(out/'run.json',dict(schema=1,mode=mode,top=cfg['top'],profile=cfg,
         snapshot_sha256=snapshot_hashes,generated_sha256=generated,status='PREPARED_NOT_IMPLEMENTED',switching='FPGA_RECONFIGURATION',board_tested=False))
    print(json.dumps(dict(mode=mode,out=str(out),source_count=len(cfg['sources']),status='PREPARED_NOT_IMPLEMENTED')))

def timing_check(report,top):
    s=report.read_text(encoding='utf8',errors='replace')
    if not re.search(r'\| Design\s*:\s*'+re.escape(top)+r'\b',s): raise ValueError('Wrong timing design')
    if 'Timing analysis mode : multi corner' not in s or 'Design Summary : All Constraints Met.' not in s:
        raise ValueError('Missing multi-corner timing pass')
    sections={}
    for corner in ('Slow','Fast'):
        for kind in ('Setup','Hold','Recovery','Removal','Minimum Pulse Width'):
            heading=f'{kind} Summary({corner} Corner):'
            if s.count(heading)!=1: raise ValueError('Missing/duplicate timing section '+heading)
            body=s.split(heading,1)[1].split('====',1)[0]
            clocks=r'(\S+)\s+' if kind=='Minimum Pulse Width' else r'\S+\s+(\S+)\s+'
            rows=re.findall(r'^\s*'+clocks+r'([-\d.]+)\s+([-\d.]+)\s+(\d+)\s+(\d+)\s*$',body,re.M)
            if not rows: raise ValueError('Empty/unparsed timing section; inspect manually: '+heading)
            if any(float(c)<0 or float(d)<0 or int(e)>0 for b,c,d,e,f in rows): raise ValueError('Timing violation '+heading)
            sections[heading]=len(rows)
    return dict(report_sha256=sha(report),sections=sections,constrained_timing_pass=True,
                scope='Reported constrained paths only; external I/O budgets and board behavior still require review.')

def receipt_check(out,phase):
    receipt=load(out/phase/'result.json')
    if not receipt['passed']: raise ValueError('Prior stage failed: '+phase)
    verify(out,receipt['artifacts'])
    return receipt

def run(out,phase,pds,license_file):
    out=out.resolve();meta=load(out/'run.json');cfg=meta['profile'];top=cfg['top']
    verify(out/'snapshot',meta['snapshot_sha256']);verify(out,meta['generated_sha256'])
    if not pds.is_file():raise FileNotFoundError(pds)
    if license_file and not license_file.is_file():raise FileNotFoundError(license_file)
    if (out/phase/'result.json').exists() or (out/phase/'pds.log').exists():
        raise FileExistsError('Stage already attempted; prepare a NEW run to preserve evidence')
    prior={}
    for earlier in STAGES[:STAGES.index(phase)]:
        prior[earlier]=receipt_check(out,earlier)
        if prior[earlier]['pds_sha256']!=sha(pds):raise ValueError('PDS executable changed between stages')
    if phase=='bitstream':
        reports=[within(out,x) for x in prior['timing']['artifacts'] if x.endswith('/'+top+'.rtr')]
        if len(reports)!=1:raise ValueError('Missing current timing report')
        timing_check(reports[0],top)
    env=os.environ.copy()
    if license_file: env['PANGO_LICENSE_FILE']=str(license_file.resolve())
    folder=out/phase;cmd=[str(pds.resolve()),'-file',str(folder/'run.tcl'),'-work_dir',str(folder)]
    with (folder/'pds.log').open('xb') as log:
        proc=subprocess.run(cmd,cwd=folder,env=env,stdout=log,stderr=subprocess.STDOUT)
    s=(folder/'pds.log').read_text(encoding='utf8',errors='replace')
    errors=re.findall(r'(?m)^\s*(?:E:|ERROR\b|FATAL\b)[^\r\n]*',s)
    passed=proc.returncode==0 and not errors and ('UNIFIED_'+phase.upper()+'_COMPLETE') in s
    artifacts={}
    if phase=='timing':
        report=folder/'project/prj_tasks/pnr_1/report_timing'/f'{top}.rtr'
        try:
            audit=timing_check(report,top);save(folder/'timing_audit.json',audit)
            artifacts[report.relative_to(out).as_posix()]=sha(report)
            artifacts[(folder/'timing_audit.json').relative_to(out).as_posix()]=sha(folder/'timing_audit.json')
        except (OSError,ValueError) as exc: passed=False;errors.append(str(exc))
    else:
        p=database(out,phase,top)
        if p.is_file() and p.stat().st_size: artifacts[p.relative_to(out).as_posix()]=sha(p)
        else:passed=False;errors.append('Expected current-run output missing: '+str(p))
    artifacts[(folder/'pds.log').relative_to(out).as_posix()]=sha(folder/'pds.log')
    save(folder/'result.json',dict(passed=bool(passed),command=cmd,exit=proc.returncode,errors=errors,
         artifacts=artifacts,pds_sha256=sha(pds),board_tested=False))
    if not passed:raise RuntimeError('PDS phase failed; inspect '+str(folder/'result.json'))
    print(phase+' completed; board verification remains outstanding')

def model_plan(out=None):
    root=ROOT/'sources/yolo/workspace/model/cmos2_concat_diag_eb1fbf30aa8f08e1_v1_20261003'
    plans=[]
    for scene in ('palm','empty'):
        folder=root/scene/'package';manifest=load(folder/'manifest.json');assets=[]
        for item in manifest['assets']:
            if item['name']=='input_hwc_i8':continue
            file=within(folder,item['file']);address=item['address'];size=item['bytes']
            if not file.is_file() or file.stat().st_size!=size or sha(file)!=item['sha256']:
                raise ValueError('Missing/changed model asset '+str(file))
            if size<=0 or address<0x80000000 or address+size>0x84000000:raise ValueError('Model address outside DDR window')
            assets.append(dict(name=item['name'],file=file.relative_to(ROOT).as_posix(),address=address,bytes=size,sha256=item['sha256']))
        if len(assets)!=317:raise ValueError('Expected 317 constants, excluding input image')
        ordered=sorted(assets,key=lambda x:x['address'])
        if any(a['address']+a['bytes']>b['address'] for a,b in zip(ordered,ordered[1:])):raise ValueError('Overlapping model constants')
        plans.append(assets)
    identities=lambda xs:[(x['name'],x['address'],x['bytes'],x['sha256']) for x in xs]
    if identities(plans[0])!=identities(plans[1]):raise ValueError('Palm/empty constants differ')
    result=dict(status='OFFLINE_CONSTANTS_CHECKED',board_access=False,package_root=str(ROOT),
                constants=plans[0],excluded='input_hwc_i8',firmware_build_id='bd0690f04d0413f8',
                note='This is a loading plan, not upload execution or board qualification.')
    if out:
        if out.exists():raise FileExistsError(out)
        save(out,result)
    print(json.dumps(dict(status=result['status'],constant_count=len(plans[0]),bytes=sum(x['bytes'] for x in plans[0]),
                          input_image_excluded=True,palm_empty_constants_match=True,output=str(out) if out else None)))

def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='cmd',required=True)
    sub.add_parser('list')
    a=sub.add_parser('prepare');a.add_argument('mode',choices=('yolo',));a.add_argument('--out',required=True,type=Path)
    a=sub.add_parser('run');a.add_argument('--out',required=True,type=Path);a.add_argument('--stage',required=True,choices=STAGES);a.add_argument('--pds',required=True,type=Path);a.add_argument('--license',type=Path)
    a=p.parse_args()
    if a.cmd=='list':
        for name,cfg in load(ROOT/'profiles.json').items():print(name,cfg['top'],cfg['clock_note'],'switch=reload FPGA bitstream')
    elif a.cmd=='prepare': prepare(a.mode,a.out)
    elif a.cmd=='run':run(a.out,a.stage,a.pds,a.license)
    elif a.cmd=='yolo-model-plan':model_plan(a.out)
    else:
        script=ROOT/'sources/linux/linux_uart_hdmi_demo_20261031_01/upload_demo.py'
        return subprocess.call([sys.executable,str(script),'--dry-run'],cwd=script.parent)
    return 0

if __name__=='__main__':raise SystemExit(main())
