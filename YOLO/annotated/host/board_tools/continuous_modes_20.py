# 架构导读：continuous_modes_20。
# 主机侧工程工具，管理本文件定义的数据解析、检查或运行流程。
"""One ARM/STOP live-preview observation for14; never starts on import.

Firmware owns rejected-frame recovery. Host only observes and issues STOP.
"""
import json
import struct
import time
import board_common as b
from capture_stats_13 import decode as decode_stats
from cmos2_protocol import preview_snapshot
from frame_pool_protocol import pool_snapshot

# 维护本地状态/计算值：NAMES = ["fist", "one", "peace", "three", "four", "palm"]。
NAMES = ["fist", "one", "peace", "three", "four", "palm"]
# 维护本地状态/计算值：LABELS = ["握拳", "单指", "V字", "三指", "四指", "张掌"]。
LABELS = ["握拳", "单指", "V字", "三指", "四指", "张掌"]


# 接口 run，显式输入字段：mon, model, report, save, out, query, seconds, mode。
# 本函数调用入口包括 folder.mkdir, dict, save, mon.request, (folder / 'pre_arm.bin').write_bytes。
def run(mon, model, report, save, out, query, seconds=60, mode="preview"):
    # 按条件 mode != 'preview' 选择后续流程，保留原有异常和退出分支。
    if mode != "preview": raise ValueError("Candidate20 acceptance uses independent V3 preview")
    # 维护本地状态/计算值：folder = out / ("continuous60_"+mode)。
    folder = out / ("continuous60_"+mode)
    folder.mkdir()
    # 维护本地状态/计算值：c = dict(requested_seconds=seconds, ARM_commands=0, STOP_commands=0,。
    c = dict(requested_seconds=seconds, ARM_commands=0, STOP_commands=0,
             host_per_frame_STARTs=0, outputs=[], observed_errors=[],
             missed_prediction_frames=0, ground_truth="Unlabelled; not accuracy")
    # 维护本地状态/计算值：c["mode"]=mode。
    c["mode"]=mode
    # 维护本地状态/计算值：report["continuous_"+mode] = c。
    report["continuous_"+mode] = c
    # 维护本地状态/计算值：report["phase"] = "continuous_preflight"。
    report["phase"] = "continuous_preflight"
    save()
    # 维护本地状态/计算值：_, raw = mon.request(26, 0xffffffff)。
    _, raw = mon.request(26, 0xffffffff)
    (folder/"pre_arm.bin").write_bytes(raw)
    b.require(not b.continuous_snapshot(raw)["active"], "Other continuous owner")
    # 维护本地状态/计算值：_, raw = mon.request(26,0xfffffffc)。
    _, raw = mon.request(26,0xfffffffc)
    (folder/"pool_before.bin").write_bytes(raw)
    # 维护本地状态/计算值：pool_before=pool_snapshot(raw)。
    pool_before=pool_snapshot(raw)
    mon.request(17, 1)
    mon.request(18, 1)

    # 接口 counters，显式输入字段：suffix。
    # 本函数调用入口包括 mon.request, (folder / f'{name}_{suffix}.bin').write_bytes, decode。
    def counters(suffix):
        # 维护本地状态/计算值：result = {}。
        result = {}
        # 迭代/等待条件：[(17, 's3', b.s3_counts), (27, 'window', b.decode_window), (29, 'concat', b.decode_concat), (18, 'profile',...；退出由原循环条件及显式 break/异常决定。
        for op, name, decode in [(17,"s3",b.s3_counts),(27,"window",b.decode_window),
                                (29,"concat",b.decode_concat),(18,"profile",b.decode_profile)]:
            # 维护本地状态/计算值：_, data = mon.request(op, 0)。
            _, data = mon.request(op, 0)
            (folder/f"{name}_{suffix}.bin").write_bytes(data)
            # 维护本地状态/计算值：result[name] = decode(data)。
            result[name] = decode(data)
        # 向调用方返回本步骤结果：result。
        return result

    # 维护本地状态/计算值：before = counters("before")。
    before = counters("before")
    # 维护本地状态/计算值：frame, run_id, fb = b.session_start(query, 90000, 100000)。
    frame, run_id, fb = b.session_start(query, 90000, 100000)
    # 维护本地状态/计算值：words = list(struct.unpack("<40I", b.make_config(model["package"],frame,fb,run_id,camera=True,live_preview=(mode...。
    words = list(struct.unpack("<40I", b.make_config(model["package"],frame,fb,run_id,camera=True,live_preview=(mode=="preview"))))
    # 维护本地状态/计算值：words[1] = 2 if mode=="v2" else 1。
    words[1] = 2 if mode=="v2" else 1
    # 维护本地状态/计算值：words[18] = 0xffffffff。
    words[18] = 0xffffffff
    # 维护本地状态/计算值：cfg = struct.pack("<40I",*words)。
    cfg = struct.pack("<40I",*words)
    (folder/"config.bin").write_bytes(cfg)
    mon.write_memory(b.CONFIG_ADDRESS,cfg)
    # 维护本地状态/计算值：armed = False。
    armed = False
    # 维护本地状态/计算值：seen = 0。
    seen = 0
    # 维护本地状态/计算值：snapshots = 0。
    snapshots = 0
    # 维护本地状态/计算值：last_bad = None。
    last_bad = None
    # 维护本地状态/计算值：began = time.monotonic()。
    began = time.monotonic()

    # 接口 observe，显式输入字段：raw。
    # 本函数调用入口包括 b.continuous_snapshot, (folder / f'snapshot_{snapshots:04d}.bin').write_bytes, b.require, save, bool。
    def observe(raw):
        nonlocal seen, snapshots, last_bad
        # 维护本地状态/计算值：snap = b.continuous_snapshot(raw)。
        snap = b.continuous_snapshot(raw)
        # 维护本地状态/计算值：snapshots += 1。
        snapshots += 1
        (folder/f"snapshot_{snapshots:04d}.bin").write_bytes(raw)
        # 维护本地状态/计算值：n, row = snap["completed"], snap["last_run"]。
        n, row = snap["completed"], snap["last_run"]
        b.require(n >= seen, "Completed counter decreased")
        # 按条件 n > seen 选择后续流程，保留原有异常和退出分支。
        if n > seen:
            # 按条件 row is not None and (not snap['last_status']) and row['pass_result'] 选择后续流程，保留原有异常和退出分支。
            if row is not None and not snap["last_status"] and row["pass_result"]:
                b.require(row["source"]=="real CMOS2 capture" and
                          row["live_preview"] == (mode=="preview") and row["pipeline_v2"] == (mode=="v2") and
                          row["same_source_frame"] == (mode=="v2") and row["frame_id"] >= frame+n-1 and
                          row["run_id"]-run_id==row["frame_id"]-frame,
                          "Frame/run/source mismatch")
                b.require(row.get("pipeline_v3") and not row["preview_delivery_confirmed"],
                          "Expected asynchronous V3 inference completion")
                # 维护本地状态/计算值：selected = bool(row.pop("palm_count"))。
                selected = bool(row.pop("palm_count"))
                # 维护本地状态/计算值：cls = row["class_id"] if selected else None。
                cls = row["class_id"] if selected else None
                b.require(cls is None or (cls<6 and 0<row["score_q15"]<=32768),
                          "Invalid selected class or confidence")
                # 维护本地状态/计算值：c["missed_prediction_frames"] += n-seen-1。
                c["missed_prediction_frames"] += n-seen-1
                # 维护本地状态/计算值：event = dict(completed=n,host_elapsed_seconds=time.monotonic()-began,。
                event = dict(completed=n,host_elapsed_seconds=time.monotonic()-began,
                             class_id=cls,class_name=NAMES[cls] if selected else None,
                             confidence=row["score_q15"]/32768 if selected else None,workflow=row)
                c["outputs"].append(event)
                # 维护本地状态/计算值：text=f"[{event['host_elapsed_seconds']:.2f}s] 帧{row['frame_id']}: "+(LABELS[cls] if selected else "未检出")。
                text=f"[{event['host_elapsed_seconds']:.2f}s] 帧{row['frame_id']}: "+(LABELS[cls] if selected else "未检出")
                # 按条件 selected 选择后续流程，保留原有异常和退出分支。
                if selected:text+=f" {event['confidence']*100:.2f}%"
                # 资源上下文：with (folder/"识别结果.txt").open("a",encoding="utf8") as log:log.write(text+"\n")；离开上下文时执行对应清理约定。
                with (folder/"识别结果.txt").open("a",encoding="utf8") as log:log.write(text+"\n")
                print(text,flush=True)
            else:
                # 维护本地状态/计算值：c["missed_prediction_frames"] += n-seen。
                c["missed_prediction_frames"] += n-seen
            # 维护本地状态/计算值：seen=n。
            seen=n
        # 按条件 snap['last_status'] 选择后续流程，保留原有异常和退出分支。
        if snap["last_status"]:
            # 维护本地状态/计算值：key=(row["frame_id"],row["run_id"]) if row else None。
            key=(row["frame_id"],row["run_id"]) if row else None
            # 按条件 key != last_bad 选择后续流程，保留原有异常和退出分支。
            if key!=last_bad:
                c["observed_errors"].append(dict(status=snap["last_status"],workflow=row))
                print(json.dumps(dict(stage="rejected_frame",status=snap["last_status"],frame=key)),flush=True)
                # 维护本地状态/计算值：last_bad=key。
                last_bad=key
            b.require(snap["last_status"]==13 and row is not None and row["phase"]==1,
                      "Unexpected pipeline error; stop without rearming")
        save()
        # 向调用方返回本步骤结果：snap。
        return snap

    # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
    try:
        # 维护本地状态/计算值：c["ARM_commands"]=1。
        c["ARM_commands"]=1
        # 维护本地状态/计算值：armed=True。
        armed=True
        mon.request(26,b.CONFIG_ADDRESS)
        # 维护本地状态/计算值：c["started_utc"]=b.utc()。
        c["started_utc"]=b.utc()
        # 维护本地状态/计算值：report["phase"]="camera_continuous60"。
        report["phase"]="camera_continuous60"
        # 维护本地状态/计算值：report["real_camera_capture_called"]=True。
        report["real_camera_capture_called"]=True
        save()
        print(json.dumps(dict(stage="continuous_started",mode=mode,seconds=seconds),ensure_ascii=False),flush=True)
        # 维护本地状态/计算值：deadline=began+seconds。
        deadline=began+seconds
        # 迭代/等待条件：time.monotonic() < deadline；退出由原循环条件及显式 break/异常决定。
        while time.monotonic()<deadline:
            time.sleep(.05)
            # 维护本地状态/计算值：_,raw=mon.request(26,0xffffffff)。
            _,raw=mon.request(26,0xffffffff)
            # 维护本地状态/计算值：snap=observe(raw)。
            snap=observe(raw)
            b.require(snap["active"],"Firmware stopped before requested observation ended")
        # 维护本地状态/计算值：c["STOP_commands"]=1。
        c["STOP_commands"]=1
        mon.request(26,0)
        # 维护本地状态/计算值：armed=False。
        armed=False
        # 维护本地状态/计算值：c["actual_ARM_to_STOP_host_seconds"]=time.monotonic()-began。
        c["actual_ARM_to_STOP_host_seconds"]=time.monotonic()-began
        # 维护本地状态/计算值：_,raw=mon.request(26,0xffffffff)。
        _,raw=mon.request(26,0xffffffff)
        # 维护本地状态/计算值：final=observe(raw)。
        final=observe(raw)
        b.require(not final["active"],"STOP not confirmed")
        c["STOP_confirmed"]=True
        _,raw=mon.request(26,0xfffffffe)
        (folder/"capture_stats.bin").write_bytes(raw)
        c["capture_stats"]=diag=decode_stats(raw)
        # 按条件 mode == 'preview' 选择后续流程，保留原有异常和退出分支。
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
        c["timestamp_scope"]="V3 replies prove inference completion and queued metadata, not per-inference HDMI delivery. Capture, inference and preview have different frame identities; phase times overlap. Throughput uses completed frames / full ARM-to-STOP observation."
        n=final["completed"]
        b.require(n>0 and scheduler["inference_inputs"]==n and
                  scheduler["overlay_acknowledged_frame"]==final["last_run"]["frame_id"],
                  "Final inference result or overlay acknowledgement is missing")
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
        c["camera_error_free"]=diag["capture_rejected"]==0 and scheduler["bad_captures"]==0
        c["raw_capture_generation_delta"]=scheduler["capture_generation"]-pool_before["capture_generation"]
        c["acknowledged_preview_frame_rate"]=c["preview_stats"]["vblank_acknowledgements"]/c["actual_ARM_to_STOP_host_seconds"]
        c["final_overlay_delivery_acknowledged"]=True
        c["observation_complete"]=True
        c["prediction_counts"]={name:sum(x["class_name"]==name for x in c["outputs"]) for name in NAMES}
        c["no_detection_frames"]=sum(x["class_id"] is None for x in c["outputs"])
        c["finished_utc"]=b.utc()
        save()
    finally:
        # 按条件 armed and (not mon.failed) 选择后续流程，保留原有异常和退出分支。
        if armed and not mon.failed:
            c["STOP_commands"]+=1
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:
                mon.request(26,0)
                c["cleanup_STOP_ack"]=True
            except Exception as exc:c["cleanup_STOP_error"]=str(exc)
        # 按条件 armed and mon.failed 选择后续流程，保留原有异常和退出分支。
        if armed and mon.failed:c["STOP_state_unknown"]=True
        save()
