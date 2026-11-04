// A physical BTB bank, not another cache way. Index/tag/training semantics
// match V13. No extra query latency and no change in total table capacity.
// ADS syn_hier="hard": preserve a local memory/compare/update boundary while
// allowing constant propagation. This is a synthesis hint, NOT timing proof.
module dc_realtime_core_btb_bank #(
    parameter int unsigned ROW_BITS = 5,
    parameter int unsigned TAG_BITS = 21
) (
    input logic clk, rst,
    input logic query_select,
    input logic [ROW_BITS-1:0] query_row,
    input logic [TAG_BITS-1:0] query_tag,
    output logic query_hit,
    output logic [36:0] query_payload,
    input logic update_enable,
    input logic [ROW_BITS-1:0] update_row,
    input logic [TAG_BITS-1:0] update_tag,
    input logic [31:0] update_target,
    input logic update_backward,
    input dc_realtime_core_pkg::dc_rt_btb_type_e update_type,
    input logic update_taken,
    output logic [1:0] update_counter
) /* synthesis syn_hier="hard" */;
    timeunit 1ns;
    timeprecision 1ps;
    import dc_realtime_core_pkg::*;
    localparam int unsigned ROWS = 1 << ROW_BITS;
    // Control = {tag, backward, type[1:0], counter[1:0]}.
    logic [ROWS-1:0] valid_q;
    logic [TAG_BITS+4:0] control_q [0:ROWS-1] /* synthesis syn_ramstyle="lut_ram" */;
    logic [31:0] target_q [0:ROWS-1] /* synthesis syn_ramstyle="lut_ram" */;
    logic [TAG_BITS+4:0] qcontrol, ucontrol;
    logic update_hit;
    assign qcontrol = control_q[query_row];
    assign ucontrol = control_q[update_row];
    assign query_hit = query_select && valid_q[query_row] &&
                       qcontrol[TAG_BITS+4:5] == query_tag;
    assign query_payload = {37{query_select}} & {target_q[query_row], qcontrol[4:0]};
    assign update_hit = valid_q[update_row] &&
                        ucontrol[TAG_BITS+4:5] == update_tag;
    always_comb begin
        if (update_type == DC_RT_BTB_CONDITIONAL && update_hit &&
            ucontrol[3:2] == DC_RT_BTB_CONDITIONAL) begin
            case (ucontrol[1:0])
                2'b00: update_counter = update_taken ? 2'b01 : 2'b00;
                2'b01: update_counter = update_taken ? 2'b10 : 2'b00;
                2'b10: update_counter = update_taken ? 2'b11 : 2'b01;
                2'b11: update_counter = update_taken ? 2'b11 : 2'b10;
                default: update_counter = 2'b01;
            endcase
        end else begin
            update_counter = (update_type != DC_RT_BTB_CONDITIONAL || update_backward) ?
                             2'b10 : 2'b01;
        end
    end
    always_ff @(posedge clk) begin
        if (rst) valid_q <= '0;
        else if (update_enable) begin
            valid_q[update_row] <= 1'b1;
            control_q[update_row] <= {update_tag, update_backward, update_type, update_counter};
            target_q[update_row] <= update_target;
        end
    end
endmodule
