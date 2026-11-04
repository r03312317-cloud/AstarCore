// Camera-enabled board candidate; the verified monitor/CoreMark top remains
// frozen separately as soc_board_top. This variant adds OV5640 DVP and a
// second DDR AXI master behind the shared HMIC adapter.
// 架构导读：soc_board_camera_top。
// 板级集成顶层，连接双路摄像头引脚、共享 DDR、SoC 和 HDMI；本轮软件选用 CMOS2 通道。
module soc_board_camera_top #(
 // 静态配置：parameter ITCM_INIT_FILE="coremark-itcm.mem"。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter ITCM_INIT_FILE="coremark-itcm.mem",
 // 静态配置：parameter DTCM_INIT_FILE="coremark-dtcm.mem"。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter DTCM_INIT_FILE="coremark-dtcm.mem",
 // 静态配置：parameter bit S3_BURST_ENABLE=1'b1。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter bit S3_BURST_ENABLE=1'b1 // one coherent compile-time rollback switch
)(
 // 接口声明：input logic sys_clk,clk_p,clk_n,rst_in,uart_rx。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic sys_clk,clk_p,clk_n,rst_in,uart_rx,
 // 接口声明：input logic camera_clk_0,camera_href_0,camera_vsync_0。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic camera_clk_0,camera_href_0,camera_vsync_0,
 // 接口声明：input logic [7:0] camera_data_0。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 input logic [7:0] camera_data_0,
 // 接口声明：input logic camera_clk_1,camera_href_1,camera_vsync_1。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic camera_clk_1,camera_href_1,camera_vsync_1,
 // 接口声明：input logic [7:0] camera_data_1。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 input logic [7:0] camera_data_1,
 // 接口声明：inout wire SCL_0,SDA_0,SCL_1,SDA_1。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 inout wire SCL_0,SDA_0,SCL_1,SDA_1,
 // 接口声明：output logic cam_rst_0,cam_rst_1。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 output logic cam_rst_0,cam_rst_1,
 // 接口声明：output logic uart_tx。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic uart_tx,
 // 接口声明：output logic [7:0] led。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [7:0] led,
 // 接口声明：output wire [2:0] tmds_data_p,tmds_data_n。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 output wire [2:0] tmds_data_p,tmds_data_n,
 // 接口声明：output wire tmds_clk_p,tmds_clk_n。
 // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
 output wire tmds_clk_p,tmds_clk_n,
 // 接口声明：output logic mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_cs_n。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_cs_n,
 // 接口声明：output logic mem_ras_n,mem_cas_n,mem_we_n,mem_odt。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic mem_ras_n,mem_cas_n,mem_we_n,mem_odt,
 // 接口声明：output logic [14:0] mem_a。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [14:0] mem_a,
 // 接口声明：output logic [2:0] mem_ba。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [2:0] mem_ba,
 // 接口声明：inout wire [3:0] mem_dqs,mem_dqs_n。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 inout wire [3:0] mem_dqs,mem_dqs_n,
 // 接口声明：inout wire [31:0] mem_dq。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 inout wire [31:0] mem_dq,
 // 接口声明：output logic [3:0] mem_dm。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [3:0] mem_dm
);
 // Regional synchronous reset distribution; identity LUTs add no clock cycle.
 // Targeted preservation applies only to these drivers, not to their loads.
 (* syn_keep=1 *) wire region_reset_s3_registers;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_s3_registers(.I0(mem_reset),.Z(region_reset_s3_registers));
 (* syn_keep=1 *) wire region_reset_s3_engine;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_s3_engine(.I0(mem_reset),.Z(region_reset_s3_engine));
 (* syn_keep=1 *) wire region_reset_window_registers;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_window_registers(.I0(mem_reset),.Z(region_reset_window_registers));
 (* syn_keep=1 *) wire region_reset_window_engine;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_window_engine(.I0(mem_reset),.Z(region_reset_window_engine));
 (* syn_keep=1 *) wire region_reset_concat_registers;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_concat_registers(.I0(mem_reset),.Z(region_reset_concat_registers));
 (* syn_keep=1 *) wire region_reset_concat_engine;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_concat_engine(.I0(mem_reset),.Z(region_reset_concat_engine));
 (* syn_keep=1 *) wire region_reset_s3_axi;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_s3_axi(.I0(mem_reset),.Z(region_reset_s3_axi));
 (* syn_keep=1 *) wire region_reset_v2_replay;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_v2_replay(.I0(mem_reset),.Z(region_reset_v2_replay));
 (* syn_keep=1 *) wire region_reset_v2_share;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_v2_share(.I0(mem_reset),.Z(region_reset_v2_share));
 (* syn_keep=1 *) wire region_reset_video_share;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_video_share(.I0(mem_reset),.Z(region_reset_video_share));
 (* syn_keep=1 *) wire region_reset_s3_share;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_s3_share(.I0(mem_reset),.Z(region_reset_s3_share));
 (* syn_keep=1 *) wire region_reset_camera_share;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_camera_share(.I0(mem_reset),.Z(region_reset_camera_share));

timeunit 1ns;timeprecision 1ps;
// 局部字段 logic ref_clk,mem_clk,cpu_clk_fast,npu_clk_fast,cpu_pll_lock,npu_pll_lock。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic ref_clk,mem_clk,cpu_clk_fast,npu_clk_fast,cpu_pll_lock,npu_pll_lock;

// 局部字段 wire arst。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
wire arst;
// 局部字段 logic hdmi_pixel_clk,hdmi_serial_clk,hdmi_pll_locked,hdmi_pixel_reset_n,hdmi_pixel_reset,hdmi_serial_r...。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
logic hdmi_pixel_clk,hdmi_serial_clk,hdmi_pll_locked,hdmi_pixel_reset_n,hdmi_pixel_reset,hdmi_serial_reset;
// 局部字段 logic [63:0] cpu_time_gray。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [63:0] cpu_time_gray;
// 局部字段 logic [1:0] video_mode。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [1:0] video_mode;
// 局部字段 logic publish_valid,publish_ready,pending_display_valid,displayed_valid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic publish_valid,publish_ready,pending_display_valid,displayed_valid;
// 局部字段 logic [31:0] publish_fb,publish_frame,publish_run,publish_xy1,publish_xy2。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] publish_fb,publish_frame,publish_run,publish_xy1,publish_xy2;
// 局部字段 logic [31:0] publish_score,publish_class,publish_count,publish_sequence。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] publish_score,publish_class,publish_count,publish_sequence;
// 局部字段 logic [31:0] pending_display_fb,displayed_fb,displayed_frame,displayed_run。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] pending_display_fb,displayed_fb,displayed_frame,displayed_run;
// 局部字段 logic [23:0] video_rgb。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [23:0] video_rgb;
// 局部字段 logic video_de,video_hs,video_vs,event_tc,event_th,event_te,te_good。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic video_de,video_hs,video_vs,event_tc,event_th,event_te,te_good;
// 局部字段 logic [63:0] tc_ticks,th_ticks,te_ticks。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [63:0] tc_ticks,th_ticks,te_ticks;
// 局部字段 logic [31:0] tc_frame,tc_run,th_frame,th_run,te_frame,te_run。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] tc_frame,tc_run,th_frame,th_run,te_frame,te_run;
// 局部字段 logic [31:0] stat_underflow,stat_mismatch,stat_presented,stat_max_ddr_wait,stat_fifo_high,stat_fifo_low。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] stat_underflow,stat_mismatch,stat_presented,stat_max_ddr_wait,stat_fifo_high,stat_fifo_low;
// 局部字段 logic [7:0] video_fault。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic [7:0] video_fault;
soc_mini_hdmi_clock u_hdmi_clock(.sys_clk,.reset_n(rst_in),
 .pixel_clk(hdmi_pixel_clk),.serial_clk(hdmi_serial_clk),.pll_locked(hdmi_pll_locked),.pixel_reset_n(hdmi_pixel_reset_n));
// HDMI lock loss participates in common reset, so no accepted AXI ownership
// is abandoned by resetting just the display reader. PLL generation itself
// is independent of arst; there is no reset/PLL-lock feedback loop.
soc_reset_sync u_hdmi_pixel_reset(.clk(hdmi_pixel_clk),.arst,.rst(hdmi_pixel_reset));
soc_reset_sync u_hdmi_serial_reset(.clk(hdmi_serial_clk),.arst,.rst(hdmi_serial_reset));

// 局部字段 logic cpu_reset,npu_reset,mem_reset,board27_reset,ddr_ref_reset。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
logic cpu_reset,npu_reset,mem_reset,board27_reset,ddr_ref_reset;
// 局部字段 logic ddr_init_done,ddr_ready,ddr_pll_lock,ddr_phy_lock,ddr_cal_fail。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic ddr_init_done,ddr_ready,ddr_pll_lock,ddr_phy_lock,ddr_cal_fail;
// 局部字段 logic adapter_fault,adapter_fault_cpu,ddr_ready_cpu,cal_fail_cpu。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic adapter_fault,adapter_fault_cpu,ddr_ready_cpu,cal_fail_cpu;
// 局部字段 logic soc_fault,ddr_fault,fatal_state,sleeping。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic soc_fault,ddr_fault,fatal_state,sleeping;
// 局部字段 logic [31:0] gpio_out,diag_mailbox。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] gpio_out,diag_mailbox;
// 局部字段 logic unused_aux_tx。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic unused_aux_tx;
// 局部字段 logic camera_init_done,camera_ready,camera_busy,camera_done,camera_valid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic camera_init_done,camera_ready,camera_busy,camera_done,camera_valid;
// 局部字段 logic [7:0] camera_errors。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic [7:0] camera_errors;
// 局部字段 logic [31:0] camera_pixels_written,camera_sensor_pixels,camera_frame_base。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [31:0] camera_pixels_written,camera_sensor_pixels,camera_frame_base;
// 局部字段 logic camera_start。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic camera_start;
// 局部字段 logic camera_diag_snapshot。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic camera_diag_snapshot;
// 局部字段 logic [511:0] camera_diag_words。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [511:0] camera_diag_words;
// 局部字段 logic camera_init_done_1,camera_init_mem_1,camera_diag_snapshot_1。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic camera_init_done_1,camera_init_mem_1,camera_diag_snapshot_1;
// 局部字段 logic [511:0] camera_diag_words_1。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [511:0] camera_diag_words_1;
// 局部字段 logic auto_scl_0,auto_sda_0,auto_scl_1,auto_sda_1。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic auto_scl_0,auto_sda_0,auto_scl_1,auto_sda_1;
// 局部字段 logic [5:0] sccb_control。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [5:0] sccb_control;
// Separate CSR fanout from the slow open-drain pin drive. All six bits move
// together in the existing DDR UI domain; auto SCCB waveforms are unchanged.
// The CPU SCCB driver waits 10us after every write, far longer than this one
// UI cycle. Retain immediate reset ownership release in the output mux.
(* keep="true" *) logic [5:0] sccb_pin_control;
// 过程边界：always_ff @(posedge mem_clk)begin。
// 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
always_ff @(posedge mem_clk)begin
 // 复位相关判断：mem_reset；分支方向由信号极性与取反表达式决定。
 if(mem_reset)sccb_pin_control<=0;
 else sccb_pin_control<=sccb_control;
end
// 局部字段 logic [31:0] camera_io_meta,camera_io_levels。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] camera_io_meta,camera_io_levels;
// Runtime diagnostics drive only low, release for ACK and sensor read data.
// Boot configuration keeps its original waveform; manual access starts after
// both sequencers finish. MMIO control is held in the UI domain and bit-banged
// at <=50kHz; external return levels use two UI synchronization stages.
assign SCL_0=(sccb_pin_control[0]&&!arst) ? (sccb_pin_control[2]?1'b0:1'bz) : auto_scl_0;
// 组合连接 SDA_0：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
assign SDA_0=(sccb_pin_control[0]&&!arst) ? (sccb_pin_control[3]?1'b0:1'bz) : auto_sda_0;
// 组合连接 SCL_1：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
assign SCL_1=(sccb_pin_control[1]&&!arst) ? (sccb_pin_control[4]?1'b0:1'bz) : auto_scl_1;
// 组合连接 SDA_1：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
assign SDA_1=(sccb_pin_control[1]&&!arst) ? (sccb_pin_control[5]?1'b0:1'bz) : auto_sda_1;
// 过程边界：always_ff @(posedge mem_clk) begin。
// 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
always_ff @(posedge mem_clk) begin
 // 复位相关判断：mem_reset；分支方向由信号极性与取反表达式决定。
 if(mem_reset)begin camera_io_meta<=0;camera_io_levels<=0;end
 else begin
  camera_io_meta<={6'b0,camera_vsync_1,camera_href_1,camera_clk_1,
   camera0_diag_sync_held[1],camera0_diag_sync_held[0],camera_clk_0,16'b0,
   SDA_1,SCL_1,SDA_0,SCL_0};
  camera_io_levels<=camera_io_meta;
 end
