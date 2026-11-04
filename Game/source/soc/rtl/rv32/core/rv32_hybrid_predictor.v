// [ARCH] 方向预测组合局部方向、GShare 和选择器，查询与训练具有不同的时序路径。
// [ARCH] 游戏实例使用 B9/G12/H12，局部历史 H5、局部索引 I8。
// [ARCH] 预测上下文包含查询时历史和分量方向，退休按该上下文定位训练表项。
// [ARCH] train_ready 限定训练接纳，双训练事件按旧指令到新指令的顺序进入。
// [ARCH] 局部方向缓存让快速查询不必串过完整的历史/PHT 更新路径。
// [ARCH] 初始化扫描结束前 initialized 为低，不能读取未初始化计数器。
// [ARCH] 饱和计数器的方向位与置信程度含义不同。
// [ARCH] 不能在退休时以最新 GHR 重算原来的预测索引。
// [ARCH] 错误预测必须由核心恢复，预测器本身不提交架构状态。
// CM120 AUDIT R1: cached-local tournament; five-bit training history.
// Queries read only the local direction bit; local history/PHT train off-path.
// Board B9/G12/H12 uses 256 H5 local rows, GShare4096 and Chooser512. Query cache index/ports are unchanged from TOPT7.
module rv32_hybrid_predictor #(
 // [ARCH] BIMODAL_INDEX_BITS：决定局部分量/选择器的索引宽度，游戏覆写为 9。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 LOCAL_INDEX_BITS, INITIALIZE_BITS, PACKET_BITS, packet0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter BIMODAL_INDEX_BITS=7,
 // [ARCH] GSHARE_INDEX_BITS：决定 GShare 表容量，游戏覆写为 12。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 INITIALIZE_BITS, PACKET_BITS, bit_index, packet0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter GSHARE_INDEX_BITS=8,
 // [ARCH] HISTORY_BITS：限定预测历史宽度，实例配置为 12；上下文需随指令保存。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 bit_index, packet0, packet1, ghr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter HISTORY_BITS=8,
 // [ARCH] ENABLE_LOCAL_DIRECTION：在局部方向缓存与独立双位计数分量之间选择实现。
 parameter ENABLE_LOCAL_DIRECTION=1,
 // [ARCH] LOCAL_HISTORY_BITS：决定每个局部历史记录的长度，本构建使用 H5。
 parameter LOCAL_HISTORY_BITS=5,
 // [ARCH] LOCAL_INDEX_BITS：决定局部方向表行数，当前 B9 集成推导为 I8。
 parameter LOCAL_INDEX_BITS=(BIMODAL_INDEX_BITS>2?BIMODAL_INDEX_BITS-1:BIMODAL_INDEX_BITS)
)(
 // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
 input clk,reset,
 // [ARCH] pc0：保存拥有者的原始 PC，用于恢复、异常或对应包的诊断。
 input [31:0] pc0,pc1,pc2,pc3,
 // [ARCH] query_history：保留预测相关历史，不能在退休时改用后来更新的历史。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 context0, context1, context2, context3 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input [HISTORY_BITS-1:0] query_history,
 output taken0,taken1,taken2,taken3,
 // [ARCH] context0：跟随预测或指令的上下文，使后续训练/恢复使用原来的索引事实。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 context1 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output [HISTORY_BITS+1:0] context0,context1,context2,context3,
 input train0,train1,
 // [ARCH] train_pc0（提交训练）：保存拥有者的原始 PC，用于恢复、异常或对应包的诊断。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 packet0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input [31:0] train_pc0,train_pc1,
 // [ARCH] train_context0（提交训练）：跟随预测或指令的上下文，使后续训练/恢复使用原来的索引事实。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 packet0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input [HISTORY_BITS+1:0] train_context0,train_context1,
 input train_taken0,train_taken1,
 // [ARCH] train_history_taken0（提交训练）：保留预测相关历史，不能在退休时改用后来更新的历史。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 ghr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input train_history_taken0,train_history_taken1,
 // [ARCH] committed_history：保留预测相关历史，不能在退休时改用后来更新的历史。
 output [HISTORY_BITS-1:0] committed_history,
 // [ARCH] initialized：初始化完成门控，防止把尚未设置的 RAM 内容当作有效状态。
 output initialized,train_ready
);
 localparam INITIALIZE_BITS=BIMODAL_INDEX_BITS>GSHARE_INDEX_BITS?BIMODAL_INDEX_BITS:GSHARE_INDEX_BITS;
 localparam PACKET_BITS=BIMODAL_INDEX_BITS+GSHARE_INDEX_BITS+3;
 reg [HISTORY_BITS-1:0] ghr;
 // [ARCH] initialize_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 initializing, ghr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 reg [INITIALIZE_BITS-1:0] initialize_index;
 // [ARCH] initializing：初始化扫描尚在进行，普通查询/接纳资格需按本模块门控。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 initialized, train_ready, training_count, pop 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 reg initializing;
 // [ARCH] training_head（预测训练路径）：指向当前最老有效项，消费顺序与环形编号回绕需要一起解释。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 tail1, head1, training_tail, training_count 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 reg [2:0] training_head,training_tail;
 // [ARCH] training_count（预测训练路径）：统计已接受的有效占用/事件；同时增减时要保留净变化。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 train_ready, pop, training_head, training_tail 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 reg [3:0] training_count;
 (* syn_ramstyle="distributed_ram" *) reg [PACKET_BITS-1:0] tq_even[0:3],tq_odd[0:3];
 reg [PACKET_BITS-1:0] training_packet;
 // [ARCH] 按训练队列索引选择奇偶银行中的原包。
 // [ARCH] 先前接受的上下文不能因当前预测历史变化而被覆盖。
 function [PACKET_BITS-1:0] read_training;
  // [ARCH] index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
  // [ARCH] 定位线索：原版中含此标识符的物理行还对 read_training 赋值；同一行可能含多个语句，不能据此单独推断依赖。
  input [2:0] index;
  begin read_training=index[0]?tq_odd[index[2:1]]:tq_even[index[2:1]];end
 endfunction
 assign initialized=!initializing;
 assign train_ready=!reset&&!initializing&&training_count<=6;
 wire accept0=train0&&train_ready,accept1=train1&&train_ready;
 // [ARCH] push_count：统计已接受的有效占用/事件；同时增减时要保留净变化。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 training_count, training_tail, training_packet 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [1:0] push_count={1'b0,accept0}+{1'b0,accept1};
 // [ARCH] pop：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 training_count, training_head, training_packet 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire pop=!initializing&&training_count!=0;
 // [ARCH] tail1：指向后续接纳位置，只有实际分配/入队才推进所有权。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 head1, tq_even, tq_odd 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [2:0] tail1=training_tail+3'd1,head1=training_head+3'd1;
 // Prediction-time history is zero-extended, not widened or recomputed at retirement.
 // [ARCH] 按目标索引宽度零扩展历史位。
 // [ARCH] 不能符号扩展，也不在这里重新计算已经保存的历史。
 function [GSHARE_INDEX_BITS-1:0] extend_history;
  // [ARCH] history：保留预测相关历史，不能在退休时改用后来更新的历史。
  // [ARCH] 定位线索：原版中含此标识符的物理行还对 extend_history 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
