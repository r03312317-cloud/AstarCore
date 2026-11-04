#!/usr/bin/env python3
"""Record build input/output identities; refuses changed sources during build."""
import argparse,pathlib,json,hashlib
p=argparse.ArgumentParser();p.add_argument('action',choices=['capture','finish']);p.add_argument('model_dir',type=pathlib.Path);a=p.parse_args();root=pathlib.Path(__file__).resolve().parent.parent;d=a.model_dir.resolve();d.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
files=list((root/'rtl').glob('*.v'))+[root/'sim'/n for n in ['linux_video_boot_main.cpp','uart_terminal.h','video_checkpoint.h']]
now={str(p.relative_to(root)):sha(p) for p in sorted(files)}
pending=d/'runtime_build_inputs.json'
if a.action=='capture':
 pending.write_text(json.dumps({'project_files':now},indent=2)+'\n')
else:
 before=json.loads(pending.read_text())['project_files'];assert before==now,'Build sources changed; provenance refuses mixed revision'
 generated={p.name:sha(p) for p in sorted(d.iterdir()) if p.suffix in ['.cpp','.h','.mk']}
 model=d/'Vrv32_linux_video_top';m={'schema':1,'model_sha256':sha(model),'project_files':now,'generated_files':generated}
 (d/'runtime_source_manifest.json').write_text(json.dumps(m,indent=2)+'\n')
 print(d/'runtime_source_manifest.json')
