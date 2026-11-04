// [ARCH] 返回地址栈按已提交的调用/返回事实更新，避免错误路径污染持久状态。
// [ARCH] 当前 RAS_DEPTH=16，栈顶指针与有效数量需要一起解释。
// [ARCH] 调用保存返回 PC，返回消费栈顶；空栈必须有无效判定。
// [ARCH] 同拍两个退休事件按程序顺序组合，不能交换调用与返回。
// [ARCH] RAS 是预测资源，给出候选目标不等于指令已经退休。
// Small prediction-only return stack. Only architecturally retired control
// instructions update it, in lane0 then lane1 order. No speculative state,
// recovery side effect, ISA-visible state, or benchmark-dependent behavior.
module rv32_committed_ras #(
    parameter DEPTH=16,
    // [ARCH] POINTER_BITS：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 top_index 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    parameter POINTER_BITS=$clog2(DEPTH)
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input clk,reset,
    input train0,train1,
    // [ARCH] instruction0：保存与同一 PC/所有权配对的指令字，不能从当前前端重新补填。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 action0, action1 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input [31:0] instruction0,instruction1,pc0,pc1,
    // [ARCH] valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 top 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output valid,
    output [31:0] top,
    output [POINTER_BITS:0] occupancy
);
    reg [31:0] entries[0:DEPTH-1];
    // [ARCH] pointer：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 top_index, pointer_next, count_next, count 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [POINTER_BITS-1:0] pointer;
    // [ARCH] count：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 valid, occupancy, pointer_next, count_next 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [POINTER_BITS:0] count;
    // [ARCH] pointer_next：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 count_next, write0, write_index0, write1 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [POINTER_BITS-1:0] pointer_next,write_index0,write_index1;
    // [ARCH] count_next：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pointer_next, pointer, count 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [POINTER_BITS:0] count_next;
    reg write0,write1;
    // [ARCH] top_index：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 top 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire [POINTER_BITS-1:0] top_index=pointer-1'b1;
    assign valid=count!=0;
    assign top=valid?entries[top_index]:32'b0;
    assign occupancy=count;

    // RISC-V implicit RAS hints: JAL rd=x1/x5 pushes. JALR with a link
    // source pops unless rd is that SAME link; any link destination pushes.
    // Different link registers therefore pop then push (coroutines).
    // [ARCH] 从已提交指令识别调用/返回的栈动作。
    // [ARCH] 动作顺序与退休顺序一致，不能用推测执行替换。
    function [1:0] action;
        // [ARCH] instruction：保存与同一 PC/所有权配对的指令字，不能从当前前端重新补填。
        // [ARCH] 定位线索：原版中含此标识符的物理行还对 destination_link, source_link, action 赋值；同一行可能含多个语句，不能据此单独推断依赖。
        input [31:0] instruction;
        // [ARCH] destination_link：目的寄存器身份随指令保持，x0 写入仍须被抑制。
        // [ARCH] 定位线索：原版中含此标识符的物理行还对 instruction, action 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
    always @(posedge clk)begin
        if(reset)begin pointer<=0;count<=0;end
        else begin
            pointer<=pointer_next;count<=count_next;
            // A saturated push replaces the oldest retained entry. If both
            // lanes write one row, the younger retired lane has precedence.
            if(write0)entries[write_index0]<=pc0+32'd4;
            if(write1)entries[write_index1]<=pc1+32'd4;
        end
    end
`ifdef VERILATOR
    initial if(DEPTH!=8&&DEPTH!=16)$fatal(1,"Committed RAS supports depth 8 or 16");
    always @(posedge clk)if(!reset&&count>DEPTH)$fatal(1,"Committed RAS count overflow");
`endif
endmodule
