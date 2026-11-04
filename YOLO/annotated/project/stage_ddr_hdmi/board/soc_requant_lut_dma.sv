// PIPEOPT4: large ping-pong tiles, four exact quantization lanes, burst INT8 stores.
// 架构导读：soc_requant_lut_dma。
// S3 重量化与 LUT 数据通路，读取 INT32 结果并写入量化 INT8 张量。
`timescale 1ns/1ps
// One-job DMA Requant plus optional current-layer 256-byte LUT.
// NPUOPT1: ping-pong INT32 input blocks overlap next-block reads with the
// existing arithmetic pipeline. Still ONE native memory request outstanding.
// INPUT_PREFETCH=0 retains the serialized reference schedule.
// Physical implementation/timing must be requalified.
// The caller must supply an accumulator bound proven from a just-completed
// signed-INT8 Conv. Only one memory request is outstanding at a time.
module soc_requant_lut_dma #(
    // 静态配置：parameter logic [31:0] DDR_BASE = 32'h8000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BASE = 32'h8000_0000,
    // 静态配置：parameter logic [32:0] DDR_BYTES = 33'h0400_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [32:0] DDR_BYTES = 33'h0400_0000,
    // 静态配置：parameter bit INPUT_PREFETCH = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit INPUT_PREFETCH = 1'b1,
    // 静态配置：parameter bit READ_BURST_ENABLE = 1'b0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit READ_BURST_ENABLE = 1'b0,
    // PIPEOPT4: opt-out retains byte/cycle-identical PIPEOPT3 implementation.
    parameter bit TILE_PIPELINE_ENABLE = 1'b1,
    // 静态配置：parameter int TILE_ELEMS = 256。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int TILE_ELEMS = 256,
    // 静态配置：parameter bit WRITE_ACK_OVERLAP = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit WRITE_ACK_OVERLAP = 1'b1,
    // 静态配置：parameter int QUANT_LANES = 4。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int QUANT_LANES = 4,
    // 静态配置：parameter bit PARAM_BURST_ENABLE = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit PARAM_BURST_ENABLE = 1'b1
) (
    // 接口声明：input logic clk。
    // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
    input  logic clk,
    // 接口声明：input logic rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input  logic rst,
    // 接口声明：input logic start_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic start_valid,
    // 接口声明：output logic start_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic start_ready,
    // 接口声明：input logic [31:0] source_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] source_addr,
    // 接口声明：input logic [31:0] output_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] output_addr,
    // 接口声明：input logic [31:0] bias_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] bias_addr,
    // 接口声明：input logic [31:0] multiplier_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] multiplier_addr,
    // 接口声明：input logic [31:0] shift_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] shift_addr,
    // 接口声明：input logic [31:0] lut_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] lut_addr,
    // 接口声明：input logic use_lut。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic use_lut,
    // 接口声明：input logic [31:0] pixels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [31:0] pixels,
    // 接口声明：input logic [8:0] channels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [8:0] channels,
    // 接口声明：input logic [31:0] acc_abs_bound。
    // 保存或选择累加结果，符号与精度由声明及算术表达式决定。
    input  logic [31:0] acc_abs_bound,
    // 接口声明：input logic [1:0] rounding_mode。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [1:0] rounding_mode,
    // 接口声明：input logic signed [31:0] output_zero。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] output_zero,
    // 接口声明：input logic signed [31:0] clamp_min。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] clamp_min,
    // 接口声明：input logic signed [31:0] clamp_max。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] clamp_max,
    // 接口声明：output logic done_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic done_valid,
    // 接口声明：input logic done_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic done_ready,
    // 接口声明：output logic [3:0] error_code。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [3:0] error_code,
    // 接口声明：output logic partial_output。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic partial_output,
    // 接口声明：output logic [31:0] read_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] read_bytes,
    // 接口声明：output logic [31:0] write_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] write_bytes,
    // 接口声明：output logic [31:0] stall_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] stall_cycles,
    // 接口声明：output logic [31:0] active_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] active_cycles,
    // 接口声明：output logic dma_req_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic dma_req_valid,
    // 接口声明：input logic dma_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic dma_req_ready,
    // 接口声明：output logic dma_req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic dma_req_write,
    // 接口声明：output logic [31:0] dma_req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] dma_req_addr,
    // 接口声明：output logic [127:0] dma_req_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [127:0] dma_req_wdata,
    // 接口声明：output logic [15:0] dma_req_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [15:0] dma_req_wstrb,
    // 接口声明：output logic [3:0] dma_req_id。
    // 把返回信息关联到对应的已接受请求。
    output logic [3:0] dma_req_id,
    // 接口声明：output logic [3:0] dma_req_len。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] dma_req_len,
    // 接口声明：input logic dma_rsp_last。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic dma_rsp_last,
    // 接口声明：input logic dma_rsp_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic dma_rsp_valid,
    // 接口声明：output logic dma_rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic dma_rsp_ready,
    // 接口声明：input logic dma_rsp_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic dma_rsp_write,
    // 接口声明：input logic [3:0] dma_rsp_id。
    // 把返回信息关联到对应的已接受请求。
    input  logic [3:0] dma_rsp_id,
    // 接口声明：input logic [127:0] dma_rsp_rdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input  logic [127:0] dma_rsp_rdata,
    // 接口声明：input logic dma_rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input  logic dma_rsp_error
);
    generate if (TILE_PIPELINE_ENABLE && READ_BURST_ENABLE) begin : tiled
        soc_requant_lut_dma_tiled #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES),
            .INPUT_PREFETCH(INPUT_PREFETCH),.READ_BURST_ENABLE(1'b1),
            .TILE_ELEMS(TILE_ELEMS),.LANES(QUANT_LANES),.PARAM_BURST_ENABLE(PARAM_BURST_ENABLE),
            .WRITE_ACK_OVERLAP(WRITE_ACK_OVERLAP)) impl(
            .clk,
            .rst,
            .start_valid,
            .start_ready,
            .source_addr,
            .output_addr,
            .bias_addr,
            .multiplier_addr,
            .shift_addr,
            .lut_addr,
            .use_lut,
            .pixels,
            .channels,
            .acc_abs_bound,
            .rounding_mode,
            .output_zero,
            .clamp_min,
            .clamp_max,
            .done_valid,
            .done_ready,
            .error_code,
            .partial_output,
            .read_bytes,
            .write_bytes,
            .stall_cycles,
            .active_cycles,
            .dma_req_valid,
            .dma_req_ready,
            .dma_req_write,
            .dma_req_addr,
            .dma_req_wdata,
            .dma_req_wstrb,
            .dma_req_id,
            .dma_req_len,
            .dma_rsp_last,
            .dma_rsp_valid,
            .dma_rsp_ready,
            .dma_rsp_write,
            .dma_rsp_id,
            .dma_rsp_rdata,
            .dma_rsp_error);
    end else begin : serial
        soc_requant_lut_dma_serial #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES),
            .INPUT_PREFETCH(INPUT_PREFETCH),.READ_BURST_ENABLE(READ_BURST_ENABLE)) impl(
            .clk,
            .rst,
            .start_valid,
            .start_ready,
            .source_addr,
            .output_addr,
            .bias_addr,
            .multiplier_addr,
            .shift_addr,
            .lut_addr,
            .use_lut,
            .pixels,
            .channels,
            .acc_abs_bound,
            .rounding_mode,
            .output_zero,
            .clamp_min,
            .clamp_max,
            .done_valid,
            .done_ready,
            .error_code,
            .partial_output,
            .read_bytes,
            .write_bytes,
            .stall_cycles,
            .active_cycles,
            .dma_req_valid,
            .dma_req_ready,
            .dma_req_write,
            .dma_req_addr,
            .dma_req_wdata,
            .dma_req_wstrb,
            .dma_req_id,
            .dma_req_len,
            .dma_rsp_last,
            .dma_rsp_valid,
            .dma_rsp_ready,
            .dma_rsp_write,
            .dma_rsp_id,
            .dma_rsp_rdata,
            .dma_rsp_error);
    end endgenerate
endmodule

`timescale 1ns/1ps
// One-job DMA Requant plus optional current-layer 256-byte LUT.
// NPUOPT1: ping-pong INT32 input blocks overlap next-block reads with the
// existing arithmetic pipeline. Still ONE native memory request outstanding.
// INPUT_PREFETCH=0 retains the serialized reference schedule.
// Physical implementation/timing must be requalified.
// The caller must supply an accumulator bound proven from a just-completed
// signed-INT8 Conv. Only one memory request is outstanding at a time.
module soc_requant_lut_dma_serial #(
    // 静态配置：parameter logic [31:0] DDR_BASE = 32'h8000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BASE = 32'h8000_0000,
    // 静态配置：parameter logic [32:0] DDR_BYTES = 33'h0400_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [32:0] DDR_BYTES = 33'h0400_0000,
    // 静态配置：parameter bit INPUT_PREFETCH = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit INPUT_PREFETCH = 1'b1,
    // 静态配置：parameter bit READ_BURST_ENABLE = 1'b0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit READ_BURST_ENABLE = 1'b0
) (
    // 接口声明：input logic clk。
    // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
    input  logic clk,
    // 接口声明：input logic rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input  logic rst,
    // 接口声明：input logic start_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic start_valid,
    // 接口声明：output logic start_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic start_ready,
    // 接口声明：input logic [31:0] source_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] source_addr,
    // 接口声明：input logic [31:0] output_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] output_addr,
    // 接口声明：input logic [31:0] bias_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] bias_addr,
    // 接口声明：input logic [31:0] multiplier_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] multiplier_addr,
    // 接口声明：input logic [31:0] shift_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] shift_addr,
    // 接口声明：input logic [31:0] lut_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] lut_addr,
    // 接口声明：input logic use_lut。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic use_lut,
    // 接口声明：input logic [31:0] pixels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [31:0] pixels,
    // 接口声明：input logic [8:0] channels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [8:0] channels,
    // 接口声明：input logic [31:0] acc_abs_bound。
    // 保存或选择累加结果，符号与精度由声明及算术表达式决定。
    input  logic [31:0] acc_abs_bound,
    // 接口声明：input logic [1:0] rounding_mode。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [1:0] rounding_mode,
    // 接口声明：input logic signed [31:0] output_zero。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] output_zero,
    // 接口声明：input logic signed [31:0] clamp_min。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] clamp_min,
    // 接口声明：input logic signed [31:0] clamp_max。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] clamp_max,
    // 接口声明：output logic done_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic done_valid,
    // 接口声明：input logic done_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic done_ready,
    // 接口声明：output logic [3:0] error_code。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [3:0] error_code,
    // 接口声明：output logic partial_output。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic partial_output,
    // 接口声明：output logic [31:0] read_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] read_bytes,
    // 接口声明：output logic [31:0] write_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] write_bytes,
    // 接口声明：output logic [31:0] stall_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] stall_cycles,
    // 接口声明：output logic [31:0] active_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] active_cycles,
    // 接口声明：output logic dma_req_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic dma_req_valid,
    // 接口声明：input logic dma_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic dma_req_ready,
    // 接口声明：output logic dma_req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic dma_req_write,
    // 接口声明：output logic [31:0] dma_req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] dma_req_addr,
    // 接口声明：output logic [127:0] dma_req_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [127:0] dma_req_wdata,
    // 接口声明：output logic [15:0] dma_req_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [15:0] dma_req_wstrb,
    // 接口声明：output logic [3:0] dma_req_id。
    // 把返回信息关联到对应的已接受请求。
    output logic [3:0] dma_req_id,
    // 接口声明：output logic [3:0] dma_req_len。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] dma_req_len,
    // 接口声明：input logic dma_rsp_last。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic dma_rsp_last,
    // 接口声明：input logic dma_rsp_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic dma_rsp_valid,
    // 接口声明：output logic dma_rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic dma_rsp_ready,
    // 接口声明：input logic dma_rsp_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic dma_rsp_write,
    // 接口声明：input logic [3:0] dma_rsp_id。
    // 把返回信息关联到对应的已接受请求。
    input  logic [3:0] dma_rsp_id,
    // 接口声明：input logic [127:0] dma_rsp_rdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input  logic [127:0] dma_rsp_rdata,
    // 接口声明：input logic dma_rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input  logic dma_rsp_error
);
    typedef enum logic [3:0] {
        IDLE, VALIDATE_SHAPE, VALIDATE_RANGES, VALIDATE_OVERLAP,
        PARAM_REQ, PARAM_RSP, LUT_REQ, LUT_RSP,
        INPUT_REQ, INPUT_RSP, PROCESS, OUTPUT_REQ, OUTPUT_RSP,
        COMPLETE, FAILED, PREFETCH_JOIN
    } state_t;
    state_t state;
    logic [31:0] source_q, output_q, elements_q, bound_q;
    logic [31:0] param_base_q [0:2];
    logic [31:0] lut_base_q;
    logic use_lut_q;
    logic [3:0] lut_beat;
    logic [8:0] channels_q, channel_index;
    logic [1:0] mode_q, param_kind;
    logic signed [31:0] zero_q, minimum_q, maximum_q;
    logic [8:0] param_beat;
    logic [31:0] completed;
    logic [4:0] block_count, feed_count, collect_count;
    logic [2:0] input_beat;
    logic param_issued;
    // A bank is read by arithmetic only after every required input beat has
    // retired successfully. The other bank can be filled concurrently.
    typedef enum logic [1:0] {PF_IDLE, PF_REQ, PF_RSP, PF_DONE} pf_state_t;
    pf_state_t pf_state;
    logic input_bank;
    logic [1:0] pf_beat;
    logic [4:0] pf_count;
    wire [31:0] next_first = completed + 32'(block_count);
    wire [31:0] next_remaining = elements_q - next_first;
    wire pf_request = INPUT_PREFETCH && pf_state==PF_REQ;
    wire pf_response = INPUT_PREFETCH && pf_state==PF_RSP;
    wire pf_rsp_fire = pf_response && dma_rsp_valid;
    wire pf_rsp_bad = pf_rsp_fire &&
        (dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0);
    wire arithmetic_fault = state==PROCESS && pipe_out_valid && pipe_out_overflow;

    wire signed [31:0] acc_word_q;
    wire [127:0] bias_beat_q, multiplier_beat_q, input_beat_q, lut_beat_q;
    wire [23:0] shift_beat_q;
    logic [1:0] lane_q, input_lane_q;
    logic result_pending;
    logic [7:0] result_value_q;
    logic signed [31:0] bias_word, multiplier_word;
    logic [5:0] shift_word;
    logic [7:0] output_block [0:15];
    logic pipe_in_valid, pipe_in_ready, pipe_out_valid, pipe_out_ready;
    logic signed [7:0] pipe_out_value;
    logic pipe_out_overflow;
    logic [127:0] output_packed;
    logic [15:0] output_strobes;
    logic [63:0] element_count_wide, element_count_q_wide;
    logic [63:0] source_bytes_wide, parameter_bytes_wide,
                 output_bytes_wide;
    logic shape_valid, addresses_valid, overlaps_valid;
    logic param_rsp_bad;
    logic [5:0][31:0] range_base;
    logic [5:0][63:0] range_bytes;
    logic [63:0] range_end_q [0:5];
    logic [32:0] ddr_end;

    // 静态配置：localparam logic [3:0] ERR_NONE=0, ERR_DESCRIPTOR=1, ERR_DMA=2。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [3:0] ERR_NONE=0, ERR_DESCRIPTOR=1, ERR_DMA=2,
                           ERR_PARAMETER=3, ERR_OVERFLOW=4;
    assign ddr_end={1'b0,DDR_BASE}+DDR_BYTES;
    assign element_count_wide=64'(pixels)*64'(channels);
    assign source_bytes_wide=((element_count_q_wide+64'd3)>>2)<<4;
    assign output_bytes_wide=((element_count_q_wide+64'd15)>>4)<<4;
    assign parameter_bytes_wide=((64'(channels_q)+64'd3)>>2)<<4;
    assign range_base[0]=source_q;
    assign range_base[1]=output_q;
    assign range_base[2]=param_base_q[0];
    assign range_base[3]=param_base_q[1];
    assign range_base[4]=param_base_q[2];
    assign range_base[5]=lut_base_q;
    assign range_bytes[0]=source_bytes_wide;
    assign range_bytes[1]=output_bytes_wide;
    assign range_bytes[2]=parameter_bytes_wide;
    assign range_bytes[3]=parameter_bytes_wide;
    assign range_bytes[4]=parameter_bytes_wide;
    assign range_bytes[5]=64'd256;
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        shape_valid=element_count_q_wide!=0 && channels_q!=0 &&
                    channels_q<=9'd256 &&
                    element_count_q_wide<=64'hffff_ffff &&
                    bound_q!=0 && bound_q<=32'h7fff_ffff &&
                    mode_q<=2'd2 && zero_q>=-32'sd128 &&
                    zero_q<=32'sd127 && minimum_q>=-32'sd128 &&
                    maximum_q<=32'sd127 && minimum_q<=maximum_q;
        addresses_valid=1;
        overlaps_valid=1;
        for (int i=0;i<6;i++) if (i<5 || use_lut_q) begin
            // 条件分支：检查 range_base[i][3:0]!=0 || range_base[i]<DDR_BASE ||。
            if (range_base[i][3:0]!=0 || range_base[i]<DDR_BASE ||
                range_end_q[i]> {31'd0,ddr_end})
                addresses_valid=0;
            for (int j=0;j<i;j++) begin
                // 条件分支：检查 (j<5 || use_lut_q) &&。
                if ((j<5 || use_lut_q) &&
                    {32'd0,range_base[i]} < range_end_q[j] &&
                    {32'd0,range_base[j]} < range_end_q[i])
                    overlaps_valid=0;
            end
        end
    end

    // 局部运算/辅助过程：function automatic logic [32:0] absolute_bias(input logic [31:0] word);。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function automatic logic [32:0] absolute_bias(input logic [31:0] word);
        logic signed [32:0] extended;
        begin
            extended=$signed({word[31],word});
            absolute_bias=extended<0 ? $unsigned(-extended):$unsigned(extended);
        end
    endfunction
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        param_rsp_bad=0;
        for (int lane=0;lane<4;lane++) begin
            // 条件分支：检查 (param_beat*9'd4+9'(lane))<channels_q。
            if ((param_beat*9'd4+9'(lane))<channels_q) begin
                // 按 param_kind 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                case (param_kind)
                    2'd0: if ({1'b0,bound_q}+{1'b0,absolute_bias(dma_rsp_rdata[lane*32 +:32])}
                              > 34'h07fff_ffff) param_rsp_bad=1;
                    2'd1: if (dma_rsp_rdata[lane*32+31]) param_rsp_bad=1;
                    default: if (dma_rsp_rdata[lane*32 +:32]>32'd62) param_rsp_bad=1;
                endcase
            end
        end
    end

    assign start_ready=(state==IDLE);
    assign done_valid=(state==COMPLETE || state==FAILED);
    assign dma_req_valid=(state==PARAM_REQ || state==LUT_REQ ||
                          state==INPUT_REQ || state==OUTPUT_REQ || pf_request);
    assign dma_req_write=(state==OUTPUT_REQ);
    assign dma_req_id=4'd0;
    assign dma_req_addr=pf_request ?
        source_q+(next_first<<2)+{26'd0,pf_beat,4'd0} :
        (state==PARAM_REQ)?
        param_base_q[param_kind]+{19'd0,param_beat,4'd0}:
        (state==LUT_REQ)?lut_base_q+{24'd0,lut_beat,4'd0}:
        (state==INPUT_REQ)?source_q+(completed<<2)+{25'd0,input_beat,4'd0}:
        output_q+completed;
    // Explicit read span: no speculative cache, no reads beyond the block.
    // Parameters remain scalar to preserve immediate invalid-parameter exit.
    logic [8:0] burst_words, boundary_words;
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        burst_words=1;
        // 复位相关判断：READ_BURST_ENABLE；分支方向由信号极性与取反表达式决定。
        if (READ_BURST_ENABLE) begin
            // 条件分支：检查 pf_request。
            if (pf_request) burst_words=((9'(pf_count)+9'd3)>>2)-9'(pf_beat);
            // 条件分支：检查 state==INPUT_REQ。
            else if (state==INPUT_REQ) burst_words=((9'(block_count)+9'd3)>>2)-9'(input_beat);
            // 条件分支：检查 state==LUT_REQ。
            else if (state==LUT_REQ) burst_words=9'd16-9'(lut_beat);
        end
        boundary_words=9'd256-{1'b0,dma_req_addr[11:4]};
        // 复位相关判断：burst_words>boundary_words；分支方向由信号极性与取反表达式决定。
        if(burst_words>boundary_words)burst_words=boundary_words;
        dma_req_len=4'(burst_words-1'b1);
    end
    wire response_last=!READ_BURST_ENABLE||dma_rsp_last;
    assign dma_req_wdata=output_packed;
    assign dma_req_wstrb=(state==OUTPUT_REQ)?output_strobes:16'd0;
    assign dma_rsp_ready=(state==PARAM_RSP || state==LUT_RSP ||
                          state==INPUT_RSP || state==OUTPUT_RSP || pf_response);
    assign pipe_in_valid=(state==PROCESS) && param_issued;
    assign pipe_out_ready=(state==PROCESS);
    assign bias_word=$signed(bias_beat_q[32*lane_q +:32]);
    assign multiplier_word=$signed(multiplier_beat_q[32*lane_q +:32]);
    assign shift_word=shift_beat_q[6*lane_q +:6];
    assign acc_word_q=$signed(input_beat_q[32*input_lane_q +:32]);

    // Each cache has exactly one wholeword write and one registered read.
    // No payload reset and no sixteen-byte dynamic write decoder. Only the
    // validated six shift bits are stored; padding lanes remain unobservable.
    wire response_ok=!rst && dma_rsp_valid && dma_rsp_ready &&
                     !dma_rsp_error && !dma_rsp_write && dma_rsp_id==0;
    wire parameter_write=response_ok && state==PARAM_RSP && !param_rsp_bad;
    // The valid token and synchronous RAM output advance together. A stalled
    // arithmetic input holds both address metadata and payload. Replacement
    // on the same edge as consumption removes the old every-other-cycle gap.
    wire operand_read=!rst && state==PROCESS && feed_count<block_count &&
                      (!param_issued || pipe_in_ready);
    wire result_read=!rst && state==PROCESS && pipe_out_valid && !pipe_out_overflow;
    wire input_write=response_ok &&
        (state==INPUT_RSP || (pf_response && error_code==ERR_NONE));
    wire [2:0] input_write_addr = pf_response ? {~input_bank,pf_beat} :
                                                             {input_bank,input_beat[1:0]};
    wire lut_write=response_ok && state==LUT_RSP;
    wire arithmetic_reset=rst || state==IDLE;
    soc_rq_sync_words #(.WIDTH(128),.ADDR_W(6)) bias_storage(
        .clk,.wr_en(parameter_write && param_kind==0),.wr_addr(param_beat[5:0]),
        .wr_data(dma_rsp_rdata),.rd_en(operand_read),.rd_addr(channel_index[7:2]),.rd_data(bias_beat_q));
    soc_rq_sync_words #(.WIDTH(128),.ADDR_W(6)) multiplier_storage(
        .clk,.wr_en(parameter_write && param_kind==1),.wr_addr(param_beat[5:0]),
        .wr_data(dma_rsp_rdata),.rd_en(operand_read),.rd_addr(channel_index[7:2]),.rd_data(multiplier_beat_q));
    soc_rq_sync_words #(.WIDTH(24),.ADDR_W(6)) shift_storage(
        .clk,.wr_en(parameter_write && param_kind==2),.wr_addr(param_beat[5:0]),
        .wr_data({dma_rsp_rdata[101:96],dma_rsp_rdata[69:64],dma_rsp_rdata[37:32],dma_rsp_rdata[5:0]}),
        .rd_en(operand_read),.rd_addr(channel_index[7:2]),.rd_data(shift_beat_q));
    // One 8x128 RAM instead of 4x128: +64 logical bytes, no extra MAC lanes.
    soc_rq_sync_words #(.WIDTH(128),.ADDR_W(3)) input_storage(
        .clk,.wr_en(input_write),.wr_addr(input_write_addr),
        .wr_data(dma_rsp_rdata),.rd_en(operand_read),
        .rd_addr({input_bank,feed_count[3:2]}),.rd_data(input_beat_q));
    soc_rq_sync_words #(.WIDTH(128),.ADDR_W(4)) lut_storage(
        .clk,.wr_en(lut_write),.wr_addr(lut_beat),
        .wr_data(dma_rsp_rdata),.rd_en(result_read && use_lut_q),
        .rd_addr(pipe_out_value[7:4]),.rd_data(lut_beat_q));

    for (genvar g=0;g<16;g++) begin: pack_output
        assign output_packed[g*8 +: 8]=output_block[g];
        assign output_strobes[g]=(5'(g)<block_count);
    end
    soc_requant_pipeline arithmetic (
        // A failed job can leave unconsumed arithmetic tokens. Clear these
        // while idle before accepting another job; cache payload is retained.
        .clk,.rst(arithmetic_reset),.in_valid(pipe_in_valid),.in_ready(pipe_in_ready),
        .in_acc(acc_word_q),.in_bias(bias_word),
        .in_multiplier(multiplier_word),.in_shift(shift_word),
        .in_mode(mode_q),.in_zero(zero_q),.in_clamp_min(minimum_q),
        .in_clamp_max(maximum_q),.out_valid(pipe_out_valid),
        .out_ready(pipe_out_ready),.out_value(pipe_out_value),
        .out_overflow(pipe_out_overflow));

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            state<=IDLE;
            source_q<=0;output_q<=0;elements_q<=0;bound_q<=0;
            element_count_q_wide<=0;
            for (int r=0;r<6;r++) range_end_q[r]<=0;
            param_base_q[0]<=0;param_base_q[1]<=0;param_base_q[2]<=0;
            lut_base_q<=0;use_lut_q<=0;lut_beat<=0;
            channels_q<=0;channel_index<=0;mode_q<=0;
            zero_q<=0;minimum_q<=0;maximum_q<=0;
            param_beat<=0;param_kind<=0;completed<=0;
            block_count<=0;feed_count<=0;collect_count<=0;input_beat<=0;
            param_issued<=0;lane_q<=0;input_lane_q<=0;
            pf_state<=PF_IDLE;pf_beat<=0;pf_count<=0;input_bank<=0;
            result_pending<=0;result_value_q<=0;
            error_code<=ERR_NONE;partial_output<=0;
            read_bytes<=0;write_bytes<=0;stall_cycles<=0;active_cycles<=0;
        end else begin
            result_pending<=result_read;
            // 条件分支：检查 result_read。
            if(result_read)result_value_q<=pipe_out_value;
            // 条件分支：检查 state!=IDLE && state!=COMPLETE && state!=FAILED。
            if (state!=IDLE && state!=COMPLETE && state!=FAILED)
                active_cycles<=active_cycles+1'b1;
            // 握手/背压判断：(dma_req_valid && !dma_req_ready) ||。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if ((dma_req_valid && !dma_req_ready) ||
                (dma_rsp_ready && !dma_rsp_valid))
                stall_cycles<=stall_cycles+1'b1;
            // The request, once advertised, cannot be withdrawn by a later
            // arithmetic failure. PREFETCH_JOIN drains its real response
            // before exposing done/failed; it does not fabricate completion.
            if (INPUT_PREFETCH) begin
                // 按 pf_state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                case (pf_state)
                    // 状态/选择分支 PF_IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                    PF_IDLE: if (state==PROCESS && error_code==ERR_NONE &&
                                 !arithmetic_fault && next_first<elements_q) begin
                        pf_count <= next_remaining>=32'd16 ? 5'd16 : 5'(next_remaining);
                        pf_beat <= 0;
                        pf_state <= PF_REQ;
                    end
                    // 状态/选择分支 PF_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                    PF_REQ: if (dma_req_ready) pf_state <= PF_RSP;
                    // 状态/选择分支 PF_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                    PF_RSP: if (dma_rsp_valid) begin
                        // 条件分支：检查 pf_rsp_bad || error_code!=ERR_NONE || arithmetic_fault。
                        if (pf_rsp_bad || error_code!=ERR_NONE || arithmetic_fault) begin
                            // Arithmetic can fail while a burst is being delivered.
                            // Keep consuming until its terminal token; never strand owner.
                            pf_state <= response_last ? PF_DONE : PF_RSP;
                        // 条件分支：检查 (({3'd0,pf_beat}+5'd1)<<2)>=pf_count。
                        end else if ((({3'd0,pf_beat}+5'd1)<<2)>=pf_count)
                            pf_state <= PF_DONE;
                        else begin
                            pf_beat <= pf_beat+1'b1;
                            pf_state <= response_last ? PF_REQ : PF_RSP;
                        end
                        // 条件分支：检查 !pf_rsp_bad。
                        if (!pf_rsp_bad) read_bytes <= read_bytes+32'd16;
                    end
                    default: ;
                endcase
            end
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case (state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if (start_valid) begin
                    pf_state<=PF_IDLE;pf_beat<=0;pf_count<=0;input_bank<=0;
                    param_issued<=0;
                    error_code<=ERR_NONE;
                    partial_output<=0;
                    read_bytes<=0;write_bytes<=0;stall_cycles<=0;active_cycles<=0;
                    source_q<=source_addr;output_q<=output_addr;
                    elements_q<=element_count_wide[31:0];
                    element_count_q_wide<=element_count_wide;
                    bound_q<=acc_abs_bound;
                    param_base_q[0]<=bias_addr;
                    param_base_q[1]<=multiplier_addr;
                    param_base_q[2]<=shift_addr;
                    lut_base_q<=lut_addr;use_lut_q<=use_lut;lut_beat<=0;
                    channels_q<=channels;
                    channel_index<=0;mode_q<=rounding_mode;
                    zero_q<=output_zero;minimum_q<=clamp_min;maximum_q<=clamp_max;
                    param_kind<=0;param_beat<=0;completed<=0;
                    state<=VALIDATE_SHAPE;
                end
                // 状态/选择分支 VALIDATE_SHAPE：本分支规定该编码下的寄存器更新和下一步动作。
                VALIDATE_SHAPE: if (!shape_valid) begin
                    error_code<=ERR_DESCRIPTOR;
                    state<=FAILED;
                end else begin
                    for (int r=0;r<6;r++)
                        range_end_q[r]<={32'd0,range_base[r]}+range_bytes[r];
                    state<=VALIDATE_RANGES;
                end
                // 状态/选择分支 VALIDATE_RANGES：本分支规定该编码下的寄存器更新和下一步动作。
                VALIDATE_RANGES: if (!addresses_valid) begin
                    error_code<=ERR_DESCRIPTOR;
                    state<=FAILED;
                end else state<=VALIDATE_OVERLAP;
                // 状态/选择分支 VALIDATE_OVERLAP：本分支规定该编码下的寄存器更新和下一步动作。
                VALIDATE_OVERLAP: if (!overlaps_valid) begin
                    error_code<=ERR_DESCRIPTOR;
                    state<=FAILED;
                end else state<=PARAM_REQ;
                // 状态/选择分支 PARAM_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                PARAM_REQ: if (dma_req_ready) state<=PARAM_RSP;
                // 状态/选择分支 PARAM_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                PARAM_RSP: if (dma_rsp_valid) begin
                    // 条件分支：检查 dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0。
                    if (dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0) begin
                        error_code<=ERR_DMA;
                        state<=FAILED;
                    // 条件分支：检查 param_rsp_bad。
                    end else if (param_rsp_bad) begin
                        error_code<=ERR_PARAMETER;
                        state<=FAILED;
                    end else begin
                        read_bytes<=read_bytes+32'd16;
                        // 条件分支：检查 (param_beat+9'd1)*9'd4 >= channels_q。
                        if ((param_beat+9'd1)*9'd4 >= channels_q) begin
                            param_beat<=0;
                            // 条件分支：检查 param_kind==2'd2。
                            if (param_kind==2'd2) begin
                                block_count <= elements_q>=32'd16 ? 5'd16 : 5'(elements_q);
                                input_beat<=0;
                                state<=use_lut_q ? LUT_REQ : INPUT_REQ;
                            end else begin
                                param_kind<=param_kind+1'b1;
                                state<=PARAM_REQ;
                            end
                        end else begin
                            param_beat<=param_beat+1'b1;
                            state<=PARAM_REQ;
                        end
                    end
                end
                // 状态/选择分支 LUT_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                LUT_REQ: if (dma_req_ready) state<=LUT_RSP;
                // 状态/选择分支 LUT_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                LUT_RSP: if (dma_rsp_valid) begin
                    // 条件分支：检查 dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0。
                    if (dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0) begin
                        error_code<=ERR_DMA;
                        state<=FAILED;
                    end else begin
                        read_bytes<=read_bytes+32'd16;
                        // 条件分支：检查 lut_beat==4'd15。
                        if (lut_beat==4'd15) begin
                            input_beat<=0;
                            state<=INPUT_REQ;
                        end else begin
                            lut_beat<=lut_beat+1'b1;
                            state<=response_last ? LUT_REQ : LUT_RSP;
                        end
                    end
                end
                // 状态/选择分支 INPUT_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                INPUT_REQ: if (dma_req_ready) state<=INPUT_RSP;
                // 状态/选择分支 INPUT_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                INPUT_RSP: if (dma_rsp_valid) begin
                    // 条件分支：检查 dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0。
                    if (dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0) begin
                        error_code<=ERR_DMA;
                        partial_output<=(completed!=0);
                        state<=FAILED;
                    end else begin
                        read_bytes<=read_bytes+32'd16;
                        if ((5'(input_beat)+5'd1)*5'd4>=block_count) begin
                            feed_count<=0;collect_count<=0;param_issued<=0;
                            state<=PROCESS;
                        end else begin
                            input_beat<=input_beat+1'b1;
                            state<=response_last ? INPUT_REQ : INPUT_RSP;
                        end
                    end
                end
                // 状态/选择分支 PROCESS：本分支规定该编码下的寄存器更新和下一步动作。
                PROCESS: begin
                    if (result_pending) begin
                        output_block[collect_count[3:0]]<=use_lut_q ?
                            lut_beat_q[8*result_value_q[3:0] +:8] : result_value_q;
                        collect_count<=collect_count+1'b1;
                        if (collect_count+5'd1==block_count)
                            state <= INPUT_PREFETCH && pf_state!=PF_DONE && next_first<elements_q ?
                                   // 状态/选择分支 PREFETCH_JOIN ：本分支规定该编码下的寄存器更新和下一步动作。
                                   PREFETCH_JOIN : OUTPUT_REQ;
                    end
                    if (param_issued && pipe_in_ready)param_issued<=0;
                    if (operand_read) begin
                        lane_q<=channel_index[1:0];input_lane_q<=feed_count[1:0];
                        param_issued<=1;feed_count<=feed_count+1'b1;
                        channel_index<=channel_index+9'd1==channels_q ? 9'd0:channel_index+1'b1;
                    end
                    if (pipe_out_valid && pipe_out_overflow) begin
                        error_code<=ERR_OVERFLOW;partial_output<=(completed!=0);
                        param_issued<=0;
                        state<=INPUT_PREFETCH ? PREFETCH_JOIN : FAILED;
                    end
                end
                // 状态/选择分支 PREFETCH_JOIN：本分支规定该编码下的寄存器更新和下一步动作。
                PREFETCH_JOIN: begin
                    // PF_IDLE is permitted only for the final block, or an
                    // arithmetic failure before any prefetch was launched.
                    if (pf_state==PF_DONE || pf_state==PF_IDLE)
                        state <= error_code!=ERR_NONE ? FAILED : OUTPUT_REQ;
                end
                // 状态/选择分支 OUTPUT_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                OUTPUT_REQ: if (dma_req_ready) state<=OUTPUT_RSP;
                // 状态/选择分支 OUTPUT_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                OUTPUT_RSP: if (dma_rsp_valid) begin
                    if (dma_rsp_error || !dma_rsp_write || dma_rsp_id!=4'd0) begin
                        error_code<=ERR_DMA;
                        partial_output<=1'b1;
                        state<=FAILED;
                    end else begin
                        write_bytes<=write_bytes+32'(block_count);
                        completed<=completed+32'(block_count);
                        if (completed+32'(block_count)==elements_q)
                            state<=COMPLETE;
                        else begin
                            block_count<=elements_q-completed-32'(block_count)>=32'd16 ?
                                5'd16:5'(elements_q-completed-32'(block_count));
                            input_beat<=0;
                            if (INPUT_PREFETCH) begin
                                input_bank<=~input_bank;
                                pf_state<=PF_IDLE;
                                feed_count<=0;collect_count<=0;param_issued<=0;
                                state<=PROCESS;
                            end else state<=INPUT_REQ;
                        end
                    end
                end
                COMPLETE, FAILED: if (done_ready) state<=IDLE;
                default: state<=FAILED;
            endcase
            // A read fault in the NEXT bank invalidates this job. No current
            // output is committed afterwards, and the accepted bad response
            // has already retired. The arithmetic pipeline resets in IDLE.
            if (pf_rsp_bad) begin
                error_code<=ERR_DMA;partial_output<=(completed!=0);
                param_issued<=0;state<=PREFETCH_JOIN;
            end
        end
    end
endmodule


`timescale 1ns/1ps
// One-job DMA Requant plus optional current-layer 256-byte LUT.
// NPUOPT1: ping-pong INT32 input blocks overlap next-block reads with the
// existing arithmetic pipeline. Still ONE native memory request outstanding.
// INPUT_PREFETCH=0 retains the serialized reference schedule.
// Physical implementation/timing must be requalified.
// The caller must supply an accumulator bound proven from a just-completed
// signed-INT8 Conv. Only one memory request is outstanding at a time.
module soc_requant_lut_dma_tiled #(
    // 静态配置：parameter logic [31:0] DDR_BASE = 32'h8000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BASE = 32'h8000_0000,
    // 静态配置：parameter logic [32:0] DDR_BYTES = 33'h0400_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [32:0] DDR_BYTES = 33'h0400_0000,
    // 静态配置：parameter bit INPUT_PREFETCH = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit INPUT_PREFETCH = 1'b1,
    // 静态配置：parameter bit READ_BURST_ENABLE = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit READ_BURST_ENABLE = 1'b1,
    // 静态配置：parameter bit WRITE_ACK_OVERLAP = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit WRITE_ACK_OVERLAP = 1'b1,
    // 静态配置：parameter int TILE_ELEMS=256, LANES=4。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int TILE_ELEMS=256, LANES=4,
    // 静态配置：parameter bit PARAM_BURST_ENABLE=1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit PARAM_BURST_ENABLE=1'b1
) (
    // 接口声明：input logic clk。
    // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
    input  logic clk,
    // 接口声明：input logic rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input  logic rst,
    // 接口声明：input logic start_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic start_valid,
    // 接口声明：output logic start_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic start_ready,
    // 接口声明：input logic [31:0] source_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] source_addr,
    // 接口声明：input logic [31:0] output_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] output_addr,
    // 接口声明：input logic [31:0] bias_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] bias_addr,
    // 接口声明：input logic [31:0] multiplier_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] multiplier_addr,
    // 接口声明：input logic [31:0] shift_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] shift_addr,
    // 接口声明：input logic [31:0] lut_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] lut_addr,
    // 接口声明：input logic use_lut。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic use_lut,
    // 接口声明：input logic [31:0] pixels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [31:0] pixels,
    // 接口声明：input logic [8:0] channels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [8:0] channels,
    // 接口声明：input logic [31:0] acc_abs_bound。
    // 保存或选择累加结果，符号与精度由声明及算术表达式决定。
    input  logic [31:0] acc_abs_bound,
    // 接口声明：input logic [1:0] rounding_mode。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic [1:0] rounding_mode,
    // 接口声明：input logic signed [31:0] output_zero。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] output_zero,
    // 接口声明：input logic signed [31:0] clamp_min。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] clamp_min,
    // 接口声明：input logic signed [31:0] clamp_max。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic signed [31:0] clamp_max,
    // 接口声明：output logic done_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic done_valid,
    // 接口声明：input logic done_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic done_ready,
    // 接口声明：output logic [3:0] error_code。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [3:0] error_code,
    // 接口声明：output logic partial_output。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic partial_output,
    // 接口声明：output logic [31:0] read_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] read_bytes,
    // 接口声明：output logic [31:0] write_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] write_bytes,
    // 接口声明：output logic [31:0] stall_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] stall_cycles,
    // 接口声明：output logic [31:0] active_cycles。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] active_cycles,
    // 接口声明：output logic dma_req_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic dma_req_valid,
    // 接口声明：input logic dma_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic dma_req_ready,
    // 接口声明：output logic dma_req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic dma_req_write,
    // 接口声明：output logic [31:0] dma_req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] dma_req_addr,
    // 接口声明：output logic [127:0] dma_req_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [127:0] dma_req_wdata,
    // 接口声明：output logic [15:0] dma_req_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [15:0] dma_req_wstrb,
    // 接口声明：output logic [3:0] dma_req_id。
    // 把返回信息关联到对应的已接受请求。
    output logic [3:0] dma_req_id,
    // 接口声明：output logic [3:0] dma_req_len。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] dma_req_len,
    // 接口声明：input logic dma_rsp_last。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic dma_rsp_last,
    // 接口声明：input logic dma_rsp_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic dma_rsp_valid,
    // 接口声明：output logic dma_rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic dma_rsp_ready,
    // 接口声明：input logic dma_rsp_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic dma_rsp_write,
    // 接口声明：input logic [3:0] dma_rsp_id。
    // 把返回信息关联到对应的已接受请求。
    input  logic [3:0] dma_rsp_id,
    // 接口声明：input logic [127:0] dma_rsp_rdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input  logic [127:0] dma_rsp_rdata,
    // 接口声明：input logic dma_rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input  logic dma_rsp_error
);
    // 静态配置：localparam int COUNT_W=$clog2(TILE_ELEMS+1)。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam int COUNT_W=$clog2(TILE_ELEMS+1);
    // 静态配置：localparam int WORD_W=$clog2(TILE_ELEMS/4)。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam int WORD_W=$clog2(TILE_ELEMS/4);
    // 静态配置：localparam int OUT_W=$clog2(TILE_ELEMS/16+1)。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam int OUT_W=$clog2(TILE_ELEMS/16+1);
    typedef logic [COUNT_W-1:0] count_t;
    typedef logic [WORD_W-1:0] word_t;
    // Only a multiple-of-four channel geometry uses all four lanes.
    // Odd/channel-tail geometries use lane 0 with the same larger tile.
    logic vector_q;
    wire [2:0] step_elements=vector_q?3'd4:3'd1;
    logic [OUT_W-1:0] output_word;
    logic [4:0] output_left;
    logic output_packet;
    // The bridge owns all old output bytes once the last W request is accepted.
    // Reuse the existing tile buffer, but retain a real B-response fence.
    // No following DMA request or job completion may pass this fence.
    logic write_pending;
    count_t pending_write_bytes;
    logic [COUNT_W-1:0] output_packet_bytes;
    wire [COUNT_W-1:0] output_first=count_t'(output_word)<<4;
    wire [COUNT_W-1:0] output_remaining=block_count-output_first;
    wire [4:0] output_valid_bytes=output_remaining>=16?5'd16:5'(output_remaining);
    typedef enum logic [3:0] {
        IDLE, VALIDATE_SHAPE, VALIDATE_RANGES, VALIDATE_OVERLAP,
        PARAM_REQ, PARAM_RSP, LUT_REQ, LUT_RSP,
        INPUT_REQ, INPUT_RSP, PROCESS, OUTPUT_REQ, OUTPUT_RSP,
        COMPLETE, FAILED, PREFETCH_JOIN
    } state_t;
    state_t state;
    logic [31:0] source_q, output_q, elements_q, bound_q;
    logic [31:0] param_base_q [0:2];
    logic [31:0] lut_base_q;
    logic use_lut_q;
    logic [3:0] lut_beat;
    logic [8:0] channels_q, channel_index;
    logic [1:0] mode_q, param_kind;
    logic signed [31:0] zero_q, minimum_q, maximum_q;
    logic [8:0] param_beat;
    logic [31:0] completed;
    count_t block_count, feed_count, collect_count;
    word_t input_beat;
    logic param_issued;
    // A bank is read by arithmetic only after every required input beat has
    // retired successfully. The other bank can be filled concurrently.
    typedef enum logic [1:0] {PF_IDLE, PF_REQ, PF_RSP, PF_DONE} pf_state_t;
    pf_state_t pf_state;
    logic input_bank;
    word_t pf_beat;
    count_t pf_count;
    wire [31:0] next_first = completed + 32'(block_count);
    wire [31:0] next_remaining = elements_q - next_first;
    wire pf_request = INPUT_PREFETCH && pf_state==PF_REQ;
    wire pf_response = INPUT_PREFETCH && pf_state==PF_RSP;
    wire pf_rsp_fire = pf_response && dma_rsp_valid;
    wire pf_rsp_bad = pf_rsp_fire &&
        (dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0);
    wire arithmetic_fault = state==PROCESS && pipe_out_valid && pipe_out_overflow;

    wire [127:0] bias_beat_q,multiplier_beat_q,input_beat_q;
    wire [23:0] shift_beat_q;
    logic [1:0] lane_q,input_lane_q;
    logic result_pending;
    logic [7:0] result_value_q[0:LANES-1];
    wire [127:0] lut_beat_q[0:LANES-1];
    wire [LANES-1:0] lane_ready,lane_valid,lane_overflow;
    wire [7:0] lane_value[0:LANES-1];
    logic [7:0] output_block[0:TILE_ELEMS-1];
    wire pipe_in_valid,pipe_in_ready,pipe_out_valid,pipe_out_ready,pipe_out_overflow;
    logic [127:0] output_packed;
    logic [15:0] output_strobes;
    logic [63:0] element_count_wide, element_count_q_wide;
    logic [63:0] source_bytes_wide, parameter_bytes_wide,
                 output_bytes_wide;
    logic shape_valid, addresses_valid, overlaps_valid;
    logic param_rsp_bad;
    logic [5:0][31:0] range_base;
    logic [5:0][63:0] range_bytes;
    logic [63:0] range_end_q [0:5];
    logic [32:0] ddr_end;

    // 静态配置：localparam logic [3:0] ERR_NONE=0, ERR_DESCRIPTOR=1, ERR_DMA=2。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [3:0] ERR_NONE=0, ERR_DESCRIPTOR=1, ERR_DMA=2,
                           ERR_PARAMETER=3, ERR_OVERFLOW=4;
    assign ddr_end={1'b0,DDR_BASE}+DDR_BYTES;
    assign element_count_wide=64'(pixels)*64'(channels);
    assign source_bytes_wide=((element_count_q_wide+64'd3)>>2)<<4;
    assign output_bytes_wide=((element_count_q_wide+64'd15)>>4)<<4;
    assign parameter_bytes_wide=((64'(channels_q)+64'd3)>>2)<<4;
    assign range_base[0]=source_q;
    assign range_base[1]=output_q;
    assign range_base[2]=param_base_q[0];
    assign range_base[3]=param_base_q[1];
    assign range_base[4]=param_base_q[2];
    assign range_base[5]=lut_base_q;
    assign range_bytes[0]=source_bytes_wide;
    assign range_bytes[1]=output_bytes_wide;
    assign range_bytes[2]=parameter_bytes_wide;
    assign range_bytes[3]=parameter_bytes_wide;
    assign range_bytes[4]=parameter_bytes_wide;
    assign range_bytes[5]=64'd256;
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        shape_valid=element_count_q_wide!=0 && channels_q!=0 &&
                    channels_q<=9'd256 &&
                    element_count_q_wide<=64'hffff_ffff &&
                    bound_q!=0 && bound_q<=32'h7fff_ffff &&
                    mode_q<=2'd2 && zero_q>=-32'sd128 &&
                    zero_q<=32'sd127 && minimum_q>=-32'sd128 &&
                    maximum_q<=32'sd127 && minimum_q<=maximum_q;
        addresses_valid=1;
        overlaps_valid=1;
        for (int i=0;i<6;i++) if (i<5 || use_lut_q) begin
            if (range_base[i][3:0]!=0 || range_base[i]<DDR_BASE ||
                range_end_q[i]> {31'd0,ddr_end})
                addresses_valid=0;
            for (int j=0;j<i;j++) begin
                if ((j<5 || use_lut_q) &&
                    {32'd0,range_base[i]} < range_end_q[j] &&
                    {32'd0,range_base[j]} < range_end_q[i])
                    overlaps_valid=0;
            end
        end
    end

    // 局部运算/辅助过程：function automatic logic [32:0] absolute_bias(input logic [31:0] word);。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function automatic logic [32:0] absolute_bias(input logic [31:0] word);
        logic signed [32:0] extended;
        begin
            extended=$signed({word[31],word});
            absolute_bias=extended<0 ? $unsigned(-extended):$unsigned(extended);
        end
    endfunction
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        param_rsp_bad=0;
        for (int lane=0;lane<4;lane++) begin
            if ((param_beat*9'd4+9'(lane))<channels_q) begin
                // 按 param_kind 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                case (param_kind)
                    2'd0: if ({1'b0,bound_q}+{1'b0,absolute_bias(dma_rsp_rdata[lane*32 +:32])}
                              > 34'h07fff_ffff) param_rsp_bad=1;
                    2'd1: if (dma_rsp_rdata[lane*32+31]) param_rsp_bad=1;
                    default: if (dma_rsp_rdata[lane*32 +:32]>32'd62) param_rsp_bad=1;
                endcase
            end
        end
    end

    assign start_ready=(state==IDLE);
    assign done_valid=(state==COMPLETE || state==FAILED);
    assign dma_req_valid=(state==PARAM_REQ || state==LUT_REQ ||
                          state==INPUT_REQ || state==OUTPUT_REQ || pf_request);
    assign dma_req_write=(state==OUTPUT_REQ);
    assign dma_req_id=4'd0;
    assign dma_req_addr=pf_request ?
        source_q+(next_first<<2)+(32'(pf_beat)<<4) :
        (state==PARAM_REQ)?
        param_base_q[param_kind]+{19'd0,param_beat,4'd0}:
        (state==LUT_REQ)?lut_base_q+{24'd0,lut_beat,4'd0}:
        (state==INPUT_REQ)?source_q+(completed<<2)+(32'(input_beat)<<4):
        output_q+completed+(32'(output_word)<<4);
    // Explicit read span: no speculative cache, no reads beyond the block.
    // Parameter fetches use the same bounded bursts as inputs. An invalid
    // parameter drains its accepted burst before reporting failure.
    logic [8:0] burst_words, boundary_words;
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        burst_words=1;
        // 复位相关判断：READ_BURST_ENABLE；分支方向由信号极性与取反表达式决定。
        if (READ_BURST_ENABLE) begin
            if (pf_request) burst_words=((9'(pf_count)+9'd3)>>2)-9'(pf_beat);
            else if (state==INPUT_REQ) burst_words=((9'(block_count)+9'd3)>>2)-9'(input_beat);
            else if (state==LUT_REQ) burst_words=9'd16-9'(lut_beat);
            // 复位相关判断：state==PARAM_REQ && PARAM_BURST_ENABLE；分支方向由信号极性与取反表达式决定。
            else if (state==PARAM_REQ && PARAM_BURST_ENABLE)
                burst_words=((channels_q+9'd3)>>2)-param_beat;
            else if (state==OUTPUT_REQ && !output_packet)
                burst_words=((9'(block_count)+9'd15)>>4)-9'(output_word);
        end
        // 复位相关判断：burst_words>16；分支方向由信号极性与取反表达式决定。
        if(burst_words>16)burst_words=16;
        boundary_words=9'd256-{1'b0,dma_req_addr[11:4]};
        // 复位相关判断：burst_words>boundary_words；分支方向由信号极性与取反表达式决定。
        if(burst_words>boundary_words)burst_words=boundary_words;
        dma_req_len=4'(burst_words-1'b1);
    end
    wire response_last=!READ_BURST_ENABLE||dma_rsp_last;
    assign dma_req_wdata=output_packed;
    assign dma_req_wstrb=(state==OUTPUT_REQ)?output_strobes:16'd0;
    assign dma_rsp_ready=(state==PARAM_RSP || state==LUT_RSP ||
                          state==INPUT_RSP || state==OUTPUT_RSP || pf_response || write_pending);
    assign pipe_in_valid=(state==PROCESS) && param_issued;
    assign pipe_out_ready=(state==PROCESS);
    assign pipe_in_ready=&lane_ready;
    assign pipe_out_valid=&lane_valid;
    assign pipe_out_overflow=vector_q? (|lane_overflow):lane_overflow[0];
    // Each cache has exactly one wholeword write and one registered read.
    // No payload reset and no sixteen-byte dynamic write decoder. Only the
    // validated six shift bits are stored; padding lanes remain unobservable.
    wire response_ok=!rst && dma_rsp_valid && dma_rsp_ready &&
                     !write_pending && !dma_rsp_error && !dma_rsp_write && dma_rsp_id==0;
    wire parameter_write=response_ok && state==PARAM_RSP && !param_rsp_bad && error_code==ERR_NONE;
    // The valid token and synchronous RAM output advance together. A stalled
    // arithmetic input holds both address metadata and payload. Replacement
    // on the same edge as consumption removes the old every-other-cycle gap.
    wire operand_read=!rst && state==PROCESS && feed_count<block_count &&
                      (!param_issued || pipe_in_ready);
    wire result_read=!rst && state==PROCESS && pipe_out_valid && !pipe_out_overflow;
    wire input_write=response_ok &&
        (state==INPUT_RSP || (pf_response && error_code==ERR_NONE));
    wire [WORD_W:0] input_write_addr = pf_response ? {~input_bank,pf_beat} : {input_bank,input_beat};
    wire lut_write=response_ok && state==LUT_RSP;
    wire arithmetic_reset=rst || state==IDLE;
    soc_rq_sync_words #(.WIDTH(128),.ADDR_W(6)) bias_storage(
        .clk,.wr_en(parameter_write && param_kind==0),.wr_addr(param_beat[5:0]),
        .wr_data(dma_rsp_rdata),.rd_en(operand_read),.rd_addr(channel_index[7:2]),.rd_data(bias_beat_q));
    soc_rq_sync_words #(.WIDTH(128),.ADDR_W(6)) multiplier_storage(
        .clk,.wr_en(parameter_write && param_kind==1),.wr_addr(param_beat[5:0]),
        .wr_data(dma_rsp_rdata),.rd_en(operand_read),.rd_addr(channel_index[7:2]),.rd_data(multiplier_beat_q));
    soc_rq_sync_words #(.WIDTH(24),.ADDR_W(6)) shift_storage(
        .clk,.wr_en(parameter_write && param_kind==2),.wr_addr(param_beat[5:0]),
        .wr_data({dma_rsp_rdata[101:96],dma_rsp_rdata[69:64],dma_rsp_rdata[37:32],dma_rsp_rdata[5:0]}),
        .rd_en(operand_read),.rd_addr(channel_index[7:2]),.rd_data(shift_beat_q));
    // Ping-pong tiles. Each tile has TILE_ELEMS/4 complete INT32 words.
    soc_rq_sync_words #(.WIDTH(128),.ADDR_W(WORD_W+1)) input_storage(
        .clk,.wr_en(input_write),.wr_addr(input_write_addr),
        .wr_data(dma_rsp_rdata),.rd_en(operand_read),
        .rd_addr({input_bank,feed_count[WORD_W+1:2]}),.rd_data(input_beat_q));
    // Four read-only replicas provide independent LUT addresses without
    // an asynchronous multiport RAM. All replicas receive the same validated LUT.
    for(genvar g=0;g<LANES;g++)begin: lanes
        wire active_lane=(g==0)||vector_q;
        wire [1:0] selected_lane=vector_q?2'(g):lane_q;
        wire [1:0] selected_input=vector_q?2'(g):input_lane_q;
        soc_rq_sync_words #(.WIDTH(128),.ADDR_W(4)) lut_storage(
            .clk,.wr_en(lut_write),.wr_addr(lut_beat),.wr_data(dma_rsp_rdata),
            .rd_en(result_read && use_lut_q),.rd_addr(lane_value[g][7:4]),
            .rd_data(lut_beat_q[g]));
        soc_requant_pipeline arithmetic(
            .clk,.rst(arithmetic_reset),.in_valid(pipe_in_valid),.in_ready(lane_ready[g]),
            .in_acc(active_lane?$signed(input_beat_q[32*selected_input+:32]):32'sd0),
            .in_bias(active_lane?$signed(bias_beat_q[32*selected_lane+:32]):32'sd0),
            .in_multiplier(active_lane?$signed(multiplier_beat_q[32*selected_lane+:32]):32'sd0),
            .in_shift(active_lane?shift_beat_q[6*selected_lane+:6]:6'd0),
            .in_mode(mode_q),.in_zero(zero_q),.in_clamp_min(minimum_q),.in_clamp_max(maximum_q),
            .out_valid(lane_valid[g]),.out_ready(pipe_out_ready),
            .out_value(lane_value[g]),.out_overflow(lane_overflow[g]));
    end
    for(genvar g=0;g<16;g++)begin:pack_output
        assign output_packed[g*8+:8]=output_block[$clog2(TILE_ELEMS)'(output_first+count_t'(g))];
        assign output_strobes[g]=(5'(g)<output_valid_bytes);
    end

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            state<=IDLE;
            source_q<=0;output_q<=0;elements_q<=0;bound_q<=0;
            element_count_q_wide<=0;
            for (int r=0;r<6;r++) range_end_q[r]<=0;
            param_base_q[0]<=0;param_base_q[1]<=0;param_base_q[2]<=0;
            lut_base_q<=0;use_lut_q<=0;lut_beat<=0;
            channels_q<=0;channel_index<=0;mode_q<=0;
            zero_q<=0;minimum_q<=0;maximum_q<=0;
            param_beat<=0;param_kind<=0;completed<=0;
            block_count<=0;feed_count<=0;collect_count<=0;input_beat<=0;
            param_issued<=0;lane_q<=0;input_lane_q<=0;
            pf_state<=PF_IDLE;pf_beat<=0;pf_count<=0;input_bank<=0;
            result_pending<=0;write_pending<=0;pending_write_bytes<=0;
            for(int g=0;g<LANES;g++)result_value_q[g]<=0;
            vector_q<=0;output_word<=0;output_left<=0;output_packet<=0;output_packet_bytes<=0;
            error_code<=ERR_NONE;partial_output<=0;
            read_bytes<=0;write_bytes<=0;stall_cycles<=0;active_cycles<=0;
        end else begin
            result_pending<=result_read;
            if(result_read)for(int g=0;g<LANES;g++)result_value_q[g]<=lane_value[g];
            if (state!=IDLE && state!=COMPLETE && state!=FAILED)
                active_cycles<=active_cycles+1'b1;
            // 握手/背压判断：(dma_req_valid && !dma_req_ready) ||。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if ((dma_req_valid && !dma_req_ready) ||
                (dma_rsp_ready && !dma_rsp_valid))
                stall_cycles<=stall_cycles+1'b1;
            // The request, once advertised, cannot be withdrawn by a later
            // arithmetic failure. PREFETCH_JOIN drains its real response
            // before exposing done/failed; it does not fabricate completion.
            if (INPUT_PREFETCH) begin
                // 按 pf_state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
                case (pf_state)
                    // 状态/选择分支 PF_IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                    PF_IDLE: if ((state==PROCESS || state==PREFETCH_JOIN) && !write_pending && error_code==ERR_NONE &&
                                 !arithmetic_fault && next_first<elements_q) begin
                        pf_count <= next_remaining>=TILE_ELEMS ? count_t'(TILE_ELEMS) : count_t'(next_remaining);
                        pf_beat <= 0;
                        pf_state <= PF_REQ;
                    end
                    // 状态/选择分支 PF_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                    PF_REQ: if (dma_req_ready) pf_state <= PF_RSP;
                    // 状态/选择分支 PF_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                    PF_RSP: if (dma_rsp_valid) begin
                        if (pf_rsp_bad || error_code!=ERR_NONE || arithmetic_fault) begin
                            // Arithmetic can fail while a burst is being delivered.
                            // Keep consuming until its terminal token; never strand owner.
                            pf_state <= response_last ? PF_DONE : PF_RSP;
                        end else if (((count_t'(pf_beat)+count_t'(1))<<2)>=pf_count)
                            pf_state <= PF_DONE;
                        else begin
                            pf_beat <= pf_beat+1'b1;
                            pf_state <= response_last ? PF_REQ : PF_RSP;
                        end
                        if (!pf_rsp_bad) read_bytes <= read_bytes+32'd16;
                    end
                    default: ;
                endcase
            end
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case (state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if (start_valid) begin
                    write_pending<=0;pending_write_bytes<=0;
                    pf_state<=PF_IDLE;pf_beat<=0;pf_count<=0;input_bank<=0;
                    param_issued<=0;
                    vector_q<=(LANES==4 && channels[1:0]==0);
                    output_word<=0;output_left<=0;output_packet<=0;output_packet_bytes<=0;
                    error_code<=ERR_NONE;
                    partial_output<=0;
                    read_bytes<=0;write_bytes<=0;stall_cycles<=0;active_cycles<=0;
                    source_q<=source_addr;output_q<=output_addr;
                    elements_q<=element_count_wide[31:0];
                    element_count_q_wide<=element_count_wide;
                    bound_q<=acc_abs_bound;
                    param_base_q[0]<=bias_addr;
                    param_base_q[1]<=multiplier_addr;
                    param_base_q[2]<=shift_addr;
                    lut_base_q<=lut_addr;use_lut_q<=use_lut;lut_beat<=0;
                    channels_q<=channels;
                    channel_index<=0;mode_q<=rounding_mode;
                    zero_q<=output_zero;minimum_q<=clamp_min;maximum_q<=clamp_max;
                    param_kind<=0;param_beat<=0;completed<=0;
                    state<=VALIDATE_SHAPE;
                end
                // 状态/选择分支 VALIDATE_SHAPE：本分支规定该编码下的寄存器更新和下一步动作。
                VALIDATE_SHAPE: if (!shape_valid) begin
                    error_code<=ERR_DESCRIPTOR;
                    state<=FAILED;
                end else begin
                    for (int r=0;r<6;r++)
                        range_end_q[r]<={32'd0,range_base[r]}+range_bytes[r];
                    state<=VALIDATE_RANGES;
                end
                // 状态/选择分支 VALIDATE_RANGES：本分支规定该编码下的寄存器更新和下一步动作。
                VALIDATE_RANGES: if (!addresses_valid) begin
                    error_code<=ERR_DESCRIPTOR;
                    state<=FAILED;
                end else state<=VALIDATE_OVERLAP;
                // 状态/选择分支 VALIDATE_OVERLAP：本分支规定该编码下的寄存器更新和下一步动作。
                VALIDATE_OVERLAP: if (!overlaps_valid) begin
                    error_code<=ERR_DESCRIPTOR;
                    state<=FAILED;
                end else state<=PARAM_REQ;
                // 状态/选择分支 PARAM_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                PARAM_REQ: if (dma_req_ready) state<=PARAM_RSP;
                // 状态/选择分支 PARAM_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                PARAM_RSP: if (dma_rsp_valid) begin
                    if (error_code!=ERR_NONE || dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0 || param_rsp_bad) begin
                        if(error_code==ERR_NONE)
                            error_code<=(dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0)?ERR_DMA:ERR_PARAMETER;
                        // Keep the accepted native read owner through LAST.
                        // No cache or output may consume a rejected parameter.
                        if(response_last)state<=FAILED;
                    end else begin
                        read_bytes<=read_bytes+32'd16;
                        if ((param_beat+9'd1)*9'd4 >= channels_q) begin
                            param_beat<=0;
                            if (param_kind==2'd2) begin
                                block_count <= elements_q>=TILE_ELEMS ? count_t'(TILE_ELEMS) : count_t'(elements_q);
                                input_beat<=0;
                                state<=use_lut_q ? LUT_REQ : INPUT_REQ;
                            end else begin
                                param_kind<=param_kind+1'b1;
                                state<=PARAM_REQ;
                            end
                        end else begin
                            param_beat<=param_beat+1'b1;
                            state<=response_last ? PARAM_REQ : PARAM_RSP;
                        end
                    end
                end
                // 状态/选择分支 LUT_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                LUT_REQ: if (dma_req_ready) state<=LUT_RSP;
                // 状态/选择分支 LUT_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                LUT_RSP: if (dma_rsp_valid) begin
                    if (dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0) begin
                        error_code<=ERR_DMA;
                        state<=FAILED;
                    end else begin
                        read_bytes<=read_bytes+32'd16;
                        if (lut_beat==4'd15) begin
                            input_beat<=0;
                            state<=INPUT_REQ;
                        end else begin
                            lut_beat<=lut_beat+1'b1;
                            state<=response_last ? LUT_REQ : LUT_RSP;
                        end
                    end
                end
                // 状态/选择分支 INPUT_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                INPUT_REQ: if (dma_req_ready) state<=INPUT_RSP;
                // 状态/选择分支 INPUT_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                INPUT_RSP: if (dma_rsp_valid) begin
                    if (dma_rsp_error || dma_rsp_write || dma_rsp_id!=4'd0) begin
                        error_code<=ERR_DMA;
                        partial_output<=(write_bytes!=0);
                        state<=FAILED;
                    end else begin
                        read_bytes<=read_bytes+32'd16;
                        if ((count_t'(input_beat)+count_t'(1))*count_t'(4)>=block_count) begin
                            feed_count<=0;collect_count<=0;param_issued<=0;
                            state<=PROCESS;
                        end else begin
                            input_beat<=input_beat+1'b1;
                            state<=response_last ? INPUT_REQ : INPUT_RSP;
                        end
                    end
                end
                // 状态/选择分支 PROCESS：本分支规定该编码下的寄存器更新和下一步动作。
                PROCESS: begin
                    if(result_pending)begin
                        for(int g=0;g<LANES;g++)if(g==0 || vector_q)
                            output_block[$clog2(TILE_ELEMS)'(collect_count+count_t'(g))]<=use_lut_q ?
                                lut_beat_q[g][8*result_value_q[g][3:0]+:8] : result_value_q[g];
                        collect_count<=collect_count+count_t'(step_elements);
                        if(collect_count+count_t'(step_elements)==block_count)begin
                            output_word<=0;output_packet<=0;output_packet_bytes<=0;
                            state<=write_pending || (INPUT_PREFETCH && pf_state!=PF_DONE && next_first<elements_q) ? PREFETCH_JOIN:OUTPUT_REQ;
                        end
                    end
                    if (param_issued && pipe_in_ready)param_issued<=0;
                    if (operand_read) begin
                        lane_q<=channel_index[1:0];input_lane_q<=feed_count[1:0];
                        param_issued<=1;feed_count<=feed_count+count_t'(step_elements);
                        channel_index<=channel_index+9'(step_elements)==channels_q ? 9'd0:channel_index+9'(step_elements);
                    end
                    if (pipe_out_valid && pipe_out_overflow) begin
                        error_code<=ERR_OVERFLOW;partial_output<=(write_bytes!=0 || write_pending);
                        param_issued<=0;
                        state<=INPUT_PREFETCH ? PREFETCH_JOIN : FAILED;
                    end
                end
                // 状态/选择分支 PREFETCH_JOIN：本分支规定该编码下的寄存器更新和下一步动作。
                PREFETCH_JOIN: begin
                    // PF_IDLE is permitted only for the final block, or an
                    // arithmetic failure before any prefetch was launched.
                    if (!write_pending && (pf_state==PF_DONE ||
                        (pf_state==PF_IDLE && (error_code!=ERR_NONE ||
                         next_first>=elements_q || !INPUT_PREFETCH))))
                        state <= error_code!=ERR_NONE ? FAILED : OUTPUT_REQ;
                end
                // 状态/选择分支 OUTPUT_REQ：本分支规定该编码下的寄存器更新和下一步动作。
                OUTPUT_REQ: if(dma_req_ready)begin
                    output_word<=output_word+1'b1;
                    output_packet_bytes<=output_packet_bytes+count_t'(output_valid_bytes);
                    if(!output_packet)begin
                        output_packet<=1;
                        output_left<=5'(burst_words)-5'd1;
                        // 复位相关判断：burst_words==1；分支方向由信号极性与取反表达式决定。
                        if(burst_words==1)state<=OUTPUT_RSP;
                    end else begin
                        output_left<=output_left-1'b1;
                        if(output_left==1)state<=OUTPUT_RSP;
                    end
                    // Launch only after every byte in this tile was accepted.
                    // Prefetch is complete before OUTPUT_REQ; its other bank is
                    // now read-only. Split bursts at 4 KiB must finish first.
                    if (WRITE_ACK_OVERLAP && INPUT_PREFETCH &&
                        output_first+count_t'(16)>=block_count &&
                        next_first<elements_q && pf_state==PF_DONE &&
                        ((!output_packet && burst_words==1) ||
                         (output_packet && output_left==1))) begin
                        write_pending<=1;
                        pending_write_bytes<=output_packet_bytes+count_t'(output_valid_bytes);
                        completed<=next_first;
                        block_count<=pf_count;
                        input_bank<=~input_bank;pf_state<=PF_IDLE;
                        feed_count<=0;collect_count<=0;param_issued<=0;
                        output_word<=0;output_packet<=0;output_packet_bytes<=0;
                        state<=PROCESS;
                    end
                end
                // 状态/选择分支 OUTPUT_RSP：本分支规定该编码下的寄存器更新和下一步动作。
                OUTPUT_RSP: if(dma_rsp_valid)begin
                    if(dma_rsp_error || !dma_rsp_write || dma_rsp_id!=4'd0)begin
                        error_code<=ERR_DMA;partial_output<=1;state<=FAILED;
                    end else begin
                        write_bytes<=write_bytes+32'(output_packet_bytes);
                        output_packet<=0;output_packet_bytes<=0;
                        if((count_t'(output_word)<<4)<block_count)state<=OUTPUT_REQ;
                        else begin
                            completed<=completed+32'(block_count);
                            if(completed+32'(block_count)==elements_q)state<=COMPLETE;
                            else begin
                                block_count<=elements_q-completed-32'(block_count)>=TILE_ELEMS ?
                                    count_t'(TILE_ELEMS):count_t'(elements_q-completed-32'(block_count));
                                input_beat<=0;
                                if(INPUT_PREFETCH)begin
                                    input_bank<=~input_bank;pf_state<=PF_IDLE;
                                    feed_count<=0;collect_count<=0;param_issued<=0;state<=PROCESS;
                                end else state<=INPUT_REQ;
                            end
                        end
                    end
                end
                COMPLETE, FAILED: if (done_ready) state<=IDLE;
                default: state<=FAILED;
            endcase
            // Arithmetic may run while the previous write awaits its B token.
            // The single DMA owner remains the write: prefetch stays PF_IDLE.
            // Even arithmetic failure drains B before reporting completion.
            if (write_pending && dma_rsp_valid) begin
                write_pending<=0;
                pending_write_bytes<=0;
                if (dma_rsp_error || !dma_rsp_write || dma_rsp_id!=4'd0) begin
                    error_code<=ERR_DMA;partial_output<=1;
                    param_issued<=0;state<=FAILED;
                end else begin
                    write_bytes<=write_bytes+32'(pending_write_bytes);
                end
            end
            // A read fault in the NEXT bank invalidates this job. No current
            // output is committed afterwards, and the accepted bad response
            // has already retired. The arithmetic pipeline resets in IDLE.
            if (pf_rsp_bad) begin
                error_code<=ERR_DMA;partial_output<=(write_bytes!=0);
                param_issued<=0;state<=PREFETCH_JOIN;
            end
        end
    end
    initial begin
        if(TILE_ELEMS<16 || TILE_ELEMS>256 || (TILE_ELEMS&(TILE_ELEMS-1))!=0 ||
           (LANES!=1 && LANES!=4))$fatal(1,"RQ_TILED_PARAMETER");
    end
    // synthesis translate_off
    always_ff @(posedge clk)if(!rst && state==PROCESS)begin
        if(vector_q && (channel_index[1:0]!=0 || feed_count[1:0]!=0 || block_count[1:0]!=0))
            $fatal(1,"RQ_VECTOR_ALIGNMENT");
        if((|lane_valid)!=(&lane_valid))$fatal(1,"RQ_LANE_VALID_DIVERGENCE");
        if(feed_count>block_count || collect_count>block_count)$fatal(1,"RQ_TILE_COUNT");
    end
    // synthesis translate_on
endmodule


// The stage source list already includes this compilation unit. Keeping the
// small RAM here avoids introducing a missing dependency in existing builds.
module soc_rq_sync_words #(parameter int WIDTH=128,ADDR_W=6)(
    // 接口声明：input logic clk,wr_en,input logic [ADDR_W-1:0] wr_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input logic clk,wr_en,input logic [ADDR_W-1:0] wr_addr,
    // 接口声明：input logic [WIDTH-1:0] wr_data,input logic rd_en。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [WIDTH-1:0] wr_data,input logic rd_en,
    // 接口声明：input logic [ADDR_W-1:0] rd_addr,output logic [WIDTH-1:0] rd_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [ADDR_W-1:0] rd_addr,output logic [WIDTH-1:0] rd_data
);
    (* ram_style="block",syn_ramstyle="block_ram" *) logic [WIDTH-1:0] words[0:(1<<ADDR_W)-1];
    // 过程边界：always_ff @(posedge clk)begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk)begin
        if(wr_en)words[wr_addr]<=wr_data;
        if(rd_en)rd_data<=words[rd_addr];
    end
endmodule
