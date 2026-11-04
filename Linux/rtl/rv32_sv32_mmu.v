// RV32 Sv32 translator, original implementation, 2026.
// Svade: missing A/D raises a page fault; this block NEVER writes page tables.
// PTW MUST be routed through a coherent physical-memory port (including PMP/PMA).
// One request in flight. flush kills the request; an accepted PTW read is drained.
// Full SFENCE.VMA overflush is intentionally used, including global entries.
// Sv32 翻译器一次持有一个请求，输出物理地址 页故障原因及原始虚拟地址。
// 实板 ITLB 与 DTLB 各实例化一份本模块，默认每份 8 项。
// Bare 模式或有效特权为 M 时直接使用零扩展物理地址。
// MPRV 只影响 M 模式数据访问，不影响取指；权限检查还使用 SUM 和 MXR 快照。
// TLB 命中仍需按当前访问类型检查读 写 执行和用户权限。
// 未命中从 satp 指定根页表开始读取 PTE，支持 4 KiB 页与 4 MiB 超级页。
// 超级页要求低位 PPN 对齐；无效编码及非法非叶项会产生页故障。
// 采用 Svade 行为：A 或所需 D 位缺失时产生页故障，本模块不自动写页表。
// flush 使全部 TLB 项失效，包括 global 项；已接受的页表读通过 DRAIN 排空。
// PTW 接口只发物理读，RAM 范围及与原子事务的互斥由上一级桥接器保证。
module rv32_sv32_mmu #(parameter TLB_ENTRIES=8)(
 input clk, reset, flush,
 // req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input req_valid, output req_ready,
 // req_satp 保存页表根 ASID 及翻译模式快照，不能随新上下文改写在途请求。
 input [31:0] req_vaddr, req_satp,
 input [1:0] req_access, req_priv, // access: 0 fetch, 1 load, 2 store/AMO
 input req_mprv, input [1:0] req_mpp, input req_sum, req_mxr,
 // rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output reg rsp_valid, input rsp_ready,
 output reg [33:0] rsp_paddr,
 // rsp_fault 保存异常资格，须携带对应指令或请求身份交给后续处理。
 output reg rsp_fault, output reg [4:0] rsp_cause,
 // rsp_tval 保存异常相关的地址或指令值，用于定位故障来源。
 output reg [31:0] rsp_tval,
 // ptw_req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output ptw_req_valid, input ptw_req_ready, output [33:0] ptw_req_addr,
 // ptw_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input ptw_rsp_valid, output ptw_rsp_ready,
 // ptw_rsp_error 保存访问或译码错误标志，不能被正常数据值掩盖。
 input [31:0] ptw_rsp_data, input ptw_rsp_error,
 output busy
);
 localparam IDLE=3'd0, LOOKUP=3'd1, READ_REQ=3'd2, READ_WAIT=3'd3, DRAIN=3'd4;
 // state 保存协议或执行状态，决定本周期允许的阶段与握手动作。
 reg [2:0] state;
 reg [31:0] va;
 // satp 保存页表根 ASID 及翻译模式快照，不能随新上下文改写在途请求。
 reg [30:0] satp;
 reg [1:0] access_kind, privilege;
 reg sum_bit, mxr_bit, level, global_path;
 // pte_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
 reg [33:0] pte_addr;
 // tlb_valid 属于TLB 表项，保存有效资格，标识该项是否属于当前仍可使用的事务。
 // 命中仍需检查地址 ASID 或 global 及本次访问权限。
 reg tlb_valid[0:TLB_ENTRIES-1];
 reg [19:0] tlb_vpn[0:TLB_ENTRIES-1];
 reg [8:0] tlb_asid[0:TLB_ENTRIES-1];
 reg [31:0] tlb_pte[0:TLB_ENTRIES-1];
 reg tlb_superpage[0:TLB_ENTRIES-1], tlb_global[0:TLB_ENTRIES-1];
 integer replacement, j;
 reg hit_found;
 reg [31:0] hit_pte;
 reg hit_level;
 // effective_priv 按 MPRV MPP 和访问类别计算的有效特权，取指不受 MPRV 数据规则影响。
 // effective_priv 按 (req_priv==2'd3 && req_mprv && req_access!=0) 进行来源选择。
 // 真分支取 req_mpp；其余情况取 req_priv。
 wire [1:0] effective_priv = (req_priv==2'd3 && req_mprv && req_access!=0) ? req_mpp : req_priv;
 // req_ready 的资格组合为 state==IDLE && !rsp_valid && !flush && !reset。
 // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
 assign req_ready = state==IDLE && !rsp_valid && !flush && !reset;
 // ptw_req_valid 的资格组合为 state==READ_REQ && !flush && !reset。
 assign ptw_req_valid = state==READ_REQ && !flush && !reset;
 // ptw_req_addr 连接到 pte_addr，两者在此路径上保持字段对应。
 assign ptw_req_addr = pte_addr;
 // ptw_rsp_ready 的资格组合为 (state==READ_WAIT || state==DRAIN) && !reset。
 assign ptw_rsp_ready = (state==READ_WAIT || state==DRAIN) && !reset;
 // busy 的资格组合为 state!=IDLE || rsp_valid。
 assign busy = state!=IDLE || rsp_valid;
 // Reserved nonleaf U/A/D bits must be zero. G is inherited by descendants.
 // 检查 PTE 有效编码 A D 用户权限及读写执行许可，使用请求时保存的 SUM MXR。
 function permission_ok;
 /* verilator lint_off UNUSEDSIGNAL */
 input [7:0] pte;
 /* verilator lint_on UNUSEDSIGNAL */
 input [1:0] acc, priv;
 input sum_v,mxr_v;
 begin
 // permission_ok 的资格组合为 pte[0] && !(pte[2]&&!pte[1]) && pte[6] && (acc!=2 || pte[7])。
 permission_ok = pte[0] && !(pte[2]&&!pte[1]) && pte[6] && (acc!=2 || pte[7]);
 if(priv==0 && !pte[4]) permission_ok=0;
 if(priv==1 && pte[4] && (acc==0 || !sum_v)) permission_ok=0;
 if(acc==0 && !pte[3]) permission_ok=0;
 if(acc==1 && !(pte[1] || (mxr_v && pte[3]))) permission_ok=0;
 if(acc==2 && !pte[2]) permission_ok=0;
 if(acc==3 || priv==2) permission_ok=0;
 end endfunction
 // 把取指 读 写访问类型映射为页故障异常号 12 13 15。
 function [4:0] page_cause;
 input [1:0] acc;
 begin case(acc) 0:page_cause=12; 1:page_cause=13; default:page_cause=15; endcase end
 endfunction
 // 把物理访问失败映射为取指 读 写访问错误号 1 5 7。
 function [4:0] access_cause;
 input [1:0] acc;
 begin case(acc) 0:access_cause=1; 1:access_cause=5; default:access_cause=7; endcase end
 endfunction
 // 按普通页或超级页拼接 PPN 与页内偏移，不通过写页表修复权限。
 function [33:0] translated_pa;
 /* verilator lint_off UNUSEDSIGNAL */
 // addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
 input [31:0] pte, addr;
 /* verilator lint_on UNUSEDSIGNAL */
 input superpage;
 begin translated_pa = superpage ? {pte[31:20],addr[21:0]} : {pte[31:10],addr[11:0]}; end
 endfunction
 always @* begin
 hit_found=0; hit_pte=0; hit_level=0;
 for(integer k=0;k<TLB_ENTRIES;k=k+1) begin
 if(tlb_valid[k] && (tlb_global[k] || tlb_asid[k]==satp[30:22]) &&
 tlb_vpn[k][19:10]==va[31:22] && (tlb_superpage[k] || tlb_vpn[k][9:0]==va[21:12])) begin
 hit_found=1;hit_pte=tlb_pte[k];hit_level=tlb_superpage[k];
 end end
 end
 always @(posedge clk) begin
 // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
 if(reset) begin
 // state 在此时钟更新路径捕获 IDLE，该更新仍受外层条件与后续同块赋值优先级限定。
 // 本时钟边界的 state 捕获 IDLE，两者在此路径上保持字段对应。
 state<=IDLE; rsp_valid<=0;rsp_paddr<=0;rsp_fault<=0;rsp_cause<=0;rsp_tval<=0;
 va<=0;satp<=0;access_kind<=0;privilege<=3;sum_bit<=0;mxr_bit<=0;
 level<=0;global_path<=0;pte_addr<=0;replacement<=0;
 for(j=0;j<TLB_ENTRIES;j=j+1) begin tlb_valid[j]<=0;tlb_vpn[j]<=0;tlb_asid[j]<=0;tlb_pte[j]<=0;tlb_superpage[j]<=0;tlb_global[j]<=0;end
 // 恢复或冲刷条件 end else if(flush)  控制下列状态更新，旧事务的处理不能当成新请求接受。
 end else if(flush) begin
 for(j=0;j<TLB_ENTRIES;j=j+1) tlb_valid[j]<=0;
 rsp_valid<=0;
 if((state==READ_WAIT || state==DRAIN) && !ptw_rsp_valid) state<=DRAIN;
 else state<=IDLE;
 end else begin
 // 本分支处理握手条件 rsp_valid 与 rsp_ready；仅满足当前条件时推进下述事务。
 if(rsp_valid && rsp_ready) rsp_valid<=0;
 case(state)
 IDLE: if(req_valid && req_ready) begin
 // 本时钟边界的 va 捕获 req_vaddr，两者在此路径上保持字段对应。
 va<=req_vaddr;satp<=req_satp[30:0];access_kind<=req_access;privilege<=effective_priv;
 // 本时钟边界的 sum_bit 捕获 req_sum，两者在此路径上保持字段对应。
 sum_bit<=req_sum;mxr_bit<=req_mxr;
 rsp_fault<=0;rsp_cause<=0;rsp_tval<=req_vaddr;rsp_paddr<=0;
 if(!req_satp[31] || effective_priv==3) begin rsp_valid<=1;rsp_paddr<={2'b0,req_vaddr};end
 else state<=LOOKUP;
 end
 LOOKUP: begin
 if(hit_found) begin
 rsp_valid<=1;state<=IDLE;
 // rsp_fault 在此时钟更新路径捕获 !permission_ok(hit_pte[7:0],access_kind,privilege,sum_bit,mxr_bit)，该更新仍受外层条件与后续同块赋值优先级限定。
 // 本时钟边界的 rsp_fault 通过 !permission_ok(hit_pte[7:0],access_kind,privilege,sum_bit,mxr_bit) 查询对应字段；结果资格仍由调用点的有效条件限定。
 rsp_fault<=!permission_ok(hit_pte[7:0],access_kind,privilege,sum_bit,mxr_bit);
 // rsp_cause 按 permission_ok(hit_pte[7:0],access_kind,privilege,sum_bit,mxr_bit) 选择候选来源；各分支结果仍属于当前寄存边界。
 // 本时钟边界的 rsp_cause 按 permission_ok(hit_pte[7:0],access_kind,privilege,sum_bit,mxr_bit) 进行来源选择。
 // 真分支取 0；其余情况取 page_cause(access_kind)。
 rsp_cause<=permission_ok(hit_pte[7:0],access_kind,privilege,sum_bit,mxr_bit) ? 0 : page_cause(access_kind);
 rsp_paddr<=translated_pa(hit_pte,va,hit_level);
 end else begin
 pte_addr<={satp[21:0],12'b0}+{22'b0,va[31:22],2'b0};
 level<=1;global_path<=0;state<=READ_REQ;
 end end
 READ_REQ: if(ptw_req_ready) state<=READ_WAIT;
 READ_WAIT: if(ptw_rsp_valid) begin
 if(ptw_rsp_error) begin
 rsp_valid<=1;rsp_fault<=1;rsp_cause<=access_cause(access_kind);state<=IDLE;
 end else if(!ptw_rsp_data[0] || (!ptw_rsp_data[1] && ptw_rsp_data[2])) begin
 rsp_valid<=1;rsp_fault<=1;rsp_cause<=page_cause(access_kind);state<=IDLE;
 end else if(ptw_rsp_data[1] || ptw_rsp_data[3]) begin
 rsp_valid<=1;state<=IDLE;
 if(!permission_ok(ptw_rsp_data[7:0],access_kind,privilege,sum_bit,mxr_bit) || (level && ptw_rsp_data[19:10]!=0)) begin
 rsp_fault<=1;rsp_cause<=page_cause(access_kind);
 end else begin
 rsp_paddr<=translated_pa(ptw_rsp_data,va,level);rsp_fault<=0;rsp_cause<=0;
 tlb_valid[replacement]<=1;tlb_vpn[replacement]<=va[31:12];tlb_asid[replacement]<=satp[30:22];
 tlb_pte[replacement]<=ptw_rsp_data;tlb_superpage[replacement]<=level;
 tlb_global[replacement]<=global_path || ptw_rsp_data[5];
 if(replacement==TLB_ENTRIES-1)replacement<=0;else replacement<=replacement+1;
 end
 end else if(!level || ptw_rsp_data[7:6]!=0 || ptw_rsp_data[4]) begin
 rsp_valid<=1;rsp_fault<=1;rsp_cause<=page_cause(access_kind);state<=IDLE;
 end else begin
 pte_addr<={ptw_rsp_data[31:10],12'b0}+{22'b0,va[21:12],2'b0};
 level<=0;global_path<=global_path||ptw_rsp_data[5];state<=READ_REQ;
 end
 end
 DRAIN: if(ptw_rsp_valid) state<=IDLE;
 default: state<=IDLE;
 endcase
 end
 end
endmodule
