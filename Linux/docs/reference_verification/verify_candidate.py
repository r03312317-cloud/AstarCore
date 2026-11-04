"""Verify the delivered source and operator kit without accessing the board."""
from pathlib import Path,PurePosixPath
import hashlib,json,subprocess,sys
R=Path(__file__).resolve().parent
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda:f.read(1048576),b''):h.update(chunk)
    return h.hexdigest()
def main():
    src=json.loads((R/'source_manifest.json').read_text(encoding='utf-8'))
    for name,expected in src['files_sha256'].items():
        p=(R/name).resolve()
        if not p.is_relative_to(R.resolve()) or digest(p)!=expected:raise ValueError('Source hash mismatch: '+name)
    imported=json.loads((R/'provenance/import_result.json').read_text(encoding='utf-8'))
    for row in imported['files']:
        if digest(R/'provenance/core01_original'/row['file'])!=row['sealed_sha256']:raise ValueError('Imported Core_01 source mismatch')
    archive=R/'ARCHIVE_MANIFEST.json'
    if archive.exists():
        m=json.loads(archive.read_text(encoding='utf-8'))
        for row in m['files']:
            rel=PurePosixPath(row['path'])
            if rel.is_absolute() or '..' in rel.parts:raise ValueError('Unsafe manifest member')
            p=R.joinpath(*rel.parts)
            if p.is_symlink() or p.stat().st_size!=row['size'] or digest(p)!=row['sha256']:raise ValueError('Archive hash mismatch: '+str(rel))
    kit=R/'operator'
    if kit.exists():subprocess.run([sys.executable,'-B',str(kit/'verify_kit.py')],cwd=kit,check=True)
    print(json.dumps({'source_files_verified':len(src['files_sha256']),'core01_originals_verified':len(imported['files']),
                      'source_build_id':src['core01_build_id'],'board_access':False},indent=2))
if __name__=='__main__':main()
