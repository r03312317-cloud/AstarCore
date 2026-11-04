"""Inspect the already-stopped, user-approved 60-second run without a new capture.

The board lease is held while existing DDR contents are read.  Software
reference calculation happens only after the UART and board lease are released.
"""
import datetime
import hashlib
import json
import msvcrt
import struct
import sys
import time
import traceback
from pathlib import Path

import board_common as b
from capture_stats_13 import decode as decode_stats

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
RUN = HERE / 'board_live60_13_01'
OUT = RUN / 'poststop_readback_02'
BUILD = 'bd0690f04d0413f8'
b.BUILD = BUILD
b.CANDIDATE = PROJECT
b.FW = PROJECT / 'fw_build_01'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    run = json.loads((RUN / 'result.json').read_text(encoding='utf8'))
    c = run['continuous']
    b.require(run['phase'] == 'complete' and c['STOP_confirmed'] and
              c['completed_frames'] == 49 and c['camera_error_free'] and
              c['capture_stats']['attempted'] == 49 and
              c['capture_stats']['capture_rejected'] == 0,
              'The saved test does not prove an idle, complete final capture')
    model = b.verify_models()['palm']
    manifest = model['manifest']
    old_last = c['outputs'][-1]['workflow']
    b.require(not OUT.exists(), 'Refusing to overwrite previous evidence')
    OUT.mkdir()
    report = {'started_utc': b.utc(), 'phase': 'preflight',
              'scope': 'read the stopped run last frame and output buffers; no new program, capture, or writes to DDR',
              'run_result': str(RUN / 'result.json'), 'firmware_build_id': BUILD,
              'expected_completed': 49, 'regions': [], 'frame_correspondence': False}

    def save():
        tmp = OUT / 'result.tmp'
        tmp.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf8')
        tmp.replace(OUT / 'result.json')

    def progress(stage, **kwargs):
        print(json.dumps({'stage': stage, **kwargs}, ensure_ascii=False), flush=True)

    def read_region(mon, name, addr, length):
        b.require(length >= 0, 'Negative read size')
        path = OUT / (name + '.bin')
        digest = hashlib.sha256()
        start = time.monotonic()
        complete = 0
        with path.open('xb') as out:
            while complete < length:
                n = min(65536, length - complete)
                part = mon.read_memory(addr + complete, n)
                b.require(len(part) == n, 'Short DDR read')
                out.write(part)
                out.flush()
                digest.update(part)
                complete += n
                if complete % 262144 == 0 or complete == length:
                    progress('readback', region=name, bytes=complete, total=length)
        item = {'name': name, 'address': hex(addr), 'bytes': length,
                'sha256': digest.hexdigest(),
                'host_seconds': time.monotonic() - start, 'file': str(path)}
        report['regions'].append(item)
        save()
        return path

    def snapshot(mon, name):
        _, raw = mon.request(26, 0xffffffff)
        (OUT / (name + '_snapshot.bin')).write_bytes(raw)
        result = b.continuous_snapshot(raw)
        _, raw = mon.request(26, 0xfffffffe)
        (OUT / (name + '_capture_stats.bin')).write_bytes(raw)
        stats = decode_stats(raw)
        r = result['last_run']
        b.require(not result['active'] and result['completed'] == 49 and
                  result['last_status'] == 0 and r and r['pass_result'] and
                  stats['attempted'] == stats['completed'] == 49 and
                  not stats['active'] and not stats['capture_rejected'] and
                  not stats['fatal'], 'Camera state changed after the approved test')
        for key in ('frame_id', 'run_id', 'framebuffer', 'source', 'NMS_count',
                    'score_q15', 'class_id', 'bbox_compact_xyxy'):
            b.require(r[key] == old_last[key], 'Last-frame state changed: ' + key)
        return {'continuous': result, 'capture_stats': stats}

    save()
    lock = None
    locked = False
    claimed = False
    try:
        report['phase'] = 'board_readback'
        save()
        lock = b.LOCK.open('r+b')
        lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        locked = True
        b.require(not b.port_in_use(), 'JTAG server is in use by another session')
        devices = b.enumerate_devices(None)
        report['devices'] = devices
        previous = b.STATUS.read_text(encoding='utf8')
        (OUT / 'previous_board_status.md').write_text(previous, encoding='utf8')
        b.STATUS.write_text('# Board resource lease\n\nUTC ' + b.utc() +
                            '; read-only inspection of stopped 13 camera run; evidence ' +
                            str(OUT) + '.\n\n' + previous, encoding='utf8')
        claimed = True
        save()
        with b.Monitor.open(devices['uart']['port'], OUT / 'serial', timeout=20) as mon:
            identity = mon.ping(BUILD)
            b.check_identity(identity)
            report['identity_before'] = identity
            report['state_before'] = before = snapshot(mon, 'before')
            save()
            row = before['continuous']['last_run']
            progress('identity_and_final_frame_matched', frame=row['frame_id'], run=row['run_id'])
            read_region(mon, 'captured_rgb565le', 0x81000000, 1280 * 720 * 2)
            read_region(mon, 'input', 0x80100000, 320 * 320 * 3)
            for head in manifest['model_outputs']:
                read_region(mon, head['name'], head['address'], head['bytes'])
            read_region(mon, 'framebuffer', int(row['framebuffer'], 16), 680 * 340 * 2)
            read_region(mon, 'NMS', manifest['detection']['result_address'], row['NMS_count'] * 24)
            runs = manifest['runs']
            address = runs[0]['trace_base']
            n = 0
            for r in runs:
                b.require(r['trace_base'] == address + 24 * n, 'Trace blocks not contiguous')
                n += r['count']
            b.require(n == 204, 'Trace count differs')
            read_region(mon, 'graph_trace', address, n * 24)
            report['state_after'] = snapshot(mon, 'after')
            identity_after = mon.ping(BUILD)
            b.check_identity(identity_after)
            report['identity_after'] = identity_after
            report['frame_correspondence'] = True
            save()
    except BaseException as exc:
        report['phase_at_error'] = report['phase']
        report['phase'] = 'failed'
        report['error'] = {'type': type(exc).__name__, 'message': str(exc),
                           'traceback': traceback.format_exc()}
        save()
        raise
    finally:
        if claimed:
            prior = b.STATUS.read_text(encoding='utf8')
            b.STATUS.write_text('# Board resource released / FPS_V2 已释放\n\nUTC ' + b.utc() +
                                '; stopped-run readback released; evidence ' + str(OUT) +
                                '.\n\n' + prior, encoding='utf8')
        if locked:
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        if lock:
            lock.close()

    try:
        report['phase'] = 'offline_integer_reference'
        save()
        progress('offline_integer_reference')
        reference_root = b.ROOT / 'work/fpsv2_pipeline_20261030_08'
        old_profile = json.loads((reference_root / 'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']
        new_profile = json.loads((PROJECT / 'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']
        b.require(old_profile == new_profile, 'Independent reference video profile differs')
        sys.path.insert(0, str(reference_root / 'board_tools'))
        from live_reference_02 import LiveReference02
        frame = (OUT / 'captured_rgb565le.bin').read_bytes()
        reference = LiveReference02()
        started = time.monotonic()
        golden = reference.calculate(frame, mode='packed_integer')
        b.require(golden['reference_mode'] == 'packed_integer' and
                  golden['frame_sha256'] == sha(frame), 'Reference frame identity mismatch')
        meta = b.save_live_golden(golden, OUT / 'integer_reference')
        comparison = []
        expected = {'input': golden['input'], 'framebuffer': golden['display'], **golden['heads']}
        for name, data in expected.items():
            actual = (OUT / (name + '.bin')).read_bytes()
            comparison.append({'name': name, 'bytes': len(actual),
                               'actual_sha256': sha(actual), 'expected_sha256': sha(data),
                               'exact': actual == data,
                               'differing_bytes': sum(a != e for a, e in zip(actual, data))
                               if len(actual) == len(data) else None})
        fields = ('x1_q16', 'y1_q16', 'x2_q16', 'y2_q16', 'score_q15', 'class_id')
        expected_nms = b''.join(struct.pack('<6I', *(d[k] for k in fields))
                                for d in golden['detections'])
        actual_nms = (OUT / 'NMS.bin').read_bytes()
        eligible = [d for d in golden['detections'] if d['class_id'] < 6 and
                    d['x1_q16'] < d['x2_q16'] and d['y1_q16'] < d['y2_q16'] and
                    d['display_680x340_xyxy'][0] < d['display_680x340_xyxy'][2] and
                    d['display_680x340_xyxy'][1] < d['display_680x340_xyxy'][3]]
        selected = max(eligible, key=lambda d: d['score_q15']) if eligible else None
        row = report['state_before']['continuous']['last_run']
        meta_exact = row['NMS_count'] == golden['NMS_count'] and row['palm_count'] == int(selected is not None)
        if selected:
            meta_exact = (meta_exact and row['class_id'] == selected['class_id'] and
                          row['score_q15'] == selected['score_q15'] and
                          row['bbox_compact_xyxy'] == selected['display_680x340_xyxy'])
        else:
            meta_exact = meta_exact and row['bbox_compact_xyxy'] == [0, 0, 0, 0]
        report['reference'] = {'frame_sha256': sha(frame), 'metadata': meta,
                               'calculation_host_seconds': time.monotonic() - started,
                               'selected_all_six': selected}
        report['comparison'] = {'regions': comparison, 'nms_actual_sha256': sha(actual_nms),
                                'nms_expected_sha256': sha(expected_nms),
                                'nms_exact': actual_nms == expected_nms,
                                'selection_metadata_exact': meta_exact}
        report['comparison']['all_exact'] = (all(x['exact'] for x in comparison) and
                                              actual_nms == expected_nms and meta_exact)
        trace = (OUT / 'graph_trace.bin').read_bytes()
        rows = [dict(zip(('index', 'opcode', 'status', 'ticks', 'crc32', 'output'), x))
                for x in struct.iter_unpack('<6I', trace)]
        report['graph_trace'] = {'records': len(rows), 'status_nonzero': sum(x['status'] != 0 for x in rows),
                                 'ticks_sum': sum(x['ticks'] for x in rows),
                                 'units': 'raw firmware trace ticks; interpretation requires source verification'}
        (OUT / 'graph_trace.json').write_text(json.dumps(rows, indent=2) + '\n', encoding='utf8')
        report['phase'] = 'complete'
        report['finished_utc'] = b.utc()
        save()
        progress('complete', all_exact=report['comparison']['all_exact'],
                 nms_exact=report['comparison']['nms_exact'],
                 selection_metadata_exact=meta_exact,
                 regions=[{'name': x['name'], 'exact': x['exact'],
                           'differing_bytes': x['differing_bytes']} for x in comparison])
        return 0
    except BaseException as exc:
        report['phase_at_error'] = report['phase']
        report['phase'] = 'failed'
        report['error'] = {'type': type(exc).__name__, 'message': str(exc),
                           'traceback': traceback.format_exc()}
        save()
        raise


if __name__ == '__main__':
    sys.exit(main())
