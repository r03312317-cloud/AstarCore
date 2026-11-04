// [ARCH] 提交和状态寄存器协调软件双缓冲与硬件扫描。
// [ARCH] COMMIT 排队不等于已经换帧，需要 PUBLISHED 与 ACTIVE_FB 共同确认。
// [ARCH] 非法地址、重复提交与下游故障必须留下可读错误状态。
// [ARCH] 目标地址必须属于当前硬件视频窗口。
// [ARCH] 本控制器不渲染 NES 内容，颜色转换由软件完成。
// [ARCH] 成功发布计数可能比已经排队的请求少一帧。
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
// [ARCH] 软件的后台缓冲写完后才写 COMMIT。
// [ARCH] 控制器把描述符送往扫描域，扫描域在允许边界接纳。
// [ARCH] 软件用发布计数和活动地址确认所有权转移。
// [ARCH] 此时旧前台才能成为下一次可写后台。
module game_video_ctrl #(
    parameter logic [31:0] FB0_DEFAULT = 32'h8200_0000,
    parameter logic [31:0] FB1_DEFAULT = 32'h8210_0000,
    parameter int PUBLISH_TIMEOUT = 200_000
) (
    input  logic ui_clk,
    // [ARCH] ui_rst：参与本域复位/就绪控制，释放条件与跨域同步链一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 req_ready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic ui_rst,
    // [ARCH] ddr_ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
    input  logic ddr_ready,
    // MMIO slave (already in ui_clk)
    // [ARCH] req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 access 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic req_valid,
    // [ARCH] req_ready：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 access 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic req_ready,
    // [ARCH] req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 off, error_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [15:0] req_addr,
    // [ARCH] req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    input  logic req_write,
    // [ARCH] req_wdata：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 fb0_q, fb1_q, test_mode_q, req_fb_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [31:0] req_wdata,
    // [ARCH] req_wstrb：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 fb0_q, fb1_q, test_mode_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [3:0]  req_wstrb,
    // [ARCH] rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    output logic rsp_valid,
    // [ARCH] rsp_ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic rsp_ready,
    // [ARCH] rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    output logic [31:0] rsp_rdata,
    // [ARCH] rsp_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    output logic rsp_error,
    // publication to the scan-out engine
    // [ARCH] publish_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    output logic publish_valid,
    // [ARCH] publish_ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
    input  logic publish_ready,
    output logic [31:0] publish_fb,
    output logic [31:0] publish_frame,
    output logic [31:0] publish_run,
    output logic [31:0] publish_xy1,
    output logic [31:0] publish_xy2,
    output logic [31:0] publish_score,
    output logic [31:0] publish_class,
    // [ARCH] publish_count：统计已接受的有效占用/事件；同时增减时要保留净变化。
    output logic [31:0] publish_count,
    // [ARCH] publish_sequence：保存绝对年龄序号，防止复用同一槽位时混淆新旧指令。
    output logic [31:0] publish_sequence,
    // scan-out feedback
    input  logic vsync_event,
    // [ARCH] presented_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 active_fb_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic presented_valid,
    input  logic [31:0] presented_fb,
    input  logic [31:0] stat_underflow,
    input  logic [31:0] stat_presented,
    input  logic [31:0] max_ddr_wait,
    // [ARCH] video_fault：错误事实应记录到所属指令/事务，再在允许的精确边界处理。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rdata_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [7:0]  video_fault,
    output logic [1:0]  test_pattern
);
    timeunit 1ns;
    timeprecision 1ps;

    // [ARCH] ID_VALUE：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rdata_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    localparam logic [31:0] ID_VALUE = 32'h4756_4944;

    // ---- MMIO-owned registers -------------------------------------------
    logic [31:0] fb0_q, fb1_q;
    logic [31:0] vsync_q, active_fb_q;
    // [ARCH] error_code_q：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rdata_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [31:0] error_code_q;
    logic [1:0]  test_mode_q;
    logic        commit_err_q;
    logic        pending_q;
    // [ARCH] rdata_q：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [31:0] rdata_q;
    // [ARCH] error_q：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_error 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic        error_q;
    // [ARCH] req_fb_q：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pub_fb_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [31:0] req_fb_q;
    // [ARCH] req_toggle_q：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 seen_toggle_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic        req_toggle_q;

    // ---- publish-owned registers ----------------------------------------
    // [ARCH] publish_valid_q：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 publish_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
