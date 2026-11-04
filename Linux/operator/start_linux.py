# 可见控制台先创建窗口，再由用户点击开始或连接，启动动作不隐藏在后台自动进行。
# Tk 主线程处理界面，板卡工作由会话线程执行，并经事件队列传回文本和进度。
# 窗口下方单行输入框发送真实 Linux 命令，上方日志是来自 UART 的实际输出。
# ANSI 过滤只影响显示，不把预录内核信息插入板卡输出，也不是完整 VT 终端模拟器。
# 退出窗口应等待本会话释放串口；重新 attach 可以连接未断电且仍运行的 Linux。
"""Visible Windows operator console for the RV32 Linux demonstration."""
import codecs
import queue
import sys
import tkinter as tk
from tkinter import filedialog, ttk
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import backend

DEFAULT_PDS = r'D:\PDS_2025.2-ads-win64\pango\PDS_2025.2-ads\bin'


# 增量 UTF8 解码器跨读包保留状态，避免一个汉字分包时产生多次替换。
# ANSI 控制序列只在日志显示时过滤，原始串口字节另存。
class AnsiFilter:
    # 初始化本对象持有的状态，实际连接和加载时机由后续调用及用户动作决定。
    def __init__(self):
        self.decoder = codecs.getincrementaldecoder('utf-8')('replace')
        # self.state 保存ANSI 解码状态，跨两批串口数据时仍保留未结束的转义序列阶段。
        self.state = 'text'

    # 增量解码串口文字并过滤 ANSI 控制序列，保留来自板卡的实际文本。
    # UTF8 字符和 ANSI 序列都可能跨串口读取边界，所以解码器状态跨调用保留。
    # 过滤后的文本用于可见窗口，功能报告仍可回到 raw 文件检查原始字节。
    # 普通字符不经过替换成演示脚本的步骤，内核文字来自本次真实接收。
    def feed(self, data):
        # result 保存本阶段形成的结果记录，只有检查分支完成后才能据此报告成功。
        result = []
        for ch in self.decoder.decode(data):
            if self.state == 'escape':
                self.state = 'csi' if ch == '[' else 'text'
            elif self.state == 'csi':
                if '@' <= ch <= '~':
                    self.state = 'text'
            elif ch == '\x1b':
                self.state = 'escape'
            elif ch != '\r':
                result.append(ch)
        return ''.join(result)


