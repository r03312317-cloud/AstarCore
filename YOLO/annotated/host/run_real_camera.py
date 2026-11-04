# 架构导读：run_real_camera。
# 主机执行入口，组织本文件中显式选择的检查或板卡操作流程。
"""Exclusive SRAM load, model readback and real camera completion measurement."""
from pathlib import Path
import argparse
import datetime
import json
import msvcrt
import socket
import subprocess
import sys
import time
import traceback

# 维护本地状态/计算值：ROOT=Path(__file__).resolve().parent。
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'board_tools'))
import board_common as b
from continuous_modes_21 import run as run_camera
from capture_stats_13 import decode as capture_stats
from frame_pool_protocol import pool_snapshot
from graph_executor_protocol import decode as graph_snapshot
from cmos2_protocol import preview_snapshot

# 维护本地状态/计算值：b.BUILD='ed37c7c631dc7896'。
b.BUILD='ed37c7c631dc7896'
# 维护本地状态/计算值：b.FW=ROOT/'runtime_policy/workspace/firmware_runtime_02'。
b.FW=ROOT/'runtime_policy/workspace/firmware_runtime_02'
# 维护本地状态/计算值：b.CANDIDATE=ROOT。
b.CANDIDATE=ROOT
# 维护本地状态/计算值：MODEL=ROOT/'Soc_StreamReviewed_20261103/canonical_model'。
MODEL=ROOT/'Soc_StreamReviewed_20261103/canonical_model'
# 维护本地状态/计算值：NATIVE=Path('D:/workspace/riscv-fpga-soc/build/yrev27_05')。
NATIVE=Path('D:/workspace/riscv-fpga-soc/build/yrev27_05')


# 接口 preflight，显式输入字段：无位置参数。
# 本函数调用入口包括 json.loads, b.require, meta['snapshot_sha256'].items, fw['image_sha256'].items, dict。
def preflight():
    # 维护本地状态/计算值：receipts={}。
    receipts={}
    # 迭代/等待条件：('synthesis', 'route', 'timing', 'bitstream')；退出由原循环条件及显式 break/异常决定。
    for stage in ('synthesis','route','timing','bitstream'):
        # 维护本地状态/计算值：path=NATIVE/stage/'result.json'。
        path=NATIVE/stage/'result.json'
        # 维护本地状态/计算值：value=json.loads(path.read_text(encoding='utf8'))。
        value=json.loads(path.read_text(encoding='utf8'))
        b.require(value['passed'],stage+' did not pass')
        # 迭代/等待条件：value['artifacts'].items()；退出由原循环条件及显式 break/异常决定。
        for rel,digest in value['artifacts'].items():
            b.require(b.sha_file(NATIVE/rel)==digest,'Changed build artifact '+rel)
        # 维护本地状态/计算值：receipts[stage]=dict(path=str(path),sha256=b.sha_file(path))。
        receipts[stage]=dict(path=str(path),sha256=b.sha_file(path))
    # 维护本地状态/计算值：timing=json.loads((NATIVE/'timing/timing_audit.json').read_text())。
    timing=json.loads((NATIVE/'timing/timing_audit.json').read_text())
    b.require(timing['constrained_timing_pass'] and len(timing['sections'])==10,'All ten timing summaries required')
    # 维护本地状态/计算值：physical=ROOT/'PHYSICAL_REVIEW.json'。
    physical=ROOT/'PHYSICAL_REVIEW.json'
    # 维护本地状态/计算值：audit=json.loads(physical.read_text())。
    audit=json.loads(physical.read_text())
    b.require(audit['status']=='PASS_FOR_BOARD' and audit['native_build']==str(NATIVE),'Physical review required')
    # 维护本地状态/计算值：meta=json.loads((NATIVE/'run.json').read_text())。
    meta=json.loads((NATIVE/'run.json').read_text())
    # 迭代/等待条件：meta['snapshot_sha256'].items()；退出由原循环条件及显式 break/异常决定。
    for rel,digest in meta['snapshot_sha256'].items():
        b.require(b.sha_file(NATIVE/'snapshot'/rel)==digest,'Changed frozen input '+rel)
    # 维护本地状态/计算值：fw=json.loads((b.FW/'manifest.json').read_text())。
    fw=json.loads((b.FW/'manifest.json').read_text())
    b.require(fw['build_id']==b.BUILD,'Wrong firmware')
    # 迭代/等待条件：fw['image_sha256'].items()；退出由原循环条件及显式 break/异常决定。
    for name,digest in fw['image_sha256'].items():
        # 迭代/等待条件：(b.FW, NATIVE / 'synthesis/project', NATIVE / 'bitstream/project')；退出由原循环条件及显式 break/异常决定。
        for folder in (b.FW,NATIVE/'synthesis/project',NATIVE/'bitstream/project'):
            b.require(b.sha_file(folder/name)==digest,'Firmware image differs: '+str(folder/name))
    # 维护本地状态/计算值：bit=NATIVE/'bitstream/project/prj_tasks/pnr_1/generate_bitstream/soc_board_camera_top.sbit'。
    bit=NATIVE/'bitstream/project/prj_tasks/pnr_1/generate_bitstream/soc_board_camera_top.sbit'
    # 维护本地状态/计算值：q=dict(bitstream=dict(path=str(bit),sha256=b.sha_file(bit)),firmware_build_id=b.BUILD,。
    q=dict(bitstream=dict(path=str(bit),sha256=b.sha_file(bit)),firmware_build_id=b.BUILD,
           firmware_manifest=dict(path=str(b.FW/'manifest.json'),sha256=b.sha_file(b.FW/'manifest.json')),
           stage_receipts=receipts,physical_review=dict(path=str(physical),sha256=b.sha_file(physical)),
           runtime_policy=json.loads((ROOT/'RUNTIME_POLICY_FINAL.json').read_text()))
    # 向调用方返回本步骤结果：q,b.verify_models(MODEL)['palm']。
    return q,b.verify_models(MODEL)['palm']


