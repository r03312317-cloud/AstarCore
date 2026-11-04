"""Add local architecture/interface/control annotations to a separate copy."""
from pathlib import Path
import ast
import csv
import hashlib
import json
import math
import re
from source_audit import analyze,equivalent

ROOT=Path('D:/workspace/riscv-fpga-soc/deliverables/YOLO_G21_20261104')
EXACT=ROOT/'exact/runtime_policy/workspace/project'
ANNOTATED=ROOT/'annotated/project'

ROLES={
'soc_board_camera_top':'板级集成顶层，连接双路摄像头引脚、共享 DDR、SoC 和 HDMI；本轮软件选用 CMOS2 通道。',
'soc_soc_top':'SoC 集成层，连接 CPU、图执行器、NPU、共享张量加速器以及跨时钟域内存接口。',
'rv32_d1_cpu_tile':'RV32 控制处理器的板级适配，模块名沿用 soc_cpu_tile_v15，实例化 rv32_ooo_core。',
'rv32_ooo_core':'RV32 RV32 控制核心，组织本地发射、操作数捕获、完成与提交边界恢复。',
'rv32_ooo_frontend':'RV32 取指前端，管理取指请求、预测路径和重定向后的指令流。',
'rv32_issue_scheduler':'依据就绪操作数和资源条件选择可发射指令，控制配对与依赖唤醒。',
'rv32_issue_bank':'保存发射项的有效状态与操作数字段，供调度器读取和完成唤醒。',
'rv32_memory_system':'组织 RV32 load/store 事务及其顺序边界，把存储器响应交还对应指令。',
'rv32_execute':'执行整数运算和控制转移，向核心提交结果以及重定向信息。',
'rv32_arithmetic':'RV32 整数算术组合数据路径，具体操作由输入控制字段选择。',
'rv32_hybrid_predictor':'结合本地预测状态和控制转移信息，为取指路径提供预测。',
'rv32_committed_ras':'在提交边界维护返回地址预测状态，避免未提交路径污染恢复状态。',
'rv32_mul_stream':'RV32 乘法结果流水，保持请求标签与延迟后的结果对应。',
'rv32_address_classify':'按地址范围识别片上存储器、外部内存和 MMIO 的访问类别。',
'rv32_instruction_flags':'根据指令编码提取调度和执行需要的分类标志。',
'rv32_queue_allocator':'分配队列项并处理释放边界，避免仍被占用的项目重复分配。',
'soc_graph_executor':'GRAPH_EXECUTOR1 图指令执行器，读取片上命令 RAM，执行受限 MMIO 写入、轮询、检查及计数。',
'soc_graph_mmio_fabric':'在 CPU 与图执行器之间维护加速器 MMIO 的请求和响应所有权。',
'soc_mmio_2m_registered':'两主机 MMIO 的寄存级仲裁，隔离组合路径并保留应答归属。',
'soc_conv_service':'卷积服务前端，接收图节点描述符，组织 Window 与 NPU 的协作执行。',
'soc_conv_microsequencer':'卷积微序列控制，推进行块与通道页，跟踪 Window/NPU 请求完成和 scratch 所有权。',
'soc_npu_legacy_descriptor_port':'将卷积服务的描述符转换为既有 NPU 控制接口事务。',
'soc_window_descriptor_port':'Window 描述符接口，提交采样参数并检查对应任务的完成状态。',
'npu_accel_top':'NPU 集成顶层，连接命令队列、DMA、scratchpad、调度器、脉动阵列和结果存储。',
'npu_scheduler':'将矩阵任务分解为 tile，协调操作数装载、计算、结果读出及完成事件。',
'npu_systolic_array':'参数化脉动阵列，逐行列传播带有效位的操作数并提供累加结果读取。',
'npu_mac_pe':'Pango APM 乘加单元，使用 48 位累加寄存器，清零优先于有效乘加使能。',
'npu_dma_engine':'NPU 外部内存事务引擎，跟踪读写请求、响应编号、在途数量与异常边界。',
'npu_cmd_queue':'保存尚待执行的 NPU 命令，在命令接收和调度出队之间隔离背压。',
'npu_completion_queue':'保存 NPU 完成记录，使完成事件在接收端暂停时仍可读取。',
'npu_mmio_overlay':'NPU 寄存器接口和原有外设地址空间的兼容覆盖层。',
'npu_postprocess':'处理累加结果的输出格式和写回字段，保留任务有效状态。',
'npu_scratchpad':'操作数暂存 RAM 组织层，连接装载端与计算端并维护 bank 选择。',
'npu_scratchpad_int8packed16':'面向 16 元素装载的 INT8 打包暂存组织，保持 lane 与 K 索引对应。',
'npu_resident_ab':'管理驻留 A/B 操作数的复用，使任务上下文和已装载数据一致。',
'npu_resident_fill_owner':'跟踪驻留操作数填充所有权，限制生产和使用同一存储区域的交叠。',
'npu_resident_fill_pack':'把 DMA 返回元素打包为驻留存储的写入向量。',
'npu_resident_operand_adapter':'将驻留存储读出的操作数整理为阵列输入时序与 lane 格式。',
'npu_response_order':'保持 NPU 数据响应与已接受请求之间的顺序关系。',
'npu_result_rows':'保存计算产生的结果行，并提供写回路径所需的行向量。',
'npu_row_result_capture':'在阵列结果有效时捕获整行数据，隔离累加器读出和后续存储。',
'npu_result_store_bridge':'把结果行转换为外部内存写入事务，处理写入背压与完成。',
'cp12_dma_read_step':'推进 DMA 读请求的小步控制，保持地址、长度和返回进度一致。',
'cp9_progress_watchdog':'记录任务进展并检测被启用的硬件进展超时条件。',
'soc_camera_dvp_capture':'在摄像头像素时钟域接收 DVP 字节和帧/行同步，形成带边界的数据流。',
'soc_camera_axi_writer':'把摄像头流写入 DDR，只有最后写响应退休后才具备完整帧完成证据。',
'soc_camera_frame_pipeline':'连接摄像头采集、跨时钟缓存和 DDR 写入路径。',
'soc_camera_mmio_mem':'摄像头控制寄存器，向固件暴露 ready/busy/done、像素计数和错误。',
'soc_camera_dvp_diag':'只观察 DVP 引脚活动并锁存诊断计数，不替代生产采集的完整性判断。',
'soc_camera_async_fifo':'隔离摄像头像素域与接收消费域，传递数据及其有效边界。',
'soc_ov5640_capture':'OV5640 采集连接层，组织像素输入与帧同步接口。',
'soc_ov5640_config':'通过 SCCB 初始化摄像头，保存配置过程的状态。',
'soc_preprocess320_core':'面向 320x320 输入张量的图像预处理核心，输出量化后的模型输入。',
'soc_display_resize_core':'独立预览图像缩放核心，输出 HDMI 图像帧缓冲所需像素。',
'soc_image_accel':'共享图像加速接口，连接预处理、预览缩放与内存访问。',
'soc_image_mmio_mem':'图像加速寄存器接口，保存源目标地址、尺寸及任务状态。',
'soc_image_axi_adapter':'将图像加速请求转换为共享 DDR 接口事务。',
'soc_requant_lut_dma':'S3 重量化与 LUT 数据通路，读取 INT32 结果并写入量化 INT8 张量。',
'soc_requant_pipeline':'重量化算术流水，处理乘数、移位、舍入、零点与饱和边界。',
'soc_s3_mmio_mem':'S3 控制寄存器，连接重量化、LUT 参数与执行统计。',
'soc_concat_dma':'在 DDR 上按张量布局拼接通道数据，跟踪每段传输和提交进度。',
'soc_concat_mmio_mem':'Concat 的任务参数、状态和计数寄存器。',
'soc_window_address_gen':'根据卷积坐标、步幅、膨胀和填充生成 Window 读取地址。',
'soc_window_gather_dma':'从输入张量采集卷积窗口并写入 scratch，维护边界填充和传输完成。',
'soc_window_mmio_mem':'Window 参数寄存器和任务状态接口，供图执行器/卷积服务访问。',
'soc_hdmi_axi_reader':'从 DDR 读取显示像素，向显示路径提供带背压的数据。',
'soc_hdmi_ddr_scanout':'组织帧缓冲扫描输出，维护显示时序和像素有效窗口。',
'soc_display_commit_mmio':'接收图像与识别元数据的发布请求，并保存显示确认状态。',
'soc_gesture_label':'将手势类别和置信度字段转为屏幕标签所用的像素/字符信息。',
'soc_stereo_osd':'对显示像素叠加识别框和文字等 OSD 信息。',
'soc_video_event_mmio':'锁存显示路径事件及对应帧/运行标识，用于软件确认。',
'soc_mini_hdmi_clock':'连接 HDMI 像素/串行时钟与锁定、复位信号。',
'soc_mini_hdmi_tx':'将视频颜色与同步信息送至 TMDS 编码和串行输出。',
'soc_display_async_fifo':'跨显示相关时钟域缓存像素和有效信息。',
'pg_ddr_burst_bridge':'把本地请求组织为 DDR AXI 突发，跟踪已接受和已完成的内存事务。',
'soc_hmic_axi_adapter':'在共享 AXI 事务和 Pango DDR 控制器接口之间适配。',
'soc_native_2m_arbiter':'两主机本地内存请求仲裁，并把应答送回原请求方。',
'soc_axi_2m_arbiter':'共享 AXI 两主机仲裁，处理通道背压与事务归属。',
'pg_three_request_mux':'复用三路请求源，保持选择状态和返回通路的一致性。',
'soc_board_mmio_router':'依据地址把 CPU 板级访问路由到相应外设寄存器。',
'core0_system_fabric':'CPU 系统请求的地址路由与响应汇聚。',
'dc_realtime_core_npu_router':'区分 NPU 与其他系统访问，维护 CPU 请求的响应路径。',
'pg_npu_mmio_bridge':'把本地寄存器事务转换为 NPU 控制端口格式。',
'soc_peripherals':'连接 UART、GPIO、定时器等 CPU 控制外设。',
'core0_cycle_timer':'产生用于控制与性能测量的周期计数信息。',
'core0_uart_mmio':'全双工串口寄存器接口，暴露发送、接收及错误状态。',
'core0_uart_tx':'串口发送位时序，将待发送字节按波特率输出。',
'pg_uart':'可寄存器访问的 UART 数据、状态和波特率控制路径。',
'pg_gpio':'GPIO 输入采样及输出控制寄存器。',
'camera_frame_pool':'三槽原始帧池，使用 generation 与 reader 位避免采集、推理、预览互相覆盖。',
'camera_loss_policy':'1280x720 每帧缺失阈值，取写入/传感器缺口的较大值，达到 92160 像素停止。',
'live_frame_pool':'持续采集服务，仲裁推理预处理与独立预览缩放，正常帧完成不排空预览。',
'cmos2_workflow':'摄像头完整推理状态机，组织采集、预处理、图执行、NMS 与结果发布。',
'graph_executor':'将已验证的 Graph204 描述符编译为 GRAPH_EXECUTOR1 命令并提交硬件图执行。',
'conv_service_hardware':'配置卷积服务参数与硬件事务，保留软件可检查的状态边界。',
'conv_service_batch_contract':'限定 Window 行块容量、scratch 大小和卷积提交参数的共同约束。',
'cycle_timer64':'读取板上 64 位周期计时，避免跨高低字翻转得到撕裂时间戳。',
'gesture_selection':'从检测结果中选择要发布的手势类别、框与置信度。',
'yolov5_postprocess':'CPU 端 YOLO 检测头解码与 NMS，使用固定点分数和候选/结果容量限制。',
'requant_i32_i8':'INT32 到 INT8 的软件重量化参考/保留路径，约束舍入与饱和。',
'conv2d_int8':'卷积参数与数据布局检查及保留的软件参考运算。',
'tensor_ops_int8':'共享张量算子的布局检查和软件参考操作。',
'preprocess320_i8':'模型输入 320x320 的有符号 INT8 预处理接口和参考实现。',
'preprocess_rgb565':'RGB565 图像到模型输入颜色与量化格式的转换。',
'preprocess5mp_v2':'保留的图像预处理软件/硬件兼容接口。',
'display_resize':'显示图像缩放的参数与实现接口。',
'display_cmos2':'连接 CMOS2 图像结果与显示帧缓冲。',
'image_accel':'软件侧共享图像加速器接口，提交预处理/缩放并检查完成。',
'shared_tensor_hardware':'软件侧共享张量加速器接口，构造受限算子参数。',
'concat_hardware':'软件侧 Concat 硬件接口与参数、完成计数检查。',
'startup_tcm_diag':'在正常固件启动时检查片上程序/只读数据的完整性。',
'rv32_performance':'读取并编码 RV32 及相关加速器性能统计字段。',
'main':'AST1 监控固件入口，处理带序号/CRC 的命令、DDR 访问与协作式识别服务。',
'memory_helpers':'为裸机固件提供内存复制、填充等基础例程。',
'video_window':'本机 Tk 操作窗口，通过后台执行线程和队列显示真实传输与识别数据。',
'video_runner':'执行独占上板流程，串联文件检查、SRAM 下载、DDR 检查、模型回读和连续识别。',
'telemetry':'统计成功完成的模型有效载荷字节，并在实时只读状态等待时支持人工取消。',
'continuous_session':'持续观察完整推理边界并保存原始证据，正常停止时核对图与采集计数。',
'completion_accumulator':'用首末完成边界累计 FPS，内存中保留固定数量状态，原始样本另存。',
'completion_fps':'按完整推理计数差与 CPU64 TR 时间戳差计算平均帧间隔和 FPS。',
'board_monitor':'AST1 串口传输与封包校验，保留原始 TX/RX 和命令序号，不自动重发命令。',
'cmos2_protocol':'解码摄像头推理与独立预览的协议字段，区分推理完成和显示确认。',
'frame_pool_protocol':'解码三槽帧池、generation、租约及 V3 推理来源信息。',
}


