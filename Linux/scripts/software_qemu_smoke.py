#!/usr/bin/env python3
"""Reference-only QEMU virt boot or RV32 LVGL headless test, never RV32 proof."""
import argparse, os, pathlib, select, subprocess, time
p=argparse.ArgumentParser();p.add_argument('--qemu',required=True);p.add_argument('--bios',required=True)
p.add_argument('--kernel',required=True);p.add_argument('--initrd',required=True);p.add_argument('--log',required=True)
p.add_argument('--gui',action='store_true');p.add_argument('--target-dtb');p.add_argument('--fdtget',default='fdtget');a=p.parse_args()
target_args=None
append='console=ttyS0,115200 earlycon=sbi rdinit=/init loglevel=7 panic=0'
if a.target_dtb:
 target_args=subprocess.check_output([a.fdtget,a.target_dtb,'/chosen','bootargs'],text=True).strip()
 # QEMU virt has a different UART; preserve every non-console target argument.
 append=' '.join('console=ttyS0,115200' if x.startswith('console=') else 'earlycon=sbi' if x.startswith('earlycon=') else x for x in target_args.split())
if a.gui:
 append=' '.join(x for x in append.split() if not x.startswith('rdinit='))+' rdinit=/bin/sh'

cmd=[a.qemu,'-M','virt','-m','64M','-nographic','-bios',a.bios,'-kernel',a.kernel,'-initrd',a.initrd,'-append',append]
child=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
data=((('TARGET_BOOTARGS='+target_args+'\nQEMU_CONSOLE_ADAPTATION='+append+'\n') if target_args else '')).encode();sent=False;passed=False;deadline=time.monotonic()+90
try:
 while time.monotonic()<deadline:
  if not select.select([child.stdout],[],[],.2)[0]:
   if child.poll() is not None:break
   continue
  block=os.read(child.stdout.fileno(),65536)
  if not block:break
  data+=block
  pathlib.Path(a.log).write_bytes(data)
  if a.gui and not sent and b'# ' in data:
   child.stdin.write(b'mount -t devtmpfs devtmpfs /dev; mount -t proc proc /proc; mount -t sysfs sysfs /sys; /usr/bin/rv32-gui --headless /tmp/gui.rgb565 --frames 50 --fifo /tmp/gui-command; echo GUI_EXIT=$?; wc -c /tmp/gui.rgb565; sha256sum /tmp/gui.rgb565; echo RV32_QEMU_GUI_END\n');child.stdin.flush();sent=True
  if a.gui:
   if b'\r\nRV32_QEMU_GUI_END\r\n' in data:
    passed=b'GUI_EXIT=0\r\n' in data and b'460800 /tmp/gui.rgb565' in data;break
  elif b'RV32_LINUX_COMMANDS_END\r\n' in data:
   passed=b"can't open /dev/null" not in data and b'Run /init as init process' in data;break
finally:
 child.terminate()
 try:child.wait(timeout=5)
 except subprocess.TimeoutExpired:child.kill();child.wait()
 pathlib.Path(a.log).write_bytes(data)
print(('PASS' if passed else 'FAIL')+': QEMU virt software reference only; '+a.log)
raise SystemExit(0 if passed else 1)
