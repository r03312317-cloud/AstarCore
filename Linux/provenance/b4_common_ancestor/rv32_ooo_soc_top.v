// Original integration boundary for RV32. External port spelling follows
// the neutral compatibility contract; no original CPU implementation is used.
module rv32_ooo_soc_top #(
    parameter [31:0] RESET_VECTOR=32'h10000000,
    parameter ENABLE_PAIRING=1,
    parameter LOAD_ORDER_ISSUE_LOOKAHEAD=1,
    parameter MEMORY_CREDITS=3,
    parameter FETCH_CREDITS=2,
    parameter ENABLE_COMMITTED_RAS=1,
    parameter RAS_DEPTH=16,
    parameter HISTORY_BITS=8,
    parameter BIMODAL_INDEX_BITS=7,
    parameter GSHARE_INDEX_BITS=8,
    parameter REGISTER_INSTRUCTION_REQUEST=0,
    parameter REGISTER_RESPONSES=0,
    parameter FAST_WAKEUP=1,
    parameter ENABLE_SAME_CYCLE_REUSE=0,
    parameter CARRIED_COMPLETION_WRITES=1,
    parameter DECOUPLED_ALLOCATION_PAYLOAD=1,
    parameter BANKED_ISSUE=1,
    parameter ENABLE_MDU_TURNOVER=1,
    parameter ENABLE_MDU_SPILL=1,
    parameter ENABLE_MUL_STREAM=1,
    parameter ENABLE_STEALING=1,
    parameter ENABLE_ORDERED_STORE_PREP=1,
    parameter ENABLE_STORE_HEAD_LOOKAHEAD=0,
    parameter ENABLE_STORE_ISSUE_LOOKAHEAD=0,
    parameter ENABLE_REDIRECT_FETCH=1,
    parameter ENABLE_CURRENT_INTEGER_PAIR=1,
    parameter DISPATCH_BYPASS_UNMAPPED_ONLY=1,
    parameter ENABLE_CONTROL_DISPATCH=1,
    parameter ENABLE_DISPATCH_BYPASS=1,
    parameter LOAD_BYPASS=0,
    parameter I_INDEX_BITS=8,
    parameter D_INDEX_BITS=6,
    parameter D_WAYS=2,
    parameter ENABLE_FAST_ICROSS=0,
    parameter ENABLE_DATA_RAM_GUARD=0,
    parameter [31:0] DATA_RAM_BASE=32'h00000000,
    parameter [31:0] DATA_RAM_LIMIT=32'hffffffff
)(
    input clk, reset,
    output instr_req_o, input instr_gnt_i,
    output [31:0] instr_addr_o, output instr_io_o,
    input instr_rvalid_i, output instr_rready_o,
    input [63:0] instr_rdata_i, input instr_err_i,
    input irq_timer_i, irq_software_i, irq_external_i,
    input [63:0] mtime_i,
    output periph_req_o, input periph_gnt_i,
    output periph_we_o, output [31:0] periph_addr_o,
    output [31:0] periph_wdata_o, output [3:0] periph_be_o,
    output [1:0] periph_size_o,
    input periph_rvalid_i, input periph_err_i,
    input [31:0] periph_rdata_i,
    output data_rd_req_o, input data_rd_gnt_i,
    output data_rd_id_o, output [31:0] data_rd_addr_o,
    input data_rd_rvalid_i, output data_rd_rready_o,
    input data_rd_rid_i, input [63:0] data_rd_rdata_i,
    input data_rd_err_i,
    output data_wr_req_o, input data_wr_gnt_i,
    output data_wr_last_o, output [31:0] data_wr_addr_o,
    output [63:0] data_wr_data_o, output data_wr_id_o,
    input data_wr_bvalid_i, input data_wr_berr_i, input data_wr_bid_i,
    output [1:0] trace_retire_mask_o, trace_retire_count_o,
    output [5:0] trace_retire_rob_id_o,
    output trace_reschedule_o,
    output [7:0] trace_reschedule_reason_o,
    output trace_reschedule_trap_o,
    output trace_branch_miss_o, trace_jump_miss_o,
    output trace_dispatch_stall_o, trace_frontend_stall_o
);
    wire iv, ir, ipv, ipr;
    wire [31:0] ia;
    wire [63:0] ipd;
    wire [1:0] ipe;
    wire cache_iv,cache_ir,cache_ipv,cache_ipr;
    wire [31:0] cache_ia;
    wire [63:0] cache_ipd;
    wire [1:0] cache_ipe;
    reg i_request_valid,i_response_valid;
    reg [31:0] i_request_address;
    reg [63:0] i_response_data;
    reg [1:0] i_response_error;
    // Early/corrected fetch addresses now come from cursor/held registers.
    // Direct requests remove the historical extra request-register latency.
    // The frontend retains every accepted owner's sticky cancellation metadata.
    generate if(REGISTER_INSTRUCTION_REQUEST)begin:registered_instruction_request
        assign ir=!reset&&(!i_request_valid||cache_ir);
        assign cache_iv=!reset&&i_request_valid;
        assign cache_ia=i_request_address;
        always @(posedge clk)begin
            if(reset)i_request_valid<=0;
            else if(ir)begin i_request_valid<=iv;if(iv)i_request_address<=ia;end
        end
    end else begin:direct_instruction_request
        assign ir=cache_ir;assign cache_iv=iv;assign cache_ia=ia;
    end endgenerate
    generate if(REGISTER_RESPONSES)begin:registered_instruction_response
        assign cache_ipr=!reset&&(!i_response_valid||ipr);
        assign ipv=!reset&&i_response_valid;
        assign ipd=i_response_data;
        assign ipe=i_response_error;
        always @(posedge clk)begin
            if(reset)i_response_valid<=0;
            else if(cache_ipr)begin
                i_response_valid<=cache_ipv;
                if(cache_ipv)begin i_response_data<=cache_ipd;i_response_error<=cache_ipe;end
            end
        end
    end else begin:direct_instruction_response
        assign cache_ipr=ipr;
        assign ipv=cache_ipv;
        assign ipd=cache_ipd;
        assign ipe=cache_ipe;
    end endgenerate
    // Declare the module data wires before generate scopes. PDS otherwise
    // creates a local implicit dpd and ties the processor input to zero.
    wire [31:0] da, dwd, dpd;
    wire dv, dr, dw, dpv, dpr, dpe;
    wire raw_dpv,raw_dpr,raw_dpe;
    wire [31:0] raw_dpd;
    reg response_valid,response_error;
    reg [31:0] response_data;
    generate if(REGISTER_RESPONSES)begin:registered_data_response
        assign raw_dpr=!reset&&(!response_valid||dpr);
        assign dpv=!reset&&response_valid;
        assign dpd=response_data;
        assign dpe=response_error;
        always @(posedge clk)begin
            if(reset)response_valid<=0;
            else if(raw_dpr)begin
                response_valid<=raw_dpv;
                if(raw_dpv)begin response_data<=raw_dpd;response_error<=raw_dpe;end
            end
        end
    end else begin:direct_data_response
        assign raw_dpr=dpr;
        assign dpv=raw_dpv;
        assign dpd=raw_dpd;
        assign dpe=raw_dpe;
    end endgenerate
    wire [3:0] ds;
    wire [1:0] dz;
    wire fi, fd, maintenance_busy;
    wire event_i, event_d, event_w;
    wire [31:0] retire_pc0, retire_pc1, retire_instruction0, retire_instruction1;
    wire [4:0] retire_destination0, retire_destination1;
    wire [31:0] retire_value0, retire_value1;

    rv32_ooo_core #(.RESET_VECTOR(RESET_VECTOR),.LOAD_ORDER_ISSUE_LOOKAHEAD(LOAD_ORDER_ISSUE_LOOKAHEAD),.MEMORY_CREDITS(MEMORY_CREDITS),.FETCH_CREDITS(FETCH_CREDITS),.ENABLE_COMMITTED_RAS(ENABLE_COMMITTED_RAS),.RAS_DEPTH(RAS_DEPTH),.HISTORY_BITS(HISTORY_BITS),.BIMODAL_INDEX_BITS(BIMODAL_INDEX_BITS),.GSHARE_INDEX_BITS(GSHARE_INDEX_BITS),.ENABLE_PAIRING(ENABLE_PAIRING),.FAST_WAKEUP(FAST_WAKEUP),.ENABLE_SAME_CYCLE_REUSE(ENABLE_SAME_CYCLE_REUSE),.CARRIED_COMPLETION_WRITES(CARRIED_COMPLETION_WRITES),.DECOUPLED_ALLOCATION_PAYLOAD(DECOUPLED_ALLOCATION_PAYLOAD),.BANKED_ISSUE(BANKED_ISSUE),.ENABLE_MDU_TURNOVER(ENABLE_MDU_TURNOVER),.ENABLE_MDU_SPILL(ENABLE_MDU_SPILL),.ENABLE_MUL_STREAM(ENABLE_MUL_STREAM),.ENABLE_STEALING(ENABLE_STEALING),.ENABLE_ORDERED_STORE_PREP(ENABLE_ORDERED_STORE_PREP),.ENABLE_STORE_HEAD_LOOKAHEAD(ENABLE_STORE_HEAD_LOOKAHEAD),.ENABLE_STORE_ISSUE_LOOKAHEAD(ENABLE_STORE_ISSUE_LOOKAHEAD),.ENABLE_REDIRECT_FETCH(ENABLE_REDIRECT_FETCH),.ENABLE_CURRENT_INTEGER_PAIR(ENABLE_CURRENT_INTEGER_PAIR),.ENABLE_CONTROL_DISPATCH(ENABLE_CONTROL_DISPATCH),.ENABLE_DISPATCH_BYPASS(ENABLE_DISPATCH_BYPASS),.DISPATCH_BYPASS_UNMAPPED_ONLY(DISPATCH_BYPASS_UNMAPPED_ONLY),.LOAD_BYPASS(LOAD_BYPASS),.ENABLE_TRACE(0)) processor (
        .clk(clk),.reset(reset),
        .imem_request_valid(iv),.imem_request_ready(ir),.imem_request_address(ia),
        .imem_response_valid(ipv),.imem_response_ready(ipr),
        .imem_response_data(ipd),.imem_response_error(ipe),
        .dmem_request_valid(dv),.dmem_request_ready(dr),.dmem_request_address(da),
        .dmem_request_write(dw),.dmem_request_size(dz),.dmem_request_wdata(dwd),
        .dmem_request_wstrb(ds),.dmem_response_valid(dpv),.dmem_response_ready(dpr),
        .dmem_response_rdata(dpd),.dmem_response_error(dpe),
        .irq_software(irq_software_i),.irq_timer(irq_timer_i),.irq_external(irq_external_i),
        .mtime(mtime_i),.event_icache_refill(event_i),.event_dcache_refill(event_d),
        .event_dcache_writeback(event_w),.fence_i(fi),.fence_d(fd),
        .debug_redirect(trace_reschedule_o),.debug_trap(trace_reschedule_trap_o),
        .debug_branch_miss(trace_branch_miss_o),.debug_jump_miss(trace_jump_miss_o),
        .debug_dispatch_stall(trace_dispatch_stall_o),.debug_frontend_stall(trace_frontend_stall_o),
        .retire_valid(trace_retire_mask_o),.retire_pc0(retire_pc0),.retire_pc1(retire_pc1),
        .retire_instruction0(retire_instruction0),.retire_instruction1(retire_instruction1),
        .retire_destination0(retire_destination0),.retire_destination1(retire_destination1),
        .retire_value0(retire_value0),.retire_value1(retire_value1)
    );
    assign trace_retire_count_o={1'b0,trace_retire_mask_o[0]}+{1'b0,trace_retire_mask_o[1]};
    // Internal reorder-buffer numbering has no architectural meaning and is
    // deliberately not emulated. Reason bit zero identifies a genuine trap;
    // other implementation-specific reason bits are not assigned meanings.
    assign trace_retire_rob_id_o=6'b0;
    assign trace_reschedule_reason_o={7'b0,trace_reschedule_trap_o};

    rv32_memory_system #(.I_INDEX_BITS(I_INDEX_BITS),.D_INDEX_BITS(D_INDEX_BITS),.D_WAYS(D_WAYS),
        .ENABLE_FAST_ICROSS(ENABLE_FAST_ICROSS),
        .ENABLE_DATA_RAM_GUARD(ENABLE_DATA_RAM_GUARD),
        .DATA_RAM_BASE(DATA_RAM_BASE),.DATA_RAM_LIMIT(DATA_RAM_LIMIT)) memory (
        .clk(clk),.reset(reset),
        .imem_request_valid(cache_iv),.imem_request_ready(cache_ir),.imem_request_address(cache_ia),
        .imem_response_valid(cache_ipv),.imem_response_ready(cache_ipr),
        .imem_response_data(cache_ipd),.imem_response_error(cache_ipe),
        .dmem_request_valid(dv),.dmem_request_ready(dr),.dmem_request_address(da),
        .dmem_request_write(dw),.dmem_request_wdata(dwd),.dmem_request_wstrb(ds),
        .dmem_request_size(dz),.dmem_response_valid(raw_dpv),.dmem_response_ready(raw_dpr),
        .dmem_response_rdata(raw_dpd),.dmem_response_error(raw_dpe),
        .fence_i(fi),.fence_d(fd),.maintenance_busy(maintenance_busy),
        .event_icache_refill(event_i),.event_dcache_refill(event_d),.event_dcache_writeback(event_w),
        .instr_req_o(instr_req_o),.instr_gnt_i(instr_gnt_i),.instr_addr_o(instr_addr_o),
        .instr_io_o(instr_io_o),.instr_rvalid_i(instr_rvalid_i),.instr_rready_o(instr_rready_o),
        .instr_rdata_i(instr_rdata_i),.instr_err_i(instr_err_i),
        .data_rd_req_o(data_rd_req_o),.data_rd_gnt_i(data_rd_gnt_i),
        .data_rd_id_o(data_rd_id_o),.data_rd_addr_o(data_rd_addr_o),
        .data_rd_rvalid_i(data_rd_rvalid_i),.data_rd_rready_o(data_rd_rready_o),
        .data_rd_rid_i(data_rd_rid_i),.data_rd_rdata_i(data_rd_rdata_i),.data_rd_err_i(data_rd_err_i),
        .data_wr_req_o(data_wr_req_o),.data_wr_gnt_i(data_wr_gnt_i),
        .data_wr_last_o(data_wr_last_o),.data_wr_addr_o(data_wr_addr_o),
        .data_wr_data_o(data_wr_data_o),.data_wr_id_o(data_wr_id_o),
        .data_wr_bvalid_i(data_wr_bvalid_i),.data_wr_berr_i(data_wr_berr_i),.data_wr_bid_i(data_wr_bid_i),
        .periph_req_o(periph_req_o),.periph_gnt_i(periph_gnt_i),.periph_we_o(periph_we_o),
        .periph_addr_o(periph_addr_o),.periph_wdata_o(periph_wdata_o),
        .periph_be_o(periph_be_o),.periph_size_o(periph_size_o),
        .periph_rvalid_i(periph_rvalid_i),.periph_err_i(periph_err_i),.periph_rdata_i(periph_rdata_i)
    );
endmodule
