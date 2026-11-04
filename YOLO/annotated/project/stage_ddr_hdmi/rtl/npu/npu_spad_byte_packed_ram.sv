// One synchronous 1R/1W word. Fixed byte lanes; no payload reset or init.
// Same-address read/write returns pre-edge data. Ownership normally excludes it.
// 架构导读：npu_spad_byte_packed_ram。
// 片上存储器数据路径，保存地址、读写使能以及同步读返回状态。
module npu_spad_byte_packed_ram #(parameter int ADDR_W=4)(
  // 接口声明：input logic clk。
  // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
  input logic clk,
  // 接口声明：input logic [15:0] wr_mask。
  input logic [15:0] wr_mask,
  input logic [ADDR_W-1:0] wr_addr,
  input logic [127:0] wr_data,
  input logic rd_en,
  input logic [ADDR_W-1:0] rd_addr,
  output logic [127:0] rd_data
);
  (* ram_style="block" *) logic [127:0] memory [0:(1<<ADDR_W)-1];
  // 过程边界：always_ff @(posedge clk) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) begin
    for (integer b=0;b<16;b=b+1)
      if (wr_mask[b]) memory[wr_addr][b*8+:8] <= wr_data[b*8+:8];
    if (rd_en) rd_data <= memory[rd_addr];
  end
endmodule

// One-cycle READ_FIRST read with a narrow held result. Byte writes and memory
// depth are unchanged; mode/offset are sampled on the same edge as rd_addr.
// Selecting before the output register removes the 128-bit read CE load.
module npu_spad_byte_read16_ram #(parameter int ADDR_W=4)(
  input logic clk,
  input logic [15:0] wr_mask,
  input logic [ADDR_W-1:0] wr_addr,
  input logic [127:0] wr_data,
  input logic rd_en,
  input logic [ADDR_W-1:0] rd_addr,
  input logic [3:0] rd_byte_offset,
  input logic rd_int16,
  output logic [15:0] rd_data
);
  (* ram_style="block" *) logic [127:0] memory [0:(1<<ADDR_W)-1];
  wire [127:0] read_word = memory[rd_addr];
  wire [15:0] read_halfword = read_word[int'(rd_byte_offset[3:1])*16+:16];
  // Both modes use the same halfword selection. Avoid building an additional
  // independent 16-to-1 byte mux beside the 8-to-1 halfword mux.
  logic [7:0] read_byte;
  // 过程边界：always_comb begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_comb begin
    // 按 rd_byte_offset[0] 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
    case (rd_byte_offset[0])
      1'b0: read_byte = read_halfword[7:0];
      1'b1: read_byte = read_halfword[15:8];
      default: read_byte = 'x;
    endcase
  end
  // 过程边界：always_ff @(posedge clk) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) begin
    for (integer b=0;b<16;b=b+1)
      if (wr_mask[b]) memory[wr_addr][b*8+:8] <= wr_data[b*8+:8];
    if (rd_en)
      rd_data <= rd_int16 ? read_halfword : {{8{read_byte[7]}},read_byte};
  end
endmodule
