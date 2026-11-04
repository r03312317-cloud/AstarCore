// [ARCH] SRAM 银行提供复位代码和数据，PDS 将初始化镜像绑定到真实存储。
// [ARCH] 同步读有明确返回拍，需要提前保持地址和使能。
// [ARCH] 字节写掩码保护同一字中的其他字节。
// [ARCH] 越界访问返回错误，不能静默折返另一段存储。
// [ARCH] 调试时应区分缓存命中值与阵列真正读出的值。
// Derived from the selected RV32 build board SRAM adapter; CPU/cache RTL is unchanged.
// Two instances preserve the game 0x10000000 / 0x20000000 software map.
// 64 KiB initialized dual-port SRAM, two independent eight-beat read channels,
// and a serialized full-line writeback channel. No TCM/cache bypass is used.
module rv32_game_sram #(
    parameter INIT_FILE="",
    parameter [15:0] BASE_PREFIX=16'h1000
)(
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input clk, reset,
    // [ARCH] i_req：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    input i_req, output i_gnt, input [31:0] i_addr,
    // [ARCH] i_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    output i_valid, input i_ready, output [63:0] i_data, output i_error,
    // [ARCH] d_req：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    input d_req, output d_gnt, input [31:0] d_addr, input d_id,
    // [ARCH] d_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    output d_valid, input d_ready, output [63:0] d_data,
    // [ARCH] d_error：错误与对应载荷一起解释，不能归给随后复用同一端口的新请求。
    output d_error, output d_rid,
    // [ARCH] w_req：提出请求不等于事务完成；接纳条件和后续响应必须分别追踪。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 write_fire, d_gnt 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input w_req, output w_gnt, input [31:0] w_addr,
    // [ARCH] w_data：载荷随事务身份传递，不能仅因总线上出现数值就视为一次新传输。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 ram 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input [63:0] w_data, input w_last, w_id,
    // [ARCH] b_valid：限定对应载荷何时有效，等待或复位后的总线残留值不可被误消费。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 d_gnt, w_gnt, b_error, b_id 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    output reg b_valid, output reg b_error, b_id
);
    localparam IDLE=2'd0, ISSUE=2'd1, RESPONSE=2'd2;
    (* syn_ramstyle="block_ram" *) reg [63:0] ram [0:8191];
    reg [63:0] i_q, d_q;
    // [ARCH] i_state：协议阶段寄存器决定当前允许的请求、等待与完成行为。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 i_q, i_gnt, i_valid, d_state 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [1:0] i_state, d_state;
    reg [9:0] i_line, d_line;
    // [ARCH] i_beat：选择当前项/拍/地址片段；范围与回绕需和对应容量/事务上下文一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 i_q, d_beat, w_beat, i_line 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    reg [2:0] i_beat, d_beat, w_beat;
    reg i_bad, d_bad, d_tag, w_bad;
    // [ARCH] write_fire：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 b_address, b_enable, ram 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire write_fire=w_req && w_gnt;
    wire write_bad=(w_addr[31:16]!=BASE_PREFIX || w_addr[5:0]!=0);
    // [ARCH] b_address：保持当前事务地址，等待/背压期间不能换成下一请求的地址。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 ram, d_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire [12:0] b_address=write_fire ? {w_addr[15:6],w_beat} : {d_line,d_beat};
    // [ARCH] b_enable：控制一次状态/载荷接纳，调试时与对应有效身份和资源条件一起观察。
    wire b_enable=(write_fire && !write_bad) || (d_state==ISSUE && !d_bad);

    initial if (INIT_FILE != "") $readmemh(INIT_FILE,ram);
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
                    i_bad<=(i_addr[31:16]!=BASE_PREFIX || i_addr[5:0]!=0);
                    // Invalid addresses need no SRAM read. Return the first
                    // error beat next cycle; preserve all eight handshakes.
                    i_state<=(i_addr[31:16]!=BASE_PREFIX || i_addr[5:0]!=0)?RESPONSE:ISSUE;
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
                    d_bad<=(d_addr[31:16]!=BASE_PREFIX || d_addr[5:0]!=0);
                    d_state<=(d_addr[31:16]!=BASE_PREFIX || d_addr[5:0]!=0)?RESPONSE:ISSUE;
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
