// 架构导读：npu_free_slot_allocator。
// 可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。
module npu_free_slot_allocator #(
  // 静态配置：parameter int SLOT_COUNT = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int SLOT_COUNT = 4
) (
  // 接口声明：input logic clk。
  // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
  input  logic clk,
  // 接口声明：input logic rst。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  input  logic rst,
  // 接口声明：input logic allocate_take。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic allocate_take,
  // 接口声明：output logic allocate_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  output logic allocate_valid,
  // 接口声明：output logic [((SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1)-1:0]。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic [((SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1)-1:0]
               allocate_slot,
  // 接口声明：input logic release_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input  logic release_valid,
  // 接口声明：input logic [((SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1)-1:0]。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic [((SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1)-1:0]
               release_slot,
  // 接口声明：output logic [((SLOT_COUNT >= 1) ? $clog2(SLOT_COUNT + 1) : 1)-1:0]。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic [((SLOT_COUNT >= 1) ? $clog2(SLOT_COUNT + 1) : 1)-1:0]
               free_count,
  // 接口声明：output logic protocol_error。
  // 记录异常状态；查看置位与清除分支可确定其保持范围。
  output logic protocol_error
);
  // 静态配置：localparam int SLOT_W = (SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int SLOT_W = (SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1;
  // 静态配置：localparam int COUNT_W = (SLOT_COUNT >= 1) ? $clog2(SLOT_COUNT + 1) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int COUNT_W = (SLOT_COUNT >= 1) ? $clog2(SLOT_COUNT + 1) : 1;
  // 静态配置：localparam int TREE_LEVELS = (SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 0。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int TREE_LEVELS = (SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 0;
  // 静态配置：localparam int TREE_LEAVES = 1 << TREE_LEVELS。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int TREE_LEAVES = 1 << TREE_LEVELS;
  // 静态配置：localparam logic [SLOT_W:0] SLOT_COUNT_EXT = (SLOT_W + 1)'(SLOT_COUNT)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [SLOT_W:0] SLOT_COUNT_EXT = (SLOT_W + 1)'(SLOT_COUNT);

  logic [SLOT_COUNT-1:0] free_bitmap_q;
  logic [TREE_LEAVES-1:0] tree_valid [0:TREE_LEVELS]
    /* verilator split_var */;
  logic [SLOT_W-1:0] tree_slot [0:TREE_LEVELS][0:TREE_LEAVES-1]
    /* verilator split_var */;
  logic allocate_fire;
  logic release_accept;
  logic release_error;
  logic [COUNT_W-1:0] free_count_q;

  generate
    for (genvar leaf = 0; leaf < TREE_LEAVES; leaf++) begin : g_tree_leaf
      // 条件分支：检查 leaf < SLOT_COUNT。
      if (leaf < SLOT_COUNT) begin : g_physical_slot
        assign tree_valid[0][leaf] = free_bitmap_q[leaf];
      end else begin : g_padded_slot
        assign tree_valid[0][leaf] = 1'b0;
      end
      assign tree_slot[0][leaf] = SLOT_W'(leaf);
    end

    for (genvar level = 1; level <= TREE_LEVELS; level++) begin : g_tree_level
      for (genvar node = 0; node < TREE_LEAVES; node++) begin : g_tree_node
        // 条件分支：检查 node < (TREE_LEAVES >> level)。
        if (node < (TREE_LEAVES >> level)) begin : g_parent
          assign tree_valid[level][node] =
            tree_valid[level-1][2*node] | tree_valid[level-1][2*node+1];
          assign tree_slot[level][node] = tree_valid[level-1][2*node]
            ? tree_slot[level-1][2*node]
            : tree_slot[level-1][2*node+1];
        end else begin : g_unused
          assign tree_valid[level][node] = 1'b0;
          assign tree_slot[level][node] = '0;
        end
      end
    end
  endgenerate

  assign allocate_valid = (rst === 1'b0) && tree_valid[TREE_LEVELS][0];
  assign allocate_slot = tree_slot[TREE_LEVELS][0];
  assign allocate_fire = (allocate_take === 1'b1) && allocate_valid;
  assign free_count = free_count_q;

  // 过程边界：always_comb begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_comb begin
    release_accept = 1'b0;
    release_error = 1'b0;
    // 条件分支：检查 release_valid === 1'b1。
    if (release_valid === 1'b1) begin
      // 条件分支：检查 (^release_slot) === 1'bx。
      if ((^release_slot) === 1'bx) begin
        release_error = 1'b1;
      end else if ({1'b0, release_slot} >= SLOT_COUNT_EXT) begin
        release_error = 1'b1;
      end else if (free_bitmap_q[release_slot] !== 1'b0) begin
        release_error = 1'b1;
      end else begin
        release_accept = 1'b1;
      end
    end
  end

  // 过程边界：always_ff @(posedge clk) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) begin
    // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
    if (rst) begin
      free_bitmap_q <= {SLOT_COUNT{1'b1}};
      free_count_q <= COUNT_W'(SLOT_COUNT);
      protocol_error <= 1'b0;
    end else begin
      if (allocate_fire)
        free_bitmap_q[allocate_slot] <= 1'b0;
      if (release_accept)
        free_bitmap_q[release_slot] <= 1'b1;

      // 按 {allocate_fire, release_accept} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
      case ({allocate_fire, release_accept})
        2'b10: free_count_q <= free_count_q - COUNT_W'(1);
        2'b01: free_count_q <= free_count_q + COUNT_W'(1);
        2'b11: free_count_q <= free_count_q;
        default: free_count_q <= free_count_q;
      endcase
      protocol_error <= release_error;
    end
  end

  generate
    if (SLOT_COUNT < 1) begin : g_bad_slot_count
      initial $fatal(1, "npu_free_slot_allocator: SLOT_COUNT must be at least 1");
    end
  endgenerate
endmodule
