// Only for a sticky/state LEVEL, never for unacknowledged one-cycle pulses.
module pg_level_sync(input logic clk,rst,input logic async_level,output logic level);
 timeunit 1ns;timeprecision 1ps;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic meta_q,sync_q;
 always_ff @(posedge clk or posedge rst)
  if(rst)begin meta_q<=0;sync_q<=0;end
  else begin meta_q<=async_level;sync_q<=meta_q;end
 assign level=sync_q;
endmodule
