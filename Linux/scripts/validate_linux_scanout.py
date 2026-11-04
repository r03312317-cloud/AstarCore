#!/usr/bin/env python3
"""Check an actual captured RTL raster; never renders or modifies its pixels."""
import argparse
import array
import hashlib
import json
import pathlib
import sys

def require(condition, message):
    # Validation must remain active under python -O / PYTHONOPTIMIZE.
    if not condition:
        raise ValueError(message)


p = argparse.ArgumentParser()
p.add_argument('capture', type=pathlib.Path, help='1280x720 little-endian RGB565')
p.add_argument('--reference', type=pathlib.Path, help='optional exact 640x360 RGB565 reference')
a = p.parse_args()
raw = a.capture.read_bytes()
meta = json.loads(a.capture.with_suffix('.json').read_text())
require(meta['source'] == 'actual RTL digital scanout', 'invalid capture source label')
require((meta['width'], meta['height']) == (1280, 720), 'invalid raster dimensions')
require(meta['format'] == 'RGB565 little-endian', 'invalid pixel format')
for error in ('underflow_rows_delta', 'dma_errors_delta', 'bounds_errors_delta'):
    require(meta[error] == 0, f'captured raster has {error}')
require(len(raw) == 1280 * 720 * 2, 'invalid raster byte count')
pixels = array.array('H')
pixels.frombytes(raw)
if sys.byteorder != 'little':
    pixels.byteswap()
fnv = 0x811c9dc5
for pixel in pixels:
    fnv = ((fnv ^ pixel) * 0x01000193) & 0xffffffff
require(fnv == int(meta['fnv1a_pixel16'], 16), 'raw pixels do not match captured metadata')
small = array.array('H')
for y in range(0, 720, 2):
    row = pixels[y * 1280:(y + 1) * 1280]
    require(row == pixels[(y + 1) * 1280:(y + 2) * 1280], f'vertical 2x mismatch at {y}')
    require(row[::2] == row[1::2], f'horizontal 2x mismatch at {y}')
    small.extend(row[::2])
if sys.byteorder != 'little':
    small.byteswap()
data = small.tobytes()
result = {'capture': str(a.capture), 'frame': meta, 'nearest_2x': 'PASS',
          'scanout_sha256': hashlib.sha256(raw).hexdigest(),
          'logical_rgb565_sha256': hashlib.sha256(data).hexdigest(),
          'scope': 'pixel comparison only; Linux process/driver/command evidence is separate'}
if a.reference:
    expected = a.reference.read_bytes()
    require(len(expected) == 640 * 360 * 2, 'invalid reference byte count')
    require(data == expected, 'actual scanout differs from the complete reference image')
    result['exact_reference'] = str(a.reference)
    result['reference_match'] = 'PASS'
print(json.dumps(result, indent=2))