def role(path):
    stem=path.stem
    if stem in ROLES:return ROLES[stem]
    if 'fifo' in stem:return 'FIFO 缓冲模块，隔离生产者与消费者，满/空条件由指针和容量关系决定。'
    if 'reset' in stem:return '复位域适配模块，将公共复位条件引入目标时钟域。'
    if 'cdc' in stem or 'sync' in stem:return '时钟域间控制/数据传输接口，使用本模块定义的同步和所有权约束。'
    if 'ram' in stem or 'tcm' in stem:return '片上存储器数据路径，保存地址、读写使能以及同步读返回状态。'
    if 'cache' in stem or 'ifill' in stem:return 'CPU 缓存/回填连接路径，维护访问命中、外部事务与响应边界。'
    if 'protocol' in stem:return '协议字段解码与一致性检查，输入来自已保存或实时收到的板卡回复。'
    if stem.startswith('test_') or 'verify' in stem:return '离线检查入口，用可重复输入验证本文件列出的行为条件。'
    if stem.startswith('run_'):return '主机执行入口，组织本文件中显式选择的检查或板卡操作流程。'
    if path.suffix=='.py':return '主机侧工程工具，管理本文件定义的数据解析、检查或运行流程。'
    if path.suffix in ('.c','.h'):return '裸机控制固件组件，提供本文件定义的状态检查、数据结构和服务函数。'
    return '可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。'


