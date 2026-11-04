// PIPEOPT7: direct registered acceptance; pending address VALID is held
// across active response retirement, and a same-edge address handshake is
// included during promotion (never replay an accepted AR/AW).
// Board-level AXI arbiter: two upstream masters, one downstream slave.
// Default widths match soc_soc_top -> soc_hmic_axi_adapter. All ports
// share clk (the HMIC user/memory clock); this module is not a CDC bridge.
//
// One active logical burst plus one captured command; the queued address
// may be offered downstream early. A bounded same-port queue lets successive
// commands traverse an arbiter tree even when sibling ports are inactive.
// DIRECT_ACCEPT captures upstream addresses without a separate grant cycle.
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
// 架构导读：soc_axi_2m_arbiter。
// 共享 AXI 两主机仲裁，处理通道背压与事务归属。
module soc_axi_2m_arbiter #(
    // 静态配置：parameter int DATA_W = 128。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int DATA_W = 128,
    // 静态配置：parameter int ADDR_W = 32。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int ADDR_W = 32,
    // 静态配置：parameter int ID_W = 4。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int ID_W = 4,
    // 静态配置：parameter bit ENABLE_PENDING_QUEUE = 1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit ENABLE_PENDING_QUEUE = 1,
    // 静态配置：parameter bit DIRECT_ACCEPT = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit DIRECT_ACCEPT = 1'b1,
    // 静态配置：parameter bit SAME_MASTER_QUEUE = 1'b1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter bit SAME_MASTER_QUEUE = 1'b1
)(
    // 接口声明：input logic clk, rst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic clk, rst,
    // 接口声明：output logic busy。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic busy,
    // 接口声明：input logic [1:0][ID_W-1:0] s_awid。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [1:0][ID_W-1:0] s_awid,
    // 接口声明：input logic [1:0][ADDR_W-1:0] s_awaddr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input logic [1:0][ADDR_W-1:0] s_awaddr,
    // 接口声明：input logic [1:0][7:0] s_awlen。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [1:0][7:0] s_awlen,
    // 接口声明：input logic [1:0][2:0] s_awsize。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [1:0][2:0] s_awsize,
    // 接口声明：input logic [1:0][1:0] s_awburst。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input logic [1:0][1:0] s_awburst,
    // 接口声明：input logic [1:0] s_awvalid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic [1:0] s_awvalid,
    // 接口声明：output logic [1:0] s_awready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic [1:0] s_awready,
    // 接口声明：input logic [1:0][DATA_W-1:0] s_wdata。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [1:0][DATA_W-1:0] s_wdata,
    // 接口声明：input logic [1:0][DATA_W/8-1:0] s_wstrb。
    // 按字节选择本次写入生效的 lane。
    input logic [1:0][DATA_W/8-1:0] s_wstrb,
    // 接口声明：input logic [1:0] s_wlast, s_wvalid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input logic [1:0] s_wlast, s_wvalid,
    // 接口声明：output logic [1:0] s_wready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    output logic [1:0] s_wready,
    // 接口声明：output logic [1:0][ID_W-1:0] s_bid。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [1:0][ID_W-1:0] s_bid,
    // 接口声明：output logic [1:0][1:0] s_bresp。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output logic [1:0][1:0] s_bresp,
    // 接口声明：output logic [1:0] s_bvalid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output logic [1:0] s_bvalid,
    // 接口声明：input logic [1:0] s_bready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input logic [1:0] s_bready,
    // 接口声明：input logic [1:0][ID_W-1:0] s_arid。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [1:0][ID_W-1:0] s_arid,
    // 接口声明：input logic [1:0][ADDR_W-1:0] s_araddr。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    input logic [1:0][ADDR_W-1:0] s_araddr,
    // 接口声明：input logic [1:0][7:0] s_arlen。
    input logic [1:0][7:0] s_arlen,
    input logic [1:0][2:0] s_arsize,
    input logic [1:0][1:0] s_arburst,
    input logic [1:0] s_arvalid,
    output logic [1:0] s_arready,
    output logic [1:0][ID_W-1:0] s_rid,
    output logic [1:0][DATA_W-1:0] s_rdata,
    output logic [1:0][1:0] s_rresp,
    output logic [1:0] s_rlast, s_rvalid,
    input logic [1:0] s_rready,
    output logic [ID_W-1:0] m_awid,
    output logic [ADDR_W-1:0] m_awaddr,
    output logic [7:0] m_awlen,
    output logic [2:0] m_awsize,
    output logic [1:0] m_awburst,
    output logic m_awvalid,
    input logic m_awready,
    output logic [DATA_W-1:0] m_wdata,
    output logic [DATA_W/8-1:0] m_wstrb,
    output logic m_wlast, m_wvalid,
    input logic m_wready,
    input logic [ID_W-1:0] m_bid,
    input logic [1:0] m_bresp,
    input logic m_bvalid,
    output logic m_bready,
    output logic [ID_W-1:0] m_arid,
    output logic [ADDR_W-1:0] m_araddr,
    output logic [7:0] m_arlen,
    output logic [2:0] m_arsize,
    output logic [1:0] m_arburst,
    output logic m_arvalid,
    input logic m_arready,
    input logic [ID_W-1:0] m_rid,
    input logic [DATA_W-1:0] m_rdata,
    input logic [1:0] m_rresp,
    input logic m_rlast, m_rvalid,
    output logic m_rready
);
    timeunit 1ns; timeprecision 1ps;
    typedef enum logic [2:0] {
        IDLE, AW_ACCEPT, AW_SEND, W_DATA, B_RESP,
        AR_ACCEPT, AR_SEND, R_DATA
    } state_t;
    state_t state;
    logic owner, next_owner;
    logic [1:0] prefer_read, requesting;
    logic selected_owner, selected_read;
    logic [ID_W-1:0] command_id;
    logic [ADDR_W-1:0] command_addr;
    logic [7:0] command_len;
    logic [2:0] command_size;
    logic [1:0] command_burst;
    logic pending_valid,pending_read,pending_owner,pending_sent,pending_w_done;
    logic [ID_W-1:0] pending_id;
    logic [ADDR_W-1:0] pending_addr;
    logic [7:0] pending_len;
    logic [2:0] pending_size;
    logic [1:0] pending_burst;
    logic other_owner,queue_owner,queue_read,queue_offer,queue_accept,active_complete;
    logic early_pending_ar,early_pending_aw,early_pending_w,early_pending_w_done;
    wire pending_address_fire=(early_pending_ar&&m_arready)||(early_pending_aw&&m_awready);

    assign requesting = s_awvalid | s_arvalid;
    wire choose_next_owner=(DIRECT_ACCEPT&&active_complete)?~owner:next_owner;
    wire direct_window=DIRECT_ACCEPT&&((state==IDLE)||(active_complete&&!pending_valid));
    assign selected_owner = requesting[choose_next_owner] ? choose_next_owner : ~choose_next_owner;
    assign selected_read = s_arvalid[selected_owner] &&
                           (!s_awvalid[selected_owner] ||
                            ((DIRECT_ACCEPT&&active_complete&&selected_owner==owner)?
                               state==B_RESP:prefer_read[selected_owner]));
    assign other_owner=~owner;
    // A tree's parent sees all child traffic as one upstream master. Permit
    // one additional command from that same port, otherwise an inactive
    // sibling serializes the entire tree. A requesting other master retains
    // priority. W order and all responses still follow active -> pending.
    assign queue_owner=(requesting[other_owner]||!SAME_MASTER_QUEUE)?other_owner:owner;
    assign queue_read=s_arvalid[queue_owner]&&
                      (!s_awvalid[queue_owner]||
                       ((SAME_MASTER_QUEUE&&queue_owner==owner)?
                         (state==AW_SEND||state==W_DATA||state==B_RESP):prefer_read[queue_owner]));
    assign active_complete=(state==B_RESP&&m_bvalid&&m_bready)||
                           (state==R_DATA&&m_rvalid&&m_rready&&m_rlast);
    assign queue_offer=ENABLE_PENDING_QUEUE&&!rst&&!pending_valid&&!active_complete&&
                       (state==AW_SEND||state==W_DATA||state==B_RESP||
                        state==AR_SEND||state==R_DATA);
    assign queue_accept=queue_offer&&(s_awvalid[queue_owner]||s_arvalid[queue_owner]);
    assign early_pending_ar=pending_valid&&pending_read&&!pending_sent&&
                            (state==R_DATA||state==B_RESP);
    assign early_pending_aw=pending_valid&&!pending_read&&!pending_sent&&
                            (state==R_DATA||state==B_RESP);
    assign early_pending_w=pending_valid&&!pending_read&&pending_sent&&
                           !pending_w_done&&(state==R_DATA||state==B_RESP);
    assign early_pending_w_done=early_pending_w&&m_wvalid&&m_wready&&m_wlast;
    assign busy = !rst && state != IDLE;

    // Select the write owner once, before the wide data mux. The queued
    // write retains its original priority. No new state or pipeline cycle.
    logic write_route_enable, write_route_owner;
    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_comb begin
        write_route_enable = 1'b0;
        write_route_owner = owner;
        // 复位相关判断：!rst；分支方向由信号极性与取反表达式决定。
        if (!rst) begin
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case (state)
                // 状态/选择分支 W_DATA：本分支规定该编码下的寄存器更新和下一步动作。
                W_DATA: write_route_enable = 1'b1;
                default: begin end
            endcase
            if (early_pending_w) begin
                write_route_enable = 1'b1;
                write_route_owner = pending_owner;
            end
        end
    end
    assign m_wdata = write_route_enable ? s_wdata[write_route_owner] : '0;
    assign m_wstrb = write_route_enable ? s_wstrb[write_route_owner] : '0;
    assign m_wlast = write_route_enable ? s_wlast[write_route_owner] : 1'b0;
    assign m_wvalid = write_route_enable ? s_wvalid[write_route_owner] : 1'b0;

    // 过程边界：always_comb begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
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
        m_bready = 1'b0; m_rready = 1'b0;
        // 复位相关判断：!rst；分支方向由信号极性与取反表达式决定。
        if (!rst) begin
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case (state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if (DIRECT_ACCEPT && (|requesting)) begin
                    if (selected_read) s_arready[selected_owner] = 1'b1;
                    else s_awready[selected_owner] = 1'b1;
                end
                // 状态/选择分支 AW_ACCEPT：本分支规定该编码下的寄存器更新和下一步动作。
                AW_ACCEPT: s_awready[owner] = 1'b1;
                // 状态/选择分支 AW_SEND：本分支规定该编码下的寄存器更新和下一步动作。
                AW_SEND: m_awvalid = 1'b1;
                // 状态/选择分支 W_DATA：本分支规定该编码下的寄存器更新和下一步动作。
                W_DATA: begin
                    s_wready[owner] = m_wready;
                end
                // 状态/选择分支 B_RESP：本分支规定该编码下的寄存器更新和下一步动作。
                B_RESP: begin
                    s_bid[owner] = m_bid; s_bresp[owner] = m_bresp;
                    s_bvalid[owner] = m_bvalid; m_bready = s_bready[owner];
                end
                // 状态/选择分支 AR_ACCEPT：本分支规定该编码下的寄存器更新和下一步动作。
                AR_ACCEPT: s_arready[owner] = 1'b1;
                // 状态/选择分支 AR_SEND：本分支规定该编码下的寄存器更新和下一步动作。
                AR_SEND: m_arvalid = 1'b1;
                // 状态/选择分支 R_DATA：本分支规定该编码下的寄存器更新和下一步动作。
                R_DATA: begin
                    s_rid[owner] = m_rid; s_rdata[owner] = m_rdata;
                    s_rresp[owner] = m_rresp; s_rlast[owner] = m_rlast;
                    s_rvalid[owner] = m_rvalid; m_rready = s_rready[owner];
                end
                default: begin end
            endcase
            // A retiring response and a new address are independent channels.
            // With no queued command, register the next grant on this edge;
            // captured addresses still pass through AR_SEND/AW_SEND.
            if (direct_window && (|requesting)) begin
                if (selected_read) s_arready[selected_owner]=1'b1;
                else s_awready[selected_owner]=1'b1;
            end
            // Capture one command, prioritizing the other master. Pending
            // W is forwarded only after its AW and after active W has ended.
            // R/B responses retain active-before-pending logical order.
            if(queue_offer)begin
                if(queue_read)s_arready[queue_owner]=1'b1;
                else s_awready[queue_owner]=1'b1;
            end
            // Experiment: offer the queued read address while R from the
            // current owner drains. The adapter must reserve a second bank.
            if(early_pending_ar)begin
                m_arid=pending_id;m_araddr=pending_addr;m_arlen=pending_len;
                m_arsize=pending_size;m_arburst=pending_burst;m_arvalid=1'b1;
            end
            // Queue a write while the active response drains. The downstream
            // adapter decides whether physical ranges permit overlap; this
            // arbiter never assumes physical completion from its own state.
            if(early_pending_aw)begin
                m_awid=pending_id;m_awaddr=pending_addr;m_awlen=pending_len;
                m_awsize=pending_size;m_awburst=pending_burst;m_awvalid=1'b1;
            end
            if(early_pending_w)begin
                s_wready[pending_owner]=m_wready;
            end
        end
    end

    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
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
                pending_owner<=queue_owner;
                if(queue_read)begin
                    pending_id<=s_arid[queue_owner];pending_addr<=s_araddr[queue_owner];
                    pending_len<=s_arlen[queue_owner];pending_size<=s_arsize[queue_owner];
                    pending_burst<=s_arburst[queue_owner];
                end else begin
                    pending_id<=s_awid[queue_owner];pending_addr<=s_awaddr[queue_owner];
                    pending_len<=s_awlen[queue_owner];pending_size<=s_awsize[queue_owner];
                    pending_burst<=s_awburst[queue_owner];
                end
            end
            if((early_pending_ar&&m_arready)||(early_pending_aw&&m_awready))pending_sent<=1;
            if(early_pending_w_done)pending_w_done<=1;
            // 按 state 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case (state)
                // 状态/选择分支 IDLE：本分支规定该编码下的寄存器更新和下一步动作。
                IDLE: if (|requesting) begin
                    owner <= selected_owner;
                    if (DIRECT_ACCEPT) begin
                        // Snapshot the granted address on the actual upstream
                        // handshake. Downstream VALID still uses registers;
                        // there is no combinational address bypass.
                        if (selected_read) begin
                            command_id<=s_arid[selected_owner]; command_addr<=s_araddr[selected_owner];
                            command_len<=s_arlen[selected_owner]; command_size<=s_arsize[selected_owner];
                            command_burst<=s_arburst[selected_owner]; state<=AR_SEND;
                        end else begin
                            command_id<=s_awid[selected_owner]; command_addr<=s_awaddr[selected_owner];
                            command_len<=s_awlen[selected_owner]; command_size<=s_awsize[selected_owner];
                            command_burst<=s_awburst[selected_owner]; state<=AW_SEND;
                        end
                    end else state <= selected_read ? AR_ACCEPT : AW_ACCEPT;
                end
                // 状态/选择分支 AW_ACCEPT：本分支规定该编码下的寄存器更新和下一步动作。
                AW_ACCEPT: if (s_awvalid[owner]) begin
                    command_id <= s_awid[owner]; command_addr <= s_awaddr[owner];
                    command_len <= s_awlen[owner]; command_size <= s_awsize[owner];
                    command_burst <= s_awburst[owner]; state <= AW_SEND;
                end
                // 状态/选择分支 AW_SEND：本分支规定该编码下的寄存器更新和下一步动作。
                AW_SEND: if (m_awready) state <= W_DATA;
                // 状态/选择分支 W_DATA：本分支规定该编码下的寄存器更新和下一步动作。
                W_DATA: if (m_wvalid && m_wready && m_wlast) state <= B_RESP;
                // 状态/选择分支 B_RESP：本分支规定该编码下的寄存器更新和下一步动作。
                B_RESP: if (m_bvalid && m_bready) begin
                    next_owner <= ~owner; prefer_read[owner] <= 1'b1;
                    if(pending_valid)begin
                        owner<=pending_owner;command_id<=pending_id;
                        command_addr<=pending_addr;command_len<=pending_len;
                        command_size<=pending_size;command_burst<=pending_burst;
                        state<=pending_read?((pending_sent||pending_address_fire)?R_DATA:AR_SEND):
                               ((pending_sent||pending_address_fire)?(pending_w_done||early_pending_w_done?B_RESP:W_DATA):AW_SEND);
                        pending_valid<=0;pending_sent<=0;pending_w_done<=0;
                    end else state <= IDLE;
                end
                // 状态/选择分支 AR_ACCEPT：本分支规定该编码下的寄存器更新和下一步动作。
                AR_ACCEPT: if (s_arvalid[owner]) begin
                    command_id <= s_arid[owner]; command_addr <= s_araddr[owner];
                    command_len <= s_arlen[owner]; command_size <= s_arsize[owner];
                    command_burst <= s_arburst[owner]; state <= AR_SEND;
                end
                // 状态/选择分支 AR_SEND：本分支规定该编码下的寄存器更新和下一步动作。
                AR_SEND: if (m_arready) state <= R_DATA;
                // 状态/选择分支 R_DATA：本分支规定该编码下的寄存器更新和下一步动作。
                R_DATA: if (m_rvalid && m_rready && m_rlast) begin
                    next_owner <= ~owner; prefer_read[owner] <= 1'b0;
                    if(pending_valid)begin
                        owner<=pending_owner;command_id<=pending_id;
                        command_addr<=pending_addr;command_len<=pending_len;
                        command_size<=pending_size;command_burst<=pending_burst;
                        state<=pending_read?((pending_sent||pending_address_fire)?R_DATA:AR_SEND):
                               ((pending_sent||pending_address_fire)?(pending_w_done||early_pending_w_done?B_RESP:W_DATA):AW_SEND);
                        pending_valid<=0;pending_sent<=0;pending_w_done<=0;
                    end else state <= IDLE;
                end
                default: state <= IDLE;
            endcase
            if (DIRECT_ACCEPT&&active_complete&&!pending_valid&&(|requesting)) begin
                owner<=selected_owner;
                if(selected_read) begin
                    command_id<=s_arid[selected_owner];command_addr<=s_araddr[selected_owner];
                    command_len<=s_arlen[selected_owner];command_size<=s_arsize[selected_owner];
                    command_burst<=s_arburst[selected_owner];state<=AR_SEND;
                end else begin
                    command_id<=s_awid[selected_owner];command_addr<=s_awaddr[selected_owner];
                    command_len<=s_awlen[selected_owner];command_size<=s_awsize[selected_owner];
                    command_burst<=s_awburst[selected_owner];state<=AW_SEND;
                end
            end
        end
    end

    initial begin
        if (DATA_W < 8 || DATA_W % 8 != 0 || ADDR_W < 1 || ID_W < 1)
            $fatal(1, "AXI_2M_INVALID_WIDTH");
    end
endmodule
