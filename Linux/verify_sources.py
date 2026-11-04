"""Read-only verification of the annotated source and original tested identity.

No serial, JTAG, GUI launch, PDS invocation, or scheduled task is performed.
"""
from pathlib import Path,PurePosixPath
import ast,hashlib,importlib.util,json

ROOT=Path(__file__).resolve().parent
def load(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(data):return hashlib.sha256(data).hexdigest()
def safe(name):
    rel=PurePosixPath(name)
    if rel.is_absolute() or '..' in rel.parts or '\\' in name or ':' in name:raise ValueError('Invalid path: '+name)
    p=ROOT.joinpath(*rel.parts)
    if not p.resolve().is_relative_to(ROOT) or p.is_symlink() or not p.is_file():raise ValueError('Missing/nonlocal file: '+name)
    return p

def main():
    manifest=load(ROOT/'SOURCE_PACKAGE_MANIFEST.json')
    for row in manifest['files']:
        p=safe(row['path']);data=p.read_bytes()
        if len(data)!=row['bytes'] or sha(data)!=row['sha256']:raise ValueError('Hash mismatch: '+row['path'])
    changes=load(ROOT/'documentation/annotation_changes.json')['files']
    recovered={}
    spec=importlib.util.spec_from_file_location('local_comment_metrics',ROOT/'tools/comment_metrics.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    for row in changes:
        data=safe(row['path']).read_bytes();text=data.decode('utf-8-sig');lines=text.splitlines(keepends=True)
        ins={x['line']:x['text'] for x in row['insertions']}
        if len(ins)!=len(row['insertions']):raise ValueError('Duplicate insertion record')
        for number,value in ins.items():
            if not 1<=number<=len(lines) or lines[number-1]!=value:raise ValueError('Annotation mismatch: '+row['path'])
        old=''.join(s for i,s in enumerate(lines,1) if i not in ins).encode('utf-8')
        if data.startswith(b'\xef\xbb\xbf'):old=b'\xef\xbb\xbf'+old
        if sha(old)!=row['before_sha256'] or sha(data)!=row['after_sha256']:raise ValueError('Original recovery mismatch: '+row['path'])
        p=ROOT/row['path'];language=mod.language(p)
        if language=='python':
            assert ast.dump(ast.parse(text),include_attributes=False)==ast.dump(ast.parse(old.decode('utf-8-sig')),include_attributes=False)
        elif language=='c':assert mod.c_scan(text)[2:]==mod.c_scan(old.decode('utf-8-sig'))[2:]
        recovered[row['path']]=old
    baseline=load(ROOT/'provenance/board_tested_baseline_metadata/SOURCE_PACKAGE_MANIFEST.json')
    changed_metadata={'source_manifest.json','SOURCE_VERSION.json','PACKAGE_SCOPE.json','README.md','verify_sources.py'}
    for row in baseline['files']:
        name=row['path']
        if name in recovered:data=recovered[name]
        elif name in changed_metadata:data=safe('provenance/board_tested_baseline_metadata/'+name).read_bytes()
        else:data=safe(name).read_bytes()
        if len(data)!=row['bytes'] or sha(data)!=row['sha256']:raise ValueError('Tested baseline mismatch: '+name)
    current=load(ROOT/'source_manifest.json')
    tested=load(ROOT/'provenance/board_tested_baseline_metadata/source_manifest.json')
    assert current['source_order']==tested['source_order']
    for name,digest in current['files_sha256'].items():assert sha(safe(name).read_bytes())==digest,name
    for name,digest in tested['files_sha256'].items():assert sha(recovered.get(name,safe(name).read_bytes()))==digest,name
    stats=mod.measure(ROOT)
    main=stats['groups']['project_production_total']
    assert main['files']==80 and 29<=main['comment_percent']<=31,main
    originals=load(ROOT/'provenance/import_result.json')['files']
    for row in originals:assert sha(safe('provenance/core01_original/'+row['file']).read_bytes())==row['sealed_sha256']
    print(json.dumps({'passed':True,'package_files':len(manifest['files']),
        'tested_baseline_files_recovered':len(baseline['files']),'annotation_sources':len(changes),
        'pds_inputs':len(current['files_sha256']),'ordered_hdl_sources':len(current['source_order']),
        'cpu_originals':len(originals),'main_source_comment_percent':main['comment_percent'],
        'hardware_access':False,'source_only':True},ensure_ascii=True,indent=2))

if __name__=='__main__':main()
