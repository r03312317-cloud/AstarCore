// Protocol-preserving memory channel: no completion is manufactured here.
// IDs are allocated/released by the ORIGINAL source and destination owners.
// A FIFO enqueue acknowledges only this interface, never DDR write completion.
// 架构导读：pg_memory_cdc。
// 时钟域间控制/数据传输接口，使用本模块定义的同步和所有权约束。
module pg_memory_cdc #(parameter int DATA_W=128,ID_W=4,DEPTH=8,parameter bit REGISTER_RSP_OUTPUT=1'b0)(
 // 接口声明：input logic src_clk,dst_clk,arst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic src_clk,dst_clk,arst,
 // 接口声明：input logic s_req_valid,output logic s_req_ready,input logic s_req_write。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic s_req_valid,output logic s_req_ready,input logic s_req_write,
 // 接口声明：input logic[31:0] s_req_addr,input logic[DATA_W-1:0] s_req_wdata。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 input logic[31:0] s_req_addr,input logic[DATA_W-1:0] s_req_wdata,
 // 接口声明：input logic[DATA_W/8-1:0] s_req_wstrb,input logic[ID_W-1:0] s_req_id。
 // 把返回信息关联到对应的已接受请求。
 input logic[DATA_W/8-1:0] s_req_wstrb,input logic[ID_W-1:0] s_req_id,
 // 接口声明：output logic s_rsp_valid,input logic s_rsp_ready,output logic s_rsp_write,s_rsp_error。
 output logic s_rsp_valid,input logic s_rsp_ready,output logic s_rsp_write,s_rsp_error,
 output logic[DATA_W-1:0] s_rsp_rdata,output logic[ID_W-1:0] s_rsp_id,
 output logic m_req_valid,input logic m_req_ready,output logic m_req_write,
 output logic[31:0] m_req_addr,output logic[DATA_W-1:0] m_req_wdata,
 output logic[DATA_W/8-1:0] m_req_wstrb,output logic[ID_W-1:0] m_req_id,
 input logic m_rsp_valid,output logic m_rsp_ready,input logic m_rsp_write,m_rsp_error,
 input logic[DATA_W-1:0] m_rsp_rdata,input logic[ID_W-1:0] m_rsp_id
);
 timeunit 1ns;timeprecision 1ps;
 // 静态配置：localparam int REQ_W=1+32+DATA_W+DATA_W/8+ID_W。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam int REQ_W=1+32+DATA_W+DATA_W/8+ID_W;
 // 静态配置：localparam int RSP_W=2+DATA_W+ID_W。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam int RSP_W=2+DATA_W+ID_W;
 logic rsp_fifo_valid,rsp_fifo_ready;
 logic [RSP_W-1:0] rsp_fifo_data;
 pg_async_fifo_dc #(.WIDTH(REQ_W),.DEPTH(DEPTH)) req_fifo(
  .wr_clk(src_clk),.rd_clk(dst_clk),.arst,
  .in_valid(s_req_valid),.in_ready(s_req_ready),
  .in_data({s_req_write,s_req_addr,s_req_wdata,s_req_wstrb,s_req_id}),
  .out_valid(m_req_valid),.out_ready(m_req_ready),
  .out_data({m_req_write,m_req_addr,m_req_wdata,m_req_wstrb,m_req_id}));
 pg_async_fifo_dc #(.WIDTH(RSP_W),.DEPTH(DEPTH)) rsp_fifo(
  .wr_clk(dst_clk),.rd_clk(src_clk),.arst,
  .in_valid(m_rsp_valid),.in_ready(m_rsp_ready),
  .in_data({m_rsp_write,m_rsp_error,m_rsp_rdata,m_rsp_id}),
  .out_valid(rsp_fifo_valid),.out_ready(rsp_fifo_ready),
  .out_data(rsp_fifo_data));
 generate if(REGISTER_RSP_OUTPUT)begin:g_registered_rsp
  logic pipe_valid_q;
  logic [RSP_W-1:0] pipe_data_q;
  assign rsp_fifo_ready=!pipe_valid_q||s_rsp_ready;
  assign s_rsp_valid=pipe_valid_q;
  assign {s_rsp_write,s_rsp_error,s_rsp_rdata,s_rsp_id}=pipe_data_q;
  // 过程边界：always_ff @(posedge src_clk or posedge arst)begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge src_clk or posedge arst)begin
   // 复位相关判断：arst；分支方向由信号极性与取反表达式决定。
   if(arst)begin pipe_valid_q<=1'b0;pipe_data_q<='0;end
   else if(rsp_fifo_ready)begin
    pipe_valid_q<=rsp_fifo_valid;
    if(rsp_fifo_valid)pipe_data_q<=rsp_fifo_data;
   end
  end
 end else begin:g_direct_rsp
  assign rsp_fifo_ready=s_rsp_ready;
  assign s_rsp_valid=rsp_fifo_valid;
  assign {s_rsp_write,s_rsp_error,s_rsp_rdata,s_rsp_id}=rsp_fifo_data;
 end endgenerate
 initial if(DATA_W<8||DATA_W%8!=0||ID_W<1)$fatal(1,"CP6_MEMORY_CDC_PARAM_RED");
endmodule
