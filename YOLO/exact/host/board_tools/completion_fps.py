"""Real-camera complete inference rate from 64-bit board TR timestamps."""
def calculate(samples):
    if len(samples) < 2:
        return {'valid': False, 'reason': 'Need two completed inference boundaries', 'samples': len(samples)}
    hz = samples[0]['cpu_hz']
    intervals = []
    for a, b in zip(samples, samples[1:]):
        count = b['completed'] - a['completed']
        ticks = b['TR'] - a['TR']
        if hz != b['cpu_hz'] or hz != 70000000 or count <= 0 or ticks <= 0:
            raise ValueError('Completion count, board clock or timestamp is not monotonic')
        if b['generation'] <= a['generation']:
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