end
// 局部字段 wire [7:0] camera_data_held。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
wire [7:0] camera_data_held;
// 局部字段 wire [1:0] camera0_diag_sync_held。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
wire [1:0] camera0_diag_sync_held;
// Camera0 diagnostics previously sampled HREF directly and failed hold by
// 131ps in both corners. Delay both sync inputs equally without a clock-cycle
// pipeline. Both diagnostics and the UI snapshot use the delayed outputs:
// the native I/O delay requires an exclusive connection from each IBUF.
soc_camera_input_hold #(.WIDTH(2),.HOLD_SET("500ps")) camera0_diag_hold(
 .data_in({camera_vsync_0,camera_href_0}),.data_out(camera0_diag_sync_held));
// Retain the original DVP capture edge and conservative input min delay.
// A supported, fixed I/O hold element delays data physically, not by adding
// a protocol cycle. Full setup and hold checks remain required after route.
soc_camera_input_hold camera_input_hold(.data_in(camera_data_1),.data_out(camera_data_held));
// 局部字段 logic board_req_valid,board_req_ready,board_req_write,board_req_fetch。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic board_req_valid,board_req_ready,board_req_write,board_req_fetch;
// 局部字段 logic [31:0] board_req_addr,board_req_wdata,board_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] board_req_addr,board_req_wdata,board_rsp_rdata;
// 局部字段 logic [3:0] board_req_wstrb。
// 按字节选择本次写入生效的 lane。
logic [3:0] board_req_wstrb;
// 局部字段 logic board_rsp_valid,board_rsp_ready,board_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic board_rsp_valid,board_rsp_ready,board_rsp_error;
// 局部字段 logic cam_mem_req_valid,cam_mem_req_ready,cam_mem_req_write。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic cam_mem_req_valid,cam_mem_req_ready,cam_mem_req_write;
// 局部字段 logic [15:0] cam_mem_req_addr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [15:0] cam_mem_req_addr;
// 局部字段 logic [31:0] cam_mem_req_wdata,cam_mem_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] cam_mem_req_wdata,cam_mem_rsp_rdata;
// 局部字段 logic [3:0] cam_mem_req_wstrb。
// 按字节选择本次写入生效的 lane。
logic [3:0] cam_mem_req_wstrb;
// 局部字段 logic cam_mem_rsp_valid,cam_mem_rsp_ready,cam_mem_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic cam_mem_rsp_valid,cam_mem_rsp_ready,cam_mem_rsp_error;
// 局部字段 logic cam_unit_req_ready,cam_unit_rsp_valid,cam_unit_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic cam_unit_req_ready,cam_unit_rsp_valid,cam_unit_rsp_error;
// 局部字段 logic [31:0] cam_unit_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] cam_unit_rsp_rdata;
// 局部字段 logic s3_mem_req_ready,s3_mem_rsp_valid,s3_mem_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic s3_mem_req_ready,s3_mem_rsp_valid,s3_mem_rsp_error;
// 局部字段 logic [31:0] s3_mem_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] s3_mem_rsp_rdata;
// 局部字段 logic s2_mem_req_ready,s2_mem_rsp_valid,s2_mem_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic s2_mem_req_ready,s2_mem_rsp_valid,s2_mem_rsp_error;
// 局部字段 logic [31:0] s2_mem_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] s2_mem_rsp_rdata;
// 局部字段 logic [2:0] mmio_response_owner。
// 跟踪存储/事务所有权，释放条件由对应完成分支决定。
logic [2:0] mmio_response_owner;
// 局部字段 logic display_mem_req_ready,display_mem_rsp_valid,display_mem_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic display_mem_req_ready,display_mem_rsp_valid,display_mem_rsp_error;
// 局部字段 logic [31:0] display_mem_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] display_mem_rsp_rdata;
// 局部字段 logic win_mem_req_ready,win_mem_rsp_valid,win_mem_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic win_mem_req_ready,win_mem_rsp_valid,win_mem_rsp_error;
// 局部字段 logic [31:0] win_mem_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] win_mem_rsp_rdata;
// 局部字段 logic concat_mem_req_ready,concat_mem_rsp_valid,concat_mem_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic concat_mem_req_ready,concat_mem_rsp_valid,concat_mem_rsp_error;
// 局部字段 logic [31:0] concat_mem_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] concat_mem_rsp_rdata;
// 局部字段 logic concat_irq_mem,concat_irq_cpu。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic concat_irq_mem,concat_irq_cpu;
// 局部字段 logic video_mem_req_ready,video_mem_rsp_valid,video_mem_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic video_mem_req_ready,video_mem_rsp_valid,video_mem_rsp_error;
// 局部字段 logic [31:0] video_mem_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] video_mem_rsp_rdata;
// 局部字段 logic image_mem_req_ready,image_mem_rsp_valid,image_mem_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic image_mem_req_ready,image_mem_rsp_valid,image_mem_rsp_error;
// 局部字段 logic [31:0] image_mem_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] image_mem_rsp_rdata;
wire [2:0] mmio_request_unit=cam_mem_req_addr[11:8]==4'h7 ? 3'd7 :
 cam_mem_req_addr[11:8]==4'h4 ? 3'd6 :
 cam_mem_req_addr[11:8]==4'h3 ? 3'd5 :
 cam_mem_req_addr[11:8]==4'h1 ? 3'd1 :
 cam_mem_req_addr[11:8]==4'h2 ? 3'd2 :
 cam_mem_req_addr[11:8]==4'h5 ? 3'd3 :
 cam_mem_req_addr[11:8]==4'h6 ? 3'd4 : 3'd0;
// The DDR PHY lock signals start low while it calibrates, so arm their
// monitor only after the controller has first reported a usable user port.
// A later DDR PLL loss latches a common reset until KEY0 is pressed. This
// avoids a reset/recalibration feedback loop when the PHY clock is unstable.
logic ddr_ready_ref_meta,ddr_ready_ref,ddr_pll_ref_meta,ddr_pll_ref;
// 局部字段 logic ddr_phy_ref_meta,ddr_phy_ref,ddr_ready_seen_ref,ddr_lock_fault_q。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic ddr_phy_ref_meta,ddr_phy_ref,ddr_ready_seen_ref,ddr_lock_fault_q;
// 过程边界：always_ff @(posedge ref_clk or negedge rst_in or negedge cpu_pll_lock or negedge npu_pll_lock) begin。
// 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
always_ff @(posedge ref_clk or negedge rst_in or negedge cpu_pll_lock or negedge npu_pll_lock) begin
 // 复位相关判断：!rst_in || !cpu_pll_lock || !npu_pll_lock；分支方向由信号极性与取反表达式决定。
 if(!rst_in || !cpu_pll_lock || !npu_pll_lock) begin
  ddr_ready_ref_meta<=0;ddr_ready_ref<=0;
  ddr_pll_ref_meta<=0;ddr_pll_ref<=0;
  ddr_phy_ref_meta<=0;ddr_phy_ref<=0;
  ddr_ready_seen_ref<=0;ddr_lock_fault_q<=0;
 end else begin
  ddr_ready_ref_meta<=ddr_ready;ddr_ready_ref<=ddr_ready_ref_meta;
  ddr_pll_ref_meta<=ddr_pll_lock;ddr_pll_ref<=ddr_pll_ref_meta;
  ddr_phy_ref_meta<=ddr_phy_lock;ddr_phy_ref<=ddr_phy_ref_meta;
  // 条件分支：检查 ddr_ready_ref。
  if(ddr_ready_ref)ddr_ready_seen_ref<=1;
  // 条件分支：检查 ddr_ready_seen_ref && (!ddr_pll_ref || !ddr_phy_ref)。
  if(ddr_ready_seen_ref && (!ddr_pll_ref || !ddr_phy_ref))ddr_lock_fault_q<=1;
 end
end
// Any PLL loss aborts all in-flight SoC/AXI traffic and restarts HMIC too.
assign arst=!rst_in || !cpu_pll_lock || !npu_pll_lock || !hdmi_pll_locked || ddr_lock_fault_q;
soc_cpu70_pll_probe u_cpu_pll(.clkin1(ref_clk),.clkout1(cpu_clk_fast),.lock(cpu_pll_lock));
soc_cpu100_pll_probe u_npu_pll(.clkin1(ref_clk),.clkout1(npu_clk_fast),.lock(npu_pll_lock));
// Pin and input buffer settings copied from the official 200K camera top.
GTP_INBUFGDS #(.IOSTANDARD("DEFAULT"),.TERM_DIFF("ON")) u_refclk(
 .O(ref_clk),.I(clk_p),.IB(clk_n));
soc_reset_sync u_board27_reset(.clk(sys_clk),.arst,.rst(board27_reset));
soc_reset_sync u_ddr_ref_reset(.clk(ref_clk),.arst,.rst(ddr_ref_reset));
// Sample calibration state only in the HMIC user domain. Common board reset
// clears the controller and every SoC CDC queue; fault recovery needs reset.
always_ff @(posedge mem_clk or posedge arst)
 // 复位相关判断：arst；分支方向由信号极性与取反表达式决定。
 if(arst)ddr_ready<=0;
 else ddr_ready<=ddr_init_done&&ddr_pll_lock&&ddr_phy_lock&&!ddr_cal_fail;
pg_level_sync u_adapter_fault_sync(.clk(cpu_clk_fast),.rst(cpu_reset),.async_level(adapter_fault),.level(adapter_fault_cpu));
pg_level_sync u_ready_sync(.clk(cpu_clk_fast),.rst(cpu_reset),.async_level(ddr_ready),.level(ddr_ready_cpu));
pg_level_sync u_cal_fault_sync(.clk(cpu_clk_fast),.rst(cpu_reset),.async_level(ddr_cal_fail),.level(cal_fail_cpu));
// LED status is held in the CPU domain, then each level is synchronized
// into the 27 MHz board/display domain before the output register.
logic [7:0] led_cpu,led_27;
// 组合连接 led_cpu：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
assign led_cpu={fatal_state|adapter_fault_cpu|soc_fault|ddr_fault,
                cal_fail_cpu,ddr_ready_cpu,!cpu_reset,gpio_out[3:0]};
// 按 genvar l=0;l<8;l++ 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
for(genvar l=0;l<8;l++)begin:led_cdc
 pg_level_sync u_sync(.clk(sys_clk),.rst(board27_reset),
                      .async_level(led_cpu[l]),.level(led_27[l]));
end
// 过程边界：always_ff @(posedge sys_clk)。
// 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
always_ff @(posedge sys_clk)
 // 复位相关判断：board27_reset；分支方向由信号极性与取反表达式决定。
 if(board27_reset) led<=8'd0;
 else led<=led_27;
