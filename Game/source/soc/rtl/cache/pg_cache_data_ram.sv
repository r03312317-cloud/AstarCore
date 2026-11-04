`timescale 1ns/1ps
// Portable cache data storage. Logical width 128; four fixed 32-bit banks.
// One synchronous read port, one byte-enabled write address. No array reset.
// rd_en produces data after THIS rising edge (no extra address/output stage).
// The cache FSM never asserts read and write together. READ_FIRST semantics
// below also define same-clock collisions for independent leaf testing.
// ram_style is an inference hint, not evidence of successful FPGA mapping.
module pg_cache_data_ram #(
    parameter integer ADDR_WIDTH = 9
)(
    input  logic                  clk,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0]  rd_addr,
    output wire  [127:0]          rd_data,
    input  logic [ADDR_WIDTH-1:0]  wr_addr,
    input  logic [127:0]           wr_data,
    input  logic [15:0]            wr_byte_en
);
    localparam integer DEPTH = 1 << ADDR_WIDTH;
    for (genvar bank = 0; bank < 4; bank = bank + 1) begin : g_bank
        (* ram_style = "block" *) logic [31:0] memory [0:DEPTH-1];
        logic [31:0] read_q;
        always_ff @(posedge clk) begin
            for (integer lane = 0; lane < 4; lane = lane + 1) begin
                if (wr_byte_en[bank*4+lane])
                    memory[wr_addr][lane*8 +: 8] <= wr_data[bank*32+lane*8 +: 8];
            end
            if (rd_en) read_q <= memory[rd_addr];
        end
        assign rd_data[bank*32 +: 32] = read_q;
    end
endmodule
