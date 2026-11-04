# 架构导读：run_camera60_sixpose_13_01。
# 主机执行入口，组织本文件中显式选择的检查或板卡操作流程。
"""SRAM-only six-gesture camera acceptance. --help never opens hardware.

One operator-confirmed pose at a time; every bounded sample is retained,
including short captures, missing detections and wrong classifications.
"""
from pathlib import Path
import argparse
import json
import msvcrt
import struct
import subprocess
import sys
import time
import traceback
import board_common as b

# 维护本地状态/计算值：HERE = Path(__file__).resolve().parent.parent。
HERE = Path(__file__).resolve().parent.parent
# 维护本地状态/计算值：BUILD = "bd0690f04d0413f8"。
BUILD = "bd0690f04d0413f8"
# 维护本地状态/计算值：NAMES = ["fist", "one", "peace", "three", "four", "palm"]。
NAMES = ["fist", "one", "peace", "three", "four", "palm"]
# 维护本地状态/计算值：b.BUILD = BUILD。
b.BUILD = BUILD
# 维护本地状态/计算值：b.CANDIDATE = HERE。
b.CANDIDATE = HERE
# 维护本地状态/计算值：b.FW = HERE / "fw_build_01"。
b.FW = HERE / "fw_build_01"


# 接口 qualified，显式输入字段：path。
# 本函数调用入口包括 json.loads, b.require, fw['image_sha256'].items, path.read_text, b.path_ref。
def qualified(path):
    # 维护本地状态/计算值：q = json.loads(path.read_text(encoding="utf8"))。
    q = json.loads(path.read_text(encoding="utf8"))
    b.require(q["schema"] == "RV32_CAMERA_OSD_FIX_BITGEN_V1" and
              q["status"] == "QUALIFIED_NATIVE_BITSTREAM" and
              q["firmware_build_id"] == BUILD and q["timing_all_classes_pass"],
              "New six-class bitstream is not qualified")
    # 迭代/等待条件：('bitstream', 'physical_review', 'source_audit', 'firmware_manifest', 'routed_adf', 'timing_summary', 'bitg...；退出由原循环条件及显式 break/异常决定。
    for key in ("bitstream", "physical_review", "source_audit", "firmware_manifest",
                "routed_adf", "timing_summary", "bitgen_execution"):
        b.path_ref(q[key])
    # 维护本地状态/计算值：fw = json.loads(Path(q["firmware_manifest"]["path"]).read_text(encoding="utf8"))。
    fw = json.loads(Path(q["firmware_manifest"]["path"]).read_text(encoding="utf8"))
    b.require(fw["build_id"] == BUILD, "Firmware identity differs")
    # 迭代/等待条件：fw['image_sha256'].items()；退出由原循环条件及显式 break/异常决定。
    for name, digest in fw["image_sha256"].items():
        b.require(b.sha_file(b.FW/name) == digest, "Canonical MEM differs")
    # 向调用方返回本步骤结果：q。
    return q


# 接口 six_config，显式输入字段：model, frame, fb, run。
# 本函数调用入口包括 list, struct.pack, struct.unpack, b.make_config。
def six_config(model, frame, fb, run):
    # 维护本地状态/计算值：words = list(struct.unpack("<40I", b.make_config(model["package"], frame, fb, run, camera=True)))。
    words = list(struct.unpack("<40I", b.make_config(model["package"], frame, fb, run, camera=True)))
    # 维护本地状态/计算值：words[18] = 0xFFFFFFFF。
    words[18] = 0xFFFFFFFF
    # 向调用方返回本步骤结果：struct.pack("<40I", *words)。
    return struct.pack("<40I", *words)


# 接口 stats，显式输入字段：mon, folder, suffix。
# 本函数调用入口包括 mon.request, b.require, (folder / f'{name}_{suffix}.bin').write_bytes, parser。
def stats(mon, folder, suffix):
    # 维护本地状态/计算值：result = {}。
    result = {}
    # 迭代/等待条件：((17, 's3', b.s3_counts), (27, 'window', b.decode_window), (29, 'concat', b.decode_concat), (18, 'profile',...；退出由原循环条件及显式 break/异常决定。
    for opcode, name, parser in ((17, "s3", b.s3_counts),
                                 (27, "window", b.decode_window),
                                 (29, "concat", b.decode_concat),
                                 (18, "profile", b.decode_profile)):
        # 维护本地状态/计算值：status, raw = mon.request(opcode, 0)。
        status, raw = mon.request(opcode, 0)
        b.require(status == 0, "Counter query failed")
        (folder/f"{name}_{suffix}.bin").write_bytes(raw)
        # 维护本地状态/计算值：result[name] = parser(raw)。
        result[name] = parser(raw)
    # 向调用方返回本步骤结果：result。
    return result