# 可见窗口由用户控制加载和连接，运行前就能看到端口 配置 进度和日志。
# 本窗口提供单行命令输入，不是能完整渲染 vi 或全屏 top 的 VT 终端。
class Window:
    def __init__(self, root):
        self.root = root
        # 明确窗口身份，方便操作者定位本板的 Linux 控制台。
        self.root.title('RV32 RV32 Linux 串口控制台')
        self.root.geometry('1080x760')
        self.root.minsize(800, 560)
        # self.events 保存工作线程到主线程的消息队列，Tk 控件只由主线程消费这些消息。
        # 线程间信息通过队列传递，避免工作线程直接修改 Tk 控件。
        self.events = queue.Queue()
        # self.session 保存当前窗口启动或连接的工作会话，重新连接前要先收束旧会话。
        # 窗口只持有本次会话对象，停止或关闭时不应接管其他窗口的任务。
        self.session = None
        # self.ready 保存当前 Linux 命令行是否可交互的资格，不能由 FPGA DONE 单独推断。
        self.ready = False
        # self.closing 保存窗口关闭请求，先完成会话退出和串口释放再销毁 UI。
        self.closing = False
        # 每次新会话重置显示解码状态，避免上次未完成的转义序列影响新输出。
        self.ansi = AnsiFilter()
        self.status = tk.StringVar(value='准备就绪：选择串口后点击“一键加载并启动 Linux”')
        self.port = tk.StringVar()
        self.pds = tk.StringVar(value=DEFAULT_PDS)
        self.progress = tk.DoubleVar(value=0)

        outer = ttk.Frame(root, padding=12)
        outer.pack(fill='both', expand=True)
        ttk.Label(outer, text='RV32 RV32  |  Linux 串口控制台', font=('Microsoft YaHei UI', 15, 'bold')).pack(anchor='w')
        ttk.Label(outer, text='先显示此窗口，再由您操作启动；Linux 的实际启动输出会显示在下方。').pack(anchor='w', pady=(3, 9))
        # config 保存运行包配置，保存位流 固件和配套身份信息。
        config = ttk.Frame(outer)
        config.pack(fill='x', pady=(0, 6))
        ttk.Label(config, text='串口').grid(row=0, column=0, sticky='w')
        # 端口下拉框只展示已枚举的 CP210x，不将旧 COM14 硬编码为必然存在。
        self.port_box = ttk.Combobox(config, textvariable=self.port, state='readonly', width=14)
        self.port_box.grid(row=0, column=1, padx=(6, 5), sticky='w')
        self.refresh_button = ttk.Button(config, text='刷新', command=self.refresh_ports)
        self.refresh_button.grid(row=0, column=2, padx=(0, 14))
        ttk.Label(config, text='PDS 下载器目录').grid(row=0, column=3, sticky='w')
        ttk.Entry(config, textvariable=self.pds).grid(row=0, column=4, sticky='ew', padx=6)
        ttk.Button(config, text='选择目录', command=self.choose_pds).grid(row=0, column=5)
        config.columnconfigure(4, weight=1)

        actions = ttk.Frame(outer)
        actions.pack(fill='x', pady=(0, 6))
        # 此按钮执行完整 JTAG 加载及固件上传，适用于冷上电后的演示准备。
        self.boot_button = ttk.Button(actions, text='一键加载并启动 Linux', command=lambda: self.start('boot'))
        self.boot_button.pack(side='left', padx=(0, 8))
        # 此按钮只连接已运行系统，适用于关闭串口窗口后重新接入 Linux。
        self.attach_button = ttk.Button(actions, text='连接已运行的系统', command=lambda: self.start('attach'))
        self.attach_button.pack(side='left', padx=(0, 8))
        # 本地检查配套文件身份，按钮本身不代表实板功能已经验证。
        self.check_button = ttk.Button(actions, text='检查工程', command=self.check_kit)
        self.check_button.pack(side='left', padx=(0, 8))
        # 停止按钮收束本窗口任务并释放串口，不切断板卡供电。
        self.stop_button = ttk.Button(actions, text='断开 / 停止', command=self.stop, state='disabled')
        self.stop_button.pack(side='left')
        ttk.Label(outer, textvariable=self.status).pack(anchor='w', pady=(2, 4))
        ttk.Progressbar(outer, variable=self.progress, maximum=100).pack(fill='x', pady=(0, 7))

        log_frame = ttk.Frame(outer)
        log_frame.pack(fill='both', expand=True)
        # 日志区域只展示收到的字节和带工具标识的本地提示，避免混淆来源。
        self.log = tk.Text(log_frame, wrap='word', bg='#101923', fg='#deebf2', insertbackground='white',
                           font=('Consolas', 10), relief='flat')
        scroll = ttk.Scrollbar(log_frame, command=self.log.yview)
        self.log.configure(yscrollcommand=scroll.set, state='disabled')
        self.log.tag_configure('info', foreground='#75d7bd')
        self.log.tag_configure('error', foreground='#ff9090')
        self.log.pack(side='left', fill='both', expand=True)
        scroll.pack(side='right', fill='y')

        entryrow = ttk.Frame(outer)
        entryrow.pack(fill='x', pady=(8, 5))
        ttk.Label(entryrow, text='Linux 命令').pack(side='left', padx=(0, 8))
        # 单行输入框保留用户直接控制 shell 的入口，按回车或发送按钮提交。
        self.command = ttk.Entry(entryrow)
        self.command.pack(side='left', fill='x', expand=True)
        self.command.bind('<Return>', self.send)
        self.send_button = ttk.Button(entryrow, text='发送', command=self.send, state='disabled')
        self.send_button.pack(side='left', padx=(8, 4))
        # 中断按钮经真实 UART 发送 Ctrl C，供用户终止前台命令。
        self.break_button = ttk.Button(entryrow, text='中断 Ctrl+C', command=self.interrupt, state='disabled')
        self.break_button.pack(side='left')
        # 快捷按钮封装公开 shell 命令，操作者也能在输入框手动输入相同命令验证。
        shortcuts = ttk.Frame(outer)
        shortcuts.pack(fill='x')
        self.quick = []
        for text, command in [('系统版本', 'uname -a'), ('进程', 'ps'), ('首页', 'gui-command home'),
                              ('状态页', 'gui-command status'), ('开始计数', 'rv32-counter start'),
                              ('停止计数', 'rv32-counter stop'), ('登录 root', 'root')]:
            button = ttk.Button(shortcuts, text=text, command=lambda c=command: self.send_line(c), state='disabled')
            button.pack(side='left', padx=(0, 5))
            self.quick.append(button)
        self.append('info', '等待您的操作。连接板卡、JTAG、USB 串口和 HDMI 后，选择串口并点击启动。\n')
        self.append('info', '启动过程约需十几分钟；看到 Linux 的 login 提示后，输入 root。\n')
        # 接管本窗口关闭事件，先结束会话与释放句柄再销毁窗口。
        self.root.protocol('WM_DELETE_WINDOW', self.close)
        # 本调用是当前可见 Tk 窗口的事件处理回调，不创建系统或后台定时任务。
        self.root.after(100, self.refresh_ports)
        self.root.after(50, self.pump)

    # 将收到的文字追加到只读显示区，颜色标签仅用于区分提示和错误。
    # 主机显示过滤不修改 raw UART 证据文件。
    def append(self, kind, text):
        # 只有程序追加文本期间暂时开放写入，用户不能编辑上方输出冒充板卡返回。
        self.log.configure(state='normal')
        if kind in ('info', 'error') and self.log.index('end-1c') != '1.0' and self.log.get('end-2c', 'end-1c') != '\n':
            self.log.insert('end', '\n', kind)
        self.log.insert('end', text, kind if kind in ('info', 'error') else ())
        self.log.see('end')
        # 恢复日志只读显示，用户交互统一通过下方命令框。
        self.log.configure(state='disabled')

    # 刷新端口选择列表，由用户选择本次使用的实际设备。
    # 枚举不打开数据连接，也不向板卡发送握手或复位字符。
    # 只有一个合格设备时可预选，多个设备时保留用户自己选择的责任。
    def refresh_ports(self):
        try:
            # ports 保存当前匹配的设备集合，必须验证唯一 CP210x 而不是默认第一个端口。
            ports = backend.inventory()
            # 筛选本板常用 CP210x 硬件标识，多个匹配时由用户选择。
            eligible = [p['device'] for p in ports if 'VID:PID=10C4:EA60' in p['hwid'].upper()]
            self.port_box['values'] = eligible
            if self.port.get() not in eligible:
                self.port.set(eligible[0] if len(eligible) == 1 else '')
            self.append('info', '[工具] 检测到 CP210x 串口：' + (', '.join(eligible) if eligible else '无') + '\n')
        except Exception as exc:
            self.append('error', '[工具] 串口枚举失败：' + str(exc) + '\n')

    # 让用户指定本机 PDS 下载器目录，后续启动使用该路径。
    def choose_pds(self):
        path = filedialog.askdirectory(title='选择包含 cdt_js.exe 的 PDS bin 目录')
        if path:
            self.pds.set(path)

    # 执行本地工程身份检查，并把结果显示在用户可见窗口。
    # 检查只针对本地配套文件，不把硬件未连接伪装成已经通过板卡检查。
    def check_kit(self):
        try:
            _config, bit, _manifest, images = backend.validate_kit()
            # blocks 保存当前批次的地址及 16 字节数据列表，确认数量必须逐块对应。
            blocks = sum(item['padded_size'] // 16 for item in images)
            self.append('info', '[工具] 工程校验通过：位流 ' + bit.name + '，固件 %d 个数据块。\n' % blocks)
        except Exception as exc:
            self.append('error', '[工具] 工程校验失败：' + str(exc) + '\n')

    # 把工作线程消息排入窗口事件队列，不在工作线程直接操作 Tk 控件。
    def emit(self, kind, value):
        # 工作结果送入 UI 事件队列，由主线程更新可见窗口。
        self.events.put((kind, value))

    # 按用户选择启动完整加载或仅连接现有 Linux，会话在后台线程中推进。
    # 同一对象已有运行线程时拒绝再启动，避免本窗口重复持有同一个串口。
    # mode 由显式调用传入，完整加载与仅连接现有系统的行为在后端区分。
    def start(self, mode):
        if self.session and self.session.thread and self.session.thread.is_alive():
            return
        if not self.port.get():
            self.append('error', '[工具] 请选择 CP210x 串口。\n')
            return
        if mode == 'boot' and not Path(self.pds.get()).is_dir():
            self.append('error', '[工具] 请选择 PDS 下载器目录。\n')
            return
        self.ansi = AnsiFilter()
        # 上传进度在新动作开始时清零，不能沿用上次完成百分比。
        self.progress.set(0)
        self.boot_button.configure(state='disabled')
        self.attach_button.configure(state='disabled')
        self.check_button.configure(state='disabled')
        self.refresh_button.configure(state='disabled')
        self.stop_button.configure(state='normal')
        self.status.set('正在准备；请保持板卡供电并连接串口。')
        self.session = backend.Session(self.port.get(), self.pds.get(), self.emit)
        # 把用户选定的 boot 或 attach 模式传给同一后端，界面不自行生成 Linux 日志。
        self.session.start(mode)

    # 停止当前连接或加载工作，关闭本工具持有的串口；不代表板卡断电。
    def stop(self):
        if self.session:
            self.status.set('正在停止并释放串口……')
            self.session.close()

    # 同步输入框和发送按钮的可用状态，登录就绪前避免把普通 shell 命令送入加载器。
    # 快捷按钮和普通发送按钮使用相同 ready 资格，快捷操作也不绕过登录阶段。
    # 输入就绪后把焦点放到命令框，方便操作者独立执行现场命令。
    def input_state(self, ready):
        self.ready = ready
        # 输入可用性由会话事件更新，未到正确交互阶段时关闭发送按钮。
        state = 'normal' if ready else 'disabled'
        self.send_button.configure(state=state)
        self.break_button.configure(state=state)
        for button in self.quick:
            button.configure(state=state)
        if ready:
            self.command.focus_set()

    # 把输入框的一行命令交给串口节拍器，命令实际在 FPGA Linux 中执行。
    def send(self, _event=None):
        # 仅在 Linux 命令交互已就绪时允许发送普通用户命令。
        if not self.ready:
            return
        value = self.command.get()
        self.command.delete(0, 'end')
        self.send_line(value)

    # 用相同的逐字节回显节拍器发送快捷命令，快捷按钮也在板上 Linux 执行。
    # 此函数只把输入交给本会话节拍器，不在 Windows 上解释执行这条 shell 命令。
    def send_line(self, value):
        if not self.ready or not self.session:
            return
        try:
            self.session.submit(value)
        except Exception as exc:
            self.append('error', '[工具] ' + str(exc) + '\n')

    # 请求发送 Ctrl C 并取消待发送输入，供用户收回命令行控制。
    def interrupt(self):
        if self.ready and self.session:
            self.session.interrupt()
            self.append('info', '\n[工具] 已发送中断请求。\n')

    # 从事件队列取出会话消息，所有 Tk 文本 进度和按钮状态由此主线程更新。
    # 周期回调服务当前窗口的事件循环，不注册任何系统计划任务。
    # 工作线程结束和串口释放后才允许窗口完整关闭。
    # 进度事件以已经回读确认的块数为分子，和总计划块数形成百分比。
    # UART 事件按真实数据流送到增量解码器，工具提示则加上工具来源标识。
    # 窗口关闭请求不会直接销毁仍在工作线程使用的会话对象。
    def pump(self):
        try:
            while True:
                # 一次取出明确类型的事件，使 UART 原文 工具提示 上传进度和错误分别显示。
                kind, value = self.events.get_nowait()
                if kind == 'uart':
                    self.append('uart', self.ansi.feed(value))
                elif kind == 'progress':
                    # 进度条来自已确认块数，不以串口已写入字节数替代 DDR 回读完成数。
                    count, total = value
                    self.progress.set(100 * count / total)
                    self.status.set('固件回读校验：%d / %d（%.1f%%）' % (count, total, 100 * count / total))
                elif kind == 'info':
                    self.append('info', '[工具] ' + value + '\n')
                    self.status.set(value)
                # 失败状态在可见窗口保留，不能继续显示启动成功。
                elif kind == 'error':
                    self.append('error', '[工具] 错误：' + value + '\n')
                    self.status.set('操作未完成，请查看日志并按提示处理。')
                elif kind == 'ready':
                    self.input_state(bool(value))
                # 工作线程已经收束后重新开放连接按钮，避免同一窗口叠加占用串口。
                elif kind == 'finished':
                    self.boot_button.configure(state='normal')
                    self.attach_button.configure(state='normal')
                    self.check_button.configure(state='normal')
                    self.refresh_button.configure(state='normal')
                    self.stop_button.configure(state='disabled')
        except queue.Empty:
            pass
        # 窗口正在关闭时先收束自己的会话，再释放界面资源。
        if self.closing:
            if not self.session or not self.session.thread or not self.session.thread.is_alive():
                self.root.destroy()
                return
        self.root.after(50, self.pump)

    # 在退出窗口前请求会话停止，等待串口释放后再结束本工具。
    # 停止属于当前对象持有的工作范围，不复位板卡，也不宣称已经关闭 Linux 内核。
    # 完整释放结果由工作线程 finally 记录，调用 close 本身是提出停止意图。
    def close(self):
        self.closing = True
        if self.session:
            self.session.close()
            self.status.set('正在释放串口和本工具的下载器进程……')


# 组织命令行入口或窗口生命周期；模块被导入时不自动开始板卡启动。
def main():
    root = tk.Tk()
    Window(root)
    root.mainloop()


if __name__ == '__main__':
    main()
