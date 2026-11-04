module dc_realtime_core_tcm_bram #(
    parameter int unsigned ADDR_WIDTH = 8,
    parameter int unsigned READ_LATENCY = 2,
    parameter INIT_FILE = ""   // PDS ADS 不支持 `parameter string`
) (
    input  logic                  clk,
    input  logic                  enable,
    input  logic [ADDR_WIDTH-1:0] address,
    input  logic                  write,
    input  logic [31:0]           wdata,
    input  logic [3:0]            wstrb,
    output logic [31:0]           rdata
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned WORDS = 1 << ADDR_WIDTH;

    (* ram_style = "block" *) logic [31:0] memory [0:WORDS-1];
    // Preserve the RAM/output-register boundary: same two-cycle behavior,
    // but allow the last register to be placed close to the consuming logic.
    (* syn_keep = 1 *) logic [31:0] memory_rdata_q;

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end

    // READ_LATENCY=1 still uses a synchronous block-memory read register.
    // It removes only the *additional* output register, never infers async RAM.
    generate
        if (READ_LATENCY == 2) begin : g_output_register
            always_ff @(posedge clk) rdata <= memory_rdata_q;
        end else begin : g_native_sync_output
            assign rdata = memory_rdata_q;
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (enable) begin
            if (write) begin
                if (wstrb[0])
                    memory[address][7:0] <= wdata[7:0];
                if (wstrb[1])
                    memory[address][15:8] <= wdata[15:8];
                if (wstrb[2])
                    memory[address][23:16] <= wdata[23:16];
                if (wstrb[3])
                    memory[address][31:24] <= wdata[31:24];
            end
            memory_rdata_q <= memory[address];
        end
    end
endmodule
