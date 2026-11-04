"""One ARM/STOP unlabelled observation for12; never starts on import.

Firmware owns rejected-frame recovery. Host only observes and issues STOP.
"""
import json
import struct
import time
import board_common as b
from capture_stats_13 import decode as decode_stats

NAMES = ["fist", "one", "peace", "three", "four", "palm"]
LABELS = ["握拳", "单指", "V字", "三指", "四指", "张掌"]


def run(mon, model, report, save, out, query, seconds=60):
    folder = out / "continuous60"
    folder.mkdir()
    c = dict(requested_seconds=seconds, ARM_commands=0, STOP_commands=0,
             host_per_frame_STARTs=0, outputs=[], observed_errors=[],
             missed_prediction_frames=0, ground_truth="Unlabelled; not accuracy")
    report["continuous"] = c
    report["phase"] = "continuous_preflight"
    save()
    _, raw = mon.request(26, 0xffffffff)
    (folder/"pre_arm.bin").write_bytes(raw)
    b.require(not b.continuous_snapshot(raw)["active"], "Other continuous owner")
    mon.request(17, 1)
    mon.request(18, 1)

    def counters(suffix):
        result = {}
        for op, name, decode in [(17,"s3",b.s3_counts),(27,"window",b.decode_window),
                                (29,"concat",b.decode_concat),(18,"profile",b.decode_profile)]:
            _, data = mon.request(op, 0)
            (folder/f"{name}_{suffix}.bin").write_bytes(data)
            result[name] = decode(data)
        return result

    before = counters("before")
    frame, run_id, fb = b.session_start(query, 90000, 100000)
    words = list(struct.unpack("<40I", b.make_config(model["package"],frame,fb,run_id,camera=True)))
    words[18] = 0xffffffff
    cfg = struct.pack("<40I",*words)
    (folder/"config.bin").write_bytes(cfg)
    mon.write_memory(b.CONFIG_ADDRESS,cfg)
    armed = False
    seen = 0
    snapshots = 0
    last_bad = None
    began = time.monotonic()

    def observe(raw):
        nonlocal seen, snapshots, last_bad
        snap = b.continuous_snapshot(raw)
        snapshots += 1
        (folder/f"snapshot_{snapshots:04d}.bin").write_bytes(raw)
        n, row = snap["completed"], snap["last_run"]
        b.require(n >= seen, "Completed counter decreased")
        if n > seen:
            if row is not None and not snap["last_status"] and row["pass_result"]:
                b.require(row["source"]=="real CMOS2 capture" and
                          row["frame_id"] >= frame+n-1 and
                          row["run_id"]-run_id==row["frame_id"]-frame,
                          "Frame/run/source mismatch")
                selected = bool(row.pop("palm_count"))
                cls = row["class_id"] if selected else None
                b.require(cls is None or (cls<6 and 0<row["score_q15"]<=32768),
                          "Invalid selected class or confidence")
                c["missed_prediction_frames"] += n-seen-1
                event = dict(completed=n,host_elapsed_seconds=time.monotonic()-began,
                             class_id=cls,class_name=NAMES[cls] if selected else None,
                             confidence=row["score_q15"]/32768 if selected else None,workflow=row)
                c["outputs"].append(event)
                text=f"[{event['host_elapsed_seconds']:.2f}s] 帧{row['frame_id']}: "+(LABELS[cls] if selected else "未检出")
                if selected:text+=f" {event['confidence']*100:.2f}%"
                with (folder/"识别结果.txt").open("a",encoding="utf8") as log:log.write(text+"\n")
                print(text,flush=True)
            else:
                c["missed_prediction_frames"] += n-seen
            seen=n
        if snap["last_status"]:
            key=(row["frame_id"],row["run_id"]) if row else None
            if key!=last_bad:
                c["observed_errors"].append(dict(status=snap["last_status"],workflow=row))
                print(json.dumps(dict(stage="rejected_frame",status=snap["last_status"],frame=key)),flush=True)
                last_bad=key
            b.require(snap["last_status"]==13 and row is not None and row["phase"]==1,
                      "Unexpected pipeline error; stop without rearming")
        save()
        return snap

    try:
        c["ARM_commands"]=1
        armed=True
        mon.request(26,b.CONFIG_ADDRESS)
        c["started_utc"]=b.utc()
        report["phase"]="camera_continuous60"
        report["real_camera_capture_called"]=True
        save()
        print(json.dumps(dict(stage="continuous_started",seconds=seconds),ensure_ascii=False),flush=True)
        deadline=began+seconds
        while time.monotonic()<deadline:
            time.sleep(.05)
            _,raw=mon.request(26,0xffffffff)
            snap=observe(raw)
            b.require(snap["active"],"Firmware stopped before requested observation ended")
        c["STOP_commands"]=1
        mon.request(26,0)
        armed=False
        c["actual_ARM_to_STOP_host_seconds"]=time.monotonic()-began
        _,raw=mon.request(26,0xffffffff)
        final=observe(raw)
        b.require(not final["active"],"STOP not confirmed")
        c["STOP_confirmed"]=True
        _,raw=mon.request(26,0xfffffffe)
        (folder/"capture_stats.bin").write_bytes(raw)
        c["capture_stats"]=diag=decode_stats(raw)
        n=final["completed"]
        b.require(diag["completed"]==n and not diag["active"] and not diag["fatal"],"Final diagnostics differ or fatal error")
        b.require(diag["attempted"]==n+diag["capture_rejected"] and
                  diag["capture_recovered"]==diag["capture_rejected"],"Attempt/recovery counts differ")
        after=counters("after")
        c["aggregate_counters"]=after
        c["Window_delta"]=b.window_delta_05(before["window"],after["window"],model["window_expected"],n)
        c["Concat_delta"]=b.concat_delta(before["concat"],after["concat"],True,n)
        b.require((after["profile"]["ops"],after["profile"]["batches"],after["profile"]["errors"])==(204*n,n,0),"Graph counts")
        b.require((after["s3"]["jobs"],after["s3"]["fallbacks"],after["s3"]["LUT_jobs"])==(60*n,0,57*n),"S3 counts")
        c["completed_frames"]=n
        c["completed_frame_rate_over_full_observation"]=n/c["actual_ARM_to_STOP_host_seconds"]
        c["camera_error_free"]=diag["capture_rejected"]==0
        c["observation_complete"]=True
        c["prediction_counts"]={name:sum(x["class_name"]==name for x in c["outputs"]) for name in NAMES}
        c["no_detection_frames"]=sum(x["class_id"] is None for x in c["outputs"])
        c["finished_utc"]=b.utc()
        save()
    finally:
        if armed and not mon.failed:
            c["STOP_commands"]+=1
            try:
                mon.request(26,0)
                c["cleanup_STOP_ack"]=True
            except Exception as exc:c["cleanup_STOP_error"]=str(exc)
        if armed and mon.failed:c["STOP_state_unknown"]=True
        save()
