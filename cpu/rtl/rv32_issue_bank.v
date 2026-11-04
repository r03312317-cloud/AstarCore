// Original RV32 four-entry scheduling bank, October 2026.
// No state and no speculative readiness: current broadcasts are usable only
// when their actual completion is valid. All rank comparisons use pre-existing
// ages, not a candidate index selected by another readiness-dependent mux.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 四项局部调度兼容模块，按现有 age 对就绪项并行排名。
// 原 ready 或标签匹配的真实完成广播提供可用操作数。
// eligible 同时需要 occupied、issue_allowed 及左右源均可用。
// 相同年龄由较小本地索引优先，第一和第二候选由较老项数量决定。
// 输出 occupancy_count 为物理占用统计，不表示可发射数量。
// 本模块无内部状态，正常相对年龄调度路径与本兼容模块需按 generate 配置区分。
// 接口契约与阅读示例
// 同拍旁路可使原left_ready为0的项获得有效左值，右值也需要独立满足许可。
// 后面的广播通道匹配会覆盖前面通道，优先级必须与原核心一致。
// 两个相同年龄条目按本地小索引优先，保证兼容策略确定性。
// first_slot与second_slot的编码不包含额外valid位，不能在valid=0时使用。
// occupancy_count包含尚未就绪的项，所以与first_valid并不等价。
// 该局部年龄模块的存在不表示本板正常相对关系路径重新读取了ROB全局序号。
module rv32_issue_bank #(
    // 参数 FAST_WAKEUP：真实完成标签可以在原ready置位前被当拍消费者使用，
    // 仍需广播valid资格。
    parameter FAST_WAKEUP=1
)(
    // 接口字段：input wire [3:0] occupied,issue_allowed。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    input wire [3:0] occupied,issue_allowed,
    // 接口字段：input wire [15:0] ages。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    input wire [15:0] ages,
    // 接口字段：input wire [3:0] left_ready,right_ready。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    input wire [3:0] left_ready,right_ready,
    // 接口字段：input wire [15:0] left_tags,right_tags。
    // 生产者或事务标签。只关联所有者，不代表算术值，也不能单凭标签判断已完成。
    input wire [15:0] left_tags,right_tags,
    // 接口字段：input wire [127:0] left_values,right_values。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
    input wire [127:0] left_values,right_values,
    // 接口字段：input wire [2:0] broadcast_valid。
    // 真实完成旁路的valid、标签或数值。必须同时验证标签和valid，
    // 未就绪数值不可使用。
    input wire [2:0] broadcast_valid,
    // 接口字段：input wire [11:0] broadcast_tags。
    // 真实完成旁路的valid、标签或数值。必须同时验证标签和valid，
    // 未就绪数值不可使用。
    input wire [11:0] broadcast_tags,
    // 接口字段：input wire [95:0] broadcast_values。
    // 真实完成旁路的valid、标签或数值。必须同时验证标签和valid，
    // 未就绪数值不可使用。
    input wire [95:0] broadcast_values,
    // 接口字段：output reg [3:0] eligible。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    output reg [3:0] eligible,
    // 接口字段：output wire [2:0] occupancy_count。
    // 有效数量或消费数量。索引编码只有对应有效/计数许可时才表示存活所有者。
    output wire [2:0] occupancy_count,
    // 接口字段：output wire first_valid,second_valid。
    // 四项局部调度兼容模块，按现有 age 对就绪项并行排名。
    output wire first_valid,second_valid,
    // 接口字段：output wire [1:0] first_slot,second_slot。
    // 四项局部调度兼容模块，按现有 age 对就绪项并行排名。
    output wire [1:0] first_slot,second_slot,
    // 接口字段：output wire [3:0] first_age,second_age。
    // 四项局部调度兼容模块，按现有 age 对就绪项并行排名。
    output wire [3:0] first_age,second_age,
    // 接口字段：output wire [31:0] first_left,first_right,second_left,
    // second_right。
    // 数据计算或选择载荷。输入数据与有效许可分开，
    // 未拥有请求的数据不产生架构副作用。
    output wire [31:0] first_left,first_right,second_left,second_right
);
    reg [31:0] ready_left[0:3],ready_right[0:3];
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
