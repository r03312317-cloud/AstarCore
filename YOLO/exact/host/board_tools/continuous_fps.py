"""Calculate an autonomous camera throughput interval from two CPU64 snapshots.

The denominator is between completed TX-input events; the numerator is the
change in successful completed frames, so the first boundary is not counted
as a completion inside the measured interval. No hardware I/O is performed.
"""
CPU_HZ=70000000
U32_LIMIT=1<<32
U64_LIMIT=1<<64

def require(cond,message):
 if not cond:raise ValueError(message)

def measured_interval(start,end,frame_base,run_base,first_fb):
 require(start.get('active') is True and end.get('active') is False,'expected active start and stopped end')
 require(start.get('last_status')==0 and end.get('last_status')==0,'autonomous workflow error')
 first,last=start.get('last_run'),end.get('last_run')
 require(first is not None and last is not None and first.get('pass_result') and last.get('pass_result'),'boundary frame missing or failed')
 a,b=start['completed'],end['completed']
 require(isinstance(a,int) and isinstance(b,int) and 0<a<U32_LIMIT and 0<b<U32_LIMIT,'no completed start/end frame or counter out of range')
 require(b>a,'no completed frame inside interval or completed counter wrapped')
 require(0<frame_base<U32_LIMIT and 0<run_base<U32_LIMIT and first_fb in (0x82000000,0x82100000),'invalid frame identity base')
 require(frame_base+b-1<U32_LIMIT and run_base+b-1<U32_LIMIT,'frame/run ID would wrap')
 for count,row in ((a,first),(b,last)):
  fb=first_fb^(((count-1)&1)*0x100000)
  require((row.get('frame_id'),row.get('run_id'),row.get('framebuffer'))==(frame_base+count-1,run_base+count-1,hex(fb)),'frame/run/framebuffer sequence mismatch')
  require(row.get('cpu_hz')==CPU_HZ and row.get('source')=='real CMOS2 capture' and row.get('window_requested') and row.get('concat_requested'),'clock, camera source or graph mode mismatch')
  require(row.get('capture_errors')==0 and row.get('capture_sensor_pixels')==921600 and row.get('capture_writer_pixels')==921600,'invalid boundary camera capture')
 t0=first['timestamps_CPU64']['TE_TX_INPUT'];t1=last['timestamps_CPU64']['TE_TX_INPUT']
 require(isinstance(t0,int) and isinstance(t1,int) and 0<t0<U64_LIMIT and 0<t1<U64_LIMIT and t1>t0,'invalid or wrapped CPU64 event')
 bounds=[first['event_capture_delay_bound_CPU_cycles'],last['event_capture_delay_bound_CPU_cycles']]
 require(all(isinstance(x,int) and 0<=x<U32_LIMIT for x in bounds),'invalid event delay bound')
 ticks=t1-t0;frame_delta=b-a;bound=max(bounds)
 require(ticks>bound,'event-capture uncertainty exceeds measurement span')
 seconds=ticks/CPU_HZ
 return {'completed_at_start':a,'completed_at_stop':b,'warmup_completed_frames':a,'completed_frames_in_interval':frame_delta,
         'start_frame_id':first['frame_id'],'end_frame_id':last['frame_id'],'start_run_id':first['run_id'],'end_run_id':last['run_id'],
         'start_TE_CPU64':t0,'end_TE_CPU64':t1,'elapsed_CPU_ticks':ticks,'CPU_hz':CPU_HZ,'elapsed_seconds':seconds,
         'average_completed_frame_FPS':frame_delta*CPU_HZ/ticks,'average_completion_interval_ms':ticks*1000/(frame_delta*CPU_HZ),
         'event_capture_bound_ticks':bound,'event_capture_bound_seconds':bound/CPU_HZ,
         'FPS_lower_bound_from_capture_delay':frame_delta*CPU_HZ/(ticks+bound),
         'FPS_upper_bound_from_capture_delay':frame_delta*CPU_HZ/(ticks-bound),
         'numerator_scope':'successful complete camera/graph/NMS/display frames, including frames without a palm; not number of palm detections',
         'denominator_scope':'CPU64 TE_TX_INPUT of start and stopped end boundary frames; includes camera wait, inference, display and in-loop status-query/host gaps; excludes pre-ARM setup and post-STOP readbacks; no physical panel confirmation'}
