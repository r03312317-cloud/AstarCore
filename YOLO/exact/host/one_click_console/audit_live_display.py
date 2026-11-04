"""Read-only validation of a live console session against saved UART replies."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import video_runner as app
from cmos2_protocol import continuous_snapshot
from completion_fps import calculate


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session',type=Path)
    args=parser.parse_args()
    folder=args.session.resolve()
    assert folder.parent==app.HERE/'logs'
    r=json.loads((folder/'result.json').read_text(encoding='utf-8'))
    c=r['continuous_preview']
    assert r['status']=='running' and r['phase']=='camera_continuous_unbounded'
    assert c['firmware_active'] and c['time_limit_seconds'] is None and c['STOP_commands']==0
    assert r['startup']['pass'] and r['identity']['build_id']=='ed37c7c631dc7896'
    receipts=r['model_receipts']
    assert len(receipts)==317 and all(x['passed'] and x['sha256']==x['readback_sha256'] for x in receipts)
    size=sum(x['bytes'] for x in receipts)
    assert size==1856488
    meter=r['model_transfer']
    assert meter['uploaded_bytes']==meter['readback_bytes']==size
    assert meter['transferred_bytes']==size*2
    assert abs(meter['average_bytes_per_second']-size*2/meter['elapsed_seconds'])<1e-9
    n=c['current_completed_frames']
    raw=(folder/'continuous_unbounded_preview/completed_snapshots.bin').read_bytes()
    samples=[]
    for start in range(0,len(raw)//304*304,304):
        reply=continuous_snapshot(raw[start:start+304]);row=reply['last_run']
        if reply['completed']>n:break
        assert row['pass_result'] and row['graph_ops']==204 and row['source']=='real CMOS2 capture'
        assert row['capture_writer_pixels']==row['capture_sensor_pixels']==921600 and row['capture_errors']==0
        samples.append(dict(completed=reply['completed'],TR=row['timestamps_CPU64']['TR'],cpu_hz=row['cpu_hz'],generation=row['inference_source_generation'],frame_id=row['frame_id'],run_id=row['run_id']))
    measured=calculate(samples)
    assert measured==c['completion_interval_fps'] and measured['valid']
    assert len(c['completion_samples'])==2 and len(c['outputs'])<=16
    result=dict(checked_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),status='LIVE_CONSOLE_ACCEPTED',
                session=str(folder),process_id=r['process_id'],raw_snapshot_FPS_exact_match=True,
                complete_frame_FPS=measured,model_transfer=meter,model_constants_verified=317,
                actual_model_bytes=size,model_payload_transfer_bytes=size*2,
                prediction_counts=c['running_prediction_counts'],no_detection=c['running_no_detection_frames'],
                observed_errors=c['observed_errors'],unbounded=True,STOP_commands=0,
                firmware_build_id=r['firmware_build_id'],bitstream=r['qualification']['bitstream'],
                source_hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in app.HERE.glob('*.py')},
                scope='Live point-in-time validation; future frame rate and hardware state may change.')
    (folder/'LIVE_DISPLAY_AUDIT.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    pointer=dict(kind='native_one_click_GUI',window_title='YOLO · 一键上板识别展示',
                 process_id=r['process_id'],evidence=str(folder),result=str(folder/'result.json'),
                 stop_request_file=str(folder/'continuous_unbounded_preview/STOP_REQUESTED'),
                 time_limit_seconds=None,entrypoint='D:/workspace/riscv-fpga-soc/打开YOLO识别展示窗口.cmd')
    (app.HERE.parent/'ACTIVE_DISPLAY_SESSION.json').write_text(json.dumps(pointer,ensure_ascii=False,indent=2),encoding='utf-8')
    manifest_path=app.HERE/'CONSOLE_MANIFEST.json'
    m=json.loads(manifest_path.read_text(encoding='utf-8'))
    m.update(physical_validation='PASS_LIVE',physical_evidence=str(folder/'LIVE_DISPLAY_AUDIT.json'),
             files_sha256={str(p.relative_to(app.HERE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in app.HERE.iterdir() if p.is_file() and p.suffix in ('.py','.cmd','.txt')})
    manifest_path.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:result[k] for k in ('status','complete_frame_FPS','model_transfer','model_constants_verified','prediction_counts','observed_errors')},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
