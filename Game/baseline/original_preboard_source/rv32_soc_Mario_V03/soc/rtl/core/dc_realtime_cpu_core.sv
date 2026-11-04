// Pure CPU: ordered I/D request-response ports; no address map or memory instances.
module dc_realtime_cpu_core #(
    parameter int unsigned BTB_INDEX_BITS = 9,
    // Register address generation ahead of the external memory interface.
    // Independent addresses are precomputed as the decode token arrives;
    // dependent addresses replay locally until a registered source is ready.
    parameter bit REGISTERED_AGU = 1'b1,
    // Selective late bypass ONLY into the branch comparator, never ALU/AGU.
    parameter bit LOAD_BRANCH_BYPASS = 1'b1,
    parameter logic [31:0] HART_ID            = 32'd0,
    parameter logic [31:0] RESET_PC           = 32'h0000_0000,
    parameter logic [31:0] FAST_VECTOR_BASE   = RESET_PC + 32'h0000_0100,
    parameter logic [31:0] FAST_VECTOR_STRIDE = 32'd4,
    parameter logic        BPU_ENABLE         = 1'b0,
    // Launch a legal memory operation on its issue edge. The registered
    // EX/MEM token retries the identical payload if the interface stalls.
    parameter bit          EARLY_LSU_ISSUE    = 1'b1,
    // Break DSP partial-product reconstruction -> ALU/AGU into two cycles.
    // RAW dependents use the registered WB result; independent ops continue.
    parameter bit          MDU_WB_ONLY        = 1'b1
) (
    input  logic        clk,
    input  logic        rst,

    output logic        if_req_valid,
    input  logic        if_req_ready,
    output logic [31:0] if_req_addr,
    input  logic        if_rsp_valid,
    output logic        if_rsp_ready,
    input  logic [31:0] if_rsp_rdata,
    input  logic        if_rsp_error,
    output logic        lsu_req_valid,
    input  logic        lsu_req_ready,
    output logic [31:0] lsu_req_addr,
    output logic        lsu_req_write,
    output logic [31:0] lsu_req_wdata,
    output logic [3:0]  lsu_req_wstrb,
    input  logic        lsu_rsp_valid,
    output logic        lsu_rsp_ready,
    input  logic [31:0] lsu_rsp_rdata,
    input  logic        lsu_rsp_error,

    input  logic        irq_nmi_fault,
    input  logic        irq_fast_adc,
    input  logic        irq_fast_pwm,
    input  logic        irq_qei,
    input  logic        irq_timer,
    input  logic        irq_ipc,
    input  logic [7:0]  irq_platform,

    output logic        core_sleeping,
    output logic        retire_valid_diag,
    output logic [31:0] retire_pc_diag,
    output logic        irq_accept_diag,
    output logic [31:0] irq_vector_pc_diag,
    output logic        handler_entry_diag,
    output logic        fatal_state_diag
`ifdef DC_RT_VERIFICATION
    ,
    output logic [31:0] trace_retire_instr,
    output logic [4:0]  trace_retire_rd,
    output logic        trace_retire_rd_write,
    output logic [31:0] trace_retire_value,
    output logic [31:0] trace_retire_next_pc
`endif
);
    timeunit 1ns;
    timeprecision 1ps;

    import dc_realtime_core_pkg::*;

    localparam logic [31:0] CAUSE_INSTRUCTION_ADDRESS_MISALIGNED = 32'd0;
    localparam logic [31:0] CAUSE_INSTRUCTION_ACCESS_FAULT       = 32'd1;
    localparam logic [31:0] CAUSE_ILLEGAL_INSTRUCTION            = 32'd2;
    localparam logic [31:0] CAUSE_BREAKPOINT                     = 32'd3;
    localparam logic [31:0] CAUSE_LOAD_ADDRESS_MISALIGNED        = 32'd4;
    localparam logic [31:0] CAUSE_LOAD_ACCESS_FAULT              = 32'd5;
    localparam logic [31:0] CAUSE_STORE_ADDRESS_MISALIGNED       = 32'd6;
    localparam logic [31:0] CAUSE_STORE_ACCESS_FAULT             = 32'd7;
    localparam logic [31:0] CAUSE_ECALL_MMODE                    = 32'd11;
    localparam logic [11:0] CSR_MTVEC = 12'h305;

    // Rev2: 84 synthesis bits (87 with trace source), not 146/149.
    // Only dynamic predictor snapshots travel through the fetch queue.
    typedef struct packed {
        logic [31:0] pc;
        logic [1:0] epoch;
        logic pred_taken;
        logic [31:0] pred_target;
`ifdef DC_RT_VERIFICATION
        logic [2:0] pred_source;
`endif
        logic loop_token_valid;
        logic [15:0] loop_token_iteration;
    } fetch_meta_t;

    logic        if_req_offered;
    logic        fetch_offer_accept;
    logic        fetch_offer_credit_available;
    logic        fetch_offer_refill_credit;
    logic        fetch_younger_pending;
    logic        fetch_result_valid;
    logic        fetch_result_ready;
    logic [31:0] fetch_result_rdata;
    logic        fetch_result_error;
    logic        fetch_result_live;
    fetch_meta_t fetch_response_meta;
    fetch_meta_t fetch_offer_meta;
    logic [$bits(fetch_meta_t)-1:0] fetch_offer_meta_bits;
    logic [$bits(fetch_meta_t)-1:0] fetch_response_meta_bits;
    logic [31:0] fetch_pc_q;
    logic        fetch_offer_valid_q;
    logic [31:0] fetch_offer_pc_q;
    logic [31:0] fetch_offer_pc_plus4;
    // Parallel carry predicates bound PC+4 propagation between low and high
    // address bits while preserving the full 32-bit increment for any PC.
    assign fetch_offer_pc_plus4[1:0] = fetch_offer_pc_q[1:0];
    assign fetch_offer_pc_plus4[9:2] = fetch_offer_pc_q[9:2] + 8'd1;
    assign fetch_offer_pc_plus4[17:10] = fetch_offer_pc_q[17:10] +
                                         {7'd0, (&fetch_offer_pc_q[9:2])};
    assign fetch_offer_pc_plus4[25:18] = fetch_offer_pc_q[25:18] +
                                         {7'd0, (&fetch_offer_pc_q[17:2])};
    assign fetch_offer_pc_plus4[31:26] = fetch_offer_pc_q[31:26] +
                                         {5'd0, (&fetch_offer_pc_q[25:2])};
    logic [1:0]  fetch_offer_epoch_q;
    logic [1:0]  fetch_epoch_q;

    logic        if_id_valid_q;
    logic [31:0] if_id_pc_q;
    logic [31:0] if_id_instruction_q;
    logic        if_id_fetch_fault_q;
    logic [1:0]  if_id_epoch_q;
    logic        if_id_pred_taken_q;
    logic [31:0] if_id_pred_target_q;
`ifdef DC_RT_VERIFICATION
    dc_rt_pred_source_e if_id_pred_source_q;
`endif
    logic [5:0]  if_id_btb_index_q;
    logic [23:0] if_id_btb_tag_q;
    logic        if_id_loop_token_valid_q;
    logic [4:0]  if_id_loop_token_index_q;
    logic [24:0] if_id_loop_token_tag_q;
    logic [15:0] if_id_loop_token_iteration_q;
    logic [1:0]  if_id_loop_token_epoch_q;

    logic        decode_legal;
    logic [4:0]  decode_rs1;
    logic [4:0]  decode_rs2;
    logic [4:0]  decode_rd;
    logic        decode_rd_write;
    dc_rt_alu_op_e decode_alu_op;
    logic        decode_m_valid;
    dc_rt_m_op_e decode_m_op;
    dc_rt_operand_a_e decode_operand_a_select;
    logic        decode_operand_b_immediate;
    logic [31:0] decode_immediate;
    dc_rt_control_e decode_control;
    dc_rt_branch_condition_e decode_branch_condition;
    logic [31:0] decode_control_immediate;
    dc_rt_memory_e decode_memory;
    dc_rt_memory_size_e decode_memory_size;
    logic        decode_load_unsigned;
    dc_rt_system_e decode_system;
    dc_rt_csr_op_e decode_csr_op;
    logic        decode_csr_immediate;
    logic [11:0] decode_csr_address;
    logic        decode_csr_source_zero;

    logic        fetch_decode_legal;
    logic [4:0]  fetch_decode_rs1;
    logic [4:0]  fetch_decode_rs2;
    logic [4:0]  fetch_decode_rd;
    logic        fetch_decode_rd_write;
    dc_rt_alu_op_e fetch_decode_alu_op;
    logic        fetch_decode_m_valid;
    dc_rt_m_op_e fetch_decode_m_op;
    dc_rt_operand_a_e fetch_decode_operand_a_select;
    logic        fetch_decode_operand_b_immediate;
    logic [31:0] fetch_decode_immediate;
    dc_rt_control_e fetch_decode_control;
    dc_rt_branch_condition_e fetch_decode_branch_condition;
    logic [31:0] fetch_decode_control_immediate;
    dc_rt_memory_e fetch_decode_memory;
    dc_rt_memory_size_e fetch_decode_memory_size;
    logic        fetch_decode_load_unsigned;
    dc_rt_system_e fetch_decode_system;
    dc_rt_csr_op_e fetch_decode_csr_op;
    logic        fetch_decode_csr_immediate;
    logic [11:0] fetch_decode_csr_address;
    logic        fetch_decode_csr_source_zero;

    logic [31:0] regfile_rs1_value;
    logic [31:0] regfile_rs2_value;
    logic [31:0] fetch_rs1_value;
    logic [31:0] fetch_rs2_value;
    logic [31:0] if_id_rs1_value_q;
    logic [31:0] if_id_rs2_value_q;
    logic [31:0] decode_rs1_value;
    logic [31:0] decode_rs2_value;
    logic [31:0] alu_operand_a;
    logic [31:0] alu_operand_b;
    logic [31:0] alu_result;
    logic [31:0] execute_result;
    logic [31:0] decode_memory_addr;
    logic [31:0] decode_address_q;
    logic decode_address_valid_q;
    logic fetch_address_source_ready;
    logic decode_address_source_ready;
    logic address_wait;
    logic [31:0] decode_address_comb;
    logic fetch_address_from_add;
    logic fetch_address_add_select;
    logic load_address_return_match;
    logic [31:0] fetch_address_add_base, fetch_address_add_result;
    logic [12:0] fetch_address_add_low;
    logic fetch_address_add_page_local;
    logic [12:0] fetch_address_generic_low;
    logic fetch_address_generic_page_local;
    logic [31:0] fetch_address_generic_result;
    logic load_address_nocarry_valid;
    logic [31:0] load_address_nocarry;

    logic        lsu_early_offer;
    logic        lsu_owner_offer;
    logic [1:0]  lsu_offer_epoch;
    dc_rt_memory_size_e lsu_offer_size;
    logic [31:0] lsu_offer_store_data;
    logic [1:0]  decode_effective_addr_low;
    logic        decode_memory_misaligned;
    logic        decode_exception_valid;
    logic [31:0] decode_exception_cause;
    dc_rt_tval_source_e decode_exception_tval_source;
    logic        decode_csr_probe_valid;
    logic        decode_csr_probe_read_only;
    logic [1:0]  decode_csr_probe_data_low;
    logic [1:0]  decode_csr_source_low;
    logic        decode_csr_write_intent;
    logic [1:0]  decode_csr_write_low;
    logic        decode_csr_semantic_illegal;

    logic        ex_mem_valid_q;
    logic [31:0] ex_mem_pc_q;
    logic [31:0] ex_mem_instruction_q;
    logic [4:0]  ex_mem_rd_q;
    logic        ex_mem_rd_write_q;
    logic        ex_mem_m_valid_q;
    logic        ex_mem_ordinary_result_ready_q;
    logic [31:0] ex_mem_result_q;
    logic [31:0] ex_mem_rs2_value_q;
    logic [31:0] ex_mem_control_immediate_q;
    dc_rt_control_e ex_mem_control_q;
    logic        ex_mem_branch_taken_q;
    logic        decode_branch_taken;
    logic [31:0] branch_rs1_value, branch_rs2_value;
    logic load_branch_bypass_valid;
    logic [31:0] decode_control_target;
    logic [31:0] ex_mem_control_target_q;
    dc_rt_memory_e ex_mem_memory_q;
    dc_rt_memory_size_e ex_mem_memory_size_q;
    logic        ex_mem_load_unsigned_q;
    logic [31:0] ex_mem_memory_addr_q;
    logic [1:0]  ex_mem_epoch_q;
    dc_rt_system_e ex_mem_system_q;
    dc_rt_csr_op_e ex_mem_csr_op_q;
    logic [11:0] ex_mem_csr_address_q;
    logic [31:0] ex_mem_csr_source_q;
    logic        ex_mem_csr_source_zero_q;
    logic [31:0] ex_mem_csr_read_data_q;
    logic        ex_mem_csr_read_valid_q;
    logic        ex_mem_csr_read_only_q;
    logic        ex_mem_exception_q;
    logic [31:0] ex_mem_exception_cause_q;
    dc_rt_tval_source_e ex_mem_tval_source_q;
    logic        ex_mem_fast_context_q;
    logic        ex_mem_pred_taken_q;
    logic [31:0] ex_mem_pred_target_q;
`ifdef DC_RT_VERIFICATION
    dc_rt_pred_source_e ex_mem_pred_source_q;
`endif
    logic [5:0]  ex_mem_btb_index_q;
    logic [23:0] ex_mem_btb_tag_q;
    logic        ex_mem_loop_token_valid_q;
    logic [4:0]  ex_mem_loop_token_index_q;
    logic [24:0] ex_mem_loop_token_tag_q;
    logic [15:0] ex_mem_loop_token_iteration_q;
    logic [1:0]  ex_mem_loop_token_epoch_q;

    logic        wb_valid_q;
    logic [31:0] wb_pc_q;
`ifdef DC_RT_VERIFICATION
    logic [31:0] wb_instruction_q;
`endif
    logic [4:0]  wb_rd_q;
    // Keep a local copy for the decode-to-EX forwarding comparators.  The
    // architectural WB destination also feeds the register file and fetch
    // bypass network; separating these loads shortens the WB-to-ALU path.
    (* syn_preserve = 1, syn_keep = 1 *) logic [4:0] wb_execute_rd_q;
    logic        wb_rd_write_q;
    logic [31:0] wb_result_q;
    logic        wb_csr_write_q;
    logic [11:0] wb_csr_address_q;
    logic [31:0] wb_csr_data_q;
    logic        wb_fast_context_q;
`ifdef DC_RT_VERIFICATION
    logic [31:0] wb_next_pc_q;
`endif

    logic        lsu_outstanding_q;
    logic        lsu_outstanding_write_q;
    logic [1:0]  lsu_outstanding_epoch_q;
    logic        lsu_response_match;
    logic        lsu_response_event;

    logic        csr_read_valid;
    logic        csr_read_only;
    logic [31:0] csr_read_data;
    logic [31:0] decode_csr_read_data;
    logic        csr_write_valid;
    logic [31:0] csr_write_effective_data;
    logic [31:0] csr_mtvec;
    logic [31:0] csr_mepc;
    logic [13:1] csr_mie;
    logic        csr_mstatus_mie;
    logic        csr_trap_valid;
    logic        csr_mret_valid;
    logic [31:0] csr_trap_pc;
    logic [31:0] csr_trap_cause;
    logic [31:0] csr_trap_tval;
    logic        ex_mem_csr_write_intent;
    logic [31:0] ex_mem_csr_write_data;
    logic        ex_mem_csr_illegal;
    logic        ex_mem_csr_illegal_q;

    logic [31:0] load_result;
    logic [3:0] load_low_lane_q, load_byte_sign_q;
    logic [1:0] load_mid_lane_q, load_half_sign_q;
    logic load_word_q, load_byte_q;
    logic [3:0] load_low_lane_d, load_byte_sign_d;
    logic [1:0] load_mid_lane_d, load_half_sign_d;
    logic load_word_d, load_byte_d;
    logic load_sign;
    logic branch_load_rs1, branch_load_rs2;
    logic branch_eq_normal, branch_eq_load, branch_load_any;
    logic branch_eq_word, branch_eq_byte;
    logic branch_other_upper24_zero, branch_other_upper24_ones;
    wire [3:0] branch_eq_byte_lane;
    logic [31:0] branch_compare_other;
    logic branch_eq_selected, branch_lt_unsigned, branch_lt_signed;
    logic        branch_taken;
    logic        control_redirect_candidate;
    logic [31:0] control_target;
    logic        control_target_misaligned;
    logic        mret_target_misaligned;
    logic        ex_mem_trap_valid;
    logic [31:0] ex_mem_trap_cause;
    logic [31:0] ex_mem_trap_tval;
    logic [31:0] ex_mem_reconstructed_tval;
    logic        ex_mem_success_complete;
    logic        ex_mem_can_accept;
    logic        ex_mem_result_available;
    logic [31:0] ex_mem_forward_value;
    logic [31:0] ex_mem_completion_value;
    logic        ex_mem_control_complete;
    logic        normal_redirect;
    logic        mret_redirect;
    logic        architectural_redirect;
    logic        pipeline_redirect;
    logic [31:0] pipeline_redirect_target;
    logic        ex_mem_csr_serializing;
    logic        ex_mem_payload_hold;
    logic        ex_mem_payload_capture;
    logic        decode_uses_rs1;
    logic        decode_uses_rs2;
    logic        load_use_response_interlock;
    logic        mdu_use_response_interlock;
    logic        id_issue_allowed;
    logic        mdu_req_valid;
    logic [31:0] mdu_req_rs1_value;
    logic [31:0] mdu_req_rs2_value;
    logic        mdu_ordinary_forward_available;
    logic [31:0] mdu_ordinary_forward_value;
    logic        mdu_req_ready;
    logic        mdu_rsp_valid;
    logic        mdu_rsp_ready;
    logic [31:0] mdu_rsp_result;
    logic [31:0] mdu_rsp_pc;
    logic [31:0] mdu_rsp_instruction;
    logic [4:0]  mdu_rsp_rd;
    logic [1:0]  mdu_rsp_epoch;
    logic        mdu_rsp_fast_context;
    logic        mdu_busy;
    logic        mdu_response_match;
    logic        mdu_incomplete;
    logic        mdu_cancel;
    logic [31:0] irq_mip;
    logic        irq_accept;
    logic [3:0]  irq_accepted_slot;
    logic [31:0] irq_accepted_vector;
    logic [31:0] irq_accepted_cause;
    logic        irq_fault_seen;
    logic        irq_accept_enable;
    logic [31:0] irq_resume_pc;
    logic        fast_context_q;
    logic        handler_active_q;
    logic        sleeping_q;
    logic [31:0] resume_pc_q;
    logic [31:0] irq_vector_pc_q;
    logic [31:0] handler_vector_q;
    logic        handler_entry_pending_q;
    logic        handler_entry_event;
    logic        wfi_sleep_enter;
    logic        actual_control_taken;
    logic [31:0] actual_next_pc;
    logic        control_mispredict;
    logic        bpu_update_valid;
    dc_rt_btb_type_e bpu_update_type;
    logic        bpu_query_valid;
    logic        bpu_query_accept;
    logic        bpu_pred_valid;
    logic        bpu_pred_taken;
    logic [31:0] bpu_pred_target;
    dc_rt_pred_source_e bpu_pred_source;
    logic [5:0]  bpu_pred_btb_index;
    logic [23:0] bpu_pred_btb_tag;
    logic [1:0]  bpu_pred_counter;
    logic        bpu_direct_jal_valid;
    logic [31:0] bpu_direct_jal_target;
    logic        bpu_pred_loop_token_valid;
    logic [4:0]  bpu_pred_loop_token_index;
    logic [24:0] bpu_pred_loop_token_tag;
    logic [15:0] bpu_pred_loop_token_iteration;
    logic [1:0]  bpu_pred_loop_token_epoch;
    logic        bpu_loop_override_valid;
    logic        bpu_loop_override_taken;
    logic        response_direct_jal_use;
    logic        direct_jal_offer_repair;

    always_comb begin
        fetch_offer_meta = '0;
        fetch_offer_meta.pc = fetch_offer_pc_q;
        fetch_offer_meta.epoch = fetch_offer_epoch_q;
        fetch_offer_meta.pred_taken = BPU_ENABLE &&
                                      bpu_pred_valid && bpu_pred_taken;
        fetch_offer_meta.pred_target = bpu_pred_target;
`ifdef DC_RT_VERIFICATION
        fetch_offer_meta.pred_source = BPU_ENABLE && bpu_pred_valid ?
                                       bpu_pred_source :
                                       DC_RT_PRED_SEQUENTIAL;
`endif
        fetch_offer_meta.loop_token_valid = BPU_ENABLE &&
                                            bpu_pred_loop_token_valid;
        fetch_offer_meta.loop_token_iteration =
            bpu_pred_loop_token_iteration;
    end
    assign fetch_offer_meta_bits = fetch_offer_meta;
    assign fetch_result_ready = !if_id_valid_q || id_issue_allowed ||
                                fetch_response_meta.epoch != fetch_epoch_q ||
                                pipeline_redirect;

    assign fetch_response_meta = fetch_response_meta_bits;

    dc_realtime_core_fetch_queue #(
        .META_WIDTH($bits(fetch_meta_t))
    ) fetch_queue (
        .clk, .rst, .invalidate(pipeline_redirect),
        .offer_valid(fetch_offer_valid_q),
        .offer_accept(fetch_offer_accept),
        .offer_offered(if_req_offered),
        .offer_credit_available(fetch_offer_credit_available),
        .offer_refill_credit(fetch_offer_refill_credit),
        .offer_addr(fetch_offer_pc_q),
        .offer_meta(fetch_offer_meta_bits),
        .memory_req_valid(if_req_valid),
        .memory_req_ready(if_req_ready),
        .memory_req_addr(if_req_addr),
        .memory_rsp_valid(if_rsp_valid),
        .memory_rsp_ready(if_rsp_ready),
        .memory_rsp_rdata(if_rsp_rdata),
        .memory_rsp_error(if_rsp_error),
        .response_valid(fetch_result_valid),
        .response_ready(fetch_result_ready),
        .response_rdata(fetch_result_rdata),
        .response_error(fetch_result_error),
        .response_meta(fetch_response_meta_bits),
        .response_live(fetch_result_live),
        .younger_pending(fetch_younger_pending)
    );



    assign bpu_query_valid = BPU_ENABLE && fetch_offer_valid_q &&
                             fetch_offer_epoch_q == fetch_epoch_q;
    assign bpu_query_accept = bpu_query_valid && fetch_offer_accept;

    dc_realtime_core_bpu #(.BTB_INDEX_BITS(BTB_INDEX_BITS)) bpu_unit (
        .clk,
        .rst,
        .query_valid(bpu_query_valid),
        .query_accept(bpu_query_accept),
        .query_pc(fetch_offer_pc_q),
        .query_epoch(fetch_offer_epoch_q),
        .current_epoch(fetch_epoch_q),
        .predictor_flush(pipeline_redirect),
        .update_valid(bpu_update_valid),
        .update_pc(ex_mem_pc_q),
        .update_taken(actual_control_taken),
        .update_target(control_target),
        .update_type(bpu_update_type),
        .update_rd(ex_mem_rd_q),
        .update_rs1(ex_mem_instruction_q[19:15]),
        .update_immediate(ex_mem_control_immediate_q),
        .update_loop_token_valid(ex_mem_loop_token_valid_q),
        .update_loop_token_index(ex_mem_loop_token_index_q),
        .update_loop_token_tag(ex_mem_loop_token_tag_q),
        .update_loop_token_iteration(ex_mem_loop_token_iteration_q),
        .update_loop_token_epoch(ex_mem_loop_token_epoch_q),
        .response_valid(fetch_result_valid && fetch_result_ready),
        .response_pc(fetch_response_meta.pc),
        .response_instruction(fetch_result_rdata),
        .pred_valid(bpu_pred_valid),
        .pred_taken(bpu_pred_taken),
        .pred_target(bpu_pred_target),
        .pred_source(bpu_pred_source),
        .pred_btb_index(bpu_pred_btb_index),
        .pred_btb_tag(bpu_pred_btb_tag),
        .pred_counter(bpu_pred_counter),
        .direct_jal_valid(bpu_direct_jal_valid),
        .direct_jal_target(bpu_direct_jal_target),
        .pred_loop_token_valid(bpu_pred_loop_token_valid),
        .pred_loop_token_index(bpu_pred_loop_token_index),
        .pred_loop_token_tag(bpu_pred_loop_token_tag),
        .pred_loop_token_iteration(bpu_pred_loop_token_iteration),
        .pred_loop_token_epoch(bpu_pred_loop_token_epoch),
        .loop_override_valid(bpu_loop_override_valid),
        .loop_override_taken(bpu_loop_override_taken)
    );

    dc_realtime_core_decode decode_unit (
        .instruction(fetch_result_rdata),
        .legal(fetch_decode_legal), .rs1(fetch_decode_rs1),
        .rs2(fetch_decode_rs2), .rd(fetch_decode_rd),
        .rd_write(fetch_decode_rd_write), .alu_op(fetch_decode_alu_op),
        .m_valid(fetch_decode_m_valid), .m_op(fetch_decode_m_op),
        .operand_a_select(fetch_decode_operand_a_select),
        .operand_b_immediate(fetch_decode_operand_b_immediate),
        .immediate(fetch_decode_immediate), .control(fetch_decode_control),
        .branch_condition(fetch_decode_branch_condition),
        .control_immediate(fetch_decode_control_immediate),
        .memory(fetch_decode_memory), .memory_size(fetch_decode_memory_size),
        .load_unsigned(fetch_decode_load_unsigned), .system(fetch_decode_system),
        .csr_op(fetch_decode_csr_op),
        .csr_immediate(fetch_decode_csr_immediate),
        .csr_address(fetch_decode_csr_address),
        .csr_source_zero(fetch_decode_csr_source_zero)
    );

    assign mdu_req_valid = id_issue_allowed && decode_m_valid && !decode_exception_valid;
    assign mdu_rsp_ready = 1'b1;
    // The MDU and EX/MEM accept one identical owner on the same edge.
    // While busy, payload holds; response or cancel releases both owners.
    // Full tuple integrity is checked below, not in the completion/forward CE cone.
    assign mdu_response_match = mdu_rsp_pc == ex_mem_pc_q &&
                                mdu_rsp_instruction == ex_mem_instruction_q &&
                                mdu_rsp_rd == ex_mem_rd_q &&
                                mdu_rsp_epoch == ex_mem_epoch_q &&
                                mdu_rsp_fast_context == ex_mem_fast_context_q;
    assign mdu_incomplete = ex_mem_valid_q && ex_mem_m_valid_q &&
                            !mdu_rsp_valid;
    assign mdu_cancel = irq_accept && mdu_incomplete;

    dc_realtime_core_mdu mdu_unit (
        .clk, .rst, .cancel(mdu_cancel), .req_valid(mdu_req_valid),
        .req_ready(mdu_req_ready), .req_op(decode_m_op),
        .req_rs1(mdu_req_rs1_value), .req_rs2(mdu_req_rs2_value),
        .req_pc(if_id_pc_q), .req_instruction(if_id_instruction_q),
        .req_rd(decode_rd), .req_epoch(if_id_epoch_q),
        .req_fast_context(fast_context_q), .rsp_valid(mdu_rsp_valid),
        .rsp_ready(mdu_rsp_ready), .rsp_result(mdu_rsp_result),
        .rsp_pc(mdu_rsp_pc), .rsp_instruction(mdu_rsp_instruction),
        .rsp_rd(mdu_rsp_rd), .rsp_epoch(mdu_rsp_epoch),
        .rsp_fast_context(mdu_rsp_fast_context), .busy(mdu_busy)
    );

    dc_realtime_core_regfile regfile_unit (
        .clk, .rst, .read_fast_context(fast_context_q),
        .read_rs1(fetch_decode_rs1), .read_rs2(fetch_decode_rs2),
        .read_rs1_value(regfile_rs1_value), .read_rs2_value(regfile_rs2_value),
        .write_valid(wb_valid_q && wb_rd_write_q),
        .write_fast_context(wb_fast_context_q), .write_rd(wb_rd_q),
        .write_value(wb_result_q)
    );

    dc_realtime_core_csr #(.HART_ID(HART_ID)) csr_unit (
        .clk, .rst, .read_address(decode_csr_address),
        .read_valid(csr_read_valid), .read_only(csr_read_only), .read_data(csr_read_data),
        .probe_address(decode_csr_address), .probe_valid(decode_csr_probe_valid),
        .probe_read_only(decode_csr_probe_read_only),
        .probe_data_low(decode_csr_probe_data_low),
        .write_valid(csr_write_valid), .write_address(wb_csr_address_q),
        .write_data(wb_csr_data_q), .write_effective_data(csr_write_effective_data),
        .trap_valid(csr_trap_valid),
        .trap_pc(csr_trap_pc), .trap_cause(csr_trap_cause),
        .trap_tval(csr_trap_tval), .mret_valid(csr_mret_valid),
        .mip(irq_mip), .mtvec(csr_mtvec), .mepc(csr_mepc),
        .mie(csr_mie), .mstatus_mie(csr_mstatus_mie)
    );

    assign csr_write_valid = wb_valid_q && wb_csr_write_q;
    assign decode_csr_read_data = (csr_write_valid &&
                                   wb_csr_address_q == decode_csr_address) ?
                                  csr_write_effective_data : csr_read_data;
    // A returning MDU owner cannot accept a new request in the same cycle.
    // A dependent M request therefore consumes that result from WB, not from
    // the live MDU response. Keep response identity comparisons off DSP data.
    assign mdu_ordinary_forward_available = !ex_mem_m_valid_q &&
                                            ex_mem_memory_q == DC_RT_MEMORY_NONE;
    assign mdu_ordinary_forward_value = ex_mem_result_q;
