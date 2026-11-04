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

BG = '#F1F3EE'
INK = '#19352D'
MUTED = '#6B7F76'
DARK = '#172B25'
ACCENT = '#B8EA77'
LINE = '#D9E1D7'
TEAL = '#22735A'
STEPS = ['文件与依赖检查', '连接开发板', '烧录 FPGA', '固件启动校验',
         'DDR 读写检查', '模型传输与校验', '实时视频识别', '确认停止']
LABELS = ['握拳', '单指', 'V 字', '三指', '四指', '张掌']


class VideoWindow:
    def __init__(self, seconds=None):
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            pass
        self.root = tk.Tk()
        self.root.title('YOLO · 一键上板识别展示')
        scale = max(1.0, float(self.root.tk.call('tk', 'scaling'))/(96/72))
        width = min(round(1180*scale), self.root.winfo_screenwidth()-70)
        height = min(round(800*scale), self.root.winfo_screenheight()-90)
        self.root.geometry(f'{width}x{height}')
        self.root.minsize(min(round(1080*scale), width), min(round(740*scale), height))
        self.root.state('zoomed')
        self.root.configure(bg=BG)
        self.root.option_add('*Font', ('Microsoft YaHei UI', 10))
        self.inbox = queue.Queue()
        self.running = False
        self.runner = None
        self.close_when_done = False
        self.seconds = seconds
        self.started = None
        self.last_frame_time = None
        self.last_reply_time = None
        self.live_stage = False
        self.fps_value = None
        self.last_rate_time = None
        self.transfer_active = False
        self.waiting_link = False
        self.poll_job = None
        self.last_out = HERE/'logs'
        style = ttk.Style(self.root)
        style.theme_use('clam')
        style.configure('Video.Horizontal.TProgressbar', troughcolor=LINE, background=TEAL,
                        borderwidth=0, thickness=8, lightcolor=TEAL, darkcolor=TEAL)
        style.configure('Video.TCombobox', padding=7, fieldbackground='#FFFFFF', foreground=INK)

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
        self.port = tk.StringVar()
        self.combo = ttk.Combobox(left, textvariable=self.port, state='readonly', style='Video.TCombobox')
        self.combo.pack(fill='x', pady=(7, 7))
        self.refresh_button = tk.Button(left, text='刷新设备', command=self.refresh_ports,
            bg='#2A4438', fg='#D4E4D8', activebackground='#365744', activeforeground='white',
            relief='flat', bd=0, pady=5, cursor='hand2')
        self.refresh_button.pack(fill='x')
        tk.Label(left, text='115200 baud  ·  自动分配 JTAG 端口', bg=DARK, fg='#94B3A4',
                 font=('Microsoft YaHei UI', 8), anchor='w', wraplength=round(210*scale)).pack(fill='x', pady=(8, 18))
        tk.Label(left,text='运行策略',bg=DARK,fg='#D2E0D5',anchor='w').pack(fill='x',pady=(0,5))
        tk.Label(left,text='不限时连续识别\n丢像素 ≥ 10% 停止\n未检出手势不超时',bg=DARK,fg='#94B3A4',justify='left',anchor='w',font=('Microsoft YaHei UI',9)).pack(fill='x',pady=(0,16))
        self.step_labels = []
        for i, title in enumerate(STEPS):
            label = tk.Label(left, text=f'{i+1:02d}   {title}', bg=DARK, fg='#819C8D',
                             anchor='w', pady=6, font=('Microsoft YaHei UI', 10))
            label.pack(fill='x')
            self.step_labels.append(label)
        tk.Label(left, text='HDMI 显示实时画面\n识别框随完整推理结果更新', bg=DARK, fg='#94B3A4',
                 justify='left', anchor='w', font=('Microsoft YaHei UI', 9)).pack(side='bottom', fill='x', pady=(12, 0))

        body = tk.Frame(self.root, bg=BG, padx=28, pady=23)
        body.pack(fill='both', expand=True)
        top = tk.Frame(body, bg=BG)
        top.pack(fill='x')
        tk.Label(top, text='一键上板 · 实时识别展示', bg=BG, fg=INK,
                 font=('Microsoft YaHei UI', 20, 'bold'), anchor='w').pack(side='left')
        self.state_badge = tk.Label(top, text='待运行', bg='#E1E9DB', fg=TEAL,
                                   padx=12, pady=6, font=('Microsoft YaHei UI', 9, 'bold'))
        self.state_badge.pack(side='right')
        self.message = tk.StringVar(value='接好电源、JTAG、USB 串口与 HDMI，点击“一键上板并识别”即可完成全流程。')
        self.message_label = tk.Label(body, textvariable=self.message, bg=BG, fg=MUTED,
                                     justify='left', anchor='w', wraplength=round(820*scale))
        self.message_label.pack(fill='x', pady=(9, 17))
        body.bind('<Configure>', lambda event: self.message_label.configure(wraplength=max(200, event.width-60)))

        metrics = tk.Frame(body, bg='#FFFFFF', padx=20, pady=14,
                           highlightbackground=LINE, highlightthickness=1)
        metrics.pack(fill='x')
        self.speed = tk.StringVar(value='—')
        self.speed_detail = tk.StringVar(value='有效载荷 · KiB/s')
        self.fps_detail = tk.StringVar(value='完整推理完成间隔 · 板上计时')
        self.fps = tk.StringVar(value='—')
        self.frames = tk.StringVar(value='0')
        self.detection = tk.StringVar(value='等待识别')
        self.confidence = tk.StringVar(value='完整推理后更新')
        cards=[('模型传输速度',self.speed,('Bahnschrift',28,'bold'),self.speed_detail),
               ('实测识别 FPS',self.fps,('Bahnschrift',28,'bold'),self.fps_detail),
               ('完整推理帧数',self.frames,('Bahnschrift',28,'bold'),None),
               ('最新识别',self.detection,('Microsoft YaHei UI',19,'bold'),self.confidence)]
        for i,(title,variable,font,detail) in enumerate(cards):
            cell=tk.Frame(metrics,bg='white')
            cell.grid(row=0,column=i,sticky='nsew',padx=(0,12))
            metrics.columnconfigure(i,weight=1,uniform='metric')
            tk.Label(cell,text=title,bg='white',fg=MUTED,anchor='w',font=('Microsoft YaHei UI',9)).pack(fill='x')
            tk.Label(cell,textvariable=variable,bg='white',fg=INK,font=font,anchor='w').pack(fill='x',pady=5)
            tk.Label(cell,textvariable=detail,text='当前识别会话' if detail is None else '',bg='white',fg=MUTED,anchor='w',font=('Microsoft YaHei UI',8),wraplength=round(195*scale),justify='left').pack(fill='x')

        progress = tk.Frame(body, bg=BG)
        progress.pack(fill='x', pady=(17, 12))
        self.fpga_text = tk.StringVar(value='FPGA 烧录 · 等待开始')
        self.model_text = tk.StringVar(value='模型上传 + 回读 · 0 / 317 项')
        self.transfer_detail=tk.StringVar(value='上传 0 KiB  ·  回读 0 KiB  ·  共 1.77 MiB 模型常量')
        tk.Label(progress, textvariable=self.fpga_text, bg=BG, fg=INK, anchor='w').pack(fill='x')
        self.fpga = ttk.Progressbar(progress, style='Video.Horizontal.TProgressbar', maximum=100)
        self.fpga.pack(fill='x', pady=(5, 10))
        tk.Label(progress, textvariable=self.model_text, bg=BG, fg=INK, anchor='w').pack(fill='x')
        self.model = ttk.Progressbar(progress, style='Video.Horizontal.TProgressbar', maximum=100)
        self.model.pack(fill='x', pady=(5, 0))
        tk.Label(progress,textvariable=self.transfer_detail,bg=BG,fg=MUTED,anchor='w',font=('Microsoft YaHei UI',8)).pack(fill='x',pady=(5,0))

        actions = tk.Frame(body, bg=BG)
        actions.pack(side='bottom', fill='x', pady=(13, 0))
        self.start_button = tk.Button(actions, text='一键上板并识别', command=self.start, bg=ACCENT, fg=DARK,
            activebackground='#A0D762', relief='flat', padx=22, pady=10, cursor='hand2', font=('Microsoft YaHei UI', 11, 'bold'))
        self.start_button.pack(side='left')
        self.stop_button = tk.Button(actions, text='停止识别', command=self.stop, bg='#E0E6DD', fg=INK,
            relief='flat', padx=17, pady=10, state='disabled', cursor='hand2')
        self.stop_button.pack(side='left', padx=9)
        self.check_button = tk.Button(actions, text='离线检查', command=lambda: self.start(check_only=True),
            bg=BG, fg=TEAL, relief='flat', padx=8, pady=10, cursor='hand2')
        self.check_button.pack(side='left')
        tk.Button(actions, text='打开日志 ↗', command=self.open_logs, bg=BG, fg=TEAL,
                  relief='flat', padx=4, pady=10, cursor='hand2').pack(side='right')
        self.elapsed = tk.StringVar(value='准备就绪')
        footer = tk.Frame(body, bg=BG)
        footer.pack(side='bottom', fill='x', pady=(8, 0))
        tk.Label(footer, textvariable=self.elapsed, bg=BG, fg=MUTED, font=('Microsoft YaHei UI', 8)).pack(side='left')
        tk.Label(footer, text='每次运行独立保存日志', bg=BG, fg=MUTED, font=('Microsoft YaHei UI', 8)).pack(side='right')

        tk.Label(body, text='串口与流程日志', bg=BG, fg=INK, anchor='w',
                 font=('Microsoft YaHei UI', 10, 'bold')).pack(fill='x', pady=(0, 6))
        pane = tk.Frame(body, bg='#10251E')
        pane.pack(fill='both', expand=True)
        self.log = tk.Text(pane, bg='#10251E', fg='#C3DDCF', insertbackground='white',
                           font=('Microsoft YaHei UI', 9), relief='flat', bd=0, padx=13, pady=12,
                           state='disabled', wrap='word', height=9)
        scroll = ttk.Scrollbar(pane, command=self.log.yview)
        scroll.pack(side='right', fill='y')
        self.log.configure(yscrollcommand=scroll.set)
        self.log.pack(fill='both', expand=True)
        self.append('准备就绪。一次点击完成：下载位流 → 模型上传与回读 → 不限时真实摄像头识别。')
        self.append('传输速度按实际有效字节计算；识别 FPS 使用板上 64 位完成时间戳，排除模型加载时间。')
        self.refresh_ports()
        self.root.protocol('WM_DELETE_WINDOW', self.close)
        self.poll_job = self.root.after(80, self.poll)

    def append(self, text):
        self.log.configure(state='normal')
        self.log.insert('end', time.strftime('%H:%M:%S')+'  '+text+'\n')
        if int(self.log.index('end-1c').split('.')[0]) > 3000:
            self.log.delete('1.0', '501.0')
        self.log.see('end')
        self.log.configure(state='disabled')

    def refresh_ports(self):
        if self.running:
            return
        try:
            values = [p['device'] for p in ports()]
            self.combo.configure(values=values)
            if self.port.get() not in values:
                self.port.set(values[0] if len(values) == 1 else '')
            if not values:
                self.message.set('未找到 CP210x 串口。接好 USB 串口线后点击“刷新设备”。')
            elif len(values) > 1 and not self.port.get():
                self.message.set('检测到多个串口，请选择连接目标开发板的串口。')
        except Exception as exc:
            self.message.set('设备查询失败：'+str(exc))

    def start(self, check_only=False):
        if self.running:
            return
        if not check_only and not self.port.get():
            self.message.set('请先选择目标开发板的串口。')
            return
        self.runner = Runner(self.port.get(), callback=self.inbox.put, seconds=self.seconds,
                             verification='readback')
        self.last_out = self.runner.out
        self.running = True
        self.close_when_done = False
        self.started = time.monotonic()
        self.start_button.configure(state='disabled')
        self.check_button.configure(state='disabled')
        self.refresh_button.configure(state='disabled')
        self.combo.configure(state='disabled')
        self.stop_button.configure(state='normal')
        self.fpga.stop()
        self.fpga.configure(mode='determinate', value=0)
        self.model.configure(value=0)
        self.live_stage=False; self.waiting_link=False; self.transfer_active=False
        self.last_frame_time=None; self.last_reply_time=None; self.fps_value=None
        self.speed.set('—'); self.speed_detail.set('有效载荷 · KiB/s')
        self.fps_detail.set('完整推理完成间隔 · 板上计时')
        self.transfer_detail.set('上传 0 KiB  ·  回读 0 KiB')
        self.fpga_text.set('FPGA 烧录 · 等待下载器')
        self.model_text.set('模型上传 + 回读 · 0 / 317 项')
        self.fps.set('—'); self.frames.set('0'); self.detection.set('等待识别')
        self.confidence.set('完整推理后更新')
        for i, label in enumerate(self.step_labels):
            label.configure(text=f'{i+1:02d}   {STEPS[i]}', fg='#819C8D')
        self.state_badge.configure(text='运行中', bg=ACCENT, fg=DARK)
        self.append('新会话：'+str(self.last_out))
        def work():
            try:
                self.runner.run(check_only=check_only)
            except BaseException as exc:
                self.inbox.put(dict(kind='complete', result=dict(status='failed', error=str(exc))))
        self.worker = threading.Thread(target=work, name='video-session', daemon=False)
        self.worker.start()

    def stop(self):
        if self.running and self.runner:
            self.runner.cancel.set()
            self.stop_button.configure(state='disabled')
            self.message.set('正在中断当前步骤并释放连接；窗口会在完成清理后允许重新运行。')
            self.state_badge.configure(text='停止中', bg='#E7DEBC', fg='#6E5722')

    def close(self):
        if self.running:
            self.close_when_done = True
            self.stop()
        else:
            self.destroy()

    def destroy(self):
        if self.poll_job is not None:
            self.root.after_cancel(self.poll_job)
            self.poll_job = None
        self.root.destroy()

    def open_logs(self):
        self.last_out.mkdir(parents=True, exist_ok=True)
        os.startfile(self.last_out)

    def handle(self, event):
        kind = event['kind']
        if kind == 'log':
            self.append(event['text'])
        elif kind == 'stage':
            number = event['number']
            self.message.set(event['title'])
            for i, label in enumerate(self.step_labels):
                label.configure(text=('✓' if i < number else '●' if i == number else f'{i+1:02d}')+'   '+STEPS[i],
                                fg=ACCENT if i <= number else '#819C8D')
            if number == 2:
                self.fpga.configure(mode='indeterminate')
                self.fpga.start(24)
                self.fpga_text.set('FPGA 烧录 · 等待下载器报告进度')
            elif number == 6:
                self.live_stage=True
                self.state_badge.configure(text='识别中', bg=ACCENT, fg=DARK)
        elif kind == 'progress':
            value = 100*event['value']/event['total'] if event['total'] else 0
            if event['channel'] == 'fpga':
                self.fpga.stop(); self.fpga.configure(mode='determinate', value=value)
                self.fpga_text.set(f'FPGA 烧录 · {value:.0f}%')
            else:
                self.model.configure(value=value)
                self.last_rate_time=time.monotonic()
                self.transfer_active=not event.get('complete',False)
                rate=event.get('current_bytes_per_second',0)/1024
                average=event.get('average_bytes_per_second',0)/1024
                self.speed.set(f'{rate:.2f}' if self.transfer_active else '完成')
                self.speed_detail.set(f'KiB/s · 近 3 秒' if self.transfer_active else f'平均 {average:.2f} KiB/s')
                self.model_text.set(f"模型上传 + 回读 · {value:.1f}% · 已校验 {event.get('assets',0)} / 317 项")
                self.transfer_detail.set(f"{event.get('direction','传输')}  |  已上传 {event.get('uploaded_bytes',0)/1024:.1f} KiB  ·  已回读 {event.get('readback_bytes',0)/1024:.1f} KiB  ·  均速 {average:.2f} KiB/s")
        elif kind == 'frame':
            row = event['event']
            self.frames.set(str(row['completed']))
            self.last_frame_time=time.monotonic()
            self.last_reply_time=self.last_frame_time
            self.waiting_link=False
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
        elif kind == 'telemetry':
            self.last_reply_time=time.monotonic()
        elif kind == 'link_wait':
            self.waiting_link=True
            self.state_badge.configure(text='等待板卡回应',bg='#E7DEBC',fg='#6E5722')
            self.message.set(f"串口已等待 {event['waited_seconds']:.0f} 秒；继续等待，不按时间中断。上次 FPS 仅作历史记录。")
            self.fps.set('—')
            if self.fps_value is not None:self.fps_detail.set(f'上次实测 {self.fps_value:.3f} FPS')
        elif kind == 'link_resumed':
            self.waiting_link=False
            self.last_reply_time=time.monotonic()
            self.append('串口已恢复回应，继续采样。')
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
            if self.close_when_done:
                self.destroy()

    def poll(self):
        self.poll_job = None
        for _ in range(120):
            try:
                event = self.inbox.get_nowait()
            except queue.Empty:
                break
            self.handle(event)
            if self.close_when_done and not self.running:
                return
        if self.running and self.started:
            elapsed = int(time.monotonic()-self.started)
            self.elapsed.set(f'本次运行 {elapsed//60:02d}:{elapsed%60:02d}')
        if self.live_stage and self.last_frame_time and not self.waiting_link and time.monotonic()-self.last_frame_time>5:
            self.fps.set('—')
            if self.fps_value is not None:self.fps_detail.set(f'上次实测 {self.fps_value:.3f} FPS · 等待新帧')
            self.message.set('板卡连接仍由串口回应确认；正在等待下一次完整推理，不按未检出时间停止。')
        if self.transfer_active and self.last_rate_time and time.monotonic()-self.last_rate_time>3:
            self.speed.set('0.00')
            self.speed_detail.set('KiB/s · 等待传输回应')
        self.poll_job = self.root.after(80, self.poll)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, help='Optional bounded recognition check')
    args = parser.parse_args()
    VideoWindow(seconds=args.seconds).root.mainloop()


if __name__ == '__main__':
    main()
