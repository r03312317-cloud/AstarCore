"""Attach architecture/API notes at declarations and reviewed control anchors."""
from pathlib import Path
import json,re,zipfile
from annotation_catalog import CONTRACTS,SW,HEADERS
from audit_comments import decode,is_comment
from pygments import lex
from pygments.lexers import SystemVerilogLexer
from pygments.token import Token
from control_notes import EXTRA_FUNCTIONS,CONTROL,C_FUNCTIONS,SOFTWARE_CONTROL
from register_notes import MACROS,PROTOTYPES,PPU_FIELDS
ROOT=Path(__file__).resolve().parents[1]

PARAM={
'RESET_VECTOR':'独立默认入口可由包装层覆写；游戏入口实际为 0x10000000。',
'ENABLE_PAIRING':'控制双通路准入能力；第二条仍需要通过资源、依赖和异常条件。',
'MEMORY_CREDITS':'限制在途/预留访存容量，不能与 ROB 或取指队列空位混用。',
'FETCH_CREDITS':'限制未返回取指请求；当前游戏覆写为 2。',
'ENABLE_COMMITTED_RAS':'决定是否利用已退休调用/返回信息维护预测栈。',
'RAS_DEPTH':'限定返回地址预测栈容量，游戏配置为 16。',
'HISTORY_BITS':'限定预测历史宽度，实例配置为 12；上下文需随指令保存。',
'BIMODAL_INDEX_BITS':'决定局部分量/选择器的索引宽度，游戏覆写为 9。',
'GSHARE_INDEX_BITS':'决定 GShare 表容量，游戏覆写为 12。',
'LOCAL_HISTORY_BITS':'决定每个局部历史记录的长度，本构建使用 H5。',
'LOCAL_INDEX_BITS':'决定局部方向表行数，当前 B9 集成推导为 I8。',
'ENABLE_LOCAL_DIRECTION':'在局部方向缓存与独立双位计数分量之间选择实现。',
'ENABLE_TRACE':'仅决定部分观测载荷是否保留，不能当成实际发射/退休使能。',
'FAST_WAKEUP':'允许使用有效完成广播尽早解析依赖，不改变生产者身份匹配。',
'ENABLE_SAME_CYCLE_REUSE':'控制当拍释放槽的复用策略；当前集成关闭这一选项。',
'CARRIED_COMPLETION_WRITES':'让完成事实携带写回资格，避免在晚端重新拼接身份。',
'DECOUPLED_ALLOCATION_PAYLOAD':'分离宽载荷提案与最终接纳，恢复仍控制真正所有权。',
'BANKED_ISSUE':'选择局部发射银行结构，与借用和复用选项共同决定调度路径。',
'ENABLE_MDU_TURNOVER':'允许后端交接时利用可用容量，交接必须区分旧响应与新请求。',
'ENABLE_MDU_SPILL':'保留乘除结果临时容纳路径，输出背压不能丢失旧所有者。',
'ENABLE_MUL_STREAM':'启用独立低位乘法请求/响应流，与传统乘除路径区分归属。',
'ENABLE_STEALING':'允许满足条件的整数候选利用其他可用通路。',
'ENABLE_ORDERED_STORE_PREP':'允许提前准备 store 载荷，但外部副作用仍受顺序约束。',
'ENABLE_STORE_HEAD_LOOKAHEAD':'使用可证明的头部后继条件准备 store；不可跨越未解决异常。',
'ENABLE_STORE_ISSUE_LOOKAHEAD':'控制 store 的前看选择，不取消旧 store 的顺序过滤。',
'LOAD_ORDER_ISSUE_LOOKAHEAD':'允许访存顺序预判参与准入，仍保留请求和响应所有权。',
'LOAD_BYPASS':'允许年轻 load 越过尚未进入 LSU 的旧 load，旧 store 继续约束顺序。',
'ENABLE_REDIRECT_FETCH':'允许恢复地址参与取指请求形成；旧路径返回仍需取消资格。',
'ENABLE_CURRENT_INTEGER_PAIR':'让当前整数指令参与双通路选择，不免除依赖和异常检查。',
'DISPATCH_BYPASS_UNMAPPED_ONLY':'限制分配绕过候选，避免未就绪的重命名依赖被误当成立即数值。',
'ENABLE_CONTROL_DISPATCH':'允许控制类指令走分配侧提案，最终恢复语义仍由核心完成。',
'ENABLE_DISPATCH_BYPASS':'允许已就绪新指令进入空闲 EX，不能同时覆盖队列发射。',
'ENABLE_EX_OPERAND_STREAM':'自由的 EX 载荷可以连续采样，但有效身份仍由准入位控制。',
'ENABLE_LOCAL_MUL_OPERANDS':'在既有 EX 边界保存乘法私有操作数，阻塞时与所有者一起保持。',
'ENABLE_PREDECODED_ALU':'让运算控制随队列/EX 保存，避免晚端重复译码。',
'ALU_DUAL_BARREL':'选择移位硬件组织，不额外证明任何软件扩展的完整兼容性。',
'ENABLE_EARLY_JALR_CHECK':'提前形成与本条操作数一致的 JALR 对齐事实。',
'ENABLE_QUEUED_EXEC_PAYLOAD':'PC/指令随队列拥有者保存，不在晚选择后重读 ROB 元数据。',
'ENABLE_EX_METADATA_STREAM':'控制私有执行元数据的连续采样，当前默认关闭。',
'ENABLE_MUL_INTEGER_BOUNDARY':'限定低位乘法依赖跨既有操作数边界的路径组织。',
'ACTIVE_QUEUE_MASK':'0x733 仅启用 7 个队列编号，最大逻辑编号不等于有效容量。',
'I_INDEX_BITS':'指令缓存每路组数为 2 的该次方，行大小固定为 64 字节。',
'I_WAYS':'指令缓存路数；当前 2 路需同时解释独立 tag/valid 与组内替换位。',
'D_INDEX_BITS':'数据缓存每路组数由该位宽决定，不能直接把它当作字节容量。',
'D_WAYS':'数据缓存路数；脏状态与替换状态需要按每路/每组分别维护。',
'ENABLE_FAST_ICROSS':'并行准备跨行标签查询；数据银行仍然是同步读。',
'ENABLE_DATA_RAM_GUARD':'供体可选单段范围守护，游戏关闭后由后端适配器检查边界。',
'DATA_RAM_BASE':'范围守护的下边界，仅在对应选项生效时参与合法性检查。',
'DATA_RAM_LIMIT':'范围守护包含式上界，不应直接作为实际 DDR 容量声明。',
'ITCM_INIT_FILE':'PDS 必须绑定匹配的 64 位代码 SRAM 初始化镜像。',
'DTCM_INIT_FILE':'数据 SRAM 初始化与代码镜像成对交付，不能混用另一固件。',
'CPU_CLOCK_HZ':'软件分频参数需与实际 100 MHz 时钟一致，不是更改 PLL 的开关。',
'DDR_BASE':'后端 DDR 窗口基地址，先检查范围再转换为控制器地址。',
'DDR_BYTES':'后端可访问范围的长度，需与实际 DDR 实现和地址检查一致。',
'CACHE_BASE':'通用包装层的保留映射参数，不重写 RV32 内部固定的缓存分类。',
'CACHE_BYTES':'通用缓存窗口参数，RV32 的实际外设分类仍按其实现判断。',
'FB0_BASE':'第一块显示缓冲基址，应与软件常量和有效视频窗口一致。',
'FB1_BASE':'第二块显示缓冲基址，双缓冲地址不同才能安全轮换所有权。',
'TICK_DIV':'硬件时钟分频值决定毫秒事件基准，实际 CPU 时钟变化需同步检查。',
'DEBOUNCE_MS':'连续稳定达到门槛才改变按键状态，单位是内部毫秒 tick。',
'REPEAT_DELAY_MS':'按住达到该延迟后才产生自动重复事件。',
'REPEAT_PERIOD_MS':'重复事件的间隔不同于按键去抖时间。',
'EXTERNAL_PAD_ENABLE':'默认关闭外部相机排针按键，避免数据引脚产生虚假输入。',
'LED_PANEL_DIAG':'选择平台诊断状态显示，不直接表示游戏逻辑是否完成。'
}

