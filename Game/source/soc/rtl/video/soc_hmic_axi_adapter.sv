// [ARCH] 系统 AXI 与 DDR 厂商用户接口之间的适配边界。
// [ARCH] 地址、长度、选通和响应 ID 都属于协议语义，不能仅改数据宽度。
// [ARCH] 读写通道独立背压，各自保持有效载荷。
// [ARCH] 复位与 mem_ready 共同约束新 DDR 事务准入。
// [ARCH] 控制器内部校准由厂商 IP 完成，本层管理用户侧握手。
// F SoC AXI128 -> HMIC_S 1.16a Standard AXI256.
// One physical burst at a time. A second logical command can be staged while
// the first B/R response is held by the upstream AXI master.
// Buffer the entire read burst: vendor UG042003 p36/p45 requires RREADY=1
// whenever RVALID=1. 16 logical beats starting in the upper half need 9
// physical beats. Byte addresses are rebased, NOT divided as in reduced AXI.
// Reset must reset the controller too; fault is sticky until this common reset.
module soc_hmic_axi_adapter #(
    // [ARCH] DDR_BASE：后端 DDR 窗口基地址，先检查范围再转换为控制器地址。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 limit, addr_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter logic [31:0] DDR_BASE=32'h80000000,
    // [ARCH] DDR_BYTES：后端可访问范围的长度，需与实际 DDR 实现和地址检查一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 limit 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter logic [32:0] DDR_BYTES=33'h010000000,
    parameter int WATCHDOG_CYCLES=65536
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input logic clk,rst,ddr_ready,
    // [ARCH] protocol_fault：错误事实应记录到所属指令/事务，再在允许的精确边界处理。
    output logic protocol_fault,
    // [ARCH] s_awid：写地址事务身份，后续 B 响应必须回到同一主机/事务。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 id_q, logical_count_q, first_half_q, prefetch_id 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [3:0] s_awid,
    // [ARCH] s_awaddr：本次写突发的起始字节地址，跟随写地址通道握手。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 id_q, logical_count_q, first_half_q, physical_count_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [31:0] s_awaddr,
    // [ARCH] s_awlen：AXI 突发长度编码，与最后一个写数据 beat 的边界一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 id_q, logical_count_q, first_half_q, physical_count_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [7:0] s_awlen,
    // [ARCH] s_awsize：每个 beat 的大小编码，需与数据宽度和地址对齐一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [2:0] s_awsize,
    // [ARCH] s_awburst：突发地址推进方式，宽度适配必须保留其语义。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] s_awburst,
    // [ARCH] s_awvalid：写地址通道载荷有效，未获 AWREADY 前不能替换其地址/突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 clear_active_mask, choose_read, prefetch_write, prefetch_id 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic s_awvalid,
    // [ARCH] s_awready：下游接受写地址的条件，与 AWVALID 同时成立才产生地址握手。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 clear_active_mask, prefetch_write, prefetch_id, prefetch_logical_count 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic s_awready,
    // [ARCH] s_wdata：当前写 beat 载荷，只有 WVALID/WREADY 握手才算下游已接收。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 wdata_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [127:0] s_wdata,
    // [ARCH] s_wstrb：写 beat 的逐字节有效位，不能随意扩展为全字节写。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 mask_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [15:0] s_wstrb,
    // [ARCH] s_wlast：当前 beat 是本次写突发的最后一拍，但事务仍需等待 B 响应。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic s_wlast,s_wvalid,
    // [ARCH] s_wready：写数据接纳条件，不能用地址通道已握手代替。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 write_fill_active, write_fill_prefetch 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic s_wready,
    // [ARCH] s_bid：写完成的事务 ID，与先前 AW 记录的归属匹配。
    output logic [3:0] s_bid,
    // [ARCH] s_bresp：写响应状态，错误必须返回给对应发起者。
    output logic [1:0] s_bresp,
    // [ARCH] s_bvalid：写响应有效，消费后才可释放对应写事务所有权。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 final_write_fire, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic s_bvalid,
    // [ARCH] s_bready：主机接收写响应的条件，与 BVALID 同拍才完成响应消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 final_write_fire, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic s_bready,
    // [ARCH] s_arid：读事务身份，R 通道需要依据它保持主机/事务归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 id_q, logical_count_q, first_half_q, prefetch_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [3:0] s_arid,
    // [ARCH] s_araddr：读突发起始字节地址，响应阶段继续使用已保存的归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 id_q, logical_count_q, first_half_q, physical_count_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [31:0] s_araddr,
    // [ARCH] s_arlen：请求的读 beat 数编码，接收方用它核对边界和 RLAST。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 id_q, logical_count_q, first_half_q, physical_count_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [7:0] s_arlen,
    // [ARCH] s_arsize：读 beat 大小编码，需与总线宽度和地址对齐一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state, prefetch_state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [2:0] s_arsize,
    // [ARCH] s_arburst：读突发的地址递增/固定方式，不能仅改变数据宽度而丢失。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state, prefetch_state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] s_arburst,
    // [ARCH] s_arvalid：读地址有效，未获 ARREADY 前保持地址和突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 choose_read 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic s_arvalid,
    // [ARCH] s_arready：读地址接纳条件，与 ARVALID 共同形成一次读命令。
    output logic s_arready,
    // [ARCH] s_rid：返回数据的事务 ID，用于检查和路由先前接纳的读请求。
    output logic [3:0] s_rid,
    // [ARCH] s_rdata：当前读返回载荷，与 RVALID、ID、错误和最后一拍共同解释。
    output logic [127:0] s_rdata,
    // [ARCH] s_rresp：读 beat 响应状态，错误需累计到对应行/突发。
    output logic [1:0] s_rresp,
    // [ARCH] s_rlast：当前为本突发最后一个返回 beat，必须与保存的长度一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 final_read_fire, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic s_rlast,s_rvalid,
    // [ARCH] s_rready：接收方允许消费当前返回 beat，背压时保持未消费响应。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 final_read_fire 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic s_rready,
    // [ARCH] m_awid：写地址事务身份，后续 B 响应必须回到同一主机/事务。
    output logic [7:0] m_awid,
    // [ARCH] m_awaddr：本次写突发的起始字节地址，跟随写地址通道握手。
    output logic [29:0] m_awaddr,
    // [ARCH] m_awlen：AXI 突发长度编码，与最后一个写数据 beat 的边界一致。
    output logic [7:0] m_awlen,
    // [ARCH] m_awsize：每个 beat 的大小编码，需与数据宽度和地址对齐一致。
    output logic [2:0] m_awsize,
    // [ARCH] m_awburst：突发地址推进方式，宽度适配必须保留其语义。
    output logic [1:0] m_awburst,
    // [ARCH] m_awvalid：写地址通道载荷有效，未获 AWREADY 前不能替换其地址/突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 controller_progress, state, prefetch_state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_awvalid,
    // [ARCH] m_awready：下游接受写地址的条件，与 AWVALID 同时成立才产生地址握手。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 controller_progress, state, prefetch_state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_awready,
    // [ARCH] m_wdata：当前写 beat 载荷，只有 WVALID/WREADY 握手才算下游已接收。
    output logic [255:0] m_wdata,
    // [ARCH] m_wstrb：写 beat 的逐字节有效位，不能随意扩展为全字节写。
    output logic [31:0] m_wstrb,
    // [ARCH] m_wlast：当前 beat 是本次写突发的最后一拍，但事务仍需等待 B 响应。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state, prefetch_state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_wlast,m_wvalid,
    // [ARCH] m_wready：写数据接纳条件，不能用地址通道已握手代替。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 controller_progress 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_wready,
    // [ARCH] m_bid：写完成的事务 ID，与先前 AW 记录的归属匹配。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [7:0] m_bid,
    // [ARCH] m_bresp：写响应状态，错误必须返回给对应发起者。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 bresp_q, prefetch_bresp 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] m_bresp,
    // [ARCH] m_bvalid：写响应有效，消费后才可释放对应写事务所有权。
    input logic m_bvalid,
    // [ARCH] m_bready：主机接收写响应的条件，与 BVALID 同拍才完成响应消费。
    output logic m_bready,
    // [ARCH] m_arid：读事务身份，R 通道需要依据它保持主机/事务归属。
    output logic [7:0] m_arid,
    // [ARCH] m_araddr：读突发起始字节地址，响应阶段继续使用已保存的归属。
    output logic [29:0] m_araddr,
    // [ARCH] m_arlen：请求的读 beat 数编码，接收方用它核对边界和 RLAST。
    output logic [7:0] m_arlen,
    // [ARCH] m_arsize：读 beat 大小编码，需与总线宽度和地址对齐一致。
    output logic [2:0] m_arsize,
    // [ARCH] m_arburst：读突发的地址递增/固定方式，不能仅改变数据宽度而丢失。
    output logic [1:0] m_arburst,
    // [ARCH] m_arvalid：读地址有效，未获 ARREADY 前保持地址和突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state, prefetch_state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_arvalid,
    // [ARCH] m_arready：读地址接纳条件，与 ARVALID 共同形成一次读命令。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state, prefetch_state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_arready,
    // [ARCH] m_rid：返回数据的事务 ID，用于检查和路由先前接纳的读请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [7:0] m_rid,
    // [ARCH] m_rdata：当前读返回载荷，与 RVALID、ID、错误和最后一拍共同解释。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 rdata_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [255:0] m_rdata,
    // [ARCH] m_rresp：读 beat 响应状态，错误需累计到对应行/突发。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 resp_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] m_rresp,
    // [ARCH] m_rlast：当前为本突发最后一个返回 beat，必须与保存的长度一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state, prefetch_state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_rlast,m_rvalid,
    // [ARCH] m_rready：接收方允许消费当前返回 beat，背压时保持未消费响应。
    output logic m_rready
);
    timeunit 1ns; timeprecision 1ps;
    localparam int WATCHDOG_W=$clog2(WATCHDOG_CYCLES);
    typedef enum logic [3:0] {IDLE,WCOLLECT,WADDR,WDATA,WRESP,BOUT,
                             RADDR,RDATA,ROUT,BADWRITE,BADREAD,FAULT,
                             RWAIT_PENDING} state_t;
    state_t state;
    typedef enum logic [2:0] {PNONE,PADDR,PDATA,PWC,PWADDR,PWDATA,PWRESP,PDONE} prefetch_t;
    prefetch_t prefetch_state;
    // One physical write bank is shared by both logical command slots.
    // A second write may fill a beat only after the first HMIC W beat has
    // been accepted, so arbitrary physical backpressure remains safe.
    // [ARCH] wdata_q：写载荷需与地址和字节选通一起保持，背压不能提前覆盖。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_wdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [255:0] wdata_q[0:8];
    // [ARCH] rdata_q：读返回值只有在对应响应有效时可消费，并需检查错误归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 selected_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [255:0] rdata_q[0:1][0:8];
    logic [31:0] mask_q[0:8];
    logic [1:0] resp_q[0:1][0:8];
    // [ARCH] addr_q：地址与当前请求/响应归属配对，不能独立于有效条件使用。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awaddr, m_araddr, state, id_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [29:0] addr_q;
    logic [3:0] id_q;
    // [ARCH] logical_count_q：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rlast, state, addr_q, id_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [8:0] logical_count_q,logical_index_q;
    // [ARCH] physical_count_q：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 physical_index_q, first_half_q, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [3:0] physical_count_q,physical_index_q;
    logic first_half_q,prefer_read_q;
    logic [1:0] bresp_q;
    logic [WATCHDOG_W-1:0] watchdog_q;
    logic active_bank,prefetch_valid,prefetch_bad,prefetch_write;
    logic [3:0] prefetch_id,prefetch_physical_count,prefetch_physical_index;
    // [ARCH] prefetch_logical_count：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 prefetch_id, prefetch_addr, id_q, logical_count_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [8:0] prefetch_logical_count;
    // [ARCH] prefetch_logical_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 prefetch_half_index, prefetch_write, prefetch_bresp, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [8:0] prefetch_logical_index;
    // [ARCH] prefetch_addr：地址与当前请求/响应归属配对，不能独立于有效条件使用。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awaddr, m_araddr, prefetch_id, prefetch_logical_count 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [29:0] prefetch_addr;
    logic prefetch_first_half;
    logic [1:0] prefetch_bresp;
    // [ARCH] half_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 data_read_index, write_fill_half, s_rdata, s_rresp 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire [9:0] half_index={1'b0,logical_index_q}+10'(first_half_q);
    // [ARCH] prefetch_half_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 write_fill_half 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire [9:0] prefetch_half_index={1'b0,prefetch_logical_index}+10'(prefetch_first_half);
    // [ARCH] data_read_index：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 selected_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire [3:0] data_read_index=(state==ROUT)?half_index[4:1]:physical_index_q;
    // [ARCH] selected_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire [255:0] selected_data=rdata_q[active_bank][data_read_index];
    wire write_fill_active=state==WCOLLECT&&s_wvalid&&s_wready;
    wire write_fill_prefetch=prefetch_state==PWC&&s_wvalid&&s_wready&&!prefetch_bad;
    wire [9:0] write_fill_half=write_fill_active?half_index:prefetch_half_index;
    wire clear_active_mask=state==IDLE&&s_awvalid&&s_awready;
    wire read_fill_active=state==RDATA;
    wire read_fill_prefetch=prefetch_state==PDATA;
    wire read_fill_bank=read_fill_active?active_bank:~active_bank;
    // [ARCH] read_fill_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
    wire [3:0] read_fill_index=read_fill_active?physical_index_q:prefetch_physical_index;
    wire choose_read=s_arvalid&&(!s_awvalid||prefer_read_q);
    // [ARCH] final_read_fire：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
    wire final_read_fire=(state==ROUT)&&s_rvalid&&s_rready&&s_rlast;
    // [ARCH] final_write_fire：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
    wire final_write_fire=(state==BOUT)&&s_bvalid&&s_bready;
    wire offer_prefetch=(state==WADDR||state==WDATA||state==WRESP||
                         state==RADDR||state==RDATA||state==ROUT||state==BOUT)&&
                        !prefetch_valid&&
                        !final_read_fire&&!final_write_fire;
    wire prefetch_issue_safe=(state==ROUT||state==BOUT||state==RWAIT_PENDING);
    wire write_slot_available=(state==RADDR||state==RDATA||state==ROUT||
                               state==WRESP||state==BOUT||state==RWAIT_PENDING||
                               (state==WDATA&&
                                prefetch_half_index[4:1]<physical_index_q));
    wire wait_controller=(state==WADDR||state==WDATA||state==WRESP||
                          state==RADDR||state==RDATA||
                          prefetch_state==PADDR||prefetch_state==PDATA||
                          prefetch_state==PWADDR||prefetch_state==PWDATA||
                          prefetch_state==PWRESP);
    wire controller_progress=(m_awvalid&&m_awready)||(m_wvalid&&m_wready)||
                             (m_bvalid&&m_bready)||(m_arvalid&&m_arready)||
                             (m_rvalid&&(state==RDATA||prefetch_state==PDATA));
    function automatic logic legal(input logic [31:0] a,input logic [7:0] len,
                                   // [ARCH] size：访问粒度与对齐/字节选通一起决定有效数据范围。
                                   input logic [2:0] size,input logic [1:0] burst);
        logic [32:0] limit;
        limit={1'b0,a}+((33'(len)+1)<<4);
        return len<16 && size==4 && burst==1 && a[3:0]==0 &&
               {1'b0,a}>={1'b0,DDR_BASE} && limit<=({1'b0,DDR_BASE}+DDR_BYTES) &&
               (33'(a[11:0])+((33'(len)+1)<<4)<=4096);
    endfunction
    assign protocol_fault=(state==FAULT);
    assign s_awready=!rst&&ddr_ready&&
                     ((state==IDLE&&!choose_read)||
                      (offer_prefetch&&s_awvalid&&!choose_read));
    assign s_arready=!rst&&ddr_ready&&
                     ((state==IDLE&&choose_read)||
                      (offer_prefetch&&choose_read));
    assign s_wready=!rst&&(state==WCOLLECT||state==BADWRITE||
                           (prefetch_state==PWC&&(prefetch_bad||write_slot_available)));
    assign s_bid=id_q;
    assign s_bresp=bresp_q;
    assign s_bvalid=!rst&&state==BOUT;
    assign s_rid=id_q;
    assign s_rdata=selected_data[128*half_index[0]+:128];
    assign s_rresp=(state==ROUT)?resp_q[active_bank][half_index[4:1]]:2'b11;
    assign s_rvalid=!rst&&(state==ROUT||state==BADREAD);
    assign s_rlast=logical_index_q+1==logical_count_q;
    assign m_awid=(state!=WADDR&&prefetch_state==PWADDR)?{4'b0,prefetch_id}:{4'b0,id_q};
    assign m_arid=(state!=RADDR&&prefetch_state==PADDR)?{4'b0,prefetch_id}:{4'b0,id_q};
    assign m_awaddr=(state!=WADDR&&prefetch_state==PWADDR)?prefetch_addr:addr_q;
    assign m_araddr=(state!=RADDR&&prefetch_state==PADDR)?prefetch_addr:addr_q;
    assign m_awlen=(state!=WADDR&&prefetch_state==PWADDR)?8'(prefetch_physical_count)-1:
                   8'(physical_count_q)-1;
    assign m_arlen=(state!=RADDR&&prefetch_state==PADDR)?8'(prefetch_physical_count)-1:
                   8'(physical_count_q)-1;
    assign m_awsize=5;
    assign m_arsize=5;
    assign m_awburst=1;
    assign m_arburst=1;
    assign m_awvalid=!rst&&ddr_ready&&
                     (state==WADDR||(prefetch_state==PWADDR&&prefetch_issue_safe));
    assign m_arvalid=!rst&&ddr_ready&&
                     (state==RADDR||(prefetch_state==PADDR&&prefetch_issue_safe));
    assign m_wdata=(prefetch_state==PWDATA)?wdata_q[prefetch_physical_index]:
                   wdata_q[physical_index_q];
    assign m_wstrb=(prefetch_state==PWDATA)?mask_q[prefetch_physical_index]:
                   (state==WDATA)?mask_q[physical_index_q]:'0;
    assign m_wlast=(prefetch_state==PWDATA)?
                   prefetch_physical_index+1==prefetch_physical_count:
                   physical_index_q+1==physical_count_q;
    assign m_wvalid=!rst&&ddr_ready&&(state==WDATA||prefetch_state==PWDATA);
    assign m_bready=!rst&&(state==WRESP||prefetch_state==PWRESP);
    // Not derived from CPU ready. Every issued read has 9 reserved RAM slots.
    assign m_rready=1'b1;
    initial begin
        if (DDR_BASE[4:0]!=0||DDR_BYTES[4:0]!=0||DDR_BYTES==0||DDR_BYTES>33'h040000000||
            {1'b0,DDR_BASE}+DDR_BYTES>33'h100000000||WATCHDOG_CYCLES<2)
            $fatal(1,"HMIC_ADAPTER_CONFIGURATION");
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;addr_q<=0;id_q<=0;logical_count_q<=0;logical_index_q<=0;
            physical_count_q<=0;physical_index_q<=0;first_half_q<=0;
            bresp_q<=0;watchdog_q<=0;prefer_read_q<=0;
            active_bank<=0;prefetch_state<=PNONE;prefetch_valid<=0;prefetch_bad<=0;
            prefetch_write<=0;prefetch_logical_index<=0;prefetch_bresp<=0;
            prefetch_id<=0;prefetch_addr<=0;prefetch_logical_count<=0;
            prefetch_physical_count<=0;prefetch_physical_index<=0;
            prefetch_first_half<=0;
        end else begin
            if(!wait_controller||controller_progress)watchdog_q<=0;
            else watchdog_q<=watchdog_q+1'b1;
            case(state)
                IDLE:begin
                    logical_index_q<=0;physical_index_q<=0;
                    if(s_awvalid&&s_awready)begin
                        id_q<=s_awid;logical_count_q<=9'(s_awlen)+1;first_half_q<=s_awaddr[4];
                        physical_count_q<=4'((10'(s_awlen)+10'd2+10'(s_awaddr[4]))>>1);
                        addr_q<=30'((s_awaddr-DDR_BASE)&32'hffffffe0);
                        bresp_q<=0;prefer_read_q<=1;
                        state<=legal(s_awaddr,s_awlen,s_awsize,s_awburst)?WCOLLECT:BADWRITE;
                    end else if(s_arvalid&&s_arready)begin
                        id_q<=s_arid;logical_count_q<=9'(s_arlen)+1;first_half_q<=s_araddr[4];
                        physical_count_q<=4'((10'(s_arlen)+10'd2+10'(s_araddr[4]))>>1);
                        addr_q<=30'((s_araddr-DDR_BASE)&32'hffffffe0);
                        prefer_read_q<=0;
                        state<=legal(s_araddr,s_arlen,s_arsize,s_arburst)?RADDR:BADREAD;
                    end
                end
                WCOLLECT,BADWRITE:if(s_wvalid&&s_wready)begin
                    if(state==WCOLLECT)begin
                    end
                    logical_index_q<=logical_index_q+1'b1;
                    if(s_wlast!=(logical_index_q+1==logical_count_q))state<=FAULT;
                    else if(s_wlast)begin
                        if(state==BADWRITE)begin state<=BOUT;bresp_q<=2'b11;end
                        else state<=WADDR;
                    end
                end
                WADDR:if(m_awvalid&&m_awready)state<=WDATA;
                WDATA:if(m_wvalid&&m_wready)begin
                    physical_index_q<=physical_index_q+1'b1;
                    if(m_wlast)state<=WRESP;
                end
                WRESP:if(m_bvalid&&m_bready)begin
                    bresp_q<=m_bresp;
                    state<=(m_bid=={4'b0,id_q})?BOUT:FAULT;
                end
                BOUT:if(s_bvalid&&s_bready)state<=prefetch_valid?RWAIT_PENDING:IDLE;
                RADDR:if(m_arvalid&&m_arready)state<=RDATA;
                RDATA:if(m_rvalid)begin
                    physical_index_q<=physical_index_q+1'b1;
                    if(m_rid!={4'b0,id_q}||m_rlast!=(physical_index_q+1==physical_count_q))state<=FAULT;
                    else if(m_rlast)state<=ROUT;
                end
                ROUT,BADREAD:if(s_rvalid&&s_rready)begin
                    logical_index_q<=logical_index_q+1'b1;
                    if(s_rlast)state<=(state==ROUT&&prefetch_valid)?RWAIT_PENDING:IDLE;
                end
                RWAIT_PENDING:if(prefetch_state==PDONE)begin
                    id_q<=prefetch_id;logical_count_q<=prefetch_logical_count;
                    logical_index_q<=0;physical_index_q<=0;
                    physical_count_q<=prefetch_physical_count;
                    first_half_q<=prefetch_first_half;addr_q<=prefetch_addr;
                    active_bank<=~active_bank;
                    if(prefetch_write)begin
                        bresp_q<=prefetch_bresp;
                        state<=BOUT;
                    end else state<=prefetch_bad?BADREAD:ROUT;
                    prefetch_valid<=0;prefetch_state<=PNONE;
                end
                default:state<=FAULT;
            endcase
            if(offer_prefetch&&((s_arvalid&&s_arready)||(s_awvalid&&s_awready)))begin
                prefetch_valid<=1;prefetch_id<=s_arid;
                prefetch_write<=s_awvalid&&s_awready;
                prefetch_id<=(s_awvalid&&s_awready)?s_awid:s_arid;
                prefetch_logical_count<=(s_awvalid&&s_awready)?9'(s_awlen)+1:9'(s_arlen)+1;
                prefetch_logical_index<=0;
                prefetch_first_half<=(s_awvalid&&s_awready)?s_awaddr[4]:s_araddr[4];
                prefetch_physical_count<=(s_awvalid&&s_awready)?
                    4'((10'(s_awlen)+10'd2+10'(s_awaddr[4]))>>1):
                    4'((10'(s_arlen)+10'd2+10'(s_araddr[4]))>>1);
                prefetch_physical_index<=0;
                prefetch_addr<=(s_awvalid&&s_awready)?
                    30'((s_awaddr-DDR_BASE)&32'hffffffe0):
                    30'((s_araddr-DDR_BASE)&32'hffffffe0);
                prefetch_bad<=(s_awvalid&&s_awready)?
                    !legal(s_awaddr,s_awlen,s_awsize,s_awburst):
                    !legal(s_araddr,s_arlen,s_arsize,s_arburst);
                if(s_awvalid&&s_awready)begin
                    prefetch_bresp<=0;
                    prefetch_state<=PWC;
                end else prefetch_state<=legal(s_araddr,s_arlen,s_arsize,s_arburst)?PADDR:PDONE;
            end else case(prefetch_state)
                PADDR:if(m_arvalid&&m_arready)prefetch_state<=PDATA;
                PDATA:if(m_rvalid)begin
                    prefetch_physical_index<=prefetch_physical_index+1'b1;
                    if(m_rid!={4'b0,prefetch_id}||
                       m_rlast!=(prefetch_physical_index+1==prefetch_physical_count))
                        state<=FAULT;
                    else if(m_rlast)prefetch_state<=PDONE;
                end
                PWC:if(s_wvalid&&s_wready)begin
                    prefetch_logical_index<=prefetch_logical_index+1'b1;
                    if(s_wlast!=(prefetch_logical_index+1==prefetch_logical_count))state<=FAULT;
                    else if(s_wlast)begin
                        if(prefetch_bad)begin
                            prefetch_bresp<=2'b11;prefetch_state<=PDONE;
                        end else prefetch_state<=PWADDR;
                    end
                end
                PWADDR:if(m_awvalid&&m_awready)prefetch_state<=PWDATA;
                PWDATA:if(m_wvalid&&m_wready)begin
                    prefetch_physical_index<=prefetch_physical_index+1'b1;
                    if(m_wlast)prefetch_state<=PWRESP;
                end
                PWRESP:if(m_bvalid&&m_bready)begin
                    prefetch_bresp<=m_bresp;
                    if(m_bid!={4'b0,prefetch_id})state<=FAULT;
                    else prefetch_state<=PDONE;
                end
                default:begin end
            endcase
            // A missing completion or lost calibration needs a common reset;
            // never recycle an ID and let a late response complete new work.
            if((state!=IDLE&&!ddr_ready)||
               (wait_controller&&!controller_progress&&watchdog_q==WATCHDOG_W'(WATCHDOG_CYCLES-1))||
               (m_rvalid&&state!=RDATA&&prefetch_state!=PDATA))state<=FAULT;
        end
    end
    // The pending write lazily replaces only beat slots already consumed by
    // HMIC. First half-write to each reused slot rebuilds its full mask;
    // stale bytes in the other half are never strobed.
    for(genvar beat=0;beat<9;beat++)begin:GEN_WRITE_BEAT
        always_ff @(posedge clk)begin
            if(!rst)begin
                if(clear_active_mask)mask_q[beat]<=0;
                else if((write_fill_active||write_fill_prefetch)&&
                        write_fill_half[4:1]==beat[3:0])begin
                    wdata_q[beat][128*write_fill_half[0]+:128]<=s_wdata;
                    if(write_fill_prefetch&&
                       (prefetch_logical_index==0||!prefetch_half_index[0]))
                        mask_q[beat]<=write_fill_half[0]?
                            {s_wstrb,16'b0}:{16'b0,s_wstrb};
                    else mask_q[beat][16*write_fill_half[0]+:16]<=s_wstrb;
                end
            end
        end
    end
    // Read responses keep their existing independently reserved banks.
    for(genvar bank=0;bank<2;bank++)begin:GEN_BANK
        for(genvar beat=0;beat<9;beat++)begin:GEN_BEAT
            always_ff @(posedge clk)begin
                if(!rst)begin
                    if(m_rvalid&&(read_fill_active||read_fill_prefetch)&&
                       read_fill_bank==bank[0]&&read_fill_index==beat[3:0])begin
                        rdata_q[bank][beat]<=m_rdata;
                        resp_q[bank][beat]<=m_rresp;
                    end
                end
            end
        end
    end
endmodule
