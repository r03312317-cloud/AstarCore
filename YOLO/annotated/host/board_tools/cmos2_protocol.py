# 架构导读：cmos2_protocol。
# 解码摄像头推理与独立预览的协议字段，区分推理完成和显示确认。
"""Distinct CMOS2 ABI. Never reinterpret the old stereo workflow as camera AI."""
import struct
import json
from pathlib import Path
_carrier=json.loads((Path(__file__).resolve().parent.parent/'VIDEO_PROFILE.json').read_text(encoding='utf-8-sig'))['carrier']
IMAGE_X,IMAGE_Y=_carrier['image_x'],_carrier['image_y']
# 按条件 not (0 <= IMAGE_X and 0 <= IMAGE_Y and (IMAGE_X + 680 <= _carrier['width']) and (IMAGE_Y + 340 <= _carrier[... 选择后续流程，保留原有异常和退出分支。
if not (0<=IMAGE_X and 0<=IMAGE_Y and IMAGE_X+680<=_carrier['width'] and IMAGE_Y+340<=_carrier['height']):raise ValueError('07 image does not fit configured carrier')
TIMES=('T0','TP0','TP1','TG0','TG1','TB','TF','TR','TC','TH_TX_INPUT','TE_TX_INPUT')
# 接口 session_start，显式输入字段：query, requested_run, runs。
# 本函数调用入口包括 int, max, ValueError。
def session_start(query,requested_run,runs):
 """Use the inactive buffer and fresh IDs so old TX events cannot match."""
 active_frame=int(query['active_frame'])
 frame=1 if active_frame&0x80000000 else active_frame+1
 run=max(requested_run,int(query['active_run'])+1)
 # 按条件 not 0 < frame < 2 ** 32 - runs or not 0 < run < 2 ** 32 - runs 选择后续流程，保留原有异常和退出分支。
 if not 0<frame<2**32-runs or not 0<run<2**32-runs:raise ValueError('Session IDs would wrap; reset/reload is required')
 fb=0x82100000 if int(query['display_status'],16)&16 and int(query['active_fb'],16)==0x82000000 else 0x82000000
 return frame,run,fb
