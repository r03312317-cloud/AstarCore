# 架构导读：run_graph_package。
# 主机执行入口，组织本文件中显式选择的检查或板卡操作流程。
"""Load a preconverted INT8 graph package into board DDR and execute it."""
from pathlib import Path
import argparse
import hashlib
import json

from board_monitor import Monitor, checked_range
from graph_descriptor import DESCRIPTOR_BYTES, MAX_OPS


# 接口 sha，显式输入字段：data。
# 本函数调用入口包括 hashlib.sha256(data).hexdigest, hashlib.sha256。
def sha(data):
    # 向调用方返回本步骤结果：hashlib.sha256(data).hexdigest()。
    return hashlib.sha256(data).hexdigest()


# 接口 overlaps，显式输入字段：a, al, b, bl。
# 该函数直接更新本地状态或返回计算值，具体返回对象见函数体。
def overlaps(a,al,b,bl):
    # 向调用方返回本步骤结果：a<b+bl and b<a+al。
    return a<b+bl and b<a+al


# 接口 validate_package，显式输入字段：manifest_path。
# 本函数调用入口包括 manifest_path.resolve, json.loads, manifest.get, manifest_path.read_text, ValueError。
def validate_package(manifest_path):
    manifest_path=manifest_path.resolve()
    root=manifest_path.parent
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    # 按条件 manifest.get('schema') != 'soc-int8-graph-package-v1' 选择后续流程，保留原有异常和退出分支。
    if manifest.get('schema')!='soc-int8-graph-package-v1':
        # 停止当前调用并上报异常：raise ValueError('Unsupported graph package schema')。
        raise ValueError('Unsupported graph package schema')
    build=manifest.get('firmware_build_id')
    # 按条件 not isinstance(build, str) or len(build) != 16 or (not all((c in '0123456789abcdef' for c in build))) 选择后续流程，保留原有异常和退出分支。
    if not isinstance(build,str) or len(build)!=16 or not all(c in '0123456789abcdef' for c in build):
        # 停止当前调用并上报异常：raise ValueError('Package firmware build ID must be 16 lowercase hex digits')。
        raise ValueError('Package firmware build ID must be 16 lowercase hex digits')
    assets={}
    # 迭代/等待条件：manifest.get('assets', [])；退出由原循环条件及显式 break/异常决定。
    for item in manifest.get('assets',[]):
        name=item['name']
        # 按条件 not isinstance(name, str) or not name or name in assets 选择后续流程，保留原有异常和退出分支。
        if not isinstance(name,str) or not name or name in assets:
            # 停止当前调用并上报异常：raise ValueError('Asset names must be unique and nonempty')。
            raise ValueError('Asset names must be unique and nonempty')
        path=(root/item['file']).resolve()
        # 按条件 not path.is_relative_to(root) or not path.is_file() 选择后续流程，保留原有异常和退出分支。
        if not path.is_relative_to(root) or not path.is_file():
            # 停止当前调用并上报异常：raise ValueError('Asset file must be inside the package folder')。
            raise ValueError('Asset file must be inside the package folder')
        raw=path.read_bytes()
        address=item['address']
        checked_range(address,len(raw))
        # 按条件 len(raw) != item['bytes'] or sha(raw) != item['sha256'] 选择后续流程，保留原有异常和退出分支。
        if len(raw)!=item['bytes'] or sha(raw)!=item['sha256']:
            # 停止当前调用并上报异常：raise ValueError(f'Asset length/hash mismatch: {name}')。
            raise ValueError(f'Asset length/hash mismatch: {name}')
        # 按条件 any((overlaps(address, len(raw), a['address'], a['bytes']) for a in assets.values())) 选择后续流程，保留原有异常和退出分支。
        if any(overlaps(address,len(raw),a['address'],a['bytes']) for a in assets.values()):
            # 停止当前调用并上报异常：raise ValueError(f'Asset DDR range overlaps another asset: {name}')。
            raise ValueError(f'Asset DDR range overlaps another asset: {name}')
        assets[name]=dict(path=path,bytes=len(raw),address=address,sha256=item['sha256'])
    # 按条件 not assets 选择后续流程，保留原有异常和退出分支。
    if not assets:
        # 停止当前调用并上报异常：raise ValueError('Package has no assets')。
        raise ValueError('Package has no assets')
    runs=[]
    # 迭代/等待条件：manifest.get('runs', [])；退出由原循环条件及显式 break/异常决定。
    for item in manifest.get('runs',[]):
        name=item['descriptor_asset']
        # 按条件 name not in assets 选择后续流程，保留原有异常和退出分支。
        if name not in assets:
            # 停止当前调用并上报异常：raise ValueError('Graph descriptor asset is missing')。
            raise ValueError('Graph descriptor asset is missing')
        count=item['count']
        # 按条件 not isinstance(count, int) or not 1 <= count <= MAX_OPS or assets[name]['bytes'] != count * DESCRIPTOR_BYTES 选择后续流程，保留原有异常和退出分支。
        if not isinstance(count,int) or not 1<=count<=MAX_OPS or \
           assets[name]['bytes']!=count*DESCRIPTOR_BYTES:
            # 停止当前调用并上报异常：raise ValueError('Graph descriptor count/size mismatch')。
            raise ValueError('Graph descriptor count/size mismatch')
        trace=item['trace_base'];final=item['final_output'];size=item['final_bytes']
        checked_range(trace,count*24);checked_range(final,size)
        desc=assets[name]
        # 按条件 trace & 3 or desc['address'] & 3 or overlaps(trace, count * 24, desc['address'], desc['bytes']) or overlaps... 选择后续流程，保留原有异常和退出分支。
        if (trace&3 or desc['address']&3 or
            overlaps(trace,count*24,desc['address'],desc['bytes']) or
            overlaps(final,size,trace,count*24) or
            overlaps(final,size,desc['address'],desc['bytes'])):
            # 停止当前调用并上报异常：raise ValueError('Graph control/output DDR ranges conflict')。
            raise ValueError('Graph control/output DDR ranges conflict')
        # 按条件 any((overlaps(trace, count * 24, asset['address'], asset['bytes']) or overlaps(final, size, asset['address'... 选择后续流程，保留原有异常和退出分支。
        if any(overlaps(trace,count*24,asset['address'],asset['bytes']) or
               overlaps(final,size,asset['address'],asset['bytes'])
               for asset in assets.values()):
            # 停止当前调用并上报异常：raise ValueError('Graph trace/final output overlaps an immutable asset')。
            raise ValueError('Graph trace/final output overlaps an immutable asset')
        expected=item.get('expected_final_sha256')
        # 按条件 expected is not None and (not isinstance(expected, str) or len(expected) != 64) 选择后续流程，保留原有异常和退出分支。
        if expected is not None and (not isinstance(expected,str) or len(expected)!=64):
            # 停止当前调用并上报异常：raise ValueError('Expected final SHA-256 must be 64 hex digits')。
            raise ValueError('Expected final SHA-256 must be 64 hex digits')
        runs.append(dict(descriptor_asset=name,count=count,trace_base=trace,
                         final_output=final,final_bytes=size,
                         expected_final_sha256=expected))
    # 按条件 not runs 选择后续流程，保留原有异常和退出分支。
    if not runs:
        # 停止当前调用并上报异常：raise ValueError('Package has no graph runs')。
        raise ValueError('Package has no graph runs')
    # 向调用方返回本步骤结果：manifest,assets,runs。
    return manifest,assets,runs


