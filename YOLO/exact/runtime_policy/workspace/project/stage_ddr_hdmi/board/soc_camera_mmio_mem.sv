// CPU-visible camera registers after the existing pg_mmio_cdc. All signals
// here use the HMIC user clock. A CPU write to CTRL bit0 arms one frame.
// Register map at 0x60001000: CTRL, BASE, STATUS, WRITTEN, SENSOR,
// ERRORS, DIMENSIONS, ID (word offsets 0,4,...,28).
module soc_camera_mmio_mem #(
    parameter int WIDTH=1280, HEIGHT=720,
    parameter bit CAPTURE_CHANNEL=0,
    parameter bit IMAGE_ACCEL_PRESENT=0
)(
    input logic clk,rst,ddr_ready,camera_init_done,
    input logic req_valid,output logic req_ready,
    input logic [15:0] req_addr,
    input logic req_write,input logic [31:0] req_wdata,
    input logic [3:0] req_wstrb,
    output logic rsp_valid,input logic rsp_ready,
    output logic [31:0] rsp_rdata,output logic rsp_error,
    output logic start,
    output logic [31:0] frame_base,
    input logic camera_ready,camera_busy,camera_done,camera_valid,
    input logic [7:0] camera_errors,
    input logic [31:0] pixels_written,sensor_pixels,
    input logic [511:0] diag_words,
    output logic diag_snapshot,
    input logic camera_init_done_1,
    input logic [511:0] diag_words_1,
    output logic diag_snapshot_1,
    output logic [5:0] sccb_control,
    input logic [31:0] camera_io_levels
);
    timeunit 1ns;timeprecision 1ps;
    logic done_hold;
    logic [31:0] status_word;
    wire capture_initialized=CAPTURE_CHANNEL?camera_init_done_1:camera_init_done;
    wire capture_manual=CAPTURE_CHANNEL?sccb_control[1]:sccb_control[0];
    assign req_ready=!rst&&!rsp_valid;
    assign status_word={25'b0,capture_initialized,(|camera_errors),ddr_ready,camera_valid,
                        done_hold,camera_busy,camera_ready};
    always_ff @(posedge clk)begin
        start<=0;diag_snapshot<=0;diag_snapshot_1<=0;
        if(rst)begin
            rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
            frame_base<=32'h8001_0000;done_hold<=0;sccb_control<=0;
        end else begin
            if(camera_done)done_hold<=1;
            if(rsp_valid&&rsp_ready)rsp_valid<=0;
            if(req_valid&&req_ready)begin
                rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;
                if(req_addr[1:0]!=0 || req_addr[11:8]!=0)rsp_error<=1;
                else if(req_write)begin
                    case(req_addr[7:2])
                        5'd0: if(req_wstrb!=4'hf || req_wdata[31:1]!=0)
                            rsp_error<=1;
                        else if(req_wdata[0])begin
                            if(camera_ready&&ddr_ready&&capture_initialized&&!capture_manual)begin
                                start<=1;done_hold<=0;
                            end else rsp_error<=1;
                        end
                        5'd1: if(req_wstrb==4'hf && camera_ready)
                            frame_base<=req_wdata;
                        else rsp_error<=1;
                        5'd8: if(req_wstrb==4'hf && req_wdata==1)
                            diag_snapshot<=1;
                        else rsp_error<=1;
                        6'd24: if(req_wstrb==4'hf && req_wdata[31:6]==0 &&
                            !camera_busy && camera_ready && camera_init_done && camera_init_done_1)
                            sccb_control<=req_wdata[5:0];
                        else rsp_error<=1;
                        6'd32: if(req_wstrb==4'hf && req_wdata==1)
                            diag_snapshot_1<=1;
                        else rsp_error<=1;
                        default:rsp_error<=1;
                    endcase
                end else begin
                    case(req_addr[7:2])
                        5'd0:rsp_rdata<=0;
                        5'd1:rsp_rdata<=frame_base;
                        5'd2:rsp_rdata<=status_word;
                        5'd3:rsp_rdata<=pixels_written;
                        5'd4:rsp_rdata<=sensor_pixels;
                        5'd5:rsp_rdata<={24'b0,camera_errors};
                        5'd6:rsp_rdata<={16'(HEIGHT),16'(WIDTH)};
                        5'd7:rsp_rdata<=32'h4341_4d31; // "CAM1"
                        6'd24:rsp_rdata<={IMAGE_ACCEL_PRESENT,25'b0,sccb_control};
                        6'd25:rsp_rdata<={29'b0,camera_busy,camera_init_done_1,camera_init_done};
                        6'd26:rsp_rdata<=camera_io_levels;
                        6'd27:rsp_rdata<=32'h31424353; // "SCB1"
                        6'd28:rsp_rdata<=32'(CAPTURE_CHANNEL);
                        default:if(req_addr[7:2]>=8 && req_addr[7:2]<=23)
                            rsp_rdata<=diag_words[32*(req_addr[7:2]-8)+:32];
                        else if(req_addr[7:2]>=32 && req_addr[7:2]<=47)
                            rsp_rdata<=diag_words_1[32*(req_addr[7:2]-32)+:32];
                        else rsp_error<=1;
                    endcase
                end
            end
        end
    end
endmodule
