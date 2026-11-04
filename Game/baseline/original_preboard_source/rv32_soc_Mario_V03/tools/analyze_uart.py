"""Read-only FPS and phase-cost analysis of captured V01/V02 board UART.
No board access. A MODE=1 map sample can be paused; it is not a playability proof.
"""
from pathlib import Path
import argparse,json,re,statistics

def analyze(data,clock_hz=100000000):
    samples=[]
    for line in data.decode('utf-8',errors='replace').splitlines():
        if 'MARIO_FRAME=' in line:
            row={k:int(v) for k,v in re.findall(r'([A-Z_]+)=(\d+)',line)}
            if {'MARIO_FRAME','DELTA','CYCLES','MODE','X','Y'}<=row.keys() and row['CYCLES']>0:samples.append(row)
        elif 'MARIO_COST ' in line and samples:
            samples[-1]['costs']={k:int(v) for k,v in re.findall(r'([A-Z]+)=(\d+)',line)}
    groups={}
    for name,predicate in [
        ('title_mode0_x40',lambda s:s['MODE']==0 and s['X']==40),
        ('mode1_x0_phase_unknown',lambda s:s['MODE']==1 and s['X']==0 and 'TASK' not in s),
        ('mode1_map_pause_unknown',lambda s:s['MODE']==1 and s['X']>0 and 'TASK' not in s),
        ('mode1_game_task3_pause_unknown',lambda s:s['MODE']==1 and s.get('TASK')==3),
        ('mode1_other_tasks',lambda s:s['MODE']==1 and 'TASK' in s and s['TASK']!=3),
        ('all_samples',lambda s:True)]:
        rows=[s for s in samples if predicate(s)]
        if not rows:continue
        ticks=sum(s['CYCLES'] for s in rows)
        group={'samples':len(rows),'weighted_emulation_fps':clock_hz*sum(s['DELTA'] for s in rows)/ticks,
               'median_emulation_fps':statistics.median(clock_hz*s['DELTA']/s['CYCLES'] for s in rows)}
        video=[s for s in rows if 'VDELTA' in s]
        if video:group['weighted_framebuffer_publications_per_second']=clock_hz*sum(s['VDELTA'] for s in video)/sum(s['CYCLES'] for s in video)
        costs=[s for s in rows if 'costs' in s]
        if costs:
            cost_ticks=sum(s['CYCLES'] for s in costs)
            keys=sorted({k for s in costs for k in s['costs']})
            group['profile_percent_of_elapsed']={k:100*sum(s['costs'].get(k,0) for s in costs)/cost_ticks for k in keys}
        groups[name]=group
    return {'clock_hz':clock_hz,'groups':groups,'scope':'emulation and successful framebuffer publications, not HDMI carrier frequency; physical movement/jump require observation',
            'errors':sorted({marker for marker in ['MARIO_VIDEO_TIMEOUT','MARIO_VIDEO_BAD_REQUEST','MARIO_ROM_REJECTED','MARIO_EXIT','TRAP='] if marker.encode() in data})}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('uart',type=Path);parser.add_argument('--output',type=Path);args=parser.parse_args()
    report=analyze(args.uart.read_bytes());text=json.dumps(report,indent=2)+'\n'
    if args.output:args.output.write_text(text)
    print(text,end='')
if __name__=='__main__':main()
