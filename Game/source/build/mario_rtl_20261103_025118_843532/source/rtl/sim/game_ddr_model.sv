// ---------------------------------------------------------------------------
// game_ddr_model -- behavioural DDR3 user-port model for Verilator simulation.
//
// Replaces soc_ddr800 (encrypted vendor PHY + controller) on the 256-bit
// AXI side.  Only the subset of the vendor port list used by game_board_top is
// implemented.  Timing is representative, not calibrated:
//   * read: AR accepted immediately, first R beat after RD_LATENCY clocks,
//     one beat per clock afterwards, RLAST on the last beat
//   * write: AW accepted, W beats consumed back to back, B after WR_LATENCY
//   * one transaction at a time (the HMIC adapter never issues two at once)
//
// Addresses are 30-bit byte offsets from the DDR base (the adapter rebases
// them), so the 32-byte line index is araddr[LINE_BITS+4:5].
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module game_ddr_model #(
    parameter integer MEM_BYTES = 128 * 1024 * 1024,
    parameter integer RD_LATENCY = 12,
    parameter integer WR_LATENCY = 6,
    parameter integer INIT_CYCLES = 200
) (
    input  logic ref_clk,
    input  logic resetn,
    output logic pll_lock,
    output logic phy_pll_lock,
    output logic ddr_init_done,
    output logic ddr_cal_fail,

    input  logic [7:0]   axi_awid,
    input  logic [29:0]  axi_awaddr,
    input  logic [7:0]   axi_awlen,
    input  logic [2:0]   axi_awsize,
    input  logic [1:0]   axi_awburst,
    input  logic         axi_awvalid,
    output logic         axi_awready,
    input  logic [255:0] axi_wdata,
    input  logic [31:0]  axi_wstrb,
    input  logic         axi_wlast,
    input  logic         axi_wvalid,
    output logic         axi_wready,
    output logic [7:0]   axi_bid,
    output logic [1:0]   axi_bresp,
    output logic         axi_bvalid,
    input  logic         axi_bready,
    input  logic [7:0]   axi_arid,
    input  logic [29:0]  axi_araddr,
    input  logic [7:0]   axi_arlen,
    input  logic [2:0]   axi_arsize,
    input  logic [1:0]   axi_arburst,
    input  logic         axi_arvalid,
    output logic         axi_arready,
    output logic [7:0]   axi_rid,
    output logic [255:0] axi_rdata,
    output logic [1:0]   axi_rresp,
    output logic         axi_rlast,
    output logic         axi_rvalid,
    input  logic         axi_rready
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer LINES = MEM_BYTES / 32;
    localparam integer LINE_BITS = $clog2(LINES);
    localparam integer LINE_MSB = LINE_BITS + 4;

    (* ram_style = "block" *) logic [255:0] mem[0:LINES-1];

    typedef enum logic [2:0] {M_IDLE, M_WDATA, M_BRESP, M_RDATA} mstate_e;
    mstate_e state_q;
    logic [7:0]  awid_q, bid_q;
    logic [7:0]  arlen_q, rid_q;
    logic [7:0]  beat_q;
    logic [7:0]  delay_q;
    logic [31:0] init_cnt_q;
    logic [LINE_BITS-1:0] wr_line_q, rd_line_q;
    logic [255:0] rdata_q;

    assign pll_lock = 1'b1;
    assign phy_pll_lock = 1'b1;
    assign ddr_cal_fail = 1'b0;
    assign ddr_init_done = (init_cnt_q >= 32'(INIT_CYCLES));

    assign axi_awready = (state_q == M_IDLE) && axi_awvalid;
    assign axi_arready = (state_q == M_IDLE) && !axi_awvalid && axi_arvalid;
    assign axi_wready = (state_q == M_WDATA);
    assign axi_bvalid = (state_q == M_BRESP) && (delay_q == 8'd0);
    assign axi_bid = bid_q;
    assign axi_bresp = 2'b00;

    assign axi_rvalid = (state_q == M_RDATA) && (delay_q == 8'd0);
    assign axi_rid = rid_q;
    assign axi_rresp = 2'b00;
    assign axi_rdata = rdata_q;
    assign axi_rlast = (beat_q == arlen_q);

    integer idx;
    integer i;
    initial begin
        for (idx = 0; idx < LINES; idx = idx + 1) mem[idx] = '0;
        state_q = M_IDLE;
        awid_q = '0; bid_q = '0; arlen_q = '0; rid_q = '0;
        beat_q = '0; delay_q = '0; init_cnt_q = '0;
        wr_line_q = '0; rd_line_q = '0; rdata_q = '0;
    end

    always_ff @(posedge ref_clk) begin
        if (!resetn) begin
            state_q <= M_IDLE;
            init_cnt_q <= '0;
            beat_q <= '0;
            delay_q <= '0;
            rdata_q <= '0;
        end else begin
            if (init_cnt_q < 32'(INIT_CYCLES)) init_cnt_q <= init_cnt_q + 32'd1;
            case (state_q)
                M_IDLE: begin
                    if (axi_awvalid && axi_awready) begin
                        awid_q <= axi_awid;
                        wr_line_q <= axi_awaddr[LINE_MSB:5];
                        beat_q <= 8'd0;
                        state_q <= M_WDATA;
                    end else if (axi_arvalid && axi_arready) begin
                        rid_q <= axi_arid;
                        arlen_q <= axi_arlen;
                        rd_line_q <= axi_araddr[LINE_MSB:5];
                        beat_q <= 8'd0;
                        delay_q <= 8'(RD_LATENCY);
                        state_q <= M_RDATA;
                    end
                end
                M_WDATA: begin
                    if (axi_wvalid && axi_wready) begin
                        for (i = 0; i < 32; i = i + 1)
                            if (axi_wstrb[i])
                                mem[wr_line_q + LINE_BITS'(beat_q)][i*8 +: 8]
                                    <= axi_wdata[i*8 +: 8];
                        beat_q <= beat_q + 8'd1;
                        if (axi_wlast) begin
                            bid_q <= awid_q;
                            delay_q <= 8'(WR_LATENCY);
                            state_q <= M_BRESP;
                        end
                    end
                end
                M_BRESP: begin
                    if (delay_q != 8'd0) delay_q <= delay_q - 8'd1;
                    else if (axi_bready) state_q <= M_IDLE;
                end
                M_RDATA: begin
                    if (delay_q != 8'd0) begin
                        delay_q <= delay_q - 8'd1;
                        if (delay_q == 8'd1) rdata_q <= mem[rd_line_q + LINE_BITS'(0)];
                    end else if (axi_rready) begin
                        if (beat_q == arlen_q) state_q <= M_IDLE;
                        else begin
                            beat_q <= beat_q + 8'd1;
                            rdata_q <= mem[rd_line_q + LINE_BITS'(beat_q + 8'd1)];
                        end
                    end
                end
                default: state_q <= M_IDLE;
            endcase
        end
    end

    initial begin
        if (MEM_BYTES % 32 != 0) $fatal(1, "GAME_DDR_MODEL_GEOMETRY");
        if (RD_LATENCY < 1 || WR_LATENCY < 1) $fatal(1, "GAME_DDR_MODEL_LATENCY");
    end
endmodule
