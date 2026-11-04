// Original RV32 S6 optimization. Two compatible issues from 8 integer
// and 4 complex slots. Slot order changes only on allocation, independently
// of current completion data, readiness and recovery acceptance.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
// 12 项物理数组分为 8 个整数槽及 4 个复杂槽，实际有效行由 ACTIVE_QUEUE_MASK
// 限定。
// 每对行只保存一个先后关系位；新分配比所有存活旧项年轻，
// 同束第二条比第一条年轻。
// 原始 ready 与当前真实完成广播共同构成可用操作数，不能把推测广播当已完成。
// late_select 模式预先计算 LSU 响应两种情形的选择，
// 晚到选择位只挑选已准备的候选。
// EX0 可以选复杂操作，EX1 同拍提供兼容整数工作；ex_hold 时 EX0 不被覆盖。
// 输出 one-hot issue_mask 直接控制所有者释放，encoded slot 主要作为辅助定位。
// 宽操作数由独立 payload mux 合成，本模块不直接写寄存器文件或提交 ROB。
// 接口契约与阅读示例
// 分配边界  若同边沿新分配两行，port0在port1之前；旧存活项仍在两者之前。
// 复用一行时要重写它与其他行的关系，不能把旧所有者的年龄留给新指令。
// 关系矩阵是66个无序行对的有向先后位，反向查询取其相反关系。
// ready计算可以接受当前真实结果广播，但一次广播不能唤醒标签不匹配的项。
// 两个候选都需符合issue_allowed，尤其访存不能仅因两个源ready就越过老Store。
// LATE_SELECT为LSU是否返回的两种假设预先算候选，并用实际返回情形选择。
// 假设候选数据不是已执行或已提交的结果，不会单独给ROB置done。
// 复杂候选占EX0时，另一个整数仍可进入EX1，提高访存与地址/循环算术重叠机会。
// 如果ex_hold为1，必须保留EX0旧所有者，不能把第一整数错误地装入该槽。
// 输出issue_mask用于真正释放队列，调试encoded slot只能在有效条件下解释。
// 同拍直接dispatch旁路由核心填空槽，不在本模块重复给它生成第二个所有者。
// 调度器自身不决定分支恢复地址，恢复由提交逻辑按程序顺序决定。
module rv32_issue_scheduler #(
    // 参数 FAST_WAKEUP：真实完成标签可以在原ready置位前被当拍消费者使用，
    // 仍需广播valid资格。
    parameter FAST_WAKEUP=1,
    // 参数 ENABLE_PAIRING：允许最大两条分配/发射/提交；
    // 资源及依赖不满足时仍可仅推进一条。
    parameter ENABLE_PAIRING=1,
    // 参数 LATE_SELECT：为晚到LSU响应分别准备两套就绪候选，
    // 只在末端选择实际情形。
    parameter LATE_SELECT=0,
    // The caller may establish this invariant at operand allocation/capture.
    // Generic callers retain the original readiness-qualified data muxes.
    // 参数 ZERO_UNREADY_OPERANDS：调用者承诺未就绪数据为零，
    // 用于合并旁路宽数据而不附加晚到ready门控。
    parameter ZERO_UNREADY_OPERANDS=0,
    // 参数 ACTIVE_QUEUE_MASK：控制12个物理发射槽的可用行；本板0x733共7行，
    // 不能按数组12项宣称容量。
    parameter [11:0] ACTIVE_QUEUE_MASK=12'hfff
)(
    // 接口字段：input clk,reset。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input clk,reset,
    // 接口字段：input [1:0] allocation_count。
    // 有效数量或消费数量。索引编码只有对应有效/计数许可时才表示存活所有者。
    input [1:0] allocation_count,
    // 接口字段：input [3:0] allocation_slot0,allocation_slot1。
    // 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
    input [3:0] allocation_slot0,allocation_slot1,
    // 接口字段：input [11:0] occupied,issue_allowed,left_ready,right_ready。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    input [11:0] occupied,issue_allowed,left_ready,right_ready,
    // 接口字段：input [47:0] left_tags,right_tags。
    // 生产者或事务标签。只关联所有者，不代表算术值，也不能单凭标签判断已完成。
    input [47:0] left_tags,right_tags,
    // 接口字段：input [383:0] left_values,right_values。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
    input [383:0] left_values,right_values,
    // 接口字段：input [2:0] broadcast_valid。
    // 真实完成旁路的valid、标签或数值。必须同时验证标签和valid，
    // 未就绪数值不可使用。
    input [2:0] broadcast_valid,
    // 接口字段：input [11:0] broadcast_tags。
    // 真实完成旁路的valid、标签或数值。必须同时验证标签和valid，
    // 未就绪数值不可使用。
    input [11:0] broadcast_tags,
    // 接口字段：input [95:0] broadcast_values。
    // 真实完成旁路的valid、标签或数值。必须同时验证标签和valid，
    // 未就绪数值不可使用。
    input [95:0] broadcast_values,
    // 接口字段：input ex_hold。
    // 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
    input ex_hold,
    // Only the select bit depends on the actual LSU response/hit. Each
    // counterfactual contains the exact tags/valids for that response case.
    // 接口字段：input late_select。
    // 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
    input late_select,
    // 接口字段：input [2:0] alternate_valid0,alternate_valid1。
    // 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
    input [2:0] alternate_valid0,alternate_valid1,
    // 接口字段：input [11:0] alternate_tags0,alternate_tags1。
    // 生产者或事务标签。只关联所有者，不代表算术值，也不能单凭标签判断已完成。
    input [11:0] alternate_tags0,alternate_tags1,
    // 接口字段：output [11:0] eligible,issue_mask0,issue_mask1。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    output [11:0] eligible,issue_mask0,issue_mask1,
    // 接口字段：output [7:0] case0_first_integer,case0_second_integer,
    // case1_first_integer,case1_second_integer。
    // 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
    output [7:0] case0_first_integer,case0_second_integer,case1_first_integer,case1_second_integer,
    // 接口字段：output [3:0] case0_first_complex,case1_first_complex。
    // 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
    output [3:0] case0_first_complex,case1_first_complex,
    // 接口字段：output case0_choose_complex,case1_choose_complex。
    // 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
    output case0_choose_complex,case1_choose_complex,
    // 接口字段：output [11:0] case0_mask0,case0_mask1,case1_mask0,case1_mask1。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    output [11:0] case0_mask0,case0_mask1,case1_mask0,case1_mask1,
    // 接口字段：output issue_valid0,issue_valid1。
    // 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
    output issue_valid0,issue_valid1,
    // 接口字段：output [3:0] issue_slot0,issue_slot1。
    // 两槽位就绪调度器，以已寄存的相对年龄关系选择兼容的老指令。
    output [3:0] issue_slot0,issue_slot1,
    // 接口字段：output [31:0] issue_left0,issue_right0,issue_left1,
    // issue_right1。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
    output [31:0] issue_left0,issue_right0,issue_left1,issue_right1,
    // Local complex-bank payload is prepared independently of global lane
    // arbitration. Ownership remains exclusively with the normal issue mask.
    // 接口字段：output [3:0] complex_candidate_mask。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    output [3:0] complex_candidate_mask,
    // 接口字段：output [31:0] complex_candidate_left,complex_candidate_right。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
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
                localparam ORDER_INDEX=i*(23-i)/2+j-i-1;
                always @(posedge clk)begin
                    if(!ACTIVE_QUEUE_MASK[i]||!ACTIVE_QUEUE_MASK[j]||reset)relative_order[ORDER_INDEX]<=0;
                    else if(new0[i]||new1[i])relative_order[ORDER_INDEX]<=new0[i]&&new1[j];
                    else if(new0[j]||new1[j])relative_order[ORDER_INDEX]<=1;
                end
                assign older[i][j]=relative_order[ORDER_INDEX];
            end else if(i>j)begin:reverse_relation
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
        .reset(reset),.ex_hold(ex_hold),.older(order_flat),.eligible(eligible_case0),.mask0(mask00),.mask1(mask01),
        .first_integer(case0_first_integer),.second_integer(case0_second_integer),
        .first_complex(case0_first_complex),.choose_complex(case0_choose_complex));
    generate if(LATE_SELECT)begin:late_case
        rv32_issue_rank #(.ENABLE_PAIRING(ENABLE_PAIRING)) rank1(
            .reset(reset),.ex_hold(ex_hold),.older(order_flat),.eligible(eligible_case1),.mask0(mask10),.mask1(mask11),
            .first_integer(case1_first_integer),.second_integer(case1_second_integer),
            .first_complex(case1_first_complex),.choose_complex(case1_choose_complex));
    end else begin:single_case
        assign mask10=12'b0;assign mask11=12'b0;
        assign case1_first_integer=0;assign case1_second_integer=0;
        assign case1_first_complex=0;assign case1_choose_complex=0;
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
    // 函数 at_least_two_integer：并行判断是否存在至少两个可发整数候选，
    // 帮助在复杂与整数候选之间形成兼容双选。
    // 调用字段：input [7:0] mask。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
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
    reg [31:0] stored_left0,stored_right0,stored_left1,stored_right1;
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
    // 函数 forwarded：按有效匹配完成通道归并旁路值；未就绪值在
    // ZERO_UNREADY_OPERANDS 契约下可安全屏蔽。
    // 调用字段：input [2:0] channels。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
    function [31:0] forwarded;
        input [2:0] channels;
        begin forwarded=({32{channels[0]}}&broadcast_values[31:0])|
            ({32{channels[1]}}&broadcast_values[63:32])|({32{channels[2]}}&broadcast_values[95:64]);end
    endfunction
    assign issue_slot0=encoded0;
    assign issue_slot1=encoded1;
    // Soc02 round 2: prepare first/second integer and first complex
    // payloads independently. The late rank decision selects completed
    // payloads rather than driving every row of the 12-way operand mux.
    // Forwarding priority remains channel 2, then 1, then 0, exactly as above.
    wire [7:0] data_first_integer=LATE_SELECT&&late_select?case1_first_integer:case0_first_integer;
    wire [7:0] data_second_integer=LATE_SELECT&&late_select?case1_second_integer:case0_second_integer;
    wire [3:0] data_first_complex=LATE_SELECT&&late_select?case1_first_complex:case0_first_complex;
    wire data_choose_complex=LATE_SELECT&&late_select?case1_choose_complex:case0_choose_complex;
    wire [839:0] operand_payload;
    wire [69:0] selected_operand0,selected_operand1;
    genvar operand_row;
    generate for(operand_row=0;operand_row<12;operand_row=operand_row+1)begin:local_operand_payload
        wire [31:0] lv={32{ZERO_UNREADY_OPERANDS||left_ready[operand_row]}}&left_values[operand_row*32+:32];
        wire [31:0] rv={32{ZERO_UNREADY_OPERANDS||right_ready[operand_row]}}&right_values[operand_row*32+:32];
        wire [2:0] lf={3{!left_ready[operand_row]}}&
            {left_match[operand_row][2],left_match[operand_row][1]&&!left_match[operand_row][2],
             left_match[operand_row][0]&&!(|left_match[operand_row][2:1])};
        wire [2:0] rf={3{!right_ready[operand_row]}}&
            {right_match[operand_row][2],right_match[operand_row][1]&&!right_match[operand_row][2],
             right_match[operand_row][0]&&!(|right_match[operand_row][2:1])};
        assign operand_payload[operand_row*70+:70]={lv,rv,lf,rf};
    end endgenerate
    rv32_issue_payload_mux #(.WIDTH(70),.ENABLE_PAIRING(ENABLE_PAIRING)) operand_mux(
        .reset(reset),.ex_hold(ex_hold),.first_integer(data_first_integer),
        .second_integer(data_second_integer),.first_complex(data_first_complex),
        .choose_complex(data_choose_complex),.payload(operand_payload),
        .value0(selected_operand0),.value1(selected_operand1));
    assign issue_left0=selected_operand0[69:38]|forwarded(selected_operand0[5:3]);
    assign issue_right0=selected_operand0[37:6]|forwarded(selected_operand0[2:0]);
    assign issue_left1=selected_operand1[69:38]|forwarded(selected_operand1[5:3]);
    assign issue_right1=selected_operand1[37:6]|forwarded(selected_operand1[2:0]);
