# 架构导读：inspect_last_frame_13_02。
# 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
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

# 维护本地状态/计算值：HERE = Path(__file__).resolve().parent。
HERE = Path(__file__).resolve().parent
# 维护本地状态/计算值：PROJECT = HERE.parent。
PROJECT = HERE.parent
# 维护本地状态/计算值：RUN = HERE / 'board_live60_13_01'。
RUN = HERE / 'board_live60_13_01'
# 维护本地状态/计算值：OUT = RUN / 'poststop_readback_02'。
OUT = RUN / 'poststop_readback_02'
# 维护本地状态/计算值：BUILD = 'bd0690f04d0413f8'。
BUILD = 'bd0690f04d0413f8'
# 维护本地状态/计算值：b.BUILD = BUILD。
b.BUILD = BUILD
# 维护本地状态/计算值：b.CANDIDATE = PROJECT。
b.CANDIDATE = PROJECT
# 维护本地状态/计算值：b.FW = PROJECT / 'fw_build_01'。
b.FW = PROJECT / 'fw_build_01'


# 接口 sha，显式输入字段：data。
# 本函数调用入口包括 hashlib.sha256(data).hexdigest, hashlib.sha256。
def sha(data):
    # 向调用方返回本步骤结果：hashlib.sha256(data).hexdigest()。
    return hashlib.sha256(data).hexdigest()


