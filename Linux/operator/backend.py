# 主机后端执行文件校验 JTAG 下载 DDR 上传和串口会话，Linux 本体始终运行在 FPGA 上。
# boot 模式完整加载，attach 模式只连接已经运行的系统；二者不能混为同一次冷启动。
# 所有固件块需要 DDR 回读确认，只有总数完整且用户未停止时才发出启动 B。
# 串口发送逐字节等待实际回显，配合板上浅接收缓冲，避免整行突发丢字。
# 原始串口 字节确认 下载日志和会话结果分别落盘，供事后核对证据来源。
# 用户取消只停止本次持有的子进程与串口，不表示 FPGA 断电或 Linux 自动关闭。
"""Board operations used by the operator's visible, user-controlled terminal."""
from __future__ import annotations

import hashlib
import json
import queue
import re
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'support'))
sys.path.insert(0, str(ROOT / 'vendor'))
import serial
from serial.tools import list_ports
from upload_boot_fast import handshake, send_batch
from upload_boot_gzip_fast import checked_plan

FLAGS = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


# 计算内容的 SHA256，作为交付文件或固件身份依据；不修改来源内容。
def sha(path):
    h = hashlib.sha256()
    # stream 以二进制读取原文件，哈希与结构判断基于实际字节。
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


# 枚举主机可见串口的设备名 描述和硬件标识，不打开串口数据连接。
def inventory():
    return [{'device': p.device, 'description': p.description, 'hwid': p.hwid}
            for p in list_ports.comports()]


# 要求目标为唯一匹配的 CP210x 端口，避免把数据发送到其他串口设备。
# 串口名称可能在重插 USB 后改变，所以不能仅凭上次使用 COM14 就直接打开。
# 硬件标识校验失败时返回可见错误，由操作者检查连接而不是尝试其他无关设备。
def validate_port(name):
    # ports 保存当前匹配的设备集合，必须验证唯一 CP210x 而不是默认第一个端口。
    ports = [p for p in inventory() if p['device'].upper() == name.upper()]
    if len(ports) != 1 or 'VID:PID=10C4:EA60' not in ports[0]['hwid'].upper():
        raise RuntimeError('找不到唯一的 CP210x 串口：' + name)
    return ports[0]


# 校验配套位流 固件清单及 27 MHz 配置，版本不一致时先终止启动流程。
# 位流路径先解析到本工程，再验证内容哈希，阻止同名文件被错误替换。
# 独立固件清单和镜像内容分别核验，清单自身的哈希也属于配套身份。
# CPU 时钟配置必须与本位流一致，27 MHz 的镜像不能直接按裸机 120 MHz 参数运行。
def validate_kit():
    # config 保存运行包配置，保存位流 固件和配套身份信息。
    # 显式读取工程元数据或脚本，不修改来源文件。
    config = json.loads((ROOT / 'kit.json').read_text(encoding='utf-8'))
    # bit 保存与清单配套的 FPGA 位流路径，功能身份由内容哈希确定。
    bit = (ROOT / config['bitstream']).resolve()
    # 校验解析后的路径仍位于工程目录，防止清单路径跳出配套文件范围。
    if not bit.is_relative_to(ROOT.resolve()) or not bit.is_file() or sha(bit) != config['bitstream_sha256']:
        raise RuntimeError('位流文件不存在或哈希不匹配，请检查交付包')
    # bundle 保存当前镜像集合的根目录，各镜像路径必须保持在该目录内。
    bundle = (ROOT / config['firmware']).resolve()
    if not bundle.is_relative_to(ROOT.resolve()):
        raise RuntimeError('固件路径无效')
    # manifest_path 保存实际固件清单路径，打开前后都要与工程范围和配套哈希核对。
    manifest_path = bundle / 'boot_manifest.json'
    # 核对当前文件内容的哈希，文件名或目录名相同不等于固件身份一致。
    if not manifest_path.is_file() or sha(manifest_path) != config.get('firmware_manifest_sha256'):
        raise RuntimeError('固件清单与位流配套信息不一致，请检查交付包')
    manifest, images = checked_plan(bundle)
    if manifest['cpu_hz'] != 27000000:
        raise RuntimeError('固件 CPU 时钟与本版位流不匹配')
    return config, bit, manifest, images


