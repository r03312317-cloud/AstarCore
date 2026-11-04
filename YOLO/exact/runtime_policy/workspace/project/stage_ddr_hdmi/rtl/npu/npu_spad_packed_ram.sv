// One synchronous read and one static-column masked write. No reset on data RAM.
// Each word stores PACK_ELEMS consecutive K values from one A lane.
module npu_spad_packed_ram #(
 parameter int ADDR_W=4, PACK_ELEMS=8
)(
 input logic clk,
 input logic [PACK_ELEMS-1:0] wr_mask,
 input logic [ADDR_W-1:0] wr_addr,
 input logic [PACK_ELEMS*16-1:0] wr_data,
 input logic rd_en,
 input logic [ADDR_W-1:0] rd_addr,
 output logic [PACK_ELEMS*16-1:0] rd_data
);
 (* ram_style="block" *) logic [PACK_ELEMS*16-1:0] memory [0:(1<<ADDR_W)-1];
 always_ff @(posedge clk)begin
  for(integer b=0;b<PACK_ELEMS;b++)
   if(wr_mask[b])memory[wr_addr][b*16+:16]<=wr_data[b*16+:16];
  if(rd_en)rd_data<=memory[rd_addr];
 end
endmodule