FIELDS={
'valid':'标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。',
'ready':'标记操作数或下游接纳条件已满足；还需检查相应有效身份。',
'tag':'保存本接口的所有者/事务编号；匹配时仍需检查有效资格，不能混用其他接口的 tag。',
'sequence':'保存绝对年龄序号，防止复用同一槽位时混淆新旧指令。',
'pc':'保存拥有者的原始 PC，用于恢复、异常或对应包的诊断。',
'instruction':'保存与同一 PC/所有权配对的指令字，不能从当前前端重新补填。',
'left':'左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。',
'right':'右操作数与来源 tag/就绪位配套，广播匹配后才可消费。',
'address':'保持当前事务地址，等待/背压期间不能换成下一请求的地址。',
'addr':'地址与当前请求/响应归属配对，不能独立于有效条件使用。',
'value':'保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。',
'data':'载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。',
'wdata':'写载荷需与地址和字节选通一起保持，背压不能提前覆盖。',
'rdata':'读返回值只有在对应响应有效时可消费，并需检查错误归属。',
'writes':'保留寄存器写资格；计算出数值不意味着可以修改架构寄存器。',
'destination':'目的寄存器身份随指令保持，x0 写入仍须被抑制。',
'store':'区分有外部写副作用的操作，顺序约束不能只依据 load 的规则。',
'memory':'访存类别事实只描述指令，真正请求还受信用、顺序和异常条件约束。',
'serial':'串行操作需要精确提交边界，不能与普通整数候选等同调度。',
'fault':'错误事实应记录到所属指令/事务，再在允许的精确边界处理。',
'error':'错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。',
'killed':'标记错误路径的结果资格已取消，不代表外部在途事务已消失。',
'irrevocable':'记录外部副作用已不可撤销，恢复时仍需等待并隔离其响应。',
'count':'统计已接受的有效占用/事件；同时增减时要保留净变化。',
'head':'指向当前最老有效项，消费顺序与环形编号回绕需要一起解释。',
'tail':'指向后续接纳位置，只有实际分配/入队才推进所有权。',
'state':'协议阶段寄存器决定当前允许的请求、等待与完成行为。',
'prediction':'保存预测时的下一 PC/方向事实，真实执行结果稍后独立产生。',
'history':'保留预测相关历史，不能在退休时改用后来更新的历史。',
'context':'跟随预测或指令的上下文，使后续训练/恢复使用原来的索引事实。',
'lru':'组内替换方向状态，在命中/安装路径更新；不表示数据有效或脏。',
'dirty':'标记缓存内容需要写回；替换不能只清除有效位而丢掉脏数据。',
'strobes':'每一位决定对应字节是否更新，不能把部分写放大成整拍全写。',
'wstrb':'字节选通与写数据同属一次事务，宽度转换要保留字节位置。',
'unsigned':'保留无符号解释方式，影响加载扩展或乘除结果选择。',
'size':'访问粒度与对齐/字节选通一起决定有效数据范围。',
'owner':'选择真正拥有当前有效结果的银行/事务，不能依赖 RAM 最后看到的值。',
'cause':'异常原因属于产生错误的指令，处理时与其 PC/tval 一起提交。',
'tval':'保存异常相关值，只有相应错误项进入处理边界时才可见。',
'initialized':'初始化完成门控，防止把尚未设置的 RAM 内容当作有效状态。',
'initializing':'初始化扫描尚在进行，普通查询/接纳资格需按本模块门控。',
}

