# 架构导读：frame_pool_protocol。
# 解码三槽帧池、generation、租约及 V3 推理来源信息。
"""V3 inference completion is distinct from asynchronous preview delivery."""
import struct
TIMES=('T0','TP0','TP1','TG0','TG1','TB','TF','TR','TC','TH_TX_INPUT','TE_TX_INPUT')
# 接口 decode_v3，显式输入字段：raw, status, image_x, image_y。
# 本函数调用入口包括 struct.unpack_from, bool, dict, len, ValueError。
def decode_v3(raw,status,image_x,image_y):
    # 按条件 len(raw) != 288 选择后续流程，保留原有异常和退出分支。
    if len(raw)!=288:raise ValueError('V3 workflow needs 288 bytes')
    w=struct.unpack_from('<24I',raw);t=struct.unpack_from('<11Q',raw,96)
    tail=struct.unpack_from('<11I',raw,184);capture=struct.unpack_from('<Q6I',raw,256)
    mode,preview_raw,inference_raw,generation,overlay_frame=struct.unpack_from('<5I',raw,228)
    ready=bool(tail[10]&1);camera=bool(tail[10]&16)
    # 按条件 w[:2] != (827732547, 3) or mode != 1 or w[13] != 70000000 or (not camera) or (w[15] != 1) 选择后续流程，保留原有异常和退出分支。
    if w[:2]!=(0x31563243,3) or mode!=1 or w[13]!=70000000 or not camera or w[15]!=1:raise ValueError('V3 identity/clock/source')
    # 按条件 tail[10] & ~49 or not tail[10] & 32 or any(t[8:]) 选择后续流程，保留原有异常和退出分支。
    if tail[10]&~49 or not tail[10]&32 or any(t[8:]):raise ValueError('V3 must not claim per-inference HDMI delivery')
    # 按条件 capture[5:] != (1, 462400) or tail[9] != 204 or tail[8] not in (3087007744, 3120562176, 3154116608, 3187671... 选择后续流程，保留原有异常和退出分支。
    if capture[5:]!=(1,462400) or tail[9]!=204 or tail[8] not in (0xb8000000,0xba000000,0xbc000000,0xbe000000):raise ValueError('V3 geometry/Graph204 contract')
    # 按条件 ready 选择后续流程，保留原有异常和退出分支。
    if ready:
        chronology=[t[i] for i in (0,1,2,3,4,5,7)]
        # 按条件 status or w[3] or w[2] != 9 or (not t[0]) or any((a > b for a, b in zip(chronology, chronology[1:]))) 选择后续流程，保留原有异常和退出分支。
        if status or w[3] or w[2]!=9 or not t[0] or any(a>b for a,b in zip(chronology,chronology[1:])):raise ValueError('V3 inference completion contradicts status or chronology')
        # 按条件 capture[0] != t[1] or not capture[1] & 8 or capture[1] & 2 or (capture[2:5] != (921600, 921600, 0)) 选择后续流程，保留原有异常和退出分支。
        if capture[0]!=t[1] or not capture[1]&8 or capture[1]&2 or capture[2:5]!=(921600,921600,0):raise ValueError('V3 raw frame lacks retired, complete capture')
        # 按条件 inference_raw not in (2164260864, 2166358016, 2168455168) or not generation or overlay_frame != w[4] 选择后续流程，保留原有异常和退出分支。
        if inference_raw not in (0x81000000,0x81200000,0x81400000) or not generation or overlay_frame!=w[4]:raise ValueError('V3 inference provenance')
        # 按条件 preview_raw not in (0, 2164260864, 2166358016, 2168455168) or w[5] not in (0, 2183135232, 2184183808) 选择后续流程，保留原有异常和退出分支。
        if preview_raw not in (0,0x81000000,0x81200000,0x81400000) or w[5] not in (0,0x82200000,0x82300000):raise ValueError('V3 preview buffer')
    box=[w[8]&65535,w[8]>>16,w[9]&65535,w[9]>>16]
    # 按条件 w[7] > 1 or (not w[7] and any(box)) or (w[7] and (not (0 <= box[0] < box[2] <= 680 and 0 <= box[1] < box[3]... 选择后续流程，保留原有异常和退出分支。
    if w[7]>1 or (not w[7] and any(box)) or (w[7] and not (0<=box[0]<box[2]<=680 and 0<=box[1]<box[3]<=340)):raise ValueError('V3 selected detection geometry')
    hz=w[13]
    return dict(pass_result=not status and ready,inference_pass=not status and ready,status=status,error=w[3],phase=w[2],
        frame_id=w[4],run_id=w[14],framebuffer=hex(w[5]),source='real CMOS2 capture',live_preview=True,pipeline_v2=False,pipeline_v3=True,
        pipeline_flags=mode,pipeline_from_prefetch=False,next_capture_raw=None,display_source_raw=hex(preview_raw),inference_source_raw=hex(inference_raw),
        inference_source_generation=generation,preview_sequence=None,overlay_inference_frame=overlay_frame,same_source_frame=False,
        selected_capture_channel=1,capture_sensor_pixels=capture[3],capture_writer_pixels=capture[2],capture_errors=capture[4],
        NMS_count=w[6],palm_count=w[7],bbox_compact_xyxy=box,bbox_HDMI_xyxy=[box[0]+image_x,box[1]+image_y,box[2]+image_x,box[3]+image_y] if w[7] else [0]*4,
        score_q15=w[10],class_id=w[11],cpu_hz=hz,timestamps_CPU64=dict(zip(TIMES,t)),capture_end_CPU64=capture[0],
        capture_seconds=(t[1]-t[0])/hz if ready else None,preprocess_seconds=(t[2]-t[1])/hz if ready else None,
        graph_seconds=(t[4]-t[3])/hz if ready else None,NMS_seconds=(t[5]-t[4])/hz if ready else None,
        display_and_commit_seconds=None,START_to_READY_seconds=(t[7]-t[0])/hz if ready else None,
        START_to_first_TX_input_seconds=None,START_to_complete_TX_input_seconds=None,
        accepted_bytes=tail[0],committed_bytes=tail[1],underflow_before=None,underflow_after=w[19],video_fault=w[17],
        graph_ops=tail[9],graph_flags=hex(tail[8]),window_requested=bool(tail[8]&0x04000000),concat_requested=bool(tail[8]&0x02000000),
        endpoint_scope='Inference result queued for independent preview; no wait for preview drain, vblank or HDMI frame completion.',
        physical_panel_verified=False,preview_delivery_confirmed=False,
        preprocess_scope='Capture completion to preprocessing completion includes input age and IMG availability wait.')

