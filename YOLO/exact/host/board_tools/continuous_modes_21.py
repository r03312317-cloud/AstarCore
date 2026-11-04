"""One ARM/STOP live-preview observation for graph21; never starts on import.

Firmware owns rejected-frame recovery. Host only observes and issues STOP.
"""
import json
import struct
import time
import board_common as b
from capture_stats_13 import decode as decode_stats
from cmos2_protocol import preview_snapshot
from frame_pool_protocol import pool_snapshot
from graph_executor_protocol import decode as graph_snapshot
from completion_fps import calculate as completion_fps

NAMES = ["fist", "one", "peace", "three", "four", "palm"]
LABELS = ["握拳", "单指", "V字", "三指", "四指", "张掌"]


def run(mon, model, report, save, out, query, seconds=60, mode="preview"):
    if mode != "preview": raise ValueError("Candidate21 acceptance uses independent V3 preview")
    unbounded = seconds is None
    folder = out / (("continuous_unbounded_" if unbounded else "continuous60_")+mode)
    folder.mkdir()
    c = dict(requested_seconds=seconds, ARM_commands=0, STOP_commands=0,
             host_per_frame_STARTs=0, outputs=[], observed_errors=[],
             missed_prediction_frames=0, ground_truth="Unlabelled; not accuracy")
    c["mode"]=mode
    c["time_limit_seconds"]=seconds
    c["stop_request_file"]=str(folder/"STOP_REQUESTED") if unbounded else None
    c["running_prediction_counts"]={name:0 for name in NAMES}
    c["running_no_detection_frames"]=0
    c["completion_samples"]=[]
    c["abort_policy"]={"pixel_loss_ratio":0.10,"recognition_idle_timeout":None}
    report["continuous_"+mode] = c
    report["phase"] = "continuous_preflight"
    save()
    _, raw = mon.request(26, 0xffffffff)
    (folder/"pre_arm.bin").write_bytes(raw)
    b.require(not b.continuous_snapshot(raw)["active"], "Other continuous owner")
    _, raw = mon.request(26,0xfffffffc)
    (folder/"pool_before.bin").write_bytes(raw)
    pool_before=pool_snapshot(raw)
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

    def graph_status(suffix):
        _, raw = mon.request(26,0xfffffffb)
        (folder/f"graph_{suffix}.bin").write_bytes(raw)
        value=graph_snapshot(raw)
        c["graph_"+suffix]=value;save()
        return value

    graph_before=graph_status("before")
    b.require(not graph_before["busy"] and not graph_before["poison"],"GRAPH_EXECUTOR requires common reset before starting")
    before = counters("before")
    frame, run_id, fb = b.session_start(query, 90000, 100000)
    words = list(struct.unpack("<40I", b.make_config(model["package"],frame,fb,run_id,camera=True,live_preview=(mode=="preview"))))
    words[1] = 2 if mode=="v2" else 1
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
        (folder/("snapshot_latest.bin" if unbounded else f"snapshot_{snapshots:04d}.bin")).write_bytes(raw)
        n, row = snap["completed"], snap["last_run"]
        b.require(n >= seen, "Completed counter decreased")
        if n > seen:
            if row is not None and not snap["last_status"] and row["pass_result"]:
                b.require(row["source"]=="real CMOS2 capture" and
                          row["live_preview"] == (mode=="preview") and row["pipeline_v2"] == (mode=="v2") and
                          row["same_source_frame"] == (mode=="v2") and row["frame_id"] >= frame+n-1 and
                          row["run_id"]-run_id==row["frame_id"]-frame,
                          "Frame/run/source mismatch")
                b.require(row.get("pipeline_v3") and not row["preview_delivery_confirmed"],
                          "Expected asynchronous V3 inference completion")
                selected = bool(row.pop("palm_count"))
                cls = row["class_id"] if selected else None
                b.require(cls is None or (cls<6 and 0<row["score_q15"]<=32768),
                          "Invalid selected class or confidence")
                c["missed_prediction_frames"] += n-seen-1
                event = dict(completed=n,host_elapsed_seconds=time.monotonic()-began,
                             class_id=cls,class_name=NAMES[cls] if selected else None,
                             confidence=row["score_q15"]/32768 if selected else None,workflow=row)
                c["outputs"].append(event)
                sample=dict(completed=n,TR=row["timestamps_CPU64"]["TR"],
                            cpu_hz=row["cpu_hz"],generation=row["inference_source_generation"],
                            frame_id=row["frame_id"],run_id=row["run_id"])
                c["completion_samples"].append(sample)
                c["completion_interval_fps"]=completion_fps(c["completion_samples"])
                with (folder/"completion_samples.jsonl").open("a",encoding="utf8") as log:
                    log.write(json.dumps(sample)+"\n")
                with (folder/"all_completed_frames.jsonl").open("a",encoding="utf8") as log:
                    log.write(json.dumps(event,ensure_ascii=False)+"\n")
                if selected:c["running_prediction_counts"][NAMES[cls]]+=1
                else:c["running_no_detection_frames"]+=1
                if unbounded:
                    with (folder/"completed_frames.jsonl").open("a",encoding="utf8") as log:log.write(json.dumps(event,ensure_ascii=False)+"\n")
                    c["outputs"]=c["outputs"][-16:]
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
        elapsed=time.monotonic()-began
        c["current_completed_frames"]=n
        c["current_host_observation_seconds"]=elapsed
        c["current_completed_frame_rate"]=c.get("completion_interval_fps",{}).get("fps")
        c["firmware_active"]=snap["active"]
        c["last_observed_utc"]=b.utc()
        save()
        return snap

    try:
        c["ARM_commands"]=1
        armed=True
        mon.request(26,b.CONFIG_ADDRESS)
        c["started_utc"]=b.utc()
        report["phase"]="camera_continuous_unbounded" if unbounded else "camera_continuous60"
        report["real_camera_capture_called"]=True
        save()
        print(json.dumps(dict(stage="continuous_started",mode=mode,seconds=seconds),ensure_ascii=False),flush=True)
        deadline=None if unbounded else began+seconds
        while (deadline is None or time.monotonic()<deadline) and not (unbounded and (folder/"STOP_REQUESTED").exists()):
            time.sleep(.05)
            _,raw=mon.request(26,0xffffffff)
            snap=observe(raw)
            b.require(snap["active"],"Firmware stopped before requested observation ended")
        g=graph_status("before_stop")
        b.require(not g["poison"],"GRAPH_EXECUTOR fault: common reset required; keep memory ownership quarantined")
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
        if mode=="preview":
            _,raw=mon.request(26,0xfffffffd)
            (folder/"preview_stats.bin").write_bytes(raw)
            c["preview_stats"]=preview_snapshot(raw)
            b.require(not c["preview_stats"]["fault"] and
                      c["preview_stats"]["vblank_acknowledgements"]>0,
                      "No acknowledged preview frames or preview fault")
        _,raw=mon.request(26,0xfffffffc)
        (folder/"scheduler_stats.bin").write_bytes(raw)
        c["pool_stats"]=scheduler=pool_snapshot(raw)
        b.require(scheduler["initialized"] and scheduler["capture_slot"]==3 and scheduler["resize_phase"]==0 and
                  not scheduler["fault"] and scheduler["resize_started"]==scheduler["resize_completed"],
                  "STOP left outstanding camera/resize ownership or scheduler fault")
        b.require(not scheduler["protocol_errors"] and not scheduler["metadata_pending"] and
                  scheduler["metadata_published"]==scheduler["metadata_acknowledged"] and
                  all(s["state"]!=1 and not s["readers"] for s in scheduler["slots"]),
                  "STOP left a raw reader, camera writer or overlay unacknowledged")
        c["timestamp_scope"]="Primary FPS is completed-count delta divided by board CPU64 TR timestamp delta; asynchronous preview delivery and startup are excluded. ARM-to-STOP host rate is auxiliary only."
        n=final["completed"]
        b.require(n>0 and scheduler["inference_inputs"]==n and
                  scheduler["overlay_acknowledged_frame"]==final["last_run"]["frame_id"],
                  "Final inference result or overlay acknowledgement is missing")
        b.require(diag["completed"]==n and not diag["active"] and not diag["fatal"],"Final diagnostics differ or fatal error")
        b.require(diag["attempted"]==n+diag["capture_rejected"] and
                  diag["capture_recovered"]==diag["capture_rejected"],"Attempt/recovery counts differ")
        graph_after=graph_status("after")
        b.require(not graph_after["busy"] and not graph_after["poison"] and graph_after["done"] and
                  graph_after["program_valid"] and graph_after["completed_nodes"]==204 and
                  graph_after["starts"]-graph_before["starts"]==n and
                  graph_after["finishes"]-graph_before["finishes"]==n,
                  "Hardware graph completion differs from firmware frame count")
        after=counters("after")
        c["aggregate_counters"]=after
        c["Window_delta"]=b.window_delta_05(before["window"],after["window"],model["window_expected"],n)
        c["Concat_delta"]=b.concat_delta(before["concat"],after["concat"],True,n)
        b.require((after["profile"]["ops"],after["profile"]["batches"],after["profile"]["errors"])==(204*n,n,0),"Graph counts")
        b.require((after["s3"]["jobs"],after["s3"]["fallbacks"],after["s3"]["LUT_jobs"])==(60*n,0,57*n),"S3 counts")
        c["completed_frames"]=n
        c["completed_frame_rate_over_full_observation"]=n/c["actual_ARM_to_STOP_host_seconds"]
        c["camera_error_free"]=diag["capture_rejected"]==0 and scheduler["bad_captures"]==0
        c["raw_capture_generation_delta"]=scheduler["capture_generation"]-pool_before["capture_generation"]
        c["acknowledged_preview_frame_rate"]=c["preview_stats"]["vblank_acknowledgements"]/c["actual_ARM_to_STOP_host_seconds"]
        c["final_overlay_delivery_acknowledged"]=True
        c["observation_complete"]=True
        c["prediction_counts"]=dict(c["running_prediction_counts"])
        c["no_detection_frames"]=c["running_no_detection_frames"]
        c["finished_utc"]=b.utc()
        save()
    finally:
        if armed and not mon.failed:
            try:
                g=graph_status("cleanup")
                if g["poison"]:
                    c["common_reset_required"]=True
                    c["STOP_skipped_due_to_quarantined_hardware"]=True
                else:
                    c["STOP_commands"]+=1
                    mon.request(26,0)
                    c["cleanup_STOP_ack"]=True
            except Exception as exc:c["cleanup_STOP_error"]=str(exc)
        if armed and mon.failed:c["STOP_state_unknown"]=True
        save()
