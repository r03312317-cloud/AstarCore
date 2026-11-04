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
    parameter int DATA_W = 128,
    parameter int ADDR_W = 32,
    parameter int ID_W = 4,
    parameter bit ENABLE_PENDING_QUEUE = 1
)(
    input logic clk, rst,
    output logic busy,
    input logic [1:0][ID_W-1:0] s_awid,
    input logic [1:0][ADDR_W-1:0] s_awaddr,
    input logic [1:0][7:0] s_awlen,
    input logic [1:0][2:0] s_awsize,
    input logic [1:0][1:0] s_awburst,
    input logic [1:0] s_awvalid,
    output logic [1:0] s_awready,
    input logic [1:0][DATA_W-1:0] s_wdata,
    input logic [1:0][DATA_W/8-1:0] s_wstrb,
    input logic [1:0] s_wlast, s_wvalid,
    output logic [1:0] s_wready,
    output logic [1:0][ID_W-1:0] s_bid,
    output logic [1:0][1:0] s_bresp,
    output logic [1:0] s_bvalid,
    input logic [1:0] s_bready,
    input logic [1:0][ID_W-1:0] s_arid,
    input logic [1:0][ADDR_W-1:0] s_araddr,
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
