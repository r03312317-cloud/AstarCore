from pathlib import Path
import json,html,sys,re
from docx import Document
from docx.shared import Cm,Pt,RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT,WD_CELL_VERTICAL_ALIGNMENT
sys.path.insert(0,str(Path(__file__).resolve().parent))
from annotation_spec import MODULES,PROTOCOLS
r=Path(__file__).resolve().parents[1]
read=lambda p:json.loads((r/p).read_text(encoding='utf-8'))
s=read('analysis/algorithm_summary.json');co={x['group']:x for x in s['cohorts']}
cm=read('verification/comment_and_equivalence.json');inv=read('docs/module_inventory.json');tim=read('evidence/timing_qualification.json')
glob=read('evidence/pipeline/data/simulation_statistics.json')
hw=read('evidence/pipeline/data/hardware_statistics.json')
inventory={x['module']:x for x in inv}
def ref(m):
    x=inventory[m];return f"{x['file']}:{x['annotated_line']}"
def num(x):return f'{x:,}'
def group_summary(g):
    a=co[g];return [['队头归属周期及全程占比',num(a['head_owned_cycles'])+f"  {a['cycle_share_percent']:.3f}%"],['按本指令PC计退休数',num(a['retired_instructions_by_exact_pc'])],['双发射接收及双提交比例',f"{a['dual_issue_percent']:.3f}%  /  {a['dual_retire_percent']:.3f}%"],['ROB等待及恢复比例',f"{a['commit_wait_percent']:.3f}%  /  {a['recovery_percent']:.3f}%"],['ROB占用平均及最大',f"{a['mean_rob']:.3f}  /  {a['max_rob']}  容量16"]]
pages=[]
def page(title):
    a={'title':title,'blocks':[]};pages.append(a);return a['blocks']
def p(a,text):a.append({'kind':'p','text':text})
def h(a,text):a.append({'kind':'h','text':text})
def table(a,headers,rows,widths=None):a.append({'kind':'table','headers':headers,'rows':rows,'widths':widths})
def image(a,path,caption,width=16.2):a.append({'kind':'image','path':path,'caption':caption,'width':width})
def code(a,text):a.append({'kind':'code','text':text})

a=page('版本与主要结论')
p(a,'本报告面向本项目的架构审查、技术报告与源码复现，整理最近一次实际上板运行的 RV32 130MHz ILA117 版本。架构源码只增加中文注释，非注释词法单元与原始冻结输入一致；性能分析结合上次实板记录与同版 RTL 的新观测仿真。')
table(a,['项目','本交付采用的真实配置'],[
 ['硬件身份','RV32CM130_ILA117_TAGSPLIT_f7d53c31485572a2'],['上次实板采集','2026年11月3日 MINI200K PG2L200H 速度级负6 FBB676'],
 ['时钟和存储','125MHz参考  130MHz CPU  64KiB SRAM'],['执行组织','有界乱序  最大双分配 双发射 双提交'],['队列容量','16项ROB  8项前端队列  7个启用发射槽'],
 ['一级Cache','I 16KiB两路  D 8KiB两路  64B行'],['实板正式CoreMark','20000次  972.790845次每秒  7.483006501 CoreMark每MHz'],
 ['全程计数','2672722521个周期  3989484251条退休指令  IPC 1.492666829']],[3.2,13.0])
p(a,'主要发现是矩阵段最容易维持双槽位并行，链表受数据和控制依赖限制，状态机对分支恢复更敏感；CRC 在编译后使用通用 Zbc 指令，但结果依赖与通用 MDU 返回延迟仍限制其队头吞吐。相关数字均保留分组方法和分母，不作为独立算法跑分。')
p(a,'本交付没有恢复已停止的150MHz优化，也没有重新烧录板卡。原始源文件、既有版权和许可原样保存在 original 和 software 目录。')

a=page('架构数据流与流水边界')
image(a,'figures/architecture.png','图1 主要功能连接。图中各块是功能域，不代表每条指令固定相同拍数。')
table(a,['功能边界','该阶段保存或确认的内容'],[
 ['取指与响应','Cache同步读 请求pending 预测快照 错误与错误路径身份'],['前端缓冲','8项队列的指令 PC 相对或绝对预测描述符 源分类'],
 ['分配与重命名','保留ROB位置 绑定目的生产者 为未就绪源保存标签'],['调度和EX','按相对年龄选择兼容就绪项 两个EX槽捕获所有者'],
 ['完成与唤醒','整数 访存 运算结果写入各银行 携带标签唤醒依赖'],['提交与恢复','ROB按序改写架构状态 最大双提交 必要时清除年轻所有权']],[3.2,13.0])
p(a,'不能把这六个功能域直接写成所有指令固定六级流水。普通整数可以从分配旁路进入空闲 EX；Load、跨行取指、MUL、DIV 和维护操作经过不同等待与返回路径。只有实际握手和 valid 更新能决定某条指令何时前进。')

