// ---------------------------------------------------------------------------
// game_video_ctrl -- double-buffered framebuffer publication for the HDMI
// scan-out engine.  Lives in the DDR user (ui) clock domain; the CPU reaches
// it through pg_mmio_cdc, so a slow DDR/HDMI domain can never stall the core.
//
// Register map (byte offset):
//   0x00 RO  ID              0x47564944 ('GVID')
//   0x04 RO  STATUS          [0] publish busy [1] pending [2] last commit error
//                            [3] ddr_ready   [4] video fault [5] test pattern
//   0x08 RW  FB0             base address of frame buffer 0 (256B aligned)
//   0x0C RW  FB1             base address of frame buffer 1
//   0x10 W   COMMIT          publish the given buffer at the next vblank
//   0x14 RO  VSYNC_COUNT     vertical blanks seen since reset
//   0x18 RO  PUBLISH_COUNT   successful publications
//   0x1C RO  ACTIVE_FB       buffer the raster is currently scanning
//   0x20 RO  UNDERFLOW       stale/missing pixel count reported by the scanout
//   0x24 RO  PRESENTED       complete frames presented
//   0x28 RW  CTRL            [0] show test pattern instead of the frame buffer
//   0x2C RO  MAX_DDR_WAIT    worst scan-out DDR wait in ui clocks
//   0x30 RO  VIDEO_FAULT     sticky scan-out fault bits
//   0x34 RO  ERROR_CODE      last rejected commit reason
//
// Structure: the MMIO block owns every software-visible register; the publish
// block owns the scan-out handshake.  They talk through a two-phase toggle, so
// each register has exactly one driving always block (PDS rejects anything
// else) and a CPU write cannot race the ready/valid transfer.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module game_video_ctrl #(
    parameter logic [31:0] FB0_DEFAULT = 32'h8200_0000,
    parameter logic [31:0] FB1_DEFAULT = 32'h8210_0000,
    parameter int PUBLISH_TIMEOUT = 200_000
) (
    input  logic ui_clk,
    input  logic ui_rst,
    input  logic ddr_ready,
    // MMIO slave (already in ui_clk)
    input  logic req_valid,
    output logic req_ready,
    input  logic [15:0] req_addr,
    input  logic req_write,
    input  logic [31:0] req_wdata,
    input  logic [3:0]  req_wstrb,
    output logic rsp_valid,
    input  logic rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic rsp_error,
    // publication to the scan-out engine
    output logic publish_valid,
    input  logic publish_ready,
    output logic [31:0] publish_fb,
    output logic [31:0] publish_frame,
    output logic [31:0] publish_run,
    output logic [31:0] publish_xy1,
    output logic [31:0] publish_xy2,
    output logic [31:0] publish_score,
    output logic [31:0] publish_class,
    output logic [31:0] publish_count,
    output logic [31:0] publish_sequence,
    // scan-out feedback
    input  logic vsync_event,
    input  logic presented_valid,
    input  logic [31:0] presented_fb,
    input  logic [31:0] stat_underflow,
    input  logic [31:0] stat_presented,
    input  logic [31:0] max_ddr_wait,
    input  logic [7:0]  video_fault,
    output logic [1:0]  test_pattern
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam logic [31:0] ID_VALUE = 32'h4756_4944;

    // ---- MMIO-owned registers -------------------------------------------
    logic [31:0] fb0_q, fb1_q;
    logic [31:0] vsync_q, active_fb_q;
    logic [31:0] error_code_q;
    logic [1:0]  test_mode_q;
    logic        commit_err_q;
    logic        pending_q;
    logic [31:0] rdata_q;
    logic        error_q;
    logic [31:0] req_fb_q;
    logic        req_toggle_q;

    // ---- publish-owned registers ----------------------------------------
    logic        publish_valid_q, busy_q;
    logic [31:0] pub_fb_q, publish_q, timeout_q;
    logic        seen_toggle_q;

    logic [7:0] off;
    logic access;
    assign off = req_addr[7:0];
    assign access = req_valid && req_ready;

    assign publish_valid = publish_valid_q;
    assign publish_fb = pub_fb_q;
    assign publish_frame = publish_q;
    assign publish_run = 32'd1;
    assign publish_xy1 = 32'd0;
    assign publish_xy2 = 32'd0;
    assign publish_score = 32'd0;
    assign publish_class = 32'd0;
    assign publish_count = 32'd0;
    assign publish_sequence = publish_q;
    assign test_pattern = test_mode_q;

    assign req_ready = !ui_rst && !pending_q;
    assign rsp_valid = pending_q;
    assign rsp_rdata = rdata_q;
    assign rsp_error = error_q;

    // ------------------------------------------------------ publish block
    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            publish_valid_q <= 1'b0;
            busy_q <= 1'b0;
            pub_fb_q <= 32'd0;
            publish_q <= 32'd0;
            timeout_q <= 32'd0;
            seen_toggle_q <= 1'b0;
        end else begin
            seen_toggle_q <= req_toggle_q;
            if (!publish_valid_q && (req_toggle_q != seen_toggle_q)) begin
                pub_fb_q <= req_fb_q;
                publish_valid_q <= 1'b1;
                busy_q <= 1'b1;
                timeout_q <= 32'd0;
            end else if (publish_valid_q && publish_ready) begin
                publish_valid_q <= 1'b0;
                busy_q <= 1'b0;
                publish_q <= publish_q + 32'd1;
                timeout_q <= 32'd0;
            end else if (publish_valid_q) begin
                if (timeout_q >= 32'(PUBLISH_TIMEOUT)) begin
                    publish_valid_q <= 1'b0;
                    busy_q <= 1'b0;
                    timeout_q <= 32'd0;
                end else begin
                    timeout_q <= timeout_q + 32'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------ counters
    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            vsync_q <= 32'd0;
            active_fb_q <= 32'd0;
        end else begin
            if (vsync_event) vsync_q <= vsync_q + 32'd1;
            if (presented_valid) active_fb_q <= presented_fb;
        end
    end

    // ---------------------------------------------------------- MMIO block
    always_ff @(posedge ui_clk) begin
        if (ui_rst) begin
            fb0_q <= FB0_DEFAULT;
            fb1_q <= FB1_DEFAULT;
            test_mode_q <= 2'd2;
            pending_q <= 1'b0;
            rdata_q <= 32'd0;
            error_q <= 1'b0;
            error_code_q <= 32'd0;
            commit_err_q <= 1'b0;
            req_fb_q <= 32'd0;
            req_toggle_q <= 1'b0;
        end else begin
            if (pending_q && rsp_ready) pending_q <= 1'b0;
            if (access) begin
                pending_q <= 1'b1;
                error_q <= 1'b0;
                rdata_q <= 32'd0;
                if (req_addr[1:0] != 2'b00) error_q <= 1'b1;
                else if (req_write) begin
                    case (off)
                        8'h08: if (req_wstrb == 4'hf) fb0_q <= {req_wdata[31:8], 8'd0};
                        8'h0C: if (req_wstrb == 4'hf) fb1_q <= {req_wdata[31:8], 8'd0};
                        8'h28: if (req_wstrb[0]) test_mode_q <= req_wdata[0] ? 2'd0 : 2'd2;
                        8'h10: begin
                            if (req_wstrb != 4'hf) begin
                                error_q <= 1'b1;
                                error_code_q <= 32'd1;
                            end else if (busy_q || publish_valid_q) begin
                                error_q <= 1'b1;
                                commit_err_q <= 1'b1;
                                error_code_q <= 32'd2;
                            end else if (req_wdata != fb0_q && req_wdata != fb1_q) begin
                                error_q <= 1'b1;
                                commit_err_q <= 1'b1;
                                error_code_q <= 32'd3;
                            end else if (presented_valid && req_wdata == active_fb_q) begin
                                error_q <= 1'b1;
                                commit_err_q <= 1'b1;
                                error_code_q <= 32'd4;
                            end else if (!ddr_ready) begin
                                error_q <= 1'b1;
                                commit_err_q <= 1'b1;
                                error_code_q <= 32'd5;
                            end else begin
                                req_fb_q <= req_wdata;
                                req_toggle_q <= ~req_toggle_q;
                                commit_err_q <= 1'b0;
                                error_code_q <= 32'd0;
                            end
                        end
                        default: error_q <= 1'b1;
                    endcase
                end else begin
                    case (off)
                        8'h00: rdata_q <= ID_VALUE;
                        8'h04: rdata_q <= {24'd0, 2'b0, (test_mode_q == 2'd0),
                                           |video_fault, ddr_ready, commit_err_q,
                                           publish_valid_q, busy_q};
                        8'h08: rdata_q <= fb0_q;
                        8'h0C: rdata_q <= fb1_q;
                        8'h14: rdata_q <= vsync_q;
                        8'h18: rdata_q <= publish_q;
                        8'h1C: rdata_q <= active_fb_q;
                        8'h20: rdata_q <= stat_underflow;
                        8'h24: rdata_q <= stat_presented;
                        8'h28: rdata_q <= {30'd0, test_mode_q};
                        8'h2C: rdata_q <= max_ddr_wait;
                        8'h30: rdata_q <= {24'd0, video_fault};
                        8'h34: rdata_q <= error_code_q;
                        default: error_q <= 1'b1;
                    endcase
                end
            end
        end
    end

    initial begin
        if (FB0_DEFAULT[7:0] != 8'd0 || FB1_DEFAULT[7:0] != 8'd0)
            $fatal(1, "GAME_VIDEO_FB_ALIGNMENT");
    end
endmodule