FAMILIES=[
('prepared_second_','LSU 第二准备槽：'),('prepared_','LSU 准备槽：'),
('lsu_','LSU 在途事务：'),('ex_','EX 包：'),('rob_','ROB 项：'),
('q_','发射队列项：'),('fetch_','取指提案：'),('allocation_','分配提案：'),
('dispatch_','分配绕过：'),('retirement_','退休下一 PC 路径：'),
('training_','预测训练路径：'),('recovery_','恢复路径：'),
('complete_','完成路径：'),('candidate_','访存候选：'),
('mul_','独立低位乘法流：'),('mdu_','乘除后端：'),
('legacy_','传统后端兼容路径：'),('request_','请求所有权：'),
('response_','响应所有权：'),('queue_','有序队列：'),
('pending_','尚未完成的事务：'),('current_','当前保持的上下文：'),
('saved_','已保存的上下文：'),('held_','背压保持的包：'),
('predictor_','预测器状态：'),('train_','提交训练：'),
('read_','读路径：'),('write_','写路径：'),
]

AXI={
'awvalid':'写地址通道载荷有效，未获 AWREADY 前不能替换其地址/突发属性。',
'awready':'下游接受写地址的条件，与 AWVALID 同时成立才产生地址握手。',
'awaddr':'本次写突发的起始字节地址，跟随写地址通道握手。',
'awlen':'AXI 突发长度编码，与最后一个写数据 beat 的边界一致。',
'awsize':'每个 beat 的大小编码，需与数据宽度和地址对齐一致。',
'awburst':'突发地址推进方式，宽度适配必须保留其语义。',
'awid':'写地址事务身份，后续 B 响应必须回到同一主机/事务。',
'wvalid':'当前写数据 beat 有效，背压期间保持数据、选通和最后一拍标记。',
'wready':'写数据接纳条件，不能用地址通道已握手代替。',
'wdata':'当前写 beat 载荷，只有 WVALID/WREADY 握手才算下游已接收。',
'wstrb':'写 beat 的逐字节有效位，不能随意扩展为全字节写。',
'wlast':'当前 beat 是本次写突发的最后一拍，但事务仍需等待 B 响应。',
'bvalid':'写响应有效，消费后才可释放对应写事务所有权。',
'bready':'主机接收写响应的条件，与 BVALID 同拍才完成响应消费。',
'bresp':'写响应状态，错误必须返回给对应发起者。',
'bid':'写完成的事务 ID，与先前 AW 记录的归属匹配。',
'arvalid':'读地址有效，未获 ARREADY 前保持地址和突发属性。',
'arready':'读地址接纳条件，与 ARVALID 共同形成一次读命令。',
'araddr':'读突发起始字节地址，响应阶段继续使用已保存的归属。',
'arlen':'请求的读 beat 数编码，接收方用它核对边界和 RLAST。',
'arsize':'读 beat 大小编码，需与总线宽度和地址对齐一致。',
'arburst':'读突发的地址递增/固定方式，不能仅改变数据宽度而丢失。',
'arid':'读事务身份，R 通道需要依据它保持主机/事务归属。',
'rvalid':'当前返回 beat 有效，没有该资格不能消费总线上旧数据。',
'rready':'接收方允许消费当前返回 beat，背压时保持未消费响应。',
'rdata':'当前读返回载荷，与 RVALID、ID、错误和最后一拍共同解释。',
'rresp':'读 beat 响应状态，错误需累计到对应行/突发。',
'rlast':'当前为本突发最后一个返回 beat，必须与保存的长度一致。',
'rid':'返回数据的事务 ID，用于检查和路由先前接纳的读请求。',
}

