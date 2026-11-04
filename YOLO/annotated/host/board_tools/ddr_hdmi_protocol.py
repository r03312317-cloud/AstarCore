# 架构导读：ddr_hdmi_protocol。
# 协议字段解码与一致性检查，输入来自已保存或实时收到的板卡回复。
"""Versioned offline decoder for production AST1 op21/op22 replies.

TH/TE are explicitly TX INPUT events, not verified serialized wire/panel times.
"""
import struct
# 维护本地状态/计算值：TIMES=('T0','TP0','TP1','TG0','TG1','TB','TF','TR','TC','TH_TX_INPUT','TE_TX_INPUT')。
TIMES=('T0','TP0','TP1','TG0','TG1','TB','TF','TR','TC','TH_TX_INPUT','TE_TX_INPUT')
PROFILE_NAMES=('Graph204','Conv','CPU_im2col','NPU_completion','NPU_command',
 'NPU_poll','hardware_Requant','software_Requant','Concat','Upsample','Add','Pool',
 'software_LUT','S3_poll','S3_active','S3_stall','S3_read','S3_write',
 'graph_validation','CPU_poll','Decode_NMS','NPU_active','NPU_DMA_wait',
 'V2_preprocess','display_resize','DDR_frame_to_READY',
 'Window_gather','Window_read','Window_write','Window_active','Window_stall')

# 接口 decode_profile，显式输入字段：raw。
# 本函数调用入口包括 struct.unpack_from, enumerate, len, ValueError, zip。
def decode_profile(raw):
 # 按条件 len(raw) < 40 选择后续流程，保留原有异常和退出分支。
 if len(raw)<40:raise ValueError('Truncated FAST_PROFILE header')
 header=struct.unpack_from('<10I',raw)
 # 按条件 header[:3] not in ((826691654, 1, 26), (826691654, 2, 31)) 选择后续流程，保留原有异常和退出分支。
 if header[:3] not in ((0x31465046,1,26),(0x31465046,2,31)):raise ValueError('Wrong FAST_PROFILE schema')
 # 按条件 len(raw) != 40 + 8 * header[2] 选择后续流程，保留原有异常和退出分支。
 if len(raw)!=40+8*header[2]:raise ValueError('FAST_PROFILE length/count mismatch')
 values=struct.unpack_from('<'+str(header[2])+'Q',raw,40)
 # 按条件 header[4:7] != (70000000, 100000000, 93750000) 选择后续流程，保留原有异常和退出分支。
 if header[4:7]!=(70000000,100000000,93750000):raise ValueError('Profile clock configuration differs')
 rows={}
 # 迭代/等待条件：enumerate(zip(PROFILE_NAMES, values))；退出由原循环条件及显式 break/异常决定。
 for i,(name,value) in enumerate(zip(PROFILE_NAMES,values)):
  unit='bytes' if i in (16,17,27,28) else 'NPU cycles' if i in (3,21,22) else 'UI cycles' if i in (14,15,29,30) else 'CPU ticks'
  frequency=None if unit=='bytes' else header[5] if unit=='NPU cycles' else header[6] if unit=='UI cycles' else header[4]
  available=bool(header[3]>>i&1)
  rows[name]={'available':available,'raw':value if available else None,'unit':unit,
   'seconds':value/frequency if available and frequency else None}
 # 向调用方返回本步骤结果：{'batches':header[7],'ops':header[8],'errors':header[9],'counters':rows,。
 return {'batches':header[7],'ops':header[8],'errors':header[9],'counters':rows,
  'scope':'Overlapping phase/wait counters; do not add them to infer total latency',
  'legacy_per_phase_counter_bits':32,'phase_wrap_limit_seconds':2**32/header[4],
  'whole_path_timing_source':'Independent CPU64 workflow timestamps'}
