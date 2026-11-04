module dc_realtime_core_split_bus #(
    parameter logic [31:0] DTCM_BASE  = 32'h2000_0000,
    parameter logic [31:0] DTCM_BYTES = 32'h0001_0000
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        if_req_valid,
    output logic        if_req_ready,
    input  logic [31:0] if_req_addr,
    output logic        if_rsp_valid,
    input  logic        if_rsp_ready,
    output logic [31:0] if_rsp_rdata,
    output logic        if_rsp_error,

    input  logic        lsu_req_valid,
    output logic        lsu_req_ready,
    input  logic [31:0] lsu_req_addr,
    input  logic        lsu_req_write,
    input  logic [31:0] lsu_req_wdata,
    input  logic [3:0]  lsu_req_wstrb,
    output logic        lsu_rsp_valid,
    input  logic        lsu_rsp_ready,
    output logic [31:0] lsu_rsp_rdata,
    output logic        lsu_rsp_error,

    output logic        tcm_if_req_valid,
    input  logic        tcm_if_req_ready,
    output logic [31:0] tcm_if_req_addr,
    input  logic        tcm_if_rsp_valid,
    output logic        tcm_if_rsp_ready,
    input  logic [31:0] tcm_if_rsp_rdata,
    input  logic        tcm_if_rsp_error,

    output logic        tcm_lsu_req_valid,
    input  logic        tcm_lsu_req_ready,
    output logic [31:0] tcm_lsu_req_addr,
    output logic        tcm_lsu_req_write,
    output logic [31:0] tcm_lsu_req_wdata,
    output logic [3:0]  tcm_lsu_req_wstrb,
    input  logic        tcm_lsu_rsp_valid,
    output logic        tcm_lsu_rsp_ready,
    input  logic [31:0] tcm_lsu_rsp_rdata,
    input  logic        tcm_lsu_rsp_error,

    output logic        bus_req_valid,
    input  logic        bus_req_ready,
    output logic [31:0] bus_req_addr,
    output logic        bus_req_write,
    output logic [31:0] bus_req_wdata,
    output logic [3:0]  bus_req_wstrb,
    output logic        bus_req_is_fetch,
    input  logic        bus_rsp_valid,
    output logic        bus_rsp_ready,
    input  logic [31:0] bus_rsp_rdata,
    input  logic        bus_rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    typedef enum logic [1:0] {
        DATA_OWNER_NONE = 2'd0,
        DATA_OWNER_TCM  = 2'd1,
        DATA_OWNER_MMIO = 2'd2
    } data_owner_e;

    // PDS ADS 不支持以模块内 typedef enum 作为变量类型；枚举常量保留，
    // 状态信号改用等宽 logic，比较与 case 语义不变。
    logic [1:0] data_owner_q;
    logic lsu_select_dtcm;
    logic data_request_accept;
    logic data_response_accept;
    logic data_slot_available;
    assign data_slot_available = data_owner_q == DATA_OWNER_NONE || data_response_accept;

    assign lsu_select_dtcm = lsu_req_addr >= DTCM_BASE &&
                             lsu_req_addr < DTCM_BASE + DTCM_BYTES;

    // V13: payload travels independently of VALID. Side effects remain
    // gated by request acceptance in the destination. This removes wide
    // payload muxes driven by global issue/owner control.
    assign tcm_if_req_valid = !rst && if_req_valid;
    assign tcm_if_req_addr = if_req_addr;
    assign if_req_ready = tcm_if_req_valid && tcm_if_req_ready;
    assign if_rsp_valid = !rst && tcm_if_rsp_valid;
    assign if_rsp_rdata = tcm_if_rsp_rdata;
    assign if_rsp_error = if_rsp_valid && tcm_if_rsp_error;
    assign tcm_if_rsp_ready = !rst && if_rsp_ready;

    assign tcm_lsu_req_valid = !rst && data_slot_available &&
                               lsu_req_valid && lsu_select_dtcm;
    assign tcm_lsu_req_addr = lsu_req_addr;
    assign tcm_lsu_req_write = tcm_lsu_req_valid && lsu_req_write;
    assign tcm_lsu_req_wdata = lsu_req_wdata;
    assign tcm_lsu_req_wstrb = lsu_req_wstrb;

    assign bus_req_valid = !rst && data_slot_available &&
                           lsu_req_valid && !lsu_select_dtcm;
    assign bus_req_addr = lsu_req_addr;
    assign bus_req_write = bus_req_valid && lsu_req_write;
    assign bus_req_wdata = lsu_req_wdata;
    assign bus_req_wstrb = lsu_req_wstrb;
    assign bus_req_is_fetch = 1'b0;

    always_comb begin
        lsu_req_ready = 1'b0;
        lsu_rsp_valid = 1'b0;
        lsu_rsp_rdata = 32'd0;
        lsu_rsp_error = 1'b0;
        tcm_lsu_rsp_ready = 1'b0;
        bus_rsp_ready = 1'b0;

        if (data_slot_available) begin
            if (tcm_lsu_req_valid)
                lsu_req_ready = tcm_lsu_req_ready;
            else if (bus_req_valid)
                lsu_req_ready = bus_req_ready;
        end
        if (data_owner_q == DATA_OWNER_TCM) begin
            lsu_rsp_valid = tcm_lsu_rsp_valid;
            lsu_rsp_rdata = tcm_lsu_rsp_rdata;
            lsu_rsp_error = tcm_lsu_rsp_error;
            tcm_lsu_rsp_ready = lsu_rsp_ready;
        end else if (data_owner_q == DATA_OWNER_MMIO) begin
            lsu_rsp_valid = bus_rsp_valid;
            lsu_rsp_rdata = bus_rsp_rdata;
            lsu_rsp_error = bus_rsp_error;
            bus_rsp_ready = lsu_rsp_ready;
        end
    end

    assign data_request_accept = lsu_req_valid && lsu_req_ready;
    assign data_response_accept = lsu_rsp_valid && lsu_rsp_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            data_owner_q <= DATA_OWNER_NONE;
        end else begin
            if (data_response_accept)
                data_owner_q <= DATA_OWNER_NONE;
            if (data_request_accept)
                data_owner_q <= lsu_select_dtcm ? DATA_OWNER_TCM : DATA_OWNER_MMIO;
        end
    end

