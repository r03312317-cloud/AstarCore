// One-outstanding 128-bit request adapter for the S3 Requant/LUT engine.
// This is an AXI master, not an AXI wire cast: AW/W/B and AR/R each retain
// their payload until handshake. A missing or wrongly tagged response poisons
// the port until the common board reset, so late DDR traffic cannot be reused.
// 请求转换层将简化存储请求映射到 AXI 地址 数据和响应通道。
// 一次请求只有一个明确所有者，等待响应期间保持对应的地址和返回类型关系。
// ready 表示本拍接受资格，valid 表示事务存在，两者同时成立才推进阶段。
// 写错误与读错误沿各自响应返回，不能因某个通道空闲就提早结束另一个通道。
module soc_rq_to_axi #(
    parameter int unsigned TIMEOUT_CYCLES=100_000_000
)(
    // ddr_ready 保存接收或操作数就绪资格，须结合对应的有效位使用。
    input logic clk,rst,ddr_ready,
    // req_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    input logic req_valid,output logic req_ready,
    // req_addr 保存地址字段，随同所属请求传递，不能从后续新请求重取。
    input logic req_write,input logic [31:0] req_addr,
    // req_wdata 保存写数据 payload，只有对应写请求被接受后才产生副作用。
    input logic [127:0] req_wdata,input logic [15:0] req_wstrb,
    input logic [3:0] req_id,
    // rsp_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output logic rsp_valid,input logic rsp_ready,
    output logic rsp_write,output logic [3:0] rsp_id,
    // rsp_rdata 保存读响应 payload，须在响应有效时才能使用。
    output logic [127:0] rsp_rdata,output logic rsp_error,
    output logic poisoned,
    // m_awid 是 AXI 写地址通道的事务身份，响应需要返回给对应请求所有者。
    // 该通道只有在 valid 与 ready 同时成立时才完成一次实际传递。
    output logic [3:0] m_awid,output logic [31:0] m_awaddr,
    // m_awlen 是 AXI 写地址通道的突发拍数减一，不能直接把编码值当作实际拍数。
    output logic [7:0] m_awlen,output logic [2:0] m_awsize,
    // m_awburst 是 AXI 写地址通道的突发地址递增方式。
    output logic [1:0] m_awburst,output logic m_awvalid,input logic m_awready,
    // m_wdata 保存写数据 payload，只有对应写请求被接受后才产生副作用。
    output logic [127:0] m_wdata,output logic [15:0] m_wstrb,
    // m_wlast 是 AXI 写数据通道的当前为本突发最后一个数据拍的标记。
    output logic m_wlast,m_wvalid,input logic m_wready,
    // m_bid 是 AXI 写响应通道的事务身份，响应需要返回给对应请求所有者。
    input logic [3:0] m_bid,input logic [1:0] m_bresp,
    // m_bvalid 是 AXI 写响应通道的本通道当前存在有效 payload 的资格。
    input logic m_bvalid,output logic m_bready,
    // m_arid 是 AXI 读地址通道的事务身份，响应需要返回给对应请求所有者。
    output logic [3:0] m_arid,output logic [31:0] m_araddr,
    // m_arlen 是 AXI 读地址通道的突发拍数减一，不能直接把编码值当作实际拍数。
    output logic [7:0] m_arlen,output logic [2:0] m_arsize,
    // m_arburst 是 AXI 读地址通道的突发地址递增方式。
    output logic [1:0] m_arburst,output logic m_arvalid,input logic m_arready,
    // m_rid 是 AXI 读响应通道的事务身份，响应需要返回给对应请求所有者。
    input logic [3:0] m_rid,input logic [127:0] m_rdata,
    // m_rresp 是 AXI 读响应通道的本次访问的成功或错误响应编码。
    input logic [1:0] m_rresp,input logic m_rlast,m_rvalid,
    // m_rready 是 AXI 读响应通道的接收方本拍能够接收该通道 payload 的资格。
    output logic m_rready
);
    typedef enum logic [2:0] {IDLE,AW,W,B,AR,R,RESP,POISON} state_t;
    state_t state;
    logic [31:0] addr_q;
    logic [127:0] wdata_q;
    logic [15:0] wstrb_q;
    logic [3:0] id_q;
    logic write_q,poison_after_rsp;
    logic [31:0] wait_cycles;
    // waiting 的资格组合为 (state==AW || state==W || state==B || state==AR || state==R)。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    wire waiting=(state==AW || state==W || state==B || state==AR || state==R);
    // step 的资格组合为 (state==AW && m_awready) || (state==W && m_wready) || (state==B && m_bvalid) || (state==AR && m_arready) || (state==R && m_rvalid)。
    wire step=(state==AW && m_awready) || (state==W && m_wready) ||
              (state==B && m_bvalid) || (state==AR && m_arready) ||
              (state==R && m_rvalid);
    // req_ready 的资格组合为 (state==IDLE) && ddr_ready && !rst。
    assign req_ready=(state==IDLE) && ddr_ready && !rst;
    // rsp_valid 由比较式 (state==RESP) 产生；该结果是条件判断，不是被比较的数据。
    assign rsp_valid=(state==RESP);
    // poisoned 的资格组合为 (state==POISON) || poison_after_rsp。
    assign poisoned=(state==POISON) || poison_after_rsp;
    // m_awid 连接到 id_q，两者在此路径上保持字段对应。
    assign m_awid=id_q;assign m_awaddr=addr_q;assign m_awlen=0;
    assign m_awsize=3'd4;assign m_awburst=2'b01;assign m_awvalid=(state==AW);
    // m_wdata 连接到 wdata_q，两者在此路径上保持字段对应。
    assign m_wdata=wdata_q;assign m_wstrb=wstrb_q;
    assign m_wlast=1'b1;assign m_wvalid=(state==W);
    // m_bready 由比较式 (state==B) 产生；该结果是条件判断，不是被比较的数据。
    assign m_bready=(state==B);
    // m_arid 连接到 id_q，两者在此路径上保持字段对应。
    assign m_arid=id_q;assign m_araddr=addr_q;assign m_arlen=0;
    assign m_arsize=3'd4;assign m_arburst=2'b01;assign m_arvalid=(state==AR);
    // m_rready 由比较式 (state==R) 产生；该结果是条件判断，不是被比较的数据。
    assign m_rready=(state==R);
    always_ff @(posedge clk) begin
        if(rst) begin
            // state 在此时钟更新路径捕获 IDLE，该更新仍受外层条件与后续同块赋值优先级限定。
            // 本时钟边界的 state 捕获 IDLE，两者在此路径上保持字段对应。
            state<=IDLE;addr_q<=0;wdata_q<=0;wstrb_q<=0;id_q<=0;
            write_q<=0;rsp_write<=0;rsp_id<=0;rsp_rdata<=0;rsp_error<=0;
            poison_after_rsp<=0;wait_cycles<=0;
        end else begin
            if(waiting) begin
                if(step) wait_cycles<=0;
                else if(wait_cycles==TIMEOUT_CYCLES-1) begin
                    // 本时钟边界的 rsp_write 捕获 write_q，两者在此路径上保持字段对应。
                    rsp_write<=write_q;rsp_id<=id_q;rsp_rdata<=0;
                    rsp_error<=1;poison_after_rsp<=1;state<=RESP;
                end else wait_cycles<=wait_cycles+1'b1;
            end else wait_cycles<=0;
            case(state)
                IDLE: if(req_valid && req_ready) begin
                    // 本时钟边界的 addr_q 捕获 req_addr，两者在此路径上保持字段对应。
                    addr_q<=req_addr;wdata_q<=req_wdata;wstrb_q<=req_wstrb;
                    id_q<=req_id;write_q<=req_write;
                    rsp_write<=req_write;rsp_id<=req_id;rsp_rdata<=0;
                    rsp_error<=0;poison_after_rsp<=0;
                    if(req_addr[3:0]!=0 || (req_write && req_wstrb==0)) begin
                        rsp_error<=1;state<=RESP;
                    end else state<=req_write?AW:AR;
                end
                AW: if(m_awready) state<=W;
                W: if(m_wready) state<=B;
                B: if(m_bvalid) begin
                    rsp_write<=1;rsp_id<=m_bid;rsp_error<=m_bresp!=0 || m_bid!=id_q;
                    if(m_bid!=id_q) poison_after_rsp<=1;
                    state<=RESP;
                end
                AR: if(m_arready) state<=R;
                R: if(m_rvalid) begin
                    rsp_write<=0;rsp_id<=m_rid;rsp_rdata<=m_rdata;
                    rsp_error<=m_rresp!=0 || m_rid!=id_q || !m_rlast;
                    if(m_rid!=id_q || !m_rlast) poison_after_rsp<=1;
                    state<=RESP;
                end
                RESP: if(rsp_ready) state<=poison_after_rsp?POISON:IDLE;
                default: state<=POISON;
            endcase
            // Timeout wins over a state transition only when no handshake.
            if(waiting && !step && wait_cycles==TIMEOUT_CYCLES-1)
                state<=RESP;
        end
    end
endmodule
