// Original RV32 OoO candidate. See SOURCE_PROVENANCE.md.
// Bounded local scheduling, captured operands and commit-boundary recovery.
// No external CPU implementation is an input to this source.
module rv32_ooo_core #(
    parameter [31:0] RESET_VECTOR=32'h80000000,
    parameter ENABLE_PAIRING=1,
    parameter LOAD_ORDER_ISSUE_LOOKAHEAD=1,
    parameter MEMORY_CREDITS=3,
    parameter FETCH_CREDITS=2,
    parameter ENABLE_COMMITTED_RAS=1,
    parameter RAS_DEPTH=16,
    parameter ENABLE_TRACE=0,
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
    parameter ENABLE_DISPATCH_BYPASS=1
)(
    input clk, reset,
    output [31:0] d1_trap_cause,d1_trap_vector,
    output reg [31:0] d1_retire_next_pc0,
    output imem_request_valid, input imem_request_ready,
    output [31:0] imem_request_address,
    input imem_response_valid, output imem_response_ready,
    input [63:0] imem_response_data, input [1:0] imem_response_error,
    output dmem_request_valid, input dmem_request_ready,
    output [31:0] dmem_request_address,
    output dmem_request_write,
    output [1:0] dmem_request_size,
    output [31:0] dmem_request_wdata,
    output [3:0] dmem_request_wstrb,
    input dmem_response_valid, output dmem_response_ready,
    input [31:0] dmem_response_rdata, input dmem_response_error,
    input irq_software, irq_timer, irq_external,
    input [63:0] mtime,
    input event_icache_refill,event_dcache_refill,event_dcache_writeback,
    output reg fence_i, fence_d,
    output debug_redirect,debug_trap,debug_branch_miss,debug_jump_miss,debug_dispatch_stall,debug_frontend_stall,
    output reg [1:0] retire_valid,
    output reg [31:0] retire_pc0, retire_pc1,
    output reg [31:0] retire_instruction0, retire_instruction1,
    output reg [4:0] retire_destination0, retire_destination1,
    output reg [31:0] retire_value0, retire_value1,
    output reg [1:0] debug_alloc_valid,debug_alloc_proposal_valid,
    output reg [3:0] debug_alloc_queue0,debug_alloc_queue1,debug_issue_queue0,debug_issue_queue1,
    output reg [3:0] debug_alloc_tag0,
    output reg [63:0] debug_alloc_sequence0,
    output reg [31:0] debug_alloc_pc0,
    output reg [3:0] debug_alloc_tag1,
    output reg [63:0] debug_alloc_sequence1,
    output reg [31:0] debug_alloc_pc1,
    output reg [1:0] debug_issue_valid,
    output reg [1:0] debug_issue_from_allocation,
    output reg [3:0] debug_issue_tag0,
    output reg [63:0] debug_issue_sequence0,
    output reg [31:0] debug_issue_pc0,
    output reg [3:0] debug_issue_tag1,
    output reg [63:0] debug_issue_sequence1,
    output reg [31:0] debug_issue_pc1,
    output reg [2:0] debug_complete_valid,
    output reg [2:0] debug_complete_writes,debug_complete_broadcast,
    output reg [3:0] debug_complete_tag0,
    output reg [63:0] debug_complete_sequence0,
    output reg [31:0] debug_complete_pc0,
    output reg [3:0] debug_complete_tag1,
    output reg [63:0] debug_complete_sequence1,
    output reg [31:0] debug_complete_pc1,
    output reg [3:0] debug_complete_tag2,
    output reg [63:0] debug_complete_sequence2,
    output reg [31:0] debug_complete_pc2,
    output reg [2:0] debug_complete_exception,
    output reg [3:0] debug_retire_tag0,
    output reg [63:0] debug_retire_sequence0,
    output reg [3:0] debug_retire_tag1,
    output reg [63:0] debug_retire_sequence1,
    output reg debug_recovery_valid,
    output reg [63:0] debug_recovery_first_killed_sequence,
    output [4:0] debug_rob_count,
    output reg [2:0] debug_iq0_count,debug_iq1_count,debug_complex_count,
    output debug_lsu_active,debug_mdu_active,debug_quarantine_active,debug_head_valid,
    output [63:0] debug_head_sequence,
    output [3:0] debug_lsu_tag,
    output [63:0] debug_lsu_sequence,
    output [31:0] debug_lsu_pc,
    output debug_lsu_irrevocable,
    output debug_mdu_response_pending,debug_mdu_response_blocked,
    output [3:0] debug_lsu_response_tag,
    output [63:0] debug_lsu_response_sequence,
    output [31:0] debug_lsu_response_pc,
    output debug_lsu_reserved,debug_prepared_valid,debug_ex_memory_valid,
    output [3:0] debug_prepared_tag,debug_ex_memory_tag,
    output [63:0] debug_prepared_sequence,debug_ex_memory_sequence,
    output [31:0] debug_prepared_pc,debug_ex_memory_pc,
    output [1:0] debug_memory_reservations,
    output [2:0] debug_memory_credit_limit,
    output debug_prepared_second_valid,
    output [3:0] debug_prepared_second_tag,
    output [63:0] debug_prepared_second_sequence,
    output [31:0] debug_prepared_second_pc,
    output debug_mul_request_valid,debug_mul_request_ready,
    output [3:0] debug_mul_request_tag,
    output [63:0] debug_mul_request_sequence,
    output [31:0] debug_mul_request_pc,debug_mul_request_left,debug_mul_request_right,
    output debug_mul_response_valid,debug_mul_response_ready,
    output [3:0] debug_mul_response_tag,
    output [63:0] debug_mul_response_sequence,
    output [31:0] debug_mul_response_pc,debug_mul_response_value,
    output [1:0] debug_mul_occupancy,
    output debug_mul_ex_valid,debug_mul_ex_hold,
    output [3:0] debug_mul_ex_tag,
    output [63:0] debug_mul_ex_sequence,
    output [31:0] debug_mul_ex_pc,
    output debug_legacy_request_valid,debug_legacy_request_ready,
    output [3:0] debug_legacy_request_tag,
    output [63:0] debug_legacy_request_sequence,
    output [31:0] debug_legacy_request_pc,
    output debug_legacy_response_valid,debug_legacy_response_ready,
    output [3:0] debug_legacy_response_tag,
    output [63:0] debug_legacy_response_sequence,
    output [31:0] debug_legacy_response_pc,
    output debug_irq_pending,
    output [1:0] debug_raw_retire_mask,
    output [1:0] debug_ex_valid,debug_ex_fault,
    output [3:0] debug_ex_tag0,debug_ex_tag1,
    output [63:0] debug_ex_sequence0,debug_ex_sequence1,
    output [31:0] debug_ex_pc0,debug_ex_pc1,
    output [31:0] debug_second_next,debug_second_prediction
);
    reg [31:0] csr_status, csr_interrupt_enable, csr_vector, csr_scratch;
    reg [31:0] csr_exception_pc, csr_cause, csr_trap_value;
    reg [2:0] event_selector [0:3];
    reg [63:0] event_counter [0:3];
    reg [63:0] cycle_counter, instruction_counter;
    // Each segment adds a constant in parallel. Carries depend on old
    // registered lower bits, so a late event/retirement need not enter a
    //64-bit ripple chain. Later original CSR assignments keep their priority.
    wire [3:0] counter_event_step;
    genvar counter_event_row;
    generate for(counter_event_row=0;counter_event_row<4;counter_event_row=counter_event_row+1)begin:counter_events
        assign counter_event_step[counter_event_row]=
            (event_selector[counter_event_row]==1&&event_icache_refill)||
            (event_selector[counter_event_row]==2&&event_dcache_refill)||
            (event_selector[counter_event_row]==3&&event_dcache_writeback)||
            (event_selector[counter_event_row]==4&&debug_branch_miss);
    end endgenerate
    wire [31:0] interrupt_bits={20'b0,irq_external,3'b0,irq_timer,3'b0,irq_software,3'b0};
    wire interrupt_pending=csr_status[3] && |(interrupt_bits & csr_interrupt_enable);
    wire [31:0] interrupt_cause=(irq_external && csr_interrupt_enable[11])?32'h8000000b:
                                (irq_software && csr_interrupt_enable[3])?32'h80000003:32'h80000007;
    reg [31:0] architectural_pc;
    function [31:0] read_csr;
        input [11:0] number;
        begin
            case(number)
                12'h300:read_csr=csr_status;
                12'h301:read_csr=32'h40001102;
                12'h304:read_csr=csr_interrupt_enable;
                12'h305:read_csr=csr_vector;
                12'h306,12'h310:read_csr=0;
                12'h340:read_csr=csr_scratch;
                12'h341:read_csr=csr_exception_pc;
                12'h342:read_csr=csr_cause;
                12'h343:read_csr=csr_trap_value;
                12'h344:read_csr=interrupt_bits;
                12'hb00:read_csr=cycle_counter[31:0];
                12'hb80:read_csr=cycle_counter[63:32];
                12'hb02:read_csr=instruction_counter[31:0];
                12'hb82:read_csr=instruction_counter[63:32];
                12'hc01:read_csr=mtime[31:0];
                12'hc81:read_csr=mtime[63:32];
                12'hf11:read_csr=0;
                12'hf12:read_csr=5;
                12'hf13:read_csr=0;
                12'hf14:read_csr=0;
                default:begin
                    if(number>=12'hb03 && number<=12'hb06) read_csr=event_counter[number[1:0]-2'd3][31:0];
                    else if(number>=12'hb83 && number<=12'hb86) read_csr=event_counter[number[1:0]-2'd3][63:32];
                    else if(number>=12'h323 && number<=12'h326) read_csr={29'b0,event_selector[number[1:0]-2'd3]};
                    else read_csr=0;
                end
            endcase
        end
    endfunction
    function csr_exists;
        input [11:0] number;
        begin
            case(number)
                12'h300,12'h301,12'h304,12'h305,12'h306,12'h310,
                12'h340,12'h341,12'h342,12'h343,12'h344,
                12'hb00,12'hb80,12'hb02,12'hb82,
                12'hc01,12'hc81,
                12'hf11,12'hf12,12'hf13,12'hf14,12'hf15:csr_exists=1;
                default:csr_exists=(number>=12'hb03 && number<=12'hb1f)||(number>=12'hb83 && number<=12'hb9f)||(number>=12'h323 && number<=12'h33f);
            endcase
        end
    endfunction

    localparam ROB_SIZE=16, QUEUE_SIZE=12;
    localparam ORDERED_SCHEDULER=BANKED_ISSUE&&ENABLE_STEALING&&!ENABLE_SAME_CYCLE_REUSE;
    // One physical RAM per retirement lane, with a one-bit last-writer map.
    // A validity bitmap implements architectural reset without resetting RAM.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] register_lane0[0:31],register_lane1[0:31];
    reg register_valid[0:31],register_owner[0:31];
    function [31:0] read_register;
        input [4:0] number;
        begin
            if(number==0||!register_valid[number])read_register=0;
            else read_register=register_owner[number]?register_lane1[number]:register_lane0[number];
        end
    endfunction
    reg map_valid[0:31]; reg [3:0] map_tag[0:31];
    reg rob_valid[0:15],rob_done[0:15],rob_fault[0:15],rob_writes[0:15];
    reg rob_memory[0:15],rob_store[0:15],rob_complex[0:15],rob_serial[0:15],rob_fetch_error[0:15];
    reg rob_arithmetic[0:15],rob_decode_error[0:15];
    reg rob_control[0:15],rob_conditional[0:15],rob_taken[0:15];
    reg rob_prediction_miss[0:15];
    reg rob_history_sequential[0:15];
    (* syn_ramstyle="distributed_ram" *) reg [9:0] rob_context_even[0:7],rob_context_odd[0:7];
    (* syn_ramstyle="distributed_ram" *) reg [7:0] rob_recovery_even[0:7],rob_recovery_odd[0:7];
    function [7:0] read_recovery_context;
        input [3:0] tag;
        begin read_recovery_context=tag[0]?rob_recovery_odd[tag[3:1]]:rob_recovery_even[tag[3:1]];end
    endfunction
    function [9:0] read_prediction_context;
        input [3:0] tag;
        begin read_prediction_context=tag[0]?rob_context_odd[tag[3:1]]:rob_context_even[tag[3:1]];end
    endfunction
    // Consecutive ROB allocation guarantees at most one write to each parity
    // bank per edge, including a wrapped two-wide bundle.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] rob_instruction_even[0:7],rob_instruction_odd[0:7];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] rob_prediction_even[0:7],rob_prediction_odd[0:7];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] next_lane0[0:15],next_lane1[0:15];
    function [31:0] read_rob_pc;
        input [3:0] tag;
        reg [3:0] previous;
        begin
            // A live non-head instruction follows its predecessor's predicted
            // PC. The architectural PC anchors the current head, whose old
            // predecessor slot may already have been reused after retirement.
            previous=tag-4'd1;
            read_rob_pc=tag==rob_head?architectural_pc:read_rob_prediction(previous);
        end
    endfunction
    function [31:0] read_rob_instruction;
        input [3:0] tag;
        begin read_rob_instruction=tag[0]?rob_instruction_odd[tag[3:1]]:rob_instruction_even[tag[3:1]];end
    endfunction
    function [31:0] read_rob_prediction;
        input [3:0] tag;
        begin read_rob_prediction=tag[0]?rob_prediction_odd[tag[3:1]]:rob_prediction_even[tag[3:1]];end
    endfunction
    function [31:0] read_rob_next;
        input [3:0] tag;
        begin
            if(rob_control[tag]||rob_system[tag]==2)
                read_rob_next=result_owner[tag]==0?next_lane0[tag]:next_lane1[tag];
            else read_rob_next=read_rob_pc(tag)+32'd4;
        end
    endfunction
    // Completion lane banks each have exactly one write port. Registered
    // owner bits select the last completion; done guards uninitialized rows.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] result_lane0[0:15],result_lane1[0:15],result_lane2[0:15];
    reg [1:0] result_owner[0:15];
    reg [31:0] rob_cause[0:15];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] tval_lane0[0:15],tval_lane1[0:15],tval_lane2[0:15];
    function [31:0] read_rob_tval;
        input [3:0] tag;
        begin
            case(result_owner[tag])
                0:read_rob_tval=tval_lane0[tag];
                1:read_rob_tval=tval_lane1[tag];
                default:read_rob_tval=tval_lane2[tag];
            endcase
        end
    endfunction
    // CSR execution is serialized with an otherwise empty ROB, so only one
    // pending CSR payload can exist. Per-entry write eligibility is retained.
    reg [31:0] serial_csr_value;
    reg [11:0] serial_csr_number;
    function [31:0] read_result;
        input [3:0] tag;
        begin
            case(result_owner[tag])
                0:read_result=result_lane0[tag];
                1:read_result=result_lane1[tag];
                default:read_result=result_lane2[tag];
            endcase
        end
    endfunction
    reg [4:0] rob_destination[0:15];
    reg [2:0] rob_system[0:15]; reg rob_csr_write[0:15];
    reg [63:0] rob_sequence[0:15];
    reg [3:0] rob_head,rob_tail; reg [4:0] rob_count; reg serial_pending;
    reg [63:0] next_sequence;
    wire [3:0] head1=rob_head+4'd1,tail1=rob_tail+4'd1;

    reg q_valid[0:11],q_left_ready[0:11],q_right_ready[0:11];
    reg q_writes[0:11],q_error[0:11],q_serial[0:11],q_memory[0:11],q_arithmetic[0:11],q_multiply[0:11];
    // EXMETA queue variant: five immutable bits per existing queue entry.
    // [0] ordinary integer, [1] misaligned JAL immediate, [2] JALR,
    // [3] PC invalid, [4] CSR access fault. Reuse q_error separately.
    // Payload is initialized with the matching allocation and owned by q_valid.
    reg [4:0] q_control_meta[0:11];
    reg legacy_issue_credit;
    reg [3:0] q_tag[0:11],q_left_tag[0:11],q_right_tag[0:11];
    reg [31:0] q_left[0:11],q_right[0:11];
    reg steer;
    reg ex_valid0,ex_valid1;
    // Immutable effective register-write identity, captured with each EX owner.
    reg ex_writes0,ex_writes1;
    reg [3:0] ex_tag0,ex_tag1;
    reg [63:0] ex_sequence0,ex_sequence1;
    reg [31:0] ex_instruction0,ex_instruction1,ex_pc0,ex_pc1,ex_left0,ex_left1,ex_right0,ex_right1;

    wire [31:0] fetch_instruction0,fetch_instruction1,fetch_pc0,fetch_pc1,fetch_prediction0,fetch_prediction1;
    wire fetch_error0,fetch_error1; wire [3:0] fetch_count;
    wire fetch_serial0,fetch_serial1,fetch_complex0,fetch_complex1;
    wire fetch_pc_dispatch_ok0,fetch_pc_dispatch_ok1;
    wire predictor_training_ready;
    wire [7:0] recovery_history;
    wire [11:0] allocation_occupied;
    wire [4:0] d_rs10,d_rs20,d_rd0,d_rs11,d_rs21,d_rd1;
    wire d_use10,d_use20,d_write0,d_mem0,d_store0,d_mdu0,d_csr0,d_bad0;
    wire d_use11,d_use21,d_write1,d_mem1,d_store1,d_mdu1,d_csr1,d_bad1;
    wire [7:0] predictor_committed_history,fetch_recovery_context0,fetch_recovery_context1;
    wire fetch_prediction_sequential0,fetch_prediction_sequential1;
    wire [9:0] fetch_prediction_context0,fetch_prediction_context1;
    reg [1:0] allocation_offer_count;
    // Recovery cancels acceptance, not the pre-edge free-slot proposal.
    wire [1:0] allocate_count=recovery?2'b0:allocation_offer_count;
    reg recovery,trap_enter,return_from_trap,maintain_i,maintain_d;
    reg [31:0] recovery_address,trap_pc,trap_cause,trap_value;
    reg [63:0] recovery_first;
    reg retire0,retire1;
    reg registered_pair_retire;
    // The successor's PC is the current head's immutable prediction. Cache
    // it across the existing ROB ownership edge, before the PHT lookup;
    // training keeps its original edge and ordered dual-port semantics.
    reg [31:0] training_successor_pc;
    wire [3:0] training_head2=rob_head+4'd2;
    function [31:0] training_prediction_proposal;
        input [3:0] tag;
        begin
            if(allocation_offer_count!=0&&rob_tail==tag)training_prediction_proposal=fetch_prediction0;
            else if(allocation_offer_count==2&&tail1==tag)training_prediction_proposal=fetch_prediction1;
            else training_prediction_proposal=read_rob_prediction(tag);
        end
    endfunction
    wire [31:0] training_proposal0=training_prediction_proposal(rob_head);
    wire [31:0] training_proposal1=training_prediction_proposal(head1);
    wire [31:0] training_proposal2=training_prediction_proposal(training_head2);
    always @(posedge clk)begin
        if(reset)training_successor_pc<=RESET_VECTOR+32'd4;
        else training_successor_pc<=retire0?(retire1?training_proposal2:training_proposal1):training_proposal0;
    end
`ifdef VERILATOR
    reg [4:0] training_pc_seen;
    always @(posedge clk)begin
        if(reset)training_pc_seen<=0;
        else begin
            if(rob_count!=0&&training_successor_pc!=read_rob_prediction(rob_head))
                $fatal(1,"R37 registered training PC differs from original current head prediction");
            if(!training_pc_seen[0]&&rob_count==0&&allocate_count!=0)begin training_pc_seen[0]<=1;$display("COVERAGE R37 training_pc_empty_allocate");end
            if(!training_pc_seen[1]&&retire0&&allocate_count!=0)begin training_pc_seen[1]<=1;$display("COVERAGE R37 training_pc_pop_allocate");end
            if(!training_pc_seen[2]&&retire0&&retire1)begin training_pc_seen[2]<=1;$display("COVERAGE R37 training_pc_retire_pair");end
            if(!training_pc_seen[3]&&retire0&&(retire1?rob_head>=14:rob_head==15))begin training_pc_seen[3]<=1;$display("COVERAGE R37 training_pc_wrap");end
            if(!training_pc_seen[4]&&recovery)begin training_pc_seen[4]<=1;$display("COVERAGE R37 training_pc_recovery");end
        end
    end
`endif
    // Existing ROB completion/ownership boundary, before recovery selects
    // the next PC. Parallel raw proposals and completion/allocation bypasses
    // keep the late current response out of result-owner -> RAM selection.
    // These are private payloads: live ROB ownership qualifies every use.
    reg [31:0] retirement_next0,retirement_next1;
    wire [3:0] retirement_head3=rob_head+4'd3;
    function [31:0] retirement_next_proposal;
        input [3:0] tag;
        begin
            if(allocation_offer_count!=0&&rob_tail==tag)retirement_next_proposal=fetch_pc0+32'd4;
            else if(allocation_offer_count==2&&tail1==tag)retirement_next_proposal=fetch_pc1+32'd4;
            else if(payload_integer1&&e_control1&&ex_tag1==tag)retirement_next_proposal=e_next1;
            else if(payload0&&(e_control0||e_system0==2)&&ex_tag0==tag)
                retirement_next_proposal=e_system0==2?csr_exception_pc:e_next0;
            else retirement_next_proposal=read_rob_next(tag);
        end
    endfunction
    wire [31:0] retirement_proposal0=retirement_next_proposal(rob_head);
    wire [31:0] retirement_proposal1=retirement_next_proposal(head1);
    wire [31:0] retirement_proposal2=retirement_next_proposal(training_head2);
    wire [31:0] retirement_proposal3=retirement_next_proposal(retirement_head3);
    always @(posedge clk)begin
        retirement_next0<=retire0?(retire1?retirement_proposal2:retirement_proposal1):retirement_proposal0;
        retirement_next1<=retire0?(retire1?retirement_proposal3:retirement_proposal2):retirement_proposal1;
    end