# 接口 classify，显式输入字段：mon, model, expected, frame, run, folder。
# 本函数调用入口包括 folder.mkdir, mon.request, b.decode_query, b.session_start, six_config。
def classify(mon, model, expected, frame, run, folder):
    folder.mkdir()
    # 维护本地状态/计算值：_, video_raw = mon.request(22, 0)。
    _, video_raw = mon.request(22, 0)
    # 维护本地状态/计算值：video = b.decode_query(video_raw)。
    video = b.decode_query(video_raw)
    # 维护本地状态/计算值：_, _, fb = b.session_start(video, run, 1)。
    _, _, fb = b.session_start(video, run, 1)
    # 维护本地状态/计算值：cfg = six_config(model, frame, fb, run)。
    cfg = six_config(model, frame, fb, run)
    (folder/"config.bin").write_bytes(cfg)
    mon.write_memory(b.CONFIG_ADDRESS, cfg)
    mon.request(17, 1)
    mon.request(18, 1)
    # 维护本地状态/计算值：before = stats(mon, folder, "before")。
    before = stats(mon, folder, "before")
    # 维护本地状态/计算值：began = time.monotonic()。
    began = time.monotonic()
    # 维护本地状态/计算值：status, raw = mon.request(25, b.CONFIG_ADDRESS, allow_status=tuple(range(1, 64)))。
    status, raw = mon.request(25, b.CONFIG_ADDRESS, allow_status=tuple(range(1, 64)))
    # 维护本地状态/计算值：elapsed = time.monotonic()-began。
    elapsed = time.monotonic()-began
    (folder/"workflow.bin").write_bytes(raw)
    # 维护本地状态/计算值：row = b.decode(raw, status)。
    row = b.decode(raw, status)
    # 维护本地状态/计算值：row["selected_gesture_count"] = row.pop("palm_count")。
    row["selected_gesture_count"] = row.pop("palm_count")
    # 维护本地状态/计算值：selected = row["selected_gesture_count"] != 0。
    selected = row["selected_gesture_count"] != 0
    row.update(expected_class_id=expected, expected_class_name=NAMES[expected],
               predicted_class_id=row["class_id"] if selected else None,
               predicted_class_name=NAMES[row["class_id"]] if selected and row["class_id"] < 6 else None,
               host_command_seconds=elapsed,
               expected_pose_evidence="Operator READY for this class before the bounded samples",
               pose_match=bool(row["pass_result"] and selected and row["class_id"] == expected))
    b.require((row["frame_id"], row["run_id"], row["framebuffer"]) == (frame, run, hex(fb)),
              "Workflow identity mismatch")
    b.require(row["source"] == "real CMOS2 capture", "A fixture is not a camera acceptance frame")
    # 维护本地状态/计算值：after = stats(mon, folder, "after")。
    after = stats(mon, folder, "after")
    # 维护本地状态/计算值：row["counters_before"] = before。
    row["counters_before"] = before
    # 维护本地状态/计算值：row["counters_after"] = after。
    row["counters_after"] = after
    # 按条件 row['pass_result'] 选择后续流程，保留原有异常和退出分支。
    if row["pass_result"]:
        b.require(row["capture_sensor_pixels"] == row["capture_writer_pixels"] == 921600 and
                  not row["capture_errors"] and row["graph_ops"] == 204 and
                  row["accepted_bytes"] == row["committed_bytes"] == 462400 and
                  not row["video_fault"] and row["underflow_after"] == row["underflow_before"],
                  "Capture/Graph/display completion contradicted")
        b.require((after["s3"]["jobs"], after["s3"]["fallbacks"], after["s3"]["LUT_jobs"]) == (60,0,57),
                  "S3 graph count differs")
        # 维护本地状态/计算值：row["Window_delta"] = b.window_delta_05(before["window"], after["window"], model["window_expected"])。
        row["Window_delta"] = b.window_delta_05(before["window"], after["window"], model["window_expected"])
        # 维护本地状态/计算值：row["Concat_delta"] = b.concat_delta(before["concat"], after["concat"], True)。
        row["Concat_delta"] = b.concat_delta(before["concat"], after["concat"], True)
        b.require((after["profile"]["ops"], after["profile"]["batches"], after["profile"]["errors"]) == (204,1,0),
                  "Graph profile differs")
        # 维护本地状态/计算值：count = row["NMS_count"]。
        count = row["NMS_count"]
        b.require(count <= 64, "NMS exceeds its output allocation")
        # 维护本地状态/计算值：det_raw = mon.read_memory(model["manifest"]["detection"]["result_address"], count*24) if count else b""。
        det_raw = mon.read_memory(model["manifest"]["detection"]["result_address"], count*24) if count else b""
        (folder/"nms_results.bin").write_bytes(det_raw)
        # 维护本地状态/计算值：detections = []。
        detections = []
        # 迭代/等待条件：range(0, len(det_raw), 24)；退出由原循环条件及显式 break/异常决定。
        for off in range(0, len(det_raw), 24):
            # 维护本地状态/计算值：x1,y1,x2,y2,score,cls = struct.unpack_from("<6I", det_raw, off)。
            x1,y1,x2,y2,score,cls = struct.unpack_from("<6I", det_raw, off)
            b.require(cls < 6 and 0 < score <= 32767 and x1 < x2 and y1 < y2,
                      "Invalid NMS result")
            detections.append(dict(class_id=cls, class_name=NAMES[cls], score_q15=score,
                                   xyxy_q16=[x1,y1,x2,y2]))
        # 维护本地状态/计算值：row["detections"] = detections。
        row["detections"] = detections
        # 按条件 selected 选择后续流程，保留原有异常和退出分支。
        if selected:
            b.require(row["class_id"] < 6 and any(d["class_id"] == row["class_id"] and
                      d["score_q15"] == row["score_q15"] for d in detections),
                      "Selected class is not in NMS")
    else:
        b.require(status == 13 and row["phase"] == 1,
                  "Unexpected hardware failure: stop; do not automatically retry")
        # 维护本地状态/计算值：row["failure_scope"] = "Bad camera capture; PP/NN did not run; retained as a failed sample"。
        row["failure_scope"] = "Bad camera capture; PP/NN did not run; retained as a failed sample"
    (folder/"result.json").write_text(json.dumps(row, indent=2), encoding="utf8")
    # 向调用方返回本步骤结果：row。
    return row


