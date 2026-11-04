// SPDX-License-Identifier: MIT
// Four locally placeable copies share asynchronous assertion and release
// together on the memory clock, one clock after the upstream reset releases.
// 内存域复位在局部寄存器复制后分发到多个叶节点，降低单网扇出压力。
// 所有叶节点属于同一时钟域，复制不构成普通数据的跨时钟握手。
// 修改扇出或级数会影响复位释放相对时序，本注释版保持原实现。
module soc_mem_reset_fanout(input wire clk,input wire reset_in,output wire [3:0] reset_out);
 (* PAP_PRESERVE=1, syn_preserve=1 *) reg [3:0] local_reset;
 always @(posedge clk or posedge reset_in)
  if(reset_in)local_reset<=4'b1111;else local_reset<=4'b0000;
 assign reset_out=local_reset;
endmodule
