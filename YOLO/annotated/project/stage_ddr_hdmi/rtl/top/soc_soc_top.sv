// Merged V15 SoC. The synthesizable core exposes a DDR-controller AXI master,
// NOT physical DDR pins. All AXI pins are synchronous to mem_clk.
// Three independent clocks; common-reset contract is mandatory.
// R3: CP13 generic peripherals + immutable V15 four-stage CPU.
// 架构导读：soc_soc_top。
// SoC 集成层，连接 CPU、图执行器、NPU、共享张量加速器以及跨时钟域内存接口。
module soc_soc_top #(
 // 静态配置：parameter integer CACHE_CAPACITY_BYTES=16384。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer CACHE_CAPACITY_BYTES=16384,
 // 静态配置：parameter integer CPU_CLOCK_HZ=175000000,UART_BAUD=115200。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer CPU_CLOCK_HZ=175000000,UART_BAUD=115200,
 // 静态配置：parameter integer NPU_ROWS=16,NPU_COLS=8,NPU_K_TILE=64,NPU_OUTSTANDING=16。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer NPU_ROWS=16,NPU_COLS=8,NPU_K_TILE=64,NPU_OUTSTANDING=16,
 // 静态配置：parameter integer DMA_TIMEOUT_CYCLES=65536,CDC_ADDR_BITS=4。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer DMA_TIMEOUT_CYCLES=65536,CDC_ADDR_BITS=4,
 // Two bounded packets fit the existing sixteen-request NPU credit window.
  parameter integer DDR_MAX_BEATS=16,
  // 静态配置：parameter bit NPU_ORDERED_RETURN=1'b1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter bit NPU_ORDERED_RETURN=1'b1,
 // 静态配置：parameter bit NPU_A_PREFETCH=1'b1。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter bit NPU_A_PREFETCH=1'b1,
 // 静态配置：parameter integer NPU_RESULT_CHUNK_COLUMNS=32。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer NPU_RESULT_CHUNK_COLUMNS=32,
 // 静态配置：parameter bit BOARD_MMIO_ENABLE=0,GRAPH_EXECUTOR_ENABLE=BOARD_MMIO_ENABLE。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter bit BOARD_MMIO_ENABLE=0,GRAPH_EXECUTOR_ENABLE=BOARD_MMIO_ENABLE,
 // 静态配置：parameter integer BTB_INDEX_BITS=8,DTCM_READ_LATENCY=1。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter integer BTB_INDEX_BITS=8,DTCM_READ_LATENCY=1,
 // 静态配置：parameter bit REGISTERED_AGU=1,LOAD_BRANCH_BYPASS=1,MDU_WB_ONLY=1。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter bit REGISTERED_AGU=1,LOAD_BRANCH_BYPASS=1,MDU_WB_ONLY=1,
 // 静态配置：parameter logic [31:0] DDR_BASE=32'h80000000,CACHE_BASE=32'h84000000。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter logic [31:0] DDR_BASE=32'h80000000,CACHE_BASE=32'h84000000,
 // 静态配置：parameter logic [32:0] DDR_BYTES=33'h010000000,CACHE_BYTES=33'h004000000。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter logic [32:0] DDR_BYTES=33'h010000000,CACHE_BYTES=33'h004000000,
 // 静态配置：parameter ITCM_INIT_FILE="coremark-itcm.mem",DTCM_INIT_FILE="coremark-dtcm.mem"。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter ITCM_INIT_FILE="coremark-itcm.mem",DTCM_INIT_FILE="coremark-dtcm.mem"
)(
 // 接口声明：input logic cpu_clk,npu_clk,mem_clk,arst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic cpu_clk,npu_clk,mem_clk,arst,
 // Active high; synchronous to mem_clk. Assert only after DDR calibration.
 input logic mem_ready,
 // 接口声明：output logic cpu_reset,npu_reset,mem_reset。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 output logic cpu_reset,npu_reset,mem_reset,
 // 接口声明：input logic irq_nmi_fault,irq_fast_adc,irq_fast_pwm,irq_qei,irq_timer,irq_ipc。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic irq_nmi_fault,irq_fast_adc,irq_fast_pwm,irq_qei,irq_timer,irq_ipc,
 // 接口声明：input logic [7:0] irq_platform。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [7:0] irq_platform,
 // 接口声明：input logic [31:0] gpio_in,output logic [31:0] gpio_out,diagnostic_mailbox。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic [31:0] gpio_in,output logic [31:0] gpio_out,diagnostic_mailbox,
 // 接口声明：output logic uart_tx。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic uart_tx,
 // CP13 full-duplex UART is separate from the immutable V15 TX console.
 input logic uart_rx,output logic uart_aux_tx,
 // 接口声明：output logic [63:0] timer_gray。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [63:0] timer_gray,
 // Optional 0x60001000..0x60001fff board peripheral, synchronous to cpu_clk.
 output logic board_req_valid,input logic board_req_ready,
 // 接口声明：output logic [31:0] board_req_addr,board_req_wdata。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 output logic [31:0] board_req_addr,board_req_wdata,
 // 接口声明：output logic board_req_write,board_req_is_fetch,output logic [3:0] board_req_wstrb。
 // 按字节选择本次写入生效的 lane。
 output logic board_req_write,board_req_is_fetch,output logic [3:0] board_req_wstrb,
 // 接口声明：input logic board_rsp_valid,output logic board_rsp_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic board_rsp_valid,output logic board_rsp_ready,
 // 接口声明：input logic [31:0] board_rsp_rdata,input logic board_rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 input logic [31:0] board_rsp_rdata,input logic board_rsp_error,
 // 接口声明：output logic gex_win_req_valid,input logic gex_win_req_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 output logic gex_win_req_valid,input logic gex_win_req_ready,
 // 接口声明：output logic [15:0] gex_win_req_addr,output logic gex_win_req_write。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [15:0] gex_win_req_addr,output logic gex_win_req_write,
 // 接口声明：output logic [31:0] gex_win_req_wdata,output logic [3:0] gex_win_req_wstrb。
 // 按字节选择本次写入生效的 lane。
 output logic [31:0] gex_win_req_wdata,output logic [3:0] gex_win_req_wstrb,
 // 接口声明：input logic gex_win_rsp_valid,output logic gex_win_rsp_ready。
 // 表达接口或资源就绪；需结合相应有效/完成条件解释。
 input logic gex_win_rsp_valid,output logic gex_win_rsp_ready,
 // 接口声明：input logic [31:0] gex_win_rsp_rdata,input logic gex_win_rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 input logic [31:0] gex_win_rsp_rdata,input logic gex_win_rsp_error,
 // 接口声明：output logic gex_locked_out。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic gex_locked_out,

 // 接口声明：output logic [1:0][31:0] cache_hit_count,cache_miss_count,cache_bypass_count。
 // 记录数量或剩余进度，位宽限定可表达范围。
 output logic [1:0][31:0] cache_hit_count,cache_miss_count,cache_bypass_count,
 // 接口声明：output logic [31:0] maintenance_count。
 // 记录数量或剩余进度，位宽限定可表达范围。
 output logic [31:0] maintenance_count,
 // 接口声明：output logic routing_protocol_fault,ddr_protocol_fault。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 output logic routing_protocol_fault,ddr_protocol_fault,
 // 接口声明：output logic [31:0] ddr_accepted,ddr_completed,ddr_bursts。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 output logic [31:0] ddr_accepted,ddr_completed,ddr_bursts,
 // 接口声明：output logic core_sleeping,retire_valid_diag,output logic [31:0] retire_pc_diag。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic core_sleeping,retire_valid_diag,output logic [31:0] retire_pc_diag,
 // 接口声明：output logic irq_accept_diag,output logic [31:0] irq_vector_pc_diag。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 output logic irq_accept_diag,output logic [31:0] irq_vector_pc_diag,
 // 接口声明：output logic handler_entry_diag,fatal_state_diag。
 // 选择控制阶段，各编码的行为由状态分支定义。
 output logic handler_entry_diag,fatal_state_diag,
    // 接口声明：output logic [3:0] m_axi_awid,output logic [31:0] m_axi_awaddr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [3:0] m_axi_awid,output logic [31:0] m_axi_awaddr,
    // 接口声明：output logic [7:0] m_axi_awlen,output logic [2:0] m_axi_awsize。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [7:0] m_axi_awlen,output logic [2:0] m_axi_awsize,
    // 接口声明：output logic [1:0] m_axi_awburst,output logic m_axi_awlock。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [1:0] m_axi_awburst,output logic m_axi_awlock,
    // 接口声明：output logic [3:0] m_axi_awcache,output logic [2:0] m_axi_awprot。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] m_axi_awcache,output logic [2:0] m_axi_awprot,
    // 接口声明：output logic m_axi_awvalid,input logic m_axi_awready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic m_axi_awvalid,input logic m_axi_awready,
    // 接口声明：output logic [128-1:0] m_axi_wdata,output logic [128/8-1:0] m_axi_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [128-1:0] m_axi_wdata,output logic [128/8-1:0] m_axi_wstrb,
    // 接口声明：output logic m_axi_wlast,output logic m_axi_wvalid,input logic m_axi_wready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic m_axi_wlast,output logic m_axi_wvalid,input logic m_axi_wready,
    // 接口声明：input logic [3:0] m_axi_bid,input logic [1:0] m_axi_bresp。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [3:0] m_axi_bid,input logic [1:0] m_axi_bresp,
    // 接口声明：input logic m_axi_bvalid,output logic m_axi_bready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic m_axi_bvalid,output logic m_axi_bready,
    // 接口声明：output logic [3:0] m_axi_arid,output logic [31:0] m_axi_araddr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [3:0] m_axi_arid,output logic [31:0] m_axi_araddr,
    // 接口声明：output logic [7:0] m_axi_arlen,output logic [2:0] m_axi_arsize。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [7:0] m_axi_arlen,output logic [2:0] m_axi_arsize,
    // 接口声明：output logic [1:0] m_axi_arburst,output logic m_axi_arlock。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [1:0] m_axi_arburst,output logic m_axi_arlock,
    // 接口声明：output logic [3:0] m_axi_arcache,output logic [2:0] m_axi_arprot。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [3:0] m_axi_arcache,output logic [2:0] m_axi_arprot,
    // 接口声明：output logic m_axi_arvalid,input logic m_axi_arready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic m_axi_arvalid,input logic m_axi_arready,
    // 接口声明：input logic [3:0] m_axi_rid,input logic [128-1:0] m_axi_rdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [3:0] m_axi_rid,input logic [128-1:0] m_axi_rdata,
    // 接口声明：input logic [1:0] m_axi_rresp,input logic m_axi_rlast。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [1:0] m_axi_rresp,input logic m_axi_rlast,
    // 接口声明：input logic m_axi_rvalid,output logic m_axi_rready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic m_axi_rvalid,output logic m_axi_rready
);
 logic cpu_rst,npu_rst,mem_rst;
 soc_reset_sync cpu_reset_sync(.clk(cpu_clk),.arst,.rst(cpu_rst));
 soc_reset_sync npu_reset_sync(.clk(npu_clk),.arst,.rst(npu_rst));
 soc_reset_sync mem_reset_sync(.clk(mem_clk),.arst,.rst(mem_rst));
 assign cpu_reset=cpu_rst;assign npu_reset=npu_rst;assign mem_reset=mem_rst;
 logic cpu_req_valid,cpu_req_ready,cpu_req_write,cpu_req_fetch,cpu_rsp_valid,cpu_rsp_ready,cpu_rsp_error;
 logic [31:0] cpu_req_addr,cpu_req_wdata,cpu_rsp_rdata;logic [3:0] cpu_req_wstrb;
 logic n_req_valid,n_req_ready,n_req_write,n_rsp_valid,n_rsp_ready,n_rsp_error;
 logic [15:0] n_req_addr;logic [31:0] n_req_wdata,n_rsp_rdata;logic [3:0] n_req_wstrb;
 logic f_req_valid,f_req_ready,f_req_write,f_rsp_valid,f_rsp_ready,f_rsp_error;
 logic [15:0] f_req_addr;logic [31:0] f_req_wdata,f_rsp_rdata;logic [3:0] f_req_wstrb;
 logic cb_req_valid,cb_req_ready,cb_req_write,cb_req_is_fetch,cb_rsp_valid,cb_rsp_ready,cb_rsp_error;
 logic [31:0] cb_req_addr,cb_req_wdata,cb_rsp_rdata;logic [3:0] cb_req_wstrb;
 logic graph_busy,graph_poison,graph_input_consumed;
 logic nn_req_valid,nn_req_ready,nn_req_write,nn_rsp_valid,nn_rsp_ready,nn_rsp_error;
 logic [15:0] nn_req_addr;logic [31:0] nn_req_wdata,nn_rsp_rdata;logic [3:0] nn_req_wstrb;
 logic n_irq,n_irq_cpu,mem_fault_cpu;
 logic [31:0] legacy_addr,legacy_data,legacy_rdata;logic legacy_wen;logic [1:0] legacy_mask;
 // c*: local CPU/NPU side. m*: all synchronous to mem_clk after CDC.
 logic [2:0] cv,cr,cw,csv,csr,csw,cse,mv,mr,mw,msv,msr,msw,mse;
 logic [2:0][31:0] ca,ma;
 logic [2:0][127:0] cd,csd,md,msd;
 logic [2:0][15:0] cstrb,mstrb;
 logic [2:0][3:0] ci,csi,mi,msi;
 logic bv,br,bw,bsv,bsr,bsw,bse;
 logic [31:0] ba;logic [127:0] bd,bsd;logic [15:0] bstrb;logic [5:0] bi,bsi;
 logic cpu_protocol_fault,mux_protocol_fault,ddr_busy;
 logic n_irq_registered,mem_fault_registered,ddr_fault_registered,ddr_fault_local;
 pg_source_level_register irq_source(.clk(npu_clk),.rst(npu_rst),.level_in(n_irq&&!gex_locked),.level_out(n_irq_registered));
 pg_source_level_register memory_fault_source(.clk(mem_clk),.rst(mem_rst),
  .level_in(mux_protocol_fault),.level_out(mem_fault_registered));
 pg_source_level_register ddr_fault_source(.clk(mem_clk),.rst(mem_rst),
  .level_in(ddr_fault_local),.level_out(ddr_fault_registered));
 pg_level_sync irq_sync(.clk(cpu_clk),.rst(cpu_rst),.async_level(n_irq_registered),.level(n_irq_cpu));
 pg_level_sync memory_fault_sync(.clk(cpu_clk),.rst(cpu_rst),.async_level(mem_fault_registered),.level(mem_fault_cpu));
 pg_level_sync ddr_fault_sync(.clk(cpu_clk),.rst(cpu_rst),.async_level(ddr_fault_registered),.level(ddr_protocol_fault));
 assign routing_protocol_fault=cpu_protocol_fault|mem_fault_cpu|ddr_protocol_fault;
 initial begin
  // 条件分支：检查 CACHE_BASE<=DDR_BASE||{1'b0,CACHE_BASE}+CACHE_BYTES>{1'b0,DDR_BASE}+DDR_BYTES。
  if(CACHE_BASE<=DDR_BASE||{1'b0,CACHE_BASE}+CACHE_BYTES>{1'b0,DDR_BASE}+DDR_BYTES)
   $fatal(1,"SOC_ADDRESS_RANGE");
  // 条件分支：检查 CDC_ADDR_BITS<2。
  if(CDC_ADDR_BITS<2) $fatal(1,"SOC_CDC_DEPTH");
 end
 soc_cpu_tile_v15 #(
  .BTB_INDEX_BITS(BTB_INDEX_BITS),.REGISTERED_AGU(REGISTERED_AGU),.LOAD_BRANCH_BYPASS(LOAD_BRANCH_BYPASS),
  .MDU_WB_ONLY(MDU_WB_ONLY),.DTCM_READ_LATENCY(DTCM_READ_LATENCY),.EARLY_STORE_ACK(1'b1),
  .CACHE_CAPACITY_BYTES(CACHE_CAPACITY_BYTES),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES),
  .CACHE_BASE(CACHE_BASE),.CACHE_BYTES(CACHE_BYTES),.NPU_ENABLE(1'b1),
  .ITCM_INIT_FILE(ITCM_INIT_FILE),.DTCM_INIT_FILE(DTCM_INIT_FILE)) cpu(
  .clk(cpu_clk),.rst(cpu_rst),
  .system_req_valid(cpu_req_valid),.system_req_ready(cpu_req_ready),.system_req_addr(cpu_req_addr),
  .system_req_write(cpu_req_write),.system_req_wdata(cpu_req_wdata),.system_req_wstrb(cpu_req_wstrb),
  .system_req_is_fetch(cpu_req_fetch),.system_rsp_valid(cpu_rsp_valid),.system_rsp_ready(cpu_rsp_ready),
  .system_rsp_rdata(cpu_rsp_rdata),.system_rsp_error(cpu_rsp_error),
  .npu_req_valid(n_req_valid),.npu_req_ready(n_req_ready),.npu_req_addr(n_req_addr),.npu_req_write(n_req_write),
  .npu_req_wdata(n_req_wdata),.npu_req_wstrb(n_req_wstrb),.npu_rsp_valid(n_rsp_valid),.npu_rsp_ready(n_rsp_ready),
  .npu_rsp_rdata(n_rsp_rdata),.npu_rsp_error(n_rsp_error),.npu_irq(n_irq_cpu),
  .cache_mem_req_valid(cv[1:0]),.cache_mem_req_ready(cr[1:0]),.cache_mem_req_write(cw[1:0]),
  .cache_mem_req_addr(ca[1:0]),.cache_mem_req_wdata(cd[1:0]),.cache_mem_req_wstrb(cstrb[1:0]),.cache_mem_req_tag(ci[1:0]),
  .cache_mem_rsp_valid(csv[1:0]),.cache_mem_rsp_ready(csr[1:0]),.cache_mem_rsp_write(csw[1:0]),
  .cache_mem_rsp_rdata(csd[1:0]),.cache_mem_rsp_tag(csi[1:0]),.cache_mem_rsp_error(cse[1:0]),
  .cache_protocol_fault(cpu_protocol_fault),.cache_hit_count,.cache_miss_count,.cache_bypass_count,.maintenance_count,
  .irq_nmi_fault(irq_nmi_fault|routing_protocol_fault),.irq_fast_adc,.irq_fast_pwm,.irq_qei,.irq_timer,.irq_ipc,.irq_platform,
  .core_sleeping,.retire_valid_diag,.retire_pc_diag,.irq_accept_diag,.irq_vector_pc_diag,.handler_entry_diag,.fatal_state_diag
`ifdef DC_RT_VERIFICATION
  ,.trace_retire_instr(),.trace_retire_rd(),.trace_retire_rd_write(),.trace_retire_value(),.trace_retire_next_pc()
`endif
 );
 logic p_req_valid,p_req_ready,p_rsp_valid,p_rsp_ready,p_rsp_error;
 logic [31:0] p_rsp_rdata;
 // 条件分支：检查 BOARD_MMIO_ENABLE。
 if(BOARD_MMIO_ENABLE)begin:board_window
  logic [1:0] rv,rr,sv,sr,se;
  logic [1:0][31:0] sd;
  assign {cb_req_valid,p_req_valid}=rv;
  assign rr={cb_req_ready,p_req_ready};
  assign sv={cb_rsp_valid,p_rsp_valid};
  assign {cb_rsp_ready,p_rsp_ready}=sr;
  assign sd={cb_rsp_rdata,p_rsp_rdata};
  assign se={cb_rsp_error,p_rsp_error};
  soc_board_mmio_router router(
   .clk(cpu_clk),.rst(cpu_rst),.req_valid(cpu_req_valid),.req_ready(cpu_req_ready),
   .req_addr(cpu_req_addr),.req_write(cpu_req_write),.req_is_fetch(cpu_req_fetch),
   .req_wdata(cpu_req_wdata),.req_wstrb(cpu_req_wstrb),.rsp_valid(cpu_rsp_valid),
   .rsp_ready(cpu_rsp_ready),.rsp_rdata(cpu_rsp_rdata),.rsp_error(cpu_rsp_error),
   .m_req_valid(rv),.m_req_ready(rr),.m_req_addr(cb_req_addr),.m_req_wdata(cb_req_wdata),
   .m_req_write(cb_req_write),.m_req_is_fetch(cb_req_is_fetch),.m_req_wstrb(cb_req_wstrb),
   .m_rsp_valid(sv),.m_rsp_ready(sr),.m_rsp_rdata(sd),.m_rsp_error(se));
 end else begin:no_board_window
  assign p_req_valid=cpu_req_valid;
  assign cpu_req_ready=p_req_ready;
  assign cpu_rsp_valid=p_rsp_valid;
  assign p_rsp_ready=cpu_rsp_ready;
  assign cpu_rsp_rdata=p_rsp_rdata;
  assign cpu_rsp_error=p_rsp_error;
  assign cb_req_valid=0;assign cb_req_addr=0;assign cb_req_wdata=0;
  assign cb_req_write=0;assign cb_req_is_fetch=0;assign cb_req_wstrb=0;
  assign cb_rsp_ready=0;
 end
 soc_peripherals #(.CLK_FREQ(CPU_CLOCK_HZ),.BAUD_RATE(UART_BAUD)) peripherals(
  .clk(cpu_clk),.rst(cpu_rst),.req_valid(p_req_valid),.req_ready(p_req_ready),.req_addr(cpu_req_addr),
  .req_write(cpu_req_write),.req_is_fetch(cpu_req_fetch),.req_wdata(cpu_req_wdata),.req_wstrb(cpu_req_wstrb),
  .rsp_valid(p_rsp_valid),.rsp_ready(p_rsp_ready),.rsp_rdata(p_rsp_rdata),.rsp_error(p_rsp_error),
  .gpio_in,.gpio_out,.diagnostic_mailbox,.uart_tx,.uart_rx,.uart_aux_tx,.timer_gray);
 // 条件分支：检查 GRAPH_EXECUTOR_ENABLE。
 if(GRAPH_EXECUTOR_ENABLE)begin:graph_fabric
  soc_graph_mmio_fabric fabric(
   .clk(cpu_clk),.rst(cpu_rst),
   .cn_req_valid(n_req_valid),.cn_req_ready(n_req_ready),.cn_req_addr(n_req_addr),
   .cn_req_write(n_req_write),.cn_req_wdata(n_req_wdata),.cn_req_wstrb(n_req_wstrb),
   .cn_rsp_valid(n_rsp_valid),.cn_rsp_ready(n_rsp_ready),.cn_rsp_rdata(n_rsp_rdata),.cn_rsp_error(n_rsp_error),
   .n_req_valid(f_req_valid),.n_req_ready(f_req_ready),.n_req_addr(f_req_addr),
   .n_req_write(f_req_write),.n_req_wdata(f_req_wdata),.n_req_wstrb(f_req_wstrb),
   .n_rsp_valid(f_rsp_valid),.n_rsp_ready(f_rsp_ready),.n_rsp_rdata(f_rsp_rdata),.n_rsp_error(f_rsp_error),
   .cb_req_valid,.cb_req_ready,.cb_req_addr,.cb_req_wdata,.cb_req_write,.cb_req_fetch(cb_req_is_fetch),.cb_req_wstrb,
   .cb_rsp_valid,.cb_rsp_ready,.cb_rsp_rdata,.cb_rsp_error,
   .b_req_valid(board_req_valid),.b_req_ready(board_req_ready),.b_req_addr(board_req_addr),.b_req_wdata(board_req_wdata),
   .b_req_write(board_req_write),.b_req_fetch(board_req_is_fetch),.b_req_wstrb(board_req_wstrb),
   .b_rsp_valid(board_rsp_valid),.b_rsp_ready(board_rsp_ready),.b_rsp_rdata(board_rsp_rdata),.b_rsp_error(board_rsp_error),
   .graph_busy,.graph_poison,.graph_input_consumed);
 end else begin:no_graph_fabric
  assign f_req_valid=n_req_valid;assign n_req_ready=f_req_ready;assign f_req_addr=n_req_addr;
  assign f_req_write=n_req_write;assign f_req_wdata=n_req_wdata;assign f_req_wstrb=n_req_wstrb;
  assign n_rsp_valid=f_rsp_valid;assign f_rsp_ready=n_rsp_ready;assign n_rsp_rdata=f_rsp_rdata;assign n_rsp_error=f_rsp_error;
  assign board_req_valid=cb_req_valid;assign cb_req_ready=board_req_ready;assign board_req_addr=cb_req_addr;
  assign board_req_write=cb_req_write;assign board_req_wdata=cb_req_wdata;assign board_req_wstrb=cb_req_wstrb;
  assign board_req_is_fetch=cb_req_is_fetch;assign cb_rsp_valid=board_rsp_valid;assign board_rsp_ready=cb_rsp_ready;
  assign cb_rsp_rdata=board_rsp_rdata;assign cb_rsp_error=board_rsp_error;
  assign graph_busy=0;assign graph_poison=0;assign graph_input_consumed=0;
 end
 // CP13 single-owner request/response CDC; all side effects stay in npu_clk.
 pg_mmio_cdc npu_mmio_cdc(
  .src_clk(cpu_clk),.dst_clk(npu_clk),.arst,
  .s_req_valid(f_req_valid),.s_req_ready(f_req_ready),.s_req_write(f_req_write),
  .s_req_addr(f_req_addr),.s_req_wdata(f_req_wdata),.s_req_wstrb(f_req_wstrb),
  .s_rsp_valid(f_rsp_valid),.s_rsp_ready(f_rsp_ready),.s_rsp_rdata(f_rsp_rdata),.s_rsp_error(f_rsp_error),
  .m_req_valid(nn_req_valid),.m_req_ready(nn_req_ready),.m_req_write(nn_req_write),
  .m_req_addr(nn_req_addr),.m_req_wdata(nn_req_wdata),.m_req_wstrb(nn_req_wstrb),
  .m_rsp_valid(nn_rsp_valid),.m_rsp_ready(nn_rsp_ready),.m_rsp_rdata(nn_rsp_rdata),.m_rsp_error(nn_rsp_error));

 // New unused page1 is a compact Conv service. Page0 remains the exact
 // original NPU registerABI whenever the exclusive service lease is idle.
 logic old_req_ready,old_rsp_valid,old_rsp_error,service_req_ready,service_rsp_valid,service_rsp_error;
 logic [31:0] old_rsp_data,service_rsp_data;
 logic [31:0] cpu_legacy_addr,cpu_legacy_data,gex_legacy_addr,gex_legacy_data;
 logic cpu_legacy_wen,gex_legacy_wen;logic [1:0] cpu_legacy_mask,gex_legacy_mask;
 logic gex_locked,gex_poison,npu_exclusive_idle,busy_reject_valid;
 logic [1:0] npu_response_owner;
 wire select_service=nn_req_addr[15:8]==8'h01;
 assign nn_req_ready=select_service?service_req_ready:gex_locked?!busy_reject_valid:old_req_ready;
 assign nn_rsp_valid=npu_response_owner==1?service_rsp_valid:npu_response_owner==2?busy_reject_valid:old_rsp_valid;
 assign nn_rsp_rdata=npu_response_owner==1?service_rsp_data:npu_response_owner==2?32'd0:old_rsp_data;
 assign nn_rsp_error=npu_response_owner==1?service_rsp_error:npu_response_owner==2?1'b1:old_rsp_error;
 assign legacy_addr=gex_locked?gex_legacy_addr:cpu_legacy_addr;
 assign legacy_data=gex_locked?gex_legacy_data:cpu_legacy_data;
 assign legacy_wen=gex_locked?gex_legacy_wen:cpu_legacy_wen;
 assign legacy_mask=gex_locked?gex_legacy_mask:cpu_legacy_mask;
 assign gex_locked_out=gex_locked;
 // 过程边界：always_ff @(posedge npu_clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge npu_clk)begin
  // 复位相关判断：npu_rst；分支方向由信号极性与取反表达式决定。
  if(npu_rst)begin npu_response_owner<=0;busy_reject_valid<=0;end
  else begin
   // 握手/背压判断：busy_reject_valid&&nn_rsp_ready&&npu_response_owner==2。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(busy_reject_valid&&nn_rsp_ready&&npu_response_owner==2)busy_reject_valid<=0;
   // 握手/背压判断：nn_req_valid&&nn_req_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(nn_req_valid&&nn_req_ready)begin
    npu_response_owner<=select_service?2'd1:gex_locked?2'd2:2'd0;
    if(!select_service&&gex_locked)busy_reject_valid<=1;
   end
  end
 end
 logic resident_enable;
 logic [31:0] resident_model_epoch,resident_frame_epoch,resident_task_generation,resident_a_generation,resident_b_base;
 logic [4:0] resident_next_a_rows;
 logic [8:0] resident_b_columns;logic [4:0] resident_b_group;
 soc_conv_service conv_service(
  .clk(npu_clk),.rst(npu_rst),.can_start(npu_exclusive_idle&&old_req_ready&&!cpu_legacy_wen),
  .req_valid(nn_req_valid&&select_service),.req_ready(service_req_ready),.req_addr(nn_req_addr),
  .req_write(nn_req_write),.req_wdata(nn_req_wdata),.req_wstrb(nn_req_wstrb),
  .rsp_valid(service_rsp_valid),.rsp_ready(nn_rsp_ready&&npu_response_owner==1),.rsp_rdata(service_rsp_data),.rsp_error(service_rsp_error),
  .locked(gex_locked),.protocol_poison(gex_poison),
  .resident_enable,.resident_model_epoch,.resident_frame_epoch,.resident_task_generation,.resident_a_generation,.resident_b_base,.resident_b_columns,.resident_b_group,.resident_next_a_rows,
  .legacy_addr(gex_legacy_addr),.legacy_wdata(gex_legacy_data),.legacy_wen(gex_legacy_wen),.legacy_mask(gex_legacy_mask),.legacy_rdata,
  .Window_req_valid(gex_win_req_valid),.Window_req_ready(gex_win_req_ready),.Window_req_addr(gex_win_req_addr),
  .Window_req_write(gex_win_req_write),.Window_req_wdata(gex_win_req_wdata),.Window_req_wstrb(gex_win_req_wstrb),
  .Window_rsp_valid(gex_win_rsp_valid),.Window_rsp_ready(gex_win_rsp_ready),.Window_rsp_rdata(gex_win_rsp_rdata),.Window_rsp_error(gex_win_rsp_error));
 pg_npu_mmio_bridge npu_mmio(
  .clk(npu_clk),.rst(npu_rst),.req_valid(nn_req_valid&&!select_service&&!gex_locked),.req_ready(old_req_ready),.req_addr(nn_req_addr),
  .req_write(nn_req_write),.req_wdata(nn_req_wdata),.req_wstrb(nn_req_wstrb),
  .rsp_valid(old_rsp_valid),.rsp_ready(nn_rsp_ready&&npu_response_owner==0),.rsp_rdata(old_rsp_data),.rsp_error(old_rsp_error),
  .legacy_addr(cpu_legacy_addr),.legacy_wdata(cpu_legacy_data),.legacy_wen(cpu_legacy_wen),.legacy_mask(cpu_legacy_mask),.legacy_rdata);
 npu_accel_top #(.ARRAY_ROWS(NPU_ROWS),.ARRAY_COLS(NPU_COLS),.K_TILE(NPU_K_TILE),.ACC_W(48),
  .RESIDENT_RESULT_CHUNK_COLUMNS(NPU_RESULT_CHUNK_COLUMNS),
  .RESIDENT_A_PREFETCH(NPU_A_PREFETCH),.IN_ORDER_TRANSPORT(NPU_ORDERED_RETURN),.MEM_DATA_W(128),.MEM_ID_W(4),.MEM_OUTSTANDING(NPU_OUTSTANDING),.DMA_TIMEOUT_CYCLES(DMA_TIMEOUT_CYCLES),
  .MUL_PIPE_STAGES(2),.SPAD_LOAD_ELEMS(16),.A_PACKED_INT8_16(1'b1),
  .DRAM_BASE(DDR_BASE),.DRAM_BYTES({1'b0,CACHE_BASE}-{1'b0,DDR_BASE})) npu(
  .clk(npu_clk),.rst(npu_rst),.perip_addr(legacy_addr),.perip_wdata(legacy_data),.perip_wen(legacy_wen),
  .perip_mask(legacy_mask),.legacy_perip_rdata(32'd0),.combined_perip_rdata(legacy_rdata),.irq(n_irq),.exclusive_idle(npu_exclusive_idle),
  .resident_enable,.resident_model_epoch,.resident_frame_epoch,.resident_task_generation,.resident_a_generation,.resident_b_base,.resident_b_columns,.resident_b_group,.resident_next_a_rows,
  .dma_req_valid(cv[2]),.dma_req_ready(cr[2]),.dma_req_write(cw[2]),.dma_req_addr(ca[2]),
  .dma_req_wdata(cd[2]),.dma_req_wstrb(cstrb[2]),.dma_req_id(ci[2]),
  .dma_rsp_valid(csv[2]),.dma_rsp_ready(csr[2]),.dma_rsp_write(csw[2]),.dma_rsp_id(csi[2]),
  .dma_rsp_rdata(csd[2]),.dma_rsp_error(cse[2]));
 for(genvar g=0;g<3;g=g+1)begin:memory_cdc
  // Generate-time clock selection: NOT a runtime clock mux.
  wire source_clk=(g==2)?npu_clk:cpu_clk;
  wire source_rst=(g==2)?npu_rst:cpu_rst;
  pg_memory_cdc #(.DEPTH(1<<CDC_ADDR_BITS),.REGISTER_RSP_OUTPUT(g<2)) channel(
   .src_clk(source_clk),.dst_clk(mem_clk),.arst,
   .s_req_valid(cv[g]),.s_req_ready(cr[g]),.s_req_write(cw[g]),
   .s_req_addr(ca[g]),.s_req_wdata(cd[g]),.s_req_wstrb(cstrb[g]),.s_req_id(ci[g]),
   .s_rsp_valid(csv[g]),.s_rsp_ready(csr[g]),.s_rsp_write(csw[g]),.s_rsp_rdata(csd[g]),.s_rsp_id(csi[g]),.s_rsp_error(cse[g]),
   .m_req_valid(mv[g]),.m_req_ready(mr[g]),.m_req_write(mw[g]),
   .m_req_addr(ma[g]),.m_req_wdata(md[g]),.m_req_wstrb(mstrb[g]),.m_req_id(mi[g]),
   .m_rsp_valid(msv[g]),.m_rsp_ready(msr[g]),.m_rsp_write(msw[g]),.m_rsp_rdata(msd[g]),.m_rsp_id(msi[g]),.m_rsp_error(mse[g]));
 end
 logic [2:0] mux_ready;
 assign mr=mux_ready&{3{mem_ready}};
 pg_three_request_mux mux(
  .clk(mem_clk),.rst(mem_rst),.req_valid(mv&{3{mem_ready}}),.req_ready(mux_ready),.req_write(mw),.req_addr(ma),
  .req_wdata(md),.req_wstrb(mstrb),.req_id(mi),.rsp_valid(msv),.rsp_ready(msr),.rsp_write(msw),
  .rsp_rdata(msd),.rsp_id(msi),.rsp_error(mse),
  .m_req_valid(bv),.m_req_ready(br),.m_req_write(bw),.m_req_addr(ba),.m_req_wdata(bd),.m_req_wstrb(bstrb),.m_req_tag(bi),
  .m_rsp_valid(bsv),.m_rsp_ready(bsr),.m_rsp_write(bsw),.m_rsp_rdata(bsd),.m_rsp_tag(bsi),.m_rsp_error(bse),.protocol_fault(mux_protocol_fault));
 pg_ddr_burst_bridge #(.MAX_BEATS(DDR_MAX_BEATS),.TAG_W(6),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) ddr_user_bridge(
  .clk(mem_clk),.rst(mem_rst),.s_req_valid(bv),.s_req_ready(br),.s_req_write(bw),.s_req_addr(ba),
  .s_req_wdata(bd),.s_req_wstrb(bstrb),.s_req_tag(bi),.s_rsp_valid(bsv),.s_rsp_ready(bsr),
  .s_rsp_write(bsw),.s_rsp_rdata(bsd),.s_rsp_tag(bsi),.s_rsp_error(bse),.protocol_fault(ddr_fault_local),
  .busy(ddr_busy),.accepted_count(ddr_accepted),.completed_count(ddr_completed),.burst_count(ddr_bursts),
  .m_axi_awid,
  .m_axi_awaddr,
  .m_axi_awlen,
  .m_axi_awsize,
  .m_axi_awburst,
  .m_axi_awlock,
  .m_axi_awcache,
  .m_axi_awprot,
  .m_axi_awvalid,
  .m_axi_awready,
  .m_axi_wdata,
  .m_axi_wstrb,
  .m_axi_wlast,
  .m_axi_wvalid,
  .m_axi_wready,
  .m_axi_bid,
  .m_axi_bresp,
  .m_axi_bvalid,
  .m_axi_bready,
  .m_axi_arid,
  .m_axi_araddr,
  .m_axi_arlen,
  .m_axi_arsize,
  .m_axi_arburst,
  .m_axi_arlock,
  .m_axi_arcache,
  .m_axi_arprot,
  .m_axi_arvalid,
  .m_axi_arready,
  .m_axi_rid,
  .m_axi_rdata,
  .m_axi_rresp,
  .m_axi_rlast,
  .m_axi_rvalid,
  .m_axi_rready);
endmodule