def first_name(line):
 line=re.sub(r'\(\*.*?\*\)','',line)
 line=re.sub(r'/\*.*?\*/','',line)
 line=re.sub(r'\[[^\]]*\]','',line)
 line=re.sub(r'^\s*(input|output|inout|wire|reg|logic|parameter|localparam)\s+','',line)
 line=re.sub(r'^(?:reg|wire|logic|integer|int|bit|signed|unsigned|real)\s+','',line)
 m=re.match(r'\s*([A-Za-z_]\w*)',line)
 return m[1] if m else None

def field_note(name):
 name=re.sub(r'\d+$','',name.lower())
 for key in sorted(FIELDS,key=len,reverse=True):
  if re.search(r'(?:^|_)'+key+r'(?:_|$)',name):return FIELDS[key]
 return None

def declaration_note(name,filename,line):
 lower=name.lower();base=re.sub(r'\d+$','',lower)
 if name in PARAM:return name+'：'+PARAM[name]
 if lower in ('clk','clock','cpu_clk','mem_clk','pix_clk','rd_clk','wr_clk','rclk','wclk','pixel_clk'):
  return name+'：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。'
 if re.fullmatch(r'(?:a?rst|reset)(?:_n)?',lower):
  return name+'：复位控制不同于 PLL/DDR 就绪；具体极性与同步方式按本模块时序块执行。'
 if lower in ('left_ready','right_ready'):
  return name+'：源操作数已经准备好的资格位，仍需 occupied、issue_allowed 与另一源一起决定候选可发射性。'
 if filename=='rv32_issue_bank.v' and lower in ('ready_left','ready_right'):
  return name+'：组合选择的操作数载荷，优先接入匹配的有效完成广播；本数组不保存时序状态。'
 if lower.startswith('debug_'):
  phase='调试观测'
  for key,label in [('alloc','分配'),('issue','发射'),('complete','完成'),('retire','退休'),('recovery','恢复'),('lsu','访存'),('mdu','乘除'),('mul','乘法')]:
   if key in lower:phase=label+'观测';break
  note=field_note(lower)
  if note:return name+'（'+phase+'）：'+note
  return name+'（'+phase+'）：只用于外部观察，不把观测提案当作软件可见的提交事件。'
 # AXI channel semantics apply only to explicitly named AXI wires.
 # Generic custom req/rsp wdata/rdata are not AXI channels.
 if 'axi_' in lower or (filename in ('soc_axi_2m_arbiter.sv','soc_hmic_axi_adapter.sv','soc_hdmi_axi_reader.sv','soc_hdmi_ddr_scanout.sv','pg_ddr_burst_bridge.sv','game_soc_top.sv','game_board_top.sv') and re.match(r'^(?:[ms]\d*|h|brg|ax)_',lower)):
  for key,note in AXI.items():
   if re.search(r'(?:^|_)'+key+r'\d*$',lower):return name+'：'+note
 if lower.startswith('hybrid_'):
  return name+'：混合预测器输出的方向/早期候选，需与对应 PC 和预测上下文一起接纳。'
 if filename=='rv32_memory_system.v':
  way='第二路' if 'second' in lower else '第一路'
  if lower.startswith('instruction_'):
   if 'even' in lower or 'odd' in lower:return name+'：'+way+'指令数据字银行，与该路 tag/valid 的同步查询结果对齐。'
   if 'tag' in lower:return name+'：'+way+'缓存标签，只有有效位同时成立才能用于命中判断。'
   if 'valid' in lower:return name+'：'+way+'指令行的有效资格，复位/维护后不能用旧 RAM 数据绕过它。'
  if lower.startswith('data_segments'):
   return name+'：'+way+'数据行的独立字节银行，逐字节写使能避免部分写破坏相邻字节。'
  if lower.startswith(('i_','d_','instruction_','data_')):
   note=field_note(lower)
   if note:return name+'（缓存路径）：'+note
 if lower.startswith('csr_'):
  return name+'：CSR 访问/状态字段；读值、写资格和异常事实分别检查，架构更新受精确提交边界约束。'
 if lower in ('cycle_counter','instruction_counter'):
  return name+'：64 位真实机器统计，低位回绕由分段进位保持连续。'
 if lower.startswith(('map_valid','map_tag')):
  return name+'：架构寄存器到最新未退休生产者的映射；旧指令退休不能清掉后来建立的新映射。'
 if lower.startswith('register_'):
  return name+'：已退休寄存器状态；银行选择/有效位共同屏蔽未初始化 RAM，并保持 x0 为零。'
 for prefix,context in FAMILIES:
  if lower.startswith(prefix):
   note=field_note(lower[len(prefix):])
   if note:return name+'（'+context[:-1]+'）：'+note
 if re.search(r'(?:^|_)(req|request)(?:_|$)',lower):
  return name+'：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。'
 if re.search(r'(?:^|_)(gnt|grant|ready)(?:_|$)',lower):
  return name+'：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。'
 if re.search(r'(?:^|_)(valid|rvalid)(?:_|$)',lower):
  return name+'：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。'
 if re.search(r'(?:^|_)(rst|reset)(?:_|$)',lower):
  return name+'：参与本域复位/就绪控制，释放条件与跨域同步链一起检查。'
 if lower.startswith(('unused_','unused')):
  return name+'：保留接口的未消费连接，不能据其静态值推导实际功能活动。'
 note=field_note(lower)
 if note:return name+'：'+note
 if re.search(r'(?:^|_)(enable|accept|push|pop|fire)(?:_|$)',lower):
  return name+'：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。'
 if re.search(r'(?:^|_)(beat|index|offset|pointer|ptr)(?:_|$)',lower):
  return name+'：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。'
 return None

