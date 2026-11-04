module dc_realtime_core_npu_router #(
    parameter logic NPU_ENABLE = 1'b1
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        core_req_valid,
    output logic        core_req_ready,
    input  logic [31:0] core_req_addr,
    input  logic        core_req_write,
    input  logic [31:0] core_req_wdata,
    input  logic [3:0]  core_req_wstrb,
    input  logic        core_req_is_fetch,
    output logic        core_rsp_valid,
    input  logic        core_rsp_ready,
    output logic [31:0] core_rsp_rdata,
    output logic        core_rsp_error,

    output logic        system_req_valid,
    input  logic        system_req_ready,
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

    localparam logic [31:0] DC_RT_NPU_BASE = 32'h7000_0000;
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

    always_comb begin
        core_rsp_valid = 1'b0;
        core_rsp_rdata = 32'd0;
        core_rsp_error = 1'b0;
        system_rsp_ready = 1'b0;
        npu_rsp_ready = 1'b0;
        case (owner_q)
            OWNER_SYSTEM: begin
                core_rsp_valid = system_rsp_valid;
                core_rsp_rdata = system_rsp_rdata;
                core_rsp_error = system_rsp_error;
                system_rsp_ready = core_rsp_ready;
            end
            OWNER_NPU: begin
                core_rsp_valid = npu_rsp_valid;
                core_rsp_rdata = npu_rsp_rdata;
                core_rsp_error = npu_rsp_error;
                npu_rsp_ready = core_rsp_ready;
            end
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

    always_ff @(posedge clk) begin
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
    always_ff @(posedge clk) begin
        if (!rst) begin
            if (system_rsp_valid && owner_q != OWNER_SYSTEM && system_rsp_ready)
                $error("CORE0_NPU_ROUTER_WRONG_SYSTEM_RESPONSE");
            if (npu_rsp_valid && owner_q != OWNER_NPU && npu_rsp_ready)
                $error("CORE0_NPU_ROUTER_WRONG_NPU_RESPONSE");
            if (owner_q != OWNER_NONE && (system_req_valid || npu_req_valid))
                $error("CORE0_NPU_ROUTER_SECOND_OUTSTANDING");
        end
    end
`endif
endmodule
