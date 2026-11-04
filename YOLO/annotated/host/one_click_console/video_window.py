# 架构导读：video_window。
# 本机 Tk 操作窗口，通过后台执行线程和队列显示真实传输与识别数据。
"""Dedicated native serial work window. Opening it does not program the board."""
import argparse
import ctypes
import os
from pathlib import Path
import queue
import threading
import time
import tkinter as tk
from tkinter import ttk

from video_runner import HERE, Runner, ports

# 维护本地状态/计算值：BG = '#F1F3EE'。
BG = '#F1F3EE'
# 维护本地状态/计算值：INK = '#19352D'。
INK = '#19352D'
# 维护本地状态/计算值：MUTED = '#6B7F76'。
MUTED = '#6B7F76'
# 维护本地状态/计算值：DARK = '#172B25'。
DARK = '#172B25'
# 维护本地状态/计算值：ACCENT = '#B8EA77'。
ACCENT = '#B8EA77'
# 维护本地状态/计算值：LINE = '#D9E1D7'。
LINE = '#D9E1D7'
# 维护本地状态/计算值：TEAL = '#22735A'。
TEAL = '#22735A'
# 维护本地状态/计算值：STEPS = ['文件与依赖检查', '连接开发板', '烧录 FPGA', '固件启动校验',。
STEPS = ['文件与依赖检查', '连接开发板', '烧录 FPGA', '固件启动校验',
         'DDR 读写检查', '模型传输与校验', '实时视频识别', '确认停止']
# 维护本地状态/计算值：LABELS = ['握拳', '单指', 'V 字', '三指', '四指', '张掌']。
LABELS = ['握拳', '单指', 'V 字', '三指', '四指', '张掌']