FUNCTIONS={
'read_csr':'按 CSR 编号选出当前值；不在读函数里提前执行写入或异常提交。',
'csr_exists':'CSR 访问合法性与读值分开判断；读到零不能证明地址非法。',
'read_register':'从最近退休的银行取架构值，无效位和 x0 强制返回零。',
'read_result':'根据结果 owner 选择银行；读取前需由调用路径确认对应 ROB 完成。',
'read_rob_pc':'ROB 头锚定架构 PC，非头项可从前驱不可变预测重建 PC。',
'read_rob_instruction':'奇偶存储只决定物理银行，tag 的有效所有权由外层维护。',
'read_rob_prediction':'读取预测时保存的目标，不用当前执行结果覆盖历史预测事实。',
'read_rob_next':'控制流使用已经完成的真实目标，普通指令取原 PC 加 4。',
'read_rob_tval':'异常相关值从对应完成银行读取，与该项的 cause/PC 保持一致。',
'read_prediction_context':'按奇偶 tag 读出原预测上下文，供退休训练使用。',
'read_recovery_context':'恢复历史属于当时被接纳的指令，不能用训练后的最新历史替代。',
'pack_queue_alu_control':'把 one-hot 家族编码压缩为队列存储格式，保留修饰字段。',
'unpack_queue_alu_control':'进入执行边界前还原原控制格式，零/非法家族保持原处理方式。',
'peripheral_address':'固定地址分类决定非缓存副作用路径；游戏帧缓冲属于该范围。',
'ordinary_integer_class':'仅形成静态整数类别，实际发射仍需要就绪/资源/异常检查。',
'training_prediction_proposal':'为当前和即将分配的 ROB 位置生成预测提案，最终训练仍按已退休顺序。',
'retirement_next_proposal':'并行准备后续 PC，保持分配/当前完成旁路和旧结果的原优先级。',
'dispatch_source_ready':'检查分配侧源是否可以立即供值，不能把有效寄存器名当成数据就绪。',
'dispatch_register_value':'分配旁路供值仍需来自正确生产者或已退休寄存器。',
'instruction_csr_access_fault':'CSR 权限/操作数合法性属于静态异常事实，随指令身份保持。',
'immutable_control_metadata':'保存不依赖运行时结果的控制分类，不能把它当实际分支走向。',
'instruction_static_wakeup':'仅编码允许的静态唤醒事实，最终有效性由各执行通路限定。'
}
FUNCTIONS.update(EXTRA_FUNCTIONS)

