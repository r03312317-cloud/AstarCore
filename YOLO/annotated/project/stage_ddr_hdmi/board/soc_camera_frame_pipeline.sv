// One OV5640 DVP RGB565 frame to the shared uncached DDR window.
// The capture clock is supplied by the sensor; all AXI signals use mem_clk.
// A failed frame is never published as valid. Stale FIFO pixels are drained
// before another arm is accepted, including after an overlong sensor frame.
// 架构导读：soc_camera_frame_pipeline。
// 连接摄像头采集、跨时钟缓存和 DDR 写入路径。
module soc_camera_frame_pipeline #(
    // 静态配置：parameter int WIDTH=1280, HEIGHT=720。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int WIDTH=1280, HEIGHT=720,
    // 静态配置：parameter logic [31:0] DDR_BASE=32'h8000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BASE=32'h8000_0000,
    // 静态配置：parameter logic [31:0] DDR_BYTES=32'h0400_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BYTES=32'h0400_0000
)(
    // 接口声明：input logic pclk, mem_clk, arst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic pclk, mem_clk, arst,
    // 接口声明：input logic start。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic start,
    // 接口声明：input logic [31:0] frame_base。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input logic [31:0] frame_base,
    // 接口声明：input logic vsync, href。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic vsync, href,
    // 接口声明：input logic [7:0] byte_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [7:0] byte_data,
    // 接口声明：output logic ready, busy, done_pulse, frame_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic ready, busy, done_pulse, frame_valid,
    // 接口声明：output logic [7:0] error_sticky。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    output logic [7:0] error_sticky,
    // 接口声明：output logic [31:0] pixels_written, sensor_pixels。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [31:0] pixels_written, sensor_pixels,
    // 接口声明：output logic [3:0] m_awid。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] m_awid,
    // 接口声明：output logic [31:0] m_awaddr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] m_awaddr,
    // 接口声明：output logic [7:0] m_awlen。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [7:0] m_awlen,
    // 接口声明：output logic [2:0] m_awsize。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [2:0] m_awsize,
    output logic [1:0] m_awburst,
    output logic m_awvalid,
    input logic m_awready,
    output logic [127:0] m_wdata,
    output logic [15:0] m_wstrb,
    output logic m_wlast, m_wvalid,
    input logic m_wready,
    input logic [3:0] m_bid,
    input logic [1:0] m_bresp,
    input logic m_bvalid,
    output logic m_bready
);
    timeunit 1ns; timeprecision 1ps;
    typedef enum logic [1:0] {IDLE,RUN,RELEASE} state_t;
    state_t state;
    logic mem_rst,pclk_rst,arm_q,arm_seen_pclk,arm_seen_mem;
    logic capture_valid,capture_ready,capture_done_toggle,capture_bad_hold;
    logic [15:0] capture_data, fifo_data;
    logic vsync_sample,href_sample;
    logic [7:0] byte_sample;
    logic [31:0] capture_pixels_hold;
    logic fifo_valid,fifo_ready,writer_ready,writer_busy,writer_done;
    logic writer_frame_valid,writer_sensor_done,sensor_bad_q;
    logic [7:0] writer_error;
    logic done_sync,done_at_start,bad_sync;
    wire launch=start && ready;
    pg_reset_sync u_mem_reset(.clk(mem_clk),.arst,.rst(mem_rst));
    pg_reset_sync u_pclk_reset(.clk(pclk),.arst,.rst(pclk_rst));
    pg_level_sync u_done_sync(.clk(mem_clk),.rst(mem_rst),
        .async_level(capture_done_toggle),.level(done_sync));
    pg_level_sync u_bad_sync(.clk(mem_clk),.rst(mem_rst),
        .async_level(capture_bad_hold),.level(bad_sync));
    pg_level_sync u_arm_to_pclk(.clk(pclk),.rst(pclk_rst),
        .async_level(arm_q),.level(arm_seen_pclk));
    pg_level_sync u_arm_to_mem(.clk(mem_clk),.rst(mem_rst),
        .async_level(arm_seen_pclk),.level(arm_seen_mem));
    // Give all DVP inputs one common capture edge before the frame parser.
    // This removes raw VSYNC/HREF from deep clock-enable cones and keeps byte
    // data aligned to the corresponding sampled qualifiers.
    always_ff @(posedge pclk)begin
        vsync_sample<=vsync;href_sample<=href;byte_sample<=byte_data;
    end
    soc_camera_dvp_capture #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) capture(
        .pclk,.arst,.arm(arm_q),.vsync(vsync_sample),.href(href_sample),
        .byte_data(byte_sample),
        .pixel_valid(capture_valid),.pixel_ready(capture_ready),
        .pixel_data(capture_data),.done_toggle(capture_done_toggle),
        .bad_hold(capture_bad_hold),.pixels_hold(capture_pixels_hold));
    soc_camera_async_fifo #(.WIDTH(16),.DEPTH(1024)) fifo(
        .wr_clk(pclk),.rd_clk(mem_clk),.arst,
        .in_valid(capture_valid),.in_ready(capture_ready),.in_data(capture_data),
        .out_valid(fifo_valid),.out_ready(fifo_ready),.out_data(fifo_data));
    assign fifo_ready=writer_ready || (state==RELEASE);
    soc_camera_axi_writer #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES),
        .MAX_PIXELS(WIDTH*HEIGHT)) writer(
        .clk(mem_clk),.rst(mem_rst),.start(launch),.frame_base,
        .frame_pixels(32'(WIDTH*HEIGHT)),
        .sensor_done(writer_sensor_done),.sensor_bad(sensor_bad_q),
        .pixel_valid(fifo_valid && state==RUN),.pixel_ready(writer_ready),
        .pixel_data(fifo_data),.busy(writer_busy),.done_pulse(writer_done),
        .frame_valid(writer_frame_valid),.error_sticky(writer_error),
        .pixels_written,.m_awid,.m_awaddr,.m_awlen,.m_awsize,.m_awburst,
        .m_awvalid,.m_awready,.m_wdata,.m_wstrb,.m_wlast,.m_wvalid,.m_wready,
        .m_bid,.m_bresp,.m_bvalid,.m_bready);
    assign ready=(state==IDLE) && !mem_rst;
    assign busy=(state!=IDLE);
    assign frame_valid=writer_frame_valid;
    assign error_sticky=writer_error;
    // 过程边界：always_ff @(posedge mem_clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge mem_clk) begin
        done_pulse<=0;
        // 复位相关判断：mem_rst；分支方向由信号极性与取反表达式决定。
        if(mem_rst)begin
            state<=IDLE;arm_q<=0;done_at_start<=0;
            writer_sensor_done<=0;sensor_bad_q<=0;sensor_pixels<=0;
        end else begin
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case(state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if(launch)begin
                    state<=RUN;arm_q<=1;done_at_start<=done_sync;
                    writer_sensor_done<=0;sensor_bad_q<=0;sensor_pixels<=0;
                end
                // 状态/选择分支 RUN：本分支规定该编码下的寄存器更新和下一步动作。
                RUN: begin
                    if(done_sync!=done_at_start && !writer_sensor_done)begin
                        writer_sensor_done<=1;
                        sensor_bad_q<=bad_sync;
                        // The PCLK count is held from the done toggle until
                        // a later arm. This is a bundled-data CDC sample.
                        sensor_pixels<=capture_pixels_hold;
                    end
                    if(writer_done)begin
                        done_pulse<=1;arm_q<=0;state<=RELEASE;
                    end
                end
                // 状态/选择分支 RELEASE：本分支规定该编码下的寄存器更新和下一步动作。
                RELEASE: if(!arm_seen_mem && !fifo_valid && !writer_busy)
                    state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
    initial if(WIDTH<8 || HEIGHT<1 || WIDTH*HEIGHT>32'h7fff_ffff)
        $fatal(1,"CAMERA_FRAME_PIPELINE_DIMENSION");
endmodule