a=page('取指与分支预测模块')
h(a,'主取指前端')
p(a,f"rv32_ooo_frontend 的入口为 {ref('rv32_ooo_frontend')}。主实现有8条指令队列，本板允许2笔按序取指信用。奇偶银行支撑相邻指令成对写入，指令、PC、预测描述符、源使用、合法性和错误标记随同一槽位保存。redirect 清除有效所有者，已发出请求仍按 killed 身份排空。")
p(a,'rv32_ooo_frontend_serial 提供较串行的兼容实现。它在源码中保留并不表示本板使用单请求取指，也不能用该分支状态数描述当前吞吐。')
h(a,'方向预测与训练')
p(a,f"rv32_hybrid_predictor 位于 {ref('rv32_hybrid_predictor')}。本板 B9 G12 H12 配置包含4096项 GShare、512项 chooser，以及启用的256行 H5 局部方向分量。预测时保存历史与两分量方向，提交时根据该上下文训练。四个查询 PC 是预测候选口数，CPU 发射最大宽度仍为2。")
p(a,'rv32_predictor_counters 实现两位饱和表与奇偶查询银行；初始化由最大表扫表统一管理。rv32_local_direction_cache 把局部历史和模式计数放在训练路径，查询只读缓存方向位，避免历史 RAM 到模式 RAM 串联读。训练FIFO最多接收两条、单条消化；无训练信用时条件分支提交可以等待。')
h(a,'返回与目标预测')
p(a,'rv32_committed_ras 是深度16的已提交返回地址栈。JAL 和 JALR 根据 x1/x5 提示产生入栈、出栈或先出后入，双提交依次应用。投机错误调用没有退休训练，因此不需要把软件栈或整套投机调用复制进返回栈。实际 JALR 地址在执行端计算，rv32_jalr_target_match 以并行进位一致性精确判等预测目标。')
p(a,'从性能上看，目标/方向错误消耗错误路径发射和恢复周期；训练信用等待、队列空与 Cache 回填是不同原因。本次短测训练压力并未成为 ROB 等待的统计分类，不能由其存在就宣称它是实测瓶颈。')

a=page('重命名调度与按序提交')
h(a,'ROB和重命名状态')
p(a,f"主后端为 {ref('rv32_ooo_core')}。ROB 为16项环形队列，head表示最老位置，tail表示下一分配位置。架构RF用两个退休银行及最后写者位读取；map_valid 和 map_tag 指向最新未提交生产者。老指令提交时仅在map仍指向它时清除映射，年轻写者不会被误清。")
p(a,'发射数组虽然声明12行，实际 ACTIVE_QUEUE_MASK 为0x733，只启用0、1、4、5、8、9、10，共4个整数槽与3个复杂槽。rv32_queue_allocator 只读取寄存占用寻找空位，本板不进行同周期释放再分配。rv32_rename_onehot_read 并行归并独热源选择，减少晚到动态表索引。')
h(a,'有界乱序与双槽位')
p(a,'rv32_issue_scheduler 保存行对之间的相对先后关系；rv32_issue_rank 在 eligible 和资源约束下求最老兼容候选。真实完成广播可以使源在本拍就绪；未匹配标签的数值不能唤醒。复杂候选使用 EX0，整数可以配入 EX1。rv32_issue_payload_mux 先归并各银行宽数据，再选择晚到候选。rv32_issue_bank 是保留的局部 age 排名兼容模块，应与正常相对关系路径区分。')
p(a,'独立年轻指令可先于未就绪老指令完成，但不能越过 ROB 队头改写架构RF。普通整数直接dispatch旁路仍占有ROB程序顺序位置，也仍受源就绪及同束RAW依赖检查。')
h(a,'完成与副作用边界')
p(a,'三套完成结果银行和 result_owner 分摊写口，rob_done 保证未初始化或错路径数据不可退休。队头成功Load响应可以显式前递；严格限定的当前整数后继也可配对退休。异常、MRET、FENCE与误预测在提交边界形成恢复。')
p(a,'rv32_order_release_filter 处理访存阻塞者释放。本板允许年轻Load在约束内越过老Load，但Store和外设副作用仍受程序顺序限制。已呈现外部请求要保持或排空，recovery杀死返回所有者身份，不会撤销已经发生的外部写入。')

a=page('指令语义与整数执行模块')
h(a,'语义译码和合法性')
p(a,f"rv32_execute 位于 {ref('rv32_execute')}，是纯组合指令语义模块。它输出源使用、目的写资格、value、地址、Store载荷、下一PC、CSR读改写建议和系统类别；真正的RF写入、访存及异常必须由核心有效所有者控制。")
p(a,'按实际译码和固件 march，本版使用 RV32I、M、Zicsr，以及 Zba、Zbb、Zbc、Zbs 位操作。还提供本项目机器态 CSR、陷阱返回与Cache维护语义。它没有因支持某些系统编码就实现完整多特权级/MMU；本报告不把编译参数本身当作所有编码均已认证的证明。')
p(a,'rv32_instruction_flags 只预判编码合法性，不能替代CSR存在性、取指错误、操作数或地址未对齐检查。合法 ECALL 编码仍按语义产生异常。')
h(a,'提前译码与数据网络')
p(a,'rv32_alu_predecode 把不依赖源数据的控制提前放在已有队列或EX边界保存；rv32_alu_value 使用保存控制计算整数结果。CLZ、CTZ和population采用平衡归约，移位/旋转由参数选择共享或双桶形网络。原语义路径在VERILATOR中对有效包逐项比较。')
p(a,'rv32_address_classify 用低位加法与区域边界纠正，精确等价于完整有效地址之后的外设分类。它没有省略真实地址计算。rv32_jalr_target_match 用相邻位进位约束精确检查预测地址，同样没有改变实际跳转目标。')
table(a,['结果类别','完成条件及主要限制'],[['整数ALU','EX有效且无对应异常时可完成或旁路；写x0不建立生产者'],['Load与Store','地址生成不等于完成；需LSU及Cache/总线确认'],['分支与跳转','实际方向和目标与原预测核对，提交时精确恢复'],['CSR和系统','访问形式与号码检查，按序提交才能改写可见状态']],[3.2,13.0])

