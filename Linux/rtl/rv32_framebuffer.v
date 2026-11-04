// SPDX-License-Identifier: MIT
// Control only: scanout/DMA consume active_base and active_enable in SAME clock domain.
// vblank is a one-cycle pulse in this domain, not an asynchronous pixel signal.
// framebuffer MMIO 接口在软件与显示控制器之间保存帧地址和显示使能。
// 提交请求与正在生效的地址分开，软件可轮询 pending 与活动地址确认所有权转移。
// 页切换需要 cache 清理和帧边界配合，单独改写基址不能保证画面一致。
// 此模块是寄存器面；从 DDR 读取像素与 HDMI 编码分别在 scanout 和板级模块中完成。
module rv32_framebuffer #(
 parameter [31:0] REGION_BASE=32'h83f00000,REGION_LIMIT=32'h84000000,
 parameter [31:0] FRAME_BYTES=32'd460800
)(
 // req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input clk,reset,input vblank,input req_valid,output req_ready,input req_write,
 // req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
 input [7:0] req_addr,input [31:0] req_wdata,input [3:0] req_wstrb,
 // rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output reg rsp_valid,input rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,
 // active_enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
 output reg [31:0] active_base,output reg active_enable,output irq
);
 reg [31:0] shadow_base,pending_base,frame_count;reg shadow_enable,pending_enable,pending,irq_enable,irq_pending;
 // req_ready 的资格组合为 !rsp_valid||rsp_ready。
 assign req_ready=!rsp_valid||rsp_ready;assign irq=irq_enable&&irq_pending;
 // base_ok 的资格组合为 shadow_base[5:0]==0&&shadow_base>=REGION_BASE&&{1'b0,shadow_base}+{1'b0,FRAME_BYTES}<={1'b0,REGION_LIMIT}。
 // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
 wire base_ok=shadow_base[5:0]==0&&shadow_base>=REGION_BASE&&{1'b0,shadow_base}+{1'b0,FRAME_BYTES}<={1'b0,REGION_LIMIT};
 always @(posedge clk)begin
  // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
  if(reset)begin
   // 本时钟边界的 shadow_base 捕获 REGION_BASE，两者在此路径上保持字段对应。
   shadow_base<=REGION_BASE;pending_base<=REGION_BASE;active_base<=REGION_BASE;
   shadow_enable<=0;pending_enable<=0;active_enable<=0;pending<=0;frame_count<=0;
   irq_enable<=0;irq_pending<=0;rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
  end else begin
   // 本分支处理握手条件 rsp_valid 与 rsp_ready；仅满足当前条件时推进下述事务。
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   if(vblank)begin frame_count<=frame_count+1'b1;irq_pending<=1;
    if(pending)begin active_base<=pending_base;active_enable<=pending_enable;pending<=0;end
   end
   // 本分支处理握手条件 req_valid 与 req_ready；仅满足当前条件时推进下述事务。
   if(req_valid&&req_ready)begin
    rsp_valid<=1;rsp_rdata<=0;rsp_error<=0;
    if(req_write&&req_wstrb!=4'hf)rsp_error<=1;
    else case(req_addr)
     8'h00:begin rsp_rdata<=shadow_base;if(req_write)shadow_base<=req_wdata;end
     8'h04:begin rsp_rdata<={31'd0,shadow_enable};if(req_write)shadow_enable<=req_wdata[0];end
     8'h08:begin
      // rsp_rdata 在此时钟更新路径捕获 {31'd0,pending}，该更新仍受外层条件与后续同块赋值优先级限定。
      // 本时钟边界的 rsp_rdata 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
      // 拼接源为 {31'd0,pending}；复制大括号表示重复位域，不是独立队列元素。
      rsp_rdata<={31'd0,pending};
      if(req_write&&req_wdata[0])begin
       if(pending||(!base_ok&&shadow_enable))rsp_error<=1;
       else begin pending_base<=shadow_base;pending_enable<=shadow_enable;pending<=1;end
      end
     end
     8'h0c:begin rsp_rdata<=active_base;if(req_write)rsp_error<=1;end
     8'h10:begin rsp_rdata<={30'd0,pending,active_enable};if(req_write)rsp_error<=1;end
     8'h14:begin rsp_rdata<=frame_count;if(req_write)rsp_error<=1;end
     8'h18:begin rsp_rdata<={31'd0,irq_enable};if(req_write)irq_enable<=req_wdata[0];end
     8'h1c:begin rsp_rdata<={31'd0,irq_pending};if(req_write&&req_wdata[0])irq_pending<=vblank;end
     8'h20:begin rsp_rdata<=32'd640;if(req_write)rsp_error<=1;end
     8'h24:begin rsp_rdata<=32'd360;if(req_write)rsp_error<=1;end
     8'h28:begin rsp_rdata<=32'd1280;if(req_write)rsp_error<=1;end
     8'h2c:begin rsp_rdata<=FRAME_BYTES;if(req_write)rsp_error<=1;end
     default:rsp_error<=1;
    endcase
   end
  end
 end
endmodule
