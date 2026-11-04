"""Resume this powered session's verified model; camera only, no elapsed-time stop.

Direct user-authorized process, not a scheduler. Create the recorded STOP_REQUESTED
file only when the user requests stopping. Protocol/hardware errors still stop.
"""
from pathlib import Path
import argparse,json,msvcrt,sys,time,traceback
import run_board_preview21 as prepared
import board_common as b
from continuous_modes_21 import run
R=Path(__file__).resolve().parents[1]

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--board-approved',action='store_true');p.add_argument('--resume-from',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
 a=p.parse_args();b.require(a.board_approved,'Explicit board authorization required')
 prior_path=a.resume_from.resolve()/'result.json';prior=json.loads(prior_path.read_text(encoding='utf8'))
 b.require(prior['phase']=='cancelled_by_user_before_fixed_verification' and prior['startup']['pass'] and len(prior['model_receipts'])==317 and not prior['real_camera_capture_called'],'Resume only the just-interrupted verified model session')
 q=prepared.qualified(R/'board_tools/bitgen_graph21_01/QUALIFIED_BITGEN_21.json')
 b.require(prior['firmware_build_id']==prepared.BUILD and prior['qualification']['bitstream']['sha256']==q['bitstream']['sha256'],'Resume identity differs')
 out=a.out.resolve();b.require(out.is_relative_to(R/'board_tools') and not out.exists(),'Use a new evidence directory');out.mkdir()
 report=dict(started_utc=b.utc(),phase='resume_preflight',firmware_build_id=prepared.BUILD,qualification=q,Flash_written=False,
  real_camera_capture_called=False,physical_panel_verified=False,user_instruction='不用搞固定图验证，直接摄像头正式测试，不要设定时间限制',
  fixed_replay_skipped_by_user=True,automatic_time_limit_seconds=None,model_receipts=prior['model_receipts'],
  startup=prior['startup'],resumed_from=str(prior_path),resumed_from_sha256=b.sha_file(prior_path),
  scope='Real camera complete recognition and independent preview, one ARM with no elapsed-time limit; retained verified DDR model; no fixed-image replay or accuracy claim')
 report['runner_sources_sha256']={n:b.sha_file(R/'board_tools'/n) for n in ['run_camera_unbounded21.py','run_board_preview21.py','continuous_modes_21.py','board_common.py','board_monitor.py','graph_executor_protocol.py','frame_pool_protocol.py']}
 def save():
  # Windows readers can deny rename while briefly holding result.json. A status
  # display conflict must not abort the hardware workflow. Raw UART/frame logs
  # remain append-only; a later save publishes the next complete JSON snapshot.
  tmp=out/'result.tmp';tmp.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
  for attempt in range(8):
   try:
    tmp.replace(out/'result.json');return
   except PermissionError:
    if attempt<7:time.sleep(.01)
  report['status_snapshot_deferrals']=report.get('status_snapshot_deferrals',0)+1
  print(json.dumps(dict(stage='status_snapshot_deferred',count=report['status_snapshot_deferrals'])),flush=True)
 save();lock=None;locked=False;claimed=False
 try:
  lock=b.LOCK.open('r+b');lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1);locked=True
  model=b.verify_models()['palm'];devices=b.enumerate_devices(None);report['devices']=devices
  b.require(devices==prior['devices'],'Device enumeration changed since upload')
  old=b.STATUS.read_text(encoding='utf8');(out/'previous_board_status.md').write_text(old,encoding='utf8')
  b.STATUS.write_text(f'# Board resource lease\n\nUTC {b.utc()}; owner candidate21 camera unbounded; explicit user authorization; evidence {out}.\n\n'+old,encoding='utf8');claimed=True;save()
  with b.Monitor.open(devices['uart']['port'],out/'serial',timeout=20) as mon:
   # Preserve and drain only the prior interrupted read response before fresh nonce.
   drain_end=time.monotonic()+1.2
   while time.monotonic()<drain_end:
    data=mon.transport.read(4096);mon._record('rx',data)
   report['identity']=mon.ping(prepared.BUILD);b.check_identity(report['identity']);save()
   _,raw=mon.request(22,0);query=b.decode_query(raw)
   run(mon,model,report,save,out,query=query,seconds=None,mode='preview')
   report['identity_after']=mon.ping(prepared.BUILD);b.check_identity(report['identity_after']);report['phase']='stopped_and_validated';save()
 except BaseException as exc:
  report['phase_at_error']=report['phase'];report['phase']='failed';report['error']=dict(type=type(exc).__name__,message=str(exc),traceback=traceback.format_exc());save()
 finally:
  if claimed:
   old=b.STATUS.read_text(encoding='utf8');b.STATUS.write_text(f'# Board resource released\n\nUTC {b.utc()}; candidate21 camera runner ended; phase {report["phase"]}; evidence {out}.\n\n'+old,encoding='utf8')
  if locked:lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
  if lock is not None:lock.close()
  report['finished_utc']=b.utc();save()
 print(json.dumps(dict(phase=report['phase'],error=report.get('error')),ensure_ascii=False),flush=True)
 return 0 if report['phase']=='stopped_and_validated' else 1

if __name__=='__main__':raise SystemExit(main())
