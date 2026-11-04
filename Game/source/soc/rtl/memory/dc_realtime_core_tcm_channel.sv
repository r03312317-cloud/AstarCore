module dc_realtime_core_tcm_channel #(
    parameter int unsigned ADDR_WIDTH = 14,
    parameter logic [31:0] BASE_ADDR = 32'd0,
    parameter INIT_FILE = "",  // PDS ADS 不支持 `parameter string`
    parameter logic READ_ONLY = 1'b0,
    parameter int unsigned READ_LATENCY = 2,
    parameter bit EARLY_STORE_ACK = 1'b0
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        req_valid,
    output logic        req_ready,
    input  logic [31:0] req_addr,
    input  logic        req_write,
    input  logic [31:0] req_wdata,
    input  logic [3:0]  req_wstrb,
    output logic        rsp_valid,
    input  logic        rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic        rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    logic pending_q;
    logic fast_store_q;
    logic rsp_valid_q;
    logic rsp_error_q;
    logic [31:0] bram_rdata;
    logic req_accept;
    logic bram_enable;
    logic bram_write;
    logic req_address_valid;

    assign req_ready = !rst && !pending_q && (!rsp_valid_q || rsp_ready);
    assign req_accept = req_valid && req_ready;
    assign req_address_valid = req_addr >= BASE_ADDR &&
                               req_addr < BASE_ADDR + (32'd4 << ADDR_WIDTH);
    assign bram_enable = req_accept && req_address_valid &&
                         (!READ_ONLY || !req_write);
    assign bram_write = req_accept && req_address_valid &&
                        !READ_ONLY && req_write;
    assign rsp_valid = !rst && rsp_valid_q;
    assign rsp_rdata = !rsp_error_q && !fast_store_q ? bram_rdata : 32'd0;
    assign rsp_error = rsp_valid && rsp_error_q;

    dc_realtime_core_tcm_bram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .READ_LATENCY(READ_LATENCY),
        .INIT_FILE(INIT_FILE)
    ) tcm_memory (
        .clk,
        .enable(bram_enable),
        .address(req_addr[ADDR_WIDTH+1:2]),
        .write(bram_write),
        .wdata(req_wdata),
        .wstrb(req_wstrb),
        .rdata(bram_rdata)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            pending_q <= 1'b0;
            fast_store_q <= 1'b0;
            rsp_valid_q <= 1'b0;
            rsp_error_q <= 1'b0;
        end else begin
            if (rsp_valid_q && rsp_ready) begin
                fast_store_q <= 1'b0;
                rsp_valid_q <= 1'b0;
                rsp_error_q <= 1'b0;
            end
            if (pending_q) begin
                pending_q <= 1'b0;
                rsp_valid_q <= 1'b1;
            end
            if (req_accept) begin
                // The writable local BRAM commits at this edge, before ack consumption.
                // Reads and rejected accesses retain the original two-edge response.
                if ((EARLY_STORE_ACK && bram_write) || READ_LATENCY == 1) begin
                    pending_q <= 1'b0;
                    rsp_valid_q <= 1'b1;
                    fast_store_q <= bram_write;
                end else begin
                    pending_q <= 1'b1;
                    fast_store_q <= 1'b0;
                end
                rsp_error_q <= !req_address_valid || (READ_ONLY && req_write);
            end
        end
    end
endmodule