a=page('乘除流水与通用位运算单元')
p(a,f"低位 MUL 的专用通路为 {ref('rv32_mul_stream')}。接收边界保存三个16乘16部分积，部分积槽与结果缓冲合计两信用。缓冲为空时可直接消费已寄存部分积的低字结果；缓冲非空时旧结果优先，token随数值一起移动。")
p(a,'本板使用寄存占用决定入口信用，避免 response_ready 沿返回仲裁反传到请求许可。EX0在确实没有信用时保持，EX1仍可推进兼容整数。此次完整计时窗口 ex_hold 为0，说明没有观察到这类背压，不代表乘法依赖或其他停顿都消失。')
table(a,['通用运算类型','接受后的结果延迟','实现路径'],[['MUL通用路径','2拍','部分积和低列归并；普通低位MUL可走专用流水'],['MULH MULHSU MULHU','3拍','部分积 高列归并及有符号修正'],['CLMUL CLMULR CLMULH','2拍','GF2部分积与异或归并'],['DIV DIVU REM REMU','正常33拍','恢复余数迭代及最终符号修正'],['除零与有符号溢出','接受边界登记','特殊结果不是输入到输出的组合旁路']],[4.2,3.3,8.7])
p(a,f"rv32_arithmetic 位于 {ref('rv32_arithmetic')}，一次只有一笔拥有状态的请求，响应保持到ready，不支持响应消费同边界立即接受下一请求。rv32_carryless_product16 用平衡XOR树计算16位GF2乘积，四个实例组成32位CLMUL。")
p(a,'低位流式MUL可以重叠多个所有者；通用CLMUL则受其状态和结果依赖制约。两者都属于通用指令实现，不含识别CoreMark数据或固定CRC答案的硬编码。本次源码整理保留了这些实际延迟，没有采用后续150MHz实验中的新算术结构。')

a=page('Cache总线与非对齐事务')
p(a,f"Cache主模块是 {ref('rv32_memory_system')}。I和D均为两路组相联，64B行。I数据按32位奇偶字银行组织，D每段64位按字节银行实现写掩码。RAM读经过时钟边界，标签与有效快照必须对应被接受请求。")
table(a,['项目','I cache','D cache'],[['组数和路数','128组 2路','64组 2路'],['容量','16KiB','8KiB'],['数据用途','双字取指与跨行处理','Load Store 写分配及脏行写回'],['替换信息','每组一位替换状态','每组一位替换状态与各路dirty'],['外部一行传输','8个64位数据拍','8个64位数据拍及写响应']],[3.5,6.3,6.4])
p(a,'130MHz已上板版本把 I 路标签逐位相等结果寄存在已有RAM读边界，之后再归约选路；未额外增加取指事务周期。D命中和way也有对应请求快照。数据输出可以是未拥有的提案，response_valid与error才决定它是否成为有效返回。')
p(a,'缺失替换遇到脏行时先写回旧行并等待写响应，然后发目标行读。MMIO走独立外围握手，FENCE维护逐set/way清扫。CPU/cache外部是项目 req/gnt/rvalid 突发接口，不能不加说明地称为完整AXI。')
p(a,f"rv32_unaligned_adapter 位于 {ref('rv32_unaligned_adapter')}。对齐访问组合直通，非对齐RAM半字/字保存偏移与掩码，按需拆成一至两个32位子事务。完整RAM边界和MMIO范围在首子事务前检查；若第二笔后来出现总线错误，先前部分Store仍可能已可见，所以拆分Store不是原子事务。")
p(a,'回填计数是行事务数量，缺少总查询数时不能换算命中率。非对齐子事务、回填等待、Cache维护和外设等待需要分别理解；本次算法性能全部基于SRAM路径，没有以此替代DDR性能结论。')

a=page('板级集成与真实运行配置')
p(a,f"rv32_ooo_soc_top 连接CPU、非对齐适配器及Cache，入口为 {ref('rv32_ooo_soc_top')}。本板 REGISTER_INSTRUCTION_REQUEST 和 REGISTER_RESPONSES 均为0；LOAD_BYPASS、控制dispatch、已提交RAS及两个取指信用启用。")
p(a,'rv32_board_memory 提供64KiB初始化SRAM。I侧独立读口可与D侧重叠，D读与写回共享另一个物理端口；每个正常读beat经过ISSUE与RESPONSE，响应背压期间数据保持。它不是零等待TCM旁路。')
p(a,'rv32_coremark_system_boot 将loader、CPU、SRAM、UART、计时器和退出寄存器集成。loading期间CPU复位且存储口由loader拥有；两次被接受的timer读取同时保存退休快照。IRQ三类线在当前板级实例接零，所以通用中断逻辑与实板中断覆盖需要分开陈述。')
p(a,'uart_loader 负责应用启动前的UART装载和可选读回验证，AUTOBOOT超时与CoreMark计时不是同一阶段。rv32_coremark_top_boot 连接差分时钟、PLL、上电计数和输出寄存。rv32_board_pll_130为厂商生成的时钟包装，原样保留。ILA在PDS综合后插入，源码未实例化ILA不代表上次位流没有ILA。')
table(a,['地址或配置','含义'],[['0x10000000 至 0x1000ffff','64KiB SRAM 固件 数据 栈和工作区'],['0x30000000','UART写数据'],['0x30000004','程序退出和状态'],['0x30000010 与 0x30000014','64位timer低高字'],['0x30000020 至 0x3000002c','两次计时边界的退休快照'],['UART_DIV 1128','130MHz板级115200波特率配置'],['UART_DIV 4 和启动等待8','功能仿真加速配置 计时窗口内CPU结构相同']],[5.0,11.2])