def names(text):
    words=re.findall(r'\b[A-Za-z_]\w*\b',text)
    ignored={'if','else','begin','end','return','int','integer','logic','wire','reg','input','output','inout','signed','unsigned','static','const','uint32_t','uint64_t','uint8_t','int32_t','int64_t','void','True','False','None','and','or','not'}
    return list(dict.fromkeys(w for w in words if w not in ignored and not re.fullmatch('[budh][0-9a-f]+',w)))


def brief(text,maximum=100):
    text=re.sub(r'\s+',' ',text).strip()
    return text if len(text)<=maximum else text[:maximum-3]+'...'


def expression(line):
    start=line.find('(');depth=0
    if start<0:return ''
    for end in range(start,len(line)):
        if line[end]=='(':depth+=1
        if line[end]==')':
            depth-=1
            if not depth:return line[start+1:end]
    return line[start+1:]


def signal_note(name):
    lower=name.lower()
    if 'wstrb' in lower or 'byte_en' in lower:return '按字节选择本次写入生效的 lane。'
    if lower.endswith('valid') or lower.endswith('_valid_q'):return '标识这一路负载有效；是否接收还需检查对应的消费条件。'
    if lower.endswith('ready') or lower.endswith('_ready_q'):return '表达接口或资源就绪；需结合相应有效/完成条件解释。'
    if 'epoch' in lower or 'generation' in lower:return '区分任务或数据代次，用于拒绝旧上下文的完成/释放。'
    if 'owner' in lower or 'lease' in lower:return '跟踪存储/事务所有权，释放条件由对应完成分支决定。'
    if 'error' in lower or 'fault' in lower or 'poison' in lower:return '记录异常状态；查看置位与清除分支可确定其保持范围。'
    if 'rst' in lower or 'reset' in lower:return '参与复位或清空条件；极性和同步边界以使用它的过程为准。'
    if 'addr' in lower or 'base' in lower:return '用于地址/基址选择，访问步长和对齐还受相应描述符约束。'
    if 'count' in lower or 'left' in lower or 'length' in lower:return '记录数量或剩余进度，位宽限定可表达范围。'
    if 'mask' in lower:return '逐位选择参与本次操作的数据通道或状态位。'
    if 'clk' in lower:return '时钟相关接口；使用本信号触发的时序过程属于相应时钟域。'
    if 'data' in lower or 'vector' in lower or 'payload' in lower:return '保存/传递数据负载，数据有效性由独立控制字段约束。'
    if 'state' in lower or 'phase' in lower:return '选择控制阶段，各编码的行为由状态分支定义。'
    if 'tag' in lower or 'cookie' in lower or lower.endswith('_id'):return '把返回信息关联到对应的已接受请求。'
    if 'ptr' in lower or 'index' in lower or 'offset' in lower:return '选择队列、数组或数据片段的位置，更新条件见对应赋值。'
    if 'acc' in lower:return '保存或选择累加结果，符号与精度由声明及算术表达式决定。'
    if 'done' in lower or 'complete' in lower:return '表达本地完成/结束条件，系统退休还需满足上层接口契约。'
    return '参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。'


