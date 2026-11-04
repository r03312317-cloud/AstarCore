// Small prediction-only return stack. Only architecturally retired control
// instructions update it, in lane0 then lane1 order. No speculative state,
// recovery side effect, ISA-visible state, or benchmark-dependent behavior.
// 架构导读：rv32_committed_ras。
// 在提交边界维护返回地址预测状态，避免未提交路径污染恢复状态。
module rv32_committed_ras #(
    // 静态配置：parameter DEPTH=16。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter DEPTH=16,
    // 静态配置：parameter POINTER_BITS=$clog2(DEPTH)。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter POINTER_BITS=$clog2(DEPTH)
)(
    // 接口声明：input clk,reset。
    // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
    input clk,reset,
    // 接口声明：input train0,train1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input train0,train1,
    // 接口声明：input [31:0] instruction0,instruction1,pc0,pc1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input [31:0] instruction0,instruction1,pc0,pc1,
    // 接口声明：output valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    output valid,
    output [31:0] top,
    output [POINTER_BITS:0] occupancy
);
    // The two ordered training events either push adjacent entries, or a
    // lane1 pop+push replaces lane0's just-pushed entry. Thus same-bank
    // writes always share one address and retain the younger lane1 value.
    (* syn_ramstyle="distributed_ram" *) reg [31:0] entries_even[0:DEPTH/2-1];
    (* syn_ramstyle="distributed_ram" *) reg [31:0] entries_odd[0:DEPTH/2-1];
    reg [POINTER_BITS-1:0] pointer;
    reg [POINTER_BITS:0] count;
    reg [POINTER_BITS-1:0] pointer_next,write_index0,write_index1;
    reg [POINTER_BITS:0] count_next;
    reg write0,write1;
    wire [POINTER_BITS-1:0] top_index=pointer-1'b1;
    assign valid=count!=0;
    assign top=valid?(top_index[0]?entries_odd[top_index>>1]:entries_even[top_index>>1]):32'b0;
    assign occupancy=count;

    // RISC-V implicit RAS hints: JAL rd=x1/x5 pushes. JALR with a link
    // source pops unless rd is that SAME link; any link destination pushes.
    // Different link registers therefore pop then push (coroutines).
    function [1:0] action;
        input [31:0] instruction;
        reg destination_link,source_link;
        begin
            destination_link=instruction[11:7]==1||instruction[11:7]==5;
            source_link=instruction[19:15]==1||instruction[19:15]==5;
            action=0;
            if(instruction[6:0]==7'b1101111)action[1]=destination_link;
            else if(instruction[6:0]==7'b1100111&&instruction[14:12]==0)begin
                action[0]=source_link&&(!destination_link||instruction[11:7]!=instruction[19:15]);
                action[1]=destination_link;
            end
        end
    endfunction
    wire [1:0] action0=action(instruction0),action1=action(instruction1);
    // 过程边界：always @*begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always @*begin
        pointer_next=pointer;count_next=count;
        write0=0;write1=0;write_index0=0;write_index1=0;
        if(train0)begin
            if(action0[0]&&count_next!=0)begin
                pointer_next=pointer_next-1'b1;count_next=count_next-1'b1;
            end
            if(action0[1])begin
                write0=1;write_index0=pointer_next;pointer_next=pointer_next+1'b1;
                if(count_next<DEPTH)count_next=count_next+1'b1;
            end
        end
        if(train1)begin
            if(action1[0]&&count_next!=0)begin
                pointer_next=pointer_next-1'b1;count_next=count_next-1'b1;
            end
            if(action1[1])begin
                write1=1;write_index1=pointer_next;pointer_next=pointer_next+1'b1;
                if(count_next<DEPTH)count_next=count_next+1'b1;
            end
        end
    end
    // 过程边界：always @(posedge clk)begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always @(posedge clk)begin
        // 复位相关判断：reset；分支方向由信号极性与取反表达式决定。
        if(reset)begin pointer<=0;count<=0;end
        else begin
            pointer<=pointer_next;count<=count_next;
        end
    end
    // One dynamic write port per parity bank; payload remains unreset.
    // A saturated push still replaces the oldest retained entry.
    always @(posedge clk)if(!reset)begin
        if(write1&&!write_index1[0])entries_even[write_index1>>1]<=pc1+32'd4;
        else if(write0&&!write_index0[0])entries_even[write_index0>>1]<=pc0+32'd4;
        if(write1&&write_index1[0])entries_odd[write_index1>>1]<=pc1+32'd4;
        else if(write0&&write_index0[0])entries_odd[write_index0>>1]<=pc0+32'd4;
    end
`ifdef VERILATOR
    initial if(DEPTH!=8&&DEPTH!=16)$fatal(1,"Committed RAS supports depth 8 or 16");
    // 过程边界：always @(posedge clk)if(!reset&&count>DEPTH)$fatal(1,"Committed RAS count overflow");。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always @(posedge clk)if(!reset&&count>DEPTH)$fatal(1,"Committed RAS count overflow");
`endif
endmodule
