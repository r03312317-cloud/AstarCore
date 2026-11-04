// One synchronous read and one static-column masked write. No reset on data RAM.
// Each word stores PACK_ELEMS consecutive K values from one A lane.
// 架构导读：npu_spad_packed_ram。
// 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
module npu_spad_packed_ram #(
 // 静态配置：parameter int ADDR_W=4, PACK_ELEMS=8。
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
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  for(integer b=0;b<PACK_ELEMS;b++)
   if(wr_mask[b])memory[wr_addr][b*16+:16]<=wr_data[b*16+:16];
  if(rd_en)rd_data<=memory[rd_addr];
 end
endmodule
