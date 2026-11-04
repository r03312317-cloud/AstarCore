// Parameterized tournament predictor. See TRAINING_QUEUE_CONTRACT.md.
// Default: 128 Bimodal, 256 GShare, 128 Chooser two-bit counters.
// History/context remain 8/10 bits; choose 7/8 for the original capacities.
// 架构导读：rv32_hybrid_predictor。
// 结合本地预测状态和控制转移信息，为取指路径提供预测。
module rv32_hybrid_predictor #(
 // 静态配置：parameter BIMODAL_INDEX_BITS=7。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter BIMODAL_INDEX_BITS=7,
 // 静态配置：parameter GSHARE_INDEX_BITS=8。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter GSHARE_INDEX_BITS=8
)(
 // 接口声明：input clk,reset。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input clk,reset,
 // 接口声明：input [31:0] pc0,pc1,pc2,pc3。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input [31:0] pc0,pc1,pc2,pc3,
 // 接口声明：input [7:0] query_history。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input [7:0] query_history,
 // 接口声明：output taken0,taken1,taken2,taken3。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output taken0,taken1,taken2,taken3,
 // 接口声明：output [9:0] context0,context1,context2,context3。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output [9:0] context0,context1,context2,context3,
 // 接口声明：input train0,train1。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input train0,train1,
 // 接口声明：input [31:0] train_pc0,train_pc1。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input [31:0] train_pc0,train_pc1,
 // 接口声明：input [9:0] train_context0,train_context1。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input [9:0] train_context0,train_context1,
 // 接口声明：input train_taken0,train_taken1。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input train_taken0,train_taken1,
 // 接口声明：input train_history_taken0,train_history_taken1。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input train_history_taken0,train_history_taken1,
 // 接口声明：output [7:0] committed_history。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output [7:0] committed_history,
 // 接口声明：output initialized,train_ready。
 output initialized,train_ready
);
 // 静态配置：localparam INITIALIZE_BITS=BIMODAL_INDEX_BITS>GSHARE_INDEX_BITS?BIMODAL_INDEX_BITS:GSHARE_INDEX_BITS。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam INITIALIZE_BITS=BIMODAL_INDEX_BITS>GSHARE_INDEX_BITS?BIMODAL_INDEX_BITS:GSHARE_INDEX_BITS;
 // 静态配置：localparam PACKET_BITS=BIMODAL_INDEX_BITS+GSHARE_INDEX_BITS+3。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam PACKET_BITS=BIMODAL_INDEX_BITS+GSHARE_INDEX_BITS+3;
 reg [7:0] ghr;
 reg [INITIALIZE_BITS-1:0] initialize_index;
 reg initializing;
 reg [2:0] training_head,training_tail;
 reg [3:0] training_count;
 (* syn_ramstyle="distributed_ram" *) reg [PACKET_BITS-1:0] tq_even[0:3],tq_odd[0:3];
 reg [PACKET_BITS-1:0] training_packet;
 // 局部运算/辅助过程：function [PACKET_BITS-1:0] read_training;。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
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
 function [GSHARE_INDEX_BITS-1:0] extend_history;
  input [7:0] history;
  begin extend_history={{(GSHARE_INDEX_BITS-8){1'b0}},history};end
 endfunction
 wire [PACKET_BITS-1:0] packet0={train_pc0[BIMODAL_INDEX_BITS+1:2],(train_pc0[GSHARE_INDEX_BITS+1:2]^extend_history(train_context0[9:2])),train_taken0,
  (train_context0[1]^train_context0[0]),(train_context0[0]==train_taken0)};
 wire [PACKET_BITS-1:0] packet1={train_pc1[BIMODAL_INDEX_BITS+1:2],(train_pc1[GSHARE_INDEX_BITS+1:2]^extend_history(train_context1[9:2])),train_taken1,
  (train_context1[1]^train_context1[0]),(train_context1[0]==train_taken1)};
 wire [PACKET_BITS-1:0] first_packet=accept0?packet0:packet1;
 // Data RAM payloads have no reset. A full largest-table initialization sweep resets
 // every counter before the frontend can issue its first fetch request.
 always @(posedge clk)begin
  // 复位相关判断：reset；分支方向由信号极性与取反表达式决定。
  if(reset)begin
   initializing<=1;initialize_index<=0;ghr<=0;
   training_head<=0;training_tail<=0;training_count<=0;training_packet<=0;
  end else begin
   if(initializing)begin
    if(&initialize_index)initializing<=0;
    else initialize_index<=initialize_index+1'b1;
   end
   if(accept1)ghr<=accept0?{ghr[5:0],train_history_taken0,train_history_taken1}:{ghr[6:0],train_history_taken1};
   else if(accept0)ghr<={ghr[6:0],train_history_taken0};
   training_count<=training_count+{2'b0,push_count}-{3'b0,pop};
   if(push_count!=0)training_tail<=training_tail+{1'b0,push_count};
   if(pop)training_head<=head1;
   if(pop&&training_count>1)training_packet<=read_training(head1);
   else if(push_count!=0&&(training_count==0||(pop&&training_count==1)))training_packet<=first_packet;
  end
 end
 // 过程边界：always @(posedge clk)if(!reset)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always @(posedge clk)if(!reset)begin
  if(push_count!=0&&(!training_tail[0]||push_count==2))
   tq_even[training_tail[0]?tail1[2:1]:training_tail[2:1]]<=training_tail[0]?packet1:first_packet;
  if(push_count!=0&&(training_tail[0]||push_count==2))
   tq_odd[training_tail[0]?training_tail[2:1]:tail1[2:1]]<=training_tail[0]?first_packet:packet1;
 end
 assign committed_history=ghr;
 wire [1:0] b0,b1,b2,b3,g0,g1,g2,g3,c0,c1,c2,c3;
 rv32_predictor_counters #(.INDEX_BITS(BIMODAL_INDEX_BITS),.INITIALIZE_BITS(INITIALIZE_BITS)) bimodal(
  .clk(clk),.reset(reset),.initializing(initializing),.initialize_index(initialize_index),
  .read0(pc0[BIMODAL_INDEX_BITS+1:2]),.read1(pc1[BIMODAL_INDEX_BITS+1:2]),.read2(pc2[BIMODAL_INDEX_BITS+1:2]),.read3(pc3[BIMODAL_INDEX_BITS+1:2]),
  .value0(b0),.value1(b1),.value2(b2),.value3(b3),
  .write(pop),.index(training_packet[PACKET_BITS-1:GSHARE_INDEX_BITS+3]),.up(training_packet[2]));
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
  if(BIMODAL_INDEX_BITS<2||BIMODAL_INDEX_BITS>30||GSHARE_INDEX_BITS<8||GSHARE_INDEX_BITS>30)
   $fatal(1,"Predictor index widths must satisfy B/C=2..30 and GShare=8..30");
 end
 // 过程边界：always @(posedge clk)if(!reset)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
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
 // 静态配置：parameter INDEX_BITS=7。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter INDEX_BITS=7,
 // 静态配置：parameter INITIALIZE_BITS=INDEX_BITS。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
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
 // 静态配置：localparam ENTRIES=1<<INDEX_BITS。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam ENTRIES=1<<INDEX_BITS;
 (* syn_ramstyle="distributed_ram" *) reg [1:0] even_rows[0:ENTRIES/2-1],odd_rows[0:ENTRIES/2-1];
 // 局部运算/辅助过程：function [1:0] read_counter;。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
 function [1:0] read_counter;
  input [INDEX_BITS-1:0] position;
  begin read_counter=initializing?2'b01:(position[0]?odd_rows[position[INDEX_BITS-1:1]]:even_rows[position[INDEX_BITS-1:1]]);end
 endfunction
 // 局部运算/辅助过程：function [1:0] saturate;。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
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
 // 过程边界：always @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
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
 // 过程边界：always @(posedge clk)if(!reset&&(read0[0]==read1[0]||read2[0]==read3[0]))$fatal(1,"R48 query parity contrac...。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always @(posedge clk)if(!reset&&(read0[0]==read1[0]||read2[0]==read3[0]))$fatal(1,"R48 query parity contract violated");
`endif
endmodule
