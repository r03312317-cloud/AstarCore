// Independently authored RV32 queue resource boundary, Verilog-2001.
// The inputs describe registered occupancy and the two decoded requests only.
// There is deliberately no execution, completion, wakeup or release input.
// 分配器根据物理槽位占用和指令类别为至多两条新指令选择位置。
// 同一拍的第二条分配须排除第一条已选槽位，避免两个所有者覆盖同一行。
// 物理掩码定义哪些槽位存在，空闲判定不能把被裁剪的槽位视为可用资源。
// 输出是分配提议，核心还会结合 ROB 空间 恢复及旁路路径决定最终接收。
module rv32_queue_allocator(
    input [11:0] occupied,
    input complex0,complex1,steer,
    // valid0 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output valid0,valid1,
    output [3:0] slot0,slot1
);
    // Each four-entry bank finds its first two holes in parallel. This avoids
    // a global first-slot selection followed by a second global rescan.
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
    // first0 对 first_hole(~occupied[3:0]) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [2:0] first0=first_hole(~occupied[3:0]);
    // first1 对 first_hole(~occupied[7:4]) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [2:0] first1=first_hole(~occupied[7:4]);
    // firstc 对 first_hole(~occupied[11:8]) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [2:0] firstc=first_hole(~occupied[11:8]);
    // second0 对 second_hole(~occupied[3:0]) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [2:0] second0=second_hole(~occupied[3:0]);
    // second1 对 second_hole(~occupied[7:4]) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [2:0] second1=second_hole(~occupied[7:4]);
    // secondc 对 second_hole(~occupied[11:8]) 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    wire [2:0] secondc=second_hole(~occupied[11:8]);
    // count0 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    // count0 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {2'b0,occupied[0]}+{2'b0,occupied[1]}+ {2'b0,occupied[2]}+{2'b0,occupied[3]}；复制大括号表示重复位域，不是独立队列元素。
    wire [2:0] count0={2'b0,occupied[0]}+{2'b0,occupied[1]}+
                      {2'b0,occupied[2]}+{2'b0,occupied[3]};
    // count1 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    // count1 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {2'b0,occupied[4]}+{2'b0,occupied[5]}+ {2'b0,occupied[6]}+{2'b0,occupied[7]}；复制大括号表示重复位域，不是独立队列元素。
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
