"""Compare the entire source tree with the immutable original PREBOARD archive."""
from pathlib import Path
import hashlib
import json
import zipfile
from audit_comments import original_from_annotated

ROOT = Path(__file__).resolve().parents[1]


def main():
    scope = json.loads((ROOT / 'audit/SOURCE_SCOPE.json').read_text())
    production = set(scope['hardware_rtl'] + scope['firmware_source'])
    metadata_only_in_baseline = {'PACKAGE_MANIFEST.json'}
    documented_tool_edits = {'tools/board_artifacts.py'}
    postboard_documents = {'README.md', 'docs/V03_ORIGIN.json'}
    new_expected = {'tools/source_identity.py', 'docs/V03_BOARD_ACCEPTANCE_20261103.json'}
    changed = []; originals = {}; tool_hashes = {}
    with zipfile.ZipFile(ROOT / 'baseline/original_preboard.zip') as z:
        originals = {name.split('/', 1)[1]: z.read(name) for name in z.namelist()
                     if name.startswith('rv32_soc_Mario_V03/') and not name.endswith('/')}
    for name, data in originals.items():
        if name in metadata_only_in_baseline:
            # Old raw-hash package manifest applies to the original PREBOARD
            # tree, not the new annotated tree. It remains intact in baseline/.
            continue
        current = (ROOT / 'source' / name).read_bytes()
        if current == data:
            continue
        changed.append(name)
        if name in production:
            assert original_from_annotated(current) == data, name
        else:
            assert name in documented_tool_edits | postboard_documents, 'Undocumented edit: ' + name
            tool_hashes[name] = hashlib.sha256(current).hexdigest()
    new = {p.relative_to(ROOT / 'source').as_posix() for p in (ROOT / 'source').rglob('*')
           if p.is_file() and p.relative_to(ROOT / 'source').as_posix() not in originals
           and '__pycache__' not in p.parts and p.suffix != '.pyc'}
    assert new == new_expected, new
    result = {
        'passed': True, 'original_payload_files_including_old_manifest': len(originals),
        'original_files_checked_in_source_tree': len(originals) - len(metadata_only_in_baseline),
        'original_metadata_retained_only_in_baseline_zip': sorted(metadata_only_in_baseline),
        'changed_original_files': changed, 'new_files': sorted(new),
        'non_document_edits_are_production_comments_and_documented_identity_tools': True,
        'postboard_documents_updated_after_preboard_archive': sorted(postboard_documents),
        'documented_tool_sha256': tool_hashes,
        'new_board_acceptance_document': 'copied from already completed V03 board acceptance',
    }
    (ROOT / 'audit/FULL_SOURCE_DIFF_AUDIT.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Full source tree audit passed:', result['original_files_checked_in_source_tree'],
          'original files;', len(changed), 'comment/tool edits;', len(new), 'documented additions.')


if __name__ == '__main__':
    main()
