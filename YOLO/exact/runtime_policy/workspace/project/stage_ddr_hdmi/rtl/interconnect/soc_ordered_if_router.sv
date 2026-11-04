`timescale 1ns/1ps
// Ordered two-target fetch router with an EMPTY-QUEUE BYPASS.
// Target 0: ITCM, target 1: I-cache (including execute-protection errors).
// Requests are accepted into an owner queue independently of a blocking cache.
// An accepted request is NEVER cancelled, even after a CPU branch redirect.
// Neither target may complete a newly accepted request in that same clock cycle.
module soc_ordered_if_router #(
    parameter integer DEPTH=4,
    parameter logic [31:0] ITCM_BASE=32'h1000_0000,
    parameter logic [32:0] ITCM_BYTES=33'd65536
)(
    input logic clk,rst,stop_new,
    input logic req_valid,input logic [31:0] req_addr,output logic req_ready,
    output logic rsp_valid,output logic [31:0] rsp_rdata,output logic rsp_error,input logic rsp_ready,
    output logic [1:0] target_req_valid,output logic [31:0] target_req_addr,input logic [1:0] target_req_ready,
    input logic [1:0] target_rsp_valid,input logic [1:0][31:0] target_rsp_rdata,input logic [1:0] target_rsp_error,
    output logic [1:0] target_rsp_ready,
    output logic drained,output logic [$clog2(DEPTH+1)-1:0] outstanding
);
    localparam integer PW=$clog2(DEPTH), CW=$clog2(DEPTH+1);
    // A1：迁移 CP13 的 owner 独立触发器/并行译码思想。
    // 不改变 R3 的空队列直通：ITCM 和 I$ 都保留原有逐拍行为。
    // 不新增流水级，不改变地址队列、credit 和响应消费时序。
    logic [DEPTH-1:0] owner_q;
    logic [DEPTH-1:0] issue_zero, issue_one, next_head_one;
    logic head_owner;
    wire [PW-1:0] next_rd = rd + 1'b1;
    for (genvar g=0;g<DEPTH;g++) begin : owner_bits
        always_ff @(posedge clk)
            if (!rst && push && wr==PW'(g)) owner_q[g]<=selected;
        assign issue_zero[g]=(issue_ptr==PW'(g)) && !owner_q[g];
        assign issue_one[g]=(issue_ptr==PW'(g)) && owner_q[g];
        assign next_head_one[g]=(next_rd==PW'(g)) && owner_q[g];
    end
    // Cache the head owner on queue transitions. This removes the owner
    // lookup from response data -> instruction decode without adding a cycle.
    // On a one-entry pop+push, the incoming owner bypasses the old queue RAM.
    always_ff @(posedge clk) begin
        if (rst) head_owner <= 1'b0;
        else if (push && (outstanding==0 || (pop && outstanding==1)))
            head_owner <= selected;
        else if (pop && outstanding>1)
            head_owner <= |next_head_one;
    end
    logic [31:0] address[0:DEPTH-1];
    logic [PW-1:0] rd,wr,issue_ptr;
    logic [CW-1:0] queued;
    logic selected,issue_owner,issue_valid,push,pop,issue_fire;
    initial begin
        if(DEPTH<4||(DEPTH&(DEPTH-1))!=0) $fatal(1,"SOC_IF_DEPTH");
    end
    assign selected=!({1'b0,req_addr}>={1'b0,ITCM_BASE} &&
                      {1'b0,req_addr}<{1'b0,ITCM_BASE}+ITCM_BYTES);
    assign req_ready=!rst&&!stop_new&&(outstanding<CW'(DEPTH));
    assign push=req_valid&&req_ready;
    // The old R4 router ALWAYS waited a cycle before issuing to ITCM.
    // Here the address/valid fall through while the issue queue is empty.
    assign issue_owner=(queued!=0)?(|issue_one):selected;
    assign target_req_addr=(queued!=0)?address[issue_ptr]:req_addr;
    assign issue_valid=!rst&&((queued!=0)||push);
    assign issue_fire=|(target_req_valid & target_req_ready);
    assign rsp_valid=!rst&&(outstanding!=0)&&target_rsp_valid[head_owner];
    // Response data is meaningful only with rsp_valid. Removing the
    // invalid-cycle zero mux keeps outstanding off the 32-bit data path.
    assign rsp_rdata=target_rsp_rdata[head_owner];
    assign rsp_error=(outstanding!=0)&&target_rsp_error[head_owner];
    assign pop=rsp_valid&&rsp_ready;
    assign drained=(outstanding==0);
    always_comb begin
        // 各目的端 valid 独立译码，避免 owner 编码后再动态索引输出。
        target_req_valid[0]=!rst && (((queued!=0) && (|issue_zero)) ||
                                   ((queued==0) && push && !selected));
        target_req_valid[1]=!rst && (((queued!=0) && (|issue_one)) ||
                                   ((queued==0) && push && selected));
        target_rsp_ready='0;
        if(!rst&&outstanding!=0) target_rsp_ready[head_owner]=rsp_ready;
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            rd<='0;wr<='0;issue_ptr<='0;outstanding<='0;queued<='0;
        end else begin
            if(push) begin address[wr]<=req_addr;wr<=wr+1'b1;end
            if(issue_fire) issue_ptr<=issue_ptr+1'b1;
            if(pop) rd<=rd+1'b1;
            case({push,issue_fire})
                2'b10:queued<=queued+1'b1;
                2'b01:queued<=queued-1'b1;
                default:begin end
            endcase
            case({push,pop})
                2'b10:outstanding<=outstanding+1'b1;
                2'b01:outstanding<=outstanding-1'b1;
                default:begin end
            endcase
        end
    end
`ifdef DC_RT_VERIFICATION
    always_ff @(posedge clk) if(!rst) begin
        assert(queued<=outstanding) else $fatal(1,"IF_QUEUE_ACCOUNTING");
        assert(outstanding<=CW'(DEPTH)) else $fatal(1,"IF_OWNER_OVERFLOW");
        assert(!(target_req_valid[0]&&target_req_valid[1])) else $fatal(1,"IF_DOUBLE_ISSUE");
        assert(!(target_rsp_ready[0]&&target_rsp_ready[1])) else $fatal(1,"IF_DOUBLE_RESPONSE");
    end
`endif
endmodule