a=page('观测方法与全程统计口径')
p(a,'本次没有重新采集硬件，而是使用2026年11月3日真实CoreMark与异常ILA。CoreMark捕获512点117位，原生TXT与VCD共59904位逐位一致，无X/Z；两个EX有效PC共712个均落入对应正式固件的matrix_test。')
p(a,'同版仿真在已有通过验证的Verilator模型副本上链接只读观察器，没有修改RTL。performance10固件在两次真实timer MMIO接受边界间经历1342928周期，退休1994683条。串行UART字节与此前接受记录逐字节一致，CRC和周期均复现。')
table(a,['观测量','值','证据来源'],[['同拍接收两条','873696周期 65.059%','同版短测仿真'],['同拍提交两条','845888周期 62.988%','同版短测仿真'],['分配阻塞','112888周期 8.406%','fetch_count非0且allocate_count为0'],['ROB等待提交','146931周期 10.941%','ROB非空 无retire0 无recovery'],['EX0乘法入口保持','0周期','ex_hold真实观测'],['局部实板双EX占用','219/512点 42.773%','CoreMark ILA'],['局部实板双提交','222/512点 43.359%','CoreMark ILA寄存位图']],[4.2,5.3,6.7])
p(a,'EX valid是占用，包含可能被保持的指令；新发射接收还要排除recovery及EX0保持，包含正常队列发射和直接dispatch旁路。debug_retire由组合retire资格寄存，仿真逐相邻边界验证了其相位、EX更新及ROB头尾与占用更新，共1342927次检查。')
p(a,'各等待谓词可以重叠，不能相加当作总停顿率；前端队列空时后端仍可执行。原生ILA没有直接探测停顿口，硬件未提交观测也不能统一归为停顿。原生VCD的100ns是导出显示刻度，图以采样/周期序号作横轴。')

a=page('关键算法的可比统计')
p(a,'所有计时周期按当拍存活ROB队头PC映射到ELF符号分组，ROB空则单列。每条真正退休指令则按它自己的PC归类，因此跨函数双提交不会被强塞给队头函数。图表的双发射、双提交和等待比例表示“队头属于该组的周期里CPU发生了什么”。')
image(a,'figures/algorithm_comparison_doc.png','图2 全计时窗口分组结果。分母为各队头分组周期，算法之间可能存在流水重叠。',16.2)
table(a,['队头分组','周期占比','退休指令数','组内退休吞吐'],[[g,f"{co[g]['cycle_share_percent']:.2f}%",num(co[g]['retired_instructions_by_exact_pc']),f"{co[g]['cohort_retired_per_cycle']:.3f}"] for g in ['链表','矩阵','状态机','CRC','ROB为空']],[3.2,3.0,4.0,6.0])
p(a,'组内退休吞吐按该组周期内CPU全局提交数计算，不是单独计时该函数得到的IPC。CRC保留独立符号组，不重新分摊到调用者；内联进matrix_test或core_bench_list的指令算在其实际所在符号内。编译内联也使源码子循环难以仅凭ELF符号单独分时。')

