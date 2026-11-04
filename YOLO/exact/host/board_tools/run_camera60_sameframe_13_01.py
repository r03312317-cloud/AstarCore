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

HERE = Path(__file__).resolve().parent.parent
BUILD = "bd0690f04d0413f8"
NAMES = ["fist", "one", "peace", "three", "four", "palm"]
b.BUILD = BUILD
b.CANDIDATE = HERE
b.FW = HERE / "fw_build_01"


def qualified(path):
    q = json.loads(path.read_text(encoding="utf8"))
    b.require(q["schema"] == "RV32_CAMERA_OSD_FIX_BITGEN_V1" and
              q["status"] == "QUALIFIED_NATIVE_BITSTREAM" and
              q["firmware_build_id"] == BUILD and q["timing_all_classes_pass"],
              "New six-class bitstream is not qualified")
    for key in ("bitstream", "physical_review", "source_audit", "firmware_manifest",
                "routed_adf", "timing_summary", "bitgen_execution"):
        b.path_ref(q[key])
    fw = json.loads(Path(q["firmware_manifest"]["path"]).read_text(encoding="utf8"))
    b.require(fw["build_id"] == BUILD, "Firmware identity differs")
    for name, digest in fw["image_sha256"].items():
        b.require(b.sha_file(b.FW/name) == digest, "Canonical MEM differs")
    return q


def six_config(model, frame, fb, run):
    words = list(struct.unpack("<40I", b.make_config(model["package"], frame, fb, run, camera=True)))
    words[18] = 0xFFFFFFFF
    return struct.pack("<40I", *words)


def stats(mon, folder, suffix):
    result = {}
    for opcode, name, parser in ((17, "s3", b.s3_counts),
                                 (27, "window", b.decode_window),
                                 (29, "concat", b.decode_concat),
                                 (18, "profile", b.decode_profile)):
        status, raw = mon.request(opcode, 0)
        b.require(status == 0, "Counter query failed")
        (folder/f"{name}_{suffix}.bin").write_bytes(raw)
        result[name] = parser(raw)
    return result


def classify(mon, model, expected, frame, run, folder):
    folder.mkdir()
    _, video_raw = mon.request(22, 0)
    video = b.decode_query(video_raw)
    _, _, fb = b.session_start(video, run, 1)
    cfg = six_config(model, frame, fb, run)
    (folder/"config.bin").write_bytes(cfg)
    mon.write_memory(b.CONFIG_ADDRESS, cfg)
    mon.request(17, 1)
    mon.request(18, 1)
    before = stats(mon, folder, "before")
    began = time.monotonic()
    status, raw = mon.request(25, b.CONFIG_ADDRESS, allow_status=tuple(range(1, 64)))
    elapsed = time.monotonic()-began
    (folder/"workflow.bin").write_bytes(raw)
    row = b.decode(raw, status)
    row["selected_gesture_count"] = row.pop("palm_count")
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
    after = stats(mon, folder, "after")
    row["counters_before"] = before
    row["counters_after"] = after
    if row["pass_result"]:
        b.require(row["capture_sensor_pixels"] == row["capture_writer_pixels"] == 921600 and
                  not row["capture_errors"] and row["graph_ops"] == 204 and
                  row["accepted_bytes"] == row["committed_bytes"] == 462400 and
                  not row["video_fault"] and row["underflow_after"] == row["underflow_before"],
                  "Capture/Graph/display completion contradicted")
        b.require((after["s3"]["jobs"], after["s3"]["fallbacks"], after["s3"]["LUT_jobs"]) == (60,0,57),
                  "S3 graph count differs")
        row["Window_delta"] = b.window_delta_05(before["window"], after["window"], model["window_expected"])
        row["Concat_delta"] = b.concat_delta(before["concat"], after["concat"], True)
        b.require((after["profile"]["ops"], after["profile"]["batches"], after["profile"]["errors"]) == (204,1,0),
                  "Graph profile differs")
        count = row["NMS_count"]
        b.require(count <= 64, "NMS exceeds its output allocation")
        det_raw = mon.read_memory(model["manifest"]["detection"]["result_address"], count*24) if count else b""
        (folder/"nms_results.bin").write_bytes(det_raw)
        detections = []
        for off in range(0, len(det_raw), 24):
            x1,y1,x2,y2,score,cls = struct.unpack_from("<6I", det_raw, off)
            b.require(cls < 6 and 0 < score <= 32767 and x1 < x2 and y1 < y2,
                      "Invalid NMS result")
            detections.append(dict(class_id=cls, class_name=NAMES[cls], score_q15=score,
                                   xyxy_q16=[x1,y1,x2,y2]))
        row["detections"] = detections
        if selected:
            b.require(row["class_id"] < 6 and any(d["class_id"] == row["class_id"] and
                      d["score_q15"] == row["score_q15"] for d in detections),
                      "Selected class is not in NMS")
    else:
        b.require(status == 13 and row["phase"] == 1,
                  "Unexpected hardware failure: stop; do not automatically retry")
        row["failure_scope"] = "Bad camera capture; PP/NN did not run; retained as a failed sample"
    (folder/"result.json").write_text(json.dumps(row, indent=2), encoding="utf8")
    return row


