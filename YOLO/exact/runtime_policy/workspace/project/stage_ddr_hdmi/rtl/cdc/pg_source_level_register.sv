// Capture a sticky/state level BEFORE crossing. Not a pulse-lossless bridge.
// One source-clock latency; assertion/ack and software W1C remain at source.
module pg_source_level_register(input logic clk,rst,level_in,output logic level_out);
 timeunit 1ns;timeprecision 1ps;
 (* KEEP="TRUE" *) logic source_q;
 always_ff @(posedge clk or posedge rst)
  if(rst)source_q<=1'b0;else source_q<=level_in;
 assign level_out=source_q;
endmodule
