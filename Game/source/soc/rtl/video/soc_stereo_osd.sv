// [ARCH] 复用的视频覆盖模块由上层决定实际使能。
// [ARCH] 叠加不能破坏颜色与 DE/HS/VS 的拍对齐。
// [ARCH] 模块存在不等于本游戏实现了立体显示或新增 HUD。
// [ARCH] Mario 主要图像由软件 PPU 与缩放器产生。
`timescale 1ns/1ps
// Pixel-domain OSD. The HDMI timing/DDR reader supplies stable RGB and x/y.
// CPU/control supplies only one box descriptor. The descriptor and displayed
// frame IDs become active together at a vertical blank, never mid-frame.
module soc_stereo_osd #(parameter int X_MIN=640,X_LIMIT=1280,Y_MIN=120,Y_LIMIT=600) (
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input logic clk,rst,
    input logic vblank,
    // [ARCH] displayed_left_id：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    input logic [31:0] displayed_left_id,displayed_right_id,
    // [ARCH] cfg_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    input logic cfg_valid,cfg_enable,
    // [ARCH] cfg_left_id：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 shadow_left_id 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [31:0] cfg_left_id,cfg_right_id,
    input logic [10:0] cfg_x1,cfg_x2,
    input logic [9:0] cfg_y1,cfg_y2,
    // [ARCH] pixel_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 border, pixel_out_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic pixel_valid,
    input logic [10:0] pixel_x,
    input logic [9:0] pixel_y,
    input logic [23:0] pixel_rgb,
    // [ARCH] pixel_out_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pixel_out_rgb 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic pixel_out_valid,
    output logic [23:0] pixel_out_rgb,
    output logic box_active,
    // [ARCH] cfg_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 box_active, cfg_x2 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic cfg_error
);
    // [ARCH] shadow_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 shadow_enable, shadow_left_id, shadow_right_id, box_active 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic shadow_valid,shadow_enable;
    // [ARCH] shadow_left_id：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 shadow_valid, shadow_enable, shadow_right_id 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [31:0] shadow_left_id,shadow_right_id;
    logic [10:0] shadow_x1,shadow_x2,active_x1,active_x2;
    logic [9:0] shadow_y1,shadow_y2,active_y1,active_y2;
    logic border;
    wire cfg_bounds_ok=cfg_x1>=X_MIN && cfg_x2<=X_LIMIT &&
                       cfg_x1<cfg_x2 && cfg_y1>=Y_MIN &&
                       cfg_y2<=Y_LIMIT && cfg_y1<cfg_y2;
    assign border=box_active && pixel_valid &&
        pixel_x>=active_x1 && pixel_x<active_x2 &&
        pixel_y>=active_y1 && pixel_y<active_y2 &&
        (pixel_x==active_x1 || pixel_x==active_x2-11'd1 ||
         pixel_y==active_y1 || pixel_y==active_y2-10'd1);
    always_ff @(posedge clk) begin
        if(rst) begin
            shadow_valid<=0;shadow_enable<=0;shadow_left_id<=0;shadow_right_id<=0;
            shadow_x1<=0;shadow_x2<=0;shadow_y1<=0;shadow_y2<=0;
            active_x1<=0;active_x2<=0;active_y1<=0;active_y2<=0;
            box_active<=0;cfg_error<=0;
            pixel_out_valid<=0;pixel_out_rgb<=0;
        end else begin
            pixel_out_valid<=pixel_valid;
            pixel_out_rgb<=border?24'h00ff00:pixel_rgb;
            if(cfg_valid) begin
                shadow_valid<=1;
                shadow_enable<=cfg_enable;
                shadow_left_id<=cfg_left_id;
                shadow_right_id<=cfg_right_id;
                shadow_x1<=cfg_x1;shadow_x2<=cfg_x2;
                shadow_y1<=cfg_y1;shadow_y2<=cfg_y2;
                cfg_error<=cfg_enable && !(cfg_x1>=X_MIN && cfg_x2<=X_LIMIT &&
                             cfg_x1<cfg_x2 && cfg_y1>=Y_MIN &&
                             cfg_y2<=Y_LIMIT && cfg_y1<cfg_y2);
            end
            if(vblank) begin
                // A descriptor first observed on this same vblank is valid:
                // latch the current coherent packet rather than old shadow.
                if(cfg_valid)begin
                    box_active<=cfg_enable && cfg_bounds_ok &&
                        cfg_left_id==displayed_left_id && cfg_right_id==displayed_right_id;
                    active_x1<=cfg_x1;active_x2<=cfg_x2;
                    active_y1<=cfg_y1;active_y2<=cfg_y2;
                end else begin
                    box_active<=shadow_valid && shadow_enable && !cfg_error &&
                        shadow_left_id==displayed_left_id &&
                        shadow_right_id==displayed_right_id;
                    active_x1<=shadow_x1;active_x2<=shadow_x2;
                    active_y1<=shadow_y1;active_y2<=shadow_y2;
                end
            end
        end
    end
endmodule