# 接口 main，显式输入字段：无位置参数。
# 本函数调用入口包括 json.loads, b.require, OUT.mkdir, save, (RUN / 'result.json').read_text。
def main():
    # 维护本地状态/计算值：run = json.loads((RUN / 'result.json').read_text(encoding='utf8'))。
    run = json.loads((RUN / 'result.json').read_text(encoding='utf8'))
    # 维护本地状态/计算值：c = run['continuous']。
    c = run['continuous']
    b.require(run['phase'] == 'complete' and c['STOP_confirmed'] and
              c['completed_frames'] == 49 and c['camera_error_free'] and
              c['capture_stats']['attempted'] == 49 and
              c['capture_stats']['capture_rejected'] == 0,
              'The saved test does not prove an idle, complete final capture')
    # 维护本地状态/计算值：model = b.verify_models()['palm']。
    model = b.verify_models()['palm']
    # 维护本地状态/计算值：manifest = model['manifest']。
    manifest = model['manifest']
    # 维护本地状态/计算值：old_last = c['outputs'][-1]['workflow']。
    old_last = c['outputs'][-1]['workflow']
    b.require(not OUT.exists(), 'Refusing to overwrite previous evidence')
    OUT.mkdir()
    # 维护本地状态/计算值：report = {'started_utc': b.utc(), 'phase': 'preflight',。
    report = {'started_utc': b.utc(), 'phase': 'preflight',
              'scope': 'read the stopped run last frame and output buffers; no new program, capture, or writes to DDR',
              'run_result': str(RUN / 'result.json'), 'firmware_build_id': BUILD,
              'expected_completed': 49, 'regions': [], 'frame_correspondence': False}

    # 接口 save，显式输入字段：无位置参数。
    # 本函数调用入口包括 tmp.write_text, tmp.replace, json.dumps。
    def save():
        # 维护本地状态/计算值：tmp = OUT / 'result.tmp'。
        tmp = OUT / 'result.tmp'
        tmp.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf8')
        tmp.replace(OUT / 'result.json')

    # 接口 progress，显式输入字段：stage。
    # 本函数调用入口包括 print, json.dumps。
    def progress(stage, **kwargs):
        print(json.dumps({'stage': stage, **kwargs}, ensure_ascii=False), flush=True)

    # 接口 read_region，显式输入字段：mon, name, addr, length。
    # 本函数调用入口包括 b.require, hashlib.sha256, time.monotonic, report['regions'].append, save。
    def read_region(mon, name, addr, length):
        b.require(length >= 0, 'Negative read size')
        # 维护本地状态/计算值：path = OUT / (name + '.bin')。
        path = OUT / (name + '.bin')
        # 维护本地状态/计算值：digest = hashlib.sha256()。
        digest = hashlib.sha256()
        # 维护本地状态/计算值：start = time.monotonic()。
        start = time.monotonic()
        # 维护本地状态/计算值：complete = 0。
        complete = 0
        # 资源上下文：with path.open('xb') as out:；离开上下文时执行对应清理约定。
        with path.open('xb') as out:
            # 迭代/等待条件：complete < length；退出由原循环条件及显式 break/异常决定。
            while complete < length:
                # 维护本地状态/计算值：n = min(65536, length - complete)。
                n = min(65536, length - complete)
                # 维护本地状态/计算值：part = mon.read_memory(addr + complete, n)。
                part = mon.read_memory(addr + complete, n)
                b.require(len(part) == n, 'Short DDR read')
                out.write(part)
                out.flush()
                digest.update(part)
                # 维护本地状态/计算值：complete += n。
                complete += n
                # 按条件 complete % 262144 == 0 or complete == length 选择后续流程，保留原有异常和退出分支。
                if complete % 262144 == 0 or complete == length:
                    progress('readback', region=name, bytes=complete, total=length)
        # 维护本地状态/计算值：item = {'name': name, 'address': hex(addr), 'bytes': length,。
        item = {'name': name, 'address': hex(addr), 'bytes': length,
                'sha256': digest.hexdigest(),
                'host_seconds': time.monotonic() - start, 'file': str(path)}
        report['regions'].append(item)
        save()
        # 向调用方返回本步骤结果：path。
        return path

    # 接口 snapshot，显式输入字段：mon, name。
    # 本函数调用入口包括 mon.request, (OUT / (name + '_snapshot.bin')).write_bytes, b.continuous_snapshot, (OUT / (name + '_capture_stats.bin')).wr...。
    def snapshot(mon, name):
        # 维护本地状态/计算值：_, raw = mon.request(26, 0xffffffff)。
        _, raw = mon.request(26, 0xffffffff)
        (OUT / (name + '_snapshot.bin')).write_bytes(raw)
        # 维护本地状态/计算值：result = b.continuous_snapshot(raw)。
        result = b.continuous_snapshot(raw)
        # 维护本地状态/计算值：_, raw = mon.request(26, 0xfffffffe)。
        _, raw = mon.request(26, 0xfffffffe)
        (OUT / (name + '_capture_stats.bin')).write_bytes(raw)
        # 维护本地状态/计算值：stats = decode_stats(raw)。
        stats = decode_stats(raw)
        # 维护本地状态/计算值：r = result['last_run']。
        r = result['last_run']
        b.require(not result['active'] and result['completed'] == 49 and
                  result['last_status'] == 0 and r and r['pass_result'] and
                  stats['attempted'] == stats['completed'] == 49 and
                  not stats['active'] and not stats['capture_rejected'] and
                  not stats['fatal'], 'Camera state changed after the approved test')
        # 迭代/等待条件：('frame_id', 'run_id', 'framebuffer', 'source', 'NMS_count', 'score_q15', 'class_id', 'bbox_compact_xyxy')；退出由原循环条件及显式 break/异常决定。
        for key in ('frame_id', 'run_id', 'framebuffer', 'source', 'NMS_count',
                    'score_q15', 'class_id', 'bbox_compact_xyxy'):
            b.require(r[key] == old_last[key], 'Last-frame state changed: ' + key)
        # 向调用方返回本步骤结果：{'continuous': result, 'capture_stats': stats}。
        return {'continuous': result, 'capture_stats': stats}

    save()
    # 维护本地状态/计算值：lock = None。
    lock = None
    # 维护本地状态/计算值：locked = False。
    locked = False
    # 维护本地状态/计算值：claimed = False。
    claimed = False
    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        # 维护本地状态/计算值：report['phase'] = 'board_readback'。
        report['phase'] = 'board_readback'
        save()
        # 维护本地状态/计算值：lock = b.LOCK.open('r+b')。
        lock = b.LOCK.open('r+b')
        lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        # 维护本地状态/计算值：locked = True。
        locked = True
        b.require(not b.port_in_use(), 'JTAG server is in use by another session')
        # 维护本地状态/计算值：devices = b.enumerate_devices(None)。
        devices = b.enumerate_devices(None)
        # 维护本地状态/计算值：report['devices'] = devices。
        report['devices'] = devices
        # 维护本地状态/计算值：previous = b.STATUS.read_text(encoding='utf8')。
        previous = b.STATUS.read_text(encoding='utf8')
        (OUT / 'previous_board_status.md').write_text(previous, encoding='utf8')
        b.STATUS.write_text('# Board resource lease\n\nUTC ' + b.utc() +
                            '; read-only inspection of stopped 13 camera run; evidence ' +
                            str(OUT) + '.\n\n' + previous, encoding='utf8')
        # 维护本地状态/计算值：claimed = True。
        claimed = True
        save()
        # 资源上下文：with b.Monitor.open(devices['uart']['port'], OUT / 'serial', timeout=20) as mon:；离开上下文时执行对应清理约定。
        with b.Monitor.open(devices['uart']['port'], OUT / 'serial', timeout=20) as mon:
            # 维护本地状态/计算值：identity = mon.ping(BUILD)。
            identity = mon.ping(BUILD)
            b.check_identity(identity)
            # 维护本地状态/计算值：report['identity_before'] = identity。
            report['identity_before'] = identity
            # 维护本地状态/计算值：report['state_before'] = before = snapshot(mon, 'before')。
            report['state_before'] = before = snapshot(mon, 'before')
            save()
            # 维护本地状态/计算值：row = before['continuous']['last_run']。
            row = before['continuous']['last_run']
            progress('identity_and_final_frame_matched', frame=row['frame_id'], run=row['run_id'])
            read_region(mon, 'captured_rgb565le', 0x81000000, 1280 * 720 * 2)
            read_region(mon, 'input', 0x80100000, 320 * 320 * 3)
            # 迭代/等待条件：manifest['model_outputs']；退出由原循环条件及显式 break/异常决定。
            for head in manifest['model_outputs']:
                read_region(mon, head['name'], head['address'], head['bytes'])
            read_region(mon, 'framebuffer', int(row['framebuffer'], 16), 680 * 340 * 2)
            read_region(mon, 'NMS', manifest['detection']['result_address'], row['NMS_count'] * 24)
            # 维护本地状态/计算值：runs = manifest['runs']。
            runs = manifest['runs']
            # 维护本地状态/计算值：address = runs[0]['trace_base']。
            address = runs[0]['trace_base']
            # 维护本地状态/计算值：n = 0。
            n = 0
            # 迭代/等待条件：runs；退出由原循环条件及显式 break/异常决定。
            for r in runs:
                b.require(r['trace_base'] == address + 24 * n, 'Trace blocks not contiguous')
                # 维护本地状态/计算值：n += r['count']。
                n += r['count']
            b.require(n == 204, 'Trace count differs')
            read_region(mon, 'graph_trace', address, n * 24)
            # 维护本地状态/计算值：report['state_after'] = snapshot(mon, 'after')。
            report['state_after'] = snapshot(mon, 'after')
            # 维护本地状态/计算值：identity_after = mon.ping(BUILD)。
            identity_after = mon.ping(BUILD)
            b.check_identity(identity_after)
            # 维护本地状态/计算值：report['identity_after'] = identity_after。
            report['identity_after'] = identity_after
            # 维护本地状态/计算值：report['frame_correspondence'] = True。
            report['frame_correspondence'] = True
            save()
    except BaseException as exc:
        # 维护本地状态/计算值：report['phase_at_error'] = report['phase']。
        report['phase_at_error'] = report['phase']
        # 维护本地状态/计算值：report['phase'] = 'failed'。
        report['phase'] = 'failed'
        # 维护本地状态/计算值：report['error'] = {'type': type(exc).__name__, 'message': str(exc),。
        report['error'] = {'type': type(exc).__name__, 'message': str(exc),
                           'traceback': traceback.format_exc()}
        save()
        # 停止当前调用并上报异常：raise。
        raise
    finally:
        # 按条件 claimed 选择后续流程，保留原有异常和退出分支。
        if claimed:
            # 维护本地状态/计算值：prior = b.STATUS.read_text(encoding='utf8')。
            prior = b.STATUS.read_text(encoding='utf8')
            b.STATUS.write_text('# Board resource released / FPS_V2 已释放\n\nUTC ' + b.utc() +
                                '; stopped-run readback released; evidence ' + str(OUT) +
                                '.\n\n' + prior, encoding='utf8')
        # 按条件 locked 选择后续流程，保留原有异常和退出分支。
        if locked:
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        # 按条件 lock 选择后续流程，保留原有异常和退出分支。
        if lock:
            lock.close()

    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        # 维护本地状态/计算值：report['phase'] = 'offline_integer_reference'。
        report['phase'] = 'offline_integer_reference'
        save()
        progress('offline_integer_reference')
        # 维护本地状态/计算值：reference_root = b.ROOT / 'work/fpsv2_pipeline_20261030_08'。
        reference_root = b.ROOT / 'work/fpsv2_pipeline_20261030_08'
        # 维护本地状态/计算值：old_profile = json.loads((reference_root / 'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']。
        old_profile = json.loads((reference_root / 'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']
        # 维护本地状态/计算值：new_profile = json.loads((PROJECT / 'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']。
        new_profile = json.loads((PROJECT / 'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']
        b.require(old_profile == new_profile, 'Independent reference video profile differs')
        sys.path.insert(0, str(reference_root / 'board_tools'))
        from live_reference_02 import LiveReference02
        # 维护本地状态/计算值：frame = (OUT / 'captured_rgb565le.bin').read_bytes()。
        frame = (OUT / 'captured_rgb565le.bin').read_bytes()
        # 维护本地状态/计算值：reference = LiveReference02()。
        reference = LiveReference02()
        # 维护本地状态/计算值：started = time.monotonic()。
        started = time.monotonic()
        # 维护本地状态/计算值：golden = reference.calculate(frame, mode='packed_integer')。
        golden = reference.calculate(frame, mode='packed_integer')
        b.require(golden['reference_mode'] == 'packed_integer' and
                  golden['frame_sha256'] == sha(frame), 'Reference frame identity mismatch')
        # 维护本地状态/计算值：meta = b.save_live_golden(golden, OUT / 'integer_reference')。
        meta = b.save_live_golden(golden, OUT / 'integer_reference')
        # 维护本地状态/计算值：comparison = []。
        comparison = []
        expected = {'input': golden['input'], 'framebuffer': golden['display'], **golden['heads']}
        # 迭代/等待条件：expected.items()；退出由原循环条件及显式 break/异常决定。
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
        # 按条件 selected 选择后续流程，保留原有异常和退出分支。
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
        # 向调用方返回本步骤结果：0。
        return 0
    except BaseException as exc:
        report['phase_at_error'] = report['phase']
        report['phase'] = 'failed'
        report['error'] = {'type': type(exc).__name__, 'message': str(exc),
                           'traceback': traceback.format_exc()}
        save()
        # 停止当前调用并上报异常：raise。
        raise


# 按条件 __name__ == '__main__' 选择后续流程，保留原有异常和退出分支。
if __name__ == '__main__':
    sys.exit(main())
