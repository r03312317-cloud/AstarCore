# 加载基础协议实现以 16 字节块为单位，CRC 同时覆盖地址和数据。
# 镜像大小 地址 重叠范围及哈希都在发往板卡之前校验，不能只依赖文件名。
# 根文件系统检查还拒绝自动启动的定时服务，符合本工程禁用系统定时任务的约定。
# 登录验证器根据真实收到的串口文字推进阶段，不把发送命令等同于执行成功。
# OpenSBI 先在 M 模式运行，再跳转到 S 模式 Linux；它们的启动文字属于不同软件阶段。
# UART 原始数据保存为字节证据，显示层解码或过滤不能替代这份原文件。
# 本工具源码导入时不会自行打开板卡端口，实际连接来自显式 main 调用。
"""Verify a board bundle, upload each 16-byte DDR block and start the CPU.

No serial port is opened with --dry-run. This protocol writes volatile DDR,
not FPGA configuration flash. A block is acknowledged only after DDR readback.
"""
import argparse
import hashlib
import json
import re
import struct
import time
import zlib
from pathlib import Path

ROOT=Path(__file__).resolve().parent
BUNDLE=ROOT/'firmware/headless27_nocron'
RAM_START=0x80000000
RAM_END=0x84000000

# 解析实际 initramfs 并检查会自动启动的服务，禁止定时服务被重新带入运行镜像。
# 这是本地固件内容检查，不创建或运行任何定时任务。
def check_no_scheduled_services(data):
    """Reject a boot archive that starts cron or an at daemon automatically."""
    # pos 保存结构解析游标，每次推进要包含格式要求的头部和对齐填充。
    pos=0; checked=0; cron_script=None
    while pos+110<=len(data):
        if data[pos:pos+6] not in (b'070701',b'070702'):
            raise ValueError('Invalid initramfs CPIO format')
        fields=[int(data[pos+6+i*8:pos+14+i*8],16) for i in range(13)]
        size,namesize=fields[6],fields[11]
        n=pos+110
        if namesize<1 or n+namesize>len(data):raise ValueError('Bad CPIO member name')
        name=data[n:n+namesize-1].decode('utf-8').removeprefix('./')
        # start 保存本阶段的起始时刻或放置基址，具体单位以当前表达式及调用点为准。
        # end 保存当前边界或截止时刻，必须与同一路径使用的单位保持一致。
        start=(n+namesize+3)&~3;end=start+size
        if end>len(data):raise ValueError('Truncated CPIO member')
        pos=(end+3)&~3
        if name=='TRAILER!!!':break
        if name=='init' or name=='etc/inittab' or name.startswith('etc/init.d/S'):
            body=data[start:end]
            if name=='etc/init.d/S50crond':cron_script=body
            for line in body.splitlines():
                if line.lstrip().startswith(b'#'):continue
                if re.search(rb'\b(?:crond|crontab|atd)\b',line):
                    raise ValueError('Scheduled service referenced in startup file: '+name)
            checked+=1
    else:raise ValueError('Missing CPIO trailer')
    if checked<3 or cron_script is None or not cron_script.startswith(b'#!/bin/sh\n# Scheduled task service intentionally disabled.\nexit 0\n'):
        raise ValueError('Expected inert cron startup script not found')

# 将地址 数据和 CRC 组成加载协议包，保持与 RTL 字节顺序一致。
# 地址字段采用小端字节序，必须与加载 RTL 接收次序一致。
# CRC 的输入含地址，因此把正确数据写到错误地址也不会被当作同一个包。
# 要求 payload 正好覆盖 16 字节，长度变化不能静默改变 RTL 包边界。
def packet(address, payload):
    if len(payload)!=16 or address%16 or not RAM_START<=address<=RAM_END-16:
        raise ValueError('Each block must be aligned and inside the 64 MiB RAM window')
    body=struct.pack('<I',address)+payload
    return b'W'+body+struct.pack('<I',zlib.crc32(body)&0xffffffff)

