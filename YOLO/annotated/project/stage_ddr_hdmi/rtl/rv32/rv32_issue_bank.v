// Original RV32 four-entry scheduling bank, October 2026.
// No state and no speculative readiness: current broadcasts are usable only
// when their actual completion is valid. All rank comparisons use pre-existing
// ages, not a candidate index selected by another readiness-dependent mux.
// 架构导读：rv32_issue_bank。
// 保存发射项的有效状态与操作数字段，供调度器读取和完成唤醒。
module rv32_issue_bank #(
    // 静态配置：parameter FAST_WAKEUP=1。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter FAST_WAKEUP=1
)(
    // 接口声明：input wire [3:0] occupied,issue_allowed。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input wire [3:0] occupied,issue_allowed,
    // 接口声明：input wire [15:0] ages。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input wire [15:0] ages,
    // 接口声明：input wire [3:0] left_ready,right_ready。
    // 表达接口或资源就绪；需结合相应有效/完成条件解释。
    input wire [3:0] left_ready,right_ready,
    // 接口声明：input wire [15:0] left_tags,right_tags。
    // 把返回信息关联到对应的已接受请求。
    input wire [15:0] left_tags,right_tags,
    // 接口声明：input wire [127:0] left_values,right_values。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input wire [127:0] left_values,right_values,
    // 接口声明：input wire [2:0] broadcast_valid。
    // 标识这一路负载有效；是否接收还需检查对应的消费条件。
    input wire [2:0] broadcast_valid,
    // 接口声明：input wire [11:0] broadcast_tags。
    input wire [11:0] broadcast_tags,
    input wire [95:0] broadcast_values,
    output reg [3:0] eligible,
    output wire [2:0] occupancy_count,
    output wire first_valid,second_valid,
    output wire [1:0] first_slot,second_slot,
    output wire [3:0] first_age,second_age,
    output wire [31:0] first_left,first_right,second_left,second_right
);
    reg [31:0] ready_left[0:3],ready_right[0:3];
    reg [3:0] available_left,available_right,first_mask,second_mask;
    reg [3:0] older[0:3];
    integer i,j;
    // 过程边界：always @* begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always @* begin
        eligible=0;available_left=left_ready;available_right=right_ready;
        first_mask=0;second_mask=0;
        for(i=0;i<4;i=i+1)begin
            ready_left[i]=left_values[i*32+:32];
            ready_right[i]=right_values[i*32+:32];
            // Later channels retain the established deterministic priority.
            for(j=0;j<3;j=j+1)begin
                // 握手/背压判断：FAST_WAKEUP&&!left_ready[i]&&broadcast_valid[j]&&。
                // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
                if(FAST_WAKEUP&&!left_ready[i]&&broadcast_valid[j]&&
                   broadcast_tags[j*4+:4]==left_tags[i*4+:4])begin
                    available_left[i]=1;ready_left[i]=broadcast_values[j*32+:32];
                end
                // 握手/背压判断：FAST_WAKEUP&&!right_ready[i]&&broadcast_valid[j]&&。
                // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
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
