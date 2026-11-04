// Logical shared-clock integration. No physical HDMI/DDR/CDC claim.
// Linux experimental SoC. External cache-line ports are NOT a DDR PHY.
// RAM bounds are simulation/integration parameters, not measured board capacity.
// 此顶层把 Linux SoC 与参考 framebuffer 扫描器连接，服务系统级仿真。
// 实板综合入口为 inputs gui 下的 soc_linux_gui_top，不是本文件。
// 视频 DMA 与 CPU 内存访问在集成边界共享存储器，必须保持各自响应所有者。
// 此文件的存在不表示显示功能只在仿真运行；实板证据由实际板级顶层位流提供。
module rv32_linux_video_top #(
 // RESET_VECTOR 复位后取指入口，实板为 OpenSBI 固件基址。
 parameter [31:0] RESET_VECTOR=32'h80000000,
 parameter [31:0] RAM_BASE=32'h80000000,RAM_LIMIT=32'h84000000,
 parameter TIMER_DIV=100,UART_DIV=868
)(
 input clk,reset,input uart_rx,output uart_tx,output vblank,
 // framebuffer_enable 保存功能或输出使能，控制资格而非实际吞吐测量值。
 output [31:0] framebuffer_base,output framebuffer_enable,
 input reservation_kill,
 output instr_req_o,input instr_gnt_i,output [31:0]instr_addr_o,output instr_io_o,
 input instr_rvalid_i,output instr_rready_o,input[63:0]instr_rdata_i,input instr_err_i,
 output data_rd_req_o,input data_rd_gnt_i,output data_rd_id_o,output[31:0]data_rd_addr_o,
 input data_rd_rvalid_i,output data_rd_rready_o,input data_rd_rid_i,input[63:0]data_rd_rdata_i,input data_rd_err_i,
 output data_wr_req_o,input data_wr_gnt_i,output data_wr_last_o,output[31:0]data_wr_addr_o,
 output[63:0]data_wr_data_o,output data_wr_id_o,input data_wr_bvalid_i,data_wr_berr_i,data_wr_bid_i,
 output[1:0]retire_valid,output[31:0]retire_pc0,retire_pc1,retire_instruction0,retire_instruction1,
 output[4:0]retire_destination0,retire_destination1,output[31:0]retire_value0,retire_value1,
 // outputdebug_privilege 保存本次访问使用的特权级，权限检查必须与请求时刻一致。
 output debug_trap,output[1:0]debug_privilege,output[31:0]debug_satp,
 output[31:0]debug_mepc,debug_mcause,debug_mtval,debug_sepc,debug_scause,debug_stval,debug_architectural_pc,
 output video_de,video_hsync,video_vsync,output [15:0] video_rgb565,
 output [11:0] video_x,output [10:0] video_y,
 // display_req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output display_req_valid,input display_req_ready,output [31:0] display_req_addr,
 // display_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input display_rsp_valid,output display_rsp_ready,input [31:0] display_rsp_data,input display_rsp_error,
 // video_frame_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
 output [31:0] video_frame_count,video_underflow_rows,video_dma_errors,video_bounds_errors
);
 // 子模块 rv32_linux_soc_top 的职责：Linux SoC 将 CPU 翻译桥 cache 和外设连接起来，外部仍是 cache 行接口。
 // 下列命名端口把本层信号连接到该模块，参数覆盖以实例中的原代码为准。
 rv32_linux_soc_top #(.RESET_VECTOR(RESET_VECTOR),.RAM_BASE(RAM_BASE),.RAM_LIMIT(RAM_LIMIT),.TIMER_DIV(TIMER_DIV),.UART_DIV(UART_DIV)) soc(
  .clk(clk),
  .reset(reset),
  .uart_rx(uart_rx),
  .uart_tx(uart_tx),
  .vblank(vblank),
  .framebuffer_base(framebuffer_base),
  .framebuffer_enable(framebuffer_enable),
  .reservation_kill(reservation_kill),
  .instr_req_o(instr_req_o),
  .instr_gnt_i(instr_gnt_i),
  .instr_addr_o(instr_addr_o),
  .instr_io_o(instr_io_o),
  .instr_rvalid_i(instr_rvalid_i),
  .instr_rready_o(instr_rready_o),
  .instr_rdata_i(instr_rdata_i),
  .instr_err_i(instr_err_i),
  .data_rd_req_o(data_rd_req_o),
  .data_rd_gnt_i(data_rd_gnt_i),
  .data_rd_id_o(data_rd_id_o),
  .data_rd_addr_o(data_rd_addr_o),
  .data_rd_rvalid_i(data_rd_rvalid_i),
  .data_rd_rready_o(data_rd_rready_o),
  .data_rd_rid_i(data_rd_rid_i),
  .data_rd_rdata_i(data_rd_rdata_i),
  .data_rd_err_i(data_rd_err_i),
  .data_wr_req_o(data_wr_req_o),
  .data_wr_gnt_i(data_wr_gnt_i),
  .data_wr_last_o(data_wr_last_o),
  .data_wr_addr_o(data_wr_addr_o),
  .data_wr_data_o(data_wr_data_o),
  .data_wr_id_o(data_wr_id_o),
  .data_wr_bvalid_i(data_wr_bvalid_i),
  .data_wr_berr_i(data_wr_berr_i),
  .data_wr_bid_i(data_wr_bid_i),
  .retire_valid(retire_valid),
  .retire_pc0(retire_pc0),
  .retire_pc1(retire_pc1),
  .retire_instruction0(retire_instruction0),
  .retire_instruction1(retire_instruction1),
  .retire_destination0(retire_destination0),
  .retire_destination1(retire_destination1),
  .retire_value0(retire_value0),
  .retire_value1(retire_value1),
  .debug_trap(debug_trap),
  .debug_privilege(debug_privilege),
  .debug_satp(debug_satp),
  .debug_mepc(debug_mepc),
  .debug_mcause(debug_mcause),
  .debug_mtval(debug_mtval),
  .debug_sepc(debug_sepc),
  .debug_scause(debug_scause),
  .debug_stval(debug_stval),
  .debug_architectural_pc(debug_architectural_pc)
 );
 // 子模块 rv32_framebuffer_scanout 的职责：参考扫描器根据 framebuffer 地址读取 RGB565 数据并产生显示像素。
 rv32_framebuffer_scanout scanout(
 .clk(clk),.reset(reset),.active_base(framebuffer_base),.active_enable(framebuffer_enable),
 .vblank(vblank),.de(video_de),.hsync(video_hsync),.vsync(video_vsync),.pixel_rgb565(video_rgb565),.pixel_x(video_x),.pixel_y(video_y),
 .mem_req_valid(display_req_valid),.mem_req_ready(display_req_ready),.mem_req_addr(display_req_addr),
 .mem_rsp_valid(display_rsp_valid),.mem_rsp_ready(display_rsp_ready),.mem_rsp_data(display_rsp_data),.mem_rsp_error(display_rsp_error),
 .frame_count(video_frame_count),.underflow_rows(video_underflow_rows),.dma_errors(video_dma_errors),.bounds_errors(video_bounds_errors));
endmodule
