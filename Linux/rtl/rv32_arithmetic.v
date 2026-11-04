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

// 乘除单元处理整数乘法高低位 除法及余数操作，结果通过握手返回。
// 请求被接受后保留操作类型 符号与操作数，后续输入改变不应改写正在计算的任务。
// 有符号与无符号运算使用不同扩展及符号恢复规则，特别注意最小负数边界。
// 除零与有符号溢出走显式边界处理，不依赖宿主语言的除法行为。
// 结果有效期间必须等待消费者接收，不能因下一次运算覆盖尚未消费的结果。
// 实际并行低位乘法路径另见 rv32_mul_stream，不能把两条路径的完成重复计数。
module rv32_arithmetic (
    input  wire        clk,
    input  wire        reset,
    input  wire        cancel,
    // request_valid 属于请求提议，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 接收事件由对应 valid 与 ready 同时成立决定。
    input  wire        request_valid,
    // request_ready 属于请求提议，保存接收或操作数就绪资格，须结合对应的有效位使用。
    output wire        request_ready,
    input  wire [2:0]  operation,
    // left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    input  wire [31:0] left,
    // right 保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    input  wire [31:0] right,
    // response_valid 属于响应边界，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 消费事件由响应 valid 与 ready 同时成立决定。
    output wire        response_valid,
    output wire        response_present,
    // response_ready 属于响应边界，保存接收或操作数就绪资格，须结合对应的有效位使用。
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

    // state 保存协议或执行状态，决定本周期允许的阶段与握手动作。
    reg [3:0] state;
    reg [2:0] saved_operation;
    // saved_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [31:0] saved_left;
    // saved_right 保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    reg [31:0] saved_right;

    reg [31:0] product_00;
    reg [31:0] product_01;
    reg [31:0] product_10;
    reg [31:0] product_11;
    reg [17:0] high_addend;
    reg [31:0] high_base;
    reg [31:0] sign_correction;
    wire [17:0] middle_column;
    // middle_column 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {2'b0, product_00[31:16]} +；复制大括号表示重复位域，不是独立队列元素。
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

    // request_ready 的资格组合为 (state == IDLE) && !reset && !cancel。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    assign request_ready = (state == IDLE) && !reset && !cancel;
    // Private registered availability for cancelled payload proposals only.
    // Public handshake validity remains immediately reset/cancel gated.
    // response_present 由比较式 (state == RESPONSE) 产生；该结果是条件判断，不是被比较的数据。
    assign response_present = (state == RESPONSE);
    // response_valid 的资格组合为 (state == RESPONSE) && !reset && !cancel。
    assign response_valid = (state == RESPONSE) && !reset && !cancel;

    // Timing-local payload pipeline. These registers do not own a request.
    // An accepted request at E0 is sampled into saved_left/right at E0;
    // MUL_PARTIAL at E1 uses those operands for sign_correction and the
    // products below sample them at E1. MUL_COLUMNS consumes the products
    // at E2, exactly as before. Other cycles are unobservable payload.
    // Deliberately no request/state/reset/cancel enable on the DSP pipeline.
    always @(posedge clk) begin
        // saved_left 在此时钟更新路径捕获 left，该更新仍受外层条件与后续同块赋值优先级限定。
        // 本时钟边界的 saved_left 捕获 left，两者在此路径上保持字段对应。
        saved_left <= left;
        // saved_right 在此时钟更新路径捕获 right，该更新仍受外层条件与后续同块赋值优先级限定。
        // 本时钟边界的 saved_right 捕获 right，两者在此路径上保持字段对应。
        saved_right <= right;
        // 本时钟边界的 product_00 按 saved_left[15:0] * saved_right[15:0] 计算，运算位宽与有无符号以原声明和显式扩展为准。
        product_00 <= saved_left[15:0] * saved_right[15:0];
        // 本时钟边界的 product_01 按 saved_left[15:0] * saved_right[31:16] 计算，运算位宽与有无符号以原声明和显式扩展为准。
        product_01 <= saved_left[15:0] * saved_right[31:16];
        // 本时钟边界的 product_10 按 saved_left[31:16] * saved_right[15:0] 计算，运算位宽与有无符号以原声明和显式扩展为准。
        product_10 <= saved_left[31:16] * saved_right[15:0];
        // 本时钟边界的 product_11 按 saved_left[31:16] * saved_right[31:16] 计算，运算位宽与有无符号以原声明和显式扩展为准。
        product_11 <= saved_left[31:16] * saved_right[31:16];
    end

    always @(posedge clk) begin
        // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
        if (reset) begin
            // state 在此时钟更新路径捕获 IDLE，该更新仍受外层条件与后续同块赋值优先级限定。
            // 本时钟边界的 state 捕获 IDLE，两者在此路径上保持字段对应。
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
                        // 本时钟边界的 saved_operation 捕获 operation，两者在此路径上保持字段对应。
                        saved_operation <= operation;
                        if (!operation[2]) begin
                            // 本时钟边界的 correct_left_sign 的资格组合为 left[31] &&。
                            correct_left_sign <= left[31] &&
                                ((operation == 3'b001) ||
                                 (operation == 3'b010));
                            // 本时钟边界的 correct_right_sign 的资格组合为 right[31] &&。
                            correct_right_sign <= right[31] &&
                                (operation == 3'b001);
                            // state 在此时钟更新路径捕获 MUL_PARTIAL，该更新仍受外层条件与后续同块赋值优先级限定。
                            // 本时钟边界的 state 捕获 MUL_PARTIAL，两者在此路径上保持字段对应。
                            state <= MUL_PARTIAL;
                        end else if (right == 32'b0) begin
                            // 本时钟边界的 result 按 operation[1] 进行来源选择。
                            // 真分支取 left；其余情况取 32'hffffffff。
                            result <= operation[1] ? left : 32'hffffffff;
                            // state 在此时钟更新路径捕获 RESPONSE，该更新仍受外层条件与后续同块赋值优先级限定。
                            // 本时钟边界的 state 捕获 RESPONSE，两者在此路径上保持字段对应。
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
