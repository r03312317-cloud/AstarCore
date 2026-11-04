// CM120 AUDIT R1: cached-local tournament; five-bit training history.
// Queries read only the local direction bit; local history/PHT train off-path.
// Board B9/G12/H12 uses 256 H5 local rows, GShare4096 and Chooser512. Query cache index/ports are unchanged from TOPT7.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 组合查询与提交训练分离的局部方向和 GShare 混合预测器。
// 本板 B9/G12/H12 对应 512 项 chooser、4096 项 GShare 及 12 位历史。
// 局部方向启用时使用 256 行 H5 历史加模式状态，查询只读取已缓存方向位。
// 四个 PC 查询口服务相邻取指及后续预测提案，不表示 CPU 每拍发射四条。
// 预测时上下文保存历史和两种分量结果，提交训练不重新猜测原来用了哪行。
// 训练 FIFO 接收最多两条、逐条消化；训练信用不足会经 train_ready 背压提交。
// 初始化扫表完成前不能开始正常取指，避免未初始化 RAM 成为有效预测状态。
// 此模块只决定预测，不改变 RISC-V 指令语义；预测错误由 ROB 提交恢复纠正。
// 接口契约与阅读示例
// 查询时PC索引与当前投机历史异或，得到GShare行。
// context保存当时历史、局部方向与GShare方向，供分支最终提交时比较两分量。
// chooser只在两种分量意见不同的情况下有必要调整偏好。
// 训练FIFO把最多两个同拍提交转换为单表写口的逐条更新，减少预测RAM多写口成本。
// train_ready预留两项信用；临界容量时宁可暂缓条件分支提交，也不能丢训练记录。
// 训练头缓存让当前写包无需再经过FIFO深读选择，局部状态预取处理下一包。
// 已提交ghr按lane0再lane1扩展，双提交的两次历史事件顺序不能颠倒。
// 初始化扫到最大表最后一行才解除initializing，
// 查询期间的未清扫值不会被当正常方向。
// 方向表计数并不是程序分支计数器，饱和值与真实miss总数不能混用。
// 本板报告中的branch miss事件来自核心提交恢复判定，不是由chooser状态估算。
module rv32_hybrid_predictor #(
    // 参数 BIMODAL_INDEX_BITS：chooser和相关PC索引宽度；本板B9，
    // 局部方向启用后不应把表统称bimodal。
 parameter BIMODAL_INDEX_BITS=7,
    // 参数 GSHARE_INDEX_BITS：GShare方向表索引位数；本板G12对应4096个计数器。
 parameter GSHARE_INDEX_BITS=8,
    // 参数 HISTORY_BITS：预测历史位宽；本板H12，
    // 历史随预测和提交各有受控上下文。
 parameter HISTORY_BITS=8,
    // 参数 ENABLE_LOCAL_DIRECTION：本板启用局部方向分量替代兼容bimodal查询，
    // GShare与chooser继续存在。
 parameter ENABLE_LOCAL_DIRECTION=1,
    // 参数 LOCAL_HISTORY_BITS：每个局部分支保留的历史位，本板5位，
    // 模式计数器数量为2的该次方。
 parameter LOCAL_HISTORY_BITS=5,
    // 参数 LOCAL_INDEX_BITS：局部方向训练行索引，本板8位对应256行。
 parameter LOCAL_INDEX_BITS=(BIMODAL_INDEX_BITS>2?BIMODAL_INDEX_BITS-1:BIMODAL_INDEX_BITS)
)(
    // 接口字段：input clk,reset。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
 input clk,reset,
    // 接口字段：input [31:0] pc0,pc1,pc2,pc3。
    // 控制流地址或恢复信息。顺序地址、预测地址和实际恢复地址具有不同来源，
    // 不能互换。
 input [31:0] pc0,pc1,pc2,pc3,
    // 接口字段：input [HISTORY_BITS-1:0] query_history。
    // 预测与恢复上下文。保存预测时信息，恢复和训练必须使用对应指令所有者。
 input [HISTORY_BITS-1:0] query_history,
    // 接口字段：output taken0,taken1,taken2,taken3。
    // 组合查询与提交训练分离的局部方向和 GShare 混合预测器。
 output taken0,taken1,taken2,taken3,
    // 接口字段：output [HISTORY_BITS+1:0] context0,context1,context2,context3。
    // 预测与恢复上下文。保存预测时信息，恢复和训练必须使用对应指令所有者。
 output [HISTORY_BITS+1:0] context0,context1,context2,context3,
    // 接口字段：input train0,train1。
    // 按提交顺序的预测训练或其信用。只采纳有资格的已提交控制流，
    // 不把推测执行当训练完成。
 input train0,train1,
    // 接口字段：input [31:0] train_pc0,train_pc1。
    // 按提交顺序的预测训练或其信用。只采纳有资格的已提交控制流，
    // 不把推测执行当训练完成。
 input [31:0] train_pc0,train_pc1,
    // 接口字段：input [HISTORY_BITS+1:0] train_context0,train_context1。
    // 按提交顺序的预测训练或其信用。只采纳有资格的已提交控制流，
    // 不把推测执行当训练完成。
 input [HISTORY_BITS+1:0] train_context0,train_context1,
    // 接口字段：input train_taken0,train_taken1。
    // 按提交顺序的预测训练或其信用。只采纳有资格的已提交控制流，
    // 不把推测执行当训练完成。
 input train_taken0,train_taken1,
    // 接口字段：input train_history_taken0,train_history_taken1。
    // 按提交顺序的预测训练或其信用。只采纳有资格的已提交控制流，
    // 不把推测执行当训练完成。
 input train_history_taken0,train_history_taken1,
    // 接口字段：output [HISTORY_BITS-1:0] committed_history。
    // 预测与恢复上下文。保存预测时信息，恢复和训练必须使用对应指令所有者。
 output [HISTORY_BITS-1:0] committed_history,
    // 接口字段：output initialized,train_ready。
    // 按提交顺序的预测训练或其信用。只采纳有资格的已提交控制流，
    // 不把推测执行当训练完成。
 output initialized,train_ready
);
 localparam INITIALIZE_BITS=BIMODAL_INDEX_BITS>GSHARE_INDEX_BITS?BIMODAL_INDEX_BITS:GSHARE_INDEX_BITS;
 localparam PACKET_BITS=BIMODAL_INDEX_BITS+GSHARE_INDEX_BITS+3;
 reg [HISTORY_BITS-1:0] ghr;
 reg [INITIALIZE_BITS-1:0] initialize_index;
 reg initializing;
 reg [2:0] training_head,training_tail;
 reg [3:0] training_count;
 (* syn_ramstyle="distributed_ram" *) reg [PACKET_BITS-1:0] tq_even[0:3],tq_odd[0:3];
 reg [PACKET_BITS-1:0] training_packet /* synthesis syn_maxfan = 32 */;
    // 函数 read_training：读取奇偶训练FIFO保存的分支更新包，
    // 包中索引来自预测时上下文。
    // 调用字段：input [2:0] index。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
 function [PACKET_BITS-1:0] read_training;
  input [2:0] index;
  begin read_training=index[0]?tq_odd[index[2:1]]:tq_even[index[2:1]];end
 endfunction
 assign initialized=!initializing;
 assign train_ready=!reset&&!initializing&&training_count<=6;
 wire accept0=train0&&train_ready,accept1=train1&&train_ready;
 wire [1:0] push_count={1'b0,accept0}+{1'b0,accept1};
 wire pop=!initializing&&training_count!=0;
 wire [2:0] tail1=training_tail+3'd1,head1=training_head+3'd1;
 // Prediction-time history is zero-extended, not widened or recomputed at retirement.
    // 函数 extend_history：把有效历史位零扩展到GShare索引宽度，
    // 保持预测与训练使用同一索引规则。
    // 调用字段：input [HISTORY_BITS-1:0] history。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
 function [GSHARE_INDEX_BITS-1:0] extend_history;
  input [HISTORY_BITS-1:0] history;
  integer bit_index;
  begin
   extend_history=0;
   for(bit_index=0;bit_index<HISTORY_BITS&&bit_index<GSHARE_INDEX_BITS;bit_index=bit_index+1)
    extend_history[bit_index]=history[bit_index];
  end
 endfunction
 wire [PACKET_BITS-1:0] packet0={train_pc0[BIMODAL_INDEX_BITS+1:2],(train_pc0[GSHARE_INDEX_BITS+1:2]^extend_history(train_context0[HISTORY_BITS+1:2])),train_taken0,
  (train_context0[1]^train_context0[0]),(train_context0[0]==train_taken0)};
 wire [PACKET_BITS-1:0] packet1={train_pc1[BIMODAL_INDEX_BITS+1:2],(train_pc1[GSHARE_INDEX_BITS+1:2]^extend_history(train_context1[HISTORY_BITS+1:2])),train_taken1,
  (train_context1[1]^train_context1[0]),(train_context1[0]==train_taken1)};
 wire [PACKET_BITS-1:0] first_packet=accept0?packet0:packet1;
 // Fetch the next local state when the existing FIFO head cache changes.
 // Training/query visibility stays on the original edge; no extra queue stage.
 wire local_prefetch=(pop&&training_count>1)||
     (push_count!=0&&(training_count==0||(pop&&training_count==1)));
 wire [PACKET_BITS-1:0] local_prefetch_packet=(pop&&training_count>1)?read_training(head1):first_packet;
 // Data RAM payloads have no reset. A full largest-table initialization sweep resets
 // every counter before the frontend can issue its first fetch request.
 always @(posedge clk)begin
  if(reset)begin
   initializing<=1;initialize_index<=0;ghr<=0;
   training_head<=0;training_tail<=0;training_count<=0;training_packet<=0;
  end else begin
   if(initializing)begin
    if(&initialize_index)initializing<=0;
    else initialize_index<=initialize_index+1'b1;
   end
   if(accept1)ghr<=accept0?{ghr[HISTORY_BITS-3:0],train_history_taken0,train_history_taken1}:{ghr[HISTORY_BITS-2:0],train_history_taken1};
   else if(accept0)ghr<={ghr[HISTORY_BITS-2:0],train_history_taken0};
   training_count<=training_count+{2'b0,push_count}-{3'b0,pop};
   if(push_count!=0)training_tail<=training_tail+{1'b0,push_count};
   if(pop)training_head<=head1;
   if(pop&&training_count>1)training_packet<=read_training(head1);
   else if(push_count!=0&&(training_count==0||(pop&&training_count==1)))training_packet<=first_packet;
  end
 end
 always @(posedge clk)if(!reset)begin
  if(push_count!=0&&(!training_tail[0]||push_count==2))
   tq_even[training_tail[0]?tail1[2:1]:training_tail[2:1]]<=training_tail[0]?packet1:first_packet;
  if(push_count!=0&&(training_tail[0]||push_count==2))
   tq_odd[training_tail[0]?training_tail[2:1]:tail1[2:1]]<=training_tail[0]?first_packet:packet1;
 end
 assign committed_history=ghr;
 wire [1:0] b0,b1,b2,b3,g0,g1,g2,g3,c0,c1,c2,c3;
 // LOCAL_COMPONENT_SELECT_BEGIN
 generate if(ENABLE_LOCAL_DIRECTION)begin:local_component
  wire local0,local1,local2,local3;
  rv32_local_direction_cache #(.INDEX_BITS(LOCAL_INDEX_BITS),
   .LOCAL_HISTORY_BITS(LOCAL_HISTORY_BITS),.INITIALIZE_BITS(INITIALIZE_BITS)) local_direction(
   .clk(clk),.reset(reset),.initializing(initializing),.initialize_index(initialize_index),
   .read0(pc0[LOCAL_INDEX_BITS+1:2]),.read1(pc1[LOCAL_INDEX_BITS+1:2]),
   .read2(pc2[LOCAL_INDEX_BITS+1:2]),.read3(pc3[LOCAL_INDEX_BITS+1:2]),
   .value0(local0),.value1(local1),.value2(local2),.value3(local3),
   .prefetch(local_prefetch),.prefetch_index(local_prefetch_packet[GSHARE_INDEX_BITS+3+:LOCAL_INDEX_BITS]),
   .write(pop),.index(training_packet[GSHARE_INDEX_BITS+3+:LOCAL_INDEX_BITS]),.up(training_packet[2]));
  assign b0={local0,1'b0};assign b1={local1,1'b0};
  assign b2={local2,1'b0};assign b3={local3,1'b0};
 end else begin:bimodal_component
 rv32_predictor_counters #(.INDEX_BITS(BIMODAL_INDEX_BITS),.INITIALIZE_BITS(INITIALIZE_BITS)) bimodal(
  .clk(clk),.reset(reset),.initializing(initializing),.initialize_index(initialize_index),
  .read0(pc0[BIMODAL_INDEX_BITS+1:2]),.read1(pc1[BIMODAL_INDEX_BITS+1:2]),.read2(pc2[BIMODAL_INDEX_BITS+1:2]),.read3(pc3[BIMODAL_INDEX_BITS+1:2]),
  .value0(b0),.value1(b1),.value2(b2),.value3(b3),
  .write(pop),.index(training_packet[PACKET_BITS-1:GSHARE_INDEX_BITS+3]),.up(training_packet[2]));
 end endgenerate
 // LOCAL_COMPONENT_SELECT_END
 rv32_predictor_counters #(.INDEX_BITS(GSHARE_INDEX_BITS),.INITIALIZE_BITS(INITIALIZE_BITS)) gshare(
  .clk(clk),.reset(reset),.initializing(initializing),.initialize_index(initialize_index),
  .read0(pc0[GSHARE_INDEX_BITS+1:2]^extend_history(query_history)),.read1(pc1[GSHARE_INDEX_BITS+1:2]^extend_history(query_history)),.read2(pc2[GSHARE_INDEX_BITS+1:2]^extend_history(query_history)),.read3(pc3[GSHARE_INDEX_BITS+1:2]^extend_history(query_history)),
  .value0(g0),.value1(g1),.value2(g2),.value3(g3),
  .write(pop),.index(training_packet[GSHARE_INDEX_BITS+2:3]),.up(training_packet[2]));
 rv32_predictor_counters #(.INDEX_BITS(BIMODAL_INDEX_BITS),.INITIALIZE_BITS(INITIALIZE_BITS)) chooser(
  .clk(clk),.reset(reset),.initializing(initializing),.initialize_index(initialize_index),
  .read0(pc0[BIMODAL_INDEX_BITS+1:2]),.read1(pc1[BIMODAL_INDEX_BITS+1:2]),.read2(pc2[BIMODAL_INDEX_BITS+1:2]),.read3(pc3[BIMODAL_INDEX_BITS+1:2]),
  .value0(c0),.value1(c1),.value2(c2),.value3(c3),
  .write(pop&&training_packet[1]),.index(training_packet[PACKET_BITS-1:GSHARE_INDEX_BITS+3]),.up(training_packet[0]));
 assign taken0=c0[1]?g0[1]:b0[1];assign taken1=c1[1]?g1[1]:b1[1];
 assign taken2=c2[1]?g2[1]:b2[1];assign taken3=c3[1]?g3[1]:b3[1];
 assign context0={query_history,b0[1],g0[1]};assign context1={query_history,b1[1],g1[1]};
 assign context2={query_history,b2[1],g2[1]};assign context3={query_history,b3[1],g3[1]};