# 对象 VideoWindow 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class VideoWindow:
    # 接口 __init__，显式输入字段：seconds。
    # 本函数调用入口包括 tk.Tk, self.root.title, max, min, self.root.geometry。
    def __init__(self, seconds=None):
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            pass
        # 维护本地状态/计算值：self.root = tk.Tk()。
        self.root = tk.Tk()
        self.root.title('YOLO · 一键上板识别展示')
        # 维护本地状态/计算值：scale = max(1.0, float(self.root.tk.call('tk', 'scaling'))/(96/72))。
        scale = max(1.0, float(self.root.tk.call('tk', 'scaling'))/(96/72))
        # 维护本地状态/计算值：width = min(round(1180*scale), self.root.winfo_screenwidth()-70)。
        width = min(round(1180*scale), self.root.winfo_screenwidth()-70)
        # 维护本地状态/计算值：height = min(round(800*scale), self.root.winfo_screenheight()-90)。
        height = min(round(800*scale), self.root.winfo_screenheight()-90)
        self.root.geometry(f'{width}x{height}')
        self.root.minsize(min(round(1080*scale), width), min(round(740*scale), height))
        self.root.state('zoomed')
        self.root.configure(bg=BG)
        self.root.option_add('*Font', ('Microsoft YaHei UI', 10))
        # 维护本地状态/计算值：self.inbox = queue.Queue()。
        self.inbox = queue.Queue()
        # 维护本地状态/计算值：self.running = False。
        self.running = False
        # 维护本地状态/计算值：self.runner = None。
        self.runner = None
        # 维护本地状态/计算值：self.close_when_done = False。
        self.close_when_done = False
        # 维护本地状态/计算值：self.seconds = seconds。
        self.seconds = seconds
        # 维护本地状态/计算值：self.started = None。
        self.started = None
        # 维护本地状态/计算值：self.last_frame_time = None。
        self.last_frame_time = None
        # 维护本地状态/计算值：self.last_reply_time = None。
        self.last_reply_time = None
        # 维护本地状态/计算值：self.live_stage = False。
        self.live_stage = False
        # 维护本地状态/计算值：self.fps_value = None。
        self.fps_value = None
        # 维护本地状态/计算值：self.last_rate_time = None。
        self.last_rate_time = None
        # 维护本地状态/计算值：self.transfer_active = False。
        self.transfer_active = False
        # 维护本地状态/计算值：self.waiting_link = False。
        self.waiting_link = False
        # 维护本地状态/计算值：self.poll_job = None。
        self.poll_job = None
        # 维护本地状态/计算值：self.last_out = HERE/'logs'。
        self.last_out = HERE/'logs'
        # 维护本地状态/计算值：style = ttk.Style(self.root)。
        style = ttk.Style(self.root)
        style.theme_use('clam')
        style.configure('Video.Horizontal.TProgressbar', troughcolor=LINE, background=TEAL,
                        borderwidth=0, thickness=8, lightcolor=TEAL, darkcolor=TEAL)
        style.configure('Video.TCombobox', padding=7, fieldbackground='#FFFFFF', foreground=INK)

        # 维护本地状态/计算值：left = tk.Frame(self.root, bg=DARK, width=round(255*scale), padx=23, pady=24)。
        left = tk.Frame(self.root, bg=DARK, width=round(255*scale), padx=23, pady=24)
        left.pack(side='left', fill='y')
        left.pack_propagate(False)
        tk.Label(left, text='VISION', bg=DARK, fg=ACCENT,
                 font=('Bahnschrift', 16, 'bold'), anchor='w').pack(fill='x')
        tk.Label(left, text='YOLO 展示控制台', bg=DARK, fg='#F2F6EF',
                 font=('Microsoft YaHei UI', 17, 'bold'), anchor='w').pack(fill='x', pady=(9, 5))
        tk.Label(left, text='Graph21 StreamPipeline', bg=DARK, fg='#94B3A4', anchor='w').pack(fill='x')
        tk.Frame(left, bg='#354B40', height=1).pack(fill='x', pady=(24, 18))
        tk.Label(left, text='连接串口', bg=DARK, fg='#D2E0D5', anchor='w').pack(fill='x')
        # 维护本地状态/计算值：self.port = tk.StringVar()。
        self.port = tk.StringVar()
        # 维护本地状态/计算值：self.combo = ttk.Combobox(left, textvariable=self.port, state='readonly', style='Video.TCombobox')。
        self.combo = ttk.Combobox(left, textvariable=self.port, state='readonly', style='Video.TCombobox')
        self.combo.pack(fill='x', pady=(7, 7))
        # 维护本地状态/计算值：self.refresh_button = tk.Button(left, text='刷新设备', command=self.refresh_ports,。
        self.refresh_button = tk.Button(left, text='刷新设备', command=self.refresh_ports,
            bg='#2A4438', fg='#D4E4D8', activebackground='#365744', activeforeground='white',
            relief='flat', bd=0, pady=5, cursor='hand2')
        self.refresh_button.pack(fill='x')
        tk.Label(left, text='115200 baud  ·  自动分配 JTAG 端口', bg=DARK, fg='#94B3A4',
                 font=('Microsoft YaHei UI', 8), anchor='w', wraplength=round(210*scale)).pack(fill='x', pady=(8, 18))
        tk.Label(left,text='运行策略',bg=DARK,fg='#D2E0D5',anchor='w').pack(fill='x',pady=(0,5))
        tk.Label(left,text='不限时连续识别\n丢像素 ≥ 10% 停止\n未检出手势不超时',bg=DARK,fg='#94B3A4',justify='left',anchor='w',font=('Microsoft YaHei UI',9)).pack(fill='x',pady=(0,16))
        # 维护本地状态/计算值：self.step_labels = []。
        self.step_labels = []
        # 迭代/等待条件：enumerate(STEPS)；退出由原循环条件及显式 break/异常决定。
        for i, title in enumerate(STEPS):
            # 维护本地状态/计算值：label = tk.Label(left, text=f'{i+1:02d} {title}', bg=DARK, fg='#819C8D',。
            label = tk.Label(left, text=f'{i+1:02d}   {title}', bg=DARK, fg='#819C8D',
                             anchor='w', pady=6, font=('Microsoft YaHei UI', 10))
            label.pack(fill='x')
            self.step_labels.append(label)
        tk.Label(left, text='HDMI 显示实时画面\n识别框随完整推理结果更新', bg=DARK, fg='#94B3A4',
                 justify='left', anchor='w', font=('Microsoft YaHei UI', 9)).pack(side='bottom', fill='x', pady=(12, 0))

        # 维护本地状态/计算值：body = tk.Frame(self.root, bg=BG, padx=28, pady=23)。
        body = tk.Frame(self.root, bg=BG, padx=28, pady=23)
        body.pack(fill='both', expand=True)
        # 维护本地状态/计算值：top = tk.Frame(body, bg=BG)。
        top = tk.Frame(body, bg=BG)
        top.pack(fill='x')
        tk.Label(top, text='一键上板 · 实时识别展示', bg=BG, fg=INK,
                 font=('Microsoft YaHei UI', 20, 'bold'), anchor='w').pack(side='left')
        # 维护本地状态/计算值：self.state_badge = tk.Label(top, text='待运行', bg='#E1E9DB', fg=TEAL,。
        self.state_badge = tk.Label(top, text='待运行', bg='#E1E9DB', fg=TEAL,
                                   padx=12, pady=6, font=('Microsoft YaHei UI', 9, 'bold'))
        self.state_badge.pack(side='right')
        # 维护本地状态/计算值：self.message = tk.StringVar(value='接好电源、JTAG、USB 串口与 HDMI，点击“一键上板并识别”即可完成全流程。')。
        self.message = tk.StringVar(value='接好电源、JTAG、USB 串口与 HDMI，点击“一键上板并识别”即可完成全流程。')
        # 维护本地状态/计算值：self.message_label = tk.Label(body, textvariable=self.message, bg=BG, fg=MUTED,。
        self.message_label = tk.Label(body, textvariable=self.message, bg=BG, fg=MUTED,
                                     justify='left', anchor='w', wraplength=round(820*scale))
        self.message_label.pack(fill='x', pady=(9, 17))
        body.bind('<Configure>', lambda event: self.message_label.configure(wraplength=max(200, event.width-60)))

        # 维护本地状态/计算值：metrics = tk.Frame(body, bg='#FFFFFF', padx=20, pady=14,。
        metrics = tk.Frame(body, bg='#FFFFFF', padx=20, pady=14,
                           highlightbackground=LINE, highlightthickness=1)
        metrics.pack(fill='x')
        # 维护本地状态/计算值：self.speed = tk.StringVar(value='—')。
        self.speed = tk.StringVar(value='—')
        # 维护本地状态/计算值：self.speed_detail = tk.StringVar(value='有效载荷 · KiB/s')。
        self.speed_detail = tk.StringVar(value='有效载荷 · KiB/s')
        # 维护本地状态/计算值：self.fps_detail = tk.StringVar(value='完整推理完成间隔 · 板上计时')。
        self.fps_detail = tk.StringVar(value='完整推理完成间隔 · 板上计时')
        # 维护本地状态/计算值：self.fps = tk.StringVar(value='—')。
        self.fps = tk.StringVar(value='—')
        # 维护本地状态/计算值：self.frames = tk.StringVar(value='0')。
        self.frames = tk.StringVar(value='0')
        # 维护本地状态/计算值：self.detection = tk.StringVar(value='等待识别')。
        self.detection = tk.StringVar(value='等待识别')
        # 维护本地状态/计算值：self.confidence = tk.StringVar(value='完整推理后更新')。
        self.confidence = tk.StringVar(value='完整推理后更新')
        # 维护本地状态/计算值：cards=[('模型传输速度',self.speed,('Bahnschrift',28,'bold'),self.speed_detail),。
        cards=[('模型传输速度',self.speed,('Bahnschrift',28,'bold'),self.speed_detail),
               ('实测识别 FPS',self.fps,('Bahnschrift',28,'bold'),self.fps_detail),
               ('完整推理帧数',self.frames,('Bahnschrift',28,'bold'),None),
               ('最新识别',self.detection,('Microsoft YaHei UI',19,'bold'),self.confidence)]
        # 迭代/等待条件：enumerate(cards)；退出由原循环条件及显式 break/异常决定。
        for i,(title,variable,font,detail) in enumerate(cards):
            # 维护本地状态/计算值：cell=tk.Frame(metrics,bg='white')。
            cell=tk.Frame(metrics,bg='white')
            cell.grid(row=0,column=i,sticky='nsew',padx=(0,12))
            metrics.columnconfigure(i,weight=1,uniform='metric')
            tk.Label(cell,text=title,bg='white',fg=MUTED,anchor='w',font=('Microsoft YaHei UI',9)).pack(fill='x')
            tk.Label(cell,textvariable=variable,bg='white',fg=INK,font=font,anchor='w').pack(fill='x',pady=5)
            tk.Label(cell,textvariable=detail,text='当前识别会话' if detail is None else '',bg='white',fg=MUTED,anchor='w',font=('Microsoft YaHei UI',8),wraplength=round(195*scale),justify='left').pack(fill='x')

        # 维护本地状态/计算值：progress = tk.Frame(body, bg=BG)。
        progress = tk.Frame(body, bg=BG)
        progress.pack(fill='x', pady=(17, 12))
        # 维护本地状态/计算值：self.fpga_text = tk.StringVar(value='FPGA 烧录 · 等待开始')。
        self.fpga_text = tk.StringVar(value='FPGA 烧录 · 等待开始')
        # 维护本地状态/计算值：self.model_text = tk.StringVar(value='模型上传 + 回读 · 0 / 317 项')。
        self.model_text = tk.StringVar(value='模型上传 + 回读 · 0 / 317 项')
        # 维护本地状态/计算值：self.transfer_detail=tk.StringVar(value='上传 0 KiB · 回读 0 KiB · 共 1.77 MiB 模型常量')。
        self.transfer_detail=tk.StringVar(value='上传 0 KiB  ·  回读 0 KiB  ·  共 1.77 MiB 模型常量')
        tk.Label(progress, textvariable=self.fpga_text, bg=BG, fg=INK, anchor='w').pack(fill='x')
        # 维护本地状态/计算值：self.fpga = ttk.Progressbar(progress, style='Video.Horizontal.TProgressbar', maximum=100)。
        self.fpga = ttk.Progressbar(progress, style='Video.Horizontal.TProgressbar', maximum=100)
        self.fpga.pack(fill='x', pady=(5, 10))
        tk.Label(progress, textvariable=self.model_text, bg=BG, fg=INK, anchor='w').pack(fill='x')
        # 维护本地状态/计算值：self.model = ttk.Progressbar(progress, style='Video.Horizontal.TProgressbar', maximum=100)。
        self.model = ttk.Progressbar(progress, style='Video.Horizontal.TProgressbar', maximum=100)
        self.model.pack(fill='x', pady=(5, 0))
        tk.Label(progress,textvariable=self.transfer_detail,bg=BG,fg=MUTED,anchor='w',font=('Microsoft YaHei UI',8)).pack(fill='x',pady=(5,0))

        # 维护本地状态/计算值：actions = tk.Frame(body, bg=BG)。
        actions = tk.Frame(body, bg=BG)
        actions.pack(side='bottom', fill='x', pady=(13, 0))
        # 维护本地状态/计算值：self.start_button = tk.Button(actions, text='一键上板并识别', command=self.start, bg=ACCENT, fg=DARK,。
        self.start_button = tk.Button(actions, text='一键上板并识别', command=self.start, bg=ACCENT, fg=DARK,
            activebackground='#A0D762', relief='flat', padx=22, pady=10, cursor='hand2', font=('Microsoft YaHei UI', 11, 'bold'))
        self.start_button.pack(side='left')
        # 维护本地状态/计算值：self.stop_button = tk.Button(actions, text='停止识别', command=self.stop, bg='#E0E6DD', fg=INK,。
        self.stop_button = tk.Button(actions, text='停止识别', command=self.stop, bg='#E0E6DD', fg=INK,
            relief='flat', padx=17, pady=10, state='disabled', cursor='hand2')
        self.stop_button.pack(side='left', padx=9)
        # 维护本地状态/计算值：self.check_button = tk.Button(actions, text='离线检查', command=lambda: self.start(check_only=True),。
        self.check_button = tk.Button(actions, text='离线检查', command=lambda: self.start(check_only=True),
            bg=BG, fg=TEAL, relief='flat', padx=8, pady=10, cursor='hand2')
        self.check_button.pack(side='left')
        tk.Button(actions, text='打开日志 ↗', command=self.open_logs, bg=BG, fg=TEAL,
                  relief='flat', padx=4, pady=10, cursor='hand2').pack(side='right')
        # 维护本地状态/计算值：self.elapsed = tk.StringVar(value='准备就绪')。
        self.elapsed = tk.StringVar(value='准备就绪')
        # 维护本地状态/计算值：footer = tk.Frame(body, bg=BG)。
        footer = tk.Frame(body, bg=BG)
        footer.pack(side='bottom', fill='x', pady=(8, 0))
        tk.Label(footer, textvariable=self.elapsed, bg=BG, fg=MUTED, font=('Microsoft YaHei UI', 8)).pack(side='left')
        tk.Label(footer, text='每次运行独立保存日志', bg=BG, fg=MUTED, font=('Microsoft YaHei UI', 8)).pack(side='right')

        tk.Label(body, text='串口与流程日志', bg=BG, fg=INK, anchor='w',
                 font=('Microsoft YaHei UI', 10, 'bold')).pack(fill='x', pady=(0, 6))
        # 维护本地状态/计算值：pane = tk.Frame(body, bg='#10251E')。
        pane = tk.Frame(body, bg='#10251E')
        pane.pack(fill='both', expand=True)
        # 维护本地状态/计算值：self.log = tk.Text(pane, bg='#10251E', fg='#C3DDCF', insertbackground='white',。
        self.log = tk.Text(pane, bg='#10251E', fg='#C3DDCF', insertbackground='white',
                           font=('Microsoft YaHei UI', 9), relief='flat', bd=0, padx=13, pady=12,
                           state='disabled', wrap='word', height=9)
        # 维护本地状态/计算值：scroll = ttk.Scrollbar(pane, command=self.log.yview)。
        scroll = ttk.Scrollbar(pane, command=self.log.yview)
        scroll.pack(side='right', fill='y')
        self.log.configure(yscrollcommand=scroll.set)
        self.log.pack(fill='both', expand=True)
        self.append('准备就绪。一次点击完成：下载位流 → 模型上传与回读 → 不限时真实摄像头识别。')
        self.append('传输速度按实际有效字节计算；识别 FPS 使用板上 64 位完成时间戳，排除模型加载时间。')
        self.refresh_ports()
        self.root.protocol('WM_DELETE_WINDOW', self.close)
        # 维护本地状态/计算值：self.poll_job = self.root.after(80, self.poll)。
        self.poll_job = self.root.after(80, self.poll)

    # 接口 append，显式输入字段：text。
    # 本函数调用入口包括 self.log.configure, self.log.insert, self.log.see, int, self.log.delete。
    def append(self, text):
        self.log.configure(state='normal')
        self.log.insert('end', time.strftime('%H:%M:%S')+'  '+text+'\n')
        # 按条件 int(self.log.index('end-1c').split('.')[0]) > 3000 选择后续流程，保留原有异常和退出分支。
        if int(self.log.index('end-1c').split('.')[0]) > 3000:
            self.log.delete('1.0', '501.0')
        self.log.see('end')
        self.log.configure(state='disabled')

    # 接口 refresh_ports，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.combo.configure, self.port.get, self.port.set, self.message.set, ports。
    def refresh_ports(self):
        # 按条件 self.running 选择后续流程，保留原有异常和退出分支。
        if self.running:
            # 向调用方返回本步骤结果：None。
            return
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            # 维护本地状态/计算值：values = [p['device'] for p in ports()]。
            values = [p['device'] for p in ports()]
            self.combo.configure(values=values)
            # 按条件 self.port.get() not in values 选择后续流程，保留原有异常和退出分支。
            if self.port.get() not in values:
                self.port.set(values[0] if len(values) == 1 else '')
            # 按条件 not values 选择后续流程，保留原有异常和退出分支。
            if not values:
                self.message.set('未找到 CP210x 串口。接好 USB 串口线后点击“刷新设备”。')
            # 按条件 len(values) > 1 and (not self.port.get()) 选择后续流程，保留原有异常和退出分支。
            elif len(values) > 1 and not self.port.get():
                self.message.set('检测到多个串口，请选择连接目标开发板的串口。')
        except Exception as exc:
            self.message.set('设备查询失败：'+str(exc))

    # 接口 start，显式输入字段：check_only。
    # 本函数调用入口包括 Runner, time.monotonic, self.start_button.configure, self.check_button.configure, self.refresh_button.configure。
    def start(self, check_only=False):
        # 按条件 self.running 选择后续流程，保留原有异常和退出分支。
        if self.running:
            # 向调用方返回本步骤结果：None。
            return
        # 按条件 not check_only and (not self.port.get()) 选择后续流程，保留原有异常和退出分支。
        if not check_only and not self.port.get():
            self.message.set('请先选择目标开发板的串口。')
            # 向调用方返回本步骤结果：None。
            return
        # 维护本地状态/计算值：self.runner = Runner(self.port.get(), callback=self.inbox.put, seconds=self.seconds,。
        self.runner = Runner(self.port.get(), callback=self.inbox.put, seconds=self.seconds,
                             verification='readback')
        # 维护本地状态/计算值：self.last_out = self.runner.out。
        self.last_out = self.runner.out
        # 维护本地状态/计算值：self.running = True。
        self.running = True
        # 维护本地状态/计算值：self.close_when_done = False。
        self.close_when_done = False
        # 维护本地状态/计算值：self.started = time.monotonic()。
        self.started = time.monotonic()
        self.start_button.configure(state='disabled')
        self.check_button.configure(state='disabled')
        self.refresh_button.configure(state='disabled')
        self.combo.configure(state='disabled')
        self.stop_button.configure(state='normal')
        self.fpga.stop()
        self.fpga.configure(mode='determinate', value=0)
        self.model.configure(value=0)
        # 维护本地状态/计算值：self.live_stage=False; self.waiting_link=False; self.transfer_active=False。
        self.live_stage=False; self.waiting_link=False; self.transfer_active=False
        # 维护本地状态/计算值：self.last_frame_time=None; self.last_reply_time=None; self.fps_value=None。
        self.last_frame_time=None; self.last_reply_time=None; self.fps_value=None
        self.speed.set('—'); self.speed_detail.set('有效载荷 · KiB/s')
        self.fps_detail.set('完整推理完成间隔 · 板上计时')
        self.transfer_detail.set('上传 0 KiB  ·  回读 0 KiB')
        self.fpga_text.set('FPGA 烧录 · 等待下载器')
        self.model_text.set('模型上传 + 回读 · 0 / 317 项')
        self.fps.set('—'); self.frames.set('0'); self.detection.set('等待识别')
        self.confidence.set('完整推理后更新')
        # 迭代/等待条件：enumerate(self.step_labels)；退出由原循环条件及显式 break/异常决定。
        for i, label in enumerate(self.step_labels):
            label.configure(text=f'{i+1:02d}   {STEPS[i]}', fg='#819C8D')
        self.state_badge.configure(text='运行中', bg=ACCENT, fg=DARK)
        self.append('新会话：'+str(self.last_out))
        # 接口 work，显式输入字段：无位置参数。
        # 本函数调用入口包括 self.runner.run, self.inbox.put, dict, str。
        def work():
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:
                self.runner.run(check_only=check_only)
            except BaseException as exc:
                self.inbox.put(dict(kind='complete', result=dict(status='failed', error=str(exc))))
        # 维护本地状态/计算值：self.worker = threading.Thread(target=work, name='video-session', daemon=False)。
        self.worker = threading.Thread(target=work, name='video-session', daemon=False)
        self.worker.start()

    # 接口 stop，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.runner.cancel.set, self.stop_button.configure, self.message.set, self.state_badge.configure。
    def stop(self):
        # 按条件 self.running and self.runner 选择后续流程，保留原有异常和退出分支。
        if self.running and self.runner:
            self.runner.cancel.set()
            self.stop_button.configure(state='disabled')
            self.message.set('正在中断当前步骤并释放连接；窗口会在完成清理后允许重新运行。')
            self.state_badge.configure(text='停止中', bg='#E7DEBC', fg='#6E5722')

    # 接口 close，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.stop, self.destroy。
    def close(self):
        # 按条件 self.running 选择后续流程，保留原有异常和退出分支。
        if self.running:
            # 维护本地状态/计算值：self.close_when_done = True。
            self.close_when_done = True
            self.stop()
        else:
            self.destroy()

    # 接口 destroy，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.root.destroy, self.root.after_cancel。
    def destroy(self):
        # 按条件 self.poll_job is not None 选择后续流程，保留原有异常和退出分支。
        if self.poll_job is not None:
            self.root.after_cancel(self.poll_job)
            # 维护本地状态/计算值：self.poll_job = None。
            self.poll_job = None
        self.root.destroy()

    # 接口 open_logs，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.last_out.mkdir, os.startfile。
    def open_logs(self):
        self.last_out.mkdir(parents=True, exist_ok=True)
        os.startfile(self.last_out)

    # 接口 handle，显式输入字段：event。
    # 本函数调用入口包括 self.append, self.message.set, enumerate, label.configure, self.fpga.configure。
    def handle(self, event):
        # 维护本地状态/计算值：kind = event['kind']。
        kind = event['kind']
        # 按条件 kind == 'log' 选择后续流程，保留原有异常和退出分支。
        if kind == 'log':
            self.append(event['text'])
        # 按条件 kind == 'stage' 选择后续流程，保留原有异常和退出分支。
        elif kind == 'stage':
            # 维护本地状态/计算值：number = event['number']。
            number = event['number']
            self.message.set(event['title'])
            # 迭代/等待条件：enumerate(self.step_labels)；退出由原循环条件及显式 break/异常决定。
            for i, label in enumerate(self.step_labels):
                label.configure(text=('✓' if i < number else '●' if i == number else f'{i+1:02d}')+'   '+STEPS[i],
                                fg=ACCENT if i <= number else '#819C8D')
            # 按条件 number == 2 选择后续流程，保留原有异常和退出分支。
            if number == 2:
                self.fpga.configure(mode='indeterminate')
                self.fpga.start(24)
                self.fpga_text.set('FPGA 烧录 · 等待下载器报告进度')
            # 按条件 number == 6 选择后续流程，保留原有异常和退出分支。
            elif number == 6:
                # 维护本地状态/计算值：self.live_stage=True。
                self.live_stage=True
                self.state_badge.configure(text='识别中', bg=ACCENT, fg=DARK)
        # 按条件 kind == 'progress' 选择后续流程，保留原有异常和退出分支。
        elif kind == 'progress':
            # 维护本地状态/计算值：value = 100*event['value']/event['total'] if event['total'] else 0。
            value = 100*event['value']/event['total'] if event['total'] else 0
            # 按条件 event['channel'] == 'fpga' 选择后续流程，保留原有异常和退出分支。
            if event['channel'] == 'fpga':
                self.fpga.stop(); self.fpga.configure(mode='determinate', value=value)
                self.fpga_text.set(f'FPGA 烧录 · {value:.0f}%')
            else:
                self.model.configure(value=value)
                # 维护本地状态/计算值：self.last_rate_time=time.monotonic()。
                self.last_rate_time=time.monotonic()
                # 维护本地状态/计算值：self.transfer_active=not event.get('complete',False)。
                self.transfer_active=not event.get('complete',False)
                rate=event.get('current_bytes_per_second',0)/1024
                average=event.get('average_bytes_per_second',0)/1024
                self.speed.set(f'{rate:.2f}' if self.transfer_active else '完成')
                self.speed_detail.set(f'KiB/s · 近 3 秒' if self.transfer_active else f'平均 {average:.2f} KiB/s')
                self.model_text.set(f"模型上传 + 回读 · {value:.1f}% · 已校验 {event.get('assets',0)} / 317 项")
                self.transfer_detail.set(f"{event.get('direction','传输')}  |  已上传 {event.get('uploaded_bytes',0)/1024:.1f} KiB  ·  已回读 {event.get('readback_bytes',0)/1024:.1f} KiB  ·  均速 {average:.2f} KiB/s")
        # 按条件 kind == 'frame' 选择后续流程，保留原有异常和退出分支。
        elif kind == 'frame':
            row = event['event']
            self.frames.set(str(row['completed']))
            self.last_frame_time=time.monotonic()
            self.last_reply_time=self.last_frame_time
            self.waiting_link=False
            # 按条件 row.get('fps_interval', {}).get('valid') 选择后续流程，保留原有异常和退出分支。
            if row.get('fps_interval',{}).get('valid'):
                measured=row['fps_interval']
                self.fps_value=measured['fps']
                self.fps.set(f"{self.fps_value:.3f}")
                self.fps_detail.set(f"累计均值 · {measured['average_interval_ms']:.2f} ms/帧")
            self.state_badge.configure(text='识别中',bg=ACCENT,fg=DARK)
            self.message.set('不限时真实摄像头识别中 · HDMI 独立预览 · 识别结果持续更新')
            cls = row['class_id']
            self.detection.set(LABELS[cls] if cls is not None else '未检出')
            self.confidence.set(f"置信度 {row['confidence']*100:.1f}%" if cls is not None else '画面继续更新')
        # 按条件 kind == 'telemetry' 选择后续流程，保留原有异常和退出分支。
        elif kind == 'telemetry':
            self.last_reply_time=time.monotonic()
        # 按条件 kind == 'link_wait' 选择后续流程，保留原有异常和退出分支。
        elif kind == 'link_wait':
            self.waiting_link=True
            self.state_badge.configure(text='等待板卡回应',bg='#E7DEBC',fg='#6E5722')
            self.message.set(f"串口已等待 {event['waited_seconds']:.0f} 秒；继续等待，不按时间中断。上次 FPS 仅作历史记录。")
            self.fps.set('—')
            # 按条件 self.fps_value is not None 选择后续流程，保留原有异常和退出分支。
            if self.fps_value is not None:self.fps_detail.set(f'上次实测 {self.fps_value:.3f} FPS')
        # 按条件 kind == 'link_resumed' 选择后续流程，保留原有异常和退出分支。
        elif kind == 'link_resumed':
            self.waiting_link=False
            self.last_reply_time=time.monotonic()
            self.append('串口已恢复回应，继续采样。')
        # 按条件 kind == 'complete' 选择后续流程，保留原有异常和退出分支。
        elif kind == 'complete':
            self.running = False
            self.live_stage=False
            self.transfer_active=False
            self.fpga.stop()
            self.stop_button.configure(state='disabled')
            self.start_button.configure(state='normal', text='重新上板并识别')
            self.check_button.configure(state='normal')
            self.refresh_button.configure(state='normal')
            self.combo.configure(state='readonly')
            result = event['result']
            status = result['status']
            title = {'stopped':'已停止', 'cancelled':'已中断', 'offline_check_passed':'检查通过'}.get(status, '连接状态未知' if status=='connection_unknown' else '运行中断')
            self.state_badge.configure(text=title, bg='#E1E9DB' if status in ('stopped','offline_check_passed') else '#F0DCCB',
                                       fg=TEAL if status in ('stopped','offline_check_passed') else '#994C30')
            message = {'stopped':'已确认停止。点击“重新运行”可再次开始完整流程。',
                       'offline_check_passed':'位流、固件和模型检查通过，可以开始视频识别。',
                       'cancelled':'本次已中断，日志已保存。点击“重新运行”可重新烧录并启动。'}.get(status)
            self.message.set(message or result.get('error', '运行未完成，请查看日志。'))
            # 按条件 self.close_when_done 选择后续流程，保留原有异常和退出分支。
            if self.close_when_done:
                self.destroy()

    # 接口 poll，显式输入字段：无位置参数。
    # 本函数调用入口包括 range, self.root.after, self.handle, int, self.elapsed.set。
    def poll(self):
        self.poll_job = None
        # 迭代/等待条件：range(120)；退出由原循环条件及显式 break/异常决定。
        for _ in range(120):
            # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
            try:
                event = self.inbox.get_nowait()
            except queue.Empty:
                break
            self.handle(event)
            # 按条件 self.close_when_done and (not self.running) 选择后续流程，保留原有异常和退出分支。
            if self.close_when_done and not self.running:
                # 向调用方返回本步骤结果：None。
                return
        # 按条件 self.running and self.started 选择后续流程，保留原有异常和退出分支。
        if self.running and self.started:
            elapsed = int(time.monotonic()-self.started)
            self.elapsed.set(f'本次运行 {elapsed//60:02d}:{elapsed%60:02d}')
        # 按条件 self.live_stage and self.last_frame_time and (not self.waiting_link) and (time.monotonic() - self.last_fram... 选择后续流程，保留原有异常和退出分支。
        if self.live_stage and self.last_frame_time and not self.waiting_link and time.monotonic()-self.last_frame_time>5:
            self.fps.set('—')
            # 按条件 self.fps_value is not None 选择后续流程，保留原有异常和退出分支。
            if self.fps_value is not None:self.fps_detail.set(f'上次实测 {self.fps_value:.3f} FPS · 等待新帧')
            self.message.set('板卡连接仍由串口回应确认；正在等待下一次完整推理，不按未检出时间停止。')
        # 按条件 self.transfer_active and self.last_rate_time and (time.monotonic() - self.last_rate_time > 3) 选择后续流程，保留原有异常和退出分支。
        if self.transfer_active and self.last_rate_time and time.monotonic()-self.last_rate_time>3:
            self.speed.set('0.00')
            self.speed_detail.set('KiB/s · 等待传输回应')
        self.poll_job = self.root.after(80, self.poll)


# 接口 main，显式输入字段：无位置参数。
# 本函数调用入口包括 argparse.ArgumentParser, parser.add_argument, parser.parse_args, VideoWindow(seconds=args.seconds).root.mainloop, VideoWindow。
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, help='Optional bounded recognition check')
    args = parser.parse_args()
    VideoWindow(seconds=args.seconds).root.mainloop()


# 按条件 __name__ == '__main__' 选择后续流程，保留原有异常和退出分支。
if __name__ == '__main__':
    main()