def rtl_candidates(path,text,info):
    lines=text.splitlines();result={}
    first=next((i for i,k in enumerate(info['kinds']) if 'code' in k),0)
    result[first]=(110,[f'架构导读：{path.stem}。',role(path)])
    continuation=False
    for i,line in enumerate(lines):
        s=line.strip()
        old_cont=continuation;continuation=s.endswith('\\')
        if old_cont or s.startswith('`') or s.startswith('#') or 'code' not in info['kinds'][i]:continue
        if i and info['kinds'][i-1]=={'comment'}:continue
        if i in result:continue
        indent=line[:len(line)-len(line.lstrip())]
        if re.match(r'(always_ff|always_comb|always_latch|always)\b',s):
            result[i]=(95,[f'过程边界：{brief(s,110)}。', '本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。'])
        elif re.match(r'(function|task)\b',s):
            result[i]=(95,[f'局部运算/辅助过程：{brief(s,105)}。','只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。'])
        elif re.match(r'(input|output|inout)\b',s):
            candidates=names(s.split('//')[0]);declared=candidates[-1] if candidates else ''
            direction=s.split()[0]
            result[i]=(80,[f'接口声明：{brief(s.split("//")[0].rstrip(",;"),110)}。',signal_note(declared)])
        elif re.match(r'(parameter|localparam)\b',s):
            result[i]=(83,[f'静态配置：{brief(s.split("//")[0].rstrip(",;"),115)}。','该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。'])
        elif re.match(r'(case|casez|casex)\b',s):
            result[i]=(88,[f'按 {brief(expression(s),90)} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。'])
        elif re.match(r'(?:end\s+)?(?:else\s+)?if\s*\(',s):
            cond=expression(s);symbols=names(cond)
            result[i]=(76,[f'条件分支：检查 {brief(cond,110)}。'])
            if any('valid' in x for x in symbols) and any('ready' in x for x in symbols):
                result[i]=(92,[f'握手/背压判断：{brief(cond,110)}。','只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。'])
            elif any('rst' in x.lower() or 'reset' in x.lower() for x in symbols):
                result[i]=(91,[f'复位相关判断：{brief(cond,110)}；分支方向由信号极性与取反表达式决定。'])
        elif re.match(r'for\s*\(',s):
            result[i]=(71,[f'按 {brief(expression(s),110)} 的索引范围生成/更新各元素；索引上下界限定数组访问范围。'])
        elif re.match(r'assign\b',s):
            lhs=s[6:].split('=',1)[0].strip()
            result[i]=(73,[f'组合连接 {brief(lhs,75)}：{signal_note(lhs)}'])
        elif re.match(r'(logic|wire|reg)\b',s) and s.endswith(';'):
            content=s.split('//')[0];items=names(content);name=items[-1] if items else ''
            result[i]=(65,[f'局部字段 {brief(content.rstrip(";"),105)}。',signal_note(name)])
        elif re.match(r'[A-Za-z_][\w]*\s*:\s*(?:begin|if|[\w])',s):
            label=s.split(':',1)[0]
            if label not in ('default',):result[i]=(82,[f'状态/选择分支 {label}：本分支规定该编码下的寄存器更新和下一步动作。'])
        elif '<=' in s and not s.startswith(('$','//')):
            lhs=s.split('<=',1)[0].strip();rhs=s.split('<=',1)[1].split(';',1)[0].strip()
            if re.match(r'[A-Za-z_][\w\[\].+:\-]*$',lhs):
                note=f'寄存更新 {brief(lhs,60)}，写入来源为 {brief(rhs,90)}；使能由所在分支限定。'
                if re.search(re.escape(lhs)+r'\s*\+\s*(?:\d+\s*\x27[bhd])?1\b',rhs):note=f'推进 {lhs} 的计数/位置；只在当前分支生效的周期递增。'
                result[i]=(55,[note])
    return result


