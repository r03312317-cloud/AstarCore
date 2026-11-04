// [ARCH] 供体 CPU 的独立包装模块随 14 个导入文件保留。
// [ARCH] 实际游戏入口是 rv32_game_cpu_tile，不直接实例化本供体顶层。
// [ARCH] 默认参数应与游戏包装层的实际覆写区分。
// [ARCH] 请求/响应和维护反馈连接核心与缓存系统。
// [ARCH] 这个文件用于原接口对照，不应将其独立板级映射照搬到游戏。
// Original integration boundary for RV32. External port spelling follows
// the neutral compatibility contract; no original CPU implementation is used.
module rv32_ooo_soc_top #(
    // [ARCH] RESET_VECTOR：独立默认入口可由包装层覆写；游戏入口实际为 0x10000000。
    parameter [31:0] RESET_VECTOR=32'h10000000,
    // [ARCH] ENABLE_PAIRING：控制双通路准入能力；第二条仍需要通过资源、依赖和异常条件。
    parameter ENABLE_PAIRING=1,
    // [ARCH] LOAD_ORDER_ISSUE_LOOKAHEAD：允许访存顺序预判参与准入，仍保留请求和响应所有权。
    parameter LOAD_ORDER_ISSUE_LOOKAHEAD=1,
    // [ARCH] MEMORY_CREDITS：限制在途/预留访存容量，不能与 ROB 或取指队列空位混用。
    parameter MEMORY_CREDITS=3,
    // [ARCH] FETCH_CREDITS：限制未返回取指请求；当前游戏覆写为 2。
    parameter FETCH_CREDITS=2,
    // [ARCH] ENABLE_COMMITTED_RAS：决定是否利用已退休调用/返回信息维护预测栈。
    parameter ENABLE_COMMITTED_RAS=1,
    // [ARCH] RAS_DEPTH：限定返回地址预测栈容量，游戏配置为 16。
    parameter RAS_DEPTH=16,
    // [ARCH] HISTORY_BITS：限定预测历史宽度，实例配置为 12；上下文需随指令保存。
    parameter HISTORY_BITS=8,
    // [ARCH] BIMODAL_INDEX_BITS：决定局部分量/选择器的索引宽度，游戏覆写为 9。
    parameter BIMODAL_INDEX_BITS=7,
    // [ARCH] GSHARE_INDEX_BITS：决定 GShare 表容量，游戏覆写为 12。
    parameter GSHARE_INDEX_BITS=8,
    // [ARCH] REGISTER_INSTRUCTION_REQUEST：已退休寄存器状态；银行选择/有效位共同屏蔽未初始化 RAM，并保持 x0 为零。
    parameter REGISTER_INSTRUCTION_REQUEST=0,
    // [ARCH] REGISTER_RESPONSES：已退休寄存器状态；银行选择/有效位共同屏蔽未初始化 RAM，并保持 x0 为零。
    parameter REGISTER_RESPONSES=0,
    // [ARCH] FAST_WAKEUP：允许使用有效完成广播尽早解析依赖，不改变生产者身份匹配。
    parameter FAST_WAKEUP=1,
    // [ARCH] ENABLE_SAME_CYCLE_REUSE：控制当拍释放槽的复用策略；当前集成关闭这一选项。
    parameter ENABLE_SAME_CYCLE_REUSE=0,
    // [ARCH] CARRIED_COMPLETION_WRITES：让完成事实携带写回资格，避免在晚端重新拼接身份。
    parameter CARRIED_COMPLETION_WRITES=1,
    // [ARCH] DECOUPLED_ALLOCATION_PAYLOAD：分离宽载荷提案与最终接纳，恢复仍控制真正所有权。
    parameter DECOUPLED_ALLOCATION_PAYLOAD=1,
    // [ARCH] BANKED_ISSUE：选择局部发射银行结构，与借用和复用选项共同决定调度路径。
    parameter BANKED_ISSUE=1,
    // [ARCH] ENABLE_MDU_TURNOVER：允许后端交接时利用可用容量，交接必须区分旧响应与新请求。
    parameter ENABLE_MDU_TURNOVER=1,
    // [ARCH] ENABLE_MDU_SPILL：保留乘除结果临时容纳路径，输出背压不能丢失旧所有者。
    parameter ENABLE_MDU_SPILL=1,
    // [ARCH] ENABLE_MUL_STREAM：启用独立低位乘法请求/响应流，与传统乘除路径区分归属。
    parameter ENABLE_MUL_STREAM=1,
    // [ARCH] ENABLE_STEALING：允许满足条件的整数候选利用其他可用通路。
    parameter ENABLE_STEALING=1,
    // [ARCH] ENABLE_ORDERED_STORE_PREP：允许提前准备 store 载荷，但外部副作用仍受顺序约束。
    parameter ENABLE_ORDERED_STORE_PREP=1,
    // [ARCH] ENABLE_STORE_HEAD_LOOKAHEAD：使用可证明的头部后继条件准备 store；不可跨越未解决异常。
    parameter ENABLE_STORE_HEAD_LOOKAHEAD=0,
    // [ARCH] ENABLE_STORE_ISSUE_LOOKAHEAD：控制 store 的前看选择，不取消旧 store 的顺序过滤。
    parameter ENABLE_STORE_ISSUE_LOOKAHEAD=0,
    // [ARCH] ENABLE_REDIRECT_FETCH：允许恢复地址参与取指请求形成；旧路径返回仍需取消资格。
    parameter ENABLE_REDIRECT_FETCH=1,
    // [ARCH] ENABLE_CURRENT_INTEGER_PAIR：让当前整数指令参与双通路选择，不免除依赖和异常检查。
    parameter ENABLE_CURRENT_INTEGER_PAIR=1,
    // [ARCH] DISPATCH_BYPASS_UNMAPPED_ONLY：限制分配绕过候选，避免未就绪的重命名依赖被误当成立即数值。
    parameter DISPATCH_BYPASS_UNMAPPED_ONLY=1,
    // [ARCH] ENABLE_CONTROL_DISPATCH：允许控制类指令走分配侧提案，最终恢复语义仍由核心完成。
    parameter ENABLE_CONTROL_DISPATCH=1,
    // [ARCH] ENABLE_DISPATCH_BYPASS：允许已就绪新指令进入空闲 EX，不能同时覆盖队列发射。
    parameter ENABLE_DISPATCH_BYPASS=1,
    // [ARCH] LOAD_BYPASS：允许年轻 load 越过尚未进入 LSU 的旧 load，旧 store 继续约束顺序。
    parameter LOAD_BYPASS=0,
    // [ARCH] I_INDEX_BITS：指令缓存每路组数为 2 的该次方，行大小固定为 64 字节。
    parameter I_INDEX_BITS=7,
    // [ARCH] I_WAYS：指令缓存路数；当前 2 路需同时解释独立 tag/valid 与组内替换位。
    parameter I_WAYS=2,
    // [ARCH] D_INDEX_BITS：数据缓存每路组数由该位宽决定，不能直接把它当作字节容量。
    parameter D_INDEX_BITS=6,
    // [ARCH] D_WAYS：数据缓存路数；脏状态与替换状态需要按每路/每组分别维护。
    parameter D_WAYS=2,
    // [ARCH] ENABLE_FAST_ICROSS：并行准备跨行标签查询；数据银行仍然是同步读。
    parameter ENABLE_FAST_ICROSS=0,
    // [ARCH] ENABLE_DATA_RAM_GUARD：供体可选单段范围守护，游戏关闭后由后端适配器检查边界。
    parameter ENABLE_DATA_RAM_GUARD=0,
    // [ARCH] DATA_RAM_BASE：范围守护的下边界，仅在对应选项生效时参与合法性检查。
    parameter [31:0] DATA_RAM_BASE=32'h00000000,
    // [ARCH] DATA_RAM_LIMIT：范围守护包含式上界，不应直接作为实际 DDR 容量声明。
    parameter [31:0] DATA_RAM_LIMIT=32'hffffffff
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input clk, reset,
    // [ARCH] instr_req_o：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output instr_req_o, input instr_gnt_i,
    // [ARCH] instr_addr_o：地址与当前请求/响应归属配对，不能独立于有效条件使用。
    output [31:0] instr_addr_o, output instr_io_o,
    // [ARCH] instr_rvalid_i：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    input instr_rvalid_i, output instr_rready_o,
    // [ARCH] instr_rdata_i：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    input [63:0] instr_rdata_i, input instr_err_i,
    input irq_timer_i, irq_software_i, irq_external_i,
    input [63:0] mtime_i,
    // [ARCH] periph_req_o：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output periph_req_o, input periph_gnt_i,
    output periph_we_o, output [31:0] periph_addr_o,
    // [ARCH] periph_wdata_o：写载荷需与地址和字节选通一起保持，背压不能提前覆盖。
    output [31:0] periph_wdata_o, output [3:0] periph_be_o,
    // [ARCH] periph_size_o：访问粒度与对齐/字节选通一起决定有效数据范围。
    output [1:0] periph_size_o,
    // [ARCH] periph_rvalid_i：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    input periph_rvalid_i, input periph_err_i,
    // [ARCH] periph_rdata_i：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    input [31:0] periph_rdata_i,
    // [ARCH] data_rd_req_o：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output data_rd_req_o, input data_rd_gnt_i,
    // [ARCH] data_rd_id_o：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    output data_rd_id_o, output [31:0] data_rd_addr_o,
    // [ARCH] data_rd_rvalid_i：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    input data_rd_rvalid_i, output data_rd_rready_o,
    // [ARCH] data_rd_rid_i：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    input data_rd_rid_i, input [63:0] data_rd_rdata_i,
    // [ARCH] data_rd_err_i：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    input data_rd_err_i,
    // [ARCH] data_wr_req_o：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    output data_wr_req_o, input data_wr_gnt_i,
    // [ARCH] data_wr_last_o：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    output data_wr_last_o, output [31:0] data_wr_addr_o,
    // [ARCH] data_wr_data_o：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    output [63:0] data_wr_data_o, output data_wr_id_o,
    // [ARCH] data_wr_bvalid_i：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    input data_wr_bvalid_i, input data_wr_berr_i, input data_wr_bid_i,
    output [1:0] trace_retire_mask_o, trace_retire_count_o,
    output [5:0] trace_retire_rob_id_o,
    output trace_reschedule_o,
    output [7:0] trace_reschedule_reason_o,
    output trace_reschedule_trap_o,
    output trace_branch_miss_o, trace_jump_miss_o,
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
    // [ARCH] i_request_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 ir, cache_iv, i_request_address 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg i_request_valid,i_response_valid;
    // [ARCH] i_request_address：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 cache_ia, i_request_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [31:0] i_request_address;
    // [ARCH] i_response_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 ipd, i_response_error 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [63:0] i_response_data;
    // [ARCH] i_response_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 ipe, i_response_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
    // [ARCH] response_valid（响应所有权）：标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 raw_dpr, dpv 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg response_valid,response_error;
    // [ARCH] response_data（响应所有权）：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 dpd, response_error 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
    // [ARCH] retire_pc0：保存拥有者的原始 PC，用于恢复、异常或对应包的诊断。
    wire [31:0] retire_pc0, retire_pc1, retire_instruction0, retire_instruction1;
    // [ARCH] retire_destination0：目的寄存器身份随指令保持，x0 写入仍须被抑制。
    wire [4:0] retire_destination0, retire_destination1;
    // [ARCH] retire_value0：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
    wire [31:0] retire_value0, retire_value1;

    rv32_ooo_core #(.RESET_VECTOR(RESET_VECTOR),.LOAD_ORDER_ISSUE_LOOKAHEAD(LOAD_ORDER_ISSUE_LOOKAHEAD),.MEMORY_CREDITS(MEMORY_CREDITS),.FETCH_CREDITS(FETCH_CREDITS),.ENABLE_COMMITTED_RAS(ENABLE_COMMITTED_RAS),.RAS_DEPTH(RAS_DEPTH),.HISTORY_BITS(HISTORY_BITS),.BIMODAL_INDEX_BITS(BIMODAL_INDEX_BITS),.GSHARE_INDEX_BITS(GSHARE_INDEX_BITS),.ENABLE_PAIRING(ENABLE_PAIRING),.FAST_WAKEUP(FAST_WAKEUP),.ENABLE_SAME_CYCLE_REUSE(ENABLE_SAME_CYCLE_REUSE),.CARRIED_COMPLETION_WRITES(CARRIED_COMPLETION_WRITES),.DECOUPLED_ALLOCATION_PAYLOAD(DECOUPLED_ALLOCATION_PAYLOAD),.BANKED_ISSUE(BANKED_ISSUE),.ENABLE_MDU_TURNOVER(ENABLE_MDU_TURNOVER),.ENABLE_MDU_SPILL(ENABLE_MDU_SPILL),.ENABLE_MUL_STREAM(ENABLE_MUL_STREAM),.ENABLE_STEALING(ENABLE_STEALING),.ENABLE_ORDERED_STORE_PREP(ENABLE_ORDERED_STORE_PREP),.ENABLE_STORE_HEAD_LOOKAHEAD(ENABLE_STORE_HEAD_LOOKAHEAD),.ENABLE_STORE_ISSUE_LOOKAHEAD(ENABLE_STORE_ISSUE_LOOKAHEAD),.ENABLE_REDIRECT_FETCH(ENABLE_REDIRECT_FETCH),.ENABLE_CURRENT_INTEGER_PAIR(ENABLE_CURRENT_INTEGER_PAIR),.ENABLE_CONTROL_DISPATCH(ENABLE_CONTROL_DISPATCH),.ENABLE_DISPATCH_BYPASS(ENABLE_DISPATCH_BYPASS),.DISPATCH_BYPASS_UNMAPPED_ONLY(DISPATCH_BYPASS_UNMAPPED_ONLY),.LOAD_BYPASS(LOAD_BYPASS),.ENABLE_TRACE(0)) processor (
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

    rv32_memory_system #(.I_INDEX_BITS(I_INDEX_BITS),.I_WAYS(I_WAYS),.D_INDEX_BITS(D_INDEX_BITS),.D_WAYS(D_WAYS),
        .ENABLE_FAST_ICROSS(ENABLE_FAST_ICROSS),
        .ENABLE_DATA_RAM_GUARD(ENABLE_DATA_RAM_GUARD),
        .DATA_RAM_BASE(DATA_RAM_BASE),.DATA_RAM_LIMIT(DATA_RAM_LIMIT)) memory (
        .clk(clk),.reset(reset),
        .imem_request_valid(cache_iv),.imem_request_ready(cache_ir),.imem_request_address(cache_ia),
        .imem_response_valid(cache_ipv),.imem_response_ready(cache_ipr),
        .imem_response_data(cache_ipd),.imem_response_error(cache_ipe),
        .dmem_request_valid(dv),.dmem_request_ready(dr),.dmem_request_address(da),
        .dmem_request_write(dw),.dmem_request_wdata(dwd),.dmem_request_wstrb(ds),
        .dmem_request_size(dz),.dmem_response_valid(raw_dpv),.dmem_response_ready(raw_dpr),
        .dmem_response_rdata(raw_dpd),.dmem_response_error(raw_dpe),
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
