"""Recognize only the exact, audited comment-only view of an accepted source.

Binary artifacts and evidence snapshots keep their ordinary raw SHA-256 checks.
An edited program token cannot obtain this fallback without the audit rejecting
it against the immutable original archive.
"""
from pathlib import Path
import hashlib,json
from build_mario import ROOT

def source_matches(path,expected):
    path=Path(path)
    actual=hashlib.sha256(path.read_bytes()).hexdigest()
    if actual==expected:
        return True
    try:
        name=path.relative_to(ROOT).as_posix()
        report=json.loads((ROOT.parent/'audit/COMMENT_AUDIT.json').read_text(encoding='utf-8'))
        item=report['files'][name]
    except (ValueError,KeyError,FileNotFoundError):
        return False
    return (report['all_files_recover_original_bytes']
            and report['all_code_tokens_and_compiler_pragmas_equal']
            and item['exact_original_recovery']
            and item['code_tokens_and_synthesis_directives_equal']
            and actual==item['annotated_sha256']
            and expected==item['original_sha256'])
