// [ARCH] 源域先注册慢速状态，再交给目标域同步链。
// [ARCH] 源寄存器减少组合毛刺，不能取代目标同步。
// [ARCH] 适用于状态观测，不用于逐拍传送高吞吐数据。
// Capture a sticky/state level BEFORE crossing. Not a pulse-lossless bridge.
// One source-clock latency; assertion/ack and software W1C remain at source.
module pg_source_level_register(input logic clk,rst,level_in,output logic level_out);
 timeunit 1ns;timeprecision 1ps;
 (* KEEP="TRUE" *) logic source_q;
 always_ff @(posedge clk or posedge rst)
  if(rst)source_q<=1'b0;else source_q<=level_in;
 assign level_out=source_q;
endmodule
