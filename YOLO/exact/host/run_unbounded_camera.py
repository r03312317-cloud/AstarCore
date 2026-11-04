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

b = task.b
ROOT = task.ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board-approved', action='store_true', required=True)
    parser.add_argument('--previous-run', type=Path, required=True)
    args = parser.parse_args()
    prior_path = args.previous_run.resolve()
    b.require(prior_path.parent == ROOT / 'board_runs', 'Previous run must belong to this task')
    prior = json.loads((prior_path / 'result.json').read_text(encoding='utf-8'))
    b.require(prior['phase'] == 'completed' and prior['continuous_preview']['STOP_confirmed'], 'Stopped qualified run required')
    qualification, model = task.preflight()
    b.require(qualification['bitstream'] == prior['qualification']['bitstream'], 'Bitstream identity changed')
    out = ROOT / 'board_runs' / ('unbounded_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    r = dict(phase='preflight', started_utc=b.utc(), process_id=os.getpid(),
             qualification=qualification, firmware_build_id=b.BUILD,
             requested_observation_seconds=None, time_limit_seconds=None,
             user_authorized_request='重新检测，不限时；沿用 10% 像素丢失停止阈值，不因长时间未识别停止',
             previous_run=str(prior_path), SRAM_reprogrammed=False, Flash_written=False,
             model_constants_reuploaded=False, scheduled_tasks_created=False,
             physical_panel_verified=False, real_camera_capture_called=False, model_receipts=[],
             runner_sources_sha256={p.name:b.sha_file(p) for p in [ROOT/'run_unbounded_camera.py',ROOT/'continuous_unbounded_runtime.py',ROOT/'completion_accumulator.py']})
    save_time = 0
    save_phase = None
    def save(force=False):
        nonlocal save_time, save_phase
        now = time.monotonic()
        if not force and r['phase'] == 'camera_continuous_unbounded' and save_phase == r['phase'] and now-save_time < 1:
            return
        r['report_updated_utc'] = b.utc()
        tmp = out/'result.tmp'
        tmp.write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
        for attempt in range(8):
            try:
                tmp.replace(out/'result.json')
                save_time,save_phase=now,r['phase']
                return
            except PermissionError:
                time.sleep(.01)
        r['snapshot_save_deferred']=r.get('snapshot_save_deferred',0)+1
    save(True)
    pointer=dict(process_id=os.getpid(),evidence=str(out),result=str(out/'result.json'),
                 stop_request_file=str(out/'continuous_unbounded_preview/STOP_REQUESTED'),time_limit_seconds=None)
    (ROOT/'UNBOUNDED_CURRENT.json').write_text(json.dumps(pointer,indent=2),encoding='utf-8')
    print(json.dumps(pointer,ensure_ascii=False),flush=True)
    locked=claimed=False
    lock=None
    try:
        lock=b.LOCK.open('r+b');lock.seek(0)
        msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1);locked=True
        for exe in ('cdt_js.exe','cdt_cfg_shell.exe'):
            result=subprocess.run(['tasklist','/FI','IMAGENAME eq '+exe,'/NH'],capture_output=True,
                                  timeout=15,creationflags=subprocess.CREATE_NO_WINDOW)
            b.require(result.returncode==0 and exe.encode() not in result.stdout.lower(),'Another JTAG owner is active')
        r['devices']=b.enumerate_devices('COM14')
        previous=b.STATUS.read_text(encoding='utf-8')
        (out/'previous_board_status.txt').write_text(previous,encoding='utf-8')
        b.STATUS.write_text(f'# Board resource lease / YOLO unbounded recognition\n\nUTC {b.utc()}; owner yolo_reviewed_board_20261103_01; PID {os.getpid()}; evidence {out}\n\n'+previous,encoding='utf-8')
        claimed=True
        with b.Monitor.open('COM14',out/'serial',timeout=20) as mon:
            try:
                r['identity']=mon.ping(b.BUILD);b.check_identity(r['identity'])
                _,raw=mon.request(26,0xffffffff)
                (out/'prior_continuous.bin').write_bytes(raw)
                previous_state=b.continuous_snapshot(raw)
                b.require(not previous_state['active'] and previous_state['completed']==prior['continuous_preview']['completed_frames'],
                          'Board state changed after previous session; do not assume resident model validity')
                _,raw=mon.request(26,0xfffffffc)
                (out/'prior_pool.bin').write_bytes(raw)
                b.require(task.pool_snapshot(raw)==prior['continuous_preview']['pool_stats'],'Previous raw pool no longer matches')
                r['phase']='resident_model_readback';save(True)
                for name,asset in model['assets'].items():
                    if name=='input_hwc_i8':continue
                    size=Path(asset['path']).stat().st_size
                    data=mon.read_memory(asset['address'],size)
                    digest=b.sha_bytes(data)
                    row=dict(name=name,address=hex(asset['address']),bytes=size,sha256=asset['sha256'],
                             readback_sha256=digest,passed=digest==asset['sha256'])
                    r['model_receipts'].append(row);save(True)
                    b.require(row['passed'],'Resident model changed: '+name)
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
                raise
    except BaseException as exc:
        r.update(phase_at_error=r['phase'],phase='failed',error=str(exc),traceback=traceback.format_exc())
        d=r.get('fault_snapshot',{});loss=d.get('pixel_loss',{})
        if loss.get('capture_retired') and loss.get('threshold_reached') and d.get('pool',{}).get('fault')==13:
            r.update(phase='stopped_at_pixel_loss_limit',stop_reason='User-requested 10% pixel loss threshold reached')
    finally:
        r['finished_utc']=b.utc();save(True)
        if claimed:
            previous=b.STATUS.read_text(encoding='utf-8')
            b.STATUS.write_text(f'# Board resource released / YOLO unbounded recognition\n\nUTC {b.utc()}; phase {r["phase"]}; evidence {out}\n\n'+previous,encoding='utf-8')
        if locked:
            lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
        if lock is not None:lock.close()
    print(json.dumps(dict(phase=r['phase'],error=r.get('error'),evidence=str(out)),ensure_ascii=False),flush=True)
    return 0 if r['phase'] in ('stopped_by_user_request','stopped_at_pixel_loss_limit') else 1


if __name__=='__main__':
    raise SystemExit(main())
