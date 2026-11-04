// Original RV32 frontend extraction; see docs/frontend_reuse.md.
// Eight queued instructions, up to four ordered fetch credits, and two predictor
// training ports. The consumer must pop only entries included in queue_count.
module rv32_ooo_frontend #(
    parameter [31:0] RESET_VECTOR=32'h80000000,
    parameter FETCH_CREDITS=2,
    parameter ENABLE_REDIRECT_FETCH=1,
    parameter ENABLE_COMMITTED_RAS=1,
    parameter RAS_DEPTH=16,
    parameter HISTORY_BITS=8,
    parameter BIMODAL_INDEX_BITS=7,
    parameter GSHARE_INDEX_BITS=8
)(
    input clk, reset,
    output imem_request_valid, input imem_request_ready,
    output [31:0] imem_request_address,
    input imem_response_valid, output imem_response_ready,
    input [63:0] imem_response_data, input [1:0] imem_response_error,
    input [1:0] imem_response_page_fault,
    input redirect, input [31:0] redirect_address,
    input maintenance_redirect,
    input [1:0] pop_count,
    output reg [3:0] queue_count,
    output [31:0] instruction0, instruction1,
    output [31:0] pc0, pc1, prediction0, prediction1,
    output error0, error1, output page_fault0,page_fault1,
    output illegal0, illegal1,
    output source_used10,source_used20,source_used11,source_used21,
    output serial0,serial1,complex0,complex1,
    output pc_dispatch_ok0,pc_dispatch_ok1,
    output prediction_sequential0,prediction_sequential1,
    output [HISTORY_BITS+1:0] prediction_context0,prediction_context1,
    input [HISTORY_BITS+1:0] train_context0,train_context1,
    output training_ready,
    output [HISTORY_BITS-1:0] committed_history,
    input [HISTORY_BITS-1:0] redirect_history,
    output [HISTORY_BITS-1:0] recovery_context0,recovery_context1,
    input train0, train1,
    input [31:0] train_instruction0,train_instruction1,
    input [31:0] train_pc0, train_pc1, train_next0, train_next1,
    input train_conditional0, train_conditional1,
    input train_history_taken0,train_history_taken1,
    input train_taken0, train_taken1
);
    // Two adjacent fetch words always address opposite parity banks.
    // Data payloads need one write port per bank and no reset circuitry.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] qi_even[0:3],qi_odd[0:3];
    reg [31:0] head_pc;
    reg [HISTORY_BITS-1:0] speculative_history;
    (* syn_ramstyle="distributed_ram" *) reg [HISTORY_BITS-1:0] qh_even[0:3],qh_odd[0:3];
    // Store an immutable relative-offset or absolute-target descriptor. PC
    // addition happens after this existing queue boundary, independently for
    // both head words, instead of BRAM data -> decode -> add -> queue write.
    (* syn_ramstyle="distributed_ram" *) reg [32:0] qd_even[0:3],qd_odd[0:3];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] qp_even[0:3],qp_odd[0:3];
    function [31:0] read_queue_instruction;
        input [2:0] tag;
        begin read_queue_instruction=tag[0]?qi_odd[tag[2:1]]:qi_even[tag[2:1]];end
    endfunction
    function [31:0] read_queue_prediction;
        input [2:0] tag;
        reg [32:0] descriptor;
        reg [31:0] location;
        begin
            descriptor=tag[0]?qd_odd[tag[2:1]]:qd_even[tag[2:1]];
            location=tag[0]?qp_odd[tag[2:1]]:qp_even[tag[2:1]];
            read_queue_prediction=descriptor[32]?location+descriptor[31:0]:descriptor[31:0];
        end
    endfunction
    (* syn_ramstyle="distributed_ram" *) reg [HISTORY_BITS+1:0] qc_even[0:3],qc_odd[0:3];
    reg queue_error [0:7]; reg queue_page_fault[0:7];
    reg queue_illegal[0:7];
    reg [1:0] queue_source_use[0:7];
    function [1:0] classify_sources;
        input [31:0] insn;
        reg [6:0] op;
        reg [2:0] sub;
        begin
            op=insn[6:0];sub=insn[14:12];
            classify_sources[0]=(op==47||op==103||op==99||op==3||op==35||op==19||op==51||
                (op==115&&sub!=0&&!sub[2]));
            classify_sources[1]=((op==47&&insn[31:27]!=2)||op==99||op==35||(op==51&&
                !(insn[31:25]==4&&sub==4&&insn[24:20]==0)));
        end
    endfunction
    reg queue_serial[0:7],queue_complex[0:7];
    reg queue_pc_dispatch_ok[0:7],queue_prediction_sequential[0:7];
    function dispatch_pc_usable;
        input [31:0] location;
        begin dispatch_pc_usable=location[1:0]==0;end
    endfunction
    function classify_serial;
        input [31:0] insn;
        begin
            classify_serial=0;
            case(insn[6:0])
                7'b0101111:classify_serial=1;
                7'b0001111:classify_serial=insn[14:12]==0||insn[14:12]==1||insn==32'h0000500f;
                7'b1110011:begin
                    if(insn[14:12]!=0)classify_serial=1;
                    else case(insn)
                        32'h00000073,32'h00100073,32'h30200073,32'h10200073,32'h10500073:classify_serial=1;
                        default:classify_serial=(insn&32'hfe007fff)==32'h12000073;
                    endcase
                end
            endcase
        end
    endfunction
    function classify_complex;
        input [31:0] insn;
        begin classify_complex=classify_serial(insn)||insn[6:0]==7'b0000011||
            insn[6:0]==7'b0100011||(insn[6:0]==7'b0110011&&insn[31:25]==7'b0000001);end
    endfunction
    reg [2:0] queue_head, queue_tail;
    wire [2:0] second_index=queue_head+3'd1;
    // Head and successor address opposite banks. Express one read address
    // per bank so the compiler need not replicate each tiny RAM read port.
    wire [1:0] even_read_index=queue_head[0]?second_index[2:1]:queue_head[2:1];
    wire [1:0] odd_read_index=queue_head[2:1];
    wire [31:0] even_instruction=qi_even[even_read_index],odd_instruction=qi_odd[odd_read_index];
    wire [32:0] even_descriptor=qd_even[even_read_index],odd_descriptor=qd_odd[odd_read_index];
    wire [31:0] even_pc=qp_even[even_read_index],odd_pc=qp_odd[odd_read_index];
    wire [31:0] even_prediction=even_descriptor[32]?even_pc+even_descriptor[31:0]:even_descriptor[31:0];
    wire [31:0] odd_prediction=odd_descriptor[32]?odd_pc+odd_descriptor[31:0]:odd_descriptor[31:0];
    wire [31:0] stored_pc0=queue_head[0]?odd_pc:even_pc,stored_pc1=queue_head[0]?even_pc:odd_pc;
    assign instruction0=queue_head[0]?odd_instruction:even_instruction;
    assign instruction1=queue_head[0]?even_instruction:odd_instruction;
    assign prediction0=queue_head[0]?odd_prediction:even_prediction;
    assign prediction1=queue_head[0]?even_prediction:odd_prediction;
    assign recovery_context0=queue_head[0]?qh_odd[odd_read_index]:qh_even[even_read_index];
    assign recovery_context1=queue_head[0]?qh_even[even_read_index]:qh_odd[odd_read_index];
    assign prediction_context0=queue_head[0]?qc_odd[odd_read_index]:qc_even[even_read_index];
    assign prediction_context1=queue_head[0]?qc_even[even_read_index]:qc_odd[odd_read_index];
    assign pc0=head_pc;
    assign pc1=prediction0;
    assign {source_used20,source_used10}=queue_source_use[queue_head];
    assign {source_used21,source_used11}=queue_source_use[second_index];
    assign illegal0=queue_illegal[queue_head];
    assign illegal1=queue_illegal[second_index];
    assign error0=queue_error[queue_head];
    assign page_fault0=queue_page_fault[queue_head];
    assign page_fault1=queue_page_fault[second_index];
    assign error1=queue_error[second_index];
    assign serial0=queue_serial[queue_head];
    assign serial1=queue_serial[second_index];
    assign complex0=queue_complex[queue_head];
    assign complex1=queue_complex[second_index];
    // Each queued word receives its own actual response PC class before the
    // head mux. The second head PC need not traverse prediction RAM + region
    // comparison before a current dispatch can grant an EX owner.
    assign pc_dispatch_ok0=queue_pc_dispatch_ok[queue_head];
    assign pc_dispatch_ok1=queue_pc_dispatch_ok[second_index];
    assign prediction_sequential0=queue_prediction_sequential[queue_head];
    assign prediction_sequential1=queue_prediction_sequential[second_index];
`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(queue_count>0&&(stored_pc0!=pc0||prediction_sequential0!=(prediction0==pc0+32'd4)))
            $fatal(1,"R34 first prediction descriptor PC/sequence mismatch");
        if(queue_count>1&&(stored_pc1!=pc1||prediction_sequential1!=(prediction1==pc1+32'd4)))
            $fatal(1,"R34 second prediction descriptor PC/sequence mismatch");
    end
`endif

    // Tagged 64-entry trained next-PC table with sequential cold prediction.
    reg predictor_valid [0:63];
    // Preserve the full 64-entry predictor and both ordered training ports.
    // Each lane writes its own RAM; the owner bit chooses the newest packet.
    (* syn_ramstyle="distributed_ram" *) reg [23:0] predictor_tag0[0:63],predictor_tag1[0:63];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] predictor_target0[0:63],predictor_target1[0:63];
    reg predictor_owner[0:63];
    function [23:0] read_predictor_tag;
        input [5:0] index;
        begin read_predictor_tag=predictor_owner[index]?predictor_tag1[index]:predictor_tag0[index];end
    endfunction
    function [31:0] read_predictor_target;
        input [5:0] index;
        begin read_predictor_target=predictor_owner[index]?predictor_target1[index]:predictor_target0[index];end
    endfunction
    always @(posedge clk)begin
        if(btb_train0&&!reset)begin predictor_tag0[train_pc0[7:2]]<=train_pc0[31:8];predictor_target0[train_pc0[7:2]]<=train_next0;end
        if(btb_train1&&!reset)begin predictor_tag1[train_pc1[7:2]]<=train_pc1[31:8];predictor_target1[train_pc1[7:2]]<=train_next1;end
    end
    // The tagged64-entry target table remains; direction uses the R45
    // untagged tournament tables. Not-taken branches never replace a target.
    reg predictor_conditional[0:63];
    // BTB metadata distinguishes zero-immediate return hints from generic
    // indirect jumps. The last-target table remains the empty-RAS fallback.
    reg predictor_return[0:63];
    wire committed_ras_valid;
    wire [31:0] committed_ras_top;
    wire use_committed_ras=ENABLE_COMMITTED_RAS&&committed_ras_valid;
    rv32_committed_ras #(.DEPTH(RAS_DEPTH)) return_stack(
        .clk(clk),.reset(reset),.train0(ENABLE_COMMITTED_RAS&&train0),.train1(ENABLE_COMMITTED_RAS&&train1),
        .instruction0(train_instruction0),.instruction1(train_instruction1),
        .pc0(train_pc0),.pc1(train_pc1),.valid(committed_ras_valid),.top(committed_ras_top),.occupancy());
    function ras_return;
        input [31:0] insn;
        reg destination_link,source_link;
        begin
            destination_link=insn[11:7]==1||insn[11:7]==5;
            source_link=insn[19:15]==1||insn[19:15]==5;
            // Nonzero offsets still update the stack according to the ISA
            // hint, but predict through BTB to avoid an extra target adder.
            ras_return=insn[6:0]==7'b1100111&&insn[14:12]==0&&insn[31:20]==0&&
                source_link&&(!destination_link||insn[11:7]!=insn[19:15]);
        end
    endfunction
    function [31:0] predict_indirect;
        input [31:0] insn,location;
        begin predict_indirect=(use_committed_ras&&ras_return(insn))?
            committed_ras_top:read_predictor_target(location[7:2]);end
    endfunction
    wire btb_train0=train0&&(!train_conditional0||train_taken0);
    wire btb_train1=train1&&(!train_conditional1||train_taken1);
    wire predictor_initialized;
    wire [31:0] normal_address;
    reg [31:0] response_pc,response_pc4,response_pc8;
    wire hybrid_early0,hybrid_early1,hybrid_response0,hybrid_response1;
    wire [HISTORY_BITS+1:0] hybrid_context_early0,hybrid_context_early1;
    wire [HISTORY_BITS+1:0] hybrid_context_response0,hybrid_context_response1;
    rv32_hybrid_predictor #(.BIMODAL_INDEX_BITS(BIMODAL_INDEX_BITS),
        .GSHARE_INDEX_BITS(GSHARE_INDEX_BITS),.HISTORY_BITS(HISTORY_BITS)) direction_predictor(
        .clk(clk),.reset(reset),
        .query_history(speculative_history),.committed_history(committed_history),
        .pc0(normal_address),.pc1(normal_address+32'd4),.pc2(response_pc),.pc3(response_pc4),
        .taken0(hybrid_early0),.taken1(hybrid_early1),.taken2(hybrid_response0),.taken3(hybrid_response1),
        .context0(hybrid_context_early0),.context1(hybrid_context_early1),
        .context2(hybrid_context_response0),.context3(hybrid_context_response1),
        .train0(train0&&train_conditional0),.train1(train1&&train_conditional1),
        .train_pc0(train_pc0),.train_pc1(train_pc1),
        .train_context0(train_context0),.train_context1(train_context1),
        .train_taken0(train_taken0),.train_taken1(train_taken1),
        .train_history_taken0(train_history_taken0),.train_history_taken1(train_history_taken1),
        .initialized(predictor_initialized),.train_ready(training_ready)
    );
    // Predict from a trained target before cache data arrives. Request-time
    // predictions travel with each fetch, so the queued PC chain is stable
    // even if retirement trains the table before that response returns.
    function [31:0] predict_early;
        input [31:0] location;
        input hybrid_taken;
        begin
            if(predictor_valid[location[7:2]]&&read_predictor_tag(location[7:2])==location[31:8]&&
               (!predictor_conditional[location[7:2]]||hybrid_taken))
                predict_early=(use_committed_ras&&predictor_return[location[7:2]])?committed_ras_top:read_predictor_target(location[7:2]);
            else predict_early=location+32'd4;
        end
    endfunction
    function [31:0] predict_next;
        input [31:0] insn, location, sequential_location;
        input hybrid_taken;
        reg [31:0] offset;
        reg guess;
        begin
            predict_next=sequential_location;
            if(insn[6:0]==7'b1101111) begin
                offset={{11{insn[31]}},insn[31],insn[19:12],insn[20],insn[30:21],1'b0};
                predict_next=location+offset;
            end else if(insn[6:0]==7'b1100011) begin
                offset={{19{insn[31]}},insn[31],insn[7],insn[30:25],insn[11:8],1'b0};
                guess=hybrid_taken;
                if(guess) predict_next=location+offset;
            end else if(insn[6:0]==7'b1100111 && ((use_committed_ras&&ras_return(insn))||
                (predictor_valid[location[7:2]]&&read_predictor_tag(location[7:2])==location[31:8])))
                predict_next=predict_indirect(insn,location);
        end
    endfunction

    // Exactly the original response-time prediction, represented without
    // doing its PC-relative addition on the instruction BRAM output path.
    // Direction and trained indirect targets are captured now, not reread
    // when a queued word is consumed later.
    function [32:0] predict_descriptor;
        input [31:0] insn,location;
        input hybrid_taken;
        reg [31:0] offset;
        reg hit,guess;
        begin
            predict_descriptor={1'b1,32'd4};
            hit=predictor_valid[location[7:2]]&&read_predictor_tag(location[7:2])==location[31:8];
            guess=hybrid_taken;
            if(insn[6:0]==7'b1101111)begin
                offset={{11{insn[31]}},insn[31],insn[19:12],insn[20],insn[30:21],1'b0};
                predict_descriptor={1'b1,offset};
            end else if(insn[6:0]==7'b1100011&&guess)begin
                offset={{19{insn[31]}},insn[31],insn[7],insn[30:25],insn[11:8],1'b0};
                predict_descriptor={1'b1,offset};
            end else if(insn[6:0]==7'b1100111&&(hit||(use_committed_ras&&ras_return(insn))))
                predict_descriptor={1'b0,predict_indirect(insn,location)};
        end
    endfunction

    // Modular PC+offset == snapshot iff offset == snapshot-PC. Both
    // registered head PCs/snapshots settle before instruction RAM data. Decode
    // the two facts directly, avoiding target-add -> 32-bit compare -> ready.
    function [1:0] prediction_facts;
        input [31:0] insn,location,sequential_location,snapshot,snapshot_delta;
        input hybrid_taken;
        reg hit,guess;
        reg [31:0] jump_offset,branch_offset,target;
        begin
            hit=predictor_valid[location[7:2]]&&read_predictor_tag(location[7:2])==location[31:8];
            guess=hybrid_taken;
            target=predict_indirect(insn,location);
            jump_offset={{11{insn[31]}},insn[31],insn[19:12],insn[20],insn[30:21],1'b0};
            branch_offset={{19{insn[31]}},insn[31],insn[7],insn[30:25],insn[11:8],1'b0};
            prediction_facts={1'b1,snapshot_delta==32'd4};
            case(insn[6:0])
                7'b1101111:prediction_facts={jump_offset==32'd4,jump_offset==snapshot_delta};
                7'b1100011:if(guess)prediction_facts={branch_offset==32'd4,branch_offset==snapshot_delta};
                7'b1100111:if(hit||(use_committed_ras&&ras_return(insn)))prediction_facts={target==sequential_location,target==snapshot};
                default:begin end
            endcase
        end
    endfunction

    reg fetch_epoch,fetch_hold,fetch_hold_epoch,fetch_hold_killed;
    reg [31:0] fetch_cursor,fetch_hold_address;
    reg correction_pending;
    reg [32:0] correction_descriptor0,correction_descriptor1;
    reg [31:0] correction_pc0,correction_pc1;
    reg correction_second;
    wire [32:0] correction_descriptor=correction_second?correction_descriptor1:correction_descriptor0;
    wire [31:0] correction_pc=correction_second?correction_pc1:correction_pc0;
    wire [31:0] correction_target=correction_descriptor[32]?correction_pc+correction_descriptor[31:0]:correction_descriptor[31:0];
    // Existing correction payload boundary, no extra cycle. Capture both
    // word descriptors/bases independently; select and add after the edge.
    always @(posedge clk)begin
        correction_descriptor0<=response_descriptor0;correction_descriptor1<=response_descriptor1;
        correction_pc0<=response_pc;correction_pc1<=response_pc4;correction_second<=response_words[1];
    end
`ifdef VERILATOR
    reg [31:0] prior_correction_target;
    always @(posedge clk)begin
        prior_correction_target<=response_next;
        if(!reset&&correction_pending&&correction_target!=prior_correction_target)
            $fatal(1,"R34 correction descriptor differs from prior full target");
    end
`endif
    reg [1:0] pending_head,pending_tail;
    reg [2:0] pending_count;
    reg [3:0] pending_active;
    wire [3:0] live_pending;
    // Each live accepted fetch reserves two words. Registered ownership,
    // sticky cancellation and epoch already encode this capacity exactly;
    // no instruction-decode-driven counter clear is needed.
    wire [4:0] reserved_words={3'b0,live_pending[0],1'b0}+{3'b0,live_pending[1],1'b0}+
        {3'b0,live_pending[2],1'b0}+{3'b0,live_pending[3],1'b0};
    reg pending_epoch[0:3],pending_killed[0:3];
    reg pending_pair[0:3];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] pending_pc[0:3],pending_prediction0[0:3],pending_prediction1[0:3];
    reg [31:0] response_snapshot0,response_snapshot1;
    wire [31:0] response_delta0=response_snapshot0-response_pc;
    wire [31:0] response_delta1=response_snapshot1-response_pc4;
    wire [1:0] response_successor=pending_head+2'd1;
    // Cache the current ring head before it is used for decode/prediction.
    // A one-item pop/push bypasses the just-written RAM cell explicitly.
    always @(posedge clk)begin
        if(reset)begin
            response_pc<=RESET_VECTOR;response_pc4<=RESET_VECTOR+32'd4;response_pc8<=RESET_VECTOR+32'd8;
            response_snapshot0<=RESET_VECTOR+32'd4;response_snapshot1<=RESET_VECTOR+32'd8;
        end
        else if(response_transfer&&pending_count>1)begin
            response_pc<=pending_pc[response_successor];
            response_pc4<=pending_pc[response_successor]+32'd4;
            response_pc8<=pending_pc[response_successor]+32'd8;
            response_snapshot0<=pending_prediction0[response_successor];response_snapshot1<=pending_prediction1[response_successor];
        end else if(request_transfer&&(pending_count==0||(response_transfer&&pending_count==1)))begin
            response_pc<=imem_request_address;response_pc4<=imem_request_address+32'd4;response_pc8<=imem_request_address+32'd8;
            response_snapshot0<=request_prediction0;response_snapshot1<=request_prediction1;
        end
    end
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&pending_count!=0)begin
        if(response_pc!=pending_pc[pending_head]||response_pc4!=response_pc+32'd4||response_pc8!=response_pc+32'd8)
            $fatal(1,"R18 pending head PC cache mismatch");
        if(response_snapshot0!=pending_prediction0[pending_head]||response_snapshot1!=pending_prediction1[pending_head])
            $fatal(1,"R22 pending head snapshot cache mismatch");
    end
`endif
    wire redirect_offer=ENABLE_REDIRECT_FETCH&&redirect&&!maintenance_redirect;
    // Normal BTB reads depend exclusively on registered cursor/held PCs.
    // A fresh architectural redirect accepts immediately with a sequential
    // snapshot; instruction-based response prediction corrects it if needed.
    // Redirect selection never steers the normal BTB read address.
    assign normal_address=fetch_hold?fetch_hold_address:fetch_cursor;
    wire fresh_redirect=redirect_offer&&!fetch_hold;
    // Registered continuation proposal settles independently of current
    // architectural recovery. A fresh recovery has final mux priority; when
    // recovery cannot present a request, this private address is immaterial.
    wire correction_offer=correction_pending;
    wire fresh_correction=correction_offer&&!fetch_hold;
    wire [31:0] continuation_address=fetch_hold?fetch_hold_address:
        (correction_pending?correction_target:fetch_cursor);
    assign imem_request_address=fresh_redirect?redirect_address:continuation_address;
    wire [31:0] normal_prediction0=predict_early(normal_address,hybrid_early0);
    wire [31:0] normal_prediction1=predict_early(normal_address+32'd4,hybrid_early1);
    wire [1:0] normal_words=(normal_prediction0==normal_address+32'd4)?2'd2:2'd1;
    wire [31:0] normal_next=normal_words==2?normal_prediction1:normal_prediction0;
    wire [31:0] request_prediction0=fresh_redirect?redirect_address+32'd4:
        (fresh_correction?correction_target+32'd4:normal_prediction0);
    wire [31:0] request_prediction1=fresh_redirect?redirect_address+32'd8:
        (fresh_correction?correction_target+32'd8:normal_prediction1);
    wire [1:0] request_words=(fresh_redirect||fresh_correction)?2'd2:normal_words;
    wire [31:0] request_next=fresh_redirect?redirect_address+32'd8:
        (fresh_correction?correction_target+32'd8:normal_next);
`ifdef VERILATOR
    wire prior_fresh_correction=correction_pending&&!redirect&&!fetch_hold;
    wire prior_fresh_restart=fresh_redirect||prior_fresh_correction;
    wire [31:0] prior_restart_address=fresh_redirect?redirect_address:correction_target;
    wire [31:0] prior_offered_address=prior_fresh_restart?prior_restart_address:normal_address;
    wire [31:0] prior_request_prediction0=prior_fresh_restart?prior_restart_address+32'd4:normal_prediction0;
    wire [31:0] prior_request_prediction1=prior_fresh_restart?prior_restart_address+32'd8:normal_prediction1;
    wire [31:0] prior_request_next=prior_fresh_restart?prior_restart_address+32'd8:normal_next;
    wire [1:0] prior_request_words=prior_fresh_restart?2'd2:normal_words;
    always @(posedge clk)if(!reset&&imem_request_valid)begin
        if(imem_request_address!=prior_offered_address||request_prediction0!=prior_request_prediction0||
           request_prediction1!=prior_request_prediction1||request_next!=prior_request_next||request_words!=prior_request_words)
            $fatal(1,"R33 presented fetch proposal differs from prior recovery/continuation mux");
    end
`endif
    assign imem_response_ready=!reset&&pending_count!=0;
    wire response_transfer=imem_response_ready&&imem_response_valid;
    wire response_current=response_transfer&&!pending_killed[pending_head]&&pending_epoch[pending_head]==fetch_epoch;
    // The original instruction-only legality decoder feeds immutable queue
    // metadata at the existing response/FIFO boundary. Unused ALU outputs
    // have no consumers. No new fetch or dispatch cycle is introduced.
    wire response_illegal0,response_illegal1;
    rv32_instruction_flags response_flags0(.instruction(imem_response_data[31:0]),.illegal(response_illegal0));
    rv32_instruction_flags response_flags1(.instruction(imem_response_data[63:32]),.illegal(response_illegal1));
`ifdef VERILATOR
    wire response_illegal_reference0,response_illegal_reference1;
    rv32_execute response_decode0(.instruction(imem_response_data[31:0]),.pc(32'b0),
        .left(32'b0),.right(32'b0),.csr_value(32'b0),.illegal(response_illegal_reference0));
    rv32_execute response_decode1(.instruction(imem_response_data[63:32]),.pc(32'b0),
        .left(32'b0),.right(32'b0),.csr_value(32'b0),.illegal(response_illegal_reference1));
    always @(posedge clk)if(!reset&&response_transfer)begin
        if(response_illegal0!=response_illegal_reference0||response_illegal1!=response_illegal_reference1)
            $fatal(1,"R41 parallel response legality differs from original execution decoder");
    end
`endif
    wire [32:0] response_descriptor0=predict_descriptor(imem_response_data[31:0],response_pc,hybrid_response0);
    wire [32:0] response_descriptor1=predict_descriptor(imem_response_data[63:32],response_pc4,hybrid_response1);
    wire [31:0] predicted0=predict_next(imem_response_data[31:0],response_pc,response_pc4,hybrid_response0);
    wire [31:0] predicted1=predict_next(imem_response_data[63:32],response_pc4,response_pc8,hybrid_response1);
    wire [1:0] prediction_facts0=prediction_facts(imem_response_data[31:0],response_pc,response_pc4,response_snapshot0,response_delta0,hybrid_response0);
    wire [1:0] prediction_facts1=prediction_facts(imem_response_data[63:32],response_pc4,response_pc8,response_snapshot1,response_delta1,hybrid_response1);
    wire [1:0] response_words=(prediction_facts0[1]&&!imem_response_error[0]) ? 2'd2 : 2'd1;
    wire [31:0] response_next=response_words==2?predicted1:predicted0;
    // Preserve older queued words, append this packet with its decoded PC
    // chain, cancel all younger accepted/held packets, and restart next edge.
    // Cofactor by the registered expected packet size. A size mismatch
    // already cancels, so second-word matching may use the expected pair bit
    // instead of waiting for the freshly decoded first word's pair decision.
    wire packet_prediction_matches=prediction_facts0[0]&&
        (pending_pair[pending_head]?(response_words[1]&&prediction_facts1[0]):!response_words[1]);
    wire local_correction=response_current&&!redirect&&!packet_prediction_matches;
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&response_current)begin
        if((response_descriptor0[32]?response_pc+response_descriptor0[31:0]:response_descriptor0[31:0])!=predicted0||
           (response_descriptor1[32]?response_pc4+response_descriptor1[31:0]:response_descriptor1[31:0])!=predicted1)
            $fatal(1,"R34 descriptor differs from original instruction predictor");
        if(prediction_facts0!={(predicted0==response_pc4),(predicted0==pending_prediction0[pending_head])})
            $fatal(1,"R22 first prediction facts differ from original full-PC comparisons");
        if(prediction_facts1!={(predicted1==response_pc8),(predicted1==pending_prediction1[pending_head])})
            $fatal(1,"R22 second prediction facts differ from original full-PC comparisons");
    end
`endif
    wire [1:0] payload_push_count=response_current?response_words:2'd0;
    wire [1:0] push_count=redirect?2'd0:payload_push_count;
    // Both words query the same packet history. The recovery checkpoint of
    // word1 includes word0's predicted conditional outcome; training retains
    // the exact query history in the independent10-bit prediction context.
    wire [HISTORY_BITS-1:0] speculative_after0=(imem_response_data[6:0]==7'b1100011&&!imem_response_error[0])?
        {speculative_history[HISTORY_BITS-2:0],(hybrid_response0&&
          {imem_response_data[31],imem_response_data[7],imem_response_data[30:25],imem_response_data[11:8],1'b0}!=13'd4)}:speculative_history;
    wire [HISTORY_BITS-1:0] speculative_after1=(imem_response_data[38:32]==7'b1100011&&!imem_response_error[1])?
        {speculative_after0[HISTORY_BITS-2:0],(hybrid_response1&&
          {imem_response_data[63],imem_response_data[39],imem_response_data[62:57],imem_response_data[43:40],1'b0}!=13'd4)}:speculative_after0;
    always @(posedge clk)begin
        if(reset)speculative_history<=0;
        else if(redirect)speculative_history<=redirect_history;
        else if(push_count!=0)speculative_history<=push_count==2?speculative_after1:speculative_after0;
    end
    wire [4:0] occupied_words={1'b0,queue_count}+reserved_words-{3'b0,pop_count};
    // An old-path offer may transfer on the detection edge. Mark it killed
    // explicitly; neither ready nor its cursor advance depends on decode.
    wire candidate_valid=!reset&&predictor_initialized&&(!redirect||redirect_offer)&&
        (pending_count<FETCH_CREDITS||response_transfer)&&
        // A presented offer may wait while predictor training changes its
        // private word count. Reserve the full external two-word capacity.
        (redirect_offer||occupied_words+5'd2<=5'd8);
    assign imem_request_valid=!reset&&predictor_initialized&&(fetch_hold||candidate_valid);
    wire request_transfer=imem_request_valid&&imem_request_ready;
    wire request_epoch=fetch_hold?fetch_hold_epoch:(redirect_offer?!fetch_epoch:fetch_epoch);
    wire request_killed=fetch_hold?(fetch_hold_killed||redirect||local_correction):local_correction;
    wire request_live=!request_killed&&request_epoch==(redirect?!fetch_epoch:fetch_epoch);
    // A cursor value computed from an offer on the detection edge is private:
    // correction_pending selects the registered target during the next cycle
    // and installs it on the next edge. Do not gate this proposal by the late
    // local-correction decision. Actual request ownership still uses killed.
    // A held request cancelled earlier or by architectural recovery cannot
    // override that recovery/registered target with an old cursor proposal.
    wire cursor_proposal_live=!(fetch_hold&&(fetch_hold_killed||redirect))&&
        request_epoch==(redirect?!fetch_epoch:fetch_epoch);
    wire [4:0] projected_count={1'b0,queue_count}+{3'b0,push_count}-{3'b0,pop_count};
    wire [2:0] pair_tail=queue_tail+3'd1;
    // Classification is immutable instruction payload. Its validity follows
    // the existing queue ownership, including cancellation and both errors.
    always @(posedge clk)begin
        if(payload_push_count!=0)begin
            queue_illegal[queue_tail]<=response_illegal0;
            queue_source_use[queue_tail]<=classify_sources(imem_response_data[31:0]);
            queue_pc_dispatch_ok[queue_tail]<=dispatch_pc_usable(response_pc);
            queue_prediction_sequential[queue_tail]<=prediction_facts0[1];
            queue_serial[queue_tail]<=classify_serial(imem_response_data[31:0]);
            queue_complex[queue_tail]<=classify_complex(imem_response_data[31:0]);
        end
        if(payload_push_count==2)begin
            queue_illegal[pair_tail]<=response_illegal1;
            queue_source_use[pair_tail]<=classify_sources(imem_response_data[63:32]);
            queue_pc_dispatch_ok[pair_tail]<=dispatch_pc_usable(response_pc4);
            queue_prediction_sequential[pair_tail]<=prediction_facts1[1];
            queue_serial[pair_tail]<=classify_serial(imem_response_data[63:32]);
            queue_complex[pair_tail]<=classify_complex(imem_response_data[63:32]);
        end
    end
    // Writing a cancelled payload does not grant queue ownership. These RAM
    // enables do not depend on the current retirement recovery decision.
    always @(posedge clk)begin
        if(payload_push_count!=0&&(!queue_tail[0]||payload_push_count==2))begin
            qh_even[queue_tail[0]?pair_tail[2:1]:queue_tail[2:1]]<=queue_tail[0]?speculative_after0:speculative_history;
            qc_even[queue_tail[0]?pair_tail[2:1]:queue_tail[2:1]]<=queue_tail[0]?hybrid_context_response1:hybrid_context_response0;
            qi_even[queue_tail[0]?pair_tail[2:1]:queue_tail[2:1]]<=queue_tail[0]?imem_response_data[63:32]:imem_response_data[31:0];
            qd_even[queue_tail[0]?pair_tail[2:1]:queue_tail[2:1]]<=queue_tail[0]?response_descriptor1:response_descriptor0;
            qp_even[queue_tail[0]?pair_tail[2:1]:queue_tail[2:1]]<=queue_tail[0]?response_pc4:response_pc;
        end
        if(payload_push_count!=0&&(queue_tail[0]||payload_push_count==2))begin
            qh_odd[queue_tail[0]?queue_tail[2:1]:pair_tail[2:1]]<=queue_tail[0]?speculative_history:speculative_after0;
            qc_odd[queue_tail[0]?queue_tail[2:1]:pair_tail[2:1]]<=queue_tail[0]?hybrid_context_response0:hybrid_context_response1;
            qi_odd[queue_tail[0]?queue_tail[2:1]:pair_tail[2:1]]<=queue_tail[0]?imem_response_data[31:0]:imem_response_data[63:32];
            qd_odd[queue_tail[0]?queue_tail[2:1]:pair_tail[2:1]]<=queue_tail[0]?response_descriptor0:response_descriptor1;
            qp_odd[queue_tail[0]?queue_tail[2:1]:pair_tail[2:1]]<=queue_tail[0]?response_pc:response_pc4;
        end
        // The tail is free unless all four physical slots are owned. A
        // simultaneous pop also frees the full-ring tail/head; the current
        // response uses its cached head payload before this edge. Writing an
        // unaccepted proposal grants no owner and cannot overwrite any other
        // live slot. Every possible actual transfer satisfies this predicate.
        if(private_pending_write)begin
            pending_pc[pending_tail]<=imem_request_address;
            pending_pair[pending_tail]<=request_words[1];
            pending_prediction0[pending_tail]<=request_prediction0;
            pending_prediction1[pending_tail]<=request_prediction1;
        end
    end
    wire private_pending_write=!reset&&(pending_count<4||response_transfer);
    always @(posedge clk)begin
        if(reset)begin fetch_hold_address<=RESET_VECTOR;fetch_hold_epoch<=0;end
        else if(!fetch_hold)begin
            // Free held-offer storage may capture a proposal every edge. The
            // original valid/stall rule alone creates held ownership.
            fetch_hold_address<=imem_request_address;fetch_hold_epoch<=request_epoch;
        end
    end
`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(request_transfer&&!private_pending_write)$fatal(1,"R31 accepted fetch had no free payload slot");
        if(private_pending_write&&pending_active[pending_tail]&&!(response_transfer&&pending_head==pending_tail))
            $fatal(1,"R31 private payload would overwrite an owned fetch");
    end
`endif
    genvar reservation_row;
    generate for(reservation_row=0;reservation_row<4;reservation_row=reservation_row+1)begin:reservation_owners
        wire accepting=request_transfer&&pending_tail==reservation_row;
        wire consuming=response_transfer&&pending_head==reservation_row;
        always @(posedge clk)begin
            if(reset)pending_active[reservation_row]<=0;
            else pending_active[reservation_row]<=accepting||(pending_active[reservation_row]&&!consuming);
        end
        assign live_pending[reservation_row]=pending_active[reservation_row]&&
            !pending_killed[reservation_row]&&pending_epoch[reservation_row]==fetch_epoch;
    end endgenerate
`ifdef VERILATOR
    reg [4:0] prior_reserved_words;
    reg [1:0] prior_pending_words[0:3];
    integer prior_reservation_row;
    wire prior_local_correction=response_current&&!redirect&&
        (response_words!=prior_pending_words[pending_head]||!prediction_facts0[0]||
        (response_words==2&&!prediction_facts1[0]));
    wire [2:0] active_pending_count={2'b0,pending_active[0]}+{2'b0,pending_active[1]}+
        {2'b0,pending_active[2]}+{2'b0,pending_active[3]};
    always @(posedge clk)begin
        if(reset)begin
            prior_reserved_words<=0;
            for(prior_reservation_row=0;prior_reservation_row<4;prior_reservation_row=prior_reservation_row+1)prior_pending_words[prior_reservation_row]<=0;
        end else begin
            if(redirect)prior_reserved_words<=request_transfer&&request_live?5'd2:5'd0;
            else if(local_correction)prior_reserved_words<=0;
            else prior_reserved_words<=prior_reserved_words+(request_transfer&&request_live?5'd2:5'd0)-(response_current?5'd2:5'd0);
            if(request_transfer)prior_pending_words[pending_tail]<=request_words;
            if(reserved_words!=prior_reserved_words)$fatal(1,"R31 reserved capacity differs from prior counter");
            if(active_pending_count!=pending_count)$fatal(1,"R31 active fetch owner count mismatch");
            if(pending_count!=0&&!pending_active[pending_head])$fatal(1,"R31 pending head has no owner");
            if(prior_local_correction!=local_correction)$fatal(1,"R31 pair-bit correction differs from prior word count");
        end
    end
`endif
    // A late decoded correction sets each cancellation bit directly. Do
    // not carry it through request_killed and a second array-write priority
    // mux. Only a newly accepted architectural redirect survives a redirect.
    genvar cancel_row;
    generate for(cancel_row=0;cancel_row<4;cancel_row=cancel_row+1)begin:cancel_owners
        wire new_owner=request_transfer&&pending_tail==cancel_row;
        wire fresh_architectural_owner=new_owner&&!fetch_hold&&redirect_offer;
        wire old_hold_killed=fetch_hold&&fetch_hold_killed;
        always @(posedge clk)begin
            if(reset)pending_killed[cancel_row]<=0;
            else pending_killed[cancel_row]<=!fresh_architectural_owner&&
                (redirect||local_correction||(new_owner?old_hold_killed:pending_killed[cancel_row]));
        end
    end endgenerate
    // An unowned hold payload is immaterial. This single expression makes
    // cancellation sticky for old held offers and for a new correction-edge
    // held offer, without a late priority-select chain.
    always @(posedge clk)begin
        if(reset)fetch_hold_killed<=0;
        else fetch_hold_killed<=local_correction||(fetch_hold&&(fetch_hold_killed||redirect));
    end
`ifdef VERILATOR
    reg prior_pending_killed[0:3],prior_hold_killed;
    integer prior_cancel_row;
    always @(posedge clk)begin
        if(reset)begin
            for(prior_cancel_row=0;prior_cancel_row<4;prior_cancel_row=prior_cancel_row+1)prior_pending_killed[prior_cancel_row]<=0;
            prior_hold_killed<=0;
        end else begin
            // Exact prior priority-write rule, kept only as an equivalence
            // reference. All pending bits agree; hold bit agrees when owned.
            if(redirect||local_correction)begin
                for(prior_cancel_row=0;prior_cancel_row<4;prior_cancel_row=prior_cancel_row+1)prior_pending_killed[prior_cancel_row]<=1;
                if(fetch_hold)prior_hold_killed<=1;
            end
            if(request_transfer)prior_pending_killed[pending_tail]<=request_killed;
            else if(imem_request_valid&&!fetch_hold)prior_hold_killed<=local_correction;
            for(prior_cancel_row=0;prior_cancel_row<4;prior_cancel_row=prior_cancel_row+1)
                if(pending_killed[prior_cancel_row]!=prior_pending_killed[prior_cancel_row])$fatal(1,"R30 sticky pending cancellation mismatch");
            if(fetch_hold&&fetch_hold_killed!=prior_hold_killed)$fatal(1,"R30 owned held cancellation mismatch");
        end
    end
`endif
    integer r;
    always @(posedge clk)begin
        if(reset)begin
            queue_head<=0;queue_tail<=0;queue_count<=0;head_pc<=RESET_VECTOR;
            fetch_epoch<=0;fetch_hold<=0;
            fetch_cursor<=RESET_VECTOR;correction_pending<=0;
            pending_head<=0;pending_tail<=0;pending_count<=0;
            for(r=0;r<4;r=r+1)begin pending_epoch[r]<=0;end
            for(r=0;r<64;r=r+1)begin predictor_valid[r]<=0;predictor_owner[r]<=0;predictor_conditional[r]<=0;predictor_return[r]<=0;end
        end else begin
            correction_pending<=local_correction;
            // Recovery below has priority. A live accepted restart advances
            // to its own snapshot after this registered-target proposal.
            if(correction_pending)fetch_cursor<=correction_target;
            if(btb_train0)begin
                predictor_valid[train_pc0[7:2]]<=1;predictor_owner[train_pc0[7:2]]<=0;
                predictor_conditional[train_pc0[7:2]]<=train_conditional0;
                predictor_return[train_pc0[7:2]]<=ras_return(train_instruction0);
            end
            if(btb_train1)begin
                predictor_valid[train_pc1[7:2]]<=1;predictor_owner[train_pc1[7:2]]<=1;
                predictor_conditional[train_pc1[7:2]]<=train_conditional1;
                predictor_return[train_pc1[7:2]]<=ras_return(train_instruction1);
            end
            pending_count<=pending_count+{2'b0,request_transfer}-{2'b0,response_transfer};
            if(response_transfer)pending_head<=pending_head+2'd1;
            if(redirect)begin
                fetch_epoch<=!fetch_epoch;fetch_cursor<=redirect_address;
                queue_head<=0;queue_tail<=0;queue_count<=0;
            end else begin
                queue_head<=queue_head+{1'b0,pop_count};
                queue_tail<=queue_tail+{1'b0,push_count};
                queue_count<=projected_count[3:0];
                if(push_count!=0)begin queue_error[queue_tail]<=imem_response_error[0];queue_page_fault[queue_tail]<=imem_response_page_fault[0];end
                if(push_count==2)begin queue_error[pair_tail]<=imem_response_error[1];queue_page_fault[pair_tail]<=imem_response_page_fault[1];end
                if(local_correction)begin
                    fetch_epoch<=!fetch_epoch;
                end
            end
            // The anchor is payload, valid only with queue_count. Recovery
            // invalidates the queue; the first fresh response re-establishes it.
            if(queue_count==0&&payload_push_count!=0)head_pc<=response_pc;
            if(pop_count==1)head_pc<=prediction0;
            if(pop_count==2)head_pc<=prediction1;
            if(request_transfer)begin
                pending_tail<=pending_tail+2'd1;
                pending_epoch[pending_tail]<=request_epoch;
                fetch_hold<=0;
                if(cursor_proposal_live)fetch_cursor<=request_next;
            end else if(imem_request_valid&&!fetch_hold)begin
                fetch_hold<=1;
            end
        end
    end
endmodule

// Read-only diagnostic control for the earlier single-credit contract.
// Original RV32 frontend extraction; see docs/frontend_reuse.md.
// Eight queued instructions, one outstanding fetch, and two ordered predictor
// training ports. The consumer must pop only entries included in queue_count.
module rv32_ooo_frontend_serial #(
    parameter [31:0] RESET_VECTOR=32'h80000000,
    parameter ENABLE_REDIRECT_FETCH=1
)(
    input clk, reset,
    output imem_request_valid, input imem_request_ready,
    output [31:0] imem_request_address,
    input imem_response_valid, output imem_response_ready,
    input [63:0] imem_response_data, input [1:0] imem_response_error,
    input [1:0] imem_response_page_fault,
    input redirect, input [31:0] redirect_address,
    input maintenance_redirect,
    input [1:0] pop_count,
    output reg [3:0] queue_count,
    output [31:0] instruction0, instruction1,
    output [31:0] pc0, pc1, prediction0, prediction1,
    output error0, error1, output page_fault0,page_fault1,
    input train0, train1,
    input [31:0] train_pc0, train_pc1, train_next0, train_next1,
    input train_conditional0, train_conditional1,
    input train_taken0, train_taken1
);
    // Two adjacent fetch words always address opposite parity banks.
    // Data payloads need one write port per bank and no reset circuitry.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] qi_even[0:3],qi_odd[0:3];
    reg [31:0] head_pc;
    (* syn_ramstyle="distributed_ram" *) reg [31:0] qn_even[0:3],qn_odd[0:3];
    function [31:0] read_queue_instruction;
        input [2:0] tag;
        begin read_queue_instruction=tag[0]?qi_odd[tag[2:1]]:qi_even[tag[2:1]];end
    endfunction
    function [31:0] read_queue_prediction;
        input [2:0] tag;
        begin read_queue_prediction=tag[0]?qn_odd[tag[2:1]]:qn_even[tag[2:1]];end
    endfunction
    reg queue_error [0:7]; reg queue_page_fault[0:7];
    reg [2:0] queue_head, queue_tail;
    wire [2:0] second_index=queue_head+3'd1;
    // Head and successor address opposite banks. Express one read address
    // per bank so the compiler need not replicate each tiny RAM read port.
    wire [1:0] even_read_index=queue_head[0]?second_index[2:1]:queue_head[2:1];
    wire [1:0] odd_read_index=queue_head[2:1];
    wire [31:0] even_instruction=qi_even[even_read_index],odd_instruction=qi_odd[odd_read_index];
    wire [31:0] even_prediction=qn_even[even_read_index],odd_prediction=qn_odd[odd_read_index];
    assign instruction0=queue_head[0]?odd_instruction:even_instruction;
    assign instruction1=queue_head[0]?even_instruction:odd_instruction;
    assign prediction0=queue_head[0]?odd_prediction:even_prediction;
    assign prediction1=queue_head[0]?even_prediction:odd_prediction;
    assign pc0=head_pc;
    assign pc1=prediction0;
    assign error0=queue_error[queue_head];
    assign page_fault0=queue_page_fault[queue_head];
    assign page_fault1=queue_page_fault[second_index];
    assign error1=queue_error[second_index];

    // Tagged 64-entry direction/target table. Conditional misses use static
    // backward prediction; direct jumps use their instruction immediate.
    reg predictor_valid [0:63];
    // Preserve the full 64-entry predictor and both ordered training ports.
    // Each lane writes its own RAM; the owner bit chooses the newest packet.
    (* syn_ramstyle="distributed_ram" *) reg [23:0] predictor_tag0[0:63],predictor_tag1[0:63];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] predictor_target0[0:63],predictor_target1[0:63];
    reg predictor_owner[0:63];
    function [23:0] read_predictor_tag;
        input [5:0] index;
        begin read_predictor_tag=predictor_owner[index]?predictor_tag1[index]:predictor_tag0[index];end
    endfunction
    function [31:0] read_predictor_target;
        input [5:0] index;
        begin read_predictor_target=predictor_owner[index]?predictor_target1[index]:predictor_target0[index];end
    endfunction
    always @(posedge clk)begin
        if(train0&&!reset)begin predictor_tag0[train_pc0[7:2]]<=train_pc0[31:8];predictor_target0[train_pc0[7:2]]<=train_next0;end
        if(train1&&!reset)begin predictor_tag1[train_pc1[7:2]]<=train_pc1[31:8];predictor_target1[train_pc1[7:2]]<=train_next1;end
    end
    reg [1:0] predictor_strength [0:63];
    function [31:0] predict_next;
        input [31:0] insn, location;
        reg [31:0] offset;
        reg guess;
        begin
            predict_next=location+32'd4;
            if(insn[6:0]==7'b1101111) begin
                offset={{11{insn[31]}},insn[31],insn[19:12],insn[20],insn[30:21],1'b0};
                predict_next=location+offset;
            end else if(insn[6:0]==7'b1100011) begin
                offset={{19{insn[31]}},insn[31],insn[7],insn[30:25],insn[11:8],1'b0};
                guess=(predictor_valid[location[7:2]] && read_predictor_tag(location[7:2])==location[31:8])?
                      predictor_strength[location[7:2]][1]:insn[31];
                if(guess) predict_next=location+offset;
            end else if(insn[6:0]==7'b1100111 && predictor_valid[location[7:2]] && read_predictor_tag(location[7:2])==location[31:8])
                predict_next=read_predictor_target(location[7:2]);
        end
    endfunction

    function [1:0] train_strength;
        input hit;
        input [1:0] previous;
        input conditional, taken;
        begin
            if(!conditional) train_strength=2'd3;
            else if(!hit) train_strength=taken?2'd2:2'd1;
            else if(taken && previous!=2'd3) train_strength=previous+2'd1;
            else if(!taken && previous!=2'd0) train_strength=previous-2'd1;
            else train_strength=previous;
        end
    endfunction
    wire [1:0] trained_strength0=train_strength(
        predictor_valid[train_pc0[7:2]] && read_predictor_tag(train_pc0[7:2])==train_pc0[31:8],
        predictor_strength[train_pc0[7:2]], train_conditional0, train_taken0);
    // Ordered retirement may contain two dynamic instances of one branch, or
    // two PCs which map to one entry. Port 1 observes port 0's updated entry.
    wire train_same_index=train0 && train_pc0[7:2]==train_pc1[7:2];
    wire train_hit1=train_same_index?(train_pc0[31:8]==train_pc1[31:8]):
        (predictor_valid[train_pc1[7:2]] && read_predictor_tag(train_pc1[7:2])==train_pc1[31:8]);
    wire [1:0] trained_strength1=train_strength(train_hit1,
        train_same_index?trained_strength0:predictor_strength[train_pc1[7:2]],
        train_conditional1, train_taken1);

    reg fetch_epoch, fetch_pending, fetch_pending_epoch, fetch_pending_killed;
    reg [31:0] fetch_cursor, fetch_pending_pc;
    reg fetch_hold, fetch_hold_epoch, fetch_hold_killed;
    reg [31:0] fetch_hold_address;
    wire response_transfer=fetch_pending && imem_response_valid;
    wire response_current=response_transfer && !fetch_pending_killed && fetch_pending_epoch==fetch_epoch;
    wire [31:0] predicted0=predict_next(imem_response_data[31:0],fetch_pending_pc);
    wire [31:0] predicted1=predict_next(imem_response_data[63:32],fetch_pending_pc+32'd4);
    wire response_pair=predicted0==fetch_pending_pc+32'd4 && !imem_response_error[0];
    wire [1:0] push_count=response_current&&!redirect?(response_pair?2'd2:2'd1):2'd0;
    wire [31:0] response_next=response_pair?predicted1:predicted0;
    // A fresh redirect request uses the new path immediately when the old
    // credit is free. Cache maintenance is visible to the wrapper only after
    // this edge, so maintenance redirects retain the conservative start.
    wire redirect_offer=ENABLE_REDIRECT_FETCH&&redirect&&!maintenance_redirect;
    wire [31:0] candidate_address=redirect_offer?redirect_address:(response_current?response_next:fetch_cursor);
    wire [4:0] projected_count={1'b0,queue_count}+{3'b0,push_count}-{3'b0,pop_count};
    // Reserve room for both words before presenting a request. When a response
    // drains, its predicted successor may be accepted on the very same edge.
    wire candidate_valid=!reset&&(!redirect||redirect_offer)&&(!fetch_pending||imem_response_valid)&&
                         (redirect_offer||projected_count<=5'd6);
    assign imem_request_valid=!reset&&(fetch_hold||candidate_valid);
    assign imem_request_address=fetch_hold?fetch_hold_address:candidate_address;
    wire request_epoch=fetch_hold?fetch_hold_epoch:(redirect_offer?!fetch_epoch:fetch_epoch);
    wire request_transfer=imem_request_valid&&imem_request_ready;
    assign imem_response_ready=!reset&&fetch_pending;

    wire [2:0] pair_tail=queue_tail+3'd1;
    always @(posedge clk)begin
        if(push_count!=0&&(!queue_tail[0]||push_count==2))begin
            qi_even[queue_tail[0]?pair_tail[2:1]:queue_tail[2:1]]<=queue_tail[0]?imem_response_data[63:32]:imem_response_data[31:0];
            qn_even[queue_tail[0]?pair_tail[2:1]:queue_tail[2:1]]<=queue_tail[0]?predicted1:predicted0;
        end
        if(push_count!=0&&(queue_tail[0]||push_count==2))begin
            qi_odd[queue_tail[0]?queue_tail[2:1]:pair_tail[2:1]]<=queue_tail[0]?imem_response_data[31:0]:imem_response_data[63:32];
            qn_odd[queue_tail[0]?queue_tail[2:1]:pair_tail[2:1]]<=queue_tail[0]?predicted0:predicted1;
        end
    end
    integer r;
    always @(posedge clk) begin
        if(reset) begin
            queue_head<=0;queue_tail<=0;queue_count<=0;head_pc<=RESET_VECTOR;
            fetch_epoch<=0;fetch_pending<=0;fetch_pending_epoch<=0;fetch_pending_killed<=0;fetch_pending_pc<=RESET_VECTOR;
            fetch_cursor<=RESET_VECTOR;fetch_hold<=0;fetch_hold_epoch<=0;fetch_hold_killed<=0;fetch_hold_address<=RESET_VECTOR;
            for(r=0;r<64;r=r+1) begin
                predictor_valid[r]<=0;predictor_owner[r]<=0;predictor_strength[r]<=2'd1;
            end
        end else begin
            if(train0) begin
                predictor_valid[train_pc0[7:2]]<=1;
                predictor_owner[train_pc0[7:2]]<=1'b0;
                predictor_strength[train_pc0[7:2]]<=trained_strength0;
            end
            if(train1) begin
                predictor_valid[train_pc1[7:2]]<=1;
                predictor_owner[train_pc1[7:2]]<=1'b1;
                predictor_strength[train_pc1[7:2]]<=trained_strength1;
            end
            if(redirect) begin
                fetch_epoch<=!fetch_epoch;fetch_cursor<=redirect_address;
                // Sticky cancellation survives any number of redirects while
                // a held offer or an accepted old request waits to drain.
                if(fetch_pending)fetch_pending_killed<=1;
                if(fetch_hold)fetch_hold_killed<=1;
                queue_head<=0;queue_tail<=0;queue_count<=0;head_pc<=redirect_address;
            end else begin
                queue_count<=projected_count[3:0];
                if(queue_count==0&&push_count!=0)head_pc<=fetch_pending_pc;
                if(pop_count==1)head_pc<=prediction0;
                if(pop_count==2)head_pc<=prediction1;
                queue_head<=queue_head+{1'b0,pop_count};
                queue_tail<=queue_tail+{1'b0,push_count};
                if(push_count!=0) begin
                    
                    
                    
                    queue_error[queue_tail]<=imem_response_error[0];queue_page_fault[queue_tail]<=imem_response_page_fault[0];
                end
                if(push_count==2) begin
                    
                    
                    
                    queue_error[queue_tail+3'd1]<=imem_response_error[1];queue_page_fault[queue_tail+3'd1]<=imem_response_page_fault[1];
                end
                if(response_current) fetch_cursor<=response_next;
            end
            // These assignments deliberately follow recovery. A response on a
            // redirect edge still drains, and an accepted held offer retains
            // cancellation even when acceptance coincides with the redirect. A fresh
            // redirect offer instead installs the new epoch with killed clear.
            if(response_transfer) fetch_pending<=0;
            if(request_transfer) begin
                fetch_pending<=1;
                fetch_pending_pc<=imem_request_address;
                fetch_pending_epoch<=request_epoch;
                fetch_pending_killed<=fetch_hold&&(fetch_hold_killed||redirect);
                fetch_hold<=0;
            end else if(imem_request_valid&&!fetch_hold) begin
                fetch_hold<=1;
                fetch_hold_address<=imem_request_address;
                fetch_hold_epoch<=request_epoch;
                fetch_hold_killed<=0;
            end
        end
    end
endmodule
