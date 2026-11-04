// Registered-occupancy FIFO; no out_ready -> in_ready combinational path.
// 架构导读：pg_sync_fifo。
// FIFO 缓冲模块，隔离生产者与消费者，满/空条件由指针和容量关系决定。
module pg_sync_fifo #(
    // 静态配置：parameter int WIDTH=32, DEPTH=16。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    parameter int WIDTH=32, DEPTH=16
)(
    input logic clk,rst,
    input logic in_valid, output logic in_ready, input logic [WIDTH-1:0] in_data,
    output logic out_valid, input logic out_ready, output logic [WIDTH-1:0] out_data,
    output logic [$clog2(DEPTH+1)-1:0] level
);
    // 静态配置：localparam int CW=$clog2(DEPTH+1)。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam int CW=$clog2(DEPTH+1);
    // 静态配置：localparam int PW=(DEPTH<2)?1:$clog2(DEPTH)。
    // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
    localparam int PW=(DEPTH<2)?1:$clog2(DEPTH);
    logic [PW-1:0] rp,wp;
    logic [WIDTH-1:0] data[DEPTH];
    logic push,pop;
    assign in_ready=!rst&&(level<CW'(DEPTH));
    assign out_valid=!rst&&(level!=0);
    assign out_data=out_valid?data[rp]:'0;
    assign push=in_valid&&in_ready;
    assign pop=out_valid&&out_ready;
    // 局部运算/辅助过程：function automatic logic [PW-1:0] inc(input logic [PW-1:0] p);。
    // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
    function automatic logic [PW-1:0] inc(input logic [PW-1:0] p);
        return (p==PW'(DEPTH-1))?'0:p+1'b1;
    endfunction
    initial if(WIDTH<1||DEPTH<1) $fatal(1,"PG_FIFO_PARAMETER_RED");
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if(rst) begin rp<='0;wp<='0;level<='0;end
        else begin
            // 按 {push,pop} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
            case({push,pop})
                2'b10:level<=level+1'b1;
                2'b01:level<=level-1'b1;
                default:begin end
            endcase
            if(push)begin data[wp]<=in_data;wp<=inc(wp);end
            if(pop)rp<=inc(rp);
        end
    end
endmodule
