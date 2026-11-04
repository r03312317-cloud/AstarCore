// [ARCH] 当前时钟包装对应 480p60 载波。
// [ARCH] PLL 锁定与像素复位不同，上层需要同步释放显示逻辑。
// [ARCH] 真实参考频率和倍分频来自硬件，软件常量不能改变它。
// [ARCH] 厂商 IP 参数保留在原生成文件。
`timescale 1ns/1ps
// PG2L200H/FBB676 MINI output reference: official 200K dual-camera clk_hdmi.
// The copied PLL is unchanged, including all vendor parameters and notices.
// 27 MHz reference -> 74.25 MHz pixel + 371.25 MHz DDR serializer clock.
// NOTE: this project instantiates the 480p variant of clk_hdmi (RATIOM=2,
// RATIO0=40, RATIO1=8), so the live frequencies are 27 MHz pixel / 135 MHz
// serial.  The line above describes the 720p parameters that were replaced.
module soc_mini_hdmi_clock (
    input  wire sys_clk,
    // [ARCH] reset_n：复位控制不同于 PLL/DDR 就绪；具体极性与同步方式按本模块时序块执行。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 reset_release 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    input  wire reset_n,
    // [ARCH] pixel_clk：所属时钟域的采样基准；跨域信号必须经过对应同步/事务协议。
    output wire pixel_clk,
    // [ARCH] serial_clk：串行操作需要精确提交边界，不能与普通整数候选等同调度。
    output wire serial_clk,
    output wire pll_locked,
    // [ARCH] pixel_reset_n：参与本域复位/就绪控制，释放条件与跨域同步链一起检查。
    output wire pixel_reset_n
);
    clk_hdmi u_pll (
        .clkin1(sys_clk), .clkout0(pixel_clk),
        .clkout1(serial_clk), .lock(pll_locked)
    );
    // [ARCH] reset_release：参与本域复位/就绪控制，释放条件与跨域同步链一起检查。
    // [ARCH] 定位线索：原版中含此标识符的物理行还对 release_q 赋值；同一行可能含多个语句，不能据此单独推断依赖。
    wire reset_release = reset_n && pll_locked;
    (* ASYNC_REG = "TRUE" *) reg [2:0] release_q;
    always @(posedge pixel_clk or negedge reset_release) begin
        if (!reset_release) release_q <= 3'b000;
        else release_q <= {release_q[1:0], 1'b1};
    end
    assign pixel_reset_n = release_q[2];
endmodule
