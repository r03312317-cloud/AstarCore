// Optional board peripheral window. One owner is held until its response is
// consumed. All signals are synchronous to cpu_clk; CDC belongs downstream.
// 架构导读：soc_board_mmio_router。
// 依据地址把 CPU 板级访问路由到相应外设寄存器。
module soc_board_mmio_router #(
 // 静态配置：parameter logic [31:0] BOARD_BASE=32'h60001000。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter logic [31:0] BOARD_BASE=32'h60001000
)(
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 input logic req_valid,output logic req_ready,
 input logic [31:0] req_addr,req_wdata,
 input logic req_write,req_is_fetch,input logic [3:0] req_wstrb,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_rdata,output logic rsp_error,
 output logic [1:0] m_req_valid,input logic [1:0] m_req_ready,
 output logic [31:0] m_req_addr,m_req_wdata,
 output logic m_req_write,m_req_is_fetch,output logic [3:0] m_req_wstrb,
 input logic [1:0] m_rsp_valid,output logic [1:0] m_rsp_ready,
 input logic [1:0][31:0] m_rsp_rdata,input logic [1:0] m_rsp_error
);
 logic busy,owner;
 wire select_board=req_addr[31:12]==BOARD_BASE[31:12];
 assign m_req_addr=req_addr;
 assign m_req_wdata=req_wdata;
 assign m_req_write=req_write;
 assign m_req_is_fetch=req_is_fetch;
 assign m_req_wstrb=req_wstrb;
 assign m_req_valid=(!rst&&!busy&&req_valid)?(select_board?2'b10:2'b01):2'b00;
 assign req_ready=!rst&&!busy&&m_req_ready[select_board];
 assign rsp_valid=!rst&&busy&&m_rsp_valid[owner];
 assign rsp_rdata=m_rsp_rdata[owner];
 assign rsp_error=m_rsp_error[owner];
 assign m_rsp_ready=(!rst&&busy&&rsp_ready)?(owner?2'b10:2'b01):2'b00;
 // 过程边界：always_ff @(posedge clk) begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk) begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin busy<=0;owner<=0;end
  else begin
   // 握手/背压判断：req_valid&&req_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(req_valid&&req_ready)begin busy<=1;owner<=select_board;end
   // 握手/背压判断：rsp_valid&&rsp_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(rsp_valid&&rsp_ready)busy<=0;
  end
 end
endmodule
