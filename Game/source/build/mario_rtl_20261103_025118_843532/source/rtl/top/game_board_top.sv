// ---------------------------------------------------------------------------
// game_board_top -- Pango PG2L200H-6FBB676 (MES2L676-200HP "200K MINI")
// board level for rv32_soc_Game.
//
//   * 27 MHz single-ended sys_clk  (D18)  -> HDMI pixel 27 MHz / serial 135 MHz
//     (720x480p60 carrier; 74.25/371.25 MHz would need 742.5 Mbit/s and is
//      outside what the 2.5 V LVDS25 TMDS bank can drive)
//   * 125 MHz differential ref_clk (N3/N2) -> CPU 100 MHz PLL, DDR reference
//   * DDR3 x32 (vendor IP soc_ddr800) in 128-bit AXI user mode via the
//     mainline HMIC adapter
//   * five onboard user buttons (C23, B22, A22, B20, C22) plus eight optional
//     external buttons on the unused camera header pads
//   * UART (B24/C24) for debug, eight LEDs, direct TMDS output
//
// Reset: there is no dedicated reset pin in this build (C22 is the fifth game
// button).  A power-on reset is generated after every PLL locks and is held for
// 1024 reference clocks, which is the fix validated on the mainline for the
// CPU's reset-only initialisation of PC and CSRs.
//
// `GAME_SIM removes the vendor PLL/DDR/TMDS primitives: clocks come from the
// testbench, the DDR controller is replaced by game_ddr_model and the TMDS
// transmitter by a passthrough so that the raster can be captured directly.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module game_board_top #(
    // Non-empty defaults: PDS runs `compile` without -define, so an empty
    // default would leave both TCMs uninitialised in the bitstream and the
    // CPU would fetch X from 0x1000_0000.  The files are copied next to the
    // Tcl script by pds/flow.py, which cds into the run directory first.
    parameter ITCM_INIT_FILE = "game-itcm.mem",
    parameter DTCM_INIT_FILE = "game-dtcm.mem",
    // 1 = LED panel shows PLL/DDR/CPU-alive state (bring-up), 0 = game status.
    parameter bit LED_PANEL_DIAG = 1'b1,
    // The header pins are also camera data pins on this board.  Ignore them
    // by default so an attached camera cannot generate phantom button presses.
    parameter bit EXTERNAL_PAD_ENABLE = 1'b0
) (
`ifdef GAME_SIM
    input  logic sim_cpu_clk,
    input  logic sim_mem_clk,
    input  logic sim_pix_clk,
    input  logic sim_ser_clk,
    input  logic sim_rst_n,
`endif
    input  logic sys_clk,
    input  logic clk_p,
    input  logic clk_n,
    input  logic uart_rx,
    input  logic [4:0] btn_n,          // active-low onboard buttons
    input  logic [7:0] pad_n,          // active-low external buttons
    output logic uart_tx,
    output logic [7:0] led,
    output logic [2:0] tmds_data_p,
    output logic [2:0] tmds_data_n,
    output logic tmds_clk_p,
    output logic tmds_clk_n,
    output logic mem_rst_n,
    output logic mem_ck,
    output logic mem_ck_n,
    output logic mem_cke,
    output logic mem_cs_n,
    output logic mem_ras_n,
    output logic mem_cas_n,
    output logic mem_we_n,
    output logic mem_odt,
    output logic [14:0] mem_a,
    output logic [2:0] mem_ba,
    inout  wire [3:0] mem_dqs,
    inout  wire [3:0] mem_dqs_n,
    inout  wire [31:0] mem_dq,
    output logic [3:0] mem_dm
`ifdef GAME_SIM
    , output logic [23:0] dbg_video_rgb,
    output logic dbg_video_de,
    output logic dbg_video_hs,
    output logic dbg_video_vs,
    output logic [31:0] dbg_vsync,
    output logic [31:0] dbg_presented,
    output logic [31:0] dbg_active_fb,
    output logic dbg_fatal
`endif
);
    timeunit 1ns;
    timeprecision 1ps;

    // ------------------------------------------------------------- clocks
    logic ref_clk, sys_clk_i, cpu_clk, cpu_pll_lock;
    logic hdmi_pixel_clk, hdmi_serial_clk, hdmi_pll_locked, hdmi_pixel_reset_n;
    logic mem_clk;

