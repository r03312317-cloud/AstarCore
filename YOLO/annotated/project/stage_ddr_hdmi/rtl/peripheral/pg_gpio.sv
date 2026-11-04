// 架构导读：pg_gpio。
// GPIO 输入采样及输出控制寄存器。
module pg_gpio #(
    // 静态配置：parameter int WIDTH = 32。
    parameter int WIDTH = 32
) (
    input logic clk, rst,
    input logic [WIDTH-1:0] pins_in,
    input logic [WIDTH-1:0] value_out,
    output logic [WIDTH-1:0] pins_out,
    output logic [WIDTH-1:0] sampled_in
);
    logic [WIDTH-1:0] meta_q;
    assign pins_out = value_out;
    // 过程边界：always_ff @(posedge clk) begin。
    // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
    always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin meta_q <= '0; sampled_in <= '0; end
        else begin meta_q <= pins_in; sampled_in <= meta_q; end
    end
endmodule