# 接口 decode，显式输入字段：raw, status。
# 本函数调用入口包括 struct.unpack_from, bool, dict, len, ValueError。
def decode(raw,status):
 # 按条件 len(raw) != 288 选择后续流程，保留原有异常和退出分支。
 if len(raw)!=288:raise ValueError('CMOS2 reply must have 288 bytes')
 # 按条件 struct.unpack_from('<I', raw, 4)[0] == 3 选择后续流程，保留原有异常和退出分支。
 if struct.unpack_from('<I',raw,4)[0]==3:
  from frame_pool_protocol import decode_v3
  return decode_v3(raw,status,IMAGE_X,IMAGE_Y)
 w=struct.unpack_from('<24I',raw);t=struct.unpack_from('<11Q',raw,96)
 tail=struct.unpack_from('<11I',raw,184);capture=struct.unpack_from('<Q6I',raw,256)
 mode_flags,source_word,next_word,word3,word4=struct.unpack_from('<5I',raw,228)
 v2=w[1]==2
 # 按条件 w[0] != 827732547 or w[1] not in (1, 2) or capture[5] != 1 or (capture[6] != 462400) 选择后续流程，保留原有异常和退出分支。
 if w[0]!=0x31563243 or w[1] not in (1,2) or capture[5]!=1 or capture[6]!=462400:raise ValueError('CMOS2 version/channel/geometry mismatch')
 # 按条件 v2 选择后续流程，保留原有异常和退出分支。
 if v2:
  # 按条件 not mode_flags & 1 选择后续流程，保留原有异常和退出分支。
  if not mode_flags&1:raise ValueError('Missing V2 frame-pipeline flag')
  live=0;display_source=source_word;inference_source=source_word;preview_sequence=overlay_frame=0
 else:
  live=mode_flags;display_source=source_word;inference_source=next_word;preview_sequence=word3;overlay_frame=word4
  # 按条件 live not in (0, 1) 选择后续流程，保留原有异常和退出分支。
  if live not in (0,1):raise ValueError('Unknown live-preview flag')
 hz=w[13];ready=bool(tail[10]&1);video=bool(tail[10]&2);camera=bool(tail[10]&16)
 # 按条件 hz != 70000000 or w[15] != int(camera) or tail[10] & 12 选择后续流程，保留原有异常和退出分支。
 if hz!=70000000 or w[15]!=int(camera) or tail[10]&12:raise ValueError('Clock/source or stereo/V2 flags mismatch')
 # 按条件 tail[8] not in (3087007744, 3120562176, 3154116608, 3187671040) or tail[9] != 204 选择后续流程，保留原有异常和退出分支。
 if tail[8] not in (0xb8000000,0xba000000,0xbc000000,0xbe000000) or tail[9]!=204:raise ValueError('Graph204 FAST/S3/LUT/profile/Window/Concat contract differs')
 # 按条件 ready 选择后续流程，保留原有异常和退出分支。
 if ready:
  chronology=(t[0],t[1],t[2],t[3],t[4],t[5],t[7]) if (live or v2) else t[:8]
  # 按条件 not t[0] or any((a > b for a, b in zip(chronology, chronology[1:]))) 选择后续流程，保留原有异常和退出分支。
  if not t[0] or any(a>b for a,b in zip(chronology,chronology[1:])):raise ValueError('Invalid CPU64 processing chronology')
  # 按条件 v2 and (source_word not in (2164260864, 2166358016) or t[6] > t[7]) 选择后续流程，保留原有异常和退出分支。
  if v2 and (source_word not in (0x81000000,0x81200000) or t[6]>t[7]):raise ValueError('V2 raw frame or display write timing mismatch')
  # 按条件 live and (w[5] not in (2183135232, 2184183808) or inference_source != 2164260864 or display_source not in (... 选择后续流程，保留原有异常和退出分支。
  if live and (w[5] not in (0x82200000,0x82300000) or inference_source!=0x81000000 or display_source not in (0x81200000,0x81400000) or overlay_frame!=w[4] or t[6]>t[7]):raise ValueError('Live preview source or result provenance mismatch')
  # 按条件 capture[0] != t[1] or tail[:2] != (462400, 462400) or (not w[12] & 4) or w[12] & 16711680 选择后续流程，保留原有异常和退出分支。
  if capture[0]!=t[1] or tail[:2]!=(462400,462400) or not w[12]&4 or w[12]&0xff0000:raise ValueError('Invalid capture-end/final-B/READY proof')
  # 按条件 camera and (not capture[1] & 8 or capture[2:4] != (921600, 921600) or capture[4]) 选择后续流程，保留原有异常和退出分支。
  if camera and (not capture[1]&8 or capture[2:4]!=(921600,921600) or capture[4]):raise ValueError('Bad captured frame cannot be READY')
 # 按条件 video 选择后续流程，保留原有异常和退出分支。
 if video:
  # 按条件 not ready or status or w[3] or (w[2] != 8) or (w[16] & 30 != 30) or w[17] or w[20] 选择后续流程，保留原有异常和退出分支。
  if not ready or status or w[3] or w[2]!=8 or w[16]&0x1e!=0x1e or w[17] or w[20]:raise ValueError('Video success contradicts errors')
  # 按条件 t[8] + w[23] < t[7] or not t[8] <= t[9] <= t[10] or w[18] != w[19] 选择后续流程，保留原有异常和退出分支。
  if t[8]+w[23]<t[7] or not t[8]<=t[9]<=t[10] or w[18]!=w[19]:raise ValueError('Video chronology or underflow')
 box=[w[8]&65535,w[8]>>16,w[9]&65535,w[9]>>16]
 # 按条件 w[7] > 1 or (not w[7] and any(box)) 选择后续流程，保留原有异常和退出分支。
 if w[7]>1 or (not w[7] and any(box)):raise ValueError('Invalid selected palm result')
 # 按条件 w[7] and (not (0 <= box[0] < box[2] <= 680 and 0 <= box[1] < box[3] <= 340)) 选择后续流程，保留原有异常和退出分支。
 if w[7] and not (0<=box[0]<box[2]<=680 and 0<=box[1]<box[3]<=340):raise ValueError('Box out of compact buffer')
 return dict(pass_result=not status and ready and video,status=status,phase=w[2],error=w[3],
  frame_id=w[4],run_id=w[14],framebuffer=hex(w[5]),source='real CMOS2 capture' if camera else 'explicit DDR replay',
  live_preview=bool(live),pipeline_v2=v2,pipeline_flags=mode_flags if v2 else 0,
  pipeline_from_prefetch=bool(mode_flags&2) if v2 else False,
  next_capture_raw=hex(next_word) if v2 else None,display_source_raw=hex(display_source),inference_source_raw=hex(inference_source),
  preview_sequence=preview_sequence,overlay_inference_frame=overlay_frame,
  same_source_frame=not bool(live),
  selected_capture_channel=capture[5],capture_sensor_pixels=capture[3],capture_writer_pixels=capture[2],capture_errors=capture[4],
  NMS_count=w[6],palm_count=w[7],bbox_compact_xyxy=box,bbox_HDMI_xyxy=[box[0]+IMAGE_X,box[1]+IMAGE_Y,box[2]+IMAGE_X,box[3]+IMAGE_Y] if w[7] else [0]*4,score_q15=w[10],class_id=w[11],
  cpu_hz=hz,timestamps_CPU64=dict(zip(TIMES,t)),capture_end_CPU64=capture[0],
  capture_seconds=(t[1]-t[0])/hz if ready and camera else None,
  preprocess_seconds=(t[2]-t[1])/hz if ready else None,graph_seconds=(t[4]-t[3])/hz if ready else None,
  NMS_seconds=(t[5]-t[4])/hz if ready else None,display_and_commit_seconds=(t[7]-t[5])/hz if ready else None,
  START_to_READY_seconds=(t[7]-t[0])/hz if ready else None,
  event_capture_delay_bound_CPU_cycles=w[23],
  START_to_READY_upper_bound_seconds=(t[7]-t[0]+w[23])/hz if ready else None,
  START_to_first_TX_input_seconds=(t[9]-t[0])/hz if video else None,
  START_to_complete_TX_input_seconds=(t[10]-t[0])/hz if video else None,
  accepted_bytes=tail[0],committed_bytes=tail[1],underflow_before=w[18],underflow_after=w[19],video_fault=w[17],
  endpoint_scope='TX input event; physical serializer/display confirmation must be separate',physical_panel_verified=False,
  graph_ops=tail[9],graph_flags=hex(tail[8]),window_requested=bool(tail[8]&0x04000000),concat_requested=bool(tail[8]&0x02000000),
  under_3_seconds_measured=ready and (t[7]-t[0]+w[23])<=3*hz)
