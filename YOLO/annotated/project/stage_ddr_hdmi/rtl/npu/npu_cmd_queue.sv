// 架构导读：npu_cmd_queue。
// 保存尚待执行的 NPU 命令，在命令接收和调度出队之间隔离背压。
module npu_cmd_queue #(parameter int DEPTH=4) (
  // 接口声明：input logic clk, rst。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  input logic clk, rst,
  // 接口声明：input logic push_valid, output logic push_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  input logic push_valid, output logic push_ready,
  // 接口声明：input npu_defs_pkg::npu_cmd_t push_data。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  input npu_defs_pkg::npu_cmd_t push_data,
  // 接口声明：output logic pop_valid, input logic pop_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic pop_valid, input logic pop_ready,
  output npu_defs_pkg::npu_cmd_t pop_data,
  output logic [$clog2(DEPTH+1)-1:0] level,
  output logic full, empty
);
  // 静态配置：localparam int PTR_W = (DEPTH >= 2) ? $clog2(DEPTH) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int PTR_W = (DEPTH >= 2) ? $clog2(DEPTH) : 1;
  // 静态配置：localparam int LEVEL_W = $clog2(DEPTH + 1)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int LEVEL_W = $clog2(DEPTH + 1);
  // 静态配置：localparam logic [LEVEL_W-1:0] DEPTH_COUNT = LEVEL_W'(DEPTH)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [LEVEL_W-1:0] DEPTH_COUNT = LEVEL_W'(DEPTH);

  generate
    if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0) begin : g_invalid_depth
      initial $fatal(1, "npu_cmd_queue: DEPTH must be a power of two and at least 2");
    end
  endgenerate

  npu_defs_pkg::npu_cmd_t mem [0:DEPTH-1];
  logic [PTR_W-1:0] rd_ptr, wr_ptr;
  logic push_fire, pop_fire;

  assign empty = (level == '0);
  assign full = (level == DEPTH_COUNT);
  assign pop_valid = !empty;
  assign pop_data = mem[rd_ptr];
  assign push_ready = !full || (pop_valid && pop_ready);
  assign push_fire = push_valid && push_ready;
  assign pop_fire = pop_valid && pop_ready;

  // 过程边界：always_ff @(posedge clk) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) begin
    // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
    if (rst) begin
      rd_ptr <= '0;
      wr_ptr <= '0;
      level <= '0;
    end else begin
      if (push_fire) begin
        mem[wr_ptr] <= push_data;
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (pop_fire)
        rd_ptr <= rd_ptr + 1'b1;
      // 按 {push_fire, pop_fire} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
      case ({push_fire, pop_fire})
        2'b10: level <= level + 1'b1;
        2'b01: level <= level - 1'b1;
        default: level <= level;
      endcase
    end
  end
endmodule
