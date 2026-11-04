"""Package and extract-verify this independent architecture source release.

Only new files and new directories are created. Original board evidence,
accepted binaries and earlier archives are never overwritten or cleaned.
"""
from pathlib import Path
import datetime
import hashlib
import json
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = next((p for p in ROOT.parents if (p / 'PERMANENT_RETENTION.json').is_file()), ROOT.parent)
PAYLOAD_ROOT = 'Game_Mario_V03'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select_files():
    files = []
    for path in sorted(ROOT.rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT)
        if '__pycache__' in rel.parts or path.suffix == '.pyc':
            continue
        if rel.parts[0] == 'audit' and len(rel.parts) > 1:
            # Canonical rebuild evidence is under evidence/rebuild. Scratch
            # compiler objects, source copies and deliberate negative fixtures
            # remain in the workspace, outside the production release payload.
            if len(rel.parts) > 2 and rel.parts[1].startswith(('identity_negative_', 'rebuild_', 'pdf_preview')):
                continue
            if rel.name.startswith(('PACKAGE_VERIFICATION', 'EXTRACTION_')):
                continue
        if rel.as_posix() == 'MANIFEST_SHA256.json':
            continue
        files.append((rel.as_posix(), path))
    return files


def run(command, cwd, log):
    result = subprocess.run([sys.executable, '-B', '-X', 'utf8', *map(str, command)],
                            cwd=cwd, capture_output=True)
    log.write_bytes(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError('Extracted package check failed: ' + str(log))


def main():
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    deliver = PROJECT / 'deliverables'
    deliver.mkdir(exist_ok=True)
    archive = deliver / ('Game_Mario_V03_Architecture_BOARD_TESTED_' + stamp + '.zip')
    assert not archive.exists()
    expected_archives = {
        'baseline/original_preboard.zip': '1346a101b08f7e9f7103738c1ab2673d58f7406d03a91505af9d95fe3ff436e4',
        'baseline/original_board_evidence.zip': 'b96a9d380e2972f7afc9afbc0fc03e283cb59526d6eadc457fa4b1866c8743ac',
    }
    for name, digest in expected_archives.items():
        assert sha(ROOT / name) == digest, 'Original archive changed: ' + name
    comment = json.loads((ROOT / 'audit/COMMENT_AUDIT.json').read_text(encoding='utf-8'))
    status = {
        'release_kind': 'independent annotated architecture source + archived physical-board evidence',
        'baseline': 'Mario V03, physical board session 2026-11-03 03:42-03:46 Asia/Shanghai',
        '整理日期': '2026-11-04',
        'physical_acceptance': 'evidence/board/acceptance.json',
        'new_board_session': False, 'new_place_and_route': False,
        'production_program_tokens_unchanged': True,
        'rebuild_binary_identical_to_physical_board_image': True,
        'comment_totals': comment['totals'],
        'complete_level_tested': False, 'audio_implemented': False,
        'manifest': 'MANIFEST_SHA256.json',
        'compact_rebuild_evidence': 'evidence/rebuild/',
        'exclusions': 'scratch compilation/negative fixtures and PDF preview PNGs retained only in work directory',
    }
    (ROOT / 'RELEASE_STATUS.json').write_text(json.dumps(status, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    files = select_files()
    records = {name: {'bytes': path.stat().st_size, 'sha256': sha(path)} for name, path in files}
    required = ['README.md', 'reports/实板功能与性能测试报告.pdf',
                'reports/架构与源码导航.md', 'reports/复现与校验说明.md',
                'audit/audit_comments.py', 'audit/rebuild_verified_firmware.py',
                'audit/verify_evidence.py', 'audit/verify_source_identity.py',
                'source/tools/program_mario.py', 'source/tools/source_identity.py',
                'evidence/rebuild/mario.bin', 'evidence/board/mario_uart.bin',
                'baseline/original_preboard.zip', 'baseline/original_board_evidence.zip']
    assert set(required) <= records.keys(), 'Missing required release payload'
    manifest = {'payload_root': PAYLOAD_ROOT, 'algorithm': 'SHA-256',
                'self_excluded': True, 'files': records}
    manifest_path = ROOT / 'MANIFEST_SHA256.json'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED, compresslevel=7) as z:
        for name, path in files:
            z.write(path, PAYLOAD_ROOT + '/' + name)
        z.write(manifest_path, PAYLOAD_ROOT + '/MANIFEST_SHA256.json')
    print('ARCHIVE_CREATED', archive, flush=True)
    verification = PROJECT / 'build' / ('mario_arch_verify_' + stamp)
    verification.mkdir(parents=True, exist_ok=False)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None, 'ZIP CRC check failed'
        assert len(z.namelist()) == len(records) + 1
        for name, item in records.items():
            data = z.read(PAYLOAD_ROOT + '/' + name)
            assert len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256'], name
        z.extractall(verification)
    extracted = verification / PAYLOAD_ROOT
    # Confirm actual extracted bytes, not just the archive directory listing.
    for name, item in records.items():
        target = extracted / name
        assert target.stat().st_size == item['bytes'] and sha(target) == item['sha256'], name
    assert (extracted / 'MANIFEST_SHA256.json').read_bytes() == manifest_path.read_bytes()
    run(['audit/audit_comments.py', '--verify'], extracted, verification / 'comment_audit.log')
    run(['audit/verify_full_source.py'], extracted, verification / 'full_source_audit.log')
    run(['audit/verify_evidence.py'], extracted, verification / 'performance_recalculation.log')
    run(['audit/verify_source_identity.py'], extracted, verification / 'source_identity.log')
    run(['source/tools/program_mario.py', '--qualify-only', '--report',
         extracted / 'audit/EXTRACTION_QUALIFICATION.json'], extracted, verification / 'qualification.log')
    run(['audit/rebuild_verified_firmware.py'], extracted, verification / 'firmware_rebuild.log')
    rebuilt = json.loads((extracted / 'audit/REBUILD_VERIFICATION.json').read_text())
    assert rebuilt['passed'] and rebuilt['binary_identical_to_physical_board_image']
    result = {
        'passed': True, 'archive': str(archive), 'archive_bytes': archive.stat().st_size,
        'archive_sha256': sha(archive), 'payload_files_including_manifest': len(records) + 1,
        'all_zip_crc_and_payload_sha256_verified': True,
        'all_extracted_payload_sha256_verified': True,
        'extracted_source_comment_audit_passed': True,
        'extracted_full_source_tree_audit_passed': True,
        'extracted_performance_recalculation_passed': True,
        'extracted_source_identity_positive_and_negative_checks_passed': True,
        'extracted_deployment_qualification_passed': True,
        'extracted_firmware_rebuild_identical_to_board_image': True,
        'board_not_used': True,
        'verification_directory': str(verification),
        'work_directory': str(ROOT),
        'pdf': str(ROOT / 'reports/实板功能与性能测试报告.pdf'),
    }
    sidecar = archive.with_suffix('.verification.json')
    sidecar.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (ROOT / 'audit/PACKAGE_VERIFICATION.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (ROOT.parent / 'LATEST_MARIO_ARCH_RELEASE.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)


if __name__ == '__main__':
    main()
