// Original board adapter. The RV32 CPU/cache sources are unchanged.
// 64 KiB initialized dual-port SRAM, two independent eight-beat read channels,
// and a serialized full-line writeback channel. No TCM/cache bypass is used.
// 中文架构说明  与上次130MHz实板源保持同一逻辑版本
// 64KiB 板级片上 SRAM 参考实现，为 I/D 行读及写回通道提供真实存储。
// 固件通过 INIT_FILE 初始化；UART loader 也可在 CPU 复位期间经同一写口装载。
// 行读以 64 位为一拍顺序返回，独立 I/D 状态保存各自事务位置。
// 地址范围外或非法事务产生错误，不返回人为固定的成功数据。
// 写回按有效请求更新，末拍产生写响应，不能把发出写请求当作已经完成。
// 本板 CoreMark 使用这条 SRAM 加 I/D Cache 路径，不是 DDR 性能测试。
// 接口契约与阅读示例
// 正常读每个beat先进入ISSUE执行同步RAM读，再进入RESPONSE等待消费者ready。
// 因此该SRAM模型的读行并非无背压每时钟返回一拍，CPU统计包含实际事务节奏。
// I侧独立读口可与D侧工作重叠；D读和写回共享另一个物理端口。
// 写端口地址必须只有一个统一表达式，避免综合器误推断超出双口BRAM的多地址写结构
// 。
// 非法行地址仍返回完整错误突发的8次握手，不能让Cache永久等缺失数据拍。
// 读输出在RESPONSE背压期间保持原寄存数据，不能被下一beat提前替换。
// 写回收到w_last后生成b_valid，错误还包括拍数或末拍位置不正确。
// 所有这些周期和背压都参与实板CoreMark时间，未旁路Cache或人为缩短访存。
module rv32_board_memory #(
    // 参数 INIT_FILE：SRAM初始化文件路径；
    // 真实固件身份需由bin/hex和构建哈希绑定。
    parameter INIT_FILE="firmware.hex"
)(
    // 接口字段：input clk, reset。
    // 时钟/复位/取消控制。同步状态在指定边界更新；
    // cancel清除所有权而非创造成功响应。
    input clk, reset,
    // 接口字段：input i_req, output i_gnt, input [31:0] i_addr。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    input i_req, output i_gnt, input [31:0] i_addr,
    // 接口字段：output i_valid, input i_ready, output [63:0] i_data, output
    // i_error。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    output i_valid, input i_ready, output [63:0] i_data, output i_error,
    // 接口字段：input d_req, output d_gnt, input [31:0] d_addr, input d_id。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    input d_req, output d_gnt, input [31:0] d_addr, input d_id,
    // 接口字段：output d_valid, input d_ready, output [63:0] d_data。
    // 队列资源或调度资格。占用、源就绪、年龄与操作类型分别决定是否能被选择。
    output d_valid, input d_ready, output [63:0] d_data,
    // 接口字段：output d_error, output d_rid。
    // 错误或非法资格。需随相应有效指令/事务传播，最终在精确提交边界处理。
    output d_error, output d_rid,
    // 接口字段：input w_req, output w_gnt, input [31:0] w_addr。
    // 外部事务通道。req/gnt许可请求，rvalid/rready或写响应确认返回；
    // 数据变化不等于完成。
    input w_req, output w_gnt, input [31:0] w_addr,
    // 接口字段：input [63:0] w_data, input w_last, w_id。
    // 64KiB 板级片上 SRAM 参考实现，为 I/D 行读及写回通道提供真实存储。
    input [63:0] w_data, input w_last, w_id,
    // 接口字段：output reg b_valid, output reg b_error, b_id。
    // 错误或非法资格。需随相应有效指令/事务传播，最终在精确提交边界处理。
    output reg b_valid, output reg b_error, b_id
);
    localparam IDLE=2'd0, ISSUE=2'd1, RESPONSE=2'd2;
    (* syn_ramstyle="block_ram" *) reg [63:0] ram [0:8191];
    reg [63:0] i_q, d_q;
    reg [1:0] i_state, d_state;
    reg [9:0] i_line, d_line;
    reg [2:0] i_beat, d_beat, w_beat;
    reg i_bad, d_bad, d_tag, w_bad;
    wire write_fire=w_req && w_gnt;
    wire write_bad=(w_addr[31:16]!=16'h1000 || w_addr[5:0]!=0);
    wire [12:0] b_address=write_fire ? {w_addr[15:6],w_beat} : {d_line,d_beat};
    wire b_enable=(write_fire && !write_bad) || (d_state==ISSUE && !d_bad);

    initial $readmemh(INIT_FILE,ram);
    // Separate clocked ports preserve synchronous block-RAM inference.
    // The CPU serializes data fills and writebacks; instruction fills are free
    // to run in parallel. Read data stays stable for arbitrary response stalls.
    always @(posedge clk)
        if(i_state==ISSUE && !i_bad) i_q<=ram[{i_line,i_beat}];
    always @(posedge clk)
        if(b_enable) begin
            // A single shared address is essential: these mutually exclusive
            // operations are the same physical port, not three RAM ports.
            if(write_fire) ram[b_address]<=w_data;
            d_q<=ram[b_address];
        end
    assign i_gnt=(i_state==IDLE) && !reset;
    assign d_gnt=(d_state==IDLE) && !w_req && (w_beat==0) && !b_valid && !reset;
    assign w_gnt=(d_state==IDLE) && !b_valid && !reset;
    assign i_valid=(i_state==RESPONSE);
    assign d_valid=(d_state==RESPONSE);
    assign i_data=i_bad ? 64'b0 : i_q;
    assign d_data=d_bad ? 64'b0 : d_q;
    assign i_error=i_bad;
    assign d_error=d_bad;
    assign d_rid=d_tag;
    always @(posedge clk) begin
        if(reset) begin
            i_state<=IDLE; d_state<=IDLE; i_line<=0; d_line<=0;
            i_beat<=0; d_beat<=0; w_beat<=0;
            i_bad<=0; d_bad<=0; d_tag<=0; w_bad<=0;
            b_valid<=0; b_error<=0; b_id<=0;
        end else begin
            b_valid<=0;
            case(i_state)
                IDLE: if(i_req && i_gnt) begin
                    i_line<=i_addr[15:6]; i_beat<=0;
                    i_bad<=(i_addr[31:16]!=16'h1000 || i_addr[5:0]!=0);
                    // Invalid addresses need no SRAM read. Return the first
                    // error beat next cycle; preserve all eight handshakes.
                    i_state<=(i_addr[31:16]!=16'h1000 || i_addr[5:0]!=0)?RESPONSE:ISSUE;
                end
                ISSUE: i_state<=RESPONSE;
                RESPONSE: if(i_ready) begin
                    if(i_beat==7) i_state<=IDLE;
                    else begin i_beat<=i_beat+1'b1; i_state<=i_bad?RESPONSE:ISSUE; end
                end
                default: i_state<=IDLE;
            endcase
            case(d_state)
                IDLE: if(d_req && d_gnt) begin
                    d_line<=d_addr[15:6]; d_beat<=0; d_tag<=d_id;
                    d_bad<=(d_addr[31:16]!=16'h1000 || d_addr[5:0]!=0);
                    d_state<=(d_addr[31:16]!=16'h1000 || d_addr[5:0]!=0)?RESPONSE:ISSUE;
                end
                ISSUE: d_state<=RESPONSE;
                RESPONSE: if(d_ready) begin
                    if(d_beat==7) d_state<=IDLE;
                    else begin d_beat<=d_beat+1'b1; d_state<=d_bad?RESPONSE:ISSUE; end
                end
                default: d_state<=IDLE;
            endcase
            if(write_fire) begin
                w_bad<=w_bad | write_bad | (w_last!=(w_beat==7));
                w_beat<=w_beat+1'b1;
                if(w_last) begin
                    b_valid<=1; b_id<=w_id;
                    b_error<=w_bad | write_bad | (w_beat!=7);
                    w_beat<=0; w_bad<=0;
                end
            end
        end
    end
endmodule
