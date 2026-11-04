"""Recompute the published performance values from immutable physical UART bytes.

No board access, downloads or scheduled work.  Samples from different game
states are deliberately kept separate; MODE=1 alone does not prove active play.
"""
from pathlib import Path
import csv
import hashlib
import importlib.util
import json
import math
import re

ROOT = Path(__file__).resolve().parents[1]
HZ = 100_000_000
UART_SHA = 'f155de38b03118099c0ee7a10db4f9cf4baa174be0cac252f7e99ed72e994c4e'


def read_samples(data):
    return [{k: int(v) for k, v in re.findall(r'([A-Z_]+)=(\d+)', line)}
            for line in data.decode('utf-8', errors='replace').splitlines()
            if 'MARIO_FRAME=' in line]


def fps(rows):
    return HZ * sum(s['VDELTA'] for s in rows) / sum(s['CYCLES'] for s in rows)


def main():
    board = ROOT / 'evidence/board'
    raw = (board / 'mario_uart.bin').read_bytes()
    assert hashlib.sha256(raw).hexdigest() == UART_SHA, 'Raw physical UART changed'
    samples = read_samples(raw)
    assert len(samples) == 176
    with (board / 'frame_samples.csv').open(newline='') as handle:
        csv_rows = [{k: int(v) for k, v in row.items()} for row in csv.DictReader(handle)]
    assert samples == csv_rows, 'Derived CSV differs from raw UART'
    for before, after in zip(samples, samples[1:]):
        t0 = (before['CYCLE_HI'] << 32) | before['CYCLE_LO']
        t1 = (after['CYCLE_HI'] << 32) | after['CYCLE_LO']
        assert t1 - t0 == after['CYCLES']
        assert after['MARIO_FRAME'] - before['MARIO_FRAME'] == after['DELTA']
        assert (after['VID'] - before['VID']) & 0xffffffff == after['VDELTA']
    # Validate the exact physical held-right boundaries from raw key events.
    text = raw.decode(errors='replace')
    key_lines = [line for line in text.splitlines() if 'MARIO_KEY=' in line]
    right_events = [{k: int(v) for k, v in re.findall(r'([A-Z_]+)=(\d+)', line)}
                    for line in key_lines]
    right_events = [s for s in right_events if s.get('MARIO_KEY') == 8]
    assert any(s.get('DOWN') == 1 and s.get('FRAME') == 2239 for s in right_events)
    assert any(s.get('DOWN') == 0 and s.get('FRAME') == 2381 for s in right_events)
    title = [s for s in samples if s['MODE'] == 0 and s['X'] == 40]
    active = [s for s in samples if s['MODE'] == 1 and s['TASK'] == 3
              and s['MARIO_FRAME'] - s['DELTA'] >= 2239 and s['MARIO_FRAME'] <= 2381]
    acceptance = json.loads((board / 'acceptance.json').read_text())
    assert len(title) == 34 and len(active) == 6
    assert math.isclose(fps(title), acceptance['title']['weighted_framebuffer_publications_per_second'], rel_tol=1e-12)
    assert math.isclose(fps(active), acceptance['right_held_active_gameplay']['weighted_framebuffer_publications_per_second'], rel_tol=1e-12)
    spec = importlib.util.spec_from_file_location('analyze_uart', ROOT / 'source/tools/analyze_uart.py')
    analyzer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(analyzer)
    analyzed = analyzer.analyze(raw)
    assert analyzed == json.loads((board / 'performance.json').read_text())
    baseline_raw = (ROOT / 'evidence/baseline_v02/mario_uart.bin').read_bytes()
    baseline = analyzer.analyze(baseline_raw)['groups']['title_mode0_x40']
    assert math.isclose(baseline['weighted_framebuffer_publications_per_second'],
                        acceptance['v02_title_baseline']['weighted_framebuffer_publications_per_second'], rel_tol=1e-12)
    result = {
        'passed': True, 'raw_uart_sha256_matches': True,
        'derived_csv_exactly_matches_raw_uart': True,
        'hardware_cycle_frame_and_video_deltas_consistent': True,
        'title_samples': len(title), 'title_publications_fps': fps(title),
        'right_active_samples': len(active), 'right_active_fps': fps(active),
        'right_physical_button_boundaries_verified': True,
        'sample_seconds': sum(s['CYCLES'] for s in samples) / HZ,
        'v02_title_publications_fps': baseline['weighted_framebuffer_publications_per_second'],
        'title_ratio_v03_over_v02': fps(title) / baseline['weighted_framebuffer_publications_per_second'],
        'scope': 'successful framebuffer publications from physical UART; not the HDMI carrier or whole-level FPS',
    }
    (ROOT / 'audit/PERFORMANCE_RECALCULATION.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
