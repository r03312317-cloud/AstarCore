module npu_scheduler #(
  parameter int ARRAY_ROWS = 4,
  parameter int ARRAY_COLS = 4,
  parameter int K_TILE = 32,
  parameter int ACC_W = 48,
  parameter bit RESULT_PAGE_STORE = 1'b0,
  parameter bit STORE_VECTOR4_ENABLE=1'b0,
  parameter bit RESIDENT_FULL_K_ENABLE = 1'b1,
  parameter bit RESIDENT_GROUP_REUSE_ENABLE = 1'b1,
  // 256 preserves the serial full-page path. Smaller aligned chunks may
  // overlap Store with the next resident N8 groups of the SAME command.
  parameter int RESULT_CHUNK_COLUMNS = 256,
  parameter logic [31:0] DRAM_BASE = 32'h8010_0000,
  parameter logic [32:0] DRAM_BYTES = 33'h00004_0000
) (
  input  logic clk,
  input  logic rst,
  input logic result_page_enable,
  // Sampled with cmd_valid/cmd_ready. Only the resident adapter may assert.
  input logic resident_compute_mode,
  input logic resident_operands_ready,
  output logic [10:0] resident_read_k,
  input logic [127:0] result_context,
  input logic [4:0] result_dma_outstanding,
  input logic result_order_idle,result_order_poison,
  output logic result_array_read_enable,
  output logic [((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1)-1:0] result_array_read_row,
  input logic [ARRAY_COLS*ACC_W-1:0] result_array_row_data,
  output logic result_protocol_error,

  input  logic cmd_valid,
  output logic cmd_ready,
  input  npu_defs_pkg::npu_cmd_t cmd_data,
  output logic reserve_valid,
  input  logic reserve_ready,
  output logic completion_valid,
  input  logic completion_ready,
  output npu_defs_pkg::npu_completion_t completion_data,

  output logic dma_job_valid,
  input  logic dma_job_ready,
  output npu_defs_pkg::npu_dma_job_t dma_job_data,
  input  logic dma_job_done,
  input  logic dma_job_error,
  input  npu_defs_pkg::npu_error_e dma_error_code,
  input  logic dma_partial_output,

  output logic spad_owner_valid,
  output logic spad_owner_is_b,
  output logic spad_owner_bank,
  output logic [1:0] spad_owner_state,
  input  logic [3:0] spad_a_owner,
  input  logic [3:0] spad_b_owner,
  input  logic spad_protocol_error,
  output logic spad_compute_read_valid,
  output logic spad_compute_bank,
  output logic [((K_TILE > 1) ? $clog2(K_TILE) : 1)-1:0] spad_compute_k,
  input  logic spad_compute_read_data_valid,
  input  logic signed [ARRAY_ROWS*16-1:0] spad_a_vector,
  input  logic signed [ARRAY_COLS*16-1:0] spad_b_vector,

  output logic array_start_valid,
  input  logic array_start_ready,
  output logic [15:0] array_k_len,
  output logic [ARRAY_ROWS-1:0] array_row_mask,
  output logic [ARRAY_COLS-1:0] array_col_mask,
  output logic array_continue_acc,
  output logic array_input_int16,
  output logic array_feed_valid,
  input  logic array_feed_ready,
  output logic signed [ARRAY_ROWS*16-1:0] array_feed_a,
  output logic signed [ARRAY_COLS*16-1:0] array_feed_b,
  input  logic array_done,
  output logic [((ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1)-1:0] array_acc_read_row,
  output logic [((ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1)-1:0] array_acc_read_col,
  input  logic signed [ACC_W-1:0] array_acc_rdata,

  output logic post_in_valid,
  input  logic post_in_ready,
  output logic signed [ACC_W-1:0] post_in_value,
  output logic [1:0] post_output_fmt,
  output logic [1:0] post_activation,
  output logic post_rounding,
  output logic [5:0] post_shift,
  output logic signed [31:0] post_clamp_min,
  output logic signed [31:0] post_clamp_max,
  input  logic post_out_valid,
  output logic post_out_ready,
  input  logic signed [31:0] post_out_value,
  input  logic [2:0] post_out_bytes,

  output logic store_elem_vector4,output logic [127:0] store_elem_vector_data,
  output logic store_elem_valid,
  input  logic store_elem_ready,
  output logic signed [31:0] store_elem_data,
  output logic [2:0] store_elem_bytes,
  output logic [15:0] store_elem_row,
  output logic [15:0] store_elem_col,
  output logic [10:0] resident_k_base,
  output logic resident_claim,
  output logic [4:0] resident_n_group,
  output logic active
);
  import npu_defs_pkg::*;
  assign resident_k_base=k0[10:0];
  // Full 11-bit address for resident K<=1152. The legacy K64 SPAD still
  // receives its original low-bit address and is never read in this mode.
  assign resident_read_k=k0[10:0]+11'(read_issue_count);
  assign resident_claim=(state==CLAIM_B)&&spad_owner_valid;
  assign resident_n_group=n0[7:3];

  localparam logic [1:0] OWNER_EMPTY   = 2'd0;
  localparam logic [1:0] OWNER_FILLING = 2'd1;
  localparam logic [1:0] OWNER_READY   = 2'd2;
  localparam logic [1:0] OWNER_COMPUTE = 2'd3;
  localparam int K_W = (K_TILE > 1) ? $clog2(K_TILE) : 1;
  localparam int EXEC_COUNT_W = RESIDENT_FULL_K_ENABLE ? ((K_W+1>11)?K_W+1:11) : K_W+1;
  localparam int ROW_W = (ARRAY_ROWS > 1) ? $clog2(ARRAY_ROWS) : 1;
  localparam int COL_W = (ARRAY_COLS > 1) ? $clog2(ARRAY_COLS) : 1;
  localparam int CELL_W = $clog2(ARRAY_ROWS * ARRAY_COLS + 1);
  localparam logic [15:0] ARRAY_ROWS_COUNT = 16'(ARRAY_ROWS);
  localparam logic [15:0] ARRAY_COLS_COUNT = 16'(ARRAY_COLS);
  localparam logic [15:0] K_TILE_COUNT = 16'(K_TILE);
  localparam logic [6:0] ACC_W_COUNT = 7'(ACC_W);

  typedef enum logic [4:0] {
    IDLE, VALIDATE_MUL, VALIDATE_PRODUCT_SUM, VALIDATE_ADDR, VALIDATE_DECIDE,
    LAUNCH_LOAD, WAIT_FIRST_LOAD,
    CLAIM_A, CLAIM_B, START_ARRAY, COMPUTE,
    RELEASE_A, RELEASE_B, STORE_PREP, STORE_ISSUE,
    DRAIN_ACC, ABORT_ARRAY, ERROR_CLEAN, COMPLETE,
    PAGE_BEGIN, PAGE_CAPTURE_START, PAGE_CAPTURE_WAIT, PAGE_COMMIT,
    PAGE_STORE_START, PAGE_STORE_WAIT,
    REUSE_FILL_A, REUSE_FILL_B, REUSE_READY_A, REUSE_READY_B
  } state_e;
  typedef enum logic [3:0] {
    LOAD_IDLE, LOAD_FILL_A, LOAD_FILL_B, LOAD_SELECT, LOAD_ISSUE,
    LOAD_WAIT, LOAD_READY_OWNER, LOAD_DONE, LOAD_ERROR
  } load_state_e;
  state_e state;
  load_state_e load_state;
  npu_cmd_t cmd_q;
  npu_completion_t completion_q;
  npu_dma_job_t load_job_q, store_job_q;
  npu_error_e validation_error;
  npu_error_e pending_error;
  logic [31:0] cycle_count;
  logic [2:0] input_bytes, output_bytes;
  logic [64:0] a_row_bytes_q, b_row_bytes_q, c_row_bytes_q;
  logic [64:0] a_stride_product_q, b_stride_product_q, c_stride_product_q;
  logic [64:0] a_last_q, b_last_q, c_last_q, dram_limit;
  logic descriptor_known_q;
  logic [63:0] mn_q, macs_q;
  // TC1: registered bounded products. Valid dimensions are 16 bits, strides
  // 32 bits; each partial multiplier is exactly 16x16. Invalid zero dimensions
  // are rejected by the original first-priority ERR_INVALID_DIM check, before
  // any address/alias calculation may authorize DMA.
  logic [15:0] m_prev_q, k_prev_q;
  logic [31:0] a_lo_q, a_hi_q, b_lo_q, b_hi_q, c_lo_q, c_hi_q;
  logic [31:0] mac_lo_q, mac_hi_q;
  logic [31:0] load_a_lo_q, load_a_hi_q, load_b_lo_q, load_b_hi_q;
  logic [31:0] load_a_offset_q, load_b_offset_q;
  logic [31:0] load_a_col_q, load_b_col_q;
  logic [31:0] store_c_lo_q, store_c_hi_q, store_c_offset_q, store_c_col_q;

  function automatic logic [31:0] product16(input logic [15:0] x, y);
    product16 = x * y;
  endfunction
  function automatic logic [47:0] join_product(input logic [31:0] lo, hi);
    join_product = {16'd0,lo} + {hi,16'd0};
  endfunction
  function automatic logic [17:0] element_bytes(
      input logic [15:0] elements, input logic [2:0] bytes_per_element);
    case (bytes_per_element)
      3'd1: element_bytes = {2'd0,elements};
      3'd2: element_bytes = {1'd0,elements,1'd0};
      3'd4: element_bytes = {elements,2'd0};
      default: element_bytes = '0;
    endcase
  endfunction

  logic [15:0] m0, n0, k0;
  logic [15:0] tile_m_len, tile_n_len, tile_k_len;
  logic [15:0] next_tile_k_len;
  logic [15:0] legacy_tile_k_len;
  logic resident_full_k_q;
  logic [16:0] m_after_tile, n_after_tile, k_after_tile;
  logic has_next_k, has_next_output, has_next_m, has_next_n;
  logic compute_bank;
  // Active metadata is captured at CLAIM_B. Legacy K_TILE is <=256;
  // resident execution requires a count for all 1152 committed K elements.
  logic [EXEC_COUNT_W-1:0] read_issue_count, array_feed_accept_count, exec_k_len_q;
  logic [ARRAY_ROWS-1:0] exec_row_mask_q;
  logic [ARRAY_COLS-1:0] exec_col_mask_q;
  logic exec_continue_q, exec_int16_q, exec_has_next_k_q;
  logic feed_q0_valid, feed_q1_valid;
  logic signed [ARRAY_ROWS*16-1:0] feed_a_q0, feed_a_q1;
  logic signed [ARRAY_COLS*16-1:0] feed_b_q0, feed_b_q1;
  logic feed_push, feed_pop;
  logic [2:0] feed_slots_after_edge;
  logic array_done_seen;
  logic runtime_error;
  logic after_release_next_k, error_after_release;

  logic load_launch, load_launch_ready, load_result_ack;
  logic load_bank_q, load_need_a, load_need_b, load_selected_b;
  logic load_last_grant_b;
  logic [15:0] load_m0, load_n0, load_k0;
  logic [15:0] load_m_len, load_n_len, load_k_len;
  npu_error_e load_error_q;

  logic [15:0] drain_issue_row, drain_issue_col;
  logic [15:0] store_out_row_q, store_out_col_q;
  logic wb_q0_valid, wb_q1_valid;
  logic signed [31:0] wb_data_q0, wb_data_q1;
  logic [2:0] wb_bytes_q0, wb_bytes_q1;
  logic [15:0] wb_row_q0, wb_row_q1, wb_col_q0, wb_col_q1;
  logic [31:0] post_in_count, post_out_count, tile_cell_count_q;
  logic [31:0] tile_cell_last_q;
  // The existing LOAD_DONE/RELEASE_B -> CLAIM_A -> CLAIM_B sequence gives
  // three register boundaries without adding a command cycle: clipped
  // dimensions, narrow product, then the final-output comparison operand.
  logic [ROW_W:0] tile_m_len_preq;
  logic [COL_W:0] tile_n_len_preq;
  logic [CELL_W-1:0] tile_cell_count_calc;
  logic [CELL_W-1:0] tile_cell_count_preq;
  logic acc_pending_valid;
  logic [31:0] discard_remaining;
  logic pending_partial_output;
  logic cleanup_all_empty;
  logic cleanup_owner_valid, cleanup_owner_is_b, cleanup_owner_bank;
  logic [1:0] cleanup_owner_state;
  logic post_in_fire, post_out_fire, store_elem_fire;

  // One M16 x bounded-N page per command. The original load engine, K64
  // compute loop and all address/alias validation remain authoritative.
  // N8 groups are captured before a row-major Store through the ONE old DMA.
  // Resident chunks may compute while the preceding chunk is stored. The
  // command still waits for every real B; there is no inter-command overlap.
  logic page_mode_q,page_slot_q;
  logic page_chunked_q,page_warm_q;
  logic [8:0] page_columns_q;
  logic [15:0] page_end_q;
  logic [4:0] page_group_origin_q;
  logic [31:0] page_c_base_q;
  npu_error_e page_failure_q;
  wire resident_candidate=RESIDENT_FULL_K_ENABLE&&(resident_compute_mode===1'b1)&&
      !cmd_data.input_int16&&cmd_data.m>0&&cmd_data.m<=16&&
      cmd_data.n>0&&cmd_data.n<=256&&cmd_data.k>0&&cmd_data.k<=1152;
  wire chunk_candidate=RESULT_CHUNK_COLUMNS<256&&RESIDENT_GROUP_REUSE_ENABLE&&resident_candidate;
  wire [8:0] initial_page_columns=chunk_candidate&&cmd_data.n>16'(RESULT_CHUNK_COLUMNS) ?
      9'(RESULT_CHUNK_COLUMNS):9'(cmd_data.n);
  wire [15:0] page_remaining=cmd_q.n-page_end_q;
  wire [8:0] next_page_columns=page_remaining>16'(RESULT_CHUNK_COLUMNS) ?
      9'(RESULT_CHUNK_COLUMNS):9'(page_remaining);
  wire page_more=page_chunked_q&&page_end_q<cmd_q.n;
  logic [255:0] page_identity_q;
  logic page_bank_ready,page_bank_poison,page_capture_ready,page_capture_busy;
  logic page_capture_done,page_capture_cancelled,page_capture_bad;
  logic page_capture_valid,page_capture_write_ready;
  logic [4:0] page_capture_row,page_capture_group;
  logic [3:0] page_read_row;
  logic [383:0] page_capture_values;
  logic [3:0] page_owners;
  logic page_claim,page_store_slot,page_claim_ready,page_bank_read,page_bank_read_ready;
  logic [255:0] page_bank_identity,page_bank_output;
  logic [4:0] page_bank_row,page_bank_group;
  logic [31:0] page_bank_strobe;
  logic page_bank_valid,page_bank_output_ready,page_release,page_retired,page_failed;
  logic page_store_ready,page_store_busy,page_store_done,page_store_cancelled,page_store_poison;
  logic page_dma_valid,page_dma_ready,page_stream_valid;
  npu_dma_job_t page_dma_job;
  npu_error_e page_store_error;
  logic signed [31:0] page_stream_data;
  logic page_stream_vector4;logic [127:0] page_stream_vector_data;
  logic [2:0] page_stream_bytes;
  logic [15:0] page_stream_row,page_stream_col;
  // Store keeps its exclusive DMA lease while compute uses already committed
  // resident operands. No second DMA, command, or early completion is added.
  wire page_grant=page_store_busy||state==PAGE_STORE_START||state==PAGE_STORE_WAIT;
  wire page_abort=page_mode_q&&state==ERROR_CLEAN&&!page_capture_busy&&
                   !page_capture_valid&&((page_slot_q?page_owners[3:2]:page_owners[1:0])==1);
  wire page_discard=page_mode_q&&state==ERROR_CLEAN&&!page_capture_busy&&!page_store_busy&&
                   ((page_slot_q?page_owners[3:2]:page_owners[1:0])==2);
  wire page_cleanup_idle=!page_mode_q||
       (page_owners==0&&!page_capture_busy&&!page_store_busy&&!page_bank_valid);
  wire page_return_error=page_store_done&&(page_store_error!=ERR_NONE||page_store_cancelled);
  wire page_capture_cancel=runtime_error||spad_protocol_error||page_return_error;
  assign result_protocol_error=page_bank_poison||page_store_poison||page_capture_bad;
  assign result_array_read_row=ROW_W'(page_read_row);
  assign page_dma_ready=page_grant&&dma_job_ready;
  generate if(RESULT_PAGE_STORE)begin:g_result_page
    npu_result_rows #(.BANK_ROWS(16),.BANK_COLUMNS(256)) bank(
      .clk,.rst,.write_begin(state==PAGE_BEGIN&&page_bank_ready&&!page_capture_cancel&&
                            (!page_warm_q||resident_operands_ready)),
      .write_slot(page_slot_q),.write_identity(page_identity_q),.rows(6'(cmd_q.m)),.columns(page_columns_q),
      .write_begin_ready(page_bank_ready),.write_valid(page_capture_valid),.write_row(page_capture_row),
      .write_group(page_capture_group),.write_ACC48(page_capture_values),.write_ready(page_capture_write_ready),
      .write_commit(state==PAGE_COMMIT&&!page_capture_cancel),.write_abort(page_abort),
      .store_claim(page_claim),.store_slot(page_discard?page_slot_q:page_store_slot),
      .expected_identity(page_discard?page_identity_q:page_bank_identity),.store_claim_ready(page_claim_ready),
      .read_valid(page_bank_read),.read_row(page_bank_row),.read_group(page_bank_group),.read_ready(page_bank_read_ready),
      .output_valid(page_bank_valid),.output_ready(page_bank_output_ready),.output_INT32(page_bank_output),.output_strobe(page_bank_strobe),
      .store_release(page_release),.real_B_retired(page_retired),.store_failed(page_failed),.discard_ready(page_discard),
      .owners(page_owners),.protocol_poison(page_bank_poison),.captured_rows(),.consumed_groups());
    npu_row_result_capture capture(
      .clk,.rst,.start_valid(state==PAGE_CAPTURE_START&&!page_capture_cancel),.start_ready(page_capture_ready),
      .tile_rows(5'(tile_m_len)),.row_base(5'd0),.channel_group(n0[7:3]-page_group_origin_q),.cancel(page_capture_cancel),
      .array_read_enable(result_array_read_enable),.array_read_row(page_read_row),.array_row_ACC48(result_array_row_data),
      .write_valid(page_capture_valid),.write_ready(page_capture_write_ready),.write_row(page_capture_row),
      .write_group(page_capture_group),.write_ACC48(page_capture_values),.busy(page_capture_busy),.done_pulse(page_capture_done),
      .cancelled(page_capture_cancelled),.bad_start(page_capture_bad),.rows_captured());
    npu_result_store_bridge #(.MAX_COLUMNS(256),.VECTOR4_ENABLE(STORE_VECTOR4_ENABLE)) store_bridge(
      .clk,.rst,.start_valid(state==PAGE_STORE_START&&!page_capture_cancel),.start_ready(page_store_ready),
      .start_slot(page_slot_q),.start_identity(page_identity_q),.start_rows(5'(cmd_q.m)),.start_columns(page_columns_q),
      .start_base(page_c_base_q),.start_stride(cmd_q.c_stride),.cancel(1'b0),.DMA_exclusive_grant(page_grant),
      .bank_claim(page_claim),.bank_slot(page_store_slot),.bank_identity(page_bank_identity),.bank_claim_ready(page_claim_ready),
      .bank_read_valid(page_bank_read),.bank_read_row(page_bank_row),.bank_read_group(page_bank_group),.bank_read_ready(page_bank_read_ready),
      .bank_output_valid(page_bank_valid),.bank_output_ready(page_bank_output_ready),.bank_output_INT32(page_bank_output),.bank_output_strobe(page_bank_strobe),
      .bank_release(page_release),.bank_real_B_retired(page_retired),.bank_store_failed(page_failed),.bank_poison(page_bank_poison),
      .dma_job_valid(page_dma_valid),.dma_job_ready(page_dma_ready),.dma_job(page_dma_job),
      .dma_job_done(page_grant&&dma_job_done),.dma_job_error(page_grant&&dma_job_error),.dma_error_code,
      .dma_outstanding(result_dma_outstanding),.response_order_idle(result_order_idle),.response_order_poison(result_order_poison),
      .store_elem_vector4(page_stream_vector4),.store_elem_vector_data(page_stream_vector_data),
      .store_elem_valid(page_stream_valid),.store_elem_ready(store_elem_ready&&page_grant),.store_elem_data(page_stream_data),
      .store_elem_bytes(page_stream_bytes),.store_elem_row(page_stream_row),.store_elem_col(page_stream_col),
      .busy(page_store_busy),.done(page_store_done),.cancelled(page_store_cancelled),.protocol_poison(page_store_poison),.error_code(page_store_error),
      .streamed_elements(),.stream_stall_cycles(),.real_retire_wait_cycles());
  end else begin:g_no_result_page
    assign page_bank_ready=1'b0;assign page_bank_poison=1'b0;assign page_owners=0;
    assign page_capture_ready=1'b0;assign page_capture_busy=1'b0;assign page_capture_done=1'b0;
    assign page_capture_cancelled=1'b0;assign page_capture_bad=1'b0;assign page_capture_valid=1'b0;
    assign page_capture_row=0;assign page_capture_group=0;assign page_capture_values=0;
    assign page_read_row=0;assign result_array_read_enable=1'b0;assign page_bank_valid=1'b0;
    assign page_store_ready=1'b0;assign page_store_busy=1'b0;assign page_store_done=1'b0;
    assign page_store_poison=1'b0;assign page_store_cancelled=1'b0;assign page_dma_valid=1'b0;assign page_dma_job='0;
    assign page_store_error=ERR_NONE;assign page_stream_valid=1'b0;assign page_stream_data=0;
    assign page_stream_vector4=1'b0;assign page_stream_vector_data='0;
    assign page_stream_bytes=0;assign page_stream_row=0;assign page_stream_col=0;
  end endgenerate

  function automatic logic [ARRAY_ROWS-1:0] make_row_mask(input logic [15:0] length);
    begin
      make_row_mask = '0;
      for (int row_index = 0; row_index < ARRAY_ROWS; row_index = row_index + 1)
        if (row_index < length) make_row_mask[row_index] = 1'b1;
    end
  endfunction

  function automatic logic [ARRAY_COLS-1:0] make_col_mask(input logic [15:0] length);
    begin
      make_col_mask = '0;
      for (int col_index = 0; col_index < ARRAY_COLS; col_index = col_index + 1)
        if (col_index < length) make_col_mask[col_index] = 1'b1;
    end
  endfunction

  function automatic logic known_word32(input logic [31:0] value);
    begin
      known_word32 = ((^value) !== 1'bx);
    end
  endfunction

  function automatic logic [31:0] increment_saturating(input logic [31:0] value);
    begin
      increment_saturating = (&value) ? value : value + 1'b1;
    end
  endfunction

  always @* begin
    input_bytes = cmd_q.input_int16 ? 3'd2 : 3'd1;
    case (cmd_q.output_fmt)
      2'd0: output_bytes = 3'd1;
      2'd1: output_bytes = 3'd2;
      2'd2: output_bytes = 3'd4;
      default: output_bytes = 3'd0;
    endcase

    dram_limit = {33'd0, DRAM_BASE} + {32'd0, DRAM_BYTES};

    // cmd_q is the acceptance snapshot, stable through all validation
    // stages. Keep the architectural priority chain unchanged; every wide
    // arithmetic endpoint below is registered before the DECIDE edge.
    validation_error = ERR_NONE;
    if (((^cmd_q.m) === 1'bx) || ((^cmd_q.n) === 1'bx) ||
        ((^cmd_q.k) === 1'bx) || (cmd_q.m == 0) ||
        (cmd_q.n == 0) || (cmd_q.k == 0)) begin
      validation_error = ERR_INVALID_DIM;
    end else if (((cmd_q.input_int16 !== 1'b0) &&
                  (cmd_q.input_int16 !== 1'b1)) ||
                 !((cmd_q.output_fmt === 2'd0) ||
                   (cmd_q.output_fmt === 2'd1) ||
                   (cmd_q.output_fmt === 2'd2)) ||
                 !((cmd_q.activation === 2'd0) ||
                   (cmd_q.activation === 2'd1) ||
                   (cmd_q.activation === 2'd2)) ||
                 ((cmd_q.rounding !== 1'b0) &&
                  (cmd_q.rounding !== 1'b1)) ||
                 ((^cmd_q.shift) === 1'bx) ||
                 ({1'b0, cmd_q.shift} >= ACC_W_COUNT)) begin
      validation_error = ERR_BAD_PRECISION;
    end else if ((cmd_q.input_int16 &&
                  (cmd_q.a_base[0] || cmd_q.b_base[0] ||
                   cmd_q.a_stride[0] || cmd_q.b_stride[0])) ||
                 ((output_bytes == 3'd2) &&
                  (cmd_q.c_base[0] || cmd_q.c_stride[0])) ||
                 ((output_bytes == 3'd4) &&
                  ((cmd_q.c_base[1:0] != 2'b00) ||
                   (cmd_q.c_stride[1:0] != 2'b00)))) begin
      validation_error = ERR_MISALIGNED;
    end else if (({33'd0, cmd_q.a_stride} < a_row_bytes_q) ||
                 ({33'd0, cmd_q.b_stride} < b_row_bytes_q) ||
                 ({33'd0, cmd_q.c_stride} < c_row_bytes_q)) begin
      validation_error = ERR_BAD_STRIDE;
    end else if ((cmd_q.activation === 2'd2) &&
                 (((^cmd_q.clamp_min) === 1'bx) ||
                  ((^cmd_q.clamp_max) === 1'bx) ||
                  ($signed(cmd_q.clamp_min) > $signed(cmd_q.clamp_max)))) begin
      validation_error = ERR_BAD_PRECISION;
    end else if (!descriptor_known_q ||
                 ({33'd0, cmd_q.a_base} < {33'd0, DRAM_BASE}) ||
                 ({33'd0, cmd_q.b_base} < {33'd0, DRAM_BASE}) ||
                 ({33'd0, cmd_q.c_base} < {33'd0, DRAM_BASE}) ||
                 (|a_last_q[64:32]) || (|b_last_q[64:32]) ||
                 (|c_last_q[64:32]) ||
                 (a_last_q >= dram_limit) || (b_last_q >= dram_limit) ||
                 (c_last_q >= dram_limit)) begin
      validation_error = ERR_ADDRESS_RANGE;
    end else if ((({33'd0, cmd_q.c_base} <= a_last_q) &&
                  ({33'd0, cmd_q.a_base} <= c_last_q)) ||
                 (({33'd0, cmd_q.c_base} <= b_last_q) &&
                  ({33'd0, cmd_q.b_base} <= c_last_q))) begin
      validation_error = ERR_ADDRESS_ALIAS;
    end
  end

  cp13_k_lengths #(.K_TILE(K_TILE)) cp13_lengths(
    .k(cmd_q.k),.k0(k0),.current_len(legacy_tile_k_len),.next_len(next_tile_k_len)
  );
  // Resident A and B are fully committed before CLAIM. Continuous K
  // avoids drain/claim/restart at every legacy K_TILE boundary. There is
  // still one array, one DMA, identical MAC order and final Store fence.
  assign tile_k_len=resident_full_k_q ? cmd_q.k : legacy_tile_k_len;
  assign tile_cell_count_calc =
      CELL_W'(tile_m_len_preq) * CELL_W'(tile_n_len_preq);
  always @* begin
    tile_m_len = cmd_q.m - m0;
    if (tile_m_len > ARRAY_ROWS_COUNT) tile_m_len = ARRAY_ROWS_COUNT;
    // CP8: expose the proven post-clamp width to synthesis. Retain the full
    // 16-bit subtraction/comparison above, including wrap behavior; narrow
    // only AFTER clipping. The extra bit preserves an exact full tile.
    tile_m_len = 16'((ROW_W+1)'(tile_m_len));
    tile_n_len = cmd_q.n - n0;
    if (tile_n_len > ARRAY_COLS_COUNT) tile_n_len = ARRAY_COLS_COUNT;
    tile_n_len = 16'((COL_W+1)'(tile_n_len));
    m_after_tile = {1'b0, m0} + {1'b0, tile_m_len};
    n_after_tile = {1'b0, n0} + {1'b0, tile_n_len};
    k_after_tile = {1'b0, k0} + {1'b0, tile_k_len};
    // CP8: termination does not depend on the clipped tile length. For
    // unsigned origin/dimension/capacity, origin+min(dim-origin,capacity)
    // is below dim iff origin+capacity is below dim (extend before adding).
    // Constants are early; cmd dimensions no longer traverse min/add/compare.
    // Actual tile lengths, addresses, state boundaries and latency stay intact.
    has_next_m = (({1'b0, m0} + {1'b0, ARRAY_ROWS_COUNT}) < {1'b0, cmd_q.m});
    has_next_n = (({1'b0, n0} + {1'b0, ARRAY_COLS_COUNT}) < {1'b0, cmd_q.n});
    has_next_k = !resident_full_k_q && (({1'b0, k0} + {1'b0, K_TILE_COUNT}) < {1'b0, cmd_q.k});
    has_next_output = has_next_n || has_next_m;

    cleanup_owner_valid = 1'b0;
    cleanup_owner_is_b = 1'b0;
    cleanup_owner_bank = 1'b0;
    cleanup_owner_state = OWNER_EMPTY;
    if (spad_a_owner[1:0] != OWNER_EMPTY) begin
      cleanup_owner_valid = 1'b1;
      cleanup_owner_is_b = 1'b0;
      cleanup_owner_bank = 1'b0;
      case (spad_a_owner[1:0])
        OWNER_FILLING: cleanup_owner_state = OWNER_READY;
        OWNER_READY: cleanup_owner_state = OWNER_COMPUTE;
        default: cleanup_owner_state = OWNER_EMPTY;
      endcase
    end else if (spad_a_owner[3:2] != OWNER_EMPTY) begin
      cleanup_owner_valid = 1'b1;
      cleanup_owner_is_b = 1'b0;
      cleanup_owner_bank = 1'b1;
      case (spad_a_owner[3:2])
        OWNER_FILLING: cleanup_owner_state = OWNER_READY;
        OWNER_READY: cleanup_owner_state = OWNER_COMPUTE;
        default: cleanup_owner_state = OWNER_EMPTY;
      endcase
    end else if (spad_b_owner[1:0] != OWNER_EMPTY) begin
      cleanup_owner_valid = 1'b1;
      cleanup_owner_is_b = 1'b1;
      cleanup_owner_bank = 1'b0;
      case (spad_b_owner[1:0])
        OWNER_FILLING: cleanup_owner_state = OWNER_READY;
        OWNER_READY: cleanup_owner_state = OWNER_COMPUTE;
        default: cleanup_owner_state = OWNER_EMPTY;
      endcase
    end else if (spad_b_owner[3:2] != OWNER_EMPTY) begin
      cleanup_owner_valid = 1'b1;
      cleanup_owner_is_b = 1'b1;
      cleanup_owner_bank = 1'b1;
      case (spad_b_owner[3:2])
        OWNER_FILLING: cleanup_owner_state = OWNER_READY;
        OWNER_READY: cleanup_owner_state = OWNER_COMPUTE;
        default: cleanup_owner_state = OWNER_EMPTY;
      endcase
    end
    cleanup_all_empty = !cleanup_owner_valid;

    load_launch_ready = (load_state == LOAD_IDLE);
    load_launch = !runtime_error && !spad_protocol_error &&
                  ((state == LAUNCH_LOAD) ||
                  ((state == START_ARRAY) && array_start_ready &&
                   exec_has_next_k_q && load_launch_ready));
    load_result_ack = ((state == WAIT_FIRST_LOAD) &&
                       ((load_state == LOAD_DONE) || (load_state == LOAD_ERROR))) ||
                      ((state == COMPUTE) && (array_done_seen || array_done) &&
                       has_next_k &&
                       ((load_state == LOAD_DONE) || (load_state == LOAD_ERROR))) ||
                      ((state == ERROR_CLEAN) &&
                       ((load_state == LOAD_DONE) || (load_state == LOAD_ERROR)));
  end

  always @* begin
    cmd_ready = !rst && (state == IDLE) && reserve_ready;
    reserve_valid = !rst && (state == IDLE) && cmd_valid;
    completion_valid = (state == COMPLETE);
    completion_data = completion_q;

    dma_job_valid = 1'b0;
    dma_job_data = '0;
    if ((load_state == LOAD_ISSUE) && !runtime_error && !spad_protocol_error) begin
      dma_job_valid = 1'b1;
      dma_job_data = load_job_q;
    end else if ((state == STORE_ISSUE) && !runtime_error && !spad_protocol_error) begin
      dma_job_valid = 1'b1;
      dma_job_data = store_job_q;
    end else if (page_grant) begin
      dma_job_valid = page_dma_valid;
      dma_job_data = page_dma_job;
    end

    spad_owner_valid = 1'b0;
    spad_owner_is_b = 1'b0;
    spad_owner_bank = 1'b0;
    spad_owner_state = OWNER_EMPTY;
    case (load_state)
      LOAD_FILL_A: begin
        spad_owner_valid = 1'b1;
        spad_owner_bank = load_bank_q;
        spad_owner_state = OWNER_FILLING;
      end
      LOAD_FILL_B: begin
        spad_owner_valid = 1'b1;
        spad_owner_is_b = 1'b1;
        spad_owner_bank = load_bank_q;
        spad_owner_state = OWNER_FILLING;
      end
      LOAD_READY_OWNER: begin
        spad_owner_valid = 1'b1;
        spad_owner_is_b = load_selected_b;
        spad_owner_bank = load_bank_q;
        spad_owner_state = OWNER_READY;
      end
      default: begin
        case (state)
          // Virtual SPAD owners still traverse their legal state machine.
          // Physical resident RAM has remained committed since the preceding
          // group. It is claimed afresh at CLAIM_B and never read early.
          REUSE_FILL_A, REUSE_FILL_B, REUSE_READY_A, REUSE_READY_B: begin
            spad_owner_valid = resident_operands_ready;
            spad_owner_bank = compute_bank;
            spad_owner_is_b = (state==REUSE_FILL_B || state==REUSE_READY_B);
            spad_owner_state = (state==REUSE_FILL_A || state==REUSE_FILL_B) ? OWNER_FILLING : OWNER_READY;
          end
          CLAIM_A: begin
            spad_owner_valid = 1'b1;
            spad_owner_bank = compute_bank;
            spad_owner_state = OWNER_COMPUTE;
          end
          CLAIM_B: begin
            spad_owner_valid = 1'b1;
            spad_owner_is_b = 1'b1;
            spad_owner_bank = compute_bank;
            spad_owner_state = OWNER_COMPUTE;
          end
          RELEASE_A: begin
            spad_owner_valid = 1'b1;
            spad_owner_bank = compute_bank;
            spad_owner_state = OWNER_EMPTY;
          end
          RELEASE_B: begin
            spad_owner_valid = 1'b1;
            spad_owner_is_b = 1'b1;
            spad_owner_bank = compute_bank;
            spad_owner_state = OWNER_EMPTY;
          end
          ERROR_CLEAN: begin
            spad_owner_valid = cleanup_owner_valid && (load_state == LOAD_IDLE);
            spad_owner_is_b = cleanup_owner_is_b;
            spad_owner_bank = cleanup_owner_bank;
            spad_owner_state = cleanup_owner_state;
          end
          default: ;
        endcase
      end
    endcase
    if ((state != ERROR_CLEAN) && (state != ABORT_ARRAY) &&
        (runtime_error || spad_protocol_error))
      spad_owner_valid = 1'b0;

    feed_push = (state == COMPUTE) && spad_compute_read_data_valid;
    feed_pop = ((state == COMPUTE) || (state == ABORT_ARRAY)) &&
               feed_q0_valid && array_feed_ready;
    feed_slots_after_edge = {2'd0, feed_q0_valid} +
                            {2'd0, feed_q1_valid} +
                            {2'd0, feed_push} - {2'd0, feed_pop};
    spad_compute_read_valid = (state == COMPUTE) &&
                              !runtime_error && !spad_protocol_error &&
                              (read_issue_count < exec_k_len_q) &&
                              (feed_slots_after_edge < 2);
    spad_compute_bank = compute_bank;
    spad_compute_k = read_issue_count[K_W-1:0];

    array_start_valid = (state == START_ARRAY) && !runtime_error &&
                        !spad_protocol_error &&
                        (!exec_has_next_k_q || load_launch_ready);
    array_k_len = 16'(exec_k_len_q);
    array_row_mask = exec_row_mask_q;
    array_col_mask = exec_col_mask_q;
    array_continue_acc = exec_continue_q;
    array_input_int16 = exec_int16_q;
    array_feed_valid = ((state == COMPUTE) && feed_q0_valid) ||
                       ((state == ABORT_ARRAY) &&
                        (array_feed_accept_count < exec_k_len_q));
    array_feed_a = ((state == ABORT_ARRAY) && !feed_q0_valid) ? '0 : feed_a_q0;
    array_feed_b = ((state == ABORT_ARRAY) && !feed_q0_valid) ? '0 : feed_b_q0;
    array_acc_read_row = drain_issue_row[ROW_W-1:0];
    array_acc_read_col = drain_issue_col[COL_W-1:0];

    post_in_valid = (state == DRAIN_ACC) && acc_pending_valid && !dma_job_error;
    post_in_value = array_acc_rdata;
    post_output_fmt = cmd_q.output_fmt;
    post_activation = cmd_q.activation;
    post_rounding = cmd_q.rounding;
    post_shift = cmd_q.shift;
    post_clamp_min = cmd_q.clamp_min;
    post_clamp_max = cmd_q.clamp_max;
    post_out_ready = 1'b0;
    if (state == DRAIN_ACC)
      post_out_ready = !wb_q1_valid && !dma_job_error;
    else if ((state == ERROR_CLEAN) && (discard_remaining != 0))
      post_out_ready = 1'b1;

    store_elem_vector4=1'b0;store_elem_vector_data='0;
    store_elem_valid = 1'b0;
    if ((state == DRAIN_ACC) && !dma_job_error)
      store_elem_valid = wb_q0_valid;
    store_elem_data = wb_data_q0;
    store_elem_bytes = wb_bytes_q0;
    store_elem_row = wb_row_q0;
    store_elem_col = wb_col_q0;
    if(page_grant)begin
      store_elem_vector4=page_stream_vector4;store_elem_vector_data=page_stream_vector_data;
      store_elem_valid=page_stream_valid;
      store_elem_data=page_stream_data;
      store_elem_bytes=page_stream_bytes;
      store_elem_row=page_stream_row;
      store_elem_col=page_stream_col;
    end
    active = (state != IDLE);
  end

  assign post_in_fire = post_in_valid && post_in_ready;
  assign post_out_fire = post_out_valid && post_out_ready;
  // CP8: distribute the final output-count comparison across the late fire
  // select. All arithmetic remains modulo 2^32, including target==0 wrap.
  // This cuts ready -> variable increment -> equality from the error/complete
  // control cone, without narrowing counters or altering state/handshakes.
  // Only DRAIN_ACC consumes these counters.  Keeping ERROR_CLEAN's discard
  // handshake out of this cone prevents its remaining-count/ready feedback
  // from traversing the DRAIN_ACC error-load arithmetic.
  logic post_out_fire_drain;
  assign post_out_fire_drain = (state == DRAIN_ACC) && post_out_valid &&
                               !wb_q1_valid && !dma_job_error;
  logic post_count_complete;
  assign post_count_complete = post_out_fire_drain ?
      (post_out_count == tile_cell_last_q) :
      (post_out_count == tile_cell_count_q);
  // CP8: full-width pending-count arithmetic before the late handshake mux.
  // Preserve modulo-2^32 behavior, including erroneous counter combinations.
  // CP8_DISCARD_SELECT_BEGIN
  logic [31:0] post_pending_base, post_pending_after_fire;
  assign post_pending_base = post_in_count - post_out_count;
  always_comb begin
    case ({post_in_fire, post_out_fire_drain})
      2'b10: post_pending_after_fire = post_pending_base + 32'd1;
      2'b01: post_pending_after_fire = post_pending_base - 32'd1;
      default: post_pending_after_fire = post_pending_base;
    endcase
  end
  // CP8_DISCARD_SELECT_END
  // synthesis translate_off
  always_ff @(posedge clk) if(!rst)begin
    if (state == DRAIN_ACC) begin
      if (post_out_fire_drain !== post_out_fire)
        $fatal(1,"CP8_DRAIN_FIRE_EQUIVALENCE_RED");
      if(post_count_complete !== ((post_out_count + (post_out_fire ? 1 : 0)) == tile_cell_count_q))
        $fatal(1,"CP8_POST_COUNT_EQUIVALENCE_RED");
      if(post_pending_after_fire !== (post_in_count + (post_in_fire ? 1 : 0) -
                                      post_out_count - (post_out_fire ? 1 : 0)))
        $fatal(1,"CP8_DISCARD_COUNT_EQUIVALENCE_RED");
    end
  end
  // synthesis translate_on
  assign store_elem_fire = store_elem_valid && store_elem_ready;

  initial begin
    if (ARRAY_ROWS < 2 || ARRAY_ROWS > 16 ||
        ((ARRAY_ROWS & (ARRAY_ROWS - 1)) != 0))
      $fatal(1, "npu_scheduler: ARRAY_ROWS must be a power of two from 2 to 16");
    if (ARRAY_COLS < 2 || ARRAY_COLS > 16 ||
        ((ARRAY_COLS & (ARRAY_COLS - 1)) != 0))
      $fatal(1, "npu_scheduler: ARRAY_COLS must be a power of two from 2 to 16");
    if (K_TILE < 8 || K_TILE > 256 || ((K_TILE & (K_TILE - 1)) != 0))
      $fatal(1, "npu_scheduler: K_TILE must be a power of two from 8 to 256");
    if (ACC_W < 48 || ACC_W > 64)
      $fatal(1, "npu_scheduler: ACC_W must be in [48,64]");
    if ((DRAM_BYTES == 0) ||
        (({33'd0, DRAM_BASE} + {32'd0, DRAM_BYTES}) > 65'h1_0000_0000))
      $fatal(1, "npu_scheduler: DRAM aperture must fit the 32-bit address space");
  end

  // The load controller is independent of compute so the opposite bank can
  // prefetch while the array consumes the current K tile. It owns only compact
  // coordinates; each externally visible DMA payload is registered first.
  always_ff @(posedge clk) begin
    if (rst) begin
      load_state <= LOAD_IDLE;
      load_job_q <= '0;
      load_bank_q <= 1'b0;
      load_need_a <= 1'b0;
      load_need_b <= 1'b0;
      load_selected_b <= 1'b0;
      load_last_grant_b <= 1'b1;
      load_m0 <= '0;
      load_n0 <= '0;
      load_k0 <= '0;
      load_m_len <= '0;
      load_n_len <= '0;
      load_k_len <= '0;
      load_error_q <= ERR_NONE;
      load_a_lo_q <= '0; load_a_hi_q <= '0;
      load_b_lo_q <= '0; load_b_hi_q <= '0;
      load_a_offset_q <= '0; load_b_offset_q <= '0;
      load_a_col_q <= '0; load_b_col_q <= '0;
    end else begin
      case (load_state)
        LOAD_IDLE: begin
          if (load_launch && load_launch_ready) begin
            load_bank_q <= (state == START_ARRAY) ? ~compute_bank : compute_bank;
            load_need_a <= 1'b1;
            load_need_b <= 1'b1;
            load_m0 <= m0;
            load_n0 <= n0;
            load_m_len <= tile_m_len;
            load_n_len <= tile_n_len;
            if (state == START_ARRAY) begin
              load_k0 <= k_after_tile[15:0];
              load_k_len <= next_tile_k_len;
            end else begin
              load_k0 <= k0;
              load_k_len <= tile_k_len;
            end
            load_error_q <= ERR_NONE;
            load_state <= LOAD_FILL_A;
          end
        end
        LOAD_FILL_A: begin
          load_a_lo_q <= product16(load_m0,cmd_q.a_stride[15:0]);
          load_a_hi_q <= product16(load_m0,cmd_q.a_stride[31:16]);
          load_b_lo_q <= product16(load_k0,cmd_q.b_stride[15:0]);
          load_b_hi_q <= product16(load_k0,cmd_q.b_stride[31:16]);
          load_a_col_q <= {14'd0,element_bytes(load_k0,input_bytes)};
          load_b_col_q <= {14'd0,element_bytes(load_n0,input_bytes)};
          load_state <= LOAD_FILL_B;
        end
        LOAD_FILL_B: begin
          // Address ABI is uint32. Descriptor range validation has already
          // proved valid accesses fit; lower-32 product matches the old ABI.
          load_a_offset_q <= load_a_lo_q + {load_a_hi_q[15:0],16'd0};
          load_b_offset_q <= load_b_lo_q + {load_b_hi_q[15:0],16'd0};
          if (runtime_error || spad_protocol_error) begin
            load_error_q <= ERR_INTERNAL_PROTOCOL;
            load_state <= LOAD_ERROR;
          end else begin
            load_state <= LOAD_SELECT;
          end
        end
        LOAD_SELECT: begin
          if (runtime_error || spad_protocol_error) begin
            load_error_q <= ERR_INTERNAL_PROTOCOL;
            load_state <= LOAD_ERROR;
          end else if (!load_need_a && !load_need_b) begin
            load_state <= LOAD_DONE;
          end else if (load_need_b && (!load_need_a || !load_last_grant_b)) begin
            load_selected_b <= 1'b1;
            load_job_q.kind <= DMA_LOAD_B;
            load_job_q.base <= cmd_q.b_base + load_b_offset_q + load_b_col_q;
            load_job_q.row_stride <= cmd_q.b_stride;
            load_job_q.rows <= load_k_len;
            load_job_q.cols <= load_n_len;
            load_job_q.elem_bytes <= input_bytes[1:0];
            load_job_q.bank <= load_bank_q;
            load_state <= LOAD_ISSUE;
          end else begin
            load_selected_b <= 1'b0;
            load_job_q.kind <= DMA_LOAD_A;
            load_job_q.base <= cmd_q.a_base + load_a_offset_q + load_a_col_q;
            load_job_q.row_stride <= cmd_q.a_stride;
            load_job_q.rows <= load_m_len;
            load_job_q.cols <= load_k_len;
            load_job_q.elem_bytes <= input_bytes[1:0];
            load_job_q.bank <= load_bank_q;
            load_state <= LOAD_ISSUE;
          end
        end
        LOAD_ISSUE: begin
          if (runtime_error || spad_protocol_error) begin
            load_error_q <= ERR_INTERNAL_PROTOCOL;
            load_state <= LOAD_ERROR;
          end else if (dma_job_valid && dma_job_ready)
            load_state <= LOAD_WAIT;
        end
        LOAD_WAIT: begin
          if (runtime_error || spad_protocol_error) begin
            if (dma_job_error || dma_job_done) begin
              load_error_q <= ERR_INTERNAL_PROTOCOL;
              load_state <= LOAD_ERROR;
            end
          end else if (dma_job_error) begin
            load_error_q <= (dma_error_code == ERR_NONE) ?
                            ERR_INTERNAL_PROTOCOL : dma_error_code;
            load_state <= LOAD_ERROR;
          end else if (dma_job_done) begin
            load_state <= LOAD_READY_OWNER;
          end
        end
        LOAD_READY_OWNER: begin
          if (runtime_error || spad_protocol_error) begin
            load_error_q <= ERR_INTERNAL_PROTOCOL;
            load_state <= LOAD_ERROR;
          end else begin
            if (load_selected_b) load_need_b <= 1'b0;
            else load_need_a <= 1'b0;
            load_last_grant_b <= load_selected_b;
            load_state <= LOAD_SELECT;
          end
        end
        LOAD_DONE, LOAD_ERROR: begin
          if (load_result_ack)
            load_state <= LOAD_IDLE;
        end
        default: load_state <= LOAD_IDLE;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      cmd_q <= '0;
      completion_q <= '0;
      store_job_q <= '0;
      cycle_count <= '0;
      a_stride_product_q <= '0;
      b_stride_product_q <= '0;
      c_stride_product_q <= '0;
      a_row_bytes_q <= '0;
      b_row_bytes_q <= '0;
      c_row_bytes_q <= '0;
      a_last_q <= '0;
      b_last_q <= '0;
      c_last_q <= '0;
      descriptor_known_q <= 1'b0;
      mn_q <= '0;
      macs_q <= '0;
      m_prev_q <= '0; k_prev_q <= '0;
      a_lo_q <= '0; a_hi_q <= '0; b_lo_q <= '0; b_hi_q <= '0;
      c_lo_q <= '0; c_hi_q <= '0; mac_lo_q <= '0; mac_hi_q <= '0;
      store_c_lo_q <= '0; store_c_hi_q <= '0;
      store_c_offset_q <= '0; store_c_col_q <= '0;
      tile_cell_count_q <= '0;
      tile_cell_last_q <= 32'hffff_ffff;
      tile_m_len_preq <= '0;
      tile_n_len_preq <= '0;
      tile_cell_count_preq <= '0;
      pending_error <= ERR_NONE;
      pending_partial_output <= 1'b0;
      m0 <= '0;
      n0 <= '0;
      k0 <= '0;
      compute_bank <= 1'b0;
      exec_k_len_q <= '0;
      exec_row_mask_q <= '0; exec_col_mask_q <= '0;
      exec_continue_q <= 1'b0; exec_int16_q <= 1'b0; exec_has_next_k_q <= 1'b0;
      read_issue_count <= '0;
      array_feed_accept_count <= '0;
      feed_q0_valid <= 1'b0;
      feed_q1_valid <= 1'b0;
      
      
      
      
      array_done_seen <= 1'b0;
      runtime_error <= 1'b0;
      after_release_next_k <= 1'b0;
      error_after_release <= 1'b0;
      drain_issue_row <= '0;
      drain_issue_col <= '0;
      store_out_row_q <= '0;
      store_out_col_q <= '0;
      wb_q0_valid <= 1'b0;
      wb_q1_valid <= 1'b0;
      
      
      
      
      
      
      
      
      post_in_count <= '0;
      post_out_count <= '0;
      acc_pending_valid <= 1'b0;
      discard_remaining <= '0;
      page_mode_q<=0;page_slot_q<=0;page_identity_q<=0;resident_full_k_q<=0;
      page_chunked_q<=0;page_warm_q<=0;page_columns_q<=0;page_end_q<=0;
      page_group_origin_q<=0;page_c_base_q<=0;page_failure_q<=ERR_NONE;
    end else begin
      if ((state != IDLE) && (state != COMPLETE))
        cycle_count <= increment_saturating(cycle_count);
      if ((state != IDLE) && spad_protocol_error)
        runtime_error <= 1'b1;
      if(page_store_done)begin
        pending_partial_output<=pending_partial_output|dma_partial_output;
        if(page_return_error)begin
          runtime_error<=1'b1;
          if(page_failure_q==ERR_NONE)
            page_failure_q<=page_store_error==ERR_NONE?ERR_INTERNAL_PROTOCOL:page_store_error;
        end
      end

      case (state)
        IDLE: begin
          if (cmd_valid && cmd_ready) begin
            cmd_q <= cmd_data;
            resident_full_k_q<=resident_candidate;
            page_chunked_q<=chunk_candidate;page_warm_q<=0;
            page_columns_q<=initial_page_columns;page_end_q<=16'(initial_page_columns);
            page_group_origin_q<=0;page_c_base_q<=cmd_data.c_base;page_failure_q<=ERR_NONE;
            page_mode_q<=RESULT_PAGE_STORE&&result_page_enable&&
              !cmd_data.input_int16&&cmd_data.m>0&&cmd_data.m<=16&&
              cmd_data.n>0&&cmd_data.n<=256&&cmd_data.output_fmt==2&&
              cmd_data.activation==0&&!cmd_data.rounding&&cmd_data.shift==0&&
              cmd_data.clamp_min==32'sh80000000&&cmd_data.clamp_max==32'sh7fffffff;
            page_slot_q<=!page_slot_q;
            page_identity_q<={result_context,cmd_data.user_tag,cmd_data.c_base,
                              cmd_data.m,16'(initial_page_columns),16'd0,cmd_data.k};
            m_prev_q <= cmd_data.m - 16'd1;
            k_prev_q <= cmd_data.k - 16'd1;
            cycle_count <= '0;
            pending_error <= ERR_NONE;
            pending_partial_output <= 1'b0;
            m0 <= '0;
            n0 <= '0;
            k0 <= '0;
            compute_bank <= 1'b0;
            feed_q0_valid <= 1'b0;
            feed_q1_valid <= 1'b0;
            array_feed_accept_count <= '0;
            runtime_error <= 1'b0;
            discard_remaining <= '0;
            state <= VALIDATE_MUL;
          end
        end
        VALIDATE_MUL: begin
          // E1: decrement happened at command acceptance. Products end in
          // registers; no DSP cascade combines low/high halves in this edge.
          a_lo_q <= product16(m_prev_q,cmd_q.a_stride[15:0]);
          a_hi_q <= product16(m_prev_q,cmd_q.a_stride[31:16]);
          b_lo_q <= product16(k_prev_q,cmd_q.b_stride[15:0]);
          b_hi_q <= product16(k_prev_q,cmd_q.b_stride[31:16]);
          c_lo_q <= product16(m_prev_q,cmd_q.c_stride[15:0]);
          c_hi_q <= product16(m_prev_q,cmd_q.c_stride[31:16]);
          a_row_bytes_q <= {47'd0,element_bytes(cmd_q.k,input_bytes)};
          b_row_bytes_q <= {47'd0,element_bytes(cmd_q.n,input_bytes)};
          c_row_bytes_q <= {47'd0,element_bytes(cmd_q.n,output_bytes)};
          descriptor_known_q <= known_word32(cmd_q.a_base) &&
                                known_word32(cmd_q.b_base) &&
                                known_word32(cmd_q.c_base) &&
                                known_word32(cmd_q.a_stride) &&
                                known_word32(cmd_q.b_stride) &&
                                known_word32(cmd_q.c_stride);
          mn_q <= {32'd0,product16(cmd_q.m,cmd_q.n)};
          state <= VALIDATE_PRODUCT_SUM;
        end
        VALIDATE_PRODUCT_SUM: begin
          // E2: registered partials -> bounded sum, independent of operand mux.
          a_stride_product_q <= {17'd0,join_product(a_lo_q,a_hi_q)};
          b_stride_product_q <= {17'd0,join_product(b_lo_q,b_hi_q)};
          c_stride_product_q <= {17'd0,join_product(c_lo_q,c_hi_q)};
          mac_lo_q <= product16(mn_q[15:0],cmd_q.k);
          mac_hi_q <= product16(mn_q[31:16],cmd_q.k);
          state <= VALIDATE_ADDR;
        end
        VALIDATE_ADDR: begin
          // E3: retain 65-bit carry/underflow in the last-byte expression.
          a_last_q <= {33'd0, cmd_q.a_base} + a_stride_product_q + a_row_bytes_q - 65'd1;
          b_last_q <= {33'd0, cmd_q.b_base} + b_stride_product_q + b_row_bytes_q - 65'd1;
          c_last_q <= {33'd0, cmd_q.c_base} + c_stride_product_q + c_row_bytes_q - 65'd1;
          macs_q <= {16'd0,join_product(mac_lo_q,mac_hi_q)};
          state <= VALIDATE_DECIDE;
        end
        VALIDATE_DECIDE: begin
          // E4: no DMA/owner launch before all registered validation results.
          completion_q.user_tag <= cmd_q.user_tag;
          completion_q.partial_output <= 1'b0;
          // pending_error is only consumed after ERROR_CLEAN. Give it a
          // validation-independent value here so the long descriptor error
          // priority chain does not drive this register's clock enable.
          pending_error <= (runtime_error || spad_protocol_error) ?
                           ERR_INTERNAL_PROTOCOL : ERR_NONE;
          if (validation_error != ERR_NONE) begin
            completion_q.error <= validation_error;
            completion_q.cycles <= increment_saturating(cycle_count);
            completion_q.macs <= '0;
            state <= COMPLETE;
          end else begin
            completion_q.error <= ERR_NONE;
            completion_q.macs <= macs_q;
            if (runtime_error || spad_protocol_error) begin
              state <= ERROR_CLEAN;
            end else begin
              state <= page_mode_q?PAGE_BEGIN:LAUNCH_LOAD;
            end
          end
        end
        LAUNCH_LOAD: begin
          if (runtime_error || spad_protocol_error) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            state <= ERROR_CLEAN;
          end else if (load_launch && load_launch_ready)
            state <= WAIT_FIRST_LOAD;
        end
        WAIT_FIRST_LOAD: begin
          if ((runtime_error || spad_protocol_error) &&
              ((load_state == LOAD_ERROR) || (load_state == LOAD_DONE))) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            pending_partial_output <= pending_partial_output | dma_partial_output;
            state <= ERROR_CLEAN;
          end else if (load_state == LOAD_ERROR) begin
            pending_error <= load_error_q;
            pending_partial_output <= pending_partial_output | dma_partial_output;
            state <= ERROR_CLEAN;
          end else if (load_state == LOAD_DONE) begin
            if (runtime_error) begin
              pending_error <= ERR_INTERNAL_PROTOCOL;
              state <= ERROR_CLEAN;
            end else begin
              tile_m_len_preq <= (ROW_W+1)'(tile_m_len);
              tile_n_len_preq <= (COL_W+1)'(tile_n_len);
              state <= CLAIM_A;
            end
          end
        end
        CLAIM_A: begin
          tile_cell_count_preq <= tile_cell_count_calc;
          if (runtime_error || spad_protocol_error) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            state <= ERROR_CLEAN;
          end else begin
            state <= CLAIM_B;
          end
        end
        CLAIM_B: begin
          // The tile dimensions are already stable before array start. Keep
          // the final-output compare operand in a register so post_out_fire
          // cannot enter a 32-bit subtract/carry path at 200 MHz.
          tile_cell_last_q <= 32'(tile_cell_count_preq - CELL_W'(1));
          exec_k_len_q <= EXEC_COUNT_W'(tile_k_len);
          exec_row_mask_q <= make_row_mask(16'(tile_m_len_preq));
          exec_col_mask_q <= make_col_mask(16'(tile_n_len_preq));
          exec_continue_q <= (k0 != 0);
          exec_int16_q <= cmd_q.input_int16;
          exec_has_next_k_q <= has_next_k;
          if (runtime_error || spad_protocol_error) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            state <= ERROR_CLEAN;
          end else begin
            state <= START_ARRAY;
          end
        end
        START_ARRAY: begin
          if (runtime_error || spad_protocol_error) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            state <= ERROR_CLEAN;
          end else if (array_start_valid && array_start_ready) begin
            // The accepted array start commits this execution tile. Hold
            // its count across K continuation, draining, and error cleanup.
            tile_cell_count_q <= 32'(tile_cell_count_preq);
            read_issue_count <= '0;
            array_feed_accept_count <= '0;
            feed_q0_valid <= 1'b0;
            feed_q1_valid <= 1'b0;
            array_done_seen <= 1'b0;
            state <= COMPUTE;
          end
        end
        COMPUTE: begin
          if (spad_compute_read_valid)
            read_issue_count <= read_issue_count + 1'b1;
          if (array_feed_valid && array_feed_ready)
            array_feed_accept_count <= array_feed_accept_count + 1'b1;
          case ({feed_push, feed_pop})
            2'b01: begin
              if (feed_q1_valid) begin
                
                
                feed_q0_valid <= 1'b1;
                feed_q1_valid <= 1'b0;
              end else begin
                feed_q0_valid <= 1'b0;
              end
            end
            2'b10: begin
              if (!feed_q0_valid) begin
                
                
                feed_q0_valid <= 1'b1;
              end else if (!feed_q1_valid) begin
                
                
                feed_q1_valid <= 1'b1;
              end else begin
                runtime_error <= 1'b1;
              end
            end
            2'b11: begin
              if (feed_q1_valid) begin
                
                
                
                
                feed_q0_valid <= 1'b1;
                feed_q1_valid <= 1'b1;
              end else begin
                
                
                feed_q0_valid <= 1'b1;
                feed_q1_valid <= 1'b0;
              end
            end
            default: ;
          endcase
          if (spad_protocol_error || runtime_error) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            pending_partial_output <= pending_partial_output | dma_partial_output;
            after_release_next_k <= 1'b0;
            error_after_release <= 1'b1;
            if (array_done_seen || array_done) begin
              feed_q0_valid <= 1'b0;
              feed_q1_valid <= 1'b0;
              state <= RELEASE_A;
            end else begin
              state <= ABORT_ARRAY;
            end
          end else begin
            if (array_done)
              array_done_seen <= 1'b1;

            if (array_done_seen || array_done) begin
            if (has_next_k) begin
              if (load_state == LOAD_ERROR) begin
                pending_error <= load_error_q;
                pending_partial_output <= pending_partial_output | dma_partial_output;
                after_release_next_k <= 1'b0;
                error_after_release <= 1'b1;
                state <= RELEASE_A;
              end else if (load_state == LOAD_DONE) begin
                if (runtime_error || spad_protocol_error ||
                    (feed_push && (feed_slots_after_edge > 2))) begin
                  pending_error <= ERR_INTERNAL_PROTOCOL;
                  after_release_next_k <= 1'b0;
                  error_after_release <= 1'b1;
                end else begin
                  after_release_next_k <= 1'b1;
                  error_after_release <= 1'b0;
                end
                state <= RELEASE_A;
              end
            end else begin
              after_release_next_k <= 1'b0;
              if (runtime_error || spad_protocol_error ||
                  (feed_push && (feed_slots_after_edge > 2))) begin
                pending_error <= ERR_INTERNAL_PROTOCOL;
                error_after_release <= 1'b1;
              end else begin
                error_after_release <= 1'b0;
              end
              state <= RELEASE_A;
            end
          end
          end
        end
        ABORT_ARRAY: begin
          if (feed_pop) begin
            if (feed_q1_valid) begin
              
              
              feed_q0_valid <= 1'b1;
              feed_q1_valid <= 1'b0;
            end else begin
              feed_q0_valid <= 1'b0;
            end
          end
          if (array_feed_valid && array_feed_ready)
            array_feed_accept_count <= array_feed_accept_count + 1'b1;
          if (array_done) begin
            feed_q0_valid <= 1'b0;
            feed_q1_valid <= 1'b0;
            state <= RELEASE_A;
          end
        end
        RELEASE_A: begin
          store_c_lo_q <= product16(m0,cmd_q.c_stride[15:0]);
          store_c_hi_q <= product16(m0,cmd_q.c_stride[31:16]);
          store_c_col_q <= {14'd0,element_bytes(n0,output_bytes)};
          if (runtime_error || spad_protocol_error) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            error_after_release <= 1'b1;
            after_release_next_k <= 1'b0;
            state <= ERROR_CLEAN;
          end else begin
            state <= RELEASE_B;
          end
        end
        RELEASE_B: begin
          store_c_offset_q <= store_c_lo_q + {store_c_hi_q[15:0],16'd0};
          if (runtime_error || spad_protocol_error) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            state <= ERROR_CLEAN;
          end else if (error_after_release) begin
            state <= ERROR_CLEAN;
          end else if (after_release_next_k) begin
            compute_bank <= ~compute_bank;
            k0 <= k_after_tile[15:0];
            tile_m_len_preq <= (ROW_W+1)'(tile_m_len);
            tile_n_len_preq <= (COL_W+1)'(tile_n_len);
            state <= CLAIM_A;
          end else begin
            state <= page_mode_q?PAGE_CAPTURE_START:STORE_PREP;
          end
        end
        STORE_PREP: begin
          if (runtime_error || spad_protocol_error) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            state <= ERROR_CLEAN;
          end else begin
            store_job_q.kind <= DMA_STORE_C;
            store_job_q.base <= cmd_q.c_base + store_c_offset_q + store_c_col_q;
            store_job_q.row_stride <= cmd_q.c_stride;
            store_job_q.rows <= tile_m_len;
            store_job_q.cols <= tile_n_len;
            // The shared job ABI has two width bits: LOAD uses literal 1/2;
            // STORE_C carries the authoritative literal 1/2/4 on its element
            // stream, so INT32 appears as zero only in this otherwise-unused
            // job field.
            store_job_q.elem_bytes <= output_bytes[1:0];
            store_job_q.bank <= 1'b0;
            state <= STORE_ISSUE;
          end
        end
        STORE_ISSUE: begin
          if (runtime_error || spad_protocol_error) begin
            pending_error <= ERR_INTERNAL_PROTOCOL;
            state <= ERROR_CLEAN;
          end else if (dma_job_valid && dma_job_ready) begin
            drain_issue_row <= '0;
            drain_issue_col <= '0;
            store_out_row_q <= '0;
            store_out_col_q <= '0;
            wb_q0_valid <= 1'b0;
            wb_q1_valid <= 1'b0;
            post_in_count <= '0;
            post_out_count <= '0;
            acc_pending_valid <= 1'b0;
            discard_remaining <= '0;
            state <= DRAIN_ACC;
          end
        end
        DRAIN_ACC: begin
          case ({post_out_fire, store_elem_fire})
            2'b01: begin
              if (wb_q1_valid) begin
                
                
                
                
                wb_q0_valid <= 1'b1;
                wb_q1_valid <= 1'b0;
              end else begin
                wb_q0_valid <= 1'b0;
              end
            end
            2'b10: begin
              if (!wb_q0_valid) begin
                
                
                
                
                wb_q0_valid <= 1'b1;
              end else begin
                
                
                
                
                wb_q1_valid <= 1'b1;
              end
            end
            2'b11: begin
              if (wb_q1_valid) begin
                
                
                
                
                
                
                
                
                wb_q0_valid <= 1'b1;
                wb_q1_valid <= 1'b1;
              end else begin
                
                
                
                
                wb_q0_valid <= 1'b1;
                wb_q1_valid <= 1'b0;
              end
            end
            default: ;
          endcase
          if (!acc_pending_valid && (post_in_count < tile_cell_count_q))
            acc_pending_valid <= 1'b1;
          if (post_in_fire) begin
            acc_pending_valid <= 1'b0;
            post_in_count <= post_in_count + 1'b1;
            if ((drain_issue_col + 1'b1) >= tile_n_len) begin
              drain_issue_col <= '0;
              drain_issue_row <= drain_issue_row + 1'b1;
            end else begin
              drain_issue_col <= drain_issue_col + 1'b1;
            end
          end
          if (post_out_fire) begin
            post_out_count <= post_out_count + 1'b1;
            if ((store_out_col_q + 1'b1) >= tile_n_len) begin
              store_out_col_q <= '0;
              store_out_row_q <= store_out_row_q + 1'b1;
            end else begin
              store_out_col_q <= store_out_col_q + 1'b1;
            end
          end

          if (dma_job_error) begin
            pending_error <= (runtime_error || spad_protocol_error) ?
                             ERR_INTERNAL_PROTOCOL :
                             ((dma_error_code == ERR_NONE) ?
                              ERR_INTERNAL_PROTOCOL : dma_error_code);
            pending_partial_output <= pending_partial_output | dma_partial_output;
            discard_remaining <= post_pending_after_fire;
            acc_pending_valid <= 1'b0;
            wb_q0_valid <= 1'b0;
            wb_q1_valid <= 1'b0;
            state <= ERROR_CLEAN;
          end else if (dma_job_done) begin
            if (runtime_error || spad_protocol_error) begin
              pending_error <= ERR_INTERNAL_PROTOCOL;
              pending_partial_output <= pending_partial_output | dma_partial_output;
              discard_remaining <= post_pending_after_fire;
              acc_pending_valid <= 1'b0;
              wb_q0_valid <= 1'b0;
              wb_q1_valid <= 1'b0;
              state <= ERROR_CLEAN;
            end else if (!post_count_complete ||
                         wb_q0_valid || wb_q1_valid) begin
              pending_error <= ERR_INTERNAL_PROTOCOL;
              pending_partial_output <= pending_partial_output | dma_partial_output;
              discard_remaining <= post_pending_after_fire;
              acc_pending_valid <= 1'b0;
              wb_q0_valid <= 1'b0;
              wb_q1_valid <= 1'b0;
              state <= ERROR_CLEAN;
            end else if (has_next_output) begin
              pending_partial_output <= pending_partial_output | dma_partial_output;
              if (has_next_n) begin
                n0 <= n_after_tile[15:0];
              end else begin
                n0 <= '0;
                m0 <= m_after_tile[15:0];
              end
              k0 <= '0;
              compute_bank <= 1'b0;
              runtime_error <= 1'b0;
              state <= LAUNCH_LOAD;
            end else begin
              pending_partial_output <= pending_partial_output | dma_partial_output;
              completion_q.error <= ERR_NONE;
              completion_q.partial_output <= 1'b0;
              completion_q.cycles <= increment_saturating(cycle_count);
              state <= COMPLETE;
            end
          end
        end
        PAGE_BEGIN:begin
          if(page_capture_cancel)begin pending_error<=ERR_INTERNAL_PROTOCOL;state<=ERROR_CLEAN;end
          else if(page_bank_ready)begin
            // A/B identity and physical ownership remain authoritative even
            // while the other result slot is being written back.
            if(!page_warm_q)state<=LAUNCH_LOAD;
            else if(resident_operands_ready)state<=REUSE_FILL_A;
          end
        end
        PAGE_CAPTURE_START:begin
          if(runtime_error||spad_protocol_error)begin pending_error<=ERR_INTERNAL_PROTOCOL;state<=ERROR_CLEAN;end
          else if(page_capture_ready)state<=PAGE_CAPTURE_WAIT;
        end
        PAGE_CAPTURE_WAIT:if(page_capture_done)begin
          if(page_capture_cancelled||page_capture_cancel)begin
            pending_error<=ERR_INTERNAL_PROTOCOL;state<=ERROR_CLEAN;
          end else if(has_next_n&&(!page_chunked_q||n_after_tile<{1'b0,page_end_q}))begin
            n0<=n_after_tile[15:0];k0<=0;compute_bank<=0;
            state <= (RESIDENT_GROUP_REUSE_ENABLE && resident_full_k_q &&
                      resident_operands_ready && load_state==LOAD_IDLE) ? REUSE_FILL_A : LAUNCH_LOAD;
          end else state<=PAGE_COMMIT;
        end
        REUSE_FILL_A, REUSE_FILL_B, REUSE_READY_A, REUSE_READY_B: begin
          if(runtime_error || spad_protocol_error || !resident_operands_ready || load_state!=LOAD_IDLE) begin
            pending_error<=ERR_INTERNAL_PROTOCOL;state<=ERROR_CLEAN;
          end else case(state)
            REUSE_FILL_A: state<=REUSE_FILL_B;
            REUSE_FILL_B: state<=REUSE_READY_A;
            REUSE_READY_A: state<=REUSE_READY_B;
            default: begin
              tile_m_len_preq <= (ROW_W+1)'(tile_m_len);
              tile_n_len_preq <= (COL_W+1)'(tile_n_len);
              state<=CLAIM_A;
            end
          endcase
        end
        PAGE_COMMIT:begin
          if(page_capture_cancel)begin pending_error<=ERR_INTERNAL_PROTOCOL;state<=ERROR_CLEAN;end
          else state<=PAGE_STORE_START;
        end
        PAGE_STORE_START:begin
          if(page_capture_cancel)begin pending_error<=ERR_INTERNAL_PROTOCOL;state<=ERROR_CLEAN;end
          else if(page_store_ready)begin
            if(page_more)begin
              // The bridge snapshots the previous page at this same edge.
              // Reuse the other physical result slot, retaining the command
              // and its completion reservation until the final real B.
              page_slot_q<=!page_slot_q;page_warm_q<=1;
              n0<=page_end_q;k0<=0;compute_bank<=0;
              page_group_origin_q<=page_end_q[7:3];
              page_columns_q<=next_page_columns;
              page_end_q<=page_end_q+16'(next_page_columns);
              page_c_base_q<=page_c_base_q+(32'(page_columns_q)<<2);
              page_identity_q[95:64]<=page_c_base_q+(32'(page_columns_q)<<2);
              page_identity_q[47:32]<=16'(next_page_columns);
              state<=PAGE_BEGIN;
            end else state<=PAGE_STORE_WAIT;
          end
        end
        PAGE_STORE_WAIT:if(page_store_done)begin
          pending_partial_output<=pending_partial_output|dma_partial_output;
          if(page_store_error!=ERR_NONE||page_store_cancelled||runtime_error||spad_protocol_error)begin
            pending_error<=(runtime_error||spad_protocol_error||page_store_cancelled)?ERR_INTERNAL_PROTOCOL:page_store_error;
            state<=ERROR_CLEAN;
          end else begin
            completion_q.error<=ERR_NONE;completion_q.partial_output<=0;
            completion_q.cycles<=increment_saturating(cycle_count);state<=COMPLETE;
          end
        end
        ERROR_CLEAN: begin
          if ((discard_remaining != 0) && post_out_fire)
            discard_remaining <= discard_remaining - 1'b1;
          if (cleanup_all_empty && page_cleanup_idle && (discard_remaining == 0) &&
              (load_state == LOAD_IDLE)) begin
            completion_q.error <= page_failure_q!=ERR_NONE ? page_failure_q :
                                  ((pending_error == ERR_NONE) ? ERR_INTERNAL_PROTOCOL : pending_error);
            completion_q.partial_output <= pending_partial_output;
            completion_q.cycles <= increment_saturating(cycle_count);
            state <= COMPLETE;
          end
        end
        COMPLETE: begin
          if (completion_valid && completion_ready)
            state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end
  // synthesis translate_off
  initial if(RESULT_CHUNK_COLUMNS!=16&&RESULT_CHUNK_COLUMNS!=32&&RESULT_CHUNK_COLUMNS!=64&&
             RESULT_CHUNK_COLUMNS!=128&&RESULT_CHUNK_COLUMNS!=256)
    $fatal(1,"RESULT_CHUNK_PARAMETER_RED");
  always_ff @(posedge clk)if(!rst)begin
    if(page_store_busy&&load_state!=LOAD_IDLE)$fatal(1,"RESULT_CHUNK_DMA_OWNER_RED");
    if(page_store_busy&&page_capture_valid&&page_store_slot==page_slot_q)
      $fatal(1,"RESULT_CHUNK_OVERWRITE_STORE_RED");
    if(completion_valid&&page_mode_q&&(page_store_busy||page_owners!=0||!result_order_idle||result_dma_outstanding!=0))
      $fatal(1,"RESULT_CHUNK_EARLY_COMPLETION_RED");
  end
  function automatic logic [15:0] cp8_reference_tile_len(
      input logic [15:0] dimension, origin, capacity);
    logic [15:0] remaining;
    remaining = dimension - origin;
    return (remaining > capacity) ? capacity : remaining;
  endfunction
  always @(posedge clk) if(!rst && !$isunknown({m0,n0,k0,cmd_q.m,cmd_q.n,cmd_q.k})) begin
    if(tile_m_len !== cp8_reference_tile_len(cmd_q.m,m0,ARRAY_ROWS_COUNT) ||
       tile_n_len !== cp8_reference_tile_len(cmd_q.n,n0,ARRAY_COLS_COUNT) ||
       legacy_tile_k_len !== cp8_reference_tile_len(cmd_q.k,k0,K_TILE_COUNT) ||
       tile_k_len !== (resident_full_k_q ? cmd_q.k :
                      cp8_reference_tile_len(cmd_q.k,k0,K_TILE_COUNT)) ||
       next_tile_k_len !== cp8_reference_tile_len(cmd_q.k,
                           16'(k0 + legacy_tile_k_len),K_TILE_COUNT))
      $fatal(1,"CP8_TILE_LENGTH_EQUIVALENCE_RED");
  end
  // Full-K execution is allowed only at resident origin zero and must
  // never schedule a legacy prefetch/partial-K restart. Keep this separate
  // from the old tile-length monitors to catch accidental mode mixing.
  always @(posedge clk) if(!rst && resident_full_k_q) begin
    if(k0 != 0 || has_next_k || tile_k_len != cmd_q.k)
      $fatal(1,"RESIDENT_FULL_K_CONTRACT_RED");
    if(state == COMPUTE && (read_issue_count > exec_k_len_q ||
                           array_feed_accept_count > exec_k_len_q))
      $fatal(1,"RESIDENT_FULL_K_FEED_BOUNDS_RED");
  end
  // Independent old predicates remain executable monitors in verification.
  // They observe the same tile geometry without driving a state transition.
  always @(posedge clk) if(!rst && !$isunknown({m0,n0,k0,cmd_q.m,cmd_q.n,cmd_q.k})) begin
    if(has_next_m !== (m_after_tile < {1'b0,cmd_q.m}) ||
       has_next_n !== (n_after_tile < {1'b0,cmd_q.n}) ||
       has_next_k !== (k_after_tile < {1'b0,cmd_q.k}))
      $fatal(1,"CP8_TILE_BOUND_EQUIVALENCE_RED");
  end
  // synthesis translate_on

  // Payload registers are meaningful only while their retained queue-valid
  // bits are set. Reset clears both queue valids/FSMs in the control block;
  // each newly-valid entry is fully overwritten here before consumption.
  // No reset qualifies this payload write path, including as a clock enable.
  // ABORT_ARRAY's existing empty-queue zero injection remains unchanged.
  always_ff @(posedge clk) begin
    if (state == COMPUTE) begin
      case ({feed_push, feed_pop})
        2'b01: if (feed_q1_valid) begin
          feed_a_q0 <= feed_a_q1; feed_b_q0 <= feed_b_q1;
        end
        2'b10: begin
          if (!feed_q0_valid) begin
            feed_a_q0 <= spad_a_vector; feed_b_q0 <= spad_b_vector;
          end else if (!feed_q1_valid) begin
            feed_a_q1 <= spad_a_vector; feed_b_q1 <= spad_b_vector;
          end
        end
        2'b11: begin
          if (feed_q1_valid) begin
            feed_a_q0 <= feed_a_q1; feed_b_q0 <= feed_b_q1;
            feed_a_q1 <= spad_a_vector; feed_b_q1 <= spad_b_vector;
          end else begin
            feed_a_q0 <= spad_a_vector; feed_b_q0 <= spad_b_vector;
          end
        end
        default: ;
      endcase
    end else if ((state == ABORT_ARRAY) && feed_pop && feed_q1_valid) begin
      feed_a_q0 <= feed_a_q1; feed_b_q0 <= feed_b_q1;
    end
    if (state == DRAIN_ACC) begin
      case ({post_out_fire, store_elem_fire})
        2'b01: if (wb_q1_valid) begin
          wb_data_q0<=wb_data_q1;wb_bytes_q0<=wb_bytes_q1;
          wb_row_q0<=wb_row_q1;wb_col_q0<=wb_col_q1;
        end
        2'b10: begin
          if (!wb_q0_valid) begin
            wb_data_q0<=post_out_value;wb_bytes_q0<=post_out_bytes;
            wb_row_q0<=store_out_row_q;wb_col_q0<=store_out_col_q;
          end else begin
            wb_data_q1<=post_out_value;wb_bytes_q1<=post_out_bytes;
            wb_row_q1<=store_out_row_q;wb_col_q1<=store_out_col_q;
          end
        end
        2'b11: begin
          if (wb_q1_valid) begin
            wb_data_q0<=wb_data_q1;wb_bytes_q0<=wb_bytes_q1;
            wb_row_q0<=wb_row_q1;wb_col_q0<=wb_col_q1;
            wb_data_q1<=post_out_value;wb_bytes_q1<=post_out_bytes;
            wb_row_q1<=store_out_row_q;wb_col_q1<=store_out_col_q;
          end else begin
            wb_data_q0<=post_out_value;wb_bytes_q0<=post_out_bytes;
            wb_row_q0<=store_out_row_q;wb_col_q0<=store_out_col_q;
          end
        end
        default: ;
      endcase
    end
  end
endmodule

// Full 16-bit modular subtraction is retained; no k>=k0 assumption.
// Power-of-two classification replaces min/add/sub/min serial arithmetic.
module cp13_k_lengths #(parameter int K_TILE=32)(
 input logic [15:0] k,k0,output logic [15:0] current_len,next_len
);
 localparam int KW=$clog2(K_TILE);
 wire [15:0] delta=k-k0;
 wire [15-KW:0] whole=delta[15:KW];
 wire [15:0] tail=16'(delta[KW-1:0]);
 initial if(K_TILE<8 || K_TILE>256 || (K_TILE&(K_TILE-1))!=0)
  $fatal(1,"CP13_K_TILE_CONTRACT_RED");
 assign current_len=(whole==0)?tail:16'(K_TILE);
 assign next_len=(whole==0)?16'd0:((whole==1)?tail:16'(K_TILE));
endmodule
