// 架构导读：npu_response_order。
// 保持 NPU 数据响应与已接受请求之间的顺序关系。
`timescale 1ns/1ps
// The SoC DDR packet bridge, per-master router FIFO and CDC FIFO preserve
// response order. For that transport, retain a bounded ownership scoreboard
// and check every response at its head instead of storing/reloading payloads.
// Generic users keep the original out-of-order-capable implementation.
module npu_response_order #(
 // 静态配置：parameter int DATA_W=128,ID_W=4,SLOTS=16,parameter bit IN_ORDER_TRANSPORT=1'b0。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter int DATA_W=128,ID_W=4,SLOTS=16,parameter bit IN_ORDER_TRANSPORT=1'b0
)(
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 // 接口声明：input logic issue_valid,output logic issue_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic issue_valid,output logic issue_ready,
 // 接口声明：input logic [ID_W-1:0] issue_id,input logic issue_write。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [ID_W-1:0] issue_id,input logic issue_write,
 // 接口声明：input logic rsp_valid,output logic rsp_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic rsp_valid,output logic rsp_ready,
 // 接口声明：input logic [ID_W-1:0] rsp_id,input logic rsp_write,rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 input logic [ID_W-1:0] rsp_id,input logic rsp_write,rsp_error,
 // 接口声明：input logic [DATA_W-1:0] rsp_data。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 input logic [DATA_W-1:0] rsp_data,
 // 接口声明：output logic out_valid,input logic out_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic out_valid,input logic out_ready,
 // 接口声明：output logic [ID_W-1:0] out_id,output logic out_write,out_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 output logic [ID_W-1:0] out_id,output logic out_write,out_error,
 // 接口声明：output logic [DATA_W-1:0] out_data。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 output logic [DATA_W-1:0] out_data,
 // 接口声明：output logic drained,idle,protocol_poison。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 output logic drained,idle,protocol_poison,
 // 接口声明：output logic [$clog2(SLOTS+1)-1:0] owned。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [$clog2(SLOTS+1)-1:0] owned
);
 generate if(IN_ORDER_TRANSPORT)begin:ordered_link
  npu_response_order_inorder #(.DATA_W(DATA_W),.ID_W(ID_W),.SLOTS(SLOTS)) impl(.*);
 end else begin:reorder_link
  npu_response_order_reorder #(.DATA_W(DATA_W),.ID_W(ID_W),.SLOTS(SLOTS)) impl(.*);
 end endgenerate
endmodule

module npu_response_order_inorder #(
 // 静态配置：parameter int DATA_W=128,ID_W=4,SLOTS=16。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter int DATA_W=128,ID_W=4,SLOTS=16
)(
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 // 接口声明：input logic issue_valid,output logic issue_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic issue_valid,output logic issue_ready,
 input logic [ID_W-1:0] issue_id,input logic issue_write,
 input logic rsp_valid,output logic rsp_ready,
 input logic [ID_W-1:0] rsp_id,input logic rsp_write,rsp_error,
 input logic [DATA_W-1:0] rsp_data,
 output logic out_valid,input logic out_ready,
 output logic [ID_W-1:0] out_id,output logic out_write,out_error,
 output logic [DATA_W-1:0] out_data,
 output logic drained,idle,protocol_poison,
 output logic [$clog2(SLOTS+1)-1:0] owned
);
 // 静态配置：localparam int PTR_W=$clog2(SLOTS),COUNT_W=$clog2(SLOTS+1)。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam int PTR_W=$clog2(SLOTS),COUNT_W=$clog2(SLOTS+1);
 logic [SLOTS-1:0] live;
 logic [ID_W:0] expected[0:SLOTS-1];
 logic [PTR_W-1:0] head,tail;
 wire issue_known=32'(issue_id)<SLOTS;
 wire response_legal=owned!=0 && 32'(rsp_id)<SLOTS && live[rsp_id] &&
                     expected[head]=={rsp_write,rsp_id};
 assign issue_ready=!rst&&!protocol_poison&&issue_known&&
                    !live[issue_id]&&owned<COUNT_W'(SLOTS);
 // A malformed response is consumed only to latch quarantine. It is never
 // forwarded as data or completion, and outstanding ownership is retained.
 assign rsp_ready=!rst&&(protocol_poison||!response_legal||out_ready);
 assign out_valid=!rst&&!protocol_poison&&rsp_valid&&response_legal;
 assign out_data=rsp_data;
 assign out_id=rsp_id;
 assign out_write=rsp_write;
 assign out_error=rsp_error;
 wire push=issue_valid&&issue_ready;
 wire pop=out_valid&&out_ready;
 assign drained=owned==0;
 assign idle=!rst&&!protocol_poison&&drained;
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin live<=0;head<=0;tail<=0;owned<=0;protocol_poison<=0;end
  else begin
   if(issue_valid&&!issue_known)protocol_poison<=1;
   // 握手/背压判断：rsp_valid&&rsp_ready&&!protocol_poison&&!response_legal。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(rsp_valid&&rsp_ready&&!protocol_poison&&!response_legal)protocol_poison<=1;
   if(push)begin
    expected[tail]<={issue_write,issue_id};tail<=tail+1'b1;live[issue_id]<=1;
   end
   if(pop)begin head<=head+1'b1;live[out_id]<=0;end
   // 按 {push,pop} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case({push,pop})
    2'b10:owned<=owned+1'b1;
    2'b01:owned<=owned-1'b1;
    default:;
   endcase
  end
 end
 initial begin
  if(SLOTS<2||(SLOTS&(SLOTS-1))!=0||SLOTS>(1<<ID_W))
   $fatal(1,"ORDERED_RETURN_PARAMETER_RED");
 end
endmodule

`timescale 1ns/1ps
// Bounded response retirement for ordered wholeword resident-bank fills.
// This is a sidecar to ONE existing DMA. It neither issues memory operations
// nor fabricates responses. RAM is written only by an actualR/B handshake.
// Every accepted request remains owned until its actual response is passed
// to the existing DMA. Malformed unowned/duplicate replies quarantine the
// owner until coordinated common reset; they cannot produce a PASS/idle.
module npu_response_order_reorder #(
 // 静态配置：parameter int DATA_W=128,ID_W=4,SLOTS=16。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter int DATA_W=128,ID_W=4,SLOTS=16
)(
 input logic clk,rst,
 input logic issue_valid,output logic issue_ready,
 input logic [ID_W-1:0] issue_id,input logic issue_write,
 input logic rsp_valid,output logic rsp_ready,
 input logic [ID_W-1:0] rsp_id,input logic rsp_write,rsp_error,
 input logic [DATA_W-1:0] rsp_data,
 output logic out_valid,input logic out_ready,
 output logic [ID_W-1:0] out_id,output logic out_write,out_error,
 output logic [DATA_W-1:0] out_data,
 output logic drained,idle,protocol_poison,
 output logic [$clog2(SLOTS+1)-1:0] owned
);
 // 静态配置：localparam int PTR_W=$clog2(SLOTS),COUNT_W=$clog2(SLOTS+1),PAYLOAD_W=DATA_W+ID_W+2。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam int PTR_W=$clog2(SLOTS),COUNT_W=$clog2(SLOTS+1),PAYLOAD_W=DATA_W+ID_W+2;
 logic [SLOTS-1:0] live,returned,expected_write;
 logic [ID_W-1:0] order_ids[0:SLOTS-1];
 logic [PTR_W-1:0] tail,fetch;
 logic [COUNT_W-1:0] unfetched;
 logic [1:0] fifo_count;logic fifo_rd,fifo_wr;
 logic [PAYLOAD_W-1:0] fifo_payload[0:1];
 logic read_pending;logic [ID_W-1:0] ram_tag;
 wire issue_known=32'(issue_id)<SLOTS;
 wire response_known=32'(rsp_id)<SLOTS&&live[rsp_id]&&!returned[rsp_id];
 assign issue_ready=!rst&&!protocol_poison&&issue_known&&!live[issue_id]&&owned<COUNT_W'(SLOTS);
 // Illegal replies are accepted only to record explicit quarantine. The
 // owning job must then stop/reset; successful retirement is impossible.
 assign rsp_ready=!rst;
 wire push=issue_valid&&issue_ready;
 wire receive=rsp_valid&&rsp_ready;
 wire receive_owned=receive&&response_known;
 assign out_valid=!rst&&fifo_count!=0;
 assign {out_write,out_error,out_id,out_data}=fifo_payload[fifo_rd];
 wire pop=out_valid&&out_ready;
 wire fifo_in_ready=fifo_count<2||pop;
 wire fifo_in_fire=read_pending&&fifo_in_ready;
 wire [2:0] buffered={1'b0,fifo_count}+{2'd0,read_pending};
 wire [ID_W-1:0] fetch_id=order_ids[fetch];
 wire read_issue=!rst&&unfetched!=0&&returned[fetch_id]&&
  (!read_pending||fifo_in_ready)&&(buffered<2||pop);
 wire [DATA_W+1:0] memory_result;
 npu_order_word_ram #(.WIDTH(DATA_W+2),.ADDR_W(PTR_W)) payload(
  .clk,.wr_en(receive_owned),.wr_addr(PTR_W'(rsp_id)),.wr_data({rsp_write,rsp_error,rsp_data}),
  .rd_en(read_issue),.rd_addr(PTR_W'(fetch_id)),.rd_data(memory_result));
 assign drained=owned==0&&unfetched==0&&fifo_count==0&&!read_pending;
 assign idle=!rst&&drained&&!protocol_poison;
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin live<=0;returned<=0;expected_write<=0;tail<=0;fetch<=0;owned<=0;unfetched<=0;
   fifo_count<=0;fifo_rd<=0;fifo_wr<=0;read_pending<=0;ram_tag<=0;protocol_poison<=0;end
  else begin
   if(issue_valid&&!issue_known)protocol_poison<=1;
   if(push)begin order_ids[tail]<=issue_id;tail<=tail+1'b1;live[issue_id]<=1;returned[issue_id]<=0;expected_write[issue_id]<=issue_write;end
   if(receive)begin
    if(!response_known)protocol_poison<=1;
    else begin returned[rsp_id]<=1;if(rsp_write!=expected_write[rsp_id])protocol_poison<=1;end
   end
   if(fifo_in_fire)begin fifo_payload[fifo_wr]<={memory_result[DATA_W+1:DATA_W],ram_tag,memory_result[DATA_W-1:0]};fifo_wr<=!fifo_wr;read_pending<=0;end
   if(read_issue)begin ram_tag<=fetch_id;fetch<=fetch+1'b1;read_pending<=1;end
   if(pop)begin
    if(32'(out_id)>=SLOTS||!live[out_id]||!returned[out_id])protocol_poison<=1;
    else begin live[out_id]<=0;returned[out_id]<=0;end
    fifo_rd<=!fifo_rd;
   end
   // 按 {push,pop} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case({push,pop})2'b10:owned<=owned+1'b1;2'b01:owned<=owned-1'b1;default:;endcase
   // 按 {push,read_issue} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case({push,read_issue})2'b10:unfetched<=unfetched+1'b1;2'b01:unfetched<=unfetched-1'b1;default:;endcase
   // 按 {fifo_in_fire,pop} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case({fifo_in_fire,pop})2'b10:fifo_count<=fifo_count+1'b1;2'b01:fifo_count<=fifo_count-1'b1;default:;endcase
  end
 end
 initial begin
  if(SLOTS<2||(SLOTS&(SLOTS-1))!=0||SLOTS>(1<<ID_W))$fatal(1,"RESPONSE_ORDER_PARAMETER_RED");
 end
endmodule

module npu_order_word_ram #(parameter int WIDTH=130,ADDR_W=4)(
 input logic clk,wr_en,input logic [ADDR_W-1:0] wr_addr,input logic [WIDTH-1:0] wr_data,
 input logic rd_en,input logic [ADDR_W-1:0] rd_addr,output logic [WIDTH-1:0] rd_data
);
 (* ram_style="block",syn_ramstyle="block_ram" *) logic [WIDTH-1:0] memory[0:(1<<ADDR_W)-1];
 // 过程边界：always_ff @(posedge clk)begin if(wr_en)memory[wr_addr]<=wr_data;if(rd_en)rd_data<=memory[rd_addr];end。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin if(wr_en)memory[wr_addr]<=wr_data;if(rd_en)rd_data<=memory[rd_addr];end
endmodule