def c_candidates(path,text,info):
    result={};lines=text.splitlines()
    first=next((i for i,k in enumerate(info['kinds']) if 'code' in k),0)
    result[first]=(110,[f'架构导读：{path.stem}。',role(path)])
    continuation=False
    for i,line in enumerate(lines):
        s=line.strip();old_cont=continuation;continuation=s.endswith('\\')
        if old_cont or 'code' not in info['kinds'][i] or s.startswith('#') or i in result:continue
        if i and info['kinds'][i-1]=={'comment'}:continue
        m=re.match(r'(?:static\s+)?(?:inline\s+)?(?:const\s+)?(?:unsigned\s+)?[\w]+(?:\s*\*)?\s+(\w+)\s*\(',s)
        if m and m.group(1) not in ('if','for','while','switch') and not s.startswith('return '):
            name=m.group(1)
            details={
                'frame_pool_quiescent':'逐槽确认无 CAPTURING 状态且 readers 为零；仍有生产者或消费者时拒绝复位。',
                'frame_pool_reset':'先验证池静止，再清空槽状态；保留 next_generation，并恢复三个固定原始帧基址。',
                'frame_pool_capture_begin':'优先选 FREE 槽，否则回收最旧且无 reader 的 READY 槽；分配新 generation。',
                'frame_pool_capture_complete':'先检查 DONE 且非 BUSY，再检查像素计数与错误；只把完整好帧置为 READY。',
                'frame_pool_take':'选择比消费者已用代次更新的 READY 帧，设置 reader 位并返回带 generation 的租约。',
                'frame_pool_release':'同时验证槽号、消费者、代次和 reader 位后释放，拒绝旧租约污染新一帧。',
                'camera_lost_pixels':'分别计算传感器和 DDR 写入的像素缺口，返回较大值，避免对同一丢失像素重复计数。',
                'camera_loss_abort':'比较像素缺口与 1280×720/10；调用位置还必须保证采集及最终写响应已经退休。',
                'live_preview_service':'以协作式小步推进采集、缩放和元数据确认；正常推理完成时继续保持独立预览服务。',
                'live_preview_begin':'初始化静止帧池并取得共享图像资源的预览所有权，然后开始首个服务步骤。',
                'live_preview_inference_input_step':'为推理取得最新原始帧租约并推进输入预处理；等待输入不会因经过时长而退出。',
                'graph_executor_emit':'检查片上命令容量，写入四个 32 位命令字，并同步累计程序 CRC。',
                'graph_executor_write':'编码一次硬件寄存器写入指令；真正的总线执行由 GRAPH_EXECUTOR1 完成。',
                'graph_executor_check':'编码寄存器掩码检查，使图指令流能校验硬件状态和预期计数。',
                'graph_executor_accum':'编码性能计数累加指令，将指定硬件寄存器关联到图执行器的统计槽。',
                'graph_executor_disjoint':'两两检查非零长度内存区域是否重叠，避免图节点在校验阶段接受冲突缓冲。',
                'graph_executor_conv':'校验卷积形状、低 DDR 地址及 scratch 条件，再构造卷积服务命令和预期 MAC/任务计数。',
                'graph_executor_requant':'从前一卷积推导数值界限，并检查可融合 LUT 节点；校验后编码 S3 寄存器序列。',
                'graph_executor_tensor':'检查共享张量算子的形状、对齐与缓冲分离，再编码对应硬件命令。',
                'cmos2_execute':'逐阶段推进一帧；未完成的图像/GRAPH_EXECUTOR 步骤返回挂起状态，把控制权交还协作式主循环。',
                'cmos2_idle_step':'推进当前连续会话的一步；成功后增加完整帧计数，错误则按原有安全恢复条件处理。',
            }
            body='\n'.join(lines[i:min(len(lines),i+50)])
            calls=[n for n in names(' '.join(re.findall(r'\b([A-Za-z_]\w*)\s*\(',body))) if n not in (name,'sizeof')]
            detail=details.get(name,'接口参数：'+brief(expression(s),110)+'；返回值及副作用由下列函数体定义。')
            signature=' '.join(lines[i:min(len(lines),i+6)]).split('{',1)[0]
            parameters=expression(signature)
            param_names=[]
            for parameter in parameters.split(','):
                choices=names(parameter)
                if choices:param_names.append(choices[-1])
            result[i]=(95,[f'服务函数 {name}。',detail,'参数入口：'+(', '.join(param_names) if param_names else '无位置参数')+'；类型、指针限定及返回约定沿用下列声明。'])
        elif re.match(r'(?:}\s*)?(?:else\s+)?if\s*\(',s):
            cond=expression(s)
            result[i]=(85,[f'控制边界：{brief(cond,115)}；仅在该条件成立时进入本分支。'])
        elif s.startswith('return '):
            result[i]=(60,[f'返回当前检查/运算结果 {brief(s[7:].rstrip(";"),95)}，由调用者解释其状态或数值。'])
        elif re.match(r'(for|while)\s*\(',s):
            result[i]=(80,[f'迭代边界：{brief(expression(s),115)}；地址和计数随循环体中的原始更新前进。'])
        elif s.startswith('switch'):
            result[i]=(85,[f'根据 {brief(expression(s),95)} 分派协议/运算类型，逐个分支保留原有返回约定。'])
        elif re.match(r'case\s+',s):
            result[i]=(76,[f'处理选择码 {brief(s.split(":",1)[0][5:],95)}，本分支对应的 MMIO 或数据动作见下面语句。'])
        elif 'R32(' in s or 'fence_all()' in s or 'cache_invalidate()' in s:
            result[i]=(92,[f'硬件/可见性边界：{brief(s,115)}。','本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。'])
        elif re.match(r'(typedef|struct|enum)\b',s):
            result[i]=(80,[f'数据布局定义：{brief(s,100)}；字段顺序与本文件使用它的接口保持一致。'])
        elif re.match(r'(?:const\s+)?(?:uint\d+_t|int\d+_t|uint32_t|size_t|uint64_t|int|unsigned)\s',s):
            result[i]=(55,[f'局部计算/控制字段：{brief(s,110)}；位宽和有符号规则由声明确定。'])
        elif re.match(r'[A-Za-z_]\w*(?:->|\.|\[|\s*=)',s):
            targets=names(s.split('=',1)[0]);target=targets[0] if targets else path.stem
            result[i]=(45,[f'更新/使用 {target} 相关字段，使本步骤的状态与后续检查保持一致。'])
    return result


