// -----------------------------------------------------------------------------
// core0_cycle_timer —— CoreMark 周期计数器 MMIO
//
// 地址：BASE_ADDR = 0x3000_0000，占用 SPAN_BYTES = 4 KiB（只用到 +0x0）
// 语义：32 位自由运行计数器，每个 CPU 时钟 +1，只读。
//
// 为什么只需要自由运行
//   CoreMark 的 port 层（sw/coremark/port/core_portme.c）只做
//   "start_time() 读一次 / stop_time() 读一次 / get_time() 求差"。
//   计数器单调递增即可，不需要 start/stop 控制位，也不需要比较器或中断。
//   secs 换算由软件用实际主频完成（time_in_secs）。
//
// 总线语义（对照 dc_realtime_core_npu_router.sv）
//   router 对每一笔被接受的请求只允许一次响应，并在响应握手前保持 owner。
//   本模块因此遵守：
//     * req_ready 仅在没有 pending 且没有未消费响应时拉高；
//     * 每接受一笔请求恰好产生一次 rsp_valid，并保持到 rsp_ready；
//     * 读数据在请求被接受的那一拍采样，响应保持期间稳定。
//   响应延迟与 dc_realtime_core_tcm_channel 一致（接受后下一拍给出）。
//
// 错误
//   * 地址落在窗口外 -> rsp_error；
//   * 对该窗口的写操作 -> rsp_error（只读外设，写视为非法）。
//   给出明确错误而不是挂死总线，便于区分"外设未命中"与"CPU 卡住"。
// -----------------------------------------------------------------------------

module core0_cycle_timer #(
    parameter logic [31:0] BASE_ADDR  = 32'h3000_0000,
    parameter logic [31:0] SPAN_BYTES = 32'h0000_1000
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

    logic [31:0] counter_q;
    logic [31:0] rsp_data_q;
    logic        pending_q;
    logic        rsp_valid_q;
    logic        rsp_error_q;
    logic        window_hit;
    logic        req_accept;

    assign window_hit = req_addr >= BASE_ADDR &&
                        req_addr <  BASE_ADDR + SPAN_BYTES;
    assign req_ready  = !rst && !pending_q && !rsp_valid_q;
    assign req_accept = req_valid && req_ready;
    assign rsp_valid  = !rst && rsp_valid_q;
    assign rsp_rdata  = rsp_valid && !rsp_error_q ? rsp_data_q : 32'd0;
    assign rsp_error  = rsp_valid && rsp_error_q;

    // 自由运行计数器：每个 CPU 时钟 +1，复位后从 0 开始。
    always_ff @(posedge clk) begin
        if (rst)
            counter_q <= 32'd0;
        else
            counter_q <= counter_q + 32'd1;
    end

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
                rsp_data_q  <= counter_q;
                rsp_error_q <= !window_hit || req_write;
            end
        end
    end
endmodule
