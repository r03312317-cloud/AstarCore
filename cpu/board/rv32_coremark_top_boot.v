// 130 MHz board top with power-on reset and UART boot loader.
// Pin-compatible with rv32_coremark_top plus the uart_rx input (B24).
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// FPGA 顶层连接差分参考时钟、130MHz PLL、复位、UART 与 LED。
// 参考输入 125MHz，经冻结 PLL 参数生成 CPU 所用的 130MHz 时钟。
// 复位释放依赖锁定状态与同步链，不应把外部异步复位直接当正常数据路径。
// 内部例化完整 coremark_system_boot，架构参数由其 CPU/Cache 实例确定。
// ILA 由 PDS 在综合后插入，源码中未出现 ILA 实例不代表所烧位流没有调试核。
// 本文件不含算法加速器；LED 用于状态显示，不是 CoreMark 时间基准。
// 接口契约与阅读示例
// 外部低有效rst_in通过async_reset进入上电计数链，PLL失锁也会重启保持过程。
// 锁定后继续等待1024个CPU时钟才释放系统复位。
// UART和LED末端增加一个输出寄存，只平移波形一拍，不改变CPU或计时握手。
// 实际引脚以随包constraints为准；历史源注释的引脚名不能覆盖冻结PCF位置。
// 此文件中的PLL只是CPU时钟来源，最终频率验收必须看布局布线后的多角STA。
module rv32_coremark_top_boot #(
    // Experimental variant: only LOAD_BYPASS differs from the frozen baseline.
    // 参数 LOAD_BYPASS：允许年轻Load越过尚未进入LSU的老Load；
    // Store的顺序限制继续保留。
    parameter LOAD_BYPASS=1,
    // 参数 BIMODAL_INDEX_BITS：chooser和相关PC索引宽度；本板B9，
    // 局部方向启用后不应把表统称bimodal。
    parameter BIMODAL_INDEX_BITS=9,
    // 参数 GSHARE_INDEX_BITS：GShare方向表索引位数；本板G12对应4096个计数器。
    parameter GSHARE_INDEX_BITS=12,
    // 参数 HISTORY_BITS：预测历史位宽；本板H12，
    // 历史随预测和提交各有受控上下文。
    parameter HISTORY_BITS=12
)(
    // 接口字段：input clk_p, clk_n, rst_in, uart_rx。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input clk_p, clk_n, rst_in, uart_rx,
    // 接口字段：output reg uart_tx, output reg [7:0] led。
    // UART串行通信或接收发送状态；串口传输耗时不作为CoreMark算法计时分母。
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
