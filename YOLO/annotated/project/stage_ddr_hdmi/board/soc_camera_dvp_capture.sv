// OV5640 RGB565 DVP byte receiver. The sensor emits the high byte first.
// A level arm from the memory domain is synchronized locally. A frame starts
// on VSYNC falling and ends on VSYNC rising. No pixel backpressure exists:
// FIFO overflow or a malformed line poisons the whole frame. done_toggle,
// bad_hold and pixels_hold stay stable until arm is deasserted and reasserted.
// 架构导读：soc_camera_dvp_capture。
// 在摄像头像素时钟域接收 DVP 字节和帧/行同步，形成带边界的数据流。
module soc_camera_dvp_capture #(
 // 静态配置：parameter int WIDTH=1280, HEIGHT=720。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter int WIDTH=1280, HEIGHT=720
)(
 // 接口声明：input logic pclk,arst,arm,vsync,href。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic pclk,arst,arm,vsync,href,
 // 接口声明：input logic [7:0] byte_data。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 input logic [7:0] byte_data,
 // 接口声明：output logic pixel_valid,input logic pixel_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic pixel_valid,input logic pixel_ready,
 // 接口声明：output logic [15:0] pixel_data。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 output logic [15:0] pixel_data,
 output logic done_toggle,bad_hold,
 output logic [31:0] pixels_hold
);
 timeunit 1ns;timeprecision 1ps;
 logic rst,armed,seen_vsync,vsync_q,href_q;
 pg_reset_sync u_reset(.clk(pclk),.arst,.rst);
 pg_level_sync u_arm(.clk(pclk),.rst,.async_level(arm),.level(armed));
 typedef enum logic [1:0] {WAIT_ARM,WAIT_LOW,CAPTURE,WAIT_RELEASE} state_t;
 state_t state;
 logic half_byte,bad;
 logic [7:0] first_byte;
 logic [15:0] col,row;
 logic [31:0] pixels;
 // DVP cannot hold a pixel. A full FIFO drops this pixel and marks the frame
 // bad; it must never present an unstable stalled ready/valid payload.
 assign pixel_valid=!rst && state==CAPTURE && !vsync && href &&
                    half_byte && row<HEIGHT && col<WIDTH && pixel_ready;
 assign pixel_data={first_byte,byte_data};
 // 过程边界：always_ff @(posedge pclk) begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge pclk) begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin
   state<=WAIT_ARM;seen_vsync<=0;vsync_q<=1;href_q<=0;
   half_byte<=0;first_byte<=0;col<=0;row<=0;pixels<=0;
   done_toggle<=0;bad_hold<=0;pixels_hold<=0;bad<=0;
  end else begin
   vsync_q<=vsync;href_q<=href;
   if(vsync)seen_vsync<=1;
   // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
   case(state)
    // 状态/选择分支 WAIT_ARM：本分支规定该编码下的寄存器更新和下一步动作。
    WAIT_ARM:if(armed&&seen_vsync)state<=WAIT_LOW;
    // 状态/选择分支 WAIT_LOW：本分支规定该编码下的寄存器更新和下一步动作。
    WAIT_LOW:begin
     if(!armed)state<=WAIT_ARM;
     else if(vsync_q&&!vsync)begin
      // HREF may already carry the first RGB565 high byte on this edge.
      state<=CAPTURE;half_byte<=href;
      if(href)first_byte<=byte_data;
      col<=0;row<=0;pixels<=0;bad<=0;
     end
    end
    // 状态/选择分支 CAPTURE：本分支规定该编码下的寄存器更新和下一步动作。
    CAPTURE:begin
     if(!vsync_q&&vsync)begin
      // A final HREF ending on the VSYNC edge is malformed.
      bad_hold<=bad || href || href_q || half_byte || col!=0 || row!=HEIGHT;
      pixels_hold<=pixels;done_toggle<=!done_toggle;state<=WAIT_RELEASE;
     end else if(vsync)bad<=1;
     else if(href)begin
      if(row>=HEIGHT)bad<=1;
      if(!half_byte)begin first_byte<=byte_data;half_byte<=1;end
      else begin
       half_byte<=0;
       if(col>=WIDTH || !pixel_ready)bad<=1;
       if(col<WIDTH)col<=col+1'b1;
       if(row<HEIGHT&&col<WIDTH)pixels<=pixels+1'b1;
      end
     end else if(href_q)begin
      if(half_byte||col!=WIDTH||row>=HEIGHT)bad<=1;
      half_byte<=0;col<=0;row<=row+1'b1;
     end
    end
    // 状态/选择分支 WAIT_RELEASE：本分支规定该编码下的寄存器更新和下一步动作。
    WAIT_RELEASE:if(!armed)state<=WAIT_ARM;
    default:state<=WAIT_ARM;
   endcase
  end
 end
 initial if(WIDTH<8||HEIGHT<1||WIDTH>65535||HEIGHT>65535)
  $fatal(1,"CAMERA_DVP_DIMENSION");
endmodule
