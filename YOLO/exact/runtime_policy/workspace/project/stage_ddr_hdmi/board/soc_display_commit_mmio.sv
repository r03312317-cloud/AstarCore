`timescale 1ns/1ps
// UI-domain framebuffer coverage and atomic metadata publication.
// Passive snoop of the LAST logical AXI write stream. AXI W has no ID:
// W bursts bind to AW acceptance order; B must match that same order on
// the existing ordered HMIC adapter. All reset together with the bus.
module soc_display_commit_mmio #(
    parameter int FRAME_BYTES=640*480*2,
    parameter int BOX_WIDTH=640,BOX_HEIGHT=480,
    parameter int TRACK_DEPTH=4,
    parameter logic [3:0] MMIO_PAGE=4'h2,
    parameter bit REQUIRE_PRESENT_ACK=0,
    parameter bit SCOPED_WRITER=0, // observe only IMG master AW/W/B in this mode
    parameter logic [31:0] FB_MIN=32'h82000000,
    parameter logic [31:0] FB_LIMIT=32'h82400000
)(
    input logic clk,rst,ddr_ready,axi_poisoned,
    input logic [63:0] cpu_time_gray,
    input logic req_valid,output logic req_ready,
    input logic [15:0] req_addr,input logic req_write,
    input logic [31:0] req_wdata,input logic [3:0] req_wstrb,
    output logic rsp_valid,input logic rsp_ready,
    output logic [31:0] rsp_rdata,output logic rsp_error,
    input logic awvalid,awready,input logic [31:0] awaddr,
    input logic [3:0] awid,input logic [7:0] awlen,
    input logic [2:0] awsize,input logic [1:0] awburst,
    input logic wvalid,wready,input logic [15:0] wstrb,input logic wlast,
    input logic bvalid,bready,input logic [3:0] bid,input logic [1:0] bresp,
    output logic publish_valid,input logic publish_ready,
    output logic [31:0] publish_fb,publish_frame,publish_run,
    output logic [31:0] publish_xy1,publish_xy2,publish_score,publish_class,
    output logic [31:0] publish_count,publish_sequence,
    input logic display_valid,input logic [31:0] display_fb,
    input logic pending_display_valid,input logic [31:0] pending_display_fb
);
    localparam int PW=$clog2(TRACK_DEPTH);
    typedef struct packed {
        logic valid,frame,w_done;
        logic [3:0] id;
        logic [31:0] address,payload;
        logic [8:0] beats,seen;
    } tx_t;
    tx_t tx[TRACK_DEPTH],tx_n[TRACK_DEPTH];
    logic [PW-1:0] aw_tail,b_head,w_head,aw_tail_n,b_head_n,w_head_n;
    logic [PW:0] pending,w_pending,pending_n,w_pending_n;
    logic [PW:0] frame_pending,frame_pending_n;
    logic scope_fault,scope_fault_n;
    logic armed,ready_flag,nms_done,active_valid;
    logic [7:0] error_code,error_n;
    logic [31:0] accepted_bytes,committed_bytes,accepted_n,committed_n;
    logic [31:0] shadow_fb,shadow_frame,shadow_xy1,shadow_xy2;
    logic [31:0] shadow_score,shadow_class,shadow_count;
    logic [31:0] active_fb,active_frame,active_xy1,active_xy2;
    logic [31:0] active_score,active_class,active_count,commit_sequence;
    logic [31:0] shadow_run,active_run;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic [63:0] cpu_gray_meta,cpu_gray_sync;
    logic [63:0] cpu_binary,cpu_ticks,tf_ticks,tr_ticks;
    logic tf_recorded;
    logic [31:0] tracked_fb;
    // Register this passive observation boundary. Cascaded AXI ready/mux
    // logic must not feed the complete coverage checker in the same cycle.
    // No ready/valid on the real bus is changed by this observer.
    logic aw_seen,w_seen,b_seen;
    logic [31:0] awaddr_seen;
    logic [3:0] awid_seen,bid_seen;
    logic [7:0] awlen_seen;
    logic [2:0] awsize_seen;
    logic [1:0] awburst_seen,bresp_seen;
    logic [15:0] wstrb_seen;
    logic wlast_seen;
    logic [63:0] last_b_ticks;
    wire [32:0] shadow_end={1'b0,shadow_fb}+FRAME_BYTES;
    wire [32:0] tracked_end={1'b0,tracked_fb}+FRAME_BYTES;
    wire [32:0] live_aw_end={1'b0,awaddr}+(({25'b0,awlen}+33'd1)<<4);
    wire shadow_aw_hit=awvalid && {1'b0,awaddr}<shadow_end &&
                                  live_aw_end>{1'b0,shadow_fb};
    wire tracked_aw_hit=awvalid && {1'b0,awaddr}<tracked_end &&
                                   live_aw_end>{1'b0,tracked_fb};
    wire aw_fire=aw_seen,w_fire=w_seen,b_fire=b_seen;
    wire observation_pending=aw_seen||w_seen||b_seen;
    wire access=req_valid&&req_ready;
    wire [7:0] off={req_addr[7:2],2'b0};
    wire metadata_ok=shadow_count<=1 &&
        (shadow_count==0 || (shadow_xy1[15:0]<shadow_xy2[15:0] &&
         shadow_xy1[31:16]<shadow_xy2[31:16] && shadow_xy2[15:0]<=BOX_WIDTH &&
         shadow_xy2[31:16]<=BOX_HEIGHT && shadow_score<=32768));
    assign req_ready=!rsp_valid || rsp_ready;
    assign publish_fb=active_fb;assign publish_frame=active_frame;
    assign publish_run=active_run;assign publish_xy1=active_xy1;
    assign publish_xy2=active_xy2;assign publish_score=active_score;
    assign publish_class=active_class;assign publish_count=active_count;
    assign publish_sequence=commit_sequence;
    always_comb for(integer i=0;i<64;i++)cpu_binary[i]=^(cpu_gray_sync>>i);

    function automatic logic [4:0] strobe_bytes(input logic [15:0] s);
        logic [2:0] a,b,c,d;
        begin
            a={2'b0,s[0]}+{2'b0,s[1]}+{2'b0,s[2]}+{2'b0,s[3]};
            b={2'b0,s[4]}+{2'b0,s[5]}+{2'b0,s[6]}+{2'b0,s[7]};
            c={2'b0,s[8]}+{2'b0,s[9]}+{2'b0,s[10]}+{2'b0,s[11]};
            d={2'b0,s[12]}+{2'b0,s[13]}+{2'b0,s[14]}+{2'b0,s[15]};
            strobe_bytes=({2'b0,a}+{2'b0,b})+({2'b0,c}+{2'b0,d});
        end
    endfunction

    always_ff @(posedge clk) begin
        if(rst) begin
            aw_seen<=0;w_seen<=0;b_seen<=0;last_b_ticks<=0;
            
            
        end else begin
            aw_seen<=awvalid&&awready;w_seen<=wvalid&&wready;b_seen<=bvalid&&bready;
            
            
            
            if(bvalid&&bready&&!SCOPED_WRITER)last_b_ticks<=cpu_ticks;
            if(SCOPED_WRITER && b_seen && pending!=0 && tx[b_head].valid &&
               tx[b_head].w_done && tx[b_head].frame &&
               tx[b_head].id==bid_seen && bresp_seen==0)last_b_ticks<=cpu_ticks;
        end
    end

    // The passive AXI observation payload is sampled every UI clock.
    // aw_seen/w_seen/b_seen retain their original reset and handshake rules;
    // coverage consumes each payload only under its matching seen bit.
    // No CDC stage, timestamp, transaction owner or MMIO reset is changed.
    always_ff @(posedge clk) begin
        awaddr_seen <= awaddr;
        awid_seen <= awid;
        awlen_seen <= awlen;
        awsize_seen <= awsize;
        awburst_seen <= awburst;
        wstrb_seen <= wstrb;
        wlast_seen <= wlast;
        bid_seen <= bid;
        bresp_seen <= bresp;
    end

    // No bus feedback: faults prevent publication, never alter AXI ready.
    always_comb begin : coverage
        logic [32:0] end_address,effective_address,expected_address;
        logic [15:0] contiguous;
        logic [4:0] first_byte,byte_count;
        for(integer i=0;i<TRACK_DEPTH;i=i+1) tx_n[i]=tx[i];
        aw_tail_n=aw_tail;b_head_n=b_head;w_head_n=w_head;
        pending_n=pending;w_pending_n=w_pending;frame_pending_n=frame_pending;
        scope_fault_n=scope_fault;
        error_n=error_code;accepted_n=accepted_bytes;committed_n=committed_bytes;
        end_address=0;effective_address=0;expected_address=0;
        contiguous=0;first_byte=0;byte_count=0;
        if(aw_fire) begin
            end_address={1'b0,awaddr_seen}+(({25'b0,awlen_seen}+33'd1)<<4);
            if(pending_n==TRACK_DEPTH) error_n=8'd1;
            else begin
                tx_n[aw_tail_n]='0;tx_n[aw_tail_n].valid=1;
                tx_n[aw_tail_n].id=awid_seen;tx_n[aw_tail_n].address=awaddr_seen;
                tx_n[aw_tail_n].beats={1'b0,awlen_seen}+9'd1;
                tx_n[aw_tail_n].frame=armed &&
                    ({1'b0,awaddr_seen}<({1'b0,tracked_fb}+FRAME_BYTES)) &&
                    (end_address>{1'b0,tracked_fb});
                if(tx_n[aw_tail_n].frame &&
                   (awsize_seen!=4 || awburst_seen!=1 || awaddr_seen[3:0]!=0 ||
                    ({1'b0,awaddr_seen[11:0]}+(({5'b0,awlen_seen}+13'd1)<<4)>4096) ||
                    awaddr_seen<tracked_fb || end_address>({1'b0,tracked_fb}+FRAME_BYTES)))
                    error_n=8'd2;
                // Scoped mode observes only the IMG master. Other IMG writes
                // may target the next input, but may not touch the FB arena.
                if(armed && !tx_n[aw_tail_n].frame && !SCOPED_WRITER)
                    error_n=8'd3;
                if(SCOPED_WRITER && !tx_n[aw_tail_n].frame &&
                   {1'b0,awaddr_seen}<{1'b0,FB_LIMIT} &&
                   end_address>{1'b0,FB_MIN})begin
                    error_n=8'd3;scope_fault_n=1'b1;
                end
                if(tx_n[aw_tail_n].frame) frame_pending_n=frame_pending_n+1'b1;
                aw_tail_n=aw_tail_n+1'b1;
                pending_n=pending_n+1'b1;w_pending_n=w_pending_n+1'b1;
            end
        end
        if(w_fire) begin
            if(w_pending_n==0 || !tx_n[w_head_n].valid || tx_n[w_head_n].w_done)
                error_n=8'd4;
            else begin
                tx_n[w_head_n].seen=tx_n[w_head_n].seen+9'd1;
                if(wlast_seen != (tx_n[w_head_n].seen==tx_n[w_head_n].beats))
                    error_n=8'd5;
                if(tx_n[w_head_n].frame) begin
                    first_byte=5'd16;byte_count=strobe_bytes(wstrb_seen);
                    for(integer lane=15;lane>=0;lane=lane-1)
                        if(wstrb_seen[lane])first_byte=5'(lane);
                    if(byte_count!=0) contiguous=(16'hffff>>(5'd16-byte_count))<<first_byte;
                    effective_address={1'b0,tx_n[w_head_n].address}+
                        (({24'b0,tx_n[w_head_n].seen}-33'd1)<<4)+33'(first_byte);
                    expected_address={1'b0,tracked_fb}+{1'b0,accepted_n};
                    if(byte_count==0 || wstrb_seen!=contiguous || effective_address!=expected_address ||
                       accepted_n+32'(byte_count)>FRAME_BYTES) error_n=8'd6;
                    else begin
                        accepted_n=accepted_n+32'(byte_count);
                        tx_n[w_head_n].payload=tx_n[w_head_n].payload+32'(byte_count);
                    end
                end
                if(wlast_seen) begin
                    tx_n[w_head_n].w_done=1;
                    w_head_n=w_head_n+1'b1;w_pending_n=w_pending_n-1'b1;
                end
            end
        end
        if(b_fire) begin
            if(pending_n==0 || !tx_n[b_head_n].valid || !tx_n[b_head_n].w_done ||
               bid_seen!=tx_n[b_head_n].id) error_n=8'd7;
            else begin
                if(bresp_seen!=0)error_n=8'd8;
                if(tx_n[b_head_n].frame && bresp_seen==0)
                    committed_n=committed_n+tx_n[b_head_n].payload;
                if(tx_n[b_head_n].frame)frame_pending_n=frame_pending_n-1'b1;
                tx_n[b_head_n]='0;b_head_n=b_head_n+1'b1;
                pending_n=pending_n-1'b1;
            end
        end
        if(armed && axi_poisoned)error_n=8'd9;
    end

    always_ff @(posedge clk) begin
        if(rst) begin
            rsp_valid<=0;rsp_error<=0;rsp_rdata<=0;
            aw_tail<=0;b_head<=0;w_head<=0;pending<=0;w_pending<=0;
            frame_pending<=0;scope_fault<=0;
            for(integer i=0;i<TRACK_DEPTH;i=i+1)tx[i]<='0;
            armed<=0;ready_flag<=0;nms_done<=0;active_valid<=0;error_code<=0;
            accepted_bytes<=0;committed_bytes<=0;tracked_fb<=0;
            shadow_fb<=0;shadow_frame<=0;shadow_xy1<=0;shadow_xy2<=0;
            shadow_score<=0;shadow_class<=0;shadow_count<=0;
            active_fb<=0;active_frame<=0;active_xy1<=0;active_xy2<=0;
            active_score<=0;active_class<=0;active_count<=0;commit_sequence<=0;
            shadow_run<=0;active_run<=0;publish_valid<=0;
            cpu_gray_meta<=0;cpu_gray_sync<=0;cpu_ticks<=0;tf_ticks<=0;tr_ticks<=0;tf_recorded<=0;
        end else begin
            cpu_gray_meta<=cpu_time_gray;cpu_gray_sync<=cpu_gray_meta;cpu_ticks<=cpu_binary;
            aw_tail<=aw_tail_n;b_head<=b_head_n;w_head<=w_head_n;
            pending<=pending_n;w_pending<=w_pending_n;
            frame_pending<=frame_pending_n;scope_fault<=scope_fault_n;
            for(integer i=0;i<TRACK_DEPTH;i=i+1)tx[i]<=tx_n[i];
            error_code<=error_n;accepted_bytes<=accepted_n;committed_bytes<=committed_n;
            if(rsp_valid&&rsp_ready)rsp_valid<=0;
            if(publish_valid&&publish_ready)publish_valid<=0;
            // Qualify registered proof state. Keep the timestamp captured at
            // the actual B handshake, even though validation completes later.
            if(armed&&error_code==0&&committed_bytes==FRAME_BYTES&&
               (SCOPED_WRITER ? (frame_pending==0 && !tracked_aw_hit) :
                (pending==0 && !observation_pending && !awvalid && !wvalid && !bvalid))&&
               !tf_recorded)begin
                tf_ticks<=last_b_ticks;tf_recorded<=1;
            end
            if(access) begin
                rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;
                if(req_addr[11:8]!=MMIO_PAGE || req_addr[1:0]!=0 ||
                   (req_write && req_wstrb!=4'hf)) rsp_error<=1;
                else if(req_write) begin
                    case(off)
                    8'h00: begin
                        if(req_wdata==1) begin // ARM: no earlier bus ownership survives.
                            ready_flag<=0;
                            // In scoped mode this is only the IMG producer,
                            // not the global DDR bus: start from a clean IMG.
                            if(!ddr_ready||axi_poisoned||armed||scope_fault||
                               pending!=0 || observation_pending ||
                               awvalid || wvalid || bvalid || shadow_aw_hit ||
                               shadow_fb[3:0]!=0||shadow_fb<FB_MIN||
                               {1'b0,shadow_fb}+FRAME_BYTES>{1'b0,FB_LIMIT}||
                               (active_valid && shadow_fb==active_fb)||
                               (REQUIRE_PRESENT_ACK && (publish_valid ||
                                (display_valid && shadow_fb==display_fb) ||
                                (pending_display_valid && shadow_fb==pending_display_fb)))) begin
                                armed<=0;error_code<=8'd10;
                            end else begin
                                armed<=1;tracked_fb<=shadow_fb;nms_done<=0;error_code<=0;
                                accepted_bytes<=0;committed_bytes<=0;
                                tf_ticks<=0;tr_ticks<=0;tf_recorded<=0;
                            end
                        end else if(req_wdata==2) begin // NMS_DONE after real software result.
                            if(!armed)error_code<=8'd11;else nms_done<=1;
                        end else if(req_wdata==4) begin // atomic COMMIT
                            // No observed transaction remains when this can
                            // succeed. Read registered proof, not the masked
                            // AW/W/B next-state arithmetic. error_n below keeps
                            // the original first-error precedence on rejection.
                            if(!armed||!nms_done||error_code!=0||axi_poisoned||!metadata_ok||
                               shadow_fb!=tracked_fb||accepted_bytes!=FRAME_BYTES||
                               committed_bytes!=FRAME_BYTES||
                               (SCOPED_WRITER ? (frame_pending!=0 || tracked_aw_hit) :
                                (pending!=0||observation_pending||awvalid||wvalid||bvalid))||
                               (REQUIRE_PRESENT_ACK && publish_valid))
                                error_code<=error_n!=0?error_n:8'd12;
                            else begin
                                active_fb<=tracked_fb;active_frame<=shadow_frame;
                                active_xy1<=shadow_count?shadow_xy1:0;
                                active_xy2<=shadow_count?shadow_xy2:0;
                                active_score<=shadow_count?shadow_score:0;
                                active_class<=shadow_count?shadow_class:0;
                                active_count<=shadow_count;active_valid<=1;
                                active_run<=shadow_run;
                                commit_sequence<=commit_sequence+1'b1;
                                publish_valid<=REQUIRE_PRESENT_ACK;
                                tr_ticks<=cpu_ticks;
                                ready_flag<=1;armed<=0;
                            end
                        end else if(req_wdata==8) begin // bounded safe ABORT, old active remains.
                            if(pending!=0||observation_pending||awvalid||wvalid||bvalid)error_code<=8'd10;
                            else begin
                                armed<=0;ready_flag<=0;nms_done<=0;error_code<=0;
                                accepted_bytes<=0;committed_bytes<=0;
                            end
                        end else if(req_wdata==16) begin // metadata on currently scanned complete image
                            if(!SCOPED_WRITER||!ddr_ready||armed||!active_valid||!metadata_ok||axi_poisoned||
                               pending!=0||observation_pending||awvalid||wvalid||bvalid||
                               publish_valid||pending_display_valid||!display_valid||display_fb!=active_fb||
                               shadow_fb!=active_fb)
                                error_code<=8'd12;
                            else begin
                                active_frame<=shadow_frame;active_run<=shadow_run;
                                active_xy1<=shadow_count?shadow_xy1:0;
                                active_xy2<=shadow_count?shadow_xy2:0;
                                active_score<=shadow_count?shadow_score:0;
                                active_class<=shadow_count?shadow_class:0;
                                active_count<=shadow_count;commit_sequence<=commit_sequence+1'b1;
                                publish_valid<=REQUIRE_PRESENT_ACK;tr_ticks<=cpu_ticks;
                                ready_flag<=1;error_code<=0;
                            end
                        end else rsp_error<=1;
                    end
                    8'h08:if(armed)rsp_error<=1;else shadow_fb<=req_wdata;
                    8'h0c:shadow_frame<=req_wdata;
                    8'h10:shadow_xy1<=req_wdata;
                    8'h14:shadow_xy2<=req_wdata;
                    8'h18:shadow_score<=req_wdata;
                    8'h1c:shadow_class<=req_wdata;
                    8'h20:shadow_count<=req_wdata;
                    8'h54:shadow_run<=req_wdata;
                    default:rsp_error<=1;
                    endcase
                end else case(off)
                    8'h00:rsp_rdata<=32'h31505344; // DSP1
                    8'h04:rsp_rdata<={SCOPED_WRITER,7'b0,error_code,11'b0,active_valid,nms_done,ready_flag,armed,ddr_ready};
                    8'h08:rsp_rdata<=shadow_fb;
                    8'h0c:rsp_rdata<=shadow_frame;
                    8'h24:rsp_rdata<=accepted_bytes;
                    8'h28:rsp_rdata<=committed_bytes;
                    8'h2c:rsp_rdata<=SCOPED_WRITER?32'(frame_pending):32'(pending);
                    8'h30:rsp_rdata<=active_fb;
                    8'h34:rsp_rdata<=active_frame;
                    8'h38:rsp_rdata<=active_xy1;
                    8'h3c:rsp_rdata<=active_xy2;
                    8'h40:rsp_rdata<=active_score;
                    8'h44:rsp_rdata<=active_class;
                    8'h48:rsp_rdata<=active_count;
                    8'h4c:rsp_rdata<=commit_sequence;
                    8'h50:rsp_rdata<=FRAME_BYTES;
                    8'h54:rsp_rdata<=shadow_run;
                    8'h58:rsp_rdata<=active_run;
                    8'h5c:rsp_rdata<={31'b0,publish_valid};
                    8'h60:rsp_rdata<=tf_ticks[31:0];
                    8'h64:rsp_rdata<=tf_ticks[63:32];
                    8'h68:rsp_rdata<=tr_ticks[31:0];
                    8'h6c:rsp_rdata<=tr_ticks[63:32];
                    8'h70:rsp_rdata<={31'b0,SCOPED_WRITER};
                    8'h74:rsp_rdata<=32'(pending);
                    8'h78:rsp_rdata<={31'b0,scope_fault};
                    // Preserve PIPEOPT5 diagnostic registers 70/74/78.
                    // Preview uses these new status registers and the same
                    // owned IMG writer; unrelated graph/camera writes cannot
                    // satisfy a framebuffer coverage proof.
                    8'h84:rsp_rdata<={27'b0,scope_fault,1'b0,publish_valid,pending_display_valid,display_valid};
                    8'h88:rsp_rdata<=display_fb;
                    8'h8c:rsp_rdata<=pending_display_fb;
                    default:rsp_error<=1;
                endcase
            end
        end
    end
    initial begin
        if(TRACK_DEPTH<2 || (TRACK_DEPTH&(TRACK_DEPTH-1))!=0 || FRAME_BYTES%16!=0)
            $fatal(1,"DISPLAY_COMMIT_BAD_PARAMETERS");
    end
endmodule
