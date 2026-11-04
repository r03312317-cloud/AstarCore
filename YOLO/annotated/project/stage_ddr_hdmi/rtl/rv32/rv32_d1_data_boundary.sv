// Registered D-channel boundary for the full, unchanged RV32 core/cache.
// No combinational memory-ready, tag-hit or response path reaches the core.
// Requests and errors remain ordered; cache maintenance drains older owners.
// 架构导读：rv32_d1_data_boundary。
// 可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。
module rv32_d1_data_boundary (
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 // 接口声明：input logic c_valid,c_write。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic c_valid,c_write,
 // 接口声明：output logic c_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic c_ready,
 // 接口声明：input logic [31:0] c_addr,c_wdata。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 input logic [31:0] c_addr,c_wdata,
 // 接口声明：input logic [3:0] c_strobe。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [3:0] c_strobe,
 // 接口声明：input logic [1:0] c_size。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [1:0] c_size,
 output logic c_rsp_valid,c_rsp_error,
 input logic c_rsp_ready,
 output logic [31:0] c_rdata,
 input logic c_fence_i,c_fence_d,
 output logic m_valid,m_write,
 input logic m_ready,
 output logic [31:0] m_addr,m_wdata,
 output logic [3:0] m_strobe,
 output logic [1:0] m_size,
 input logic m_rsp_valid,m_rsp_error,
 output logic m_rsp_ready,
 input logic [31:0] m_rdata,
 output logic m_fence_i,m_fence_d,
 output logic barrier_pending,
 output logic fault
);
 logic request_full,response_full,pending_i,pending_d;
 logic [1:0] owners;
 wire push=c_valid&&c_ready;
 wire take=m_valid&&m_ready;
 wire receive=m_rsp_valid&&m_rsp_ready;
 wire consume=c_rsp_valid&&c_rsp_ready;
 wire barrier=(pending_i||pending_d)&&owners==0&&!request_full&&!response_full&&!fault;
 // Deliberately omit full+pop turnover: space and response validity depend
 // on registers only. Payload reset is unnecessary while validity is clear.
 assign c_ready=!rst&&!fault&&!request_full&&owners!=3&&
                !pending_i&&!pending_d&&!c_fence_i&&!c_fence_d;
 assign m_valid=!rst&&!fault&&request_full;
 assign m_rsp_ready=!rst&&!fault&&!response_full;
 assign c_rsp_valid=!rst&&!fault&&response_full;
 assign m_fence_i=barrier&&pending_i;
 assign m_fence_d=barrier&&pending_d;
 // Stop post-FENCE fetch admission during the drain/forward gap. Already
 // accepted old-epoch I responses still drain through the original frontend.
 assign barrier_pending=c_fence_i||c_fence_d||pending_i||pending_d;
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  if(push)begin m_addr<=c_addr;m_wdata<=c_wdata;m_strobe<=c_strobe;m_size<=c_size;m_write<=c_write;end
  if(receive)begin c_rdata<=m_rdata;c_rsp_error<=m_rsp_error;end
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin request_full<=0;response_full<=0;pending_i<=0;pending_d<=0;owners<=0;fault<=0;end
  else begin
   if(take)request_full<=0;
   if(push)request_full<=1;
   if(consume)response_full<=0;
   if(receive)response_full<=1;
   // 按 {push,consume} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case({push,consume})
    2'b10:owners<=owners+1'b1;
    2'b01:owners<=owners-1'b1;
    default:;
   endcase
   if(barrier)begin pending_i<=0;pending_d<=0;end
   if(c_fence_i)pending_i<=1;
   if(c_fence_d)pending_d<=1;
   if((receive&&owners==0)||(consume&&owners==0))fault<=1;
  end
 end
`ifdef VERILATOR
 // 过程边界：always @(posedge clk)if(!rst)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always @(posedge clk)if(!rst)begin
  if(consume&&owners==0)$fatal(1,"RV32 registered D boundary response without owner");
  if((m_fence_i||m_fence_d)&&(owners!=0||request_full||response_full))$fatal(1,"RV32 registered D boundary FENCE overtook transaction");
 end
`endif
endmodule