# 接口 passive_snapshot，显式输入字段：mon, folder。
# 本函数调用入口包括 folder.mkdir, result.get, (folder / 'result.json').write_text, max, dict。
def passive_snapshot(mon,folder):
    folder.mkdir(exist_ok=True)
    # 维护本地状态/计算值：result={}。
    result={}
    # 维护本地状态/计算值：queries=[('camera',5,0,lambda raw:b.Monitor._camera_words(raw,0)),。
    queries=[('camera',5,0,lambda raw:b.Monitor._camera_words(raw,0)),
             ('capture',26,0xfffffffe,capture_stats),('pool',26,0xfffffffc,pool_snapshot),
             ('graph',26,0xfffffffb,graph_snapshot),('preview',26,0xfffffffd,preview_snapshot)]
    # 迭代/等待条件：queries；退出由原循环条件及显式 break/异常决定。
    for name,opcode,arg,decode in queries:
        # 按条件 mon.failed 选择后续流程，保留原有异常和退出分支。
        if mon.failed:break
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            # 维护本地状态/计算值：_,raw=mon.request(opcode,arg);(folder/(name+'.bin')).write_bytes(raw)。
            _,raw=mon.request(opcode,arg);(folder/(name+'.bin')).write_bytes(raw)
            # 维护本地状态/计算值：result[name]=decode(raw)。
            result[name]=decode(raw)
        # 维护本地状态/计算值：except Exception as exc:result[name]={'error':str(exc)}。
        except Exception as exc:result[name]={'error':str(exc)}
    # 维护本地状态/计算值：camera=result.get('camera',{})。
    camera=result.get('camera',{})
    # 按条件 'pixels_written' in camera 选择后续流程，保留原有异常和退出分支。
    if 'pixels_written' in camera:
        # 维护本地状态/计算值：lost=max(0,921600-camera['pixels_written'],921600-camera['sensor_pixels'])。
        lost=max(0,921600-camera['pixels_written'],921600-camera['sensor_pixels'])
        # 维护本地状态/计算值：result['pixel_loss']=dict(expected=921600,lost=lost,ratio=lost/921600,。
        result['pixel_loss']=dict(expected=921600,lost=lost,ratio=lost/921600,
             capture_retired=bool(camera['flags']&4 and not camera['flags']&2),
             threshold=0.10,threshold_reached=lost>=92160)
    (folder/'result.json').write_text(json.dumps(result,indent=2),encoding='utf8')
    # 向调用方返回本步骤结果：result。
    return result


