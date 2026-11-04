`timescale 1ns/1ps
// Signed INT32 accumulator + per-channel quantizer, exactly matching the
// C Requant rounding modes for legal inputs. Five elastic stages separate
// add, multiply, magnitude/shift, rounding, and final INT8 clamp.
module soc_requant_pipeline (
    input  logic clk,
    input  logic rst,
    input  logic in_valid,
    output logic in_ready,
    input  logic signed [31:0] in_acc,
    input  logic signed [31:0] in_bias,
    input  logic signed [31:0] in_multiplier,
    input  logic [5:0] in_shift,
    input  logic [1:0] in_mode,
    input  logic signed [31:0] in_zero,
    input  logic signed [31:0] in_clamp_min,
    input  logic signed [31:0] in_clamp_max,
    output logic out_valid,
    input  logic out_ready,
    output logic signed [7:0] out_value,
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
    assign valid_configuration = in_multiplier >= 0 && in_shift <= 6'd62 &&
                                 in_mode <= 2'd2 && in_zero >= -32'sd128 &&
                                 in_zero <= 32'sd127 &&
                                 in_clamp_min >= -32'sd128 &&
                                 in_clamp_max <= 32'sd127 &&
                                 in_clamp_min <= in_clamp_max;
    assign sum_ext = {in_acc[31], in_acc} + {in_bias[31], in_bias};
    assign ready_4 = !valid_q[4] || out_ready;
    assign ready_3 = !valid_q[3] || ready_4;
    assign ready_2 = !valid_q[2] || ready_3;
    assign ready_1 = !valid_q[1] || ready_2;
    assign ready_0 = !valid_q[0] || ready_1;
    assign in_ready = !rst && valid_configuration && ready_0;
    assign out_valid = valid_q[4];
    assign out_value = value_q;
    assign out_overflow = overflow_5;

    function automatic logic round_up(
        input logic negative,
        input logic [1:0] mode,
        input logic quotient_lsb,
        input logic [63:0] remainder,
        input logic [63:0] half
    );
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

    always_ff @(posedge clk) begin
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
            if (ready_0) begin
                valid_q[0] <= in_valid && valid_configuration;
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
            if (ready_1) begin
                valid_q[1] <= valid_q[0];
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
            if (ready_2) begin
                valid_q[2] <= valid_q[1];
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
            if (ready_3) begin
                valid_q[3] <= valid_q[2];
                if (valid_q[2]) begin
                    shifted_q <= signed_rounded;
                    zero_4 <= zero_3;
                    minimum_4 <= minimum_3;
                    maximum_4 <= maximum_3;
                    overflow_4 <= overflow_3;
                end
            end
            if (ready_4) begin
                valid_q[4] <= valid_q[3];
                if (valid_q[3]) begin
                    if (zero_added < minimum_extended)
                        value_q <= minimum_4[7:0];
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