# 接口 decode_workflow，显式输入字段：raw, status。
# 本函数调用入口包括 struct.unpack_from, bool, len, ValueError, hex。
def decode_workflow(raw,status):
 # 按条件 len(raw) != 256 选择后续流程，保留原有异常和退出分支。
 if len(raw)!=256:raise ValueError(f'Workflow reply needs 256 bytes, got {len(raw)}, status {status}')
 w=struct.unpack_from('<24I',raw);ticks=struct.unpack_from('<11Q',raw,96)
 tail=struct.unpack_from('<11I',raw,184)
 # 按条件 w[:2] != (827475030, 2) 选择后续流程，保留原有异常和退出分支。
 if w[:2]!=(0x31524456,2):raise ValueError('Wrong workflow version')
 hz=w[13];bound=w[23]
 # 按条件 hz != 70000000 选择后续流程，保留原有异常和退出分支。
 if hz!=70000000:raise ValueError('Unexpected CPU time reference')
 ready=bool(tail[10]&1);digital=bool(tail[10]&2)
 # 按条件 ready 选择后续流程，保留原有异常和退出分支。
 if ready:
  # 按条件 not ticks[0] or any((a > b for a, b in zip(ticks[:8], ticks[1:8]))) 选择后续流程，保留原有异常和退出分支。
  if not ticks[0] or any(a>b for a,b in zip(ticks[:8],ticks[1:8])):
   # 停止当前调用并上报异常：raise ValueError('Invalid processing CPU64 chronology')。
   raise ValueError('Invalid processing CPU64 chronology')
  # 按条件 tail[:2] != (614400, 614400) or not w[12] & 4 or w[12] & 16711680 选择后续流程，保留原有异常和退出分支。
  if tail[:2]!=(614400,614400) or not w[12]&4 or w[12]&0xff0000:
   # 停止当前调用并上报异常：raise ValueError('Invalid final B coverage/atomic READY')。
   raise ValueError('Invalid final B coverage/atomic READY')
 # 按条件 digital 选择后续流程，保留原有异常和退出分支。
 if digital:
  # 按条件 not ready or w[2] != 8 or w[3] or status or (w[16] & 30 != 30) or w[17] or w[20] 选择后续流程，保留原有异常和退出分支。
  if not ready or w[2]!=8 or w[3] or status or w[16]&0x1e!=0x1e or w[17] or w[20]:
   # 停止当前调用并上报异常：raise ValueError('Digital completion flag contradicts result/state/error counters')。
   raise ValueError('Digital completion flag contradicts result/state/error counters')
  # 按条件 ticks[8] + bound < ticks[7] or not ticks[8] <= ticks[9] <= ticks[10] 选择后续流程，保留原有异常和退出分支。
  if ticks[8]+bound<ticks[7] or not ticks[8]<=ticks[9]<=ticks[10]:
   # 停止当前调用并上报异常：raise ValueError('Invalid video event chronology')。
   raise ValueError('Invalid video event chronology')
  # 按条件 w[19] != w[18] 选择后续流程，保留原有异常和退出分支。
  if w[19]!=w[18]:raise ValueError('Video underflow occurred during this run')
 # 按条件 ready and tail[10] & 8 选择后续流程，保留原有异常和退出分支。
 if ready and tail[10]&8:
  # 按条件 w[15] or tail[5:7] != (5038848, 307200) or (not tail[7] & 8) or tail[7] & 32 选择后续流程，保留原有异常和退出分支。
  if w[15] or tail[5:7]!=(5038848,307200) or not tail[7]&8 or tail[7]&32:
   # 停止当前调用并上报异常：raise ValueError('Hardware V2 completion evidence contradicts the result')。
   raise ValueError('Hardware V2 completion evidence contradicts the result')
 flags={'processing_ready':ready,'digital_tx_input_frame':digital,
        'same_image_two_windows_replay':bool(tail[10]&4),'hardware_v2':bool(tail[10]&8)}
 # Each raw Gray capture can trail the shared CPU reference by <= bound.
 # End-start duration uncertainty is <= one bound (both delays nonnegative).
 ready_s=(ticks[7]-ticks[0])/hz if ready else None
 tx_s=(ticks[9]-ticks[0])/hz if digital else None
 # 向调用方返回本步骤结果：{'pass':status==0 and ready and digital,'status':status,'phase':w[2],'error':w[3],。
 return {'pass':status==0 and ready and digital,'status':status,'phase':w[2],'error':w[3],
  'frame_id':w[4],'framebuffer':hex(w[5]),'nms_results':w[6],'display_palm_count':w[7],
  'bbox_xyxy':[w[8]&65535,w[8]>>16,w[9]&65535,w[9]>>16],
  'score_q15':w[10],'class_id':w[11],'display_status':hex(w[12]),'cpu_hz':hz,
  'run_id':w[14],'v2_mode':'software' if w[15] else 'hardware',
  'video_status':hex(w[16]),'video_fault':w[17],
  'underflow_before':w[18],'underflow_after':w[19],'frame_mismatch':w[20],
  'presented_frames':w[21],'max_ddr_wait_UI_cycles':w[22],
  'event_capture_delay_bound_CPU_cycles':bound,'event_capture_delay_bound_seconds':bound/hz,
  'timestamps_cpu64':dict(zip(TIMES,ticks)),
  'START_to_READY_seconds':ready_s,'START_to_READY_upper_bound_seconds':ready_s+bound/hz if ready else None,
  'START_to_TH_TX_INPUT_seconds':tx_s,
  'START_to_TE_TX_INPUT_seconds':(ticks[10]-ticks[0])/hz if digital else None,
  'phase_seconds':{'V2':(ticks[2]-ticks[1])/hz,'Graph204':(ticks[4]-ticks[3])/hz,
    'NMS_select':(ticks[5]-ticks[4])/hz,'resize_to_last_B':(ticks[6]-ticks[5])/hz,
    'last_B_to_READY':(ticks[7]-ticks[6])/hz},
  'accepted_bytes':tail[0],'committed_bytes':tail[1],'commit_sequence':tail[2],
  'fifo_high':tail[3],'fifo_low':tail[4],'V2_source_pixels':tail[5],
  'V2_output_bytes':tail[6],'V2_status':hex(tail[7]),'graph_flags':hex(tail[8]),'graph_ops':tail[9],
  'flags':flags,'wire_serializer_latency_verified':False,'physical_panel_verified':False,
  'camera_connected':False}

