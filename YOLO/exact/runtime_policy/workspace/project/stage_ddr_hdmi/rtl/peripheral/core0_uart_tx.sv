// -----------------------------------------------------------------------------
// core0_uart_tx —— 8N1 串口发送器
//
// 帧格式：1 起始位(0) + 8 数据位(LSB 先) + 1 停止位(1)，无校验。
// 波特率由 CLK_FREQ / BAUD_RATE 整数分频得到，除数四舍五入。
//
// 握手（与 core0_uart_mmio 配合）
//   tx_start 为单周期脉冲时启动一次发送；busy 期间忽略新的 tx_start，
//   因此上游必须先确认 !tx_busy 再触发（MMIO 层用背压实现这一点）。
//
// 波形时序
//   tx_start 当拍：装载 {stop=1, data[7:0], start=0}，tx 立即拉低（起始位），
//                  起始位占满一个波特周期。
//   之后每个波特周期移出一位，共 10 个波特周期发送完毕，tx 回到空闲高电平。
// -----------------------------------------------------------------------------

module core0_uart_tx #(
    parameter int unsigned CLK_FREQ  = 100_000_000,
    parameter int unsigned BAUD_RATE = 115200
) (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_busy,
    output logic       tx
);
    timeunit 1ns;
    timeprecision 1ps;

    // 四舍五入的波特分频：CLK_FREQ=100MHz -> 868，170MHz -> 1476，200MHz -> 1736。
    localparam int unsigned BAUD_DIV = (CLK_FREQ + (BAUD_RATE / 2)) / BAUD_RATE;

    localparam logic IDLE = 1'b0;
    localparam logic SEND = 1'b1;

    logic        state_q;
    logic [15:0] baud_count_q;
    logic [3:0]  bit_index_q;
    logic [9:0]  shift_q;

    wire baud_tick = (baud_count_q == (BAUD_DIV - 1));

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q      <= IDLE;
            baud_count_q <= 16'd0;
            bit_index_q  <= 4'd0;
            shift_q      <= 10'h3ff;
            tx_busy      <= 1'b0;
            tx           <= 1'b1;
        end else begin
            case (state_q)
                IDLE: begin
                    tx_busy <= 1'b0;
                    tx      <= 1'b1;
                    if (tx_start) begin
                        // {停止位, 数据位, 起始位}，最低位先发送。
                        // 注意：这里不能同时把 tx 拉低——起始位由 SEND 的第一个
                        // 波特刻度输出 shift_q[0] 产生；若此处也拉低，起始位会
                        // 占满两个位周期，整帧错位（串口抓到的是右移一位的数据）。
                        shift_q      <= {1'b1, tx_data, 1'b0};
                        baud_count_q <= 16'd0;
                        bit_index_q  <= 4'd0;
                        tx_busy      <= 1'b1;
                        state_q      <= SEND;
                    end
                end

                SEND: begin
                    if (baud_tick) begin
                        baud_count_q <= 16'd0;
                        tx           <= shift_q[0];
                        shift_q      <= {1'b1, shift_q[9:1]};
                        if (bit_index_q == 4'd9) begin
                            state_q <= IDLE;
                        end else begin
                            bit_index_q <= bit_index_q + 4'd1;
                        end
                    end else begin
                        baud_count_q <= baud_count_q + 16'd1;
                    end
                end

                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
