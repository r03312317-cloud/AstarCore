`timescale 1ns/1ps
// PG2L200H/FBB676 MINI output reference: official 200K dual-camera clk_hdmi.
// PLL parameters match the board-verified 480p reference and retain notices.
// 27 MHz reference -> 27 MHz pixel + 135 MHz DDR serializer clock.
// 此包装层实例化厂商 PLL，产生像素时钟及用于 TMDS 的串行时钟。
// 实板目标为 27 MHz 像素时钟和 135 MHz 串行时钟，锁定后才允许视频路径运行。
// 时钟对象与生成时钟约束必须和 PLL 实例保持一致，不能仅更改模块注释来提频。
module soc_mini_hdmi_clock (
    input  wire sys_clk,
    input  wire reset_n,
    output wire pixel_clk,
    output wire serial_clk,
    output wire pll_locked,
    output wire pixel_reset_n
);
    clk_hdmi u_pll (
        .clkin1(sys_clk), .clkout0(pixel_clk),
        .clkout1(serial_clk), .lock(pll_locked)
    );
    // reset_release 的资格组合为 reset_n && pll_locked。
    // 逻辑与要求相关条件同时成立；逻辑或汇总可接受的替代条件。
    wire reset_release = reset_n && pll_locked;
    (* PAP_ASYNC_REG = 1, syn_preserve = 1 *) reg [2:0] release_q;
    always @(posedge pixel_clk or negedge reset_release) begin
        // 复位分支建立下列状态的初始值；其后的正常更新分支在复位不成立时才执行。
        if (!reset_release) release_q <= 3'b000;
        else release_q <= {release_q[1:0], 1'b1};
    end
    // pixel_reset_n 读取 release_q[2] 所选位域；位索引按声明中的高低位顺序解释。
    assign pixel_reset_n = release_q[2];
endmodule
