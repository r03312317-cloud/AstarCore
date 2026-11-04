#!/usr/bin/env python3
"""Package a byte-consistent source/evidence snapshot without local build products."""
import argparse, datetime, hashlib, json, pathlib, zipfile
root=pathlib.Path(__file__).resolve().parent.parent
p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--compact',action='store_true',help='omit redundant historical/generated firmware; retain CPU-v1/video-v4');p.add_argument('--max-bytes',type=int);a=p.parse_args()
out=a.output.resolve()
if root==out or root in out.parents: raise SystemExit('Output must be outside project to avoid recursive packaging')
excluded=('firmware/generated/','firmware/snapshots/','firmware/boot-video-v1/','firmware/boot-video-v2/','firmware/boot-video-v3/') if a.compact else ()
def include(path):
 rel=path.relative_to(root)
 if any(rel.as_posix().startswith(prefix) for prefix in excluded):return False
 # Runtime checkpoints belong beside the project, never in a source release.
 if path.suffix in {'.ckpt','.tmp'} or 'rv32_runtime_state' in rel.parts:return False
 if rel.parts[0]=='reports' and any(x.startswith('checkpoint') for x in rel.parts[1:-1]) and path.name.endswith(('.bin','.ckpt','.tmp')):return False
 return not any(x in {'build','obj_dir','.git','__pycache__','.tools'} or x.startswith('build_') for x in rel.parts[:-1]) and path.suffix not in {'.pyc','.o','.a','.gch'} and not path.is_symlink()
files=sorted(x for x in root.rglob('*') if x.is_file() and include(x) and x.relative_to(root).as_posix()!='reports/RELEASE_SHA256.json')
# Read each file exactly once: logs may still be appended during an interim
# checkpoint. Archive hashes must describe archived bytes, not later live logs.
snapshot={str(f.relative_to(root)):(zipfile.ZipInfo.from_file(f,root.name+'/'+str(f.relative_to(root))),f.read_bytes()) for f in files}
required={'scripts/build_soc_sim.sh','scripts/build_video_boot_sim.sh','scripts/software_build.sh','rtl/rv32_ooo_core.v','sim/linux_soc_main.cpp','README.md'}
if a.compact:required.update({'firmware/boot-video-v4/Image','firmware/boot-video-v4/rootfs.cpio','firmware/boot-video-v4/fw_jump_quiet.bin','firmware/boot-video-v4/boot_manifest.json','CHANGELOG.md'})
missing=required-set(snapshot)
if missing:raise SystemExit('Required deliverables excluded: '+str(sorted(missing)))
manifest={'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'excluded_prefixes':list(excluded),'files':{name:hashlib.sha256(v[1]).hexdigest() for name,v in snapshot.items()}}
data=(json.dumps(manifest,indent=2)+'\n').encode()
(root/'reports/RELEASE_SHA256.json').write_bytes(data)
out.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for info,content in snapshot.values():z.writestr(info,content,compress_type=zipfile.ZIP_DEFLATED,compresslevel=6)
 z.writestr(root.name+'/reports/RELEASE_SHA256.json',data)
with zipfile.ZipFile(out) as z:
 bad=z.testzip()
 if bad:raise SystemExit('ZIP CRC failure '+bad)
 for name,digest in manifest['files'].items():
  if hashlib.sha256(z.read(root.name+'/'+name)).hexdigest()!=digest:raise SystemExit('Archive hash mismatch '+name)
if a.max_bytes and out.stat().st_size>a.max_bytes:raise SystemExit('Archive exceeds requested delivery size; do not attach')
print(json.dumps({'archive':str(out),'bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'files':len(snapshot)+1},indent=2))
