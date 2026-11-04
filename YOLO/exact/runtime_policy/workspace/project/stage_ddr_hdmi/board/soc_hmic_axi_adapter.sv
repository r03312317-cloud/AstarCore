// PIPEOPT7 disjoint opposite-direction physical transaction overlap.
// A protocol fault quarantines BOTH directions until common controller reset;
// never accept new write data or acknowledge the peer after fail-stop.
// PIPEOPT6R: bounded cut-through AXI width conversion. NOT the lost CFQ design.
// Keep both reserved read banks and the existing nine physical write slots.
// Reads may be returned only from already captured physical beats. A physical
// write beat may issue only when BOTH of its logical halves (or the terminal
// partial beat) have been captured. RREADY remains permanently asserted.
// The write response is still exclusively derived from the real physical B.
// Disable both streaming parameters to restore packet-gated scheduling.
// The prefetch address-handshake ownership fix remains active in that mode.
// F SoC AXI128 -> HMIC_S 1.16a Standard AXI256.
// PIPEOPT7 permits one disjoint read and write in parallel; never two
// physical bursts of the same direction. A second logical command is staged while
// the first B/R response is held by the upstream AXI master.
// Buffer the entire read burst: vendor UG042003 p36/p45 requires RREADY=1
// whenever RVALID=1. 16 logical beats starting in the upper half need 9
// physical beats. Byte addresses are rebased, NOT divided as in reduced AXI.
// Reset must reset the controller too; fault is sticky until this common reset.
module soc_hmic_axi_adapter #(
    parameter logic [31:0] DDR_BASE=32'h80000000,
    parameter logic [32:0] DDR_BYTES=33'h010000000,
    parameter int WATCHDOG_CYCLES=65536,
    parameter bit STREAM_READ=1'b1,
    parameter bit STREAM_WRITE=1'b1,
    parameter bit DISJOINT_RW_OVERLAP=1'b1
)(
    input logic clk,rst,ddr_ready,
    output logic protocol_fault,
    input logic [3:0] s_awid,
    input logic [31:0] s_awaddr,
    input logic [7:0] s_awlen,
    input logic [2:0] s_awsize,
    input logic [1:0] s_awburst,
    input logic s_awvalid,
    output logic s_awready,
    input logic [127:0] s_wdata,
    input logic [15:0] s_wstrb,
    input logic s_wlast,s_wvalid,
    output logic s_wready,
    output logic [3:0] s_bid,
    output logic [1:0] s_bresp,
    output logic s_bvalid,
    input logic s_bready,
    input logic [3:0] s_arid,
    input logic [31:0] s_araddr,
    input logic [7:0] s_arlen,
    input logic [2:0] s_arsize,
    input logic [1:0] s_arburst,
    input logic s_arvalid,
    output logic s_arready,
    output logic [3:0] s_rid,
    output logic [127:0] s_rdata,
    output logic [1:0] s_rresp,
    output logic s_rlast,s_rvalid,
    input logic s_rready,
    output logic [7:0] m_awid,
    output logic [29:0] m_awaddr,
    output logic [7:0] m_awlen,
    output logic [2:0] m_awsize,
    output logic [1:0] m_awburst,
    output logic m_awvalid,
    input logic m_awready,
    output logic [255:0] m_wdata,
    output logic [31:0] m_wstrb,
    output logic m_wlast,m_wvalid,
    input logic m_wready,
    input logic [7:0] m_bid,
    input logic [1:0] m_bresp,
    input logic m_bvalid,
    output logic m_bready,
    output logic [7:0] m_arid,
    output logic [29:0] m_araddr,
    output logic [7:0] m_arlen,
    output logic [2:0] m_arsize,
    output logic [1:0] m_arburst,
    output logic m_arvalid,
    input logic m_arready,
    input logic [7:0] m_rid,
    input logic [255:0] m_rdata,
    input logic [1:0] m_rresp,
    input logic m_rlast,m_rvalid,
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
    // Canonical single-write-port distributed memories. Only the original
    // nine slots per logical bank are addressable by writes. Power-of-two
    // declaration padding does not reserve fewer physical burst beats.
    (* syn_ramstyle="distributed_ram" *) logic [127:0] wdata_low[0:15];
    (* syn_ramstyle="distributed_ram" *) logic [127:0] wdata_high[0:15];
    (* syn_ramstyle="distributed_ram" *) logic [255:0] rdata_memory[0:31];
    logic [31:0] mask_q[0:8];
    logic [1:0] resp_q[0:1][0:8];
    logic [29:0] addr_q;
    logic [3:0] id_q;
    logic [8:0] logical_count_q,logical_index_q;
    logic [3:0] physical_count_q,physical_index_q;
    logic first_half_q,prefer_read_q;
    logic [1:0] bresp_q;
    logic active_aw_sent, prefetch_aw_sent;
    wire active_collect=(state==WCOLLECT) && (logical_index_q<logical_count_q);
    wire stream_active=(STREAM_WRITE && state==WCOLLECT);
    wire stream_prefetch=(STREAM_WRITE && prefetch_state==PWC && !prefetch_bad);
    wire active_word_ready=(physical_index_q<physical_count_q) &&
       ((10'(physical_index_q) < (({1'b0,logical_index_q}+10'(first_half_q))>>1)) ||
         logical_index_q==logical_count_q);
    wire prefetch_word_ready=(prefetch_physical_index<prefetch_physical_count) &&
       ((10'(prefetch_physical_index) < (({1'b0,prefetch_logical_index}+10'(prefetch_first_half))>>1)) ||
         prefetch_logical_index==prefetch_logical_count);
    wire stream_write_valid=stream_active && active_aw_sent && active_word_ready;
    wire stream_prefetch_write_valid=stream_prefetch && prefetch_aw_sent && prefetch_word_ready;
    wire stream_read_valid=STREAM_READ && state==RDATA &&
                          (half_index[4:1]<physical_index_q);
    wire active_aw_phase=(state==WADDR) || stream_active;
    wire prefetch_aw_phase=(prefetch_state==PWADDR) || stream_prefetch;
    wire active_w_phase=(state==WDATA) || stream_active;
    wire prefetch_w_phase=(prefetch_state==PWDATA) || (stream_prefetch&&prefetch_aw_sent);
    logic [WATCHDOG_W-1:0] watchdog_q;
    logic active_bank,prefetch_valid,prefetch_bad,prefetch_write;
    logic [3:0] prefetch_id,prefetch_physical_count,prefetch_physical_index;
    logic [8:0] prefetch_logical_count;
    logic [8:0] prefetch_logical_index;
    logic [29:0] prefetch_addr;
    logic prefetch_first_half;
    logic [1:0] prefetch_bresp;
    wire [9:0] half_index={1'b0,logical_index_q}+10'(first_half_q);
    wire [9:0] prefetch_half_index={1'b0,prefetch_logical_index}+10'(prefetch_first_half);
    wire [3:0] data_read_index=(state==ROUT || (STREAM_READ && state==RDATA))?
                                half_index[4:1]:physical_index_q;
    wire [255:0] selected_data=rdata_memory[{active_bank,data_read_index}];
    wire write_fill_active=active_collect&&s_wvalid&&s_wready;
    wire write_fill_prefetch=prefetch_state==PWC&&!active_collect&&
                             s_wvalid&&s_wready&&!prefetch_bad;
    wire [9:0] write_fill_half=write_fill_active?half_index:prefetch_half_index;
    wire clear_active_mask=state==IDLE&&s_awvalid&&s_awready;
    wire read_fill_active=state==RDATA;
    wire read_fill_prefetch=prefetch_state==PDATA;
    wire read_fill_bank=read_fill_active?active_bank:~active_bank;
    wire [3:0] read_fill_index=read_fill_active?physical_index_q:prefetch_physical_index;
    wire choose_read=s_arvalid&&(!s_awvalid||prefer_read_q);
    wire final_read_fire=(state==ROUT)&&s_rvalid&&s_rready&&s_rlast;
    wire final_write_fire=(state==BOUT)&&s_bvalid&&s_bready;
    wire offer_prefetch=(state==WADDR||state==WDATA||state==WRESP||
                         state==RADDR||state==RDATA||state==ROUT||state==BOUT||
                         (stream_active&&logical_index_q==logical_count_q))&&
                        !prefetch_valid&&
                        !final_read_fire&&!final_write_fire;
    // PIPEOPT7: one physical READ and one physical WRITE may overlap,
    // but only for disjoint physical 32-byte ranges. Same-direction and
    // possibly aliasing requests retain the PIPEOPT6R serialization fence.
    // Do not gate an already presented address on an upstream READY signal.
    wire prefetch_issue_safe=(state==ROUT||state==BOUT||state==RWAIT_PENDING);
    wire [30:0] active_end={1'b0,addr_q}+({27'd0,physical_count_q}<<5);
    wire [30:0] pending_end={1'b0,prefetch_addr}+({27'd0,prefetch_physical_count}<<5);
    wire disjoint_physical=(active_end<={1'b0,prefetch_addr}) ||
                           (pending_end<={1'b0,addr_q});
    // Active address must already have been accepted. This preserves the
    // old command order even on arbitrarily stalled AR/AW channels.
    wire active_read_inflight=(state==RDATA);
    wire active_write_inflight=(state==WDATA||state==WRESP||
                                 (stream_active&&active_aw_sent));
    wire pending_read_issue_safe=prefetch_issue_safe ||
      (DISJOINT_RW_OVERLAP&&disjoint_physical&&!prefetch_write&&active_write_inflight);
    wire pending_write_issue_safe=prefetch_issue_safe ||
      (DISJOINT_RW_OVERLAP&&disjoint_physical&&prefetch_write&&active_read_inflight);
    wire write_slot_available=(state==RADDR||state==RDATA||state==ROUT||
                               state==WRESP||state==BOUT||state==RWAIT_PENDING||
                               (state==WDATA&&
                                prefetch_half_index[4:1]<physical_index_q)||
                               (stream_active&&logical_index_q==logical_count_q&&
                                prefetch_half_index[4:1]<physical_index_q));
    wire wait_controller=(state==WADDR||state==WDATA||state==WRESP||
                          state==RADDR||state==RDATA||
                          prefetch_state==PADDR||prefetch_state==PDATA||
                          prefetch_state==PWADDR||prefetch_state==PWDATA||
                          prefetch_state==PWRESP||
                          (stream_active&&(!active_aw_sent||stream_write_valid))||
                          (stream_prefetch&&pending_write_issue_safe&&
                            ((!prefetch_aw_sent&&prefetch_logical_index!=0)||stream_prefetch_write_valid)));
    wire controller_progress=(m_awvalid&&m_awready)||(m_wvalid&&m_wready)||
                             (m_bvalid&&m_bready)||(m_arvalid&&m_arready)||
                             (m_rvalid&&(state==RDATA||prefetch_state==PDATA));
    function automatic logic legal(input logic [31:0] a,input logic [7:0] len,
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
    assign s_wready=!rst&&!protocol_fault&&(active_collect||state==BADWRITE||
                           (prefetch_state==PWC&&prefetch_logical_index<prefetch_logical_count&&
                            (prefetch_bad||write_slot_available)));
    assign s_bid=id_q;
    assign s_bresp=bresp_q;
    assign s_bvalid=!rst&&state==BOUT;
    assign s_rid=id_q;
    assign s_rdata=selected_data[128*half_index[0]+:128];
    assign s_rresp=(state==ROUT || stream_read_valid)?
                   resp_q[active_bank][half_index[4:1]]:2'b11;
    assign s_rvalid=!rst&&(state==ROUT||state==BADREAD||stream_read_valid);
    assign s_rlast=logical_index_q+1==logical_count_q;
    assign m_awid=(!active_aw_phase&&prefetch_aw_phase)?{4'b0,prefetch_id}:{4'b0,id_q};
    assign m_arid=(state!=RADDR&&prefetch_state==PADDR)?{4'b0,prefetch_id}:{4'b0,id_q};
    assign m_awaddr=(!active_aw_phase&&prefetch_aw_phase)?prefetch_addr:addr_q;
    assign m_araddr=(state!=RADDR&&prefetch_state==PADDR)?prefetch_addr:addr_q;
    assign m_awlen=(!active_aw_phase&&prefetch_aw_phase)?8'(prefetch_physical_count)-1:
                   8'(physical_count_q)-1;
    assign m_arlen=(state!=RADDR&&prefetch_state==PADDR)?8'(prefetch_physical_count)-1:
                   8'(physical_count_q)-1;
    assign m_awsize=5;
    assign m_arsize=5;
    assign m_awburst=1;
    assign m_arburst=1;
    assign m_awvalid=!rst&&ddr_ready&&
                     (state==WADDR||(stream_active&&!active_aw_sent)||
                      ((prefetch_state==PWADDR || (stream_prefetch&&!prefetch_aw_sent&&prefetch_logical_index!=0))
                        &&pending_write_issue_safe));
    assign m_arvalid=!rst&&ddr_ready&&
                     (state==RADDR||(prefetch_state==PADDR&&pending_read_issue_safe));
    wire [3:0] write_data_read_index=(prefetch_w_phase)?
                                    prefetch_physical_index:physical_index_q;
    assign m_wdata={wdata_high[write_data_read_index],wdata_low[write_data_read_index]};
    assign m_wstrb=(prefetch_w_phase)?mask_q[prefetch_physical_index]:
                   (active_w_phase)?mask_q[physical_index_q]:'0;
    assign m_wlast=(prefetch_w_phase)?
                   prefetch_physical_index+1==prefetch_physical_count:
                   physical_index_q+1==physical_count_q;
    assign m_wvalid=!rst&&ddr_ready&&!protocol_fault&&(state==WDATA||prefetch_state==PWDATA||
                                      stream_write_valid||stream_prefetch_write_valid);
    // Accept B only after the corresponding final physical W handshake.
    // Receiving/packing a write is not permission to retire its response.
    assign m_bready=!rst&&!protocol_fault&&(state==WRESP||prefetch_state==PWRESP);
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
            bresp_q<=0;watchdog_q<=0;prefer_read_q<=0;active_aw_sent<=0;prefetch_aw_sent<=0;
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
                    logical_index_q<=0;physical_index_q<=0;active_aw_sent<=0;
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
                WCOLLECT:if(STREAM_WRITE)begin
                    if(m_awvalid&&m_awready)active_aw_sent<=1'b1;
                    if(s_wvalid&&s_wready&&active_collect)begin
                        logical_index_q<=logical_index_q+1'b1;
                    end
                    if(stream_write_valid&&m_wready)begin
                        physical_index_q<=physical_index_q+1'b1;
                        if(m_wlast)state<=WRESP;
                    end
                    if(s_wvalid&&s_wready&&active_collect&&
                       s_wlast!=(logical_index_q+1==logical_count_q))state<=FAULT;
                end else if(s_wvalid&&s_wready)begin
                    logical_index_q<=logical_index_q+1'b1;
                    if(s_wlast!=(logical_index_q+1==logical_count_q))state<=FAULT;
                    else if(s_wlast)state<=WADDR;
                end
                BADWRITE:if(s_wvalid&&s_wready)begin
                    logical_index_q<=logical_index_q+1'b1;
                    if(s_wlast!=(logical_index_q+1==logical_count_q))state<=FAULT;
                    else if(s_wlast)begin state<=BOUT;bresp_q<=2'b11;end
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
                RDATA:begin
                    if(s_rvalid&&s_rready)logical_index_q<=logical_index_q+1'b1;
                    if(m_rvalid)begin
                        physical_index_q<=physical_index_q+1'b1;
                        if(m_rid!={4'b0,id_q}||m_rlast!=(physical_index_q+1==physical_count_q))state<=FAULT;
                        else if(m_rlast)state<=ROUT;
                    end
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
                prefetch_valid<=1;prefetch_id<=s_arid;prefetch_aw_sent<=0;
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
                // Only the pending command's own granted address may advance it.
                // Active RADDR/AWADDR handshakes can occur while PADDR/PWADDR
                // are queued; counting them for both slots aliases the IDs.
                PADDR:if(m_arvalid&&m_arready&&pending_read_issue_safe)prefetch_state<=PDATA;
                PDATA:if(m_rvalid)begin
                    prefetch_physical_index<=prefetch_physical_index+1'b1;
                    if(m_rid!={4'b0,prefetch_id}||
                       m_rlast!=(prefetch_physical_index+1==prefetch_physical_count))
                        state<=FAULT;
                    else if(m_rlast)prefetch_state<=PDONE;
                end
                PWC:if(STREAM_WRITE&&!prefetch_bad)begin
                    if(m_awvalid&&m_awready&&pending_write_issue_safe)prefetch_aw_sent<=1'b1;
                    if(s_wvalid&&s_wready&&!active_collect)
                        prefetch_logical_index<=prefetch_logical_index+1'b1;
                    if(stream_prefetch_write_valid&&m_wready)begin
                        prefetch_physical_index<=prefetch_physical_index+1'b1;
                        if(m_wlast)prefetch_state<=PWRESP;
                    end
                    if(s_wvalid&&s_wready&&!active_collect&&
                       s_wlast!=(prefetch_logical_index+1==prefetch_logical_count))state<=FAULT;
                end else if(s_wvalid&&s_wready&&!active_collect)begin
                    prefetch_logical_index<=prefetch_logical_index+1'b1;
                    if(s_wlast!=(prefetch_logical_index+1==prefetch_logical_count))state<=FAULT;
                    else if(s_wlast)begin
                        if(prefetch_bad)begin
                            prefetch_bresp<=2'b11;prefetch_state<=PDONE;
                        end else prefetch_state<=PWADDR;
                    end
                end
                PWADDR:if(m_awvalid&&m_awready&&pending_write_issue_safe)prefetch_state<=PWDATA;
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
    // One canonical write process per independent half keeps byte/half write
    // semantics without nine decoded FF-enable processes or a wide read mux.
    always_ff @(posedge clk)begin
        if(!rst&&!clear_active_mask&&(write_fill_active||write_fill_prefetch)&&
           write_fill_half[4:1]<4'd9)begin
            if(write_fill_half[0]==1'b0)wdata_low[write_fill_half[4:1]]<=s_wdata;
            if(write_fill_half[0]==1'b1)wdata_high[write_fill_half[4:1]]<=s_wdata;
        end
    end
    always_ff @(posedge clk)begin
        if(!rst&&m_rvalid&&(read_fill_active||read_fill_prefetch)&&
           read_fill_index<4'd9)
            rdata_memory[{read_fill_bank,read_fill_index}]<=m_rdata;
    end
    for(genvar beat=0;beat<9;beat++)begin:GEN_WRITE_BEAT
        always_ff @(posedge clk)begin
            if(!rst)begin
                if(clear_active_mask)mask_q[beat]<=0;
                else if((write_fill_active||write_fill_prefetch)&&
                        write_fill_half[4:1]==beat[3:0])begin
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
                        resp_q[bank][beat]<=m_rresp;
                    end
                end
            end
        end
    end
endmodule
