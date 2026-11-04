module dc_realtime_core_mul (
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

    logic [31:0] registered_result;
    logic product_valid_q;
    dc_rt_m_op_e op_q;
    logic signed [32:0] req_a_ext;
    logic signed [32:0] req_b_ext;
    logic [15:0] req_a_low;
    logic [15:0] req_b_low;
    logic signed [16:0] req_a_high;
    logic signed [16:0] req_b_high;
    logic [31:0] pp_ll_q;
    logic signed [33:0] pp_lh_q;
    logic signed [33:0] pp_hl_q;
    logic signed [33:0] pp_hh_q;

    logic signed [66:0] pp_ll_extended;
    logic signed [66:0] pp_lh_extended;
    logic signed [66:0] pp_hl_extended;
    logic signed [66:0] pp_hh_extended;
    logic signed [66:0] product_reconstructed;
    logic product_extension_valid;

    assign rsp_result = op_q == DC_RT_M_MUL ? product_reconstructed[31:0] : registered_result;
    assign req_ready = !product_valid_q && !rsp_valid;

    always_comb begin
        req_a_ext = (req_op == DC_RT_M_MULH || req_op == DC_RT_M_MULHSU) ?
                    $signed({req_rs1[31], req_rs1}) : $signed({1'b0, req_rs1});
        req_b_ext = req_op == DC_RT_M_MULH ?
                    $signed({req_rs2[31], req_rs2}) : $signed({1'b0, req_rs2});
        req_a_low = req_a_ext[15:0];
        req_b_low = req_b_ext[15:0];
        req_a_high = req_a_ext[32:16];
        req_b_high = req_b_ext[32:16];

        pp_ll_extended = $signed({35'd0, pp_ll_q});
        pp_lh_extended = $signed({{33{pp_lh_q[33]}}, pp_lh_q}) <<< 16;
        pp_hl_extended = $signed({{33{pp_hl_q[33]}}, pp_hl_q}) <<< 16;
        pp_hh_extended = $signed({{33{pp_hh_q[33]}}, pp_hh_q}) <<< 32;
        product_reconstructed = pp_ll_extended + pp_lh_extended +
                                pp_hl_extended + pp_hh_extended;
        if (op_q == DC_RT_M_MULH || op_q == DC_RT_M_MULHSU)
            product_extension_valid = product_reconstructed[66:64] ==
                                      {3{product_reconstructed[63]}};
        else
            product_extension_valid = product_reconstructed[66:64] == 3'b000;
    end

    // The operation tag is captured on the same local accepting boundary as
    // the DSP A/B input registers. Invalid idle pre-capture remains harmless.
    always_ff @(posedge clk) begin
        if (rst)
            op_q <= DC_RT_M_MUL;
        else if (req_valid && req_ready)
            op_q <= req_op;
    end

    dc_realtime_mul_backend partial_products (
        .clk, .rst, .operand_ce(req_ready),
        .product_ce(req_valid && req_ready),
        .req_a_low, .req_b_low, .req_a_high, .req_b_high,
        .pp_ll_q, .pp_lh_q, .pp_hl_q, .pp_hh_q
    );

    always_ff @(posedge clk) begin
        if (rst)
            registered_result <= 32'd0;
        else if (!rsp_valid)
            registered_result <= op_q == DC_RT_M_MUL ?
                          product_reconstructed[31:0] :
                          product_reconstructed[63:32];
    end

    always_ff @(posedge clk) begin
        if (rst || cancel) begin
            product_valid_q <= 1'b0;
            rsp_valid <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            if (product_valid_q) begin
                // synthesis translate_off
                if (!product_extension_valid)
                    $error("CORE0_RV32M_MULTIPLY_EXTENSION_INVALID");
                // synthesis translate_on
                rsp_valid <= 1'b1;
                product_valid_q <= 1'b0;
            end

            // DSP P registers capture on the accepting edge. The low
            // product can complete immediately in the following cycle;
            // high-product reconstruction keeps its existing extra cycle.
            if (req_valid && req_ready) begin
                if (req_op == DC_RT_M_MUL) rsp_valid <= 1'b1;
                else product_valid_q <= 1'b1;
            end
        end
    end
endmodule
