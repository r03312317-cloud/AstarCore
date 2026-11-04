// SPDX-License-Identifier: MIT
// Headless first-boot candidate for the Pango 200K MINI. The 27 MHz board
// oscillator clocks CPU/UART; the vendor DDR controller supplies its own
// 93.75 MHz UI clock. The common board reset resets both CDC domains and DDR.
// 保留的无图形板级候选将 CPU 加载器与 DDR 控制器连接起来。
// 最新 HDMI 演示实际使用 soc_linux_gui_top，不能把此文件当作最终板级入口。
// CPU 释放依赖 DDR 就绪和固件启动许可，下载位流本身不等于 Linux 镜像已就位。
// 故障信息和复位跨域处理须与相应 CDC 模块一起阅读。
module soc_linux_board_top #(
    // CPU_UART_DIV 给主机加载器与 CPU UART 共享的分频配置。
    parameter integer CPU_UART_DIV=234,
    // CPU_TIMER_DIV 把板级输入时钟分频为 mtime 节拍，本版覆盖为 27。
    parameter integer CPU_TIMER_DIV=27,
    // LOADER_TIMEOUT 定义加载协议等待边界，超时不能被当作一次成功回读。
    parameter integer LOADER_TIMEOUT=13500000
)(
    input wire sys_clk,clk_p,clk_n,rst_in,uart_rx,
    output wire uart_tx,output wire [7:0] led,
    output wire mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_cs_n,
    output wire mem_ras_n,mem_cas_n,mem_we_n,mem_odt,
    output wire [14:0] mem_a,output wire [2:0] mem_ba,
    inout wire [3:0] mem_dqs,mem_dqs_n,inout wire [31:0] mem_dq,
    output wire [3:0] mem_dm
);
    wire arst=!rst_in;
    wire ref_clk,mem_clk,sys_reset,mem_reset;
    // ddr_init_done 保存执行完成状态，完成不等于已经获得顺序提交资格。
    wire ddr_init_done,ddr_pll_lock,ddr_phy_lock,ddr_cal_fail;
    reg ddr_ready_mem;
    wire ddr_ready_cpu,cal_fail_cpu,adapter_fault_cpu,axi_poison_cpu;
    // bridge_fault 保存异常资格，须携带对应指令或请求身份交给后续处理。
    wire bridge_fault,loader_fault,boot_release;
    reg ddr_seen,fatal_sys;
    always @(posedge sys_clk) begin
        // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
        if(sys_reset) begin ddr_seen<=0;fatal_sys<=0;end
        else begin
            if(ddr_ready_cpu) ddr_seen<=1;
            if((ddr_seen && !ddr_ready_cpu) || loader_fault || bridge_fault ||
               adapter_fault_cpu || axi_poison_cpu || cal_fail_cpu) fatal_sys<=1;
        end
    end
    // cpu_reset 综合系统复位 DDR 就绪 启动许可及致命故障后的 CPU 复位条件。
    // cpu_reset 的资格组合为 sys_reset || !ddr_ready_cpu || !boot_release || loader_fault || bridge_fault || adapter_fault_cpu || axi_poison_cpu || cal_fail_cpu || fatal_sys。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    wire cpu_reset=sys_reset || !ddr_ready_cpu || !boot_release || loader_fault ||
                   bridge_fault || adapter_fault_cpu || axi_poison_cpu || cal_fail_cpu || fatal_sys;
    wire loader_tx,cpu_tx;
    // uart_tx 按 boot_release 进行来源选择。
    // 真分支取 cpu_tx；其余情况取 loader_tx。
    assign uart_tx=boot_release ? cpu_tx : loader_tx;
    // led 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {fatal_sys|loader_fault|bridge_fault|adapter_fault_cpu|axi_poison_cpu,；复制大括号表示重复位域，不是独立队列元素。
    assign led={fatal_sys|loader_fault|bridge_fault|adapter_fault_cpu|axi_poison_cpu,
                cal_fail_cpu,ddr_ready_cpu,boot_release,4'b0000};

    GTP_INBUFGDS #(.IOSTANDARD("DEFAULT"),.TERM_DIFF("ON")) u_refclk(
        .O(ref_clk),.I(clk_p),.IB(clk_n));
    // 子模块 soc_reset_sync 的职责：复位同步器允许异步请求复位，并在目标时钟域按寄存链同步释放。
    // 下列命名端口把本层信号连接到该模块，参数覆盖以实例中的原代码为准。
    soc_reset_sync u_sys_reset(.clk(sys_clk),.arst(arst),.rst(sys_reset));
    soc_reset_sync u_mem_reset(.clk(mem_clk),.arst(arst),.rst(mem_reset));
    always @(posedge mem_clk or posedge arst)
        if(arst) ddr_ready_mem<=0;
        else ddr_ready_mem<=ddr_init_done && ddr_pll_lock && ddr_phy_lock && !ddr_cal_fail;
    // 子模块 soc_level_sync 的职责：单比特状态通过本域同步链进入逻辑，只适用于足够稳定的电平信号。
    soc_level_sync u_ready_sync(.clk(sys_clk),.rst(sys_reset),.async_level(ddr_ready_mem),.level(ddr_ready_cpu));
    soc_level_sync u_cal_sync(.clk(sys_clk),.rst(sys_reset),.async_level(ddr_cal_fail),.level(cal_fail_cpu));
    // adapter_fault 保存异常资格，须携带对应指令或请求身份交给后续处理。
    wire adapter_fault,axi_poison;
    soc_level_sync u_fault_sync(.clk(sys_clk),.rst(sys_reset),.async_level(adapter_fault),.level(adapter_fault_cpu));
    soc_level_sync u_poison_sync(.clk(sys_clk),.rst(sys_reset),.async_level(axi_poison),.level(axi_poison_cpu));

    wire instr_req,instr_gnt,instr_io,instr_rvalid,instr_rready,instr_err;
    // instr_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    wire [31:0] instr_addr;wire [63:0] instr_rdata;
    wire dr_req,dr_gnt,dr_id,dr_rvalid,dr_rready,dr_rid,dr_err;
    // dr_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    wire [31:0] dr_addr;wire [63:0] dr_data;
    wire dw_req,dw_gnt,dw_last,dw_id,dw_bvalid,dw_bid,dw_berr;
    // dw_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    wire [31:0] dw_addr;wire [63:0] dw_data;
    // fb_base 软件提交的 framebuffer 地址，进入显示域前还需完整提交握手。
    wire [31:0] fb_base;wire fb_enable;
    // 子模块 rv32_linux_soc_top 的职责：Linux SoC 将 CPU 翻译桥 cache 和外设连接起来，外部仍是 cache 行接口。
    rv32_linux_soc_top #(.TIMER_DIV(CPU_TIMER_DIV),.UART_DIV(CPU_UART_DIV)) cpu(
        .clk(sys_clk),.reset(cpu_reset),.uart_rx(uart_rx),.uart_tx(cpu_tx),
        .vblank(1'b0),.framebuffer_base(fb_base),.framebuffer_enable(fb_enable),
        .reservation_kill(1'b0),
        .instr_req_o(instr_req),.instr_gnt_i(instr_gnt),.instr_addr_o(instr_addr),.instr_io_o(instr_io),
        .instr_rvalid_i(instr_rvalid),.instr_rready_o(instr_rready),.instr_rdata_i(instr_rdata),.instr_err_i(instr_err),
        .data_rd_req_o(dr_req),.data_rd_gnt_i(dr_gnt),.data_rd_id_o(dr_id),.data_rd_addr_o(dr_addr),
        .data_rd_rvalid_i(dr_rvalid),.data_rd_rready_o(dr_rready),.data_rd_rid_i(dr_rid),.data_rd_rdata_i(dr_data),.data_rd_err_i(dr_err),
        .data_wr_req_o(dw_req),.data_wr_gnt_i(dw_gnt),.data_wr_last_o(dw_last),.data_wr_addr_o(dw_addr),
        .data_wr_data_o(dw_data),.data_wr_id_o(dw_id),.data_wr_bvalid_i(dw_bvalid),.data_wr_berr_i(dw_berr),.data_wr_bid_i(dw_bid),
        .retire_valid(),.retire_pc0(),.retire_pc1(),.retire_instruction0(),.retire_instruction1(),
        .retire_destination0(),.retire_destination1(),.retire_value0(),.retire_value1(),
        .debug_trap(),.debug_privilege(),.debug_satp(),.debug_mepc(),.debug_mcause(),.debug_mtval(),
        .debug_sepc(),.debug_scause(),.debug_stval(),.debug_architectural_pc());

    wire l_req,l_ready,l_write,l_rsp,l_rsp_ready,l_rsp_write,l_rsp_error;
    // l_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    wire [31:0] l_addr;wire [127:0] l_wdata,l_rdata;wire [15:0] l_wstrb;wire [3:0] l_tag,l_rtag;
    wire c_req,c_ready,c_write,c_rsp,c_rsp_ready,c_rsp_write,c_rsp_error;
    // c_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    wire [31:0] c_addr;wire [127:0] c_wdata,c_rdata;wire [15:0] c_wstrb;wire [3:0] c_tag,c_rtag;
    // 子模块 rv32_uart_ddr_loader 的职责：串口加载器在 CPU 保持复位时把 OpenSBI Linux DTB 及根文件系统写入 DDR。
    rv32_uart_ddr_loader #(.UART_DIV(CPU_UART_DIV),.PACKET_TIMEOUT(LOADER_TIMEOUT)) loader(
        .clk(sys_clk),.reset(sys_reset),.ddr_ready(ddr_ready_cpu),.uart_rx(uart_rx),.uart_tx(loader_tx),
        .boot_release(boot_release),.loader_fault(loader_fault),
        .mem_req_valid(l_req),.mem_req_ready(l_ready),.mem_req_write(l_write),.mem_req_addr(l_addr),
        .mem_req_wdata(l_wdata),.mem_req_wstrb(l_wstrb),.mem_req_tag(l_tag),
        .mem_rsp_valid(l_rsp),.mem_rsp_ready(l_rsp_ready),.mem_rsp_write(l_rsp_write),
        .mem_rsp_rdata(l_rdata),.mem_rsp_tag(l_rtag),.mem_rsp_error(l_rsp_error));
    // 子模块 rv32_line_to_native128 的职责：此桥将 CPU 的 64 位行拍接口转换为 DDR 侧 128 位带标签事务。
    rv32_line_to_native128 line_bridge(
        .clk(sys_clk),.reset(cpu_reset),.enable(ddr_ready_cpu),
        .instr_req(instr_req),.instr_addr(instr_addr),.instr_io(instr_io),.instr_gnt(instr_gnt),
        .instr_rvalid(instr_rvalid),.instr_rready(instr_rready),.instr_rdata(instr_rdata),.instr_err(instr_err),
        .data_rd_req(dr_req),.data_rd_id(dr_id),.data_rd_addr(dr_addr),.data_rd_gnt(dr_gnt),
        .data_rd_rvalid(dr_rvalid),.data_rd_rready(dr_rready),.data_rd_rid(dr_rid),.data_rd_rdata(dr_data),.data_rd_err(dr_err),
        .data_wr_req(dw_req),.data_wr_last(dw_last),.data_wr_id(dw_id),.data_wr_addr(dw_addr),.data_wr_data(dw_data),
        .data_wr_gnt(dw_gnt),.data_wr_bvalid(dw_bvalid),.data_wr_bid(dw_bid),.data_wr_berr(dw_berr),
        .mem_req_valid(c_req),.mem_req_ready(c_ready),.mem_req_write(c_write),.mem_req_addr(c_addr),
        .mem_req_wdata(c_wdata),.mem_req_wstrb(c_wstrb),.mem_req_tag(c_tag),
        .mem_rsp_valid(c_rsp),.mem_rsp_ready(c_rsp_ready),.mem_rsp_write(c_rsp_write),
        .mem_rsp_rdata(c_rdata),.mem_rsp_tag(c_rtag),.mem_rsp_error(c_rsp_error),.protocol_fault(bridge_fault));

    // s_req_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
    wire s_req_ready,s_rsp_valid,s_rsp_write,s_rsp_error;
    wire [127:0] s_rsp_data;wire [3:0] s_rsp_tag;
    // l_ready 的资格组合为 !boot_release && s_req_ready。
    assign l_ready=!boot_release && s_req_ready;
    // c_ready 的资格组合为 boot_release && s_req_ready。
    assign c_ready=boot_release && s_req_ready;
    // l_rsp 的资格组合为 !boot_release && s_rsp_valid。
    assign l_rsp=!boot_release && s_rsp_valid;
    // c_rsp 的资格组合为 boot_release && s_rsp_valid。
    assign c_rsp=boot_release && s_rsp_valid;
    // l_rsp_write 连接到 s_rsp_write，两者在此路径上保持字段对应。
    assign l_rsp_write=s_rsp_write;assign c_rsp_write=s_rsp_write;
    // l_rdata 连接到 s_rsp_data，两者在此路径上保持字段对应。
    assign l_rdata=s_rsp_data;assign c_rdata=s_rsp_data;
    // l_rtag 连接到 s_rsp_tag，两者在此路径上保持字段对应。
    assign l_rtag=s_rsp_tag;assign c_rtag=s_rsp_tag;
    // l_rsp_error 连接到 s_rsp_error，两者在此路径上保持字段对应。
    assign l_rsp_error=s_rsp_error;assign c_rsp_error=s_rsp_error;
    wire m_req,m_ready,m_write,m_rsp,m_rsp_ready,m_rsp_write,m_rsp_error;
    // m_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    wire [31:0] m_addr;wire [127:0] m_wdata,m_rdata;wire [15:0] m_wstrb;wire [3:0] m_tag,m_rtag;
    // 子模块 soc_native_cdc 的职责：原生 DDR 请求与响应各用一条异步 FIFO 跨时钟域，形成完整往返通道。
    soc_native_cdc #(.DATA_W(128),.TAG_W(4),.FIFO_ADDR_BITS(2)) memory_cdc(
        .s_clk(sys_clk),.s_rst(sys_reset),.s_req_valid(boot_release?c_req:l_req),.s_req_ready(s_req_ready),
        .s_req_write(boot_release?c_write:l_write),.s_req_addr(boot_release?c_addr:l_addr),
        .s_req_wdata(boot_release?c_wdata:l_wdata),.s_req_wstrb(boot_release?c_wstrb:l_wstrb),
        .s_req_tag(boot_release?c_tag:l_tag),.s_rsp_valid(s_rsp_valid),
        .s_rsp_ready(boot_release?c_rsp_ready:l_rsp_ready),.s_rsp_write(s_rsp_write),
        .s_rsp_rdata(s_rsp_data),.s_rsp_tag(s_rsp_tag),.s_rsp_error(s_rsp_error),
        .m_clk(mem_clk),.m_rst(mem_reset),.m_req_valid(m_req),.m_req_ready(m_ready),
        .m_req_write(m_write),.m_req_addr(m_addr),.m_req_wdata(m_wdata),.m_req_wstrb(m_wstrb),.m_req_tag(m_tag),
        .m_rsp_valid(m_rsp),.m_rsp_ready(m_rsp_ready),.m_rsp_write(m_rsp_write),
        .m_rsp_rdata(m_rdata),.m_rsp_tag(m_rtag),.m_rsp_error(m_rsp_error));

    // s_awid 是 AXI 写地址通道的事务身份，响应需要返回给对应请求所有者。
    // 该通道只有在 valid 与 ready 同时成立时才完成一次实际传递。
    wire [3:0] s_awid,s_bid,s_arid,s_rid;wire [31:0] s_awaddr,s_araddr;
    // s_awlen 是 AXI 写地址通道的突发拍数减一，不能直接把编码值当作实际拍数。
    wire [7:0] s_awlen,s_arlen;wire [2:0] s_awsize,s_arsize;wire [1:0] s_awburst,s_arburst,s_bresp,s_rresp;
    // s_awvalid 是 AXI 写地址通道的本通道当前存在有效 payload 的资格。
    wire s_awvalid,s_awready,s_wlast,s_wvalid,s_wready,s_bvalid,s_bready;
    // s_arvalid 是 AXI 读地址通道的本通道当前存在有效 payload 的资格。
    wire s_arvalid,s_arready,s_rlast,s_rvalid,s_rready;wire [127:0] s_wdata,s_rdata;wire [15:0] s_wstrb;
    // 子模块 soc_rq_to_axi 的职责：请求转换层将简化存储请求映射到 AXI 地址 数据和响应通道。
    soc_rq_to_axi requests(.clk(mem_clk),.rst(mem_reset),.ddr_ready(ddr_ready_mem),
        .req_valid(m_req),.req_ready(m_ready),.req_write(m_write),.req_addr(m_addr),
        .req_wdata(m_wdata),.req_wstrb(m_wstrb),.req_id(m_tag),
        .rsp_valid(m_rsp),.rsp_ready(m_rsp_ready),.rsp_write(m_rsp_write),.rsp_id(m_rtag),
        .rsp_rdata(m_rdata),.rsp_error(m_rsp_error),.poisoned(axi_poison),
        .m_awid(s_awid),.m_awaddr(s_awaddr),.m_awlen(s_awlen),.m_awsize(s_awsize),.m_awburst(s_awburst),.m_awvalid(s_awvalid),.m_awready(s_awready),
        .m_wdata(s_wdata),.m_wstrb(s_wstrb),.m_wlast(s_wlast),.m_wvalid(s_wvalid),.m_wready(s_wready),
        .m_bid(s_bid),.m_bresp(s_bresp),.m_bvalid(s_bvalid),.m_bready(s_bready),
        .m_arid(s_arid),.m_araddr(s_araddr),.m_arlen(s_arlen),.m_arsize(s_arsize),.m_arburst(s_arburst),.m_arvalid(s_arvalid),.m_arready(s_arready),
        .m_rid(s_rid),.m_rdata(s_rdata),.m_rresp(s_rresp),.m_rlast(s_rlast),.m_rvalid(s_rvalid),.m_rready(s_rready));

    // m_awid 是 AXI 写地址通道的事务身份，响应需要返回给对应请求所有者。
    wire [7:0] m_awid,m_bid,m_arid,m_rid,m_awlen,m_arlen;
    // m_awaddr 是 AXI 写地址通道的字节地址，控制器侧还会按其地址窗进行重定位。
    wire [29:0] m_awaddr,m_araddr;wire [2:0] m_awsize,m_arsize;wire [1:0] m_awburst,m_arburst,m_bresp,m_rresp;
    // m_awvalid 是 AXI 写地址通道的本通道当前存在有效 payload 的资格。
    wire m_awvalid,m_awready,m_wlast,m_wvalid,m_wready,m_bvalid,m_bready;
    // m_arvalid 是 AXI 读地址通道的本通道当前存在有效 payload 的资格。
    wire m_arvalid,m_arready,m_rlast,m_rvalid,m_rready;wire [255:0] axi_wdata,axi_rdata;wire [31:0] axi_wstrb;
    // 子模块 soc_hmic_axi_adapter 的职责：此适配器把板级请求转换为 DDR 控制器 AXI 接口，保留地址 数据与响应的阶段关系。
    soc_hmic_axi_adapter bridge(.clk(mem_clk),.rst(mem_reset),.ddr_ready(ddr_ready_mem),.protocol_fault(adapter_fault),
        .s_awid(s_awid),.s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awsize(s_awsize),.s_awburst(s_awburst),.s_awvalid(s_awvalid),.s_awready(s_awready),
        .s_wdata(s_wdata),.s_wstrb(s_wstrb),.s_wlast(s_wlast),.s_wvalid(s_wvalid),.s_wready(s_wready),
        .s_bid(s_bid),.s_bresp(s_bresp),.s_bvalid(s_bvalid),.s_bready(s_bready),
        .s_arid(s_arid),.s_araddr(s_araddr),.s_arlen(s_arlen),.s_arsize(s_arsize),.s_arburst(s_arburst),.s_arvalid(s_arvalid),.s_arready(s_arready),
        .s_rid(s_rid),.s_rdata(s_rdata),.s_rresp(s_rresp),.s_rlast(s_rlast),.s_rvalid(s_rvalid),.s_rready(s_rready),
        .m_awid(m_awid),.m_awaddr(m_awaddr),.m_awlen(m_awlen),.m_awsize(m_awsize),.m_awburst(m_awburst),.m_awvalid(m_awvalid),.m_awready(m_awready),
        .m_wdata(axi_wdata),.m_wstrb(axi_wstrb),.m_wlast(m_wlast),.m_wvalid(m_wvalid),.m_wready(m_wready),
        .m_bid(m_bid),.m_bresp(m_bresp),.m_bvalid(m_bvalid),.m_bready(m_bready),
        .m_arid(m_arid),.m_araddr(m_araddr),.m_arlen(m_arlen),.m_arsize(m_arsize),.m_arburst(m_arburst),.m_arvalid(m_arvalid),.m_arready(m_arready),
        .m_rid(m_rid),.m_rdata(axi_rdata),.m_rresp(m_rresp),.m_rlast(m_rlast),.m_rvalid(m_rvalid),.m_rready(m_rready));
    soc_ddr800 I_ips_ddr_top(.ref_clk(ref_clk),.resetn(rst_in),.core_clk(mem_clk),
        .pll_lock(ddr_pll_lock),.phy_pll_lock(ddr_phy_lock),.ddr_init_done(ddr_init_done),
        .axi_awid(m_awid),.axi_awaddr(m_awaddr),.axi_awlen(m_awlen),.axi_awsize(m_awsize),.axi_awburst(m_awburst),.axi_awvalid(m_awvalid),.axi_awready(m_awready),
        .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wlast(m_wlast),.axi_wvalid(m_wvalid),.axi_wready(m_wready),
        .axi_bid(m_bid),.axi_bresp(m_bresp),.axi_bvalid(m_bvalid),.axi_bready(m_bready),
        .axi_arid(m_arid),.axi_araddr(m_araddr),.axi_arlen(m_arlen),.axi_arsize(m_arsize),.axi_arburst(m_arburst),.axi_arvalid(m_arvalid),.axi_arready(m_arready),
        .axi_rid(m_rid),.axi_rdata(axi_rdata),.axi_rresp(m_rresp),.axi_rlast(m_rlast),.axi_rvalid(m_rvalid),.axi_rready(m_rready),
        .mem_cs_n(mem_cs_n),.mem_rst_n(mem_rst_n),.mem_ck(mem_ck),.mem_ck_n(mem_ck_n),.mem_cke(mem_cke),
        .mem_ras_n(mem_ras_n),.mem_cas_n(mem_cas_n),.mem_we_n(mem_we_n),.mem_odt(mem_odt),
        .mem_a(mem_a),.mem_ba(mem_ba),.mem_dqs(mem_dqs),.mem_dqs_n(mem_dqs_n),.mem_dq(mem_dq),.mem_dm(mem_dm),
        .apb_clk(1'b0),.apb_rst_n(1'b0),.apb_sel(1'b0),.apb_enable(1'b0),.apb_addr(8'b0),.apb_write(1'b0),.apb_wdata(16'b0),
        .dbg_gate_start(1'b0),.dbg_cpd_start(1'b0),.dbg_ddrphy_rst_n(1'b1),.dbg_gpll_scan_rst(1'b0),
        .samp_position_dyn_adj(1'b0),.init_samp_position_even(32'b0),.wrcal_position_dyn_adj(1'b0),.init_wrcal_position(32'b0),
        .force_read_clk_ctrl(1'b0),.init_slip_step(16'b0),.init_read_clk_ctrl(12'b0),
        .debug_cpd_offset_adj(1'b0),.debug_cpd_offset_dir(1'b0),.debug_cpd_offset(10'b0),
        .ck_dly_en(1'b1),.init_ck_dly_step(8'b0),.dbg_ddrphy_init_fail(ddr_cal_fail));
endmodule
