// V3 timing: registered external requests; original TCM paths stay direct.
// V15 native core, original V15 TCM, and inherited two-way caches.
// New fast instruction router preserves the no-stall ITCM acceptance cycle.
module soc_cpu_tile_v15 #(
    parameter int unsigned BTB_INDEX_BITS=9,
    parameter bit REGISTERED_AGU=1, LOAD_BRANCH_BYPASS=1, MDU_WB_ONLY=1,
    parameter logic [31:0] HART_ID            = 32'd0,
    parameter logic [31:0] RESET_PC           = 32'h1000_0000,
    parameter logic [31:0] FAST_VECTOR_BASE   = RESET_PC + 32'h0000_0100,
    parameter logic [31:0] FAST_VECTOR_STRIDE = 32'd4,
    parameter logic        BPU_ENABLE         = 1'b1,
    parameter logic        NPU_ENABLE         = 1'b1,
    parameter int unsigned ITCM_ADDR_WIDTH    = 14,
    parameter int unsigned DTCM_ADDR_WIDTH    = 14,
    parameter int unsigned DTCM_READ_LATENCY = 1,
    parameter ITCM_INIT_FILE     = "",
    parameter DTCM_INIT_FILE     = "",
    parameter integer      CACHE_CAPACITY_BYTES=16384,
    parameter logic [31:0] DDR_BASE=32'h80000000, CACHE_BASE=32'h84000000,
    parameter logic [32:0] DDR_BYTES=33'h010000000, CACHE_BYTES=33'h004000000,
    parameter bit          EARLY_STORE_ACK    = 1'b1
) (
    input  logic        clk,
    input  logic        rst,

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
    input  logic        npu_rsp_error,
    input  logic        npu_irq,

    output logic [1:0] cache_mem_req_valid,cache_mem_req_write,
    input logic [1:0] cache_mem_req_ready,
    output logic [1:0][31:0] cache_mem_req_addr,
    output logic [1:0][127:0] cache_mem_req_wdata,
    output logic [1:0][15:0] cache_mem_req_wstrb,
    output logic [1:0][3:0] cache_mem_req_tag,
    input logic [1:0] cache_mem_rsp_valid,cache_mem_rsp_write,cache_mem_rsp_error,
    output logic [1:0] cache_mem_rsp_ready,
    input logic [1:0][127:0] cache_mem_rsp_rdata,
    input logic [1:0][3:0] cache_mem_rsp_tag,
    output logic cache_protocol_fault,
    output logic [1:0][31:0] cache_hit_count,cache_miss_count,cache_bypass_count,
    output logic [31:0] maintenance_count,
    input  logic        irq_nmi_fault,
    input  logic        irq_fast_adc,
    input  logic        irq_fast_pwm,
    input  logic        irq_qei,
    input  logic        irq_timer,
    input  logic        irq_ipc,
    input  logic [7:0]  irq_platform,

    output logic        core_sleeping,
    output logic        retire_valid_diag,
    output logic [31:0] retire_pc_diag,
    output logic        irq_accept_diag,
    output logic [31:0] irq_vector_pc_diag,
    output logic        handler_entry_diag,
    output logic        fatal_state_diag
`ifdef DC_RT_VERIFICATION
    ,
    output logic [31:0] trace_retire_instr,
    output logic [4:0]  trace_retire_rd,
    output logic        trace_retire_rd_write,
    output logic [31:0] trace_retire_value,
    output logic [31:0] trace_retire_next_pc
`endif
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam int DC_RT_NPU_PLATFORM_IRQ_INDEX=0;


    logic [1:0] t_req_valid,t_req_ready,t_rsp_valid,t_rsp_ready,t_rsp_error;
    logic [31:0] t_req_addr;
    logic [1:0][31:0] t_rsp_rdata;
    logic stop_new,if_drained;
    logic [2:0] unused_if_outstanding;
    logic [1:0] inv_valid,inv_ready,inv_done,cache_initialized,cache_fault;
    logic x_req_valid,x_req_ready,x_req_write,x_req_fetch,x_rsp_valid,x_rsp_ready,x_rsp_error;
    logic [31:0] x_req_addr,x_req_wdata,x_rsp_rdata;logic [3:0] x_req_wstrb;
    logic d_req_valid,d_req_ready,d_req_write,d_req_fetch,d_rsp_valid,d_rsp_ready,d_rsp_error;
    logic [31:0] d_req_addr,d_req_wdata,d_rsp_rdata;logic [3:0] d_req_wstrb;
    assign cache_protocol_fault=|cache_fault;

    logic core_req_valid;
    logic core_req_ready;
    logic [31:0] core_req_addr;
    logic core_req_write;
    logic [31:0] core_req_wdata;
    logic [3:0] core_req_wstrb;
    logic core_req_is_fetch;
    logic core_rsp_valid;
    logic core_rsp_ready;
    logic [31:0] core_rsp_rdata;
    logic core_rsp_error;
    logic router_rsp_valid,router_rsp_ready,router_rsp_error;
    logic [31:0] router_rsp_rdata;
    logic core_rsp_hold_q,core_rsp_error_q;
    logic [31:0] core_rsp_rdata_q;

    logic itcm_req_valid;
    logic itcm_req_ready;
    logic [31:0] itcm_req_addr;
    logic itcm_rsp_valid;
    logic itcm_rsp_ready;
    logic [31:0] itcm_rsp_rdata;
    logic itcm_rsp_error;
    logic dtcm_req_valid;
    logic dtcm_req_ready;
    logic [31:0] dtcm_req_addr;
    logic dtcm_req_write;
    logic [31:0] dtcm_req_wdata;
    logic [3:0] dtcm_req_wstrb;
    logic dtcm_rsp_valid;
    logic dtcm_rsp_ready;
    logic [31:0] dtcm_rsp_rdata;
    logic dtcm_rsp_error;
    logic [7:0] irq_platform_to_core;
    logic npu_irq_known_high;



    always_comb begin
        npu_irq_known_high = npu_irq === 1'b1;
        irq_platform_to_core = irq_platform;
        irq_platform_to_core[DC_RT_NPU_PLATFORM_IRQ_INDEX] =
            irq_platform[DC_RT_NPU_PLATFORM_IRQ_INDEX] | npu_irq_known_high;
    end

    logic if_req_valid;
    logic if_req_ready;
    logic [31:0] if_req_addr;
    logic if_rsp_valid;
    logic if_rsp_ready;
    logic [31:0] if_rsp_rdata;
    logic if_rsp_error;
    logic lsu_req_valid;
    logic lsu_req_ready;
    logic [31:0] lsu_req_addr;
    logic lsu_req_write;
    logic [31:0] lsu_req_wdata;
    logic [3:0] lsu_req_wstrb;
    logic lsu_rsp_valid;
    logic lsu_rsp_ready;
    logic [31:0] lsu_rsp_rdata;
    logic lsu_rsp_error;
    dc_realtime_core_split_bus #(.DTCM_BYTES(32'd4 << DTCM_ADDR_WIDTH)) bus_adapter (
        .clk, .rst,
        .if_req_valid, .if_req_ready, .if_req_addr, .if_rsp_valid, .if_rsp_ready, .if_rsp_rdata, .if_rsp_error, .lsu_req_valid, .lsu_req_ready, .lsu_req_addr, .lsu_req_write, .lsu_req_wdata, .lsu_req_wstrb, .lsu_rsp_valid, .lsu_rsp_ready, .lsu_rsp_rdata, .lsu_rsp_error,
        .tcm_if_req_valid(itcm_req_valid), .tcm_if_req_ready(itcm_req_ready), .tcm_if_req_addr(itcm_req_addr),
        .tcm_if_rsp_valid(itcm_rsp_valid), .tcm_if_rsp_ready(itcm_rsp_ready), .tcm_if_rsp_rdata(itcm_rsp_rdata), .tcm_if_rsp_error(itcm_rsp_error),
        .tcm_lsu_req_valid(dtcm_req_valid), .tcm_lsu_req_ready(dtcm_req_ready), .tcm_lsu_req_addr(dtcm_req_addr),
        .tcm_lsu_req_write(dtcm_req_write), .tcm_lsu_req_wdata(dtcm_req_wdata), .tcm_lsu_req_wstrb(dtcm_req_wstrb),
        .tcm_lsu_rsp_valid(dtcm_rsp_valid), .tcm_lsu_rsp_ready(dtcm_rsp_ready), .tcm_lsu_rsp_rdata(dtcm_rsp_rdata), .tcm_lsu_rsp_error(dtcm_rsp_error),
        .bus_req_valid(core_req_valid), .bus_req_ready(core_req_ready), .bus_req_addr(core_req_addr),
        .bus_req_write(core_req_write), .bus_req_wdata(core_req_wdata), .bus_req_wstrb(core_req_wstrb), .bus_req_is_fetch(core_req_is_fetch),
        .bus_rsp_valid(core_rsp_valid), .bus_rsp_ready(core_rsp_ready), .bus_rsp_rdata(core_rsp_rdata), .bus_rsp_error(core_rsp_error)
    );

    dc_realtime_cpu_core #(
        .REGISTERED_AGU(REGISTERED_AGU),
        .LOAD_BRANCH_BYPASS(LOAD_BRANCH_BYPASS),
        .BTB_INDEX_BITS(BTB_INDEX_BITS),
        .HART_ID(HART_ID),
        .RESET_PC(RESET_PC),
        .FAST_VECTOR_BASE(FAST_VECTOR_BASE),
        .FAST_VECTOR_STRIDE(FAST_VECTOR_STRIDE),
        .BPU_ENABLE(BPU_ENABLE),
        .MDU_WB_ONLY(MDU_WB_ONLY)
    ) core (
        .clk, .rst,
        .if_req_valid, .if_req_ready, .if_req_addr, .if_rsp_valid, .if_rsp_ready, .if_rsp_rdata, .if_rsp_error, .lsu_req_valid, .lsu_req_ready, .lsu_req_addr, .lsu_req_write, .lsu_req_wdata, .lsu_req_wstrb, .lsu_rsp_valid, .lsu_rsp_ready, .lsu_rsp_rdata, .lsu_rsp_error,
        .irq_nmi_fault, .irq_fast_adc, .irq_fast_pwm, .irq_qei, .irq_timer,
        .irq_ipc, .irq_platform(irq_platform_to_core), .core_sleeping,
        .retire_valid_diag, .retire_pc_diag, .irq_accept_diag,
        .irq_vector_pc_diag, .handler_entry_diag, .fatal_state_diag
`ifdef DC_RT_VERIFICATION
        , .trace_retire_instr, .trace_retire_rd, .trace_retire_rd_write,
        .trace_retire_value, .trace_retire_next_pc
`endif
    );

    dc_realtime_core_itcm_channel #(
        .ADDR_WIDTH(ITCM_ADDR_WIDTH),
        .BASE_ADDR(32'h1000_0000),
        .INIT_FILE(ITCM_INIT_FILE)
    ) itcm_channel (
        .clk, .rst,
        .req_valid(t_req_valid[0]), .req_ready(t_req_ready[0]),
        .req_addr(t_req_addr),
        .rsp_valid(t_rsp_valid[0]), .rsp_ready(t_rsp_ready[0]),
        .rsp_rdata(t_rsp_rdata[0]), .rsp_error(t_rsp_error[0])
    );

    dc_realtime_core_tcm_channel #(
        .ADDR_WIDTH(DTCM_ADDR_WIDTH),
        .BASE_ADDR(32'h2000_0000),
        .INIT_FILE(DTCM_INIT_FILE),
        .READ_LATENCY(DTCM_READ_LATENCY),
        .EARLY_STORE_ACK(EARLY_STORE_ACK),
        .READ_ONLY(1'b0)
    ) dtcm_channel (
        .clk, .rst,
        .req_valid(dtcm_req_valid), .req_ready(dtcm_req_ready),
        .req_addr(dtcm_req_addr), .req_write(dtcm_req_write),
        .req_wdata(dtcm_req_wdata), .req_wstrb(dtcm_req_wstrb),
        .rsp_valid(dtcm_rsp_valid), .rsp_ready(dtcm_rsp_ready),
        .rsp_rdata(dtcm_rsp_rdata), .rsp_error(dtcm_rsp_error)
    );

    // The split bus owns the transaction until its response. Capture the
    // external request before NPU/MMIO/cache address decoding so that CPU AGU
    // logic does not feed downstream decoders and cache enables in one cycle.
    // No fall-through: ready depends only on this buffer's occupancy. TCM
    // requests above never enter this buffer. Responses keep their handshake.
    logic ext_req_valid_q;
    logic ext_req_ready;
    logic [31:0] ext_req_addr_q, ext_req_wdata_q;
    logic [3:0] ext_req_wstrb_q;
    logic ext_req_write_q, ext_req_fetch_q;
    assign core_req_ready = !rst && !ext_req_valid_q;
    always_ff @(posedge clk) begin
        if (rst) ext_req_valid_q <= 1'b0;
        else begin
            if (ext_req_valid_q && ext_req_ready)
                ext_req_valid_q <= 1'b0;
            if (core_req_valid && core_req_ready) begin
                ext_req_valid_q <= 1'b1;
                ext_req_addr_q <= core_req_addr;
                ext_req_write_q <= core_req_write;
                ext_req_wdata_q <= core_req_wdata;
                ext_req_wstrb_q <= core_req_wstrb;
                ext_req_fetch_q <= core_req_is_fetch;
            end
        end
    end
    // The external response router may combine NPU, camera, cache and reset
    // state. Capture its one-owner reply before the CPU completion/redirect
    // control, while preserving ready/valid backpressure and exact ownership.
    assign router_rsp_ready = !rst && !core_rsp_hold_q;
    assign core_rsp_valid = core_rsp_hold_q;
    assign core_rsp_rdata = core_rsp_rdata_q;
    assign core_rsp_error = core_rsp_error_q;
    always_ff @(posedge clk) begin
        if (rst) begin
            core_rsp_hold_q <= 1'b0;
            core_rsp_rdata_q <= 32'd0;
            core_rsp_error_q <= 1'b0;
        end else begin
            if (router_rsp_valid && router_rsp_ready) begin
                core_rsp_hold_q <= 1'b1;
                core_rsp_rdata_q <= router_rsp_rdata;
                core_rsp_error_q <= router_rsp_error;
            end else if (core_rsp_valid && core_rsp_ready)
                core_rsp_hold_q <= 1'b0;
        end
    end
    dc_realtime_core_npu_router #(.NPU_ENABLE(NPU_ENABLE)) router (
        .clk, .rst,
        .core_req_valid(ext_req_valid_q && !rst), .core_req_ready(ext_req_ready),
        .core_req_addr(ext_req_addr_q), .core_req_write(ext_req_write_q),
        .core_req_wdata(ext_req_wdata_q), .core_req_wstrb(ext_req_wstrb_q),
        .core_req_is_fetch(ext_req_fetch_q),
        .core_rsp_valid(router_rsp_valid), .core_rsp_ready(router_rsp_ready),
        .core_rsp_rdata(router_rsp_rdata), .core_rsp_error(router_rsp_error),
        .system_req_valid(x_req_valid), .system_req_ready(x_req_ready), .system_req_addr(x_req_addr),
        .system_req_write(x_req_write), .system_req_wdata(x_req_wdata), .system_req_wstrb(x_req_wstrb),
        .system_req_is_fetch(x_req_fetch), .system_rsp_valid(x_rsp_valid), .system_rsp_ready(x_rsp_ready),
        .system_rsp_rdata(x_rsp_rdata), .system_rsp_error(x_rsp_error),
        .npu_req_valid, .npu_req_ready, .npu_req_addr, .npu_req_write,
        .npu_req_wdata, .npu_req_wstrb, .npu_rsp_valid, .npu_rsp_ready,
        .npu_rsp_rdata, .npu_rsp_error
    );

    soc_ordered_if_router #(.ITCM_BYTES(33'(4*(1<<ITCM_ADDR_WIDTH)))) fetch_router(
      .clk,.rst,.stop_new,.req_valid(itcm_req_valid),.req_ready(itcm_req_ready),.req_addr(itcm_req_addr),
      .rsp_valid(itcm_rsp_valid),.rsp_ready(itcm_rsp_ready),.rsp_rdata(itcm_rsp_rdata),.rsp_error(itcm_rsp_error),
      .target_req_valid(t_req_valid),.target_req_ready(t_req_ready),.target_req_addr(t_req_addr),
      .target_rsp_valid(t_rsp_valid),.target_rsp_ready(t_rsp_ready),.target_rsp_rdata(t_rsp_rdata),.target_rsp_error(t_rsp_error),
      .drained(if_drained),.outstanding(unused_if_outstanding));
    pg_cached_data_router #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) data_router(
      .clk,.rst,.req_valid(x_req_valid),.req_ready(x_req_ready),.req_addr(x_req_addr),.req_write(x_req_write),
      .req_is_fetch(x_req_fetch),.req_wdata(x_req_wdata),.req_wstrb(x_req_wstrb),
      .rsp_valid(x_rsp_valid),.rsp_ready(x_rsp_ready),.rsp_rdata(x_rsp_rdata),.rsp_error(x_rsp_error),
      .d_req_valid,.d_req_ready,.d_req_addr,.d_req_write,.d_req_fetch,.d_req_wdata,.d_req_wstrb,
      .d_rsp_valid,.d_rsp_ready,.d_rsp_rdata,.d_rsp_error,
      .p_req_valid(system_req_valid),.p_req_ready(system_req_ready),.p_req_addr(system_req_addr),
      .p_req_write(system_req_write),.p_req_is_fetch(system_req_is_fetch),.p_req_wdata(system_req_wdata),.p_req_wstrb(system_req_wstrb),
      .p_rsp_valid(system_rsp_valid),.p_rsp_ready(system_rsp_ready),.p_rsp_rdata(system_rsp_rdata),.p_rsp_error(system_rsp_error),
      .stop_new,.if_drained,.invalidate_valid(inv_valid),.invalidate_ready(inv_ready),.invalidate_done(inv_done),.initialized(cache_initialized),
      .hit_count(cache_hit_count),.miss_count(cache_miss_count),.bypass_count(cache_bypass_count),.maintenance_count);
    logic [1:0] c_req_ready,c_rsp_valid,c_rsp_error;
    logic [1:0][31:0] c_rsp_rdata;
    assign {d_req_ready,t_req_ready[1]}=c_req_ready;
    assign {d_rsp_valid,t_rsp_valid[1]}=c_rsp_valid;
    assign {d_rsp_error,t_rsp_error[1]}=c_rsp_error;
    assign d_rsp_rdata=c_rsp_rdata[1];assign t_rsp_rdata[1]=c_rsp_rdata[0];
    for(genvar g=0;g<2;g++)begin:cache
      pg_cache2way #(.CAPACITY_BYTES(CACHE_CAPACITY_BYTES),.READ_ONLY(g==0),
        .DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES),.CACHE_BASE(CACHE_BASE),.CACHE_BYTES(CACHE_BYTES)) u_cache(
        .clk,.rst,.req_valid(g==0?t_req_valid[1]:d_req_valid),.req_ready(c_req_ready[g]),
        .req_write(g==0?1'b0:d_req_write),.req_fetch(g==0?1'b1:d_req_fetch),
        .req_addr(g==0?t_req_addr:d_req_addr),.req_wdata(g==0?32'b0:d_req_wdata),.req_wstrb(g==0?4'b0:d_req_wstrb),
        .rsp_valid(c_rsp_valid[g]),.rsp_error(c_rsp_error[g]),.rsp_rdata(c_rsp_rdata[g]),.rsp_ready(g==0?t_rsp_ready[1]:d_rsp_ready),
        .invalidate_valid(inv_valid[g]),.invalidate_ready(inv_ready[g]),.invalidate_done(inv_done[g]),
        .initialized(cache_initialized[g]),.protocol_fault(cache_fault[g]),
        .hit_count(cache_hit_count[g]),.miss_count(cache_miss_count[g]),.bypass_count(cache_bypass_count[g]),
        .mem_req_valid(cache_mem_req_valid[g]),.mem_req_ready(cache_mem_req_ready[g]),.mem_req_write(cache_mem_req_write[g]),
        .mem_req_addr(cache_mem_req_addr[g]),.mem_req_wdata(cache_mem_req_wdata[g]),.mem_req_wstrb(cache_mem_req_wstrb[g]),.mem_req_tag(cache_mem_req_tag[g]),
        .mem_rsp_valid(cache_mem_rsp_valid[g]),.mem_rsp_ready(cache_mem_rsp_ready[g]),.mem_rsp_write(cache_mem_rsp_write[g]),
        .mem_rsp_rdata(cache_mem_rsp_rdata[g]),.mem_rsp_tag(cache_mem_rsp_tag[g]),.mem_rsp_error(cache_mem_rsp_error[g]));
    end

endmodule