# 核对镜像哈希 大小 对齐和物理地址范围，返回可按顺序上传的数据块计划。
# 同一地址窗口不能被两个镜像意外重叠，framebuffer 保留区也不能被 rootfs 越界覆盖。
# 每个镜像先按原始字节核对哈希，补齐只用于传输分块。
# 地址排序和结束位置检查可发现重叠或越界，不能用文件列表顺序替代。
# 计划生成不打开串口，真正数据发送是后续明确执行的阶段。
def plan(bundle):
    # manifest 保存待校验的镜像元数据，不能把其中的名称当成内容已经可信。
    # 显式读取工程元数据或脚本，不修改来源文件。
    manifest=json.loads((bundle/'boot_manifest.json').read_text(encoding='utf-8'))
    if manifest.get('cron_daemon_auto_start') is not False:
        raise ValueError('Bundle does not explicitly disable the scheduled-task daemon')
    # images 保存已经解析的镜像列表，包含放置地址 大小 哈希及真实数据。
    images=[]
    # 逐份处理镜像 row，每份保留自己的物理地址 大小和哈希。
    # 只有整组镜像都完成当前校验阶段，外层流程才会继续启动。
    for row in manifest['images']:
        name=row['file']
        if Path(name).name!=name:raise ValueError('Unsafe image file name')
        # data 保存本阶段处理的实际字节，是否为镜像或串口响应由调用接口决定。
        data=(bundle/name).read_bytes();addr=int(row['address'],0)
        if len(data)!=row['size'] or hashlib.sha256(data).hexdigest()!=row['sha256']:
            raise ValueError('Image hash/size mismatch: '+name)
        # padded 保存按协议块大小补齐的数据，尾部填充不改变清单中的原始文件长度。
        padded=(len(data)+15)&~15
        if addr%16 or addr<RAM_START or addr+padded>RAM_END:raise ValueError('Image outside RAM: '+name)
        images.append(dict(file=name,address=addr,size=len(data),padded_size=padded,
                           sha256=row['sha256'],data=data))
        if name=='rootfs.cpio':check_no_scheduled_services(data)
    ordered=sorted(images,key=lambda x:x['address'])
    if sum(x['file']=='rootfs.cpio' for x in images)!=1:
        raise ValueError('Exactly one checked initramfs is required')
    for a,b in zip(ordered,ordered[1:]):
        if a['address']+a['padded_size']>b['address']:raise ValueError('Image ranges overlap')
    if not images or images[0]['address']!=RAM_START:raise ValueError('Reset firmware missing')
    return manifest,images

# 等待加载器返回确认字节，其他字符或超时都必须走错误路径。
def ack(port, command, expected):
    # response 保存串口返回的原始应答，长度和每个字节都需检查。
    # 等待当前主机串口发送缓冲提交；板卡是否处理成功仍由协议应答决定。
    port.write(command);port.flush();response=port.read(1)
    if response!=expected:raise RuntimeError('Loader response %r, expected %r' % (response,expected))

class LoginVerifier:
    """Wait for the real getty, then send each character only after echo."""
    # 初始化本对象持有的状态，实际连接和加载时机由后续调用及用户动作决定。
    def __init__(self, port):
        # self.index 保存当前命令已完成回显的字节位置，只有 observe 收到匹配值后推进。
        self.port=port;self.phase='login';self.tail=bytearray();self.index=0;self.sequence=b''
        self.login_prompt_seen=False;self.root_prompt_seen=False
        self.uname_riscv32_seen=False;self.marker_seen=False;self.shell_prompt_returned=False

    # 登录检查进入命令回显验证阶段，后续结果依赖真实接收字节。
    def start_echo(self, sequence, phase):
        self.sequence=sequence;self.index=0;self.phase=phase;self.tail.clear()
        self.port.write(sequence[:1]);self.port.flush()

    # 根据收到的真实串口字节识别启动 登录和命令完成阶段，不把主机发出命令等同于板卡执行成功。
    def observe(self, byte):
        if self.phase in ('root_echo','command_echo'):
            if byte==self.sequence[self.index]:
                self.index+=1
                if self.index<len(self.sequence):
                    self.port.write(self.sequence[self.index:self.index+1]);self.port.flush()
                else:
                    self.phase='root_prompt' if self.phase=='root_echo' else 'result'
                    self.tail.clear()
            return
        self.tail.append(byte)
        if len(self.tail)>16384:del self.tail[:-16384]
        if self.phase=='login' and self.tail.endswith(b'rv32 login:'):
            self.login_prompt_seen=True;self.start_echo(b'root\n','root_echo')
        elif self.phase=='root_prompt' and self.tail.endswith(b'# '):
            self.root_prompt_seen=True
            self.start_echo(b'uname -a; echo RV32_BOARD_CHECK\n','command_echo')
        elif self.phase=='result':
            self.uname_riscv32_seen=bool(re.search(rb'Linux [^\r\n]*riscv32',self.tail))
            self.marker_seen=b'RV32_BOARD_CHECK' in self.tail
            # 根据真实完成标记判断阶段是否完成，不能只凭进程没有报错就确认功能。
            if self.uname_riscv32_seen and self.marker_seen and self.tail.endswith(b'# '):
                self.shell_prompt_returned=True;self.phase='done'

    # 汇总已观察到的登录阶段，不把未完成步骤默认为成功。
    def result(self):
        flags={k:getattr(self,k) for k in ('login_prompt_seen','root_prompt_seen',
              'uname_riscv32_seen','marker_seen','shell_prompt_returned')}
        return dict(flags,passed=all(flags.values()),phase=self.phase)

