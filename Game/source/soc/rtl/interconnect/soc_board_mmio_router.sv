// [ARCH] 根据地址选择板级外设窗口，并将对应响应送回 CPU。
// [ARCH] 未命中合法窗口应产生可诊断的错误结果。
// [ARCH] 等待响应期间保持选择归属，不使用下一请求的地址改路由。
// [ARCH] 具体寄存器副作用由目标外设定义。
// Optional board peripheral window. One owner is held until its response is
// consumed. All signals are synchronous to cpu_clk; CDC belongs downstream.
module soc_board_mmio_router #(
 parameter logic [31:0] BOARD_BASE=32'h60001000
)(
 // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
 input logic clk,rst,
 // [ARCH] req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_req_valid, busy, owner 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic req_valid,output logic req_ready,
 // [ARCH] req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 select_board, m_req_addr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic [31:0] req_addr,req_wdata,
 // [ARCH] req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_req_write 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic req_write,req_is_fetch,input logic [3:0] req_wstrb,
 // [ARCH] rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 busy 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic rsp_valid,input logic rsp_ready,
 // [ARCH] rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 output logic [31:0] rsp_rdata,output logic rsp_error,
 // [ARCH] m_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic [1:0] m_req_valid,input logic [1:0] m_req_ready,
 // [ARCH] m_req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic [31:0] m_req_addr,m_req_wdata,
 // [ARCH] m_req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic m_req_write,m_req_is_fetch,output logic [3:0] m_req_wstrb,
 // [ARCH] m_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic [1:0] m_rsp_valid,output logic [1:0] m_rsp_ready,
 // [ARCH] m_rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
 always_ff @(posedge clk) begin
  if(rst)begin busy<=0;owner<=0;end
  else begin
   if(req_valid&&req_ready)begin busy<=1;owner<=select_board;end
   if(rsp_valid&&rsp_ready)busy<=0;
  end
 end
endmodule