// 局部字段 logic [3:0] s_awid。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [3:0] s_awid;
// 局部字段 logic [31:0] s_awaddr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [31:0] s_awaddr;
// 局部字段 logic [7:0] s_awlen。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] s_awlen;
// 局部字段 logic [2:0] s_awsize。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [2:0] s_awsize;
// 局部字段 logic [1:0] s_awburst。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
logic [1:0] s_awburst;
// 局部字段 logic s_awvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic s_awvalid;
// 局部字段 logic s_awready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic s_awready;
// 局部字段 logic [127:0] s_wdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [127:0] s_wdata;
// 局部字段 logic [15:0] s_wstrb。
// 按字节选择本次写入生效的 lane。
logic [15:0] s_wstrb;
// 局部字段 logic s_wlast,s_wvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic s_wlast,s_wvalid;
// 局部字段 logic s_wready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic s_wready;
// 局部字段 logic [3:0] s_bid。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [3:0] s_bid;
// 局部字段 logic [1:0] s_bresp。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [1:0] s_bresp;
// 局部字段 logic s_bvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic s_bvalid;
// 局部字段 logic s_bready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic s_bready;
// 局部字段 logic [3:0] s_arid。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [3:0] s_arid;
// 局部字段 logic [31:0] s_araddr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [31:0] s_araddr;
// 局部字段 logic [7:0] s_arlen。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] s_arlen;
// 局部字段 logic [2:0] s_arsize。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [2:0] s_arsize;
// 局部字段 logic [1:0] s_arburst。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
logic [1:0] s_arburst;
// 局部字段 logic s_arvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic s_arvalid;
// 局部字段 logic s_arready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic s_arready;
// 局部字段 logic [3:0] s_rid。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [3:0] s_rid;
// 局部字段 logic [127:0] s_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [127:0] s_rdata;
// 局部字段 logic [1:0] s_rresp。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [1:0] s_rresp;
// 局部字段 logic s_rlast,s_rvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic s_rlast,s_rvalid;
// 局部字段 logic s_rready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic s_rready;
// 局部字段 logic [7:0] m_awid。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] m_awid;
// 局部字段 logic [29:0] m_awaddr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [29:0] m_awaddr;
// 局部字段 logic [7:0] m_awlen。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] m_awlen;
// 局部字段 logic [2:0] m_awsize。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [2:0] m_awsize;
// 局部字段 logic [1:0] m_awburst。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
logic [1:0] m_awburst;
// 局部字段 logic m_awvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic m_awvalid;
// 局部字段 logic m_awready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic m_awready;
// 局部字段 logic [255:0] m_wdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [255:0] m_wdata;
// 局部字段 logic [31:0] m_wstrb。
// 按字节选择本次写入生效的 lane。
logic [31:0] m_wstrb;
// 局部字段 logic m_wlast,m_wvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic m_wlast,m_wvalid;
// 局部字段 logic m_wready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic m_wready;
// 局部字段 logic [7:0] m_bid。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] m_bid;
// 局部字段 logic [1:0] m_bresp。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [1:0] m_bresp;
// 局部字段 logic m_bvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic m_bvalid;
// 局部字段 logic m_bready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic m_bready;
// 局部字段 logic [7:0] m_arid。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] m_arid;
// 局部字段 logic [29:0] m_araddr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [29:0] m_araddr;
// 局部字段 logic [7:0] m_arlen。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] m_arlen;
// 局部字段 logic [2:0] m_arsize。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [2:0] m_arsize;
// 局部字段 logic [1:0] m_arburst。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
logic [1:0] m_arburst;
// 局部字段 logic m_arvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic m_arvalid;
// 局部字段 logic m_arready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic m_arready;
// 局部字段 logic [7:0] m_rid。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] m_rid;
// 局部字段 logic [255:0] m_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [255:0] m_rdata;
// 局部字段 logic [1:0] m_rresp。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [1:0] m_rresp;
// 局部字段 logic m_rlast,m_rvalid。
// 标识这一路负载有效；是否接收还需检查对应的消费条件。
logic m_rlast,m_rvalid;
// 局部字段 logic m_rready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic m_rready;
soc_soc_top #(.CPU_CLOCK_HZ(70000000),.UART_BAUD(115200),.BOARD_MMIO_ENABLE(1'b1),
 .DMA_TIMEOUT_CYCLES(500000),
 .ITCM_INIT_FILE(ITCM_INIT_FILE),.DTCM_INIT_FILE(DTCM_INIT_FILE)) soc(
 .cpu_clk(cpu_clk_fast),.npu_clk(npu_clk_fast),.mem_clk,.arst,.mem_ready(ddr_ready),
 .cpu_reset,.npu_reset,.mem_reset,.irq_nmi_fault(adapter_fault_cpu),
 .irq_fast_adc(1'b0),.irq_fast_pwm(1'b0),.irq_qei(1'b0),.irq_timer(1'b0),.irq_ipc(1'b0),.irq_platform({7'b0,concat_irq_cpu}),
 .gpio_in({28'b0,cal_fail_cpu,adapter_fault_cpu,ddr_ready_cpu,1'b1}),.gpio_out,.diagnostic_mailbox(diag_mailbox),.uart_tx,.uart_rx,.uart_aux_tx(unused_aux_tx),.timer_gray(cpu_time_gray),
 .board_req_valid,.board_req_ready,.board_req_addr,.board_req_wdata,
 .board_req_write,.board_req_is_fetch(board_req_fetch),.board_req_wstrb,
 .board_rsp_valid,.board_rsp_ready,.board_rsp_rdata,.board_rsp_error,
 .gex_win_req_valid,.gex_win_req_ready,.gex_win_req_addr,.gex_win_req_write,.gex_win_req_wdata,.gex_win_req_wstrb,
 .gex_win_rsp_valid,.gex_win_rsp_ready,.gex_win_rsp_rdata,.gex_win_rsp_error,.gex_locked_out(gex_locked_npu),
 .routing_protocol_fault(soc_fault),.ddr_protocol_fault(ddr_fault),.fatal_state_diag(fatal_state),.core_sleeping(sleeping),
 .m_axi_awid(s_awid),
 .m_axi_awaddr(s_awaddr),
 .m_axi_awlen(s_awlen),
 .m_axi_awsize(s_awsize),
 .m_axi_awburst(s_awburst),
 .m_axi_awvalid(s_awvalid),
 .m_axi_awready(s_awready),
 .m_axi_wdata(s_wdata),
 .m_axi_wstrb(s_wstrb),
 .m_axi_wlast(s_wlast),
 .m_axi_wvalid(s_wvalid),
 .m_axi_wready(s_wready),
 .m_axi_bid(s_bid),
 .m_axi_bresp(s_bresp),
 .m_axi_bvalid(s_bvalid),
 .m_axi_bready(s_bready),
 .m_axi_arid(s_arid),
 .m_axi_araddr(s_araddr),
 .m_axi_arlen(s_arlen),
 .m_axi_arsize(s_arsize),
 .m_axi_arburst(s_arburst),
 .m_axi_arvalid(s_arvalid),
 .m_axi_arready(s_arready),
 .m_axi_rid(s_rid),
 .m_axi_rdata(s_rdata),
 .m_axi_rresp(s_rresp),
 .m_axi_rlast(s_rlast),
 .m_axi_rvalid(s_rvalid),
 .m_axi_rready(s_rready));
soc_ov5640_config sensor_init(.clk_27m(sys_clk),.rst_n(!board27_reset),
 .SCL(auto_scl_0),.SDA(auto_sda_0),.cam_rst_n(cam_rst_0),.init_done(camera_init_done));
soc_ov5640_config sensor_init_1(.clk_27m(sys_clk),.rst_n(!board27_reset),
 .SCL(auto_scl_1),.SDA(auto_sda_1),.cam_rst_n(cam_rst_1),.init_done(camera_init_done_1));
// 局部字段 logic camera_init_mem。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic camera_init_mem;
pg_level_sync u_camera_init_sync(.clk(mem_clk),.rst(mem_reset),
 .async_level(camera_init_done),.level(camera_init_mem));
pg_level_sync u_camera_init_sync_1(.clk(mem_clk),.rst(mem_reset),
 .async_level(camera_init_done_1),.level(camera_init_mem_1));
pg_mmio_cdc camera_register_cdc(.src_clk(cpu_clk_fast),.dst_clk(mem_clk),.arst,
 .s_req_valid(board_req_valid),.s_req_ready(board_req_ready),
 .s_req_addr(board_req_addr[15:0]),.s_req_write(board_req_write),
 .s_req_wdata(board_req_wdata),.s_req_wstrb(board_req_wstrb),
 .s_rsp_valid(board_rsp_valid),.s_rsp_ready(board_rsp_ready),
 .s_rsp_rdata(board_rsp_rdata),.s_rsp_error(board_rsp_error),
 .m_req_valid(cam_mem_req_valid),.m_req_ready(cam_mem_req_ready),
 .m_req_addr(cam_mem_req_addr),.m_req_write(cam_mem_req_write),
 .m_req_wdata(cam_mem_req_wdata),.m_req_wstrb(cam_mem_req_wstrb),
 .m_rsp_valid(cam_mem_rsp_valid),.m_rsp_ready(cam_mem_rsp_ready),
 .m_rsp_rdata(cam_mem_rsp_rdata),.m_rsp_error(cam_mem_rsp_error));
soc_camera_mmio_mem #(.WIDTH(1280),.HEIGHT(720),.CAPTURE_CHANNEL(1),.IMAGE_ACCEL_PRESENT(1)) camera_registers(
 .clk(mem_clk),.rst(mem_reset),.ddr_ready,.camera_init_done(camera_init_mem),
 .req_valid(cam_mem_req_valid && mmio_request_unit==0),.req_ready(cam_unit_req_ready),
 .req_addr(cam_mem_req_addr),.req_write(cam_mem_req_write),
 .req_wdata(cam_mem_req_wdata),.req_wstrb(cam_mem_req_wstrb),
 .rsp_valid(cam_unit_rsp_valid),.rsp_ready(cam_mem_rsp_ready && mmio_response_owner==0),
 .rsp_rdata(cam_unit_rsp_rdata),.rsp_error(cam_unit_rsp_error),
 .start(camera_start),.frame_base(camera_frame_base),
 .camera_ready,.camera_busy,.camera_done,.camera_valid,
 .camera_errors,.pixels_written(camera_pixels_written),
 .sensor_pixels(camera_sensor_pixels),
 .diag_words(camera_diag_words),.diag_snapshot(camera_diag_snapshot),
 .camera_init_done_1(camera_init_mem_1),.diag_words_1(camera_diag_words_1),
 .diag_snapshot_1(camera_diag_snapshot_1),.sccb_control,.camera_io_levels);
soc_camera_dvp_diag camera_diagnostics(
 .pclk(camera_clk_0),.mem_clk,.arst,
 .vsync(camera0_diag_sync_held[1]),.href(camera0_diag_sync_held[0]),
 .snapshot_req(camera_diag_snapshot),.snapshot_words(camera_diag_words));
soc_camera_dvp_diag camera_diagnostics_1(
 .pclk(camera_clk_1),.mem_clk,.arst,
 .vsync(camera_vsync_1),.href(camera_href_1),
 .snapshot_req(camera_diag_snapshot_1),.snapshot_words(camera_diag_words_1));
// 组合连接 cam_mem_req_ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
assign cam_mem_req_ready=mmio_request_unit==7?image_mem_req_ready:
 mmio_request_unit==6?concat_mem_req_ready:
 mmio_request_unit==5?win_mem_req_ready:
 mmio_request_unit==4?video_mem_req_ready:
 mmio_request_unit==3?display_mem_req_ready:
 mmio_request_unit==1?s3_mem_req_ready:
                         mmio_request_unit==2?s2_mem_req_ready:cam_unit_req_ready;
// 组合连接 cam_mem_rsp_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
assign cam_mem_rsp_valid=mmio_response_owner==7?image_mem_rsp_valid:
 mmio_response_owner==6?concat_mem_rsp_valid:
 mmio_response_owner==5?win_mem_rsp_valid:
 mmio_response_owner==4?video_mem_rsp_valid:
 mmio_response_owner==3?display_mem_rsp_valid:
 mmio_response_owner==1?s3_mem_rsp_valid:
                          mmio_response_owner==2?s2_mem_rsp_valid:cam_unit_rsp_valid;
// 组合连接 cam_mem_rsp_rdata：保存/传递数据负载，数据有效性由独立控制字段约束。
assign cam_mem_rsp_rdata=mmio_response_owner==7?image_mem_rsp_rdata:
 mmio_response_owner==6?concat_mem_rsp_rdata:
 mmio_response_owner==5?win_mem_rsp_rdata:
 mmio_response_owner==4?video_mem_rsp_rdata:
 mmio_response_owner==3?display_mem_rsp_rdata:
 mmio_response_owner==1?s3_mem_rsp_rdata:
                          mmio_response_owner==2?s2_mem_rsp_rdata:cam_unit_rsp_rdata;
// 组合连接 cam_mem_rsp_error：记录异常状态；查看置位与清除分支可确定其保持范围。
assign cam_mem_rsp_error=mmio_response_owner==7?image_mem_rsp_error:
 mmio_response_owner==6?concat_mem_rsp_error:
 mmio_response_owner==5?win_mem_rsp_error:
 mmio_response_owner==4?video_mem_rsp_error:
 mmio_response_owner==3?display_mem_rsp_error:
 mmio_response_owner==1?s3_mem_rsp_error:
                           mmio_response_owner==2?s2_mem_rsp_error:cam_unit_rsp_error;
// 过程边界：always_ff @(posedge mem_clk) begin。
// 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
always_ff @(posedge mem_clk) begin
 // 复位相关判断：mem_reset；分支方向由信号极性与取反表达式决定。
 if(mem_reset) mmio_response_owner<=0;
 // 握手/背压判断：cam_mem_req_valid && cam_mem_req_ready。
 // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
 else if(cam_mem_req_valid && cam_mem_req_ready)
  mmio_response_owner<=mmio_request_unit;
