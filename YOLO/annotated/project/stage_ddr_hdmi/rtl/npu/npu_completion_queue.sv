// 架构导读：npu_completion_queue。
// 保存 NPU 完成记录，使完成事件在接收端暂停时仍可读取。
function automatic integer npu_completion_count_width(input integer depth);
  begin
    if (depth < 2)
      npu_completion_count_width = 1;
    else
      npu_completion_count_width = $clog2(depth + 1);
  end
endfunction

module npu_completion_queue #(parameter int DEPTH=4) (
  // 接口声明：input logic clk, rst。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  input logic clk, rst,
  // 接口声明：input logic reserve_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input logic reserve_valid,
  // 接口声明：output logic reserve_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic reserve_ready,
  // 接口声明：input logic release_reservation。
  // 跟踪存储/事务所有权，释放条件由对应完成分支决定。
  input logic release_reservation,
  // 接口声明：input logic enqueue_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input logic enqueue_valid,
  // 接口声明：output logic enqueue_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic enqueue_ready,
  // 接口声明：input npu_defs_pkg::npu_completion_t enqueue_data。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  input npu_defs_pkg::npu_completion_t enqueue_data,
  // 接口声明：output logic head_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  output logic head_valid,
  // 接口声明：output npu_defs_pkg::npu_completion_t head_data。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  output npu_defs_pkg::npu_completion_t head_data,
  // 接口声明：input logic pop。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input logic pop,
  // 接口声明：output logic [npu_completion_count_width(DEPTH)-1:0] level。
  output logic [npu_completion_count_width(DEPTH)-1:0] level,
  output logic [npu_completion_count_width(DEPTH)-1:0] reserved
);
  // 静态配置：localparam int COUNT_W = npu_completion_count_width(DEPTH)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int COUNT_W = npu_completion_count_width(DEPTH);
  // 静态配置：localparam logic [COUNT_W-1:0] DEPTH_COUNT = COUNT_W'(DEPTH)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [COUNT_W-1:0] DEPTH_COUNT = COUNT_W'(DEPTH);
  // 静态配置：localparam logic [COUNT_W:0] DEPTH_CAPACITY = (COUNT_W+1)'(DEPTH)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [COUNT_W:0] DEPTH_CAPACITY = (COUNT_W+1)'(DEPTH);

  generate
    if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0) begin : g_invalid_depth
      initial $fatal(1, "npu_completion_queue: DEPTH must be a power of two and at least 2");

      assign reserve_ready = 1'b0;
      assign enqueue_ready = 1'b0;
      assign head_valid = 1'b0;
      assign head_data = '0;
      assign level = '0;
      assign reserved = '0;
    end else begin : g_valid_depth
      // 静态配置：localparam int PTR_W = $clog2(DEPTH)。
      // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
      localparam int PTR_W = $clog2(DEPTH);

      npu_defs_pkg::npu_completion_t mem [0:DEPTH-1];
      logic [PTR_W-1:0] rd_ptr, wr_ptr;
      logic reserve_fire, enqueue_fire, release_fire, pop_fire;
      logic [COUNT_W:0] capacity_used;

      assign capacity_used = {1'b0, level} + {1'b0, reserved};
      assign head_valid = (level != '0);
      assign head_data = mem[rd_ptr];
      assign pop_fire = head_valid && pop;
      assign reserve_ready = capacity_used < DEPTH_CAPACITY;
      assign reserve_fire = reserve_valid && reserve_ready;
      assign enqueue_ready = (reserved != '0) && ((level != DEPTH_COUNT) || pop_fire);
      assign enqueue_fire = enqueue_valid && enqueue_ready;
      assign release_fire = release_reservation && (reserved != '0) && !enqueue_fire;

`ifndef SYNTHESIS
      // 过程边界：always @(posedge clk) begin。
      // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
      always @(posedge clk) begin
        // 复位相关判断：!rst；分支方向由信号极性与取反表达式决定。
        if (!rst) begin
          assert (!(enqueue_valid && release_reservation))
            else $error("npu_completion_queue: enqueue and release cannot occur together");
          assert (!(enqueue_fire && (reserved == '0)))
            else $fatal(1, "npu_completion_queue: enqueue consumed no reservation");
          assert (!(release_fire && (reserved == '0)))
            else $fatal(1, "npu_completion_queue: release consumed no reservation");
          assert (capacity_used <= DEPTH_CAPACITY)
            else $fatal(1, "npu_completion_queue: capacity invariant violated");
        end
      end
`endif

      // 过程边界：always_ff @(posedge clk) begin。
      // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
      always_ff @(posedge clk) begin
        // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
        if (rst) begin
          rd_ptr <= '0;
          wr_ptr <= '0;
          level <= '0;
          reserved <= '0;
        end else begin
          if (enqueue_fire) begin
            mem[wr_ptr] <= enqueue_data;
            wr_ptr <= wr_ptr + 1'b1;
          end
          if (pop_fire)
            rd_ptr <= rd_ptr + 1'b1;

          // 按 {enqueue_fire, pop_fire} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
          case ({enqueue_fire, pop_fire})
            2'b10: level <= level + 1'b1;
            2'b01: level <= level - 1'b1;
            default: level <= level;
          endcase
          // 按 {reserve_fire, (enqueue_fire || release_fire)} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
          case ({reserve_fire, (enqueue_fire || release_fire)})
            2'b10: reserved <= reserved + 1'b1;
            2'b01: reserved <= reserved - 1'b1;
            default: reserved <= reserved;
          endcase
        end
      end
    end
  endgenerate
endmodule