for group,title,paras in [
 ('链表','链表算法的访存依赖与控制开销',[
 'core_bench_list 执行查找、反转、排序及移除恢复，cmp_complex和calc_func还可能触发矩阵与状态机工作。iterate每轮两次调用链表测试，因此源码调用关系不是三个算法各自互不重叠地跑完一次。',
 '按实际退休PC归类，链表共有729832条指令，其中Load 271978条、Store 76963条、条件分支214932条。指针追踪使下一地址依赖前一次Load结果，排序/比较又引入控制依赖；只有独立循环、索引及其他源已就绪的操作可以填充第二槽。',
 '该队头组的ROB等待29541周期，其中队头为Load的等待10158周期、整数/位操作12442周期。等待的整数可能在等前序数据，不能把所有这些周期都称为Cache miss。平均ROB占用8.951项，最大15项，未达到16项，说明该组的等待并非简单由ROB长期满造成。',
 '从数据看，双发射接收65.143%而双提交59.871%，二者受错路径与完成时机共同影响。源代码和依赖结构支持“需要进一步缩短依赖链或提高可重叠工作”的分析，但没有进行单因素实验来给每个因素精确分摊收益。']),
 ('矩阵','矩阵算法的双槽位与乘法重叠',[
 '矩阵源码依次执行常量加法、常量乘、矩阵向量乘、矩阵矩阵乘、位提取矩阵乘和校验归并，最后恢复输入。编译器把大量子例程内联进matrix_test；不能只统计仍保留独立符号的matrix_mul_matrix来代表全部矩阵乘法。',
 '矩阵按PC归类退休707440条，包含93960条低位MUL、146520条Load和17120条Store。展开循环同时暴露地址递增、加载、乘法及累加等工作，为复杂EX0与整数EX1提供兼容候选。该组双发射76.668%、双提交79.401%，恢复仅0.383%。',
 '低位MUL流水通过两信用和部分积直接响应减少强制结果寄存等待。计时窗口未观察到ex_hold，但矩阵仍有28362个ROB等待周期：队头MUL 7670周期、整数/位操作17002周期。这与结果链和累加依赖仍存在相符，不能由ex_hold为0推导乘法完全无代价。',
 '上次物理ILA的512点全部位于matrix_test，双EX同时占用219拍、双提交222拍，提供真实硬件并行证据。该局部窗口平均1.378906条/采样，与完整短测矩阵队头组吞吐1.724847不是同一分母，差别不能被解释为功能回退或性能提升。']),
 ('状态机','状态机算法的分支与恢复敏感性',[
 'core_bench_state 扫描输入串、修改部分字符、再次扫描并恢复数据。core_state_transition按字符类别与当前状态转移，含START、整数、小数、符号、指数及无效状态，源码有大量条件判断和switch路径。',
 '该组退休496480条指令，条件分支199200条，占40.122%左右；Load 65480条、Store 12800条。分支方向、字符Load与状态更新互相依赖，即使某些周期双槽均有工作，也可能很快在一次恢复中丢弃年轻推测工作。',
 '该队头组恢复13563周期，占4.152%，高于链表的1.311%和矩阵的0.383%；ROB等待42908周期，占13.134%。其中等待队头为Load 12931、Store 9661、整数/位操作13918、条件分支6396周期，不能只归因为分支预测。',
 '平均ROB占用6.140项、最大13项，前端空3.125%。这些现象更符合控制流与依赖使有效并行窗口收缩，而不是单纯增大ROB就必然解决。下一步若优化预测，应分别测方向、目标和训练压力，不能把所有recovery直接当同一种方向miss。'])]:
 a=page(title)
 table(a,['本算法队头组指标','实测同版仿真值'],group_summary(group),[8.0,8.2])
 for text in paras:p(a,text)
 image(a,f'figures/{group}_doc32.png',f'图 {len(pages)-8} {group}相关窗口的32拍示例。逐拍关系见CSV，整体比例使用完整组周期。',14.0 if group=='矩阵' else 15.0)

a=page('CRC编译结果与通用指令效率')
p(a,'CoreMark原始core_util.c仍是逐位CRC循环，本交付五个算法C文件均匹配随附coremark.md5。实际performance10反汇编的crc16、crcu16和crcu32含CLMUL类指令；因此本版的CRC效率需要同时分析编译器产生的通用Zbc指令及硬件通用MDU。')
table(a,['CRC观测量','值'],[['按退休PC归类指令数','60740'],['CLMUL类退休指令','11680  约19.230%'],['队头归属周期','84741  占全计时6.310%'],['同拍接收两条','19.928%'],['同拍双提交','28.395%'],['ROB等待提交','46080周期  54.377%'],['其中队头CLMUL等待','31582周期'],['其中队头整数或位操作等待','14498周期']],[9.4,6.8])
p(a,'CRC的当前值是下一步输入，存在强数据递推。通用arith单元一次一笔并在响应消费后回到IDLE，CLMUL两拍计算加上接口与依赖限制使该段难以持续双发射。等待队头类别观测支持这个方向，但没有单独旁路实验来精确分解计算延迟与数据依赖各占多少周期。')
p(a,'这里使用的是通用GF2多项式指令实现，没有CPU外MMIO算法加速器，也没有改写本次benchmark核心C源码。矩阵依赖低位MUL流水，CRC主要依赖通用CLMUL，两条硬件路径不应混为同一个“乘法加速”。')
p(a,'可复核文件是 analysis/performance10_disassembly.txt、software/src/coremark/core_util.c、analysis/algorithm_instruction_mix.csv 与 commit_wait_by_head_instruction.csv。头文件coremark.h虽与随附旧MD5条目不符，但与2026年11月4日读取的EEMBC官方文件逐字节一致；差异记录与校验JSON保留，未覆盖原校验清单。')
p(a,'官方头文件对照地址 https://raw.githubusercontent.com/eembc/coremark/main/coremark.h 。该对照用于来源核查，不替代固件CRC与实测时序验证。')

