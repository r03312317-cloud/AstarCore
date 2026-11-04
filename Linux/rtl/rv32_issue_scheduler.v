// Original RV32 S6 optimization. Two compatible issues from 8 integer
// and 4 complex slots. Slot order changes only on allocation, independently
// of current completion data, readiness and recovery acceptance.
// 调度器根据就绪操作数 年龄与资源资格选择当前可发射的队列槽位。
// 最多两个候选不意味着每拍一定发射两条，复杂单元与访存还有独立占用条件。
// 同一物理槽位不能同时交付两个执行通道，第二候选要排除第一候选。
// 旁路广播可让等待操作数变为就绪，但标签匹配必须对应仍然存活的生产者。
// 调度选择不改变程序顺序提交，访存顺序及不可逆副作用由核心外层另行把关。
// ACTIVE_QUEUE_MASK 下的物理身份保持固定，不能把裁剪后的槽位重新编号理解。
module rv32_issue_scheduler #(
    parameter FAST_WAKEUP=1,
    // ENABLE_PAIRING 控制双指令条件配对，仍受依赖和资源约束。
    parameter ENABLE_PAIRING=1,
    parameter LATE_SELECT=0,
    // The caller may establish this invariant at operand allocation/capture.
    // Generic callers retain the original readiness-qualified data muxes.
    parameter ZERO_UNREADY_OPERANDS=0,
    // ACTIVE_QUEUE_MASK 按固定物理槽位掩码裁剪发射队列，0x733 对应七个活动位置。
    parameter [11:0] ACTIVE_QUEUE_MASK=12'hfff
)(
    input clk,reset,
    // allocation_count 属于新分配候选，保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    // 仅在最终接收时获得持久所有者，提议不能提前占用架构状态。
    input [1:0] allocation_count,
    input [3:0] allocation_slot0,allocation_slot1,
    // left_ready 保存左源操作数已经可用的标志，标签存在不等于值已经可用。
    input [11:0] occupied,issue_allowed,left_ready,right_ready,
    input [47:0] left_tags,right_tags,
    input [383:0] left_values,right_values,
    // broadcast_valid 属于完成广播，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 消费者按生产者标签匹配，数值相同不能替代身份相同。
    input [2:0] broadcast_valid,
    input [11:0] broadcast_tags,
    input [95:0] broadcast_values,
    input ex_hold,
    // Only the select bit depends on the actual LSU response/hit. Each
    // counterfactual contains the exact tags/valids for that response case.
    input late_select,
    // alternate_valid0 保存有效资格，标识该项是否属于当前仍可使用的事务。
    input [2:0] alternate_valid0,alternate_valid1,
    input [11:0] alternate_tags0,alternate_tags1,
    output [11:0] eligible,issue_mask0,issue_mask1,
    output [11:0] case0_mask0,case0_mask1,case1_mask0,case1_mask1,
    // issue_valid0 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output issue_valid0,issue_valid1,
    output [3:0] issue_slot0,issue_slot1,
    // issue_left0 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    output [31:0] issue_left0,issue_right0,issue_left1,issue_right1,
    // Local complex-bank payload is prepared independently of global lane
    // arbitration. Ownership remains exclusively with the normal issue mask.
    output [3:0] complex_candidate_mask,
    // complex_candidate_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    output [31:0] complex_candidate_left,complex_candidate_right
);
    wire [11:0] older[0:11];
    reg [65:0] relative_order;
    wire [11:0] new0,new1;
    genvar i,j;
    generate for(i=0;i<12;i=i+1)begin:allocation_order
        // new0[i] 的资格组合为 allocation_count!=0&&allocation_slot0==i。
        // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
        assign new0[i]=allocation_count!=0&&allocation_slot0==i;
        // new1[i] 的资格组合为 allocation_count==2&&allocation_slot1==i。
        assign new1[i]=allocation_count==2&&allocation_slot1==i;
        for(j=0;j<12;j=j+1)begin:relation
            // Both new: port 0 precedes port 1. One new: every surviving
            // old owner precedes it. Relations involving invalid slots are
            // payload only; reallocation rewrites the whole row and column.
            if(i<j)begin:stored_relation
                // ORDER_INDEX 按 i*(23-i)/2+j-i-1 计算，运算位宽与有无符号以原声明和显式扩展为准。
                localparam ORDER_INDEX=i*(23-i)/2+j-i-1;
                always @(posedge clk)begin
                    // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
                    if(!ACTIVE_QUEUE_MASK[i]||!ACTIVE_QUEUE_MASK[j]||reset)relative_order[ORDER_INDEX]<=0;
                    else if(new0[i]||new1[i])relative_order[ORDER_INDEX]<=new0[i]&&new1[j];
                    else if(new0[j]||new1[j])relative_order[ORDER_INDEX]<=1;
                end
                assign older[i][j]=relative_order[ORDER_INDEX];
            end else if(i>j)begin:reverse_relation
                // ORDER_INDEX 按 j*(23-j)/2+i-j-1 计算，运算位宽与有无符号以原声明和显式扩展为准。
                localparam ORDER_INDEX=j*(23-j)/2+i-j-1;
                assign older[i][j]=!relative_order[ORDER_INDEX];
            end else begin:self_relation
                assign older[i][j]=0;
            end
        end
    end endgenerate

    wire [2:0] left_match[0:11],right_match[0:11];
    wire [11:0] eligible_actual,eligible_case0,eligible_case1;
    wire [143:0] order_flat;
    wire [11:0] mask00,mask01,mask10,mask11;
    generate for(i=0;i<12;i=i+1)begin:readiness
        // left0 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
        wire [2:0] left0,right0,left1,right1,actual_left,actual_right;
        for(j=0;j<12;j=j+1)begin:flatten_order
            assign order_flat[i*12+j]=older[i][j];
        end
        for(j=0;j<3;j=j+1)begin:channel
            // actual_left[j] 的资格组合为 FAST_WAKEUP&&broadcast_valid[j]&&left_tags[i*4+:4]==broadcast_tags[j*4+:4]。
            assign actual_left[j]=FAST_WAKEUP&&broadcast_valid[j]&&left_tags[i*4+:4]==broadcast_tags[j*4+:4];
            // actual_right[j] 的资格组合为 FAST_WAKEUP&&broadcast_valid[j]&&right_tags[i*4+:4]==broadcast_tags[j*4+:4]。
            assign actual_right[j]=FAST_WAKEUP&&broadcast_valid[j]&&right_tags[i*4+:4]==broadcast_tags[j*4+:4];
            assign left_match[i][j]=LATE_SELECT?(late_select?left1[j]:left0[j]):actual_left[j];
            assign right_match[i][j]=LATE_SELECT?(late_select?right1[j]:right0[j]):actual_right[j];
            // left0[j] 的资格组合为 FAST_WAKEUP&&alternate_valid0[j]&&left_tags[i*4+:4]==alternate_tags0[j*4+:4]。
            assign left0[j]=FAST_WAKEUP&&alternate_valid0[j]&&left_tags[i*4+:4]==alternate_tags0[j*4+:4];
            // right0[j] 的资格组合为 FAST_WAKEUP&&alternate_valid0[j]&&right_tags[i*4+:4]==alternate_tags0[j*4+:4]。
            assign right0[j]=FAST_WAKEUP&&alternate_valid0[j]&&right_tags[i*4+:4]==alternate_tags0[j*4+:4];
            // left1[j] 的资格组合为 FAST_WAKEUP&&alternate_valid1[j]&&left_tags[i*4+:4]==alternate_tags1[j*4+:4]。
            assign left1[j]=FAST_WAKEUP&&alternate_valid1[j]&&left_tags[i*4+:4]==alternate_tags1[j*4+:4];
            // right1[j] 的资格组合为 FAST_WAKEUP&&alternate_valid1[j]&&right_tags[i*4+:4]==alternate_tags1[j*4+:4]。
            assign right1[j]=FAST_WAKEUP&&alternate_valid1[j]&&right_tags[i*4+:4]==alternate_tags1[j*4+:4];
        end
        // eligible_actual[i] 的资格组合为 occupied[i]&&issue_allowed[i]&&。
        assign eligible_actual[i]=occupied[i]&&issue_allowed[i]&&
            (left_ready[i]||(|actual_left))&&(right_ready[i]||(|actual_right));
        assign eligible_case0[i]=LATE_SELECT?
            occupied[i]&&issue_allowed[i]&&(left_ready[i]||(|left0))&&(right_ready[i]||(|right0)):eligible_actual[i];
        // eligible_case1[i] 的资格组合为 occupied[i]&&issue_allowed[i]&&。
        assign eligible_case1[i]=occupied[i]&&issue_allowed[i]&&
            (left_ready[i]||(|left1))&&(right_ready[i]||(|right1));
    end endgenerate
    rv32_issue_rank #(.ENABLE_PAIRING(ENABLE_PAIRING)) rank0(
        .reset(reset),.ex_hold(ex_hold),.older(order_flat),.eligible(eligible_case0),.mask0(mask00),.mask1(mask01));
    generate if(LATE_SELECT)begin:late_case
        rv32_issue_rank #(.ENABLE_PAIRING(ENABLE_PAIRING)) rank1(
            .reset(reset),.ex_hold(ex_hold),.older(order_flat),.eligible(eligible_case1),.mask0(mask10),.mask1(mask11));
    end else begin:single_case
        assign mask10=12'b0;assign mask11=12'b0;
    end endgenerate
    // eligible 按 LATE_SELECT 进行来源选择。
    // 真分支取 (late_select?eligible_case1:eligible_case0)；其余情况取 eligible_actual。
    assign eligible=LATE_SELECT?(late_select?eligible_case1:eligible_case0):eligible_actual;
    // case0_mask0 连接到 mask00，两者在此路径上保持字段对应。
    assign case0_mask0=mask00;assign case0_mask1=mask01;
    // case1_mask0 连接到 mask10，两者在此路径上保持字段对应。
    assign case1_mask0=mask10;assign case1_mask1=mask11;
    // issue_mask0 按 LATE_SELECT&&late_select 进行来源选择。
    // 真分支取 mask10；其余情况取 mask00。
    assign issue_mask0=LATE_SELECT&&late_select?mask10:mask00;
    // issue_mask1 按 LATE_SELECT&&late_select 进行来源选择。
    // 真分支取 mask11；其余情况取 mask01。
    assign issue_mask1=LATE_SELECT&&late_select?mask11:mask01;
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&LATE_SELECT&&eligible!=eligible_actual)
        $fatal(1,"R51 counterfactual eligibility differs from actual completion-qualified eligibility");
