// Legacy diagnostic top only. The NPU200 delivery top is soc_board_camera_top.
// First physical closure candidate: CPU/NPU use the board's 27 MHz clock.
// HMIC 1.16a provides its own user clock. No performance qualification implied.
// 架构导读：soc_board_top。
// 可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。
module soc_board_top #(
 // 静态配置：parameter ITCM_INIT_FILE="coremark-itcm.mem"。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter ITCM_INIT_FILE="coremark-itcm.mem",
 // 静态配置：parameter DTCM_INIT_FILE="coremark-dtcm.mem"。
 // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
 parameter DTCM_INIT_FILE="coremark-dtcm.mem"
)(
 // 接口声明：input logic sys_clk,clk_p,clk_n,rst_in,uart_rx。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 input logic sys_clk,clk_p,clk_n,rst_in,uart_rx,
 // 接口声明：output logic uart_tx。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic uart_tx,
 // 接口声明：output logic [7:0] led。
 // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
 output logic [7:0] led,
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
timeunit 1ns;timeprecision 1ps;
// 局部字段 logic ref_clk,mem_clk,cpu_reset,npu_reset,mem_reset。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
logic ref_clk,mem_clk,cpu_reset,npu_reset,mem_reset;
// 局部字段 logic ddr_init_done,ddr_ready,ddr_pll_lock,ddr_phy_lock,ddr_cal_fail。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic ddr_init_done,ddr_ready,ddr_pll_lock,ddr_phy_lock,ddr_cal_fail;
// 局部字段 logic adapter_fault,adapter_fault_cpu,ddr_ready_cpu,cal_fail_cpu。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic adapter_fault,adapter_fault_cpu,ddr_ready_cpu,cal_fail_cpu;
// 局部字段 logic soc_fault,ddr_fault,fatal_state,sleeping。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic soc_fault,ddr_fault,fatal_state,sleeping;
// 局部字段 logic [31:0] gpio_out,mailbox。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic [31:0] gpio_out,mailbox;
// 局部字段 logic unused_aux_tx。
// 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
logic unused_aux_tx;
// 局部字段 wire arst=!rst_in。
// 参与复位或清空条件；极性和同步边界以使用它的过程为准。
wire arst=!rst_in;
// Pin and input buffer settings copied from the official 200K camera top.
GTP_INBUFGDS #(.IOSTANDARD("DEFAULT"),.TERM_DIFF("ON")) u_refclk(
 .O(ref_clk),.I(clk_p),.IB(clk_n));
// Sample calibration state only in the HMIC user domain. Common board reset
// clears the controller and every SoC CDC queue; fault recovery needs reset.
always_ff @(posedge mem_clk or posedge arst)
 // 复位相关判断：arst；分支方向由信号极性与取反表达式决定。
 if(arst)ddr_ready<=0;
 else ddr_ready<=ddr_init_done&&ddr_pll_lock&&ddr_phy_lock&&!ddr_cal_fail;
pg_level_sync u_adapter_fault_sync(.clk(sys_clk),.rst(cpu_reset),.async_level(adapter_fault),.level(adapter_fault_cpu));
pg_level_sync u_ready_sync(.clk(sys_clk),.rst(cpu_reset),.async_level(ddr_ready),.level(ddr_ready_cpu));
pg_level_sync u_cal_fault_sync(.clk(sys_clk),.rst(cpu_reset),.async_level(ddr_cal_fail),.level(cal_fail_cpu));
// Board LEDs are active high; low four bits are CPU GPIO.
assign led={fatal_state|adapter_fault_cpu|soc_fault|ddr_fault,
             cal_fail_cpu,ddr_ready_cpu,!cpu_reset,gpio_out[3:0]};
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
logic [1:0] s_rresp;
logic s_rlast,s_rvalid;
logic s_rready;
logic [7:0] m_awid;
logic [29:0] m_awaddr;
logic [7:0] m_awlen;
logic [2:0] m_awsize;
logic [1:0] m_awburst;
logic m_awvalid;
logic m_awready;
logic [255:0] m_wdata;
logic [31:0] m_wstrb;
logic m_wlast,m_wvalid;
logic m_wready;
logic [7:0] m_bid;
logic [1:0] m_bresp;
logic m_bvalid;
logic m_bready;
logic [7:0] m_arid;
logic [29:0] m_araddr;
logic [7:0] m_arlen;
logic [2:0] m_arsize;
logic [1:0] m_arburst;
logic m_arvalid;
logic m_arready;
logic [7:0] m_rid;
logic [255:0] m_rdata;
logic [1:0] m_rresp;
logic m_rlast,m_rvalid;
logic m_rready;
soc_soc_top #(.CPU_CLOCK_HZ(27000000),.UART_BAUD(115200),
 .ITCM_INIT_FILE(ITCM_INIT_FILE),.DTCM_INIT_FILE(DTCM_INIT_FILE)) soc(
 .cpu_clk(sys_clk),.npu_clk(sys_clk),.mem_clk,.arst,.mem_ready(ddr_ready),
 .cpu_reset,.npu_reset,.mem_reset,.irq_nmi_fault(adapter_fault_cpu),
 .irq_fast_adc(1'b0),.irq_fast_pwm(1'b0),.irq_qei(1'b0),.irq_timer(1'b0),.irq_ipc(1'b0),.irq_platform(8'b0),
 .gpio_in({28'b0,cal_fail_cpu,adapter_fault_cpu,ddr_ready_cpu,1'b1}),.gpio_out,.diagnostic_mailbox(mailbox),.uart_tx,.uart_rx,.uart_aux_tx(unused_aux_tx),
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
soc_hmic_axi_adapter bridge(.clk(mem_clk),.rst(mem_reset),.ddr_ready,.protocol_fault(adapter_fault),
.s_awid,
.s_awaddr,
.s_awlen,
.s_awsize,
.s_awburst,
.s_awvalid,
.s_awready,
.s_wdata,
.s_wstrb,
.s_wlast,
.s_wvalid,
.s_wready,
.s_bid,
.s_bresp,
.s_bvalid,
.s_bready,
.s_arid,
.s_araddr,
.s_arlen,
.s_arsize,
.s_arburst,
.s_arvalid,
.s_arready,
.s_rid,
.s_rdata,
.s_rresp,
.s_rlast,
.s_rvalid,
.s_rready,
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
soc_ddr800 I_ips_ddr_top(.ref_clk,.resetn(rst_in),.core_clk(mem_clk),
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