OP={
'adc':'累加器带进位加法，分别更新进位、溢出与 Z/N。',
'sbc':'累加器减法沿用 6502 的借位/进位约定。',
'and':'对累加器执行按位与并更新 Z/N。',
'ora':'对累加器执行按位或并更新 Z/N。',
'eor':'对累加器执行按位异或并更新 Z/N。',
'bit':'测试 A 与操作数，并按实现更新对应状态位。',
'lda':'把寻址得到的值装入 A，随后更新 Z/N。',
'ldx':'把寻址得到的值装入 X，随后更新 Z/N。',
'ldy':'把寻址得到的值装入 Y，随后更新 Z/N。',
'sta':'把 A 写入寻址给出的目标，不能扩大为宿主物理写。',
'stx':'把 X 写入 NES 虚拟目标地址。',
'sty':'把 Y 写入 NES 虚拟目标地址。',
'jmp':'修改模拟 PC，目标由前面的寻址器生成。',
'jsr':'按原栈顺序保存返回位置，再更新模拟 PC。',
'rts':'从模拟栈恢复返回位置并应用原来的 PC 修正。',
'rti':'从模拟栈恢复状态与 PC，属于被模拟的中断返回。',
'brk':'保留此轻量引擎原有的软件中断处理，不在注释整理中修订。',
'cmp':'比较 A 与操作数，不写回减法结果，只更新相应标志。',
'cpx':'比较 X 与操作数，寄存器值保持不变。',
'cpy':'比较 Y 与操作数，寄存器值保持不变。',
'inc':'对寻址目标做字节增量并写回，更新 Z/N。',
'dec':'对寻址目标做字节减量并写回，更新 Z/N。',
'nop':'空操作处理器仍由表中预算参与时间推进。'
}

