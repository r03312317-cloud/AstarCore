// SPDX-License-Identifier: MIT
// Single-hart CLINT-compatible register layout; little-endian 32-bit accesses.
// CLINT 保存 mtime mtimecmp 和软件中断状态，向单 hart 提供本地中断源。
// mtime 的节拍来自输入时钟分频，本版 27 MHz 除以 27 后形成 1 MHz 基准。
// 32 位总线访问 64 位计数器时，高低字是分开的寄存器访问。
// 中断输出依赖比较与使能状态，清中断通常需要软件更新比较值或软件中断位。
module rv32_clint #(parameter TICK_DIV=100)(
 // req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input clk,reset,input req_valid,output req_ready,input req_write,
 // req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
 input [15:0] req_addr,input [31:0] req_wdata,input [3:0] req_wstrb,
 // rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output reg rsp_valid,input rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,
 output [63:0] mtime,output irq_timer,output irq_software
);
 reg [63:0] time_reg,compare_reg; reg software_reg; reg [31:0] tick;
 // mtime 连接到 time_reg，两者在此路径上保持字段对应。
 assign mtime=time_reg; assign irq_timer=time_reg>=compare_reg;
 // irq_software 连接到 software_reg，两者在此路径上保持字段对应。
 assign irq_software=software_reg; assign req_ready=!rsp_valid||rsp_ready;
 integer i;
 always @(posedge clk) begin
  // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
  if(reset)begin time_reg<=0;compare_reg<=64'hffffffffffffffff;software_reg<=0;tick<=0;rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;end
  else begin
   if(tick==TICK_DIV-1)begin tick<=0;time_reg<=time_reg+1'b1;end else tick<=tick+1'b1;
   // 本分支处理握手条件 rsp_valid 与 rsp_ready；仅满足当前条件时推进下述事务。
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   // 本分支处理握手条件 req_valid 与 req_ready；仅满足当前条件时推进下述事务。
   if(req_valid&&req_ready)begin
    rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;
    case(req_addr)
     16'h0000:begin rsp_rdata<={31'd0,software_reg};if(req_write&&req_wstrb[0])software_reg<=req_wdata[0];end
     16'h4000:begin rsp_rdata<=compare_reg[31:0];if(req_write)for(i=0;i<4;i=i+1)if(req_wstrb[i])compare_reg[i*8+:8]<=req_wdata[i*8+:8];end
     16'h4004:begin rsp_rdata<=compare_reg[63:32];if(req_write)for(i=0;i<4;i=i+1)if(req_wstrb[i])compare_reg[32+i*8+:8]<=req_wdata[i*8+:8];end
     16'hbff8:begin rsp_rdata<=time_reg[31:0];if(req_write)for(i=0;i<4;i=i+1)if(req_wstrb[i])time_reg[i*8+:8]<=req_wdata[i*8+:8];end
     16'hbffc:begin rsp_rdata<=time_reg[63:32];if(req_write)for(i=0;i<4;i=i+1)if(req_wstrb[i])time_reg[32+i*8+:8]<=req_wdata[i*8+:8];end
     default:rsp_error<=1;
    endcase
   end
  end
 end
endmodule
