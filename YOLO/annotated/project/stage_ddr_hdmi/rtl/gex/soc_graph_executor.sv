// Bounded graph command executor, CPU clock domain. No DDR data is computed
// here: all results come from the existing GEX/S3/Concat accelerators.
// Poison is cleared only by common reset; a timed-out accepted request retains
// its response ownership and can never be reassigned to a CPU transaction.
// 架构导读：soc_graph_executor。
// GRAPH_EXECUTOR1 图指令执行器，读取片上命令 RAM，执行受限 MMIO 写入、轮询、检查及计数。
module soc_graph_executor #(
 // 静态配置：parameter integer PROGRAM_ADDR_BITS=13,MAX_NODES=256。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer PROGRAM_ADDR_BITS=13,MAX_NODES=256
)(
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 // 接口声明：input logic req_valid,output logic req_ready,input logic [7:0] req_addr。
 // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
 input logic req_valid,output logic req_ready,input logic [7:0] req_addr,
 // 接口声明：input logic req_write,input logic [31:0] req_wdata,input logic [3:0] req_wstrb。
 // 按字节选择本次写入生效的 lane。
 input logic req_write,input logic [31:0] req_wdata,input logic [3:0] req_wstrb,
 // 接口声明：output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_rdata,output logic rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_rdata,output logic rsp_error,
 // 接口声明：output logic m_req_valid,input logic m_req_ready,output logic [31:0] m_req_addr,m_req_wdata。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 output logic m_req_valid,input logic m_req_ready,output logic [31:0] m_req_addr,m_req_wdata,
 // 接口声明：output logic m_req_write,output logic [3:0] m_req_wstrb。
 // 按字节选择本次写入生效的 lane。
 output logic m_req_write,output logic [3:0] m_req_wstrb,
 // 接口声明：input logic m_rsp_valid,output logic m_rsp_ready,input logic [31:0] m_rsp_rdata,input logic m_rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 input logic m_rsp_valid,output logic m_rsp_ready,input logic [31:0] m_rsp_rdata,input logic m_rsp_error,
 // 接口声明：output logic busy,poison,input_consumed。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic busy,poison,input_consumed
);
 // 静态配置：localparam integer DEPTH=1<<PROGRAM_ADDR_BITS,MAX_WORDS=DEPTH*4。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam integer DEPTH=1<<PROGRAM_ADDR_BITS,MAX_WORDS=DEPTH*4;
 // 静态配置：localparam [3:0] IDLE=0,FETCH=1,DECODE=2,ISSUE=3,RESPONSE=4,POLL_DELAY=5。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam [3:0] IDLE=0,FETCH=1,DECODE=2,ISSUE=3,RESPONSE=4,POLL_DELAY=5,
  TRACE0=6,TRACE1=7,TRACE2=8,TRACE3=9,FAULT_WAIT=10,FAULT=11;
 // 静态配置：localparam [7:0] OP_END=0,OP_WRITE=1,OP_CONTEXT=2,OP_WAIT=3,OP_CHECK=4。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam [7:0] OP_END=0,OP_WRITE=1,OP_CONTEXT=2,OP_WAIT=3,OP_CHECK=4,
  OP_ACCUM=5,OP_BEGIN=6,OP_END_NODE=7;
 // 局部字段 logic [31:0] program0[0:DEPTH-1],program1[0:DEPTH-1],program2[0:DEPTH-1],program3[0:DEPTH-1]。
 logic [31:0] program0[0:DEPTH-1],program1[0:DEPTH-1],program2[0:DEPTH-1],program3[0:DEPTH-1];
 logic [31:0] q0,q1,q2,q3,a,b,c;logic [7:0] op;
 logic [PROGRAM_ADDR_BITS:0] pc;
 logic [31:0] loaded_words,expected_words,expected_crc,crc_state,crc_shift;
 logic [2:0] crc_left;
 logic program_valid,done;
 logic [31:0] model_epoch,frame_epoch,expected_nodes,timeout_cycles,program_generation;
 logic [31:0] elapsed,instructions,writes,reads,completed,failure,last_read,node,node_kind,node_begin;
 logic [31:0] watchdog,trace_elapsed,trace_flags;
 logic [3:0] state;logic node_open,trace_fused;
 logic [4:0] poll_delay;
 logic [63:0] counters[0:31];logic [31:0] counter_latch_hi;
 logic [4:0] counter_index;
 logic [31:0] trace_mem[0:MAX_NODES*4-1],trace_q;
 logic [9:0] trace_index,trace_write_index;
 logic [31:0] trace_count;
 wire ctl=req_valid&&req_ready;
 // 组合连接 req_ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
 assign req_ready=!rst&&!rsp_valid&&(crc_left==0);
 // 组合连接 busy：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 assign busy=(state!=IDLE);
 // 组合连接 m_req_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
 assign m_req_valid=!rst&&state==ISSUE;
 // 组合连接 m_rsp_ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
 assign m_rsp_ready=!rst&&(state==RESPONSE||state==FAULT_WAIT);
 // 组合连接 m_req_addr：用于地址/基址选择，访问步长和对齐还受相应描述符约束。
 assign m_req_addr=a;assign m_req_wdata=(op[7:0]==OP_CONTEXT)?(b==0?model_epoch:frame_epoch):b;
 // 组合连接 m_req_write：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 assign m_req_write=op[7:0]==OP_WRITE||op[7:0]==OP_CONTEXT;
 // 组合连接 m_req_wstrb：按字节选择本次写入生效的 lane。
 assign m_req_wstrb=4'hf;
 // 局部运算/辅助过程：function automatic [31:0] crc_byte(input [31:0] prior,input [7:0] value);。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
 function automatic [31:0] crc_byte(input [31:0] prior,input [7:0] value);
  reg [31:0] r;integer i;begin r=prior^{24'd0,value};for(i=0;i<8;i=i+1)r=r[0]?((r>>1)^32'hedb88320):(r>>1);crc_byte=r;end
 endfunction
 // 局部运算/辅助过程：function automatic allowed(input [31:0] addr,input wr);。
 // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
 function automatic allowed(input [31:0] addr,input wr);
  begin
   allowed=(addr[1:0]==0)&&((addr>=32'h70000100&&addr<=32'h700001bc)||
      (addr>=32'h60001100&&addr<=32'h60001140)||
      (addr>=32'h60001400&&addr<=32'h60001440)||
      (!wr&&addr==32'h7000000c)||(wr&&(addr==32'h70000014||addr==32'h70000078)));
  end
 endfunction
 // Inferred synchronous block RAMs. Program contents never receive reset.
 always_ff @(posedge clk) begin
  q0<=program0[pc[PROGRAM_ADDR_BITS-1:0]];q1<=program1[pc[PROGRAM_ADDR_BITS-1:0]];
  q2<=program2[pc[PROGRAM_ADDR_BITS-1:0]];q3<=program3[pc[PROGRAM_ADDR_BITS-1:0]];
  trace_q<=trace_mem[trace_index];
  // 条件分支：检查 ctl&&req_write&&req_wstrb==4'hf&&req_addr==8'h1c&&!busy&&!poison&&。
  if(ctl&&req_write&&req_wstrb==4'hf&&req_addr==8'h1c&&!busy&&!poison&&
     !program_valid&&loaded_words<MAX_WORDS)begin
   // 按 loaded_words[1:0] 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case(loaded_words[1:0])
    0:program0[loaded_words[PROGRAM_ADDR_BITS+1:2]]<=req_wdata;
    1:program1[loaded_words[PROGRAM_ADDR_BITS+1:2]]<=req_wdata;
    2:program2[loaded_words[PROGRAM_ADDR_BITS+1:2]]<=req_wdata;
    3:program3[loaded_words[PROGRAM_ADDR_BITS+1:2]]<=req_wdata;
   endcase
  end
  // 复位相关判断：!rst；分支方向由信号极性与取反表达式决定。
  if(!rst)case(state)
   // 状态/选择分支 TRACE0：本分支规定该编码下的寄存器更新和下一步动作。
   TRACE0:trace_mem[trace_write_index]<=trace_elapsed;
   // 状态/选择分支 TRACE1：本分支规定该编码下的寄存器更新和下一步动作。
   TRACE1:trace_mem[trace_write_index+10'd1]<=trace_flags;
   // 状态/选择分支 TRACE2：本分支规定该编码下的寄存器更新和下一步动作。
   TRACE2:trace_mem[trace_write_index+10'd2]<=0;
   // 状态/选择分支 TRACE3：本分支规定该编码下的寄存器更新和下一步动作。
   TRACE3:trace_mem[trace_write_index+10'd3]<=0;
   default:;
  endcase
 end
 integer i;
 // 过程边界：always_ff @(posedge clk) begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk) begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin
   rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;state<=IDLE;pc<=0;
   loaded_words<=0;expected_words<=0;expected_crc<=0;crc_state<=32'hffffffff;crc_shift<=0;crc_left<=0;
   program_valid<=0;done<=0;poison<=0;input_consumed<=0;
   model_epoch<=0;frame_epoch<=0;expected_nodes<=0;timeout_cycles<=350000000;program_generation<=0;
   elapsed<=0;instructions<=0;writes<=0;reads<=0;completed<=0;failure<=0;last_read<=0;
   node<=0;node_kind<=0;node_begin<=0;node_open<=0;watchdog<=0;poll_delay<=0;
   trace_elapsed<=0;trace_flags<=0;trace_fused<=0;trace_index<=0;trace_write_index<=0;trace_count<=0;
   counter_index<=0;counter_latch_hi<=0;op<=0;a<=0;b<=0;c<=0;
   // 按 i=0;i<32;i=i+1 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
   for(i=0;i<32;i=i+1)counters[i]<=0;
  end else begin
   // 握手/背压判断：rsp_valid&&rsp_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   // 条件分支：检查 crc_left!=0。
   if(crc_left!=0)begin crc_state<=crc_byte(crc_state,crc_shift[7:0]);crc_shift<=crc_shift>>8;crc_left<=crc_left-1'b1;end
   // 条件分支：检查 busy&&!poison。
   if(busy&&!poison)begin elapsed<=elapsed+1'b1;watchdog<=watchdog+1'b1;end
   // 条件分支：检查 ctl。
   if(ctl)begin
    rsp_valid<=1;rsp_rdata<=0;rsp_error<=0;
    // 条件分支：检查 req_addr[1:0]!=0||(req_write&&req_wstrb!=4'hf)。
    if(req_addr[1:0]!=0||(req_write&&req_wstrb!=4'hf))rsp_error<=1;
    // 条件分支：检查 req_write。
    else if(req_write)begin
     // 条件分支：检查 req_addr==8'h54。
     if(req_addr==8'h54)trace_index<=req_wdata[9:0];
     // 条件分支：检查 req_addr==8'h5c。
     else if(req_addr==8'h5c)counter_index<=req_wdata[4:0];
     // 条件分支：检查 busy||poison。
     else if(busy||poison)rsp_error<=1;
     else case(req_addr)
      8'h08:case(req_wdata)
       1:begin program_valid<=0;done<=0;loaded_words<=0;crc_state<=32'hffffffff;expected_words<=0;expected_crc<=0;end
       2:if(loaded_words==0||loaded_words[1:0]!=0||loaded_words!=expected_words||(~crc_state)!=expected_crc||expected_nodes==0||expected_nodes>MAX_NODES)
            rsp_error<=1;
         else begin program_valid<=1;program_generation<=program_generation+1'b1;end
       4:if(!program_valid||model_epoch==0||frame_epoch==0||timeout_cycles==0)rsp_error<=1;
         else begin
          state<=FETCH;pc<=0;done<=0;input_consumed<=0;elapsed<=0;watchdog<=0;
          completed<=0;trace_count<=0;failure<=0;instructions<=0;writes<=0;reads<=0;node_open<=0;
          // 按 i=0;i<32;i=i+1 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
          for(i=0;i<32;i=i+1)counters[i]<=0;
         end
       8:done<=0;
       default:rsp_error<=1;
      endcase
      8'h10:expected_words<=req_wdata;
      8'h14:expected_crc<=req_wdata;
      8'h1c:if(program_valid||loaded_words>=MAX_WORDS)rsp_error<=1;
             else begin loaded_words<=loaded_words+1'b1;crc_shift<=req_wdata;crc_left<=4;end
      8'h20:model_epoch<=req_wdata;
      8'h24:frame_epoch<=req_wdata;
      8'h28:expected_nodes<=req_wdata;
      8'h2c:timeout_cycles<=req_wdata;
      default:rsp_error<=1;
     endcase
    end else case(req_addr)
     8'h00:rsp_rdata<=32'h31585047; // GRAPH_EXECUTOR1
     8'h04:rsp_rdata<={26'd0,input_consumed,(crc_left!=0),poison,program_valid,done,busy};
     8'h0c:rsp_rdata<=loaded_words;
     8'h10:rsp_rdata<=expected_words;
     8'h14:rsp_rdata<=expected_crc;
     8'h18:rsp_rdata<=~crc_state;
     8'h20:rsp_rdata<=model_epoch;
     8'h24:rsp_rdata<=frame_epoch;
     8'h28:rsp_rdata<=expected_nodes;
     8'h2c:rsp_rdata<=timeout_cycles;
     8'h30:rsp_rdata<={{(31-PROGRAM_ADDR_BITS){1'b0}},pc};
     8'h34:rsp_rdata<=completed;
     8'h38:rsp_rdata<=failure;
     8'h3c:rsp_rdata<=last_read;
     8'h40:rsp_rdata<=elapsed;
     8'h44:rsp_rdata<=instructions;
     8'h48:rsp_rdata<=writes;
     8'h4c:rsp_rdata<=reads;
     8'h50:rsp_rdata<=node;
     8'h54:rsp_rdata<={22'd0,trace_index};
     8'h58:begin rsp_rdata<=({22'd0,trace_index}<trace_count*4)?trace_q:0;trace_index<=trace_index+1'b1;end
     8'h5c:rsp_rdata<={27'd0,counter_index};
     8'h60:begin rsp_rdata<=counters[counter_index][31:0];counter_latch_hi<=counters[counter_index][63:32];end
     8'h64:rsp_rdata<=counter_latch_hi;
     8'h68:rsp_rdata<=MAX_WORDS;
     8'h6c:rsp_rdata<=program_generation;
     default:rsp_error<=1;
    endcase
   end
   // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case(state)
    IDLE:;
    // 状态/选择分支 FETCH：本分支规定该编码下的寄存器更新和下一步动作。
    FETCH:begin
     // 条件分支：检查 ({{(31-PROGRAM_ADDR_BITS){1'b0}},pc}<<2)>=loaded_words。
     if(({{(31-PROGRAM_ADDR_BITS){1'b0}},pc}<<2)>=loaded_words)begin poison<=1;failure<=1;state<=FAULT;end
     else state<=DECODE;
    end
    // 状态/选择分支 DECODE：本分支规定该编码下的寄存器更新和下一步动作。
    DECODE:begin
     op<=q0[7:0];a<=q1;b<=q2;c<=q3;watchdog<=0;
     // 条件分支：检查 q0[31:8]!=0。
     if(q0[31:8]!=0)begin poison<=1;failure<=2;state<=FAULT;end
     else case(q0[7:0])
      // 状态/选择分支 OP_END：本分支规定该编码下的寄存器更新和下一步动作。
      OP_END:if(node_open||completed!=expected_nodes||q1!=expected_nodes||q2!=0||q3!=0||((32'(pc)+1)*4)!=loaded_words)begin poison<=1;failure<=3;state<=FAULT;end
             else begin done<=1;state<=IDLE;instructions<=instructions+1'b1;end
      OP_WRITE,OP_CONTEXT,OP_WAIT,OP_CHECK,OP_ACCUM:begin
       // 条件分支：检查 !allowed(q1,q0[7:0]==OP_WRITE||q0[7:0]==OP_CONTEXT)||。
       if(!allowed(q1,q0[7:0]==OP_WRITE||q0[7:0]==OP_CONTEXT)||
          (q0[7:0]==OP_CONTEXT&&(q2>1||q3!=0))||
          (q0[7:0]==OP_WRITE&&q3!=0)||
          (q0[7:0]==OP_WAIT&&q2==0)||
          (q0[7:0]==OP_ACCUM&&(q2>31||(q3!=0&&q3!=32))))begin poison<=1;failure<=4;state<=FAULT;end
       else state<=ISSUE;
      end
      // 状态/选择分支 OP_BEGIN：本分支规定该编码下的寄存器更新和下一步动作。
      OP_BEGIN:if(node_open||q1!=completed||q1>=expected_nodes||q2<1||q2>6||q3!=0)begin poison<=1;failure<=5;state<=FAULT;end
       else begin node<=q1;node_kind<=q2;node_begin<=elapsed;node_open<=1;pc<=pc+1'b1;state<=FETCH;instructions<=instructions+1'b1;end
      // 状态/选择分支 OP_END_NODE：本分支规定该编码下的寄存器更新和下一步动作。
      OP_END_NODE:if(!node_open||q1!=node||q2>1||q3>2||(q2!=0&&node_kind!=2)||completed+1+q2>expected_nodes)begin poison<=1;failure<=6;state<=FAULT;end
       else begin
        node_open<=0;trace_elapsed<=elapsed-node_begin;trace_flags<=32'ha0000000;
        trace_write_index<={node[7:0],2'b00};trace_fused<=q2!=0;state<=TRACE0;
        // 条件分支：检查 node==0。
        if(node==0)input_consumed<=1;
        // 按 node_kind 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
        case(node_kind)
         1:begin counters[18]<=counters[18]+1'b1;counters[23]<=counters[23]+{32'd0,(elapsed-node_begin)};
             // 条件分支：检查 q3==1。
             if(q3==1)counters[29]<=counters[29]+1'b1;
             // 条件分支：检查 q3==2。
             if(q3==2)counters[30]<=counters[30]+1'b1;end
         2:begin counters[19]<=counters[19]+1'b1;counters[24]<=counters[24]+{32'd0,(elapsed-node_begin)};
             // 条件分支：检查 q2!=0。
             if(q2!=0)counters[20]<=counters[20]+1'b1;end
         3:begin counters[21]<=counters[21]+1'b1;counters[25]<=counters[25]+{32'd0,(elapsed-node_begin)};end
         4:begin counters[22]<=counters[22]+1'b1;counters[26]<=counters[26]+{32'd0,(elapsed-node_begin)};end
         5:begin counters[22]<=counters[22]+1'b1;counters[27]<=counters[27]+{32'd0,(elapsed-node_begin)};end
         6:begin counters[22]<=counters[22]+1'b1;counters[28]<=counters[28]+{32'd0,(elapsed-node_begin)};end
         default:;
        endcase
       end
      default:begin poison<=1;failure<=7;state<=FAULT;end
     endcase
    end
    // 状态/选择分支 ISSUE：本分支规定该编码下的寄存器更新和下一步动作。
    ISSUE:if(m_req_ready)begin
     state<=RESPONSE;if(m_req_write)writes<=writes+1'b1;else reads<=reads+1'b1;
    // 条件分支：检查 watchdog>=timeout_cycles。
    end else if(watchdog>=timeout_cycles)begin poison<=1;failure<=8;state<=FAULT;end
    // 状态/选择分支 RESPONSE：本分支规定该编码下的寄存器更新和下一步动作。
    RESPONSE:if(m_rsp_valid)begin
     last_read<=m_rsp_rdata;
     // 条件分支：检查 m_rsp_error。
     if(m_rsp_error)begin poison<=1;failure<=9;state<=FAULT;end
     // 条件分支：检查 op[7:0]==OP_WAIT&&(m_rsp_rdata&c)!=0。
     else if(op[7:0]==OP_WAIT&&(m_rsp_rdata&c)!=0)begin poison<=1;failure<=10;state<=FAULT;end
     // 条件分支：检查 op[7:0]==OP_WAIT&&(m_rsp_rdata&b)==0。
     else if(op[7:0]==OP_WAIT&&(m_rsp_rdata&b)==0)begin
      // 条件分支：检查 watchdog>=timeout_cycles。
      if(watchdog>=timeout_cycles)begin poison<=1;failure<=11;state<=FAULT;end
      else begin state<=POLL_DELAY;poll_delay<=15;end
     // 条件分支：检查 op[7:0]==OP_CHECK&&(m_rsp_rdata&c)!=(b&c)。
     end else if(op[7:0]==OP_CHECK&&(m_rsp_rdata&c)!=(b&c))begin poison<=1;failure<=12;state<=FAULT;end
     else begin
      // 条件分支：检查 op[7:0]==OP_ACCUM。
      if(op[7:0]==OP_ACCUM)counters[b[4:0]]<=counters[b[4:0]]+((c==32)?{m_rsp_rdata,32'd0}:{32'd0,m_rsp_rdata});
      pc<=pc+1'b1;state<=FETCH;instructions<=instructions+1'b1;
     end
    // 条件分支：检查 watchdog>=timeout_cycles。
    end else if(watchdog>=timeout_cycles)begin poison<=1;failure<=13;state<=FAULT_WAIT;end
    // 状态/选择分支 POLL_DELAY：本分支规定该编码下的寄存器更新和下一步动作。
    POLL_DELAY:if(poll_delay==0)state<=ISSUE;else poll_delay<=poll_delay-1'b1;
    // 状态/选择分支 TRACE0：本分支规定该编码下的寄存器更新和下一步动作。
    TRACE0:state<=TRACE1;
    // 状态/选择分支 TRACE1：本分支规定该编码下的寄存器更新和下一步动作。
    TRACE1:state<=TRACE2;
    // 状态/选择分支 TRACE2：本分支规定该编码下的寄存器更新和下一步动作。
    TRACE2:state<=TRACE3;
    // 状态/选择分支 TRACE3：本分支规定该编码下的寄存器更新和下一步动作。
    TRACE3:begin
     completed<=completed+1'b1;trace_count<=trace_count+1'b1;
     // 条件分支：检查 trace_fused。
     if(trace_fused)begin trace_fused<=0;trace_write_index<=trace_write_index+10'd4;trace_elapsed<=0;trace_flags<=32'he0000000;state<=TRACE0;end
     else begin pc<=pc+1'b1;state<=FETCH;instructions<=instructions+1'b1;end
    end
    // 状态/选择分支 FAULT_WAIT：本分支规定该编码下的寄存器更新和下一步动作。
    FAULT_WAIT:if(m_rsp_valid)state<=FAULT;
    FAULT:;
    default:begin poison<=1;failure<=14;state<=FAULT;end
   endcase
  end
 end
endmodule