def related_assignments(texts):
 # The graph is deliberately local to each module and preserves original line
 # positions. It is a navigation aid, not a claim of exhaustive dataflow proof.
 groups=[];current=[]
 clean=''.join((''.join('\n' if c=='\n' else ' ' for c in value)
                if is_comment(token) or token in Token.Literal.String else value)
               for token,value in lex('\n'.join(texts),SystemVerilogLexer()))
 clean=re.sub(r'\(\*[\s\S]*?\*\)',lambda m:''.join('\n' if c=='\n' else ' ' for c in m[0]),clean)
 for line in clean.splitlines():
  if re.match(r'\s*module\b',line):
   current=[];groups.append(current)
  if current is not None:current.append(line)
 mapping={};position=0
 for group in groups:
  joined='\n'.join(group)
  # A physical source line can carry both a control test and an assignment.
  # Thus the result is labelled an association, not pure combinational fanout.
  names={}
  for line in group:
   targets=re.findall(r'(?<![\w.])([A-Za-z_]\w*)\s*(?:\[[^;\n]*?\])?\s*(?:<=(?!=)|=(?!=))',line)
   for name in set(re.findall(r'\b[A-Za-z_]\w*\b',line)):
    for target in targets:
     if name!=target:names.setdefault(name,[]).append(target)
  mapping[id(group)]={name:list(dict.fromkeys(values)) for name,values in names.items()}
 result=[];index=-1
 for line in clean.splitlines():
  if re.match(r'\s*module\b',line):index+=1
  result.append(mapping.get(id(groups[index]),{}) if index>=0 and index<len(groups) else {})
 return result

def software_function_note(name):
 if name.startswith('cpu_op_'):
  op=name[7:]
  if op in OP:return OP[op]
  if op.startswith(('asl','lsr','rol','ror')):return '移位/循环移位保留原来的进位输入输出；内存版还需写回目标。'
  if op in ('bcs','beq','bmi','bvs','bne','bcc','bpl','bvc'):return '按对应状态位的正/反条件决定是否把模拟 PC 改为相对目标。'
  if op in ('tax','txa','tay','tya','tsx','txs'):return '6502 内部寄存器传送，是否更新标志按该处理器原实现保留。'
  if op in ('clc','cld','cli','clv','sec','sed','sei'):return '只修改指定 6502 状态位，不改变 RV32 的硬件 CSR。'
  if op in ('php','pha','pla','plp'):return '通过模拟栈传送累加器或状态字节，不使用 RISC-V 宿主调用栈。'
  if op in ('inx','iny','dex','dey'):return '字节寄存器按本机宽度增减，随后更新 Z/N。'
  return '保留上游的扩展操作码组合语义，不据此声称全部扩展已通过实板兼容性测试。'
 if name.startswith('cpu_address_'):
  return '先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。'
 return None