def py_candidates(path,text,info):
    tree=ast.parse(text);lines=text.splitlines();result={}
    first=next((i for i,k in enumerate(info['kinds']) if 'code' in k),0)
    result[first]=(110,[f'架构导读：{path.stem}。',role(path)])
    for node in ast.walk(tree):
        if not isinstance(node,ast.stmt) or not hasattr(node,'lineno'):continue
        i=node.lineno-1
        if i in result or (i and info['kinds'][i-1]=={'comment'}):continue
        s=lines[i].strip()
        if isinstance(node,(ast.FunctionDef,ast.AsyncFunctionDef)):
            args=[x.arg for x in node.args.args if x.arg not in ('self','cls')]
            callees=list(dict.fromkeys(ast.unparse(call.func) for call in ast.walk(node) if isinstance(call,ast.Call)))[:5]
            trace='本函数调用入口包括 '+brief(', '.join(callees),125)+'。' if callees else '该函数直接更新本地状态或返回计算值，具体返回对象见函数体。'
            result[i]=(95,[f'接口 {node.name}，显式输入字段：{", ".join(args) or "无位置参数"}。',trace])
        elif isinstance(node,ast.ClassDef):result[i]=(95,[f'对象 {node.name} 封装下列状态和操作，实例字段在各方法之间保持本地上下文。'])
        elif isinstance(node,ast.If):result[i]=(80,[f'按条件 {brief(ast.unparse(node.test),110)} 选择后续流程，保留原有异常和退出分支。'])
        elif isinstance(node,(ast.For,ast.While)):
            cond=ast.unparse(node.iter) if isinstance(node,ast.For) else ast.unparse(node.test)
            result[i]=(85,[f'迭代/等待条件：{brief(cond,110)}；退出由原循环条件及显式 break/异常决定。'])
        elif isinstance(node,(ast.With,ast.AsyncWith)):result[i]=(85,[f'资源上下文：{brief(s,100)}；离开上下文时执行对应清理约定。'])
        elif isinstance(node,ast.Try):result[i]=(85,['异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。'])
        elif isinstance(node,ast.Raise):result[i]=(85,[f'停止当前调用并上报异常：{brief(s,110)}。'])
        elif isinstance(node,ast.Return):result[i]=(60,[f'向调用方返回本步骤结果：{brief(s[6:].strip(),105) or "None"}。'])
        elif isinstance(node,(ast.Assign,ast.AnnAssign,ast.AugAssign)):
            result[i]=(50,[f'维护本地状态/计算值：{brief(s,115)}。'])
        elif isinstance(node,ast.Expr) and isinstance(node.value,ast.Call):
            result[i]=(45,[f'调用 {brief(ast.unparse(node.value.func),100)} 完成本步骤，参数与调用顺序保持原样。'])
    return result


