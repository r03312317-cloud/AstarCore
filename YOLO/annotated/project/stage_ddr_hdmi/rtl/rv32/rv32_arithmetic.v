// Original RV32 project file; see SOURCE_PROVENANCE.md.
// RV32 RV32M arithmetic unit. Original implementation, October 2026.
//
// One request may be outstanding. A request is accepted on a rising edge
// with request_valid && request_ready. Operands need only remain stable for
// that edge. response_valid and result then remain stable until a rising
// edge with response_ready. The next request can be accepted on the edge
// after the response is consumed; there is no same-edge response turnover.
//
// Latency, measured in rising edges AFTER request acceptance:
//   MUL:                   2
//   MULH/MULHSU/MULHU:      3
//   DIV/DIVU/REM/REMU:    33, or 0 for divide by zero / signed overflow
// A zero-latency exceptional result is registered at the acceptance edge,
// never a combinational operand-to-result path.
//
// reset and cancel have synchronous priority over all transfers. They also
// suppress the ready/valid outputs while asserted. cancel abandons both an
// in-flight calculation and an unconsumed response.
//
// Multiplication uses four explicitly unsigned registered 16x16 products
// followed by short registered accumulation/correction stages. Division is
// radix-2 restoring division with one 33-bit trial subtraction per cycle.
// No combinational divide or remainder operator is used.

