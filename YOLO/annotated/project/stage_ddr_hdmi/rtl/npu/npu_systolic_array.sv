// 架构导读：npu_systolic_array。
// 参数化脉动阵列，逐行列传播带有效位的操作数并提供累加结果读取。
module npu_systolic_array #(
  // 静态配置：parameter int ARRAY_ROWS=4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int ARRAY_ROWS=4,
  // 静态配置：parameter int ARRAY_COLS=4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int ARRAY_COLS=4,
  // 静态配置：parameter int ACC_W=48。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int ACC_W=48,
  // 静态配置：parameter int MUL_PIPE_STAGES=1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MUL_PIPE_STAGES=1
) (
  // 接口声明：input logic clk。
  // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
  input  logic                            clk,
  // 接口声明：input logic rst。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  input  logic                            rst,
  // 接口声明：input logic start_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input  logic                            start_valid,
  // 接口声明：output logic start_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic                            start_ready,
  // 接口声明：input logic [15:0] k_len。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic [15:0]                     k_len,
  // 接口声明：input logic [ARRAY_ROWS-1:0] row_mask。
  // 逐位选择参与本次操作的数据通道或状态位。
  input  logic [ARRAY_ROWS-1:0]           row_mask,
  // 接口声明：input logic [ARRAY_COLS-1:0] col_mask。
  // 逐位选择参与本次操作的数据通道或状态位。
  input  logic [ARRAY_COLS-1:0]           col_mask,
  // 接口声明：input logic continue_acc。
  // 保存或选择累加结果，符号与精度由声明及算术表达式决定。
  input  logic                            continue_acc,
  // 接口声明：input logic input_int16。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic                            input_int16,
  // 接口声明：input logic feed_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input  logic                            feed_valid,
  // 接口声明：output logic feed_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic                            feed_ready,
  // 接口声明：input logic signed [ARRAY_ROWS*16-1:0] feed_a。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic signed [ARRAY_ROWS*16-1:0] feed_a,
  // 接口声明：input logic signed [ARRAY_COLS*16-1:0] feed_b。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic signed [ARRAY_COLS*16-1:0] feed_b,
  // 接口声明：output logic tile_done。
  // 表达本地完成/结束条件，系统退休还需满足上层接口契约。
  output logic                            tile_done,
  // 接口声明：input logic [((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1)-1:0] acc_read_row。
  // 保存或选择累加结果，符号与精度由声明及算术表达式决定。
  input  logic [((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1)-1:0] acc_read_row,
  // 接口声明：input logic [((ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1)-1:0] acc_read_col。
  // 保存或选择累加结果，符号与精度由声明及算术表达式决定。
  input  logic [((ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1)-1:0] acc_read_col,
  // 接口声明：output logic signed [ACC_W-1:0] acc_rdata。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  output logic signed [ACC_W-1:0]         acc_rdata,
  // 接口声明：input logic acc_row_read_enable。
  // 保存或选择累加结果，符号与精度由声明及算术表达式决定。
  input logic acc_row_read_enable,
  // 接口声明：output logic signed [ARRAY_COLS*ACC_W-1:0] acc_row_vector。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  output logic signed [ARRAY_COLS*ACC_W-1:0] acc_row_vector
);
  // 静态配置：localparam int ROW_IDX_W = (ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int ROW_IDX_W = (ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1;
  // 静态配置：localparam int COL_IDX_W = (ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int COL_IDX_W = (ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1;
  // 静态配置：localparam int DRAIN_CYCLES = ARRAY_ROWS + ARRAY_COLS - 2 + MUL_PIPE_STAGES。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int DRAIN_CYCLES = ARRAY_ROWS + ARRAY_COLS - 2 + MUL_PIPE_STAGES;
  // 静态配置：localparam int DRAIN_W = $clog2(DRAIN_CYCLES + 1)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int DRAIN_W = $clog2(DRAIN_CYCLES + 1);
  // 静态配置：localparam logic [ROW_IDX_W:0] ARRAY_ROWS_COUNT = (ROW_IDX_W+1)'(ARRAY_ROWS)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [ROW_IDX_W:0] ARRAY_ROWS_COUNT = (ROW_IDX_W+1)'(ARRAY_ROWS);
  // 静态配置：localparam logic [COL_IDX_W:0] ARRAY_COLS_COUNT = (COL_IDX_W+1)'(ARRAY_COLS)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [COL_IDX_W:0] ARRAY_COLS_COUNT = (COL_IDX_W+1)'(ARRAY_COLS);
  // 静态配置：localparam logic [DRAIN_W-1:0] DRAIN_COUNT_INIT = DRAIN_W'(DRAIN_CYCLES)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [DRAIN_W-1:0] DRAIN_COUNT_INIT = DRAIN_W'(DRAIN_CYCLES);

  initial begin
    // 条件分支：检查 ARRAY_ROWS < 2 || ARRAY_ROWS > 16 ||。
    if (ARRAY_ROWS < 2 || ARRAY_ROWS > 16 ||
        (ARRAY_ROWS & (ARRAY_ROWS - 1)) != 0)
      $fatal(1, "npu_systolic_array: ARRAY_ROWS must be a power of two from 2 to 16");
    // 条件分支：检查 ARRAY_COLS < 2 || ARRAY_COLS > 16 ||。
    if (ARRAY_COLS < 2 || ARRAY_COLS > 16 ||
        (ARRAY_COLS & (ARRAY_COLS - 1)) != 0)
      $fatal(1, "npu_systolic_array: ARRAY_COLS must be a power of two from 2 to 16");
    // 条件分支：检查 ACC_W < 48。
    if (ACC_W < 48)
      $fatal(1, "npu_systolic_array: ACC_W must be at least 48");
    // 条件分支：检查 MUL_PIPE_STAGES != 1 && MUL_PIPE_STAGES != 2。
    if (MUL_PIPE_STAGES != 1 && MUL_PIPE_STAGES != 2)
      $fatal(1, "npu_systolic_array: MUL_PIPE_STAGES must be 1 or 2");
  end

  logic active_q, draining_q;
  logic [15:0] k_len_q, feed_count_q;
  logic [DRAIN_W-1:0] drain_count_q;
  logic [ARRAY_ROWS-1:0] row_mask_q;
  logic [ARRAY_COLS-1:0] col_mask_q;
  logic mode_q, clear_pulse;
  logic feed_fire;
  // TC3: normalize once per input lane instead of broadcasting mode through
  // every PE multiplier. The PE module remains unchanged. Invalid-cycle data
  // is deliberately don't-care; independent valid bits still gate all MACs.
  logic signed [ARRAY_ROWS*16-1:0] feed_a_normalized;
  logic signed [ARRAY_COLS*16-1:0] feed_b_normalized;
  for (genvar n = 0; n < ARRAY_ROWS; n++) begin : g_normalize_a
    assign feed_a_normalized[n*16 +: 16] = mode_q ? feed_a[n*16 +: 16] :
                                          {{8{feed_a[n*16+7]}},feed_a[n*16 +: 8]};
  end
  for (genvar n = 0; n < ARRAY_COLS; n++) begin : g_normalize_b
    assign feed_b_normalized[n*16 +: 16] = mode_q ? feed_b[n*16 +: 16] :
                                          {{8{feed_b[n*16+7]}},feed_b[n*16 +: 8]};
  end
  logic signed [15:0] a_skew_data [0:ARRAY_ROWS-1][0:ARRAY_ROWS-1];
  logic signed [15:0] b_skew_data [0:ARRAY_COLS-1][0:ARRAY_COLS-1];
  logic a_skew_valid [0:ARRAY_ROWS-1][0:ARRAY_ROWS-1];
  logic b_skew_valid [0:ARRAY_COLS-1][0:ARRAY_COLS-1];
  logic signed [15:0] a_mesh [0:ARRAY_ROWS-1][0:ARRAY_COLS];
  logic signed [15:0] b_mesh [0:ARRAY_ROWS][0:ARRAY_COLS-1];
  logic a_valid_mesh [0:ARRAY_ROWS-1][0:ARRAY_COLS];
  logic b_valid_mesh [0:ARRAY_ROWS][0:ARRAY_COLS-1];
  logic signed [ACC_W-1:0] acc [0:ARRAY_ROWS-1][0:ARRAY_COLS-1];
  // Select the row ONCE for both existing one-clock response registers.
  // Separate acc[row][col] and acc[row][fixed_col] expressions caused PDS
  // to duplicate the full row selector. No PE, arithmetic, enable or read
  // latency changes: the scalar port selects its column from this same bus.
  wire [ARRAY_COLS*ACC_W-1:0] selected_acc_row;
  for(genvar c=0;c<ARRAY_COLS;c++)begin:g_shared_result_row
    assign selected_acc_row[c*ACC_W+:ACC_W]=
      ({1'b0,acc_read_row}<ARRAY_ROWS_COUNT)?acc[acc_read_row][c]:'0;
  end

  assign start_ready = !active_q;
  assign feed_ready = active_q && !draining_q && (feed_count_q < k_len_q);
  assign feed_fire = feed_valid && feed_ready;

  // Packed feed vectors use lane zero at bits [15:0]; higher lanes ascend.
  for (genvar r = 0; r < ARRAY_ROWS; r = r + 1) begin: g_a_boundary
    // 条件分支：检查 r == 0。
    if (r == 0) begin : g_direct
      assign a_mesh[r][0] = feed_a_normalized[r*16 +: 16];
      assign a_valid_mesh[r][0] = feed_fire;
    end else begin : g_skewed
      assign a_mesh[r][0] = a_skew_data[r][r-1];
      assign a_valid_mesh[r][0] = a_skew_valid[r][r-1];
    end
  end
  for (genvar c = 0; c < ARRAY_COLS; c = c + 1) begin: g_b_boundary
    // 条件分支：检查 c == 0。
    if (c == 0) begin : g_direct
      assign b_mesh[0][c] = feed_b_normalized[c*16 +: 16];
      assign b_valid_mesh[0][c] = feed_fire;
    end else begin : g_skewed
      assign b_mesh[0][c] = b_skew_data[c][c-1];
      assign b_valid_mesh[0][c] = b_skew_valid[c][c-1];
    end
  end
  for (genvar r = 0; r < ARRAY_ROWS; r = r + 1) begin: g_pe_rows
    for (genvar c = 0; c < ARRAY_COLS; c = c + 1) begin: g_pe_cols
      npu_mac_pe #(.ACC_W(ACC_W), .MUL_PIPE_STAGES(MUL_PIPE_STAGES)) pe (
        .clk, .rst, .clear_acc(clear_pulse), .input_int16(1'b1),
        .a_valid_in(a_valid_mesh[r][c] && row_mask_q[r]),
        .b_valid_in(b_valid_mesh[r][c] && col_mask_q[c]),
        .a_in(a_mesh[r][c]), .b_in(b_mesh[r][c]),
        .a_valid_out(a_valid_mesh[r][c+1]),
        .b_valid_out(b_valid_mesh[r+1][c]),
        .a_out(a_mesh[r][c+1]), .b_out(b_mesh[r+1][c]),
        .acc_value(acc[r][c])
      );
    end
  end

  // Payload shifts have no reset. The independently reset valid chains mask
  // every unused value, including interrupted tiles and post-reset refill.
  // No cycle, enable, arithmetic, or externally visible valid signal changes.
  always_ff @(posedge clk) begin
    for (int r = 0; r < ARRAY_ROWS; r++) begin
      a_skew_data[r][0] <= feed_a_normalized[r*16 +: 16];
      for (int d = 1; d < ARRAY_ROWS; d++)
        a_skew_data[r][d] <= a_skew_data[r][d-1];
    end
    for (int c = 0; c < ARRAY_COLS; c++) begin
      b_skew_data[c][0] <= feed_b_normalized[c*16 +: 16];
      for (int d = 1; d < ARRAY_COLS; d++)
        b_skew_data[c][d] <= b_skew_data[c][d-1];
    end
  end

  // 过程边界：always_ff @(posedge clk) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) begin
    // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
    if (rst) begin
      active_q <= 1'b0;
      draining_q <= 1'b0;
      k_len_q <= '0;
      feed_count_q <= '0;
      drain_count_q <= '0;
      tile_done <= 1'b0;
      acc_rdata <= '0;
      acc_row_vector <= '0;
      row_mask_q <= '0;
      col_mask_q <= '0;
      mode_q <= 1'b0;
      clear_pulse <= 1'b0;
      for (int r = 0; r < ARRAY_ROWS; r = r + 1)
        for (int d = 0; d < ARRAY_ROWS; d = d + 1) begin
          a_skew_valid[r][d] <= 1'b0;
        end
      for (int c = 0; c < ARRAY_COLS; c = c + 1)
        for (int d = 0; d < ARRAY_COLS; d = d + 1) begin
          b_skew_valid[c][d] <= 1'b0;
        end
    end else begin
      tile_done <= 1'b0;
      clear_pulse <= 1'b0;
      if(acc_row_read_enable)begin
        acc_row_vector<=selected_acc_row;
      end
      if (({1'b0, acc_read_row} < ARRAY_ROWS_COUNT) &&
          ({1'b0, acc_read_col} < ARRAY_COLS_COUNT))
        acc_rdata <= $signed(selected_acc_row[ACC_W*acc_read_col+:ACC_W]);
      else
        acc_rdata <= '0;
      for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
        a_skew_valid[r][0] <= feed_fire;
        for (int d = 1; d < ARRAY_ROWS; d = d + 1) begin
          a_skew_valid[r][d] <= a_skew_valid[r][d-1];
        end
      end
      for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
        b_skew_valid[c][0] <= feed_fire;
        for (int d = 1; d < ARRAY_COLS; d = d + 1) begin
          b_skew_valid[c][d] <= b_skew_valid[c][d-1];
        end
      end
      // 握手/背压判断：start_valid && start_ready。
      // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
      if (start_valid && start_ready) begin
        active_q <= 1'b1;
        draining_q <= 1'b0;
        k_len_q <= k_len;
        feed_count_q <= '0;
        row_mask_q <= row_mask;
        col_mask_q <= col_mask;
        mode_q <= input_int16;
        clear_pulse <= !continue_acc;
      end
      if (feed_fire) begin
        feed_count_q <= feed_count_q + 16'd1;
        if (feed_count_q + 16'd1 == k_len_q) begin
          draining_q <= 1'b1;
          drain_count_q <= DRAIN_COUNT_INIT;
        end
      end else if (draining_q) begin
        if (drain_count_q == 1) begin
          tile_done <= 1'b1;
          active_q <= 1'b0;
          draining_q <= 1'b0;
          drain_count_q <= '0;
        end else begin
          drain_count_q <= drain_count_q - 1'b1;
        end
      end
    end
  end
endmodule
