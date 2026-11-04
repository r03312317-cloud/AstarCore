# 架构导读：completion_fps。
# 按完整推理计数差与 CPU64 TR 时间戳差计算平均帧间隔和 FPS。
"""Real-camera complete inference rate from 64-bit board TR timestamps."""
# 接口 calculate，显式输入字段：samples。
# 本函数调用入口包括 zip, sum, dict, len, intervals.append。
def calculate(samples):
    # 按条件 len(samples) < 2 选择后续流程，保留原有异常和退出分支。
    if len(samples) < 2:
        return {'valid': False, 'reason': 'Need two completed inference boundaries', 'samples': len(samples)}
    hz = samples[0]['cpu_hz']
    intervals = []
    # 迭代/等待条件：zip(samples, samples[1:])；退出由原循环条件及显式 break/异常决定。
    for a, b in zip(samples, samples[1:]):
        count = b['completed'] - a['completed']
        ticks = b['TR'] - a['TR']
        # 按条件 hz != b['cpu_hz'] or hz != 70000000 or count <= 0 or (ticks <= 0) 选择后续流程，保留原有异常和退出分支。
        if hz != b['cpu_hz'] or hz != 70000000 or count <= 0 or ticks <= 0:
            # 停止当前调用并上报异常：raise ValueError('Completion count, board clock or timestamp is not monotonic')。
            raise ValueError('Completion count, board clock or timestamp is not monotonic')
        if b['generation'] <= a['generation']:
            # 停止当前调用并上报异常：raise ValueError('Duplicate/stale raw camera frame')。
            raise ValueError('Duplicate/stale raw camera frame')
        intervals.append(dict(frames=count, ticks=ticks, seconds=ticks/hz))
    frames = sum(x['frames'] for x in intervals)
    ticks = sum(x['ticks'] for x in intervals)
    return dict(valid=True, samples=len(samples), completed_at_start=samples[0]['completed'],
                completed_at_end=samples[-1]['completed'], complete_frame_intervals=frames,
                timer_hz=hz, first_TR=samples[0]['TR'], last_TR=samples[-1]['TR'],
                elapsed_ticks=ticks, elapsed_seconds=ticks/hz,
                average_interval_ms=ticks*1000/(hz*frames), fps=frames*hz/ticks,
                unsampled_completions=frames-len(intervals),
                scope='Real-camera complete Graph204 and NMS completion TR; includes no-detection frames; excludes model upload and startup')
