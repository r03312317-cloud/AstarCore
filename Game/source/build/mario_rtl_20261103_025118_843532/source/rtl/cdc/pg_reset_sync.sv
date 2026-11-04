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
