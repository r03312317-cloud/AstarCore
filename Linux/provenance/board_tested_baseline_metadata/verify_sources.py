"""Verify this source package only; never open serial/JTAG or launch PDS."""
from pathlib import Path,PurePosixPath
import hashlib,json
r=Path(__file__).resolve().parent
m=json.loads((r/'SOURCE_PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
for row in m['files']:
 rel=PurePosixPath(row['path']);assert not rel.is_absolute() and '..' not in rel.parts
 p=r.joinpath(*rel.parts)
 assert p.resolve().is_relative_to(r) and p.is_file() and not p.is_symlink(),str(p)
 assert p.stat().st_size==row['bytes'] and sha(p)==row['sha256'],str(p)
src=json.loads((r/'source_manifest.json').read_text(encoding='utf-8'))
for path,expected in src['files_sha256'].items():assert sha(r/path)==expected,path
imp=json.loads((r/'provenance/import_result.json').read_text(encoding='utf-8'))
for row in imp['files']:assert sha(r/'provenance/core01_original'/row['file'])==row['sealed_sha256'],row['file']
print(json.dumps({'passed':True,'package_files':len(m['files']),'pds_inputs':len(src['files_sha256']),
 'ordered_hdl_sources':len(src['source_order']),'core01_originals':len(imp['files']),
 'cpu_configured_hz':m['cpu_configured_hz'],'source_only':True,'hardware_access':False},indent=2))
