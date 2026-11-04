# 架构导读：compare_stopped_frame_in_session_13。
# 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
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


# 接口 sha，显式输入字段：data。
# 本函数调用入口包括 hashlib.sha256(data).hexdigest, hashlib.sha256。
def sha(data):
    # 向调用方返回本步骤结果：hashlib.sha256(data).hexdigest()。
    return hashlib.sha256(data).hexdigest()


# 接口 compare，显式输入字段：mon, model, continuous, output。
# 本函数调用入口包括 Path, b.require, output.mkdir, save, temp.write_text。
def compare(mon, model, continuous, output):
    # 维护本地状态/计算值：output = Path(output)。
    output = Path(output)
    b.require(not output.exists(), 'Use a fresh same-frame evidence folder')
    b.require(continuous.get('STOP_confirmed') and continuous.get('observation_complete') and
              continuous.get('outputs') and continuous.get('completed_frames', 0) > 0,
              'A complete, stopped camera observation is required')
    # 维护本地状态/计算值：diag = continuous['capture_stats']。
    diag = continuous['capture_stats']
    # 维护本地状态/计算值：n = continuous['completed_frames']。
    n = continuous['completed_frames']
    # The source buffer is overwritten during every attempt.  With any rejected
    # attempt, counters alone cannot prove its contents are the last good frame.
    b.require(diag['attempted'] == diag['completed'] == n and
              not diag['active'] and not diag['capture_rejected'] and not diag['fatal'],
              'Cannot prove last-frame association after a rejected/failed capture')
    # 维护本地状态/计算值：last = continuous['outputs'][-1]['workflow']。
    last = continuous['outputs'][-1]['workflow']
    output.mkdir(parents=True)
    # 维护本地状态/计算值：report = {'phase': 'readback', 'frame_correspondence': False,。
    report = {'phase': 'readback', 'frame_correspondence': False,
              'scope': 'Same active session, STOP already confirmed; read-only DDR and status queries.',
              'completed_frames': n, 'regions': []}

    # 接口 save，显式输入字段：无位置参数。
    # 本函数调用入口包括 temp.write_text, temp.replace, json.dumps。
    def save():
        # 维护本地状态/计算值：temp = output / 'result.tmp'。
        temp = output / 'result.tmp'
        temp.write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n', encoding='utf8')
        temp.replace(output / 'result.json')

    # 接口 check_snapshot，显式输入字段：label。
    # 本函数调用入口包括 mon.request, (output / (label + '_snapshot.bin')).write_bytes, b.continuous_snapshot, (output / (label + '_capture_stats.b...。
    def check_snapshot(label):
        # 维护本地状态/计算值：_, raw = mon.request(26, 0xffffffff)。
        _, raw = mon.request(26, 0xffffffff)
        (output / (label+'_snapshot.bin')).write_bytes(raw)
        # 维护本地状态/计算值：snap = b.continuous_snapshot(raw)。
        snap = b.continuous_snapshot(raw)
        # 维护本地状态/计算值：_, raw = mon.request(26, 0xfffffffe)。
        _, raw = mon.request(26, 0xfffffffe)
        (output / (label+'_capture_stats.bin')).write_bytes(raw)
        # 维护本地状态/计算值：stats = decode_stats(raw)。
        stats = decode_stats(raw)
        # 维护本地状态/计算值：row = snap['last_run']。
        row = snap['last_run']
        b.require(not snap['active'] and snap['completed'] == n and not snap['last_status'] and
                  row and row['pass_result'] and row['source'] == 'real CMOS2 capture' and
                  not stats['active'] and stats['attempted'] == stats['completed'] == n and
                  not stats['capture_rejected'] and not stats['fatal'], 'Camera state changed')
        # 迭代/等待条件：('frame_id', 'run_id', 'framebuffer', 'source', 'NMS_count', 'score_q15', 'class_id', 'bbox_compact_xyxy')；退出由原循环条件及显式 break/异常决定。
        for key in ('frame_id','run_id','framebuffer','source','NMS_count',
                    'score_q15','class_id','bbox_compact_xyxy'):
            b.require(row[key] == last[key], 'Last result changed: '+key)
        # 向调用方返回本步骤结果：{'continuous': snap, 'capture_stats': stats}。
        return {'continuous': snap, 'capture_stats': stats}

    # 接口 read_region，显式输入字段：name, address, length。
    # 本函数调用入口包括 hashlib.sha256, time.monotonic, report['regions'].append, save, file.open。
    def read_region(name, address, length):
        # 维护本地状态/计算值：file = output / (name+'.bin')。
        file = output / (name+'.bin')
        # 维护本地状态/计算值：digest = hashlib.sha256()。
        digest = hashlib.sha256()
        # 维护本地状态/计算值：done = 0。
        done = 0
        # 维护本地状态/计算值：started = time.monotonic()。
        started = time.monotonic()
        # 资源上下文：with file.open('xb') as f:；离开上下文时执行对应清理约定。
        with file.open('xb') as f:
            # 迭代/等待条件：done < length；退出由原循环条件及显式 break/异常决定。
            while done < length:
                # 维护本地状态/计算值：count = min(65536, length-done)。
                count = min(65536, length-done)
                # 维护本地状态/计算值：data = mon.read_memory(address+done, count)。
                data = mon.read_memory(address+done, count)
                b.require(len(data) == count, 'Short readback: '+name)
                f.write(data)
                f.flush()
                digest.update(data)
                # 维护本地状态/计算值：done += count。
                done += count
                # 按条件 done % 262144 == 0 or done == length 选择后续流程，保留原有异常和退出分支。
                if done % 262144 == 0 or done == length:
                    print(json.dumps({'stage':'same_frame_readback','region':name,
                                      'bytes':done,'total':length}), flush=True)
        report['regions'].append({'name':name,'address':hex(address),'bytes':length,
                                  'sha256':digest.hexdigest(),
                                  'host_seconds':time.monotonic()-started,'file':str(file)})
        save()

    save()
    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        # 维护本地状态/计算值：identity = mon.ping(b.BUILD)。
        identity = mon.ping(b.BUILD)
        b.check_identity(identity)
        # 维护本地状态/计算值：report['identity_before'] = identity。
        report['identity_before'] = identity
        # 维护本地状态/计算值：report['state_before'] = state = check_snapshot('before')。
        report['state_before'] = state = check_snapshot('before')
        # 维护本地状态/计算值：row = state['continuous']['last_run']。
        row = state['continuous']['last_run']
        # 维护本地状态/计算值：manifest = model['manifest']。
        manifest = model['manifest']
        read_region('captured_rgb565le', 0x81000000, 1280*720*2)
        read_region('input', 0x80100000, 320*320*3)
        # 迭代/等待条件：manifest['model_outputs']；退出由原循环条件及显式 break/异常决定。
        for head in manifest['model_outputs']:
            read_region(head['name'], head['address'], head['bytes'])
        read_region('framebuffer', int(row['framebuffer'], 16), 680*340*2)
        read_region('NMS', manifest['detection']['result_address'], row['NMS_count']*24)
        # 维护本地状态/计算值：report['state_after'] = check_snapshot('after')。
        report['state_after'] = check_snapshot('after')
        # 维护本地状态/计算值：identity = mon.ping(b.BUILD)。
        identity = mon.ping(b.BUILD)
        b.check_identity(identity)
        # 维护本地状态/计算值：report['identity_after'] = identity。
        report['identity_after'] = identity
        # 维护本地状态/计算值：report['frame_correspondence'] = True。
        report['frame_correspondence'] = True
        # 维护本地状态/计算值：report['phase'] = 'software_reference'。
        report['phase'] = 'software_reference'
        save()
        # 维护本地状态/计算值：old_root = b.ROOT / 'work/fpsv2_pipeline_20261030_08'。
        old_root = b.ROOT / 'work/fpsv2_pipeline_20261030_08'
        # 维护本地状态/计算值：old_profile = json.loads((old_root/'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']。
        old_profile = json.loads((old_root/'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']
        # 维护本地状态/计算值：new_profile = json.loads((b.CANDIDATE/'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']。
        new_profile = json.loads((b.CANDIDATE/'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']
        b.require(old_profile == new_profile, 'Reference carrier differs from actual board')
        sys.path.insert(0, str(old_root/'board_tools'))
        from live_reference_02 import LiveReference02
        # 维护本地状态/计算值：frame = (output/'captured_rgb565le.bin').read_bytes()。
        frame = (output/'captured_rgb565le.bin').read_bytes()
        # 维护本地状态/计算值：reference = LiveReference02().calculate(frame, mode='packed_integer')。
        reference = LiveReference02().calculate(frame, mode='packed_integer')
        b.require(reference['frame_sha256'] == sha(frame) and reference['reference_mode']=='packed_integer',
                  'Reference frame identity differs')
        # 维护本地状态/计算值：meta = b.save_live_golden(reference, output/'integer_reference')。
        meta = b.save_live_golden(reference, output/'integer_reference')
        pairs = {'input':reference['input'], 'framebuffer':reference['display'], **reference['heads']}
        checks = []
        # 迭代/等待条件：pairs.items()；退出由原循环条件及显式 break/异常决定。
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
        # 按条件 selected 选择后续流程，保留原有异常和退出分支。
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
        # 向调用方返回本步骤结果：report。
        return report
    except BaseException as exc:
        report['phase_at_error'] = report['phase']
        report['phase'] = 'failed'
        report['error'] = {'type':type(exc).__name__,'message':str(exc)}
        save()
        # 停止当前调用并上报异常：raise。
        raise
