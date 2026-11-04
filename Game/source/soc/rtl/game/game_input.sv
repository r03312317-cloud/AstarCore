// [ARCH] 板载按键依次经过同步、1 ms 积分去抖和边沿检测。
// [ARCH] LEVEL、PRESSED、RELEASED、REPEAT 分别表示电平、按下、松开和重复事件。
// [ARCH] 粘滞事件按 RW1C 定义清除，不能与电平读取混用。
// [ARCH] 毫秒分频依赖实际 100 MHz CPU 时钟。
// [ARCH] 输入低有效，软件 LEVEL 中按下被转换为 1。
// [ARCH] 实体按键经板级重排，bit0 不能直接解释为 USER_BUTTON0。
// ---------------------------------------------------------------------------
// game_input -- 8-button debounced input with press/release/auto-repeat events.
//
// One physical board key and up to eight external buttons share the same
// pipeline: two-flop synchroniser -> 1 ms integrator debounce -> edge events ->
// hold/auto-repeat.  The 1 ms time base keeps every counter small.
//
// Register map (byte offset inside the board MMIO page selected by the fabric):
//   0x00 RO  ID             0x47494E31 ('GIN1')
//   0x04 RO  LEVEL          bit i = button i is pressed (1 = pressed)
//   0x08 RW1C PRESSED       sticky press event
//   0x0C RW1C RELEASED      sticky release event
//   0x10 RW1C REPEAT        sticky auto-repeat tick while held
//   0x14 RW  DEBOUNCE_MS    stable time required before a level is accepted
//   0x18 RW  REPEAT_DELAY_MS  hold time before the first repeat
//   0x1C RW  REPEAT_PERIOD_MS period of following repeats
//   0x20 RO  MS_TICKS       free-running 1 ms counter
//   0x24 RO  HOLD_MS        hold time of the most recently pressed button
//
// All inputs are active-low on the pads (button to GND, internal pull-up), so
// the module inverts them once after synchronisation.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module game_input #(
    parameter int WIDTH = 8,
    // [ARCH] TICK_DIV：硬件时钟分频值决定毫秒事件基准，实际 CPU 时钟变化需同步检查。
    parameter int TICK_DIV = 100_000,      // 100 MHz -> 1 ms
    // [ARCH] DEBOUNCE_MS：连续稳定达到门槛才改变按键状态，单位是内部毫秒 tick。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 debounce_ms_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter int DEBOUNCE_MS = 8,
    // [ARCH] REPEAT_DELAY_MS：按住达到该延迟后才产生自动重复事件。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 repeat_delay_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter int REPEAT_DELAY_MS = 300,
    // [ARCH] REPEAT_PERIOD_MS：重复事件的间隔不同于按键去抖时间。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 repeat_period_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter int REPEAT_PERIOD_MS = 90
) (
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input  logic clk,
    // [ARCH] rst：复位控制不同于 PLL/DDR 就绪；具体极性与同步方式按本模块时序块执行。
    input  logic rst,
    input  logic [WIDTH-1:0] pads_n,       // active-low raw pins
    // [ARCH] req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 access 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic req_valid,
    // [ARCH] req_ready：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 access 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic req_ready,
    // [ARCH] req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 off, error_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [15:0] req_addr,
    // [ARCH] req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 clear_events, clear_press, clear_release, clear_repeat 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic req_write,
    // [ARCH] req_wdata：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pressed_q, released_q, repeat_q, debounce_ms_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [31:0] req_wdata,
    // [ARCH] req_wstrb：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 clear_events, error_q, debounce_ms_q, repeat_delay_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic [3:0]  req_wstrb,
    // [ARCH] rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    output logic rsp_valid,
    // [ARCH] rsp_ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  logic rsp_ready,
    // [ARCH] rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    output logic [31:0] rsp_rdata,
    // [ARCH] rsp_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    output logic rsp_error
);
    timeunit 1ns;
    timeprecision 1ps;

    // [ARCH] ID_VALUE：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rdata_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    localparam logic [31:0] ID_VALUE = 32'h4749_4E31;

    // ---- 1 ms tick -------------------------------------------------------
    logic [31:0] tick_div_q;
    logic [31:0] ms_q;
    logic tick;
    always_ff @(posedge clk) begin
        if (rst) begin
            tick_div_q <= 32'd0;
            ms_q <= 32'd0;
            tick <= 1'b0;
        end else begin
            if (tick_div_q + 32'd1 >= 32'(TICK_DIV)) begin
                tick_div_q <= 32'd0;
                tick <= 1'b1;
                ms_q <= ms_q + 32'd1;
            end else begin
                tick_div_q <= tick_div_q + 32'd1;
                tick <= 1'b0;
            end
        end
    end

    // ---- synchronise + invert -------------------------------------------
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic [WIDTH-1:0] pad_meta_q;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic [WIDTH-1:0] pad_sync_q;
    logic [WIDTH-1:0] level_in;
    always_ff @(posedge clk) begin
        if (rst) begin
            pad_meta_q <= '0;
            pad_sync_q <= '0;
        end else begin
            pad_meta_q <= pads_n;
            pad_sync_q <= pad_meta_q;
        end
    end
    assign level_in = ~pad_sync_q;

    // ---- debounce --------------------------------------------------------
    logic [WIDTH-1:0] stable_q;
    logic [7:0] dbnc_cnt_q[WIDTH];
    logic [WIDTH-1:0] press_pulse, release_pulse;
    logic [7:0] debounce_ms_q;
    logic [WIDTH-1:0] dbnc_last;
    integer i;
    always_ff @(posedge clk) begin
        press_pulse <= '0;
        release_pulse <= '0;
        if (rst) begin
            stable_q <= '0;
            for (i = 0; i < WIDTH; i = i + 1) dbnc_cnt_q[i] <= 8'd0;
        end else begin
            if (tick) begin
                for (i = 0; i < WIDTH; i = i + 1) begin
                    if (level_in[i] != stable_q[i]) begin
                        if (dbnc_cnt_q[i] + 8'd1 >= debounce_ms_q) begin
                            dbnc_cnt_q[i] <= 8'd0;
                            stable_q[i] <= level_in[i];
                            if (level_in[i]) press_pulse[i] <= 1'b1;
                            else release_pulse[i] <= 1'b1;
                        end else begin
                            dbnc_cnt_q[i] <= dbnc_cnt_q[i] + 8'd1;
                        end
                    end else begin
                        dbnc_cnt_q[i] <= 8'd0;
                    end
                end
            end
        end
    end

    // ---- hold / auto repeat ---------------------------------------------
    logic [15:0] hold_cnt_q[WIDTH];
    logic [15:0] rep_cnt_q[WIDTH];
    logic [WIDTH-1:0] rep_pulse;
    logic [15:0] repeat_delay_q, repeat_period_q;
    logic [15:0] last_hold_q;
    logic [4:0] last_idx_q;
    always_ff @(posedge clk) begin
        rep_pulse <= '0;
        if (rst) begin
            for (i = 0; i < WIDTH; i = i + 1) begin
                hold_cnt_q[i] <= 16'd0;
                rep_cnt_q[i] <= 16'd0;
            end
            last_hold_q <= 16'd0;
            last_idx_q <= 5'd0;
        end else begin
            if (tick) begin
                for (i = 0; i < WIDTH; i = i + 1) begin
                    if (press_pulse[i]) last_idx_q <= 5'(i);
                    if (press_pulse[i]) begin
                        hold_cnt_q[i] <= 16'd0;
                        rep_cnt_q[i] <= repeat_delay_q;
                    end else if (stable_q[i]) begin
                        if (hold_cnt_q[i] != 16'hffff)
                            hold_cnt_q[i] <= hold_cnt_q[i] + 16'd1;
                        if (rep_cnt_q[i] != 16'd0) begin
                            rep_cnt_q[i] <= rep_cnt_q[i] - 16'd1;
                            if (rep_cnt_q[i] == 16'd1) begin
                                rep_pulse[i] <= 1'b1;
                                rep_cnt_q[i] <= (repeat_period_q == 16'd0) ? 16'd1 : repeat_period_q;
                            end
                        end
                    end else begin
                        hold_cnt_q[i] <= 16'd0;
                        rep_cnt_q[i] <= 16'd0;
                    end
                end
                last_hold_q <= hold_cnt_q[last_idx_q];
            end
        end
    end

    // ---- sticky event registers -----------------------------------------
    // The W1C clear is applied in this same block: a register may only be
    // driven from one always block (PDS rejects anything else).
    logic [WIDTH-1:0] pressed_q, released_q, repeat_q;
    logic clear_press, clear_release, clear_repeat;
    always_ff @(posedge clk) begin
        if (rst) begin
            pressed_q <= '0;
            released_q <= '0;
            repeat_q <= '0;
        end else begin
            if (clear_press)
                pressed_q <= (pressed_q | press_pulse) & ~req_wdata[WIDTH-1:0];
            else
                pressed_q <= pressed_q | press_pulse;
            if (clear_release)
                released_q <= (released_q | release_pulse) & ~req_wdata[WIDTH-1:0];
            else
                released_q <= released_q | release_pulse;
            if (clear_repeat)
                repeat_q <= (repeat_q | rep_pulse) & ~req_wdata[WIDTH-1:0];
            else
                repeat_q <= repeat_q | rep_pulse;
        end
    end

    // ---- MMIO slave ------------------------------------------------------
    logic pending_q;
    // [ARCH] rdata_q：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [31:0] rdata_q;
    // [ARCH] error_q：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rsp_error 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic error_q;
    wire [7:0] off = req_addr[7:0];
    wire access = req_valid && req_ready;
    wire clear_events = req_write && req_wstrb == 4'hf;

    assign clear_press = access && req_write && clear_events && (off == 8'h08);
    assign clear_release = access && req_write && clear_events && (off == 8'h0C);
    assign clear_repeat = access && req_write && clear_events && (off == 8'h10);

    assign req_ready = !rst && !pending_q;
    assign rsp_valid = pending_q;
    assign rsp_rdata = rdata_q;
    assign rsp_error = error_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            pending_q <= 1'b0;
            rdata_q <= 32'd0;
            error_q <= 1'b0;
            debounce_ms_q <= 8'(DEBOUNCE_MS);
            repeat_delay_q <= 16'(REPEAT_DELAY_MS);
            repeat_period_q <= 16'(REPEAT_PERIOD_MS);
        end else begin
            if (pending_q && rsp_ready) pending_q <= 1'b0;
            if (access) begin
                pending_q <= 1'b1;
                error_q <= 1'b0;
                rdata_q <= 32'd0;
                if (req_addr[1:0] != 2'b00) error_q <= 1'b1;
                else if (req_write) begin
                    case (off)
                        8'h08: if (req_wstrb != 4'hf) error_q <= 1'b1;
                        8'h0C: if (req_wstrb != 4'hf) error_q <= 1'b1;
                        8'h10: if (req_wstrb != 4'hf) error_q <= 1'b1;
                        8'h14: if (req_wstrb[0]) debounce_ms_q <= req_wdata[7:0];
                        8'h18: if (req_wstrb[1:0] == 2'b11) repeat_delay_q <= req_wdata[15:0];
                        8'h1C: if (req_wstrb[1:0] == 2'b11) repeat_period_q <= req_wdata[15:0];
                        default: error_q <= 1'b1;
                    endcase
                end else begin
                    case (off)
                        8'h00: rdata_q <= ID_VALUE;
                        8'h04: rdata_q <= {{(32-WIDTH){1'b0}}, stable_q};
                        8'h08: rdata_q <= {{(32-WIDTH){1'b0}}, pressed_q};
                        8'h0C: rdata_q <= {{(32-WIDTH){1'b0}}, released_q};
                        8'h10: rdata_q <= {{(32-WIDTH){1'b0}}, repeat_q};
                        8'h14: rdata_q <= {24'd0, debounce_ms_q};
                        8'h18: rdata_q <= {16'd0, repeat_delay_q};
                        8'h1C: rdata_q <= {16'd0, repeat_period_q};
                        8'h20: rdata_q <= ms_q;
                        8'h24: rdata_q <= {16'd0, last_hold_q};
                        default: error_q <= 1'b1;
                    endcase
                end
            end
        end
    end

    initial begin
        if (WIDTH < 1 || WIDTH > 32) $fatal(1, "GAME_INPUT_BAD_WIDTH");
        if (TICK_DIV < 2) $fatal(1, "GAME_INPUT_BAD_TICK");
    end
endmodule
