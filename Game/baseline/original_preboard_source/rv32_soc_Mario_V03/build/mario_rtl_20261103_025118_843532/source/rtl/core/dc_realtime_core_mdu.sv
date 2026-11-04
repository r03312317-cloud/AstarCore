module dc_realtime_core_mdu (
    input  logic clk,
    input  logic rst,
    input  logic cancel,
    input  logic req_valid,
    output logic req_ready,
    input  dc_realtime_core_pkg::dc_rt_m_op_e req_op,
    input  logic [31:0] req_rs1,
    input  logic [31:0] req_rs2,
    input  logic [31:0] req_pc,
    input  logic [31:0] req_instruction,
    input  logic [4:0] req_rd,
    input  logic [1:0] req_epoch,
    input  logic req_fast_context,
    output logic rsp_valid,
    input  logic rsp_ready,
    output logic [31:0] rsp_result,
    output logic [31:0] rsp_pc,
    output logic [31:0] rsp_instruction,
    output logic [4:0] rsp_rd,
    output logic [1:0] rsp_epoch,
    output logic rsp_fast_context,
    output logic busy
);
    timeunit 1ns;
    timeprecision 1ps;

    import dc_realtime_core_pkg::*;

    logic mul_req_valid;
    logic mul_req_ready;
    logic mul_rsp_valid;
    logic mul_rsp_ready;
    logic [31:0] mul_rsp_result;
    logic div_req_valid;
    logic div_req_ready;
    logic div_rsp_valid;
    logic div_rsp_ready;
    logic [31:0] div_rsp_result;
    logic owner_valid_q;
    logic owner_div_q;

    assign req_ready = !owner_valid_q && (req_op[2] ? div_req_ready : mul_req_ready);
    assign mul_req_valid = req_valid && req_ready && !req_op[2];
    assign div_req_valid = req_valid && req_ready && req_op[2];
    assign rsp_valid = owner_valid_q && (owner_div_q ? div_rsp_valid : mul_rsp_valid);
    assign rsp_result = owner_div_q ? div_rsp_result : mul_rsp_result;
    assign mul_rsp_ready = rsp_ready && owner_valid_q && !owner_div_q;
    assign div_rsp_ready = rsp_ready && owner_valid_q && owner_div_q;
    assign busy = owner_valid_q;

    dc_realtime_core_mul mul_unit (
        .clk, .rst, .cancel, .req_valid(mul_req_valid), .req_ready(mul_req_ready),
        .req_op, .req_rs1, .req_rs2, .rsp_valid(mul_rsp_valid),
        .rsp_ready(mul_rsp_ready), .rsp_result(mul_rsp_result)
    );

    dc_realtime_core_div div_unit (
        .clk, .rst, .cancel, .req_valid(div_req_valid), .req_ready(div_req_ready),
        .req_op, .req_rs1, .req_rs2, .rsp_valid(div_rsp_valid),
        .rsp_ready(div_rsp_ready), .rsp_result(div_rsp_result)
    );

    always_ff @(posedge clk) begin
        if (rst || cancel) begin
            owner_valid_q <= 1'b0;
            owner_div_q <= 1'b0;
            rsp_pc <= 32'd0;
            rsp_instruction <= 32'd0;
            rsp_rd <= 5'd0;
            rsp_epoch <= 2'd0;
            rsp_fast_context <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready)
                owner_valid_q <= 1'b0;
            if (req_valid && req_ready) begin
                owner_valid_q <= 1'b1;
                owner_div_q <= req_op[2];
                rsp_pc <= req_pc;
                rsp_instruction <= req_instruction;
                rsp_rd <= req_rd;
                rsp_epoch <= req_epoch;
                rsp_fast_context <= req_fast_context;
            end
        end
    end
endmodule