`ifdef DC_RT_VERIFICATION
    logic if_held_q;
    logic [31:0] if_held_addr_q;
    logic data_held_q;
    logic [68:0] data_held_tuple_q;
    always_ff @(posedge clk) begin
        if (rst) begin
            if_held_q <= 1'b0;
            if_held_addr_q <= 32'd0;
            data_held_q <= 1'b0;
            data_held_tuple_q <= 69'd0;
        end else begin
            if (if_held_q && tcm_if_req_valid &&
                tcm_if_req_addr != if_held_addr_q)
                $error("CORE0_SPLIT_TCM_FETCH_HOLD_RED");
            if_held_q <= tcm_if_req_valid && !tcm_if_req_ready;
            if (tcm_if_req_valid)
                if_held_addr_q <= tcm_if_req_addr;

            if (data_held_q &&
                {tcm_lsu_req_addr, tcm_lsu_req_write,
                 tcm_lsu_req_wdata, tcm_lsu_req_wstrb} != data_held_tuple_q)
                $error("CORE0_SPLIT_TCM_DATA_HOLD_RED");
            data_held_q <= tcm_lsu_req_valid && !tcm_lsu_req_ready;
            if (tcm_lsu_req_valid)
                data_held_tuple_q <= {tcm_lsu_req_addr, tcm_lsu_req_write,
                                      tcm_lsu_req_wdata, tcm_lsu_req_wstrb};

            if (tcm_lsu_rsp_valid && data_owner_q != DATA_OWNER_TCM)
                $error("CORE0_SPLIT_TCM_DATA_OWNER_RED");
            if (bus_rsp_valid && data_owner_q != DATA_OWNER_MMIO)
                $error("CORE0_SPLIT_TCM_MMIO_OWNER_RED");
        end
    end
`endif
endmodule
