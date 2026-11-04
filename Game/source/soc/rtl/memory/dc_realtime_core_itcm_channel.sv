module dc_realtime_core_itcm_channel #(
    parameter int unsigned ADDR_WIDTH = 14,
    parameter logic [31:0] BASE_ADDR = 32'h1000_0000,
    parameter INIT_FILE = ""   // PDS ADS 不支持 `parameter string`
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        req_valid,
    output logic        req_ready,
    input  logic [31:0] req_addr,
    output logic        rsp_valid,
    input  logic        rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic        rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [1:0] outstanding_count_q;
    logic read_stage1_valid_q;
    logic read_stage1_error_q;
    logic read_stage2_valid_q;
    logic read_stage2_error_q;
    logic [31:0] bram_rdata;
    logic [31:0] response_data_q [0:1];
    logic response_error_q [0:1];
    logic response_read_ptr_q;
    logic response_write_ptr_q;
    logic [1:0] response_count_q;
    logic req_accept;
    logic req_address_valid;
    logic rsp_accept;
    logic response_fifo_push;
    logic response_fifo_pop;

    assign rsp_valid = !rst &&
                       (response_count_q != 0 || read_stage2_valid_q);
    assign rsp_rdata = response_count_q != 0 ?
                       response_data_q[response_read_ptr_q] :
                       read_stage2_error_q ? 32'd0 : bram_rdata;
    assign rsp_error = response_count_q != 0 ?
                       response_error_q[response_read_ptr_q] :
                       read_stage2_error_q;
    assign rsp_accept = rsp_valid && rsp_ready;

    assign req_ready = !rst &&
                       (outstanding_count_q < 2 || rsp_accept);
    assign req_accept = req_valid && req_ready;
    assign req_address_valid = req_addr >= BASE_ADDR &&
                               req_addr < BASE_ADDR +
                                          (32'd4 << ADDR_WIDTH) &&
                               req_addr[1:0] == 2'b00;

    assign response_fifo_pop = response_count_q != 0 && rsp_ready;
    assign response_fifo_push = read_stage2_valid_q &&
                                !(response_count_q == 0 && rsp_ready);

    dc_realtime_core_tcm_bram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE(INIT_FILE)
    ) tcm_memory (
        .clk,
        .enable(req_accept && req_address_valid),
        .address(req_addr[ADDR_WIDTH+1:2]),
        .write(1'b0),
        .wdata(32'd0),
        .wstrb(4'd0),
        .rdata(bram_rdata)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            outstanding_count_q <= 2'd0;
            read_stage1_valid_q <= 1'b0;
            read_stage1_error_q <= 1'b0;
            read_stage2_valid_q <= 1'b0;
            read_stage2_error_q <= 1'b0;
            response_read_ptr_q <= 1'b0;
            response_write_ptr_q <= 1'b0;
            response_count_q <= 2'd0;
            for (int unsigned index = 0; index < 2; ++index) begin
                response_data_q[index] <= 32'd0;
                response_error_q[index] <= 1'b0;
            end
        end else begin
            case ({req_accept, rsp_accept})
                2'b10: outstanding_count_q <= outstanding_count_q + 2'd1;
                2'b01: outstanding_count_q <= outstanding_count_q - 2'd1;
                default: begin end
            endcase

            read_stage1_valid_q <= req_accept;
            read_stage1_error_q <= req_accept && !req_address_valid;
            read_stage2_valid_q <= read_stage1_valid_q;
            read_stage2_error_q <= read_stage1_error_q;

            case ({response_fifo_push, response_fifo_pop})
                2'b10: response_count_q <= response_count_q + 2'd1;
                2'b01: response_count_q <= response_count_q - 2'd1;
                default: begin end
            endcase
            if (response_fifo_push) begin
                response_data_q[response_write_ptr_q] <=
                    read_stage2_error_q ? 32'd0 : bram_rdata;
                response_error_q[response_write_ptr_q] <=
                    read_stage2_error_q;
                response_write_ptr_q <= response_write_ptr_q + 1'b1;
            end
            if (response_fifo_pop)
                response_read_ptr_q <= response_read_ptr_q + 1'b1;
        end
    end

`ifdef DC_RT_VERIFICATION
    logic response_held_q;
    logic [32:0] response_held_tuple_q;
    always_ff @(posedge clk) begin
        if (rst) begin
            response_held_q <= 1'b0;
            response_held_tuple_q <= 33'd0;
        end else begin
            if (outstanding_count_q > 2 || response_count_q > 2)
                $error("CORE0_ITCM_PIPELINE_CREDIT_RED outstanding=%0d buffered=%0d",
                       outstanding_count_q, response_count_q);
            if (response_held_q &&
                {rsp_error, rsp_rdata} !== response_held_tuple_q)
                $error("CORE0_ITCM_PIPELINE_HELD_RESPONSE_RED");
            response_held_q <= rsp_valid && !rsp_ready;
            if (rsp_valid)
                response_held_tuple_q <= {rsp_error, rsp_rdata};
        end
    end
`endif
endmodule
