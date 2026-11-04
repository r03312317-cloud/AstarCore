# 架构导读：run_unbounded_camera。
# 主机执行入口，组织本文件中显式选择的检查或板卡操作流程。
"""Resume the verified, stopped YOLO image indefinitely, in one direct process."""
import argparse
import datetime
import json
import msvcrt
import os
from pathlib import Path
import subprocess
import time
import traceback
import run_real_camera as task
from continuous_unbounded_runtime import run as run_camera

# 维护本地状态/计算值：b = task.b。
b = task.b
# 维护本地状态/计算值：ROOT = task.ROOT。
ROOT = task.ROOT


# 接口 main，显式输入字段：无位置参数。
# 本函数调用入口包括 argparse.ArgumentParser, parser.add_argument, parser.parse_args, args.previous_run.resolve, b.require。
def main():
    # 维护本地状态/计算值：parser = argparse.ArgumentParser(description=__doc__)。
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board-approved', action='store_true', required=True)
    parser.add_argument('--previous-run', type=Path, required=True)
    # 维护本地状态/计算值：args = parser.parse_args()。
    args = parser.parse_args()
    # 维护本地状态/计算值：prior_path = args.previous_run.resolve()。
    prior_path = args.previous_run.resolve()
    b.require(prior_path.parent == ROOT / 'board_runs', 'Previous run must belong to this task')
    # 维护本地状态/计算值：prior = json.loads((prior_path / 'result.json').read_text(encoding='utf-8'))。
    prior = json.loads((prior_path / 'result.json').read_text(encoding='utf-8'))
    b.require(prior['phase'] == 'completed' and prior['continuous_preview']['STOP_confirmed'], 'Stopped qualified run required')
    # 维护本地状态/计算值：qualification, model = task.preflight()。
    qualification, model = task.preflight()
    b.require(qualification['bitstream'] == prior['qualification']['bitstream'], 'Bitstream identity changed')
    # 维护本地状态/计算值：out = ROOT / 'board_runs' / ('unbounded_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))。
    out = ROOT / 'board_runs' / ('unbounded_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    # 维护本地状态/计算值：r = dict(phase='preflight', started_utc=b.utc(), process_id=os.getpid(),。
    r = dict(phase='preflight', started_utc=b.utc(), process_id=os.getpid(),
             qualification=qualification, firmware_build_id=b.BUILD,
             requested_observation_seconds=None, time_limit_seconds=None,
             user_authorized_request='重新检测，不限时；沿用 10% 像素丢失停止阈值，不因长时间未识别停止',
             previous_run=str(prior_path), SRAM_reprogrammed=False, Flash_written=False,
             model_constants_reuploaded=False, scheduled_tasks_created=False,
             physical_panel_verified=False, real_camera_capture_called=False, model_receipts=[],
             runner_sources_sha256={p.name:b.sha_file(p) for p in [ROOT/'run_unbounded_camera.py',ROOT/'continuous_unbounded_runtime.py',ROOT/'completion_accumulator.py']})
    # 维护本地状态/计算值：save_time = 0。
    save_time = 0
    # 维护本地状态/计算值：save_phase = None。
    save_phase = None
    # 接口 save，显式输入字段：force。
    # 本函数调用入口包括 time.monotonic, b.utc, tmp.write_text, range, json.dumps。
    def save(force=False):
        nonlocal save_time, save_phase
        # 维护本地状态/计算值：now = time.monotonic()。
        now = time.monotonic()
        # 按条件 not force and r['phase'] == 'camera_continuous_unbounded' and (save_phase == r['phase']) and (now - save_ti... 选择后续流程，保留原有异常和退出分支。
        if not force and r['phase'] == 'camera_continuous_unbounded' and save_phase == r['phase'] and now-save_time < 1:
            # 向调用方返回本步骤结果：None。
            return
        # 维护本地状态/计算值：r['report_updated_utc'] = b.utc()。
        r['report_updated_utc'] = b.utc()
        # 维护本地状态/计算值：tmp = out/'result.tmp'。
        tmp = out/'result.tmp'
        tmp.write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
        # 迭代/等待条件：range(8)；退出由原循环条件及显式 break/异常决定。
        for attempt in range(8):
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:
                tmp.replace(out/'result.json')
                # 维护本地状态/计算值：save_time,save_phase=now,r['phase']。
                save_time,save_phase=now,r['phase']
                # 向调用方返回本步骤结果：None。
                return
            except PermissionError:
                time.sleep(.01)
        # 维护本地状态/计算值：r['snapshot_save_deferred']=r.get('snapshot_save_deferred',0)+1。
        r['snapshot_save_deferred']=r.get('snapshot_save_deferred',0)+1
    save(True)
    # 维护本地状态/计算值：pointer=dict(process_id=os.getpid(),evidence=str(out),result=str(out/'result.json'),。
    pointer=dict(process_id=os.getpid(),evidence=str(out),result=str(out/'result.json'),
                 stop_request_file=str(out/'continuous_unbounded_preview/STOP_REQUESTED'),time_limit_seconds=None)
    (ROOT/'UNBOUNDED_CURRENT.json').write_text(json.dumps(pointer,indent=2),encoding='utf-8')
    print(json.dumps(pointer,ensure_ascii=False),flush=True)
    # 维护本地状态/计算值：locked=claimed=False。
    locked=claimed=False
    # 维护本地状态/计算值：lock=None。
    lock=None
    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        # 维护本地状态/计算值：lock=b.LOCK.open('r+b');lock.seek(0)。
        lock=b.LOCK.open('r+b');lock.seek(0)
        msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1);locked=True
        # 迭代/等待条件：('cdt_js.exe', 'cdt_cfg_shell.exe')；退出由原循环条件及显式 break/异常决定。
        for exe in ('cdt_js.exe','cdt_cfg_shell.exe'):
            # 维护本地状态/计算值：result=subprocess.run(['tasklist','/FI','IMAGENAME eq '+exe,'/NH'],capture_output=True,。
            result=subprocess.run(['tasklist','/FI','IMAGENAME eq '+exe,'/NH'],capture_output=True,
                                  timeout=15,creationflags=subprocess.CREATE_NO_WINDOW)
            b.require(result.returncode==0 and exe.encode() not in result.stdout.lower(),'Another JTAG owner is active')
        # 维护本地状态/计算值：r['devices']=b.enumerate_devices('COM14')。
        r['devices']=b.enumerate_devices('COM14')
        # 维护本地状态/计算值：previous=b.STATUS.read_text(encoding='utf-8')。
        previous=b.STATUS.read_text(encoding='utf-8')
        (out/'previous_board_status.txt').write_text(previous,encoding='utf-8')
        b.STATUS.write_text(f'# Board resource lease / YOLO unbounded recognition\n\nUTC {b.utc()}; owner yolo_reviewed_board_20261103_01; PID {os.getpid()}; evidence {out}\n\n'+previous,encoding='utf-8')
        # 维护本地状态/计算值：claimed=True。
        claimed=True
        # 资源上下文：with b.Monitor.open('COM14',out/'serial',timeout=20) as mon:；离开上下文时执行对应清理约定。
        with b.Monitor.open('COM14',out/'serial',timeout=20) as mon:
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:
                # 维护本地状态/计算值：r['identity']=mon.ping(b.BUILD);b.check_identity(r['identity'])。
                r['identity']=mon.ping(b.BUILD);b.check_identity(r['identity'])
                # 维护本地状态/计算值：_,raw=mon.request(26,0xffffffff)。
                _,raw=mon.request(26,0xffffffff)
                (out/'prior_continuous.bin').write_bytes(raw)
                previous_state=b.continuous_snapshot(raw)
                b.require(not previous_state['active'] and previous_state['completed']==prior['continuous_preview']['completed_frames'],
                          'Board state changed after previous session; do not assume resident model validity')
                _,raw=mon.request(26,0xfffffffc)
                (out/'prior_pool.bin').write_bytes(raw)
                b.require(task.pool_snapshot(raw)==prior['continuous_preview']['pool_stats'],'Previous raw pool no longer matches')
                r['phase']='resident_model_readback';save(True)
                # 迭代/等待条件：model['assets'].items()；退出由原循环条件及显式 break/异常决定。
                for name,asset in model['assets'].items():
                    # 按条件 name == 'input_hwc_i8' 选择后续流程，保留原有异常和退出分支。
                    if name=='input_hwc_i8':continue
                    size=Path(asset['path']).stat().st_size
                    data=mon.read_memory(asset['address'],size)
                    digest=b.sha_bytes(data)
                    row=dict(name=name,address=hex(asset['address']),bytes=size,sha256=asset['sha256'],
                             readback_sha256=digest,passed=digest==asset['sha256'])
                    r['model_receipts'].append(row);save(True)
                    b.require(row['passed'],'Resident model changed: '+name)
                    # 按条件 len(r['model_receipts']) % 32 == 0 选择后续流程，保留原有异常和退出分支。
                    if len(r['model_receipts'])%32==0:
                        print(json.dumps(dict(stage=r['phase'],verified=len(r['model_receipts']))),flush=True)
                b.require(len(r['model_receipts'])==317,'Incomplete model verification')
                _,raw=mon.request(22,0)
                query=b.decode_query(raw)
                r['identity_before_ARM']=mon.ping(b.BUILD);b.check_identity(r['identity_before_ARM'])
                run_camera(mon,model,r,save,out,query,seconds=None,mode='preview')
                r['identity_after']=mon.ping(b.BUILD);b.check_identity(r['identity_after'])
                r.update(phase='stopped_by_user_request',stop_reason='STOP_REQUESTED file observed; no time limit')
            except Exception:
                r['fault_snapshot']=task.passive_snapshot(mon,out/'fault_snapshot')
                # 停止当前调用并上报异常：raise。
                raise
    except BaseException as exc:
        r.update(phase_at_error=r['phase'],phase='failed',error=str(exc),traceback=traceback.format_exc())
        d=r.get('fault_snapshot',{});loss=d.get('pixel_loss',{})
        # 按条件 loss.get('capture_retired') and loss.get('threshold_reached') and (d.get('pool', {}).get('fault') == 13) 选择后续流程，保留原有异常和退出分支。
        if loss.get('capture_retired') and loss.get('threshold_reached') and d.get('pool',{}).get('fault')==13:
            r.update(phase='stopped_at_pixel_loss_limit',stop_reason='User-requested 10% pixel loss threshold reached')
    finally:
        r['finished_utc']=b.utc();save(True)
        # 按条件 claimed 选择后续流程，保留原有异常和退出分支。
        if claimed:
            previous=b.STATUS.read_text(encoding='utf-8')
            b.STATUS.write_text(f'# Board resource released / YOLO unbounded recognition\n\nUTC {b.utc()}; phase {r["phase"]}; evidence {out}\n\n'+previous,encoding='utf-8')
        # 按条件 locked 选择后续流程，保留原有异常和退出分支。
        if locked:
            lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
        # 按条件 lock is not None 选择后续流程，保留原有异常和退出分支。
        if lock is not None:lock.close()
    print(json.dumps(dict(phase=r['phase'],error=r.get('error'),evidence=str(out)),ensure_ascii=False),flush=True)
    # 向调用方返回本步骤结果：0 if r['phase'] in ('stopped_by_user_request','stopped_at_pixel_loss_limit') else 1。
    return 0 if r['phase'] in ('stopped_by_user_request','stopped_at_pixel_loss_limit') else 1


# 按条件 __name__ == '__main__' 选择后续流程，保留原有异常和退出分支。
if __name__=='__main__':
    # 停止当前调用并上报异常：raise SystemExit(main())。
    raise SystemExit(main())