# 接口 main，显式输入字段：无位置参数。
# 本函数调用入口包括 argparse.ArgumentParser, parser.add_argument, parser.parse_args, validate_package, args.out.resolve。
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
    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        # 资源上下文：with Monitor.open(args.port,out,timeout=40.0) as mon:；离开上下文时执行对应清理约定。
        with Monitor.open(args.port,out,timeout=40.0) as mon:
            result['identity']=mon.ping(manifest['firmware_build_id'])
            loaded=[]
            # 迭代/等待条件：assets.items()；退出由原循环条件及显式 break/异常决定。
            for name,asset in assets.items():
                receipt=mon.load_file(asset['path'],asset['address'])
                loaded.append(dict(name=name,**receipt))
            result['assets']=loaded
            completed=[]
            # 迭代/等待条件：enumerate(runs)；退出由原循环条件及显式 break/异常决定。
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
            # 迭代/等待条件：completed；退出由原循环条件及显式 break/异常决定。
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
    # 向调用方返回本步骤结果：0 if result['pass'] else 1。
    return 0 if result['pass'] else 1


# 按条件 __name__ == '__main__' 选择后续流程，保留原有异常和退出分支。
if __name__=='__main__':
    # 停止当前调用并上报异常：raise SystemExit(main())。
    raise SystemExit(main())
