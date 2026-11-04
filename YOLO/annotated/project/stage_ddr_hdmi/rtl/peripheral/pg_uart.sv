// 8N1 UART with pin-level TX/RX, one-byte RX holding register, error pulses.
// CLKS_PER_BIT is selected from the actual input clock by the board integration.
// 架构导读：pg_uart。
// 可寄存器访问的 UART 数据、状态和波特率控制路径。
module pg_uart #(
    // 静态配置：parameter int CLKS_PER_BIT = 16。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int CLKS_PER_BIT = 16
) (
    // 接口声明：input logic clk, rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic clk, rst,
    // 接口声明：input logic tx_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic tx_valid,
    // 接口声明：output logic tx_ready。
    output logic tx_ready,
    input logic [7:0] tx_data,
    output logic tx_pin,
    input logic rx_pin,
    output logic rx_valid,
    input logic rx_ready,
    output logic [7:0] rx_data,
    output logic rx_frame_error, rx_overrun
);
    // 静态配置：localparam int COUNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
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
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            tx_busy <= 0; tx_shift <= '1; tx_bits <= 0; tx_count <= 0;
        end else if (tx_busy) begin
            if (tx_count == 0) begin
                tx_shift <= {1'b1,tx_shift[9:1]};
                tx_count <= COUNT_W'(CLKS_PER_BIT-1);
                tx_bits <= tx_bits - 1'b1;
                if (tx_bits == 1) tx_busy <= 0;
            end else tx_count <= tx_count - 1'b1;
        // 握手/背压判断：tx_valid && tx_ready。
        // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
        end else if (tx_valid && tx_ready) begin
            tx_shift <= {1'b1,tx_data,1'b0};
            tx_bits <= 10; tx_count <= COUNT_W'(CLKS_PER_BIT-1); tx_busy <= 1;
        end
    end
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin rx_meta <= 1; rx_sync <= 1; end
        else begin rx_meta <= rx_pin; rx_sync <= rx_meta; end
    end
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            rx_state <= IDLE; rx_count <= 0; rx_bit <= 0; rx_shift <= 0;
            rx_valid <= 0; rx_data <= 0; rx_frame_error <= 0; rx_overrun <= 0;
        end else begin
            rx_frame_error <= 0; rx_overrun <= 0;
            // 握手/背压判断：rx_valid && rx_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if (rx_valid && rx_ready) rx_valid <= 0;
            // 按 rx_state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case (rx_state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if (!rx_sync) begin
                    rx_count <= COUNT_W'(CLKS_PER_BIT/2-1); rx_state <= START;
                end
                // 状态/选择分支 START：本分支规定该编码下的寄存器更新和下一步动作。
                START: if (rx_count != 0) rx_count <= rx_count - 1'b1;
                    else if (rx_sync) rx_state <= IDLE;
                    else begin rx_bit <= 0; rx_count <= COUNT_W'(CLKS_PER_BIT-1); rx_state <= DATA; end
                // 状态/选择分支 DATA：本分支规定该编码下的寄存器更新和下一步动作。
                DATA: if (rx_count != 0) rx_count <= rx_count - 1'b1;
                    else begin
                        rx_shift[rx_bit] <= rx_sync; rx_count <= COUNT_W'(CLKS_PER_BIT-1);
                        if (rx_bit == 7) rx_state <= STOP;
                        else rx_bit <= rx_bit + 1'b1;
                    end
                // 状态/选择分支 STOP：本分支规定该编码下的寄存器更新和下一步动作。
                STOP: if (rx_count != 0) rx_count <= rx_count - 1'b1;
                    else begin
                        if (!rx_sync) begin rx_frame_error <= 1; rx_state <= WAIT_HIGH; end
                        else begin
                            // 握手/背压判断：rx_valid && !rx_ready。
                            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
                            if (rx_valid && !rx_ready) rx_overrun <= 1;
                            else begin rx_valid <= 1; rx_data <= rx_shift; end
                            rx_state <= IDLE;
                        end
                    end
                // 状态/选择分支 WAIT_HIGH：本分支规定该编码下的寄存器更新和下一步动作。
                WAIT_HIGH: if (rx_sync) rx_state <= IDLE;
                default: rx_state <= IDLE;
            endcase
        end
    end
endmodule
