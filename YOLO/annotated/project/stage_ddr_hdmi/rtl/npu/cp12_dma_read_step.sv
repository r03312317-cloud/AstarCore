// Beat-exhausting read progression, modulo 2^32 like the original DMA.
// No cols subtraction, min selection, shift or variable full-width addition.
// 架构导读：cp12_dma_read_step。
module cp12_dma_read_step #(parameter int MEM_BYTES=16)(
 input logic [31:0] address,input logic [1:0] element_bytes,
 output logic [31:0] next_address
);
 timeunit 1ns;timeprecision 1ps;
 localparam int OFF_W=$clog2(MEM_BYTES);
 initial if(MEM_BYTES<4 || (MEM_BYTES&(MEM_BYTES-1))!=0 || OFF_W>=32)
  $fatal(1,"CP12_READ_STEP_PARAMETER");
 logic [31-OFF_W:0] next_beat;
 assign next_beat=address[31:OFF_W]+1'b1;
 // An odd INT16 address ends at the final unconsumable byte, preserving
 // old malformed-leaf behavior. Do not silently align or skip that byte.
 assign next_address=(element_bytes==2'd2 && address[0]) ?
   {address[31:OFF_W],{OFF_W{1'b1}}} : {next_beat,{OFF_W{1'b0}}};
endmodule
