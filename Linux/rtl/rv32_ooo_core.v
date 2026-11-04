// Original RV32 OoO candidate. See SOURCE_PROVENANCE.md.
// Bounded local scheduling, captured operands and commit-boundary recovery.
// No external CPU implementation is an input to this source.
// CPU 的架构状态在 ROB 提交边界更新，执行完成与架构提交是两个不同事件。
// 取指前端交付最多两条指令，重命名将寄存器依赖绑定到 ROB 生产者。
// ROB 固定为 16 项；发射队列保留物理槽位身份，由 ACTIVE_QUEUE_MASK 裁剪。
// 两个整数通道与乘除及访存路径共享完成广播，实际配对受依赖和资源条件限制。
// 存储及带副作用的访问必须经过顺序许可，不能因推测执行而重复写入外设。
// Linux SoC 覆盖 LOAD_BYPASS 和 store lookahead 为零，不能套用裸机参数推断行为。
// M S U 特权状态、异常委托及中断判断集中在本模块，异常按程序顺序交付。
// satp 及 SUM MXR MPRV MPP 输出给地址翻译桥，SFENCE 在提交处触发。
// 分支误预测恢复使用已提交边界及仍存活的所有者信息，清除年轻指令的资格。
// FENCE I 在本平台还承载 D-cache 清理契约，供 framebuffer 的所有权转移使用。
// 调试端口描述分配 发射 完成 提交各阶段，不能把完成数直接当作退休指令数。
// 本次只增加阅读注释，原始源文件逐行保留；实板身份和校验结果见随包报告。
module rv32_ooo_core #(
    // RESET_VECTOR 复位后取指入口，实板为 OpenSBI 固件基址。
    parameter [31:0] RESET_VECTOR=32'h80000000,
    // ENABLE_PAIRING 控制双指令条件配对，仍受依赖和资源约束。
    parameter ENABLE_PAIRING=1,
    parameter LOAD_ORDER_ISSUE_LOOKAHEAD=1,
    // MEMORY_CREDITS 限制可占有的访存资源额度，不是无限在途访问。
    parameter MEMORY_CREDITS=3,
    // FETCH_CREDITS 限制在途取指请求资源，和前端队列占用共同约束容量。
    parameter FETCH_CREDITS=2,
    // ENABLE_COMMITTED_RAS 控制是否使用提交驱动的返回地址栈。
    parameter ENABLE_COMMITTED_RAS=1,
    // RAS_DEPTH 定义有限返回地址栈容量，容量之外的行为按原实现处理。
    parameter RAS_DEPTH=16,
    // HISTORY_BITS 规定分支历史位宽，Linux SoC 会覆盖模块默认值。
    parameter HISTORY_BITS=8,
    // BIMODAL_INDEX_BITS 规定 bimodal 表索引位数，不能把位数直接当作表项数量。
    parameter BIMODAL_INDEX_BITS=7,
    // GSHARE_INDEX_BITS 规定 gshare 表索引位数，实际容量随参数展开。
    parameter GSHARE_INDEX_BITS=8,
    parameter ENABLE_TRACE=0,
    parameter FAST_WAKEUP=1,
    parameter ENABLE_SAME_CYCLE_REUSE=0,
    parameter CARRIED_COMPLETION_WRITES=1,
    parameter DECOUPLED_ALLOCATION_PAYLOAD=1,
    parameter BANKED_ISSUE=1,
    parameter ENABLE_MDU_TURNOVER=1,
    parameter ENABLE_MDU_SPILL=1,
    parameter ENABLE_MUL_STREAM=1,
    parameter ENABLE_STEALING=1,
    parameter ENABLE_ORDERED_STORE_PREP=1,
    parameter ENABLE_STORE_HEAD_LOOKAHEAD=0,
    parameter ENABLE_STORE_ISSUE_LOOKAHEAD=0,
    parameter ENABLE_REDIRECT_FETCH=1,
    parameter ENABLE_CURRENT_INTEGER_PAIR=1,
    parameter DISPATCH_BYPASS_UNMAPPED_ONLY=1,
    parameter ENABLE_CONTROL_DISPATCH=1,
    parameter ENABLE_DISPATCH_BYPASS=1,
    // LOAD_BYPASS: a younger load may issue past an older load that has not yet
    // entered the LSU. Only older stores still order a load. Stores keep the
    // full original ordering. 0 reproduces the frozen baseline bit-for-bit.
    // LOAD_BYPASS 控制年轻 load 越过较老 load 的资格；Linux 集成显式关闭。
    parameter LOAD_BYPASS=0,
    // Sample unowned EX operands without a late issue-valid clock enable.
    // EX0 still holds its complete packet while the multiplier is blocked.
    parameter ENABLE_EX_OPERAND_STREAM=1,
    // Prepare low-MUL operands from the local complex bank at the existing
    // EX edge; this is an isolated payload copy, not an extra pipeline stage.
    parameter ENABLE_LOCAL_MUL_OPERANDS=1,
    // TOPT3: operation controls cross the existing EX edge already decoded.
    // No additional execution/forwarding latency is introduced.
    parameter ENABLE_PREDECODED_ALU=1,
    parameter ALU_DUAL_BARREL=1,
    parameter ENABLE_EARLY_JALR_CHECK=1,
    // TOPT4: PC/instruction travel with their existing queue owner. Selection
    // no longer reads ROB metadata after the late one-hot scheduler grant.
    parameter ENABLE_QUEUED_EXEC_PAYLOAD=1,
    // TOPT6: stream private queued PC/instruction at the existing EX edge.
    // Effective only with ordered scheduling and queued execution payload.
    parameter ENABLE_EX_METADATA_STREAM=0,
    // Experimental: low-MUL integer dependencies cross the existing queue
    // operand register edge. No new pipeline or architectural state is added.
    parameter ENABLE_MUL_INTEGER_BOUNDARY=1,
    // TOPT5: fixed slot identities, with inactive physical rows removed.
    // 0..3/4..7 are integer banks; 8..11 are complex.
    // ACTIVE_QUEUE_MASK 按固定物理槽位掩码裁剪发射队列，0x733 对应七个活动位置。
    parameter [11:0] ACTIVE_QUEUE_MASK=12'h733
)(
    input clk, reset,
    // imem_request_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output imem_request_valid, input imem_request_ready,
    // imem_request_address 保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
    output [31:0] imem_request_address,
    // imem_response_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    input imem_response_valid, output imem_response_ready,
    // imem_response_error 保存访问或译码错误标志，不能被正常数据值掩盖。
    input [63:0] imem_response_data, input [1:0] imem_response_error,
    // imem_response_page_fault 保存异常资格，须携带对应指令或请求身份交给后续处理。
    input [1:0] imem_response_page_fault,
    // dmem_request_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output dmem_request_valid, input dmem_request_ready,
    // dmem_request_address 保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
    output [31:0] dmem_request_address,
    output dmem_request_write,
    output dmem_request_is_atomic, output [4:0] dmem_request_atomic,
    // dmem_request_size 保存访问尺寸编码，决定对齐和字节选择的处理方式。
    output [1:0] dmem_request_size,
    // dmem_request_wdata 保存写数据 payload，只有对应写请求被接受后才产生副作用。
    output [31:0] dmem_request_wdata,
    // dmem_request_wstrb 保存逐字节写使能，未使能的字节保持原值。
    output [3:0] dmem_request_wstrb,
    // dmem_response_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    input dmem_response_valid, output dmem_response_ready,
    // dmem_response_rdata 保存读响应 payload，须在响应有效时才能使用。
    input [31:0] dmem_response_rdata, input dmem_response_error,
    // dmem_response_page_fault 保存异常资格，须携带对应指令或请求身份交给后续处理。
    input dmem_response_page_fault,
    // mmu_satp 保存页表根 ASID 及翻译模式快照，不能随新上下文改写在途请求。
    output [1:0] privilege_mode, output [31:0] mmu_satp,
    output mmu_sum,mmu_mxr,mmu_mprv, output [1:0] mmu_mpp,
    output mmu_sfence,
    // debug_architectural_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_mepc,debug_mcause,debug_mtval,debug_sepc,debug_scause,debug_stval,debug_architectural_pc,
    input irq_software, irq_timer, irq_external, irq_supervisor_external,
    input [63:0] mtime,
    input event_icache_refill,event_dcache_refill,event_dcache_writeback,
    output reg fence_i, fence_d,
    output debug_redirect,debug_trap,debug_branch_miss,debug_jump_miss,debug_dispatch_stall,debug_frontend_stall,
    // retire_valid 属于顺序退休，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 退休数表示真实架构提交，不能用执行完成数替代。
    output reg [1:0] retire_valid,
    // retire_pc0 属于顺序退休，保存指令地址，供退休记录及异常恢复定位。
    output reg [31:0] retire_pc0, retire_pc1,
    // retire_instruction0 属于顺序退休，保存原始指令编码，和该条指令的 PC 及身份同行保存。
    output reg [31:0] retire_instruction0, retire_instruction1,
    // retire_destination0 属于顺序退休，保存目的架构寄存器编号，必须和结果所有者同时核对。
    output reg [4:0] retire_destination0, retire_destination1,
    output reg [31:0] retire_value0, retire_value1,
    // debug_alloc_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output reg [1:0] debug_alloc_valid,debug_alloc_proposal_valid,
    output reg [3:0] debug_alloc_queue0,debug_alloc_queue1,debug_issue_queue0,debug_issue_queue1,
    // debug_alloc_tag0 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output reg [3:0] debug_alloc_tag0,
    // debug_alloc_sequence0 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_alloc_sequence0,
    // debug_alloc_pc0 保存指令地址，供退休记录及异常恢复定位。
    output reg [31:0] debug_alloc_pc0,
    // debug_alloc_tag1 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output reg [3:0] debug_alloc_tag1,
    // debug_alloc_sequence1 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_alloc_sequence1,
    // debug_alloc_pc1 保存指令地址，供退休记录及异常恢复定位。
    output reg [31:0] debug_alloc_pc1,
    // debug_issue_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output reg [1:0] debug_issue_valid,
    output reg [1:0] debug_issue_from_allocation,
    // debug_issue_tag0 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output reg [3:0] debug_issue_tag0 /* synthesis syn_maxfan = 32 */,
    // debug_issue_sequence0 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_issue_sequence0,
    // debug_issue_pc0 保存指令地址，供退休记录及异常恢复定位。
    output reg [31:0] debug_issue_pc0,
    // debug_issue_tag1 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output reg [3:0] debug_issue_tag1 /* synthesis syn_maxfan = 32 */,
    // debug_issue_sequence1 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_issue_sequence1,
    // debug_issue_pc1 保存指令地址，供退休记录及异常恢复定位。
    output reg [31:0] debug_issue_pc1,
    // debug_complete_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output reg [2:0] debug_complete_valid,
    // debug_complete_writes 保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    output reg [2:0] debug_complete_writes,debug_complete_broadcast,
    // debug_complete_tag0 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output reg [3:0] debug_complete_tag0,
    // debug_complete_sequence0 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_complete_sequence0,
    // debug_complete_pc0 保存指令地址，供退休记录及异常恢复定位。
    output reg [31:0] debug_complete_pc0,
    // debug_complete_tag1 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output reg [3:0] debug_complete_tag1,
    // debug_complete_sequence1 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_complete_sequence1,
    // debug_complete_pc1 保存指令地址，供退休记录及异常恢复定位。
    output reg [31:0] debug_complete_pc1,
    // debug_complete_tag2 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output reg [3:0] debug_complete_tag2,
    // debug_complete_sequence2 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_complete_sequence2,
    // debug_complete_pc2 保存指令地址，供退休记录及异常恢复定位。
    output reg [31:0] debug_complete_pc2,
    output reg [2:0] debug_complete_exception,
    // debug_retire_tag0 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output reg [3:0] debug_retire_tag0,
    // debug_retire_sequence0 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_retire_sequence0,
    // debug_retire_tag1 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output reg [3:0] debug_retire_tag1,
    // debug_retire_sequence1 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_retire_sequence1,
    // debug_recovery_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output reg debug_recovery_valid,
    // debug_recovery_first_killed_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output reg [63:0] debug_recovery_first_killed_sequence,
    // debug_rob_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    output [4:0] debug_rob_count,
    // debug_iq0_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    output reg [2:0] debug_iq0_count,debug_iq1_count,debug_complex_count,
    // debug_head_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output debug_lsu_active,debug_mdu_active,debug_quarantine_active,debug_head_valid,
    // debug_head_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_head_sequence,
    // debug_lsu_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_lsu_tag,
    // debug_lsu_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_lsu_sequence,
    // debug_lsu_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_lsu_pc,
    output debug_lsu_irrevocable,
    // debug_mdu_response_pending 保存尚未完成的工作标志，阻止新任务错误地越过当前生命周期。
    output debug_mdu_response_pending,debug_mdu_response_blocked,
    // debug_lsu_response_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_lsu_response_tag,
    // debug_lsu_response_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_lsu_response_sequence,
    // debug_lsu_response_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_lsu_response_pc,
    // debug_prepared_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output debug_lsu_reserved,debug_prepared_valid,debug_ex_memory_valid,
    // debug_prepared_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_prepared_tag,debug_ex_memory_tag,
    // debug_prepared_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_prepared_sequence,debug_ex_memory_sequence,
    // debug_prepared_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_prepared_pc,debug_ex_memory_pc,
    output [1:0] debug_memory_reservations,
    output [2:0] debug_memory_credit_limit,
    // debug_prepared_second_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output debug_prepared_second_valid,
    // debug_prepared_second_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_prepared_second_tag,
    // debug_prepared_second_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_prepared_second_sequence,
    // debug_prepared_second_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_prepared_second_pc,
    // debug_mul_request_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output debug_mul_request_valid,debug_mul_request_ready,
    // debug_mul_request_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_mul_request_tag,
    // debug_mul_request_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_mul_request_sequence,
    // debug_mul_request_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_mul_request_pc,debug_mul_request_left,debug_mul_request_right,
    // debug_mul_response_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output debug_mul_response_valid,debug_mul_response_ready,
    // debug_mul_response_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_mul_response_tag,
    // debug_mul_response_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_mul_response_sequence,
    // debug_mul_response_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_mul_response_pc,debug_mul_response_value,
    output [1:0] debug_mul_occupancy,
    // debug_mul_ex_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output debug_mul_ex_valid,debug_mul_ex_hold,
    // debug_mul_ex_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_mul_ex_tag,
    // debug_mul_ex_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_mul_ex_sequence,
    // debug_mul_ex_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_mul_ex_pc,
    // debug_legacy_request_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output debug_legacy_request_valid,debug_legacy_request_ready,
    // debug_legacy_request_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_legacy_request_tag,
    // debug_legacy_request_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_legacy_request_sequence,
    // debug_legacy_request_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_legacy_request_pc,
    // debug_legacy_response_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output debug_legacy_response_valid,debug_legacy_response_ready,
    // debug_legacy_response_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_legacy_response_tag,
    // debug_legacy_response_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_legacy_response_sequence,
    // debug_legacy_response_pc 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_legacy_response_pc,
    // debug_irq_pending 保存尚未完成的工作标志，阻止新任务错误地越过当前生命周期。
    output debug_irq_pending,
    output [1:0] debug_raw_retire_mask,
    // debug_ex_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output [1:0] debug_ex_valid,debug_ex_fault,
    // debug_ex_tag0 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    output [3:0] debug_ex_tag0,debug_ex_tag1,
    // debug_ex_sequence0 保存完整顺序身份，用来区分标签环绕前后的指令。
    output [63:0] debug_ex_sequence0,debug_ex_sequence1,
    // debug_ex_pc0 保存指令地址，供退休记录及异常恢复定位。
    output [31:0] debug_ex_pc0,debug_ex_pc1,
    // debug_second_prediction 保存该指令携带的预测结果，用于和实际后继地址对照。
    output [31:0] debug_second_next,debug_second_prediction
);
    // Single hart, M/S/U privileged state. All changes are precise retirement events.
    // current_privilege 当前架构特权级，只在精确 trap 或返回等边界改变。
    reg [1:0] current_privilege;
    reg [31:0] csr_svector,csr_sscratch,csr_sepc,csr_scause,csr_stval,csr_satp;
    reg [31:0] csr_medeleg,csr_mideleg,csr_mcounteren,csr_scounteren,csr_pending;
    localparam [31:0] STATUS_MASK=32'h007e19aa, SSTATUS_MASK=32'h000c0122;
    // debug_mepc 连接到 csr_exception_pc，两者在此路径上保持字段对应。
    assign debug_mepc=csr_exception_pc;assign debug_mcause=csr_cause;assign debug_mtval=csr_trap_value;
    // debug_sepc 连接到 csr_sepc，两者在此路径上保持字段对应。
    assign debug_sepc=csr_sepc;assign debug_scause=csr_scause;assign debug_stval=csr_stval;assign debug_architectural_pc=architectural_pc;
    // privilege_mode 连接到 current_privilege，两者在此路径上保持字段对应。
    assign privilege_mode=current_privilege;
    // mmu_satp 连接到 csr_satp，两者在此路径上保持字段对应。
    assign mmu_satp=csr_satp;
    // mmu_sum 读取 csr_status[18] 所选位域；位索引按声明中的高低位顺序解释。
    assign mmu_sum=csr_status[18]; assign mmu_mxr=csr_status[19];
    // mmu_mprv 读取 csr_status[17] 所选位域；位索引按声明中的高低位顺序解释。
    assign mmu_mprv=csr_status[17]; assign mmu_mpp=csr_status[12:11];
    // mmu_sfence 的资格组合为 retire0 && ((read_rob_instruction(rob_head)&32'hfe007fff)==32'h12000073)。
    assign mmu_sfence=retire0 && ((read_rob_instruction(rob_head)&32'hfe007fff)==32'h12000073);
    // data_response_fault 属于D-cache 状态，保存异常资格，须携带对应指令或请求身份交给后续处理。
    // 脏行替换必须先保留待写回数据，不能被新回填覆盖。
    // data_response_fault 的资格组合为 dmem_response_error || dmem_response_page_fault。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    wire data_response_fault=dmem_response_error || dmem_response_page_fault;
    reg [31:0] csr_status, csr_interrupt_enable, csr_vector, csr_scratch;
    // csr_exception_pc 属于特权 CSR，保存指令地址，供退休记录及异常恢复定位。
    // 读写资格由 CSR 编号 权限和提交路径共同限定。
    reg [31:0] csr_exception_pc, csr_cause, csr_trap_value;
    reg [2:0] event_selector [0:3];
    reg [63:0] event_counter [0:3];
    reg [63:0] cycle_counter, instruction_counter;
    // Each segment adds a constant in parallel. Carries depend on old
    // registered lower bits, so a late event/retirement need not enter a
    //64-bit ripple chain. Later original CSR assignments keep their priority.
    wire [3:0] counter_event_step;
    genvar counter_event_row;
    generate for(counter_event_row=0;counter_event_row<4;counter_event_row=counter_event_row+1)begin:counter_events
        assign counter_event_step[counter_event_row]=
            (event_selector[counter_event_row]==1&&event_icache_refill)||
            (event_selector[counter_event_row]==2&&event_dcache_refill)||
            (event_selector[counter_event_row]==3&&event_dcache_writeback)||
            (event_selector[counter_event_row]==4&&debug_branch_miss);
    end endgenerate
    // interrupt_bits 外部中断源与软件挂起位合并后的候选集合，还未完成权限使能筛选。
    // interrupt_bits 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {20'b0,irq_external,1'b0,irq_supervisor_external,1'b0,irq_timer,3'b0,irq_software,3'b0}|csr_pending；复制大括号表示重复位域，不是独立队列元素。
    wire [31:0] interrupt_bits={20'b0,irq_external,1'b0,irq_supervisor_external,1'b0,irq_timer,3'b0,irq_software,3'b0}|csr_pending;
    // enabled_interrupts 经过 mie 位筛选的挂起集合，后续还须按委托与特权状态决定可接收性。
    // enabled_interrupts 对 interrupt_bits & csr_interrupt_enable 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [31:0] enabled_interrupts=interrupt_bits & csr_interrupt_enable;
    // eligible_machine 未委托且当前 M 级条件允许接收的中断集合。
    // eligible_machine 的资格组合为 enabled_interrupts & ~csr_mideleg & {32{current_privilege<3 || csr_status[3]}}。
    wire [31:0] eligible_machine=enabled_interrupts & ~csr_mideleg & {32{current_privilege<3 || csr_status[3]}};
    // eligible_supervisor 委托给 S 级且当前特权与 SIE 条件允许接收的中断集合。
    // eligible_supervisor 的资格组合为 enabled_interrupts & csr_mideleg & {32{current_privilege<1 || (current_privilege==1 && csr_status[1])}}。
    wire [31:0] eligible_supervisor=enabled_interrupts & csr_mideleg & {32{current_privilege<1 || (current_privilege==1 && csr_status[1])}};
    // eligible_interrupts 机器级与监督级可接收集合的合并，归约后给出中断待处理资格。
    // eligible_interrupts 对 eligible_machine|eligible_supervisor 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [31:0] eligible_interrupts=eligible_machine|eligible_supervisor;
    // interrupt_pending 保存尚未完成的工作标志，阻止新任务错误地越过当前生命周期。
    // interrupt_pending 对 |eligible_interrupts 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire interrupt_pending=|eligible_interrupts;
    // interrupt_cause 保存异常原因编码，用于决定精确异常入口及 CSR 记录。
    wire [31:0] interrupt_cause=eligible_interrupts[11]?32'h8000000b:
        eligible_interrupts[3]?32'h80000003:eligible_interrupts[7]?32'h80000007:
        eligible_interrupts[9]?32'h80000009:eligible_interrupts[1]?32'h80000001:32'h80000005;
    // 依据异常或中断原因选择 M 或 S 委托目标，并按向量模式计算中断入口。
    function [31:0] trap_target;
        // cause 保存异常原因编码，用于决定精确异常入口及 CSR 记录。
        input [31:0] cause;
        reg delegated; reg [31:0] vector;
        begin
            // delegated 的资格组合为 current_privilege!=3 && (cause[31]?csr_mideleg[cause[4:0]]:csr_medeleg[cause[4:0]])。
            delegated=current_privilege!=3 && (cause[31]?csr_mideleg[cause[4:0]]:csr_medeleg[cause[4:0]]);
            // vector 按 delegated 进行来源选择。
            // 真分支取 csr_svector；其余情况取 csr_vector。
            vector=delegated?csr_svector:csr_vector;
            // trap_target 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
            // 拼接源为 {vector[31:2],2'b0}+((cause[31]&&vector[1:0]==1)?{25'b0,cause[4:0],2'b0}:32'b0)；复制大括号表示重复位域，不是独立队列元素。
            trap_target={vector[31:2],2'b0}+((cause[31]&&vector[1:0]==1)?{25'b0,cause[4:0],2'b0}:32'b0);
        end
    endfunction
    // architectural_pc 已提交边界的架构 PC，不能用当前前端投机 PC 替代。
    reg [31:0] architectural_pc;
    // 把 CSR 编号映射为当前架构寄存器或计数器的读值；访问合法性另行检查。
    function [31:0] read_csr;
        input [11:0] number;
        begin
            case(number)
                12'h300:read_csr=csr_status;
                12'h301:read_csr=32'h40141101; // RV32 I/M/A/S/U; integrated atomic/MMU smoke verified
                12'h304:read_csr=csr_interrupt_enable;
                12'h305:read_csr=csr_vector;
                12'h306:read_csr=csr_mcounteren;
                12'h310:read_csr=0;
                12'h302:read_csr=csr_medeleg;
                12'h303:read_csr=csr_mideleg;
                12'h100:read_csr=csr_status&SSTATUS_MASK;
                12'h104:read_csr=csr_interrupt_enable&csr_mideleg;
                12'h105:read_csr=csr_svector;
                12'h106:read_csr=csr_scounteren;
                12'h140:read_csr=csr_sscratch;
                12'h141:read_csr=csr_sepc;
                12'h142:read_csr=csr_scause;
                12'h143:read_csr=csr_stval;
                12'h144:read_csr=interrupt_bits&csr_mideleg;
                12'h180:read_csr=csr_satp;
                12'hc00:read_csr=cycle_counter[31:0];
                12'hc80:read_csr=cycle_counter[63:32];
                12'hc02:read_csr=instruction_counter[31:0];
                12'hc82:read_csr=instruction_counter[63:32];
                12'h340:read_csr=csr_scratch;
                12'h341:read_csr=csr_exception_pc;
                12'h342:read_csr=csr_cause;
                12'h343:read_csr=csr_trap_value;
                12'h344:read_csr=interrupt_bits;
                12'hb00:read_csr=cycle_counter[31:0];
                12'hb80:read_csr=cycle_counter[63:32];
                12'hb02:read_csr=instruction_counter[31:0];
                12'hb82:read_csr=instruction_counter[63:32];
                12'hc01:read_csr=mtime[31:0];
                12'hc81:read_csr=mtime[63:32];
                12'hf11:read_csr=0;
                12'hf12:read_csr=5;
                12'hf13:read_csr=0;
                12'hf14:read_csr=0;
                default:begin
                    if(number>=12'hb03 && number<=12'hb06) read_csr=event_counter[number[1:0]-2'd3][31:0];
                    else if(number>=12'hb83 && number<=12'hb86) read_csr=event_counter[number[1:0]-2'd3][63:32];
                    else if(number>=12'h323 && number<=12'h326) read_csr={29'b0,event_selector[number[1:0]-2'd3]};
                    else read_csr=0;
                end
            endcase
        end
    endfunction
    // 识别实现过的 CSR 编号，不能把默认读零解释为所有 CSR 都存在。
    function csr_exists;
        input [11:0] number;
        begin
            case(number)
                12'h100,12'h104,12'h105,12'h106,12'h140,12'h141,12'h142,12'h143,12'h144,12'h180,
                12'h302,12'h303,12'h300,12'h301,12'h304,12'h305,12'h306,12'h310,
                12'h340,12'h341,12'h342,12'h343,12'h344,
                12'hb00,12'hb80,12'hb02,12'hb82,
                12'hc00,12'hc80,12'hc02,12'hc82,12'hc01,12'hc81,
                12'hf11,12'hf12,12'hf13,12'hf14,12'hf15:csr_exists=1;
                default:csr_exists=(number>=12'hb03 && number<=12'hb1f)||(number>=12'hb83 && number<=12'hb9f)||(number>=12'h323 && number<=12'h33f);
            endcase
        end
    endfunction

    localparam ROB_SIZE=16, QUEUE_SIZE=12;
    // ORDERED_SCHEDULER 的资格组合为 BANKED_ISSUE&&ENABLE_STEALING&&!ENABLE_SAME_CYCLE_REUSE。
    localparam ORDERED_SCHEDULER=BANKED_ISSUE&&ENABLE_STEALING&&!ENABLE_SAME_CYCLE_REUSE;
    // One physical RAM per retirement lane, with a one-bit last-writer map.
    // A validity bitmap implements architectural reset without resetting RAM.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] register_lane0[0:31],register_lane1[0:31];
    // register_valid 架构寄存器存储的有效信息，与重命名映射的在途所有者信息不同。
    reg register_valid[0:31],register_owner[0:31];
    // 读取架构寄存器；x0 的恒零规则不能被内部存储内容覆盖。
    function [31:0] read_register;
        input [4:0] number;
        begin
            if(number==0||!register_valid[number])read_register=0;
            else read_register=register_owner[number]?register_lane1[number]:register_lane0[number];
        end
    endfunction
    // map_valid 架构寄存器是否映射到仍在途的 ROB 生产者。
    reg map_valid[0:31]; reg [3:0] map_tag[0:31];
    // rob_valid ROB 各行的存活资格；恢复取消的年轻行不能继续提供有效结果。
    reg rob_valid[0:15],rob_done[0:15],rob_fault[0:15],rob_writes[0:15];
    // rob_fetch_page_fault 属于ROB 行，保存异常资格，须携带对应指令或请求身份交给后续处理。
    // 本行 payload 只有在对应 ROB 资格有效时才属于当前指令。
    reg rob_fetch_page_fault[0:15];
    // rob_memory 属于ROB 行，保存访存类别资格，供访存顺序与执行资源选择使用。
    reg rob_memory[0:15],rob_store[0:15],rob_complex[0:15],rob_serial[0:15],rob_fetch_error[0:15];
    // rob_arithmetic 属于ROB 行，保存复杂算术类别或结果，和普通整数路径分别仲裁。
    reg rob_arithmetic[0:15],rob_decode_error[0:15];
    // rob_control 属于ROB 行，保存控制流类别或控制位，供目标选择和分支结果处理使用。
    reg rob_control[0:15],rob_conditional[0:15],rob_taken[0:15];
    reg rob_prediction_miss[0:15];
    reg rob_history_sequential[0:15];
    (* syn_ramstyle="distributed_ram" *) reg [HISTORY_BITS+1:0] rob_context_even[0:7],rob_context_odd[0:7];
    (* syn_ramstyle="distributed_ram" *) reg [HISTORY_BITS-1:0] rob_recovery_even[0:7],rob_recovery_odd[0:7];
    // 读取该 ROB 所有者携带的恢复历史，避免使用之后改变的全局投机状态。
    function [HISTORY_BITS-1:0] read_recovery_context;
        // tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
        input [3:0] tag;
        begin read_recovery_context=tag[0]?rob_recovery_odd[tag[3:1]]:rob_recovery_even[tag[3:1]];end
    endfunction
    // 读取指令分配时保存的预测上下文，供对应退休分支训练使用。
    function [HISTORY_BITS+1:0] read_prediction_context;
        input [3:0] tag;
        begin read_prediction_context=tag[0]?rob_context_odd[tag[3:1]]:rob_context_even[tag[3:1]];end
    endfunction
    // Consecutive ROB allocation guarantees at most one write to each parity
    // bank per edge, including a wrapped two-wide bundle.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] rob_instruction_even[0:7],rob_instruction_odd[0:7];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] rob_prediction_even[0:7],rob_prediction_odd[0:7];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] next_lane0[0:15],next_lane1[0:15];
    // 取得指定 ROB 行的指令地址，供异常与退休元数据路径使用。
    function [31:0] read_rob_pc;
        input [3:0] tag;
        reg [3:0] previous;
        begin
            // A live non-head instruction follows its predecessor's predicted
            // PC. The architectural PC anchors the current head, whose old
            // predecessor slot may already have been reused after retirement.
            previous=tag-4'd1;
            // read_rob_pc 按 tag==rob_head 选择候选来源；各分支结果仍属于当前组合路径。
            // read_rob_pc 按 tag==rob_head 进行来源选择。
            // 真分支取 architectural_pc；其余情况取 read_rob_prediction(previous)。
            read_rob_pc=tag==rob_head?architectural_pc:read_rob_prediction(previous);
        end
    endfunction
    // 取得指定 ROB 行保存的原始指令，不能从当前取指总线替代。
    function [31:0] read_rob_instruction;
        input [3:0] tag;
        begin read_rob_instruction=tag[0]?rob_instruction_odd[tag[3:1]]:rob_instruction_even[tag[3:1]];end
    endfunction
    // 读取指令进入 ROB 时的预测目标，用于和实际结果比较。
    function [31:0] read_rob_prediction;
        input [3:0] tag;
        begin read_rob_prediction=tag[0]?rob_prediction_odd[tag[3:1]]:rob_prediction_even[tag[3:1]];end
    endfunction
    // 读取该指令已经记录的后继 PC，恢复与退休必须对应相同所有者。
    function [31:0] read_rob_next;
        input [3:0] tag;
        begin
            if(rob_control[tag]||rob_system[tag]==2||rob_system[tag]==7)
                // read_rob_next 按 result_owner[tag]==0 进行来源选择。
                // 真分支取 next_lane0[tag]；其余情况取 next_lane1[tag]。
                read_rob_next=result_owner[tag]==0?next_lane0[tag]:next_lane1[tag];
            else read_rob_next=read_rob_pc(tag)+32'd4;
        end
    endfunction
    // Completion lane banks each have exactly one write port. Registered
    // owner bits select the last completion; done guards uninitialized rows.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] result_lane0[0:15],result_lane1[0:15],result_lane2[0:15];
    // result_owner 结果存储的归属选择，避免完成端口和 RAM 读取之间发生身份错配。
    reg [1:0] result_owner[0:15];
    // rob_cause 属于ROB 行，保存异常原因编码，用于决定精确异常入口及 CSR 记录。
    reg [31:0] rob_cause[0:15];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] tval_lane0[0:15],tval_lane1[0:15],tval_lane2[0:15];
    // 读取该行异常相关的地址或指令值，以便精确写入 trap value。
    function [31:0] read_rob_tval;
        input [3:0] tag;
        begin
            case(result_owner[tag])
                0:read_rob_tval=tval_lane0[tag];
                1:read_rob_tval=tval_lane1[tag];
                default:read_rob_tval=tval_lane2[tag];
            endcase
        end
    endfunction
    // CSR execution is serialized with an otherwise empty ROB, so only one
    // pending CSR payload can exist. Per-entry write eligibility is retained.
    reg [31:0] serial_csr_value;
    reg [11:0] serial_csr_number;
    // 根据结果所有权选择完成数据，读取动作本身不使指令获得提交资格。
    function [31:0] read_result;
        input [3:0] tag;
        begin
            case(result_owner[tag])
                0:read_result=result_lane0[tag];
                1:read_result=result_lane1[tag];
                default:read_result=result_lane2[tag];
            endcase
        end
    endfunction
    // rob_destination 属于ROB 行，保存目的架构寄存器编号，必须和结果所有者同时核对。
    reg [4:0] rob_destination[0:15];
    reg [2:0] rob_system[0:15]; reg rob_csr_write[0:15];
    // rob_sequence 属于ROB 行，保存完整顺序身份，用来区分标签环绕前后的指令。
    reg [63:0] rob_sequence[0:15];
    // rob_head 最早未退休指令的 ROB 位置，是精确异常与程序顺序的基准。
    // rob_head 按 32 */,rob_tail 计算，运算位宽与有无符号以原声明和显式扩展为准。
    reg [3:0] rob_head /* synthesis syn_maxfan = 32 */,rob_tail; reg [4:0] rob_count; reg serial_pending;
    // next_sequence 下一条分配指令的完整序号，辅助区分有限 ROB 标签的多次复用。
    reg [63:0] next_sequence;
    // head1 保存队头位置，界定本周期最早尚未完成相应生命周期的条目。
    // head1 按 rob_head+4'd1,tail1=rob_tail+4'd1 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [3:0] head1=rob_head+4'd1,tail1=rob_tail+4'd1;

    // q_valid 物理发射槽位的占有资格，实际存在的槽位还受 ACTIVE_QUEUE_MASK 限定。
    reg q_valid[0:11],q_left_ready[0:11],q_right_ready[0:11];
    // q_writes 属于物理发射队列，保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    // 槽位编号保持固定；所有者 依赖就绪和有效位须配套解释。
    reg q_writes[0:11],q_error[0:11],q_serial[0:11],q_memory[0:11],q_arithmetic[0:11],q_multiply[0:11];
    // TOPT2: instruction-only wake permission is captured with queue ownership.
    // Lane 0 checks CSR access faults; the original lane 1 predicate does not.
    // q_static_wakeup 提前译码形成的静态唤醒元数据，仍须结合运行时所有者和异常资格。
    reg [1:0] q_static_wakeup[0:11];
    // Registered store class of the queued owner; selects the store-only
    // ordering filter for a younger load under LOAD_BYPASS.
    // q_store 属于物理发射队列，保存存储类别资格；最终写副作用仍受顺序及握手限定。
    reg q_store[0:11];
    // EXMETA queue variant: five immutable bits per existing queue entry.
    // [0] ordinary integer, [1] misaligned JAL immediate, [2] JALR,
    // [3] PC invalid, [4] CSR access fault. Reuse q_error separately.
    // Payload is initialized with the matching allocation and owned by q_valid.
    // q_control_meta 随队列项保存的不可变控制元数据，减少晚调度路径上的重复译码。
    reg [4:0] q_control_meta[0:11];
    // TOPT5: queue-only compact control. EX retains the original 32-bit
    // one-hot-or-zero family plus modifiers; no execution latency changes.
    // [4:0] family code: 0=none, 1..21 select original control[0..20].
    // [15:5] preserves every original modifier control[31:21], including
    // irrelevant modifier bits on illegal/zero-result instruction encodings.
    // q_alu_control 分配阶段打包的 ALU 选择，和同一队列项的 PC 及操作数一起使用。
    reg [15:0] q_alu_control[0:11];
    // 把已译码 ALU 控制压缩为队列 payload，避免晚发射选择后重新走完整译码。
    function [15:0] pack_queue_alu_control;
        input [31:0] decoded;
        reg [4:0] family_code;
        integer family;
        begin
            family_code=0;
            for(family=0;family<21;family=family+1)
                // family_code 按 family_code|({5{decoded[family]}}&(family[4:0]+5'd1)) 计算，运算位宽与有无符号以原声明和显式扩展为准。
                family_code=family_code|({5{decoded[family]}}&(family[4:0]+5'd1));
            // pack_queue_alu_control 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
            // 拼接源为 {decoded[31:21],family_code}；复制大括号表示重复位域，不是独立队列元素。
            pack_queue_alu_control={decoded[31:21],family_code};
        end
    endfunction
    // 从队列保存的控制字段恢复 ALU 选择，必须与打包位域完全对应。
    function [31:0] unpack_queue_alu_control;
        // packed_control 保存控制流类别或控制位，供目标选择和分支结果处理使用。
        input [15:0] packed_control;
        integer family;
        begin
            // unpack_queue_alu_control 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
            // 拼接源为 {packed_control[15:5],21'b0}；复制大括号表示重复位域，不是独立队列元素。
            unpack_queue_alu_control={packed_control[15:5],21'b0};
            for(family=0;family<21;family=family+1)
                // unpack_queue_alu_control[family] 由比较式 (packed_control[4:0]==(family[4:0]+5'd1)) 产生；该结果是条件判断，不是被比较的数据。
                unpack_queue_alu_control[family]=(packed_control[4:0]==(family[4:0]+5'd1));
        end
    endfunction
    // Private allocation payload, owned by q_valid and captured with q_tag.
    // Each active row carries 64 bits; q_valid remains its only owner state.
    // q_pc 属于物理发射队列，保存指令地址，供退休记录及异常恢复定位。
    reg [31:0] q_pc[0:11],q_instruction[0:11];
    reg legacy_issue_credit;
    // q_tag 属于物理发射队列，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    reg [3:0] q_tag[0:11],q_left_tag[0:11],q_right_tag[0:11];
    // q_left 属于物理发射队列，保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [31:0] q_left[0:11],q_right[0:11];
    reg steer;
    // ex_valid0 属于执行边界，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 执行结果仍需经过完成及顺序提交检查，不能直接当作架构状态。
    reg ex_valid0,ex_valid1;
    // Immutable effective register-write identity, captured with each EX owner.
    // ex_writes0 属于执行边界，保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    reg ex_writes0,ex_writes1;
    // ex_tag0 属于执行边界，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    reg [3:0] ex_tag0,ex_tag1;
    // ex_sequence0 属于执行边界，保存完整顺序身份，用来区分标签环绕前后的指令。
    reg [63:0] ex_sequence0,ex_sequence1;
    // ex_instruction0 属于执行边界，保存原始指令编码，和该条指令的 PC 及身份同行保存。
    reg [31:0] ex_instruction0,ex_instruction1,ex_pc0,ex_pc1,ex_left0,ex_left1,ex_right0,ex_right1;
    reg [31:0] ex_mul_left_local,ex_mul_right_local;

    // fetch_instruction0 属于取指与分配边界，保存原始指令编码，和该条指令的 PC 及身份同行保存。
    // 所带预测和错误信息必须跟随相同指令，而不是后来的取指请求。
    wire [31:0] fetch_instruction0,fetch_instruction1,fetch_pc0,fetch_pc1,fetch_prediction0,fetch_prediction1;
    // fetch_error0 属于取指与分配边界，保存访问或译码错误标志，不能被正常数据值掩盖。
    wire fetch_error0,fetch_error1,fetch_page_fault0,fetch_page_fault1; wire [3:0] fetch_count;
    // fetch_serial0 属于取指与分配边界，保存串行操作资格，用于阻止不允许重叠的架构操作。
    wire fetch_serial0,fetch_serial1,fetch_complex0,fetch_complex1;
    wire fetch_pc_dispatch_ok0,fetch_pc_dispatch_ok1;
    // predictor_training_ready 属于预测表接口，保存接收或操作数就绪资格，须结合对应的有效位使用。
    // 命中 payload 要和有效位及对应 PC 一起判断。
    wire predictor_training_ready;
    // recovery_history 属于恢复边界，保存分支历史信息，投机路径与提交路径必须保持各自归属。
    // 年轻指令被取消后，在途响应仍可能返回，但不能恢复旧的提交资格。
    wire [HISTORY_BITS-1:0] recovery_history;
    wire [11:0] allocation_occupied;
    wire [4:0] d_rs10,d_rs20,d_rd0,d_rs11,d_rs21,d_rd1;
    wire d_use10,d_use20,d_write0,d_mem0,d_store0,d_mdu0,d_csr0,d_bad0;
    wire d_use11,d_use21,d_write1,d_mem1,d_store1,d_mdu1,d_csr1,d_bad1;
    // predictor_committed_history 属于预测表接口，保存分支历史信息，投机路径与提交路径必须保持各自归属。
    wire [HISTORY_BITS-1:0] predictor_committed_history,fetch_recovery_context0,fetch_recovery_context1;
    wire fetch_prediction_sequential0,fetch_prediction_sequential1;
    // fetch_prediction_context0 属于取指与分配边界，保存随指令保存的上下文，不能用之后变化的全局状态替代。
    wire [HISTORY_BITS+1:0] fetch_prediction_context0,fetch_prediction_context1;
    // allocation_offer_count 属于新分配候选，保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    // 仅在最终接收时获得持久所有者，提议不能提前占用架构状态。
    reg [1:0] allocation_offer_count;
    // Recovery cancels acceptance, not the pre-edge free-slot proposal.
    // allocate_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    // allocate_count 按 recovery 进行来源选择。
    // 真分支取 2'b0；其余情况取 allocation_offer_count。
    wire [1:0] allocate_count=recovery?2'b0:allocation_offer_count;
    reg recovery,trap_enter,return_from_trap,maintain_i,maintain_d;
    // A new live redirect request must observe post-retirement translation
    // context. Held old offers still drain, marked killed by the frontend.
    // satp_context_commit 的资格组合为 retire0&&rob_csr_write[rob_head]&&serial_csr_number==12'h180。
    wire satp_context_commit=retire0&&rob_csr_write[rob_head]&&serial_csr_number==12'h180;
    // recovery_address 属于恢复边界，保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
    reg [31:0] recovery_address,trap_pc,trap_cause,trap_value;
    reg [63:0] recovery_first;
    reg retire0,retire1;
    reg registered_pair_retire;
    // The successor's PC is the current head's immutable prediction. Cache
    // it across the existing ROB ownership edge, before the PHT lookup;
    // training keeps its original edge and ordered dual-port semantics.
    // training_successor_pc 随训练边界保存的真实后继地址，避免用后来的 ROB 读取结果替代。
    reg [31:0] training_successor_pc;
    // training_head2 属于预测训练，保存队头位置，界定本周期最早尚未完成相应生命周期的条目。
    // 训练事件来自已经退休的真实控制流，不能混入被取消的投机结果。
    // training_head2 按 rob_head+4'd2 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [3:0] training_head2=rob_head+4'd2;
    // 为训练读口计算含当前旁路的候选元数据，训练有效性由外层退休条件限定。
    function [31:0] training_prediction_proposal;
        input [3:0] tag;
        begin
            if(allocation_offer_count!=0&&rob_tail==tag)training_prediction_proposal=fetch_prediction0;
            else if(allocation_offer_count==2&&tail1==tag)training_prediction_proposal=fetch_prediction1;
            else training_prediction_proposal=read_rob_prediction(tag);
        end
    endfunction
    wire [31:0] training_proposal0=training_prediction_proposal(rob_head);
    wire [31:0] training_proposal1=training_prediction_proposal(head1);
    wire [31:0] training_proposal2=training_prediction_proposal(training_head2);
    always @(posedge clk)begin
        // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
        if(reset)training_successor_pc<=RESET_VECTOR+32'd4;
        else training_successor_pc<=retire0?(retire1?training_proposal2:training_proposal1):training_proposal0;
    end
`ifdef VERILATOR
    reg [4:0] training_pc_seen;
    always @(posedge clk)begin
        if(reset)training_pc_seen<=0;
        else begin
            if(rob_count!=0&&training_successor_pc!=read_rob_prediction(rob_head))
                $fatal(1,"R37 registered training PC differs from original current head prediction");
            if(!training_pc_seen[0]&&rob_count==0&&allocate_count!=0)begin training_pc_seen[0]<=1;$display("COVERAGE R37 training_pc_empty_allocate");end
            if(!training_pc_seen[1]&&retire0&&allocate_count!=0)begin training_pc_seen[1]<=1;$display("COVERAGE R37 training_pc_pop_allocate");end
            if(!training_pc_seen[2]&&retire0&&retire1)begin training_pc_seen[2]<=1;$display("COVERAGE R37 training_pc_retire_pair");end
            if(!training_pc_seen[3]&&retire0&&(retire1?rob_head>=14:rob_head==15))begin training_pc_seen[3]<=1;$display("COVERAGE R37 training_pc_wrap");end
            // 恢复或冲刷条件 if(!training_pc_seen[4]&&recovery) 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(!training_pc_seen[4]&&recovery)begin training_pc_seen[4]<=1;$display("COVERAGE R37 training_pc_recovery");end
        end
    end
`endif
    // Existing ROB completion/ownership boundary, before recovery selects
    // the next PC. Parallel raw proposals and completion/allocation bypasses
    // keep the late current response out of result-owner -> RAM selection.
    // These are private payloads: live ROB ownership qualifies every use.
    // retirement_next0 提前保存在退休边界的第一后继 PC，使用前仍由存活 ROB 所有者限定。
    reg [31:0] retirement_next0,retirement_next1;
    // retirement_head3 属于退休边界，保存队头位置，界定本周期最早尚未完成相应生命周期的条目。
    // 只有退休有效的指令能更新架构寄存器和精确异常状态。
    // retirement_head3 按 rob_head+4'd3 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [3:0] retirement_head3=rob_head+4'd3;
    // 优先选择本拍分配或控制执行旁路，否则读取 ROB 已存储的后继地址。
    function [31:0] retirement_next_proposal;
        input [3:0] tag;
        begin
            if(allocation_offer_count!=0&&rob_tail==tag)retirement_next_proposal=fetch_pc0+32'd4;
            else if(allocation_offer_count==2&&tail1==tag)retirement_next_proposal=fetch_pc1+32'd4;
            else if(payload_integer1&&e_control1&&ex_tag1==tag)retirement_next_proposal=e_next1;
            else if(payload0&&(e_control0||(e_system0==2||e_system0==7))&&ex_tag0==tag)
                // retirement_next_proposal 按 e_system0==2 进行来源选择。
                // 真分支取 csr_exception_pc；其余情况取 (e_system0==7?csr_sepc:e_next0)。
                retirement_next_proposal=e_system0==2?csr_exception_pc:(e_system0==7?csr_sepc:e_next0);
            else retirement_next_proposal=read_rob_next(tag);
        end
    endfunction
    wire [31:0] retirement_proposal0=retirement_next_proposal(rob_head);
    wire [31:0] retirement_proposal1=retirement_next_proposal(head1);
    wire [31:0] retirement_proposal2=retirement_next_proposal(training_head2);
    wire [31:0] retirement_proposal3=retirement_next_proposal(retirement_head3);
    always @(posedge clk)begin
        // retirement_next0 按 retire0 选择候选来源；各分支结果仍属于当前寄存边界。
        // 本时钟边界的 retirement_next0 按 retire0 进行来源选择。
        // 真分支取 (retire1?retirement_proposal2:retirement_proposal1)；其余情况取 retirement_proposal0。
        retirement_next0<=retire0?(retire1?retirement_proposal2:retirement_proposal1):retirement_proposal0;
        // retirement_next1 按 retire0 选择候选来源；各分支结果仍属于当前寄存边界。
        // 本时钟边界的 retirement_next1 按 retire0 进行来源选择。
        // 真分支取 (retire1?retirement_proposal3:retirement_proposal2)；其余情况取 retirement_proposal1。
        retirement_next1<=retire0?(retire1?retirement_proposal3:retirement_proposal2):retirement_proposal1;
    end
`ifdef VERILATOR
    reg [4:0] retirement_next_seen;
    always @(posedge clk)begin
        if(reset)retirement_next_seen<=0;
        else begin
            if(rob_count>0&&retirement_next0!=read_rob_next(rob_head))
                $fatal(1,"R38 cached first retirement target differs from original raw value");
            if(rob_count>1&&retirement_next1!=read_rob_next(head1))
                $fatal(1,"R38 cached second retirement target differs from original raw value");
            if(!retirement_next_seen[0]&&payload0&&e_control0&&(ex_tag0==rob_head||ex_tag0==head1))begin retirement_next_seen[0]<=1;$display("COVERAGE R38 retirement_next_control0_forward");end
            if(!retirement_next_seen[1]&&payload_integer1&&e_control1&&(ex_tag1==rob_head||ex_tag1==head1))begin retirement_next_seen[1]<=1;$display("COVERAGE R38 retirement_next_control1_forward");end
            if(!retirement_next_seen[2]&&retire0&&retire1)begin retirement_next_seen[2]<=1;$display("COVERAGE R38 retirement_next_pair_shift");end
            if(!retirement_next_seen[3]&&retire0&&allocate_count!=0)begin retirement_next_seen[3]<=1;$display("COVERAGE R38 retirement_next_pop_allocate");end
            if(!retirement_next_seen[4]&&payload0&&e_system0==2)begin retirement_next_seen[4]<=1;$display("COVERAGE R38 retirement_next_mret_forward");end
        end
    end
`endif
    // A current ordinary integer has no control-training payload. Qualify
    // training with existing registered completion/retirement facts so its
    // full illegal-encoding decode cannot enter the predictor write enable.
`ifdef VERILATOR
    reg [HISTORY_BITS+1:0] prediction_context_reference[0:15];
    integer context_row;
    always @(posedge clk)if(!reset)begin
        for(context_row=0;context_row<16;context_row=context_row+1)
            if(rob_valid[context_row]&&read_prediction_context(context_row[3:0])!=prediction_context_reference[context_row])
                $fatal(1,"R45 live ROB prediction context differs from accepted allocation");
        if(allocate_count!=0)prediction_context_reference[rob_tail]<=fetch_prediction_context0;
        if(allocate_count==2)prediction_context_reference[tail1]<=fetch_prediction_context1;
    end
`endif
`ifdef VERILATOR
    reg [HISTORY_BITS-1:0] recovery_context_reference[0:15];
    integer recovery_context_row;
    always @(posedge clk)if(!reset)begin
        for(recovery_context_row=0;recovery_context_row<16;recovery_context_row=recovery_context_row+1)
            if(rob_valid[recovery_context_row]&&read_recovery_context(recovery_context_row[3:0])!=recovery_context_reference[recovery_context_row])
                $fatal(1,"R49 live ROB prediction context differs from accepted allocation");
        if(allocate_count!=0)recovery_context_reference[rob_tail]<=fetch_recovery_context0;
        if(allocate_count==2)recovery_context_reference[tail1]<=fetch_recovery_context1;
    end
`endif
`ifdef VERILATOR
    // r48_retired_history 保存分支历史信息，投机路径与提交路径必须保持各自归属。
    reg [HISTORY_BITS-1:0] r48_retired_history;
    reg r48_pressure_seen;
    // r48_history0 保存分支历史信息，投机路径与提交路径必须保持各自归属。
    // r48_history0 按 (retire0&&rob_conditional[rob_head]) 进行来源选择。
    // 真分支取 {r48_retired_history[HISTORY_BITS-2:0],(read_rob_next(rob_head)!=read_rob_pc(rob_head)+32'd4)}；其余情况取 r48_retired_history。
    wire [HISTORY_BITS-1:0] r48_history0=(retire0&&rob_conditional[rob_head])?
        {r48_retired_history[HISTORY_BITS-2:0],(read_rob_next(rob_head)!=read_rob_pc(rob_head)+32'd4)}:r48_retired_history;
    always @(posedge clk)begin
        if(reset)begin r48_retired_history<=0;r48_pressure_seen<=0;end
        else begin
            if(frontend.direction_predictor.committed_history!=r48_retired_history)
                $fatal(1,"R48 GHR differs from independent actual-retirement history");
            // r48_retired_history 按 (retire1&&rob_conditional[head1]) 选择候选来源；各分支结果仍属于当前寄存边界。
            // 本时钟边界的 r48_retired_history 的资格组合为 (retire1&&rob_conditional[head1])?。
            r48_retired_history<=(retire1&&rob_conditional[head1])?
                {r48_history0[HISTORY_BITS-2:0],(read_rob_next(head1)!=read_rob_pc(head1)+32'd4)}:r48_history0;
            if(rob_count!=0&&rob_done[rob_head]&&rob_conditional[rob_head]&&!predictor_training_ready&&!r48_pressure_seen)begin
                r48_pressure_seen<=1;$display("COVERAGE R48 training_queue_backpressure");
            end
        end
    end
    always @(posedge clk)if(!reset)begin
        if((retire0&&rob_conditional[rob_head]&&!train0)||(retire1&&rob_conditional[head1]&&!train1))
            $fatal(1,"R48 retired conditional branch lost its training event");
        if((train0&&rob_conditional[rob_head]||train1&&rob_conditional[head1])&&!predictor_training_ready)
            $fatal(1,"R48 retired conditional branch without predictor queue credit");
    end
`endif
    // train0 的资格组合为 retire0&&rob_done[rob_head]&&rob_control[rob_head]。
    wire train0=retire0&&rob_done[rob_head]&&rob_control[rob_head];
    // train1 的资格组合为 registered_pair_retire&&rob_control[head1]。
    wire train1=registered_pair_retire&&rob_control[head1];
`ifdef VERILATOR
    reg [2:0] training_qualification_seen;
    always @(posedge clk)begin
        if(reset)training_qualification_seen<=0;
        else begin
            if(train0!=(retire0&&rob_control[rob_head])||train1!=(retire1&&rob_control[head1]))
                $fatal(1,"R40 completed training qualification differs from original actual retirement");
            if(!training_qualification_seen[0]&&retire1&&!registered_pair_retire)begin
                training_qualification_seen[0]<=1;$display("COVERAGE R40 training_current_integer_no_control");
            end
            if(!training_qualification_seen[1]&&train0)begin training_qualification_seen[1]<=1;$display("COVERAGE R40 training_registered_head");end
            if(!training_qualification_seen[2]&&train1)begin training_qualification_seen[2]<=1;$display("COVERAGE R40 training_registered_pair");end
        end
    end
`endif
    // 子模块 rv32_ooo_frontend 的职责：前端把取指响应、分支预测和队列存储连接到后端的双指令分配接口。
    // 下列命名端口把本层信号连接到该模块，参数覆盖以实例中的原代码为准。
    rv32_ooo_frontend #(.RESET_VECTOR(RESET_VECTOR),.FETCH_CREDITS(FETCH_CREDITS),.ENABLE_REDIRECT_FETCH(ENABLE_REDIRECT_FETCH),
        .ENABLE_COMMITTED_RAS(ENABLE_COMMITTED_RAS),.RAS_DEPTH(RAS_DEPTH),.HISTORY_BITS(HISTORY_BITS),
        .BIMODAL_INDEX_BITS(BIMODAL_INDEX_BITS),.GSHARE_INDEX_BITS(GSHARE_INDEX_BITS)) frontend(
        .clk(clk),.reset(reset),.imem_request_valid(imem_request_valid),.imem_request_ready(imem_request_ready),
        .imem_request_address(imem_request_address),.imem_response_valid(imem_response_valid),
        .imem_response_ready(imem_response_ready),.imem_response_data(imem_response_data),.imem_response_error(imem_response_error|imem_response_page_fault),.imem_response_page_fault(imem_response_page_fault),
        .redirect(recovery),.redirect_address(recovery_address),.maintenance_redirect(maintain_i||maintain_d||trap_enter||return_from_trap||satp_context_commit),.pop_count(allocate_count),.queue_count(fetch_count),
        .instruction0(fetch_instruction0),.instruction1(fetch_instruction1),.pc0(fetch_pc0),.pc1(fetch_pc1),
        .prediction0(fetch_prediction0),.prediction1(fetch_prediction1),.error0(fetch_error0),.error1(fetch_error1),.page_fault0(fetch_page_fault0),.page_fault1(fetch_page_fault1),
        .serial0(fetch_serial0),.serial1(fetch_serial1),.complex0(fetch_complex0),.complex1(fetch_complex1),
        .illegal0(d_bad0),.illegal1(d_bad1),
        .source_used10(d_use10),.source_used20(d_use20),.source_used11(d_use11),.source_used21(d_use21),
        .pc_dispatch_ok0(fetch_pc_dispatch_ok0),.pc_dispatch_ok1(fetch_pc_dispatch_ok1),
        .prediction_sequential0(fetch_prediction_sequential0),.prediction_sequential1(fetch_prediction_sequential1),
        .prediction_context0(fetch_prediction_context0),.prediction_context1(fetch_prediction_context1),
        .train_context0(read_prediction_context(rob_head)),.train_context1(read_prediction_context(head1)),
        .training_ready(predictor_training_ready),.committed_history(predictor_committed_history),
        .redirect_history(recovery_history),
        .recovery_context0(fetch_recovery_context0),.recovery_context1(fetch_recovery_context1),
        .train_instruction0(read_rob_instruction(rob_head)),.train_instruction1(read_rob_instruction(head1)),
        .train0(train0),.train1(train1),.train_pc0(read_rob_pc(rob_head)),.train_pc1(training_successor_pc),
        .train_next0(retirement_next0),.train_next1(retirement_next1),
        .train_conditional0(rob_conditional[rob_head]),.train_conditional1(rob_conditional[head1]),
        .train_taken0(rob_taken[rob_head]),.train_taken1(rob_taken[head1]),
        .train_history_taken0(rob_taken[rob_head]&&!rob_history_sequential[rob_head]),
        .train_history_taken1(rob_taken[head1]&&!rob_history_sequential[head1])
    );

    wire [2:0] d_system0,d_system1;
    wire d_bad_reference0,d_bad_reference1;
    wire ref_use10,ref_use20,ref_use11,ref_use21;
    // d_serial0 属于D-cache 控制，保存串行操作资格，用于阻止不允许重叠的架构操作。
    // 数据 payload 与 tag valid dirty 及路选择须在同一访问上下文中对齐。
    wire d_serial0=fetch_serial0,d_serial1=fetch_serial1;
    wire d_complex0=fetch_complex0,d_complex1=fetch_complex1;
    // 子模块 rv32_execute 的职责：执行译码从指令 PC 和捕获的操作数形成 ALU 访存 分支及系统操作结果。
    rv32_execute decode0(.sequential_target(),.branch_jump_target(),.indirect_jump_target(),
        .instruction(fetch_instruction0),.pc(fetch_pc0),.left(32'b0),.right(32'b0),.csr_value(32'b0),
        .source1(d_rs10),.source2(d_rs20),.destination(d_rd0),.uses_source1(ref_use10),.uses_source2(ref_use20),
        .writes_destination(d_write0),.memory(d_mem0),.memory_write(d_store0),.arithmetic(d_mdu0),
        .csr(d_csr0),.system_operation(d_system0),.illegal(d_bad_reference0));
    rv32_execute decode1(.sequential_target(),.branch_jump_target(),.indirect_jump_target(),
        .instruction(fetch_instruction1),.pc(fetch_pc1),.left(32'b0),.right(32'b0),.csr_value(32'b0),
        .source1(d_rs11),.source2(d_rs21),.destination(d_rd1),.uses_source1(ref_use11),.uses_source2(ref_use21),
        .writes_destination(d_write1),.memory(d_mem1),.memory_write(d_store1),.arithmetic(d_mdu1),
        .csr(d_csr1),.system_operation(d_system1),.illegal(d_bad_reference1));

`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&{d_use10,d_use20}!={ref_use10,ref_use20})
            $fatal(1,"R46 first queued operand-use flags differ from execute decoder");
        if(fetch_count>1&&{d_use11,d_use21}!={ref_use11,ref_use21})
            $fatal(1,"R46 second queued operand-use flags differ from execute decoder");
    end
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&fetch_pc_dispatch_ok0!=(fetch_pc0[1:0]==0))
            $fatal(1,"R30 first queued PC classification mismatch");
        if(fetch_count>1&&fetch_pc_dispatch_ok1!=(fetch_pc1[1:0]==0))
            $fatal(1,"R30 second queued PC classification mismatch");
    end
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&fetch_prediction_sequential0!=(fetch_prediction0==fetch_pc0+32'd4))
            $fatal(1,"R34 first allocation prediction sequence flag mismatch");
        if(fetch_count>1&&fetch_prediction_sequential1!=(fetch_prediction1==fetch_pc1+32'd4))
            $fatal(1,"R34 second allocation prediction sequence flag mismatch");
    end
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&d_bad0!=d_bad_reference0)$fatal(1,"R36 first queued legality differs from original decoder");
        if(fetch_count>1&&d_bad1!=d_bad_reference1)$fatal(1,"R36 second queued legality differs from original decoder");
    end
    // The unchanged original execution decoder is an independent reference
    // for every valid head instruction, including reserved/fault encodings.
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&((fetch_serial0!=(d_csr0||d_system0!=0||fetch_instruction0[6:0]==7'h2f))||
            (fetch_complex0!=(d_mem0||d_mdu0||d_csr0||d_system0!=0))))
            $fatal(1,"frontend lane 0 class differs from original decoder");
        if(fetch_count>1&&((fetch_serial1!=(d_csr1||d_system1!=0||fetch_instruction1[6:0]==7'h2f))||
            (fetch_complex1!=(d_mem1||d_mdu1||d_csr1||d_system1!=0))))
            $fatal(1,"frontend lane 1 class differs from original decoder");
    end
`endif
    wire [31:0] e_value0,e_value1,e_address0,e_address1,e_store0,e_store1,e_next0,e_next1;
    wire [31:0] e_sequential_target0,e_sequential_target1;
    wire [31:0] e_branch_jump_target0,e_branch_jump_target1,e_indirect_jump_target0,e_indirect_jump_target1;
    // e_memory0 属于组合执行结果，保存访存类别资格，供访存顺序与执行资源选择使用。
    // 这些字段属于执行候选，异常或恢复可能取消其写回资格。
    wire e_memory0,e_store_enable0,e_unsigned0,e_arithmetic0,e_control0,e_conditional0,e_taken0,e_csr0,e_csr_write0,e_illegal0;
    // e_memory1 属于组合执行结果，保存访存类别资格，供访存顺序与执行资源选择使用。
    wire e_memory1,e_arithmetic1,e_control1,e_conditional1,e_taken1,e_illegal1;
    // ex_decode_error0 属于执行边界，保存访问或译码错误标志，不能被正常数据值掩盖。
    reg ex_decode_error0,ex_decode_error1;
    wire e_illegal_reference0,e_illegal_reference1;
    // e_illegal0 连接到 ex_decode_error0，两者在此路径上保持字段对应。
    assign e_illegal0=ex_decode_error0;
    // e_illegal1 连接到 ex_decode_error1，两者在此路径上保持字段对应。
    assign e_illegal1=ex_decode_error1;

    // EXMETA experiment: immutable control facts travel with the existing EX
    // packet, not through a new pipeline stage. Preserve raw class bits even
    // for illegal encodings; precise faults still have their original priority.
    // [0] memory, [1] MDU, [2] ordinary integer, [3] misaligned JAL immediate,
    // [4] JALR, [5] static instruction/PC fault. CSR access checks are likewise
    // instruction-only in this implementation, including the rs1/zimm test.
    reg [5:0] ex_control_meta0,ex_control_meta1;
    // ex_csr_access_fault0 属于执行边界，保存异常资格，须携带对应指令或请求身份交给后续处理。
    reg ex_csr_access_fault0;
    reg ex_static_wakeup0,ex_static_wakeup1;
    // TOPT4: operand-dependent JALR alignment is payload, captured with the
    // same instruction and operands at the existing EX edge. No speculation
    // of fault permission and no additional execution cycle is introduced.
    reg ex_jalr_misaligned0,ex_jalr_misaligned1;
    // ex_alu_control0 属于执行边界，保存控制流类别或控制位，供目标选择和分支结果处理使用。
    reg [31:0] ex_alu_control0,ex_alu_control1;
    wire e_memory_reference0,e_memory_reference1;
    wire e_arithmetic_reference0,e_arithmetic_reference1;
    // e_memory0 读取 ex_control_meta0[0] 所选位域；位索引按声明中的高低位顺序解释。
    assign e_memory0=ex_control_meta0[0];
    // e_memory1 读取 ex_control_meta1[0] 所选位域；位索引按声明中的高低位顺序解释。
    assign e_memory1=ex_control_meta1[0];
    // e_arithmetic0 读取 ex_control_meta0[1] 所选位域；位索引按声明中的高低位顺序解释。
    assign e_arithmetic0=ex_control_meta0[1];
    // e_arithmetic1 读取 ex_control_meta1[1] 所选位域；位索引按声明中的高低位顺序解释。
    assign e_arithmetic1=ex_control_meta1[1];

    // e_size0 属于组合执行结果，保存访问尺寸编码，决定对齐和字节选择的处理方式。
    wire [1:0] e_size0; wire [2:0] e_arithmetic_operation0,e_system0;
    // system_access_fault 保存异常资格，须携带对应指令或请求身份交给后续处理。
    wire system_access_fault=(e_system0==2 && current_privilege!=3)||
        (e_system0==7 && (current_privilege==0 || (current_privilege==1&&csr_status[22])))||
        (e_system0==5 && (current_privilege==0 || (current_privilege!=3&&csr_status[21])))||
        (((ex_instruction0&32'hfe007fff)==32'h12000073) &&
            (current_privilege==0 || (current_privilege==1&&csr_status[20])));
    wire [11:0] e_csr_number0; wire [31:0] e_csr_new0;
    wire [31:0] e_value_reference0,e_value_reference1;
    wire [31:0] e_value_predecoded0,e_value_predecoded1;
    // dispatch_alu_control0 属于分配直达执行路径，保存控制流类别或控制位，供目标选择和分支结果处理使用。
    // 快速路径仍遵守源依赖和同拍配对限制，不绕过精确异常。
    wire [31:0] dispatch_alu_control0,dispatch_alu_control1;
    // Decode each frontend packet before allocation and before the late
    // dispatch selector. Queue entries retain this immutable owner metadata.
    rv32_alu_predecode allocation_alu_decode0(.instruction(fetch_instruction0),.control(dispatch_alu_control0));
    rv32_alu_predecode allocation_alu_decode1(.instruction(fetch_instruction1),.control(dispatch_alu_control1));
    rv32_alu_value #(.DUAL_BARREL(ALU_DUAL_BARREL)) alu_value0(
        .control(ex_alu_control0),.pc(ex_pc0),.left(ex_left0),.right(ex_right0),
        .csr_value(read_csr(e_csr_number0)),
        .immediate_i({{20{ex_instruction0[31]}},ex_instruction0[31:20]}),
        .immediate_u({ex_instruction0[31:12],12'b0}),.immediate_shift(ex_instruction0[24:20]),
        .value(e_value_predecoded0));
    rv32_alu_value #(.DUAL_BARREL(ALU_DUAL_BARREL)) alu_value1(
        .control(ex_alu_control1),.pc(ex_pc1),.left(ex_left1),.right(ex_right1),.csr_value(32'b0),
        .immediate_i({{20{ex_instruction1[31]}},ex_instruction1[31:20]}),
        .immediate_u({ex_instruction1[31:12],12'b0}),.immediate_shift(ex_instruction1[24:20]),
        .value(e_value_predecoded1));
    // e_value0 按 ENABLE_PREDECODED_ALU 进行来源选择。
    // 真分支取 e_value_predecoded0；其余情况取 e_value_reference0。
    assign e_value0=ENABLE_PREDECODED_ALU?e_value_predecoded0:e_value_reference0;
    // e_value1 按 ENABLE_PREDECODED_ALU 进行来源选择。
    // 真分支取 e_value_predecoded1；其余情况取 e_value_reference1。
    assign e_value1=ENABLE_PREDECODED_ALU?e_value_predecoded1:e_value_reference1;
    rv32_execute execute0(.instruction(ex_instruction0),.pc(ex_pc0),.left(ex_left0),.right(ex_right0),
        .csr_value(read_csr(e_csr_number0)),.value(e_value_reference0),.address(e_address0),.store_value(e_store0),.next_pc(e_next0),
        .sequential_target(e_sequential_target0),.branch_jump_target(e_branch_jump_target0),.indirect_jump_target(e_indirect_jump_target0),
        .memory(e_memory_reference0),.memory_write(e_store_enable0),.memory_size(e_size0),.memory_unsigned(e_unsigned0),
        .arithmetic(e_arithmetic_reference0),.arithmetic_operation(e_arithmetic_operation0),.control(e_control0),
        .conditional(e_conditional0),.taken(e_taken0),.csr(e_csr0),.csr_write(e_csr_write0),.csr_new_value(e_csr_new0),
        .csr_number(e_csr_number0),.system_operation(e_system0),.illegal(e_illegal_reference0));
    rv32_execute execute1(.instruction(ex_instruction1),.pc(ex_pc1),.left(ex_left1),.right(ex_right1),.csr_value(32'b0),
        .value(e_value_reference1),.address(e_address1),.store_value(e_store1),.next_pc(e_next1),.memory(e_memory_reference1),
        .sequential_target(e_sequential_target1),.branch_jump_target(e_branch_jump_target1),.indirect_jump_target(e_indirect_jump_target1),
        .arithmetic(e_arithmetic_reference1),.control(e_control1),.conditional(e_conditional1),.taken(e_taken1),.illegal(e_illegal_reference1));

    // LSU state retains a presented request even while an old path is discarded.
    localparam L_IDLE=0,L_PREPARED=1,L_OFFER=2,L_WAIT=3;
    // lsu_state 属于活动访存事务，保存协议或执行状态，决定本周期允许的阶段与握手动作。
    // 请求接收与响应消费是两个阶段，直到结束都要保留原事务身份。
    reg [1:0] lsu_state;
    // lsu_tag 属于活动访存事务，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    reg [3:0] lsu_tag; reg [63:0] lsu_sequence; reg [31:0] lsu_pc,lsu_address,lsu_wdata;
    // lsu_strobes 属于活动访存事务，保存逐字节写资格，用于屏蔽未被本次存储修改的字节。
    reg [3:0] lsu_strobes; reg [1:0] lsu_size;
    reg lsu_is_atomic;reg [4:0] lsu_atomic;
    reg prepared_is_atomic,prepared_second_is_atomic;reg [4:0] prepared_atomic,prepared_second_atomic;
    // lsu_store 属于活动访存事务，保存存储类别资格；最终写副作用仍受顺序及握手限定。
    reg lsu_store,lsu_unsigned,lsu_killed,lsu_irrevocable,lsu_writes;
    // lsu_active 由比较式 lsu_state!=L_IDLE 产生；该结果是条件判断，不是被比较的数据。
    wire lsu_active=lsu_state!=L_IDLE;
    // Three registered credits cover A, prepared FIFO P0/P1 and EX.
    // A move uses no credit. Admission never uses the current response/recovery.
    // prepared_valid 属于预备访存项，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 只有获得顺序和资源许可后才能移交活动访存事务。
    reg prepared_valid;
    // prepared_tag 属于预备访存项，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    reg [3:0] prepared_tag,prepared_strobes;
    // prepared_sequence 属于预备访存项，保存完整顺序身份，用来区分标签环绕前后的指令。
    reg [63:0] prepared_sequence;
    // prepared_pc 属于预备访存项，保存指令地址，供退休记录及异常恢复定位。
    reg [31:0] prepared_pc,prepared_address,prepared_wdata;
    // prepared_size 属于预备访存项，保存访问尺寸编码，决定对齐和字节选择的处理方式。
    reg [1:0] prepared_size;
    // prepared_store 属于预备访存项，保存存储类别资格；最终写副作用仍受顺序及握手限定。
    reg prepared_store,prepared_unsigned,prepared_peripheral,prepared_writes;
    // prepared_second_valid 属于第二待发访存，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 它与第一预备项各自保存身份和 payload，不可互相覆盖。
    reg prepared_second_valid;
    // prepared_second_tag 属于第二待发访存，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    reg [3:0] prepared_second_tag,prepared_second_strobes;
    // prepared_second_sequence 属于第二待发访存，保存完整顺序身份，用来区分标签环绕前后的指令。
    reg [63:0] prepared_second_sequence;
    // prepared_second_pc 属于第二待发访存，保存指令地址，供退休记录及异常恢复定位。
    reg [31:0] prepared_second_pc,prepared_second_address,prepared_second_wdata;
    // prepared_second_size 属于第二待发访存，保存访问尺寸编码，决定对齐和字节选择的处理方式。
    reg [1:0] prepared_second_size;
    // prepared_second_store 属于第二待发访存，保存存储类别资格；最终写副作用仍受顺序及握手限定。
    reg prepared_second_store,prepared_second_unsigned,prepared_second_peripheral,prepared_second_writes;
    // ex_memory_reservation 的资格组合为 ex_valid0&&e_memory0&&!fault0。
    wire ex_memory_reservation=ex_valid0&&e_memory0&&!fault0;
    // ex_memory_credit 的资格组合为 ex_valid0&&e_memory0。
    wire ex_memory_credit=ex_valid0&&e_memory0;
    // Memory-class fault qualification avoids the unrelated branch-result
    // alignment cone while preserving exact ownership for ordering checks.
    // ex_memory_order_owner 的资格组合为 ex_memory_credit&&ex_pc0[1:0]==0&& !rob_fetch_error[ex_tag0]&&!e_illegal0&& !((e_size0==2&&e_address0[1:0]!=0)||(e_size0==1&&e_address0[0]))。
    wire ex_memory_order_owner=ex_memory_credit&&ex_pc0[1:0]==0&&
        !rob_fetch_error[ex_tag0]&&!e_illegal0&&
        !((e_size0==2&&e_address0[1:0]!=0)||(e_size0==1&&e_address0[0]));
    // active_reserved 的资格组合为 lsu_active||lsu_irrevocable。
    wire active_reserved=lsu_active||lsu_irrevocable;
    // memory_reservations_wide 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {2'b0,active_reserved}+{2'b0,prepared_valid}+ {2'b0,prepared_second_valid}+{2'b0,ex_memory_reservation}；复制大括号表示重复位域，不是独立队列元素。
    wire [2:0] memory_reservations_wide={2'b0,active_reserved}+{2'b0,prepared_valid}+
        {2'b0,prepared_second_valid}+{2'b0,ex_memory_reservation};
    // issue_memory_reservations 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {2'b0,active_reserved}+{2'b0,prepared_valid}+ {2'b0,prepared_second_valid}+{2'b0,ex_memory_credit}；复制大括号表示重复位域，不是独立队列元素。
    wire [2:0] issue_memory_reservations={2'b0,active_reserved}+{2'b0,prepared_valid}+
        {2'b0,prepared_second_valid}+{2'b0,ex_memory_credit};
    // memory_reservations 已占有的访存资源数量，用于限制新的访存进入而非统计总访存次数。
    // memory_reservations 读取 memory_reservations_wide[1:0] 所选位域；位索引按声明中的高低位顺序解释。
    wire [1:0] memory_reservations=memory_reservations_wide[1:0];
    // ex_shifted_store 属于执行边界，保存存储类别资格；最终写副作用仍受顺序及握手限定。
    // ex_shifted_store 按 e_store0<<{e_address0[1:0],3'b0} 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [31:0] ex_shifted_store=e_store0<<{e_address0[1:0],3'b0};
    // ex_store_strobes 属于执行边界，保存逐字节写资格，用于屏蔽未被本次存储修改的字节。
    // ex_store_strobes 按 e_size0==0 进行来源选择。
    // 真分支取 (4'b0001<<e_address0[1:0])；其余情况取 e_size0==1?(4'b0011<<e_address0[1:0]):4'b1111。
    wire [3:0] ex_store_strobes=e_size0==0?(4'b0001<<e_address0[1:0]):
                               // e_size0 按 =1 选择候选来源；各分支结果仍属于当前组合路径。
                               // e_size0 按 =1 进行来源选择。
                               // 真分支取 (4'b0011<<e_address0[1:0])；其余情况取 4'b1111。
                               e_size0==1?(4'b0011<<e_address0[1:0]):4'b1111;
    // P precedes EX. Every field, including side-effect classification, comes
    // from the same owner. Old response fields remain exclusively in A.
    // candidate_valid 属于当前访存候选，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 组合提议需要握手接受，候选存在不等于已经发生访问。
    // candidate_valid 的资格组合为 prepared_valid||ex_memory_reservation。
    wire candidate_valid=prepared_valid||ex_memory_reservation;
    // candidate_tag 属于当前访存候选，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // candidate_tag 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_tag；其余情况取 ex_tag0。
    wire [3:0] candidate_tag=prepared_valid?prepared_tag:ex_tag0;
    // candidate_writes 属于当前访存候选，保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    // candidate_writes 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_writes；其余情况取 ex_writes0。
    wire candidate_writes=prepared_valid?prepared_writes:ex_writes0;
    // candidate_sequence 属于当前访存候选，保存完整顺序身份，用来区分标签环绕前后的指令。
    // candidate_sequence 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_sequence；其余情况取 ex_sequence0。
    wire [63:0] candidate_sequence=prepared_valid?prepared_sequence:ex_sequence0;
    // candidate_pc 属于当前访存候选，保存指令地址，供退休记录及异常恢复定位。
    // candidate_pc 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_pc；其余情况取 ex_pc0。
    wire [31:0] candidate_pc=prepared_valid?prepared_pc:ex_pc0;
    // candidate_address 属于当前访存候选，保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
    // candidate_address 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_address；其余情况取 e_address0。
    wire [31:0] candidate_address=prepared_valid?prepared_address:e_address0;
    // candidate_wdata 属于当前访存候选，保存写数据 payload，只有对应写请求被接受后才产生副作用。
    // candidate_wdata 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_wdata；其余情况取 ex_shifted_store。
    wire [31:0] candidate_wdata=prepared_valid?prepared_wdata:ex_shifted_store;
    // candidate_strobes 属于当前访存候选，保存逐字节写资格，用于屏蔽未被本次存储修改的字节。
    // candidate_strobes 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_strobes；其余情况取 ex_store_strobes。
    wire [3:0] candidate_strobes=prepared_valid?prepared_strobes:ex_store_strobes;
    // candidate_size 属于当前访存候选，保存访问尺寸编码，决定对齐和字节选择的处理方式。
    // candidate_size 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_size；其余情况取 e_size0。
    wire [1:0] candidate_size=prepared_valid?prepared_size:e_size0;
    // candidate_is_atomic 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_is_atomic；其余情况取 (ex_instruction0[6:0]==7'b0101111)。
    wire candidate_is_atomic=prepared_valid?prepared_is_atomic:(ex_instruction0[6:0]==7'b0101111);
    // candidate_atomic 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_atomic；其余情况取 ex_instruction0[31:27]。
    wire [4:0] candidate_atomic=prepared_valid?prepared_atomic:ex_instruction0[31:27];
    // candidate_store 属于当前访存候选，保存存储类别资格；最终写副作用仍受顺序及握手限定。
    // candidate_store 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_store；其余情况取 e_store_enable0。
    wire candidate_store=prepared_valid?prepared_store:e_store_enable0;
    // candidate_unsigned 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_unsigned；其余情况取 e_unsigned0。
    wire candidate_unsigned=prepared_valid?prepared_unsigned:e_unsigned0;
    // ex_address_offset 按 ex_instruction0[5] 进行来源选择。
    // 真分支取 {ex_instruction0[31:25],ex_instruction0[11:7]}；其余情况取 ex_instruction0[31:20]。
    wire [11:0] ex_address_offset=ex_instruction0[5]?{ex_instruction0[31:25],ex_instruction0[11:7]}:ex_instruction0[31:20];
    // Before translation no VA range establishes whether a load is MMIO.
    // Conservatively commit all memory operations at the ROB head.
    wire ex_peripheral_proposal=1'b1;
    // candidate_peripheral 按 prepared_valid 进行来源选择。
    // 真分支取 prepared_peripheral；其余情况取 ex_peripheral_proposal。
    wire candidate_peripheral=prepared_valid?prepared_peripheral:ex_peripheral_proposal;
    // candidate_side_effect 的资格组合为 candidate_store||candidate_peripheral。
    wire candidate_side_effect=candidate_store||candidate_peripheral;
    // active_room 的资格组合为 !active_reserved||lsu_turnover。
    wire active_room=!active_reserved||lsu_turnover;
    // Raw first-visible head side effects defer IRQ without depending on the
    // recovery decision. A prospective head after retirement is insufficient.
    // ex_head_side_effect 的资格组合为 candidate_valid&&candidate_side_effect&&candidate_tag==rob_head&&!active_reserved。
    wire ex_head_side_effect=candidate_valid&&candidate_side_effect&&candidate_tag==rob_head&&!active_reserved;
    // prepared_side_effect 的资格组合为 lsu_state==L_PREPARED&&lsu_tag==rob_head&&!lsu_irrevocable。
    wire prepared_side_effect=lsu_state==L_PREPARED&&lsu_tag==rob_head&&!lsu_irrevocable;
    // Idle direct loads retain killed capture on recovery. A new turnover
    // offer is suppressed on recovery; no prior held offer is gated this way.
    // Cacheable stores may become irrevocable on the same edge that every
    // older owner retires. Never anticipate an unresolved retirement or an
    // IRQ/recovery boundary. MMIO keeps the original registered-head rule.
    // Keep this gate separate from the raw current-head IRQ deferral above:
    // prospective head ownership must never defer a pending interrupt.
    // retiring_head 保存队头位置，界定本周期最早尚未完成相应生命周期的条目。
    // retiring_head 按 rob_head+{3'b0,retire0}+{3'b0,retire1} 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [3:0] retiring_head=rob_head+{3'b0,retire0}+{3'b0,retire1};
    // store_head_lookahead 的资格组合为 ENABLE_STORE_HEAD_LOOKAHEAD&&retire0&&!recovery&&!interrupt_pending。
    wire store_head_lookahead=ENABLE_STORE_HEAD_LOOKAHEAD&&retire0&&!recovery&&!interrupt_pending;
    // candidate_store_lookahead 的资格组合为 store_head_lookahead&&candidate_store&&!candidate_peripheral&& candidate_tag==retiring_head。
    wire candidate_store_lookahead=store_head_lookahead&&candidate_store&&!candidate_peripheral&&
        candidate_tag==retiring_head;
    // prepared_store_lookahead 的资格组合为 store_head_lookahead&&lsu_state==L_PREPARED&&!lsu_irrevocable&& lsu_store&&!peripheral_address(lsu_address)&&lsu_tag==retiring_head。
    wire prepared_store_lookahead=store_head_lookahead&&lsu_state==L_PREPARED&&!lsu_irrevocable&&
        lsu_store&&!peripheral_address(lsu_address)&&lsu_tag==retiring_head;
    wire direct_request=!reset&&candidate_valid&&active_room&&
                        (candidate_side_effect?((!active_reserved&&candidate_tag==rob_head)||candidate_store_lookahead):
                                               (!active_reserved||!recovery));
    // active_handoff 的资格组合为 candidate_valid&&active_room&&(!recovery||direct_request)。
    wire active_handoff=candidate_valid&&active_room&&(!recovery||direct_request);
`ifdef VERILATOR
    reg [172:0] prior_active_payload;
    always @(posedge clk)begin
        if(reset)prior_active_payload<=0;
        else begin
            if((lsu_active||lsu_irrevocable)&&
               {lsu_tag,lsu_writes,lsu_sequence,lsu_pc,lsu_address,lsu_size,lsu_store,lsu_unsigned,lsu_wdata,lsu_strobes}!=prior_active_payload)
                $fatal(1,"R42 owned LSU payload differs from original handoff-only capture");
            if(active_handoff)prior_active_payload<=
                {candidate_tag,candidate_writes,candidate_sequence,candidate_pc,candidate_address,candidate_size,candidate_store,candidate_unsigned,candidate_wdata,candidate_strobes};
        end
    end
`endif
    // dmem_request_valid 的资格组合为 !reset&&(lsu_state==L_OFFER||direct_request||prepared_side_effect||prepared_store_lookahead)。
    assign dmem_request_valid=!reset&&(lsu_state==L_OFFER||direct_request||prepared_side_effect||prepared_store_lookahead);
    // IDLE and WAIT may present a new direct candidate; PREPARED/OFFER
    // retain the stored old bus owner. Invalid-cycle address is a private
    // proposal and need not wait for faults, recovery or turnover eligibility.
    // direct_address_proposal 的资格组合为 lsu_state==L_IDLE||lsu_state==L_WAIT。
    wire direct_address_proposal=lsu_state==L_IDLE||lsu_state==L_WAIT;
    // dmem_request_is_atomic 按 direct_address_proposal 进行来源选择。
    // 真分支取 candidate_is_atomic；其余情况取 lsu_is_atomic。
    assign dmem_request_is_atomic=direct_address_proposal?candidate_is_atomic:lsu_is_atomic;
    // dmem_request_atomic 按 direct_address_proposal 进行来源选择。
    // 真分支取 candidate_atomic；其余情况取 lsu_atomic。
    assign dmem_request_atomic=direct_address_proposal?candidate_atomic:lsu_atomic;
    // dmem_request_address 按 direct_address_proposal 选择候选来源；各分支结果仍属于当前组合路径。
    // dmem_request_address 按 direct_address_proposal 进行来源选择。
    // 真分支取 candidate_address；其余情况取 lsu_address。
    assign dmem_request_address=direct_address_proposal?candidate_address:lsu_address;
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&dmem_request_valid&&
        dmem_request_address!=(direct_request?candidate_address:lsu_address))
        $fatal(1,"R29 presented data address differs from original owned offer");
`endif
    // dmem_request_write 按 direct_address_proposal 进行来源选择。
    // 真分支取 candidate_store；其余情况取 lsu_store。
    assign dmem_request_write=direct_address_proposal?candidate_store:lsu_store;
    // dmem_request_size 按 direct_address_proposal 选择候选来源；各分支结果仍属于当前组合路径。
    // dmem_request_size 按 direct_address_proposal 进行来源选择。
    // 真分支取 candidate_size；其余情况取 lsu_size。
    assign dmem_request_size=direct_address_proposal?candidate_size:lsu_size;
    // dmem_request_wdata 按 direct_address_proposal 选择候选来源；各分支结果仍属于当前组合路径。
    // dmem_request_wdata 按 direct_address_proposal 进行来源选择。
    // 真分支取 candidate_wdata；其余情况取 lsu_wdata。
    assign dmem_request_wdata=direct_address_proposal?candidate_wdata:lsu_wdata;
    // dmem_request_wstrb 按 direct_address_proposal 选择候选来源；各分支结果仍属于当前组合路径。
    // dmem_request_wstrb 按 direct_address_proposal 进行来源选择。
    // 真分支取 candidate_strobes；其余情况取 lsu_strobes。
    assign dmem_request_wstrb=direct_address_proposal?candidate_strobes:lsu_strobes;
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&dmem_request_valid&&
        {dmem_request_write,dmem_request_size,dmem_request_wdata,dmem_request_wstrb}!=
        {direct_request?candidate_store:lsu_store,direct_request?candidate_size:lsu_size,
         direct_request?candidate_wdata:lsu_wdata,direct_request?candidate_strobes:lsu_strobes})
        $fatal(1,"R42 presented data payload differs from original owned offer");
`endif
    // dmem_response_ready 的资格组合为 !reset&&(lsu_state==L_OFFER||lsu_state==L_WAIT)。
    assign dmem_response_ready=!reset&&(lsu_state==L_OFFER||lsu_state==L_WAIT);
    // lsu_response 的资格组合为 dmem_response_ready&&dmem_response_valid&& (lsu_state==L_WAIT||dmem_request_ready)。
    wire lsu_response=dmem_response_ready&&dmem_response_valid&&
                      (lsu_state==L_WAIT||dmem_request_ready);
    // lsu_shifted 按 dmem_response_rdata >> {lsu_address[1:0],3'b0} 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [31:0] lsu_shifted=dmem_response_rdata >> {lsu_address[1:0],3'b0};
    wire [31:0] lsu_result=(lsu_size==0)?(lsu_unsigned?{24'b0,lsu_shifted[7:0]}:{{24{lsu_shifted[7]}},lsu_shifted[7:0]}):
                           (lsu_size==1)?(lsu_unsigned?{16'b0,lsu_shifted[15:0]}:{{16{lsu_shifted[15]}},lsu_shifted[15:0]}):lsu_shifted;
    // 判断地址是否属于需要按副作用顺序处理的外设区域。
    function peripheral_address;
        // address 保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
        input [31:0] address;
        begin peripheral_address=1'b1;end
    endfunction

    reg mdu_active,mdu_writes; reg [3:0] mdu_tag; reg [63:0] mdu_sequence; reg [31:0] mdu_pc;
    wire mdu_response_present,mul_response_present;
    // mdu_ready 属于乘除路径，保存接收或操作数就绪资格，须结合对应的有效位使用。
    // 结果有效与结果被接收分别处理，未消费结果不能被新任务覆盖。
    wire mdu_ready,mdu_response_valid; wire [31:0] mdu_result;
    // ex_stream_mul 的资格组合为 ENABLE_MUL_STREAM&&e_arithmetic0&&e_arithmetic_operation0==0。
    wire ex_stream_mul=ENABLE_MUL_STREAM&&e_arithmetic0&&e_arithmetic_operation0==0;
    // mul_request_ready 属于低位乘法路径，保存接收或操作数就绪资格，须结合对应的有效位使用。
    // 乘法身份随数据流动，外层还会限定恢复后的所有者存活。
    wire mul_request_ready,mul_unit_request_ready,mul_response_valid,mul_response_ready;
    wire [31:0] mul_result; wire [4:0] mul_response_identity; wire [1:0] mul_occupancy;
    // mul_response_tag 属于低位乘法路径，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // mul_response_tag 读取 mul_response_identity[3:0] 所选位域；位索引按声明中的高低位顺序解释。
    wire [3:0] mul_response_tag=mul_response_identity[3:0];
    // mul_response_writes 属于低位乘法路径，保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    // mul_response_writes 读取 mul_response_identity[4] 所选位域；位索引按声明中的高低位顺序解释。
    wire mul_response_writes=mul_response_identity[4];
    // MDU instruction faults depend on registered instruction/PC metadata;
    // operand-dependent branch/alignment faults cannot apply to this class.
    // mdu_static_fault 属于乘除路径，保存异常资格，须携带对应指令或请求身份交给后续处理。
    // mdu_static_fault 读取 ex_control_meta0[5] 所选位域；位索引按声明中的高低位顺序解释。
    wire mdu_static_fault=ex_control_meta0[5];
    // mul_ex_reserved 的资格组合为 ex_valid0&&ex_stream_mul&&!mdu_static_fault。
    wire mul_ex_reserved=ex_valid0&&ex_stream_mul&&!mdu_static_fault;
    // Full occupancy waits for a registered release; the response-ready /
    // recovery cone never controls the next issue packet. Held EX is not sent.
    // mul_issue_space 由比较式 mul_occupancy!=2 产生；该结果是条件判断，不是被比较的数据。
    wire mul_issue_space=mul_occupancy!=2;
    // mul_request_ready 的资格组合为 mul_issue_space&&mul_unit_request_ready。
    assign mul_request_ready=mul_issue_space&&mul_unit_request_ready;
    // ex_hold 的资格组合为 mul_ex_reserved&&!mul_issue_space。
    wire ex_hold=mul_ex_reserved&&!mul_issue_space;
    // mul_request 的资格组合为 mul_ex_reserved&&!recovery&&!reset。
    wire mul_request=mul_ex_reserved&&!recovery&&!reset;
    // mdu_request 的资格组合为 ex_valid0&&e_arithmetic0&&!ex_stream_mul&&!mdu_static_fault&&!recovery&&!reset。
    wire mdu_request=ex_valid0&&e_arithmetic0&&!ex_stream_mul&&!mdu_static_fault&&!recovery&&!reset;
    // Response arbitration depends only on registered owners and existing
    // completion availability, never new issue or input acceptance.
    // select_stream_result 的资格组合为 mul_response_valid&& (!(mdu_active&&mdu_response_valid)||age(mul_response_tag)<age(mdu_tag))。
    wire select_stream_result=mul_response_valid&&
        (!(mdu_active&&mdu_response_valid)||age(mul_response_tag)<age(mdu_tag));
    // arithmetic_response_space 的资格组合为 !reset&&!recovery&& (!(lsu_response&&!lsu_killed)||(ENABLE_MDU_SPILL&&!ex_valid1))。
    wire arithmetic_response_space=!reset&&!recovery&&
        (!(lsu_response&&!lsu_killed)||(ENABLE_MDU_SPILL&&!ex_valid1));
    // mdu_response_ready 属于乘除路径，保存接收或操作数就绪资格，须结合对应的有效位使用。
    // mdu_response_ready 的资格组合为 arithmetic_response_space&&!select_stream_result。
    wire mdu_response_ready=arithmetic_response_space&&!select_stream_result;
    // mul_response_ready 的资格组合为 arithmetic_response_space&&select_stream_result。
    assign mul_response_ready=arithmetic_response_space&&select_stream_result;
    // complete_legacy 的资格组合为 mdu_active&&mdu_response_valid&&mdu_response_ready。
    wire complete_legacy=mdu_active&&mdu_response_valid&&mdu_response_ready;
    // complete_stream 的资格组合为 mul_response_valid&&mul_response_ready。
    wire complete_stream=mul_response_valid&&mul_response_ready;
    // arithmetic_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // arithmetic_tag 按 select_stream_result 进行来源选择。
    // 真分支取 mul_response_tag；其余情况取 mdu_tag。
    wire [3:0] arithmetic_tag=select_stream_result?mul_response_tag:mdu_tag;
    // arithmetic_writes 保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    // arithmetic_writes 按 select_stream_result 进行来源选择。
    // 真分支取 mul_response_writes；其余情况取 mdu_writes。
    wire arithmetic_writes=select_stream_result?mul_response_writes:mdu_writes;
    // arithmetic_value 按 select_stream_result 进行来源选择。
    // 真分支取 mul_result；其余情况取 mdu_result。
    wire [31:0] arithmetic_value=select_stream_result?mul_result:mdu_result;
    // arithmetic_sequence 保存完整顺序身份，用来区分标签环绕前后的指令。
    // arithmetic_sequence 按 select_stream_result 进行来源选择。
    // 真分支取 rob_sequence[mul_response_tag]；其余情况取 mdu_sequence。
    wire [63:0] arithmetic_sequence=select_stream_result?rob_sequence[mul_response_tag]:mdu_sequence;
    // arithmetic_pc 保存指令地址，供退休记录及异常恢复定位。
    // arithmetic_pc 按 select_stream_result 进行来源选择。
    // 真分支取 read_rob_pc(mul_response_tag)；其余情况取 mdu_pc。
    wire [31:0] arithmetic_pc=select_stream_result?read_rob_pc(mul_response_tag):mdu_pc;
    // 子模块 rv32_mul_stream 的职责：独立低位乘法流水通过请求和响应握手处理 MUL 的低 32 位结果。
    rv32_mul_stream #(.TOKEN_WIDTH(5),.REGISTERED_INPUT_CREDIT(1)) low_multiplier(.clk(clk),.reset(reset),.cancel(recovery),
        .request_valid(mul_request&&mul_issue_space),.request_ready(mul_unit_request_ready),
        .left(ENABLE_LOCAL_MUL_OPERANDS&&ORDERED_SCHEDULER?ex_mul_left_local:ex_left0),
        .right(ENABLE_LOCAL_MUL_OPERANDS&&ORDERED_SCHEDULER?ex_mul_right_local:ex_right0),.request_token({ex_writes0,ex_tag0}),
        .response_valid(mul_response_valid),.response_present(mul_response_present),.response_ready(mul_response_ready),
        .result(mul_result),.response_token(mul_response_identity),.occupancy(mul_occupancy));
    // 子模块 rv32_arithmetic 的职责：乘除单元处理整数乘法高低位 除法及余数操作，结果通过握手返回。
    rv32_arithmetic arithmetic_unit(.clk(clk),.reset(reset),.cancel(recovery),
        .request_valid(mdu_request),.request_ready(mdu_ready),.operation(e_arithmetic_operation0),
        .left(ex_left0),.right(ex_right0),.response_valid(mdu_response_valid),.response_present(mdu_response_present),
        .response_ready(mdu_response_ready),.result(mdu_result));

    // Faults are recorded in order-independent result slots, then handled at head.
    // fault0 保存异常资格，须携带对应指令或请求身份交给后续处理。
    reg fault0,fault1; reg [31:0] fault_cause0,fault_cause1,fault_value0,fault_value1;
    always @* begin
        fault0=0;fault_cause0=0;fault_value0=0;
        if(ex_pc0[1:0]!=0)begin fault0=1;fault_cause0=0;fault_value0=ex_pc0;end
        else if(rob_fetch_error[ex_tag0])begin fault0=1;fault_cause0=rob_fetch_page_fault[ex_tag0]?12:1;fault_value0=ex_pc0;end
        else if(e_illegal0||ex_csr_access_fault0||system_access_fault)begin fault0=1;fault_cause0=2;fault_value0=ex_instruction0;end
        else if(e_control0&&e_next0[1:0]!=0)begin fault0=1;fault_cause0=0;fault_value0=e_next0;end
        else if(e_memory0&&((e_size0==2&&e_address0[1:0]!=0)||(e_size0==1&&e_address0[0])))begin fault0=1;fault_cause0=e_store_enable0?6:4;fault_value0=e_address0;end
        else if(e_system0==3||e_system0==4)begin fault0=1;fault_cause0=e_system0==3?(current_privilege==3?11:(current_privilege==1?9:8)):3;fault_value0=e_system0==4?ex_pc0:0;end
        fault1=0;fault_cause1=0;fault_value1=0;
        if(ex_pc1[1:0]!=0)begin fault1=1;fault_cause1=0;fault_value1=ex_pc1;end
        else if(rob_fetch_error[ex_tag1])begin fault1=1;fault_cause1=rob_fetch_page_fault[ex_tag1]?12:1;fault_value1=ex_pc1;end
        else if(e_illegal1)begin fault1=1;fault_cause1=2;fault_value1=ex_instruction1;end
        else if(e_control1&&e_next1[1:0]!=0)begin fault1=1;fault_cause1=0;fault_value1=e_next1;end
    end

    // 筛选可走普通整数快速路径的指令，排除需要独立处理的复杂类别。
    function ordinary_integer_class;
        // instruction 保存原始指令编码，和该条指令的 PC 及身份同行保存。
        input [31:0] instruction;
        begin ordinary_integer_class=instruction[6:0]==7'b0110111||instruction[6:0]==7'b0010111||
            // instruction[6:0] 的资格组合为 =7'b0010011||。
            instruction[6:0]==7'b0010011||
            (instruction[6:0]==7'b0110011&&instruction[31:25]!=7'b0000001);end
    endfunction
    // A legal ready control operation may use an otherwise idle EX input.
    // It still owns its ROB slot and uses ordinary precise branch retirement;
    // unlike arithmetic, it is NOT eligible for current-successor retirement.
    // 判断分配阶段候选是否满足整数旁路类别限制。
    function dispatch_integer_class;
        input [31:0] instruction;
        begin dispatch_integer_class=ordinary_integer_class(instruction)||
            (ENABLE_CONTROL_DISPATCH&&(instruction[6:0]==7'b1100011||
             // instruction[6:0] 的资格组合为 =7'b1100111||instruction[6:0]==7'b1101111))。
             instruction[6:0]==7'b1100111||instruction[6:0]==7'b1101111));end
    endfunction
    // Instruction/PC fault facts never depend on the general branch-result
    // mux. Ordinary integers can use allocation's registered prediction bit.
    // ex_static_fault1 属于执行边界，保存异常资格，须携带对应指令或请求身份交给后续处理。
    // ex_static_fault1 读取 ex_control_meta1[5] 所选位域；位索引按声明中的高低位顺序解释。
    wire ex_static_fault1=ex_control_meta1[5];
    // 在早期检查中计算加法结果的低位，供 JALR 对齐判断使用。
    function low_sum_bit1;
        input [1:0] lhs,rhs;
        begin low_sum_bit1=lhs[1]^rhs[1]^(lhs[0]&rhs[0]);end
    endfunction
    // jalr_low0 按 ex_left0[1:0]+ex_instruction0[21:20] 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [1:0] jalr_low0=ex_left0[1:0]+ex_instruction0[21:20];
    // jalr_low1 按 ex_left1[1:0]+ex_instruction1[21:20] 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [1:0] jalr_low1=ex_left1[1:0]+ex_instruction1[21:20];
    // wake_jalr_misaligned0 按 ENABLE_EARLY_JALR_CHECK 进行来源选择。
    // 真分支取 ex_jalr_misaligned0；其余情况取 jalr_low0[1]。
    wire wake_jalr_misaligned0=ENABLE_EARLY_JALR_CHECK?ex_jalr_misaligned0:jalr_low0[1];
    // wake_jalr_misaligned1 按 ENABLE_EARLY_JALR_CHECK 进行来源选择。
    // 真分支取 ex_jalr_misaligned1；其余情况取 jalr_low1[1]。
    wire wake_jalr_misaligned1=ENABLE_EARLY_JALR_CHECK?ex_jalr_misaligned1:jalr_low1[1];
    // integer_fault0 保存异常资格，须携带对应指令或请求身份交给后续处理。
    // integer_fault0 的资格组合为 mdu_static_fault||ex_csr_access_fault0|| ex_control_meta0[3]||(ex_control_meta0[4]&&jalr_low0[1])。
    wire integer_fault0=mdu_static_fault||ex_csr_access_fault0||
        ex_control_meta0[3]||(ex_control_meta0[4]&&jalr_low0[1]);
    // integer_fault1 保存异常资格，须携带对应指令或请求身份交给后续处理。
    // integer_fault1 的资格组合为 ex_static_fault1|| ex_control_meta1[3]||(ex_control_meta1[4]&&jalr_low1[1])。
    wire integer_fault1=ex_static_fault1||
        ex_control_meta1[3]||(ex_control_meta1[4]&&jalr_low1[1]);
    wire current_second0=ENABLE_CURRENT_INTEGER_PAIR&&!reset&&!interrupt_pending&&rob_count>1&&!rob_done[head1]&&
        ex_valid0&&ex_tag0==head1&&!mdu_static_fault&&ex_control_meta0[2]&&
        !rob_prediction_miss[head1];
    wire current_second1=ENABLE_CURRENT_INTEGER_PAIR&&!reset&&!interrupt_pending&&rob_count>1&&!rob_done[head1]&&
        ex_valid1&&ex_tag1==head1&&!ex_static_fault1&&ex_control_meta1[2]&&
        !rob_prediction_miss[head1];
    // current_second_integer 的资格组合为 current_second0||current_second1。
    wire current_second_integer=current_second0||current_second1;
    // second_retire_value 按 current_second0 进行来源选择。
    // 真分支取 e_value0；其余情况取 (current_second1?e_value1:read_result(head1))。
    wire [31:0] second_retire_value=current_second0?e_value0:(current_second1?e_value1:read_result(head1));

    // complete0 的资格组合为 !reset&&!recovery&&ex_valid0&&(fault0||(!e_memory0&&!e_arithmetic0))。
    wire complete0=!reset&&!recovery&&ex_valid0&&(fault0||(!e_memory0&&!e_arithmetic0));
    // complete_integer1 的资格组合为 !reset&&!recovery&&ex_valid1。
    wire complete_integer1=!reset&&!recovery&&ex_valid1;
    // Raw head-response eligibility is independent of recovery/complete gating.
    // The response may complete and retire together after all priority checks.
    // head_response 的资格组合为 !reset&&lsu_response&&!lsu_killed&&rob_count!=0&&lsu_tag==rob_head。
    wire head_response=!reset&&lsu_response&&!lsu_killed&&rob_count!=0&&lsu_tag==rob_head;
    // head_response_success 的资格组合为 head_response&&!data_response_fault。
    wire head_response_success=head_response&&!data_response_fault;
    // head_retire_value 按 head_response_success 进行来源选择。
    // 真分支取 lsu_result；其余情况取 read_result(rob_head)。
    wire [31:0] head_retire_value=head_response_success?lsu_result:read_result(rob_head);
    // complete_memory 属于执行完成边界，保存访存类别资格，供访存顺序与执行资源选择使用。
    // 完成资格和顺序退休不同，带异常的指令不能按普通结果提交。
    // complete_memory 的资格组合为 !reset&&lsu_response&&!lsu_killed&& (!recovery||(head_response&&(retire0||data_response_fault)))。
    wire complete_memory=!reset&&lsu_response&&!lsu_killed&&
                         (!recovery||(head_response&&(retire0||data_response_fault)));
    // complete_mdu 的资格组合为 complete_legacy||complete_stream。
    wire complete_mdu=complete_legacy||complete_stream;
    // Reuse the existing idle integer result channel; never a fourth write port.
    // spill_mdu 的资格组合为 ENABLE_MDU_SPILL&&complete_mdu&&complete_memory。
    wire spill_mdu=ENABLE_MDU_SPILL&&complete_mdu&&complete_memory;
    // complete1 的资格组合为 complete_integer1||spill_mdu。
    wire complete1=complete_integer1||spill_mdu;
    // complete_tag1 属于执行完成边界，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // complete_tag1 按 spill_mdu 进行来源选择。
    // 真分支取 arithmetic_tag；其余情况取 ex_tag1。
    wire [3:0] complete_tag1=spill_mdu?arithmetic_tag:ex_tag1;
    // complete_sequence1 属于执行完成边界，保存完整顺序身份，用来区分标签环绕前后的指令。
    // complete_sequence1 按 spill_mdu 进行来源选择。
    // 真分支取 arithmetic_sequence；其余情况取 ex_sequence1。
    wire [63:0] complete_sequence1=spill_mdu?arithmetic_sequence:ex_sequence1;
    // complete_pc1 属于执行完成边界，保存指令地址，供退休记录及异常恢复定位。
    // complete_pc1 按 spill_mdu 进行来源选择。
    // 真分支取 arithmetic_pc；其余情况取 ex_pc1。
    wire [31:0] complete_pc1=spill_mdu?arithmetic_pc:ex_pc1;
    // complete_value1 按 spill_mdu 进行来源选择。
    // 真分支取 arithmetic_value；其余情况取 e_value1。
    wire [31:0] complete_value1=spill_mdu?arithmetic_value:e_value1;
    // complete_fault1 属于执行完成边界，保存异常资格，须携带对应指令或请求身份交给后续处理。
    // complete_fault1 的资格组合为 !spill_mdu&&fault1。
    wire complete_fault1=!spill_mdu&&fault1;
    // complete_writes1 属于执行完成边界，保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    // complete_writes1 按 spill_mdu 进行来源选择。
    // 真分支取 arithmetic_writes；其余情况取 ex_writes1。
    wire complete_writes1=spill_mdu?arithmetic_writes:ex_writes1;
    // complete2 的资格组合为 complete_memory||(complete_mdu&&!spill_mdu)。
    wire complete2=complete_memory||(complete_mdu&&!spill_mdu);
    // complete_tag2 属于执行完成边界，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // complete_tag2 按 complete_memory 进行来源选择。
    // 真分支取 lsu_tag；其余情况取 arithmetic_tag。
    wire [3:0] complete_tag2=complete_memory?lsu_tag:arithmetic_tag;
    // complete_sequence2 属于执行完成边界，保存完整顺序身份，用来区分标签环绕前后的指令。
    // complete_sequence2 按 complete_memory 进行来源选择。
    // 真分支取 lsu_sequence；其余情况取 arithmetic_sequence。
    wire [63:0] complete_sequence2=complete_memory?lsu_sequence:arithmetic_sequence;
    // complete_pc2 属于执行完成边界，保存指令地址，供退休记录及异常恢复定位。
    // complete_pc2 按 complete_memory 进行来源选择。
    // 真分支取 lsu_pc；其余情况取 arithmetic_pc。
    wire [31:0] complete_pc2=complete_memory?lsu_pc:arithmetic_pc;
    // complete_value2 按 complete_memory 进行来源选择。
    // 真分支取 lsu_result；其余情况取 arithmetic_value。
    wire [31:0] complete_value2=complete_memory?lsu_result:arithmetic_value;
    // complete_fault2 属于执行完成边界，保存异常资格，须携带对应指令或请求身份交给后续处理。
    // complete_fault2 的资格组合为 complete_memory&&data_response_fault。
    wire complete_fault2=complete_memory&&data_response_fault;
    // complete_writes2 属于执行完成边界，保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    // complete_writes2 按 complete_memory 进行来源选择。
    // 真分支取 lsu_writes；其余情况取 arithmetic_writes。
    wire complete_writes2=complete_memory?lsu_writes:arithmetic_writes;
    // Default completion packets are self-contained. The alternative is an
    // explicit diagnostic control retaining the pre-boundary ROB lookup.
    // broadcast0 的资格组合为 complete0&&!fault0&&(CARRIED_COMPLETION_WRITES?ex_writes0: (rob_writes[ex_tag0]&&rob_destination[ex_tag0]!=0))。
    wire broadcast0=complete0&&!fault0&&(CARRIED_COMPLETION_WRITES?ex_writes0:
        (rob_writes[ex_tag0]&&rob_destination[ex_tag0]!=0));
    // broadcast1 的资格组合为 complete1&&!complete_fault1&&(CARRIED_COMPLETION_WRITES?complete_writes1: (rob_writes[complete_tag1]&&rob_destination[complete_tag1]!=0))。
    wire broadcast1=complete1&&!complete_fault1&&(CARRIED_COMPLETION_WRITES?complete_writes1:
        (rob_writes[complete_tag1]&&rob_destination[complete_tag1]!=0));
    // broadcast2 的资格组合为 complete2&&!complete_fault2&&(CARRIED_COMPLETION_WRITES?complete_writes2: (rob_writes[complete_tag2]&&rob_destination[complete_tag2]!=0))。
    wire broadcast2=complete2&&!complete_fault2&&(CARRIED_COMPLETION_WRITES?complete_writes2:
        (rob_writes[complete_tag2]&&rob_destination[complete_tag2]!=0));
    // Raw wakeup payloads equal actual completions whenever recovery is
    // false. Recovery cancels queue/EX/rename ownership atomically; it need
    // not feed every data mux and readiness/ranking proposal on that edge.
    // raw_memory 保存访存类别资格，供访存顺序与执行资源选择使用。
    // raw_memory 的资格组合为 !reset&&lsu_response&&!lsu_killed。
    wire raw_memory=!reset&&lsu_response&&!lsu_killed;
    // raw_select_stream 的资格组合为 mul_response_present&& (!(mdu_active&&mdu_response_present)||age(mul_response_tag)<age(mdu_tag))。
    wire raw_select_stream=mul_response_present&&
        (!(mdu_active&&mdu_response_present)||age(mul_response_tag)<age(mdu_tag));
    // raw_arithmetic_space 的资格组合为 !raw_memory||(ENABLE_MDU_SPILL&&!ex_valid1)。
    wire raw_arithmetic_space=!raw_memory||(ENABLE_MDU_SPILL&&!ex_valid1);
    // raw_arithmetic 保存复杂算术类别或结果，和普通整数路径分别仲裁。
    // raw_arithmetic 的资格组合为 !reset&&raw_arithmetic_space&& (mul_response_present||(mdu_active&&mdu_response_present))。
    wire raw_arithmetic=!reset&&raw_arithmetic_space&&
        (mul_response_present||(mdu_active&&mdu_response_present));
    // raw_spill 的资格组合为 ENABLE_MDU_SPILL&&raw_arithmetic&&raw_memory。
    wire raw_spill=ENABLE_MDU_SPILL&&raw_arithmetic&&raw_memory;
    // raw_arithmetic_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // raw_arithmetic_tag 按 raw_select_stream 进行来源选择。
    wire [3:0] raw_arithmetic_tag=raw_select_stream?mul_response_tag:mdu_tag;
    // raw_arithmetic_writes 保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    // raw_arithmetic_writes 按 raw_select_stream 进行来源选择。
    wire raw_arithmetic_writes=raw_select_stream?mul_response_writes:mdu_writes;
    // raw_arithmetic_value 按 raw_select_stream 进行来源选择。
    wire [31:0] raw_arithmetic_value=raw_select_stream?mul_result:mdu_result;
    // wake_tag1 属于唤醒路径，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // 唤醒必须来自正确生产者的有效完成，不能使用被恢复取消的结果。
    // wake_tag1 按 raw_spill 进行来源选择。
    // 真分支取 raw_arithmetic_tag；其余情况取 ex_tag1。
    wire [3:0] wake_tag1=raw_spill?raw_arithmetic_tag:ex_tag1;
    // wake_tag2 属于唤醒路径，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // wake_tag2 按 raw_memory 进行来源选择。
    // 真分支取 lsu_tag；其余情况取 raw_arithmetic_tag。
    wire [3:0] wake_tag2=raw_memory?lsu_tag:raw_arithmetic_tag;
    // wake_value1 按 raw_spill 进行来源选择。
    // 真分支取 raw_arithmetic_value；其余情况取 e_value1。
    wire [31:0] wake_value1=raw_spill?raw_arithmetic_value:e_value1;
    // wake_value2 按 raw_memory 进行来源选择。
    // 真分支取 lsu_result；其余情况取 raw_arithmetic_value。
    wire [31:0] wake_value2=raw_memory?lsu_result:raw_arithmetic_value;
    // wake0_reference 的资格组合为 !reset&&ex_valid0&&!e_memory0&&!e_arithmetic0&&!integer_fault0&& (CARRIED_COMPLETION_WRITES?ex_writes0:(rob_writes[ex_tag0]&&rob_destination[ex_tag0]!=0))。
    wire wake0_reference=!reset&&ex_valid0&&!e_memory0&&!e_arithmetic0&&!integer_fault0&&
        (CARRIED_COMPLETION_WRITES?ex_writes0:(rob_writes[ex_tag0]&&rob_destination[ex_tag0]!=0));
    wire wake1_reference=!reset&&(raw_spill||(ex_valid1&&!e_memory1&&!e_arithmetic1&&!integer_fault1))&&
        (CARRIED_COMPLETION_WRITES?(raw_spill?raw_arithmetic_writes:ex_writes1):
            (rob_writes[wake_tag1]&&rob_destination[wake_tag1]!=0));
    // TOPT4: all wake permission facts are now captured before scheduling.
    // Keep the original operand-based references for the diagnostic fallback
    // and for independent simulation checks, including misaligned JALR.
    // wake0 按 CARRIED_COMPLETION_WRITES 进行来源选择。
    // 真分支取 (!reset&&ex_valid0&&ex_static_wakeup0&&!(ex_control_meta0[4]&&wake_jalr_misaligned0))；其余情况取 wake0_reference。
    wire wake0=CARRIED_COMPLETION_WRITES?
        (!reset&&ex_valid0&&ex_static_wakeup0&&!(ex_control_meta0[4]&&wake_jalr_misaligned0)):wake0_reference;
    // wake1 按 CARRIED_COMPLETION_WRITES 进行来源选择。
    // 真分支取 (raw_spill?(!reset&&raw_arithmetic_writes):early_integer1_wake)；其余情况取 wake1_reference。
    wire wake1=CARRIED_COMPLETION_WRITES?
        (raw_spill?(!reset&&raw_arithmetic_writes):early_integer1_wake):wake1_reference;
    wire wake2=!reset&&(raw_memory?!data_response_fault:raw_arithmetic)&&
        (CARRIED_COMPLETION_WRITES?(raw_memory?lsu_writes:raw_arithmetic_writes):
            (rob_writes[wake_tag2]&&rob_destination[wake_tag2]!=0));
    // R51: compute each response case without using cache hit/response
    // validity in either tag mux or wakeup/ranking cone. The final one-bit
    // select uses raw_memory; actual broadcasts still own every captured value.
    // early_integer1_wake_reference 的资格组合为 !reset&&ex_valid1&&!e_memory1&&!e_arithmetic1&&!integer_fault1&& (CARRIED_COMPLETION_WRITES?ex_writes1:(rob_writes[ex_tag1]&&rob_destination[ex_tag1]!=0))。
    wire early_integer1_wake_reference=!reset&&ex_valid1&&!e_memory1&&!e_arithmetic1&&!integer_fault1&&
        (CARRIED_COMPLETION_WRITES?ex_writes1:(rob_writes[ex_tag1]&&rob_destination[ex_tag1]!=0));
    // early_integer1_wake 按 CARRIED_COMPLETION_WRITES 进行来源选择。
    // 真分支取 (!reset&&ex_valid1&&ex_static_wakeup1&&!(ex_control_meta1[4]&&wake_jalr_misaligned1))；其余情况取 early_integer1_wake_reference。
    wire early_integer1_wake=CARRIED_COMPLETION_WRITES?
        (!reset&&ex_valid1&&ex_static_wakeup1&&!(ex_control_meta1[4]&&wake_jalr_misaligned1)):early_integer1_wake_reference;
`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(wake0!=wake0_reference||wake1!=wake1_reference||
           early_integer1_wake!=early_integer1_wake_reference)
            $fatal(1,"TOPT2 captured wake permission differs from original EX predicate");
        if(ex_valid0&&ex_static_wakeup0!=(ex_writes0&&!e_memory0&&!e_arithmetic0&&
           !ex_control_meta0[5]&&!ex_csr_access_fault0&&!ex_control_meta0[3]))
            $fatal(1,"TOPT2 EX0 static wake metadata mismatch");
        if(ex_valid1&&ex_static_wakeup1!=(ex_writes1&&!e_memory1&&!e_arithmetic1&&
           !ex_control_meta1[5]&&!ex_control_meta1[3]))
            $fatal(1,"TOPT2 EX1 static wake metadata mismatch");
    end
`endif
    // early_memory_wake 的资格组合为 !reset&&!data_response_fault&& (CARRIED_COMPLETION_WRITES?lsu_writes:(rob_writes[lsu_tag]&&rob_destination[lsu_tag]!=0))。
    wire early_memory_wake=!reset&&!data_response_fault&&
        (CARRIED_COMPLETION_WRITES?lsu_writes:(rob_writes[lsu_tag]&&rob_destination[lsu_tag]!=0));
    // Experiment: only the ordered scheduler defers arithmetic dependencies
    // until queue operand capture. Neither counterfactual may bypass a MUL/
    // legacy-MDU result, including a result spilled onto completion lane 1.
    // no_response_wake 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {1'b0,early_integer1_wake,wake0}；复制大括号表示重复位域，不是独立队列元素。
    wire [2:0] no_response_wake={1'b0,early_integer1_wake,wake0};
    // no_response_tags 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {4'b0,ex_tag1,ex_tag0}；复制大括号表示重复位域，不是独立队列元素。
    wire [11:0] no_response_tags={4'b0,ex_tag1,ex_tag0};
    // with_response_wake 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {early_memory_wake,early_integer1_wake,wake0}；复制大括号表示重复位域，不是独立队列元素。
    wire [2:0] with_response_wake={early_memory_wake,early_integer1_wake,wake0};
    // with_response_tags 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {lsu_tag,ex_tag1,ex_tag0}；复制大括号表示重复位域，不是独立队列元素。
    wire [11:0] with_response_tags={lsu_tag,ex_tag1,ex_tag0};
    // Keep the actual eligibility check and selected operand data aligned
    // with those counterfactuals. Lane 1 is integer-only; lane 2 is LSU-only.
    // ordered_broadcast_valid 属于有序调度候选，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 当前选择还需结合操作数就绪 资源许可和恢复状态。
    // ordered_broadcast_valid 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {raw_memory&&early_memory_wake,early_integer1_wake,wake0}；复制大括号表示重复位域，不是独立队列元素。
    wire [2:0] ordered_broadcast_valid={raw_memory&&early_memory_wake,early_integer1_wake,wake0};
    // ordered_broadcast_tags 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    wire [11:0] ordered_broadcast_tags={lsu_tag,ex_tag1,ex_tag0};
    // ordered_broadcast_values 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {lsu_result,e_value1,e_value0}；复制大括号表示重复位域，不是独立队列元素。
    wire [95:0] ordered_broadcast_values={lsu_result,e_value1,e_value0};
    // Full broadcasts remain unchanged for immediate queue/allocation
    // capture and for both diagnostic nonordered scheduler implementations.
    // queue_broadcast_valid 属于前端队列，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 取指字 错误和预测描述须在同一次队列操作中保持对应。
    // queue_broadcast_valid 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {wake2,wake1,wake0}；复制大括号表示重复位域，不是独立队列元素。
    wire [2:0] queue_broadcast_valid={wake2,wake1,wake0};
    // queue_broadcast_tags 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {wake_tag2,wake_tag1,ex_tag0}；复制大括号表示重复位域，不是独立队列元素。
    wire [11:0] queue_broadcast_tags={wake_tag2,wake_tag1,ex_tag0};
    // queue_broadcast_values 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {wake_value2,wake_value1,e_value0}；复制大括号表示重复位域，不是独立队列元素。
    wire [95:0] queue_broadcast_values={wake_value2,wake_value1,e_value0};
    // 按生产者标签查询当前完成广播是否提供可用操作数。
    function broadcast_available;
        input [3:0] tag;
        begin broadcast_available=(queue_broadcast_valid[0]&&queue_broadcast_tags[3:0]==tag)||
            (queue_broadcast_valid[1]&&queue_broadcast_tags[7:4]==tag)||
            (queue_broadcast_valid[2]&&queue_broadcast_tags[11:8]==tag);end
    endfunction
    // 按匹配标签选择广播值，调用者还需确认该值有效且所有者未被取消。
    function [31:0] broadcast_value;
        input [3:0] tag;
        begin broadcast_value=0;
            if(queue_broadcast_valid[0]&&queue_broadcast_tags[3:0]==tag)broadcast_value=queue_broadcast_values[31:0];
            if(queue_broadcast_valid[1]&&queue_broadcast_tags[7:4]==tag)broadcast_value=queue_broadcast_values[63:32];
            if(queue_broadcast_valid[2]&&queue_broadcast_tags[11:8]==tag)broadcast_value=queue_broadcast_values[95:64];
        end
    endfunction
    // 判断指定生产者是否已经能提供值，结合已存结果与当前广播。
    function producer_available;
        input [3:0] tag;
        begin producer_available=(rob_done[tag]&&!rob_fault[tag])||broadcast_available(tag);end
    endfunction
    // 取得对应生产者的值，不能把其他 ROB 行的旧数据当作该生产者结果。
    function [31:0] producer_value;
        input [3:0] tag;
        begin producer_value=broadcast_available(tag)?broadcast_value(tag):read_result(tag);end
    endfunction
    // 以 ROB 头为基准计算环形年龄，避免标签回绕破坏程序顺序比较。
    function [3:0] age;
        input [3:0] tag;
        begin age=tag-rob_head;end
    endfunction
    // A grant-plus-response for a held OFFER still belongs to that old offer.
    // Fast handoff is restricted to WAIT, so its ready cannot accept a new owner.
    // lsu_turnover 的资格组合为 lsu_state==L_WAIT&&lsu_response&&!lsu_killed&&!data_response_fault&& (!lsu_irrevocable||(retire0&&lsu_tag==rob_head)||(retire1&&lsu_tag==head1))。
    wire lsu_turnover=lsu_state==L_WAIT&&lsu_response&&!lsu_killed&&!data_response_fault&&
                      (!lsu_irrevocable||(retire0&&lsu_tag==rob_head)||(retire1&&lsu_tag==head1));
    // active_retiring 的资格组合为 (retire0&&lsu_tag==rob_head)||(retire1&&lsu_tag==head1)。
    wire active_retiring=(retire0&&lsu_tag==rob_head)||(retire1&&lsu_tag==head1);
    // active_release 的资格组合为 (lsu_response&&(!lsu_irrevocable||active_retiring||trap_enter))|| (!lsu_active&&lsu_irrevocable&&active_retiring)。
    wire active_release=(lsu_response&&(!lsu_irrevocable||active_retiring||trap_enter))||
                        (!lsu_active&&lsu_irrevocable&&active_retiring);
    wire memory_issue_credit=issue_memory_reservations<MEMORY_CREDITS;
    // Static ownership/order matrix: no function-local loop variables in the
    // synthesized memory-order cone. Killed owners cannot exempt reused tags.
    wire [15:0] memory_blocker,memory_order_blocker,memory_store_blocker;
    wire [15:0] memory_store_base;
    // TOPT2: at most one memory owner can leave the complex bank per cycle.
    // Prepare blocker summaries and each candidate's membership BEFORE the
    // late grant. Integer slots cannot contain memory operations. The global
    // selection only gates four already-prepared release possibilities.
    wire [3:0] memory_release_select;
    wire [15:0] memory_release_tags;
    genvar memory_candidate;
    generate for(memory_candidate=0;memory_candidate<4;memory_candidate=memory_candidate+1)begin:order_release_candidates
        // memory_release_tags[memory_candidate*4+:4] 读取 q_tag[8+memory_candidate] 所选位域；位索引按声明中的高低位顺序解释。
        assign memory_release_tags[memory_candidate*4+:4]=q_tag[8+memory_candidate];
        // memory_release_select[memory_candidate] 的资格组合为 ordered_mask0[8+memory_candidate]&&。
        assign memory_release_select[memory_candidate]=ordered_mask0[8+memory_candidate]&&
            q_memory[8+memory_candidate]&&!q_error[8+memory_candidate]&&
            ((LOAD_ORDER_ISSUE_LOOKAHEAD&&!rob_store[q_tag[8+memory_candidate]])||
             (ENABLE_ORDERED_STORE_PREP&&ENABLE_STORE_ISSUE_LOOKAHEAD&&rob_store[q_tag[8+memory_candidate]]));
    end endgenerate
    // entering_load_tag 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // entering_load_tag 连接到 issue_payload_tag0，两者在此路径上保持字段对应。
    wire [3:0] entering_load_tag=issue_payload_tag0;
    // entering_memory 保存访存类别资格，供访存顺序与执行资源选择使用。
    // entering_memory 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 (|(ordered_mask0&ordered_memory_good))；其余情况取 (issue_present0&&q_memory[issue_present0?issue_choice0:0]&& !q_error[issue_present0?issue_choice0:0])。
    wire entering_memory=ORDERED_SCHEDULER?(|(ordered_mask0&ordered_memory_good)):
        (issue_present0&&q_memory[issue_present0?issue_choice0:0]&&
         !q_error[issue_present0?issue_choice0:0]);
    // entering_load 的资格组合为 entering_memory&&!rob_store[entering_load_tag]。
    wire entering_load=entering_memory&&!rob_store[entering_load_tag];
    // A surviving selected load is registered in EX before a younger issue.
    // Its eventual local fault still completes precisely and kills younger
    // work. Stores retain the exact pre-existing, nonfaulting-owner rule.
    // Only this admission register sees the issue proposal; no data-result or
    // current-response path is restored into the age matrix/scheduler.
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&!recovery&&entering_load)begin
        if(!rob_valid[entering_load_tag]||!rob_memory[entering_load_tag]||rob_store[entering_load_tag])
            $fatal(1,"R19 load admission proposal lacks exact live load identity");
    end
`endif
    wire [11:0] older_memory_waiting;
    // TOPT6: fold the immutable owner class into the existing order edge.
    // For a live queue owner this is q_error || !q_memory || old_order_clear.
    // Current-cycle resource credit and serial/head eligibility stay separate.
    // memory_order_permission 对待发射访存的顺序许可，必须与资源空闲和操作数就绪分别判断。
    reg [11:0] memory_order_permission;
    integer order_index;
    // Blocker set visible to a newly allocated owner. A store keeps the full
    // memory order; under LOAD_BYPASS a load only sees older stores. With
    // LOAD_BYPASS=0 both selects fall back to memory_order_blocker and the
    // expressions are identical to the frozen baseline.
    // alloc0_store_only 的资格组合为 LOAD_BYPASS&&!d_store0。
    wire alloc0_store_only=LOAD_BYPASS&&!d_store0;
    // alloc1_store_only 的资格组合为 LOAD_BYPASS&&!d_store1。
    wire alloc1_store_only=LOAD_BYPASS&&!d_store1;
    // alloc0_blocker 按 alloc0_store_only 进行来源选择。
    // 真分支取 memory_store_blocker；其余情况取 memory_order_blocker。
    wire [15:0] alloc0_blocker=alloc0_store_only?memory_store_blocker:memory_order_blocker;
    // alloc1_blocker 按 alloc1_store_only 进行来源选择。
    wire [15:0] alloc1_blocker=alloc1_store_only?memory_store_blocker:memory_order_blocker;
    wire alloc0_wait,alloc1_wait;
    generate if(ORDERED_SCHEDULER)begin:factored_allocation_order
        rv32_order_release_filter alloc0_filter(
            .blockers(alloc0_store_only?memory_store_base:memory_blocker),
            .selected_release(memory_release_select),.selected_tags(memory_release_tags),.waiting(alloc0_wait));
        rv32_order_release_filter alloc1_filter(
            .blockers(alloc1_store_only?memory_store_base:memory_blocker),
            .selected_release(memory_release_select),.selected_tags(memory_release_tags),.waiting(alloc1_wait));
    end else begin:legacy_allocation_order
        // alloc0_wait 对 |alloc0_blocker 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
        assign alloc0_wait=|alloc0_blocker;
        // alloc1_wait 对 |alloc1_blocker 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
        assign alloc1_wait=|alloc1_blocker;
    end endgenerate
`ifdef VERILATOR
    integer memory_class_row;
    always @(posedge clk)if(!reset&&ORDERED_SCHEDULER)begin
        if((memory_release_select&(memory_release_select-4'b1))!=0)
            $fatal(1,"TOPT2 memory lookahead released multiple owners");
        for(memory_class_row=0;memory_class_row<8;memory_class_row=memory_class_row+1)
            if(q_valid[memory_class_row]&&q_memory[memory_class_row])
                $fatal(1,"TOPT2 memory owner escaped complex queue bank");
        if((|(ordered_mask0[7:0]&ordered_memory_good[7:0]))||
           alloc0_wait!=(|alloc0_blocker)||alloc1_wait!=(|alloc1_blocker))
            $fatal(1,"TOPT2 allocation order filter differs from full original matrix");
    end
`endif
    always @(posedge clk)begin
        // 恢复或冲刷条件 if(reset||recovery)memory_order_permission<=12'hfff; 控制下列状态更新，旧事务的处理不能当成新请求接受。
        if(reset||recovery)memory_order_permission<=12'hfff;
        else for(order_index=0;order_index<12;order_index=order_index+1)begin
            // Allocation has the same priority as the original clear register.
            // Error is exactly the queue payload's fetch_error || decode_error.
            if(allocation_offer_count!=0&&allocation_slot0==order_index)
                // memory_order_permission[order_index] 在此时钟更新路径捕获 fetch_error0||d_bad0||!d_mem0||!alloc0_wait，该更新仍受外层条件与后续同块赋值优先级限定。
                // 本时钟边界的 memory_order_permission[order_index] 的资格组合为 fetch_error0||d_bad0||!d_mem0||!alloc0_wait。
                memory_order_permission[order_index]<=fetch_error0||d_bad0||!d_mem0||!alloc0_wait;
            else if(allocation_offer_count==2&&allocation_slot1==order_index)
                // memory_order_permission[order_index] 在此时钟更新路径捕获 fetch_error1||d_bad1||!d_mem1||，该更新仍受外层条件与后续同块赋值优先级限定。
                // 本时钟边界的 memory_order_permission[order_index] 的资格组合为 fetch_error1||d_bad1||!d_mem1||。
                memory_order_permission[order_index]<=fetch_error1||d_bad1||!d_mem1||
                    (!alloc1_wait&&(alloc1_store_only?!d_store0:!d_mem0));
            else memory_order_permission[order_index]<=q_error[order_index]||!q_memory[order_index]||
                (q_valid[order_index]&&!older_memory_waiting[order_index]);
        end
    end
`ifdef VERILATOR
    // Original raw-clear recurrence remains an independent simulation shadow.
    // It is not a hardware register and grants no owner or resource credit.
    reg [11:0] memory_order_clear_reference;
    integer order_reference_index;
    always @(posedge clk)begin
        // 恢复或冲刷条件 if(reset||recovery)memory_order_clear_reference<=0; 控制下列状态更新，旧事务的处理不能当成新请求接受。
        if(reset||recovery)memory_order_clear_reference<=0;
        else for(order_reference_index=0;order_reference_index<12;order_reference_index=order_reference_index+1)begin
            // Every pre-edge valid ROB owner precedes a new tail allocation.
            // A second memory allocation also waits for the first allocation
            // when that first allocation is a store (or always, without bypass).
            // Selected registered address credits remain independently enforced.
            if(allocation_offer_count!=0&&allocation_slot0==order_reference_index)
                memory_order_clear_reference[order_reference_index]<=!alloc0_wait;
            else if(allocation_offer_count==2&&allocation_slot1==order_reference_index)
                // 本时钟边界的 memory_order_clear_reference[order_reference_index] 的资格组合为 !alloc1_wait&&。
                memory_order_clear_reference[order_reference_index]<=!alloc1_wait&&
                    (alloc1_store_only?!d_store0:!d_mem0);
            else memory_order_clear_reference[order_reference_index]<=q_valid[order_reference_index]&&!older_memory_waiting[order_reference_index];
        end
    end
    integer order_permission_check_row;
    always @(posedge clk)if(!reset)begin
        for(order_permission_check_row=0;order_permission_check_row<12;order_permission_check_row=order_permission_check_row+1)
            if(q_valid[order_permission_check_row]&&
               memory_order_permission[order_permission_check_row]!=
               (q_error[order_permission_check_row]||!q_memory[order_permission_check_row]||
                memory_order_clear_reference[order_permission_check_row]))
                $fatal(1,"TOPT6 order permission lost its live queue owner/class");
    end
`endif
    genvar mr,mq,load_queue;
    generate for(mr=0;mr<16;mr=mr+1)begin:memory_order_rows
        wire owned=(lsu_active&&!lsu_killed&&lsu_tag==mr)||
                   (prepared_valid&&prepared_tag==mr)||
                   (prepared_second_valid&&prepared_second_tag==mr)||
                   (ex_memory_order_owner&&ex_tag0==mr);
        // memory_blocker[mr] 的资格组合为 rob_valid[mr]&&rob_memory[mr]&&。
        assign memory_blocker[mr]=rob_valid[mr]&&rob_memory[mr]&&
            ((!rob_done[mr]&&!owned)||(rob_store[mr]&&!(ENABLE_ORDERED_STORE_PREP&&owned)));
        // Decode each queued owner before the late grant. Avoid grant ->
        // encoded queue -> tag mux -> tag equality on the order-credit edge.
        wire [11:0] selected_load_owner;
        for(load_queue=0;load_queue<12;load_queue=load_queue+1)begin:load_owner
            // selected_load_owner[load_queue] 的资格组合为 ordered_mask0[load_queue]&&q_memory[load_queue]&&。
            assign selected_load_owner[load_queue]=ordered_mask0[load_queue]&&q_memory[load_queue]&&
                !q_error[load_queue]&&q_tag[load_queue]==mr;
        end
        // selected_memory 保存访存类别资格，供访存顺序与执行资源选择使用。
        // selected_memory 按 ORDERED_SCHEDULER 进行来源选择。
        // 真分支取 (|selected_load_owner)；其余情况取 (entering_memory&&entering_load_tag==mr)。
        wire selected_memory=ORDERED_SCHEDULER?(|selected_load_owner):
            (entering_memory&&entering_load_tag==mr);
        // selected_load 的资格组合为 selected_memory&&!rob_store[mr]。
        wire selected_load=selected_memory&&!rob_store[mr];
        // This only forwards next-cycle address-preparation order. A selected
        // store enters registered EX before a younger issue. A local EX fault
        // completes precisely and younger prepared stores remain unable to
        // present any side effect across that older nonretiring fault.
        // The existing memory credits, prepared FIFO, and actual bus-head gate
        // are unchanged; this grants neither memory access nor retirement.
        // selected_store 保存存储类别资格；最终写副作用仍受顺序及握手限定。
        // selected_store 的资格组合为 selected_memory&&rob_store[mr]。
        wire selected_store=selected_memory&&rob_store[mr];
`ifdef VERILATOR
        reg selected_store_prior;
        reg [63:0] selected_store_sequence_prior;
        reg [31:0] selected_store_pc_prior;
        always @(posedge clk) begin
            if(reset)selected_store_prior<=0;
            else begin
                if(selected_store_prior&&(!ex_valid0||ex_tag0!=mr||
                   ex_sequence0!=selected_store_sequence_prior||ex_pc0!=selected_store_pc_prior))
                    $fatal(1,"Selected-store order lookahead lost exact next-cycle EX owner");
                // 本时钟边界的 selected_store_prior 的资格组合为 ENABLE_ORDERED_STORE_PREP&&ENABLE_STORE_ISSUE_LOOKAHEAD&&!recovery&&selected_store。
                selected_store_prior<=ENABLE_ORDERED_STORE_PREP&&ENABLE_STORE_ISSUE_LOOKAHEAD&&!recovery&&selected_store;
                // 恢复或冲刷条件 if(ENABLE_ORDERED_STORE_PREP&&ENABLE_STORE_ISSUE_LOOKAHEAD&&!recovery&&selected_store) 控制下列状态更新，旧事务的处理不能当成新请求接受。
                if(ENABLE_ORDERED_STORE_PREP&&ENABLE_STORE_ISSUE_LOOKAHEAD&&!recovery&&selected_store)begin
                    if(!rob_valid[mr]||!rob_memory[mr])
                        $fatal(1,"Selected-store order lookahead lacks exact live memory owner");
                    // 本时钟边界的 selected_store_sequence_prior 读取 rob_sequence[mr] 所选位域；位索引按声明中的高低位顺序解释。
                    selected_store_sequence_prior<=rob_sequence[mr];
                    // 本时钟边界的 selected_store_pc_prior 通过 read_rob_pc(mr) 查询对应字段；结果资格仍由调用点的有效条件限定。
                    selected_store_pc_prior<=read_rob_pc(mr);
                end
            end
        end
`endif
        // memory_order_blocker[mr] 的资格组合为 memory_blocker[mr]&&。
        assign memory_order_blocker[mr]=memory_blocker[mr]&&
            !(LOAD_ORDER_ISSUE_LOOKAHEAD&&selected_load)&&
            !(ENABLE_ORDERED_STORE_PREP&&ENABLE_STORE_ISSUE_LOOKAHEAD&&selected_store);
        // Store-only blocker set: under LOAD_BYPASS this is the only ordering a
        // younger load observes. Stores are still published to the cache in
        // program order by the LSU and only at the ROB head, so store->load and
        // store->store ordering is unchanged.
        // memory_store_blocker[mr] 的资格组合为 memory_order_blocker[mr]&&rob_store[mr]。
        assign memory_store_blocker[mr]=memory_order_blocker[mr]&&rob_store[mr];
        // memory_store_base[mr] 的资格组合为 memory_blocker[mr]&&rob_store[mr]。
        assign memory_store_base[mr]=memory_blocker[mr]&&rob_store[mr];
    end
    for(mq=0;mq<12;mq=mq+1)begin:memory_order_columns
        wire [15:0] blocks,base_blocks;
        // A queued owner is a load only when it is memory-class and not a store.
        // query_store_only 的资格组合为 !(LOAD_BYPASS&&!q_store[mq])。
        wire query_store_only=!(LOAD_BYPASS&&!q_store[mq]);
        for(mr=0;mr<16;mr=mr+1)begin:compare_age
            wire [3:0] row_age=mr-rob_head;
            // query_age 按 q_tag[mq]-rob_head 计算，运算位宽与有无符号以原声明和显式扩展为准。
            wire [3:0] query_age=q_tag[mq]-rob_head;
            assign blocks[mr]=(query_store_only?memory_order_blocker[mr]:memory_store_blocker[mr])
                &&(row_age<query_age);
            assign base_blocks[mr]=(query_store_only?memory_blocker[mr]:memory_store_base[mr])
                &&(row_age<query_age);
        end
        if(ORDERED_SCHEDULER)begin:factored_order
            rv32_order_release_filter filter(
                .blockers(base_blocks),.selected_release(memory_release_select),
                .selected_tags(memory_release_tags),.waiting(older_memory_waiting[mq]));
`ifdef VERILATOR
            always @(posedge clk)if(!reset&&older_memory_waiting[mq]!=(|blocks))
                $fatal(1,"TOPT2 queued order filter differs from full original age matrix");
`endif
        end else begin:legacy_order
            // older_memory_waiting[mq] 对 |blocks 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
            assign older_memory_waiting[mq]=|blocks;
        end
    end endgenerate

    // Ordinary retirement uses registered completions. A successful current
    // LSU head response may retire with explicit value forwarding; a successor
    // may pair when registered complete, or as the narrowly qualified current
    // ordinary-integer successor. Slot0 completion rules remain unchanged.
    always @* begin
        retire0=0;retire1=0;registered_pair_retire=0;recovery=0;recovery_address=architectural_pc;
        trap_enter=0;return_from_trap=0;maintain_i=0;maintain_d=0;
        // trap_pc 连接到 architectural_pc，两者在此路径上保持字段对应。
        trap_pc=architectural_pc;trap_cause=0;trap_value=0;recovery_first=next_sequence;
        if(!reset)begin
            if(rob_count!=0&&rob_done[rob_head]&&rob_fault[rob_head])begin
                trap_enter=1;trap_pc=read_rob_pc(rob_head);trap_cause=rob_cause[rob_head];trap_value=read_rob_tval(rob_head);recovery_first=rob_sequence[rob_head];
            end else if(head_response&&data_response_fault)begin
                trap_enter=1;trap_pc=read_rob_pc(rob_head);trap_cause=dmem_response_page_fault?(lsu_store?15:13):(lsu_store?7:5);trap_value=lsu_address;recovery_first=rob_sequence[rob_head];
            end else if(interrupt_pending&&!lsu_irrevocable&&!ex_head_side_effect&&!prepared_side_effect)begin
                trap_enter=1;trap_pc=rob_count!=0?read_rob_pc(rob_head):architectural_pc;
                // trap_cause 按 interrupt_cause;recovery_first=rob_count!=0 选择候选来源；各分支结果仍属于当前组合路径。
                // trap_cause 连接到 interrupt_cause，两者在此路径上保持字段对应。
                trap_cause=interrupt_cause;recovery_first=rob_count!=0?rob_sequence[rob_head]:next_sequence;
            end else if(rob_count!=0&&(rob_done[rob_head]||head_response_success)&&
                (predictor_training_ready||!rob_conditional[rob_head]))begin
                retire0=1;
                if((rob_system[rob_head]==2||rob_system[rob_head]==7))begin
                    return_from_trap=1;recovery=1;recovery_address=rob_system[rob_head]==7?csr_sepc:csr_exception_pc;recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_system[rob_head]==1||rob_system[rob_head]==6)begin
                    maintain_i=1;maintain_d=rob_system[rob_head]==6;recovery=1;recovery_address=retirement_next0;recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_csr_write[rob_head]&&serial_csr_number==12'h180)begin
                    // Refetch younger instructions under the new SATP without
                    // invalidating ASID-tagged TLB entries (SFENCE is separate).
                    recovery=1;recovery_address=retirement_next0;recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_prediction_miss[rob_head])begin
                    recovery=1;recovery_address=retirement_next0;recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(ENABLE_PAIRING&&!rob_serial[rob_head]&&rob_count>1&&!rob_fault[head1]&&!rob_serial[head1])begin
                    // Only a registered completed successor can mispredict.
                    // Current ordinary integer pairing explicitly requires a
                    // correct registered prediction. Keep its legality cone
                    // out of recovery-address selection instead of relying on
                    // cross-condition boolean simplification by the compiler.
                    if(rob_done[head1]&&(predictor_training_ready||!rob_conditional[head1]))begin
                        retire1=1;registered_pair_retire=1;
                        if(rob_prediction_miss[head1])begin recovery=1;recovery_address=retirement_next1;recovery_first=rob_sequence[head1]+64'd1;end
                    end else if(current_second_integer)retire1=1;
                end
            end
            // A pending IRQ cannot be deferred by an endless succession of
            // new head side effects. Finish the current irrevocable owner and
            // any legal completed successor, then trap at that exact boundary.
            if(interrupt_pending&&lsu_irrevocable&&((retire0&&lsu_tag==rob_head)||(registered_pair_retire&&lsu_tag==head1)))begin
                trap_enter=1;trap_cause=interrupt_cause;trap_value=0;
                // trap_pc 按 registered_pair_retire 选择候选来源；各分支结果仍属于当前组合路径。
                // trap_pc 按 registered_pair_retire 进行来源选择。
                // 真分支取 retirement_next1；其余情况取 retirement_next0。
                trap_pc=registered_pair_retire?retirement_next1:retirement_next0;
                // recovery_first 按 (registered_pair_retire?rob_sequence[head1]:rob_sequence[rob_head])+64'd1 计算，运算位宽与有无符号以原声明和显式扩展为准。
                recovery_first=(registered_pair_retire?rob_sequence[head1]:rob_sequence[rob_head])+64'd1;
            end
            if(trap_enter)begin recovery=1;recovery_address=trap_target(trap_cause);end
        end
    end
`ifdef VERILATOR
    reg prior_retire0,prior_retire1,prior_recovery,prior_trap_enter,prior_return_from_trap,prior_maintain_i,prior_maintain_d;
    // prior_recovery_address 属于上一边界快照，保存地址 payload，具体是虚拟或物理地址由所在接口边界决定。
    // 该快照与本拍组合候选分开，避免晚路径反向影响已有所有权。
    reg [31:0] prior_recovery_address,prior_trap_pc,prior_trap_cause,prior_trap_value;
    reg [63:0] prior_recovery_first;
    always @* begin
        prior_retire0=0;prior_retire1=0;prior_recovery=0;prior_recovery_address=architectural_pc;
        prior_trap_enter=0;prior_return_from_trap=0;prior_maintain_i=0;prior_maintain_d=0;
        // prior_trap_pc 连接到 architectural_pc，两者在此路径上保持字段对应。
        prior_trap_pc=architectural_pc;prior_trap_cause=0;prior_trap_value=0;prior_recovery_first=next_sequence;
        if(!reset)begin
            if(rob_count!=0&&rob_done[rob_head]&&rob_fault[rob_head])begin
                prior_trap_enter=1;prior_trap_pc=read_rob_pc(rob_head);prior_trap_cause=rob_cause[rob_head];prior_trap_value=read_rob_tval(rob_head);prior_recovery_first=rob_sequence[rob_head];
            end else if(head_response&&data_response_fault)begin
                prior_trap_enter=1;prior_trap_pc=read_rob_pc(rob_head);prior_trap_cause=dmem_response_page_fault?(lsu_store?15:13):(lsu_store?7:5);prior_trap_value=lsu_address;prior_recovery_first=rob_sequence[rob_head];
            end else if(interrupt_pending&&!lsu_irrevocable&&!ex_head_side_effect&&!prepared_side_effect)begin
                prior_trap_enter=1;prior_trap_pc=rob_count!=0?read_rob_pc(rob_head):architectural_pc;
                // prior_trap_cause 按 interrupt_cause;prior_recovery_first=rob_count!=0 选择候选来源；各分支结果仍属于当前组合路径。
                // prior_trap_cause 连接到 interrupt_cause，两者在此路径上保持字段对应。
                prior_trap_cause=interrupt_cause;prior_recovery_first=rob_count!=0?rob_sequence[rob_head]:next_sequence;
            end else if(rob_count!=0&&(rob_done[rob_head]||head_response_success)&&
                (predictor_training_ready||!rob_conditional[rob_head]))begin
                prior_retire0=1;
                if((rob_system[rob_head]==2||rob_system[rob_head]==7))begin
                    prior_return_from_trap=1;prior_recovery=1;prior_recovery_address=rob_system[rob_head]==7?csr_sepc:csr_exception_pc;prior_recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_system[rob_head]==1||rob_system[rob_head]==6)begin
                    prior_maintain_i=1;prior_maintain_d=rob_system[rob_head]==6;prior_recovery=1;prior_recovery_address=read_rob_next(rob_head);prior_recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_csr_write[rob_head]&&serial_csr_number==12'h180)begin
                    prior_recovery=1;prior_recovery_address=read_rob_next(rob_head);prior_recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_prediction_miss[rob_head])begin
                    prior_recovery=1;prior_recovery_address=read_rob_next(rob_head);prior_recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(ENABLE_PAIRING&&!rob_serial[rob_head]&&rob_count>1&&(predictor_training_ready||!rob_conditional[head1])&&(rob_done[head1]||current_second_integer)&&!rob_fault[head1]&&!rob_serial[head1])begin
                    prior_retire1=1;
                    if(rob_prediction_miss[head1])begin prior_recovery=1;prior_recovery_address=read_rob_next(head1);prior_recovery_first=rob_sequence[head1]+64'd1;end
                end
            end
            // A pending IRQ cannot be deferred by an endless succession of
            // new head side effects. Finish the current irrevocable owner and
            // any legal completed successor, then trap at that exact boundary.
            if(interrupt_pending&&lsu_irrevocable&&((prior_retire0&&lsu_tag==rob_head)||(prior_retire1&&lsu_tag==head1)))begin
                prior_trap_enter=1;prior_trap_cause=interrupt_cause;prior_trap_value=0;
                // prior_trap_pc 按 prior_retire1 选择候选来源；各分支结果仍属于当前组合路径。
                // prior_trap_pc 按 prior_retire1 进行来源选择。
                // 真分支取 read_rob_next(head1)；其余情况取 read_rob_next(rob_head)。
                prior_trap_pc=prior_retire1?read_rob_next(head1):read_rob_next(rob_head);
                // prior_recovery_first 按 (prior_retire1?rob_sequence[head1]:rob_sequence[rob_head])+64'd1 计算，运算位宽与有无符号以原声明和显式扩展为准。
                prior_recovery_first=(prior_retire1?rob_sequence[head1]:rob_sequence[rob_head])+64'd1;
            end
            if(prior_trap_enter)begin prior_recovery=1;prior_recovery_address=trap_target(prior_trap_cause);end
        end
    end
    always @(posedge clk)if(!reset)begin
        if(interrupt_pending&&retire1!=registered_pair_retire)$fatal(1,"R29 current pairing survived pending interrupt");
        if(retire0!=prior_retire0||
           retire1!=prior_retire1||
           recovery!=prior_recovery||
           recovery_address!=prior_recovery_address||
           trap_enter!=prior_trap_enter||
           return_from_trap!=prior_return_from_trap||
           maintain_i!=prior_maintain_i||
           maintain_d!=prior_maintain_d||
           trap_pc!=prior_trap_pc||
           trap_cause!=prior_trap_cause||
           trap_value!=prior_trap_value||
           recovery_first!=prior_recovery_first)
            $fatal(1,"R29 retirement/recovery differs from prior decision");
    end
`endif
    wire [HISTORY_BITS-1:0] committed_history_after0=(retire0&&rob_conditional[rob_head])?
        {predictor_committed_history[HISTORY_BITS-2:0],(rob_taken[rob_head]&&!rob_history_sequential[rob_head])}:predictor_committed_history;
    // committed_history_after1 按 (retire1&&rob_conditional[head1]) 进行来源选择。
    // 真分支取 {committed_history_after0[HISTORY_BITS-2:0],(rob_taken[head1]&&!rob_history_sequential[head1])}；其余情况取 committed_history_after0。
    wire [HISTORY_BITS-1:0] committed_history_after1=(retire1&&rob_conditional[head1])?
        {committed_history_after0[HISTORY_BITS-2:0],(rob_taken[head1]&&!rob_history_sequential[head1])}:committed_history_after0;
    // recovery_second 的资格组合为 registered_pair_retire&&rob_prediction_miss[head1]。
    wire recovery_second=registered_pair_retire&&rob_prediction_miss[head1];
    // recovery_checkpoint 按 recovery_second 进行来源选择。
    // 真分支取 read_recovery_context(head1)；其余情况取 read_recovery_context(rob_head)。
    wire [HISTORY_BITS-1:0] recovery_checkpoint=recovery_second?read_recovery_context(head1):read_recovery_context(rob_head);
    // recovery_is_conditional 属于恢复边界，保存条件分支资格，决定是否需要方向预测训练。
    // recovery_is_conditional 按 recovery_second 进行来源选择。
    // 真分支取 rob_conditional[head1]；其余情况取 rob_conditional[rob_head]。
    wire recovery_is_conditional=recovery_second?rob_conditional[head1]:rob_conditional[rob_head];
    // recovery_actual_taken 属于恢复边界，保存真实或候选跳转方向，使用时须区分执行结果与预测提议。
    // recovery_actual_taken 按 recovery_second 进行来源选择。
    // 真分支取 (rob_taken[head1]&&!rob_history_sequential[head1])；其余情况取 (rob_taken[rob_head]&&!rob_history_sequential[rob_head])。
    wire recovery_actual_taken=recovery_second?(rob_taken[head1]&&!rob_history_sequential[head1]):(rob_taken[rob_head]&&!rob_history_sequential[rob_head]);
    // recovered_branch_history 保存分支历史信息，投机路径与提交路径必须保持各自归属。
    // recovered_branch_history 按 recovery_is_conditional 进行来源选择。
    // 真分支取 {recovery_checkpoint[HISTORY_BITS-2:0],recovery_actual_taken}；其余情况取 recovery_checkpoint。
    wire [HISTORY_BITS-1:0] recovered_branch_history=recovery_is_conditional?
        {recovery_checkpoint[HISTORY_BITS-2:0],recovery_actual_taken}:recovery_checkpoint;
    // recovery_history 按 (trap_enter||return_from_trap||maintain_i||maintain_d) 选择候选来源；各分支结果仍属于当前组合路径。
    // recovery_history 的资格组合为 (trap_enter||return_from_trap||maintain_i||maintain_d)?。
    assign recovery_history=(trap_enter||return_from_trap||maintain_i||maintain_d)?
        committed_history_after1:recovered_branch_history;
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&recovery&&!(trap_enter||return_from_trap||maintain_i||maintain_d))begin
        if(recovery_history!=committed_history_after1)
            $fatal(1,"R49 speculative checkpoint recovery differs from actual committed conditional history");
    end
`endif
    // debug_redirect 连接到 recovery，两者在此路径上保持字段对应。
    assign debug_redirect=recovery;
    // debug_trap 连接到 trap_enter，两者在此路径上保持字段对应。
    assign debug_trap=trap_enter;
    // The exact next-PC/prediction comparison is already registered in the ROB.
    // Event counting must use that same retirement decision, without reading
    // compressed predecessor PCs and repeating the address arithmetic here.
    // Compute registered miss-kind and pairing eligibility in parallel with
    // the current LSU hit. A current ordinary integer cannot mispredict;
    // only a registered-complete successor contributes a slot1 miss event.
    // An IRQ taken after an irrevocable retirement still counts that retire.
    wire miss_event_admit=!reset&&rob_count!=0&&(predictor_training_ready||!rob_conditional[rob_head])&&
        !(rob_done[rob_head]&&rob_fault[rob_head])&&
        !(interrupt_pending&&!lsu_irrevocable&&!ex_head_side_effect&&!prepared_side_effect);
    // miss_event_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
    // miss_event_ready 的资格组合为 (rob_done[rob_head]&&!(head_response&&data_response_fault))||head_response_success。
    wire miss_event_ready=(rob_done[rob_head]&&!(head_response&&data_response_fault))||head_response_success;
    // miss_event0 的资格组合为 rob_control[rob_head]&&rob_prediction_miss[rob_head]。
    wire miss_event0=rob_control[rob_head]&&rob_prediction_miss[rob_head];
    wire miss_event1=ENABLE_PAIRING&&rob_count>1&&(predictor_training_ready||!rob_conditional[head1])&&
        rob_system[rob_head]!=2&&rob_system[rob_head]!=1&&rob_system[rob_head]!=6&&
        !rob_prediction_miss[rob_head]&&!rob_serial[rob_head]&&
        rob_done[head1]&&!rob_fault[head1]&&!rob_serial[head1]&&
        rob_control[head1]&&rob_prediction_miss[head1];
    // debug_branch_miss 的资格组合为 miss_event_admit&&miss_event_ready&&。
    assign debug_branch_miss=miss_event_admit&&miss_event_ready&&
        ((miss_event0&&rob_conditional[rob_head])||(miss_event1&&rob_conditional[head1]));
    // debug_jump_miss 的资格组合为 miss_event_admit&&miss_event_ready&&。
    assign debug_jump_miss=miss_event_admit&&miss_event_ready&&
        ((miss_event0&&!rob_conditional[rob_head])||(miss_event1&&!rob_conditional[head1]));
`ifdef VERILATOR
    // prior_branch_miss 的资格组合为 (train0&&rob_conditional[rob_head]&&rob_prediction_miss[rob_head])|| (train1&&rob_conditional[head1]&&rob_prediction_miss[head1])。
    wire prior_branch_miss=(train0&&rob_conditional[rob_head]&&rob_prediction_miss[rob_head])||
        (train1&&rob_conditional[head1]&&rob_prediction_miss[head1]);
    // prior_jump_miss 的资格组合为 (train0&&!rob_conditional[rob_head]&&rob_prediction_miss[rob_head])|| (train1&&!rob_conditional[head1]&&rob_prediction_miss[head1])。
    wire prior_jump_miss=(train0&&!rob_conditional[rob_head]&&rob_prediction_miss[rob_head])||
        (train1&&!rob_conditional[head1]&&rob_prediction_miss[head1]);
    always @(posedge clk)if(!reset)begin
        if(debug_branch_miss!=prior_branch_miss||debug_jump_miss!=prior_jump_miss)
            $fatal(1,"R36 miss events differ from original actual retirement/training");
        if(current_second_integer&&rob_prediction_miss[head1])
            $fatal(1,"R36 ordinary current second instruction can mispredict");
    end
`endif
`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(train0&&rob_prediction_miss[rob_head]!=(read_rob_next(rob_head)!=read_rob_prediction(rob_head)))
            $fatal(1,"R14 head prediction event mismatch");
        if(train1&&rob_prediction_miss[head1]!=(read_rob_next(head1)!=read_rob_prediction(head1)))
            $fatal(1,"R14 successor prediction event mismatch");
    end
`endif
    // debug_dispatch_stall 的资格组合为 !reset&&fetch_count!=0&&allocate_count==0。
    assign debug_dispatch_stall=!reset&&fetch_count!=0&&allocate_count==0;
    // debug_frontend_stall 的资格组合为 !reset&&fetch_count==0。
    assign debug_frontend_stall=!reset&&fetch_count==0;
    // debug_rob_count 连接到 rob_count，两者在此路径上保持字段对应。
    assign debug_rob_count=rob_count;
    // debug_lsu_active 连接到 lsu_active，两者在此路径上保持字段对应。
    assign debug_lsu_active=lsu_active;
    // debug_mdu_active 连接到 mdu_active，两者在此路径上保持字段对应。
    assign debug_mdu_active=mdu_active;
    // debug_irq_pending 的资格组合为 ENABLE_TRACE&&interrupt_pending。
    assign debug_irq_pending=ENABLE_TRACE&&interrupt_pending;
    // debug_ex_valid 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_valid 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 {ex_valid1,ex_valid0}；其余情况取 2'b0。
    assign debug_ex_valid=ENABLE_TRACE?{ex_valid1,ex_valid0}:2'b0;
    // debug_ex_fault 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_fault 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 {fault1,fault0}；其余情况取 2'b0。
    assign debug_ex_fault=ENABLE_TRACE?{fault1,fault0}:2'b0;
    // debug_ex_tag0 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_tag0 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 ex_tag0；其余情况取 4'b0。
    assign debug_ex_tag0=ENABLE_TRACE?ex_tag0:4'b0;
    // debug_ex_tag1 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_tag1 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 ex_tag1；其余情况取 4'b0。
    assign debug_ex_tag1=ENABLE_TRACE?ex_tag1:4'b0;
    // debug_ex_sequence0 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_sequence0 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 ex_sequence0；其余情况取 64'b0。
    assign debug_ex_sequence0=ENABLE_TRACE?ex_sequence0:64'b0;
    // debug_ex_sequence1 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_sequence1 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 ex_sequence1；其余情况取 64'b0。
    assign debug_ex_sequence1=ENABLE_TRACE?ex_sequence1:64'b0;
    // debug_ex_pc0 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_pc0 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 ex_pc0；其余情况取 32'b0。
    assign debug_ex_pc0=ENABLE_TRACE?ex_pc0:32'b0;
    // debug_ex_pc1 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_pc1 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 ex_pc1；其余情况取 32'b0。
    assign debug_ex_pc1=ENABLE_TRACE?ex_pc1:32'b0;
    // debug_second_next 按 ENABLE_TRACE&&rob_count>1 进行来源选择。
    // 真分支取 read_rob_next(head1)；其余情况取 32'b0。
    assign debug_second_next=ENABLE_TRACE&&rob_count>1?read_rob_next(head1):32'b0;
    // debug_second_prediction 按 ENABLE_TRACE&&rob_count>1 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_second_prediction 按 ENABLE_TRACE&&rob_count>1 进行来源选择。
    // 真分支取 read_rob_prediction(head1)；其余情况取 32'b0。
    assign debug_second_prediction=ENABLE_TRACE&&rob_count>1?read_rob_prediction(head1):32'b0;
    // debug_mdu_response_pending 的资格组合为 ENABLE_TRACE&&((mdu_active&&mdu_response_valid)||mul_response_valid)。
    assign debug_mdu_response_pending=ENABLE_TRACE&&((mdu_active&&mdu_response_valid)||mul_response_valid);
    // debug_mdu_response_blocked 的资格组合为 ENABLE_TRACE&&。
    assign debug_mdu_response_blocked=ENABLE_TRACE&&
        ((mdu_active&&mdu_response_valid&&!mdu_response_ready)||(mul_response_valid&&!mul_response_ready));
    // debug_mul_request_valid 的资格组合为 ENABLE_TRACE&&mul_request。
    assign debug_mul_request_valid=ENABLE_TRACE&&mul_request;
    // debug_mul_request_ready 的资格组合为 ENABLE_TRACE&&mul_request_ready。
    assign debug_mul_request_ready=ENABLE_TRACE&&mul_request_ready;
    // debug_mul_request_tag 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_request_tag 按 ENABLE_TRACE 进行来源选择。
    assign debug_mul_request_tag=ENABLE_TRACE?ex_tag0:4'b0;
    // debug_mul_request_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_request_sequence 按 ENABLE_TRACE 进行来源选择。
    assign debug_mul_request_sequence=ENABLE_TRACE?ex_sequence0:64'b0;
    // debug_mul_request_pc 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_request_pc 按 ENABLE_TRACE 进行来源选择。
    assign debug_mul_request_pc=ENABLE_TRACE?ex_pc0:32'b0;
    // debug_mul_request_left 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_request_left 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 ex_left0；其余情况取 32'b0。
    assign debug_mul_request_left=ENABLE_TRACE?ex_left0:32'b0;
    // debug_mul_request_right 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_request_right 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 ex_right0；其余情况取 32'b0。
    assign debug_mul_request_right=ENABLE_TRACE?ex_right0:32'b0;
    // debug_mul_response_valid 的资格组合为 ENABLE_TRACE&&mul_response_valid。
    assign debug_mul_response_valid=ENABLE_TRACE&&mul_response_valid;
    // debug_mul_response_ready 的资格组合为 ENABLE_TRACE&&mul_response_ready。
    assign debug_mul_response_ready=ENABLE_TRACE&&mul_response_ready;
    // debug_mul_response_tag 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_response_tag 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 mul_response_tag；其余情况取 4'b0。
    assign debug_mul_response_tag=ENABLE_TRACE?mul_response_tag:4'b0;
    // debug_mul_response_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_response_sequence 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 rob_sequence[mul_response_tag]；其余情况取 64'b0。
    assign debug_mul_response_sequence=ENABLE_TRACE?rob_sequence[mul_response_tag]:64'b0;
    // debug_mul_response_pc 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_response_pc 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 read_rob_pc(mul_response_tag)；其余情况取 32'b0。
    assign debug_mul_response_pc=ENABLE_TRACE?read_rob_pc(mul_response_tag):32'b0;
    // debug_mul_response_value 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 mul_result；其余情况取 32'b0。
    assign debug_mul_response_value=ENABLE_TRACE?mul_result:32'b0;
    // debug_mul_occupancy 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 mul_occupancy；其余情况取 2'b0。
    assign debug_mul_occupancy=ENABLE_TRACE?mul_occupancy:2'b0;
    // debug_mul_ex_valid 的资格组合为 ENABLE_TRACE&&mul_ex_reserved。
    assign debug_mul_ex_valid=ENABLE_TRACE&&mul_ex_reserved;
    // debug_mul_ex_hold 的资格组合为 ENABLE_TRACE&&ex_hold。
    assign debug_mul_ex_hold=ENABLE_TRACE&&ex_hold;
    // debug_mul_ex_tag 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_ex_tag 按 ENABLE_TRACE 进行来源选择。
    assign debug_mul_ex_tag=ENABLE_TRACE?ex_tag0:4'b0;
    // debug_mul_ex_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_ex_sequence 按 ENABLE_TRACE 进行来源选择。
    assign debug_mul_ex_sequence=ENABLE_TRACE?ex_sequence0:64'b0;
    // debug_mul_ex_pc 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_mul_ex_pc 按 ENABLE_TRACE 进行来源选择。
    assign debug_mul_ex_pc=ENABLE_TRACE?ex_pc0:32'b0;
    // debug_legacy_request_valid 的资格组合为 ENABLE_TRACE&&mdu_request。
    assign debug_legacy_request_valid=ENABLE_TRACE&&mdu_request;
    // debug_legacy_request_ready 的资格组合为 ENABLE_TRACE&&mdu_ready。
    assign debug_legacy_request_ready=ENABLE_TRACE&&mdu_ready;
    // debug_legacy_request_tag 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_legacy_request_tag 按 ENABLE_TRACE 进行来源选择。
    assign debug_legacy_request_tag=ENABLE_TRACE?ex_tag0:4'b0;
    // debug_legacy_request_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_legacy_request_sequence 按 ENABLE_TRACE 进行来源选择。
    assign debug_legacy_request_sequence=ENABLE_TRACE?ex_sequence0:64'b0;
    // debug_legacy_request_pc 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_legacy_request_pc 按 ENABLE_TRACE 进行来源选择。
    assign debug_legacy_request_pc=ENABLE_TRACE?ex_pc0:32'b0;
    // debug_legacy_response_valid 的资格组合为 ENABLE_TRACE&&mdu_active&&mdu_response_valid。
    assign debug_legacy_response_valid=ENABLE_TRACE&&mdu_active&&mdu_response_valid;
    // debug_legacy_response_ready 的资格组合为 ENABLE_TRACE&&mdu_response_ready。
    assign debug_legacy_response_ready=ENABLE_TRACE&&mdu_response_ready;
    // debug_legacy_response_tag 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_legacy_response_tag 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 mdu_tag；其余情况取 4'b0。
    assign debug_legacy_response_tag=ENABLE_TRACE?mdu_tag:4'b0;
    // debug_legacy_response_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_legacy_response_sequence 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 mdu_sequence；其余情况取 64'b0。
    assign debug_legacy_response_sequence=ENABLE_TRACE?mdu_sequence:64'b0;
    // debug_legacy_response_pc 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_legacy_response_pc 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 mdu_pc；其余情况取 32'b0。
    assign debug_legacy_response_pc=ENABLE_TRACE?mdu_pc:32'b0;
    // debug_quarantine_active 的资格组合为 lsu_active&&lsu_killed。
    assign debug_quarantine_active=lsu_active&&lsu_killed;
    // debug_head_valid 由比较式 rob_count!=0 产生；该结果是条件判断，不是被比较的数据。
    assign debug_head_valid=rob_count!=0;
    // debug_head_sequence 按 ENABLE_TRACE&&rob_count!=0 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_head_sequence 按 ENABLE_TRACE&&rob_count!=0 进行来源选择。
    // 真分支取 rob_sequence[rob_head]；其余情况取 0。
    assign debug_head_sequence=ENABLE_TRACE&&rob_count!=0?rob_sequence[rob_head]:0;
    // debug_raw_retire_mask 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 {retire1,retire0}；其余情况取 2'b0。
    assign debug_raw_retire_mask=ENABLE_TRACE?{retire1,retire0}:2'b0;
    // debug_lsu_tag 按 direct_request 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_lsu_tag 按 direct_request 进行来源选择。
    // 真分支取 candidate_tag；其余情况取 lsu_tag。
    assign debug_lsu_tag=direct_request?candidate_tag:lsu_tag;
    // debug_lsu_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_lsu_sequence 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 (direct_request?candidate_sequence:lsu_sequence)；其余情况取 0。
    assign debug_lsu_sequence=ENABLE_TRACE?(direct_request?candidate_sequence:lsu_sequence):0;
    // debug_lsu_pc 按 direct_request 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_lsu_pc 按 direct_request 进行来源选择。
    // 真分支取 candidate_pc；其余情况取 lsu_pc。
    assign debug_lsu_pc=direct_request?candidate_pc:lsu_pc;
    // debug_lsu_irrevocable 的资格组合为 lsu_irrevocable||ex_head_side_effect||prepared_side_effect。
    assign debug_lsu_irrevocable=lsu_irrevocable||ex_head_side_effect||prepared_side_effect;
    // debug_lsu_response_tag 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_lsu_response_tag 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 lsu_tag；其余情况取 4'b0。
    assign debug_lsu_response_tag=ENABLE_TRACE?lsu_tag:4'b0;
    // debug_lsu_response_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_lsu_response_sequence 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 lsu_sequence；其余情况取 64'b0。
    assign debug_lsu_response_sequence=ENABLE_TRACE?lsu_sequence:64'b0;
    // debug_lsu_response_pc 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_lsu_response_pc 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 lsu_pc；其余情况取 32'b0。
    assign debug_lsu_response_pc=ENABLE_TRACE?lsu_pc:32'b0;
    // debug_lsu_reserved 的资格组合为 ENABLE_TRACE&&active_reserved。
    assign debug_lsu_reserved=ENABLE_TRACE&&active_reserved;
    // debug_prepared_valid 的资格组合为 ENABLE_TRACE&&prepared_valid。
    assign debug_prepared_valid=ENABLE_TRACE&&prepared_valid;
    // debug_prepared_tag 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_prepared_tag 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 prepared_tag；其余情况取 4'b0。
    assign debug_prepared_tag=ENABLE_TRACE?prepared_tag:4'b0;
    // debug_prepared_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_prepared_sequence 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 prepared_sequence；其余情况取 64'b0。
    assign debug_prepared_sequence=ENABLE_TRACE?prepared_sequence:64'b0;
    // debug_prepared_pc 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_prepared_pc 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 prepared_pc；其余情况取 32'b0。
    assign debug_prepared_pc=ENABLE_TRACE?prepared_pc:32'b0;
    // debug_ex_memory_valid 的资格组合为 ENABLE_TRACE&&ex_memory_reservation。
    assign debug_ex_memory_valid=ENABLE_TRACE&&ex_memory_reservation;
    // debug_ex_memory_tag 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_memory_tag 按 ENABLE_TRACE 进行来源选择。
    assign debug_ex_memory_tag=ENABLE_TRACE?ex_tag0:4'b0;
    // debug_ex_memory_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_memory_sequence 按 ENABLE_TRACE 进行来源选择。
    assign debug_ex_memory_sequence=ENABLE_TRACE?ex_sequence0:64'b0;
    // debug_ex_memory_pc 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    // debug_ex_memory_pc 按 ENABLE_TRACE 进行来源选择。
    assign debug_ex_memory_pc=ENABLE_TRACE?ex_pc0:32'b0;
    // debug_memory_reservations 按 ENABLE_TRACE 进行来源选择。
    // 真分支取 memory_reservations；其余情况取 2'b0。
    assign debug_memory_reservations=ENABLE_TRACE?memory_reservations:2'b0;
    assign debug_memory_credit_limit=MEMORY_CREDITS;
    assign debug_prepared_second_valid=ENABLE_TRACE&&prepared_second_valid;
    // debug_prepared_second_tag 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    assign debug_prepared_second_tag=ENABLE_TRACE?prepared_second_tag:4'b0;
    // debug_prepared_second_sequence 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    assign debug_prepared_second_sequence=ENABLE_TRACE?prepared_second_sequence:64'b0;
    // debug_prepared_second_pc 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前组合路径。
    assign debug_prepared_second_pc=ENABLE_TRACE?prepared_second_pc:32'b0;
`ifdef VERILATOR
    initial if(MEMORY_CREDITS!=2&&MEMORY_CREDITS!=3)$fatal(1,"R17 unsupported memory credit policy");
    always @(posedge clk)if(!reset)begin
        if(memory_reservations_wide>MEMORY_CREDITS||issue_memory_reservations>MEMORY_CREDITS)
            $fatal(1,"R17 memory credit overflow");
        if(prepared_second_valid&&!prepared_valid)$fatal(1,"R17 prepared FIFO hole");
        // 恢复或冲刷条件 if(!recovery&&ex_memory_reservation&&prepared_valid&&prepared_second_valid&&!active_handoff) 控制下列状态更新，旧事务的处理不能当成新请求接受。
        if(!recovery&&ex_memory_reservation&&prepared_valid&&prepared_second_valid&&!active_handoff)
            $fatal(1,"R17 EX overwrites a full prepared FIFO");
    end
`endif

    reg [11:0] eligible;
    // Legacy arrays exist only in the diagnostic global-selector elaboration.
    // ready_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [31:0] ready_left[0:11],ready_right[0:11];
    integer int_choice0,int_choice1,int_second0,int_second1,integer_first,integer_second;
    integer complex_choice,issue_choice0,issue_choice1;
    integer s;
    reg [3:0] integer_first_age,integer_second_age;
    reg [11:0] bank_issue_allowed;
    integer allow_index;
    always @* begin
        bank_issue_allowed=12'hfff;
        for(allow_index=8;allow_index<12;allow_index=allow_index+1)begin
            // The registered order/class permission is the final local gate.
            // Head, memory credit and legacy-unit credit remain current-cycle.
            bank_issue_allowed[allow_index]=memory_order_permission[allow_index]&&
                (q_error[allow_index]||
                 ((!q_serial[allow_index]||q_tag[allow_index]==rob_head)&&
                  (!q_memory[allow_index]||memory_issue_credit)&&
                  (!q_arithmetic[allow_index]||(ENABLE_MUL_STREAM&&q_multiply[allow_index])||
                   legacy_issue_credit)));
        end
    end
    // MUL_INTEGER_BOUNDARY_GATE_BEGIN
    // Keep the original order/class/credit policy and its shadow independent.
    // Only the ordered low-MUL path gets this additional readiness boundary.
    // Neither this permission nor its tag comparisons depend on raw_memory,
    // so both LSU response cases retain their early scheduling computation.
    // MUL_INTEGER_BOUNDARY 的资格组合为 ENABLE_MUL_INTEGER_BOUNDARY&& ORDERED_SCHEDULER&&ENABLE_LOCAL_MUL_OPERANDS&&ENABLE_MUL_STREAM。
    localparam MUL_INTEGER_BOUNDARY=ENABLE_MUL_INTEGER_BOUNDARY&&
        ORDERED_SCHEDULER&&ENABLE_LOCAL_MUL_OPERANDS&&ENABLE_MUL_STREAM;
    reg [11:0] scheduler_issue_allowed;
    reg [11:0] mul_integer_dependency_blocked;
    integer mul_boundary_row;
    always @*begin
        scheduler_issue_allowed=bank_issue_allowed;
        mul_integer_dependency_blocked=0;
        for(mul_boundary_row=8;mul_boundary_row<12;mul_boundary_row=mul_boundary_row+1)begin
            // q_multiply alone is only funct3==0; q_arithmetic identifies M.
            if(MUL_INTEGER_BOUNDARY&&FAST_WAKEUP&&q_valid[mul_boundary_row]&&
               q_arithmetic[mul_boundary_row]&&q_multiply[mul_boundary_row]&&!q_error[mul_boundary_row])begin
                mul_integer_dependency_blocked[mul_boundary_row]=
                    (!q_left_ready[mul_boundary_row]&&
                     ((wake0&&q_left_tag[mul_boundary_row]==ex_tag0)||
                      (early_integer1_wake&&q_left_tag[mul_boundary_row]==ex_tag1)))||
                    (!q_right_ready[mul_boundary_row]&&
                     ((wake0&&q_right_tag[mul_boundary_row]==ex_tag0)||
                      (early_integer1_wake&&q_right_tag[mul_boundary_row]==ex_tag1)));
                scheduler_issue_allowed[mul_boundary_row]=bank_issue_allowed[mul_boundary_row]&&
                    !mul_integer_dependency_blocked[mul_boundary_row];
            end
        end
    end
    // MUL_INTEGER_BOUNDARY_GATE_END
`ifdef VERILATOR
    reg [11:0] order_reference_bank_allowed;
    integer order_reference_allow_index;
    always @* begin
        order_reference_bank_allowed=12'hfff;
        for(order_reference_allow_index=8;order_reference_allow_index<12;order_reference_allow_index=order_reference_allow_index+1)begin
            if(!q_error[order_reference_allow_index])begin
                if(q_serial[order_reference_allow_index])order_reference_bank_allowed[order_reference_allow_index]=q_tag[order_reference_allow_index]==rob_head;
                if(q_memory[order_reference_allow_index])order_reference_bank_allowed[order_reference_allow_index]=order_reference_bank_allowed[order_reference_allow_index]&&
                    memory_issue_credit&&memory_order_clear_reference[order_reference_allow_index];
                if(q_arithmetic[order_reference_allow_index]&&
                   !(ENABLE_MUL_STREAM&&q_multiply[order_reference_allow_index]))
                    order_reference_bank_allowed[order_reference_allow_index]=order_reference_bank_allowed[order_reference_allow_index]&&
                    legacy_issue_credit;
            end
        end
    end
    integer order_bank_check_row;
    always @(posedge clk)if(!reset)begin
        for(order_bank_check_row=8;order_bank_check_row<12;order_bank_check_row=order_bank_check_row+1)
            if(q_valid[order_bank_check_row]&&
               bank_issue_allowed[order_bank_check_row]!=order_reference_bank_allowed[order_bank_check_row])
                $fatal(1,"TOPT6 live bank eligibility differs from original clear/class gates");
    end
`endif
    wire [11:0] ordered_eligible,ordered_mask0,ordered_mask1;
    wire [11:0] no_response_mask0,no_response_mask1,with_response_mask0,with_response_mask1;
    // ordered_valid0 属于有序调度候选，保存有效资格，标识该项是否属于当前仍可使用的事务。
    wire ordered_valid0,ordered_valid1;
    wire [3:0] ordered_slot0,ordered_slot1;
    // ordered_left0 属于有序调度候选，保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    wire [31:0] ordered_left0,ordered_right0,ordered_left1,ordered_right1;
    wire [3:0] ordered_complex_mask;
    // ordered_complex_left 属于有序调度候选，保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    wire [31:0] ordered_complex_left,ordered_complex_right;
    // ordered_left_ready 属于有序调度候选，保存左源操作数已经可用的标志，标签存在不等于值已经可用。
    wire [11:0] ordered_left_ready,ordered_right_ready,ordered_writes;
    wire [11:0] ordered_memory_good,ordered_legacy_good;
    wire [11:0] ordered_static_wakeup0,ordered_static_wakeup1;
    wire [47:0] ordered_left_tags,ordered_right_tags;
    wire [383:0] ordered_left_values,ordered_right_values;
    genvar ordered_row;
    generate for(ordered_row=0;ordered_row<12;ordered_row=ordered_row+1)begin:ordered_payload
        assign ordered_left_ready[ordered_row]=q_left_ready[ordered_row];
        assign ordered_right_ready[ordered_row]=q_right_ready[ordered_row];
        assign ordered_writes[ordered_row]=q_writes[ordered_row];
        assign ordered_static_wakeup0[ordered_row]=q_static_wakeup[ordered_row][0];
        assign ordered_static_wakeup1[ordered_row]=q_static_wakeup[ordered_row][1];
        // Decode registered row classes before the issue grant. The grant
        // reduces one-hot bits instead of encoding and re-indexing the queue.
        assign ordered_memory_good[ordered_row]=q_memory[ordered_row]&&!q_error[ordered_row];
        assign ordered_legacy_good[ordered_row]=q_arithmetic[ordered_row]&&!q_error[ordered_row]&&
            !(ENABLE_MUL_STREAM&&q_multiply[ordered_row]);
        assign ordered_left_tags[ordered_row*4+:4]=q_left_tag[ordered_row];
        assign ordered_right_tags[ordered_row*4+:4]=q_right_tag[ordered_row];
        assign ordered_left_values[ordered_row*32+:32]=q_left[ordered_row];
        assign ordered_right_values[ordered_row*32+:32]=q_right[ordered_row];
    end
    if(ORDERED_SCHEDULER)begin:relative_order_scheduler
        // 子模块 rv32_issue_scheduler 的职责：调度器根据就绪操作数 年龄与资源资格选择当前可发射的队列槽位。
        rv32_issue_scheduler #(.FAST_WAKEUP(FAST_WAKEUP),.ENABLE_PAIRING(ENABLE_PAIRING),.LATE_SELECT(1),
            .ZERO_UNREADY_OPERANDS(1),.ACTIVE_QUEUE_MASK(ACTIVE_QUEUE_MASK)) scheduler(
            .clk(clk),.reset(reset),.allocation_count(allocation_offer_count),
            .allocation_slot0(allocation_slot0[3:0]),.allocation_slot1(allocation_slot1[3:0]),
            .occupied(allocation_occupied),.issue_allowed(scheduler_issue_allowed),
            .left_ready(ordered_left_ready),.right_ready(ordered_right_ready),
            .left_tags(ordered_left_tags),.right_tags(ordered_right_tags),
            .left_values(ordered_left_values),.right_values(ordered_right_values),
            .broadcast_valid(ordered_broadcast_valid),.broadcast_tags(ordered_broadcast_tags),.broadcast_values(ordered_broadcast_values),
            .late_select(raw_memory),.alternate_valid0(no_response_wake),.alternate_tags0(no_response_tags),
            .alternate_valid1(with_response_wake),.alternate_tags1(with_response_tags),
            .ex_hold(ex_hold),.eligible(ordered_eligible),.issue_mask0(ordered_mask0),.issue_mask1(ordered_mask1),
            .case0_mask0(no_response_mask0),.case0_mask1(no_response_mask1),
            .case1_mask0(with_response_mask0),.case1_mask1(with_response_mask1),
            .issue_valid0(ordered_valid0),.issue_valid1(ordered_valid1),.issue_slot0(ordered_slot0),.issue_slot1(ordered_slot1),
            .issue_left0(ordered_left0),.issue_right0(ordered_right0),.issue_left1(ordered_left1),.issue_right1(ordered_right1),
            .complex_candidate_mask(ordered_complex_mask),
            .complex_candidate_left(ordered_complex_left),.complex_candidate_right(ordered_complex_right));
    end else begin:no_ordered_complex_payload
        assign ordered_complex_mask=4'b0;
        assign ordered_complex_left=32'b0;assign ordered_complex_right=32'b0;
    end endgenerate
    // RV32: select already-read metadata after the cache response bit,
    // instead of response -> grant -> encoded ROB tag -> ROB read ports.
    // no_response_tag0 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    reg [3:0] no_response_tag0,no_response_tag1,with_response_tag0,with_response_tag1;
    // no_response_control0 保存控制流类别或控制位，供目标选择和分支结果处理使用。
    reg [6:0] no_response_control0,no_response_control1,with_response_control0,with_response_control1;
    reg [15:0] no_response_alu0,no_response_alu1,with_response_alu0,with_response_alu1;
    // no_response_pc0 保存指令地址，供退休记录及异常恢复定位。
    reg [31:0] no_response_pc0,no_response_pc1,with_response_pc0,with_response_pc1;
    // no_response_instruction0 保存原始指令编码，和该条指令的 PC 及身份同行保存。
    reg [31:0] no_response_instruction0,no_response_instruction1,with_response_instruction0,with_response_instruction1;
    integer tag_row;
    always @*begin
        no_response_tag0=0;no_response_tag1=0;with_response_tag0=0;with_response_tag1=0;
        no_response_control0=0;no_response_control1=0;with_response_control0=0;with_response_control1=0;
        no_response_alu0=0;no_response_alu1=0;with_response_alu0=0;with_response_alu1=0;
        no_response_pc0=0;no_response_pc1=0;with_response_pc0=0;with_response_pc1=0;
        no_response_instruction0=0;no_response_instruction1=0;with_response_instruction0=0;with_response_instruction1=0;
        for(tag_row=0;tag_row<12;tag_row=tag_row+1)begin
            // Prepare both readiness cases from registered per-entry bits.
            // The late cache-response bit only selects their completed muxes.
            no_response_pc0=no_response_pc0|({32{no_response_mask0[tag_row]}}&q_pc[tag_row]);
            no_response_pc1=no_response_pc1|({32{no_response_mask1[tag_row]}}&q_pc[tag_row]);
            with_response_pc0=with_response_pc0|({32{with_response_mask0[tag_row]}}&q_pc[tag_row]);
            with_response_pc1=with_response_pc1|({32{with_response_mask1[tag_row]}}&q_pc[tag_row]);
            no_response_instruction0=no_response_instruction0|({32{no_response_mask0[tag_row]}}&q_instruction[tag_row]);
            no_response_instruction1=no_response_instruction1|({32{no_response_mask1[tag_row]}}&q_instruction[tag_row]);
            with_response_instruction0=with_response_instruction0|({32{with_response_mask0[tag_row]}}&q_instruction[tag_row]);
            with_response_instruction1=with_response_instruction1|({32{with_response_mask1[tag_row]}}&q_instruction[tag_row]);
            no_response_alu0=no_response_alu0|({16{no_response_mask0[tag_row]}}&q_alu_control[tag_row]);
            no_response_alu1=no_response_alu1|({16{no_response_mask1[tag_row]}}&q_alu_control[tag_row]);
            with_response_alu0=with_response_alu0|({16{with_response_mask0[tag_row]}}&q_alu_control[tag_row]);
            with_response_alu1=with_response_alu1|({16{with_response_mask1[tag_row]}}&q_alu_control[tag_row]);
            no_response_tag0=no_response_tag0|({4{no_response_mask0[tag_row]}}&q_tag[tag_row]);
            no_response_tag1=no_response_tag1|({4{no_response_mask1[tag_row]}}&q_tag[tag_row]);
            with_response_tag0=with_response_tag0|({4{with_response_mask0[tag_row]}}&q_tag[tag_row]);
            with_response_tag1=with_response_tag1|({4{with_response_mask1[tag_row]}}&q_tag[tag_row]);
            no_response_control0=no_response_control0|({7{no_response_mask0[tag_row]}}&
                {q_control_meta[tag_row][4],q_control_meta[tag_row][3]||q_error[tag_row],
                 q_control_meta[tag_row][2:0],q_arithmetic[tag_row],q_memory[tag_row]});
            no_response_control1=no_response_control1|({7{no_response_mask1[tag_row]}}&
                {q_control_meta[tag_row][4],q_control_meta[tag_row][3]||q_error[tag_row],
                 q_control_meta[tag_row][2:0],q_arithmetic[tag_row],q_memory[tag_row]});
            with_response_control0=with_response_control0|({7{with_response_mask0[tag_row]}}&
                {q_control_meta[tag_row][4],q_control_meta[tag_row][3]||q_error[tag_row],
                 q_control_meta[tag_row][2:0],q_arithmetic[tag_row],q_memory[tag_row]});
            with_response_control1=with_response_control1|({7{with_response_mask1[tag_row]}}&
                {q_control_meta[tag_row][4],q_control_meta[tag_row][3]||q_error[tag_row],
                 q_control_meta[tag_row][2:0],q_arithmetic[tag_row],q_memory[tag_row]});
        end
    end
    // ordered_tag0 属于有序调度候选，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // ordered_tag0 按 raw_memory 进行来源选择。
    // 真分支取 with_response_tag0；其余情况取 no_response_tag0。
    wire [3:0] ordered_tag0=raw_memory?with_response_tag0:no_response_tag0;
    // ordered_tag1 属于有序调度候选，保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // ordered_tag1 按 raw_memory 进行来源选择。
    // 真分支取 with_response_tag1；其余情况取 no_response_tag1。
    wire [3:0] ordered_tag1=raw_memory?with_response_tag1:no_response_tag1;
    // ordered_control0 属于有序调度候选，保存控制流类别或控制位，供目标选择和分支结果处理使用。
    // ordered_control0 按 raw_memory 进行来源选择。
    // 真分支取 with_response_control0；其余情况取 no_response_control0。
    wire [6:0] ordered_control0=raw_memory?with_response_control0:no_response_control0;
    // ordered_control1 属于有序调度候选，保存控制流类别或控制位，供目标选择和分支结果处理使用。
    // ordered_control1 按 raw_memory 进行来源选择。
    // 真分支取 with_response_control1；其余情况取 no_response_control1。
    wire [6:0] ordered_control1=raw_memory?with_response_control1:no_response_control1;
    // ordered_alu_control0 属于有序调度候选，保存控制流类别或控制位，供目标选择和分支结果处理使用。
    wire [31:0] ordered_alu_control0=unpack_queue_alu_control(
        raw_memory?with_response_alu0:no_response_alu0);
    // ordered_alu_control1 属于有序调度候选，保存控制流类别或控制位，供目标选择和分支结果处理使用。
    wire [31:0] ordered_alu_control1=unpack_queue_alu_control(
        raw_memory?with_response_alu1:no_response_alu1);
    // legacy_ordered_pc0 保存指令地址，供退休记录及异常恢复定位。
    // legacy_ordered_pc0 按 raw_memory 进行来源选择。
    // 真分支取 read_rob_pc(with_response_tag0)；其余情况取 read_rob_pc(no_response_tag0)。
    wire [31:0] legacy_ordered_pc0=raw_memory?read_rob_pc(with_response_tag0):read_rob_pc(no_response_tag0);
    // legacy_ordered_pc1 保存指令地址，供退休记录及异常恢复定位。
    // legacy_ordered_pc1 按 raw_memory 进行来源选择。
    // 真分支取 read_rob_pc(with_response_tag1)；其余情况取 read_rob_pc(no_response_tag1)。
    wire [31:0] legacy_ordered_pc1=raw_memory?read_rob_pc(with_response_tag1):read_rob_pc(no_response_tag1);
    // legacy_ordered_instruction0 保存原始指令编码，和该条指令的 PC 及身份同行保存。
    // legacy_ordered_instruction0 按 raw_memory 进行来源选择。
    // 真分支取 read_rob_instruction(with_response_tag0)；其余情况取 read_rob_instruction(no_response_tag0)。
    wire [31:0] legacy_ordered_instruction0=raw_memory?read_rob_instruction(with_response_tag0):read_rob_instruction(no_response_tag0);
    // legacy_ordered_instruction1 保存原始指令编码，和该条指令的 PC 及身份同行保存。
    // legacy_ordered_instruction1 按 raw_memory 进行来源选择。
    // 真分支取 read_rob_instruction(with_response_tag1)；其余情况取 read_rob_instruction(no_response_tag1)。
    wire [31:0] legacy_ordered_instruction1=raw_memory?read_rob_instruction(with_response_tag1):read_rob_instruction(no_response_tag1);
    // Select each response case directly from registered row payload first.
    // The cache-response bit is only the final 2:1 data selection. A zero
    // mask has no issue owner, so its zero payload is intentionally unchecked.
    // ordered_pc0 属于有序调度候选，保存指令地址，供退休记录及异常恢复定位。
    // ordered_pc0 按 ENABLE_QUEUED_EXEC_PAYLOAD 进行来源选择。
    // 真分支取 (raw_memory?with_response_pc0:no_response_pc0)；其余情况取 legacy_ordered_pc0。
    wire [31:0] ordered_pc0=ENABLE_QUEUED_EXEC_PAYLOAD?
        (raw_memory?with_response_pc0:no_response_pc0):legacy_ordered_pc0;
    // ordered_pc1 属于有序调度候选，保存指令地址，供退休记录及异常恢复定位。
    // ordered_pc1 按 ENABLE_QUEUED_EXEC_PAYLOAD 进行来源选择。
    // 真分支取 (raw_memory?with_response_pc1:no_response_pc1)；其余情况取 legacy_ordered_pc1。
    wire [31:0] ordered_pc1=ENABLE_QUEUED_EXEC_PAYLOAD?
        (raw_memory?with_response_pc1:no_response_pc1):legacy_ordered_pc1;
    // ordered_instruction0 属于有序调度候选，保存原始指令编码，和该条指令的 PC 及身份同行保存。
    // ordered_instruction0 按 ENABLE_QUEUED_EXEC_PAYLOAD 进行来源选择。
    // 真分支取 (raw_memory?with_response_instruction0:no_response_instruction0)；其余情况取 legacy_ordered_instruction0。
    wire [31:0] ordered_instruction0=ENABLE_QUEUED_EXEC_PAYLOAD?
        (raw_memory?with_response_instruction0:no_response_instruction0):legacy_ordered_instruction0;
    // ordered_instruction1 属于有序调度候选，保存原始指令编码，和该条指令的 PC 及身份同行保存。
    // ordered_instruction1 按 ENABLE_QUEUED_EXEC_PAYLOAD 进行来源选择。
    // 真分支取 (raw_memory?with_response_instruction1:no_response_instruction1)；其余情况取 legacy_ordered_instruction1。
    wire [31:0] ordered_instruction1=ENABLE_QUEUED_EXEC_PAYLOAD?
        (raw_memory?with_response_instruction1:no_response_instruction1):legacy_ordered_instruction1;
`ifdef VERILATOR
    integer execution_payload_row;
    always @(posedge clk)if(!reset&&ENABLE_QUEUED_EXEC_PAYLOAD)begin
        for(execution_payload_row=0;execution_payload_row<12;execution_payload_row=execution_payload_row+1)
            if(q_valid[execution_payload_row])begin
                if(q_pc[execution_payload_row]!=read_rob_pc(q_tag[execution_payload_row]))
                    $fatal(1,"TOPT4 queued PC lost its live ROB owner");
                if(q_instruction[execution_payload_row]!=read_rob_instruction(q_tag[execution_payload_row]))
                    $fatal(1,"TOPT4 queued instruction lost its live ROB owner");
            end
        if(ORDERED_SCHEDULER)begin
            if(ordered_valid0&&(ordered_pc0!=legacy_ordered_pc0||ordered_instruction0!=legacy_ordered_instruction0))
                $fatal(1,"TOPT4 first queued execution payload differs from legacy ROB read");
            if(ordered_valid1&&(ordered_pc1!=legacy_ordered_pc1||ordered_instruction1!=legacy_ordered_instruction1))
                $fatal(1,"TOPT4 second queued execution payload differs from legacy ROB read");
        end
    end
    always @(posedge clk)if(!reset&&ORDERED_SCHEDULER)begin
        if(ordered_valid0&&(ordered_pc0!=read_rob_pc(ordered_tag0)||ordered_instruction0!=read_rob_instruction(ordered_tag0)))
            $fatal(1,"RV32 first early issue metadata differs from selected live ROB owner");
        if(ordered_valid1&&(ordered_pc1!=read_rob_pc(ordered_tag1)||ordered_instruction1!=read_rob_instruction(ordered_tag1)))
            $fatal(1,"RV32 second early issue metadata differs from selected live ROB owner");
    end
`endif
    // 按调度选择的物理槽位取得生产者标签，使结果仍可追溯到 ROB。
    function [3:0] issue_tag_value;
        input integer choice;
        begin
            if(ORDERED_SCHEDULER)issue_tag_value=choice==issue_choice0?ordered_tag0:ordered_tag1;
            else issue_tag_value=q_tag[choice];
        end
    endfunction
    // 取得候选的目的写资格，x0 和无目的寄存器指令不能获得普通写回。
    function issue_write_value;
        input integer choice;
        begin
            if(ORDERED_SCHEDULER)issue_write_value=choice==issue_choice0?
                (|(ordered_mask0&ordered_writes)):(|(ordered_mask1&ordered_writes));
            else issue_write_value=q_writes[choice];
        end
    endfunction
    wire [11:0] bank_eligible;
    // bank_first_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    wire [2:0] bank_first_valid,bank_second_valid;
    // bank_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    wire [2:0] bank_count[0:2];
    wire [1:0] bank_first_slot[0:2],bank_second_slot[0:2];
    wire [3:0] bank_first_age[0:2],bank_second_age[0:2];
    // bank_first_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    wire [31:0] bank_first_left[0:2],bank_first_right[0:2],bank_second_left[0:2],bank_second_right[0:2];
    genvar bank,entry;
    generate for(bank=0;bank<3;bank=bank+1)begin:issue_banks
        wire [3:0] occupied,left_ready,right_ready;
        wire [15:0] ages,left_tags,right_tags;
        wire [127:0] left_values,right_values;
        for(entry=0;entry<4;entry=entry+1)begin:local_operands
            assign occupied[entry]=q_valid[bank*4+entry];
            assign ages[entry*4+:4]=q_tag[bank*4+entry]-rob_head;
            assign left_ready[entry]=q_left_ready[bank*4+entry];
            assign right_ready[entry]=q_right_ready[bank*4+entry];
            assign left_tags[entry*4+:4]=q_left_tag[bank*4+entry];
            assign right_tags[entry*4+:4]=q_right_tag[bank*4+entry];
            assign left_values[entry*32+:32]=q_left[bank*4+entry];
            assign right_values[entry*32+:32]=q_right[bank*4+entry];
        end
        // 子模块 rv32_issue_bank 的职责：局部发射 bank 接收已占有的队列行和操作数就绪信息，提出局部候选。
        rv32_issue_bank #(.FAST_WAKEUP(FAST_WAKEUP)) scheduler_bank(
            .occupied(occupied),.issue_allowed(bank_issue_allowed[bank*4+:4]),.ages(ages),
            .left_ready(left_ready),.right_ready(right_ready),.left_tags(left_tags),.right_tags(right_tags),
            .left_values(left_values),.right_values(right_values),
            .broadcast_valid(queue_broadcast_valid),
            .broadcast_tags(queue_broadcast_tags),
            .broadcast_values(queue_broadcast_values),
            .eligible(bank_eligible[bank*4+:4]),.occupancy_count(bank_count[bank]),
            .first_valid(bank_first_valid[bank]),.second_valid(bank_second_valid[bank]),
            .first_slot(bank_first_slot[bank]),.second_slot(bank_second_slot[bank]),
            .first_age(bank_first_age[bank]),.second_age(bank_second_age[bank]),
            .first_left(bank_first_left[bank]),.first_right(bank_first_right[bank]),
            .second_left(bank_second_left[bank]),.second_right(bank_second_right[bank]));
    end endgenerate
    generate if(ORDERED_SCHEDULER)begin:ordered_selection
        always @*begin
            eligible=ordered_eligible;
            debug_iq0_count={2'b0,q_valid[0]}+{2'b0,q_valid[1]}+{2'b0,q_valid[2]}+{2'b0,q_valid[3]};
            debug_iq1_count={2'b0,q_valid[4]}+{2'b0,q_valid[5]}+{2'b0,q_valid[6]}+{2'b0,q_valid[7]};
            debug_complex_count={2'b0,q_valid[8]}+{2'b0,q_valid[9]}+{2'b0,q_valid[10]}+{2'b0,q_valid[11]};
            int_choice0=-1;int_choice1=-1;int_second0=-1;int_second1=-1;complex_choice=-1;
            for(s=0;s<12;s=s+1)begin ready_left[s]=0;ready_right[s]=0;end
        end
    end else if(BANKED_ISSUE)begin:local_selection
        always @* begin
            eligible=bank_eligible;
            debug_iq0_count=bank_count[0];debug_iq1_count=bank_count[1];debug_complex_count=bank_count[2];
            int_choice0=bank_first_valid[0]?{30'b0,bank_first_slot[0]}:-1;
            int_second0=bank_second_valid[0]?{30'b0,bank_second_slot[0]}:-1;
            int_choice1=bank_first_valid[1]?{28'b0,2'b01,bank_first_slot[1]}:-1;
            int_second1=bank_second_valid[1]?{28'b0,2'b01,bank_second_slot[1]}:-1;
            complex_choice=bank_first_valid[2]?{28'b0,2'b10,bank_first_slot[2]}:-1;
            for(s=0;s<12;s=s+1)begin ready_left[s]=0;ready_right[s]=0;end
        end
    end else begin:legacy_selection
    always @* begin
        debug_iq0_count=0;debug_iq1_count=0;debug_complex_count=0;
        eligible=0;int_choice0=-1;int_choice1=-1;int_second0=-1;int_second1=-1;
        complex_choice=-1;
        for(s=0;s<12;s=s+1)begin
            ready_left[s]=q_left[s];ready_right[s]=q_right[s];
            if(FAST_WAKEUP&&!q_left_ready[s]&&broadcast_available(q_left_tag[s]))ready_left[s]=broadcast_value(q_left_tag[s]);
            if(FAST_WAKEUP&&!q_right_ready[s]&&broadcast_available(q_right_tag[s]))ready_right[s]=broadcast_value(q_right_tag[s]);
            if(q_valid[s])begin
                if(s<4)debug_iq0_count=debug_iq0_count+1'b1;
                else if(s<8)debug_iq1_count=debug_iq1_count+1'b1;
                else debug_complex_count=debug_complex_count+1'b1;
                eligible[s]=(q_left_ready[s]||(FAST_WAKEUP&&broadcast_available(q_left_tag[s])))&&
                            (q_right_ready[s]||(FAST_WAKEUP&&broadcast_available(q_right_tag[s])));
                if(s>=8&&!q_error[s])begin
                    if(q_serial[s])eligible[s]=eligible[s]&&q_tag[s]==rob_head;
                    if(q_memory[s])eligible[s]=eligible[s]&&memory_issue_credit&&memory_order_permission[s];
                    if(q_arithmetic[s]&&
                       !(ENABLE_MUL_STREAM&&q_multiply[s]))
                        eligible[s]=eligible[s]&&
                        legacy_issue_credit;
                end
                if(eligible[s])begin
                    if(s<4)begin
                        if(int_choice0<0||age(q_tag[s])<age(q_tag[(int_choice0<0 ? 4'd0 : int_choice0[3:0])]))begin
                            int_second0=int_choice0;int_choice0=s;
                        end else if(int_second0<0||age(q_tag[s])<age(q_tag[(int_second0<0 ? 4'd0 : int_second0[3:0])]))int_second0=s;
                    end else if(s<8)begin
                        if(int_choice1<0||age(q_tag[s])<age(q_tag[(int_choice1<0 ? 4'd0 : int_choice1[3:0])]))begin
                            int_second1=int_choice1;int_choice1=s;
                        end else if(int_second1<0||age(q_tag[s])<age(q_tag[(int_second1<0 ? 4'd0 : int_second1[3:0])]))int_second1=s;
                    end
                    else begin if(complex_choice<0||age(q_tag[s])<age(q_tag[(complex_choice<0 ? 4'd0 : complex_choice[3:0])]))complex_choice=s;end
                end
            end
        end
    end
    end endgenerate
    // age_choice0 按 BANKED_ISSUE 进行来源选择。
    // 真分支取 bank_first_age[0]；其余情况取 (int_choice0<0?4'b0:age(q_tag[(int_choice0<0 ? 4'd0 : int_choice0[3:0])]))。
    wire [3:0] age_choice0=BANKED_ISSUE?bank_first_age[0]:(int_choice0<0?4'b0:age(q_tag[(int_choice0<0 ? 4'd0 : int_choice0[3:0])]));
    // age_choice1 按 BANKED_ISSUE 进行来源选择。
    // 真分支取 bank_first_age[1]；其余情况取 (int_choice1<0?4'b0:age(q_tag[(int_choice1<0 ? 4'd0 : int_choice1[3:0])]))。
    wire [3:0] age_choice1=BANKED_ISSUE?bank_first_age[1]:(int_choice1<0?4'b0:age(q_tag[(int_choice1<0 ? 4'd0 : int_choice1[3:0])]));
    // age_second0 按 BANKED_ISSUE 进行来源选择。
    // 真分支取 bank_second_age[0]；其余情况取 (int_second0<0?4'b0:age(q_tag[(int_second0<0 ? 4'd0 : int_second0[3:0])]))。
    wire [3:0] age_second0=BANKED_ISSUE?bank_second_age[0]:(int_second0<0?4'b0:age(q_tag[(int_second0<0 ? 4'd0 : int_second0[3:0])]));
    // age_second1 按 BANKED_ISSUE 进行来源选择。
    // 真分支取 bank_second_age[1]；其余情况取 (int_second1<0?4'b0:age(q_tag[(int_second1<0 ? 4'd0 : int_second1[3:0])]))。
    wire [3:0] age_second1=BANKED_ISSUE?bank_second_age[1]:(int_second1<0?4'b0:age(q_tag[(int_second1<0 ? 4'd0 : int_second1[3:0])]));
    // age_complex 按 BANKED_ISSUE 进行来源选择。
    // 真分支取 bank_first_age[2]；其余情况取 (complex_choice<0?4'b0:age(q_tag[(complex_choice<0 ? 4'd0 : complex_choice[3:0])]))。
    wire [3:0] age_complex=BANKED_ISSUE?bank_first_age[2]:(complex_choice<0?4'b0:age(q_tag[(complex_choice<0 ? 4'd0 : complex_choice[3:0])]));
    // Only local first/second operands leave each four-entry bank. The global
    // stage arbitrates bank candidates; it does not index twelve operand rows.
    // 读取已选槽位的左操作数，并保留与该槽位一致的身份关系。
    function [31:0] issue_left_value;
        input integer choice;
        begin
            if(choice<0)issue_left_value=0;
            else if(ORDERED_SCHEDULER)issue_left_value=choice==issue_choice0?ordered_left0:ordered_left1;
            else if(!BANKED_ISSUE)issue_left_value=ready_left[choice];
            else if(choice>=8)issue_left_value=bank_first_left[2];
            else if(choice>=4)issue_left_value=choice==int_choice1?bank_first_left[1]:bank_second_left[1];
            else issue_left_value=choice==int_choice0?bank_first_left[0]:bank_second_left[0];
        end
    endfunction
    // 读取已选槽位的右操作数，和左操作数及控制字段组成同一执行包。
    function [31:0] issue_right_value;
        input integer choice;
        begin
            if(choice<0)issue_right_value=0;
            else if(ORDERED_SCHEDULER)issue_right_value=choice==issue_choice0?ordered_right0:ordered_right1;
            else if(!BANKED_ISSUE)issue_right_value=ready_right[choice];
            else if(choice>=8)issue_right_value=bank_first_right[2];
            else if(choice>=4)issue_right_value=choice==int_choice1?bank_first_right[1]:bank_second_right[1];
            else issue_right_value=choice==int_choice0?bank_first_right[0]:bank_second_right[0];
        end
    endfunction
    generate if(ORDERED_SCHEDULER)begin:ordered_global_choice
        always @*begin
            integer_first=-1;integer_second=-1;integer_first_age=0;integer_second_age=0;
            issue_choice0=ordered_valid0?{28'b0,ordered_slot0}:-1;
            issue_choice1=ordered_valid1?{28'b0,ordered_slot1}:-1;
        end
    end else begin:legacy_global_choice
    always @* begin
        integer_first=-1;integer_second=-1;issue_choice0=-1;issue_choice1=-1;
        integer_first_age=0;integer_second_age=0;
        // Merge the local top-two sets, rather than repeat a flat queue scan.
        integer_first=int_choice0;integer_first_age=age_choice0;
        if(int_choice1>=0&&(integer_first<0||age_choice1<integer_first_age))begin integer_first=int_choice1;integer_first_age=age_choice1;end
        if(integer_first==int_choice0)begin
            integer_second=int_second0;integer_second_age=age_second0;
            if(int_choice1>=0&&(integer_second<0||age_choice1<integer_second_age))begin integer_second=int_choice1;integer_second_age=age_choice1;end
        end else begin
            integer_second=int_second1;integer_second_age=age_second1;
            if(int_choice0>=0&&(integer_second<0||age_choice0<integer_second_age))begin integer_second=int_choice0;integer_second_age=age_choice0;end
        end
        if(!reset)begin
            if(ENABLE_STEALING)begin
                if(ENABLE_PAIRING)begin
                    // Assign the oldest compatible set. Complex must use EX0;
                    // the older integer may therefore correctly use EX1.
                    if(complex_choice>=0&&(integer_second<0||age_complex<integer_second_age))begin
                        issue_choice0=complex_choice;issue_choice1=integer_first;
                    end else begin issue_choice0=integer_first;issue_choice1=integer_second;end
                end else begin
                    issue_choice0=integer_first;
                    if(complex_choice>=0&&(integer_first<0||age_complex<integer_first_age))issue_choice0=complex_choice;
                end
                if(ex_hold)begin
                    issue_choice0=-1;
                    if(ENABLE_PAIRING)issue_choice1=integer_first;
                end
            end else begin
                issue_choice0=int_choice0;
                if(complex_choice>=0&&(int_choice0<0||age_complex<age_choice0))issue_choice0=complex_choice;
                if(ENABLE_PAIRING)issue_choice1=int_choice1;
                else if(issue_choice0<0)issue_choice0=int_choice1;
                if(ex_hold)issue_choice0=-1;
            end
        end
    end

    end endgenerate

    // Resource selection reads registered queue occupancy only. Released
    // slots become visible after the edge, independently of current wakeup,
    // issue selection, LSU response, arithmetic arbitration and recovery.
    // resource_valid0 保存有效资格，标识该项是否属于当前仍可使用的事务。
    wire resource_valid0,resource_valid1;
    wire [3:0] resource_slot0,resource_slot1;
    genvar qindex;
    generate for(qindex=0;qindex<12;qindex=qindex+1)begin:registered_resources
        assign allocation_occupied[qindex]=q_valid[qindex];
    end endgenerate
    // Disabled slots are occupied only to the allocator, never to issue.
    // resource_occupied 对 allocation_occupied|~ACTIVE_QUEUE_MASK 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [11:0] resource_occupied=allocation_occupied|~ACTIVE_QUEUE_MASK;
    // 子模块 rv32_queue_allocator 的职责：分配器根据物理槽位占用和指令类别为至多两条新指令选择位置。
    rv32_queue_allocator queue_resources(
        .occupied(resource_occupied),.complex0(d_complex0),.complex1(d_complex1),.steer(steer),
        .valid0(resource_valid0),.valid1(resource_valid1),.slot0(resource_slot0),.slot1(resource_slot1));

    // Diagnostic legacy mode only. The normal allocator has no issue input.
    // The execution registers sample old issued-slot fields on this edge.
    // Later allocation writes replace that slot for the following cycle.
    function integer free_queue_slot;
        input complex_operation,preferred_bank;
        input integer excluded;
        integer k;
        begin
            free_queue_slot=-1;
            if(complex_operation)begin
                for(k=11;k>=8;k=k-1)if(ACTIVE_QUEUE_MASK[k]&&(!q_valid[k]||(ENABLE_SAME_CYCLE_REUSE&&(issue_choice0==k||issue_choice1==k)))&&k!=excluded)free_queue_slot=k;
            end else begin
                // Prefer the less occupied local bank; use the other if full.
                for(k=7;k>=0;k=k-1)if(ACTIVE_QUEUE_MASK[k]&&(!q_valid[k]||(ENABLE_SAME_CYCLE_REUSE&&(issue_choice0==k||issue_choice1==k)))&&k!=excluded)free_queue_slot=k;
                if(preferred_bank)begin
                    for(k=7;k>=4;k=k-1)if(ACTIVE_QUEUE_MASK[k]&&(!q_valid[k]||(ENABLE_SAME_CYCLE_REUSE&&(issue_choice0==k||issue_choice1==k)))&&k!=excluded)free_queue_slot=k;
                end else begin
                    for(k=3;k>=0;k=k-1)if(ACTIVE_QUEUE_MASK[k]&&(!q_valid[k]||(ENABLE_SAME_CYCLE_REUSE&&(issue_choice0==k||issue_choice1==k)))&&k!=excluded)free_queue_slot=k;
                end
            end
        end
    endfunction
    // 把源寄存器映射为可用值或等待中的生产者标签，保留数据有效标识。
    function [32:0] source_value;
        input [4:0] number;
        input used;
        reg [31:0] committed;
        begin
            committed=read_register(number);
            // A retiring writer is still renamed until this edge. Its
            // registered ROB value is selected below; unrenamed reads use RF.
            if(!used||number==0)source_value={1'b1,32'b0};
            else if(!map_valid[number])source_value={1'b1,committed};
            else source_value={producer_available(map_tag[number]),producer_value(map_tag[number])};
        end
    endfunction
    integer allocation_slot0,allocation_slot1;
    reg preferred0,preferred1;
    // allocation_left0 属于新分配候选，保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [32:0] allocation_left0,allocation_right0,allocation_left1,allocation_right1;
    reg [3:0] allocation_ltag0,allocation_rtag0,allocation_ltag1,allocation_rtag1;
    always @* begin
        allocation_left0=source_value(d_rs10,d_use10&&!d_bad0&&!fetch_error0);
        allocation_right0=source_value(d_rs20,d_use20&&!d_bad0&&!fetch_error0);
        allocation_left1=source_value(d_rs11,d_use11&&!d_bad1&&!fetch_error1);
        allocation_right1=source_value(d_rs21,d_use21&&!d_bad1&&!fetch_error1);
        allocation_ltag0=map_tag[d_rs10];allocation_rtag0=map_tag[d_rs20];
        allocation_ltag1=map_tag[d_rs11];allocation_rtag1=map_tag[d_rs21];
        if(d_write0&&d_rd0!=0)begin
            if(d_use11&&d_rs11==d_rd0&&!d_bad1&&!fetch_error1)begin allocation_left1[32]=0;allocation_ltag1=rob_tail;end
            if(d_use21&&d_rs21==d_rd0&&!d_bad1&&!fetch_error1)begin allocation_right1[32]=0;allocation_rtag1=rob_tail;end
        end
    end
    // Capacity and slot proposals depend only on registered occupancy and the
    // current decoded bundle. Recovery is applied at final acceptance above;
    // it does not drive wide initialization enables in the decoupled mode.
    always @* begin
        allocation_offer_count=0;allocation_slot0=-1;allocation_slot1=-1;
        preferred0=debug_iq1_count<debug_iq0_count?1'b1:debug_iq0_count<debug_iq1_count?1'b0:steer;
        preferred1=preferred0;
        // 恢复或冲刷条件 if(!reset&&(DECOUPLED_ALLOCATION_PAYLOAD||!recovery)&&!serial_pending&&fetch_count!=0&&rob_count<16&& 控制下列状态更新，旧事务的处理不能当成新请求接受。
        if(!reset&&(DECOUPLED_ALLOCATION_PAYLOAD||!recovery)&&!serial_pending&&fetch_count!=0&&rob_count<16&&
            (!d_serial0||(rob_count==0&&!lsu_active&&!mdu_active&&mul_occupancy==0&&!ex_valid0&&!ex_valid1)))begin
            if(ENABLE_SAME_CYCLE_REUSE)allocation_slot0=free_queue_slot(d_complex0,preferred0,-1);
            else if(resource_valid0)allocation_slot0={28'b0,resource_slot0};
            if(allocation_slot0>=0)begin
                allocation_offer_count=1;
                if(!d_complex0)preferred1=allocation_slot0<4;
                if(ENABLE_PAIRING&&!d_serial0&&!d_serial1&&fetch_count>1&&rob_count<15&&fetch_pc1==fetch_prediction0)begin
                    if(ENABLE_SAME_CYCLE_REUSE)allocation_slot1=free_queue_slot(d_complex1,preferred1,allocation_slot0);
                    else if(resource_valid1)allocation_slot1={28'b0,resource_slot1};
                    if(allocation_slot1>=0)allocation_offer_count=2;
                end
            end
        end
    end

    // TOPT: preserve the scheduler's lane identity through its consumers.
    // Validity and one-hot grants are already known; encoding a slot merely
    // to recover them adds a reconvergent path into dispatch and EX enables.
    // The encoded choices remain available for trace and legacy policies.
    // issue_present0 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_valid0；其余情况取 (issue_choice0>=0)。
    wire issue_present0=ORDERED_SCHEDULER?ordered_valid0:(issue_choice0>=0);
    // issue_present1 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_valid1；其余情况取 (issue_choice1>=0)。
    wire issue_present1=ORDERED_SCHEDULER?ordered_valid1:(issue_choice1>=0);
    // issue_payload_tag0 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // issue_payload_tag0 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_tag0；其余情况取 issue_tag_value(issue_present0?issue_choice0:0)。
    wire [3:0] issue_payload_tag0=ORDERED_SCHEDULER?ordered_tag0:issue_tag_value(issue_present0?issue_choice0:0);
    // issue_payload_tag1 保存生产者或事务标签，用于把结果匹配到正确的所有者。
    // issue_payload_tag1 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_tag1；其余情况取 issue_tag_value(issue_present1?issue_choice1:0)。
    wire [3:0] issue_payload_tag1=ORDERED_SCHEDULER?ordered_tag1:issue_tag_value(issue_present1?issue_choice1:0);
    // issue_payload_writes0 保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    // issue_payload_writes0 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 (|(ordered_mask0&ordered_writes))；其余情况取 issue_write_value(issue_present0?issue_choice0:0)。
    wire issue_payload_writes0=ORDERED_SCHEDULER?(|(ordered_mask0&ordered_writes)):issue_write_value(issue_present0?issue_choice0:0);
    // issue_payload_writes1 保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
    // issue_payload_writes1 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 (|(ordered_mask1&ordered_writes))；其余情况取 issue_write_value(issue_present1?issue_choice1:0)。
    wire issue_payload_writes1=ORDERED_SCHEDULER?(|(ordered_mask1&ordered_writes)):issue_write_value(issue_present1?issue_choice1:0);
    // issue_payload_left0 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // issue_payload_left0 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_left0；其余情况取 issue_left_value(issue_choice0)。
    wire [31:0] issue_payload_left0=ORDERED_SCHEDULER?ordered_left0:issue_left_value(issue_choice0);
    // issue_payload_right0 保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    // issue_payload_right0 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_right0；其余情况取 issue_right_value(issue_choice0)。
    wire [31:0] issue_payload_right0=ORDERED_SCHEDULER?ordered_right0:issue_right_value(issue_choice0);
    // issue_payload_left1 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // issue_payload_left1 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_left1；其余情况取 issue_left_value(issue_choice1)。
    wire [31:0] issue_payload_left1=ORDERED_SCHEDULER?ordered_left1:issue_left_value(issue_choice1);
    // issue_payload_right1 保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    // issue_payload_right1 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_right1；其余情况取 issue_right_value(issue_choice1)。
    wire [31:0] issue_payload_right1=ORDERED_SCHEDULER?ordered_right1:issue_right_value(issue_choice1);
    wire issue_legacy0=ORDERED_SCHEDULER?(|(ordered_mask0&ordered_legacy_good)):
        (issue_present0&&q_arithmetic[issue_present0?issue_choice0:0]&&
         !q_error[issue_present0?issue_choice0:0]&&
         !(ENABLE_MUL_STREAM&&q_multiply[issue_present0?issue_choice0:0]));

    // 在分配旁路路径判断源操作数可用性，不能因寄存器有旧值就忽略重命名依赖。
    function dispatch_source_ready;
        input [4:0] number;
        input used;
        begin dispatch_source_ready=!used||number==0||!map_valid[number];end
    endfunction
    // 为分配直达执行路径读取正确的架构值或可用生产者值。
    function [31:0] dispatch_register_value;
        input [4:0] number;
        input used;
        begin dispatch_register_value=(!used||number==0)?32'b0:read_register(number);end
    endfunction
    // dispatch_ready0 属于分配直达执行路径，保存接收或操作数就绪资格，须结合对应的有效位使用。
    // dispatch_ready0 的资格组合为 dispatch_source_ready(d_rs10,d_use10)&&dispatch_source_ready(d_rs20,d_use20)。
    wire dispatch_ready0=dispatch_source_ready(d_rs10,d_use10)&&dispatch_source_ready(d_rs20,d_use20);
    // bundle_raw1 的资格组合为 d_write0&&d_rd0!=0&&((d_use11&&d_rs11==d_rd0)||(d_use21&&d_rs21==d_rd0))。
    wire bundle_raw1=d_write0&&d_rd0!=0&&((d_use11&&d_rs11==d_rd0)||(d_use21&&d_rs21==d_rd0));
    // dispatch_ready1 属于分配直达执行路径，保存接收或操作数就绪资格，须结合对应的有效位使用。
    // dispatch_ready1 的资格组合为 !bundle_raw1&&dispatch_source_ready(d_rs11,d_use11)&&dispatch_source_ready(d_rs21,d_use21)。
    wire dispatch_ready1=!bundle_raw1&&dispatch_source_ready(d_rs11,d_use11)&&dispatch_source_ready(d_rs21,d_use21);
    // dispatch_left0 属于分配直达执行路径，保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // dispatch_left0 按 DISPATCH_BYPASS_UNMAPPED_ONLY 进行来源选择。
    // 真分支取 dispatch_register_value(d_rs10,d_use10)；其余情况取 allocation_left0[31:0]。
    wire [31:0] dispatch_left0=DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_register_value(d_rs10,d_use10):allocation_left0[31:0];
    // dispatch_right0 属于分配直达执行路径，保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    // dispatch_right0 按 DISPATCH_BYPASS_UNMAPPED_ONLY 进行来源选择。
    // 真分支取 dispatch_register_value(d_rs20,d_use20)；其余情况取 allocation_right0[31:0]。
    wire [31:0] dispatch_right0=DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_register_value(d_rs20,d_use20):allocation_right0[31:0];
    // dispatch_left1 属于分配直达执行路径，保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // dispatch_left1 按 DISPATCH_BYPASS_UNMAPPED_ONLY 进行来源选择。
    // 真分支取 dispatch_register_value(d_rs11,d_use11)；其余情况取 allocation_left1[31:0]。
    wire [31:0] dispatch_left1=DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_register_value(d_rs11,d_use11):allocation_left1[31:0];
    // dispatch_right1 属于分配直达执行路径，保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    // dispatch_right1 按 DISPATCH_BYPASS_UNMAPPED_ONLY 进行来源选择。
    // 真分支取 dispatch_register_value(d_rs21,d_use21)；其余情况取 allocation_right1[31:0]。
    wire [31:0] dispatch_right1=DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_register_value(d_rs21,d_use21):allocation_right1[31:0];
    // Allocation admission and queued issue stay independent of this path.
    // A new ready integer may fill only a genuinely unused next EX register.
    // It still reserves a queue slot, then discards that transient reservation.
    wire bypass_candidate0=allocation_offer_count!=0&&dispatch_integer_class(fetch_instruction0)&&
        !d_bad0&&!fetch_error0&&!d_complex0&&fetch_pc_dispatch_ok0&&(DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_ready0:(allocation_left0[32]&&allocation_right0[32]));
    wire bypass_candidate1=allocation_offer_count==2&&dispatch_integer_class(fetch_instruction1)&&
        !d_bad1&&!fetch_error1&&!d_complex1&&fetch_pc_dispatch_ok1&&(DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_ready1:(allocation_left1[32]&&allocation_right1[32]));
    integer dispatch_ex0,dispatch_ex1,b;
    reg unselected_ready_integer;
    always @* begin
        dispatch_ex0=-1;dispatch_ex1=-1;unselected_ready_integer=0;
        // Include all old integer-queue classes, including control and faults.
        // In the ordered policy the grants themselves identify each winner.
        if(ORDERED_SCHEDULER)
            unselected_ready_integer=|(eligible[7:0]&~(ordered_mask0[7:0]|ordered_mask1[7:0]));
        else for(b=0;b<8;b=b+1)
            if(eligible[b]&&issue_choice0!=b&&issue_choice1!=b)unselected_ready_integer=1;
        if(ENABLE_DISPATCH_BYPASS&&!reset&&(ORDERED_SCHEDULER||!unselected_ready_integer))begin
            if(bypass_candidate0)begin
                if(!issue_present0&&!ex_hold)dispatch_ex0=0;
                else if(ENABLE_PAIRING&&!issue_present1)dispatch_ex1=0;
            end
            if(bypass_candidate1)begin
                if(!issue_present0&&!ex_hold&&dispatch_ex0<0)dispatch_ex0=1;
                else if(ENABLE_PAIRING&&!issue_present1&&dispatch_ex1<0)dispatch_ex1=1;
            end
        end
    end

`ifdef VERILATOR
    // Compare against the original encoded-choice consumers on every live
    // grant, including response wakeup, EX hold, and recovery proposal edges.
    // TOPT2: a maximal compatible issue set leaves a dispatch-eligible
    // lane free only when every ready integer was issued. Retain the old
    // admission as an independent reference; enable/reset/hold are included.
    integer reference_dispatch_ex0,reference_dispatch_ex1;
    always @*begin
        reference_dispatch_ex0=-1;reference_dispatch_ex1=-1;
        if(ENABLE_DISPATCH_BYPASS&&!reset&&!unselected_ready_integer)begin
            if(bypass_candidate0)begin
                if(!issue_present0&&!ex_hold)reference_dispatch_ex0=0;
                else if(ENABLE_PAIRING&&!issue_present1)reference_dispatch_ex1=0;
            end
            if(bypass_candidate1)begin
                if(!issue_present0&&!ex_hold&&reference_dispatch_ex0<0)reference_dispatch_ex0=1;
                else if(ENABLE_PAIRING&&!issue_present1&&reference_dispatch_ex1<0)reference_dispatch_ex1=1;
            end
        end
    end
    always @(posedge clk)begin
        if(dispatch_ex0!=reference_dispatch_ex0||dispatch_ex1!=reference_dispatch_ex1)
            $fatal(1,"TOPT2 direct dispatch admission differs from original leftover-integer guard");
    end
    reg reference_unselected_ready_integer;
    integer reference_issue_row;
    always @*begin
        reference_unselected_ready_integer=0;
        for(reference_issue_row=0;reference_issue_row<8;reference_issue_row=reference_issue_row+1)
            if(eligible[reference_issue_row]&&issue_choice0!=reference_issue_row&&issue_choice1!=reference_issue_row)
                reference_unselected_ready_integer=1;
    end
    always @(posedge clk)if(!reset&&ORDERED_SCHEDULER)begin
        if(issue_present0!=(issue_choice0>=0)||issue_present1!=(issue_choice1>=0)||
           unselected_ready_integer!=reference_unselected_ready_integer)
            $fatal(1,"TOPT one-hot issue admission differs from encoded-choice reference");
        if((ordered_mask0&(ordered_mask0-12'd1))!=0||
           (ordered_mask1&(ordered_mask1-12'd1))!=0||(ordered_mask0&ordered_mask1)!=0)
            $fatal(1,"TOPT ordered issue masks are not disjoint one-hot-or-zero grants");
        if(issue_present0&&(issue_payload_tag0!=issue_tag_value(issue_choice0)||
            issue_payload_writes0!=issue_write_value(issue_choice0)||
            issue_payload_left0!=issue_left_value(issue_choice0)||issue_payload_right0!=issue_right_value(issue_choice0)))
            $fatal(1,"TOPT lane 0 direct payload differs from encoded-choice reference");
        if(issue_present1&&(issue_payload_tag1!=issue_tag_value(issue_choice1)||
            issue_payload_writes1!=issue_write_value(issue_choice1)||
            issue_payload_left1!=issue_left_value(issue_choice1)||issue_payload_right1!=issue_right_value(issue_choice1)))
            $fatal(1,"TOPT lane 1 direct payload differs from encoded-choice reference");
        if(entering_memory!=((issue_choice0>=0)&&q_memory[issue_choice0>=0?issue_choice0:0]&&
            !q_error[issue_choice0>=0?issue_choice0:0]))
            $fatal(1,"TOPT one-hot memory admission differs from encoded-choice reference");
        if(issue_legacy0!=((issue_choice0>=0)&&q_arithmetic[issue_choice0>=0?issue_choice0:0]&&
            !q_error[issue_choice0>=0?issue_choice0:0]&&
            !(ENABLE_MUL_STREAM&&q_multiply[issue_choice0>=0?issue_choice0:0])))
            $fatal(1,"TOPT one-hot legacy-MDU admission differs from encoded-choice reference");
    end
`endif

    // TOPT2: local complex-bank operands are captured at the SAME edge as
    // the existing EX payload. They may be overwritten on an integer/bubble
    // cycle: only a low-MUL owner consumes them. A blocked MUL holds them with
    // the existing EX packet. This separates DSP operand preparation from
    // the 12-entry global selection and from integer dispatch bypass.
    // MUL_INTEGER_BOUNDARY_PAYLOAD_BEGIN
    // Private DSP data has no integer result bus input in the boundary mode,
    // including on non-MUL cycles. Masking a full forwarded value only when
    // MUL is valid would leave an ALU path in this continuously sampled D cone.
    // Live unready q_* data is already zero under the existing queue contract.
    // mul_boundary_stored_left 属于低位乘法路径，保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [31:0] mul_boundary_stored_left,mul_boundary_stored_right;
    // mul_boundary_lsu_left 属于低位乘法路径，保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg mul_boundary_lsu_left,mul_boundary_lsu_right;
    integer mul_operand_row;
    always @*begin
        mul_boundary_stored_left=0;mul_boundary_stored_right=0;
        mul_boundary_lsu_left=0;mul_boundary_lsu_right=0;
        for(mul_operand_row=8;mul_operand_row<12;mul_operand_row=mul_operand_row+1)begin
            mul_boundary_stored_left=mul_boundary_stored_left|
                ({32{ordered_complex_mask[mul_operand_row-8]}}&q_left[mul_operand_row]);
            mul_boundary_stored_right=mul_boundary_stored_right|
                ({32{ordered_complex_mask[mul_operand_row-8]}}&q_right[mul_operand_row]);
            mul_boundary_lsu_left=mul_boundary_lsu_left||
                (ordered_complex_mask[mul_operand_row-8]&&!q_left_ready[mul_operand_row]&&
                 FAST_WAKEUP&&raw_memory&&early_memory_wake&&q_left_tag[mul_operand_row]==lsu_tag);
            mul_boundary_lsu_right=mul_boundary_lsu_right||
                (ordered_complex_mask[mul_operand_row-8]&&!q_right_ready[mul_operand_row]&&
                 FAST_WAKEUP&&raw_memory&&early_memory_wake&&q_right_tag[mul_operand_row]==lsu_tag);
        end
    end
    // mul_boundary_left 属于低位乘法路径，保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // mul_boundary_left 对 mul_boundary_stored_left| ({32{mul_boundary_lsu_left}}&lsu_result) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [31:0] mul_boundary_left=mul_boundary_stored_left|
        ({32{mul_boundary_lsu_left}}&lsu_result);
    // mul_boundary_right 属于低位乘法路径，保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    // mul_boundary_right 对 mul_boundary_stored_right| ({32{mul_boundary_lsu_right}}&lsu_result) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [31:0] mul_boundary_right=mul_boundary_stored_right|
        ({32{mul_boundary_lsu_right}}&lsu_result);
    // MUL_INTEGER_BOUNDARY_PAYLOAD_END
    always @(posedge clk)begin
        if(reset)begin ex_mul_left_local<=0;ex_mul_right_local<=0;end
        else if(!ex_hold)begin
            ex_mul_left_local<=MUL_INTEGER_BOUNDARY?mul_boundary_left:ordered_complex_left;
            ex_mul_right_local<=MUL_INTEGER_BOUNDARY?mul_boundary_right:ordered_complex_right;
        end
    end
`ifdef VERILATOR
    // Admission, rather than the private data mux, must guarantee that every
    // issued low-MUL operand is either stored or supplied by the actual LSU.
    integer mul_boundary_check_row;
    always @(posedge clk)if(!reset&&MUL_INTEGER_BOUNDARY)begin
        for(mul_boundary_check_row=8;mul_boundary_check_row<12;mul_boundary_check_row=mul_boundary_check_row+1)
            if(ordered_mask0[mul_boundary_check_row]&&q_arithmetic[mul_boundary_check_row]&&
               q_multiply[mul_boundary_check_row]&&!q_error[mul_boundary_check_row])begin
                if((!q_left_ready[mul_boundary_check_row]&&
                    !(FAST_WAKEUP&&raw_memory&&early_memory_wake&&q_left_tag[mul_boundary_check_row]==lsu_tag))||
                   (!q_right_ready[mul_boundary_check_row]&&
                    !(FAST_WAKEUP&&raw_memory&&early_memory_wake&&q_right_tag[mul_boundary_check_row]==lsu_tag)))
                    $fatal(1,"MUL boundary admitted an operand without stored or LSU data");
            end
    end
    always @(posedge clk)if(!reset&&ENABLE_LOCAL_MUL_OPERANDS&&ORDERED_SCHEDULER&&mul_ex_reserved)begin
        if(ex_mul_left_local!=ex_left0||ex_mul_right_local!=ex_right0)
            $fatal(1,"TOPT2 local DSP operands differ from live or held low-MUL owner");
    end
`endif

    // TOPT: the scheduler's four operand outputs are zero when their lane
    // has no grant. Queued issue and allocation bypass are mutually exclusive
    // on each lane. Their masked OR can therefore feed the operand registers
    // continuously, without putting late issue selection on a 128-bit CE.
    // TOPT6 applies the same private-payload contract to the queued
    // PC/instruction path below, when that path is known to be zero on a bubble.
    // stream_left0 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // stream_left0 由比较式 issue_payload_left0 | ({32{dispatch_ex0==0}}&dispatch_left0) | ({32{dispatch_ex0==1}}&dispatch_left1) 产生；该结果是条件判断，不是被比较的数据。
    wire [31:0] stream_left0=issue_payload_left0 |
        ({32{dispatch_ex0==0}}&dispatch_left0) | ({32{dispatch_ex0==1}}&dispatch_left1);
    // stream_right0 保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    // stream_right0 由比较式 issue_payload_right0 | ({32{dispatch_ex0==0}}&dispatch_right0) | ({32{dispatch_ex0==1}}&dispatch_right1) 产生；该结果是条件判断，不是被比较的数据。
    wire [31:0] stream_right0=issue_payload_right0 |
        ({32{dispatch_ex0==0}}&dispatch_right0) | ({32{dispatch_ex0==1}}&dispatch_right1);
    // stream_left1 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    // stream_left1 由比较式 issue_payload_left1 | ({32{dispatch_ex1==0}}&dispatch_left0) | ({32{dispatch_ex1==1}}&dispatch_left1) 产生；该结果是条件判断，不是被比较的数据。
    wire [31:0] stream_left1=issue_payload_left1 |
        ({32{dispatch_ex1==0}}&dispatch_left0) | ({32{dispatch_ex1==1}}&dispatch_left1);
    // stream_right1 保存右源操作数值，其依赖和有效性与左操作数分别跟踪。
    // stream_right1 由比较式 issue_payload_right1 | ({32{dispatch_ex1==0}}&dispatch_right0) | ({32{dispatch_ex1==1}}&dispatch_right1) 产生；该结果是条件判断，不是被比较的数据。
    wire [31:0] stream_right1=issue_payload_right1 |
        ({32{dispatch_ex1==0}}&dispatch_right0) | ({32{dispatch_ex1==1}}&dispatch_right1);
    always @(posedge clk)begin
        if(reset)begin
            ex_left0<=0;ex_right0<=0;ex_left1<=0;ex_right1<=0;
        end else if(ENABLE_EX_OPERAND_STREAM)begin
            if(!ex_hold)begin ex_left0<=stream_left0;ex_right0<=stream_right0;end
            ex_left1<=stream_left1;ex_right1<=stream_right1;
        end else begin
            // Diagnostic switch: identical valid-qualified capture to B4.
            if(dispatch_ex0>=0)begin
                // ex_left0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_left0<=dispatch_ex0==0?dispatch_left0:dispatch_left1;
                // ex_right0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_right0<=dispatch_ex0==0?dispatch_right0:dispatch_right1;
            end
            if(dispatch_ex1>=0)begin
                // ex_left1 按 dispatch_ex1==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_left1<=dispatch_ex1==0?dispatch_left0:dispatch_left1;
                // ex_right1 按 dispatch_ex1==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_right1<=dispatch_ex1==0?dispatch_right0:dispatch_right1;
            end
            if(issue_present0)begin ex_left0<=issue_payload_left0;ex_right0<=issue_payload_right0;end
            if(issue_present1)begin ex_left1<=issue_payload_left1;ex_right1<=issue_payload_right1;end
        end
    end
`ifdef VERILATOR
    // reference_ex_left0 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [31:0] reference_ex_left0,reference_ex_right0,reference_ex_left1,reference_ex_right1;
    always @(posedge clk)begin
        if(reset)begin
            reference_ex_left0<=0;reference_ex_right0<=0;
            reference_ex_left1<=0;reference_ex_right1<=0;
        end else begin
            // Independent held-payload reference follows the original priority.
            if(ex_valid0&&{ex_left0,ex_right0}!={reference_ex_left0,reference_ex_right0})
                $fatal(1,"TOPT streamed EX0 operands differ from held-payload reference");
            if(ex_valid1&&{ex_left1,ex_right1}!={reference_ex_left1,reference_ex_right1})
                $fatal(1,"TOPT streamed EX1 operands differ from held-payload reference");
            if((issue_present0&&dispatch_ex0>=0)||(issue_present1&&dispatch_ex1>=0))
                $fatal(1,"TOPT queued issue and dispatch overlap on the same lane");
            if((!issue_present0&&{issue_payload_left0,issue_payload_right0}!=64'b0)||
               (!issue_present1&&{issue_payload_left1,issue_payload_right1}!=64'b0))
                $fatal(1,"TOPT ungranted queued operands are not zero");
            if(dispatch_ex0>=0)begin
                // reference_ex_left0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                reference_ex_left0<=dispatch_ex0==0?dispatch_left0:dispatch_left1;
                // reference_ex_right0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                reference_ex_right0<=dispatch_ex0==0?dispatch_right0:dispatch_right1;
            end
            if(dispatch_ex1>=0)begin
                // reference_ex_left1 按 dispatch_ex1==0 选择候选来源；各分支结果仍属于当前寄存边界。
                reference_ex_left1<=dispatch_ex1==0?dispatch_left0:dispatch_left1;
                // reference_ex_right1 按 dispatch_ex1==0 选择候选来源；各分支结果仍属于当前寄存边界。
                reference_ex_right1<=dispatch_ex1==0?dispatch_right0:dispatch_right1;
            end
            if(issue_present0)begin reference_ex_left0<=issue_payload_left0;reference_ex_right0<=issue_payload_right0;end
            if(issue_present1)begin reference_ex_left1<=issue_payload_left1;reference_ex_right1<=issue_payload_right1;end
        end
    end
`endif

    // TOPT6 B: prepare dispatch metadata before the final queue/dispatch mux.
    // These existing private registers capture without issue-valid CE.
    // Bubble values may differ; every live owner keeps its original source.
    // Recovery still clears validity in the original owner block; private
    // payload sampling does not allocate, retire, or accept an instruction.
    // STREAM_EXEC_METADATA 的资格组合为 ENABLE_EX_METADATA_STREAM&& ORDERED_SCHEDULER&&ENABLE_QUEUED_EXEC_PAYLOAD。
    localparam STREAM_EXEC_METADATA=ENABLE_EX_METADATA_STREAM&&
        ORDERED_SCHEDULER&&ENABLE_QUEUED_EXEC_PAYLOAD;
    // stream_pc0 保存指令地址，供退休记录及异常恢复定位。
    // stream_pc0 按 issue_present0 进行来源选择。
    // 真分支取 ordered_pc0；其余情况取 (bypass_candidate0?fetch_pc0:fetch_pc1)。
    wire [31:0] stream_pc0=issue_present0?ordered_pc0:
        (bypass_candidate0?fetch_pc0:fetch_pc1);
    // stream_instruction0 保存原始指令编码，和该条指令的 PC 及身份同行保存。
    // stream_instruction0 按 issue_present0 进行来源选择。
    // 真分支取 ordered_instruction0；其余情况取 (bypass_candidate0?fetch_instruction0:fetch_instruction1)。
    wire [31:0] stream_instruction0=issue_present0?ordered_instruction0:
        (bypass_candidate0?fetch_instruction0:fetch_instruction1);
    // stream_pc1 保存指令地址，供退休记录及异常恢复定位。
    // stream_pc1 按 issue_present1 进行来源选择。
    // 真分支取 ordered_pc1；其余情况取 ((bypass_candidate0&&(issue_present0||ex_hold))?fetch_pc0:fetch_pc1)。
    wire [31:0] stream_pc1=issue_present1?ordered_pc1:
        ((bypass_candidate0&&(issue_present0||ex_hold))?fetch_pc0:fetch_pc1);
    // stream_instruction1 保存原始指令编码，和该条指令的 PC 及身份同行保存。
    // stream_instruction1 按 issue_present1 进行来源选择。
    // 真分支取 ordered_instruction1；其余情况取 ((bypass_candidate0&&(issue_present0||ex_hold))?fetch_instruction0:fetch_instruction1)。
    wire [31:0] stream_instruction1=issue_present1?ordered_instruction1:
        ((bypass_candidate0&&(issue_present0||ex_hold))?fetch_instruction0:fetch_instruction1);
    always @(posedge clk)begin
        if(reset)begin
            ex_instruction0<=0;ex_instruction1<=0;ex_pc0<=RESET_VECTOR;ex_pc1<=RESET_VECTOR;
        end else if(STREAM_EXEC_METADATA)begin
            // EX0 ownership can persist while the low-MUL request is held.
            if(!ex_hold)begin ex_pc0<=stream_pc0;ex_instruction0<=stream_instruction0;end
            ex_pc1<=stream_pc1;ex_instruction1<=stream_instruction1;
        end else begin
            // Exact original dispatch-then-issue priority in diagnostic modes.
            if(dispatch_ex0>=0)begin
                // ex_pc0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_pc0<=dispatch_ex0==0?fetch_pc0:fetch_pc1;
                // ex_instruction0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_instruction0<=dispatch_ex0==0?fetch_instruction0:fetch_instruction1;
            end
            if(dispatch_ex1>=0)begin
                // ex_pc1 按 dispatch_ex1==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_pc1<=dispatch_ex1==0?fetch_pc0:fetch_pc1;
                // ex_instruction1 按 dispatch_ex1==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_instruction1<=dispatch_ex1==0?fetch_instruction0:fetch_instruction1;
            end
            if(issue_present0)begin ex_pc0<=ORDERED_SCHEDULER?ordered_pc0:read_rob_pc(issue_payload_tag0);ex_instruction0<=ORDERED_SCHEDULER?ordered_instruction0:read_rob_instruction(issue_payload_tag0); end
            if(issue_present1)begin ex_pc1<=ORDERED_SCHEDULER?ordered_pc1:read_rob_pc(issue_payload_tag1);ex_instruction1<=ORDERED_SCHEDULER?ordered_instruction1:read_rob_instruction(issue_payload_tag1); end
        end
    end
`ifdef VERILATOR
    // t6_reference_ex_pc0 保存指令地址，供退休记录及异常恢复定位。
    reg [31:0] t6_reference_ex_pc0,t6_reference_ex_pc1;
    // t6_reference_ex_instruction0 保存原始指令编码，和该条指令的 PC 及身份同行保存。
    reg [31:0] t6_reference_ex_instruction0,t6_reference_ex_instruction1;
    always @(posedge clk)begin
        if(reset)begin
            t6_reference_ex_instruction0<=0;t6_reference_ex_instruction1<=0;t6_reference_ex_pc0<=RESET_VECTOR;t6_reference_ex_pc1<=RESET_VECTOR;
        end else begin
            if(ex_valid0&&{ex_pc0,ex_instruction0}!=
                {t6_reference_ex_pc0,t6_reference_ex_instruction0})
                $fatal(1,"TOPT6 streamed EX0 metadata differs from original live/held owner");
            if(ex_valid1&&{ex_pc1,ex_instruction1}!=
                {t6_reference_ex_pc1,t6_reference_ex_instruction1})
                $fatal(1,"TOPT6 streamed EX1 metadata differs from original live owner");
            if(STREAM_EXEC_METADATA)begin
                if((!issue_present0&&{ordered_pc0,ordered_instruction0}!=64'b0)||
                   (!issue_present1&&{ordered_pc1,ordered_instruction1}!=64'b0))
                    $fatal(1,"TOPT6 ungranted queued metadata must be zero before masked OR");
                if((issue_present0&&dispatch_ex0>=0)||(issue_present1&&dispatch_ex1>=0))
                    $fatal(1,"TOPT6 queued and dispatch metadata owners overlap");
                if(ex_hold&&(issue_present0||dispatch_ex0>=0))
                    $fatal(1,"TOPT6 held EX0 received a new metadata owner");
            end
            if(dispatch_ex0>=0)begin
                // t6_reference_ex_pc0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                t6_reference_ex_pc0<=dispatch_ex0==0?fetch_pc0:fetch_pc1;
                // t6_reference_ex_instruction0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                t6_reference_ex_instruction0<=dispatch_ex0==0?fetch_instruction0:fetch_instruction1;
            end
            if(dispatch_ex1>=0)begin
                // t6_reference_ex_pc1 按 dispatch_ex1==0 选择候选来源；各分支结果仍属于当前寄存边界。
                t6_reference_ex_pc1<=dispatch_ex1==0?fetch_pc0:fetch_pc1;
                // t6_reference_ex_instruction1 按 dispatch_ex1==0 选择候选来源；各分支结果仍属于当前寄存边界。
                t6_reference_ex_instruction1<=dispatch_ex1==0?fetch_instruction0:fetch_instruction1;
            end
            if(issue_present0)begin t6_reference_ex_pc0<=ORDERED_SCHEDULER?ordered_pc0:read_rob_pc(issue_payload_tag0);t6_reference_ex_instruction0<=ORDERED_SCHEDULER?ordered_instruction0:read_rob_instruction(issue_payload_tag0); end
            if(issue_present1)begin t6_reference_ex_pc1<=ORDERED_SCHEDULER?ordered_pc1:read_rob_pc(issue_payload_tag1);t6_reference_ex_instruction1<=ORDERED_SCHEDULER?ordered_instruction1:read_rob_instruction(issue_payload_tag1); end
        end
    end
`endif

    // Payload may be prepared in a free slot even when recovery cancels its
    // proposal. Only accepted entries gain validity or rename ownership.
    // 为指定物理发射行初始化身份 操作数 译码和错误信息，动态槽位仍受有效掩码约束。
    task initialize_allocation_payload;
        input [3:0] tag;
        input integer qs;
        // pc 保存指令地址，供退休记录及异常恢复定位。
        input [31:0] pc,instruction,prediction,alu_control;
        // fetch_error 属于取指与分配边界，保存访问或译码错误标志，不能被正常数据值掩盖。
        input fetch_error,writes,memory_operation,store_operation,arithmetic_operation,serial_operation,complex_operation,decode_error;
        // destination 保存目的架构寄存器编号，必须和结果所有者同时核对。
        input [4:0] destination;
        input [32:0] left_value,right_value;
        // left_tag 保存左源操作数所等待的生产者标签，供广播唤醒匹配。
        input [3:0] left_tag,right_tag;
        input [63:0] sequence_number;
        begin
            rob_history_sequential[tag]<=({instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0}==13'd4);
            rob_writes[tag]<=writes;
            rob_memory[tag]<=memory_operation;rob_store[tag]<=store_operation;rob_arithmetic[tag]<=arithmetic_operation;
            rob_serial[tag]<=serial_operation;rob_complex[tag]<=complex_operation;rob_decode_error[tag]<=decode_error;
            rob_fetch_error[tag]<=fetch_error;
            // rob_fetch_page_fault[tag] 按 tag==rob_tail 选择候选来源；各分支结果仍属于当前寄存边界。
            rob_fetch_page_fault[tag]<=tag==rob_tail?fetch_page_fault0:fetch_page_fault1;
            rob_destination[tag]<=destination;
            // rob_sequence[tag] 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
            rob_sequence[tag]<=ENABLE_TRACE?sequence_number:0;
            // Constant row guards eliminate disabled payload registers.
            if(ACTIVE_QUEUE_MASK[0]&&qs==0)begin
                q_tag[0]<=tag;q_left_ready[0]<=left_value[32];q_right_ready[0]<=right_value[32];
                q_pc[0]<=pc;q_instruction[0]<=instruction;
                q_writes[0]<=writes&&destination!=0;q_error[0]<=fetch_error||decode_error;
                q_static_wakeup[0]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[0]<=serial_operation;q_memory[0]<=memory_operation;
                q_arithmetic[0]<=arithmetic_operation;q_multiply[0]<=instruction[14:12]==0;
                q_store[0]<=store_operation;
                q_control_meta[0]<=immutable_control_metadata(instruction,pc);
                q_alu_control[0]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[0] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[0]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[0] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[0]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[0]<=left_tag;q_right_tag[0]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[1]&&qs==1)begin
                q_tag[1]<=tag;q_left_ready[1]<=left_value[32];q_right_ready[1]<=right_value[32];
                q_pc[1]<=pc;q_instruction[1]<=instruction;
                q_writes[1]<=writes&&destination!=0;q_error[1]<=fetch_error||decode_error;
                q_static_wakeup[1]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[1]<=serial_operation;q_memory[1]<=memory_operation;
                q_arithmetic[1]<=arithmetic_operation;q_multiply[1]<=instruction[14:12]==0;
                q_store[1]<=store_operation;
                q_control_meta[1]<=immutable_control_metadata(instruction,pc);
                q_alu_control[1]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[1] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[1]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[1] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[1]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[1]<=left_tag;q_right_tag[1]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[2]&&qs==2)begin
                q_tag[2]<=tag;q_left_ready[2]<=left_value[32];q_right_ready[2]<=right_value[32];
                q_pc[2]<=pc;q_instruction[2]<=instruction;
                q_writes[2]<=writes&&destination!=0;q_error[2]<=fetch_error||decode_error;
                q_static_wakeup[2]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[2]<=serial_operation;q_memory[2]<=memory_operation;
                q_arithmetic[2]<=arithmetic_operation;q_multiply[2]<=instruction[14:12]==0;
                q_store[2]<=store_operation;
                q_control_meta[2]<=immutable_control_metadata(instruction,pc);
                q_alu_control[2]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[2] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[2]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[2] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[2]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[2]<=left_tag;q_right_tag[2]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[3]&&qs==3)begin
                q_tag[3]<=tag;q_left_ready[3]<=left_value[32];q_right_ready[3]<=right_value[32];
                q_pc[3]<=pc;q_instruction[3]<=instruction;
                q_writes[3]<=writes&&destination!=0;q_error[3]<=fetch_error||decode_error;
                q_static_wakeup[3]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[3]<=serial_operation;q_memory[3]<=memory_operation;
                q_arithmetic[3]<=arithmetic_operation;q_multiply[3]<=instruction[14:12]==0;
                q_store[3]<=store_operation;
                q_control_meta[3]<=immutable_control_metadata(instruction,pc);
                q_alu_control[3]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[3] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[3]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[3] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[3]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[3]<=left_tag;q_right_tag[3]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[4]&&qs==4)begin
                q_tag[4]<=tag;q_left_ready[4]<=left_value[32];q_right_ready[4]<=right_value[32];
                q_pc[4]<=pc;q_instruction[4]<=instruction;
                q_writes[4]<=writes&&destination!=0;q_error[4]<=fetch_error||decode_error;
                q_static_wakeup[4]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[4]<=serial_operation;q_memory[4]<=memory_operation;
                q_arithmetic[4]<=arithmetic_operation;q_multiply[4]<=instruction[14:12]==0;
                q_store[4]<=store_operation;
                q_control_meta[4]<=immutable_control_metadata(instruction,pc);
                q_alu_control[4]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[4] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[4]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[4] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[4]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[4]<=left_tag;q_right_tag[4]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[5]&&qs==5)begin
                q_tag[5]<=tag;q_left_ready[5]<=left_value[32];q_right_ready[5]<=right_value[32];
                q_pc[5]<=pc;q_instruction[5]<=instruction;
                q_writes[5]<=writes&&destination!=0;q_error[5]<=fetch_error||decode_error;
                q_static_wakeup[5]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[5]<=serial_operation;q_memory[5]<=memory_operation;
                q_arithmetic[5]<=arithmetic_operation;q_multiply[5]<=instruction[14:12]==0;
                q_store[5]<=store_operation;
                q_control_meta[5]<=immutable_control_metadata(instruction,pc);
                q_alu_control[5]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[5] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[5]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[5] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[5]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[5]<=left_tag;q_right_tag[5]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[6]&&qs==6)begin
                q_tag[6]<=tag;q_left_ready[6]<=left_value[32];q_right_ready[6]<=right_value[32];
                q_pc[6]<=pc;q_instruction[6]<=instruction;
                q_writes[6]<=writes&&destination!=0;q_error[6]<=fetch_error||decode_error;
                q_static_wakeup[6]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[6]<=serial_operation;q_memory[6]<=memory_operation;
                q_arithmetic[6]<=arithmetic_operation;q_multiply[6]<=instruction[14:12]==0;
                q_store[6]<=store_operation;
                q_control_meta[6]<=immutable_control_metadata(instruction,pc);
                q_alu_control[6]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[6] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[6]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[6] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[6]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[6]<=left_tag;q_right_tag[6]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[7]&&qs==7)begin
                q_tag[7]<=tag;q_left_ready[7]<=left_value[32];q_right_ready[7]<=right_value[32];
                q_pc[7]<=pc;q_instruction[7]<=instruction;
                q_writes[7]<=writes&&destination!=0;q_error[7]<=fetch_error||decode_error;
                q_static_wakeup[7]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[7]<=serial_operation;q_memory[7]<=memory_operation;
                q_arithmetic[7]<=arithmetic_operation;q_multiply[7]<=instruction[14:12]==0;
                q_store[7]<=store_operation;
                q_control_meta[7]<=immutable_control_metadata(instruction,pc);
                q_alu_control[7]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[7] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[7]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[7] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[7]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[7]<=left_tag;q_right_tag[7]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[8]&&qs==8)begin
                q_tag[8]<=tag;q_left_ready[8]<=left_value[32];q_right_ready[8]<=right_value[32];
                q_pc[8]<=pc;q_instruction[8]<=instruction;
                q_writes[8]<=writes&&destination!=0;q_error[8]<=fetch_error||decode_error;
                q_static_wakeup[8]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[8]<=serial_operation;q_memory[8]<=memory_operation;
                q_arithmetic[8]<=arithmetic_operation;q_multiply[8]<=instruction[14:12]==0;
                q_store[8]<=store_operation;
                q_control_meta[8]<=immutable_control_metadata(instruction,pc);
                q_alu_control[8]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[8] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[8]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[8] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[8]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[8]<=left_tag;q_right_tag[8]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[9]&&qs==9)begin
                q_tag[9]<=tag;q_left_ready[9]<=left_value[32];q_right_ready[9]<=right_value[32];
                q_pc[9]<=pc;q_instruction[9]<=instruction;
                q_writes[9]<=writes&&destination!=0;q_error[9]<=fetch_error||decode_error;
                q_static_wakeup[9]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[9]<=serial_operation;q_memory[9]<=memory_operation;
                q_arithmetic[9]<=arithmetic_operation;q_multiply[9]<=instruction[14:12]==0;
                q_store[9]<=store_operation;
                q_control_meta[9]<=immutable_control_metadata(instruction,pc);
                q_alu_control[9]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[9] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[9]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[9] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[9]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[9]<=left_tag;q_right_tag[9]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[10]&&qs==10)begin
                q_tag[10]<=tag;q_left_ready[10]<=left_value[32];q_right_ready[10]<=right_value[32];
                q_pc[10]<=pc;q_instruction[10]<=instruction;
                q_writes[10]<=writes&&destination!=0;q_error[10]<=fetch_error||decode_error;
                q_static_wakeup[10]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[10]<=serial_operation;q_memory[10]<=memory_operation;
                q_arithmetic[10]<=arithmetic_operation;q_multiply[10]<=instruction[14:12]==0;
                q_store[10]<=store_operation;
                q_control_meta[10]<=immutable_control_metadata(instruction,pc);
                q_alu_control[10]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[10] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[10]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[10] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[10]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[10]<=left_tag;q_right_tag[10]<=right_tag;
            end
            if(ACTIVE_QUEUE_MASK[11]&&qs==11)begin
                q_tag[11]<=tag;q_left_ready[11]<=left_value[32];q_right_ready[11]<=right_value[32];
                q_pc[11]<=pc;q_instruction[11]<=instruction;
                q_writes[11]<=writes&&destination!=0;q_error[11]<=fetch_error||decode_error;
                q_static_wakeup[11]<=instruction_static_wakeup(instruction,pc,writes&&destination!=0,
                    memory_operation,arithmetic_operation,fetch_error,decode_error);
                q_serial[11]<=serial_operation;q_memory[11]<=memory_operation;
                q_arithmetic[11]<=arithmetic_operation;q_multiply[11]<=instruction[14:12]==0;
                q_store[11]<=store_operation;
                q_control_meta[11]<=immutable_control_metadata(instruction,pc);
                q_alu_control[11]<=pack_queue_alu_control(alu_control);
                // An unavailable operand carries a producer tag, never usable data.
                // Zero it here so the later one-hot wide mux needs no ready gate.
                // q_left[11] 按 left_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_left[11]<=left_value[32]?left_value[31:0]:32'b0;
                // q_right[11] 按 right_value[32] 选择候选来源；各分支结果仍属于当前寄存边界。
                q_right[11]<=right_value[32]?right_value[31:0]:32'b0;
                q_left_tag[11]<=left_tag;q_right_tag[11]<=right_tag;
            end
        end
    endtask

    // 把满足条件的分配候选装入执行边界，避免再次排队时保持同一身份与依赖约束。
    task install_dispatch_execution;
        // writes 保存目的写资格，无目的寄存器的指令不能借此写回架构寄存器。
        input lane,writes;
        input [3:0] tag;
        input integer qs;
        input [31:0] pc,instruction,left_value,right_value;
        input [63:0] sequence_number;
        begin
            if(!lane)begin
                // ex_tag0 按 tag;ex_writes0<=writes;ex_sequence0<=ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_tag0<=tag;ex_writes0<=writes;ex_sequence0<=ENABLE_TRACE?sequence_number:0;
                // debug_issue_tag0 按 tag;debug_issue_sequence0<=ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
                debug_issue_tag0<=tag;debug_issue_sequence0<=ENABLE_TRACE?sequence_number:0;debug_issue_pc0<=pc;
                debug_issue_queue0<=ENABLE_TRACE?qs[3:0]:4'b0;
            end else begin
                // ex_tag1 按 tag;ex_writes1<=writes;ex_sequence1<=ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_tag1<=tag;ex_writes1<=writes;ex_sequence1<=ENABLE_TRACE?sequence_number:0;
                // debug_issue_tag1 按 tag;debug_issue_sequence1<=ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
                debug_issue_tag1<=tag;debug_issue_sequence1<=ENABLE_TRACE?sequence_number:0;debug_issue_pc1<=pc;
                debug_issue_queue1<=ENABLE_TRACE?qs[3:0]:4'b0;
            end
            // Per-row ownership masks discard a bypassed reservation while
            // preserving the allocated ROB owner in the execution register.
        end
    endtask

    // 提前形成不会随操作数值变化的控制元数据，与该指令一起保存在队列。
    function [4:0] immutable_control_metadata;
        input [31:0] instruction,pc;
        begin
            immutable_control_metadata[0]=ordinary_integer_class(instruction);
            immutable_control_metadata[1]=instruction[6:0]==7'b1101111&&instruction[21];
            immutable_control_metadata[2]=instruction[6:0]==7'b1100111;
            immutable_control_metadata[3]=pc[1:0]!=0;
            immutable_control_metadata[4]=instruction_csr_access_fault(instruction);
        end
    endfunction

    // Precompute immutable wake qualification at allocation, before any
    // scheduling/operand data path. The second bit intentionally omits CSR
    // access checking to retain the original lane-1 predicate in every mode.
    // 识别可由静态类别提前给出的唤醒资格；运行时异常仍须另外限定。
    function [1:0] instruction_static_wakeup;
        input [31:0] instruction,pc;
        input writes,memory_operation,arithmetic_operation,fetch_error,decode_error;
        reg [4:0] metadata;
        reg common_permission;
        begin
            metadata=immutable_control_metadata(instruction,pc);
            common_permission=writes&&!memory_operation&&!arithmetic_operation&&
                !fetch_error&&!decode_error&&!metadata[3]&&!metadata[1];
            instruction_static_wakeup={common_permission,common_permission&&!metadata[4]};
        end
    endfunction
    wire [1:0] dispatch_static_wakeup0=instruction_static_wakeup(fetch_instruction0,fetch_pc0,
        d_write0&&d_rd0!=0,d_mem0,d_mdu0,fetch_error0,d_bad0);
    wire [1:0] dispatch_static_wakeup1=instruction_static_wakeup(fetch_instruction1,fetch_pc1,
        d_write1&&d_rd1!=0,d_mem1,d_mdu1,fetch_error1,d_bad1);
    // issue_static_wakeup0 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 (|(ordered_mask0&ordered_static_wakeup0))；其余情况取 q_static_wakeup[issue_present0?issue_choice0:0][0]。
    wire issue_static_wakeup0=ORDERED_SCHEDULER?(|(ordered_mask0&ordered_static_wakeup0)):
        q_static_wakeup[issue_present0?issue_choice0:0][0];
    // issue_static_wakeup1 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 (|(ordered_mask1&ordered_static_wakeup1))；其余情况取 q_static_wakeup[issue_present1?issue_choice1:0][1]。
    wire issue_static_wakeup1=ORDERED_SCHEDULER?(|(ordered_mask1&ordered_static_wakeup1)):
        q_static_wakeup[issue_present1?issue_choice1:0][1];
`ifdef VERILATOR
    integer wakeup_contract_row;
    always @(posedge clk)if(!reset)begin
        for(wakeup_contract_row=0;wakeup_contract_row<12;wakeup_contract_row=wakeup_contract_row+1)
            if(q_valid[wakeup_contract_row])begin
                if((!q_left_ready[wakeup_contract_row]&&q_left[wakeup_contract_row]!=0)||
                   (!q_right_ready[wakeup_contract_row]&&q_right[wakeup_contract_row]!=0))
                    $fatal(1,"TOPT2 live unready queue operand is not zero");
                if(q_static_wakeup[wakeup_contract_row][1]!=(q_writes[wakeup_contract_row]&&
                   !q_memory[wakeup_contract_row]&&!q_arithmetic[wakeup_contract_row]&&
                   !q_error[wakeup_contract_row]&&!q_control_meta[wakeup_contract_row][3]&&
                   !q_control_meta[wakeup_contract_row][1])||
                   q_static_wakeup[wakeup_contract_row][0]!=(q_static_wakeup[wakeup_contract_row][1]&&
                   !q_control_meta[wakeup_contract_row][4]))
                    $fatal(1,"TOPT2 queued static wake metadata mismatch");
            end
    end
`endif

    // Decode each frontend proposal before the late dispatch lane selector.
    wire [4:0] dispatch_immutable0=immutable_control_metadata(fetch_instruction0,fetch_pc0);
    wire [4:0] dispatch_immutable1=immutable_control_metadata(fetch_instruction1,fetch_pc1);
    // dispatch_control0 属于分配直达执行路径，保存控制流类别或控制位，供目标选择和分支结果处理使用。
    // dispatch_control0 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {dispatch_immutable0[4],dispatch_immutable0[3]||fetch_error0||d_bad0,；复制大括号表示重复位域，不是独立队列元素。
    wire [6:0] dispatch_control0={dispatch_immutable0[4],dispatch_immutable0[3]||fetch_error0||d_bad0,
        dispatch_immutable0[2:0],d_mdu0,d_mem0};
    // dispatch_control1 属于分配直达执行路径，保存控制流类别或控制位，供目标选择和分支结果处理使用。
    // dispatch_control1 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {dispatch_immutable1[4],dispatch_immutable1[3]||fetch_error1||d_bad1,；复制大括号表示重复位域，不是独立队列元素。
    wire [6:0] dispatch_control1={dispatch_immutable1[4],dispatch_immutable1[3]||fetch_error1||d_bad1,
        dispatch_immutable1[2:0],d_mdu1,d_mem1};
    // These are precisely the instruction fields captured by the original
    // queued issue block. TOPT4 queued payloads have removed the late ROB read
    // in the default configuration; the diagnostic mode uses the old source.
    // issue_capture_instruction0 保存原始指令编码，和该条指令的 PC 及身份同行保存。
    // issue_capture_instruction0 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_instruction0；其余情况取 read_rob_instruction(issue_payload_tag0)。
    wire [31:0] issue_capture_instruction0=ORDERED_SCHEDULER?ordered_instruction0:read_rob_instruction(issue_payload_tag0);
    // issue_capture_instruction1 保存原始指令编码，和该条指令的 PC 及身份同行保存。
    // issue_capture_instruction1 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_instruction1；其余情况取 read_rob_instruction(issue_payload_tag1)。
    wire [31:0] issue_capture_instruction1=ORDERED_SCHEDULER?ordered_instruction1:read_rob_instruction(issue_payload_tag1);
    wire dispatch_jalr_misaligned0=low_sum_bit1(dispatch_left0[1:0],fetch_instruction0[21:20]);
    wire dispatch_jalr_misaligned1=low_sum_bit1(dispatch_left1[1:0],fetch_instruction1[21:20]);
    wire issue_jalr_misaligned0=low_sum_bit1(issue_payload_left0[1:0],issue_capture_instruction0[21:20]);
    wire issue_jalr_misaligned1=low_sum_bit1(issue_payload_left1[1:0],issue_capture_instruction1[21:20]);
    // issue_alu_control0 保存控制流类别或控制位，供目标选择和分支结果处理使用。
    // issue_alu_control0 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_alu_control0；其余情况取 unpack_queue_alu_control(q_alu_control[issue_present0?issue_choice0:0])。
    wire [31:0] issue_alu_control0=ORDERED_SCHEDULER?ordered_alu_control0:
        unpack_queue_alu_control(q_alu_control[issue_present0?issue_choice0:0]);
    // issue_alu_control1 保存控制流类别或控制位，供目标选择和分支结果处理使用。
    // issue_alu_control1 按 ORDERED_SCHEDULER 进行来源选择。
    // 真分支取 ordered_alu_control1；其余情况取 unpack_queue_alu_control(q_alu_control[issue_present1?issue_choice1:0])。
    wire [31:0] issue_alu_control1=ORDERED_SCHEDULER?ordered_alu_control1:
        unpack_queue_alu_control(q_alu_control[issue_present1?issue_choice1:0]);
    // Queued issue consumes already-predecoded per-entry bits, not the late
    // encoded ROB instruction/PC read. Preserve the R51/RV32 response cases.
    // issue_control0 保存控制流类别或控制位，供目标选择和分支结果处理使用。
    wire [6:0] issue_control0=ORDERED_SCHEDULER?ordered_control0:
        {q_control_meta[issue_present0?issue_choice0:0][4],
         q_control_meta[issue_present0?issue_choice0:0][3]||q_error[issue_present0?issue_choice0:0],
         q_control_meta[issue_present0?issue_choice0:0][2:0],q_arithmetic[issue_present0?issue_choice0:0],q_memory[issue_present0?issue_choice0:0]};
    // issue_control1 保存控制流类别或控制位，供目标选择和分支结果处理使用。
    wire [6:0] issue_control1=ORDERED_SCHEDULER?ordered_control1:
        {q_control_meta[issue_present1?issue_choice1:0][4],
         q_control_meta[issue_present1?issue_choice1:0][3]||q_error[issue_present1?issue_choice1:0],
         q_control_meta[issue_present1?issue_choice1:0][2:0],q_arithmetic[issue_present1?issue_choice1:0],q_memory[issue_present1?issue_choice1:0]};
    // 结合编号 权限和访问类型检查 CSR 指令访问是否合法。
    function instruction_csr_access_fault;
        input [31:0] instruction;
        // csr_instruction 属于特权 CSR，保存原始指令编码，和该条指令的 PC 及身份同行保存。
        reg csr_instruction,write_requested;
        begin
            csr_instruction=instruction[6:0]==7'b1110011&&instruction[14:12]!=0;
            // CSRRW/CSRRWI write even for rs1/zimm=0; CSRRS/CSRRC and their
            // immediate forms write only when the instruction field is nonzero.
            // funct3=100 is illegal but the original decoder leaves write=0.
            write_requested=instruction[13:12]==1||
                ((instruction[13:12]==2||instruction[13:12]==3)&&instruction[19:15]!=0);
            instruction_csr_access_fault=csr_instruction&&
                (!csr_exists(instruction[31:20])||(write_requested&&instruction[31:30]==3)||
                 current_privilege<instruction[29:28]||
                 (instruction[31:20]==12'h180&&current_privilege==1&&csr_status[20])||
                 ((instruction[31:20]==12'hc00||instruction[31:20]==12'hc80||
                   instruction[31:20]==12'hc01||instruction[31:20]==12'hc81||
                   instruction[31:20]==12'hc02||instruction[31:20]==12'hc82)&&current_privilege!=3&&
                  (!csr_mcounteren[instruction[24:20]]||(current_privilege==0&&!csr_scounteren[instruction[24:20]]))));
        end
    endfunction

    // The assignments mirror the instruction/PC payload at  install_dispatch_
    // execution and the queued issue block: issue overrides dispatch if both
    // propose the same lane, recovery does not gate private payload, and a held
    // MUL receives neither lane-0 proposal. No readiness or ownership changes.
    always @(posedge clk)begin
        if(reset)begin
            ex_control_meta0<=6'b100000;ex_control_meta1<=6'b100000;
            ex_csr_access_fault0<=0;
            ex_static_wakeup0<=0;ex_static_wakeup1<=0;
            ex_jalr_misaligned0<=0;ex_jalr_misaligned1<=0;
            ex_alu_control0<=0;ex_alu_control1<=0;
        end else begin
            if(dispatch_ex0>=0)begin
                ex_static_wakeup0<=dispatch_ex0==0?dispatch_static_wakeup0[0]:dispatch_static_wakeup1[0];
                ex_jalr_misaligned0<=dispatch_ex0==0?dispatch_jalr_misaligned0:dispatch_jalr_misaligned1;
                // ex_alu_control0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_alu_control0<=dispatch_ex0==0?dispatch_alu_control0:dispatch_alu_control1;
                ex_control_meta0<=dispatch_ex0==0?dispatch_control0[5:0]:dispatch_control1[5:0];
                // ex_csr_access_fault0 按 dispatch_ex0==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_csr_access_fault0<=dispatch_ex0==0?dispatch_control0[6]:dispatch_control1[6];
            end
            if(dispatch_ex1>=0)begin
                ex_static_wakeup1<=dispatch_ex1==0?dispatch_static_wakeup0[1]:dispatch_static_wakeup1[1];
                ex_jalr_misaligned1<=dispatch_ex1==0?dispatch_jalr_misaligned0:dispatch_jalr_misaligned1;
                // ex_alu_control1 按 dispatch_ex1==0 选择候选来源；各分支结果仍属于当前寄存边界。
                ex_alu_control1<=dispatch_ex1==0?dispatch_alu_control0:dispatch_alu_control1;
                ex_control_meta1<=dispatch_ex1==0?dispatch_control0[5:0]:dispatch_control1[5:0];
            end
            if(issue_present0)begin
                ex_static_wakeup0<=issue_static_wakeup0;
                ex_jalr_misaligned0<=issue_jalr_misaligned0;
                ex_alu_control0<=issue_alu_control0;
                ex_control_meta0<=issue_control0[5:0];
                ex_csr_access_fault0<=issue_control0[6];
            end
            if(issue_present1)begin
                ex_static_wakeup1<=issue_static_wakeup1;
                ex_jalr_misaligned1<=issue_jalr_misaligned1;
                ex_alu_control1<=issue_alu_control1;
                ex_control_meta1<=issue_control1[5:0];
            end
        end
    end

`ifdef VERILATOR
    always @(posedge clk)if(!reset&&ENABLE_EARLY_JALR_CHECK)begin
        // Only valid packets own their private payload. On a bubble, streamed
        // operands may change while the instruction and alignment flag hold.
        if(ex_valid0&&ex_jalr_misaligned0!=jalr_low0[1])
            $fatal(1,"TOPT4 EX0 early JALR alignment lost its operand/instruction owner");
        if(ex_valid1&&ex_jalr_misaligned1!=jalr_low1[1])
            $fatal(1,"TOPT4 EX1 early JALR alignment lost its operand/instruction owner");
    end
    // Independent original decode/value paths remain live only in simulation
    // (or when the diagnostic parameter selects them). They check packet
    // correspondence, including both dispatch lanes and held EX0 ownership.
    wire [31:0] alu_control_reference0,alu_control_reference1;
    wire [31:0] issue_alu_control_reference0,issue_alu_control_reference1;
    rv32_alu_predecode issue_alu_contract0(.instruction(issue_capture_instruction0),.control(issue_alu_control_reference0));
    rv32_alu_predecode issue_alu_contract1(.instruction(issue_capture_instruction1),.control(issue_alu_control_reference1));
    always @(posedge clk)if(!reset&&ENABLE_PREDECODED_ALU)begin
        if(issue_present0&&issue_alu_control0!=issue_alu_control_reference0)
            $fatal(1,"TOPT5 first compact queue ALU control differs from its instruction owner");
        if(issue_present1&&issue_alu_control1!=issue_alu_control_reference1)
            $fatal(1,"TOPT5 second compact queue ALU control differs from its instruction owner");
    end
    rv32_alu_predecode alu_contract_decode0(.instruction(ex_instruction0),.control(alu_control_reference0));
    rv32_alu_predecode alu_contract_decode1(.instruction(ex_instruction1),.control(alu_control_reference1));
    genvar alu_contract_row;
    generate for(alu_contract_row=0;alu_contract_row<12;alu_contract_row=alu_contract_row+1)begin:queue_alu_contract
        // reference_control 保存控制流类别或控制位，供目标选择和分支结果处理使用。
        wire [31:0] reference_control;
        rv32_alu_predecode decode(.instruction(read_rob_instruction(q_tag[alu_contract_row])),.control(reference_control));
        always @(posedge clk)if(!reset&&q_valid[alu_contract_row]&&ENABLE_PREDECODED_ALU)
            if(unpack_queue_alu_control(q_alu_control[alu_contract_row])!=reference_control)
                $fatal(1,"TOPT3 queued ALU control lost its instruction owner");
    end endgenerate
    always @(posedge clk)if(!reset&&ENABLE_PREDECODED_ALU)begin
        if(ex_valid0&&(ex_alu_control0!=alu_control_reference0||e_value0!=e_value_reference0))
            $fatal(1,"TOPT3 EX0 predecoded ALU differs from original captured packet");
        if(ex_valid1&&(ex_alu_control1!=alu_control_reference1||e_value1!=e_value_reference1))
            $fatal(1,"TOPT3 EX1 predecoded ALU differs from original captured packet");
    end
    // Coverage is observational only: it does not drive RTL admission/data.
    // Origin follows the same dispatch-then-issue capture priority as EX.
    reg [1:0] alu_origin0,alu_origin1;
    reg [83:0] alu_family_seen;
    integer alu_family;
    always @(posedge clk)begin
        if(reset)begin alu_origin0<=0;alu_origin1<=0;alu_family_seen<=0;end
        else begin
            if(ENABLE_PREDECODED_ALU)for(alu_family=0;alu_family<21;alu_family=alu_family+1)begin
                if(ex_valid0&&ex_alu_control0[alu_family])begin
                    if(alu_origin0==1&&!alu_family_seen[alu_family])begin
                        alu_family_seen[alu_family]<=1;
                        $display("COVERAGE TOPT3_ALU lane=0 origin=dispatch family=%0d",alu_family);
                    end
                    if(alu_origin0==2&&!alu_family_seen[21+alu_family])begin
                        alu_family_seen[21+alu_family]<=1;
                        $display("COVERAGE TOPT3_ALU lane=0 origin=queued family=%0d",alu_family);
                    end
                end
                if(ex_valid1&&ex_alu_control1[alu_family])begin
                    if(alu_origin1==1&&!alu_family_seen[42+alu_family])begin
                        alu_family_seen[42+alu_family]<=1;
                        $display("COVERAGE TOPT3_ALU lane=1 origin=dispatch family=%0d",alu_family);
                    end
                    if(alu_origin1==2&&!alu_family_seen[63+alu_family])begin
                        alu_family_seen[63+alu_family]<=1;
                        $display("COVERAGE TOPT3_ALU lane=1 origin=queued family=%0d",alu_family);
                    end
                end
            end
            if(dispatch_ex0>=0)alu_origin0<=1;
            if(dispatch_ex1>=0)alu_origin1<=1;
            if(issue_present0)alu_origin0<=2;
            if(issue_present1)alu_origin1<=2;
        end
    end
`endif

`ifdef VERILATOR
    // Independent originals remain evaluated from the captured EX packet.
    // Comparing only valid packets avoids imposing requirements on proposals
    // canceled by recovery or on payload left behind after a bubble.
    // exmeta_static_reference0 的资格组合为 ex_pc0[1:0]!=0||rob_fetch_error[ex_tag0]|| e_illegal_reference0。
    wire exmeta_static_reference0=ex_pc0[1:0]!=0||rob_fetch_error[ex_tag0]||
        e_illegal_reference0;
    // exmeta_static_reference1 的资格组合为 ex_pc1[1:0]!=0||rob_fetch_error[ex_tag1]|| e_illegal_reference1。
    wire exmeta_static_reference1=ex_pc1[1:0]!=0||rob_fetch_error[ex_tag1]||
        e_illegal_reference1;
    wire exmeta_csr_reference0=instruction_csr_access_fault(ex_instruction0);
    // exmeta_integer_reference0 的资格组合为 exmeta_static_reference0||exmeta_csr_reference0|| (ex_instruction0[6:0]==7'b1101111&&ex_instruction0[21])|| (ex_instruction0[6:0]==7'b1100111&&jalr_low0[1])。
    wire exmeta_integer_reference0=exmeta_static_reference0||exmeta_csr_reference0||
        (ex_instruction0[6:0]==7'b1101111&&ex_instruction0[21])||
        (ex_instruction0[6:0]==7'b1100111&&jalr_low0[1]);
    // exmeta_integer_reference1 的资格组合为 exmeta_static_reference1|| (ex_instruction1[6:0]==7'b1101111&&ex_instruction1[21])|| (ex_instruction1[6:0]==7'b1100111&&jalr_low1[1])。
    wire exmeta_integer_reference1=exmeta_static_reference1||
        (ex_instruction1[6:0]==7'b1101111&&ex_instruction1[21])||
        (ex_instruction1[6:0]==7'b1100111&&jalr_low1[1]);
    reg [1:0] exmeta_origin0,exmeta_origin1;
    reg [7:0] exmeta_seen;
    always @(posedge clk)begin
        if(reset)begin exmeta_origin0<=0;exmeta_origin1<=0;exmeta_seen<=0;end
        else begin
            if(dispatch_ex0>=0)exmeta_origin0<=1;
            if(dispatch_ex1>=0)exmeta_origin1<=1;
            if(issue_present0)exmeta_origin0<=2;
            if(issue_present1)exmeta_origin1<=2;
            if(ex_valid0)begin
                if(ex_control_meta0!={exmeta_static_reference0,
                    ex_instruction0[6:0]==7'b1100111,
                    (ex_instruction0[6:0]==7'b1101111&&ex_instruction0[21]),
                    ordinary_integer_class(ex_instruction0),e_arithmetic_reference0,e_memory_reference0})
                    $fatal(1,"EXMETA lane 0 class/static fault differs from original EX decoder");
                if(ex_csr_access_fault0!=exmeta_csr_reference0||integer_fault0!=exmeta_integer_reference0)
                    $fatal(1,"EXMETA lane 0 CSR/jump fault differs from original EX expression");
                if(!exmeta_seen[exmeta_origin0])begin
                    exmeta_seen[exmeta_origin0]<=1;
                    $display("COVERAGE EXMETA lane=0 source=%0d (1=dispatch,2=issue)",exmeta_origin0);
                end
            end
            if(ex_valid1)begin
                if(ex_control_meta1!={exmeta_static_reference1,
                    ex_instruction1[6:0]==7'b1100111,
                    (ex_instruction1[6:0]==7'b1101111&&ex_instruction1[21]),
                    ordinary_integer_class(ex_instruction1),e_arithmetic_reference1,e_memory_reference1})
                    $fatal(1,"EXMETA lane 1 class/static fault differs from original EX decoder");
                if(integer_fault1!=exmeta_integer_reference1)
                    $fatal(1,"EXMETA lane 1 jump fault differs from original EX expression");
                if(!exmeta_seen[4+exmeta_origin1])begin
                    exmeta_seen[4+exmeta_origin1]<=1;
                    $display("COVERAGE EXMETA lane=1 source=%0d (1=dispatch,2=issue)",exmeta_origin1);
                end
            end
            if(ex_hold&&(issue_present0||dispatch_ex0>=0))
                $fatal(1,"EXMETA held MUL has a conflicting lane 0 payload proposal");
        end
    end
`endif

    // Encoding legality is immutable allocation metadata. Capture it with
    // exactly the same private EX instruction payload and issue priorities.
    always @(posedge clk)begin
        if(reset)begin ex_decode_error0<=1;ex_decode_error1<=1;end
        else begin
            if(dispatch_ex0>=0)ex_decode_error0<=dispatch_ex0==0?d_bad0:d_bad1;
            if(dispatch_ex1>=0)ex_decode_error1<=dispatch_ex1==0?d_bad0:d_bad1;
            if(issue_present0)ex_decode_error0<=rob_decode_error[issue_payload_tag0];
            if(issue_present1)ex_decode_error1<=rob_decode_error[issue_payload_tag1];
        end
    end
`ifdef VERILATOR
    reg [3:0] ex_decode_seen;
    always @(posedge clk)begin
        if(reset)ex_decode_seen<=0;
        else begin
            if(ex_valid0&&e_illegal0!=e_illegal_reference0)$fatal(1,"R41 first cached EX legality differs from original decoder");
            if(ex_valid1&&e_illegal1!=e_illegal_reference1)$fatal(1,"R41 second cached EX legality differs from original decoder");
            if(ex_valid0&&!ex_decode_seen[{1'b0,e_illegal0}])begin
                ex_decode_seen[{1'b0,e_illegal0}]<=1;$display("COVERAGE R41 ex_decode lane=0 illegal=%0d",e_illegal0);
            end
            if(ex_valid1&&!ex_decode_seen[{1'b1,e_illegal1}])begin
                ex_decode_seen[{1'b1,e_illegal1}]<=1;$display("COVERAGE R41 ex_decode lane=1 illegal=%0d",e_illegal1);
            end
        end
    end
`endif
    // Metadata proposals equal actual completions off recovery. Payloads may
    // be written on a cancelling edge; only accepted completion masks grant done.
    // payload0 的资格组合为 !reset&&ex_valid0&&(fault0||(!e_memory0&&!e_arithmetic0))。
    wire payload0=!reset&&ex_valid0&&(fault0||(!e_memory0&&!e_arithmetic0));
    // payload_integer1 的资格组合为 !reset&&ex_valid1。
    wire payload_integer1=!reset&&ex_valid1;
    // payload1 的资格组合为 payload_integer1||raw_spill。
    wire payload1=payload_integer1||raw_spill;
    // payload2 的资格组合为 raw_memory||(raw_arithmetic&&!raw_spill)。
    wire payload2=raw_memory||(raw_arithmetic&&!raw_spill);
    // payload_fault1 保存异常资格，须携带对应指令或请求身份交给后续处理。
    // payload_fault1 的资格组合为 !raw_spill&&fault1。
    wire payload_fault1=!raw_spill&&fault1;
    // payload_fault2 保存异常资格，须携带对应指令或请求身份交给后续处理。
    // payload_fault2 的资格组合为 raw_memory&&data_response_fault。
    wire payload_fault2=raw_memory&&data_response_fault;
    // TOPT5: use the targets already computed for control flow. There is no
    // extra prediction-minus-PC adder, and no direction -> 32-bit next-PC mux
    // -> comparison path hidden inside the non-branch fallback. Direction
    // selects only among completed one-bit agreements, on the original edge.
    // payload_prediction0 保存该指令携带的预测结果，用于和实际后继地址对照。
    // payload_prediction0 通过 read_rob_prediction(ex_tag0) 查询对应字段；结果资格仍由调用点的有效条件限定。
    wire [31:0] payload_prediction0=read_rob_prediction(ex_tag0);
    // payload_sequential_miss0 由比较式 e_sequential_target0!=payload_prediction0 产生；该结果是条件判断，不是被比较的数据。
    wire payload_sequential_miss0=e_sequential_target0!=payload_prediction0;
    // payload_direct_miss0 由比较式 e_branch_jump_target0!=payload_prediction0 产生；该结果是条件判断，不是被比较的数据。
    wire payload_direct_miss0=e_branch_jump_target0!=payload_prediction0;
    // payload_indirect_miss0 由比较式 e_indirect_jump_target0!=payload_prediction0 产生；该结果是条件判断，不是被比较的数据。
    wire payload_indirect_miss0=e_indirect_jump_target0!=payload_prediction0;
    // payload_use_direct0 的资格组合为 ex_instruction0[6:0]==7'b1101111|| (ex_instruction0[6:0]==7'b1100011&&e_taken0)。
    wire payload_use_direct0=ex_instruction0[6:0]==7'b1101111||
        (ex_instruction0[6:0]==7'b1100011&&e_taken0);
    // payload_prediction_miss0 按 ex_instruction0[6:0]==7'b1100111 进行来源选择。
    // 真分支取 payload_indirect_miss0；其余情况取 (payload_use_direct0?payload_direct_miss0:payload_sequential_miss0)。
    wire payload_prediction_miss0=ex_instruction0[6:0]==7'b1100111 ? payload_indirect_miss0:
        (payload_use_direct0?payload_direct_miss0:payload_sequential_miss0);
    // payload_prediction1 保存该指令携带的预测结果，用于和实际后继地址对照。
    // payload_prediction1 通过 read_rob_prediction(ex_tag1) 查询对应字段；结果资格仍由调用点的有效条件限定。
    wire [31:0] payload_prediction1=read_rob_prediction(ex_tag1);
    // payload_sequential_miss1 由比较式 e_sequential_target1!=payload_prediction1 产生；该结果是条件判断，不是被比较的数据。
    wire payload_sequential_miss1=e_sequential_target1!=payload_prediction1;
    // payload_direct_miss1 由比较式 e_branch_jump_target1!=payload_prediction1 产生；该结果是条件判断，不是被比较的数据。
    wire payload_direct_miss1=e_branch_jump_target1!=payload_prediction1;
    // payload_indirect_miss1 由比较式 e_indirect_jump_target1!=payload_prediction1 产生；该结果是条件判断，不是被比较的数据。
    wire payload_indirect_miss1=e_indirect_jump_target1!=payload_prediction1;
    // payload_use_direct1 的资格组合为 ex_instruction1[6:0]==7'b1101111|| (ex_instruction1[6:0]==7'b1100011&&e_taken1)。
    wire payload_use_direct1=ex_instruction1[6:0]==7'b1101111||
        (ex_instruction1[6:0]==7'b1100011&&e_taken1);
    // payload_prediction_miss1 按 ex_instruction1[6:0]==7'b1100111 进行来源选择。
    // 真分支取 payload_indirect_miss1；其余情况取 (payload_use_direct1?payload_direct_miss1:payload_sequential_miss1)。
    wire payload_prediction_miss1=ex_instruction1[6:0]==7'b1100111 ? payload_indirect_miss1:
        (payload_use_direct1?payload_direct_miss1:payload_sequential_miss1);
`ifdef VERILATOR
    // Branch direction is late operand logic. Compute both possible target
    // agreements independently, then select a single bit after direction;
    // avoid direction ->32-bit next-PC mux -> full prediction comparison.
    // payload_prediction_delta0 通过 read_rob_prediction(ex_tag0)-ex_pc0 查询对应字段；结果资格仍由调用点的有效条件限定。
    wire [31:0] payload_prediction_delta0=read_rob_prediction(ex_tag0)-ex_pc0;
    // payload_prediction_delta1 通过 read_rob_prediction(ex_tag1)-ex_pc1 查询对应字段；结果资格仍由调用点的有效条件限定。
    wire [31:0] payload_prediction_delta1=read_rob_prediction(ex_tag1)-ex_pc1;
    // payload_branch_offset0 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {{19{ex_instruction0[31]}},ex_instruction0[31],ex_instruction0[7],ex_instruction0[30:25],ex_instruction0[11:8],1'b0}；复制大括号表示重复位域，不是独立队列元素。
    wire [31:0] payload_branch_offset0={{19{ex_instruction0[31]}},ex_instruction0[31],ex_instruction0[7],ex_instruction0[30:25],ex_instruction0[11:8],1'b0};
    // payload_branch_offset1 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {{19{ex_instruction1[31]}},ex_instruction1[31],ex_instruction1[7],ex_instruction1[30:25],ex_instruction1[11:8],1'b0}；复制大括号表示重复位域，不是独立队列元素。
    wire [31:0] payload_branch_offset1={{19{ex_instruction1[31]}},ex_instruction1[31],ex_instruction1[7],ex_instruction1[30:25],ex_instruction1[11:8],1'b0};
    // payload_branch_match0 的资格组合为 (e_taken0&&(payload_prediction_delta0==payload_branch_offset0))|| (!e_taken0&&(payload_prediction_delta0==32'd4))。
    wire payload_branch_match0=(e_taken0&&(payload_prediction_delta0==payload_branch_offset0))||
        (!e_taken0&&(payload_prediction_delta0==32'd4));
    // payload_branch_match1 的资格组合为 (e_taken1&&(payload_prediction_delta1==payload_branch_offset1))|| (!e_taken1&&(payload_prediction_delta1==32'd4))。
    wire payload_branch_match1=(e_taken1&&(payload_prediction_delta1==payload_branch_offset1))||
        (!e_taken1&&(payload_prediction_delta1==32'd4));
    // payload_prediction_miss_reference0 按 ex_instruction0[6:0]==7'b1100011 进行来源选择。
    // 真分支取 !payload_branch_match0；其余情况取 (e_next0!=read_rob_prediction(ex_tag0))。
    wire payload_prediction_miss_reference0=ex_instruction0[6:0]==7'b1100011 ? !payload_branch_match0 : (e_next0!=read_rob_prediction(ex_tag0));
    // payload_prediction_miss_reference1 按 ex_instruction1[6:0]==7'b1100011 进行来源选择。
    // 真分支取 !payload_branch_match1；其余情况取 (e_next1!=read_rob_prediction(ex_tag1))。
    wire payload_prediction_miss_reference1=ex_instruction1[6:0]==7'b1100011 ? !payload_branch_match1 : (e_next1!=read_rob_prediction(ex_tag1));
    always @(posedge clk)if(!reset)begin
        if(payload0&&payload_prediction_miss0!=payload_prediction_miss_reference0)
            $fatal(1,"TOPT5 first prediction match differs from original R39 formula");
        if(payload_integer1&&payload_prediction_miss1!=payload_prediction_miss_reference1)
            $fatal(1,"TOPT5 second prediction match differs from original R39 formula");
    end
`endif
`ifdef VERILATOR
    reg [3:0] branch_facts_seen0,branch_facts_seen1;
    always @(posedge clk)begin
        if(reset)begin branch_facts_seen0<=0;branch_facts_seen1<=0;end
        else begin
            if(payload0&&e_control0&&payload_prediction_miss0!=(e_next0!=read_rob_prediction(ex_tag0)))
                $fatal(1,"R39 first prediction fact differs from original full next-PC comparison");
            if(payload_integer1&&e_control1&&payload_prediction_miss1!=(e_next1!=read_rob_prediction(ex_tag1)))
                $fatal(1,"R39 second prediction fact differs from original full next-PC comparison");
            if(complete0&&ex_instruction0[6:0]==7'b1100011&&!branch_facts_seen0[{e_taken0,payload_prediction_miss0}])begin
                branch_facts_seen0[{e_taken0,payload_prediction_miss0}]<=1;
                $display("COVERAGE R39 branch_fact lane=0 taken=%0d miss=%0d",e_taken0,payload_prediction_miss0);
            end
            if(complete_integer1&&ex_instruction1[6:0]==7'b1100011&&!branch_facts_seen1[{e_taken1,payload_prediction_miss1}])begin
                branch_facts_seen1[{e_taken1,payload_prediction_miss1}]<=1;
                $display("COVERAGE R39 branch_fact lane=1 taken=%0d miss=%0d",e_taken1,payload_prediction_miss1);
            end
        end
    end
`endif
    wire allocate_prediction_miss0=!fetch_prediction_sequential0;
    wire allocate_prediction_miss1=!fetch_prediction_sequential1;
    genvar completion_row;
    generate for(completion_row=0;completion_row<16;completion_row=completion_row+1)begin:completion_metadata
        // alloc0 的资格组合为 allocation_offer_count!=0&&rob_tail==completion_row。
        wire alloc0=allocation_offer_count!=0&&rob_tail==completion_row;
        // alloc1 的资格组合为 allocation_offer_count==2&&tail1==completion_row。
        wire alloc1=allocation_offer_count==2&&tail1==completion_row;
        // packet0 的资格组合为 payload0&&ex_tag0==completion_row。
        wire packet0=payload0&&ex_tag0==completion_row;
        // packet1 的资格组合为 payload1&&wake_tag1==completion_row。
        wire packet1=payload1&&wake_tag1==completion_row;
        // packet2 的资格组合为 payload2&&wake_tag2==completion_row。
        wire packet2=payload2&&wake_tag2==completion_row;
        // accepted 的资格组合为 (complete0&&ex_tag0==completion_row)|| (complete1&&complete_tag1==completion_row)||(complete2&&complete_tag2==completion_row)。
        wire accepted=(complete0&&ex_tag0==completion_row)||
            (complete1&&complete_tag1==completion_row)||(complete2&&complete_tag2==completion_row);
        always @(posedge clk)begin
            // 恢复或冲刷条件 if(reset||recovery)rob_done[completion_row]<=0; 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(reset||recovery)rob_done[completion_row]<=0;
            else if(alloc0||alloc1)rob_done[completion_row]<=0;
            else if(accepted)rob_done[completion_row]<=1;
            if(reset)begin rob_fault[completion_row]<=0;result_owner[completion_row]<=0;end
            else begin
                if(packet0)begin
                    rob_fault[completion_row]<=fault0;rob_cause[completion_row]<=fault_cause0;
                    result_owner[completion_row]<=0;
                    rob_control[completion_row]<=e_control0;rob_conditional[completion_row]<=e_conditional0;
                    rob_taken[completion_row]<=e_taken0;
                    if(e_control0)rob_prediction_miss[completion_row]<=payload_prediction_miss0;
                    rob_system[completion_row]<=e_system0;rob_csr_write[completion_row]<=e_csr0&&e_csr_write0;
                end
                if(packet1)begin
                    // rob_fault[completion_row] 按 payload_fault1;rob_cause[completion_row]<=raw_spill 选择候选来源；各分支结果仍属于当前寄存边界。
                    rob_fault[completion_row]<=payload_fault1;rob_cause[completion_row]<=raw_spill?32'b0:fault_cause1;
                    result_owner[completion_row]<=1;
                    if(!raw_spill)begin
                        rob_control[completion_row]<=e_control1;rob_conditional[completion_row]<=e_conditional1;
                        rob_taken[completion_row]<=e_taken1;
                        if(e_control1)rob_prediction_miss[completion_row]<=payload_prediction_miss1;
                    end
                end
                if(packet2)begin
                    // rob_fault[completion_row] 按 payload_fault2;rob_cause[completion_row]<=dmem_response_page_fault 选择候选来源；各分支结果仍属于当前寄存边界。
                    rob_fault[completion_row]<=payload_fault2;rob_cause[completion_row]<=dmem_response_page_fault?(lsu_store?15:13):(lsu_store?7:5);
                    result_owner[completion_row]<=2;
                end
                // Pre-edge free allocation targets override any dead payload.
                if(alloc0||alloc1)begin
                    rob_fault[completion_row]<=0;rob_cause[completion_row]<=0;
                    rob_control[completion_row]<=0;rob_conditional[completion_row]<=0;rob_taken[completion_row]<=0;
                    rob_system[completion_row]<=0;rob_csr_write[completion_row]<=0;
                    rob_prediction_miss[completion_row]<=alloc0?allocate_prediction_miss0:allocate_prediction_miss1;
                end
            end
        end
`ifdef VERILATOR
        always @(posedge clk)if(!reset&&!recovery)begin
            if((packet0&&packet1)||(packet0&&packet2)||(packet1&&packet2))
                $fatal(1,"R15 duplicate completion owner");
            if((packet0||packet1||packet2)&&(!rob_valid[completion_row]||alloc0||alloc1))
                $fatal(1,"R15 completion allocation/validity ownership collision");
        end
`endif
    end endgenerate
    always @(posedge clk)begin
        if(payload0)begin
            serial_csr_number<=e_csr_number0;serial_csr_value<=e_csr_new0;
            // mip.SEIP has a software latch ORed with the external controller
            // for rd readback. The external level MUST NOT feed the CSRRS/RC
            // RMW write value, including immediate forms (Privileged ISA).
            // CSRRW still writes its source directly; e_value0 retains OR readback.
            if(e_csr0&&e_csr_number0==12'h344&&ex_instruction0[13])begin
                if(ex_instruction0[12])
                    serial_csr_value[9]<=csr_pending[9]&~(!ex_instruction0[14]&&ex_left0[9]);
                else
                    serial_csr_value[9]<=csr_pending[9]|(!ex_instruction0[14]&&ex_left0[9]);
            end
        end
    end
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&!recovery)begin
        if(payload0!=complete0||payload1!=complete1||payload2!=complete2)
            $fatal(1,"R15 private/accepted completion mask mismatch");
        if(complete1&&(wake_tag1!=complete_tag1||wake_value1!=complete_value1||payload_fault1!=complete_fault1))
            $fatal(1,"R15 private/accepted completion1 payload mismatch");
        if(complete2&&(wake_tag2!=complete_tag2||wake_value2!=complete_value2||payload_fault2!=complete_fault2))
            $fatal(1,"R15 private/accepted completion2 payload mismatch");
    end
`endif

    always @(posedge clk)begin
        if(allocation_offer_count!=0&&(!rob_tail[0]||allocation_offer_count==2))begin
            rob_instruction_even[rob_tail[0]?tail1[3:1]:rob_tail[3:1]]<=rob_tail[0]?fetch_instruction1:fetch_instruction0;
            rob_recovery_even[rob_tail[0]?tail1[3:1]:rob_tail[3:1]]<=rob_tail[0]?fetch_recovery_context1:fetch_recovery_context0;
            rob_context_even[rob_tail[0]?tail1[3:1]:rob_tail[3:1]]<=rob_tail[0]?fetch_prediction_context1:fetch_prediction_context0;
            rob_prediction_even[rob_tail[0]?tail1[3:1]:rob_tail[3:1]]<=rob_tail[0]?fetch_prediction1:fetch_prediction0;
        end
        if(allocation_offer_count!=0&&(rob_tail[0]||allocation_offer_count==2))begin
            rob_instruction_odd[rob_tail[0]?rob_tail[3:1]:tail1[3:1]]<=rob_tail[0]?fetch_instruction0:fetch_instruction1;
            rob_recovery_odd[rob_tail[0]?rob_tail[3:1]:tail1[3:1]]<=rob_tail[0]?fetch_recovery_context0:fetch_recovery_context1;
            rob_context_odd[rob_tail[0]?rob_tail[3:1]:tail1[3:1]]<=rob_tail[0]?fetch_prediction_context0:fetch_prediction_context1;
            rob_prediction_odd[rob_tail[0]?rob_tail[3:1]:tail1[3:1]]<=rob_tail[0]?fetch_prediction0:fetch_prediction1;
        end
        if(payload0&&(e_control0||e_system0==2||e_system0==7))next_lane0[ex_tag0]<=e_system0==2?csr_exception_pc:(e_system0==7?csr_sepc:e_next0);
        if(payload_integer1&&e_control1)next_lane1[ex_tag1]<=e_next1;
        if(payload0&&fault0)tval_lane0[ex_tag0]<=fault_value0;
        if(payload_integer1&&fault1)tval_lane1[ex_tag1]<=fault_value1;
        if(payload2&&raw_memory&&data_response_fault)tval_lane2[wake_tag2]<=lsu_address;
        if(retire0&&rob_writes[rob_head]&&rob_destination[rob_head]!=0)
            register_lane0[rob_destination[rob_head]]<=head_retire_value;
        if(retire1&&rob_writes[head1]&&rob_destination[head1]!=0)
            register_lane1[rob_destination[head1]]<=second_retire_value;
        if(payload0)result_lane0[ex_tag0]<=e_value0;
        if(payload1)result_lane1[wake_tag1]<=wake_value1;
        if(payload2)result_lane2[wake_tag2]<=wake_value2;
    end
    always @(posedge clk)begin
        // 恢复或冲刷条件 if(reset||recovery)legacy_issue_credit<=1; 控制下列状态更新，旧事务的处理不能当成新请求接受。
        if(reset||recovery)legacy_issue_credit<=1;
        else if(issue_legacy0)legacy_issue_credit<=0;
        else if(complete_legacy)legacy_issue_credit<=1;
    end
    genvar ownership_row;
    generate for(ownership_row=0;ownership_row<12;ownership_row=ownership_row+1)begin:queue_ownership
        // issued 按 ORDERED_SCHEDULER 进行来源选择。
        // 真分支取 (ordered_mask0[ownership_row]||ordered_mask1[ownership_row])；其余情况取 (issue_choice0==ownership_row||issue_choice1==ownership_row)。
        wire issued=ORDERED_SCHEDULER?(ordered_mask0[ownership_row]||ordered_mask1[ownership_row]):
            (issue_choice0==ownership_row||issue_choice1==ownership_row);
        // allocate0 的资格组合为 allocation_offer_count!=0&&allocation_slot0==ownership_row&& dispatch_ex0!=0&&dispatch_ex1!=0。
        wire allocate0=allocation_offer_count!=0&&allocation_slot0==ownership_row&&
            dispatch_ex0!=0&&dispatch_ex1!=0;
        // allocate1 的资格组合为 allocation_offer_count==2&&allocation_slot1==ownership_row&& dispatch_ex0!=1&&dispatch_ex1!=1。
        wire allocate1=allocation_offer_count==2&&allocation_slot1==ownership_row&&
            dispatch_ex0!=1&&dispatch_ex1!=1;
        always @(posedge clk)begin
            // 恢复或冲刷条件 if(!ACTIVE_QUEUE_MASK[ownership_row]||reset||recovery)q_valid[ownership_row]<=0; 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(!ACTIVE_QUEUE_MASK[ownership_row]||reset||recovery)q_valid[ownership_row]<=0;
            else q_valid[ownership_row]<=(q_valid[ownership_row]&&!issued)||allocate0||allocate1;
        end
    end endgenerate
`ifdef VERILATOR
    reg [63:0] prior_expected_cycle,prior_expected_instruction,prior_expected_event[0:3];
    // counter_reference_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    reg counter_reference_valid;
    reg saw_cycle_carry64,saw_instruction_carry64;
    reg [3:0] saw_event_carry64;
    integer counter_reference_row;
    always @(posedge clk)begin
        if(reset)begin
            prior_expected_cycle<=0;prior_expected_instruction<=0;counter_reference_valid<=1;
            saw_cycle_carry64<=0;saw_instruction_carry64<=0;saw_event_carry64<=0;
            for(counter_reference_row=0;counter_reference_row<4;counter_reference_row=counter_reference_row+1)prior_expected_event[counter_reference_row]<=0;
        end else begin
            if(counter_reference_valid)begin
                if(cycle_counter!=prior_expected_cycle||instruction_counter!=prior_expected_instruction)
                    $fatal(1,"R35 cycle/retirement counter differs from original64-bit arithmetic/CSR priority");
                for(counter_reference_row=0;counter_reference_row<4;counter_reference_row=counter_reference_row+1)
                    if(event_counter[counter_reference_row]!=prior_expected_event[counter_reference_row])
                        $fatal(1,"R35 event counter differs from original64-bit arithmetic/partial CSR priority");
            end
            prior_expected_cycle<=cycle_counter+64'd1;
            prior_expected_instruction<=instruction_counter+{63'b0,retire0}+{63'b0,retire1};
            for(counter_reference_row=0;counter_reference_row<4;counter_reference_row=counter_reference_row+1)begin
                prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row];
                case(event_selector[counter_reference_row])
                    1:if(event_icache_refill)prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row]+64'd1;
                    2:if(event_dcache_refill)prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row]+64'd1;
                    3:if(event_dcache_writeback)prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row]+64'd1;
                    4:if(debug_branch_miss)prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row]+64'd1;
                    default:begin end
                endcase
                if(!saw_event_carry64[counter_reference_row]&&counter_event_step[counter_reference_row]&&event_counter[counter_reference_row]==64'hffffffffffffffff)begin
                    saw_event_carry64[counter_reference_row]<=1;$display("COVERAGE R35 event_carry64 row=%0d",counter_reference_row);
                end
            end
            if(!saw_cycle_carry64&&cycle_counter==64'hffffffffffffffff)begin saw_cycle_carry64<=1;$display("COVERAGE R35 cycle_carry64");end
            if(!saw_instruction_carry64&&(retire0||retire1)&&
               (instruction_counter==64'hffffffffffffffff||((retire0&&retire1)&&instruction_counter==64'hfffffffffffffffe)))begin
                saw_instruction_carry64<=1;$display("COVERAGE R35 instruction_carry64");
            end
            // Exact original write priority: cycle/instret writes replace a
            // whole64-bit proposal with the old untouched half. Event writes
            // replace only their selected half of the incremented proposal.
            if(retire0&&rob_csr_write[rob_head])begin
                case(serial_csr_number)
                    12'hb00:prior_expected_cycle<={cycle_counter[63:32],serial_csr_value};
                    12'hb80:prior_expected_cycle<={serial_csr_value,cycle_counter[31:0]};
                    12'hb02:prior_expected_instruction<={instruction_counter[63:32],serial_csr_value};
                    12'hb82:prior_expected_instruction<={serial_csr_value,instruction_counter[31:0]};
                    default:begin
                        if(serial_csr_number>=12'hb03&&serial_csr_number<=12'hb06)prior_expected_event[serial_csr_number[1:0]-2'd3][31:0]<=serial_csr_value;
                        if(serial_csr_number>=12'hb83&&serial_csr_number<=12'hb86)prior_expected_event[serial_csr_number[1:0]-2'd3][63:32]<=serial_csr_value;
                    end
                endcase
            end
        end
    end
`endif
    integer r;
    always @(posedge clk)begin
        if(reset)begin
            rob_head<=0;rob_tail<=0;rob_count<=0;serial_pending<=0;steer<=0;next_sequence<=0;
            ex_valid0<=0;ex_valid1<=0;ex_writes0<=0;ex_writes1<=0;ex_tag0<=0;ex_tag1<=0;ex_sequence0<=0;ex_sequence1<=0;
            lsu_is_atomic<=0;lsu_atomic<=0;prepared_is_atomic<=0;prepared_atomic<=0;prepared_second_is_atomic<=0;prepared_second_atomic<=0;
            lsu_state<=L_IDLE;lsu_tag<=0;lsu_sequence<=0;lsu_pc<=0;lsu_address<=0;lsu_wdata<=0;
            lsu_writes<=0;lsu_strobes<=0;lsu_size<=0;lsu_store<=0;lsu_unsigned<=0;lsu_killed<=0;lsu_irrevocable<=0;
            prepared_second_valid<=0;
            prepared_valid<=0;prepared_writes<=0;prepared_tag<=0;prepared_sequence<=0;prepared_pc<=0;prepared_address<=0;
            prepared_wdata<=0;prepared_strobes<=0;prepared_size<=0;prepared_store<=0;prepared_unsigned<=0;prepared_peripheral<=0;
            mdu_active<=0;mdu_writes<=0;mdu_tag<=0;mdu_sequence<=0;mdu_pc<=0;
            current_privilege<=3;csr_svector<=0;csr_sscratch<=0;csr_sepc<=0;csr_scause<=0;csr_stval<=0;csr_satp<=0;
            csr_medeleg<=0;csr_mideleg<=0;csr_mcounteren<=0;csr_scounteren<=0;csr_pending<=0;
            csr_status<=32'h00001800;csr_interrupt_enable<=0;csr_vector<=0;csr_scratch<=0;
            csr_exception_pc<=0;csr_cause<=0;csr_trap_value<=0;
            cycle_counter<=0;instruction_counter<=0;architectural_pc<=RESET_VECTOR;
            retire_valid<=0;retire_pc0<=0;retire_pc1<=0;retire_instruction0<=0;retire_instruction1<=0;
            retire_destination0<=0;retire_destination1<=0;retire_value0<=0;retire_value1<=0;fence_i<=0;fence_d<=0;
            for(r=0;r<32;r=r+1)begin register_valid[r]<=0;register_owner[r]<=0;map_valid[r]<=0;map_tag[r]<=0;end
            for(r=0;r<16;r=r+1)begin
                rob_valid[r]<=0;
            end

            // Inactive rows have constant payloads, with no allocation writes.
            for(r=0;r<12;r=r+1)if(!ACTIVE_QUEUE_MASK[r])begin
                q_tag[r]<=0;q_left_ready[r]<=0;q_right_ready[r]<=0;
                q_pc[r]<=0;q_instruction[r]<=0;q_writes[r]<=0;q_error[r]<=0;
                q_static_wakeup[r]<=0;q_serial[r]<=0;q_memory[r]<=0;
                q_arithmetic[r]<=0;q_multiply[r]<=0;q_store[r]<=0;
                q_control_meta[r]<=0;q_alu_control[r]<=0;
                q_left[r]<=0;q_right[r]<=0;q_left_tag[r]<=0;q_right_tag[r]<=0;
            end
            for(r=0;r<4;r=r+1)begin event_selector[r]<=0;event_counter[r]<=0;end
            debug_alloc_valid<=0;debug_alloc_proposal_valid<=0;
            debug_alloc_queue0<=0;debug_alloc_queue1<=0;debug_issue_queue0<=0;debug_issue_queue1<=0;
            debug_alloc_tag0<=0;debug_alloc_sequence0<=0;debug_alloc_pc0<=0;
            debug_alloc_tag1<=0;debug_alloc_sequence1<=0;debug_alloc_pc1<=0;
            debug_issue_valid<=0;
            debug_issue_from_allocation<=0;
            debug_issue_tag0<=0;debug_issue_sequence0<=0;debug_issue_pc0<=0;
            debug_issue_tag1<=0;debug_issue_sequence1<=0;debug_issue_pc1<=0;
            debug_complete_valid<=0;debug_complete_writes<=0;debug_complete_broadcast<=0;
            debug_complete_tag0<=0;debug_complete_sequence0<=0;debug_complete_pc0<=0;
            debug_complete_tag1<=0;debug_complete_sequence1<=0;debug_complete_pc1<=0;
            debug_complete_tag2<=0;debug_complete_sequence2<=0;debug_complete_pc2<=0;
            debug_complete_exception<=0;debug_retire_tag0<=0;debug_retire_tag1<=0;debug_retire_sequence0<=0;debug_retire_sequence1<=0;
            debug_recovery_valid<=0;debug_recovery_first_killed_sequence<=0;
        end else begin
            cycle_counter[15:0]<=cycle_counter[15:0]+16'd1;
            if(&cycle_counter[15:0])cycle_counter[31:16]<=cycle_counter[31:16]+16'd1;
            if(&cycle_counter[31:0])cycle_counter[47:32]<=cycle_counter[47:32]+16'd1;
            if(&cycle_counter[47:0])cycle_counter[63:48]<=cycle_counter[63:48]+16'd1;
            if(retire0||retire1)begin
                instruction_counter[15:0]<=instruction_counter[15:0]+(retire0&&retire1?16'd2:16'd1);
                if((&instruction_counter[15:1])&&(instruction_counter[0]||(retire0&&retire1)))
                    instruction_counter[31:16]<=instruction_counter[31:16]+16'd1;
                if((&instruction_counter[31:1])&&(instruction_counter[0]||(retire0&&retire1)))
                    instruction_counter[47:32]<=instruction_counter[47:32]+16'd1;
                if((&instruction_counter[47:1])&&(instruction_counter[0]||(retire0&&retire1)))
                    instruction_counter[63:48]<=instruction_counter[63:48]+16'd1;
            end
            for(r=0;r<4;r=r+1)if(counter_event_step[r])begin
                event_counter[r][15:0]<=event_counter[r][15:0]+16'd1;
                if(&event_counter[r][15:0])event_counter[r][31:16]<=event_counter[r][31:16]+16'd1;
                if(&event_counter[r][31:0])event_counter[r][47:32]<=event_counter[r][47:32]+16'd1;
                if(&event_counter[r][47:0])event_counter[r][63:48]<=event_counter[r][63:48]+16'd1;
            end
            retire_valid<={retire1,retire0};
            retire_pc0<=read_rob_pc(rob_head);retire_pc1<=read_rob_prediction(rob_head);
            retire_instruction0<=read_rob_instruction(rob_head);retire_instruction1<=read_rob_instruction(head1);
            // retire_destination0 按 rob_writes[rob_head] 选择候选来源；各分支结果仍属于当前寄存边界。
            retire_destination0<=rob_writes[rob_head]?rob_destination[rob_head]:0;
            // retire_destination1 按 rob_writes[head1] 选择候选来源；各分支结果仍属于当前寄存边界。
            retire_destination1<=rob_writes[head1]?rob_destination[head1]:0;
            retire_value0<=head_retire_value;retire_value1<=second_retire_value;
            debug_retire_tag0<=rob_head;debug_retire_tag1<=head1;
            debug_retire_sequence0<=rob_sequence[rob_head];debug_retire_sequence1<=rob_sequence[head1];
            // debug_recovery_valid 按 recovery;debug_recovery_first_killed_sequence<=ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
            debug_recovery_valid<=recovery;debug_recovery_first_killed_sequence<=ENABLE_TRACE?recovery_first:0;
            fence_i<=maintain_i;fence_d<=maintain_d;
            // debug_alloc_valid 按 allocate_count==2 选择候选来源；各分支结果仍属于当前寄存边界。
            debug_alloc_valid<=allocate_count==2?2'b11:allocate_count==1?2'b01:2'b00;
            // debug_alloc_proposal_valid 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
            debug_alloc_proposal_valid<=ENABLE_TRACE?(allocation_offer_count==2?2'b11:allocation_offer_count==1?2'b01:2'b00):2'b00;
            debug_alloc_queue0<=ENABLE_TRACE?allocation_slot0[3:0]:4'b0;
            debug_alloc_queue1<=ENABLE_TRACE?allocation_slot1[3:0]:4'b0;
            debug_alloc_tag0<=rob_tail;debug_alloc_tag1<=tail1;
            // debug_alloc_sequence0 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
            debug_alloc_sequence0<=ENABLE_TRACE?next_sequence:0;
            // debug_alloc_sequence1 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
            debug_alloc_sequence1<=ENABLE_TRACE?next_sequence+64'd1:0;
            debug_alloc_pc0<=fetch_pc0;debug_alloc_pc1<=fetch_pc1;
            // debug_issue_valid 按 recovery 选择候选来源；各分支结果仍属于当前寄存边界。
            debug_issue_valid<=recovery?2'b0:{issue_present1||dispatch_ex1>=0,issue_present0||dispatch_ex0>=0};
            debug_issue_from_allocation<=ENABLE_TRACE?{dispatch_ex1>=0,dispatch_ex0>=0}:2'b0;
            debug_issue_queue0<=ENABLE_TRACE?issue_choice0[3:0]:4'b0;
            debug_issue_queue1<=ENABLE_TRACE?issue_choice1[3:0]:4'b0;
            debug_complete_valid<={complete2,complete1,complete0};
            // debug_complete_writes 按 ENABLE_TRACE 选择候选来源；各分支结果仍属于当前寄存边界。
            debug_complete_writes<=ENABLE_TRACE?{complete_writes2,complete_writes1,ex_writes0}:3'b0;
            debug_complete_broadcast<=ENABLE_TRACE?{broadcast2,broadcast1,broadcast0}:3'b0;
            debug_complete_exception<={complete_fault2,complete_fault1,fault0};
            debug_complete_tag0<=ex_tag0;debug_complete_tag1<=complete_tag1;debug_complete_tag2<=complete_tag2;
            debug_complete_sequence0<=ex_sequence0;debug_complete_sequence1<=complete_sequence1;debug_complete_sequence2<=complete_sequence2;
            debug_complete_pc0<=ex_pc0;debug_complete_pc1<=complete_pc1;debug_complete_pc2<=complete_pc2;

            if(retire0)begin
                if(rob_writes[rob_head]&&rob_destination[rob_head]!=0)begin
                    register_valid[rob_destination[rob_head]]<=1;register_owner[rob_destination[rob_head]]<=0;
                    if(map_valid[rob_destination[rob_head]]&&map_tag[rob_destination[rob_head]]==rob_head)map_valid[rob_destination[rob_head]]<=0;
                end
                architectural_pc<=retirement_next0;
                if(rob_serial[rob_head])serial_pending<=0;
                if(lsu_irrevocable&&lsu_tag==rob_head)lsu_irrevocable<=0;
            end
            if(retire1)begin
                if(rob_writes[head1]&&rob_destination[head1]!=0)begin
                    register_valid[rob_destination[head1]]<=1;register_owner[rob_destination[head1]]<=1;
                    if(map_valid[rob_destination[head1]]&&map_tag[rob_destination[head1]]==head1)map_valid[rob_destination[head1]]<=0;
                end
                architectural_pc<=retirement_next1;
                if(lsu_irrevocable&&lsu_tag==head1)lsu_irrevocable<=0;
            end
            register_valid[0]<=0;map_valid[0]<=0;
            if(retire0&&rob_csr_write[rob_head])begin
                case(serial_csr_number)
                    12'h300:begin
                        csr_status<=serial_csr_value&STATUS_MASK;
                        if(serial_csr_value[12:11]==2)csr_status[12:11]<=0;
                    end
                    12'h100:csr_status<=(csr_status&~SSTATUS_MASK)|(serial_csr_value&SSTATUS_MASK);
                    12'h302:csr_medeleg<=serial_csr_value&32'h0000b3ff;
                    12'h303:csr_mideleg<=serial_csr_value&32'h00000222;
                    12'h306:csr_mcounteren<=serial_csr_value&7;
                    12'h106:csr_scounteren<=serial_csr_value&7;
                    12'h104:csr_interrupt_enable<=(csr_interrupt_enable&~csr_mideleg)|(serial_csr_value&csr_mideleg&32'h222);
                    12'h344:csr_pending<=serial_csr_value&32'h222;
                    12'h144:csr_pending<=(csr_pending&~(csr_mideleg&32'h2))|(serial_csr_value&csr_mideleg&32'h2);
                    12'h105:csr_svector<={serial_csr_value[31:2],1'b0,serial_csr_value[1:0]==1};
                    12'h140:csr_sscratch<=serial_csr_value;
                    12'h141:csr_sepc<={serial_csr_value[31:2],2'b0};
                    12'h142:csr_scause<=serial_csr_value;
                    12'h143:csr_stval<=serial_csr_value;
                    12'h180:csr_satp<=serial_csr_value;
                    12'h304:csr_interrupt_enable<=serial_csr_value&32'h00000aaa;
                    12'h305:csr_vector<={serial_csr_value[31:2],1'b0,serial_csr_value[1:0]==1};
                    12'h340:csr_scratch<=serial_csr_value;
                    12'h341:csr_exception_pc<={serial_csr_value[31:2],2'b0};
                    12'h342:csr_cause<=serial_csr_value;
                    12'h343:csr_trap_value<=serial_csr_value;
                    12'hb00:cycle_counter<={cycle_counter[63:32],serial_csr_value};
                    12'hb80:cycle_counter<={serial_csr_value,cycle_counter[31:0]};
                    12'hb02:instruction_counter<={instruction_counter[63:32],serial_csr_value};
                    12'hb82:instruction_counter<={serial_csr_value,instruction_counter[31:0]};
                    default:begin
                        if(serial_csr_number>=12'hb03&&serial_csr_number<=12'hb06)event_counter[serial_csr_number[1:0]-2'd3][31:0]<=serial_csr_value;
                        if(serial_csr_number>=12'hb83&&serial_csr_number<=12'hb86)event_counter[serial_csr_number[1:0]-2'd3][63:32]<=serial_csr_value;
                        if(serial_csr_number>=12'h323&&serial_csr_number<=12'h326)event_selector[serial_csr_number[1:0]-2'd3]<=serial_csr_value[2:0];
                    end
                endcase
            end
            if(return_from_trap)begin
                if(rob_system[rob_head]==7)begin
                    // current_privilege 按 csr_status[8] 选择候选来源；各分支结果仍属于当前寄存边界。
                    current_privilege<=csr_status[8]?1:0;
                    csr_status[1]<=csr_status[5];csr_status[5]<=1;csr_status[8]<=0;csr_status[17]<=0;
                end else begin
                    current_privilege<=csr_status[12:11];
                    csr_status[3]<=csr_status[7];csr_status[7]<=1;csr_status[12:11]<=0;
                    if(csr_status[12:11]!=3)csr_status[17]<=0;
                end
            end
            if(trap_enter)begin
                if(current_privilege!=3&&(trap_cause[31]?csr_mideleg[trap_cause[4:0]]:csr_medeleg[trap_cause[4:0]]))begin
                    csr_sepc<={trap_pc[31:2],2'b0};csr_scause<=trap_cause;csr_stval<=trap_value;
                    csr_status[5]<=csr_status[1];csr_status[1]<=0;csr_status[8]<=current_privilege==1;current_privilege<=1;
                end else begin
                    csr_exception_pc<={trap_pc[31:2],2'b0};csr_cause<=trap_cause;csr_trap_value<=trap_value;
                    csr_status[7]<=csr_status[3];csr_status[3]<=0;csr_status[12:11]<=current_privilege;current_privilege<=3;
                end
                lsu_irrevocable<=0;
            end
            // 恢复或冲刷条件 if(recovery)architectural_pc<=recovery_address; 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(recovery)architectural_pc<=recovery_address;

            // Presented requests survive recovery; only their result identity dies.
            if(lsu_state==L_OFFER&&dmem_request_ready)lsu_state<=L_WAIT;
            // 恢复或冲刷条件 if((prepared_side_effect||prepared_store_lookahead)&&!recovery) 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if((prepared_side_effect||prepared_store_lookahead)&&!recovery)begin
                // lsu_state 按 dmem_request_ready 选择候选来源；各分支结果仍属于当前寄存边界。
                lsu_state<=dmem_request_ready?L_WAIT:L_OFFER;lsu_irrevocable<=1;
            end
            // 恢复或冲刷条件 if(recovery) 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(recovery)begin
                if(lsu_state==L_PREPARED)begin lsu_state<=L_IDLE;lsu_killed<=0;end
                else if(lsu_state==L_OFFER||lsu_state==L_WAIT)lsu_killed<=1;
            end
            if(lsu_response)begin lsu_state<=L_IDLE;lsu_killed<=0;end
            // Old response consumes old A metadata. A later handoff assignment
            // installs the new owner only after that response has been recorded.
            // Unowned/turning-over payload may settle before late admission.
            // State, killed and irrevocable ownership still use active_handoff.
            if(active_room)begin
                lsu_is_atomic<=candidate_is_atomic;lsu_atomic<=candidate_atomic;
                lsu_tag<=candidate_tag;lsu_writes<=candidate_writes;lsu_sequence<=candidate_sequence;lsu_pc<=candidate_pc;
                lsu_address<=candidate_address;lsu_size<=candidate_size;lsu_store<=candidate_store;lsu_unsigned<=candidate_unsigned;
                lsu_wdata<=candidate_wdata;lsu_strobes<=candidate_strobes;
            end
            if(active_handoff)begin
                lsu_killed<=recovery;lsu_irrevocable<=candidate_side_effect&&direct_request;
                if(!direct_request)lsu_state<=L_PREPARED;
                else lsu_state<=dmem_request_ready?L_WAIT:L_OFFER;
            end
            if(recovery)begin prepared_valid<=0;prepared_second_valid<=0;end
            else begin
                if(active_handoff&&prepared_valid)begin
                    if(prepared_second_valid)begin
                        prepared_valid<=1;
                    prepared_tag<=prepared_second_tag;
                    prepared_writes<=prepared_second_writes;
                    prepared_sequence<=prepared_second_sequence;
                    prepared_pc<=prepared_second_pc;
                    prepared_address<=prepared_second_address;
                    prepared_size<=prepared_second_size;
                    prepared_store<=prepared_second_store;
                    prepared_unsigned<=prepared_second_unsigned;
                    prepared_wdata<=prepared_second_wdata;
                    prepared_strobes<=prepared_second_strobes;
                    prepared_peripheral<=prepared_second_peripheral;
                    prepared_is_atomic<=prepared_second_is_atomic;prepared_atomic<=prepared_second_atomic;
                        if(ex_memory_reservation)begin
                            prepared_second_valid<=1;
                    prepared_second_tag<=ex_tag0;
                    prepared_second_writes<=ex_writes0;
                    prepared_second_sequence<=ex_sequence0;
                    prepared_second_pc<=ex_pc0;
                    prepared_second_address<=e_address0;
                    prepared_second_size<=e_size0;
                    prepared_second_store<=e_store_enable0;
                    prepared_second_unsigned<=e_unsigned0;
                    prepared_second_wdata<=ex_shifted_store;
                    prepared_second_strobes<=ex_store_strobes;
                    prepared_second_peripheral<=ex_peripheral_proposal;
                    prepared_second_is_atomic<=ex_instruction0[6:0]==7'b0101111;prepared_second_atomic<=ex_instruction0[31:27];
                        end else prepared_second_valid<=0;
                    end else if(ex_memory_reservation)begin
                        prepared_valid<=1;
                    prepared_tag<=ex_tag0;
                    prepared_writes<=ex_writes0;
                    prepared_sequence<=ex_sequence0;
                    prepared_pc<=ex_pc0;
                    prepared_address<=e_address0;
                    prepared_size<=e_size0;
                    prepared_store<=e_store_enable0;
                    prepared_unsigned<=e_unsigned0;
                    prepared_wdata<=ex_shifted_store;
                    prepared_strobes<=ex_store_strobes;
                    prepared_peripheral<=ex_peripheral_proposal;
                    prepared_is_atomic<=ex_instruction0[6:0]==7'b0101111;prepared_atomic<=ex_instruction0[31:27];
                    end else prepared_valid<=0;
                end else if(ex_memory_reservation&&!(active_handoff&&!prepared_valid))begin
                    if(!prepared_valid)begin
                        prepared_valid<=1;
                    prepared_tag<=ex_tag0;
                    prepared_writes<=ex_writes0;
                    prepared_sequence<=ex_sequence0;
                    prepared_pc<=ex_pc0;
                    prepared_address<=e_address0;
                    prepared_size<=e_size0;
                    prepared_store<=e_store_enable0;
                    prepared_unsigned<=e_unsigned0;
                    prepared_wdata<=ex_shifted_store;
                    prepared_strobes<=ex_store_strobes;
                    prepared_peripheral<=ex_peripheral_proposal;
                    prepared_is_atomic<=ex_instruction0[6:0]==7'b0101111;prepared_atomic<=ex_instruction0[31:27];
                    end else begin
                        prepared_second_valid<=1;
                    prepared_second_tag<=ex_tag0;
                    prepared_second_writes<=ex_writes0;
                    prepared_second_sequence<=ex_sequence0;
                    prepared_second_pc<=ex_pc0;
                    prepared_second_address<=e_address0;
                    prepared_second_size<=e_size0;
                    prepared_second_store<=e_store_enable0;
                    prepared_second_unsigned<=e_unsigned0;
                    prepared_second_wdata<=ex_shifted_store;
                    prepared_second_strobes<=ex_store_strobes;
                    prepared_second_peripheral<=ex_peripheral_proposal;
                    prepared_second_is_atomic<=ex_instruction0[6:0]==7'b0101111;prepared_second_atomic<=ex_instruction0[31:27];
                    end
                end
            end
            if(complete_legacy)mdu_active<=0;
            if(mdu_request&&mdu_ready)begin mdu_active<=1;mdu_tag<=ex_tag0;mdu_writes<=ex_writes0;mdu_sequence<=ex_sequence0;mdu_pc<=ex_pc0;end
            // 恢复或冲刷条件 if(recovery)mdu_active<=0; 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(recovery)mdu_active<=0;

            if(recovery)begin
                rob_head<=0;rob_tail<=0;rob_count<=0;serial_pending<=0;
                ex_valid0<=0;ex_valid1<=0;
                for(r=0;r<16;r=r+1)begin rob_valid[r]<=0;end
    
                for(r=0;r<32;r=r+1)map_valid[r]<=0;
            end else begin
                rob_count<=rob_count+{3'b0,allocate_count}-{4'b0,retire0}-{4'b0,retire1};
                rob_head<=rob_head+{3'b0,retire0}+{3'b0,retire1};
                rob_tail<=rob_tail+{2'b0,allocate_count};
                if(ENABLE_TRACE)next_sequence<=next_sequence+{62'b0,allocate_count};
                else next_sequence<=0;
                if(retire0)rob_valid[rob_head]<=0;
                if(retire1)rob_valid[head1]<=0;
                for(r=0;r<12;r=r+1)begin
                    if(ACTIVE_QUEUE_MASK[r]&&q_valid[r])begin
                        if(!q_left_ready[r]&&broadcast_available(q_left_tag[r]))begin q_left_ready[r]<=1;q_left[r]<=broadcast_value(q_left_tag[r]);end
                        if(!q_right_ready[r]&&broadcast_available(q_right_tag[r]))begin q_right_ready[r]<=1;q_right[r]<=broadcast_value(q_right_tag[r]);end
                    end
                end
                if(!ex_hold)ex_valid0<=issue_present0||dispatch_ex0>=0;
                ex_valid1<=issue_present1||dispatch_ex1>=0;
                if(allocate_count!=0)begin
                    rob_valid[rob_tail]<=1;
                    if(d_write0&&d_rd0!=0)begin map_valid[d_rd0]<=1;map_tag[d_rd0]<=rob_tail;end
                    if(d_serial0)serial_pending<=1;
                    if(!d_complex0)steer<=allocation_slot0<4;
                end
                if(allocate_count==2)begin
                    rob_valid[tail1]<=1;
                    if(d_write1&&d_rd1!=0)begin map_valid[d_rd1]<=1;map_tag[d_rd1]<=tail1;end
                    if(!d_complex1)steer<=allocation_slot1<4;
                end
            end
                if(dispatch_ex0>=0)begin
                    install_dispatch_execution(1'b0,dispatch_ex0==0?(d_write0&&d_rd0!=0):(d_write1&&d_rd1!=0),
                        dispatch_ex0==0?rob_tail:tail1,
                        dispatch_ex0==0?allocation_slot0:allocation_slot1,
                        dispatch_ex0==0?fetch_pc0:fetch_pc1,dispatch_ex0==0?fetch_instruction0:fetch_instruction1,
                        dispatch_ex0==0?dispatch_left0:dispatch_left1,
                        dispatch_ex0==0?dispatch_right0:dispatch_right1,
                        next_sequence+(dispatch_ex0==0?64'd0:64'd1));
                end
                if(dispatch_ex1>=0)begin
                    install_dispatch_execution(1'b1,dispatch_ex1==0?(d_write0&&d_rd0!=0):(d_write1&&d_rd1!=0),
                        dispatch_ex1==0?rob_tail:tail1,
                        dispatch_ex1==0?allocation_slot0:allocation_slot1,
                        dispatch_ex1==0?fetch_pc0:fetch_pc1,dispatch_ex1==0?fetch_instruction0:fetch_instruction1,
                        dispatch_ex1==0?dispatch_left0:dispatch_left1,
                        dispatch_ex1==0?dispatch_right0:dispatch_right1,
                        next_sequence+(dispatch_ex1==0?64'd0:64'd1));
                end
            // Selection proposes payload independently of commit recovery.
            // Recovery clears EX validity and all queue ownership above.
                if(issue_present0)begin
                    ex_tag0<=issue_payload_tag0;
                    ex_writes0<=issue_payload_writes0;
                    ex_sequence0<=rob_sequence[issue_payload_tag0];
                    debug_issue_tag0<=issue_payload_tag0;debug_issue_sequence0<=rob_sequence[issue_payload_tag0];debug_issue_pc0<=read_rob_pc(issue_payload_tag0);
                end
                if(issue_present1)begin
                    ex_tag1<=issue_payload_tag1;
                    ex_writes1<=issue_payload_writes1;
                    ex_sequence1<=rob_sequence[issue_payload_tag1];
                    debug_issue_tag1<=issue_payload_tag1;debug_issue_sequence1<=rob_sequence[issue_payload_tag1];debug_issue_pc1<=read_rob_pc(issue_payload_tag1);
                end
            // ROB targets are pre-edge free; queue grants follow their policy.
            // Payload does not grant validity or rename ownership.
            // Keep this outside recovery gating to bound the initialization
            // control path. Recovery above clears every consumer's validity.
            if(allocation_offer_count!=0)begin
                initialize_allocation_payload(rob_tail,allocation_slot0,fetch_pc0,fetch_instruction0,fetch_prediction0,dispatch_alu_control0,fetch_error0,
                        d_write0,d_mem0,d_store0,d_mdu0,d_serial0,d_complex0,d_bad0,d_rd0,
                        allocation_left0,allocation_right0,allocation_ltag0,allocation_rtag0,next_sequence);
            end
            if(allocation_offer_count==2)begin
                initialize_allocation_payload(tail1,allocation_slot1,fetch_pc1,fetch_instruction1,fetch_prediction1,dispatch_alu_control1,fetch_error1,
                        d_write1,d_mem1,d_store1,d_mdu1,d_serial1,d_complex1,d_bad1,d_rd1,
                        allocation_left1,allocation_right1,allocation_ltag1,allocation_rtag1,next_sequence+64'd1);
            end
        end
    end

`ifdef VERILATOR
    integer t5_queue_check_row;
    always @(posedge clk)if(!reset)begin
        if(allocation_offer_count!=0&&!ACTIVE_QUEUE_MASK[allocation_slot0])
            $fatal(1,"TOPT5 allocation offered an inactive queue row (port 0)");
        if(allocation_offer_count==2&&!ACTIVE_QUEUE_MASK[allocation_slot1])
            $fatal(1,"TOPT5 allocation offered an inactive queue row (port 1)");
        if(issue_present0&&!ACTIVE_QUEUE_MASK[issue_choice0])
            $fatal(1,"TOPT5 issue selected an inactive queue row (lane 0)");
        if(issue_present1&&!ACTIVE_QUEUE_MASK[issue_choice1])
            $fatal(1,"TOPT5 issue selected an inactive queue row (lane 1)");
        for(t5_queue_check_row=0;t5_queue_check_row<12;t5_queue_check_row=t5_queue_check_row+1)
            if(!ACTIVE_QUEUE_MASK[t5_queue_check_row]&&q_valid[t5_queue_check_row])
                $fatal(1,"TOPT5 inactive queue row acquired ownership");
    end
`endif
// Observation-only TOPT4 coverage. Insert INSIDE rv32_ooo_core, before
// endmodule. All referenced architectural signals already exist in TOPT3.
// No output below drives an RTL admission, payload, validity or result signal.
`ifdef VERILATOR
    reg [1:0] t4_cov_origin0,t4_cov_origin1;
    reg t4_cov_prev_hold,t4_cov_release_pending;
    reg [12:0] t4_cov_event_seen;
    reg [63:0] t4_cov_jalr_seen;
    // t4_cov_capture0 的资格组合为 issue_present0||(dispatch_ex0>=0)。
    wire t4_cov_capture0=issue_present0||(dispatch_ex0>=0);
    // t4_cov_capture1 的资格组合为 issue_present1||(dispatch_ex1>=0)。
    wire t4_cov_capture1=issue_present1||(dispatch_ex1>=0);
    // t4_cov_released 的资格组合为 t4_cov_prev_hold&&!ex_hold。
    wire t4_cov_released=t4_cov_prev_hold&&!ex_hold;
    // t4_cov_hold1_index 保存表或队列的索引，须配合有效位与对应所有者使用。
    // t4_cov_hold1_index 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {3'b000,issue_present1}；复制大括号表示重复位域，不是独立队列元素。
    wire [3:0] t4_cov_hold1_index={3'b000,issue_present1};
    // t4_cov_release_index 保存表或队列的索引，须配合有效位与对应所有者使用。
    // t4_cov_release_index 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {2'b01,t4_cov_release_pending,issue_present0}；复制大括号表示重复位域，不是独立队列元素。
    wire [3:0] t4_cov_release_index={2'b01,t4_cov_release_pending,issue_present0};
    // t4_cov_raw_index0 保存表或队列的索引，须配合有效位与对应所有者使用。
    // t4_cov_raw_index0 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {2'b10,1'b0,raw_memory}；复制大括号表示重复位域，不是独立队列元素。
    wire [3:0] t4_cov_raw_index0={2'b10,1'b0,raw_memory};
    // t4_cov_raw_index1 保存表或队列的索引，须配合有效位与对应所有者使用。
    // t4_cov_raw_index1 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {2'b10,1'b1,raw_memory}；复制大括号表示重复位域，不是独立队列元素。
    wire [3:0] t4_cov_raw_index1={2'b10,1'b1,raw_memory};
    // t4_cov_jalr0 的资格组合为 ex_valid0&&ex_instruction0[6:0]==7'b1100111&&ex_instruction0[14:12]==0。
    wire t4_cov_jalr0=ex_valid0&&ex_instruction0[6:0]==7'b1100111&&ex_instruction0[14:12]==0;
    // t4_cov_jalr1 的资格组合为 ex_valid1&&ex_instruction1[6:0]==7'b1100111&&ex_instruction1[14:12]==0。
    wire t4_cov_jalr1=ex_valid1&&ex_instruction1[6:0]==7'b1100111&&ex_instruction1[14:12]==0;
    // JALR's sign-extended I immediate has these same low two bits.
    // t4_cov_jalr_sum0 按 ex_left0[1:0]+ex_instruction0[21:20] 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [1:0] t4_cov_jalr_sum0=ex_left0[1:0]+ex_instruction0[21:20];
    // t4_cov_jalr_sum1 按 ex_left1[1:0]+ex_instruction1[21:20] 计算，运算位宽与有无符号以原声明和显式扩展为准。
    wire [1:0] t4_cov_jalr_sum1=ex_left1[1:0]+ex_instruction1[21:20];
    // t4_cov_jalr_index0 保存表或队列的索引，须配合有效位与对应所有者使用。
    // t4_cov_jalr_index0 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {1'b0,(t4_cov_origin0==2),ex_left0[1:0],ex_instruction0[21:20]}；复制大括号表示重复位域，不是独立队列元素。
    wire [5:0] t4_cov_jalr_index0={1'b0,(t4_cov_origin0==2),ex_left0[1:0],ex_instruction0[21:20]};
    // t4_cov_jalr_index1 保存表或队列的索引，须配合有效位与对应所有者使用。
    // t4_cov_jalr_index1 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {1'b1,(t4_cov_origin1==2),ex_left1[1:0],ex_instruction1[21:20]}；复制大括号表示重复位域，不是独立队列元素。
    wire [5:0] t4_cov_jalr_index1={1'b1,(t4_cov_origin1==2),ex_left1[1:0],ex_instruction1[21:20]};

    always @(posedge clk)begin
        if(reset)begin
            t4_cov_origin0<=0;t4_cov_origin1<=0;
            t4_cov_prev_hold<=0;t4_cov_release_pending<=0;
            t4_cov_event_seen<=0;t4_cov_jalr_seen<=0;
        end else begin
            // Mirror the ORIGINAL capture priority: queued issue follows
            // dispatch. Recovery may update private payload but kills validity.
            if(dispatch_ex0>=0)t4_cov_origin0<=1;
            if(dispatch_ex1>=0)t4_cov_origin1<=1;
            if(issue_present0)t4_cov_origin0<=2;
            if(issue_present1)t4_cov_origin1<=2;

            // 恢复或冲刷条件 if(ex_hold&&!recovery&&t4_cov_capture1&&!t4_cov_event_seen[t4_cov_hold1_index]) 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(ex_hold&&!recovery&&t4_cov_capture1&&!t4_cov_event_seen[t4_cov_hold1_index])begin
                t4_cov_event_seen[t4_cov_hold1_index]<=1'b1;
                if(issue_present1)$display("COVERAGE TOPT4_CAPTURE event=hold_ex1_capture origin=queued");
                else $display("COVERAGE TOPT4_CAPTURE event=hold_ex1_capture origin=dispatch");
            end
            if(ex_hold&&ex_valid1&&!t4_cov_event_seen[12])begin
                t4_cov_event_seen[12]<=1'b1;
                $display("COVERAGE TOPT4_CAPTURE event=hold_ex1_valid");
            end
            if(t4_cov_prev_hold&&ex_hold&&!t4_cov_event_seen[2])begin
                t4_cov_event_seen[2]<=1'b1;
                $display("COVERAGE TOPT4_CAPTURE event=consecutive_hold");
            end
            // 恢复或冲刷条件 if(ex_hold&&recovery&&!t4_cov_event_seen[3]) 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(ex_hold&&recovery&&!t4_cov_event_seen[3])begin
                t4_cov_event_seen[3]<=1'b1;
                $display("COVERAGE TOPT4_CAPTURE event=hold_recovery");
            end

            // A recovery terminates the held owner rather than releasing it
            // into a new capture. Track normal release until the FIRST new
            // lane-0 capture; delayed=1 means at least one intervening bubble.
            if(t4_cov_released)t4_cov_release_pending<=1'b1;
            // 恢复或冲刷条件 if(recovery)t4_cov_release_pending<=1'b0; 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(recovery)t4_cov_release_pending<=1'b0;
            else if((t4_cov_release_pending||t4_cov_released)&&!ex_hold&&t4_cov_capture0)begin
                t4_cov_release_pending<=1'b0;
                if(!t4_cov_event_seen[t4_cov_release_index])begin
                    t4_cov_event_seen[t4_cov_release_index]<=1'b1;
                    if(issue_present0)$display("COVERAGE TOPT4_CAPTURE event=release_capture lane=0 origin=queued delayed=%0d",t4_cov_release_pending);
                    else $display("COVERAGE TOPT4_CAPTURE event=release_capture lane=0 origin=dispatch delayed=%0d",t4_cov_release_pending);
                end
            end
            t4_cov_prev_hold<=ex_hold&&!recovery;

            // 恢复或冲刷条件 if(issue_present0&&!recovery&&!t4_cov_event_seen[t4_cov_raw_index0]) 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(issue_present0&&!recovery&&!t4_cov_event_seen[t4_cov_raw_index0])begin
                t4_cov_event_seen[t4_cov_raw_index0]<=1'b1;
                $display("COVERAGE TOPT4_CAPTURE event=queued_raw lane=0 raw_memory=%0d",raw_memory);
            end
            // 恢复或冲刷条件 if(issue_present1&&!recovery&&!t4_cov_event_seen[t4_cov_raw_index1]) 控制下列状态更新，旧事务的处理不能当成新请求接受。
            if(issue_present1&&!recovery&&!t4_cov_event_seen[t4_cov_raw_index1])begin
                t4_cov_event_seen[t4_cov_raw_index1]<=1'b1;
                $display("COVERAGE TOPT4_CAPTURE event=queued_raw lane=1 raw_memory=%0d",raw_memory);
            end

            // Observe the CURRENT EX owner, not the new proposal at this edge.
            // These are valid-EX events, not retire events; fault/recovery may
            // prevent a packet from retiring. No trap stimulus is introduced.
            if(t4_cov_jalr0&&(t4_cov_origin0==1||t4_cov_origin0==2)&&!t4_cov_jalr_seen[t4_cov_jalr_index0])begin
                t4_cov_jalr_seen[t4_cov_jalr_index0]<=1'b1;
                if(t4_cov_origin0==1)$display("COVERAGE TOPT4_JALR lane=0 origin=dispatch left_low=%0d imm_low=%0d sum_bit1=%0d integer_fault=%0d",ex_left0[1:0],ex_instruction0[21:20],t4_cov_jalr_sum0[1],integer_fault0);
                else $display("COVERAGE TOPT4_JALR lane=0 origin=queued left_low=%0d imm_low=%0d sum_bit1=%0d integer_fault=%0d",ex_left0[1:0],ex_instruction0[21:20],t4_cov_jalr_sum0[1],integer_fault0);
            end
            if(t4_cov_jalr1&&(t4_cov_origin1==1||t4_cov_origin1==2)&&!t4_cov_jalr_seen[t4_cov_jalr_index1])begin
                t4_cov_jalr_seen[t4_cov_jalr_index1]<=1'b1;
                if(t4_cov_origin1==1)$display("COVERAGE TOPT4_JALR lane=1 origin=dispatch left_low=%0d imm_low=%0d sum_bit1=%0d integer_fault=%0d",ex_left1[1:0],ex_instruction1[21:20],t4_cov_jalr_sum1[1],integer_fault1);
                else $display("COVERAGE TOPT4_JALR lane=1 origin=queued left_low=%0d imm_low=%0d sum_bit1=%0d integer_fault=%0d",ex_left1[1:0],ex_instruction1[21:20],t4_cov_jalr_sum1[1],integer_fault1);
            end
        end
    end
`endif

endmodule


// Remove zero or one selected owner from a blocker bitmap. The caller ensures
// selected_release is one-hot-or-zero. With at least two blockers, removing
// one cannot empty the set. With exactly one blocker, only its membership in
// the selected candidate matters. This separates the registered ROB/tag/age
// cone from the late issue grant; no issue selection feeds the 16-way summary.
module rv32_order_release_filter(
    input [15:0] blockers,
    input [3:0] selected_release,
    input [15:0] selected_tags,
    output waiting
);
    wire [7:0] pair_any,pair_many;
    wire [3:0] quad_any,quad_many;
    wire [1:0] half_any,half_many;
    wire [3:0] selected_hit;
    genvar bit_pair,quad,half,candidate;
    generate
        for(bit_pair=0;bit_pair<8;bit_pair=bit_pair+1)begin:pair_summary
            assign pair_any[bit_pair]=|blockers[bit_pair*2+:2];
            assign pair_many[bit_pair]=&blockers[bit_pair*2+:2];
        end
        for(quad=0;quad<4;quad=quad+1)begin:quad_summary
            assign quad_any[quad]=|pair_any[quad*2+:2];
            assign quad_many[quad]=(|pair_many[quad*2+:2])||(&pair_any[quad*2+:2]);
        end
        for(half=0;half<2;half=half+1)begin:half_summary
            assign half_any[half]=|quad_any[half*2+:2];
            assign half_many[half]=(|quad_many[half*2+:2])||(&quad_any[half*2+:2]);
        end
        for(candidate=0;candidate<4;candidate=candidate+1)begin:candidate_membership
            assign selected_hit[candidate]=selected_release[candidate]&&blockers[selected_tags[candidate*4+:4]];
        end
    endgenerate
    // any_blocker 对 |half_any 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire any_blocker=|half_any;
    // multiple_blockers 的资格组合为 (|half_many)||(&half_any)。
    wire multiple_blockers=(|half_many)||(&half_any);
    assign waiting=multiple_blockers||(any_blocker&&!(|selected_hit));
endmodule