`endif
    // TOPT: validity is a set-cardinality property, independent of age.
    // A legal order always has an oldest eligible owner. With two lanes,
    // either two integers or an integer plus one complex owner can issue.
    // A held EX0 still leaves EX1 available to one integer owner.
    function at_least_two_integer;
        input [7:0] mask;
        reg lo_many,hi_many;
        begin
            // lo_many 的资格组合为 (mask[0]&&mask[1])||(mask[2]&&mask[3])||。
            lo_many=(mask[0]&&mask[1])||(mask[2]&&mask[3])||
                    ((|mask[1:0])&&(|mask[3:2]));
            // hi_many 的资格组合为 (mask[4]&&mask[5])||(mask[6]&&mask[7])||。
            hi_many=(mask[4]&&mask[5])||(mask[6]&&mask[7])||
                    ((|mask[5:4])&&(|mask[7:6]));
            // at_least_two_integer 的资格组合为 lo_many||hi_many||((|mask[3:0])&&(|mask[7:4]))。
            at_least_two_integer=lo_many||hi_many||((|mask[3:0])&&(|mask[7:4]));
        end
    endfunction
    // issue_valid0 的资格组合为 !reset&&!ex_hold&&(|eligible)。
    assign issue_valid0=!reset&&!ex_hold&&(|eligible);
    // issue_valid1 的资格组合为 !reset&&ENABLE_PAIRING&&(|eligible[7:0])&&。
    assign issue_valid1=!reset&&ENABLE_PAIRING&&(|eligible[7:0])&&
        (ex_hold||(|eligible[11:8])||at_least_two_integer(eligible[7:0]));
`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(issue_valid0!=(|issue_mask0)||issue_valid1!=(|issue_mask1))
            $fatal(1,"TOPT age-independent issue validity differs from selected masks");
    end