# 接口 preview_snapshot，显式输入字段：raw, cpu_hz。
# 本函数调用入口包括 struct.unpack_from, dict, len, ValueError, bool。
def preview_snapshot(raw,cpu_hz=70000000):
 # 按条件 len(raw) != 64 选择后续流程，保留原有异常和退出分支。
 if len(raw)!=64:raise ValueError('Live preview status needs 64 bytes')
 w=struct.unpack_from('<12I2Q',raw)
 # 按条件 w[0] != 827740236 or w[1] != 1 or w[2] > 1 选择后续流程，保留原有异常和退出分支。
 if w[0]!=0x3156504c or w[1]!=1 or w[2]>1:raise ValueError('Live preview status ABI')
 # 按条件 w[4] > w[3] or w[6] > w[4] or w[7] > w[6] or (w[13] and w[13] < w[12]) 选择后续流程，保留原有异常和退出分支。
 if w[4]>w[3] or w[6]>w[4] or w[7]>w[6] or (w[13] and w[13]<w[12]):raise ValueError('Live preview counters or timestamps are inconsistent')
 elapsed=(w[13]-w[12])/cpu_hz if w[12] and w[13]>=w[12] else None
 return dict(active=bool(w[2]),capture_attempts=w[3],valid_camera_frames=w[4],dropped_frames=w[5],
             publications=w[6],vblank_acknowledgements=w[7],fault=w[8],last_overlay_inference_frame=w[9],
             last_display_fb=hex(w[10]),sequence=w[11],first_capture_CPU64=w[12],last_ack_CPU64=w[13],
             acknowledged_fps=w[7]/elapsed if elapsed else None,measurement_seconds=elapsed,
             measurement_scope='vblank acknowledgements during first capture start through last acknowledged preview; not inference FPS or monitor refresh')
# 接口 continuous_snapshot，显式输入字段：raw。
# 本函数调用入口包括 struct.unpack_from, dict, len, ValueError, bool。
def continuous_snapshot(raw):
 # 按条件 len(raw) != 304 选择后续流程，保留原有异常和退出分支。
 if len(raw)!=304:raise ValueError('Continuous status needs 304 bytes')
 ident,active,completed,status=struct.unpack_from('<4I',raw)
 # 按条件 ident != 827732547 or active > 1 选择后续流程，保留原有异常和退出分支。
 if ident!=0x31563243 or active>1:raise ValueError('continuous ABI')
 reply=raw[16:]
 return dict(active=bool(active),completed=completed,last_status=status,
             last_run=decode(reply,status) if reply[:4]==struct.pack('<I',ident) else None)

# 接口 scheduler_snapshot，显式输入字段：raw。
# 本函数调用入口包括 struct.unpack_from, dict, len, ValueError, bool。
def scheduler_snapshot(raw):
 # 按条件 len(raw) != 64 选择后续流程，保留原有异常和退出分支。
 if len(raw)!=64:raise ValueError('Preview scheduler status needs 64 bytes')
 w=struct.unpack_from('<8I2Q4I',raw)
 # 按条件 w[0] != 959533904 or w[1] != 1 or w[13] != 70000000 选择后续流程，保留原有异常和退出分支。
 if w[0]!=0x39315350 or w[1]!=1 or w[13]!=70000000:raise ValueError('Preview scheduler ABI/clock')
 # 按条件 w[3] > w[2] or w[5] + w[6] > w[4] or w[10] > 1 or (w[11] > 2) 选择后续流程，保留原有异常和退出分支。
 if w[3]>w[2] or w[5]+w[6]>w[4] or w[10]>1 or w[11]>2:raise ValueError('Preview scheduler counters/ownership')
 return dict(resize_started=w[2],resize_completed=w[3],prefetch_started=w[4],prefetch_used=w[5],
             prefetch_discarded=w[6],prefetch_bad=w[7],preview_drain_seconds=w[8]/w[13],
             resize_wall_seconds=w[9]/w[13],prefetch_pending=bool(w[10]),resize_phase=w[11],fault=w[12],
             scope='Resize wall time overlaps graph/capture; do not add these counters to total latency.')
