// CM120 AUDIT R1: cached-local tournament; five-bit training history.
// Queries read only the local direction bit; local history/PHT train off-path.
// Board B9/G12/H12 uses 256 H5 local rows, GShare4096 and Chooser512. Query cache index/ports are unchanged from TOPT7.
// 方向预测组合 bimodal gshare 及选择器，预测结果附带用于以后训练的上下文。
// 取指读取的是推测路径，训练依据已经退休的真实分支结果更新。
// 投机历史与提交历史分开保存，分支恢复必须还原到正确的检查点。
// 训练队列满时对上游施加背压，不能静默丢弃已经退休的分支事件。
// 实板覆盖参数 B9 G12 H12；模块默认参数不等于上板实际表容量。
// 该模块预测方向，间接目标与返回地址还需前端 BTB 和 committed RAS 配合。
module rv32_hybrid_predictor #(
 // BIMODAL_INDEX_BITS 规定 bimodal 表索引位数，不能把位数直接当作表项数量。
 parameter BIMODAL_INDEX_BITS=7,
 // GSHARE_INDEX_BITS 规定 gshare 表索引位数，实际容量随参数展开。
 parameter GSHARE_INDEX_BITS=8,
 // HISTORY_BITS 规定分支历史位宽，Linux SoC 会覆盖模块默认值。
 parameter HISTORY_BITS=8,
 parameter ENABLE_LOCAL_DIRECTION=1,
 parameter LOCAL_HISTORY_BITS=5,
 parameter LOCAL_INDEX_BITS=(BIMODAL_INDEX_BITS>2?BIMODAL_INDEX_BITS-1:BIMODAL_INDEX_BITS)
)(
 input clk,reset,
 // pc0 保存指令地址，供退休记录及异常恢复定位。
 input [31:0] pc0,pc1,pc2,pc3,
 // query_history 保存分支历史信息，投机路径与提交路径必须保持各自归属。
 input [HISTORY_BITS-1:0] query_history,
 // taken0 保存真实或候选跳转方向，使用时须区分执行结果与预测提议。
 output taken0,taken1,taken2,taken3,
 // context0 保存随指令保存的上下文，不能用之后变化的全局状态替代。
 output [HISTORY_BITS+1:0] context0,context1,context2,context3,
 input train0,train1,
 // train_pc0 属于预测训练，保存指令地址，供退休记录及异常恢复定位。
 input [31:0] train_pc0,train_pc1,
 // train_context0 属于预测训练，保存随指令保存的上下文，不能用之后变化的全局状态替代。
 input [HISTORY_BITS+1:0] train_context0,train_context1,
 // train_taken0 属于预测训练，保存真实或候选跳转方向，使用时须区分执行结果与预测提议。
 input train_taken0,train_taken1,
 // train_history_taken0 属于预测训练，保存真实或候选跳转方向，使用时须区分执行结果与预测提议。
 input train_history_taken0,train_history_taken1,
 // committed_history 保存分支历史信息，投机路径与提交路径必须保持各自归属。
 output [HISTORY_BITS-1:0] committed_history,
 // train_ready 属于预测训练，保存接收或操作数就绪资格，须结合对应的有效位使用。
 output initialized,train_ready
);
 // INITIALIZE_BITS 按 BIMODAL_INDEX_BITS>GSHARE_INDEX_BITS 进行来源选择。
 // 真分支取 BIMODAL_INDEX_BITS；其余情况取 GSHARE_INDEX_BITS。
 localparam INITIALIZE_BITS=BIMODAL_INDEX_BITS>GSHARE_INDEX_BITS?BIMODAL_INDEX_BITS:GSHARE_INDEX_BITS;
 // PACKET_BITS 按 BIMODAL_INDEX_BITS+GSHARE_INDEX_BITS+3 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam PACKET_BITS=BIMODAL_INDEX_BITS+GSHARE_INDEX_BITS+3;
 reg [HISTORY_BITS-1:0] ghr;
 // initialize_index 保存表或队列的索引，须配合有效位与对应所有者使用。
 reg [INITIALIZE_BITS-1:0] initialize_index;
 reg initializing;
 // training_head 属于预测训练，保存队头位置，界定本周期最早尚未完成相应生命周期的条目。
 // 训练事件来自已经退休的真实控制流，不能混入被取消的投机结果。
 reg [2:0] training_head,training_tail;
 // training_count 属于预测训练，保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
 reg [3:0] training_count;
 (* syn_ramstyle="distributed_ram" *) reg [PACKET_BITS-1:0] tq_even[0:3],tq_odd[0:3];
 reg [PACKET_BITS-1:0] training_packet;
 function [PACKET_BITS-1:0] read_training;
  // index 保存表或队列的索引，须配合有效位与对应所有者使用。
  input [2:0] index;
  begin read_training=index[0]?tq_odd[index[2:1]]:tq_even[index[2:1]];end
 endfunction
 assign initialized=!initializing;
 // train_ready 的资格组合为 !reset&&!initializing&&training_count<=6。
 assign train_ready=!reset&&!initializing&&training_count<=6;
 // accept0 的资格组合为 train0&&train_ready,accept1=train1&&train_ready。
 // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
 wire accept0=train0&&train_ready,accept1=train1&&train_ready;
 // push_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
 // push_count 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
 // 拼接源为 {1'b0,accept0}+{1'b0,accept1}；复制大括号表示重复位域，不是独立队列元素。
 wire [1:0] push_count={1'b0,accept0}+{1'b0,accept1};
 // pop 的资格组合为 !initializing&&training_count!=0。
 wire pop=!initializing&&training_count!=0;
 // tail1 保存队尾写入位置，必须和占用计数及同拍消费一起更新。
 // tail1 按 training_tail+3'd1,head1=training_head+3'd1 计算，运算位宽与有无符号以原声明和显式扩展为准。
 wire [2:0] tail1=training_tail+3'd1,head1=training_head+3'd1;
 // Prediction-time history is zero-extended, not widened or recomputed at retirement.
 function [GSHARE_INDEX_BITS-1:0] extend_history;
  // history 保存分支历史信息，投机路径与提交路径必须保持各自归属。
  input [HISTORY_BITS-1:0] history;
  integer bit_index;
  begin
   extend_history=0;
   for(bit_index=0;bit_index<HISTORY_BITS&&bit_index<GSHARE_INDEX_BITS;bit_index=bit_index+1)
    // extend_history[bit_index] 读取 history[bit_index] 所选位域；位索引按声明中的高低位顺序解释。
    extend_history[bit_index]=history[bit_index];
  end
 endfunction
 // packet0 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
 // 拼接源为 {train_pc0[BIMODAL_INDEX_BITS+1:2],(train_pc0[GSHARE_INDEX_BITS+1:2]^extend_history(train_context0[HISTORY_BITS+1:2])),train_taken0,；复制大括号表示重复位域，不是独立队列元素。
 wire [PACKET_BITS-1:0] packet0={train_pc0[BIMODAL_INDEX_BITS+1:2],(train_pc0[GSHARE_INDEX_BITS+1:2]^extend_history(train_context0[HISTORY_BITS+1:2])),train_taken0,
  (train_context0[1]^train_context0[0]),(train_context0[0]==train_taken0)};
 // packet1 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
 // 拼接源为 {train_pc1[BIMODAL_INDEX_BITS+1:2],(train_pc1[GSHARE_INDEX_BITS+1:2]^extend_history(train_context1[HISTORY_BITS+1:2])),train_taken1,；复制大括号表示重复位域，不是独立队列元素。
 wire [PACKET_BITS-1:0] packet1={train_pc1[BIMODAL_INDEX_BITS+1:2],(train_pc1[GSHARE_INDEX_BITS+1:2]^extend_history(train_context1[HISTORY_BITS+1:2])),train_taken1,
  (train_context1[1]^train_context1[0]),(train_context1[0]==train_taken1)};
 // first_packet 按 accept0 进行来源选择。
 // 真分支取 packet0；其余情况取 packet1。
 wire [PACKET_BITS-1:0] first_packet=accept0?packet0:packet1;
 // Data RAM payloads have no reset. A full largest-table initialization sweep resets
 // every counter before the frontend can issue its first fetch request.
 always @(posedge clk)begin
  // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
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
   // training_count 在此时钟更新路径捕获 training_count+{2'b0,push_count}-{3'b0,pop}，该更新仍受外层条件与后续同块赋值优先级限定。
   // 本时钟边界的 training_count 按 training_count+{2'b0,push_count}-{3'b0,pop} 计算，运算位宽与有无符号以原声明和显式扩展为准。
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
 // committed_history 连接到 ghr，两者在此路径上保持字段对应。
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
  // b0 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
  // 拼接源为 {local0,1'b0}；复制大括号表示重复位域，不是独立队列元素。
  assign b0={local0,1'b0};assign b1={local1,1'b0};
  // b2 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
  // 拼接源为 {local2,1'b0}；复制大括号表示重复位域，不是独立队列元素。
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
 // taken0 按 c0[1] 选择候选来源；各分支结果仍属于当前组合路径。
 // taken0 按 c0[1] 进行来源选择。
 // 真分支取 g0[1]；其余情况取 b0[1]。
 assign taken0=c0[1]?g0[1]:b0[1];assign taken1=c1[1]?g1[1]:b1[1];
 // taken2 按 c2[1] 选择候选来源；各分支结果仍属于当前组合路径。
 // taken2 按 c2[1] 进行来源选择。
 // 真分支取 g2[1]；其余情况取 b2[1]。
 assign taken2=c2[1]?g2[1]:b2[1];assign taken3=c3[1]?g3[1]:b3[1];
 // context0 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
 // 拼接源为 {query_history,b0[1],g0[1]}；复制大括号表示重复位域，不是独立队列元素。
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
 parameter INDEX_BITS=7,
 parameter INITIALIZE_BITS=INDEX_BITS
)(
 input clk,reset,initializing,
 input [INITIALIZE_BITS-1:0] initialize_index,
 input [INDEX_BITS-1:0] read0,read1,read2,read3,
 output [1:0] value0,value1,value2,value3,
 input write,
 input [INDEX_BITS-1:0] index,
 input up
);
 // ENTRIES 按 1<<INDEX_BITS 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam ENTRIES=1<<INDEX_BITS;
 (* syn_ramstyle="distributed_ram" *) reg [1:0] even_rows[0:ENTRIES/2-1],odd_rows[0:ENTRIES/2-1];
 function [1:0] read_counter;
  input [INDEX_BITS-1:0] position;
  begin read_counter=initializing?2'b01:(position[0]?odd_rows[position[INDEX_BITS-1:1]]:even_rows[position[INDEX_BITS-1:1]]);end
 endfunction
 function [1:0] saturate;
  input [1:0] old_value;
  input increment;
  begin
   if(increment)saturate=old_value==3?2'd3:old_value+2'd1;
   else saturate=old_value==0?2'd0:old_value-2'd1;
  end
 endfunction
 // Smaller tables clear once, rather than wrapping while the largest table clears.
 // clearing 的资格组合为 initializing&&((initialize_index>>INDEX_BITS)==0)。
 wire clearing=initializing&&((initialize_index>>INDEX_BITS)==0);
 // write_enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
 // write_enable 的资格组合为 !reset&&(clearing||(!initializing&&write))。
 wire write_enable=!reset&&(clearing||(!initializing&&write));
 // address 保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
 // address 按 initializing 进行来源选择。
 // 真分支取 initialize_index[INDEX_BITS-1:0]；其余情况取 index。
 wire [INDEX_BITS-1:0] address=initializing?initialize_index[INDEX_BITS-1:0]:index;
 // updated 按 initializing 进行来源选择。
 // 真分支取 2'b01；其余情况取 saturate(read_counter(index),up)。
 wire [1:0] updated=initializing?2'b01:saturate(read_counter(index),up);
 always @(posedge clk)begin
  if(write_enable&&!address[0])even_rows[address[INDEX_BITS-1:1]]<=updated;
  if(write_enable&&address[0])odd_rows[address[INDEX_BITS-1:1]]<=updated;
 end
 // ei0 按 read0[0] 进行来源选择。
 // 真分支取 read1[INDEX_BITS-1:1]；其余情况取 read0[INDEX_BITS-1:1]。
 wire [INDEX_BITS-2:0] ei0=read0[0]?read1[INDEX_BITS-1:1]:read0[INDEX_BITS-1:1];
 // oi0 按 read0[0] 进行来源选择。
 // 真分支取 read0[INDEX_BITS-1:1]；其余情况取 read1[INDEX_BITS-1:1]。
 wire [INDEX_BITS-2:0] oi0=read0[0]?read0[INDEX_BITS-1:1]:read1[INDEX_BITS-1:1];
 // ei1 按 read2[0] 进行来源选择。
 // 真分支取 read3[INDEX_BITS-1:1]；其余情况取 read2[INDEX_BITS-1:1]。
 wire [INDEX_BITS-2:0] ei1=read2[0]?read3[INDEX_BITS-1:1]:read2[INDEX_BITS-1:1];
 // oi1 按 read2[0] 进行来源选择。
 // 真分支取 read2[INDEX_BITS-1:1]；其余情况取 read3[INDEX_BITS-1:1]。
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
 parameter INDEX_BITS=8,
 parameter LOCAL_HISTORY_BITS=5,
 parameter INITIALIZE_BITS=12
)(
 input clk,reset,initializing,
 input [INITIALIZE_BITS-1:0] initialize_index,
 input [INDEX_BITS-1:0] read0,read1,read2,read3,
 output value0,value1,value2,value3,
 input write,
 input [INDEX_BITS-1:0] index,
 input up
);
 localparam ENTRIES=1<<INDEX_BITS;
 // PATTERNS 按 1<<LOCAL_HISTORY_BITS 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam PATTERNS=1<<LOCAL_HISTORY_BITS;
 // PATTERN_BITS 按 2*PATTERNS 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam PATTERN_BITS=2*PATTERNS;
 // STATE_BITS 按 LOCAL_HISTORY_BITS+PATTERN_BITS 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam STATE_BITS=LOCAL_HISTORY_BITS+PATTERN_BITS;
 // A single logical read and write port, both indexed by the training owner.
 (* syn_ramstyle="distributed_ram" *) reg [STATE_BITS-1:0] training_rows[0:ENTRIES-1];
 // Exactly the original paired parity query topology, but only one bit per row.
 (* syn_ramstyle="distributed_ram" *) reg even_rows[0:ENTRIES/2-1],odd_rows[0:ENTRIES/2-1];
 // training_state 属于预测训练，保存协议或执行状态，决定本周期允许的阶段与握手动作。
 // training_state 读取 training_rows[index] 所选位域；位索引按声明中的高低位顺序解释。
 wire [STATE_BITS-1:0] training_state=training_rows[index];
 // LOCAL_DIRECTION_STEP_BEGIN
 function [1:0] saturate_local;
  input [1:0] old_value;
  input increment;
  begin
   if(increment)saturate_local=old_value==3?2'd3:old_value+2'd1;
   else saturate_local=old_value==0?2'd0:old_value-2'd1;
  end
 endfunction
 // old_history 保存分支历史信息，投机路径与提交路径必须保持各自归属。
 // old_history 读取 training_state[STATE_BITS-1:PATTERN_BITS] 所选位域；位索引按声明中的高低位顺序解释。
 wire [LOCAL_HISTORY_BITS-1:0] old_history=training_state[STATE_BITS-1:PATTERN_BITS];
 // old_counters 读取 training_state[PATTERN_BITS-1:0] 所选位域；位索引按声明中的高低位顺序解释。
 wire [PATTERN_BITS-1:0] old_counters=training_state[PATTERN_BITS-1:0];
 // old_counter 读取 old_counters[{old_history,1'b0}+:2] 所选位域；位索引按声明中的高低位顺序解释。
 wire [1:0] old_counter=old_counters[{old_history,1'b0}+:2];
 wire [1:0] updated_counter=saturate_local(old_counter,up);
 // shifted_history 保存分支历史信息，投机路径与提交路径必须保持各自归属。
 // shifted_history 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
 // 拼接源为 {old_history,up}；复制大括号表示重复位域，不是独立队列元素。
 wire [LOCAL_HISTORY_BITS:0] shifted_history={old_history,up};
 // next_history 保存分支历史信息，投机路径与提交路径必须保持各自归属。
 // next_history 读取 shifted_history[LOCAL_HISTORY_BITS-1:0] 所选位域；位索引按声明中的高低位顺序解释。
 wire [LOCAL_HISTORY_BITS-1:0] next_history=shifted_history[LOCAL_HISTORY_BITS-1:0];
 reg [PATTERN_BITS-1:0] next_counters;
 always @*begin
  next_counters=old_counters;
  next_counters[{old_history,1'b0}+:2]=updated_counter;
 end
 // Select from the old vector unless the next history selects the one counter
 // just updated. This avoids a wide modify-vector -> select-vector chain.
 // next_direction 按 (next_history==old_history) 进行来源选择。
 // 真分支取 updated_counter[1]；其余情况取 old_counters[{next_history,1'b1}]。
 wire next_direction=(next_history==old_history)?updated_counter[1]:
                     old_counters[{next_history,1'b1}];
 // Smaller tables clear once during the existing largest-table sweep.
 wire clearing=initializing&&((initialize_index>>INDEX_BITS)==0);
 wire write_enable=!reset&&(clearing||(!initializing&&write));
 wire [INDEX_BITS-1:0] address=initializing?initialize_index[INDEX_BITS-1:0]:index;
 // updated_state 保存协议或执行状态，决定本周期允许的阶段与握手动作。
 // updated_state 按 initializing 进行来源选择。
 // 真分支取 {{LOCAL_HISTORY_BITS{1'b0}},{PATTERNS{2'b01}}}；其余情况取 {next_history,next_counters}。
 wire [STATE_BITS-1:0] updated_state=initializing?
     {{LOCAL_HISTORY_BITS{1'b0}},{PATTERNS{2'b01}}}:{next_history,next_counters};
 // updated_direction 按 initializing 进行来源选择。
 // 真分支取 1'b0；其余情况取 next_direction。
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
