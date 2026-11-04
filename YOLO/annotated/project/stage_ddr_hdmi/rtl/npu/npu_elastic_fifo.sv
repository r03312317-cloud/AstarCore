// 架构导读：npu_elastic_fifo。
// FIFO 缓冲模块，隔离生产者与消费者，满/空条件由指针和容量关系决定。
module npu_elastic_fifo #(
  // 静态配置：parameter int WIDTH = 8。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int WIDTH = 8,
  // 静态配置：parameter int DEPTH = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int DEPTH = 4,
  // 静态配置：parameter int COUNT_W = (DEPTH >= 1) ? $clog2(DEPTH + 1) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int COUNT_W = (DEPTH >= 1) ? $clog2(DEPTH + 1) : 1
) (
  // 接口声明：input logic clk。
  // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
  input  logic               clk,
  // 接口声明：input logic rst。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  input  logic               rst,
  // 接口声明：input logic in_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input  logic               in_valid,
  // 接口声明：output logic in_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic               in_ready,
  // 接口声明：input logic [WIDTH-1:0] in_data。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  input  logic [WIDTH-1:0]   in_data,
  // 接口声明：output logic out_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  output logic               out_valid,
  // 接口声明：input logic out_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  input  logic               out_ready,
  // 接口声明：output logic [WIDTH-1:0] out_data。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  output logic [WIDTH-1:0]   out_data,
  // 接口声明：output logic [COUNT_W-1:0] occupancy。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic [COUNT_W-1:0] occupancy
);
  // 静态配置：localparam int BACKING_DEPTH = (DEPTH > 1) ? DEPTH - 1 : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int BACKING_DEPTH = (DEPTH > 1) ? DEPTH - 1 : 1;
  // 静态配置：localparam int PTR_W = (DEPTH > 2) ? $clog2(DEPTH - 1) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int PTR_W = (DEPTH > 2) ? $clog2(DEPTH - 1) : 1;

  logic [WIDTH-1:0] backing [0:BACKING_DEPTH-1];
  logic [PTR_W-1:0] head_q, tail_q;
  logic [WIDTH-1:0] out_data_q;
  logic out_valid_q;
  logic [COUNT_W-1:0] occupancy_q;
  logic push, pop;

  // 局部运算/辅助过程：function automatic logic [PTR_W-1:0] next_backing_ptr(。
  // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
  function automatic logic [PTR_W-1:0] next_backing_ptr(
    // 接口声明：input logic [PTR_W-1:0] ptr。
    // 选择队列、数组或数据片段的位置，更新条件见对应赋值。
    input logic [PTR_W-1:0] ptr
  );
    // 条件分支：检查 DEPTH <= 2。
    if (DEPTH <= 2)
      next_backing_ptr = '0;
    else if (ptr == PTR_W'(DEPTH - 2))
      next_backing_ptr = '0;
    else
      next_backing_ptr = ptr + PTR_W'(1);
  endfunction

  assign in_ready = !rst && (occupancy_q < COUNT_W'(DEPTH));
  assign out_valid = out_valid_q;
  assign out_data = out_data_q;
  assign occupancy = occupancy_q;
  assign push = (in_valid === 1'b1) && in_ready;
  assign pop = out_valid_q && (out_ready === 1'b1);

  // 过程边界：always_ff @(posedge clk) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) begin
    // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
    if (rst) begin
      head_q <= '0;
      tail_q <= '0;
      out_data_q <= '0;
      out_valid_q <= 1'b0;
      occupancy_q <= '0;
    end else begin
      // 按 {push, pop} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
      case ({push, pop})
        2'b10: begin
          if (!out_valid_q) begin
            out_data_q <= in_data;
            out_valid_q <= 1'b1;
          end else begin
            backing[tail_q] <= in_data;
            tail_q <= next_backing_ptr(tail_q);
          end
          occupancy_q <= occupancy_q + COUNT_W'(1);
        end
        2'b01: begin
          if (occupancy_q > COUNT_W'(1)) begin
            out_data_q <= backing[head_q];
            head_q <= next_backing_ptr(head_q);
            occupancy_q <= occupancy_q - COUNT_W'(1);
          end else begin
            out_valid_q <= 1'b0;
            occupancy_q <= '0;
          end
        end
        2'b11: begin
          if (occupancy_q == COUNT_W'(1)) begin
            out_data_q <= in_data;
          end else begin
            out_data_q <= backing[head_q];
            head_q <= next_backing_ptr(head_q);
            backing[tail_q] <= in_data;
            tail_q <= next_backing_ptr(tail_q);
          end
        end
        default: begin end
      endcase
    end
  end

  generate
    if (WIDTH < 1) begin : g_bad_width
      initial $fatal(1, "npu_elastic_fifo: WIDTH must be at least 1");
    end
    if (DEPTH < 1) begin : g_bad_depth
      initial $fatal(1, "npu_elastic_fifo: DEPTH must be at least 1");
    end
  endgenerate
endmodule