def annotate(name,data):
 source,encoding=decode(data);lines=data.splitlines(keepends=True)
 texts=source.splitlines();notes={}
 def add(index,values):
  if isinstance(values,str):values=[v for v in values.split('|') if v]
  notes.setdefault(index,[]).extend(values)
 file=Path(name).name
 if name.endswith(('.v','.sv')):
  if file in CONTRACTS:add(0,CONTRACTS[file])
  associations=related_assignments(texts)
  for i,line in enumerate(texts):
   if i and texts[i-1].rstrip().endswith('\\'):continue
   if re.match(r'\s*(?:\(\*.*?\*\)\s*)?(?:input|output|inout|wire|reg|logic|parameter|localparam)\b',line):
    variable=first_name(line);note=declaration_note(variable,file,line) if variable else None
    if note:
     add(i,note)
     related=associations[i].get(variable,[]) if i<len(associations) else []
     if related and variable.lower() not in ('clk','clock','reset','rst','arst','cpu_clk','mem_clk','pix_clk'):
      add(i,'定位线索：原版中含此标识符的物理行还对 '+', '.join(related[:4])+' 赋值；同一行可能含多个语句，不能据此单独推断依赖。')
     if re.search(r'\[\s*0\s*:',line):
      if variable.startswith('q_'):add(i,'队列数组逐行由 q_valid 限定所有权；空行载荷允许残留，不能据数值推导就绪。')
      elif variable.startswith('rob_'):add(i,'ROB 数组按有效项使用；结果读取还需完成资格，回绕后同编号可能属于另一条指令。')
      elif variable.startswith(('result_','tval_','next_lane')):add(i,'银行数据的可见性由对应 ROB 完成位与 owner 选择共同限定。')
      elif variable.startswith(('instruction_','data_segments')):add(i,'存储阵列与控制位分开复位/维护，未知或旧行数据必须被有效状态屏蔽。')
   function=re.match(r'\s*function(?:\s+automatic)?(?:\s+\[[^]]+\])?\s+(\w+)',line)
   if function and function[1] in FUNCTIONS:add(i,FUNCTIONS[function[1]])
  for anchor,note in CONTROL.get(file,[]):
   index=next((i for i,line in enumerate(texts) if anchor in line and not line.lstrip().startswith('//')),None)
   if index is not None:add(index,note)
 else:
  if file in SW:add(0,SW[file])
  elif file in HEADERS:add(0,HEADERS[file])
  for i,line in enumerate(texts):
   if i and texts[i-1].rstrip().endswith('\\'):continue
   macro=re.match(r'\s*#define\s+(\w+)',line)
   if macro and macro[1] in MACROS:add(i,MACROS[macro[1]])
   if file=='soc_port.h':
    proto=re.search(r'\b(soc_\w+)\s*\([^{}]*\);',line)
    if proto and proto[1] in PROTOTYPES:add(i,PROTOTYPES[proto[1]])
   if file=='cpu-internal.h':
    flag=re.match(r'\s*(\w+)_(flag|bp)\s*=',line)
    if flag:add(i,flag[1]+(' 是状态位掩码，可与整个 P 状态字节按位组合。' if flag[2]=='flag' else ' 是位编号，供要求位置参数的位操作函数使用；不要传成掩码。'))
   if file=='ppu.h':
    field=re.match(r'\s*(?:byte|word|bool|int)\s+(\w+)',line)
    if field and field[1] in PPU_FIELDS:add(i,PPU_FIELDS[field[1]])
   function=re.match(r'\s*(?:static\s+)?(?:inline\s+)?(?:void|int|byte|word|unsigned|uint\d+_t|long|bool)\s+(\w+)\s*\([^;]*\)\s*\{',line)
   if function:
    note=software_function_note(function[1])
    if note:add(i,note)
    if function[1] in C_FUNCTIONS:add(i,C_FUNCTIONS[function[1]])
   op=re.match(r'\s*CPU_OP_(?:BIS|EIS)\(([0-9A-F]+),\s*(\d+),\s*(\w+),\s*"([^"]+)",\s*(\w+)\)',line)
   if op:add(i,f'操作码 0x{op[1]}：{op[4]}，{op[5]} 寻址，基础预算 {op[2]}；附加预算由 op_cycles 单独计入。')
  for anchor,note in SOFTWARE_CONTROL.get(file,[]):
   index=next((i for i,line in enumerate(texts) if anchor in line and not line.lstrip().startswith('//')),None)
   if index is not None:add(index,note)
 newline=b'\r\n' if b'\r\n' in data else b'\n';out=[]
 for i,line in enumerate(lines):
  indent=re.match(rb'\s*',line)[0].replace(b'\r',b'').replace(b'\n',b'')
  for note in notes.get(i,[]):
   if name.endswith(('.S','.ld')):comment='/* [ARCH] '+note.replace('*/','* /')+' */'
   else:comment='// [ARCH] '+note
   out.append(indent+comment.encode(encoding)+newline)
  out.append(line)
 return b''.join(out),sum(len(v) for v in notes.values())

def main():
 scope=json.loads((ROOT/'audit/SOURCE_SCOPE.json').read_text())
 counts={}
 with zipfile.ZipFile(ROOT/'baseline/original_preboard.zip') as z:
  for name in scope['hardware_rtl']+scope['firmware_source']:
   original=z.read('rv32_soc_Mario_V03/'+name)
   annotated,number=annotate(name,original)
   (ROOT/'source'/name).write_bytes(annotated)
   counts[name]=number
 (ROOT/'audit/ANNOTATION_INSERTIONS.json').write_text(json.dumps(counts,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('Added architecture-comment lines:',sum(counts.values()))
if __name__=='__main__':main()