`ifdef VERILATOR
 initial begin
  if(BIMODAL_INDEX_BITS<2||BIMODAL_INDEX_BITS>30||GSHARE_INDEX_BITS<8||GSHARE_INDEX_BITS>30||HISTORY_BITS<2||HISTORY_BITS>GSHARE_INDEX_BITS)
   $fatal(1,"Predictor index widths must satisfy B/C=2..30 and GShare=8..30");
  if(ENABLE_LOCAL_DIRECTION&&(LOCAL_INDEX_BITS<2||LOCAL_INDEX_BITS>BIMODAL_INDEX_BITS||
     LOCAL_HISTORY_BITS<1||LOCAL_HISTORY_BITS>6))
   $fatal(1,"TOPT7 local table must fit the existing training index and initialization sweep");
 end
 always @(posedge clk)if(!reset)begin
  if((train0||train1)&&!train_ready)$fatal(1,"R48 conditional training offered without two queue credits");
  if(training_count>7)$fatal(1,"R48 training queue overflow");
  if(training_count!=0&&training_packet!=read_training(training_head))$fatal(1,"R48 training head cache differs from FIFO owner");
 end
`endif
endmodule

// Single writer per logical table; two paired parity reads plus one training
// read. Reset is performed by the top-level sweep, never by per-row FFs.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 两位饱和计数器 RAM，作为 GShare、chooser 或兼容 bimodal 的物理表。
// even/odd 银行支持两对奇偶相反的查询，调用者必须满足成对奇偶契约。
// 最高位作为方向，up 使状态向 3 饱和，不 up 时向 0 饱和。
// 初始化由上层扫表驱动，不对每个 RAM 字施加复位以保留分布式 RAM 推断。
// 正常训练每拍至多写一行，不承担训练 FIFO 的所有权管理。
// 读出的方向只是预测值，不能被解释为实际分支是否跳转。
// 接口契约与阅读示例
// 饱和例子  3继续向上仍为3，0继续向下仍为0。
// 索引最低位选even/odd银行，其余位选银行内行号。
// read0/read1和read2/read3分别需要奇偶相反，才能每对共用一次各银行读取。
// 小表只在initialize_index高出本表范围的位仍为0时写初始化值，避免重复清扫。
// 初始化结束后的第一笔训练才采用正常index和up。
// 预测查询不消耗或删除表项，训练才会改变后续查询方向。
module rv32_predictor_counters #(
    // 参数 INDEX_BITS：当前表的索引宽度，表项数量为2的该次方。
 parameter INDEX_BITS=7,
    // 参数 INITIALIZE_BITS：按最大方向表深度进行初始化扫表，较小表只清扫一次。
 parameter INITIALIZE_BITS=INDEX_BITS
)(
    // 接口字段：input clk,reset,initializing。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
 input clk,reset,initializing,
    // 接口字段：input [INITIALIZE_BITS-1:0] initialize_index。
    // 两位饱和计数器 RAM，作为 GShare、chooser 或兼容 bimodal 的物理表。
 input [INITIALIZE_BITS-1:0] initialize_index,
    // 接口字段：input [INDEX_BITS-1:0] read0,read1,read2,read3。
    // 两位饱和计数器 RAM，作为 GShare、chooser 或兼容 bimodal 的物理表。
 input [INDEX_BITS-1:0] read0,read1,read2,read3,
    // 接口字段：output [1:0] value0,value1,value2,value3。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
 output [1:0] value0,value1,value2,value3,
    // 接口字段：input write。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
 input write,
    // 接口字段：input [INDEX_BITS-1:0] index。
    // 两位饱和计数器 RAM，作为 GShare、chooser 或兼容 bimodal 的物理表。
 input [INDEX_BITS-1:0] index,
    // 接口字段：input up。
    // 两位饱和计数器 RAM，作为 GShare、chooser 或兼容 bimodal 的物理表。
 input up
);
 localparam ENTRIES=1<<INDEX_BITS;
 (* syn_ramstyle="distributed_ram" *) reg [1:0] even_rows[0:ENTRIES/2-1],odd_rows[0:ENTRIES/2-1];
    // 函数 read_counter：读取指定方向计数器；初始化期间统一返回弱不跳转，
    // 避免暴露未清扫的RAM值。
    // 调用字段：input [INDEX_BITS-1:0] position。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
 function [1:0] read_counter;
  input [INDEX_BITS-1:0] position;
  begin read_counter=initializing?2'b01:(position[0]?odd_rows[position[INDEX_BITS-1:1]]:even_rows[position[INDEX_BITS-1:1]]);end
 endfunction
    // 函数 saturate：对2位预测计数器作向上或向下饱和更新，
    // 不允许算术回绕颠倒预测方向。
    // 调用字段：input [1:0] old_value；input increment。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
 function [1:0] saturate;
  input [1:0] old_value;
  input increment;
  begin
   if(increment)saturate=old_value==3?2'd3:old_value+2'd1;
   else saturate=old_value==0?2'd0:old_value-2'd1;
  end
 endfunction
 // Smaller tables clear once, rather than wrapping while the largest table clears.
 wire clearing=initializing&&((initialize_index>>INDEX_BITS)==0);
 wire write_enable=!reset&&(clearing||(!initializing&&write));
 wire [INDEX_BITS-1:0] address=initializing?initialize_index[INDEX_BITS-1:0]:index;
 wire [1:0] updated=initializing?2'b01:saturate(read_counter(index),up);
 always @(posedge clk)begin
  if(write_enable&&!address[0])even_rows[address[INDEX_BITS-1:1]]<=updated;
  if(write_enable&&address[0])odd_rows[address[INDEX_BITS-1:1]]<=updated;
 end
 wire [INDEX_BITS-2:0] ei0=read0[0]?read1[INDEX_BITS-1:1]:read0[INDEX_BITS-1:1];
 wire [INDEX_BITS-2:0] oi0=read0[0]?read0[INDEX_BITS-1:1]:read1[INDEX_BITS-1:1];
 wire [INDEX_BITS-2:0] ei1=read2[0]?read3[INDEX_BITS-1:1]:read2[INDEX_BITS-1:1];
 wire [INDEX_BITS-2:0] oi1=read2[0]?read2[INDEX_BITS-1:1]:read3[INDEX_BITS-1:1];
 wire [1:0] e0=even_rows[ei0],o0=odd_rows[oi0],e1=even_rows[ei1],o1=odd_rows[oi1];
 assign value0=initializing?2'b01:(read0[0]?o0:e0);
 assign value1=initializing?2'b01:(read1[0]?o0:e0);
 assign value2=initializing?2'b01:(read2[0]?o1:e1);
 assign value3=initializing?2'b01:(read3[0]?o1:e1);