a=page('软件构建与成绩复算')
p(a,'正式固件和短测使用相同的GCC15.2.0 xPack工具链与指令集选项，分别以20000和10作为迭代数。命令中保留早期候选选项，但重复选项以最后一项生效；因此不能只看到FLAGS_STR开头的O3就把该固件描述成最终O3构建。')
table(a,['构建项','实际最终选项或值'],[['优化级别','最后为 -O2'],['ISA和ABI','rv32im_zicsr_zba_zbb_zbc_zbs  ilp32'],['循环展开','-funroll-loops  -funroll-all-loops'],['分支与内联','-mbranch-cost=1  max-inline-insns-auto=80'],['调度模型','-mtune=sifive-7-series'],['布局与小数据','functions=16  jumps=8  loops=4  labels=4  small-data-limit=16'],['链接松弛','最后为 -mrelax'],['工作数据和计时','TOTAL_DATA_SIZE=2000  CPU_HZ=TIMER_HZ=130000000']],[4.3,11.9])
p(a,'五个CoreMark算法C文件原样保存并通过随附MD5；改动空间在平台启动、计时、编译和通用指令硬件实现。本次交付没有重新选择编译器或改变算法源码，反汇编和原build_plan保留以复核CLMUL及内联行为。')
p(a,'mtune选择的是编译器的软件调度成本模型，不表示硬件采用了同名处理器核。软件生成的调度、指令和代码布局都影响成绩，不能把编译收益全部归因于RTL变化。')
p(a,'链接地址由link.ld明确给出，RAM为0x10000000起的65536字节，.text、.rodata、.data与.bss都在此范围，栈顶为0x1000fff0并保留至少8KiB栈空间断言。performance10的text为50660字节、data为24字节、bss为2112字节；这不是从打印的SRAM字符串单独推断存储位置。')
code(a,'实板秒数 = 2672722521 / 130000000 = 20.5594040077\nCoreMark = 20000 / 20.5594040077 = 972.790845\nCoreMark每MHz = 20000 × 1000000 / 2672722521 = 7.483006501\n全程IPC = 3989484251 / 2672722521 = 1.492666829')
p(a,'计时始末由板级外设接受timer读取时确定，不包含下载与模型装载。固件打印旧Build ID，所以硬件身份由真实位流SHA与源清单绑定；仅靠串口中的字符串不能判断是否烧录了相同物理实现。')

a=page('物理资源时序与实板证据')
table(a,['器件映射资源','已用','器件可用'],[['LUT','24427','159800'],['FF','9672','319600'],['Distributed RAM','2051','39500'],['DRM','45','415'],['APM','7','740'],['SCANCHAIN','1','1'],['GPLL','1','10']],[6.0,5.1,5.1])
p(a,'资源来自本次已上板130MHz ILA版本的原生device map日志，包含调试插入后的设计，不是净CPU面积，也不是之后150MHz候选的利用率。Cache及64KiB SRAM采用片上存储，因此资源构成不能直接类比ASIC面积。')
table(a,['最终多角检查','慢角最差余量','快角最差余量'],[[k,f"{tim['worst_slack_ns'][k+'_slow']:+.3f} ns",f"{tim['worst_slack_ns'][k+'_fast']:+.3f} ns"] for k in ['setup','hold','recovery','removal','mpw']],[6.2,5.0,5.0])
p(a,'全部必要检查通过，cpu_clk请求130MHz，原生估算Fmax为131.4008MHz。这里是最终布线STA的结果，不是布局估计或板上独立扫频；也不能把正余量外推成150MHz已经闭合。原始报告和位流放在implementation_reference，原位流SHA为eef99a0318d65129ced86535464fbe26d7210ae82dcfdf9a2279f77037235aef。')
p(a,'20,000次实板计时20.559404008秒，CRC为seed e9f5、list e714、matrix 1fd7、state 8e3a、final 382f。实板I行回填240179、D行回填1、D写回0、条件分支miss事件40866766。事件没有总访问计数，报告不据此构造Cache命中率。')

a=page('源码注释与模块索引')
p(a,f"本交付架构RTL共17个文件，包含26个RTL模块；另附5个板级模块，总计31个模块均有功能说明。注释前非空行{cm['rtl_before']['nonblank_lines']}行，其中纯注释848行。注释后非空行{cm['rtl_after']['nonblank_lines']}行，纯注释{cm['rtl_after']['comment_only_lines']}行，另有9行代码与注释混合。纯注释占比{cm['rtl_after']['comment_only_percent']:.3f}%，含注释行占比{cm['rtl_after']['comment_bearing_percent']:.3f}%，接近约30%的目标。")
p(a,'比例按非空物理行计算，空行不充数，生成PLL不计入手写架构RTL统计。小型组合模块需要完整契约说明，局部比例会高于30%；大型核心保留原本重复的静态银行写分支，局部比例较低。逐文件统计全部公开，不宣称每个文件都恰好30%。')
table(a,['源码文件组','模块职责'],[['rv32_ooo_core.v','主后端 顺序释放过滤器 独热重命名读'],['rv32_ooo_frontend.v','多请求主前端与串行兼容前端'],['rv32_issue_scheduler.v','相对年龄调度与兼容候选排名'],['rv32_execute.v','语义译码 提前ALU译码与数据结果'],['rv32_hybrid_predictor.v','混合预测 两位表 局部方向缓存'],['rv32_memory_system.v','I/D Cache 外部行事务和MMIO'],['其余RTL文件','RAS 资源分配 payload选择 算术 非对齐和辅助判等']],[7.2,9.0])
p(a,'docs/模块功能详解.txt逐模块列出职责、接口约束、事务示例和实际源码定位；docs/module_inventory.json提供机器可读索引。rtl是注释后的阅读/集成版本，original是上次输入的逐字节副本，board和constraints是对应集成参考。')
p(a,'noncomment token逐项相等，并单独验证原有综合语义注释未改变。Verilator对完整注释RTL及真实board system/SRAM/loader检查通过；230项既有类别警告保留在日志，没有以压制所有警告来宣称零警告。注释不改变逻辑，因此本次没有重新综合或布线。')

