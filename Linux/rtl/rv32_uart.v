// SPDX-License-Identifier: MIT
// Custom rv32,uart-v1, 8N1. NOT an ns16550-compatible controller.
// UART 用输入时钟分频生成串行节拍，对外为 8N1 字节流。
// 异步 RX 先经同步链，再按位中心采样，避免直接把引脚作为同步逻辑条件。
// 发送忙与接收有效具有各自生命周期，读数据和写数据可能带有握手副作用。
// 本版板级 UART_DIV 为 234，对应约 115200 波特的串口配置。
// 浅接收缓冲由主机逐字节等待回显配合，不能把主机整行突发视为无限容量。
module rv32_uart #(parameter RESET_DIVISOR=868)(
 // req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input clk,reset,input rx,output tx,input req_valid,output req_ready,input req_write,
 // req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
 input [7:0] req_addr,input [31:0] req_wdata,input [3:0] req_wstrb,
 // rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output reg rsp_valid,input rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,
 output irq
);
 // control 保存控制流类别或控制位，供目标选择和分支结果处理使用。
 reg [1:0] control,irq_enable;reg [31:0] divisor;
 reg tx_busy;reg [9:0] tx_shift;reg [3:0] tx_bit;reg [31:0] tx_count,tx_div;
 (* PAP_ASYNC_REG=1, syn_preserve=1 *) reg [1:0] rx_sync;reg rx_busy;reg [3:0] rx_bit;reg [31:0] rx_count,rx_div;
 reg [7:0] rx_shift,rx_data;reg rx_full,rx_overrun,rx_framing;
 // take 的资格组合为 req_valid&&req_ready。
 // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
 wire take=req_valid&&req_ready;
 // rx_pop 的资格组合为 take&&!req_write&&req_addr==8'h04。
 wire rx_pop=take&&!req_write&&req_addr==8'h04;
 // rx_finish 的资格组合为 rx_busy&&(rx_bit==9)&&(rx_count==rx_div-1)。
 wire rx_finish=rx_busy&&(rx_bit==9)&&(rx_count==rx_div-1);
 // new_framing 的资格组合为 rx_finish&&!rx_sync[1]。
 wire new_framing=rx_finish&&!rx_sync[1];
 // new_overrun 的资格组合为 rx_finish&&rx_sync[1]&&rx_full&&!rx_pop。
 wire new_overrun=rx_finish&&rx_sync[1]&&rx_full&&!rx_pop;
 // tx 按 tx_busy 进行来源选择。
 // 真分支取 tx_shift[0]；其余情况取 1'b1。
 assign tx=tx_busy?tx_shift[0]:1'b1;
 // irq 的资格组合为 (irq_enable[0]&&rx_full)||(irq_enable[1]&&!tx_busy&&control[0])。
 assign irq=(irq_enable[0]&&rx_full)||(irq_enable[1]&&!tx_busy&&control[0]);
 // req_ready 的资格组合为 !rsp_valid||rsp_ready。
 assign req_ready=!rsp_valid||rsp_ready;
 always @(posedge clk)begin
  // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
  if(reset)begin
   // control 在此时钟更新路径捕获 3，该更新仍受外层条件与后续同块赋值优先级限定。
   // 本时钟边界的 control 捕获 3，两者在此路径上保持字段对应。
   control<=3;irq_enable<=0;divisor<=RESET_DIVISOR;
   tx_busy<=0;tx_shift<=10'h3ff;tx_bit<=0;tx_count<=0;tx_div<=RESET_DIVISOR;
   // 本时钟边界的 rx_sync 捕获 3，两者在此路径上保持字段对应。
   rx_sync<=3;rx_busy<=0;rx_bit<=0;rx_count<=0;rx_div<=RESET_DIVISOR;
   rx_shift<=0;rx_data<=0;rx_full<=0;rx_overrun<=0;rx_framing<=0;
   rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
  end else begin
   // 本时钟边界的 rx_sync 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
   // 拼接源为 {rx_sync[0],rx}；复制大括号表示重复位域，不是独立队列元素。
   rx_sync<={rx_sync[0],rx};
   // 本分支处理握手条件 rsp_valid 与 rsp_ready；仅满足当前条件时推进下述事务。
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   if(rx_pop)rx_full<=0;
   if(tx_busy)begin
    if(tx_count==tx_div-1)begin
     tx_count<=0;
     if(tx_bit==9)tx_busy<=0;
     else begin tx_shift<={1'b1,tx_shift[9:1]};tx_bit<=tx_bit+1'b1;end
    end else tx_count<=tx_count+1'b1;
   end
   if(!rx_busy)begin
    if(control[1]&&!rx_sync[1])begin rx_busy<=1;rx_count<=0;rx_bit<=0;rx_div<=divisor;end
   end else if(rx_count==((rx_bit==0)?((rx_div>>1)-1):(rx_div-1)))begin
    rx_count<=0;
    if(rx_bit==0)begin if(rx_sync[1])rx_busy<=0;else rx_bit<=1;end
    else if(rx_bit<=8)begin rx_shift[rx_bit-1]<=rx_sync[1];rx_bit<=rx_bit+1'b1;end
    else begin
     rx_busy<=0;
     if(!rx_sync[1])rx_framing<=1;
     else if(rx_full&&!rx_pop)rx_overrun<=1;
     else begin rx_data<=rx_shift;rx_full<=1;end
    end
   end else rx_count<=rx_count+1'b1;
   if(take)begin
    rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;
    case(req_addr)
     8'h00:begin
      // rsp_rdata 在此时钟更新路径捕获 {tx_busy,31'd0}，该更新仍受外层条件与后续同块赋值优先级限定。
      // 本时钟边界的 rsp_rdata 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
      // 拼接源为 {tx_busy,31'd0}；复制大括号表示重复位域，不是独立队列元素。
      rsp_rdata<={tx_busy,31'd0};
      if(req_write&&req_wstrb[0])begin
       if(tx_busy||!control[0])rsp_error<=1;
       else begin tx_shift<={1'b1,req_wdata[7:0],1'b0};tx_busy<=1;tx_count<=0;tx_bit<=0;tx_div<=divisor;end
      end
     end
     8'h04:begin rsp_rdata<={!rx_full,23'd0,rx_data};if(req_write)rsp_error<=1;end
     8'h08:begin rsp_rdata<={30'd0,control};if(req_write&&req_wstrb[0])control<=req_wdata[1:0];end
     8'h0c:begin rsp_rdata<={30'd0,irq_enable};if(req_write&&req_wstrb[0])irq_enable<=req_wdata[1:0];end
     8'h10:begin rsp_rdata<={30'd0,(!tx_busy&&control[0]),rx_full};if(req_write)rsp_error<=1;end
     8'h14:begin
      // rsp_rdata 在此时钟更新路径捕获 divisor，该更新仍受外层条件与后续同块赋值优先级限定。
      // 本时钟边界的 rsp_rdata 捕获 divisor，两者在此路径上保持字段对应。
      rsp_rdata<=divisor;
      if(req_write)begin if(req_wstrb!=4'hf||req_wdata<4)rsp_error<=1;else divisor<=req_wdata;end
     end
     8'h18:begin
      // rsp_rdata 在此时钟更新路径捕获 {29'd0,rx_framing,rx_overrun,tx_busy}，该更新仍受外层条件与后续同块赋值优先级限定。
      // 拼接源为 {29'd0,rx_framing,rx_overrun,tx_busy}；复制大括号表示重复位域，不是独立队列元素。
      rsp_rdata<={29'd0,rx_framing,rx_overrun,tx_busy};
      if(req_write&&req_wstrb[0])begin if(req_wdata[1])rx_overrun<=new_overrun;if(req_wdata[2])rx_framing<=new_framing;end
     end
     default:rsp_error<=1;
    endcase
   end
  end
 end
endmodule
