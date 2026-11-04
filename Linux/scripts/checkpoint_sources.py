#!/usr/bin/env python3
"""Snapshot source hashes and baseline-relative RTL patch; no build claims."""
import argparse, datetime, hashlib, json, pathlib, subprocess
r=pathlib.Path(__file__).resolve().parent.parent
p=argparse.ArgumentParser();p.add_argument('name');a=p.parse_args()
if not a.name.replace('_','').replace('-','').isalnum():raise SystemExit('Use a simple checkpoint name')
d=r/'reports/checkpoints'/a.name;d.mkdir(parents=True,exist_ok=True)
roots=['rtl','sim','scripts','linux','firmware/opensbi','gui','buildroot','boards']
files=[]
for root in roots:
 for f in (r/root).rglob('*'):
  if f.is_file() and not f.is_symlink() and not any(x in {'build','__pycache__'} or x.startswith('build_') for x in f.relative_to(r).parts[:-1]):files.append(f)
hashes={str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(set(files))}
(d/'sources.json').write_text(json.dumps({'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sha256':hashes},indent=2)+'\n')
with (d/'baseline_rtl.patch').open('w') as out:
 subprocess.run(['diff','-ruN','baseline/rtl','rtl'],cwd=r,stdout=out,check=False)
models={}
for f in [r/'build/soc/Vrv32_linux_soc_top',r/'build/video/Vrv32_linux_video_top']:
 if f.exists():models[str(f.relative_to(r))]=hashlib.sha256(f.read_bytes()).hexdigest()
(d/'simulation_models.json').write_text(json.dumps(models,indent=2)+'\n')
print(d)
