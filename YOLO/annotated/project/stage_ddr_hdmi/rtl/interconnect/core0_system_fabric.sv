// -----------------------------------------------------------------------------
// core0_system_fabric —— system 总线地址译码
//
// 上游：dc_realtime_core_npu_router 的 system_* 端口。
//   router 只截获 NPU 窗口 [0x7000_0000, 0x7001_0000)；**其余全部地址**转发到这里。
//   ITCM(0x1000_0000) 与 DTCM(0x2000_0000) 已在 wrapper 内部由 split_bus 分流，
//   不会到达本模块。因此本模块只需覆盖外设与"未映射"两种情况。
//
// 译码表
//   0x3000_0000 ~ 0x3000_0FFF -> Timer  (core0_cycle_timer)
//   0x4000_0000 ~ 0x4000_0FFF -> UART   (core0_uart_mmio)
//   其余                        -> 立即错误响应
//
// 为什么未映射地址要给错误响应而不是挂死
//   挂死会让"外设未命中"与"CPU 卡在异常"无法区分，也无法从 LED 诊断。给出
//   error 响应会让 CPU 产生精确的访问异常，可通过 fatal_state_diag 与 LED 观察。
//
// 仲裁：沿用 npu_router 的 owner 单笔模型
//   router 在响应握手前保持 owner，且只允许一笔未完成事务，因此这里只需要一个
//   2 位 owner 寄存器：请求被接受时锁定目标，响应握手后释放。
//   未映射时不需要等待目标，owner 直接进入 ERROR 状态并在下一拍给出响应
//   （与 npu_router 的 OWNER_ERROR 行为一致：接受后一拍响应）。
// -----------------------------------------------------------------------------