# 接口 pool_snapshot，显式输入字段：raw。
# 本函数调用入口包括 struct.unpack_from, any, dict, len, ValueError。
def pool_snapshot(raw):
    # 按条件 len(raw) != 144 选择后续流程，保留原有异常和退出分支。
    if len(raw)!=144:raise ValueError('Frame pool status needs 144 bytes')
    w=struct.unpack_from('<8I2Q24I',raw)
    # 按条件 w[:2] != (808603718, 1) or w[13] != 70000000 or w[10] > 3 or (w[11] > 2) 选择后续流程，保留原有异常和退出分支。
    if w[:2]!=(0x30325046,1) or w[13]!=70000000 or w[10]>3 or w[11]>2:raise ValueError('Frame pool ABI/clock/state')
    slots=[dict(base=hex(w[22+i*4]),state=w[23+i*4],readers=w[24+i*4],generation=w[25+i*4]) for i in range(3)]
    initialized=any(int(s['base'],16) for s in slots)
    # 按条件 not initialized 选择后续流程，保留原有异常和退出分支。
    if not initialized:
        # 按条件 any((value for index, value in enumerate(w) if index not in (0, 1, 13))) 选择后续流程，保留原有异常和退出分支。
        if any(value for index,value in enumerate(w) if index not in (0,1,13)):
            # 停止当前调用并上报异常：raise ValueError('Nonempty uninitialized frame pool')。
            raise ValueError('Nonempty uninitialized frame pool')
    # 按条件 initialized and any((s['base'] != hex(2164260864 + i * 2097152) or s['state'] > 2 or s['readers'] > 3 or (s... 选择后续流程，保留原有异常和退出分支。
    if initialized and any(s['base']!=hex(0x81000000+i*0x200000) or s['state']>2 or s['readers']>3 or (s['readers'] and s['state']!=2) for i,s in enumerate(slots)):raise ValueError('Invalid frame pool ownership')
    if initialized and (sum(s['state']==1 for s in slots)!=(w[10]<3) or (w[10]<3 and slots[w[10]]['state']!=1)):raise ValueError('Camera ownership mismatch')
    if w[3]>w[2] or w[15]>w[14]:raise ValueError('Frame pool counters inconsistent')
    return dict(initialized=initialized,resize_started=w[2],resize_completed=w[3],capture_generation=w[4],inference_inputs=w[5],reclaimed_ready_slots=w[6],bad_captures=w[7],
        stop_drain_seconds=w[8]/w[13],input_wait_seconds=w[9]/w[13],capture_slot=w[10] if initialized else None,resize_phase=w[11],fault=w[12],
        metadata_published=w[14],metadata_acknowledged=w[15],overlay_acknowledged_frame=w[16],metadata_pending=w[17],
        service_calls=w[18],protocol_errors=w[19],inference_generation=w[20],preview_generation=w[21],slots=slots)