`ifdef GAME_SIM
    assign ref_clk = sim_mem_clk;
    assign cpu_clk = sim_cpu_clk;
    assign mem_clk = sim_mem_clk;
    assign hdmi_pixel_clk = sim_pix_clk;
    assign hdmi_serial_clk = sim_ser_clk;
    assign cpu_pll_lock = 1'b1;
    assign hdmi_pll_locked = 1'b1;
    assign sys_clk_i = sys_clk;
    logic unused_clk_p, unused_clk_n;
    assign unused_clk_p = clk_p;
    assign unused_clk_n = clk_n;
`else
    GTP_INBUFGDS #(.IOSTANDARD("DEFAULT"), .TERM_DIFF("ON")) u_refclk(
        .O(ref_clk), .I(clk_p), .IB(clk_n));
    soc_cpu100_pll_probe u_cpu_pll(
        .clkin1(ref_clk), .clkout1(cpu_clk), .lock(cpu_pll_lock));
    soc_mini_hdmi_clock u_hdmi_clock(
        .sys_clk(sys_clk), .reset_n(1'b1),
        .pixel_clk(hdmi_pixel_clk), .serial_clk(hdmi_serial_clk),
        .pll_locked(hdmi_pll_locked), .pixel_reset_n(hdmi_pixel_reset_n));
    assign sys_clk_i = sys_clk;
`endif

    // --------------------------------------------------------- reset chain
    logic [11:0] boot_cnt_q;
    logic boot_done_q;
    logic pll_ok;
`ifdef GAME_SIM
    assign pll_ok = sim_rst_n && cpu_pll_lock && hdmi_pll_locked;
`else
    assign pll_ok = cpu_pll_lock && hdmi_pll_locked;
`endif

    always_ff @(posedge ref_clk or negedge pll_ok) begin
        if (!pll_ok) begin
            boot_cnt_q <= 12'd0;
            boot_done_q <= 1'b0;
        end else if (!boot_done_q) begin
            if (boot_cnt_q == 12'd1023) boot_done_q <= 1'b1;
            else boot_cnt_q <= boot_cnt_q + 12'd1;
        end
    end

    logic arst;
    assign arst = !pll_ok || !boot_done_q;

    // DDR ready is sampled only in the user clock domain. A later PLL loss
    // stops new requests; it does not latch a permanent reset, so the game
    // resumes as soon as the controller reports ready again.
    logic ddr_init_done, ddr_pll_lock, ddr_phy_lock, ddr_cal_fail, ddr_ready;
    logic ddr_ready_core_meta, ddr_ready_core;
    always_ff @(posedge mem_clk or posedge arst) begin
        if (arst) begin
            ddr_ready <= 1'b0;
            ddr_ready_core_meta <= 1'b0;
            ddr_ready_core <= 1'b0;
        end else begin
            ddr_ready <= ddr_init_done && ddr_pll_lock && ddr_phy_lock && !ddr_cal_fail;
            ddr_ready_core_meta <= ddr_ready;
            ddr_ready_core <= ddr_ready_core_meta;
        end
    end

    // ------------------------------------------------------------ buttons
    // Five onboard buttons, plus an opt-in external pad on camera-header pins.
    logic [7:0] all_pads_n;
    logic [7:0] external_pads_n;
    assign external_pads_n = EXTERNAL_PAD_ENABLE ? pad_n : 8'hff;
    assign all_pads_n[0] = btn_n[0] & external_pads_n[0];   // UP
    assign all_pads_n[1] = btn_n[1] & external_pads_n[1];   // DOWN
    assign all_pads_n[2] = btn_n[2] & external_pads_n[2];   // LEFT
    assign all_pads_n[3] = btn_n[3] & external_pads_n[3];   // RIGHT
    assign all_pads_n[4] = btn_n[4] & external_pads_n[4];   // A / confirm
    assign all_pads_n[5] = external_pads_n[5];              // B / cancel
    assign all_pads_n[6] = external_pads_n[6];              // START
    assign all_pads_n[7] = external_pads_n[7];              // SELECT

    // ------------------------------------------------------------- SoC
    logic [23:0] video_rgb;
    logic video_de, video_hs, video_vs, pix_rst;
    logic [31:0] gpio_out;
    logic [31:0] dbg_vsync_i, dbg_presented_i, dbg_active_fb_i;
    logic dbg_cpu_sleeping_i, dbg_fatal_i, dbg_cpu_alive_i, dbg_cpu_trapped_i;
    logic uart_tx_cpu, cpu_tx_seen_q;

    logic [3:0] s_awid, s_bid, s_arid, s_rid;
    logic [31:0] s_awaddr, s_araddr;
    logic [7:0] s_awlen, s_arlen;
    logic [2:0] s_awsize, s_arsize;
    logic [1:0] s_awburst, s_arburst, s_bresp, s_rresp;
    logic s_awvalid, s_awready, s_wlast, s_wvalid, s_wready;
    logic s_bvalid, s_bready, s_arvalid, s_arready, s_rlast, s_rvalid, s_rready;
    logic [127:0] s_wdata, s_rdata;
    logic [15:0] s_wstrb;

    game_soc_top #(
        .ITCM_INIT_FILE(ITCM_INIT_FILE),
        .DTCM_INIT_FILE(DTCM_INIT_FILE)
    ) soc (
        .cpu_clk(cpu_clk), .mem_clk(mem_clk), .pix_clk(hdmi_pixel_clk),
        .arst(arst), .mem_ready(ddr_ready_core),
        .pads_n(all_pads_n), .key_n(1'b1),
        .uart_rx(uart_rx), .uart_tx(uart_tx_cpu), .gpio_out(gpio_out),
        .video_rgb(video_rgb), .video_de(video_de),
        .video_hs(video_hs), .video_vs(video_vs),
        .pix_rst_o(pix_rst),
        .dbg_vsync(dbg_vsync_i), .dbg_presented(dbg_presented_i),
        .dbg_active_fb(dbg_active_fb_i),
        .dbg_cpu_sleeping(dbg_cpu_sleeping_i), .dbg_fatal(dbg_fatal_i),
        .dbg_cpu_alive(dbg_cpu_alive_i),
        .dbg_cpu_trapped(dbg_cpu_trapped_i),
        .m_awid(s_awid), .m_awaddr(s_awaddr), .m_awlen(s_awlen),
        .m_awsize(s_awsize), .m_awburst(s_awburst), .m_awvalid(s_awvalid),
        .m_awready(s_awready),
        .m_wdata(s_wdata), .m_wstrb(s_wstrb), .m_wlast(s_wlast),
        .m_wvalid(s_wvalid), .m_wready(s_wready),
        .m_bid(s_bid), .m_bresp(s_bresp), .m_bvalid(s_bvalid), .m_bready(s_bready),
        .m_arid(s_arid), .m_araddr(s_araddr), .m_arlen(s_arlen),
        .m_arsize(s_arsize), .m_arburst(s_arburst), .m_arvalid(s_arvalid),
        .m_arready(s_arready),
        .m_rid(s_rid), .m_rdata(s_rdata), .m_rresp(s_rresp),
        .m_rlast(s_rlast), .m_rvalid(s_rvalid), .m_rready(s_rready)
    );

    // ------------------------------------------------------------- HDMI TX
`ifdef GAME_SIM
    assign dbg_video_rgb = video_rgb;
    assign dbg_video_de = video_de;
    assign dbg_video_hs = video_hs;
    assign dbg_video_vs = video_vs;
    assign dbg_vsync = dbg_vsync_i;
    assign dbg_presented = dbg_presented_i;
    assign dbg_active_fb = dbg_active_fb_i;
    assign dbg_fatal = dbg_fatal_i;
    assign tmds_data_p = 3'b0;
    assign tmds_data_n = 3'b0;
    assign tmds_clk_p = 1'b0;
    assign tmds_clk_n = 1'b0;
    logic unused_pix_rst_sim;
    assign unused_pix_rst_sim = pix_rst;
`else
    soc_mini_hdmi_tx u_hdmi_tx(
        .pixel_clk(hdmi_pixel_clk), .serial_clk(hdmi_serial_clk),
        .reset_n(!pix_rst), .serial_reset_n(hdmi_pixel_reset_n),
        .rgb888(video_rgb), .de(video_de), .hsync(video_hs), .vsync(video_vs),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n));
`endif

    // ------------------------------------------------------ UART bring-up beacon
    // LEDs cannot distinguish "the serial pin never reaches the USB bridge" from
    // "the core never transmitted".  Until the core drives its first start bit,
    // the pin carries a 0x55 pattern generated in fabric at 115200 baud, so a
    // terminal showing "UUUU..." proves pin map, wiring and baud are all right
    // and the remaining fault is inside the core.
`ifdef GAME_SIM
    assign uart_tx = uart_tx_cpu;
    assign cpu_tx_seen_q = 1'b0;
`else
    logic beacon_tx, beacon_ready;

    // 27 MHz / 115200 = 234.4; 234 is within 0.2 % of the nominal rate.
    pg_uart #(.CLKS_PER_BIT(234)) u_uart_beacon (
        .clk(sys_clk), .rst(1'b0),
        .tx_valid(beacon_ready), .tx_ready(beacon_ready),
        .tx_data(8'h55), .tx_pin(beacon_tx),
        .rx_pin(1'b1), .rx_valid(), .rx_ready(1'b0), .rx_data(),
        .rx_frame_error(), .rx_overrun()
    );

    always_ff @(posedge sys_clk or posedge arst) begin
        if (arst) cpu_tx_seen_q <= 1'b0;
        else if (!uart_tx_cpu) cpu_tx_seen_q <= 1'b1;
    end
    assign uart_tx = cpu_tx_seen_q ? uart_tx_cpu : beacon_tx;
`endif

    // ------------------------------------------------------------ LED panel
    // The diagnostic panel is deliberately NOT cleared by board27_rst: a reset
    // that never releases is exactly the failure it has to show.  Bit order
    // (led7..led0):
    //   7 heartbeat   1 Hz from sys_clk; proves the panel itself is alive
    //   6 tx_seen     the core drove uart_tx low at least once
    //   5 trapped     the core entered its exception handler (mtvec resets to 0)
    //   4 cpu_alive   toggles ~6 Hz only while the core retires instructions
    //   3 ddr_ready   calibration done and all PLLs locked
    //   2 ddr_pll_lock
    //   1 hdmi_pll_locked
    //   0 cpu_pll_lock
    logic [7:0] led_level_cpu, led_sync27;
    logic [7:0] led_diag_raw, led_diag_s1, led_diag_s2;
    logic [23:0] led_heart_q;
    logic board27_rst;
    soc_reset_sync u_board27_reset(.clk(sys_clk), .arst, .rst(board27_rst));
    assign led_level_cpu = {dbg_fatal_i, dbg_cpu_sleeping_i, ddr_ready_core,
                            gpio_out[4:0]};
    always_ff @(posedge sys_clk) led_heart_q <= led_heart_q + 24'd1;
    assign led_diag_raw = {led_heart_q[22], cpu_tx_seen_q, dbg_cpu_trapped_i,
                           dbg_cpu_alive_i, ddr_ready_core, ddr_pll_lock,
                           hdmi_pll_locked, cpu_pll_lock};
    always_ff @(posedge sys_clk) begin
        led_diag_s1 <= led_diag_raw;
        led_diag_s2 <= led_diag_s1;
    end
    for (genvar l = 0; l < 8; l = l + 1) begin : led_cdc
        pg_level_sync u_sync(.clk(sys_clk), .rst(board27_rst),
                             .async_level(led_level_cpu[l]), .level(led_sync27[l]));
    end
    always_ff @(posedge sys_clk) begin
        if (LED_PANEL_DIAG) led <= led_diag_s2;
        else if (board27_rst) led <= 8'd0;
        else led <= led_sync27;
    end

    // -------------------------------------------------------------- DDR
    logic [7:0]  m_awid, m_bid, m_arid, m_rid;
    logic [29:0] m_awaddr, m_araddr;
    logic [7:0]  m_awlen, m_arlen;
    logic [2:0]  m_awsize, m_arsize;
    logic [1:0]  m_awburst, m_arburst, m_bresp, m_rresp;
    logic        m_awvalid, m_awready, m_wlast, m_wvalid, m_wready;
    logic        m_bvalid, m_bready, m_arvalid, m_arready, m_rlast, m_rvalid, m_rready;
    logic [255:0] m_wdata, m_rdata;
    logic [31:0]  m_wstrb;
    logic adapter_fault;

    soc_hmic_axi_adapter bridge(
        .clk(mem_clk), .rst(arst), .ddr_ready(ddr_ready_core),
        .protocol_fault(adapter_fault),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen),
        .s_awsize(s_awsize), .s_awburst(s_awburst), .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
        .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen),
        .s_arsize(s_arsize), .s_arburst(s_arburst), .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_rid(s_rid), .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rlast(s_rlast), .s_rvalid(s_rvalid), .s_rready(s_rready),
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

