// [ARCH] 从就绪候选中选择最多两个包，同时保持银行和功能单元资源约束。
// [ARCH] 环形 tag 的数值大小不能替代指令年龄比较。
// [ARCH] 允许的整数借用路径可以利用另一银行空闲通路，复杂操作仍受资源限制。
// [ARCH] 已经保持的 EX 包不能被新候选覆盖，尤其是乘法背压下的 EX0。
// [ARCH] 访存顺序过滤与源操作数就绪是独立条件，需要同时满足。
// [ARCH] 分配绕过与队列发射在同一通路上互斥，避免双重所有者。
// [ARCH] 恢复取消最终接纳，但不应反向控制所有宽载荷提案。
// Original RV32 S6 optimization. Two compatible issues from 8 integer
// and 4 complex slots. Slot order changes only on allocation, independently
// of current completion data, readiness and recovery acceptance.
module rv32_issue_scheduler #(
    // [ARCH] FAST_WAKEUP：允许使用有效完成广播尽早解析依赖，不改变生产者身份匹配。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 actual_left, actual_right, left0, right0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter FAST_WAKEUP=1,
    // [ARCH] ENABLE_PAIRING：控制双通路准入能力；第二条仍需要通过资源、依赖和异常条件。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 issue_valid1 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter ENABLE_PAIRING=1,
    parameter LATE_SELECT=0,
    // The caller may establish this invariant at operand allocation/capture.
    // Generic callers retain the original readiness-qualified data muxes.
    parameter ZERO_UNREADY_OPERANDS=0,
    // [ARCH] ACTIVE_QUEUE_MASK：0x733 仅启用 7 个队列编号，最大逻辑编号不等于有效容量。
    parameter [11:0] ACTIVE_QUEUE_MASK=12'hfff
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input clk,reset,
    // [ARCH] allocation_count（分配提案）：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 new0, new1 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input [1:0] allocation_count,
    input [3:0] allocation_slot0,allocation_slot1,
    input [11:0] occupied,issue_allowed,left_ready,right_ready,
    // [ARCH] left_tags：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 actual_left, left0, left1 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input [47:0] left_tags,right_tags,
    // [ARCH] left_values：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 stored_left0, stored_left1, complex_stored_left, reference_stored_left0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input [383:0] left_values,right_values,
    // [ARCH] broadcast_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 actual_left, actual_right 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input [2:0] broadcast_valid,
    input [11:0] broadcast_tags,
    input [95:0] broadcast_values,
    input ex_hold,
    // Only the select bit depends on the actual LSU response/hit. Each
    // counterfactual contains the exact tags/valids for that response case.
    input late_select,
    // [ARCH] alternate_valid0：标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 left0, right0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input [2:0] alternate_valid0,alternate_valid1,
    input [11:0] alternate_tags0,alternate_tags1,
    output [11:0] eligible,issue_mask0,issue_mask1,
    output [11:0] case0_mask0,case0_mask1,case1_mask0,case1_mask1,
    // [ARCH] issue_valid0：标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。
    output issue_valid0,issue_valid1,
    output [3:0] issue_slot0,issue_slot1,
    // [ARCH] issue_left0：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    output [31:0] issue_left0,issue_right0,issue_left1,issue_right1,
    // Local complex-bank payload is prepared independently of global lane
    // arbitration. Ownership remains exclusively with the normal issue mask.
    output [3:0] complex_candidate_mask,
    // [ARCH] complex_candidate_left：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    output [31:0] complex_candidate_left,complex_candidate_right
);
    wire [11:0] older[0:11];
    reg [65:0] relative_order;
    wire [11:0] new0,new1;
    genvar i,j;
    generate for(i=0;i<12;i=i+1)begin:allocation_order
        assign new0[i]=allocation_count!=0&&allocation_slot0==i;
        assign new1[i]=allocation_count==2&&allocation_slot1==i;
        for(j=0;j<12;j=j+1)begin:relation
            // Both new: port 0 precedes port 1. One new: every surviving
            // old owner precedes it. Relations involving invalid slots are
            // payload only; reallocation rewrites the whole row and column.
            if(i<j)begin:stored_relation
                // [ARCH] ORDER_INDEX：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
                // [ARCH] 定位线索：原版中含此标识符的物理行还对 ACTIVE_QUEUE_MASK, new0, older 赋值；同一行可能含多个语句，不能据此单独推断依赖。
                localparam ORDER_INDEX=i*(23-i)/2+j-i-1;
                always @(posedge clk)begin
                    if(!ACTIVE_QUEUE_MASK[i]||!ACTIVE_QUEUE_MASK[j]||reset)relative_order[ORDER_INDEX]<=0;
                    else if(new0[i]||new1[i])relative_order[ORDER_INDEX]<=new0[i]&&new1[j];
                    else if(new0[j]||new1[j])relative_order[ORDER_INDEX]<=1;
                end
                assign older[i][j]=relative_order[ORDER_INDEX];
            end else if(i>j)begin:reverse_relation
                // [ARCH] ORDER_INDEX：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
                // [ARCH] 定位线索：原版中含此标识符的物理行还对 ACTIVE_QUEUE_MASK, new0, older 赋值；同一行可能含多个语句，不能据此单独推断依赖。
                localparam ORDER_INDEX=j*(23-j)/2+i-j-1;
                assign older[i][j]=!relative_order[ORDER_INDEX];
            end else begin:self_relation
                assign older[i][j]=0;
            end
        end
    end endgenerate

    // [ARCH] left_match：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    wire [2:0] left_match[0:11],right_match[0:11];
    wire [11:0] eligible_actual,eligible_case0,eligible_case1;
    wire [143:0] order_flat;
    wire [11:0] mask00,mask01,mask10,mask11;
    generate for(i=0;i<12;i=i+1)begin:readiness
        // [ARCH] left0：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
        // [ARCH] 定位线索：原版中含此标识符的物理行还对 left_match 赋值；同一行可能含多个语句，不能据此单独推断依赖。
        wire [2:0] left0,right0,left1,right1,actual_left,actual_right;
        for(j=0;j<12;j=j+1)begin:flatten_order
            assign order_flat[i*12+j]=older[i][j];
        end
        for(j=0;j<3;j=j+1)begin:channel
            assign actual_left[j]=FAST_WAKEUP&&broadcast_valid[j]&&left_tags[i*4+:4]==broadcast_tags[j*4+:4];
            assign actual_right[j]=FAST_WAKEUP&&broadcast_valid[j]&&right_tags[i*4+:4]==broadcast_tags[j*4+:4];
            assign left_match[i][j]=LATE_SELECT?(late_select?left1[j]:left0[j]):actual_left[j];
            assign right_match[i][j]=LATE_SELECT?(late_select?right1[j]:right0[j]):actual_right[j];
            assign left0[j]=FAST_WAKEUP&&alternate_valid0[j]&&left_tags[i*4+:4]==alternate_tags0[j*4+:4];
            assign right0[j]=FAST_WAKEUP&&alternate_valid0[j]&&right_tags[i*4+:4]==alternate_tags0[j*4+:4];
            assign left1[j]=FAST_WAKEUP&&alternate_valid1[j]&&left_tags[i*4+:4]==alternate_tags1[j*4+:4];
            assign right1[j]=FAST_WAKEUP&&alternate_valid1[j]&&right_tags[i*4+:4]==alternate_tags1[j*4+:4];
        end
        assign eligible_actual[i]=occupied[i]&&issue_allowed[i]&&
            (left_ready[i]||(|actual_left))&&(right_ready[i]||(|actual_right));
        assign eligible_case0[i]=LATE_SELECT?
            occupied[i]&&issue_allowed[i]&&(left_ready[i]||(|left0))&&(right_ready[i]||(|right0)):eligible_actual[i];
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
    assign eligible=LATE_SELECT?(late_select?eligible_case1:eligible_case0):eligible_actual;
    assign case0_mask0=mask00;assign case0_mask1=mask01;
    assign case1_mask0=mask10;assign case1_mask1=mask11;
    assign issue_mask0=LATE_SELECT&&late_select?mask10:mask00;
    assign issue_mask1=LATE_SELECT&&late_select?mask11:mask01;
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&LATE_SELECT&&eligible!=eligible_actual)
        $fatal(1,"R51 counterfactual eligibility differs from actual completion-qualified eligibility");
