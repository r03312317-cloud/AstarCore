// [ARCH] 把 CPU 与内存域的请求和响应隔离成有明确归属的跨域事务。
// [ARCH] 载荷要按协议保持，不能只同步一个 valid 后直接采样变化的数据总线。
// [ARCH] 源端仅在协议允许时才能替换待传载荷。
// [ARCH] 复位后重新建立空闲状态，旧确认不能冒充新响应。
// [ARCH] 吞吐受跨域往返与排队能力共同限制。
// Protocol-preserving memory channel: no completion is manufactured here.
// IDs are allocated/released by the ORIGINAL source and destination owners.
// A FIFO enqueue acknowledges only this interface, never DDR write completion.
module pg_memory_cdc #(parameter int DATA_W=128,ID_W=4,DEPTH=8,parameter bit REGISTER_RSP_OUTPUT=1'b0)(
 input logic src_clk,dst_clk,arst,
 // [ARCH] s_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 input logic s_req_valid,output logic s_req_ready,input logic s_req_write,
 // [ARCH] s_req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 input logic[31:0] s_req_addr,input logic[DATA_W-1:0] s_req_wdata,
 // [ARCH] s_req_wstrb：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 input logic[DATA_W/8-1:0] s_req_wstrb,input logic[ID_W-1:0] s_req_id,
 // [ARCH] s_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 output logic s_rsp_valid,input logic s_rsp_ready,output logic s_rsp_write,s_rsp_error,
 // [ARCH] s_rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 output logic[DATA_W-1:0] s_rsp_rdata,output logic[ID_W-1:0] s_rsp_id,
 // [ARCH] m_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic m_req_valid,input logic m_req_ready,output logic m_req_write,
 // [ARCH] m_req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic[31:0] m_req_addr,output logic[DATA_W-1:0] m_req_wdata,
 // [ARCH] m_req_wstrb：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic[DATA_W/8-1:0] m_req_wstrb,output logic[ID_W-1:0] m_req_id,
 // [ARCH] m_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 input logic m_rsp_valid,output logic m_rsp_ready,input logic m_rsp_write,m_rsp_error,
 // [ARCH] m_rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 input logic[DATA_W-1:0] m_rsp_rdata,input logic[ID_W-1:0] m_rsp_id
);
 timeunit 1ns;timeprecision 1ps;
 // [ARCH] REQ_W：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 localparam int REQ_W=1+32+DATA_W+DATA_W/8+ID_W;
 localparam int RSP_W=2+DATA_W+ID_W;
 // [ARCH] rsp_fifo_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 pipe_valid_q, pipe_data_q, s_rsp_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic rsp_fifo_valid,rsp_fifo_ready;
 // [ARCH] rsp_fifo_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 pipe_data_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
  // [ARCH] pipe_valid_q：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
  // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_fifo_ready, s_rsp_valid, pipe_data_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
  logic pipe_valid_q;
  // [ARCH] pipe_data_q：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
  // [ARCH] 定位线索：原版中含此标识符的物理行还对 pipe_valid_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
  logic [RSP_W-1:0] pipe_data_q;
  assign rsp_fifo_ready=!pipe_valid_q||s_rsp_ready;
  assign s_rsp_valid=pipe_valid_q;
  assign {s_rsp_write,s_rsp_error,s_rsp_rdata,s_rsp_id}=pipe_data_q;
  always_ff @(posedge src_clk or posedge arst)begin
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
