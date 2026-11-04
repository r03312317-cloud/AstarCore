// SPDX-License-Identifier: MIT
// CEA 720x480p raster with a centered RGB565 image. Configurable power-of-two
// integer scaling reuses a fetched source line across repeated output rows.
// The framebuffer stride can exceed the logical GUI width. Four ordered
// native requests overlap the pixel/UI CDC; a bounded ring of line buffers
// absorbs DDR/CPU contention. A frame change drains old requests before reuse.
// 实板扫描器用 128 位 DDR 读事务取得 RGB565 源像素，并跨域供像素时序消费。
// 每拍可携带 8 个 16 位像素，读请求和返回仍受队列容量与背压限制。
// 本版 GUI 源区域为 320 乘 180，经 2 倍缩放占据居中 640 乘 360 区域。
// DDR 中每行 ABI stride 保持 1280 字节，不能改按紧密排列的 640 字节计算。
// 源帧读取规模为 115200 字节，较完整 640 乘 360 页的 460800 字节减少 75%。
// 帧基址切换必须在帧边界完成，视频错误与欠载计数用于定位数据供应问题。
// 固定 HDMI 扫描频率不是应用渲染帧率，也不是 DDR 实测带宽结果。
module rv32_framebuffer_scanout_128 #(
 parameter [31:0] REGION_BASE=32'h83f00000, REGION_LIMIT=32'h84000000,
 parameter H_ACTIVE=720,H_FRONT=16,H_SYNC=62,H_BACK=60,
 parameter V_ACTIVE=480,V_FRONT=9,V_SYNC=6,V_BACK=30,
 parameter SRC_WIDTH=640,SRC_HEIGHT=360,
 // SRC_STRIDE_BYTES 保留 Linux framebuffer 的行跨度，源 ROI 缩小不改变该值。
 parameter SRC_STRIDE_BYTES=SRC_WIDTH*2,
 // X_SCALE_SHIFT 按二的幂扩展横向像素，移位为一表示两倍放大。
 parameter X_SCALE_SHIFT=0,Y_SCALE_SHIFT=0,
 parameter LINE_BITS=6, MAX_OUTSTANDING=4
)(
 // active_enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
 input clk,reset,input [31:0] active_base,input active_enable,input frame_latch,
 output vblank,output de,hsync,vsync,output [15:0] pixel_rgb565,
 output [11:0] pixel_x,output [10:0] pixel_y,
 // mem_req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output mem_req_valid,input mem_req_ready,output [31:0] mem_req_addr,
 // mem_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input mem_rsp_valid,output mem_rsp_ready,input [127:0] mem_rsp_data,input mem_rsp_error,
 // frame_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
 output reg [31:0] frame_count,underflow_rows,dma_errors,bounds_errors
);
 // HTOTAL 按 H_ACTIVE+H_FRONT+H_SYNC+H_BACK 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam HTOTAL=H_ACTIVE+H_FRONT+H_SYNC+H_BACK;
 // VTOTAL 按 V_ACTIVE+V_FRONT+V_SYNC+V_BACK 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam VTOTAL=V_ACTIVE+V_FRONT+V_SYNC+V_BACK;
 // WORDS 按 SRC_WIDTH/8,WORD_BITS=7 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam WORDS=SRC_WIDTH/8,WORD_BITS=7;
 // DISPLAY_WIDTH 按 SRC_WIDTH<<X_SCALE_SHIFT,DISPLAY_HEIGHT=SRC_HEIGHT<<Y_SCALE_SHIFT 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam DISPLAY_WIDTH=SRC_WIDTH<<X_SCALE_SHIFT,DISPLAY_HEIGHT=SRC_HEIGHT<<Y_SCALE_SHIFT;
 // X_PAD 按 (H_ACTIVE-DISPLAY_WIDTH)/2,Y_PAD=(V_ACTIVE-DISPLAY_HEIGHT)/2 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam X_PAD=(H_ACTIVE-DISPLAY_WIDTH)/2,Y_PAD=(V_ACTIVE-DISPLAY_HEIGHT)/2;
 // LINES 按 (1<<LINE_BITS),FRAME_BYTES=(SRC_HEIGHT-1)*SRC_STRIDE_BYTES+SRC_WIDTH*2 计算，运算位宽与有无符号以原声明和显式扩展为准。
 localparam LINES=(1<<LINE_BITS),FRAME_BYTES=(SRC_HEIGHT-1)*SRC_STRIDE_BYTES+SRC_WIDTH*2;
 reg [11:0] hx;reg [10:0] vy;
 // line_memory 保存访存类别资格，供访存顺序与执行资源选择使用。
 reg [127:0] line_memory[0:(LINES*(1<<WORD_BITS))-1];
 // line_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
 reg [LINES-1:0] line_ready,line_bad;
 // line_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
 reg [9:0] line_tag[0:LINES-1];
 reg row_ok,enabled;
 reg [31:0] frame_base,pending_base;
 // pending_enable 属于在途取指队列，保存功能或输出使能，控制资格而非实际吞吐测量值。
 // 在途预留与已入队占用共同约束容量，响应返回仍需排空旧事务。
 reg pending_enable,draining;
 reg [9:0] issue_y,retire_y;
 reg [6:0] issue_word,retire_word;
 reg fill_bad,request_pending;
 // request_address 属于请求提议，保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
 // 接收事件由对应 valid 与 ready 同时成立决定。
 reg [31:0] request_address;
 reg [3:0] outstanding;
 // base_ok 的资格组合为 (active_base[5:0]==0)&&(active_base>=REGION_BASE)&& ({1'b0,active_base}+FRAME_BYTES<={1'b0,REGION_LIMIT})。
 // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
 wire base_ok=(active_base[5:0]==0)&&(active_base>=REGION_BASE)&&
  ({1'b0,active_base}+FRAME_BYTES<={1'b0,REGION_LIMIT});
 // image_y 的资格组合为 (vy>=Y_PAD)&&(vy<Y_PAD+DISPLAY_HEIGHT)。
 wire image_y=(vy>=Y_PAD)&&(vy<Y_PAD+DISPLAY_HEIGHT);
 // image_x 的资格组合为 (hx>=X_PAD)&&(hx<X_PAD+DISPLAY_WIDTH)。
 wire image_x=(hx>=X_PAD)&&(hx<X_PAD+DISPLAY_WIDTH);
 // source_y 按 image_y 进行来源选择。
 // 真分支取 ((vy-Y_PAD)>>Y_SCALE_SHIFT)；其余情况取 10'd0。
 wire [9:0] source_y=image_y ? ((vy-Y_PAD)>>Y_SCALE_SHIFT) : 10'd0;
 // source_x 按 image_x 进行来源选择。
 // 真分支取 ((hx-X_PAD)>>X_SCALE_SHIFT)；其余情况取 10'd0。
 wire [9:0] source_x=image_x ? ((hx-X_PAD)>>X_SCALE_SHIFT) : 10'd0;
 // read_bank 读取 source_y[LINE_BITS-1:0] 所选位域；位索引按声明中的高低位顺序解释。
 wire [LINE_BITS-1:0] read_bank=source_y[LINE_BITS-1:0];
 reg [127:0] read_word;
 reg pixel_ok;reg [2:0] pixel_slice;
 reg [11:0] out_x;reg [10:0] out_y;
 // pixel_rgb565 按 de&&pixel_ok 进行来源选择。
 // 真分支取 read_word[pixel_slice*16+:16]；其余情况取 16'd0。
 assign pixel_rgb565=de&&pixel_ok?read_word[pixel_slice*16+:16]:16'd0;
 assign de=(out_x<H_ACTIVE)&&(out_y<V_ACTIVE);
 assign hsync=!((out_x>=H_ACTIVE+H_FRONT)&&(out_x<H_ACTIVE+H_FRONT+H_SYNC));
 assign vsync=!((out_y>=V_ACTIVE+V_FRONT)&&(out_y<V_ACTIVE+V_FRONT+V_SYNC));
 assign pixel_x=out_x;assign pixel_y=out_y;
 always @(posedge clk)begin
  read_word<=line_memory[{read_bank,source_x[9:3]}];
  // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
  if(reset)begin out_x<=0;out_y<=V_ACTIVE;pixel_slice<=0;pixel_ok<=0;end
  else begin
   out_x<=hx;out_y<=vy;pixel_slice<=source_x[2:0];
   pixel_ok<=enabled&&row_ok&&image_x&&image_y;
  end
 end
 assign vblank=(vy==V_ACTIVE)&&(hx==0);
 assign mem_req_valid=request_pending;
 assign mem_req_addr=request_address;
 assign mem_rsp_ready=(outstanding!=0);
 // req_fire 的资格组合为 mem_req_valid&&mem_req_ready。
 wire req_fire=mem_req_valid&&mem_req_ready;
 // rsp_fire 的资格组合为 mem_rsp_valid&&mem_rsp_ready。
 wire rsp_fire=mem_rsp_valid&&mem_rsp_ready;
 // next_v 按 (vy==VTOTAL-1) 进行来源选择。
 // 真分支取 11'd0；其余情况取 vy+1'b1。
 wire [10:0] next_v=(vy==VTOTAL-1)?11'd0:vy+1'b1;
 // next_image_y 的资格组合为 (next_v>=Y_PAD)&&(next_v<Y_PAD+DISPLAY_HEIGHT)。
 wire next_image_y=(next_v>=Y_PAD)&&(next_v<Y_PAD+DISPLAY_HEIGHT);
 // next_sy 按 next_image_y 进行来源选择。
 // 真分支取 ((next_v-Y_PAD)>>Y_SCALE_SHIFT)；其余情况取 10'd0。
 wire [9:0] next_sy=next_image_y ? ((next_v-Y_PAD)>>Y_SCALE_SHIFT) : 10'd0;
 // next_bank 读取 next_sy[LINE_BITS-1:0] 所选位域；位索引按声明中的高低位顺序解释。
 wire [LINE_BITS-1:0] next_bank=next_sy[LINE_BITS-1:0];
 // next_row_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
 // next_row_ready 的资格组合为 line_ready[next_bank]&&!line_bad[next_bank]&&line_tag[next_bank]==next_sy。
 wire next_row_ready=line_ready[next_bank]&&!line_bad[next_bank]&&line_tag[next_bank]==next_sy;
 always @(posedge clk)begin
  if(reset)begin
   hx<=0;vy<=V_ACTIVE;frame_count<=0;underflow_rows<=0;dma_errors<=0;bounds_errors<=0;
   line_ready<=0;line_bad<=0;row_ok<=0;enabled<=0;frame_base<=REGION_BASE;
   pending_base<=REGION_BASE;pending_enable<=0;draining<=0;
   issue_y<=0;retire_y<=0;issue_word<=0;retire_word<=0;fill_bad<=0;
   request_pending<=0;request_address<=REGION_BASE;outstanding<=0;
  end else begin
   if(hx==HTOTAL-1)begin
    hx<=0;vy<=next_v;
    if(vy==VTOTAL-1)frame_count<=frame_count+1'b1;
    if(next_image_y)row_ok<=next_row_ready;
   end else hx<=hx+1'b1;
   if(hx==0&&image_y&&enabled&&!row_ok)underflow_rows<=underflow_rows+1'b1;
   // The row stays owned by the reader until its last scaled output line.
   if(hx==H_ACTIVE-1&&image_y&&
      (((vy-Y_PAD)&((1<<Y_SCALE_SHIFT)-1))==((1<<Y_SCALE_SHIFT)-1)))
    line_ready[read_bank]<=0;
   // A held request may not be withdrawn on a frame change. Complete and
   // discard every old response before the new frame owns the line buffers.
   if(!request_pending&&!draining&&!frame_latch&&enabled&&issue_y<SRC_HEIGHT&&
      !line_ready[issue_y[LINE_BITS-1:0]]&&outstanding<MAX_OUTSTANDING)begin
    request_address<=frame_base+issue_y*SRC_STRIDE_BYTES+issue_word*16;
    request_pending<=1;
   end
   if(req_fire)begin
    request_pending<=0;
    if(issue_word==WORDS-1)begin issue_word<=0;issue_y<=issue_y+1'b1;end
    else issue_word<=issue_word+1'b1;
   end
   case({req_fire,rsp_fire})
    2'b10:outstanding<=outstanding+1'b1;
    2'b01:outstanding<=outstanding-1'b1;
    default:outstanding<=outstanding;
   endcase
   if(rsp_fire&&!draining&&!frame_latch)begin
    line_memory[{retire_y[LINE_BITS-1:0],retire_word}]<=mem_rsp_error?128'd0:mem_rsp_data;
    if(mem_rsp_error)begin dma_errors<=dma_errors+1'b1;fill_bad<=1;end
    if(retire_word==WORDS-1)begin
     line_ready[retire_y[LINE_BITS-1:0]]<=1;
     line_bad[retire_y[LINE_BITS-1:0]]<=fill_bad||mem_rsp_error;
     line_tag[retire_y[LINE_BITS-1:0]]<=retire_y;
     retire_y<=retire_y+1'b1;retire_word<=0;fill_bad<=0;
    end else retire_word<=retire_word+1'b1;
   end
   if(frame_latch)begin
    pending_base<=active_base;pending_enable<=active_enable&&base_ok;draining<=1;
    if(active_enable&&!base_ok)bounds_errors<=bounds_errors+1'b1;
   end else if(draining&&!request_pending&&outstanding==0)begin
    frame_base<=pending_base;enabled<=pending_enable;draining<=0;
    line_ready<=0;line_bad<=0;issue_y<=0;retire_y<=0;
    issue_word<=0;retire_word<=0;fill_bad<=0;row_ok<=0;
   end
  end
 end
endmodule
