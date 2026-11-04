// [ARCH] 游戏 SoC 到 RV32 核和缓存的实际集成入口。
// [ARCH] 复位向量改为 0x10000000，核与缓存的可执行逻辑仍来自指定供体。
// [ARCH] I-cache 16 KiB、D-cache 8 KiB，预测参数以当前实例为准。
// [ARCH] 关闭供体单段地址守护，让分离代码/数据 SRAM 与 DDR 可合法访问。
// [ARCH] 缓存与非缓存数据路径复用下游端口，响应所有者保持到事务结束。
// [ARCH] 故障反馈与退休诊断独立，LED 不能替代完整软件状态观测。
// CPU/cache RTL is imported byte-for-byte from rv32_core_01 RV32CM120 I2W2.
// Direct core/cache connections equal the donor REGISTER_* = 0 integration.
// Board-only DATA_RAM_GUARD is disabled so the game data SRAM and DDR cache
// window are legal. SRAM and DDR adapters independently enforce their ranges.
module rv32_game_cpu_tile #(
 // [ARCH] ITCM_INIT_FILE：PDS 必须绑定匹配的 64 位代码 SRAM 初始化镜像。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 DTCM_INIT_FILE 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 parameter ITCM_INIT_FILE="",DTCM_INIT_FILE="",
 // [ARCH] DDR_BASE：后端 DDR 窗口基地址，先检查范围再转换为控制器地址。
 parameter logic [31:0] DDR_BASE=32'h80000000,
 // [ARCH] DDR_BYTES：后端可访问范围的长度，需与实际 DDR 实现和地址检查一致。
 parameter logic [32:0] DDR_BYTES=33'h010000000
)(
 // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
 input logic clk,rst,irq_fault,
 // [ARCH] system_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic system_req_valid,input logic system_req_ready,
 // [ARCH] system_req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic [31:0] system_req_addr,system_req_wdata,
 // [ARCH] system_req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 output logic system_req_write,system_req_is_fetch,output logic [3:0] system_req_wstrb,
 // [ARCH] system_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 input logic system_rsp_valid,output logic system_rsp_ready,
 // [ARCH] system_rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 input logic [31:0] system_rsp_rdata,input logic system_rsp_error,
 // [ARCH] cache_mem_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 cache_mem_req_write 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic [1:0] cache_mem_req_valid,cache_mem_req_write,
 // [ARCH] cache_mem_req_ready：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 lr, lsv, pr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic [1:0] cache_mem_req_ready,
 // [ARCH] cache_mem_req_addr：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 cache_mem_req_wdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic [1:0][31:0] cache_mem_req_addr,
 // [ARCH] cache_mem_req_wdata：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 cache_mem_req_addr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic [1:0][127:0] cache_mem_req_wdata,
 // [ARCH] cache_mem_req_wstrb：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 cache_mem_req_tag 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic [1:0][15:0] cache_mem_req_wstrb,
 // [ARCH] cache_mem_req_tag：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 cache_mem_req_wstrb 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 output logic [1:0][3:0] cache_mem_req_tag,
 // [ARCH] cache_mem_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 lr, lsv, psv 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 input logic [1:0] cache_mem_rsp_valid,cache_mem_rsp_write,cache_mem_rsp_error,
 // [ARCH] cache_mem_rsp_ready：就绪/接纳资格需按当前接口或候选逻辑解释；操作数准备位与总线握手 ready 不能混为一类。
 output logic [1:0] cache_mem_rsp_ready,
 // [ARCH] cache_mem_rsp_rdata：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 input logic [1:0][127:0] cache_mem_rsp_rdata,
 // [ARCH] cache_mem_rsp_tag：保存本接口的所有者/事务编号；匹配时仍需检查有效资格，不能混用其他接口的 tag。
 input logic [1:0][3:0] cache_mem_rsp_tag,
 // [ARCH] cache_protocol_fault：错误事实应记录到所属指令/事务，再在允许的精确边界处理。
 output logic cache_protocol_fault,retire_valid_diag,trap_event,
 // [ARCH] retire_pc_diag：保存拥有者的原始 PC，用于恢复、异常或对应包的诊断。
 output logic [31:0] retire_pc_diag,output logic [1:0] retire_count_diag
);
 wire iv,ir,ipv,ipr,dv,dr,dw,dpv,dpr,dpe,fi,fd,maintenance_busy,event_i,event_d,event_w;
 wire [31:0] ia,da,dwd,dpd;
 wire [63:0] ipd;
 wire [1:0] ipe,dz;
 wire [3:0] ds;
 wire [1:0] retired_mask;
 // [ARCH] retire_pc0：保存拥有者的原始 PC，用于恢复、异常或对应包的诊断。
 // [ARCH] 定位线索：原版中含此标识符的物理行还对 retire_pc_diag 赋值；同一行可能含多个语句，不能据此单独推断依赖。
 wire [31:0] retire_pc0,retire_pc1,retire_instruction0,retire_instruction1,retire_value0,retire_value1;
 // [ARCH] retire_destination0：目的寄存器身份随指令保持，x0 写入仍须被抑制。
 wire [4:0] retire_destination0,retire_destination1;
 wire redirect_event;
 logic [63:0] cycles;
 always_ff @(posedge clk)if(rst)cycles<=0;else cycles<=cycles+1'b1;
 assign retire_valid_diag=|retired_mask;
 assign retire_count_diag={1'b0,retired_mask[0]}+{1'b0,retired_mask[1]};
 assign retire_pc_diag=retired_mask[0]?retire_pc0:retire_pc1;
 assign system_req_is_fetch=1'b0;
 // [ARCH] instr_req_o：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 wire instr_req_o,instr_gnt_i,instr_io_o,instr_rvalid_i,instr_rready_o,instr_err_i;
 // [ARCH] instr_addr_o：地址与当前请求/响应归属配对，不能独立于有效条件使用。
 wire [31:0] instr_addr_o;
 // [ARCH] instr_rdata_i：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 wire [63:0] instr_rdata_i;
 // [ARCH] data_rd_req_o：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 wire data_rd_req_o,data_rd_gnt_i,data_rd_id_o,data_rd_rvalid_i,data_rd_rready_o,data_rd_rid_i,data_rd_err_i;
 // [ARCH] data_rd_addr_o：地址与当前请求/响应归属配对，不能独立于有效条件使用。
 wire [31:0] data_rd_addr_o;
 // [ARCH] data_rd_rdata_i：读返回值只有在对应响应有效时可消费，并需检查错误归属。
 wire [63:0] data_rd_rdata_i;
 // [ARCH] data_wr_req_o：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 wire data_wr_req_o,data_wr_gnt_i,data_wr_last_o,data_wr_id_o,data_wr_bvalid_i,data_wr_berr_i,data_wr_bid_i;
 // [ARCH] data_wr_addr_o：地址与当前请求/响应归属配对，不能独立于有效条件使用。
 wire [31:0] data_wr_addr_o;
 // [ARCH] data_wr_data_o：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
 wire [63:0] data_wr_data_o;
 // [ARCH] periph_req_o：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
 wire periph_req_o,periph_gnt_i,periph_we_o,periph_rvalid_i,periph_err_i;
 // [ARCH] periph_addr_o：地址与当前请求/响应归属配对，不能独立于有效条件使用。
 wire [31:0] periph_addr_o,periph_wdata_o,periph_rdata_i;
 wire [3:0] periph_be_o;
 // [ARCH] periph_size_o：访问粒度与对齐/字节选通一起决定有效数据范围。
 wire [1:0] periph_size_o;
 // [ARCH] 这一实例是游戏当前真正使用的核参数集合。
 // [ARCH] 核文件的复用默认值不能替代下面明确的覆写。
 // [ARCH] LOAD_BYPASS 和 store 前看是不同开关，不能混作放松所有访存顺序。
 // [ARCH] 中断输入包含平台故障，正常游戏不依赖软件定时中断。
 rv32_ooo_core #(
  .RESET_VECTOR(32'h10000000),
  .LOAD_ORDER_ISSUE_LOOKAHEAD(1),
  .MEMORY_CREDITS(3),
  .FETCH_CREDITS(2),
  .ENABLE_COMMITTED_RAS(1),
  .RAS_DEPTH(16),
  .HISTORY_BITS(12),
  .BIMODAL_INDEX_BITS(9),
  .GSHARE_INDEX_BITS(12),
  .ENABLE_PAIRING(1),
  .FAST_WAKEUP(1),
  .ENABLE_SAME_CYCLE_REUSE(0),
  .CARRIED_COMPLETION_WRITES(1),
  .DECOUPLED_ALLOCATION_PAYLOAD(1),
  .BANKED_ISSUE(1),
  .ENABLE_MDU_TURNOVER(1),
  .ENABLE_MDU_SPILL(1),
  .ENABLE_MUL_STREAM(1),
  .ENABLE_STEALING(1),
  .ENABLE_ORDERED_STORE_PREP(1),
  .ENABLE_STORE_HEAD_LOOKAHEAD(1),
  .ENABLE_STORE_ISSUE_LOOKAHEAD(1),
  .ENABLE_REDIRECT_FETCH(1),
  .ENABLE_CURRENT_INTEGER_PAIR(1),
  .ENABLE_CONTROL_DISPATCH(1),
  .ENABLE_DISPATCH_BYPASS(1),
  .DISPATCH_BYPASS_UNMAPPED_ONLY(1),
  .LOAD_BYPASS(1),
  .ENABLE_TRACE(0)
 ) processor(
        .clk(clk),.reset(rst),
        .imem_request_valid(iv),.imem_request_ready(ir),.imem_request_address(ia),
        .imem_response_valid(ipv),.imem_response_ready(ipr),
        .imem_response_data(ipd),.imem_response_error(ipe),
        .dmem_request_valid(dv),.dmem_request_ready(dr),.dmem_request_address(da),
        .dmem_request_write(dw),.dmem_request_size(dz),.dmem_request_wdata(dwd),
        .dmem_request_wstrb(ds),.dmem_response_valid(dpv),.dmem_response_ready(dpr),
        .dmem_response_rdata(dpd),.dmem_response_error(dpe),
        .irq_software(1'b0),.irq_timer(1'b0),.irq_external(irq_fault|cache_protocol_fault),
        .mtime(cycles),.event_icache_refill(event_i),.event_dcache_refill(event_d),
        .event_dcache_writeback(event_w),.fence_i(fi),.fence_d(fd),
        .debug_redirect(redirect_event),.debug_trap(trap_event),
        .debug_branch_miss(),.debug_jump_miss(),
        .debug_dispatch_stall(),.debug_frontend_stall(),
        .retire_valid(retired_mask),.retire_pc0(retire_pc0),.retire_pc1(retire_pc1),
        .retire_instruction0(retire_instruction0),.retire_instruction1(retire_instruction1),
        .retire_destination0(retire_destination0),.retire_destination1(retire_destination1),
        .retire_value0(retire_value0),.retire_value1(retire_value1)
    );
    // [ARCH] 缓存容量由索引位、路数、64 字节行三者计算。
    // [ARCH] 关闭单段守护仅为适配分离的 SRAM 与 DDR。
    // [ARCH] 范围和响应归属检查仍在 backing/periph 层执行。
    rv32_memory_system #(.I_INDEX_BITS(7),.I_WAYS(2),.D_INDEX_BITS(6),.D_WAYS(2),
        .ENABLE_FAST_ICROSS(1),
        .ENABLE_DATA_RAM_GUARD(0),
        .DATA_RAM_BASE(32'h10000000),.DATA_RAM_LIMIT(32'h8fffffff)) memory (
        .clk(clk),.reset(rst),
        .imem_request_valid(iv),.imem_request_ready(ir),.imem_request_address(ia),
        .imem_response_valid(ipv),.imem_response_ready(ipr),
        .imem_response_data(ipd),.imem_response_error(ipe),
        .dmem_request_valid(dv),.dmem_request_ready(dr),.dmem_request_address(da),
        .dmem_request_write(dw),.dmem_request_wdata(dwd),.dmem_request_wstrb(ds),
        .dmem_request_size(dz),.dmem_response_valid(dpv),.dmem_response_ready(dpr),
        .dmem_response_rdata(dpd),.dmem_response_error(dpe),
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
 logic [1:0] lv,lw,lr,lsv,lsr;
 logic [1:0][31:0] la;
 logic [1:0][127:0] ld;
 logic [1:0][15:0] lm;
 logic [1:0][3:0] lt;
 logic pv,pw,pr,psv,psr,pactive,line_fault,periph_fault;
 logic [31:0] pa;logic [127:0] pd;logic [15:0] pm;logic [3:0] pt;
 rv32_game_line_memory #(.ITCM_INIT_FILE(ITCM_INIT_FILE),.DTCM_INIT_FILE(DTCM_INIT_FILE),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) backing(
  .clk,.rst,
  .i_req(instr_req_o),.i_gnt(instr_gnt_i),.i_addr(instr_addr_o),.i_valid(instr_rvalid_i),.i_ready(instr_rready_o),.i_data(instr_rdata_i),.i_error(instr_err_i),
  .d_req(data_rd_req_o),.d_gnt(data_rd_gnt_i),.d_addr(data_rd_addr_o),.d_id(data_rd_id_o),
  .d_valid(data_rd_rvalid_i),.d_ready(data_rd_rready_o),.d_data(data_rd_rdata_i),.d_error(data_rd_err_i),.d_rid(data_rd_rid_i),
  .w_req(data_wr_req_o),.w_gnt(data_wr_gnt_i),.w_addr(data_wr_addr_o),.w_data(data_wr_data_o),.w_last(data_wr_last_o),.w_id(data_wr_id_o),
  .b_valid(data_wr_bvalid_i),.b_error(data_wr_berr_i),.b_id(data_wr_bid_i),.fault(line_fault),
  .mem_req_valid(lv),.mem_req_write(lw),.mem_req_ready(lr),.mem_req_addr(la),.mem_req_wdata(ld),.mem_req_wstrb(lm),.mem_req_tag(lt),
  .mem_rsp_valid(lsv),.mem_rsp_write(cache_mem_rsp_write),.mem_rsp_error(cache_mem_rsp_error),
  .mem_rsp_ready(lsr),.mem_rsp_rdata(cache_mem_rsp_rdata),.mem_rsp_tag(cache_mem_rsp_tag));
 rv32_game_periph #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) periph(
  .clk,.rst,.req(periph_req_o),.gnt(periph_gnt_i),.write(periph_we_o),.addr(periph_addr_o),.wdata(periph_wdata_o),.be(periph_be_o),
  .rvalid(periph_rvalid_i),.error(periph_err_i),.rdata(periph_rdata_i),
  .system_req_valid,.system_req_ready,.system_req_addr,.system_req_write,.system_req_wdata,.system_req_wstrb,
  .system_rsp_valid,.system_rsp_ready,.system_rsp_rdata,.system_rsp_error,
  .mem_active(pactive),.mem_req_valid(pv),.mem_req_ready(pr),.mem_req_write(pw),.mem_req_addr(pa),.mem_req_wdata(pd),.mem_req_wstrb(pm),.mem_req_tag(pt),
  .mem_rsp_valid(psv),.mem_rsp_ready(psr),.mem_rsp_write(cache_mem_rsp_write[1]),.mem_rsp_rdata(cache_mem_rsp_rdata[1]),
  .mem_rsp_tag(cache_mem_rsp_tag[1]),.mem_rsp_error(cache_mem_rsp_error[1]),.fault(periph_fault));
 // The blocking RV32 D-cache serializes cache fills/writebacks and IO commands.
 // Keep the uncached owner selected until its DDR response is consumed.
 assign cache_mem_req_valid[0]=lv[0];assign cache_mem_req_write[0]=lw[0];
 assign cache_mem_req_addr[0]=la[0];assign cache_mem_req_wdata[0]=ld[0];
 assign cache_mem_req_wstrb[0]=lm[0];assign cache_mem_req_tag[0]=lt[0];
 assign lr[0]=cache_mem_req_ready[0];assign lsv[0]=cache_mem_rsp_valid[0];
 assign cache_mem_rsp_ready[0]=lsr[0];
 assign cache_mem_req_valid[1]=pactive?pv:lv[1];assign cache_mem_req_write[1]=pactive?pw:lw[1];
 assign cache_mem_req_addr[1]=pactive?pa:la[1];assign cache_mem_req_wdata[1]=pactive?pd:ld[1];
 assign cache_mem_req_wstrb[1]=pactive?pm:lm[1];assign cache_mem_req_tag[1]=pactive?pt:lt[1];
 assign lr[1]=cache_mem_req_ready[1]&&!pactive;assign pr=cache_mem_req_ready[1]&&pactive;
 assign lsv[1]=cache_mem_rsp_valid[1]&&!pactive;assign psv=cache_mem_rsp_valid[1]&&pactive;
 assign cache_mem_rsp_ready[1]=pactive?psr:lsr[1];
 assign cache_protocol_fault=line_fault|periph_fault;
endmodule
