// [ARCH] 同步单比特电平，降低异步状态直接进入控制逻辑的风险。
// [ARCH] 同步需要若干拍，目标域变化不与源域同拍。
// [ARCH] 它不是任意数据宽度的传输协议。
// [ARCH] 相关信号的一致性由上层保证。
// Only for a sticky/state LEVEL, never for unacknowledged one-cycle pulses.
module pg_level_sync(input logic clk,rst,input logic async_level,output logic level);
 timeunit 1ns;timeprecision 1ps;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic meta_q,sync_q;
 always_ff @(posedge clk or posedge rst)
  if(rst)begin meta_q<=0;sync_q<=0;end
  else begin meta_q<=async_level;sync_q<=meta_q;end
 assign level=sync_q;
endmodule