# 接口 main，显式输入字段：无位置参数。
# 本函数调用入口包括 argparse.ArgumentParser, p.add_argument, p.parse_args, b.require, a.out.resolve。
def main():
    # 维护本地状态/计算值：p = argparse.ArgumentParser(description="13 camera60: requires explicit user approval before this command may ru...。
    p = argparse.ArgumentParser(description="13 camera60: requires explicit user approval before this command may run.")
    p.add_argument("--board-approved", action="store_true", help="Only pass after user explicitly authorizes this board run")
    p.add_argument("--qualification", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--samples-per-pose", type=int, default=3, help=argparse.SUPPRESS)
    # 维护本地状态/计算值：a = p.parse_args()。
    a = p.parse_args()
    b.require(a.board_approved, "Board work is on user hold. Obtain explicit approval before passing --board-approved.")
    # 维护本地状态/计算值：out = a.out.resolve()。
    out = a.out.resolve()
    b.require(out.is_relative_to((HERE/"board_tools").resolve()) and not out.exists(), "Use a new evidence folder")
    b.require(1 <= a.samples_per_pose <= 5, "Samples must be bounded")
    # 维护本地状态/计算值：q = qualified(a.qualification.resolve())。
    q = qualified(a.qualification.resolve())
    # 维护本地状态/计算值：proof_path=HERE/"reports/SAME_SESSION_READBACK_PREPARATION_13.json"。
    proof_path=HERE/"reports/SAME_SESSION_READBACK_PREPARATION_13.json"
    # 维护本地状态/计算值：proof=json.loads(proof_path.read_text(encoding="utf8"))。
    proof=json.loads(proof_path.read_text(encoding="utf8"))
    b.require(proof["passed"] and b.sha_file(Path(proof["helper"]))==proof["helper_sha256"] and
              b.sha_file(Path(proof["fake_test"]))==proof["fake_test_sha256"] and
              b.sha_file(Path(proof["fake_result"]))==proof["fake_result_sha256"] and
              json.loads(Path(proof["fake_result"]).read_text(encoding="utf8"))["phase"]=="PASS",
              "Same-session diagnostic script was modified or its fake test proof is missing")
    b.require(b.sha_file(HERE/"board_tools/continuous_all6_sixpose_13_01.py")=="dbe971e5e26473e7b842924075d1710132d695be2efd10e456a4301f233dd302", "Pose schedule module changed")
    # 维护本地状态/计算值：model = b.verify_models()["palm"]。
    model = b.verify_models()["palm"]
    out.mkdir()
    # 维护本地状态/计算值：report = dict(started_utc=b.utc(), phase="preflight", firmware_build_id=BUILD,。
    report = dict(started_utc=b.utc(), phase="preflight", firmware_build_id=BUILD,
                  qualification=q, Flash_written=False, real_camera_capture_called=False,
                  model_receipts=[], poses=[], physical_panel_verified=False,
                  scope="Unlabelled 60second realcamera continuous observation; capture errors retained; no class accuracy claim")
    # 接口 save，显式输入字段：无位置参数。
    # 本函数调用入口包括 (out / 'result.json').write_text, json.dumps。
    def save():
        (out/"result.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    save()
    # 维护本地状态/计算值：lock=None; locked=False; claimed=False。
    lock=None; locked=False; claimed=False
    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        # 维护本地状态/计算值：lock=b.LOCK.open("r+b"); lock.seek(0)。
        lock=b.LOCK.open("r+b"); lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1); locked=True
        b.require(not b.port_in_use(), "JTAG server belongs to another session")
        # 维护本地状态/计算值：devices=b.enumerate_devices(None); report["devices"]=devices。
        devices=b.enumerate_devices(None); report["devices"]=devices
        # 维护本地状态/计算值：prior=b.STATUS.read_text(encoding="utf8")。
        prior=b.STATUS.read_text(encoding="utf8")
        (out/"previous_board_status.md").write_text(prior,encoding="utf8")
        # 维护本地状态/计算值：header=f"# Board resource lease\n\nUTC {b.utc()}; current owner: Vision5MP / DDR_HDMI_STARTUP_02 ; camera OSD sa...。
        header=f"# Board resource lease\n\nUTC {b.utc()}; current owner: Vision5MP / DDR_HDMI_STARTUP_02 ; camera OSD same-session diagnostic 13; evidence {out}.\n\n"
        b.STATUS.write_text(header+prior,encoding="utf8");claimed=True;save()
        # 维护本地状态/计算值：report["phase"]="SRAM_program_and_startup";save()。
        report["phase"]="SRAM_program_and_startup";save()
        # 维护本地状态/计算值：cmd=[sys.executable,"-B","-X","utf8",str(HERE/"board_tools/program_window_sram_70.py"),。
        cmd=[sys.executable,"-B","-X","utf8",str(HERE/"board_tools/program_window_sram_70.py"),
             "--bitstream",q["bitstream"]["path"],"--expected-sha256",q["bitstream"]["sha256"],
             "--lease-record",str(b.STATUS),"--out",str(out/"startup"),"--port",devices["uart"]["port"],
             "--cpu-hz","70000000","--expected-build",BUILD,"--startup-diagnostic-firmware",str(b.FW/"manifest.json"),
             "--pds-bin",str(b.PDS),"--seconds","45","--program-timeout","240"]
        # 维护本地状态/计算值：report["startup_command"]=cmd;save()。
        report["startup_command"]=cmd;save()
        # 资源上下文：with (out/"startup_console.log").open("xb") as log:；离开上下文时执行对应清理约定。
        with (out/"startup_console.log").open("xb") as log:
            # 维护本地状态/计算值：code=subprocess.call(cmd,cwd=HERE/"board_tools",stdout=log,stderr=subprocess.STDOUT,。
            code=subprocess.call(cmd,cwd=HERE/"board_tools",stdout=log,stderr=subprocess.STDOUT,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        # 维护本地状态/计算值：startup=json.loads((out/"startup/result.json").read_text(encoding="utf8"));report["startup"]=startup;save()。
        startup=json.loads((out/"startup/result.json").read_text(encoding="utf8"));report["startup"]=startup;save()
        b.require(code==0 and startup.get("pass") is True and startup.get("monitor_challenge",{}).get("valid") is True,
                  "SRAM startup proof failed")
        # 资源上下文：with b.Monitor.open(devices["uart"]["port"],out/"serial",timeout=20) as mon:；离开上下文时执行对应清理约定。
        with b.Monitor.open(devices["uart"]["port"],out/"serial",timeout=20) as mon:
            report["identity"]=mon.ping(BUILD);b.check_identity(report["identity"]);save()
            report["phase"]="DDR_initial_test";save()
            report["DDR_tests"]=b.ddr_test(mon);save()
            report["phase"]="model_upload_and_readback";save()
            # 迭代/等待条件：model['assets'].items()；退出由原循环条件及显式 break/异常决定。
            for name, asset in model["assets"].items():
                # 按条件 name == 'input_hwc_i8' 选择后续流程，保留原有异常和退出分支。
                if name=="input_hwc_i8":continue
                receipt=b.upload(mon,asset["path"],asset["address"],asset["sha256"])
                report["model_receipts"].append(dict(name=name,**receipt));save()
                # 按条件 len(report['model_receipts']) % 16 == 0 选择后续流程，保留原有异常和退出分支。
                if len(report["model_receipts"])%16==0:
                    print(json.dumps(dict(stage="model_verified",count=len(report["model_receipts"])),),flush=True)
            b.require(len(report["model_receipts"])==317,"Incomplete model")
            report["phase"]="awaiting_user_pose_ready";save()
            print(json.dumps(dict(stage="awaiting_user_pose_ready",schedule=["握拳","单指","V字","三指","四指","张掌"],seconds_each=10),ensure_ascii=False),flush=True)
            ready=sys.stdin.readline().strip()
            b.require(ready=="READY", "Pose readiness not provided; no camera capture started")
            report["user_ready_received"]=True;report["phase"]="pose_ready";save()
            _,raw=mon.request(22,0);video=b.decode_query(raw)
            frame,run,_=b.session_start(video,60000,1000)
            from continuous_all6_sixpose_13_01 import run as run_continuous_all6
            run_continuous_all6(mon, model, report, save, out, query=video, seconds=60)
            report["phase"]="same_session_final_frame_readback";save()
            from compare_stopped_frame_in_session_13 import compare as compare_stopped_frame
            report["same_frame"]=compare_stopped_frame(mon,model,report["continuous"],out/"same_frame")
            report["same_frame"]["claim_scope"]="One final frame only; does not measure class accuracy";save()
            report["identity_after"]=mon.ping(BUILD);b.check_identity(report["identity_after"])
            report["phase"]="complete"
            save()
    except BaseException as exc:
        report["phase_at_error"]=report["phase"];report["phase"]="failed"
        report["error"]=dict(type=type(exc).__name__,message=str(exc),traceback=traceback.format_exc());save()
    finally:
        # 按条件 claimed 选择后续流程，保留原有异常和退出分支。
        if claimed:
            prior=b.STATUS.read_text(encoding="utf8")
            b.STATUS.write_text(f"# Board resource released / FPS_V2 已释放\n\nUTC {b.utc()}; camera OSD same-session diagnostic 13 lease released; phase {report['phase']}; evidence {out}.\n\n"+prior,encoding="utf8")
        # 按条件 locked 选择后续流程，保留原有异常和退出分支。
        if locked:lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
        # 按条件 lock is not None 选择后续流程，保留原有异常和退出分支。
        if lock is not None:lock.close()
        report["finished_utc"]=b.utc();save()
    print(json.dumps(dict(stage="session_finished",phase=report["phase"],
                         completed_frames=report.get("continuous",{}).get("completed_frames",0))),flush=True)
    # 向调用方返回本步骤结果：0 if report["phase"]=="complete" else 1。
    return 0 if report["phase"]=="complete" else 1


# 按条件 __name__ == '__main__' 选择后续流程，保留原有异常和退出分支。
if __name__=="__main__":
    # 停止当前调用并上报异常：raise SystemExit(main())。
    raise SystemExit(main())
