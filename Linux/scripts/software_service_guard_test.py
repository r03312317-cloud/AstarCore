#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,os,select,time,argparse
p=argparse.ArgumentParser(description="Reference-only QEMU service guard regression; frozen v4 is read-only")
p.add_argument("--qemu",required=True);p.add_argument("--bios",required=True);p.add_argument("--work-dir",required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=Path(a.work_dir);out.mkdir(parents=True,exist_ok=True)
src=root/'firmware/boot-video-v4/rootfs.cpio';data=src.read_bytes();offset=0;records=[];changes=[]
while data[offset:offset+6]==b'070701':
 start=offset;f=[int(data[offset+6+i*8:offset+14+i*8],16) for i in range(13)];name=data[offset+110:offset+110+f[11]-1].decode();offset=(offset+110+f[11]+3)&~3;body=data[offset:offset+f[6]];offset=(offset+f[6]+3)&~3;record=data[start:offset];new=body
 if name=='etc/init.d/S01syslogd':new=(root/'buildroot/board/rv32/overlay'/name).read_bytes()
 if name=='etc/inittab':new=body.replace(b'ttyAS0',b'ttyS0')
 if new!=body:
  f[6]=len(new);record=b'070701'+b''.join(('%08x'%x).encode() for x in f)+name.encode()+b'\0';record+=b'\0'*((-len(record))%4);record+=new;record+=b'\0'*((-len(record))%4);changes.append(name)
 records.append(record)
 if name=='TRAILER!!!':break
assert changes==['etc/inittab','etc/init.d/S01syslogd'] or sorted(changes)==['etc/init.d/S01syslogd','etc/inittab'],changes
variant=b''.join(records);variant+=b'\0'*((-len(variant))%512);initrd=out/'rootfs.cpio';initrd.write_bytes(variant)
qemu=Path(a.qemu).resolve();env=os.environ.copy()
cmd=[str(qemu),'-M','virt','-m','64M','-nographic','-bios',a.bios,'-kernel',str(root/'firmware/boot-video-v4/Image'),'-initrd',str(initrd),'-append','console=ttyS0,115200 earlycon=sbi rdinit=/init loglevel=7 panic=0'];p=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env);log=b'';deadline=time.monotonic()+120
try:
 while time.monotonic()<deadline:
  if not select.select([p.stdout],[],[],.2)[0]:continue
  block=os.read(p.stdout.fileno(),65536)
  if not block:break
  log+=block
  if b'rv32 login:' in log:break
finally:p.terminate();p.wait(timeout=5)
report={'scope':'QEMU virt reference only, post-v4 source guard; not RTL tested image','changes':changes,'console_adaptation':'inittab ttyAS0 to ttyS0 only for QEMU virt','frozen_input_sha256':hashlib.sha256(data).hexdigest(),'variant_sha256':hashlib.sha256(variant).hexdigest(),'checks':{'init_wrapper':b'Run /init as init process' in log,'s01_commands_end':b'RV32_LINUX_COMMANDS_END\r\n' in log,'explicit_syslog_skip':b'Starting syslogd: SKIP (AF_UNIX unavailable; /proc/net/unix absent)' in log,'no_false_syslog_ok':b'Starting syslogd: OK' not in log,'getty_login_prompt':b'rv32 login:' in log}}
report['passed']=all(report['checks'].values());dest=root/'reports';(dest/'qemu_service_guard.log').write_bytes(log);(dest/'qemu_service_guard.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));raise SystemExit(not report['passed'])
