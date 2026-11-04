// One accepted transaction owns its response through arbitrary backpressure.
// Register both ingress and response; no new long CPU->MMIO combinational path.
// 架构导读：soc_mmio_2m_registered。
// 两主机 MMIO 的寄存级仲裁，隔离组合路径并保留应答归属。
module soc_mmio_2m_registered(
 input logic clk,rst,
 input logic [1:0] s_req_valid, output logic [1:0] s_req_ready,
 input logic [1:0][31:0] s_req_addr,s_req_wdata,
 input logic [1:0] s_req_write,s_req_fetch,input logic [1:0][3:0] s_req_wstrb,
 output logic [1:0] s_rsp_valid,input logic [1:0] s_rsp_ready,
 output logic [1:0][31:0] s_rsp_rdata,output logic [1:0] s_rsp_error,
 output logic m_req_valid,input logic m_req_ready,
 output logic [31:0] m_req_addr,m_req_wdata,
 output logic m_req_write,m_req_fetch,output logic [3:0] m_req_wstrb,
 input logic m_rsp_valid,output logic m_rsp_ready,
 input logic [31:0] m_rsp_rdata,input logic m_rsp_error
);
 // 静态配置：localparam [1:0] IDLE=0,ISSUE=1,WAIT_RSP=2,RETURN_RSP=3。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 localparam [1:0] IDLE=0,ISSUE=1,WAIT_RSP=2,RETURN_RSP=3;
 logic [1:0] state;logic owner,prefer,selected;
 logic [31:0] response;logic response_error;
 // 过程边界：always_comb begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_comb begin
  selected=s_req_valid[prefer]?prefer:~prefer;
  s_req_ready=0;s_rsp_valid=0;s_rsp_error=0;
  s_rsp_rdata[0]=response;s_rsp_rdata[1]=response;
  m_req_valid=!rst&&state==ISSUE;m_rsp_ready=!rst&&state==WAIT_RSP;
  // 复位相关判断：!rst&&state==IDLE；分支方向由信号极性与取反表达式决定。
  if(!rst&&state==IDLE)s_req_ready[selected]=1;
  // 复位相关判断：!rst&&state==RETURN_RSP；分支方向由信号极性与取反表达式决定。
  if(!rst&&state==RETURN_RSP)begin s_rsp_valid[owner]=1;s_rsp_error[owner]=response_error;end
 end
 // 过程边界：always_ff @(posedge clk) begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk) begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin
   state<=IDLE;owner<=0;prefer<=0;response<=0;response_error<=0;
   m_req_addr<=0;m_req_wdata<=0;m_req_write<=0;m_req_fetch<=0;m_req_wstrb<=0;
  end else case(state)
   // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
   IDLE:if(s_req_valid[selected])begin
    owner<=selected;prefer<=~selected;m_req_addr<=s_req_addr[selected];
    m_req_wdata<=s_req_wdata[selected];m_req_write<=s_req_write[selected];
    m_req_fetch<=s_req_fetch[selected];m_req_wstrb<=s_req_wstrb[selected];state<=ISSUE;
   end
   // 状态/选择分支 ISSUE：本分支规定该编码下的寄存器更新和下一步动作。
   ISSUE:if(m_req_ready)state<=WAIT_RSP;
   // 状态/选择分支 WAIT_RSP：本分支规定该编码下的寄存器更新和下一步动作。
   WAIT_RSP:if(m_rsp_valid)begin response<=m_rsp_rdata;response_error<=m_rsp_error;state<=RETURN_RSP;end
   // 状态/选择分支 RETURN_RSP：本分支规定该编码下的寄存器更新和下一步动作。
   RETURN_RSP:if(s_rsp_ready[owner])state<=IDLE;
  endcase
 end
endmodule
