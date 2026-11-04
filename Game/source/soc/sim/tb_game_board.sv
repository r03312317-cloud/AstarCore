// ---------------------------------------------------------------------------
// tb_game_board -- full-SoC simulation of rv32_soc_Game.
//
// Instantiates the real board top (CPU, caches, DDR bridge, HMIC adapter,
// scan-out, HDMI timing, button controller) with the behavioural DDR model and
// the real firmware images in ITCM/DTCM.  The raster is sampled from the HDMI
// pixel stream, so a captured frame proves the whole path:
//   CPU stores -> caches/bypass -> CDC -> burst bridge -> AXI -> DDR ->
//   scan-out -> HDMI timing.
//
// The clocks and the reset are driven by sim/sim_main.cpp (one eval() per clock
// edge) instead of #delays, which keeps the run far faster than Verilator's
// timing scheduler.
//
// Plusargs:
//   +frames=N      stop after N vertical blanks (default 40)
//   +dump=PREFIX   write PREFIX_<n>.ppm for each frame listed below
//   +at0..at3=K    frame indices to dump
// ---------------------------------------------------------------------------
`timescale 1ps/1ps
module tb_game_board(
    input  logic cpu_clk,
    input  logic mem_clk,
    input  logic pix_clk,
    input  logic sys_clk,
    input  logic ser_clk,
    input  logic rst_n,
    output logic finished,
    output int   frames_o,
    output logic [31:0] vsync_o,
    output logic [31:0] present_o,
    output logic de_seen_o
);

    localparam int W = 640;
    localparam int H = 360;

    logic [4:0] btn_n;
    logic [7:0] pad_n;

    logic uart_tx;
    logic [7:0] led;
    logic [2:0] tmds_p, tmds_n;
    logic tmds_clk_p, tmds_clk_n;

    logic [23:0] v_rgb;
    logic v_de, v_hs, v_vs;
    logic [31:0] dbg_vsync, dbg_presented, dbg_active_fb;
    logic dbg_fatal;

    game_board_top #(
        .ITCM_INIT_FILE("game-itcm.mem"),
        .DTCM_INIT_FILE("game-dtcm.mem")
    ) dut (
        .sim_cpu_clk(cpu_clk),
        .sim_mem_clk(mem_clk),
        .sim_pix_clk(pix_clk),
        .sim_ser_clk(ser_clk),
        .sim_rst_n(rst_n),
        .sys_clk(sys_clk),
        .clk_p(1'b0), .clk_n(1'b0),
        .uart_rx(1'b1),
        .btn_n(btn_n),
        .pad_n(pad_n),
        .uart_tx(uart_tx),
        .led(led),
        .tmds_data_p(tmds_p), .tmds_data_n(tmds_n),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .mem_rst_n(), .mem_ck(), .mem_ck_n(), .mem_cke(), .mem_cs_n(),
        .mem_ras_n(), .mem_cas_n(), .mem_we_n(), .mem_odt(), .mem_a(),
        .mem_ba(), .mem_dqs(), .mem_dqs_n(), .mem_dq(), .mem_dm(),
        .dbg_video_rgb(v_rgb), .dbg_video_de(v_de),
        .dbg_video_hs(v_hs), .dbg_video_vs(v_vs),
        .dbg_vsync(dbg_vsync), .dbg_presented(dbg_presented),
        .dbg_active_fb(dbg_active_fb), .dbg_fatal(dbg_fatal)
    );

    // ---- raster capture: every second pixel of every second line ----------
    logic [23:0] frame[0:W*H-1];
    int px, py;
    int frames_done;
    int dump_at[4];
    int dump_count;
    string dump_prefix;
    int max_frames;
    int de_pixels;

    initial begin
        px = 0; py = 0; frames_done = 0; de_pixels = 0;
        dump_count = 0; finished = 0;
        btn_n = 5'h1f; pad_n = 8'hff;
        for (int i = 0; i < 4; i++) dump_at[i] = -1;
        if (!$value$plusargs("frames=%d", max_frames)) max_frames = 40;
        if (!$value$plusargs("dump=%s", dump_prefix)) dump_prefix = "sim_frame";
        begin
            int v;
            if ($value$plusargs("at0=%d", v)) dump_at[dump_count++] = v;
            if ($value$plusargs("at1=%d", v)) dump_at[dump_count++] = v;
            if ($value$plusargs("at2=%d", v)) dump_at[dump_count++] = v;
            if ($value$plusargs("at3=%d", v)) dump_at[dump_count++] = v;
        end
        $display("TB: frames=%0d dumps=%0d", max_frames, dump_count);
    end

    // sample the active window: 1280x720 doubled from the 640x360 buffer
    always @(posedge pix_clk) begin
        if (v_de) begin
            de_pixels <= de_pixels + 1;
            if ((px % 2) == 0 && (py % 2) == 0 && px < 2*W && py < 2*H)
                frame[(py/2)*W + (px/2)] <= v_rgb;
            if (px == 2*W - 1) begin
                px <= 0;
                py <= py + 1;
            end else begin
                px <= px + 1;
            end
        end
        if (v_vs) begin
            px <= 0;
            py <= 0;
        end
    end

    // ---- frame counter / dumping ------------------------------------------
    // Frames are counted from the HDMI vertical sync itself, not from the
    // publication counter, so the raster timeline is observable even when the
    // CPU has not published anything yet.
    logic vs_q;

    initial vs_q = 1'b0;

    assign frames_o = frames_done;
    assign vsync_o = dbg_vsync;
    assign present_o = dbg_presented;
    assign de_seen_o = v_de;

    always @(posedge pix_clk) begin
        vs_q <= v_vs;
        if (v_vs && !vs_q) begin
            frames_done <= frames_done + 1;
            for (int i = 0; i < dump_count; i++) begin
                if (dump_at[i] == frames_done) dump_frame(frames_done);
            end
            if (frames_done + 1 >= max_frames) begin
                $display("TB: done frames=%0d de_pixels=%0d presented=%0d active_fb=%08x fatal=%0d led=%02x",
                         frames_done + 1, de_pixels, dbg_presented, dbg_active_fb, dbg_fatal, led);
                finished <= 1;
                $finish;
            end
        end
    end

    // UART activity proves the firmware is executing even before the first
    // frame buffer commit.
    int uart_falls;
    logic uart_q;
    initial begin uart_falls = 0; uart_q = 1'b1; end
    always @(posedge cpu_clk) begin
        uart_q <= uart_tx;
        if (uart_q && !uart_tx) uart_falls <= uart_falls + 1;
    end

    task automatic dump_frame(input int idx);
        int fd;
        string name;
        name = $sformatf("%s_%03d.ppm", dump_prefix, idx);
        fd = $fopen(name, "wb");
        if (fd == 0) begin
            $display("TB: cannot open %s", name);
            return;
        end
        $fwrite(fd, "P6\n%0d %0d\n255\n", W, H);
        for (int i = 0; i < W*H; i++) begin
            $fwrite(fd, "%c%c%c", frame[i][23:16], frame[i][15:8], frame[i][7:0]);
        end
        $fclose(fd);
        $display("TB: dumped %s at frame %0d (presented=%0d)", name, idx, dbg_presented);
    endtask

    // ---- scripted buttons --------------------------------------------------
    // bit0 UP, bit1 DOWN, bit2 LEFT, bit3 RIGHT, bit4 A (all active low).
    // The script does not depend on the exact boot time: A is pulsed every
    // 30 frames (start the game / advance a dialog) and the direction walks a
    // clockwise square once the first frame has been published.
    logic [4:0] btn_script;
    always @(posedge mem_clk) begin
        if (!rst_n) begin
            btn_n <= 5'h1f;
        end else begin
            btn_script = 5'h1f;
            if ((frames_done % 30) >= 12 && (frames_done % 30) < 15)
                btn_script[4] = 1'b0;
            if (frames_done > 55) begin
                case ((frames_done / 18) % 4)
                    0: btn_script[3] = 1'b0;   // RIGHT
                    1: btn_script[1] = 1'b0;   // DOWN
                    2: btn_script[2] = 1'b0;   // LEFT
                    default: btn_script[0] = 1'b0; // UP
                endcase
            end
            btn_n <= btn_script;
        end
    end

endmodule