`ifdef GAME_SIM
    logic unused_adapter_fault;
    assign unused_adapter_fault = adapter_fault;
    game_ddr_model u_ddr (
        .ref_clk(ref_clk),
        .resetn(!arst),
        .pll_lock(ddr_pll_lock),
        .phy_pll_lock(ddr_phy_lock),
        .ddr_init_done(ddr_init_done),
        .ddr_cal_fail(ddr_cal_fail),
        .axi_awid(m_awid), .axi_awaddr(m_awaddr), .axi_awlen(m_awlen),
        .axi_awsize(m_awsize), .axi_awburst(m_awburst), .axi_awvalid(m_awvalid),
        .axi_awready(m_awready),
        .axi_wdata(m_wdata), .axi_wstrb(m_wstrb), .axi_wlast(m_wlast),
        .axi_wvalid(m_wvalid), .axi_wready(m_wready),
        .axi_bid(m_bid), .axi_bresp(m_bresp), .axi_bvalid(m_bvalid),
        .axi_bready(m_bready),
        .axi_arid(m_arid), .axi_araddr(m_araddr), .axi_arlen(m_arlen),
        .axi_arsize(m_arsize), .axi_arburst(m_arburst), .axi_arvalid(m_arvalid),
        .axi_arready(m_arready),
        .axi_rid(m_rid), .axi_rdata(m_rdata), .axi_rresp(m_rresp),
        .axi_rlast(m_rlast), .axi_rvalid(m_rvalid), .axi_rready(m_rready)
    );
    assign mem_rst_n = 1'b1;
    assign mem_ck = 1'b0;
    assign mem_ck_n = 1'b1;
    assign mem_cke = 1'b0;
    assign mem_cs_n = 1'b1;
    assign mem_ras_n = 1'b1;
    assign mem_cas_n = 1'b1;
    assign mem_we_n = 1'b1;
    assign mem_odt = 1'b0;
    assign mem_a = 15'd0;
    assign mem_ba = 3'd0;
    assign mem_dm = 4'd0;
`else
    soc_ddr800 I_ips_ddr_top(
        .ref_clk(ref_clk), .resetn(!arst), .core_clk(mem_clk),
        .pll_lock(ddr_pll_lock), .phy_pll_lock(ddr_phy_lock),
        .ddr_init_done(ddr_init_done),
        .axi_awid(m_awid), .axi_awaddr(m_awaddr), .axi_awlen(m_awlen),
        .axi_awsize(m_awsize), .axi_awburst(m_awburst), .axi_awvalid(m_awvalid),
        .axi_awready(m_awready),
        .axi_wdata(m_wdata), .axi_wstrb(m_wstrb), .axi_wlast(m_wlast),
        .axi_wvalid(m_wvalid), .axi_wready(m_wready),
        .axi_bid(m_bid), .axi_bresp(m_bresp), .axi_bvalid(m_bvalid),
        .axi_bready(m_bready),
        .axi_arid(m_arid), .axi_araddr(m_araddr), .axi_arlen(m_arlen),
        .axi_arsize(m_arsize), .axi_arburst(m_arburst), .axi_arvalid(m_arvalid),
        .axi_arready(m_arready),
        .axi_rid(m_rid), .axi_rdata(m_rdata), .axi_rresp(m_rresp),
        .axi_rlast(m_rlast), .axi_rvalid(m_rvalid), .axi_rready(m_rready),
        .mem_cs_n(mem_cs_n), .mem_rst_n(mem_rst_n), .mem_ck(mem_ck),
        .mem_ck_n(mem_ck_n), .mem_cke(mem_cke), .mem_ras_n(mem_ras_n),
        .mem_cas_n(mem_cas_n), .mem_we_n(mem_we_n), .mem_odt(mem_odt),
        .mem_a(mem_a), .mem_ba(mem_ba), .mem_dqs(mem_dqs),
        .mem_dqs_n(mem_dqs_n), .mem_dq(mem_dq), .mem_dm(mem_dm),
        .apb_clk(1'b0), .apb_rst_n(1'b0), .apb_sel(1'b0), .apb_enable(1'b0),
        .apb_addr(8'b0), .apb_write(1'b0), .apb_wdata(16'b0),
        .dbg_gate_start(1'b0), .dbg_cpd_start(1'b0), .dbg_ddrphy_rst_n(1'b1),
        .dbg_gpll_scan_rst(1'b0),
        .samp_position_dyn_adj(1'b0), .init_samp_position_even(32'b0),
        .wrcal_position_dyn_adj(1'b0), .init_wrcal_position(32'b0),
        .force_read_clk_ctrl(1'b0), .init_slip_step(16'b0),
        .init_read_clk_ctrl(12'b0),
        .debug_cpd_offset_adj(1'b0), .debug_cpd_offset_dir(1'b0),
        .debug_cpd_offset(10'b0),
        .ck_dly_en(1'b1), .init_ck_dly_step(8'b0),
        .dbg_ddrphy_init_fail(ddr_cal_fail)
    );
`endif

endmodule
