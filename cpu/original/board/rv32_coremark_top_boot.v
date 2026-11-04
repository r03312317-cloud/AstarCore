// 130 MHz board top with power-on reset and UART boot loader.
// Pin-compatible with rv32_coremark_top plus the uart_rx input (B24).
module rv32_coremark_top_boot #(
    // Experimental variant: only LOAD_BYPASS differs from the frozen baseline.
    parameter LOAD_BYPASS=1,
    parameter BIMODAL_INDEX_BITS=9,
    parameter GSHARE_INDEX_BITS=12,
    parameter HISTORY_BITS=12
)(
    input clk_p, clk_n, rst_in, uart_rx,
    output reg uart_tx, output reg [7:0] led
);
    wire reference_clk,cpu_clk,locked;
    GTP_INBUFGDS #(.IOSTANDARD("DEFAULT"),.TERM_DIFF("ON")) reference_input(
        .I(clk_p),.IB(clk_n),.O(reference_clk));
    rv32_board_pll_130 u_cpu_pll(.clkin1(reference_clk),.clkout0(cpu_clk),.lock(locked));

    // Power-on reset: hold reset for 1024 cycles after lock.
    wire async_reset=!rst_in;
    reg [9:0] por_count;
    reg por_done;
    always @(posedge cpu_clk or posedge async_reset)
        if(async_reset) begin por_count<=10'd0; por_done<=1'b0; end
        else if(!locked) begin por_count<=10'd0; por_done<=1'b0; end
        else if(!por_done) begin
            por_count<=por_count+1'b1;
            if(&por_count) por_done<=1'b1;
        end
    wire reset=!por_done;

    wire done,fault,loading;
    wire system_uart_tx;
    wire [31:0] exit_code;
    wire [63:0] clocks;
    wire [1:0] retire;
    wire du,dv; wire [7:0] dd; wire [31:0] dt;
    wire ifill,dfill,wb,berr;

    rv32_coremark_system_boot #(.UART_DIV(1128),.LOAD_BYPASS(LOAD_BYPASS),.BIMODAL_INDEX_BITS(BIMODAL_INDEX_BITS),.GSHARE_INDEX_BITS(GSHARE_INDEX_BITS),.HISTORY_BITS(HISTORY_BITS)) system(
        .clk(cpu_clk),.reset(reset),.uart_rx(uart_rx),.uart_tx(system_uart_tx),
        .done(done),.exit_code(exit_code),.fault(fault),.elapsed_clocks(clocks),
        .debug_uart_valid(du),.debug_uart_data(dd),
        .debug_timer_valid(dv),.debug_timer_value(dt),
        .debug_retire(retire),.debug_i_fill(ifill),.debug_d_fill(dfill),
        .debug_writeback(wb),.debug_bus_read_error(berr),.loading(loading));

    // Output-only registers preserve every UART bit for the same number of
    // clocks; the external waveform is delayed by exactly one CPU clock.
    // No CPU, cache, benchmark counter, or UART handshake stage is added.
    always @(posedge cpu_clk)begin
        uart_tx<=system_uart_tx;
        led<=~{2'b11,loading,fault,done,!reset,locked,1'b0};
    end
endmodule