module rv32_predictor_counters #(
 // [ARCH] INDEX_BITS：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 INITIALIZE_BITS, ENTRIES, read_counter, clearing 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter INDEX_BITS=7,
 parameter INITIALIZE_BITS=INDEX_BITS
)(
 // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
 input clk,reset,initializing,
 // [ARCH] initialize_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 clearing, address 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input [INITIALIZE_BITS-1:0] initialize_index,
 input [INDEX_BITS-1:0] read0,read1,read2,read3,
 // [ARCH] value0：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
 output [1:0] value0,value1,value2,value3,
 input write,
 // [ARCH] index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 address, updated 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input [INDEX_BITS-1:0] index,
 input up
);
 localparam ENTRIES=1<<INDEX_BITS;
 (* syn_ramstyle="distributed_ram" *) reg [1:0] even_rows[0:ENTRIES/2-1],odd_rows[0:ENTRIES/2-1];
 // [ARCH] 从预测计数存储选择当前表项。
 // [ARCH] 初始化门控决定该项何时能被合法查询。
 function [1:0] read_counter;
  input [INDEX_BITS-1:0] position;
  begin read_counter=initializing?2'b01:(position[0]?odd_rows[position[INDEX_BITS-1:1]]:even_rows[position[INDEX_BITS-1:1]]);end
 endfunction
 // [ARCH] 方向计数更新在边界饱和，不做自然回绕。
 // [ARCH] 否则强预测会因一次更新跳到相反极端。
 function [1:0] saturate;
  // [ARCH] old_value：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
  // [ARCH] 定位线索：原版中含此标识符的物理行还对 saturate 赋值；同一行可能含多个语句，不能据此单独推断依赖。
  input [1:0] old_value;
  input increment;
  begin
   if(increment)saturate=old_value==3?2'd3:old_value+2'd1;
   else saturate=old_value==0?2'd0:old_value-2'd1;
  end
 endfunction
 // Smaller tables clear once, rather than wrapping while the largest table clears.
 wire clearing=initializing&&((initialize_index>>INDEX_BITS)==0);
 // [ARCH] write_enable：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 address 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire write_enable=!reset&&(clearing||(!initializing&&write));
 // [ARCH] address：保持当前事务地址，等待/背压期间不能换成下一请求的地址。
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
module rv32_local_direction_cache #(
 // [ARCH] INDEX_BITS：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 ENTRIES, clearing, address, ei0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter INDEX_BITS=8,
 // [ARCH] LOCAL_HISTORY_BITS：决定每个局部历史记录的长度，本构建使用 H5。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 PATTERNS, STATE_BITS, old_history, shifted_history 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter LOCAL_HISTORY_BITS=5,
 parameter INITIALIZE_BITS=12
)(
 // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
 input clk,reset,initializing,
 // [ARCH] initialize_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 clearing, address 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input [INITIALIZE_BITS-1:0] initialize_index,
 input [INDEX_BITS-1:0] read0,read1,read2,read3,
 // [ARCH] value0：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
 output value0,value1,value2,value3,
 input write,
 // [ARCH] index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 training_state, address 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input [INDEX_BITS-1:0] index,
 input up
);
 localparam ENTRIES=1<<INDEX_BITS;
 localparam PATTERNS=1<<LOCAL_HISTORY_BITS;
 localparam PATTERN_BITS=2*PATTERNS;
 // [ARCH] STATE_BITS：协议阶段寄存器决定当前允许的请求、等待与完成行为。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 training_state, old_history, updated_state, history_value 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 localparam STATE_BITS=LOCAL_HISTORY_BITS+PATTERN_BITS;
 // A single logical read and write port, both indexed by the training owner.
 (* syn_ramstyle="distributed_ram" *) reg [STATE_BITS-1:0] training_rows[0:ENTRIES-1];
 // Exactly the original paired parity query topology, but only one bit per row.
 (* syn_ramstyle="distributed_ram" *) reg even_rows[0:ENTRIES/2-1],odd_rows[0:ENTRIES/2-1];
 // [ARCH] training_state（预测训练路径）：协议阶段寄存器决定当前允许的请求、等待与完成行为。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 old_history, old_counters 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [STATE_BITS-1:0] training_state=training_rows[index];
 // LOCAL_DIRECTION_STEP_BEGIN
 // [ARCH] 局部分量的更新保持本地饱和规则。
 // [ARCH] 与查询缓存同步时仍需保持同一表项索引。
 function [1:0] saturate_local;
  // [ARCH] old_value：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
  // [ARCH] 定位线索：原版中含此标识符的物理行还对 saturate_local 赋值；同一行可能含多个语句，不能据此单独推断依赖。
  input [1:0] old_value;
  input increment;
  begin
   if(increment)saturate_local=old_value==3?2'd3:old_value+2'd1;
   else saturate_local=old_value==0?2'd0:old_value-2'd1;
  end
 endfunction
 // [ARCH] old_history：保留预测相关历史，不能在退休时改用后来更新的历史。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 old_counter, shifted_history, next_counters, next_direction 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [LOCAL_HISTORY_BITS-1:0] old_history=training_state[STATE_BITS-1:PATTERN_BITS];
 wire [PATTERN_BITS-1:0] old_counters=training_state[PATTERN_BITS-1:0];
 wire [1:0] old_counter=old_counters[{old_history,1'b0}+:2];
 wire [1:0] updated_counter=saturate_local(old_counter,up);
 // [ARCH] shifted_history：保留预测相关历史，不能在退休时改用后来更新的历史。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 next_history 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [LOCAL_HISTORY_BITS:0] shifted_history={old_history,up};
 // [ARCH] next_history：保留预测相关历史，不能在退休时改用后来更新的历史。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 next_direction 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
 // [ARCH] write_enable：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
 wire write_enable=!reset&&(clearing||(!initializing&&write));
 // [ARCH] address：保持当前事务地址，等待/背压期间不能换成下一请求的地址。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 training_rows 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [INDEX_BITS-1:0] address=initializing?initialize_index[INDEX_BITS-1:0]:index;
 // [ARCH] updated_state：协议阶段寄存器决定当前允许的请求、等待与完成行为。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 training_rows 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [STATE_BITS-1:0] updated_state=initializing?
     {{LOCAL_HISTORY_BITS{1'b0}},{PATTERNS{2'b01}}}:{next_history,next_counters};
 wire updated_direction=initializing?1'b0:next_direction;
 // LOCAL_DIRECTION_STEP_END
 // LOCAL_DIRECTION_CAPTURE_BEGIN
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
 // [ARCH] 仿真参考重建原方向结果，用于核对当前有效查询。
 // [ARCH] 参考输出不能作为另一条实际硬件预测通路来计数。
 function reference_direction;
  input [INDEX_BITS-1:0] position;
  // [ARCH] state_value：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
  // [ARCH] 定位线索：原版中含此标识符的物理行还对 counters_value, history_value 赋值；同一行可能含多个语句，不能据此单独推断依赖。
  reg [STATE_BITS-1:0] state_value;
  // [ARCH] counters_value：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
  // [ARCH] 定位线索：原版中含此标识符的物理行还对 reference_direction 赋值；同一行可能含多个语句，不能据此单独推断依赖。
  reg [PATTERN_BITS-1:0] counters_value;
  // [ARCH] history_value：保留预测相关历史，不能在退休时改用后来更新的历史。
  // [ARCH] 定位线索：原版中含此标识符的物理行还对 reference_direction 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
