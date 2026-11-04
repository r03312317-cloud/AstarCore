// Mario boot/input/video integration test: unchanged SoC, real UART and HDMI output.
// DDR preloading bypasses the wire transfer, not CPU execution.
// UART is decoded from the pin; pictures are sampled from the HDMI RGB stream.
`timescale 1ps/1ps
module tb_game_bringup (
    input logic cpu_clk, mem_clk, pix_clk, sys_clk, ser_clk, rst_n,
    output logic finished,
    output int frames_o,
    output logic [31:0] vsync_o, presented_o, active_fb_o
);
    localparam int W = 640, H = 360;
    localparam int UART_BIT_CYCLES = 868; // 100 MHz / 115200

    logic [4:0] btn_n;
    logic uart_tx;
    logic [7:0] led;
    logic [23:0] rgb;
    logic de, hs, vs, fatal;
    logic [31:0] vsync_count, presented, active_fb;
    int trace_writes, trace_en;
    logic [29:0] trace_awaddr;
    initial begin trace_writes = 0; trace_awaddr = 0; trace_en = 0;
        if ($test$plusargs("trace_writes")) trace_en = 1;
    end
    always @(posedge mem_clk) begin
        if (trace_en && dut.m_awvalid && dut.m_awready) trace_awaddr <= dut.m_awaddr;
        if (trace_en && dut.m_wvalid && dut.m_wready && trace_writes < 16) begin
            $display("WRITE_TRACE: aw=%08x strobe=%08x data=%064x", trace_awaddr,
                     dut.m_wstrb, dut.m_wdata);
            trace_writes <= trace_writes + 1;
        end
    end

    game_board_top #(.ITCM_INIT_FILE("game-itcm.mem"),
                     .DTCM_INIT_FILE("game-dtcm.mem")) dut (
        .sim_cpu_clk(cpu_clk), .sim_mem_clk(mem_clk), .sim_pix_clk(pix_clk),
        .sim_ser_clk(ser_clk), .sim_rst_n(rst_n), .sys_clk(sys_clk),
        .clk_p(1'b0), .clk_n(1'b0), .uart_rx(1'b1),
        // Camera data pins held low must not act as buttons in the default
        // onboard-button configuration.
        .btn_n(btn_n), .pad_n(8'h00), .uart_tx(uart_tx), .led(led),
        .tmds_data_p(), .tmds_data_n(), .tmds_clk_p(), .tmds_clk_n(),
        .mem_rst_n(), .mem_ck(), .mem_ck_n(), .mem_cke(), .mem_cs_n(),
        .mem_ras_n(), .mem_cas_n(), .mem_we_n(), .mem_odt(),
        .mem_a(), .mem_ba(), .mem_dqs(), .mem_dqs_n(), .mem_dq(), .mem_dm(),
        .dbg_video_rgb(rgb), .dbg_video_de(de), .dbg_video_hs(hs),
        .dbg_video_vs(vs), .dbg_vsync(vsync_count),
        .dbg_presented(presented), .dbg_active_fb(active_fb), .dbg_fatal(fatal)
    );

    assign vsync_o = vsync_count;
    assign presented_o = presented;
    assign active_fb_o = active_fb;

    // Decode the actual pin at the centre of each serial bit.
    typedef enum logic [1:0] {U_IDLE, U_START, U_DATA, U_STOP} uart_state_t;
    uart_state_t uart_state;
    int uart_timer, uart_bit;
    logic [7:0] uart_byte;
    string uart_line = "";
    bit memory_probe = $test$plusargs("memory_probe");
    bit loader_probe = $test$plusargs("loader_probe");
    bit mario_ready = 0, key_seen = 0, preloaded = 0;
    always @(negedge cpu_clk) if (!rst_n && !preloaded) begin
        if ($test$plusargs("mario_preload")) begin
            $readmemh("mario-ddr.mem", dut.u_ddr.mem);
            $display("MARIO_TEST: preload deployable mario.bin into behavioural DDR");
        end
        preloaded = 1;
    end
    initial begin uart_state = U_IDLE; uart_timer = 0; uart_bit = 0; uart_byte = 0; end
    always @(posedge cpu_clk) begin
        if (!rst_n) begin
            uart_state <= U_IDLE;
            uart_timer <= 0;
            uart_bit <= 0;
        end else if (uart_state == U_IDLE) begin
            if (!uart_tx) begin
                uart_state <= U_START;
                uart_timer <= UART_BIT_CYCLES/2 - 1;
            end
        end else if (uart_timer != 0) begin
            uart_timer <= uart_timer - 1;
        end else begin
            case (uart_state)
                U_START: begin
                    if (uart_tx) uart_state <= U_IDLE;
                    else begin uart_state <= U_DATA; uart_bit <= 0; uart_timer <= UART_BIT_CYCLES-1; end
                end
                U_DATA: begin
                    uart_byte[uart_bit] <= uart_tx;
                    uart_timer <= UART_BIT_CYCLES-1;
                    if (uart_bit == 7) uart_state <= U_STOP;
                    else uart_bit <= uart_bit + 1;
                end
                U_STOP: begin
                    if (uart_tx) begin
                        $write("%c", uart_byte); $fflush();
                        begin
                            if(uart_byte==10)begin
                                if(memory_probe && uart_line=="RV32_MEMORY_PASS")begin
                                    $display("RV32_MEMORY_PROBE_COMPLETE");$finish;
                                end
                                if(uart_line.substr(0,14)=="RV32_MEMORY_FAIL")$fatal(1,"CPU memory probe failed: %s",uart_line);
                                if(loader_probe && uart_line=="APAL_READY V01 100MHz") begin
                                    $display("PAL_LOADER_RTL_READY_PASS"); $finish;
                                end
                                if(uart_line.substr(0,15)=="MARIO_CHECKPOINT") mario_ready=1;
                                if(uart_line.substr(0,17)=="MARIO_KEY=1 DOWN=1") key_seen=1;
                                if(uart_line=="MARIO_VIDEO_TIMEOUT" || uart_line=="MARIO_EXIT" || uart_line.substr(0,4)=="TRAP=")
                                    $fatal(1,"Mario runtime failure: %s",uart_line);
                                uart_line="";
                            end else if(uart_byte!=13)uart_line={uart_line,string'(uart_byte)};
                        end
                    end
                    else $display("\nUART_FRAMING_ERROR");
                    uart_state <= U_IDLE;
                end
                default: uart_state <= U_IDLE;
            endcase
        end
    end

    // 480p carrier has 720 active pixels per line.  Store only the 640x360
    // central game area (x=40..679, y=60..419), once for each active pixel.
    logic [23:0] image [0:W*H-1];
    logic de_q, vs_q;
    logic after_one, after_two;
    logic [31:0] after_fb;
    int px, py, frames, max_frames, first_present_frame;
    initial begin
        btn_n = 5'h1f; de_q = 0; vs_q = 1; px = 0; py = 0; frames = 0;
        first_present_frame = -1; finished = 0; after_one = 0; after_two = 0; after_fb = 0;
        if (!$value$plusargs("frames=%d", max_frames)) max_frames = 180;
        $display("BRINGUP: 480p60, max_frames=%0d", max_frames);
    end
    assign frames_o = frames;

    task automatic dump_image(input string name);
        int fd;
        fd = $fopen(name, "wb");
        if (!fd) $fatal(1, "cannot open %s", name);
        $fwrite(fd, "P6\n%0d %0d\n255\n", W, H);
        for (int i = 0; i < W*H; i++)
            $fwrite(fd, "%c%c%c", image[i][23:16], image[i][15:8], image[i][7:0]);
        $fclose(fd);
        $display("BRINGUP: saved %s", name);
    endtask

    always @(posedge pix_clk) begin
        de_q <= de;
        vs_q <= vs;
        if (de) begin
            if (px >= 40 && px < 680 && py >= 60 && py < 420)
                image[(py-60)*W + (px-40)] <= rgb;
            px <= px + 1;
        end
        if (de_q && !de) begin px <= 0; py <= py + 1; end
        // This mode has a negative-polarity VSYNC pulse.
        if (rst_n && !dut.arst && vs_q && !vs) begin
            px <= 0; py <= 0; frames <= frames + 1;
            if ((frames % 30)==0)
                $display("MARIO_TEST frame=%0d presented=%0d active=%08x fatal=%0d",frames,presented,active_fb,fatal);
            if (fatal) $fatal(1,"Mario SoC fatal flag");
            if(mario_ready && first_present_frame<0) first_present_frame<=frames;
            // Hold BUTTON0 until the real AM input pump sees it. This avoids
            // assuming a particular software rendering rate.
            btn_n <= (mario_ready && !key_seen) ? 5'h0f : 5'h1f;
            if(first_present_frame>=0 && frames>=first_present_frame+2 && !after_one) begin
                dump_image("mario_boot.ppm"); after_one<=1;
            end
            if(key_seen && after_one) begin
                $display("MARIO_RTL_BOOT_INPUT_VIDEO_PASS: presented=%0d active=%08x",presented,active_fb);
                finished<=1; $finish;
            end
            if(frames+1>=max_frames) $fatal(1,"Mario integration timeout");
        end
    end
endmodule
