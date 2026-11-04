// [ARCH] 软件写入的 GPIO 状态供 LED 等板级观察使用。
// [ARCH] 这是 MMIO 寄存器，不应像缓存内存一样随意重排。
// [ARCH] GPIO 变化不能单独证明一帧游戏逻辑已经完成。
module pg_gpio #(
    parameter int WIDTH = 32
) (
    // [ARCH] clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    input logic clk, rst,
    input logic [WIDTH-1:0] pins_in,
    // [ARCH] value_out：保存候选或完成值，只有对应有效/完成条件满足时才具有架构意义。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 pins_out 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input logic [WIDTH-1:0] value_out,
    output logic [WIDTH-1:0] pins_out,
    output logic [WIDTH-1:0] sampled_in
);
    logic [WIDTH-1:0] meta_q;
    assign pins_out = value_out;
    always_ff @(posedge clk) begin
        if (rst) begin meta_q <= '0; sampled_in <= '0; end
        else begin meta_q <= pins_in; sampled_in <= meta_q; end
    end
endmodule
