// Independently authored RV32 queue resource boundary, Verilog-2001.
// The inputs describe registered occupancy and the two decoded requests only.
// There is deliberately no execution, completion, wakeup or release input.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 只依据已寄存占用和译码类别给出至多两个空闲槽位建议。
// 整数两银行各四行，复杂银行四行；无效物理行由上游置为不可分配。
// 每银行并行求第一及第二空位，第二条分配不用再串行扫描整个队列。
// 整数优先较空银行，数量相同由 steer 打破平局；第二整数优先另一银行。
// 复杂操作使用复杂银行，valid0/1 才表示对应 slot 编码有意义。
// 没有完成、唤醒或当拍释放输入，因此不依赖当拍 issue 来重复使用槽位。
// 接口契约与阅读示例
// 以occupied=全1为例，所有valid均应为0，slot数值此时没有有效所有者含义。
// 一个整数与一个复杂请求可以各自使用不同银行，资源并不完全共享。
// 两条复杂请求需复杂银行至少两个空位，否则只允许第一条分配。
// 两条整数优先分散到两个银行，若另一银行没有空位再使用同银行第二空位。
// steer只在两银行占用相同时影响偏好，不改变已存活指令的程序年龄。
// 上层将禁用行OR入occupied，使物理数组中的未启用项不能意外被分配。
// 空位建议本身不更新q_valid，实际分配还需核心接受并更新ROB和重命名。
module rv32_queue_allocator(
    // 接口字段：input [11:0] occupied。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    input [11:0] occupied,
    // 接口字段：input complex0,complex1,steer。
    // 只依据已寄存占用和译码类别给出至多两个空闲槽位建议。
    input complex0,complex1,steer,
    // 接口字段：output valid0,valid1。
    // 只依据已寄存占用和译码类别给出至多两个空闲槽位建议。
    output valid0,valid1,
    // 接口字段：output [3:0] slot0,slot1。
    // 只依据已寄存占用和译码类别给出至多两个空闲槽位建议。
    output [3:0] slot0,slot1
);
    // Each four-entry bank finds its first two holes in parallel. This avoids
    // a global first-slot selection followed by a second global rescan.
    // 函数 first_hole：编码四行位图的第一个空闲项，同时返回是否存在空位；
    // 没有空位时编码不可使用。
    // 调用字段：input [3:0] holes。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
    function [2:0] first_hole;
        input [3:0] holes;
        begin
            first_hole={|holes,2'b00};
            if(holes[0])first_hole[1:0]=0;
            else if(holes[1])first_hole[1:0]=1;
            else if(holes[2])first_hole[1:0]=2;
            else first_hole[1:0]=3;
        end
    endfunction
    // 函数 second_hole：在原始空闲位图中并行求第二空位，
    // 不在第一选择结果之后再串行扫描。
    // 调用字段：input [3:0] holes。
    // 返回值是局部组合计算；调用者继续负责有效性、标签或表项命中条件。
    function [2:0] second_hole;
        input [3:0] holes;
        reg pick1,pick2,pick3;
        begin
            pick1=holes[1]&&holes[0];
            pick2=holes[2]&&(holes[0]^holes[1]);
            pick3=holes[3]&&((holes[0]&&!holes[1]&&!holes[2])||
                                  (!holes[0]&&holes[1]&&!holes[2])||
                                  (!holes[0]&&!holes[1]&&holes[2]));
            second_hole={pick1||pick2||pick3,pick2||pick3,pick1||pick3};
        end
    endfunction
    wire [2:0] first0=first_hole(~occupied[3:0]);
    wire [2:0] first1=first_hole(~occupied[7:4]);
    wire [2:0] firstc=first_hole(~occupied[11:8]);
    wire [2:0] second0=second_hole(~occupied[3:0]);
    wire [2:0] second1=second_hole(~occupied[7:4]);
    wire [2:0] secondc=second_hole(~occupied[11:8]);
    wire [2:0] count0={2'b0,occupied[0]}+{2'b0,occupied[1]}+
                      {2'b0,occupied[2]}+{2'b0,occupied[3]};
    wire [2:0] count1={2'b0,occupied[4]}+{2'b0,occupied[5]}+
                      {2'b0,occupied[6]}+{2'b0,occupied[7]};
    wire preferred=count1<count0?1'b1:count0<count1?1'b0:steer;
    wire first_bank=preferred?first1[2]:!first0[2];
    wire [2:0] integer_first=first_bank?first1:first0;
    // After the first integer, prefer the other bank. If it has no hole,
    // reuse the precomputed second hole of the first bank, never a rescan.
    wire second_bank=first_bank?!first0[2]:first1[2];
    wire [2:0] integer_second=second_bank?
        (first_bank?second1:first1):(first_bank?first0:second0);
    wire [2:0] complex_next=complex0?secondc:firstc;
    wire [2:0] integer_next=complex0?integer_first:integer_second;
    wire integer_next_bank=complex0?first_bank:second_bank;
    assign valid0=complex0?firstc[2]:integer_first[2];
    assign slot0=complex0?{2'b10,firstc[1:0]}:{1'b0,first_bank,integer_first[1:0]};
    assign valid1=complex1?complex_next[2]:integer_next[2];
    assign slot1=complex1?{2'b10,complex_next[1:0]}:{1'b0,integer_next_bank,integer_next[1:0]};
endmodule
