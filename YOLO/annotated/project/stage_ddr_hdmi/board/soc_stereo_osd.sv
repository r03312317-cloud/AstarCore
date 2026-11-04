// 架构导读：soc_stereo_osd。
// 对显示像素叠加识别框和文字等 OSD 信息。
`timescale 1ns/1ps
// Pixel-domain OSD. The HDMI timing/DDR reader supplies stable RGB and x/y.
// CPU/control supplies only one box descriptor. The descriptor and displayed
// frame IDs become active together at a vertical blank, never mid-frame.
module soc_stereo_osd #(parameter int X_MIN=640,X_LIMIT=1280,Y_MIN=120,Y_LIMIT=600) (
    // 接口声明：input logic clk,rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic clk,rst,
    // 接口声明：input logic vblank。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic vblank,
    // 接口声明：input logic [31:0] displayed_left_id,displayed_right_id。
    // 把返回信息关联到对应的已接受请求。
    input logic [31:0] displayed_left_id,displayed_right_id,
    // 接口声明：input logic cfg_valid,cfg_enable。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic cfg_valid,cfg_enable,
    // 接口声明：input logic [31:0] cfg_left_id,cfg_right_id。
    // 把返回信息关联到对应的已接受请求。
    input logic [31:0] cfg_left_id,cfg_right_id,
    // 接口声明：input logic [10:0] cfg_x1,cfg_x2。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [10:0] cfg_x1,cfg_x2,
    // 接口声明：input logic [9:0] cfg_y1,cfg_y2。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [9:0] cfg_y1,cfg_y2,
    // 接口声明：input logic pixel_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic pixel_valid,
    // 接口声明：input logic [10:0] pixel_x。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [10:0] pixel_x,
    // 接口声明：input logic [9:0] pixel_y。
    input logic [9:0] pixel_y,
    input logic [23:0] pixel_rgb,
    output logic pixel_out_valid,
    output logic [23:0] pixel_out_rgb,
    output logic box_active,
    output logic cfg_error
);
    logic shadow_valid,shadow_enable;
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
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
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
