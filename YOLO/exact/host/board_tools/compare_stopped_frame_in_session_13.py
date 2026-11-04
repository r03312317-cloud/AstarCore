"""Read the last completed frame BEFORE closing the active board session.

Caller must own the board lease and have confirmed STOP.  This module never
programs the FPGA, starts a capture, or writes DDR.  Importing touches no board.
"""
import hashlib
import json
import struct
import sys
import time
from pathlib import Path

import board_common as b
from capture_stats_13 import decode as decode_stats


def sha(data):
    return hashlib.sha256(data).hexdigest()


def compare(mon, model, continuous, output):
    output = Path(output)
    b.require(not output.exists(), 'Use a fresh same-frame evidence folder')
    b.require(continuous.get('STOP_confirmed') and continuous.get('observation_complete') and
              continuous.get('outputs') and continuous.get('completed_frames', 0) > 0,
              'A complete, stopped camera observation is required')
    diag = continuous['capture_stats']
    n = continuous['completed_frames']
    # The source buffer is overwritten during every attempt.  With any rejected
    # attempt, counters alone cannot prove its contents are the last good frame.
    b.require(diag['attempted'] == diag['completed'] == n and
              not diag['active'] and not diag['capture_rejected'] and not diag['fatal'],
              'Cannot prove last-frame association after a rejected/failed capture')
    last = continuous['outputs'][-1]['workflow']
    output.mkdir(parents=True)
    report = {'phase': 'readback', 'frame_correspondence': False,
              'scope': 'Same active session, STOP already confirmed; read-only DDR and status queries.',
              'completed_frames': n, 'regions': []}

    def save():
        temp = output / 'result.tmp'
        temp.write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n', encoding='utf8')
        temp.replace(output / 'result.json')

    def check_snapshot(label):
        _, raw = mon.request(26, 0xffffffff)
        (output / (label+'_snapshot.bin')).write_bytes(raw)
        snap = b.continuous_snapshot(raw)
        _, raw = mon.request(26, 0xfffffffe)
        (output / (label+'_capture_stats.bin')).write_bytes(raw)
        stats = decode_stats(raw)
        row = snap['last_run']
        b.require(not snap['active'] and snap['completed'] == n and not snap['last_status'] and
                  row and row['pass_result'] and row['source'] == 'real CMOS2 capture' and
                  not stats['active'] and stats['attempted'] == stats['completed'] == n and
                  not stats['capture_rejected'] and not stats['fatal'], 'Camera state changed')
        for key in ('frame_id','run_id','framebuffer','source','NMS_count',
                    'score_q15','class_id','bbox_compact_xyxy'):
            b.require(row[key] == last[key], 'Last result changed: '+key)
        return {'continuous': snap, 'capture_stats': stats}

    def read_region(name, address, length):
        file = output / (name+'.bin')
        digest = hashlib.sha256()
        done = 0
        started = time.monotonic()
        with file.open('xb') as f:
            while done < length:
                count = min(65536, length-done)
                data = mon.read_memory(address+done, count)
                b.require(len(data) == count, 'Short readback: '+name)
                f.write(data)
                f.flush()
                digest.update(data)
                done += count
                if done % 262144 == 0 or done == length:
                    print(json.dumps({'stage':'same_frame_readback','region':name,
                                      'bytes':done,'total':length}), flush=True)
        report['regions'].append({'name':name,'address':hex(address),'bytes':length,
                                  'sha256':digest.hexdigest(),
                                  'host_seconds':time.monotonic()-started,'file':str(file)})
        save()

    save()
    try:
        identity = mon.ping(b.BUILD)
        b.check_identity(identity)
        report['identity_before'] = identity
        report['state_before'] = state = check_snapshot('before')
        row = state['continuous']['last_run']
        manifest = model['manifest']
        read_region('captured_rgb565le', 0x81000000, 1280*720*2)
        read_region('input', 0x80100000, 320*320*3)
        for head in manifest['model_outputs']:
            read_region(head['name'], head['address'], head['bytes'])
        read_region('framebuffer', int(row['framebuffer'], 16), 680*340*2)
        read_region('NMS', manifest['detection']['result_address'], row['NMS_count']*24)
        report['state_after'] = check_snapshot('after')
        identity = mon.ping(b.BUILD)
        b.check_identity(identity)
        report['identity_after'] = identity
        report['frame_correspondence'] = True
        report['phase'] = 'software_reference'
        save()
        old_root = b.ROOT / 'work/fpsv2_pipeline_20261030_08'
        old_profile = json.loads((old_root/'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']
        new_profile = json.loads((b.CANDIDATE/'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']
        b.require(old_profile == new_profile, 'Reference carrier differs from actual board')
        sys.path.insert(0, str(old_root/'board_tools'))
        from live_reference_02 import LiveReference02
        frame = (output/'captured_rgb565le.bin').read_bytes()
        reference = LiveReference02().calculate(frame, mode='packed_integer')
        b.require(reference['frame_sha256'] == sha(frame) and reference['reference_mode']=='packed_integer',
                  'Reference frame identity differs')
        meta = b.save_live_golden(reference, output/'integer_reference')
        pairs = {'input':reference['input'], 'framebuffer':reference['display'], **reference['heads']}
        checks = []
        for name, expected in pairs.items():
            actual = (output/(name+'.bin')).read_bytes()
            checks.append({'name':name,'bytes':len(actual),'exact':actual==expected,
                           'actual_sha256':sha(actual),'expected_sha256':sha(expected),
                           'differing_bytes':sum(a!=b for a,b in zip(actual,expected))
                               if len(actual)==len(expected) else None})
        fields = ('x1_q16','y1_q16','x2_q16','y2_q16','score_q15','class_id')
        expected = b''.join(struct.pack('<6I',*(x[k] for k in fields))
                            for x in reference['detections'])
        actual = (output/'NMS.bin').read_bytes()
        valid = [d for d in reference['detections'] if d['class_id']<6 and
                 d['x1_q16']<d['x2_q16'] and d['y1_q16']<d['y2_q16'] and
                 d['display_680x340_xyxy'][0]<d['display_680x340_xyxy'][2] and
                 d['display_680x340_xyxy'][1]<d['display_680x340_xyxy'][3]]
        selected = max(valid,key=lambda d:d['score_q15']) if valid else None
        selection_exact = row['NMS_count']==reference['NMS_count'] and row['palm_count']==int(bool(selected))
        if selected:
            selection_exact = (selection_exact and row['class_id']==selected['class_id'] and
                               row['score_q15']==selected['score_q15'] and
                               row['bbox_compact_xyxy']==selected['display_680x340_xyxy'])
        else:
            selection_exact = selection_exact and row['bbox_compact_xyxy']==[0,0,0,0]
        report['reference'] = {'frame_sha256':sha(frame),'metadata':meta,'selected_all_six':selected}
        report['comparison'] = {'regions':checks,'nms_exact':actual==expected,
                                'nms_actual_sha256':sha(actual),'nms_expected_sha256':sha(expected),
                                'selection_metadata_exact':selection_exact}
        report['comparison']['all_exact'] = (all(x['exact'] for x in checks) and actual==expected and selection_exact)
        report['phase'] = 'complete'
        save()
        return report
    except BaseException as exc:
        report['phase_at_error'] = report['phase']
        report['phase'] = 'failed'
        report['error'] = {'type':type(exc).__name__,'message':str(exc)}
        save()
        raise