# 接口 main，显式输入字段：无位置参数。
# 本函数调用入口包括 argparse.ArgumentParser, parser.add_argument, parser.parse_args, b.require, preflight。
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board-approved',action='store_true')
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--seconds',type=float,default=120)
    args=parser.parse_args()
    # 按条件 not args.check and (not args.board_approved) 选择后续流程，保留原有异常和退出分支。
    if not args.check and not args.board_approved:parser.error('Explicit board request required')
    b.require(args.seconds>0,'Positive observation duration required')
    qualification,model=preflight()
    # 按条件 args.check 选择后续流程，保留原有异常和退出分支。
    if args.check:
        print(json.dumps(dict(status='OFFLINE_PREFLIGHT_PASS',qualification=qualification),indent=2));return 0
    out=ROOT/'board_runs'/datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f');out.mkdir(parents=True)
    report=dict(phase='preflight',started_utc=b.utc(),qualification=qualification,
       firmware_build_id=b.BUILD,real_camera_capture_called=False,Flash_written=False,
       physical_panel_verified=False,model_receipts=[],requested_observation_seconds=args.seconds,
       user_authorized_request='Run attached YOLO on real board; 10% pixel-loss abort; no recognition-idle timeout',
       runner_sources_sha256={p.name:b.sha_file(p) for p in (ROOT/'board_tools').glob('*.py')})
    # 接口 save，显式输入字段：无位置参数。
    # 本函数调用入口包括 tmp.write_text, range, json.dumps, report.get, tmp.replace。
    def save():
        # A reader holding result.json must never interrupt live firmware.
        tmp=out/'result.tmp';tmp.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
        # 迭代/等待条件：range(8)；退出由原循环条件及显式 break/异常决定。
        for i in range(8):
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:tmp.replace(out/'result.json');return
            except PermissionError:time.sleep(.01)
        report['snapshot_save_deferred']=report.get('snapshot_save_deferred',0)+1
    save();lock=None;locked=False;claimed=False
    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        lock=b.LOCK.open('r+b');lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1);locked=True
        # 迭代/等待条件：('cdt_js.exe', 'cdt_cfg_shell.exe')；退出由原循环条件及显式 break/异常决定。
        for exe in ('cdt_js.exe','cdt_cfg_shell.exe'):
            result=subprocess.run(['tasklist','/FI','IMAGENAME eq '+exe,'/NH'],capture_output=True,
                timeout=15,creationflags=subprocess.CREATE_NO_WINDOW)
            b.require(result.returncode==0 and exe.encode() not in result.stdout.lower(),'Another JTAG owner is active')
        devices=b.enumerate_devices('COM14');report['devices']=devices
        # 迭代/等待条件：range(65450, 65480)；退出由原循环条件及显式 break/异常决定。
        for port in range(65450,65480):
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:
                # 资源上下文：with socket.socket() as sock:sock.bind(('127.0.0.1',port))；离开上下文时执行对应清理约定。
                with socket.socket() as sock:sock.bind(('127.0.0.1',port))
                break
            except OSError:continue
        # 停止当前调用并上报异常：else:raise RuntimeError('No free JTAG TCP port')。
        else:raise RuntimeError('No free JTAG TCP port')
        prior=b.STATUS.read_text(encoding='utf8');(out/'previous_board_status.txt').write_text(prior,encoding='utf8')
        header=f'# Board resource lease\n\nVision5MP / DDR_HDMI_STARTUP_02; owner yolo_reviewed_board_20261103_01; UTC {b.utc()}; evidence {out}\n\n'
        b.STATUS.write_text(header+prior,encoding='utf8');claimed=True
        lease=out/'lease.txt';lease.write_text(header,encoding='utf8')
        cmd=[sys.executable,'-B','-X','utf8',str(ROOT/'board_tools/program_window_sram_70.py'),
             '--bitstream',qualification['bitstream']['path'],'--expected-sha256',qualification['bitstream']['sha256'],
             '--lease-record',str(lease),'--out',str(out/'startup'),'--port',devices['uart']['port'],
             '--jtag-port',str(port),'--cpu-hz','70000000','--expected-build',b.BUILD,
             '--startup-diagnostic-firmware',str(b.FW/'manifest.json'),'--pds-bin',str(b.PDS),
             '--seconds','45','--program-timeout','240','--replace-active']
        report.update(phase='SRAM_program_and_startup',startup_command=cmd);save()
        print(json.dumps(dict(stage=report['phase'],evidence=str(out))),flush=True)
        # 资源上下文：with (out/'startup_console.log').open('xb') as log:；离开上下文时执行对应清理约定。
        with (out/'startup_console.log').open('xb') as log:
            code=subprocess.call(cmd,cwd=ROOT/'board_tools',stdout=log,stderr=subprocess.STDOUT,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        report['startup']=json.loads((out/'startup/result.json').read_text(encoding='utf8'));save()
        b.require(code==0 and report['startup'].get('pass') and report['startup'].get('monitor_challenge',{}).get('valid'),'SRAM/identity validation failed')
        # 资源上下文：with b.Monitor.open(devices['uart']['port'],out/'serial',timeout=20) as mon:；离开上下文时执行对应清理约定。
        with b.Monitor.open(devices['uart']['port'],out/'serial',timeout=20) as mon:
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:
                report['identity']=mon.ping(b.BUILD);b.check_identity(report['identity'])
                report['phase']='DDR_test';save();report['DDR_tests']=b.ddr_test(mon)
                report['phase']='model_upload_and_readback';save()
                # 迭代/等待条件：model['assets'].items()；退出由原循环条件及显式 break/异常决定。
                for name,asset in model['assets'].items():
                    # 按条件 name == 'input_hwc_i8' 选择后续流程，保留原有异常和退出分支。
                    if name=='input_hwc_i8':continue
                    receipt=b.upload(mon,asset['path'],asset['address'],asset['sha256'])
                    report['model_receipts'].append(dict(name=name,**receipt));save()
                    # 按条件 len(report['model_receipts']) % 16 == 0 选择后续流程，保留原有异常和退出分支。
                    if len(report['model_receipts'])%16==0:
                        print(json.dumps(dict(stage='model_verified',count=len(report['model_receipts']))),flush=True)
                b.require(len(report['model_receipts'])==317,'Incomplete model load')
                _,raw=mon.request(22,0);video=b.decode_query(raw)
                run_camera(mon,model,report,save,out,video,seconds=args.seconds,mode='preview')
                report['identity_after']=mon.ping(b.BUILD);b.check_identity(report['identity_after'])
                report['phase']='completed'
            except Exception:
                report['fault_snapshot']=passive_snapshot(mon,out/'fault_snapshot')
                # 停止当前调用并上报异常：raise。
                raise
    except BaseException as exc:
        report.update(phase_at_error=report['phase'],phase='failed',error=str(exc),traceback=traceback.format_exc())
        diagnostic=report.get('fault_snapshot',{})
        loss=diagnostic.get('pixel_loss',{})
        # 按条件 loss.get('capture_retired') and loss.get('threshold_reached') and (diagnostic.get('pool', {}).get('fault') ... 选择后续流程，保留原有异常和退出分支。
        if (loss.get('capture_retired') and loss.get('threshold_reached')
                and diagnostic.get('pool',{}).get('fault')==13):
            report['phase']='stopped_at_pixel_loss_limit'
            report['stop_reason']='User-requested pixel loss threshold reached on a retired camera frame'
    finally:
        report['finished_utc']=b.utc();save()
        # 按条件 claimed 选择后续流程，保留原有异常和退出分支。
        if claimed:
            prior=b.STATUS.read_text(encoding='utf8')
            b.STATUS.write_text(f'# Board resource released\n\nUTC {b.utc()}; reviewed YOLO session {report["phase"]}; evidence {out}\n\n'+prior,encoding='utf8')
        # 按条件 locked 选择后续流程，保留原有异常和退出分支。
        if locked:lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
        # 按条件 lock is not None 选择后续流程，保留原有异常和退出分支。
        if lock is not None:lock.close()
    summary=dict(phase=report['phase'],evidence=str(out),error=report.get('error'),
                 fps=report.get('continuous_preview',{}).get('completion_interval_fps'))
    print(json.dumps(summary,ensure_ascii=False,indent=2),flush=True)
    # 向调用方返回本步骤结果：0 if report['phase'] in ('completed','stopped_at_pixel_loss_limit') else 1。
    return 0 if report['phase'] in ('completed','stopped_at_pixel_loss_limit') else 1


# 按条件 __name__ == '__main__' 选择后续流程，保留原有异常和退出分支。
if __name__=='__main__':raise SystemExit(main())
