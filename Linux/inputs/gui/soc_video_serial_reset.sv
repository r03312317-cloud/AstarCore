// SPDX-License-Identifier: MIT
// The serial reset no longer has DDR/CPU-domain signals on async reset pins.
// PLL loss/external reset assert asynchronously; both readiness levels pass
// through a two-flop serial-clock synchronizer before enabling the serializer.
// 串行视频控制把异步故障与 PLL 锁定状态变成串行域可用的复位和使能。
// 异步置位可以迅速停止输出，释放过程经本域寄存链避免亚稳态直接扩散。
// 时钟稳定之前保持复位，不能用像素域的同步完成替代串行域的释放。
module soc_video_serial_reset(
 input wire serial_clk,hard_arst,pll_locked,ddr_ready_async,boot_release_async,
 output wire serial_reset
);
 wire root_reset;
 soc_reset_sync u_root(.clk(serial_clk),.arst(hard_arst||!pll_locked),.rst(root_reset));
 (* PAP_ASYNC_REG=1, syn_preserve=1 *) reg ready_meta,ready_sync;
 always @(posedge serial_clk)begin
  if(root_reset)begin ready_meta<=0;ready_sync<=0;end
  else begin ready_meta<=ddr_ready_async&&boot_release_async;ready_sync<=ready_meta;end
 end
 assign serial_reset=root_reset||!ready_sync;
endmodule