a=page('复现方法与证据边界')
p(a,'首先阅读根目录README和docs/模块功能详解.txt，再按rtl_filelist.f集成CPU/cache；board_filelist.f增加130MHz板级参考，厂商PLL及差分输入原语需要PDS器件库。直接重建必须在新工作副本中进行，不能在永久封存目录内写构建结果。')
table(a,['复核目的','入口及预期'],[['核对注释没有改逻辑','tools/verify_delivery.py  比较原始/注释词法单元 统计SHA及注释比例'],['语法检查','tools/lint_sources.py  使用本机Verilator 检查CPU加Cache及板级功能顶层'],['复核分算法统计','tools/analyze_algorithms.py  从原始计时窗口CSV重新计算'],['重放同版仿真','tools/run_algorithm_profile.py  在独立新输出目录链接模型观察器'],['核对实板ILA','evidence/pipeline/hardware 与 data  样本逐位校验及PC定位'],['核对物理通过','implementation_reference/native_routed_timing.rtr 与 evidence/timing_qualification.json']],[5.3,10.9])
p(a,'源代码、固件bin/hex/ELF、工具链选项、原始UART、VCD/TXT、逐周期CSV、统计表及交付SHA清单均随包保留。原PDS脚本中的历史绝对路径仅作原生实现参考，迁移机器需要重定向路径及IP库；这份源码包不声称已经替用户生成一个新的物理实现。')
p(a,'分析限制包括：只有矩阵有这次正式CoreMark实板512点窗口；链表、状态机和CRC的分组数据来自10次同版仿真；源码内联使符号边界不等于所有源码子算法边界；等待谓词重叠；Cache访问总数与板上真实IRQ覆盖仍未由本包扩展。建议先比较同一输入、同一编译参数、同一统计窗口，再解释任何后续优化收益。')
p(a,'报告整理日期为2026年11月4日，所有架构结论以本包原始与注释RTL为准。150MHz优化候选和后来可能出现的其他工程不参与本报告基线。')

title='RV32 130MHz CPU架构源码与CoreMark流水线性能分析'
(r/'docs/report_content.json').write_text(json.dumps({'title':title,'pages':pages},ensure_ascii=False,indent=2),encoding='utf-8')
guide=[]
for item in inv:
    name=item['module'];guide += [name,ref(name),MODULES[name]]
    if name in PROTOCOLS:guide += ['接口契约与示例',PROTOCOLS[name]]
    guide += ['']
(r/'docs/模块功能详解.txt').write_text('\n'.join(guide),encoding='utf-8-sig')

doc=Document();sec=doc.sections[0];sec.page_width=Cm(21);sec.page_height=Cm(29.7)
sec.top_margin=Cm(1.65);sec.bottom_margin=Cm(1.7);sec.left_margin=Cm(2.0);sec.right_margin=Cm(2.0)
sec.header_distance=Cm(.7);sec.footer_distance=Cm(.75)
for sty in ['Normal','Title','Subtitle','Heading 1','Heading 2','Heading 3','Caption']:
    st=doc.styles[sty];st.font.name='Microsoft YaHei';st._element.rPr.rFonts.set(qn('w:eastAsia'),'Microsoft YaHei');st.font.color.rgb=RGBColor(0,0,0)
for border in list(doc.styles.element.iter(qn('w:pBdr'))):border.getparent().remove(border)
doc.styles['Normal'].font.size=Pt(10)
doc.styles['Normal'].paragraph_format.line_spacing=1.18;doc.styles['Normal'].paragraph_format.space_after=Pt(6)
doc.styles['Title'].font.size=Pt(22);doc.styles['Title'].paragraph_format.space_after=Pt(12)
doc.styles['Heading 1'].font.size=Pt(16);doc.styles['Heading 1'].paragraph_format.space_after=Pt(10)
doc.styles['Heading 2'].font.size=Pt(11.5);doc.styles['Heading 2'].paragraph_format.space_before=Pt(8);doc.styles['Heading 2'].paragraph_format.space_after=Pt(4)
doc.styles['Caption'].font.size=Pt(8.5);doc.styles['Caption'].paragraph_format.space_after=Pt(6)
doc.styles['Caption'].paragraph_format.line_spacing=1.05
header=sec.header.paragraphs[0];header.text='RV32 130MHz 实板版本  架构与性能分析';header.style=doc.styles['Caption']
foot=sec.footer.paragraphs[0];foot.alignment=WD_ALIGN_PARAGRAPH.RIGHT
foot.add_run('RV32 130MHz   ')
for instr in ['PAGE','NUMPAGES']:
    if instr=='NUMPAGES':foot.add_run(' / ')
    el=OxmlElement('w:fldSimple');el.set(qn('w:instr'),instr);foot._p.append(el)
for run in foot.runs:run.font.size=Pt(8)

