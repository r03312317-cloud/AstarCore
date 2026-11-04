// [ARCH] 外设跨域必须保证一次软件事务只产生一次目标副作用。
// [ARCH] 请求和应答分别跨域，等待时保持地址与写载荷。
// [ARCH] 目标背压不能导致同一次写重复提交。
// [ARCH] 两端复位协议决定中断事务后的恢复状态。
// Full single-owner MMIO request/response CDC. Doorbells, W1C and reads with
// side effects cross exactly once. The existing legacy bridge stays entirely
// in dst_clk; its fixed ISSUE/WAIT states and write pulse never cross a clock.
// [ARCH] 源域请求保持到目标域确认。
// [ARCH] 目标域只对同一请求执行一次寄存器副作用。
// [ARCH] 返回确认经过同步后，源端才可接受下一份可覆盖载荷。
// [ARCH] 不要用普通两级同步器逐位传送这组多比特数据。
module pg_mmio_cdc (
 input logic src_clk,dst_clk,arst,
 // [ARCH] s_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 busy_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic s_req_valid,output logic s_req_ready,input logic[15:0] s_req_addr,
 // [ARCH] s_req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 input logic s_req_write,input logic[31:0] s_req_wdata,input logic[3:0] s_req_wstrb,
 // [ARCH] s_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 busy_q, rsp_hold_valid_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic s_rsp_valid,input logic s_rsp_ready,output logic[31:0] s_rsp_rdata,
 // [ARCH] s_rsp_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
 output logic s_rsp_error,
 // [ARCH] m_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic m_req_valid,input logic m_req_ready,output logic[15:0] m_req_addr,
 // [ARCH] m_req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic m_req_write,output logic[31:0] m_req_wdata,output logic[3:0] m_req_wstrb,
 // [ARCH] m_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 input logic m_rsp_valid,output logic m_rsp_ready,input logic[31:0] m_rsp_rdata,
 // [ARCH] m_rsp_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
 input logic m_rsp_error
);
 timeunit 1ns;timeprecision 1ps;
 // [ARCH] src_rst：参与本域复位/就绪控制，释放条件与跨域同步链一起检查。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_req_ready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic src_rst,busy_q,req_ready_local,rsp_valid_local;
 // [ARCH] rsp_hold_valid_q：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rsp_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic rsp_hold_valid_q,rsp_hold_error_q;
 // [ARCH] rsp_hold_rdata_q：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rsp_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic [31:0] rsp_hold_rdata_q,rsp_rdata_local;
 // [ARCH] rsp_error_local：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_hold_error_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 logic rsp_error_local;
 pg_reset_sync release_src(.clk(src_clk),.arst,.rst(src_rst));
 assign s_req_ready=!src_rst&&!busy_q&&req_ready_local;
 // Register the returned response in the source domain before it reaches the
 // SoC response router and CPU control. This is a one-owner, one-entry stage:
 // the FIFO cannot pop again until the previous response is consumed.
 assign s_rsp_valid=rsp_hold_valid_q;
 assign s_rsp_rdata=rsp_hold_rdata_q;
 assign s_rsp_error=rsp_hold_error_q;
 always_ff @(posedge src_clk or posedge src_rst)
  if(src_rst)begin
   busy_q<=0;
   rsp_hold_valid_q<=0;
   rsp_hold_rdata_q<=0;
   rsp_hold_error_q<=0;
  end
  else begin
   if(s_req_valid&&s_req_ready)busy_q<=1;
   if(s_rsp_valid&&s_rsp_ready)busy_q<=0;
   if(rsp_valid_local&&!rsp_hold_valid_q&&busy_q)begin
    rsp_hold_valid_q<=1;
    rsp_hold_rdata_q<=rsp_rdata_local;
    rsp_hold_error_q<=rsp_error_local;
   end
   else if(s_rsp_valid&&s_rsp_ready)rsp_hold_valid_q<=0;
  end
 pg_async_fifo_dc #(.WIDTH(53),.DEPTH(2)) req_fifo(
  .wr_clk(src_clk),.rd_clk(dst_clk),.arst,
  .in_valid(s_req_valid&&!busy_q&&!src_rst),.in_ready(req_ready_local),
  .in_data({s_req_addr,s_req_write,s_req_wdata,s_req_wstrb}),
  .out_valid(m_req_valid),.out_ready(m_req_ready),
  .out_data({m_req_addr,m_req_write,m_req_wdata,m_req_wstrb}));
 pg_async_fifo_dc #(.WIDTH(33),.DEPTH(2)) rsp_fifo(
  .wr_clk(dst_clk),.rd_clk(src_clk),.arst,
  .in_valid(m_rsp_valid),.in_ready(m_rsp_ready),
  .in_data({m_rsp_error,m_rsp_rdata}),
  .out_valid(rsp_valid_local),.out_ready(!rsp_hold_valid_q&&busy_q&&!src_rst),
  .out_data({rsp_error_local,rsp_rdata_local}));
 // synthesis translate_off
 always @(posedge src_clk)if(!src_rst&&rsp_valid_local&&!busy_q)
  $fatal(1,"CP6_MMIO_UNOWNED_RESPONSE_RED");
 // synthesis translate_on
endmodule
