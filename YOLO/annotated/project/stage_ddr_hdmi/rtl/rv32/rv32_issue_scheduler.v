// Original RV32 S6 optimization. Two compatible issues from 8 integer
// and 4 complex slots. Slot order changes only on allocation, independently
// of current completion data, readiness and recovery acceptance.
// 架构导读：rv32_issue_scheduler。
// 依据就绪操作数和资源条件选择可发射指令，控制配对与依赖唤醒。
module rv32_issue_scheduler #(
    // 静态配置：parameter FAST_WAKEUP=1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter FAST_WAKEUP=1,
    // 静态配置：parameter ENABLE_PAIRING=1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter ENABLE_PAIRING=1,
    // 静态配置：parameter LATE_SELECT=0。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter LATE_SELECT=0
)(
    // 接口声明：input clk,reset。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input clk,reset,
    // 接口声明：input [1:0] allocation_count。
    // 记录数量或剩余进度，位宽限定可表达范围。
    input [1:0] allocation_count,
    // 接口声明：input [3:0] allocation_slot0,allocation_slot1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input [3:0] allocation_slot0,allocation_slot1,
    // 接口声明：input [11:0] occupied,issue_allowed,left_ready,right_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input [11:0] occupied,issue_allowed,left_ready,right_ready,
    // 接口声明：input [47:0] left_tags,right_tags。
    // 把返回信息关联到对应的已接受请求。
    input [47:0] left_tags,right_tags,
    // 接口声明：input [383:0] left_values,right_values。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input [383:0] left_values,right_values,
    // 接口声明：input [2:0] broadcast_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input [2:0] broadcast_valid,
    // 接口声明：input [11:0] broadcast_tags。
    // 把返回信息关联到对应的已接受请求。
    input [11:0] broadcast_tags,
    // 接口声明：input [95:0] broadcast_values。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input [95:0] broadcast_values,
    // 接口声明：input ex_hold。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input ex_hold,
    // Only the select bit depends on the actual LSU response/hit. Each
    // counterfactual contains the exact tags/valids for that response case.
    input late_select,
    // 接口声明：input [2:0] alternate_valid0,alternate_valid1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input [2:0] alternate_valid0,alternate_valid1,
    // 接口声明：input [11:0] alternate_tags0,alternate_tags1。
    // 把返回信息关联到对应的已接受请求。
    input [11:0] alternate_tags0,alternate_tags1,
    // 接口声明：output [11:0] eligible,issue_mask0,issue_mask1。
    // 逐位选择参与本次操作的数据通道或状态位。
    output [11:0] eligible,issue_mask0,issue_mask1,
    // 接口声明：output [11:0] case0_mask0,case0_mask1,case1_mask0,case1_mask1。
    // 逐位选择参与本次操作的数据通道或状态位。
    output [11:0] case0_mask0,case0_mask1,case1_mask0,case1_mask1,
    // 接口声明：output issue_valid0,issue_valid1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output issue_valid0,issue_valid1,
    // 接口声明：output [3:0] issue_slot0,issue_slot1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output [3:0] issue_slot0,issue_slot1,
    // 接口声明：output [31:0] issue_left0,issue_right0,issue_left1,issue_right1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output [31:0] issue_left0,issue_right0,issue_left1,issue_right1
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
                // 静态配置：localparam ORDER_INDEX=i*(23-i)/2+j-i-1。
                // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
                localparam ORDER_INDEX=i*(23-i)/2+j-i-1;
                // 过程边界：always @(posedge clk)begin。
                // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
                always @(posedge clk)begin
                    // 复位相关判断：reset；分支方向由信号极性与取反表达式决定。
                    if(reset)relative_order[ORDER_INDEX]<=0;
                    else if(new0[i]||new1[i])relative_order[ORDER_INDEX]<=new0[i]&&new1[j];
                    else if(new0[j]||new1[j])relative_order[ORDER_INDEX]<=1;
                end
                assign older[i][j]=relative_order[ORDER_INDEX];
            end else if(i>j)begin:reverse_relation
                // 静态配置：localparam ORDER_INDEX=j*(23-j)/2+i-j-1。
                // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
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
    // 过程边界：always @(posedge clk)if(!reset&&LATE_SELECT&&eligible!=eligible_actual)。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always @(posedge clk)if(!reset&&LATE_SELECT&&eligible!=eligible_actual)
        $fatal(1,"R51 counterfactual eligibility differs from actual completion-qualified eligibility");
`endif
    assign issue_valid0=|issue_mask0;
    assign issue_valid1=|issue_mask1;

    reg [3:0] encoded0,encoded1;
    reg [31:0] stored_left0,stored_right0,stored_left1,stored_right1;
    reg [2:0] forward_left0,forward_right0,forward_left1,forward_right1;
    integer row;
    // 过程边界：always @*begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always @*begin
        encoded0=0;encoded1=0;
        stored_left0=0;stored_right0=0;stored_left1=0;stored_right1=0;
        forward_left0=0;forward_right0=0;forward_left1=0;forward_right1=0;
        for(row=0;row<12;row=row+1)begin
            encoded0=encoded0|({4{issue_mask0[row]}}&row[3:0]);
            encoded1=encoded1|({4{issue_mask1[row]}}&row[3:0]);
            stored_left0=stored_left0|({32{issue_mask0[row]&&left_ready[row]}}&left_values[row*32+:32]);
            stored_right0=stored_right0|({32{issue_mask0[row]&&right_ready[row]}}&right_values[row*32+:32]);
            stored_left1=stored_left1|({32{issue_mask1[row]&&left_ready[row]}}&left_values[row*32+:32]);
            stored_right1=stored_right1|({32{issue_mask1[row]&&right_ready[row]}}&right_values[row*32+:32]);
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
    // 局部运算/辅助过程：function [31:0] forwarded;。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function [31:0] forwarded;
        // 接口声明：input [2:0] channels。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
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
endmodule

// Pure oldest-compatible-set function. Both copies share the same registered
// order relations; no speculative completion changes queue ownership.
module rv32_issue_rank #(parameter ENABLE_PAIRING=1)(
    // 接口声明：input reset,ex_hold。
    input reset,ex_hold,
    input [143:0] older,
    input [11:0] eligible,
    output [11:0] mask0,mask1
);
    wire [7:0] older_integer[0:11];
    wire [3:0] older_complex[0:11];
    wire [7:0] first_integer,second_integer;
    wire [3:0] first_complex,compatible_complex;
    // 局部运算/辅助过程：function at_most_one;。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function at_most_one;
        input [7:0] mask;
        begin at_most_one=mask==0||mask==8'h01||mask==8'h02||mask==8'h04||mask==8'h08||
            mask==8'h10||mask==8'h20||mask==8'h40||mask==8'h80;end
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
            assign compatible_complex[i-8]=first_complex[i-8]&&
                (ENABLE_PAIRING?at_most_one(older_integer[i]):!(|older_integer[i]));
        end
    end endgenerate
    wire choose_complex=|compatible_complex;
    assign mask0=reset||ex_hold?12'b0:
        (choose_complex?{first_complex,8'b0}:{4'b0,first_integer});
    assign mask1=reset||!ENABLE_PAIRING?12'b0:
        (ex_hold||choose_complex?{4'b0,first_integer}:{4'b0,second_integer});
endmodule