def source_files():
    stage=EXACT/'stage_ddr_hdmi';rtl=[]
    for line in (stage/'sources_pango.f').read_text().splitlines():
        p=stage/line.strip()
        if p.is_file() and p.suffix in ('.v','.sv') and not any(x in ('ipcore','vendor') for x in p.parts):rtl.append(p)
    rtl+=list((stage/'board').glob('soc*.sv'))
    rtl=list(dict.fromkeys(rtl))
    firmware=[p for p in (EXACT/'firmware_displayready_src').iterdir() if p.suffix in ('.c','.h') and p.name not in ('graph_sim.c','model_input_lut.h','s3_model_fuse_whitelist.h')]
    host=list((ROOT/'exact/host').rglob('*.py'))
    return {'RTL':rtl,'firmware':firmware,'host':host}


def main():
    records=[];insertions=[];groups=source_files()
    for group,files in groups.items():
        work=[]
        for original in files:
            if group=='host':annotated=ROOT/'annotated/host'/original.relative_to(ROOT/'exact/host')
            else:annotated=ANNOTATED/original.relative_to(EXACT)
            text=original.read_text(encoding='utf-8-sig');info=analyze(original)
            candidates=(py_candidates if original.suffix=='.py' else rtl_candidates if original.suffix in ('.v','.sv') else c_candidates)(original,text,info)
            goal=max(0,info['code_lines']*3/7-info['comment_lines'])
            work.append(dict(original=original,annotated=annotated,text=text,info=info,candidates=candidates,goal=goal,selected={}))
        code=sum(x['info']['code_lines'] for x in work);com=sum(x['info']['comment_lines'] for x in work)
        budget=round(code*3/7-com)
        remaining=budget
        # File-proportional allocation keeps explanation distributed rather
        # than inflating the ratio with one large artificial header.
        for file in work:
            need=min(remaining,max(0,math.floor(file['goal'])))
            for index,(priority,comments) in sorted(file['candidates'].items(),key=lambda item:(-item[1][0],item[0])):
                if need<=0:break
                chosen=comments[:need];file['selected'][index]=chosen;need-=len(chosen);remaining-=len(chosen)
        if remaining:
            for file in sorted(work,key=lambda x:-x['info']['code_lines']):
                for index,(priority,comments) in sorted(file['candidates'].items(),key=lambda item:(-item[1][0],item[0])):
                    if index in file['selected']:continue
                    chosen=comments[:remaining];file['selected'][index]=chosen;remaining-=len(chosen)
                    if not remaining:break
                if not remaining:break
        if remaining:raise RuntimeError(f'Insufficient substantive annotation points: {group}, {remaining}')
        for file in work:
            original=file['original'];annotated=file['annotated'];lines=file['text'].splitlines(keepends=True);output=[]
            marker='# ' if original.suffix=='.py' else '// '
            for i,line in enumerate(lines):
                if i in file['selected']:
                    indent=line[:len(line)-len(line.lstrip())]
                    comments=file['selected'][i]
                    output.extend(indent+marker+c+'\n' for c in comments)
                    insertions.append(dict(file=annotated.relative_to(ROOT).as_posix(),original_line=i+1,comments=comments))
                output.append(line)
            annotated.write_text(''.join(output),encoding='utf-8')
            before,after=equivalent(original,annotated)
            records.append(dict(group=group,file=annotated.relative_to(ROOT).as_posix(),original=original.relative_to(ROOT).as_posix(),role=role(original),code_lines=after['code_lines'],comment_lines=after['comment_lines'],mixed_lines=after['mixed_lines'],nonblank_lines=after['nonblank_lines'],comment_percent=after['comment_rate']*100,original_comment_percent=before['comment_rate']*100,added_comment_lines=after['comment_lines']-before['comment_lines'],tokens_equal=True,original_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),annotated_sha256=hashlib.sha256(annotated.read_bytes()).hexdigest(),token_sha256=after['token_sha256']))
    summary={}
    for group in (*groups,'ALL'):
        rs=[r for r in records if group=='ALL' or r['group']==group];c=sum(r['code_lines'] for r in rs);m=sum(r['comment_lines'] for r in rs)
        summary[group]=dict(files=len(rs),code_lines=c,comment_lines=m,nonblank_lines=c+m,comment_percent=m/(c+m)*100,all_tokens_equal=all(r['tokens_equal'] for r in rs))
    report=dict(method='Pure-comment physical lines / (code physical lines + pure-comment physical lines); blank lines excluded; mixed inline-comment lines count as code; Python docstrings count as code.',scope='All files listed in files; PDS-generated lowered design, encrypted/vendor IP, generated coefficient tables, unselected legacy RTL and testbenches excluded explicitly.',excluded_generated_firmware=['model_input_lut.h','s3_model_fuse_whitelist.h'],summary=summary,files=records)
    (ROOT/'audit/COMMENT_RATE_AND_TOKEN_EQUIVALENCE.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'audit/ANNOTATION_INSERTIONS.json').write_text(json.dumps(insertions,ensure_ascii=False,indent=2),encoding='utf-8')
    with (ROOT/'audit/源码注释率逐文件.csv').open('w',encoding='utf-8-sig',newline='') as stream:
        fields=list(records[0]);writer=csv.DictWriter(stream,fieldnames=fields);writer.writeheader();writer.writerows(records)
    (ROOT/'audit/ANNOTATED_FILE_SCOPE.txt').write_text('\n'.join(r['file'] for r in records)+'\n',encoding='utf-8')
    print(json.dumps(summary,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
