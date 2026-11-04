// 架构导读：dc_realtime_core_itcm_channel。
// 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
module dc_realtime_core_itcm_channel #(
    // 静态配置：parameter int unsigned ADDR_WIDTH = 14。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned ADDR_WIDTH = 14,
    // 静态配置：parameter logic [31:0] BASE_ADDR = 32'h1000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] BASE_ADDR = 32'h1000_0000,
    // 静态配置：parameter INIT_FILE = ""。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter INIT_FILE = ""   // PDS ADS 不支持 `parameter string`
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
    // 接口声明：output logic rsp_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic        rsp_valid,
    // 接口声明：input logic rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic        rsp_ready,
    // 接口声明：output logic [31:0] rsp_rdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [31:0] rsp_rdata,
    // 接口声明：output logic rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic        rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    // 局部字段 logic [1:0] outstanding_count_q。
    // 记录数量或剩余进度，位宽限定可表达范围。
    logic [1:0] outstanding_count_q;
    // 局部字段 logic read_stage1_valid_q。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    logic read_stage1_valid_q;
    logic read_stage1_error_q;
    logic read_stage2_valid_q;
    logic read_stage2_error_q;
    logic [31:0] bram_rdata;
    logic [31:0] response_data_q [0:1];
    logic response_error_q [0:1];
    logic response_read_ptr_q;
    logic response_write_ptr_q;
    logic [1:0] response_count_q;
    logic req_accept;
    logic req_address_valid;
    logic rsp_accept;
    logic response_fifo_push;
    logic response_fifo_pop;

    // 组合连接 rsp_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
    assign rsp_valid = !rst &&
                       (response_count_q != 0 || read_stage2_valid_q);
    // 组合连接 rsp_rdata：保存/传递数据负载，数据有效性由独立控制字段约束。
    assign rsp_rdata = response_count_q != 0 ?
                       response_data_q[response_read_ptr_q] :
                       read_stage2_error_q ? 32'd0 : bram_rdata;
    // 组合连接 rsp_error：记录异常状态；查看置位与清除分支可确定其保持范围。
    assign rsp_error = response_count_q != 0 ?
                       response_error_q[response_read_ptr_q] :
                       read_stage2_error_q;
    // 组合连接 rsp_accept：保存或选择累加结果，符号与精度由声明及算术表达式决定。
    assign rsp_accept = rsp_valid && rsp_ready;

    // 组合连接 req_ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
    assign req_ready = !rst &&
                       (outstanding_count_q < 2 || rsp_accept);
    // 组合连接 req_accept：保存或选择累加结果，符号与精度由声明及算术表达式决定。
    assign req_accept = req_valid && req_ready;
    // 组合连接 req_address_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
    assign req_address_valid = req_addr >= BASE_ADDR &&
                               req_addr < BASE_ADDR +
                                          (32'd4 << ADDR_WIDTH) &&
                               req_addr[1:0] == 2'b00;

    // 组合连接 response_fifo_pop：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign response_fifo_pop = response_count_q != 0 && rsp_ready;
    // 组合连接 response_fifo_push：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    assign response_fifo_push = read_stage2_valid_q &&
                                !(response_count_q == 0 && rsp_ready);

    dc_realtime_core_tcm_bram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE(INIT_FILE)
    ) tcm_memory (
        .clk,
        .enable(req_accept && req_address_valid),
        .address(req_addr[ADDR_WIDTH+1:2]),
        .write(1'b0),
        .wdata(32'd0),
        .wstrb(4'd0),
        .rdata(bram_rdata)
    );

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            outstanding_count_q <= 2'd0;
            read_stage1_valid_q <= 1'b0;
            read_stage1_error_q <= 1'b0;
            read_stage2_valid_q <= 1'b0;
            read_stage2_error_q <= 1'b0;
            response_read_ptr_q <= 1'b0;
            response_write_ptr_q <= 1'b0;
            response_count_q <= 2'd0;
            // 按 int unsigned index = 0; index < 2; ++index 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
            for (int unsigned index = 0; index < 2; ++index) begin
                response_data_q[index] <= 32'd0;
                response_error_q[index] <= 1'b0;
            end
        end else begin
            // 按 {req_accept, rsp_accept} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case ({req_accept, rsp_accept})
                2'b10: outstanding_count_q <= outstanding_count_q + 2'd1;
                2'b01: outstanding_count_q <= outstanding_count_q - 2'd1;
                default: begin end
            endcase

            read_stage1_valid_q <= req_accept;
            read_stage1_error_q <= req_accept && !req_address_valid;
            read_stage2_valid_q <= read_stage1_valid_q;
            read_stage2_error_q <= read_stage1_error_q;

            // 按 {response_fifo_push, response_fifo_pop} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case ({response_fifo_push, response_fifo_pop})
                2'b10: response_count_q <= response_count_q + 2'd1;
                2'b01: response_count_q <= response_count_q - 2'd1;
                default: begin end
            endcase
            // 条件分支：检查 response_fifo_push。
            if (response_fifo_push) begin
                response_data_q[response_write_ptr_q] <=
                    read_stage2_error_q ? 32'd0 : bram_rdata;
                response_error_q[response_write_ptr_q] <=
                    read_stage2_error_q;
                response_write_ptr_q <= response_write_ptr_q + 1'b1;
            end
            // 条件分支：检查 response_fifo_pop。
            if (response_fifo_pop)
                response_read_ptr_q <= response_read_ptr_q + 1'b1;
        end
    end

`ifdef DC_RT_VERIFICATION
    logic response_held_q;
    logic [32:0] response_held_tuple_q;
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
            response_held_q <= 1'b0;
            response_held_tuple_q <= 33'd0;
        end else begin
            // 条件分支：检查 outstanding_count_q > 2 || response_count_q > 2。
            if (outstanding_count_q > 2 || response_count_q > 2)
                $error("CORE0_ITCM_PIPELINE_CREDIT_RED outstanding=%0d buffered=%0d",
                       outstanding_count_q, response_count_q);
            // 条件分支：检查 response_held_q &&。
            if (response_held_q &&
                {rsp_error, rsp_rdata} !== response_held_tuple_q)
                $error("CORE0_ITCM_PIPELINE_HELD_RESPONSE_RED");
            response_held_q <= rsp_valid && !rsp_ready;
            // 条件分支：检查 rsp_valid。
            if (rsp_valid)
                response_held_tuple_q <= {rsp_error, rsp_rdata};
        end
    end
`endif
endmodule
