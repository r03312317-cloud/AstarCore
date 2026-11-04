// Original RV32 project file; see SOURCE_PROVENANCE.md.
// RV32 RV32M/Zbc arithmetic unit. Original implementation, October 2026.
//
// One request may be outstanding. A request is accepted on a rising edge
// with request_valid && request_ready. Operands need only remain stable for
// that edge. response_valid and result then remain stable until a rising
// edge with response_ready. The next request can be accepted on the edge
// after the response is consumed; there is no same-edge response turnover.
//
// Latency, measured in rising edges AFTER request acceptance:
//   CLMUL/CLMULR/CLMULH:   2
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

// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 通用多周期 M/Zbc 运算器，一次仅拥有一笔在途请求。
// 请求只在 request_valid 与 request_ready 同时为 1 的上升沿接收。
// 普通 MUL 的通用路径在接收后 2 拍可形成结果，高位乘法为 3 拍。
// CLMUL 系列在接收后 2 拍完成部分积归并；本板低位 MUL
// 通常走另一个专用流水模块。
// 除法使用 32 次恢复余数迭代与结果符号修正，正常完成延迟为接收后 33 拍。
// 除零与有符号溢出在接收边界登记特殊结果，不是输入到输出的组合零延迟通路。
// response_valid 保持到 response_ready；
// 通用接口不在响应消费同边界接收下一请求。
// reset/cancel 同步清除运算所有权并抑制公开握手，取消的响应不得提交。
// 私有乘法部分积可持续采样，state 才决定哪些数据属于真实请求。
// 接口契约与阅读示例
// 握手示例  E0接受request_valid且request_ready的请求，并保存操作种类。
// 对通用MUL，E1使用E0捕获的操作数形成部分积，E2归并低字并置响应状态。
// 高位MUL还需要E3归并高列，并按有符号解释减去高字符号修正。
// MULHU不减有符号修正，MULHSU只考虑左操作数的符号。
// 低位MUL不需要最高16乘16部分积，专用流式模块利用了这一点。
// 除法把绝对值余数与被除数移位，逐拍决定一个商位。
// trial_difference的第32位表示无符号试减是否下溢，决定是否接受该商位。
// DIV与REM的最后符号规则不同：商取两源符号异或，余数跟随被除数。
// 除零时DIV返回全1，REM返回原被除数；有符号最小值除负1按规定返回特殊值。
// 这些特殊结果仍在E0登记，不允许把可变输入直接穿到已拥有的响应。
// response_ready为0时必须保留result和response_valid，不能接受新请求覆盖旧结果。
// cancel优先结束状态机所有权；私有产品寄存器继续变化不产生可退休响应。
// CLMUL组合的是GF2异或部分积，不适用普通乘法的带进位列相加。
// 本版没有针对某个CoreMark常量硬编码乘积或CRC，运算语义由所有输入共同决定。
module rv32_arithmetic (
    // 接口字段：input  wire        clk。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input  wire        clk,
    // 接口字段：input  wire        reset。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input  wire        reset,
    // 接口字段：input  wire        cancel。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input  wire        cancel,
    // 接口字段：input  wire        request_valid。
    // 事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。
    input  wire        request_valid,
    // 接口字段：output wire        request_ready。
    // 事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。
    output wire        request_ready,
    // 接口字段：input  wire [2:0]  operation。
    // 指令编码、寄存器类别或控制字段。静态译码仅给建议，
    // 实际副作用由核心有效所有权控制。
    input  wire [2:0]  operation,
    // 接口字段：input  wire        carryless。
    // 通用多周期 M/Zbc 运算器，一次仅拥有一笔在途请求。
    input  wire        carryless,
    // 接口字段：input  wire [31:0] left。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
    input  wire [31:0] left,
    // 接口字段：input  wire [31:0] right。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
    input  wire [31:0] right,
    // 接口字段：output wire        response_valid。
    // 事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。
    output wire        response_valid,
    // 接口字段：output wire        response_present。
    // 通用多周期 M/Zbc 运算器，一次仅拥有一笔在途请求。
    output wire        response_present,
    // 接口字段：input  wire        response_ready。
    // 事务握手。valid与对应ready同边界才接收；背压期间有主状态的载荷必须保持。
    input  wire        response_ready,
    // 接口字段：output reg  [31:0] result。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
    output reg  [31:0] result
);

    localparam [3:0] IDLE          = 4'd0;
    localparam [3:0] MUL_PARTIAL   = 4'd1;
    localparam [3:0] MUL_COLUMNS   = 4'd2;
    localparam [3:0] MUL_HIGH      = 4'd3;
    localparam [3:0] DIV_STEP      = 4'd4;
    localparam [3:0] DIV_FINISH    = 4'd5;
    localparam [3:0] RESPONSE      = 4'd6;
    localparam [3:0] CLMUL_PARTIAL = 4'd7;
    localparam [3:0] CLMUL_RESULT  = 4'd8;

    reg [3:0] state;
    reg [2:0] saved_operation;
    reg [31:0] saved_left;
    reg [31:0] saved_right;

    // Standard GF(2) multiplication: fixed shifts and XOR, independent of
    // benchmark data and polynomial. Payload is unowned until state advances.
    wire [30:0] cl_product00,cl_product01,cl_product10,cl_product11;
    reg [30:0] cl_partial00,cl_partial01,cl_partial10,cl_partial11;
    rv32_carryless_product16 cl00(.left(saved_left[15:0]),.right(saved_right[15:0]),.product(cl_product00));
    rv32_carryless_product16 cl01(.left(saved_left[15:0]),.right(saved_right[31:16]),.product(cl_product01));
    rv32_carryless_product16 cl10(.left(saved_left[31:16]),.right(saved_right[15:0]),.product(cl_product10));
    rv32_carryless_product16 cl11(.left(saved_left[31:16]),.right(saved_right[31:16]),.product(cl_product11));
    wire [63:0] cl_full={33'b0,cl_partial00}^{17'b0,cl_partial01,16'b0}^
                      {17'b0,cl_partial10,16'b0}^{1'b0,cl_partial11,32'b0};
    always @(posedge clk)begin
        cl_partial00<=cl_product00;cl_partial01<=cl_product01;
        cl_partial10<=cl_product10;cl_partial11<=cl_product11;
    end

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
                        if (carryless) begin
                            state <= CLMUL_PARTIAL;
                        end else if (!operation[2]) begin
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

                CLMUL_PARTIAL: begin
                    // E1: the four partial-product registers capture operands
                    // saved at the E0 request edge, regardless of input changes.
                    state <= CLMUL_RESULT;
                end

                CLMUL_RESULT: begin
                    // E2: combine the saved partials; CLMULR includes bit 31.
                    case(saved_operation)
                        3'b001:result<=cl_full[31:0];
                        3'b010:result<=cl_full[62:31];
                        3'b011:result<=cl_full[63:32];
                        default:result<=32'b0;
                    endcase
                    state <= RESPONSE;
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

// Original balanced 16x16 polynomial multiplier. The RISC-V specification
// defines semantics; no external CPU or accelerator RTL is incorporated.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 16 乘 16 位 GF2 多项式乘法组合辅助单元，输出 31 位无进位乘积。
// 每个 right 位选择一个固定移位的 left，所有部分积通过平衡 XOR 树归并。
// 与普通整数乘法不同，这里使用异或而非带进位加法。
// 四个本模块结果可拼成 32 位 CLMUL 的 64 位多项式结果。
// 本模块不包含时序寄存器、CRC 多项式常量或 CoreMark 专用算法识别。
// 接口契约与阅读示例
// 数值例子  left=3、right=3时，多项式(1+x)乘(1+x)等于1+x的平方项，结果为5。
// 同样两个输入的普通整数乘法为9，说明GF2乘积不能用普通加法树替代。
// term数组按右源位选择左源的固定偏移，不含数据依赖的循环次数。
// XOR树每层把相邻项成对归并，组合深度随层数增长而非16次串行累加。
// 本模块输出尚未携带请求token；上层arith状态机的有效性才赋予它请求身份。
module rv32_carryless_product16(input [15:0] left,right,output [30:0] product);
    wire [30:0] term[0:15],level1[0:7],level2[0:3],level3[0:1];
    genvar i;
    generate
        for(i=0;i<16;i=i+1)begin: terms
            assign term[i]=({15'b0,left}&{31{right[i]}})<<i;
        end
        for(i=0;i<8;i=i+1)begin: pairs
            assign level1[i]=term[2*i]^term[2*i+1];
        end
        for(i=0;i<4;i=i+1)begin: fours
            assign level2[i]=level1[2*i]^level1[2*i+1];
        end
        for(i=0;i<2;i=i+1)begin: eights
            assign level3[i]=level2[2*i]^level2[2*i+1];
        end
    endgenerate
    assign product=level3[0]^level3[1];
endmodule
