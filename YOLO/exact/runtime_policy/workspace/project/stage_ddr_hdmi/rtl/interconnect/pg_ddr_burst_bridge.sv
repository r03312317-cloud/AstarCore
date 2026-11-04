// Portable USER-side DDR interface, NOT a DDR PHY/controller/calibration block.
// Collects adjacent full-width beats into bounded AXI4 INCR bursts. A second
// burst can wait in the request FIFO while one AXI transaction is active.
// Upstream tags are restored per beat; AXI ID=0.
// All write completions are emitted only after B. AW and W proceed independently.
// Hard reset must reset/isolate the downstream AXI transaction domain as well.
// A malformed RID/BID/RLAST causes sticky fail-stop; no fabricated success or
// reuse of an outstanding transaction is allowed. SLVERR/DECERR drain normally.
module pg_ddr_burst_bridge #(
    parameter int DATA_W=128, TAG_W=5, MAX_BEATS=16, FLUSH_CYCLES=5,
    parameter bit PIPELINED_COLLECT=1'b1,
    parameter logic [31:0] DDR_BASE=32'h8000_0000,
    parameter logic [32:0] DDR_BYTES=33'h01000_0000
)(
    input logic clk,rst,
    input logic s_req_valid,output logic s_req_ready,
    input logic s_req_write,input logic [31:0] s_req_addr,
    input logic [DATA_W-1:0] s_req_wdata,input logic [DATA_W/8-1:0] s_req_wstrb,
    input logic [TAG_W-1:0] s_req_tag,
    output logic s_rsp_valid,input logic s_rsp_ready,
    output logic s_rsp_write,output logic [DATA_W-1:0] s_rsp_rdata,
    output logic [TAG_W-1:0] s_rsp_tag,output logic s_rsp_error,
    output logic [3:0] m_axi_awid,output logic [31:0] m_axi_awaddr,
    output logic [7:0] m_axi_awlen,output logic [2:0] m_axi_awsize,
    output logic [1:0] m_axi_awburst,output logic m_axi_awlock,
    output logic [3:0] m_axi_awcache,output logic [2:0] m_axi_awprot,
    output logic m_axi_awvalid,input logic m_axi_awready,
    output logic [DATA_W-1:0] m_axi_wdata,output logic [DATA_W/8-1:0] m_axi_wstrb,
    output logic m_axi_wlast,output logic m_axi_wvalid,input logic m_axi_wready,
    input logic [3:0] m_axi_bid,input logic [1:0] m_axi_bresp,
    input logic m_axi_bvalid,output logic m_axi_bready,
    output logic [3:0] m_axi_arid,output logic [31:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen,output logic [2:0] m_axi_arsize,
    output logic [1:0] m_axi_arburst,output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache,output logic [2:0] m_axi_arprot,
    output logic m_axi_arvalid,input logic m_axi_arready,
    input logic [3:0] m_axi_rid,input logic [DATA_W-1:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp,input logic m_axi_rlast,
    input logic m_axi_rvalid,output logic m_axi_rready,
    output logic protocol_fault,output logic busy,
    output logic [31:0] accepted_count,completed_count,burst_count
);
    // PIPEOPT5: packet preparation overlaps the previous burst's R/B wait.
    // Disable for exact PIPEOPT4 timing and request FIFO behavior.
    generate if(PIPELINED_COLLECT)begin:g_overlap
        pg_ddr_burst_bridge_overlap #(.DATA_W(DATA_W),.TAG_W(TAG_W),.MAX_BEATS(MAX_BEATS),
          .FLUSH_CYCLES(FLUSH_CYCLES),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) impl(.*);
    end else begin:g_serial
        pg_ddr_burst_bridge_serial #(.DATA_W(DATA_W),.TAG_W(TAG_W),.MAX_BEATS(MAX_BEATS),
          .FLUSH_CYCLES(FLUSH_CYCLES),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) impl(.*);
    end endgenerate
endmodule