`endif
    // TOPT: validity is a set-cardinality property, independent of age.
    // A legal order always has an oldest eligible owner. With two lanes,
    // either two integers or an integer plus one complex owner can issue.
    // A held EX0 still leaves EX1 available to one integer owner.
    // [ARCH] 对候选集合检查是否具有可配对数量。
    // [ARCH] 候选数量成立不免除每条指令的准备和资源条件。
    function at_least_two_integer;
        input [7:0] mask;
        reg lo_many,hi_many;
        begin
            lo_many=(mask[0]&&mask[1])||(mask[2]&&mask[3])||
                    ((|mask[1:0])&&(|mask[3:2]));
            hi_many=(mask[4]&&mask[5])||(mask[6]&&mask[7])||
                    ((|mask[5:4])&&(|mask[7:6]));
            at_least_two_integer=lo_many||hi_many||((|mask[3:0])&&(|mask[7:4]));
        end
    endfunction
    assign issue_valid0=!reset&&!ex_hold&&(|eligible);
    assign issue_valid1=!reset&&ENABLE_PAIRING&&(|eligible[7:0])&&
        (ex_hold||(|eligible[11:8])||at_least_two_integer(eligible[7:0]));
`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(issue_valid0!=(|issue_mask0)||issue_valid1!=(|issue_mask1))
            $fatal(1,"TOPT age-independent issue validity differs from selected masks");
    end
