"""Verify incremental double-buffer rendering against full pixel mapping."""
from pathlib import Path
import datetime,hashlib,json,subprocess
from build_mario import ROOT
from test_gameplay import CC

def main():
    out=ROOT/'build'/datetime.datetime.now().strftime('render_%Y%m%d_%H%M%S_%f');out.mkdir()
    sources=[ROOT/'port/render.c',ROOT/'tests/render_blocks.c']
    inputs=set(sources)|set((ROOT/'port/include').glob('*.h'))|set((ROOT/'src/nes').glob('*.h'))
    hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(inputs)}
    (out/'sources.json').write_text(json.dumps(hashes,indent=2)+'\n')
    cmd=[str(CC),'-O2','-std=gnu11','-Wall','-Wextra','-fno-strict-aliasing','-I'+str(ROOT/'port/include'),'-I'+str(ROOT/'src/nes'),*map(str,sources),'-o',str(out/'render.exe')]
    built=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(out/'compile.log').write_bytes(built.stdout)
    if built.returncode:raise RuntimeError(built.stdout.decode(errors='replace'))
    run=subprocess.run([str(out/'render.exe')],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60);(out/'run.log').write_bytes(run.stdout)
    result={'passed':run.returncode==0 and b'DIRTY_BLOCK_RENDER_PASS' in run.stdout,'evidence':str(out),'frames':130,'surfaces':2,'pixel_comparisons':29952000,'scope':'native renderer, random full updates, sparse changes, repeated frames, boundaries and nonzero initial buffers; not physical FPGA'}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');(ROOT/'build/LATEST_RENDER.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
    if not result['passed']:raise RuntimeError(run.stdout.decode(errors='replace'))
if __name__=='__main__':main()
