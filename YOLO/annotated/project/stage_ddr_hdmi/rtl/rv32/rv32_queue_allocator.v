// Independently authored RV32 queue resource boundary, Verilog-2001.
// The inputs describe registered occupancy and the two decoded requests only.
// There is deliberately no execution, completion, wakeup or release input.
// 架构导读：rv32_queue_allocator。
// 分配队列项并处理释放边界，避免仍被占用的项目重复分配。
module rv32_queue_allocator(
    // 接口声明：input [11:0] occupied。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input [11:0] occupied,
    // 接口声明：input complex0,complex1,steer。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input complex0,complex1,steer,
    // 接口声明：output valid0,valid1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output valid0,valid1,
    // 接口声明：output [3:0] slot0,slot1。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    output [3:0] slot0,slot1
);
    // Each four-entry bank finds its first two holes in parallel. This avoids
    // a global first-slot selection followed by a second global rescan.
    function [2:0] first_hole;
        // 接口声明：input [3:0] holes。
        // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
        input [3:0] holes;
        begin
            first_hole={|holes,2'b00};
            if(holes[0])first_hole[1:0]=0;
            else if(holes[1])first_hole[1:0]=1;
            else if(holes[2])first_hole[1:0]=2;
            else first_hole[1:0]=3;
        end
    endfunction
    // 局部运算/辅助过程：function [2:0] second_hole;。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function [2:0] second_hole;
        // 接口声明：input [3:0] holes。
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
