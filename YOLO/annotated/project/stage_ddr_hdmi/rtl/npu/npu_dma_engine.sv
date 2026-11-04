// Generic DMA boundary for LOAD_A/LOAD_B reads and packed STORE_C writes.
// 架构导读：npu_dma_engine。
// NPU 外部内存事务引擎，跟踪读写请求、响应编号、在途数量与异常边界。
module npu_dma_engine #(
  // 静态配置：parameter int MEM_ADDR_W = 32。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MEM_ADDR_W = 32,
  // 静态配置：parameter bit STORE_VECTOR4_ENABLE = 1'b0。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter bit STORE_VECTOR4_ENABLE = 1'b0,
  // 静态配置：parameter int MEM_DATA_W = 32。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MEM_DATA_W = 32,
  // 静态配置：parameter int MEM_ID_W = 2。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MEM_ID_W = 2,
  // 静态配置：parameter int MEM_OUTSTANDING = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int MEM_OUTSTANDING = 4,
  // 静态配置：parameter int ARRAY_ROWS = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int ARRAY_ROWS = 4,
  // 静态配置：parameter int ARRAY_COLS = 4。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int ARRAY_COLS = 4,
  // 静态配置：parameter int K_TILE = 32。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int K_TILE = 32,
  // 静态配置：parameter int SPAD_VECTOR_ELEMS = 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int SPAD_VECTOR_ELEMS = 1,
  // 静态配置：parameter bit A_PACKED_INT8_16 = 1'b0。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter bit A_PACKED_INT8_16 = 1'b0,
  // 静态配置：parameter int READ_REQ_PIPELINE = 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int READ_REQ_PIPELINE = 1,
  // 静态配置：parameter int RSP_FIFO_DEPTH = 2。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int RSP_FIFO_DEPTH = 2,
  // 静态配置：parameter int DMA_TIMEOUT_CYCLES = 4096。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  parameter int DMA_TIMEOUT_CYCLES = 4096
) (
  // 接口声明：input logic clk。
  // 时钟相关接口；使用本信号触发的时序过程属于相应时钟域。
  input  logic clk,
  // 接口声明：input logic rst。
  // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
  input  logic rst,
  // 接口声明：input logic job_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input  logic job_valid,
  // 接口声明：output logic job_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic job_ready,
  // 接口声明：input npu_defs_pkg::npu_dma_job_t job_data。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  input  npu_defs_pkg::npu_dma_job_t job_data,
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
  input  logic dma_rsp_error,
  // Four aligned INT32s share the existing source handshake and ID allocator.
  // Disabled by default for legacy standalone DMA instantiations.
  input logic store_elem_vector4,
  // 接口声明：input logic [127:0] store_elem_vector_data。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  input logic [127:0] store_elem_vector_data,
  // 接口声明：input logic store_elem_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  input  logic store_elem_valid,
  // 接口声明：output logic store_elem_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  output logic store_elem_ready,
  // 接口声明：input logic signed [31:0] store_elem_data。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  input  logic signed [31:0] store_elem_data,
  // 接口声明：input logic [2:0] store_elem_bytes。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic [2:0] store_elem_bytes,
  // 接口声明：input logic [15:0] store_elem_row。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic [15:0] store_elem_row,
  // 接口声明：input logic [15:0] store_elem_col。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  input  logic [15:0] store_elem_col,
  // 接口声明：output logic spad_write_valid。
  // 标识这一路负载有效；是否接收还需检查对应的消费条件。
  output logic spad_write_valid,
  // 接口声明：input logic spad_write_ready。
  // 表达接口或资源就绪；需结合相应有效/完成条件解释。
  input  logic spad_write_ready,
  // 接口声明：output logic spad_write_is_b。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic spad_write_is_b,
  // 接口声明：output logic spad_write_bank。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic spad_write_bank,
  // 接口声明：output logic [((ARRAY_ROWS > ARRAY_COLS) ? ((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1) : ((ARRAY_COLS > 1) ...。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic [((ARRAY_ROWS > ARRAY_COLS) ? ((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1) : ((ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1))-1:0] spad_write_lane,
  // 接口声明：output logic [((K_TILE > 1) ? $clog2(K_TILE) : 1)-1:0] spad_write_k。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic [((K_TILE > 1) ? $clog2(K_TILE) : 1)-1:0] spad_write_k,
  // 接口声明：output logic spad_write_input_int16。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic spad_write_input_int16,
  // 接口声明：output logic signed [SPAD_VECTOR_ELEMS*16-1:0] spad_write_data。
  // 保存/传递数据负载，数据有效性由独立控制字段约束。
  output logic signed [SPAD_VECTOR_ELEMS*16-1:0] spad_write_data,
  // 接口声明：output logic [((SPAD_VECTOR_ELEMS>1)?$clog2(SPAD_VECTOR_ELEMS+1):1)-1:0] spad_write_count。
  // 记录数量或剩余进度，位宽限定可表达范围。
  output logic [((SPAD_VECTOR_ELEMS>1)?$clog2(SPAD_VECTOR_ELEMS+1):1)-1:0] spad_write_count,
  // 接口声明：output logic [15:0] spad_write_row_full,spad_write_col_full。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic [15:0] spad_write_row_full,spad_write_col_full,
  // 接口声明：output logic job_done。
  // 表达本地完成/结束条件，系统退休还需满足上层接口契约。
  output logic job_done,
  // 接口声明：output logic job_error。
  // 记录异常状态；查看置位与清除分支可确定其保持范围。
  output logic job_error,
  // 接口声明：output npu_defs_pkg::npu_error_e error_code。
  // 记录异常状态；查看置位与清除分支可确定其保持范围。
  output npu_defs_pkg::npu_error_e error_code,
  // 接口声明：output logic partial_output。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic partial_output,
  // 接口声明：output logic [((MEM_OUTSTANDING > 0) ? $clog2(MEM_OUTSTANDING + 1) : 1)-1:0] outstanding。
  // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
  output logic [((MEM_OUTSTANDING > 0) ? $clog2(MEM_OUTSTANDING + 1) : 1)-1:0] outstanding
);
  import npu_defs_pkg::*;

  // 静态配置：localparam int MEM_BYTES = MEM_DATA_W / 8。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int MEM_BYTES = MEM_DATA_W / 8;
  // 静态配置：localparam int RSP_PAYLOAD_W = 2 + MEM_ID_W + MEM_DATA_W。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int RSP_PAYLOAD_W = 2 + MEM_ID_W + MEM_DATA_W;
  // 静态配置：localparam int SAFE_MEM_ID_W = ((MEM_ID_W >= 1) && (MEM_ID_W <= 30)) ?。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int SAFE_MEM_ID_W = ((MEM_ID_W >= 1) && (MEM_ID_W <= 30)) ?
                                 // 状态/选择分支 MEM_ID_W ：本分支规定该编码下的寄存器更新和下一步动作。
                                 MEM_ID_W : 1;
  // 静态配置：localparam logic [63:0] ID_CAPACITY = 64'd1 << SAFE_MEM_ID_W。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [63:0] ID_CAPACITY = 64'd1 << SAFE_MEM_ID_W;
  // 静态配置：localparam int SLOT_COUNT = (MEM_OUTSTANDING > 0) ? MEM_OUTSTANDING : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int SLOT_COUNT = (MEM_OUTSTANDING > 0) ? MEM_OUTSTANDING : 1;
  // 静态配置：localparam int SLOT_W = (SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int SLOT_W = (SLOT_COUNT > 1) ? $clog2(SLOT_COUNT) : 1;
  // 静态配置：localparam logic [63:0] MEM_OUTSTANDING_U64 =。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [63:0] MEM_OUTSTANDING_U64 =
    (MEM_OUTSTANDING > 0) ? 64'(MEM_OUTSTANDING) : 64'd0;
  // 静态配置：localparam int OWNED_W = (MEM_OUTSTANDING > 0) ?。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int OWNED_W = (MEM_OUTSTANDING > 0) ?
                           $clog2(MEM_OUTSTANDING + 1) : 1;
  // 静态配置：localparam int LANE_W = (ARRAY_ROWS > ARRAY_COLS) ?。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int LANE_W = (ARRAY_ROWS > ARRAY_COLS) ?
                            ((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1) :
                            ((ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1);
  // 静态配置：localparam int K_W = (K_TILE > 1) ? $clog2(K_TILE) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int K_W = (K_TILE > 1) ? $clog2(K_TILE) : 1;
  // 静态配置：localparam int BYTE_OFF_W = (MEM_BYTES > 1) ? $clog2(MEM_BYTES) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int BYTE_OFF_W = (MEM_BYTES > 1) ? $clog2(MEM_BYTES) : 1;
  // 静态配置：localparam int SEG_COUNT_W = (MEM_BYTES > 1) ? $clog2(MEM_BYTES + 1) : 1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int SEG_COUNT_W = (MEM_BYTES > 1) ? $clog2(MEM_BYTES + 1) : 1;
  // 静态配置：localparam int TIMEOUT_W = (DMA_TIMEOUT_CYCLES > 1) ?。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int TIMEOUT_W = (DMA_TIMEOUT_CYCLES > 1) ?
                           $clog2(64'(DMA_TIMEOUT_CYCLES) + 64'd1) : 1;
  // 静态配置：localparam logic [BYTE_OFF_W:0] MEM_BYTES_COUNT = (BYTE_OFF_W+1)'(MEM_BYTES)。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [BYTE_OFF_W:0] MEM_BYTES_COUNT = (BYTE_OFF_W+1)'(MEM_BYTES);
  // 静态配置：localparam logic [TIMEOUT_W-1:0] TIMEOUT_LIMIT =。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam logic [TIMEOUT_W-1:0] TIMEOUT_LIMIT =
    (DMA_TIMEOUT_CYCLES >= 0) ? TIMEOUT_W'(DMA_TIMEOUT_CYCLES) : '0;

  // Ownership starts when a request is registered, but `outstanding` itself
  // means accepted requests awaiting buffered response classification.
  typedef struct packed {
    logic is_b, bank;
    logic [15:0] row, col;
    logic [BYTE_OFF_W-1:0] byte_off;
    logic [SEG_COUNT_W-1:0] count;
    logic [1:0] elem_bytes;
  } id_meta_t;
  logic meta_valid [0:SLOT_COUNT-1];
  logic meta_accepted [0:SLOT_COUNT-1];
  logic meta_write [0:SLOT_COUNT-1];
  logic meta_is_b [0:SLOT_COUNT-1];
  logic meta_bank [0:SLOT_COUNT-1];
  logic [15:0] meta_row [0:SLOT_COUNT-1];
  logic [15:0] meta_col [0:SLOT_COUNT-1];
  logic [BYTE_OFF_W-1:0] meta_byte_off [0:SLOT_COUNT-1];
  logic [SEG_COUNT_W-1:0] meta_count [0:SLOT_COUNT-1];
  logic [1:0] meta_elem_bytes [0:SLOT_COUNT-1];

  logic job_active, failing, all_issued, store_source_done;
  logic [OWNED_W-1:0] owned_count;
  // Base is consumed by the address registers at acceptance, so retain only
  // the descriptor fields needed after that edge.
  struct packed {
    npu_dma_kind_e kind;
    logic [31:0] row_stride;
    logic [15:0] rows, cols;
    logic [1:0] elem_bytes;
    logic bank;
  } job_q;
  logic [15:0] next_row, next_col;
  // Job dimensions remain stable while active.  Capture their final indices
  // with the job to shorten the store-request enable path at 200 MHz.
  logic [15:0] job_last_row_q, job_last_col_q,job_last_vec_col_q;
  logic store_vector_seen;
  wire store_vector = STORE_VECTOR4_ENABLE && MEM_DATA_W==128 && (store_elem_vector4===1'b1);
  wire [15:0] store_step = store_vector ? 16'd4 : 16'd1;
  logic [31:0] row_base_q, element_addr_q;
  logic [31:0] cp12_read_step_address;
  cp12_dma_read_step #(.MEM_BYTES(MEM_BYTES)) read_step (
    .address(element_addr_q),.element_bytes(job_q.elem_bytes),
    .next_address(cp12_read_step_address));
  logic req_hold_valid;
  logic dma_req_write_q;
  logic [MEM_ADDR_W-1:0] dma_req_addr_q;
  logic [MEM_DATA_W-1:0] dma_req_wdata_q;
  logic [MEM_BYTES-1:0] dma_req_wstrb_q;
  logic [MEM_ID_W-1:0] dma_req_id_q;
  logic [SLOT_W-1:0] dma_req_slot_q;
  logic [SLOT_W-1:0] allocated_slot;
  logic allocate_valid, allocator_protocol_error;
  logic [OWNED_W-1:0] allocator_free_count;
  logic read_req_make, store_req_make, req_reserve, req_fire;
  logic [MEM_ADDR_W-1:0] element_addr;
  logic [BYTE_OFF_W-1:0] element_byte_off;
  logic [SEG_COUNT_W-1:0] segment_count;
  logic [15:0] cols_left;
  logic read_row_last;
  integer bytes_left;
  integer elems_fit;

  // A reserved read has 1 <= cols_left and a legal byte/halfword which fits
  // the current beat. segment_count = min(cols_left, elems_fit), so the row
  // ends exactly when the beat capacity covers the remaining columns.
  // Avoid serial min -> next_col add -> full-width compare; no new state or
  // latency, and keep the original reservation/ownership event unchanged.
  assign read_row_last = (cols_left <= 16'(elems_fit));

  logic store_pack_valid, store_pack_row_end, store_bytes_seen;
  logic [MEM_ADDR_W-1:0] store_pack_addr;
  logic [MEM_DATA_W-1:0] store_pack_data;
  logic [MEM_BYTES-1:0] store_pack_strb;
  logic [2:0] store_bytes_q;
  logic store_bytes_valid, store_input_valid, store_input_malformed;
  logic store_post_done_fault, store_fault_event;
  logic [MEM_ADDR_W-1:0] store_elem_addr, store_elem_beat;
  logic [BYTE_OFF_W-1:0] store_elem_byte_off;
  logic store_same_beat, store_row_last, store_job_last, store_flush_input, store_needs_request;
  logic store_can_make, store_fire, store_tail_make;
  logic [MEM_DATA_W-1:0] store_merged_data;
  logic [MEM_BYTES-1:0] store_merged_strb;

  logic rsp_id_known, rsp_owned, rsp_fire, rsp_owned_fire;
  logic rsp_fifo_in_valid, rsp_fifo_in_ready, rsp_fifo_out_valid, rsp_fifo_out_ready;
  logic [RSP_PAYLOAD_W-1:0] rsp_fifo_in_data, rsp_fifo_out_data;
  // 静态配置：localparam int RSP_COUNT_W=(RSP_FIFO_DEPTH>0)?$clog2(RSP_FIFO_DEPTH+1):1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int RSP_COUNT_W=(RSP_FIFO_DEPTH>0)?$clog2(RSP_FIFO_DEPTH+1):1;
  logic [RSP_COUNT_W-1:0] rsp_fifo_occupancy;
  logic rsp_q_write, rsp_q_error, rsp_ingress_fire;
  logic [MEM_ID_W-1:0] rsp_q_id;
  logic [MEM_DATA_W-1:0] rsp_q_rdata;
  logic [SLOT_W-1:0] rsp_slot;
  logic rsp_error_event, read_capture_fire;
  logic timeout_event, forward_progress, watchdog_pending;
  logic success_transition, failure_transition;
  logic [TIMEOUT_W-1:0] timeout_count;
  logic unpack_valid;
  logic [MEM_DATA_W-1:0] unpack_rdata;
  logic unpack_is_b, unpack_bank;
  logic [15:0] unpack_row, unpack_col;
  logic [BYTE_OFF_W-1:0] unpack_byte_off;
  logic [SEG_COUNT_W-1:0] unpack_count;
  logic [1:0] unpack_elem_bytes;
  logic [SEG_COUNT_W-1:0] unpack_index;
  logic spad_fire;
  logic unpack_last, unpack_can_exchange;
  // 静态配置：localparam int VECTOR_COUNT_W=(SPAD_VECTOR_ELEMS>1)?$clog2(SPAD_VECTOR_ELEMS+1):1。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int VECTOR_COUNT_W=(SPAD_VECTOR_ELEMS>1)?$clog2(SPAD_VECTOR_ELEMS+1):1;
  // 静态配置：localparam int ALIGN_W = (MEM_DATA_W>SPAD_VECTOR_ELEMS*16)?MEM_DATA_W:SPAD_VECTOR_ELEMS*16。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int ALIGN_W = (MEM_DATA_W>SPAD_VECTOR_ELEMS*16)?MEM_DATA_W:SPAD_VECTOR_ELEMS*16;
  // 静态配置：localparam int BATCH_W=(SEG_COUNT_W>VECTOR_COUNT_W)?SEG_COUNT_W:VECTOR_COUNT_W。
  // 该值在展开时参与宽度、深度或控制常量计算；实例覆盖值需沿上层参数检查。
  localparam int BATCH_W=(SEG_COUNT_W>VECTOR_COUNT_W)?SEG_COUNT_W:VECTOR_COUNT_W;
  logic [SEG_COUNT_W-1:0] unpack_batch, unpack_batch_q;
  logic unpack_last_q;
  logic [15:0] unpack_current_col, unpack_current_col_q;
  // Decode the scratchpad tuple at response capture. Keeping the B/A
  // lane-versus-K mux before these registers shortens the write-enable path
  // without inserting a transfer cycle.
  logic [LANE_W-1:0] unpack_spad_lane_q;
  logic [K_W-1:0] unpack_spad_k_q;
  logic [BATCH_W-1:0] unpack_remaining,unpack_boundary,unpack_limited,unpack_group_elems;
  logic [BYTE_OFF_W:0] unpack_shift_bytes,unpack_shift_bytes_q;
  logic [ALIGN_W-1:0] unpack_aligned;

  // CP11: a sidecar of the EXISTING response register, not an added stage.
  // Metadata arithmetic is evaluated at capture/advance; no raw RDATA bypass.
  // A simultaneous replacement response has the same priority as unpack_*.
  function automatic logic [SEG_COUNT_W-1:0] cp11_batch(
      // 接口声明：input logic [SEG_COUNT_W-1:0] count, index。
      // 选择队列、数组或数据片段的位置，更新条件见对应赋值。
      input logic [SEG_COUNT_W-1:0] count, index,
      // 接口声明：input logic [15:0] col, input logic is_b。
      // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
      input logic [15:0] col, input logic is_b,
      // 接口声明：input logic [1:0] elem_bytes)。
      // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
      input logic [1:0] elem_bytes);
    logic [BATCH_W-1:0] remaining, boundary, limited, group_elems;
    logic [15:0] current;
    begin
      current=col+16'(index);
      remaining=BATCH_W'(count)-BATCH_W'(index);
      // A compact word holds 16 INT8 or 8 INT16 elements. B uses
      // its original lane bound. Legacy V1/V2/V4/V8 is unchanged.
      group_elems=BATCH_W'((A_PACKED_INT8_16 && !is_b && elem_bytes==2'd2) ? 8 : SPAD_VECTOR_ELEMS);
      boundary=group_elems-BATCH_W'(current & (16'(group_elems)-16'd1));
      limited=remaining>group_elems?group_elems:remaining;
      cp11_batch=SEG_COUNT_W'(!is_b && limited>boundary ? boundary : limited);
    end
  endfunction
  assign unpack_current_col=unpack_current_col_q;
  assign unpack_batch=unpack_valid ? unpack_batch_q : '0;
  assign unpack_last=unpack_valid && unpack_last_q;
  assign unpack_can_exchange = !unpack_valid || (unpack_last && (spad_write_ready === 1'b1));
  // Original combinational expressions retained as independent simulation checks.
  assign unpack_remaining=BATCH_W'(unpack_count)-BATCH_W'(unpack_index);
  assign unpack_group_elems=BATCH_W'((A_PACKED_INT8_16 && !unpack_is_b && unpack_elem_bytes==2'd2) ? 8 : SPAD_VECTOR_ELEMS);
  assign unpack_boundary=unpack_group_elems-
      BATCH_W'((unpack_col+16'(unpack_index)) & (16'(unpack_group_elems)-16'd1));
  assign unpack_limited=unpack_remaining>unpack_group_elems?
      // 状态/选择分支 unpack_group_elems：本分支规定该编码下的寄存器更新和下一步动作。
      unpack_group_elems:unpack_remaining;
  // One shared alignment from the existing response register, followed by
  // fixed byte/halfword slices. Never fan raw FIFO payload directly to RAM.
  assign unpack_shift_bytes = (BYTE_OFF_W+1)'(unpack_byte_off) +
      ((BYTE_OFF_W+1)'(unpack_index) << (unpack_elem_bytes==2'd2));
  // CP8: maintain exactly the same modular byte offset at the existing
  // response-capture/vector-advance edges. No extra stage or transfer cycle.
  // The element-size/index arithmetic no longer precedes the barrel shifter.
  assign unpack_aligned = ALIGN_W'(unpack_rdata) >> {unpack_shift_bytes_q,3'b000};
  // CP8_UNPACK_OFFSET_STATE_BEGIN
  always_ff @(posedge clk) begin
    // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
    if (rst) unpack_shift_bytes_q <= '0;
    else begin
      // 条件分支：检查 spad_fire && !unpack_last。
      if (spad_fire && !unpack_last)
        unpack_shift_bytes_q <= unpack_shift_bytes_q +
          ((BYTE_OFF_W+1)'(unpack_batch) << (unpack_elem_bytes==2'd2));
      // When the current vector is absent or retires now, a response can be
      // consumed regardless of its ownership/type.  Preloading the offset for
      // a malformed or write response is harmless: no read vector becomes
      // valid, and the next valid read replaces it.  This keeps the ID
      // ownership lookup out of the shift-register enable path.
      if ((job_active === 1'b1) && (rsp_fifo_out_valid === 1'b1) &&
          unpack_can_exchange && (spad_write_ready === 1'b1))
        unpack_shift_bytes_q <= (BYTE_OFF_W+1)'(meta_byte_off[rsp_slot]);
    end
  end
  // CP8_UNPACK_OFFSET_STATE_END
  assign spad_write_count=VECTOR_COUNT_W'(unpack_batch);
  logic [15:0] segment_count_16;

  // 局部运算/辅助过程：function automatic logic signed [15:0] read_element(。
  // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
  function automatic logic signed [15:0] read_element(
    // 接口声明：input logic [MEM_DATA_W-1:0] data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [MEM_DATA_W-1:0] data,
    // 接口声明：input integer unsigned byte_offset。
    // 选择队列、数组或数据片段的位置，更新条件见对应赋值。
    input integer unsigned byte_offset,
    // 接口声明：input logic [1:0] elem_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [1:0] elem_bytes
  );
    logic [15:0] raw;
    begin
      raw = '0;
      // 条件分支：检查 elem_bytes == 2'd1。
      if (elem_bytes == 2'd1)
        raw = {{8{data[byte_offset*8 + 7]}}, data[byte_offset*8 +: 8]};
      // 条件分支：检查 elem_bytes == 2'd2。
      else if (elem_bytes == 2'd2)
        raw = data[byte_offset*8 +: 16];
      read_element = raw;
    end
  endfunction

  // Callers prove element width/alignment/range legal before merging.
  // PDS 2025.2 mis-maps mixed int comparisons and dynamic byte selections
  // at offsets >= 8. Explicitly sized masks preserve untouched lanes.
  function automatic logic [MEM_DATA_W-1:0] merge_store_data(
    // 接口声明：input logic [MEM_DATA_W-1:0] old_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic [MEM_DATA_W-1:0] old_data,
    // 接口声明：input logic signed [31:0] element_data。
    // 保存/传递数据负载，数据有效性由独立控制字段约束。
    input logic signed [31:0] element_data,
    // 接口声明：input logic [BYTE_OFF_W-1:0] byte_offset。
    // 选择队列、数组或数据片段的位置，更新条件见对应赋值。
    input logic [BYTE_OFF_W-1:0] byte_offset,
    // 接口声明：input logic [2:0] element_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [2:0] element_bytes
  );
    logic [MEM_DATA_W-1:0] mask, payload;
    begin
      mask = '0;
      // 按 element_bytes 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
      case (element_bytes)
        3'd1: mask[7:0] = 8'hff;
        3'd2: mask[15:0] = 16'hffff;
        3'd4: mask[31:0] = 32'hffffffff;
        default: mask = '0;
      endcase
      mask = mask << {byte_offset,3'b000};
      payload = {{(MEM_DATA_W-32){1'b0}},element_data};
      payload = payload << {byte_offset,3'b000};
      merge_store_data = (old_data & ~mask) | (payload & mask);
    end
  endfunction

  // 局部运算/辅助过程：function automatic logic [MEM_BYTES-1:0] merge_store_strb(。
  // 只封装当前模块的计算或条件检查；外部事务仍由请求/响应逻辑完成。
  function automatic logic [MEM_BYTES-1:0] merge_store_strb(
    // 接口声明：input logic [MEM_BYTES-1:0] old_strb。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [MEM_BYTES-1:0] old_strb,
    // 接口声明：input logic [BYTE_OFF_W-1:0] byte_offset。
    // 选择队列、数组或数据片段的位置，更新条件见对应赋值。
    input logic [BYTE_OFF_W-1:0] byte_offset,
    // 接口声明：input logic [2:0] element_bytes。
    // 参与本模块的局部数据/控制连接，驱动来源由后续赋值或实例端口给出。
    input logic [2:0] element_bytes
  );
    logic [MEM_BYTES-1:0] mask;
    begin
      mask = '0;
      // 按 element_bytes 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
      case (element_bytes)
        3'd1: mask[0] = 1'b1;
        3'd2: mask[1:0] = 2'b11;
        3'd4: mask[3:0] = 4'b1111;
        default: mask = '0;
      endcase
      merge_store_strb = old_strb | (mask << byte_offset);
    end
  endfunction

  npu_free_slot_allocator #(.SLOT_COUNT(SLOT_COUNT)) free_slots (
    .clk(clk), .rst(rst),
    .allocate_take(req_reserve), .allocate_valid(allocate_valid),
    .allocate_slot(allocated_slot),
    .release_valid(rsp_owned_fire), .release_slot(rsp_slot),
    .free_count(allocator_free_count), .protocol_error(allocator_protocol_error)
  );

  // 过程边界：always @* begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always @* begin
    element_addr = MEM_ADDR_W'(element_addr_q);
    element_byte_off = element_addr[BYTE_OFF_W-1:0];
    cols_left = job_q.cols - next_col;
    bytes_left = MEM_BYTES - int'(element_byte_off);
    elems_fit = 0;
    segment_count = '0;
    // 条件分支：检查 (job_q.kind === DMA_LOAD_A) || (job_q.kind === DMA_LOAD_B)。
    if ((job_q.kind === DMA_LOAD_A) || (job_q.kind === DMA_LOAD_B)) begin
      // Only byte/halfword jobs are legal. No variable divide in this cone.
      case(job_q.elem_bytes)
        2'd1: elems_fit=bytes_left;
        2'd2: elems_fit=bytes_left >> 1;
        default: elems_fit=0;
      endcase
      // 条件分支：检查 elems_fit > int'(cols_left)。
      if (elems_fit > int'(cols_left))
        segment_count = cols_left[SEG_COUNT_W-1:0];
      else
        segment_count = elems_fit[SEG_COUNT_W-1:0];
      // 条件分支：检查 segment_count == '0。
      if (segment_count == '0) segment_count = 1;
    end
    // This is the sole allocation event.  A response error visible in this
    // edge must stop a previously unpresented request before it owns metadata
    // or advances the logical source, while an already-held request remains.
    read_req_make = job_active && !failing && !rsp_error_event && !allocator_protocol_error &&
               ((job_q.kind === DMA_LOAD_A) || (job_q.kind === DMA_LOAD_B)) && !all_issued && (!req_hold_valid || ((READ_REQ_PIPELINE!=0) && req_fire)) &&
               (allocator_free_count != '0) &&
               allocate_valid && (job_q.elem_bytes == 2'd1 || job_q.elem_bytes == 2'd2) &&
               (({1'b0, element_byte_off} +
                 {{(BYTE_OFF_W-1){1'b0}}, job_q.elem_bytes}) <= MEM_BYTES_COUNT);
  end

  // 过程边界：always @* begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always @* begin
    store_elem_addr = MEM_ADDR_W'(element_addr_q);
    store_elem_beat = store_elem_addr & ~(MEM_BYTES - 1);
    store_elem_byte_off = store_elem_addr[BYTE_OFF_W-1:0];
    store_bytes_valid = (store_elem_bytes === 3'd1) || (store_elem_bytes === 3'd2) ||
                        (store_elem_bytes === 3'd4);
    store_input_valid = store_bytes_valid &&
                        (!store_bytes_seen || ((store_elem_bytes === store_bytes_q) &&
                          (store_vector===store_vector_seen))) &&
                        (!store_vector || (store_elem_bytes==4 && store_elem_byte_off==0 &&
                          job_q.cols[1:0]==0 && next_col[1:0]==0 && !store_pack_valid &&
                          {1'b0,next_col}+17'd4<={1'b0,job_q.cols})) &&
                        (store_elem_row === next_row) && (store_elem_col === next_col) &&
                        (({1'b0, store_elem_byte_off} +
                          {{(BYTE_OFF_W-2){1'b0}}, store_elem_bytes}) <=
                         MEM_BYTES_COUNT) &&
                        (((store_elem_bytes === 3'd1)) ||
                         ((store_elem_bytes === 3'd2) && (store_elem_byte_off[0] === 1'b0)) ||
                         ((store_elem_bytes === 3'd4) && (store_elem_byte_off[1:0] === 2'b00)));
    // Store-side payload is intentionally ignored while a read job owns this
    // shared leaf interface. Only an active STORE_C job may classify it as a
    // protocol fault.
    store_input_malformed = job_active && (job_q.kind === DMA_STORE_C) &&
                              (store_elem_valid === 1'b1) && !store_input_valid;
    // Once the final source transfer has occurred, every further valid is a
    // protocol violation.  It must defeat terminal success even though ready
    // is held low and no additional source handshake occurs.
    store_post_done_fault = job_active && (job_q.kind === DMA_STORE_C) &&
                            store_source_done && (store_elem_valid === 1'b1);
    store_fault_event = store_input_malformed || store_post_done_fault;
    store_same_beat = store_pack_valid && (store_pack_addr === store_elem_beat);
    store_row_last = store_vector ? next_col==job_last_vec_col_q : next_col==job_last_col_q;
    store_job_last = store_row_last && (next_row == job_last_row_q);
    store_flush_input = store_pack_valid && (!store_same_beat || store_row_last);
    store_needs_request = store_vector || (!store_pack_valid && store_row_last) || store_flush_input;
    store_can_make = (!req_hold_valid || (store_vector && req_fire)) &&
                     (allocator_free_count != '0) && allocate_valid;
    store_elem_ready = job_active && (job_q.kind === DMA_STORE_C) && !failing &&
                       !rsp_error_event && !allocator_protocol_error && !store_source_done &&
                       !store_pack_row_end &&
                       (store_input_malformed || !store_needs_request || store_can_make);
    store_fire = store_elem_valid && store_elem_ready;
    store_req_make = store_fire && store_input_valid &&
                     store_needs_request;
    store_tail_make = job_active && (job_q.kind === DMA_STORE_C) && !failing &&
                      !rsp_error_event && !allocator_protocol_error && !store_fault_event && store_source_done &&
                      store_pack_valid && store_can_make;
    // 条件分支：检查 store_pack_row_end。
    if (store_pack_row_end)
      store_tail_make = job_active && (job_q.kind === DMA_STORE_C) && !failing &&
                        !rsp_error_event && !allocator_protocol_error && !store_fault_event &&
                        store_pack_valid && store_can_make;
    req_reserve = read_req_make || store_req_make || store_tail_make;
    store_merged_data = '0;
    store_merged_strb = '0;
    // 条件分支：检查 store_input_valid && store_vector。
    if (store_input_valid && store_vector) begin
      store_merged_data = MEM_DATA_W'(store_elem_vector_data);
      store_merged_strb = '1;
    // 条件分支：检查 store_input_valid。
    end else if (store_input_valid) begin
      store_merged_data = merge_store_data(store_pack_valid ? store_pack_data : '0,
                                            store_elem_data, store_elem_byte_off, store_elem_bytes);
      store_merged_strb = merge_store_strb(store_pack_valid ? store_pack_strb : '0,
                                            store_elem_byte_off, store_elem_bytes);
    end
  end

  // Old idle state discards stray responses, including a response on the
  // same edge as job acceptance. Only an active job may enqueue; unknown
  // valid/state values fail closed. Ready is solely registered capacity.
  assign rsp_fifo_in_valid = (job_active === 1'b1) && (dma_rsp_valid === 1'b1);
  assign rsp_fifo_in_data = {dma_rsp_write, dma_rsp_error, dma_rsp_id, dma_rsp_rdata};
  assign {rsp_q_write, rsp_q_error, rsp_q_id, rsp_q_rdata} = rsp_fifo_out_data;
  assign dma_rsp_ready = rsp_fifo_in_ready;
  assign rsp_ingress_fire = rsp_fifo_in_valid && (rsp_fifo_in_ready === 1'b1);
  npu_elastic_fifo #(.WIDTH(RSP_PAYLOAD_W), .DEPTH(RSP_FIFO_DEPTH)) response_ingress (
    .clk(clk), .rst(rst),
    .in_valid(rsp_fifo_in_valid), .in_ready(rsp_fifo_in_ready), .in_data(rsp_fifo_in_data),
    .out_valid(rsp_fifo_out_valid), .out_ready(rsp_fifo_out_ready), .out_data(rsp_fifo_out_data),
    .occupancy(rsp_fifo_occupancy)
  );

  // 过程边界：always @* begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always @* begin
    rsp_id_known = ((^rsp_q_id) !== 1'bx);
    rsp_slot = '0;
    rsp_owned = 1'b0;
    // 条件分支：检查 rsp_id_known && (64'($unsigned(rsp_q_id)) < MEM_OUTSTANDING_U64)。
    if (rsp_id_known && (64'($unsigned(rsp_q_id)) < MEM_OUTSTANDING_U64)) begin
      rsp_slot = SLOT_W'(rsp_q_id);
      rsp_owned = (meta_valid[rsp_slot] === 1'b1) &&
                  (meta_accepted[rsp_slot] === 1'b1);
    end
  end

  assign job_ready = !job_active;
  assign dma_req_valid = req_hold_valid;
  assign dma_req_write = dma_req_write_q;
  assign dma_req_addr = dma_req_addr_q;
  assign dma_req_id = dma_req_id_q;
  assign dma_req_wdata = dma_req_wdata_q;
  assign dma_req_wstrb = dma_req_wstrb_q;
  assign req_fire = dma_req_valid && dma_req_ready;

  // Invalid/duplicate responses are consumed and converted to a deterministic
  // protocol failure so a broken responder cannot deadlock this engine.
  assign rsp_fifo_out_ready = (job_active === 1'b1) &&
                         ((failing === 1'b1) || !rsp_owned ||
                          (meta_write[rsp_slot] === 1'b1) ||
                          (unpack_can_exchange && (spad_write_ready === 1'b1)));
  assign rsp_fire = (rsp_fifo_out_valid === 1'b1) && (rsp_fifo_out_ready === 1'b1);
  assign rsp_owned_fire = rsp_fire && rsp_owned;
  assign rsp_error_event = rsp_fire && (!rsp_owned || (rsp_q_error !== 1'b0) ||
                             (rsp_owned && (rsp_q_write !== meta_write[rsp_slot])));
  // A valid read response can capture its unpack tuple directly.  Under
  // rsp_owned && !meta_write, rsp_fire reduces to the exchange-ready arm of
  // rsp_fifo_out_ready.  Keeping the error/duplicate-response mux off this
  // wide register-enable cone avoids a response-ID -> ready -> error -> CE
  // round trip, while the ownership/error bookkeeping below is unchanged.
  assign read_capture_fire = (job_active === 1'b1) &&
      (rsp_fifo_out_valid === 1'b1) && (failing === 1'b0) && rsp_owned &&
      (rsp_q_error === 1'b0) && (rsp_q_write === 1'b0) &&
      (meta_write[rsp_slot] === 1'b0) && unpack_can_exchange &&
      (spad_write_ready === 1'b1);
  // synthesis translate_off
  always_ff @(posedge clk) if (!rst) begin
    // 条件分支：检查 read_capture_fire !== ((rsp_fire && rsp_owned && !failing &&。
    if (read_capture_fire !== ((rsp_fire && rsp_owned && !failing &&
        !rsp_error_event && !meta_write[rsp_slot]) === 1'b1))
      $fatal(1, "NPU_DMA_READ_CAPTURE_EQUIVALENCE_RED");
  end
  // synthesis translate_on
  // Once asserted, an unpacked element stream is a ready/valid commitment.
  // An unrelated malformed response may fail the job, but cannot withdraw it.
  assign spad_write_valid = unpack_valid;
  assign spad_write_is_b = unpack_is_b;
  assign spad_write_bank = unpack_bank;
  assign segment_count_16 = {{(16-SEG_COUNT_W){1'b0}}, segment_count};
  assign spad_write_row_full=unpack_row;
  assign spad_write_col_full=unpack_current_col_q;
  assign spad_write_lane = unpack_spad_lane_q;
  assign spad_write_k = unpack_spad_k_q;
  assign spad_write_input_int16 = (unpack_elem_bytes == 2'd2);
  for(genvar e=0;e<SPAD_VECTOR_ELEMS;e++)begin : g_unpack_vector
    // CP8: count/valid qualify writes at the receiving scratchpad, not the
    // payload cone. ALIGN_W covers every static select, including V8/MEM32.
    // Elements e >= spad_write_count are unspecified payload and must never
    // be written. All tuple bits still remain stable throughout backpressure:
    // the unpack registers/index cannot advance without spad_fire.
    assign spad_write_data[e*16+:16] = (unpack_elem_bytes==2'd2) ?
      unpack_aligned[e*16+:16] : {{8{unpack_aligned[e*8+7]}},unpack_aligned[e*8+:8]};
  end
  assign spad_fire = spad_write_valid && spad_write_ready;

  // The watchdog measures consecutive edges on which DMA-owned work is
  // actionable but the engine makes no state-machine progress. A STORE_C job
  // waiting for its upstream source to present the next element is not a DMA
  // stall; once the source is valid, a request is held, a response is owed, or
  // an unpack stream is committed, the watchdog is armed. Internal request
  // formation, source packing, response unpacking, and terminal publication
  // are progress just as external transfers are. A merely held valid without
  // its handshake is deliberately absent from forward_progress.
  assign success_transition = job_active && !failing && !rsp_error_event &&
                              !allocator_protocol_error && !store_fault_event &&
                              (((job_q.kind === DMA_STORE_C) && store_source_done) ||
                               ((job_q.kind !== DMA_STORE_C) && all_issued)) &&
                              (outstanding == '0) && (owned_count == '0) &&
                              !req_hold_valid && !unpack_valid && !store_pack_valid &&
                              (rsp_fifo_occupancy == '0) && !rsp_ingress_fire;
  assign failure_transition = job_active && (failing || rsp_error_event || allocator_protocol_error) &&
                              (outstanding == '0) && (owned_count == '0) &&
                              !req_hold_valid && !unpack_valid && !store_pack_valid &&
                              (rsp_fifo_occupancy == '0) && !rsp_ingress_fire;
  assign forward_progress = req_reserve || req_fire || rsp_ingress_fire || rsp_fire || store_fire ||
                            spad_fire || store_fault_event || allocator_protocol_error ||
                            success_transition || failure_transition;
  assign watchdog_pending = job_active && !failing &&
                            ((((job_q.kind === DMA_LOAD_A) ||
                               (job_q.kind === DMA_LOAD_B)) && !all_issued) ||
                             req_hold_valid || (owned_count != '0) ||
                             (outstanding != '0) || (rsp_fifo_occupancy != '0) || unpack_valid ||
                             (((job_q.kind === DMA_STORE_C) &&
                               (store_elem_valid || store_source_done ||
                                store_pack_row_end))));
  cp9_progress_watchdog #(.LIMIT(DMA_TIMEOUT_CYCLES),.W(TIMEOUT_W)) watchdog_counter (
    .clk,.rst,.job_accept((job_valid === 1'b1) && (job_ready === 1'b1)),
    .active(job_active),.pending(watchdog_pending),.progress(forward_progress),
    .effective_count(timeout_count),.expired(timeout_event));
  // synthesis translate_off
  logic [TIMEOUT_W-1:0] cp9_timeout_reference;
  // 过程边界：always_ff @(posedge clk) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) begin
    // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
    if(rst) cp9_timeout_reference <= '0;
    // 握手/背压判断：(job_valid === 1'b1) && (job_ready === 1'b1)。
    // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
    else if((job_valid === 1'b1) && (job_ready === 1'b1)) cp9_timeout_reference <= '0;
    // 条件分支：检查 job_active。
    else if(job_active) begin
      // 条件分支：检查 forward_progress || !watchdog_pending || (DMA_TIMEOUT_CYCLES==0)。
      if(forward_progress || !watchdog_pending || (DMA_TIMEOUT_CYCLES==0)) cp9_timeout_reference <= '0;
      // 条件分支：检查 int'(cp9_timeout_reference)<DMA_TIMEOUT_CYCLES。
      else if(int'(cp9_timeout_reference)<DMA_TIMEOUT_CYCLES) cp9_timeout_reference <= cp9_timeout_reference+1'b1;
    end
    // 复位相关判断：!rst；分支方向由信号极性与取反表达式决定。
    if(!rst) begin
      // 条件分支：检查 timeout_count !== cp9_timeout_reference。
      if(timeout_count !== cp9_timeout_reference) $fatal(1,"CP9_WATCHDOG_INTEGRATED_COUNT_RED");
      // 条件分支：检查 timeout_event !== (watchdog_pending && (DMA_TIMEOUT_CYCLES!=0) && !forward_progress &&。
      if(timeout_event !== (watchdog_pending && (DMA_TIMEOUT_CYCLES!=0) && !forward_progress &&
         (cp9_timeout_reference==(TIMEOUT_LIMIT-1'b1)))) $fatal(1,"CP9_WATCHDOG_INTEGRATED_EVENT_RED");
    end
  end
  // synthesis translate_on

  // synthesis translate_off
  always_ff @(posedge clk)if(!rst && req_fire && read_req_make && allocated_slot==dma_req_slot_q)
    $fatal(1,"CP6_REQUEST_SLOT_OVERLAP_RED");
  // 过程边界：always_ff @(posedge clk) if(!rst && read_req_make) begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) if(!rst && read_req_make) begin
    // 条件分支：检查 !read_row_last && cp12_read_step_address !==。
    if(!read_row_last && cp12_read_step_address !==
       (element_addr_q + (32'(segment_count) << (job_q.elem_bytes == 2'd2))))
      $fatal(1,"CP12_DMA_ADDRESS_EQ_RED");
    // 条件分支：检查 next_col >= job_q.cols || cols_left == 0 || elems_fit <= 0。
    if(next_col >= job_q.cols || cols_left == 0 || elems_fit <= 0)
      $fatal(1,"CP8_READ_ROW_PRECONDITION_RED");
    // 条件分支：检查 read_row_last !== ((next_col + segment_count_16) >= job_q.cols)。
    if(read_row_last !== ((next_col + segment_count_16) >= job_q.cols))
      $fatal(1,"CP8_READ_ROW_EQUIVALENCE_RED");
  end
  // synthesis translate_on

  generate
    // 条件分支：检查 RSP_FIFO_DEPTH<2 || RSP_FIFO_DEPTH>16。
    if(RSP_FIFO_DEPTH<2 || RSP_FIFO_DEPTH>16)begin:g_bad_rsp_depth
      initial $fatal(1,"CP6_RSP_DEPTH_RED");
    end
    // 条件分支：检查 SPAD_VECTOR_ELEMS<1 || SPAD_VECTOR_ELEMS>(A_PACKED_INT8_16?16:8) ||。
    if (SPAD_VECTOR_ELEMS<1 || SPAD_VECTOR_ELEMS>(A_PACKED_INT8_16?16:8) ||
        ((SPAD_VECTOR_ELEMS & (SPAD_VECTOR_ELEMS-1))!=0) || SPAD_VECTOR_ELEMS>K_TILE) begin:g_bad_vector
      initial $fatal(1,"CP5_DMA_VECTOR_PARAM_RED");
    end
    // 条件分支：检查 A_PACKED_INT8_16 && (SPAD_VECTOR_ELEMS!=16 || MEM_DATA_W!=128 || K_TILE<16)。
    if(A_PACKED_INT8_16 && (SPAD_VECTOR_ELEMS!=16 || MEM_DATA_W!=128 || K_TILE<16))begin:g_bad_packed16
      initial $fatal(1,"A_INT8PACKED16_DMA_CONFIGURATION_RED");
    end
    // 条件分支：检查 (MEM_DATA_W != 32) && (MEM_DATA_W != 64) && (MEM_DATA_W != 128)。
    if ((MEM_DATA_W != 32) && (MEM_DATA_W != 64) && (MEM_DATA_W != 128)) begin : g_bad_data_width
      initial $fatal(1, "npu_dma_engine: MEM_DATA_W must be 32, 64, or 128");
    end
    // 条件分支：检查 MEM_ID_W < 1。
    if (MEM_ID_W < 1) begin : g_bad_id_width
      initial $fatal(1, "npu_dma_engine: MEM_ID_W must be at least 1");
    end
    // 条件分支：检查 MEM_ID_W > 30。
    if (MEM_ID_W > 30) begin : g_bad_id_width_high
      initial $fatal(1, "npu_dma_engine: MEM_ID_W must be at most 30");
    end
    // 条件分支：检查 (MEM_OUTSTANDING < 1) || (MEM_OUTSTANDING_U64 > ID_CAPACITY)。
    if ((MEM_OUTSTANDING < 1) || (MEM_OUTSTANDING_U64 > ID_CAPACITY)) begin : g_bad_outstanding
      initial $fatal(1, "npu_dma_engine: MEM_OUTSTANDING must be 1..2**MEM_ID_W");
    end
    // 条件分支：检查 (ARRAY_ROWS < 1) || (ARRAY_COLS < 1) || (K_TILE < 1)。
    if ((ARRAY_ROWS < 1) || (ARRAY_COLS < 1) || (K_TILE < 1)) begin : g_bad_shape
      initial $fatal(1, "npu_dma_engine: array and K dimensions must be positive");
    end
    // 条件分支：检查 DMA_TIMEOUT_CYCLES < 0。
    if (DMA_TIMEOUT_CYCLES < 0) begin : g_bad_timeout
      initial $fatal(1, "npu_dma_engine: DMA_TIMEOUT_CYCLES must be nonnegative");
    end
  endgenerate

  // synthesis translate_off
  always_ff @(posedge clk) if(!rst && unpack_valid)begin
    // 条件分支：检查 unpack_current_col_q !== unpack_col+16'(unpack_index)。
    if(unpack_current_col_q !== unpack_col+16'(unpack_index))
      $fatal(1,"CP11_UNPACK_COLUMN_EQ_RED");
    // 条件分支：检查 unpack_spad_lane_q !== LANE_W'(unpack_is_b ? unpack_current_col_q : unpack_row) ||。
    if (unpack_spad_lane_q !== LANE_W'(unpack_is_b ? unpack_current_col_q : unpack_row) ||
        unpack_spad_k_q !== K_W'(unpack_is_b ? unpack_row : unpack_current_col_q))
      $fatal(1,"NPU200_UNPACK_SPAD_TUPLE_EQ_RED");
    // 条件分支：检查 unpack_batch !== SEG_COUNT_W'(!unpack_is_b && unpack_limited>unpack_boundary ? unpack_boundary : unpack_lim...。
    if(unpack_batch !== SEG_COUNT_W'(!unpack_is_b && unpack_limited>unpack_boundary ? unpack_boundary : unpack_limited))
      $fatal(1,"CP11_UNPACK_BATCH_EQ_RED");
    // 条件分支：检查 unpack_last !== ((unpack_remaining<=unpack_group_elems) &&。
    if(unpack_last !== ((unpack_remaining<=unpack_group_elems) &&
       (unpack_is_b || unpack_remaining<=unpack_boundary)))
      $fatal(1,"CP11_UNPACK_LAST_EQ_RED");
  end
  // The offset register may prefetch an ignored malformed/write response
  // while no unpack vector is live.  It must agree with the tuple whenever
  // the registered vector can be presented to the scratchpad.
  always_ff @(posedge clk) if(!rst && unpack_valid)begin
    // 条件分支：检查 unpack_shift_bytes_q !== unpack_shift_bytes。
    if(unpack_shift_bytes_q !== unpack_shift_bytes)
      $fatal(1,"CP8_UNPACK_OFFSET_EQUIVALENCE_RED");
  end
  // 过程边界：always_ff @(posedge clk) if(!rst && rsp_fire && rsp_owned && !failing &&。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) if(!rst && rsp_fire && rsp_owned && !failing &&
                              !rsp_error_event && !meta_write[rsp_slot])begin
    // 条件分支：检查 !unpack_can_exchange || (spad_write_ready !== 1'b1)。
    if (!unpack_can_exchange || (spad_write_ready !== 1'b1))
      $fatal(1,"NPU200_VALID_READ_OFFSET_PREFETCH_RED");
  end
  // 过程边界：always_ff @(posedge clk) if(!rst && unpack_valid)begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) if(!rst && unpack_valid)begin
    // 条件分支：检查 unpack_count==0 || int'(unpack_count)>MEM_BYTES || unpack_index>=unpack_count。
    if(unpack_count==0 || int'(unpack_count)>MEM_BYTES || unpack_index>=unpack_count)
      $fatal(1,"CP8_UNPACK_STATE_PRECONDITION_RED");
    // 条件分支：检查 unpack_last !== ((unpack_index + unpack_batch) >= unpack_count)。
    if(unpack_last !== ((unpack_index + unpack_batch) >= unpack_count))
      $fatal(1,"CP8_UNPACK_LAST_EQUIVALENCE_RED");
  end
  // 过程边界：always_ff @(posedge clk) if(!rst&&spad_write_valid)begin。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) if(!rst&&spad_write_valid)begin
    // 条件分支：检查 unpack_batch==0 || int'(unpack_batch)>SPAD_VECTOR_ELEMS ||。
    if(unpack_batch==0 || int'(unpack_batch)>SPAD_VECTOR_ELEMS ||
       (unpack_index+unpack_batch)>unpack_count)
      $fatal(1,"CP5_DMA_VECTOR_COUNT_RED");
  end
  // 过程边界：always_ff @(posedge clk) if (!rst && job_active &&。
  // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
  always_ff @(posedge clk) if (!rst && job_active &&
      (job_q.kind === DMA_STORE_C) && !failing &&
      !$isunknown({next_col,next_row,job_q.cols,job_q.rows})) begin
    // 条件分支：检查 (next_col >= job_q.cols) || (next_row >= job_q.rows)。
    if ((next_col >= job_q.cols) || (next_row >= job_q.rows))
      $fatal(1, "NPU_DMA_STORE_FINAL_INDEX_RANGE_RED");
    // 条件分支：检查 store_row_last !== (({1'b0,next_col} + {1'b0,store_step}) >= {1'b0,job_q.cols}) ||。
    if (store_row_last !== (({1'b0,next_col} + {1'b0,store_step}) >= {1'b0,job_q.cols}) ||
        store_job_last !== (store_row_last && ((next_row + 1'b1) >= job_q.rows)))
      $fatal(1, "NPU_DMA_STORE_FINAL_INDEX_EQUIVALENCE_RED");
  end
  // synthesis translate_on
  always_ff @(posedge clk) begin
    // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
    if (rst) begin
      job_active <= 1'b0;
      failing <= 1'b0;
      all_issued <= 1'b0;
      store_source_done <= 1'b0;
      store_pack_valid <= 1'b0;
      store_pack_row_end <= 1'b0;
      store_bytes_seen <= 1'b0;
        store_vector_seen <= 1'b0;
      store_pack_addr <= '0;
      store_pack_data <= '0;
      store_pack_strb <= '0;
      store_bytes_q <= '0;
      job_q <= '0;
      next_row <= '0;
      next_col <= '0;
      job_last_row_q <= '0;
      job_last_col_q <= '0;job_last_vec_col_q <= '0;
      row_base_q <= '0;
      element_addr_q <= '0;
      req_hold_valid <= 1'b0;
      dma_req_write_q <= 1'b0;
      dma_req_addr_q <= '0;
      dma_req_wdata_q <= '0;
      dma_req_wstrb_q <= '0;
      dma_req_id_q <= '0;
      dma_req_slot_q <= '0;
      unpack_valid <= 1'b0;
      unpack_rdata <= '0;
      unpack_is_b <= 1'b0;
      unpack_bank <= 1'b0;
      unpack_row <= '0;
      unpack_col <= '0;
      unpack_byte_off <= '0;
      unpack_count <= '0;
      unpack_elem_bytes <= '0;
      unpack_index <= '0;
      unpack_batch_q <= '0;
      unpack_last_q <= 1'b0;
      unpack_current_col_q <= '0;
      unpack_spad_lane_q <= '0;
      unpack_spad_k_q <= '0;
      job_done <= 1'b0;
      job_error <= 1'b0;
      error_code <= ERR_NONE;
      partial_output <= 1'b0;
      outstanding <= '0;
      owned_count <= '0;
      for (int i = 0; i < SLOT_COUNT; i = i + 1) begin
        meta_valid[i] <= 1'b0;
        meta_accepted[i] <= 1'b0;
        meta_write[i] <= 1'b0;
        meta_is_b[i] <= 1'b0;
        meta_bank[i] <= 1'b0;
        meta_row[i] <= '0;
        meta_col[i] <= '0;
        meta_byte_off[i] <= '0;
        meta_count[i] <= '0;
        meta_elem_bytes[i] <= '0;
      end
    end else begin
      job_done <= 1'b0;
      job_error <= 1'b0;

      // 握手/背压判断：job_valid === 1'b1 && job_ready === 1'b1。
      // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
      if (job_valid === 1'b1 && job_ready === 1'b1) begin
        job_q <= {job_data.kind, job_data.row_stride, job_data.rows,
                  job_data.cols, job_data.elem_bytes, job_data.bank};
        next_row <= '0;
        next_col <= '0;
        job_last_row_q <= job_data.rows - 16'd1;
        job_last_col_q <= job_data.cols - 16'd1;
        job_last_vec_col_q <= job_data.cols - 16'd4;
        row_base_q <= job_data.base;
        element_addr_q <= job_data.base;
        all_issued <= 1'b0;
        store_source_done <= 1'b0;
        store_pack_valid <= 1'b0;
        store_pack_row_end <= 1'b0;
        store_bytes_seen <= 1'b0;
        store_vector_seen <= 1'b0;
        store_pack_addr <= '0;
        store_pack_data <= '0;
        store_pack_strb <= '0;
        store_bytes_q <= '0;
        req_hold_valid <= 1'b0;
        dma_req_write_q <= 1'b0;
        dma_req_wdata_q <= '0;
        dma_req_wstrb_q <= '0;
        unpack_valid <= 1'b0;
        outstanding <= '0;
        owned_count <= '0;
        failing <= 1'b0;
        error_code <= ERR_NONE;
        partial_output <= 1'b0;
        // 条件分支：检查 (((job_data.kind === DMA_LOAD_A) || (job_data.kind === DMA_LOAD_B)) &&。
        if ((((job_data.kind === DMA_LOAD_A) || (job_data.kind === DMA_LOAD_B)) &&
             ((job_data.elem_bytes === 2'd1) || (job_data.elem_bytes === 2'd2)) &&
             (job_data.rows != 0) && (job_data.cols != 0)) ||
            ((job_data.kind === DMA_STORE_C) && (job_data.rows != 0) && (job_data.cols != 0))) begin
          job_active <= 1'b1;
        end else begin
          job_active <= 1'b0;
          job_error <= 1'b1;
          error_code <= ERR_INTERNAL_PROTOCOL;
        end
      // 条件分支：检查 job_active。
      end else if (job_active) begin
        // 条件分支：检查 read_req_make。
        if (read_req_make) begin
          req_hold_valid <= 1'b1;
          dma_req_write_q <= 1'b0;
          dma_req_addr_q <= element_addr & ~(MEM_BYTES - 1);
          dma_req_wdata_q <= '0;
          dma_req_wstrb_q <= '0;
          dma_req_id_q <= SAFE_MEM_ID_W'(allocated_slot);
          dma_req_slot_q <= allocated_slot;
          meta_valid[allocated_slot] <= 1'b1;
          meta_accepted[allocated_slot] <= 1'b0;
          meta_write[allocated_slot] <= 1'b0;
          meta_is_b[allocated_slot] <= (job_q.kind === DMA_LOAD_B);
          meta_bank[allocated_slot] <= job_q.bank;
          meta_row[allocated_slot] <= next_row;
          meta_col[allocated_slot] <= next_col;
          meta_byte_off[allocated_slot] <= element_byte_off;
          meta_count[allocated_slot] <= segment_count;
          meta_elem_bytes[allocated_slot] <= job_q.elem_bytes;
          // 条件分支：检查 read_row_last。
          if (read_row_last) begin
            next_col <= '0;
            row_base_q <= row_base_q + job_q.row_stride;
            element_addr_q <= row_base_q + job_q.row_stride;
            // 条件分支：检查 (next_row + 1'b1) >= job_q.rows。
            if ((next_row + 1'b1) >= job_q.rows)
              all_issued <= 1'b1;
            else
              next_row <= next_row + 1'b1;
          end else begin
            next_col <= next_col + segment_count_16;
            // Non-row-final requests exhaust the usable bytes of this beat.
            // The next address does not depend on cols-left/min arithmetic.
            element_addr_q <= cp12_read_step_address;
          end
        end

        // 条件分支：检查 store_fire。
        if (store_fire) begin
          // 条件分支：检查 !store_input_valid。
          if (!store_input_valid) begin
            failing <= 1'b1;
            error_code <= ERR_INTERNAL_PROTOCOL;
          end else begin
            // 条件分支：检查 !store_bytes_seen。
            if (!store_bytes_seen) begin
              store_bytes_seen <= 1'b1;
              store_bytes_q <= store_elem_bytes;
              store_vector_seen <= store_vector;
            end
            // 条件分支：检查 store_req_make。
            if (store_req_make) begin
              req_hold_valid <= 1'b1;
              dma_req_write_q <= 1'b1;
              dma_req_id_q <= SAFE_MEM_ID_W'(allocated_slot);
              dma_req_slot_q <= allocated_slot;
              meta_valid[allocated_slot] <= 1'b1;
              meta_accepted[allocated_slot] <= 1'b0;
              meta_write[allocated_slot] <= 1'b1;
              meta_is_b[allocated_slot] <= 1'b0;
              meta_bank[allocated_slot] <= 1'b0;
              meta_row[allocated_slot] <= '0;
              meta_col[allocated_slot] <= '0;
              meta_byte_off[allocated_slot] <= '0;
              meta_count[allocated_slot] <= '0;
              meta_elem_bytes[allocated_slot] <= '0;
              // 条件分支：检查 store_pack_valid && !store_same_beat。
              if (store_pack_valid && !store_same_beat) begin
                dma_req_addr_q <= store_pack_addr;
                dma_req_wdata_q <= store_pack_data;
                dma_req_wstrb_q <= store_pack_strb;
                store_pack_valid <= 1'b1;
                store_pack_row_end <= store_row_last;
                store_pack_addr <= store_elem_beat;
                store_pack_data <= merge_store_data('0, store_elem_data,
                                                     store_elem_byte_off, store_elem_bytes);
                store_pack_strb <= merge_store_strb('0, store_elem_byte_off, store_elem_bytes);
              end else begin
                dma_req_addr_q <= store_pack_valid ? store_pack_addr : store_elem_beat;
                dma_req_wdata_q <= store_merged_data;
                dma_req_wstrb_q <= store_merged_strb;
                store_pack_valid <= 1'b0;
                store_pack_row_end <= 1'b0;
              end
            end else begin
              store_pack_valid <= 1'b1;
              store_pack_row_end <= 1'b0;
              store_pack_addr <= store_elem_beat;
              store_pack_data <= store_merged_data;
              store_pack_strb <= store_merged_strb;
            end
            // 条件分支：检查 store_row_last。
            if (store_row_last) begin
              next_col <= '0;
              row_base_q <= row_base_q + job_q.row_stride;
              element_addr_q <= row_base_q + job_q.row_stride;
              // 条件分支：检查 store_job_last。
              if (store_job_last) store_source_done <= 1'b1;
              else next_row <= next_row + 1'b1;
            end else begin
              next_col <= next_col + store_step;
              element_addr_q <= element_addr_q + (store_vector?32'd16:32'(store_elem_bytes));
            end
          end
        end

        // The final source element can force the previous beat out while
        // becoming the first (and only) element of a new beat. Once that
        // prior request transfers, flush this retained terminal beat without
        // waiting for a non-existent next source element.
        if (store_tail_make) begin
          req_hold_valid <= 1'b1;
          dma_req_write_q <= 1'b1;
          dma_req_addr_q <= store_pack_addr;
          dma_req_wdata_q <= store_pack_data;
          dma_req_wstrb_q <= store_pack_strb;
          dma_req_id_q <= SAFE_MEM_ID_W'(allocated_slot);
          dma_req_slot_q <= allocated_slot;
          meta_valid[allocated_slot] <= 1'b1;
          meta_accepted[allocated_slot] <= 1'b0;
          meta_write[allocated_slot] <= 1'b1;
          meta_is_b[allocated_slot] <= 1'b0;
          meta_bank[allocated_slot] <= 1'b0;
          meta_row[allocated_slot] <= '0;
          meta_col[allocated_slot] <= '0;
          meta_byte_off[allocated_slot] <= '0;
          meta_count[allocated_slot] <= '0;
          meta_elem_bytes[allocated_slot] <= '0;
          store_pack_valid <= 1'b0;
          store_pack_row_end <= 1'b0;
        end

        // 条件分支：检查 req_fire。
        if (req_fire) begin
          // The OLD tuple has transferred. A freshly reserved read above
          // replaces it atomically; otherwise this holding register empties.
          // Allocator never allocates the currently-owned old slot.
          if (!read_req_make && !store_req_make && !store_tail_make) req_hold_valid <= 1'b0;
          meta_accepted[dma_req_slot_q] <= 1'b1;
          // 条件分支：检查 dma_req_write_q。
          if (dma_req_write_q) partial_output <= 1'b1;
        end

        // Retire the OLD registered vector first. A successful response below
        // may atomically replace it in this edge; replacement owns valid/index.
        if (spad_fire) begin
          // 条件分支：检查 unpack_last。
          if (unpack_last)
            unpack_valid <= 1'b0;
          else begin
            unpack_index <= unpack_index + unpack_batch;
            unpack_batch_q <= cp11_batch(unpack_count,unpack_index+unpack_batch,unpack_col,unpack_is_b,unpack_elem_bytes);
            unpack_last_q <= (BATCH_W'(unpack_count)-BATCH_W'(unpack_index+unpack_batch)) ==
                BATCH_W'(cp11_batch(unpack_count,unpack_index+unpack_batch,unpack_col,unpack_is_b,unpack_elem_bytes));
            unpack_current_col_q <= unpack_current_col_q + 16'(unpack_batch);
            // 条件分支：检查 unpack_is_b。
            if (unpack_is_b)
              unpack_spad_lane_q <= unpack_spad_lane_q + LANE_W'(unpack_batch);
            else
              unpack_spad_k_q <= unpack_spad_k_q + K_W'(unpack_batch);
          end
        end
        // 条件分支：检查 rsp_fire。
        if (rsp_fire) begin
          // 条件分支：检查 rsp_owned。
          if (rsp_owned) begin
            meta_valid[rsp_slot] <= 1'b0;
            meta_accepted[rsp_slot] <= 1'b0;
          end
        end
        if (read_capture_fire) begin
          unpack_valid <= 1'b1;
          unpack_rdata <= rsp_q_rdata;
          unpack_is_b <= meta_is_b[rsp_slot];
          unpack_bank <= meta_bank[rsp_slot];
          unpack_row <= meta_row[rsp_slot];
          unpack_col <= meta_col[rsp_slot];
          unpack_byte_off <= meta_byte_off[rsp_slot];
          unpack_count <= meta_count[rsp_slot];
          unpack_elem_bytes <= meta_elem_bytes[rsp_slot];
          unpack_index <= '0;
          unpack_batch_q <= cp11_batch(meta_count[rsp_slot],'0,meta_col[rsp_slot],meta_is_b[rsp_slot],meta_elem_bytes[rsp_slot]);
          unpack_last_q <= meta_count[rsp_slot] ==
              cp11_batch(meta_count[rsp_slot],'0,meta_col[rsp_slot],meta_is_b[rsp_slot],meta_elem_bytes[rsp_slot]);
          unpack_current_col_q <= meta_col[rsp_slot];
          unpack_spad_lane_q <= LANE_W'(meta_is_b[rsp_slot] ?
                                         meta_col[rsp_slot] : meta_row[rsp_slot]);
          unpack_spad_k_q <= K_W'(meta_is_b[rsp_slot] ?
                                   meta_row[rsp_slot] : meta_col[rsp_slot]);
        end

        // Current-cycle response faults outrank timeout and success.  The
        // response is still consumed above so its ID cannot leak ownership.
        if (!failing && rsp_error_event) begin
          failing <= 1'b1;
          error_code <= (rsp_owned && (rsp_q_error === 1'b1)) ?
                        // 状态/选择分支 ERR_DMA_RESPONSE ：本分支规定该编码下的寄存器更新和下一步动作。
                        ERR_DMA_RESPONSE : ERR_INTERNAL_PROTOCOL;
        end else if (!failing && allocator_protocol_error) begin
          failing <= 1'b1;
          error_code <= ERR_INTERNAL_PROTOCOL;
        end else if (!failing && timeout_event) begin
          failing <= 1'b1;
          error_code <= ERR_DMA_TIMEOUT;
        end
        if (!failing && !rsp_error_event && !allocator_protocol_error && !timeout_event && store_fault_event) begin
          failing <= 1'b1;
          error_code <= ERR_INTERNAL_PROTOCOL;
        end
        if (failing || rsp_error_event || allocator_protocol_error || timeout_event)
          store_pack_valid <= 1'b0;
        if (failing || rsp_error_event || allocator_protocol_error || timeout_event)
          store_pack_row_end <= 1'b0;


        // 按 {req_fire, rsp_owned_fire} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
        case ({req_fire, rsp_owned_fire})
          2'b10: outstanding <= outstanding + 1'b1;
          2'b01: outstanding <= outstanding - 1'b1;
          default: outstanding <= outstanding;
        endcase

        // 按 {req_reserve, rsp_owned_fire} 选择控制分支；遗漏编码需结合默认赋值和 default 检查。
        case ({req_reserve, rsp_owned_fire})
          2'b10: owned_count <= owned_count + 1'b1;
          2'b01: owned_count <= owned_count - 1'b1;
          default: owned_count <= owned_count;
        endcase

        // CP9 counter leaf maintains the exact original logical count.

        // Completion is deliberately one edge after the final state change;
        // all logical writes, held request state, and accepted traffic are gone.
        if (failure_transition) begin
          job_active <= 1'b0;
          job_error <= 1'b1;
        end else if (success_transition && !timeout_event) begin
          job_active <= 1'b0;
          job_done <= 1'b1;
        end
      end
    end
  end
endmodule
