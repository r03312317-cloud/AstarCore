// V3 timing: registered external requests; original TCM paths stay direct.
// V15 native core, original V15 TCM, and inherited two-way caches.
// New fast instruction router preserves the no-stall ITCM acceptance cycle.
// 架构导读：rv32_d1_cpu_tile。
// RV32 控制处理器的板级适配，模块名沿用 soc_cpu_tile_v15，实例化 rv32_ooo_core。
module soc_cpu_tile_v15 #(
    // 静态配置：parameter int unsigned BTB_INDEX_BITS=9。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned BTB_INDEX_BITS=9,
    // 静态配置：parameter bit REGISTERED_AGU=1, LOAD_BRANCH_BYPASS=1, MDU_WB_ONLY=1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit REGISTERED_AGU=1, LOAD_BRANCH_BYPASS=1, MDU_WB_ONLY=1,
    // 静态配置：parameter logic [31:0] HART_ID = 32'd0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] HART_ID            = 32'd0,
    // 静态配置：parameter logic [31:0] RESET_PC = 32'h1000_0000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] RESET_PC           = 32'h1000_0000,
    // 静态配置：parameter logic [31:0] FAST_VECTOR_BASE = RESET_PC + 32'h0000_0100。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] FAST_VECTOR_BASE   = RESET_PC + 32'h0000_0100,
    // 静态配置：parameter logic [31:0] FAST_VECTOR_STRIDE = 32'd4。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] FAST_VECTOR_STRIDE = 32'd4,
    // 静态配置：parameter logic BPU_ENABLE = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic        BPU_ENABLE         = 1'b1,
    // 静态配置：parameter logic NPU_ENABLE = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic        NPU_ENABLE         = 1'b1,
    // 静态配置：parameter int unsigned ITCM_ADDR_WIDTH = 14。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned ITCM_ADDR_WIDTH    = 14,
    // 静态配置：parameter int unsigned DTCM_ADDR_WIDTH = 14。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned DTCM_ADDR_WIDTH    = 14,
    // 静态配置：parameter int unsigned DTCM_READ_LATENCY = 1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int unsigned DTCM_READ_LATENCY = 1,
    // 静态配置：parameter ITCM_INIT_FILE = ""。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter ITCM_INIT_FILE     = "",
    // 静态配置：parameter DTCM_INIT_FILE = ""。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter DTCM_INIT_FILE     = "",
    // 静态配置：parameter integer CACHE_CAPACITY_BYTES=16384。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter integer      CACHE_CAPACITY_BYTES=16384,
    // 静态配置：parameter logic [31:0] DDR_BASE=32'h80000000, CACHE_BASE=32'h84000000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [31:0] DDR_BASE=32'h80000000, CACHE_BASE=32'h84000000,
    // 静态配置：parameter logic [32:0] DDR_BYTES=33'h010000000, CACHE_BYTES=33'h004000000。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter logic [32:0] DDR_BYTES=33'h010000000, CACHE_BYTES=33'h004000000,
    // 静态配置：parameter bit EARLY_STORE_ACK = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit          EARLY_STORE_ACK    = 1'b1
) (
    // 接口声明：input logic clk。
    // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
    input  logic        clk,
    // 接口声明：input logic rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input  logic        rst,

    // 接口声明：output logic system_req_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic        system_req_valid,
    // 接口声明：input logic system_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic        system_req_ready,
    // 接口声明：output logic [31:0] system_req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [31:0] system_req_addr,
    // 接口声明：output logic system_req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic        system_req_write,
    // 接口声明：output logic [31:0] system_req_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [31:0] system_req_wdata,
    // 接口声明：output logic [3:0] system_req_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [3:0]  system_req_wstrb,
    // 接口声明：output logic system_req_is_fetch。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic        system_req_is_fetch,
    // 接口声明：input logic system_rsp_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic        system_rsp_valid,
    // 接口声明：output logic system_rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic        system_rsp_ready,
    // 接口声明：input logic [31:0] system_rsp_rdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input  logic [31:0] system_rsp_rdata,
    // 接口声明：input logic system_rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input  logic        system_rsp_error,

    // 接口声明：output logic npu_req_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic        npu_req_valid,
    // 接口声明：input logic npu_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input  logic        npu_req_ready,
    // 接口声明：output logic [15:0] npu_req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [15:0] npu_req_addr,
    // 接口声明：output logic npu_req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic        npu_req_write,
    // 接口声明：output logic [31:0] npu_req_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [31:0] npu_req_wdata,
    // 接口声明：output logic [3:0] npu_req_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [3:0]  npu_req_wstrb,
    // 接口声明：input logic npu_rsp_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input  logic        npu_rsp_valid,
    // 接口声明：output logic npu_rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic        npu_rsp_ready,
    // 接口声明：input logic [31:0] npu_rsp_rdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input  logic [31:0] npu_rsp_rdata,
    // 接口声明：input logic npu_rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input  logic        npu_rsp_error,
    // 接口声明：input logic npu_irq。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input  logic        npu_irq,

    // 接口声明：output logic [1:0] cache_mem_req_valid,cache_mem_req_write。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [1:0] cache_mem_req_valid,cache_mem_req_write,
    // 接口声明：input logic [1:0] cache_mem_req_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic [1:0] cache_mem_req_ready,
    // 接口声明：output logic [1:0][31:0] cache_mem_req_addr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    output logic [1:0][31:0] cache_mem_req_addr,
    // 接口声明：output logic [1:0][127:0] cache_mem_req_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    output logic [1:0][127:0] cache_mem_req_wdata,
    // 接口声明：output logic [1:0][15:0] cache_mem_req_wstrb。
    // 按字节选择本次写入生效的 lane。
    output logic [1:0][15:0] cache_mem_req_wstrb,
    // 接口声明：output logic [1:0][3:0] cache_mem_req_tag。
    // 把返回信息关联到对应的已接受请求。
    output logic [1:0][3:0] cache_mem_req_tag,
    // 接口声明：input logic [1:0] cache_mem_rsp_valid,cache_mem_rsp_write,cache_mem_rsp_error。
    // 记录异常状态；查看置位与清除分支可确定其保持范围。
    input logic [1:0] cache_mem_rsp_valid,cache_mem_rsp_write,cache_mem_rsp_error,
    // 接口声明：output logic [1:0] cache_mem_rsp_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic [1:0] cache_mem_rsp_ready,
    // 接口声明：input logic [1:0][127:0] cache_mem_rsp_rdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [1:0][127:0] cache_mem_rsp_rdata,
    // 接口声明：input logic [1:0][3:0] cache_mem_rsp_tag。
    input logic [1:0][3:0] cache_mem_rsp_tag,
    output logic cache_protocol_fault,
    output logic [1:0][31:0] cache_hit_count,cache_miss_count,cache_bypass_count,
    output logic [31:0] maintenance_count,
    input  logic        irq_nmi_fault,
    input  logic        irq_fast_adc,
    input  logic        irq_fast_pwm,
    input  logic        irq_qei,
    input  logic        irq_timer,
    input  logic        irq_ipc,
    input  logic [7:0]  irq_platform,

    output logic        core_sleeping,
    output logic        retire_valid_diag,
    output logic [31:0] retire_pc_diag,
    output logic        irq_accept_diag,
    output logic [31:0] irq_vector_pc_diag,
    output logic        handler_entry_diag,
    output logic        fatal_state_diag
`ifdef DC_RT_VERIFICATION
    ,
    output logic [31:0] trace_retire_instr,
    output logic [4:0]  trace_retire_rd,
    output logic        trace_retire_rd_write,
    output logic [31:0] trace_retire_value,
    output logic [31:0] trace_retire_next_pc
`endif
);
 // Regional synchronous reset distribution; identity LUTs add no clock cycle.
 // Targeted preservation applies only to these drivers, not to their loads.
 (* syn_keep=1 *) wire region_reset_core;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_core(.I0(rst),.Z(region_reset_core));
 (* syn_keep=1 *) wire region_reset_memory;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_memory(.I0(rst),.Z(region_reset_memory));
 (* syn_keep=1 *) wire region_reset_data_boundary;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_data_boundary(.I0(rst),.Z(region_reset_data_boundary));
 (* syn_keep=1 *) wire region_reset_ifill;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_ifill(.I0(rst),.Z(region_reset_ifill));
 (* syn_keep=1 *) wire region_reset_data_lines;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_data_lines(.I0(rst),.Z(region_reset_data_lines));
 (* syn_keep=1 *) wire region_reset_uncached;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_uncached(.I0(rst),.Z(region_reset_uncached));
 (* syn_keep=1 *) wire region_reset_router;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_router(.I0(rst),.Z(region_reset_router));

    timeunit 1ns;timeprecision 1ps;
    // The D1 public tile boundary is unchanged. CPU + I/D cache are RV32.
    logic iv,ir,ipv,ipr;logic [31:0] ia;logic [63:0] ipd;logic [1:0] ipe;
    logic dv,dr,dw,dpv,dpr,dpe;logic [31:0] da,dwd,dpd;logic [3:0] ds;logic [1:0] dz;
    logic cv,cr,cw,cpv,cpr,cpe;logic [31:0] ca,cwd,cpd;logic [3:0] cs;logic [1:0] cz;
    logic memory_fence_i,memory_fence_d,boundary_fault,boundary_barrier,memory_ir;
    logic fi,fd,maint_busy,manual_maint,manual_maint_done;
    logic ei,ed,ew,ih,im,dh,dm;
    logic line_i_req,line_i_gnt,line_i_valid,line_i_ready,line_i_error,line_i_io;
    logic [31:0] line_i_addr;logic [63:0] line_i_data;
    logic line_d_req,line_d_gnt,line_d_id,line_d_valid,line_d_ready,line_d_error,line_d_rid;
    logic [31:0] line_d_addr;logic [63:0] line_d_data;
    logic wr_req,wr_gnt,wr_last,wr_id,b_valid,b_error,b_id;logic [31:0] wr_addr;logic [63:0] wr_data;
    logic preq,pgnt,pwrite,prvalid,perror;logic [31:0] paddr,pdata,prdata;logic [3:0] pbe;logic [1:0] psize;
    logic [1:0] retired_mask;logic [31:0] rpc0,rpc1,rinstr0,rinstr1,rv0,rv1;
    logic [4:0] rd0,rd1;logic trap_event,redirect_event;logic [31:0] trap_cause,trap_vector;
    logic [63:0] cycles,retired_total,cycle_snapshot,retired_snapshot;
    logic [31:0] irq_vector_q,retired_next_pc0;logic handler_armed;
    logic [31:0] writebacks,fences,maintenance_cycles,i_refills,d_refills;
    logic [31:0] mmio_submits,mmio_wait_cycles,uncached_ddr_count;
    logic [31:0] control_addr,control_rdata;
    logic ifault,dfault,pfault;
    assign ir=memory_ir&&!boundary_barrier;
    // The D1 maintenance store is owned before the blocking RV32 D-cache.
    // Sending it through D_IO_WAIT would prevent that cache from reaching
    // D_IDLE to sweep. No store acknowledgement precedes the real sweep.
    logic mdv,mdr,mdpv,mdpr,mdpe;logic [31:0] mdpd;
    logic [1:0] manual_state;
    logic manual_error,manual_seen_busy;
    wire manual_select=dw&&da==32'h30000100;
    assign mdv=dv&&!manual_select&&manual_state==0;
    assign dr=manual_state==0?(manual_select?(mdr&&!mdpv):mdr):1'b0;
    assign dpv=manual_state==3?1'b1:manual_state==0?mdpv:1'b0;
    assign dpd=manual_state==3?32'd0:mdpd;
    assign dpe=manual_state==3?manual_error:mdpe;
    assign mdpr=dpr&&manual_state==0;
    assign manual_maint=manual_state==1&&!manual_error;
    assign manual_maint_done=manual_state==3&&dpr&&!manual_error;
    // 过程边界：always_ff @(posedge clk)begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk)begin
      // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
      if(rst)begin manual_state<=0;manual_error<=0;manual_seen_busy<=0;end
      else case(manual_state)
        0:if(dv&&dr&&manual_select)begin
          manual_error<=dz!=2||ds!=15||dwd!=1;manual_seen_busy<=0;manual_state<=1;
        end
        1:manual_state<=manual_error?3:2;
        2:begin
          if(maint_busy)manual_seen_busy<=1;
          if(cache_protocol_fault)begin manual_error<=1;manual_state<=3;end
          else if(manual_seen_busy&&!maint_busy)manual_state<=3;
        end
        3:if(dpr)manual_state<=0;
      endcase
    end
    assign cache_protocol_fault=ifault|dfault|pfault|boundary_fault;
    assign core_sleeping=1'b0; // RV32 WFI has no exported physical sleep signal.
    assign retire_valid_diag=|retired_mask;
    assign retire_pc_diag=rpc0;
    assign irq_accept_diag=trap_event&&trap_cause[31];
    assign irq_vector_pc_diag=irq_vector_q;
    assign handler_entry_diag=handler_armed&&retired_mask[0]&&rpc0==irq_vector_q;
    assign fatal_state_diag=cache_protocol_fault;