def main():
    p = argparse.ArgumentParser(description="13 camera60: requires explicit user approval before this command may run.")
    p.add_argument("--board-approved", action="store_true", help="Only pass after user explicitly authorizes this board run")
    p.add_argument("--qualification", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--samples-per-pose", type=int, default=3, help=argparse.SUPPRESS)
    a = p.parse_args()
    b.require(a.board_approved, "Board work is on user hold. Obtain explicit approval before passing --board-approved.")
    out = a.out.resolve()
    b.require(out.is_relative_to((HERE/"board_tools").resolve()) and not out.exists(), "Use a new evidence folder")
    b.require(1 <= a.samples_per_pose <= 5, "Samples must be bounded")
    q = qualified(a.qualification.resolve())
    proof_path=HERE/"reports/SAME_SESSION_READBACK_PREPARATION_13.json"
    proof=json.loads(proof_path.read_text(encoding="utf8"))
    b.require(proof["passed"] and b.sha_file(Path(proof["helper"]))==proof["helper_sha256"] and
              b.sha_file(Path(proof["fake_test"]))==proof["fake_test_sha256"] and
              b.sha_file(Path(proof["fake_result"]))==proof["fake_result_sha256"] and
              json.loads(Path(proof["fake_result"]).read_text(encoding="utf8"))["phase"]=="PASS",
              "Same-session diagnostic script was modified or its fake test proof is missing")
    model = b.verify_models()["palm"]
    out.mkdir()
    report = dict(started_utc=b.utc(), phase="preflight", firmware_build_id=BUILD,
                  qualification=q, Flash_written=False, real_camera_capture_called=False,
                  model_receipts=[], poses=[], physical_panel_verified=False,
                  scope="Unlabelled 60second realcamera continuous observation; capture errors retained; no class accuracy claim")
    def save():
        (out/"result.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    save()
    lock=None; locked=False; claimed=False
    try:
        lock=b.LOCK.open("r+b"); lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1); locked=True
        b.require(not b.port_in_use(), "JTAG server belongs to another session")
        devices=b.enumerate_devices(None); report["devices"]=devices
        prior=b.STATUS.read_text(encoding="utf8")
        (out/"previous_board_status.md").write_text(prior,encoding="utf8")
        header=f"# Board resource lease\n\nUTC {b.utc()}; current owner: Vision5MP / DDR_HDMI_STARTUP_02 ; camera OSD same-session diagnostic 13; evidence {out}.\n\n"
        b.STATUS.write_text(header+prior,encoding="utf8");claimed=True;save()
        report["phase"]="SRAM_program_and_startup";save()
        cmd=[sys.executable,"-B","-X","utf8",str(HERE/"board_tools/program_window_sram_70.py"),
             "--bitstream",q["bitstream"]["path"],"--expected-sha256",q["bitstream"]["sha256"],
             "--lease-record",str(b.STATUS),"--out",str(out/"startup"),"--port",devices["uart"]["port"],
             "--cpu-hz","70000000","--expected-build",BUILD,"--startup-diagnostic-firmware",str(b.FW/"manifest.json"),
             "--pds-bin",str(b.PDS),"--seconds","45","--program-timeout","240"]
        report["startup_command"]=cmd;save()
        with (out/"startup_console.log").open("xb") as log:
            code=subprocess.call(cmd,cwd=HERE/"board_tools",stdout=log,stderr=subprocess.STDOUT,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        startup=json.loads((out/"startup/result.json").read_text(encoding="utf8"));report["startup"]=startup;save()
        b.require(code==0 and startup.get("pass") is True and startup.get("monitor_challenge",{}).get("valid") is True,
                  "SRAM startup proof failed")
        with b.Monitor.open(devices["uart"]["port"],out/"serial",timeout=20) as mon:
            report["identity"]=mon.ping(BUILD);b.check_identity(report["identity"]);save()
            report["phase"]="DDR_initial_test";save()
            report["DDR_tests"]=b.ddr_test(mon);save()
            report["phase"]="model_upload_and_readback";save()
            for name, asset in model["assets"].items():
                if name=="input_hwc_i8":continue
                receipt=b.upload(mon,asset["path"],asset["address"],asset["sha256"])
                report["model_receipts"].append(dict(name=name,**receipt));save()
                if len(report["model_receipts"])%16==0:
                    print(json.dumps(dict(stage="model_verified",count=len(report["model_receipts"])),),flush=True)
            b.require(len(report["model_receipts"])==317,"Incomplete model")
            _,raw=mon.request(22,0);video=b.decode_query(raw)
            frame,run,_=b.session_start(video,60000,1000)
            from continuous_all6_13 import run as run_continuous_all6
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
        if claimed:
            prior=b.STATUS.read_text(encoding="utf8")
            b.STATUS.write_text(f"# Board resource released / FPS_V2 已释放\n\nUTC {b.utc()}; camera OSD same-session diagnostic 13 lease released; phase {report['phase']}; evidence {out}.\n\n"+prior,encoding="utf8")
        if locked:lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
        if lock is not None:lock.close()
        report["finished_utc"]=b.utc();save()
    print(json.dumps(dict(stage="session_finished",phase=report["phase"],
                         completed_frames=report.get("continuous",{}).get("completed_frames",0))),flush=True)
    return 0 if report["phase"]=="complete" else 1


if __name__=="__main__":
    raise SystemExit(main())
