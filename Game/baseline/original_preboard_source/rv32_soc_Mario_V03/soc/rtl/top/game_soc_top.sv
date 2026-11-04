// ---------------------------------------------------------------------------
// game_soc_top -- rv32_soc_Game SoC.
//
// Built from the verified rv32_soc mainline with the AI/vision datapath
// removed.  What stays is the minimum closed loop a game needs:
//
//   * RV32 H5I8 dual-issue out-of-order RISC-V + initialized code/data SRAM
//   * RV32 16 KiB I-cache / 8 KiB two-way D-cache and a non-cacheable DDR path
//   * one DDR user port (native 128-bit -> AXI128 burst bridge)
//   * HDMI scan-out with its own AXI read master (reused unchanged)
//   * CP13 UART / timer / GPIO, game button controller, game video controller
//
// Removed relative to mainline: NPU, camera capture, AI DMA engines
// (Requant / Window / Concat / Pool), replay and video statistics, YOLO stack.
//
// Clock domains: cpu_clk (100 MHz), mem_clk (DDR user, 93.75 MHz) and
// pix_clk (HDMI pixel clock).  Every cross-domain path uses a mainline CDC
// primitive; the CPU never touches DDR or the pixel domain directly.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module game_soc_top #(
    parameter integer CPU_CLOCK_HZ = 100_000_000,
    parameter integer CACHE_CAPACITY_BYTES = 16384,
    parameter ITCM_INIT_FILE = "",
    parameter DTCM_INIT_FILE = "",
    parameter logic [31:0] DDR_BASE = 32'h8000_0000,
    parameter logic [32:0] DDR_BYTES = 33'h0_1000_0000,
    parameter logic [31:0] CACHE_BASE = 32'h8400_0000,
    parameter logic [32:0] CACHE_BYTES = 33'h0_0400_0000,
    parameter logic [31:0] FB0_BASE = 32'h8200_0000,
    parameter logic [31:0] FB1_BASE = 32'h8210_0000
) (
    input  logic cpu_clk,
    input  logic mem_clk,
    input  logic pix_clk,
    input  logic arst,
    input  logic mem_ready,

    input  logic [7:0] pads_n,
    input  logic       key_n,
    input  logic       uart_rx,
    output logic       uart_tx,
    output logic [31:0] gpio_out,

    output logic [23:0] video_rgb,
    output logic        video_de,
    output logic        video_hs,
    output logic        video_vs,

    output logic        pix_rst_o,
    output logic [31:0] dbg_vsync,
    output logic [31:0] dbg_presented,
    output logic [31:0] dbg_active_fb,
    output logic        dbg_cpu_sleeping,
    output logic        dbg_fatal,
    // Slowly toggling level that only moves when the core actually retires an
    // instruction.  A dead core, a core stuck in reset and a core spinning on
    // a hung bus all look identical on the status LEDs otherwise.
    output logic        dbg_cpu_alive,
    // Latches when the core enters its exception handler.  mtvec resets to 0,
    // which is outside the ITCM, so a trap turns into a silent loop with no
    // observable side effect; this is the only way to see it.
    output logic        dbg_cpu_trapped,

    // DDR user-side AXI (128-bit) toward the board-level HMIC adapter
    output logic [3:0]  m_awid,
    output logic [31:0] m_awaddr,
    output logic [7:0]  m_awlen,
    output logic [2:0]  m_awsize,
    output logic [1:0]  m_awburst,
    output logic        m_awvalid,
    input  logic        m_awready,
    output logic [127:0] m_wdata,
    output logic [15:0]  m_wstrb,
    output logic        m_wlast,
    output logic        m_wvalid,
    input  logic        m_wready,
    input  logic [3:0]  m_bid,
    input  logic [1:0]  m_bresp,
    input  logic        m_bvalid,
    output logic        m_bready,
    output logic [3:0]  m_arid,
    output logic [31:0] m_araddr,
    output logic [7:0]  m_arlen,
    output logic [2:0]  m_arsize,
    output logic [1:0]  m_arburst,
    output logic        m_arvalid,
    input  logic        m_arready,
    input  logic [3:0]  m_rid,
    input  logic [127:0] m_rdata,
    input  logic [1:0]   m_rresp,
    input  logic         m_rlast,
    input  logic         m_rvalid,
    output logic         m_rready
);
    timeunit 1ns;
    timeprecision 1ps;

    // ---------------------------------------------------------------- resets
    logic cpu_rst, mem_rst, pix_rst;
    soc_reset_sync u_cpu_reset(.clk(cpu_clk), .arst, .rst(cpu_rst));
    soc_reset_sync u_mem_reset(.clk(mem_clk), .arst, .rst(mem_rst));
    soc_reset_sync u_pix_reset(.clk(pix_clk), .arst, .rst(pix_rst));
    assign pix_rst_o = pix_rst;

    // ------------------------------------------------------------------ CPU
    logic        s_req_valid, s_req_ready, s_req_write, s_req_fetch;
    logic [31:0] s_req_addr, s_req_wdata;
    logic [3:0]  s_req_wstrb;
    logic        s_rsp_valid, s_rsp_ready, s_rsp_error;
    logic [31:0] s_rsp_rdata;

    logic        n_req_valid, n_req_ready, n_req_write;
    logic [15:0] n_req_addr;
    logic [31:0] n_req_wdata;
    logic [3:0]  n_req_wstrb;
    logic        n_rsp_valid, n_rsp_ready, n_rsp_error;
    logic [31:0] n_rsp_rdata;

    logic [1:0]      c_req_valid, c_req_ready, c_req_write;
    logic [1:0][31:0]  c_req_addr;
    logic [1:0][127:0] c_req_wdata;
    logic [1:0][15:0]  c_req_wstrb;
    logic [1:0][3:0]   c_req_tag;
    logic [1:0]      c_rsp_valid, c_rsp_write, c_rsp_error, c_rsp_ready;
    logic [1:0][127:0] c_rsp_rdata;
    logic [1:0][3:0]   c_rsp_tag;

    logic [1:0][31:0] cache_hit_count, cache_miss_count, cache_bypass_count;
    logic [31:0] maintenance_count;
    logic cache_fault, cpu_sleeping, fatal_state;
    logic retire_valid_diag, irq_accept_diag, handler_entry_diag;
    logic [31:0] retire_pc_diag, irq_vector_pc_diag;
    logic irq_fault_cpu;

    logic [1:0] retire_count_diag;
    // RV32 exposes retirement and trap events; no physical WFI sleep output.
    assign cpu_sleeping = 1'b0;
    assign fatal_state = cache_fault;
    rv32_game_cpu_tile #(
        .ITCM_INIT_FILE(ITCM_INIT_FILE), .DTCM_INIT_FILE(DTCM_INIT_FILE),
        .DDR_BASE(DDR_BASE), .DDR_BYTES(DDR_BYTES)
    ) cpu (
        // Explicit common assertion also covers the first simulation clock edge;
        // cpu_rst retains the three-edge synchronous release.
        .clk(cpu_clk), .rst(cpu_rst | arst),
        .system_req_valid(s_req_valid), .system_req_ready(s_req_ready),
        .system_req_addr(s_req_addr), .system_req_write(s_req_write),
        .system_req_wdata(s_req_wdata), .system_req_wstrb(s_req_wstrb),
        .system_req_is_fetch(s_req_fetch),
        .system_rsp_valid(s_rsp_valid), .system_rsp_ready(s_rsp_ready),
        .system_rsp_rdata(s_rsp_rdata), .system_rsp_error(s_rsp_error),
        .cache_mem_req_valid(c_req_valid), .cache_mem_req_ready(c_req_ready),
        .cache_mem_req_write(c_req_write), .cache_mem_req_addr(c_req_addr),
        .cache_mem_req_wdata(c_req_wdata), .cache_mem_req_wstrb(c_req_wstrb),
        .cache_mem_req_tag(c_req_tag),
        .cache_mem_rsp_valid(c_rsp_valid), .cache_mem_rsp_ready(c_rsp_ready),
        .cache_mem_rsp_write(c_rsp_write), .cache_mem_rsp_rdata(c_rsp_rdata),
        .cache_mem_rsp_tag(c_rsp_tag), .cache_mem_rsp_error(c_rsp_error),
        .cache_protocol_fault(cache_fault),
        .irq_fault(irq_fault_cpu),
        .retire_valid_diag(retire_valid_diag), .retire_pc_diag(retire_pc_diag),
        .retire_count_diag(retire_count_diag), .trap_event(handler_entry_diag)
    );
    assign dbg_cpu_sleeping = cpu_sleeping;
    assign dbg_fatal = fatal_state | cache_fault;

    // Bit 24 of the retire counter flips roughly six times a second at 100 MHz:
    // slow enough to watch on an LED, and impossible to reach without the core
    // actually retiring instructions.
    logic [24:0] retire_cnt_q;
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) retire_cnt_q <= '0;
        else if (retire_valid_diag) retire_cnt_q <= retire_cnt_q + {23'd0, retire_count_diag};
    end
    assign dbg_cpu_alive = retire_cnt_q[24];

    logic trap_seen_q;
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) trap_seen_q <= 1'b0;
        else if (handler_entry_diag) trap_seen_q <= 1'b1;
    end
    assign dbg_cpu_trapped = trap_seen_q;



    // ---------------------------------------------------------- CPU MMIO map
    // 0x6000_1000..0x6000_1fff -> board window; everything else -> CP13 block.
    logic        br_req_addr_unused;
    logic [31:0] br_req_addr, br_req_wdata;
    logic        br_req_write, br_req_fetch;
    logic [3:0]  br_req_wstrb;
    logic [1:0]  rq_valid, rq_ready, rq_rsp_valid, rq_rsp_ready, rq_rsp_error;
    logic [1:0][31:0] rq_rsp_rdata;

    soc_board_mmio_router router(
        .clk(cpu_clk), .rst(cpu_rst),
        .req_valid(s_req_valid), .req_ready(s_req_ready),
        .req_addr(s_req_addr), .req_write(s_req_write),
        .req_is_fetch(s_req_fetch), .req_wdata(s_req_wdata), .req_wstrb(s_req_wstrb),
        .rsp_valid(s_rsp_valid), .rsp_ready(s_rsp_ready),
        .rsp_rdata(s_rsp_rdata), .rsp_error(s_rsp_error),
        .m_req_valid(rq_valid), .m_req_ready(rq_ready),
        .m_req_addr(br_req_addr), .m_req_wdata(br_req_wdata),
        .m_req_write(br_req_write), .m_req_is_fetch(br_req_fetch),
        .m_req_wstrb(br_req_wstrb),
        .m_rsp_valid(rq_rsp_valid), .m_rsp_ready(rq_rsp_ready),
        .m_rsp_rdata(rq_rsp_rdata), .m_rsp_error(rq_rsp_error)
    );
    assign br_req_addr_unused = 1'b0;

    // index 0 = CP13 peripherals (0x3000_0000), index 1 = game board window
    logic        p_valid, p_error;
    logic [31:0] p_rdata;
    logic [31:0] dbg_mailbox;
    logic [63:0] timer_gray;
    logic [31:0] gpio_in_word;
    assign gpio_in_word = {24'd0, pads_n};

    pg_cpu_peripherals #(
        .CLOCK_HZ(CPU_CLOCK_HZ),
        .UART_CLKS_PER_BIT((CPU_CLOCK_HZ + 57600) / 115200),
        .UART_RX_DEPTH(16)
    ) peripherals (
        .clk(cpu_clk), .rst(cpu_rst),
        .req_valid(rq_valid[0]), .req_ready(rq_ready[0]),
        .req_addr(br_req_addr), .req_wdata(br_req_wdata), .req_write(br_req_write),
        .req_is_fetch(br_req_fetch), .req_wstrb(br_req_wstrb),
        .rsp_valid(p_valid), .rsp_ready(rq_rsp_ready[0]),
        .rsp_rdata(p_rdata), .rsp_error(p_error),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .gpio_in(gpio_in_word), .gpio_out(gpio_out),
        .diagnostic_mailbox(dbg_mailbox), .timer_gray(timer_gray)
    );
    assign rq_rsp_valid[0] = p_valid;
    assign rq_rsp_rdata[0] = p_rdata;
    assign rq_rsp_error[0] = p_error;

    // ------------------------------------------------------- game board MMIO
    logic        gm_req_valid_any, gm_req_ready_any, gm_rsp_valid_any, gm_rsp_ready_any;
    logic [31:0] gm_req_addr, gm_req_wdata, gm_rsp_rdata_any;
    logic        gm_req_write, gm_rsp_error_any;
    logic [3:0]  gm_req_wstrb;

    logic [1:0]  gm_req_valid, gm_req_ready;
    logic [1:0]  gm_rsp_valid, gm_rsp_ready, gm_rsp_error;
    logic [31:0] gm_rsp_rdata0, gm_rsp_rdata1;

    game_mmio_fabric board_fabric(
        .clk(cpu_clk), .rst(cpu_rst),
        .req_valid(rq_valid[1]), .req_ready(rq_ready[1]),
        .req_addr(br_req_addr), .req_write(br_req_write),
        .req_wdata(br_req_wdata), .req_is_fetch(br_req_fetch), .req_wstrb(br_req_wstrb),
        .rsp_valid(gm_rsp_valid_any), .rsp_ready(rq_rsp_ready[1]),
        .rsp_rdata(gm_rsp_rdata_any), .rsp_error(gm_rsp_error_any),
        .m_req_valid(gm_req_valid), .m_req_ready(gm_req_ready),
        .m_req_addr(gm_req_addr), .m_req_write(gm_req_write),
        .m_req_wdata(gm_req_wdata), .m_req_wstrb(gm_req_wstrb),
        .m_rsp_valid(gm_rsp_valid), .m_rsp_ready(gm_rsp_ready),
        .m_rsp_rdata({gm_rsp_rdata1, gm_rsp_rdata0}),
        .m_rsp_error(gm_rsp_error)
    );
    assign rq_rsp_valid[1] = gm_rsp_valid_any;
    assign rq_rsp_rdata[1] = gm_rsp_rdata_any;
    assign rq_rsp_error[1] = gm_rsp_error_any;

    // PC13-compatible timer / UART live at 0x3000_0000; the button block only
    // needs the eight active-low pads (the onboard key is pad 0 after the
    // board-level merge).
    game_input #(.WIDTH(8), .TICK_DIV(CPU_CLOCK_HZ / 1000)) buttons (
        .clk(cpu_clk), .rst(cpu_rst), .pads_n(pads_n),
        .req_valid(gm_req_valid[0]), .req_ready(gm_req_ready[0]),
        .req_addr(gm_req_addr[15:0]), .req_write(gm_req_write),
        .req_wdata(gm_req_wdata), .req_wstrb(gm_req_wstrb),
        .rsp_valid(gm_rsp_valid[0]), .rsp_ready(gm_rsp_ready[0]),
        .rsp_rdata(gm_rsp_rdata0), .rsp_error(gm_rsp_error[0])
    );

    // ---------------------------------------------------- frame buffer commit
    logic        vm_req_valid, vm_req_ready, vm_rsp_valid, vm_rsp_ready, vm_rsp_error;
    logic [15:0] vm_req_addr;
    logic        vm_req_write;
    logic [31:0] vm_req_wdata;
    logic [3:0]  vm_req_wstrb;
    logic [31:0] vm_rsp_rdata;

    pg_mmio_cdc video_mmio_cdc(
        .src_clk(cpu_clk), .dst_clk(mem_clk), .arst,
        .s_req_valid(gm_req_valid[1]), .s_req_ready(gm_req_ready[1]),
        .s_req_addr(gm_req_addr[15:0]), .s_req_write(gm_req_write),
        .s_req_wdata(gm_req_wdata), .s_req_wstrb(gm_req_wstrb),
        .s_rsp_valid(gm_rsp_valid[1]), .s_rsp_ready(gm_rsp_ready[1]),
        .s_rsp_rdata(gm_rsp_rdata1), .s_rsp_error(gm_rsp_error[1]),
        .m_req_valid(vm_req_valid), .m_req_ready(vm_req_ready),
        .m_req_addr(vm_req_addr), .m_req_write(vm_req_write),
        .m_req_wdata(vm_req_wdata), .m_req_wstrb(vm_req_wstrb),
        .m_rsp_valid(vm_rsp_valid), .m_rsp_ready(vm_rsp_ready),
        .m_rsp_rdata(vm_rsp_rdata), .m_rsp_error(vm_rsp_error)
    );

    // ------------------------------------------------------------- scan-out
    logic        pub_valid, pub_ready;
    logic [31:0] pub_fb, pub_frame, pub_run, pub_xy1, pub_xy2;
    logic [31:0] pub_score, pub_class, pub_count, pub_sequence;
    logic        pending_valid;
    logic [31:0] pending_fb;
    logic        presented_valid;
    logic [31:0] presented_fb, presented_frame, presented_run;
    logic [1:0]  test_pattern;
    logic        event_tc, event_th, event_te, te_good;
    logic [63:0] tc_ticks, th_ticks, te_ticks;
    logic [31:0] tc_frame, tc_run, th_frame, th_run, te_frame, te_run;
    logic [31:0] stat_underflow, stat_mismatch, stat_presented, stat_max_ddr_wait;
    logic [31:0] stat_fifo_high, stat_fifo_low;
    logic [7:0]  video_fault;
    logic [63:0] pix_ticks_unused;
    logic [63:0] cpu_time_zero;

    game_video_ctrl #(.FB0_DEFAULT(FB0_BASE), .FB1_DEFAULT(FB1_BASE)) video_ctrl (
        .ui_clk(mem_clk), .ui_rst(mem_rst), .ddr_ready(mem_ready),
        .req_valid(vm_req_valid), .req_ready(vm_req_ready),
        .req_addr(vm_req_addr), .req_write(vm_req_write),
        .req_wdata(vm_req_wdata), .req_wstrb(vm_req_wstrb),
        .rsp_valid(vm_rsp_valid), .rsp_ready(vm_rsp_ready),
        .rsp_rdata(vm_rsp_rdata), .rsp_error(vm_rsp_error),
        .publish_valid(pub_valid), .publish_ready(pub_ready), .publish_fb(pub_fb),
        .publish_frame(pub_frame), .publish_run(pub_run),
        .publish_xy1(pub_xy1), .publish_xy2(pub_xy2),
        .publish_score(pub_score), .publish_class(pub_class),
        .publish_count(pub_count), .publish_sequence(pub_sequence),
        .vsync_event(event_tc), .presented_valid(presented_valid),
        .presented_fb(presented_fb), .stat_underflow(stat_underflow),
        .stat_presented(stat_presented), .max_ddr_wait(stat_max_ddr_wait),
        .video_fault(video_fault), .test_pattern(test_pattern)
    );

    logic [3:0]  h_arid;
    logic [31:0] h_araddr;
    logic [7:0]  h_arlen;
    logic [2:0]  h_arsize;
    logic [1:0]  h_arburst;
    logic        h_arvalid, h_arready;
    logic [3:0]  h_rid;
    logic [127:0] h_rdata;
    logic [1:0]  h_rresp;
    logic        h_rlast, h_rvalid, h_rready;

    // 720x480p60 carrier, 27 MHz pixel / 135 MHz DDR serial (the profile the
    // camera project verified on a real monitor). The 640x360 framebuffer is
    // mapped 1:1 and centred at (40,60); no scaling.
    soc_hdmi_ddr_scanout #(
        .SINGLE_VIEW(1), .W(640), .H(360), .X_START(40), .Y_START(60),
        .H_ACTIVE(720), .H_FP(16), .H_SYNC(62), .H_BP(60),
        .V_ACTIVE(480), .V_FP(9), .V_SYNC(6), .V_BP(30),
        .HS_NEGATIVE(1), .VS_NEGATIVE(1), .TX_EXTRA_CYCLES(0)
    ) scanout (
        .ui_clk(mem_clk), .ui_rst(mem_rst), .pix_clk(pix_clk), .pix_rst(pix_rst),
        .cpu_time_gray(cpu_time_zero), .test_pattern(test_pattern),
        .publish_valid(pub_valid), .publish_ready(pub_ready), .publish_fb(pub_fb),
        .publish_frame(pub_frame), .publish_run(pub_run),
        .publish_xy1(pub_xy1), .publish_xy2(pub_xy2),
        .publish_score(pub_score), .publish_class(pub_class),
        .publish_count(pub_count), .publish_sequence(pub_sequence),
        .pending_valid(pending_valid), .pending_fb(pending_fb),
        .presented_valid(presented_valid), .presented_fb(presented_fb),
        .presented_frame(presented_frame), .presented_run(presented_run),
        .m_arid(h_arid), .m_araddr(h_araddr), .m_arlen(h_arlen),
        .m_arsize(h_arsize), .m_arburst(h_arburst),
        .m_arvalid(h_arvalid), .m_arready(h_arready),
        .m_rid(h_rid), .m_rdata(h_rdata), .m_rresp(h_rresp),
        .m_rlast(h_rlast), .m_rvalid(h_rvalid), .m_rready(h_rready),
        .video_rgb(video_rgb), .video_de(video_de), .video_hs(video_hs), .video_vs(video_vs),
        .event_tc(event_tc), .event_th(event_th), .event_te(event_te), .te_good(te_good),
        .tc_ticks(tc_ticks), .th_ticks(th_ticks), .te_ticks(te_ticks),
        .tc_pixel_ticks(pix_ticks_unused), .th_pixel_ticks(), .te_pixel_ticks(),
        .tc_frame(tc_frame), .tc_run(tc_run), .th_frame(th_frame), .th_run(th_run),
        .te_frame(te_frame), .te_run(te_run),
        .stat_underflow(stat_underflow), .stat_mismatch(stat_mismatch),
        .stat_presented(stat_presented), .stat_max_ddr_wait(stat_max_ddr_wait),
        .stat_fifo_high(stat_fifo_high), .stat_fifo_low(stat_fifo_low),
        .video_fault(video_fault)
    );
    assign cpu_time_zero = 64'd0;

    logic [31:0] vsync_count_q;
    always_ff @(posedge mem_clk) begin
        if (mem_rst) vsync_count_q <= 32'd0;
        else if (event_tc) vsync_count_q <= vsync_count_q + 32'd1;
    end
    assign dbg_vsync = vsync_count_q;
    assign dbg_presented = stat_presented;
    assign dbg_active_fb = presented_fb;

    // ------------------------------------------------------- DDR user port
    logic [1:0]  mcdc_req_valid, mcdc_req_ready, mcdc_req_write;
    logic [1:0][31:0]  mcdc_req_addr;
    logic [1:0][127:0] mcdc_req_wdata;
    logic [1:0][15:0]  mcdc_req_wstrb;
    logic [1:0][3:0]   mcdc_req_tag;
    logic [1:0]  mcdc_rsp_valid, mcdc_rsp_ready, mcdc_rsp_write, mcdc_rsp_error;
    logic [1:0][127:0] mcdc_rsp_rdata;
    logic [1:0][3:0]   mcdc_rsp_tag;

    for (genvar g = 0; g < 2; g = g + 1) begin : cpu_mem_cdc
        pg_memory_cdc #(.DEPTH(16), .REGISTER_RSP_OUTPUT(1)) channel (
            .src_clk(cpu_clk), .dst_clk(mem_clk), .arst,
            .s_req_valid(c_req_valid[g]), .s_req_ready(c_req_ready[g]),
            .s_req_write(c_req_write[g]), .s_req_addr(c_req_addr[g]),
            .s_req_wdata(c_req_wdata[g]), .s_req_wstrb(c_req_wstrb[g]),
            .s_req_id(c_req_tag[g]),
            .s_rsp_valid(c_rsp_valid[g]), .s_rsp_ready(c_rsp_ready[g]),
            .s_rsp_write(c_rsp_write[g]), .s_rsp_rdata(c_rsp_rdata[g]),
            .s_rsp_id(c_rsp_tag[g]), .s_rsp_error(c_rsp_error[g]),
            .m_req_valid(mcdc_req_valid[g]), .m_req_ready(mcdc_req_ready[g]),
            .m_req_write(mcdc_req_write[g]), .m_req_addr(mcdc_req_addr[g]),
            .m_req_wdata(mcdc_req_wdata[g]), .m_req_wstrb(mcdc_req_wstrb[g]),
            .m_req_id(mcdc_req_tag[g]),
            .m_rsp_valid(mcdc_rsp_valid[g]), .m_rsp_ready(mcdc_rsp_ready[g]),
            .m_rsp_write(mcdc_rsp_write[g]), .m_rsp_rdata(mcdc_rsp_rdata[g]),
            .m_rsp_id(mcdc_rsp_tag[g]), .m_rsp_error(mcdc_rsp_error[g])
        );
    end

    logic [2:0] mx_req_valid, mx_req_ready, mx_req_write;
    logic [2:0][31:0]  mx_req_addr;
    logic [2:0][127:0] mx_req_wdata;
    logic [2:0][15:0]  mx_req_wstrb;
    logic [2:0][3:0]   mx_req_tag;
    logic [2:0] mx_rsp_valid, mx_rsp_ready, mx_rsp_write, mx_rsp_error;
    logic [2:0][127:0] mx_rsp_rdata;
    logic [2:0][3:0]   mx_rsp_tag;
    logic mux_fault;

    assign mx_req_valid[0] = mcdc_req_valid[0] & mem_ready;
    assign mx_req_valid[1] = mcdc_req_valid[1] & mem_ready;
    // Preserve the complete I/D request and response channels across the
    // CDC-to-DDR arbiter boundary.  A valid-only connection sends undefined
    // addresses/data and leaves the CPU waiting forever for the response.
    assign mx_req_write[1:0] = mcdc_req_write;
    assign mx_req_addr[1:0] = mcdc_req_addr;
    assign mx_req_wdata[1:0] = mcdc_req_wdata;
    assign mx_req_wstrb[1:0] = mcdc_req_wstrb;
    assign mx_req_tag[1:0] = mcdc_req_tag;
    assign mcdc_rsp_valid = mx_rsp_valid[1:0];
    assign mcdc_rsp_write = mx_rsp_write[1:0];
    assign mcdc_rsp_error = mx_rsp_error[1:0];
    assign mcdc_rsp_rdata = mx_rsp_rdata[1:0];
    assign mcdc_rsp_tag = mx_rsp_tag[1:0];
    assign mx_rsp_ready[1:0] = mcdc_rsp_ready;
    assign mx_req_valid[2] = 1'b0;
    assign mx_req_write[2] = 1'b0;
    assign mx_req_addr[2] = 32'd0;
    assign mx_req_wdata[2] = 128'd0;
    assign mx_req_wstrb[2] = 16'd0;
    assign mx_req_tag[2] = 4'd0;
    assign mx_rsp_ready[2] = 1'b0;

    logic        nat_req_valid, nat_req_ready, nat_req_write;
    logic [31:0] nat_req_addr;
    logic [127:0] nat_req_wdata;
    logic [15:0] nat_req_wstrb;
    logic [5:0]  nat_req_tag;
    logic        nat_rsp_valid, nat_rsp_ready, nat_rsp_write, nat_rsp_error;
    logic [127:0] nat_rsp_rdata;
    logic [5:0]  nat_rsp_tag;

    pg_three_request_mux mem_mux(
        .clk(mem_clk), .rst(mem_rst),
        .req_valid(mx_req_valid), .req_ready(mx_req_ready),
        .req_write(mx_req_write), .req_addr(mx_req_addr),
        .req_wdata(mx_req_wdata), .req_wstrb(mx_req_wstrb), .req_id(mx_req_tag),
        .rsp_valid(mx_rsp_valid), .rsp_ready(mx_rsp_ready),
        .rsp_write(mx_rsp_write), .rsp_error(mx_rsp_error),
        .rsp_rdata(mx_rsp_rdata), .rsp_id(mx_rsp_tag),
        .m_req_valid(nat_req_valid), .m_req_ready(nat_req_ready),
        .m_req_write(nat_req_write), .m_req_addr(nat_req_addr),
        .m_req_wdata(nat_req_wdata), .m_req_wstrb(nat_req_wstrb),
        .m_req_tag(nat_req_tag),
        .m_rsp_valid(nat_rsp_valid), .m_rsp_ready(nat_rsp_ready),
        .m_rsp_write(nat_rsp_write), .m_rsp_error(nat_rsp_error),
        .m_rsp_rdata(nat_rsp_rdata), .m_rsp_tag(nat_rsp_tag),
        .protocol_fault(mux_fault)
    );
    assign mcdc_req_ready = mx_req_ready[1:0] & {mem_ready, mem_ready};

    logic        brg_awvalid, brg_awready, brg_wvalid, brg_wready, brg_bvalid, brg_bready;
    logic        brg_arvalid, brg_arready, brg_rvalid, brg_rready;
    logic [3:0]  brg_awid, brg_bid, brg_arid, brg_rid;
    logic [31:0] brg_awaddr, brg_araddr;
    logic [7:0]  brg_awlen, brg_arlen;
    logic [2:0]  brg_awsize, brg_arsize;
    logic [1:0]  brg_awburst, brg_arburst, brg_bresp, brg_rresp;
    logic [127:0] brg_wdata, brg_rdata;
    logic [15:0] brg_wstrb;
    logic        brg_wlast, brg_rlast;
    logic        brg_fault, brg_busy;
    logic [31:0] brg_accepted, brg_completed, brg_bursts;

    pg_ddr_burst_bridge #(
        .DATA_W(128), .TAG_W(6), .MAX_BEATS(16), .FLUSH_CYCLES(5),
        .DDR_BASE(DDR_BASE), .DDR_BYTES(DDR_BYTES)
    ) ddr_bridge (
        .clk(mem_clk), .rst(mem_rst),
        .s_req_valid(nat_req_valid), .s_req_ready(nat_req_ready),
        .s_req_write(nat_req_write), .s_req_addr(nat_req_addr),
        .s_req_wdata(nat_req_wdata), .s_req_wstrb(nat_req_wstrb),
        .s_req_tag(nat_req_tag),
        .s_rsp_valid(nat_rsp_valid), .s_rsp_ready(nat_rsp_ready),
        .s_rsp_write(nat_rsp_write), .s_rsp_rdata(nat_rsp_rdata),
        .s_rsp_tag(nat_rsp_tag), .s_rsp_error(nat_rsp_error),
        .m_axi_awid(brg_awid), .m_axi_awaddr(brg_awaddr), .m_axi_awlen(brg_awlen),
        .m_axi_awsize(brg_awsize), .m_axi_awburst(brg_awburst),
        .m_axi_awlock(), .m_axi_awcache(), .m_axi_awprot(),
        .m_axi_awvalid(brg_awvalid), .m_axi_awready(brg_awready),
        .m_axi_wdata(brg_wdata), .m_axi_wstrb(brg_wstrb),
        .m_axi_wlast(brg_wlast), .m_axi_wvalid(brg_wvalid), .m_axi_wready(brg_wready),
        .m_axi_bid(brg_bid), .m_axi_bresp(brg_bresp), .m_axi_bvalid(brg_bvalid),
        .m_axi_bready(brg_bready),
        .m_axi_arid(brg_arid), .m_axi_araddr(brg_araddr), .m_axi_arlen(brg_arlen),
        .m_axi_arsize(brg_arsize), .m_axi_arburst(brg_arburst),
        .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(),
        .m_axi_arvalid(brg_arvalid), .m_axi_arready(brg_arready),
        .m_axi_rid(brg_rid), .m_axi_rdata(brg_rdata), .m_axi_rresp(brg_rresp),
        .m_axi_rlast(brg_rlast), .m_axi_rvalid(brg_rvalid), .m_axi_rready(brg_rready),
        .protocol_fault(brg_fault), .busy(brg_busy),
        .accepted_count(brg_accepted), .completed_count(brg_completed),
        .burst_count(brg_bursts)
    );

    // memory-domain fault is fatal for the CPU: cross it as a level and OR it
    // into the NMI input together with the cache protocol fault.
    logic fault_lvl_mem, fault_lvl_cpu;
    pg_source_level_register fault_src(
        .clk(mem_clk), .rst(mem_rst), .level_in(mux_fault | brg_fault),
        .level_out(fault_lvl_mem));
    pg_level_sync fault_sync(
        .clk(cpu_clk), .rst(cpu_rst), .async_level(fault_lvl_mem),
        .level(fault_lvl_cpu));
    assign irq_fault_cpu = cache_fault | fault_lvl_cpu;

    // AXI merge: port 0 = CPU/cache path, port 1 = HDMI scan-out
    logic [1:0]  ax_awvalid, ax_awready, ax_wvalid, ax_wready;
    logic [1:0]  ax_bvalid, ax_bready, ax_arvalid, ax_arready;
    logic [1:0]  ax_rvalid, ax_rready, ax_wlast, ax_rlast;
    logic [1:0][3:0]  ax_awid, ax_bid, ax_arid, ax_rid;
    logic [1:0][31:0] ax_awaddr, ax_araddr;
    logic [1:0][7:0]  ax_awlen, ax_arlen;
    logic [1:0][2:0]  ax_awsize, ax_arsize;
    logic [1:0][1:0]  ax_awburst, ax_arburst, ax_bresp, ax_rresp;
    logic [1:0][127:0] ax_wdata, ax_rdata;
    logic [1:0][15:0]  ax_wstrb;
    logic axi_busy;

    assign ax_awvalid[0] = brg_awvalid;
    assign ax_awaddr[0] = brg_awaddr;
    assign ax_awlen[0] = brg_awlen;
    assign ax_awsize[0] = brg_awsize;
    assign ax_awburst[0] = brg_awburst;
    assign ax_awid[0] = brg_awid;
    assign ax_wdata[0] = brg_wdata;
    assign ax_wstrb[0] = brg_wstrb;
    assign ax_wlast[0] = brg_wlast;
    assign ax_wvalid[0] = brg_wvalid;
    assign brg_awready = ax_awready[0];
    assign brg_wready = ax_wready[0];
    assign brg_bid = ax_bid[0];
    assign brg_bresp = ax_bresp[0];
    assign brg_bvalid = ax_bvalid[0];
    assign ax_bready[0] = brg_bready;
    assign ax_arvalid[0] = brg_arvalid;
    assign ax_araddr[0] = brg_araddr;
    assign ax_arlen[0] = brg_arlen;
    assign ax_arsize[0] = brg_arsize;
    assign ax_arburst[0] = brg_arburst;
    assign ax_arid[0] = brg_arid;
    assign brg_arready = ax_arready[0];
    assign brg_rid = ax_rid[0];
    assign brg_rdata = ax_rdata[0];
    assign brg_rresp = ax_rresp[0];
    assign brg_rlast = ax_rlast[0];
    assign brg_rvalid = ax_rvalid[0];
    assign ax_rready[0] = brg_rready;

    assign ax_awvalid[1] = 1'b0;
    assign ax_awaddr[1] = 32'd0;
    assign ax_awlen[1] = 8'd0;
    assign ax_awsize[1] = 3'd4;
    assign ax_awburst[1] = 2'b01;
    assign ax_awid[1] = 4'd0;
    assign ax_wdata[1] = 128'd0;
    assign ax_wstrb[1] = 16'd0;
    assign ax_wlast[1] = 1'b0;
    assign ax_wvalid[1] = 1'b0;
    assign ax_bready[1] = 1'b1;
    assign ax_arvalid[1] = h_arvalid;
    assign ax_araddr[1] = h_araddr;
    assign ax_arlen[1] = h_arlen;
    assign ax_arsize[1] = h_arsize;
    assign ax_arburst[1] = h_arburst;
    assign ax_arid[1] = h_arid;
    assign h_arready = ax_arready[1];
    assign h_rid = ax_rid[1];
    assign h_rdata = ax_rdata[1];
    assign h_rresp = ax_rresp[1];
    assign h_rlast = ax_rlast[1];
    assign h_rvalid = ax_rvalid[1];
    assign ax_rready[1] = h_rready;

    soc_axi_2m_arbiter #(.DATA_W(128), .ADDR_W(32), .ID_W(4)) axi_merge (
        .clk(mem_clk), .rst(mem_rst), .busy(axi_busy),
        .s_awid(ax_awid), .s_awaddr(ax_awaddr), .s_awlen(ax_awlen),
        .s_awsize(ax_awsize), .s_awburst(ax_awburst), .s_awvalid(ax_awvalid),
        .s_awready(ax_awready),
        .s_wdata(ax_wdata), .s_wstrb(ax_wstrb), .s_wlast(ax_wlast),
        .s_wvalid(ax_wvalid), .s_wready(ax_wready),
        .s_bid(ax_bid), .s_bresp(ax_bresp), .s_bvalid(ax_bvalid), .s_bready(ax_bready),
        .s_arid(ax_arid), .s_araddr(ax_araddr), .s_arlen(ax_arlen),
        .s_arsize(ax_arsize), .s_arburst(ax_arburst), .s_arvalid(ax_arvalid),
        .s_arready(ax_arready),
        .s_rid(ax_rid), .s_rdata(ax_rdata), .s_rresp(ax_rresp),
        .s_rlast(ax_rlast), .s_rvalid(ax_rvalid), .s_rready(ax_rready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen),
        .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready)
    );

endmodule