`ifdef VERILATOR
 always @(posedge clk)if(!reset&&(read0[0]==read1[0]||read2[0]==read3[0]))$fatal(1,"R48 query parity contract violated");
`endif
endmodule

// ROUND7 local direction component. Only the independent cached direction RAM
// serves queries. History and pattern counters are read only by the one-at-a-time
// committed training stream; no history -> pattern RAM chain exists at query.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 局部方向分量，把训练用历史与模式表移出取指查询关键路径。
// 每行训练状态含 LOCAL_HISTORY_BITS 位历史及每个历史模式的两位计数器。
// 查询只看独立的方向缓存 even_rows/odd_rows，避免连续历史 RAM 到模式 RAM
// 的读链。
// 训练 FIFO 头变化时预取下一行状态，命中当前写行时做写前递。
// 训练更新模式计数与局部历史后，缓存下一次预测需要的方向。
// 初始化和有效查询的边界由上层控制，预取不是一次分支提交。
// 保留原有成对奇偶查询拓扑，本板局部行数为 256、历史长度为 5。
// 接口契约与阅读示例
// 查询方向缓存保存的是当前行历史对应的预测结果，不是整个模式表。
// 一次真实提交先使用旧历史选择模式计数器，再按实际方向更新历史。
// 后续缓存方向必须与更新后的历史对应，避免把训练前方向误留给下一次查询。
// 相邻训练包访问同一行时，需要前一写结果到下一预取的旁路。
// 预取只准备训练payload，不等于已经对下一分支执行了训练写入。
// 局部历史和模式状态在训练端可以较宽，查询只取方向位以缩短取指路径。
// 参考断言对照完整状态计算，检查缓存位没有因同址写读而偏离。
module rv32_local_direction_cache #(
    // 参数 INDEX_BITS：当前表的索引宽度，表项数量为2的该次方。
 parameter INDEX_BITS=8,
    // 参数 LOCAL_HISTORY_BITS：每个局部分支保留的历史位，本板5位，
    // 模式计数器数量为2的该次方。
 parameter LOCAL_HISTORY_BITS=5,
    // 参数 INITIALIZE_BITS：按最大方向表深度进行初始化扫表，较小表只清扫一次。
 parameter INITIALIZE_BITS=12
)(
    // 接口字段：input clk,reset,initializing。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
 input clk,reset,initializing,
    // 接口字段：input [INITIALIZE_BITS-1:0] initialize_index。
    // 局部方向分量，把训练用历史与模式表移出取指查询关键路径。
 input [INITIALIZE_BITS-1:0] initialize_index,
    // 接口字段：input [INDEX_BITS-1:0] read0,read1,read2,read3。
    // 局部方向分量，把训练用历史与模式表移出取指查询关键路径。
 input [INDEX_BITS-1:0] read0,read1,read2,read3,
    // 接口字段：output value0,value1,value2,value3。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
 output value0,value1,value2,value3,
    // 接口字段：input write,prefetch。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
 input write,prefetch,
    // 接口字段：input [INDEX_BITS-1:0] prefetch_index。
    // 局部方向分量，把训练用历史与模式表移出取指查询关键路径。
 input [INDEX_BITS-1:0] prefetch_index,
    // 接口字段：input [INDEX_BITS-1:0] index。
    // 局部方向分量，把训练用历史与模式表移出取指查询关键路径。
 input [INDEX_BITS-1:0] index,
    // 接口字段：input up。
    // 局部方向分量，把训练用历史与模式表移出取指查询关键路径。
 input up
);
 localparam ENTRIES=1<<INDEX_BITS;
 localparam PATTERNS=1<<LOCAL_HISTORY_BITS;
 localparam PATTERN_BITS=2*PATTERNS;
 localparam STATE_BITS=LOCAL_HISTORY_BITS+PATTERN_BITS;
 // One look-ahead read port and one current-owner write port. A matching
 // current write bypasses the look-ahead RAM read at the capture edge.
 (* syn_ramstyle="distributed_ram" *) reg [STATE_BITS-1:0] training_rows[0:ENTRIES-1];
 // Exactly the original paired parity query topology, but only one bit per row.
 (* syn_ramstyle="distributed_ram" *) reg even_rows[0:ENTRIES/2-1],odd_rows[0:ENTRIES/2-1];
 reg [STATE_BITS-1:0] training_state;
 // LOCAL_DIRECTION_STEP_BEGIN
    // 函数 saturate_local：更新局部分支的模式计数器，饱和范围0至3，
    // 配合该行局部历史。
    // 调用字段：input [1:0] old_value；input increment。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
 function [1:0] saturate_local;
  input [1:0] old_value;
  input increment;
  begin
   if(increment)saturate_local=old_value==3?2'd3:old_value+2'd1;
   else saturate_local=old_value==0?2'd0:old_value-2'd1;
  end
 endfunction
 wire [LOCAL_HISTORY_BITS-1:0] old_history=training_state[STATE_BITS-1:PATTERN_BITS];
 wire [PATTERN_BITS-1:0] old_counters=training_state[PATTERN_BITS-1:0];
 wire [1:0] old_counter=old_counters[{old_history,1'b0}+:2];
 wire [1:0] updated_counter=saturate_local(old_counter,up);
 wire [LOCAL_HISTORY_BITS:0] shifted_history={old_history,up};
 wire [LOCAL_HISTORY_BITS-1:0] next_history=shifted_history[LOCAL_HISTORY_BITS-1:0];
 reg [PATTERN_BITS-1:0] next_counters;
 always @*begin
  next_counters=old_counters;
  next_counters[{old_history,1'b0}+:2]=updated_counter;
 end
 // Select from the old vector unless the next history selects the one counter
 // just updated. This avoids a wide modify-vector -> select-vector chain.
 wire next_direction=(next_history==old_history)?updated_counter[1]:
                     old_counters[{next_history,1'b1}];
 // Smaller tables clear once during the existing largest-table sweep.
 wire clearing=initializing&&((initialize_index>>INDEX_BITS)==0);
 wire write_enable=!reset&&(clearing||(!initializing&&write));
 wire [INDEX_BITS-1:0] address=initializing?initialize_index[INDEX_BITS-1:0]:index;
 wire [STATE_BITS-1:0] updated_state=initializing?
     {{LOCAL_HISTORY_BITS{1'b0}},{PATTERNS{2'b01}}}:{next_history,next_counters};
 wire updated_direction=initializing?1'b0:next_direction;
 // LOCAL_DIRECTION_STEP_END
 // LOCAL_DIRECTION_CAPTURE_BEGIN
 // The pending owner sees the completed write when consecutive packets alias.
 // Otherwise capture its row directly, in parallel with the FIFO head payload.
 always @(posedge clk)begin
  if(reset)training_state<={{LOCAL_HISTORY_BITS{1'b0}},{PATTERNS{2'b01}}};
  else if(prefetch)training_state<=(write_enable&&address==prefetch_index)?
       updated_state:training_rows[prefetch_index];
 end
 always @(posedge clk)begin
  if(write_enable)begin
   training_rows[address]<=updated_state;
   if(!address[0])even_rows[address[INDEX_BITS-1:1]]<=updated_direction;
   if(address[0])odd_rows[address[INDEX_BITS-1:1]]<=updated_direction;
  end
 end
 // LOCAL_DIRECTION_CAPTURE_END
 // LOCAL_DIRECTION_QUERY_BEGIN
 wire [INDEX_BITS-2:0] ei0=read0[0]?read1[INDEX_BITS-1:1]:read0[INDEX_BITS-1:1];
 wire [INDEX_BITS-2:0] oi0=read0[0]?read0[INDEX_BITS-1:1]:read1[INDEX_BITS-1:1];
 wire [INDEX_BITS-2:0] ei1=read2[0]?read3[INDEX_BITS-1:1]:read2[INDEX_BITS-1:1];
 wire [INDEX_BITS-2:0] oi1=read2[0]?read2[INDEX_BITS-1:1]:read3[INDEX_BITS-1:1];
 wire e0=even_rows[ei0],o0=odd_rows[oi0],e1=even_rows[ei1],o1=odd_rows[oi1];
 assign value0=initializing?1'b0:(read0[0]?o0:e0);
 assign value1=initializing?1'b0:(read1[0]?o0:e0);
 assign value2=initializing?1'b0:(read2[0]?o1:e1);
 assign value3=initializing?1'b0:(read3[0]?o1:e1);
 // LOCAL_DIRECTION_QUERY_END
`ifdef VERILATOR
 // Simulation-only extra reads check the cached bit against the actual local
 // history/PHT owner. They do not create hardware state or RAM read ports.
    // 函数 reference_direction：仿真参考从完整局部历史/模式状态计算方向，
    // 用来核对缓存方向位。
    // 调用字段：input [INDEX_BITS-1:0] position。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
 function reference_direction;
  input [INDEX_BITS-1:0] position;
  reg [STATE_BITS-1:0] state_value;
  reg [PATTERN_BITS-1:0] counters_value;
  reg [LOCAL_HISTORY_BITS-1:0] history_value;
  begin
   state_value=training_rows[position];
   counters_value=state_value[PATTERN_BITS-1:0];
   history_value=state_value[STATE_BITS-1:PATTERN_BITS];
   reference_direction=counters_value[{history_value,1'b1}];
  end
 endfunction
 initial begin
  if(INDEX_BITS<2||INDEX_BITS>INITIALIZE_BITS||LOCAL_HISTORY_BITS<1||LOCAL_HISTORY_BITS>6)
   $fatal(1,"TOPT7 local direction widths outside supported range");
 end
 always @(posedge clk)if(!reset)begin
  if(read0[0]==read1[0]||read2[0]==read3[0])
   $fatal(1,"TOPT7 local direction query parity contract violated");
  if(!initializing)begin
   if(write&&training_state!=training_rows[index])
    $fatal(1,"R8 local prefetched state differs from current training owner");
   if(value0!=reference_direction(read0)||value1!=reference_direction(read1)||
      value2!=reference_direction(read2)||value3!=reference_direction(read3))
    $fatal(1,"TOPT7 local direction cache differs from history/pattern state");
   if(write&&next_direction!=next_counters[{next_history,1'b1}])
    $fatal(1,"TOPT7 local direction next-cache select differs from updated state");
   if(write&&(index[0]?odd_rows[index[INDEX_BITS-1:1]]:even_rows[index[INDEX_BITS-1:1]])!=
      reference_direction(index))
    $fatal(1,"TOPT7 local direction training owner cache mismatch");
  end
 end
`endif
endmodule
