import subprocess,time,resource,json,pathlib,statistics,hashlib,os
root=pathlib.Path('reports/peripherals/video_opt_bench');root.mkdir(exist_ok=True)
rows=[]
env={k:v for k,v in os.environ.items() if not k.startswith('RV32_')}
for cycles,n in [(1000000,3),(4000000,1)]:
 for rep in range(n):
  for mode in (['os','o3'] if rep%2==0 else ['o3','os']):
   exe=f'build/video_boot_{"os_bench" if mode=="os" else "o3"}/Vrv32_linux_video_top'
   before=resource.getrusage(resource.RUSAGE_CHILDREN);start=time.monotonic()
   p=subprocess.run([exe,'build/video/video.bin',str(cycles)],capture_output=True,env=env)
   wall=time.monotonic()-start;after=resource.getrusage(resource.RUSAGE_CHILDREN)
   stem=root/f'{mode}_{cycles}_{rep}';stem.with_suffix('.stdout').write_bytes(p.stdout);stem.with_suffix('.stderr').write_bytes(p.stderr)
   row=dict(mode=mode,cycles=cycles,rep=rep,wall=wall,cpu=after.ru_utime+after.ru_stime-before.ru_utime-before.ru_stime,returncode=p.returncode,stdout_sha256=hashlib.sha256(p.stdout).hexdigest(),stderr_sha256=hashlib.sha256(p.stderr).hexdigest());rows.append(row);print(json.dumps(row),flush=True)
   (root/'timings.json').write_text(json.dumps(rows,indent=2))
for cycles in (1000000,4000000):
 subset=[r for r in rows if r['cycles']==cycles]
 assert all(r['returncode']==0 for r in subset)
 assert len({r['stdout_sha256'] for r in subset})==1 and len({r['stderr_sha256'] for r in subset})==1
 print('IDENTICAL',cycles,flush=True)
for mode in ['os','o3']:
 print(mode,'median cpu',statistics.median(r['cpu'] for r in rows if r['cycles']==1000000 and r['mode']==mode),flush=True)
