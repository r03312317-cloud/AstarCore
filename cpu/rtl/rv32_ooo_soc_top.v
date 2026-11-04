// Original integration boundary for RV32. External port spelling follows
// the neutral compatibility contract; no original CPU implementation is used.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// CPU 与存储系统的可复用连接层，组合核心、非对齐适配器和 I/D Cache。
// 把核心 32 位单次数据访问转换为 Cache 请求，同时向外提供 64
// 位行回填和写回通道。
// 本板 I-cache 为 128 组乘 2 路乘 64B，容量 16KiB；D-cache 为 64 组乘 2 路乘
// 64B，容量 8KiB。
// 对齐访问可直接通过；非对齐 RAM 访问由适配器拆成一至两个子事务。
// 可选的请求及响应寄存边界由参数选择，本板没有启用这些额外寄存级。
// 事件计数输入来自 Cache 的真实回填与写回事件，不能解释为总访问次数。
// 中断线和 mtime 由板级系统连接，处理器支持的逻辑不等于本板已经接入真实中断源。
// ENABLE_TRACE 在本层设为 0，部分宽调试口会被裁剪；
// 简洁提交位图仍连接板级计数器。
// 本外部接口是项目 req/gnt/rvalid 风格突发协议，不能直接称为完整 AXI 总线。
// 接口契约与阅读示例
// CPU内部是32位请求/返回，Cache行口是64位突发，两种接口的宽度和数量需分别理解。
// 非对齐适配器位于核心数据口与Cache之间，不影响指令口的成对取指组织。
// 本板注册响应参数关闭，性能仿真使用这一真实参数组合。
// 如果以后打开寄存边界，必须重新跑CRC、周期及最终时序，不能沿用本版成绩。
// I/D Cache事件先送核心事件计数，板级UART打印的是计时边界差值。
// CPU可复用的IRQ输入在本板系统中接零，文档将RTL支持与板级覆盖分开。
// 在迁移DDR时，RAM guard、地址映射与存储等待需要重新配置验证。
module rv32_ooo_soc_top #(
    // 参数 RESET_VECTOR：复位后第一个架构PC；本板在板级实例覆盖为0x10000000。
    parameter [31:0] RESET_VECTOR=32'h10000000,
    // 参数 ENABLE_PAIRING：允许最大两条分配/发射/提交；
    // 资源及依赖不满足时仍可仅推进一条。
    parameter ENABLE_PAIRING=1,
    // 参数 ENABLE_UNALIGNED：允许普通RAM非对齐拆分；
    // 外设与受保护范围仍由精确异常条件约束。
    parameter ENABLE_UNALIGNED=1,
    parameter LOAD_ORDER_ISSUE_LOOKAHEAD=1,
    // 参数 MEMORY_CREDITS：LSU在途/准备容量设置，
    // 不等于外部存储每拍并行返回条数。
    parameter MEMORY_CREDITS=3,
    // 参数 FETCH_CREDITS：按序取指请求信用上限；本板为2，
    // 前端指令队列容量另为8。
    parameter FETCH_CREDITS=2,
    // 参数 ENABLE_COMMITTED_RAS：启用只受提交训练的返回预测栈，
    // 不改变架构链接寄存器语义。
    parameter ENABLE_COMMITTED_RAS=1,
    // 参数 RAS_DEPTH：已提交返回地址预测栈深度，本板16，不是通用调用堆栈容量。
    parameter RAS_DEPTH=16,
    // 参数 HISTORY_BITS：预测历史位宽；本板H12，
    // 历史随预测和提交各有受控上下文。
    parameter HISTORY_BITS=8,
    // 参数 BIMODAL_INDEX_BITS：chooser和相关PC索引宽度；本板B9，
    // 局部方向启用后不应把表统称bimodal。
    parameter BIMODAL_INDEX_BITS=7,
    // 参数 GSHARE_INDEX_BITS：GShare方向表索引位数；本板G12对应4096个计数器。
    parameter GSHARE_INDEX_BITS=8,
    // 参数 REGISTER_INSTRUCTION_REQUEST：可选外部取指请求寄存边界；本板为0，
    // 分析使用实际延迟而非该可选模式。
    parameter REGISTER_INSTRUCTION_REQUEST=0,
    // 参数 REGISTER_RESPONSES：可选外部响应寄存边界；本板为0。
    parameter REGISTER_RESPONSES=0,
    // 参数 FAST_WAKEUP：真实完成标签可以在原ready置位前被当拍消费者使用，
    // 仍需广播valid资格。
    parameter FAST_WAKEUP=1,
    // 参数 ENABLE_SAME_CYCLE_REUSE：是否允许当拍发射释放槽立即被分配；本板为0，
    // 资源边界只看寄存占用。
    parameter ENABLE_SAME_CYCLE_REUSE=0,
    // 参数 CARRIED_COMPLETION_WRITES：由被捕获执行所有者携带目的写资格，
    // 减少完成时再查共享ROB元数据。
    parameter CARRIED_COMPLETION_WRITES=1,
    // 参数 DECOUPLED_ALLOCATION_PAYLOAD：把私有元数据预写与有效所有权分开，
    // 恢复时可取消所有权而无需门控宽数据。
    parameter DECOUPLED_ALLOCATION_PAYLOAD=1,
    // 参数 BANKED_ISSUE：启用银行化调度组织；
    // 结合stealing和不复用模式选择相对年龄调度器。
    parameter BANKED_ISSUE=1,
    parameter ENABLE_MDU_TURNOVER=1,
    parameter ENABLE_MDU_SPILL=1,
    parameter ENABLE_MUL_STREAM=1,
    parameter ENABLE_STEALING=1,
    parameter ENABLE_ORDERED_STORE_PREP=1,
    parameter ENABLE_STORE_HEAD_LOOKAHEAD=0,
    parameter ENABLE_STORE_ISSUE_LOOKAHEAD=0,
    // 参数 ENABLE_REDIRECT_FETCH：允许恢复地址当拍进入取指提案；
    // 本次130MHz基线启用。
    parameter ENABLE_REDIRECT_FETCH=1,
    // 参数 ENABLE_CURRENT_INTEGER_PAIR：
    // 允许严格限定的当前整数后继与队头同拍退休，不是任意未完成指令提前提交。
    parameter ENABLE_CURRENT_INTEGER_PAIR=1,
    // 参数 DISPATCH_BYPASS_UNMAPPED_ONLY：直接分配旁路要求源未被重命名，
    // 不沿复杂完成路径在本入口旁路取值。
    parameter DISPATCH_BYPASS_UNMAPPED_ONLY=1,
    // 参数 ENABLE_CONTROL_DISPATCH：允许符合条件的控制类操作使用直接分配路径，
    // 错预测恢复机制保持。
    parameter ENABLE_CONTROL_DISPATCH=1,
    // 参数 ENABLE_DISPATCH_BYPASS：
    // 可让新分配且源就绪的普通整数直接填入空闲EX槽，仍分配ROB所有者。
    parameter ENABLE_DISPATCH_BYPASS=1,
    // 参数 LOAD_BYPASS：允许年轻Load越过尚未进入LSU的老Load；
    // Store的顺序限制继续保留。
    parameter LOAD_BYPASS=0,
    // 参数 I_INDEX_BITS：I-cache组索引位宽；本板7位即128组，
    // 容量还需乘路数与64B行长。
    parameter I_INDEX_BITS=7,
    // 参数 I_WAYS：I-cache组相联路数；本板2路，奇偶字银行并非路数。
    parameter I_WAYS=2,
    // 参数 D_INDEX_BITS：D-cache组索引位宽；本板6位即64组。
    parameter D_INDEX_BITS=6,
    // 参数 D_WAYS：D-cache组相联路数；本板2路，每路拥有独立tag/valid/dirty。
    parameter D_WAYS=2,
    // 参数 ENABLE_FAST_ICROSS：双指令取指跨行且两行命中时使用并行下一行标签信息
    // ；错误/缺失保持原状态流程。
    parameter ENABLE_FAST_ICROSS=0,
    // 参数 ENABLE_DATA_RAM_GUARD：启用板级RAM边界知识，防止越界行访问；
    // 不是MMU或页级权限机制。
    parameter ENABLE_DATA_RAM_GUARD=0,
    // 参数 DATA_RAM_BASE：本板可访问RAM的包含式低边界，0x10000000。
    parameter [31:0] DATA_RAM_BASE=32'h00000000,
    // 参数 DATA_RAM_LIMIT：本板可访问RAM的包含式高边界，0x1000ffff。
    parameter [31:0] DATA_RAM_LIMIT=32'hffffffff
)(
    // 接口字段：input clk, reset。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input clk, reset,
    // 接口字段：output instr_req_o, input instr_gnt_i。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    output instr_req_o, input instr_gnt_i,
    // 接口字段：output [31:0] instr_addr_o, output instr_io_o。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    output [31:0] instr_addr_o, output instr_io_o,
    // 接口字段：input instr_rvalid_i, output instr_rready_o。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    input instr_rvalid_i, output instr_rready_o,
    // 接口字段：input [63:0] instr_rdata_i, input instr_err_i。
    // 错误或非法资格。需随相应有效指令/事务传播，最终在精确提交边界处理。
    input [63:0] instr_rdata_i, input instr_err_i,
    // 接口字段：input irq_timer_i, irq_software_i, irq_external_i。
    // 中断或时间输入。板级是否真实连接需另查system实例，
    // 通用端口不等于实板覆盖。
    input irq_timer_i, irq_software_i, irq_external_i,
    // 接口字段：input [63:0] mtime_i。
    // 中断或时间输入。板级是否真实连接需另查system实例，
    // 通用端口不等于实板覆盖。
    input [63:0] mtime_i,
    // 接口字段：output periph_req_o, input periph_gnt_i。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    output periph_req_o, input periph_gnt_i,
    // 接口字段：output periph_we_o, output [31:0] periph_addr_o。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    output periph_we_o, output [31:0] periph_addr_o,
    // 接口字段：output [31:0] periph_wdata_o, output [3:0] periph_be_o。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    output [31:0] periph_wdata_o, output [3:0] periph_be_o,
    // 接口字段：output [1:0] periph_size_o。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    output [1:0] periph_size_o,
    // 接口字段：input periph_rvalid_i, input periph_err_i。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    input periph_rvalid_i, input periph_err_i,
    // 接口字段：input [31:0] periph_rdata_i。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    input [31:0] periph_rdata_i,
    // 接口字段：output data_rd_req_o, input data_rd_gnt_i。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    output data_rd_req_o, input data_rd_gnt_i,
    // 接口字段：output data_rd_id_o, output [31:0] data_rd_addr_o。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    output data_rd_id_o, output [31:0] data_rd_addr_o,
    // 接口字段：input data_rd_rvalid_i, output data_rd_rready_o。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    input data_rd_rvalid_i, output data_rd_rready_o,
    // 接口字段：input data_rd_rid_i, input [63:0] data_rd_rdata_i。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    input data_rd_rid_i, input [63:0] data_rd_rdata_i,
    // 接口字段：input data_rd_err_i。
    // 错误或非法资格。需随相应有效指令/事务传播，最终在精确提交边界处理。
    input data_rd_err_i,
    // 接口字段：output data_wr_req_o, input data_wr_gnt_i。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    output data_wr_req_o, input data_wr_gnt_i,
    // 接口字段：output data_wr_last_o, output [31:0] data_wr_addr_o。
    // 访存载荷或字节控制。地址、大小与字节掩码必须属于同一笔已接受事务。
    output data_wr_last_o, output [31:0] data_wr_addr_o,
    // 接口字段：output [63:0] data_wr_data_o, output data_wr_id_o。
    // CPU 与存储系统的可复用连接层，组合核心、非对齐适配器和 I/D Cache。
    output [63:0] data_wr_data_o, output data_wr_id_o,
    // 接口字段：input data_wr_bvalid_i, input data_wr_berr_i, input
    // data_wr_bid_i。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    input data_wr_bvalid_i, input data_wr_berr_i, input data_wr_bid_i,
    // 接口字段：output [1:0] trace_retire_mask_o, trace_retire_count_o。
    // 观测接口。有效门控由对应assign决定，不作为功能事务接收条件。
    output [1:0] trace_retire_mask_o, trace_retire_count_o,
    // 接口字段：output [5:0] trace_retire_rob_id_o。
    // 观测接口。有效门控由对应assign决定，不作为功能事务接收条件。
    output [5:0] trace_retire_rob_id_o,
    // 接口字段：output trace_reschedule_o。
    // 观测接口。有效门控由对应assign决定，不作为功能事务接收条件。
    output trace_reschedule_o,
    // 接口字段：output [7:0] trace_reschedule_reason_o。
    // 观测接口。有效门控由对应assign决定，不作为功能事务接收条件。
    output [7:0] trace_reschedule_reason_o,
    // 接口字段：output trace_reschedule_trap_o。
    // 观测接口。有效门控由对应assign决定，不作为功能事务接收条件。
    output trace_reschedule_trap_o,
    // 接口字段：output trace_branch_miss_o, trace_jump_miss_o。
    // 观测接口。有效门控由对应assign决定，不作为功能事务接收条件。
    output trace_branch_miss_o, trace_jump_miss_o,
    // 接口字段：output trace_dispatch_stall_o, trace_frontend_stall_o。
    // 观测接口。有效门控由对应assign决定，不作为功能事务接收条件。
    output trace_dispatch_stall_o, trace_frontend_stall_o
);
    wire iv, ir, ipv, ipr;
    wire [31:0] ia;
    wire [63:0] ipd;
    wire [1:0] ipe;
    wire cache_iv,cache_ir,cache_ipv,cache_ipr;
    wire [31:0] cache_ia;
    wire [63:0] cache_ipd;
    wire [1:0] cache_ipe;
    reg i_request_valid,i_response_valid;
    reg [31:0] i_request_address;
    reg [63:0] i_response_data;
    reg [1:0] i_response_error;
    // Early/corrected fetch addresses now come from cursor/held registers.
    // Direct requests remove the historical extra request-register latency.
    // The frontend retains every accepted owner's sticky cancellation metadata.
    generate if(REGISTER_INSTRUCTION_REQUEST)begin:registered_instruction_request
        assign ir=!reset&&(!i_request_valid||cache_ir);
        assign cache_iv=!reset&&i_request_valid;
        assign cache_ia=i_request_address;
        always @(posedge clk)begin
            if(reset)i_request_valid<=0;
            else if(ir)begin i_request_valid<=iv;if(iv)i_request_address<=ia;end
        end
    end else begin:direct_instruction_request
        assign ir=cache_ir;assign cache_iv=iv;assign cache_ia=ia;
    end endgenerate
    generate if(REGISTER_RESPONSES)begin:registered_instruction_response
        assign cache_ipr=!reset&&(!i_response_valid||ipr);
        assign ipv=!reset&&i_response_valid;
        assign ipd=i_response_data;
        assign ipe=i_response_error;
        always @(posedge clk)begin
            if(reset)i_response_valid<=0;
            else if(cache_ipr)begin
                i_response_valid<=cache_ipv;
                if(cache_ipv)begin i_response_data<=cache_ipd;i_response_error<=cache_ipe;end
            end
        end
    end else begin:direct_instruction_response
        assign cache_ipr=ipr;
        assign ipv=cache_ipv;
        assign ipd=cache_ipd;
        assign ipe=cache_ipe;
    end endgenerate
    // Declare the module data wires before generate scopes. PDS otherwise
    // creates a local implicit dpd and ties the processor input to zero.
    wire [31:0] da, dwd, dpd;
    wire dv, dr, dw, dpv, dpr, dpe;
    wire raw_dpv,raw_dpr,raw_dpe;
    wire [31:0] raw_dpd;
    reg response_valid,response_error;
    reg [31:0] response_data;
    generate if(REGISTER_RESPONSES)begin:registered_data_response
        assign raw_dpr=!reset&&(!response_valid||dpr);
        assign dpv=!reset&&response_valid;
        assign dpd=response_data;
        assign dpe=response_error;
        always @(posedge clk)begin
            if(reset)response_valid<=0;
            else if(raw_dpr)begin
                response_valid<=raw_dpv;
                if(raw_dpv)begin response_data<=raw_dpd;response_error<=raw_dpe;end
            end
        end
    end else begin:direct_data_response
        assign raw_dpr=dpr;
        assign dpv=raw_dpv;
        assign dpd=raw_dpd;
        assign dpe=raw_dpe;
    end endgenerate
    wire [3:0] ds;
    wire [1:0] dz;
    wire fi, fd, maintenance_busy;
    wire event_i, event_d, event_w;
    wire [31:0] retire_pc0, retire_pc1, retire_instruction0, retire_instruction1;
    wire [4:0] retire_destination0, retire_destination1;
    wire [31:0] retire_value0, retire_value1;

    rv32_ooo_core #(.ENABLE_UNALIGNED(ENABLE_UNALIGNED),.RESET_VECTOR(RESET_VECTOR),.LOAD_ORDER_ISSUE_LOOKAHEAD(LOAD_ORDER_ISSUE_LOOKAHEAD),.MEMORY_CREDITS(MEMORY_CREDITS),.FETCH_CREDITS(FETCH_CREDITS),.ENABLE_COMMITTED_RAS(ENABLE_COMMITTED_RAS),.RAS_DEPTH(RAS_DEPTH),.HISTORY_BITS(HISTORY_BITS),.BIMODAL_INDEX_BITS(BIMODAL_INDEX_BITS),.GSHARE_INDEX_BITS(GSHARE_INDEX_BITS),.ENABLE_PAIRING(ENABLE_PAIRING),.FAST_WAKEUP(FAST_WAKEUP),.ENABLE_SAME_CYCLE_REUSE(ENABLE_SAME_CYCLE_REUSE),.CARRIED_COMPLETION_WRITES(CARRIED_COMPLETION_WRITES),.DECOUPLED_ALLOCATION_PAYLOAD(DECOUPLED_ALLOCATION_PAYLOAD),.BANKED_ISSUE(BANKED_ISSUE),.ENABLE_MDU_TURNOVER(ENABLE_MDU_TURNOVER),.ENABLE_MDU_SPILL(ENABLE_MDU_SPILL),.ENABLE_MUL_STREAM(ENABLE_MUL_STREAM),.ENABLE_STEALING(ENABLE_STEALING),.ENABLE_ORDERED_STORE_PREP(ENABLE_ORDERED_STORE_PREP),.ENABLE_STORE_HEAD_LOOKAHEAD(ENABLE_STORE_HEAD_LOOKAHEAD),.ENABLE_STORE_ISSUE_LOOKAHEAD(ENABLE_STORE_ISSUE_LOOKAHEAD),.ENABLE_REDIRECT_FETCH(ENABLE_REDIRECT_FETCH),.ENABLE_CURRENT_INTEGER_PAIR(ENABLE_CURRENT_INTEGER_PAIR),.ENABLE_CONTROL_DISPATCH(ENABLE_CONTROL_DISPATCH),.ENABLE_DISPATCH_BYPASS(ENABLE_DISPATCH_BYPASS),.DISPATCH_BYPASS_UNMAPPED_ONLY(DISPATCH_BYPASS_UNMAPPED_ONLY),.LOAD_BYPASS(LOAD_BYPASS),.ENABLE_TRACE(0)) processor (
        .clk(clk),.reset(reset),
        .imem_request_valid(iv),.imem_request_ready(ir),.imem_request_address(ia),
        .imem_response_valid(ipv),.imem_response_ready(ipr),
        .imem_response_data(ipd),.imem_response_error(ipe),
        .dmem_request_valid(dv),.dmem_request_ready(dr),.dmem_request_address(da),
        .dmem_request_write(dw),.dmem_request_size(dz),.dmem_request_wdata(dwd),
        .dmem_request_wstrb(ds),.dmem_response_valid(dpv),.dmem_response_ready(dpr),
        .dmem_response_rdata(dpd),.dmem_response_error(dpe),
        .irq_software(irq_software_i),.irq_timer(irq_timer_i),.irq_external(irq_external_i),
        .mtime(mtime_i),.event_icache_refill(event_i),.event_dcache_refill(event_d),
        .event_dcache_writeback(event_w),.fence_i(fi),.fence_d(fd),
        .debug_redirect(trace_reschedule_o),.debug_trap(trace_reschedule_trap_o),
        .debug_branch_miss(trace_branch_miss_o),.debug_jump_miss(trace_jump_miss_o),
        .debug_dispatch_stall(trace_dispatch_stall_o),.debug_frontend_stall(trace_frontend_stall_o),
        .retire_valid(trace_retire_mask_o),.retire_pc0(retire_pc0),.retire_pc1(retire_pc1),
        .retire_instruction0(retire_instruction0),.retire_instruction1(retire_instruction1),
        .retire_destination0(retire_destination0),.retire_destination1(retire_destination1),
        .retire_value0(retire_value0),.retire_value1(retire_value1)
    );
    assign trace_retire_count_o={1'b0,trace_retire_mask_o[0]}+{1'b0,trace_retire_mask_o[1]};
    // Internal reorder-buffer numbering has no architectural meaning and is
    // deliberately not emulated. Reason bit zero identifies a genuine trap;
    // other implementation-specific reason bits are not assigned meanings.
    assign trace_retire_rob_id_o=6'b0;
    assign trace_reschedule_reason_o={7'b0,trace_reschedule_trap_o};

    wire [31:0] split_address,split_wdata;wire [3:0] split_strobes;wire [1:0] split_size;
    wire split_valid,split_ready,split_write,split_rvalid,split_rready,split_error;
    wire [31:0] split_rdata;
    generate if(ENABLE_UNALIGNED)begin:unaligned_memory
        rv32_unaligned_adapter #(.ENABLE_DATA_RAM_GUARD(ENABLE_DATA_RAM_GUARD),
            .DATA_RAM_BASE(DATA_RAM_BASE),.DATA_RAM_LIMIT(DATA_RAM_LIMIT)) adapter(
            .clk(clk),.reset(reset),.u_valid(dv),.u_ready(dr),.u_address(da),.u_write(dw),
            .u_wdata(dwd),.u_wstrb(ds),.u_size(dz),.u_rvalid(raw_dpv),.u_rready(raw_dpr),
            .u_rdata(raw_dpd),.u_error(raw_dpe),.m_valid(split_valid),.m_ready(split_ready),
            .m_address(split_address),.m_write(split_write),.m_wdata(split_wdata),
            .m_wstrb(split_strobes),.m_size(split_size),.m_rvalid(split_rvalid),
            .m_rready(split_rready),.m_rdata(split_rdata),.m_error(split_error));
    end else begin:aligned_memory
        assign split_address=da;assign split_valid=dv;assign dr=split_ready;
        assign split_write=dw;assign split_wdata=dwd;assign split_strobes=ds;assign split_size=dz;
        assign raw_dpv=split_rvalid;assign split_rready=raw_dpr;
        assign raw_dpd=split_rdata;assign raw_dpe=split_error;
    end endgenerate

    rv32_memory_system #(.I_INDEX_BITS(I_INDEX_BITS),.I_WAYS(I_WAYS),.D_INDEX_BITS(D_INDEX_BITS),.D_WAYS(D_WAYS),
        .ENABLE_FAST_ICROSS(ENABLE_FAST_ICROSS),
        .ENABLE_DATA_RAM_GUARD(ENABLE_DATA_RAM_GUARD),
        .DATA_RAM_BASE(DATA_RAM_BASE),.DATA_RAM_LIMIT(DATA_RAM_LIMIT)) memory (
        .clk(clk),.reset(reset),
        .imem_request_valid(cache_iv),.imem_request_ready(cache_ir),.imem_request_address(cache_ia),
        .imem_response_valid(cache_ipv),.imem_response_ready(cache_ipr),
        .imem_response_data(cache_ipd),.imem_response_error(cache_ipe),
        .dmem_request_valid(split_valid),.dmem_request_ready(split_ready),.dmem_request_address(split_address),
        .dmem_request_write(split_write),.dmem_request_wdata(split_wdata),.dmem_request_wstrb(split_strobes),
        .dmem_request_size(split_size),.dmem_response_valid(split_rvalid),.dmem_response_ready(split_rready),
        .dmem_response_rdata(split_rdata),.dmem_response_error(split_error),
        .fence_i(fi),.fence_d(fd),.maintenance_busy(maintenance_busy),
        .event_icache_refill(event_i),.event_dcache_refill(event_d),.event_dcache_writeback(event_w),
        .instr_req_o(instr_req_o),.instr_gnt_i(instr_gnt_i),.instr_addr_o(instr_addr_o),
        .instr_io_o(instr_io_o),.instr_rvalid_i(instr_rvalid_i),.instr_rready_o(instr_rready_o),
        .instr_rdata_i(instr_rdata_i),.instr_err_i(instr_err_i),
        .data_rd_req_o(data_rd_req_o),.data_rd_gnt_i(data_rd_gnt_i),
        .data_rd_id_o(data_rd_id_o),.data_rd_addr_o(data_rd_addr_o),
        .data_rd_rvalid_i(data_rd_rvalid_i),.data_rd_rready_o(data_rd_rready_o),
        .data_rd_rid_i(data_rd_rid_i),.data_rd_rdata_i(data_rd_rdata_i),.data_rd_err_i(data_rd_err_i),
        .data_wr_req_o(data_wr_req_o),.data_wr_gnt_i(data_wr_gnt_i),
        .data_wr_last_o(data_wr_last_o),.data_wr_addr_o(data_wr_addr_o),
        .data_wr_data_o(data_wr_data_o),.data_wr_id_o(data_wr_id_o),
        .data_wr_bvalid_i(data_wr_bvalid_i),.data_wr_berr_i(data_wr_berr_i),.data_wr_bid_i(data_wr_bid_i),
        .periph_req_o(periph_req_o),.periph_gnt_i(periph_gnt_i),.periph_we_o(periph_we_o),
        .periph_addr_o(periph_addr_o),.periph_wdata_o(periph_wdata_o),
        .periph_be_o(periph_be_o),.periph_size_o(periph_size_o),
        .periph_rvalid_i(periph_rvalid_i),.periph_err_i(periph_err_i),.periph_rdata_i(periph_rdata_i)
    );
endmodule