# 接口 decode_query，显式输入字段：raw。
# 本函数调用入口包括 struct.unpack_from, len, ValueError, hex。
def decode_query(raw):
 # 按条件 len(raw) != 136 选择后续流程，保留原有异常和退出分支。
 if len(raw)!=136:raise ValueError('Video query size mismatch')
 w=struct.unpack_from('<32I',raw)
 # 按条件 w[:2] != (843339336, 2) or w[4] != 844384598 选择后续流程，保留原有异常和退出分支。
 if w[:2]!=(0x32445648,2) or w[4]!=0x32544956:raise ValueError('Video query schema/ID mismatch')
 # 向调用方返回本步骤结果：{'cpu_hz':w[2],'gpio_status':w[3],'video_status':hex(w[5]),。
 return {'cpu_hz':w[2],'gpio_status':w[3],'video_status':hex(w[5]),
  'expected_run':w[6],'expected_frame':w[7],'requested_pattern':w[8],
  'underflow':w[9],'mismatch':w[10],'presented_frames':w[11],
  'max_ddr_wait_UI_cycles':w[12],'fifo_high':w[13],'fifo_low':w[14],'video_fault':w[15],
  'TC':w[16]|w[17]<<32,'TH_TX_INPUT':w[18]|w[19]<<32,'TE_TX_INPUT':w[20]|w[21]<<32,
  'underflow_before':w[22],'event_delay_bound_CPU_cycles':w[23],
  'display_status':hex(w[24]),'active_fb':hex(w[25]),'active_frame':w[26],'active_run':w[27],
  'active_box_count':w[28],'committed_bytes':w[29],'pending_writes':w[30],
  'display_frame_bytes':w[31],'CPU_query_ticks':struct.unpack_from('<Q',raw,128)[0],
  'scope':'Immutable per-run event snapshots; live counters sampled sequentially; no panel proof'}