// Portable USER-side DDR interface, NOT a DDR PHY/controller/calibration block.
// Collects adjacent full-width beats into bounded AXI4 INCR bursts. A second
// burst can wait in the request FIFO while one AXI transaction is active.
// Upstream tags are restored per beat; AXI ID=0.
// All write completions are emitted only after B. AW and W proceed independently.
// Hard reset must reset/isolate the downstream AXI transaction domain as well.
// A malformed RID/BID/RLAST causes sticky fail-stop; no fabricated success or
// reuse of an outstanding transaction is allowed. SLVERR/DECERR drain normally.
module pg_ddr_burst_bridge_overlap #(
    parameter int DATA_W=128, TAG_W=5, MAX_BEATS=16, FLUSH_CYCLES=5,
    parameter logic [31:0] DDR_BASE=32'h8000_0000,
    parameter logic [32:0] DDR_BYTES=33'h01000_0000
)(
    input logic clk,rst,
    input logic s_req_valid,output logic s_req_ready,
    input logic s_req_write,input logic [31:0] s_req_addr,
    input logic [DATA_W-1:0] s_req_wdata,input logic [DATA_W/8-1:0] s_req_wstrb,
    input logic [TAG_W-1:0] s_req_tag,
    output logic s_rsp_valid,input logic s_rsp_ready,
    output logic s_rsp_write,output logic [DATA_W-1:0] s_rsp_rdata,
    output logic [TAG_W-1:0] s_rsp_tag,output logic s_rsp_error,
    output logic [3:0] m_axi_awid,output logic [31:0] m_axi_awaddr,
    output logic [7:0] m_axi_awlen,output logic [2:0] m_axi_awsize,
    output logic [1:0] m_axi_awburst,output logic m_axi_awlock,
    output logic [3:0] m_axi_awcache,output logic [2:0] m_axi_awprot,
    output logic m_axi_awvalid,input logic m_axi_awready,
    output logic [DATA_W-1:0] m_axi_wdata,output logic [DATA_W/8-1:0] m_axi_wstrb,
    output logic m_axi_wlast,output logic m_axi_wvalid,input logic m_axi_wready,
    input logic [3:0] m_axi_bid,input logic [1:0] m_axi_bresp,
    input logic m_axi_bvalid,output logic m_axi_bready,
    output logic [3:0] m_axi_arid,output logic [31:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen,output logic [2:0] m_axi_arsize,
    output logic [1:0] m_axi_arburst,output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache,output logic [2:0] m_axi_arprot,
    output logic m_axi_arvalid,input logic m_axi_arready,
    input logic [3:0] m_axi_rid,input logic [DATA_W-1:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp,input logic m_axi_rlast,
    input logic m_axi_rvalid,output logic m_axi_rready,
    output logic protocol_fault,output logic busy,
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
    logic [CW-1:0] count_q,read_index_q,write_index_q,ack_index_q;
    logic [7:0] gap_q;
    // Two packet payload banks. A collector fills only the non-active bank.
    // There remains ONE external AXI transaction, one ID, ordered replies.
    logic active_bank,fill_bank,fill_sealed,fill_legal,fill_write;
    // A real AXI B may retire the external transaction before all of its
    // per-request confirmations have entered the response FIFO. Retain its
    // original tag bank until that enqueue finishes; the other bank can
    // drive the next transaction. There is still only ONE external AXI job.
    logic ack_pending,ack_bank;
    logic [CW-1:0] ack_count;
    logic [31:0] fill_base;
    logic [CW-1:0] fill_count;
    logic [7:0] fill_gap;
    wire dispatch=(state==COLLECT||state==DRAIN)&&(fill_sealed||seal);
    logic [DATA_W-1:0] data_q[2][MAX_BEATS];
    logic [BYTES-1:0] strb_q[2][MAX_BEATS];
    logic [TAG_W-1:0] tag_q[2][MAX_BEATS];
    logic legal_req,joins_req,req_fire,collect_fire,aw_fire,w_fire,r_fire,b_fire,seal;
    logic req_fifo_in_ready,req_fifo_out_valid,req_fifo_out_ready;
    logic [QW-1:0] req_fifo_out_data;
    logic [CW-1:0] req_fifo_level;
    logic collect_write;
    logic [31:0] collect_addr;
    logic [DATA_W-1:0] collect_wdata;
    logic [BYTES-1:0] collect_wstrb;
    logic [TAG_W-1:0] collect_tag;
    logic r_malformed;
    logic fifo_in_valid,fifo_in_ready;
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
    assign joins_req=(fill_count==0)||(legal_req&&(collect_write==fill_write)&&
                     ({1'b0,collect_addr}=={1'b0,fill_base}+(33'(fill_count)<<LG))&&
                     (collect_addr[31:12]==fill_base[31:12]));
    assign req_fifo_out_ready=!rst&&!protocol_fault&&!fill_sealed&&
                              !(ack_pending&&fill_bank==ack_bank)&&
                              (fill_count<CW'(MAX_BEATS))&&joins_req;
    assign s_req_ready=!rst&&!protocol_fault&&req_fifo_in_ready;
    assign req_fire=s_req_valid&&s_req_ready;
    assign collect_fire=req_fifo_out_valid&&req_fifo_out_ready;
    // Do not flush a partial packet merely because the current external
    // transaction is slow. Keep joining arrivals until dispatch is possible.
    assign seal=!fill_sealed&&(fill_count!=0)&&!collect_fire&&
                ((req_fifo_out_valid&&!joins_req)||
                 ((state==COLLECT||state==DRAIN)&&fill_gap>=8'(FLUSH_CYCLES-1)));
    assign protocol_fault=(state==FAULT);
    assign busy=(state!=COLLECT)||(count_q!=0)||(req_fifo_level!=0)||(fifo_level!=0)||(fill_count!=0)||fill_sealed||ack_pending;
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
    assign m_axi_wdata=m_axi_wvalid?data_q[active_bank][IW'(write_index_q)]:'0;
    assign m_axi_wstrb=m_axi_wvalid?strb_q[active_bank][IW'(write_index_q)]:'0;
    assign m_axi_wlast=(write_index_q+1'b1==count_q);
    assign m_axi_bready=!rst&&(state==WRITE_B)&&!ack_pending;
    assign m_axi_arid='0;
    assign m_axi_araddr=base_q;
    assign m_axi_arlen=m_axi_awlen;
    assign m_axi_arsize=3'(LG);
    assign m_axi_arburst=2'b01;
    assign m_axi_arlock=1'b0;
    assign m_axi_arcache=4'b0000;
    assign m_axi_arprot=3'b000;
    assign m_axi_arvalid=!rst&&(state==READ_ADDR);
    assign m_axi_rready=!rst&&(state==READ_DATA)&&!ack_pending&&fifo_in_ready;
    assign aw_fire=m_axi_awvalid&&m_axi_awready;
    assign w_fire=m_axi_wvalid&&m_axi_wready;
    assign r_fire=m_axi_rvalid&&m_axi_rready;
    assign b_fire=m_axi_bvalid&&m_axi_bready;
    assign r_malformed=(m_axi_rid!=0)||(m_axi_rlast!=(read_index_q+1'b1==count_q));
    always_comb begin
        fifo_in_valid=1'b0;fifo_in_data='0;
        // Old write confirmations always precede a subsequent R or local
        // error. Never enqueue confirmation until its actual B was accepted.
        if(ack_pending)begin
            fifo_in_valid=1'b1;
            fifo_in_data={b_error_q,1'b1,tag_q[ack_bank][IW'(ack_index_q)],{DATA_W{1'b0}}};
        end else case(state)
            READ_DATA:begin
                fifo_in_valid=m_axi_rvalid;
                fifo_in_data={((m_axi_rresp!=0)||r_malformed),1'b0,
                    tag_q[active_bank][IW'(read_index_q)],
                    ((m_axi_rresp!=0)||r_malformed)?{DATA_W{1'b0}}:m_axi_rdata};
            end
            LOCAL_ERROR:begin
                fifo_in_valid=1'b1;
                fifo_in_data={1'b1,write_q,tag_q[active_bank][0],{DATA_W{1'b0}}};
            end
            default:begin end
        endcase
    end
    always_ff @(posedge clk)begin
        if(rst)begin ack_pending<=0;ack_bank<=0;ack_count<=0;ack_index_q<=0;b_error_q<=0;end
        else begin
            if(b_fire&&m_axi_bid==0)begin
                ack_pending<=1;ack_bank<=active_bank;ack_count<=count_q;
                ack_index_q<=0;b_error_q<=m_axi_bresp!=0;
            end else if(ack_pending&&fifo_in_ready)begin
                ack_index_q<=ack_index_q+1'b1;
                if(ack_index_q+1'b1==ack_count)ack_pending<=0;
            end
        end
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
            fill_bank<=0;fill_sealed<=0;fill_legal<=1;fill_write<=0;
            fill_base<=0;fill_count<=0;fill_gap<=0;
        end else if(!protocol_fault)begin
            if(dispatch)begin
                fill_bank<=!fill_bank;fill_sealed<=0;fill_count<=0;fill_gap<=0;
            end else if(!fill_sealed)begin
                if(collect_fire)begin
                    tag_q[fill_bank][IW'(fill_count)]<=collect_tag;
                    data_q[fill_bank][IW'(fill_count)]<=collect_wdata;
                    strb_q[fill_bank][IW'(fill_count)]<=collect_wstrb;
                    fill_count<=fill_count+1'b1;fill_gap<=0;
                    if(fill_count==0)begin
                        fill_base<=collect_addr;fill_write<=collect_write;fill_legal<=legal_req;
                    end
                    if((fill_count==0&&!legal_req)||fill_count==CW'(MAX_BEATS-1))fill_sealed<=1;
                end else if(fill_count!=0)begin
                    if(seal)fill_sealed<=1;
                    else if(fill_gap<8'(FLUSH_CYCLES))fill_gap<=fill_gap+1'b1;
                end
            end
        end
    end
    always_ff @(posedge clk) begin
        if(rst)begin
            state<=COLLECT;base_q<='0;write_q<=0;aw_sent_q<=0;
            active_bank<=1;count_q<='0;read_index_q<='0;write_index_q<='0;gap_q<=0;
            accepted_count<=0;completed_count<=0;burst_count<=0;
        end else begin
            if(req_fire)accepted_count<=accepted_count+1'b1;
            if(s_rsp_valid&&s_rsp_ready)completed_count<=completed_count+1'b1;
            case(state)
                COLLECT,DRAIN:if(dispatch)begin
                    base_q<=fill_base;write_q<=fill_write;count_q<=fill_count;
                    active_bank<=fill_bank;
                    read_index_q<=0;write_index_q<=0;aw_sent_q<=0;
                    if(!fill_legal)state<=LOCAL_ERROR;
                    else begin
                        state<=fill_write?WRITE_SEND:READ_ADDR;
                        burst_count<=burst_count+1'b1;
                    end
                end
                else if(state==DRAIN)begin count_q<=0;gap_q<=0;state<=COLLECT;end
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
                    else state<=DRAIN;
                end
                LOCAL_ERROR:if(fifo_in_ready&&!ack_pending)state<=DRAIN;
                // A group releases its tags/data after its last response was ENQUEUED.
                // The independent response FIFO owns them now; do not wait for
                // the consumer to pop before collecting the following burst.

                FAULT:begin end
                default:state<=FAULT;
            endcase
        end
    end
`ifndef SYNTHESIS
    always_ff @(posedge clk) if(!rst)begin
        if(fill_count>CW'(MAX_BEATS))$fatal(1,"PG_DDR_FILL_CREDIT_RED");
        if(state!=COLLECT && fill_bank==active_bank)$fatal(1,"PG_DDR_PACKET_OWNERSHIP_RED");
        if(collect_fire && state!=COLLECT && fill_bank==active_bank)$fatal(1,"PG_DDR_OVERWRITE_ACTIVE_RED");
        if(collect_fire&&ack_pending&&fill_bank==ack_bank)$fatal(1,"PG_DDR_OVERWRITE_ACK_TAGS_RED");
        if(ack_pending&&ack_index_q>=ack_count)$fatal(1,"PG_DDR_ACK_CREDIT_RED");
        if(count_q>CW'(MAX_BEATS))$fatal(1,"PG_DDR_CREDIT_RED");
        if(m_axi_awvalid&&({1'b0,m_axi_awaddr[11:0]}+(13'(count_q)<<LG)>13'd4096))
            $fatal(1,"PG_DDR_4KB_WRITE_RED");
        if(m_axi_arvalid&&({1'b0,m_axi_araddr[11:0]}+(13'(count_q)<<LG)>13'd4096))
            $fatal(1,"PG_DDR_4KB_READ_RED");
    end
`endif
endmodule


// Exact PIPEOPT4 implementation for deterministic rollback.
// Portable USER-side DDR interface, NOT a DDR PHY/controller/calibration block.
// Collects adjacent full-width beats into bounded AXI4 INCR bursts. A second
// burst can wait in the request FIFO while one AXI transaction is active.
// Upstream tags are restored per beat; AXI ID=0.
// All write completions are emitted only after B. AW and W proceed independently.
// Hard reset must reset/isolate the downstream AXI transaction domain as well.
// A malformed RID/BID/RLAST causes sticky fail-stop; no fabricated success or
// reuse of an outstanding transaction is allowed. SLVERR/DECERR drain normally.
module pg_ddr_burst_bridge_serial #(
    parameter int DATA_W=128, TAG_W=5, MAX_BEATS=16, FLUSH_CYCLES=5,
    parameter logic [31:0] DDR_BASE=32'h8000_0000,
    parameter logic [32:0] DDR_BYTES=33'h01000_0000
)(
    input logic clk,rst,
    input logic s_req_valid,output logic s_req_ready,
    input logic s_req_write,input logic [31:0] s_req_addr,
    input logic [DATA_W-1:0] s_req_wdata,input logic [DATA_W/8-1:0] s_req_wstrb,
    input logic [TAG_W-1:0] s_req_tag,
    output logic s_rsp_valid,input logic s_rsp_ready,
    output logic s_rsp_write,output logic [DATA_W-1:0] s_rsp_rdata,
    output logic [TAG_W-1:0] s_rsp_tag,output logic s_rsp_error,
    output logic [3:0] m_axi_awid,output logic [31:0] m_axi_awaddr,
    output logic [7:0] m_axi_awlen,output logic [2:0] m_axi_awsize,
    output logic [1:0] m_axi_awburst,output logic m_axi_awlock,
    output logic [3:0] m_axi_awcache,output logic [2:0] m_axi_awprot,
    output logic m_axi_awvalid,input logic m_axi_awready,
    output logic [DATA_W-1:0] m_axi_wdata,output logic [DATA_W/8-1:0] m_axi_wstrb,
    output logic m_axi_wlast,output logic m_axi_wvalid,input logic m_axi_wready,
    input logic [3:0] m_axi_bid,input logic [1:0] m_axi_bresp,
    input logic m_axi_bvalid,output logic m_axi_bready,
    output logic [3:0] m_axi_arid,output logic [31:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen,output logic [2:0] m_axi_arsize,
    output logic [1:0] m_axi_arburst,output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache,output logic [2:0] m_axi_arprot,
    output logic m_axi_arvalid,input logic m_axi_arready,
    input logic [3:0] m_axi_rid,input logic [DATA_W-1:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp,input logic m_axi_rlast,
    input logic m_axi_rvalid,output logic m_axi_rready,
    output logic protocol_fault,output logic busy,
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
    logic [CW-1:0] count_q,read_index_q,write_index_q,ack_index_q;
    logic [7:0] gap_q;
    logic [DATA_W-1:0] data_q[MAX_BEATS];
    logic [BYTES-1:0] strb_q[MAX_BEATS];
    logic [TAG_W-1:0] tag_q[MAX_BEATS];
    logic legal_req,joins_req,req_fire,collect_fire,aw_fire,w_fire,r_fire,b_fire,seal;
    logic req_fifo_in_ready,req_fifo_out_valid,req_fifo_out_ready;
    logic [QW-1:0] req_fifo_out_data;
    logic [CW-1:0] req_fifo_level;
    logic collect_write;
    logic [31:0] collect_addr;
    logic [DATA_W-1:0] collect_wdata;
    logic [BYTES-1:0] collect_wstrb;
    logic [TAG_W-1:0] collect_tag;
    logic r_malformed;
    logic fifo_in_valid,fifo_in_ready;
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
