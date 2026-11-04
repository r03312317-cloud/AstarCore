// [ARCH] 将异步复位转换为目标域可安全释放的复位。
// [ARCH] 同步链级数用于吸收跨域采样的不确定性。
// [ARCH] 目标时钟不运行时不会自行释放。
// [ARCH] 复位控制有效性，不表示所有 RAM 内容被清零。
// Async assertion, two-clock synchronous release. arst is the common hard
// reset for ALL domains and the external AXI isolation/reset contract.
module pg_reset_sync(input logic clk,arst,output logic rst);
 timeunit 1ns;timeprecision 1ps;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic [1:0] release_q;
 always_ff @(posedge clk or posedge arst)
  if(arst) release_q<=2'b11;
  else release_q<={release_q[0],1'b0};
 assign rst=release_q[1];
endmodule
