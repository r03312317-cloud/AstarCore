// 架构导读：npu_accel_top。
// NPU 集成顶层，连接命令队列、DMA、scratchpad、调度器、脉动阵列和结果存储。
module npu_accel_top #(
  // 静态配置：parameter int ARRAY_ROWS = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int ARRAY_ROWS = 4,
  // Enable only behind a transport that guarantees per-master response order.
  parameter bit IN_ORDER_TRANSPORT = 1'b0,
  // 静态配置：parameter bit RESIDENT_A_PREFETCH = 1'b0。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter bit RESIDENT_A_PREFETCH = 1'b0,
  // 静态配置：parameter int RESIDENT_RESULT_CHUNK_COLUMNS = 256。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int RESIDENT_RESULT_CHUNK_COLUMNS = 256,
  // NPU-P1: full-K resident execution and bubble-free operand fill.
  // Set either parameter to zero for controlled A/B comparison.
  parameter bit RESIDENT_FULL_K_ENABLE = 1'b1,
  // 静态配置：parameter bit RESIDENT_GROUP_REUSE_ENABLE = 1'b1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter bit RESIDENT_GROUP_REUSE_ENABLE = 1'b1,
  // 静态配置：parameter bit RESIDENT_STORE_VECTOR4 = 1'b1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter bit RESIDENT_STORE_VECTOR4 = 1'b1,
  // 静态配置：parameter bit RESIDENT_PACK_PIPELINED = 1'b1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter bit RESIDENT_PACK_PIPELINED = 1'b1,
  // 静态配置：parameter int ARRAY_COLS = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int ARRAY_COLS = 4,
  // 静态配置：parameter int K_TILE = 32。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int K_TILE = 32,
  // 静态配置：parameter int SPAD_LOAD_ELEMS = 8。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int SPAD_LOAD_ELEMS = 8,
  // 静态配置：parameter bit A_PACKED_INT8_16 = 1'b0。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter bit A_PACKED_INT8_16 = 1'b0,
  // 静态配置：parameter int ACC_W = 48。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int ACC_W = 48,
  // 静态配置：parameter int MEM_ADDR_W = 32。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MEM_ADDR_W = 32,
  // 静态配置：parameter int MEM_DATA_W = 32。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MEM_DATA_W = 32,
  // 静态配置：parameter int MEM_ID_W = 2。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MEM_ID_W = 2,
  // 静态配置：parameter int MEM_OUTSTANDING = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MEM_OUTSTANDING = 4,
  // 静态配置：parameter int DMA_READ_PIPELINE = 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int DMA_READ_PIPELINE = 1,
  // 静态配置：parameter int DMA_RSP_DEPTH = 2。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int DMA_RSP_DEPTH = 2,
  // 静态配置：parameter int DMA_TIMEOUT_CYCLES = 4096。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int DMA_TIMEOUT_CYCLES = 4096,
  // 静态配置：parameter int CMDQ_DEPTH = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int CMDQ_DEPTH = 4,
  // 静态配置：parameter int COMPQ_DEPTH = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int COMPQ_DEPTH = 4,
  // 静态配置：parameter int MUL_PIPE_STAGES = 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MUL_PIPE_STAGES = 1,
  // 静态配置：parameter logic [31:0] DRAM_BASE = 32'h8010_0000。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter logic [31:0] DRAM_BASE = 32'h8010_0000,
  // 静态配置：parameter logic [32:0] DRAM_BYTES = 33'h00004_0000。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter logic [32:0] DRAM_BYTES = 33'h00004_0000
) (
  // 接口声明：input logic clk。
  // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
  input  logic clk,
  // 接口声明：input logic resident_enable。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input logic resident_enable,
  // 接口声明：input logic [31:0] resident_model_epoch,resident_frame_epoch,resident_task_generation,resident_a_generation...。
  // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
  input logic [31:0] resident_model_epoch,resident_frame_epoch,resident_task_generation,resident_a_generation,resident_b_base,
  // 接口声明：input logic [4:0] resident_next_a_rows。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input logic [4:0] resident_next_a_rows,
  // 接口声明：input logic [8:0] resident_b_columns,input logic [4:0] resident_b_group。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input logic [8:0] resident_b_columns,input logic [4:0] resident_b_group,

  // 接口声明：input logic rst。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  input  logic rst,
  // 接口声明：input logic [31:0] perip_addr。
  // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
  input  logic [31:0] perip_addr,
  // 接口声明：input logic [31:0] perip_wdata。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  input  logic [31:0] perip_wdata,
  // 接口声明：input logic perip_wen。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic perip_wen,
  // 接口声明：input logic [1:0] perip_mask。
  // 逐位选择参与本次操作的数据通道或状态位。
  input  logic [1:0] perip_mask,
  // 接口声明：input logic [31:0] legacy_perip_rdata。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  input  logic [31:0] legacy_perip_rdata,
  // 接口声明：output logic [31:0] combined_perip_rdata。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  output logic [31:0] combined_perip_rdata,
  // 接口声明：output logic irq。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic irq,
  // 接口声明：output logic exclusive_idle。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic exclusive_idle,
  // 接口声明：output logic dma_req_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  output logic dma_req_valid,
  // 接口声明：input logic dma_req_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  input  logic dma_req_ready,
  // 接口声明：output logic dma_req_write。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic dma_req_write,
  // 接口声明：output logic [MEM_ADDR_W-1:0] dma_req_addr。
  // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
  output logic [MEM_ADDR_W-1:0] dma_req_addr,
  // 接口声明：output logic [MEM_DATA_W-1:0] dma_req_wdata。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  output logic [MEM_DATA_W-1:0] dma_req_wdata,
  // 接口声明：output logic [MEM_DATA_W/8-1:0] dma_req_wstrb。
  // 按字节选择本次写入生效的 lane。
  output logic [MEM_DATA_W/8-1:0] dma_req_wstrb,
  // 接口声明：output logic [MEM_ID_W-1:0] dma_req_id。
  // 把返回信息关联到对应的已接受请求。
  output logic [MEM_ID_W-1:0] dma_req_id,
  // 接口声明：input logic dma_rsp_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input  logic dma_rsp_valid,
  // 接口声明：output logic dma_rsp_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic dma_rsp_ready,
  // 接口声明：input logic dma_rsp_write。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic dma_rsp_write,
  // 接口声明：input logic [MEM_ID_W-1:0] dma_rsp_id。
  // 把返回信息关联到对应的已接受请求。
  input  logic [MEM_ID_W-1:0] dma_rsp_id,
  // 接口声明：input logic [MEM_DATA_W-1:0] dma_rsp_rdata。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  input  logic [MEM_DATA_W-1:0] dma_rsp_rdata,
  // 接口声明：input logic dma_rsp_error。
  // 记录异常状态；查看置位与清除分支可确定其保持范围。
  input  logic dma_rsp_error
);
 // Regional synchronous reset distribution; identity LUTs add no clock cycle.
 // Targeted preservation applies only to these drivers, not to their loads.
 (* syn_keep=1 *) wire region_reset_u_order;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_order(.I0(core_rst),.Z(region_reset_u_order));
 (* syn_keep=1 *) wire region_reset_u_resident;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_resident(.I0(core_rst),.Z(region_reset_u_resident));
 (* syn_keep=1 *) wire region_reset_u_mmio;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_mmio(.I0(core_rst),.Z(region_reset_u_mmio));
 (* syn_keep=1 *) wire region_reset_u_cmdq;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_cmdq(.I0(core_rst),.Z(region_reset_u_cmdq));
 (* syn_keep=1 *) wire region_reset_u_compq;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_compq(.I0(core_rst),.Z(region_reset_u_compq));
 (* syn_keep=1 *) wire region_reset_u_scheduler;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_scheduler(.I0(core_rst),.Z(region_reset_u_scheduler));
 (* syn_keep=1 *) wire region_reset_u_dma;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_dma(.I0(core_rst),.Z(region_reset_u_dma));
 (* syn_keep=1 *) wire region_reset_u_spad;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_spad(.I0(core_rst),.Z(region_reset_u_spad));
 (* syn_keep=1 *) wire region_reset_u_array;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_array(.I0(core_rst),.Z(region_reset_u_array));
 (* syn_keep=1 *) wire region_reset_u_postprocess;
 (* syn_noprune=1, PAP_DONT_TOUCH="TRUE" *) GTP_LUT1 #(.INIT(2'b10))
 reset_driver_u_postprocess(.I0(core_rst),.Z(region_reset_u_postprocess));

  // 静态配置：localparam int CMD_COUNT_W = (CMDQ_DEPTH < 2) ? 1 : $clog2(CMDQ_DEPTH + 1)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int CMD_COUNT_W = (CMDQ_DEPTH < 2) ? 1 : $clog2(CMDQ_DEPTH + 1);
  // 静态配置：localparam int COMP_COUNT_W = (COMPQ_DEPTH < 2) ? 1 : $clog2(COMPQ_DEPTH + 1)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int COMP_COUNT_W = (COMPQ_DEPTH < 2) ? 1 : $clog2(COMPQ_DEPTH + 1);
  // 静态配置：localparam int SPAD_LANE_W = ((ARRAY_ROWS > ARRAY_COLS) ?。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int SPAD_LANE_W = ((ARRAY_ROWS > ARRAY_COLS) ?
    ((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1) :
    ((ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1));
  // 静态配置：localparam int K_INDEX_W = (K_TILE > 1) ? $clog2(K_TILE) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int K_INDEX_W = (K_TILE > 1) ? $clog2(K_TILE) : 1;
  // 静态配置：localparam int ROW_INDEX_W = (ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int ROW_INDEX_W = (ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1;
  // 静态配置：localparam int COL_INDEX_W = (ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int COL_INDEX_W = (ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1;
  // 静态配置：localparam int OUTSTANDING_W = (MEM_OUTSTANDING > 0) ?。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int OUTSTANDING_W = (MEM_OUTSTANDING > 0) ?
    $clog2(MEM_OUTSTANDING + 1) : 1;
  // 静态配置：localparam int SAFE_MEM_ID_W = ((MEM_ID_W >= 1) && (MEM_ID_W <= 30)) ?。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int SAFE_MEM_ID_W = ((MEM_ID_W >= 1) && (MEM_ID_W <= 30)) ?
    // 状态/选择分支 MEM_ID_W ：本分支规定该编码下的寄存器更新和下一步动作。
    MEM_ID_W : 1;
  // 静态配置：localparam logic [63:0] DMA_ID_CAPACITY = 64'd1 << SAFE_MEM_ID_W。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [63:0] DMA_ID_CAPACITY = 64'd1 << SAFE_MEM_ID_W;
  // 静态配置：localparam logic [63:0] MEM_OUTSTANDING_U64 =。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [63:0] MEM_OUTSTANDING_U64 =
    (MEM_OUTSTANDING > 0) ? 64'(MEM_OUTSTANDING) : 64'd0;
  // 静态配置：localparam logic [64:0] DRAM_LIMIT =。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [64:0] DRAM_LIMIT =
    {33'd0, DRAM_BASE} + {32'd0, DRAM_BYTES};

  // 局部字段 logic core_rst。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  logic core_rst;
  // 局部字段 logic soft_reset_req, soft_reset_accept, soft_reset_accept_q, soft_reset_fire。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  logic soft_reset_req, soft_reset_accept, soft_reset_accept_q, soft_reset_fire;

  // 局部字段 logic cmd_push_valid, cmd_push_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  logic cmd_push_valid, cmd_push_ready;
  npu_defs_pkg::npu_cmd_t cmd_push_data;
  // 局部字段 logic cmd_pop_valid, cmd_pop_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  logic cmd_pop_valid, cmd_pop_ready;
  npu_defs_pkg::npu_cmd_t cmd_pop_data;
  // 局部字段 logic [CMD_COUNT_W-1:0] cmd_level。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  logic [CMD_COUNT_W-1:0] cmd_level;
  // 局部字段 logic cmd_full, cmd_empty。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  logic cmd_full, cmd_empty;

  // 局部字段 logic completion_reserve_valid, completion_reserve_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  logic completion_reserve_valid, completion_reserve_ready;
  // 局部字段 logic completion_release_reservation。
  // 跟踪存储/事务所有权，释放条件由对应完成分支决定。
  logic completion_release_reservation;
  // 局部字段 logic completion_enqueue_valid, completion_enqueue_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  logic completion_enqueue_valid, completion_enqueue_ready;
  npu_defs_pkg::npu_completion_t completion_enqueue_data;
  logic completion_head_valid, completion_pop;
  npu_defs_pkg::npu_completion_t completion_head_data;
  logic [COMP_COUNT_W-1:0] completion_level, unused_completion_reserved;
  logic completion_empty, completion_full, completion_enqueued;

  logic scheduler_active;
  logic error_event_valid;
  npu_defs_pkg::npu_error_e error_event_code;
  logic [1:0] unused_irq_status;
  logic [11:0] unused_error_status;
  logic [31:0] unused_error_tag, unused_reject_count;
  wire _unused_leaf_observability = &{1'b0, unused_completion_reserved,
    unused_irq_status, unused_error_status, unused_error_tag,
    unused_reject_count};

  logic dma_job_valid, dma_job_ready;
  npu_defs_pkg::npu_dma_job_t dma_job_data;
  logic dma_job_done, dma_job_error, dma_partial_output;
  npu_defs_pkg::npu_error_e dma_error_code;
  logic [OUTSTANDING_W-1:0] dma_outstanding;
  logic store_elem_valid, store_elem_ready;
  logic store_elem_vector4;logic [127:0] store_elem_vector_data;
  logic signed [31:0] store_elem_data;
  logic [2:0] store_elem_bytes;
  logic [15:0] store_elem_row, store_elem_col;

  logic spad_owner_valid, spad_owner_is_b, spad_owner_bank;
  logic [1:0] spad_owner_state;
  logic [3:0] spad_a_owner, spad_b_owner;
  logic spad_protocol_error;
  logic spad_compute_read_valid, spad_compute_bank;
  logic [K_INDEX_W-1:0] spad_compute_k;
  logic spad_compute_read_data_valid;
  logic signed [ARRAY_ROWS*16-1:0] spad_a_vector;
  logic signed [ARRAY_COLS*16-1:0] spad_b_vector;
  logic spad_write_valid, spad_write_is_b, spad_write_bank;
  logic [SPAD_LANE_W-1:0] spad_write_lane;
  logic [K_INDEX_W-1:0] spad_write_k;
  logic spad_write_input_int16;
  logic signed [SPAD_LOAD_ELEMS*16-1:0] spad_write_data;
  logic [((SPAD_LOAD_ELEMS>1)?$clog2(SPAD_LOAD_ELEMS+1):1)-1:0] spad_write_count;

  logic array_start_valid, array_start_ready;
  logic [15:0] array_k_len;
  logic [ARRAY_ROWS-1:0] array_row_mask;
  logic [ARRAY_COLS-1:0] array_col_mask;
  logic array_continue_acc, array_input_int16;
  logic array_feed_valid, array_feed_ready, array_done;
  logic signed [ARRAY_ROWS*16-1:0] array_feed_a;
  logic signed [ARRAY_COLS*16-1:0] array_feed_b;
  logic [ROW_INDEX_W-1:0] array_acc_read_row;
  logic [COL_INDEX_W-1:0] array_acc_read_col;
  logic signed [ACC_W-1:0] array_acc_rdata;

  logic post_in_valid, post_in_ready;
  logic signed [ACC_W-1:0] post_in_value;
  logic [1:0] post_output_fmt, post_activation;
  logic post_rounding;
  logic [5:0] post_shift;
  logic signed [31:0] post_clamp_min, post_clamp_max;
  logic post_out_valid, post_out_ready;
  logic signed [31:0] post_out_value;
  logic [2:0] post_out_bytes;


  logic resident_mode_q;
  logic res_committed_ready;
  logic [10:0] res_read_k;
  wire resident_command_eligible=(resident_enable===1'b1)&&!cmd_pop_data.input_int16&&
       cmd_pop_data.m<=16&&cmd_pop_data.n<=resident_b_columns&&
       cmd_pop_data.n<=256&&cmd_pop_data.k<=1152;
  logic [31:0] res_model,res_frame,res_task,res_agen,res_a_base,res_b_base;
  logic [5:0] res_rows;logic [8:0] res_columns;logic [10:0] res_k,res_k_base;
  logic [4:0] res_b_group,res_scheduler_n_group;logic res_claim,res_poison,res_vector_valid,legacy_unpack_enable;
  logic result_array_read_enable,result_protocol_error;
  logic [ROW_INDEX_W-1:0] result_array_read_row;
  logic [ARRAY_COLS*ACC_W-1:0] result_array_row_data;
  logic [255:0] res_a_vector;logic [127:0] res_b_vector;
  logic sched_job_valid,sched_job_ready,sched_job_done,sched_job_error;
  npu_defs_pkg::npu_dma_job_t sched_job;
  npu_defs_pkg::npu_error_e sched_error_code;
  logic legacy_read_valid,legacy_spad_error,unpack_ready;
  logic signed [ARRAY_ROWS*16-1:0] legacy_a_vector;
  logic signed [ARRAY_COLS*16-1:0] legacy_b_vector;
  logic [15:0] unpack_full_row,unpack_full_col;
  logic [4:0] res_next_a_rows;
  logic order_ready,order_idle,order_poison,ordered_valid,ordered_ready,ordered_write,ordered_error;
  logic [MEM_ID_W-1:0] ordered_id,physical_id;
  logic [MEM_DATA_W-1:0] ordered_data,physical_wdata;
  logic physical_req_valid,physical_req_ready,physical_write;
  logic [MEM_ADDR_W-1:0] physical_addr;logic [MEM_DATA_W/8-1:0] physical_strobe;
  logic [OUTSTANDING_W-1:0] ordered_owned;
  // 过程边界：always_ff @(posedge clk)begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk)begin
   // 复位相关判断：core_rst；分支方向由信号极性与取反表达式决定。
   if(core_rst)begin
    resident_mode_q<=0;res_next_a_rows<=0;res_model<=0;res_frame<=0;res_task<=0;res_agen<=0;
    res_a_base<=0;res_b_base<=0;res_rows<=0;res_columns<=0;res_k<=0;res_b_group<=0;
   // 握手/背压判断：cmd_pop_valid&&cmd_pop_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   end else if(cmd_pop_valid&&cmd_pop_ready)begin
    resident_mode_q<=resident_command_eligible;
    res_next_a_rows<=(resident_command_eligible && cmd_pop_data.m==16 &&
                     cmd_pop_data.a_stride==32'(cmd_pop_data.k)) ? resident_next_a_rows:5'd0;
    res_model<=resident_model_epoch;res_frame<=resident_frame_epoch;res_task<=resident_task_generation;
    res_agen<=resident_a_generation;res_a_base<=cmd_pop_data.a_base;res_b_base<=resident_b_base;
    res_rows<=6'(cmd_pop_data.m);res_columns<=resident_b_columns;res_k<=11'(cmd_pop_data.k);res_b_group<=resident_b_group;
   end
  end
  // 组合连接 spad_protocol_error：记录异常状态；查看置位与清除分支可确定其保持范围。
  assign spad_protocol_error=legacy_spad_error||res_poison||result_protocol_error;
  // 组合连接 spad_compute_read_data_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
  assign spad_compute_read_data_valid=resident_mode_q?res_vector_valid:legacy_read_valid;
  // 组合连接 spad_a_vector：保存/传递数据负载，数据有效性由独立控制字段约束。
  assign spad_a_vector=resident_mode_q?res_a_vector:legacy_a_vector;
  // 组合连接 spad_b_vector：保存/传递数据负载，数据有效性由独立控制字段约束。
  assign spad_b_vector=resident_mode_q?res_b_vector:legacy_b_vector;
  // The response-order sidecar owns only accepted real transactions.
  npu_response_order #(.DATA_W(MEM_DATA_W),.ID_W(MEM_ID_W),.SLOTS(MEM_OUTSTANDING),.IN_ORDER_TRANSPORT(IN_ORDER_TRANSPORT)) u_order(
   .clk,.rst(region_reset_u_order),.issue_valid(physical_req_valid&&dma_req_ready),.issue_ready(order_ready),
   .issue_id(physical_id),.issue_write(physical_write),
   .rsp_valid(dma_rsp_valid),.rsp_ready(dma_rsp_ready),.rsp_id(dma_rsp_id),.rsp_write(dma_rsp_write),.rsp_error(dma_rsp_error),.rsp_data(dma_rsp_rdata),
   .out_valid(ordered_valid),.out_ready(ordered_ready),.out_id(ordered_id),.out_write(ordered_write),.out_error(ordered_error),.out_data(ordered_data),
   .drained(),.idle(order_idle),.protocol_poison(order_poison),.owned(ordered_owned));
  // 组合连接 dma_req_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
  assign dma_req_valid=physical_req_valid&&order_ready;
  // 组合连接 physical_req_ready：表达接口或资源就绪；需结合相应有效/完成条件解释。
  assign physical_req_ready=dma_req_ready&&order_ready;
  // 组合连接 dma_req_write：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  assign dma_req_write=physical_write;assign dma_req_addr=physical_addr;
  // 组合连接 dma_req_wdata：保存/传递数据负载，数据有效性由独立控制字段约束。
  assign dma_req_wdata=physical_wdata;assign dma_req_wstrb=physical_strobe;assign dma_req_id=physical_id;
  npu_resident_operand_adapter #(.DRAM_BASE(DRAM_BASE),.DRAM_BYTES(DRAM_BYTES),
   .PIPELINED_FILL(RESIDENT_PACK_PIPELINED),.PREFETCH_A(RESIDENT_A_PREFETCH)) u_resident(
   .clk,.rst(region_reset_u_resident),.mode_resident(resident_mode_q),.model_epoch(res_model),.frame_epoch(res_frame),.task_generation(res_task),.a_generation(res_agen),
   .next_a_rows(res_next_a_rows),.a_base(res_a_base),.b_page_base(res_b_base),.a_rows(res_rows),.b_columns(res_columns),.k_length(res_k),.b_group(res_b_group+res_scheduler_n_group),
   .sched_valid(sched_job_valid),.sched_ready(sched_job_ready),.sched_job,
   .sched_done(sched_job_done),.sched_error(sched_job_error),.sched_error_code,
   .physical_valid(dma_job_valid),.physical_ready(dma_job_ready),.physical_job(dma_job_data),
   .physical_done(dma_job_done),.physical_error(dma_job_error),.physical_error_code(dma_error_code),
   .outstanding(dma_outstanding),.order_idle,.order_poison,
   .unpack_valid(spad_write_valid),.unpack_ready,.unpack_row(unpack_full_row),.unpack_col(unpack_full_col),
   .unpack_count(spad_write_count),.unpack_data(spad_write_data),.legacy_unpack_enable,
   .claim(resident_mode_q&&res_claim),
   .release_compute(resident_mode_q&&spad_owner_valid&&spad_owner_is_b&&spad_owner_state==0),
   .read_valid(resident_mode_q&&spad_compute_read_valid),.read_k(res_read_k),
   .committed_operands_ready(res_committed_ready),
   .vector_valid(res_vector_valid),.a_vector(res_a_vector),.b_vector(res_b_vector),.protocol_poison(res_poison));

  // 组合连接 exclusive_idle：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  assign exclusive_idle=cmd_empty&&!completion_head_valid&&!scheduler_active&&(dma_outstanding==0);
  // 组合连接 completion_empty：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  assign completion_empty = !completion_head_valid;
  // 静态配置：localparam logic [COMP_COUNT_W-1:0] COMPQ_DEPTH_COUNT =。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [COMP_COUNT_W-1:0] COMPQ_DEPTH_COUNT =
    COMP_COUNT_W'(COMPQ_DEPTH);
  // 组合连接 completion_full：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  assign completion_full = (completion_level == COMPQ_DEPTH_COUNT);
  // 组合连接 completion_enqueued：参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  assign completion_enqueued = completion_enqueue_valid && completion_enqueue_ready;
  // 组合连接 completion_release_reservation：跟踪存储/事务所有权，释放条件由对应完成分支决定。
  assign completion_release_reservation = 1'b0;
  // 组合连接 error_event_valid：标识这一路负载有效；是否接收还需检查对应的消费条件。
  assign error_event_valid = completion_enqueued &&
                             (completion_enqueue_data.error != npu_defs_pkg::ERR_NONE);
  // 组合连接 error_event_code：记录异常状态；查看置位与清除分支可确定其保持范围。
  assign error_event_code = completion_enqueue_data.error;

  // The MMIO leaf samples this acceptance on the write edge.  The companion
  // register keeps that same decision aligned with its registered request so
  // a rejected request cannot become accepted merely because work ends later.
  assign soft_reset_accept = !scheduler_active && (dma_outstanding == '0);
  // 组合连接 soft_reset_fire：参与复位或清空条件；极性和同步边界以使用它的过程为准。
  assign soft_reset_fire = soft_reset_req && soft_reset_accept_q;
  // 组合连接 core_rst：参与复位或清空条件；极性和同步边界以使用它的过程为准。
  assign core_rst = rst || soft_reset_fire;
  // 过程边界：always_ff @(posedge clk) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) begin
    // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
    if (rst)
      soft_reset_accept_q <= 1'b0;
    else
      soft_reset_accept_q <= soft_reset_accept;
  end

  initial begin
    // 条件分支：检查 ARRAY_ROWS < 2 || ARRAY_ROWS > 16 ||。
    if (ARRAY_ROWS < 2 || ARRAY_ROWS > 16 ||
        ((ARRAY_ROWS & (ARRAY_ROWS - 1)) != 0))
      $fatal(1, "npu_accel_top: ARRAY_ROWS must be a power of two from 2 to 16");
    // 条件分支：检查 ARRAY_COLS < 2 || ARRAY_COLS > 16 ||。
    if (ARRAY_COLS < 2 || ARRAY_COLS > 16 ||
        ((ARRAY_COLS & (ARRAY_COLS - 1)) != 0))
      $fatal(1, "npu_accel_top: ARRAY_COLS must be a power of two from 2 to 16");
    // 条件分支：检查 K_TILE < 8 || K_TILE > 256 || ((K_TILE & (K_TILE - 1)) != 0)。
    if (K_TILE < 8 || K_TILE > 256 || ((K_TILE & (K_TILE - 1)) != 0))
      $fatal(1, "npu_accel_top: K_TILE must be a power of two from 8 to 256");
    // 条件分支：检查 ACC_W < 48 || ACC_W > 64。
    if (ACC_W < 48 || ACC_W > 64)
      $fatal(1, "npu_accel_top: ACC_W must be in [48,64]");
    // 条件分支：检查 (MUL_PIPE_STAGES != 1) && (MUL_PIPE_STAGES != 2)。
    if ((MUL_PIPE_STAGES != 1) && (MUL_PIPE_STAGES != 2))
      $fatal(1, "npu_accel_top: MUL_PIPE_STAGES must be 1 or 2");
    // 条件分支：检查 (MEM_DATA_W != 32) && (MEM_DATA_W != 64) && (MEM_DATA_W != 128)。
    if ((MEM_DATA_W != 32) && (MEM_DATA_W != 64) && (MEM_DATA_W != 128))
      $fatal(1, "npu_accel_top: MEM_DATA_W must be 32, 64, or 128");
    // 条件分支：检查 MEM_ADDR_W != 32。
    if (MEM_ADDR_W != 32)
      $fatal(1, "npu_accel_top: v1 requires MEM_ADDR_W=32");
    // 条件分支：检查 MEM_ID_W < 1 || MEM_ID_W > 30。
    if (MEM_ID_W < 1 || MEM_ID_W > 30)
      $fatal(1, "npu_accel_top: MEM_ID_W must be in [1,30]");
    // 条件分支：检查 MEM_OUTSTANDING < 1 || MEM_OUTSTANDING_U64 > DMA_ID_CAPACITY。
    if (MEM_OUTSTANDING < 1 || MEM_OUTSTANDING_U64 > DMA_ID_CAPACITY)
      $fatal(1, "npu_accel_top: MEM_OUTSTANDING must be in [1,2**MEM_ID_W]");
    // 条件分支：检查 DMA_TIMEOUT_CYCLES < 0。
    if (DMA_TIMEOUT_CYCLES < 0)
      $fatal(1, "npu_accel_top: DMA_TIMEOUT_CYCLES must be nonnegative");
    // 条件分支：检查 CMDQ_DEPTH < 2 || CMDQ_DEPTH > 128 ||。
    if (CMDQ_DEPTH < 2 || CMDQ_DEPTH > 128 ||
        ((CMDQ_DEPTH & (CMDQ_DEPTH - 1)) != 0))
      $fatal(1, "npu_accel_top: CMDQ_DEPTH must be a power of two from 2 to 128");
    // 条件分支：检查 COMPQ_DEPTH < 2 || COMPQ_DEPTH > 128 ||。
    if (COMPQ_DEPTH < 2 || COMPQ_DEPTH > 128 ||
        ((COMPQ_DEPTH & (COMPQ_DEPTH - 1)) != 0))
      $fatal(1, "npu_accel_top: COMPQ_DEPTH must be a power of two from 2 to 128");
    // 条件分支：检查 (DRAM_BYTES == 0) || (DRAM_LIMIT > 65'h1_0000_0000)。
    if ((DRAM_BYTES == 0) || (DRAM_LIMIT > 65'h1_0000_0000))
      $fatal(1, "npu_accel_top: DRAM aperture must be positive and end at or below 2**32");
  end

  npu_mmio_overlay #(
    .ARRAY_ROWS(ARRAY_ROWS), .ARRAY_COLS(ARRAY_COLS), .K_TILE(K_TILE),
    .MEM_DATA_W(MEM_DATA_W), .CMDQ_DEPTH(CMDQ_DEPTH), .COMPQ_DEPTH(COMPQ_DEPTH)
  ) u_mmio (
    .clk(clk), .rst(region_reset_u_mmio), .perip_addr(perip_addr), .perip_wdata(perip_wdata),
    .perip_wen(perip_wen), .perip_mask(perip_mask),
    .legacy_perip_rdata(legacy_perip_rdata),
    .combined_perip_rdata(combined_perip_rdata),
    .cmd_push_valid(cmd_push_valid), .cmd_push_ready(cmd_push_ready),
    .cmd_push_data(cmd_push_data), .cmd_level(cmd_level),
    .cmd_empty(cmd_empty), .cmd_full(cmd_full),
    .completion_head_valid(completion_head_valid),
    .completion_head_data(completion_head_data),
    .completion_enqueued(completion_enqueued), .completion_pop(completion_pop),
    .completion_level(completion_level), .completion_empty(completion_empty),
    .completion_full(completion_full), .active(scheduler_active),
    .error_event_valid(error_event_valid), .error_event_code(error_event_code),
    .error_event_tag(completion_enqueue_data.user_tag), .soft_reset_req(soft_reset_req),
    .soft_reset_accept(soft_reset_accept), .irq_status(unused_irq_status),
    .error_status(unused_error_status), .error_tag(unused_error_tag),
    .reject_count(unused_reject_count), .irq(irq)
  );

  npu_cmd_queue #(.DEPTH(CMDQ_DEPTH)) u_cmdq (
    .clk(clk), .rst(region_reset_u_cmdq), .push_valid(cmd_push_valid),
    .push_ready(cmd_push_ready), .push_data(cmd_push_data),
    .pop_valid(cmd_pop_valid), .pop_ready(cmd_pop_ready), .pop_data(cmd_pop_data),
    .level(cmd_level), .full(cmd_full), .empty(cmd_empty)
  );

  npu_completion_queue #(.DEPTH(COMPQ_DEPTH)) u_compq (
    .clk(clk), .rst(region_reset_u_compq), .reserve_valid(completion_reserve_valid),
    .reserve_ready(completion_reserve_ready),
    .release_reservation(completion_release_reservation),
    .enqueue_valid(completion_enqueue_valid), .enqueue_ready(completion_enqueue_ready),
    .enqueue_data(completion_enqueue_data), .head_valid(completion_head_valid),
    .head_data(completion_head_data), .pop(completion_pop),
    .level(completion_level), .reserved(unused_completion_reserved)
  );

  npu_scheduler #(
    .RESULT_CHUNK_COLUMNS(RESIDENT_RESULT_CHUNK_COLUMNS),
    .STORE_VECTOR4_ENABLE(RESIDENT_STORE_VECTOR4 && MEM_DATA_W==128),
    .RESIDENT_GROUP_REUSE_ENABLE(RESIDENT_GROUP_REUSE_ENABLE),
    .ARRAY_ROWS(ARRAY_ROWS), .ARRAY_COLS(ARRAY_COLS), .K_TILE(K_TILE),
    .ACC_W(ACC_W), .DRAM_BASE(DRAM_BASE), .DRAM_BYTES(DRAM_BYTES),
    .RESULT_PAGE_STORE(ARRAY_ROWS==16&&ARRAY_COLS==8&&ACC_W==48&&MEM_DATA_W==128&&MEM_OUTSTANDING<=16),
    .RESIDENT_FULL_K_ENABLE(RESIDENT_FULL_K_ENABLE&&ARRAY_ROWS==16&&ARRAY_COLS==8)
  ) u_scheduler (
    .clk(clk), .rst(region_reset_u_scheduler), .cmd_valid(cmd_pop_valid), .cmd_ready(cmd_pop_ready),
    .result_page_enable(resident_command_eligible),
    .resident_compute_mode(resident_command_eligible),.resident_read_k(res_read_k),
    .resident_operands_ready(res_committed_ready),
    .result_context({resident_model_epoch,resident_frame_epoch,resident_task_generation,resident_a_generation}),
    .result_dma_outstanding(5'(dma_outstanding)),.result_order_idle(order_idle),.result_order_poison(order_poison),
    .result_array_read_enable,.result_array_read_row,.result_array_row_data,.result_protocol_error,
    .cmd_data(cmd_pop_data), .reserve_valid(completion_reserve_valid),
    .reserve_ready(completion_reserve_ready),
    .completion_valid(completion_enqueue_valid),
    .completion_ready(completion_enqueue_ready),
    .completion_data(completion_enqueue_data), .dma_job_valid(sched_job_valid),
    .dma_job_ready(sched_job_ready), .dma_job_data(sched_job),
    .dma_job_done(sched_job_done), .dma_job_error(sched_job_error),
    .dma_error_code(sched_error_code), .dma_partial_output(dma_partial_output),
    .spad_owner_valid(spad_owner_valid), .spad_owner_is_b(spad_owner_is_b),
    .spad_owner_bank(spad_owner_bank), .spad_owner_state(spad_owner_state),
    .spad_a_owner(spad_a_owner), .spad_b_owner(spad_b_owner),
    .spad_protocol_error(spad_protocol_error),
    .spad_compute_read_valid(spad_compute_read_valid),
    .spad_compute_bank(spad_compute_bank), .spad_compute_k(spad_compute_k),
    .spad_compute_read_data_valid(spad_compute_read_data_valid),
    .spad_a_vector(spad_a_vector), .spad_b_vector(spad_b_vector),
    .array_start_valid(array_start_valid), .array_start_ready(array_start_ready),
    .array_k_len(array_k_len), .array_row_mask(array_row_mask),
    .array_col_mask(array_col_mask), .array_continue_acc(array_continue_acc),
    .array_input_int16(array_input_int16), .array_feed_valid(array_feed_valid),
    .array_feed_ready(array_feed_ready), .array_feed_a(array_feed_a),
    .array_feed_b(array_feed_b), .array_done(array_done),
    .array_acc_read_row(array_acc_read_row),
    .array_acc_read_col(array_acc_read_col), .array_acc_rdata(array_acc_rdata),
    .post_in_valid(post_in_valid), .post_in_ready(post_in_ready),
    .post_in_value(post_in_value), .post_output_fmt(post_output_fmt),
    .post_activation(post_activation), .post_rounding(post_rounding),
    .post_shift(post_shift), .post_clamp_min(post_clamp_min),
    .post_clamp_max(post_clamp_max), .post_out_valid(post_out_valid),
    .post_out_ready(post_out_ready), .post_out_value(post_out_value),
    .post_out_bytes(post_out_bytes), .store_elem_vector4(store_elem_vector4),.store_elem_vector_data(store_elem_vector_data),.store_elem_valid(store_elem_valid),
    .store_elem_ready(store_elem_ready), .store_elem_data(store_elem_data),
    .store_elem_bytes(store_elem_bytes), .store_elem_row(store_elem_row),
    .store_elem_col(store_elem_col), .resident_k_base(res_k_base),.resident_claim(res_claim),
    .resident_n_group(res_scheduler_n_group),.active(scheduler_active)
  );

  npu_dma_engine #(
    .STORE_VECTOR4_ENABLE(RESIDENT_STORE_VECTOR4 && MEM_DATA_W==128),
    .MEM_ADDR_W(MEM_ADDR_W), .MEM_DATA_W(MEM_DATA_W), .MEM_ID_W(MEM_ID_W),
    .MEM_OUTSTANDING(MEM_OUTSTANDING), .ARRAY_ROWS(ARRAY_ROWS),
    .ARRAY_COLS(ARRAY_COLS), .K_TILE(K_TILE),
    .READ_REQ_PIPELINE(DMA_READ_PIPELINE),.RSP_FIFO_DEPTH(DMA_RSP_DEPTH),
    .DMA_TIMEOUT_CYCLES(DMA_TIMEOUT_CYCLES), .SPAD_VECTOR_ELEMS(SPAD_LOAD_ELEMS),
    .A_PACKED_INT8_16(A_PACKED_INT8_16)
  ) u_dma (
    .clk(clk), .rst(region_reset_u_dma), .job_valid(dma_job_valid), .job_ready(dma_job_ready),
    .job_data(dma_job_data), .dma_req_valid(physical_req_valid),
    .dma_req_ready(physical_req_ready), .dma_req_write(physical_write),
    .dma_req_addr(physical_addr), .dma_req_wdata(physical_wdata),
    .dma_req_wstrb(physical_strobe), .dma_req_id(physical_id),
    .dma_rsp_valid(ordered_valid), .dma_rsp_ready(ordered_ready),
    .dma_rsp_write(ordered_write), .dma_rsp_id(ordered_id),
    .dma_rsp_rdata(ordered_data), .dma_rsp_error(ordered_error),
    .store_elem_vector4(store_elem_vector4),.store_elem_vector_data(store_elem_vector_data),.store_elem_valid(store_elem_valid), .store_elem_ready(store_elem_ready),
    .store_elem_data(store_elem_data), .store_elem_bytes(store_elem_bytes),
    .store_elem_row(store_elem_row), .store_elem_col(store_elem_col),
    .spad_write_valid(spad_write_valid), .spad_write_ready(unpack_ready),
    .spad_write_is_b(spad_write_is_b), .spad_write_bank(spad_write_bank),
    .spad_write_lane(spad_write_lane), .spad_write_k(spad_write_k),
    .spad_write_input_int16(spad_write_input_int16),
    .spad_write_data(spad_write_data), .spad_write_count(spad_write_count), .spad_write_row_full(unpack_full_row),.spad_write_col_full(unpack_full_col),.job_done(dma_job_done),
    .job_error(dma_job_error), .error_code(dma_error_code),
    .partial_output(dma_partial_output), .outstanding(dma_outstanding)
  );

  npu_scratchpad #(
    .ARRAY_ROWS(ARRAY_ROWS), .ARRAY_COLS(ARRAY_COLS), .K_TILE(K_TILE),
    .MAX_ELEM_W(16), .DMA_VECTOR_ELEMS(SPAD_LOAD_ELEMS),
    .A_PACKED_INT8_16(A_PACKED_INT8_16)
  ) u_spad (
    .clk(clk), .rst(region_reset_u_spad), .owner_req_valid(spad_owner_valid),
    .owner_req_is_b(spad_owner_is_b), .owner_req_bank(spad_owner_bank),
    .owner_req_state(spad_owner_state), .dma_write_valid(spad_write_valid&&legacy_unpack_enable),
    .dma_is_b(spad_write_is_b), .dma_bank(spad_write_bank),
    .dma_lane(spad_write_lane), .dma_k(spad_write_k),
    .dma_input_int16(spad_write_input_int16), .dma_data(spad_write_data), .dma_count(spad_write_count),
    .compute_read_valid(spad_compute_read_valid&&!resident_mode_q),
    .compute_bank(spad_compute_bank), .compute_k(spad_compute_k),
    .a_vector(legacy_a_vector), .b_vector(legacy_b_vector),
    .compute_read_data_valid(legacy_read_valid),
    .a_owner(spad_a_owner), .b_owner(spad_b_owner),
    .protocol_error(legacy_spad_error)
  );

  npu_systolic_array #(
    .ARRAY_ROWS(ARRAY_ROWS), .ARRAY_COLS(ARRAY_COLS), .ACC_W(ACC_W),
    .MUL_PIPE_STAGES(MUL_PIPE_STAGES)
  ) u_array (
    .clk(clk), .rst(region_reset_u_array), .start_valid(array_start_valid),
    .start_ready(array_start_ready), .k_len(array_k_len),
    .row_mask(array_row_mask), .col_mask(array_col_mask),
    .continue_acc(array_continue_acc), .input_int16(array_input_int16),
    .feed_valid(array_feed_valid), .feed_ready(array_feed_ready),
    .feed_a(array_feed_a), .feed_b(array_feed_b), .tile_done(array_done),
    .acc_read_row(result_array_read_enable?result_array_read_row:array_acc_read_row), .acc_read_col(array_acc_read_col),
    .acc_rdata(array_acc_rdata),.acc_row_read_enable(result_array_read_enable),.acc_row_vector(result_array_row_data)
  );

  npu_postprocess #(.ACC_W(ACC_W)) u_postprocess (
    .clk(clk), .rst(region_reset_u_postprocess), .in_valid(post_in_valid), .in_ready(post_in_ready),
    .in_value(post_in_value), .output_fmt(post_output_fmt),
    .activation(post_activation), .rounding(post_rounding), .shift(post_shift),
    .clamp_min(post_clamp_min), .clamp_max(post_clamp_max),
    .out_valid(post_out_valid), .out_ready(post_out_ready),
    .out_value(post_out_value), .out_bytes(post_out_bytes)
  );
endmodule