`ifdef VERILATOR
    always @(posedge clk)if(!reset)begin
        if(issue_left0!=(stored_left0|forwarded(forward_left0))||
           issue_right0!=(stored_right0|forwarded(forward_right0))||
           issue_left1!=(stored_left1|forwarded(forward_left1))||
           issue_right1!=(stored_right1|forwarded(forward_right1)))
            $fatal(1,"Soc02 split operand payload changed lane ownership or forwarding");
    end
`endif

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
    reg [31:0] complex_stored_left,complex_stored_right;
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
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 在给定 ready 位图与相对年龄矩阵中，组合选择第一和第二个可发射者。
// 整数槽与复杂槽分开形成最老候选，再决定 lane0 的操作类型。
// 年龄关系已在分配时保存，此处不重新读取 ROB 序号进行全局排序。
// 一个复杂候选占用 EX0 时，EX1 仍可选一个整数候选；不会选择同一行两次。
// 无状态模块，reset、ex_hold 与 ENABLE_PAIRING 约束候选输出。
// 相对矩阵必须由调度器按分配顺序维护，任意无效行内容不构成有效指令。
// 接口契约与阅读示例
// 对一个候选，只有比它更老且eligible的其他项才影响排名。
// 第一候选没有更老可发项，第二候选应恰有一个更老可发项。
// 整数与复杂候选先按各自类别排名，再满足两槽兼容性。
// 一个未就绪老指令不会因此强制阻止所有独立年轻整数发射。
// 访存次序限制通过issue_allowed进入eligible，
// 所以不能据排名本身宣称任意访存可乱序。
// 调用者把禁用物理行清除，避免矩阵中无效旧内容成为候选。
// 没有时钟状态意味着本模块优化影响组合延迟，不直接改变队列保存周期。
module rv32_issue_rank #(parameter ENABLE_PAIRING=1)(
    // 接口字段：input reset,ex_hold。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input reset,ex_hold,
    // 接口字段：input [143:0] older。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    input [143:0] older,
    // 接口字段：input [11:0] eligible。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    input [11:0] eligible,
    // 接口字段：output [11:0] mask0,mask1。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    output [11:0] mask0,mask1,
    // 接口字段：output [7:0] first_integer,second_integer。
    // 在给定 ready 位图与相对年龄矩阵中，组合选择第一和第二个可发射者。
    output [7:0] first_integer,second_integer,
    // 接口字段：output [3:0] first_complex。
    // 在给定 ready 位图与相对年龄矩阵中，组合选择第一和第二个可发射者。
    output [3:0] first_complex,
    // 接口字段：output choose_complex。
    // 在给定 ready 位图与相对年龄矩阵中，组合选择第一和第二个可发射者。
    output choose_complex
);
    wire [7:0] older_integer[0:11];
    wire [3:0] older_complex[0:11];
    wire [3:0] compatible_complex;
    // 函数 at_most_one：仿真或控制辅助判断选择位图最多一位，
    // 防止重复发射所有者。
    // 调用字段：input [7:0] mask。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
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
    assign choose_complex=|compatible_complex;
    assign mask0=reset||ex_hold?12'b0:
        (choose_complex?{first_complex,8'b0}:{4'b0,first_integer});
    assign mask1=reset||!ENABLE_PAIRING?12'b0:
        (ex_hold||choose_complex?{4'b0,first_integer}:{4'b0,second_integer});
endmodule
