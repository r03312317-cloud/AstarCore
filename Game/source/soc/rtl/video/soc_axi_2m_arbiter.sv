// [ARCH] CPU 与显示主机共享 DDR，并分别保持读写返回归属。
// [ARCH] 已接纳请求不能因后续瞬时 valid 改变而换主机。
// [ARCH] 显示读取有连续时序需求，CPU 缓存事务仍须得到正确响应。
// [ARCH] ID 有助于识别事务，但不能省去对主机与突发完成的追踪。
// [ARCH] W/B 关联保持到真实写响应完成。
// Board-level AXI arbiter: two upstream masters, one downstream slave.
// Default widths match soc_soc_top -> soc_hmic_axi_adapter. All ports
// share clk (the HMIC user/memory clock); this module is not a CDC bridge.
//
// One downstream burst at a time, plus one captured command from the other
// master. Grant is registered before READY is asserted for an idle arbiter.
// Address fields are captured on the upstream handshake. W is accepted only
// after downstream AW; an
// upstream master may present WVALID earlier and must hold it until WREADY.
// No write-data or response buffering, ID remapping, timeout, or fake response.
// Round robin between masters and between each master's reads and writes is
// conditional on the active transaction eventually making forward progress.
//
// s_*[0] = existing F SoC, s_*[1] = camera DMA (integration convention).
// m_* connects to the existing adapter's s_* ports; IDs pass unchanged.
// Reset must also reset both masters and the downstream transaction domain.
// An isolated arbiter reset cannot cancel an already accepted AXI command.
module soc_axi_2m_arbiter #(
    // [ARCH] DATA_W：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    parameter int DATA_W = 128,
    // [ARCH] ADDR_W：地址与当前请求/响应归属配对，不能独立于有效条件使用。
    parameter int ADDR_W = 32,
    parameter int ID_W = 4,
    // [ARCH] ENABLE_PENDING_QUEUE：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 queue_offer 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter bit ENABLE_PENDING_QUEUE = 1
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input logic clk, rst,
    output logic busy,
    // [ARCH] s_awid：写地址事务身份，后续 B 响应必须回到同一主机/事务。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_id, pending_addr, command_id, command_addr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][ID_W-1:0] s_awid,
    // [ARCH] s_awaddr：本次写突发的起始字节地址，跟随写地址通道握手。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_id, pending_addr, command_id, command_addr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][ADDR_W-1:0] s_awaddr,
    // [ARCH] s_awlen：AXI 突发长度编码，与最后一个写数据 beat 的边界一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_len, pending_size, command_len, command_size 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][7:0] s_awlen,
    // [ARCH] s_awsize：每个 beat 的大小编码，需与数据宽度和地址对齐一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_len, pending_size, command_len, command_size 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][2:0] s_awsize,
    // [ARCH] s_awburst：突发地址推进方式，宽度适配必须保留其语义。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_burst, command_burst, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][1:0] s_awburst,
    // [ARCH] s_awvalid：写地址通道载荷有效，未获 AWREADY 前不能替换其地址/突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 requesting, queue_accept 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] s_awvalid,
    // [ARCH] s_awready：下游接受写地址的条件，与 AWVALID 同时成立才产生地址握手。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_wready, s_arready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0] s_awready,
    // [ARCH] s_wdata：当前写 beat 载荷，只有 WVALID/WREADY 握手才算下游已接收。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_wdata, m_wstrb 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][DATA_W-1:0] s_wdata,
    // [ARCH] s_wstrb：写 beat 的逐字节有效位，不能随意扩展为全字节写。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_wdata, m_wstrb 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][DATA_W/8-1:0] s_wstrb,
    // [ARCH] s_wlast：当前 beat 是本次写突发的最后一拍，但事务仍需等待 B 响应。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_wlast, m_wvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] s_wlast, s_wvalid,
    // [ARCH] s_wready：写数据接纳条件，不能用地址通道已握手代替。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_awready, s_arready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0] s_wready,
    // [ARCH] s_bid：写完成的事务 ID，与先前 AW 记录的归属匹配。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_bresp, s_bvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0][ID_W-1:0] s_bid,
    // [ARCH] s_bresp：写响应状态，错误必须返回给对应发起者。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_bid, s_bvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0][1:0] s_bresp,
    // [ARCH] s_bvalid：写响应有效，消费后才可释放对应写事务所有权。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_bid, s_bresp, m_bready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0] s_bvalid,
    // [ARCH] s_bready：主机接收写响应的条件，与 BVALID 同拍才完成响应消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_bvalid, m_bready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] s_bready,
    // [ARCH] s_arid：读事务身份，R 通道需要依据它保持主机/事务归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_id, pending_addr, command_id, command_addr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][ID_W-1:0] s_arid,
    // [ARCH] s_araddr：读突发起始字节地址，响应阶段继续使用已保存的归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_id, pending_addr, command_id, command_addr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][ADDR_W-1:0] s_araddr,
    // [ARCH] s_arlen：请求的读 beat 数编码，接收方用它核对边界和 RLAST。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_len, pending_size, command_len, command_size 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][7:0] s_arlen,
    // [ARCH] s_arsize：读 beat 大小编码，需与总线宽度和地址对齐一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_len, pending_size, command_len, command_size 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][2:0] s_arsize,
    // [ARCH] s_arburst：读突发的地址递增/固定方式，不能仅改变数据宽度而丢失。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_burst, command_burst, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0][1:0] s_arburst,
    // [ARCH] s_arvalid：读地址有效，未获 ARREADY 前保持地址和突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 requesting, selected_read, queue_read, queue_accept 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] s_arvalid,
    // [ARCH] s_arready：读地址接纳条件，与 ARVALID 共同形成一次读命令。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_awready, s_wready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0] s_arready,
    // [ARCH] s_rid：返回数据的事务 ID，用于检查和路由先前接纳的读请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rdata, s_rresp 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0][ID_W-1:0] s_rid,
    // [ARCH] s_rdata：当前读返回载荷，与 RVALID、ID、错误和最后一拍共同解释。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rid, s_rresp 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0][DATA_W-1:0] s_rdata,
    // [ARCH] s_rresp：读 beat 响应状态，错误需累计到对应行/突发。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rid, s_rdata, s_rlast 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0][1:0] s_rresp,
    // [ARCH] s_rlast：当前为本突发最后一个返回 beat，必须与保存的长度一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rvalid, s_rresp 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0] s_rlast, s_rvalid,
    // [ARCH] s_rready：接收方允许消费当前返回 beat，背压时保持未消费响应。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rvalid, m_rready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] s_rready,
    // [ARCH] m_awid：写地址事务身份，后续 B 响应必须回到同一主机/事务。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awaddr, m_awlen 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [ID_W-1:0] m_awid,
    // [ARCH] m_awaddr：本次写突发的起始字节地址，跟随写地址通道握手。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awid, m_awlen 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [ADDR_W-1:0] m_awaddr,
    // [ARCH] m_awlen：AXI 突发长度编码，与最后一个写数据 beat 的边界一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awsize, m_awburst, m_awid, m_awaddr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [7:0] m_awlen,
    // [ARCH] m_awsize：每个 beat 的大小编码，需与数据宽度和地址对齐一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awlen, m_awburst, m_awvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [2:0] m_awsize,
    // [ARCH] m_awburst：突发地址推进方式，宽度适配必须保留其语义。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awlen, m_awsize, m_awvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0] m_awburst,
    // [ARCH] m_awvalid：写地址通道载荷有效，未获 AWREADY 前不能替换其地址/突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_arvalid, m_awsize, m_awburst 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_awvalid,
    // [ARCH] m_awready：下游接受写地址的条件，与 AWVALID 同时成立才产生地址握手。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_sent, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_awready,
    // [ARCH] m_wdata：当前写 beat 载荷，只有 WVALID/WREADY 握手才算下游已接收。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_wstrb, m_wlast, m_wvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [DATA_W-1:0] m_wdata,
    // [ARCH] m_wstrb：写 beat 的逐字节有效位，不能随意扩展为全字节写。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_wdata, m_wlast, m_wvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [DATA_W/8-1:0] m_wstrb,
    // [ARCH] m_wlast：当前 beat 是本次写突发的最后一拍，但事务仍需等待 B 响应。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 early_pending_w_done, m_wdata, m_wstrb, m_wvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_wlast, m_wvalid,
    // [ARCH] m_wready：写数据接纳条件，不能用地址通道已握手代替。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 early_pending_w_done, s_wready, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_wready,
    // [ARCH] m_bid：写完成的事务 ID，与先前 AW 记录的归属匹配。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_bid, s_bresp 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [ID_W-1:0] m_bid,
    // [ARCH] m_bresp：写响应状态，错误必须返回给对应发起者。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_bid, s_bresp 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] m_bresp,
    // [ARCH] m_bvalid：写响应有效，消费后才可释放对应写事务所有权。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 active_complete, s_bvalid, m_bready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_bvalid,
    // [ARCH] m_bready：主机接收写响应的条件，与 BVALID 同拍才完成响应消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 active_complete, m_rready, s_bvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_bready,
    // [ARCH] m_arid：读事务身份，R 通道需要依据它保持主机/事务归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_araddr, m_arlen 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [ID_W-1:0] m_arid,
    // [ARCH] m_araddr：读突发起始字节地址，响应阶段继续使用已保存的归属。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_arid, m_arlen 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [ADDR_W-1:0] m_araddr,
    // [ARCH] m_arlen：请求的读 beat 数编码，接收方用它核对边界和 RLAST。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_arsize, m_arburst, m_arid, m_araddr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [7:0] m_arlen,
    // [ARCH] m_arsize：读 beat 大小编码，需与总线宽度和地址对齐一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_arlen, m_arburst, m_arvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [2:0] m_arsize,
    // [ARCH] m_arburst：读突发的地址递增/固定方式，不能仅改变数据宽度而丢失。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_arlen, m_arsize, m_arvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [1:0] m_arburst,
    // [ARCH] m_arvalid：读地址有效，未获 ARREADY 前保持地址和突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awvalid, m_arsize, m_arburst 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_arvalid,
    // [ARCH] m_arready：读地址接纳条件，与 ARVALID 共同形成一次读命令。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pending_sent, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_arready,
    // [ARCH] m_rid：返回数据的事务 ID，用于检查和路由先前接纳的读请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rid, s_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [ID_W-1:0] m_rid,
    // [ARCH] m_rdata：当前读返回载荷，与 RVALID、ID、错误和最后一拍共同解释。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rid, s_rdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [DATA_W-1:0] m_rdata,
    // [ARCH] m_rresp：读 beat 响应状态，错误需累计到对应行/突发。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rresp, s_rlast 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] m_rresp,
    // [ARCH] m_rlast：当前为本突发最后一个返回 beat，必须与保存的长度一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_rresp, s_rlast 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_rlast, m_rvalid,
    // [ARCH] m_rready：接收方允许消费当前返回 beat，背压时保持未消费响应。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_bready, s_rvalid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_rready
);
    timeunit 1ns; timeprecision 1ps;
    typedef enum logic [2:0] {
        IDLE, AW_ACCEPT, AW_SEND, W_DATA, B_RESP,
        AR_ACCEPT, AR_SEND, R_DATA
    } state_t;
    state_t state;
    // [ARCH] owner：选择真正拥有当前有效结果的银行/事务，不能依赖 RAM 最后看到的值。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 other_owner, s_awready, m_wdata, m_wstrb 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic owner, next_owner;
    logic [1:0] prefer_read, requesting;
    // [ARCH] selected_owner：选择真正拥有当前有效结果的银行/事务，不能依赖 RAM 最后看到的值。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 selected_read, owner 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic selected_owner, selected_read;
    logic [ID_W-1:0] command_id;
    // [ARCH] command_addr：地址与当前请求/响应归属配对，不能独立于有效条件使用。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awid, m_awaddr, m_arid, m_araddr 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [ADDR_W-1:0] command_addr;
    logic [7:0] command_len;
    // [ARCH] command_size：访问粒度与对齐/字节选通一起决定有效数据范围。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_awlen, m_awsize, m_awburst, m_arlen 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [2:0] command_size;
    logic [1:0] command_burst;
    // [ARCH] pending_valid（尚未完成的事务）：标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 queue_offer, early_pending_ar, early_pending_aw, early_pending_w 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic pending_valid,pending_read,pending_owner,pending_sent,pending_w_done;
    logic [ID_W-1:0] pending_id;
    // [ARCH] pending_addr（尚未完成的事务）：地址与当前请求/响应归属配对，不能独立于有效条件使用。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_arid, m_araddr, m_arlen, m_awid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [ADDR_W-1:0] pending_addr;
    logic [7:0] pending_len;
    // [ARCH] pending_size（尚未完成的事务）：访问粒度与对齐/字节选通一起决定有效数据范围。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_arsize, m_arburst, m_arvalid, m_awsize 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [2:0] pending_size;
    logic [1:0] pending_burst;
    // [ARCH] other_owner：选择真正拥有当前有效结果的银行/事务，不能依赖 RAM 最后看到的值。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 queue_read, queue_accept, s_arready, s_awready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic other_owner,queue_read,queue_offer,queue_accept,active_complete;
    logic early_pending_ar,early_pending_aw,early_pending_w,early_pending_w_done;

    assign requesting = s_awvalid | s_arvalid;
    assign selected_owner = requesting[next_owner] ? next_owner : ~next_owner;
    assign selected_read = s_arvalid[selected_owner] &&
                           (!s_awvalid[selected_owner] || prefer_read[selected_owner]);
    assign other_owner=~owner;
    assign queue_read=s_arvalid[other_owner]&&
                      (!s_awvalid[other_owner]||prefer_read[other_owner]);
    assign active_complete=(state==B_RESP&&m_bvalid&&m_bready)||
                           (state==R_DATA&&m_rvalid&&m_rready&&m_rlast);
    assign queue_offer=ENABLE_PENDING_QUEUE&&!rst&&!pending_valid&&!active_complete&&
                       (state==AW_SEND||state==W_DATA||state==B_RESP||
                        state==AR_SEND||state==R_DATA);
    assign queue_accept=queue_offer&&(s_awvalid[other_owner]||s_arvalid[other_owner]);
    assign early_pending_ar=pending_valid&&pending_read&&!pending_sent&&
                            (state==R_DATA||state==B_RESP)&&!active_complete;
    assign early_pending_aw=pending_valid&&!pending_read&&!pending_sent&&
                            (state==R_DATA||state==B_RESP)&&!active_complete;
    assign early_pending_w=pending_valid&&!pending_read&&pending_sent&&
                           !pending_w_done&&(state==R_DATA||state==B_RESP);
    assign early_pending_w_done=early_pending_w&&m_wvalid&&m_wready&&m_wlast;
    assign busy = !rst && state != IDLE;

    always_comb begin
        s_awready = '0; s_wready = '0; s_arready = '0;
        s_bid = '0; s_bresp = '0; s_bvalid = '0;
        s_rid = '0; s_rdata = '0; s_rresp = '0;
        s_rlast = '0; s_rvalid = '0;
        m_awid = command_id; m_awaddr = command_addr;
        m_awlen = command_len; m_awsize = command_size; m_awburst = command_burst;
        m_arid = command_id; m_araddr = command_addr;
        m_arlen = command_len; m_arsize = command_size; m_arburst = command_burst;
        m_awvalid = 1'b0; m_arvalid = 1'b0;
        m_wdata = '0; m_wstrb = '0; m_wlast = 1'b0; m_wvalid = 1'b0;
        m_bready = 1'b0; m_rready = 1'b0;
        if (!rst) begin
            case (state)
                AW_ACCEPT: s_awready[owner] = 1'b1;
                AW_SEND: m_awvalid = 1'b1;
                W_DATA: begin
                    m_wdata = s_wdata[owner]; m_wstrb = s_wstrb[owner];
                    m_wlast = s_wlast[owner]; m_wvalid = s_wvalid[owner];
                    s_wready[owner] = m_wready;
                end
                B_RESP: begin
                    s_bid[owner] = m_bid; s_bresp[owner] = m_bresp;
                    s_bvalid[owner] = m_bvalid; m_bready = s_bready[owner];
                end
                AR_ACCEPT: s_arready[owner] = 1'b1;
                AR_SEND: m_arvalid = 1'b1;
                R_DATA: begin
                    s_rid[owner] = m_rid; s_rdata[owner] = m_rdata;
                    s_rresp[owner] = m_rresp; s_rlast[owner] = m_rlast;
                    s_rvalid[owner] = m_rvalid; m_rready = s_rready[owner];
                end
                default: begin end
            endcase
            // Capture one command from the other master while the current
            // transaction drains. Its W/R/B channels remain blocked until
            // promotion, so the downstream slave still sees one transaction.
            if(queue_offer)begin
                if(queue_read)s_arready[other_owner]=1'b1;
                else s_awready[other_owner]=1'b1;
            end
            // Experiment: offer the queued read address while R from the
            // current owner drains. The adapter must reserve a second bank.
            if(early_pending_ar)begin
                m_arid=pending_id;m_araddr=pending_addr;m_arlen=pending_len;
                m_arsize=pending_size;m_arburst=pending_burst;m_arvalid=1'b1;
            end
            // The active physical write/read has already finished when the
            // arbiter reaches B_RESP/R_DATA. Stage the other master's write
            // in the adapter's second bank while the first response drains.
            if(early_pending_aw)begin
                m_awid=pending_id;m_awaddr=pending_addr;m_awlen=pending_len;
                m_awsize=pending_size;m_awburst=pending_burst;m_awvalid=1'b1;
            end
            if(early_pending_w)begin
                m_wdata=s_wdata[pending_owner];m_wstrb=s_wstrb[pending_owner];
                m_wlast=s_wlast[pending_owner];m_wvalid=s_wvalid[pending_owner];
                s_wready[pending_owner]=m_wready;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; owner <= 1'b0; next_owner <= 1'b0; prefer_read <= '0;
            command_id <= '0; command_addr <= '0; command_len <= '0;
            command_size <= '0; command_burst <= '0;
            pending_valid<=0;pending_read<=0;pending_owner<=0;pending_sent<=0;
            pending_w_done<=0;
            pending_id<='0;pending_addr<='0;pending_len<='0;
            pending_size<='0;pending_burst<='0;
        end else begin
            if(queue_accept)begin
                pending_valid<=1'b1;
                pending_sent<=0;
                pending_w_done<=0;
                pending_read<=queue_read;
                pending_owner<=other_owner;
                if(queue_read)begin
                    pending_id<=s_arid[other_owner];pending_addr<=s_araddr[other_owner];
                    pending_len<=s_arlen[other_owner];pending_size<=s_arsize[other_owner];
                    pending_burst<=s_arburst[other_owner];
                end else begin
                    pending_id<=s_awid[other_owner];pending_addr<=s_awaddr[other_owner];
                    pending_len<=s_awlen[other_owner];pending_size<=s_awsize[other_owner];
                    pending_burst<=s_awburst[other_owner];
                end
            end
            if((early_pending_ar&&m_arready)||(early_pending_aw&&m_awready))pending_sent<=1;
            if(early_pending_w_done)pending_w_done<=1;
            case (state)
                IDLE: if (|requesting) begin
                    owner <= selected_owner;
                    state <= selected_read ? AR_ACCEPT : AW_ACCEPT;
                end
                AW_ACCEPT: if (s_awvalid[owner]) begin
                    command_id <= s_awid[owner]; command_addr <= s_awaddr[owner];
                    command_len <= s_awlen[owner]; command_size <= s_awsize[owner];
                    command_burst <= s_awburst[owner]; state <= AW_SEND;
                end
                AW_SEND: if (m_awready) state <= W_DATA;
                W_DATA: if (m_wvalid && m_wready && m_wlast) state <= B_RESP;
                B_RESP: if (m_bvalid && m_bready) begin
                    next_owner <= ~owner; prefer_read[owner] <= 1'b1;
                    if(pending_valid)begin
                        owner<=pending_owner;command_id<=pending_id;
                        command_addr<=pending_addr;command_len<=pending_len;
                        command_size<=pending_size;command_burst<=pending_burst;
                        state<=pending_read?(pending_sent?R_DATA:AR_SEND):
                               (pending_sent?(pending_w_done||early_pending_w_done?B_RESP:W_DATA):AW_SEND);
                        pending_valid<=0;pending_sent<=0;pending_w_done<=0;
                    end else state <= IDLE;
                end
                AR_ACCEPT: if (s_arvalid[owner]) begin
                    command_id <= s_arid[owner]; command_addr <= s_araddr[owner];
                    command_len <= s_arlen[owner]; command_size <= s_arsize[owner];
                    command_burst <= s_arburst[owner]; state <= AR_SEND;
                end
                AR_SEND: if (m_arready) state <= R_DATA;
                R_DATA: if (m_rvalid && m_rready && m_rlast) begin
                    next_owner <= ~owner; prefer_read[owner] <= 1'b0;
                    if(pending_valid)begin
                        owner<=pending_owner;command_id<=pending_id;
                        command_addr<=pending_addr;command_len<=pending_len;
                        command_size<=pending_size;command_burst<=pending_burst;
                        state<=pending_read?(pending_sent?R_DATA:AR_SEND):
                               (pending_sent?(pending_w_done||early_pending_w_done?B_RESP:W_DATA):AW_SEND);
                        pending_valid<=0;pending_sent<=0;pending_w_done<=0;
                    end else state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

    initial begin
        if (DATA_W < 8 || DATA_W % 8 != 0 || ADDR_W < 1 || ID_W < 1)
            $fatal(1, "AXI_2M_INVALID_WIDTH");
    end
endmodule
