// Small prediction-only return stack. Only architecturally retired control
// instructions update it, in lane0 then lane1 order. No speculative state,
// recovery side effect, ISA-visible state, or benchmark-dependent behavior.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 只在控制指令提交后更新的返回地址预测栈，本板深度 16。
// JAL 写 x1/x5 表示入栈；JALR 根据源与目的链接寄存器决定出栈或先出后入。
// 两条提交按 lane0 再 lane1 的程序顺序作用于同一个下一栈状态。
// 返回值保存 pc+4；满栈继续入栈会覆盖最旧的保留项。
// 同一行被两个提交写入时，较年轻的 lane1 优先。
// 不保存 ISA 可见架构状态，也不随每次投机调用立即修改；
// 错误预测通过正常恢复纠正。
// 接口契约与阅读示例
// 返回预测栈与软件栈是两个不同对象，软件Load/Store不会自动修改它。
// 普通JAL rd=x0不产生链接，不应无条件入栈。
// JAL rd=x1或x5记录顺序返回地址pc+4。
// JALR使用链接源但不写同一个链接寄存器时可以出栈。
// 不同链接源和目的的协程形式先出栈再入栈，不能简单二选一。
// 两条提交动作逐条更新临时指针，第二条看到第一条动作后的状态。
// 恢复清除错路径指令时没有对应退休训练，因此本栈无需复制整套投机状态。
module rv32_committed_ras #(
    // 参数 DEPTH：有效项数容量，读写指针和饱和计数必须与此参数匹配。
    parameter DEPTH=16,
    // 参数 POINTER_BITS：栈或队列指针编码位宽，不包含额外的满空计数位。
    parameter POINTER_BITS=$clog2(DEPTH)
)(
    // 接口字段：input clk,reset。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input clk,reset,
    // 接口字段：input train0,train1。
    // 按提交顺序的预测训练或其信用。只采纳有资格的已提交控制流，
    // 不把推测执行当训练完成。
    input train0,train1,
    // 接口字段：input [31:0] instruction0,instruction1,pc0,pc1。
    // 控制流地址或恢复信息。顺序地址、预测地址和实际恢复地址具有不同来源，
    // 不能互换。
    input [31:0] instruction0,instruction1,pc0,pc1,
    // 接口字段：output valid。
    // 只在控制指令提交后更新的返回地址预测栈，本板深度 16。
    output valid,
    // 接口字段：output [31:0] top。
    // 只在控制指令提交后更新的返回地址预测栈，本板深度 16。
    output [31:0] top,
    // 接口字段：output [POINTER_BITS:0] occupancy。
    // 有效数量或消费数量。索引编码只有对应有效/计数许可时才表示存活所有者。
    output [POINTER_BITS:0] occupancy
);
    reg [31:0] entries[0:DEPTH-1];
    reg [POINTER_BITS-1:0] pointer;
    reg [POINTER_BITS:0] count;
    reg [POINTER_BITS-1:0] pointer_next,write_index0,write_index1;
    reg [POINTER_BITS:0] count_next;
    reg write0,write1;
    wire [POINTER_BITS-1:0] top_index=pointer-1'b1;
    assign valid=count!=0;
    assign top=valid?entries[top_index]:32'b0;
    assign occupancy=count;

    // RISC-V implicit RAS hints: JAL rd=x1/x5 pushes. JALR with a link
    // source pops unless rd is that SAME link; any link destination pushes.
    // Different link registers therefore pop then push (coroutines).
    // 函数 action：解码JAL/JALR的x1/x5提示，给出先出栈与后入栈动作，
    // 按提交顺序应用。
    // 调用字段：input [31:0] instruction。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
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