// 架构导读：rv32_arithmetic。
// RV32 整数算术组合数据路径，具体操作由输入控制字段选择。
`default_nettype none

module rv32_arithmetic (
    // 接口声明：input wire clk。
    // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
    input  wire        clk,
    // 接口声明：input wire reset。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input  wire        reset,
    // 接口声明：input wire cancel。
    input  wire        cancel,
    input  wire        request_valid,
    output wire        request_ready,
    input  wire [2:0]  operation,
    input  wire [31:0] left,
    input  wire [31:0] right,
    output wire        response_valid,
    output wire        response_present,
    input  wire        response_ready,
    output reg  [31:0] result
);

    // 静态配置：localparam [3:0] IDLE = 4'd0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam [3:0] IDLE          = 4'd0;
    // 静态配置：localparam [3:0] MUL_PARTIAL = 4'd1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam [3:0] MUL_PARTIAL   = 4'd1;
    // 静态配置：localparam [3:0] MUL_COLUMNS = 4'd2。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam [3:0] MUL_COLUMNS   = 4'd2;
    // 静态配置：localparam [3:0] MUL_HIGH = 4'd3。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam [3:0] MUL_HIGH      = 4'd3;
    // 静态配置：localparam [3:0] DIV_STEP = 4'd4。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam [3:0] DIV_STEP      = 4'd4;
    // 静态配置：localparam [3:0] DIV_FINISH = 4'd5。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam [3:0] DIV_FINISH    = 4'd5;
    // 静态配置：localparam [3:0] RESPONSE = 4'd6。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam [3:0] RESPONSE      = 4'd6;

    reg [3:0] state;
    reg [2:0] saved_operation;
    reg [31:0] saved_left;
    reg [31:0] saved_right;

    reg [31:0] product_00;
    reg [31:0] product_01;
    reg [31:0] product_10;
    reg [31:0] product_11;
    reg [17:0] high_addend;
    reg [31:0] high_base;
    reg [31:0] sign_correction;
    wire [17:0] middle_column;
    assign middle_column = {2'b0, product_00[31:16]} +
                           {2'b0, product_01[15:0]} +
                           {2'b0, product_10[15:0]};
    reg correct_left_sign;
    reg correct_right_sign;

    reg [31:0] division_quotient;
    reg [31:0] division_remainder;
    reg [31:0] division_divisor;
    reg [5:0] division_remaining;
    reg quotient_negative;
    reg remainder_negative;

    // During division, remainder < divisor. Therefore this subtraction
    // lies in [-2^32+1, 2^32-2]; bit 32 unambiguously indicates underflow.
    wire [32:0] trial_difference;
    assign trial_difference =
        {division_remainder, division_quotient[31]} -
        {1'b0, division_divisor};

    assign request_ready = (state == IDLE) && !reset && !cancel;
    // Private registered availability for cancelled payload proposals only.
    // Public handshake validity remains immediately reset/cancel gated.
    assign response_present = (state == RESPONSE);
    assign response_valid = (state == RESPONSE) && !reset && !cancel;

    // Timing-local payload pipeline. These registers do not own a request.
    // An accepted request at E0 is sampled into saved_left/right at E0;
    // MUL_PARTIAL at E1 uses those operands for sign_correction and the
    // products below sample them at E1. MUL_COLUMNS consumes the products
    // at E2, exactly as before. Other cycles are unobservable payload.
    // Deliberately no request/state/reset/cancel enable on the DSP pipeline.
    always @(posedge clk) begin
        saved_left <= left;
        saved_right <= right;
        product_00 <= saved_left[15:0] * saved_right[15:0];
        product_01 <= saved_left[15:0] * saved_right[31:16];
        product_10 <= saved_left[31:16] * saved_right[15:0];
        product_11 <= saved_left[31:16] * saved_right[31:16];
    end

    // 过程边界：always @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always @(posedge clk) begin
        // 复位相关判断：reset；分支方向由信号极性与取反表达式决定。
        if (reset) begin
            state <= IDLE;
            result <= 32'b0;
            saved_operation <= 3'b0;
            high_addend <= 18'b0;
            high_base <= 32'b0;
            sign_correction <= 32'b0;
            correct_left_sign <= 1'b0;
            correct_right_sign <= 1'b0;
            division_quotient <= 32'b0;
            division_remainder <= 32'b0;
            division_divisor <= 32'b0;
            division_remaining <= 6'b0;
            quotient_negative <= 1'b0;
            remainder_negative <= 1'b0;
        end else if (cancel) begin
            state <= IDLE;
        end else begin
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case (state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: begin
                    if (request_valid) begin
                        saved_operation <= operation;
                        if (!operation[2]) begin
                            correct_left_sign <= left[31] &&
                                ((operation == 3'b001) ||
                                 (operation == 3'b010));
                            correct_right_sign <= right[31] &&
                                (operation == 3'b001);
                            state <= MUL_PARTIAL;
                        end else if (right == 32'b0) begin
                            result <= operation[1] ? left : 32'hffffffff;
                            state <= RESPONSE;
                        end else if (!operation[0] &&
                                     (left == 32'h80000000) &&
                                     (right == 32'hffffffff)) begin
                            result <= operation[1] ? 32'b0 : 32'h80000000;
                            state <= RESPONSE;
                        end else begin
                            division_quotient <= (!operation[0] && left[31])
                                ? (~left + 32'd1) : left;
                            division_divisor <= (!operation[0] && right[31])
                                ? (~right + 32'd1) : right;
                            division_remainder <= 32'b0;
                            division_remaining <= 6'd32;
                            quotient_negative <= !operation[0] &&
                                (left[31] ^ right[31]);
                            remainder_negative <= !operation[0] && left[31];
                            state <= DIV_STEP;
                        end
                    end
                end

                // 状态/选择分支 MUL_PARTIAL：本分支规定该编码下的寄存器更新和下一步动作。
                MUL_PARTIAL: begin
                    // Interpreting A as signed subtracts B from the high
                    // unsigned product word when A[31] is set, and vice
                    // versa. Compute their modulo-2^32 sum alongside DSPs.
                    sign_correction <=
                        (correct_left_sign ? saved_right : 32'b0) +
                        (correct_right_sign ? saved_left : 32'b0);
                    state <= MUL_COLUMNS;
                end

                // 状态/选择分支 MUL_COLUMNS：本分支规定该编码下的寄存器更新和下一步动作。
                MUL_COLUMNS: begin
                    // Low MUL needs only the low two base-2^16 columns.
                    // The high path subtracts its signed correction here
                    // while assembling the narrow cross-product carry.
                    high_base <= product_11 - sign_correction;
                    high_addend <= {2'b0, product_01[31:16]} +
                                   {2'b0, product_10[31:16]} +
                                   {16'b0, middle_column[17:16]};
                    if (saved_operation == 3'b000) begin
                        result <= {middle_column[15:0], product_00[15:0]};
                        state <= RESPONSE;
                    end else begin
                        state <= MUL_HIGH;
                    end
                end

                // 状态/选择分支 MUL_HIGH：本分支规定该编码下的寄存器更新和下一步动作。
                MUL_HIGH: begin
                    result <= high_base + {14'b0, high_addend};
                    state <= RESPONSE;
                end

                // 状态/选择分支 DIV_STEP：本分支规定该编码下的寄存器更新和下一步动作。
                DIV_STEP: begin
                    if (!trial_difference[32]) begin
                        division_remainder <= trial_difference[31:0];
                        division_quotient <= {division_quotient[30:0], 1'b1};
                    end else begin
                        division_remainder <=
                            {division_remainder[30:0], division_quotient[31]};
                        division_quotient <= {division_quotient[30:0], 1'b0};
                    end
                    division_remaining <= division_remaining - 6'd1;
                    if (division_remaining == 6'd1)
                        state <= DIV_FINISH;
                end

                // 状态/选择分支 DIV_FINISH：本分支规定该编码下的寄存器更新和下一步动作。
                DIV_FINISH: begin
                    if (saved_operation[1])
                        result <= remainder_negative
                            ? (~division_remainder + 32'd1)
                            : division_remainder;
                    else
                        result <= quotient_negative
                            ? (~division_quotient + 32'd1)
                            : division_quotient;
                    state <= RESPONSE;
                end

                // 状态/选择分支 RESPONSE：本分支规定该编码下的寄存器更新和下一步动作。
                RESPONSE: begin
                    if (response_ready)
                        state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
