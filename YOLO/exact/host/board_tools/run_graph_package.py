"""Load a preconverted INT8 graph package into board DDR and execute it."""
from pathlib import Path
import argparse
import hashlib
import json

from board_monitor import Monitor, checked_range
from graph_descriptor import DESCRIPTOR_BYTES, MAX_OPS


def sha(data):
    return hashlib.sha256(data).hexdigest()


def overlaps(a,al,b,bl):
    return a<b+bl and b<a+al


def validate_package(manifest_path):
    manifest_path=manifest_path.resolve()
    root=manifest_path.parent
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest.get('schema')!='soc-int8-graph-package-v1':
        raise ValueError('Unsupported graph package schema')
    build=manifest.get('firmware_build_id')
    if not isinstance(build,str) or len(build)!=16 or not all(c in '0123456789abcdef' for c in build):
        raise ValueError('Package firmware build ID must be 16 lowercase hex digits')
    assets={}
    for item in manifest.get('assets',[]):
        name=item['name']
        if not isinstance(name,str) or not name or name in assets:
            raise ValueError('Asset names must be unique and nonempty')
        path=(root/item['file']).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError('Asset file must be inside the package folder')
        raw=path.read_bytes()
        address=item['address']
        checked_range(address,len(raw))
        if len(raw)!=item['bytes'] or sha(raw)!=item['sha256']:
            raise ValueError(f'Asset length/hash mismatch: {name}')
        if any(overlaps(address,len(raw),a['address'],a['bytes']) for a in assets.values()):
            raise ValueError(f'Asset DDR range overlaps another asset: {name}')
        assets[name]=dict(path=path,bytes=len(raw),address=address,sha256=item['sha256'])
    if not assets:
        raise ValueError('Package has no assets')
    runs=[]
    for item in manifest.get('runs',[]):
        name=item['descriptor_asset']
        if name not in assets:
            raise ValueError('Graph descriptor asset is missing')
        count=item['count']
        if not isinstance(count,int) or not 1<=count<=MAX_OPS or \
           assets[name]['bytes']!=count*DESCRIPTOR_BYTES:
            raise ValueError('Graph descriptor count/size mismatch')
        trace=item['trace_base'];final=item['final_output'];size=item['final_bytes']
        checked_range(trace,count*24);checked_range(final,size)
        desc=assets[name]
        if (trace&3 or desc['address']&3 or
            overlaps(trace,count*24,desc['address'],desc['bytes']) or
            overlaps(final,size,trace,count*24) or
            overlaps(final,size,desc['address'],desc['bytes'])):
            raise ValueError('Graph control/output DDR ranges conflict')
        if any(overlaps(trace,count*24,asset['address'],asset['bytes']) or
               overlaps(final,size,asset['address'],asset['bytes'])
               for asset in assets.values()):
            raise ValueError('Graph trace/final output overlaps an immutable asset')
        expected=item.get('expected_final_sha256')
        if expected is not None and (not isinstance(expected,str) or len(expected)!=64):
            raise ValueError('Expected final SHA-256 must be 64 hex digits')
        runs.append(dict(descriptor_asset=name,count=count,trace_base=trace,
                         final_output=final,final_bytes=size,
                         expected_final_sha256=expected))
    if not runs:
        raise ValueError('Package has no graph runs')
    return manifest,assets,runs


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,required=True,
                        help='Path to manifest.json inside a preconverted package')
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--port',default='COM14')
    args=parser.parse_args()
    manifest,assets,runs=validate_package(args.package)
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    result=dict(pass_=False,package=str(args.package.resolve()),
                package_sha256=sha(args.package.read_bytes()),port=args.port,
                scope='Physical loading and execution of a preconverted INT8 graph package; no .pt/ONNX conversion, sensor or recognition claim')
    try:
        with Monitor.open(args.port,out,timeout=40.0) as mon:
            result['identity']=mon.ping(manifest['firmware_build_id'])
            loaded=[]
            for name,asset in assets.items():
                receipt=mon.load_file(asset['path'],asset['address'])
                loaded.append(dict(name=name,**receipt))
            result['assets']=loaded
            completed=[]
            for index,run in enumerate(runs):
                desc=assets[run['descriptor_asset']]
                graph=mon.run_graph(desc['address'],run['count'],run['trace_base'],
                                    run['final_output'],run['final_bytes'])
                output=mon.read_memory(run['final_output'],run['final_bytes'])
                (out/f'output_{index}.bin').write_bytes(output)
                digest=sha(output)
                passed=(run['expected_final_sha256'] is None or
                        digest==run['expected_final_sha256'])
                completed.append(dict(index=index,graph=graph,
                                      final_output_sha256=digest,
                                      expected_final_sha256=run['expected_final_sha256'],
                                      pass_=passed))
            for row in completed:row['pass']=row.pop('pass_')
            result['runs']=completed
            result['pass_']=all(row['pass'] for row in completed)
    except Exception as exc:
        result['error']=f'{type(exc).__name__}: {exc}'
    result['pass']=result.pop('pass_')
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(pass_=result['pass'],error=result.get('error'),
                          assets=len(result.get('assets',[])),
                          runs=[x['pass'] for x in result.get('runs',[])]),indent=2))
    return 0 if result['pass'] else 1


if __name__=='__main__':
    raise SystemExit(main())