`ifdef DC_RT_VERIFICATION
    always_ff @(posedge clk) begin
        if (!rst && wb_valid_q && wb_execute_rd_q !== wb_rd_q)
            $fatal(1, "WB_EXECUTE_DESTINATION_MISMATCH");
    end
`endif
    always_comb begin
        mdu_req_rs1_value = if_id_rs1_value_q;
        mdu_req_rs2_value = if_id_rs2_value_q;
        if (ex_mem_valid_q && ex_mem_rd_write_q && mdu_ordinary_forward_available &&
            ex_mem_rd_q == decode_rs1)
            mdu_req_rs1_value = mdu_ordinary_forward_value;
        else if (wb_valid_q && wb_rd_write_q &&
                  wb_fast_context_q == fast_context_q && wb_rd_q == decode_rs1)
            mdu_req_rs1_value = wb_result_q;
        if (ex_mem_valid_q && ex_mem_rd_write_q && mdu_ordinary_forward_available &&
            ex_mem_rd_q == decode_rs2)
            mdu_req_rs2_value = mdu_ordinary_forward_value;
        else if (wb_valid_q && wb_rd_write_q &&
                  wb_fast_context_q == fast_context_q && wb_rd_q == decode_rs2)
            mdu_req_rs2_value = wb_result_q;
    end

    assign csr_trap_valid = ex_mem_trap_valid || irq_accept;
    assign csr_trap_pc = irq_accept ? irq_resume_pc : ex_mem_pc_q;
    assign csr_trap_cause = irq_accept ? irq_accepted_cause : ex_mem_trap_cause;
    assign csr_trap_tval = irq_accept ? 32'd0 : ex_mem_trap_tval;
    assign csr_mret_valid = mret_redirect;

    dc_realtime_core_fast_irq fast_irq_unit (
        .clk, .rst, .irq_nmi_fault, .irq_fast_adc, .irq_fast_pwm,
        .irq_qei, .irq_timer, .irq_ipc, .irq_platform,
        .mie(csr_mie), .mstatus_mie(csr_mstatus_mie),
        .handler_active(handler_active_q), .accept_enable(irq_accept_enable),
        .mip(irq_mip), .accept(irq_accept),
        .accepted_slot(irq_accepted_slot), .fault_seen(irq_fault_seen)
    );

    assign irq_accepted_vector = FAST_VECTOR_BASE +
                                 (irq_accepted_slot * FAST_VECTOR_STRIDE);
    assign irq_accepted_cause = 32'h8000_0010 + {28'd0, irq_accepted_slot};

    always_comb begin
        fetch_rs1_value = regfile_rs1_value;
        fetch_rs2_value = regfile_rs2_value;
        if (ex_mem_valid_q && ex_mem_rd_write_q &&
            ex_mem_result_available && ex_mem_fast_context_q == fast_context_q &&
            ex_mem_rd_q == fetch_decode_rs1)
            fetch_rs1_value = ex_mem_forward_value;
        else if (wb_valid_q && wb_rd_write_q &&
                 wb_fast_context_q == fast_context_q &&
                 wb_rd_q == fetch_decode_rs1)
            fetch_rs1_value = wb_result_q;
        if (ex_mem_valid_q && ex_mem_rd_write_q &&
            ex_mem_result_available && ex_mem_fast_context_q == fast_context_q &&
            ex_mem_rd_q == fetch_decode_rs2)
            fetch_rs2_value = ex_mem_forward_value;
        else if (wb_valid_q && wb_rd_write_q &&
                 wb_fast_context_q == fast_context_q &&
                 wb_rd_q == fetch_decode_rs2)
            fetch_rs2_value = wb_result_q;

        decode_rs1_value = if_id_rs1_value_q;
        decode_rs2_value = if_id_rs2_value_q;
        if (ex_mem_valid_q && ex_mem_rd_write_q &&
            ex_mem_result_available && ex_mem_fast_context_q == fast_context_q &&
            ex_mem_rd_q == decode_rs1)
            decode_rs1_value = ex_mem_forward_value;
        else if (wb_valid_q && wb_rd_write_q &&
                 wb_fast_context_q == fast_context_q && wb_execute_rd_q == decode_rs1)
            decode_rs1_value = wb_result_q;
        if (ex_mem_valid_q && ex_mem_rd_write_q &&
            ex_mem_result_available && ex_mem_fast_context_q == fast_context_q &&
            ex_mem_rd_q == decode_rs2)
            decode_rs2_value = ex_mem_forward_value;
        else if (wb_valid_q && wb_rd_write_q &&
                 wb_fast_context_q == fast_context_q && wb_execute_rd_q == decode_rs2)
            decode_rs2_value = wb_result_q;

        case (decode_operand_a_select)
            DC_RT_OPERAND_A_RS1:  alu_operand_a = decode_rs1_value;
            DC_RT_OPERAND_A_PC:   alu_operand_a = if_id_pc_q;
            DC_RT_OPERAND_A_ZERO: alu_operand_a = 32'd0;
            default:              alu_operand_a = 32'd0;
        endcase
        alu_operand_b = decode_operand_b_immediate ? decode_immediate :
                        decode_rs2_value;

        case (decode_alu_op)
            DC_RT_ALU_ADD:  alu_result = alu_operand_a + alu_operand_b;
            DC_RT_ALU_SUB:  alu_result = alu_operand_a - alu_operand_b;
            DC_RT_ALU_SLL:  alu_result = alu_operand_a << alu_operand_b[4:0];
            DC_RT_ALU_SLT:  alu_result = $signed(alu_operand_a) < $signed(alu_operand_b) ? 32'd1 : 32'd0;
            DC_RT_ALU_SLTU: alu_result = alu_operand_a < alu_operand_b ? 32'd1 : 32'd0;
            DC_RT_ALU_XOR:  alu_result = alu_operand_a ^ alu_operand_b;
            DC_RT_ALU_SRL:  alu_result = alu_operand_a >> alu_operand_b[4:0];
            DC_RT_ALU_SRA:  alu_result = $signed(alu_operand_a) >>> alu_operand_b[4:0];
            DC_RT_ALU_OR:   alu_result = alu_operand_a | alu_operand_b;
            DC_RT_ALU_AND:  alu_result = alu_operand_a & alu_operand_b;
            default:        alu_result = 32'd0;
        endcase
        execute_result = (decode_control == DC_RT_CONTROL_JAL ||
                          decode_control == DC_RT_CONTROL_JALR) ?
                         if_id_pc_q + 32'd4 : alu_result;
    end

    always_comb begin
        decode_csr_source_low = decode_csr_immediate ? decode_rs1[1:0] :
                                                       decode_rs1_value[1:0];
        decode_csr_write_intent = decode_csr_op == DC_RT_CSR_RW ||
                                  !decode_csr_source_zero;
        case (decode_csr_op)
            DC_RT_CSR_RW: decode_csr_write_low = decode_csr_source_low;
            DC_RT_CSR_RS: decode_csr_write_low = decode_csr_probe_data_low |
                                                 decode_csr_source_low;
            DC_RT_CSR_RC: decode_csr_write_low = decode_csr_probe_data_low &
                                                 ~decode_csr_source_low;
            default:      decode_csr_write_low = 2'b00;
        endcase
        decode_csr_semantic_illegal = decode_system == DC_RT_SYSTEM_CSR &&
                                      (!decode_csr_probe_valid ||
                                       (decode_csr_write_intent && decode_csr_probe_read_only) ||
                                       (decode_csr_write_intent && decode_csr_address == CSR_MTVEC &&
                                        decode_csr_write_low != 2'b00));
    end

    // V3: four parallel byte adders, then carry-select by predecoded
    // within-byte propagate prefixes. The inter-byte carry no longer enters
    // a second eight-bit incrementer on its way to the high result bits.
    function automatic logic [31:0] fast_add32(input logic [31:0] a, b);
        logic [8:0] sums [0:3];
        logic [3:0] prop;
        logic [4:0] carry;
        logic [7:0] increment_mask;
        begin
            carry[0] = 1'b0;
            for (int i=0; i<4; i++) begin
                sums[i] = {1'b0,a[i*8+:8]} + {1'b0,b[i*8+:8]};
                prop[i] = &(a[i*8+:8] ^ b[i*8+:8]);
                carry[i+1] = sums[i][8] | (prop[i] & carry[i]);
                increment_mask[0] = 1'b1;
                for (int j=1; j<8; j++)
                    increment_mask[j] = increment_mask[j-1] & sums[i][j-1];
                fast_add32[i*8+:8] = sums[i][7:0] ^
                    (increment_mask & {8{carry[i]}});
            end
        end
    endfunction
    // Select the other operand before the DTCM response. Compare each
    // returned lane directly, so byte loads never pass through the
    // 32-bit load-result selection and sign-extension network.
    (* syn_keep = 1 *) wire [7:0] branch_eq_word_chunk;
    for (genvar c=0; c<8; c++) begin : g_branch_eq_word_chunks
        assign branch_eq_word_chunk[c] =
            ~|(lsu_rsp_rdata[c*4+:4] ^ branch_compare_other[c*4+:4]);
    end
    assign branch_eq_word = &branch_eq_word_chunk;
    assign branch_other_upper24_zero = branch_compare_other[31:8] == 24'd0;
    assign branch_other_upper24_ones = &branch_compare_other[31:8];
    for (genvar lane=0; lane<4; lane++) begin : g_branch_eq_byte
        wire negative = load_byte_sign_q[lane] && lsu_rsp_rdata[lane*8+7];
        assign branch_eq_byte_lane[lane] = load_low_lane_q[lane] &&
            (lsu_rsp_rdata[lane*8+:8] == branch_compare_other[7:0]) &&
            (negative ? branch_other_upper24_ones : branch_other_upper24_zero);
    end
    assign branch_eq_byte = |branch_eq_byte_lane;

    // Dedicated AGU: memory addresses do not traverse the full ALU result mux.
    assign decode_address_comb = fast_add32(decode_rs1_value, decode_immediate);
    assign decode_memory_addr = REGISTERED_AGU ? decode_address_q : decode_address_comb;
    // The incoming token must not use an RF snapshot superseded by the
    // instruction currently executing, or by an unavailable older result.
    assign fetch_address_source_ready = fetch_address_from_add || (
        !(if_id_valid_q && decode_rd_write && decode_rd != 5'd0 &&
          decode_rd == fetch_decode_rs1) &&
        !(ex_mem_valid_q && ex_mem_rd_write_q && ex_mem_rd_q != 5'd0 &&
          ex_mem_fast_context_q == fast_context_q &&
          ex_mem_rd_q == fetch_decode_rs1 && !ex_mem_result_available));
    // Fuse only the *address calculation* of a preceding ordinary ADD/ADDI
    // into a carry-save three-operand adder. Both instructions still retire.
    // This avoids ADD -> ADD ripple chains and avoids a replay for common
    // base-register increments. No instruction-address-specific rules exist.
    assign fetch_address_add_select = if_id_valid_q &&
        decode_rd_write && decode_rd != 5'd0 && decode_rd == fetch_decode_rs1 &&
        !decode_m_valid &&
        decode_memory == DC_RT_MEMORY_NONE && decode_system == DC_RT_SYSTEM_NONE &&
        decode_control == DC_RT_CONTROL_NONE && decode_alu_op == DC_RT_ALU_ADD;
    // Slow issue/exception qualification gates a validity bit, not the
    // 32-bit CSA/normal-address mux. Its unqualified value is ignored when
    // the corresponding address-valid bit is clear.
    assign fetch_address_from_add = fetch_address_add_select &&
                                    id_issue_allowed && !decode_exception_valid;
    // The prior ADD/ADDI result is available independently of the new
    // fetched instruction. Only add its 12-bit memory offset on the late
    // ITCM response path. If this crosses a 4 KiB page, replay the address
    // through the ordinary registered AGU on the following cycle.
    assign fetch_address_add_base = alu_operand_a + alu_operand_b;
    assign fetch_address_add_low = {1'b0, fetch_address_add_base[11:0]} +
                                   {1'b0, fetch_decode_immediate[11:0]};
    assign fetch_address_add_page_local =
        fetch_address_add_low[12] == fetch_decode_immediate[11];
    assign fetch_address_add_result =
        {fetch_address_add_base[31:12], fetch_address_add_low[11:0]};
    // RV32 load/store offsets are signed 12-bit. Most do not cross a 4 KiB
    // page, so the upper address bits can bypass the late fetch-stage adder.
    // A crossing address replays through the registered 32-bit AGU.
    assign fetch_address_generic_low = {1'b0, fetch_rs1_value[11:0]} +
                                       {1'b0, fetch_decode_immediate[11:0]};
    assign fetch_address_generic_page_local =
        fetch_address_generic_low[12] == fetch_decode_immediate[11];
    assign fetch_address_generic_result =
        {fetch_rs1_value[31:12], fetch_address_generic_low[11:0]};

    // For disjoint bitfields addition equals OR (including offset=0).
    // A dependent pointer load can fill the address register on the return
    // edge with NO carry-propagate adder on the raw memory path. All other
    // addresses take the conservative WB -> AGU -> address-register replay.
    // Only a word load can set the candidate valid, so its unformatted
    // DTCM response is the address source. Other load sizes replay normally.
    assign load_address_nocarry = lsu_rsp_rdata | decode_immediate;
    assign load_address_return_match = ex_mem_valid_q &&
        ex_mem_memory_q == DC_RT_MEMORY_LOAD && ex_mem_rd_write_q && ex_mem_rd_q != 5'd0 &&
        ex_mem_fast_context_q == fast_context_q && ex_mem_rd_q == decode_rs1 &&
        lsu_response_event && !lsu_rsp_error;
    // Word-load low bits come directly from DTCM. Other load sizes replay
    // through the ordinary registered AGU, preserving their address value.
    assign load_address_nocarry_valid = load_address_return_match &&
        load_word_q && !decode_immediate[31] &&
        ((lsu_rsp_rdata[11:0] & decode_immediate[11:0]) == 12'd0);

    assign decode_address_source_ready =
        !(ex_mem_valid_q && ex_mem_rd_write_q && ex_mem_rd_q != 5'd0 &&
          ex_mem_fast_context_q == fast_context_q &&
          ex_mem_rd_q == decode_rs1 && !ex_mem_result_available);
    assign address_wait = REGISTERED_AGU && decode_memory != DC_RT_MEMORY_NONE &&
                          !decode_address_valid_q;
    always_ff @(posedge clk) begin
        if (rst) begin
            decode_address_q <= 32'd0;
            decode_address_valid_q <= 1'b0;
        end else begin
            if (if_id_valid_q && decode_memory != DC_RT_MEMORY_NONE &&
                !decode_address_valid_q) begin
                if (load_address_return_match) begin
                    // Speculatively write the OR candidate into an INVALID
                    // address slot. Only positive, carry-free offsets qualify.
                    // No speculative memory request or store is generated.
                    decode_address_q <= load_address_nocarry;
                    decode_address_valid_q <= load_address_nocarry_valid;
                end else if (decode_address_source_ready) begin
                    decode_address_q <= decode_address_comb;
                    decode_address_valid_q <= 1'b1;
                end
            end
            if (id_issue_allowed) decode_address_valid_q <= 1'b0;
            // Both incoming paths compute twelve low address bits.
            // The validity bit rejects page crossings and source hazards;
            // invalid candidates replay through the registered AGU.
            if (!if_id_valid_q || id_issue_allowed)
                decode_address_q <= fetch_address_add_select ? fetch_address_add_result :
                                    fetch_address_generic_result;
            if (fetch_result_valid && fetch_result_ready && !pipeline_redirect &&
                fetch_result_live && fetch_response_meta.epoch == fetch_epoch_q &&
                fetch_decode_memory != DC_RT_MEMORY_NONE)
                decode_address_valid_q <= fetch_address_source_ready &&
                    (fetch_address_add_select ? fetch_address_add_page_local :
                     fetch_address_generic_page_local);
            if (pipeline_redirect) decode_address_valid_q <= 1'b0;
        end
    end
    assign decode_effective_addr_low = decode_memory_addr[1:0];

    always_comb begin
        decode_memory_misaligned = 1'b0;
        case (decode_memory_size)
            DC_RT_MEMORY_HALF: decode_memory_misaligned = decode_effective_addr_low[0];
            DC_RT_MEMORY_WORD: decode_memory_misaligned = |decode_effective_addr_low;
            default: begin end
        endcase
        decode_memory_misaligned = decode_memory != DC_RT_MEMORY_NONE &&
                                   decode_memory_misaligned;

    end

    always_comb begin
        decode_exception_valid = if_id_fetch_fault_q;
        decode_exception_cause = CAUSE_INSTRUCTION_ACCESS_FAULT;
        decode_exception_tval_source = DC_RT_TVAL_PC;
        if (!if_id_fetch_fault_q) begin
            if (!decode_legal) begin
                decode_exception_valid = 1'b1;
                decode_exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
                decode_exception_tval_source = DC_RT_TVAL_INSTRUCTION;
            end else if (decode_system == DC_RT_SYSTEM_ECALL) begin
                decode_exception_valid = 1'b1;
                decode_exception_cause = CAUSE_ECALL_MMODE;
                decode_exception_tval_source = DC_RT_TVAL_ZERO;
            end else if (decode_system == DC_RT_SYSTEM_EBREAK) begin
                decode_exception_valid = 1'b1;
                decode_exception_cause = CAUSE_BREAKPOINT;
                decode_exception_tval_source = DC_RT_TVAL_PC;
            end else if (decode_memory_misaligned) begin
                decode_exception_valid = 1'b1;
                decode_exception_cause = decode_memory == DC_RT_MEMORY_LOAD ?
                                         CAUSE_LOAD_ADDRESS_MISALIGNED :
                                         CAUSE_STORE_ADDRESS_MISALIGNED;
                decode_exception_tval_source = DC_RT_TVAL_ADDRESS;
            end else begin
                decode_exception_valid = 1'b0;
                decode_exception_cause = 32'd0;
                decode_exception_tval_source = DC_RT_TVAL_ZERO;
            end
        end
    end

    // V14: move load lane/sign decode to the existing owner-capture edge.
    // The return path is AND/OR selection with registered controls, rather
    // than byte selection -> sign extension -> size selection in series.
    always_comb begin
        load_low_lane_d = 4'd0;
        load_mid_lane_d = 2'd0;
        load_byte_sign_d = 4'd0;
        load_half_sign_d = 2'd0;
        load_word_d = 1'b0;
        load_byte_d = 1'b0;
        case (decode_memory_size)
            DC_RT_MEMORY_BYTE: begin
                load_low_lane_d = 4'b0001 << decode_memory_addr[1:0];
                load_byte_d = 1'b1;
                if (!decode_load_unsigned) load_byte_sign_d = load_low_lane_d;
            end
            DC_RT_MEMORY_HALF: begin
                load_low_lane_d = decode_memory_addr[1] ? 4'b0100 : 4'b0001;
                load_mid_lane_d = decode_memory_addr[1] ? 2'b10 : 2'b01;
                if (!decode_load_unsigned) load_half_sign_d = load_mid_lane_d;
            end
            DC_RT_MEMORY_WORD: begin
                load_low_lane_d = 4'b0001;
                load_mid_lane_d = 2'b01;
                load_word_d = 1'b1;
            end
            default: begin end
        endcase
    end
    always_ff @(posedge clk) begin
        if (rst) begin
            load_low_lane_q <= '0; load_mid_lane_q <= '0;
            load_byte_sign_q <= '0; load_half_sign_q <= '0;
            load_word_q <= 1'b0; load_byte_q <= 1'b0;
        end else if (ex_mem_payload_capture) begin
            load_low_lane_q <= load_low_lane_d;
            load_mid_lane_q <= load_mid_lane_d;
            load_byte_sign_q <= load_byte_sign_d;
            load_half_sign_q <= load_half_sign_d;
            load_word_q <= load_word_d;
            load_byte_q <= load_byte_d;
        end
    end
    assign load_sign = |({lsu_rsp_rdata[31], lsu_rsp_rdata[23],
                          lsu_rsp_rdata[15], lsu_rsp_rdata[7]} & load_byte_sign_q) ||
                       |({lsu_rsp_rdata[31], lsu_rsp_rdata[15]} & load_half_sign_q);
    assign load_result[7:0] =
        (lsu_rsp_rdata[7:0]   & {8{load_low_lane_q[0]}}) |
        (lsu_rsp_rdata[15:8]  & {8{load_low_lane_q[1]}}) |
        (lsu_rsp_rdata[23:16] & {8{load_low_lane_q[2]}}) |
        (lsu_rsp_rdata[31:24] & {8{load_low_lane_q[3]}});
    assign load_result[15:8] =
        (lsu_rsp_rdata[15:8]  & {8{load_mid_lane_q[0]}}) |
        (lsu_rsp_rdata[31:24] & {8{load_mid_lane_q[1]}}) |
        {8{load_sign && load_byte_q}};
    assign load_result[31:16] =
        (lsu_rsp_rdata[31:16] & {16{load_word_q}}) | {16{load_sign}};

    // An exception payload always stores MEMORY_NONE in EX/MEM, so the
    // memory-kind test also excludes exceptions from this LSU offer.
    assign lsu_owner_offer = ex_mem_valid_q && ex_mem_memory_q != DC_RT_MEMORY_NONE &&
                             !lsu_outstanding_q;
    assign lsu_early_offer = EARLY_LSU_ISSUE && id_issue_allowed &&
                             decode_memory != DC_RT_MEMORY_NONE && !decode_exception_valid;
    assign lsu_req_valid = !rst && (lsu_owner_offer || lsu_early_offer);
    assign lsu_req_addr = lsu_owner_offer ? ex_mem_memory_addr_q : decode_memory_addr;
    assign lsu_req_write = lsu_owner_offer ? ex_mem_memory_q == DC_RT_MEMORY_STORE :
                                            decode_memory == DC_RT_MEMORY_STORE;
    assign lsu_offer_size = lsu_owner_offer ? ex_mem_memory_size_q : decode_memory_size;
    assign lsu_offer_store_data = lsu_owner_offer ? ex_mem_rs2_value_q : decode_rs2_value;
    assign lsu_offer_epoch = lsu_owner_offer ? ex_mem_epoch_q : if_id_epoch_q;
    always_comb begin
        lsu_req_wdata = 32'd0;
        lsu_req_wstrb = 4'd0;
        if (lsu_req_write) begin
            case (lsu_offer_size)
                DC_RT_MEMORY_BYTE: begin
                    case (lsu_req_addr[1:0])
                        2'd0: begin lsu_req_wdata = {24'd0, lsu_offer_store_data[7:0]};       lsu_req_wstrb = 4'b0001; end
                        2'd1: begin lsu_req_wdata = {16'd0, lsu_offer_store_data[7:0], 8'd0}; lsu_req_wstrb = 4'b0010; end
                        2'd2: begin lsu_req_wdata = {8'd0, lsu_offer_store_data[7:0], 16'd0}; lsu_req_wstrb = 4'b0100; end
                        2'd3: begin lsu_req_wdata = {lsu_offer_store_data[7:0], 24'd0};       lsu_req_wstrb = 4'b1000; end
                        default: begin end
                    endcase
                end
                DC_RT_MEMORY_HALF: begin
                    if (lsu_req_addr[1]) begin
                        lsu_req_wdata = {lsu_offer_store_data[15:0], 16'd0};
                        lsu_req_wstrb = 4'b1100;
                    end else begin
                        lsu_req_wdata = {16'd0, lsu_offer_store_data[15:0]};
                        lsu_req_wstrb = 4'b0011;
                    end
                end
                DC_RT_MEMORY_WORD: begin
                    lsu_req_wdata = lsu_offer_store_data;
                    lsu_req_wstrb = 4'b1111;
                end
                default: begin end
            endcase
        end
    end
    assign lsu_rsp_ready = lsu_outstanding_q;
    assign lsu_response_match = lsu_outstanding_q &&
                                lsu_outstanding_epoch_q == ex_mem_epoch_q;
    assign lsu_response_event = lsu_rsp_valid && lsu_rsp_ready && lsu_response_match;

    always_comb begin
        ex_mem_csr_write_intent = ex_mem_csr_op_q == DC_RT_CSR_RW ||
                                  !ex_mem_csr_source_zero_q;
        case (ex_mem_csr_op_q)
            DC_RT_CSR_RW: ex_mem_csr_write_data = ex_mem_csr_source_q;
            DC_RT_CSR_RS: ex_mem_csr_write_data = ex_mem_csr_read_data_q | ex_mem_csr_source_q;
            DC_RT_CSR_RC: ex_mem_csr_write_data = ex_mem_csr_read_data_q & ~ex_mem_csr_source_q;
            default:      ex_mem_csr_write_data = 32'd0;
        endcase

    end

    assign ex_mem_csr_illegal = ex_mem_csr_illegal_q;

    always_comb begin
        case (ex_mem_tval_source_q)
            DC_RT_TVAL_PC:          ex_mem_reconstructed_tval = ex_mem_pc_q;
            DC_RT_TVAL_INSTRUCTION: ex_mem_reconstructed_tval = ex_mem_instruction_q;
            DC_RT_TVAL_ADDRESS:     ex_mem_reconstructed_tval = ex_mem_memory_addr_q;
            default:                ex_mem_reconstructed_tval = 32'd0;
        endcase
    end

    // Valid return data may feed a branch comparison in parallel with WB.
    // The branch target uses PC+immediate and its taken bit is registered in
    // EX/MEM. Other consumers retain the V12 return-cycle interlock.
    assign load_branch_bypass_valid = LOAD_BRANCH_BYPASS &&
        decode_control == DC_RT_CONTROL_BRANCH &&
        (decode_branch_condition == DC_RT_BRANCH_EQ || decode_branch_condition == DC_RT_BRANCH_NE) &&
        ex_mem_valid_q &&
        ex_mem_memory_q == DC_RT_MEMORY_LOAD && (load_word_q || load_byte_q) &&
        lsu_response_event && !lsu_rsp_error && ex_mem_rd_write_q && ex_mem_rd_q != 5'd0 &&
        ex_mem_fast_context_q == fast_context_q;
    // V14: compute equality candidates in parallel, then select ONE bit.
    // The load-return availability/RAW control no longer selects two 32-bit
    // buses before the equality comparator. Ordering comparisons have NO
    // load data in their fan-in; only EQ/NE use this late bypass, as in V13.
    assign branch_load_rs1 = load_branch_bypass_valid && ex_mem_rd_q == decode_rs1;
    assign branch_load_rs2 = load_branch_bypass_valid && ex_mem_rd_q == decode_rs2;
    assign branch_eq_normal = decode_rs1_value == decode_rs2_value;
    assign branch_load_any = branch_load_rs1 || branch_load_rs2;
    assign branch_compare_other = branch_load_rs1 ? decode_rs2_value : decode_rs1_value;
    assign branch_eq_load = load_word_q ? branch_eq_word : branch_eq_byte;
    assign branch_eq_selected = (branch_load_rs1 && branch_load_rs2) ||
                                (branch_load_any ? branch_eq_load : branch_eq_normal);
    assign branch_lt_unsigned = decode_rs1_value < decode_rs2_value;
    assign branch_lt_signed = (decode_rs1_value[31] != decode_rs2_value[31]) ?
                              decode_rs1_value[31] : branch_lt_unsigned;
    // Retain diagnostic names, disconnected from the ordinary comparator.
    assign branch_rs1_value = branch_load_rs1 ? load_result : decode_rs1_value;
    assign branch_rs2_value = branch_load_rs2 ? load_result : decode_rs2_value;

    always_comb begin
        case (decode_branch_condition)
            DC_RT_BRANCH_EQ:  decode_branch_taken = branch_eq_selected;
            DC_RT_BRANCH_NE:  decode_branch_taken = !branch_eq_selected;
            DC_RT_BRANCH_LT:  decode_branch_taken = branch_lt_signed;
            DC_RT_BRANCH_GE:  decode_branch_taken = !branch_lt_signed;
            DC_RT_BRANCH_LTU: decode_branch_taken = branch_lt_unsigned;
            DC_RT_BRANCH_GEU: decode_branch_taken = !branch_lt_unsigned;
            default:          decode_branch_taken = 1'b0;
        endcase
        branch_taken = ex_mem_branch_taken_q;

        // Precompute from the same final operands captured with this token.
        // Keep the carry chain out of mispredict/IRQ/MDU issue arbitration.
        decode_control_target = if_id_pc_q + decode_control_immediate;
        if (decode_control == DC_RT_CONTROL_JALR)
            decode_control_target = (decode_rs1_value + decode_control_immediate) & 32'hffff_fffe;

        actual_control_taken = 1'b0;
        control_target = ex_mem_control_target_q;
        case (ex_mem_control_q)
            DC_RT_CONTROL_BRANCH: actual_control_taken = branch_taken;
            DC_RT_CONTROL_JAL:    actual_control_taken = 1'b1;
            DC_RT_CONTROL_JALR: begin
                actual_control_taken = 1'b1;
            end
            default: begin end
        endcase
        control_redirect_candidate = ex_mem_valid_q && actual_control_taken;
        actual_next_pc = actual_control_taken ? control_target : ex_mem_pc_q + 32'd4;
        control_target_misaligned = control_redirect_candidate && |control_target[1:0];
        mret_target_misaligned = ex_mem_valid_q && ex_mem_system_q == DC_RT_SYSTEM_MRET &&
                                 |csr_mepc[1:0];

        ex_mem_trap_valid = 1'b0;
        ex_mem_trap_cause = 32'd0;
        ex_mem_trap_tval = 32'd0;
        if (ex_mem_valid_q && ex_mem_exception_q) begin
            ex_mem_trap_valid = 1'b1;
            ex_mem_trap_cause = ex_mem_exception_cause_q;
            ex_mem_trap_tval = ex_mem_reconstructed_tval;
        end else if (ex_mem_valid_q && ex_mem_csr_illegal) begin
            ex_mem_trap_valid = 1'b1;
            ex_mem_trap_cause = CAUSE_ILLEGAL_INSTRUCTION;
            ex_mem_trap_tval = ex_mem_instruction_q;
        end else if (control_target_misaligned) begin
            ex_mem_trap_valid = 1'b1;
            ex_mem_trap_cause = CAUSE_INSTRUCTION_ADDRESS_MISALIGNED;
            ex_mem_trap_tval = control_target;
        end else if (mret_target_misaligned) begin
            ex_mem_trap_valid = 1'b1;
            ex_mem_trap_cause = CAUSE_INSTRUCTION_ADDRESS_MISALIGNED;
            ex_mem_trap_tval = csr_mepc;
        end else if (lsu_response_event && lsu_rsp_error) begin
            ex_mem_trap_valid = 1'b1;
            ex_mem_trap_cause = lsu_outstanding_write_q ?
                                CAUSE_STORE_ACCESS_FAULT : CAUSE_LOAD_ACCESS_FAULT;
            ex_mem_trap_tval = ex_mem_memory_addr_q;
        end
    end

    assign ex_mem_success_complete = ex_mem_valid_q && !ex_mem_trap_valid &&
                                     ((!ex_mem_m_valid_q &&
                                       ex_mem_memory_q == DC_RT_MEMORY_NONE) ||
                                      (ex_mem_m_valid_q && mdu_rsp_valid) ||
                                      (lsu_response_event && !lsu_rsp_error));
    assign ex_mem_control_complete = ex_mem_valid_q &&
                                     ex_mem_control_q != DC_RT_CONTROL_NONE &&
                                     !control_target_misaligned;
    assign ex_mem_can_accept = !ex_mem_valid_q || ex_mem_success_complete || ex_mem_trap_valid;
    // EX bypass eligibility travels with the payload. This removes the
    // system/memory decode from the next cycle's 32-bit ALU feedback.
    assign ex_mem_result_available = (!MDU_WB_ONLY && ex_mem_m_valid_q && mdu_rsp_valid) ||
                                     ex_mem_ordinary_result_ready_q;
    // CSR is serializing and uses WB forwarding, never the EX fast bypass.
    assign ex_mem_forward_value = (!MDU_WB_ONLY && ex_mem_m_valid_q) ? mdu_rsp_result :
                                  ex_mem_result_q;
    assign ex_mem_completion_value = ex_mem_system_q == DC_RT_SYSTEM_CSR ? ex_mem_csr_read_data_q :
                                     ex_mem_m_valid_q ? mdu_rsp_result :
                                     ex_mem_memory_q == DC_RT_MEMORY_LOAD ? load_result :
                                     ex_mem_result_q;
    assign control_mispredict = ex_mem_control_complete &&
                                ((ex_mem_pred_taken_q != actual_control_taken) ||
                                 (actual_control_taken &&
                                  ex_mem_pred_target_q != control_target));
    assign normal_redirect = control_mispredict;
    assign mret_redirect = ex_mem_success_complete && ex_mem_system_q == DC_RT_SYSTEM_MRET;
    assign architectural_redirect = ex_mem_trap_valid || mret_redirect || normal_redirect;
    assign irq_resume_pc = mdu_incomplete ? ex_mem_pc_q :
                           ex_mem_success_complete ? actual_next_pc : resume_pc_q;
    assign irq_accept_enable = (!ex_mem_valid_q || ex_mem_success_complete ||
                                mdu_incomplete) &&
                                !architectural_redirect && !csr_write_valid &&
                                !(ex_mem_valid_q && ex_mem_system_q == DC_RT_SYSTEM_CSR);
    assign wfi_sleep_enter = ex_mem_success_complete &&
                             ex_mem_system_q == DC_RT_SYSTEM_WFI &&
                             !irq_accept && !handler_active_q;
    assign pipeline_redirect = architectural_redirect || irq_accept || wfi_sleep_enter;
    assign pipeline_redirect_target = ex_mem_trap_valid ? csr_mtvec :
                                      mret_redirect ? csr_mepc :
                                      normal_redirect ? actual_next_pc :
                                      irq_accept ? irq_accepted_vector :
                                      ex_mem_pc_q + 32'd4;
    assign ex_mem_csr_serializing = ex_mem_valid_q &&
                                    (ex_mem_system_q == DC_RT_SYSTEM_CSR ||
                                     ex_mem_system_q == DC_RT_SYSTEM_WFI);
    assign ex_mem_payload_hold = ex_mem_valid_q &&
                                 ((ex_mem_memory_q != DC_RT_MEMORY_NONE &&
                                   !lsu_response_event) ||
                                  (ex_mem_m_valid_q && !mdu_rsp_valid));
    assign ex_mem_payload_capture = id_issue_allowed;
    assign decode_uses_rs1 = decode_legal &&
                             decode_operand_a_select == DC_RT_OPERAND_A_RS1 &&
                             decode_control != DC_RT_CONTROL_JAL &&
                             (decode_system == DC_RT_SYSTEM_NONE ||
                              (decode_system == DC_RT_SYSTEM_CSR &&
                               !decode_csr_immediate));
    assign decode_uses_rs2 = decode_legal &&
                             ((decode_memory == DC_RT_MEMORY_STORE) ||
                              (!decode_operand_b_immediate &&
                               decode_control != DC_RT_CONTROL_JAL &&
                               decode_control != DC_RT_CONTROL_JALR &&
                               decode_system == DC_RT_SYSTEM_NONE));
    assign load_use_response_interlock = ex_mem_valid_q &&
                                         ex_mem_memory_q == DC_RT_MEMORY_LOAD &&
                                         lsu_response_event && !lsu_rsp_error &&
                                         ex_mem_rd_write_q && ex_mem_rd_q != 5'd0 &&
                                         ex_mem_fast_context_q == fast_context_q &&
                                         if_id_valid_q && !load_branch_bypass_valid &&
                                         ((decode_uses_rs1 && ex_mem_rd_q == decode_rs1) ||
                                          (decode_uses_rs2 && ex_mem_rd_q == decode_rs2));
    // Timing-oriented mode: no combinational DSP-sum -> forwarding -> AGU/RAM chain.
    // The WB register supplies the dependent operand on the following cycle.
    assign mdu_use_response_interlock = MDU_WB_ONLY && ex_mem_valid_q &&
                                        ex_mem_m_valid_q && mdu_rsp_valid &&
                                        ex_mem_rd_write_q && ex_mem_rd_q != 5'd0 &&
                                        ex_mem_fast_context_q == fast_context_q && if_id_valid_q &&
                                        ((decode_uses_rs1 && ex_mem_rd_q == decode_rs1) ||
                                         (decode_uses_rs2 && ex_mem_rd_q == decode_rs2));
    assign id_issue_allowed = if_id_valid_q && ex_mem_can_accept && !address_wait &&
                              (!decode_m_valid || mdu_req_ready) &&
                              !ex_mem_csr_serializing && !pipeline_redirect &&
                              !load_use_response_interlock && !mdu_use_response_interlock;
    assign handler_entry_event = handler_entry_pending_q && id_issue_allowed &&
                                 !decode_exception_valid && !decode_csr_semantic_illegal &&
                                 if_id_pc_q == handler_vector_q;

    assign bpu_update_valid = BPU_ENABLE && ex_mem_control_complete &&
                              ex_mem_epoch_q == fetch_epoch_q &&
                              ex_mem_btb_index_q ==
                                  (ex_mem_pc_q[7:2] ^ ex_mem_pc_q[13:8]) &&
                              ex_mem_btb_tag_q == ex_mem_pc_q[31:8]
`ifdef DC_RT_VERIFICATION
                              && !$isunknown(ex_mem_pred_source_q)
`endif
                              ;
    always_comb begin
        bpu_update_type = DC_RT_BTB_CONDITIONAL;
        case (ex_mem_control_q)
            DC_RT_CONTROL_JAL: bpu_update_type = DC_RT_BTB_JAL_CALL;
            DC_RT_CONTROL_JALR: begin
                if (ex_mem_rd_q == 5'd0 &&
                    (ex_mem_instruction_q[19:15] == 5'd1 ||
                     ex_mem_instruction_q[19:15] == 5'd5) &&
                    ex_mem_control_immediate_q == 32'd0)
                    bpu_update_type = DC_RT_BTB_RETURN;
                else if (ex_mem_rd_q == 5'd1 || ex_mem_rd_q == 5'd5)
                    bpu_update_type = DC_RT_BTB_JAL_CALL;
                else
                    bpu_update_type = DC_RT_BTB_JALR;
            end
            default: begin end
        endcase
    end

    assign response_direct_jal_use = BPU_ENABLE && bpu_direct_jal_valid &&
                                     fetch_response_meta.epoch == fetch_epoch_q &&
                                     !fetch_response_meta.pred_taken &&
                                     !fetch_younger_pending &&
                                     fetch_offer_valid_q &&
                                     fetch_offer_epoch_q == fetch_response_meta.epoch &&
                                     fetch_offer_pc_q == fetch_response_meta.pc + 32'd4 &&
                                     !if_req_offered;
    // Mark the instruction as repaired only when its next offer is repaired.
    // Otherwise EX must still detect the original not-taken prediction miss.
    assign direct_jal_offer_repair = response_direct_jal_use;

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (!rst && load_branch_bypass_valid && branch_load_any &&
            branch_eq_load !== (load_result == branch_compare_other))
            $error("LOAD_BRANCH_LANE_COMPARE_MISMATCH");
        if (!rst && REGISTERED_AGU && id_issue_allowed &&
            decode_memory != DC_RT_MEMORY_NONE && !decode_exception_valid) begin
            if (!decode_address_valid_q || decode_memory_addr !== decode_address_comb)
                $error("V13_REGISTERED_AGU_MISMATCH pc=%h cached=%h expected=%h", if_id_pc_q, decode_memory_addr, decode_address_comb);
        end
        if (!rst && fetch_address_from_add && fetch_address_add_page_local &&
            fetch_result_valid && fetch_result_ready &&
            fetch_decode_memory != DC_RT_MEMORY_NONE) begin
            if (fetch_address_add_result !== (execute_result + fetch_decode_immediate))
                $error("V13_CSA_ADDRESS_MISMATCH");
        end
        if (!rst && !fetch_address_add_select && fetch_address_generic_page_local &&
            fetch_result_valid && fetch_result_ready &&
            fetch_decode_memory != DC_RT_MEMORY_NONE) begin
            if (fetch_address_generic_result !==
                (fetch_rs1_value + fetch_decode_immediate))
                $error("V13_GENERIC_PAGE_ADDRESS_MISMATCH");
        end
        if (!rst && load_address_nocarry_valid &&
            decode_memory != DC_RT_MEMORY_NONE &&
            load_address_nocarry !== (load_result + decode_immediate))
            $error("V13_CARRYFREE_ADDRESS_MISMATCH");
    end
    // synthesis translate_on

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (!rst && bpu_query_accept) begin
            if ($isunknown({bpu_pred_counter, bpu_loop_override_valid,
                            bpu_loop_override_taken}))
                $error("CORE0_BPU_ACCEPTED_PREDICTION_UNKNOWN");
            if (bpu_loop_override_valid &&
                bpu_pred_source != DC_RT_PRED_LOOP)
                $error("CORE0_BPU_LOOP_SOURCE_INCONSISTENT");
        end
    end
    // synthesis translate_on

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (!rst) begin
            if (mdu_rsp_valid && (!ex_mem_valid_q || !ex_mem_m_valid_q ||
                                  !mdu_response_match))
                $error("CORE0_RV32M_OWNER_IDENTITY_MISMATCH");
            if (mdu_busy && !ex_mem_valid_q)
                $error("CORE0_RV32M_BUSY_WITHOUT_PIPE_OWNER");
            if (mdu_busy && (!ex_mem_m_valid_q || !mdu_response_match))
                $error("CORE0_MDU_LIVE_OWNER_TUPLE_RED");
            if (mdu_req_valid && !mdu_req_ready)
                $error("CORE0_RV32M_ISSUE_WITHOUT_READY");
            if (mdu_req_valid && ex_mem_valid_q && ex_mem_rd_write_q &&
                mdu_ordinary_forward_available &&
                (ex_mem_rd_q == decode_rs1 || ex_mem_rd_q == decode_rs2) &&
                (ex_mem_fast_context_q != fast_context_q ||
                 ex_mem_system_q == DC_RT_SYSTEM_CSR))
                $error("CORE0_MDU_REDUNDANT_FORWARD_INVARIANT_RED");
        end
    end
    // synthesis translate_on

    always_ff @(posedge clk) begin
        if (rst) begin
            fetch_pc_q <= RESET_PC;
            fetch_offer_valid_q <= 1'b0;
            fetch_offer_pc_q <= RESET_PC;
            fetch_offer_epoch_q <= 2'd0;
            fetch_epoch_q <= 2'd0;
            fast_context_q <= 1'b0;
            handler_active_q <= 1'b0;
            sleeping_q <= 1'b0;
            resume_pc_q <= RESET_PC;
            irq_vector_pc_q <= 32'd0;
            handler_vector_q <= 32'd0;
            handler_entry_pending_q <= 1'b0;
            irq_accept_diag <= 1'b0;
            handler_entry_diag <= 1'b0;
            if_id_valid_q <= 1'b0;
            if_id_pc_q <= 32'd0;
            if_id_instruction_q <= 32'd0;
            if_id_fetch_fault_q <= 1'b0;
            if_id_epoch_q <= 2'd0;
            if_id_pred_taken_q <= 1'b0;
            if_id_pred_target_q <= 32'd0;
`ifdef DC_RT_VERIFICATION
            if_id_pred_source_q <= DC_RT_PRED_SEQUENTIAL;
`endif
            if_id_btb_index_q <= 6'd0;
            if_id_btb_tag_q <= 24'd0;
            if_id_loop_token_valid_q <= 1'b0;
            if_id_loop_token_index_q <= 5'd0;
            if_id_loop_token_tag_q <= 25'd0;
            if_id_loop_token_iteration_q <= 16'd0;
            if_id_loop_token_epoch_q <= 2'd0;
            if_id_rs1_value_q <= 32'd0;
            if_id_rs2_value_q <= 32'd0;
            decode_legal <= 1'b0;
            decode_rs1 <= 5'd0;
            decode_rs2 <= 5'd0;
            decode_rd <= 5'd0;
            decode_rd_write <= 1'b0;
            decode_alu_op <= DC_RT_ALU_ADD;
            decode_m_valid <= 1'b0;
            decode_m_op <= DC_RT_M_MUL;
            decode_operand_a_select <= DC_RT_OPERAND_A_RS1;
            decode_operand_b_immediate <= 1'b0;
            decode_immediate <= 32'd0;
            decode_control <= DC_RT_CONTROL_NONE;
            decode_branch_condition <= DC_RT_BRANCH_EQ;
            decode_control_immediate <= 32'd0;
            decode_memory <= DC_RT_MEMORY_NONE;
            decode_memory_size <= DC_RT_MEMORY_BYTE;
            decode_load_unsigned <= 1'b0;
            decode_system <= DC_RT_SYSTEM_NONE;
            decode_csr_op <= DC_RT_CSR_RW;
            decode_csr_immediate <= 1'b0;
            decode_csr_address <= 12'd0;
            decode_csr_source_zero <= 1'b1;
            ex_mem_valid_q <= 1'b0;
            ex_mem_pc_q <= 32'd0;
            ex_mem_instruction_q <= 32'd0;
            ex_mem_rd_q <= 5'd0;
            ex_mem_rd_write_q <= 1'b0;
            ex_mem_m_valid_q <= 1'b0;
            ex_mem_ordinary_result_ready_q <= 1'b1;
            ex_mem_result_q <= 32'd0;
            ex_mem_rs2_value_q <= 32'd0;
            ex_mem_control_immediate_q <= 32'd0;
            ex_mem_control_q <= DC_RT_CONTROL_NONE;
            ex_mem_branch_taken_q <= 1'b0;
            ex_mem_control_target_q <= 32'd0;
            ex_mem_memory_q <= DC_RT_MEMORY_NONE;
            ex_mem_memory_size_q <= DC_RT_MEMORY_BYTE;
            ex_mem_load_unsigned_q <= 1'b0;
            ex_mem_memory_addr_q <= 32'd0;
            ex_mem_epoch_q <= 2'd0;
            ex_mem_system_q <= DC_RT_SYSTEM_NONE;
            ex_mem_csr_op_q <= DC_RT_CSR_RW;
            ex_mem_csr_address_q <= 12'd0;
            ex_mem_csr_source_q <= 32'd0;
            ex_mem_csr_source_zero_q <= 1'b1;
            ex_mem_csr_read_data_q <= 32'd0;
            ex_mem_csr_read_valid_q <= 1'b0;
            ex_mem_csr_read_only_q <= 1'b0;
            ex_mem_csr_illegal_q <= 1'b0;
            ex_mem_exception_q <= 1'b0;
            ex_mem_exception_cause_q <= 32'd0;
            ex_mem_tval_source_q <= DC_RT_TVAL_ZERO;
            ex_mem_fast_context_q <= 1'b0;
            ex_mem_pred_taken_q <= 1'b0;
            ex_mem_pred_target_q <= 32'd0;
`ifdef DC_RT_VERIFICATION
            ex_mem_pred_source_q <= DC_RT_PRED_SEQUENTIAL;
`endif
            ex_mem_btb_index_q <= 6'd0;
            ex_mem_btb_tag_q <= 24'd0;
            ex_mem_loop_token_valid_q <= 1'b0;
            ex_mem_loop_token_index_q <= 5'd0;
            ex_mem_loop_token_tag_q <= 25'd0;
            ex_mem_loop_token_iteration_q <= 16'd0;
            ex_mem_loop_token_epoch_q <= 2'd0;
            lsu_outstanding_q <= 1'b0;
            lsu_outstanding_write_q <= 1'b0;
            lsu_outstanding_epoch_q <= 2'd0;
            wb_valid_q <= 1'b0;
            wb_pc_q <= 32'd0;
`ifdef DC_RT_VERIFICATION
            wb_instruction_q <= 32'd0;
`endif
            wb_rd_q <= 5'd0;
            wb_execute_rd_q <= 5'd0;
            wb_rd_write_q <= 1'b0;
            wb_result_q <= 32'd0;
            wb_csr_write_q <= 1'b0;
            wb_csr_address_q <= 12'd0;
            wb_csr_data_q <= 32'd0;
            wb_fast_context_q <= 1'b0;
`ifdef DC_RT_VERIFICATION
            wb_next_pc_q <= 32'd0;
`endif
            retire_valid_diag <= 1'b0;
            retire_pc_diag <= 32'd0;
`ifdef DC_RT_VERIFICATION
            trace_retire_instr <= 32'd0;
            trace_retire_rd <= 5'd0;
            trace_retire_rd_write <= 1'b0;
            trace_retire_value <= 32'd0;
            trace_retire_next_pc <= 32'd0;
`endif
        end else begin
            irq_accept_diag <= irq_accept;
            handler_entry_diag <= handler_entry_event;

            if (ex_mem_success_complete) begin
                if (mret_redirect)
                    resume_pc_q <= csr_mepc;
                else
                    resume_pc_q <= actual_next_pc;
            end

            if (irq_accept) begin
                fast_context_q <= 1'b1;
                handler_active_q <= 1'b1;
                sleeping_q <= 1'b0;
                irq_vector_pc_q <= irq_accepted_vector;
                handler_vector_q <= irq_accepted_vector;
                handler_entry_pending_q <= 1'b1;
            end else begin
                if (wfi_sleep_enter)
                    sleeping_q <= 1'b1;
                if (mret_redirect && handler_active_q) begin
                    fast_context_q <= 1'b0;
                    handler_active_q <= 1'b0;
                end
                if (handler_entry_event)
                    handler_entry_pending_q <= 1'b0;
            end

            retire_valid_diag <= wb_valid_q;
            if (wb_valid_q) begin
                retire_pc_diag <= wb_pc_q;
`ifdef DC_RT_VERIFICATION
                trace_retire_instr <= wb_instruction_q;
                trace_retire_rd <= wb_rd_q;
                trace_retire_rd_write <= wb_rd_write_q;
                trace_retire_value <= wb_rd_write_q ? wb_result_q : 32'd0;
                trace_retire_next_pc <= wb_next_pc_q;
`endif
            end else begin
                retire_pc_diag <= 32'd0;
`ifdef DC_RT_VERIFICATION
                trace_retire_instr <= 32'd0;
                trace_retire_rd <= 5'd0;
                trace_retire_rd_write <= 1'b0;
                trace_retire_value <= 32'd0;
                trace_retire_next_pc <= 32'd0;
`endif
            end

            wb_valid_q <= ex_mem_success_complete;
            // WB forwarding only uses this destination while wb_valid_q is
            // high. Clearing it otherwise keeps the local register distinct
            // from the architectural destination through synthesis.
            wb_execute_rd_q <= ex_mem_success_complete ? ex_mem_rd_q : 5'd0;
            if (ex_mem_success_complete) begin
                wb_pc_q <= ex_mem_pc_q;
`ifdef DC_RT_VERIFICATION
                wb_instruction_q <= ex_mem_instruction_q;
`endif
                wb_rd_q <= ex_mem_rd_q;
                wb_rd_write_q <= ex_mem_rd_write_q;
                wb_result_q <= ex_mem_completion_value;
                wb_csr_write_q <= ex_mem_system_q == DC_RT_SYSTEM_CSR &&
                                  ex_mem_csr_write_intent;
                wb_csr_address_q <= ex_mem_csr_address_q;
                wb_csr_data_q <= ex_mem_csr_write_data;
                wb_fast_context_q <= ex_mem_fast_context_q;
`ifdef DC_RT_VERIFICATION
                wb_next_pc_q <= mret_redirect ? csr_mepc : actual_next_pc;
`endif
            end

            if (if_id_valid_q && wb_valid_q && wb_rd_write_q &&
                wb_fast_context_q == fast_context_q) begin
                if (wb_rd_q == decode_rs1)
                    if_id_rs1_value_q <= wb_result_q;
                if (wb_rd_q == decode_rs2)
                    if_id_rs2_value_q <= wb_result_q;
            end

            if (ex_mem_success_complete || ex_mem_trap_valid || mdu_cancel)
                ex_mem_valid_q <= 1'b0;
            if (id_issue_allowed) begin
                if_id_valid_q <= 1'b0;
                ex_mem_valid_q <= 1'b1;
            end
            if (ex_mem_payload_capture) begin
                ex_mem_pc_q <= if_id_pc_q;
                ex_mem_instruction_q <= if_id_instruction_q;
                ex_mem_rd_q <= decode_rd;
                ex_mem_rd_write_q <= decode_exception_valid ? 1'b0 : decode_rd_write;
                ex_mem_m_valid_q <= decode_exception_valid ? 1'b0 : decode_m_valid;
                ex_mem_ordinary_result_ready_q <= decode_exception_valid ||
                    (!decode_m_valid && decode_system != DC_RT_SYSTEM_CSR &&
                     decode_memory == DC_RT_MEMORY_NONE);
                ex_mem_result_q <= execute_result;
                ex_mem_rs2_value_q <= decode_rs2_value;
                ex_mem_control_immediate_q <= decode_control_immediate;
                ex_mem_control_q <= decode_exception_valid ? DC_RT_CONTROL_NONE : decode_control;
                ex_mem_branch_taken_q <= decode_branch_taken;
                ex_mem_control_target_q <= decode_control_target;
                ex_mem_memory_q <= decode_exception_valid ? DC_RT_MEMORY_NONE : decode_memory;
                ex_mem_memory_size_q <= decode_memory_size;
                ex_mem_load_unsigned_q <= decode_load_unsigned;
                ex_mem_memory_addr_q <= decode_memory_addr;
                ex_mem_epoch_q <= if_id_epoch_q;
                ex_mem_system_q <= decode_exception_valid ? DC_RT_SYSTEM_NONE : decode_system;
                ex_mem_csr_op_q <= decode_csr_op;
                ex_mem_csr_address_q <= decode_csr_address;
                ex_mem_csr_source_q <= decode_csr_immediate ?
                                       {27'd0, decode_rs1} : decode_rs1_value;
                ex_mem_csr_source_zero_q <= decode_csr_source_zero;
                ex_mem_csr_read_data_q <= decode_csr_read_data;
                ex_mem_csr_read_valid_q <= csr_read_valid;
                ex_mem_csr_read_only_q <= csr_read_only;
                ex_mem_csr_illegal_q <= decode_csr_semantic_illegal && !decode_exception_valid;
                ex_mem_exception_q <= decode_exception_valid;
                ex_mem_exception_cause_q <= decode_exception_cause;
                ex_mem_tval_source_q <= decode_exception_tval_source;
                ex_mem_fast_context_q <= fast_context_q;
                ex_mem_pred_taken_q <= if_id_pred_taken_q;
                ex_mem_pred_target_q <= if_id_pred_target_q;
`ifdef DC_RT_VERIFICATION
                ex_mem_pred_source_q <= if_id_pred_source_q;
`endif
                ex_mem_btb_index_q <= if_id_btb_index_q;
                ex_mem_btb_tag_q <= if_id_btb_tag_q;
                ex_mem_loop_token_valid_q <= if_id_loop_token_valid_q;
                ex_mem_loop_token_index_q <= if_id_loop_token_index_q;
                ex_mem_loop_token_tag_q <= if_id_loop_token_tag_q;
                ex_mem_loop_token_iteration_q <= if_id_loop_token_iteration_q;
                ex_mem_loop_token_epoch_q <= if_id_loop_token_epoch_q;
            end

            if (fetch_offer_accept) begin
                fetch_offer_valid_q <= fetch_offer_refill_credit &&
                                       !pipeline_redirect && !sleeping_q;
                fetch_offer_pc_q <= fetch_offer_epoch_q != fetch_epoch_q ? fetch_pc_q :
                                    BPU_ENABLE && bpu_pred_valid &&
                                    bpu_pred_taken ? bpu_pred_target :
                                    fetch_offer_pc_plus4;
                fetch_offer_epoch_q <= fetch_epoch_q;
                if (fetch_offer_epoch_q == fetch_epoch_q) begin
                    if (BPU_ENABLE && bpu_pred_valid && bpu_pred_taken)
                        fetch_pc_q <= bpu_pred_target;
                    else
                        fetch_pc_q <= fetch_offer_pc_plus4;
                end
            end

            // A completion and a new launch may share an edge. New owner wins.
            if (lsu_rsp_valid && lsu_rsp_ready)
                lsu_outstanding_q <= 1'b0;
            if (lsu_req_valid && lsu_req_ready) begin
                lsu_outstanding_q <= 1'b1;
                lsu_outstanding_write_q <= lsu_req_write;
                lsu_outstanding_epoch_q <= lsu_offer_epoch;
            end

            if (fetch_result_valid && fetch_result_ready) begin
                if (!pipeline_redirect && fetch_result_live &&
                    fetch_response_meta.epoch == fetch_epoch_q) begin
                    if_id_valid_q <= 1'b1;
                    if_id_pc_q <= fetch_response_meta.pc;
                    if_id_instruction_q <= fetch_result_rdata;
                    if_id_fetch_fault_q <= fetch_result_error;
                    if_id_epoch_q <= fetch_response_meta.epoch;
                    if_id_pred_taken_q <= response_direct_jal_use ? 1'b1 :
                                          fetch_response_meta.pred_taken;
                    if_id_pred_target_q <= response_direct_jal_use ?
                                           bpu_direct_jal_target :
                                           fetch_response_meta.pred_target;
`ifdef DC_RT_VERIFICATION
                    if_id_pred_source_q <= response_direct_jal_use ?
                                           DC_RT_PRED_DIRECT_JAL :
                                           dc_rt_pred_source_e'(
                                               fetch_response_meta.pred_source);
`endif
                    if_id_btb_index_q <= (fetch_response_meta.pc[7:2] ^ fetch_response_meta.pc[13:8]);
                    if_id_btb_tag_q <= fetch_response_meta.pc[31:8];
                    if_id_loop_token_valid_q <=
                        fetch_response_meta.loop_token_valid;
                    if_id_loop_token_index_q <=
                        (fetch_response_meta.pc[6:2] ^ fetch_response_meta.pc[11:7]);
                    if_id_loop_token_tag_q <=
                        fetch_response_meta.pc[31:7];
                    if_id_loop_token_iteration_q <=
                        fetch_response_meta.loop_token_iteration;
                    if_id_loop_token_epoch_q <=
                        fetch_response_meta.epoch;
                    if_id_rs1_value_q <= fetch_rs1_value;
                    if_id_rs2_value_q <= fetch_rs2_value;
                    decode_legal <= fetch_decode_legal;
                    decode_rs1 <= fetch_decode_rs1;
                    decode_rs2 <= fetch_decode_rs2;
                    decode_rd <= fetch_decode_rd;
                    decode_rd_write <= fetch_decode_rd_write;
                    decode_alu_op <= fetch_decode_alu_op;
                    decode_m_valid <= fetch_decode_m_valid;
                    decode_m_op <= fetch_decode_m_op;
                    decode_operand_a_select <= fetch_decode_operand_a_select;
                    decode_operand_b_immediate <= fetch_decode_operand_b_immediate;
                    decode_immediate <= fetch_decode_immediate;
                    decode_control <= fetch_decode_control;
                    decode_branch_condition <= fetch_decode_branch_condition;
                    decode_control_immediate <= fetch_decode_control_immediate;
                    decode_memory <= fetch_decode_memory;
                    decode_memory_size <= fetch_decode_memory_size;
                    decode_load_unsigned <= fetch_decode_load_unsigned;
                    decode_system <= fetch_decode_system;
                    decode_csr_op <= fetch_decode_csr_op;
                    decode_csr_immediate <= fetch_decode_csr_immediate;
                    decode_csr_address <= fetch_decode_csr_address;
                    decode_csr_source_zero <= fetch_decode_csr_source_zero;
                end
            end

            if (direct_jal_offer_repair) begin
                fetch_offer_pc_q <= bpu_direct_jal_target;
                fetch_pc_q <= bpu_direct_jal_target;
            end

            if (!fetch_offer_valid_q && fetch_offer_credit_available &&
                !pipeline_redirect && !sleeping_q) begin
                fetch_offer_valid_q <= 1'b1;
                fetch_offer_pc_q <= fetch_pc_q;
                fetch_offer_epoch_q <= fetch_epoch_q;
            end

            if (pipeline_redirect) begin
                fetch_pc_q <= pipeline_redirect_target;
                fetch_epoch_q <= fetch_epoch_q + 2'd1;
                if_id_valid_q <= 1'b0;
                // Refill the target immediately when no old offer is held.
                // An unaccepted request stays stable until the memory accepts it.
                if (!if_req_offered || fetch_offer_accept) begin
                    fetch_offer_valid_q <= !wfi_sleep_enter;
                    fetch_offer_pc_q <= pipeline_redirect_target;
                    fetch_offer_epoch_q <= fetch_epoch_q + 2'd1;
                end
            end
        end
    end

    assign core_sleeping = sleeping_q;
    assign irq_vector_pc_diag = irq_vector_pc_q;
    assign fatal_state_diag = rst || irq_fault_seen;
endmodule
