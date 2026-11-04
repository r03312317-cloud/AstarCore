"""Read-only source, model, comment-rate and recorded-board validation.

No serial/JTAG/PDS process is opened. Optional independent comment counting
uses Pygments; the default checks need only the Python standard library.
"""
from pathlib import Path,PurePosixPath,PureWindowsPath
import argparse
import csv
import hashlib
import json
import sys
from source_audit import analyze,equivalent

ROOT=Path(__file__).resolve().parents[1]


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest()


def relative_file(text):
    rel=PurePosixPath(text)
    if rel.is_absolute() or '..' in rel.parts or ':' in text or '\\' in text:
        raise ValueError('Invalid package-relative path: '+text)
    p=ROOT.joinpath(*rel.parts).resolve()
    if not p.is_relative_to(ROOT):raise ValueError('Path escapes package')
    return p


def independent_count(path):
    from pygments import lex
    from pygments.lexers import PythonLexer,CLexer,SystemVerilogLexer
    from pygments.token import Comment
    text=path.read_text(encoding='utf-8');marks=[set() for _ in text.splitlines()];index=0
    lexer=PythonLexer() if path.suffix=='.py' else CLexer() if path.suffix in ('.c','.h') else SystemVerilogLexer()
    for kind,value in lex(text,lexer):
        comment=kind in Comment and kind not in Comment.Preproc and kind not in Comment.PreprocFile
        for piece in value.splitlines(keepends=True):
            if piece.strip() and index<len(marks):marks[index].add('comment' if comment else 'code')
            if piece.endswith('\n'):index+=1
    return sum(x=={'comment'} for x in marks),sum('code' in x for x in marks)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--independent-comments',action='store_true',help='Also recount using the optional Pygments package')
    args=parser.parse_args()
    result=dict(status='checking',board_access=False)
    manifest=ROOT/'MANIFEST.json'
    if manifest.is_file():
        payload=load(manifest)['files']
        for rel,entry in payload.items():
            p=relative_file(rel)
            assert p.is_file() and p.stat().st_size==entry['bytes'] and sha(p)==entry['sha256'], 'Payload changed: '+rel
        result['payload_files_verified']=len(payload)
    frozen=load(ROOT/'audit/FROZEN_INPUT_VALIDATION.json')
    for rel,wanted in frozen['source_hashes'].items():
        assert sha(ROOT/'exact/runtime_policy/workspace'/rel)==wanted,'Frozen source changed: '+rel
    result['frozen_files_verified']=len(frozen['source_hashes'])
    audit=load(ROOT/'audit/COMMENT_RATE_AND_TOKEN_EQUIVALENCE.json')
    groups={}
    for item in audit['files']:
        original=relative_file(item['original']);annotated=relative_file(item['file'])
        assert sha(original)==item['original_sha256'] and sha(annotated)==item['annotated_sha256']
        before,after=equivalent(original,annotated)
        assert after['code_lines']==item['code_lines'] and after['comment_lines']==item['comment_lines']
        if args.independent_comments:assert independent_count(annotated)==(after['comment_lines'],after['code_lines'])
        g=groups.setdefault(item['group'],dict(files=0,code=0,comment=0))
        g['files']+=1;g['code']+=after['code_lines'];g['comment']+=after['comment_lines']
    groups['ALL']=dict(files=sum(x['files'] for x in groups.values()),code=sum(x['code'] for x in groups.values()),comment=sum(x['comment'] for x in groups.values()))
    for group,values in groups.items():
        values['comment_percent']=values['comment']/(values['code']+values['comment'])*100
        assert 29.5<=values['comment_percent']<=30.5
        assert values['files']==audit['summary'][group]['files']
    result['source_comment_and_token_audit']=groups
    result['independent_lexer_recount']=args.independent_comments
    compiler=load(ROOT/'audit/ANNOTATED_C_RECOMPILE.json')
    assert compiler['status']=='PASS' and compiler['ELF']['byte_identical'] and all(x['byte_identical'] for x in compiler['objects'])
    for name,wanted in compiler['annotated_source_sha256'].items():
        assert sha(ROOT/'annotated/project/firmware_displayready_src'/name)==wanted
    assert sha(ROOT/'artifacts/firmware/monitor.elf')==compiler['ELF']['original_sha256']
    result['byte_identical_compilation']=dict(objects=len(compiler['objects']),ELF=True)
    sys.path.insert(0,str(ROOT/'exact/host/board_tools'))
    from run_graph_package import validate_package
    from cmos2_protocol import continuous_snapshot
    from completion_fps import calculate
    m,assets,runs=validate_package(ROOT/'model/canonical_model/palm/package/manifest.json')
    constants=[a for name,a in assets.items() if name!='input_hwc_i8']
    assert len(constants)==317 and sum(a['bytes'] for a in constants)==1856488
    assert sha(ROOT/'model/best_raw_heads_int8.onnx')==m['model_sha256']
    assert sum(x['count'] for x in runs)==204
    result['model']=dict(constants=317,bytes=1856488,graph_nodes=204,ONNX_sha256=m['model_sha256'])
    assert sha(ROOT/'artifacts/soc_board_camera_top.sbit')==frozen['bitstream_sha256']
    measurements=load(ROOT/'reports/REAL_BOARD_DATA_20261104.json')
    checked=[]
    for historical in measurements['runs']:
        name=PureWindowsPath(historical['path']).parent.name
        folder=ROOT/'evidence/board'/name
        r=load(folder/'result.json');c=r['continuous_preview']
        scene=folder/('continuous60_preview' if c['time_limit_seconds'] is not None else 'continuous_unbounded_preview')
        packed=scene/'completed_snapshots.bin'
        if packed.is_file():
            data=packed.read_bytes();assert len(data)%304==0
            raw=[data[i:i+304] for i in range(0,len(data),304)]
        else:raw=[p.read_bytes() for p in sorted(scene.glob('snapshot_[0-9]*.bin'))]
        samples=[];seen=0
        for packet in raw:
            snap=continuous_snapshot(packet);n=snap['completed'];row=snap['last_run']
            assert n>=seen
            if n>seen:
                assert row and row['pass_result'] and not snap['last_status']
                assert row['source']=='real CMOS2 capture' and row['graph_ops']==204
                assert row['capture_writer_pixels']==row['capture_sensor_pixels']==921600 and not row['capture_errors']
                samples.append(dict(completed=n,TR=row['timestamps_CPU64']['TR'],cpu_hz=row['cpu_hz'],generation=row['inference_source_generation'],frame_id=row['frame_id'],run_id=row['run_id']))
            seen=n
        measured=calculate(samples)
        assert measured==c['completion_interval_fps']==historical['FPS']
        assert seen==historical['frames']
        checked.append(dict(session=name,frames=seen,fps=measured['fps']))
    result.update(status='PASS',board_sessions_recomputed=checked,total_complete_inferences=sum(x['frames'] for x in checked))
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
