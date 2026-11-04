// 架构导读：dc_realtime_core_tcm_channel。
// 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
module dc_realtime_core_tcm_channel #(
    // 静态配置：parameter int unsigned ADDR_WIDTH = 14。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned ADDR_WIDTH = 14,
    // 静态配置：parameter logic [31:0] BASE_ADDR = 32'd0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] BASE_ADDR = 32'd0,
    // 静态配置：parameter INIT_FILE = "",。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter INIT_FILE = "",  // PDS ADS 不支持 `parameter string`
    // 静态配置：parameter logic READ_ONLY = 1'b0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic READ_ONLY = 1'b0,
    // 静态配置：parameter int unsigned READ_LATENCY = 2。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned READ_LATENCY = 2,
    // 静态配置：parameter bit EARLY_STORE_ACK = 1'b0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit EARLY_STORE_ACK = 1'b0
) (
    // 接口声明：input logic clk。
    // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
    input  logic        clk,
    // 接口声明：input logic rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input  logic        rst,
    // 接口声明：input logic req_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic        req_valid,
    // 接口声明：output logic req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic        req_ready,
    // 接口声明：input logic [31:0] req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] req_addr,
    // 接口声明：input logic req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic        req_write,
    // 接口声明：input logic [31:0] req_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input  logic [31:0] req_wdata,
    // 接口声明：input logic [3:0] req_wstrb。
    input  logic [3:0]  req_wstrb,
    output logic        rsp_valid,
    input  logic        rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic        rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    logic pending_q;
    logic fast_store_q;
    logic rsp_valid_q;
    logic rsp_error_q;
    logic [31:0] bram_rdata;
    logic req_accept;
    logic bram_enable;
    logic bram_write;
    logic req_address_valid;

    assign req_ready = !rst && !pending_q && (!rsp_valid_q || rsp_ready);
    assign req_accept = req_valid && req_ready;
    assign req_address_valid = req_addr >= BASE_ADDR &&
                               req_addr < BASE_ADDR + (32'd4 << ADDR_WIDTH);
    assign bram_enable = req_accept && req_address_valid &&
                         (!READ_ONLY || !req_write);
    assign bram_write = req_accept && req_address_valid &&
                        !READ_ONLY && req_write;
    assign rsp_valid = !rst && rsp_valid_q;
    assign rsp_rdata = !rsp_error_q && !fast_store_q ? bram_rdata : 32'd0;
    assign rsp_error = rsp_valid && rsp_error_q;

    dc_realtime_core_tcm_bram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .READ_LATENCY(READ_LATENCY),
        .INIT_FILE(INIT_FILE)
    ) tcm_memory (
        .clk,
        .enable(bram_enable),
        .address(req_addr[ADDR_WIDTH+1:2]),
        .write(bram_write),
        .wdata(req_wdata),
        .wstrb(req_wstrb),
        .rdata(bram_rdata)
    );

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            pending_q <= 1'b0;
            fast_store_q <= 1'b0;
            rsp_valid_q <= 1'b0;
            rsp_error_q <= 1'b0;
        end else begin
            // 握手/背压判断：rsp_valid_q && rsp_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if (rsp_valid_q && rsp_ready) begin
                fast_store_q <= 1'b0;
                rsp_valid_q <= 1'b0;
                rsp_error_q <= 1'b0;
            end
            if (pending_q) begin
                pending_q <= 1'b0;
                rsp_valid_q <= 1'b1;
            end
            if (req_accept) begin
                // The writable local BRAM commits at this edge, before ack consumption.
                // Reads and rejected accesses retain the original two-edge response.
                if ((EARLY_STORE_ACK && bram_write) || READ_LATENCY == 1) begin
                    pending_q <= 1'b0;
                    rsp_valid_q <= 1'b1;
                    fast_store_q <= bram_write;
                end else begin
                    pending_q <= 1'b1;
                    fast_store_q <= 1'b0;
                end
                rsp_error_q <= !req_address_valid || (READ_ONLY && req_write);
            end
        end
    end
endmodule
