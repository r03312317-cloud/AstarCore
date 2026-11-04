"""Typeset the source-bound Graph21 architecture and physical test report."""
from pathlib import Path
import csv
import json
import math
from xml.sax.saxutils import escape
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT,TA_CENTER
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.platypus import SimpleDocTemplate,Paragraph,Spacer,Table,TableStyle,PageBreak,Image,Flowable,KeepTogether

ROOT=Path('D:/workspace/riscv-fpga-soc/deliverables/YOLO_G21_20261104')
REPORT=ROOT/'reports'
FIG=REPORT/'figures';FIG.mkdir(exist_ok=True)
data=json.loads((REPORT/'REAL_BOARD_DATA_20261104.json').read_text(encoding='utf-8'))
runs=data['runs']
comments=json.loads((ROOT/'audit/COMMENT_RATE_AND_TOKEN_EQUIVALENCE.json').read_text(encoding='utf-8'))
model=json.loads((REPORT/'MODEL_ARCHITECTURE.json').read_text(encoding='utf-8'))
physical=json.loads((ROOT/'evidence/PHYSICAL_REVIEW.json').read_text(encoding='utf-8'))
compile_check=json.loads((ROOT/'audit/ANNOTATED_C_RECOMPILE.json').read_text(encoding='utf-8'))

