`timescale 1ns/1ps
// Pixel-domain OSD. The HDMI timing/DDR reader supplies stable RGB and x/y.
// CPU/control supplies only one box descriptor. The descriptor and displayed
// frame IDs become active together at a vertical blank, never mid-frame.
module soc_stereo_osd #(parameter int X_MIN=640,X_LIMIT=1280,Y_MIN=120,Y_LIMIT=600) (
    input logic clk,rst,
    input logic vblank,
    input logic [31:0] displayed_left_id,displayed_right_id,
    input logic cfg_valid,cfg_enable,
    input logic [31:0] cfg_left_id,cfg_right_id,
    input logic [10:0] cfg_x1,cfg_x2,
    input logic [9:0] cfg_y1,cfg_y2,
    input logic pixel_valid,
    input logic [10:0] pixel_x,
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
