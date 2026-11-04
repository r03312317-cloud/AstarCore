`timescale 1ns/1ps
// One full 2592x1944 RGB565 raster -> 320x320 RGB INT8 V2 raster.
// The caller must discard the destination on any error and commit it only
// after frame_valid. Pixel-center coordinates match S1: (162*u+71)/20.
module soc_v2_stream_5mp (
    input logic clk,rst,start,abort,
    output logic ready,busy,done_pulse,frame_valid,
    output logic [7:0] error_sticky,
    input logic lut_write,
    input logic [7:0] lut_addr,lut_data,
    output logic lut_ready,lut_complete,
    input logic in_valid,in_last,
    output logic in_ready,
    input logic [15:0] in_rgb565,
    output logic out_valid,out_last,
    input logic out_ready,
    output logic [23:0] out_rgb_i8,
    output logic [31:0] source_pixels,active_pixels,output_pixels
);
    localparam int SRC_W=2592,SRC_H=1944,DST_W=320,ACTIVE_H=240;
    localparam int SRC_PIXELS=SRC_W*SRC_H;
    localparam int ACTIVE_PIXELS=DST_W*ACTIVE_H;
    localparam int PAD_PIXELS=DST_W*40;
    localparam int OUT_PIXELS=DST_W*320;
    typedef enum logic [2:0] {IDLE,TOP_PAD,SOURCE,BOTTOM_PAD,DRAIN,FAILED} state_t;
    state_t state;
    (* ram_style="block" *) logic [15:0] top_left[0:DST_W-1];
    (* ram_style="block" *) logic [15:0] top_right[0:DST_W-1];
    logic [15:0] left_sample;
    logic [11:0] source_x,target_x,target_y;
    logic [10:0] source_y;
    logic [8:0] target_u;
    logic [7:0] target_v;
    logic [4:0] phase_x,phase_y;
    logic [13:0] pad_issued;
    logic source_ok;
    logic [2:0] failed_drain_cycles;
    logic top_row,bottom_row,at_left,at_right,need_core;
    logic core_in_valid,core_in_ready,core_out_valid,core_out_ready;
    logic [23:0] core_out_data;
    logic source_fire,core_fire,output_fire;

    assign ready=!rst && state==IDLE && lut_complete;
    assign busy=state!=IDLE;
    assign top_row=source_y==target_y && target_v<ACTIVE_H;
    assign bottom_row=source_y==target_y+12'd1 && target_v<ACTIVE_H;
    assign at_left=source_x==target_x && target_u<DST_W;
    assign at_right=source_x==target_x+12'd1 && target_u<DST_W;
    assign need_core=bottom_row && at_right;
    assign core_in_valid=(state==TOP_PAD || state==BOTTOM_PAD) ? 1'b1 :
                         (state==SOURCE && in_valid && need_core);
    assign in_ready=state==SOURCE && (!need_core || core_in_ready);
    assign source_fire=in_valid && in_ready;
    assign core_fire=core_in_valid && core_in_ready;
    assign core_out_ready=state==FAILED ? 1'b1 : out_ready;
    assign out_valid=core_out_valid && state!=FAILED && state!=IDLE;
    assign out_rgb_i8=core_out_data;
    assign out_last=out_valid && output_pixels==OUT_PIXELS-1;
    assign output_fire=out_valid && out_ready;

    soc_v2_bilinear_quant arithmetic(
        .clk,.rst,.lut_write,.lut_addr,.lut_data,.lut_ready,.lut_complete,
        .in_valid(core_in_valid),.in_ready(core_in_ready),
        .pad(state==TOP_PAD || state==BOTTOM_PAD),
        .c00(top_left[target_u]),.c01(top_right[target_u]),
        .c10(left_sample),.c11(in_rgb565),.phase_x,.phase_y,
        .out_valid(core_out_valid),.out_ready(core_out_ready),
        .out_rgb_i8(core_out_data));

    always_ff @(posedge clk) begin
        done_pulse<=0;
        if(rst) begin
            state<=IDLE;frame_valid<=0;error_sticky<=0;source_ok<=0;failed_drain_cycles<=0;
            source_x<=0;source_y<=0;target_x<=12'd3;target_y<=12'd3;
            target_u<=0;target_v<=0;phase_x<=5'd11;phase_y<=5'd11;
            pad_issued<=0;source_pixels<=0;active_pixels<=0;
            output_pixels<=0;left_sample<=0;
        end else begin
            if(start && state!=IDLE)error_sticky[3]<=1;
            if(output_fire) begin
                output_pixels<=output_pixels+1;
                if(output_pixels==OUT_PIXELS-1) begin
                    frame_valid<=source_ok && error_sticky==0;
                    done_pulse<=1;
                    state<=IDLE;
                end
            end
            case(state)
                IDLE: if(start) begin
                    frame_valid<=0;error_sticky<=0;source_ok<=0;failed_drain_cycles<=0;
                    source_x<=0;source_y<=0;source_pixels<=0;
                    target_x<=12'd3;target_y<=12'd3;target_u<=0;target_v<=0;
                    phase_x<=5'd11;phase_y<=5'd11;active_pixels<=0;
                    pad_issued<=0;output_pixels<=0;
                    if(lut_complete)state<=TOP_PAD;
                    else begin error_sticky[0]<=1;done_pulse<=1;end
                end
                TOP_PAD: if(core_fire) begin
                    pad_issued<=pad_issued+1;
                    if(pad_issued==PAD_PIXELS-1) begin
                        pad_issued<=0;state<=SOURCE;
                    end
                end
                SOURCE: begin
                    if(abort) begin
                        error_sticky[1]<=1;done_pulse<=1;state<=FAILED;
                    end else if(source_fire) begin
                        source_pixels<=source_pixels+1;
                        if(source_x==SRC_W-1) begin
                            source_x<=0;source_y<=source_y+1;
                            target_x<=12'd3;target_u<=0;phase_x<=5'd11;
                        end else source_x<=source_x+1;
                        if((top_row || bottom_row) && at_left)
                            left_sample<=in_rgb565;
                        if((top_row || bottom_row) && at_right) begin
                            if(top_row) begin
                                top_left[target_u]<=left_sample;
                                top_right[target_u]<=in_rgb565;
                            end else begin
                                active_pixels<=active_pixels+1;
                                if(target_u==DST_W-1) begin
                                    target_v<=target_v+1;
                                    target_y<=target_y+12'd8+(phase_y>=5'd18);
                                    phase_y<=phase_y>=5'd18 ? phase_y+5'd2-5'd20 : phase_y+5'd2;
                                end
                            end
                            target_u<=target_u+1;
                            target_x<=target_x+12'd8+(phase_x>=5'd18);
                            phase_x<=phase_x>=5'd18 ? phase_x+5'd2-5'd20 : phase_x+5'd2;
                        end
                        if(in_last || source_pixels==SRC_PIXELS-1) begin
                            if(in_last && source_pixels==SRC_PIXELS-1 &&
                               active_pixels==ACTIVE_PIXELS) begin
                                source_ok<=1;pad_issued<=0;state<=BOTTOM_PAD;
                            end else begin
                                error_sticky[2]<=1;done_pulse<=1;state<=FAILED;failed_drain_cycles<=0;
                            end
                        end
                    end
                end
                BOTTOM_PAD: if(core_fire) begin
                    pad_issued<=pad_issued+1;
                    if(pad_issued==PAD_PIXELS-1) state<=DRAIN;
                end
                DRAIN: ;
                FAILED: begin
                    // Drain all five elastic stages, including bubbles. A single
                    // !out_valid cycle alone does not prove the pipeline is empty.
                    if(failed_drain_cycles<3'd5)
                        failed_drain_cycles<=failed_drain_cycles+1'b1;
                    else if(!core_out_valid)state<=IDLE;
                end
                default:state<=FAILED;
            endcase
            // The reader can fail while TOP_PAD is backpressured before the
            // first raw pixel. Abort every active phase with highest priority.
            if(abort && state!=IDLE && state!=FAILED)begin
                frame_valid<=0;source_ok<=0;error_sticky[1]<=1;
                done_pulse<=1;state<=FAILED;failed_drain_cycles<=0;
            end
        end
    end
    initial if(SRC_W*SRC_H!=5038848 || OUT_PIXELS!=102400)
        $fatal(1,"V2_STREAM_DIMENSIONS");
endmodule
