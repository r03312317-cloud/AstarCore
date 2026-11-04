// -----------------------------------------------------------------------------
// core0_uart_mmio —— UART 的 MMIO 封装（V1 只做发送）
//
// 地址：BASE_ADDR = 0x4000_0000，占用 SPAN_BYTES = 4 KiB
//   +0x0  TX      write : 写一字节即发送；read 恒为 0
//   +0x4  STATUS  read  : bit0 = tx_busy
//   +0x8  RX      read  : V1 恒为 0（接收路径未实现）
//   +0xC  CTRL    read  : 固定 0x0000_0001（存在性探测位）
//
// 寄存器按字索引 req_addr[3:2] 译码，因此 sb/sh/sw 访问同一字都会命中同一寄存器。
//
// 写数据取自 wstrb 指明的字节通道，而不是固定取 [7:0]
//   CPU 的存储数据与写掩码按字节通道对齐（对照 dc_realtime_core_tcm_bram 的
//   逐字节写实现）。因此 `sb` 到 0x4000_0000 时 wstrb=0001、数据在 wdata[7:0]；
//   `sw` 时 wstrb=1111、取 wdata[7:0]。按最低有效通道选择可同时正确支持两者。
//
// 为什么不实现 RX
//   前序在同一块板的同一对引脚上做过 RX 验证：发送（TX）完全正常、RX 收不到任何
//   字节，且已排除波特率、引脚映射、时序、DTR/RTS、内存 IP 保真度与引导器逻辑
//   （见 handoff_codex/DEBUG_HANDOFF_REPORT.md）。本方案 V1 以"串口输出 CoreMark
//   结果"为验收，RX 不是必需项，故不引入已知有缺陷的路径；接口位置已预留。
//
// 背压：发送忙时卡住总线，而不是丢字节
//   若在 tx_busy 时接受写并忽略数据，串口输出会静默丢字符、CoreMark 结果不可信。
//   因此当本笔请求是 TX 写且发送器忙时，本模块不拉高 req_ready，让总线等到
//   发送器空闲。代价是一次写最多阻塞约 10 个波特周期（100 MHz/115200 约 87 µs）；
//   CoreMark 只在结束时打印，完全可接受，且保证每个写入字节都被真正发出。
//
// 总线语义与 core0_cycle_timer 一致：每笔被接受的请求恰好一次响应；
// 读数据在请求被接受那一拍锁存，响应保持期间稳定（STATUS 的 tx_busy 变化不会
// 造成响应数据抖动）。
// -----------------------------------------------------------------------------

module core0_uart_mmio #(
    parameter logic [31:0] BASE_ADDR  = 32'h4000_0000,
    parameter logic [31:0] SPAN_BYTES = 32'h0000_1000,
    parameter int unsigned CLK_FREQ   = 100_000_000,
    parameter int unsigned BAUD_RATE  = 115200
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
    output logic        rsp_error,

    output logic        uart_tx
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam logic [1:0] REG_TX     = 2'd0;
    localparam logic [1:0] REG_STATUS = 2'd1;
    localparam logic [1:0] REG_RX     = 2'd2;
    localparam logic [1:0] REG_CTRL   = 2'd3;

    logic [31:0] rsp_data_q;
    logic [7:0]  tx_byte;
    logic        pending_q;
    logic        rsp_valid_q;
    logic        rsp_error_q;
    logic        window_hit;
    logic        select_tx;
    logic        req_accept;
    logic        tx_busy;
    logic        tx_start;
    logic        tx_write_waits;
    logic        access_illegal;
    logic [31:0] read_data_mux;

    assign window_hit = req_addr >= BASE_ADDR &&
                        req_addr <  BASE_ADDR + SPAN_BYTES;
    assign select_tx  = window_hit && req_addr[3:2] == REG_TX;

    // 发送忙时对 TX 的写不握手，让总线等待（保证不丢字符）。
    assign tx_write_waits = select_tx && req_write && tx_busy;
    assign req_ready  = !rst && !pending_q && !rsp_valid_q && !tx_write_waits;
    assign req_accept = req_valid && req_ready;
    assign rsp_valid  = !rst && rsp_valid_q;
    assign rsp_rdata  = rsp_valid && !rsp_error_q ? rsp_data_q : 32'd0;
    assign rsp_error  = rsp_valid && rsp_error_q;
    assign tx_start   = req_accept && !access_illegal && select_tx;

    // 写只允许 TX；窗口外一律错误。
    assign access_illegal = !window_hit ||
                            (req_write && req_addr[3:2] != REG_TX);

    always_comb begin
        case (req_wstrb)
            4'b0001: tx_byte = req_wdata[7:0];
            4'b0010: tx_byte = req_wdata[15:8];
            4'b0100: tx_byte = req_wdata[23:16];
            4'b1000: tx_byte = req_wdata[31:24];
            default: tx_byte = req_wdata[7:0];
        endcase
    end

    always_comb begin
        case (req_addr[3:2])
            REG_STATUS: read_data_mux = {31'b0, tx_busy};
            REG_RX:     read_data_mux = 32'd0;
            REG_CTRL:   read_data_mux = 32'h0000_0001;
            default:    read_data_mux = 32'd0;
        endcase
    end

    core0_uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) tx_unit (
        .clk      (clk),
        .rst      (rst),
        .tx_data  (tx_byte),
        .tx_start (tx_start),
        .tx_busy  (tx_busy),
        .tx       (uart_tx)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            pending_q   <= 1'b0;
            rsp_valid_q <= 1'b0;
            rsp_error_q <= 1'b0;
            rsp_data_q  <= 32'd0;
        end else begin
            if (rsp_valid_q && rsp_ready) begin
                rsp_valid_q <= 1'b0;
                rsp_error_q <= 1'b0;
            end

            if (pending_q) begin
                pending_q   <= 1'b0;
                rsp_valid_q <= 1'b1;
            end

            if (req_accept) begin
                pending_q   <= 1'b1;
                rsp_data_q  <= read_data_mux;
                rsp_error_q <= access_illegal;
            end
        end
    end
endmodule
