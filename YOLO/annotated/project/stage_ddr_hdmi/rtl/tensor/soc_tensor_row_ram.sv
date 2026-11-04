// One bounded payload bank. No clear loop, dynamic port replication or async
// read. READ_FIRST behavior follows nonblocking writes; owners prove that the
// production controller never consumes a simultaneous same-address collision.
// 架构导读：soc_tensor_row_ram。
// 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
module soc_tensor_row_ram(
 input logic clk,wr_en,rd_en,
 input logic [8:0] wr_addr,rd_addr,
 input logic [127:0] wr_data,
 output logic [127:0] rd_data
);
 (* ram_style="block" *) logic [127:0] payload[0:511];
 always_ff @(posedge clk)begin
  if(wr_en)payload[wr_addr]<=wr_data;
  if(rd_en)rd_data<=payload[rd_addr];
 end
endmodule
