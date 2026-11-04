// [ARCH] 根据空闲槽和指令类别提出最多两个有序的分配位置。
// [ARCH] 活动掩码限定合法编号，停用行不能获得新指令所有权。
// [ARCH] 双分配必须使用两个不同空槽。
// [ARCH] 分配提案和最终接纳分开，恢复可以取消接纳而不重写提案路径。
// [ARCH] 分配次序与 ROB 中的程序顺序保持一致。
// Independently authored RV32 queue resource boundary, Verilog-2001.
// The inputs describe registered occupancy and the two decoded requests only.
// There is deliberately no execution, completion, wakeup or release input.
module rv32_queue_allocator(
    input [11:0] occupied,
    input complex0,complex1,steer,
    // [ARCH] valid0：标记本槽/载荷是否属于一个有效所有者；数据 RAM 的残留值本身不能代替有效位。
    output valid0,valid1,
    output [3:0] slot0,slot1
);
    // Each four-entry bank finds its first two holes in parallel. This avoids
    // a global first-slot selection followed by a second global rescan.
    // [ARCH] 从允许的空闲集合找第一个可分配位置。
    // [ARCH] 不存在合法空位时不能把默认编号当作有效分配。
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
    // [ARCH] 在排除第一个候选后找另一个空位。
    // [ARCH] 双分配不能让两条指令占有同一物理行。
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
    // [ARCH] count0：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 preferred 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire [2:0] count0={2'b0,occupied[0]}+{2'b0,occupied[1]}+
                      {2'b0,occupied[2]}+{2'b0,occupied[3]};
    // [ARCH] count1：统计已接受的有效占用/事件；同时增减时要保留净变化。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 preferred 赋值；同一行可能含多个语句，不能据此单独推断依赖。
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