end
// 局部字段 logic rq_start_valid,rq_start_ready,rq_done_valid,rq_done_ready。
// 表达接口或资源就绪；需结合相应有效/完成条件解释。
logic rq_start_valid,rq_start_ready,rq_done_valid,rq_done_ready;
// 局部字段 logic rq_partial,rq_use_lut,rq_axi_poisoned。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic rq_partial,rq_use_lut,rq_axi_poisoned;
// 局部字段 logic [3:0] rq_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic [3:0] rq_error;
// 局部字段 logic [31:0] rq_source,rq_output,rq_bias,rq_mult,rq_shift,rq_lut。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] rq_source,rq_output,rq_bias,rq_mult,rq_shift,rq_lut;
// 局部字段 logic [31:0] rq_pixels,rq_bound,rq_read_bytes,rq_write_bytes。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] rq_pixels,rq_bound,rq_read_bytes,rq_write_bytes;
// 局部字段 logic [31:0] rq_stall_cycles,rq_active_cycles。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] rq_stall_cycles,rq_active_cycles;
// 局部字段 logic [8:0] rq_channels。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [8:0] rq_channels;
// 局部字段 logic [1:0] rq_rounding。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [1:0] rq_rounding;
// 局部字段 logic signed [31:0] rq_zero,rq_min,rq_max。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic signed [31:0] rq_zero,rq_min,rq_max;
// 局部字段 logic rq_dma_req_valid,rq_dma_req_ready,rq_dma_req_write。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic rq_dma_req_valid,rq_dma_req_ready,rq_dma_req_write;
// 局部字段 logic [31:0] rq_dma_req_addr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [31:0] rq_dma_req_addr;
// 局部字段 logic [127:0] rq_dma_req_wdata,rq_dma_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [127:0] rq_dma_req_wdata,rq_dma_rsp_rdata;
// 局部字段 logic [15:0] rq_dma_req_wstrb。
// 按字节选择本次写入生效的 lane。
logic [15:0] rq_dma_req_wstrb;
// 局部字段 logic [3:0] rq_dma_req_id,rq_dma_rsp_id。
// 把返回信息关联到对应的已接受请求。
logic [3:0] rq_dma_req_id,rq_dma_rsp_id;
// 局部字段 logic rq_dma_rsp_valid,rq_dma_rsp_ready,rq_dma_rsp_write,rq_dma_rsp_error,rq_dma_rsp_last。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic rq_dma_rsp_valid,rq_dma_rsp_ready,rq_dma_rsp_write,rq_dma_rsp_error,rq_dma_rsp_last;
// 局部字段 logic [3:0] rq_dma_req_len。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [3:0] rq_dma_req_len;
soc_s3_mmio_mem s3_registers(
 .clk(mem_clk),.rst(region_reset_s3_registers),.ddr_ready,.axi_poisoned(rq_axi_poisoned),
 .req_valid(cam_mem_req_valid && mmio_request_unit==1),.req_ready(s3_mem_req_ready),
 .req_addr({4'b0000,cam_mem_req_addr[11:0]}),.req_write(cam_mem_req_write),
 .req_wdata(cam_mem_req_wdata),.req_wstrb(cam_mem_req_wstrb),
 .rsp_valid(s3_mem_rsp_valid),.rsp_ready(cam_mem_rsp_ready && mmio_response_owner==1),
 .rsp_rdata(s3_mem_rsp_rdata),.rsp_error(s3_mem_rsp_error),
 .start_valid(rq_start_valid),.start_ready(rq_start_ready),
 .done_valid(rq_done_valid),.done_ready(rq_done_ready),
 .engine_error(rq_error),.engine_partial(rq_partial),
 .engine_read_bytes(rq_read_bytes),.engine_write_bytes(rq_write_bytes),
 .engine_stall_cycles(rq_stall_cycles),.engine_active_cycles(rq_active_cycles),
 .source_addr(rq_source),.output_addr(rq_output),.bias_addr(rq_bias),
 .multiplier_addr(rq_mult),.shift_addr(rq_shift),.lut_addr(rq_lut),
 .use_lut(rq_use_lut),.pixels(rq_pixels),.channels(rq_channels),
 .acc_abs_bound(rq_bound),.rounding_mode(rq_rounding),
 .output_zero(rq_zero),.clamp_min(rq_min),.clamp_max(rq_max));
soc_requant_lut_dma #(.DDR_BASE(32'h8000_0000),
 .DDR_BYTES(33'h0400_0000),.READ_BURST_ENABLE(S3_BURST_ENABLE)) s3_engine(
 .clk(mem_clk),.rst(region_reset_s3_engine),.start_valid(rq_start_valid),
 .start_ready(rq_start_ready),.source_addr(rq_source),.output_addr(rq_output),
 .bias_addr(rq_bias),.multiplier_addr(rq_mult),.shift_addr(rq_shift),
 .lut_addr(rq_lut),.use_lut(rq_use_lut),.pixels(rq_pixels),
 .channels(rq_channels),.acc_abs_bound(rq_bound),
 .rounding_mode(rq_rounding),.output_zero(rq_zero),
 .clamp_min(rq_min),.clamp_max(rq_max),
 .done_valid(rq_done_valid),.done_ready(rq_done_ready),
 .error_code(rq_error),.partial_output(rq_partial),
 .read_bytes(rq_read_bytes),.write_bytes(rq_write_bytes),
 .stall_cycles(rq_stall_cycles),.active_cycles(rq_active_cycles),
 .dma_req_valid(rq_dma_req_valid),.dma_req_ready(rq_dma_req_ready),
 .dma_req_write(rq_dma_req_write),.dma_req_addr(rq_dma_req_addr),
 .dma_req_wdata(rq_dma_req_wdata),.dma_req_wstrb(rq_dma_req_wstrb),
 .dma_req_id(rq_dma_req_id),.dma_req_len(rq_dma_req_len),.dma_rsp_last(rq_dma_rsp_last),.dma_rsp_valid(rq_dma_rsp_valid),
 .dma_rsp_ready(rq_dma_rsp_ready),.dma_rsp_write(rq_dma_rsp_write),
 .dma_rsp_id(rq_dma_rsp_id),.dma_rsp_rdata(rq_dma_rsp_rdata),
 .dma_rsp_error(rq_dma_rsp_error));

// The service uses the unchanged WindowMMIO engine through a second small
// registerCDC. CPU Window access is blocked during the exclusive Conv lease.
// There is still one Window gather, nativeDMA and downstream DDR bridge.
logic gex_win_req_valid,gex_win_req_ready,gex_win_req_write,gex_win_rsp_valid,gex_win_rsp_ready,gex_win_rsp_error;
// 局部字段 logic [15:0] gex_win_req_addr;logic [31:0] gex_win_req_wdata,gex_win_rsp_rdata;logic [3:0] gex_win_req...。
// 按字节选择本次写入生效的 lane。
logic [15:0] gex_win_req_addr;logic [31:0] gex_win_req_wdata,gex_win_rsp_rdata;logic [3:0] gex_win_req_wstrb;
// 局部字段 logic gex_locked_npu,gex_locked_mem。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic gex_locked_npu,gex_locked_mem;
// 局部字段 logic gw_req_valid,gw_req_ready,gw_req_write,gw_rsp_valid,gw_rsp_ready,gw_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic gw_req_valid,gw_req_ready,gw_req_write,gw_rsp_valid,gw_rsp_ready,gw_rsp_error;
// 局部字段 logic [15:0] gw_req_addr;logic [31:0] gw_req_wdata,gw_rsp_rdata;logic [3:0] gw_req_wstrb。
// 按字节选择本次写入生效的 lane。
logic [15:0] gw_req_addr;logic [31:0] gw_req_wdata,gw_rsp_rdata;logic [3:0] gw_req_wstrb;
// 局部字段 logic win_reg_req_ready,win_reg_rsp_valid,win_reg_rsp_ready,win_reg_rsp_error,win_reg_owner。
// 跟踪存储/事务所有权，释放条件由对应完成分支决定。
logic win_reg_req_ready,win_reg_rsp_valid,win_reg_rsp_ready,win_reg_rsp_error,win_reg_owner;
// 局部字段 logic [31:0] win_reg_rsp_data。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [31:0] win_reg_rsp_data;
pg_level_sync gex_window_lease_sync(.clk(mem_clk),.rst(mem_reset),.async_level(gex_locked_npu),.level(gex_locked_mem));
pg_mmio_cdc gex_window_register_cdc(.src_clk(npu_clk_fast),.dst_clk(mem_clk),.arst,
 .s_req_valid(gex_win_req_valid),.s_req_ready(gex_win_req_ready),.s_req_addr(gex_win_req_addr),.s_req_write(gex_win_req_write),
 .s_req_wdata(gex_win_req_wdata),.s_req_wstrb(gex_win_req_wstrb),
 .s_rsp_valid(gex_win_rsp_valid),.s_rsp_ready(gex_win_rsp_ready),.s_rsp_rdata(gex_win_rsp_rdata),.s_rsp_error(gex_win_rsp_error),
 .m_req_valid(gw_req_valid),.m_req_ready(gw_req_ready),.m_req_addr(gw_req_addr),.m_req_write(gw_req_write),
 .m_req_wdata(gw_req_wdata),.m_req_wstrb(gw_req_wstrb),
 .m_rsp_valid(gw_rsp_valid),.m_rsp_ready(gw_rsp_ready),.m_rsp_rdata(gw_rsp_rdata),.m_rsp_error(gw_rsp_error));
// 组合连接 gw_req_ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
assign gw_req_ready=win_reg_req_ready;
// 组合连接 win_mem_req_ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
assign win_mem_req_ready=win_reg_req_ready&&!gex_locked_mem&&!gw_req_valid;
// 组合连接 gw_rsp_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
assign gw_rsp_valid=win_reg_rsp_valid&&win_reg_owner;
// 组合连接 gw_rsp_rdata：保存/传递数据负载，数据有效性由独立控制字段约束。
assign gw_rsp_rdata=win_reg_rsp_data;assign gw_rsp_error=win_reg_rsp_error;
// 组合连接 win_mem_rsp_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
assign win_mem_rsp_valid=win_reg_rsp_valid&&!win_reg_owner;
// 组合连接 win_mem_rsp_rdata：保存/传递数据负载，数据有效性由独立控制字段约束。
assign win_mem_rsp_rdata=win_reg_rsp_data;assign win_mem_rsp_error=win_reg_rsp_error;
// 组合连接 win_reg_rsp_ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
assign win_reg_rsp_ready=win_reg_owner?gw_rsp_ready:(cam_mem_rsp_ready&&mmio_response_owner==5);
// 过程边界：always_ff @(posedge mem_clk)begin。
// 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
always_ff @(posedge mem_clk)begin
 // 复位相关判断：mem_reset；分支方向由信号极性与取反表达式决定。
 if(mem_reset)win_reg_owner<=0;
 // 握手/背压判断：win_reg_req_ready&&(gw_req_valid||(cam_mem_req_valid&&mmio_request_unit==5&&!gex_locked_mem))。
 // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
 else if(win_reg_req_ready&&(gw_req_valid||(cam_mem_req_valid&&mmio_request_unit==5&&!gex_locked_mem)))win_reg_owner<=gw_req_valid;
end

// 局部字段 logic win_start,win_ready,win_busy,win_done,win_partial,win_flush。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic win_start,win_ready,win_busy,win_done,win_partial,win_flush;
// 局部字段 logic [7:0] win_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic [7:0] win_error;
// 局部字段 logic [31:0] win_input_base,win_scratch_base,win_first_row。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
logic [31:0] win_input_base,win_scratch_base,win_first_row;
// 局部字段 logic [15:0] win_input_h,win_input_w,win_input_c。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [15:0] win_input_h,win_input_w,win_input_c;
// 局部字段 logic [15:0] win_output_h,win_output_w,win_first_oy,win_first_ox,win_row_count。
// 记录数量或剩余进度，位宽限定可表达范围。
logic [15:0] win_output_h,win_output_w,win_first_oy,win_first_ox,win_row_count;
// 局部字段 logic [7:0] win_kernel_h,win_kernel_w,win_stride_h,win_stride_w。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] win_kernel_h,win_kernel_w,win_stride_h,win_stride_w;
// 局部字段 logic [7:0] win_dilation_h,win_dilation_w。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] win_dilation_h,win_dilation_w;
// 局部字段 logic [7:0] win_pad_top,win_pad_left,win_pad_bottom,win_pad_right。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [7:0] win_pad_top,win_pad_left,win_pad_bottom,win_pad_right;
// 局部字段 logic [31:0] win_read_bytes,win_write_bytes,win_cache_hits,win_cache_misses。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] win_read_bytes,win_write_bytes,win_cache_hits,win_cache_misses;
// 局部字段 logic [31:0] win_active_cycles,win_stall_cycles。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] win_active_cycles,win_stall_cycles;
// 局部字段 logic win_dma_req_valid,win_dma_req_ready,win_dma_req_write。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic win_dma_req_valid,win_dma_req_ready,win_dma_req_write;
// 局部字段 logic [31:0] win_dma_req_addr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [31:0] win_dma_req_addr;
// 局部字段 logic [127:0] win_dma_req_wdata,win_dma_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [127:0] win_dma_req_wdata,win_dma_rsp_rdata;
// 局部字段 logic [15:0] win_dma_req_wstrb。
// 按字节选择本次写入生效的 lane。
logic [15:0] win_dma_req_wstrb;
// 局部字段 logic [3:0] win_dma_req_id,win_dma_rsp_id,win_dma_req_len。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [3:0] win_dma_req_id,win_dma_rsp_id,win_dma_req_len;
// 局部字段 logic win_dma_rsp_valid,win_dma_rsp_ready,win_dma_rsp_write,win_dma_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic win_dma_rsp_valid,win_dma_rsp_ready,win_dma_rsp_write,win_dma_rsp_error;
soc_window_mmio_mem window_registers(
 .clk(mem_clk),.rst(region_reset_window_registers),.ddr_ready,.axi_poisoned(rq_axi_poisoned),
 .req_valid(gw_req_valid||(cam_mem_req_valid&&mmio_request_unit==5&&!gex_locked_mem)),.req_ready(win_reg_req_ready),
 .req_addr(gw_req_valid?gw_req_addr:{4'b0000,cam_mem_req_addr[11:0]}),.req_write(gw_req_valid?gw_req_write:cam_mem_req_write),
 .req_wdata(gw_req_valid?gw_req_wdata:cam_mem_req_wdata),.req_wstrb(gw_req_valid?gw_req_wstrb:cam_mem_req_wstrb),
 .rsp_valid(win_reg_rsp_valid),.rsp_ready(win_reg_rsp_ready),
 .rsp_rdata(win_reg_rsp_data),.rsp_error(win_reg_rsp_error),
 .engine_start(win_start),.engine_ready(win_ready),.engine_done(win_done),
 .engine_error(win_error),.engine_partial(win_partial),
 .engine_read_bytes(win_read_bytes),.engine_write_bytes(win_write_bytes),
 .engine_cache_hits(win_cache_hits),.engine_cache_misses(win_cache_misses),
 .engine_active_cycles(win_active_cycles),.engine_stall_cycles(win_stall_cycles),
 .input_base(win_input_base),.scratch_base(win_scratch_base),
 .first_row(win_first_row),.input_h(win_input_h),.input_w(win_input_w),
 .input_c(win_input_c),.output_h(win_output_h),.output_w(win_output_w),
 .first_oy(win_first_oy),.first_ox(win_first_ox),.row_count(win_row_count),
 .kernel_h(win_kernel_h),.kernel_w(win_kernel_w),
 .stride_h(win_stride_h),.stride_w(win_stride_w),
 .dilation_h(win_dilation_h),.dilation_w(win_dilation_w),
 .pad_top(win_pad_top),.pad_left(win_pad_left),
 .pad_bottom(win_pad_bottom),.pad_right(win_pad_right),
 .flush_cache(win_flush));
soc_window_gather_dma #(.DDR_BASE(32'h8000_0000),
 .DDR_BYTES(32'h0400_0000),.WRITE_BURST_ENABLE(S3_BURST_ENABLE)) window_engine(
 .clk(mem_clk),.rst(region_reset_window_engine),.start(win_start),.flush_cache(win_flush),
 .input_base(win_input_base),.scratch_base(win_scratch_base),
 .first_row(win_first_row),.input_h(win_input_h),.input_w(win_input_w),
 .input_c(win_input_c),.output_h(win_output_h),.output_w(win_output_w),
 .first_oy(win_first_oy),.first_ox(win_first_ox),
 .kernel_h(win_kernel_h),.kernel_w(win_kernel_w),
 .stride_h(win_stride_h),.stride_w(win_stride_w),
 .dilation_h(win_dilation_h),.dilation_w(win_dilation_w),
 .pad_top(win_pad_top),.pad_left(win_pad_left),
 .pad_bottom(win_pad_bottom),.pad_right(win_pad_right),
 .row_count(win_row_count),.ready(win_ready),.busy(win_busy),
 .done_pulse(win_done),.partial_output(win_partial),.error_sticky(win_error),
 .source_read_bytes(win_read_bytes),.scratch_write_bytes(win_write_bytes),
 .cache_hits(win_cache_hits),.cache_misses(win_cache_misses),
 .active_cycles(win_active_cycles),.stall_cycles(win_stall_cycles),
 .dma_req_valid(win_dma_req_valid),.dma_req_ready(win_dma_req_ready),
 .dma_req_write(win_dma_req_write),.dma_req_addr(win_dma_req_addr),
 .dma_req_wdata(win_dma_req_wdata),.dma_req_wstrb(win_dma_req_wstrb),
 .dma_req_id(win_dma_req_id),.dma_req_len(win_dma_req_len),.dma_rsp_last(win_dma_rsp_last),.dma_rsp_valid(win_dma_rsp_valid),
 .dma_rsp_ready(win_dma_rsp_ready),.dma_rsp_write(win_dma_rsp_write),
 .dma_rsp_id(win_dma_rsp_id),.dma_rsp_rdata(win_dma_rsp_rdata),
 .dma_rsp_error(win_dma_rsp_error));
// 局部字段 logic win_dma_rsp_last。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic win_dma_rsp_last;
// 局部字段 logic native_req_valid,native_req_ready,native_req_write。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic native_req_valid,native_req_ready,native_req_write;
// 局部字段 logic [31:0] native_req_addr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [31:0] native_req_addr;
// 局部字段 logic [127:0] native_req_wdata,native_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [127:0] native_req_wdata,native_rsp_rdata;
// 局部字段 logic [15:0] native_req_wstrb。
// 按字节选择本次写入生效的 lane。
logic [15:0] native_req_wstrb;
// 局部字段 logic [3:0] native_req_id,native_rsp_id。
// 把返回信息关联到对应的已接受请求。
logic [3:0] native_req_id,native_rsp_id;
// 局部字段 logic native_rsp_valid,native_rsp_ready,native_rsp_write,native_rsp_error,native_rsp_last。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic native_rsp_valid,native_rsp_ready,native_rsp_write,native_rsp_error,native_rsp_last;
// 局部字段 logic [3:0] native_req_len。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [3:0] native_req_len;
soc_native_2m_arbiter #(.BURST_ENABLE(S3_BURST_ENABLE)) s3_window_share(
 .clk(mem_clk),.rst(mem_reset),
 .s_req_valid({win_dma_req_valid,rq_dma_req_valid}),
 .s_req_ready({win_dma_req_ready,rq_dma_req_ready}),
 .s_req_write({win_dma_req_write,rq_dma_req_write}),
 .s_req_addr({win_dma_req_addr,rq_dma_req_addr}),
 .s_req_wdata({win_dma_req_wdata,rq_dma_req_wdata}),
 .s_req_wstrb({win_dma_req_wstrb,rq_dma_req_wstrb}),
 .s_req_id({win_dma_req_id,rq_dma_req_id}),.s_req_len({win_dma_req_len,rq_dma_req_len}),
 .s_rsp_last({win_dma_rsp_last,rq_dma_rsp_last}),
 .s_rsp_valid({win_dma_rsp_valid,rq_dma_rsp_valid}),
 .s_rsp_ready({win_dma_rsp_ready,rq_dma_rsp_ready}),
 .s_rsp_write({win_dma_rsp_write,rq_dma_rsp_write}),
 .s_rsp_id({win_dma_rsp_id,rq_dma_rsp_id}),
 .s_rsp_rdata({win_dma_rsp_rdata,rq_dma_rsp_rdata}),
 .s_rsp_error({win_dma_rsp_error,rq_dma_rsp_error}),
 .m_req_valid(native_req_valid),.m_req_ready(native_req_ready),
 .m_req_write(native_req_write),.m_req_addr(native_req_addr),
 .m_req_wdata(native_req_wdata),.m_req_wstrb(native_req_wstrb),
 .m_req_id(native_req_id),.m_req_len(native_req_len),.m_rsp_last(native_rsp_last),.m_rsp_valid(native_rsp_valid),
 .m_rsp_ready(native_rsp_ready),.m_rsp_write(native_rsp_write),
 .m_rsp_id(native_rsp_id),.m_rsp_rdata(native_rsp_rdata),
 .m_rsp_error(native_rsp_error));
// 局部字段 logic [3:0] q_awid,q_bid,q_arid,q_rid。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [3:0] q_awid,q_bid,q_arid,q_rid;
// 局部字段 logic concat_start,concat_ready,concat_busy,concat_done,concat_partial。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic concat_start,concat_ready,concat_busy,concat_done,concat_partial;
// 局部字段 logic tensor_cancel,tensor_poison;logic [1:0] tensor_operation;logic [15:0] tensor_h,tensor_w。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic tensor_cancel,tensor_poison;logic [1:0] tensor_operation;logic [15:0] tensor_h,tensor_w;
// 局部字段 logic [7:0] concat_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic [7:0] concat_error;
// 局部字段 logic [31:0] concat_input,concat_aux,concat_output,concat_pixels。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] concat_input,concat_aux,concat_output,concat_pixels;
// 局部字段 logic [15:0] concat_input_c,concat_aux_c。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [15:0] concat_input_c,concat_aux_c;
// 局部字段 logic [31:0] concat_read_bytes,concat_write_bytes,concat_active,concat_stall。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] concat_read_bytes,concat_write_bytes,concat_active,concat_stall;
// 局部字段 logic cat_req_valid,cat_req_ready,cat_req_write,cat_rsp_valid,cat_rsp_ready,cat_rsp_write,cat_rsp_error。
// 记录异常状态；查看置位与清除分支可确定其保持范围。
logic cat_req_valid,cat_req_ready,cat_req_write,cat_rsp_valid,cat_rsp_ready,cat_rsp_write,cat_rsp_error;
// 局部字段 logic [31:0] cat_req_addr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [31:0] cat_req_addr;
// 局部字段 logic [127:0] cat_req_wdata,cat_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [127:0] cat_req_wdata,cat_rsp_rdata;
// 局部字段 logic [15:0] cat_req_wstrb。
// 按字节选择本次写入生效的 lane。
logic [15:0] cat_req_wstrb;
// 局部字段 logic [3:0] cat_req_id,cat_rsp_id,cat_req_len。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [3:0] cat_req_id,cat_rsp_id,cat_req_len;
// 局部字段 logic cat_rsp_last。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic cat_rsp_last;
soc_concat_mmio_mem concat_registers(
 .clk(mem_clk),.rst(region_reset_concat_registers),.ddr_ready,.axi_poisoned(rq_axi_poisoned|tensor_poison),
 .req_valid(cam_mem_req_valid && mmio_request_unit==6),.req_ready(concat_mem_req_ready),
 .req_addr({4'b0,cam_mem_req_addr[11:0]}),.req_write(cam_mem_req_write),
 .req_wdata(cam_mem_req_wdata),.req_wstrb(cam_mem_req_wstrb),
 .rsp_valid(concat_mem_rsp_valid),.rsp_ready(cam_mem_rsp_ready && mmio_response_owner==6),
 .rsp_rdata(concat_mem_rsp_rdata),.rsp_error(concat_mem_rsp_error),
 .engine_start(concat_start),.engine_cancel(tensor_cancel),
 .operation(tensor_operation),.image_h(tensor_h),.image_w(tensor_w),.engine_ready(concat_ready),.engine_done(concat_done),
 .engine_error(concat_error),.engine_partial(concat_partial),
 .engine_read_bytes(concat_read_bytes),.engine_write_bytes(concat_write_bytes),
 .engine_active_cycles(concat_active),.engine_stall_cycles(concat_stall),
 .input_base(concat_input),.aux_base(concat_aux),.output_base(concat_output),
 .pixels(concat_pixels),.input_channels(concat_input_c),.aux_channels(concat_aux_c),
 .irq_level(concat_irq_mem));
pg_level_sync concat_completion_sync(.clk(cpu_clk_fast),.rst(cpu_reset),
 .async_level(concat_irq_mem),.level(concat_irq_cpu));
soc_concat_dma #(.READ_BURST_ENABLE(S3_BURST_ENABLE),.WRITE_BURST_ENABLE(S3_BURST_ENABLE)) concat_engine(
 .clk(mem_clk),.rst(region_reset_concat_engine),.start(concat_start),.cancel(tensor_cancel),.protocol_poison(tensor_poison),
 .operation(tensor_operation),.image_h(tensor_h),.image_w(tensor_w),
 .input_base(concat_input),.aux_base(concat_aux),.output_base(concat_output),
 .pixels(concat_pixels),.input_channels(concat_input_c),.aux_channels(concat_aux_c),
 .ready(concat_ready),.busy(concat_busy),.done_pulse(concat_done),
 .partial_output(concat_partial),.error_sticky(concat_error),
 .read_bytes(concat_read_bytes),.write_bytes(concat_write_bytes),
 .active_cycles(concat_active),.stall_cycles(concat_stall),
 .dma_req_valid(cat_req_valid),.dma_req_ready(cat_req_ready),.dma_req_write(cat_req_write),
 .dma_req_addr(cat_req_addr),.dma_req_wdata(cat_req_wdata),.dma_req_wstrb(cat_req_wstrb),
 .dma_req_id(cat_req_id),.dma_req_len(cat_req_len),.dma_rsp_last(cat_rsp_last),.dma_rsp_valid(cat_rsp_valid),.dma_rsp_ready(cat_rsp_ready),
 .dma_rsp_write(cat_rsp_write),.dma_rsp_id(cat_rsp_id),.dma_rsp_rdata(cat_rsp_rdata),.dma_rsp_error(cat_rsp_error));
// 局部字段 logic shared_req_valid,shared_req_ready,shared_req_write。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic shared_req_valid,shared_req_ready,shared_req_write;
// 局部字段 logic [31:0] shared_req_addr。
// 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
logic [31:0] shared_req_addr;
// 局部字段 logic [127:0] shared_req_wdata,shared_rsp_rdata。
// 保存/传递数据负载，数据有效性由独立控制字段约束。
logic [127:0] shared_req_wdata,shared_rsp_rdata;
// 局部字段 logic [15:0] shared_req_wstrb。
logic [15:0] shared_req_wstrb;
logic [3:0] shared_req_id,shared_rsp_id;
logic shared_rsp_valid,shared_rsp_ready,shared_rsp_write,shared_rsp_error,shared_rsp_last;
logic [3:0] shared_req_len;
// Existing S3/Window ownership is retained; Concat is a third native client.
soc_native_2m_arbiter #(.BURST_ENABLE(S3_BURST_ENABLE)) tensor_native_share(
 .clk(mem_clk),.rst(mem_reset),
 .s_req_valid({cat_req_valid,native_req_valid}),.s_req_ready({cat_req_ready,native_req_ready}),
 .s_req_write({cat_req_write,native_req_write}),.s_req_addr({cat_req_addr,native_req_addr}),
 .s_req_wdata({cat_req_wdata,native_req_wdata}),.s_req_wstrb({cat_req_wstrb,native_req_wstrb}),
 .s_req_len({cat_req_len,native_req_len}),.s_rsp_last({cat_rsp_last,native_rsp_last}),
 .s_req_id({cat_req_id,native_req_id}),.s_rsp_valid({cat_rsp_valid,native_rsp_valid}),
 .s_rsp_ready({cat_rsp_ready,native_rsp_ready}),.s_rsp_write({cat_rsp_write,native_rsp_write}),
 .s_rsp_id({cat_rsp_id,native_rsp_id}),.s_rsp_rdata({cat_rsp_rdata,native_rsp_rdata}),
 .s_rsp_error({cat_rsp_error,native_rsp_error}),
 .m_req_valid(shared_req_valid),.m_req_ready(shared_req_ready),.m_req_write(shared_req_write),
 .m_req_addr(shared_req_addr),.m_req_wdata(shared_req_wdata),.m_req_wstrb(shared_req_wstrb),
 .m_req_id(shared_req_id),.m_req_len(shared_req_len),.m_rsp_last(shared_rsp_last),.m_rsp_valid(shared_rsp_valid),.m_rsp_ready(shared_rsp_ready),
 .m_rsp_write(shared_rsp_write),.m_rsp_id(shared_rsp_id),.m_rsp_rdata(shared_rsp_rdata),.m_rsp_error(shared_rsp_error));
logic [31:0] q_awaddr,q_araddr;
logic [7:0] q_awlen,q_arlen;
logic [2:0] q_awsize,q_arsize;
logic [1:0] q_awburst,q_arburst,q_bresp,q_rresp;
logic q_awvalid,q_awready,q_wlast,q_wvalid,q_wready,q_bvalid,q_bready;
logic q_arvalid,q_arready,q_rlast,q_rvalid,q_rready;
logic [127:0] q_wdata,q_rdata;
logic [15:0] q_wstrb;
soc_rq_to_axi #(.BURST_ENABLE(S3_BURST_ENABLE)) s3_axi(
 .clk(mem_clk),.rst(region_reset_s3_axi),.ddr_ready,
 .req_valid(shared_req_valid),.req_ready(shared_req_ready),
 .req_write(shared_req_write),.req_addr(shared_req_addr),
 .req_wdata(shared_req_wdata),.req_wstrb(shared_req_wstrb),
 .req_len(shared_req_len),.rsp_last(shared_rsp_last),
 .req_id(shared_req_id),.rsp_valid(shared_rsp_valid),
 .rsp_ready(shared_rsp_ready),.rsp_write(shared_rsp_write),
 .rsp_id(shared_rsp_id),.rsp_rdata(shared_rsp_rdata),
 .rsp_error(shared_rsp_error),.poisoned(rq_axi_poisoned),
 .m_awid(q_awid),.m_awaddr(q_awaddr),.m_awlen(q_awlen),
 .m_awsize(q_awsize),.m_awburst(q_awburst),.m_awvalid(q_awvalid),
 .m_awready(q_awready),.m_wdata(q_wdata),.m_wstrb(q_wstrb),
 .m_wlast(q_wlast),.m_wvalid(q_wvalid),.m_wready(q_wready),
 .m_bid(q_bid),.m_bresp(q_bresp),.m_bvalid(q_bvalid),.m_bready(q_bready),
 .m_arid(q_arid),.m_araddr(q_araddr),.m_arlen(q_arlen),
 .m_arsize(q_arsize),.m_arburst(q_arburst),.m_arvalid(q_arvalid),
 .m_arready(q_arready),.m_rid(q_rid),.m_rdata(q_rdata),
 .m_rresp(q_rresp),.m_rlast(q_rlast),.m_rvalid(q_rvalid),
 .m_rready(q_rready));
logic [3:0] c_awid,c_bid,c_arid,c_rid;
logic [31:0] c_awaddr,c_araddr;
logic [7:0] c_awlen,c_arlen;
logic [2:0] c_awsize,c_arsize;
logic [1:0] c_awburst,c_arburst,c_bresp,c_rresp;
logic c_awvalid,c_awready,c_wlast,c_wvalid,c_wready,c_bvalid,c_bready;
logic c_arvalid,c_arready,c_rlast,c_rvalid,c_rready;
logic [127:0] c_wdata,c_rdata;
logic [15:0] c_wstrb;
soc_camera_frame_pipeline #(.WIDTH(1280),.HEIGHT(720)) camera_frame(
 .pclk(camera_clk_1),.mem_clk,.arst,.start(camera_start),
 .frame_base(camera_frame_base),.vsync(camera_vsync_1),.href(camera_href_1),
 .byte_data(camera_data_held),.ready(camera_ready),.busy(camera_busy),
 .done_pulse(camera_done),.frame_valid(camera_valid),
 .error_sticky(camera_errors),.pixels_written(camera_pixels_written),
 .sensor_pixels(camera_sensor_pixels),
 .m_awid(c_awid),.m_awaddr(c_awaddr),.m_awlen(c_awlen),
 .m_awsize(c_awsize),.m_awburst(c_awburst),.m_awvalid(c_awvalid),
 .m_awready(c_awready),.m_wdata(c_wdata),.m_wstrb(c_wstrb),
 .m_wlast(c_wlast),.m_wvalid(c_wvalid),.m_wready(c_wready),
 .m_bid(c_bid),.m_bresp(c_bresp),.m_bvalid(c_bvalid),.m_bready(c_bready));
// 组合连接 c_arid：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
assign c_arid=0;assign c_araddr=0;assign c_arlen=0;
// 组合连接 c_arsize：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
assign c_arsize=0;assign c_arburst=0;assign c_arvalid=0;
// 组合连接 c_rready：表达接口或资源就绪；需结合相应有效/完成条件解释。
assign c_rready=1'b1;
logic [3:0] a_awid,a_bid,a_arid,a_rid;
logic [31:0] a_awaddr,a_araddr;
logic [7:0] a_awlen,a_arlen;
logic [2:0] a_awsize,a_arsize;
logic [1:0] a_awburst,a_arburst,a_bresp,a_rresp;
logic a_awvalid,a_awready,a_wlast,a_wvalid,a_wready,a_bvalid,a_bready;
logic a_arvalid,a_arready,a_rlast,a_rvalid,a_rready;
logic [127:0] a_wdata,a_rdata;
logic [15:0] a_wstrb;
logic [3:0] b_awid,b_bid,b_arid,b_rid;
logic [31:0] b_awaddr,b_araddr;
logic [7:0] b_awlen,b_arlen;
logic [2:0] b_awsize,b_arsize;
logic [1:0] b_awburst,b_arburst,b_bresp,b_rresp;
logic b_awvalid,b_awready,b_wlast,b_wvalid,b_wready,b_bvalid,b_bready;
logic b_arvalid,b_arready,b_rlast,b_rvalid,b_rready;
logic [127:0] b_wdata,b_rdata;
logic [15:0] b_wstrb;
logic [3:0] v_awid,v_bid,v_arid,v_rid;
logic [31:0] v_awaddr,v_araddr;
logic [7:0] v_awlen,v_arlen;
logic [2:0] v_awsize,v_arsize;
logic [1:0] v_awburst,v_arburst,v_bresp,v_rresp;
logic v_awvalid,v_awready,v_wlast,v_wvalid,v_wready,v_bvalid,v_bready;
logic v_arvalid,v_arready,v_rlast,v_rvalid,v_rready;
logic [127:0] v_wdata,v_rdata;
logic [15:0] v_wstrb;
logic [3:0] vr_awid,vr_bid,vr_arid,vr_rid;
logic [31:0] vr_awaddr,vr_araddr;
logic [7:0] vr_awlen,vr_arlen;
logic [2:0] vr_awsize,vr_arsize;
logic [1:0] vr_awburst,vr_arburst,vr_bresp,vr_rresp;
logic vr_awvalid,vr_awready,vr_wlast,vr_wvalid,vr_wready,vr_bvalid,vr_bready;
logic vr_arvalid,vr_arready,vr_rlast,vr_rvalid,vr_rready;
logic [127:0] vr_wdata,vr_rdata;
logic [15:0] vr_wstrb;
soc_v2_replay_pipeline v2_replay(
 .clk(mem_clk),.rst(region_reset_v2_replay),.ddr_ready,
 .req_valid(cam_mem_req_valid && mmio_request_unit==2),
 .req_ready(s2_mem_req_ready),
 .req_addr({4'b0000,cam_mem_req_addr[11:0]}),
 .req_write(cam_mem_req_write),.req_wdata(cam_mem_req_wdata),
 .req_wstrb(cam_mem_req_wstrb),
 .rsp_valid(s2_mem_rsp_valid),
 .rsp_ready(cam_mem_rsp_ready && mmio_response_owner==2),
 .rsp_rdata(s2_mem_rsp_rdata),.rsp_error(s2_mem_rsp_error),
 .m_awid(vr_awid),.m_awaddr(vr_awaddr),.m_awlen(vr_awlen),
 .m_awsize(vr_awsize),.m_awburst(vr_awburst),.m_awvalid(vr_awvalid),
 .m_awready(vr_awready),.m_wdata(vr_wdata),.m_wstrb(vr_wstrb),
 .m_wlast(vr_wlast),.m_wvalid(vr_wvalid),.m_wready(vr_wready),
 .m_bid(vr_bid),.m_bresp(vr_bresp),.m_bvalid(vr_bvalid),
 .m_bready(vr_bready),.m_arid(vr_arid),.m_araddr(vr_araddr),
 .m_arlen(vr_arlen),.m_arsize(vr_arsize),.m_arburst(vr_arburst),
 .m_arvalid(vr_arvalid),.m_arready(vr_arready),
 .m_rid(vr_rid),.m_rdata(vr_rdata),.m_rresp(vr_rresp),
 .m_rlast(vr_rlast),.m_rvalid(vr_rvalid),.m_rready(vr_rready));
soc_axi_2m_arbiter camera_share(.clk(mem_clk),.rst(region_reset_camera_share),.busy(),
 .s_awid({c_awid,s_awid}),.s_awaddr({c_awaddr,s_awaddr}),
 .s_awlen({c_awlen,s_awlen}),.s_awsize({c_awsize,s_awsize}),
 .s_awburst({c_awburst,s_awburst}),.s_awvalid({c_awvalid,s_awvalid}),
 .s_awready({c_awready,s_awready}),
 .s_wdata({c_wdata,s_wdata}),.s_wstrb({c_wstrb,s_wstrb}),
 .s_wlast({c_wlast,s_wlast}),.s_wvalid({c_wvalid,s_wvalid}),
 .s_wready({c_wready,s_wready}),
 .s_bid({c_bid,s_bid}),.s_bresp({c_bresp,s_bresp}),
 .s_bvalid({c_bvalid,s_bvalid}),.s_bready({c_bready,s_bready}),
 .s_arid({c_arid,s_arid}),.s_araddr({c_araddr,s_araddr}),
 .s_arlen({c_arlen,s_arlen}),.s_arsize({c_arsize,s_arsize}),
 .s_arburst({c_arburst,s_arburst}),.s_arvalid({c_arvalid,s_arvalid}),
 .s_arready({c_arready,s_arready}),
 .s_rid({c_rid,s_rid}),.s_rdata({c_rdata,s_rdata}),
 .s_rresp({c_rresp,s_rresp}),.s_rlast({c_rlast,s_rlast}),
 .s_rvalid({c_rvalid,s_rvalid}),.s_rready({c_rready,s_rready}),
 .m_awid(a_awid),.m_awaddr(a_awaddr),.m_awlen(a_awlen),
 .m_awsize(a_awsize),.m_awburst(a_awburst),.m_awvalid(a_awvalid),
 .m_awready(a_awready),.m_wdata(a_wdata),.m_wstrb(a_wstrb),
 .m_wlast(a_wlast),.m_wvalid(a_wvalid),.m_wready(a_wready),
 .m_bid(a_bid),.m_bresp(a_bresp),.m_bvalid(a_bvalid),.m_bready(a_bready),
 .m_arid(a_arid),.m_araddr(a_araddr),.m_arlen(a_arlen),
 .m_arsize(a_arsize),.m_arburst(a_arburst),.m_arvalid(a_arvalid),
 .m_arready(a_arready),.m_rid(a_rid),.m_rdata(a_rdata),
 .m_rresp(a_rresp),.m_rlast(a_rlast),.m_rvalid(a_rvalid),
 .m_rready(a_rready));
soc_axi_2m_arbiter s3_share(.clk(mem_clk),.rst(region_reset_s3_share),.busy(),
 .s_awid({q_awid,a_awid}),.s_awaddr({q_awaddr,a_awaddr}),
 .s_awlen({q_awlen,a_awlen}),.s_awsize({q_awsize,a_awsize}),
 .s_awburst({q_awburst,a_awburst}),.s_awvalid({q_awvalid,a_awvalid}),
 .s_awready({q_awready,a_awready}),
 .s_wdata({q_wdata,a_wdata}),.s_wstrb({q_wstrb,a_wstrb}),
 .s_wlast({q_wlast,a_wlast}),.s_wvalid({q_wvalid,a_wvalid}),
 .s_wready({q_wready,a_wready}),
 .s_bid({q_bid,a_bid}),.s_bresp({q_bresp,a_bresp}),
 .s_bvalid({q_bvalid,a_bvalid}),.s_bready({q_bready,a_bready}),
 .s_arid({q_arid,a_arid}),.s_araddr({q_araddr,a_araddr}),
 .s_arlen({q_arlen,a_arlen}),.s_arsize({q_arsize,a_arsize}),
 .s_arburst({q_arburst,a_arburst}),.s_arvalid({q_arvalid,a_arvalid}),
 .s_arready({q_arready,a_arready}),
 .s_rid({q_rid,a_rid}),.s_rdata({q_rdata,a_rdata}),
 .s_rresp({q_rresp,a_rresp}),.s_rlast({q_rlast,a_rlast}),
 .s_rvalid({q_rvalid,a_rvalid}),.s_rready({q_rready,a_rready}),
 .m_awid(b_awid),.m_awaddr(b_awaddr),.m_awlen(b_awlen),
 .m_awsize(b_awsize),.m_awburst(b_awburst),.m_awvalid(b_awvalid),
 .m_awready(b_awready),.m_wdata(b_wdata),.m_wstrb(b_wstrb),
 .m_wlast(b_wlast),.m_wvalid(b_wvalid),.m_wready(b_wready),
 .m_bid(b_bid),.m_bresp(b_bresp),.m_bvalid(b_bvalid),
 .m_bready(b_bready),.m_arid(b_arid),.m_araddr(b_araddr),
 .m_arlen(b_arlen),.m_arsize(b_arsize),.m_arburst(b_arburst),
 .m_arvalid(b_arvalid),.m_arready(b_arready),
 .m_rid(b_rid),.m_rdata(b_rdata),.m_rresp(b_rresp),
 .m_rlast(b_rlast),.m_rvalid(b_rvalid),.m_rready(b_rready));
logic [3:0] d_awid,d_bid,d_arid,d_rid;
logic [31:0] d_awaddr,d_araddr;
logic [7:0] d_awlen,d_arlen;
logic [2:0] d_awsize,d_arsize;
logic [1:0] d_awburst,d_arburst,d_bresp,d_rresp;
logic d_awvalid,d_awready,d_wlast,d_wvalid,d_wready,d_bvalid,d_bready;
logic d_arvalid,d_arready,d_rlast,d_rvalid,d_rready;
logic [127:0] d_wdata,d_rdata;
logic [15:0] d_wstrb;
soc_axi_2m_arbiter v2_share(.clk(mem_clk),.rst(region_reset_v2_share),.busy(),
 .s_awid({v_awid,b_awid}),.s_awaddr({v_awaddr,b_awaddr}),
 .s_awlen({v_awlen,b_awlen}),.s_awsize({v_awsize,b_awsize}),
 .s_awburst({v_awburst,b_awburst}),.s_awvalid({v_awvalid,b_awvalid}),
 .s_awready({v_awready,b_awready}),
 .s_wdata({v_wdata,b_wdata}),.s_wstrb({v_wstrb,b_wstrb}),
 .s_wlast({v_wlast,b_wlast}),.s_wvalid({v_wvalid,b_wvalid}),
 .s_wready({v_wready,b_wready}),
 .s_bid({v_bid,b_bid}),.s_bresp({v_bresp,b_bresp}),
 .s_bvalid({v_bvalid,b_bvalid}),.s_bready({v_bready,b_bready}),
 .s_arid({v_arid,b_arid}),.s_araddr({v_araddr,b_araddr}),
 .s_arlen({v_arlen,b_arlen}),.s_arsize({v_arsize,b_arsize}),
 .s_arburst({v_arburst,b_arburst}),.s_arvalid({v_arvalid,b_arvalid}),
 .s_arready({v_arready,b_arready}),
 .s_rid({v_rid,b_rid}),.s_rdata({v_rdata,b_rdata}),
 .s_rresp({v_rresp,b_rresp}),.s_rlast({v_rlast,b_rlast}),
 .s_rvalid({v_rvalid,b_rvalid}),.s_rready({v_rready,b_rready}),
 .m_awid(d_awid),.m_awaddr(d_awaddr),.m_awlen(d_awlen),
 .m_awsize(d_awsize),.m_awburst(d_awburst),.m_awvalid(d_awvalid),
 .m_awready(d_awready),.m_wdata(d_wdata),.m_wstrb(d_wstrb),
 .m_wlast(d_wlast),.m_wvalid(d_wvalid),.m_wready(d_wready),
 .m_bid(d_bid),.m_bresp(d_bresp),.m_bvalid(d_bvalid),
 .m_bready(d_bready),.m_arid(d_arid),.m_araddr(d_araddr),
 .m_arlen(d_arlen),.m_arsize(d_arsize),.m_arburst(d_arburst),
 .m_arvalid(d_arvalid),.m_arready(d_arready),
 .m_rid(d_rid),.m_rdata(d_rdata),.m_rresp(d_rresp),
 .m_rlast(d_rlast),.m_rvalid(d_rvalid),.m_rready(d_rready));
logic [3:0] h_awid,h_bid,h_arid,h_rid;
logic [31:0] h_awaddr,h_araddr;
logic [7:0] h_awlen,h_arlen;
logic [2:0] h_awsize,h_arsize;
logic [1:0] h_awburst,h_arburst,h_bresp,h_rresp;
logic h_awvalid,h_awready,h_wlast,h_wvalid,h_wready,h_bvalid,h_bready;
logic h_arvalid,h_arready,h_rlast,h_rvalid,h_rready;
logic [127:0] h_wdata,h_rdata;
logic [15:0] h_wstrb;
logic [3:0] e_awid,e_bid,e_arid,e_rid;
logic [31:0] e_awaddr,e_araddr;
logic [7:0] e_awlen,e_arlen;
logic [2:0] e_awsize,e_arsize;
logic [1:0] e_awburst,e_arburst,e_bresp,e_rresp;
logic e_awvalid,e_awready,e_wlast,e_wvalid,e_wready,e_bvalid,e_bready;
logic e_arvalid,e_arready,e_rlast,e_rvalid,e_rready;
logic [127:0] e_wdata,e_rdata;
logic [15:0] e_wstrb;
soc_axi_2m_arbiter video_share(.clk(mem_clk),.rst(region_reset_video_share),.busy(),
 .s_awid({4'd0,d_awid}),
 .s_awaddr({32'd0,d_awaddr}),
 .s_awlen({8'd0,d_awlen}),
 .s_awsize({3'd4,d_awsize}),
 .s_awburst({2'd1,d_awburst}),
 .s_awvalid({1'b0,d_awvalid}),
 .s_awready({h_awready,d_awready}),
 .s_wdata({128'd0,d_wdata}),
 .s_wstrb({16'd0,d_wstrb}),
 .s_wlast({1'b0,d_wlast}),
 .s_wvalid({1'b0,d_wvalid}),
 .s_wready({h_wready,d_wready}),
 .s_bid({h_bid,d_bid}),
 .s_bresp({h_bresp,d_bresp}),
 .s_bvalid({h_bvalid,d_bvalid}),
 .s_bready({1'b1,d_bready}),
 .s_arid({h_arid,d_arid}),
 .s_araddr({h_araddr,d_araddr}),
 .s_arlen({h_arlen,d_arlen}),
 .s_arsize({h_arsize,d_arsize}),
 .s_arburst({h_arburst,d_arburst}),
 .s_arvalid({h_arvalid,d_arvalid}),
 .s_arready({h_arready,d_arready}),
 .s_rid({h_rid,d_rid}),
 .s_rdata({h_rdata,d_rdata}),
 .s_rresp({h_rresp,d_rresp}),
 .s_rlast({h_rlast,d_rlast}),
 .s_rvalid({h_rvalid,d_rvalid}),
 .s_rready({h_rready,d_rready}),
 .m_awid(e_awid),
 .m_awaddr(e_awaddr),
 .m_awlen(e_awlen),
 .m_awsize(e_awsize),
 .m_awburst(e_awburst),
 .m_awvalid(e_awvalid),
 .m_awready(e_awready),
 .m_wdata(e_wdata),
 .m_wstrb(e_wstrb),
 .m_wlast(e_wlast),
 .m_wvalid(e_wvalid),
 .m_wready(e_wready),
 .m_bid(e_bid),
 .m_bresp(e_bresp),
 .m_bvalid(e_bvalid),
 .m_bready(e_bready),
 .m_arid(e_arid),
 .m_araddr(e_araddr),
 .m_arlen(e_arlen),
 .m_arsize(e_arsize),
 .m_arburst(e_arburst),
 .m_arvalid(e_arvalid),
 .m_arready(e_arready),
 .m_rid(e_rid),
 .m_rdata(e_rdata),
 .m_rresp(e_rresp),
 .m_rlast(e_rlast),
 .m_rvalid(e_rvalid),
 .m_rready(e_rready));
// Image and V2 replay share the V2 slot before video arbitration.
logic [3:0] im_awid;
logic [31:0] im_awaddr;
logic [7:0] im_awlen;
logic [2:0] im_awsize;
logic [1:0] im_awburst;
logic im_awvalid;
logic im_awready;
logic [127:0] im_wdata;
logic [15:0] im_wstrb;
logic im_wlast;
logic im_wvalid;
logic im_wready;
logic [3:0] im_bid;
logic [1:0] im_bresp;
logic im_bvalid;
logic im_bready;
logic [3:0] im_arid;
logic [31:0] im_araddr;
logic [7:0] im_arlen;
logic [2:0] im_arsize;
logic [1:0] im_arburst;
logic im_arvalid;
logic im_arready;
logic [3:0] im_rid;
logic [127:0] im_rdata;
logic [1:0] im_rresp;
logic im_rlast;
logic im_rvalid;
logic im_rready;

soc_display_commit_mmio #(.FRAME_BYTES(680*340*2),.BOX_WIDTH(680),.BOX_HEIGHT(340),.MMIO_PAGE(4'h5),.REQUIRE_PRESENT_ACK(1),.SCOPED_WRITER(1)) display_commit(
 .clk(mem_clk),.rst(mem_reset),.ddr_ready,.axi_poisoned(adapter_fault||rq_axi_poisoned),.cpu_time_gray,
 .req_valid(cam_mem_req_valid&&mmio_request_unit==3),.req_ready(display_mem_req_ready),
 .req_addr(cam_mem_req_addr),.req_write(cam_mem_req_write),.req_wdata(cam_mem_req_wdata),.req_wstrb(cam_mem_req_wstrb),
 .rsp_valid(display_mem_rsp_valid),.rsp_ready(cam_mem_rsp_ready&&mmio_response_owner==3),
 .rsp_rdata(display_mem_rsp_rdata),.rsp_error(display_mem_rsp_error),
 .awvalid(im_awvalid),.awready(im_awready),.awaddr(im_awaddr),.awid(im_awid),.awlen(im_awlen),.awsize(im_awsize),.awburst(im_awburst),
 .wvalid(im_wvalid),.wready(im_wready),.wstrb(im_wstrb),.wlast(im_wlast),
 .bvalid(im_bvalid),.bready(im_bready),.bid(im_bid),.bresp(im_bresp),
 .publish_valid,.publish_ready,.publish_fb,.publish_frame,.publish_run,.publish_xy1,.publish_xy2,
 .publish_score,.publish_class,.publish_count,.publish_sequence,
 .display_valid(displayed_valid),.display_fb(displayed_fb),
 .pending_display_valid,.pending_display_fb);
soc_hdmi_ddr_scanout #(.SINGLE_VIEW(1),.W(680),.H(340),.X_START(20),.Y_START(70),.TX_EXTRA_CYCLES(0)) display_scanout(
 .ui_clk(mem_clk),.ui_rst(mem_reset),.pix_clk(hdmi_pixel_clk),.pix_rst(hdmi_pixel_reset),
 .cpu_time_gray,.test_pattern(video_mode),.publish_valid,.publish_ready,
 .publish_fb,.publish_frame,.publish_run,.publish_xy1,.publish_xy2,.publish_score,.publish_class,.publish_count,.publish_sequence,
 .pending_valid(pending_display_valid),.pending_fb(pending_display_fb),
 .presented_valid(displayed_valid),.presented_fb(displayed_fb),.presented_frame(displayed_frame),.presented_run(displayed_run),
 .m_arid(h_arid),.m_araddr(h_araddr),.m_arlen(h_arlen),.m_arsize(h_arsize),.m_arburst(h_arburst),.m_arvalid(h_arvalid),.m_arready(h_arready),
 .m_rid(h_rid),.m_rdata(h_rdata),.m_rresp(h_rresp),.m_rlast(h_rlast),.m_rvalid(h_rvalid),.m_rready(h_rready),
 .video_rgb,.video_de,.video_hs,.video_vs,.event_tc,.event_th,.event_te,.te_good,
 .tc_ticks,.th_ticks,.te_ticks,.tc_pixel_ticks(),.th_pixel_ticks(),.te_pixel_ticks(),
 .tc_frame,.tc_run,.th_frame,.th_run,.te_frame,.te_run,
 .stat_underflow,.stat_mismatch,.stat_presented,.stat_max_ddr_wait,.stat_fifo_high,.stat_fifo_low,.video_fault);
soc_video_event_mmio video_registers(
 .clk(mem_clk),.rst(mem_reset),
 .req_valid(cam_mem_req_valid&&mmio_request_unit==4),.req_ready(video_mem_req_ready),
 .req_addr(cam_mem_req_addr),.req_write(cam_mem_req_write),.req_wdata(cam_mem_req_wdata),.req_wstrb(cam_mem_req_wstrb),
 .rsp_valid(video_mem_rsp_valid),.rsp_ready(cam_mem_rsp_ready&&mmio_response_owner==4),
 .rsp_rdata(video_mem_rsp_rdata),.rsp_error(video_mem_rsp_error),.test_pattern(video_mode),
 .event_tc,.event_th,.event_te,.te_good,.tc_ticks,.th_ticks,.te_ticks,
 .tc_frame,.tc_run,.th_frame,.th_run,.te_frame,.te_run,
 .stat_underflow,.stat_mismatch,.stat_presented,.stat_max_ddr_wait,.stat_fifo_high,.stat_fifo_low,.video_fault);
soc_mini_hdmi_tx u_hdmi_tx(.pixel_clk(hdmi_pixel_clk),.serial_clk(hdmi_serial_clk),.reset_n(!hdmi_pixel_reset),
 .serial_reset_n(!hdmi_serial_reset),
 .rgb888(video_rgb),.de(video_de),.hsync(video_hs),.vsync(video_vs),
 .tmds_data_p,.tmds_data_n,.tmds_clk_p,.tmds_clk_n);

soc_image_accel image_accel(
 .clk(mem_clk),.rst(mem_reset),.ddr_ready,.external_poisoned(adapter_fault||rq_axi_poisoned),
 .req_valid(cam_mem_req_valid&&mmio_request_unit==7),.req_ready(image_mem_req_ready),
 .req_addr(cam_mem_req_addr),.req_write(cam_mem_req_write),.req_wdata(cam_mem_req_wdata),.req_wstrb(cam_mem_req_wstrb),
 .rsp_valid(image_mem_rsp_valid),.rsp_ready(cam_mem_rsp_ready&&mmio_response_owner==7),
 .rsp_rdata(image_mem_rsp_rdata),.rsp_error(image_mem_rsp_error),
 .m_awid(im_awid),
 .m_awaddr(im_awaddr),
 .m_awlen(im_awlen),
 .m_awsize(im_awsize),
 .m_awburst(im_awburst),
 .m_awvalid(im_awvalid),
 .m_awready(im_awready),
 .m_wdata(im_wdata),
 .m_wstrb(im_wstrb),
 .m_wlast(im_wlast),
 .m_wvalid(im_wvalid),
 .m_wready(im_wready),
 .m_bid(im_bid),
 .m_bresp(im_bresp),
 .m_bvalid(im_bvalid),
 .m_bready(im_bready),
 .m_arid(im_arid),
 .m_araddr(im_araddr),
 .m_arlen(im_arlen),
 .m_arsize(im_arsize),
 .m_arburst(im_arburst),
 .m_arvalid(im_arvalid),
 .m_arready(im_arready),
 .m_rid(im_rid),
 .m_rdata(im_rdata),
 .m_rresp(im_rresp),
 .m_rlast(im_rlast),
 .m_rvalid(im_rvalid),
 .m_rready(im_rready));
soc_axi_2m_arbiter image_v2_share(.clk(mem_clk),.rst(mem_reset),.busy(),
 .s_awid({im_awid,vr_awid}),
 .s_awaddr({im_awaddr,vr_awaddr}),
 .s_awlen({im_awlen,vr_awlen}),
 .s_awsize({im_awsize,vr_awsize}),
 .s_awburst({im_awburst,vr_awburst}),
 .s_awvalid({im_awvalid,vr_awvalid}),
 .s_awready({im_awready,vr_awready}),
 .s_wdata({im_wdata,vr_wdata}),
 .s_wstrb({im_wstrb,vr_wstrb}),
 .s_wlast({im_wlast,vr_wlast}),
 .s_wvalid({im_wvalid,vr_wvalid}),
 .s_wready({im_wready,vr_wready}),
 .s_bid({im_bid,vr_bid}),
 .s_bresp({im_bresp,vr_bresp}),
 .s_bvalid({im_bvalid,vr_bvalid}),
 .s_bready({im_bready,vr_bready}),
 .s_arid({im_arid,vr_arid}),
 .s_araddr({im_araddr,vr_araddr}),
 .s_arlen({im_arlen,vr_arlen}),
 .s_arsize({im_arsize,vr_arsize}),
 .s_arburst({im_arburst,vr_arburst}),
 .s_arvalid({im_arvalid,vr_arvalid}),
 .s_arready({im_arready,vr_arready}),
 .s_rid({im_rid,vr_rid}),
 .s_rdata({im_rdata,vr_rdata}),
 .s_rresp({im_rresp,vr_rresp}),
 .s_rlast({im_rlast,vr_rlast}),
 .s_rvalid({im_rvalid,vr_rvalid}),
 .s_rready({im_rready,vr_rready}),
 .m_awid(v_awid),
 .m_awaddr(v_awaddr),
 .m_awlen(v_awlen),
 .m_awsize(v_awsize),
 .m_awburst(v_awburst),
 .m_awvalid(v_awvalid),
 .m_awready(v_awready),
 .m_wdata(v_wdata),
 .m_wstrb(v_wstrb),
 .m_wlast(v_wlast),
 .m_wvalid(v_wvalid),
 .m_wready(v_wready),
 .m_bid(v_bid),
 .m_bresp(v_bresp),
 .m_bvalid(v_bvalid),
 .m_bready(v_bready),
 .m_arid(v_arid),
 .m_araddr(v_araddr),
 .m_arlen(v_arlen),
 .m_arsize(v_arsize),
 .m_arburst(v_arburst),
 .m_arvalid(v_arvalid),
 .m_arready(v_arready),
 .m_rid(v_rid),
 .m_rdata(v_rdata),
 .m_rresp(v_rresp),
 .m_rlast(v_rlast),
 .m_rvalid(v_rvalid),
 .m_rready(v_rready));
soc_hmic_axi_adapter bridge(.clk(mem_clk),.rst(mem_reset),.ddr_ready,.protocol_fault(adapter_fault),
.s_awid(e_awid),
.s_awaddr(e_awaddr),
.s_awlen(e_awlen),
.s_awsize(e_awsize),
.s_awburst(e_awburst),
.s_awvalid(e_awvalid),
.s_awready(e_awready),
.s_wdata(e_wdata),
.s_wstrb(e_wstrb),
.s_wlast(e_wlast),
.s_wvalid(e_wvalid),
.s_wready(e_wready),
.s_bid(e_bid),
.s_bresp(e_bresp),
.s_bvalid(e_bvalid),
.s_bready(e_bready),
.s_arid(e_arid),
.s_araddr(e_araddr),
.s_arlen(e_arlen),
.s_arsize(e_arsize),
.s_arburst(e_arburst),
.s_arvalid(e_arvalid),
.s_arready(e_arready),
.s_rid(e_rid),
.s_rdata(e_rdata),
.s_rresp(e_rresp),
.s_rlast(e_rlast),
.s_rvalid(e_rvalid),
.s_rready(e_rready),
.m_awid,
.m_awaddr,
.m_awlen,
.m_awsize,
.m_awburst,
.m_awvalid,
.m_awready,
.m_wdata,
.m_wstrb,
.m_wlast,
.m_wvalid,
.m_wready,
.m_bid,
.m_bresp,
.m_bvalid,
.m_bready,
.m_arid,
.m_araddr,
.m_arlen,
.m_arsize,
.m_arburst,
.m_arvalid,
.m_arready,
.m_rid,
.m_rdata,
.m_rresp,
.m_rlast,
.m_rvalid,
.m_rready);
soc_ddr800 I_ips_ddr_top(.ref_clk,.resetn(!ddr_ref_reset),.core_clk(mem_clk),
 .pll_lock(ddr_pll_lock),.phy_pll_lock(ddr_phy_lock),.ddr_init_done,
.axi_awid(m_awid),
.axi_awaddr(m_awaddr),
.axi_awlen(m_awlen),
.axi_awsize(m_awsize),
.axi_awburst(m_awburst),
.axi_awvalid(m_awvalid),
.axi_awready(m_awready),
.axi_wdata(m_wdata),
.axi_wstrb(m_wstrb),
.axi_wlast(m_wlast),
.axi_wvalid(m_wvalid),
.axi_wready(m_wready),
.axi_bid(m_bid),
.axi_bresp(m_bresp),
.axi_bvalid(m_bvalid),
.axi_bready(m_bready),
.axi_arid(m_arid),
.axi_araddr(m_araddr),
.axi_arlen(m_arlen),
.axi_arsize(m_arsize),
.axi_arburst(m_arburst),
.axi_arvalid(m_arvalid),
.axi_arready(m_arready),
.axi_rid(m_rid),
.axi_rdata(m_rdata),
.axi_rresp(m_rresp),
.axi_rlast(m_rlast),
.axi_rvalid(m_rvalid),
.axi_rready(m_rready),
.mem_cs_n,.mem_rst_n,.mem_ck,.mem_ck_n,.mem_cke,.mem_ras_n,.mem_cas_n,.mem_we_n,.mem_odt,.mem_a,.mem_ba,.mem_dqs,.mem_dqs_n,.mem_dq,.mem_dm,
 .apb_clk(1'b0),.apb_rst_n(1'b0),.apb_sel(1'b0),.apb_enable(1'b0),
 .apb_addr(8'b0),.apb_write(1'b0),.apb_wdata(16'b0),
 .dbg_gate_start(1'b0),.dbg_cpd_start(1'b0),.dbg_ddrphy_rst_n(1'b1),.dbg_gpll_scan_rst(1'b0),
 .samp_position_dyn_adj(1'b0),.init_samp_position_even(32'b0),
 .wrcal_position_dyn_adj(1'b0),.init_wrcal_position(32'b0),.force_read_clk_ctrl(1'b0),
 .init_slip_step(16'b0),.init_read_clk_ctrl(12'b0),
 .debug_cpd_offset_adj(1'b0),.debug_cpd_offset_dir(1'b0),.debug_cpd_offset(10'b0),
 .ck_dly_en(1'b1),.init_ck_dly_step(8'b0),.dbg_ddrphy_init_fail(ddr_cal_fail)
);
endmodule

// PG2L200H native cell supported by the unmodified Logos2 technology library.
// All eight data bits use the same setting; no new state or reset is added.
module soc_camera_input_hold #(
 // 静态配置：parameter integer WIDTH=8,parameter HOLD_SET="1500ps"。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer WIDTH=8,parameter HOLD_SET="1500ps"
)(input wire [WIDTH-1:0] data_in,output wire [WIDTH-1:0] data_out);
// 按 genvar bit_index=0;bit_index<WIDTH;bit_index++ 的索引范围生成/更新各元素；索引上下界限定数组访问范围。
for(genvar bit_index=0;bit_index<WIDTH;bit_index++)begin:bit_hold
 GTP_ZEROHOLDDELAY #(.ZHOLD_SET(HOLD_SET)) hold_cell(.DI(data_in[bit_index]),.DO(data_out[bit_index]));
end
endmodule
