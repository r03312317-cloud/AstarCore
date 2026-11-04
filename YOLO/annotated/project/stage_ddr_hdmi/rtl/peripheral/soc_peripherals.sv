// 架构导读：soc_peripherals。
// 连接 UART、GPIO、定时器等 CPU 控制外设。
`timescale 1ns/1ps
// 四级 CPU 的旧 Timer/UART 不改；CP13 外设在 0x60000000 独立窗口。
// GPIO/mailbox 保留 R2 的 0x50000000 别名。任何请求恰好一次响应。
module soc_peripherals #(
 // 静态配置：parameter integer CLK_FREQ=170000000, BAUD_RATE=115200。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer CLK_FREQ=170000000, BAUD_RATE=115200
)(
 // 接口声明：input logic clk,rst,req_valid,req_write,req_is_fetch。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic clk,rst,req_valid,req_write,req_is_fetch,
 // 接口声明：input logic [31:0] req_addr,req_wdata,input logic [3:0] req_wstrb。
 // 按字节选择本次写入生效的 lane。
 input logic [31:0] req_addr,req_wdata,input logic [3:0] req_wstrb,
 output logic req_ready,rsp_valid,rsp_error,output logic [31:0] rsp_rdata,input logic rsp_ready,
 input logic [31:0] gpio_in,output logic [31:0] gpio_out,diagnostic_mailbox,
 output logic uart_tx,input logic uart_rx,output logic uart_aux_tx,
 output logic [63:0] timer_gray
);
 logic legacy_ready,legacy_valid,legacy_error,pg_ready,pg_valid,pg_error;
 logic [31:0] legacy_data,pg_data,pg_addr;
 logic select_pg,alias_gpio,busy;
 assign alias_gpio=req_addr[31:12]==20'h50000;
 assign select_pg=alias_gpio||(req_addr[31:12]==20'h60000);
 // 未定义的 GPIO 别名映射到 CP13 的未定义字，确保返回 error。
 always_comb begin
  pg_addr={20'h30000,req_addr[11:0]};
  if(alias_gpio) case(req_addr[11:0])
   12'h000:pg_addr=32'h30000010;
   12'h004:pg_addr=32'h30000014;
   12'h0fc:pg_addr=32'h300000fc;
   default:pg_addr=32'h30000ffc;
  endcase
 end
 assign req_ready=!rst&&!busy&&(select_pg?pg_ready:legacy_ready);
 assign rsp_valid=!rst&&(pg_valid||legacy_valid);
 assign rsp_rdata=pg_valid?pg_data:legacy_data;
 assign rsp_error=pg_valid?pg_error:legacy_error;
 core0_system_fabric #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD_RATE)) legacy(
  .clk,.rst,.req_valid(req_valid&&!busy&&!select_pg),.req_ready(legacy_ready),
  .req_addr,.req_write,.req_wdata,.req_wstrb,.req_is_fetch,
  .rsp_valid(legacy_valid),.rsp_ready(rsp_ready&&!pg_valid),.rsp_rdata(legacy_data),.rsp_error(legacy_error),.uart_tx);
 pg_cpu_peripherals #(.CLOCK_HZ(CLK_FREQ),.UART_CLKS_PER_BIT((CLK_FREQ+BAUD_RATE/2)/BAUD_RATE),.UART_RX_DEPTH(128)) cp13(
  .clk,.rst,.req_valid(req_valid&&!busy&&select_pg),.req_ready(pg_ready),
  .req_addr(pg_addr),.req_write,.req_wdata,.req_wstrb,.req_is_fetch,
  .rsp_valid(pg_valid),.rsp_ready(rsp_ready&&!legacy_valid),.rsp_rdata(pg_data),.rsp_error(pg_error),
  .gpio_in,.gpio_out,.diagnostic_mailbox,.uart_rx,.uart_tx(uart_aux_tx),.timer_gray);
 // 过程边界：always_ff @(posedge clk) begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk) begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)busy<=0;
  else begin
   // 握手/背压判断：rsp_valid&&rsp_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(rsp_valid&&rsp_ready)busy<=0;
   // 握手/背压判断：req_valid&&req_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(req_valid&&req_ready)busy<=1;
  end
 end
 // synthesis translate_off
 always_ff @(posedge clk)if(!rst&&legacy_valid&&pg_valid)$fatal(1,"R3_MMIO_DOUBLE_RESPONSE");
 // synthesis translate_on
endmodule
