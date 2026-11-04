module dc_realtime_core_div (
    input  logic clk,
    input  logic rst,
    input  logic cancel,
    input  logic req_valid,
    output logic req_ready,
    input  dc_realtime_core_pkg::dc_rt_m_op_e req_op,
    input  logic [31:0] req_rs1,
    input  logic [31:0] req_rs2,
    output logic rsp_valid,
    input  logic rsp_ready,
    output logic [31:0] rsp_result
);
    timeunit 1ns;
    timeprecision 1ps;

    import dc_realtime_core_pkg::*;

    logic busy_q;
    logic [5:0] count_q;
    logic [31:0] dividend_q;
    logic [31:0] divisor_q;
    logic [31:0] quotient_q;
    logic [32:0] remainder_q;
    logic quotient_negative_q;
    logic remainder_negative_q;
    logic result_remainder_q;
    logic [32:0] shifted_remainder;
    logic [32:0] reduced_remainder;
    logic [31:0] next_quotient;
    logic trial_ge_divisor;
    logic [31:0] quotient_magnitude;
    logic [31:0] remainder_magnitude;

    assign req_ready = !busy_q && !rsp_valid;
    assign shifted_remainder = (remainder_q << 1) |
                               {{32{1'b0}}, dividend_q[31]};
    assign trial_ge_divisor = shifted_remainder >= {1'b0, divisor_q};
    assign reduced_remainder = trial_ge_divisor ?
                               shifted_remainder - {1'b0, divisor_q} :
                               shifted_remainder;
    assign next_quotient = (quotient_q << 1) |
                           {31'd0, trial_ge_divisor};
    assign quotient_magnitude = quotient_negative_q ? -next_quotient : next_quotient;
    assign remainder_magnitude = remainder_negative_q ?
                                 -reduced_remainder[31:0] : reduced_remainder[31:0];

    // The divisor is consumed only while busy. Capture during the local idle
    // window, including the real request edge; never couple this wide CE to
    // upstream issue, cancellation, or corner-case response qualification.
    always_ff @(posedge clk) begin
        if (rst)
            divisor_q <= 32'd0;
        else if (req_ready)
            divisor_q <= ((req_op == DC_RT_M_DIV || req_op == DC_RT_M_REM) &&
                          req_rs2[31]) ? -req_rs2 : req_rs2;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            count_q <= 6'd0;
            dividend_q <= 32'd0;
            quotient_q <= 32'd0;
            remainder_q <= 33'd0;
            quotient_negative_q <= 1'b0;
            remainder_negative_q <= 1'b0;
            result_remainder_q <= 1'b0;
        end else if (req_ready) begin
            // Local idle capture includes the accepting edge. Cancellation
            // invalidates control only; the next request reinitializes all data.
            count_q <= 6'd0;
            dividend_q <= ((req_op == DC_RT_M_DIV || req_op == DC_RT_M_REM) &&
                           req_rs1[31]) ? -req_rs1 : req_rs1;
            quotient_q <= 32'd0;
            remainder_q <= 33'd0;
            quotient_negative_q <= (req_op == DC_RT_M_DIV) &&
                                   (req_rs1[31] ^ req_rs2[31]);
            remainder_negative_q <= (req_op == DC_RT_M_REM) && req_rs1[31];
            result_remainder_q <= req_op == DC_RT_M_REM || req_op == DC_RT_M_REMU;
        end else if (busy_q) begin
            count_q <= count_q + 6'd1;
            dividend_q <= {dividend_q[30:0], 1'b0};
            quotient_q <= next_quotient;
            remainder_q <= reduced_remainder;
        end
    end

    // Payload can change while invalid. Only registered response validity
    // controls holding; late operand comparisons never control this bank's CE.
    always_ff @(posedge clk) begin
        if (rst)
            rsp_result <= 32'd0;
        else if (rsp_valid) begin
            // Hold until consumed or cancelled, including backpressure.
        end else begin
            rsp_result <= busy_q ?
                (result_remainder_q ? remainder_magnitude : quotient_magnitude) :
                ((req_op == DC_RT_M_REM || req_op == DC_RT_M_REMU) ?
                    (req_rs2 == 32'd0 ? req_rs1 : 32'd0) :
                    (req_rs2 == 32'd0 ? 32'hffff_ffff : 32'h8000_0000));
        end
    end

    // Architectural control and corner-case response timing are unchanged.
    always_ff @(posedge clk) begin
        if (rst || cancel) begin
            busy_q <= 1'b0;
            rsp_valid <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            if (busy_q) begin
                if (count_q == 6'd31) begin
                    busy_q <= 1'b0;
                    rsp_valid <= 1'b1;
                end
            end

            if (req_valid && req_ready) begin
                if (req_rs2 == 32'd0) begin
                    rsp_valid <= 1'b1;
                end else if (req_op == DC_RT_M_DIV && req_rs1 == 32'h8000_0000 &&
                             req_rs2 == 32'hffff_ffff) begin
                    rsp_valid <= 1'b1;
                end else if (req_op == DC_RT_M_REM && req_rs1 == 32'h8000_0000 &&
                             req_rs2 == 32'hffff_ffff) begin
                    rsp_valid <= 1'b1;
                end else begin
                    busy_q <= 1'b1;
                end
            end
        end
    end
endmodule
