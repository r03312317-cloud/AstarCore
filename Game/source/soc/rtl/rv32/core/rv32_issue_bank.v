// [ARCH] 局部发射银行对主核保存的候选做组合选择，本模块不保存指令状态。
// [ARCH] 队列编号与 ROB tag 不同，释放和分配必须保持所有者唯一。
// [ARCH] 只有上层准入后的选择才消费候选，组合选择不是实际发射。
// [ARCH] 完成广播只为身份匹配的依赖形成组合可用值；队列有效位与源准备状态由外层维护。
// [ARCH] 活动掩码裁剪不用的行，不能按最大数组编号推算实际容量。
// Original RV32 four-entry scheduling bank, October 2026.
// No state and no speculative readiness: current broadcasts are usable only
// when their actual completion is valid. All rank comparisons use pre-existing
// ages, not a candidate index selected by another readiness-dependent mux.
module rv32_issue_bank #(
    // [ARCH] FAST_WAKEUP：允许使用有效完成广播尽早解析依赖，不改变生产者身份匹配。
    parameter FAST_WAKEUP=1
)(
    input wire [3:0] occupied,issue_allowed,
    input wire [15:0] ages,
    // [ARCH] left_ready：源操作数已经准备好的资格位，仍需 occupied、issue_allowed 与另一源一起决定候选可发射性。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 eligible, available_left, available_right 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input wire [3:0] left_ready,right_ready,
    // [ARCH] left_tags：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    input wire [15:0] left_tags,right_tags,
    // [ARCH] left_values：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 ready_left 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input wire [127:0] left_values,right_values,
    // [ARCH] broadcast_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    input wire [2:0] broadcast_valid,
    input wire [11:0] broadcast_tags,
    input wire [95:0] broadcast_values,
    output reg [3:0] eligible,
    // [ARCH] occupancy_count：统计已接受的有效占用/事件；同时增减时要保留净变化。
    output wire [2:0] occupancy_count,
    // [ARCH] first_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    output wire first_valid,second_valid,
    output wire [1:0] first_slot,second_slot,
    output wire [3:0] first_age,second_age,
    // [ARCH] first_left：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    output wire [31:0] first_left,first_right,second_left,second_right
);
    // [ARCH] ready_left：组合选择的操作数载荷，优先接入匹配的有效完成广播；本数组不保存时序状态。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 available_left, first_left, second_left 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [31:0] ready_left[0:3],ready_right[0:3];
    // [ARCH] available_left：左操作数必须与拥有者和就绪状态一致，未就绪数据不能直接发射。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 eligible, available_right, ready_left 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [3:0] available_left,available_right,first_mask,second_mask;
    reg [3:0] older[0:3];
    integer i,j;
    always @* begin
        eligible=0;available_left=left_ready;available_right=right_ready;
        first_mask=0;second_mask=0;
        for(i=0;i<4;i=i+1)begin
            ready_left[i]=left_values[i*32+:32];
            ready_right[i]=right_values[i*32+:32];
            // Later channels retain the established deterministic priority.
            for(j=0;j<3;j=j+1)begin
                if(FAST_WAKEUP&&!left_ready[i]&&broadcast_valid[j]&&
                   broadcast_tags[j*4+:4]==left_tags[i*4+:4])begin
                    available_left[i]=1;ready_left[i]=broadcast_values[j*32+:32];
                end
                if(FAST_WAKEUP&&!right_ready[i]&&broadcast_valid[j]&&
                   broadcast_tags[j*4+:4]==right_tags[i*4+:4])begin
                    available_right[i]=1;ready_right[i]=broadcast_values[j*32+:32];
                end
            end
            eligible[i]=occupied[i]&&issue_allowed[i]&&available_left[i]&&available_right[i];
        end
        // Rank each eligible entry in parallel. Equal-age ties prefer the
        // lower local slot, matching the original ascending queue scan.
        for(i=0;i<4;i=i+1)begin
            for(j=0;j<4;j=j+1)begin
                older[i][j]=(i!=j)&&eligible[j]&&
                    ((ages[j*4+:4]<ages[i*4+:4])||
                     ((ages[j*4+:4]==ages[i*4+:4])&&(j<i)));
            end
            first_mask[i]=eligible[i]&&!(|older[i]);
            second_mask[i]=eligible[i]&&((older[i]==4'b0001)||(older[i]==4'b0010)||
                                        (older[i]==4'b0100)||(older[i]==4'b1000));
        end
    end
    assign occupancy_count={2'b0,occupied[0]}+{2'b0,occupied[1]}+
                           {2'b0,occupied[2]}+{2'b0,occupied[3]};
    assign first_valid=|first_mask;
    assign second_valid=|second_mask;
    assign first_slot={first_mask[2]|first_mask[3],first_mask[1]|first_mask[3]};
    assign second_slot={second_mask[2]|second_mask[3],second_mask[1]|second_mask[3]};
    assign first_age=({4{first_mask[0]}}&ages[3:0])|({4{first_mask[1]}}&ages[7:4])|
                     ({4{first_mask[2]}}&ages[11:8])|({4{first_mask[3]}}&ages[15:12]);
    assign second_age=({4{second_mask[0]}}&ages[3:0])|({4{second_mask[1]}}&ages[7:4])|
                      ({4{second_mask[2]}}&ages[11:8])|({4{second_mask[3]}}&ages[15:12]);
    assign first_left=({32{first_mask[0]}}&ready_left[0])|({32{first_mask[1]}}&ready_left[1])|
                      ({32{first_mask[2]}}&ready_left[2])|({32{first_mask[3]}}&ready_left[3]);
    assign first_right=({32{first_mask[0]}}&ready_right[0])|({32{first_mask[1]}}&ready_right[1])|
                       ({32{first_mask[2]}}&ready_right[2])|({32{first_mask[3]}}&ready_right[3]);
    assign second_left=({32{second_mask[0]}}&ready_left[0])|({32{second_mask[1]}}&ready_left[1])|
                       ({32{second_mask[2]}}&ready_left[2])|({32{second_mask[3]}}&ready_left[3]);
    assign second_right=({32{second_mask[0]}}&ready_right[0])|({32{second_mask[1]}}&ready_right[1])|
                        ({32{second_mask[2]}}&ready_right[2])|({32{second_mask[3]}}&ready_right[3]);
endmodule
