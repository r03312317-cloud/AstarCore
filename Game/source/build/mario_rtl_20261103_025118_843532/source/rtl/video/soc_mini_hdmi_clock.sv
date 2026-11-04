`timescale 1ns/1ps
// PG2L200H/FBB676 MINI output reference: official 200K dual-camera clk_hdmi.
// The copied PLL is unchanged, including all vendor parameters and notices.
// 27 MHz reference -> 74.25 MHz pixel + 371.25 MHz DDR serializer clock.
// NOTE: this project instantiates the 480p variant of clk_hdmi (RATIOM=2,
// RATIO0=40, RATIO1=8), so the live frequencies are 27 MHz pixel / 135 MHz
// serial.  The line above describes the 720p parameters that were replaced.
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
    wire reset_release = reset_n && pll_locked;
    (* ASYNC_REG = "TRUE" *) reg [2:0] release_q;
    always @(posedge pixel_clk or negedge reset_release) begin
        if (!reset_release) release_q <= 3'b000;
        else release_q <= {release_q[1:0], 1'b1};
    end
    assign pixel_reset_n = release_q[2];
endmodule