# 组织命令行入口或窗口生命周期；模块被导入时不自动开始板卡启动。
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--bundle',type=Path,default=BUNDLE)
    ap.add_argument('--port')
    ap.add_argument('--baud',type=int,default=115200)
    ap.add_argument('--capture-seconds',type=int,default=600)
    ap.add_argument('--verify-login',action='store_true',
                    help='log in as root after the actual getty prompt and verify uname via echo-paced UART')
    ap.add_argument('--log-dir',type=Path)
    ap.add_argument('--dry-run',action='store_true')
    args=ap.parse_args()
    if args.capture_seconds<1:ap.error('--capture-seconds must be positive')
    manifest,images=plan(args.bundle)
    # summary 保存当前动作的元数据摘要，原始 UART 与确认字节保存在独立文件。
    summary={'bundle':str(args.bundle.resolve()),'cpu_hz':manifest['cpu_hz'],
             'timer_hz':manifest['timer_hz'],'images':[ {k:v for k,v in x.items() if k!='data'} for x in images],
             'blocks':sum(x['padded_size']//16 for x in images),
             'serial_bytes_to_board':sum(x['padded_size']//16*25 for x in images)+2,
             'hardware_access_requested':not args.dry_run}
    print(json.dumps(summary,indent=2),flush=True)
    if args.dry_run:return 0
    if not args.port or not args.log_dir:ap.error('--port and a fresh --log-dir are required for hardware')
    if args.log_dir.exists():raise SystemExit('Refusing to overwrite log directory')
    try:import serial
    except ImportError as e:raise SystemExit('pyserial is required for real UART access') from e
    args.log_dir.mkdir(parents=True,exist_ok=False)
    # f 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
    with (args.log_dir/'plan.json').open('x',encoding='utf-8') as f:json.dump(summary,f,indent=2);f.write('\n')
    # port 保存本会话持有的串口对象，退出时只释放这一句柄。
    port=serial.Serial(port=None,baudrate=args.baud,timeout=3,write_timeout=3)
    port.dtr=False;port.rts=False;port.port=args.port
    # count 保存已经通过本阶段检查的累计数量，不能在尚未确认前提前增加。
    # 以单调时钟判断本次传输的间隔或超时，不受电脑时区和时钟校准跳变影响。
    start=time.monotonic();count=0
    # log 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
    with (args.log_dir/'upload.log').open('x',encoding='utf-8',buffering=1) as log:
        # 无论正常结束还是发生异常，finally 路径都负责释放此阶段打开的资源。
        try:
            port.open();port.reset_input_buffer();ack(port,b'P',b'p')
            # 逐份处理镜像 image，每份保留自己的物理地址 大小和哈希。
            for image in images:
                data=image['data'].ljust(image['padded_size'],b'\0')
                log.write('upload %s addr=0x%08x bytes=%d sha256=%s\n' %
                          (image['file'],image['address'],image['size'],image['sha256']))
                # 循环位置 offset 按协议块或批次边界推进，尾部长度仍需落在对应缓冲范围。
                for offset in range(0,len(data),16):
                    ack(port,packet(image['address']+offset,data[offset:offset+16]),b'K')
                    count+=1
                    if count%8192==0:
                        print('verified blocks',count,'of',summary['blocks'],flush=True)
                        # 日志记录本次实际动作与结果，原始串口数据另存为字节文件。
                        log.write('verified blocks %d\n' % count)
            ack(port,b'B',b'K')
            log.write('boot command acknowledged; elapsed %.3f seconds\n' % (time.monotonic()-start))
            end=time.monotonic()+args.capture_seconds
            port.timeout=0.1
            # verifier 保存根据真实字节推进的登录状态检查器，不替代 Linux 进程本身。
            verifier=LoginVerifier(port) if args.verify_login else None
            # capture 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
            with (args.log_dir/'uart.raw').open('xb') as capture:
                while time.monotonic()<end:
                    data=port.read(min(4096,max(1,port.in_waiting)))
                    if data:
                        capture.write(data);capture.flush()
                        if verifier:
                            # 逐个处理 data 中的真实字节，协议状态不依据显示层解码后的字符串猜测。
                            for byte in data:verifier.observe(byte)
                            if verifier.phase=='done':break
            if verifier:
                # result 保存本阶段形成的结果记录，只有检查分支完成后才能据此报告成功。
                result=verifier.result()
                with (args.log_dir/'login_verification.json').open('x',encoding='utf-8') as f:
                    json.dump(result,f,indent=2);f.write('\n')
                if not result['passed']:raise RuntimeError('Linux login verification incomplete: '+json.dumps(result))
                log.write('verified real Linux root shell and riscv32 uname\n')
            log.write('capture finished\n')
        except Exception as error:
            log.write('FAILED: %s\n' % error)
            raise
        finally:
            # 释放本对象持有的串口句柄，不会因此切断板卡电源或清除 DDR。
            if port.is_open:port.close()
    return 0

if __name__=='__main__':raise SystemExit(main())
