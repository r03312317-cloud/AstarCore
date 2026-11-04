// 架构导读：dc_realtime_core_tcm_bram。
// 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
module dc_realtime_core_tcm_bram #(
    // 静态配置：parameter int unsigned ADDR_WIDTH = 8。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned ADDR_WIDTH = 8,
    // 静态配置：parameter int unsigned READ_LATENCY = 2。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned READ_LATENCY = 2,
    // 静态配置：parameter INIT_FILE = ""。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter INIT_FILE = ""   // PDS ADS 不支持 `parameter string`
) (
    // 接口声明：input logic clk。
    input  logic                  clk,
    input  logic                  enable,
    input  logic [ADDR_WIDTH-1:0] address,
    input  logic                  write,
    input  logic [31:0]           wdata,
    input  logic [3:0]            wstrb,
    output logic [31:0]           rdata
);
    timeunit 1ns;
    timeprecision 1ps;

    // 静态配置：localparam int unsigned WORDS = 1 << ADDR_WIDTH。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam int unsigned WORDS = 1 << ADDR_WIDTH;

    (* ram_style = "block" *) logic [31:0] memory [0:WORDS-1];
    // Preserve the RAM/output-register boundary: same two-cycle behavior,
    // but allow the last register to be placed close to the consuming logic.
    (* syn_keep = 1 *) logic [31:0] memory_rdata_q;

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end

    // READ_LATENCY=1 still uses a synchronous block-memory read register.
    // It removes only the *additional* output register, never infers async RAM.
    generate
        if (READ_LATENCY == 2) begin : g_output_register
            // 过程边界：always_ff @(posedge clk) rdata <= memory_rdata_q;。
            // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
            always_ff @(posedge clk) rdata <= memory_rdata_q;
        end else begin : g_native_sync_output
            assign rdata = memory_rdata_q;
        end
    endgenerate

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        if (enable) begin
            if (write) begin
                if (wstrb[0])
                    memory[address][7:0] <= wdata[7:0];
                if (wstrb[1])
                    memory[address][15:8] <= wdata[15:8];
                if (wstrb[2])
                    memory[address][23:16] <= wdata[23:16];
                if (wstrb[3])
                    memory[address][31:24] <= wdata[31:24];
            end
            memory_rdata_q <= memory[address];
        end
    end
endmodule
