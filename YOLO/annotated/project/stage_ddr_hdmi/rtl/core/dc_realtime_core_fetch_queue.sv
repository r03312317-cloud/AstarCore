module dc_realtime_core_fetch_queue #(
    parameter int unsigned META_WIDTH = 1
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  invalidate,

    input  logic                  offer_valid,
    output logic                  offer_accept,
    output logic                  offer_offered,
    output logic                  offer_credit_available,
    output logic                  offer_refill_credit,
    input  logic [31:0]           offer_addr,
    input  logic [META_WIDTH-1:0] offer_meta,

    output logic                  memory_req_valid,
    input  logic                  memory_req_ready,
    output logic [31:0]           memory_req_addr,
    input  logic                  memory_rsp_valid,
    output logic                  memory_rsp_ready,
    input  logic [31:0]           memory_rsp_rdata,
    input  logic                  memory_rsp_error,

    output logic                  response_valid,
    input  logic                  response_ready,
    output logic [31:0]           response_rdata,
    output logic                  response_error,
    output logic [META_WIDTH-1:0] response_meta,
    output logic                  response_live,
    output logic                  younger_pending
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [META_WIDTH-1:0] request_meta_q [0:1];
    logic request_live_q [0:1];
    logic request_read_ptr_q;
    logic request_write_ptr_q;
    logic [1:0] request_count_q;
    logic held_offer_dead_q;

    logic [31:0] response_data_q [0:3];
    logic response_error_q [0:3];
    logic [META_WIDTH-1:0] response_meta_q [0:3];
    logic response_live_q [0:3];
    logic [1:0] response_read_ptr_q;
    logic [1:0] response_write_ptr_q;
    logic [2:0] response_count_q;

    logic [2:0] reserved_count;
    logic memory_response_accept;
    logic direct_response;
    logic response_accept;
    logic response_fifo_push;
    logic response_fifo_pop;

    assign reserved_count = {1'b0, request_count_q} + response_count_q;
    assign offer_credit_available = reserved_count < 3'd4;
    assign memory_req_valid = !rst && offer_valid &&
                              (request_count_q < 2 || memory_response_accept);
    assign memory_req_addr = offer_addr;
    assign offer_offered = memory_req_valid;
    assign offer_accept = memory_req_valid && memory_req_ready;

    assign memory_rsp_ready = !rst && request_count_q != 0 &&
                              response_count_q < 3'd4;
    assign memory_response_accept = memory_rsp_valid && memory_rsp_ready;
    assign direct_response = response_count_q == 0 &&
                             memory_response_accept;
    assign response_valid = !rst &&
                            (response_count_q != 0 || direct_response);
    assign response_rdata = response_count_q != 0 ?
                            response_data_q[response_read_ptr_q] :
                            memory_rsp_rdata;
    assign response_error = response_count_q != 0 ?
                            response_error_q[response_read_ptr_q] :
                            memory_rsp_error;
    assign response_meta = response_count_q != 0 ?
                           response_meta_q[response_read_ptr_q] :
                           request_meta_q[request_read_ptr_q];
    assign response_live = !invalidate &&
                           (response_count_q != 0 ?
                            response_live_q[response_read_ptr_q] :
                            request_live_q[request_read_ptr_q]);
    assign response_accept = response_valid && response_ready;
    assign response_fifo_pop = response_count_q != 0 && response_accept;
    assign response_fifo_push = memory_response_accept && !invalidate &&
                                !(response_count_q == 0 && response_ready);
    assign younger_pending = reserved_count > 3'd1;
    assign offer_refill_credit =
        (reserved_count + (offer_accept ? 3'd1 : 3'd0)) <
        3'd4;

    // V14: the write pointer names a FREE tail slot whenever a memory
    // response can be accepted (response_count < 4). Writing that unused
    // payload even during direct consumption/invalidation is harmless:
    // allocation, pointers and live bits below remain unchanged. This takes
    // pipeline_redirect and downstream issue/ready off the wide data/meta CE.
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int unsigned index = 0; index < 4; ++index) begin
                response_data_q[index] <= 32'd0;
                response_error_q[index] <= 1'b0;
                response_meta_q[index] <= '0;
            end
        end else if (memory_response_accept) begin
            response_data_q[response_write_ptr_q] <=
                memory_rsp_error ? 32'd0 : memory_rsp_rdata;
            response_error_q[response_write_ptr_q] <= memory_rsp_error;
            response_meta_q[response_write_ptr_q] <= request_meta_q[request_read_ptr_q];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            request_read_ptr_q <= 1'b0;
            request_write_ptr_q <= 1'b0;
            request_count_q <= 2'd0;
            held_offer_dead_q <= 1'b0;
            response_read_ptr_q <= 2'd0;
            response_write_ptr_q <= 2'd0;
            response_count_q <= 3'd0;
            for (int unsigned index = 0; index < 2; ++index) begin
                request_meta_q[index] <= '0;
                request_live_q[index] <= 1'b0;
            end
            for (int unsigned index = 0; index < 4; ++index) begin
                response_live_q[index] <= 1'b0;
            end
        end else begin
            if (!memory_req_valid || offer_accept)
                held_offer_dead_q <= 1'b0;
            if (invalidate && memory_req_valid && !offer_accept)
                held_offer_dead_q <= 1'b1;
            case ({offer_accept, memory_response_accept})
                2'b10: request_count_q <= request_count_q + 2'd1;
                2'b01: request_count_q <= request_count_q - 2'd1;
                default: begin end
            endcase
            if (offer_accept) begin
                request_meta_q[request_write_ptr_q] <= offer_meta;
                request_live_q[request_write_ptr_q] <=
                    !invalidate && !held_offer_dead_q;
                request_write_ptr_q <= request_write_ptr_q + 1'b1;
            end
            if (memory_response_accept)
                request_read_ptr_q <= request_read_ptr_q + 1'b1;

            case ({response_fifo_push, response_fifo_pop})
                2'b10: response_count_q <= response_count_q + 3'd1;
                2'b01: response_count_q <= response_count_q - 3'd1;
                default: begin end
            endcase
            if (response_fifo_push) begin
                response_live_q[response_write_ptr_q] <=
                    request_live_q[request_read_ptr_q];
                response_write_ptr_q <= response_write_ptr_q + 2'd1;
            end
            if (response_fifo_pop)
                response_read_ptr_q <= response_read_ptr_q + 2'd1;
            if (invalidate) begin
                for (int unsigned index = 0; index < 2; ++index)
                    request_live_q[index] <= 1'b0;
                for (int unsigned index = 0; index < 4; ++index)
                    response_live_q[index] <= 1'b0;
                response_read_ptr_q <= response_write_ptr_q;
                response_count_q <= 3'd0;
            end
        end
    end

`ifdef DC_RT_VERIFICATION
    logic response_held_q;
    logic [META_WIDTH+32:0] response_held_tuple_q;
    always_ff @(posedge clk) begin
        if (rst) begin
            response_held_q <= 1'b0;
            response_held_tuple_q <= '0;
        end else begin
            if (memory_rsp_valid && request_count_q == 0)
                $error("CORE0_FETCH_FIFO_RESPONSE_WITHOUT_OWNER_RED");
            if (request_count_q > 2 || response_count_q > 4 ||
                reserved_count > 4)
                $error("CORE0_FETCH_FIFO_CREDIT_RED request=%0d response=%0d",
                       request_count_q, response_count_q);
            if (response_held_q && !invalidate &&
                {response_meta, response_error, response_rdata} !==
                response_held_tuple_q)
                $error("CORE0_FETCH_FIFO_HELD_TUPLE_RED");
            response_held_q <= response_valid && !response_ready;
            if (response_valid)
                response_held_tuple_q <=
                    {response_meta, response_error, response_rdata};
        end
    end
`endif
endmodule
