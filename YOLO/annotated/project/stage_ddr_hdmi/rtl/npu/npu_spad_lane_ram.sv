// Portable synchronous simple-dual-port lane memory. No data reset or init.
// A same-address read/write returns pre-edge data (READ_FIRST). The scratchpad
// owner protocol normally prevents such a collision but the leaf defines it.
// 架构导读：npu_spad_lane_ram。
// 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
module npu_spad_lane_ram #(
  parameter int ADDR_W = 7
)(
  input logic clk,wr_en,rd_en,
  input logic [ADDR_W-1:0] wr_addr,rd_addr,
  input logic [15:0] wr_data,
  output logic [15:0] rd_data
);
  (* ram_style = "block" *) logic [15:0] mem [0:(1<<ADDR_W)-1];
  // 过程边界：always_ff @(posedge clk) begin。
  always_ff @(posedge clk) begin
    if (wr_en) mem[wr_addr] <= wr_data;
    if (rd_en) rd_data <= mem[rd_addr];
  end
  initial if (ADDR_W < 4 || ADDR_W > 9)
    $fatal(1,"TC_SPAD_ADDR_W");
endmodule