pdfmetrics.registerFont(TTFont('CN','C:/Windows/Fonts/msyh.ttc',subfontIndex=0))
pdfmetrics.registerFont(TTFont('CNB','C:/Windows/Fonts/msyhbd.ttc',subfontIndex=0))
font_manager.fontManager.addfont('C:/Windows/Fonts/msyh.ttc')
plt.rcParams.update({'font.family':'Microsoft YaHei','axes.unicode_minus':False,'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
INK=colors.HexColor('#17352D');TEAL=colors.HexColor('#22735A');MUTED=colors.HexColor('#61766C');PALE=colors.HexColor('#EEF4ED');LINE=colors.HexColor('#D5E1D5');ORANGE=colors.HexColor('#A55A2A')
STYLE={
 'title':ParagraphStyle('title',fontName='CNB',fontSize=27,leading=36,textColor=INK,spaceAfter=15,wordWrap='CJK'),
 'h1':ParagraphStyle('h1',fontName='CNB',fontSize=18,leading=25,textColor=INK,spaceAfter=14,wordWrap='CJK'),
 'h2':ParagraphStyle('h2',fontName='CNB',fontSize=11.5,leading=18,textColor=TEAL,spaceBefore=10,spaceAfter=7,wordWrap='CJK'),
 'body':ParagraphStyle('body',fontName='CN',fontSize=9.5,leading=16,textColor=INK,spaceAfter=8,wordWrap='CJK'),
 'small':ParagraphStyle('small',fontName='CN',fontSize=8,leading=12,textColor=MUTED,spaceAfter=6,wordWrap='CJK'),
 'cell':ParagraphStyle('cell',fontName='CN',fontSize=8.3,leading=12,textColor=INK,wordWrap='CJK'),
 'headcell':ParagraphStyle('headcell',fontName='CNB',fontSize=8.3,leading=12,textColor=colors.white,wordWrap='CJK'),
 'code':ParagraphStyle('code',fontName='Courier',fontSize=7.2,leading=10,textColor=INK,spaceAfter=7,wordWrap='CJK'),
}


def para(text,style='body'):
    return Paragraph(escape(str(text)).replace('\n','<br/>'),STYLE[style])


def table(rows,widths,header=True):
    cells=[[para(v,'headcell' if header and i==0 else 'cell') for v in row] for i,row in enumerate(rows)]
    t=Table(cells,colWidths=widths,hAlign='LEFT',repeatRows=1 if header else 0)
    commands=[('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7),('LINEBELOW',(0,-1),(-1,-1),.6,LINE)]
    if header:commands += [('BACKGROUND',(0,0),(-1,0),TEAL),('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,PALE])]
    else:commands += [('BACKGROUND',(0,0),(-1,-1),PALE)]
    t.setStyle(TableStyle(commands));return t


class Architecture(Flowable):
    def __init__(self):super().__init__();self.width=505;self.height=313
    def draw(self):
        c=self.canv
        def box(x,y,w,h,title,detail,color=TEAL):
            c.setFillColor(PALE);c.setStrokeColor(LINE);c.roundRect(x,y,w,h,5,stroke=1,fill=1)
            c.setFillColor(color);c.setFont('CNB',10);c.drawString(x+9,y+h-17,title)
            c.setFillColor(INK);c.setFont('CN',8)
            for n,line in enumerate(detail):c.drawString(x+9,y+h-33-n*12,line)
        def arrow(points,label='',labelx=0,labely=0):
            c.setStrokeColor(MUTED);c.setLineWidth(1.1)
            for a,b in zip(points,points[1:]):c.line(*a,*b)
            a,b=points[-2:];dx=b[0]-a[0];dy=b[1]-a[1];length=math.hypot(dx,dy);ux,uy=dx/length,dy/length
            c.line(b[0],b[1],b[0]-5*ux+2.5*uy,b[1]-5*uy-2.5*ux)
            c.line(b[0],b[1],b[0]-5*ux-2.5*uy,b[1]-5*uy+2.5*ux)
            if label:c.setFillColor(MUTED);c.setFont('CN',7);c.drawString(labelx,labely,label)
        box(0,247,125,60,'CMOS2 / OV5640',['1280x720 RGB565','DVP 采集与最终写响应'])
        box(165,247,145,60,'共享 DDR + 三槽帧池',['0x81000000 / 0x81200000','0x81400000；代次与租约'])
        box(350,247,150,60,'共享图像加速器',['推理输入 320x320 INT8','独立预览缩放 680x340'])
        arrow([(125,277),(165,277)],'像素',135,285)
        arrow([(310,277),(350,277)])
        box(0,133,140,68,'RV32 CPU / 70 MHz',['AST1 控制与帧调度','输入预处理协调','检测头解码与 NMS'])
        box(177,133,135,68,'GRAPH_EXECUTOR1 / CPU 时钟域',['每 ARM 编译一次图程序','受限 MMIO 指令执行','204 节点完成与计数'])
        box(350,133,150,68,'硬件算子执行',['NPU: 16x8 /100MHz /48位','S3/Concat: DDR UI 域','按图节点执行共享张量'])
        arrow([(140,168),(177,168)],'控制',146,176)
        arrow([(312,168),(350,168)])
        arrow([(425,247),(425,201)],'输入张量',433,221)
        arrow([(350,139),(328,139),(328,116),(70,116),(70,133)],'三尺度检测头',166,119)
        box(0,17,140,62,'独立预览发布',['最新完整预览帧','原始帧 reader 独立释放'])
        box(177,17,135,62,'识别元数据',['框、类别、置信度','完整推理后更新'])
        box(350,17,150,62,'HDMI / 27 + 135 MHz',['720x480 载波输出','预览与识别异步叠加'])
        arrow([(237,247),(237,224),(151,224),(151,96),(70,96),(70,79)],'预览支路',157,101)
        arrow([(70,133),(70,102),(244,102),(244,79)])
        arrow([(140,48),(160,48),(160,7),(338,7),(338,48),(350,48)])
        arrow([(312,48),(350,48)])


def plots():
    labels=['首轮无检出','不限时复测','展示窗口 1','展示窗口 2']
    values=[r['FPS']['fps'] for r in runs]
    fig,ax=plt.subplots(figsize=(7.1,2.5),layout='constrained')
    ax.bar(labels,values,color=['#22735A','#9AB399','#4B8771','#6B9B82'],width=.55)
    for i,value in enumerate(values):ax.text(i,value+.09,f'{value:.6f}',ha='center',fontsize=10)
    ax.set_ylim(0,4.9);ax.set_ylabel('完整识别 FPS');ax.grid(axis='y',alpha=.2);ax.set_axisbelow(True)
    fig.savefig(FIG/'fps_by_run.png',dpi=220);plt.close(fig)
    fig,ax=plt.subplots(figsize=(7.1,2.45),layout='constrained')
    x=range(4)
    ax.plot(x,[r['interval_ms']['median'] for r in runs],'o-',color='#22735A',label='中位帧间隔')
    ax.plot(x,[r['interval_ms']['p95'] for r in runs],'s-',color='#B07A40',label='P95 帧间隔')
    ax.plot(x,[r['interval_ms']['maximum'] for r in runs],'^--',color='#9C4E38',label='最大帧间隔')
    ax.set_yscale('log');ax.set_ylabel('毫秒（对数轴）');ax.set_xticks(list(x),labels);ax.legend(frameon=False,ncol=3,fontsize=8);ax.grid(alpha=.2)
    fig.savefig(FIG/'interval_jitter.png',dpi=220);plt.close(fig)


def footer(c,doc):
    c.saveState();w,h=doc.pagesize
    c.setStrokeColor(LINE);c.line(42,h-36,w-42,h-36)
    c.setFillColor(MUTED);c.setFont('CN',7.5);c.drawString(42,h-27,'RV32 / GRAPH21  |  实板版本源码与性能分析')
    c.line(42,35,w-42,35);c.drawString(42,23,'实测：2026-11-03  |  整理：2026-11-04  |  固件 ed37c7c631dc7896')
    c.drawRightString(w-42,23,str(doc.page));c.restoreState()


def main():
    plots();story=[]
    def p(text,style='body'):story.append(para(text,style))
    def h(text):p(text,'h2')
    def page(title):
        if story:story.append(PageBreak())
        p(title,'h1')
    def t(rows,widths):story.append(table(rows,widths));story.append(Spacer(1,8))
    W=511
    page('YOLO Graph21\n架构源码与实板性能分析')
    p('对应最后一次实板下载的完整源码、运行证据与注释审计。','small')
    story.append(Spacer(1,10))
    t([['实板完整推理样本','自研源码注释率','验证范围'],['1,367 帧 / 4 轮',f"{comments['summary']['ALL']['comment_percent']:.4f}% / 220 文件",'代码 token 一致\n固件 ELF 字节一致']],[160,170,181])
    h('结论与适用范围')
    p('首轮 120 秒测试正常完成：491 帧，4.088745 FPS，未检出手势。后三轮出现手势输出，平均完整识别速率分别为 2.432295、3.559459 和 3.390387 FPS；三轮都在后续出现串口无响应，不能认定长时间连续运行已经通过验收。')
    p('本交付整理源码、补充中文注释与分析历史证据，没有重新下载 FPGA。注释版的 220 个文件与对应原始文件执行 token 一致；固定实测 build ID 后重新编译的 12 个目标文件和完整 ELF 均与上板产物逐字节一致。')
    h('实板身份')
    t([['项目','版本 / 范围'],['FPGA / 工具','PG2L200H -6 FBB676；PDS 2025.2'],['运行时钟','CPU 70 MHz；NPU 100 MHz；DDR UI 93.75 MHz'],['固件身份','ed37c7c631dc7896'],['位流 SHA256','98d9f5f293812b1d7bf902429f0b8d862d5fcfe74ac141d03bdd34c120873cd0'],['测试方式','真实 CMOS2 摄像头；独立预览；只配置 SRAM，未写 Flash']],[108,403])
    h('交付阅读顺序')
    p('annotated/ 为约 30% 中文注释的架构阅读版；exact/ 保留用于字节级对照与重建的冻结输入；artifacts/ 为当时的位流、ELF、MEM；model/ 为已验证模型资产；evidence/ 保存原始 UART 和实现报告；audit/ 提供逐文件统计与校验收据。')
    p('既有清单中“candidate / not routed / board deferred”等字段保留历史原文。当前实现结论以本包的阶段完成收据、位流哈希和四轮实板记录为准。','small')

    page('01  架构与数据流')
    story.append(Architecture());story.append(Spacer(1,7))
    p('图中为逻辑连接关系，箭头表示数据或控制流，不表示所有步骤按顺序串行执行。摄像头原始缓冲与模型输入、预览帧缓冲互相分离；预览与推理作为两个消费者读取原始帧。','small')
    t([['层次','源码入口（annotated/project 下）','职责'],['板级','stage_ddr_hdmi/board/soc_board_camera_top.sv','时钟、引脚、DDR 与图像/显示集成'],['SoC / CPU','stage_ddr_hdmi/rtl/top/soc_soc_top.sv\nstage_ddr_hdmi/rtl/rv32/rv32_d1_cpu_tile.sv','RV32 控制核心、MMIO、内存与中断'],['图执行','stage_ddr_hdmi/rtl/gex/soc_graph_executor.sv\nfirmware_displayready_src/graph_executor.h','图程序编译、命令执行、完成检查'],['NPU','stage_ddr_hdmi/rtl/npu/npu_accel_top.sv','16x8 阵列、DMA、驻留操作数和结果写回'],['帧调度','firmware_displayready_src/live_frame_pool.h\nfirmware_displayready_src/camera_frame_pool.h','三槽帧池、共享 IMG、识别及预览发布']],[66,267,178])
    p('RV32 的适配文件仍声明模块名 soc_cpu_tile_v15，并实例化 rv32_ooo_core。源码树中旧 core/ 和其他同名适配文件属于保留参考；应按 sources_pango.f 和实际 PDS 清单构建，不能对目录中全部 RTL 盲目 glob。','small')

    page('02  一帧如何完成')
    t([['边界','实际动作','成立条件 / 证据'],['1. 原始采集','DVP 字节流跨域后写入 DDR','摄像头 DONE 且非 BUSY；最终写响应已退休'],['2. 原始帧发布','槽进入 READY，分配 generation','写入与传感器像素均 921600，错误为 0'],['3. 取得输入','推理消费者租用最新完整槽，提交 320x320 预处理','reader 位与 generation 同时验证；共享 IMG 完成后释放租约'],['4. 图执行','CPU 为该帧启动 GRAPH_EXECUTOR1，硬件派发 Conv / S3 / Concat / 张量节点','图程序有效、上下文代次一致；节点完成和计数检查通过'],['5. 解码 / NMS','CPU 读取三尺度检测头，生成检测结果','Q15 分数与候选/结果容量限制；每帧可正常未检出'],['6. 结果发布','发布最近的框、类别和置信度到独立预览','TR 是完整推理结果边界；预览 vblank 确认是另一条事件链']],[66,208,237])
    h('所有权与故障边界')
    p('原始帧槽可同时由推理和预览持有 reader；生产者只能重用无 reader 的槽。generation 在 ARM/STOP 之间保留，旧释放令牌不能作用于新一帧。GRAPH_EXECUTOR poison 只能由公共复位清除，已接受而超时的 MMIO 响应不能被转交给另一个主机。')
    h('内存布局与本轮策略')
    t([['区域','有效内容 / 规则'],['0x81000000 / 0x81200000 / 0x81400000','三槽 RGB565 原始缓冲；每槽有效 1843200 字节，槽间距 2 MiB'],['0x82200000 / 0x82300000','两个独立预览帧缓冲；每帧 680x340x2 = 462400 字节'],['像素缺失停止阈值','退休后缺口 max(921600-written, 921600-sensor, 0) >= 92160 时停止；更小坏帧丢弃继续'],['等待策略','V3 等待输入和未检出没有经过时长退出条件；硬件/协议错误检查仍保留']],[193,318])
    p('内存表描述源代码契约，不代表已经实测全 DDR 占用或全系统带宽。本轮保留已验证的地址方案，未继续暂停中的 DDR 地址优化。','small')

    page('03  模型与执行器配置')
    t([['项目','由模型清单 / 源码得到的值'],['输入与数据格式','320x320x3；HWC 有符号 INT8；权重按 K-major、每组最多 8 个输出通道排列'],['检测头','40x40 / 20x20 / 10x10，stride 8 / 16 / 32；6 类手势'],['图规模','144 个语义算子展开为 204 个描述符节点'],['节点构成','Conv 60；Requant 60；LUT 57；Concat 15；Pool 3；Upsample 2；Add 7'],['卷积运算量','518,732,800 MAC / 帧，按 60 个卷积描述符静态求和'],['NPU 阵列','16 行 x 8 列 = 128 个 PE；48 位累加；100 MHz；乘法流水参数为 2'],['图程序容量 / 本轮装载','容量 32768 个 32 位字；首轮装载 20332 字（5083 条四字指令）'],['模型资产','317 项常量，1,856,488 字节；相机输入帧不作为常量上传']],[133,378])
    h('静态工作量与实测性能的关系')
    p('若按一次乘加计 2 次运算，128 PE 在每个时钟都有效喂数的理想上界为 25.6 GOP/s。该值仅是阵列结构上界，不含输入装载、drain、量化、拼接、NMS 或等待；本包没有把它当作实测板级吞吐或利用率。')
    p('按卷积 MAC 数乘实测 FPS 换算，首轮完整输出对应约 %.3f GMAC/s；后三轮对应约 %.3f 至 %.3f GMAC/s。这是网络卷积工作量的等效输出速率，不能替代硬件 active/DMA-wait 计数。' % (model['MACs_per_inference']*runs[0]['FPS']['fps']/1e9,min(model['MACs_per_inference']*r['FPS']['fps']/1e9 for r in runs[1:]),max(model['MACs_per_inference']*r['FPS']['fps']/1e9 for r in runs[1:])))
    h('主机与固件的分工')
    p('主机经 AST1 上传并回读验证模型。ARM 后，CPU 在片上编译并装载图程序；GRAPH_EXECUTOR1 按允许的 MMIO 范围派发图节点；CPU 保持协作式采集/预处理服务并执行检测头解码与 NMS。GUI 只观察完整结果，未通过每帧 START 命令驱动性能。')
    p('模型资产清单中的 eb1fbf30aa8f08e1 是历史包兼容标识；当前板上执行固件由 nonce 身份检查确认为 ed37c7c631dc7896。两者含义不同，原清单均原样保留。','small')

    page('04  四轮实板吞吐与抖动')
    rows=[['轮次','完整帧','有效区间 s','FPS','平均间隔 ms','最终状态']]
    names=['首轮 120 秒','不限时复测','展示窗口 1','展示窗口 2']
    for i,r in enumerate(runs):rows.append([names[i],r['frames'],f"{r['FPS']['elapsed_seconds']:.3f}",f"{r['FPS']['fps']:.6f}",f"{r['FPS']['average_interval_ms']:.3f}",'正常停止' if i==0 else '后续串口无响应'])
    t(rows,[85,49,80,85,91,121])
    story.append(Image(str(FIG/'fps_by_run.png'),width=489,height=172))
    story.append(Image(str(FIG/'interval_jitter.png'),width=489,height=169))
    p('计时公式：FPS = (末完成计数 - 首完成计数) x 70,000,000 / (末 TR - 首 TR)。N 个连续样本覆盖 N-1 个间隔。包含未检出的完整推理；不计模型加载和最后一次成功后串口失联的等待。','small')
    p('首轮 491 帧均未检出，保存的末帧中未见手部。后三轮有手势输出；数据并非同一人工标注数据集上的严格 A/B。中位间隔约 259 ms 的同时，后三轮最大间隔分别达到 7443.942、1429.163、4749.240 ms，均值因此不能只用图执行耗时解释。','small')

    page('05  单帧阶段延迟与流水重叠')
    keys=[('capture_seconds','所用原始帧的采集'),('preprocess_seconds','采集结束到预处理完成'),('graph_seconds','204 节点图执行'),('NMS_seconds','解码与 NMS'),('START_to_READY_seconds','采集开始到结果准备完成')]
    rows=[['平均耗时 / ms','首轮','不限时复测','窗口 1','窗口 2']]
    for key,label in keys:rows.append([label,*[f"{r['stage_ms'][key]['mean']:.3f}" for r in runs]])
    t(rows,[183,82,82,82,82])
    h('解释这些数字')
    p('采集结束到预处理完成包含输入年龄及共享 IMG 的等待，不能称为纯缩放核时延。START-to-READY 描述单帧从采集开始到结果准备完成的跨度；帧池允许不同帧的采集、预处理、图执行和显示相互重叠，因此其倒数不等于完整结果输出 FPS。')
    p('最后一轮单帧跨度均值为 452.196 ms，连续完整输出间隔均值为 294.952 ms；这两个值同时成立。首轮图执行均值 221.106 ms，已经接近 244.574 ms 的平均输出间隔；但后三轮图执行均值仍约 221 至 225 ms，不能据此解释最长数秒停顿或串口失联。')
    h('首轮已完成的硬件计数闭环')
    t([['检查','真实记录'],['硬件图启动 / 完成','491 / 491；最后一帧完成节点 204'],['批次数 / 算子数 / 错误','491 / 100164 / 0'],['S3 / LUT 工作次数','29460 / 27987；fallback 0'],['Concat 任务 / 失败','7365 / 0'],['摄像头 / 独立预览','有效采集 954；坏采集 0；预览确认 953'],['实际预览更新速度','7.930407 次确认/秒；与 59.94 Hz HDMI 载波及识别 FPS 分别统计']],[170,341])
    p('阶段性能计数可能互相重叠，部分兼容字段有固定位宽；本报告的整体时延和 FPS 优先使用独立 CPU64 工作流时间戳。其余三轮未取得正常 STOP 后的采集/预览汇总，不能把首轮 0 坏帧推广到全部运行。','small')

    page('06  模型传输、内存正确性与检测输出')
    a,b=runs[2:]
    rows=[['传输项目','展示窗口 1','展示窗口 2']]
    for label,key,scale in [('加载与回读总时间 / s','elapsed_seconds',1),('上传+回读平均有效 KiB/s','average_bytes_per_second',1024),('上传有效 KiB/s','upload_bytes_per_second',1024),('回读有效 KiB/s','readback_bytes_per_second',1024)]:rows.append([label,f"{a['model_transfer'][key]/scale:.3f}",f"{b['model_transfer'][key]/scale:.3f}"])
    t(rows,[221,145,145])
    p('每轮模型有效字节为 1,856,488，上传加逐字节回读为 3,712,976；317 项全部通过 SHA256 比对。均速包含该模型传输流程的间隙和校验开销，方向速度按对应请求耗时统计。GUI 最近 3 秒速率来自已完成的真实有效载荷字节，不含协议包头，也不混入位流下载和 DDR 自检。')
    p('三次 SRAM 位流下载耗时 34.562 至 35.765 秒；包含固件启动验证的下载阶段约 52.859 至 55.265 秒。每次完整初始化的 11 项 DDR 读写/多地址独立性检查均通过；这不是全 DDR 容量或极限带宽测试。')
    h('四轮检测输出分布')
    rows=[['类别','输出帧数','平均模型置信度']]
    for x in data['class_outputs']:rows.append([x['class_name'],x['output_frames'],f"{x['average_model_confidence_percent']:.2f}%"])
    t(rows,[171,170,170])
    p('共 1367 帧完整推理，其中 686 帧有选定检测结果、681 帧未检出。这里的次数和置信度是模型输出分布；缺少逐帧人工真值，不能当作准确率、召回率或 mAP，也不能把未检出帧一律当成漏检。','small')

    page('07  稳定性现象与后续定位优先级')
    t([['会话','最后已确认结果','之后发生的事'],['首轮 120 秒','491 帧；采集/图/预览计数闭环','STOP 确认，所有权排空'],['不限时复测','346 帧；有效区间 141.841 秒','旧宿主等待串口 20 秒后报错；板端停止未知'],['展示窗口 1','246 帧；有效区间 68.831 秒','后续无回应，等待约 565.9 秒后结束等待；停止未确认'],['展示窗口 2','284 帧；有效区间 83.471 秒','后续无回应，等待约 4.0 秒后结束等待；停止未确认']],[102,175,234])
    h('证据支持的判断')
    p('首轮证明该位流可执行完整真实摄像头图推理、独立预览及正常停止。后三轮在最后成功的完整推理边界之前，输入像素和图节点记录通过一致性检查，但其后缺少响应；没有足够现场数据证明失联由摄像头 10% 丢像素阈值、NPU、DDR、CPU 或串口某一个环节单独造成。')
    p('窗口版取消了实时只读状态回复的时间上限。没有新回复时，窗口显示等待、隐藏实时 FPS 主值并保留上次实测值；这避免把等待超时等同于硬件已停，但并未修复实际无响应的根因。')
    h('建议的定位顺序（本次未执行新实验）')
    p('1. 为最后成功帧之后的 CPU 阶段、UART 接收/发送、GRAPH_EXECUTOR busy/poison、IMG 与原始帧租约建立同帧标识的进展证据，区分主循环停顿、总线等待和物理通信断开。')
    p('2. 优先复现有人手变化和较大帧间隔场景，保存首次异常前后的状态，而不是在重配后推断旧现场。维持当前时钟与已验证 DDR 地址方案。')
    p('3. 在稳定性问题定位后，再用受控相同输入比较图执行、操作数驻留、结果写回和预览争用；单纯放宽宿主等待不能作为性能优化或稳定性通过的证据。')
    p('本包不新增定时任务、不重新上板、不修改已封存工程；上述是下一步可选实验方向。整板功耗、温度、DDR 极限带宽及 CPU/NPU 真实利用率尚无本轮实测数据。','small')

    page('08  实现资源与时序报告')
    t([['最终实现资源','使用 / 可用','比例'],['CLMA','20269 / 30075','67.39%'],['CLMS','6318 / 9875','63.98%'],['APM 物理 grid','118 / 370','31.89%'],['APM 单元','227 / 740','30.68%'],['DRM 物理 grid','222 / 415','53.49%'],['IO','121 / 400','30.25%']],[200,170,141])
    p('资源取自最终 route optimize 的 PDS 报告。物理 grid 与逻辑单元统计口径不同；上述是静态占用，不是运行时利用率。','small')
    rows=[['STA 项目','Slow 最差余量 / ns','Fast 最差余量 / ns']]
    for kind in ('Setup','Hold','Recovery','Removal','Minimum Pulse Width'):
        rows.append([kind,f"{physical['timing_minimums'][kind+' Slow']['worst_ns']:.3f}",f"{physical['timing_minimums'][kind+' Fast']['worst_ns']:.3f}"])
    t(rows,[200,155,156])
    p('10 组时序汇总均无失败端点；最差 setup 为 0.177 ns、hold 为 0.020 ns。报告约束对应 CPU 70 MHz、NPU 100 MHz、DDR UI 93.75 MHz、HDMI 27/135 MHz；全部 155565 条网线完成布线。')
    p('STA 的 All Constraints Met 覆盖其实际分析的路径。DDR 硬 PHY、TMDS 外部链路和异步引脚的板级裕量不能仅由该摘要认证；本包保留完整 .rtr 和约束覆盖说明，不声称已经完成外部 I/O 极限条件认证。')
    h('复现输入')
    p('exact/runtime_policy/workspace 是当次 PDS 的冻结输入。116 个实际综合输入含转换后的 design.v、独立 RV32 Verilog 及厂商 IP；3 项约束与 456 个冻结文件哈希已校验。不能用目录名称或较早的 inherited qualification 清单替代本次完成收据。')

    page('09  注释审计与源码一致性')
    rows=[['范围','文件数','代码行','纯注释行','注释率']]
    for name,label in [('RTL','自研 RTL'),('firmware','固件 C/H'),('host','主机 Python'),('ALL','合计')]:
        x=comments['summary'][name];rows.append([label,x['files'],x['code_lines'],x['comment_lines'],f"{x['comment_percent']:.4f}%"])
    t(rows,[112,65,105,105,124])
    p('统计口径：纯注释物理行 /（代码物理行 + 纯注释物理行）。空行不计；含代码的行尾注释仍算代码行；Python docstring 按代码计算。范围是 audit/ANNOTATED_FILE_SCOPE.txt 列出的 220 个文件。')
    p('不纳入统计的文件包括加密/厂商 IP、PDS 转换后的生成 Verilog、自动生成模型 LUT/白名单、未选中的旧 RTL 和测试平台。它们仍按原样保留在 exact 或参考目录中。逐文件数据见 audit/源码注释率逐文件.csv。')
    h('一致性保证')
    t([['检查','结果'],['220 文件执行 token 对照','全部一致；Python 同时比较不含行号属性的 AST'],['独立注释计数','Pygments 对 220 文件复核，代码/纯注释行数全部一致'],['固定实测身份的固件复编','12 个目标文件全部字节一致；完整 ELF 字节一致'],['原始固件 ELF SHA256','6c102fbe9049cf215e08b3a0c43c08fe2fd0da1413204a0fd2314c84148deba0'],['原件保护','exact 冻结来源保持字节不变；仅 annotated 副本添加注释']],[170,341])
    p('固定实测 build ID 的复编用于检查注释不改变机器码。原身份生成器还会哈希源码文本和路径；若直接对注释版运行它，得到新的 build ID 属于身份机制预期，不能冒称新构建已由旧位流上板验证。')
    p('注释以模块职责、接口字段、状态/握手条件、所有权与关键控制为主。原始版权、许可声明和综合属性均保留。已标出 CPU 适配模块名、默认参数和板级覆盖参数之间的关系。','small')

    page('10  复现方法与证据索引')
    h('离线检查')
    p('在解压后的工作副本中执行下面命令。检查器只读源码、模型和证据，不打开 COM/JTAG。')
    p('python tools/check_delivery.py','code')
    h('准备同一 PDS 输入')
    p('使用短的新输出路径，避免 PDS/Windows 路径长度限制：')
    p('python exact/unified_runtime.py prepare yolo --out D:/b/g21_new','code')
    p('然后使用已安装的 PDS 2025.2，按 synthesis、route、timing、bitstream 顺序运行；每一步消费同一新构建的上游结果：')
    p('python exact/unified_runtime.py run --out D:/b/g21_new\n  --stage synthesis --pds <pds_shell.exe> --license <license.lic>','code')
    p('上述 prepare 已在本次离线复核中执行，116 项综合输入及全部冻结哈希匹配。未为补注释重新运行耗时综合/布线，也未进行新的下载或上板。重建产物的物理时序和实板行为仍需按新构建验收。')
    h('源码与证据入口')
    t([['目录 / 文件','用途'],['annotated/project/','带中文注释的 RTL、固件及源码阅读上下文'],['annotated/host/','现场上板脚本、协议解码和展示窗口的注释版'],['exact/','字节级冻结源、原样现场主机代码和原构建驱动'],['artifacts/','实测 sbit；固件 ELF/MEM/map/目标文件'],['model/canonical_model/','317 项常量及原有模型、参考元数据'],['evidence/board/','四轮原始回复、时间戳和结果；包括正常停止与失联证据'],['audit/','逐文件注释率、token 对照、独立计数、复编和最终包校验'],['reports/REAL_BOARD_DATA_20261104.json','逐帧时延统计、输出分布、原始记录索引']],[210,301])
    p('原始主机源码保留现场绝对路径；当前机器的既有展示入口为 D:/workspace/riscv-fpga-soc/打开YOLO识别展示窗口.cmd。离线构建/检查入口使用包内相对路径。model/ 附有与部署清单 SHA256 一致的 INT8 ONNX 导出图；本次未重新训练或量化。实测 FPS 在主机窗口显示，HDMI 沿用预览与识别元数据，尚未接入硬件 FPS 数字。','small')
    p('数据范围：2026-11-03 四轮实板记录，2026-11-04 复核整理。没有人工真值精度测试、功耗测试或 DDR 极限带宽测试；没有把仿真约 6 FPS 当作实板成绩。','small')

    output=REPORT/'YOLO_Graph21_架构源码与实板性能分析_20261104.pdf'
    doc=SimpleDocTemplate(str(output),pagesize=(595.276,841.89),rightMargin=42,leftMargin=42,topMargin=52,bottomMargin=48,title='YOLO Graph21 架构源码与实板性能分析',author='rv32_soc 工程交付')
    doc.build(story,onFirstPage=footer,onLaterPages=footer)
    print(output)


if __name__=='__main__':main()
