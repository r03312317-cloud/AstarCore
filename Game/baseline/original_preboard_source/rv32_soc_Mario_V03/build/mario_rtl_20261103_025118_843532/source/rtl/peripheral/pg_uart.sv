// 8N1 UART with pin-level TX/RX, one-byte RX holding register, error pulses.
// CLKS_PER_BIT is selected from the actual input clock by the board integration.
module pg_uart #(
    parameter int CLKS_PER_BIT = 16
) (
    input logic clk, rst,
    input logic tx_valid,
    output logic tx_ready,
    input logic [7:0] tx_data,
    output logic tx_pin,
    input logic rx_pin,
    output logic rx_valid,
    input logic rx_ready,
    output logic [7:0] rx_data,
    output logic rx_frame_error, rx_overrun
);
    localparam int COUNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    logic tx_busy;
    logic [9:0] tx_shift;
    logic [3:0] tx_bits;
    logic [COUNT_W-1:0] tx_count, rx_count;
    logic rx_meta, rx_sync;
    logic [2:0] rx_bit;
    logic [7:0] rx_shift;
    typedef enum logic [2:0] {IDLE,START,DATA,STOP,WAIT_HIGH} rx_state_t;
    rx_state_t rx_state;
    initial if (CLKS_PER_BIT < 4) $fatal(1,"PG_UART_DIVISOR_RED");
    assign tx_ready = !rst && !tx_busy;
    assign tx_pin = tx_busy ? tx_shift[0] : 1'b1;
    always_ff @(posedge clk) begin
        if (rst) begin
            tx_busy <= 0; tx_shift <= '1; tx_bits <= 0; tx_count <= 0;
        end else if (tx_busy) begin
            if (tx_count == 0) begin
                tx_shift <= {1'b1,tx_shift[9:1]};
                tx_count <= COUNT_W'(CLKS_PER_BIT-1);
                tx_bits <= tx_bits - 1'b1;
                if (tx_bits == 1) tx_busy <= 0;
            end else tx_count <= tx_count - 1'b1;
        end else if (tx_valid && tx_ready) begin
            tx_shift <= {1'b1,tx_data,1'b0};
            tx_bits <= 10; tx_count <= COUNT_W'(CLKS_PER_BIT-1); tx_busy <= 1;
        end
    end
    always_ff @(posedge clk) begin
        if (rst) begin rx_meta <= 1; rx_sync <= 1; end
        else begin rx_meta <= rx_pin; rx_sync <= rx_meta; end
    end
    always_ff @(posedge clk) begin
        if (rst) begin
            rx_state <= IDLE; rx_count <= 0; rx_bit <= 0; rx_shift <= 0;
            rx_valid <= 0; rx_data <= 0; rx_frame_error <= 0; rx_overrun <= 0;
        end else begin
            rx_frame_error <= 0; rx_overrun <= 0;
            if (rx_valid && rx_ready) rx_valid <= 0;
            case (rx_state)
                IDLE: if (!rx_sync) begin
                    rx_count <= COUNT_W'(CLKS_PER_BIT/2-1); rx_state <= START;
                end
                START: if (rx_count != 0) rx_count <= rx_count - 1'b1;
                    else if (rx_sync) rx_state <= IDLE;
                    else begin rx_bit <= 0; rx_count <= COUNT_W'(CLKS_PER_BIT-1); rx_state <= DATA; end
                DATA: if (rx_count != 0) rx_count <= rx_count - 1'b1;
                    else begin
                        rx_shift[rx_bit] <= rx_sync; rx_count <= COUNT_W'(CLKS_PER_BIT-1);
                        if (rx_bit == 7) rx_state <= STOP;
                        else rx_bit <= rx_bit + 1'b1;
                    end
                STOP: if (rx_count != 0) rx_count <= rx_count - 1'b1;
                    else begin
                        if (!rx_sync) begin rx_frame_error <= 1; rx_state <= WAIT_HIGH; end
                        else begin
                            if (rx_valid && !rx_ready) rx_overrun <= 1;
                            else begin rx_valid <= 1; rx_data <= rx_shift; end
                            rx_state <= IDLE;
                        end
                    end
                WAIT_HIGH: if (rx_sync) rx_state <= IDLE;
                default: rx_state <= IDLE;
            endcase
        end
    end
endmodule