`endif

    reg [3:0] encoded0,encoded1;
    // [ARCH] stored_left0：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 stored_right0, stored_left1, stored_right1, issue_left0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [31:0] stored_left0,stored_right0,stored_left1,stored_right1;
    // [ARCH] forward_left0：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 forward_right0, forward_left1, forward_right1, issue_left0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [2:0] forward_left0,forward_right0,forward_left1,forward_right1;
    integer row;
    always @*begin
        encoded0=0;encoded1=0;
        stored_left0=0;stored_right0=0;stored_left1=0;stored_right1=0;
        forward_left0=0;forward_right0=0;forward_left1=0;forward_right1=0;
        for(row=0;row<12;row=row+1)begin
            encoded0=encoded0|({4{issue_mask0[row]}}&row[3:0]);
            encoded1=encoded1|({4{issue_mask1[row]}}&row[3:0]);
            stored_left0=stored_left0|({32{issue_mask0[row]&&(ZERO_UNREADY_OPERANDS||left_ready[row])}}&left_values[row*32+:32]);
            stored_right0=stored_right0|({32{issue_mask0[row]&&(ZERO_UNREADY_OPERANDS||right_ready[row])}}&right_values[row*32+:32]);
            stored_left1=stored_left1|({32{issue_mask1[row]&&(ZERO_UNREADY_OPERANDS||left_ready[row])}}&left_values[row*32+:32]);
            stored_right1=stored_right1|({32{issue_mask1[row]&&(ZERO_UNREADY_OPERANDS||right_ready[row])}}&right_values[row*32+:32]);
            // Resolve channel priority with bits before the wide data mux.
            // Only four selected operands receive completion data.
            forward_left0=forward_left0|({3{issue_mask0[row]&&!left_ready[row]}}&
                {left_match[row][2],left_match[row][1]&&!left_match[row][2],left_match[row][0]&&!(|left_match[row][2:1])});
            forward_right0=forward_right0|({3{issue_mask0[row]&&!right_ready[row]}}&
                {right_match[row][2],right_match[row][1]&&!right_match[row][2],right_match[row][0]&&!(|right_match[row][2:1])});
            forward_left1=forward_left1|({3{issue_mask1[row]&&!left_ready[row]}}&
                {left_match[row][2],left_match[row][1]&&!left_match[row][2],left_match[row][0]&&!(|left_match[row][2:1])});
            forward_right1=forward_right1|({3{issue_mask1[row]&&!right_ready[row]}}&
                {right_match[row][2],right_match[row][1]&&!right_match[row][2],right_match[row][0]&&!(|right_match[row][2:1])});
        end
    end
    // [ARCH] 在正确身份匹配时选择已有值或有效完成广播。
    // [ARCH] 广播的数据和写资格必须属于同一生产者。
    function [31:0] forwarded;
        input [2:0] channels;
        begin forwarded=({32{channels[0]}}&broadcast_values[31:0])|
            ({32{channels[1]}}&broadcast_values[63:32])|({32{channels[2]}}&broadcast_values[95:64]);end
    endfunction
    assign issue_slot0=encoded0;
    assign issue_slot1=encoded1;
    assign issue_left0=stored_left0|forwarded(forward_left0);
    assign issue_right0=stored_right0|forwarded(forward_right0);
    assign issue_left1=stored_left1|forwarded(forward_left1);
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
            assign local_older0[local_other]=eligible_case0[8+local_other]&&older[8+local_other][8+local_entry];
            assign local_older1[local_other]=eligible_case1[8+local_other]&&older[8+local_other][8+local_entry];
        end
        assign complex_local_case0[local_entry]=eligible_case0[8+local_entry]&&!(|local_older0);
        assign complex_local_case1[local_entry]=eligible_case1[8+local_entry]&&!(|local_older1);
    end endgenerate
    assign complex_candidate_mask=LATE_SELECT&&late_select?complex_local_case1:complex_local_case0;
    // [ARCH] complex_stored_left：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 complex_stored_right, complex_candidate_left 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [31:0] complex_stored_left,complex_stored_right;
    // [ARCH] complex_forward_left：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 complex_forward_right, complex_candidate_left 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [2:0] complex_forward_left,complex_forward_right;
    integer local_row;
    always @*begin
        complex_stored_left=0;complex_stored_right=0;
        complex_forward_left=0;complex_forward_right=0;
        for(local_row=8;local_row<12;local_row=local_row+1)begin
            complex_stored_left=complex_stored_left|({32{complex_candidate_mask[local_row-8]&&(ZERO_UNREADY_OPERANDS||left_ready[local_row])}}&left_values[local_row*32+:32]);
            complex_stored_right=complex_stored_right|({32{complex_candidate_mask[local_row-8]&&(ZERO_UNREADY_OPERANDS||right_ready[local_row])}}&right_values[local_row*32+:32]);
            complex_forward_left=complex_forward_left|({3{complex_candidate_mask[local_row-8]&&!left_ready[local_row]}}&
                {left_match[local_row][2],left_match[local_row][1]&&!left_match[local_row][2],left_match[local_row][0]&&!(|left_match[local_row][2:1])});
            complex_forward_right=complex_forward_right|({3{complex_candidate_mask[local_row-8]&&!right_ready[local_row]}}&
                {right_match[local_row][2],right_match[local_row][1]&&!right_match[local_row][2],right_match[local_row][0]&&!(|right_match[local_row][2:1])});
        end
    end
    assign complex_candidate_left=complex_stored_left|forwarded(complex_forward_left);
    assign complex_candidate_right=complex_stored_right|forwarded(complex_forward_right);
`ifdef VERILATOR
    always @(posedge clk)if(!reset&&(|issue_mask0[11:8]))begin
        if(complex_candidate_mask!=issue_mask0[11:8]||
           complex_candidate_left!=issue_left0||complex_candidate_right!=issue_right0)
            $fatal(1,"TOPT2 local complex payload differs from admitted EX0 owner");
    end