`ifdef DC_RT_VERIFICATION
    assign trace_retire_instr=rinstr0;assign trace_retire_rd=rd0;
    assign trace_retire_rd_write=retired_mask[0]&&rd0!=0;
    assign trace_retire_value=rv0;assign trace_retire_next_pc=retired_next_pc0;
`endif
    rv32_ooo_core #(.RESET_VECTOR(RESET_PC),.ENABLE_PAIRING(1),.LOAD_ORDER_ISSUE_LOOKAHEAD(1),
      .MEMORY_CREDITS(3),.FETCH_CREDITS(2),.ENABLE_COMMITTED_RAS(1),.RAS_DEPTH(16),
      .ENABLE_ORDERED_STORE_PREP(1),.ENABLE_STORE_HEAD_LOOKAHEAD(1),.ENABLE_STORE_ISSUE_LOOKAHEAD(1),
      .ENABLE_REDIRECT_FETCH(0),.ENABLE_CURRENT_INTEGER_PAIR(1),.ENABLE_DISPATCH_BYPASS(1),
      .DISPATCH_BYPASS_UNMAPPED_ONLY(1),.ENABLE_CONTROL_DISPATCH(1),.BANKED_ISSUE(1),
      .DECOUPLED_ALLOCATION_PAYLOAD(1),.CARRIED_COMPLETION_WRITES(1),.FAST_WAKEUP(1),
      .ENABLE_SAME_CYCLE_REUSE(0),.ENABLE_TRACE(0)) core(
      .clk,.reset(region_reset_core),.d1_trap_cause(trap_cause),.d1_trap_vector(trap_vector),.d1_retire_next_pc0(retired_next_pc0),
      .imem_request_valid(iv),.imem_request_ready(ir),.imem_request_address(ia),
      .imem_response_valid(ipv),.imem_response_ready(ipr),.imem_response_data(ipd),.imem_response_error(ipe),
      .dmem_request_valid(cv),.dmem_request_ready(cr),.dmem_request_address(ca),.dmem_request_write(cw),
      .dmem_request_size(cz),.dmem_request_wdata(cwd),.dmem_request_wstrb(cs),
      .dmem_response_valid(cpv),.dmem_response_ready(cpr),.dmem_response_rdata(cpd),.dmem_response_error(cpe),
      .irq_software(irq_ipc),.irq_timer(irq_timer),
      .irq_external(npu_irq|(|irq_platform)|irq_fast_adc|irq_fast_pwm|irq_qei|irq_nmi_fault|cache_protocol_fault),
      .mtime(cycles),.event_icache_refill(ei),.event_dcache_refill(ed),.event_dcache_writeback(ew),
      .fence_i(fi),.fence_d(fd),.debug_redirect(redirect_event),.debug_trap(trap_event),
      .debug_branch_miss(),.debug_jump_miss(),.debug_dispatch_stall(),.debug_frontend_stall(),
      .retire_valid(retired_mask),.retire_pc0(rpc0),.retire_pc1(rpc1),
      .retire_instruction0(rinstr0),.retire_instruction1(rinstr1),.retire_destination0(rd0),
      .retire_destination1(rd1),.retire_value0(rv0),.retire_value1(rv1));
    rv32_d1_data_boundary data_boundary(
      .clk,.rst(region_reset_data_boundary),.c_valid(cv),.c_ready(cr),.c_addr(ca),.c_write(cw),.c_wdata(cwd),.c_strobe(cs),.c_size(cz),
      .c_rsp_valid(cpv),.c_rsp_ready(cpr),.c_rdata(cpd),.c_rsp_error(cpe),.c_fence_i(fi),.c_fence_d(fd),
      .m_valid(dv),.m_ready(dr),.m_addr(da),.m_write(dw),.m_wdata(dwd),.m_strobe(ds),.m_size(dz),
      .m_rsp_valid(dpv),.m_rsp_ready(dpr),.m_rdata(dpd),.m_rsp_error(dpe),
      .m_fence_i(memory_fence_i),.m_fence_d(memory_fence_d),.barrier_pending(boundary_barrier),.fault(boundary_fault));
    rv32_memory_system #(.I_INDEX_BITS(8),.D_INDEX_BITS(6),.D_WAYS(2),.ENABLE_FAST_ICROSS(1),
      .D1_COMPAT(1),.D1_CACHE_BASE(CACHE_BASE),.D1_CACHE_BYTES(CACHE_BYTES),
      .ENABLE_DATA_RAM_GUARD(1),.DATA_RAM_BASE(CACHE_BASE),.DATA_RAM_LIMIT(CACHE_BASE+32'(CACHE_BYTES)-1)) memory(
      .clk,.reset(region_reset_memory),.imem_request_valid(iv&&!boundary_barrier),.imem_request_ready(memory_ir),.imem_request_address(ia),
      .imem_response_valid(ipv),.imem_response_ready(ipr),.imem_response_data(ipd),.imem_response_error(ipe),
      .dmem_request_valid(mdv),.dmem_request_ready(mdr),.dmem_request_address(da),.dmem_request_write(dw),
      .dmem_request_wdata(dwd),.dmem_request_wstrb(ds),.dmem_request_size(dz),
      .dmem_response_valid(mdpv),.dmem_response_ready(mdpr),.dmem_response_rdata(mdpd),.dmem_response_error(mdpe),
      .fence_i(memory_fence_i|manual_maint),.fence_d(memory_fence_d|manual_maint),.maintenance_busy(maint_busy),
      .event_icache_refill(ei),.event_dcache_refill(ed),.event_dcache_writeback(ew),
      .event_icache_hit(ih),.event_icache_miss(im),.event_dcache_hit(dh),.event_dcache_miss(dm),
      .instr_req_o(line_i_req),.instr_gnt_i(line_i_gnt),.instr_addr_o(line_i_addr),.instr_io_o(line_i_io),
      .instr_rvalid_i(line_i_valid),.instr_rready_o(line_i_ready),.instr_rdata_i(line_i_data),.instr_err_i(line_i_error),
      .data_rd_req_o(line_d_req),.data_rd_gnt_i(line_d_gnt),.data_rd_id_o(line_d_id),.data_rd_addr_o(line_d_addr),
      .data_rd_rvalid_i(line_d_valid),.data_rd_rready_o(line_d_ready),.data_rd_rid_i(line_d_rid),
      .data_rd_rdata_i(line_d_data),.data_rd_err_i(line_d_error),
      .data_wr_req_o(wr_req),.data_wr_gnt_i(wr_gnt),.data_wr_last_o(wr_last),.data_wr_addr_o(wr_addr),
      .data_wr_data_o(wr_data),.data_wr_id_o(wr_id),.data_wr_bvalid_i(b_valid),.data_wr_berr_i(b_error),.data_wr_bid_i(b_id),
      .periph_req_o(preq),.periph_gnt_i(pgnt),.periph_we_o(pwrite),.periph_addr_o(paddr),.periph_wdata_o(pdata),
      .periph_be_o(pbe),.periph_size_o(psize),.periph_rvalid_i(prvalid),.periph_err_i(perror),.periph_rdata_i(prdata));
    rv32_d1_ifill #(.ITCM_ADDR_WIDTH(ITCM_ADDR_WIDTH),.ITCM_INIT_FILE(ITCM_INIT_FILE),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) ifill(
      .clk,.rst(region_reset_ifill),.req(line_i_req),.gnt(line_i_gnt),.addr(line_i_addr),.rvalid(line_i_valid),.rready(line_i_ready),
      .rdata(line_i_data),.error(line_i_error),.fault(ifault),
      .mem_req_valid(cache_mem_req_valid[0]),.mem_req_ready(cache_mem_req_ready[0]),.mem_req_write(cache_mem_req_write[0]),
      .mem_req_addr(cache_mem_req_addr[0]),.mem_req_wdata(cache_mem_req_wdata[0]),.mem_req_wstrb(cache_mem_req_wstrb[0]),.mem_req_tag(cache_mem_req_tag[0]),
      .mem_rsp_valid(cache_mem_rsp_valid[0]),.mem_rsp_ready(cache_mem_rsp_ready[0]),.mem_rsp_write(cache_mem_rsp_write[0]),
      .mem_rsp_rdata(cache_mem_rsp_rdata[0]),.mem_rsp_tag(cache_mem_rsp_tag[0]),.mem_rsp_error(cache_mem_rsp_error[0]));
    logic lv,lr,lw,lsv,lsr,lsw,lse;logic [31:0] la;logic [127:0] ld;logic [15:0] lm;logic [3:0] lt;
    logic pv,pr,pw,psv,psr,psw,pse,pactive;logic [31:0] pa;logic [127:0] pd;logic [15:0] pm;logic [3:0] pt;
    rv32_line128_adapter #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) data_lines(
      .clk,.rst(region_reset_data_lines),.rd_req(line_d_req),.rd_gnt(line_d_gnt),.rd_addr(line_d_addr),.rd_id(line_d_id),
      .rd_valid(line_d_valid),.rd_ready(line_d_ready),.rd_data(line_d_data),.rd_error(line_d_error),.rd_rid(line_d_rid),
      .wr_req,.wr_gnt,.wr_addr,.wr_data,.wr_last,.wr_id,.b_valid,.b_error,.b_id,.fault(dfault),
      .mem_req_valid(lv),.mem_req_ready(lr),.mem_req_write(lw),.mem_req_addr(la),.mem_req_wdata(ld),.mem_req_wstrb(lm),.mem_req_tag(lt),
      .mem_rsp_valid(lsv),.mem_rsp_ready(lsr),.mem_rsp_write(cache_mem_rsp_write[1]),.mem_rsp_rdata(cache_mem_rsp_rdata[1]),
      .mem_rsp_tag(cache_mem_rsp_tag[1]),.mem_rsp_error(cache_mem_rsp_error[1]));
    // A blocking RV32 D-cache owns either a cache line or one uncached request.
    // The selection is held across request/response, including DDR backpressure.
    assign cache_mem_req_valid[1]=pactive?pv:lv;assign cache_mem_req_write[1]=pactive?pw:lw;
    assign cache_mem_req_addr[1]=pactive?pa:la;assign cache_mem_req_wdata[1]=pactive?pd:ld;
    assign cache_mem_req_wstrb[1]=pactive?pm:lm;assign cache_mem_req_tag[1]=pactive?pt:lt;
    assign lr=cache_mem_req_ready[1]&&!pactive;assign pr=cache_mem_req_ready[1]&&pactive;
    assign lsv=cache_mem_rsp_valid[1]&&!pactive;assign psv=cache_mem_rsp_valid[1]&&pactive;
    assign cache_mem_rsp_ready[1]=pactive?psr:lsr;
    logic nv,nr,nw,nsv,nsr,nse;logic [31:0] na,nd,nsd;logic [3:0] nm;
    rv32_d1_uncached #(.DTCM_ADDR_WIDTH(DTCM_ADDR_WIDTH),.DTCM_READ_LATENCY(DTCM_READ_LATENCY),.DTCM_INIT_FILE(DTCM_INIT_FILE),
      .DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) uncached(
      .clk,.rst(region_reset_uncached),.req(preq),.gnt(pgnt),.write(pwrite),.addr(paddr),.wdata(pdata),.be(pbe),.size(psize),.rvalid(prvalid),.error(perror),.rdata(prdata),
      .native_req(nv),.native_ready(nr),.native_write(nw),.native_addr(na),.native_wdata(nd),.native_strb(nm),
      .native_rvalid(nsv),.native_rready(nsr),.native_rdata(nsd),.native_error(nse),
      .mem_active(pactive),.mem_req_valid(pv),.mem_req_ready(pr),.mem_req_write(pw),.mem_req_addr(pa),.mem_req_wdata(pd),.mem_req_wstrb(pm),.mem_req_tag(pt),
      .mem_rsp_valid(psv),.mem_rsp_ready(psr),.mem_rsp_write(cache_mem_rsp_write[1]),.mem_rsp_rdata(cache_mem_rsp_rdata[1]),
      .mem_rsp_tag(cache_mem_rsp_tag[1]),.mem_rsp_error(cache_mem_rsp_error[1]),
      .maintenance_req(),.maintenance_done(),.maintenance_busy(maint_busy),.cache_fault(cache_protocol_fault),
      .control_addr,.control_rdata,.fault(pfault),.mmio_submits,.mmio_wait_cycles,.ddr_uncached_count(uncached_ddr_count));
    dc_realtime_core_npu_router #(.NPU_ENABLE(NPU_ENABLE)) router(
      .clk,.rst(region_reset_router),.core_req_valid(nv),.core_req_ready(nr),.core_req_addr(na),.core_req_write(nw),.core_req_wdata(nd),.core_req_wstrb(nm),
      .core_req_is_fetch(1'b0),.core_rsp_valid(nsv),.core_rsp_ready(nsr),.core_rsp_rdata(nsd),.core_rsp_error(nse),
      .system_req_valid,.system_req_ready,.system_req_addr,.system_req_write,.system_req_wdata,.system_req_wstrb,.system_req_is_fetch,
      .system_rsp_valid,.system_rsp_ready,.system_rsp_rdata,.system_rsp_error,
      .npu_req_valid,.npu_req_ready,.npu_req_addr,.npu_req_write,.npu_req_wdata,.npu_req_wstrb,
      .npu_rsp_valid,.npu_rsp_ready,.npu_rsp_rdata,.npu_rsp_error);
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
      control_rdata=0;
      // 按 control_addr 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
      case(control_addr)
       32'h30000100:control_rdata=3;
       32'h30000104:control_rdata=cache_hit_count[0];32'h30000108:control_rdata=cache_miss_count[0];
       32'h3000010c:control_rdata=cache_hit_count[1];32'h30000110:control_rdata=cache_miss_count[1];
       32'h30000114:control_rdata=cache_bypass_count[1];32'h30000118:control_rdata=maintenance_count;
       32'h3000011c:control_rdata=cache_bypass_count[0];
       32'h30000200:control_rdata=32'h44323552; // "RV32D", performance ABI version 1
       32'h30000204:control_rdata=cycle_snapshot[31:0];32'h30000208:control_rdata=cycle_snapshot[63:32];
       32'h3000020c:control_rdata=retired_snapshot[31:0];32'h30000210:control_rdata=retired_snapshot[63:32];
       32'h30000214:control_rdata=writebacks;32'h30000218:control_rdata=fences;
       32'h3000021c:control_rdata=maintenance_cycles;32'h30000220:control_rdata=mmio_submits;
       32'h30000224:control_rdata=mmio_wait_cycles;32'h30000228:control_rdata=uncached_ddr_count;
       32'h3000022c:control_rdata={28'd0,maint_busy,pfault,dfault,ifault};
       32'h30000230:control_rdata=i_refills;32'h30000234:control_rdata=d_refills;
       default:control_rdata=0;
      endcase
    end
    // 过程边界：always_ff @(posedge clk)begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk)begin
      // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
      if(rst)begin cycles<=0;retired_total<=0;cycle_snapshot<=0;retired_snapshot<=0;irq_vector_q<=0;handler_armed<=0;
        cache_hit_count<='0;cache_miss_count<='0;cache_bypass_count<='0;maintenance_count<=0;
        writebacks<=0;fences<=0;maintenance_cycles<=0;i_refills<=0;d_refills<=0;end
      else begin
        cycles<=cycles+1'b1;retired_total<=retired_total+64'(retired_mask[0])+64'(retired_mask[1]);
        if(preq&&pgnt&&paddr==32'h30000204)cycle_snapshot<=cycles;
        if(preq&&pgnt&&paddr==32'h3000020c)retired_snapshot<=retired_total;
        if(handler_entry_diag)handler_armed<=0;
        if(irq_accept_diag)begin irq_vector_q<=trap_vector;handler_armed<=1;end
        if(ih)cache_hit_count[0]<=cache_hit_count[0]+1'b1;if(im)cache_miss_count[0]<=cache_miss_count[0]+1'b1;
        if(dh)cache_hit_count[1]<=cache_hit_count[1]+1'b1;if(dm)cache_miss_count[1]<=cache_miss_count[1]+1'b1;
        if(preq&&pgnt)cache_bypass_count[1]<=cache_bypass_count[1]+1'b1;
        if(ew)writebacks<=writebacks+1'b1;
        if(ei)i_refills<=i_refills+1'b1;if(ed)d_refills<=d_refills+1'b1;
        if(fi||fd||manual_maint)fences<=fences+1'b1;
        if(manual_maint_done)maintenance_count<=maintenance_count+1'b1;
        if(maint_busy)maintenance_cycles<=maintenance_cycles+1'b1;
      end
    end
`ifdef VERILATOR
    // 过程边界：always @(posedge clk)if(!rst&&pactive&&lv)$fatal(1,"RV32 D1 cache/uncached DDR owners overlap");。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always @(posedge clk)if(!rst&&pactive&&lv)$fatal(1,"RV32 D1 cache/uncached DDR owners overlap");
`endif
endmodule