`endif

    reg [3:0] encoded0,encoded1;
    // stored_left0 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [31:0] stored_left0,stored_right0,stored_left1,stored_right1;
    // forward_left0 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [2:0] forward_left0,forward_right0,forward_left1,forward_right1;
    integer row;
    always @*begin
        encoded0=0;encoded1=0;
        stored_left0=0;stored_right0=0;stored_left1=0;stored_right1=0;
        forward_left0=0;forward_right0=0;forward_left1=0;forward_right1=0;
        for(row=0;row<12;row=row+1)begin
            // encoded0 对 encoded0|({4{issue_mask0[row]}}&row[3:0]) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
            encoded0=encoded0|({4{issue_mask0[row]}}&row[3:0]);
            // encoded1 对 encoded1|({4{issue_mask1[row]}}&row[3:0]) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
            encoded1=encoded1|({4{issue_mask1[row]}}&row[3:0]);
            // stored_left0 的资格组合为 stored_left0|({32{issue_mask0[row]&&(ZERO_UNREADY_OPERANDS||left_ready[row])}}&left_values[row*32+:32])。
            stored_left0=stored_left0|({32{issue_mask0[row]&&(ZERO_UNREADY_OPERANDS||left_ready[row])}}&left_values[row*32+:32]);
            // stored_right0 的资格组合为 stored_right0|({32{issue_mask0[row]&&(ZERO_UNREADY_OPERANDS||right_ready[row])}}&right_values[row*32+:32])。
            stored_right0=stored_right0|({32{issue_mask0[row]&&(ZERO_UNREADY_OPERANDS||right_ready[row])}}&right_values[row*32+:32]);
            // stored_left1 的资格组合为 stored_left1|({32{issue_mask1[row]&&(ZERO_UNREADY_OPERANDS||left_ready[row])}}&left_values[row*32+:32])。
            stored_left1=stored_left1|({32{issue_mask1[row]&&(ZERO_UNREADY_OPERANDS||left_ready[row])}}&left_values[row*32+:32]);
            // stored_right1 的资格组合为 stored_right1|({32{issue_mask1[row]&&(ZERO_UNREADY_OPERANDS||right_ready[row])}}&right_values[row*32+:32])。
            stored_right1=stored_right1|({32{issue_mask1[row]&&(ZERO_UNREADY_OPERANDS||right_ready[row])}}&right_values[row*32+:32]);
            // Resolve channel priority with bits before the wide data mux.
            // Only four selected operands receive completion data.
            // forward_left0 的资格组合为 forward_left0|({3{issue_mask0[row]&&!left_ready[row]}}&。
            forward_left0=forward_left0|({3{issue_mask0[row]&&!left_ready[row]}}&
                {left_match[row][2],left_match[row][1]&&!left_match[row][2],left_match[row][0]&&!(|left_match[row][2:1])});
            // forward_right0 的资格组合为 forward_right0|({3{issue_mask0[row]&&!right_ready[row]}}&。
            forward_right0=forward_right0|({3{issue_mask0[row]&&!right_ready[row]}}&
                {right_match[row][2],right_match[row][1]&&!right_match[row][2],right_match[row][0]&&!(|right_match[row][2:1])});
            // forward_left1 的资格组合为 forward_left1|({3{issue_mask1[row]&&!left_ready[row]}}&。
            forward_left1=forward_left1|({3{issue_mask1[row]&&!left_ready[row]}}&
                {left_match[row][2],left_match[row][1]&&!left_match[row][2],left_match[row][0]&&!(|left_match[row][2:1])});
            // forward_right1 的资格组合为 forward_right1|({3{issue_mask1[row]&&!right_ready[row]}}&。
            forward_right1=forward_right1|({3{issue_mask1[row]&&!right_ready[row]}}&
                {right_match[row][2],right_match[row][1]&&!right_match[row][2],right_match[row][0]&&!(|right_match[row][2:1])});
        end
    end
    function [31:0] forwarded;
        input [2:0] channels;
        begin forwarded=({32{channels[0]}}&broadcast_values[31:0])|
            ({32{channels[1]}}&broadcast_values[63:32])|({32{channels[2]}}&broadcast_values[95:64]);end
    endfunction
    // issue_slot0 连接到 encoded0，两者在此路径上保持字段对应。
    assign issue_slot0=encoded0;
    // issue_slot1 连接到 encoded1，两者在此路径上保持字段对应。
    assign issue_slot1=encoded1;
    // issue_left0 对 stored_left0|forwarded(forward_left0) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    assign issue_left0=stored_left0|forwarded(forward_left0);
    // issue_right0 对 stored_right0|forwarded(forward_right0) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    assign issue_right0=stored_right0|forwarded(forward_right0);
    // issue_left1 对 stored_left1|forwarded(forward_left1) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    assign issue_left1=stored_left1|forwarded(forward_left1);
    // issue_right1 对 stored_right1|forwarded(forward_right1) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    assign issue_right1=stored_right1|forwarded(forward_right1);

    // TOPT2: the oldest eligible complex entry is always the selected complex
    // owner whenever EX0 admits one. Prepare that candidate before competing
    // with the eight integer entries. The DSP payload need not depend on
    // integer-bank readiness, choose_complex, EX0 validity or dispatch bypass.
    // Compute the two response cases before their late selection, just as the
    // existing issue path does. No new owner, credit or acceptance is created.
    wire [3:0] complex_local_case0,complex_local_case1;
    genvar local_entry,local_other;
    generate for(local_entry=0;local_entry<4;local_entry=local_entry+1)begin:local_complex_rank
        wire [3:0] local_older0,local_older1;
        for(local_other=0;local_other<4;local_other=local_other+1)begin:local_relation
            // local_older0[local_other] 的资格组合为 eligible_case0[8+local_other]&&older[8+local_other][8+local_entry]。
            assign local_older0[local_other]=eligible_case0[8+local_other]&&older[8+local_other][8+local_entry];
            // local_older1[local_other] 的资格组合为 eligible_case1[8+local_other]&&older[8+local_other][8+local_entry]。
            assign local_older1[local_other]=eligible_case1[8+local_other]&&older[8+local_other][8+local_entry];
        end
        // complex_local_case0[local_entry] 的资格组合为 eligible_case0[8+local_entry]&&!(|local_older0)。
        assign complex_local_case0[local_entry]=eligible_case0[8+local_entry]&&!(|local_older0);
        // complex_local_case1[local_entry] 的资格组合为 eligible_case1[8+local_entry]&&!(|local_older1)。
        assign complex_local_case1[local_entry]=eligible_case1[8+local_entry]&&!(|local_older1);
    end endgenerate
    // complex_candidate_mask 按 LATE_SELECT&&late_select 进行来源选择。
    // 真分支取 complex_local_case1；其余情况取 complex_local_case0。
    assign complex_candidate_mask=LATE_SELECT&&late_select?complex_local_case1:complex_local_case0;
    // complex_stored_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [31:0] complex_stored_left,complex_stored_right;
    // complex_forward_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [2:0] complex_forward_left,complex_forward_right;
    integer local_row;
    always @*begin
        complex_stored_left=0;complex_stored_right=0;
        complex_forward_left=0;complex_forward_right=0;
        for(local_row=8;local_row<12;local_row=local_row+1)begin
            // complex_stored_left 的资格组合为 complex_stored_left|({32{complex_candidate_mask[local_row-8]&&(ZERO_UNREADY_OPERANDS||left_ready[local_row])}}&left_values[local_row*32+:32])。
            complex_stored_left=complex_stored_left|({32{complex_candidate_mask[local_row-8]&&(ZERO_UNREADY_OPERANDS||left_ready[local_row])}}&left_values[local_row*32+:32]);
            // complex_stored_right 的资格组合为 complex_stored_right|({32{complex_candidate_mask[local_row-8]&&(ZERO_UNREADY_OPERANDS||right_ready[local_row])}}&right_values[local_row*32+:32])。
            complex_stored_right=complex_stored_right|({32{complex_candidate_mask[local_row-8]&&(ZERO_UNREADY_OPERANDS||right_ready[local_row])}}&right_values[local_row*32+:32]);
            // complex_forward_left 的资格组合为 complex_forward_left|({3{complex_candidate_mask[local_row-8]&&!left_ready[local_row]}}&。
            complex_forward_left=complex_forward_left|({3{complex_candidate_mask[local_row-8]&&!left_ready[local_row]}}&
                {left_match[local_row][2],left_match[local_row][1]&&!left_match[local_row][2],left_match[local_row][0]&&!(|left_match[local_row][2:1])});
            // complex_forward_right 的资格组合为 complex_forward_right|({3{complex_candidate_mask[local_row-8]&&!right_ready[local_row]}}&。
            complex_forward_right=complex_forward_right|({3{complex_candidate_mask[local_row-8]&&!right_ready[local_row]}}&
                {right_match[local_row][2],right_match[local_row][1]&&!right_match[local_row][2],right_match[local_row][0]&&!(|right_match[local_row][2:1])});
        end
    end
    // complex_candidate_left 对 complex_stored_left|forwarded(complex_forward_left) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    assign complex_candidate_left=complex_stored_left|forwarded(complex_forward_left);
    // complex_candidate_right 对 complex_stored_right|forwarded(complex_forward_right) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    assign complex_candidate_right=complex_stored_right|forwarded(complex_forward_right);
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&(|issue_mask0[11:8]))begin
        if(complex_candidate_mask!=issue_mask0[11:8]||
           complex_candidate_left!=issue_left0||complex_candidate_right!=issue_right0)
            $fatal(1,"TOPT2 local complex payload differs from admitted EX0 owner");
    end
`endif
`ifdef VERILATOR
    // reference_stored_left0 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [31:0] reference_stored_left0,reference_stored_right0,reference_stored_left1,reference_stored_right1;
    integer operand_reference_row;
    always @*begin
        reference_stored_left0=0;reference_stored_right0=0;
        reference_stored_left1=0;reference_stored_right1=0;
        for(operand_reference_row=0;operand_reference_row<12;operand_reference_row=operand_reference_row+1)begin
            // reference_stored_left0 的资格组合为 reference_stored_left0|({32{issue_mask0[operand_reference_row]&&left_ready[operand_reference_row]}}&left_values[operand_reference_row*32+:32])。
            reference_stored_left0=reference_stored_left0|({32{issue_mask0[operand_reference_row]&&left_ready[operand_reference_row]}}&left_values[operand_reference_row*32+:32]);
            // reference_stored_right0 的资格组合为 reference_stored_right0|({32{issue_mask0[operand_reference_row]&&right_ready[operand_reference_row]}}&right_values[operand_reference_row*32+:32])。
            reference_stored_right0=reference_stored_right0|({32{issue_mask0[operand_reference_row]&&right_ready[operand_reference_row]}}&right_values[operand_reference_row*32+:32]);
            // reference_stored_left1 的资格组合为 reference_stored_left1|({32{issue_mask1[operand_reference_row]&&left_ready[operand_reference_row]}}&left_values[operand_reference_row*32+:32])。
            reference_stored_left1=reference_stored_left1|({32{issue_mask1[operand_reference_row]&&left_ready[operand_reference_row]}}&left_values[operand_reference_row*32+:32]);
            // reference_stored_right1 的资格组合为 reference_stored_right1|({32{issue_mask1[operand_reference_row]&&right_ready[operand_reference_row]}}&right_values[operand_reference_row*32+:32])。
            reference_stored_right1=reference_stored_right1|({32{issue_mask1[operand_reference_row]&&right_ready[operand_reference_row]}}&right_values[operand_reference_row*32+:32]);
        end
    end
    integer operand_contract_row;
    always @(posedge clk)if(!reset&&ZERO_UNREADY_OPERANDS)begin
        for(operand_contract_row=0;operand_contract_row<12;operand_contract_row=operand_contract_row+1)
            if(occupied[operand_contract_row]&&
               ((!left_ready[operand_contract_row]&&left_values[operand_contract_row*32+:32]!=0)||
                (!right_ready[operand_contract_row]&&right_values[operand_contract_row*32+:32]!=0)))
                $fatal(1,"TOPT2 scheduler unready operand zero contract violated");
        if(issue_left0!=(reference_stored_left0|forwarded(forward_left0))||
           issue_right0!=(reference_stored_right0|forwarded(forward_right0))||
           issue_left1!=(reference_stored_left1|forwarded(forward_left1))||
           issue_right1!=(reference_stored_right1|forwarded(forward_right1)))
            $fatal(1,"TOPT2 selected operand differs from original ready-qualified mux");
    end
`endif
endmodule

