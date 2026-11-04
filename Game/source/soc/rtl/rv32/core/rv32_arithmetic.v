// [ARCH] 整数算术/逻辑通路接收操作数和已经编码的运算控制。
// [ARCH] 加减、比较、移位和位操作生成候选，最终选择由控制字段决定。
// [ARCH] 带符号比较与无符号比较有不同扩展规则，不能只用结果最高位替代。
// [ARCH] 算术右移保留符号，逻辑右移补零，移位量使用相应低位。
// [ARCH] 本模块不持有退休资格，外部必须用有效包和目的身份限定结果。
// [ARCH] 双桶形移位器是实现策略，不代表额外的软件扩展已经完整验收。
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

`default_nettype none

module rv32_arithmetic (
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input  wire        clk,
    // [ARCH] reset：复位控制不同于 PLL/DDR 就绪；具体极性与同步方式按本模块时序块执行。
    input  wire        reset,
    input  wire        cancel,
    // [ARCH] request_valid（请求所有权）：标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。
    input  wire        request_valid,
    // [ARCH] request_ready（请求所有权）：标记操作数或下游接纳条件已满足；还需检查相应有效身份。
    output wire        request_ready,
    input  wire [2:0]  operation,
    // [ARCH] left：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 saved_left, correct_left_sign, result, division_quotient 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  wire [31:0] left,
    // [ARCH] right：右操作数与来源 tag/就绪位配套，广播匹配后才可消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 saved_right, correct_right_sign, division_divisor 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  wire [31:0] right,
    // [ARCH] response_valid（响应所有权）：标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。
    output wire        response_valid,
    output wire        response_present,
    // [ARCH] response_ready（响应所有权）：标记操作数或下游接纳条件已满足；还需检查相应有效身份。
    input  wire        response_ready,
    output reg  [31:0] result
);

    localparam [3:0] IDLE          = 4'd0;
    localparam [3:0] MUL_PARTIAL   = 4'd1;
    localparam [3:0] MUL_COLUMNS   = 4'd2;
    localparam [3:0] MUL_HIGH      = 4'd3;
    localparam [3:0] DIV_STEP      = 4'd4;
    localparam [3:0] DIV_FINISH    = 4'd5;
    localparam [3:0] RESPONSE      = 4'd6;

    // [ARCH] state：协议阶段寄存器决定当前允许的请求、等待与完成行为。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 request_ready, response_present, response_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [3:0] state;
    reg [2:0] saved_operation;
    // [ARCH] saved_left（已保存的上下文）：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 product_00, product_01, product_10, product_11 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [31:0] saved_left;
    // [ARCH] saved_right（已保存的上下文）：右操作数与来源 tag/就绪位配套，广播匹配后才可消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 product_00, product_01, product_10, product_11 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
    // [ARCH] correct_left_sign：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    reg correct_left_sign;
    // [ARCH] correct_right_sign：右操作数与来源 tag/就绪位配套，广播匹配后才可消费。
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

    always @(posedge clk) begin
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
            case (state)
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

                MUL_PARTIAL: begin
                    // Interpreting A as signed subtracts B from the high
                    // unsigned product word when A[31] is set, and vice
                    // versa. Compute their modulo-2^32 sum alongside DSPs.
                    sign_correction <=
                        (correct_left_sign ? saved_right : 32'b0) +
                        (correct_right_sign ? saved_left : 32'b0);
                    state <= MUL_COLUMNS;
                end

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

                MUL_HIGH: begin
                    result <= high_base + {14'b0, high_addend};
                    state <= RESPONSE;
                end

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