`ifdef VERILATOR
    reg [4:0] retirement_next_seen;
    always @(posedge clk)begin
        if(reset)retirement_next_seen<=0;
        else begin
            if(rob_count>0&&retirement_next0!=read_rob_next(rob_head))
                $fatal(1,"R38 cached first retirement target differs from original raw value");
            if(rob_count>1&&retirement_next1!=read_rob_next(head1))
                $fatal(1,"R38 cached second retirement target differs from original raw value");
            if(!retirement_next_seen[0]&&payload0&&e_control0&&(ex_tag0==rob_head||ex_tag0==head1))begin retirement_next_seen[0]<=1;$display("COVERAGE R38 retirement_next_control0_forward");end
            if(!retirement_next_seen[1]&&payload_integer1&&e_control1&&(ex_tag1==rob_head||ex_tag1==head1))begin retirement_next_seen[1]<=1;$display("COVERAGE R38 retirement_next_control1_forward");end
            if(!retirement_next_seen[2]&&retire0&&retire1)begin retirement_next_seen[2]<=1;$display("COVERAGE R38 retirement_next_pair_shift");end
            if(!retirement_next_seen[3]&&retire0&&allocate_count!=0)begin retirement_next_seen[3]<=1;$display("COVERAGE R38 retirement_next_pop_allocate");end
            if(!retirement_next_seen[4]&&payload0&&e_system0==2)begin retirement_next_seen[4]<=1;$display("COVERAGE R38 retirement_next_mret_forward");end
        end
    end
`endif
    // A current ordinary integer has no control-training payload. Qualify
    // training with existing registered completion/retirement facts so its
    // full illegal-encoding decode cannot enter the predictor write enable.
`ifdef VERILATOR
    reg [9:0] prediction_context_reference[0:15];
    integer context_row;
    always @(posedge clk)if(!reset)begin
        for(context_row=0;context_row<16;context_row=context_row+1)
            if(rob_valid[context_row]&&read_prediction_context(context_row[3:0])!=prediction_context_reference[context_row])
                $fatal(1,"R45 live ROB prediction context differs from accepted allocation");
        if(allocate_count!=0)prediction_context_reference[rob_tail]<=fetch_prediction_context0;
        if(allocate_count==2)prediction_context_reference[tail1]<=fetch_prediction_context1;
    end
`endif
`ifdef VERILATOR
    reg [7:0] recovery_context_reference[0:15];
    integer recovery_context_row;
    always @(posedge clk)if(!reset)begin
        for(recovery_context_row=0;recovery_context_row<16;recovery_context_row=recovery_context_row+1)
            if(rob_valid[recovery_context_row]&&read_recovery_context(recovery_context_row[3:0])!=recovery_context_reference[recovery_context_row])
                $fatal(1,"R49 live ROB prediction context differs from accepted allocation");
        if(allocate_count!=0)recovery_context_reference[rob_tail]<=fetch_recovery_context0;
        if(allocate_count==2)recovery_context_reference[tail1]<=fetch_recovery_context1;
    end
`endif
`ifdef VERILATOR
    reg [7:0] r48_retired_history;
    reg r48_pressure_seen;
    wire [7:0] r48_history0=(retire0&&rob_conditional[rob_head])?
        {r48_retired_history[6:0],(read_rob_next(rob_head)!=read_rob_pc(rob_head)+32'd4)}:r48_retired_history;
    always @(posedge clk)begin
        if(reset)begin r48_retired_history<=0;r48_pressure_seen<=0;end
        else begin
            if(frontend.direction_predictor.committed_history!=r48_retired_history)
                $fatal(1,"R48 GHR differs from independent actual-retirement history");
            r48_retired_history<=(retire1&&rob_conditional[head1])?
                {r48_history0[6:0],(read_rob_next(head1)!=read_rob_pc(head1)+32'd4)}:r48_history0;
            if(rob_count!=0&&rob_done[rob_head]&&rob_conditional[rob_head]&&!predictor_training_ready&&!r48_pressure_seen)begin
                r48_pressure_seen<=1;$display("COVERAGE R48 training_queue_backpressure");
            end
        end
    end
    always @(posedge clk)if(!reset)begin
        if((retire0&&rob_conditional[rob_head]&&!train0)||(retire1&&rob_conditional[head1]&&!train1))
            $fatal(1,"R48 retired conditional branch lost its training event");
        if((train0&&rob_conditional[rob_head]||train1&&rob_conditional[head1])&&!predictor_training_ready)
            $fatal(1,"R48 retired conditional branch without predictor queue credit");
    end
`endif
    wire train0=retire0&&rob_done[rob_head]&&rob_control[rob_head];
    wire train1=registered_pair_retire&&rob_control[head1];
