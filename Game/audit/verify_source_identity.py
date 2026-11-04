"""Positive/negative checks for the comment-only source identity adapter."""
from pathlib import Path
import datetime
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'source/tools'))
import source_identity


def main():
    report = json.loads((ROOT / 'audit/COMMENT_AUDIT.json').read_text(encoding='utf-8'))
    name, item = next((n, v) for n, v in report['files'].items()
                      if v['original_sha256'] != v['annotated_sha256'])
    assert source_identity.source_matches(ROOT / 'source' / name, item['original_sha256'])
    # Work only in a new fixture. Keep it on disk as audit evidence; the release
    # packager excludes fixture source so it cannot be confused with production.
    negative = ROOT / 'audit' / ('identity_negative_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    target = negative / 'source' / name
    target.parent.mkdir(parents=True)
    (negative / 'audit').mkdir()
    (negative / 'audit/COMMENT_AUDIT.json').write_text(json.dumps(report), encoding='utf-8')
    target.write_bytes((ROOT / 'source' / name).read_bytes() + b'\nwire changed_program_token;\n')
    source_identity.ROOT = negative / 'source'
    assert not source_identity.source_matches(target, item['original_sha256'])
    binary = negative / 'source/platform/fixture.bin'
    binary.parent.mkdir(parents=True)
    binary.write_bytes(b'changed binary')
    assert not source_identity.source_matches(binary, hashlib.sha256(b'original binary').hexdigest())
    result = {'passed': True, 'known_annotated_raw_hash_accepted': True,
              'changed_code_rejected': True, 'binary_never_uses_comment_fallback': True}
    (ROOT / 'audit/IDENTITY_HELPER_TEST.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
