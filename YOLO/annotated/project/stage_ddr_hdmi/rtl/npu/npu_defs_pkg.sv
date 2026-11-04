// 架构导读：npu_defs_pkg。
// 可综合数据/控制组件；接口含义和更新条件以下面的局部注释及原始表达式为准。
package npu_defs_pkg;
  typedef enum logic [7:0] {
    ERR_NONE=8'd0, ERR_INVALID_DIM=8'd1, ERR_BAD_PRECISION=8'd2,
    ERR_MISALIGNED=8'd3, ERR_BAD_STRIDE=8'd4, ERR_ADDRESS_RANGE=8'd5,
    ERR_DMA_RESPONSE=8'd6, ERR_DMA_TIMEOUT=8'd7, ERR_CMDQ_OVERFLOW=8'd8,
    ERR_MMIO_PROTOCOL=8'd9, ERR_RESET_BUSY=8'd10,
    ERR_INTERNAL_PROTOCOL=8'd11, ERR_ADDRESS_ALIAS=8'd12
  } npu_error_e;
  typedef enum logic [1:0] {DMA_LOAD_A, DMA_LOAD_B, DMA_STORE_C} npu_dma_kind_e;
  typedef struct packed {
    // 局部字段 logic [31:0] a_base, b_base, c_base。
    // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
    logic [31:0] a_base, b_base, c_base;
    // 局部字段 logic [15:0] m, n, k。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    logic [15:0] m, n, k;
    // 局部字段 logic input_int16。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    logic input_int16;
    // 局部字段 logic [31:0] a_stride, b_stride, c_stride。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    logic [31:0] a_stride, b_stride, c_stride;
    // 局部字段 logic [1:0] output_fmt, activation。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    logic [1:0] output_fmt, activation;
    // 局部字段 logic rounding。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    logic rounding;
    // 局部字段 logic [5:0] shift。
    logic [5:0] shift;
    logic signed [31:0] clamp_min, clamp_max;
    logic [31:0] user_tag;
  } npu_cmd_t;
  typedef struct packed {
    logic [31:0] user_tag;
    npu_error_e error;
    logic partial_output;
    logic [31:0] cycles;
    logic [63:0] macs;
  } npu_completion_t;
  typedef struct packed {
    npu_dma_kind_e kind;
    logic [31:0] base, row_stride;
    logic [15:0] rows, cols;
    logic [1:0] elem_bytes;
    logic bank;
  } npu_dma_job_t;
endpackage