// 架构导读：core0_system_fabric。
// CPU 系统请求的地址路由与响应汇聚。
module core0_system_fabric #(
    // 静态配置：parameter logic [31:0] TIMER_BASE = 32'h3000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] TIMER_BASE  = 32'h3000_0000,
    // 静态配置：parameter logic [31:0] TIMER_SPAN = 32'h0000_1000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] TIMER_SPAN  = 32'h0000_1000,
    // 静态配置：parameter logic [31:0] UART_BASE = 32'h4000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] UART_BASE   = 32'h4000_0000,
    // 静态配置：parameter logic [31:0] UART_SPAN = 32'h0000_1000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] UART_SPAN   = 32'h0000_1000,
    // 静态配置：parameter int unsigned CLK_FREQ = 100_000_000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned CLK_FREQ    = 100_000_000,
    // 静态配置：parameter int unsigned BAUD_RATE = 115200。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned BAUD_RATE   = 115200
) (
    // 接口声明：input logic clk。
    // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
    input  logic        clk,
    // 接口声明：input logic rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input  logic        rst,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic [31:0] req_addr,
    input  logic        req_write,
    input  logic [31:0] req_wdata,
    input  logic [3:0]  req_wstrb,
    input  logic        req_is_fetch,
    output logic        rsp_valid,
    input  logic        rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic        rsp_error,

    output logic        uart_tx
);
    timeunit 1ns;
    timeprecision 1ps;

    // 静态配置：localparam logic [1:0] OWNER_NONE = 2'd0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [1:0] OWNER_NONE  = 2'd0;
    // 静态配置：localparam logic [1:0] OWNER_TIMER = 2'd1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [1:0] OWNER_TIMER = 2'd1;
    // 静态配置：localparam logic [1:0] OWNER_UART = 2'd2。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [1:0] OWNER_UART  = 2'd2;
    // 静态配置：localparam logic [1:0] OWNER_ERROR = 2'd3。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [1:0] OWNER_ERROR = 2'd3;

    logic [1:0] owner_q;

    logic select_timer;
    logic select_uart;
    logic select_error;
    logic in_timer_window;
    logic in_uart_window;
    logic request_accept;
    logic response_accept;

    logic        timer_req_valid;
    logic        timer_req_ready;
    logic        timer_rsp_valid;
    logic [31:0] timer_rsp_rdata;
    logic        timer_rsp_error;

    logic        uart_req_valid;
    logic        uart_req_ready;
    logic        uart_rsp_valid;
    logic [31:0] uart_rsp_rdata;
    logic        uart_rsp_error;

    assign in_timer_window = req_addr >= TIMER_BASE &&
                             req_addr <  TIMER_BASE + TIMER_SPAN;
    assign in_uart_window  = req_addr >= UART_BASE &&
                             req_addr <  UART_BASE + UART_SPAN;
    // 取指落到外设/未映射空间一律错误：指令不应从 MMIO 取指。
    // 注意 select_error 必须优先于 select_timer/select_uart：否则一次对外设地址的
    // 取指仍会被路由到外设并正常应答，错误就无法上报（仿真 T5 抓到该缺陷）。
    assign select_error = req_is_fetch || !(in_timer_window || in_uart_window);
    assign select_timer = in_timer_window && !select_error;
    assign select_uart  = in_uart_window  && !select_error;

    core0_cycle_timer #(
        .BASE_ADDR (TIMER_BASE),
        .SPAN_BYTES(TIMER_SPAN)
    ) timer_unit (
        .clk       (clk),
        .rst       (rst),
        .req_valid (timer_req_valid),
        .req_ready (timer_req_ready),
        .req_addr  (req_addr),
        .req_write (req_write),
        .req_wdata (req_wdata),
        .req_wstrb (req_wstrb),
        .rsp_valid (timer_rsp_valid),
        .rsp_ready (rsp_ready),
        .rsp_rdata (timer_rsp_rdata),
        .rsp_error (timer_rsp_error)
    );

    core0_uart_mmio #(
        .BASE_ADDR (UART_BASE),
        .SPAN_BYTES(UART_SPAN),
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) uart_unit (
        .clk       (clk),
        .rst       (rst),
        .req_valid (uart_req_valid),
        .req_ready (uart_req_ready),
        .req_addr  (req_addr),
        .req_write (req_write),
        .req_wdata (req_wdata),
        .req_wstrb (req_wstrb),
        .rsp_valid (uart_rsp_valid),
        .rsp_ready (rsp_ready),
        .rsp_rdata (uart_rsp_rdata),
        .rsp_error (uart_rsp_error),
        .uart_tx   (uart_tx)
    );

    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        timer_req_valid = 1'b0;
        uart_req_valid  = 1'b0;
        req_ready       = 1'b0;

        if (owner_q == OWNER_NONE) begin
            if (select_timer) begin
                timer_req_valid = req_valid;
                req_ready       = timer_req_ready;
            end else if (select_uart) begin
                uart_req_valid = req_valid;
                req_ready      = uart_req_ready;
            end else begin
                // 未映射：立即接受，owner 下一拍进入 ERROR。
                req_ready = 1'b1;
            end
        end
    end

    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        rsp_valid = 1'b0;
        rsp_rdata = 32'd0;
        rsp_error = 1'b0;
        // 按 owner_q 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
        case (owner_q)
            // 状态/选择分支 OWNER_TIMER：本分支规定该编码下的寄存器更新和下一步动作。
            OWNER_TIMER: begin
                rsp_valid = timer_rsp_valid;
                rsp_rdata = timer_rsp_rdata;
                rsp_error = timer_rsp_error;
            end
            // 状态/选择分支 OWNER_UART：本分支规定该编码下的寄存器更新和下一步动作。
            OWNER_UART: begin
                rsp_valid = uart_rsp_valid;
                rsp_rdata = uart_rsp_rdata;
                rsp_error = uart_rsp_error;
            end
            // 状态/选择分支 OWNER_ERROR：本分支规定该编码下的寄存器更新和下一步动作。
            OWNER_ERROR: begin
                rsp_valid = 1'b1;
                rsp_rdata = 32'd0;
                rsp_error = 1'b1;
            end
            default: begin
            end
        endcase
    end

    assign request_accept  = req_valid && req_ready;
    assign response_accept = rsp_valid && rsp_ready;

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            owner_q <= OWNER_NONE;
        end else begin
            if (response_accept)
                owner_q <= OWNER_NONE;
            if (owner_q == OWNER_NONE && request_accept) begin
                if (select_timer)
                    owner_q <= OWNER_TIMER;
                else if (select_uart)
                    owner_q <= OWNER_UART;
                else if (select_error)
                    owner_q <= OWNER_ERROR;
            end
        end
    end
endmodule