`endif
`ifdef VERILATOR
    // [ARCH] reference_stored_left0：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 reference_stored_right0 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [31:0] reference_stored_left0,reference_stored_right0,reference_stored_left1,reference_stored_right1;
    integer operand_reference_row;
    always @*begin
        reference_stored_left0=0;reference_stored_right0=0;
        reference_stored_left1=0;reference_stored_right1=0;
        for(operand_reference_row=0;operand_reference_row<12;operand_reference_row=operand_reference_row+1)begin
            reference_stored_left0=reference_stored_left0|({32{issue_mask0[operand_reference_row]&&left_ready[operand_reference_row]}}&left_values[operand_reference_row*32+:32]);
            reference_stored_right0=reference_stored_right0|({32{issue_mask0[operand_reference_row]&&right_ready[operand_reference_row]}}&right_values[operand_reference_row*32+:32]);
            reference_stored_left1=reference_stored_left1|({32{issue_mask1[operand_reference_row]&&left_ready[operand_reference_row]}}&left_values[operand_reference_row*32+:32]);
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
    // [ARCH] reset：复位控制不同于 PLL/DDR 就绪；具体极性与同步方式按本模块时序块执行。
    input reset,ex_hold,
    input [143:0] older,
    input [11:0] eligible,
    output [11:0] mask0,mask1
);
    wire [7:0] older_integer[0:11];
    wire [3:0] older_complex[0:11];
    wire [7:0] first_integer,second_integer;
    wire [3:0] first_complex,compatible_complex;
    // [ARCH] 空集合和单元素集合都满足该约束。
    // [ARCH] 此性质用于删除一个候选后判断阻塞集合是否可能变空。
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
    wire choose_complex=|compatible_complex;
    assign mask0=reset||ex_hold?12'b0:
        (choose_complex?{first_complex,8'b0}:{4'b0,first_integer});
    assign mask1=reset||!ENABLE_PAIRING?12'b0:
        (ex_hold||choose_complex?{4'b0,first_integer}:{4'b0,second_integer});
endmodule
