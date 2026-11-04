module dc_realtime_core_loop_predictor (
    input  logic        clk,
    input  logic        rst,
    input  logic        query_valid,
    input  logic        query_accept,
    input  logic [31:0] query_pc,
    input  logic        query_is_backward_conditional,
    input  logic [1:0]  query_epoch,
    output logic        override_valid,
    output logic        override_taken,
    output logic        token_valid,
    output logic [4:0]  token_index,
    output logic [24:0] token_tag,
    output logic [15:0] token_iteration,
    output logic [1:0]  token_epoch,
    input  logic        resolve_valid,
    input  logic [31:0] resolve_pc,
    input  logic        resolve_taken,
    input  logic        resolve_token_valid,
    input  logic [4:0]  resolve_token_index,
    input  logic [24:0] resolve_token_tag,
    input  logic [15:0] resolve_token_iteration,
    input  logic [1:0]  resolve_token_epoch,
    input  logic [1:0]  current_epoch,
    input  logic        flush,
    output logic        query_hit,
    output logic [1:0]  query_confidence,
    output logic [15:0] query_trip_count,
    output logic [15:0] query_current_iteration,
    output logic        query_busy
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [31:0] valid_q;
    logic [24:0] tag_q [0:31];
    logic [15:0] trip_count_q [0:31];
    logic [15:0] current_iteration_q [0:31];
    logic [1:0] confidence_q [0:31];
    logic [1:0] age_q [0:31];
    logic direction_q [0:31];
    logic [31:0] prediction_taken_q;
    // 分 bank 存储：ADS 的 DRC-1021 不接受同一向量被多个 always_ff 分区驱动
    // （原写法在 genvar bank 内写 prediction_taken_q[bank*8 +: 8] 与动态位选）。
    // 拆成 4 个独立 8 位存储再按原字节位置拼接，分 bank 比较器结构与时序不变。
    logic [7:0] prediction_taken_bank_q [0:3];

    logic [31:0] busy_q;
    logic [24:0] busy_tag_q [0:31];
    logic [15:0] busy_iteration_q [0:31];
    logic [1:0] busy_epoch_q [0:31];

    logic [24:0] resolve_pc_tag;
    logic resolve_owner_match;
    logic resolve_table_hit;
    logic [15:0] incremented_iteration;
    logic [1:0] incremented_confidence;
    logic [1:0] decremented_confidence;
    logic [1:0] incremented_age;

    // Compare each fixed entry locally, then reduce one-bit results. A
    // dynamically indexed 25-bit tag mux followed by comparison put the
    // complete RAM lookup on the PC -> next-PC prediction path in PDS.
    // Index, tag, confidence and age semantics remain cycle-identical.
    logic [31:0] query_entry_hit, query_entry_override;
    for (genvar entry = 0; entry < 32; entry++) begin : query_entry
        assign query_entry_hit[entry] = token_index == 5'(entry) &&
            valid_q[entry] && direction_q[entry] && tag_q[entry] == token_tag;
        assign query_entry_override[entry] = query_entry_hit[entry] &&
            confidence_q[entry] == 2'b11 && age_q[entry] != 2'b00;
    end

    // Each update comparator reads only its eight-entry bank. The query
    // interface and the cycle of prediction/ownership updates are unchanged.
    for (genvar bank = 0; bank < 4; bank++) begin : prediction_bank
        localparam logic [1:0] BANK_ID = 2'(bank);
        logic [15:0] selected_trip;
        logic next_taken;
        assign selected_trip = trip_count_q[{BANK_ID, resolve_token_index[2:0]}];
        assign next_taken = resolve_taken ?
            (resolve_table_hit && incremented_iteration < selected_trip) :
            (resolve_token_iteration != 16'd0);
        always_ff @(posedge clk) begin
            if (rst)
                prediction_taken_bank_q[bank] <= 8'd0;
            else if (resolve_owner_match &&
                     resolve_token_epoch == current_epoch &&
                     resolve_token_index[4:3] == BANK_ID)
                prediction_taken_bank_q[bank][int'(resolve_token_index[2:0])] <= next_taken;
        end
    end

    assign prediction_taken_q = {prediction_taken_bank_q[3],
                                 prediction_taken_bank_q[2],
                                 prediction_taken_bank_q[1],
                                 prediction_taken_bank_q[0]};

    always_comb begin
        token_index = query_pc[6:2];
        token_tag = query_pc[31:7];
        token_iteration = current_iteration_q[token_index];
        token_epoch = query_epoch;

        query_hit = |query_entry_hit;
        query_busy = busy_q[token_index];
        query_confidence = query_hit ? confidence_q[token_index] : 2'b00;
        query_trip_count = query_hit ? trip_count_q[token_index] : 16'd0;
        query_current_iteration = query_hit ?
                                  current_iteration_q[token_index] : 16'd0;

        token_valid = query_valid && query_pc[1:0] == 2'b00 &&
                      query_is_backward_conditional &&
                      !query_busy;
        override_valid = token_valid && (|query_entry_override);
        override_taken = prediction_taken_q[token_index];

        resolve_pc_tag = resolve_pc[31:7];
        resolve_owner_match = resolve_valid && resolve_token_valid &&
                              busy_q[resolve_token_index] &&
                              busy_tag_q[resolve_token_index] == resolve_token_tag &&
                              busy_iteration_q[resolve_token_index] ==
                                  resolve_token_iteration &&
                              busy_epoch_q[resolve_token_index] ==
                                  resolve_token_epoch &&
                              resolve_pc_tag == resolve_token_tag &&
                              resolve_pc[6:2] == resolve_token_index &&
                              resolve_pc[1:0] == 2'b00;
        resolve_table_hit = valid_q[resolve_token_index] &&
                            tag_q[resolve_token_index] == resolve_token_tag &&
                            direction_q[resolve_token_index];

        incremented_iteration = resolve_token_iteration == 16'hffff ?
                                16'hffff : resolve_token_iteration + 16'd1;
        incremented_confidence = confidence_q[resolve_token_index] == 2'b11 ?
                                 2'b11 : confidence_q[resolve_token_index] + 2'b01;
        decremented_confidence = confidence_q[resolve_token_index] == 2'b00 ?
                                 2'b00 : confidence_q[resolve_token_index] - 2'b01;
        incremented_age = age_q[resolve_token_index] == 2'b11 ?
                          2'b11 : age_q[resolve_token_index] + 2'b01;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_q <= 32'd0;
            busy_q <= 32'd0;
        end else begin
            if (flush)
                busy_q <= 32'd0;

            if (query_accept && token_valid) begin
                busy_q[token_index] <= 1'b1;
                busy_tag_q[token_index] <= token_tag;
                busy_iteration_q[token_index] <= token_iteration;
                busy_epoch_q[token_index] <= token_epoch;
            end

            if (resolve_owner_match) begin
                busy_q[resolve_token_index] <= 1'b0;
                if (resolve_token_epoch == current_epoch) begin
                    if (!resolve_table_hit) begin
                        valid_q[resolve_token_index] <= 1'b1;
                        tag_q[resolve_token_index] <= resolve_token_tag;
                        direction_q[resolve_token_index] <= 1'b1;
                        trip_count_q[resolve_token_index] <=
                            resolve_taken ? 16'd0 : resolve_token_iteration;
                        current_iteration_q[resolve_token_index] <=
                            resolve_taken ? incremented_iteration : 16'd0;
                        confidence_q[resolve_token_index] <= 2'b00;
                        age_q[resolve_token_index] <= 2'b00;
                    end else if (resolve_taken) begin
                        current_iteration_q[resolve_token_index] <=
                            incremented_iteration;
                        age_q[resolve_token_index] <= incremented_age;
                    end else begin
                        current_iteration_q[resolve_token_index] <= 16'd0;
                        if (trip_count_q[resolve_token_index] ==
                            resolve_token_iteration) begin
                            confidence_q[resolve_token_index] <=
                                incremented_confidence;
                            age_q[resolve_token_index] <= incremented_age;
                        end else begin
                            trip_count_q[resolve_token_index] <=
                                resolve_token_iteration;
                            confidence_q[resolve_token_index] <=
                                decremented_confidence;
                            age_q[resolve_token_index] <= 2'b00;
                        end
                    end
                end
            end
        end
    end
endmodule
