function automatic integer npu_mmio_count_width(input integer depth);
  begin
    npu_mmio_count_width = (depth < 2) ? 1 : $clog2(depth + 1);
  end
endfunction

function automatic integer npu_mmio_log2(input integer value);
  begin
    npu_mmio_log2 = (value < 1) ? 0 : $clog2(value);
  end
endfunction

module npu_mmio_overlay #(
  parameter int ARRAY_ROWS=4, ARRAY_COLS=4, K_TILE=32, MEM_DATA_W=32,
  parameter int CMDQ_DEPTH=4, COMPQ_DEPTH=4
) (
  input logic clk, rst,
  input logic [31:0] perip_addr, perip_wdata,
  input logic perip_wen,
  input logic [1:0] perip_mask,
  input logic [31:0] legacy_perip_rdata,
  output logic [31:0] combined_perip_rdata,
  output logic cmd_push_valid,
  input logic cmd_push_ready,
  output npu_defs_pkg::npu_cmd_t cmd_push_data,
  input logic [npu_mmio_count_width(CMDQ_DEPTH)-1:0] cmd_level,
  input logic cmd_empty, cmd_full,
  input logic completion_head_valid,
  input npu_defs_pkg::npu_completion_t completion_head_data,
  input logic completion_enqueued,
  output logic completion_pop,
  input logic [npu_mmio_count_width(COMPQ_DEPTH)-1:0] completion_level,
  input logic completion_empty, completion_full,
  input logic active,
  input logic error_event_valid,
  input npu_defs_pkg::npu_error_e error_event_code,
  /* verilator lint_off UNUSEDSIGNAL */
  input logic [31:0] error_event_tag,
  /* verilator lint_on UNUSEDSIGNAL */
  output logic soft_reset_req,
  input logic soft_reset_accept,
  output logic [1:0] irq_status,
  output logic [11:0] error_status,
  output logic [31:0] error_tag, reject_count,
  output logic irq
);
  localparam int CMD_LEVEL_W = npu_mmio_count_width(CMDQ_DEPTH);
  localparam int COMP_LEVEL_W = npu_mmio_count_width(COMPQ_DEPTH);
  localparam logic [31:0] NPU_BASE = 32'h8020_0200;
  localparam logic [31:0] CONTROL_WRITABLE = 32'h0000_0103;
  localparam logic [31:0] CAP0_VALUE =
    (ARRAY_ROWS & 32'hff) | ((ARRAY_COLS & 32'hff) << 8) |
    ((npu_mmio_log2(K_TILE) & 32'hff) << 16) | 32'h0100_0000;
  localparam logic [31:0] CAP1_VALUE =
    (CMDQ_DEPTH & 32'hff) | ((COMPQ_DEPTH & 32'hff) << 8) |
    ((npu_mmio_log2(MEM_DATA_W) & 32'h1f) << 16) | 32'h00e0_0000;

  logic hit_now, hit_q1, hit_q2, aligned_write, write_in_window, write_valid;
  logic [31:0] perip_word_addr, read_data_now, data_q1, data_q2;
  logic completion_irq_enable, error_irq_enable, error_tag_valid;
  logic [31:0] action_write_word, control_merged, dim_k_flags_merged, post_cfg_merged;
  logic protocol_error_write, doorbell_write, doorbell_admit, doorbell_reject;
  logic irq_clear_write, error_clear_write, completion_ack_write, soft_reset_write;
  logic reset_busy_error, external_error_valid, external_error_new;
  logic rejection_error_new, protocol_error_new, reset_busy_error_new;
  logic [3:0] external_error_index;
  npu_defs_pkg::npu_cmd_t descriptor_shadow;

  function automatic logic [31:0] merge_store_lane(
    input logic [31:0] old_word, input logic [31:0] store_data,
    input logic [1:0] store_mask, input logic [1:0] addr_low
  );
    logic [31:0] merged;
    begin
      merged = old_word;
      case (store_mask)
        2'b10: merged = store_data;
        2'b01: if (addr_low[1]) merged[31:16] = store_data[15:0];
               else merged[15:0] = store_data[15:0];
        2'b00: case (addr_low)
                 2'd0: merged[7:0] = store_data[7:0];
                 2'd1: merged[15:8] = store_data[7:0];
                 2'd2: merged[23:16] = store_data[7:0];
                 default: merged[31:24] = store_data[7:0];
               endcase
        default: merged = old_word;
      endcase
      merge_store_lane = merged;
    end
  endfunction

  function automatic logic legal_access(input logic [1:0] store_mask,
                                        input logic [1:0] addr_low);
    begin
      case (store_mask)
        2'b10: legal_access = (addr_low == 2'd0);
        2'b01: legal_access = !addr_low[0];
        2'b00: legal_access = 1'b1;
        default: legal_access = 1'b0;
      endcase
    end
  endfunction

  assign perip_word_addr = {perip_addr[31:2], 2'b00};
  assign hit_now = (perip_addr[31:8] == NPU_BASE[31:8]);
  assign aligned_write = legal_access(perip_mask, perip_addr[1:0]);
  assign write_in_window = perip_wen && hit_now;
  assign write_valid = write_in_window && aligned_write;
  assign action_write_word = merge_store_lane(32'd0, perip_wdata, perip_mask,
                                              perip_addr[1:0]);
  assign control_merged = merge_store_lane(
    {23'd0, 1'b0, 6'd0, error_irq_enable, completion_irq_enable},
    perip_wdata, perip_mask, perip_addr[1:0]);
  assign dim_k_flags_merged = merge_store_lane(
    {15'd0, descriptor_shadow.input_int16, descriptor_shadow.k},
    perip_wdata, perip_mask, perip_addr[1:0]);
  assign post_cfg_merged = merge_store_lane(
    {21'd0, descriptor_shadow.shift, descriptor_shadow.rounding,
     descriptor_shadow.activation, descriptor_shadow.output_fmt},
    perip_wdata, perip_mask, perip_addr[1:0]);

  always @(*) begin
    protocol_error_write = 1'b0;
    if (write_in_window) begin
      if (!aligned_write) protocol_error_write = 1'b1;
      else begin
        case (perip_word_addr)
          NPU_BASE + 32'h10:
            protocol_error_write = |(control_merged & ~CONTROL_WRITABLE);
          NPU_BASE + 32'h14:
            protocol_error_write = |(action_write_word & ~32'h0000_0003);
          NPU_BASE + 32'h20, NPU_BASE + 32'h24, NPU_BASE + 32'h28,
          NPU_BASE + 32'h2C, NPU_BASE + 32'h34, NPU_BASE + 32'h38,
          NPU_BASE + 32'h3C, NPU_BASE + 32'h44, NPU_BASE + 32'h48,
          NPU_BASE + 32'h4C: protocol_error_write = 1'b0;
          NPU_BASE + 32'h30:
            protocol_error_write = |dim_k_flags_merged[31:17];
          NPU_BASE + 32'h40:
            protocol_error_write = |post_cfg_merged[31:11] ||
                                   (post_cfg_merged[1:0] > 2'd2) ||
                                   (post_cfg_merged[3:2] > 2'd2) ||
                                   (post_cfg_merged[10:5] > 6'd47);
          NPU_BASE + 32'h50, NPU_BASE + 32'h74:
            protocol_error_write = |(action_write_word & ~32'h0000_0001);
          NPU_BASE + 32'h78:
            protocol_error_write = |action_write_word[31:12];
          default: protocol_error_write = 1'b1;
        endcase
      end
    end
  end

  assign doorbell_write = write_valid && !protocol_error_write &&
                          (perip_word_addr == NPU_BASE + 32'h50) && action_write_word[0];
  assign doorbell_admit = doorbell_write && cmd_push_ready;
  assign doorbell_reject = doorbell_write && !cmd_push_ready;
  assign irq_clear_write = write_valid && !protocol_error_write &&
                           (perip_word_addr == NPU_BASE + 32'h14);
  assign error_clear_write = write_valid && !protocol_error_write &&
                             (perip_word_addr == NPU_BASE + 32'h78);
  assign completion_ack_write = write_valid && !protocol_error_write &&
                                (perip_word_addr == NPU_BASE + 32'h74) && action_write_word[0];
  // The control-register error decision is local to this address.  Reusing
  // the global protocol-error mux here makes every unrelated MMIO decode a
  // predecessor of the busy-error IRQ flop on the 200 MHz path.
  assign soft_reset_write = write_valid &&
                            (perip_word_addr == NPU_BASE + 32'h10) &&
                            !(|(control_merged & ~CONTROL_WRITABLE)) &&
                            control_merged[8];
  assign reset_busy_error = soft_reset_write && !soft_reset_accept;
  assign external_error_valid = error_event_valid &&
                                (error_event_code != npu_defs_pkg::ERR_NONE) &&
                                (error_event_code <= npu_defs_pkg::ERR_ADDRESS_ALIAS);
  assign external_error_index = error_event_code[3:0] - 1'b1;
  assign external_error_new = external_error_valid && !error_status[external_error_index];
  assign rejection_error_new = doorbell_reject && !error_status[7];
  assign protocol_error_new = protocol_error_write && !error_status[8];
  assign reset_busy_error_new = reset_busy_error && !error_status[9];

  always @(*) begin
    read_data_now = 32'd0;
    case (perip_word_addr)
      NPU_BASE + 32'h00: read_data_now = 32'h4E50_5531;
      NPU_BASE + 32'h04: read_data_now = CAP0_VALUE;
      NPU_BASE + 32'h08: read_data_now = CAP1_VALUE;
      NPU_BASE + 32'h0C: begin
        read_data_now[0] = !active; read_data_now[1] = active;
        read_data_now[2] = cmd_empty; read_data_now[3] = cmd_full;
        read_data_now[4] = completion_empty; read_data_now[5] = completion_full;
        read_data_now[6] = completion_head_valid; read_data_now[7] = |error_status;
      end
      NPU_BASE + 32'h10: read_data_now = {30'd0, error_irq_enable, completion_irq_enable};
      NPU_BASE + 32'h14: read_data_now = {30'd0, irq_status};
      NPU_BASE + 32'h18: begin
        read_data_now[CMD_LEVEL_W-1:0] = cmd_level;
        read_data_now[8 +: COMP_LEVEL_W] = completion_level;
      end
      NPU_BASE + 32'h20: read_data_now = descriptor_shadow.a_base;
      NPU_BASE + 32'h24: read_data_now = descriptor_shadow.b_base;
      NPU_BASE + 32'h28: read_data_now = descriptor_shadow.c_base;
      NPU_BASE + 32'h2C: read_data_now = {descriptor_shadow.n, descriptor_shadow.m};
      NPU_BASE + 32'h30: read_data_now = {15'd0, descriptor_shadow.input_int16, descriptor_shadow.k};
      NPU_BASE + 32'h34: read_data_now = descriptor_shadow.a_stride;
      NPU_BASE + 32'h38: read_data_now = descriptor_shadow.b_stride;
      NPU_BASE + 32'h3C: read_data_now = descriptor_shadow.c_stride;
      NPU_BASE + 32'h40: read_data_now = {21'd0, descriptor_shadow.shift,
        descriptor_shadow.rounding, descriptor_shadow.activation, descriptor_shadow.output_fmt};
      NPU_BASE + 32'h44: read_data_now = descriptor_shadow.clamp_min;
      NPU_BASE + 32'h48: read_data_now = descriptor_shadow.clamp_max;
      NPU_BASE + 32'h4C: read_data_now = descriptor_shadow.user_tag;
      NPU_BASE + 32'h60: if (completion_head_valid) read_data_now = completion_head_data.user_tag;
      NPU_BASE + 32'h64: if (completion_head_valid) read_data_now =
        {23'd0, completion_head_data.partial_output, completion_head_data.error};
      NPU_BASE + 32'h68: if (completion_head_valid) read_data_now = completion_head_data.cycles;
      NPU_BASE + 32'h6C: if (completion_head_valid) read_data_now = completion_head_data.macs[31:0];
      NPU_BASE + 32'h70: if (completion_head_valid) read_data_now = completion_head_data.macs[63:32];
      NPU_BASE + 32'h78: read_data_now = {20'd0, error_status};
      NPU_BASE + 32'h7C: if (error_tag_valid) read_data_now = error_tag;
      NPU_BASE + 32'h80: read_data_now = reject_count;
      default: read_data_now = 32'd0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      hit_q1 <= 1'b0; hit_q2 <= 1'b0; data_q1 <= 32'd0; data_q2 <= 32'd0;
    end else begin
      hit_q1 <= hit_now && !perip_wen; hit_q2 <= hit_q1;
      data_q1 <= read_data_now; data_q2 <= data_q1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      descriptor_shadow <= '0;
      completion_irq_enable <= 1'b0; error_irq_enable <= 1'b0;
      completion_pop <= 1'b0;
      soft_reset_req <= 1'b0; irq_status <= '0; error_status <= '0;
      error_tag <= '0; error_tag_valid <= 1'b0; reject_count <= '0;
    end else begin
      completion_pop <= 1'b0; soft_reset_req <= 1'b0;
      if (soft_reset_write && soft_reset_accept) begin
        descriptor_shadow <= '0; completion_irq_enable <= 1'b0; error_irq_enable <= 1'b0;
        irq_status <= '0; error_status <= '0; error_tag <= '0; error_tag_valid <= 1'b0;
        reject_count <= '0; soft_reset_req <= 1'b1;
      end else begin
        if (write_valid && !protocol_error_write) begin
          case (perip_word_addr)
            NPU_BASE + 32'h10: begin
              if (!soft_reset_write) begin
                completion_irq_enable <= control_merged[0];
                error_irq_enable <= control_merged[1];
              end
            end
            NPU_BASE + 32'h20: descriptor_shadow.a_base <= merge_store_lane(descriptor_shadow.a_base, perip_wdata, perip_mask, perip_addr[1:0]);
            NPU_BASE + 32'h24: descriptor_shadow.b_base <= merge_store_lane(descriptor_shadow.b_base, perip_wdata, perip_mask, perip_addr[1:0]);
            NPU_BASE + 32'h28: descriptor_shadow.c_base <= merge_store_lane(descriptor_shadow.c_base, perip_wdata, perip_mask, perip_addr[1:0]);
            NPU_BASE + 32'h2C: {descriptor_shadow.n, descriptor_shadow.m} <= merge_store_lane({descriptor_shadow.n, descriptor_shadow.m}, perip_wdata, perip_mask, perip_addr[1:0]);
            NPU_BASE + 32'h30: {descriptor_shadow.input_int16, descriptor_shadow.k} <= dim_k_flags_merged[16:0];
            NPU_BASE + 32'h34: descriptor_shadow.a_stride <= merge_store_lane(descriptor_shadow.a_stride, perip_wdata, perip_mask, perip_addr[1:0]);
            NPU_BASE + 32'h38: descriptor_shadow.b_stride <= merge_store_lane(descriptor_shadow.b_stride, perip_wdata, perip_mask, perip_addr[1:0]);
            NPU_BASE + 32'h3C: descriptor_shadow.c_stride <= merge_store_lane(descriptor_shadow.c_stride, perip_wdata, perip_mask, perip_addr[1:0]);
            NPU_BASE + 32'h40: begin
              descriptor_shadow.output_fmt <= post_cfg_merged[1:0];
              descriptor_shadow.activation <= post_cfg_merged[3:2];
              descriptor_shadow.rounding <= post_cfg_merged[4]; descriptor_shadow.shift <= post_cfg_merged[10:5];
            end
            NPU_BASE + 32'h44: descriptor_shadow.clamp_min <= merge_store_lane(descriptor_shadow.clamp_min, perip_wdata, perip_mask, perip_addr[1:0]);
            NPU_BASE + 32'h48: descriptor_shadow.clamp_max <= merge_store_lane(descriptor_shadow.clamp_max, perip_wdata, perip_mask, perip_addr[1:0]);
            NPU_BASE + 32'h4C: descriptor_shadow.user_tag <= merge_store_lane(descriptor_shadow.user_tag, perip_wdata, perip_mask, perip_addr[1:0]);
            default: begin end
          endcase
        end
        if (completion_ack_write) completion_pop <= 1'b1;
        if (soft_reset_write) soft_reset_req <= 1'b1;

        if (irq_clear_write) irq_status <= irq_status & ~action_write_word[1:0];
        if (completion_enqueued) irq_status[0] <= 1'b1;
        if (external_error_new || rejection_error_new || protocol_error_new || reset_busy_error_new) irq_status[1] <= 1'b1;
        if (error_clear_write) error_status <= error_status & ~action_write_word[11:0];
        if (external_error_valid) error_status[external_error_index] <= 1'b1;
        if (doorbell_reject) error_status[7] <= 1'b1;
        if (protocol_error_write) error_status[8] <= 1'b1;
        if (reset_busy_error) error_status[9] <= 1'b1;
        if (error_clear_write && action_write_word[7] && !doorbell_reject) begin
          error_tag <= '0; error_tag_valid <= 1'b0;
        end
        if (doorbell_reject) begin
          if (!error_tag_valid) begin error_tag <= descriptor_shadow.user_tag; error_tag_valid <= 1'b1; end
          if (reject_count != 32'hffff_ffff) reject_count <= reject_count + 1'b1;
        end
      end
    end
  end

  assign cmd_push_valid = doorbell_admit;
  assign cmd_push_data = descriptor_shadow;
  assign combined_perip_rdata = hit_q2 ? data_q2 : legacy_perip_rdata;
  assign irq = (completion_irq_enable && irq_status[0]) || (error_irq_enable && irq_status[1]);

  // synthesis translate_off
  always_ff @(posedge clk) if (!rst && write_in_window) begin
    if (soft_reset_write !== (write_valid && !protocol_error_write &&
                              (perip_word_addr == NPU_BASE + 32'h10) &&
                              action_write_word[8]))
      $fatal(1, "NPU200_SOFT_RESET_DECODE_EQ_RED");
  end
  // synthesis translate_on

  generate
    if (!(CMDQ_DEPTH >= 2 && CMDQ_DEPTH <= 128 &&
          (CMDQ_DEPTH & (CMDQ_DEPTH - 1)) == 0)) begin : g_invalid_cmdq_depth
      initial $fatal(1, "npu_mmio_overlay: CMDQ_DEPTH must be a power of two from 2 through 128");
    end
    if (!(COMPQ_DEPTH >= 2 && COMPQ_DEPTH <= 128 &&
          (COMPQ_DEPTH & (COMPQ_DEPTH - 1)) == 0)) begin : g_invalid_compq_depth
      initial $fatal(1, "npu_mmio_overlay: COMPQ_DEPTH must be a power of two from 2 through 128");
    end
  endgenerate
endmodule