// Pure oldest-compatible-set function. Both copies share the same registered
// order relations; no speculative completion changes queue ownership.
module rv32_issue_rank #(parameter ENABLE_PAIRING=1)(
    input reset,ex_hold,
    input [143:0] older,
    input [11:0] eligible,
    output [11:0] mask0,mask1
);
    wire [7:0] older_integer[0:11];
    wire [3:0] older_complex[0:11];
    wire [7:0] first_integer,second_integer;
    wire [3:0] first_complex,compatible_complex;
    function at_most_one;
        input [7:0] mask;
        reg lo_many,hi_many;
        begin
            // Balanced threshold tree: 0/1 among eight bits, no arithmetic
            // carry chain and no eight-way equality/decode OR.
            lo_many=(mask[0]&&mask[1])||(mask[2]&&mask[3])||
                    ((|mask[1:0])&&(|mask[3:2]));
            hi_many=(mask[4]&&mask[5])||(mask[6]&&mask[7])||
                    ((|mask[5:4])&&(|mask[7:6]));
            // at_most_one 的资格组合为 !(lo_many||hi_many||((|mask[3:0])&&(|mask[7:4])))。
            at_most_one=!(lo_many||hi_many||((|mask[3:0])&&(|mask[7:4])));
        end
    endfunction
    genvar i,j;
    generate for(i=0;i<12;i=i+1)begin:ranking
        for(j=0;j<8;j=j+1)begin:integer_age
            assign older_integer[i][j]=eligible[j]&&older[j*12+i];
        end
        for(j=0;j<4;j=j+1)begin:complex_age
            assign older_complex[i][j]=eligible[8+j]&&older[(8+j)*12+i];
        end
        if(i<8)begin:integer_masks
            // first_integer[i] 的资格组合为 eligible[i]&&!(|older_integer[i])。
            assign first_integer[i]=eligible[i]&&!(|older_integer[i]);
            assign second_integer[i]=eligible[i]&&(|older_integer[i])&&at_most_one(older_integer[i]);
        end else begin:complex_masks
            assign first_complex[i-8]=eligible[i]&&!(|older_complex[i]);
            // TOPT: existence of a compatible complex owner does not
            // require first finding the oldest complex owner. In a total
            // order, the oldest eligible complex has no more older eligible
            // integers than any later complex. Thus an eligible compatible
            // complex exists iff the oldest complex is compatible.
            // Keep first_complex only on the complex payload mask; remove
            // complex-to-complex age bits from the global lane choice.
            assign compatible_complex[i-8]=eligible[i]&&
                (ENABLE_PAIRING?at_most_one(older_integer[i]):!(|older_integer[i]));
        end
    end endgenerate
    // choose_complex 对 |compatible_complex 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire choose_complex=|compatible_complex;
    assign mask0=reset||ex_hold?12'b0:
        (choose_complex?{first_complex,8'b0}:{4'b0,first_integer});
    assign mask1=reset||!ENABLE_PAIRING?12'b0:
        (ex_hold||choose_complex?{4'b0,first_integer}:{4'b0,second_integer});
endmodule
