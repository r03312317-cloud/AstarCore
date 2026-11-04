# 快速上传保持原 W 协议不变，只把最多 64 个独立块连续交给主机串口发送。
# 每个块仍必须收到一个真实的 DDR 回读 K，批量发送并没有省略校验。
# 收到多余字节也视为协议失配，因为后续确认不能与前一批响应混淆。
# 开始上传前清理旧超时响应，并以 P 到 p 握手建立明确协议边界。
# 先导试写覆盖 8 16 32 64 块，由此确认当前链路能处理批量包。
# 正式固件从相同入口重新覆盖试写区域，试写数据不会成为 Linux 指令内容。
# 所有块成功后才发送 B，随后仍需检查启动 K 和真实 Linux 登录输出。
# 这不是提高 UART 波特率，115200 的物理配置保持原版不变。
"""Batch independent W packets, still requiring one real DDR readback ACK each.

The loader protocol and FPGA bitstream are unchanged. Only volatile DDR is
written. No boot command is sent unless every acknowledgement is verified.
"""
import argparse,hashlib,json,time
from pathlib import Path
import serial
from serial.tools import list_ports
from upload_boot import BUNDLE,LoginVerifier,packet,plan

# 发送一批 16 字节块，并要求每个块都有板卡 DDR 回读确认。
def send_batch(port,blocks,acks):
    if not blocks or len(blocks)>64:raise ValueError('Batch must contain 1..64 blocks')
    # data 保存本阶段处理的实际字节，是否为镜像或串口响应由调用接口决定。
    data=b''.join(packet(address,payload) for address,payload in blocks)
    # sent 保存主机串口报告的实际写入字节数，短写必须与计划长度比较。
    sent=port.write(data)
    if sent!=len(data):raise RuntimeError('Short serial write: %d/%d'%(sent,len(data)))
    # 等待当前主机串口发送缓冲提交；板卡是否处理成功仍由协议应答决定。
    port.flush()
    # response 保存串口返回的原始应答，长度和每个字节都需检查。
    response=port.read(len(blocks))
    # 保留板卡原始确认字节，报告中的成功块数可独立从原文件复核。
    acks.write(response);acks.flush()
    if len(response)!=len(blocks) or any(x!=0x4b for x in response):
        raise RuntimeError('Batch acknowledgement failure: %d/%d, bytes=%s' %
                           (len(response),len(blocks),response.hex()))
    if port.in_waiting:
        # extra 保存预期应答之外的串口字节，记录后按协议失配处理。
        extra=port.read(port.in_waiting);acks.write(extra);acks.flush()
        raise RuntimeError('Unexpected extra loader response: '+extra.hex())

# 等待并验证加载器握手，确认当前端口处于可上传固件的阶段。
def handshake(port,log):
    # A prior interrupted packet may time out and emit E. Leave the RX line idle
    # for >0.5 s, record/drain its response, then obtain an unambiguous P->p.
    time.sleep(1.2)
    # stale 保存开始本次握手前已存在的旧字节，单独记录并排空以避免阶段混淆。
    stale=port.read(port.in_waiting) if port.in_waiting else b''
    # 日志记录本次实际动作与结果，原始串口数据另存为字节文件。
    log.write('idle drain '+stale.hex()+'\n')
    # 检查实际写入字节数，短写不能当作完整命令或协议包发送成功。
    if port.write(b'P')!=1:raise RuntimeError('Short ping write')
    # reply 保存当前命令的原始返回值，不能把之前缓存的字节当作新应答。
    port.flush();reply=port.read(1)
    if reply!=b'p':raise RuntimeError('Loader ping response '+repr(reply))
    if port.in_waiting:raise RuntimeError('Unexpected bytes after ping')
    log.write('loader ping confirmed\n')

