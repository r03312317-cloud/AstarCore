// Original RV32 four-entry scheduling bank, October 2026.
// No state and no speculative readiness: current broadcasts are usable only
// when their actual completion is valid. All rank comparisons use pre-existing
// ages, not a candidate index selected by another readiness-dependent mux.
// 局部发射 bank 接收已占有的队列行和操作数就绪信息，提出局部候选。
// 年龄比较使用相对 ROB 头部的顺序信息，环绕标签不能直接作无符号大小比较。
// 本模块提出的有效候选还要与外层资源许可合并，提议不是最终接受事件。
// 广播唤醒携带生产者身份，不能仅凭数据数值相等认定依赖满足。
module rv32_issue_bank #(
    parameter FAST_WAKEUP=1
)(
    input wire [3:0] occupied,issue_allowed,
    input wire [15:0] ages,
    // left_ready 保存左源操作数已经可用的标志，标签存在不等于值已经可用。
    input wire [3:0] left_ready,right_ready,
    input wire [15:0] left_tags,right_tags,
    input wire [127:0] left_values,right_values,
    // broadcast_valid 属于完成广播，保存有效资格，标识该项是否属于当前仍可使用的事务。
    // 消费者按生产者标签匹配，数值相同不能替代身份相同。
    input wire [2:0] broadcast_valid,
    input wire [11:0] broadcast_tags,
    input wire [95:0] broadcast_values,
    output reg [3:0] eligible,
    // occupancy_count 保存占用数量或事件数量，不能由某个槽位的旧 payload 推断。
    output wire [2:0] occupancy_count,
    // first_valid 保存有效资格，标识该项是否属于当前仍可使用的事务。
    output wire first_valid,second_valid,
    output wire [1:0] first_slot,second_slot,
    output wire [3:0] first_age,second_age,
    // first_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    output wire [31:0] first_left,first_right,second_left,second_right
);
    // ready_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [31:0] ready_left[0:3],ready_right[0:3];
    // available_left 保存左源操作数值，未就绪时不能把存储中的旧值用于执行。
    reg [3:0] available_left,available_right,first_mask,second_mask;
    reg [3:0] older[0:3];
    integer i,j;
    always @* begin
        eligible=0;available_left=left_ready;available_right=right_ready;
        first_mask=0;second_mask=0;
        for(i=0;i<4;i=i+1)begin
            // ready_left[i] 读取 left_values[i*32+:32] 所选位域；位索引按声明中的高低位顺序解释。
            ready_left[i]=left_values[i*32+:32];
            // ready_right[i] 读取 right_values[i*32+:32] 所选位域；位索引按声明中的高低位顺序解释。
            ready_right[i]=right_values[i*32+:32];
            // Later channels retain the established deterministic priority.
            for(j=0;j<3;j=j+1)begin
                // 本分支处理握手条件 left_ready 与 broadcast_valid；仅满足当前条件时推进下述事务。
                if(FAST_WAKEUP&&!left_ready[i]&&broadcast_valid[j]&&
                   // broadcast_tags[j*4+:4] 按 =left_tags[i*4+:4])begin 计算，运算位宽与有无符号以原声明和显式扩展为准。
                   broadcast_tags[j*4+:4]==left_tags[i*4+:4])begin
                    available_left[i]=1;ready_left[i]=broadcast_values[j*32+:32];
                end
                // 本分支处理握手条件 right_ready 与 broadcast_valid；仅满足当前条件时推进下述事务。
                if(FAST_WAKEUP&&!right_ready[i]&&broadcast_valid[j]&&
                   // broadcast_tags[j*4+:4] 按 =right_tags[i*4+:4])begin 计算，运算位宽与有无符号以原声明和显式扩展为准。
                   broadcast_tags[j*4+:4]==right_tags[i*4+:4])begin
                    available_right[i]=1;ready_right[i]=broadcast_values[j*32+:32];
                end
            end
            // eligible[i] 的资格组合为 occupied[i]&&issue_allowed[i]&&available_left[i]&&available_right[i]。
            // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
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
            // first_mask[i] 的资格组合为 eligible[i]&&!(|older[i])。
            first_mask[i]=eligible[i]&&!(|older[i]);
            // second_mask[i] 的资格组合为 eligible[i]&&((older[i]==4'b0001)||(older[i]==4'b0010)||。
            second_mask[i]=eligible[i]&&((older[i]==4'b0001)||(older[i]==4'b0010)||
                                        (older[i]==4'b0100)||(older[i]==4'b1000));
        end
    end
    // occupancy_count 按从高位到低位的拼接顺序组成，保留各字段原来的位置关系。
    // 拼接源为 {2'b0,occupied[0]}+{2'b0,occupied[1]}+；复制大括号表示重复位域，不是独立队列元素。
    assign occupancy_count={2'b0,occupied[0]}+{2'b0,occupied[1]}+
                           {2'b0,occupied[2]}+{2'b0,occupied[3]};
    // first_valid 对 |first_mask 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
    assign first_valid=|first_mask;
    // second_valid 对 |second_mask 做位级处理；位与 位或和异或不等于整字的逻辑真值组合。
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
