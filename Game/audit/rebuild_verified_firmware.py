"""Rebuild annotated-source inputs while retaining original diagnostic locations.

Compiler __FILE__/__LINE__ values can change an assert diagnostic even when only
comments change. Recovering the marked lines and mapping the source prefix makes
the firmware reproducible, while all normal program tokens remain unchanged.
The accepted binary is never overwritten.
"""
from pathlib import Path
import datetime,hashlib,json,shutil,subprocess,sys
from audit_comments import original_from_annotated
ROOT=Path(__file__).resolve().parents[1]
EXPECTED='46ad6c47ada60bff9f0656da3175f0e7ea8a89fa0828d8db0bc71cf8eb4823bb'

def main():
    scope=json.loads((ROOT/'audit/SOURCE_SCOPE.json').read_text())
    source=ROOT/'source'
    record=json.loads((ROOT/'evidence/firmware/input_sha256.json').read_text())
    out=ROOT/'audit'/('rebuild_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    work=out/'project'
    (work/'tools').mkdir(parents=True);(work/'build').mkdir()
    derived={}
    for name,digest in record.items():
        annotated=(source/name).read_bytes()
        original=original_from_annotated(annotated) if name in scope['baseline_sha256'] else annotated
        if hashlib.sha256(original).hexdigest()!=digest:
            raise RuntimeError('Recovered compiler input differs: '+name)
        dest=work/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(original)
        derived[name]={'annotated_sha256':hashlib.sha256(annotated).hexdigest(),'compiler_input_sha256':digest}
    builder=(source/'tools/build_mario.py').read_text()
    prefix='-ffile-prefix-map='+str(work)+'='+scope['baseline_project']
    assert builder.count("flags=arch+[")==1
    builder=builder.replace("flags=arch+[","flags=arch+["+repr(prefix)+"]+[",1)
    (work/'tools/build_mario.py').write_text(builder,encoding='utf-8')
    run=subprocess.run([sys.executable,'-B','-X','utf8',str(work/'tools/build_mario.py')],cwd=work,capture_output=True)
    (out/'build.log').write_bytes(run.stdout+run.stderr)
    if run.returncode:raise RuntimeError('Firmware rebuild failed: '+str(out))
    built=json.loads((work/'build/LATEST_MARIO.json').read_text())
    binary=Path(built['binary'])
    digest=hashlib.sha256(binary.read_bytes()).hexdigest()
    result={'passed':digest==EXPECTED,'binary_sha256':digest,'expected_board_binary_sha256':EXPECTED,
            'binary_bytes':binary.stat().st_size,'binary_identical_to_physical_board_image':digest==EXPECTED,
            'compiler_inputs_derived_from_annotated_source':True,'original_diagnostic_locations_preserved':True,
            'evidence':str(out),'binary':str(binary),'inputs':derived}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    (ROOT/'audit/REBUILD_VERIFICATION.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='inputs'},indent=2))
    if digest!=EXPECTED:raise RuntimeError('Rebuilt image does not match the physical board image')
if __name__=='__main__':main()
