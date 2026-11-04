// Virtual core to physical cache bridge. Original RV32 implementation.
// Page walks share the physical D-cache port: dirty cached PTEs are visible.
// 此桥把 CPU 虚拟取指和数据访问转换为 cache 可接受的物理事务。
// 取指与数据路径分别保存 satp 特权及权限控制快照，避免在途请求换用新上下文。
// 取指包中的两个 32 位字依次翻译，因此跨页时可分别报告访问错误和页故障。
// ITLB PTW DTLB PTW 及原子数据路径共享物理 D-cache 端口。
// 仲裁所有者一直保留到响应被消费，响应返回时不能按新的请求选择结果。
// 原子读改写锁定期间阻止页表读插入，保持单 hart 内原子序列的完整性。
// 页表访问必须落在 RAM 范围；非法 PTE 地址不得触发 MMIO 读副作用。
// SFENCE 先挂起并停止新接收，待现有事务全部空闲后再清空翻译状态。
// 34 位 Sv32 物理地址超出当前 32 位平台能力时返回错误，不静默截断。
module rv32_linux_memory_bridge #(
 parameter [31:0] RAM_BASE=32'h80000000, RAM_LIMIT=32'h84000000
)(
 input clk,reset,sfence,reservation_kill,
 input [1:0] privilege_mode,mmu_mpp,
 // mmu_satp 保存页表根 ASID 及翻译模式快照，不能随新上下文改写在途请求。
 input [31:0] mmu_satp,input mmu_sum,mmu_mxr,mmu_mprv,
 // c_i_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input c_i_valid,output c_i_ready,input [31:0] c_i_addr,
 // c_i_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output reg c_i_rsp_valid,input c_i_rsp_ready,output reg [63:0] c_i_rsp_data,
 // c_i_rsp_error 保存访问或译码错误标志，不能被正常数据值掩盖。
 output reg [1:0] c_i_rsp_error,c_i_rsp_pagefault,
 // c_d_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input c_d_valid,output c_d_ready,input [31:0] c_d_addr,c_d_wdata,
 // c_d_wstrb 保存逐字节写使能，未使能的字节保持原值。
 input c_d_write,input [3:0] c_d_wstrb,input [1:0] c_d_size,
 input c_d_atomic,input [4:0] c_d_amo,
 // c_d_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output reg c_d_rsp_valid,input c_d_rsp_ready,output reg [31:0] c_d_rsp_data,
 // c_d_rsp_error 保存访问或译码错误标志，不能被正常数据值掩盖。
 output reg c_d_rsp_error,c_d_rsp_pagefault,
 // p_i_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output p_i_valid,input p_i_ready,output [31:0] p_i_addr,
 // p_i_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input p_i_rsp_valid,output p_i_rsp_ready,input [63:0] p_i_rsp_data,input [1:0] p_i_rsp_error,
 // p_d_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 output p_d_valid,input p_d_ready,output [31:0] p_d_addr,p_d_wdata,
 // p_d_wstrb 保存逐字节写使能，未使能的字节保持原值。
 output p_d_write,output [3:0] p_d_wstrb,output [1:0] p_d_size,
 // p_d_rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 input p_d_rsp_valid,output p_d_rsp_ready,input [31:0] p_d_rsp_data,input p_d_rsp_error,
 output busy,flush_busy
);
 localparam IDLE=0, TRANSLATE=1, TRANSLATE_WAIT=2, PHYSICAL=3, PHYSICAL_WAIT=4;
 reg [2:0] is,ds;
 // flush_pending 已收到但尚未执行的翻译冲刷，等待所有在途事务安全排空。
 reg flush_pending;
 reg [31:0] iva,ipa,dva,dpa,ddata;
 reg iword,dwrite,datomic;
 reg [3:0] dstrb;reg [1:0] dsize;reg [4:0] damo;
 reg [31:0] isatp,dsatp;reg [1:0] ipriv,dpriv,impp,dmpp;
 reg isum,imxr,imprv,dsum,dmxr,dmprv;
 // im_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
 wire im_ready,im_valid,im_fault,im_busy,dm_ready,dm_valid,dm_fault,dm_busy;
 wire [33:0] im_pa,dm_pa;
 // im_cause 保存异常原因编码，用于决定精确异常入口及 CSR 记录。
 wire [4:0] im_cause,dm_cause;
 // im_tval 保存异常相关的地址或指令值，用于定位故障来源。
 wire [31:0] im_tval,dm_tval;
 wire iw_req,iw_ready,iw_rsp,iw_rsp_ready,iw_error;
 wire dw_req,dw_ready,dw_rsp,dw_rsp_ready,dw_error;
 // iw_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
 wire [33:0] iw_addr,dw_addr;
 wire [31:0] iw_data,dw_data;
 // am_req_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
 wire am_req_ready,am_rsp_valid,am_rsp_error,am_lock;
 wire [31:0] am_rsp_data;
 // am_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
 wire am_valid,am_ready,am_write,am_rsp_in_valid,am_rsp_in_ready,am_rsp_in_error;
 // am_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
 wire [31:0] am_addr,am_wdata,am_rsp_in_data;
 // am_wstrb 保存逐字节写使能，未使能的字节保持原值。
 wire [3:0] am_wstrb;wire [1:0] am_size;
 reg arb_busy,arb_error;
 // arb_owner 已经接受的物理事务所有者，直到响应消费之前保持归属不变。
 reg [1:0] arb_owner;
 reg [1:0] selection;
 // all_idle 取指 数据 页表遍历 原子及响应槽全部空闲的合取条件。
 // all_idle 的资格组合为 (is==IDLE)&&(ds==IDLE)&&!c_i_rsp_valid&&!c_d_rsp_valid&&!arb_busy&&!im_busy&&!dm_busy&&!am_lock&&!am_rsp_valid。
 // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
 wire all_idle=(is==IDLE)&&(ds==IDLE)&&!c_i_rsp_valid&&!c_d_rsp_valid&&!arb_busy&&!im_busy&&!dm_busy&&!am_lock&&!am_rsp_valid;
 // flush_now 挂起冲刷与全空闲同时满足的真正冲刷时机。
 // flush_now 的资格组合为 flush_pending&&all_idle。
 wire flush_now=flush_pending&&all_idle;
 // flush_busy 的资格组合为 flush_pending||sfence。
 assign flush_busy=flush_pending||sfence;
 // busy 的资格组合为 !all_idle||flush_busy。
 assign busy=!all_idle||flush_busy;
 // c_i_ready 的资格组合为 !reset&&!flush_busy&&is==IDLE&&!c_i_rsp_valid。
 assign c_i_ready=!reset&&!flush_busy&&is==IDLE&&!c_i_rsp_valid;
 // c_d_ready 的资格组合为 !reset&&!flush_busy&&ds==IDLE&&!c_d_rsp_valid。
 assign c_d_ready=!reset&&!flush_busy&&ds==IDLE&&!c_d_rsp_valid;
 // p_i_valid 的资格组合为 !reset&&is==PHYSICAL。
 assign p_i_valid=!reset&&is==PHYSICAL;
 // p_i_addr 连接到 ipa，两者在此路径上保持字段对应。
 assign p_i_addr=ipa;
 // p_i_rsp_ready 由比较式 is==PHYSICAL_WAIT 产生；该结果是条件判断，不是被比较的数据。
 assign p_i_rsp_ready=is==PHYSICAL_WAIT;
 // data_access 按 datomic 进行来源选择。
 // 真分支取 (damo==2 ? 2'd1 : 2'd2)；其余情况取 (dwrite ? 2'd2 : 2'd1)。
 wire [1:0] data_access=datomic ? (damo==2 ? 2'd1 : 2'd2) : (dwrite ? 2'd2 : 2'd1);
 // 子模块 rv32_sv32_mmu 的职责：Sv32 翻译器一次持有一个请求，输出物理地址 页故障原因及原始虚拟地址。
 // 下列命名端口把本层信号连接到该模块，参数覆盖以实例中的原代码为准。
 rv32_sv32_mmu itlb(
 .clk(clk),.reset(reset),.flush(flush_now),.req_valid(is==TRANSLATE),.req_ready(im_ready),
 .req_vaddr(iva),.req_satp(isatp),.req_access(2'd0),.req_priv(ipriv),.req_mprv(imprv),.req_mpp(impp),.req_sum(isum),.req_mxr(imxr),
 .rsp_valid(im_valid),.rsp_ready(is==TRANSLATE_WAIT),.rsp_paddr(im_pa),.rsp_fault(im_fault),.rsp_cause(im_cause),.rsp_tval(im_tval),
 .ptw_req_valid(iw_req),.ptw_req_ready(iw_ready),.ptw_req_addr(iw_addr),.ptw_rsp_valid(iw_rsp),.ptw_rsp_ready(iw_rsp_ready),.ptw_rsp_data(iw_data),.ptw_rsp_error(iw_error),.busy(im_busy));
 rv32_sv32_mmu dtlb(
 .clk(clk),.reset(reset),.flush(flush_now),.req_valid(ds==TRANSLATE),.req_ready(dm_ready),
 .req_vaddr(dva),.req_satp(dsatp),.req_access(data_access),.req_priv(dpriv),.req_mprv(dmprv),.req_mpp(dmpp),.req_sum(dsum),.req_mxr(dmxr),
 .rsp_valid(dm_valid),.rsp_ready(ds==TRANSLATE_WAIT),.rsp_paddr(dm_pa),.rsp_fault(dm_fault),.rsp_cause(dm_cause),.rsp_tval(dm_tval),
 .ptw_req_valid(dw_req),.ptw_req_ready(dw_ready),.ptw_req_addr(dw_addr),.ptw_rsp_valid(dw_rsp),.ptw_rsp_ready(dw_rsp_ready),.ptw_rsp_data(dw_data),.ptw_rsp_error(dw_error),.busy(dm_busy));
 // 子模块 rv32_atomic_memory 的职责：原子单元位于地址翻译之后，对物理地址实现 LR SC 及 RV32 AMO 操作。
 rv32_atomic_memory atomic_unit(
 .clk(clk),.reset(reset),.reservation_kill(reservation_kill||flush_now),
 .req_valid(ds==PHYSICAL),.req_ready(am_req_ready),.req_addr(dpa),.req_wdata(ddata),.req_write(dwrite),.req_wstrb(dstrb),.req_size(dsize),.req_atomic(datomic),.req_amo(damo),
 .rsp_valid(am_rsp_valid),.rsp_ready(ds==PHYSICAL_WAIT),.rsp_data(am_rsp_data),.rsp_error(am_rsp_error),
 .mem_valid(am_valid),.mem_ready(am_ready),.mem_addr(am_addr),.mem_wdata(am_wdata),.mem_write(am_write),.mem_wstrb(am_wstrb),.mem_size(am_size),
 .mem_rsp_valid(am_rsp_in_valid),.mem_rsp_ready(am_rsp_in_ready),.mem_rsp_data(am_rsp_in_data),.mem_rsp_error(am_rsp_in_error),.lock(am_lock));
 // One owner through response retirement; atomic owner excludes walks during RMW.
 always @* begin
 selection=0;
 if(!arb_busy)begin
 if(am_valid)selection=3;
 else if(!am_lock&&dw_req)selection=2;
 else if(!am_lock&&iw_req)selection=1;
 end end
 // Page tables are RAM-only: a malformed SATP/PTE must never read MMIO.
 // iw_bad 的资格组合为 (iw_addr < {2'b0,RAM_BASE}) || (iw_addr > ({2'b0,RAM_LIMIT}-34'd4))。
 wire iw_bad=(iw_addr < {2'b0,RAM_BASE}) || (iw_addr > ({2'b0,RAM_LIMIT}-34'd4));
 // dw_bad 的资格组合为 (dw_addr < {2'b0,RAM_BASE}) || (dw_addr > ({2'b0,RAM_LIMIT}-34'd4))。
 wire dw_bad=(dw_addr < {2'b0,RAM_BASE}) || (dw_addr > ({2'b0,RAM_LIMIT}-34'd4));
 // selected_high 的资格组合为 (selection==1&&iw_bad)||(selection==2&&dw_bad)。
 wire selected_high=(selection==1&&iw_bad)||(selection==2&&dw_bad);
 // p_d_valid 的资格组合为 !reset&&selection!=0&&!selected_high。
 assign p_d_valid=!reset&&selection!=0&&!selected_high;
 // p_d_addr 按 selection==3 选择候选来源；各分支结果仍属于当前组合路径。
 // p_d_addr 按 selection==3 进行来源选择。
 // 真分支取 am_addr；其余情况取 (selection==2?dw_addr[31:0]:iw_addr[31:0])。
 assign p_d_addr=selection==3?am_addr:(selection==2?dw_addr[31:0]:iw_addr[31:0]);
 // p_d_wdata 按 selection==3 选择候选来源；各分支结果仍属于当前组合路径。
 assign p_d_wdata=selection==3?am_wdata:0;
 assign p_d_write=selection==3&&am_write;
 // p_d_wstrb 按 selection==3 选择候选来源；各分支结果仍属于当前组合路径。
 assign p_d_wstrb=selection==3?am_wstrb:4'h0;
 // p_d_size 按 selection==3 选择候选来源；各分支结果仍属于当前组合路径。
 assign p_d_size=selection==3?am_size:2'd2;
 assign iw_ready=!reset&&selection==1&&(selected_high||p_d_ready);
 assign dw_ready=!reset&&selection==2&&(selected_high||p_d_ready);
 assign am_ready=!reset&&selection==3&&p_d_ready;
 // selected_rsp_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
 // selected_rsp_ready 按 arb_owner==1 进行来源选择。
 // 真分支取 iw_rsp_ready；其余情况取 (arb_owner==2?dw_rsp_ready:am_rsp_in_ready)。
 wire selected_rsp_ready=arb_owner==1?iw_rsp_ready:(arb_owner==2?dw_rsp_ready:am_rsp_in_ready);
 assign p_d_rsp_ready=arb_busy&&!arb_error&&selected_rsp_ready;
 assign iw_rsp=arb_busy&&arb_owner==1&&(arb_error||p_d_rsp_valid);
 assign dw_rsp=arb_busy&&arb_owner==2&&(arb_error||p_d_rsp_valid);
 assign am_rsp_in_valid=arb_busy&&arb_owner==3&&(arb_error||p_d_rsp_valid);
 assign iw_data=p_d_rsp_data;assign dw_data=p_d_rsp_data;assign am_rsp_in_data=p_d_rsp_data;
 assign iw_error=arb_error||p_d_rsp_error;assign dw_error=arb_error||p_d_rsp_error;assign am_rsp_in_error=arb_error||p_d_rsp_error;
 always @(posedge clk)begin
 // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
 if(reset)begin
 is<=IDLE;ds<=IDLE;flush_pending<=0;c_i_rsp_valid<=0;c_i_rsp_data<=0;c_i_rsp_error<=0;c_i_rsp_pagefault<=0;
 c_d_rsp_valid<=0;c_d_rsp_data<=0;c_d_rsp_error<=0;c_d_rsp_pagefault<=0;
 arb_busy<=0;arb_owner<=0;arb_error<=0;
 iva<=0;ipa<=0;dva<=0;dpa<=0;ddata<=0;iword<=0;dwrite<=0;datomic<=0;dstrb<=0;dsize<=0;damo<=0;
 isatp<=0;dsatp<=0;ipriv<=3;dpriv<=3;impp<=0;dmpp<=0;isum<=0;imxr<=0;imprv<=0;dsum<=0;dmxr<=0;dmprv<=0;
 end else begin
 // 恢复或冲刷条件 if(sfence)flush_pending<=1;else if(flush_now)flush_pending<=0; 控制下列状态更新，旧事务的处理不能当成新请求接受。
 if(sfence)flush_pending<=1;else if(flush_now)flush_pending<=0;
 // 本分支处理握手条件 c_i_rsp_valid 与 c_i_rsp_ready；仅满足当前条件时推进下述事务。
 if(c_i_rsp_valid&&c_i_rsp_ready)c_i_rsp_valid<=0;
 // 本分支处理握手条件 c_d_rsp_valid 与 c_d_rsp_ready；仅满足当前条件时推进下述事务。
 if(c_d_rsp_valid&&c_d_rsp_ready)c_d_rsp_valid<=0;
 if(!arb_busy&&selection!=0&&(selected_high||p_d_ready))begin arb_busy<=1;arb_owner<=selection;arb_error<=selected_high;end
 else if(arb_busy&&(arb_error||p_d_rsp_valid)&&selected_rsp_ready)begin arb_busy<=0;arb_error<=0;end
 case(is)
 IDLE:if(c_i_valid&&c_i_ready)begin
 iva<=c_i_addr;iword<=0;c_i_rsp_data<=0;c_i_rsp_error<=0;c_i_rsp_pagefault<=0;
 isatp<=mmu_satp;ipriv<=privilege_mode;impp<=mmu_mpp;isum<=mmu_sum;imxr<=mmu_mxr;imprv<=mmu_mprv;is<=TRANSLATE;
 end
 TRANSLATE:if(im_ready)is<=TRANSLATE_WAIT;
 TRANSLATE_WAIT:if(im_valid)begin
 if(im_fault|| |im_pa[33:32])begin
 c_i_rsp_error[iword]<=!im_fault||im_cause!=12;c_i_rsp_pagefault[iword]<=im_fault&&im_cause==12;
 if(iword)begin is<=IDLE;c_i_rsp_valid<=1;end
 else begin iword<=1;iva<=iva+4;is<=TRANSLATE;end
 end else begin ipa<=im_pa[31:0];is<=PHYSICAL;end
 end
 PHYSICAL:if(p_i_ready)is<=PHYSICAL_WAIT;
 PHYSICAL_WAIT:if(p_i_rsp_valid)begin
 if(iword)c_i_rsp_data[63:32]<=p_i_rsp_data[31:0];else c_i_rsp_data[31:0]<=p_i_rsp_data[31:0];
 c_i_rsp_error[iword]<=p_i_rsp_error[0];
 if(iword)begin is<=IDLE;c_i_rsp_valid<=1;end
 else begin iword<=1;iva<=iva+4;is<=TRANSLATE;end
 end
 default:is<=IDLE;
 endcase
 case(ds)
 IDLE:if(c_d_valid&&c_d_ready)begin
 dva<=c_d_addr;ddata<=c_d_wdata;dwrite<=c_d_write;dstrb<=c_d_wstrb;dsize<=c_d_size;datomic<=c_d_atomic;damo<=c_d_amo;
 dsatp<=mmu_satp;dpriv<=privilege_mode;dmpp<=mmu_mpp;dsum<=mmu_sum;dmxr<=mmu_mxr;dmprv<=mmu_mprv;
 c_d_rsp_error<=0;c_d_rsp_pagefault<=0;c_d_rsp_data<=0;ds<=TRANSLATE;
 end
 TRANSLATE:if(dm_ready)ds<=TRANSLATE_WAIT;
 TRANSLATE_WAIT:if(dm_valid)begin
 if(dm_fault|| |dm_pa[33:32] || (datomic&&(dm_pa[31:0]<RAM_BASE||dm_pa[31:0]>=RAM_LIMIT)))begin
 c_d_rsp_error<=!dm_fault||(dm_cause!=13&&dm_cause!=15);c_d_rsp_pagefault<=dm_fault&&(dm_cause==13||dm_cause==15);
 ds<=IDLE;c_d_rsp_valid<=1;
 end else begin dpa<=dm_pa[31:0];ds<=PHYSICAL;end
 end
 PHYSICAL:if(am_req_ready)ds<=PHYSICAL_WAIT;
 PHYSICAL_WAIT:if(am_rsp_valid)begin c_d_rsp_data<=am_rsp_data;c_d_rsp_error<=am_rsp_error;ds<=IDLE;c_d_rsp_valid<=1;end
 default:ds<=IDLE;
 endcase
 end end
endmodule