def add_table(block):
    headers=block['headers'];rows=block['rows'];widths=block['widths'] or [16.2/len(headers)]*len(headers)
    t=doc.add_table(rows=1,cols=len(headers));t.alignment=WD_TABLE_ALIGNMENT.CENTER;t.autofit=False
    for col,width in zip(t.columns,widths):col.width=Cm(width)
    for i,h_ in enumerate(headers):t.rows[0].cells[i].text=str(h_)
    repeat=OxmlElement('w:tblHeader');t.rows[0]._tr.get_or_add_trPr().append(repeat)
    for row in rows:
        cells=t.add_row().cells
        for c_,value,width in zip(cells,row,widths):c_.text=str(value);c_.width=Cm(width)
    pr=t._tbl.tblPr;borders=OxmlElement('w:tblBorders')
    for side in ['top','left','bottom','right','insideH','insideV']:
        b_=OxmlElement('w:'+side);b_.set(qn('w:val'),'single');b_.set(qn('w:sz'),'4');b_.set(qn('w:color'),'D9D9D9');borders.append(b_)
    pr.append(borders)
    for j,row in enumerate(t.rows):
        no=OxmlElement('w:cantSplit');row._tr.get_or_add_trPr().append(no)
        for k,cell in enumerate(row.cells):
            cell.width=Cm(widths[k])
            cell.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
            shd=OxmlElement('w:shd');shd.set(qn('w:fill'),'DCEAF4' if j==0 else ('F5F8FA' if j%2==0 else 'FFFFFF'));cell._tc.get_or_add_tcPr().append(shd)
            margins=OxmlElement('w:tcMar')
            for side,val in [('top','70'),('bottom','70'),('left','95'),('right','95')]:
                x=OxmlElement('w:'+side);x.set(qn('w:w'),val);x.set(qn('w:type'),'dxa');margins.append(x)
            cell._tc.get_or_add_tcPr().append(margins)
            for paragraph in cell.paragraphs:
                paragraph.paragraph_format.space_after=Pt(0);paragraph.paragraph_format.line_spacing=1.06
                if k>0 and len(str(cell.text))<28:paragraph.alignment=WD_ALIGN_PARAGRAPH.CENTER
                for run in paragraph.runs:run.font.size=Pt(9);run.font.bold=j==0;run.font.color.rgb=RGBColor(0,0,0)
    doc.add_paragraph().paragraph_format.space_after=Pt(0)

plain=[title,'整理日期 2026年11月4日','']
htmlparts=['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+title+'</title><style>body{font-family:"Microsoft YaHei",sans-serif;line-height:1.85;margin:0;color:#172331;background:#f2f4f6}main{max-width:1160px;background:white;margin:25px auto;padding:40px}h1,h2,h3{color:black}h2{margin-top:42px;border-top:1px solid #ddd;padding-top:24px}table{border-collapse:collapse;width:100%;font-size:14px;margin:20px 0}td,th{border:1px solid #d9d9d9;padding:10px;text-align:left}th{background:#dceaf4}tr:nth-child(even){background:#f5f8fa}img{max-width:100%;height:auto}figcaption{font-size:13px;color:#526172}pre{white-space:pre-wrap}section{margin-bottom:25px}</style><main><h1>'+title+'</h1><p>整理日期 2026年11月4日</p>']
for i,pag in enumerate(pages):
    if i:
        q=doc.add_heading(str(i+1)+' '+pag['title'],1);q.paragraph_format.page_break_before=True
    else:
        doc.add_paragraph(title,'Title');doc.add_paragraph('上次130MHz实板版本  中文注释源码与可追溯性能证据','Subtitle')
        doc.add_paragraph('整理日期 2026年11月4日')
    plain+=['',f'{i+1} {pag["title"]}','']
    htmlparts.append('<section><h2>'+html.escape(f'{i+1} {pag["title"]}')+'</h2>')
    for block in pag['blocks']:
        kind=block['kind']
        if kind in ['p','h','code']:
            text=block['text'];plain.append(text)
            if kind=='p':doc.add_paragraph(text);htmlparts.append('<p>'+html.escape(text)+'</p>')
            elif kind=='h':doc.add_heading(text,2);htmlparts.append('<h3>'+html.escape(text)+'</h3>')
            else:
                q=doc.add_paragraph();rr=q.add_run(text);rr.font.name='Consolas';rr.font.size=Pt(8.5);htmlparts.append('<pre>'+html.escape(text)+'</pre>')
        elif kind=='table':
            add_table(block);plain.append(' | '.join(map(str,block['headers'])));plain+=[' | '.join(map(str,row)) for row in block['rows']]
            htmlparts.append('<table><tr>'+''.join('<th>'+html.escape(str(h_))+'</th>' for h_ in block['headers'])+'</tr>'+''.join('<tr>'+''.join('<td>'+html.escape(str(v))+'</td>' for v in row)+'</tr>' for row in block['rows'])+'</table>')
        elif kind=='image':
            q=doc.add_paragraph();q.alignment=WD_ALIGN_PARAGRAPH.CENTER;q.paragraph_format.keep_with_next=True
            q.add_run().add_picture(str(r/'docs'/block['path']),width=Cm(block['width']))
            # Preserve an accessible alternative description in DrawingML.
            pics=q._p.xpath('.//wp:docPr')
            if pics:pics[0].set('descr',block['caption'])
            doc.add_paragraph(block['caption'],'Caption');plain.append(block['caption'])
            htmlparts.append('<figure><img src="'+block['path']+'" alt="'+html.escape(block['caption'])+'"><figcaption>'+html.escape(block['caption'])+'</figcaption></figure>')
    htmlparts.append('</section>')
htmlparts.append('</main></html>')
doc.core_properties.title=title;doc.core_properties.subject='最后实际上板130MHz版本的架构与CoreMark流水线分析';doc.core_properties.author='RV32 项目源码整理'
for border in list(doc.element.iter(qn('w:pBdr'))):border.getparent().remove(border)
doc.save(r/'docs/RV32_CPU架构与CoreMark性能分析.docx')
(r/'docs/RV32_CPU架构与CoreMark性能分析.html').write_text(''.join(htmlparts),encoding='utf-8')
(r/'docs/RV32_CPU架构与CoreMark性能分析.txt').write_text('\n'.join(plain)+'\n',encoding='utf-8-sig')
print('DOCX content sections:',len(pages))
