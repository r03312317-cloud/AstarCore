// One armed OV5640 DVP RGB565 frame. VSYNC high is frame blanking; HREF
// high qualifies bytes sampled on PCLK rising edges, high byte first.
// pixel_ready is FIFO capacity, NOT sensor backpressure: a rejected pixel
// invalidates the whole frame. done/count/error remain reportable even when
// the pixel FIFO is full. A new arm is permitted only after the old frame's
// pixels and external memory transactions have been drained by the caller.
// 架构导读：soc_ov5640_capture。
// OV5640 采集连接层，组织像素输入与帧同步接口。
module soc_ov5640_capture #(
    // 静态配置：parameter int TIMEOUT_CYCLES = 100_000_000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int TIMEOUT_CYCLES = 100_000_000
)(
    // 接口声明：input logic pclk, rst, arm。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic pclk, rst, arm,
    // 接口声明：input logic [15:0] width, height。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [15:0] width, height,
    // 接口声明：input logic vsync, href。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic vsync, href,
    // 接口声明：input logic [7:0] data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [7:0] data,
    // 接口声明：output logic pixel_valid。
    output logic pixel_valid,
    input logic pixel_ready,
    output logic [15:0] pixel_data,
    output logic busy, done,
    output logic [7:0] error,
    output logic [31:0] pixels_enqueued
);
    timeunit 1ns; timeprecision 1ps;
    // 静态配置：localparam int TW = $clog2(TIMEOUT_CYCLES)。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam int TW = $clog2(TIMEOUT_CYCLES);
    typedef enum logic [1:0] {IDLE, WAIT_FRAME, CAPTURE} state_t;
    state_t state;
    logic vsync_q, href_q, byte_phase;
    logic [7:0] high_byte;
    logic [15:0] width_q, height_q;
    logic [16:0] row_pixels, lines;
    logic [TW-1:0] timer;
    logic [7:0] end_error;
    logic [17:0] end_lines;
    wire line_end = href_q && !href;
    wire frame_end = !vsync_q && vsync;
    assign busy = !rst && state != IDLE;
    assign pixel_valid = !rst && state == CAPTURE && !vsync && href && byte_phase &&
                         error == 0 && row_pixels < {1'b0,width_q} && lines < {1'b0,height_q};
    assign pixel_data = {high_byte,data};
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        end_lines = {1'b0,lines} + 18'(line_end);
        end_error = error;
        if (line_end && (byte_phase || row_pixels != {1'b0,width_q})) end_error[1] = 1;
        if (end_lines != {2'b0,height_q}) end_error[2] = 1;
        if (href) end_error[3] = 1;
    end
    // 过程边界：always_ff @(posedge pclk or posedge rst) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge pclk or posedge rst) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            state<=IDLE; vsync_q<=1; href_q<=0; byte_phase<=0; high_byte<=0;
            width_q<=0; height_q<=0; row_pixels<=0; lines<=0; timer<=0;
            done<=0; error<=0; pixels_enqueued<=0;
        end else begin
            vsync_q<=vsync; href_q<=href; done<=0;
            // 握手/背压判断：pixel_valid && pixel_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if (pixel_valid && pixel_ready) pixels_enqueued<=pixels_enqueued+1;
            if (state!=IDLE) timer<=timer+1'b1;
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case (state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if (arm) begin
                    width_q<=width; height_q<=height; row_pixels<=0; lines<=0;
                    byte_phase<=0; pixels_enqueued<=0; error<=0; timer<=0; state<=WAIT_FRAME;
                end
                // 状态/选择分支 WAIT_FRAME：本分支规定该编码下的寄存器更新和下一步动作。
                WAIT_FRAME: if (vsync_q && !vsync) begin
                    state<=CAPTURE; row_pixels<=0; lines<=0;
                    // Also support the first byte on the VSYNC falling edge.
                    byte_phase<=href; if (href) high_byte<=data;
                end
                // 状态/选择分支 CAPTURE：本分支规定该编码下的寄存器更新和下一步动作。
                CAPTURE: begin
                    if (frame_end) begin state<=IDLE; done<=1; error<=end_error; end
                    else if (href && !vsync) begin
                        if (!byte_phase) begin high_byte<=data; byte_phase<=1; end
                        else begin
                            byte_phase<=0;
                            if (!(&row_pixels)) row_pixels<=row_pixels+1'b1;
                            if (row_pixels >= {1'b0,width_q}) error[1]<=1;
                            if (lines >= {1'b0,height_q}) error[2]<=1;
                            // 握手/背压判断：pixel_valid && !pixel_ready。
                            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
                            if (pixel_valid && !pixel_ready) error[0]<=1;
                        end
                    end else if (line_end) begin
                        if (byte_phase || row_pixels != {1'b0,width_q}) error[1]<=1;
                        if (!(&lines)) lines<=lines+1'b1;
                        row_pixels<=0; byte_phase<=0;
                    end
                end
                default: state<=IDLE;
            endcase
            if (state!=IDLE && timer==TW'(TIMEOUT_CYCLES-1)) begin
                state<=IDLE; done<=1; error<=error|8'h10;
            end
        end
    end
    initial if (TIMEOUT_CYCLES<2) $fatal(1,"CAMERA_CAPTURE_TIMEOUT_PARAMETER");
endmodule
