// SPDX-License-Identifier: MIT
// Single outstanding 32-bit request. req_valid/req_ready commits side effects once.
// rsp_* is held until rsp_ready; unknown or unaligned addresses return an error.
// 此模块对 Linux 使用的 MMIO 地址做片选，并汇总各从设备响应。
// UART 接收状态经 PLIC 转为机器或监督外部中断，CLINT 提供软件与定时中断。
// framebuffer 寄存器记录软件希望显示的帧地址，帧边界提交由视频路径完成。
// 未命中的地址必须返回错误，不能伪装成成功的零数据读取。
// 响应有独立有效状态；请求接收与响应消费须分别观察，避免重复访问副作用。
// 时间基准由 TIMER_DIV 决定，本版板级传入 27 得到 1 MHz mtime。
module rv32_linux_peripherals #(parameter TIMER_DIV=100,UART_DIV=868)(
 // req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input clk,reset,input req_valid,output req_ready,input req_write,
 // req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
 input [31:0] req_addr,req_wdata,input [3:0] req_wstrb,
 // rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output rsp_valid,input rsp_ready,output [31:0] rsp_rdata,output rsp_error,
 input uart_rx,output uart_tx,input vblank,
 // fb_base 软件提交的 framebuffer 地址，进入显示域前还需完整提交握手。
 output [31:0] fb_base,output fb_enable,output [63:0] mtime,
 output irq_timer,irq_software,irq_external_m,irq_external_s
);
 reg busy;reg [2:0] owner;wire [2:0] sel;
 assign sel=req_addr[1:0]!=0?3'd4:
  req_addr[31:16]==16'h0200 ? 3'd0:
  req_addr[31:22]==10'h030 ? 3'd1:
  req_addr[31:8]==24'h100000 ? 3'd2:
  req_addr[31:8]==24'h100010 ? 3'd3:3'd4;
 wire [3:0] qr,rv,re;wire [31:0] rd0,rd1,rd2,rd3;wire uart_irq,fb_irq;
 assign req_ready=!busy&&((sel==4)?1'b1:qr[sel[1:0]]);
 assign rsp_valid=busy&&((owner==4)?1'b1:rv[owner[1:0]]);
 assign rsp_error=owner==4?1'b1:re[owner[1:0]];
 assign rsp_rdata=owner==0?rd0:owner==1?rd1:owner==2?rd2:owner==3?rd3:32'd0;
 always @(posedge clk)begin
  // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
  if(reset)begin busy<=0;owner<=4;end
  else begin
   // 本分支处理握手条件 rsp_valid 与 rsp_ready；仅满足当前条件时推进下述事务。
   if(rsp_valid&&rsp_ready)busy<=0;
   if(req_valid&&req_ready)begin busy<=1;owner<=sel;end
  end
 end
 // 子模块 rv32_clint 的职责：CLINT 保存 mtime mtimecmp 和软件中断状态，向单 hart 提供本地中断源。
 // 下列命名端口把本层信号连接到该模块，参数覆盖以实例中的原代码为准。
 rv32_clint #(.TICK_DIV(TIMER_DIV)) timer(
  .clk(clk),.reset(reset),.req_valid(req_valid&&!busy&&sel==0),.req_ready(qr[0]),.req_write(req_write),
  .req_addr(req_addr[15:0]),.req_wdata(req_wdata),.req_wstrb(req_wstrb),.rsp_valid(rv[0]),
  .rsp_ready(busy&&owner==0&&rsp_ready),.rsp_rdata(rd0),.rsp_error(re[0]),.mtime(mtime),.irq_timer(irq_timer),.irq_software(irq_software));
 // 子模块 rv32_plic 的职责：PLIC 汇总外设中断并根据使能 优先级和阈值为 M S 上下文提出外部中断。
 rv32_plic interrupts(
  .clk(clk),.reset(reset),.sources({2'b0,fb_irq,uart_irq}),.req_valid(req_valid&&!busy&&sel==1),.req_ready(qr[1]),.req_write(req_write),
  .req_addr(req_addr[21:0]),.req_wdata(req_wdata),.req_wstrb(req_wstrb),.rsp_valid(rv[1]),
  .rsp_ready(busy&&owner==1&&rsp_ready),.rsp_rdata(rd1),.rsp_error(re[1]),.irq_m(irq_external_m),.irq_s(irq_external_s));
 // 子模块 rv32_uart 的职责：UART 用输入时钟分频生成串行节拍，对外为 8N1 字节流。
 rv32_uart #(.RESET_DIVISOR(UART_DIV)) serial(
  .clk(clk),.reset(reset),.rx(uart_rx),.tx(uart_tx),.req_valid(req_valid&&!busy&&sel==2),.req_ready(qr[2]),.req_write(req_write),
  .req_addr(req_addr[7:0]),.req_wdata(req_wdata),.req_wstrb(req_wstrb),.rsp_valid(rv[2]),
  .rsp_ready(busy&&owner==2&&rsp_ready),.rsp_rdata(rd2),.rsp_error(re[2]),.irq(uart_irq));
 // 子模块 rv32_framebuffer 的职责：framebuffer MMIO 接口在软件与显示控制器之间保存帧地址和显示使能。
 rv32_framebuffer display(
  .clk(clk),.reset(reset),.vblank(vblank),.req_valid(req_valid&&!busy&&sel==3),.req_ready(qr[3]),.req_write(req_write),
  .req_addr(req_addr[7:0]),.req_wdata(req_wdata),.req_wstrb(req_wstrb),.rsp_valid(rv[3]),
  .rsp_ready(busy&&owner==3&&rsp_ready),.rsp_rdata(rd3),.rsp_error(re[3]),.active_base(fb_base),.active_enable(fb_enable),.irq(fb_irq));
endmodule
