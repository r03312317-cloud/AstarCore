// 架构导读：dc_realtime_core_npu_router。
// 区分 NPU 与其他系统访问，维护 CPU 请求的响应路径。
module dc_realtime_core_npu_router #(
    // 静态配置：parameter logic NPU_ENABLE = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic NPU_ENABLE = 1'b1
) (
    // 接口声明：input logic clk。
    // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
    input  logic        clk,
    // 接口声明：input logic rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input  logic        rst,

    // 接口声明：input logic core_req_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic        core_req_valid,
    // 接口声明：output logic core_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic        core_req_ready,
    // 接口声明：input logic [31:0] core_req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input  logic [31:0] core_req_addr,
    // 接口声明：input logic core_req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic        core_req_write,
    // 接口声明：input logic [31:0] core_req_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input  logic [31:0] core_req_wdata,
    // 接口声明：input logic [3:0] core_req_wstrb。
    // 按字节选择本次写入生效的 lane。
    input  logic [3:0]  core_req_wstrb,
    // 接口声明：input logic core_req_is_fetch。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic        core_req_is_fetch,
    // 接口声明：output logic core_rsp_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic        core_rsp_valid,
    // 接口声明：input logic core_rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic        core_rsp_ready,
    // 接口声明：output logic [31:0] core_rsp_rdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [31:0] core_rsp_rdata,
    // 接口声明：output logic core_rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic        core_rsp_error,

    // 接口声明：output logic system_req_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic        system_req_valid,
    // 接口声明：input logic system_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic        system_req_ready,
    // 接口声明：output logic [31:0] system_req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] system_req_addr,
    output logic        system_req_write,
    output logic [31:0] system_req_wdata,
    output logic [3:0]  system_req_wstrb,
    output logic        system_req_is_fetch,
    input  logic        system_rsp_valid,
    output logic        system_rsp_ready,
    input  logic [31:0] system_rsp_rdata,
    input  logic        system_rsp_error,

    output logic        npu_req_valid,
    input  logic        npu_req_ready,
    output logic [15:0] npu_req_addr,
    output logic        npu_req_write,
    output logic [31:0] npu_req_wdata,
    output logic [3:0]  npu_req_wstrb,
    input  logic        npu_rsp_valid,
    output logic        npu_rsp_ready,
    input  logic [31:0] npu_rsp_rdata,
    input  logic        npu_rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    // 静态配置：localparam logic [31:0] DC_RT_NPU_BASE = 32'h7000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [31:0] DC_RT_NPU_BASE = 32'h7000_0000;
    // 静态配置：localparam logic [31:0] DC_RT_NPU_END = 32'h7001_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam logic [31:0] DC_RT_NPU_END = 32'h7001_0000;

    typedef enum logic [1:0] {
        OWNER_NONE   = 2'd0,
        OWNER_SYSTEM = 2'd1,
        OWNER_NPU    = 2'd2,
        OWNER_ERROR  = 2'd3
    } owner_e;

    // PDS ADS 不支持以模块内 typedef enum 作为变量类型；枚举常量保留，
    // 状态信号改用等宽 logic，比较与 case 语义不变。
    logic [1:0] owner_q;
    logic npu_window_hit;
    logic select_npu;
    logic select_error;
    logic request_accept;
    logic response_accept;

    assign npu_window_hit = core_req_addr >= DC_RT_NPU_BASE &&
                            core_req_addr < DC_RT_NPU_END;
    assign select_npu = npu_window_hit && !core_req_is_fetch && NPU_ENABLE;
    assign select_error = npu_window_hit && (core_req_is_fetch || !NPU_ENABLE);

    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        system_req_valid = 1'b0;
        system_req_addr = core_req_addr;
        system_req_write = core_req_write;
        system_req_wdata = core_req_wdata;
        system_req_wstrb = core_req_wstrb;
        system_req_is_fetch = core_req_is_fetch;
        npu_req_valid = 1'b0;
        npu_req_addr = core_req_addr[15:0];
        npu_req_write = core_req_write;
        npu_req_wdata = core_req_wdata;
        npu_req_wstrb = core_req_wstrb;
        core_req_ready = 1'b0;

        if (owner_q == OWNER_NONE) begin
            if (select_npu) begin
                npu_req_valid = core_req_valid;
                core_req_ready = npu_req_ready;
            end else if (select_error) begin
                core_req_ready = 1'b1;
            end else begin
                system_req_valid = core_req_valid;
                core_req_ready = system_req_ready;
            end
        end
    end

    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        core_rsp_valid = 1'b0;
        core_rsp_rdata = 32'd0;
        core_rsp_error = 1'b0;
        system_rsp_ready = 1'b0;
        npu_rsp_ready = 1'b0;
        // 按 owner_q 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
        case (owner_q)
            // 状态/选择分支 OWNER_SYSTEM：本分支规定该编码下的寄存器更新和下一步动作。
            OWNER_SYSTEM: begin
                core_rsp_valid = system_rsp_valid;
                core_rsp_rdata = system_rsp_rdata;
                core_rsp_error = system_rsp_error;
                system_rsp_ready = core_rsp_ready;
            end
            // 状态/选择分支 OWNER_NPU：本分支规定该编码下的寄存器更新和下一步动作。
            OWNER_NPU: begin
                core_rsp_valid = npu_rsp_valid;
                core_rsp_rdata = npu_rsp_rdata;
                core_rsp_error = npu_rsp_error;
                npu_rsp_ready = core_rsp_ready;
            end
            // 状态/选择分支 OWNER_ERROR：本分支规定该编码下的寄存器更新和下一步动作。
            OWNER_ERROR: begin
                core_rsp_valid = 1'b1;
                core_rsp_rdata = 32'd0;
                core_rsp_error = 1'b1;
            end
            default: begin
            end
        endcase
    end

    assign request_accept = core_req_valid && core_req_ready;
    assign response_accept = core_rsp_valid && core_rsp_ready;

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
                if (select_npu)
                    owner_q <= OWNER_NPU;
                else if (select_error)
                    owner_q <= OWNER_ERROR;
                else
                    owner_q <= OWNER_SYSTEM;
            end
        end
    end

`ifdef DC_RT_VERIFICATION
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：!rst；分支方向由信号极性与取反表达式决定。
        if (!rst) begin
            // 握手/背压判断：system_rsp_valid && owner_q != OWNER_SYSTEM && system_rsp_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if (system_rsp_valid && owner_q != OWNER_SYSTEM && system_rsp_ready)
                $error("CORE0_NPU_ROUTER_WRONG_SYSTEM_RESPONSE");
            // 握手/背压判断：npu_rsp_valid && owner_q != OWNER_NPU && npu_rsp_ready。
            // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
            if (npu_rsp_valid && owner_q != OWNER_NPU && npu_rsp_ready)
                $error("CORE0_NPU_ROUTER_WRONG_NPU_RESPONSE");
            if (owner_q != OWNER_NONE && (system_req_valid || npu_req_valid))
                $error("CORE0_NPU_ROUTER_SECOND_OUTSTANDING");
        end
    end
`endif
endmodule