`ifdef VERILATOR
    reg [2:0] training_qualification_seen;
    always @(posedge clk)begin
        if(reset)training_qualification_seen<=0;
        else begin
            if(train0!=(retire0&&rob_control[rob_head])||train1!=(retire1&&rob_control[head1]))
                $fatal(1,"R40 completed training qualification differs from original actual retirement");
            if(!training_qualification_seen[0]&&retire1&&!registered_pair_retire)begin
                training_qualification_seen[0]<=1;$display("COVERAGE R40 training_current_integer_no_control");
            end
            if(!training_qualification_seen[1]&&train0)begin training_qualification_seen[1]<=1;$display("COVERAGE R40 training_registered_head");end
            if(!training_qualification_seen[2]&&train1)begin training_qualification_seen[2]<=1;$display("COVERAGE R40 training_registered_pair");end
        end
    end
`endif
    rv32_ooo_frontend #(.RESET_VECTOR(RESET_VECTOR),.FETCH_CREDITS(FETCH_CREDITS),.ENABLE_REDIRECT_FETCH(ENABLE_REDIRECT_FETCH),
        .ENABLE_COMMITTED_RAS(ENABLE_COMMITTED_RAS),.RAS_DEPTH(RAS_DEPTH)) frontend(
        .clk(clk),.reset(reset),.imem_request_valid(imem_request_valid),.imem_request_ready(imem_request_ready),
        .imem_request_address(imem_request_address),.imem_response_valid(imem_response_valid),
        .imem_response_ready(imem_response_ready),.imem_response_data(imem_response_data),.imem_response_error(imem_response_error),
        .redirect(recovery),.redirect_address(recovery_address),.maintenance_redirect(maintain_i||maintain_d),.pop_count(allocate_count),.queue_count(fetch_count),
        .instruction0(fetch_instruction0),.instruction1(fetch_instruction1),.pc0(fetch_pc0),.pc1(fetch_pc1),
        .prediction0(fetch_prediction0),.prediction1(fetch_prediction1),.error0(fetch_error0),.error1(fetch_error1),
        .serial0(fetch_serial0),.serial1(fetch_serial1),.complex0(fetch_complex0),.complex1(fetch_complex1),
        .illegal0(d_bad0),.illegal1(d_bad1),
        .source_used10(d_use10),.source_used20(d_use20),.source_used11(d_use11),.source_used21(d_use21),
        .pc_dispatch_ok0(fetch_pc_dispatch_ok0),.pc_dispatch_ok1(fetch_pc_dispatch_ok1),
        .prediction_sequential0(fetch_prediction_sequential0),.prediction_sequential1(fetch_prediction_sequential1),
        .prediction_context0(fetch_prediction_context0),.prediction_context1(fetch_prediction_context1),
        .train_context0(read_prediction_context(rob_head)),.train_context1(read_prediction_context(head1)),
        .training_ready(predictor_training_ready),.committed_history(predictor_committed_history),
        .redirect_history(recovery_history),
        .recovery_context0(fetch_recovery_context0),.recovery_context1(fetch_recovery_context1),
        .train_instruction0(read_rob_instruction(rob_head)),.train_instruction1(read_rob_instruction(head1)),
        .train0(train0),.train1(train1),.train_pc0(read_rob_pc(rob_head)),.train_pc1(training_successor_pc),
        .train_next0(retirement_next0),.train_next1(retirement_next1),
        .train_conditional0(rob_conditional[rob_head]),.train_conditional1(rob_conditional[head1]),
        .train_taken0(rob_taken[rob_head]),.train_taken1(rob_taken[head1]),
        .train_history_taken0(rob_taken[rob_head]&&!rob_history_sequential[rob_head]),
        .train_history_taken1(rob_taken[head1]&&!rob_history_sequential[head1])
    );

    wire [2:0] d_system0,d_system1;
    wire d_bad_reference0,d_bad_reference1;
    wire ref_use10,ref_use20,ref_use11,ref_use21;
    wire d_serial0=fetch_serial0,d_serial1=fetch_serial1;
    wire d_complex0=fetch_complex0,d_complex1=fetch_complex1;
    rv32_execute decode0(.instruction(fetch_instruction0),.pc(fetch_pc0),.left(32'b0),.right(32'b0),.csr_value(32'b0),
        .source1(d_rs10),.source2(d_rs20),.destination(d_rd0),.uses_source1(ref_use10),.uses_source2(ref_use20),
        .writes_destination(d_write0),.memory(d_mem0),.memory_write(d_store0),.arithmetic(d_mdu0),
        .csr(d_csr0),.system_operation(d_system0),.illegal(d_bad_reference0));
    rv32_execute decode1(.instruction(fetch_instruction1),.pc(fetch_pc1),.left(32'b0),.right(32'b0),.csr_value(32'b0),
        .source1(d_rs11),.source2(d_rs21),.destination(d_rd1),.uses_source1(ref_use11),.uses_source2(ref_use21),
        .writes_destination(d_write1),.memory(d_mem1),.memory_write(d_store1),.arithmetic(d_mdu1),
        .csr(d_csr1),.system_operation(d_system1),.illegal(d_bad_reference1));

`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&{d_use10,d_use20}!={ref_use10,ref_use20})
            $fatal(1,"R46 first queued operand-use flags differ from execute decoder");
        if(fetch_count>1&&{d_use11,d_use21}!={ref_use11,ref_use21})
            $fatal(1,"R46 second queued operand-use flags differ from execute decoder");
    end
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&fetch_pc_dispatch_ok0!=(fetch_pc0[1:0]==0&&(fetch_pc0[31:28]==1||fetch_pc0[31:28]==8)))
            $fatal(1,"R30 first queued PC classification mismatch");
        if(fetch_count>1&&fetch_pc_dispatch_ok1!=(fetch_pc1[1:0]==0&&(fetch_pc1[31:28]==1||fetch_pc1[31:28]==8)))
            $fatal(1,"R30 second queued PC classification mismatch");
    end
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&fetch_prediction_sequential0!=(fetch_prediction0==fetch_pc0+32'd4))
            $fatal(1,"R34 first allocation prediction sequence flag mismatch");
        if(fetch_count>1&&fetch_prediction_sequential1!=(fetch_prediction1==fetch_pc1+32'd4))
            $fatal(1,"R34 second allocation prediction sequence flag mismatch");
    end
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&d_bad0!=d_bad_reference0)$fatal(1,"R36 first queued legality differs from original decoder");
        if(fetch_count>1&&d_bad1!=d_bad_reference1)$fatal(1,"R36 second queued legality differs from original decoder");
    end
    // The unchanged original execution decoder is an independent reference
    // for every valid head instruction, including reserved/fault encodings.
    always @(posedge clk)if(!reset)begin
        if(fetch_count>0&&((fetch_serial0!=(d_csr0||d_system0!=0))||
            (fetch_complex0!=(d_mem0||d_mdu0||d_csr0||d_system0!=0))))
            $fatal(1,"frontend lane 0 class differs from original decoder");
        if(fetch_count>1&&((fetch_serial1!=(d_csr1||d_system1!=0))||
            (fetch_complex1!=(d_mem1||d_mdu1||d_csr1||d_system1!=0))))
            $fatal(1,"frontend lane 1 class differs from original decoder");
    end
`endif
    wire [31:0] e_value0,e_value1,e_address0,e_address1,e_store0,e_store1,e_next0,e_next1;
    wire e_memory0,e_store_enable0,e_unsigned0,e_arithmetic0,e_control0,e_conditional0,e_taken0,e_csr0,e_csr_write0,e_illegal0;
    wire e_memory1,e_arithmetic1,e_control1,e_conditional1,e_taken1,e_illegal1;
    reg ex_decode_error0,ex_decode_error1;
    wire e_illegal_reference0,e_illegal_reference1;
    assign e_illegal0=ex_decode_error0;
    assign e_illegal1=ex_decode_error1;

    // EXMETA experiment: immutable control facts travel with the existing EX
    // packet, not through a new pipeline stage. Preserve raw class bits even
    // for illegal encodings; precise faults still have their original priority.
    // [0] memory, [1] MDU, [2] ordinary integer, [3] misaligned JAL immediate,
    // [4] JALR, [5] static instruction/PC fault. CSR access checks are likewise
    // instruction-only in this implementation, including the rs1/zimm test.
    reg [5:0] ex_control_meta0,ex_control_meta1;
    reg ex_csr_access_fault0;
    wire e_memory_reference0,e_memory_reference1;
    wire e_arithmetic_reference0,e_arithmetic_reference1;
    assign e_memory0=ex_control_meta0[0];
    assign e_memory1=ex_control_meta1[0];
    assign e_arithmetic0=ex_control_meta0[1];
    assign e_arithmetic1=ex_control_meta1[1];

    wire [1:0] e_size0; wire [2:0] e_arithmetic_operation0,e_system0;
    wire [11:0] e_csr_number0; wire [31:0] e_csr_new0;
    rv32_execute execute0(.instruction(ex_instruction0),.pc(ex_pc0),.left(ex_left0),.right(ex_right0),
        .csr_value(read_csr(e_csr_number0)),.value(e_value0),.address(e_address0),.store_value(e_store0),.next_pc(e_next0),
        .memory(e_memory_reference0),.memory_write(e_store_enable0),.memory_size(e_size0),.memory_unsigned(e_unsigned0),
        .arithmetic(e_arithmetic_reference0),.arithmetic_operation(e_arithmetic_operation0),.control(e_control0),
        .conditional(e_conditional0),.taken(e_taken0),.csr(e_csr0),.csr_write(e_csr_write0),.csr_new_value(e_csr_new0),
        .csr_number(e_csr_number0),.system_operation(e_system0),.illegal(e_illegal_reference0));
    rv32_execute execute1(.instruction(ex_instruction1),.pc(ex_pc1),.left(ex_left1),.right(ex_right1),.csr_value(32'b0),
        .value(e_value1),.address(e_address1),.store_value(e_store1),.next_pc(e_next1),.memory(e_memory_reference1),
        .arithmetic(e_arithmetic_reference1),.control(e_control1),.conditional(e_conditional1),.taken(e_taken1),.illegal(e_illegal_reference1));

    // LSU state retains a presented request even while an old path is discarded.
    localparam L_IDLE=0,L_PREPARED=1,L_OFFER=2,L_WAIT=3;
    reg [1:0] lsu_state;
    reg [3:0] lsu_tag; reg [63:0] lsu_sequence; reg [31:0] lsu_pc,lsu_address,lsu_wdata;
    reg [3:0] lsu_strobes; reg [1:0] lsu_size;
    reg lsu_store,lsu_unsigned,lsu_killed,lsu_irrevocable,lsu_writes;
    wire lsu_active=lsu_state!=L_IDLE;
    // Three registered credits cover A, prepared FIFO P0/P1 and EX.
    // A move uses no credit. Admission never uses the current response/recovery.
    reg prepared_valid;
    reg [3:0] prepared_tag,prepared_strobes;
    reg [63:0] prepared_sequence;
    reg [31:0] prepared_pc,prepared_address,prepared_wdata;
    reg [1:0] prepared_size;
    reg prepared_store,prepared_unsigned,prepared_peripheral,prepared_writes;
    reg prepared_second_valid;
    reg [3:0] prepared_second_tag,prepared_second_strobes;
    reg [63:0] prepared_second_sequence;
    reg [31:0] prepared_second_pc,prepared_second_address,prepared_second_wdata;
    reg [1:0] prepared_second_size;
    reg prepared_second_store,prepared_second_unsigned,prepared_second_peripheral,prepared_second_writes;
    wire ex_memory_reservation=ex_valid0&&e_memory0&&!fault0;
    wire ex_memory_credit=ex_valid0&&e_memory0;
    // Memory-class fault qualification avoids the unrelated branch-result
    // alignment cone while preserving exact ownership for ordering checks.
    wire ex_memory_order_owner=ex_memory_credit&&ex_pc0[1:0]==0&&
        !rob_fetch_error[ex_tag0]&&(ex_pc0[31:28]==1||ex_pc0[31:28]==8)&&!e_illegal0&&
        !((e_size0==2&&e_address0[1:0]!=0)||(e_size0==1&&e_address0[0]));
    wire active_reserved=lsu_active||lsu_irrevocable;
    wire [2:0] memory_reservations_wide={2'b0,active_reserved}+{2'b0,prepared_valid}+
        {2'b0,prepared_second_valid}+{2'b0,ex_memory_reservation};
    wire [2:0] issue_memory_reservations={2'b0,active_reserved}+{2'b0,prepared_valid}+
        {2'b0,prepared_second_valid}+{2'b0,ex_memory_credit};
    wire [1:0] memory_reservations=memory_reservations_wide[1:0];
    wire [31:0] ex_shifted_store=e_store0<<{e_address0[1:0],3'b0};
    wire [3:0] ex_store_strobes=e_size0==0?(4'b0001<<e_address0[1:0]):
                               e_size0==1?(4'b0011<<e_address0[1:0]):4'b1111;
    // P precedes EX. Every field, including side-effect classification, comes
    // from the same owner. Old response fields remain exclusively in A.
    wire candidate_valid=prepared_valid||ex_memory_reservation;
    wire [3:0] candidate_tag=prepared_valid?prepared_tag:ex_tag0;
    wire candidate_writes=prepared_valid?prepared_writes:ex_writes0;
    wire [63:0] candidate_sequence=prepared_valid?prepared_sequence:ex_sequence0;
    wire [31:0] candidate_pc=prepared_valid?prepared_pc:ex_pc0;
    wire [31:0] candidate_address=prepared_valid?prepared_address:e_address0;
    wire [31:0] candidate_wdata=prepared_valid?prepared_wdata:ex_shifted_store;
    wire [3:0] candidate_strobes=prepared_valid?prepared_strobes:ex_store_strobes;
    wire [1:0] candidate_size=prepared_valid?prepared_size:e_size0;
    wire candidate_store=prepared_valid?prepared_store:e_store_enable0;
    wire candidate_unsigned=prepared_valid?prepared_unsigned:e_unsigned0;
    wire [11:0] ex_address_offset=ex_instruction0[5]?{ex_instruction0[31:25],ex_instruction0[11:7]}:ex_instruction0[31:20];
    wire ex_peripheral_proposal;
    rv32_address_classify address_flags(.base(ex_left0),.offset(ex_address_offset),.peripheral(ex_peripheral_proposal));
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&ex_valid0&&e_memory0&&ex_peripheral_proposal!=peripheral_address(e_address0))
        $fatal(1,"R42 early peripheral classification differs from original full effective address");
`endif
    wire candidate_peripheral=prepared_valid?prepared_peripheral:ex_peripheral_proposal;
    wire candidate_side_effect=candidate_store||candidate_peripheral;
    wire active_room=!active_reserved||lsu_turnover;
    // Raw first-visible head side effects defer IRQ without depending on the
    // recovery decision. A prospective head after retirement is insufficient.
    wire ex_head_side_effect=candidate_valid&&candidate_side_effect&&candidate_tag==rob_head&&!active_reserved;
    wire prepared_side_effect=lsu_state==L_PREPARED&&lsu_tag==rob_head&&!lsu_irrevocable;
    // Idle direct loads retain killed capture on recovery. A new turnover
    // offer is suppressed on recovery; no prior held offer is gated this way.
    // Cacheable stores may become irrevocable on the same edge that every
    // older owner retires. Never anticipate an unresolved retirement or an
    // IRQ/recovery boundary. MMIO keeps the original registered-head rule.
    // Keep this gate separate from the raw current-head IRQ deferral above:
    // prospective head ownership must never defer a pending interrupt.
    wire [3:0] retiring_head=rob_head+{3'b0,retire0}+{3'b0,retire1};
    wire store_head_lookahead=ENABLE_STORE_HEAD_LOOKAHEAD&&retire0&&!recovery&&!interrupt_pending;
    wire candidate_store_lookahead=store_head_lookahead&&candidate_store&&!candidate_peripheral&&
        candidate_tag==retiring_head;
    wire prepared_store_lookahead=store_head_lookahead&&lsu_state==L_PREPARED&&!lsu_irrevocable&&
        lsu_store&&!peripheral_address(lsu_address)&&lsu_tag==retiring_head;
    wire direct_request=!reset&&candidate_valid&&active_room&&
                        (candidate_side_effect?((!active_reserved&&candidate_tag==rob_head)||candidate_store_lookahead):
                                               (!active_reserved||!recovery));
    wire active_handoff=candidate_valid&&active_room&&(!recovery||direct_request);
`ifdef VERILATOR
    reg [172:0] prior_active_payload;
    always @(posedge clk)begin
        if(reset)prior_active_payload<=0;
        else begin
            if((lsu_active||lsu_irrevocable)&&
               {lsu_tag,lsu_writes,lsu_sequence,lsu_pc,lsu_address,lsu_size,lsu_store,lsu_unsigned,lsu_wdata,lsu_strobes}!=prior_active_payload)
                $fatal(1,"R42 owned LSU payload differs from original handoff-only capture");
            if(active_handoff)prior_active_payload<=
                {candidate_tag,candidate_writes,candidate_sequence,candidate_pc,candidate_address,candidate_size,candidate_store,candidate_unsigned,candidate_wdata,candidate_strobes};
        end
    end
`endif
    assign dmem_request_valid=!reset&&(lsu_state==L_OFFER||direct_request||prepared_side_effect||prepared_store_lookahead);
    // IDLE and WAIT may present a new direct candidate; PREPARED/OFFER
    // retain the stored old bus owner. Invalid-cycle address is a private
    // proposal and need not wait for faults, recovery or turnover eligibility.
    wire direct_address_proposal=lsu_state==L_IDLE||lsu_state==L_WAIT;
    assign dmem_request_address=direct_address_proposal?candidate_address:lsu_address;
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&dmem_request_valid&&
        dmem_request_address!=(direct_request?candidate_address:lsu_address))
        $fatal(1,"R29 presented data address differs from original owned offer");
`endif
    assign dmem_request_write=direct_address_proposal?candidate_store:lsu_store;
    assign dmem_request_size=direct_address_proposal?candidate_size:lsu_size;
    assign dmem_request_wdata=direct_address_proposal?candidate_wdata:lsu_wdata;
    assign dmem_request_wstrb=direct_address_proposal?candidate_strobes:lsu_strobes;
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&dmem_request_valid&&
        {dmem_request_write,dmem_request_size,dmem_request_wdata,dmem_request_wstrb}!=
        {direct_request?candidate_store:lsu_store,direct_request?candidate_size:lsu_size,
         direct_request?candidate_wdata:lsu_wdata,direct_request?candidate_strobes:lsu_strobes})
        $fatal(1,"R42 presented data payload differs from original owned offer");
`endif
    assign dmem_response_ready=!reset&&(lsu_state==L_OFFER||lsu_state==L_WAIT);
    wire lsu_response=dmem_response_ready&&dmem_response_valid&&
                      (lsu_state==L_WAIT||dmem_request_ready);
    wire [31:0] lsu_shifted=dmem_response_rdata >> {lsu_address[1:0],3'b0};
    wire [31:0] lsu_result=(lsu_size==0)?(lsu_unsigned?{24'b0,lsu_shifted[7:0]}:{{24{lsu_shifted[7]}},lsu_shifted[7:0]}):
                           (lsu_size==1)?(lsu_unsigned?{16'b0,lsu_shifted[15:0]}:{{16{lsu_shifted[15]}},lsu_shifted[15:0]}):lsu_shifted;
    function peripheral_address;
        input [31:0] address;
        begin peripheral_address=(address>=32'h30000000&&address<=32'h7fffffff)||
                                  (address>=32'h80000000&&address<=32'h83ffffff);end
    endfunction

    reg mdu_active,mdu_writes; reg [3:0] mdu_tag; reg [63:0] mdu_sequence; reg [31:0] mdu_pc;
    wire mdu_response_present,mul_response_present;
    wire mdu_ready,mdu_response_valid; wire [31:0] mdu_result;
    wire ex_stream_mul=ENABLE_MUL_STREAM&&e_arithmetic0&&e_arithmetic_operation0==0;
    wire mul_request_ready,mul_unit_request_ready,mul_response_valid,mul_response_ready;
    wire [31:0] mul_result; wire [4:0] mul_response_identity; wire [1:0] mul_occupancy;
    wire [3:0] mul_response_tag=mul_response_identity[3:0];
    wire mul_response_writes=mul_response_identity[4];
    // MDU instruction faults depend on registered instruction/PC metadata;
    // operand-dependent branch/alignment faults cannot apply to this class.
    wire mdu_static_fault=ex_control_meta0[5];
    wire mul_ex_reserved=ex_valid0&&ex_stream_mul&&!mdu_static_fault;
    // Full occupancy waits for a registered release; the response-ready /
    // recovery cone never controls the next issue packet. Held EX is not sent.
    wire mul_issue_space=mul_occupancy!=2;
    assign mul_request_ready=mul_issue_space&&mul_unit_request_ready;
    wire ex_hold=mul_ex_reserved&&!mul_issue_space;
    wire mul_request=mul_ex_reserved&&!recovery&&!reset;
    wire mdu_request=ex_valid0&&e_arithmetic0&&!ex_stream_mul&&!mdu_static_fault&&!recovery&&!reset;
    // Response arbitration depends only on registered owners and existing
    // completion availability, never new issue or input acceptance.
    wire select_stream_result=mul_response_valid&&
        (!(mdu_active&&mdu_response_valid)||age(mul_response_tag)<age(mdu_tag));
    wire arithmetic_response_space=!reset&&!recovery&&
        (!(lsu_response&&!lsu_killed)||(ENABLE_MDU_SPILL&&!ex_valid1));
    wire mdu_response_ready=arithmetic_response_space&&!select_stream_result;
    assign mul_response_ready=arithmetic_response_space&&select_stream_result;
    wire complete_legacy=mdu_active&&mdu_response_valid&&mdu_response_ready;
    wire complete_stream=mul_response_valid&&mul_response_ready;
    wire [3:0] arithmetic_tag=select_stream_result?mul_response_tag:mdu_tag;
    wire arithmetic_writes=select_stream_result?mul_response_writes:mdu_writes;
    wire [31:0] arithmetic_value=select_stream_result?mul_result:mdu_result;
    wire [63:0] arithmetic_sequence=select_stream_result?rob_sequence[mul_response_tag]:mdu_sequence;
    wire [31:0] arithmetic_pc=select_stream_result?read_rob_pc(mul_response_tag):mdu_pc;
    rv32_mul_stream #(.TOKEN_WIDTH(5),.REGISTERED_INPUT_CREDIT(1)) low_multiplier(.clk(clk),.reset(reset),.cancel(recovery),
        .request_valid(mul_request&&mul_issue_space),.request_ready(mul_unit_request_ready),
        .left(ex_left0),.right(ex_right0),.request_token({ex_writes0,ex_tag0}),
        .response_valid(mul_response_valid),.response_present(mul_response_present),.response_ready(mul_response_ready),
        .result(mul_result),.response_token(mul_response_identity),.occupancy(mul_occupancy));
    rv32_arithmetic arithmetic_unit(.clk(clk),.reset(reset),.cancel(recovery),
        .request_valid(mdu_request),.request_ready(mdu_ready),.operation(e_arithmetic_operation0),
        .left(ex_left0),.right(ex_right0),.response_valid(mdu_response_valid),.response_present(mdu_response_present),
        .response_ready(mdu_response_ready),.result(mdu_result));

    // Faults are recorded in order-independent result slots, then handled at head.
    reg fault0,fault1; reg [31:0] fault_cause0,fault_cause1,fault_value0,fault_value1;
    always @* begin
        fault0=0;fault_cause0=0;fault_value0=0;
        if(ex_pc0[1:0]!=0)begin fault0=1;fault_cause0=0;fault_value0=ex_pc0;end
        else if(rob_fetch_error[ex_tag0]||(ex_pc0[31:28]!=1&&ex_pc0[31:28]!=8))begin fault0=1;fault_cause0=1;fault_value0=ex_pc0;end
        else if(e_illegal0||ex_csr_access_fault0)begin fault0=1;fault_cause0=2;fault_value0=ex_instruction0;end
        else if(e_control0&&e_next0[1:0]!=0)begin fault0=1;fault_cause0=0;fault_value0=e_next0;end
        else if(e_memory0&&((e_size0==2&&e_address0[1:0]!=0)||(e_size0==1&&e_address0[0])))begin fault0=1;fault_cause0=e_store_enable0?6:4;fault_value0=e_address0;end
        else if(e_system0==3||e_system0==4)begin fault0=1;fault_cause0=e_system0==3?11:3;fault_value0=e_system0==4?ex_pc0:0;end
        fault1=0;fault_cause1=0;fault_value1=0;
        if(ex_pc1[1:0]!=0)begin fault1=1;fault_cause1=0;fault_value1=ex_pc1;end
        else if(rob_fetch_error[ex_tag1]||(ex_pc1[31:28]!=1&&ex_pc1[31:28]!=8))begin fault1=1;fault_cause1=1;fault_value1=ex_pc1;end
        else if(e_illegal1)begin fault1=1;fault_cause1=2;fault_value1=ex_instruction1;end
        else if(e_control1&&e_next1[1:0]!=0)begin fault1=1;fault_cause1=0;fault_value1=e_next1;end
    end

    function ordinary_integer_class;
        input [31:0] instruction;
        begin ordinary_integer_class=instruction[6:0]==7'b0110111||instruction[6:0]==7'b0010111||
            instruction[6:0]==7'b0010011||
            (instruction[6:0]==7'b0110011&&instruction[31:25]!=7'b0000001);end
    endfunction
    // A legal ready control operation may use an otherwise idle EX input.
    // It still owns its ROB slot and uses ordinary precise branch retirement;
    // unlike arithmetic, it is NOT eligible for current-successor retirement.
    function dispatch_integer_class;
        input [31:0] instruction;
        begin dispatch_integer_class=ordinary_integer_class(instruction)||
            (ENABLE_CONTROL_DISPATCH&&(instruction[6:0]==7'b1100011||
             instruction[6:0]==7'b1100111||instruction[6:0]==7'b1101111));end
    endfunction
    // Instruction/PC fault facts never depend on the general branch-result
    // mux. Ordinary integers can use allocation's registered prediction bit.
    wire ex_static_fault1=ex_control_meta1[5];
    wire [1:0] jalr_low0=ex_left0[1:0]+ex_instruction0[21:20];
    wire [1:0] jalr_low1=ex_left1[1:0]+ex_instruction1[21:20];
    wire integer_fault0=mdu_static_fault||ex_csr_access_fault0||
        ex_control_meta0[3]||(ex_control_meta0[4]&&jalr_low0[1]);
    wire integer_fault1=ex_static_fault1||
        ex_control_meta1[3]||(ex_control_meta1[4]&&jalr_low1[1]);
    wire current_second0=ENABLE_CURRENT_INTEGER_PAIR&&!reset&&!interrupt_pending&&rob_count>1&&!rob_done[head1]&&
        ex_valid0&&ex_tag0==head1&&!mdu_static_fault&&ex_control_meta0[2]&&
        !rob_prediction_miss[head1];
    wire current_second1=ENABLE_CURRENT_INTEGER_PAIR&&!reset&&!interrupt_pending&&rob_count>1&&!rob_done[head1]&&
        ex_valid1&&ex_tag1==head1&&!ex_static_fault1&&ex_control_meta1[2]&&
        !rob_prediction_miss[head1];
    wire current_second_integer=current_second0||current_second1;
    wire [31:0] second_retire_value=current_second0?e_value0:(current_second1?e_value1:read_result(head1));

    wire complete0=!reset&&!recovery&&ex_valid0&&(fault0||(!e_memory0&&!e_arithmetic0));
    wire complete_integer1=!reset&&!recovery&&ex_valid1;
    // Raw head-response eligibility is independent of recovery/complete gating.
    // The response may complete and retire together after all priority checks.
    wire head_response=!reset&&lsu_response&&!lsu_killed&&rob_count!=0&&lsu_tag==rob_head;
    wire head_response_success=head_response&&!dmem_response_error;
    wire [31:0] head_retire_value=head_response_success?lsu_result:read_result(rob_head);
    wire complete_memory=!reset&&lsu_response&&!lsu_killed&&
                         (!recovery||(head_response&&(retire0||dmem_response_error)));
    wire complete_mdu=complete_legacy||complete_stream;
    // Reuse the existing idle integer result channel; never a fourth write port.
    wire spill_mdu=ENABLE_MDU_SPILL&&complete_mdu&&complete_memory;
    wire complete1=complete_integer1||spill_mdu;
    wire [3:0] complete_tag1=spill_mdu?arithmetic_tag:ex_tag1;
    wire [63:0] complete_sequence1=spill_mdu?arithmetic_sequence:ex_sequence1;
    wire [31:0] complete_pc1=spill_mdu?arithmetic_pc:ex_pc1;
    wire [31:0] complete_value1=spill_mdu?arithmetic_value:e_value1;
    wire complete_fault1=!spill_mdu&&fault1;
    wire complete_writes1=spill_mdu?arithmetic_writes:ex_writes1;
    wire complete2=complete_memory||(complete_mdu&&!spill_mdu);
    wire [3:0] complete_tag2=complete_memory?lsu_tag:arithmetic_tag;
    wire [63:0] complete_sequence2=complete_memory?lsu_sequence:arithmetic_sequence;
    wire [31:0] complete_pc2=complete_memory?lsu_pc:arithmetic_pc;
    wire [31:0] complete_value2=complete_memory?lsu_result:arithmetic_value;
    wire complete_fault2=complete_memory&&dmem_response_error;
    wire complete_writes2=complete_memory?lsu_writes:arithmetic_writes;
    // Default completion packets are self-contained. The alternative is an
    // explicit diagnostic control retaining the pre-boundary ROB lookup.
    wire broadcast0=complete0&&!fault0&&(CARRIED_COMPLETION_WRITES?ex_writes0:
        (rob_writes[ex_tag0]&&rob_destination[ex_tag0]!=0));
    wire broadcast1=complete1&&!complete_fault1&&(CARRIED_COMPLETION_WRITES?complete_writes1:
        (rob_writes[complete_tag1]&&rob_destination[complete_tag1]!=0));
    wire broadcast2=complete2&&!complete_fault2&&(CARRIED_COMPLETION_WRITES?complete_writes2:
        (rob_writes[complete_tag2]&&rob_destination[complete_tag2]!=0));
    // Raw wakeup payloads equal actual completions whenever recovery is
    // false. Recovery cancels queue/EX/rename ownership atomically; it need
    // not feed every data mux and readiness/ranking proposal on that edge.
    wire raw_memory=!reset&&lsu_response&&!lsu_killed;
    wire raw_select_stream=mul_response_present&&
        (!(mdu_active&&mdu_response_present)||age(mul_response_tag)<age(mdu_tag));
    wire raw_arithmetic_space=!raw_memory||(ENABLE_MDU_SPILL&&!ex_valid1);
    wire raw_arithmetic=!reset&&raw_arithmetic_space&&
        (mul_response_present||(mdu_active&&mdu_response_present));
    wire raw_spill=ENABLE_MDU_SPILL&&raw_arithmetic&&raw_memory;
    wire [3:0] raw_arithmetic_tag=raw_select_stream?mul_response_tag:mdu_tag;
    wire raw_arithmetic_writes=raw_select_stream?mul_response_writes:mdu_writes;
    wire [31:0] raw_arithmetic_value=raw_select_stream?mul_result:mdu_result;
    wire [3:0] wake_tag1=raw_spill?raw_arithmetic_tag:ex_tag1;
    wire [3:0] wake_tag2=raw_memory?lsu_tag:raw_arithmetic_tag;
    wire [31:0] wake_value1=raw_spill?raw_arithmetic_value:e_value1;
    wire [31:0] wake_value2=raw_memory?lsu_result:raw_arithmetic_value;
    wire wake0=!reset&&ex_valid0&&!e_memory0&&!e_arithmetic0&&!integer_fault0&&
        (CARRIED_COMPLETION_WRITES?ex_writes0:(rob_writes[ex_tag0]&&rob_destination[ex_tag0]!=0));
    wire wake1=!reset&&(raw_spill||(ex_valid1&&!e_memory1&&!e_arithmetic1&&!integer_fault1))&&
        (CARRIED_COMPLETION_WRITES?(raw_spill?raw_arithmetic_writes:ex_writes1):
            (rob_writes[wake_tag1]&&rob_destination[wake_tag1]!=0));
    wire wake2=!reset&&(raw_memory?!dmem_response_error:raw_arithmetic)&&
        (CARRIED_COMPLETION_WRITES?(raw_memory?lsu_writes:raw_arithmetic_writes):
            (rob_writes[wake_tag2]&&rob_destination[wake_tag2]!=0));
    // R51: compute each response case without using cache hit/response
    // validity in either tag mux or wakeup/ranking cone. The final one-bit
    // select uses raw_memory; actual broadcasts still own every captured value.
    wire early_integer1_wake=!reset&&ex_valid1&&!e_memory1&&!e_arithmetic1&&!integer_fault1&&
        (CARRIED_COMPLETION_WRITES?ex_writes1:(rob_writes[ex_tag1]&&rob_destination[ex_tag1]!=0));
    wire early_memory_wake=!reset&&!dmem_response_error&&
        (CARRIED_COMPLETION_WRITES?lsu_writes:(rob_writes[lsu_tag]&&rob_destination[lsu_tag]!=0));
    // Experiment: only the ordered scheduler defers arithmetic dependencies
    // until queue operand capture. Neither counterfactual may bypass a MUL/
    // legacy-MDU result, including a result spilled onto completion lane 1.
    wire [2:0] no_response_wake={1'b0,early_integer1_wake,wake0};
    wire [11:0] no_response_tags={4'b0,ex_tag1,ex_tag0};
    wire [2:0] with_response_wake={early_memory_wake,early_integer1_wake,wake0};
    wire [11:0] with_response_tags={lsu_tag,ex_tag1,ex_tag0};
    // Keep the actual eligibility check and selected operand data aligned
    // with those counterfactuals. Lane 1 is integer-only; lane 2 is LSU-only.
    wire [2:0] ordered_broadcast_valid={raw_memory&&early_memory_wake,early_integer1_wake,wake0};
    wire [11:0] ordered_broadcast_tags={lsu_tag,ex_tag1,ex_tag0};
    wire [95:0] ordered_broadcast_values={lsu_result,e_value1,e_value0};
    // Full broadcasts remain unchanged for immediate queue/allocation
    // capture and for both diagnostic nonordered scheduler implementations.
    wire [2:0] queue_broadcast_valid={wake2,wake1,wake0};
    wire [11:0] queue_broadcast_tags={wake_tag2,wake_tag1,ex_tag0};
    wire [95:0] queue_broadcast_values={wake_value2,wake_value1,e_value0};
    function broadcast_available;
        input [3:0] tag;
        begin broadcast_available=(queue_broadcast_valid[0]&&queue_broadcast_tags[3:0]==tag)||
            (queue_broadcast_valid[1]&&queue_broadcast_tags[7:4]==tag)||
            (queue_broadcast_valid[2]&&queue_broadcast_tags[11:8]==tag);end
    endfunction
    function [31:0] broadcast_value;
        input [3:0] tag;
        begin broadcast_value=0;
            if(queue_broadcast_valid[0]&&queue_broadcast_tags[3:0]==tag)broadcast_value=queue_broadcast_values[31:0];
            if(queue_broadcast_valid[1]&&queue_broadcast_tags[7:4]==tag)broadcast_value=queue_broadcast_values[63:32];
            if(queue_broadcast_valid[2]&&queue_broadcast_tags[11:8]==tag)broadcast_value=queue_broadcast_values[95:64];
        end
    endfunction
    function producer_available;
        input [3:0] tag;
        begin producer_available=(rob_done[tag]&&!rob_fault[tag])||broadcast_available(tag);end
    endfunction
    function [31:0] producer_value;
        input [3:0] tag;
        begin producer_value=broadcast_available(tag)?broadcast_value(tag):read_result(tag);end
    endfunction
    function [3:0] age;
        input [3:0] tag;
        begin age=tag-rob_head;end
    endfunction
    // A grant-plus-response for a held OFFER still belongs to that old offer.
    // Fast handoff is restricted to WAIT, so its ready cannot accept a new owner.
    wire lsu_turnover=lsu_state==L_WAIT&&lsu_response&&!lsu_killed&&!dmem_response_error&&
                      (!lsu_irrevocable||(retire0&&lsu_tag==rob_head)||(retire1&&lsu_tag==head1));
    wire active_retiring=(retire0&&lsu_tag==rob_head)||(retire1&&lsu_tag==head1);
    wire active_release=(lsu_response&&(!lsu_irrevocable||active_retiring||trap_enter))||
                        (!lsu_active&&lsu_irrevocable&&active_retiring);
    wire memory_issue_credit=issue_memory_reservations<MEMORY_CREDITS;
    // Static ownership/order matrix: no function-local loop variables in the
    // synthesized memory-order cone. Killed owners cannot exempt reused tags.
    wire [15:0] memory_blocker,memory_order_blocker;
    wire [3:0] entering_load_tag=issue_tag_value(issue_choice0>=0?issue_choice0:0);
    wire entering_memory=issue_choice0>=0&&q_memory[issue_choice0>=0?issue_choice0:0]&&
        !q_error[issue_choice0>=0?issue_choice0:0];
    wire entering_load=entering_memory&&!rob_store[entering_load_tag];
    // A surviving selected load is registered in EX before a younger issue.
    // Its eventual local fault still completes precisely and kills younger
    // work. Stores retain the exact pre-existing, nonfaulting-owner rule.
    // Only this admission register sees the issue proposal; no data-result or
    // current-response path is restored into the age matrix/scheduler.
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&!recovery&&entering_load)begin
        if(!rob_valid[entering_load_tag]||!rob_memory[entering_load_tag]||rob_store[entering_load_tag])
            $fatal(1,"R19 load admission proposal lacks exact live load identity");
    end
`endif
    wire [11:0] older_memory_waiting;
    reg [11:0] memory_order_clear;
    integer order_index;
    always @(posedge clk)begin
        if(reset||recovery)memory_order_clear<=0;
        else for(order_index=0;order_index<12;order_index=order_index+1)begin
            // Every pre-edge valid ROB owner precedes a new tail allocation.
            // A second memory allocation also waits for the first allocation.
            // Selected registered address credits remain independently enforced.
            if(allocation_offer_count!=0&&allocation_slot0==order_index)
                memory_order_clear[order_index]<=!(|memory_order_blocker);
            else if(allocation_offer_count==2&&allocation_slot1==order_index)
                memory_order_clear[order_index]<=!(|memory_order_blocker)&&!d_mem0;
            else memory_order_clear[order_index]<=q_valid[order_index]&&!older_memory_waiting[order_index];
        end
    end
    genvar mr,mq,load_queue;
    generate for(mr=0;mr<16;mr=mr+1)begin:memory_order_rows
        wire owned=(lsu_active&&!lsu_killed&&lsu_tag==mr)||
                   (prepared_valid&&prepared_tag==mr)||
                   (prepared_second_valid&&prepared_second_tag==mr)||
                   (ex_memory_order_owner&&ex_tag0==mr);
        assign memory_blocker[mr]=rob_valid[mr]&&rob_memory[mr]&&
            ((!rob_done[mr]&&!owned)||(rob_store[mr]&&!(ENABLE_ORDERED_STORE_PREP&&owned)));
        // Decode each queued owner before the late grant. Avoid grant ->
        // encoded queue -> tag mux -> tag equality on the order-credit edge.
        wire [11:0] selected_load_owner;
        for(load_queue=0;load_queue<12;load_queue=load_queue+1)begin:load_owner
            assign selected_load_owner[load_queue]=ordered_mask0[load_queue]&&q_memory[load_queue]&&
                !q_error[load_queue]&&q_tag[load_queue]==mr;
        end
        wire selected_memory=ORDERED_SCHEDULER?(|selected_load_owner):
            (entering_memory&&entering_load_tag==mr);
        wire selected_load=selected_memory&&!rob_store[mr];
        // This only forwards next-cycle address-preparation order. A selected
        // store enters registered EX before a younger issue. A local EX fault
        // completes precisely and younger prepared stores remain unable to
        // present any side effect across that older nonretiring fault.
        // The existing memory credits, prepared FIFO, and actual bus-head gate
        // are unchanged; this grants neither memory access nor retirement.
        wire selected_store=selected_memory&&rob_store[mr];
`ifdef VERILATOR
        reg selected_store_prior;
        reg [63:0] selected_store_sequence_prior;
        reg [31:0] selected_store_pc_prior;
        always @(posedge clk) begin
            if(reset)selected_store_prior<=0;
            else begin
                if(selected_store_prior&&(!ex_valid0||ex_tag0!=mr||
                   ex_sequence0!=selected_store_sequence_prior||ex_pc0!=selected_store_pc_prior))
                    $fatal(1,"Selected-store order lookahead lost exact next-cycle EX owner");
                selected_store_prior<=ENABLE_ORDERED_STORE_PREP&&ENABLE_STORE_ISSUE_LOOKAHEAD&&!recovery&&selected_store;
                if(ENABLE_ORDERED_STORE_PREP&&ENABLE_STORE_ISSUE_LOOKAHEAD&&!recovery&&selected_store)begin
                    if(!rob_valid[mr]||!rob_memory[mr])
                        $fatal(1,"Selected-store order lookahead lacks exact live memory owner");
                    selected_store_sequence_prior<=rob_sequence[mr];
                    selected_store_pc_prior<=read_rob_pc(mr);
                end
            end
        end
`endif
        assign memory_order_blocker[mr]=memory_blocker[mr]&&
            !(LOAD_ORDER_ISSUE_LOOKAHEAD&&selected_load)&&
            !(ENABLE_ORDERED_STORE_PREP&&ENABLE_STORE_ISSUE_LOOKAHEAD&&selected_store);
    end
    for(mq=0;mq<12;mq=mq+1)begin:memory_order_columns
        wire [15:0] blocks;
        for(mr=0;mr<16;mr=mr+1)begin:compare_age
            wire [3:0] row_age=mr-rob_head;
            wire [3:0] query_age=q_tag[mq]-rob_head;
            assign blocks[mr]=memory_order_blocker[mr]&&(row_age<query_age);
        end
        assign older_memory_waiting[mq]=|blocks;
    end endgenerate

    // Ordinary retirement uses registered completions. A successful current
    // LSU head response may retire with explicit value forwarding; a successor
    // may pair when registered complete, or as the narrowly qualified current
    // ordinary-integer successor. Slot0 completion rules remain unchanged.
    always @* begin
        retire0=0;retire1=0;registered_pair_retire=0;recovery=0;recovery_address=architectural_pc;
        trap_enter=0;return_from_trap=0;maintain_i=0;maintain_d=0;
        trap_pc=architectural_pc;trap_cause=0;trap_value=0;recovery_first=next_sequence;
        if(!reset)begin
            if(rob_count!=0&&rob_done[rob_head]&&rob_fault[rob_head])begin
                trap_enter=1;trap_pc=read_rob_pc(rob_head);trap_cause=rob_cause[rob_head];trap_value=read_rob_tval(rob_head);recovery_first=rob_sequence[rob_head];
            end else if(head_response&&dmem_response_error)begin
                trap_enter=1;trap_pc=read_rob_pc(rob_head);trap_cause=lsu_store?7:5;trap_value=lsu_address;recovery_first=rob_sequence[rob_head];
            end else if(interrupt_pending&&!lsu_irrevocable&&!ex_head_side_effect&&!prepared_side_effect)begin
                trap_enter=1;trap_pc=rob_count!=0?read_rob_pc(rob_head):architectural_pc;
                trap_cause=interrupt_cause;recovery_first=rob_count!=0?rob_sequence[rob_head]:next_sequence;
            end else if(rob_count!=0&&(rob_done[rob_head]||head_response_success)&&
                (predictor_training_ready||!rob_conditional[rob_head]))begin
                retire0=1;
                if(rob_system[rob_head]==2)begin
                    return_from_trap=1;recovery=1;recovery_address=csr_exception_pc;recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_system[rob_head]==1||rob_system[rob_head]==6)begin
                    maintain_i=1;maintain_d=rob_system[rob_head]==6;recovery=1;recovery_address=retirement_next0;recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_prediction_miss[rob_head])begin
                    recovery=1;recovery_address=retirement_next0;recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(ENABLE_PAIRING&&!rob_serial[rob_head]&&rob_count>1&&!rob_fault[head1]&&!rob_serial[head1])begin
                    // Only a registered completed successor can mispredict.
                    // Current ordinary integer pairing explicitly requires a
                    // correct registered prediction. Keep its legality cone
                    // out of recovery-address selection instead of relying on
                    // cross-condition boolean simplification by the compiler.
                    if(rob_done[head1]&&(predictor_training_ready||!rob_conditional[head1]))begin
                        retire1=1;registered_pair_retire=1;
                        if(rob_prediction_miss[head1])begin recovery=1;recovery_address=retirement_next1;recovery_first=rob_sequence[head1]+64'd1;end
                    end else if(current_second_integer)retire1=1;
                end
            end
            // A pending IRQ cannot be deferred by an endless succession of
            // new head side effects. Finish the current irrevocable owner and
            // any legal completed successor, then trap at that exact boundary.
            if(interrupt_pending&&lsu_irrevocable&&((retire0&&lsu_tag==rob_head)||(registered_pair_retire&&lsu_tag==head1)))begin
                trap_enter=1;trap_cause=interrupt_cause;trap_value=0;
                trap_pc=registered_pair_retire?retirement_next1:retirement_next0;
                recovery_first=(registered_pair_retire?rob_sequence[head1]:rob_sequence[rob_head])+64'd1;
            end
            if(trap_enter)begin recovery=1;recovery_address={csr_vector[31:2],2'b0};end
        end
    end
`ifdef VERILATOR
    reg prior_retire0,prior_retire1,prior_recovery,prior_trap_enter,prior_return_from_trap,prior_maintain_i,prior_maintain_d;
    reg [31:0] prior_recovery_address,prior_trap_pc,prior_trap_cause,prior_trap_value;
    reg [63:0] prior_recovery_first;
    always @* begin
        prior_retire0=0;prior_retire1=0;prior_recovery=0;prior_recovery_address=architectural_pc;
        prior_trap_enter=0;prior_return_from_trap=0;prior_maintain_i=0;prior_maintain_d=0;
        prior_trap_pc=architectural_pc;prior_trap_cause=0;prior_trap_value=0;prior_recovery_first=next_sequence;
        if(!reset)begin
            if(rob_count!=0&&rob_done[rob_head]&&rob_fault[rob_head])begin
                prior_trap_enter=1;prior_trap_pc=read_rob_pc(rob_head);prior_trap_cause=rob_cause[rob_head];prior_trap_value=read_rob_tval(rob_head);prior_recovery_first=rob_sequence[rob_head];
            end else if(head_response&&dmem_response_error)begin
                prior_trap_enter=1;prior_trap_pc=read_rob_pc(rob_head);prior_trap_cause=lsu_store?7:5;prior_trap_value=lsu_address;prior_recovery_first=rob_sequence[rob_head];
            end else if(interrupt_pending&&!lsu_irrevocable&&!ex_head_side_effect&&!prepared_side_effect)begin
                prior_trap_enter=1;prior_trap_pc=rob_count!=0?read_rob_pc(rob_head):architectural_pc;
                prior_trap_cause=interrupt_cause;prior_recovery_first=rob_count!=0?rob_sequence[rob_head]:next_sequence;
            end else if(rob_count!=0&&(rob_done[rob_head]||head_response_success)&&
                (predictor_training_ready||!rob_conditional[rob_head]))begin
                prior_retire0=1;
                if(rob_system[rob_head]==2)begin
                    prior_return_from_trap=1;prior_recovery=1;prior_recovery_address=csr_exception_pc;prior_recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_system[rob_head]==1||rob_system[rob_head]==6)begin
                    prior_maintain_i=1;prior_maintain_d=rob_system[rob_head]==6;prior_recovery=1;prior_recovery_address=read_rob_next(rob_head);prior_recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(rob_prediction_miss[rob_head])begin
                    prior_recovery=1;prior_recovery_address=read_rob_next(rob_head);prior_recovery_first=rob_sequence[rob_head]+64'd1;
                end else if(ENABLE_PAIRING&&!rob_serial[rob_head]&&rob_count>1&&(predictor_training_ready||!rob_conditional[head1])&&(rob_done[head1]||current_second_integer)&&!rob_fault[head1]&&!rob_serial[head1])begin
                    prior_retire1=1;
                    if(rob_prediction_miss[head1])begin prior_recovery=1;prior_recovery_address=read_rob_next(head1);prior_recovery_first=rob_sequence[head1]+64'd1;end
                end
            end
            // A pending IRQ cannot be deferred by an endless succession of
            // new head side effects. Finish the current irrevocable owner and
            // any legal completed successor, then trap at that exact boundary.
            if(interrupt_pending&&lsu_irrevocable&&((prior_retire0&&lsu_tag==rob_head)||(prior_retire1&&lsu_tag==head1)))begin
                prior_trap_enter=1;prior_trap_cause=interrupt_cause;prior_trap_value=0;
                prior_trap_pc=prior_retire1?read_rob_next(head1):read_rob_next(rob_head);
                prior_recovery_first=(prior_retire1?rob_sequence[head1]:rob_sequence[rob_head])+64'd1;
            end
            if(prior_trap_enter)begin prior_recovery=1;prior_recovery_address={csr_vector[31:2],2'b0};end
        end
    end
    always @(posedge clk)if(!reset)begin
        if(interrupt_pending&&retire1!=registered_pair_retire)$fatal(1,"R29 current pairing survived pending interrupt");
        if(retire0!=prior_retire0||
           retire1!=prior_retire1||
           recovery!=prior_recovery||
           recovery_address!=prior_recovery_address||
           trap_enter!=prior_trap_enter||
           return_from_trap!=prior_return_from_trap||
           maintain_i!=prior_maintain_i||
           maintain_d!=prior_maintain_d||
           trap_pc!=prior_trap_pc||
           trap_cause!=prior_trap_cause||
           trap_value!=prior_trap_value||
           recovery_first!=prior_recovery_first)
            $fatal(1,"R29 retirement/recovery differs from prior decision");
    end
`endif
    wire [7:0] committed_history_after0=(retire0&&rob_conditional[rob_head])?
        {predictor_committed_history[6:0],(rob_taken[rob_head]&&!rob_history_sequential[rob_head])}:predictor_committed_history;
    wire [7:0] committed_history_after1=(retire1&&rob_conditional[head1])?
        {committed_history_after0[6:0],(rob_taken[head1]&&!rob_history_sequential[head1])}:committed_history_after0;
    wire recovery_second=registered_pair_retire&&rob_prediction_miss[head1];
    wire [7:0] recovery_checkpoint=recovery_second?read_recovery_context(head1):read_recovery_context(rob_head);
    wire recovery_is_conditional=recovery_second?rob_conditional[head1]:rob_conditional[rob_head];
    wire recovery_actual_taken=recovery_second?(rob_taken[head1]&&!rob_history_sequential[head1]):(rob_taken[rob_head]&&!rob_history_sequential[rob_head]);
    wire [7:0] recovered_branch_history=recovery_is_conditional?
        {recovery_checkpoint[6:0],recovery_actual_taken}:recovery_checkpoint;
    assign recovery_history=(trap_enter||return_from_trap||maintain_i||maintain_d)?
        committed_history_after1:recovered_branch_history;
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&recovery&&!(trap_enter||return_from_trap||maintain_i||maintain_d))begin
        if(recovery_history!=committed_history_after1)
            $fatal(1,"R49 speculative checkpoint recovery differs from actual committed conditional history");
    end
`endif
    assign debug_redirect=recovery;
    assign debug_trap=trap_enter;
    assign d1_trap_cause=trap_cause;
    assign d1_trap_vector=recovery_address;
    // The exact next-PC/prediction comparison is already registered in the ROB.
    // Event counting must use that same retirement decision, without reading
    // compressed predecessor PCs and repeating the address arithmetic here.
    // Compute registered miss-kind and pairing eligibility in parallel with
    // the current LSU hit. A current ordinary integer cannot mispredict;
    // only a registered-complete successor contributes a slot1 miss event.
    // An IRQ taken after an irrevocable retirement still counts that retire.
    wire miss_event_admit=!reset&&rob_count!=0&&(predictor_training_ready||!rob_conditional[rob_head])&&
        !(rob_done[rob_head]&&rob_fault[rob_head])&&
        !(interrupt_pending&&!lsu_irrevocable&&!ex_head_side_effect&&!prepared_side_effect);
    wire miss_event_ready=(rob_done[rob_head]&&!(head_response&&dmem_response_error))||head_response_success;
    wire miss_event0=rob_control[rob_head]&&rob_prediction_miss[rob_head];
    wire miss_event1=ENABLE_PAIRING&&rob_count>1&&(predictor_training_ready||!rob_conditional[head1])&&
        rob_system[rob_head]!=2&&rob_system[rob_head]!=1&&rob_system[rob_head]!=6&&
        !rob_prediction_miss[rob_head]&&!rob_serial[rob_head]&&
        rob_done[head1]&&!rob_fault[head1]&&!rob_serial[head1]&&
        rob_control[head1]&&rob_prediction_miss[head1];
    assign debug_branch_miss=miss_event_admit&&miss_event_ready&&
        ((miss_event0&&rob_conditional[rob_head])||(miss_event1&&rob_conditional[head1]));
    assign debug_jump_miss=miss_event_admit&&miss_event_ready&&
        ((miss_event0&&!rob_conditional[rob_head])||(miss_event1&&!rob_conditional[head1]));
`ifdef VERILATOR
    wire prior_branch_miss=(train0&&rob_conditional[rob_head]&&rob_prediction_miss[rob_head])||
        (train1&&rob_conditional[head1]&&rob_prediction_miss[head1]);
    wire prior_jump_miss=(train0&&!rob_conditional[rob_head]&&rob_prediction_miss[rob_head])||
        (train1&&!rob_conditional[head1]&&rob_prediction_miss[head1]);
    always @(posedge clk)if(!reset)begin
        if(debug_branch_miss!=prior_branch_miss||debug_jump_miss!=prior_jump_miss)
            $fatal(1,"R36 miss events differ from original actual retirement/training");
        if(current_second_integer&&rob_prediction_miss[head1])
            $fatal(1,"R36 ordinary current second instruction can mispredict");
    end
`endif
`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(train0&&rob_prediction_miss[rob_head]!=(read_rob_next(rob_head)!=read_rob_prediction(rob_head)))
            $fatal(1,"R14 head prediction event mismatch");
        if(train1&&rob_prediction_miss[head1]!=(read_rob_next(head1)!=read_rob_prediction(head1)))
            $fatal(1,"R14 successor prediction event mismatch");
    end
`endif
    assign debug_dispatch_stall=!reset&&fetch_count!=0&&allocate_count==0;
    assign debug_frontend_stall=!reset&&fetch_count==0;
    assign debug_rob_count=rob_count;
    assign debug_lsu_active=lsu_active;
    assign debug_mdu_active=mdu_active;
    assign debug_irq_pending=ENABLE_TRACE&&interrupt_pending;
    assign debug_ex_valid=ENABLE_TRACE?{ex_valid1,ex_valid0}:2'b0;
    assign debug_ex_fault=ENABLE_TRACE?{fault1,fault0}:2'b0;
    assign debug_ex_tag0=ENABLE_TRACE?ex_tag0:4'b0;
    assign debug_ex_tag1=ENABLE_TRACE?ex_tag1:4'b0;
    assign debug_ex_sequence0=ENABLE_TRACE?ex_sequence0:64'b0;
    assign debug_ex_sequence1=ENABLE_TRACE?ex_sequence1:64'b0;
    assign debug_ex_pc0=ENABLE_TRACE?ex_pc0:32'b0;
    assign debug_ex_pc1=ENABLE_TRACE?ex_pc1:32'b0;
    assign debug_second_next=ENABLE_TRACE&&rob_count>1?read_rob_next(head1):32'b0;
    assign debug_second_prediction=ENABLE_TRACE&&rob_count>1?read_rob_prediction(head1):32'b0;
    assign debug_mdu_response_pending=ENABLE_TRACE&&((mdu_active&&mdu_response_valid)||mul_response_valid);
    assign debug_mdu_response_blocked=ENABLE_TRACE&&
        ((mdu_active&&mdu_response_valid&&!mdu_response_ready)||(mul_response_valid&&!mul_response_ready));
    assign debug_mul_request_valid=ENABLE_TRACE&&mul_request;
    assign debug_mul_request_ready=ENABLE_TRACE&&mul_request_ready;
    assign debug_mul_request_tag=ENABLE_TRACE?ex_tag0:4'b0;
    assign debug_mul_request_sequence=ENABLE_TRACE?ex_sequence0:64'b0;
    assign debug_mul_request_pc=ENABLE_TRACE?ex_pc0:32'b0;
    assign debug_mul_request_left=ENABLE_TRACE?ex_left0:32'b0;
    assign debug_mul_request_right=ENABLE_TRACE?ex_right0:32'b0;
    assign debug_mul_response_valid=ENABLE_TRACE&&mul_response_valid;
    assign debug_mul_response_ready=ENABLE_TRACE&&mul_response_ready;
    assign debug_mul_response_tag=ENABLE_TRACE?mul_response_tag:4'b0;
    assign debug_mul_response_sequence=ENABLE_TRACE?rob_sequence[mul_response_tag]:64'b0;
    assign debug_mul_response_pc=ENABLE_TRACE?read_rob_pc(mul_response_tag):32'b0;
    assign debug_mul_response_value=ENABLE_TRACE?mul_result:32'b0;
    assign debug_mul_occupancy=ENABLE_TRACE?mul_occupancy:2'b0;
    assign debug_mul_ex_valid=ENABLE_TRACE&&mul_ex_reserved;
    assign debug_mul_ex_hold=ENABLE_TRACE&&ex_hold;
    assign debug_mul_ex_tag=ENABLE_TRACE?ex_tag0:4'b0;
    assign debug_mul_ex_sequence=ENABLE_TRACE?ex_sequence0:64'b0;
    assign debug_mul_ex_pc=ENABLE_TRACE?ex_pc0:32'b0;
    assign debug_legacy_request_valid=ENABLE_TRACE&&mdu_request;
    assign debug_legacy_request_ready=ENABLE_TRACE&&mdu_ready;
    assign debug_legacy_request_tag=ENABLE_TRACE?ex_tag0:4'b0;
    assign debug_legacy_request_sequence=ENABLE_TRACE?ex_sequence0:64'b0;
    assign debug_legacy_request_pc=ENABLE_TRACE?ex_pc0:32'b0;
    assign debug_legacy_response_valid=ENABLE_TRACE&&mdu_active&&mdu_response_valid;
    assign debug_legacy_response_ready=ENABLE_TRACE&&mdu_response_ready;
    assign debug_legacy_response_tag=ENABLE_TRACE?mdu_tag:4'b0;
    assign debug_legacy_response_sequence=ENABLE_TRACE?mdu_sequence:64'b0;
    assign debug_legacy_response_pc=ENABLE_TRACE?mdu_pc:32'b0;
    assign debug_quarantine_active=lsu_active&&lsu_killed;
    assign debug_head_valid=rob_count!=0;
    assign debug_head_sequence=ENABLE_TRACE&&rob_count!=0?rob_sequence[rob_head]:0;
    assign debug_raw_retire_mask=ENABLE_TRACE?{retire1,retire0}:2'b0;
    assign debug_lsu_tag=direct_request?candidate_tag:lsu_tag;
    assign debug_lsu_sequence=ENABLE_TRACE?(direct_request?candidate_sequence:lsu_sequence):0;
    assign debug_lsu_pc=direct_request?candidate_pc:lsu_pc;
    assign debug_lsu_irrevocable=lsu_irrevocable||ex_head_side_effect||prepared_side_effect;
    assign debug_lsu_response_tag=ENABLE_TRACE?lsu_tag:4'b0;
    assign debug_lsu_response_sequence=ENABLE_TRACE?lsu_sequence:64'b0;
    assign debug_lsu_response_pc=ENABLE_TRACE?lsu_pc:32'b0;
    assign debug_lsu_reserved=ENABLE_TRACE&&active_reserved;
    assign debug_prepared_valid=ENABLE_TRACE&&prepared_valid;
    assign debug_prepared_tag=ENABLE_TRACE?prepared_tag:4'b0;
    assign debug_prepared_sequence=ENABLE_TRACE?prepared_sequence:64'b0;
    assign debug_prepared_pc=ENABLE_TRACE?prepared_pc:32'b0;
    assign debug_ex_memory_valid=ENABLE_TRACE&&ex_memory_reservation;
    assign debug_ex_memory_tag=ENABLE_TRACE?ex_tag0:4'b0;
    assign debug_ex_memory_sequence=ENABLE_TRACE?ex_sequence0:64'b0;
    assign debug_ex_memory_pc=ENABLE_TRACE?ex_pc0:32'b0;
    assign debug_memory_reservations=ENABLE_TRACE?memory_reservations:2'b0;
    assign debug_memory_credit_limit=MEMORY_CREDITS;
    assign debug_prepared_second_valid=ENABLE_TRACE&&prepared_second_valid;
    assign debug_prepared_second_tag=ENABLE_TRACE?prepared_second_tag:4'b0;
    assign debug_prepared_second_sequence=ENABLE_TRACE?prepared_second_sequence:64'b0;
    assign debug_prepared_second_pc=ENABLE_TRACE?prepared_second_pc:32'b0;
`ifdef VERILATOR
    initial if(MEMORY_CREDITS!=2&&MEMORY_CREDITS!=3)$fatal(1,"R17 unsupported memory credit policy");
    always @(posedge clk)if(!reset)begin
        if(memory_reservations_wide>MEMORY_CREDITS||issue_memory_reservations>MEMORY_CREDITS)
            $fatal(1,"R17 memory credit overflow");
        if(prepared_second_valid&&!prepared_valid)$fatal(1,"R17 prepared FIFO hole");
        if(!recovery&&ex_memory_reservation&&prepared_valid&&prepared_second_valid&&!active_handoff)
            $fatal(1,"R17 EX overwrites a full prepared FIFO");
    end
`endif

    reg [11:0] eligible;
    // Legacy arrays exist only in the diagnostic global-selector elaboration.
    reg [31:0] ready_left[0:11],ready_right[0:11];
    integer int_choice0,int_choice1,int_second0,int_second1,integer_first,integer_second;
    integer complex_choice,issue_choice0,issue_choice1;
    integer s;
    reg [3:0] integer_first_age,integer_second_age;
    reg [11:0] bank_issue_allowed;
    integer allow_index;
    always @* begin
        bank_issue_allowed=12'hfff;
        for(allow_index=8;allow_index<12;allow_index=allow_index+1)begin
            if(!q_error[allow_index])begin
                if(q_serial[allow_index])bank_issue_allowed[allow_index]=q_tag[allow_index]==rob_head;
                if(q_memory[allow_index])bank_issue_allowed[allow_index]=bank_issue_allowed[allow_index]&&
                    memory_issue_credit&&memory_order_clear[allow_index];
                if(q_arithmetic[allow_index]&&
                   !(ENABLE_MUL_STREAM&&q_multiply[allow_index]))
                    bank_issue_allowed[allow_index]=bank_issue_allowed[allow_index]&&
                    legacy_issue_credit;
            end
        end
    end
    wire [11:0] ordered_eligible,ordered_mask0,ordered_mask1;
    wire [11:0] no_response_mask0,no_response_mask1,with_response_mask0,with_response_mask1;
    wire ordered_valid0,ordered_valid1;
    wire [3:0] ordered_slot0,ordered_slot1;
    wire [31:0] ordered_left0,ordered_right0,ordered_left1,ordered_right1;
    wire [11:0] ordered_left_ready,ordered_right_ready,ordered_writes;
    wire [47:0] ordered_left_tags,ordered_right_tags;
    wire [383:0] ordered_left_values,ordered_right_values;
    genvar ordered_row;
    generate for(ordered_row=0;ordered_row<12;ordered_row=ordered_row+1)begin:ordered_payload
        assign ordered_left_ready[ordered_row]=q_left_ready[ordered_row];
        assign ordered_right_ready[ordered_row]=q_right_ready[ordered_row];
        assign ordered_writes[ordered_row]=q_writes[ordered_row];
        assign ordered_left_tags[ordered_row*4+:4]=q_left_tag[ordered_row];
        assign ordered_right_tags[ordered_row*4+:4]=q_right_tag[ordered_row];
        assign ordered_left_values[ordered_row*32+:32]=q_left[ordered_row];
        assign ordered_right_values[ordered_row*32+:32]=q_right[ordered_row];
    end
    if(ORDERED_SCHEDULER)begin:relative_order_scheduler
        rv32_issue_scheduler #(.FAST_WAKEUP(FAST_WAKEUP),.ENABLE_PAIRING(ENABLE_PAIRING),.LATE_SELECT(1)) scheduler(
            .clk(clk),.reset(reset),.allocation_count(allocation_offer_count),
            .allocation_slot0(allocation_slot0[3:0]),.allocation_slot1(allocation_slot1[3:0]),
            .occupied(allocation_occupied),.issue_allowed(bank_issue_allowed),
            .left_ready(ordered_left_ready),.right_ready(ordered_right_ready),
            .left_tags(ordered_left_tags),.right_tags(ordered_right_tags),
            .left_values(ordered_left_values),.right_values(ordered_right_values),
            .broadcast_valid(ordered_broadcast_valid),.broadcast_tags(ordered_broadcast_tags),.broadcast_values(ordered_broadcast_values),
            .late_select(raw_memory),.alternate_valid0(no_response_wake),.alternate_tags0(no_response_tags),
            .alternate_valid1(with_response_wake),.alternate_tags1(with_response_tags),
            .ex_hold(ex_hold),.eligible(ordered_eligible),.issue_mask0(ordered_mask0),.issue_mask1(ordered_mask1),
            .case0_mask0(no_response_mask0),.case0_mask1(no_response_mask1),
            .case1_mask0(with_response_mask0),.case1_mask1(with_response_mask1),
            .issue_valid0(ordered_valid0),.issue_valid1(ordered_valid1),.issue_slot0(ordered_slot0),.issue_slot1(ordered_slot1),
            .issue_left0(ordered_left0),.issue_right0(ordered_right0),.issue_left1(ordered_left1),.issue_right1(ordered_right1));
    end endgenerate
    // RV32: select already-read metadata after the cache response bit,
    // instead of response -> grant -> encoded ROB tag -> ROB read ports.
    reg [3:0] no_response_tag0,no_response_tag1,with_response_tag0,with_response_tag1;
    reg [6:0] no_response_control0,no_response_control1,with_response_control0,with_response_control1;
    integer tag_row;
    always @*begin
        no_response_tag0=0;no_response_tag1=0;with_response_tag0=0;with_response_tag1=0;
        no_response_control0=0;no_response_control1=0;with_response_control0=0;with_response_control1=0;
        for(tag_row=0;tag_row<12;tag_row=tag_row+1)begin
            no_response_tag0=no_response_tag0|({4{no_response_mask0[tag_row]}}&q_tag[tag_row]);
            no_response_tag1=no_response_tag1|({4{no_response_mask1[tag_row]}}&q_tag[tag_row]);
            with_response_tag0=with_response_tag0|({4{with_response_mask0[tag_row]}}&q_tag[tag_row]);
            with_response_tag1=with_response_tag1|({4{with_response_mask1[tag_row]}}&q_tag[tag_row]);
            no_response_control0=no_response_control0|({7{no_response_mask0[tag_row]}}&
                {q_control_meta[tag_row][4],q_control_meta[tag_row][3]||q_error[tag_row],
                 q_control_meta[tag_row][2:0],q_arithmetic[tag_row],q_memory[tag_row]});
            no_response_control1=no_response_control1|({7{no_response_mask1[tag_row]}}&
                {q_control_meta[tag_row][4],q_control_meta[tag_row][3]||q_error[tag_row],
                 q_control_meta[tag_row][2:0],q_arithmetic[tag_row],q_memory[tag_row]});
            with_response_control0=with_response_control0|({7{with_response_mask0[tag_row]}}&
                {q_control_meta[tag_row][4],q_control_meta[tag_row][3]||q_error[tag_row],
                 q_control_meta[tag_row][2:0],q_arithmetic[tag_row],q_memory[tag_row]});
            with_response_control1=with_response_control1|({7{with_response_mask1[tag_row]}}&
                {q_control_meta[tag_row][4],q_control_meta[tag_row][3]||q_error[tag_row],
                 q_control_meta[tag_row][2:0],q_arithmetic[tag_row],q_memory[tag_row]});
        end
    end
    wire [3:0] ordered_tag0=raw_memory?with_response_tag0:no_response_tag0;
    wire [3:0] ordered_tag1=raw_memory?with_response_tag1:no_response_tag1;
    wire [6:0] ordered_control0=raw_memory?with_response_control0:no_response_control0;
    wire [6:0] ordered_control1=raw_memory?with_response_control1:no_response_control1;
    wire [31:0] ordered_pc0=raw_memory?read_rob_pc(with_response_tag0):read_rob_pc(no_response_tag0);
    wire [31:0] ordered_pc1=raw_memory?read_rob_pc(with_response_tag1):read_rob_pc(no_response_tag1);
    wire [31:0] ordered_instruction0=raw_memory?read_rob_instruction(with_response_tag0):read_rob_instruction(no_response_tag0);
    wire [31:0] ordered_instruction1=raw_memory?read_rob_instruction(with_response_tag1):read_rob_instruction(no_response_tag1);
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&ORDERED_SCHEDULER)begin
        if(ordered_valid0&&(ordered_pc0!=read_rob_pc(ordered_tag0)||ordered_instruction0!=read_rob_instruction(ordered_tag0)))
            $fatal(1,"RV32 first early issue metadata differs from selected live ROB owner");
        if(ordered_valid1&&(ordered_pc1!=read_rob_pc(ordered_tag1)||ordered_instruction1!=read_rob_instruction(ordered_tag1)))
            $fatal(1,"RV32 second early issue metadata differs from selected live ROB owner");
    end
`endif
    function [3:0] issue_tag_value;
        input integer choice;
        begin
            if(ORDERED_SCHEDULER)issue_tag_value=choice==issue_choice0?ordered_tag0:ordered_tag1;
            else issue_tag_value=q_tag[choice];
        end
    endfunction
    function issue_write_value;
        input integer choice;
        begin
            if(ORDERED_SCHEDULER)issue_write_value=choice==issue_choice0?
                (|(ordered_mask0&ordered_writes)):(|(ordered_mask1&ordered_writes));
            else issue_write_value=q_writes[choice];
        end
    endfunction
    wire [11:0] bank_eligible;
    wire [2:0] bank_first_valid,bank_second_valid;
    wire [2:0] bank_count[0:2];
    wire [1:0] bank_first_slot[0:2],bank_second_slot[0:2];
    wire [3:0] bank_first_age[0:2],bank_second_age[0:2];
    wire [31:0] bank_first_left[0:2],bank_first_right[0:2],bank_second_left[0:2],bank_second_right[0:2];
    genvar bank,entry;
    generate for(bank=0;bank<3;bank=bank+1)begin:issue_banks
        wire [3:0] occupied,left_ready,right_ready;
        wire [15:0] ages,left_tags,right_tags;
        wire [127:0] left_values,right_values;
        for(entry=0;entry<4;entry=entry+1)begin:local_operands
            assign occupied[entry]=q_valid[bank*4+entry];
            assign ages[entry*4+:4]=q_tag[bank*4+entry]-rob_head;
            assign left_ready[entry]=q_left_ready[bank*4+entry];
            assign right_ready[entry]=q_right_ready[bank*4+entry];
            assign left_tags[entry*4+:4]=q_left_tag[bank*4+entry];
            assign right_tags[entry*4+:4]=q_right_tag[bank*4+entry];
            assign left_values[entry*32+:32]=q_left[bank*4+entry];
            assign right_values[entry*32+:32]=q_right[bank*4+entry];
        end
        rv32_issue_bank #(.FAST_WAKEUP(FAST_WAKEUP)) scheduler_bank(
            .occupied(occupied),.issue_allowed(bank_issue_allowed[bank*4+:4]),.ages(ages),
            .left_ready(left_ready),.right_ready(right_ready),.left_tags(left_tags),.right_tags(right_tags),
            .left_values(left_values),.right_values(right_values),
            .broadcast_valid(queue_broadcast_valid),
            .broadcast_tags(queue_broadcast_tags),
            .broadcast_values(queue_broadcast_values),
            .eligible(bank_eligible[bank*4+:4]),.occupancy_count(bank_count[bank]),
            .first_valid(bank_first_valid[bank]),.second_valid(bank_second_valid[bank]),
            .first_slot(bank_first_slot[bank]),.second_slot(bank_second_slot[bank]),
            .first_age(bank_first_age[bank]),.second_age(bank_second_age[bank]),
            .first_left(bank_first_left[bank]),.first_right(bank_first_right[bank]),
            .second_left(bank_second_left[bank]),.second_right(bank_second_right[bank]));
    end endgenerate
    generate if(ORDERED_SCHEDULER)begin:ordered_selection
        always @*begin
            eligible=ordered_eligible;
            debug_iq0_count={2'b0,q_valid[0]}+{2'b0,q_valid[1]}+{2'b0,q_valid[2]}+{2'b0,q_valid[3]};
            debug_iq1_count={2'b0,q_valid[4]}+{2'b0,q_valid[5]}+{2'b0,q_valid[6]}+{2'b0,q_valid[7]};
            debug_complex_count={2'b0,q_valid[8]}+{2'b0,q_valid[9]}+{2'b0,q_valid[10]}+{2'b0,q_valid[11]};
            int_choice0=-1;int_choice1=-1;int_second0=-1;int_second1=-1;complex_choice=-1;
            for(s=0;s<12;s=s+1)begin ready_left[s]=0;ready_right[s]=0;end
        end
    end else if(BANKED_ISSUE)begin:local_selection
        always @* begin
            eligible=bank_eligible;
            debug_iq0_count=bank_count[0];debug_iq1_count=bank_count[1];debug_complex_count=bank_count[2];
            int_choice0=bank_first_valid[0]?{30'b0,bank_first_slot[0]}:-1;
            int_second0=bank_second_valid[0]?{30'b0,bank_second_slot[0]}:-1;
            int_choice1=bank_first_valid[1]?{28'b0,2'b01,bank_first_slot[1]}:-1;
            int_second1=bank_second_valid[1]?{28'b0,2'b01,bank_second_slot[1]}:-1;
            complex_choice=bank_first_valid[2]?{28'b0,2'b10,bank_first_slot[2]}:-1;
            for(s=0;s<12;s=s+1)begin ready_left[s]=0;ready_right[s]=0;end
        end
    end else begin:legacy_selection
    always @* begin
        debug_iq0_count=0;debug_iq1_count=0;debug_complex_count=0;
        eligible=0;int_choice0=-1;int_choice1=-1;int_second0=-1;int_second1=-1;
        complex_choice=-1;
        for(s=0;s<12;s=s+1)begin
            ready_left[s]=q_left[s];ready_right[s]=q_right[s];
            if(FAST_WAKEUP&&!q_left_ready[s]&&broadcast_available(q_left_tag[s]))ready_left[s]=broadcast_value(q_left_tag[s]);
            if(FAST_WAKEUP&&!q_right_ready[s]&&broadcast_available(q_right_tag[s]))ready_right[s]=broadcast_value(q_right_tag[s]);
            if(q_valid[s])begin
                if(s<4)debug_iq0_count=debug_iq0_count+1'b1;
                else if(s<8)debug_iq1_count=debug_iq1_count+1'b1;
                else debug_complex_count=debug_complex_count+1'b1;
                eligible[s]=(q_left_ready[s]||(FAST_WAKEUP&&broadcast_available(q_left_tag[s])))&&
                            (q_right_ready[s]||(FAST_WAKEUP&&broadcast_available(q_right_tag[s])));
                if(s>=8&&!q_error[s])begin
                    if(q_serial[s])eligible[s]=eligible[s]&&q_tag[s]==rob_head;
                    if(q_memory[s])eligible[s]=eligible[s]&&memory_issue_credit&&memory_order_clear[s];
                    if(q_arithmetic[s]&&
                       !(ENABLE_MUL_STREAM&&q_multiply[s]))
                        eligible[s]=eligible[s]&&
                        legacy_issue_credit;
                end
                if(eligible[s])begin
                    if(s<4)begin
                        if(int_choice0<0||age(q_tag[s])<age(q_tag[(int_choice0<0 ? 4'd0 : int_choice0[3:0])]))begin
                            int_second0=int_choice0;int_choice0=s;
                        end else if(int_second0<0||age(q_tag[s])<age(q_tag[(int_second0<0 ? 4'd0 : int_second0[3:0])]))int_second0=s;
                    end else if(s<8)begin
                        if(int_choice1<0||age(q_tag[s])<age(q_tag[(int_choice1<0 ? 4'd0 : int_choice1[3:0])]))begin
                            int_second1=int_choice1;int_choice1=s;
                        end else if(int_second1<0||age(q_tag[s])<age(q_tag[(int_second1<0 ? 4'd0 : int_second1[3:0])]))int_second1=s;
                    end
                    else begin if(complex_choice<0||age(q_tag[s])<age(q_tag[(complex_choice<0 ? 4'd0 : complex_choice[3:0])]))complex_choice=s;end
                end
            end
        end
    end
    end endgenerate
    wire [3:0] age_choice0=BANKED_ISSUE?bank_first_age[0]:(int_choice0<0?4'b0:age(q_tag[(int_choice0<0 ? 4'd0 : int_choice0[3:0])]));
    wire [3:0] age_choice1=BANKED_ISSUE?bank_first_age[1]:(int_choice1<0?4'b0:age(q_tag[(int_choice1<0 ? 4'd0 : int_choice1[3:0])]));
    wire [3:0] age_second0=BANKED_ISSUE?bank_second_age[0]:(int_second0<0?4'b0:age(q_tag[(int_second0<0 ? 4'd0 : int_second0[3:0])]));
    wire [3:0] age_second1=BANKED_ISSUE?bank_second_age[1]:(int_second1<0?4'b0:age(q_tag[(int_second1<0 ? 4'd0 : int_second1[3:0])]));
    wire [3:0] age_complex=BANKED_ISSUE?bank_first_age[2]:(complex_choice<0?4'b0:age(q_tag[(complex_choice<0 ? 4'd0 : complex_choice[3:0])]));
    // Only local first/second operands leave each four-entry bank. The global
    // stage arbitrates bank candidates; it does not index twelve operand rows.
    function [31:0] issue_left_value;
        input integer choice;
        begin
            if(choice<0)issue_left_value=0;
            else if(ORDERED_SCHEDULER)issue_left_value=choice==issue_choice0?ordered_left0:ordered_left1;
            else if(!BANKED_ISSUE)issue_left_value=ready_left[choice];
            else if(choice>=8)issue_left_value=bank_first_left[2];
            else if(choice>=4)issue_left_value=choice==int_choice1?bank_first_left[1]:bank_second_left[1];
            else issue_left_value=choice==int_choice0?bank_first_left[0]:bank_second_left[0];
        end
    endfunction
    function [31:0] issue_right_value;
        input integer choice;
        begin
            if(choice<0)issue_right_value=0;
            else if(ORDERED_SCHEDULER)issue_right_value=choice==issue_choice0?ordered_right0:ordered_right1;
            else if(!BANKED_ISSUE)issue_right_value=ready_right[choice];
            else if(choice>=8)issue_right_value=bank_first_right[2];
            else if(choice>=4)issue_right_value=choice==int_choice1?bank_first_right[1]:bank_second_right[1];
            else issue_right_value=choice==int_choice0?bank_first_right[0]:bank_second_right[0];
        end
    endfunction
    generate if(ORDERED_SCHEDULER)begin:ordered_global_choice
        always @*begin
            integer_first=-1;integer_second=-1;integer_first_age=0;integer_second_age=0;
            issue_choice0=ordered_valid0?{28'b0,ordered_slot0}:-1;
            issue_choice1=ordered_valid1?{28'b0,ordered_slot1}:-1;
        end
    end else begin:legacy_global_choice
    always @* begin
        integer_first=-1;integer_second=-1;issue_choice0=-1;issue_choice1=-1;
        integer_first_age=0;integer_second_age=0;
        // Merge the local top-two sets, rather than repeat a flat queue scan.
        integer_first=int_choice0;integer_first_age=age_choice0;
        if(int_choice1>=0&&(integer_first<0||age_choice1<integer_first_age))begin integer_first=int_choice1;integer_first_age=age_choice1;end
        if(integer_first==int_choice0)begin
            integer_second=int_second0;integer_second_age=age_second0;
            if(int_choice1>=0&&(integer_second<0||age_choice1<integer_second_age))begin integer_second=int_choice1;integer_second_age=age_choice1;end
        end else begin
            integer_second=int_second1;integer_second_age=age_second1;
            if(int_choice0>=0&&(integer_second<0||age_choice0<integer_second_age))begin integer_second=int_choice0;integer_second_age=age_choice0;end
        end
        if(!reset)begin
            if(ENABLE_STEALING)begin
                if(ENABLE_PAIRING)begin
                    // Assign the oldest compatible set. Complex must use EX0;
                    // the older integer may therefore correctly use EX1.
                    if(complex_choice>=0&&(integer_second<0||age_complex<integer_second_age))begin
                        issue_choice0=complex_choice;issue_choice1=integer_first;
                    end else begin issue_choice0=integer_first;issue_choice1=integer_second;end
                end else begin
                    issue_choice0=integer_first;
                    if(complex_choice>=0&&(integer_first<0||age_complex<integer_first_age))issue_choice0=complex_choice;
                end
                if(ex_hold)begin
                    issue_choice0=-1;
                    if(ENABLE_PAIRING)issue_choice1=integer_first;
                end
            end else begin
                issue_choice0=int_choice0;
                if(complex_choice>=0&&(int_choice0<0||age_complex<age_choice0))issue_choice0=complex_choice;
                if(ENABLE_PAIRING)issue_choice1=int_choice1;
                else if(issue_choice0<0)issue_choice0=int_choice1;
                if(ex_hold)issue_choice0=-1;
            end
        end
    end

    end endgenerate

    // Resource selection reads registered queue occupancy only. Released
    // slots become visible after the edge, independently of current wakeup,
    // issue selection, LSU response, arithmetic arbitration and recovery.
    wire resource_valid0,resource_valid1;
    wire [3:0] resource_slot0,resource_slot1;
    genvar qindex;
    generate for(qindex=0;qindex<12;qindex=qindex+1)begin:registered_resources
        assign allocation_occupied[qindex]=q_valid[qindex];
    end endgenerate
    rv32_queue_allocator queue_resources(
        .occupied(allocation_occupied),.complex0(d_complex0),.complex1(d_complex1),.steer(steer),
        .valid0(resource_valid0),.valid1(resource_valid1),.slot0(resource_slot0),.slot1(resource_slot1));

    // Diagnostic legacy mode only. The normal allocator has no issue input.
    // The execution registers sample old issued-slot fields on this edge.
    // Later allocation writes replace that slot for the following cycle.
    function integer free_queue_slot;
        input complex_operation,preferred_bank;
        input integer excluded;
        integer k;
        begin
            free_queue_slot=-1;
            if(complex_operation)begin
                for(k=11;k>=8;k=k-1)if((!q_valid[k]||(ENABLE_SAME_CYCLE_REUSE&&(issue_choice0==k||issue_choice1==k)))&&k!=excluded)free_queue_slot=k;
            end else begin
                // Prefer the less occupied local bank; use the other if full.
                for(k=7;k>=0;k=k-1)if((!q_valid[k]||(ENABLE_SAME_CYCLE_REUSE&&(issue_choice0==k||issue_choice1==k)))&&k!=excluded)free_queue_slot=k;
                if(preferred_bank)begin
                    for(k=7;k>=4;k=k-1)if((!q_valid[k]||(ENABLE_SAME_CYCLE_REUSE&&(issue_choice0==k||issue_choice1==k)))&&k!=excluded)free_queue_slot=k;
                end else begin
                    for(k=3;k>=0;k=k-1)if((!q_valid[k]||(ENABLE_SAME_CYCLE_REUSE&&(issue_choice0==k||issue_choice1==k)))&&k!=excluded)free_queue_slot=k;
                end
            end
        end
    endfunction
    function [32:0] source_value;
        input [4:0] number;
        input used;
        reg [31:0] committed;
        begin
            committed=read_register(number);
            // A retiring writer is still renamed until this edge. Its
            // registered ROB value is selected below; unrenamed reads use RF.
            if(!used||number==0)source_value={1'b1,32'b0};
            else if(!map_valid[number])source_value={1'b1,committed};
            else source_value={producer_available(map_tag[number]),producer_value(map_tag[number])};
        end
    endfunction
    integer allocation_slot0,allocation_slot1;
    reg preferred0,preferred1;
    reg [32:0] allocation_left0,allocation_right0,allocation_left1,allocation_right1;
    reg [3:0] allocation_ltag0,allocation_rtag0,allocation_ltag1,allocation_rtag1;
    always @* begin
        allocation_left0=source_value(d_rs10,d_use10&&!d_bad0&&!fetch_error0);
        allocation_right0=source_value(d_rs20,d_use20&&!d_bad0&&!fetch_error0);
        allocation_left1=source_value(d_rs11,d_use11&&!d_bad1&&!fetch_error1);
        allocation_right1=source_value(d_rs21,d_use21&&!d_bad1&&!fetch_error1);
        allocation_ltag0=map_tag[d_rs10];allocation_rtag0=map_tag[d_rs20];
        allocation_ltag1=map_tag[d_rs11];allocation_rtag1=map_tag[d_rs21];
        if(d_write0&&d_rd0!=0)begin
            if(d_use11&&d_rs11==d_rd0&&!d_bad1&&!fetch_error1)begin allocation_left1[32]=0;allocation_ltag1=rob_tail;end
            if(d_use21&&d_rs21==d_rd0&&!d_bad1&&!fetch_error1)begin allocation_right1[32]=0;allocation_rtag1=rob_tail;end
        end
    end
    // Capacity and slot proposals depend only on registered occupancy and the
    // current decoded bundle. Recovery is applied at final acceptance above;
    // it does not drive wide initialization enables in the decoupled mode.
    always @* begin
        allocation_offer_count=0;allocation_slot0=-1;allocation_slot1=-1;
        preferred0=debug_iq1_count<debug_iq0_count?1'b1:debug_iq0_count<debug_iq1_count?1'b0:steer;
        preferred1=preferred0;
        if(!reset&&(DECOUPLED_ALLOCATION_PAYLOAD||!recovery)&&!serial_pending&&fetch_count!=0&&rob_count<16&&
            (!d_serial0||(rob_count==0&&!lsu_active&&!mdu_active&&mul_occupancy==0&&!ex_valid0&&!ex_valid1)))begin
            if(ENABLE_SAME_CYCLE_REUSE)allocation_slot0=free_queue_slot(d_complex0,preferred0,-1);
            else if(resource_valid0)allocation_slot0={28'b0,resource_slot0};
            if(allocation_slot0>=0)begin
                allocation_offer_count=1;
                if(!d_complex0)preferred1=allocation_slot0<4;
                if(ENABLE_PAIRING&&!d_serial0&&!d_serial1&&fetch_count>1&&rob_count<15&&fetch_pc1==fetch_prediction0)begin
                    if(ENABLE_SAME_CYCLE_REUSE)allocation_slot1=free_queue_slot(d_complex1,preferred1,allocation_slot0);
                    else if(resource_valid1)allocation_slot1={28'b0,resource_slot1};
                    if(allocation_slot1>=0)allocation_offer_count=2;
                end
            end
        end
    end

    function dispatch_source_ready;
        input [4:0] number;
        input used;
        begin dispatch_source_ready=!used||number==0||!map_valid[number];end
    endfunction
    function [31:0] dispatch_register_value;
        input [4:0] number;
        input used;
        begin dispatch_register_value=(!used||number==0)?32'b0:read_register(number);end
    endfunction
    wire dispatch_ready0=dispatch_source_ready(d_rs10,d_use10)&&dispatch_source_ready(d_rs20,d_use20);
    wire bundle_raw1=d_write0&&d_rd0!=0&&((d_use11&&d_rs11==d_rd0)||(d_use21&&d_rs21==d_rd0));
    wire dispatch_ready1=!bundle_raw1&&dispatch_source_ready(d_rs11,d_use11)&&dispatch_source_ready(d_rs21,d_use21);
    wire [31:0] dispatch_left0=DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_register_value(d_rs10,d_use10):allocation_left0[31:0];
    wire [31:0] dispatch_right0=DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_register_value(d_rs20,d_use20):allocation_right0[31:0];
    wire [31:0] dispatch_left1=DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_register_value(d_rs11,d_use11):allocation_left1[31:0];
    wire [31:0] dispatch_right1=DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_register_value(d_rs21,d_use21):allocation_right1[31:0];
    // Allocation admission and queued issue stay independent of this path.
    // A new ready integer may fill only a genuinely unused next EX register.
    // It still reserves a queue slot, then discards that transient reservation.
    wire bypass_candidate0=allocation_offer_count!=0&&dispatch_integer_class(fetch_instruction0)&&
        !d_bad0&&!fetch_error0&&!d_complex0&&fetch_pc_dispatch_ok0&&(DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_ready0:(allocation_left0[32]&&allocation_right0[32]));
    wire bypass_candidate1=allocation_offer_count==2&&dispatch_integer_class(fetch_instruction1)&&
        !d_bad1&&!fetch_error1&&!d_complex1&&fetch_pc_dispatch_ok1&&(DISPATCH_BYPASS_UNMAPPED_ONLY?dispatch_ready1:(allocation_left1[32]&&allocation_right1[32]));
    integer dispatch_ex0,dispatch_ex1,b;
    reg unselected_ready_integer;
    always @* begin
        dispatch_ex0=-1;dispatch_ex1=-1;unselected_ready_integer=0;
        // Include all old integer-queue classes, including control and faults.
        for(b=0;b<8;b=b+1)
            if(eligible[b]&&issue_choice0!=b&&issue_choice1!=b)unselected_ready_integer=1;
        // In the ordered oldest-compatible scheduler, any usable free lane
        // implies that every eligible integer was already selected. Keep the
        // legacy guard for other policies; do not feed encoded slots back
        // into direct-dispatch admission in the ordered implementation.
        if(ENABLE_DISPATCH_BYPASS&&!reset&&(ORDERED_SCHEDULER||!unselected_ready_integer))begin
            if(bypass_candidate0)begin
                if(issue_choice0<0&&!ex_hold)dispatch_ex0=0;
                else if(ENABLE_PAIRING&&issue_choice1<0)dispatch_ex1=0;
            end
            if(bypass_candidate1)begin
                if(issue_choice0<0&&!ex_hold&&dispatch_ex0<0)dispatch_ex0=1;
                else if(ENABLE_PAIRING&&issue_choice1<0&&dispatch_ex1<0)dispatch_ex1=1;
            end
        end
    end

`ifdef VERILATOR
    always @(posedge clk) if(!reset&&ORDERED_SCHEDULER)begin
        if((ordered_mask0&ordered_mask1)!=0)
            $fatal(1,"T120D ordered issue lanes overlap");
        if(ENABLE_DISPATCH_BYPASS&&(dispatch_ex0>=0||dispatch_ex1>=0)&&unselected_ready_integer)
            $fatal(1,"T120D ordered dispatch omitted an eligible integer");
        if(issue_choice0>=0&&(ordered_left0!=issue_left_value(issue_choice0)||ordered_right0!=issue_right_value(issue_choice0)))
            $fatal(1,"T120D lane0 direct operand differs from reference");
        if(issue_choice1>=0&&(ordered_left1!=issue_left_value(issue_choice1)||ordered_right1!=issue_right_value(issue_choice1)))
            $fatal(1,"T120D lane1 direct operand differs from reference");
    end
`endif

    // Payload may be prepared in a free slot even when recovery cancels its
    // proposal. Only accepted entries gain validity or rename ownership.
    task initialize_allocation_payload;
        input [3:0] tag;
        input integer qs;
        input [31:0] pc,instruction,prediction;
        input fetch_error,writes,memory_operation,store_operation,arithmetic_operation,serial_operation,complex_operation,decode_error;
        input [4:0] destination;
        input [32:0] left_value,right_value;
        input [3:0] left_tag,right_tag;
        input [63:0] sequence_number;
        begin
            rob_history_sequential[tag]<=({instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0}==13'd4);
            rob_writes[tag]<=writes;
            rob_memory[tag]<=memory_operation;rob_store[tag]<=store_operation;rob_arithmetic[tag]<=arithmetic_operation;
            rob_serial[tag]<=serial_operation;rob_complex[tag]<=complex_operation;rob_decode_error[tag]<=decode_error;
            rob_fetch_error[tag]<=fetch_error;
            rob_destination[tag]<=destination;
            rob_sequence[tag]<=ENABLE_TRACE?sequence_number:0;
            q_tag[qs]<=tag;q_left_ready[qs]<=left_value[32];q_right_ready[qs]<=right_value[32];
            q_writes[qs]<=writes&&destination!=0;q_error[qs]<=fetch_error||decode_error;
            q_serial[qs]<=serial_operation;q_memory[qs]<=memory_operation;
            q_arithmetic[qs]<=arithmetic_operation;q_multiply[qs]<=instruction[14:12]==0;
            q_control_meta[qs]<=immutable_control_metadata(instruction,pc);
            q_left[qs]<=left_value[31:0];q_right[qs]<=right_value[31:0];q_left_tag[qs]<=left_tag;q_right_tag[qs]<=right_tag;
        end
    endtask

    task install_dispatch_execution;
        input lane,writes;
        input [3:0] tag;
        input integer qs;
        input [31:0] pc,instruction,left_value,right_value;
        input [63:0] sequence_number;
        begin
            if(!lane)begin
                ex_tag0<=tag;ex_writes0<=writes;ex_sequence0<=ENABLE_TRACE?sequence_number:0;
                ex_pc0<=pc;ex_instruction0<=instruction;ex_left0<=left_value;ex_right0<=right_value;
                debug_issue_tag0<=tag;debug_issue_sequence0<=ENABLE_TRACE?sequence_number:0;debug_issue_pc0<=pc;
                debug_issue_queue0<=ENABLE_TRACE?qs[3:0]:4'b0;
            end else begin
                ex_tag1<=tag;ex_writes1<=writes;ex_sequence1<=ENABLE_TRACE?sequence_number:0;
                ex_pc1<=pc;ex_instruction1<=instruction;ex_left1<=left_value;ex_right1<=right_value;
                debug_issue_tag1<=tag;debug_issue_sequence1<=ENABLE_TRACE?sequence_number:0;debug_issue_pc1<=pc;
                debug_issue_queue1<=ENABLE_TRACE?qs[3:0]:4'b0;
            end
            // Per-row ownership masks discard a bypassed reservation while
            // preserving the allocated ROB owner in the execution register.
        end
    endtask

    function [4:0] immutable_control_metadata;
        input [31:0] instruction,pc;
        begin
            immutable_control_metadata[0]=ordinary_integer_class(instruction);
            immutable_control_metadata[1]=instruction[6:0]==7'b1101111&&instruction[21];
            immutable_control_metadata[2]=instruction[6:0]==7'b1100111;
            immutable_control_metadata[3]=pc[1:0]!=0||(pc[31:28]!=1&&pc[31:28]!=8);
            immutable_control_metadata[4]=instruction_csr_access_fault(instruction);
        end
    endfunction

    // Decode each frontend proposal before the late dispatch lane selector.
    wire [4:0] dispatch_immutable0=immutable_control_metadata(fetch_instruction0,fetch_pc0);
    wire [4:0] dispatch_immutable1=immutable_control_metadata(fetch_instruction1,fetch_pc1);
    wire [6:0] dispatch_control0={dispatch_immutable0[4],dispatch_immutable0[3]||fetch_error0||d_bad0,
        dispatch_immutable0[2:0],d_mdu0,d_mem0};
    wire [6:0] dispatch_control1={dispatch_immutable1[4],dispatch_immutable1[3]||fetch_error1||d_bad1,
        dispatch_immutable1[2:0],d_mdu1,d_mem1};
    // Queued issue consumes already-predecoded per-entry bits, not the late
    // encoded ROB instruction/PC read. Preserve the R51/RV32 response cases.
    wire [6:0] issue_control0=ORDERED_SCHEDULER?ordered_control0:
        {q_control_meta[issue_choice0>=0?issue_choice0:0][4],
         q_control_meta[issue_choice0>=0?issue_choice0:0][3]||q_error[issue_choice0>=0?issue_choice0:0],
         q_control_meta[issue_choice0>=0?issue_choice0:0][2:0],q_arithmetic[issue_choice0>=0?issue_choice0:0],q_memory[issue_choice0>=0?issue_choice0:0]};
    wire [6:0] issue_control1=ORDERED_SCHEDULER?ordered_control1:
        {q_control_meta[issue_choice1>=0?issue_choice1:0][4],
         q_control_meta[issue_choice1>=0?issue_choice1:0][3]||q_error[issue_choice1>=0?issue_choice1:0],
         q_control_meta[issue_choice1>=0?issue_choice1:0][2:0],q_arithmetic[issue_choice1>=0?issue_choice1:0],q_memory[issue_choice1>=0?issue_choice1:0]};
    function instruction_csr_access_fault;
        input [31:0] instruction;
        reg csr_instruction,write_requested;
        begin
            csr_instruction=instruction[6:0]==7'b1110011&&instruction[14:12]!=0;
            // CSRRW/CSRRWI write even for rs1/zimm=0; CSRRS/CSRRC and their
            // immediate forms write only when the instruction field is nonzero.
            // funct3=100 is illegal but the original decoder leaves write=0.
            write_requested=instruction[13:12]==1||
                ((instruction[13:12]==2||instruction[13:12]==3)&&instruction[19:15]!=0);
            instruction_csr_access_fault=csr_instruction&&
                (!csr_exists(instruction[31:20])||(write_requested&&instruction[31:30]==3));
        end
    endfunction

    // The assignments mirror the instruction/PC payload at  install_dispatch_
    // execution and the queued issue block: issue overrides dispatch if both
    // propose the same lane, recovery does not gate private payload, and a held
    // MUL receives neither lane-0 proposal. No readiness or ownership changes.
    always @(posedge clk)begin
        if(reset)begin
            ex_control_meta0<=6'b100000;ex_control_meta1<=6'b100000;
            ex_csr_access_fault0<=0;
        end else begin
            if(dispatch_ex0>=0)begin
                ex_control_meta0<=dispatch_ex0==0?dispatch_control0[5:0]:dispatch_control1[5:0];
                ex_csr_access_fault0<=dispatch_ex0==0?dispatch_control0[6]:dispatch_control1[6];
            end
            if(dispatch_ex1>=0)begin
                ex_control_meta1<=dispatch_ex1==0?dispatch_control0[5:0]:dispatch_control1[5:0];
            end
            if(issue_choice0>=0)begin
                ex_control_meta0<=issue_control0[5:0];
                ex_csr_access_fault0<=issue_control0[6];
            end
            if(issue_choice1>=0)begin
                ex_control_meta1<=issue_control1[5:0];
            end
        end
    end
`ifdef VERILATOR
    // Independent originals remain evaluated from the captured EX packet.
    // Comparing only valid packets avoids imposing requirements on proposals
    // canceled by recovery or on payload left behind after a bubble.
    wire exmeta_static_reference0=ex_pc0[1:0]!=0||rob_fetch_error[ex_tag0]||
        (ex_pc0[31:28]!=1&&ex_pc0[31:28]!=8)||e_illegal_reference0;
    wire exmeta_static_reference1=ex_pc1[1:0]!=0||rob_fetch_error[ex_tag1]||
        (ex_pc1[31:28]!=1&&ex_pc1[31:28]!=8)||e_illegal_reference1;
    wire exmeta_csr_reference0=e_csr0&&
        (!csr_exists(e_csr_number0)||(e_csr_write0&&e_csr_number0[11:10]==3));
    wire exmeta_integer_reference0=exmeta_static_reference0||exmeta_csr_reference0||
        (ex_instruction0[6:0]==7'b1101111&&ex_instruction0[21])||
        (ex_instruction0[6:0]==7'b1100111&&jalr_low0[1]);
    wire exmeta_integer_reference1=exmeta_static_reference1||
        (ex_instruction1[6:0]==7'b1101111&&ex_instruction1[21])||
        (ex_instruction1[6:0]==7'b1100111&&jalr_low1[1]);
    reg [1:0] exmeta_origin0,exmeta_origin1;
    reg [7:0] exmeta_seen;
    always @(posedge clk)begin
        if(reset)begin exmeta_origin0<=0;exmeta_origin1<=0;exmeta_seen<=0;end
        else begin
            if(dispatch_ex0>=0)exmeta_origin0<=1;
            if(dispatch_ex1>=0)exmeta_origin1<=1;
            if(issue_choice0>=0)exmeta_origin0<=2;
            if(issue_choice1>=0)exmeta_origin1<=2;
            if(ex_valid0)begin
                if(ex_control_meta0!={exmeta_static_reference0,
                    ex_instruction0[6:0]==7'b1100111,
                    (ex_instruction0[6:0]==7'b1101111&&ex_instruction0[21]),
                    ordinary_integer_class(ex_instruction0),e_arithmetic_reference0,e_memory_reference0})
                    $fatal(1,"EXMETA lane 0 class/static fault differs from original EX decoder");
                if(ex_csr_access_fault0!=exmeta_csr_reference0||integer_fault0!=exmeta_integer_reference0)
                    $fatal(1,"EXMETA lane 0 CSR/jump fault differs from original EX expression");
                if(!exmeta_seen[exmeta_origin0])begin
                    exmeta_seen[exmeta_origin0]<=1;
                    $display("COVERAGE EXMETA lane=0 source=%0d (1=dispatch,2=issue)",exmeta_origin0);
                end
            end
            if(ex_valid1)begin
                if(ex_control_meta1!={exmeta_static_reference1,
                    ex_instruction1[6:0]==7'b1100111,
                    (ex_instruction1[6:0]==7'b1101111&&ex_instruction1[21]),
                    ordinary_integer_class(ex_instruction1),e_arithmetic_reference1,e_memory_reference1})
                    $fatal(1,"EXMETA lane 1 class/static fault differs from original EX decoder");
                if(integer_fault1!=exmeta_integer_reference1)
                    $fatal(1,"EXMETA lane 1 jump fault differs from original EX expression");
                if(!exmeta_seen[4+exmeta_origin1])begin
                    exmeta_seen[4+exmeta_origin1]<=1;
                    $display("COVERAGE EXMETA lane=1 source=%0d (1=dispatch,2=issue)",exmeta_origin1);
                end
            end
            if(ex_hold&&(issue_choice0>=0||dispatch_ex0>=0))
                $fatal(1,"EXMETA held MUL has a conflicting lane 0 payload proposal");
        end
    end
`endif

    // Encoding legality is immutable allocation metadata. Capture it with
    // exactly the same private EX instruction payload and issue priorities.
    always @(posedge clk)begin
        if(reset)begin ex_decode_error0<=1;ex_decode_error1<=1;end
        else begin
            if(dispatch_ex0>=0)ex_decode_error0<=dispatch_ex0==0?d_bad0:d_bad1;
            if(dispatch_ex1>=0)ex_decode_error1<=dispatch_ex1==0?d_bad0:d_bad1;
            if(issue_choice0>=0)ex_decode_error0<=rob_decode_error[issue_tag_value(issue_choice0)];
            if(issue_choice1>=0)ex_decode_error1<=rob_decode_error[issue_tag_value(issue_choice1)];
        end
    end
`ifdef VERILATOR
    reg [3:0] ex_decode_seen;
    always @(posedge clk)begin
        if(reset)ex_decode_seen<=0;
        else begin
            if(ex_valid0&&e_illegal0!=e_illegal_reference0)$fatal(1,"R41 first cached EX legality differs from original decoder");
            if(ex_valid1&&e_illegal1!=e_illegal_reference1)$fatal(1,"R41 second cached EX legality differs from original decoder");
            if(ex_valid0&&!ex_decode_seen[{1'b0,e_illegal0}])begin
                ex_decode_seen[{1'b0,e_illegal0}]<=1;$display("COVERAGE R41 ex_decode lane=0 illegal=%0d",e_illegal0);
            end
            if(ex_valid1&&!ex_decode_seen[{1'b1,e_illegal1}])begin
                ex_decode_seen[{1'b1,e_illegal1}]<=1;$display("COVERAGE R41 ex_decode lane=1 illegal=%0d",e_illegal1);
            end
        end
    end
`endif
    // Metadata proposals equal actual completions off recovery. Payloads may
    // be written on a cancelling edge; only accepted completion masks grant done.
    wire payload0=!reset&&ex_valid0&&(fault0||(!e_memory0&&!e_arithmetic0));
    wire payload_integer1=!reset&&ex_valid1;
    wire payload1=payload_integer1||raw_spill;
    wire payload2=raw_memory||(raw_arithmetic&&!raw_spill);
    wire payload_fault1=!raw_spill&&fault1;
    wire payload_fault2=raw_memory&&dmem_response_error;
    // Branch direction is late operand logic. Compute both possible target
    // agreements independently, then select a single bit after direction;
    // avoid direction ->32-bit next-PC mux -> full prediction comparison.
    wire [31:0] payload_prediction_delta0=read_rob_prediction(ex_tag0)-ex_pc0;
    wire [31:0] payload_prediction_delta1=read_rob_prediction(ex_tag1)-ex_pc1;
    wire [31:0] payload_branch_offset0={{19{ex_instruction0[31]}},ex_instruction0[31],ex_instruction0[7],ex_instruction0[30:25],ex_instruction0[11:8],1'b0};
    wire [31:0] payload_branch_offset1={{19{ex_instruction1[31]}},ex_instruction1[31],ex_instruction1[7],ex_instruction1[30:25],ex_instruction1[11:8],1'b0};
    wire payload_branch_match0=(e_taken0&&(payload_prediction_delta0==payload_branch_offset0))||
        (!e_taken0&&(payload_prediction_delta0==32'd4));
    wire payload_branch_match1=(e_taken1&&(payload_prediction_delta1==payload_branch_offset1))||
        (!e_taken1&&(payload_prediction_delta1==32'd4));
    wire payload_prediction_miss0=ex_instruction0[6:0]==7'b1100011 ? !payload_branch_match0 : (e_next0!=read_rob_prediction(ex_tag0));
    wire payload_prediction_miss1=ex_instruction1[6:0]==7'b1100011 ? !payload_branch_match1 : (e_next1!=read_rob_prediction(ex_tag1));
`ifdef VERILATOR
    reg [3:0] branch_facts_seen0,branch_facts_seen1;
    always @(posedge clk)begin
        if(reset)begin branch_facts_seen0<=0;branch_facts_seen1<=0;end
        else begin
            if(payload0&&e_control0&&payload_prediction_miss0!=(e_next0!=read_rob_prediction(ex_tag0)))
                $fatal(1,"R39 first prediction fact differs from original full next-PC comparison");
            if(payload_integer1&&e_control1&&payload_prediction_miss1!=(e_next1!=read_rob_prediction(ex_tag1)))
                $fatal(1,"R39 second prediction fact differs from original full next-PC comparison");
            if(complete0&&ex_instruction0[6:0]==7'b1100011&&!branch_facts_seen0[{e_taken0,payload_prediction_miss0}])begin
                branch_facts_seen0[{e_taken0,payload_prediction_miss0}]<=1;
                $display("COVERAGE R39 branch_fact lane=0 taken=%0d miss=%0d",e_taken0,payload_prediction_miss0);
            end
            if(complete_integer1&&ex_instruction1[6:0]==7'b1100011&&!branch_facts_seen1[{e_taken1,payload_prediction_miss1}])begin
                branch_facts_seen1[{e_taken1,payload_prediction_miss1}]<=1;
                $display("COVERAGE R39 branch_fact lane=1 taken=%0d miss=%0d",e_taken1,payload_prediction_miss1);
            end
        end
    end
`endif
    wire allocate_prediction_miss0=!fetch_prediction_sequential0;
    wire allocate_prediction_miss1=!fetch_prediction_sequential1;
    genvar completion_row;
    generate for(completion_row=0;completion_row<16;completion_row=completion_row+1)begin:completion_metadata
        wire alloc0=allocation_offer_count!=0&&rob_tail==completion_row;
        wire alloc1=allocation_offer_count==2&&tail1==completion_row;
        wire packet0=payload0&&ex_tag0==completion_row;
        wire packet1=payload1&&wake_tag1==completion_row;
        wire packet2=payload2&&wake_tag2==completion_row;
        wire accepted=(complete0&&ex_tag0==completion_row)||
            (complete1&&complete_tag1==completion_row)||(complete2&&complete_tag2==completion_row);
        always @(posedge clk)begin
            if(reset||recovery)rob_done[completion_row]<=0;
            else if(alloc0||alloc1)rob_done[completion_row]<=0;
            else if(accepted)rob_done[completion_row]<=1;
            if(reset)begin rob_fault[completion_row]<=0;result_owner[completion_row]<=0;end
            else begin
                if(packet0)begin
                    rob_fault[completion_row]<=fault0;rob_cause[completion_row]<=fault_cause0;
                    result_owner[completion_row]<=0;
                    rob_control[completion_row]<=e_control0;rob_conditional[completion_row]<=e_conditional0;
                    rob_taken[completion_row]<=e_taken0;
                    if(e_control0)rob_prediction_miss[completion_row]<=payload_prediction_miss0;
                    rob_system[completion_row]<=e_system0;rob_csr_write[completion_row]<=e_csr0&&e_csr_write0;
                end
                if(packet1)begin
                    rob_fault[completion_row]<=payload_fault1;rob_cause[completion_row]<=raw_spill?32'b0:fault_cause1;
                    result_owner[completion_row]<=1;
                    if(!raw_spill)begin
                        rob_control[completion_row]<=e_control1;rob_conditional[completion_row]<=e_conditional1;
                        rob_taken[completion_row]<=e_taken1;
                        if(e_control1)rob_prediction_miss[completion_row]<=payload_prediction_miss1;
                    end
                end
                if(packet2)begin
                    rob_fault[completion_row]<=payload_fault2;rob_cause[completion_row]<=lsu_store?7:5;
                    result_owner[completion_row]<=2;
                end
                // Pre-edge free allocation targets override any dead payload.
                if(alloc0||alloc1)begin
                    rob_fault[completion_row]<=0;rob_cause[completion_row]<=0;
                    rob_control[completion_row]<=0;rob_conditional[completion_row]<=0;rob_taken[completion_row]<=0;
                    rob_system[completion_row]<=0;rob_csr_write[completion_row]<=0;
                    rob_prediction_miss[completion_row]<=alloc0?allocate_prediction_miss0:allocate_prediction_miss1;
                end
            end
        end
`ifdef VERILATOR
        always @(posedge clk)if(!reset&&!recovery)begin
            if((packet0&&packet1)||(packet0&&packet2)||(packet1&&packet2))
                $fatal(1,"R15 duplicate completion owner");
            if((packet0||packet1||packet2)&&(!rob_valid[completion_row]||alloc0||alloc1))
                $fatal(1,"R15 completion allocation/validity ownership collision");
        end
`endif
    end endgenerate
    always @(posedge clk)begin
        if(payload0)begin serial_csr_number<=e_csr_number0;serial_csr_value<=e_csr_new0;end
    end
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&!recovery)begin
        if(payload0!=complete0||payload1!=complete1||payload2!=complete2)
            $fatal(1,"R15 private/accepted completion mask mismatch");
        if(complete1&&(wake_tag1!=complete_tag1||wake_value1!=complete_value1||payload_fault1!=complete_fault1))
            $fatal(1,"R15 private/accepted completion1 payload mismatch");
        if(complete2&&(wake_tag2!=complete_tag2||wake_value2!=complete_value2||payload_fault2!=complete_fault2))
            $fatal(1,"R15 private/accepted completion2 payload mismatch");
    end
`endif

    always @(posedge clk)begin
        if(allocation_offer_count!=0&&(!rob_tail[0]||allocation_offer_count==2))begin
            rob_instruction_even[rob_tail[0]?tail1[3:1]:rob_tail[3:1]]<=rob_tail[0]?fetch_instruction1:fetch_instruction0;
            rob_recovery_even[rob_tail[0]?tail1[3:1]:rob_tail[3:1]]<=rob_tail[0]?fetch_recovery_context1:fetch_recovery_context0;
            rob_context_even[rob_tail[0]?tail1[3:1]:rob_tail[3:1]]<=rob_tail[0]?fetch_prediction_context1:fetch_prediction_context0;
            rob_prediction_even[rob_tail[0]?tail1[3:1]:rob_tail[3:1]]<=rob_tail[0]?fetch_prediction1:fetch_prediction0;
        end
        if(allocation_offer_count!=0&&(rob_tail[0]||allocation_offer_count==2))begin
            rob_instruction_odd[rob_tail[0]?rob_tail[3:1]:tail1[3:1]]<=rob_tail[0]?fetch_instruction0:fetch_instruction1;
            rob_recovery_odd[rob_tail[0]?rob_tail[3:1]:tail1[3:1]]<=rob_tail[0]?fetch_recovery_context0:fetch_recovery_context1;
            rob_context_odd[rob_tail[0]?rob_tail[3:1]:tail1[3:1]]<=rob_tail[0]?fetch_prediction_context0:fetch_prediction_context1;
            rob_prediction_odd[rob_tail[0]?rob_tail[3:1]:tail1[3:1]]<=rob_tail[0]?fetch_prediction0:fetch_prediction1;
        end
        if(payload0&&(e_control0||e_system0==2))next_lane0[ex_tag0]<=e_system0==2?csr_exception_pc:e_next0;
        if(payload_integer1&&e_control1)next_lane1[ex_tag1]<=e_next1;
        if(payload0&&fault0)tval_lane0[ex_tag0]<=fault_value0;
        if(payload_integer1&&fault1)tval_lane1[ex_tag1]<=fault_value1;
        if(payload2&&raw_memory&&dmem_response_error)tval_lane2[wake_tag2]<=lsu_address;
        if(retire0&&rob_writes[rob_head]&&rob_destination[rob_head]!=0)
            register_lane0[rob_destination[rob_head]]<=head_retire_value;
        if(retire1&&rob_writes[head1]&&rob_destination[head1]!=0)
            register_lane1[rob_destination[head1]]<=second_retire_value;
        if(payload0)result_lane0[ex_tag0]<=e_value0;
        if(payload1)result_lane1[wake_tag1]<=wake_value1;
        if(payload2)result_lane2[wake_tag2]<=wake_value2;
    end
    always @(posedge clk)begin
        if(reset||recovery)legacy_issue_credit<=1;
        else if(issue_choice0>=0&&q_arithmetic[(issue_choice0>=0)?issue_choice0:0]&&
            !q_error[(issue_choice0>=0)?issue_choice0:0]&&
            !(ENABLE_MUL_STREAM&&q_multiply[(issue_choice0>=0)?issue_choice0:0]))legacy_issue_credit<=0;
        else if(complete_legacy)legacy_issue_credit<=1;
    end
    genvar ownership_row;
    generate for(ownership_row=0;ownership_row<12;ownership_row=ownership_row+1)begin:queue_ownership
        wire issued=ORDERED_SCHEDULER?(ordered_mask0[ownership_row]||ordered_mask1[ownership_row]):
            (issue_choice0==ownership_row||issue_choice1==ownership_row);
        wire allocate0=allocation_offer_count!=0&&allocation_slot0==ownership_row&&
            dispatch_ex0!=0&&dispatch_ex1!=0;
        wire allocate1=allocation_offer_count==2&&allocation_slot1==ownership_row&&
            dispatch_ex0!=1&&dispatch_ex1!=1;
        always @(posedge clk)begin
            if(reset||recovery)q_valid[ownership_row]<=0;
            else q_valid[ownership_row]<=(q_valid[ownership_row]&&!issued)||allocate0||allocate1;
        end
    end endgenerate
`ifdef VERILATOR
    reg [63:0] prior_expected_cycle,prior_expected_instruction,prior_expected_event[0:3];
    reg counter_reference_valid;
    reg saw_cycle_carry64,saw_instruction_carry64;
    reg [3:0] saw_event_carry64;
    integer counter_reference_row;
    always @(posedge clk)begin
        if(reset)begin
            prior_expected_cycle<=0;prior_expected_instruction<=0;counter_reference_valid<=1;
            saw_cycle_carry64<=0;saw_instruction_carry64<=0;saw_event_carry64<=0;
            for(counter_reference_row=0;counter_reference_row<4;counter_reference_row=counter_reference_row+1)prior_expected_event[counter_reference_row]<=0;
        end else begin
            if(counter_reference_valid)begin
                if(cycle_counter!=prior_expected_cycle||instruction_counter!=prior_expected_instruction)
                    $fatal(1,"R35 cycle/retirement counter differs from original64-bit arithmetic/CSR priority");
                for(counter_reference_row=0;counter_reference_row<4;counter_reference_row=counter_reference_row+1)
                    if(event_counter[counter_reference_row]!=prior_expected_event[counter_reference_row])
                        $fatal(1,"R35 event counter differs from original64-bit arithmetic/partial CSR priority");
            end
            prior_expected_cycle<=cycle_counter+64'd1;
            prior_expected_instruction<=instruction_counter+{63'b0,retire0}+{63'b0,retire1};
            for(counter_reference_row=0;counter_reference_row<4;counter_reference_row=counter_reference_row+1)begin
                prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row];
                case(event_selector[counter_reference_row])
                    1:if(event_icache_refill)prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row]+64'd1;
                    2:if(event_dcache_refill)prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row]+64'd1;
                    3:if(event_dcache_writeback)prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row]+64'd1;
                    4:if(debug_branch_miss)prior_expected_event[counter_reference_row]<=event_counter[counter_reference_row]+64'd1;
                    default:begin end
                endcase
                if(!saw_event_carry64[counter_reference_row]&&counter_event_step[counter_reference_row]&&event_counter[counter_reference_row]==64'hffffffffffffffff)begin
                    saw_event_carry64[counter_reference_row]<=1;$display("COVERAGE R35 event_carry64 row=%0d",counter_reference_row);
                end
            end
            if(!saw_cycle_carry64&&cycle_counter==64'hffffffffffffffff)begin saw_cycle_carry64<=1;$display("COVERAGE R35 cycle_carry64");end
            if(!saw_instruction_carry64&&(retire0||retire1)&&
               (instruction_counter==64'hffffffffffffffff||((retire0&&retire1)&&instruction_counter==64'hfffffffffffffffe)))begin
                saw_instruction_carry64<=1;$display("COVERAGE R35 instruction_carry64");
            end
            // Exact original write priority: cycle/instret writes replace a
            // whole64-bit proposal with the old untouched half. Event writes
            // replace only their selected half of the incremented proposal.
            if(retire0&&rob_csr_write[rob_head])begin
                case(serial_csr_number)
                    12'hb00:prior_expected_cycle<={cycle_counter[63:32],serial_csr_value};
                    12'hb80:prior_expected_cycle<={serial_csr_value,cycle_counter[31:0]};
                    12'hb02:prior_expected_instruction<={instruction_counter[63:32],serial_csr_value};
                    12'hb82:prior_expected_instruction<={serial_csr_value,instruction_counter[31:0]};
                    default:begin
                        if(serial_csr_number>=12'hb03&&serial_csr_number<=12'hb06)prior_expected_event[serial_csr_number[1:0]-2'd3][31:0]<=serial_csr_value;
                        if(serial_csr_number>=12'hb83&&serial_csr_number<=12'hb86)prior_expected_event[serial_csr_number[1:0]-2'd3][63:32]<=serial_csr_value;
                    end
                endcase
            end
        end
    end
`endif
    integer r;
    always @(posedge clk)begin
        if(reset)begin
            rob_head<=0;rob_tail<=0;rob_count<=0;serial_pending<=0;steer<=0;next_sequence<=0;
            ex_valid0<=0;ex_valid1<=0;ex_writes0<=0;ex_writes1<=0;ex_tag0<=0;ex_tag1<=0;ex_sequence0<=0;ex_sequence1<=0;
            ex_instruction0<=0;ex_instruction1<=0;ex_pc0<=RESET_VECTOR;ex_pc1<=RESET_VECTOR;
            ex_left0<=0;ex_left1<=0;ex_right0<=0;ex_right1<=0;
            lsu_state<=L_IDLE;lsu_tag<=0;lsu_sequence<=0;lsu_pc<=0;lsu_address<=0;lsu_wdata<=0;
            lsu_writes<=0;lsu_strobes<=0;lsu_size<=0;lsu_store<=0;lsu_unsigned<=0;lsu_killed<=0;lsu_irrevocable<=0;
            prepared_second_valid<=0;
            prepared_valid<=0;prepared_writes<=0;prepared_tag<=0;prepared_sequence<=0;prepared_pc<=0;prepared_address<=0;
            prepared_wdata<=0;prepared_strobes<=0;prepared_size<=0;prepared_store<=0;prepared_unsigned<=0;prepared_peripheral<=0;
            mdu_active<=0;mdu_writes<=0;mdu_tag<=0;mdu_sequence<=0;mdu_pc<=0;
            csr_status<=32'h00001800;csr_interrupt_enable<=0;csr_vector<=0;csr_scratch<=0;
            csr_exception_pc<=0;csr_cause<=0;csr_trap_value<=0;
            cycle_counter<=0;instruction_counter<=0;architectural_pc<=RESET_VECTOR;
            retire_valid<=0;retire_pc0<=0;retire_pc1<=0;d1_retire_next_pc0<=0;retire_instruction0<=0;retire_instruction1<=0;
            retire_destination0<=0;retire_destination1<=0;retire_value0<=0;retire_value1<=0;fence_i<=0;fence_d<=0;
            for(r=0;r<32;r=r+1)begin register_valid[r]<=0;register_owner[r]<=0;map_valid[r]<=0;map_tag[r]<=0;end
            for(r=0;r<16;r=r+1)begin
                rob_valid[r]<=0;
            end

            for(r=0;r<4;r=r+1)begin event_selector[r]<=0;event_counter[r]<=0;end
            debug_alloc_valid<=0;debug_alloc_proposal_valid<=0;
            debug_alloc_queue0<=0;debug_alloc_queue1<=0;debug_issue_queue0<=0;debug_issue_queue1<=0;
            debug_alloc_tag0<=0;debug_alloc_sequence0<=0;debug_alloc_pc0<=0;
            debug_alloc_tag1<=0;debug_alloc_sequence1<=0;debug_alloc_pc1<=0;
            debug_issue_valid<=0;
            debug_issue_from_allocation<=0;
            debug_issue_tag0<=0;debug_issue_sequence0<=0;debug_issue_pc0<=0;
            debug_issue_tag1<=0;debug_issue_sequence1<=0;debug_issue_pc1<=0;
            debug_complete_valid<=0;debug_complete_writes<=0;debug_complete_broadcast<=0;
            debug_complete_tag0<=0;debug_complete_sequence0<=0;debug_complete_pc0<=0;
            debug_complete_tag1<=0;debug_complete_sequence1<=0;debug_complete_pc1<=0;
            debug_complete_tag2<=0;debug_complete_sequence2<=0;debug_complete_pc2<=0;
            debug_complete_exception<=0;debug_retire_tag0<=0;debug_retire_tag1<=0;debug_retire_sequence0<=0;debug_retire_sequence1<=0;
            debug_recovery_valid<=0;debug_recovery_first_killed_sequence<=0;
        end else begin
            cycle_counter[15:0]<=cycle_counter[15:0]+16'd1;
            if(&cycle_counter[15:0])cycle_counter[31:16]<=cycle_counter[31:16]+16'd1;
            if(&cycle_counter[31:0])cycle_counter[47:32]<=cycle_counter[47:32]+16'd1;
            if(&cycle_counter[47:0])cycle_counter[63:48]<=cycle_counter[63:48]+16'd1;
            if(retire0||retire1)begin
                instruction_counter[15:0]<=instruction_counter[15:0]+(retire0&&retire1?16'd2:16'd1);
                if((&instruction_counter[15:1])&&(instruction_counter[0]||(retire0&&retire1)))
                    instruction_counter[31:16]<=instruction_counter[31:16]+16'd1;
                if((&instruction_counter[31:1])&&(instruction_counter[0]||(retire0&&retire1)))
                    instruction_counter[47:32]<=instruction_counter[47:32]+16'd1;
                if((&instruction_counter[47:1])&&(instruction_counter[0]||(retire0&&retire1)))
                    instruction_counter[63:48]<=instruction_counter[63:48]+16'd1;
            end
            for(r=0;r<4;r=r+1)if(counter_event_step[r])begin
                event_counter[r][15:0]<=event_counter[r][15:0]+16'd1;
                if(&event_counter[r][15:0])event_counter[r][31:16]<=event_counter[r][31:16]+16'd1;
                if(&event_counter[r][31:0])event_counter[r][47:32]<=event_counter[r][47:32]+16'd1;
                if(&event_counter[r][47:0])event_counter[r][63:48]<=event_counter[r][63:48]+16'd1;
            end
            retire_valid<={retire1,retire0};
            d1_retire_next_pc0<=retirement_next0;retire_pc0<=read_rob_pc(rob_head);retire_pc1<=read_rob_prediction(rob_head);
            retire_instruction0<=read_rob_instruction(rob_head);retire_instruction1<=read_rob_instruction(head1);
            retire_destination0<=rob_writes[rob_head]?rob_destination[rob_head]:0;
            retire_destination1<=rob_writes[head1]?rob_destination[head1]:0;
            retire_value0<=head_retire_value;retire_value1<=second_retire_value;
            debug_retire_tag0<=rob_head;debug_retire_tag1<=head1;
            debug_retire_sequence0<=rob_sequence[rob_head];debug_retire_sequence1<=rob_sequence[head1];
            debug_recovery_valid<=recovery;debug_recovery_first_killed_sequence<=ENABLE_TRACE?recovery_first:0;
            fence_i<=maintain_i;fence_d<=maintain_d;
            debug_alloc_valid<=allocate_count==2?2'b11:allocate_count==1?2'b01:2'b00;
            debug_alloc_proposal_valid<=ENABLE_TRACE?(allocation_offer_count==2?2'b11:allocation_offer_count==1?2'b01:2'b00):2'b00;
            debug_alloc_queue0<=ENABLE_TRACE?allocation_slot0[3:0]:4'b0;
            debug_alloc_queue1<=ENABLE_TRACE?allocation_slot1[3:0]:4'b0;
            debug_alloc_tag0<=rob_tail;debug_alloc_tag1<=tail1;
            debug_alloc_sequence0<=ENABLE_TRACE?next_sequence:0;
            debug_alloc_sequence1<=ENABLE_TRACE?next_sequence+64'd1:0;
            debug_alloc_pc0<=fetch_pc0;debug_alloc_pc1<=fetch_pc1;
            debug_issue_valid<=recovery?2'b0:{issue_choice1>=0||dispatch_ex1>=0,issue_choice0>=0||dispatch_ex0>=0};
            debug_issue_from_allocation<=ENABLE_TRACE?{dispatch_ex1>=0,dispatch_ex0>=0}:2'b0;
            debug_issue_queue0<=ENABLE_TRACE?issue_choice0[3:0]:4'b0;
            debug_issue_queue1<=ENABLE_TRACE?issue_choice1[3:0]:4'b0;
            debug_complete_valid<={complete2,complete1,complete0};
            debug_complete_writes<=ENABLE_TRACE?{complete_writes2,complete_writes1,ex_writes0}:3'b0;
            debug_complete_broadcast<=ENABLE_TRACE?{broadcast2,broadcast1,broadcast0}:3'b0;
            debug_complete_exception<={complete_fault2,complete_fault1,fault0};
            debug_complete_tag0<=ex_tag0;debug_complete_tag1<=complete_tag1;debug_complete_tag2<=complete_tag2;
            debug_complete_sequence0<=ex_sequence0;debug_complete_sequence1<=complete_sequence1;debug_complete_sequence2<=complete_sequence2;
            debug_complete_pc0<=ex_pc0;debug_complete_pc1<=complete_pc1;debug_complete_pc2<=complete_pc2;

            if(retire0)begin
                if(rob_writes[rob_head]&&rob_destination[rob_head]!=0)begin
                    register_valid[rob_destination[rob_head]]<=1;register_owner[rob_destination[rob_head]]<=0;
                    if(map_valid[rob_destination[rob_head]]&&map_tag[rob_destination[rob_head]]==rob_head)map_valid[rob_destination[rob_head]]<=0;
                end
                architectural_pc<=retirement_next0;
                if(rob_serial[rob_head])serial_pending<=0;
                if(lsu_irrevocable&&lsu_tag==rob_head)lsu_irrevocable<=0;
            end
            if(retire1)begin
                if(rob_writes[head1]&&rob_destination[head1]!=0)begin
                    register_valid[rob_destination[head1]]<=1;register_owner[rob_destination[head1]]<=1;
                    if(map_valid[rob_destination[head1]]&&map_tag[rob_destination[head1]]==head1)map_valid[rob_destination[head1]]<=0;
                end
                architectural_pc<=retirement_next1;
                if(lsu_irrevocable&&lsu_tag==head1)lsu_irrevocable<=0;
            end
            register_valid[0]<=0;map_valid[0]<=0;
            if(retire0&&rob_csr_write[rob_head])begin
                case(serial_csr_number)
                    12'h300:csr_status<=(serial_csr_value&32'h00000088)|32'h00001800;
                    12'h304:csr_interrupt_enable<=serial_csr_value&32'h00000888;
                    12'h305:csr_vector<={serial_csr_value[31:2],2'b0};
                    12'h340:csr_scratch<=serial_csr_value;
                    12'h341:csr_exception_pc<={serial_csr_value[31:2],2'b0};
                    12'h342:csr_cause<=serial_csr_value&32'h8000000f;
                    12'h343:csr_trap_value<=serial_csr_value;
                    12'hb00:cycle_counter<={cycle_counter[63:32],serial_csr_value};
                    12'hb80:cycle_counter<={serial_csr_value,cycle_counter[31:0]};
                    12'hb02:instruction_counter<={instruction_counter[63:32],serial_csr_value};
                    12'hb82:instruction_counter<={serial_csr_value,instruction_counter[31:0]};
                    default:begin
                        if(serial_csr_number>=12'hb03&&serial_csr_number<=12'hb06)event_counter[serial_csr_number[1:0]-2'd3][31:0]<=serial_csr_value;
                        if(serial_csr_number>=12'hb83&&serial_csr_number<=12'hb86)event_counter[serial_csr_number[1:0]-2'd3][63:32]<=serial_csr_value;
                        if(serial_csr_number>=12'h323&&serial_csr_number<=12'h326)event_selector[serial_csr_number[1:0]-2'd3]<=serial_csr_value[2:0];
                    end
                endcase
            end
            if(return_from_trap)begin csr_status[3]<=csr_status[7];csr_status[7]<=1;end
            if(trap_enter)begin
                csr_exception_pc<={trap_pc[31:2],2'b0};csr_cause<=trap_cause;csr_trap_value<=trap_value;
                csr_status[7]<=csr_status[3];csr_status[3]<=0;lsu_irrevocable<=0;
            end
            if(recovery)architectural_pc<=recovery_address;

            // Presented requests survive recovery; only their result identity dies.
            if(lsu_state==L_OFFER&&dmem_request_ready)lsu_state<=L_WAIT;
            if((prepared_side_effect||prepared_store_lookahead)&&!recovery)begin
                lsu_state<=dmem_request_ready?L_WAIT:L_OFFER;lsu_irrevocable<=1;
            end
            if(recovery)begin
                if(lsu_state==L_PREPARED)begin lsu_state<=L_IDLE;lsu_killed<=0;end
                else if(lsu_state==L_OFFER||lsu_state==L_WAIT)lsu_killed<=1;
            end
            if(lsu_response)begin lsu_state<=L_IDLE;lsu_killed<=0;end
            // Old response consumes old A metadata. A later handoff assignment
            // installs the new owner only after that response has been recorded.
            // Unowned/turning-over payload may settle before late admission.
            // State, killed and irrevocable ownership still use active_handoff.
            if(active_room)begin
                lsu_tag<=candidate_tag;lsu_writes<=candidate_writes;lsu_sequence<=candidate_sequence;lsu_pc<=candidate_pc;
                lsu_address<=candidate_address;lsu_size<=candidate_size;lsu_store<=candidate_store;lsu_unsigned<=candidate_unsigned;
                lsu_wdata<=candidate_wdata;lsu_strobes<=candidate_strobes;
            end
            if(active_handoff)begin
                lsu_killed<=recovery;lsu_irrevocable<=candidate_side_effect&&direct_request;
                if(!direct_request)lsu_state<=L_PREPARED;
                else lsu_state<=dmem_request_ready?L_WAIT:L_OFFER;
            end
            if(recovery)begin prepared_valid<=0;prepared_second_valid<=0;end
            else begin
                if(active_handoff&&prepared_valid)begin
                    if(prepared_second_valid)begin
                        prepared_valid<=1;
                    prepared_tag<=prepared_second_tag;
                    prepared_writes<=prepared_second_writes;
                    prepared_sequence<=prepared_second_sequence;
                    prepared_pc<=prepared_second_pc;
                    prepared_address<=prepared_second_address;
                    prepared_size<=prepared_second_size;
                    prepared_store<=prepared_second_store;
                    prepared_unsigned<=prepared_second_unsigned;
                    prepared_wdata<=prepared_second_wdata;
                    prepared_strobes<=prepared_second_strobes;
                    prepared_peripheral<=prepared_second_peripheral;
                        if(ex_memory_reservation)begin
                            prepared_second_valid<=1;
                    prepared_second_tag<=ex_tag0;
                    prepared_second_writes<=ex_writes0;
                    prepared_second_sequence<=ex_sequence0;
                    prepared_second_pc<=ex_pc0;
                    prepared_second_address<=e_address0;
                    prepared_second_size<=e_size0;
                    prepared_second_store<=e_store_enable0;
                    prepared_second_unsigned<=e_unsigned0;
                    prepared_second_wdata<=ex_shifted_store;
                    prepared_second_strobes<=ex_store_strobes;
                    prepared_second_peripheral<=ex_peripheral_proposal;
                        end else prepared_second_valid<=0;
                    end else if(ex_memory_reservation)begin
                        prepared_valid<=1;
                    prepared_tag<=ex_tag0;
                    prepared_writes<=ex_writes0;
                    prepared_sequence<=ex_sequence0;
                    prepared_pc<=ex_pc0;
                    prepared_address<=e_address0;
                    prepared_size<=e_size0;
                    prepared_store<=e_store_enable0;
                    prepared_unsigned<=e_unsigned0;
                    prepared_wdata<=ex_shifted_store;
                    prepared_strobes<=ex_store_strobes;
                    prepared_peripheral<=ex_peripheral_proposal;
                    end else prepared_valid<=0;
                end else if(ex_memory_reservation&&!(active_handoff&&!prepared_valid))begin
                    if(!prepared_valid)begin
                        prepared_valid<=1;
                    prepared_tag<=ex_tag0;
                    prepared_writes<=ex_writes0;
                    prepared_sequence<=ex_sequence0;
                    prepared_pc<=ex_pc0;
                    prepared_address<=e_address0;
                    prepared_size<=e_size0;
                    prepared_store<=e_store_enable0;
                    prepared_unsigned<=e_unsigned0;
                    prepared_wdata<=ex_shifted_store;
                    prepared_strobes<=ex_store_strobes;
                    prepared_peripheral<=ex_peripheral_proposal;
                    end else begin
                        prepared_second_valid<=1;
                    prepared_second_tag<=ex_tag0;
                    prepared_second_writes<=ex_writes0;
                    prepared_second_sequence<=ex_sequence0;
                    prepared_second_pc<=ex_pc0;
                    prepared_second_address<=e_address0;
                    prepared_second_size<=e_size0;
                    prepared_second_store<=e_store_enable0;
                    prepared_second_unsigned<=e_unsigned0;
                    prepared_second_wdata<=ex_shifted_store;
                    prepared_second_strobes<=ex_store_strobes;
                    prepared_second_peripheral<=ex_peripheral_proposal;
                    end
                end
            end
            if(complete_legacy)mdu_active<=0;
            if(mdu_request&&mdu_ready)begin mdu_active<=1;mdu_tag<=ex_tag0;mdu_writes<=ex_writes0;mdu_sequence<=ex_sequence0;mdu_pc<=ex_pc0;end
            if(recovery)mdu_active<=0;

            if(recovery)begin
                rob_head<=0;rob_tail<=0;rob_count<=0;serial_pending<=0;
                ex_valid0<=0;ex_valid1<=0;
                for(r=0;r<16;r=r+1)begin rob_valid[r]<=0;end
    
                for(r=0;r<32;r=r+1)map_valid[r]<=0;
            end else begin
                rob_count<=rob_count+{3'b0,allocate_count}-{4'b0,retire0}-{4'b0,retire1};
                rob_head<=rob_head+{3'b0,retire0}+{3'b0,retire1};
                rob_tail<=rob_tail+{2'b0,allocate_count};
                if(ENABLE_TRACE)next_sequence<=next_sequence+{62'b0,allocate_count};
                else next_sequence<=0;
                if(retire0)rob_valid[rob_head]<=0;
                if(retire1)rob_valid[head1]<=0;
                for(r=0;r<12;r=r+1)begin
                    if(q_valid[r])begin
                        if(!q_left_ready[r]&&broadcast_available(q_left_tag[r]))begin q_left_ready[r]<=1;q_left[r]<=broadcast_value(q_left_tag[r]);end
                        if(!q_right_ready[r]&&broadcast_available(q_right_tag[r]))begin q_right_ready[r]<=1;q_right[r]<=broadcast_value(q_right_tag[r]);end
                    end
                end
                if(!ex_hold)ex_valid0<=issue_choice0>=0||dispatch_ex0>=0;
                ex_valid1<=issue_choice1>=0||dispatch_ex1>=0;
                if(allocate_count!=0)begin
                    rob_valid[rob_tail]<=1;
                    if(d_write0&&d_rd0!=0)begin map_valid[d_rd0]<=1;map_tag[d_rd0]<=rob_tail;end
                    if(d_serial0)serial_pending<=1;
                    if(!d_complex0)steer<=allocation_slot0<4;
                end
                if(allocate_count==2)begin
                    rob_valid[tail1]<=1;
                    if(d_write1&&d_rd1!=0)begin map_valid[d_rd1]<=1;map_tag[d_rd1]<=tail1;end
                    if(!d_complex1)steer<=allocation_slot1<4;
                end
            end
                if(dispatch_ex0>=0)begin
                    install_dispatch_execution(1'b0,dispatch_ex0==0?(d_write0&&d_rd0!=0):(d_write1&&d_rd1!=0),
                        dispatch_ex0==0?rob_tail:tail1,
                        dispatch_ex0==0?allocation_slot0:allocation_slot1,
                        dispatch_ex0==0?fetch_pc0:fetch_pc1,dispatch_ex0==0?fetch_instruction0:fetch_instruction1,
                        dispatch_ex0==0?dispatch_left0:dispatch_left1,
                        dispatch_ex0==0?dispatch_right0:dispatch_right1,
                        next_sequence+(dispatch_ex0==0?64'd0:64'd1));
                end
                if(dispatch_ex1>=0)begin
                    install_dispatch_execution(1'b1,dispatch_ex1==0?(d_write0&&d_rd0!=0):(d_write1&&d_rd1!=0),
                        dispatch_ex1==0?rob_tail:tail1,
                        dispatch_ex1==0?allocation_slot0:allocation_slot1,
                        dispatch_ex1==0?fetch_pc0:fetch_pc1,dispatch_ex1==0?fetch_instruction0:fetch_instruction1,
                        dispatch_ex1==0?dispatch_left0:dispatch_left1,
                        dispatch_ex1==0?dispatch_right0:dispatch_right1,
                        next_sequence+(dispatch_ex1==0?64'd0:64'd1));
                end
            // Selection proposes payload independently of commit recovery.
            // Recovery clears EX validity and all queue ownership above.
                if(issue_choice0>=0)begin
                    ex_tag0<=issue_tag_value(issue_choice0);
                    ex_writes0<=issue_write_value(issue_choice0);
                    ex_sequence0<=rob_sequence[issue_tag_value(issue_choice0)];
                    ex_pc0<=ORDERED_SCHEDULER?ordered_pc0:read_rob_pc(issue_tag_value(issue_choice0));ex_instruction0<=ORDERED_SCHEDULER?ordered_instruction0:read_rob_instruction(issue_tag_value(issue_choice0));
                    ex_left0<=(ORDERED_SCHEDULER?ordered_left0:issue_left_value(issue_choice0));ex_right0<=(ORDERED_SCHEDULER?ordered_right0:issue_right_value(issue_choice0));
                    debug_issue_tag0<=issue_tag_value(issue_choice0);debug_issue_sequence0<=rob_sequence[issue_tag_value(issue_choice0)];debug_issue_pc0<=read_rob_pc(issue_tag_value(issue_choice0));
                end
                if(issue_choice1>=0)begin
                    ex_tag1<=issue_tag_value(issue_choice1);
                    ex_writes1<=issue_write_value(issue_choice1);
                    ex_sequence1<=rob_sequence[issue_tag_value(issue_choice1)];
                    ex_pc1<=ORDERED_SCHEDULER?ordered_pc1:read_rob_pc(issue_tag_value(issue_choice1));ex_instruction1<=ORDERED_SCHEDULER?ordered_instruction1:read_rob_instruction(issue_tag_value(issue_choice1));
                    ex_left1<=(ORDERED_SCHEDULER?ordered_left1:issue_left_value(issue_choice1));ex_right1<=(ORDERED_SCHEDULER?ordered_right1:issue_right_value(issue_choice1));
                    debug_issue_tag1<=issue_tag_value(issue_choice1);debug_issue_sequence1<=rob_sequence[issue_tag_value(issue_choice1)];debug_issue_pc1<=read_rob_pc(issue_tag_value(issue_choice1));
                end
            // ROB targets are pre-edge free; queue grants follow their policy.
            // Payload does not grant validity or rename ownership.
            // Keep this outside recovery gating to bound the initialization
            // control path. Recovery above clears every consumer's validity.
            if(allocation_offer_count!=0)begin
                initialize_allocation_payload(rob_tail,allocation_slot0,fetch_pc0,fetch_instruction0,fetch_prediction0,fetch_error0,
                        d_write0,d_mem0,d_store0,d_mdu0,d_serial0,d_complex0,d_bad0,d_rd0,
                        allocation_left0,allocation_right0,allocation_ltag0,allocation_rtag0,next_sequence);
            end
            if(allocation_offer_count==2)begin
                initialize_allocation_payload(tail1,allocation_slot1,fetch_pc1,fetch_instruction1,fetch_prediction1,fetch_error1,
                        d_write1,d_mem1,d_store1,d_mdu1,d_serial1,d_complex1,d_bad1,d_rd1,
                        allocation_left1,allocation_right1,allocation_ltag1,allocation_rtag1,next_sequence+64'd1);
            end
        end
    end
endmodule
