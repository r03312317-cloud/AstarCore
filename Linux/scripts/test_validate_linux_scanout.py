#!/usr/bin/env python3
"""Synthetic validator tests ONLY: fixtures are NOT Linux/RTL/GUI evidence."""
import array
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / 'scripts/validate_linux_scanout.py'

def encode(words):
    values = array.array('H', words)
    if sys.byteorder != 'little':
        values.byteswap()
    return values.tobytes()

def pixel_fnv(words):
    result = 2166136261
    for word in words:
        result = (result ^ word) * 16777619 % (1 << 32)
    return f'{result:08x}'

class ScanoutValidator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='rv32_SYNTHETIC_VALIDATOR_ONLY_')
        cls.folder = Path(cls.tmp.name)
        # Arbitrary coordinate-dependent words, not a screenshot or GUI rendering.
        cls.logical = [(x * 257 ^ y * 911 ^ (x >> 2) ^ 0xa55a) & 65535
                       for y in range(360) for x in range(640)]
        cls.physical = []
        for y in range(360):
            doubled = [v for v in cls.logical[y * 640:(y + 1) * 640] for _ in range(2)]
            cls.physical.extend(doubled + doubled)
        cls.raw = encode(cls.physical)
        cls.ref = cls.folder / 'SYNTHETIC_VALIDATION_ONLY_reference.rgb565'
        cls.ref.write_bytes(encode(cls.logical))
        cls.meta = {
            # Required format label is deliberately emulated by this test fixture.
            # A metadata string is NOT a proof of actual RTL provenance.
            'source': 'actual RTL digital scanout', 'width': 1280, 'height': 720,
            'format': 'RGB565 little-endian', 'underflow_rows_delta': 0,
            'dma_errors_delta': 0, 'bounds_errors_delta': 0,
            'fnv1a_pixel16': pixel_fnv(cls.physical),
            'fixture_provenance': 'SYNTHETIC VALIDATOR TEST ONLY; NOT GUI SUCCESS',
        }
        (cls.folder / 'NOT_ACTUAL_CAPTURE.txt').write_text(
            'All fixtures here are synthetic unit-test inputs, not observed RTL or GUI evidence.\n')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def invoke(self, *, raw=None, meta=None, reference=None, optimized=False):
        target = self.folder / 'SYNTHETIC_VALIDATION_ONLY_capture.rgb565'
        target.write_bytes(self.raw if raw is None else raw)
        target.with_suffix('.json').write_text(json.dumps(self.meta if meta is None else meta))
        cmd = [sys.executable] + (['-O'] if optimized else []) + [str(VALIDATOR), str(target)]
        if reference is not None:
            cmd += ['--reference', str(reference)]
        env = os.environ.copy()
        env.pop('PYTHONOPTIMIZE', None)
        return subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=30)

    def rejected(self, result, message):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)
        self.assertEqual(result.stdout, '', 'failed validation emitted a success report')

    def test_valid_synthetic_fixture_and_full_reference(self):
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                r = self.invoke(reference=self.ref, optimized=optimized)
                self.assertEqual(r.returncode, 0, r.stderr)
                report = json.loads(r.stdout)
                self.assertEqual(report['nearest_2x'], 'PASS')
                self.assertEqual(report['reference_match'], 'PASS')
                self.assertEqual(report['scanout_sha256'], hashlib.sha256(self.raw).hexdigest())
                self.assertEqual(report['logical_rgb565_sha256'], hashlib.sha256(self.ref.read_bytes()).hexdigest())
                self.assertIn('separate', report['scope'])

    def test_optional_reference_does_not_claim_exact_match(self):
        r = self.invoke()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn('reference_match', json.loads(r.stdout))

    def test_metadata_errors_even_under_optimization(self):
        for key in ('underflow_rows_delta', 'dma_errors_delta', 'bounds_errors_delta'):
            for optimized in (False, True):
                with self.subTest(key=key, optimized=optimized):
                    self.rejected(self.invoke(meta={**self.meta, key: 1}, optimized=optimized), key)

    def test_bad_dimensions_source_format(self):
        for key, value, error in [('width', 640, 'dimensions'), ('source', 'synthetic', 'source'),
                                  ('format', 'RGB888', 'format')]:
            with self.subTest(key=key):
                self.rejected(self.invoke(meta={**self.meta, key: value}), error)

    def test_bad_byte_count(self):
        self.rejected(self.invoke(raw=self.raw[:-2]), 'byte count')

    def test_tampered_pixel_without_new_hash(self):
        raw = bytearray(self.raw)
        raw[23456] ^= 1
        self.rejected(self.invoke(raw=raw), 'do not match captured metadata')

    def test_tampered_hash(self):
        self.rejected(self.invoke(meta={**self.meta, 'fnv1a_pixel16': '00000000'}), 'do not match captured metadata')

    def test_non_2x_horizontal_with_correct_hash(self):
        words = list(self.physical)
        words[1] ^= 1
        words[1281] ^= 1  # preserve vertical pairs, break only horizontal pair
        self.rejected(self.invoke(raw=encode(words), meta={**self.meta, 'fnv1a_pixel16': pixel_fnv(words)}), 'horizontal 2x')

    def test_non_2x_vertical_with_correct_hash(self):
        words = list(self.physical)
        words[1280] ^= 1
        words[1281] ^= 1  # preserve horizontal pair, break vertical pair
        self.rejected(self.invoke(raw=encode(words), meta={**self.meta, 'fnv1a_pixel16': pixel_fnv(words)}), 'vertical 2x')

    def test_wrong_full_reference_even_under_optimization(self):
        wrong = self.folder / 'SYNTHETIC_WRONG_reference.rgb565'
        data = bytearray(self.ref.read_bytes())
        data[-1] ^= 1  # last byte: full reference, not only prefix, must be checked
        wrong.write_bytes(data)
        for optimized in (False, True):
            self.rejected(self.invoke(reference=wrong, optimized=optimized), 'differs from the complete reference')
        wrong.write_bytes(b'')
        self.rejected(self.invoke(reference=wrong), 'reference byte count')

if __name__ == '__main__':
    print('SYNTHETIC VALIDATOR UNIT TESTS ONLY — NOT Linux/RTL/GUI success evidence', flush=True)
    unittest.main(verbosity=2)
