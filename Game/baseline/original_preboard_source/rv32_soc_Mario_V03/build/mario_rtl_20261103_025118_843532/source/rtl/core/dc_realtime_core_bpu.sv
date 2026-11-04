// V14: cycle-preserving bank-local BTB lookup and training.
// V13: parameterized private BTB capacity. Public index/tag outputs remain
// the original PC fingerprints used by the core's epoch/token integrity check.
module dc_realtime_core_bpu #(
    parameter int unsigned BTB_INDEX_BITS = 9,
    parameter int unsigned BANK_ROW_BITS = 5,
    parameter bit UPDATE_BYPASS = 1'b0,
    parameter bit LOOP_ENABLE = 1'b0
) (
    input  logic                                      clk,
    input  logic                                      rst,
    input  logic                                      query_valid,
    input  logic                                      query_accept,
    input  logic [31:0]                               query_pc,
    input  logic [1:0]                                query_epoch,
    input  logic [1:0]                                current_epoch,
    input  logic                                      predictor_flush,
    input  logic                                      update_valid,
    input  logic [31:0]                               update_pc,
    input  logic                                      update_taken,
    input  logic [31:0]                               update_target,
    input  dc_realtime_core_pkg::dc_rt_btb_type_e     update_type,
    input  logic [4:0]                                update_rd,
    input  logic [4:0]                                update_rs1,
    input  logic [31:0]                               update_immediate,
    input  logic                                      update_loop_token_valid,
    input  logic [4:0]                                update_loop_token_index,
    input  logic [24:0]                               update_loop_token_tag,
    input  logic [15:0]                               update_loop_token_iteration,
    input  logic [1:0]                                update_loop_token_epoch,
    input  logic                                      response_valid,
    input  logic [31:0]                               response_pc,
    input  logic [31:0]                               response_instruction,
    output logic                                      pred_valid,
    output logic                                      pred_taken,
    output logic [31:0]                               pred_target,
    output dc_realtime_core_pkg::dc_rt_pred_source_e pred_source,
    output logic [5:0]                                pred_btb_index,
    output logic [23:0]                               pred_btb_tag,
    output logic [1:0]                                pred_counter,
    output logic                                      direct_jal_valid,
    output logic [31:0]                               direct_jal_target,
    output logic                                      pred_loop_token_valid,
    output logic [4:0]                                pred_loop_token_index,
    output logic [24:0]                               pred_loop_token_tag,
    output logic [15:0]                               pred_loop_token_iteration,
    output logic [1:0]                                pred_loop_token_epoch,
    output logic                                      loop_override_valid,
    output logic                                      loop_override_taken
);
    timeunit 1ns;
    timeprecision 1ps;

    import dc_realtime_core_pkg::*;

    localparam int unsigned BTB_ENTRIES = 1 << BTB_INDEX_BITS;
    localparam int unsigned BTB_TAG_BITS = 30 - BTB_INDEX_BITS;
    logic [BTB_INDEX_BITS-1:0] lookup_index;
    logic [BTB_TAG_BITS-1:0] lookup_tag;
    localparam int unsigned ROW_BITS = (BANK_ROW_BITS < BTB_INDEX_BITS) ?
                                        BANK_ROW_BITS : BTB_INDEX_BITS - 1;
    localparam int unsigned BANK_BITS = BTB_INDEX_BITS - ROW_BITS;
    localparam int unsigned BANKS = 1 << BANK_BITS;
    logic [BANKS-1:0] bank_hit;
    logic [36:0] bank_payload [0:BANKS-1];
    logic [1:0] bank_update_counter [0:BANKS-1];
    logic [36:0] table_payload;

    logic [BTB_INDEX_BITS-1:0] update_index;
    logic [BTB_TAG_BITS-1:0] update_tag;
    logic query_array_hit;
    logic selected_hit;
    logic [31:0] selected_target;
    logic selected_backward;
    logic update_backward;
    dc_rt_btb_type_e selected_type;
    logic [1:0] selected_counter;
    logic [1:0] update_counter_value;
    logic [31:0] ras_stack_q [0:7];
    logic [3:0] ras_count_q;
    logic [2:0] ras_top_index;
    logic [31:0] response_jal_immediate;
    logic update_is_call;
    logic update_is_return;
    logic response_instruction_known;
    logic loop_query_is_backward_conditional;
    logic loop_query_hit_diag;
    logic [1:0] loop_query_confidence_diag;
    logic [15:0] loop_query_trip_count_diag;
    logic [15:0] loop_query_current_iteration_diag;
    logic loop_query_busy_diag;

    generate if (LOOP_ENABLE) begin : g_loop_predictor
    dc_realtime_core_loop_predictor loop_predictor (
        .clk,
        .rst,
        .query_valid,
        .query_accept,
        .query_pc,
        .query_is_backward_conditional(loop_query_is_backward_conditional),
        .query_epoch,
        .override_valid(loop_override_valid),
        .override_taken(loop_override_taken),
        .token_valid(pred_loop_token_valid),
        .token_index(pred_loop_token_index),
        .token_tag(pred_loop_token_tag),
        .token_iteration(pred_loop_token_iteration),
        .token_epoch(pred_loop_token_epoch),
        .resolve_valid(update_valid && update_type == DC_RT_BTB_CONDITIONAL),
        .resolve_pc(update_pc),
        .resolve_taken(update_taken),
        .resolve_token_valid(update_loop_token_valid),
        .resolve_token_index(update_loop_token_index),
        .resolve_token_tag(update_loop_token_tag),
        .resolve_token_iteration(update_loop_token_iteration),
        .resolve_token_epoch(update_loop_token_epoch),
        .current_epoch,
        .flush(predictor_flush),
        .query_hit(loop_query_hit_diag),
        .query_confidence(loop_query_confidence_diag),
        .query_trip_count(loop_query_trip_count_diag),
        .query_current_iteration(loop_query_current_iteration_diag),
        .query_busy(loop_query_busy_diag)
    );
    end else begin : g_no_loop_predictor
        assign loop_override_valid = 1'b0;
        assign loop_override_taken = 1'b0;
        assign pred_loop_token_valid = 1'b0;
        assign pred_loop_token_index = '0;
        assign pred_loop_token_tag = '0;
        assign pred_loop_token_iteration = '0;
        assign pred_loop_token_epoch = '0;
        assign loop_query_hit_diag = 1'b0;
        assign loop_query_confidence_diag = '0;
        assign loop_query_trip_count_diag = '0;
        assign loop_query_current_iteration_diag = '0;
        assign loop_query_busy_diag = 1'b0;
    end endgenerate

    // V14: sixteen 32-row banks at the default 512-entry capacity. The
    // indexed tag comparison and counter read/modify/write happen locally;
    // no 512-entry update read mux precedes the saturating-counter logic.
    for (genvar bank = 0; bank < BANKS; bank++) begin : g_btb_bank
        localparam logic [BANK_BITS-1:0] BANK_ID = BANK_BITS'(bank);
        dc_realtime_core_btb_bank #(
            .ROW_BITS(ROW_BITS), .TAG_BITS(BTB_TAG_BITS)
        ) storage (
            .clk, .rst,
            .query_select(lookup_index[BTB_INDEX_BITS-1:ROW_BITS] == BANK_ID),
            .query_row(lookup_index[ROW_BITS-1:0]), .query_tag(lookup_tag),
            .query_hit(bank_hit[bank]), .query_payload(bank_payload[bank]),
            .update_enable(update_valid && update_index[BTB_INDEX_BITS-1:ROW_BITS] == BANK_ID),
            .update_row(update_index[ROW_BITS-1:0]), .update_tag(update_tag),
            .update_target, .update_backward, .update_type, .update_taken,
            .update_counter(bank_update_counter[bank])
        );
    end

    always_comb begin
        table_payload = '0;
        update_counter_value = '0;
        for (int unsigned bank = 0; bank < BANKS; bank++) begin
            // Select by PC bank, NOT hit: even invalid payload remains a
            // don't-care exactly as before; valid/taken control is independent.
            table_payload |= bank_payload[bank];
            if (update_index[BTB_INDEX_BITS-1:ROW_BITS] == BANK_BITS'(bank))
                update_counter_value |= bank_update_counter[bank];
        end
    end

    always_comb begin
        pred_btb_index = query_pc[7:2] ^ query_pc[13:8];
        pred_btb_tag = query_pc[31:8];
        lookup_index = query_pc[BTB_INDEX_BITS+1:2] ^ query_pc[2*BTB_INDEX_BITS+1:BTB_INDEX_BITS+2];
        lookup_tag = query_pc[31:BTB_INDEX_BITS+2];
        update_index = update_pc[BTB_INDEX_BITS+1:2] ^ update_pc[2*BTB_INDEX_BITS+1:BTB_INDEX_BITS+2];
        update_tag = update_pc[31:BTB_INDEX_BITS+2];
        update_backward = update_target < update_pc;

        query_array_hit = |bank_hit;
        selected_hit = query_array_hit;
        selected_target = table_payload[36:5];
        selected_backward = table_payload[4];
        selected_type = dc_rt_btb_type_e'(table_payload[3:2]);
        selected_counter = table_payload[1:0];

        ras_top_index = ras_count_q[2:0] - 3'd1;
        response_jal_immediate = {
            {11{response_instruction[31]}}, response_instruction[31],
            response_instruction[19:12], response_instruction[20],
            response_instruction[30:21], 1'b0
        };
        response_instruction_known = 1'b1;
        // synthesis translate_off
        response_instruction_known = !$isunknown(response_instruction);
        // synthesis translate_on
        direct_jal_valid = response_valid && response_instruction_known &&
                           response_instruction[6:0] == 7'b1101111;
        direct_jal_target = response_pc + response_jal_immediate;

        update_is_call = update_valid && update_type == DC_RT_BTB_JAL_CALL &&
                         (update_rd == 5'd1 || update_rd == 5'd5);
        update_is_return = update_valid && update_type == DC_RT_BTB_RETURN &&
                           update_rd == 5'd0 &&
                           (update_rs1 == 5'd1 || update_rs1 == 5'd5) &&
                           update_immediate == 32'd0;

        if (UPDATE_BYPASS && update_valid && update_pc == query_pc) begin
            selected_hit = 1'b1;
            selected_target = update_target;
            selected_backward = update_backward;
            selected_type = update_type;
            selected_counter = update_counter_value;
        end

        loop_query_is_backward_conditional = selected_hit &&
                                             selected_type == DC_RT_BTB_CONDITIONAL &&
                                             selected_backward;

        pred_valid = query_valid && selected_hit;
        pred_taken = 1'b0;
        // Data and valid/taken control are parallel. Target is don't-care on
        // a BTB miss; the core consults it only for a valid taken prediction.
        pred_target = (selected_type == DC_RT_BTB_RETURN && ras_count_q != 4'd0) ?
                       ras_stack_q[ras_top_index] : selected_target;
        pred_source = DC_RT_PRED_SEQUENTIAL;
        pred_counter = selected_hit ? selected_counter : 2'b00;

        if (query_valid && selected_hit) begin
            if (selected_type == DC_RT_BTB_CONDITIONAL) begin
                if (loop_override_valid) begin
                    pred_taken = loop_override_taken;
                    pred_source = DC_RT_PRED_LOOP;
                end else begin
                    pred_taken = selected_counter[1];
                    pred_source = DC_RT_PRED_BHT;
                end
            end else begin
                pred_taken = 1'b1;
                pred_source = DC_RT_PRED_BTB;
                if (selected_type == DC_RT_BTB_RETURN && ras_count_q != 4'd0) begin
                    pred_source = DC_RT_PRED_RAS;
                end
            end
        end
    end


    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (!rst && query_valid &&
            $isunknown({loop_query_hit_diag, loop_query_confidence_diag,
                        loop_query_trip_count_diag,
                        loop_query_current_iteration_diag,
                        loop_query_busy_diag}))
            $error("CORE0_BPU_LOOP_DIAGNOSTIC_UNKNOWN");
    end
    // synthesis translate_on

    always_ff @(posedge clk) begin
        if (rst) begin
            ras_count_q <= 4'd0;
        end else begin
            if (update_is_call) begin
                if (ras_count_q < 4'd8) begin
                    ras_stack_q[ras_count_q[2:0]] <= update_pc + 32'd4;
                    ras_count_q <= ras_count_q + 4'd1;
                end else begin
                    // A ninth nested call replaces the most recent entry.
                    ras_stack_q[7] <= update_pc + 32'd4;
                end
            end else if (update_is_return && ras_count_q != 4'd0) begin
                ras_count_q <= ras_count_q - 4'd1;
            end
        end
    end
endmodule
