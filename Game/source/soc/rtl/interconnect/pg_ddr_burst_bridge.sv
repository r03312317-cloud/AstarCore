// [ARCH] 将内部内存事务转换为 AXI 读写通道。
// [ARCH] 地址、写数据和写响应独立握手，不能假定同拍完成。
// [ARCH] 读响应按 beat 接收，最后一拍和错误必须属于本次突发。
// [ARCH] 写入收到 B 响应后才报告完成。
// [ARCH] 请求的 tag 与返回数据/错误一起保持归属。
// [ARCH] 已经提出的 AW/W/AR 载荷在背压下必须稳定。
// Portable USER-side DDR interface, NOT a DDR PHY/controller/calibration block.
// Collects adjacent full-width beats into bounded AXI4 INCR bursts. A second
// burst can wait in the request FIFO while one AXI transaction is active.
// Upstream tags are restored per beat; AXI ID=0.
// All write completions are emitted only after B. AW and W proceed independently.
// Hard reset must reset/isolate the downstream AXI transaction domain as well.
// A malformed RID/BID/RLAST causes sticky fail-stop; no fabricated success or
// reuse of an outstanding transaction is allowed. SLVERR/DECERR drain normally.
// [ARCH] 联调按 AR/R 和 AW/W/B 两条事务链分别观察。
// [ARCH] 看到 AW 已接纳不表示写数据已经被接纳。
// [ARCH] 看到 WLAST 已接纳也不表示写入已经获得成功确认。
// [ARCH] 读突发必须检查每个有效 beat 的错误，不只检查末拍。
module pg_ddr_burst_bridge #(
    // [ARCH] DATA_W：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 TAG_W, MAX_BEATS, FLUSH_CYCLES, BYTES 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter int DATA_W=128, TAG_W=5, MAX_BEATS=16, FLUSH_CYCLES=5,
    // [ARCH] DDR_BASE：后端 DDR 窗口基地址，先检查范围再转换为控制器地址。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 LIMIT, legal_req 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter logic [31:0] DDR_BASE=32'h8000_0000,
    // [ARCH] DDR_BYTES：后端可访问范围的长度，需与实际 DDR 实现和地址检查一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 LIMIT 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter logic [32:0] DDR_BYTES=33'h01000_0000
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input logic clk,rst,
    // [ARCH] s_req_valid：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 req_fire 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic s_req_valid,output logic s_req_ready,
    // [ARCH] s_req_write：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    input logic s_req_write,input logic [31:0] s_req_addr,
    // [ARCH] s_req_wdata：当前写 beat 载荷，只有 WVALID/WREADY 握手才算下游已接收。
    input logic [DATA_W-1:0] s_req_wdata,input logic [DATA_W/8-1:0] s_req_wstrb,
    // [ARCH] s_req_tag：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    input logic [TAG_W-1:0] s_req_tag,
    // [ARCH] s_rsp_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 completed_count 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic s_rsp_valid,input logic s_rsp_ready,
    output logic s_rsp_write,output logic [DATA_W-1:0] s_rsp_rdata,
    // [ARCH] s_rsp_tag：保存本接口的所有者/事务编号；匹配时仍需检查有效资格，不能混用其他接口的 tag。
    output logic [TAG_W-1:0] s_rsp_tag,output logic s_rsp_error,
    // [ARCH] m_axi_awid：写地址事务身份，后续 B 响应必须回到同一主机/事务。
    output logic [3:0] m_axi_awid,output logic [31:0] m_axi_awaddr,
    // [ARCH] m_axi_awlen：AXI 突发长度编码，与最后一个写数据 beat 的边界一致。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_axi_arlen 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [7:0] m_axi_awlen,output logic [2:0] m_axi_awsize,
    // [ARCH] m_axi_awburst：突发地址推进方式，宽度适配必须保留其语义。
    output logic [1:0] m_axi_awburst,output logic m_axi_awlock,
    output logic [3:0] m_axi_awcache,output logic [2:0] m_axi_awprot,
    // [ARCH] m_axi_awvalid：写地址通道载荷有效，未获 AWREADY 前不能替换其地址/突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 aw_fire 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_axi_awvalid,input logic m_axi_awready,
    // [ARCH] m_axi_wdata：当前写 beat 载荷，只有 WVALID/WREADY 握手才算下游已接收。
    output logic [DATA_W-1:0] m_axi_wdata,output logic [DATA_W/8-1:0] m_axi_wstrb,
    // [ARCH] m_axi_wlast：当前 beat 是本次写突发的最后一拍，但事务仍需等待 B 响应。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_axi_wlast,output logic m_axi_wvalid,input logic m_axi_wready,
    // [ARCH] m_axi_bid：写完成的事务 ID，与先前 AW 记录的归属匹配。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [3:0] m_axi_bid,input logic [1:0] m_axi_bresp,
    // [ARCH] m_axi_bvalid：写响应有效，消费后才可释放对应写事务所有权。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 b_fire 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_axi_bvalid,output logic m_axi_bready,
    // [ARCH] m_axi_arid：读事务身份，R 通道需要依据它保持主机/事务归属。
    output logic [3:0] m_axi_arid,output logic [31:0] m_axi_araddr,
    // [ARCH] m_axi_arlen：请求的读 beat 数编码，接收方用它核对边界和 RLAST。
    output logic [7:0] m_axi_arlen,output logic [2:0] m_axi_arsize,
    // [ARCH] m_axi_arburst：读突发的地址递增/固定方式，不能仅改变数据宽度而丢失。
    output logic [1:0] m_axi_arburst,output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache,output logic [2:0] m_axi_arprot,
    // [ARCH] m_axi_arvalid：读地址有效，未获 ARREADY 前保持地址和突发属性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic m_axi_arvalid,input logic m_axi_arready,
    // [ARCH] m_axi_rid：返回数据的事务 ID，用于检查和路由先前接纳的读请求。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 r_malformed 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [3:0] m_axi_rid,input logic [DATA_W-1:0] m_axi_rdata,
    // [ARCH] m_axi_rresp：读 beat 响应状态，错误需累计到对应行/突发。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 fifo_in_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [1:0] m_axi_rresp,input logic m_axi_rlast,
    // [ARCH] m_axi_rvalid：当前返回 beat 有效，没有该资格不能消费总线上旧数据。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 r_fire, fifo_in_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic m_axi_rvalid,output logic m_axi_rready,
    // [ARCH] protocol_fault：错误事实应记录到所属指令/事务，再在允许的精确边界处理。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_req_ready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic protocol_fault,output logic busy,
    // [ARCH] accepted_count：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 completed_count, burst_count 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output logic [31:0] accepted_count,completed_count,burst_count
);
    localparam int BYTES=DATA_W/8, LG=$clog2(BYTES);
    localparam int CW=$clog2(MAX_BEATS+1), IW=(MAX_BEATS<2)?1:$clog2(MAX_BEATS);
    localparam int RW=DATA_W+TAG_W+2;
    localparam int QW=1+32+DATA_W+BYTES+TAG_W;
    localparam logic [32:0] LIMIT={1'b0,DDR_BASE}+DDR_BYTES;
    typedef enum logic [3:0] {COLLECT,READ_ADDR,READ_DATA,WRITE_SEND,
                              WRITE_B,WRITE_ACK,LOCAL_ERROR,DRAIN,FAULT} state_t;
    state_t state;
    logic [31:0] base_q;
    logic write_q,aw_sent_q,b_error_q;
    // [ARCH] count_q：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 joins_req, req_fifo_out_ready, seal, busy 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [CW-1:0] count_q,read_index_q,write_index_q,ack_index_q;
    logic [7:0] gap_q;
    // [ARCH] data_q：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 m_axi_wdata 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [DATA_W-1:0] data_q[MAX_BEATS];
    logic [BYTES-1:0] strb_q[MAX_BEATS];
    // [ARCH] tag_q：保存本接口的所有者/事务编号；匹配时仍需检查有效资格，不能混用其他接口的 tag。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 fifo_in_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [TAG_W-1:0] tag_q[MAX_BEATS];
    // [ARCH] legal_req：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 joins_req, state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic legal_req,joins_req,req_fire,collect_fire,aw_fire,w_fire,r_fire,b_fire,seal;
    // [ARCH] req_fifo_in_ready：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 s_req_ready 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic req_fifo_in_ready,req_fifo_out_valid,req_fifo_out_ready;
    // [ARCH] req_fifo_out_data：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    logic [QW-1:0] req_fifo_out_data;
    // [ARCH] req_fifo_level：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 busy 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [CW-1:0] req_fifo_level;
    logic collect_write;
    // [ARCH] collect_addr：地址与当前请求/响应归属配对，不能独立于有效条件使用。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 legal_req, base_q, write_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [31:0] collect_addr;
    // [ARCH] collect_wdata：写载荷需与地址和字节选通一起保持，背压不能提前覆盖。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 data_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [DATA_W-1:0] collect_wdata;
    // [ARCH] collect_wstrb：字节选通与写数据同属一次事务，宽度转换要保留字节位置。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 strb_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [BYTES-1:0] collect_wstrb;
    // [ARCH] collect_tag：保存本接口的所有者/事务编号；匹配时仍需检查有效资格，不能混用其他接口的 tag。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 tag_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [TAG_W-1:0] collect_tag;
    logic r_malformed;
    // [ARCH] fifo_in_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 fifo_in_data 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic fifo_in_valid,fifo_in_ready;
    // [ARCH] fifo_in_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 fifo_in_valid 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    logic [RW-1:0] fifo_in_data,fifo_out_data;
    logic [CW-1:0] fifo_level;
    // The pending FIFO absorbs one full burst while the active burst waits
    // for AXI B/R. It preserves order across address or direction changes.
    pg_sync_fifo #(.WIDTH(QW),.DEPTH(MAX_BEATS)) pending_requests(
        .clk,.rst,.in_valid(s_req_valid&&!protocol_fault),.in_ready(req_fifo_in_ready),
        .in_data({s_req_write,s_req_addr,s_req_wdata,s_req_wstrb,s_req_tag}),
        .out_valid(req_fifo_out_valid),.out_ready(req_fifo_out_ready),
        .out_data(req_fifo_out_data),.level(req_fifo_level));
    assign {collect_write,collect_addr,collect_wdata,collect_wstrb,collect_tag}=req_fifo_out_data;
    assign legal_req=(collect_addr[LG-1:0]=='0)&&({1'b0,collect_addr}>={1'b0,DDR_BASE})&&
                     ({1'b0,collect_addr}+33'(BYTES)<=LIMIT);
    assign joins_req=(count_q==0)||(legal_req&&(collect_write==write_q)&&
                     ({1'b0,collect_addr}=={1'b0,base_q}+(33'(count_q)<<LG))&&
                     (collect_addr[31:12]==base_q[31:12]));
    assign req_fifo_out_ready=!rst&&(state==COLLECT)&&(count_q<CW'(MAX_BEATS))&&joins_req;
    assign s_req_ready=!rst&&!protocol_fault&&req_fifo_in_ready;
    assign req_fire=s_req_valid&&s_req_ready;
    assign collect_fire=req_fifo_out_valid&&req_fifo_out_ready;
    assign seal=(state==COLLECT)&&(count_q!=0)&&!collect_fire&&
                ((req_fifo_out_valid&&!joins_req)||(gap_q>=8'(FLUSH_CYCLES-1)));
    assign protocol_fault=(state==FAULT);
    assign busy=(state!=COLLECT)||(count_q!=0)||(req_fifo_level!=0)||(fifo_level!=0);
    assign m_axi_awid='0;
    assign m_axi_awaddr=base_q;
    assign m_axi_awlen=(count_q!=0)?8'(count_q-1'b1):8'd0;
    assign m_axi_awsize=3'(LG);
    assign m_axi_awburst=2'b01;
    assign m_axi_awlock=1'b0;
    assign m_axi_awcache=4'b0000;
    assign m_axi_awprot=3'b000;
    assign m_axi_awvalid=!rst&&(state==WRITE_SEND)&&!aw_sent_q;
    assign m_axi_wvalid=!rst&&(state==WRITE_SEND)&&(write_index_q<count_q);
    assign m_axi_wdata=m_axi_wvalid?data_q[IW'(write_index_q)]:'0;
    assign m_axi_wstrb=m_axi_wvalid?strb_q[IW'(write_index_q)]:'0;
    assign m_axi_wlast=(write_index_q+1'b1==count_q);
    assign m_axi_bready=!rst&&(state==WRITE_B);
    assign m_axi_arid='0;
    assign m_axi_araddr=base_q;
    assign m_axi_arlen=m_axi_awlen;
    assign m_axi_arsize=3'(LG);
    assign m_axi_arburst=2'b01;
    assign m_axi_arlock=1'b0;
    assign m_axi_arcache=4'b0000;
    assign m_axi_arprot=3'b000;
    assign m_axi_arvalid=!rst&&(state==READ_ADDR);
    assign m_axi_rready=!rst&&(state==READ_DATA)&&fifo_in_ready;
    assign aw_fire=m_axi_awvalid&&m_axi_awready;
    assign w_fire=m_axi_wvalid&&m_axi_wready;
    assign r_fire=m_axi_rvalid&&m_axi_rready;
    assign b_fire=m_axi_bvalid&&m_axi_bready;
    assign r_malformed=(m_axi_rid!=0)||(m_axi_rlast!=(read_index_q+1'b1==count_q));
    always_comb begin
        fifo_in_valid=1'b0;fifo_in_data='0;
        case(state)
            READ_DATA:begin
                fifo_in_valid=m_axi_rvalid;
                fifo_in_data={((m_axi_rresp!=0)||r_malformed),1'b0,
                    tag_q[IW'(read_index_q)],
                    ((m_axi_rresp!=0)||r_malformed)?{DATA_W{1'b0}}:m_axi_rdata};
            end
            WRITE_ACK:begin
                fifo_in_valid=1'b1;
                fifo_in_data={b_error_q,1'b1,tag_q[IW'(ack_index_q)],{DATA_W{1'b0}}};
            end
            LOCAL_ERROR:begin
                fifo_in_valid=1'b1;
                fifo_in_data={1'b1,write_q,tag_q[0],{DATA_W{1'b0}}};
            end
            default:begin end
        endcase
    end
    pg_sync_fifo #(.WIDTH(RW),.DEPTH(MAX_BEATS)) responses(
        .clk,.rst,.in_valid(fifo_in_valid),.in_ready(fifo_in_ready),.in_data(fifo_in_data),
        .out_valid(s_rsp_valid),.out_ready(s_rsp_ready),.out_data(fifo_out_data),.level(fifo_level));
    assign {s_rsp_error,s_rsp_write,s_rsp_tag,s_rsp_rdata}=fifo_out_data;
    initial begin
        if(DATA_W!=32&&DATA_W!=64&&DATA_W!=128)$fatal(1,"PG_DDR_DATA_WIDTH_RED");
        if(TAG_W<1||MAX_BEATS<1||MAX_BEATS>16||FLUSH_CYCLES<1||FLUSH_CYCLES>255)
            $fatal(1,"PG_DDR_PARAMETER_RED");
        if(DDR_BYTES==0||LIMIT>33'h1_0000_0000||DDR_BASE%BYTES!=0||DDR_BYTES%33'(BYTES)!=0)
            $fatal(1,"PG_DDR_APERTURE_RED");
    end
    always_ff @(posedge clk) begin
        if(rst)begin
            state<=COLLECT;base_q<='0;write_q<=0;aw_sent_q<=0;b_error_q<=0;
            count_q<='0;read_index_q<='0;write_index_q<='0;ack_index_q<='0;gap_q<=0;
            accepted_count<=0;completed_count<=0;burst_count<=0;
        end else begin
            if(req_fire)accepted_count<=accepted_count+1'b1;
            if(s_rsp_valid&&s_rsp_ready)completed_count<=completed_count+1'b1;
            case(state)
                COLLECT:begin
                    if(collect_fire)begin
                        tag_q[IW'(count_q)]<=collect_tag;
                        data_q[IW'(count_q)]<=collect_wdata;
                        strb_q[IW'(count_q)]<=collect_wstrb;
                        count_q<=count_q+1'b1;gap_q<=0;
                        if(count_q==0)begin base_q<=collect_addr;write_q<=collect_write;end
                        if(count_q==0&&!legal_req)state<=LOCAL_ERROR;
                        else if(count_q==CW'(MAX_BEATS-1))begin
                            state<=collect_write?WRITE_SEND:READ_ADDR;
                            read_index_q<=0;write_index_q<=0;ack_index_q<=0;aw_sent_q<=0;
                            burst_count<=burst_count+1'b1;
                        end
                    end else if(count_q!=0)begin
                        if(seal)begin
                            state<=write_q?WRITE_SEND:READ_ADDR;
                            read_index_q<=0;write_index_q<=0;ack_index_q<=0;aw_sent_q<=0;
                            burst_count<=burst_count+1'b1;
                        end else gap_q<=gap_q+1'b1;
                    end
                end
                READ_ADDR:if(m_axi_arvalid&&m_axi_arready)state<=READ_DATA;
                READ_DATA:if(r_fire)begin
                    read_index_q<=read_index_q+1'b1;
                    if(r_malformed)state<=FAULT;
                    else if(read_index_q+1'b1==count_q)state<=DRAIN;
                end
                WRITE_SEND:begin
                    if(aw_fire)aw_sent_q<=1;
                    if(w_fire)write_index_q<=write_index_q+1'b1;
                    if((aw_sent_q||aw_fire)&&
                       ((write_index_q==count_q)||(w_fire&&m_axi_wlast)))state<=WRITE_B;
                end
                WRITE_B:if(b_fire)begin
                    if(m_axi_bid!=0)state<=FAULT;
                    else begin b_error_q<=m_axi_bresp!=0;ack_index_q<=0;state<=WRITE_ACK;end
                end
                WRITE_ACK:if(fifo_in_ready)begin
                    ack_index_q<=ack_index_q+1'b1;
                    if(ack_index_q+1'b1==count_q)state<=DRAIN;
                end
                LOCAL_ERROR:if(fifo_in_ready)state<=DRAIN;
                // A group releases its tags/data after its last response was ENQUEUED.
                // The independent response FIFO owns them now; do not wait for
                // the consumer to pop before collecting the following burst.
                DRAIN:begin count_q<=0;gap_q<=0;state<=COLLECT;end
                FAULT:begin end
                default:state<=FAULT;
            endcase
        end
    end
`ifndef SYNTHESIS
    always_ff @(posedge clk) if(!rst)begin
        if(count_q>CW'(MAX_BEATS))$fatal(1,"PG_DDR_CREDIT_RED");
        if(m_axi_awvalid&&({1'b0,m_axi_awaddr[11:0]}+(13'(count_q)<<LG)>13'd4096))
            $fatal(1,"PG_DDR_4KB_WRITE_RED");
        if(m_axi_arvalid&&({1'b0,m_axi_araddr[11:0]}+(13'(count_q)<<LG)>13'd4096))
            $fatal(1,"PG_DDR_4KB_READ_RED");
    end
`endif
endmodule
