// 架构导读：soc_requant_pipeline。
// 重量化算术流水，处理乘数、移位、舍入、零点与饱和边界。
`timescale 1ns/1ps
// Signed INT32 accumulator + per-channel quantizer, exactly matching the
// C Requant rounding modes for legal inputs. Five elastic stages separate
// add, multiply, magnitude/shift, rounding, and final INT8 clamp.
module soc_requant_pipeline (
    // 接口声明：input logic clk。
    // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
    input  logic clk,
    // 接口声明：input logic rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input  logic rst,
    // 接口声明：input logic in_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic in_valid,
    // 接口声明：output logic in_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic in_ready,
    // 接口声明：input logic signed [31:0] in_acc。
    // 保存或选择累加结果，符号与精度由声明及算术表达式决定。
    input  logic signed [31:0] in_acc,
    // 接口声明：input logic signed [31:0] in_bias。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] in_bias,
    // 接口声明：input logic signed [31:0] in_multiplier。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] in_multiplier,
    // 接口声明：input logic [5:0] in_shift。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [5:0] in_shift,
    // 接口声明：input logic [1:0] in_mode。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [1:0] in_mode,
    // 接口声明：input logic signed [31:0] in_zero。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] in_zero,
    // 接口声明：input logic signed [31:0] in_clamp_min。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] in_clamp_min,
    // 接口声明：input logic signed [31:0] in_clamp_max。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] in_clamp_max,
    // 接口声明：output logic out_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic out_valid,
    // 接口声明：input logic out_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic out_ready,
    // 接口声明：output logic signed [7:0] out_value。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic signed [7:0] out_value,
    // 接口声明：output logic out_overflow。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic out_overflow
);
    logic [4:0] valid_q;
    logic ready_0, ready_1, ready_2, ready_3, ready_4;
    logic signed [32:0] sum_ext;
    logic signed [31:0] sum_q;
    logic signed [31:0] multiplier_q;
    logic [5:0] shift_1, shift_2;
    logic [1:0] mode_1, mode_2, mode_3;
    logic signed [31:0] zero_1, zero_2, zero_3, zero_4;
    logic signed [31:0] minimum_1, minimum_2, minimum_3, minimum_4;
    logic signed [31:0] maximum_1, maximum_2, maximum_3, maximum_4;
    logic overflow_1, overflow_2, overflow_3, overflow_4, overflow_5;
    logic signed [63:0] product_q;
    logic negative_q;
    logic [63:0] quotient_q, remainder_q, half_q;
    logic signed [63:0] shifted_q;
    logic signed [7:0] value_q;

    logic valid_configuration;
    // 组合连接 valid_configuration：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign valid_configuration = in_multiplier >= 0 && in_shift <= 6'd62 &&
                                 in_mode <= 2'd2 && in_zero >= -32'sd128 &&
                                 in_zero <= 32'sd127 &&
                                 in_clamp_min >= -32'sd128 &&
                                 in_clamp_max <= 32'sd127 &&
                                 in_clamp_min <= in_clamp_max;
    // 组合连接 sum_ext：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign sum_ext = {in_acc[31], in_acc} + {in_bias[31], in_bias};
    // 组合连接 ready_4：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign ready_4 = !valid_q[4] || out_ready;
    // 组合连接 ready_3：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign ready_3 = !valid_q[3] || ready_4;
    // 组合连接 ready_2：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign ready_2 = !valid_q[2] || ready_3;
    // 组合连接 ready_1：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign ready_1 = !valid_q[1] || ready_2;
    // 组合连接 ready_0：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign ready_0 = !valid_q[0] || ready_1;
    // 组合连接 in_ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
    assign in_ready = !rst && valid_configuration && ready_0;
    // 组合连接 out_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
    assign out_valid = valid_q[4];
    // 组合连接 out_value：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign out_value = value_q;
    // 组合连接 out_overflow：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign out_overflow = overflow_5;

    // 局部运算/辅助过程：function automatic logic round_up(。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function automatic logic round_up(
        // 接口声明：input logic negative。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input logic negative,
        // 接口声明：input logic [1:0] mode。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input logic [1:0] mode,
        // 接口声明：input logic quotient_lsb。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input logic quotient_lsb,
        // 接口声明：input logic [63:0] remainder。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input logic [63:0] remainder,
        // 接口声明：input logic [63:0] half。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input logic [63:0] half
    );
        // 按 mode 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
        case (mode)
            2'd0: round_up = negative && remainder != 0;
            2'd1: round_up = remainder >= half;
            default: round_up = remainder > half ||
                                (remainder == half && quotient_lsb);
        endcase
    endfunction

    logic [63:0] product_magnitude;
    logic [63:0] rounded_magnitude;
    logic signed [63:0] signed_rounded;
    logic signed [63:0] zero_added;
    logic signed [63:0] minimum_extended, maximum_extended;
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        product_magnitude = product_q < 0 ? $unsigned(-product_q) : $unsigned(product_q);
        rounded_magnitude = quotient_q + 64'(round_up(negative_q, mode_3,
                                                       quotient_q[0], remainder_q, half_q));
        signed_rounded = negative_q ? -$signed(rounded_magnitude) :
                                      $signed(rounded_magnitude);
        zero_added = shifted_q + {{32{zero_4[31]}}, zero_4};
        minimum_extended = {{32{minimum_4[31]}}, minimum_4};
        maximum_extended = {{32{maximum_4[31]}}, maximum_4};
    end

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            valid_q <= '0;
            sum_q <= '0;
            multiplier_q <= '0;
            shift_1 <= '0;
            shift_2 <= '0;
            mode_1 <= '0;
            mode_2 <= '0;
            mode_3 <= '0;
            zero_1 <= '0;
            zero_2 <= '0;
            zero_3 <= '0;
            zero_4 <= '0;
            minimum_1 <= '0;
            minimum_2 <= '0;
            minimum_3 <= '0;
            minimum_4 <= '0;
            maximum_1 <= '0;
            maximum_2 <= '0;
            maximum_3 <= '0;
            maximum_4 <= '0;
            overflow_1 <= 1'b0;
            overflow_2 <= 1'b0;
            overflow_3 <= 1'b0;
            overflow_4 <= 1'b0;
            overflow_5 <= 1'b0;
            product_q <= '0;
            negative_q <= 1'b0;
            quotient_q <= '0;
            remainder_q <= '0;
            half_q <= '0;
            shifted_q <= '0;
            value_q <= '0;
        end else begin
            // 条件分支：检查 ready_0。
            if (ready_0) begin
                valid_q[0] <= in_valid && valid_configuration;
                // 条件分支：检查 in_valid && valid_configuration。
                if (in_valid && valid_configuration) begin
                    sum_q <= sum_ext[31:0];
                    multiplier_q <= in_multiplier;
                    shift_1 <= in_shift;
                    mode_1 <= in_mode;
                    zero_1 <= in_zero;
                    minimum_1 <= in_clamp_min;
                    maximum_1 <= in_clamp_max;
                    overflow_1 <= sum_ext > 33'sh0_7fff_ffff ||
                                  sum_ext < -33'sh0_8000_0000;
                end
            end
            // 条件分支：检查 ready_1。
            if (ready_1) begin
                valid_q[1] <= valid_q[0];
                // 条件分支：检查 valid_q[0]。
                if (valid_q[0]) begin
                    product_q <= $signed(sum_q) * $signed(multiplier_q);
                    shift_2 <= shift_1;
                    mode_2 <= mode_1;
                    zero_2 <= zero_1;
                    minimum_2 <= minimum_1;
                    maximum_2 <= maximum_1;
                    overflow_2 <= overflow_1;
                end
            end
            // 条件分支：检查 ready_2。
            if (ready_2) begin
                valid_q[2] <= valid_q[1];
                // 条件分支：检查 valid_q[1]。
                if (valid_q[1]) begin
                    negative_q <= product_q < 0;
                    quotient_q <= product_magnitude >> shift_2;
                    remainder_q <= shift_2 == 0 ? 64'd0 :
                                   product_magnitude & ((64'd1 << shift_2) - 64'd1);
                    half_q <= shift_2 == 0 ? 64'd1 : 64'd1 << (shift_2 - 6'd1);
                    mode_3 <= mode_2;
                    zero_3 <= zero_2;
                    minimum_3 <= minimum_2;
                    maximum_3 <= maximum_2;
                    overflow_3 <= overflow_2;
                end
            end
            // 条件分支：检查 ready_3。
            if (ready_3) begin
                valid_q[3] <= valid_q[2];
                // 条件分支：检查 valid_q[2]。
                if (valid_q[2]) begin
                    shifted_q <= signed_rounded;
                    zero_4 <= zero_3;
                    minimum_4 <= minimum_3;
                    maximum_4 <= maximum_3;
                    overflow_4 <= overflow_3;
                end
            end
            // 条件分支：检查 ready_4。
            if (ready_4) begin
                valid_q[4] <= valid_q[3];
                // 条件分支：检查 valid_q[3]。
                if (valid_q[3]) begin
                    // 条件分支：检查 zero_added < minimum_extended。
                    if (zero_added < minimum_extended)
                        value_q <= minimum_4[7:0];
                    // 条件分支：检查 zero_added > maximum_extended。
                    else if (zero_added > maximum_extended)
                        value_q <= maximum_4[7:0];
                    else
                        value_q <= zero_added[7:0];
                    overflow_5 <= overflow_4;
                end
            end
        end
    end
endmodule
