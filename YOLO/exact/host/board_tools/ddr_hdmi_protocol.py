"""Versioned offline decoder for production AST1 op21/op22 replies.

TH/TE are explicitly TX INPUT events, not verified serialized wire/panel times.
"""
import struct
TIMES=('T0','TP0','TP1','TG0','TG1','TB','TF','TR','TC','TH_TX_INPUT','TE_TX_INPUT')
PROFILE_NAMES=('Graph204','Conv','CPU_im2col','NPU_completion','NPU_command',
 'NPU_poll','hardware_Requant','software_Requant','Concat','Upsample','Add','Pool',
 'software_LUT','S3_poll','S3_active','S3_stall','S3_read','S3_write',
 'graph_validation','CPU_poll','Decode_NMS','NPU_active','NPU_DMA_wait',
 'V2_preprocess','display_resize','DDR_frame_to_READY',
 'Window_gather','Window_read','Window_write','Window_active','Window_stall')

def decode_profile(raw):
 if len(raw)<40:raise ValueError('Truncated FAST_PROFILE header')
 header=struct.unpack_from('<10I',raw)
 if header[:3] not in ((0x31465046,1,26),(0x31465046,2,31)):raise ValueError('Wrong FAST_PROFILE schema')
 if len(raw)!=40+8*header[2]:raise ValueError('FAST_PROFILE length/count mismatch')
 values=struct.unpack_from('<'+str(header[2])+'Q',raw,40)
 if header[4:7]!=(70000000,100000000,93750000):raise ValueError('Profile clock configuration differs')
 rows={}
 for i,(name,value) in enumerate(zip(PROFILE_NAMES,values)):
  unit='bytes' if i in (16,17,27,28) else 'NPU cycles' if i in (3,21,22) else 'UI cycles' if i in (14,15,29,30) else 'CPU ticks'
  frequency=None if unit=='bytes' else header[5] if unit=='NPU cycles' else header[6] if unit=='UI cycles' else header[4]
  available=bool(header[3]>>i&1)
  rows[name]={'available':available,'raw':value if available else None,'unit':unit,
   'seconds':value/frequency if available and frequency else None}
 return {'batches':header[7],'ops':header[8],'errors':header[9],'counters':rows,
  'scope':'Overlapping phase/wait counters; do not add them to infer total latency',
  'legacy_per_phase_counter_bits':32,'phase_wrap_limit_seconds':2**32/header[4],
  'whole_path_timing_source':'Independent CPU64 workflow timestamps'}
def decode_workflow(raw,status):
 if len(raw)!=256:raise ValueError(f'Workflow reply needs 256 bytes, got {len(raw)}, status {status}')
 w=struct.unpack_from('<24I',raw);ticks=struct.unpack_from('<11Q',raw,96)
 tail=struct.unpack_from('<11I',raw,184)
 if w[:2]!=(0x31524456,2):raise ValueError('Wrong workflow version')
 hz=w[13];bound=w[23]
 if hz!=70000000:raise ValueError('Unexpected CPU time reference')
 ready=bool(tail[10]&1);digital=bool(tail[10]&2)
 if ready:
  if not ticks[0] or any(a>b for a,b in zip(ticks[:8],ticks[1:8])):
   raise ValueError('Invalid processing CPU64 chronology')
  if tail[:2]!=(614400,614400) or not w[12]&4 or w[12]&0xff0000:
   raise ValueError('Invalid final B coverage/atomic READY')
 if digital:
  if not ready or w[2]!=8 or w[3] or status or w[16]&0x1e!=0x1e or w[17] or w[20]:
   raise ValueError('Digital completion flag contradicts result/state/error counters')
  if ticks[8]+bound<ticks[7] or not ticks[8]<=ticks[9]<=ticks[10]:
   raise ValueError('Invalid video event chronology')
  if w[19]!=w[18]:raise ValueError('Video underflow occurred during this run')
 if ready and tail[10]&8:
  if w[15] or tail[5:7]!=(5038848,307200) or not tail[7]&8 or tail[7]&32:
   raise ValueError('Hardware V2 completion evidence contradicts the result')
 flags={'processing_ready':ready,'digital_tx_input_frame':digital,
        'same_image_two_windows_replay':bool(tail[10]&4),'hardware_v2':bool(tail[10]&8)}
 # Each raw Gray capture can trail the shared CPU reference by <= bound.
 # End-start duration uncertainty is <= one bound (both delays nonnegative).
 ready_s=(ticks[7]-ticks[0])/hz if ready else None
 tx_s=(ticks[9]-ticks[0])/hz if digital else None
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

def decode_query(raw):
 if len(raw)!=136:raise ValueError('Video query size mismatch')
 w=struct.unpack_from('<32I',raw)
 if w[:2]!=(0x32445648,2) or w[4]!=0x32544956:raise ValueError('Video query schema/ID mismatch')
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