# 组织命令行入口或窗口生命周期；模块被导入时不自动开始板卡启动。
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',required=True)
    parser.add_argument('--log-dir',required=True,type=Path)
    parser.add_argument('--bundle',type=Path,default=BUNDLE)
    parser.add_argument('--batch-blocks',type=int,default=64)
    parser.add_argument('--capture-seconds',type=int,default=1200)
    parser.add_argument('--verify-login',action='store_true')
    args=parser.parse_args()
    if not 1<=args.batch_blocks<=64 or args.capture_seconds<1:parser.error('Invalid batch or capture limit')
    manifest,images=plan(args.bundle)
    # ports 保存当前匹配的设备集合，必须验证唯一 CP210x 而不是默认第一个端口。
    ports=[p for p in list_ports.comports() if p.device.upper()==args.port.upper()]
    if len(ports)!=1 or 'VID:PID=10C4:EA60' not in ports[0].hwid.upper():
        raise SystemExit('The expected CP210x port is not uniquely present')
    if args.log_dir.exists():raise SystemExit('Refusing to overwrite log directory')
    args.log_dir.mkdir(parents=True)
    # total 保存计划上传的块总数，完成条件要求实际确认计数与它精确相等。
    total=sum(x['padded_size']//16 for x in images)
    # summary 保存当前动作的元数据摘要，原始 UART 与确认字节保存在独立文件。
    summary={'bundle':str(args.bundle.resolve()),'cpu_hz':manifest['cpu_hz'],
             'timer_hz':manifest['timer_hz'],'images':[{k:v for k,v in x.items() if k!='data'} for x in images],
             'blocks':total,'batch_blocks':args.batch_blocks,'serial_device':args.port,
             'hardware_access_requested':True,'pilot_blocks':120}
    # f 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
    with (args.log_dir/'plan.json').open('x',encoding='utf-8') as f:json.dump(summary,f,indent=2);f.write('\n')
    # port 保存本会话持有的串口对象，退出时只释放这一句柄。
    port=serial.Serial(port=None,baudrate=115200,timeout=4,write_timeout=4)
    port.dtr=False;port.rts=False;port.port=args.port
    # started 保存单调时钟记录的阶段起点，用于耗时或超时判断。
    # count 保存已经通过本阶段检查的累计数量，不能在尚未确认前提前增加。
    # 以单调时钟判断本次传输的间隔或超时，不受电脑时区和时钟校准跳变影响。
    started=time.monotonic();count=0;next_report=4096
    # log 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
    # acks 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
    with (args.log_dir/'upload.log').open('x',encoding='utf-8',buffering=1) as log, \
         (args.log_dir/'ack.raw').open('xb') as acks:
        # 无论正常结束还是发生异常，finally 路径都负责释放此阶段打开的资源。
        try:
            port.open();handshake(port,log)
            # Pilot uses firmware start, which the real upload overwrites.
            # Increasing burst sizes checks this particular board/serial link.
            # pilot 保存已完成的先导试写数量，用于为下一批选择不重叠的测试地址。
            pilot=0
            for size in (8,16,32,64):
                # blocks 保存当前批次的地址及 16 字节数据列表，确认数量必须逐块对应。
                blocks=[]
                for j in range(size):
                    n=pilot+j
                    # payload 保存当前协议包的数据部分，须与相同地址一起参与校验。
                    payload=hashlib.sha256(('rv32-pilot-%d'%n).encode()).digest()[:16]
                    blocks.append((0x80000000+n*16,payload))
                # 本批每个 16 字节块均要求 DDR 回读确认，批处理只降低主机逐块往返开销。
                t=time.monotonic();send_batch(port,blocks,acks);elapsed=time.monotonic()-t
                log.write('pilot %d blocks readback verified in %.3f s\n'%(size,elapsed))
                print('pilot',size,'blocks verified in %.3f s'%elapsed,flush=True)
                pilot+=size
            # 逐份处理镜像 image，每份保留自己的物理地址 大小和哈希。
            # 只有整组镜像都完成当前校验阶段，外层流程才会继续启动。
            for image in images:
                data=image['data'].ljust(image['padded_size'],b'\0')
                log.write('upload %s addr=0x%08x bytes=%d sha256=%s\n' %
                          (image['file'],image['address'],image['size'],image['sha256']))
                # 循环位置 offset 按协议块或批次边界推进，尾部长度仍需落在对应缓冲范围。
                for offset in range(0,len(data),16*args.batch_blocks):
                    length=min(16*args.batch_blocks,len(data)-offset)
                    blocks=[(image['address']+offset+k,data[offset+k:offset+k+16])
                            for k in range(0,length,16)]
                    send_batch(port,blocks,acks);count+=len(blocks)
                    if count>=next_report or count==total:
                        log.write('verified blocks %d of %d\n'%(count,total))
                        print('verified blocks',count,'of',total,flush=True)
                        while next_report<=count:next_report+=4096
            if count!=total:raise RuntimeError('Incomplete block count')
            if port.write(b'B')!=1:raise RuntimeError('Short boot command')
            port.flush();reply=port.read(1)
            if reply!=b'K':raise RuntimeError('Boot acknowledgement '+repr(reply))
            log.write('boot acknowledged after %d verified blocks; elapsed %.3f s\n'%(count,time.monotonic()-started))
            # end 保存当前边界或截止时刻，必须与同一路径使用的单位保持一致。
            end=time.monotonic()+args.capture_seconds;port.timeout=0.1
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
                            for value in data:verifier.observe(value)
                            if verifier.phase=='done':break
            if verifier:
                # result 保存本阶段形成的结果记录，只有检查分支完成后才能据此报告成功。
                result=verifier.result()
                with (args.log_dir/'login_verification.json').open('x',encoding='utf-8') as f:
                    json.dump(result,f,indent=2);f.write('\n')
                if not result['passed']:raise RuntimeError('Linux login verification incomplete: '+json.dumps(result))
                log.write('verified Linux root shell and riscv32 uname\n')
            log.write('capture finished\n')
        except Exception as e:
            log.write('FAILED after %d blocks: %s\n'%(count,e))
            raise
        finally:
            # 释放本对象持有的串口句柄，不会因此切断板卡电源或清除 DDR。
            if port.is_open:port.close()
    return 0

if __name__=='__main__':raise SystemExit(main())