# 先完成 DDR 试写与回读，再逐批上传全部固件，只有全部确认后才发送 B。
# 主机进度只在 send batch 已经通过确认后增加，表示回读成功而非仅发送完成。
# 每个镜像按自身 padded size 切块，最后一块补零仍保留清单原始文件长度。
# 上传停止事件在先导和正式循环中都检查，已停止流程不会继续发送启动命令。
# 每次正式批次最多 64 块，CRC 与每块 K 仍逐一对应。
# B 发送后还需要一个独立启动确认，之后才开放启动日志阶段。
def send_firmware(port, images, stop, emit, log, acks, do_handshake=handshake):
    """Every payload block needs a DDR-readback ACK before B can be sent."""
    # total 保存计划上传的块总数，完成条件要求实际确认计数与它精确相等。
    total = sum(image['padded_size'] // 16 for image in images)
    if total <= 0:
        raise ValueError('No firmware blocks')
    do_handshake(port, log)
    # pilot 保存已完成的先导试写数量，用于为下一批选择不重叠的测试地址。
    pilot = 0
    # 先导批次逐步增加包数量，用真实回读检查当前板卡及串口链路。
    # 这些测试数据稍后由正式固件覆盖，不会作为内核代码启动。
    for size in (8, 16, 32, 64):
        # 停止请求优先于继续传输，未完成的数据不会触发后续启动命令。
        if stop.is_set():
            raise InterruptedError('用户停止；固件尚未启动')
        # blocks 保存当前批次的地址及 16 字节数据列表，确认数量必须逐块对应。
        blocks = [(0x80000000 + (pilot + j) * 16,
                   hashlib.sha256(('rv32-pilot-%d' % (pilot + j)).encode()).digest()[:16])
                  for j in range(size)]
        # 本批每个 16 字节块均要求 DDR 回读确认，批处理只降低主机逐块往返开销。
        send_batch(port, blocks, acks)
        pilot += size
    emit('info', 'DDR 试写回读通过，开始上传固件。')
    # count 保存已经通过本阶段检查的累计数量，不能在尚未确认前提前增加。
    count = 0
    last_report = 0
    # 逐份处理镜像 image，每份保留自己的物理地址 大小和哈希。
    # 只有整组镜像都完成当前校验阶段，外层流程才会继续启动。
    for image in images:
        # padded 保存按协议块大小补齐的数据，尾部填充不改变清单中的原始文件长度。
        padded = image['data'].ljust(image['padded_size'], b'\0')
        log.write('image %s address=0x%08x size=%d sha256=%s\n' %
                  (image['file'], image['address'], image['size'], image['sha256']))
        # 批次只改变主机发送粒度，不改变每个地址块的 CRC 和 DDR 回读要求。
        # 循环位置 off 按协议块或批次边界推进，尾部长度仍需落在对应缓冲范围。
        for off in range(0, len(padded), 16 * 64):
            if stop.is_set():
                raise InterruptedError('用户停止；固件未完成，不会发送启动命令')
            chunk = padded[off:off + 16 * 64]
            blocks = [(image['address'] + off + k, chunk[k:k + 16]) for k in range(0, len(chunk), 16)]
            send_batch(port, blocks, acks)
            count += len(blocks)
            if count - last_report >= 1024 or count == total:
                emit('progress', (count, total))
                last_report = count
    if count != total or stop.is_set():
        raise RuntimeError('固件传输不完整，不会发送启动命令')
    # B 是从加载器交接给 CPU 的最后命令。
    # 必须先确认所有镜像块数完整，不能凭上传进度条接近结束就提前发送。
    # 检查实际写入字节数，短写不能当作完整命令或协议包发送成功。
    if port.write(b'B') != 1:
        raise RuntimeError('启动命令发送失败')
    # 等待当前主机串口发送缓冲提交；板卡是否处理成功仍由协议应答决定。
    port.flush()
    # 启动 K 的确认与先前的块确认分开，避免把最后一个数据块应答误作启动应答。
    # 检查板卡实际返回的确认字节，空读或其他字符都不是成功确认。
    if port.read(1) != b'K':
        raise RuntimeError('启动命令未获板卡确认')
    # 日志记录本次实际动作与结果，原始串口数据另存为字节文件。
    log.write('boot acknowledged after %d verified blocks\n' % count)
    emit('info', '全部固件块已回读校验，已发送 Linux 启动命令。')
    return count


# 输入回显超时与整段启动失败分别处理，用户可以中断后重试命令。
class InputTimeout(Exception):
    pass


# 浅 UART 接收容量要求按回显节拍逐字节发送。
# 同一行内部只允许一个尚未确认字节，队列则保存后续待发送的行。
# Ctrl C 请求会先撤销本地未发完的命令，避免中断后继续补发旧行。
class EchoPacer:
    """Transmit one byte per echoed byte, protecting the shallow UART RX."""
    # 初始化本对象持有的状态，实际连接和加载时机由后续调用及用户动作决定。
    def __init__(self):
        # 线程间信息通过队列传递，避免工作线程直接修改 Tk 控件。
        self.lines = queue.Queue()
        # self.current 保存正在逐字节发送的命令行，和仍在队列中等待的其他命令分开。
        self.current = b''
        # self.index 保存当前命令已完成回显的字节位置，只有 observe 收到匹配值后推进。
        self.index = 0
        # self.expected 保存已经发送但仍在等真实回显的字节，未确认时不能继续发送下一字节。
        self.expected = None
        # self.sent_at 保存最近一个待确认字节的单调时间戳，用于输入回显超时判断。
        self.sent_at = 0.0
        # 用事件在界面与工作线程间传递停止或中断意图，工作线程自行收束持有资源。
        self.interrupt_requested = threading.Event()

    # 接收单行用户输入并排队，长度与换行检查在发到板卡之前完成。
    # 输入按 UTF8 编码，行末换行由此函数统一追加，避免重复发送多行控制内容。
    # 已排队和正在逐字节发送是两个状态，提交一行不会绕过回显节拍保护。
    def submit(self, text):
        if '\r' in text or '\n' in text:
            raise ValueError('一次只能输入一行')
        # data 保存本阶段处理的实际字节，是否为镜像或串口响应由调用接口决定。
        data = text.encode('utf-8') + b'\n'
        if len(data) > 2048:
            raise ValueError('命令行过长')
        self.lines.put(data)

    # 按回显节拍发送下一个字节，超时或人工中断会清理待发送命令。
    # 只要前一个字节仍有 expected，就不再向 UART 发送新字节。
    # 如果没有待发数据，函数立即返回，让同一会话循环继续接收板卡输出。
    # 回显等待使用单调时间，超时会取消当前行及后续排队内容。
    # 中断优先处理，先取消旧行再发送 Ctrl C，避免用户中断后又收到旧命令尾部。
    # 换行也是协议输入的一部分，它的发送和确认仍受该节拍器状态约束。
    def tick(self, port):
        if self.interrupt_requested.is_set():
            # 清除一次性中断意图，并取消尚未完成的本地行状态。
            self.interrupt_requested.clear()
            self.current = b''
            self.index = 0
            self.expected = None
            # 这里排空的是本节拍器的待发队列，板上 Linux 进程由真正的 Ctrl C 处理。
            while True:
                try:self.lines.get_nowait()
                except queue.Empty:break
            # Ctrl C 仍以真实串口字符送到板上 tty，主机不替代 Linux 实现信号语义。
            if port.write(b'\x03') != 1:
                raise RuntimeError('中断字符发送失败')
            port.flush()
            return
        # 已有未确认字节时等待串口真实回显，不能提前推进下一字符。
        if self.expected is not None:
            # 超时只说明这一字节没有及时得到预期回显，不能直接归因于 CPU 或 HDMI 故障。
            if time.monotonic() - self.sent_at > 15:
                self.current = b''
                self.index = 0
                self.expected = None
                while True:
                    try:self.lines.get_nowait()
                    except queue.Empty:break
                raise InputTimeout('串口输入回显超时；请先点“中断 Ctrl+C”，再检查 Linux 并重试。')
            return
        if self.index >= len(self.current):
            try:
                self.current = self.lines.get_nowait()
            except queue.Empty:
                return
            self.index = 0
        # 取出单个字节，发送前不会把整行剩余数据突发塞入板上 RX。
        value = self.current[self.index:self.index + 1]
        if port.write(value) != 1:
            raise RuntimeError('串口输入发送失败')
        port.flush()
        # 保存刚送出字节的数值，下一步 observe 以真实回显比较它。
        self.expected = value[0]
        # 以单调时钟判断本次传输的间隔或超时，不受电脑时区和时钟校准跳变影响。
        self.sent_at = time.monotonic()

    # 用真实串口回显确认前一字节已返回，从而推进下一字节发送。
    def observe(self, data):
        # 逐个处理 data 中的真实字节，协议状态不依据显示层解码后的字符串猜测。
        for byte in data:
            # 仅匹配当前等待字节才推进 index，其他输出仍保留在串口日志中。
            if self.expected is not None and byte == self.expected:
                self.index += 1
                self.expected = None


# 在独立无窗口子进程调用下载脚本，保存原始输出并检查退出和完成标记。
# PDS 的标准输出和错误汇入本阶段的新日志，保留原生命令执行证据。
# 进程退出后还扫描原生错误并查找指定完成标记，单一条件不足以确认下载成功。
# 用户停止或超时只终止这里创建的下载脚本进程，不枚举并终止其他窗口任务。
def run_tcl(bin_dir, script, logfile, stop, emit, marker):
    # stream 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
    with logfile.open('xb') as stream:
        process = subprocess.Popen([str(bin_dir / 'cdt_cfg_shell.exe'), '-file', str(script),
                                    '-work_dir', str(logfile.parent)],
                                   stdout=stream, stderr=subprocess.STDOUT, creationflags=FLAGS)
        # start 保存本阶段的起始时刻或放置基址，具体单位以当前表达式及调用点为准。
        start = time.monotonic()
        while process.poll() is None:
            if stop.is_set():
                process.terminate()
                process.wait(timeout=10)
                raise InterruptedError('用户停止 JTAG 操作')
            # 下载脚本使用有界等待，超时后只结束本次创建的下载子进程。
            if time.monotonic() - start > 240:
                process.terminate()
                process.wait(timeout=10)
                raise RuntimeError('JTAG 命令超时')
            time.sleep(.2)
    text = logfile.read_text(encoding='utf-8', errors='replace')
    errors = re.findall(r'(?m)^\s*(?:E:|ERROR\b|FATAL\b)[^\r\n]*', text)
    # 根据真实完成标记判断阶段是否完成，不能只凭进程没有报错就确认功能。
    if process.returncode or errors or marker not in text:
        raise RuntimeError('JTAG 操作失败，请查看 ' + str(logfile))
    return text


# 识别 PDS 下载器及目标器件，再向 FPGA 易失 SRAM 加载配套位流。
# 必须检查真实 JTAG ID 完成标记和 DONE 状态；只启动下载进程不构成成功。
# 此函数没有写入非易失 Flash，断电后仍需重新配置。
# 下载服务使用本地回环地址及本次分配的端口，不连接远程硬件服务。
# 实际服务端口从原生日志读取，不能在启动服务之前假定连接已经建立。
# 扫描链只有一个 PG2L200H 且 ID 为 0x00603899 时才接受目标身份。
# 位流路径使用 Tcl 花括号引用，不接受可能改变脚本结构的特殊字符。
# 下载成功必须同时满足原生 program 成功记录和最终 DONE 为一。
# 函数退出时回收本次 JTAG 服务，Linux 之后通过独立 UART 会话运行。
def program_sram(bit, bin_dir, out, stop, emit):
    shell, server_exe = bin_dir / 'cdt_cfg_shell.exe', bin_dir / 'cdt_js.exe'
    if not shell.is_file() or not server_exe.is_file():
        raise RuntimeError('PDS 下载器目录无效；需包含 cdt_js.exe 和 cdt_cfg_shell.exe')
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        # port 保存本会话持有的串口对象，退出时只释放这一句柄。
        port = sock.getsockname()[1]
    server = None
    # serverlog 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
    with (out / 'jtag_server.log').open('xb') as serverlog:
        try:
            server = subprocess.Popen([str(server_exe), '-port', str(port), '-work_dir', str(out)],
                                      stdout=serverlog, stderr=subprocess.STDOUT, creationflags=FLAGS)
            deadline = time.monotonic() + 25
            actual = None
            while time.monotonic() < deadline:
                if stop.is_set():
                    raise InterruptedError('用户停止')
                data = (out / 'jtag_server.log').read_text(encoding='utf-8', errors='replace')
                match = re.search(r'To connect this JtagServer instance use port\s*:\s*(\d+)', data)
                if match:
                    actual = int(match.group(1))
                    break
                if server.poll() is not None:
                    raise RuntimeError('JTAG 服务提前退出')
                time.sleep(.2)
            if actual is None:
                raise RuntimeError('JTAG 服务启动超时')
            prefix = ('cfg_set_tcl_break -flag true\n'
                      f'cfg_connect -ip 127.0.0.1 -port {actual}\n'
                      'cfg_set_cable_property -index 0 -freq 5MHz\ncfg_scan_chain\n')
            scan = out / 'identify.tcl'
            scan.write_text(prefix + 'cfg_read_device_property -mode 0 -device_index 0\n'
                            'cfg_disconnect\nputs ID_COMPLETE\n', encoding='utf-8')
            emit('info', '正在识别 JTAG 器件……')
            text = run_tcl(bin_dir, scan, out / 'identify.log', stop, emit, 'ID_COMPLETE')
            # 同时核对器件名称和 JTAG ID，防止下载到链上错误目标。
            devices = re.findall(r'^PG2L200H\s*$', text, re.M)
            identities = re.findall(r'The ID value is:\s*(0x[0-9a-fA-F]+)', text)
            # DONE 由下载器真实读回，不能仅凭 cfg program 被调用就宣称位流已生效。
            done = re.findall(r'This device configure situation \(done bit\):\s*([01])', text)
            if len(devices) != 1 or len(identities) != 1 or int(identities[0], 16) != 0x00603899 or len(done) != 1:
                raise RuntimeError('JTAG 链或器件 ID 不符合 PG2L200H')
            path = bit.as_posix()
            if any(c in path for c in '{}\r\n'):
                raise ValueError('位流路径含 Tcl 不支持的字符')
            program = out / 'program.tcl'
            program.write_text(prefix + 'cfg_assign_file -file {' + path + '} -device_index 0\n'
                               'cfg_set_device_property -device_index 0 -program 1\n'
                               'cfg_program -device_index 0\ncfg_scan_chain\n'
                               'cfg_disconnect\nputs PROGRAM_COMPLETE\n', encoding='utf-8')
            emit('info', '器件识别通过，正在加载 FPGA 位流……')
            text = run_tcl(bin_dir, program, out / 'program.log', stop, emit, 'PROGRAM_COMPLETE')
            done = re.findall(r'This device configure situation \(done bit\):\s*([01])', text)
            if 'cfg_program -device_index 0 successfully' not in text or not done or done[-1] != '1':
                raise RuntimeError('未确认 FPGA 位流下载成功及 DONE=1')
            emit('info', 'FPGA 位流加载成功，DONE=1。')
        finally:
            if server is not None and server.poll() is None:
                server.terminate()
                try:server.wait(timeout=6)
                except subprocess.TimeoutExpired:server.kill();server.wait(timeout=6)


# Session 只管理本窗口的一次启动或连接。
# 它持有工作线程 停止事件 回显节拍器和日志目录，释放时不停止其他窗口任务。
class Session:
    def __init__(self, port_name, bin_dir, emit):
        self.port_name = port_name
        self.bin_dir = Path(bin_dir)
        self.emit = emit
        # self.stop 保存本会话的停止请求，工作线程检查后负责安全结束本会话。
        self.stop = threading.Event()
        self.pacer = EchoPacer()
        self.thread = None
        # 窗口只持有本次会话对象，停止或关闭时不应接管其他窗口的任务。
        self.session_dir = None

    # 按用户选择启动完整加载或仅连接现有 Linux，会话在后台线程中推进。
    # 同一对象已有运行线程时拒绝再启动，避免本窗口重复持有同一个串口。
    # mode 由显式调用传入，完整加载与仅连接现有系统的行为在后端区分。
    def start(self, mode):
        if self.thread and self.thread.is_alive():
            raise RuntimeError('当前会话尚未结束')
        self.thread = threading.Thread(target=self._run, args=(mode,), daemon=True)
        self.thread.start()

    def submit(self, line):
        self.pacer.submit(line)

    # 在退出窗口前请求会话停止，等待串口释放后再结束本工具。
    # 停止属于当前对象持有的工作范围，不复位板卡，也不宣称已经关闭 Linux 内核。
    # 完整释放结果由工作线程 finally 记录，调用 close 本身是提出停止意图。
    def close(self):
        self.stop.set()

    # 请求发送 Ctrl C 并取消待发送输入，供用户收回命令行控制。
    def interrupt(self):
        self.pacer.interrupt_requested.set()

    # 会话线程按 boot 或 attach 模式执行，并把进度与真实 UART 字节交给主线程。
    # boot 才执行 JTAG 和固件上传，attach 连接现有系统时不重置运行中的 Linux。
    # finally 负责关闭本会话持有的串口并记录释放状态。
    # 先打开串口并建立原始证据文件，再执行加载，因此能从启动最早阶段保存 UART。
    # 位流在下载前后都重新核对哈希，期间变化会阻止继续上传固件。
    # 首次 boot 等待 login 或 shell 提示符，提示可能跨多次串口读取到达。
    # 输入回显超时只报告输入问题，会话仍可接收并展示板卡输出。
    # 最终结果分别记录异常 中断 启动确认和串口释放，不能把窗口退出等同于测试全通过。
    def _run(self, mode):
        port = None
        # result 保存本阶段形成的结果记录，只有检查分支完成后才能据此报告成功。
        result = {'mode': mode, 'port': self.port_name, 'boot_acknowledged': False,
                  'interrupted': False, 'error': None}
        # 无论正常结束还是发生异常，finally 路径都负责释放此阶段打开的资源。
        try:
            validate_port(self.port_name)
            if mode == 'boot':
                _config, bit, _manifest, images = validate_kit()
            runs = ROOT / 'runs'
            runs.mkdir(exist_ok=True)
            self.session_dir = runs / datetime.now().strftime('%Y%m%d_%H%M%S_%f')
            self.session_dir.mkdir()
            self.emit('info', '本次日志目录：' + str(self.session_dir))
            port = serial.Serial(port=None, baudrate=115200, timeout=4, write_timeout=4)
            # 避免打开串口时主动拉动 DTR；是否实际复位仍由板卡连接方式决定。
            port.dtr = False
            # 本板以软件回显节拍配合接收缓冲，不启用主机 RTS 硬件流控。
            port.rts = False
            port.port = self.port_name
            port.open()
            # log 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
            # acks 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
            # uart 以独占新建方式保存本次结果，已有日志不会被本次运行静默覆盖。
            with (self.session_dir / 'operator.log').open('x', encoding='utf-8', buffering=1) as log, \
                 (self.session_dir / 'ack.raw').open('xb') as acks, \
                 (self.session_dir / 'uart.raw').open('xb') as uart:
                if mode == 'boot':
                    if sha(bit) != _config['bitstream_sha256']:
                        raise RuntimeError('位流在下载前发生变化；已停止启动')
                    program_sram(bit, self.bin_dir, self.session_dir, self.stop, self.emit)
                    if sha(bit) != _config['bitstream_sha256']:
                        raise RuntimeError('位流在下载期间发生变化；未上传固件')
                    result['verified_blocks'] = send_firmware(port, images, self.stop, self.emit, log, acks)
                    result['boot_acknowledged'] = True
                    self.emit('info', '正在启动 Linux；串口输入将在出现登录提示后开放。')
                else:
                    self.emit('info', '串口已连接；按回车可请求现有 Linux 提示符。')
                port.timeout = .1
                # attach 假定用户连接的是现有系统，boot 则等待真实登录提示后开放输入。
                terminal_ready = mode != 'boot'
                # 保留有限末尾文本用于识别 login 或 shell 提示符，原始 UART 文件仍保存全部字节。
                tail = bytearray()
                if terminal_ready:
                    self.emit('ready', True)
                while not self.stop.is_set():
                    try:
                        self.pacer.tick(port)
                    except InputTimeout as error:
                        log.write('input echo timeout: ' + str(error) + '\n')
                        self.emit('error', str(error))
                    data = port.read(min(4096, max(1, port.in_waiting)))
                    if data:
                        # 记录实际收到的串口字节，不以显示过滤后的文本替代原始证据。
                        uart.write(data);uart.flush()
                        self.pacer.observe(data)
                        self.emit('uart', data)
                        if not terminal_ready:
                            # 提示符可能跨多次串口读取返回，拼接末尾后再检测才能正确识别。
                            tail.extend(data)
                            if len(tail) > 4096:
                                # 限制提示符检测窗口的内存，不截断另存的原始串口证据。
                                del tail[:-4096]
                            if b'rv32 login:' in tail or re.search(rb'(?:^|[\r\n])# $', tail):
                                terminal_ready = True
                                self.emit('ready', True)
                                self.emit('info', '终端提示符已出现；若提示 login，请输入 root 并回车。')
        except InterruptedError as error:
            result['interrupted'] = True
            result['error'] = str(error)
            self.emit('info', str(error))
        except Exception as error:
            result['error'] = str(error)
            self.emit('error', str(error))
        finally:
            if port is not None and port.is_open:
                # 释放本对象持有的串口句柄，不会因此切断板卡电源或清除 DDR。
                port.close()
            if self.session_dir is not None:
                # 释放状态根据实际串口对象是否打开形成，不能只记录窗口已经关闭。
                result['serial_released'] = not port or not port.is_open
                try:
                    with (self.session_dir / 'session_result.json').open('x', encoding='utf-8') as stream:
                        json.dump(result, stream, ensure_ascii=False, indent=2)
                        stream.write('\n')
                except OSError as error:
                    self.emit('error', '会话结果保存失败：' + str(error))
            self.emit('ready', False)
            self.emit('finished', None)
